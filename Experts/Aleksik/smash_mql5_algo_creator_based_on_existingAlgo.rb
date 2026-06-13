#!/usr/bin/env ruby
# frozen_string_literal: true

# Creates a new algo in aleksik.mq5 by copying an existing one and optionally
# adding extra rules on top. Edits the four //algocreator* blocks.

require_relative 'smash_mql5_algo_creator_common'

include SmashMql5AlgoCreatorCommon

# --- CONFIG (edit before running) ---

copy_from_algo_id = 18

# Rules copied from copy_from_algo_id; uncommented lines below are ADDED (duplicates skipped).
# Shorthand below_PDH also accepts below_PDH=true.
extra_rules = <<~RULES
  # --- clean streak / anchor ---
  # cleanStreakLong
  # cleanStreakShort
  # cleanStreakTooLong
  # anchorAboveTooHigh

  # --- bounce / ceiling counts (tune-backed) ---
  # bounceCountTooHigh
  # bounceCountTooLow
  # recentBounceCountTooHigh
  # ceilingProximityCandlesTooHigh
  # ceilingCountTooHigh
  # ceilingCountTooLow
  # weekBounceCountTooLow
  # weekBounceCountTooHigh
  # weekCeilingCountTooLow
  # weekCeilingCountTooHigh
  # weekContactCandlesTooHigh

  # --- contact / ONO (tune-backed) ---
  # dayStartEarlierWeekContactTooHigh
  # dayContactTodayTooHigh
  # levelOnoAbsDiffTooLow
  # onoAboveLevelTooLow
  # onoBelowLevelTooLow

  # --- day high/low distance (tune or literal) ---
  # dayLowSoFarNoMoreThanXBelowLevel
  # dayLowSoFarAtLeastXBelowLevel=2.0
  # dayHighSoFarAtLeastXAboveLevel=2.0
  # dayHighSoFarNoMoreThanXAboveLevel=5.0

  # --- gap / RTHO (tune-backed) ---
  # rthoTertiaryReady
  # dayGapDownRequired
  # dayGapUpRequired
  # gapRangePtsAbove
  # gapFillPcBelow

  # --- day broke prior day high/low ---
  # dayBrokePDH=true
  # dayBrokePDH=false
  # dayBrokePDL=true
  dayBrokePDL=false

  # --- prior day trend ---
  # PD_trend=PD_green
  # PD_trend=PD_red

  # --- open gap ---
  # openGap_info=unknown
  # openGap_info=gapUp_Day
  # openGap_info=gapDown_Day

  # --- level tag ---
  # levelTag=dailyPivot
  # levelTag=dailyUp1
  # levelTag=todayRTHopen

  # --- session ---
  # session=ON
  # session=RTH-IB
  # session=RTH-afterIB
  # session=full

  # --- day of week (pick one) ---
  # day_of_week=MON
  # day_of_week=TUE
  # day_of_week=WED
  # day_of_week=THU
  # day_of_week=FRI

  # --- level vs PDO ---
  # below_PDO=true
  # above_PDO=true

  # --- level vs PDH / PDL / PDC ---
  below_PDH=true
  # above_PDH=true
  # below_PDL=true
  # above_PDL=true
  below_PDC=true
  # above_PDC=true

  # --- level vs ONH / ONL ---
  below_ONH=true
  # above_ONH=true
  below_ONL=true
  # above_ONL=true

  # --- level vs RTH high/low ---
  below_RTHH=true
  # above_RTHH=true
  below_RTHL=true
  # above_RTHL=true

  # --- level vs IB high/low ---
  below_IBL=true
  # above_IBL=true
  below_IBH=true
  # above_IBH=true

  # --- level vs day high/low so far ---
  below_dayHighSoFar=true
  # above_dayHighSoFar=true
  below_dayLowSoFar=true
  # above_dayLowSoFar=true

  # --- level vs midpoint ---
  below_midpoint=true
  # above_midpoint=true

  # --- weekly contact (literal min count; edit number) ---
  # weekContactCandlesTooLow=2
RULES

def run_copy_from!(copy_from:, extra_rules_text:)
  content = read_mq5
  new_id = next_unused_algo_id(content)
  source_id = copy_from.to_i

  raise "copy_from_algo_id must be >= #{MIN_ALGO_ID}" if source_id < MIN_ALGO_ID
  raise "Source algo #{source_id} not found in #{MQ5_FILE}" unless existing_algo_ids(content).include?(source_id)

  extra_tokens = selected_rule_tokens(extra_rules_text)

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
    run_copy_from!(copy_from: copy_from_algo_id, extra_rules_text: extra_rules)
  end
end
