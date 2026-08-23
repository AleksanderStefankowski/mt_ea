#!/usr/bin/env ruby
# frozen_string_literal: true
# Enable/disable base vs quant-ref algos per family in aleksik2.
#
# Quant algos are clones with a quantref comment (reference-point gate rules).
# Base algos are wired algos that are not quant-ref clones.
#
# For each selected family, each listed ALGO_TYPE gets TARGET_STATE; unlisted types get the opposite.
# Use both types to apply TARGET_STATE to every wired algo (e.g. disable all).
# Example: ALGO_TYPES = [:quant], TARGET_STATE = :enabled
#   -> enable quant, disable base (within selected families).
# Example: ALGO_TYPES = [:quant, :base], TARGET_STATE = :disabled
#   -> disable all wired algos in selected families.
DO_WHICH_FAMS = [
  :level,
  :time,
  :breakdown
].freeze

# :quant = algos with quantref comment; :base = wired algos that are not quant-ref clones
# One or both — [:quant, :base] applies TARGET_STATE to every algo (no opposite flip)
ALGO_TYPES = [
  :quant, 
  # :base
].freeze

# :enabled or :disabled — applied to each type in ALGO_TYPES
TARGET_STATE = :enabled

require_relative "smash_BREAKDOWN_creator_from_combinations"

LEVEL_FAM_FILE = File.expand_path("aleksik2_level_fam.mqh", __dir__)

QUANTREF_NEW_ID_RE = /(?:\/\/\s*)?quantref\s+base=\d+\s+new=(\d+)/

FAMILY_CONFIG = {
  breakdown: {
    label: "Breakdown",
    registry_markers: %w[//breakdowncreator1start //breakdowncreator1end],
    registry_id_re: /MAGIC_BREAKDOWN(\d+)/,
    enabled_line_re: /
      g_breakdownAlgos\[BreakdownAlgoSlotIndexByAlgoId\(MAGIC_BREAKDOWN(\d+)\)\]\.enabled\s*=\s*(true|false);
    /x,
    write_target: :mq5
  },
  time: {
    label: "Time",
    registry_markers: %w[//timealgocreator1start //timealgocreator1end],
    registry_id_re: /TIME_ALGO_(\d+)/,
    enabled_line_re: /
      g_timeAlgos\[TimeAlgoSlotIndexByAlgoId\(TIME_ALGO_(\d+)\)\]\.enabled\s*=\s*(true|false);
    /x,
    write_target: :mq5
  },
  level: {
    label: "Level",
    registry_markers: %w[//levelalgocreator1start //levelalgocreator1end],
    registry_id_re: /MAGIC_LEVEL(\d+)/,
    enabled_line_re: /
      g_levelAlgos\[LevelAlgoSlotIndexByAlgoId\(MAGIC_LEVEL(\d+)\)\]\.enabled\s*=\s*(true|false);
    /x,
    write_target: :level_fam
  }
}.freeze

module DisableEnableByQuant
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

  def parse_algo_type(value, label)
    case value.to_s.strip.downcase.to_sym
    when :quant, :quanted
      :quant
    when :base, :unquanted
      :base
    else
      raise ArgumentError, "#{label} must be :quant or :base (got #{value.inspect})"
    end
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

  def quant_algo_ids(*contents)
    contents.compact.join.scan(QUANTREF_NEW_ID_RE).flatten.map(&:to_i).uniq.sort
  end

  def parse_algo_types(value, label)
    types = Array(value).flatten.map { |item| parse_algo_type(item, label) }.uniq
    raise ArgumentError, "#{label} must list at least one of :quant, :base" if types.empty?

    types
  end

  def build_type_plan(all_ids, quant_ids, algo_types:, target_enabled:)
    quant_set = quant_ids.to_set
    type_set = algo_types.to_set
    apply_to_all = type_set.include?(:quant) && type_set.include?(:base)
    on_state = target_enabled
    off_state = !target_enabled

    all_ids.to_h do |id|
      is_quant = quant_set.include?(id)
      bucket = is_quant ? :quant : :base
      enabled =
        if apply_to_all
          on_state
        elsif type_set.include?(bucket)
          on_state
        else
          off_state
        end
      [id, enabled]
    end
  end

  def summarize_plan(family_label, all_ids, quant_ids, base_ids, algo_types, target_enabled, plan)
    on_label = target_enabled ? "enabled" : "disabled"
    off_label = target_enabled ? "disabled" : "enabled"
    apply_to_all = algo_types.include?(:quant) && algo_types.include?(:base)

    enable_ids = plan.select { |_id, enabled| enabled }.keys.sort
    disable_ids = plan.select { |_id, enabled| !enabled }.keys.sort

    puts "#{family_label}:"
    puts "  Wired algos:              #{all_ids.size}"
    puts "  Quant algos:              #{quant_ids.size}"
    puts "  Base algos:               #{base_ids.size}"
    if apply_to_all
      puts "  ALGO_TYPES:               #{algo_types.join(', ')} -> all #{on_label}"
    else
      on_types = algo_types.join(", ")
      off_types = ([:quant, :base] - algo_types).join(", ")
      puts "  ALGO_TYPES:               #{on_types} -> #{on_label}, #{off_types} -> #{off_label}"
    end
    puts "  Will enable:              #{enable_ids.empty? ? '(none)' : enable_ids.join(', ')}"
    puts "  Will disable:             #{disable_ids.empty? ? '(none)' : disable_ids.join(', ')}"
    puts
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
end

if __FILE__ == $PROGRAM_NAME
  if DO_WHICH_FAMS.empty?
    warn "ERROR: DO_WHICH_FAMS is empty — uncomment at least one family"
    exit 1
  end

  unknown_fams = DO_WHICH_FAMS - FAMILY_CONFIG.keys
  unless unknown_fams.empty?
    warn "ERROR: unknown family in DO_WHICH_FAMS: #{unknown_fams.join(', ')}"
    exit 1
  end

  algo_types = DisableEnableByQuant.parse_algo_types(ALGO_TYPES, "ALGO_TYPES")
  target_enabled = DisableEnableByQuant.parse_target_state(TARGET_STATE, "TARGET_STATE")

  mq5_content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  level_fam_content = DO_WHICH_FAMS.include?(:level) ? File.read(LEVEL_FAM_FILE, encoding: "UTF-8") : nil
  quant_ids_all = DisableEnableByQuant.quant_algo_ids(mq5_content, level_fam_content)

  plans = []

  DO_WHICH_FAMS.each do |family|
    cfg = FAMILY_CONFIG.fetch(family)
    all_ids = DisableEnableByQuant.registry_algo_ids(mq5_content, cfg[:registry_markers], cfg[:registry_id_re])
    quant_ids = quant_ids_all & all_ids
    base_ids = all_ids - quant_ids
    plan = DisableEnableByQuant.build_type_plan(
      all_ids, quant_ids, algo_types: algo_types, target_enabled: target_enabled
    )

    content_for_lines = family == :level ? level_fam_content : mq5_content
    missing = plan.keys.reject { |algo_id| content_for_lines.match?(cfg[:enabled_line_re]) }
    unless missing.empty?
      warn "ERROR: no .enabled line for #{family} algo(s): #{missing.join(', ')}"
      exit 1
    end

    DisableEnableByQuant.summarize_plan(
      cfg[:label], all_ids, quant_ids, base_ids, algo_types, target_enabled, plan
    )
    plans << [cfg[:write_target], cfg[:enabled_line_re], plan]
  end

  puts "Families:     #{DO_WHICH_FAMS.join(', ')}"
  puts "ALGO_TYPES:   #{algo_types.join(', ')}"
  puts "TARGET_STATE: #{target_enabled ? :enabled : :disabled}"
  puts

  mq5_updated = mq5_content
  level_fam_updated = level_fam_content
  dry_changed = []
  dry_skipped = []

  plans.each do |target, line_re, plan|
    case target
    when :mq5
      mq5_updated, changed, skipped = DisableEnableByQuant.apply_enable_plan!(mq5_updated, line_re, plan)
    when :level_fam
      level_fam_updated, changed, skipped = DisableEnableByQuant.apply_enable_plan!(
        level_fam_updated, line_re, plan
      )
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
      mq5_updated, = DisableEnableByQuant.apply_enable_plan!(mq5_updated, line_re, plan)
    when :level_fam
      level_fam_updated, = DisableEnableByQuant.apply_enable_plan!(level_fam_updated, line_re, plan)
    end
  end

  File.write(MQ5_FILE, mq5_updated) if plans.any? { |target, _, _| target == :mq5 }
  File.write(LEVEL_FAM_FILE, level_fam_updated) if plans.any? { |target, _, _| target == :level_fam }

  puts "Updated #{dry_changed.uniq.size} algo(s): #{dry_changed.uniq.sort.join(', ')}"
  puts MQ5_FILE if plans.any? { |target, _, _| target == :mq5 }
  puts LEVEL_FAM_FILE if plans.any? { |target, _, _| target == :level_fam }
end
