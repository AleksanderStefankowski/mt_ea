#!/usr/bin/env ruby
# frozen_string_literal: true
# Reads wired time algos from aleksik2.mq5, prints them, and writes CSV.

require "csv"
require_relative "../Aleksik/smash_mql5_algo_reader_lib"

MQ5_FILE = File.expand_path("aleksik2.mq5", __dir__)
OUT_CSV  = File.expand_path("aleksik2_r_read_time_algos_csv.csv", __dir__)

MAIN_FIELDS = %w[
  entry_hour
  entry_minute
  rule_switch_map
  secret_tp_profit_percent_min
  secret_tp_greenguard_pricediff_at_least
  max_trades_per_day
  max_open_positions
  stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
].freeze

SHARED_FIELDS = %w[
  use_banned_days
  tradeSizePct
  bannedRanges
  tradesDays
  babysit_enabled
  blockPlacementIfFamilyOpenOrPending
  stop_trading_today_if_AllAlgos_losing_trades_count
  stop_trading_today_if_AllAlgos_winning_trades_count
  stop_trading_if_day_has_X_wins_0_losses
  stop_trading_if_day_has_profit_factor_above
].freeze

ASSIGN_RE = /
  g_timeAlgos\[TimeAlgoSlotIndexByAlgoId\(TIME_ALGO_(\d+)\)\]\.(\w+)\s*=\s*([^;]+);
/x

SHARED_ASSIGN_RE = /
  g_timeAlgoShared\.(\w+)\s*=\s*("[^"]*"|[^;]+);
/x

def strip_mq5_value(raw)
  val = raw.strip.sub(%r{//.*}, "").strip
  if (m = val.match(/\A"(.*)"\z/))
    return m[1]
  end

  val
end

def registry_algo_ids(src)
  block = src[/int\s+g_timeAlgoRegistryIds\[\]\s*=\s*\{([^}]+)\}/m, 1]
  return [] unless block

  block.scan(/TIME_ALGO_(\d+)/).flatten.map(&:to_i)
end

def params_by_algo_from_src(src)
  params = Hash.new { |h, k| h[k] = {} }
  src.scan(ASSIGN_RE) do |id, field, value|
    params[id.to_i][field] = strip_mq5_value(value)
  end
  params
end

def shared_params_from_src(src)
  shared = {}
  src.scan(SHARED_ASSIGN_RE) do |field, value|
    shared[field] = strip_mq5_value(value)
  end
  shared
end

def field_value(params, field)
  params[field].to_s
end

def enabled?(raw)
  strip_mq5_value(raw.to_s).casecmp("true").zero?
end

def entry_time_label(row)
  hour = row[:entry_hour].to_s
  minute = row[:entry_minute].to_s.rjust(2, "0")
  "#{hour}:#{minute}"
end

def print_summary(rows)
  all_count = rows.size
  enabled_rows = rows.select { |row| enabled?(row[:enabled]) }
  disabled_count = all_count - enabled_rows.size

  enabled_by_entry = enabled_rows.group_by { |row| entry_time_label(row) }
  enabled_by_entry.transform_values!(&:size)

  enabled_by_rule = enabled_rows.group_by { |row| row[:rule_switch_map].to_s }
  enabled_by_rule.transform_values!(&:size)

  puts "--- summary ---"
  puts "count all:      #{all_count}"
  puts "count enabled:  #{enabled_rows.size}"
  puts "count disabled: #{disabled_count}"
  puts "enabled by entry time:"
  if enabled_by_entry.empty?
    puts "  (none)"
  else
    enabled_by_entry.sort_by { |entry, _| entry }.each do |entry, count|
      puts "  #{entry}: #{count}"
    end
  end
  puts "enabled by rule_switch_map:"
  if enabled_by_rule.empty?
    puts "  (none)"
  else
    enabled_by_rule.sort_by { |rule, _| rule.to_i }.each do |rule, count|
      puts "  #{rule}: #{count}"
    end
  end
  puts
end

src = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
params_by_algo = params_by_algo_from_src(src)
shared_params = shared_params_from_src(src)
algo_ids = registry_algo_ids(src)

rows = algo_ids.map do |id|
  p = params_by_algo[id] || {}
  row = {
    algo_id: id,
    enabled: p["enabled"] || ""
  }
  SHARED_FIELDS.each { |f| row[:"shared_#{f}"] = shared_params[f].to_s }
  MAIN_FIELDS.each { |f| row[f.to_sym] = field_value(p, f) }
  row
end

headers = ["algo_id", "enabled", *SHARED_FIELDS.map { |f| "shared_#{f}" }, *MAIN_FIELDS]

CSV.open(OUT_CSV, "w") do |csv|
  csv << headers
  rows.each do |row|
    csv << headers.map { |header| row[header.to_sym] }
  end
end

puts OUT_CSV
print_summary(rows)
