#!/usr/bin/env ruby

require 'csv'
require 'time'

# =========================================================
# CONFIG
# =========================================================

FILE_PATH   = 'summary_tradeResults_all_days.tsv'
OUTPUT_FILE = 'analyze_day_by_day_output.csv'

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

# ---------------------------------------------------------
# Remove stacked trades
# ---------------------------------------------------------
# Rules:
# - same direction
# - overlap >= 1 second
# - earlier trade wins
# ---------------------------------------------------------

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

# ---------------------------------------------------------
# Count stacked pairs
# ---------------------------------------------------------

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

grouped = rows.group_by { |r| r['date'] }

# =========================================================
# CSV OUTPUT
# =========================================================

output_headers = [
  'date',
  'analysis_type',
  'tradecount',
  'stacked_trade_count',
  'profit_factor',
  'profit'
]

# =========================================================
# GLOBAL SUMMARY STORAGE
# =========================================================

global_summary = Hash.new do |h, k|
  h[k] = {
    tradecount: 0,
    stacked: 0,
    gross_profit: 0.0,
    gross_loss: 0.0,
    profit: 0.0,
    days: 0
  }
end

# =========================================================
# WRITE CSV
# =========================================================

CSV.open(OUTPUT_FILE, 'w') do |csv|
  csv << output_headers

  grouped.each do |date, trades|
    trades = trades.sort_by { |t| parse_time(t['startTime']) }

    # -----------------------------------------------------
    # FULL DAY ANALYSIS
    # -----------------------------------------------------

    full_tradecount = trades.size
    full_stacked    = stacked_trade_count(trades)
    full_pf         = profit_factor(trades)
    full_profit     = total_profit(trades)

    csv << [
      date,
      'all_trades',
      full_tradecount,
      full_stacked,
      full_pf,
      full_profit
    ]

    summary = global_summary['all_trades']

    summary[:tradecount] += full_tradecount
    summary[:stacked] += full_stacked
    summary[:profit] += full_profit
    summary[:days] += 1

    trades.each do |t|
      p = t['profit'].to_f

      if p > 0
        summary[:gross_profit] += p
      elsif p < 0
        summary[:gross_loss] += p.abs
      end
    end

    # -----------------------------------------------------
    # FIRST N NON-STACKED TRADES
    # -----------------------------------------------------

    clean_trades = remove_stacked_trades(trades)

    (simulate_trades_per_day_limit_start..simulate_trades_per_day_limit_end).each do |limit|
      selected = clean_trades.first(limit)

      tc     = selected.size
      pf     = profit_factor(selected)
      profit = total_profit(selected)

      analysis_name = "first_#{limit}_trades_non_stacked"

      csv << [
        date,
        analysis_name,
        tc,
        0,
        pf,
        profit
      ]

      summary = global_summary[analysis_name]

      summary[:tradecount] += tc
      summary[:profit] += profit
      summary[:days] += 1

      selected.each do |t|
        p = t['profit'].to_f

        if p > 0
          summary[:gross_profit] += p
        elsif p < 0
          summary[:gross_loss] += p.abs
        end
      end
    end
  end
end

# =========================================================
# CONSOLE SUMMARY
# =========================================================

puts
puts '========================================================='
puts 'GLOBAL SUMMARY ACROSS ALL DAYS'
puts '========================================================='

global_summary.each do |analysis, data|
  pf =
    if data[:gross_loss] == 0
      0
    else
      (data[:gross_profit] / data[:gross_loss]).round(2)
    end

  avg_profit =
    if data[:days] == 0
      0
    else
      (data[:profit] / data[:days]).round(2)
    end

  puts
  puts "Analysis: #{analysis}"
  puts "Days: #{data[:days]}"
  puts "Total Trades: #{data[:tradecount]}"
  puts "Stacked Trade Pairs: #{data[:stacked]}"
  puts "Profit Factor: #{pf}"
  puts "Total Profit: #{data[:profit].round(2)}"
  puts "Average Profit Per Day: #{avg_profit}"
end

puts
puts "CSV written to: #{OUTPUT_FILE}"