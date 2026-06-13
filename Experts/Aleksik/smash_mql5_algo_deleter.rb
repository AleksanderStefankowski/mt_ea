#!/usr/bin/env ruby
# frozen_string_literal: true

# Deletes one or more algos from aleksik.mq5 (four //algocreator* blocks)
# and decrements ALGO_FAMILY_REGISTRY_MAX by 1 per deleted algo.

require_relative 'smash_mql5_algo_creator_common'

AlgoCreator = SmashMql5AlgoCreatorCommon
MIN_ALGO_ID = SmashMql5AlgoCreatorCommon::MIN_ALGO_ID
MQ5_FILE = SmashMql5AlgoCreatorCommon::MQ5_FILE

# --- CONFIG (edit before running) ---
# Delete highest id first when removing several (e.g. 32 then 31).
delete_algo_ids = [31]

module AlgoDeleter
  module_function

  def rebuild_block1_for_ids(inner, ids)
    lines = inner.lines.map(&:chomp)
    comment = lines.find { |l| l.include?('wired algo magic prefixes') } ||
              '// wired algo magic prefixes — add MAGIC_ALGO* define + id here + tune block in Sync'

    existing_by_id = {}
    lines.select { |l| l.match?(/#define\s+MAGIC_ALGO\d+/) }.each do |line|
      existing_by_id[line[/MAGIC_ALGO(\d+)/, 1].to_i] = line
    end

    sorted_ids = ids.uniq.sort
    define_lines = sorted_ids.map do |id|
      existing_by_id[id] || raise("MAGIC_ALGO#{id} define missing in algocreator1")
    end

    [define_lines, comment, '', AlgoCreator.format_registry_array(sorted_ids)].flatten.join("\n")
  end

  def delete_from_block1(inner, delete_id)
    ids = AlgoCreator.registry_ids_from_block1(inner)
    raise "Algo #{delete_id} not in algocreator1 registry" unless ids.include?(delete_id)

    rebuild_block1_for_ids(inner, ids - [delete_id])
  end

  def delete_from_block2(inner, delete_id)
    const = AlgoCreator.magic_const(delete_id)
    lines = inner.lines.map(&:chomp)
    prefix = "   g_algos[AlgoSlotIndexByAlgoId(#{const})]"
    start_idx = lines.index { |line| line.start_with?(prefix) }
    raise "Tune block for algo #{delete_id} not found in algocreator2" unless start_idx

    end_idx = start_idx
    end_idx += 1 while end_idx < lines.length && lines[end_idx].start_with?(prefix)

    remaining = lines[0...start_idx] + lines[end_idx..]
    remaining.join("\n").gsub(/\n{3,}/, "\n\n").rstrip
  end

  def delete_from_block4(inner, delete_id)
    const = AlgoCreator.magic_const(delete_id)
    lines = inner.lines.map(&:chomp)
    case_idx = lines.index { |line| line.match?(/^\s*case\s+#{const}\s*:/) }
    raise "Rule case for algo #{delete_id} not found in algocreator4" unless case_idx

    break_idx = case_idx
    break_idx += 1 while break_idx < lines.length && !lines[break_idx].match?(/^\s*break\s*;/)
    raise "No break; after case #{const} in algocreator4" unless break_idx < lines.length

    start_idx = case_idx
    start_idx -= 1 if start_idx.positive? && lines[start_idx - 1].strip.empty?

    remaining = lines[0...start_idx] + lines[(break_idx + 1)..]
    remaining.join("\n").rstrip
  end

  def delete_one!(content, delete_id)
    delete_id = delete_id.to_i
    if delete_id < MIN_ALGO_ID
      puts "  Skipping algo #{delete_id}: id must be >= #{MIN_ALGO_ID}"
      return [content, false]
    end
    unless AlgoCreator.existing_algo_ids(content).include?(delete_id)
      puts "  Skipping algo #{delete_id}: not found in #{MQ5_FILE}"
      return [content, false]
    end

    b1 = AlgoCreator.extract_inner(content, 1)
    b2 = AlgoCreator.extract_inner(content, 2)
    b4 = AlgoCreator.extract_inner(content, 4)

    content = AlgoCreator.replace_inner(content, 1, delete_from_block1(b1, delete_id))
    content = AlgoCreator.replace_inner(content, 2, delete_from_block2(b2, delete_id))
    content = AlgoCreator.replace_inner(content, 4, delete_from_block4(b4, delete_id))
    [decrement_registry_max(content, by: 1), true]
  end

  def decrement_registry_max(content, by: 1)
    match = content.match(/#define\s+ALGO_FAMILY_REGISTRY_MAX\s+(\d+)/)
    raise 'ALGO_FAMILY_REGISTRY_MAX not found' unless match

    current = match[1].to_i
    new_val = current - by
    raise "ALGO_FAMILY_REGISTRY_MAX would become #{new_val}" if new_val < 1

    content.sub(
      /#define\s+ALGO_FAMILY_REGISTRY_MAX\s+\d+/,
      "#define ALGO_FAMILY_REGISTRY_MAX  #{new_val}"
    )
  end

  def run(delete_ids:)
    ids = delete_ids.map(&:to_i).uniq
    raise 'No algo ids to delete' if ids.empty?

    content = AlgoCreator.read_mq5
    initial_max = content[/ALGO_FAMILY_REGISTRY_MAX\s+(\d+)/, 1].to_i
    deleted_ids = []

    ids.each do |delete_id|
      puts "Deleting algo #{delete_id}..."
      content, deleted = delete_one!(content, delete_id)
      deleted_ids << delete_id if deleted
    end

    if deleted_ids.any?
      content = AlgoCreator.normalize_block1!(content)
      AlgoCreator.write_mq5!(content)
    end

    final_max = content[/ALGO_FAMILY_REGISTRY_MAX\s+(\d+)/, 1].to_i
    remaining = AlgoCreator.registry_ids(AlgoCreator.extract_inner(content, 1))
    skipped_ids = ids - deleted_ids

    puts
    puts "Deleted algos: #{deleted_ids.empty? ? '(none)' : deleted_ids.join(', ')}"
    puts "Skipped algos: #{skipped_ids.empty? ? '(none)' : skipped_ids.join(', ')}" unless skipped_ids.empty?
    puts "ALGO_FAMILY_REGISTRY_MAX: #{initial_max} -> #{final_max}" if deleted_ids.any?
    puts "Remaining wired algos (#{remaining.size}): #{remaining.join(', ')}"
    puts "Updated #{MQ5_FILE}" if deleted_ids.any?
    puts

    if deleted_ids.any?
      AlgoCreator.print_block(1, AlgoCreator.extract_inner(content, 1))
    end

    deleted_ids
  end
end

if __FILE__ == $PROGRAM_NAME
  ids = if ARGV.empty?
          delete_algo_ids
        else
          ARGV.map(&:to_i)
        end
  AlgoDeleter.run(delete_ids: ids)
end
