#!/usr/bin/env ruby
# frozen_string_literal: true

# Read all 3 summary_tradeResults_all_days_* files, count trades per calendar day
# by startTime (opens today — matches stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count),
# find each algo's peak daily open count, print distribution.

require_relative 'analyze_algos_performance_common'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
SUMMARY_FILES = AnalyzeAlgosPerformanceCommon::ALL_TRADE_SUMMARY_FILES

def format_percent(numerator, denominator)
  return 'n/a' if denominator.zero?

  format('%.1f%%', 100.0 * numerator / denominator)
end

# Count by open day (startTime), not close day (TSV date / endTime).
def trade_start_date_key(trade)
  trade[:start_time]&.strftime('%Y.%m.%d')
end

# examples: [{ algo_id:, peak_date: }, ...] — up to 2, sorted by algo_id
def example_algo_with_dates(examples, limit = 2)
  examples
    .sort_by { |ex| ex[:algo_id].to_i }
    .first(limit)
    .map { |ex| "#{ex[:algo_id]} (#{ex[:peak_date]})" }
    .join(', ')
end

# Returns { algo_id => { peak:, peak_date: } }
def peak_trades_per_day_by_algo(trades)
  daily_counts_by_algo = Hash.new { |h, algo_id| h[algo_id] = Hash.new(0) }

  trades.each do |trade|
    algo_id = trade[:algo_id].to_s.strip
    date_key = trade_start_date_key(trade)
    next if algo_id.empty? || date_key.nil? || date_key.empty?

    daily_counts_by_algo[algo_id][date_key] += 1
  end

  daily_counts_by_algo.transform_values do |counts_by_day|
    peak_date, peak = counts_by_day.max_by { |_, count| count }
    { peak: peak || 0, peak_date: peak_date.to_s }
  end
end

missing_files = SUMMARY_FILES.reject { |name| File.file?(File.join(SCRIPT_DIR, name)) }
unless missing_files.empty?
  warn "ERROR: missing summary file(s): #{missing_files.join(', ')}"
  exit 1
end

trades = AnalyzeAlgosPerformanceCommon.load_trades_from_summary_files(SCRIPT_DIR)
if trades.empty?
  warn 'ERROR: no trades loaded.'
  exit 1
end

peak_by_algo = peak_trades_per_day_by_algo(trades)
peak_histogram = Hash.new { |h, k| h[k] = [] }
peak_by_algo.each do |algo_id, info|
  peak_histogram[info[:peak]] << { algo_id: algo_id, peak_date: info[:peak_date] }
end

total_algos = peak_by_algo.size
total_trades = trades.size
skipped_no_start = trades.count { |t| trade_start_date_key(t).nil? }

puts 'peak opens per day by algo (all families; grouped by startTime date)'
puts "directory: #{SCRIPT_DIR}"
SUMMARY_FILES.each { |name| puts "  #{name}" }
puts
puts "total trades: #{total_trades}"
puts "skipped (no startTime): #{skipped_no_start}" unless skipped_no_start.zero?
puts "algos with trades: #{total_algos}"
puts
puts 'peak opens per day     algo count   % of all algos   example algo IDs (up to 2, with peak start date)'
puts '-' * 100

peak_histogram.keys.sort.each do |peak|
  examples = peak_histogram[peak]
  puts format('%-20s %-12d %-16s %s', peak, examples.size, format_percent(examples.size, total_algos),
              example_algo_with_dates(examples))
end
