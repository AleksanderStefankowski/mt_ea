#!/usr/bin/env ruby
# frozen_string_literal: true
# Set g_breakdownAlgos[...].enabled for algos whose FILTER_VARIABLE matches FILTER_VALUES.

require_relative "smash_BREAKDOWN_creator_from_combinationsMap"

ALLOWED_FIELDS = %w[
  tested?
  enabled
  stop_trading_today_if_thisAlgo_losing_trades_count
  stop_trading_today_if_thisAlgo_winning_trades_count
  stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
  expiry_minutes
  this_algo_max_concurrent_pending_trades
  min_breakdown_sequence_len
  max_breakdown_sequence_len
  breakdown_streak_continuation_mode
  breakdowntype
  bd_start_min_breakdown_percent
  min_breakdown_total_percent
  after_bd_need_x_15greenc
  entry_max_minutes_after_bdend
  forget_about_latest_breakdown_after_x_15m_candles
  entryrange_range_percentspot
  secret_tp_range_percent
  secret_tp_greenguard_pricediff_at_least
  tp_enabled
  tp_notsecret_range_percent
  sl_enabled
  sl_points
  closetrade_after_some_time
  closetrade_after_some_time_butOnlyIfProfit
  closetrade_after_some_time_but_ProfitPercent_Needed
  closetrade_after_x_minutes_from_breakdown
  max_open_positions
].freeze

# --- edit filter here ---
FILTER_VARIABLE = "stop_trading_today_if_thisAlgo_losing_trades_count"
# FILTER_VALUES = [11, 18].freeze
FILTER_VALUES = [999].freeze

SET_ENABLED_TO = true

ENABLED_LINE_RE = /
  g_breakdownAlgos\[BreakdownAlgoSlotIndexByAlgoId\(MAGIC_BREAKDOWN(\d+)\)\]\.enabled\s*=\s*(true|false);
/x

module BreakdownDisableEnableByVariable
  module_function

  def normalize_filter_value(field, raw)
    BreakdownCombinationsMapCreator.normalize_row_field_for_signature(field, raw)
  end

  def normalized_filter_values(field, values)
    values.map { |v| normalize_filter_value(field, v) }
  end

  def matching_algo_ids(content, field, values)
    params = BreakdownCombinationsMapCreator.mq5_params_by_algo_id(content)
    wanted = normalized_filter_values(field, values)
    params.select do |_algo_id, algo_params|
      actual = normalize_filter_value(field, algo_params[field])
      wanted.include?(actual)
    end.keys.sort
  end

  def set_enabled_for_algos!(content, algo_ids, enabled)
    target = enabled ? "true" : "false"
    changed = []
    skipped = []

    updated = content.gsub(ENABLED_LINE_RE) do |match|
      algo_id = Regexp.last_match(1).to_i
      current = Regexp.last_match(2)

      unless algo_ids.include?(algo_id)
        next match
      end

      if current == target
        skipped << algo_id
        next match
      end

      changed << algo_id
      match.sub(/=\s*(true|false);/, "= #{target};")
    end

    [updated, changed.sort, skipped.sort]
  end
end

include BreakdownCombinationsCreator
include BreakdownDisableEnableByVariable

if __FILE__ == $PROGRAM_NAME
  unless ALLOWED_FIELDS.include?(FILTER_VARIABLE)
    warn "ERROR: FILTER_VARIABLE #{FILTER_VARIABLE.inspect} not in allowed list"
    exit 1
  end

  if FILTER_VALUES.empty?
    warn "ERROR: FILTER_VALUES is empty"
    exit 1
  end

  target = SET_ENABLED_TO ? "true" : "false"
  content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  wired_ids = registry_algo_ids(content)
  match_ids = matching_algo_ids(content, FILTER_VARIABLE, FILTER_VALUES)
  missing_enabled = match_ids.reject do |algo_id|
    content.match?(
      /g_breakdownAlgos\[BreakdownAlgoSlotIndexByAlgoId\(MAGIC_BREAKDOWN#{algo_id}\)\]\.enabled\s*=\s*(true|false);/
    )
  end

  puts "MQ5 file:                 #{MQ5_FILE}"
  puts "Wired breakdown algos:    #{wired_ids.size}"
  puts "Filter variable:          #{FILTER_VARIABLE}"
  puts "Filter values:            #{FILTER_VALUES.join(', ')}"
  puts "Set enabled to:           #{target}"
  puts
  puts "Matching algos:           #{match_ids.size}"
  puts match_ids.empty? ? "(none)" : match_ids.join(", ")
  puts

  if missing_enabled.any?
    warn "ERROR: no .enabled line for algo(s): #{missing_enabled.join(', ')}"
    exit 1
  end

  if match_ids.empty?
    puts "No breakdown algos match the filter."
    exit 0
  end

  _updated, changed, skipped = set_enabled_for_algos!(content, match_ids, SET_ENABLED_TO)

  if changed.empty?
    puts "No changes (#{skipped.join(', ')} already enabled=#{target})."
    exit 0
  end

  print "Set enabled=#{target} for #{changed.size} breakdown algo(s)? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  updated, = set_enabled_for_algos!(content, match_ids, SET_ENABLED_TO)
  File.write(MQ5_FILE, updated)

  puts "Set enabled=#{target} for #{changed.size} algo(s): #{changed.join(', ')}"
  puts "Unchanged (#{skipped.join(', ')})" unless skipped.empty?
  puts MQ5_FILE
end
