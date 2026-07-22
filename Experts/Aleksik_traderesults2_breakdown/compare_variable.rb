#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'set'
require_relative 'compare_variable_analysis_lib'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR)
PERF_PATH = File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_output.csv')

# Change this to compare algos that differ only in another config field.
# Supported COMPARE_VARIABLE values (any column in aleksik2_r_read_breakdown_algos_csv.csv except algo_id):
#   enabled
#   quant_rules
#   rules
#   stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
#   expiry_minutes
#   breakdown_streak_continuation_mode
#   min_breakdown_sequence_len
#   max_breakdown_sequence_len
#   bd_start_min_breakdown_percent
#   min_breakdown_total_percent
#   after_bd_need_x_15greenc
#   entry_max_minutes_after_bdend
#   forget_about_latest_breakdown_after_x_15m_candles
#   entryrange_range_percentspot
#   secret_tp_range_percent
#   tp_notsecret_range_percent
#   closetrade_after_some_time
#   closetrade_after_some_time_butOnlyIfProfit
#   closetrade_after_some_time_but_ProfitPercent_Needed
#   closetrade_after_x_minutes_from_breakdown
#   max_open_positions
COMPARE_VARIABLE = 'forget_about_latest_breakdown_after_x_15m_candles'

CLOSETRADE_CONFIG_COLUMNS = %w[
  closetrade_after_some_time
  closetrade_after_some_time_butOnlyIfProfit
  closetrade_after_some_time_but_ProfitPercent_Needed
  closetrade_after_x_minutes_from_breakdown
].freeze

OUTPUT_PATH = File.join(
  SCRIPT_DIR,
  "compare_variable_#{COMPARE_VARIABLE}_pairs.csv"
)

def read_csv(path)
  raw = File.read(path, encoding: 'bom|utf-8')
  CSV.parse(raw, headers: true)
end

def config_signature(row, compare_variable)
  row.headers
     .reject { |header| header == 'algo_id' || header == compare_variable }
     .map { |header| row[header].to_s }
     .join("\x1f")
end

def merged_row(group_id, pair_id, config_row, perf_row)
  out = { 'group_id' => group_id, 'pair_id' => pair_id }
  config_row.headers.each { |header| out["config_#{header}"] = config_row[header] }
  perf_row.headers.each { |header| out["perf_#{header}"] = perf_row[header] }
  out
end

def parse_float(value)
  text = value.to_s.strip
  return nil if text.empty?

  Float(text)
rescue ArgumentError, TypeError
  nil
end

def format_percent(numerator, denominator)
  return 'n/a' if denominator.zero?

  format('%.1f%%', 100.0 * numerator / denominator)
end

def format_float(value, decimals = 3)
  return 'n/a' if value.nil?

  format("%.#{decimals}f", value)
end

def average(values)
  nums = values.compact
  return nil if nums.empty?

  nums.sum.to_f / nums.size
end

def percent_better_than(better, worse)
  return nil if better.nil? || worse.nil? || worse.zero?

  ((better - worse) / worse.abs) * 100.0
end

def puts_better_than_worse_line(prefix:, field_name:, left_value:, left_avg:, right_value:, right_avg:, decimals: 3, label: nil)
  return if left_avg.nil? || right_avg.nil?

  metric_prefix = label ? "#{label}: " : ''

  if left_avg == right_avg
    puts "#{prefix}#{metric_prefix}#{field_name}=#{left_value} and #{field_name}=#{right_value} tie " \
         "(#{format_float(left_avg, decimals)})"
    return
  end

  if left_avg > right_avg
    better_value, better_avg = left_value, left_avg
    worse_value, worse_avg = right_value, right_avg
  else
    better_value, better_avg = right_value, right_avg
    worse_value, worse_avg = left_value, left_avg
  end

  pct = percent_better_than(better_avg, worse_avg)
  puts "#{prefix}#{metric_prefix}#{field_name}=#{better_value} (#{format_float(better_avg, decimals)}) is " \
       "#{format('%.1f%%', pct)} better than #{field_name}=#{worse_value} (#{format_float(worse_avg, decimals)})"
end

def build_variable_pair_stats(pairs, compare_variable, perf_field)
  stats = Hash.new do |hash, key|
    hash[key] = { appearances: 0, wins: 0, ties: 0, missing: 0, values: [] }
  end

  pairs.each do |pair|
    left_value = pair[:left][:config][compare_variable].to_s
    right_value = pair[:right][:config][compare_variable].to_s
    left_metric = parse_float(pair[:left][:perf][perf_field])
    right_metric = parse_float(pair[:right][:perf][perf_field])

    stats[left_value][:appearances] += 1
    stats[right_value][:appearances] += 1

    if left_metric.nil? || right_metric.nil?
      stats[left_value][:missing] += 1
      stats[right_value][:missing] += 1
      next
    end

    stats[left_value][:values] << left_metric
    stats[right_value][:values] << right_metric

    if left_metric > right_metric
      stats[left_value][:wins] += 1
    elsif right_metric > left_metric
      stats[right_value][:wins] += 1
    else
      stats[left_value][:ties] += 1
      stats[right_value][:ties] += 1
    end
  end

  stats
end

def config_bool(value)
  %w[true 1 yes].include?(value.to_s.strip.downcase)
end

def paired_entries_from_pairs(pairs)
  pairs.flat_map { |pair| [pair[:left], pair[:right]] }.uniq { |entry| entry[:algo_id] }
end

def print_grouped_config_comparison(entries, group_field)
  puts "  comparison by #{group_field}:"
  if entries.empty?
    puts '    (none)'
    return
  end

  grouped = entries.group_by { |entry| entry[:config][group_field].to_s }
  metric_averages = {}

  grouped.sort_by { |value, _| value }.each do |value, group|
    time_vs_profit_avg = average(group.map { |entry| parse_float(entry[:perf]['timeVSprofit']) })
    percent_sum_avg = average(group.map { |entry| parse_float(entry[:perf]['percentSum_w_roll']) })
    duration_avg = average(group.map { |entry| parse_float(entry[:perf]['avgDurationHours']) })
    trades_avg = average(group.map { |entry| parse_float(entry[:perf]['tradesCount']) })
    metric_averages[value] = {
      timeVSprofit: time_vs_profit_avg,
      percentSum_w_roll: percent_sum_avg,
      avgDurationHours: duration_avg,
      tradesCount: trades_avg
    }

    puts "    #{group_field}=#{value}: count=#{group.size}, " \
         "avg perf_timeVSprofit=#{format_float(time_vs_profit_avg)}, " \
         "avg perf_percentSum_w_roll=#{format_float(percent_sum_avg, 2)}, " \
         "avg perf_avgDurationHours=#{format_float(duration_avg)}, " \
         "avg perf_tradesCount=#{format_float(trades_avg, 2)}"
  end

  sorted_values = metric_averages.keys.sort
  return unless sorted_values.size == 2

  left_value, right_value = sorted_values
  left_metrics = metric_averages[left_value]
  right_metrics = metric_averages[right_value]

  puts_better_than_worse_line(
    prefix: '    ', field_name: group_field,
    left_value: left_value, left_avg: left_metrics[:timeVSprofit],
    right_value: right_value, right_avg: right_metrics[:timeVSprofit],
    label: 'perf_timeVSprofit'
  )
  puts_better_than_worse_line(
    prefix: '    ', field_name: group_field,
    left_value: left_value, left_avg: left_metrics[:percentSum_w_roll],
    right_value: right_value, right_avg: right_metrics[:percentSum_w_roll],
    decimals: 2, label: 'perf_percentSum_w_roll'
  )
  puts_better_than_worse_line(
    prefix: '    ', field_name: group_field,
    left_value: left_value, left_avg: left_metrics[:avgDurationHours],
    right_value: right_value, right_avg: right_metrics[:avgDurationHours],
    label: 'perf_avgDurationHours'
  )
  puts_better_than_worse_line(
    prefix: '    ', field_name: group_field,
    left_value: left_value, left_avg: left_metrics[:tradesCount],
    right_value: right_value, right_avg: right_metrics[:tradesCount],
    decimals: 2, label: 'perf_tradesCount'
  )
end

def print_closetrade_conditional_comparisons(pairs)
  paired_entries = paired_entries_from_pairs(pairs)
  false_entries = paired_entries.reject { |entry| config_bool(entry[:config]['closetrade_after_some_time']) }
  true_entries = paired_entries.select { |entry| config_bool(entry[:config]['closetrade_after_some_time']) }

  puts 'closetrade_after_some_time=false:'
  if false_entries.empty?
    puts '  (no paired algos)'
  else
    print_grouped_config_comparison(false_entries, 'secret_tp_range_percent')
  end

  puts 'closetrade_after_some_time=true:'
  if true_entries.empty?
    puts '  (no paired algos)'
  else
    print_grouped_config_comparison(true_entries, 'closetrade_after_some_time_but_ProfitPercent_Needed')
    print_grouped_config_comparison(true_entries, 'closetrade_after_x_minutes_from_breakdown')
  end
end

def print_variable_pair_stats(label, compare_variable, stats, paired_entries, perf_field, show_avg_comparison: false, avg_decimals: 3)
  puts "#{label} higher in head-to-head pairs:"
  if stats.empty?
    puts '  (no pairs)'
    return
  end

  per_algo_averages = {}
  paired_entries.group_by { |entry| entry[:config][compare_variable].to_s }.each do |value, group|
    per_algo_averages[value] = average(group.map { |entry| parse_float(entry[:perf][perf_field]) })
  end

  stats.sort_by { |value, _| compare_variable_sort_key(value) }.each do |value, row|
    comparable = row[:appearances] - row[:missing]
    avg = per_algo_averages[value]
    avg_text = show_avg_comparison ? ", avg #{label}=#{format_float(avg, avg_decimals)} (per algo)" : ''
    puts "  #{compare_variable}=#{value}: #{row[:wins]}/#{comparable} (#{format_percent(row[:wins], comparable)})#{avg_text}"
  end

  return unless show_avg_comparison

  sorted_values = per_algo_averages.keys.sort_by { |value| compare_variable_sort_key(value) }
  return if sorted_values.size < 2

  sorted_values.combination(2).each do |left_value, right_value|
    puts_better_than_worse_line(
      prefix: '  ', field_name: compare_variable,
      left_value: left_value, left_avg: per_algo_averages[left_value],
      right_value: right_value, right_avg: per_algo_averages[right_value],
      decimals: avg_decimals, label: label
    )
  end
end

def compare_output_group_sort_key(group_id)
  text = group_id.to_s
  if (match = text.match(/\Aunpaired-(\d+)\z/))
    [2, match[1].to_i]
  elsif text.match?(/\A\d+\z/)
    [0, text.to_i]
  else
    [1, text]
  end
end

def compare_variable_sort_key(value)
  text = value.to_s
  return [0, text.to_i, text] if text.match?(/\A-?\d+\z/)

  [1, text]
end

unless File.file?(CONFIG_PATH)
  warn "ERROR: config file not found: #{CONFIG_PATH}"
  exit 1
end

unless File.file?(PERF_PATH)
  warn "ERROR: performance file not found: #{PERF_PATH}"
  exit 1
end

config_table = read_csv(CONFIG_PATH)
unless config_table.headers.include?(COMPARE_VARIABLE)
  available = config_table.headers.reject { |header| header == 'algo_id' }
  warn "ERROR: compare variable not found in config: #{COMPARE_VARIABLE}"
  warn "Available config columns: #{available.join(', ')}"
  exit 1
end

config_by_algo_id =
  config_table.each_with_object({}) do |row, memo|
    algo_id = row['algo_id'].to_s.strip
    next if algo_id.empty?

    memo[algo_id] = row
  end

perf_rows =
  read_csv(PERF_PATH).select do |row|
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

groups = Hash.new { |hash, key| hash[key] = [] }
matched_rows.each do |entry|
  signature = config_signature(entry[:config], COMPARE_VARIABLE)
  groups[signature] << entry
end

output_rows = []
pairs = []
paired_algo_ids = Set.new
group_id = 0
total_pairs = 0

sorted_groups =
  groups.sort_by do |_signature, entries|
    entries.map { |entry| entry[:algo_id].to_i }.min
  end

sorted_groups.each do |_signature, entries|
  next unless entries.size >= 2

  variable_values = entries.map { |entry| entry[:config][COMPARE_VARIABLE].to_s }.uniq
  next if variable_values.size < 2

  group_id += 1
  pair_id = 0

  entries.combination(2).each do |left, right|
    next if left[:config][COMPARE_VARIABLE].to_s == right[:config][COMPARE_VARIABLE].to_s

    pair_id += 1
    total_pairs += 1
    paired_algo_ids << left[:algo_id]
    paired_algo_ids << right[:algo_id]
    pairs << { group_id: group_id, pair_id: pair_id, left: left, right: right }

    output_rows << merged_row(group_id, pair_id, left[:config], left[:perf])
    output_rows << merged_row(group_id, pair_id, right[:config], right[:perf])
  end
end

unpaired_id = 0
matched_rows
  .reject { |entry| paired_algo_ids.include?(entry[:algo_id]) }
  .sort_by { |entry| entry[:algo_id].to_i }
  .each do |entry|
    unpaired_id += 1
    output_rows << merged_row("unpaired-#{unpaired_id}", '', entry[:config], entry[:perf])
  end

output_rows.sort_by! do |row|
  [
    compare_output_group_sort_key(row['group_id']),
    row['pair_id'].to_s.empty? ? 0 : row['pair_id'].to_i,
    row['perf_algoID'].to_i
  ]
end

leading_columns = [
  'group_id',
  'pair_id',
  "config_#{COMPARE_VARIABLE}",
  'config_algo_id',
  'perf_avgDurationHours',
  'perf_timeVSprofit',
  'perf_percentSum_w_roll',
  *CLOSETRADE_CONFIG_COLUMNS.map { |column| "config_#{column}" }
]
all_headers = output_rows.flat_map(&:keys).uniq
headers = leading_columns + (all_headers - leading_columns).sort

CSV.open(OUTPUT_PATH, 'w', write_headers: true, headers: headers) do |csv|
  output_rows.each do |row|
    csv << headers.map { |header| row[header] }
  end
end

unpaired_count = perf_rows.size - paired_algo_ids.size

puts "compare variable: #{COMPARE_VARIABLE}"
puts "algos in analyze_breakdown_algos_performance_output: #{perf_rows.size}"
puts "algos without a pair: #{unpaired_count} (#{format_percent(unpaired_count, perf_rows.size)} of all)"
puts "groups found: #{group_id}"
puts "pairs found: #{total_pairs}"
puts "unpaired groups written: #{unpaired_id}"
CompareVariableAnalysisLib.compare_analysis_lines(pairs, COMPARE_VARIABLE).each { |line| puts line }
print_closetrade_conditional_comparisons(pairs)
puts "wrote #{output_rows.size} rows to #{OUTPUT_PATH}"
