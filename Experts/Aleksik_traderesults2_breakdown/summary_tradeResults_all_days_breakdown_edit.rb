#!/usr/bin/env ruby
# frozen_string_literal: true

# Reads summary_tradeResults_all_days_breakdown.tsv + breakdown algo config.
# Rewrites the TSV keeping only trade rows for algos in PRESERVE_GROUP.
#
# Exit groups (from config):
#   :closetradefalse_secret_tp0      — closetrade_after_some_time=false, secret_tp_range_percent=0
#   :closetradetrue_secret_tp0       — closetrade_after_some_time=true,  secret_tp_range_percent=0
#   :closetradefalse_secret_tp_nonzero — closetrade_after_some_time=false, secret_tp_range_percent!=0
#
# Raises if any config algo is outside these groups
# (e.g. non-zero secret TP with closetrade_after_some_time=true).

require 'csv'
require 'set'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR)
TRADES_PATH = File.join(SCRIPT_DIR, 'summary_tradeResults_all_days_breakdown.tsv')

PRESERVE_GROUP = :closetradefalse_secret_tp0

GROUP_ORDER = %i[
  closetradefalse_secret_tp0
  closetradetrue_secret_tp0
  closetradefalse_secret_tp_nonzero
].freeze

GROUP_LABELS = {
  closetradefalse_secret_tp0: 'closetrade=false, secret_tp=0',
  closetradetrue_secret_tp0: 'closetrade=true, secret_tp=0',
  closetradefalse_secret_tp_nonzero: 'closetrade=false, secret_tp!=0'
}.freeze

def read_csv(path)
  raw = File.read(path, encoding: 'bom|utf-8')
  CSV.parse(raw, headers: true)
end

def parse_float(value)
  text = value.to_s.strip
  return nil if text.empty?

  Float(text)
rescue ArgumentError, TypeError
  nil
end

def config_bool(value)
  %w[true 1 yes].include?(value.to_s.strip.downcase)
end

def classify_exit_group(config_row, algo_id:)
  secret_tp = parse_float(config_row['secret_tp_range_percent'])
  closetrade = config_bool(config_row['closetrade_after_some_time'])

  if secret_tp.nil?
    raise "ERROR: algo #{algo_id}: missing or invalid secret_tp_range_percent in config"
  end

  if !secret_tp.zero? && closetrade
    raise "ERROR: algo #{algo_id}: non-zero secret_tp_range_percent (#{secret_tp.to_i}) " \
          'with closetrade_after_some_time=true is outside exit groups'
  end

  if secret_tp.zero? && !closetrade
    :closetradefalse_secret_tp0
  elsif secret_tp.zero? && closetrade
    :closetradetrue_secret_tp0
  elsif !secret_tp.zero? && !closetrade
    :closetradefalse_secret_tp_nonzero
  else
    raise "ERROR: algo #{algo_id}: could not classify into an exit group"
  end
end

def normalize_preserve_group(value)
  key = value.is_a?(Symbol) ? value : value.to_s.strip.to_sym
  return key if GROUP_ORDER.include?(key)

  aliases = {
    g1: :closetradefalse_secret_tp0,
    g2: :closetradetrue_secret_tp0,
    g3: :closetradefalse_secret_tp_nonzero,
    '1': :closetradefalse_secret_tp0,
    '2': :closetradetrue_secret_tp0,
    '3': :closetradefalse_secret_tp_nonzero
  }
  mapped = aliases[key] || aliases[value.to_s.strip]
  return mapped if mapped && GROUP_ORDER.include?(mapped)

  raise "ERROR: invalid PRESERVE_GROUP #{value.inspect} " \
        "(use #{GROUP_ORDER.map(&:inspect).join(', ')})"
end

unless File.file?(CONFIG_PATH)
  warn "ERROR: config file not found: #{CONFIG_PATH}"
  exit 1
end

unless File.file?(TRADES_PATH)
  warn "ERROR: trades file not found: #{TRADES_PATH}"
  exit 1
end

begin
  preserve_group = normalize_preserve_group(PRESERVE_GROUP)
rescue StandardError => e
  warn e.message
  exit 1
end

config_by_algo_id = {}
group_by_algo_id = {}

read_csv(CONFIG_PATH).each do |row|
  algo_id = row['algo_id'].to_s.strip
  next if algo_id.empty?

  group = classify_exit_group(row, algo_id: algo_id)
  config_by_algo_id[algo_id] = row
  group_by_algo_id[algo_id] = group
end

trades_table = read_csv(TRADES_PATH)
unless trades_table.headers&.include?('algoID')
  warn 'ERROR: trades TSV missing algoID column'
  exit 1
end

kept_rows = []
removed_rows = 0
missing_config_in_trades = Set.new
unknown_algo_in_trades = Set.new

trades_table.each do |row|
  algo_id = row['algoID'].to_s.strip
  if algo_id.empty?
    unknown_algo_in_trades << '(blank algoID)'
    next
  end

  group = group_by_algo_id[algo_id]
  if group.nil?
    missing_config_in_trades << algo_id
    next
  end

  if group == preserve_group
    kept_rows << row
  else
    removed_rows += 1
  end
end

unless missing_config_in_trades.empty?
  warn "ERROR: #{missing_config_in_trades.size} trade row algo(s) missing from config: " \
       "#{missing_config_in_trades.to_a.sort.join(', ')}"
  exit 1
end

unless unknown_algo_in_trades.empty?
  warn "ERROR: #{unknown_algo_in_trades.size} trade row(s) with blank algoID"
  exit 1
end

config_counts = GROUP_ORDER.to_h { |group| [group, 0] }
group_by_algo_id.each_value { |group| config_counts[group] += 1 }

kept_algo_ids = kept_rows.map { |row| row['algoID'].to_s.strip }.uniq
removed_algo_ids =
  group_by_algo_id
  .select { |_algo_id, group| group != preserve_group }
  .keys
  .select { |algo_id| trades_table.any? { |row| row['algoID'].to_s.strip == algo_id } }
  .sort_by(&:to_i)

CSV.open(TRADES_PATH, 'w', write_headers: true, headers: trades_table.headers) do |csv|
  kept_rows.each { |row| csv << trades_table.headers.map { |header| row[header] } }
end

puts "config: #{CONFIG_PATH}"
puts "trades: #{TRADES_PATH}"
puts "preserve group: #{preserve_group} (#{GROUP_LABELS[preserve_group]})"
puts
puts 'config algos by exit group:'
GROUP_ORDER.each do |group|
  puts "  #{group} (#{GROUP_LABELS[group]}): #{config_counts[group]}"
end
puts
puts "trade rows before: #{trades_table.size}"
puts "trade rows kept:   #{kept_rows.size}"
puts "trade rows removed:#{removed_rows}"
puts "algos with kept trades: #{kept_algo_ids.size}"
puts "algos removed from trades (had rows, other group): #{removed_algo_ids.size}"
puts
puts "wrote #{kept_rows.size} rows to #{TRADES_PATH}"
