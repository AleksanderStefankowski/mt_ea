#!/usr/bin/env ruby
# frozen_string_literal: true
# Read analyze_referencePoints_*_output.csv -> append quant-ref-gated algos in aleksik2.mq5 (+ level_fam for level).

DO_WHICH_FAMS = [
  :level,
  :time,
  :breakdown
].freeze

# Per base algo, per creation mode (deduped when both modes pick the same quant).
CREATE_HOW_MANY_PER_ALGOID_PER_CREATION_MODE_LEVEL = 3
CREATE_HOW_MANY_PER_ALGOID_PER_CREATION_MODE_TIME = 3
CREATE_HOW_MANY_PER_ALGOID_PER_CREATION_MODE_BREAKDOWN = 1

CREATE_HOW_MANY_PER_ALGOID_PER_CREATION_MODE_BY_FAM = {
  level: CREATE_HOW_MANY_PER_ALGOID_PER_CREATION_MODE_LEVEL,
  time: CREATE_HOW_MANY_PER_ALGOID_PER_CREATION_MODE_TIME,
  breakdown: CREATE_HOW_MANY_PER_ALGOID_PER_CREATION_MODE_BREAKDOWN
}.freeze
CREATE_HOW_MANY_PER_FAM_PER_CREATION_MODE = 999999 # e.g. write 10 if u only want top 10 from each fam and each creation mode

CREATION_MODE = [
  :best_timevsprofit,
  :best_timeVSprofitVSratecut
].freeze

require "csv"
require "set"
require_relative "../Aleksik_traderesults2_breakdown/analyze_referencePoints_common"
require_relative "smash_from_CATALOG_creator_common"
require_relative "smash_BREAKDOWN_creator_from_combinations"
require_relative "smash_LEVEL_create_From_combinations"
require_relative "smash_TIME_creator_common"
require_relative "../Aleksik/smash_mql5_algo_reader_lib"

MQ5_FILE = File.expand_path("aleksik2.mq5", __dir__)
LEVEL_FAM_FILE = File.expand_path("aleksik2_level_fam.mqh", __dir__)

REFERENCE_POINTS_DIR = File.expand_path("../Aleksik_traderesults2_breakdown", __dir__)

LEVEL_RULE_MARKERS = %w[//levelalgocreator3start //levelalgocreator3end].freeze
TIME_RULE_MARKERS = %w[//timealgocreator3start //timealgocreator3end].freeze
BREAKDOWN_REGISTRY_MARKERS = %w[//breakdowncreator1start //breakdowncreator1end].freeze
BREAKDOWN_PARAMS_MARKERS = %w[//breakdowncreator2start //breakdowncreator2end].freeze
BREAKDOWN_RULES_MARKERS = %w[//breakdowncreator4start //breakdowncreator4end].freeze

REF_SUFFIX = {
  "dayHighSoFar" => "DayHighSoFar",
  "dayLowSoFar" => "DayLowSoFar",
  "midpoint" => "Midpoint"
}.freeze

REF_RULE_ABOVE = {
  "PDO" => "RULE_LEVEL_BELOW_PDO",
  "PDH" => "RULE_LEVEL_BELOW_PDH",
  "PDL" => "RULE_LEVEL_BELOW_PDL",
  "PDC" => "RULE_LEVEL_BELOW_PDC",
  "ONH" => "RULE_LEVEL_BELOW_ONH",
  "ONL" => "RULE_LEVEL_BELOW_ONL",
  "RTHH" => "RULE_LEVEL_BELOW_RTHH",
  "RTHL" => "RULE_LEVEL_BELOW_RTHL",
  "IBH" => "RULE_LEVEL_BELOW_IBH",
  "IBL" => "RULE_LEVEL_BELOW_IBL",
  "dayHighSoFar" => "RULE_LEVEL_BELOW_DAY_HIGH",
  "dayLowSoFar" => "RULE_LEVEL_BELOW_DAY_LOW",
  "midpoint" => "RULE_LEVEL_BELOW_MIDPOINT"
}.freeze

REF_RULE_BELOW = {
  "PDO" => "RULE_LEVEL_ABOVE_PDO",
  "PDH" => "RULE_LEVEL_ABOVE_PDH",
  "PDL" => "RULE_LEVEL_ABOVE_PDL",
  "PDC" => "RULE_LEVEL_ABOVE_PDC",
  "ONH" => "RULE_LEVEL_ABOVE_ONH",
  "ONL" => "RULE_LEVEL_ABOVE_ONL",
  "RTHH" => "RULE_LEVEL_ABOVE_RTHH",
  "RTHL" => "RULE_LEVEL_ABOVE_RTHL",
  "IBH" => "RULE_LEVEL_ABOVE_IBH",
  "IBL" => "RULE_LEVEL_ABOVE_IBL",
  "dayHighSoFar" => "RULE_LEVEL_ABOVE_DAY_HIGH",
  "dayLowSoFar" => "RULE_LEVEL_ABOVE_DAY_LOW",
  "midpoint" => "RULE_LEVEL_ABOVE_MIDPOINT"
}.freeze

module QuantRefCreator
  module_function

  def reference_points_csv_path(family)
    File.join(REFERENCE_POINTS_DIR, "analyze_referencePoints_#{family}_output.csv")
  end

  def split_refs(value)
    value.to_s.split(";").map(&:strip).reject(&:empty?)
  end

  def ref_suffix(ref)
    REF_SUFFIX.fetch(ref, ref)
  end

  def load_grouped_rows(path)
    raise "Missing reference-points CSV: #{path}" unless File.exist?(path)

    raw = File.read(path, encoding: "bom|utf-8")
    table = CSV.parse(raw, headers: true, col_sep: ",")
    table.filter_map do |csv_row|
      row = csv_row.to_h.transform_keys(&:to_s).transform_values { |v| v.to_s.strip }
      group_size = row["refGroupSize"].to_i
      # Skip ungrouped baseline rows (refGroupSize 0); grouped sizes come from the analyzer CSV.
      next if group_size == AnalyzeAlgosReferencePointsCommon::UNGROUPED_REF_GROUP_SIZE

      {
        algo_id: row["algoID"].to_i,
        ref_group_size: group_size,
        grp_refs_above: row["grpRefsAbove"],
        grp_refs_below: row["grpRefsBelow"],
        ratecut: row["ratecut"],
        time_vs_profit: row["timeVSprofit"].to_f,
        time_vs_profit_vs_ratecut: row["timeVSprofitVSratecut"].to_f,
        percent_sum_w_roll: row["percentSum_w_roll"],
        trades_count: row["tradesCount"].to_i,
        pattern: row["pattern"]
      }
    end
  end

  def sort_metric(row, mode)
    case mode
    when :best_timevsprofit then row[:time_vs_profit]
    when :best_timeVSprofitVSratecut then row[:time_vs_profit_vs_ratecut]
    else raise "Unknown creation mode: #{mode.inspect}"
    end
  end

  def selection_signature(row)
    [row[:algo_id], row[:grp_refs_above].to_s, row[:grp_refs_below].to_s]
  end

  QUANTREF_SIGNATURE_RE =
    /(?:\/\/\s*)?quantref\s+base=(\d+)\s+new=(\d+)\s+modes=\S+\s+above=(\S+)\s+below=(\S+)/

  QUANTREF_NEW_ID_RE = /(?:\/\/\s*)?quantref\s+base=\d+\s+new=(\d+)/

  def quant_clone_algo_ids(*contents)
    contents.compact.join.scan(QUANTREF_NEW_ID_RE).flatten.map(&:to_i).uniq.sort
  end

  def quantref_signature_from_match(base, _new_id, above, below)
    [base.to_i, above == "-" ? "" : above, below == "-" ? "" : below]
  end

  # Returns { selection_signature => existing_new_algo_id } from quantref comments in mq5/level_fam.
  def existing_quantref_signatures(*contents)
    by_sig = {}
    contents.compact.join.scan(QUANTREF_SIGNATURE_RE) do |base, new_id, above, below|
      sig = quantref_signature_from_match(base, new_id, above, below)
      by_sig[sig] ||= new_id.to_i
    end
    by_sig
  end

  def filter_rows_already_defined(rows, existing_by_sig)
    skipped = []
    kept = rows.select do |row|
      sig = selection_signature(row)
      if existing_by_sig.key?(sig)
        skipped << { row: row, existing_algo_id: existing_by_sig[sig] }
        false
      else
        true
      end
    end
    { rows: kept, skipped: skipped }
  end

  def creation_modes_for(row)
    row[:creation_modes] || [row[:creation_mode]].compact
  end

  def select_creations(rows, modes, per_algo_limit, total_limit_per_mode)
    selected_by_sig = {}
    dedup_skipped = 0

    modes.each do |mode|
      mode_count = 0
      mode_candidates = rows.group_by { |row| row[:algo_id] }.flat_map do |_algo_id, algo_rows|
        algo_rows.sort_by { |row| -sort_metric(row, mode) }.first(per_algo_limit)
      end

      mode_candidates.sort_by! { |row| -sort_metric(row, mode) }.each do |row|
        break if mode_count >= total_limit_per_mode

        sig = selection_signature(row)
        existing = selected_by_sig[sig]
        if existing
          existing[:creation_modes] << mode unless existing[:creation_modes].include?(mode)
          dedup_skipped += 1
          next
        end

        selected_by_sig[sig] = row.merge(creation_mode: mode, creation_modes: [mode])
        mode_count += 1
      end
    end

    { rows: selected_by_sig.values, dedup_skipped: dedup_skipped }
  end

  def filter_rows_with_eligible_base_algos(rows, wired_base_ids, quant_clone_ids)
    wired = wired_base_ids.to_set
    quant_clones = quant_clone_ids.to_set
    skipped_not_wired = []
    skipped_quant_base = []

    kept = rows.select do |row|
      algo_id = row[:algo_id]
      unless wired.include?(algo_id)
        skipped_not_wired << algo_id
        next false
      end
      if quant_clones.include?(algo_id)
        skipped_quant_base << algo_id
        next false
      end
      true
    end

    {
      rows: kept,
      skipped_base_ids: skipped_not_wired.uniq.sort,
      skipped_quant_base_ids: skipped_quant_base.uniq.sort
    }
  end

  def wired_base_ids_for_family(family, mq5_content)
    case family
    when :breakdown then breakdown_wired_algo_ids(mq5_content)
    when :level then LevelCombinationsCreator.registry_algo_ids(mq5_content)
    when :time then TimeCombinationsCommon.registry_algo_ids(mq5_content)
    else raise "Unknown family #{family.inspect}"
    end
  end

  def breakdown_wired_algo_ids(mq5_content)
    block = mq5_content[/int\s+g_breakdownRegistryIds\[\]\s*=\s*\{([^}]+)\}/m, 1]
    return [] unless block

    block.scan(/MAGIC_BREAKDOWN(\d+)/).flatten.map(&:to_i).uniq.sort
  end

  def marker_line_re(marker)
    /^\s*#{Regexp.escape(marker)}\s*$/
  end

  def extract_inner(content, start_marker, end_marker)
    lines = content.lines
    start_idx = lines.index { |line| line.match?(marker_line_re(start_marker)) }
    end_idx = lines.index { |line| line.match?(marker_line_re(end_marker)) }
    unless start_idx && end_idx && end_idx > start_idx
      raise "Could not find block (#{start_marker} .. #{end_marker})"
    end

    lines[(start_idx + 1)...end_idx].join.rstrip
  end

  def replace_inner(content, start_marker, end_marker, new_inner)
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

  def extract_algo_lines(inner, magic_const)
    inner.lines.select { |line| line.include?(magic_const) }
  end

  def clone_algo_lines(lines, base_magic_const, new_magic_const, comment_suffix)
    lines.map do |line|
      line = line.gsub(base_magic_const, new_magic_const)
      if line.match?(/\.enabled\s*=/)
        stripped = line.rstrip
        "#{stripped.sub(/;\s*$/, '')};#{comment_suffix}\n"
      else
        line.end_with?("\n") ? line : "#{line}\n"
      end
    end.join.rstrip
  end

  def append_block(inner, block)
    return inner if block.strip.empty?
    return block if inner.strip.empty?

    inner.rstrip + "\n\n" + block
  end

  def append_rule_case_with_rules(inner, case_label, rule_lines, comment_suffix)
    return inner if inner.match?(/^\s*case\s+#{Regexp.escape(case_label)}\s*:/m)

    body = rule_lines.empty? ? "   break;" : (rule_lines + ["   break;"]).join("\n")
    inner.rstrip + "\n" + <<~MQL5.rstrip
      case #{case_label}:#{comment_suffix}
      #{body}
    MQL5
  end

  def quantref_comment(row, new_algo_id)
    modes = creation_modes_for(row).join(",")
    " // quantref base=#{row[:algo_id]} new=#{new_algo_id} modes=#{modes} " \
      "above=#{row[:grp_refs_above].empty? ? '-' : row[:grp_refs_above]} " \
      "below=#{row[:grp_refs_below].empty? ? '-' : row[:grp_refs_below]} " \
      "ratecut=#{row[:ratecut]} timeVSprofit=#{row[:time_vs_profit]} " \
      "percentSum_w_roll=#{row[:percent_sum_w_roll]} tradesCount=#{row[:trades_count]}"
  end

  def describe_row(row)
    primary_mode = row[:creation_mode] || creation_modes_for(row).first
    "base=#{row[:algo_id]} above=#{row[:grp_refs_above].empty? ? '-' : row[:grp_refs_above]} " \
      "below=#{row[:grp_refs_below].empty? ? '-' : row[:grp_refs_below]} " \
      "modes=#{creation_modes_for(row).join(',')} metric=#{sort_metric(row, primary_mode)} " \
      "percentSum_w_roll=#{row[:percent_sum_w_roll]} tradesCount=#{row[:trades_count]}"
  end

  def breakdown_rule_lines(refs_above, refs_below)
    split_refs(refs_above).map { |ref| "   AlgoRuleAdd_LevelBelow#{ref_suffix(ref)}(slotIdx);" } +
      split_refs(refs_below).map { |ref| "   AlgoRuleAdd_LevelAbove#{ref_suffix(ref)}(slotIdx);" }
  end

  def chain_rule_lines(chain_add_fn, refs_above, refs_below)
    above = split_refs(refs_above).map do |ref|
      rule = REF_RULE_ABOVE.fetch(ref) { raise "No above-ref rule mapping for #{ref.inspect}" }
      "   #{chain_add_fn}(slotIdx, #{rule});"
    end
    below = split_refs(refs_below).map do |ref|
      rule = REF_RULE_BELOW.fetch(ref) { raise "No below-ref rule mapping for #{ref.inspect}" }
      "   #{chain_add_fn}(slotIdx, #{rule});"
    end
    above + below
  end

  def apply_breakdown_rows!(mq5_content, rows)
    existing_ids = breakdown_wired_algo_ids(mq5_content)
    new_ids = BreakdownCombinationsCreator.next_algo_ids(existing_ids, rows.size)
    all_ids = (existing_ids + new_ids).uniq.sort
    required_registry_max = BreakdownCombinationsCreator.compute_registry_max_for_wired_count(all_ids.size)

    if required_registry_max > BreakdownCombinationsCreator.breakdown_registry_max(mq5_content)
      mq5_content = BreakdownCombinationsCreator.set_breakdown_registry_max(mq5_content, required_registry_max)
    end

    inner1 = BreakdownCombinationsCreator.rebuild_registry_inner(all_ids)
    inner2 = extract_inner(mq5_content, BREAKDOWN_PARAMS_MARKERS[0], BREAKDOWN_PARAMS_MARKERS[1])
    inner4 = extract_inner(mq5_content, BREAKDOWN_RULES_MARKERS[0], BREAKDOWN_RULES_MARKERS[1])

    rows.zip(new_ids).each do |row, new_algo_id|
      base_const = "MAGIC_BREAKDOWN#{row[:algo_id]}"
      new_const = "MAGIC_BREAKDOWN#{new_algo_id}"
      base_lines = extract_algo_lines(inner2, base_const)
      raise "Base breakdown algo #{row[:algo_id]} not found in breakdowncreator2 block" if base_lines.empty?

      comment = quantref_comment(row, new_algo_id)
      inner2 = append_block(inner2, clone_algo_lines(base_lines, base_const, new_const, comment))
      inner4 = append_rule_case_with_rules(
        inner4, new_const, breakdown_rule_lines(row[:grp_refs_above], row[:grp_refs_below]), comment
      )
    end

    mq5_content = replace_inner(mq5_content, BREAKDOWN_REGISTRY_MARKERS[0], BREAKDOWN_REGISTRY_MARKERS[1], inner1)
    mq5_content = replace_inner(mq5_content, BREAKDOWN_PARAMS_MARKERS[0], BREAKDOWN_PARAMS_MARKERS[1], inner2)
    replace_inner(mq5_content, BREAKDOWN_RULES_MARKERS[0], BREAKDOWN_RULES_MARKERS[1], inner4)
  end

  def apply_level_rows!(mq5_content, level_fam_content, rows)
    existing_ids = LevelCombinationsCreator.registry_algo_ids(mq5_content)
    new_ids = CatalogCreatorCommon.next_algo_ids(
      existing_ids, rows.size, LEVEL_ALGO_ID_MIN, LEVEL_ALGO_ID_MAX
    )
    all_ids = (existing_ids + new_ids).uniq.sort

    if all_ids.size > LevelCombinationsCreator.level_registry_max(mq5_content)
      mq5_content = LevelCombinationsCreator.set_level_registry_max(mq5_content, all_ids.size)
    end
    mq5_content = LevelCombinationsCreator.replace_magic_level_defines(mq5_content, all_ids)
    mq5_content = LevelCombinationsCreator.replace_inner(
      mq5_content, MQ5_MARKERS[1], LevelCombinationsCreator.rebuild_registry_inner(all_ids)
    )

    inner2 = LevelCombinationsCreator.extract_inner(level_fam_content, LEVEL_FAM_MARKERS[2])
    inner3 = extract_inner(mq5_content, LEVEL_RULE_MARKERS[0], LEVEL_RULE_MARKERS[1])

    rows.zip(new_ids).each do |row, new_algo_id|
      base_const = format("MAGIC_LEVEL%08d", row[:algo_id])
      new_const = format("MAGIC_LEVEL%08d", new_algo_id)
      base_lines = extract_algo_lines(inner2, base_const)
      raise "Base level algo #{row[:algo_id]} not found in levelalgocreator2 block" if base_lines.empty?

      comment = quantref_comment(row, new_algo_id)
      inner2 = append_block(inner2, clone_algo_lines(base_lines, base_const, new_const, comment))
      inner3 = append_rule_case_with_rules(
        inner3, new_const, chain_rule_lines("LevelRuleChainAdd", row[:grp_refs_above], row[:grp_refs_below]), comment
      )
    end

    level_fam_content = LevelCombinationsCreator.replace_inner(level_fam_content, LEVEL_FAM_MARKERS[2], inner2)
    mq5_content = replace_inner(mq5_content, LEVEL_RULE_MARKERS[0], LEVEL_RULE_MARKERS[1], inner3)
    [mq5_content, level_fam_content]
  end

  def apply_time_rows!(mq5_content, rows)
    existing_ids = TimeCombinationsCommon.registry_algo_ids(mq5_content)
    new_ids = CatalogCreatorCommon.next_algo_ids(
      existing_ids, rows.size, TIME_ALGO_ID_MIN, TIME_ALGO_ID_MAX
    )
    all_ids = (existing_ids + new_ids).uniq.sort
    required_registry_max = TimeCombinationsCommon.compute_registry_max_for_wired_count(all_ids.size)

    if required_registry_max > TimeCombinationsCommon.time_registry_max(mq5_content)
      mq5_content = TimeCombinationsCommon.set_time_registry_max(mq5_content, required_registry_max)
    end

    inner1 = TimeCombinationsCommon.rebuild_registry_inner(all_ids)
    inner2 = TimeCombinationsCommon.extract_inner(mq5_content, 2)
    inner3 = extract_inner(mq5_content, TIME_RULE_MARKERS[0], TIME_RULE_MARKERS[1])

    rows.zip(new_ids).each do |row, new_algo_id|
      base_const = TimeCombinationsCommon.time_const(row[:algo_id])
      new_const = TimeCombinationsCommon.time_const(new_algo_id)
      base_lines = extract_algo_lines(inner2, base_const)
      raise "Base time algo #{row[:algo_id]} not found in timealgocreator2 block" if base_lines.empty?

      comment = quantref_comment(row, new_algo_id)
      inner2 = append_block(inner2, clone_algo_lines(base_lines, base_const, new_const, comment))
      inner3 = append_rule_case_with_rules(
        inner3, new_const, chain_rule_lines("TimeRuleChainAdd", row[:grp_refs_above], row[:grp_refs_below]), comment
      )
    end

    mq5_content = TimeCombinationsCommon.replace_inner(mq5_content, 1, inner1)
    mq5_content = TimeCombinationsCommon.replace_inner(mq5_content, 2, inner2)
    replace_inner(mq5_content, TIME_RULE_MARKERS[0], TIME_RULE_MARKERS[1], inner3)
  end
end

if __FILE__ == $PROGRAM_NAME
  raise "DO_WHICH_FAMS is empty" if DO_WHICH_FAMS.empty?
  raise "CREATION_MODE is empty" if CREATION_MODE.empty?
  CREATE_HOW_MANY_PER_ALGOID_PER_CREATION_MODE_BY_FAM.each do |family, limit|
    raise "CREATE_HOW_MANY_PER_ALGOID_PER_CREATION_MODE_#{family.to_s.upcase} must be >= 1" if limit < 1
  end
  raise "CREATE_HOW_MANY_PER_FAM_PER_CREATION_MODE must be >= 1" if CREATE_HOW_MANY_PER_FAM_PER_CREATION_MODE < 1

  mq5_content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  level_fam_content = File.exist?(LEVEL_FAM_FILE) ? File.read(LEVEL_FAM_FILE, encoding: "bom|utf-8") : nil
  existing_quantref_by_sig = QuantRefCreator.existing_quantref_signatures(mq5_content, level_fam_content)
  quant_clone_ids = QuantRefCreator.quant_clone_algo_ids(mq5_content, level_fam_content)

  plans = DO_WHICH_FAMS.map do |family|
    path = QuantRefCreator.reference_points_csv_path(family)
    grouped_rows = QuantRefCreator.load_grouped_rows(path)
    selected = QuantRefCreator.select_creations(
      grouped_rows,
      CREATION_MODE,
      CREATE_HOW_MANY_PER_ALGOID_PER_CREATION_MODE_BY_FAM.fetch(family),
      CREATE_HOW_MANY_PER_FAM_PER_CREATION_MODE
    )
    filtered = QuantRefCreator.filter_rows_with_eligible_base_algos(
      selected[:rows],
      QuantRefCreator.wired_base_ids_for_family(family, mq5_content),
      quant_clone_ids
    )
    already = QuantRefCreator.filter_rows_already_defined(filtered[:rows], existing_quantref_by_sig)
    {
      family: family,
      path: path,
      grouped_count: grouped_rows.size,
      dedup_skipped: selected[:dedup_skipped],
      rows: already[:rows],
      skipped_base_ids: filtered[:skipped_base_ids],
      skipped_quant_base_ids: filtered[:skipped_quant_base_ids],
      skipped_already_defined: already[:skipped]
    }
  end

  total_create = plans.sum { |plan| plan[:rows].size }
  total_dedup_skipped = plans.sum { |plan| plan[:dedup_skipped] }
  puts "Quant reference-points algo creator"
  puts "Families:               #{DO_WHICH_FAMS.join(', ')}"
  puts "Creation modes:         #{CREATION_MODE.join(', ')}"
  puts "Per algo per mode:      #{CREATE_HOW_MANY_PER_ALGOID_PER_CREATION_MODE_BY_FAM.map { |fam, n| "#{fam}=#{n}" }.join(', ')}"
  puts "Cap per fam per mode:   #{CREATE_HOW_MANY_PER_FAM_PER_CREATION_MODE}"
  puts "Will create total:      #{total_create}"
  puts

  plans.each do |plan|
    puts "#{plan[:family]}: #{plan[:path]}"
    puts "  grouped rows in CSV: #{plan[:grouped_count]}"
    puts "  skipped (deduplication): #{plan[:dedup_skipped]}"
    puts "  selected to create:  #{plan[:rows].size}"
    unless plan[:skipped_base_ids].empty?
      puts "  skipped (base algo not wired in mq5): #{plan[:skipped_base_ids].join(', ')}"
    end
    unless plan[:skipped_quant_base_ids].empty?
      puts "  skipped (base is quant-ref clone, not original algo): #{plan[:skipped_quant_base_ids].join(', ')}"
    end
    unless plan[:skipped_already_defined].empty?
      puts "  skipped (already defined in mq5): #{plan[:skipped_already_defined].size}"
      plan[:skipped_already_defined].first(5).each do |entry|
        row = entry[:row]
        puts "    #{QuantRefCreator.describe_row(row)} -> algo #{entry[:existing_algo_id]}"
      end
      remaining = plan[:skipped_already_defined].size - 5
      puts "    ... and #{remaining} more" if remaining.positive?
    end
    plan[:rows].each { |row| puts "    #{QuantRefCreator.describe_row(row)}" }
    puts
  end

  if total_create.zero?
    puts "No quant-ref algos to create."
    exit 0
  end

  puts "Skipped (deduplication): #{total_dedup_skipped}"
  print "Create #{total_create} quant-ref algo(s) in #{MQ5_FILE}"
  print " + #{LEVEL_FAM_FILE}" if plans.any? { |plan| plan[:family] == :level }
  print "? [y/N] "
  unless $stdin.gets&.strip&.downcase == "y"
    puts "Aborted."
    exit 0
  end

  plans.each do |plan|
    next if plan[:rows].empty?

    case plan[:family]
    when :breakdown
      mq5_content = QuantRefCreator.apply_breakdown_rows!(mq5_content, plan[:rows])
    when :level
      raise "Missing #{LEVEL_FAM_FILE}" if level_fam_content.nil?

      mq5_content, level_fam_content = QuantRefCreator.apply_level_rows!(
        mq5_content, level_fam_content, plan[:rows]
      )
    when :time
      mq5_content = QuantRefCreator.apply_time_rows!(mq5_content, plan[:rows])
    else
      raise "Unknown family #{plan[:family].inspect}"
    end
  end

  File.write(MQ5_FILE, mq5_content)
  File.write(LEVEL_FAM_FILE, level_fam_content) if level_fam_content

  puts "Created #{total_create} quant-ref algo(s)."
  puts MQ5_FILE
  puts LEVEL_FAM_FILE if level_fam_content
end
