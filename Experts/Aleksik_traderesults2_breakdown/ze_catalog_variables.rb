#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'date'
require_relative 'compare_variable_analysis_lib'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CATALOG_VARIABLE = 'after_bd_need_x_15greenc'

PAIRS_PATH = File.join(SCRIPT_DIR, "compare_variable_#{CATALOG_VARIABLE}_pairs.csv")
TIME_PERF_PATH = File.join(SCRIPT_DIR, 'analyze_time_algos_performance_output.csv')
BENCHMARK_PATH = File.join(SCRIPT_DIR, 'benchmark_buyAndHold.csv')
OUTPUT_PATH = File.join(SCRIPT_DIR, "ze_catalog_variable_#{CATALOG_VARIABLE}.csv")

BREAKDOWN_PATTERNS = %w[CLOSES OHLC_AVG LOW OC_MID HL_MID].freeze
ALL_BREAKDOWN_NAME = 'ALL_BREAKDOWN'

CATALOG_HEADERS = %w[
  record_type
  catalog_name
  tested_variable
  tested_argument
  perf_firstTradeDate
  perf_lastTradeDate
  perf_timeVSprofit
  perf_percentSum_w_roll
  perf_avgDurationHours
  perf_tradesCount
  sum_lifetime_days
].freeze

Lib = CompareVariableAnalysisLib

def blank_catalog_row
  CATALOG_HEADERS.to_h { |header| [header, ''] }
end

def fill_core_perf_metrics(row, perf)
  row['perf_timeVSprofit'] = Lib.format_float(perf[:timeVSprofit], 3)
  row['perf_percentSum_w_roll'] = Lib.format_float(perf[:percentSum_w_roll], 2)
  row['perf_avgDurationHours'] = Lib.format_float(perf[:avgDurationHours], 2)
  row['perf_tradesCount'] = Lib.format_float(perf[:tradesCount], 2)
  row
end

def breakdown_metrics_present?(metrics)
  metrics.values.any? { |value| !value.nil? }
end

def scoped_entries(pairs, catalog_name, tested_argument)
  scope_pairs =
    if catalog_name == ALL_BREAKDOWN_NAME
      pairs
    else
      Lib.pairs_for_pattern(pairs, catalog_name)
    end

  entries = Lib.paired_entries_from_pairs(scope_pairs)
  entries.select { |entry| entry[:config][CATALOG_VARIABLE].to_s == tested_argument.to_s }
end

def load_time_perf_row
  return nil unless File.file?(TIME_PERF_PATH)

  Lib.read_csv(TIME_PERF_PATH).find { |row| row['algoID'].to_s.strip != '' }
end

def load_benchmark_summary
  return nil unless File.file?(BENCHMARK_PATH)

  raw = File.read(BENCHMARK_PATH, encoding: 'bom|utf-8')
  table = CSV.parse(raw, headers: true, col_sep: "\t")
  first_day = table.find { |row| row['row'].to_s == 'first_day' }
  last_day = table.find { |row| row['row'].to_s == 'last_day' }
  diff = table.find { |row| row['row'].to_s == 'diff' }
  return nil unless first_day && last_day && diff

  {
    firstTradeDate: first_day['date'].to_s,
    lastTradeDate: last_day['date'].to_s,
    percentSum_w_roll: Lib.parse_float(diff['percentIncrease_firstOpen_lastClose_with_roll']),
    sum_lifetime_days: Lib.parse_float(diff['sum_lifetime_days'])
  }
end

def build_breakdown_catalog_row(catalog_name, tested_argument, pairs)
  entries = scoped_entries(pairs, catalog_name, tested_argument)
  return nil if entries.empty?

  metrics = Lib.metrics_for_entries(entries)
  return nil unless breakdown_metrics_present?(metrics)

  first_date, last_date = Lib.perf_date_span(entries)

  row = blank_catalog_row
  row['record_type'] = 'catalog'
  row['catalog_name'] = catalog_name
  row['tested_variable'] = CATALOG_VARIABLE
  row['tested_argument'] = tested_argument.to_s
  row['perf_firstTradeDate'] = Lib.format_date(first_date)
  row['perf_lastTradeDate'] = Lib.format_date(last_date)
  fill_core_perf_metrics(row, metrics)
  row
end

def build_time_catalog_row
  perf_row = load_time_perf_row
  row = blank_catalog_row
  row['record_type'] = 'catalog'
  row['catalog_name'] = 'TIME'

  if perf_row
    row['perf_firstTradeDate'] = perf_row['firstTradeDate'].to_s
    row['perf_lastTradeDate'] = perf_row['lastTradeDate'].to_s
    fill_core_perf_metrics(
      row,
      {
        timeVSprofit: Lib.parse_float(perf_row['timeVSprofit']),
        percentSum_w_roll: Lib.parse_float(perf_row['percentSum_w_roll']),
        avgDurationHours: Lib.parse_float(perf_row['avgDurationHours']),
        tradesCount: Lib.parse_float(perf_row['tradesCount'])
      }
    )
  end

  row
end

def build_benchmark_catalog_row
  summary = load_benchmark_summary
  row = blank_catalog_row
  row['record_type'] = 'catalog'
  row['catalog_name'] = 'buyAndHold'

  if summary
    row['perf_firstTradeDate'] = summary[:firstTradeDate]
    row['perf_lastTradeDate'] = summary[:lastTradeDate]
    row['perf_percentSum_w_roll'] = Lib.format_float(summary[:percentSum_w_roll], 2)
    row['sum_lifetime_days'] = Lib.format_float(summary[:sum_lifetime_days], 1)
  end

  row
end

# =========================================================
# MAIN
# =========================================================

unless File.file?(PAIRS_PATH)
  warn "ERROR: pairs file not found: #{PAIRS_PATH}"
  warn 'Run compare_variable.rb first.'
  exit 1
end

pairs, tested_arguments = Lib.load_pairs_from_compare_csv(PAIRS_PATH, CATALOG_VARIABLE)
if tested_arguments.empty?
  warn "ERROR: no tested arguments found in #{PAIRS_PATH}"
  exit 1
end

rows = [build_time_catalog_row, build_benchmark_catalog_row]

BREAKDOWN_PATTERNS.each do |pattern|
  tested_arguments.each do |tested_argument|
    row = build_breakdown_catalog_row(pattern, tested_argument, pairs)
    rows << row if row
  end
end

tested_arguments.each do |tested_argument|
  row = build_breakdown_catalog_row(ALL_BREAKDOWN_NAME, tested_argument, pairs)
  rows << row if row
end

CSV.open(OUTPUT_PATH, 'w', write_headers: true, headers: CATALOG_HEADERS) do |csv|
  rows.each do |row|
    csv << CATALOG_HEADERS.map { |header| row[header] }
  end
end

warn "Catalog variable: #{CATALOG_VARIABLE}"
warn "Tested arguments: #{tested_arguments.join(', ')}"
warn "Pairs loaded: #{pairs.size}"
warn "Wrote #{rows.size} catalog rows to #{OUTPUT_PATH}"
