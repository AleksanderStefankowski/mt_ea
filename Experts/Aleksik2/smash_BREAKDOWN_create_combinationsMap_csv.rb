#!/usr/bin/env ruby
# frozen_string_literal: true
# Cartesian product of desired_* arrays -> combinationsMap.csv (no aleksik2 edits).
# Merges into existing combinationsMap.csv when present:
#   - matching rows (all fields except tested?): keep tested? from file
#   - new grid combos: append with tested?=false
#   - rows only in old file (dropped from grid): kept at end
#   - duplicate signatures: one row only (tested?=true wins when merging dupes in file)

require "csv"

OUT_CSV = File.expand_path("combinationsMap.csv", __dir__)

BREAKDOWN_TYPE_TO_MODE = {
  "CLOSES" => "BREAKDOWN_STREAK_CONTINUATION_CLOSES",
  "OHLC_AVG" => "BREAKDOWN_STREAK_CONTINUATION_OHLC_AVG",
  "LOW" => "BREAKDOWN_STREAK_CONTINUATION_LOW",
  "OC_MID" => "BREAKDOWN_STREAK_CONTINUATION_OC_MID",
  "HL_MID" => "BREAKDOWN_STREAK_CONTINUATION_HL_MID"
}.freeze

# All breakdown-algo-specific fields needed to recreate an algo from the map alone.
COMBINATION_MAP_FIELDS = %w[
  tested?
  enabled
  stop_trading_today_if_thisAlgo_losing_trades_count
  stop_trading_today_if_thisAlgo_winning_trades_count
  stop_trading_today_if_thisAlgo_total_trades_count
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

# --- edit combination grids here ---
DESIRED_EXPIRY_MINUTES = [15].freeze #  [15, 45]
DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TOTAL_TRADES_COUNT = [3].freeze # 3 5 10

DESIRED_CLOSETRADE_AFTER_SOME_TIME = [false].freeze
DESIRED_CLOSETRADE_AFTER_SOME_TIME_BUT_PROFITPERCENT_NEEDED = [2.0].freeze
DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN = [90].freeze

DESIRED_MIN_BREAKDOWN_SEQUENCE_LEN = [3].freeze # 3  [3, 4, 5]
DESIRED_MAX_BREAKDOWN_SEQUENCE_LEN = [9].freeze # 9 [9]

DESIRED_BD_START_MIN_BREAKDOWN_PERCENT = [0.20].freeze # 0.20  [0.20, 0.35]
DESIRED_MIN_BREAKDOWN_TOTAL_PERCENT = [0.60].freeze  #  [0.40, 0.60, 0.85, 1.50]

DESIRED_AFTER_BD_NEED_X_15GREENC = [1, 2, 4].freeze #  [1, 2, 3]
DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND = [75].freeze

DESIRED_FORGET_ABOUT_LATEST_BREAKDOWN_AFTER_X_15M_CANDLES = [6].freeze # 6 [6, 9]

DESIRED_ENTRYRANGE_RANGE_PERCENTSPOT = [20, 33, 50, 66, 75].freeze #  [20, 33, 50, 66, 75]
DESIRED_SECRET_TP_RANGE_PERCENT = [0, 20, 45, 75].freeze

DESIRED_TP_NOTSECRET_RANGE_PERCENT = [150].freeze
DESIRED_MAX_OPEN_POSITIONS = [10].freeze
DESIRED_BREAKDOWNTYPES = %w[
  CLOSES
  OHLC_AVG
  LOW
  OC_MID
  HL_MID
].freeze

module BreakdownCombinationsMap
  module_function

  def format_csv_double(value)
    format("%.2f", value.to_f)
  end

  def format_csv_bool(value)
    value ? "true" : "false"
  end

  def breakdowntype_for_mode(mode)
    BREAKDOWN_TYPE_TO_MODE.key(mode) || mode
  end

  def build_combinations
    combos = []
    DESIRED_MIN_BREAKDOWN_SEQUENCE_LEN.product(
      DESIRED_MAX_BREAKDOWN_SEQUENCE_LEN,
      DESIRED_BD_START_MIN_BREAKDOWN_PERCENT,
      DESIRED_MIN_BREAKDOWN_TOTAL_PERCENT,
      DESIRED_EXPIRY_MINUTES,
      DESIRED_AFTER_BD_NEED_X_15GREENC,
      DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND,
      DESIRED_FORGET_ABOUT_LATEST_BREAKDOWN_AFTER_X_15M_CANDLES,
      DESIRED_ENTRYRANGE_RANGE_PERCENTSPOT,
      DESIRED_SECRET_TP_RANGE_PERCENT,
      DESIRED_TP_NOTSECRET_RANGE_PERCENT,
      DESIRED_CLOSETRADE_AFTER_SOME_TIME,
      DESIRED_CLOSETRADE_AFTER_SOME_TIME_BUT_PROFITPERCENT_NEEDED,
      DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN,
      DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TOTAL_TRADES_COUNT,
      DESIRED_BREAKDOWNTYPES,
      DESIRED_MAX_OPEN_POSITIONS
    ) do |min_len, max_len, bd_start_pct, min_total_pct, expiry_min, after_greenc, entry_min, forget_bd_candles, entryrange_pct, secret_tp, tp_notsecret, close_after_some_time, close_profit_pct_needed, close_after_min, stop_total_trades, bd_type, max_open|
      next if min_len > max_len

      mode = BREAKDOWN_TYPE_TO_MODE[bd_type]
      raise "Unknown breakdowntype #{bd_type.inspect}" unless mode

      combos << {
        min_breakdown_sequence_len: min_len,
        max_breakdown_sequence_len: max_len,
        bd_start_min_breakdown_percent: bd_start_pct,
        min_breakdown_total_percent: min_total_pct,
        expiry_minutes: expiry_min,
        after_bd_need_x_15greenc: after_greenc,
        entry_max_minutes_after_bdend: entry_min,
        forget_about_latest_breakdown_after_x_15m_candles: forget_bd_candles,
        entryrange_range_percentspot: entryrange_pct,
        secret_tp_range_percent: secret_tp,
        tp_notsecret_range_percent: tp_notsecret,
        closetrade_after_some_time: close_after_some_time,
        closetrade_after_some_time_but_ProfitPercent_Needed: close_profit_pct_needed,
        closetrade_after_x_minutes_from_breakdown: close_after_min,
        stop_trading_today_if_thisAlgo_total_trades_count: stop_total_trades,
        breakdown_streak_continuation_mode: mode,
        breakdowntype: bd_type,
        max_open_positions: max_open
      }
    end
    combos
  end

  def combination_dimension_counts
    valid_min_max_pairs = DESIRED_MIN_BREAKDOWN_SEQUENCE_LEN.product(DESIRED_MAX_BREAKDOWN_SEQUENCE_LEN)
      .count { |min_len, max_len| min_len <= max_len }

    {
      min_max_breakdown_sequence_len: valid_min_max_pairs,
      bd_start_min_breakdown_percent: DESIRED_BD_START_MIN_BREAKDOWN_PERCENT.size,
      min_breakdown_total_percent: DESIRED_MIN_BREAKDOWN_TOTAL_PERCENT.size,
      expiry_minutes: DESIRED_EXPIRY_MINUTES.size,
      after_bd_need_x_15greenc: DESIRED_AFTER_BD_NEED_X_15GREENC.size,
      entry_max_minutes_after_bdend: DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND.size,
      forget_about_latest_breakdown_after_x_15m_candles: DESIRED_FORGET_ABOUT_LATEST_BREAKDOWN_AFTER_X_15M_CANDLES.size,
      entryrange_range_percentspot: DESIRED_ENTRYRANGE_RANGE_PERCENTSPOT.size,
      secret_tp_range_percent: DESIRED_SECRET_TP_RANGE_PERCENT.size,
      tp_notsecret_range_percent: DESIRED_TP_NOTSECRET_RANGE_PERCENT.size,
      closetrade_after_some_time: DESIRED_CLOSETRADE_AFTER_SOME_TIME.size,
      closetrade_after_some_time_but_ProfitPercent_Needed: DESIRED_CLOSETRADE_AFTER_SOME_TIME_BUT_PROFITPERCENT_NEEDED.size,
      closetrade_after_x_minutes_from_breakdown: DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN.size,
      stop_trading_today_if_thisAlgo_total_trades_count: DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TOTAL_TRADES_COUNT.size,
      breakdowntypes: DESIRED_BREAKDOWNTYPES.size,
      max_open_positions: DESIRED_MAX_OPEN_POSITIONS.size
    }
  end

  def row_field_value(row, field)
    row[field.to_sym] || row[field]
  end

  def normalize_signature_value(value)
    s = value.to_s.strip
    case s.downcase
    when "true" then "true"
    when "false" then "false"
    else s
    end
  end

  def normalize_map_row(row)
    COMBINATION_MAP_FIELDS.each_with_object({}) do |field, normalized|
      normalized[field] = row_field_value(row, field).to_s
    end
  end

  def row_signature(row)
    COMBINATION_SIGNATURE_FIELDS
      .map { |field| normalize_signature_value(row_field_value(row, field)) }
      .join("\0")
  end

  def load_existing_combinations_map_csv(path)
    return [] unless File.exist?(path)

    table = CSV.read(path, headers: true)
    missing = COMBINATION_MAP_FIELDS - table.headers
    unless missing.empty?
      raise "Existing CSV missing columns: #{missing.join(', ')}"
    end

    table.map { |csv_row| normalize_map_row(csv_row) }
  end

  def merge_combinations_map_rows(existing_rows, generated_rows)
    tested_by_signature = {}
    existing_rows.each do |row|
      signature = row_signature(row)
      tested = normalize_signature_value(row_field_value(row, "tested?"))
      if tested == "true"
        tested_by_signature[signature] = "true"
      else
        tested_by_signature[signature] ||= "false"
      end
    end

    merged = []
    seen = {}
    matched_count = 0
    new_from_grid_count = 0
    preserved_tested_count = 0

    generated_rows.each do |row|
      signature = row_signature(row)
      next if seen[signature]

      out = normalize_map_row(row)
      if tested_by_signature.key?(signature)
        out["tested?"] = tested_by_signature[signature]
        matched_count += 1
        preserved_tested_count += 1 if tested_by_signature[signature] == "true"
      else
        out["tested?"] = "false"
        new_from_grid_count += 1
      end
      merged << out
      seen[signature] = true
    end

    orphans_added = 0
    existing_rows.each do |row|
      signature = row_signature(row)
      next if seen[signature]

      merged << normalize_map_row(row)
      seen[signature] = true
      orphans_added += 1
    end

    {
      rows: merged,
      matched_count: matched_count,
      new_from_grid_count: new_from_grid_count,
      orphans_added: orphans_added,
      preserved_tested_count: preserved_tested_count
    }
  end

  def combo_to_map_row(combo)
    secret_tp_enabled = combo[:secret_tp_range_percent] != 0

    {
      "tested?" => "false",
      enabled: "true",
      stop_trading_today_if_thisAlgo_losing_trades_count: 999,
      stop_trading_today_if_thisAlgo_winning_trades_count: 999,
      stop_trading_today_if_thisAlgo_total_trades_count: combo[:stop_trading_today_if_thisAlgo_total_trades_count],
      expiry_minutes: combo[:expiry_minutes],
      this_algo_max_concurrent_pending_trades: 1,
      min_breakdown_sequence_len: combo[:min_breakdown_sequence_len],
      max_breakdown_sequence_len: combo[:max_breakdown_sequence_len],
      breakdown_streak_continuation_mode: combo[:breakdown_streak_continuation_mode],
      breakdowntype: combo[:breakdowntype],
      bd_start_min_breakdown_percent: format_csv_double(combo[:bd_start_min_breakdown_percent]),
      min_breakdown_total_percent: format_csv_double(combo[:min_breakdown_total_percent]),
      after_bd_need_x_15greenc: combo[:after_bd_need_x_15greenc],
      entry_max_minutes_after_bdend: combo[:entry_max_minutes_after_bdend],
      forget_about_latest_breakdown_after_x_15m_candles: combo[:forget_about_latest_breakdown_after_x_15m_candles],
      entryrange_range_percentspot: format_csv_double(combo[:entryrange_range_percentspot]),
      secret_tp_enabled: format_csv_bool(secret_tp_enabled),
      secret_tp_range_percent: combo[:secret_tp_range_percent],
      secret_tp_greenguard_pricediff_at_least: format_csv_double(8.0),
      tp_enabled: "true",
      tp_notsecret_range_percent: combo[:tp_notsecret_range_percent],
      sl_enabled: "false",
      sl_points: format_csv_double(0.0),
      closetrade_after_some_time: format_csv_bool(combo[:closetrade_after_some_time]),
      closetrade_after_some_time_butOnlyIfProfit: "true",
      closetrade_after_some_time_but_ProfitPercent_Needed: format_csv_double(combo[:closetrade_after_some_time_but_ProfitPercent_Needed]),
      closetrade_after_x_minutes_from_breakdown: combo[:closetrade_after_x_minutes_from_breakdown],
      max_open_positions: combo[:max_open_positions]
    }
  end

  def write_combinations_map_csv!(path, rows)
    CSV.open(path, "w") do |csv|
      csv << COMBINATION_MAP_FIELDS
      rows.each do |row|
        normalized = normalize_map_row(row)
        csv << COMBINATION_MAP_FIELDS.map { |field| normalized[field] }
      end
    end

    rows.size
  end

  def write_merged_combinations_map_csv!(path, combinations)
    generated_rows = combinations.map { |combo| combo_to_map_row(combo) }
    existing_rows = load_existing_combinations_map_csv(path)
    merge_result = merge_combinations_map_rows(existing_rows, generated_rows)
    write_combinations_map_csv!(path, merge_result[:rows])
    merge_result
  end
end

include BreakdownCombinationsMap

if __FILE__ == $PROGRAM_NAME
  dimension_counts = combination_dimension_counts
  total_combinations = dimension_counts.values.reduce(1, :*)
  valid_min_max_pairs = dimension_counts[:min_max_breakdown_sequence_len]

  puts "Breakdown combination map count: #{total_combinations}"
  puts
  dimension_counts.each do |name, count|
    puts "  #{name}: #{count}"
  end
  puts
  puts "  (min_breakdown_sequence_len <= max_breakdown_sequence_len: #{valid_min_max_pairs} of #{DESIRED_MIN_BREAKDOWN_SEQUENCE_LEN.size * DESIRED_MAX_BREAKDOWN_SEQUENCE_LEN.size} pairs)"
  puts

  if total_combinations.zero?
    puts "No combinations to write."
    exit 0
  end

  combinations = build_combinations
  raise "Combination build mismatch: #{combinations.size} != #{total_combinations}" if combinations.size != total_combinations

  existing_count = File.exist?(OUT_CSV) ? load_existing_combinations_map_csv(OUT_CSV).size : 0
  if existing_count.positive?
    puts "Existing #{OUT_CSV}: #{existing_count} row(s) — will merge (preserve tested?, append new, skip dupes)."
  else
    puts "No existing #{OUT_CSV} — will create fresh (all tested?=false)."
  end
  puts

  print "Merge #{total_combinations} grid row(s) into #{OUT_CSV}? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  merge_result = write_merged_combinations_map_csv!(OUT_CSV, combinations)
  puts "Wrote #{merge_result[:rows].size} row(s) to #{OUT_CSV}"
  puts "  grid: #{total_combinations} (#{merge_result[:matched_count]} matched, #{merge_result[:new_from_grid_count]} new)"
  puts "  orphans kept from old file: #{merge_result[:orphans_added]}"
  puts "  tested?=true preserved on matches: #{merge_result[:preserved_tested_count]}"
  puts "Columns: #{COMBINATION_MAP_FIELDS.join(', ')}"
end
