#!/usr/bin/env ruby
# frozen_string_literal: true
# Read create_RESULTcatalogOUTPUT_level*.csv + INPUT_CATALOG_IDS heredoc -> append new level algos in aleksik2.mq5 + aleksik2_level_fam.mqh.
# Does not check for duplicate configs; each catalog id always gets a new mq5 algo id.

count_of_created_algos_limit = 1300

require "csv"
require_relative "smash_from_CATALOG_creator_common"
require_relative "smash_LEVEL_create_From_combinations"

CATALOG_FAMILY = "level"
CATALOG_PREFIX = "L"
CATALOG_PATH = CatalogCreatorCommon.resolve_catalog_path(CATALOG_FAMILY)

# Edit catalog ids here (L1, L2, ...). Blank lines and # comments are ignored.
INPUT_CATALOG_IDS = <<~IDS
L211
IDS

module LevelCatalogCreator
  include CatalogCreatorCommon
  module_function

  def trades_scope_from_catalog(value)
    case value.to_s.strip.downcase
    when "both" then :both
    when "weekly" then :weekly
    when "daily" then :daily
    else
      raise "Unknown trades_what_levels #{value.inspect}"
    end
  end

  def trades_tags_preset_from_catalog(value)
    preset = value.to_s.strip.downcase
    sym = preset.to_sym
    raise "Unknown trades_tags_preset #{value.inspect}" unless TRADES_TAGS_BY_PRESET.key?(sym)

    sym
  end

  def build_algo_params_block_from_catalog_row(algo_id, row)
    const = level_magic_const(algo_id)
    slot = "LevelAlgoSlotIndexByAlgoId(#{const})"
    scope = trades_scope_for(trades_scope_from_catalog(row["trades_what_levels"]))
    tags_preset = trades_tags_preset_from_catalog(row["trades_tags_preset"])
    tags = TRADES_TAGS_BY_PRESET.fetch(tags_preset)

    lines = []
    lines << "g_levelAlgos[#{slot}].enabled = true; // catalog #{row[WITHIN_CATALOG_ID_COLUMN]}"
    lines << "g_levelAlgos[#{slot}].trades_weekly = #{format_mq5_bool(scope[:trades_weekly])};"
    lines << "g_levelAlgos[#{slot}].trades_daily = #{format_mq5_bool(scope[:trades_daily])};"
    lines << "g_levelAlgos[#{slot}].stop_trading_today_if_thisAlgo_losing_trades_count = 999;"
    lines << "g_levelAlgos[#{slot}].stop_trading_today_if_thisAlgo_winning_trades_count = 999;"
    lines << "g_levelAlgos[#{slot}].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = #{row["stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count"].to_i};"
    lines << "g_levelAlgos[#{slot}].expiry_minutes = #{row["expiry_minutes"].to_i};"
    lines << "g_levelAlgos[#{slot}].this_algo_max_concurrent_pending_trades = 1;"
    lines << "g_levelAlgos[#{slot}].max_open_positions = #{row["max_open_positions"].to_i};"
    lines << "g_levelAlgos[#{slot}].secret_tp_profit_percent_min = #{format_mq5_double(row["secret_tp_profit_percent_min"])};"
    lines << "g_levelAlgos[#{slot}].secret_tp_greenguard_pricediff_at_least = 20.0;"
    lines << "g_levelAlgos[#{slot}].level_needs_to_be_below_ONO = #{row["level_needs_to_be_below_ONO"].downcase};"
    lines << "g_levelAlgos[#{slot}].offset_positive = #{row["offset_positive"].downcase};"
    lines << "g_levelAlgos[#{slot}].offset_percentage = #{format_mq5_double(row["offset_percentage"], 4)};"
    lines << "g_levelAlgos[#{slot}].cannotTrade__when_levelProximity_multiplyOffset = #{format_mq5_double(row["cannotTrade__when_levelProximity_multiplyOffset"], 2)};"
    lines << "g_levelAlgos[#{slot}].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;"
    lines << build_trades_tags_lines(slot, tags)
    lines << "g_levelAlgos[#{slot}].real_tp = 499.0;"
    lines << "g_levelAlgos[#{slot}].rule_switch_map = 0;"
    lines.join("\n")
  end

  def append_params_block_from_catalog_row(inner, algo_id, row)
    block = build_algo_params_block_from_catalog_row(algo_id, row)
    return inner if inner.include?("LevelAlgoSlotIndexByAlgoId(#{level_magic_const(algo_id)})")

    inner.rstrip + "\n\n" + block
  end

  def apply_catalog_rows!(mq5_content, level_fam_content, catalog_rows)
    existing_ids = registry_algo_ids(mq5_content)
    new_ids = next_algo_ids(existing_ids, catalog_rows.size, LEVEL_ALGO_ID_MIN, LEVEL_ALGO_ID_MAX)
    all_ids = (existing_ids + new_ids).uniq.sort
    required_registry_max = all_ids.size

    if required_registry_max > level_registry_max(mq5_content)
      mq5_content = set_level_registry_max(mq5_content, required_registry_max)
    end
    mq5_content = replace_magic_level_defines(mq5_content, all_ids)
    mq5_content = replace_inner(mq5_content, MQ5_MARKERS[1], rebuild_registry_inner(all_ids))

    inner2 = extract_inner(level_fam_content, LEVEL_FAM_MARKERS[2])
    catalog_rows.zip(new_ids).each do |row, algo_id|
      inner2 = append_params_block_from_catalog_row(inner2, algo_id, row)
    end
    level_fam_content = replace_inner(level_fam_content, LEVEL_FAM_MARKERS[2], inner2)

    [mq5_content, level_fam_content]
  end
end

include LevelCombinationsCreator
include LevelCatalogCreator

if __FILE__ == $PROGRAM_NAME
  limit = count_of_created_algos_limit
  raise "count_of_created_algos_limit must be >= 1" if limit < 1

  catalog_ids = parse_catalog_ids(INPUT_CATALOG_IDS, CATALOG_PREFIX)
  if catalog_ids.empty?
    puts "ERROR: INPUT_CATALOG_IDS is empty (add catalog ids like L1 to the heredoc at top of script)"
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

  puts "level catalog: #{CATALOG_PATH}"
  puts "Requested catalog ids:  #{catalog_ids.size}"
  puts "Create limit (top var): #{limit}"
  puts "Will create this run:   #{rows_to_create.size}"
  puts "Mode: APPEND (each catalog id gets a new mq5 algo id)"
  puts
  rows_to_create.each do |row|
    puts "  #{row[WITHIN_CATALOG_ID_COLUMN]}"
  end
  puts

  mq5_content = File.read(MQ5_FILE, encoding: "bom|utf-8")
  level_fam_content = File.read(LEVEL_FAM_FILE, encoding: "bom|utf-8")
  registry_max = level_registry_max(mq5_content)
  registry_headroom = level_registry_max_headroom(mq5_content)
  wired_ids = registry_algo_ids(mq5_content)
  empty_slots = registry_max - wired_ids.size
  next_algo_id = wired_ids.empty? ? LEVEL_ALGO_ID_MIN : wired_ids.max + 1
  required_registry_max = wired_ids.size + rows_to_create.size

  puts "Registry slot capacity:   #{registry_max} (LEVEL_ALGO_REGISTRY_MAX in aleksik2.mq5)"
  puts "Registry headroom:        #{registry_headroom}"
  puts "Wired level algos:        #{wired_ids.size}"
  puts "Empty registry slots:     #{empty_slots}"
  puts "Required registry slots:  #{required_registry_max} (after creating #{rows_to_create.size})"
  puts "Next new algo ID:         #{next_algo_id}"
  if required_registry_max > registry_max
    puts "Will raise LEVEL_ALGO_REGISTRY_MAX: #{registry_max} -> #{required_registry_max}"
  end
  puts

  if rows_to_create.empty?
    puts "No catalog rows to create."
    exit 0
  end

  print "Create #{rows_to_create.size} level algo(s) from catalog in #{MQ5_FILE} + #{LEVEL_FAM_FILE}? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  updated_mq5, updated_level_fam = apply_catalog_rows!(mq5_content, level_fam_content, rows_to_create)
  File.write(MQ5_FILE, updated_mq5)
  File.write(LEVEL_FAM_FILE, updated_level_fam)

  new_ids = registry_algo_ids(updated_mq5).last(rows_to_create.size)
  final_registry_max = level_registry_max(updated_mq5)
  puts "Created #{rows_to_create.size} level algo(s):"
  rows_to_create.zip(new_ids).each do |row, algo_id|
    puts "  #{row[WITHIN_CATALOG_ID_COLUMN]} -> #{algo_id}"
  end
  puts "LEVEL_ALGO_REGISTRY_MAX: #{registry_max} -> #{final_registry_max}" if required_registry_max > registry_max
  puts MQ5_FILE
  puts LEVEL_FAM_FILE
end
