#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare two config variables using explicit allowed (var1, var2) groups only.
# Within each config signature (all other fields equal), pairs algos that differ on
# exactly one variable while the other stays fixed — only when both tuples are allowed.

require 'csv'
require 'set'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR)
PERF_PATH = File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_output.csv')

VARIABLE_1 = 'forget_about_latest_breakdown_after_x_15m_candles'
VARIABLE_2 = 'entry_max_minutes_after_bdend'

# Each row is one allowed group: [variable_1_value, variable_2_value]
ALLOWED_GROUPS = [
  [6, 75],
  [11, 75],
  [6, 150],
  [11, 150]
].freeze

PERF_FIELDS = %w[
  timeVSprofit
  percentSum_w_roll
  avgDurationHours
  tradesCount
].freeze

OUTPUT_PATH = File.join(
  SCRIPT_DIR,
  "compare_2variables_#{VARIABLE_1}_#{VARIABLE_2}_pairs.csv"
)

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

def format_percent(numerator, denominator)
  return 'n/a' if denominator.zero?

  format('%.1f%%', 100.0 * numerator / denominator)
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

def print_group_averages(group_averages)
  puts '=' * 72
  puts 'PER-GROUP AVERAGES (before group vs group comparison)'
  puts '=' * 72
  group_averages.each do |group|
    puts allowed_group_label(group[:variable_1], group[:variable_2]) + " (algos=#{group[:algo_count]}):"
    if group[:algo_count].zero?
      puts '  (no algos with performance data)'
      next
    end

    PERF_FIELDS.each do |field|
      puts "  avg perf_#{field}=#{format_float(group[:averages][field], perf_field_decimals(field))}"
    end
  end
end

def group_average_lookup(group_averages)
  group_averages.each_with_object({}) do |group, memo|
    memo[allowed_group_key(group[:variable_1], group[:variable_2])] = group
  end
end

def print_group_vs_group_from_averages(group_averages)
  lookup = group_average_lookup(group_averages)
  puts
  puts '=' * 72
  puts 'GROUP VS GROUP (from per-group averages)'
  puts '=' * 72

  print_variable_fixed_comparisons(
    lookup,
    fixed_variable: VARIABLE_2,
    varied_variable: VARIABLE_1
  )
  puts
  print_variable_fixed_comparisons(
    lookup,
    fixed_variable: VARIABLE_1,
    varied_variable: VARIABLE_2
  )
end

def print_variable_fixed_comparisons(lookup, fixed_variable:, varied_variable:)
  varied_pairs =
    ALLOWED_GROUPS
    .map { |var1_value, var2_value| [normalize_group_value(var1_value), normalize_group_value(var2_value)] }
    .combination(2)
    .select do |(left_var1, left_var2), (right_var1, right_var2)|
      if fixed_variable == VARIABLE_1
        left_var1 == right_var1 && left_var2 != right_var2
      else
        left_var2 == right_var2 && left_var1 != right_var1
      end
    end
    .map do |(left_var1, left_var2), (right_var1, right_var2)|
      left_key = allowed_group_key(left_var1, left_var2)
      right_key = allowed_group_key(right_var1, right_var2)
      fixed_value = fixed_variable == VARIABLE_1 ? left_var1 : left_var2
      left_varied = varied_variable == VARIABLE_1 ? left_var1 : left_var2
      right_varied = varied_variable == VARIABLE_1 ? right_var1 : right_var2
      [fixed_value, left_key, right_key, left_varied, right_varied]
    end
    .uniq

  puts "#{varied_variable} compared at fixed #{fixed_variable}:"
  if varied_pairs.empty?
    puts '  (no comparisons)'
    return
  end

  varied_pairs.each do |fixed_value, left_key, right_key, left_varied, right_varied|
    left_group = lookup[left_key]
    right_group = lookup[right_key]
    puts "  fixed #{fixed_variable}=#{fixed_value}: #{varied_variable}=#{left_varied} vs #{right_varied}"
    if left_group[:algo_count].zero? || right_group[:algo_count].zero?
      puts '    skipped (missing algos in one or both groups)'
      next
    end

    PERF_FIELDS.each do |field|
      left_avg = left_group[:averages][field]
      right_avg = right_group[:averages][field]
      winner =
        if left_avg.nil? || right_avg.nil?
          'n/a'
        elsif left_avg == right_avg
          'tie'
        elsif left_avg > right_avg
          left_varied
        else
          right_varied
        end
      puts "    perf_#{field}: #{left_varied}=#{format_float(left_avg, perf_field_decimals(field))} vs " \
           "#{right_varied}=#{format_float(right_avg, perf_field_decimals(field))} -> winner #{winner}"
    end
  end
end

def normalize_group_value(value)
  text = value.to_s.strip
  return text.to_i.to_s if text.match?(/\A-?\d+\z/)

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

def config_signature_excluding(row, *exclude_headers)
  exclude = exclude_headers.map(&:to_s).to_set
  exclude.add('algo_id')
  row.headers
     .reject { |header| exclude.include?(header) }
     .map { |header| row[header].to_s }
     .join("\x1f")
end

def pair_winner(left_metric, right_metric)
  return 'tie' if left_metric.nil? || right_metric.nil?
  return 'tie' if left_metric == right_metric

  left_metric > right_metric ? 'left' : 'right'
end

def build_signature_groups(matched_rows, allowed_lookup)
  groups = Hash.new { |hash, key| hash[key] = {} }

  matched_rows.each do |entry|
    var1 = normalize_group_value(entry[:config][VARIABLE_1])
    var2 = normalize_group_value(entry[:config][VARIABLE_2])
    group_key = allowed_group_key(var1, var2)
    next unless allowed_lookup.key?(group_key)

    signature = config_signature_excluding(entry[:config], VARIABLE_1, VARIABLE_2)
    groups[signature][group_key] = entry
  end

  groups
end

def build_comparison_pairs(signature_groups)
  pairs = []
  group_id = 0

  signature_groups.sort_by { |_signature, entries_by_group| entries_by_group.values.map { |e| e[:algo_id].to_i }.min }.each do |_signature, entries_by_group|
    by_var1 = Hash.new { |hash, key| hash[key] = {} }
    by_var2 = Hash.new { |hash, key| hash[key] = {} }

    entries_by_group.each do |_group_key, entry|
      var1 = normalize_group_value(entry[:config][VARIABLE_1])
      var2 = normalize_group_value(entry[:config][VARIABLE_2])
      by_var1[var1][var2] = entry
      by_var2[var2][var1] = entry
    end

    by_var1.each do |var1, entries_by_var2|
      sorted_var2 = entries_by_var2.keys.sort_by { |value| [value.to_s.match?(/\A-?\d+\z/) ? 0 : 1, value.to_s] }
      sorted_var2.combination(2).each do |left_var2, right_var2|
        left = entries_by_var2[left_var2]
        right = entries_by_var2[right_var2]
        group_id += 1
        pairs << {
          group_id: group_id,
          compare_kind: "#{VARIABLE_2}_at_fixed_#{VARIABLE_1}",
          fixed_variable: VARIABLE_1,
          fixed_value: var1,
          varied_variable: VARIABLE_2,
          left: left,
          right: right
        }
      end
    end

    by_var2.each do |var2, entries_by_var1|
      sorted_var1 = entries_by_var1.keys.sort_by { |value| [value.to_s.match?(/\A-?\d+\z/) ? 0 : 1, value.to_s] }
      sorted_var1.combination(2).each do |left_var1, right_var1|
        left = entries_by_var1[left_var1]
        right = entries_by_var1[right_var1]
        group_id += 1
        pairs << {
          group_id: group_id,
          compare_kind: "#{VARIABLE_1}_at_fixed_#{VARIABLE_2}",
          fixed_variable: VARIABLE_2,
          fixed_value: var2,
          varied_variable: VARIABLE_1,
          left: left,
          right: right
        }
      end
    end
  end

  pairs
end

def pair_output_row(pair)
  left = pair[:left]
  right = pair[:right]
  left_var1 = normalize_group_value(left[:config][VARIABLE_1])
  left_var2 = normalize_group_value(left[:config][VARIABLE_2])
  right_var1 = normalize_group_value(right[:config][VARIABLE_1])
  right_var2 = normalize_group_value(right[:config][VARIABLE_2])

  row = {
    'group_id' => pair[:group_id],
    'compare_kind' => pair[:compare_kind],
    'fixed_variable' => pair[:fixed_variable],
    'fixed_value' => pair[:fixed_value].to_s,
    'varied_variable' => pair[:varied_variable],
    'left_algo_id' => left[:algo_id],
    "left_#{VARIABLE_1}" => left_var1,
    "left_#{VARIABLE_2}" => left_var2,
    'right_algo_id' => right[:algo_id],
    "right_#{VARIABLE_1}" => right_var1,
    "right_#{VARIABLE_2}" => right_var2
  }

  PERF_FIELDS.each do |field|
    left_metric = parse_float(left[:perf][field])
    right_metric = parse_float(right[:perf][field])
    decimals = field == 'percentSum_w_roll' || field == 'tradesCount' ? 2 : 3
    row["left_perf_#{field}"] = format_float(left_metric, decimals)
    row["right_perf_#{field}"] = format_float(right_metric, decimals)

    winner = pair_winner(left_metric, right_metric)
    row["winner_perf_#{field}"] =
      case winner
      when 'left'
        pair[:varied_variable] == VARIABLE_1 ? left_var1 : left_var2
      when 'right'
        pair[:varied_variable] == VARIABLE_1 ? right_var1 : right_var2
      else
        'tie'
      end
  end

  row
end

def build_win_stats(pairs, varied_variable)
  stats = PERF_FIELDS.to_h do |field|
    [field, Hash.new { |hash, key| hash[key] = { wins: 0, ties: 0, missing: 0 } }]
  end

  pairs.each do |pair|
    next unless pair[:varied_variable] == varied_variable

    left_value = normalize_group_value(pair[:left][:config][varied_variable])
    right_value = normalize_group_value(pair[:right][:config][varied_variable])

    PERF_FIELDS.each do |field|
      left_metric = parse_float(pair[:left][:perf][field])
      right_metric = parse_float(pair[:right][:perf][field])
      field_stats = stats[field]

      if left_metric.nil? || right_metric.nil?
        field_stats[left_value][:missing] += 1
        field_stats[right_value][:missing] += 1
        next
      end

      winner = pair_winner(left_metric, right_metric)
      case winner
      when 'left'
        field_stats[left_value][:wins] += 1
      when 'right'
        field_stats[right_value][:wins] += 1
      else
        field_stats[left_value][:ties] += 1
        field_stats[right_value][:ties] += 1
      end
    end
  end

  stats
end

def print_win_stats(label, varied_variable, stats, pair_count)
  puts "#{label} wins (#{varied_variable} varied, other variable held fixed):"
  if pair_count.zero?
    puts '  (no pairs)'
    return
  end

  values = stats.values.flat_map(&:keys).uniq.sort_by do |value|
    value.match?(/\A-?\d+\z/) ? [0, value.to_i, value] : [1, value]
  end

  PERF_FIELDS.each do |field|
    puts "  perf_#{field}:"
    values.each do |value|
      row = stats[field][value]
      comparable = pair_count - row[:missing]
      puts "    #{varied_variable}=#{value}: #{row[:wins]}/#{comparable} (#{format_percent(row[:wins], comparable)}), ties=#{row[:ties]}"
    end
  end
end

def print_allowed_group_summary(allowed_rows, paired_algo_ids)
  puts 'allowed group coverage:'
  ALLOWED_GROUPS.each do |var1_value, var2_value|
    group_rows = rows_for_allowed_group(allowed_rows, var1_value, var2_value)
    in_pairs = group_rows.count { |entry| paired_algo_ids.include?(entry[:algo_id]) }
    puts "  #{allowed_group_label(var1_value, var2_value)}: algos=#{group_rows.size}, in_pairs=#{in_pairs}"
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
write_group_averages_csv(group_averages)

signature_groups = build_signature_groups(allowed_rows, allowed_lookup)
pairs = build_comparison_pairs(signature_groups)
output_rows = pairs.map { |pair| pair_output_row(pair) }

headers = output_rows.flat_map(&:keys).uniq
CSV.open(OUTPUT_PATH, 'w', write_headers: true, headers: headers) do |csv|
  output_rows.each do |row|
    csv << headers.map { |header| row[header] }
  end
end

paired_algo_ids = pairs.flat_map { |pair| [pair[:left][:algo_id], pair[:right][:algo_id]] }.to_set
var1_pairs = pairs.select { |pair| pair[:varied_variable] == VARIABLE_1 }
var2_pairs = pairs.select { |pair| pair[:varied_variable] == VARIABLE_2 }

puts "compare 2 variables: #{VARIABLE_1} + #{VARIABLE_2}"
puts 'allowed groups:'
ALLOWED_GROUPS.each do |var1_value, var2_value|
  puts "  #{VARIABLE_1}=#{var1_value}, #{VARIABLE_2}=#{var2_value}"
end
puts "algos in performance output: #{perf_rows.size}"
puts "algos in allowed groups: #{allowed_rows.size}"
puts
print_group_averages(group_averages)
print_group_vs_group_from_averages(group_averages)
puts
puts '=' * 72
puts 'DIRECT ALGO PAIRS (same config except allowed (var1, var2) tuple)'
puts '=' * 72
puts "config signatures with at least one allowed algo: #{signature_groups.size}"
puts "comparison pairs: #{pairs.size}"
puts "  #{VARIABLE_1} varied (#{VARIABLE_2} held fixed): #{var1_pairs.size}"
puts "  #{VARIABLE_2} varied (#{VARIABLE_1} held fixed): #{var2_pairs.size}"
puts "algos in at least one pair: #{paired_algo_ids.size}"
puts "algos in allowed groups but not paired: #{allowed_rows.size - paired_algo_ids.size}"
puts
print_allowed_group_summary(allowed_rows, paired_algo_ids)
puts
if pairs.empty?
  puts 'no direct pairs found (need two algos with identical config except the allowed (var1, var2) tuple).'
  puts
end

print_win_stats('variable_1', VARIABLE_1, build_win_stats(var1_pairs, VARIABLE_1), var1_pairs.size)
puts
print_win_stats('variable_2', VARIABLE_2, build_win_stats(var2_pairs, VARIABLE_2), var2_pairs.size)
puts
puts "wrote group averages to #{GROUP_AVERAGES_OUTPUT_PATH}"
puts "wrote #{output_rows.size} pair rows to #{OUTPUT_PATH}"
