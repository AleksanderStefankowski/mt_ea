#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'alert_done_common'

# Head-to-head performance comparison for time algos.
# Each section pairs algos whose config matches on every field except one:
#   entry_time, secret_tp_profit_percent_min, rule_switch_map, max_open_positions
#
# Uses all trades (no flash-crash split). Console output only.

require 'set'
require_relative 'compare_variable_analysis_lib'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_time_algos_csv.csv', SCRIPT_DIR)
PERF_PATH = File.join(SCRIPT_DIR, 'analyze_time_algos_performance_output.csv')

COMPARE_FIELD_ENTRY_TIME = 'entry_time'

COMPARE_SECTIONS = [
  {
    variable: COMPARE_FIELD_ENTRY_TIME,
    title: 'compare entry_time (all other config equal)',
    signature_exclude_variables: %w[entry_hour entry_minute],
    sort_key: :entry_time_sort_key
  },
  {
    variable: 'secret_tp_profit_percent_min',
    title: 'compare secret_tp_profit_percent_min (all other config equal)',
    signature_exclude_variables: []
  },
  {
    variable: 'rule_switch_map',
    title: 'compare rule_switch_map (all other config equal)',
    signature_exclude_variables: []
  },
  {
    variable: 'max_open_positions',
    title: 'compare max_open_positions (all other config equal)',
    signature_exclude_variables: []
  }
].freeze

DISPLAY_CONFIG_FIELDS = %w[
  entry_time
  rule_switch_map
  secret_tp_profit_percent_min
  secret_tp_greenguard_pricediff_at_least
  max_open_positions
  max_trades_per_day
  stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
].freeze

COMPARE_METRICS = [
  ['perf_percentSum_w_roll', 'percentSum_w_roll', 2],
  ['perf_profitSumVSexposure', 'profitSumVSexposure', Lib::TIMEVSPROFIT_DECIMALS],
  ['perf_avgDurationHours', 'avgDurationHours', 2]
].freeze

Lib = CompareVariableAnalysisLib

class ConfigRow
  attr_reader :data

  def initialize(data)
    @data = data.transform_keys(&:to_s)
  end

  def [](key)
    @data[key.to_s]
  end

  def headers
    @data.keys
  end
end

def format_entry_time(hour, minute)
  "#{hour.to_i}:#{minute.to_i.to_s.rjust(2, '0')}"
end

def entry_time_sort_key(value)
  text = value.to_s
  hour, minute =
    if (match = text.match(/\A(\d+):(\d+)\z/))
      [match[1].to_i, match[2].to_i]
    else
      [99, 99]
    end

  [hour, minute, text]
end

def build_config_row(csv_row)
  data = csv_row.to_h
  data[COMPARE_FIELD_ENTRY_TIME] =
    format_entry_time(data['entry_hour'], data['entry_minute'])
  ConfigRow.new(data)
end

def load_matched_rows
  config_by_algo_id =
    Lib.read_csv(CONFIG_PATH).each_with_object({}) do |row, memo|
      algo_id = row['algo_id'].to_s.strip
      next if algo_id.empty?

      memo[algo_id] = build_config_row(row)
    end

  perf_rows =
    Lib.read_csv(PERF_PATH).select do |row|
      row['algoID'].to_s.strip != ''
    end

  matched_rows = []
  missing_config = []

  perf_rows.each do |perf_row|
    algo_id = perf_row['algoID'].to_s.strip
    config_row = config_by_algo_id[algo_id]
    if config_row.nil?
      missing_config << algo_id
      next
    end

    matched_rows << { algo_id: algo_id, config: config_row, perf: perf_row }
  end

  unless missing_config.empty?
    warn "WARNING: #{missing_config.size} performance algos missing from config: #{missing_config.sort.join(', ')}"
  end

  [matched_rows, perf_rows.size]
end

def format_config_summary(config)
  DISPLAY_CONFIG_FIELDS
    .map do |field|
      value = config[field]
      next if value.nil? || value.to_s.strip.empty?

      "#{field}=#{value}"
    end
    .compact
    .join(', ')
end

def unpaired_entries(matched_rows, run_result)
  matched_rows
    .reject { |entry| run_result[:paired_algo_ids].include?(entry[:algo_id]) }
    .sort_by { |entry| entry[:algo_id].to_i }
end

def metric_values(entry)
  COMPARE_METRICS.to_h { |_, field, _| [field, Lib.parse_float(entry[:perf][field])] }
end

def percent_change(base, value)
  return nil if base.nil? || value.nil?
  return nil if base.zero?

  100.0 * (value - base) / base.abs
end

def format_metric_change_part(label, pct, avg: false)
  prefix = avg ? 'avg ' : ''
  return "#{prefix}#{label} n/a" if pct.nil?
  return "#{prefix}#{label} same" if pct.abs < 0.05

  direction = pct.positive? ? 'higher' : 'lower'
  "#{prefix}#{format('%.1f', pct.abs)}% #{direction} #{label}"
end

def format_right_vs_left_pct_line(compare_variable, right_value, left_metrics, right_metrics, left_value: nil, avg: false)
  metric_parts =
    COMPARE_METRICS.map do |label, field, _decimals|
      format_metric_change_part(label, percent_change(left_metrics[field], right_metrics[field]), avg: avg)
    end

  value_part =
    if avg && !left_value.nil?
      "#{compare_variable} #{right_value} vs #{left_value}"
    else
      "#{compare_variable} #{right_value}"
    end

  "right has #{value_part} has #{metric_parts.join(' and ')}"
end

def format_side_summary(entry, compare_variable)
  perf_parts =
    COMPARE_METRICS.map do |label, field, decimals|
      value = Lib.format_float(Lib.parse_float(entry[:perf][field]), decimals)
      "#{label} #{value}"
    end

  "#{compare_variable}=#{entry[:config][compare_variable]}, algo #{entry[:algo_id]}   #{perf_parts.join(' ')}"
end

def combined_percent_sum(pair)
  left = Lib.parse_float(pair[:left][:perf]['percentSum_w_roll']) || 0.0
  right = Lib.parse_float(pair[:right][:perf]['percentSum_w_roll']) || 0.0
  left + right
end

def sorted_pairs(pairs, _compare_variable = nil, sort_key: nil)
  pairs.sort_by do |pair|
    [
      -combined_percent_sum(pair),
      pair[:group_id],
      pair[:pair_id]
    ]
  end
end

def compare_value_sort_key(value, sort_key: nil)
  return sort_key.call(value) if sort_key

  text = value.to_s.strip
  if text.match?(/\A-?\d+(?:\.\d+)?\z/)
    return [0, Float(text), text]
  end

  Lib.compare_variable_sort_key(text)
rescue ArgumentError
  Lib.compare_variable_sort_key(value.to_s)
end

def ordered_value_pair(left_val, right_val, sort_key: nil)
  [left_val, right_val].sort_by { |value| compare_value_sort_key(value, sort_key: sort_key) }
end

def averages_by_compare_value(pairs, compare_variable)
  entries_by_value = Hash.new { |hash, key| hash[key] = [] }
  seen_by_value = Hash.new { |hash, key| hash[key] = Set.new }

  pairs.each do |pair|
    [pair[:left], pair[:right]].each do |entry|
      value = entry[:config][compare_variable].to_s
      next if seen_by_value[value].include?(entry[:algo_id])

      seen_by_value[value] << entry[:algo_id]
      entries_by_value[value] << entry
    end
  end

  entries_by_value.transform_values do |entries|
    COMPARE_METRICS.to_h do |_, field, _|
      [field, Lib.average(entries.map { |entry| Lib.parse_float(entry[:perf][field]) })]
    end
  end
end

def compared_value_pairs(pairs, compare_variable, sort_key: nil)
  pairs.each_with_object(Set.new) do |pair, memo|
    left_val = pair[:left][:config][compare_variable].to_s
    right_val = pair[:right][:config][compare_variable].to_s
    next if left_val == right_val

    memo << ordered_value_pair(left_val, right_val, sort_key: sort_key)
  end
end

def print_section_summaries(pairs, compare_variable, sort_key: nil)
  return if pairs.empty?

  paired_entries = Lib.paired_entries_from_pairs(pairs)

  puts '--- by compare value (paired algos, per-algo averages) ---'
  Lib.compare_value_group_table_lines(compare_variable, paired_entries, sort_key: sort_key).each do |line|
    puts "  #{line}"
  end
  puts

  puts '--- profitSumVSexposure head-to-head (paired duels) ---'
  Lib.variable_pair_stats_lines(
    'perf_profitSumVSexposure',
    compare_variable,
    Lib.build_variable_pair_stats(pairs, compare_variable, 'profitSumVSexposure'),
    paired_entries,
    'profitSumVSexposure',
    pairs: pairs,
    sort_key: sort_key,
    show_avg_on_win_lines: true,
    show_avg_comparison: true,
    show_best_algo_duel: false
  ).each { |line| puts "  #{line}" }
  puts
end

def print_pair_comparisons(pairs, compare_variable, sort_key: nil)
  if pairs.empty?
    puts '(no pairs)'
    return
  end

  sorted_pairs(pairs, compare_variable, sort_key: sort_key).each do |pair|
    left = pair[:left]
    right = pair[:right]
    right_value = right[:config][compare_variable].to_s

    puts "--- pair #{pair[:group_id]}.#{pair[:pair_id]} ---"
    puts "  left:  #{format_side_summary(left, compare_variable)}"
    puts "  right: #{format_side_summary(right, compare_variable)}"
    puts "  #{format_right_vs_left_pct_line(
      compare_variable,
      right_value,
      metric_values(left),
      metric_values(right)
    )}"
    puts
  end

  averages = averages_by_compare_value(pairs, compare_variable)
  value_pairs =
    compared_value_pairs(pairs, compare_variable, sort_key: sort_key).sort_by do |left_val, right_val|
      [
        compare_value_sort_key(left_val, sort_key: sort_key),
        compare_value_sort_key(right_val, sort_key: sort_key)
      ]
    end

  if value_pairs.empty?
    print_section_summaries(pairs, compare_variable, sort_key: sort_key)
    return
  end

  puts '--- section avg ---'
  value_pairs.each do |left_val, right_val|
    puts "  #{format_right_vs_left_pct_line(
      compare_variable,
      right_val,
      averages[left_val],
      averages[right_val],
      left_value: left_val,
      avg: true
    )}"
  end
  puts

  print_section_summaries(pairs, compare_variable, sort_key: sort_key)
end

def print_comparison_section(title, matched_rows, compare_variable, signature_exclude_variables: [], sort_key: nil)
  puts '=' * 72
  puts title
  puts '=' * 72

  if matched_rows.size < 2
    puts "algos: #{matched_rows.size} (need at least 2 for head-to-head comparison)"
    puts
    return unpaired_entries(matched_rows, { paired_algo_ids: Set.new })
  end

  run_result =
    Lib.build_variable_compare_run(
      matched_rows,
      compare_variable,
      signature_exclude_variables: signature_exclude_variables
    )
  compared_count = run_result[:paired_algo_ids].size
  unpaired = unpaired_entries(matched_rows, run_result)

  puts "algos: #{matched_rows.size}"
  puts "algos in head-to-head pairs: #{compared_count}"
  puts "algos without a pair: #{unpaired.size}"
  puts "groups found: #{run_result[:group_count]}"
  puts "pairs found: #{run_result[:pair_count]}"
  puts

  print_pair_comparisons(run_result[:pairs], compare_variable, sort_key: sort_key)

  unpaired
end

def print_unpaired_configs(unpaired_by_section)
  puts '=' * 72
  puts 'UNPAIRED CONFIGS (no head-to-head pair found)'
  puts '=' * 72
  puts

  any_unpaired = false

  COMPARE_SECTIONS.each do |section|
    unpaired = unpaired_by_section[section[:variable]] || []
    puts "--- #{section[:title]} ---"
    if unpaired.empty?
      puts '(none)'
    else
      any_unpaired = true
      unpaired.each do |entry|
        puts "  algo #{entry[:algo_id]}: #{format_config_summary(entry[:config])}"
      end
    end
    puts
  end

  puts '(all comparisons had pairs for every algo)' unless any_unpaired
end

unless File.file?(CONFIG_PATH)
  warn "ERROR: config file not found: #{CONFIG_PATH}"
  exit 1
end

unless File.file?(PERF_PATH)
  warn "ERROR: performance file not found: #{PERF_PATH}"
  exit 1
end

matched_rows, perf_row_count = load_matched_rows
if matched_rows.empty?
  warn 'ERROR: no matched time algo rows.'
  exit 1
end

puts "time algo type performance (all trades)"
puts "performance file: #{PERF_PATH}"
puts "config file: #{CONFIG_PATH}"
puts "algos in analyze_time_algos_performance_output: #{perf_row_count}"
puts "matched config algos: #{matched_rows.size}"
puts "grouping rule: all config fields equal except the compared variable"
puts

unpaired_by_section = {}

COMPARE_SECTIONS.each do |section|
  sort_key =
    if section[:sort_key] == :entry_time_sort_key
      method(:entry_time_sort_key)
    end

  unpaired_by_section[section[:variable]] =
    print_comparison_section(
      section[:title].upcase,
      matched_rows,
      section[:variable],
      signature_exclude_variables: section[:signature_exclude_variables],
      sort_key: sort_key
    )
end

print_unpaired_configs(unpaired_by_section)

play_alert_done! if __FILE__ == $PROGRAM_NAME
