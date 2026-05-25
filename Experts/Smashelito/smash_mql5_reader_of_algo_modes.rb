#!/usr/bin/env ruby
# Reads smashelito.mq5 tune blocks → CSV of per-algo trade modes (neutral/strong/bad/terrible) + triggers.

require "csv"

MQ5_FILE = File.expand_path("smashelito.mq5", __dir__)
OUT_CSV  = File.expand_path("smash_mql5_reader_of_algo_modes_output.csv", __dir__)
src = File.read(MQ5_FILE)

struct_block = src[/struct\s+AlgoPerAlgoTune\s*\{(.*?)\};/m, 1]
TUNE_FIELDS = struct_block.scan(/^\s+\w+\s+(\w+);/m).flatten

MODE_FOR_FIELD = lambda do |field|
  case field
  when /\Aneutral_/ then "neutral"
  when /\Astrong_/ then "strong"
  when /\Abadtrade_/ then "badtrade"
  when /\Aterribletrade_/ then "terribletrade"
  when /\Atelemetry_|trade_telemetry/ then "telemetry"
  when /babysit|stop_trading/ then "day_control"
  else "other"
  end
end

tune_re = /
  g_algos\[AlgoSlotIndexByAlgoId\(MAGIC_ALGO(\d+)\)\]\.tune\.(\w+)\s*=\s*([^;]+);
/x

algo_re = /
  g_algos\[AlgoSlotIndexByAlgoId\(MAGIC_ALGO(\d+)\)\]\.(\w+)\s*=\s*([^;]+);
/x

tune_by_algo = Hash.new { |h, k| h[k] = {} }
meta_by_algo = Hash.new { |h, k| h[k] = {} }

src.scan(tune_re) do |id, field, value|
  tune_by_algo[id.to_i][field] = value.strip.sub(%r{//.*}, "").strip
end

src.scan(algo_re) do |id, field, value|
  next if field == "tune"
  meta_by_algo[id.to_i][field] = value.strip.sub(%r{//.*}, "").strip
end

registry = src[/int\s+g_algoRegistryIds\[\]\s*=\s*\{([^}]+)\}/m, 1]
algo_ids = registry.scan(/MAGIC_ALGO(\d+)/).flatten.map(&:to_i)

def direction(val)
  return "" unless val
  return "short" if val.include?("ALGO_SIDE_SHORT") || val == "true"
  return "long"  if val.include?("ALGO_SIDE_LONG")  || val == "false"
  val
end

# Columns: algo_id, direction, enabled, then each tune field (struct order).
headers = %w[algo_id direction enabled] + TUNE_FIELDS

CSV.open(OUT_CSV, "w") do |csv|
  csv << headers
  algo_ids.each do |id|
    meta = meta_by_algo[id]
    tune = tune_by_algo[id]
    row = [
      id,
      direction(meta["trades_short"]),
      meta["enabled"] || ""
    ]
    TUNE_FIELDS.each { |f| row << (tune[f] || "") }
    csv << row
  end
end

puts "Wrote #{OUT_CSV} (#{algo_ids.size} algos, #{TUNE_FIELDS.size} tune fields)"
puts
puts "Modes covered:"
TUNE_FIELDS.group_by { |f| MODE_FOR_FIELD.call(f) }.sort.each do |mode, fields|
  puts "  #{mode}: #{fields.join(', ')}"
end
