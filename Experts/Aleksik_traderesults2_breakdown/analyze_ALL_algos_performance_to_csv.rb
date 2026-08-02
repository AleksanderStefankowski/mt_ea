#!/usr/bin/env ruby
# frozen_string_literal: true

# Run per-family performance scripts, then merge into one combined CSV:
#   analyze_ALL_algos_performance_output.csv
#   analyze_ALL_algos_performance_output_2025flashcrash.csv
#   analyze_ALL_algos_performance_output_except_2025flashcrash.csv

require 'csv'
require 'rbconfig'
require 'open3'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
OUTPUT_TIMESTAMP_PATH = File.join(SCRIPT_DIR, 'analyze_ALL_algos_performance_output.timestamp')

FAMILY_SCRIPTS = [
  {
    path: File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_to_csv.rb'),
    success_markers: %w[RAN OK]
  },
  {
    path: File.join(SCRIPT_DIR, 'analyze_time_algos_performance_to_csv.rb'),
    success_markers: %w[DONE RAN OK]
  },
  {
    path: File.join(SCRIPT_DIR, 'analyze_level_algos_performance_to_csv.rb'),
    success_markers: %w[RAN OK]
  }
].freeze

MERGE_SETS = [
  {
    family_outputs: %w[
      analyze_breakdown_algos_performance_output.csv
      analyze_time_algos_performance_output.csv
      analyze_level_algos_performance_output.csv
    ],
    merged_output: 'analyze_ALL_algos_performance_output.csv'
  },
  {
    family_outputs: %w[
      analyze_breakdown_algos_performance_output_2025flashcrash.csv
      analyze_time_algos_performance_output_2025flashcrash.csv
      analyze_level_algos_performance_output_2025flashcrash.csv
    ],
    merged_output: 'analyze_ALL_algos_performance_output_2025flashcrash.csv'
  },
  {
    family_outputs: %w[
      analyze_breakdown_algos_performance_output_except_2025flashcrash.csv
      analyze_time_algos_performance_output_except_2025flashcrash.csv
      analyze_level_algos_performance_output_except_2025flashcrash.csv
    ],
    merged_output: 'analyze_ALL_algos_performance_output_except_2025flashcrash.csv'
  }
].freeze

def run_family_script!(entry)
  path = entry[:path]
  unless File.file?(path)
    warn "ERROR: family script not found: #{path}"
    exit 1
  end

  warn
  warn "Running #{File.basename(path)}..."
  output, status = Open3.capture2e(RbConfig.ruby, path)
  warn output unless output.empty?

  success = status.success? && entry[:success_markers].any? { |marker| output.include?(marker) }
  unless success
    warn "ERROR: #{File.basename(path)} did not finish successfully " \
         "(expected one of: #{entry[:success_markers].join(', ')})"
    exit 1
  end
end

def read_csv_rows(path)
  raw = File.read(path, encoding: 'bom|utf-8')
  CSV.parse(raw, headers: true)
end

def merge_family_outputs!(family_outputs, merged_output)
  rows = []
  headers = nil
  used_paths = []

  family_outputs.each do |filename|
    path = File.join(SCRIPT_DIR, filename)
    next unless File.file?(path)

    table = read_csv_rows(path)
    next if table.empty?

    headers ||= table.headers
    used_paths << filename
    table.each { |row| rows << row.to_h }
  end

  if rows.empty?
    warn "Skipped #{merged_output}: no rows from #{family_outputs.join(', ')}"
    return
  end

  rows.sort_by! { |row| row['algoID'].to_i }

  merged_path = File.join(SCRIPT_DIR, merged_output)
  CSV.open(merged_path, 'w', write_headers: true, headers: headers) do |csv|
    rows.each do |row|
      csv << headers.map { |header| row[header] }
    end
  end

  warn "Wrote #{rows.size} algo rows to #{merged_path} " \
       "(merged from #{used_paths.join(', ')})"
end

if __FILE__ == $PROGRAM_NAME

FAMILY_SCRIPTS.each { |entry| run_family_script!(entry) }

warn
MERGE_SETS.each do |entry|
  merge_family_outputs!(entry[:family_outputs], entry[:merged_output])
end

File.write(OUTPUT_TIMESTAMP_PATH, Time.now.to_i.to_s)
warn
warn 'RAN OK'

end
