#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'alert_done_common'

require 'csv'
require 'set'
require_relative '../Aleksik2/smash_BREAKDOWN_create_combinationsMap_csv'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR)
PERF_PATH = File.join(SCRIPT_DIR, 'summary_tradeResults_all_days_breakdown.tsv')

# Change this to count trades grouped by another config field.
# Supported COUNT_VARIABLE values (any column in aleksik2_r_read_breakdown_algos_csv.csv except algo_id):
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
COUNT_VARIABLE = 'entry_max_minutes_after_bdend'
FORGET_VARIABLE = 'forget_about_latest_breakdown_after_x_15m_candles'
MQ5_PATH = File.expand_path('../Aleksik2/aleksik2.mq5', SCRIPT_DIR)

OUTPUT_PATH = File.join(
  SCRIPT_DIR,
  "count_variable_algotrade_occurrences_#{COUNT_VARIABLE}.csv"
)

def read_csv(path)
  raw = File.read(path, encoding: 'bom|utf-8')
  CSV.parse(raw, headers: true)
end

def format_percent(numerator, denominator)
  return 'n/a' if denominator.zero?

  format('%.1f%%', 100.0 * numerator / denominator)
end

def variable_sort_key(value)
  text = value.to_s
  return [0, text.to_i, text] if text.match?(/\A-?\d+\z/)

  [1, text]
end

def load_forget_candles_by_algo_id(mq5_path)
  return {} unless File.file?(mq5_path)

  text = File.read(mq5_path, encoding: 'bom|utf-8')
  text.each_line.with_object({}) do |line, memo|
    next unless (match = line.match(/MAGIC_BREAKDOWN(\d+)\)\]\.forget_about_latest_breakdown_after_x_15m_candles\s*=\s*(\d+)/))

    memo[match[1]] = match[2].to_i
  end
end

def entry_forget_reachability(entry_max_min, forget_candles)
  forget_min = forget_candles * 15
  room_min = forget_min - entry_max_min
  effective_entry_cap_min = [entry_max_min, forget_min].min
  unreachable_tail_min = [entry_max_min - forget_min, 0].max
  valid_with_room = BreakdownCombinationsMap.entry_forget_combo_valid?(entry_max_min, forget_candles)
  {
    forget_candles: forget_candles,
    forget_min: forget_min,
    room_min: room_min,
    effective_entry_cap_min: effective_entry_cap_min,
    unreachable_tail_min: unreachable_tail_min,
    valid_with_room: valid_with_room
  }
end

unless File.file?(CONFIG_PATH)
  warn "ERROR: config file not found: #{CONFIG_PATH}"
  exit 1
end

unless File.file?(PERF_PATH)
  warn "ERROR: trades file not found: #{PERF_PATH}"
  exit 1
end

config_table = read_csv(CONFIG_PATH)
unless config_table.headers.include?(COUNT_VARIABLE)
  available = config_table.headers.reject { |header| header == 'algo_id' }
  warn "ERROR: count variable not found in config: #{COUNT_VARIABLE}"
  warn "Available config columns: #{available.join(', ')}"
  exit 1
end

config_by_algo_id =
  config_table.each_with_object({}) do |row, memo|
    algo_id = row['algo_id'].to_s.strip
    next if algo_id.empty?

    memo[algo_id] = row
  end

split_by_forget =
  COUNT_VARIABLE != FORGET_VARIABLE && config_table.headers.include?(FORGET_VARIABLE)

trade_rows =
  read_csv(PERF_PATH).select do |row|
    row['algoID'].to_s.strip != ''
  end

counts = Hash.new(0)
algo_ids_by_value = Hash.new { |hash, key| hash[key] = Set.new }
counts_by_value_and_forget = Hash.new { |hash, key| hash[key] = Hash.new(0) }
algo_ids_by_value_and_forget = Hash.new { |hash, key| hash[key] = Hash.new { |inner, key2| inner[key2] = Set.new } }
missing_config_algo_ids = Set.new
missing_config_trade_count = 0

trade_rows.each do |trade_row|
  algo_id = trade_row['algoID'].to_s.strip
  config_row = config_by_algo_id[algo_id]
  if config_row.nil?
    missing_config_algo_ids << algo_id
    missing_config_trade_count += 1
    next
  end

  value = config_row[COUNT_VARIABLE].to_s
  counts[value] += 1
  algo_ids_by_value[value] << algo_id
  if split_by_forget
    forget_value = config_row[FORGET_VARIABLE].to_s
    counts_by_value_and_forget[value][forget_value] += 1
    algo_ids_by_value_and_forget[value][forget_value] << algo_id
  end
end

output_rows =
  counts
  .sort_by { |value, _| variable_sort_key(value) }
  .map do |value, trade_count|
    {
      'count_variable' => COUNT_VARIABLE,
      'variable_value' => value,
      'trade_count' => trade_count.to_s,
      'pct_of_trades' => format_percent(trade_count, trade_rows.size),
      'unique_algo_count' => algo_ids_by_value[value].size.to_s
    }
  end

headers = %w[count_variable variable_value trade_count pct_of_trades unique_algo_count]

CSV.open(OUTPUT_PATH, 'w', write_headers: true, headers: headers) do |csv|
  output_rows.each do |row|
    csv << headers.map { |header| row[header] }
  end
end

puts "count variable: #{COUNT_VARIABLE}"
puts "trades file: #{PERF_PATH}"
puts "total trades: #{trade_rows.size}"
puts "trades with config value: #{trade_rows.size - missing_config_trade_count}"
if missing_config_trade_count.positive?
  puts "trades missing config: #{missing_config_trade_count} " \
       "(algos: #{missing_config_algo_ids.to_a.sort.join(', ')})"
end
puts
puts 'occurrences by variable value:'
if output_rows.empty?
  puts '  (none)'
else
  output_rows.each do |row|
    value = row['variable_value']
    puts "  #{COUNT_VARIABLE}=#{value}: " \
         "trades=#{row['trade_count']} (#{row['pct_of_trades']}), " \
         "algos=#{row['unique_algo_count']}"
    next unless split_by_forget

    value_trade_count = row['trade_count'].to_i
    counts_by_value_and_forget[value]
      .sort_by { |forget_value, _| variable_sort_key(forget_value) }
      .each do |forget_value, forget_trade_count|
        puts "    #{FORGET_VARIABLE}=#{forget_value}: " \
             "trades=#{forget_trade_count} (#{format_percent(forget_trade_count, trade_rows.size)}, " \
             "#{format_percent(forget_trade_count, value_trade_count)} of #{COUNT_VARIABLE}=#{value}), " \
             "algos=#{algo_ids_by_value_and_forget[value][forget_value].size}"
      end
  end
end
puts

forget_by_algo_id = load_forget_candles_by_algo_id(MQ5_PATH)
if forget_by_algo_id.empty?
  puts 'entry/forget reachability: skipped (could not parse forget candles from aleksik2.mq5)'
else
  puts "entry/forget reachability (room rule from smash_BREAKDOWN_create_combinationsMap_csv: forget_min - entry_max >= #{ENTRY_FORGET_MIN_ROOM_MINUTES}):"
  reach_by_entry_value = Hash.new { |hash, key| hash[key] = [] }

  config_by_algo_id.each_value do |config_row|
    algo_id = config_row['algo_id'].to_s
    entry_max = config_row['entry_max_minutes_after_bdend'].to_i
    forget_candles = forget_by_algo_id[algo_id]
    next if forget_candles.nil?

    reach = entry_forget_reachability(entry_max, forget_candles)
    reach_by_entry_value[entry_max.to_s] << reach unless reach_by_entry_value[entry_max.to_s].any? { |row| row[:forget_candles] == reach[:forget_candles] }
  end

  reach_by_entry_value.sort_by { |value, _| variable_sort_key(value) }.each do |entry_value, rows|
    rows.each do |reach|
      status = reach[:valid_with_room] ? 'ok' : 'INVALID'
      puts "  entry_max=#{entry_value}, forget=#{reach[:forget_candles]}x15m (#{reach[:forget_min]} min): " \
           "room=#{reach[:room_min]} min [#{status}], effective cap=#{reach[:effective_entry_cap_min]} min" \
           "#{reach[:unreachable_tail_min].positive? ? ", unreachable tail #{reach[:unreachable_tail_min]} min" : ''}"
    end
  end

  invalid_algos =
    config_by_algo_id.filter_map do |algo_id, config_row|
      entry_max = config_row['entry_max_minutes_after_bdend'].to_i
      forget_candles = forget_by_algo_id[algo_id]
      next if forget_candles.nil?

      BreakdownCombinationsMap.entry_forget_combo_valid?(entry_max, forget_candles) ? nil : algo_id
    end

  unless invalid_algos.empty?
    puts
    puts "invalid algos (#{invalid_algos.size}): #{invalid_algos.sort.join(', ')}"
  end
end
puts
puts "wrote #{output_rows.size} rows to #{OUTPUT_PATH}"

play_alert_done! if __FILE__ == $PROGRAM_NAME
