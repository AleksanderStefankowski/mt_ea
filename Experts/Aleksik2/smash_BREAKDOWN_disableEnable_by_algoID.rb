#!/usr/bin/env ruby
# frozen_string_literal: true
# Set .enabled for specific breakdown/time algo IDs in aleksik2.mq5.
#
# Whitelist (target :enabled): enable listed algos, disable all other wired algos in that family.
# Blacklist (target :disabled): disable listed algos only; leave all others unchanged.

require_relative "smash_BREAKDOWN_creator_from_combinations"

EDIT_BD_ALGOS = true
TARGET_STATE_FOR_BD_ALGOS = :enabled # :enabled or :disabled

SET_STATE_FOR_BD_ALGOS_LIST = <<~IDS
  20000028
IDS

EDIT_TIME_ALGOS = true
TARGET_STATE_FOR_TIME_ALGOS = :enabled # :enabled or :disabled

SET_STATE_FOR_TIME_ALGOS_LIST = <<~IDS
  10000002
IDS

BD_REGISTRY_MARKERS = %w[//breakdowncreator1start //breakdowncreator1end].freeze
BD_REGISTRY_ID_RE = /MAGIC_BREAKDOWN(\d+)/

TIME_REGISTRY_MARKERS = %w[//timealgocreator1start //timealgocreator1end].freeze
TIME_REGISTRY_ID_RE = /TIME_ALGO_(\d+)/

BD_ENABLED_LINE_RE = /
  g_breakdownAlgos\[BreakdownAlgoSlotIndexByAlgoId\(MAGIC_BREAKDOWN(\d+)\)\]\.enabled\s*=\s*(true|false);
/x

TIME_ENABLED_LINE_RE = /
  g_timeAlgos\[TimeAlgoSlotIndexByAlgoId\(TIME_ALGO_(\d+)\)\]\.enabled\s*=\s*(true|false);
/x

module DisableEnableByAlgoId
  module_function

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

  def parse_algo_id_list(text, label)
    ids =
      text.each_line.filter_map do |line|
        stripped = line.strip
        next if stripped.empty?
        next if stripped.start_with?("#")

        raise ArgumentError, "Invalid algo id line: #{line.inspect}" unless stripped.match?(/\A\d+\z/)

        stripped.to_i
      end.uniq.sort

    raise ArgumentError, "#{label} is empty" if ids.empty?

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
    puts "  List algo ids:            #{list_ids.join(', ')}"
    puts "  Target for listed algos:  #{target_enabled ? 'enabled' : 'disabled'}"
    if target_enabled
      puts "  Mode:                     whitelist (enable listed, disable others)"
      puts "  Will enable:              #{enable_ids.empty? ? '(none)' : enable_ids.join(', ')}"
      puts "  Will disable:             #{disable_ids.empty? ? '(none)' : disable_ids.join(', ')}"
    else
      puts "  Mode:                     blacklist (disable listed only)"
      puts "  Will disable:             #{disable_ids.empty? ? '(none)' : disable_ids.join(', ')}"
    end
    puts
  end
end

include DisableEnableByAlgoId

if __FILE__ == $PROGRAM_NAME
  unless EDIT_BD_ALGOS || EDIT_TIME_ALGOS
    warn "ERROR: set EDIT_BD_ALGOS and/or EDIT_TIME_ALGOS to true"
    exit 1
  end

  content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  updated = content
  plans = []

  if EDIT_BD_ALGOS
    bd_target_enabled = parse_target_state(TARGET_STATE_FOR_BD_ALGOS, "TARGET_STATE_FOR_BD_ALGOS")
    bd_list_ids = parse_algo_id_list(SET_STATE_FOR_BD_ALGOS_LIST, "SET_STATE_FOR_BD_ALGOS_LIST")
    bd_all_ids = registry_algo_ids(content, BD_REGISTRY_MARKERS, BD_REGISTRY_ID_RE)
    bd_plan = build_enable_plan(bd_all_ids, bd_list_ids, target_enabled: bd_target_enabled)
    bd_missing = bd_plan.keys.reject { |algo_id| content.match?(breakdown_enabled_line_re(algo_id)) }

    if bd_missing.any?
      warn "ERROR: no .enabled line for breakdown algo(s): #{bd_missing.join(', ')}"
      exit 1
    end

    summarize_plan("Breakdown algos", bd_all_ids, bd_list_ids, bd_target_enabled, bd_plan)
    plans << [:breakdown, BD_ENABLED_LINE_RE, bd_plan]
  end

  if EDIT_TIME_ALGOS
    time_target_enabled = parse_target_state(TARGET_STATE_FOR_TIME_ALGOS, "TARGET_STATE_FOR_TIME_ALGOS")
    time_list_ids = parse_algo_id_list(SET_STATE_FOR_TIME_ALGOS_LIST, "SET_STATE_FOR_TIME_ALGOS_LIST")
    time_all_ids = registry_algo_ids(content, TIME_REGISTRY_MARKERS, TIME_REGISTRY_ID_RE)
    time_plan = build_enable_plan(time_all_ids, time_list_ids, target_enabled: time_target_enabled)
    time_missing = time_plan.keys.reject { |algo_id| content.match?(time_enabled_line_re(algo_id)) }

    if time_missing.any?
      warn "ERROR: no .enabled line for time algo(s): #{time_missing.join(', ')}"
      exit 1
    end

    summarize_plan("Time algos", time_all_ids, time_list_ids, time_target_enabled, time_plan)
    plans << [:time, TIME_ENABLED_LINE_RE, time_plan]
  end

  dry_changed = []
  dry_skipped = []

  plans.each do |_family, line_re, plan|
    updated, changed, skipped = apply_enable_plan!(updated, line_re, plan)
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

  updated = content
  plans.each do |_family, line_re, plan|
    updated, = apply_enable_plan!(updated, line_re, plan)
  end

  File.write(MQ5_FILE, updated)

  puts "Updated #{dry_changed.uniq.size} algo(s): #{dry_changed.uniq.sort.join(', ')}"
  puts MQ5_FILE
end
