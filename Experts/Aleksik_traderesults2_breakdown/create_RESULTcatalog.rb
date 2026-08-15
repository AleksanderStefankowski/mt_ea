#!/usr/bin/env ruby
# frozen_string_literal: true

# Build/append per-family result catalogs: config + performance for input algos.
# Rows are keyed by config (not algo id).
#
# If a config already exists with identical result columns, the input algo is skipped.
# If a config already exists but result columns differ, the catalog row is overwritten
# and the previous row is appended to create_RESULTcatalogOUTPUT_<family>_YYYY_YYYY_olddupes.csv.
#
# Outputs (separate schemas — config columns differ per family):
#   create_RESULTcatalogOUTPUT_time_YYYY_YYYY.csv      — within-catalog-id T1, T2, ... (+ placeholder_1/2 after pattern)
#   create_RESULTcatalogOUTPUT_breakdown_YYYY_YYYY.csv — within-catalog-id B1, B2, ...
#   create_RESULTcatalogOUTPUT_level_YYYY_YYYY.csv     — within-catalog-id L1, L2, ...
# YYYY_YYYY comes from earliest/latest firstTradeDate/lastTradeDate across all 3 perf input files.
# Legacy undated output files are not read or written.
#
# Mode:
#   READ_ALL_ALGOS_FROM_PERFORMANCE_OUTPUT = false (default)
#     Use INPUT_ALGO_IDS heredoc. Routes each id to breakdown, time, or level family by algo range.
#   READ_ALL_ALGOS_FROM_PERFORMANCE_OUTPUT = true
#     Catalog every algo listed in analyze_breakdown_algos_performance_output.csv,
#     analyze_time_algos_performance_output.csv, and analyze_level_algos_performance_output.csv.
#   Rows with non-numeric algoID (e.g. ALL/BREAKDOWN summary rows) are skipped.
#
# Per family:
#   breakdown -> aleksik2_r_read_breakdown_algos_csv.csv + analyze_breakdown_algos_performance_output*.csv
#   time      -> aleksik2_r_read_time_algos_csv.csv      + analyze_time_algos_performance_output*.csv
#   level     -> aleksik2_level_fam.mqh                   + analyze_level_algos_performance_output*.csv
# Performance columns (incl. main_close_reason) are copied from the perf CSV into the catalog output.
#
# Also adds 2025flashcrash_percentSum_isWhat_percent_of_allpercentSum from each family's flashcrash perf file.
#
# Level fam parsing (aleksik2_level_fam.mqh):
#   LEVEL_PARSE_ONLY_ENABLED_TRUE = true  — only blocks starting with ".enabled = true"
#   LEVEL_PARSE_ONLY_ENABLED_TRUE = false — all wired blocks (".enabled = true|false")

require 'csv'
require 'date'
require 'set'
require_relative 'compare_variable_analysis_lib'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
WITHIN_CATALOG_ID_COLUMN = 'within-catalog-id'
EXTRA_COLUMN = '2025flashcrash_percentSum_isWhat_percent_of_allpercentSum'
TIME_CATALOG_PLACEHOLDER_COLUMNS = %w[placeholder_1 placeholder_2].freeze
PERF_DATE_COLUMNS = %w[firstTradeDate lastTradeDate].freeze

READ_ALL_ALGOS_FROM_PERFORMANCE_OUTPUT = true
LEVEL_PARSE_ONLY_ENABLED_TRUE = false

FAMILY_BREAKDOWN = :breakdown
FAMILY_TIME = :time
FAMILY_LEVEL = :level

FAMILY_CATALOG_ID_PREFIX = {
  FAMILY_BREAKDOWN => 'B',
  FAMILY_TIME => 'T',
  FAMILY_LEVEL => 'L'
}.freeze

LEVEL_TRADES_TAGS_BY_PRESET = {
  'all_tags' => (1..5).map { |n| "Down#{n}" } + (1..5).map { |n| "Up#{n}" } + %w[Pivot],
  'all_down' => (1..5).map { |n| "Down#{n}" },
  'all_up' => (1..5).map { |n| "Up#{n}" },
  'all_down_pivot' => (1..5).map { |n| "Down#{n}" } + %w[Pivot]
}.freeze

LEVEL_CONFIG_HEADERS = %w[
  algo_id
  max_open_positions
  expiry_minutes
  trades_what_levels
  stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
  secret_tp_profit_percent_min
  level_needs_to_be_below_ONO
  offset_positive
  offset_percentage
  cannotTrade__when_levelProximity_multiplyOffset
  trades_tags_preset
].freeze

FAMILIES = {
  FAMILY_BREAKDOWN => {
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
  },
  FAMILY_LEVEL => {
    config_path: File.expand_path('../Aleksik2/aleksik2_level_fam.mqh', SCRIPT_DIR),
    perf_path: File.join(SCRIPT_DIR, 'analyze_level_algos_performance_output.csv'),
    flashcrash_perf_path: File.join(
      SCRIPT_DIR,
      'analyze_level_algos_performance_output_2025flashcrash.csv'
    ),
    except_flashcrash_perf_path: File.join(
      SCRIPT_DIR,
      'analyze_level_algos_performance_output_except_2025flashcrash.csv'
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

def parse_trade_date(value)
  text = value.to_s.strip
  match = text.match(/\A(\d{4})\.(\d{2})\.(\d{2})\z/)
  return nil unless match

  Date.new(match[1].to_i, match[2].to_i, match[3].to_i)
rescue ArgumentError
  nil
end

def date_range_suffix_from_perf_paths(perf_paths)
  earliest = nil
  latest = nil

  perf_paths.each do |path|
    unless File.file?(path)
      warn "ERROR: performance output not found: #{path}"
      exit 1
    end

    Lib.read_csv(path).each do |row|
      PERF_DATE_COLUMNS.each do |column|
        date = parse_trade_date(row[column])
        next unless date

        earliest = date if earliest.nil? || date < earliest
        latest = date if latest.nil? || date > latest
      end
    end
  end

  if earliest.nil? || latest.nil?
    warn 'ERROR: could not determine date range from performance output files'
    exit 1
  end

  {
    suffix: "_#{earliest.year}_#{latest.year}",
    earliest: earliest,
    latest: latest
  }
end

def family_paths(family, date_suffix)
  base_name = "create_RESULTcatalogOUTPUT_#{family}#{date_suffix}"
  FAMILIES.fetch(family).merge(
    output_path: File.join(SCRIPT_DIR, "#{base_name}.csv"),
    olddupes_output_path: File.join(SCRIPT_DIR, "#{base_name}_olddupes.csv")
  )
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

def family_for_algo_id(algo_id)
  id = Integer(algo_id)
  return FAMILY_TIME if id >= 10_000_000 && id < 20_000_000
  return FAMILY_BREAKDOWN if id >= 20_000_000 && id < 30_000_000
  return FAMILY_LEVEL if id >= 30_000_000 && id < 40_000_000

  raise "ERROR: cannot determine algo family for algo id #{algo_id} " \
        '(expected 10000000..19999999 time, 20000000..29999999 breakdown, or 30000000..39999999 level)'
rescue ArgumentError
  raise "ERROR: invalid algo id #{algo_id.inspect} (expected digits only)"
end

def parse_level_bool_token(value)
  value.to_s.strip.downcase == 'true'
end

def level_trades_what_levels_label(weekly, daily)
  return 'both' if weekly && daily
  return 'weekly' if weekly && !daily
  return 'daily' if !weekly && daily

  'none'
end

def level_trades_tags_preset_for(tags)
  preset = LEVEL_TRADES_TAGS_BY_PRESET.find { |_name, list| list == tags }
  return preset[0] if preset

  tags.empty? ? '(no tags)' : tags.join('+')
end

def level_enabled_parse_mode_label
  if LEVEL_PARSE_ONLY_ENABLED_TRUE
    'enabled = true only'
  else
    'enabled = true|false (all wired level algos)'
  end
end

def print_create_resultcatalog_finish(status = 'done')
  warn "level fam parse: #{level_enabled_parse_mode_label} (LEVEL_PARSE_ONLY_ENABLED_TRUE = #{LEVEL_PARSE_ONLY_ENABLED_TRUE})"
  warn "--- create_RESULTcatalog #{status} ---"
end

def level_enabled_line_regex
  if LEVEL_PARSE_ONLY_ENABLED_TRUE
    /LevelAlgoSlotIndexByAlgoId\(MAGIC_LEVEL(\d+)\)\]\.enabled = true/
  else
    /LevelAlgoSlotIndexByAlgoId\(MAGIC_LEVEL(\d+)\)\]\.enabled = (true|false)/
  end
end

def parse_level_catalog_configs(path)
  unless File.file?(path)
    warn "ERROR: level config not found: #{path}"
    exit 1
  end

  configs = {}
  current_id = nil

  File.foreach(path, encoding: 'bom|utf-8') do |line|
    if (match = line.match(level_enabled_line_regex))
      current_id = match[1]
      configs[current_id] = {
        'algo_id' => current_id,
        'max_open_positions' => nil,
        'expiry_minutes' => nil,
        'trades_what_levels' => nil,
        'stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count' => nil,
        'secret_tp_profit_percent_min' => nil,
        'level_needs_to_be_below_ONO' => nil,
        'offset_positive' => nil,
        'offset_percentage' => nil,
        'cannotTrade__when_levelProximity_multiplyOffset' => nil,
        'trades_tags_preset' => nil,
        weekly: false,
        daily: false,
        tags: []
      }
      next
    end
    next unless current_id
    next unless line.include?("MAGIC_LEVEL#{current_id}")

    config = configs[current_id]
    if (match = line.match(/trades_weekly = (true|false)/))
      config[:weekly] = parse_level_bool_token(match[1])
    elsif (match = line.match(/trades_daily = (true|false)/))
      config[:daily] = parse_level_bool_token(match[1])
    elsif (match = line.match(/max_open_positions = (\d+)/))
      config['max_open_positions'] = match[1]
    elsif (match = line.match(/expiry_minutes = (\d+)/))
      config['expiry_minutes'] = match[1]
    elsif (match = line.match(/stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = (\d+)/))
      config['stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count'] = match[1]
    elsif (match = line.match(/secret_tp_profit_percent_min = ([0-9.]+)/))
      config['secret_tp_profit_percent_min'] = match[1]
    elsif (match = line.match(/level_needs_to_be_below_ONO = (true|false)/))
      config['level_needs_to_be_below_ONO'] = match[1]
    elsif (match = line.match(/offset_positive = (true|false)/))
      config['offset_positive'] = match[1]
    elsif (match = line.match(/offset_percentage = ([0-9.]+)/))
      config['offset_percentage'] = match[1]
    elsif (match = line.match(/cannotTrade__when_levelProximity_multiplyOffset = ([0-9.]+)/))
      config['cannotTrade__when_levelProximity_multiplyOffset'] = match[1]
    elsif (match = line.match(/trades_tags\[\d+\] = "([^"]+)"/))
      config[:tags] << match[1]
    end
  end

  configs.each_value do |config|
    config['trades_what_levels'] = level_trades_what_levels_label(config[:weekly], config[:daily])
    config['trades_tags_preset'] = level_trades_tags_preset_for(config[:tags])
    config.delete(:weekly)
    config.delete(:daily)
    config.delete(:tags)
  end

  configs
end

def load_level_config_table(path)
  configs = parse_level_catalog_configs(path)
  rows = configs.values.sort_by { |config| config['algo_id'].to_i }.map do |config|
    CSV::Row.new(LEVEL_CONFIG_HEADERS, LEVEL_CONFIG_HEADERS.map { |header| config[header].to_s })
  end
  CSV::Table.new(rows)
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

def family_result_headers(output_headers, config_headers)
  output_headers - config_headers - [WITHIN_CATALOG_ID_COLUMN]
end

def catalog_row_signature(row, headers)
  headers.map { |header| normalize_config_value(row[header]) }.join("\x1f")
end

def same_catalog_results?(old_row, new_row, result_headers)
  catalog_row_signature(old_row, result_headers) == catalog_row_signature(new_row, result_headers)
end

def catalog_row_to_hash(row, headers)
  headers.to_h { |header| [header, row[header].to_s] }
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
  config_table =
    if family == FAMILY_LEVEL
      load_level_config_table(paths[:config_path])
    else
      load_required_csv(paths[:config_path], "#{family} config")
    end
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

  existing_by_config_key = existing_rows.each_with_object({}) do |row, memo|
    memo[config_key_for_row(row, config_headers)] = row
  end
  catalog_id_counter = next_catalog_id_counter(existing_rows, prefix)
  result_headers = family_result_headers(output_headers, config_headers)

  missing_config = []
  missing_perf = []
  skipped_unchanged = []
  rows_to_append = []
  rows_to_overwrite = []
  archived_rows = []

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
    existing_row = existing_by_config_key[config_key]
    flashcrash_perf_row = data[:flashcrash_by_algo_id][algo_id]
    except_perf_row = data[:except_by_algo_id][algo_id]
    if flashcrash_perf_row.nil?
      warn "WARNING: algo #{algo_id}: no row in #{File.basename(paths[:flashcrash_perf_path])} " \
           "(#{EXTRA_COLUMN} will be blank)"
    end
    if except_perf_row.nil?
      warn "WARNING: algo #{algo_id}: no row in #{File.basename(paths[:except_flashcrash_perf_path])}"
    end

    if existing_row
      within_catalog_id = existing_row[WITHIN_CATALOG_ID_COLUMN].to_s
      new_row = build_output_row(
        within_catalog_id,
        config_row,
        perf_row,
        flashcrash_perf_row,
        output_headers,
        config_headers,
        perf_headers
      )

      if same_catalog_results?(existing_row, new_row, result_headers)
        skipped_unchanged << algo_id
        next
      end

      archived_rows << catalog_row_to_hash(existing_row, output_headers)
      rows_to_overwrite << new_row
      existing_by_config_key[config_key] = new_row
      next
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
    existing_by_config_key[config_key] = rows_to_append.last
  end

  {
    family: family,
    paths: paths,
    output_path: output_path,
    olddupes_output_path: paths[:olddupes_output_path],
    output_headers: output_headers,
    input_count: family_algo_ids.size,
    missing_config: missing_config,
    missing_perf: missing_perf,
    skipped_unchanged: skipped_unchanged,
    rows_to_append: rows_to_append,
    rows_to_overwrite: rows_to_overwrite,
    archived_rows: archived_rows,
    existing_row_count: existing_rows.size
  }
end

def write_catalog_rows(path, headers, rows)
  CSV.open(path, 'w', write_headers: true, headers: headers) do |csv|
    rows.each do |row|
      csv << headers.map { |header| row[header].to_s }
    end
  end
end

def append_catalog_rows(path, headers, rows)
  return if rows.empty?

  write_headers = !File.file?(path)
  CSV.open(path, 'a', write_headers: write_headers, headers: headers) do |csv|
    rows.each do |row|
      csv << headers.map { |header| row[header].to_s }
    end
  end
end

def write_family_catalog(result)
  output_headers = result[:output_headers]
  has_changes = !result[:rows_to_append].empty? || !result[:rows_to_overwrite].empty?
  return unless has_changes || !result[:archived_rows].empty?

  if !result[:rows_to_overwrite].empty?
    existing_rows =
      if File.file?(result[:output_path])
        Lib.read_csv(result[:output_path]).map { |row| catalog_row_to_hash(row, output_headers) }
      else
        []
      end

    overwrite_by_id = result[:rows_to_overwrite].to_h { |row| [row[WITHIN_CATALOG_ID_COLUMN], row] }
    merged_rows = existing_rows.map { |row| overwrite_by_id.fetch(row[WITHIN_CATALOG_ID_COLUMN], row) }
    merged_rows.concat(result[:rows_to_append])
    write_catalog_rows(result[:output_path], output_headers, merged_rows)
  elsif !result[:rows_to_append].empty?
    append_catalog_rows(result[:output_path], output_headers, result[:rows_to_append])
  end

  return if result[:archived_rows].empty?

  append_catalog_rows(result[:olddupes_output_path], output_headers, result[:archived_rows])
end

# =========================================================
# MAIN
# =========================================================

warn '--- create_RESULTcatalog start ---'
warn "level fam parse: #{level_enabled_parse_mode_label} (LEVEL_PARSE_ONLY_ENABLED_TRUE = #{LEVEL_PARSE_ONLY_ENABLED_TRUE})"

CompareVariableAnalysisLib.refresh_breakdown_algos_performance_output!(SCRIPT_DIR)

date_range = date_range_suffix_from_perf_paths(FAMILIES.values.map { |paths| paths[:perf_path] })
date_suffix = date_range[:suffix]
warn "catalog date range: #{date_range[:earliest]} .. #{date_range[:latest]} (#{date_suffix})"

input_algo_ids = resolve_input_algo_ids
if input_algo_ids.empty?
  if READ_ALL_ALGOS_FROM_PERFORMANCE_OUTPUT
    warn 'ERROR: no algo ids found in performance output files'
  else
    warn 'ERROR: INPUT_ALGO_IDS is empty (add algo ids to the heredoc at top of script)'
  end
  print_create_resultcatalog_finish('failed')
  exit 1
end

families_needed = input_algo_ids.map { |algo_id| family_for_algo_id(algo_id) }.uniq
family_results =
  families_needed.map do |family|
    paths = family_paths(family, date_suffix)
    data = load_family_data(family, paths)
    append_family_catalog(family, input_algo_ids, data)
  end

family_errors = []
family_results.each do |result|
  unless result[:missing_config].empty?
    family_errors << "#{result[:missing_config].size} #{result[:family]} algo(s) missing from config: " \
                     "#{result[:missing_config].sort.join(', ')}"
    next
  end

  unless result[:missing_perf].empty?
    family_errors << "#{result[:missing_perf].size} #{result[:family]} algo(s) missing from performance output: " \
                     "#{result[:missing_perf].sort.join(', ')}"
    next
  end

  write_family_catalog(result)
end

if family_errors.any?
  family_errors.each { |message| warn "ERROR: #{message}" }
  print_create_resultcatalog_finish('failed')
  exit 1
end

if family_results.all? do |result|
     result[:rows_to_append].empty? && result[:rows_to_overwrite].empty?
   end
  skipped_total = family_results.sum { |result| result[:skipped_unchanged].size }
  warn "No catalog changes (#{skipped_total} input algo(s) already present with same results)"
  print_create_resultcatalog_finish('done')
  exit 0
end

warn "mode: #{READ_ALL_ALGOS_FROM_PERFORMANCE_OUTPUT ? 'read_all_algos_from_performance_output' : 'input_algo_ids'}"
family_results.each do |result|
  paths = result[:paths]
  warn "#{result[:family]} config: #{paths[:config_path]}"
  warn "#{result[:family]} performance: #{paths[:perf_path]}"
  warn "#{result[:family]} flashcrash performance: #{paths[:flashcrash_perf_path]}"
  warn "#{result[:family]} except-flashcrash performance: #{paths[:except_flashcrash_perf_path]}"
  warn "#{result[:family]} output: #{result[:output_path]}"
  warn "#{result[:family]} olddupes output: #{result[:olddupes_output_path]}"
  warn "#{result[:family]} input algos: #{result[:input_count]}"
  warn "#{result[:family]} appended rows: #{result[:rows_to_append].size}"
  warn "#{result[:family]} overwritten rows: #{result[:rows_to_overwrite].size}"
  unless result[:archived_rows].empty?
    warn "#{result[:family]} archived to olddupes: #{result[:archived_rows].size}"
  end
  unless result[:skipped_unchanged].empty?
    warn "#{result[:family]} skipped unchanged (config + results match): #{result[:skipped_unchanged].size}"
  end
  final_count = result[:existing_row_count] + result[:rows_to_append].size
  warn "#{result[:family]} total rows in catalog: #{final_count}"
end

print_create_resultcatalog_finish('done')
