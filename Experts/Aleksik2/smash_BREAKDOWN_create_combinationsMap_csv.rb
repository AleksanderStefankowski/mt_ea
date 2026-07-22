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

COMBINATION_SIGNATURE_FIELDS = (COMBINATION_MAP_FIELDS - ["tested?"]).freeze

# --- edit combination grids here ---
DESIRED_EXPIRY_MINUTES = [45].freeze # 15  [15, 45] # obviously longer expiry means more trades fill. can test 30 45 60 90
# compare variable: expiry_minutes
# algos in analyze_breakdown_algos_performance_output: 425
# algos without a pair: 41 (9.6% of all)
# groups found: 192
# pairs found: 192
# unpaired groups written: 41
# perf_timeVSprofit higher in head-to-head pairs:
#   expiry_minutes=15: 25/192 (13.0%), avg perf_timeVSprofit=0.048 (per algo)
#   expiry_minutes=45: 141/192 (73.4%), avg perf_timeVSprofit=0.052 (per algo)
#   perf_timeVSprofit: expiry_minutes=45 (0.052) is 8.0% better than expiry_minutes=15 (0.048)
# perf_percentSum_w_roll higher in head-to-head pairs:
#   expiry_minutes=15: 0/192 (0.0%), avg perf_percentSum_w_roll=52.53 (per algo)
#   expiry_minutes=45: 192/192 (100.0%), avg perf_percentSum_w_roll=62.92 (per algo)
#   perf_percentSum_w_roll: expiry_minutes=45 (62.92) is 19.8% better than expiry_minutes=15 (52.53)    <===========
# perf_avgDurationHours higher in head-to-head pairs:
#   expiry_minutes=15: 163/192 (84.9%), avg perf_avgDurationHours=253.211 (per algo)
#   expiry_minutes=45: 27/192 (14.1%), avg perf_avgDurationHours=236.500 (per algo)
#   perf_avgDurationHours: expiry_minutes=15 (253.211) is 7.1% better than expiry_minutes=45 (236.500)
# perf_tradesCount higher in head-to-head pairs:
#   expiry_minutes=15: 0/192 (0.0%), avg perf_tradesCount=58.92 (per algo)
#   expiry_minutes=45: 192/192 (100.0%), avg perf_tradesCount=71.58 (per algo)
#   perf_tradesCount: expiry_minutes=45 (71.58) is 21.5% better than expiry_minutes=15 (58.92)

DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT = [3].freeze # 3 # TESTED ALREADY  [3 6] is no diff. maybe test 1, 2, 3, but it is low prio
# TESTED ALREADY
# TESTED ALREADY
# TESTED ALREADY

DESIRED_CLOSETRADE_AFTER_SOME_TIME = [false].freeze
DESIRED_CLOSETRADE_AFTER_SOME_TIME_BUT_PROFITPERCENT_NEEDED = [2.0].freeze # 0.2 0.4 0.7 1.0 1.5 2.0
DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN = [90].freeze

DESIRED_MIN_BREAKDOWN_SEQUENCE_LEN = [3].freeze # 3  # [3, 4, 6, 8] the less, the more trades the more profit (of course limt 10 orders). can test 2 3 4 later 
# compare variable: min_breakdown_sequence_len
# algos in analyze_breakdown_algos_performance_output: 425
# algos without a pair: 29 (6.8% of all)
# groups found: 156
# pairs found: 324
# unpaired groups written: 29
# perf_timeVSprofit higher in head-to-head pairs:
#   min_breakdown_sequence_len=3: 60/240 (25.0%), avg perf_timeVSprofit=0.045 (per algo)
#   min_breakdown_sequence_len=4: 98/240 (40.8%), avg perf_timeVSprofit=0.046 (per algo)
#   min_breakdown_sequence_len=6: 148/168 (88.1%), avg perf_timeVSprofit=0.070 (per algo)
#   perf_timeVSprofit: min_breakdown_sequence_len=4 (0.046) is 1.8% better than min_breakdown_sequence_len=3 (0.045)
#   perf_timeVSprofit: min_breakdown_sequence_len=6 (0.070) is 53.7% better than min_breakdown_sequence_len=3 (0.045)
#   perf_timeVSprofit: min_breakdown_sequence_len=6 (0.070) is 51.0% better than min_breakdown_sequence_len=4 (0.046)
# perf_percentSum_w_roll higher in head-to-head pairs:
#   min_breakdown_sequence_len=3: 218/240 (90.8%), avg perf_percentSum_w_roll=69.03 (per algo)
#   min_breakdown_sequence_len=4: 106/240 (44.2%), avg perf_percentSum_w_roll=56.68 (per algo)
#   min_breakdown_sequence_len=6: 0/168 (0.0%), avg perf_percentSum_w_roll=37.29 (per algo)
#   perf_percentSum_w_roll: min_breakdown_sequence_len=3 (69.03) is 21.8% better than min_breakdown_sequence_len=4 (56.68)
#   perf_percentSum_w_roll: min_breakdown_sequence_len=3 (69.03) is 85.1% better than min_breakdown_sequence_len=6 (37.29)
#   perf_percentSum_w_roll: min_breakdown_sequence_len=4 (56.68) is 52.0% better than min_breakdown_sequence_len=6 (37.29)
# perf_avgDurationHours higher in head-to-head pairs:
#   min_breakdown_sequence_len=3: 128/240 (53.3%), avg perf_avgDurationHours=246.340 (per algo)
#   min_breakdown_sequence_len=4: 148/240 (61.7%), avg perf_avgDurationHours=254.567 (per algo)
#   min_breakdown_sequence_len=6: 48/168 (28.6%), avg perf_avgDurationHours=215.002 (per algo)
#   perf_avgDurationHours: min_breakdown_sequence_len=4 (254.567) is 3.3% better than min_breakdown_sequence_len=3 (246.340)
#   perf_avgDurationHours: min_breakdown_sequence_len=3 (246.340) is 14.6% better than min_breakdown_sequence_len=6 (215.002)
#   perf_avgDurationHours: min_breakdown_sequence_len=4 (254.567) is 18.4% better than min_breakdown_sequence_len=6 (215.002)
# perf_tradesCount higher in head-to-head pairs:
#   min_breakdown_sequence_len=3: 240/240 (100.0%), avg perf_tradesCount=84.53 (per algo)
#   min_breakdown_sequence_len=4: 84/240 (35.0%), avg perf_tradesCount=60.86 (per algo)
#   min_breakdown_sequence_len=6: 0/168 (0.0%), avg perf_tradesCount=35.14 (per algo)
#   perf_tradesCount: min_breakdown_sequence_len=3 (84.53) is 38.9% better than min_breakdown_sequence_len=4 (60.86)
#   perf_tradesCount: min_breakdown_sequence_len=3 (84.53) is 140.5% better than min_breakdown_sequence_len=6 (35.14)
#   perf_tradesCount: min_breakdown_sequence_len=4 (60.86) is 73.2% better than min_breakdown_sequence_len=6 (35.14)


DESIRED_MAX_BREAKDOWN_SEQUENCE_LEN = [9].freeze # 9 [9]

DESIRED_BD_START_MIN_BREAKDOWN_PERCENT = [0.20, 0.35, 0.15].freeze # 0.20  [0.20, 0.35]
DESIRED_MIN_BREAKDOWN_TOTAL_PERCENT = [0.60].freeze  #  [0.40, 0.60, 0.85, 1.50]

DESIRED_AFTER_BD_NEED_X_15GREENC = [1].freeze #  [1, 2, 3] # Aleksik2_traderesults2_variable_comparisons shows 1 is much better due to more trades

ENTRY_FORGET_MIN_ROOM_MINUTES = 15 # match aleksik2.mq5 BREAKDOWN_ENTRY_FORGET_MIN_ROOM_MINUTES
SKIP_INVALIDCOMBOS_OF_FORGETBD_VS_ENTRY_MAX_MINUTES = true # if false, error and dont create any. if true, only skip invalid combos
DESIRED_FORGET_ABOUT_LATEST_BREAKDOWN_AFTER_X_15M_CANDLES = [6, 11, 14].freeze # 6 [6, 9]
DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND = [75, 50, 110].freeze # 75


DESIRED_ENTRYRANGE_RANGE_PERCENTSPOT = [75, 90].freeze #  66  [20, 66, 75].    [20, 33, 50, 66, 75], the higher the better. test 90. 99 rarely trades obvously as too hard to fill. 
# 90 has more trades as it is close enough to fill more often?
# bez duzej roznicy, to na razie usune 33, 55
# perf_percentSum_w_roll higher in head-to-head pairs:
#   entryrange_range_percentspot=20.00: 6/80 (7.5%), avg perf_percentSum_w_roll=26.46 (per algo)
#   entryrange_range_percentspot=33.00: 31/92 (33.7%), avg perf_percentSum_w_roll=28.73 (per algo)
#   entryrange_range_percentspot=50.00: 47/124 (37.9%), avg perf_percentSum_w_roll=25.69 (per algo)
#   entryrange_range_percentspot=66.00: 87/124 (70.2%), avg perf_percentSum_w_roll=35.21 (per algo)
#   entryrange_range_percentspot=75.00: 101/124 (81.5%), avg perf_percentSum_w_roll=36.34 (per algo)
# perf_percentSum_w_roll higher in head-to-head pairs:
#   entryrange_range_percentspot=20.00: 20/216 (9.3%), avg perf_percentSum_w_roll=37.30 (per algo)
#   entryrange_range_percentspot=66.00: 208/264 (78.8%), avg perf_percentSum_w_roll=63.00 (per algo)
#   entryrange_range_percentspot=75.00: 142/264 (53.8%), avg perf_percentSum_w_roll=60.80 (per algo)


DESIRED_SECRET_TP_RANGE_PERCENT = [0, 75].freeze # 45 mialo najslabszy result w big run, na razie usuwam. usuwam tez 20 ale mozna retest

DESIRED_TP_NOTSECRET_RANGE_PERCENT = [110, 150].freeze # 150
# perf_percentSum_w_roll group 0 secret TP higher in head-to-head pairs:
#   tp_notsecret_range_percent=110: 24/30 (80.0%), avg perf_percentSum_w_roll group 0 secret TP=57.45 (per algo)
#   tp_notsecret_range_percent=150: 6/30 (20.0%), avg perf_percentSum_w_roll group 0 secret TP=29.45 (per algo)
#   perf_percentSum_w_roll group 0 secret TP: tp_notsecret_range_percent=110 (57.45) is 95.1% better than tp_notsecret_range_percent=150 (29.45)

# perf_percentSum_w_roll group non 0 secret TP higher in head-to-head pairs:
#   tp_notsecret_range_percent=110: 15/20 (75.0%), avg perf_percentSum_w_roll group non 0 secret TP=60.34 (per algo)
#   tp_notsecret_range_percent=150: 5/20 (25.0%), avg perf_percentSum_w_roll group non 0 secret TP=32.41 (per algo)
#   perf_percentSum_w_roll group non 0 secret TP: tp_notsecret_range_percent=110 (60.34) is 86.2% better than tp_notsecret_range_percent=150 (32.41)


DESIRED_MAX_OPEN_POSITIONS = [10].freeze # 10 also test 5
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

  def entry_forget_invalid_reason(entry_max, forget_candles)
    forget = forget_candles.to_i
    entry = entry_max.to_i
    if forget <= 0
      return "forget_about_latest_breakdown_after_x_15m_candles must be >= 1 (got #{forget_candles})"
    end

    forget_min = forget * 15
    room_min = forget_min - entry
    if room_min < ENTRY_FORGET_MIN_ROOM_MINUTES
      return "forget #{forget}x15m=#{forget_min} min needs >= #{ENTRY_FORGET_MIN_ROOM_MINUTES} min room before entry_max=#{entry} (room=#{room_min})"
    end

    nil
  end

  def entry_forget_combo_valid?(entry_max, forget_candles)
    entry_forget_invalid_reason(entry_max, forget_candles).nil?
  end

  def invalid_entry_forget_pairs(entry_values = DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND,
    forget_values = DESIRED_FORGET_ABOUT_LATEST_BREAKDOWN_AFTER_X_15M_CANDLES)
    entry_values.product(forget_values).filter_map do |entry_max, forget_candles|
      reason = entry_forget_invalid_reason(entry_max, forget_candles)
      next unless reason

      { entry_max: entry_max, forget_candles: forget_candles, reason: reason }
    end
  end

  def entry_forget_pair_count(entry_values = DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND,
    forget_values = DESIRED_FORGET_ABOUT_LATEST_BREAKDOWN_AFTER_X_15M_CANDLES)
    entry_values.product(forget_values).count do |entry_max, forget_candles|
      entry_forget_combo_valid?(entry_max, forget_candles)
    end
  end

  def validate_entry_forget_desired_grid!
    invalid_pairs = invalid_entry_forget_pairs
    return if invalid_pairs.empty?

    lines = invalid_pairs.map do |pair|
      "  entry_max=#{pair[:entry_max]}, forget=#{pair[:forget_candles]}x15m: #{pair[:reason]}"
    end

    if SKIP_INVALIDCOMBOS_OF_FORGETBD_VS_ENTRY_MAX_MINUTES
      warn "WARNING: skipping #{invalid_pairs.size} invalid entry_max/forget pair(s) from desired grid:"
      lines.each { |line| warn line }
      warn
      return
    end

    $stderr.puts "ERROR: invalid entry_max vs forget combinations in desired grid (#{invalid_pairs.size} pair(s)):"
    lines.each { |line| $stderr.puts line }
    $stderr.puts
    $stderr.puts "Set SKIP_INVALIDCOMBOS_OF_FORGETBD_VS_ENTRY_MAX_MINUTES = true to skip only invalid pairs, or fix DESIRED_* arrays."
    exit 1
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
      DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT,
      DESIRED_BREAKDOWNTYPES,
      DESIRED_MAX_OPEN_POSITIONS
    ) do |min_len, max_len, bd_start_pct, min_total_pct, expiry_min, after_greenc, entry_min, forget_bd_candles, entryrange_pct, secret_tp, tp_notsecret, close_after_some_time, close_profit_pct_needed, close_after_min, stop_total_trades, bd_type, max_open|
      next if min_len > max_len
      next unless entry_forget_combo_valid?(entry_min, forget_bd_candles)

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
        stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count: stop_total_trades,
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
      entry_max_forget_pairs: entry_forget_pair_count,
      entryrange_range_percentspot: DESIRED_ENTRYRANGE_RANGE_PERCENTSPOT.size,
      secret_tp_range_percent: DESIRED_SECRET_TP_RANGE_PERCENT.size,
      tp_notsecret_range_percent: DESIRED_TP_NOTSECRET_RANGE_PERCENT.size,
      closetrade_after_some_time: DESIRED_CLOSETRADE_AFTER_SOME_TIME.size,
      closetrade_after_some_time_but_ProfitPercent_Needed: DESIRED_CLOSETRADE_AFTER_SOME_TIME_BUT_PROFITPERCENT_NEEDED.size,
      closetrade_after_x_minutes_from_breakdown: DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN.size,
      stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count: DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT.size,
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
    {
      "tested?" => "false",
      enabled: "true",
      stop_trading_today_if_thisAlgo_losing_trades_count: 999,
      stop_trading_today_if_thisAlgo_winning_trades_count: 999,
      stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count: combo[:stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count],
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
  validate_entry_forget_desired_grid!

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
