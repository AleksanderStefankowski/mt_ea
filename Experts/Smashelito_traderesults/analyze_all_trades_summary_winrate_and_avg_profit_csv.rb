#!/usr/bin/env ruby

require 'csv'
require 'date'
require 'set'

# =========================================================
# CONFIG
# =========================================================

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
FILE_PATH = File.join(SCRIPT_DIR, 'summary_tradeResults_all_days.tsv')
SMASHELITO_MQ5_PATH = File.join(SCRIPT_DIR, '..', 'Smashelito', 'smashelito.mq5')
OUTPUT_CSV_PATH = File.join(SCRIPT_DIR, 'analyze_all_trades_summary_winrate_and_avg_profit_output.csv')

EXCLUDE_PREFIXES_MODE = true
EXCLUDE_PREFIXES = [
    "11", "12", "13", "14", "15", "16", "17", "18", "19", 
    "20", "21", "22", "23", "25", "26", "27", "30"
]
# EXCLUDE_PREFIXES = ["11" "12 13  14 15 16 17 18 19', '20', '21', '22',  "23" '25', '26', '27', "30] #  10 24  28 29

CSV_HEADERS = %w[
  magicprefix
  tp
  sl
  profitfactor
  projected_PF_if_next_future_trade_is_a_loss
  projected_PF_if_next_2_future_trades_is_a_loss
  traderate
  max_loseday_streak
  max_notrades_streak
  avg_notrades_streak
  tradedDaysCount
  allDaysCount
  allDays_startDate
  allDays_endDate
].freeze

# =========================================================
# HELPERS
# =========================================================

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

def profit_factor(trades)
  gross_profit, gross_loss = gross_profit_and_loss(trades)
  profit_factor_from_gross(gross_profit, gross_loss)
end

def gross_profit_and_loss(trades)
  profits = trades.map { |t| t[:profit].to_f }

  [
    profits.select(&:positive?).sum,
    profits.select(&:negative?).sum.abs
  ]
end

def profit_factor_from_gross(gross_profit, gross_loss)
  return 999.0 if gross_loss.zero? && gross_profit > 0
  return 0.0 if gross_loss.zero?

  gross_profit / gross_loss
end

def avg_loss_magnitude(trades)
  losers = trades.select { |t| t[:profit].to_f < 0 }
  return nil if losers.empty?

  losers.sum { |t| t[:profit].to_f }.abs / losers.size
end

def projected_pf_if_next_n_losses(trades, loss_count)
  avg_loss = avg_loss_magnitude(trades)
  return nil if avg_loss.nil?

  gross_profit, gross_loss = gross_profit_and_loss(trades)
  profit_factor_from_gross(gross_profit, gross_loss + (loss_count * avg_loss))
end

def format_projected_pf(pf)
  return '' if pf.nil?
  return '999.00' if pf >= 999.0

  format('%.2f', pf)
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

def daily_net_profit_by_date(trades)
  trades.each_with_object({}) do |trade, totals|
    next if trade[:date].empty?

    date = parse_trade_date(trade[:date])
    totals[date] = (totals[date] || 0.0) + trade[:profit].to_f
  end
end

def no_trades_streaks(trades, first_date, last_date)
  return [] if first_date.nil? || last_date.nil?

  trade_dates = daily_net_profit_by_date(trades).keys.to_set
  streaks = []
  current_streak = 0
  date = first_date

  while date <= last_date
    if weekday?(date)
      if trade_dates.include?(date)
        streaks << current_streak if current_streak.positive?
        current_streak = 0
      else
        current_streak += 1
      end
    end

    date += 1
  end

  streaks << current_streak if current_streak.positive?
  streaks
end

def max_no_trades_streak(trades, first_date, last_date)
  streaks = no_trades_streaks(trades, first_date, last_date)
  streaks.empty? ? 0 : streaks.max
end

def avg_no_trades_streak(trades, first_date, last_date)
  streaks = no_trades_streaks(trades, first_date, last_date)
  return 0.0 if streaks.empty?

  streaks.sum.to_f / streaks.size
end

def max_loss_day_streak(trades, first_date, last_date)
  return 0 if first_date.nil? || last_date.nil?

  daily_net = daily_net_profit_by_date(trades)
  max_streak = 0
  current_streak = 0
  date = first_date

  while date <= last_date
    if weekday?(date)
      if daily_net.key?(date)
        if daily_net[date].negative?
          current_streak += 1
          max_streak = [max_streak, current_streak].max
        else
          current_streak = 0
        end
      end
    end

    date += 1
  end

  max_streak
end

def read_algo_shared_tp_sl(mq5_path)
  unless File.file?(mq5_path)
    $stderr.puts "ERROR: smashelito.mq5 not found: #{mq5_path}"
    exit 1
  end

  content = File.read(mq5_path, encoding: 'bom|utf-8')
  tp = content[/g_algoShared\.initialTP\s*=\s*([\d.]+)/, 1]
  sl = content[/g_algoShared\.initialSL\s*=\s*([\d.]+)/, 1]

  unless tp && sl
    $stderr.puts "ERROR: g_algoShared.initialTP / initialSL not found in #{mq5_path}"
    exit 1
  end

  [tp.to_f, sl.to_f]
end

def format_date(date)
  date&.strftime('%Y-%m-%d')
end

def build_csv_row(magic_prefix, trades, initial_tp, initial_sl, first_date, last_date, all_trading_day_count, include_projected_pf:)
  traded_days_count = unique_trade_days(trades).size

  {
    magicprefix: magic_prefix,
    tp: initial_tp,
    sl: initial_sl,
    profitfactor: format('%.2f', profit_factor(trades)),
    projected_PF_if_next_future_trade_is_a_loss: include_projected_pf ? format_projected_pf(projected_pf_if_next_n_losses(trades, 1)) : '',
    projected_PF_if_next_2_future_trades_is_a_loss: include_projected_pf ? format_projected_pf(projected_pf_if_next_n_losses(trades, 2)) : '',
    traderate: format('%.2f', trade_rate(trades, all_trading_day_count)),
    max_loseday_streak: max_loss_day_streak(trades, first_date, last_date),
    max_notrades_streak: max_no_trades_streak(trades, first_date, last_date),
    avg_notrades_streak: format('%.2f', avg_no_trades_streak(trades, first_date, last_date)),
    tradedDaysCount: traded_days_count,
    allDaysCount: all_trading_day_count,
    allDays_startDate: format_date(first_date),
    allDays_endDate: format_date(last_date)
  }
end

# =========================================================
# LOAD FILE
# =========================================================

$stderr.puts
$stderr.puts "Loading file: #{FILE_PATH}"
$stderr.puts "Reading TP/SL from: #{SMASHELITO_MQ5_PATH}"

initial_tp, initial_sl = read_algo_shared_tp_sl(SMASHELITO_MQ5_PATH)
$stderr.puts "g_algoShared.initialTP = #{initial_tp}, initialSL = #{initial_sl}"

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
if EXCLUDE_PREFIXES_MODE
  excluded = rows.count { |t| trade_excluded?(t) }
  $stderr.puts "EXCLUDE_PREFIXES_MODE: excluding prefixes #{excluded_prefixes.inspect} (#{excluded} trades dropped)"
end
$stderr.puts

rows_for_all_trades = apply_exclude_prefixes(rows)
magic_groups = rows_for_all_trades.group_by { |r| r[:magic_prefix] }
enabled_prefixes = magic_groups.keys.sort

csv_rows = [
  build_csv_row(
    "all(#{enabled_prefixes.join('-')})",
    rows_for_all_trades,
    initial_tp,
    initial_sl,
    first_date,
    last_date,
    all_trading_day_count,
    include_projected_pf: false
  )
]

enabled_prefixes.each do |magic_prefix|
  csv_rows << build_csv_row(
    magic_prefix,
    magic_groups[magic_prefix],
    initial_tp,
    initial_sl,
    first_date,
    last_date,
    all_trading_day_count,
    include_projected_pf: true
  )
end

# =========================================================
# OUTPUT CSV
# =========================================================

CSV.open(OUTPUT_CSV_PATH, 'w', write_headers: true, headers: CSV_HEADERS) do |out|
  csv_rows.each do |row|
    out << CSV_HEADERS.map { |h| row[h.to_sym] }
  end
end

$stderr.puts "Wrote #{csv_rows.size} rows to #{OUTPUT_CSV_PATH}"
$stderr.puts 'DONE'
