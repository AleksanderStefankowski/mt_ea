#!/usr/bin/env ruby
# frozen_string_literal: true
# Read create_RESULTcatalogOUTPUT_time*.csv + INPUT_CATALOG_IDS heredoc -> append new time algos in aleksik2.mq5.
# Does not check for duplicate configs; each catalog id always gets a new mq5 algo id.

count_of_created_algos_limit = 1300

require "csv"
require_relative "smash_from_CATALOG_creator_common"
require_relative "smash_TIME_creator_common"

CATALOG_FAMILY = "time"
CATALOG_PREFIX = "T"
CATALOG_PATH = CatalogCreatorCommon.resolve_catalog_path(CATALOG_FAMILY)

# Edit catalog ids here (T1, T2, ...). Blank lines and # comments are ignored.
INPUT_CATALOG_IDS = <<~IDS
T5
IDS

module TimeCatalogCreator
  include CatalogCreatorCommon
  module_function

  def build_algo_params_block_from_catalog_row(algo_id, row)
    const = time_const(algo_id)
    slot = "TimeAlgoSlotIndexByAlgoId(#{const})"
    entry_label = entry_time_label(row["entry_hour"], row["entry_minute"])

    <<~MQL5.rstrip
      g_timeAlgos[#{slot}].enabled = #{csv_bool?(row["enabled"]) ? "true" : "false"};
      g_timeAlgos[#{slot}].entry_hour = #{row["entry_hour"].to_i};   // #{entry_label} catalog #{row[WITHIN_CATALOG_ID_COLUMN]}
      g_timeAlgos[#{slot}].entry_minute = #{row["entry_minute"].to_i};
      g_timeAlgos[#{slot}].rule_switch_map = #{row["rule_switch_map"].to_i};
      g_timeAlgos[#{slot}].secret_tp_profit_percent_min = #{format_mq5_double(row["secret_tp_profit_percent_min"])};
      g_timeAlgos[#{slot}].secret_tp_greenguard_pricediff_at_least = #{format_mq5_double(row["secret_tp_greenguard_pricediff_at_least"])};
      g_timeAlgos[#{slot}].max_trades_per_day = #{row["max_trades_per_day"].to_i};
      g_timeAlgos[#{slot}].max_open_positions = #{row["max_open_positions"].to_i};
      g_timeAlgos[#{slot}].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = #{row["stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count"].to_i};
    MQL5
  end

  def append_params_block_from_catalog_row(inner, algo_id, row)
    block = build_algo_params_block_from_catalog_row(algo_id, row)
    return inner if inner.include?("TimeAlgoSlotIndexByAlgoId(#{time_const(algo_id)})")

    inner.rstrip + "\n\n" + block
  end

  def apply_catalog_rows!(content, catalog_rows)
    existing_ids = registry_algo_ids(content)
    new_ids = next_algo_ids(existing_ids, catalog_rows.size, TIME_ALGO_ID_MIN, TIME_ALGO_ID_MAX)
    all_ids = (existing_ids + new_ids).uniq.sort
    required_registry_max = compute_registry_max_for_wired_count(all_ids.size)

    content = set_time_registry_max(content, required_registry_max) if required_registry_max > time_registry_max(content)

    inner1 = rebuild_registry_inner(all_ids)
    inner2 = extract_inner(content, 2)

    catalog_rows.zip(new_ids).each do |row, algo_id|
      inner2 = append_params_block_from_catalog_row(inner2, algo_id, row)
    end

    content = replace_inner(content, 1, inner1)
    replace_inner(content, 2, inner2)
  end
end

include TimeCombinationsCommon
include TimeCatalogCreator

if __FILE__ == $PROGRAM_NAME
  limit = count_of_created_algos_limit
  raise "count_of_created_algos_limit must be >= 1" if limit < 1

  catalog_ids = parse_catalog_ids(INPUT_CATALOG_IDS, CATALOG_PREFIX)
  if catalog_ids.empty?
    puts "ERROR: INPUT_CATALOG_IDS is empty (add catalog ids like T1 to the heredoc at top of script)"
    exit 1
  end

  rows_by_id = catalog_rows_by_id(CATALOG_PATH, CATALOG_PREFIX)
  selection = select_catalog_rows(catalog_ids, rows_by_id, limit)
  rows_to_create = selection[:rows]
  missing_catalog_ids = selection[:missing]

  unless missing_catalog_ids.empty?
    warn "ERROR: catalog id(s) not found in #{CATALOG_PATH}: #{missing_catalog_ids.join(', ')}"
    exit 1
  end

  puts "time catalog: #{CATALOG_PATH}"
  puts "Requested catalog ids:  #{catalog_ids.size}"
  puts "Create limit (top var): #{limit}"
  puts "Will create this run:   #{rows_to_create.size}"
  puts "Mode: APPEND (each catalog id gets a new mq5 algo id)"
  puts
  rows_to_create.each do |row|
    puts "  #{row[WITHIN_CATALOG_ID_COLUMN]}"
  end
  puts

  content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  registry_max = time_registry_max(content)
  registry_headroom = time_registry_max_headroom(content)
  wired_ids = registry_algo_ids(content)
  empty_slots = registry_max - wired_ids.size
  next_algo_id = wired_ids.empty? ? TIME_ALGO_ID_MIN : wired_ids.max + 1
  required_registry_max = compute_registry_max_for_wired_count(wired_ids.size + rows_to_create.size)

  puts "Registry slot capacity:   #{registry_max} (TIME_ALGO_REGISTRY_MAX in aleksik2.mq5)"
  puts "Registry headroom:        #{registry_headroom}"
  puts "Wired time algos:         #{wired_ids.size}"
  puts "Empty registry slots:     #{empty_slots}"
  puts "Required registry slots:  #{required_registry_max} (after creating #{rows_to_create.size})"
  puts "Next new algo ID:         #{next_algo_id}"
  if required_registry_max > registry_max
    puts "Will raise TIME_ALGO_REGISTRY_MAX: #{registry_max} -> #{required_registry_max}"
  end
  puts

  if rows_to_create.empty?
    puts "No catalog rows to create."
    exit 0
  end

  print "Create #{rows_to_create.size} time algo(s) from catalog in #{MQ5_FILE}? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  updated = apply_catalog_rows!(content, rows_to_create)
  File.write(MQ5_FILE, updated)

  new_ids = registry_algo_ids(updated).last(rows_to_create.size)
  final_registry_max = time_registry_max(updated)
  puts "Created #{rows_to_create.size} time algo(s):"
  rows_to_create.zip(new_ids).each do |row, algo_id|
    puts "  #{row[WITHIN_CATALOG_ID_COLUMN]} -> #{algo_id}"
  end
  puts "TIME_ALGO_REGISTRY_MAX: #{registry_max} -> #{final_registry_max}" if required_registry_max > registry_max
  puts MQ5_FILE
end
