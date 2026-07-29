#!/usr/bin/env ruby
# frozen_string_literal: true

# Classify input algos into exit groups from config, then compare group averages
# using the same perf metrics as compare_variable.rb:
#   perf_timeVSprofit
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

require_relative 'compare_variable_analysis_lib'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR)
PERF_PATH = File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_output.csv')
MIN_BETTER_THAN_PERCENT_DIFF = 33.0

# Edit algo ids here. Blank lines and # comments are ignored.
INPUT_ALGO_IDS = <<~IDS
20000007
20000016
20000005
20000014
20000090
20000171
20000087
20000168
20000006
20000015
20000089
20000170
20000093
20000174
20000063
20000144
20000086
20000167
20000060
20000141
20000092
20000173
20000081
20000162
20000083
20000164
20000066
20000147
20000094
20000175
20000036
20000117
20000091
20000172
20000062
20000143
20000039
20000120
20000033
20000114
20000053
20000134
20000059
20000140
20000065
20000146
20000035
20000116
20000082
20000163
20000084
20000165
20000080
20000161
20000054
20000135
20000088
20000169
20000038
20000119
20000067
20000148
20000064
20000145
20000056
20000137
20000032
20000113
20000058
20000139
20000103
20000184
20000055
20000136
20000078
20000159
20000100
20000181
20000061
20000142
20000040
20000121
20000097
20000178
20000057
20000138
20000085
20000166
20000037
20000118
20000027
20000108
20000076
20000157
20000073
20000154
20000070
20000151
20000030
20000111
20000049
20000130
20000099
20000180
20000102
20000183
20000096
20000177
20000051
20000132
20000046
20000127
20000026
20000107
20000034
20000115
20000072
20000153
20000043
20000124
20000075
20000156
20000048
20000129
20000069
20000150
20000079
20000160
20000045
20000126
20000077
20000158
20000047
20000128
20000042
20000123
20000050
20000131
20000029
20000110
20000101
20000182
20000044
20000125
20000098
20000179
20000041
20000122
20000095
20000176
20000031
20000112
20000074
20000155
20000071
20000152
20000068
20000149
20000024
20000105
20000028
20000109
20000052
20000133
20000023
20000104
20000025
20000106
20000003
20000001
20000004
20000000
20000002
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
  ['perf_timeVSprofit', 'timeVSprofit', 3],
  ['perf_percentSum_w_roll', 'percentSum_w_roll', 2],
  ['perf_avgDurationHours', 'avgDurationHours', 3],
  ['perf_tradesCount', 'tradesCount', 2]
].freeze

Lib = CompareVariableAnalysisLib

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
    timeVSprofit: Lib.average(entries.map { |entry| Lib.parse_float(entry[:perf]['timeVSprofit']) }),
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
    puts "  avg perf_timeVSprofit=#{Lib.format_float(metrics[:timeVSprofit])}"
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

input_algo_ids = parse_input_algo_ids(INPUT_ALGO_IDS)
if input_algo_ids.empty?
  warn 'ERROR: INPUT_ALGO_IDS is empty (add algo ids to the heredoc at top of script)'
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
puts "input algos: #{input_algo_ids.size}"
puts "matched algos: #{matched_rows.size}"
EXIT_GROUP_ORDER.each do |group_key|
  count = grouped_entries[group_key]&.size || 0
  puts "  #{EXIT_GROUP_LABELS[group_key]}: #{count}"
end
puts

print_group_summary(grouped_entries)
print_metric_comparisons(grouped_entries)
