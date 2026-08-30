#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'alert_done_common'

require_relative 'compare_variable_analysis_lib'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR)
PERF_PATH = File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_output.csv')

# Change this to compare algos that differ only in another config field.
# Supported COMPARE_VARIABLE values (any column in aleksik2_r_read_breakdown_algos_csv.csv except algo_id):
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
COMPARE_VARIABLE = 'secret_tp_range_percent'

WRITE_OUTPUT_FILE = false

CLOSETRADE_CONFIG_COLUMNS = %w[
  closetrade_after_some_time
  closetrade_after_some_time_butOnlyIfProfit
  closetrade_after_some_time_but_ProfitPercent_Needed
  closetrade_after_x_minutes_from_breakdown
].freeze

OUTPUT_PATH = File.join(
  SCRIPT_DIR,
  "compare_variable_#{COMPARE_VARIABLE}_pairs.csv"
)

Lib = CompareVariableAnalysisLib

def config_bool(value)
  %w[true 1 yes].include?(value.to_s.strip.downcase)
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

def print_closetrade_conditional_comparisons(pairs)
  paired_entries = Lib.paired_entries_from_pairs(pairs)
  false_entries = paired_entries.reject { |entry| config_bool(entry[:config]['closetrade_after_some_time']) }
  true_entries = paired_entries.select { |entry| config_bool(entry[:config]['closetrade_after_some_time']) }

  puts 'closetrade_after_some_time=false:'
  if false_entries.empty?
    puts '  (no paired algos)'
  else
    Lib.grouped_entries_table_lines(
      '  by secret_tp_range_percent (paired algos, per-algo averages):',
      false_entries,
      'secret_tp_range_percent'
    ).each { |line| puts line }
  end

  puts 'closetrade_after_some_time=true:'
  if true_entries.empty?
    puts '  (no paired algos)'
  else
    Lib.grouped_entries_table_lines(
      '  by closetrade_after_some_time_but_ProfitPercent_Needed:',
      true_entries,
      'closetrade_after_some_time_but_ProfitPercent_Needed'
    ).each { |line| puts line }
    puts
    Lib.grouped_entries_table_lines(
      '  by closetrade_after_x_minutes_from_breakdown:',
      true_entries,
      'closetrade_after_x_minutes_from_breakdown'
    ).each { |line| puts line }
  end
end

Lib.refresh_breakdown_algos_performance_output!(SCRIPT_DIR)

unless File.file?(CONFIG_PATH)
  warn "ERROR: config file not found: #{CONFIG_PATH}"
  exit 1
end

unless Lib.read_csv(CONFIG_PATH).headers.include?(COMPARE_VARIABLE)
  available = Lib.read_csv(CONFIG_PATH).headers.reject { |header| header == 'algo_id' }
  warn "ERROR: compare variable not found in config: #{COMPARE_VARIABLE}"
  warn "Available config columns: #{available.join(', ')}"
  exit 1
end

matched_rows, perf_row_count = load_matched_rows
run_result = Lib.build_variable_compare_run(matched_rows, COMPARE_VARIABLE)

Lib.write_compare_pairs_csv(
  OUTPUT_PATH,
  run_result[:output_rows],
  COMPARE_VARIABLE,
  closetrade_config_columns: CLOSETRADE_CONFIG_COLUMNS
) if WRITE_OUTPUT_FILE

puts "compare variable: #{COMPARE_VARIABLE}"
puts "algos in analyze_breakdown_algos_performance_output: #{perf_row_count}"
puts "algos without a pair: #{run_result[:unpaired_count]} (#{Lib.format_percent(run_result[:unpaired_count], perf_row_count)} of all)"
puts "groups found: #{run_result[:group_count]}"
puts "pairs found: #{run_result[:pair_count]}"
puts "unpaired groups written: #{run_result[:unpaired_written]}"
puts
Lib.compare_analysis_lines(run_result[:pairs], COMPARE_VARIABLE).each { |line| puts line }
puts
print_closetrade_conditional_comparisons(run_result[:pairs])
puts "wrote #{run_result[:output_rows].size} rows to #{OUTPUT_PATH}" if WRITE_OUTPUT_FILE

play_alert_done! if __FILE__ == $PROGRAM_NAME
