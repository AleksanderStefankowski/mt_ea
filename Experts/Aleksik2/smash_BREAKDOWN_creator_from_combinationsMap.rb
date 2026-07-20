#!/usr/bin/env ruby
# frozen_string_literal: true
# Read combinationsMap.csv (tested?=false) -> new enabled breakdown algos in aleksik2.mq5.

count_of_created_algos_limit = 1000

require "csv"
require_relative "smash_BREAKDOWN_creator_from_combinations"

COMBINATIONS_MAP_CSV = File.expand_path("combinationsMap.csv", __dir__)

# Keep in sync with smash_BREAKDOWN_create_combinationsMap_csv.rb
COMBINATION_MAP_FIELDS = %w[
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
  secret_tp_enabled
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

COMBINATION_SIGNATURE_FIELDS = (COMBINATION_MAP_FIELDS - ["tested?"]).freeze

BREAKDOWN_MODE_TO_TYPE = BREAKDOWN_TYPE_TO_MODE.invert.freeze

BD_PARAMS_ASSIGN_RE = /
  g_breakdownAlgos\[BreakdownAlgoSlotIndexByAlgoId\(MAGIC_BREAKDOWN(\d+)\)\]\.(\w+)\s*=\s*([^;]+);
/x

DOUBLE_SIGNATURE_FIELDS = %w[
  bd_start_min_breakdown_percent
  min_breakdown_total_percent
  entryrange_range_percentspot
  secret_tp_greenguard_pricediff_at_least
  sl_points
  closetrade_after_some_time_but_ProfitPercent_Needed
].freeze

BOOL_SIGNATURE_FIELDS = %w[
  enabled
  secret_tp_enabled
  tp_enabled
  sl_enabled
  closetrade_after_some_time
  closetrade_after_some_time_butOnlyIfProfit
].freeze

module BreakdownCombinationsMapCreator
  module_function

  def csv_bool?(value)
    %w[true 1 yes].include?(value.to_s.strip.downcase)
  end

  def normalize_signature_value(value)
    s = value.to_s.strip
    case s.downcase
    when "true" then "true"
    when "false" then "false"
    else s
    end
  end

  def parse_mq5_value(raw)
    raw.to_s.strip.sub(%r{//.*}, "").strip
  end

  def normalize_row_field_for_signature(field, value, all_fields = {})
    case field
    when "breakdowntype"
      if value && !value.to_s.strip.empty?
        normalize_signature_value(value)
      else
        mode = parse_mq5_value(all_fields["breakdown_streak_continuation_mode"])
        normalize_signature_value(BREAKDOWN_MODE_TO_TYPE[mode] || mode)
      end
    when *DOUBLE_SIGNATURE_FIELDS
      format("%.2f", value.to_f)
    when *BOOL_SIGNATURE_FIELDS
      normalize_signature_value(value)
    else
      s = value.to_s.strip
      s = s.sub(/\.0+\z/, "") if s.match?(/\A-?\d+\.0+\z/)
      normalize_signature_value(s)
    end
  end

  def row_signature(row)
    COMBINATION_SIGNATURE_FIELDS
      .map { |field| normalize_row_field_for_signature(field, row[field], row) }
      .join("\0")
  end

  def mq5_params_by_algo_id(content)
    inner = extract_inner(content, 2)
    params = Hash.new { |h, k| h[k] = {} }
    inner.scan(BD_PARAMS_ASSIGN_RE) do |algo_id, field, value|
      params[algo_id.to_i][field] = parse_mq5_value(value)
    end
    params
  end

  def wired_combination_signatures(content)
    mq5_params_by_algo_id(content).each_value.map { |params| row_signature(params) }.to_set
  end

  def normalize_csv_row(row)
    COMBINATION_MAP_FIELDS.each_with_object({}) do |field, normalized|
      normalized[field] = row[field]&.to_s&.strip
    end
  end

  def row_tested?(row)
    csv_bool?(row["tested?"])
  end

  def select_untested_rows_to_create(path, limit, existing_signatures)
    raise "Missing combinations map: #{path}" unless File.exist?(path)

    table = CSV.read(path, headers: true)
    missing = COMBINATION_MAP_FIELDS - table.headers
    unless missing.empty?
      raise "combinationsMap.csv missing columns: #{missing.join(', ')}"
    end

    rows = []
    skipped_existing = 0
    table.each do |csv_row|
      row = normalize_csv_row(csv_row)
      next if row_tested?(row)

      if existing_signatures.include?(row_signature(row))
        skipped_existing += 1
        next
      end

      rows << row
      break if rows.size >= limit
    end

    { rows: rows, skipped_existing: skipped_existing }
  end

  def build_algo_params_block_from_row(algo_id, row)
    const = magic_const(algo_id)
    slot = "BreakdownAlgoSlotIndexByAlgoId(#{const})"

    <<~MQL5.rstrip

      g_breakdownAlgos[#{slot}].enabled = true;
      g_breakdownAlgos[#{slot}].stop_trading_today_if_thisAlgo_losing_trades_count = #{row["stop_trading_today_if_thisAlgo_losing_trades_count"].to_i};
      g_breakdownAlgos[#{slot}].stop_trading_today_if_thisAlgo_winning_trades_count = #{row["stop_trading_today_if_thisAlgo_winning_trades_count"].to_i};
      g_breakdownAlgos[#{slot}].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = #{row["stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count"].to_i};
      g_breakdownAlgos[#{slot}].expiry_minutes = #{row["expiry_minutes"].to_i};
      g_breakdownAlgos[#{slot}].this_algo_max_concurrent_pending_trades = #{row["this_algo_max_concurrent_pending_trades"].to_i};
      g_breakdownAlgos[#{slot}].min_breakdown_sequence_len = #{row["min_breakdown_sequence_len"].to_i}; // more important starts here and below:
      g_breakdownAlgos[#{slot}].max_breakdown_sequence_len = #{row["max_breakdown_sequence_len"].to_i};
      g_breakdownAlgos[#{slot}].breakdown_streak_continuation_mode = #{row["breakdown_streak_continuation_mode"]};
      g_breakdownAlgos[#{slot}].bd_start_min_breakdown_percent = #{format_mq5_double(row["bd_start_min_breakdown_percent"])};
      g_breakdownAlgos[#{slot}].min_breakdown_total_percent = #{format_mq5_double(row["min_breakdown_total_percent"])};
      g_breakdownAlgos[#{slot}].after_bd_need_x_15greenc = #{row["after_bd_need_x_15greenc"].to_i};
      g_breakdownAlgos[#{slot}].entry_max_minutes_after_bdend = #{row["entry_max_minutes_after_bdend"].to_i};
      g_breakdownAlgos[#{slot}].forget_about_latest_breakdown_after_x_15m_candles = #{row["forget_about_latest_breakdown_after_x_15m_candles"].to_i};
      g_breakdownAlgos[#{slot}].entryrange_range_percentspot = #{format_mq5_double(row["entryrange_range_percentspot"])};
      g_breakdownAlgos[#{slot}].secret_tp_enabled = #{row["secret_tp_enabled"].downcase};
      g_breakdownAlgos[#{slot}].secret_tp_range_percent = #{row["secret_tp_range_percent"].to_i};
      g_breakdownAlgos[#{slot}].secret_tp_greenguard_pricediff_at_least = #{format_mq5_double(row["secret_tp_greenguard_pricediff_at_least"])};
      g_breakdownAlgos[#{slot}].tp_enabled = #{row["tp_enabled"].downcase};
      g_breakdownAlgos[#{slot}].tp_notsecret_range_percent = #{row["tp_notsecret_range_percent"].to_i};
      g_breakdownAlgos[#{slot}].sl_enabled = #{row["sl_enabled"].downcase};
      g_breakdownAlgos[#{slot}].sl_points = #{format_mq5_double(row["sl_points"])};
      g_breakdownAlgos[#{slot}].closetrade_after_some_time = #{row["closetrade_after_some_time"].downcase};
      g_breakdownAlgos[#{slot}].closetrade_after_some_time_butOnlyIfProfit = #{row["closetrade_after_some_time_butOnlyIfProfit"].downcase};
      g_breakdownAlgos[#{slot}].closetrade_after_some_time_but_ProfitPercent_Needed = #{format_mq5_double(row["closetrade_after_some_time_but_ProfitPercent_Needed"])};
      g_breakdownAlgos[#{slot}].closetrade_after_x_minutes_from_breakdown = #{row["closetrade_after_x_minutes_from_breakdown"].to_i};
      g_breakdownAlgos[#{slot}].max_open_positions = #{row["max_open_positions"].to_i};
    MQL5
  end

  def append_params_block_from_row(inner, algo_id, row)
    block = build_algo_params_block_from_row(algo_id, row)
    return inner if inner.include?("BreakdownAlgoSlotIndexByAlgoId(#{magic_const(algo_id)})")

    inner.rstrip + "\n\n" + block
  end

  def apply_map_rows!(content, rows)
    existing_ids = registry_algo_ids(content)
    new_ids = next_algo_ids(existing_ids, rows.size)
    all_ids = (existing_ids + new_ids).uniq.sort

    inner1 = rebuild_registry_inner(all_ids)
    inner2 = extract_inner(content, 2)
    inner4 = extract_inner(content, 4)

    rows.zip(new_ids).each do |row, algo_id|
      inner2 = append_params_block_from_row(inner2, algo_id, row)
      inner4 = append_rule_case(inner4, algo_id)
    end

    content = replace_inner(content, 1, inner1)
    content = replace_inner(content, 2, inner2)
    replace_inner(content, 4, inner4)
  end
end

include BreakdownCombinationsCreator
include BreakdownCombinationsMapCreator

if __FILE__ == $PROGRAM_NAME
  limit = count_of_created_algos_limit
  raise "count_of_created_algos_limit must be >= 1" if limit < 1

  all_rows = CSV.read(COMBINATIONS_MAP_CSV, headers: true)
  total_untested = all_rows.count { |r| !BreakdownCombinationsMapCreator.row_tested?(BreakdownCombinationsMapCreator.normalize_csv_row(r)) }

  content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  existing_signatures = wired_combination_signatures(content)
  selection = select_untested_rows_to_create(COMBINATIONS_MAP_CSV, limit, existing_signatures)
  rows_to_create = selection[:rows]
  skipped_existing = selection[:skipped_existing]

  puts "combinationsMap: #{COMBINATIONS_MAP_CSV}"
  puts "Untested rows in map:     #{total_untested}"
  puts "Already wired (skipped):  #{skipped_existing}"
  puts "Create limit (top var):   #{limit}"
  puts "Will create this run:     #{rows_to_create.size}"
  puts

  registry_max = breakdown_registry_max(content)
  registry_headroom = breakdown_registry_max_headroom(content)
  wired_ids = registry_algo_ids(content)
  empty_slots = registry_max - wired_ids.size
  next_algo_id = wired_ids.empty? ? BREAKDOWN_ID_MIN : wired_ids.max + 1
  required_registry_max = compute_registry_max_for_wired_count(wired_ids.size + rows_to_create.size)

  puts "Registry slot capacity:   #{registry_max} (BREAKDOWN_ALGO_REGISTRY_MAX in aleksik2.mq5)"
  puts "Registry headroom:        #{registry_headroom}"
  puts "Wired breakdown algos:    #{wired_ids.size}"
  puts "Empty registry slots:     #{empty_slots}"
  puts "Required registry slots:  #{required_registry_max} (after creating #{rows_to_create.size})"
  puts "Next new algo ID:         #{next_algo_id}"
  if required_registry_max > registry_max
    puts "Will raise BREAKDOWN_ALGO_REGISTRY_MAX: #{registry_max} -> #{required_registry_max}"
  end
  puts

  if rows_to_create.empty?
    puts "No new untested combinations to create (all skipped or already wired)."
    exit 0
  end

  print "Create #{rows_to_create.size} enabled breakdown algo(s) in #{MQ5_FILE}? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  content = set_breakdown_registry_max(content, required_registry_max) if required_registry_max > registry_max
  updated = apply_map_rows!(content, rows_to_create)
  File.write(MQ5_FILE, updated)

  new_ids = registry_algo_ids(updated).last(rows_to_create.size)
  final_registry_max = breakdown_registry_max(updated)
  puts "Created #{rows_to_create.size} breakdown algo(s): #{new_ids.join(', ')}"
  puts "BREAKDOWN_ALGO_REGISTRY_MAX: #{registry_max} -> #{final_registry_max}" if required_registry_max > registry_max
  puts MQ5_FILE
  puts
  puts "Note: combinationsMap.csv tested? flags are unchanged — mark tested after backtest."
end
