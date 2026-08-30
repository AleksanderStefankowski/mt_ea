#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'alert_done_common'

require 'csv'
require 'date'

# ============ INPUT (edit these) ============
ALGO_ID = 20000327 # examples: 10000001 time, 20000086 breakdown, 30000001 level
# ============================================

ALGO_ID_MIN = 10_000_000
ALGO_ID_MAX = 99_999_999

SOURCE_FILES = {
  breakdown: File.expand_path('summary_tradeResults_all_days_breakdown.tsv', __dir__),
  time: File.expand_path('summary_tradeResults_all_days_time.tsv', __dir__),
  level: File.expand_path('summary_tradeResults_all_days_level.tsv', __dir__)
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

# Leading digit of 8-digit algo id (aleksik2.mq5 FalgoAlgoFamilyLeadingDigit):
#   1 => time, 3 => level, 2/4/5/6/7/8/9 => breakdown
def algo_type_for_algo_id(algo_id)
  id = Integer(algo_id)
  unless id >= ALGO_ID_MIN && id <= ALGO_ID_MAX
    raise "algo id #{algo_id} out of range (#{ALGO_ID_MIN}..#{ALGO_ID_MAX})"
  end

  case id / 10_000_000
  when 1 then :time
  when 3 then :level
  when 2, 4, 5, 6, 7, 8, 9 then :breakdown
  else
    raise "cannot determine algo family for algo id #{algo_id} (invalid leading digit)"
  end
rescue ArgumentError
  raise "invalid algo id #{algo_id.inspect} (expected digits only)"
end

algo_id = ALGO_ID.to_s.strip
if algo_id.empty?
  warn 'ERROR: ALGO_ID is empty'
  exit 1
end

begin
  algo_type = algo_type_for_algo_id(algo_id)
rescue StandardError => e
  warn "ERROR: #{e.message}"
  exit 1
end

unless SOURCE_FILES.key?(algo_type)
  warn "ERROR: unknown algo type #{algo_type.inspect}"
  exit 1
end

source_path = SOURCE_FILES[algo_type]
unless File.file?(source_path)
  warn "ERROR: source file not found: #{source_path}"
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

warn "algo_id=#{algo_id} algo_type=#{algo_type}"
warn "source=#{source_path}"
warn "Wrote #{matching_rows.size} trades to #{OUTPUT_PATH}"

play_alert_done! if __FILE__ == $PROGRAM_NAME
