#!/usr/bin/env ruby

require 'csv'
require 'date'
require 'set'
require_relative 'analyze_traderate_common'
# =========================================================
# CONFIG
# =========================================================

FILE_PATH = 'summary_tradeResults_all_days.tsv'

# =========================================================
# HELPERS
# =========================================================
EXCLUDE_PREFIXES_MODE = false
# EXCLUDE_PREFIXES = ["19", "20", "21", "22", "25", "26", "27"]  # magic first 2 digits; comma in one string also works, e.g. "20, 24"
EXCLUDE_PREFIXES = [
    "11"
]

INCLUDE_PREFIXES_MODE = false # one magic prefix per line below (no commas)
INCLUDE_PREFIXES = <<~INCLUDE_PREFIXES
121
124
129
138
142
120
133
127
155
157
130
141
144
206
171
174
192
182
189
268
226
137
162
153
183
INCLUDE_PREFIXES

CHECK_ONLY_A_DATERANGE = false
CHECK_ONLY_A_DATERANGE_LATEST_X_WEEKS = 15

def excluded_prefixes
  EXCLUDE_PREFIXES
    .flat_map { |p| p.to_s.split(',') }
    .map(&:strip)
    .reject(&:empty?)
end

def normalize_magic_prefix(value)
  value.to_s.strip.rjust(3, '0')
end

def included_prefixes
  INCLUDE_PREFIXES
    .lines
    .map(&:strip)
    .reject(&:empty?)
    .reject { |line| line.start_with?('#') }
    .map { |p| normalize_magic_prefix(p) }
    .uniq
end

def trade_excluded?(trade)
  EXCLUDE_PREFIXES_MODE && excluded_prefixes.include?(trade[:magic_prefix])
end

def trade_included?(trade)
  included_prefixes.include?(trade[:magic_prefix])
end

def apply_include_prefixes(trades)
  return trades unless INCLUDE_PREFIXES_MODE

  trades.select { |t| trade_included?(t) }
end

def apply_exclude_prefixes(trades)
  return trades unless EXCLUDE_PREFIXES_MODE

  trades.reject { |t| trade_excluded?(t) }
end

def apply_prefix_filters(trades)
  apply_exclude_prefixes(apply_include_prefixes(trades))
end

def print_include_prefixes_summary(before_count, after_count, trades, io: $stderr)
  return unless INCLUDE_PREFIXES_MODE

  prefixes = included_prefixes
  found_prefixes = trades.map { |t| t[:magic_prefix] }.uniq.sort
  missing_prefixes = prefixes - found_prefixes

  io.puts format(
    'INCLUDE_PREFIXES_MODE: keeping prefixes %s (%d trades kept from %d)',
    prefixes.join(', '),
    after_count,
    before_count
  )
  io.puts "Included prefixes with trades (#{found_prefixes.size}): #{found_prefixes.join(', ')}" if found_prefixes.any?
  if missing_prefixes.any?
    io.puts "Included prefixes with no trades (#{missing_prefixes.size}): #{missing_prefixes.join(', ')}"
  end
end

def apply_latest_weeks_date_filter(trades, week_count)
  return trades if week_count.nil? || week_count <= 0

  _, last_date, = trade_date_range(trades)
  return trades if last_date.nil?

  filter_start = monday_of_week(last_date) - ((week_count - 1) * 7)

  trades.select do |trade|
    trade_date = parse_trade_date(trade[:date])
    trade_date && trade_date >= filter_start && trade_date <= last_date
  end
end

def apply_date_range_filter(trades)
  return trades unless CHECK_ONLY_A_DATERANGE

  apply_latest_weeks_date_filter(trades, CHECK_ONLY_A_DATERANGE_LATEST_X_WEEKS)
end

def print_date_range_filter_summary(before_count, after_count, filtered_first_date, filtered_last_date, io: $stderr)
  return unless CHECK_ONLY_A_DATERANGE

  io.puts format(
    'CHECK_ONLY_A_DATERANGE: latest %d weeks (%s .. %s), %d trades kept from %d',
    CHECK_ONLY_A_DATERANGE_LATEST_X_WEEKS,
    format_trade_span_date(filtered_first_date),
    format_trade_span_date(filtered_last_date),
    after_count,
    before_count
  )
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

def avg_win_magnitude(trades)
  winners = trades.select { |t| t[:profit].to_f > 0 }
  return nil if winners.empty?

  winners.sum { |t| t[:profit].to_f } / winners.size
end

def projected_pf_if_next_n_wins(trades, win_count)
  avg_win = avg_win_magnitude(trades)
  return nil if avg_win.nil?

  gross_profit, gross_loss = gross_profit_and_loss(trades)
  profit_factor_from_gross(gross_profit + (win_count * avg_win), gross_loss)
end

def projected_pf_if_next_n_losses(trades, loss_count)
  avg_loss = avg_loss_magnitude(trades)
  return nil if avg_loss.nil?

  gross_profit, gross_loss = gross_profit_and_loss(trades)
  profit_factor_from_gross(gross_profit, gross_loss + (loss_count * avg_loss))
end

def format_projected_pf(pf, empty_reason: 'no losing trades')
  return "n/a (#{empty_reason})" if pf.nil?
  return '999.00 (no losses)' if pf >= 999.0

  format('%.2f', pf)
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

def format_profit_factor(trades)
  return 'n/a (no trades)' if trades.empty?

  pf = profit_factor(trades)
  pf >= 999.0 ? '999.00 (no losses)' : format('%.2f', pf)
end

def print_summary(label, trades, first_date, last_date, total_trading_days, full_week_mondays, include_projected_pf: true)
  winners = trades.select { |t| t[:profit].to_f > 0 }
  losers = trades.select { |t| t[:profit].to_f < 0 }

  puts label
  puts format('  trades: %d', trades.size)
  puts format('  trade rate: %.2f (%d / %d countable weekdays)', trade_rate(trades, total_trading_days), countable_unique_trade_days(trades).size, total_trading_days)
  puts format(
    '  weekly trade rate: %.2f (%d / %d countable Mon-Fri weeks)',
    weekly_trade_rate(trades, full_week_mondays),
    traded_full_week_count(trades, full_week_mondays),
    full_week_mondays.size
  )
  puts format('  max no-trades streak: %d weekdays', max_no_trades_streak(trades, first_date, last_date))
  puts format('  avg no-trades streak: %.2f weekdays', avg_no_trades_streak(trades, first_date, last_date))
  puts format('  max loss-day streak: %d weekdays', max_loss_day_streak(trades, first_date, last_date))
  puts format('  winrate: %.2f%%', winrate(trades))
  puts format('  profit factor: %.2f', profit_factor(trades))
  if include_projected_pf
    puts format(
      '  projected PF if next future trade is a win: %s',
      format_projected_pf(projected_pf_if_next_n_wins(trades, 1), empty_reason: 'no winning trades')
    )
    puts format('  projected PF if next future trade is a loss: %s', format_projected_pf(projected_pf_if_next_n_losses(trades, 1)))
    puts format('  projected PF if next 2 future trades are a loss: %s', format_projected_pf(projected_pf_if_next_n_losses(trades, 2)))
  end
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
    magic_prefix: magic[0, 3],
    date: row['date'].to_s.strip,
    profit: row['profit'].to_f
  }
end

if rows.empty?
  $stderr.puts 'ERROR: No trades loaded.'
  exit 1
end

loaded_trade_count = rows.size
rows = apply_date_range_filter(rows)

if rows.empty?
  $stderr.puts 'ERROR: No trades left after date-range filter.'
  exit 1
end

first_date, last_date, all_trading_day_count = trade_date_range(rows)

all_full_week_mondays =
  countable_mon_fri_weeks_in_date_range(first_date, last_date)

print_loaded_trade_span_summary(
  trade_count: rows.size,
  first_date: first_date,
  last_date: last_date,
  trading_day_count: all_trading_day_count,
  full_week_mondays: all_full_week_mondays,
  io: $stderr
)
print_date_range_filter_summary(loaded_trade_count, rows.size, first_date, last_date)
$stderr.puts "Days with any trade in file: #{unique_trade_days(rows).size}"

prefix_filter_before_count = rows.size
rows_for_all_trades = apply_prefix_filters(rows)

if rows_for_all_trades.empty?
  $stderr.puts 'ERROR: No trades left after prefix filter.'
  exit 1
end

print_include_prefixes_summary(prefix_filter_before_count, rows_for_all_trades.size, rows_for_all_trades)

if EXCLUDE_PREFIXES_MODE
  excluded = rows.count { |t| trade_excluded?(t) }
  $stderr.puts "EXCLUDE_PREFIXES_MODE: excluding prefixes #{excluded_prefixes.inspect} (#{excluded} trades dropped from ALL TRADES output)"
end
$stderr.puts

# =========================================================
# OUTPUT
# =========================================================

puts '-' * 60
puts 'BY MAGIC PREFIX (first 3 digits)'
puts '-' * 60
puts

magic_groups = rows_for_all_trades.group_by { |r| r[:magic_prefix] }

magic_groups.keys.sort.each do |magic_prefix|
  print_summary("Magic prefix #{magic_prefix}", magic_groups[magic_prefix], first_date, last_date, all_trading_day_count, all_full_week_mondays)
end

puts '-' * 60
puts 'ALL TRADES'
puts '-' * 60
puts

print_summary('Overall', rows_for_all_trades, first_date, last_date, all_trading_day_count, all_full_week_mondays, include_projected_pf: false)

print_excluded_prefixes_footer(rows)

$stderr.puts 'DONE'
