#!/usr/bin/env ruby
# frozen_string_literal: true
# Read create_RESULTcatalogOUTPUT_breakdown.csv + INPUT_CATALOG_IDS heredoc -> new breakdown algos in aleksik2.mq5.
# Does not check for duplicate configs; each catalog id always gets a new mq5 algo id.

count_of_created_algos_limit = 1300

require "csv"
require_relative "smash_BREAKDOWN_creator_from_combinations"

CATALOG_PATH = File.expand_path(
  "../Aleksik_traderesults2_breakdown/create_RESULTcatalogOUTPUT_breakdown.csv",
  __dir__
)
WITHIN_CATALOG_ID_COLUMN = "within-catalog-id"
CATALOG_PERF_FIRST_COLUMN = "pattern"

# Edit catalog ids here (B1, B2, ...). Blank lines and # comments are ignored.
INPUT_CATALOG_IDS = <<~IDS
B7
B8
B9
B10
B11
B12
B13
IDS

module BreakdownCatalogCreator
  module_function

  def parse_catalog_ids(text)
    text.each_line.filter_map do |line|
      stripped = line.strip
      next if stripped.empty?
      next if stripped.start_with?("#")

      unless stripped.match?(/\AB\d+\z/i)
        raise "ERROR: invalid catalog id line: #{line.inspect} (expected B followed by digits, e.g. B7)"
      end

      "B#{stripped[/\d+/].to_i}"
    end.uniq
  end

  def normalize_catalog_row(row)
    row.to_h.transform_keys(&:to_s).transform_values { |value| value.to_s.strip }
  end

  def catalog_rows_by_id(path)
    raise "Missing breakdown catalog: #{path}" unless File.exist?(path)

    table = CSV.read(path, headers: true)
    unless table.headers.include?(WITHIN_CATALOG_ID_COLUMN)
      raise "#{File.basename(path)} missing column: #{WITHIN_CATALOG_ID_COLUMN}"
    end

    rows_by_id = {}
    table.each do |csv_row|
      row = normalize_catalog_row(csv_row)
      catalog_id = row[WITHIN_CATALOG_ID_COLUMN]
      next if catalog_id.empty?

      catalog_id = "B#{catalog_id[/\d+/].to_i}"
      rows_by_id[catalog_id] = row
    end
    rows_by_id
  end

  def csv_bool?(value)
    %w[true 1 yes].include?(value.to_s.strip.downcase)
  end

  def resolve_continuation_mode(value)
    text = value.to_s.strip
    return text if text.start_with?("BREAKDOWN_STREAK_CONTINUATION_")

    mode = BREAKDOWN_TYPE_TO_MODE[text]
    raise "Unknown breakdown_streak_continuation_mode #{text.inspect}" unless mode

    mode
  end

  def build_algo_params_block_from_catalog_row(algo_id, row)
    const = magic_const(algo_id)
    slot = "BreakdownAlgoSlotIndexByAlgoId(#{const})"
    mode = resolve_continuation_mode(row["breakdown_streak_continuation_mode"])

    <<~MQL5.rstrip

      g_breakdownAlgos[#{slot}].enabled = #{csv_bool?(row["enabled"]) ? "true" : "false"};
      g_breakdownAlgos[#{slot}].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
      g_breakdownAlgos[#{slot}].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
      g_breakdownAlgos[#{slot}].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = #{row["stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count"].to_i};
      g_breakdownAlgos[#{slot}].expiry_minutes = #{row["expiry_minutes"].to_i};
      g_breakdownAlgos[#{slot}].this_algo_max_concurrent_pending_trades = 1;
      g_breakdownAlgos[#{slot}].min_breakdown_sequence_len = #{row["min_breakdown_sequence_len"].to_i}; // catalog #{row[WITHIN_CATALOG_ID_COLUMN]}
      g_breakdownAlgos[#{slot}].max_breakdown_sequence_len = #{row["max_breakdown_sequence_len"].to_i};
      g_breakdownAlgos[#{slot}].breakdown_streak_continuation_mode = #{mode};
      g_breakdownAlgos[#{slot}].bd_start_min_breakdown_percent = #{format_mq5_double(row["bd_start_min_breakdown_percent"])};
      g_breakdownAlgos[#{slot}].min_breakdown_total_percent = #{format_mq5_double(row["min_breakdown_total_percent"])};
      g_breakdownAlgos[#{slot}].after_bd_need_x_15greenc = #{row["after_bd_need_x_15greenc"].to_i};
      g_breakdownAlgos[#{slot}].entry_max_minutes_after_bdend = #{row["entry_max_minutes_after_bdend"].to_i};
      g_breakdownAlgos[#{slot}].forget_about_latest_breakdown_after_x_15m_candles = #{row["forget_about_latest_breakdown_after_x_15m_candles"].to_i};
      g_breakdownAlgos[#{slot}].entryrange_range_percentspot = #{format_mq5_double(row["entryrange_range_percentspot"])};
      g_breakdownAlgos[#{slot}].secret_tp_range_percent = #{row["secret_tp_range_percent"].to_i};
      g_breakdownAlgos[#{slot}].secret_tp_greenguard_pricediff_at_least = 8.0;
      g_breakdownAlgos[#{slot}].tp_enabled = true;
      g_breakdownAlgos[#{slot}].tp_notsecret_range_percent = #{row["tp_notsecret_range_percent"].to_i};
      g_breakdownAlgos[#{slot}].sl_enabled = false;
      g_breakdownAlgos[#{slot}].sl_points = 0.0;
      g_breakdownAlgos[#{slot}].closetrade_after_some_time = #{row["closetrade_after_some_time"].downcase};
      g_breakdownAlgos[#{slot}].closetrade_after_some_time_butOnlyIfProfit = #{row["closetrade_after_some_time_butOnlyIfProfit"].downcase};
      g_breakdownAlgos[#{slot}].closetrade_after_some_time_but_ProfitPercent_Needed = #{format_mq5_double(row["closetrade_after_some_time_but_ProfitPercent_Needed"])};
      g_breakdownAlgos[#{slot}].closetrade_after_x_minutes_from_breakdown = #{row["closetrade_after_x_minutes_from_breakdown"].to_i};
      g_breakdownAlgos[#{slot}].max_open_positions = #{row["max_open_positions"].to_i};
    MQL5
  end

  def append_params_block_from_catalog_row(inner, algo_id, row)
    block = build_algo_params_block_from_catalog_row(algo_id, row)
    return inner if inner.include?("BreakdownAlgoSlotIndexByAlgoId(#{magic_const(algo_id)})")

    inner.rstrip + "\n\n" + block
  end

  def apply_catalog_rows!(content, catalog_rows)
    existing_ids = registry_algo_ids(content)
    new_ids = next_algo_ids(existing_ids, catalog_rows.size)
    all_ids = (existing_ids + new_ids).uniq.sort

    inner1 = rebuild_registry_inner(all_ids)
    inner2 = extract_inner(content, 2)
    inner4 = extract_inner(content, 4)

    catalog_rows.zip(new_ids).each do |row, algo_id|
      inner2 = append_params_block_from_catalog_row(inner2, algo_id, row)
      inner4 = append_rule_case(inner4, algo_id)
    end

    content = replace_inner(content, 1, inner1)
    content = replace_inner(content, 2, inner2)
    replace_inner(content, 4, inner4)
  end

  def select_catalog_rows(catalog_ids, rows_by_id, limit)
    selected = []
    missing = []

    catalog_ids.first(limit).each do |catalog_id|
      row = rows_by_id[catalog_id]
      if row.nil?
        missing << catalog_id
        next
      end

      selected << row.merge(WITHIN_CATALOG_ID_COLUMN => catalog_id)
    end

    { rows: selected, missing: missing }
  end
end

include BreakdownCombinationsCreator
include BreakdownCatalogCreator

if __FILE__ == $PROGRAM_NAME
  limit = count_of_created_algos_limit
  raise "count_of_created_algos_limit must be >= 1" if limit < 1

  catalog_ids = parse_catalog_ids(INPUT_CATALOG_IDS)
  if catalog_ids.empty?
    puts "ERROR: INPUT_CATALOG_IDS is empty (add catalog ids like B7 to the heredoc at top of script)"
    exit 1
  end

  rows_by_id = catalog_rows_by_id(CATALOG_PATH)
  selection = select_catalog_rows(catalog_ids, rows_by_id, limit)
  rows_to_create = selection[:rows]
  missing_catalog_ids = selection[:missing]

  unless missing_catalog_ids.empty?
    warn "ERROR: catalog id(s) not found in #{CATALOG_PATH}: #{missing_catalog_ids.join(', ')}"
    exit 1
  end

  puts "breakdown catalog: #{CATALOG_PATH}"
  puts "Requested catalog ids:  #{catalog_ids.size}"
  puts "Create limit (top var): #{limit}"
  puts "Will create this run:   #{rows_to_create.size}"
  puts
  rows_to_create.each do |row|
    puts "  #{row[WITHIN_CATALOG_ID_COLUMN]}"
  end
  puts

  content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
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
    puts "No catalog rows to create."
    exit 0
  end

  print "Create #{rows_to_create.size} breakdown algo(s) from catalog in #{MQ5_FILE}? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  content = set_breakdown_registry_max(content, required_registry_max) if required_registry_max > registry_max
  updated = apply_catalog_rows!(content, rows_to_create)
  File.write(MQ5_FILE, updated)

  new_ids = registry_algo_ids(updated).last(rows_to_create.size)
  final_registry_max = breakdown_registry_max(updated)
  puts "Created #{rows_to_create.size} breakdown algo(s):"
  rows_to_create.zip(new_ids).each do |row, algo_id|
    puts "  #{row[WITHIN_CATALOG_ID_COLUMN]} -> #{algo_id}"
  end
  puts "BREAKDOWN_ALGO_REGISTRY_MAX: #{registry_max} -> #{final_registry_max}" if required_registry_max > registry_max
  puts MQ5_FILE
end
