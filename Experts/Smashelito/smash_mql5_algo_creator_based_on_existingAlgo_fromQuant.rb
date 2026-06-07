#!/usr/bin/env ruby
# frozen_string_literal: true

# Creates a new algo in smashelito.mq5 by copying an existing one and adding
# extra rules from a quant pipe-separated string, e.g.:
#   "above_ONH=true | above_PDC=true | levelTag=dailyUp1"
# Optional session gate (adds AlgoRuleAdd_Session):
#   session_rule_enabled = true
#   session_rule = "ON"  # full, ON, RTH-IB, RTH-afterIB (aliases: on, rthib, rthafterib)
#
# Usage: edit CONFIG below, then run:
#   ruby smash_mql5_algo_creator_based_on_existingAlgo_fromQuant.rb

require_relative 'smash_mql5_algo_creator_common'

include SmashMql5AlgoCreatorCommon

# --- CONFIG (edit before running) ---

copy_from_algo_id = 31

session_rule_enabled = true
session_rule = "ON" # full, ON, RTH-IB, RTH-afterIB (aliases: on, rthib, rthafterib)

extra_rules_quant = <<~QUANT.strip
above_ONL=true | above_PDL=true | above_PDO=true | above_dayLowSoFar=true | above_midpoint=true | below_ONH=true | below_dayHighSoFar=true | dayBrokePDL=false | openGap_info=unknown
QUANT

def run_copy_from_quant!(copy_from:, extra_rules_quant:, session_rule_enabled: false, session_rule: nil)
  content = read_mq5
  new_id = next_unused_algo_id(content)
  source_id = copy_from.to_i

  raise "copy_from_algo_id must be >= #{MIN_ALGO_ID}" if source_id < MIN_ALGO_ID
  raise "Source algo #{source_id} not found in #{MQ5_FILE}" unless existing_algo_ids(content).include?(source_id)

  extra_tokens = extra_rule_tokens_from_quant(
    extra_rules_quant: extra_rules_quant,
    session_rule_enabled: session_rule_enabled,
    session_rule: session_rule
  )

  b1 = extract_inner(content, 1)
  b2 = extract_inner(content, 2)
  b4 = extract_inner(content, 4)

  new_b1 = update_block1(b1, new_id)
  new_b2 = update_block2_copy(b2, source_id, new_id)
  new_b4 = append_rule_case_cloned_from(b4, source_id, new_id, extra_tokens)

  content = replace_inner(content, 1, new_b1)
  content = replace_inner(content, 2, new_b2)
  content = replace_inner(content, 4, new_b4)
  content = finalize_mq5!(content)

  write_mq5!(content)

  puts
  puts "Created algo #{new_id} (copy of algo #{source_id}) in #{MQ5_FILE}"
  puts "Extra rules added: #{extra_tokens.empty? ? '(none)' : extra_tokens.join(', ')}"
  if session_rule_enabled
    puts "Session rule: #{session_rule} -> #{session_rule_token(session_rule)}"
  end
  puts

  print_block(1, extract_inner(content, 1))
  print_block(2, extract_tune_block(new_b2, new_id))
  print_block(4, extract_rule_case_block_for_id(new_b4, new_id))

  new_id
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.include?('--normalize')
    content = read_mq5
    content = normalize_block1!(content)
    write_mq5!(content)
    puts "Normalized algocreator1 registry formatting in #{MQ5_FILE}"
    print_block(1, extract_inner(content, 1))
  else
    run_copy_from_quant!(
      copy_from: copy_from_algo_id,
      extra_rules_quant: extra_rules_quant,
      session_rule_enabled: session_rule_enabled,
      session_rule: session_rule
    )
  end
end
