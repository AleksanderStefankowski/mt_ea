#!/usr/bin/env ruby
# frozen_string_literal: true

# Pairs algos only when a config group has exactly 2 algos that match on every field
# except COMPARE_VARIABLE. Each pair is one algo vs one algo — win counts only, no averages.

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
COMPARE_VARIABLE = 'entryrange_range_percentspot'

WRITE_OUTPUT_FILE = false

PERF_FIELDS = %w[
  timeVSprofit
  percentSum_w_roll
  avgDurationHours
  tradesCount
].freeze

OUTPUT_PATH = File.join(
  SCRIPT_DIR,
  "compare_variable_direct2Pairs_#{COMPARE_VARIABLE}_pairs.csv"
)

def read_csv(path)
  raw = File.read(path, encoding: 'bom|utf-8')
  CSV.parse(raw, headers: true)
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
  return '' if value.nil?

  format("%.#{decimals}f", value)
end

def compare_variable_sort_key(value)
  text = value.to_s
  return [0, text.to_i, text] if text.match?(/\A-?\d+\z/)

  [1, text]
end

def config_signature(row, compare_variable)
  row.headers
     .reject { |header| header == 'algo_id' || header == compare_variable }
     .map { |header| row[header].to_s }
     .join("\x1f")
end

def pair_winner(left_metric, right_metric)
  return 'tie' if left_metric.nil? || right_metric.nil?
  return 'tie' if left_metric == right_metric

  left_metric > right_metric ? 'left' : 'right'
end

def build_direct_pairs(matched_rows, compare_variable)
  groups = Hash.new { |hash, key| hash[key] = [] }
  matched_rows.each do |entry|
    signature = config_signature(entry[:config], compare_variable)
    groups[signature] << entry
  end

  pairs = []
  paired_algo_ids = Set.new
  skipped_not_size_2 = 0
  skipped_same_variable = 0
  group_id = 0

  groups.sort_by { |_signature, entries| entries.map { |entry| entry[:algo_id].to_i }.min }.each do |_signature, entries|
    if entries.size != 2
      skipped_not_size_2 += 1 if entries.size > 1
      next
    end

    left, right = entries.sort_by { |entry| entry[:algo_id].to_i }
    if left[:config][compare_variable].to_s == right[:config][compare_variable].to_s
      skipped_same_variable += 1
      next
    end

    group_id += 1
    paired_algo_ids << left[:algo_id]
    paired_algo_ids << right[:algo_id]
    pairs << { group_id: group_id, left: left, right: right }
  end

  unpaired =
    matched_rows
    .reject { |entry| paired_algo_ids.include?(entry[:algo_id]) }
    .sort_by { |entry| entry[:algo_id].to_i }

  {
    pairs: pairs,
    paired_algo_ids: paired_algo_ids,
    unpaired: unpaired,
    skipped_not_size_2: skipped_not_size_2,
    skipped_same_variable: skipped_same_variable
  }
end

def pair_output_row(pair, compare_variable)
  left = pair[:left]
  right = pair[:right]
  left_value = left[:config][compare_variable].to_s
  right_value = right[:config][compare_variable].to_s

  row = {
    'group_id' => pair[:group_id],
    'left_algo_id' => left[:algo_id],
    "left_#{compare_variable}" => left_value,
    'right_algo_id' => right[:algo_id],
    "right_#{compare_variable}" => right_value
  }

  PERF_FIELDS.each do |field|
    left_metric = parse_float(left[:perf][field])
    right_metric = parse_float(right[:perf][field])
    row["left_perf_#{field}"] = format_float(left_metric, field == 'percentSum_w_roll' || field == 'tradesCount' ? 2 : 3)
    row["right_perf_#{field}"] = format_float(right_metric, field == 'percentSum_w_roll' || field == 'tradesCount' ? 2 : 3)

    winner = pair_winner(left_metric, right_metric)
    row["winner_perf_#{field}"] =
      case winner
      when 'left' then left_value
      when 'right' then right_value
      else 'tie'
      end
  end

  row
end

def build_win_stats(pairs, compare_variable)
  stats =
    PERF_FIELDS.to_h do |field|
      [field, Hash.new { |hash, key| hash[key] = { wins: 0, ties: 0, missing: 0 } }]
    end

  pairs.each do |pair|
    left_value = pair[:left][:config][compare_variable].to_s
    right_value = pair[:right][:config][compare_variable].to_s

    PERF_FIELDS.each do |field|
      left_metric = parse_float(pair[:left][:perf][field])
      right_metric = parse_float(pair[:right][:perf][field])
      field_stats = stats[field]

      if left_metric.nil? || right_metric.nil?
        field_stats[left_value][:missing] += 1
        field_stats[right_value][:missing] += 1
        next
      end

      winner = pair_winner(left_metric, right_metric)
      case winner
      when 'left'
        field_stats[left_value][:wins] += 1
      when 'right'
        field_stats[right_value][:wins] += 1
      else
        field_stats[left_value][:ties] += 1
        field_stats[right_value][:ties] += 1
      end
    end
  end

  stats
end

def print_win_stats(label, compare_variable, stats, pair_count)
  puts "#{label} wins in direct pairs:"
  if pair_count.zero?
    puts '  (no pairs)'
    return
  end

  values = stats.keys.sort_by { |value| compare_variable_sort_key(value) }
  values.each do |value|
    row = stats[value]
    comparable = pair_count - row[:missing]
    puts "  #{compare_variable}=#{value}: #{row[:wins]}/#{comparable} (#{format_percent(row[:wins], comparable)}), ties=#{row[:ties]}"
  end
end

CompareVariableAnalysisLib.refresh_breakdown_algos_performance_output!(SCRIPT_DIR)

unless File.file?(CONFIG_PATH)
  warn "ERROR: config file not found: #{CONFIG_PATH}"
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

perf_rows = read_csv(PERF_PATH).select { |row| row['algoID'].to_s.strip != '' }
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

run = build_direct_pairs(matched_rows, COMPARE_VARIABLE)
pairs = run[:pairs]
output_rows = pairs.map { |pair| pair_output_row(pair, COMPARE_VARIABLE) }
win_stats = build_win_stats(pairs, COMPARE_VARIABLE)

headers = output_rows.flat_map(&:keys).uniq
if WRITE_OUTPUT_FILE
  CSV.open(OUTPUT_PATH, 'w', write_headers: true, headers: headers) do |csv|
    output_rows.each do |row|
      csv << headers.map { |header| row[header] }
    end
  end
end

puts "compare variable: #{COMPARE_VARIABLE}"
puts 'pairing mode: direct pairs only (exactly 2 algos, all config equal except compare variable)'
puts "algos in analyze_breakdown_algos_performance_output: #{perf_rows.size}"
puts "pairs found: #{pairs.size}"
puts "algos without a pair: #{run[:unpaired].size} (#{format_percent(run[:unpaired].size, perf_rows.size)} of all)"
puts "groups skipped (size != 2): #{run[:skipped_not_size_2]}"
puts "groups skipped (size 2, same #{COMPARE_VARIABLE}): #{run[:skipped_same_variable]}"
puts

PERF_FIELDS.each do |field|
  print_win_stats("perf_#{field}", COMPARE_VARIABLE, win_stats[field], pairs.size)
  puts
end

puts "wrote #{output_rows.size} pair rows to #{OUTPUT_PATH}" if WRITE_OUTPUT_FILE
