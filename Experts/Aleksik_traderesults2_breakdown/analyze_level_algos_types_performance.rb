#!/usr/bin/env ruby
# frozen_string_literal: true

# Group level algo performance by config dimensions. Console output only.
#
# Sections:
#   - trades_tags preset (all_tags, all_up, all_down, all_down_pivot)
#   - offset_positive + offset_percentage (paired)
#   - level scope (weekly, daily, both)
#   - secret_tp_profit_percent_min
#   - level_needs_to_be_below_ONO
#   - cannotTrade__when_levelProximity_multiplyOffset
#   - stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
#
# Uses analyze_level_algos_performance_output.csv + config parsed from aleksik2_level_fam.mqh.

require_relative 'compare_variable_analysis_lib'
require_relative '../Aleksik_traderesults/analyze_traderate_common'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
LEVEL_FAM_PATH = File.expand_path('../Aleksik2/aleksik2_level_fam.mqh', SCRIPT_DIR)
PERF_PATH = File.join(SCRIPT_DIR, 'analyze_level_algos_performance_output.csv')

Lib = CompareVariableAnalysisLib

TRADES_TAGS_BY_PRESET = {
  'all_tags' => (1..5).map { |n| "Down#{n}" } + (1..5).map { |n| "Up#{n}" } + %w[Pivot],
  'all_down' => (1..5).map { |n| "Down#{n}" },
  'all_up' => (1..5).map { |n| "Up#{n}" },
  'all_down_pivot' => (1..5).map { |n| "Down#{n}" } + %w[Pivot]
}.freeze

GROUP_SECTIONS = [
  { field: :trades_tags_preset, title: 'TRADES_TAGS PRESET' },
  { field: :offset_pair, title: 'OFFSET_POSITIVE + OFFSET_PERCENTAGE' },
  { field: :level_scope, title: 'LEVEL SCOPE (weekly / daily / both)' },
  { field: :secret_tp_profit_percent_min, title: 'SECRET_TP_PROFIT_PERCENT_MIN' },
  { field: :level_needs_to_be_below_ONO, title: 'LEVEL_NEEDS_TO_BE_BELOW_ONO' },
  { field: :cannotTrade__when_levelProximity_multiplyOffset,
    title: 'CANNOT_TRADE__WHEN_LEVELPROXIMITY_MULTIPLYOFFSET' },
  { field: :stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count,
    title: 'STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT' }
].freeze

TABLE_COLUMNS = [
  [:group, 22],
  [:algos, 6],
  [:trades, 8],
  [:avg_trades, 10],
  [:percent_sum, 12],
  [:avg_percent, 10],
  [:avgOpen, 10],
  [:gross_profit, 12],
  [:gross_loss, 10],
  [:profit_factor, 8],
  [:avg_traderate, 12],
  [:avg_weekly_tr, 12],
  [:avglongestDurationDays, 12],
  [:avgavgDurationHours, 12],
  [:avgtimeVSprofit, 10],
  [:avgavg_time_at_peak_exposure_hours, 14]
].freeze

TABLE_COLUMNS_PART1 = TABLE_COLUMNS[0..6].freeze
TABLE_COLUMNS_PART2 = [TABLE_COLUMNS[0]] + TABLE_COLUMNS[7..11].freeze
TABLE_COLUMNS_PART3 = [TABLE_COLUMNS[0]] + TABLE_COLUMNS[12..].freeze

def catalogable_algo_id?(algo_id)
  algo_id.to_s.strip.match?(/\A\d+\z/)
end

def parse_bool_token(value)
  value.to_s.strip.downcase == 'true'
end

def parse_level_alg_configs(path)
  unless File.file?(path)
    warn "ERROR: level fam file not found: #{path}"
    exit 1
  end

  configs = {}
  current_id = nil

  File.foreach(path, encoding: 'bom|utf-8') do |line|
    if (match = line.match(/LevelAlgoSlotIndexByAlgoId\(MAGIC_LEVEL(\d+)\)\]\.enabled = true/))
      current_id = match[1]
      configs[current_id] = {
        algo_id: current_id,
        weekly: false,
        daily: false,
        offset_positive: nil,
        offset_percentage: nil,
        secret_tp_profit_percent_min: nil,
        level_needs_to_be_below_ONO: nil,
        cannotTrade__when_levelProximity_multiplyOffset: nil,
        stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count: nil,
        tags: []
      }
      next
    end
    next unless current_id
    next unless line.include?("MAGIC_LEVEL#{current_id}")

    config = configs[current_id]
    if (match = line.match(/trades_weekly = (true|false)/))
      config[:weekly] = parse_bool_token(match[1])
    elsif (match = line.match(/trades_daily = (true|false)/))
      config[:daily] = parse_bool_token(match[1])
    elsif (match = line.match(/offset_positive = (true|false)/))
      config[:offset_positive] = parse_bool_token(match[1])
    elsif (match = line.match(/offset_percentage = ([0-9.]+)/))
      config[:offset_percentage] = match[1]
    elsif (match = line.match(/secret_tp_profit_percent_min = ([0-9.]+)/))
      config[:secret_tp_profit_percent_min] = match[1]
    elsif (match = line.match(/level_needs_to_be_below_ONO = (true|false)/))
      config[:level_needs_to_be_below_ONO] = parse_bool_token(match[1])
    elsif (match = line.match(/cannotTrade__when_levelProximity_multiplyOffset = ([0-9.]+)/))
      config[:cannotTrade__when_levelProximity_multiplyOffset] = match[1]
    elsif (match = line.match(/stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = (\d+)/))
      config[:stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count] = match[1]
    elsif (match = line.match(/trades_tags\[\d+\] = "([^"]+)"/))
      config[:tags] << match[1]
    end
  end

  configs.each_value do |config|
    config[:trades_tags_preset] = trades_tags_preset_for(config[:tags])
    config[:level_scope] = level_scope_label(config[:weekly], config[:daily])
    config[:offset_positive_label] = config[:offset_positive].nil? ? 'n/a' : config[:offset_positive].to_s
    config[:offset_pair] = offset_pair_label(config[:offset_positive], config[:offset_percentage])
    config[:level_needs_to_be_below_ONO_label] =
      config[:level_needs_to_be_below_ONO].nil? ? 'n/a' : config[:level_needs_to_be_below_ONO].to_s
  end

  configs
end

def trades_tags_preset_for(tags)
  preset = TRADES_TAGS_BY_PRESET.find { |_name, list| list == tags }
  return preset[0] if preset

  tags.empty? ? '(no tags)' : tags.join('+')
end

def level_scope_label(weekly, daily)
  return 'both' if weekly && daily
  return 'weekly' if weekly && !daily
  return 'daily' if !weekly && daily

  'none'
end

def offset_pair_label(offset_positive, offset_percentage)
  positive = offset_positive.nil? ? 'n/a' : offset_positive.to_s
  percentage = offset_percentage.nil? ? 'n/a' : offset_percentage.to_s
  "#{positive}, #{percentage}"
end

def load_matched_rows
  config_by_algo_id = parse_level_alg_configs(LEVEL_FAM_PATH)

  unless File.file?(PERF_PATH)
    warn "ERROR: performance file not found: #{PERF_PATH}"
    exit 1
  end

  perf_rows = Lib.read_csv(PERF_PATH).select do |row|
    catalogable_algo_id?(row['algoID'])
  end

  matched_rows = []
  missing_config = []

  perf_rows.each do |perf_row|
    algo_id = perf_row['algoID'].to_s.strip
    config = config_by_algo_id[algo_id]
    if config.nil?
      missing_config << algo_id
      next
    end

    matched_rows << { algo_id: algo_id, config: config, perf: perf_row }
  end

  unless missing_config.empty?
    warn "WARNING: #{missing_config.size} performance algos missing from level fam config: " \
         "#{missing_config.sort_by(&:to_i).join(', ')}"
  end

  [matched_rows, perf_rows.size]
end

def group_profit_factor(entries)
  gross_profit = entries.sum { |entry| Lib.parse_float(entry[:perf]['gross_profit']).to_f }
  gross_loss = entries.sum { |entry| Lib.parse_float(entry[:perf]['gross_loss']).to_f }
  profit_factor_from_gross(gross_profit, gross_loss)
end

def format_profit_factor_value(value)
  return 'n/a' if value.nil?
  return '999.00' if value >= 999.0

  format('%.2f', value)
end

def aggregate_group(group_key, entries)
  trades = entries.sum { |entry| entry[:perf]['tradesCount'].to_i }
  percent_values = entries.map { |entry| Lib.parse_float(entry[:perf]['percentSum_w_roll']) }
  traderate_values = entries.map { |entry| Lib.parse_float(entry[:perf]['traderate']) }
  weekly_values = entries.map { |entry| Lib.parse_float(entry[:perf]['weekly_traderate']) }
  longest_duration_days_values = entries.map { |entry| Lib.parse_float(entry[:perf]['longestDurationDays']) }
  avg_duration_hours_values = entries.map { |entry| Lib.parse_float(entry[:perf]['avgDurationHours']) }
  time_vs_profit_values = entries.map { |entry| Lib.parse_float(entry[:perf]['timeVSprofit']) }
  avg_peak_exposure_hours_values =
    entries.map { |entry| Lib.parse_float(entry[:perf]['avg_time_at_peak_exposure_hours']) }
  avg_open_exposure_values = entries.map { |entry| Lib.parse_float(entry[:perf]['avg_open_exposure']) }
  gross_profit = entries.sum { |entry| Lib.parse_float(entry[:perf]['gross_profit']).to_f }
  gross_loss = entries.sum { |entry| Lib.parse_float(entry[:perf]['gross_loss']).to_f }
  algo_count = entries.size

  {
    group: group_key,
    algos: algo_count,
    trades: trades,
    avg_trades: algo_count.zero? ? nil : trades.to_f / algo_count,
    percent_sum: percent_values.compact.sum,
    avg_percent: Lib.average(percent_values),
    avgOpen: Lib.average(avg_open_exposure_values),
    gross_profit: gross_profit,
    gross_loss: gross_loss,
    profit_factor: group_profit_factor(entries),
    avg_traderate: Lib.average(traderate_values),
    avg_weekly_tr: Lib.average(weekly_values),
    avglongestDurationDays: Lib.average(longest_duration_days_values),
    avgavgDurationHours: Lib.average(avg_duration_hours_values),
    avgtimeVSprofit: Lib.average(time_vs_profit_values),
    avgavg_time_at_peak_exposure_hours: Lib.average(avg_peak_exposure_hours_values)
  }
end

def group_rows(matched_rows, field)
  grouped = matched_rows.group_by do |entry|
    case field
    when :offset_pair
      entry[:config][:offset_pair]
    when :level_needs_to_be_below_ONO
      entry[:config][:level_needs_to_be_below_ONO_label]
    when :secret_tp_profit_percent_min
      entry[:config][:secret_tp_profit_percent_min].to_s
    when :cannotTrade__when_levelProximity_multiplyOffset
      entry[:config][:cannotTrade__when_levelProximity_multiplyOffset].to_s
    else
      entry[:config][field].to_s
    end
  end

  grouped
    .map { |group_key, entries| aggregate_group(group_key, entries) }
    .sort_by { |row| group_sort_key(field, row[:group], row) }
end

def group_sort_key(field, group_key, row)
  case field
  when :level_scope
    { 'both' => 0, 'weekly' => 1, 'daily' => 2, 'none' => 3 }.fetch(group_key.to_s, 99)
  when :offset_pair
    positive, percentage = group_key.to_s.split(', ', 2)
    positive_rank = { 'true' => 0, 'false' => 1, 'n/a' => 2 }.fetch(positive, 99)
    [positive_rank, Lib.parse_float(percentage) || 99.0, group_key.to_s]
  when :level_needs_to_be_below_ONO
    { 'true' => 0, 'false' => 1, 'n/a' => 2 }.fetch(group_key.to_s, 99)
  when :secret_tp_profit_percent_min,
       :cannotTrade__when_levelProximity_multiplyOffset,
       :stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
    [Lib.parse_float(group_key) || 99.0, group_key.to_s]
  when :trades_tags_preset
  [
    { 'all_tags' => 0, 'all_down' => 1, 'all_up' => 2, 'all_down_pivot' => 3 }.fetch(group_key.to_s, 99),
    group_key.to_s
  ]
  else
    [-row[:percent_sum].to_f, group_key.to_s]
  end
end

def format_table_cell(value, width, numeric: false, decimals: 2)
  text =
    if value.nil?
      'n/a'
    elsif numeric && value.is_a?(Numeric)
      if decimals == 3
        format('%.3f', value)
      elsif value == value.to_i
        value.to_i.to_s
      else
        format("%.#{decimals}f", value)
      end
    else
      value.to_s
    end

  text.ljust(width)[0, width]
end

def print_group_table_with_columns(rows, columns)
  header = columns.map { |name, width| name.to_s.ljust(width) }.join(' ')
  puts header
  puts '-' * header.length

  rows.each do |row|
    line = columns.map do |name, width|
      case name
      when :profit_factor
        format_table_cell(format_profit_factor_value(row[:profit_factor]), width)
      when :algos, :trades
        format_table_cell(row[name], width, numeric: true)
      when :avgtimeVSprofit
        format_table_cell(row[name], width, numeric: true, decimals: 3)
      when :avg_trades, :percent_sum, :avg_percent, :avgOpen, :gross_profit, :gross_loss, :avg_traderate, :avg_weekly_tr,
           :avglongestDurationDays, :avgavgDurationHours, :avgavg_time_at_peak_exposure_hours
        format_table_cell(row[name], width, numeric: true)
      else
        format_table_cell(row[name], width)
      end
    end.join(' ')
    puts line
  end
end

def print_group_table(rows)
  print_group_table_with_columns(rows, TABLE_COLUMNS_PART1)
  puts
  print_group_table_with_columns(rows, TABLE_COLUMNS_PART2)
  puts
  print_group_table_with_columns(rows, TABLE_COLUMNS_PART3)
end

def print_section(section, matched_rows)
  puts '=' * 72
  puts section[:title]
  puts '=' * 72

  rows = group_rows(matched_rows, section[:field])
  if rows.empty?
    puts '(no rows)'
    puts
    return
  end

  total_algos = rows.sum { |row| row[:algos] }
  puts "groups: #{rows.size}   algos: #{total_algos}"
  puts

  print_group_table(rows)
  puts
end

if __FILE__ == $PROGRAM_NAME

matched_rows, perf_row_count = load_matched_rows
if matched_rows.empty?
  warn 'ERROR: no matched level algo rows.'
  exit 1
end

puts 'level algo type performance (grouped stats, all trades)'
puts "performance file: #{PERF_PATH}"
puts "config file: #{LEVEL_FAM_PATH}"
puts "algos in performance output: #{perf_row_count}"
puts "matched config algos: #{matched_rows.size}"
puts "profit_factor per group: sum(gross_profit) / sum(gross_loss) across algos in group"
puts

GROUP_SECTIONS.each do |section|
  print_section(section, matched_rows)
end

end
