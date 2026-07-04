#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'date'

# =========================================================
# CONFIG
# =========================================================

FILE_PATH = 'summary_tradeResults_all_days.tsv'

EXCLUDE_PREFIXES_MODE = false
EXCLUDE_PREFIXES = [
  '11', '12', '13', '14', '15', '16', '17', '18', '19',
  '20', '21', '22', '23', '25', '26', '27', '30'
]

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

def parse_trade_date(date_str)
  Date.parse(date_str.gsub('.', '-'))
end

def format_date(date)
  format('%04d.%02d.%02d', date.year, date.month, date.day)
end

def monday_of_week(date)
  date - ((date.wday + 6) % 7)
end

def gross_profit_and_loss(trades)
  profits = trades.map { |t| t[:profit].to_f }
  [
    profits.select(&:positive?).sum,
    profits.select(&:negative?).sum.abs
  ]
end

def profit_factor_from_trades(trades)
  gross_profit, gross_loss = gross_profit_and_loss(trades)
  return 999.0 if gross_loss.zero? && gross_profit.positive?
  return 0.0 if gross_loss.zero?

  gross_profit / gross_loss
end

def format_profit_factor(pf)
  format('%.2f', pf)
end

def format_money(value)
  format('%.2f', value)
end

def aggregate_weeks(trades)
  grouped = trades.group_by { |t| monday_of_week(parse_trade_date(t[:date])) }

  grouped
    .map do |week_start, week_trades|
      net = week_trades.sum { |t| t[:profit].to_f }
      [week_start, net, week_trades]
    end
    .sort_by(&:first)
end

def print_week_by_week(weeks)
  return puts '(no traded weeks)' if weeks.empty?

  net_profit_total = 0.0
  week_pfs = []

  weeks.each do |week_start, net, week_trades|
    net_profit_total += net
    pf = profit_factor_from_trades(week_trades)
    week_pfs << { week_start: week_start, pf: pf }

    magic_prefixes_count = week_trades.map { |t| t[:magic_prefix] }.uniq.size

    puts format(
      '%s  net_profit_total=%s  net_profit_this_week=%s  profit_factor_this_week=%s  trade_count_this_week=%d  magic_prefixes_count_this_week=%d',
      format_date(week_start),
      format_money(net_profit_total),
      format_money(net),
      format_profit_factor(pf),
      week_trades.size,
      magic_prefixes_count
    )
  end

  print_pf_extremes(week_pfs)
  print_green_red_summary(weeks)
end

def print_pf_extremes(week_pfs)
  return if week_pfs.empty?

  max_pf = week_pfs.map { |w| w[:pf] }.max
  min_pf = week_pfs.map { |w| w[:pf] }.min
  max_count = week_pfs.count { |w| w[:pf] == max_pf }
  min_count = week_pfs.count { |w| w[:pf] == min_pf }

  puts
  puts format(
    'highest PF week: %s (%d week%s)',
    format_profit_factor(max_pf),
    max_count,
    max_count == 1 ? '' : 's'
  )
  puts format(
    'lowest PF week: %s (%d week%s)',
    format_profit_factor(min_pf),
    min_count,
    min_count == 1 ? '' : 's'
  )
end

def print_green_red_summary(weeks)
  green_weeks = weeks.select { |_, net, _| net.positive? }
  red_weeks = weeks.select { |_, net, _| net.negative? }

  green_nets = green_weeks.map { |_, net, _| net }
  red_nets = red_weeks.map { |_, net, _| net }

  green_sum = green_nets.sum
  green_avg = green_nets.empty? ? 0.0 : green_sum / green_nets.size
  best_green_week = green_weeks.max_by { |_, net, _| net }
  red_sum = red_nets.sum
  red_avg = red_nets.empty? ? 0.0 : red_sum / red_nets.size
  worst_red_week = red_weeks.min_by { |_, net, _| net }

  puts
  puts format('green_weeks_profit_sum: %s', format_money(green_sum))
  puts format('green_weeks_profit_avg: %s', format_money(green_avg))
  if best_green_week
    puts format(
      'best_green_week_profit: %s  week_start=%s',
      format_money(best_green_week[1]),
      format_date(best_green_week[0])
    )
  else
    puts 'best_green_week_profit: 0.00  week_start=n/a'
  end
  puts format('red_weeks_loss_sum: %s', format_money(red_sum))
  puts format('red_weeks_loss_avg: %s', format_money(red_avg))
  if worst_red_week
    puts format(
      'worst_red_week_loss: %s  week_start=%s',
      format_money(worst_red_week[1]),
      format_date(worst_red_week[0])
    )
  else
    puts 'worst_red_week_loss: 0.00  week_start=n/a'
  end
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

  date = row['date'].to_s.strip
  next if date.empty?

  rows << {
    magic_prefix: magic[0, 3],
    date: date,
    profit: row['profit'].to_f
  }
end

if rows.empty?
  $stderr.puts 'ERROR: No trades loaded.'
  exit 1
end

rows = apply_exclude_prefixes(rows)
if rows.empty?
  $stderr.puts 'ERROR: No trades left after prefix exclusions.'
  exit 1
end

$stderr.puts "Loaded trades: #{rows.size}"
if EXCLUDE_PREFIXES_MODE
  $stderr.puts "EXCLUDE_PREFIXES_MODE: excluding prefixes #{excluded_prefixes.inspect}"
end
$stderr.puts

weekly_periods = aggregate_weeks(rows)
print_week_by_week(weekly_periods)
