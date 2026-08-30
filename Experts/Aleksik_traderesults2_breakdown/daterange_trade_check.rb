#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'alert_done_common'
require_relative 'analyze_algos_performance_common'

require 'date'
require 'set'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))

# --- family toggles: edit here or pass 3 booleans on CLI ---
#   ruby daterange_trade_check.rb true true false
CHECK_BREAKDOWN = true
CHECK_TIME = true
CHECK_LEVEL = true
# Keep only algos whose ALL-time profitpercentsum is >= this.
MIN_PROFIT_PERCENT_SUM = 90
# Keep only algos whose peak_open_exposure is <= this. nil = disabled.
MAX_PEAKEXPOSURE_LESSTHANOREQUAL = 5
# Keep only algos whose ratio_all_vs_daterange is <= this. nil = disabled.
MAX_RATIO_ALL_VS_DATERANGE = 10.0
# Max algos printed per family table (after sort/filter). 0 = print all.
PRINT_HOW_MANY_ALGOS_PER_FAM = 90

# Algos must have >=1 trade with startTime date in EVERY range (inclusive).
DATE_RANGES = [
  { start: '2026.03.08', end: '2026.03.29' },
  { start: '2025.03.12', end: '2025.04.27' }
].freeze

# Divide profitpercentsum and daterange_profitpercentsum by algo peak_open_exposure.
DIVIDE_BY_PEAKOPENEXPOSURE = true


# Table sort: :profitpercentsum, :daterange_profitpercentsum, :ratio_all_vs_daterange
SORT_BY = :ratio_all_vs_daterange
SORT_BY_OPTIONS = %i[profitpercentsum daterange_profitpercentsum ratio_all_vs_daterange].freeze

# :desc = highest first; :asc = lowest first.
# For ratio_all_vs_daterange: :asc puts daterange-heavy algos first (more % profit in the windows).
SORT_DIRECTION = :asc
SORT_DIRECTION_OPTIONS = %i[asc desc].freeze



FAMILIES = {
  breakdown: {
    file: 'summary_tradeResults_all_days_breakdown.tsv',
    default_enabled: CHECK_BREAKDOWN
  },
  time: {
    file: 'summary_tradeResults_all_days_time.tsv',
    default_enabled: CHECK_TIME
  },
  level: {
    file: 'summary_tradeResults_all_days_level.tsv',
    default_enabled: CHECK_LEVEL
  }
}.freeze

TIMEVSPROFIT_DECIMALS = AnalyzeAlgosPerformanceCommon::TIMEVSPROFIT_DECIMALS
RATIO_DECIMALS = 4

def resolve_sort_by(value)
  key = value.to_s.strip.to_sym
  raise ArgumentError, "invalid SORT_BY #{value.inspect}; use #{SORT_BY_OPTIONS.join(' or ')}" unless SORT_BY_OPTIONS.include?(key)

  key
end

def resolve_sort_direction(value)
  key = value.to_s.strip.downcase.to_sym
  unless SORT_DIRECTION_OPTIONS.include?(key)
    raise ArgumentError, "invalid SORT_DIRECTION #{value.inspect}; use #{SORT_DIRECTION_OPTIONS.join(' or ')}"
  end

  key
end

def parse_bool(value)
  case value.to_s.strip.downcase
  when 'true', '1', 'yes', 'y' then true
  when 'false', '0', 'no', 'n' then false
  else
    raise ArgumentError, "expected boolean, got #{value.inspect}"
  end
end

def family_enabled_flags_from_argv
  return nil if ARGV.length < 3

  %i[breakdown time level].map.with_index { |_key, index| parse_bool(ARGV[index]) }
end

def parse_trade_date(value)
  text = value.to_s.strip
  return nil if text.empty?

  Date.strptime(text, '%Y.%m.%d')
rescue ArgumentError
  nil
end

def parse_range_dates(range)
  start_date = parse_trade_date(range[:start] || range['start'])
  end_date = parse_trade_date(range[:end] || range['end'])
  raise ArgumentError, "invalid date range: #{range.inspect}" if start_date.nil? || end_date.nil?
  raise ArgumentError, "range start after end: #{range.inspect}" if start_date > end_date

  { start: start_date, end: end_date }
end

def format_percent(numerator, denominator)
  return 'n/a' if denominator.zero?

  format('%.1f%%', 100.0 * numerator / denominator)
end

def format_float(value, decimals = 2)
  return '' if value.nil?

  format("%.#{decimals}f", value)
end

def trade_start_date(trade)
  start_time = trade[:start_time]
  return nil unless start_time

  Date.new(start_time.year, start_time.month, start_time.day)
end

def trade_start_in_range?(trade, range)
  start_date = trade_start_date(trade)
  return false unless start_date

  start_date >= range[:start] && start_date <= range[:end]
end

def trade_start_in_any_range?(trade, ranges)
  ranges.any? { |range| trade_start_in_range?(trade, range) }
end

def algos_with_trade_start_in_range(trades, range)
  algos = Set.new
  trades.each do |trade|
    next unless trade_start_in_range?(trade, range)

    algo_id = trade[:algo_id].to_s.strip
    algos << algo_id unless algo_id.empty?
  end
  algos
end

def average_duration_hours(trades)
  durations =
    trades.filter_map do |trade|
      duration = trade[:duration_hours]
      next if duration.nil? || duration.negative?

      duration
    end
  return nil if durations.empty?

  durations.sum.to_f / durations.size
end

def profit_percent_sum(trades)
  trades.sum { |trade| trade[:percent_increase_w_roll].to_f }
end

def time_vs_profit_sum_for_trades(trades)
  AnalyzeAlgosPerformanceCommon.time_vs_profit_sum_from_components(
    profit_percent_sum(trades),
    average_duration_hours(trades)
  )
end

def ratio_all_vs_daterange(profitpercentsum, daterange_profitpercentsum)
  return nil if daterange_profitpercentsum.nil? || daterange_profitpercentsum <= 0

  profitpercentsum / daterange_profitpercentsum
end

def adjust_percent_sum_by_peak(percent_sum, peak_open_exposure, divide_by_peak)
  return percent_sum unless divide_by_peak
  return nil if peak_open_exposure.nil? || peak_open_exposure <= 0

  percent_sum / peak_open_exposure.to_f
end

def build_algo_stats(trades_by_algo, algo_id, ranges, divide_by_peak:)
  algo_trades = trades_by_algo[algo_id] || []
  range_trades = algo_trades.select { |trade| trade_start_in_any_range?(trade, ranges) }
  raw_profitpercentsum = profit_percent_sum(algo_trades)
  raw_daterange_profitpercentsum = profit_percent_sum(range_trades)
  peak_open_exposure = AnalyzeAlgosPerformanceCommon.peak_open_exposure(algo_trades)
  profitpercentsum =
    adjust_percent_sum_by_peak(raw_profitpercentsum, peak_open_exposure, divide_by_peak)
  daterange_profitpercentsum =
    adjust_percent_sum_by_peak(raw_daterange_profitpercentsum, peak_open_exposure, divide_by_peak)

  {
    profitpercentsum: profitpercentsum,
    profitpercentsum_raw: raw_profitpercentsum,
    timeVSprofitSum: time_vs_profit_sum_for_trades(algo_trades),
    daterange_profitpercentsum: daterange_profitpercentsum,
    daterange_profitpercentsum_raw: raw_daterange_profitpercentsum,
    peak_open_exposure: peak_open_exposure,
    ratio_all_vs_daterange: ratio_all_vs_daterange(profitpercentsum, daterange_profitpercentsum)
  }
end

def sort_value_for_algo(stats, sort_by, sort_direction)
  value = stats[sort_by]
  return Float::INFINITY if value.nil? && sort_direction == :asc
  return -Float::INFINITY if value.nil?

  value
end

def sort_algo_key(stats, sort_by, sort_direction, algo_id)
  value = sort_value_for_algo(stats, sort_by, sort_direction)
  signed_value = sort_direction == :asc ? value : -value
  [signed_value, algo_id.to_i]
end

def algo_passes_peak_exposure_filter?(stats, max_peak_exposure)
  return true if max_peak_exposure.nil?

  peak = stats[:peak_open_exposure]
  return false if peak.nil?

  peak <= max_peak_exposure
end

def algo_passes_ratio_all_vs_daterange_filter?(stats, max_ratio_all_vs_daterange)
  return true if max_ratio_all_vs_daterange.nil?

  ratio = stats[:ratio_all_vs_daterange]
  return false if ratio.nil?

  ratio <= max_ratio_all_vs_daterange
end

def analyze_family(family_name, path, ranges, min_profit_percent_sum, max_peak_exposure,
  max_ratio_all_vs_daterange, sort_by, sort_direction, divide_by_peak:)
  unless File.file?(path)
    warn "ERROR: missing #{family_name} file: #{path}"
    return nil
  end

  trades = AnalyzeAlgosPerformanceCommon.load_trades(path)
  trades_by_algo = trades.group_by { |trade| trade[:algo_id].to_s.strip }.reject { |algo_id, _| algo_id.empty? }
  all_algos = trades_by_algo.keys.sort_by(&:to_i)
  return nil if all_algos.empty?

  algos_per_range =
    ranges.map do |range|
      algos_with_trade_start_in_range(trades, range)
    end

  range_matching_algos =
    algos_per_range.reduce(all_algos.to_set) { |acc, range_algos| acc & range_algos }
      .to_a
      .sort_by(&:to_i)

  stats_by_algo =
    range_matching_algos.to_h do |algo_id|
      [algo_id, build_algo_stats(trades_by_algo, algo_id, ranges, divide_by_peak: divide_by_peak)]
    end

  profit_matching_algos =
    range_matching_algos.select do |algo_id|
      stats_by_algo[algo_id][:profitpercentsum_raw] >= min_profit_percent_sum
    end

  peak_matching_algos =
    profit_matching_algos.select do |algo_id|
      algo_passes_peak_exposure_filter?(stats_by_algo[algo_id], max_peak_exposure)
    end

  filtered_algos =
    peak_matching_algos.select do |algo_id|
      algo_passes_ratio_all_vs_daterange_filter?(stats_by_algo[algo_id], max_ratio_all_vs_daterange)
    end.sort_by do |algo_id|
      sort_algo_key(stats_by_algo[algo_id], sort_by, sort_direction, algo_id)
    end

  {
    family: family_name,
    path: path,
    total_algos: all_algos.size,
    range_matching_algos: range_matching_algos,
    range_matching_count: range_matching_algos.size,
    profit_matching_count: profit_matching_algos.size,
    peak_matching_count: peak_matching_algos.size,
    matching_algos: filtered_algos,
    matching_count: filtered_algos.size,
    algos_per_range: algos_per_range,
    stats_by_algo: stats_by_algo
  }
end

def print_range_header(ranges)
  puts 'date ranges (inclusive startTime date; algo must have a trade start in ALL):'
  ranges.each_with_index do |range, index|
    puts "  [#{index + 1}] #{range[:start].strftime('%Y.%m.%d')} .. #{range[:end].strftime('%Y.%m.%d')}"
  end
  puts
end

def print_family_report(result, sort_by, sort_direction, print_limit, min_profit_percent_sum,
  max_peak_exposure, max_ratio_all_vs_daterange, divide_by_peak:)
  puts "=== #{result[:family].upcase} ==="
  puts result[:path]
  puts "sorted by: #{sort_by} (#{sort_direction})"
  if divide_by_peak
    puts 'profitpercentsum and daterange_profitpercentsum divided by peak_open_exposure'
  end
  puts "family algos in file: #{result[:total_algos]}"
  result[:algos_per_range].each_with_index do |range_algos, index|
    puts "  range #{index + 1} algos with trade start in range: #{range_algos.size}"
  end
  puts "algos with trade start in every range: #{result[:range_matching_count]} " \
       "(#{format_percent(result[:range_matching_count], result[:total_algos])} of family)"
  puts "after min profitpercentsum (ALL) >= #{min_profit_percent_sum}: #{result[:profit_matching_count]} " \
       "(#{format_percent(result[:profit_matching_count], result[:total_algos])} of family)"
  if max_peak_exposure.nil?
    puts 'after peak_open_exposure filter: disabled'
  else
    puts "after peak_open_exposure <= #{max_peak_exposure}: #{result[:peak_matching_count]} " \
         "(#{format_percent(result[:peak_matching_count], result[:total_algos])} of family)"
  end
  if max_ratio_all_vs_daterange.nil?
    puts 'after ratio_all_vs_daterange filter: disabled'
  else
    puts "after ratio_all_vs_daterange <= #{max_ratio_all_vs_daterange}: #{result[:matching_count]} " \
         "(#{format_percent(result[:matching_count], result[:total_algos])} of family)"
  end
  puts

  if result[:matching_algos].empty?
    puts '  (none)'
    puts
    return
  end

  algos_to_print =
    if print_limit.nil? || print_limit <= 0
      result[:matching_algos]
    else
      result[:matching_algos].first(print_limit)
    end

  if print_limit.to_i.positive? && result[:matching_count] > print_limit
    puts "showing top #{print_limit} of #{result[:matching_count]} algos"
  end

  puts format(
    '%-10s %18s %16s %26s %22s',
    'algoID', 'profitpercentsum', 'timeVSprofitSum', 'daterange_profitpercentsum', 'ratio_all_vs_daterange'
  )
  algos_to_print.each do |algo_id|
    stats = result[:stats_by_algo][algo_id]
    puts format(
      '%-10s %18s %16s %26s %22s',
      algo_id,
      format_float(stats[:profitpercentsum], 2),
      format_float(stats[:timeVSprofitSum], TIMEVSPROFIT_DECIMALS),
      format_float(stats[:daterange_profitpercentsum], 2),
      format_float(stats[:ratio_all_vs_daterange], RATIO_DECIMALS)
    )
  end
  puts
end

argv_flags = family_enabled_flags_from_argv
enabled_by_family =
  if argv_flags
    %i[breakdown time level].zip(argv_flags).to_h
  else
    FAMILIES.transform_values { |cfg| cfg[:default_enabled] }
  end

unless enabled_by_family.values.any?
  warn 'ERROR: all family checks are disabled (breakdown/time/level).'
  exit 1
end

begin
  ranges = DATE_RANGES.map { |range| parse_range_dates(range) }
  sort_by = resolve_sort_by(SORT_BY)
  sort_direction = resolve_sort_direction(SORT_DIRECTION)
rescue ArgumentError => e
  warn "ERROR: #{e.message}"
  exit 1
end

if ranges.empty?
  warn 'ERROR: DATE_RANGES is empty.'
  exit 1
end

puts 'daterange_trade_check'
puts "directory: #{SCRIPT_DIR}"
puts "families: breakdown=#{enabled_by_family[:breakdown]} time=#{enabled_by_family[:time]} " \
     "level=#{enabled_by_family[:level]}"
puts "MIN_PROFIT_PERCENT_SUM (ALL-time): #{MIN_PROFIT_PERCENT_SUM}"
puts "MAX_PEAKEXPOSURE_LESSTHANOREQUAL: #{MAX_PEAKEXPOSURE_LESSTHANOREQUAL.nil? ? 'disabled' : MAX_PEAKEXPOSURE_LESSTHANOREQUAL}"
puts "MAX_RATIO_ALL_VS_DATERANGE: #{MAX_RATIO_ALL_VS_DATERANGE.nil? ? 'disabled' : MAX_RATIO_ALL_VS_DATERANGE}"
puts "SORT_BY: #{sort_by}"
puts "SORT_DIRECTION: #{sort_direction}"
puts "PRINT_HOW_MANY_ALGOS_PER_FAM: #{PRINT_HOW_MANY_ALGOS_PER_FAM}"
puts "DIVIDE_BY_PEAKOPENEXPOSURE: #{DIVIDE_BY_PEAKOPENEXPOSURE}"
puts
print_range_header(ranges)

results = []
FAMILIES.each do |family_name, cfg|
  next unless enabled_by_family[family_name]

  path = File.join(SCRIPT_DIR, cfg[:file])
  result = analyze_family(
    family_name, path, ranges, MIN_PROFIT_PERCENT_SUM, MAX_PEAKEXPOSURE_LESSTHANOREQUAL,
    MAX_RATIO_ALL_VS_DATERANGE, sort_by, sort_direction,
    divide_by_peak: DIVIDE_BY_PEAKOPENEXPOSURE
  )
  next if result.nil?

  results << result
  print_family_report(
    result, sort_by, sort_direction, PRINT_HOW_MANY_ALGOS_PER_FAM, MIN_PROFIT_PERCENT_SUM,
    MAX_PEAKEXPOSURE_LESSTHANOREQUAL, MAX_RATIO_ALL_VS_DATERANGE,
    divide_by_peak: DIVIDE_BY_PEAKOPENEXPOSURE
  )
end

if results.empty?
  warn 'ERROR: no family files analyzed.'
  exit 1
end

play_alert_done! if __FILE__ == $PROGRAM_NAME
