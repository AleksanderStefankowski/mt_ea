#!/usr/bin/env ruby
# frozen_string_literal: true

# Build/append per-family result catalogs: config + performance for input algos.
# Rows are keyed by config (not algo id). Append-only; skips configs already present.
#
# Outputs (separate schemas — time and breakdown config columns differ):
#   create_RESULTcatalogOUTPUT_time.csv      — within-catalog-id T1, T2, ... (+ placeholder_1/2 after pattern)
#   create_RESULTcatalogOUTPUT_breakdown.csv — within-catalog-id B1, B2, ...
# No mq5 algo id in either output file.
#
# Mode:
#   READ_ALL_ALGOS_FROM_PERFORMANCE_OUTPUT = false (default)
#     Use INPUT_ALGO_IDS heredoc. Routes each id to breakdown or time family by algo range.
#   READ_ALL_ALGOS_FROM_PERFORMANCE_OUTPUT = true
#     Catalog every algo listed in analyze_breakdown_algos_performance_output.csv and
#     analyze_time_algos_performance_output.csv.
#   Rows with non-numeric algoID (e.g. ALL/BREAKDOWN summary rows) are skipped.
#
# Per family:
#   breakdown -> aleksik2_r_read_breakdown_algos_csv.csv + analyze_breakdown_algos_performance_output*.csv
#   time      -> aleksik2_r_read_time_algos_csv.csv      + analyze_time_algos_performance_output*.csv
# Performance columns (incl. main_close_reason) are copied from the perf CSV into the catalog output.
#
# Also adds 2025flashcrash_percentSum_isWhat_percent_of_allpercentSum from each family's flashcrash perf file.

require 'csv'
require 'set'
require_relative 'compare_variable_analysis_lib'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
OUTPUT_PATHS = {
  breakdown: File.join(SCRIPT_DIR, 'create_RESULTcatalogOUTPUT_breakdown.csv'),
  time: File.join(SCRIPT_DIR, 'create_RESULTcatalogOUTPUT_time.csv')
}.freeze
WITHIN_CATALOG_ID_COLUMN = 'within-catalog-id'
EXTRA_COLUMN = '2025flashcrash_percentSum_isWhat_percent_of_allpercentSum'
TIME_CATALOG_PLACEHOLDER_COLUMNS = %w[placeholder_1 placeholder_2].freeze

READ_ALL_ALGOS_FROM_PERFORMANCE_OUTPUT = true

FAMILY_BREAKDOWN = :breakdown
FAMILY_TIME = :time

FAMILY_CATALOG_ID_PREFIX = {
  FAMILY_BREAKDOWN => 'B',
  FAMILY_TIME => 'T'
}.freeze

FAMILIES = {
  FAMILY_BREAKDOWN => {
    output_path: OUTPUT_PATHS[:breakdown],
    config_path: File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR),
    perf_path: File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_output.csv'),
    flashcrash_perf_path: File.join(
      SCRIPT_DIR,
      'analyze_breakdown_algos_performance_output_2025flashcrash.csv'
    ),
    except_flashcrash_perf_path: File.join(
      SCRIPT_DIR,
      'analyze_breakdown_algos_performance_output_except_2025flashcrash.csv'
    )
  },
  FAMILY_TIME => {
    output_path: OUTPUT_PATHS[:time],
    config_path: File.expand_path('../Aleksik2/aleksik2_r_read_time_algos_csv.csv', SCRIPT_DIR),
    perf_path: File.join(SCRIPT_DIR, 'analyze_time_algos_performance_output.csv'),
    flashcrash_perf_path: File.join(
      SCRIPT_DIR,
      'analyze_time_algos_performance_output_2025flashcrash.csv'
    ),
    except_flashcrash_perf_path: File.join(
      SCRIPT_DIR,
      'analyze_time_algos_performance_output_except_2025flashcrash.csv'
    )
  }
}.freeze

# Edit algo ids here when READ_ALL_ALGOS_FROM_PERFORMANCE_OUTPUT = false.
# Blank lines and # comments are ignored. Duplicates are removed.
INPUT_ALGO_IDS = <<~IDS
10000004
10000001

IDS

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

def family_for_algo_id(algo_id)
  id = Integer(algo_id)
  return FAMILY_TIME if id >= 10_000_000 && id < 20_000_000
  return FAMILY_BREAKDOWN if id >= 20_000_000

  raise "ERROR: cannot determine algo family for algo id #{algo_id} " \
        '(expected 10000000..19999999 time or 20000000+ breakdown)'
rescue ArgumentError
  raise "ERROR: invalid algo id #{algo_id.inspect} (expected digits only)"
end

def catalogable_algo_id?(algo_id)
  algo_id.to_s.strip.match?(/\A\d+\z/)
end

def algo_ids_from_performance_output(family)
  perf_path = FAMILIES[family][:perf_path]
  unless File.file?(perf_path)
    warn "WARNING: #{family} performance output not found: #{perf_path}"
    return []
  end

  Lib.read_csv(perf_path).filter_map do |row|
    algo_id = row['algoID'].to_s.strip
    next if algo_id.empty?
    next unless catalogable_algo_id?(algo_id)

    algo_id
  end.uniq.sort_by(&:to_i)
end

def resolve_input_algo_ids
  if READ_ALL_ALGOS_FROM_PERFORMANCE_OUTPUT
    FAMILIES.keys.flat_map { |family| algo_ids_from_performance_output(family) }.uniq.sort_by(&:to_i)
  else
    parse_input_algo_ids(INPUT_ALGO_IDS)
  end
end

def normalize_config_value(value)
  text = value.to_s.strip
  return '' if text.empty?

  downcased = text.downcase
  return 'true' if %w[true 1 yes].include?(downcased)
  return 'false' if %w[false 0 no].include?(downcased)

  float_match = text.match(/\A-?\d+(?:\.\d+)?\z/)
  return format('%.10g', Float(text)) if float_match

  text
end

def config_key_for_row(row, config_headers)
  config_headers.map { |header| normalize_config_value(row[header]) }.join("\x1f")
end

def index_rows_by_algo_id(rows, algo_column)
  rows.each_with_object({}) do |row, memo|
    algo_id = row[algo_column].to_s.strip
    next if algo_id.empty?

    memo[algo_id] = row
  end
end

def family_config_headers(config_table)
  config_table.headers.map(&:to_s) - ['algo_id']
end

def family_perf_headers(perf_table)
  perf_table.headers.map(&:to_s) - ['algoID']
end

def family_output_headers(family, config_headers, perf_headers)
  headers = [WITHIN_CATALOG_ID_COLUMN] + config_headers
  if family == FAMILY_TIME
    pattern_index = perf_headers.index('pattern')
    unless pattern_index
      warn 'ERROR: time performance output has no pattern column'
      exit 1
    end

    headers.concat(perf_headers[0..pattern_index])
    headers.concat(TIME_CATALOG_PLACEHOLDER_COLUMNS)
    headers.concat(perf_headers[(pattern_index + 1)..])
  else
    headers.concat(perf_headers)
  end
  headers << EXTRA_COLUMN
  headers
end

def flashcrash_percent_of_all(all_percent_sum, flashcrash_percent_sum)
  all_value = Lib.parse_float(all_percent_sum)
  flash_value = Lib.parse_float(flashcrash_percent_sum)
  return '' if all_value.nil? || flash_value.nil? || all_value.zero?

  Lib.format_float(100.0 * flash_value / all_value, 2)
end

def parse_catalog_id_number(catalog_id, prefix)
  text = catalog_id.to_s.strip
  match = text.match(/\A#{Regexp.escape(prefix)}(\d+)\z/i)
  return nil unless match

  match[1].to_i
end

def next_catalog_id_counter(existing_rows, prefix)
  max_num = 0
  existing_rows.each do |row|
    number = parse_catalog_id_number(row[WITHIN_CATALOG_ID_COLUMN], prefix)
    max_num = number if number && number > max_num
  end
  max_num
end

def build_output_row(within_catalog_id, config_row, perf_row, flashcrash_perf_row, output_headers, config_headers, perf_headers)
  row = { WITHIN_CATALOG_ID_COLUMN => within_catalog_id }
  config_headers.each { |header| row[header] = config_row[header].to_s }
  perf_headers.each { |header| row[header] = perf_row[header].to_s }
  output_headers.each do |header|
    row[header] = '' unless row.key?(header)
  end
  row[EXTRA_COLUMN] = flashcrash_percent_of_all(
    perf_row['percentSum_w_roll'],
    flashcrash_perf_row&.[]('percentSum_w_roll')
  )
  row
end

def load_required_csv(path, label)
  unless File.file?(path)
    warn "ERROR: #{label} not found: #{path}"
    exit 1
  end

  Lib.read_csv(path)
end

def load_optional_csv(path, label)
  return [] unless File.file?(path)

  Lib.read_csv(path)
rescue StandardError => e
  warn "WARNING: could not read #{label} (#{path}): #{e.message}"
  []
end

def load_family_data(family, paths)
  config_table = load_required_csv(paths[:config_path], "#{family} config")
  perf_table = load_required_csv(paths[:perf_path], "#{family} performance output")
  {
    family: family,
    config_table: config_table,
    perf_table: perf_table,
    config_by_algo_id: index_rows_by_algo_id(config_table, 'algo_id'),
    perf_by_algo_id: index_rows_by_algo_id(perf_table, 'algoID'),
    flashcrash_by_algo_id: index_rows_by_algo_id(
      load_optional_csv(paths[:flashcrash_perf_path], "#{family} flashcrash performance"),
      'algoID'
    ),
    except_by_algo_id: index_rows_by_algo_id(
      load_optional_csv(paths[:except_flashcrash_perf_path], "#{family} except-flashcrash performance"),
      'algoID'
    ),
    paths: paths
  }
end

def append_family_catalog(family, input_algo_ids, data)
  paths = data[:paths]
  output_path = paths[:output_path]
  prefix = FAMILY_CATALOG_ID_PREFIX.fetch(family)
  config_headers = family_config_headers(data[:config_table])
  perf_headers = family_perf_headers(data[:perf_table])
  output_headers = family_output_headers(family, config_headers, perf_headers)

  family_algo_ids = input_algo_ids.select { |algo_id| family_for_algo_id(algo_id) == family }
  existing_rows = File.file?(output_path) ? Lib.read_csv(output_path) : []
  if !existing_rows.empty? && !existing_rows.headers.include?(WITHIN_CATALOG_ID_COLUMN)
    warn "ERROR: #{output_path} exists but has no #{WITHIN_CATALOG_ID_COLUMN} column. " \
         'Remove the file or rebuild the catalog from scratch.'
    exit 1
  end
  if family == FAMILY_TIME && !existing_rows.empty?
    missing_placeholders = TIME_CATALOG_PLACEHOLDER_COLUMNS.reject do |column|
      existing_rows.headers.include?(column)
    end
    unless missing_placeholders.empty?
      warn "ERROR: #{output_path} is missing time placeholder column(s): #{missing_placeholders.join(', ')}. " \
           'Remove the file or rebuild the time catalog from scratch.'
      exit 1
    end
  end

  existing_config_keys = existing_rows.map { |row| config_key_for_row(row, config_headers) }.to_set
  catalog_id_counter = next_catalog_id_counter(existing_rows, prefix)

  missing_config = []
  missing_perf = []
  skipped_existing = []
  rows_to_append = []

  family_algo_ids.each do |algo_id|
    config_row = data[:config_by_algo_id][algo_id]
    if config_row.nil?
      missing_config << algo_id
      next
    end

    perf_row = data[:perf_by_algo_id][algo_id]
    if perf_row.nil?
      missing_perf << algo_id
      next
    end

    config_key = config_key_for_row(config_row, config_headers)
    if existing_config_keys.include?(config_key)
      skipped_existing << algo_id
      next
    end

    flashcrash_perf_row = data[:flashcrash_by_algo_id][algo_id]
    except_perf_row = data[:except_by_algo_id][algo_id]
    if flashcrash_perf_row.nil?
      warn "WARNING: algo #{algo_id}: no row in #{File.basename(paths[:flashcrash_perf_path])} " \
           "(#{EXTRA_COLUMN} will be blank)"
    end
    if except_perf_row.nil?
      warn "WARNING: algo #{algo_id}: no row in #{File.basename(paths[:except_flashcrash_perf_path])}"
    end

    catalog_id_counter += 1
    rows_to_append << build_output_row(
      "#{prefix}#{catalog_id_counter}",
      config_row,
      perf_row,
      flashcrash_perf_row,
      output_headers,
      config_headers,
      perf_headers
    )
    existing_config_keys << config_key
  end

  {
    family: family,
    output_path: output_path,
    output_headers: output_headers,
    input_count: family_algo_ids.size,
    missing_config: missing_config,
    missing_perf: missing_perf,
    skipped_existing: skipped_existing,
    rows_to_append: rows_to_append,
    existing_row_count: existing_rows.size,
    write_headers: existing_rows.empty?
  }
end

def write_family_catalog(result)
  return if result[:rows_to_append].empty?

  output_headers = result[:output_headers]
  CSV.open(result[:output_path], 'a', write_headers: result[:write_headers], headers: output_headers) do |csv|
    result[:rows_to_append].each do |row|
      csv << output_headers.map { |header| row[header].to_s }
    end
  end
end

# =========================================================
# MAIN
# =========================================================

CompareVariableAnalysisLib.refresh_breakdown_algos_performance_output!(SCRIPT_DIR)

input_algo_ids = resolve_input_algo_ids
if input_algo_ids.empty?
  if READ_ALL_ALGOS_FROM_PERFORMANCE_OUTPUT
    warn 'ERROR: no algo ids found in performance output files'
  else
    warn 'ERROR: INPUT_ALGO_IDS is empty (add algo ids to the heredoc at top of script)'
  end
  exit 1
end

families_needed = input_algo_ids.map { |algo_id| family_for_algo_id(algo_id) }.uniq
family_results =
  families_needed.map do |family|
    data = load_family_data(family, FAMILIES[family])
    append_family_catalog(family, input_algo_ids, data)
  end

family_results.each do |result|
  unless result[:missing_config].empty?
    warn "ERROR: #{result[:missing_config].size} #{result[:family]} algo(s) missing from config: " \
         "#{result[:missing_config].sort.join(', ')}"
    exit 1
  end

  unless result[:missing_perf].empty?
    warn "ERROR: #{result[:missing_perf].size} #{result[:family]} algo(s) missing from performance output: " \
         "#{result[:missing_perf].sort.join(', ')}"
    exit 1
  end
end

family_results.each { |result| write_family_catalog(result) }

if family_results.all? { |result| result[:rows_to_append].empty? }
  skipped_total = family_results.sum { |result| result[:skipped_existing].size }
  warn "No new rows to append (#{skipped_total} input algo(s) already cataloged by config)"
  exit 0
end

warn "mode: #{READ_ALL_ALGOS_FROM_PERFORMANCE_OUTPUT ? 'read_all_algos_from_performance_output' : 'input_algo_ids'}"
family_results.each do |result|
  paths = FAMILIES[result[:family]]
  warn "#{result[:family]} config: #{paths[:config_path]}"
  warn "#{result[:family]} performance: #{paths[:perf_path]}"
  warn "#{result[:family]} flashcrash performance: #{paths[:flashcrash_perf_path]}"
  warn "#{result[:family]} except-flashcrash performance: #{paths[:except_flashcrash_perf_path]}"
  warn "#{result[:family]} output: #{result[:output_path]}"
  warn "#{result[:family]} input algos: #{result[:input_count]}"
  warn "#{result[:family]} appended rows: #{result[:rows_to_append].size}"
  unless result[:skipped_existing].empty?
    warn "#{result[:family]} skipped (config already present): #{result[:skipped_existing].size}"
  end
  warn "#{result[:family]} total rows in catalog: #{result[:existing_row_count] + result[:rows_to_append].size}"
end
