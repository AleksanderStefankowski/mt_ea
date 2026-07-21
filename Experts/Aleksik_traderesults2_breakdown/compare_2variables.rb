#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'compare_variable_analysis_lib'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR)
PERF_PATH = File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_output.csv')

# Independent head-to-head analysis for two config columns.
# When comparing COMPARE_VARIABLE_1, grouping ignores both var1 and var2 (so var2 does not split groups).
# When comparing COMPARE_VARIABLE_2, grouping ignores both var2 and var1 (so var1 does not split groups).
# Supported values: any column in aleksik2_r_read_breakdown_algos_csv.csv except algo_id, e.g.
#   stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count, expiry_minutes,
#   after_bd_need_x_15greenc, secret_tp_range_percent, entryrange_range_percentspot, ...
COMPARE_VARIABLE_1 = 'after_bd_need_x_15greenc'
COMPARE_VARIABLE_2 = 'secret_tp_range_percent'

CLOSETRADE_CONFIG_COLUMNS = %w[
  closetrade_after_some_time
  closetrade_after_some_time_butOnlyIfProfit
  closetrade_after_some_time_but_ProfitPercent_Needed
  closetrade_after_x_minutes_from_breakdown
].freeze

Lib = CompareVariableAnalysisLib

def output_path_for(compare_variable)
  File.join(
    SCRIPT_DIR,
    "compare_2variables_#{COMPARE_VARIABLE_1}_#{COMPARE_VARIABLE_2}_pairs_#{compare_variable}.csv"
  )
end

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

def run_variable_analysis(matched_rows, perf_row_count, compare_variable, other_variable)
  puts
  puts '=' * 72
  puts "INDEPENDENT ANALYSIS: #{compare_variable}"
  puts '=' * 72

  run_result =
    Lib.build_variable_compare_run(
      matched_rows,
      compare_variable,
      signature_exclude_variables: [other_variable]
    )

  output_path = output_path_for(compare_variable)
  Lib.write_compare_pairs_csv(
    output_path,
    run_result[:output_rows],
    compare_variable,
    closetrade_config_columns: CLOSETRADE_CONFIG_COLUMNS
  )

  Lib.print_variable_compare_summary(compare_variable, perf_row_count, run_result)
  puts "wrote #{run_result[:output_rows].size} rows to #{output_path}"
end

unless File.file?(CONFIG_PATH)
  warn "ERROR: config file not found: #{CONFIG_PATH}"
  exit 1
end

unless File.file?(PERF_PATH)
  warn "ERROR: performance file not found: #{PERF_PATH}"
  exit 1
end

config_headers = Lib.read_csv(CONFIG_PATH).headers
[COMPARE_VARIABLE_1, COMPARE_VARIABLE_2].each do |variable|
  unless config_headers.include?(variable)
    available = config_headers.reject { |header| header == 'algo_id' }
    warn "ERROR: compare variable not found in config: #{variable}"
    warn "Available config columns: #{available.join(', ')}"
    exit 1
  end
end

if COMPARE_VARIABLE_1 == COMPARE_VARIABLE_2
  warn 'ERROR: COMPARE_VARIABLE_1 and COMPARE_VARIABLE_2 must be different'
  exit 1
end

matched_rows, perf_row_count = load_matched_rows

puts "compare 2 variables: #{COMPARE_VARIABLE_1} + #{COMPARE_VARIABLE_2}"
puts 'Each variable is analyzed independently; the other variable is excluded from grouping.'

run_variable_analysis(matched_rows, perf_row_count, COMPARE_VARIABLE_1, COMPARE_VARIABLE_2)
run_variable_analysis(matched_rows, perf_row_count, COMPARE_VARIABLE_2, COMPARE_VARIABLE_1)
