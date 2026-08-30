#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'alert_done_common'

require 'csv'
require 'date'
require 'set'
require_relative '../Aleksik_traderesults/analyze_traderate_common'

self.traderate_account_for_banned_days = false

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
INPUT_PATH = File.join(SCRIPT_DIR, 'summary_tradeResults_all_days_breakdown.tsv')
TOP_N = 5

def parse_mt_datetime(value)
  text = value.to_s.strip
  return nil if text.empty?

  DateTime.strptime(text, '%Y.%m.%d %H:%M:%S')
rescue ArgumentError
  nil
end

def format_mt_datetime(time)
  return '(missing)' if time.nil?

  time.strftime('%Y.%m.%d %H:%M:%S')
end

def format_date(date)
  return '(missing)' if date.nil?

  date.strftime('%Y.%m.%d')
end

def trade_send_time(trade)
  trade[:sent_time] || trade[:start_time]
end

def load_trades(path)
  raw = File.read(path, encoding: 'bom|utf-8')
  table = CSV.parse(raw, headers: true, col_sep: ',')

  trades = []
  table.each do |row|
    algo_id = row['algoID'].to_s.strip
    next if algo_id.empty?

    trades << {
      algo_id: algo_id,
      date: row['date'].to_s.strip,
      sent_time: parse_mt_datetime(row['sentTime']),
      start_time: parse_mt_datetime(row['startTime']),
      end_time: parse_mt_datetime(row['endTime'])
    }
  end

  trades
end

def valid_open_trades(trades)
  trades.select do |trade|
    trade[:start_time] && trade[:end_time] && trade[:end_time] > trade[:start_time]
  end
end

def build_concurrency_events(trades)
  valid = valid_open_trades(trades)
  events = []
  valid.each_with_index do |trade, idx|
    events << { time: trade[:start_time].to_time, delta: 1, trade_idx: idx }
    events << { time: trade[:end_time].to_time, delta: -1, trade_idx: idx }
  end
  events.sort_by! { |event| [event[:time], -event[:delta]] }
  [valid, events]
end

def concurrency_intervals(trades)
  valid, events = build_concurrency_events(trades)
  return [] if events.empty?

  intervals = []
  active = Set.new
  count = 0
  last_time = nil

  events.each do |event|
    time = event[:time]
    if last_time && time > last_time && count.positive?
      intervals << {
        start: last_time,
        end: time,
        count: count,
        active_trade_idxs: active.to_a
      }
    end

    if event[:delta] == 1
      active.add(event[:trade_idx])
    else
      active.delete(event[:trade_idx])
    end
    count += event[:delta]
    last_time = time
  end

  merge_adjacent_intervals(valid, intervals)
end

def merge_adjacent_intervals(valid_trades, intervals)
  return [] if intervals.empty?

  sorted = intervals.sort_by { |interval| [interval[:start], interval[:count]] }
  merged = [sorted.first.dup]

  sorted[1..].each do |interval|
    last = merged.last
    if interval[:count] == last[:count] && interval[:start] == last[:end]
      last[:end] = interval[:end]
    else
      merged << interval.dup
    end
  end

  merged.each do |interval|
    interval[:active_trades] = interval[:active_trade_idxs].map { |idx| valid_trades[idx] }
    interval.delete(:active_trade_idxs)
  end

  merged
end

def stack_period_summary(_trades, interval, algo_id: nil)
  active_trades = interval[:active_trades] || []
  send_times = active_trades.map { |trade| trade_send_time(trade) }.compact
  end_times = active_trades.map { |trade| trade[:end_time] }.compact

  earliest_send = send_times.min
  latest_end = end_times.max
  day_before_earliest_send = earliest_send ? earliest_send.to_date - 1 : nil
  last_finish_day = latest_end ? latest_end.to_date : nil

  {
    algo_id: algo_id,
    stacked_count: interval[:count],
    algo_count: active_trades.map { |trade| trade[:algo_id] }.uniq.size,
    trade_count: active_trades.size,
    day_before_earliest_send: day_before_earliest_send,
    last_finish_day: last_finish_day,
    interval_start: interval[:start],
    interval_end: interval[:end],
    earliest_send: earliest_send,
    latest_end: latest_end
  }
end

def collapse_to_daily_peak_intervals(intervals)
  intervals
    .group_by { |interval| interval[:start].to_date }
    .map do |_date, day_intervals|
      day_intervals.max_by { |interval| [interval[:count], interval[:end].to_i - interval[:start].to_i] }
    end
end

def rank_stack_summaries(summaries)
  summaries.sort_by do |summary|
    [
      -summary[:stacked_count],
      -summary[:interval_start].to_i,
      summary[:interval_end].to_i
    ]
  end
end

def top_stack_periods(trades, limit = TOP_N, algo_id: nil)
  intervals = collapse_to_daily_peak_intervals(concurrency_intervals(trades))
  return [] if intervals.empty?

  rank_stack_summaries(
    intervals.map { |interval| stack_period_summary(trades, interval, algo_id: algo_id) }
  ).first(limit)
end

def top_per_algo_stack_periods(trades_by_algo, limit = TOP_N)
  candidates =
    trades_by_algo.filter_map do |algo_id, algo_trades|
      summary = top_stack_periods(algo_trades, 1, algo_id: algo_id).first
      summary if summary && summary[:stacked_count] >= 2
    end

  rank_stack_summaries(candidates).first(limit)
end

def print_stack_period(label, rank, summary, show_algo: false)
  puts "#{label} ##{rank}"
  puts "  algoID: #{summary[:algo_id]}" if show_algo && summary[:algo_id]
  puts "  stacked_trades_at_peak: #{summary[:stacked_count]}"
  puts "  algos_at_peak: #{summary[:algo_count]}"
  puts "  trades_at_peak: #{summary[:trade_count]}"
  puts "  day_before_earliest_send: #{format_date(summary[:day_before_earliest_send])}"
  puts "  last_finish_day: #{format_date(summary[:last_finish_day])}"
  puts "  peak_interval: #{format_mt_datetime(summary[:interval_start])} -> #{format_mt_datetime(summary[:interval_end])}"
  puts "  earliest_send: #{format_mt_datetime(summary[:earliest_send])}"
  puts "  latest_end: #{format_mt_datetime(summary[:latest_end])}"
  puts
end

def print_top_stack_periods(title, periods, show_algo: false)
  puts title
  puts '=' * title.length
  if periods.empty?
    puts '(none)'
    puts
    return
  end

  periods.each_with_index do |summary, index|
    print_stack_period('Rank', index + 1, summary, show_algo: show_algo)
  end
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

global_top = top_stack_periods(trades, TOP_N)
print_top_stack_periods("Top #{TOP_N} global stack periods (all algos together)", global_top)

trades_by_algo = trades.group_by { |trade| trade[:algo_id] }
per_algo_top = top_per_algo_stack_periods(trades_by_algo, TOP_N)
print_top_stack_periods("Top #{TOP_N} per-algo stack periods (single algo)", per_algo_top, show_algo: true)

warn 'DONE'

play_alert_done! if __FILE__ == $PROGRAM_NAME
