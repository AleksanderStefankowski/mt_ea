# frozen_string_literal: true

require 'date'
require 'set'
require_relative 'aleksik_non_trade_calendar'

def weekday?(date)
  !date.saturday? && !date.sunday?
end

def parse_trade_date(date_str)
  return nil if date_str.nil? || date_str.to_s.strip.empty?

  Date.strptime(date_str.to_s.strip, '%Y.%m.%d')
rescue ArgumentError
  nil
end

def countable_weekday?(date)
  weekday?(date) && !AleksikNonTradeCalendar.non_trade_date?(date)
end

def countable_weekday_count_in_range(first_date, last_date)
  return 0 if first_date.nil? || last_date.nil?

  count = 0
  date = first_date
  while date <= last_date
    count += 1 if countable_weekday?(date)
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
      .compact

  return [nil, nil, 0] if dates.empty?

  first_date = dates.min
  last_date = dates.max

  [first_date, last_date, countable_weekday_count_in_range(first_date, last_date)]
end

def unique_trade_days(trades)
  trades
    .map { |t| t[:date] }
    .reject(&:empty?)
    .uniq
end

def countable_unique_trade_days(trades)
  unique_trade_days(trades)
    .map { |d| parse_trade_date(d) }
    .compact
    .select { |d| countable_weekday?(d) }
end

def trade_rate(trades, total_trading_days)
  return 0.0 if total_trading_days.zero?

  countable_unique_trade_days(trades).size.to_f / total_trading_days
end

def monday_of_week(date)
  date - ((date.wday + 6) % 7)
end

def mon_fri_week_in_range?(monday, first_date, last_date)
  (0..4).map { |i| monday + i }.all? { |d| d >= first_date && d <= last_date }
end

def mon_fri_week_fully_non_trade?(monday, first_date, last_date)
  weekdays = (0..4).map { |i| monday + i }.select { |d| d >= first_date && d <= last_date }
  return false if weekdays.empty?

  weekdays.all? { |d| AleksikNonTradeCalendar.non_trade_date?(d) }
end

def countable_mon_fri_weeks_in_date_range(first_date, last_date)
  return [] if first_date.nil? || last_date.nil?

  first_monday = monday_of_week(first_date)
  last_monday = monday_of_week(last_date)

  full_weeks = []
  monday = first_monday
  while monday <= last_monday
    if mon_fri_week_in_range?(monday, first_date, last_date) &&
       !mon_fri_week_fully_non_trade?(monday, first_date, last_date)
      full_weeks << monday
    end
    monday += 7
  end
  full_weeks
end

def traded_full_week_count(trades, full_week_mondays)
  return 0 if full_week_mondays.nil? || full_week_mondays.empty?

  full_week_set = full_week_mondays.to_set
  countable_unique_trade_days(trades)
    .map { |d| monday_of_week(d) }
    .uniq
    .count { |monday| full_week_set.include?(monday) }
end

def weekly_trade_rate(trades, full_week_mondays)
  return 0.0 if full_week_mondays.nil? || full_week_mondays.empty?

  traded_full_week_count(trades, full_week_mondays).to_f / full_week_mondays.size
end

def format_trade_span_date(date)
  return '(none)' if date.nil?

  date.strftime('%Y.%m.%d')
end

def minimum_traded_full_weeks_for_weekly_trade_rate(threshold, full_week_mondays)
  return 0 if full_week_mondays.nil? || full_week_mondays.empty?

  (threshold.to_f * full_week_mondays.size).ceil
end

def print_loaded_trade_span_summary(
  trade_count:,
  first_date:,
  last_date:,
  trading_day_count:,
  full_week_mondays:,
  io: $stdout,
  weekly_trade_rate_check_enabled: false,
  minimum_weekly_trade_rate: nil
)
  io.puts "Loaded trades: #{trade_count}"
  io.puts "Trade span first day: #{format_trade_span_date(first_date)}"
  io.puts "Trade span last day: #{format_trade_span_date(last_date)}"
  io.puts "Countable weekdays in range (excl. weekends + aleksik banned): #{trading_day_count}"
  io.puts "Countable Mon-Fri weeks in range (excl. fully banned weeks): #{full_week_mondays.size}"

  return unless weekly_trade_rate_check_enabled && !minimum_weekly_trade_rate.nil?

  min_trades =
    minimum_traded_full_weeks_for_weekly_trade_rate(minimum_weekly_trade_rate, full_week_mondays)

  io.puts "CHECK_MINIMUM_TRADERATEWEEKLY enabled: threshold=#{minimum_weekly_trade_rate}"
  io.puts format(
    'Minimum trades to pass weekly traderate (1 trade each on %d distinct full weeks): %d',
    min_trades,
    min_trades
  )
end

def trade_close_reason_label(close_decision, reason)
  decision = close_decision.to_s.strip
  return decision unless decision.empty?

  reason.to_s.strip
end

def main_close_reason_for_trades(trades)
  return '' if trades.empty?

  counts = Hash.new(0)
  trades.each do |trade|
    label = trade_close_reason_label(trade[:close_decision], trade[:reason])
    label = '(none)' if label.empty?
    counts[label] += 1
  end

  counts.max_by { |label, count| [count, label] }.first
end

def trade_close_reason_label(close_decision, reason)
  decision = close_decision.to_s.strip
  return decision unless decision.empty?

  reason.to_s.strip
end

def main_close_reason_for_trades(trades)
  return '' if trades.empty?

  counts = Hash.new(0)
  trades.each do |trade|
    label = trade_close_reason_label(trade[:close_decision], trade[:reason])
    label = '(none)' if label.empty?
    counts[label] += 1
  end

  counts.max_by { |label, count| [count, label] }.first
end
