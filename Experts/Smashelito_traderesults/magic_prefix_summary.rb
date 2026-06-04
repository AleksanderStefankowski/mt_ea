#!/usr/bin/env ruby

require 'csv'

# =========================================================
# CONFIG
# =========================================================

FILE_PATH = 'summary_tradeResults_all_days.tsv'

# =========================================================
# HELPERS
# =========================================================

def profit_factor(trades)
  profits = trades.map { |t| t[:profit].to_f }

  gross_profit = profits.select(&:positive?).sum
  gross_loss = profits.select(&:negative?).sum.abs

  return 999.0 if gross_loss.zero? && gross_profit > 0
  return 0.0 if gross_loss.zero?

  gross_profit / gross_loss
end

def net_profit(trades)
  trades.sum { |t| t[:profit].to_f }
end

def winrate(trades)
  return 0 if trades.empty?

  wins = trades.count { |t| t[:profit].to_f > 0 }
  (wins.to_f / trades.size) * 100.0
end

def unique_trade_days(trades)
  trades
    .map { |t| t[:date] }
    .reject(&:empty?)
    .uniq
end

def trade_rate(trades, total_trading_days)
  return 0.0 if total_trading_days.zero?

  (unique_trade_days(trades).size.to_f / total_trading_days) * 100.0
end

def sample_start_times(trades, max_samples = 5)
  trades
    .map { |t| t[:start_time] }
    .reject(&:empty?)
    .sort
    .first(max_samples)
    .join('; ')
end

def sessions_detected(trades, all_sessions_in_data)
  found =
    trades
      .map { |t| t[:session] }
      .reject(&:empty?)
      .uniq
      .sort

  return 'full' if found.sort == all_sessions_in_data.sort

  found.join('; ')
end

# =========================================================
# LOAD FILE
# =========================================================

$stderr.puts
$stderr.puts "Loading file: #{FILE_PATH}"

raw = File.read(FILE_PATH, encoding: 'bom|utf-8')

csv = CSV.parse(raw, headers: true, col_sep: ',')

rows = []

csv.each do |row|
  magic = row['magic'].to_s.strip
  next if magic.empty?

  rows << {
    magic_prefix: magic[0, 2],
    session: row['sessionSent'].to_s.strip,
    profit: row['profit'].to_f,
    date: row['date'].to_s.strip,
    start_time: row['startTime'].to_s.strip
  }
end

if rows.empty?
  $stderr.puts "ERROR: No trades loaded."
  exit 1
end

all_trading_day_count = unique_trade_days(rows).size
all_sessions_in_data =
  rows
    .map { |t| t[:session] }
    .reject(&:empty?)
    .uniq
    .sort

$stderr.puts "Loaded trades: #{rows.size}"
$stderr.puts "Days with any level trade: #{all_trading_day_count}"
$stderr.puts

magic_groups = rows.group_by { |r| r[:magic_prefix] }

headers = %w[
  magic_prefix
  sessions
  trade_count
  traderate
  profitfactor
  winrate
  netprofit
  grouping_sampledates
]

csv_out = CSV.generate do |out|
  out << headers

  magic_groups.keys.sort.each do |magic_prefix|
    trades = magic_groups[magic_prefix]

    out << [
      magic_prefix,
      sessions_detected(trades, all_sessions_in_data),
      trades.size,
      format('%.2f', trade_rate(trades, all_trading_day_count)),
      format('%.2f', profit_factor(trades)),
      format('%.2f', winrate(trades)),
      format('%.2f', net_profit(trades)),
      sample_start_times(trades)
    ]
  end
end

print csv_out

$stderr.puts
$stderr.puts "DONE"
