#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'set'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR)
PERF_PATH = File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_output.csv')

# Change this to compare algos that differ only in another config field.
COMPARE_VARIABLE = 'after_bd_need_x_15greenc'

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

def merged_row(pair_id, config_row, perf_row)
  out = { 'pair_id' => pair_id }
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

def format_relative_percent_difference(base, other)
  return 'n/a' if base.nil? || other.nil? || base.zero?

  diff = ((other - base) / base.abs) * 100.0
  sign = diff.positive? ? '+' : ''
  "#{sign}#{format('%.1f%%', diff)}"
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
    duration_avg = average(group.map { |entry| parse_float(entry[:perf]['avgDurationHours']) })
    trades_avg = average(group.map { |entry| parse_float(entry[:perf]['tradesCount']) })
    metric_averages[value] = {
      timeVSprofit: time_vs_profit_avg,
      avgDurationHours: duration_avg,
      tradesCount: trades_avg
    }

    puts "    #{group_field}=#{value}: count=#{group.size}, " \
         "avg perf_timeVSprofit=#{format_float(time_vs_profit_avg)}, " \
         "avg perf_avgDurationHours=#{format_float(duration_avg)}, " \
         "avg perf_tradesCount=#{format_float(trades_avg, 2)}"
  end

  sorted_values = metric_averages.keys.sort
  return unless sorted_values.size == 2

  left_value, right_value = sorted_values
  left_metrics = metric_averages[left_value]
  right_metrics = metric_averages[right_value]

  puts "    avg vs avg perf_timeVSprofit: " \
       "#{format_float(left_metrics[:timeVSprofit])} vs #{format_float(right_metrics[:timeVSprofit])} " \
       "(#{format_relative_percent_difference(left_metrics[:timeVSprofit], right_metrics[:timeVSprofit])} " \
       "for #{group_field}=#{right_value} vs #{left_value})"
  puts "    avg vs avg perf_avgDurationHours: " \
       "#{format_float(left_metrics[:avgDurationHours])} vs #{format_float(right_metrics[:avgDurationHours])} " \
       "(#{format_relative_percent_difference(left_metrics[:avgDurationHours], right_metrics[:avgDurationHours])} " \
       "for #{group_field}=#{right_value} vs #{left_value})"
  puts "    avg vs avg perf_tradesCount: " \
       "#{format_float(left_metrics[:tradesCount], 2)} vs #{format_float(right_metrics[:tradesCount], 2)} " \
       "(#{format_relative_percent_difference(left_metrics[:tradesCount], right_metrics[:tradesCount])} " \
       "for #{group_field}=#{right_value} vs #{left_value})"
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

def print_variable_pair_stats(label, compare_variable, stats, show_avg_comparison: false, avg_decimals: 3)
  puts "#{label} higher in head-to-head pairs:"
  if stats.empty?
    puts '  (no pairs)'
    return
  end

  averages = {}
  stats.sort_by { |value, _| value }.each do |value, row|
    comparable = row[:appearances] - row[:missing]
    avg = average(row[:values])
    averages[value] = avg
    avg_text = show_avg_comparison ? ", avg #{label}=#{format_float(avg, avg_decimals)}" : ''
    puts "  #{compare_variable}=#{value}: #{row[:wins]}/#{comparable} (#{format_percent(row[:wins], comparable)})#{avg_text}"
  end

  return unless show_avg_comparison

  sorted_values = averages.keys.sort
  return unless sorted_values.size == 2

  left_value, right_value = sorted_values
  left_avg = averages[left_value]
  right_avg = averages[right_value]
  return if left_avg.nil? || right_avg.nil?

  puts "  avg vs avg: #{format_float(left_avg, avg_decimals)} vs #{format_float(right_avg, avg_decimals)} " \
       "(#{format_relative_percent_difference(left_avg, right_avg)} for #{compare_variable}=#{right_value} vs #{left_value})"
end

unless File.file?(CONFIG_PATH)
  warn "ERROR: config file not found: #{CONFIG_PATH}"
  exit 1
end

unless File.file?(PERF_PATH)
  warn "ERROR: performance file not found: #{PERF_PATH}"
  exit 1
end

unless read_csv(CONFIG_PATH).headers.include?(COMPARE_VARIABLE)
  warn "ERROR: compare variable not found in config: #{COMPARE_VARIABLE}"
  exit 1
end

config_by_algo_id =
  read_csv(CONFIG_PATH).each_with_object({}) do |row, memo|
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
pair_id = 0

groups.each_value do |entries|
  next unless entries.size >= 2

  variable_values = entries.map { |entry| entry[:config][COMPARE_VARIABLE].to_s }.uniq
  next if variable_values.size < 2

  entries.combination(2).each do |left, right|
    next if left[:config][COMPARE_VARIABLE].to_s == right[:config][COMPARE_VARIABLE].to_s

    pair_id += 1
    paired_algo_ids << left[:algo_id]
    paired_algo_ids << right[:algo_id]
    pairs << { left: left, right: right }

    output_rows << merged_row(pair_id, left[:config], left[:perf])
    output_rows << merged_row(pair_id, right[:config], right[:perf])
  end
end

output_rows.sort_by! do |row|
  [row['pair_id'].to_i, row['perf_algoID'].to_i]
end

leading_columns = [
  'pair_id',
  "config_#{COMPARE_VARIABLE}",
  'config_algo_id',
  'perf_avgDurationHours',
  'perf_timeVSprofit',
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

time_vs_profit_stats = build_variable_pair_stats(pairs, COMPARE_VARIABLE, 'timeVSprofit')
avg_duration_stats = build_variable_pair_stats(pairs, COMPARE_VARIABLE, 'avgDurationHours')
trade_count_stats = build_variable_pair_stats(pairs, COMPARE_VARIABLE, 'tradesCount')

puts "compare variable: #{COMPARE_VARIABLE}"
puts "algos in analyze_breakdown_algos_performance_output: #{perf_rows.size}"
puts "algos without a pair: #{unpaired_count} (#{format_percent(unpaired_count, perf_rows.size)} of all)"
puts "pairs found: #{pair_id}"
print_variable_pair_stats('perf_timeVSprofit', COMPARE_VARIABLE, time_vs_profit_stats, show_avg_comparison: true)
print_variable_pair_stats('perf_avgDurationHours', COMPARE_VARIABLE, avg_duration_stats, show_avg_comparison: true)
print_variable_pair_stats('perf_tradesCount', COMPARE_VARIABLE, trade_count_stats, show_avg_comparison: true, avg_decimals: 2)
print_closetrade_conditional_comparisons(pairs)
puts "wrote #{output_rows.size} rows to #{OUTPUT_PATH}"
