#!/usr/bin/env ruby
# Enables/disables algos by quanted vs unquanted ruleset classification.

require_relative "smash_mql5_algo_reader_lib"

MQ5_FILE = File.expand_path("aleksik.mq5", __dir__)

enable_all_unquanted = true
disable_all_unquanted = false
enable_all_quanted = false
disable_all_quanted = false

ENABLED_LINE_RE = /
  g_algos\[AlgoSlotIndexByAlgoId\(MAGIC_ALGO(\d+)\)\]\.enabled\s*=\s*(true|false);
/x

src = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
params_by_algo = SmashMql5AlgoReader.params_by_algo_from_src(src)
algo_ids = SmashMql5AlgoReader.registry_algo_ids(src)
rules_by_algo = SmashMql5AlgoReader.rules_by_algo_from_src(src, params_by_algo)

targets = {}
algo_ids.each do |id|
  quanted = SmashMql5AlgoReader.contains_quant_rule?(rules_by_algo[id])
  target =
    if quanted
      disable_all_quanted ? "false" : (enable_all_quanted ? "true" : nil)
    else
      disable_all_unquanted ? "false" : (enable_all_unquanted ? "true" : nil)
    end
  targets[id] = target if target
end

if targets.empty?
  puts "No changes (all enable/disable flags are false)."
  exit 0
end

content = src

found = {}
content.scan(ENABLED_LINE_RE) { |id, val| found[id.to_i] = val }

missing = targets.keys.reject { |id| found.key?(id) }
if missing.any?
  warn "ERROR: no .enabled line for algo(s): #{missing.sort.join(', ')}"
  exit 1
end

changed = Hash.new { |h, k| h[k] = [] }
skipped = Hash.new { |h, k| h[k] = [] }

updated = content.gsub(ENABLED_LINE_RE) do |match|
  algo_id = $1.to_i
  current = $2
  target = targets[algo_id]

  if target.nil?
    match
  elsif current == target
    skipped[target] << algo_id
    match
  else
    changed[target] << algo_id
    match.sub(/=\s*(true|false);/, "= #{target};")
  end
end

if changed.values.all?(&:empty?)
  skipped.each do |target, ids|
    puts "No changes (#{ids.sort.join(', ')} already #{target})."
  end
else
  File.write(MQ5_FILE, updated)
  changed.each do |target, ids|
    puts "Set enabled=#{target} for algo(s): #{ids.sort.join(', ')}"
  end
  skipped.each do |target, ids|
    puts "Unchanged (#{ids.sort.join(', ')}) already #{target}" unless ids.empty?
  end
end
