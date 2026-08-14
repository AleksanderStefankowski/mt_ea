#!/usr/bin/env ruby
# frozen_string_literal: true
# Reads wired breakdown/time/level algos from aleksik2.mq5 (+ level_fam.mqh), prints to console.

require "set"
require_relative "../Aleksik/smash_mql5_algo_reader_lib"

MQ5_FILE = File.expand_path("aleksik2.mq5", __dir__)
LEVEL_FAM_FILE = File.expand_path("aleksik2_level_fam.mqh", __dir__)

BD_REGISTRY_MARKERS = %w[//breakdowncreator1start //breakdowncreator1end].freeze
TIME_REGISTRY_MARKERS = %w[//timealgocreator1start //timealgocreator1end].freeze
LEVEL_REGISTRY_MARKERS = %w[//levelalgocreator1start //levelalgocreator1end].freeze

BD_MAIN_FIELDS = %w[
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

TIME_MAIN_FIELDS = %w[
  entry_hour
  entry_minute
  rule_switch_map
  secret_tp_profit_percent_min
  secret_tp_greenguard_pricediff_at_least
  max_trades_per_day
  max_open_positions
  stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
].freeze

TIME_SHARED_FIELDS = %w[
  use_banned_days_QOPEX
  use_banned_days_holidays
  tradeSizePct
  bannedRanges
  tradesDays
  babysit_enabled
  blockPlacementIfFamilyOpenOrPending
  stop_trading_today_if_AllAlgos_losing_trades_count
  stop_trading_today_if_AllAlgos_winning_trades_count
  stop_trading_if_day_has_X_wins_0_losses
  stop_trading_if_day_has_profit_factor_above
].freeze

BD_ASSIGN_RE = /
  g_breakdownAlgos\[BreakdownAlgoSlotIndexByAlgoId\(MAGIC_BREAKDOWN(\d+)\)\]\.(\w+)\s*=\s*([^;]+);
/x

TIME_ASSIGN_RE = /
  g_timeAlgos\[TimeAlgoSlotIndexByAlgoId\(TIME_ALGO_(\d+)\)\]\.(\w+)\s*=\s*([^;]+);
/x

TIME_SHARED_ASSIGN_RE = /
  g_timeAlgoShared\.(\w+)\s*=\s*("[^"]*"|[^;]+);
/x

CONTINUATION_MODE_RE = /\ABREAKDOWN_STREAK_CONTINUATION_(.+)\z/
ENABLED_ALGO_ID_SAMPLE_LIMIT = 5

def strip_mq5_value(raw)
  val = raw.strip.sub(%r{//.*}, "").strip
  if (m = val.match(/\A"(.*)"\z/))
    return m[1]
  end

  val
end

def enabled?(raw)
  strip_mq5_value(raw.to_s).casecmp("true").zero?
end

def registry_algo_ids(src, markers, id_re)
  start_marker, end_marker = markers
  marker_line_re = ->(marker) { /^\s*#{Regexp.escape(marker)}\s*$/ }

  lines = src.lines
  start_idx = lines.index { |line| line.match?(marker_line_re.call(start_marker)) }
  end_idx = lines.index { |line| line.match?(marker_line_re.call(end_marker)) }
  return [] unless start_idx && end_idx && end_idx > start_idx

  lines[(start_idx + 1)...end_idx].join.scan(id_re).flatten.map(&:to_i).uniq.sort
end

def numeric_sort_key(value)
  text = value.to_s.strip
  return [0, text.to_f, text] if text.match?(/\A-?\d+(?:\.\d+)?\z/)

  [1, text]
end

def print_grouped_counts(label, enabled_rows, field)
  grouped = enabled_rows.group_by { |row| row[field].to_s }
  grouped.transform_values!(&:size)

  puts label
  if grouped.empty?
    puts "  (none)"
  else
    grouped.sort_by { |value, _| numeric_sort_key(value) }.each do |value, count|
      display = value.empty? ? "(unknown)" : value
      puts "  #{display}: #{count}"
    end
  end
end

def print_enabled_algo_ids(enabled_rows, limit = ENABLED_ALGO_ID_SAMPLE_LIMIT)
  ids = enabled_rows.map { |row| row[:algo_id] }.sort
  sample = ids.first(limit)

  puts "enabled algo ids (up to #{limit}):"
  if sample.empty?
    puts "  (none)"
  else
    puts "  #{sample.join(', ')}"
    remaining = ids.size - sample.size
    puts "  ... +#{remaining} more" if remaining.positive?
  end
end

def print_family_counts(label, rows)
  enabled_rows = rows.select { |row| enabled?(row[:enabled]) }
  puts "--- #{label} ---"
  puts "count all:      #{rows.size}"
  puts "count enabled:  #{enabled_rows.size}"
  puts "count disabled: #{rows.size - enabled_rows.size}"
  print_enabled_algo_ids(enabled_rows)
  enabled_rows
end

def continuation_mode_label(raw)
  val = strip_mq5_value(raw)
  if (m = val.match(CONTINUATION_MODE_RE))
    m[1]
  else
    val
  end
end

def breakdown_params_by_algo_from_src(src)
  params = Hash.new { |h, k| h[k] = {} }
  src.scan(BD_ASSIGN_RE) do |id, field, value|
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

def breakdown_rules_by_algo_from_src(src, params_by_algo)
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

def breakdown_quant_rules(rules)
  return [] if rules.nil? || rules.empty?

  rules.select do |rule|
    name = rule[/\A([A-Za-z_]+)/, 1]
    SmashMql5AlgoReader::QUANT_RULE_PREFIXES.any? { |pfx| name&.start_with?(pfx) } ||
      rule.start_with?("RULE_LEVEL_")
  end
end

def breakdown_field_value(params, field)
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

def build_breakdown_rows(src)
  params_by_algo = breakdown_params_by_algo_from_src(src)
  algo_ids = registry_algo_ids(src, BD_REGISTRY_MARKERS, /MAGIC_BREAKDOWN(\d+)/)
  rules_by_algo = breakdown_rules_by_algo_from_src(src, params_by_algo)

  algo_ids.map do |id|
    p = params_by_algo[id] || {}
    rules = rules_by_algo[id] || []
    qrules = breakdown_quant_rules(rules)

    row = {
      algo_id: id,
      enabled: p["enabled"] || "",
      quant_rules: rules_cell(qrules),
      rules: rules_cell(rules)
    }
    BD_MAIN_FIELDS.each { |f| row[f.to_sym] = breakdown_field_value(p, f) }
    row
  end
end

def print_breakdown_summary(rows)
  enabled_rows = print_family_counts("breakdown", rows)

  enabled_by_mode = enabled_rows.group_by { |row| row[:breakdown_streak_continuation_mode].to_s }
  enabled_by_mode.transform_values!(&:size)

  secret_tp_zero_count = enabled_rows.count { |row| row[:secret_tp_range_percent].to_s.strip.to_f.zero? }
  secret_tp_nonzero_count = enabled_rows.size - secret_tp_zero_count

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

def time_params_by_algo_from_src(src)
  params = Hash.new { |h, k| h[k] = {} }
  src.scan(TIME_ASSIGN_RE) do |id, field, value|
    params[id.to_i][field] = strip_mq5_value(value)
  end
  params
end

def time_shared_params_from_src(src)
  shared = {}
  src.scan(TIME_SHARED_ASSIGN_RE) do |field, value|
    shared[field] = strip_mq5_value(value)
  end
  shared
end

def build_time_rows(src)
  params_by_algo = time_params_by_algo_from_src(src)
  shared_params = time_shared_params_from_src(src)
  algo_ids = registry_algo_ids(src, TIME_REGISTRY_MARKERS, /TIME_ALGO_(\d+)/)

  algo_ids.map do |id|
    p = params_by_algo[id] || {}
    row = {
      algo_id: id,
      enabled: p["enabled"] || ""
    }
    TIME_SHARED_FIELDS.each { |f| row[:"shared_#{f}"] = shared_params[f].to_s }
    TIME_MAIN_FIELDS.each { |f| row[f.to_sym] = p[f].to_s }
    row
  end
end

def time_entry_time_label(row)
  hour = row[:entry_hour].to_s
  minute = row[:entry_minute].to_s.rjust(2, "0")
  "#{hour}:#{minute}"
end

def print_time_summary(rows)
  enabled_rows = print_family_counts("time", rows)

  enabled_by_entry = enabled_rows.group_by { |row| time_entry_time_label(row) }
  enabled_by_entry.transform_values!(&:size)

  puts "enabled by entry time:"
  if enabled_by_entry.empty?
    puts "  (none)"
  else
    enabled_by_entry.sort_by { |entry, _| entry }.each do |entry, count|
      puts "  #{entry}: #{count}"
    end
  end
  print_grouped_counts("enabled by rule_switch_map:", enabled_rows, :rule_switch_map)
  print_grouped_counts("enabled by secret_tp_profit_percent_min:", enabled_rows, :secret_tp_profit_percent_min)
  print_grouped_counts("enabled by max_open_positions:", enabled_rows, :max_open_positions)
  puts
end

def level_scope_label(weekly, daily)
  if weekly && daily
    "both"
  elsif weekly
    "weekly"
  elsif daily
    "daily"
  else
    "(none)"
  end
end

def parse_level_rows(level_fam_src)
  rows = {}
  current_id = nil

  level_fam_src.each_line do |line|
    if (match = line.match(/LevelAlgoSlotIndexByAlgoId\(MAGIC_LEVEL(\d+)\)\]\.enabled = (true|false)/))
      current_id = match[1].to_i
      rows[current_id] = {
        algo_id: current_id,
        enabled: match[2],
        weekly: false,
        daily: false,
        offset_positive: nil,
        offset_percentage: nil,
        secret_tp_profit_percent_min: nil,
        tags: []
      }
      next
    end

    next unless current_id
    next unless line.include?("MAGIC_LEVEL#{current_id}")

    row = rows[current_id]
    if (match = line.match(/trades_weekly = (true|false)/))
      row[:weekly] = enabled?(match[1])
    elsif (match = line.match(/trades_daily = (true|false)/))
      row[:daily] = enabled?(match[1])
    elsif (match = line.match(/offset_positive = (true|false)/))
      row[:offset_positive] = match[1]
    elsif (match = line.match(/offset_percentage = ([0-9.]+)/))
      row[:offset_percentage] = match[1]
    elsif (match = line.match(/secret_tp_profit_percent_min = ([0-9.]+)/))
      row[:secret_tp_profit_percent_min] = match[1]
    elsif (match = line.match(/trades_tags\[\d+\] = "([^"]+)"/))
      row[:tags] << match[1]
    end
  end

  rows.values.sort_by { |row| row[:algo_id] }.each do |row|
    row[:level_scope] = level_scope_label(row[:weekly], row[:daily])
    row[:tags] = row[:tags].join(", ")
  end
end

def print_level_summary(rows, registry_ids)
  wired_ids = registry_ids.to_set
  wired_rows = rows.select { |row| wired_ids.include?(row[:algo_id]) }
  missing_ids = wired_ids - wired_rows.map { |row| row[:algo_id] }.to_set
  extra_ids = wired_rows.map { |row| row[:algo_id] }.to_set - wired_ids

  enabled_rows = print_family_counts("level", wired_rows)

  unless missing_ids.empty?
    puts "missing config in #{File.basename(LEVEL_FAM_FILE)}: #{missing_ids.to_a.sort.join(', ')}"
  end
  unless extra_ids.empty?
    puts "extra config not in registry: #{extra_ids.to_a.sort.join(', ')}"
  end

  print_grouped_counts("enabled by level_scope:", enabled_rows, :level_scope)
  print_grouped_counts("enabled by offset_positive:", enabled_rows, :offset_positive)
  print_grouped_counts("enabled by secret_tp_profit_percent_min:", enabled_rows, :secret_tp_profit_percent_min)
  puts
end

def print_overall_summary(breakdown_rows, time_rows, level_rows)
  all_rows = breakdown_rows + time_rows + level_rows
  enabled_count = all_rows.count { |row| enabled?(row[:enabled]) }

  puts "--- all ---"
  puts "count all:      #{all_rows.size}"
  puts "count enabled:  #{enabled_count}"
  puts "count disabled: #{all_rows.size - enabled_count}"
  puts "by family:"
  puts "  breakdown: #{breakdown_rows.size} (#{breakdown_rows.count { |row| enabled?(row[:enabled]) }} enabled)"
  puts "  time:      #{time_rows.size} (#{time_rows.count { |row| enabled?(row[:enabled]) }} enabled)"
  puts "  level:     #{level_rows.size} (#{level_rows.count { |row| enabled?(row[:enabled]) }} enabled)"
  puts
end

unless File.file?(MQ5_FILE)
  warn "ERROR: mq5 file not found: #{MQ5_FILE}"
  exit 1
end

unless File.file?(LEVEL_FAM_FILE)
  warn "ERROR: level fam file not found: #{LEVEL_FAM_FILE}"
  exit 1
end

mq5_src = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
level_fam_src = File.read(LEVEL_FAM_FILE, encoding: "bom|utf-8")

breakdown_rows = build_breakdown_rows(mq5_src)
time_rows = build_time_rows(mq5_src)
level_registry_ids = registry_algo_ids(mq5_src, LEVEL_REGISTRY_MARKERS, /MAGIC_LEVEL(\d+)/)
level_rows = parse_level_rows(level_fam_src).select { |row| level_registry_ids.include?(row[:algo_id]) }

puts "=== breakdown ==="
print_breakdown_summary(breakdown_rows)

puts "=== time ==="
print_time_summary(time_rows)

puts "=== level ==="
print_level_summary(level_rows, level_registry_ids)

puts "=== all ==="
print_overall_summary(breakdown_rows, time_rows, level_rows)

warn "RAN OK"
