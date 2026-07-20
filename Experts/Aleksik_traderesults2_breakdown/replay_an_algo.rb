#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'date'

# ============ INPUT (edit these) ============
ALGO_ID = 20000086
ALGO_TYPE = :breakdown # :breakdown or :time
# ============================================

SOURCE_FILES = {
  breakdown: File.expand_path('summary_tradeResults_all_days_breakdown.tsv', __dir__),
  time: File.expand_path('summary_tradeResults_all_days_time.tsv', __dir__)
}.freeze

OUTPUT_PATH = File.expand_path('replay_an_algo_output.csv', __dir__)

def read_csv_table(path)
  raw = File.read(path, encoding: 'bom|utf-8')
  CSV.parse(raw, headers: true, col_sep: ',')
end

def parse_mt_datetime(value)
  text = value.to_s.strip
  return nil if text.empty?

  DateTime.strptime(text, '%Y.%m.%d %H:%M:%S')
rescue ArgumentError
  nil
end

def trade_sort_key(row)
  start_time = parse_mt_datetime(row['startTime'])
  sent_time = parse_mt_datetime(row['sentTime'])
  [
    start_time || sent_time || DateTime.new(1900, 1, 1),
    row['trade_customID'].to_i
  ]
end

unless SOURCE_FILES.key?(ALGO_TYPE)
  warn "ERROR: ALGO_TYPE must be :breakdown or :time (got #{ALGO_TYPE.inspect})"
  exit 1
end

source_path = SOURCE_FILES[ALGO_TYPE]
unless File.file?(source_path)
  warn "ERROR: source file not found: #{source_path}"
  exit 1
end

algo_id = ALGO_ID.to_s.strip
if algo_id.empty?
  warn 'ERROR: ALGO_ID is empty'
  exit 1
end

table = read_csv_table(source_path)
matching_rows =
  table
  .select { |row| row['algoID'].to_s.strip == algo_id }
  .sort_by { |row| trade_sort_key(row) }

if matching_rows.empty?
  warn "ERROR: no trades found for algoID=#{algo_id} in #{source_path}"
  exit 1
end

CSV.open(OUTPUT_PATH, 'w', write_headers: true, headers: table.headers) do |csv|
  matching_rows.each do |row|
    csv << table.headers.map { |header| row[header] }
  end
end

warn "algo_id=#{algo_id} algo_type=#{ALGO_TYPE}"
warn "source=#{source_path}"
warn "Wrote #{matching_rows.size} trades to #{OUTPUT_PATH}"
