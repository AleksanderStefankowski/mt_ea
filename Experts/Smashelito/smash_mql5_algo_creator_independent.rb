#!/usr/bin/env ruby
# frozen_string_literal: true

# Creates a new algo in smashelito.mq5 from scratch (no copy-from source).
# Writes a full tune block (every AlgoDef field) and rules from uncommented lines below.
# Edits algocreator1 (registry), algocreator2 (tune), algocreator4 (rules).
# algocreator3 is a fixed per-algo level-flag validation loop — not edited by this script.

require_relative 'smash_mql5_algo_creator_common'

include SmashMql5AlgoCreatorCommon

# --- CONFIG (edit before running) ---
# Configured below to recreate algo 29 (next run creates a new algo id with same tune + rules).

# Uncomment key=value lines to override defaults. Every field is still written to mq5.
# At least one of tradesWeeklyLevels, tradesDailyLevels, tradesTertiaryTodayRTHOLevel must be true.
tune_overrides = <<~TUNE
  # --- placement / side (algo 29) ---
  trades_short=ALGO_SIDE_SHORT
  enabled=true
  tradesWeeklyLevels=true
  tradesDailyLevels=false
  # tradesTertiaryTodayRTHOLevel=false

  # --- per-algo stop counts ---
  tune.stop_trading_today_if_thisAlgo_losing_trades_count=2
  tune.stop_trading_today_if_thisAlgo_winning_trades_count=4
  tune.stop_trading_today_if_thisAlgo_total_trades_count=7

  # --- mode switching tune ---
  tune.babysitStart_minute=0
  tune.neutral_trade_TP=2.1
  tune.strong_trade_TP=3.8
  tune.strong_trade_mode_enabled=true
  tune.neutral_trade_mode_enabled=true
  tune.badtrade_mode_enabled=true
  tune.terribletrade_mode_enabled=true
  tune.strong_trade_eval_min_profit_pts=1.8
  tune.strong_trade_min_velocity_trigger=0.4
  tune.strong_trade_velocity_window_seconds=10
  # tune.strong_trade_stall_mode_uses_avgvelocity_weakening=false
  tune.strong_trade_stall_velocity_max_trigger=0.1
  tune.strong_trade_stall_giveback_pts_trigger=99.0
  # tune.strong_trade_stall_avgvelocity_weaken_pct=0.0
  tune.strong_trade_stall_min_close_profit_pts=2.5
  tune.telemetry_velocity_window_seconds=10
  tune.telemetry_avg_velocity_window_seconds=10
  tune.start_mae_care_after_x_seconds=90
  tune.badtrade_MaePostX_trigger=-4.0
  tune.badtrade_totalRedSeconds_minTrigger=90
  tune.badtrade_try_save_TP=1.0
  tune.terribletrade_MaePostX_trigger=-5.5
  tune.terribletrade_consecutiveRedSeconds_minTrigger=90
  tune.terribletrade_avgProfitVelocity10_trigger=0.02
  tune.terribletrade_try_smaller_loss_TP=-2.0

  # --- order placement (algo 29) ---
  levelOffset=0.4
  priceProximity=4.5
  expiry_minutes=5

  # --- lookbacks ---
  # recentBounceCountToday_Minutes=0
  # recentCeilingCountToday_Minutes=0

  # --- clean streak / anchor ---
  # min_anchorAbove_cleanStreak=0.0
  # max_anchorAbove_cleanStreak=0.0
  # min_anchorBelow_cleanStreak=11.0
  # min_cleanOHLC_streak_count=2
  # max_cleanOHLC_streak_count=0

  # --- bounce / ceiling (algo 29) ---
  # bounceMaxAllowed_today=0
  # min_bounceCount=0
  # recentBounceCount_max_allowed=0
  physicalCeilingMaxAllowed_today=0
  # proximityCeilingMaxAllowed_today=0
  max_allowed_trades_perLevel_perDay_forThisAlgo=1

  # --- weekly bounce / ceiling / contact ---
  # min_weekly_bounce_required=0
  # max_weekly_bounce_allowed=0
  # min_ceilingCount=0
  # min_weekly_ceiling_required=0
  # max_weekly_ceiling_allowed=0
  # max_weekly_contact_candles_allowed=-1

  # --- ONO / contact ---
  # min_levelOnoAbsDiff=0.0
  # min_onoAboveLevel=1.0
  # min_onoBelowLevel=0.0
  # max_daystart_earlierWeek_contactAndProx_allowed=-1
  # max_intraday_contactAndProx_today_allowed=-1

  # --- day range / gap ---
  # max_dayLowSoFar_belowLevel_dist=0.0
  # min_gap_range_pts_exclusive=0.0
  # max_gap_fill_pc_exclusive=0.0
TUNE

# Uncomment rules to include. Shorthand below_PDH also accepts below_PDH=true.
rules = <<~RULES
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
  ceilingCountTooHigh
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
  # dayBrokePDL=false

  # --- prior day trend ---
  # PD_trend=PD_green
  # PD_trend=PD_red

  # --- open gap ---
  # openGap_info=unknown
  # openGap_info=gapUp_Day
  # openGap_info=gapDown_Day

  # --- level tag ---
  # levelTag=dailySmash
  # levelTag=dailyUp1
  # levelTag=todayRTHopen

  # --- session ---
  # session=ON
  session=RTH-IB
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
  # below_RTHH=true
  # above_RTHH=true
  # below_RTHL=true
  # above_RTHL=true

  # --- level vs IB high/low ---
  # below_IBL=true
  # above_IBL=true
  # below_IBH=true
  # above_IBH=true

  # --- level vs day high/low so far ---
  below_dayHighSoFar=true
  # above_dayHighSoFar=true
  # below_dayLowSoFar=true
  # above_dayLowSoFar=true

  # --- level vs midpoint ---
  below_midpoint=true
  # above_midpoint=true

  # --- weekly contact (literal min count; edit number) ---
  # weekContactCandlesTooLow=2
RULES

def run_independent!(tune_overrides_text:, rules_text:)
  content = read_mq5
  new_id = next_unused_algo_id(content)
  tune = parse_key_value_lines(tune_overrides_text)
  rule_tokens = selected_rule_tokens(rules_text)

  raise 'rules has no uncommented entries — uncomment at least one rule' if rule_tokens.empty?

  b1 = extract_inner(content, 1)
  b2 = extract_inner(content, 2)
  b4 = extract_inner(content, 4)

  new_b1 = update_block1(b1, new_id)
  new_b2 = append_tune_block(b2, new_id, tune)
  new_b4 = append_rule_case(b4, new_id, rule_tokens)

  content = replace_inner(content, 1, new_b1)
  content = replace_inner(content, 2, new_b2)
  content = replace_inner(content, 4, new_b4)
  content = finalize_mq5!(content)

  write_mq5!(content)

  puts
  puts "Created independent algo #{new_id} in #{MQ5_FILE}"
  puts "Tune: full AlgoDef field set (#{TUNE_FIELD_DEFAULTS.size} fields, #{tune.size} override(s) applied)"
  puts "Rules (#{rule_tokens.size}): #{rule_tokens.join(', ')}"
  puts

  print_block(1, extract_inner(content, 1))
  print_block(2, extract_tune_block(new_b2, new_id))
  print_block(4, extract_rule_case_block_for_id(new_b4, new_id))

  new_id
end

if __FILE__ == $PROGRAM_NAME
  run_independent!(
    tune_overrides_text: tune_overrides,
    rules_text: rules
  )
end
