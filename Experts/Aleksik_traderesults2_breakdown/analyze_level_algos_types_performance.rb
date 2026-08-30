#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'alert_done_common'

# Group level algo performance by config dimensions. Console output only.
#
# Sections:
#   - trades_tags preset (all_tags, all_up, all_down, all_down_pivot)
#   - offset_positive + offset_percentage (paired)
#   - level scope (weekly, daily, both)
#   - secret_tp_profit_percent_min
#   - rule_switch_map (0=anytime; 1=14:30-15:29; 2=02:00-03:00 secret-TP close window)
#   - level_needs_to_be_below_ONO
#   - cannotTrade__when_levelProximity_multiplyOffset
#   - cannotTrade__when_levelProximity_multiplyOffset + offset_percentage (paired)
#   - offset_positive + offset_percentage + cannotTrade multiply (triple group + top-3 duels)
#   - stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
#
# Uses analyze_level_algos_performance_output.csv + config parsed from aleksik2_level_fam.mqh.

require 'set'
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
  { field: :rule_switch_map, title: 'RULE_SWITCH_MAP (0=anytime; 1=14:30-15:29; 2=02:00-03:00)' },
  { field: :level_needs_to_be_below_ONO, title: 'LEVEL_NEEDS_TO_BE_BELOW_ONO' },
  { field: :cannotTrade__when_levelProximity_multiplyOffset,
    title: 'CANNOT_TRADE__WHEN_LEVELPROXIMITY_MULTIPLYOFFSET' },
  { field: :proximity_offset_pair,
    title: 'CANNOT_TRADE__WHEN_LEVELPROXIMITY_MULTIPLYOFFSET + OFFSET_PERCENTAGE' },
  { field: :offset_proximity_triple,
    title: 'OFFSET_POSITIVE + OFFSET_PERCENTAGE + CANNOT_TRADE__WHEN_LEVELPROXIMITY_MULTIPLYOFFSET',
    top3_duels: true },
  { field: :stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count,
    title: 'STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT' }
].freeze

OFFSET_PROXIMITY_TRIPLE_FIELDS = %i[
  offset_positive offset_percentage cannotTrade__when_levelProximity_multiplyOffset
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
  [:avgprofitSumVSexposure, 10],
  [:avgavg_time_at_peak_exposure_hours, 14]
].freeze

TRIPLE_TABLE_COLUMNS = TABLE_COLUMNS.map do |name, width|
  name == :group ? [:group, 34] : [name, width]
end.freeze

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
        rule_switch_map: nil,
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
    elsif (match = line.match(/rule_switch_map = (\d+)/))
      config[:rule_switch_map] = match[1]
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
    config[:proximity_offset_pair] = config_pair_label(
      config[:cannotTrade__when_levelProximity_multiplyOffset],
      config[:offset_percentage]
    )
    config[:offset_proximity_triple] = offset_proximity_triple_label(
      config[:offset_positive],
      config[:offset_percentage],
      config[:cannotTrade__when_levelProximity_multiplyOffset]
    )
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
  config_pair_label(offset_positive, offset_percentage)
end

def config_pair_label(first, second)
  a = first.nil? ? 'n/a' : first.to_s
  b = second.nil? ? 'n/a' : second.to_s
  "#{a}, #{b}"
end

def offset_proximity_triple_label(offset_positive, offset_percentage, multiply_offset)
  a = offset_positive.nil? ? 'n/a' : offset_positive.to_s
  b = offset_percentage.nil? ? 'n/a' : offset_percentage.to_s
  c = multiply_offset.nil? ? 'n/a' : multiply_offset.to_s
  "#{a}, #{b}, #{c}"
end

def parse_offset_proximity_triple_key(group_key)
  parts = group_key.to_s.split(', ', 3)
  return %w[n/a n/a n/a] if parts.size < 3

  parts
end

def offset_proximity_triple_diff_fields(left_key, right_key)
  names = %w[offset_positive offset_percentage multiplyOffset]
  left_parts = parse_offset_proximity_triple_key(left_key)
  right_parts = parse_offset_proximity_triple_key(right_key)
  names.zip(left_parts, right_parts).filter_map do |name, left, right|
    name if left != right
  end
end

def offset_proximity_triple_keys_differ?(left_key, right_key)
  offset_proximity_triple_diff_fields(left_key, right_key).any?
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
  time_vs_profit_values = entries.map { |entry| Lib.parse_float(entry[:perf]['profitSumVSexposure']) }
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
    avgprofitSumVSexposure: Lib.average(time_vs_profit_values),
    avgavg_time_at_peak_exposure_hours: Lib.average(avg_peak_exposure_hours_values)
  }
end

def group_key_for_entry(entry, field)
  case field
  when :offset_pair
    entry[:config][:offset_pair]
  when :proximity_offset_pair
    entry[:config][:proximity_offset_pair]
  when :offset_proximity_triple
    entry[:config][:offset_proximity_triple]
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

def group_rows(matched_rows, field)
  grouped = matched_rows.group_by { |entry| group_key_for_entry(entry, field) }

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
  when :proximity_offset_pair
    multiply, percentage = group_key.to_s.split(', ', 2)
    [Lib.parse_float(multiply) || 99.0, Lib.parse_float(percentage) || 99.0, group_key.to_s]
  when :offset_proximity_triple
    positive, percentage, multiply = parse_offset_proximity_triple_key(group_key)
    positive_rank = { 'true' => 0, 'false' => 1, 'n/a' => 2 }.fetch(positive, 99)
    [positive_rank, Lib.parse_float(percentage) || 99.0, Lib.parse_float(multiply) || 99.0, group_key.to_s]
  when :level_needs_to_be_below_ONO
    { 'true' => 0, 'false' => 1, 'n/a' => 2 }.fetch(group_key.to_s, 99)
  when :secret_tp_profit_percent_min,
       :rule_switch_map,
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

LEVEL_CONFIG_SIGNATURE_KEYS = %i[
  weekly daily offset_positive offset_percentage secret_tp_profit_percent_min rule_switch_map
  level_needs_to_be_below_ONO cannotTrade__when_levelProximity_multiplyOffset
  stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
].freeze

def signature_exclude_for_field(field)
  case field
  when :trades_tags_preset
    %i[trades_tags_preset tags]
  when :offset_pair
    %i[offset_positive offset_percentage offset_pair offset_positive_label]
  when :level_scope
    %i[weekly daily level_scope]
  when :proximity_offset_pair
    %i[cannotTrade__when_levelProximity_multiplyOffset offset_percentage proximity_offset_pair]
  when :offset_proximity_triple
    %i[
      offset_positive offset_percentage cannotTrade__when_levelProximity_multiplyOffset
      offset_pair proximity_offset_pair offset_proximity_triple offset_positive_label
    ]
  when :level_needs_to_be_below_ONO
    %i[level_needs_to_be_below_ONO level_needs_to_be_below_ONO_label]
  else
    [field]
  end
end

def compare_config_key_for_field(field)
  case field
  when :level_needs_to_be_below_ONO
    :level_needs_to_be_below_ONO_label
  else
    field
  end
end

def level_config_signature(entry, field)
  exclude = signature_exclude_for_field(field).to_set
  LEVEL_CONFIG_SIGNATURE_KEYS
    .reject { |key| exclude.include?(key) }
    .map { |key| entry[:config][key].to_s }
    .join("\x1f")
end

def level_pair_side(entry, field)
  compare_key = compare_config_key_for_field(field).to_s
  Lib.make_pair_config_row(
    compare_key => group_key_for_entry(entry, field).to_s,
    'algo_id' => entry[:algo_id].to_s
  )
end

def build_level_pairs(matched_rows, field)
  pairs = []
  matched_rows
    .group_by { |entry| level_config_signature(entry, field) }
    .each_value do |entries|
      next if entries.size < 2

      values = entries.map { |entry| group_key_for_entry(entry, field).to_s }.uniq
      next if values.size < 2

      entries.combination(2).each do |left, right|
        left_value = group_key_for_entry(left, field).to_s
        right_value = group_key_for_entry(right, field).to_s
        next if left_value == right_value

        pairs << {
          left: { algo_id: left[:algo_id], config: level_pair_side(left, field), perf: left[:perf] },
          right: { algo_id: right[:algo_id], config: level_pair_side(right, field), perf: right[:perf] }
        }
      end
    end
  pairs
end

def duel_sort_key_for_field(field)
  lambda do |value|
    group_sort_key(field, value, {})
  end
end

TRIPLE_CHAMPION_COLUMNS = [
  [:group, 34],
  [:algo, 10],
  [:percent_sum, 12],
  [:profitSumVSexposure, 12],
  [:gross_profit, 12]
].freeze

def triple_group_champion_rows(matched_rows, field, rows)
  perf_field = 'percentSum_w_roll'
  rows.filter_map do |row|
    group_key = row[:group].to_s
    entries = matched_rows.select { |entry| group_key_for_entry(entry, field).to_s == group_key }
    best = Lib.best_algo_from_entries(entries, perf_field)
    next unless best

    entry = entries.find { |e| e[:algo_id].to_s == best[:algo_id] }
    gross_profit = entry ? Lib.parse_float(entry[:perf]['gross_profit']) : nil

    {
      group: group_key,
      algo: best[:algo_id],
      percent_sum: best[:metric],
      profitSumVSexposure: best[:profitSumVSexposure],
      gross_profit: gross_profit
    }
  end.sort_by { |row| group_sort_key(field, row[:group], {}) }
end

def print_triple_group_champions(matched_rows, field, rows)
  champions = triple_group_champion_rows(matched_rows, field, rows)
  return if champions.empty?

  puts '#1 by percent_sum per combination (highest profit, one row each):'
  header = TRIPLE_CHAMPION_COLUMNS.map { |name, width| name.to_s.ljust(width) }.join(' ')
  puts header
  puts '-' * header.length
  champions.each do |row|
    line = TRIPLE_CHAMPION_COLUMNS.map do |name, width|
      case name
      when :percent_sum, :gross_profit
        format_table_cell(row[name], width, numeric: true)
      when :profitSumVSexposure
        format_table_cell(row[name], width, numeric: true, decimals: Lib::TIMEVSPROFIT_DECIMALS)
      else
        format_table_cell(row[name], width)
      end
    end.join(' ')
    puts line
  end
  puts
end

def print_top3_triple_duels(section, matched_rows, rows)
  field = section[:field]
  compare_variable = compare_config_key_for_field(field).to_s
  pairs = build_level_pairs(matched_rows, field)
  top3 = rows.sort_by { |row| -row[:percent_sum].to_f }.first(3)

  if top3.size >= 2
    puts 'top-3 group duels (paired algos — same config except offset_positive, offset_percentage, multiplyOffset):'
    if pairs.empty?
      puts '(no paired algos)'
      puts
    else
      top3_keys = top3.map { |row| row[:group].to_s }
      puts "top groups by percent_sum: #{top3_keys.join(' | ')}"
      puts

      duel_blocks = 0
      header_printed = false
      top3_keys.combination(2).each do |left_key, right_key|
        next unless offset_proximity_triple_keys_differ?(left_key, right_key)

        diff_fields = offset_proximity_triple_diff_fields(left_key, right_key)
        puts "--- #{left_key} vs #{right_key} (diff: #{diff_fields.join(', ')}) ---"

        %w[percentSum_w_roll profitSumVSexposure].each do |perf_field|
          best_by_value = Lib.paired_duel_best_by_value_for_pair(
            pairs, compare_variable, perf_field, left_key, right_key
          )
          next if best_by_value.size < 2

          duel_label = Lib::METRIC_DUEL_LABELS[perf_field] || "#{perf_field} #1"
          lines = Lib.single_metric_duel_block_lines(
            duel_label: duel_label,
            perf_field: perf_field,
            best_by_value: best_by_value
          )
          next if lines.empty?

          unless header_printed
            cols = Lib::BEST_PAIR_DUEL_TABLE_COLUMNS
            header = cols.map { |name, width| name.to_s.ljust(width) }.join(' ')
            puts header
            puts '-' * header.length
            header_printed = true
          end
          lines.each { |line| puts line }
          duel_blocks += 1
        end
        puts
      end

      puts '(no paired duels among top-3 groups)' if duel_blocks.zero?
    end
  end

  print_triple_group_champions(matched_rows, field, rows)
end

def print_section_best_duels(section, matched_rows)
  return if section[:top3_duels]

  field = section[:field]
  compare_variable = compare_config_key_for_field(field).to_s
  pairs = build_level_pairs(matched_rows, field)
  group_count = matched_rows.map { |entry| group_key_for_entry(entry, field).to_s }.uniq.size
  return if group_count < 2

  lines =
    if pairs.empty?
      ['best pair duels: (no paired algos — same config except this dimension)']
    else
      Lib.best_pair_duel_table_lines(
        field_name: field.to_s,
        best_by_percent: {},
        best_by_time: {},
        pairs: pairs,
        compare_variable: compare_variable,
        sort_key: duel_sort_key_for_field(field)
      )
    end
  lines.each { |line| puts line }
  puts
end

def format_table_cell(value, width, numeric: false, decimals: 2)
  text =
    if value.nil?
      'n/a'
    elsif numeric && value.is_a?(Numeric)
      if decimals == 2 && value == value.to_i
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
      when :avgprofitSumVSexposure
        format_table_cell(row[name], width, numeric: true, decimals: Lib::TIMEVSPROFIT_DECIMALS)
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

def print_group_table(rows, columns: TABLE_COLUMNS)
  part1 = columns[0..6]
  part2 = [columns[0]] + columns[7..11]
  part3 = [columns[0]] + columns[12..]
  print_group_table_with_columns(rows, part1)
  puts
  print_group_table_with_columns(rows, part2)
  puts
  print_group_table_with_columns(rows, part3)
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

  if section[:top3_duels]
    print_group_table(rows, columns: TRIPLE_TABLE_COLUMNS)
  else
    print_group_table(rows)
  end
  puts
  if section[:top3_duels]
    print_top3_triple_duels(section, matched_rows, rows)
  else
    print_section_best_duels(section, matched_rows)
  end
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

play_alert_done! if __FILE__ == $PROGRAM_NAME
