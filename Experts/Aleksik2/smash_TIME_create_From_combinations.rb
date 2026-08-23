#!/usr/bin/env ruby
# frozen_string_literal: true
# Cartesian product of desired_* arrays -> REPLACE all time algos in aleksik2.mq5.
# Does NOT append — deletes previous base AND quant-ref time algos, then writes a fresh base set from combo #1.
# Re-run smash_from_QUANTREFERENCEPOINTS_creator.rb afterward to recreate quant-ref clones.

require "set"
require_relative "smash_TIME_creator_common"

# --- edit combination grids here ---
#dopoki niie ma swap cost, time to nie koszt, wiec ruleset 1 jest lepszy
#start tme 02:00 i 15:29 są oba mocne, ale wybieram jeden time, wiec wybieram 02:00 
DESIRED_ENTRY_TIMES = [
  # "15:29",
  # "16:00",
  # "16:25",
  # "21:58",
  "2:00"
].freeze

DESIRED_RULE_SWITCH_MAP = [0, 1].freeze  ### [0, 1] !!!!!!!!!! Rule 1: Secret-TP babysit close is only allowed during 14:30–15:29 server time

# [5.0, 10.0, 15.0, 20.0] 20.0 had most profit but 5.0 had most efficiency and still crazy profit
DESIRED_SECRET_TP_PROFIT_PERCENT_MIN = [1.0, 2.0, 8.0, 12.0].freeze # 5 10 20 # 2.0, 3.0. are too weak even vs buy and hold benchmark

DESIRED_SECRET_TP_GREENGUARD_PRICEDIFF_AT_LEAST = [10.0].freeze
DESIRED_MAX_TRADES_PER_DAY = [1].freeze
DESIRED_MAX_OPEN_POSITIONS = [10].freeze # 15
DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT = [1].freeze

TIME_RULE_MARKERS = %w[//timealgocreator3start //timealgocreator3end].freeze
QUANTREF_NEW_ID_RE = /(?:\/\/\s*)?quantref\s+base=\d+\s+new=(\d+)/

module TimeCombinationsCreator
  module_function

  def marker_line_re(marker)
    /^\s*#{Regexp.escape(marker)}\s*$/
  end

  def extract_marked_inner(content, markers)
    start_marker, end_marker = markers
    lines = content.lines
    start_idx = lines.index { |line| line.match?(marker_line_re(start_marker)) }
    end_idx = lines.index { |line| line.match?(marker_line_re(end_marker)) }
    unless start_idx && end_idx && end_idx > start_idx
      raise "Could not find block (#{start_marker} .. #{end_marker})"
    end

    lines[(start_idx + 1)...end_idx].join.rstrip
  end

  def replace_marked_inner(content, markers, new_inner)
    start_marker, end_marker = markers
    lines = content.lines
    start_idx = lines.index { |line| line.match?(marker_line_re(start_marker)) }
    end_idx = lines.index { |line| line.match?(marker_line_re(end_marker)) }
    unless start_idx && end_idx && end_idx > start_idx
      raise "Could not find block (#{start_marker} .. #{end_marker})"
    end

    before = lines[0..start_idx].join
    after = lines[end_idx..].join
    "#{before}#{new_inner.rstrip}\n#{after}"
  end

  def time_quant_clone_algo_ids(content)
    params_block = TimeCombinationsCommon.extract_inner(content, 2)
    rule_block =
      begin
        extract_marked_inner(content, TIME_RULE_MARKERS)
      rescue StandardError
        ""
      end
    ids = [params_block, rule_block].join.scan(QUANTREF_NEW_ID_RE).flatten.map(&:to_i)
    ids.select { |id| id >= TIME_ALGO_ID_MIN && id <= TIME_ALGO_ID_MAX }.uniq.sort
  end

  ENTRY_TIME_RE = /\A(\d{1,2}):(\d{2})\z/

  def parse_entry_time(text)
    match = text.to_s.strip.match(ENTRY_TIME_RE)
    raise "Invalid entry time #{text.inspect} (expected HH:MM)" unless match

    hour = match[1].to_i
    minute = match[2].to_i
    raise "Invalid hour in #{text.inspect}" unless hour.between?(0, 23)
    raise "Invalid minute in #{text.inspect}" unless minute.between?(0, 59)

    {
      entry_hour: hour,
      entry_minute: minute,
      label: TimeCombinationsCommon.entry_time_label(hour, minute)
    }
  end

  def entry_time_pairs
    DESIRED_ENTRY_TIMES.map { |text| parse_entry_time(text) }
  end

  def combination_dimension_counts
    {
      entry_times: entry_time_pairs.size,
      rule_switch_map: DESIRED_RULE_SWITCH_MAP.size,
      secret_tp_profit_percent_min: DESIRED_SECRET_TP_PROFIT_PERCENT_MIN.size,
      secret_tp_greenguard_pricediff_at_least: DESIRED_SECRET_TP_GREENGUARD_PRICEDIFF_AT_LEAST.size,
      max_trades_per_day: DESIRED_MAX_TRADES_PER_DAY.size,
      max_open_positions: DESIRED_MAX_OPEN_POSITIONS.size,
      stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count:
        DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT.size
    }
  end

  def build_combinations
    combos = []
    seen = Set.new

    entry_time_pairs.product(
      DESIRED_RULE_SWITCH_MAP,
      DESIRED_SECRET_TP_PROFIT_PERCENT_MIN,
      DESIRED_SECRET_TP_GREENGUARD_PRICEDIFF_AT_LEAST,
      DESIRED_MAX_TRADES_PER_DAY,
      DESIRED_MAX_OPEN_POSITIONS,
      DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT
    ) do |entry_pair, rule_switch_map, secret_tp, greenguard, max_trades, max_open, stop_total|
      combo = {
        entry_hour: entry_pair[:entry_hour],
        entry_minute: entry_pair[:entry_minute],
        rule_switch_map: rule_switch_map,
        secret_tp_profit_percent_min: secret_tp,
        secret_tp_greenguard_pricediff_at_least: greenguard,
        max_trades_per_day: max_trades,
        max_open_positions: max_open,
        stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count: stop_total
      }

      signature = TimeCombinationsCommon.combo_signature(combo)
      next if seen.include?(signature)

      seen << signature
      combos << combo
    end

    combos
  end

  def build_algo_params_block(algo_id, combo)
    const = TimeCombinationsCommon.time_const(algo_id)
    slot = "TimeAlgoSlotIndexByAlgoId(#{const})"
    entry_label = TimeCombinationsCommon.entry_time_label(combo[:entry_hour], combo[:entry_minute])

    <<~MQL5.rstrip
      g_timeAlgos[#{slot}].enabled = true;
      g_timeAlgos[#{slot}].entry_hour = #{combo[:entry_hour]};   // #{entry_label}
      g_timeAlgos[#{slot}].entry_minute = #{combo[:entry_minute]};
      g_timeAlgos[#{slot}].rule_switch_map = #{combo[:rule_switch_map]};
      g_timeAlgos[#{slot}].secret_tp_profit_percent_min = #{TimeCombinationsCommon.format_mq5_double(combo[:secret_tp_profit_percent_min])};
      g_timeAlgos[#{slot}].secret_tp_greenguard_pricediff_at_least = #{TimeCombinationsCommon.format_mq5_double(combo[:secret_tp_greenguard_pricediff_at_least])};
      g_timeAlgos[#{slot}].max_trades_per_day = #{combo[:max_trades_per_day]};
      g_timeAlgos[#{slot}].max_open_positions = #{combo[:max_open_positions]};
      g_timeAlgos[#{slot}].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = #{combo[:stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count]};
    MQL5
  end

  def algo_ids_for_count(count)
    raise "Need at least one time algo combination" if count <= 0

    last_id = TIME_ALGO_ID_MIN + count - 1
    raise "Ran out of time algo ids below #{TIME_ALGO_ID_MAX}" if last_id > TIME_ALGO_ID_MAX

    (TIME_ALGO_ID_MIN..last_id).to_a
  end

  def apply_combinations_overwrite!(content, combinations)
    algo_ids = algo_ids_for_count(combinations.size)
    required_registry_max = combinations.size

    content = set_time_registry_max(content, required_registry_max)
    inner1 = rebuild_registry_inner(algo_ids)
    inner2 =
      combinations.zip(algo_ids).map do |combo, algo_id|
        build_algo_params_block(algo_id, combo)
      end.join("\n\n")

    content = replace_inner(content, 1, inner1)
    content = replace_marked_inner(content, TIME_RULE_MARKERS, "")
    replace_inner(content, 2, inner2)
  end
end

include TimeCombinationsCommon
include TimeCombinationsCreator

if __FILE__ == $PROGRAM_NAME
  dimension_counts = combination_dimension_counts
  total_combinations = dimension_counts.values.reduce(1, :*)

  puts "Time algo combination count: #{total_combinations}"
  puts
  dimension_counts.each do |name, count|
    puts "  #{name}: #{count}"
  end
  puts "  (entry_times: #{entry_time_pairs.map { |pair| pair[:label] }.join(', ')})"
  puts

  content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  registry_max = time_registry_max(content)
  registry_headroom = time_registry_max_headroom(content)
  wired_ids = registry_algo_ids(content)
  quant_ids = time_quant_clone_algo_ids(content)

  all_combinations = build_combinations
  raise "Combination build mismatch: #{all_combinations.size} != #{total_combinations}" if all_combinations.size != total_combinations

  new_algo_ids = algo_ids_for_count(all_combinations.size)
  required_registry_max = all_combinations.size

  puts "Registry slot capacity:    #{registry_max} (TIME_ALGO_REGISTRY_MAX in aleksik2.mq5)"
  puts "Registry headroom:         #{registry_headroom} (max unused slots above wired count)"
  puts "Currently wired time IDs:  #{wired_ids.size} (#{wired_ids.join(', ')})"
  unless quant_ids.empty?
    puts "Quant-ref algos to remove: #{quant_ids.size} (#{quant_ids.join(', ')})"
  end
  puts "Will REPLACE with:         #{all_combinations.size} base algos"
  puts "New algo ID range:         #{new_algo_ids.first}..#{new_algo_ids.last}"
  puts "Required registry slots:   #{required_registry_max}"
  if required_registry_max != registry_max
    verb = required_registry_max > registry_max ? "raise" : "lower"
    puts "Will #{verb} TIME_ALGO_REGISTRY_MAX: #{registry_max} -> #{required_registry_max}"
  end
  puts
  puts "Mode: OVERWRITE (base + quant-ref time algos removed; timealgocreator3 rules cleared)"
  puts "      Re-run smash_from_QUANTREFERENCEPOINTS_creator.rb to recreate quant-ref clones."
  puts

  if all_combinations.empty?
    puts "No time algo combinations to create."
    exit 0
  end

  print "Overwrite time algos (#{quant_ids.size} quant + #{wired_ids.size} wired -> #{all_combinations.size} base)? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  updated = apply_combinations_overwrite!(content, all_combinations)
  File.write(MQ5_FILE, updated)

  after_ids = registry_algo_ids(updated)
  final_registry_max = time_registry_max(updated)
  puts "Wrote #{all_combinations.size} time algo(s): #{after_ids.join(', ')}"
  puts "TIME_ALGO_REGISTRY_MAX: #{registry_max} -> #{final_registry_max}" if required_registry_max != registry_max
  puts MQ5_FILE
end
