#!/usr/bin/env ruby

require 'csv'
require 'time'
require 'date'

# =========================================================
# CONFIG
# =========================================================

FILE_PATH   = 'summary_tradeResults_all_days.tsv'
OUTPUT_FILE = 'analyze_week_by_week_o.csv'

simulate_trades_per_day_limit_start = 1
simulate_trades_per_day_limit_end   = 3

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

# =========================================================
# REMOVE STACKED TRADES
# =========================================================

def remove_stacked_trades(trades)
  sorted = trades.sort_by { |t| parse_time(t['startTime']) }

  selected = []

  sorted.each do |trade|
    current_start = parse_time(trade['startTime'])
    current_end   = parse_time(trade['endTime'])
    current_dir   = direction(trade)

    overlaps = selected.any? do |kept|
      kept_start = parse_time(kept['startTime'])
      kept_end   = parse_time(kept['endTime'])
      kept_dir   = direction(kept)

      next false unless current_dir == kept_dir

      overlap_seconds =
        [current_end, kept_end].min - [current_start, kept_start].max

      overlap_seconds >= 1
    end

    selected << trade unless overlaps
  end

  selected
end

# =========================================================
# COUNT STACKED PAIRS
# =========================================================

def stacked_trade_count(trades)
  count = 0

  trades.combination(2).each do |a, b|
    next unless direction(a) == direction(b)

    a_start = parse_time(a['startTime'])
    a_end   = parse_time(a['endTime'])

    b_start = parse_time(b['startTime'])
    b_end   = parse_time(b['endTime'])

    overlap_seconds =
      [a_end, b_end].min - [a_start, b_start].max

    count += 1 if overlap_seconds >= 1
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
      stacked: 0
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
  'profit_factor',
  'profit'
]

CSV.open(OUTPUT_FILE, 'w') do |csv|
  csv << output_headers

  weekly_data.each do |week_key, analyses|
    week_start, week_end = week_key

    analyses.each do |analysis_type, data|
      trades = data[:trades]

      csv << [
        week_start.to_s,
        week_end.to_s,
        analysis_type,
        trades.size,
        data[:stacked],
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
puts '========================================================='
puts 'WEEKLY ANALYSIS COMPLETE'
puts '========================================================='
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

puts
puts 'Done.'