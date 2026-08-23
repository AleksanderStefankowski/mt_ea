#!/usr/bin/env ruby
# frozen_string_literal: true
# Delete base or quant-ref algo definitions per family in aleksik2.
#
# Quant algos are clones with a quantref comment (reference-point gate rules).
# Base algos are wired algos that are not quant-ref clones.
#
# Removes registry entries, param blocks, and rule cases. Lowers *_REGISTRY_MAX when possible.
# Re-run smash_from_QUANTREFERENCEPOINTS_creator.rb afterward to recreate quant-ref clones.

DO_WHICH_FAMS = [
  :level,
  :time,
  :breakdown
].freeze

# :quant = algos created with reference-point gates (quantref comment)
# :base  = wired algos that are not quant-ref clones
ALGO_TYPE = :quant

require "set"
require_relative "../Aleksik/smash_mql5_algo_reader_lib"

MQ5_FILE = File.expand_path("aleksik2.mq5", __dir__)
LEVEL_FAM_FILE = File.expand_path("aleksik2_level_fam.mqh", __dir__)

QUANTREF_NEW_ID_RE = /(?:\/\/\s*)?quantref\s+base=\d+\s+new=(\d+)/

BREAKDOWN_ID_MIN = 20_000_000
BREAKDOWN_ID_MAX = 99_999_999
LEVEL_ALGO_ID_MIN = 30_000_001
LEVEL_ALGO_ID_MAX = 39_999_999
TIME_ALGO_ID_MIN = 10_000_001
TIME_ALGO_ID_MAX = 99_999_999

BREAKDOWN_REGISTRY_MARKERS = %w[//breakdowncreator1start //breakdowncreator1end].freeze
BREAKDOWN_PARAMS_MARKERS = %w[//breakdowncreator2start //breakdowncreator2end].freeze
BREAKDOWN_RULES_MARKERS = %w[//breakdowncreator4start //breakdowncreator4end].freeze
TIME_REGISTRY_MARKERS = %w[//timealgocreator1start //timealgocreator1end].freeze
TIME_PARAMS_MARKERS = %w[//timealgocreator2start //timealgocreator2end].freeze
TIME_RULE_MARKERS = %w[//timealgocreator3start //timealgocreator3end].freeze
LEVEL_REGISTRY_MARKERS = %w[//levelalgocreator1start //levelalgocreator1end].freeze
LEVEL_PARAMS_MARKERS = %w[//levelalgocreator2start //levelalgocreator2end].freeze
LEVEL_RULE_MARKERS = %w[//levelalgocreator3start //levelalgocreator3end].freeze

module DeleteQuantAlgosFams
  module_function

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

  def delete_ids_for(wired_ids, quant_ids, algo_type)
    case algo_type
    when :quant
      quant_ids.uniq.sort
    when :base
      (wired_ids - quant_ids).uniq.sort
    else
      raise ArgumentError, "Unknown algo_type: #{algo_type.inspect}"
    end
  end

  def marker_line_re(marker)
    /^\s*#{Regexp.escape(marker)}\s*$/
  end

  def extract_marked_inner(content, markers)
    start_marker, end_marker = markers
    lines = content.lines
    start_idx = lines.index { |line| line.match?(marker_line_re(start_marker)) }
    end_idx = lines.index { |line| line.match?(marker_line_re(end_marker)) }
    unless start_idx && end_idx && end_idx > start_idx
      raise "Could not find block (#{start_marker} .. #{end_marker})"
    end

    lines[(start_idx + 1)...end_idx].join.rstrip
  end

  def replace_marked_inner(content, markers, new_inner)
    start_marker, end_marker = markers
    lines = content.lines
    start_idx = lines.index { |line| line.match?(marker_line_re(start_marker)) }
    end_idx = lines.index { |line| line.match?(marker_line_re(end_marker)) }
    unless start_idx && end_idx && end_idx > start_idx
      raise "Could not find block (#{start_marker} .. #{end_marker})"
    end

    before = lines[0..start_idx].join
    after = lines[end_idx..].join
    "#{before}#{new_inner.rstrip}\n#{after}"
  end

  def collapse_blank_lines(text)
    text.gsub(/\n{3,}/, "\n\n").rstrip
  end

  # Drop every line that references any delete_id via id_re (g_*, ArrayResize, case labels, etc.).
  def filter_params_lines(inner, delete_ids, id_re)
    return inner if delete_ids.empty?

    delete_set = delete_ids.to_set
    kept = inner.lines.reject do |line|
      line.scan(id_re).flatten.any? { |id| delete_set.include?(id.to_i) }
    end
    collapse_blank_lines(kept.join)
  end

  # Single-pass removal of switch cases for any label in delete_labels (e.g. MAGIC_LEVEL30000037).
  def filter_rule_cases(inner, delete_labels)
    return inner if delete_labels.empty?

    delete_set = delete_labels.to_set
    lines = inner.lines.map(&:chomp)
    out = []
    i = 0
    while i < lines.length
      if (m = lines[i].match(/^\s*case\s+(\S+)\s*:/))
        if delete_set.include?(m[1])
          i += 1
          while i < lines.length && !lines[i].match?(/^\s*break\s*;/)
            i += 1
          end
          raise "No break; after case #{m[1]}" unless i < lines.length

          i += 1
          i += 1 while i < lines.length && lines[i].strip.empty?
          next
        end
      end
      out << lines[i]
      i += 1
    end
    collapse_blank_lines(out.join("\n"))
  end

  def breakdown_id_re
    /MAGIC_BREAKDOWN(\d+)/
  end

  def level_id_re
    /MAGIC_LEVEL(\d{8})/
  end

  def time_id_re
    /TIME_ALGO_(\d{8})/
  end

  def breakdown_case_labels(delete_ids)
    delete_ids.map { |algo_id| breakdown_magic_const(algo_id) }
  end

  def level_case_labels(delete_ids)
    delete_ids.map { |algo_id| level_magic_const(algo_id) }
  end

  def time_case_labels(delete_ids)
    delete_ids.map { |algo_id| time_const(algo_id) }
  end

  def breakdown_magic_const(algo_id)
    "MAGIC_BREAKDOWN#{algo_id}"
  end

  def level_magic_const(algo_id)
    format("MAGIC_LEVEL%08d", algo_id)
  end

  def time_const(algo_id)
    format("TIME_ALGO_%08d", algo_id)
  end

  def ids_from_block(block, id_re)
    block.scan(id_re).flatten.map(&:to_i).uniq.sort
  end

  def quant_ids_from_text(text, min_id, max_id)
    text.scan(QUANTREF_NEW_ID_RE).flatten.map(&:to_i)
      .select { |id| id >= min_id && id <= max_id }.uniq.sort
  end

  def breakdown_wired_ids(mq5_content)
    ids_from_block(extract_marked_inner(mq5_content, BREAKDOWN_REGISTRY_MARKERS), /MAGIC_BREAKDOWN(\d+)/)
  end

  def breakdown_quant_ids(mq5_content)
    params = extract_marked_inner(mq5_content, BREAKDOWN_PARAMS_MARKERS)
    rules =
      begin
        extract_marked_inner(mq5_content, BREAKDOWN_RULES_MARKERS)
      rescue StandardError
        ""
      end
    quant_ids_from_text([params, rules].join("\n"), BREAKDOWN_ID_MIN, BREAKDOWN_ID_MAX)
  end

  def time_wired_ids(mq5_content)
    ids_from_block(extract_marked_inner(mq5_content, TIME_REGISTRY_MARKERS), /TIME_ALGO_(\d+)/)
  end

  def time_quant_ids(mq5_content)
    params = extract_marked_inner(mq5_content, TIME_PARAMS_MARKERS)
    rules =
      begin
        extract_marked_inner(mq5_content, TIME_RULE_MARKERS)
      rescue StandardError
        ""
      end
    quant_ids_from_text([params, rules].join("\n"), TIME_ALGO_ID_MIN, TIME_ALGO_ID_MAX)
  end

  def level_wired_ids(mq5_content)
    ids_from_block(extract_marked_inner(mq5_content, LEVEL_REGISTRY_MARKERS), /MAGIC_LEVEL(\d+)/)
  end

  def level_quant_ids(mq5_content, level_fam_content)
    params = extract_marked_inner(level_fam_content, LEVEL_PARAMS_MARKERS)
    rules =
      begin
        extract_marked_inner(mq5_content, LEVEL_RULE_MARKERS)
      rescue StandardError
        ""
      end
    quant_ids_from_text([params, rules].join("\n"), LEVEL_ALGO_ID_MIN, LEVEL_ALGO_ID_MAX)
  end

  def registry_max(mq5_content, define_name)
    m = mq5_content.match(/#define\s+#{define_name}\s+(\d+)/)
    raise "#{define_name} not found in #{MQ5_FILE}" unless m

    m[1].to_i
  end

  def set_registry_max(mq5_content, define_name, new_max, format_str)
    unless mq5_content.sub!(/#define\s+#{define_name}\s+\d+/, format(format_str, new_max))
      raise "Failed to update #{define_name} in #{MQ5_FILE}"
    end

    mq5_content
  end

  def rebuild_breakdown_registry_inner(algo_ids)
    lines = []
    algo_ids.each do |algo_id|
      const = breakdown_magic_const(algo_id)
      lines << "#define #{const}#{' ' * (28 - const.length)}#{algo_id}"
    end
    lines << ""
    lines << "int g_breakdownRegistryIds[] ="
    lines << "{"
    algo_ids.each { |algo_id| lines << "   #{breakdown_magic_const(algo_id)}," }
    lines[-1] = lines[-1].sub(/,\z/, "") unless algo_ids.empty?
    lines << "};"
    lines.join("\n")
  end

  def rebuild_time_registry_inner(algo_ids)
    lines = []
    algo_ids.each do |algo_id|
      const = time_const(algo_id)
      lines << "#define #{const}#{' ' * (28 - const.length)}#{algo_id}"
    end
    lines << ""
    lines << "int g_timeAlgoRegistryIds[] ="
    lines << "{"
    algo_ids.each { |algo_id| lines << "   #{time_const(algo_id)}," }
    lines[-1] = lines[-1].sub(/,\z/, "") unless algo_ids.empty?
    lines << "};"
    lines.join("\n")
  end

  def rebuild_level_registry_inner(algo_ids)
    lines = []
    lines << "int g_levelAlgoRegistryIds[] ="
    lines << "{"
    algo_ids.each { |algo_id| lines << "   #{level_magic_const(algo_id)}," }
    lines[-1] = lines[-1].sub(/,\z/, "") unless algo_ids.empty?
    lines << "};"
    lines.join("\n")
  end

  def replace_magic_level_defines(mq5_content, algo_ids)
    new_block = algo_ids.map do |algo_id|
      format("#define %-28s %d", level_magic_const(algo_id), algo_id)
    end.join("\n") + "\n"

    unless mq5_content.sub!(/(?:#define MAGIC_LEVEL\d+\s+\d+\s*\n)+/, new_block)
      raise "Failed to replace MAGIC_LEVEL* defines in #{MQ5_FILE}"
    end

    mq5_content
  end

  def delete_breakdown!(mq5_content, delete_ids)
    remaining_ids = breakdown_wired_ids(mq5_content) - delete_ids
    raise "Cannot delete all breakdown algos" if remaining_ids.empty?

    inner1 = rebuild_breakdown_registry_inner(remaining_ids)
    inner2 = filter_params_lines(
      extract_marked_inner(mq5_content, BREAKDOWN_PARAMS_MARKERS), delete_ids, breakdown_id_re
    )
    inner4 = filter_rule_cases(
      extract_marked_inner(mq5_content, BREAKDOWN_RULES_MARKERS), breakdown_case_labels(delete_ids)
    )

    mq5_content = replace_marked_inner(mq5_content, BREAKDOWN_REGISTRY_MARKERS, inner1)
    mq5_content = replace_marked_inner(mq5_content, BREAKDOWN_PARAMS_MARKERS, inner2)
    replace_marked_inner(mq5_content, BREAKDOWN_RULES_MARKERS, inner4)
  end

  def delete_time!(mq5_content, delete_ids)
    remaining_ids = time_wired_ids(mq5_content) - delete_ids
    raise "Cannot delete all time algos" if remaining_ids.empty?

    inner1 = rebuild_time_registry_inner(remaining_ids)
    inner2 = filter_params_lines(
      extract_marked_inner(mq5_content, TIME_PARAMS_MARKERS), delete_ids, time_id_re
    )
    inner3 = filter_rule_cases(
      extract_marked_inner(mq5_content, TIME_RULE_MARKERS), time_case_labels(delete_ids)
    )

    mq5_content = replace_marked_inner(mq5_content, TIME_REGISTRY_MARKERS, inner1)
    mq5_content = replace_marked_inner(mq5_content, TIME_PARAMS_MARKERS, inner2)
    replace_marked_inner(mq5_content, TIME_RULE_MARKERS, inner3)
  end

  def delete_level!(mq5_content, level_fam_content, delete_ids)
    remaining_ids = level_wired_ids(mq5_content) - delete_ids
    raise "Cannot delete all level algos" if remaining_ids.empty?

    mq5_content = replace_magic_level_defines(mq5_content, remaining_ids)
    mq5_content = replace_marked_inner(
      mq5_content, LEVEL_REGISTRY_MARKERS, rebuild_level_registry_inner(remaining_ids)
    )

    inner2 = filter_params_lines(
      extract_marked_inner(level_fam_content, LEVEL_PARAMS_MARKERS), delete_ids, level_id_re
    )
    inner3 = filter_rule_cases(
      extract_marked_inner(mq5_content, LEVEL_RULE_MARKERS), level_case_labels(delete_ids)
    )

    level_fam_content = replace_marked_inner(level_fam_content, LEVEL_PARAMS_MARKERS, inner2)
    mq5_content = replace_marked_inner(mq5_content, LEVEL_RULE_MARKERS, inner3)
    [mq5_content, level_fam_content]
  end

  def summarize_family(label, wired_ids, quant_ids, base_ids, algo_type, delete_ids)
    on_type = algo_type == :quant ? "quant" : "base"
    puts "#{label}:"
    puts "  Wired algos:              #{wired_ids.size}"
    puts "  Quant algos:              #{quant_ids.size}"
    puts "  Base algos:               #{base_ids.size}"
    puts "  ALGO_TYPE:                #{on_type}"
    puts "  Will delete:              #{delete_ids.empty? ? '(none)' : "#{delete_ids.size} (#{delete_ids.join(', ')})"}"
    puts "  Will keep (wired):        #{(wired_ids - delete_ids).empty? ? '(none)' : (wired_ids - delete_ids).join(', ')}"
    puts
  end
end

FAMILY_CONFIG = {
  breakdown: {
    label: "Breakdown",
    registry_max_name: "BREAKDOWN_ALGO_REGISTRY_MAX",
    registry_max_format: "#define BREAKDOWN_ALGO_REGISTRY_MAX           %d",
    wired_ids: ->(mq5, _level_fam) { DeleteQuantAlgosFams.breakdown_wired_ids(mq5) },
    quant_ids: ->(mq5, _level_fam) { DeleteQuantAlgosFams.breakdown_quant_ids(mq5) },
    apply_delete!: lambda { |mq5, _level_fam, delete_ids|
      updated = DeleteQuantAlgosFams.delete_breakdown!(mq5, delete_ids)
      keep_count = DeleteQuantAlgosFams.breakdown_wired_ids(updated).size
      old_max = DeleteQuantAlgosFams.registry_max(updated, "BREAKDOWN_ALGO_REGISTRY_MAX")
      updated = DeleteQuantAlgosFams.set_registry_max(
        updated, "BREAKDOWN_ALGO_REGISTRY_MAX", keep_count,
        "#define BREAKDOWN_ALGO_REGISTRY_MAX           %d"
      ) if keep_count != old_max
      [updated, nil, old_max, DeleteQuantAlgosFams.registry_max(updated, "BREAKDOWN_ALGO_REGISTRY_MAX")]
    }
  },
  time: {
    label: "Time",
    registry_max_name: "TIME_ALGO_REGISTRY_MAX",
    registry_max_format: "#define TIME_ALGO_REGISTRY_MAX                   %d",
    wired_ids: ->(mq5, _level_fam) { DeleteQuantAlgosFams.time_wired_ids(mq5) },
    quant_ids: ->(mq5, _level_fam) { DeleteQuantAlgosFams.time_quant_ids(mq5) },
    apply_delete!: lambda { |mq5, _level_fam, delete_ids|
      updated = DeleteQuantAlgosFams.delete_time!(mq5, delete_ids)
      keep_count = DeleteQuantAlgosFams.time_wired_ids(updated).size
      old_max = DeleteQuantAlgosFams.registry_max(updated, "TIME_ALGO_REGISTRY_MAX")
      updated = DeleteQuantAlgosFams.set_registry_max(
        updated, "TIME_ALGO_REGISTRY_MAX", keep_count,
        "#define TIME_ALGO_REGISTRY_MAX                   %d"
      ) if keep_count != old_max
      [updated, nil, old_max, DeleteQuantAlgosFams.registry_max(updated, "TIME_ALGO_REGISTRY_MAX")]
    }
  },
  level: {
    label: "Level",
    registry_max_name: "LEVEL_ALGO_REGISTRY_MAX",
    registry_max_format: "#define LEVEL_ALGO_REGISTRY_MAX                  %d",
    wired_ids: ->(mq5, level_fam) { DeleteQuantAlgosFams.level_wired_ids(mq5) },
    quant_ids: ->(mq5, level_fam) { DeleteQuantAlgosFams.level_quant_ids(mq5, level_fam) },
    apply_delete!: lambda { |mq5, level_fam, delete_ids|
      updated_mq5, updated_level_fam = DeleteQuantAlgosFams.delete_level!(mq5, level_fam, delete_ids)
      keep_count = DeleteQuantAlgosFams.level_wired_ids(updated_mq5).size
      old_max = DeleteQuantAlgosFams.registry_max(updated_mq5, "LEVEL_ALGO_REGISTRY_MAX")
      if keep_count != old_max
        updated_mq5 = DeleteQuantAlgosFams.set_registry_max(
          updated_mq5, "LEVEL_ALGO_REGISTRY_MAX", keep_count,
          "#define LEVEL_ALGO_REGISTRY_MAX                  %d"
        )
      end
      [updated_mq5, updated_level_fam, old_max, DeleteQuantAlgosFams.registry_max(updated_mq5, "LEVEL_ALGO_REGISTRY_MAX")]
    }
  }
}.freeze

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

  algo_type = DeleteQuantAlgosFams.parse_algo_type(ALGO_TYPE, "ALGO_TYPE")
  type_label = algo_type == :quant ? "quant-ref" : "base"

  mq5_content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  level_fam_content = DO_WHICH_FAMS.include?(:level) ? File.read(LEVEL_FAM_FILE, encoding: "bom|utf-8") : nil

  plans = DO_WHICH_FAMS.map do |family|
    cfg = FAMILY_CONFIG.fetch(family)
    wired_ids = cfg[:wired_ids].call(mq5_content, level_fam_content)
    quant_ids = cfg[:quant_ids].call(mq5_content, level_fam_content)
    base_ids = wired_ids - quant_ids
    delete_ids = DeleteQuantAlgosFams.delete_ids_for(wired_ids, quant_ids, algo_type)

    DeleteQuantAlgosFams.summarize_family(
      cfg[:label], wired_ids, quant_ids, base_ids, algo_type, delete_ids
    )

    {
      cfg: cfg,
      delete_ids: delete_ids,
      registry_max: DeleteQuantAlgosFams.registry_max(mq5_content, cfg[:registry_max_name])
    }
  end

  puts "Families:    #{DO_WHICH_FAMS.join(', ')}"
  puts "ALGO_TYPE:   #{algo_type} (#{type_label})"
  puts

  total_delete = plans.sum { |plan| plan[:delete_ids].size }
  if total_delete.zero?
    puts "No #{type_label} algos to delete in selected families."
    exit 0
  end

  plans.each do |plan|
    next if plan[:delete_ids].empty?

    puts "#{plan[:cfg][:label]} registry capacity: #{plan[:registry_max]} (#{plan[:cfg][:registry_max_name]})"
    wired_now = plan[:cfg][:wired_ids].call(mq5_content, level_fam_content)
    keep_count = (wired_now - plan[:delete_ids]).size
    puts "  Required slots after:      #{keep_count}"
    puts
  end

  print "Delete #{total_delete} #{type_label} algo(s) from selected families? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  registry_changes = []
  plans.each do |plan|
    next if plan[:delete_ids].empty?

    mq5_content, updated_level_fam, old_max, new_max =
      plan[:cfg][:apply_delete!].call(mq5_content, level_fam_content, plan[:delete_ids])
    level_fam_content = updated_level_fam if updated_level_fam
    registry_changes << [plan[:cfg][:label], plan[:cfg][:registry_max_name], old_max, new_max] if old_max != new_max
  end

  File.write(MQ5_FILE, mq5_content)
  File.write(LEVEL_FAM_FILE, level_fam_content) if DO_WHICH_FAMS.include?(:level) && level_fam_content

  puts "Deleted #{total_delete} #{type_label} algo(s):"
  plans.each do |plan|
    next if plan[:delete_ids].empty?

    puts "  #{plan[:cfg][:label]}: #{plan[:delete_ids].size} (#{plan[:delete_ids].join(', ')})"
  end

  registry_changes.each do |label, name, old_max, new_max|
    puts "#{label} #{name}: #{old_max} -> #{new_max}"
  end

  if algo_type == :quant
    puts "Re-run smash_from_QUANTREFERENCEPOINTS_creator.rb to recreate quant-ref clones."
  end

  puts MQ5_FILE
  puts LEVEL_FAM_FILE if DO_WHICH_FAMS.include?(:level)
end
