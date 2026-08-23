#!/usr/bin/env ruby
# frozen_string_literal: true

# Shared logic for quantexpected_vs_quantrun_alignmentCheck.rb and
# quantexpected_vs_quantrun_alignmentCheck-exactAlgoIDs.rb

require 'csv'
require_relative 'analyze_algos_performance_common'
require_relative '../Aleksik/smash_mql5_algo_reader_lib'

include AnalyzeAlgosPerformanceCommon

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
MQ5_FILE = File.expand_path('../Aleksik2/aleksik2.mq5', SCRIPT_DIR)
LEVEL_FAM_FILE = File.expand_path('../Aleksik2/aleksik2_level_fam.mqh', SCRIPT_DIR)

# Alignment summary band (inclusive): rows within this % range count as "good alignment".
ALIGNMENT_GOOD_MIN_PERCENT = 85
ALIGNMENT_GOOD_MAX_PERCENT = 115

# Ref-pattern reliability: a signature needs at least this many quant algos to report.
MIN_REF_PATTERN_SAMPLE_SIZE = 3
# Signature "reliable" if >= this % of its rows fall in the good alignment band.
RELIABLE_REF_PATTERN_MIN_IN_BAND_PERCENT = 60
# Signature "unreliable" if < this % of its rows fall in the good alignment band.
UNRELIABLE_REF_PATTERN_MAX_IN_BAND_PERCENT = 15

# Final copy-paste lists: pick this many per family (e.g. 5 x 3 families = 15 IDs per list).
PRINT_HOW_MANY_MOST_RELIABLE_PER_FAM = 5
PRINT_HOW_MANY_LEAST_RELIABLE_PER_FAM = 5

ALIGNMENT_COLUMNS = {
  'tVSp_align' => 'timeVSprofit alignment %',
  'percentSum_align' => 'percentSum alignment %',
  'tC_align' => 'tradesCount alignment %'
}.freeze

FAMILIES = {
  breakdown: {
    summary_tsv: 'summary_tradeResults_all_days_breakdown.tsv',
    breakdown_config_csv: '../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv',
    output_csv: 'quantexpected_vs_quantrun_alignmentCheck_breakdown.csv'
  },
  level: {
    summary_tsv: 'summary_tradeResults_all_days_level.tsv',
    output_csv: 'quantexpected_vs_quantrun_alignmentCheck_level.csv'
  },
  time: {
    summary_tsv: 'summary_tradeResults_all_days_time.tsv',
    output_csv: 'quantexpected_vs_quantrun_alignmentCheck_time.csv'
  }
}.freeze

QUANTREF_RE = /
  quantref\s+
  base=(\d+)\s+
  new=(\d+)\s+
  modes=(\S+)\s+
  above=(\S+)\s+
  below=(\S+)\s+
  ratecut=([\d.]+)\s+
  timeVSprofit=([\d.]+)\s+
  percentSum_w_roll=([\d.]+)\s+
  tradesCount=(\d+)
/x

OUTPUT_HEADERS = %w[
  quantAlgoID
  pattern
  firstTradeDate
  lastTradeDate
  refGroupSize
  grpRefsAbove
  grpRefsBelow
  tradedDaysCount
  avgDurationHours
  longestDurationHours
  longestDurationDays
  gross_profit
  avg_time_at_peak_exposure_hours
  max_time_at_peak_exposure_hours
  max_time_at_peak_exposure_days
  traderate
  weekly_traderate
  avg_open_exposure
  peak_open_exposure
  timeVSprofit
  tVSp_expected
  tVSp_align
  percentSum_w_roll
  percSum_expected
  percentSum_align
  tradesCount
  tC_expected
  tC_align
].freeze

def split_refs(value)
  text = value.to_s.strip
  return [] if text.empty? || text == '-'

  text.split(';').map(&:strip).reject(&:empty?)
end

def ref_group_size_from_refs(above_str, below_str)
  above = split_refs(above_str)
  below = split_refs(below_str)

  case [above.size, below.size]
  when [1, 0], [0, 1] then 1
  when [2, 0], [0, 2], [1, 1] then 2
  else above.size + below.size
  end
end

def format_grp_refs(value)
  refs = split_refs(value)
  refs.empty? ? '' : refs.join(';')
end

def detect_family(line)
  return :breakdown if line.include?('g_breakdownAlgos') || line.include?('MAGIC_BREAKDOWN')
  return :level if line.include?('g_levelAlgos') || line.include?('MAGIC_LEVEL')
  return :time if line.include?('g_timeAlgos') || line.include?('TIME_ALGO_')

  nil
end

def parse_quantref_entries(content, default_family: nil)
  entries = []

  content.lines.each do |line|
    next unless line.include?('quantref')
    # Params blocks use .enabled lines; skip duplicate quantref on matching rule-case lines.
    next unless line.include?('.enabled = true')

    match = line.match(QUANTREF_RE)
    next unless match

    family = detect_family(line) || default_family
    unless family
      warn "WARN: could not detect family for quantref line: #{line.strip}"
      next
    end

    base_algo_id, quant_algo_id, modes, above, below, ratecut,
      time_vs_profit, percent_sum, trades_count = match.captures

    entries << {
      family: family,
      base_algo_id: base_algo_id,
      quant_algo_id: quant_algo_id,
      modes: modes,
      grp_refs_above: above,
      grp_refs_below: below,
      ratecut: ratecut,
      time_vs_profit_expected: time_vs_profit,
      percent_sum_expected: percent_sum,
      trades_count_expected: trades_count,
      ref_group_size: ref_group_size_from_refs(above, below)
    }
  end

  entries
end

def pct_alignment(real_value, expected_value)
  real = parse_float(real_value)
  expected = parse_float(expected_value)
  return '' if real.nil? || expected.nil? || expected.zero?

  format_float((real / expected) * 100.0, 2)
end

def int_pct_alignment(real_value, expected_value)
  return '' if real_value.nil? || real_value.to_s.strip.empty?

  real = Integer(real_value)
  expected = Integer(expected_value)
  return '' if expected.zero?

  format_float((real.to_f / expected) * 100.0, 2)
end

def build_output_row(entry, perf_row)
  perf_row ||= {}

  row = {
    quantAlgoID: entry[:quant_algo_id],
    pattern: perf_row['pattern'],
    firstTradeDate: perf_row['firstTradeDate'],
    lastTradeDate: perf_row['lastTradeDate'],
    refGroupSize: entry[:ref_group_size],
    grpRefsAbove: format_grp_refs(entry[:grp_refs_above]),
    grpRefsBelow: format_grp_refs(entry[:grp_refs_below]),
    tradedDaysCount: perf_row['tradedDaysCount'],
    avgDurationHours: perf_row['avgDurationHours'],
    longestDurationHours: perf_row['longestDurationHours'],
    longestDurationDays: perf_row['longestDurationDays'],
    gross_profit: perf_row['gross_profit'],
    avg_time_at_peak_exposure_hours: perf_row['avg_time_at_peak_exposure_hours'],
    max_time_at_peak_exposure_hours: perf_row['max_time_at_peak_exposure_hours'],
    max_time_at_peak_exposure_days: perf_row['max_time_at_peak_exposure_days'],
    traderate: perf_row['traderate'],
    weekly_traderate: perf_row['weekly_traderate'],
    avg_open_exposure: perf_row['avg_open_exposure'],
    peak_open_exposure: perf_row['peak_open_exposure'],
    timeVSprofit: perf_row['timeVSprofit'],
    tVSp_expected: entry[:time_vs_profit_expected],
    tVSp_align: pct_alignment(perf_row['timeVSprofit'], entry[:time_vs_profit_expected]),
    percentSum_w_roll: perf_row['percentSum_w_roll'],
    percSum_expected: entry[:percent_sum_expected],
    percentSum_align: pct_alignment(perf_row['percentSum_w_roll'], entry[:percent_sum_expected]),
    tradesCount: perf_row['tradesCount'],
    tC_expected: entry[:trades_count_expected],
    tC_align: int_pct_alignment(perf_row['tradesCount'], entry[:trades_count_expected])
  }

  row.transform_keys(&:to_s).transform_values { |v| v.nil? ? '' : v.to_s }
end

def load_breakdown_pattern_by_algo_id(path)
  unless File.file?(path)
    warn "WARN: breakdown config not found: #{path}"
    return {}
  end

  raw = File.read(path, encoding: 'bom|utf-8')
  table = CSV.parse(raw, headers: true)
  table.each_with_object({}) do |row, out|
    algo_id = row['algo_id'].to_s.strip
    next if algo_id.empty?

    out[algo_id] = row['breakdown_streak_continuation_mode'].to_s.strip
  end
end

class FamilyRunStatsContext
  include AnalyzeAlgosPerformanceCommon

  attr_reader :computed_count, :missing_count

  def initialize(family, script_dir)
    @family = family
    @script_dir = script_dir
    @config = FAMILIES[family]
    @summary_path = File.join(script_dir, @config[:summary_tsv])
    @breakdown_patterns = nil
    @computed_count = 0
    @missing_count = 0
    load_summary_trades!
  end

  def perf_row_for(entry)
    trades = @trades_by_algo[entry[:quant_algo_id]]
    if trades.nil? || trades.empty?
      @missing_count += 1
      return nil
    end

    computed =
      build_performance_row(
        entry[:quant_algo_id],
        trades,
        pattern_for(entry),
        @global_first_date,
        @global_last_date,
        @global_trading_day_count,
        @global_full_week_mondays
      )
    @computed_count += 1
    computed.transform_keys(&:to_s).transform_values { |v| v.nil? ? '' : v.to_s }
  end

  private

  def load_summary_trades!
    unless File.file?(@summary_path)
      warn "WARN: summary TSV not found: #{@summary_path}"
      @trades_by_algo = {}
      @global_first_date = nil
      @global_last_date = nil
      @global_trading_day_count = 0
      @global_full_week_mondays = 0
      return
    end

    warn "Loading: #{@summary_path}"
    trades = load_trades(@summary_path)
    @global_first_date, @global_last_date, @global_trading_day_count = trade_date_range(trades)
    @global_full_week_mondays =
      countable_mon_fri_weeks_in_date_range(@global_first_date, @global_last_date)
    @trades_by_algo = trades.group_by { |trade| trade[:algo_id] }
  end

  def pattern_for(entry)
    case @family
    when :breakdown
      @breakdown_patterns ||= load_breakdown_pattern_by_algo_id(
        File.expand_path(@config[:breakdown_config_csv], @script_dir)
      )
      @breakdown_patterns[entry[:base_algo_id].to_s] || ''
    when :level
      'LEVEL'
    when :time
      'TIME'
    else
      ''
    end
  end
end

def alignment_column_stats(rows, column)
  values = rows.filter_map { |row| parse_float(row[column]) }
  return { count: 0, average: nil, in_band_count: 0, in_band_percent: nil } if values.empty?

  in_band_count =
    values.count do |value|
      value >= ALIGNMENT_GOOD_MIN_PERCENT && value <= ALIGNMENT_GOOD_MAX_PERCENT
    end

  {
    count: values.size,
    average: values.sum / values.size,
    in_band_count: in_band_count,
    in_band_percent: (in_band_count.to_f / values.size) * 100.0
  }
end

def row_in_align_band?(row, column)
  value = parse_float(row[column])
  return false if value.nil?

  value >= ALIGNMENT_GOOD_MIN_PERCENT && value <= ALIGNMENT_GOOD_MAX_PERCENT
end

def ref_signature_label(row)
  above = row['grpRefsAbove'].to_s.empty? ? '-' : row['grpRefsAbove']
  below = row['grpRefsBelow'].to_s.empty? ? '-' : row['grpRefsBelow']
  "size=#{row['refGroupSize']} above=#{above} below=#{below}"
end

def in_band_rate_percent(in_band_count, total_count)
  return nil if total_count.zero?

  (in_band_count.to_f / total_count) * 100.0
end

def grouped_ref_band_stats(rows, column, group_key_fn)
  groups = Hash.new { |h, k| h[k] = { total: 0, in_band: 0, align_sum: 0.0, align_count: 0 } }

  rows.each do |row|
    align = parse_float(row[column])
    next if align.nil?

    key = group_key_fn.call(row)
    groups[key][:total] += 1
    groups[key][:in_band] += 1 if row_in_align_band?(row, column)
    groups[key][:align_sum] += align
    groups[key][:align_count] += 1
  end

  groups.map do |label, stats|
    {
      label: label,
      total: stats[:total],
      in_band: stats[:in_band],
      in_band_rate: in_band_rate_percent(stats[:in_band], stats[:total]),
      avg_align: stats[:align_count].zero? ? nil : stats[:align_sum] / stats[:align_count]
    }
  end.sort_by { |entry| [-entry[:in_band_rate].to_f, -entry[:total]] }
end

def print_ref_count_distribution(title, counts, total)
  warn "    #{title}:"
  counts.sort_by { |_, count| -count }.each do |label, count|
    pct = total.zero? ? 0.0 : (count.to_f / total) * 100.0
    warn "      #{label}: #{count} (#{format_float(pct, 1)}%)"
  end
end

def print_in_band_ref_composition(rows, column, label)
  in_band_rows = rows.select { |row| row_in_align_band?(row, column) }
  return if in_band_rows.empty?

  warn "  In-band ref composition for #{label} (#{in_band_rows.size} rows):"

  size_counts = in_band_rows.group_by { |row| row['refGroupSize'] }
  print_ref_count_distribution(
    'refGroupSize',
    size_counts.transform_keys { |size| "size #{size}" }.transform_values(&:size),
    in_band_rows.size
  )

  above_counts = Hash.new(0)
  below_counts = Hash.new(0)
  in_band_rows.each do |row|
    above_refs = split_refs(row['grpRefsAbove'])
    below_refs = split_refs(row['grpRefsBelow'])
    if above_refs.empty?
      above_counts['(none)'] += 1
    else
      above_refs.each { |ref| above_counts[ref] += 1 }
    end
    if below_refs.empty?
      below_counts['(none)'] += 1
    else
      below_refs.each { |ref| below_counts[ref] += 1 }
    end
  end

  print_ref_count_distribution('grpRefsAbove appearances', above_counts, in_band_rows.size)
  print_ref_count_distribution('grpRefsBelow appearances', below_counts, in_band_rows.size)

  signature_counts = in_band_rows.group_by { |row| ref_signature_label(row) }.transform_values(&:size)
  print_ref_count_distribution('full ref signatures', signature_counts, in_band_rows.size)
end

def print_ref_signature_reliability(rows, column, label)
  stats =
    grouped_ref_band_stats(rows, column, ->(row) { ref_signature_label(row) })
      .select { |entry| entry[:total] >= MIN_REF_PATTERN_SAMPLE_SIZE }

  if stats.empty?
    warn "  Ref signature reliability for #{label}: no signatures with n>=#{MIN_REF_PATTERN_SAMPLE_SIZE}"
    return
  end

  reliable =
    stats.select { |entry| entry[:in_band_rate] >= RELIABLE_REF_PATTERN_MIN_IN_BAND_PERCENT }
  unreliable =
    stats
    .select { |entry| entry[:in_band_rate] <= UNRELIABLE_REF_PATTERN_MAX_IN_BAND_PERCENT }
    .sort_by { |entry| entry[:in_band_rate] }

  warn "  Ref signature reliability for #{label} (min n=#{MIN_REF_PATTERN_SAMPLE_SIZE}, " \
       "reliable>=#{RELIABLE_REF_PATTERN_MIN_IN_BAND_PERCENT}%, " \
       "unreliable<=#{UNRELIABLE_REF_PATTERN_MAX_IN_BAND_PERCENT}%):"

  if reliable.any?
    warn '    Reliable patterns:'
    reliable.first(10).each do |entry|
      warn "      #{entry[:label]}: #{entry[:in_band]}/#{entry[:total]} " \
           "(#{format_float(entry[:in_band_rate], 1)}%) " \
           "avg=#{format_float(entry[:avg_align], 1)}%"
    end
  else
    warn '    Reliable patterns: (none)'
  end

  if unreliable.any?
    warn '    Unreliable patterns:'
    unreliable.first(10).each do |entry|
      warn "      #{entry[:label]}: #{entry[:in_band]}/#{entry[:total]} " \
           "(#{format_float(entry[:in_band_rate], 1)}%) " \
           "avg=#{format_float(entry[:avg_align], 1)}%"
    end
  else
    warn '    Unreliable patterns: (none)'
  end
end

def print_ref_pattern_analysis(rows)
  warn
  warn '--- Ref pattern analysis (reliable vs unreliable alignment) ---'

  all_in_band =
    rows.select do |row|
      ALIGNMENT_COLUMNS.keys.all? { |column| row_in_align_band?(row, column) }
    end
  warn "Rows with ALL 3 metrics in band: #{all_in_band.size}/#{rows.size}"
  if all_in_band.any?
    signatures = all_in_band.group_by { |row| ref_signature_label(row) }.transform_values(&:size)
    print_ref_count_distribution('signatures (all 3 in band)', signatures, all_in_band.size)
  end

  ALIGNMENT_COLUMNS.each do |column, label|
    warn
    print_in_band_ref_composition(rows, column, label)
    print_ref_signature_reliability(rows, column, label)
  end
end

def print_alignment_summary_brief(family, rows, label_suffix: '')
  suffix = label_suffix.empty? ? '' : " #{label_suffix}"
  warn
  warn "--- #{family} summary#{suffix} (#{rows.size} rows) ---"
  warn "Good alignment band: #{ALIGNMENT_GOOD_MIN_PERCENT}%–#{ALIGNMENT_GOOD_MAX_PERCENT}% (inclusive)"

  ALIGNMENT_COLUMNS.each do |column, label|
    stats = alignment_column_stats(rows, column)
    avg_str = stats[:average].nil? ? 'n/a' : format_float(stats[:average], 2)
    pct_str =
      stats[:in_band_percent].nil? ? 'n/a' : format_float(stats[:in_band_percent], 2)
    warn "  #{label} (#{column}): avg=#{avg_str}% | " \
         "in band=#{stats[:in_band_count]}/#{stats[:count]} (#{pct_str}%)"
  end
end

def print_alignment_summary(family, output_path, rows)
  warn
  warn "\n--- #{family} summary: #{File.basename(output_path)} (#{rows.size} rows) ---"
  warn "Good alignment band: #{ALIGNMENT_GOOD_MIN_PERCENT}%–#{ALIGNMENT_GOOD_MAX_PERCENT}% (inclusive)"

  ALIGNMENT_COLUMNS.each do |column, label|
    stats = alignment_column_stats(rows, column)
    avg_str = stats[:average].nil? ? 'n/a' : format_float(stats[:average], 2)
    pct_str =
      stats[:in_band_percent].nil? ? 'n/a' : format_float(stats[:in_band_percent], 2)
    warn "  #{label} (#{column}): avg=#{avg_str}% | " \
         "in band=#{stats[:in_band_count]}/#{stats[:count]} (#{pct_str}%)"
  end

  print_ref_pattern_analysis(rows)
end

def scored_algo_rows(rows)
  rows.filter_map do |row|
    align_values = ALIGNMENT_COLUMNS.keys.filter_map { |col| parse_float(row[col]) }
    next if align_values.empty?

    in_band_count = ALIGNMENT_COLUMNS.keys.count { |col| row_in_align_band?(row, col) }
    avg_dev_from_100 = align_values.sum { |v| (v - 100).abs } / align_values.size
    {
      quant_algo_id: row['quantAlgoID'],
      in_band_count: in_band_count,
      avg_dev_from_100: avg_dev_from_100
    }
  end
end

def pick_scored_algo_ids(scored, count, most_reliable:)
  return [] if count <= 0 || scored.empty?

  sorted =
    if most_reliable
      scored.sort_by { |entry| [-entry[:in_band_count], entry[:avg_dev_from_100]] }
    else
      scored.sort_by { |entry| [entry[:in_band_count], entry[:avg_dev_from_100]] }
    end

  sorted.first(count).map { |entry| entry[:quant_algo_id] }
end

def print_reliability_algo_id_lists(family_rows)
  return if PRINT_HOW_MANY_MOST_RELIABLE_PER_FAM <= 0 && PRINT_HOW_MANY_LEAST_RELIABLE_PER_FAM <= 0

  most = []
  least = []

  FAMILIES.each_key do |family|
    scored = scored_algo_rows(family_rows[family] || [])
    next if scored.empty?

    fam_most =
      pick_scored_algo_ids(scored, PRINT_HOW_MANY_MOST_RELIABLE_PER_FAM, most_reliable: true)
    most.concat(fam_most)

    fam_least_pool = scored.reject { |entry| fam_most.include?(entry[:quant_algo_id]) }
    fam_least =
      pick_scored_algo_ids(fam_least_pool, PRINT_HOW_MANY_LEAST_RELIABLE_PER_FAM, most_reliable: false)
    least.concat(fam_least)
  end

  warn
  warn "--- Most reliable quant algo IDs (#{PRINT_HOW_MANY_MOST_RELIABLE_PER_FAM} per family, copy-paste) ---"
  most.each { |id| warn id }

  warn
  warn "--- Least reliable quant algo IDs (#{PRINT_HOW_MANY_LEAST_RELIABLE_PER_FAM} per family, copy-paste) ---"
  least.each { |id| warn id }
end

def write_family_output(family, entries, stats_context)
  config = FAMILIES[family]
  output_path = File.join(SCRIPT_DIR, config[:output_csv])
  rows = entries.sort_by { |entry| entry[:quant_algo_id].to_i }.map do |entry|
    perf_row = stats_context.perf_row_for(entry)
    build_output_row(entry, perf_row)
  end

  CSV.open(output_path, 'w', write_headers: true, headers: OUTPUT_HEADERS) do |csv|
    rows.each do |row|
      csv << OUTPUT_HEADERS.map { |header| row[header] }
    end
  end

  warn "Wrote #{rows.size} rows to #{output_path} " \
       "(#{stats_context.computed_count} from summary TSV, " \
       "#{stats_context.missing_count} with no trades)"
  print_alignment_summary(family, output_path, rows)
  rows
end

def load_quantref_entries
  mq5_content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  level_fam_content = File.exist?(LEVEL_FAM_FILE) ? File.read(LEVEL_FAM_FILE, encoding: 'bom|utf-8') : nil

  entries =
    parse_quantref_entries(mq5_content) +
    parse_quantref_entries(level_fam_content || '', default_family: :level)

  entries
    .group_by { |entry| entry[:quant_algo_id] }
    .values
    .map(&:first)
end

def build_family_rows(family, entries, stats_context)
  entries.sort_by { |entry| entry[:quant_algo_id].to_i }.map do |entry|
    perf_row = stats_context.perf_row_for(entry)
    build_output_row(entry, perf_row)
  end
end

def run_full_quant_alignment_check!
  entries = load_quantref_entries
  if entries.empty?
    warn 'No quantref entries found in mq5 / level_fam.'
    return
  end

  warn "Found #{entries.size} quantref definitions"

  family_rows = {}
  FAMILIES.each_key do |family|
    family_entries = entries.select { |entry| entry[:family] == family }
    stats_context = FamilyRunStatsContext.new(family, SCRIPT_DIR)
    family_rows[family] = write_family_output(family, family_entries, stats_context)
  end

  print_reliability_algo_id_lists(family_rows)
  warn 'DONE'
end

def run_exact_algo_ids_check!(exact_algo_ids)
  exact_set = exact_algo_ids.map(&:to_s).reject(&:empty?).uniq
  if exact_set.empty?
    warn 'No exact algo IDs provided.'
    return
  end

  entries = load_quantref_entries.select { |entry| exact_set.include?(entry[:quant_algo_id]) }
  found_ids = entries.map { |entry| entry[:quant_algo_id] }.uniq
  missing_ids = exact_set - found_ids

  warn "Exact algo ID check: #{exact_set.size} requested, #{found_ids.size} matched in quantref comments"
  unless missing_ids.empty?
    warn "WARN: exact algo IDs not found in quantref comments: #{missing_ids.join(', ')}"
  end

  if entries.empty?
    warn 'No matching quantref entries for exact algo IDs.'
    return
  end

  FAMILIES.each_key do |family|
    family_entries = entries.select { |entry| entry[:family] == family }
    next if family_entries.empty?

    stats_context = FamilyRunStatsContext.new(family, SCRIPT_DIR)
    rows = build_family_rows(family, family_entries, stats_context)
    print_alignment_summary_brief(family, rows, label_suffix: 'exact algo IDs')
  end

  warn 'DONE'
end
