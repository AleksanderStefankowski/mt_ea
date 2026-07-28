#!/usr/bin/env ruby
# frozen_string_literal: true
# Deletes time algos from aleksik2.mq5 except those listed in PRESERVE_ALGO_IDS_TEXT.

require_relative "smash_TIME_creator_common"

# Edit algo ids to preserve. Blank lines and # comments are ignored.
PRESERVE_ALGO_IDS_TEXT = <<~TEXT

TEXT

module TimeCombinationsDeleter
  module_function

  def delete_ids_for(wired_ids, preserve_ids)
    wired_ids - preserve_ids
  end

  def delete_params_block(inner, algo_id)
    const = TimeCombinationsCommon.time_const(algo_id)
    lines = inner.lines.map(&:chomp)
    prefix_re = /^\s*g_timeAlgos\[TimeAlgoSlotIndexByAlgoId\(#{const}\)\]/
    start_idx = lines.index { |line| line.match?(prefix_re) }
    raise "Params block for algo #{algo_id} not found in timealgocreator2" unless start_idx

    end_idx = start_idx
    end_idx += 1 while end_idx < lines.length && lines[end_idx].match?(prefix_re)

    trailing_blank = end_idx
    trailing_blank += 1 while trailing_blank < lines.length && lines[trailing_blank].strip.empty?

    remaining = lines[0...start_idx] + lines[trailing_blank..]
    remaining.join("\n").gsub(/\n{3,}/, "\n\n").rstrip
  end

  def delete_algos!(content, delete_ids)
    remaining_ids = TimeCombinationsCommon.registry_algo_ids(content) - delete_ids

    inner1 = TimeCombinationsCommon.rebuild_registry_inner(remaining_ids)
    inner2 = TimeCombinationsCommon.extract_inner(content, 2)

    delete_ids.each do |algo_id|
      inner2 = delete_params_block(inner2, algo_id)
    end

    content = TimeCombinationsCommon.replace_inner(content, 1, inner1)
    TimeCombinationsCommon.replace_inner(content, 2, inner2)
  end
end

include TimeCombinationsCommon
include TimeCombinationsDeleter

if __FILE__ == $PROGRAM_NAME
  preserve_ids = parse_id_list(PRESERVE_ALGO_IDS_TEXT)
  content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  registry_max = time_registry_max(content)
  registry_headroom = time_registry_max_headroom(content)
  wired_ids = registry_algo_ids(content)
  delete_ids = delete_ids_for(wired_ids, preserve_ids).sort
  keep_ids = wired_ids - delete_ids
  required_registry_max = compute_registry_max_for_wired_count(keep_ids.size)

  puts "Registry slot capacity:    #{registry_max} (TIME_ALGO_REGISTRY_MAX in aleksik2.mq5)"
  puts "Registry headroom:         #{registry_headroom} (max unused slots above wired count)"
  puts "Wired time algos:          #{wired_ids.empty? ? '(none)' : wired_ids.join(', ')}"
  puts "Preserve list:             #{preserve_ids.empty? ? '(none)' : preserve_ids.join(', ')}"
  puts
  puts "Will delete:               #{delete_ids.empty? ? '(none)' : delete_ids.join(', ')}"
  puts "Will keep:                 #{keep_ids.empty? ? '(none)' : keep_ids.join(', ')}"
  if delete_ids.any?
    puts "Required registry slots:   #{required_registry_max} (after delete)"
    if required_registry_max != registry_max
      verb = required_registry_max > registry_max ? "raise" : "lower"
      puts "Will #{verb} TIME_ALGO_REGISTRY_MAX: #{registry_max} -> #{required_registry_max}"
    end
  end
  puts

  if delete_ids.empty?
    puts "No time algos to delete."
    exit 0
  end

  missing_preserve = preserve_ids - wired_ids
  if missing_preserve.any?
    puts "Warning: preserve list includes unwired algos: #{missing_preserve.join(', ')}"
    puts
  end

  print "Delete #{delete_ids.size} time algo(s) from #{MQ5_FILE}? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  updated = delete_algos!(content, delete_ids)
  updated = set_time_registry_max(updated, required_registry_max) if required_registry_max != registry_max
  File.write(MQ5_FILE, updated)

  remaining = registry_algo_ids(updated)
  final_registry_max = time_registry_max(updated)
  puts "Deleted #{delete_ids.size} time algo(s): #{delete_ids.join(', ')}"
  puts "Remaining wired algos (#{remaining.size}): #{remaining.join(', ')}"
  puts "TIME_ALGO_REGISTRY_MAX: #{registry_max} -> #{final_registry_max}" if required_registry_max != registry_max
  puts MQ5_FILE
end
