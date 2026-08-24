#!/usr/bin/env ruby
# frozen_string_literal: true
# Set .enabled for specific breakdown / time / level algo IDs from one mixed list.
#
# Breakdown + time: aleksik2.mq5 (//breakdowncreator1*, //timealgocreator1*)
# Level: registry in aleksik2.mq5 (//levelalgocreator1*), .enabled in aleksik2_level_fam.mqh
#
# Family is inferred from algo id range:
#   10000000..19999999 => time
#   20000000..29999999 => breakdown
#   30000000..39999999 => level
#
# Whitelist (target :enabled): enable listed algos, disable all other wired algos in that family.
# Blacklist (target :disabled): disable listed algos only; leave all others unchanged.
# Whitelist with an empty per-family list: disable every algo in that edited family.

require_relative "smash_BREAKDOWN_creator_from_combinations"

EDIT_BD_ALGOS = true
EDIT_TIME_ALGOS = true
EDIT_LEVEL_ALGOS = true
TARGET_STATE_FOR_ALL_EDITED_ALGOS = :enabled # :enabled or :disabled

# Family is inferred from algo id (see ranges above).
SET_STATE_FOR_ALL_ALGOS_LIST = <<~IDS
10000001
30000082
20001094
20001232
IDS
# 10000023
# 20001094
# 30000133
# 1 is time
# 2 is bd
# 3 is level

BD_REGISTRY_MARKERS = %w[//breakdowncreator1start //breakdowncreator1end].freeze
BD_REGISTRY_ID_RE = /MAGIC_BREAKDOWN(\d+)/

TIME_REGISTRY_MARKERS = %w[//timealgocreator1start //timealgocreator1end].freeze
TIME_REGISTRY_ID_RE = /TIME_ALGO_(\d+)/

LEVEL_REGISTRY_MARKERS = %w[//levelalgocreator1start //levelalgocreator1end].freeze
LEVEL_REGISTRY_ID_RE = /MAGIC_LEVEL(\d+)/

LEVEL_FAM_FILE = File.expand_path("aleksik2_level_fam.mqh", __dir__)

BD_ENABLED_LINE_RE = /
  g_breakdownAlgos\[BreakdownAlgoSlotIndexByAlgoId\(MAGIC_BREAKDOWN(\d+)\)\]\.enabled\s*=\s*(true|false);
/x

TIME_ENABLED_LINE_RE = /
  g_timeAlgos\[TimeAlgoSlotIndexByAlgoId\(TIME_ALGO_(\d+)\)\]\.enabled\s*=\s*(true|false);
/x

LEVEL_ENABLED_LINE_RE = /
  g_levelAlgos\[LevelAlgoSlotIndexByAlgoId\(MAGIC_LEVEL(\d+)\)\]\.enabled\s*=\s*(true|false);
/x

module DisableEnableByAlgoId
  module_function

  FAMILY_BREAKDOWN = :breakdown
  FAMILY_TIME = :time
  FAMILY_LEVEL = :level

  def family_for_algo_id(algo_id)
    id = Integer(algo_id)
    return FAMILY_TIME if id >= 10_000_000 && id < 20_000_000
    return FAMILY_BREAKDOWN if id >= 20_000_000 && id < 30_000_000
    return FAMILY_LEVEL if id >= 30_000_000 && id < 40_000_000

    nil
  rescue ArgumentError, TypeError
    nil
  end

  def group_algo_ids_by_family(algo_ids)
    grouped = {
      FAMILY_BREAKDOWN => [],
      FAMILY_TIME => [],
      FAMILY_LEVEL => []
    }
    unknown = []

    algo_ids.each do |algo_id|
      family = family_for_algo_id(algo_id)
      if family.nil?
        unknown << algo_id
        next
      end

      grouped[family] << algo_id
    end

    grouped.each_value(&:uniq!)
    grouped.each_value(&:sort!)
    [grouped, unknown]
  end

  def family_edit_enabled?(family)
    case family
    when FAMILY_BREAKDOWN then EDIT_BD_ALGOS
    when FAMILY_TIME then EDIT_TIME_ALGOS
    when FAMILY_LEVEL then EDIT_LEVEL_ALGOS
    else
      false
    end
  end

  def partition_list_for_edited_families(all_list_ids)
    grouped, unknown = group_algo_ids_by_family(all_list_ids)
    raise ArgumentError, "Unknown algo id range(s): #{unknown.join(', ')}" unless unknown.empty?

    skipped = []
    selected = grouped.transform_values(&:dup)

    grouped.each do |family, ids|
      next if family_edit_enabled?(family)

      skipped.concat(ids)
      selected[family] = []
    end

    [selected, skipped.sort]
  end

  def parse_target_state(value, label)
    case value.to_s.strip.downcase.to_sym
    when :enabled, :enable, :true
      true
    when :disabled, :disable, :false
      false
    else
      raise ArgumentError, "#{label} must be :enabled or :disabled (got #{value.inspect})"
    end
  end

  def parse_algo_id_list(text, label, allow_empty: false)
    ids =
      text.each_line.filter_map do |line|
        stripped = line.strip
        next if stripped.empty?
        next if stripped.start_with?("#")

        raise ArgumentError, "Invalid algo id line: #{line.inspect}" unless stripped.match?(/\A\d+\z/)

        stripped.to_i
      end.uniq.sort

    if ids.empty? && !allow_empty
      raise ArgumentError, "#{label} is empty"
    end

    ids
  end

  def registry_algo_ids(content, markers, id_re)
    start_marker, end_marker = markers
    marker_line_re = ->(marker) { /^\s*#{Regexp.escape(marker)}\s*$/ }

    lines = content.lines
    start_idx = lines.index { |line| line.match?(marker_line_re.call(start_marker)) }
    end_idx = lines.index { |line| line.match?(marker_line_re.call(end_marker)) }
    unless start_idx && end_idx && end_idx > start_idx
      raise "Could not find registry block (#{start_marker} .. #{end_marker})"
    end

    lines[(start_idx + 1)...end_idx].join.scan(id_re).flatten.map(&:to_i).uniq.sort
  end

  def build_enable_plan(all_ids, list_ids, target_enabled:)
    unknown = list_ids - all_ids
    unless unknown.empty?
      raise ArgumentError, "Unknown algo id(s) not in registry: #{unknown.join(', ')}"
    end

    if target_enabled
      all_ids.to_h { |id| [id, list_ids.include?(id)] }
    else
      list_ids.to_h { |id| false }
    end
  end

  def breakdown_enabled_line_re(algo_id)
    /g_breakdownAlgos\[BreakdownAlgoSlotIndexByAlgoId\(MAGIC_BREAKDOWN#{algo_id}\)\]\.enabled\s*=\s*(true|false);/
  end

  def time_enabled_line_re(algo_id)
    /g_timeAlgos\[TimeAlgoSlotIndexByAlgoId\(TIME_ALGO_#{algo_id}\)\]\.enabled\s*=\s*(true|false);/
  end

  def level_enabled_line_re(algo_id)
    /g_levelAlgos\[LevelAlgoSlotIndexByAlgoId\(MAGIC_LEVEL#{algo_id}\)\]\.enabled\s*=\s*(true|false);/
  end

  def apply_enable_plan!(content, line_re, plan)
    changed = []
    skipped = []

    updated = content.gsub(line_re) do |match|
      algo_id = Regexp.last_match(1).to_i
      next match unless plan.key?(algo_id)

      target = plan[algo_id] ? "true" : "false"
      current = Regexp.last_match(2)

      if current == target
        skipped << algo_id
        next match
      end

      changed << algo_id
      match.sub(/=\s*(true|false);/, "= #{target};")
    end

    [updated, changed.sort, skipped.sort]
  end

  def summarize_plan(family_label, all_ids, list_ids, target_enabled, plan)
    enable_ids = plan.select { |_id, enabled| enabled }.keys.sort
    disable_ids = plan.select { |_id, enabled| !enabled }.keys.sort

    puts "#{family_label}:"
    puts "  Wired algos:              #{all_ids.size}"
    puts "  List algo ids:            #{list_ids.empty? ? '(empty)' : list_ids.join(', ')}"
    puts "  Target for listed algos:  #{target_enabled ? 'enabled' : 'disabled'}"
    if target_enabled
      puts "  Mode:                     whitelist (enable listed, disable others)"
      puts "  Will enable:              #{enable_ids.empty? ? '(none)' : enable_ids.join(', ')}"
      puts "  Will disable:             #{disable_ids.empty? ? '(none)' : "#{disable_ids.size} algo(s)"}"
    else
      puts "  Mode:                     blacklist (disable listed only)"
      puts "  Will disable:             #{disable_ids.empty? ? '(none)' : disable_ids.join(', ')}"
    end
    puts
  end
end

include DisableEnableByAlgoId

if __FILE__ == $PROGRAM_NAME
  unless EDIT_BD_ALGOS || EDIT_TIME_ALGOS || EDIT_LEVEL_ALGOS
    warn "ERROR: set EDIT_BD_ALGOS, EDIT_TIME_ALGOS, and/or EDIT_LEVEL_ALGOS to true"
    exit 1
  end

  target_enabled = parse_target_state(
    TARGET_STATE_FOR_ALL_EDITED_ALGOS,
    "TARGET_STATE_FOR_ALL_EDITED_ALGOS"
  )
  all_list_ids = parse_algo_id_list(
    SET_STATE_FOR_ALL_ALGOS_LIST,
    "SET_STATE_FOR_ALL_ALGOS_LIST",
    allow_empty: target_enabled
  )
  list_ids_by_family, skipped_for_disabled_families = partition_list_for_edited_families(all_list_ids)

  unless skipped_for_disabled_families.empty?
    warn "WARNING: skipping algo id(s) in SET_STATE_FOR_ALL_ALGOS_LIST because that family's EDIT flag is false: " \
         "#{skipped_for_disabled_families.join(', ')}"
  end

  mq5_content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  mq5_updated = mq5_content
  level_fam_content = EDIT_LEVEL_ALGOS ? File.read(LEVEL_FAM_FILE, encoding: "UTF-8") : nil
  level_fam_updated = level_fam_content
  plans = []

  puts "Target for edited families: #{target_enabled ? 'enabled (whitelist)' : 'disabled (blacklist)'}"
  puts

  if EDIT_BD_ALGOS
    bd_list_ids = list_ids_by_family[FAMILY_BREAKDOWN]
    bd_all_ids = registry_algo_ids(mq5_content, BD_REGISTRY_MARKERS, BD_REGISTRY_ID_RE)
    bd_plan = build_enable_plan(bd_all_ids, bd_list_ids, target_enabled: target_enabled)
    bd_missing = bd_plan.keys.reject { |algo_id| mq5_content.match?(breakdown_enabled_line_re(algo_id)) }

    if bd_missing.any?
      warn "ERROR: no .enabled line for breakdown algo(s): #{bd_missing.join(', ')}"
      exit 1
    end

    summarize_plan("Breakdown algos", bd_all_ids, bd_list_ids, target_enabled, bd_plan)
    plans << [:mq5, BD_ENABLED_LINE_RE, bd_plan]
  end

  if EDIT_TIME_ALGOS
    time_list_ids = list_ids_by_family[FAMILY_TIME]
    time_all_ids = registry_algo_ids(mq5_content, TIME_REGISTRY_MARKERS, TIME_REGISTRY_ID_RE)
    time_plan = build_enable_plan(time_all_ids, time_list_ids, target_enabled: target_enabled)
    time_missing = time_plan.keys.reject { |algo_id| mq5_content.match?(time_enabled_line_re(algo_id)) }

    if time_missing.any?
      warn "ERROR: no .enabled line for time algo(s): #{time_missing.join(', ')}"
      exit 1
    end

    summarize_plan("Time algos", time_all_ids, time_list_ids, target_enabled, time_plan)
    plans << [:mq5, TIME_ENABLED_LINE_RE, time_plan]
  end

  if EDIT_LEVEL_ALGOS
    level_list_ids = list_ids_by_family[FAMILY_LEVEL]
    level_all_ids = registry_algo_ids(mq5_content, LEVEL_REGISTRY_MARKERS, LEVEL_REGISTRY_ID_RE)
    level_plan = build_enable_plan(level_all_ids, level_list_ids, target_enabled: target_enabled)
    level_missing = level_plan.keys.reject { |algo_id| level_fam_content.match?(level_enabled_line_re(algo_id)) }

    if level_missing.any?
      warn "ERROR: no .enabled line for level algo(s): #{level_missing.join(', ')}"
      exit 1
    end

    summarize_plan("Level algos", level_all_ids, level_list_ids, target_enabled, level_plan)
    plans << [:level_fam, LEVEL_ENABLED_LINE_RE, level_plan]
  end

  dry_changed = []
  dry_skipped = []

  plans.each do |target, line_re, plan|
    case target
    when :mq5
      mq5_updated, changed, skipped = apply_enable_plan!(mq5_updated, line_re, plan)
    when :level_fam
      level_fam_updated, changed, skipped = apply_enable_plan!(level_fam_updated, line_re, plan)
    else
      raise "Unknown write target: #{target}"
    end
    dry_changed.concat(changed)
    dry_skipped.concat(skipped)
  end

  if dry_changed.empty?
    puts "No changes (#{dry_skipped.uniq.sort.join(', ')} already at target state)."
    exit 0
  end

  print "Apply enabled changes for #{dry_changed.uniq.size} algo(s)? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  mq5_updated = mq5_content
  level_fam_updated = level_fam_content
  plans.each do |target, line_re, plan|
    case target
    when :mq5
      mq5_updated, = apply_enable_plan!(mq5_updated, line_re, plan)
    when :level_fam
      level_fam_updated, = apply_enable_plan!(level_fam_updated, line_re, plan)
    end
  end

  File.write(MQ5_FILE, mq5_updated) if plans.any? { |target, _, _| target == :mq5 }
  File.write(LEVEL_FAM_FILE, level_fam_updated) if plans.any? { |target, _, _| target == :level_fam }

  puts "Updated #{dry_changed.uniq.size} algo(s): #{dry_changed.uniq.sort.join(', ')}"
  puts MQ5_FILE if plans.any? { |target, _, _| target == :mq5 }
  puts LEVEL_FAM_FILE if plans.any? { |target, _, _| target == :level_fam }
end
