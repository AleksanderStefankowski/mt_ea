#!/usr/bin/env ruby
# frozen_string_literal: true

# Read RESULT catalogs and aleksik2 algo configs; report which wired algos are cataloged.
# Match is by config fingerprint (same rules as create_RESULTcatalog.rb), not algo id.

CHECK_ONLY_ENABLED_ALGOS = true

require 'csv'
require 'open3'
require 'rbconfig'
require 'set'
require_relative 'compare_variable_analysis_lib'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
WITHIN_CATALOG_ID_COLUMN = 'within-catalog-id'

FAMILY_BREAKDOWN = :breakdown
FAMILY_TIME = :time
FAMILY_LEVEL = :level

FAMILIES = {
  FAMILY_BREAKDOWN => {
    catalog_path: File.join(SCRIPT_DIR, 'create_RESULTcatalogOUTPUT_breakdown.csv'),
    config_path: File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR),
    read_script: File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos.rb', SCRIPT_DIR)
  },
  FAMILY_TIME => {
    catalog_path: File.join(SCRIPT_DIR, 'create_RESULTcatalogOUTPUT_time.csv'),
    config_path: File.expand_path('../Aleksik2/aleksik2_r_read_time_algos_csv.csv', SCRIPT_DIR),
    read_script: File.expand_path('../Aleksik2/aleksik2_r_read_time_algos.rb', SCRIPT_DIR)
  },
  FAMILY_LEVEL => {
    catalog_path: File.join(SCRIPT_DIR, 'create_RESULTcatalogOUTPUT_level.csv'),
    config_path: File.expand_path('../Aleksik2/aleksik2_level_fam.mqh', SCRIPT_DIR),
    read_script: nil
  }
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

Lib = CompareVariableAnalysisLib

def enabled?(value)
  %w[true 1 yes].include?(value.to_s.strip.downcase)
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

def family_config_headers(config_table)
  config_table.headers.map(&:to_s) - %w[algo_id _enabled]
end

def refresh_aleksik2_config!(family, paths)
  script = paths[:read_script]
  return if script.nil? || !File.file?(script)

  output, status = Open3.capture2e(RbConfig.ruby, script)
  unless status.success?
    warn "ERROR: failed to refresh #{family} config via #{File.basename(script)}"
    warn output unless output.empty?
    exit 1
  end
end

def load_required_csv(path, label)
  unless File.file?(path)
    warn "ERROR: #{label} not found: #{path}"
    exit 1
  end

  Lib.read_csv(path)
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

def parse_level_alg_configs(path)
  unless File.file?(path)
    warn "ERROR: level config not found: #{path}"
    exit 1
  end

  configs = {}
  current_id = nil

  File.foreach(path, encoding: 'bom|utf-8') do |line|
    if (match = line.match(/LevelAlgoSlotIndexByAlgoId\(MAGIC_LEVEL(\d+)\)\]\.enabled = (true|false)/))
      current_id = match[1]
      configs[current_id] = {
        'algo_id' => current_id,
        '_enabled' => match[2],
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
  configs = parse_level_alg_configs(path)
  rows = configs.values.sort_by { |config| config['algo_id'].to_i }.map do |config|
    CSV::Row.new(LEVEL_CONFIG_HEADERS + ['_enabled'], (LEVEL_CONFIG_HEADERS + ['_enabled']).map do |header|
      config[header].to_s
    end)
  end
  CSV::Table.new(rows)
end

def load_config_table(family, config_path)
  if family == FAMILY_LEVEL
    load_level_config_table(config_path)
  else
    load_required_csv(config_path, "#{family} aleksik2 config")
  end
end

def catalog_index(catalog_rows, config_headers)
  catalog_rows.each_with_object(Hash.new { |h, k| h[k] = [] }) do |row, memo|
    key = config_key_for_row(row, config_headers)
    catalog_id = row[WITHIN_CATALOG_ID_COLUMN].to_s.strip
    memo[key] << catalog_id unless catalog_id.empty?
  end
end

def filter_config_rows(config_table)
  rows = config_table
  return rows unless CHECK_ONLY_ENABLED_ALGOS

  enabled_column = config_table.headers.map(&:to_s).include?('_enabled') ? '_enabled' : 'enabled'
  rows.select { |row| enabled?(row[enabled_column]) }
end

def check_family(family, paths)
  refresh_aleksik2_config!(family, paths)

  config_table = load_config_table(family, paths[:config_path])
  config_headers = family_config_headers(config_table)
  config_rows = filter_config_rows(config_table)

  catalog_rows = load_required_csv(paths[:catalog_path], "#{family} catalog")
  unless catalog_rows.empty? || catalog_rows.headers.include?(WITHIN_CATALOG_ID_COLUMN)
    warn "ERROR: #{paths[:catalog_path]} has no #{WITHIN_CATALOG_ID_COLUMN} column"
    exit 1
  end

  catalog_by_key = catalog_index(catalog_rows, config_headers)

  in_catalog = []
  missing = []

  config_rows.each do |row|
    algo_id = row['algo_id'].to_s.strip
    key = config_key_for_row(row, config_headers)
    catalog_ids = catalog_by_key[key]

    if catalog_ids && !catalog_ids.empty?
      in_catalog << { algo_id: algo_id, catalog_ids: catalog_ids.uniq }
    else
      missing << algo_id
    end
  end

  {
    family: family,
    catalog_path: paths[:catalog_path],
    config_path: paths[:config_path],
    checked: config_rows.size,
    in_catalog: in_catalog,
    missing: missing,
    catalog_row_count: catalog_rows.size
  }
end

def print_family_result(result)
  puts "=== #{result[:family]} ==="
  puts "aleksik2 config: #{result[:config_path]}"
  puts "catalog:         #{result[:catalog_path]} (#{result[:catalog_row_count]} rows)"
  puts "check only enabled algos: #{CHECK_ONLY_ENABLED_ALGOS}"
  puts "checked:         #{result[:checked]}"
  puts "in catalog:      #{result[:in_catalog].size}"
  puts "missing:         #{result[:missing].size}"

  unless result[:in_catalog].empty?
    puts "present:"
    result[:in_catalog].sort_by { |entry| entry[:algo_id].to_i }.each do |entry|
      puts "  #{entry[:algo_id]} -> #{entry[:catalog_ids].join(', ')}"
    end
  end

  unless result[:missing].empty?
    puts "missing from catalog:"
    result[:missing].sort_by(&:to_i).each do |algo_id|
      puts "  #{algo_id}"
    end
  end

  puts
end

family_results = FAMILIES.map { |family, paths| check_family(family, paths) }

family_results.each { |result| print_family_result(result) }

total_checked = family_results.sum { |result| result[:checked] }
total_in_catalog = family_results.sum { |result| result[:in_catalog].size }
total_missing = family_results.sum { |result| result[:missing].size }

puts '=== all ==='
puts "check only enabled algos: #{CHECK_ONLY_ENABLED_ALGOS}"
puts "checked:         #{total_checked}"
puts "in catalog:      #{total_in_catalog}"
puts "missing:         #{total_missing}"
puts 'by family:'
family_results.each do |result|
  puts "  #{result[:family]}: #{result[:checked]} checked, #{result[:in_catalog].size} in catalog, #{result[:missing].size} missing"
end
puts

if total_missing.positive?
  warn "ERROR: #{total_missing} aleksik2 algo(s) not found in catalog"
  exit 1
end

warn 'RAN OK'
