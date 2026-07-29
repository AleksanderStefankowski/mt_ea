#!/usr/bin/env ruby
# frozen_string_literal: true
# Bulk-edit g_breakdownAlgos fields for algos whose FILTER_VARIABLE matches FILTER_VALUES.
# Also auto-fixes dependent fields required by aleksik2.mq5 validation.

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

# Keep in sync with BREAKDOWN_ENTRY_FORGET_MIN_ROOM_MINUTES in aleksik2.mq5
BREAKDOWN_ENTRY_FORGET_MIN_ROOM_MINUTES = 15

# --- edit filter here ---
FILTER_VARIABLE = "max_open_positions"
FILTER_VALUES = [10].freeze
SET_VARIABLE_TO = 20
SET_ENABLED_TO = nil # set to nil to leave .enabled unchanged

PARAM_ASSIGN_RE = /
  g_breakdownAlgos\[BreakdownAlgoSlotIndexByAlgoId\(MAGIC_BREAKDOWN(\d+)\)\]\.(\w+)\s*=\s*([^;]+);
/x

module BreakdownEditByVariable
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

  def format_mq5_field_value(field, value)
    case field
    when *DOUBLE_SIGNATURE_FIELDS
      BreakdownCombinationsCreator.format_mq5_double(value)
    when *BOOL_SIGNATURE_FIELDS
      bool =
        case value
        when true, false then value
        else %w[true 1 yes].include?(value.to_s.strip.downcase)
        end
      BreakdownCombinationsCreator.format_mq5_bool(bool)
    when "breakdown_streak_continuation_mode"
      value.to_s
    else
      s = value.to_s.strip
      s.match?(/\A-?\d+\z/) ? s.to_i.to_s : s
    end
  end

  def max_entry_max_minutes_for_forget_candles(forget_candles)
    forget_candles.to_i * 15 - BREAKDOWN_ENTRY_FORGET_MIN_ROOM_MINUTES
  end

  def dependent_field_targets(params, filter_variable, set_variable_to)
    targets = {}

    effective_forget =
      if filter_variable == "forget_about_latest_breakdown_after_x_15m_candles"
        set_variable_to
      else
        params["forget_about_latest_breakdown_after_x_15m_candles"]
      end

    return targets if effective_forget.nil? || effective_forget.to_s.strip.empty?

    entry_max = params["entry_max_minutes_after_bdend"].to_i
    max_entry = max_entry_max_minutes_for_forget_candles(effective_forget)
    targets["entry_max_minutes_after_bdend"] = max_entry if entry_max > max_entry

    targets
  end

  def build_algo_field_targets(params_by_algo, match_ids, filter_variable, set_variable_to, set_enabled_to)
    targets_by_algo = {}

    match_ids.each do |algo_id|
      params = params_by_algo[algo_id]
      targets = {}

      current_filter = normalize_filter_value(filter_variable, params[filter_variable])
      wanted_filter = normalize_filter_value(filter_variable, set_variable_to)
      targets[filter_variable] = set_variable_to unless current_filter == wanted_filter

      unless set_enabled_to.nil?
        current_enabled = normalize_filter_value("enabled", params["enabled"])
        wanted_enabled = normalize_filter_value("enabled", set_enabled_to)
        targets["enabled"] = set_enabled_to unless current_enabled == wanted_enabled
      end

      dependent_field_targets(params, filter_variable, set_variable_to).each do |field, value|
        current = normalize_filter_value(field, params[field])
        wanted = normalize_filter_value(field, value)
        targets[field] = value unless current == wanted
      end

      targets_by_algo[algo_id] = targets unless targets.empty?
    end

    targets_by_algo
  end

  def apply_edits!(content, targets_by_algo)
    changed_by_field = Hash.new { |h, k| h[k] = [] }
    skipped_by_field = Hash.new { |h, k| h[k] = [] }

    updated = content.gsub(PARAM_ASSIGN_RE) do |match|
      algo_id = Regexp.last_match(1).to_i
      field = Regexp.last_match(2)
      current_raw = BreakdownCombinationsMapCreator.parse_mq5_value(Regexp.last_match(3))
      targets = targets_by_algo[algo_id]
      next match unless targets&.key?(field)

      target_value = targets[field]
      current = normalize_filter_value(field, current_raw)
      wanted = normalize_filter_value(field, target_value)
      formatted = format_mq5_field_value(field, target_value)

      if current == wanted
        skipped_by_field[field] << algo_id
        next match
      end

      changed_by_field[field] << algo_id
      match.sub(/=\s*[^;]+;/, "= #{formatted};")
    end

    missing_by_field = Hash.new { |h, k| h[k] = [] }
    targets_by_algo.each do |algo_id, targets|
      targets.each_key do |field|
        next if changed_by_field[field].include?(algo_id) || skipped_by_field[field].include?(algo_id)

        missing_by_field[field] << algo_id
      end
    end

    [updated, changed_by_field, skipped_by_field, missing_by_field]
  end

  def summarize_field_changes(changed_by_field, skipped_by_field, field)
  {
    changed: changed_by_field[field]&.uniq&.sort || [],
    skipped: skipped_by_field[field]&.uniq&.sort || []
  }
  end
end

include BreakdownCombinationsCreator
include BreakdownEditByVariable

if __FILE__ == $PROGRAM_NAME
  unless ALLOWED_FIELDS.include?(FILTER_VARIABLE)
    warn "ERROR: FILTER_VARIABLE #{FILTER_VARIABLE.inspect} not in allowed list"
    exit 1
  end

  if FILTER_VALUES.empty?
    warn "ERROR: FILTER_VALUES is empty"
    exit 1
  end

  content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  params_by_algo = BreakdownCombinationsMapCreator.mq5_params_by_algo_id(content)
  wired_ids = registry_algo_ids(content)
  match_ids = matching_algo_ids(content, FILTER_VARIABLE, FILTER_VALUES)
  targets_by_algo = build_algo_field_targets(
    params_by_algo, match_ids, FILTER_VARIABLE, SET_VARIABLE_TO, SET_ENABLED_TO
  )

  puts "MQ5 file:                 #{MQ5_FILE}"
  puts "Wired breakdown algos:    #{wired_ids.size}"
  puts "Filter variable:          #{FILTER_VARIABLE}"
  puts "Filter values:            #{FILTER_VALUES.join(', ')}"
  puts "Set variable to:          #{SET_VARIABLE_TO}"
  puts "Set enabled to:           #{SET_ENABLED_TO.nil? ? '(unchanged)' : SET_ENABLED_TO}"
  puts "Auto-fix dependency:      entry_max_minutes_after_bdend <= forget*15-#{BREAKDOWN_ENTRY_FORGET_MIN_ROOM_MINUTES}"
  puts
  puts "Matching algos:           #{match_ids.size}"
  puts match_ids.empty? ? "(none)" : match_ids.join(", ")
  puts

  if match_ids.empty?
    puts "No breakdown algos match the filter."
    exit 0
  end

  _updated, changed_by_field, skipped_by_field, missing_by_field = apply_edits!(content, targets_by_algo)

  missing_by_field.each do |field, ids|
    next if ids.empty?

    warn "ERROR: no #{field} line for algo(s): #{ids.join(', ')}"
    exit 1
  end

  if targets_by_algo.empty?
    puts "No changes needed."
    exit 0
  end

  filter_summary = summarize_field_changes(changed_by_field, skipped_by_field, FILTER_VARIABLE)
  enabled_summary = summarize_field_changes(changed_by_field, skipped_by_field, "enabled")
  entry_summary = summarize_field_changes(changed_by_field, skipped_by_field, "entry_max_minutes_after_bdend")

  unless filter_summary[:changed].empty?
    puts "Will update #{FILTER_VARIABLE} -> #{SET_VARIABLE_TO} for #{filter_summary[:changed].size} algo(s)"
  end
  unless filter_summary[:skipped].empty?
    puts "Will skip #{FILTER_VARIABLE} (#{filter_summary[:skipped].size} already #{SET_VARIABLE_TO})"
  end
  unless SET_ENABLED_TO.nil?
    unless enabled_summary[:changed].empty?
      puts "Will set enabled=#{SET_ENABLED_TO} for #{enabled_summary[:changed].size} algo(s)"
    end
    unless enabled_summary[:skipped].empty?
      puts "Will skip enabled (#{enabled_summary[:skipped].size} already #{SET_ENABLED_TO})"
    end
  end
  unless entry_summary[:changed].empty?
    max_entry = max_entry_max_minutes_for_forget_candles(SET_VARIABLE_TO)
    puts "Will cap entry_max_minutes_after_bdend to #{max_entry} for #{entry_summary[:changed].size} algo(s)"
  end
  puts

  print "Apply edits to #{targets_by_algo.size} breakdown algo(s)? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  updated, changed_by_field, skipped_by_field, = apply_edits!(content, targets_by_algo)
  File.write(MQ5_FILE, updated)

  filter_summary = summarize_field_changes(changed_by_field, skipped_by_field, FILTER_VARIABLE)
  enabled_summary = summarize_field_changes(changed_by_field, skipped_by_field, "enabled")
  entry_summary = summarize_field_changes(changed_by_field, skipped_by_field, "entry_max_minutes_after_bdend")

  unless filter_summary[:changed].empty?
    puts "Updated #{FILTER_VARIABLE}=#{SET_VARIABLE_TO} for #{filter_summary[:changed].size} algo(s): #{filter_summary[:changed].join(', ')}"
  end
  unless filter_summary[:skipped].empty?
    puts "#{FILTER_VARIABLE} already #{SET_VARIABLE_TO}: #{filter_summary[:skipped].join(', ')}"
  end
  unless SET_ENABLED_TO.nil?
    unless enabled_summary[:changed].empty?
      puts "Set enabled=#{SET_ENABLED_TO} for #{enabled_summary[:changed].size} algo(s): #{enabled_summary[:changed].join(', ')}"
    end
    unless enabled_summary[:skipped].empty?
      puts "Enabled already #{SET_ENABLED_TO}: #{enabled_summary[:skipped].join(', ')}"
    end
  end
  unless entry_summary[:changed].empty?
    max_entry = max_entry_max_minutes_for_forget_candles(SET_VARIABLE_TO)
    puts "Capped entry_max_minutes_after_bdend to #{max_entry} for #{entry_summary[:changed].size} algo(s): #{entry_summary[:changed].join(', ')}"
  end
  puts MQ5_FILE
end
