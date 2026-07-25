#!/usr/bin/env ruby
# frozen_string_literal: true

# Head-to-head performance comparison for time algos:
#   1) rule_switch_map=0 algos compared by entry time
#   2) rule_switch_map=1 algos compared by entry time
#   3) same entry time algos compared by rule_switch_map
#
# Uses all trades (no flash-crash split). Console output only.

require 'set'
require_relative 'compare_variable_analysis_lib'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_time_algos_csv.csv', SCRIPT_DIR)
PERF_PATH = File.join(SCRIPT_DIR, 'analyze_time_algos_performance_output.csv')

COMPARE_FIELD_ENTRY_TIME = 'entry_time'
COMPARE_FIELD_RULE_SWITCH_MAP = 'rule_switch_map'

OPTIONAL_COMPARE_FIELDS = %w[
  secret_tp_profit_percent_min
  secret_tp_greenguard_pricediff_at_least
].freeze

MIN_BETTER_THAN_PERCENT_DIFF = 15.0

Lib = CompareVariableAnalysisLib

class ConfigRow
  attr_reader :data

  def initialize(data)
    @data = data.transform_keys(&:to_s)
  end

  def [](key)
    @data[key.to_s]
  end

  def headers
    @data.keys
  end
end

def format_entry_time(hour, minute)
  "#{hour.to_i}:#{minute.to_i.to_s.rjust(2, '0')}"
end

def entry_time_sort_key(value)
  text = value.to_s
  hour, minute =
    if (match = text.match(/\A(\d+):(\d+)\z/))
      [match[1].to_i, match[2].to_i]
    else
      [99, 99]
    end

  [hour, minute, text]
end

def build_config_row(csv_row)
  data = csv_row.to_h
  data[COMPARE_FIELD_ENTRY_TIME] =
    format_entry_time(data['entry_hour'], data['entry_minute'])
  ConfigRow.new(data)
end

def load_matched_rows
  config_by_algo_id =
    Lib.read_csv(CONFIG_PATH).each_with_object({}) do |row, memo|
      algo_id = row['algo_id'].to_s.strip
      next if algo_id.empty?

      memo[algo_id] = build_config_row(row)
    end

  perf_rows =
    Lib.read_csv(PERF_PATH).select do |row|
      row['algoID'].to_s.strip != ''
    end

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

  [matched_rows, perf_rows.size]
end

def filter_rows(matched_rows, compare_variable, value)
  matched_rows.select { |entry| entry[:config][compare_variable].to_s == value.to_s }
end

def print_comparison_section(title, matched_rows, compare_variable, sort_key: nil, signature_exclude_variables: [])
  puts '=' * 72
  puts title
  puts '=' * 72

  if matched_rows.size < 2
    puts "algos: #{matched_rows.size} (need at least 2 for head-to-head comparison)"
    puts
    return
  end

  run_result =
    Lib.build_variable_compare_run(
      matched_rows,
      compare_variable,
      signature_exclude_variables: signature_exclude_variables
    )
  compared_count = run_result[:paired_algo_ids].size
  unpaired_count = matched_rows.size - compared_count

  puts "algos: #{matched_rows.size}"
  puts "algos in head-to-head pairs: #{compared_count}"
  puts "algos without a pair: #{unpaired_count}"
  puts "groups found: #{run_result[:group_count]}"
  puts "pairs found: #{run_result[:pair_count]}"
  puts

  line_opts = {
    sort_by_avg: true,
    min_percent_diff: MIN_BETTER_THAN_PERCENT_DIFF,
    include_secret_tp_split: false
  }
  line_opts[:sort_key] = sort_key if sort_key
  Lib.compare_analysis_lines(run_result[:pairs], compare_variable, **line_opts).each { |line| puts line }
  puts
end

def maybe_print_optional_field_comparisons(matched_rows)
  OPTIONAL_COMPARE_FIELDS.each do |field|
    values = matched_rows.map { |entry| entry[:config][field].to_s }.reject(&:empty?).uniq
    next if values.size < 2

    print_comparison_section(
      "OPTIONAL: compare by #{field}",
      matched_rows,
      field
    )
  end
end

unless File.file?(CONFIG_PATH)
  warn "ERROR: config file not found: #{CONFIG_PATH}"
  exit 1
end

unless File.file?(PERF_PATH)
  warn "ERROR: performance file not found: #{PERF_PATH}"
  exit 1
end

matched_rows, perf_row_count = load_matched_rows
if matched_rows.empty?
  warn 'ERROR: no matched time algo rows.'
  exit 1
end

puts "time algo type performance (all trades)"
puts "performance file: #{PERF_PATH}"
puts "config file: #{CONFIG_PATH}"
puts "algos in analyze_time_algos_performance_output: #{perf_row_count}"
puts "matched config algos: #{matched_rows.size}"
puts

rule0_rows = filter_rows(matched_rows, COMPARE_FIELD_RULE_SWITCH_MAP, 0)
rule1_rows = filter_rows(matched_rows, COMPARE_FIELD_RULE_SWITCH_MAP, 1)

print_comparison_section(
  'GROUP 1: rule_switch_map=0 — compare entry times',
  rule0_rows,
  COMPARE_FIELD_ENTRY_TIME,
  sort_key: method(:entry_time_sort_key),
  signature_exclude_variables: %w[entry_hour entry_minute]
)

print_comparison_section(
  'GROUP 2: rule_switch_map=1 — compare entry times',
  rule1_rows,
  COMPARE_FIELD_ENTRY_TIME,
  sort_key: method(:entry_time_sort_key),
  signature_exclude_variables: %w[entry_hour entry_minute]
)

entry_times =
  matched_rows
  .map { |entry| entry[:config][COMPARE_FIELD_ENTRY_TIME].to_s }
  .uniq
  .sort_by { |entry_time| entry_time_sort_key(entry_time) }

entry_times.each do |entry_time|
  rows_at_time = filter_rows(matched_rows, COMPARE_FIELD_ENTRY_TIME, entry_time)
  print_comparison_section(
    "GROUP 3: entry_time=#{entry_time} — compare rule_switch_map",
    rows_at_time,
    COMPARE_FIELD_RULE_SWITCH_MAP,
    signature_exclude_variables: [COMPARE_FIELD_ENTRY_TIME, 'entry_hour', 'entry_minute']
  )
end

maybe_print_optional_field_comparisons(matched_rows)
