#!/usr/bin/env ruby
# frozen_string_literal: true

# Renumbers wired algos in aleksik.mq5 to contiguous ids from 100 upward:
# unquanted algos first (sorted by old id), then quanted algos (sorted by old id).

require_relative 'smash_mql5_algo_creator_common'
require_relative 'smash_mql5_algo_reader_lib'

AlgoCreator = SmashMql5AlgoCreatorCommon
MIN_ALGO_ID = SmashMql5AlgoCreatorCommon::MIN_ALGO_ID
MQ5_FILE = SmashMql5AlgoCreatorCommon::MQ5_FILE

# --- CONFIG (edit before running) ---
DRY_RUN = false

module AlgoFlattener
  module_function

  TUNE_PREFIX_RE = /^\s+g_algos\[AlgoSlotIndexByAlgoId\(MAGIC_ALGO(\d+)\)\]/
  CASE_LINE_RE = /^\s*case\s+MAGIC_ALGO(\d+)\s*:/

  def classify_algo_ids(content)
    src = content
    params = SmashMql5AlgoReader.params_by_algo_from_src(src)
    rules = SmashMql5AlgoReader.rules_by_algo_from_src(src, params)
    ids = AlgoCreator.registry_ids_from_block1(AlgoCreator.extract_inner(content, 1))

    unquanted = ids.reject { |id| SmashMql5AlgoReader.contains_quant_rule?(rules[id]) }.sort
    quanted = ids.select { |id| SmashMql5AlgoReader.contains_quant_rule?(rules[id]) }.sort
    [unquanted, quanted]
  end

  def build_id_mapping(unquanted_ids, quanted_ids)
    ordered_old = unquanted_ids + quanted_ids
    new_ids = (MIN_ALGO_ID...(MIN_ALGO_ID + ordered_old.length)).to_a

    old_to_new = ordered_old.each_with_index.to_h { |old_id, idx| [old_id, new_ids[idx]] }
    new_to_old = new_ids.each_with_index.to_h { |new_id, idx| [new_id, ordered_old[idx]] }
    [new_ids, old_to_new, new_to_old]
  end

  def already_flat?(old_ids, new_ids, old_to_new)
    old_ids == new_ids && old_to_new.all? { |old_id, new_id| old_id == new_id }
  end

  def rebuild_block1(inner, new_ids)
    lines = inner.lines.map(&:chomp)
    comment = lines.find { |l| l.include?('wired algo magic prefixes') } ||
              '// wired algo magic prefixes — add MAGIC_ALGO* define + id here + tune block in Sync'

    pad = 16
    define_lines = new_ids.map { |id| "#define #{AlgoCreator.magic_const(id)}#{' ' * pad}#{id}" }
    [define_lines, comment, '', AlgoCreator.format_registry_array(new_ids)].flatten.join("\n")
  end

  def extract_all_tune_blocks(inner)
    lines = inner.lines.map(&:chomp)
    blocks = {}
    i = 0
    while i < lines.length
      m = lines[i].match(TUNE_PREFIX_RE)
      unless m
        i += 1
        next
      end

      old_id = m[1].to_i
      start = i
      i += 1 while i < lines.length && lines[i].match?(TUNE_PREFIX_RE) && lines[i][/MAGIC_ALGO(\d+)/, 1].to_i == old_id
      blocks[old_id] = lines[start...i].join("\n")
    end
    blocks
  end

  def rebuild_block2(inner, new_ids, old_to_new)
    tune_blocks = extract_all_tune_blocks(inner)
    missing = old_to_new.keys.reject { |old_id| tune_blocks.key?(old_id) }
    raise "Tune block missing for algo(s): #{missing.sort.join(', ')}" if missing.any?

    new_ids.map do |new_id|
      old_id = old_to_new.key(new_id)
      AlgoCreator.clone_tune_block(tune_blocks.fetch(old_id), old_id, new_id)
    end.join("\n\n")
  end

  def extract_rule_case_groups(inner)
    lines = inner.lines.map(&:chomp)
    groups = []
    i = 0
    while i < lines.length
      unless lines[i].match?(CASE_LINE_RE)
        i += 1
        next
      end

      case_ids = []
      while i < lines.length && (m = lines[i].match(CASE_LINE_RE))
        case_ids << m[1].to_i
        i += 1
      end

      body = []
      while i < lines.length && !lines[i].match?(/^\s*break\s*;/)
        body << lines[i]
        i += 1
      end
      raise "No break; after case #{case_ids.join('/')}" if i >= lines.length

      groups << { ids: case_ids, body: body }
      i += 1
    end
    groups
  end

  def rule_body_by_old_id(inner)
    by_id = {}
    extract_rule_case_groups(inner).each do |group|
      group[:ids].each { |id| by_id[id] = group[:body] }
    end
    by_id
  end

  def format_rule_case(new_id, body_lines)
    out = ["      case #{AlgoCreator.magic_const(new_id)}:"]
    body_lines.each { |line| out << line }
    out << '         break;'
    out.join("\n")
  end

  def rebuild_block4(inner, new_ids, old_to_new)
    bodies = rule_body_by_old_id(inner)
    missing = old_to_new.keys.reject { |old_id| bodies.key?(old_id) }
    raise "Rule case missing for algo(s): #{missing.sort.join(', ')}" if missing.any?

    new_ids.map do |new_id|
      old_id = old_to_new.key(new_id)
      format_rule_case(new_id, bodies.fetch(old_id))
    end.join("\n")
  end

  def print_mapping(unquanted_ids, quanted_ids, old_to_new)
    puts 'Planned remap (old -> new):'
    puts '  unquanted:'
    unquanted_ids.each { |old_id| puts "    #{old_id} -> #{old_to_new[old_id]}" }
    puts '  quanted:'
    quanted_ids.each { |old_id| puts "    #{old_id} -> #{old_to_new[old_id]}" }
    puts
  end

  def run(dry_run: false)
    content = AlgoCreator.read_mq5
    old_ids = AlgoCreator.registry_ids_from_block1(AlgoCreator.extract_inner(content, 1))
    unquanted_ids, quanted_ids = classify_algo_ids(content)
    new_ids, old_to_new, = build_id_mapping(unquanted_ids, quanted_ids)

    if already_flat?(old_ids, new_ids, old_to_new)
      puts 'Already flat: unquanted then quanted from 100 with no gaps.'
      puts "Wired algos (#{old_ids.size}): #{old_ids.join(', ')}"
      puts "  unquanted (#{unquanted_ids.size}): #{unquanted_ids.join(', ')}"
      puts "  quanted (#{quanted_ids.size}): #{quanted_ids.join(', ')}"
      return false
    end

    print_mapping(unquanted_ids, quanted_ids, old_to_new)

    b1 = AlgoCreator.extract_inner(content, 1)
    b2 = AlgoCreator.extract_inner(content, 2)
    b4 = AlgoCreator.extract_inner(content, 4)

    content = AlgoCreator.replace_inner(content, 1, rebuild_block1(b1, new_ids))
    content = AlgoCreator.replace_inner(content, 2, rebuild_block2(b2, new_ids, old_to_new))
    content = AlgoCreator.replace_inner(content, 4, rebuild_block4(b4, new_ids, old_to_new))
    content = AlgoCreator.finalize_mq5!(content)

    if dry_run
      puts 'Dry run only — file not written.'
      AlgoCreator.print_block(1, AlgoCreator.extract_inner(content, 1))
      return true
    end

    AlgoCreator.write_mq5!(content)
    puts "Flattened #{old_ids.size} algos -> #{new_ids.first}..#{new_ids.last}"
    puts "  unquanted (#{unquanted_ids.size}): #{unquanted_ids.join(', ')}"
    puts "  quanted (#{quanted_ids.size}): #{quanted_ids.join(', ')}"
    puts "Updated #{MQ5_FILE}"
    puts
    AlgoCreator.print_block(1, AlgoCreator.extract_inner(content, 1))
    true
  end
end

if __FILE__ == $PROGRAM_NAME
  AlgoFlattener.run(dry_run: DRY_RUN)
end
