#!/usr/bin/env ruby

require 'csv'
require 'date'
# =========================================================
# CONFIG
# =========================================================

FILE_PATH = 'summary_tradeResults_all_days.tsv'

# =========================================================
# HELPERS
# =========================================================
EXCLUDE_PREFIXES_MODE = true
EXCLUDE_PREFIXES = ["19", "20", "21", "22", "25", "26"]  # magic first 2 digits; comma in one string also works, e.g. "20, 24"

def excluded_prefixes
  EXCLUDE_PREFIXES
    .flat_map { |p| p.to_s.split(',') }
    .map(&:strip)
    .reject(&:empty?)
end

def trade_excluded?(trade)
  EXCLUDE_PREFIXES_MODE && excluded_prefixes.include?(trade[:magic_prefix])
end

def apply_exclude_prefixes(trades)
  return trades unless EXCLUDE_PREFIXES_MODE

  trades.reject { |t| trade_excluded?(t) }
end

def winrate(trades)
  return 0.0 if trades.empty?

  wins = trades.count { |t| t[:profit].to_f > 0 }
  (wins.to_f / trades.size) * 100.0
end

def avg_profit(trades)
  return 0.0 if trades.empty?

  trades.sum { |t| t[:profit].to_f } / trades.size
end

def profit_factor(trades)
  profits = trades.map { |t| t[:profit].to_f }

  gross_profit = profits.select(&:positive?).sum
  gross_loss = profits.select(&:negative?).sum.abs

  return 999.0 if gross_loss.zero? && gross_profit > 0
  return 0.0 if gross_loss.zero?

  gross_profit / gross_loss
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
      .map { |t| t[:date] }
      .reject(&:empty?)
      .map { |d| parse_trade_date(d) }

  return [nil, nil, 0] if dates.empty?

  first_date = dates.min
  last_date = dates.max

  [first_date, last_date, weekday_count_in_range(first_date, last_date)]
end

def unique_trade_days(trades)
  trades
    .map { |t| t[:date] }
    .reject(&:empty?)
    .uniq
end

def trade_rate(trades, total_trading_days)
  return 0.0 if total_trading_days.zero?

  unique_trade_days(trades).size.to_f / total_trading_days
end

def format_profit_factor(trades)
  return 'n/a (no trades)' if trades.empty?

  pf = profit_factor(trades)
  pf >= 999.0 ? '999.00 (no losses)' : format('%.2f', pf)
end

def print_summary(label, trades, total_trading_days)
  winners = trades.select { |t| t[:profit].to_f > 0 }
  losers = trades.select { |t| t[:profit].to_f < 0 }

  puts label
  puts format('  trades: %d', trades.size)
  puts format('  trade rate: %.2f (%d / %d weekdays)', trade_rate(trades, total_trading_days), unique_trade_days(trades).size, total_trading_days)
  puts format('  winrate: %.2f%%', winrate(trades))
  puts format('  profit factor: %.2f', profit_factor(trades))
  puts format('  avg profit (winning trades): %.2f', avg_profit(winners))
  puts format('  avg profit (losing trades): %.2f', avg_profit(losers))
  puts
end

def print_excluded_prefixes_footer(all_rows)
  return unless EXCLUDE_PREFIXES_MODE

  excluded_groups = all_rows.group_by { |r| r[:magic_prefix] }
  parts =
    excluded_prefixes.sort.map do |prefix|
      trades = excluded_groups[prefix] || []
      "prefix #{prefix} (#{trades.size} trades, pf #{format_profit_factor(trades)})"
    end

  puts "!!!!!!!!!!!!!!!!!!!!!!!!! EXCLUDED from ALL TRADES: #{parts.join('; ')}"
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
    date: row['date'].to_s.strip,
    profit: row['profit'].to_f
  }
end

if rows.empty?
  $stderr.puts 'ERROR: No trades loaded.'
  exit 1
end

first_date, last_date, all_trading_day_count = trade_date_range(rows)

$stderr.puts "Loaded trades: #{rows.size}"
$stderr.puts "Date range: #{first_date} -> #{last_date}"
$stderr.puts "Weekdays in range (excl. weekends): #{all_trading_day_count}"
$stderr.puts "Days with any trade in file: #{unique_trade_days(rows).size}"
if EXCLUDE_PREFIXES_MODE
  excluded = rows.count { |t| trade_excluded?(t) }
  $stderr.puts "EXCLUDE_PREFIXES_MODE: excluding prefixes #{excluded_prefixes.inspect} (#{excluded} trades dropped from ALL TRADES output)"
end
$stderr.puts

rows_for_all_trades = apply_exclude_prefixes(rows)

# =========================================================
# OUTPUT
# =========================================================

puts '=' * 60
puts 'ALL TRADES'
puts '=' * 60
puts

print_summary('Overall', rows_for_all_trades, all_trading_day_count)

puts '=' * 60
puts 'BY MAGIC PREFIX (first 2 digits)'
puts '=' * 60
puts

magic_groups = rows_for_all_trades.group_by { |r| r[:magic_prefix] }

magic_groups.keys.sort.each do |magic_prefix|
  print_summary("Magic prefix #{magic_prefix}", magic_groups[magic_prefix], all_trading_day_count)
end

print_excluded_prefixes_footer(rows)

$stderr.puts 'DONE'
