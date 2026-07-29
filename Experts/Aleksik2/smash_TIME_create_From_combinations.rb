#!/usr/bin/env ruby
# frozen_string_literal: true
# Cartesian product of desired_* arrays -> new time algos in aleksik2.mq5.
# Skips combinations whose config already exists among wired time algos.

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

DESIRED_RULE_SWITCH_MAP = [1].freeze  ### [0, 1] !!!!!!!!!! Rule 1: Secret-TP babysit close is only allowed during 14:30–15:29 server time

# [5.0, 10.0, 15.0, 20.0] 20.0 had most profit but 5.0 had most efficiency and still crazy profit
DESIRED_SECRET_TP_PROFIT_PERCENT_MIN = [2.0, 3.5, 5.0, 10.0, 15.0, 20.0].freeze # 5 10 20 # also test 2.0, 3.5. 

DESIRED_SECRET_TP_GREENGUARD_PRICEDIFF_AT_LEAST = [12.0].freeze
DESIRED_MAX_TRADES_PER_DAY = [1].freeze
DESIRED_MAX_OPEN_POSITIONS = [15].freeze # 10, 15
DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT = [1].freeze

module TimeCombinationsCreator
  module_function

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

  def append_params_block(inner, algo_id, combo)
    const = TimeCombinationsCommon.time_const(algo_id)
    return inner if inner.include?("TimeAlgoSlotIndexByAlgoId(#{const})")

    inner.rstrip + "\n" + build_algo_params_block(algo_id, combo)
  end

  def next_algo_ids(existing_ids, count)
    raise "Need at least one new algo id" if count <= 0

    ids = existing_ids.dup
    out = []
    candidate = ids.empty? ? TIME_ALGO_ID_MIN : ids.max + 1
    while out.size < count
      raise "Ran out of time algo ids below #{TIME_ALGO_ID_MAX}" if candidate > TIME_ALGO_ID_MAX

      unless ids.include?(candidate)
        out << candidate
        ids << candidate
      end
      candidate += 1
    end
    out
  end

  def filter_new_combinations(content, combinations)
    existing = TimeCombinationsCommon.existing_combo_signatures(content)
    combinations.reject do |combo|
      existing.include?(TimeCombinationsCommon.combo_signature(combo))
    end
  end

  def apply_combinations!(content, combinations)
    existing_ids = TimeCombinationsCommon.registry_algo_ids(content)
    new_ids = next_algo_ids(existing_ids, combinations.size)
    all_ids = (existing_ids + new_ids).uniq.sort

    inner1 = TimeCombinationsCommon.rebuild_registry_inner(all_ids)
    inner2 = TimeCombinationsCommon.extract_inner(content, 2)

    combinations.zip(new_ids).each do |combo, algo_id|
      inner2 = append_params_block(inner2, algo_id, combo)
    end

    content = TimeCombinationsCommon.replace_inner(content, 1, inner1)
    TimeCombinationsCommon.replace_inner(content, 2, inner2)
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
  empty_slots = registry_max - wired_ids.size

  all_combinations = build_combinations
  raise "Combination build mismatch: #{all_combinations.size} != #{total_combinations}" if all_combinations.size != total_combinations

  new_combinations = filter_new_combinations(content, all_combinations)
  duplicate_count = all_combinations.size - new_combinations.size
  required_registry_max = compute_registry_max_for_wired_count(wired_ids.size + new_combinations.size)
  next_algo_id = wired_ids.empty? ? TIME_ALGO_ID_MIN : wired_ids.max + 1

  puts "Registry slot capacity:    #{registry_max} (TIME_ALGO_REGISTRY_MAX in aleksik2.mq5)"
  puts "Registry headroom:         #{registry_headroom} (max unused slots above wired count)"
  puts "Wired time algos:          #{wired_ids.size} (#{wired_ids.join(', ')})"
  puts "Empty registry slots:      #{empty_slots}"
  puts "Already exist (skip):      #{duplicate_count}"
  puts "Will create:               #{new_combinations.size}"
  puts "Required registry slots:   #{required_registry_max} (after creating #{new_combinations.size})"
  puts "Time algo ID range:        #{TIME_ALGO_ID_MIN}..#{TIME_ALGO_ID_MAX}"
  puts "Next new algo ID would be: #{next_algo_id}"
  if required_registry_max > registry_max
    puts "Will raise TIME_ALGO_REGISTRY_MAX: #{registry_max} -> #{required_registry_max}"
  end
  puts

  if new_combinations.empty?
    puts "No new time algo combinations to create."
    exit 0
  end

  print "Create #{new_combinations.size} time algo(s) in #{MQ5_FILE}? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  before_ids = wired_ids
  content = set_time_registry_max(content, required_registry_max) if required_registry_max > registry_max
  updated = apply_combinations!(content, new_combinations)
  File.write(MQ5_FILE, updated)

  after_ids = registry_algo_ids(updated)
  new_ids = after_ids - before_ids
  final_registry_max = time_registry_max(updated)
  puts "Created #{new_combinations.size} time algo(s): #{new_ids.sort.join(', ')}"
  puts "TIME_ALGO_REGISTRY_MAX: #{registry_max} -> #{final_registry_max}" if required_registry_max > registry_max
  puts MQ5_FILE
end
