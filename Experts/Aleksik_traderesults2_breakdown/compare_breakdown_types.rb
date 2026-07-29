#!/usr/bin/env ruby
# frozen_string_literal: true

# Head-to-head comparison of breakdown streak continuation modes:
#   CLOSES, OHLC_AVG, LOW, OC_MID, HL_MID
# (config column: breakdown_streak_continuation_mode)
#
# Prints the same metrics as compare_variable.rb:
#   perf_timeVSprofit
#   perf_percentSum_w_roll (+ group 0 secret TP / group non 0 secret TP)
#   perf_avgDurationHours (+ secret TP splits)
#   perf_tradesCount (+ secret TP splits)

require 'set'
require_relative 'compare_variable_analysis_lib'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR)
PERF_PATH = File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_output.csv')

COMPARE_VARIABLE = 'breakdown_streak_continuation_mode'
BREAKDOWN_TYPES = %w[CLOSES OHLC_AVG LOW OC_MID HL_MID].freeze
MIN_BETTER_THAN_PERCENT_DIFF = 33.0
OUTPUT_PATH = File.join(SCRIPT_DIR, 'compare_breakdown_types_pairs.csv')

CLOSETRADE_CONFIG_COLUMNS = %w[
  closetrade_after_some_time
  closetrade_after_some_time_butOnlyIfProfit
  closetrade_after_some_time_but_ProfitPercent_Needed
  closetrade_after_x_minutes_from_breakdown
].freeze

Lib = CompareVariableAnalysisLib

def load_matched_rows
  config_by_algo_id =
    Lib.read_csv(CONFIG_PATH).each_with_object({}) do |row, memo|
      algo_id = row['algo_id'].to_s.strip
      next if algo_id.empty?

      memo[algo_id] = row
    end

  perf_rows =
    Lib.read_csv(PERF_PATH).select do |row|
      row['algoID'].to_s.strip != ''
    end

  matched_rows = []
  missing_config = []
  unknown_breakdown_types = Set.new

  perf_rows.each do |perf_row|
    algo_id = perf_row['algoID'].to_s.strip
    config_row = config_by_algo_id[algo_id]
    if config_row.nil?
      missing_config << algo_id
      next
    end

    breakdown_type = config_row[COMPARE_VARIABLE].to_s
    unless BREAKDOWN_TYPES.include?(breakdown_type)
      unknown_breakdown_types << breakdown_type
      next
    end

    matched_rows << { algo_id: algo_id, config: config_row, perf: perf_row }
  end

  unless missing_config.empty?
    warn "WARNING: #{missing_config.size} performance algos missing from config: #{missing_config.sort.join(', ')}"
  end
  unless unknown_breakdown_types.empty?
    warn "WARNING: skipped algos with unknown #{COMPARE_VARIABLE}: #{unknown_breakdown_types.to_a.sort.join(', ')}"
  end

  [matched_rows, perf_rows.size]
end

CompareVariableAnalysisLib.refresh_breakdown_algos_performance_output!(SCRIPT_DIR)

unless File.file?(CONFIG_PATH)
  warn "ERROR: config file not found: #{CONFIG_PATH}"
  exit 1
end

unless Lib.read_csv(CONFIG_PATH).headers.include?(COMPARE_VARIABLE)
  warn "ERROR: compare variable not found in config: #{COMPARE_VARIABLE}"
  exit 1
end

matched_rows, perf_row_count = load_matched_rows
run_result = Lib.build_variable_compare_run(matched_rows, COMPARE_VARIABLE)

Lib.write_compare_pairs_csv(
  OUTPUT_PATH,
  run_result[:output_rows],
  COMPARE_VARIABLE,
  closetrade_config_columns: CLOSETRADE_CONFIG_COLUMNS
)

puts "compare breakdown types (#{COMPARE_VARIABLE}): #{BREAKDOWN_TYPES.join(', ')}"
puts "algos in analyze_breakdown_algos_performance_output: #{perf_row_count}"
puts "algos in comparison (known breakdown types): #{matched_rows.size}"
puts "algos without a pair: #{run_result[:unpaired_count]} (#{Lib.format_percent(run_result[:unpaired_count], matched_rows.size)} of compared)"
puts "groups found: #{run_result[:group_count]}"
puts "pairs found: #{run_result[:pair_count]}"
puts "unpaired groups written: #{run_result[:unpaired_written]}"
Lib.compare_analysis_lines(
  run_result[:pairs],
  COMPARE_VARIABLE,
  sort_by_avg: true,
  min_percent_diff: MIN_BETTER_THAN_PERCENT_DIFF
).each { |line| puts line }
puts
puts "wrote #{run_result[:output_rows].size} rows to #{OUTPUT_PATH}"
