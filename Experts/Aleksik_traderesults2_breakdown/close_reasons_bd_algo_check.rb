#!/usr/bin/env ruby
# frozen_string_literal: true

# Reads breakdown trade results + algo config CSV.
# Buckets trades by secret_tp_range_percent recorded on each trade row (what actually ran).
# Also prints config counts and any config vs trade mismatches.

require 'csv'
require 'set'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR)
TRADES_PATH = File.join(SCRIPT_DIR, 'summary_tradeResults_all_days_breakdown.tsv')

def read_csv(path)
  raw = File.read(path, encoding: 'bom|utf-8')
  CSV.parse(raw, headers: true)
end

def format_percent(numerator, denominator)
  return 'n/a' if denominator.zero?

  format('%.1f%%', 100.0 * numerator / denominator)
end

def secret_tp_value(raw)
  text = raw.to_s.strip
  return nil if text.empty?

  text.to_f
end

def secret_tp_zero?(raw)
  value = secret_tp_value(raw)
  value.nil? ? nil : value.zero?
end

def load_secret_tp_by_algo_id(config_path)
  read_csv(config_path).each_with_object({}) do |row, memo|
    algo_id = row['algo_id'].to_s.strip
    next if algo_id.empty?

    memo[algo_id.to_i] = secret_tp_value(row['secret_tp_range_percent'])
  end
end

def close_reason_key(row)
  decision = row['close_decision'].to_s.strip
  reason = row['reason'].to_s.strip
  decision = '(none)' if decision.empty?
  reason = '(none)' if reason.empty?
  "#{decision} | #{reason}"
end

def print_group_report(label, trades_by_reason, config_algo_count:, algo_ids_with_trades:, skipped_trades: 0)
  trade_count = trades_by_reason.values.sum
  puts "=== #{label} ==="
  puts "algos in config: #{config_algo_count}"
  puts "algos with trades: #{algo_ids_with_trades.size}"
  puts "trades: #{trade_count}"
  puts "trades skipped (algo not in config): #{skipped_trades}" if skipped_trades.positive?
  puts

  if trade_count.zero?
    puts '(no trades)'
    puts
    return
  end

  puts format('%-55s %8s %8s', 'close_decision | reason', 'count', 'pct')
  trades_by_reason.sort_by { |_, count| -count }.each do |key, count|
    puts format('%-55s %8d %8s', key, count, format_percent(count, trade_count))
  end
  puts
end

def build_close_reason_counts(trades, secret_tp_by_algo:, source:, secret_tp_zero:)
  trades_by_reason = Hash.new(0)
  algo_ids_with_trades = Set.new
  skipped = 0
  mismatched_rows = 0

  trades.each do |row|
    algo_id = row['algoID'].to_s.strip.to_i
    config_secret_tp = secret_tp_by_algo[algo_id]
    if config_secret_tp.nil?
      skipped += 1
      next
    end

    trade_secret_tp = secret_tp_value(row['secret_tp_range_percent'])

    if source == :config
      bucket_secret_tp = config_secret_tp
    else
      if trade_secret_tp.nil?
        skipped += 1
        next
      end
      mismatched_rows += 1 if trade_secret_tp != config_secret_tp
      bucket_secret_tp = trade_secret_tp
    end

    is_zero = bucket_secret_tp.zero?
    next if secret_tp_zero ? !is_zero : is_zero

    algo_ids_with_trades << algo_id
    trades_by_reason[close_reason_key(row)] += 1
  end

  [trades_by_reason, algo_ids_with_trades, skipped, mismatched_rows]
end

def config_algo_ids_for_bucket(secret_tp_by_algo, secret_tp_zero:)
  secret_tp_by_algo.select do |_, secret_tp|
    secret_tp_zero ? secret_tp.zero? : !secret_tp.zero?
  end.keys
end

secret_tp_by_algo = load_secret_tp_by_algo_id(CONFIG_PATH)
trades = read_csv(TRADES_PATH)

config_zero_count = secret_tp_by_algo.count { |_, v| v.zero? }
config_nonzero_count = secret_tp_by_algo.count { |_, v| !v.zero? }
config_nonzero_ids = secret_tp_by_algo.select { |_, v| !v.zero? }.sort.map { |id, v| "#{id}(#{v.to_i})" }

zero_reasons, zero_algos, zero_skipped, zero_mismatch =
  build_close_reason_counts(trades, secret_tp_by_algo: secret_tp_by_algo, source: :trade, secret_tp_zero: true)
non_zero_reasons, non_zero_algos, non_zero_skipped, non_zero_mismatch =
  build_close_reason_counts(trades, secret_tp_by_algo: secret_tp_by_algo, source: :trade, secret_tp_zero: false)

trade_zero_count = zero_reasons.values.sum
trade_nonzero_count = non_zero_reasons.values.sum

puts "config: #{CONFIG_PATH}"
puts "trades: #{TRADES_PATH}"
puts "total trade rows: #{trades.size}"
puts "algos in config: #{secret_tp_by_algo.size}"
puts "config secret_tp_range_percent:"
puts "  0: #{config_zero_count}"
puts "  non-zero: #{config_nonzero_count}"
unless config_nonzero_ids.empty?
  puts "  non-zero algo ids: #{config_nonzero_ids.join(', ')}"
end
puts "trade rows bucketed by trade secret_tp_range_percent:"
puts "  0: #{trade_zero_count}"
puts "  non-zero: #{trade_nonzero_count}"
mismatch_rows = zero_mismatch + non_zero_mismatch
if mismatch_rows.positive?
  puts "WARNING: #{mismatch_rows} trade rows have secret_tp_range_percent != config for that algo_id"
else
  puts "config vs trade secret_tp_range_percent: no mismatches"
end
puts

print_group_report(
  'secret_tp_range_percent = 0 (trade column)',
  zero_reasons,
  config_algo_count: config_algo_ids_for_bucket(secret_tp_by_algo, secret_tp_zero: true).size,
  algo_ids_with_trades: zero_algos,
  skipped_trades: zero_skipped
)
print_group_report(
  'secret_tp_range_percent != 0 (trade column)',
  non_zero_reasons,
  config_algo_count: config_algo_ids_for_bucket(secret_tp_by_algo, secret_tp_zero: false).size,
  algo_ids_with_trades: non_zero_algos,
  skipped_trades: non_zero_skipped
)
