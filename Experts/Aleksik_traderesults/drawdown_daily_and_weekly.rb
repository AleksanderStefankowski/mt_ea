#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'date'

# =========================================================
# CONFIG
# =========================================================

FILE_PATH = 'summary_tradeResults_all_days.tsv'

EXCLUDE_PREFIXES_MODE = true
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

def format_profit_factor(trades)
  return 'n/a' if trades.empty?

  pf = profit_factor_from_trades(trades)
  pf >= 999.0 ? '999.00 (no losses)' : format('%.2f', pf)
end

def format_money(value)
  format('%.2f', value)
end

def drawdown_pct(max_drawdown_abs, peak_equity)
  return nil if peak_equity <= 0.0

  (max_drawdown_abs / peak_equity) * 100.0
end

def format_drawdown_pct(pct)
  pct.nil? ? 'n/a (ATH <= 0)' : format('%.2f%%', pct)
end

def aggregate_periods(trades, key_fn)
  grouped = trades.group_by { |t| key_fn.call(parse_trade_date(t[:date])) }

  grouped
    .map do |key, period_trades|
      net = period_trades.sum { |t| t[:profit].to_f }
      [key, net, period_trades]
    end
    .sort_by(&:first)
end

def build_profit_streaks(periods)
  streaks = []

  periods.each do |key, net, period_trades|
    sign = net.positive? ? :positive : :negative
    if streaks.empty? || streaks.last[:sign] != sign
      streaks << { sign: sign, start: key, entries: [[key, net, period_trades]] }
    else
      streaks.last[:entries] << [key, net, period_trades]
    end
  end

  streaks
end

def green_streak_episodes(periods)
  build_profit_streaks(periods)
    .select { |streak| streak[:sign] == :positive }
    .map do |streak|
      all_trades = streak[:entries].flat_map { |_, _, ts| ts }
      {
        length: streak[:entries].size,
        total_profit: streak[:entries].sum { |_, net, _| net },
        trades: all_trades
      }
    end
end

def print_profit_streaks(periods, unit_label)
  return puts '  (no traded periods)' if periods.empty?

  build_profit_streaks(periods).each do |streak|
    all_trades = streak[:entries].flat_map { |_, _, ts| ts }
    total_profit = streak[:entries].sum { |_, net, _| net }
    kind = streak[:sign] == :positive ? 'PROFIT' : 'LOSS'
    puts format(
      '  %s streak  start=%s  length=%d %s  profit=%s  PF=%s',
      kind,
      format_date(streak[:start]),
      streak[:entries].size,
      unit_label,
      format_money(total_profit),
      format_profit_factor(all_trades)
    )
  end
end

def print_green_streak_summary(episodes, length_unit)
  note = length_unit.include?('week') ? 'non-trade weeks not counted' : 'non-trade days not counted'

  if episodes.empty?
    puts format('  (lengths are %s only; %s)', length_unit, note)
    puts '  max green streak length: 0'
    puts '  max green streak profit: 0.00'
    puts '  max green streak PF: n/a'
    puts format('  avg green streak length: 0.00 %s', length_unit)
    puts '  avg green streak profit: 0.00'
    puts '  avg green streak PF: n/a'
    return
  end

  lengths = episodes.map { |e| e[:length] }
  profits = episodes.map { |e| e[:total_profit] }
  pfs = episodes.map { |e| profit_factor_from_trades(e[:trades]) }

  max_len = lengths.max
  avg_len = lengths.sum.to_f / lengths.size
  max_profit = profits.max
  avg_profit = profits.sum / profits.size
  max_pf = pfs.max
  avg_pf = pfs.sum / pfs.size

  format_pf = lambda do |pf|
    pf >= 999.0 ? '999.00 (no losses)' : format('%.2f', pf)
  end

  puts format('  (lengths are %s only; %s)', length_unit, note)
  puts format('  max green streak length: %d %s', max_len, length_unit)
  puts format('  max green streak profit: %s', format_money(max_profit))
  puts format('  max green streak PF: %s', format_pf.call(max_pf))
  puts format('  avg green streak length: %.2f %s', avg_len, length_unit)
  puts format('  avg green streak profit: %s', format_money(avg_profit))
  puts format('  avg green streak PF: %s', format_pf.call(avg_pf))
end

def print_drawdowns(periods, unit_label)
  return puts '  (no traded periods)', [] if periods.empty?

  equity = 0.0
  ath = 0.0
  in_drawdown = false
  dd_start_key = nil
  dd_peak = 0.0
  dd_max_abs = 0.0
  dd_length = 0
  episodes = []

  periods.each do |key, net, _|
    equity += net

    if in_drawdown
      dd_length += 1
      dd_max_abs = [dd_max_abs, dd_peak - equity].max

      if equity > ath
        pct = drawdown_pct(dd_max_abs, dd_peak)
        puts format(
          '  DRAWDOWN END   %s  max_drawdown=%s  max_drawdown_pct=%s  length=%d %s',
          format_date(key),
          format_money(dd_max_abs),
          format_drawdown_pct(pct),
          dd_length,
          unit_label
        )
        episodes << { length: dd_length, max_pct: pct, max_abs: dd_max_abs }
        in_drawdown = false
        ath = equity
      end
    elsif equity > ath
      ath = equity
    elsif equity < ath
      in_drawdown = true
      dd_start_key = key
      dd_peak = ath
      dd_max_abs = dd_peak - equity
      dd_length = 1
      puts format(
        '  DRAWDOWN START %s  ATH=%s',
        format_date(dd_start_key),
        format_money(dd_peak)
      )
    end
  end

  if in_drawdown
    pct = drawdown_pct(dd_max_abs, dd_peak)
    puts format(
      '  DRAWDOWN OPEN  start=%s  max_drawdown=%s  max_drawdown_pct=%s  length=%d %s  (no new ATH before end of data)',
      format_date(dd_start_key),
      format_money(dd_max_abs),
      format_drawdown_pct(pct),
      dd_length,
      unit_label
    )
    episodes << { length: dd_length, max_pct: pct, max_abs: dd_max_abs }
  end

  episodes
end

def print_drawdown_summary(episodes, length_unit)
  note = length_unit.include?('week') ? 'non-trade weeks not counted' : 'non-trade days not counted'

  if episodes.empty?
    puts format('  (lengths are %s only; %s)', length_unit, note)
    puts '  max drawdown length: 0'
    puts '  max drawdown %: n/a'
    puts format('  avg drawdown length: 0.00 %s', length_unit)
    puts '  avg drawdown %: n/a'
    return
  end

  lengths = episodes.map { |e| e[:length] }
  pcts = episodes.map { |e| e[:max_pct] }.compact

  max_len = lengths.max
  avg_len = lengths.sum.to_f / lengths.size
  max_pct = pcts.empty? ? nil : pcts.max
  avg_pct = pcts.empty? ? nil : (pcts.sum / pcts.size)

  puts format('  (lengths are %s only; %s)', length_unit, note)
  puts format('  max drawdown length: %d %s', max_len, length_unit)
  puts format('  max drawdown %%: %s', format_drawdown_pct(max_pct))
  puts format('  avg drawdown length: %.2f %s', avg_len, length_unit)
  puts format('  avg drawdown %%: %s', format_drawdown_pct(avg_pct))
end

def analyze_section(title, periods, unit_label, length_unit)
  puts
  puts '=' * 72
  puts title
  puts '=' * 72
  puts
  puts '--- Profit / loss streaks (traded periods only) ---'
  print_profit_streaks(periods, unit_label)
  puts
  puts '--- Green streak summary ---'
  print_green_streak_summary(green_streak_episodes(periods), length_unit)
  puts
  puts '--- Drawdowns (ends only on new cumulative-profit ATH) ---'
  episodes = print_drawdowns(periods, unit_label)
  puts
  puts '--- Summary ---'
  print_drawdown_summary(episodes, length_unit)
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

daily_periods = aggregate_periods(rows, ->(date) { date })
weekly_periods = aggregate_periods(rows, ->(date) { monday_of_week(date) })

analyze_section('DAILY', daily_periods, 'days', 'traded days')
analyze_section('WEEKLY', weekly_periods, 'weeks', 'traded weeks')
