#!/usr/bin/env ruby
# frozen_string_literal: true
# Deletes breakdown algos from aleksik2.mq5 except those listed in PRESERVE_ALGO_IDS_TEXT.

require_relative "smash_BREAKDOWN_creator_from_combinations"

PRESERVE_ALGO_IDS_TEXT = <<~TEXT
  20000000
TEXT

module BreakdownCombinationsDeleter
  module_function

  def parse_id_list(text)
    text.lines.map(&:strip).reject(&:empty?).grep(/\A\d+\z/).map(&:to_i)
  end

  def delete_ids_for(wired_ids, preserve_ids)
    wired_ids - preserve_ids
  end

  def delete_params_block(inner, algo_id)
    const = magic_const(algo_id)
    lines = inner.lines.map(&:chomp)
    prefix_re = /^\s*g_breakdownAlgos\[BreakdownAlgoSlotIndexByAlgoId\(#{const}\)\]/
    start_idx = lines.index { |line| line.match?(prefix_re) }
    raise "Params block for algo #{algo_id} not found in breakdowncreator2" unless start_idx

    end_idx = start_idx
    end_idx += 1 while end_idx < lines.length && lines[end_idx].match?(prefix_re)

    trailing_blank = end_idx
    trailing_blank += 1 while trailing_blank < lines.length && lines[trailing_blank].strip.empty?

    remaining = lines[0...start_idx] + lines[trailing_blank..]
    remaining.join("\n").gsub(/\n{3,}/, "\n\n").rstrip
  end

  def delete_rule_case(inner, algo_id)
    const = magic_const(algo_id)
    lines = inner.lines.map(&:chomp)
    case_idx = lines.index { |line| line.match?(/^\s*case\s+#{const}\s*:/) }
    raise "Rule case for algo #{algo_id} not found in breakdowncreator4" unless case_idx

    break_idx = case_idx
    break_idx += 1 while break_idx < lines.length && !lines[break_idx].match?(/^\s*break\s*;/)
    raise "No break; after case #{const} in breakdowncreator4" unless break_idx < lines.length

    start_idx = case_idx
    start_idx -= 1 if start_idx.positive? && lines[start_idx - 1].strip.empty?

    trailing_blank = break_idx + 1
    trailing_blank += 1 while trailing_blank < lines.length && lines[trailing_blank].strip.empty?

    remaining = lines[0...start_idx] + lines[trailing_blank..]
    remaining.join("\n").rstrip
  end

  def delete_algos!(content, delete_ids)
    remaining_ids = registry_algo_ids(content) - delete_ids
    raise "Cannot delete all breakdown algos" if remaining_ids.empty?

    inner1 = rebuild_registry_inner(remaining_ids)
    inner2 = extract_inner(content, 2)
    inner4 = extract_inner(content, 4)

    delete_ids.each do |algo_id|
      inner2 = delete_params_block(inner2, algo_id)
      inner4 = delete_rule_case(inner4, algo_id)
    end

    content = replace_inner(content, 1, inner1)
    content = replace_inner(content, 2, inner2)
    replace_inner(content, 4, inner4)
  end
end

include BreakdownCombinationsCreator
include BreakdownCombinationsDeleter

if __FILE__ == $PROGRAM_NAME
  preserve_ids = parse_id_list(PRESERVE_ALGO_IDS_TEXT).uniq.sort
  content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  registry_max = breakdown_registry_max(content)
  registry_headroom = breakdown_registry_max_headroom(content)
  wired_ids = registry_algo_ids(content)
  delete_ids = delete_ids_for(wired_ids, preserve_ids).sort
  keep_ids = wired_ids - delete_ids
  required_registry_max = compute_registry_max_for_wired_count(keep_ids.size)

  puts "Registry slot capacity:    #{registry_max} (BREAKDOWN_ALGO_REGISTRY_MAX in aleksik2.mq5)"
  puts "Registry headroom:         #{registry_headroom} (max unused slots above wired count)"
  puts "Wired breakdown algos:     #{wired_ids.empty? ? '(none)' : wired_ids.join(', ')}"
  puts "Preserve list:             #{preserve_ids.empty? ? '(none)' : preserve_ids.join(', ')}"
  puts
  puts "Will delete:               #{delete_ids.empty? ? '(none)' : delete_ids.join(', ')}"
  puts "Will keep:                 #{keep_ids.empty? ? '(none)' : keep_ids.join(', ')}"
  if delete_ids.any?
    puts "Required registry slots:   #{required_registry_max} (after delete)"
    if required_registry_max != registry_max
      verb = required_registry_max > registry_max ? "raise" : "lower"
      puts "Will #{verb} BREAKDOWN_ALGO_REGISTRY_MAX: #{registry_max} -> #{required_registry_max}"
    end
  end
  puts

  if delete_ids.empty?
    puts "No breakdown algos to delete."
    exit 0
  end

  missing_preserve = preserve_ids - wired_ids
  if missing_preserve.any?
    puts "Warning: preserve list includes unwired algos: #{missing_preserve.join(', ')}"
    puts
  end

  print "Delete #{delete_ids.size} breakdown algo(s) from #{MQ5_FILE}? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  updated = delete_algos!(content, delete_ids)
  updated = set_breakdown_registry_max(updated, required_registry_max) if required_registry_max != registry_max
  File.write(MQ5_FILE, updated)

  remaining = registry_algo_ids(updated)
  final_registry_max = breakdown_registry_max(updated)
  puts "Deleted #{delete_ids.size} breakdown algo(s): #{delete_ids.join(', ')}"
  puts "Remaining wired algos (#{remaining.size}): #{remaining.join(', ')}"
  puts "BREAKDOWN_ALGO_REGISTRY_MAX: #{registry_max} -> #{final_registry_max}" if required_registry_max != registry_max
  puts MQ5_FILE
end
