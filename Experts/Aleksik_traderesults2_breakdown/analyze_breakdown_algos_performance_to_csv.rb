#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'date'
require 'set'
require_relative '../Aleksik_traderesults/analyze_traderate_common'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
INPUT_PATH = File.join(SCRIPT_DIR, 'summary_tradeResults_all_days_breakdown.tsv')
OUTPUT_PATH = File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_output.csv')

CSV_HEADERS = %w[
  algoID
  firstTradeDate
  lastTradeDate
  tradesCount
  tradedDaysCount
  max_notrades_streak
  avg_notrades_streak
  avgMFE_w_roll
  avgMAE_w_roll
  avgDurationHours
  longestDurationHours
  longestDurationDays
  avgFillDelaySeconds
  avg_profit_custom_with_roll
  avg_time_at_peak_exposure_hours
  timeVSprofit
  max_time_at_peak_exposure_hours
  max_time_at_peak_exposure_days
  traderate
  weekly_traderate
  avg_open_exposure
  peak_open_exposure
].freeze

def parse_mt_datetime(value)
  text = value.to_s.strip
  return nil if text.empty?

  DateTime.strptime(text, '%Y.%m.%d %H:%M:%S')
rescue ArgumentError
  nil
end

def parse_float(value)
  text = value.to_s.strip
  return nil if text.empty?

  Float(text)
rescue ArgumentError, TypeError
  nil
end

def format_float(value, decimals = 4)
  return '' if value.nil?

  format("%.#{decimals}f", value)
end

def format_date(date)
  return '' if date.nil?

  date.strftime('%Y.%m.%d')
end

def load_trades(path)
  raw = File.read(path, encoding: 'bom|utf-8')
  table = CSV.parse(raw, headers: true, col_sep: ',')

  trades = []
  table.each do |row|
    algo_id = row['algoID'].to_s.strip
    next if algo_id.empty?

    start_time = parse_mt_datetime(row['startTime'])
    end_time = parse_mt_datetime(row['endTime'])
    sent_time = parse_mt_datetime(row['sentTime'])
    trade_date = row['date'].to_s.strip

    trades << {
      algo_id: algo_id,
      date: trade_date,
      sent_time: sent_time,
      start_time: start_time,
      end_time: end_time,
      duration_hours: parse_float(row['durationHours']),
      profit_custom_with_roll: parse_float(row['profit_custom_with_roll']) || 0.0,
      mfe_w_roll: parse_float(row['MFE_w_roll']),
      mae_w_roll: parse_float(row['MAE_w_roll'])
    }
  end

  trades
end

def average(values)
  nums = values.compact
  return nil if nums.empty?

  nums.sum.to_f / nums.size
end

def fill_delay_seconds(trade)
  return nil unless trade[:sent_time] && trade[:start_time]

  # sentTime = pending ORDER_TIME_SETUP; startTime = IN deal fill time
  (trade[:start_time] - trade[:sent_time]) * 86_400
end

MIN_DURATION_HOURS = 0.000001

def duration_hours_from_column(trade)
  duration = trade[:duration_hours]
  return nil if duration.nil? || duration.negative?

  duration
end

def trade_time_label(trade)
  start_s = trade[:start_time] ? trade[:start_time].strftime('%Y.%m.%d %H:%M:%S') : '(missing)'
  end_s = trade[:end_time] ? trade[:end_time].strftime('%Y.%m.%d %H:%M:%S') : '(missing)'
  "startTime=#{start_s} endTime=#{end_s}"
end

def duration_hours_from_times(trade)
  return nil unless trade[:start_time] && trade[:end_time]

  hours = (trade[:end_time] - trade[:start_time]) * 24
  hours.negative? ? nil : hours
end

def duration_hours_for_time_vs_profit!(trade)
  hours = duration_hours_from_times(trade)
  hours = trade[:duration_hours] if hours.nil?

  if hours.nil?
    raise "ERROR: timeVSprofit: durationHours missing for algo #{trade[:algo_id]} #{trade_time_label(trade)}"
  end
  if hours < MIN_DURATION_HOURS
    raise "ERROR: timeVSprofit: durationHours=#{hours} < #{MIN_DURATION_HOURS} for algo #{trade[:algo_id]} #{trade_time_label(trade)}"
  end

  hours
end

def time_vs_profit(trades)
  return nil if trades.empty?

  profits = trades.map { |trade| trade[:profit_custom_with_roll].to_f }
  hours_list = trades.map { |trade| duration_hours_for_time_vs_profit!(trade) }

  avg_profit = average(profits)
  avg_hours = average(hours_list)
  return nil if avg_profit.nil? || avg_hours.nil? || avg_hours < MIN_DURATION_HOURS

  avg_profit / avg_hours
end

def day_range(date)
  start = DateTime.new(date.year, date.month, date.day, 0, 0, 0)
  [start, start + 1]
end

def build_open_close_events(trades, range_start = nil, range_end = nil)
  events = []

  trades.each do |trade|
    start_time = trade[:start_time]
    end_time = trade[:end_time]
    next unless start_time && end_time && end_time > start_time

    start_t = start_time.to_time
    end_t = end_time.to_time
    next if range_end && start_t >= range_end
    next if range_start && end_t <= range_start

    clip_start = range_start ? [start_t, range_start].max : start_t
    clip_end = range_end ? [end_t, range_end].min : end_t
    next unless clip_end > clip_start

    events << [clip_start, 1]
    events << [clip_end, -1]
  end

  events.sort_by { |time, delta| [time, -delta] }
end

def max_concurrent_open(trades, range_start = nil, range_end = nil)
  events = build_open_close_events(trades, range_start, range_end)
  count = 0
  max_count = 0

  events.each do |_time, delta|
    count += delta
    max_count = [max_count, count].max
  end

  max_count
end

def peak_exposure_time_stats(trades)
  events = build_open_close_events(trades)
  return { peak: 0, max_hours: 0.0, avg_hours: 0.0 } if events.empty?

  count = 0
  peak = 0
  events.each { |_time, delta| count += delta; peak = [peak, count].max }
  return { peak: 0, max_hours: 0.0, avg_hours: 0.0 } if peak.zero?

  count = 0
  in_peak = false
  peak_start = nil
  peak_intervals = []

  events.each do |time, delta|
    count += delta
    if !in_peak && count == peak
      in_peak = true
      peak_start = time
    elsif in_peak && count < peak
      peak_intervals << (time - peak_start)
      in_peak = false
      peak_start = nil
    end
  end

  return { peak: peak, max_hours: 0.0, avg_hours: 0.0 } if peak_intervals.empty?

  max_seconds = peak_intervals.max
  avg_seconds = peak_intervals.sum.to_f / peak_intervals.size
  {
    peak: peak,
    max_hours: max_seconds / 3600.0,
    avg_hours: avg_seconds / 3600.0
  }
end

def open_days_for_algo(trades)
  trades
    .map { |trade| parse_trade_date(trade[:date]) }
    .compact
    .uniq
end

def avg_open_exposure(trades)
  days = open_days_for_algo(trades)
  return 0.0 if days.empty?

  daily_peaks =
    days.map do |date|
      day_start, day_end = day_range(date)
      max_concurrent_open(trades, day_start.to_time, day_end.to_time)
    end

  daily_peaks.sum.to_f / daily_peaks.size
end

def peak_open_exposure(trades)
  daily_peaks =
    open_days_for_algo(trades).map do |date|
      day_start, day_end = day_range(date)
      max_concurrent_open(trades, day_start.to_time, day_end.to_time)
    end

  return 0 if daily_peaks.empty?

  daily_peaks.max
end

def build_algo_row(algo_id, trades, global_first_date, global_last_date, global_trading_day_count, global_full_week_mondays)
  first_date, last_date, = trade_date_range(trades)
  exposure_stats = peak_exposure_time_stats(trades)
  durations = trades.filter_map { |t| duration_hours_from_column(t) }
  longest_duration_hours = durations.max

  {
    algoID: algo_id,
    firstTradeDate: format_date(first_date),
    lastTradeDate: format_date(last_date),
    tradesCount: trades.size,
    tradedDaysCount: countable_unique_trade_days(trades).size,
    max_notrades_streak: max_no_trades_streak(trades, global_first_date, global_last_date),
    avg_notrades_streak: format_float(avg_no_trades_streak(trades, global_first_date, global_last_date), 2),
    avgMFE_w_roll: format_float(average(trades.map { |t| t[:mfe_w_roll] }), 1),
    avgMAE_w_roll: format_float(average(trades.map { |t| t[:mae_w_roll] }), 1),
    avgDurationHours: format_float(average(durations), 2),
    longestDurationHours: format_float(longest_duration_hours, 2),
    longestDurationDays: format_float(longest_duration_hours.nil? ? nil : longest_duration_hours / 24.0, 2),
    avgFillDelaySeconds: format_float(average(trades.map { |t| fill_delay_seconds(t) }), 2),
    avg_profit_custom_with_roll: format_float(average(trades.map { |t| t[:profit_custom_with_roll] }), 2),
    avg_time_at_peak_exposure_hours: format_float(exposure_stats[:avg_hours], 2),
    timeVSprofit: format_float(time_vs_profit(trades), 3),
    max_time_at_peak_exposure_hours: format_float(exposure_stats[:max_hours], 2),
    max_time_at_peak_exposure_days: format_float(exposure_stats[:max_hours] / 24.0, 2),
    traderate: format_float(trade_rate(trades, global_trading_day_count), 2),
    weekly_traderate: format_float(weekly_trade_rate(trades, global_full_week_mondays), 2),
    avg_open_exposure: format_float(avg_open_exposure(trades), 2),
    peak_open_exposure: peak_open_exposure(trades)
  }
end

def no_trades_streaks(trades, first_date, last_date)
  return [] if first_date.nil? || last_date.nil?

  trade_dates = countable_unique_trade_days(trades).to_set
  streaks = []
  current_streak = 0
  date = first_date

  while date <= last_date
    if countable_weekday?(date)
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

# =========================================================
# MAIN
# =========================================================

unless File.file?(INPUT_PATH)
  warn "ERROR: input file not found: #{INPUT_PATH}"
  exit 1
end

warn "Loading: #{INPUT_PATH}"
trades = load_trades(INPUT_PATH)
if trades.empty?
  warn 'ERROR: no trades loaded.'
  exit 1
end

global_first_date, global_last_date, global_trading_day_count = trade_date_range(trades)
global_full_week_mondays = countable_mon_fri_weeks_in_date_range(global_first_date, global_last_date)

print_loaded_trade_span_summary(
  trade_count: trades.size,
  first_date: global_first_date,
  last_date: global_last_date,
  trading_day_count: global_trading_day_count,
  full_week_mondays: global_full_week_mondays,
  io: $stderr
)

rows =
  trades
    .group_by { |trade| trade[:algo_id] }
    .sort_by { |algo_id, _| algo_id.to_i }
    .map { |algo_id, algo_trades| build_algo_row(algo_id, algo_trades, global_first_date, global_last_date, global_trading_day_count, global_full_week_mondays) }

CSV.open(OUTPUT_PATH, 'w', write_headers: true, headers: CSV_HEADERS) do |csv|
  rows.each do |row|
    csv << CSV_HEADERS.map { |header| row[header.to_sym] }
  end
end

warn "Wrote #{rows.size} algo rows to #{OUTPUT_PATH}"
warn 'DONE'
