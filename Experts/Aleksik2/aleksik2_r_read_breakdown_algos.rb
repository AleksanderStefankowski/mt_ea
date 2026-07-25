#!/usr/bin/env ruby
# frozen_string_literal: true
# Reads wired breakdown algos from aleksik2.mq5, prints them, and writes CSV.

require "csv"
require_relative "../Aleksik/smash_mql5_algo_reader_lib"

MQ5_FILE = File.expand_path("aleksik2.mq5", __dir__)
OUT_CSV  = File.expand_path("aleksik2_r_read_breakdown_algos_csv.csv", __dir__)

MAIN_FIELDS = %w[
  stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
  expiry_minutes
  breakdown_streak_continuation_mode
  min_breakdown_sequence_len
  max_breakdown_sequence_len
  bd_start_min_breakdown_percent
  min_breakdown_total_percent
  after_bd_need_x_15greenc
  entry_max_minutes_after_bdend
  forget_about_latest_breakdown_after_x_15m_candles
  entryrange_range_percentspot
  secret_tp_range_percent
  tp_notsecret_range_percent
  closetrade_after_some_time
  closetrade_after_some_time_butOnlyIfProfit
  closetrade_after_some_time_but_ProfitPercent_Needed
  closetrade_after_x_minutes_from_breakdown
  max_open_positions
].freeze

ASSIGN_RE = /
  g_breakdownAlgos\[BreakdownAlgoSlotIndexByAlgoId\(MAGIC_BREAKDOWN(\d+)\)\]\.(\w+)\s*=\s*([^;]+);
/x

CONTINUATION_MODE_RE = /\ABREAKDOWN_STREAK_CONTINUATION_(.+)\z/

def strip_mq5_value(raw)
  raw.strip.sub(%r{//.*}, "").strip
end

def continuation_mode_label(raw)
  val = strip_mq5_value(raw)
  if (m = val.match(CONTINUATION_MODE_RE))
    m[1]
  else
    val
  end
end

def registry_algo_ids(src)
  block = src[/int\s+g_breakdownRegistryIds\[\]\s*=\s*\{([^}]+)\}/m, 1]
  return [] unless block

  block.scan(/MAGIC_BREAKDOWN(\d+)/).flatten.map(&:to_i)
end

def params_by_algo_from_src(src)
  params = Hash.new { |h, k| h[k] = {} }
  src.scan(ASSIGN_RE) do |id, field, value|
    params[id.to_i][field] = strip_mq5_value(value)
  end
  params
end

def parse_breakdown_rule_line(line, params)
  line = line.sub(%r{//.*}, "").strip
  return nil if line.empty?

  if (m = line.match(/BreakdownRuleChainAdd\(slotIdx,\s*(RULE_\w+)(?:,\s*(.+))?\)/))
    rule = m[1]
    if m[2]
      args = m[2].split(",").map { |a| SmashMql5AlgoReader.resolve(a, params) }.join(", ")
      return "#{rule}(#{args})"
    end
    return rule
  end

  SmashMql5AlgoReader.parse_rule_line(line, params)
end

def rules_by_algo_from_src(src, params_by_algo)
  rule_switch = src[/void\s+BreakdownRebuildRuleChainForSlot\b.*?switch\s*\(\s*algoId\s*\)\s*\{(.*?)\n\s*default:/m, 1]
  rules_by_algo = {}
  return rules_by_algo unless rule_switch

  pending_ids = []
  body_lines = []

  rule_switch.each_line do |line|
    stripped = line.sub(%r{//.*}, "").strip
    if (m = stripped.match(/\Acase\s+MAGIC_BREAKDOWN(\d+):\z/))
      pending_ids << m[1].to_i
    elsif stripped == "break;"
      pending_ids.each do |id|
        rules_by_algo[id] = body_lines.filter_map { |ln| parse_breakdown_rule_line(ln, params_by_algo[id]) }
      end
      pending_ids = []
      body_lines = []
    elsif !stripped.empty? && !pending_ids.empty?
      body_lines << line
    end
  end

  rules_by_algo
end

def quant_rules(rules)
  return [] if rules.nil? || rules.empty?

  rules.select do |rule|
    name = rule[/\A([A-Za-z_]+)/, 1]
    SmashMql5AlgoReader::QUANT_RULE_PREFIXES.any? { |pfx| name&.start_with?(pfx) } ||
      rule.start_with?("RULE_LEVEL_")
  end
end

def field_value(params, field)
  return "" unless params[field]

  if field == "breakdown_streak_continuation_mode"
    continuation_mode_label(params[field])
  else
    params[field]
  end
end

def rules_cell(rules)
  return "" if rules.nil? || rules.empty?

  rules.join(" | ")
end

def enabled?(raw)
  strip_mq5_value(raw.to_s).casecmp("true").zero?
end

def secret_tp_zero?(row)
  row[:secret_tp_range_percent].to_s.strip.to_f.zero?
end

def print_summary(rows)
  all_count = rows.size
  enabled_rows = rows.select { |row| enabled?(row[:enabled]) }
  disabled_count = all_count - enabled_rows.size

  enabled_by_mode = enabled_rows.group_by { |row| row[:breakdown_streak_continuation_mode].to_s }
  enabled_by_mode.transform_values!(&:size)

  secret_tp_zero_count = enabled_rows.count { |row| secret_tp_zero?(row) }
  secret_tp_nonzero_count = enabled_rows.size - secret_tp_zero_count

  puts "--- summary ---"
  puts "count all:      #{all_count}"
  puts "count enabled:  #{enabled_rows.size}"
  puts "count disabled: #{disabled_count}"
  puts "enabled by secret_tp_range_percent:"
  puts "  0: #{secret_tp_zero_count}"
  puts "  non-zero: #{secret_tp_nonzero_count}"
  puts "enabled by breakdown_streak_continuation_mode:"
  if enabled_by_mode.empty?
    puts "  (none)"
  else
    enabled_by_mode.sort_by { |mode, _| mode }.each do |mode, count|
      label = mode.empty? ? "(unknown)" : mode
      puts "  #{label}: #{count}"
    end
  end
  puts
end

src = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
params_by_algo = params_by_algo_from_src(src)
algo_ids = registry_algo_ids(src)
rules_by_algo = rules_by_algo_from_src(src, params_by_algo)

rows = algo_ids.map do |id|
  p = params_by_algo[id] || {}
  rules = rules_by_algo[id] || []
  qrules = quant_rules(rules)

  row = {
    algo_id: id,
    enabled: p["enabled"] || "",
    quant_rules: rules_cell(qrules),
    rules: rules_cell(rules)
  }
  MAIN_FIELDS.each { |f| row[f.to_sym] = field_value(p, f) }
  row
end

CSV.open(OUT_CSV, "w") do |csv|
  csv << ["algo_id", "enabled", "quant_rules", "rules", *MAIN_FIELDS]
  rows.each do |row|
    csv << [
      row[:algo_id],
      row[:enabled],
      row[:quant_rules],
      row[:rules],
      *MAIN_FIELDS.map { |f| row[f.to_sym] }
    ]
  end
end

puts OUT_CSV
print_summary(rows)
