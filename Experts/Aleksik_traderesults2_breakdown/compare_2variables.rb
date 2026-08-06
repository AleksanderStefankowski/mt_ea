#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare two config variables using allowed (var1, var2) groups only.
# Set DYNAMIC_GROUPS_MODE = true to build groups from DYNAMIC_VARIABLE_* cartesian product.
# Set DYNAMIC_GROUPS_MODE = false to use ALLOWED_GROUPS_EXPLICIT.

require 'csv'
require_relative 'compare_variable_analysis_lib'
SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR)
PERF_PATH = File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_output.csv')

# Supported VARIABLE_1 / VARIABLE_2 values (any column in aleksik2_r_read_breakdown_algos_csv.csv except algo_id):
#   enabled
#   quant_rules
#   rules
#   stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
#   expiry_minutes
#   breakdown_streak_continuation_mode
#   min_breakdown_sequence_len
#   max_breakdown_sequence_len
#   bd_start_min_breakdown_percent
#   min_breakdown_total_percent
#   after_bd_need_x_15greenc
#   entry_max_minutes_after_bdend
#   forget_about_latest_breakdown_after_x_15m_candles
#   entryrange_range_percentspot
#   secret_tp_range_percent
#   tp_notsecret_range_percent
#   closetrade_after_some_time
#   closetrade_after_some_time_butOnlyIfProfit
#   closetrade_after_some_time_but_ProfitPercent_Needed
#   closetrade_after_x_minutes_from_breakdown
#   max_open_positions
VARIABLE_1 = 'forget_about_latest_breakdown_after_x_15m_candles'
VARIABLE_2 = 'entry_max_minutes_after_bdend'
WRITE_OUTPUT_FILE = false
# VARIABLE_1 = 'closetrade_after_some_time_but_ProfitPercent_Needed'
# VARIABLE_2 = 'closetrade_after_x_minutes_from_breakdown'
DYNAMIC_GROUPS_MODE = true
# Used when DYNAMIC_GROUPS_MODE = true: cartesian product of var1 x var2 values.
DYNAMIC_VARIABLE_1_VALUES = [6, 11, 52].freeze
DYNAMIC_VARIABLE_2_VALUES = [60, 110, 250].freeze


# Used when DYNAMIC_GROUPS_MODE = false: each row is [variable_1_value, variable_2_value]
ALLOWED_GROUPS_EXPLICIT = [
  [5, 60],
  # [8, 60],
  # [12, 60],
  # [5, 110],
  # [8, 110],
  [12, 110]
].freeze

ALLOWED_GROUPS = (
  if DYNAMIC_GROUPS_MODE
    DYNAMIC_VARIABLE_1_VALUES.product(DYNAMIC_VARIABLE_2_VALUES)
  else
    ALLOWED_GROUPS_EXPLICIT
  end
).freeze

PERF_FIELDS = %w[
  timeVSprofit
  percentSum_w_roll
  avgDurationHours
  tradesCount
].freeze

GROUP_AVERAGES_OUTPUT_PATH = File.join(
  SCRIPT_DIR,
  "compare_2variables_#{VARIABLE_1}_#{VARIABLE_2}_group_averages.csv"
)

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

def format_float(value, decimals = 3)
  return 'n/a' if value.nil?

  format("%.#{decimals}f", value)
end

def perf_field_decimals(field)
  field == 'percentSum_w_roll' || field == 'tradesCount' ? 2 : 3
end

def average(values)
  nums = values.compact
  return nil if nums.empty?

  nums.sum.to_f / nums.size
end

def allowed_group_label(var1_value, var2_value)
  "#{VARIABLE_1}=#{normalize_group_value(var1_value)}, #{VARIABLE_2}=#{normalize_group_value(var2_value)}"
end

def rows_for_allowed_group(allowed_rows, var1_value, var2_value)
  allowed_rows.select do |entry|
    normalize_group_value(entry[:config][VARIABLE_1]) == normalize_group_value(var1_value) &&
      normalize_group_value(entry[:config][VARIABLE_2]) == normalize_group_value(var2_value)
  end
end

def build_group_averages(allowed_rows)
  ALLOWED_GROUPS.map do |var1_value, var2_value|
    group_rows = rows_for_allowed_group(allowed_rows, var1_value, var2_value)
    averages =
      PERF_FIELDS.to_h do |field|
        [field, average(group_rows.map { |entry| parse_float(entry[:perf][field]) })]
      end
    {
      variable_1: normalize_group_value(var1_value),
      variable_2: normalize_group_value(var2_value),
      algo_count: group_rows.size,
      averages: averages,
      rows: group_rows
    }
  end
end

def write_group_averages_csv(group_averages)
  headers = [
    VARIABLE_1,
    VARIABLE_2,
    'algo_count',
    *PERF_FIELDS.map { |field| "avg_#{field}" }
  ]
  CSV.open(GROUP_AVERAGES_OUTPUT_PATH, 'w', write_headers: true, headers: headers) do |csv|
    group_averages.each do |group|
      csv << [
        group[:variable_1],
        group[:variable_2],
        group[:algo_count].to_s,
        *PERF_FIELDS.map { |field| format_float(group[:averages][field], perf_field_decimals(field)) }
      ]
    end
  end
end

def sort_groups_by_average(group_averages, field, order: :desc)
  group_averages.sort do |left, right|
    left_avg = left[:averages][field]
    right_avg = right[:averages][field]

    if left_avg.nil? && right_avg.nil?
      0
    elsif left_avg.nil?
      1
    elsif right_avg.nil?
      -1
    elsif order == :desc
      right_avg <=> left_avg
    else
      left_avg <=> right_avg
    end
  end
end

def short_group_label(var1_value, var2_value)
  "#{normalize_group_value(var1_value)}/#{normalize_group_value(var2_value)}"
end

def print_grid_cell_duels(groups_with_data)
  return if groups_with_data.size < 2

  puts
  puts '=' * 72
  puts 'GRID CELL DUELS (best algo per var1/var2 cell, top-2 cells by metric — not paired single-variable)'
  puts '=' * 72

  PERF_FIELDS.each do |perf_field|
    best_by_value =
      groups_with_data.each_with_object({}) do |group, memo|
        label = short_group_label(group[:variable_1], group[:variable_2])
        best = CompareVariableAnalysisLib.best_algo_from_entries(group[:rows], perf_field)
        memo[label] = best if best
      end
    duel_lines = CompareVariableAnalysisLib.metric_duel_table_lines_from_best(best_by_value, perf_field)
    next if duel_lines.empty?

    puts
    duel_lines.each { |line| puts line }
  end
end

def print_paired_var1_duels(allowed_rows)
  var2_values = ALLOWED_GROUPS.map { |_, var2| normalize_group_value(var2) }.uniq
  any = false

  var2_values.sort.each do |var2_value|
    subset =
      allowed_rows.select do |entry|
        normalize_group_value(entry[:config][VARIABLE_2]) == var2_value
      end
    next if subset.map { |entry| entry[:config][VARIABLE_1].to_s }.uniq.size < 2

    run = CompareVariableAnalysisLib.build_variable_compare_run(subset, VARIABLE_1)
    next if run[:pairs].empty?

    any = true
    puts
    puts '=' * 72
    puts "PAIRED DUELS: #{VARIABLE_1} (fixed #{VARIABLE_2}=#{var2_value}, all other config equal)"
    puts '=' * 72
    CompareVariableAnalysisLib.compare_compact_analysis_lines(run[:pairs], VARIABLE_1).each { |line| puts line }
  end

  return if any

  puts
  puts "(no paired duels: no #{VARIABLE_1} pairs at fixed #{VARIABLE_2} with matching other config)"
end

def print_group_averages_sorted(group_averages, field, order:)
  direction = order == :desc ? 'highest' : 'lowest'
  groups_with_data = group_averages.select { |group| group[:algo_count].positive? }
  puts '=' * 72
  puts "PER-GROUP AVERAGES sorted by #{direction} perf_#{field}"
  puts '=' * 72

  if groups_with_data.empty?
    puts '(no groups with performance data)'
    return
  end

  sort_groups_by_average(groups_with_data, field, order: order).each do |group|
    puts allowed_group_label(group[:variable_1], group[:variable_2]) + " (algos=#{group[:algo_count]}):"
    PERF_FIELDS.each do |perf_field|
      puts "  avg perf_#{perf_field}=#{format_float(group[:averages][perf_field], perf_field_decimals(perf_field))}"
    end
  end
end

def print_group_averages(group_averages, allowed_rows)
  groups_with_data = group_averages.select { |group| group[:algo_count].positive? }
  print_group_averages_sorted(group_averages, 'timeVSprofit', order: :desc)
  puts
  print_group_averages_sorted(group_averages, 'percentSum_w_roll', order: :desc)
  puts
  print_group_averages_sorted(group_averages, 'avgDurationHours', order: :asc)
  print_paired_var1_duels(allowed_rows)
  print_grid_cell_duels(groups_with_data)
end

def normalize_group_value(value)
  text = value.to_s.strip
  return text.to_i.to_s if text.match?(/\A-?\d+\z/)
  if text.match?(/\A-?\d+\.\d+\z/)
    f = Float(text)
    return f == f.to_i ? f.to_i.to_s : format('%g', f)
  end

  text
end

def allowed_group_key(var1_value, var2_value)
  "#{normalize_group_value(var1_value)}\x1f#{normalize_group_value(var2_value)}"
end

def allowed_groups_lookup
  ALLOWED_GROUPS.each_with_object({}) do |(var1_value, var2_value), memo|
    memo[allowed_group_key(var1_value, var2_value)] = {
      variable_1: normalize_group_value(var1_value),
      variable_2: normalize_group_value(var2_value)
    }
  end
end

CompareVariableAnalysisLib.refresh_breakdown_algos_performance_output!(SCRIPT_DIR)

unless File.file?(CONFIG_PATH)
  warn "ERROR: config file not found: #{CONFIG_PATH}"
  exit 1
end

config_table = read_csv(CONFIG_PATH)
[VARIABLE_1, VARIABLE_2].each do |variable|
  next if config_table.headers.include?(variable)

  available = config_table.headers.reject { |header| header == 'algo_id' }
  warn "ERROR: variable not found in config: #{variable}"
  warn "Available config columns: #{available.join(', ')}"
  exit 1
end

allowed_lookup = allowed_groups_lookup

config_by_algo_id =
  config_table.each_with_object({}) do |row, memo|
    algo_id = row['algo_id'].to_s.strip
    next if algo_id.empty?

    memo[algo_id] = row
  end

perf_rows = read_csv(PERF_PATH).select { |row| row['algoID'].to_s.strip != '' }
matched_rows = []
missing_config = []

perf_rows.each do |perf_row|
  algo_id = perf_row['algoID'].to_s.strip
  config_row = config_by_algo_id[algo_id]
  if config_row.nil?
    missing_config << algo_id
    next
  end

  matched_rows << { algo_id: algo_id, config: config_row, perf: perf_row }
end

unless missing_config.empty?
  warn "WARNING: #{missing_config.size} performance algos missing from config: #{missing_config.sort.join(', ')}"
end

allowed_rows =
  matched_rows.select do |entry|
    key = allowed_group_key(entry[:config][VARIABLE_1], entry[:config][VARIABLE_2])
    allowed_lookup.key?(key)
  end

group_averages = build_group_averages(allowed_rows)
write_group_averages_csv(group_averages) if WRITE_OUTPUT_FILE

puts "compare 2 variables: #{VARIABLE_1} + #{VARIABLE_2}"
puts "groups mode: #{DYNAMIC_GROUPS_MODE ? 'dynamic' : 'explicit'}"
puts 'allowed groups:'
ALLOWED_GROUPS.each do |var1_value, var2_value|
  puts "  #{VARIABLE_1}=#{var1_value}, #{VARIABLE_2}=#{var2_value}"
end
puts "algos in performance output: #{perf_rows.size}"
puts "algos in allowed groups: #{allowed_rows.size}"
puts
print_group_averages(group_averages, allowed_rows)
puts
puts "wrote group averages to #{GROUP_AVERAGES_OUTPUT_PATH}" if WRITE_OUTPUT_FILE
