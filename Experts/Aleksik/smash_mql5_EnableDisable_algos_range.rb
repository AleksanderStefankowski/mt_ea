#!/usr/bin/env ruby
# Sets g_algos[...].enabled for each MAGIC_ALGO id in algo_range_start..algo_range_end.

MQ5_FILE = File.expand_path("aleksik.mq5", __dir__)
set_enabled_to = false # true or false. Skips an algo if it is already in that state.
# algo_range_start = 10
# algo_range_end = 15

algo_range_start = 39
algo_range_end = 45

# algo_range_start = 17
# algo_range_end = 19
# 36




ENABLED_LINE_RE = /
  g_algos\[AlgoSlotIndexByAlgoId\(MAGIC_ALGO(\d+)\)\]\.enabled\s*=\s*(true|false);
/x

target = set_enabled_to ? "true" : "false"
algo_ids = (algo_range_start..algo_range_end).to_a

content = File.read(MQ5_FILE)

found = {}
content.scan(ENABLED_LINE_RE) { |id, val| found[id.to_i] = val }

missing = algo_ids.reject { |id| found.key?(id) }
if missing.any?
  warn "ERROR: no .enabled line for algo(s): #{missing.join(', ')}"
  exit 1
end

changed = []
skipped = []

updated = content.gsub(ENABLED_LINE_RE) do |match|
  algo_id = $1.to_i
  current = $2

  if !algo_ids.include?(algo_id)
    match
  elsif current == target
    skipped << algo_id
    match
  else
    changed << algo_id
    match.sub(/=\s*(true|false);/, "= #{target};")
  end
end

if changed.empty?
  puts "No changes (#{skipped.sort.join(', ')} already #{target})."
else
  File.write(MQ5_FILE, updated)
  puts "Set enabled=#{target} for algo(s): #{changed.sort.join(', ')}"
  puts "Unchanged (#{skipped.sort.join(', ')})" unless skipped.empty?
end
