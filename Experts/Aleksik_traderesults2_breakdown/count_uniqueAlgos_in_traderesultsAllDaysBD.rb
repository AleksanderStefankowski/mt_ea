#!/usr/bin/env ruby
# frozen_string_literal: true

# Counts unique breakdown algos that appear in summary_tradeResults_all_days_breakdown.tsv
# and compares against algos defined in aleksik2_r_read_breakdown_algos_csv.csv.

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

def truthy_enabled?(raw)
  %w[true 1 yes].include?(raw.to_s.strip.downcase)
end

unless File.file?(CONFIG_PATH)
  warn "ERROR: config file not found: #{CONFIG_PATH}"
  exit 1
end

unless File.file?(TRADES_PATH)
  warn "ERROR: trades file not found: #{TRADES_PATH}"
  exit 1
end

config_rows = read_csv(CONFIG_PATH)
config_algo_ids = Set.new
enabled_algo_ids = Set.new
disabled_algo_ids = Set.new

config_rows.each do |row|
  algo_id = row['algo_id'].to_s.strip
  next if algo_id.empty?

  config_algo_ids << algo_id
  if truthy_enabled?(row['enabled'])
    enabled_algo_ids << algo_id
  else
    disabled_algo_ids << algo_id
  end
end

trade_rows = read_csv(TRADES_PATH)
algo_ids_with_trades = Set.new
trade_count_by_algo_id = Hash.new(0)
missing_algo_id_trade_count = 0

trade_rows.each do |row|
  algo_id = row['algoID'].to_s.strip
  if algo_id.empty?
    missing_algo_id_trade_count += 1
    next
  end

  algo_ids_with_trades << algo_id
  trade_count_by_algo_id[algo_id] += 1
end

traded_config_algo_ids = algo_ids_with_trades & config_algo_ids
traded_not_in_config = algo_ids_with_trades - config_algo_ids
defined_but_no_trades = config_algo_ids - algo_ids_with_trades
enabled_but_no_trades = enabled_algo_ids - algo_ids_with_trades
disabled_but_traded = disabled_algo_ids & algo_ids_with_trades

puts '=== unique breakdown algos in trade results ==='
puts "trades file: #{TRADES_PATH}"
puts "config file: #{CONFIG_PATH}"
puts
puts "total trades: #{trade_rows.size}"
puts "trades missing algoID: #{missing_algo_id_trade_count}" if missing_algo_id_trade_count.positive?
puts
puts "defined algos in config: #{config_algo_ids.size}"
puts "  enabled: #{enabled_algo_ids.size}"
puts "  disabled: #{disabled_algo_ids.size}"
puts
puts "unique algos with trades: #{algo_ids_with_trades.size}"
puts "  in config: #{traded_config_algo_ids.size} (#{format_percent(traded_config_algo_ids.size, config_algo_ids.size)} of defined)"
traded_enabled_algo_ids = traded_config_algo_ids & enabled_algo_ids
puts "  enabled in config: #{traded_enabled_algo_ids.size} (#{format_percent(traded_enabled_algo_ids.size, enabled_algo_ids.size)} of enabled)"
puts "  not in config: #{traded_not_in_config.size}"
puts
puts "defined algos with no trades: #{defined_but_no_trades.size} (#{format_percent(defined_but_no_trades.size, config_algo_ids.size)} of defined)"
puts "  enabled with no trades: #{enabled_but_no_trades.size} (#{format_percent(enabled_but_no_trades.size, enabled_algo_ids.size)} of enabled)"
puts "  disabled but traded: #{disabled_but_traded.size}" if disabled_but_traded.any?

if traded_not_in_config.any?
  puts
  puts "algos with trades but missing from config (#{traded_not_in_config.size}):"
  traded_not_in_config.sort.each do |algo_id|
    puts "  #{algo_id}: #{trade_count_by_algo_id[algo_id]} trades"
  end
end
