#!/usr/bin/env ruby

require 'csv'
require 'time'
require 'date'

# =========================================================
# CONFIG
# =========================================================

FILE_PATH   = 'summary_tradeResults_all_days.tsv'
OUTPUT_FILE = 'analyze_week_by_week_1_2_3_tradesPerDay_any_o.csv'

simulate_trades_per_day_limit_start = 1
simulate_trades_per_day_limit_end   = 3

# Save full trade list per scenario (same rows used for overall profit factor).
# Skips all_trades — that list is identical to the input file.
OUTPUT_LIST_OF_TRADES_OF_EACH_SCENARIO = true

# =========================================================
# HELPERS
# =========================================================

def parse_time(str)
  Time.parse(str)
end

def direction(trade)
  trade['type'].include?('BUY') ? :long : :short
end

def profit_factor(trades)
  gross_profit = trades
    .map { |t| t['profit'].to_f }
    .select { |p| p > 0 }
    .sum

  gross_loss = trades
    .map { |t| t['profit'].to_f }
    .select { |p| p < 0 }
    .map(&:abs)
    .sum

  return 0 if gross_loss == 0

  (gross_profit / gross_loss).round(2)
end

def total_profit(trades)
  trades.map { |t| t['profit'].to_f }.sum.round(2)
end

def parse_trade_date(date_str)
  Date.parse(date_str.gsub('.', '-'))
end

def weekday?(date)
  !date.saturday? && !date.sunday?
end

def weekday_count_in_range(first_date, last_date)
  count = 0
  date = first_date

  while date <= last_date
    count += 1 if weekday?(date)
    date += 1
  end

  count
end

def trade_date_range(trades)
  dates =
    trades
      .map { |t| t['date'].to_s.strip }
      .reject(&:empty?)
      .map { |d| parse_trade_date(d) }

  return [nil, nil, 0] if dates.empty?

  first_date = dates.min
  last_date = dates.max

  [first_date, last_date, weekday_count_in_range(first_date, last_date)]
end

def unique_trade_days(trades)
  trades
    .map { |t| t['date'].to_s.strip }
    .reject(&:empty?)
    .uniq
end

def trade_rate(trades, total_weekdays)
  return 0.0 if total_weekdays.zero?

  unique_trade_days(trades).size.to_f / total_weekdays
end

def total_overlapping_trades(weekly_data)
  total = 0

  weekly_data.each_value do |analyses|
    total += analyses['all_trades'][:overlapping_trades]
  end

  total
end

def aggregate_trades_by_scenario(weekly_data)
  overall = Hash.new { |h, k| h[k] = [] }

  weekly_data.each_value do |analyses|
    analyses.each do |analysis_type, data|
      overall[analysis_type].concat(data[:trades])
    end
  end

  overall
end

def scenario_trades_output_path(scenario_name)
  base = OUTPUT_FILE.sub(/\.csv\z/, '')
  "#{base}_scenario_#{scenario_name}_trades.tsv"
end

def write_scenario_trade_lists(weekly_data, headers)
  aggregate_trades_by_scenario(weekly_data).each do |scenario, trades|
    next if scenario == 'all_trades'
    next if trades.empty?

    output_path = scenario_trades_output_path(scenario)
    sorted = trades.sort_by { |t| parse_time(t['startTime']) }

    CSV.open(output_path, 'w', write_headers: true, headers: headers) do |csv|
      sorted.each { |row| csv << row }
    end

    puts "Scenario trades: #{scenario} (#{sorted.size}) -> #{output_path}"
  end
end

def print_overall_summary(weekly_data, all_rows_for_range)
  _, _, total_weekdays = trade_date_range(all_rows_for_range)

  overall = aggregate_trades_by_scenario(weekly_data)
  overlap_by_scenario = Hash.new(0)

  weekly_data.each_value do |analyses|
    analyses.each do |analysis_type, data|
      overlap_by_scenario[analysis_type] += data[:overlapping_trades]
    end
  end

  summary_rows =
    overall.map do |scenario, trades|
      {
        scenario: scenario,
        profit_factor: profit_factor(trades),
        trade_rate: trade_rate(trades, total_weekdays),
        trade_count: trades.size,
        overlapping_trades: scenario == 'all_trades' ? overlap_by_scenario[scenario] : nil
      }
    end

  summary_rows.sort_by! { |r| -r[:profit_factor] }

  puts 'OVERALL SUMMARY (all weeks, sorted by profit factor)'
  puts format('%-45s %12s %12s %12s %12s', 'scenario', 'profit_factor', 'trade_rate', 'trade_count', 'overlap_trades')
  puts '-' * 97

  summary_rows.each do |r|
    overlap_label = r[:overlapping_trades].nil? ? '' : r[:overlapping_trades].to_s

    puts format(
      '%-45s %12.2f %12.2f %12d %12s',
      r[:scenario],
      r[:profit_factor],
      r[:trade_rate],
      r[:trade_count],
      overlap_label
    )
  end

  puts
  puts 'overlap_trades = same-direction trades overlapping >=1s (all_trades row only)'
  puts
end

# =========================================================
# OVERLAP / STACKED TRADES
# =========================================================

def overlap_seconds(trade_a, trade_b)
  a_start = parse_time(trade_a['startTime'])
  a_end   = parse_time(trade_a['endTime'])
  b_start = parse_time(trade_b['startTime'])
  b_end   = parse_time(trade_b['endTime'])

  [a_end, b_end].min - [a_start, b_start].max
end

def stacked_with?(trade_a, trade_b)
  return false unless direction(trade_a) == direction(trade_b)

  overlap_seconds(trade_a, trade_b) >= 1
end

def remove_stacked_trades(trades)
  sorted = trades.sort_by { |t| parse_time(t['startTime']) }

  selected = []

  sorted.each do |trade|
    overlaps = selected.any? { |kept| stacked_with?(trade, kept) }
    selected << trade unless overlaps
  end

  selected
end

def overlapping_trades_count(trades)
  sorted = trades.sort_by { |t| parse_time(t['startTime']) }

  sorted.count do |trade|
    sorted.any? do |other|
      other.object_id != trade.object_id && stacked_with?(trade, other)
    end
  end
end

def stacked_trade_count(trades)
  count = 0

  trades.combination(2).each do |a, b|
    count += 1 if stacked_with?(a, b)
  end

  count
end

# =========================================================
# LOAD DATA
# =========================================================

rows = CSV.read(FILE_PATH, headers: true)

# =========================================================
# GROUP BY DAY
# =========================================================

trades_by_day = rows.group_by { |r| r['date'] }

# =========================================================
# WEEKLY AGGREGATION STORAGE
# =========================================================

weekly_data = Hash.new do |h, k|
  h[k] = Hash.new do |hh, kk|
    hh[kk] = {
      trades: [],
      stacked: 0,
      overlapping_trades: 0
    }
  end
end

# =========================================================
# PROCESS EACH DAY
# =========================================================

trades_by_day.each do |date_str, trades|
  date = Date.parse(date_str.gsub('.', '-'))

  # monday -> sunday week
  week_start = date - (date.cwday - 1)
  week_end   = week_start + 6

  week_key = [week_start, week_end]

  trades = trades.sort_by { |t| parse_time(t['startTime']) }

  # -------------------------------------------------------
  # ALL TRADES
  # -------------------------------------------------------

  weekly_data[week_key]['all_trades'][:trades].concat(trades)

  weekly_data[week_key]['all_trades'][:stacked] +=
    stacked_trade_count(trades)

  weekly_data[week_key]['all_trades'][:overlapping_trades] +=
    overlapping_trades_count(trades)

  # -------------------------------------------------------
  # FIRST N NON-STACKED TRADES
  # -------------------------------------------------------

  clean_trades = remove_stacked_trades(trades)

  (simulate_trades_per_day_limit_start..simulate_trades_per_day_limit_end).each do |limit|
    selected = clean_trades.first(limit)

    analysis_name = "first_#{limit}_trades_non_stacked"

    weekly_data[week_key][analysis_name][:trades]
      .concat(selected)
  end
end

# =========================================================
# WRITE CSV
# =========================================================

output_headers = [
  'week_start_date',
  'week_end_date',
  'analysis_type',
  'tradecount',
  'stacked_trade_count',
  'overlapping_trades_count',
  'profit_factor',
  'profit'
]

CSV.open(OUTPUT_FILE, 'w') do |csv|
  csv << output_headers

  weekly_data.each do |week_key, analyses|
    week_start, week_end = week_key

    analyses.each do |analysis_type, data|
      trades = data[:trades]
      overlapping_trades =
        analysis_type == 'all_trades' ? data[:overlapping_trades] : ''

      csv << [
        week_start.to_s,
        week_end.to_s,
        analysis_type,
        trades.size,
        data[:stacked],
        overlapping_trades,
        profit_factor(trades),
        total_profit(trades)
      ]
    end
  end
end

# =========================================================
# CONSOLE SUMMARY ONLY
# =========================================================

puts
puts '---------------------------------------------------------'
puts 'WEEKLY ANALYSIS COMPLETE'
puts '---------------------------------------------------------'
puts
puts "Input file : #{FILE_PATH}"
puts "Output file: #{OUTPUT_FILE}"
puts

weekly_count =
  weekly_data.keys.size

puts "Weeks analyzed: #{weekly_count}"

(simulate_trades_per_day_limit_start..simulate_trades_per_day_limit_end).each do |limit|
  puts "Included analysis: first #{limit} non-stacked trades per day"
end

puts "All-trades overlapping trades: #{total_overlapping_trades(weekly_data)}"

print_overall_summary(weekly_data, rows)

if OUTPUT_LIST_OF_TRADES_OF_EACH_SCENARIO
  puts 'Scenario trade lists (all weeks combined, excludes all_trades):'
  write_scenario_trade_lists(weekly_data, rows.headers)
end

puts
puts 'Done.'
