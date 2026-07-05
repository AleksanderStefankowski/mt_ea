#!/usr/bin/env ruby
# Enable algos listed in algos_to_enable; disable all other wired algos.

MQ5_FILE = File.expand_path("aleksik.mq5", __dir__)

### enable the list, disable all other
#  to lecialo i wyszlo niedobrze bo too many stacked at once
# algos_to_enable = <<TEXT
# 117
# 118
# 119
# 120
# 121
# 122
# 123
# 124
# 125
# 126
# 128
# 129
# 130
# 131
# TEXT

# retry all
algos_to_enable = <<TEXT
126
132
123
120
119
138
128
131
TEXT

ENABLED_LINE_RE = /
  g_algos\[AlgoSlotIndexByAlgoId\(MAGIC_ALGO(\d+)\)\]\.enabled\s*=\s*(true|false);
/x

enable_ids =
  algos_to_enable
    .lines
    .map(&:strip)
    .reject(&:empty?)
    .grep(/\A\d+\z/)
    .map(&:to_i)
    .uniq
    .sort

if enable_ids.empty?
  warn "ERROR: algos_to_enable is empty."
  exit 1
end

content = File.read(MQ5_FILE)

found = {}
content.scan(ENABLED_LINE_RE) { |id, val| found[id.to_i] = val }

missing = enable_ids.reject { |id| found.key?(id) }
if missing.any?
  warn "ERROR: no .enabled line for algo(s): #{missing.join(', ')}"
  exit 1
end

enable_set = enable_ids
disable_ids = found.keys.reject { |id| enable_set.include?(id) }.sort

changed = Hash.new { |h, k| h[k] = [] }
skipped = Hash.new { |h, k| h[k] = [] }

updated = content.gsub(ENABLED_LINE_RE) do |match|
  algo_id = $1.to_i
  current = $2
  target = enable_set.include?(algo_id) ? "true" : "false"

  if current == target
    skipped[target] << algo_id
    match
  else
    changed[target] << algo_id
    match.sub(/=\s*(true|false);/, "= #{target};")
  end
end

if changed.values.all?(&:empty?)
  puts "No changes."
  puts "Enable list (#{enable_ids.size}): #{enable_ids.join(', ')}"
  puts "Disable others (#{disable_ids.size}): #{disable_ids.join(', ')}" unless disable_ids.empty?
else
  File.write(MQ5_FILE, updated)
  puts "Enable list (#{enable_ids.size}): #{enable_ids.join(', ')}"
  puts "Disable others (#{disable_ids.size}): #{disable_ids.join(', ')}" unless disable_ids.empty?
  changed["true"]&.then { |ids| puts "Set enabled=true for algo(s): #{ids.sort.join(', ')}" unless ids.empty? }
  changed["false"]&.then { |ids| puts "Set enabled=false for algo(s): #{ids.sort.join(', ')}" unless ids.empty? }
  skipped.each do |target, ids|
    puts "Unchanged (#{ids.sort.join(', ')}) already #{target}" unless ids.empty?
  end
end
