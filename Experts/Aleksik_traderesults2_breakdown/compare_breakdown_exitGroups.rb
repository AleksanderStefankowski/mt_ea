#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'alert_done_common'

# Classify input algos into exit groups from config, then compare group averages
# using the same perf metrics as compare_variable.rb:
#   perf_profitSumVSexposure
#   perf_percentSum_w_roll
#   perf_avgDurationHours
#   perf_tradesCount
#
# Exit groups:
#   0 secret TP, closetrade_after_some_time=false
#   0 secret TP, closetrade_after_some_time=true
#   non-zero secret_tp_range_percent
#
# Raises if an algo has non-zero secret TP and closetrade_after_some_time=true.
#
# When closetrade=true algos are present, also prints per-combo stats for each
# profit_percent x minutes_from_breakdown pair from smash_BREAKDOWN_create_combinationsMap_csv.rb:
#   DESIRED_CLOSETRADE_AFTER_SOME_TIME_BUT_PROFITPERCENT_NEEDED
#   DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN
#
# Algo set modes:
#   :all_from_performance (default) — all numeric algo ids from perf CSV; no INPUT_ALGO_IDS needed
#   :closetrade_after_some_time_true — same source, only closetrade_after_some_time=true
#   :input_algo_ids — use INPUT_ALGO_IDS heredoc (must not be empty)

require_relative 'compare_variable_analysis_lib'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR)
PERF_PATH = File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_output.csv')
COMBINATIONS_MAP_CREATOR_PATH =
  File.expand_path('../Aleksik2/smash_BREAKDOWN_create_combinationsMap_csv.rb', SCRIPT_DIR)
MIN_BETTER_THAN_PERCENT_DIFF = 33.0

# :all_from_performance | :closetrade_after_some_time_true | :input_algo_ids
ALGO_SET_MODE = :closetrade_after_some_time_true

# Edit algo ids here when ALGO_SET_MODE = :input_algo_ids. Blank lines and # comments are ignored.
INPUT_ALGO_IDS = <<~IDS

IDS

EXIT_GROUP_ORDER = %i[
  zero_secret_tp_no_time_exit
  zero_secret_tp_time_exit
  non_zero_secret_tp
].freeze

EXIT_GROUP_LABELS = {
  zero_secret_tp_no_time_exit: '0 secret TP, closetrade=false',
  zero_secret_tp_time_exit: '0 secret TP, closetrade=true',
  non_zero_secret_tp: 'non-zero secret TP'
}.freeze

METRICS = [
  ['perf_profitSumVSexposure', 'profitSumVSexposure', Lib::TIMEVSPROFIT_DECIMALS],
  ['perf_percentSum_w_roll', 'percentSum_w_roll', 2],
  ['perf_avgDurationHours', 'avgDurationHours', 3],
  ['perf_tradesCount', 'tradesCount', 2]
].freeze

Lib = CompareVariableAnalysisLib

ALGO_SET_MODES = %i[
  all_from_performance
  closetrade_after_some_time_true
  input_algo_ids
].freeze

def catalogable_algo_id?(algo_id)
  algo_id.to_s.strip.match?(/\A\d+\z/)
end

def algo_ids_from_performance_output
  Lib.read_csv(PERF_PATH).filter_map do |row|
    algo_id = row['algoID'].to_s.strip
    next if algo_id.empty?
    next unless catalogable_algo_id?(algo_id)

    algo_id
  end.uniq.sort_by(&:to_i)
end

def resolve_input_algo_ids(config_by_algo_id)
  unless ALGO_SET_MODES.include?(ALGO_SET_MODE)
    warn "ERROR: unknown ALGO_SET_MODE #{ALGO_SET_MODE.inspect} " \
         "(expected #{ALGO_SET_MODES.map(&:inspect).join(', ')})"
    exit 1
  end

  case ALGO_SET_MODE
  when :input_algo_ids
    ids = parse_input_algo_ids(INPUT_ALGO_IDS)
    if ids.empty?
      warn 'ERROR: ALGO_SET_MODE=:input_algo_ids but INPUT_ALGO_IDS is empty ' \
           '(add algo ids to the heredoc at top of script)'
      exit 1
    end
    ids
  when :all_from_performance
    algo_ids_from_performance_output
  when :closetrade_after_some_time_true
    algo_ids_from_performance_output.select do |algo_id|
      config_row = config_by_algo_id[algo_id]
      config_row && config_bool(config_row['closetrade_after_some_time'])
    end
  end
end

def parse_input_algo_ids(text)
  text.each_line.filter_map do |line|
    stripped = line.strip
    next if stripped.empty?
    next if stripped.start_with?('#')

    unless stripped.match?(/\A\d+\z/)
      raise "ERROR: invalid algo id line: #{line.inspect} (expected digits only)"
    end

    stripped
  end.uniq
end

def config_bool(value)
  %w[true 1 yes].include?(value.to_s.strip.downcase)
end

def parse_desired_array_constant(path, constant_name)
  unless File.file?(path)
    warn "ERROR: combinations map creator not found: #{path}"
    exit 1
  end

  content = File.read(path, encoding: 'bom|utf-8')
  pattern = /#{Regexp.escape(constant_name)}\s*=\s*\[([^\]]+)\]\.freeze/
  match = content.match(pattern)
  unless match
    warn "ERROR: #{constant_name} not found in #{path}"
    exit 1
  end

  match[1].split(',').map(&:strip).reject(&:empty?).map do |token|
    if token.match?(/\A-?\d+\z/)
      token.to_i
    else
      Float(token)
    end
  end
end

def closetrade_combo_grid_from_map_creator
  profit_values = parse_desired_array_constant(
    COMBINATIONS_MAP_CREATOR_PATH,
    'DESIRED_CLOSETRADE_AFTER_SOME_TIME_BUT_PROFITPERCENT_NEEDED'
  )
  minutes_values = parse_desired_array_constant(
    COMBINATIONS_MAP_CREATOR_PATH,
    'DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN'
  )
  [profit_values, minutes_values]
end

def normalize_combo_scalar(value)
  text = value.to_s.strip
  return nil if text.empty?

  float_match = text.match(/\A-?\d+(?:\.\d+)?\z/)
  return format('%.10g', Float(text)) if float_match

  text
end

def closetrade_combo_match?(config_row, profit_needed, minutes_from_breakdown)
  config_profit = normalize_combo_scalar(config_row['closetrade_after_some_time_but_ProfitPercent_Needed'])
  config_minutes = normalize_combo_scalar(config_row['closetrade_after_x_minutes_from_breakdown'])
  target_profit = normalize_combo_scalar(profit_needed)
  target_minutes = normalize_combo_scalar(minutes_from_breakdown)
  config_profit == target_profit && config_minutes == target_minutes
end

def classify_exit_group(config_row, algo_id:)
  secret_tp = Lib.parse_float(config_row['secret_tp_range_percent'])
  closetrade = config_bool(config_row['closetrade_after_some_time'])

  if secret_tp.nil?
    raise "ERROR: algo #{algo_id}: missing or invalid secret_tp_range_percent in config"
  end

  if !secret_tp.zero? && closetrade
    raise "ERROR: algo #{algo_id}: non-zero secret_tp_range_percent (#{secret_tp.to_i}) " \
          'with closetrade_after_some_time=true is ambiguous (not in any exit group)'
  end

  if !secret_tp.zero?
    :non_zero_secret_tp
  elsif closetrade
    :zero_secret_tp_time_exit
  else
    :zero_secret_tp_no_time_exit
  end
end

def group_metrics(entries)
  {
    profitSumVSexposure: Lib.average(entries.map { |entry| Lib.parse_float(entry[:perf]['profitSumVSexposure']) }),
    percentSum_w_roll: Lib.average(entries.map { |entry| Lib.parse_float(entry[:perf]['percentSum_w_roll']) }),
    avgDurationHours: Lib.average(entries.map { |entry| Lib.parse_float(entry[:perf]['avgDurationHours']) }),
    tradesCount: Lib.average(entries.map { |entry| Lib.parse_float(entry[:perf]['tradesCount']) })
  }
end

def print_group_summary(grouped_entries)
  puts '=== exit group summary ==='
  EXIT_GROUP_ORDER.each do |group_key|
    entries = grouped_entries[group_key]
    label = EXIT_GROUP_LABELS[group_key]
    if entries.nil? || entries.empty?
      puts "#{label}: (no algos)"
      next
    end

    metrics = group_metrics(entries)
    algo_ids = entries.map { |entry| entry[:algo_id] }.sort_by(&:to_i).join(', ')
    puts "#{label}: algos=#{entries.size} [#{algo_ids}]"
    puts "  avg perf_profitSumVSexposure=#{Lib.format_float(metrics[:profitSumVSexposure], Lib::TIMEVSPROFIT_DECIMALS)}"
    puts "  avg perf_percentSum_w_roll=#{Lib.format_float(metrics[:percentSum_w_roll], 2)}"
    puts "  avg perf_avgDurationHours=#{Lib.format_float(metrics[:avgDurationHours])}"
    puts "  avg perf_tradesCount=#{Lib.format_float(metrics[:tradesCount], 2)}"
  end
  puts
end

def print_closetrade_combo_analysis(time_exit_entries, profit_values, minutes_values)
  puts '=== closetrade time-exit combos (from combinationsMap creator grid) ==='
  puts "map creator: #{COMBINATIONS_MAP_CREATOR_PATH}"
  puts "profit_percent grid: #{profit_values.join(', ')}"
  puts "minutes_from_breakdown grid: #{minutes_values.join(', ')}"
  puts

  combo_rows = profit_values.product(minutes_values).map do |profit, minutes|
    entries = time_exit_entries.select do |entry|
      closetrade_combo_match?(entry[:config], profit, minutes)
    end
    {
      profit: profit,
      minutes: minutes,
      entries: entries,
      metrics: entries.empty? ? nil : group_metrics(entries)
    }
  end

  matched_algo_ids = combo_rows.flat_map { |row| row[:entries].map { |entry| entry[:algo_id] } }.to_set
  unmatched = time_exit_entries.reject { |entry| matched_algo_ids.include?(entry[:algo_id]) }
  unless unmatched.empty?
    warn "WARNING: #{unmatched.size} closetrade=true algo(s) did not match any grid combo: " \
         "#{unmatched.map { |entry| entry[:algo_id] }.sort_by(&:to_i).join(', ')}"
  end

  combo_rows.sort_by { |row| -(row[:metrics]&.dig(:profitSumVSexposure) || -Float::INFINITY) }.each do |row|
    label = "closetrade_after_some_time_but_ProfitPercent_Needed=#{row[:profit]}, " \
            "closetrade_after_x_minutes_from_breakdown=#{row[:minutes]}"
    if row[:entries].empty?
      puts "#{label} (algos=0): (no algos)"
      next
    end

    metrics = row[:metrics]
    puts "#{label} (algos=#{row[:entries].size}):"
    puts "  avg perf_profitSumVSexposure=#{Lib.format_float(metrics[:profitSumVSexposure], Lib::TIMEVSPROFIT_DECIMALS)}"
    puts "  avg perf_percentSum_w_roll=#{Lib.format_float(metrics[:percentSum_w_roll], 2)}"
    puts "  avg perf_avgDurationHours=#{Lib.format_float(metrics[:avgDurationHours])}"
    puts "  avg perf_tradesCount=#{Lib.format_float(metrics[:tradesCount], 2)}"
  end
  puts
end

def print_metric_comparisons(grouped_entries)
  metric_averages_by_group = {}
  EXIT_GROUP_ORDER.each do |group_key|
    entries = grouped_entries[group_key]
    next if entries.nil? || entries.empty?

    metric_averages_by_group[group_key] = group_metrics(entries)
  end

  active_groups = EXIT_GROUP_ORDER.select { |group_key| metric_averages_by_group.key?(group_key) }
  if active_groups.size < 2
    puts '(need at least 2 exit groups with algos for head-to-head comparison)'
    return
  end

  METRICS.each do |label, field, decimals|
    puts "#{label} (group averages):"
    active_groups.each do |group_key|
      avg = metric_averages_by_group[group_key][field.to_sym]
      puts "  #{EXIT_GROUP_LABELS[group_key]}: #{Lib.format_float(avg, decimals)} (n=#{grouped_entries[group_key].size})"
    end

    active_groups.combination(2).each do |left_key, right_key|
      left_label = EXIT_GROUP_LABELS[left_key]
      right_label = EXIT_GROUP_LABELS[right_key]
      line = Lib.better_than_worse_line(
        prefix: '  ',
        field_name: 'exit_group',
        left_value: left_label,
        left_avg: metric_averages_by_group[left_key][field.to_sym],
        right_value: right_label,
        right_avg: metric_averages_by_group[right_key][field.to_sym],
        decimals: decimals,
        label: label,
        min_percent_diff: MIN_BETTER_THAN_PERCENT_DIFF
      )
      puts line if line
    end
    puts
  end
end

CompareVariableAnalysisLib.refresh_breakdown_algos_performance_output!(SCRIPT_DIR)

unless File.file?(CONFIG_PATH)
  warn "ERROR: config file not found: #{CONFIG_PATH}"
  exit 1
end

config_by_algo_id =
  Lib.read_csv(CONFIG_PATH).each_with_object({}) do |row, memo|
    algo_id = row['algo_id'].to_s.strip
    next if algo_id.empty?

    memo[algo_id] = row
  end

perf_by_algo_id =
  Lib.read_csv(PERF_PATH).each_with_object({}) do |row, memo|
    algo_id = row['algoID'].to_s.strip
    next if algo_id.empty?

    memo[algo_id] = row
  end

input_algo_ids = resolve_input_algo_ids(config_by_algo_id)
if input_algo_ids.empty?
  case ALGO_SET_MODE
  when :all_from_performance
    warn 'ERROR: no numeric algo ids found in performance output'
  when :closetrade_after_some_time_true
    warn 'ERROR: no algos with closetrade_after_some_time=true found in performance output'
  end
  exit 1
end

missing_config_from_perf = []
if %i[all_from_performance closetrade_after_some_time_true].include?(ALGO_SET_MODE)
  algo_ids_from_performance_output.each do |algo_id|
    missing_config_from_perf << algo_id if config_by_algo_id[algo_id].nil?
  end
  unless missing_config_from_perf.empty?
    warn "WARNING: #{missing_config_from_perf.size} performance algo(s) missing from config: " \
         "#{missing_config_from_perf.sort_by(&:to_i).join(', ')}"
  end
end

matched_rows = []
missing_config = []
missing_perf = []

input_algo_ids.each do |algo_id|
  config_row = config_by_algo_id[algo_id]
  if config_row.nil?
    missing_config << algo_id
    next
  end

  perf_row = perf_by_algo_id[algo_id]
  if perf_row.nil?
    missing_perf << algo_id
    next
  end

  exit_group = classify_exit_group(config_row, algo_id: algo_id)
  matched_rows << {
    algo_id: algo_id,
    exit_group: exit_group,
    config: config_row,
    perf: perf_row
  }
end

unless missing_config.empty?
  warn "ERROR: #{missing_config.size} input algo(s) missing from config: #{missing_config.sort.join(', ')}"
  exit 1
end

unless missing_perf.empty?
  warn "ERROR: #{missing_perf.size} input algo(s) missing from performance output: #{missing_perf.sort.join(', ')}"
  exit 1
end

grouped_entries = matched_rows.group_by { |entry| entry[:exit_group] }

puts "config: #{CONFIG_PATH}"
puts "performance: #{PERF_PATH}"
puts "algo set mode: #{ALGO_SET_MODE}"
puts "input algos: #{input_algo_ids.size}"
puts "matched algos: #{matched_rows.size}"
EXIT_GROUP_ORDER.each do |group_key|
  count = grouped_entries[group_key]&.size || 0
  puts "  #{EXIT_GROUP_LABELS[group_key]}: #{count}"
end
puts

print_group_summary(grouped_entries)
print_metric_comparisons(grouped_entries)

time_exit_entries = grouped_entries[:zero_secret_tp_time_exit]
if time_exit_entries&.any?
  profit_values, minutes_values = closetrade_combo_grid_from_map_creator
  print_closetrade_combo_analysis(time_exit_entries, profit_values, minutes_values)
end

play_alert_done! if __FILE__ == $PROGRAM_NAME
