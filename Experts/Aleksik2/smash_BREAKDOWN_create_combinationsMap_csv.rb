#!/usr/bin/env ruby
# frozen_string_literal: true
# Cartesian product of desired_* arrays -> combinationsMap.csv (no aleksik2 edits).
# overwrite_csv = true: replace combinationsMap.csv entirely from grid (all tested?=false).
# overwrite_csv = false: merge into existing combinationsMap.csv when present:
#   - matching rows (all fields except tested?): keep tested? from file
#   - new grid combos: append with tested?=false
#   - rows only in old file (dropped from grid): kept at end
#   - duplicate signatures: one row only (tested?=true wins when merging dupes in file)

require "csv"

overwrite_csv = false

OUT_CSV = File.expand_path("combinationsMap.csv", __dir__)

BREAKDOWN_TYPE_TO_MODE = {
  "CLOSES" => "BREAKDOWN_STREAK_CONTINUATION_CLOSES",
  "OHLC_AVG" => "BREAKDOWN_STREAK_CONTINUATION_OHLC_AVG",
  "LOW" => "BREAKDOWN_STREAK_CONTINUATION_LOW",
  "OC_MID" => "BREAKDOWN_STREAK_CONTINUATION_OC_MID",
  "HL_MID" => "BREAKDOWN_STREAK_CONTINUATION_HL_MID"
}.freeze

# All breakdown-algo-specific fields needed to recreate an algo from the map alone.
COMBINATION_MAP_FIELDS = %w[
  tested?
  enabled
  stop_trading_today_if_thisAlgo_losing_trades_count
  stop_trading_today_if_thisAlgo_winning_trades_count
  stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
  expiry_minutes
  this_algo_max_concurrent_pending_trades
  min_breakdown_sequence_len
  max_breakdown_sequence_len
  breakdown_streak_continuation_mode
  breakdowntype
  bd_start_min_breakdown_percent
  min_breakdown_total_percent
  after_bd_need_x_15greenc
  entry_max_minutes_after_bdend
  forget_about_latest_breakdown_after_x_15m_candles
  entryrange_range_percentspot
  secret_tp_range_percent
  secret_tp_greenguard_pricediff_at_least
  tp_enabled
  tp_notsecret_range_percent
  sl_enabled
  sl_points
  closetrade_after_some_time
  closetrade_after_some_time_butOnlyIfProfit
  closetrade_after_some_time_but_ProfitPercent_Needed
  closetrade_after_x_minutes_from_breakdown
  max_open_positions
].freeze

COMBINATION_SIGNATURE_FIELDS = (COMBINATION_MAP_FIELDS - ["tested?"]).freeze

# --- edit combination grids here ---
DESIRED_EXPIRY_MINUTES = [60].freeze # 15  [15, 45] # obviously longer expiry means more trades fill. | 45 is best ✅✅✅
# [45, 90]
# perf_percentSum_w_roll: expiry_minutes=90 (182.72) is 1.1% better than expiry_minutes=45 (180.71)

# [25, 45] more trades more proft
# perf_percentSum_w_roll higher in head-to-head pairs:
#   expiry_minutes=25: 0/90 (0.0%), avg perf_percentSum_w_roll=131.18 (per algo)
#   expiry_minutes=45: 90/90 (100.0%), avg perf_percentSum_w_roll=137.42 (per algo)
#   perf_percentSum_w_roll: expiry_minutes=45 (137.42) is 4.8% better


DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT = [10].freeze #✅ 3 # TESTED ALREADY  [3 6] is no diff.  maybe test 1, 2, 3, but it is low prio
  # stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count=3: 316/575 (55.0%), avg perf_percentSum_w_roll=239.19 (per algo)
  # stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count=10: 444/574 (77.4%), avg perf_percentSum_w_roll=239.74 (per algo)




DESIRED_SECRET_TP_RANGE_PERCENT = [50, 100, 175, 300].freeze #  [100, 200, 300, 500]
#  [100, 200, 300, 500] 100 too weak vs buy and hold. 200 already good
# perf_percentSum_w_roll highers 100      20000057   149.52      0.059
#                        2nd    200      20000058   203.34      0.038
#                        Δ 1→2                      -26.5%      +55.3%
#   tVSprof solo 300     best   300      20000063   267.56      0.033
#   tVSprof solo 500     best   500      20000004   369.89      0.026
#   duel                 side   group    algo       percent_sum timeVSprofit
#   ------------------------------------------------------------------------
#   %sum #1              1st    500      20000016   372.10      0.026
#                        2nd    300      20000015   336.90      0.030
#                        Δ 1→2                      +10.4%      -13.3%
#   %sum solo 100        best   100      20000013   184.10      0.040
#   %sum solo 200        best   200      20000014   307.32      0.037  

### It does not need secret TP != 0. The time-based close is independent of secret_tp_range_percent.
# profit/minutes arrays are only expanded in the grid when closetrade_after_some_time=true.
DESIRED_CLOSETRADE_AFTER_SOME_TIME = [true].freeze
DESIRED_CLOSETRADE_AFTER_SOME_TIME_BUT_PROFITPERCENT_NEEDED = [2.0, 4.0, 15.0].freeze # ✅✅[1.0, 2.0, 3.5, 5.0, 8.0, 12.0, 18.0, 25.0]
DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN = [800].freeze # ✅ with higher TP targets it is irrelevant 
# DESIRED_CLOSETRADE_AFTER_SOME_TIME_BUT_PROFITPERCENT_NEEDED = [2.0, 5.0, 10.0, 19.0].freeze # [1.0, 2.0, 3.5, 5.0, 8.0, 12.0, 18.0, 25.0]
# DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN = [60, 800].freeze
# both 2.0 is weaker performance than time algo benchmark, same for 5.0
# both 10.0 are weaker than benchmark but twice as good time vs profit coompared to benchmark
# closetrade_after_some_time_but_ProfitPercent_Needed=10.0, closetrade_after_x_minutes_from_breakdown=60 (algos=15):
#   avg perf_timeVSprofit=0.049
#   avg perf_percentSum_w_roll=113.76
#   avg perf_avgDurationHours=151.623
#   avg perf_tradesCount=182.80
# closetrade_after_some_time_but_ProfitPercent_Needed=10.0, closetrade_after_x_minutes_from_breakdown=800 (algos=16):
#   avg perf_timeVSprofit=0.048
#   avg perf_percentSum_w_roll=119.70
#   avg perf_avgDurationHours=172.408
#   avg perf_tradesCount=169.56

# This has profit and timevsprofit better than time benchmarks!
# closetrade_after_some_time_but_ProfitPercent_Needed=19.0, closetrade_after_x_minutes_from_breakdown=60 (algos=15):
#   avg perf_timeVSprofit=0.038
#   avg perf_percentSum_w_roll=157.33
#   avg perf_avgDurationHours=321.963
#   avg perf_tradesCount=146.93
# closetrade_after_some_time_but_ProfitPercent_Needed=19.0, closetrade_after_x_minutes_from_breakdown=800 (algos=14):
#   avg perf_timeVSprofit=0.038
#   avg perf_percentSum_w_roll=164.10
#   avg perf_avgDurationHours=334.801
#   avg perf_tradesCount=148.29



DESIRED_MIN_BREAKDOWN_SEQUENCE_LEN = [3].freeze # 3 ✅ the less, the more trades the more profit (of course limt 10 orders) 
# [3, 7]
# perf_percentSum_w_roll group 0 secret TP higher in head-to-head pairs:
# min_breakdown_sequence_len=3: 36/36 (100.0%), avg perf_percentSum_w_roll group 0 secret TP=146.45 (per algo)
# min_breakdown_sequence_len=7: 0/36 (0.0%), avg perf_percentSum_w_roll group 0 secret TP=77.15 (per algo)
# perf_avgDurationHours group 0 secret TP higher in head-to-head pairs:
# min_breakdown_sequence_len=3: 0/36 (0.0%), avg perf_avgDurationHours group 0 secret TP=254.700 (per algo)
# min_breakdown_sequence_len=7: 36/36 (100.0%), avg perf_avgDurationHours group 0 secret TP=305.376 (per algo)

DESIRED_MAX_BREAKDOWN_SEQUENCE_LEN = [21].freeze # 9  ✅ 21 best from tested
# [21, 42, 64] no diff, probably after min bd satisfied it always fills before it matters for max bd length
# [9, 21] not much diff, but 21 better
# perf_percentSum_w_roll group 0 secret TP higher in head-to-head pairs:
#   max_breakdown_sequence_len=9: 0/432 (0.0%), avg perf_percentSum_w_roll group 0 secret TP=136.07 (per algo)
#   max_breakdown_sequence_len=21: 432/432 (100.0%), avg perf_percentSum_w_roll group 0 secret TP=139.95 (per algo)
# perf_tradesCount higher in head-to-head pairs:
#   max_breakdown_sequence_len=9: 0/432 (0.0%), avg perf_tradesCount=299.04 (per algo)
#   max_breakdown_sequence_len=21: 432/432 (100.0%), avg perf_tradesCount=307.18 (per algo)


DESIRED_BD_START_MIN_BREAKDOWN_PERCENT = [0.20, 0.30, 0.45].freeze # 0.20   [0.20, 0.35, 0.15] the less the more trades obviously, turns out for mmore profit?  tested with 10 trades limit
# perf_percentSum_w_roll group 0 secret TP higher in head-to-head pairs:
#   bd_start_min_breakdown_percent=0.15: 191/280 (68.2%), avg perf_percentSum_w_roll group 0 secret TP=78.68 (per algo)
#   bd_start_min_breakdown_percent=0.20: 113/280 (40.4%), avg perf_percentSum_w_roll group 0 secret TP=76.07 (per algo)
#   bd_start_min_breakdown_percent=0.35: 116/280 (41.4%), avg perf_percentSum_w_roll group 0 secret TP=75.81 (per algo)

# [0.15, 0.10] not much diff in gan or tradesC
# perf_percentSum_w_roll group 0 secret TP higher in head-to-head pairs:
#   bd_start_min_breakdown_percent=0.10: 242/432 (56.0%), avg perf_percentSum_w_roll group 0 secret TP=138.53 (per algo)
#   bd_start_min_breakdown_percent=0.15: 190/432 (44.0%), avg perf_percentSum_w_roll group 0 secret TP=137.49 (per algo)
#   perf_percentSum_w_roll group 0 secret TP: bd_start_min_breakdown_percent=0.10 (138.53) is 0.8% better

# [0.10, 0.20] top 4 profit algo is 0.20. top 4 profitVStime are 0.20. NEVER USE 0.10 ANYMORE, BUT CAN TEST 0.3

DESIRED_MIN_BREAKDOWN_TOTAL_PERCENT = [0.30, 0.60, 0.95].freeze  #  0.60, [0.40, 0.60, 0.85, 1.50]  # again easier rule = more trades = more profit
# perf_percentSum_w_roll higher in head-to-head pairs:
#   min_breakdown_total_percent=0.45: 374/384 (97.4%), avg perf_percentSum_w_roll=140.89 (per algo)
#   min_breakdown_total_percent=0.60: 10/384 (2.6%), avg perf_percentSum_w_roll=118.90 (per algo)
# [0.30, 0.45] # gains 34% better but through 64% more tradess
# perf_percentSum_w_roll group 0 secret TP higher in head-to-head pairs:
#   min_breakdown_total_percent=0.30: 432/432 (100.0%), avg perf_percentSum_w_roll group 0 secret TP=158.09 (per algo)
#   min_breakdown_total_percent=0.45: 0/432 (0.0%), avg perf_percentSum_w_roll group 0 secret TP=117.94 (per algo)
#   perf_percentSum_w_roll group 0 secret TP: min_breakdown_total_percent=0.30 (158.09) is 34.0% better
# perf_tradesCount higher in head-to-head pairs:
#   min_breakdown_total_percent=0.30: 432/432 (100.0%), avg perf_tradesCount=377.03 (per algo)
#   min_breakdown_total_percent=0.45: 0/432 (0.0%), avg perf_tradesCount=229.20 (per algo)
#   perf_tradesCount: min_breakdown_total_percent=0.30 (377.03) is 64.5% better

#  [0.30, 0.60]
#   perf_timeVSprofit #1: min_breakdown_total_percent=0.60 algo 20001014 (0.071) is 10.9% better than min_breakdown_total_percent=0.30 algo 20000580 (0.064)
#   perf_percentSum_w_roll (same #1 algos): min_breakdown_total_percent=0.60 algo 20001014 (132.49) is 21.7% worse than min_breakdown_total_percent=0.30 algo 20000580 (161.18)
# time algo has 221.57 sum for this run! with 0.028
#   perf_percentSum_w_roll #1: min_breakdown_total_percent=0.30 algo 20000273 (341.38) is 28.2% better than min_breakdown_total_percent=0.60 algo 20000561 (266.30)
#   perf_timeVSprofit (same #1 algos): min_breakdown_total_percent=0.30 algo 20000273 (0.029) is 3.4% worse than min_breakdown_total_percent=0.60 algo 20000561 (0.030)

DESIRED_AFTER_BD_NEED_X_15GREENC = [1].freeze #  [1, 2, 3] # Aleksik2_traderesults2_variable_comparisons shows 1 is much better due to more trades

ENTRY_FORGET_MIN_ROOM_MINUTES = 15 # match aleksik2.mq5 BREAKDOWN_ENTRY_FORGET_MIN_ROOM_MINUTES
SKIP_INVALIDCOMBOS_OF_FORGETBD_VS_ENTRY_MAX_MINUTES = true # if false, error and dont create any. if true, only skip invalid combos

### this set had no diffs at all, for non secret TP run
# DESIRED_FORGET_ABOUT_LATEST_BREAKDOWN_AFTER_X_15M_CANDLES = [8, 11, 18, 30].freeze # literally no diff for this with 150 below
# DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND = [150].freeze 
DESIRED_FORGET_ABOUT_LATEST_BREAKDOWN_AFTER_X_15M_CANDLES = [52].freeze # 52✅ but can test VS bigger numbers
DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND = [110, 250].freeze # 250  ✅ 110 wins vs 60. 160 wins vs 110 & 13 with better profit and time!  [110, 250]:250 wins
# duel           side   group    algo       percent_sum timeVSprofit
# ------------------------------------------------------------------
# %sum #1        1st    52/250   20000032   377.12      0.027
#                2nd    52/110   20000016   358.47      0.026
#                Δ 1→2                      +5.2%       +3.8%

# compare2vars:
# forget_about_latest_breakdown_after_x_15m_candles=6, entry_max_minutes_after_bdend=75 (algos=13):
#   avg perf_timeVSprofit=0.039
#   avg perf_percentSum_w_roll=124.60
#   avg perf_avgDurationHours=254.629
#   avg perf_tradesCount=177.69
# forget_about_latest_breakdown_after_x_15m_candles=11, entry_max_minutes_after_bdend=75 (algos=12):
#   avg perf_timeVSprofit=0.036
#   avg perf_percentSum_w_roll=132.40
#   avg perf_avgDurationHours=271.217
#   avg perf_tradesCount=185.25
# forget_about_latest_breakdown_after_x_15m_candles=11, entry_max_minutes_after_bdend=150 (algos=12): # most trades so most profit
#   avg perf_timeVSprofit=0.038
#   avg perf_percentSum_w_roll=146.38
#   avg perf_avgDurationHours=254.844
#   avg perf_tradesCount=212.92

#  [22, 28, 40, 52, 60]  [160, 200, 250] 250 is best somehow ale nie ufam
# forget_about_latest_breakdown_after_x_15m_candles=52, entry_max_minutes_after_bdend=250 (algos=12):
#   avg perf_timeVSprofit=0.053
#   avg perf_percentSum_w_roll=137.37
#   avg perf_avgDurationHours=129.098
#   avg perf_tradesCount=243.00

#  [5, 8, 12],  [60, 110]
# forget_about_latest_breakdown_after_x_15m_candles=5, entry_max_minutes_after_bdend=60 (algos=12):
#   avg perf_timeVSprofit=0.043
#   avg perf_percentSum_w_roll=113.47
#   avg perf_avgDurationHours=144.297
#   avg perf_tradesCount=224.67
# forget_about_latest_breakdown_after_x_15m_candles=8, entry_max_minutes_after_bdend=60 (algos=12):
#   avg perf_timeVSprofit=0.043
#   avg perf_percentSum_w_roll=113.47
#   avg perf_avgDurationHours=144.297
#   avg perf_tradesCount=224.67
# forget_about_latest_breakdown_after_x_15m_candles=12, entry_max_minutes_after_bdend=60 (algos=12):
#   avg perf_timeVSprofit=0.043
#   avg perf_percentSum_w_roll=113.47
#   avg perf_avgDurationHours=144.297
#   avg perf_tradesCount=224.67
# forget_about_latest_breakdown_after_x_15m_candles=12, entry_max_minutes_after_bdend=110 (algos=12):
#   avg perf_timeVSprofit=0.040
#   avg perf_percentSum_w_roll=117.06
#   avg perf_avgDurationHours=148.825
#   avg perf_tradesCount=239.25



# 23.6%  38.2%  50.0% — Midpoint Benchmark Not a mathematical Fibonacci ratio, but universally included on charting platforms based on Dow Theory price behavior.
# 61.8% — The Golden Ratio ($1 / 1.618 \approx 0.618$)
# 78.6%
# 88.6% — Harmonic Level Calculated as $\sqrt{0.786}$ (or $\sqrt[4]{0.618}$). Popularized in Harmonic trading (e.g., Bat patterns)
DESIRED_ENTRYRANGE_RANGE_PERCENTSPOT = [33, 66, 71].freeze # ✅✅✅✅✅66 > 62 ✅ [20, 66, 75].    [20, 33, 50, 66, 75], the higher the better. test 90. 99 rarely trades obvously as too hard to fill. 
# [62, 66] 66 won slightly
# by entryrange_range_percentspot (paired algos, per-algo averages):
# group                    algos  avg_trades avg_percent  avgtimeVSprofit avgavgDurationHours
# -------------------------------------------------------------------------------------------
# 62.00                    84     175.44     149.58       0.044        306.25
# 66.00                    84     180.92     152.68       0.043        306.50
#   duel           side   group    algo       percent_sum timeVSprofit
#   ------------------------------------------------------------------
#   tVSprof #1     1st    66.00    20000177   35.62       0.095
#                  2nd    62.00    20000161   33.93       0.091
#                  Δ 1→2                      +5.0%       +4.4%
#   duel           side   group    algo       percent_sum timeVSprofit
#   ------------------------------------------------------------------
#   %sum #1        1st    66.00    20000016   372.10      0.026
#                  2nd    62.00    20000008   368.25      0.026
#                  Δ 1→2                      +1.0%       +0.0%

# [38, 62]
# 62 so much better in all ways.






DESIRED_TP_NOTSECRET_RANGE_PERCENT = [9999].freeze # 150 outperforms 110. [175, 250] 250 still better than 175, can try even 350, 500? but lower has better  efficency?
# perf_percentSum_w_roll group 0 secret TP higher in head-to-head pairs:
#   tp_notsecret_range_percent=110: 2/210 (1.0%), avg perf_percentSum_w_roll group 0 secret TP=65.11 (per algo)
#   tp_notsecret_range_percent=150: 208/210 (99.0%), avg perf_percentSum_w_roll group 0 secret TP=88.60 (per algo)
#   perf_percentSum_w_roll group 0 secret TP: tp_notsecret_range_percent=150 (88.60) is 36.1% better than tp_notsecret_range_percent=110 (65.11)
# perf_percentSum_w_roll group non 0 secret TP higher in head-to-head pairs:
#   tp_notsecret_range_percent=110: 1/210 (0.5%), avg perf_percentSum_w_roll group non 0 secret TP=43.63 (per algo)
#   tp_notsecret_range_percent=150: 209/210 (99.5%), avg perf_percentSum_w_roll group non 0 secret TP=47.26 (per algo)
# perf_percentSum_w_roll group 0 secret TP higher in head-to-head pairs:
#   tp_notsecret_range_percent=175: 0/192 (0.0%), avg perf_percentSum_w_roll group 0 secret TP=136.38 (per algo)
#   tp_notsecret_range_percent=250: 192/192 (100.0%), avg perf_percentSum_w_roll group 0 secret TP=170.24 (per algo)

#  [110, 150, 250] # 110 less profit but most efficiency
# perf_timeVSprofit higher in head-to-head pairs:
#   tp_notsecret_range_percent=110: 24/24 (100.0%), avg perf_timeVSprofit=0.042 (per algo)
#   tp_notsecret_range_percent=150: 12/24 (50.0%), avg perf_timeVSprofit=0.038 (per algo)
#   tp_notsecret_range_percent=250: 0/24 (0.0%), avg perf_timeVSprofit=0.034 (per algo)
# perf_percentSum_w_roll group 0 secret TP higher in head-to-head pairs:
#   tp_notsecret_range_percent=110: 0/24 (0.0%), avg perf_percentSum_w_roll group 0 secret TP=114.48 (per algo)
#   tp_notsecret_range_percent=150: 12/24 (50.0%), avg perf_percentSum_w_roll group 0 secret TP=139.06 (per algo)
#   tp_notsecret_range_percent=250: 24/24 (100.0%), avg perf_percentSum_w_roll group 0 secret TP=185.80 (per algo)


DESIRED_MAX_OPEN_POSITIONS = [10].freeze # 15 is better than 10 I think (put 10 to have quicker sim)? 10 also test 5.  could even test 20, beecause 15 is more trades so more proft, but also has better durations
# perf_percentSum_w_roll group 0 secret TP higher in head-to-head pairs:
#   max_open_positions=10: 0/192 (0.0%), avg perf_percentSum_w_roll group 0 secret TP=131.34 (per algo)
#   max_open_positions=15: 192/192 (100.0%), avg perf_percentSum_w_roll group 0 secret TP=175.28 (per algo)
#   perf_percentSum_w_roll group 0 secret TP: max_open_positions=15 (175.28) is 33.4% better than max_open_positions=10 (131.34)
# [10, 15] perf_avgDurationHours group 0 secret TP higher in head-to-head pairs:
#   max_open_positions=10: 180/192 (93.8%), avg perf_avgDurationHours group 0 secret TP=442.625 (per algo)
#   max_open_positions=15: 12/192 (6.2%), avg perf_avgDurationHours group 0 secret TP=396.513 (per algo)
#   perf_avgDurationHours group 0 secret TP: max_open_positions=10 (442.625) is 11.6% better than max_open_positions=15 (396.513)


# removed LOW and  CLOSES, and HL_MID.   removed OHLC_AVG
DESIRED_BREAKDOWNTYPES = %w[ 
  OC_MID
  OHLC_AVG
].freeze
#latest test  ruby .\compare_breakdown_types.rb
# perf_timeVSprofit higher in head-to-head pairs:
#   breakdown_streak_continuation_mode=OC_MID: 31/50 (62.0%), avg perf_timeVSprofit=0.037 (per algo)
#   breakdown_streak_continuation_mode=OHLC_AVG: 10/50 (20.0%), avg perf_timeVSprofit=0.036 (per algo)
#   perf_timeVSprofit: breakdown_streak_continuation_mode=OC_MID (0.037) is 2.5% better than breakdown_streak_continuation_mode=OHLC_AVG (0.036)

#   duel           side   group    algo       percent_sum timeVSprofit
#   ------------------------------------------------------------------
#   tVSprof #1     1st    OC_MID   20000098   137.24      0.057
#                  2nd    OHLC_AVG 20000097   126.20      0.053
#                  Δ 1→2                      +8.7%       +7.5%


### Test new:
# DECYZJA TUTAJ: Z TOP 3 ZOSTAWIAM TOP 2 TYLKO. HL_MID JEST POŚRODKU W OBU rankingach wiec go wyłączam.
# perf_avgDurationHours group 0 secret TP higher in head-to-head pairs:
#   breakdown_streak_continuation_mode=OC_MID: 483/540 (89.4%), avg perf_avgDurationHours group 0 secret TP=1195.980 (per algo)
#   breakdown_streak_continuation_mode=HL_MID: 30/540 (5.6%), avg perf_avgDurationHours group 0 secret TP=1125.692 (per algo)
#   breakdown_streak_continuation_mode=OHLC_AVG: 279/504 (55.4%), avg perf_avgDurationHours group 0 secret TP=1059.035 (per algo)
# perf_percentSum_w_roll group 0 secret TP higher in head-to-head pairs:
#   breakdown_streak_continuation_mode=OHLC_AVG: 255/504 (50.6%), avg perf_percentSum_w_roll group 0 secret TP=183.46 (per algo)
#   breakdown_streak_continuation_mode=HL_MID: 335/540 (62.0%), avg perf_percentSum_w_roll group 0 secret TP=182.58 (per algo)
#   breakdown_streak_continuation_mode=OC_MID: 199/540 (36.9%), avg perf_percentSum_w_roll group 0 secret TP=179.32 (per algo)
### test old:
# looks like OC_MID and OHLC_AVG perform the best profit. But HL_MID has lowest durations, 2nd place is OHLC_AVG. 
# but basically LOW is the worst by far, CLOSES is very weak too, both have low trade count 
# tested with max trades 10
# perf_timeVSprofit higher in head-to-head pairs:
#   breakdown_streak_continuation_mode=OHLC_AVG: 469/676 (69.4%), avg perf_timeVSprofit=0.055 (per algo)
#   breakdown_streak_continuation_mode=HL_MID: 446/676 (66.0%), avg perf_timeVSprofit=0.054 (per algo)
#   breakdown_streak_continuation_mode=OC_MID: 250/676 (37.0%), avg perf_timeVSprofit=0.048 (per algo)
#   breakdown_streak_continuation_mode=CLOSES: 245/676 (36.2%), avg perf_timeVSprofit=0.047 (per algo)
# perf_percentSum_w_roll higher in head-to-head pairs: 
#   breakdown_streak_continuation_mode=OC_MID: 538/676 (79.6%), avg perf_percentSum_w_roll=65.00 (per algo)
#   breakdown_streak_continuation_mode=OHLC_AVG: 468/676 (69.2%), avg perf_percentSum_w_roll=64.87 (per algo)
#   breakdown_streak_continuation_mode=CLOSES: 351/676 (51.9%), avg perf_percentSum_w_roll=62.10 (per algo)
#   breakdown_streak_continuation_mode=HL_MID: 301/676 (44.5%), avg perf_percentSum_w_roll=61.91 (per algo)
#   breakdown_streak_continuation_mode=LOW: 32/676 (4.7%), avg perf_percentSum_w_roll=50.96 (per algo)
# perf_avgDurationHours higher in head-to-head pairs:
#   breakdown_streak_continuation_mode=CLOSES: 569/676 (84.2%), avg perf_avgDurationHours=217.963 (per algo)
#   breakdown_streak_continuation_mode=OC_MID: 394/676 (58.3%), avg perf_avgDurationHours=192.951 (per algo)
#   breakdown_streak_continuation_mode=LOW: 344/676 (50.9%), avg perf_avgDurationHours=183.016 (per algo)
#   breakdown_streak_continuation_mode=OHLC_AVG: 237/676 (35.1%), avg perf_avgDurationHours=171.174 (per algo)
#   breakdown_streak_continuation_mode=HL_MID: 146/676 (21.6%), avg perf_avgDurationHours=162.973 (per algo)
# perf_tradesCount higher in head-to-head pairs:
#   breakdown_streak_continuation_mode=OC_MID: 566/676 (83.7%), avg perf_tradesCount=96.44 (per algo)
#   breakdown_streak_continuation_mode=OHLC_AVG: 488/676 (72.2%), avg perf_tradesCount=94.46 (per algo)
#   breakdown_streak_continuation_mode=HL_MID: 424/676 (62.7%), avg perf_tradesCount=93.15 (per algo)
#   breakdown_streak_continuation_mode=LOW: 99/676 (14.6%), avg perf_tradesCount=77.85 (per algo)
#   breakdown_streak_continuation_mode=CLOSES: 90/676 (13.3%), avg perf_tradesCount=76.79 (per algo)





module BreakdownCombinationsMap
  module_function

  def format_csv_double(value, decimals = 2)
    format("%.#{decimals}f", value.to_f)
  end

  def format_csv_bool(value)
    value ? "true" : "false"
  end

  def breakdowntype_for_mode(mode)
    BREAKDOWN_TYPE_TO_MODE.key(mode) || mode
  end

  def entry_forget_invalid_reason(entry_max, forget_candles)
    forget = forget_candles.to_i
    entry = entry_max.to_i
    if forget <= 0
      return "forget_about_latest_breakdown_after_x_15m_candles must be >= 1 (got #{forget_candles})"
    end

    forget_min = forget * 15
    room_min = forget_min - entry
    if room_min < ENTRY_FORGET_MIN_ROOM_MINUTES
      return "forget #{forget}x15m=#{forget_min} min needs >= #{ENTRY_FORGET_MIN_ROOM_MINUTES} min room before entry_max=#{entry} (room=#{room_min})"
    end

    nil
  end

  def entry_forget_combo_valid?(entry_max, forget_candles)
    entry_forget_invalid_reason(entry_max, forget_candles).nil?
  end

  def invalid_entry_forget_pairs(entry_values = DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND,
    forget_values = DESIRED_FORGET_ABOUT_LATEST_BREAKDOWN_AFTER_X_15M_CANDLES)
    entry_values.product(forget_values).filter_map do |entry_max, forget_candles|
      reason = entry_forget_invalid_reason(entry_max, forget_candles)
      next unless reason

      { entry_max: entry_max, forget_candles: forget_candles, reason: reason }
    end
  end

  def entry_forget_pair_count(entry_values = DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND,
    forget_values = DESIRED_FORGET_ABOUT_LATEST_BREAKDOWN_AFTER_X_15M_CANDLES)
    entry_values.product(forget_values).count do |entry_max, forget_candles|
      entry_forget_combo_valid?(entry_max, forget_candles)
    end
  end

  # When closetrade_after_some_time is false, profit/minutes are inactive in mq5 — emit one placeholder leg only.
  def closetrade_after_some_time_combo_legs(
    some_time_values = DESIRED_CLOSETRADE_AFTER_SOME_TIME,
    profit_values = DESIRED_CLOSETRADE_AFTER_SOME_TIME_BUT_PROFITPERCENT_NEEDED,
    minutes_values = DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN
  )
    raise "DESIRED_CLOSETRADE_AFTER_SOME_TIME_BUT_PROFITPERCENT_NEEDED must not be empty" if profit_values.empty?
    raise "DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN must not be empty" if minutes_values.empty?

    legs = []
    some_time_values.each do |enabled|
      if enabled
        profit_values.product(minutes_values).each do |profit, minutes|
          legs << [true, profit, minutes]
        end
      else
        legs << [false, profit_values.first, minutes_values.first]
      end
    end
    legs
  end

  def closetrade_after_some_time_leg_count(
    some_time_values = DESIRED_CLOSETRADE_AFTER_SOME_TIME,
    profit_values = DESIRED_CLOSETRADE_AFTER_SOME_TIME_BUT_PROFITPERCENT_NEEDED,
    minutes_values = DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN
  )
    closetrade_after_some_time_combo_legs(some_time_values, profit_values, minutes_values).size
  end

  def validate_entry_forget_desired_grid!
    invalid_pairs = invalid_entry_forget_pairs
    return if invalid_pairs.empty?

    lines = invalid_pairs.map do |pair|
      "  entry_max=#{pair[:entry_max]}, forget=#{pair[:forget_candles]}x15m: #{pair[:reason]}"
    end

    if SKIP_INVALIDCOMBOS_OF_FORGETBD_VS_ENTRY_MAX_MINUTES
      warn "WARNING: skipping #{invalid_pairs.size} invalid entry_max/forget pair(s) from desired grid:"
      lines.each { |line| warn line }
      warn
      return
    end

    $stderr.puts "ERROR: invalid entry_max vs forget combinations in desired grid (#{invalid_pairs.size} pair(s)):"
    lines.each { |line| $stderr.puts line }
    $stderr.puts
    $stderr.puts "Set SKIP_INVALIDCOMBOS_OF_FORGETBD_VS_ENTRY_MAX_MINUTES = true to skip only invalid pairs, or fix DESIRED_* arrays."
    exit 1
  end

  # When closetrade_after_some_time is true, secret TP is inactive — use 0 only (no grid dupes).
  def effective_secret_tp_values_for_closetrade(closetrade_after_some_time)
    closetrade_after_some_time ? [0] : DESIRED_SECRET_TP_RANGE_PERCENT
  end

  def secret_tp_combination_factor(
    some_time_values = DESIRED_CLOSETRADE_AFTER_SOME_TIME,
    profit_values = DESIRED_CLOSETRADE_AFTER_SOME_TIME_BUT_PROFITPERCENT_NEEDED,
    minutes_values = DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN,
    secret_tp_values = DESIRED_SECRET_TP_RANGE_PERCENT
  )
    closetrade_after_some_time_combo_legs(some_time_values, profit_values, minutes_values).sum do |enabled, _, _|
      enabled ? 1 : secret_tp_values.size
    end
  end

  def build_combinations
    combos = []
    closetrade_legs = closetrade_after_some_time_combo_legs
    DESIRED_MIN_BREAKDOWN_SEQUENCE_LEN.product(
      DESIRED_MAX_BREAKDOWN_SEQUENCE_LEN,
      DESIRED_BD_START_MIN_BREAKDOWN_PERCENT,
      DESIRED_MIN_BREAKDOWN_TOTAL_PERCENT,
      DESIRED_EXPIRY_MINUTES,
      DESIRED_AFTER_BD_NEED_X_15GREENC,
      DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND,
      DESIRED_FORGET_ABOUT_LATEST_BREAKDOWN_AFTER_X_15M_CANDLES,
      DESIRED_ENTRYRANGE_RANGE_PERCENTSPOT,
      DESIRED_TP_NOTSECRET_RANGE_PERCENT,
      DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT,
      DESIRED_BREAKDOWNTYPES,
      DESIRED_MAX_OPEN_POSITIONS
    ) do |min_len, max_len, bd_start_pct, min_total_pct, expiry_min, after_greenc, entry_min, forget_bd_candles, entryrange_pct, tp_notsecret, stop_total_trades, bd_type, max_open|
      next if min_len > max_len
      next unless entry_forget_combo_valid?(entry_min, forget_bd_candles)

      mode = BREAKDOWN_TYPE_TO_MODE[bd_type]
      raise "Unknown breakdowntype #{bd_type.inspect}" unless mode

      closetrade_legs.each do |close_after_some_time, close_profit_pct_needed, close_after_min|
        effective_secret_tp_values_for_closetrade(close_after_some_time).each do |secret_tp|
          combos << {
            min_breakdown_sequence_len: min_len,
            max_breakdown_sequence_len: max_len,
            bd_start_min_breakdown_percent: bd_start_pct,
            min_breakdown_total_percent: min_total_pct,
            expiry_minutes: expiry_min,
            after_bd_need_x_15greenc: after_greenc,
            entry_max_minutes_after_bdend: entry_min,
            forget_about_latest_breakdown_after_x_15m_candles: forget_bd_candles,
            entryrange_range_percentspot: entryrange_pct,
            secret_tp_range_percent: secret_tp,
            tp_notsecret_range_percent: tp_notsecret,
            closetrade_after_some_time: close_after_some_time,
            closetrade_after_some_time_but_ProfitPercent_Needed: close_profit_pct_needed,
            closetrade_after_x_minutes_from_breakdown: close_after_min,
            stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count: stop_total_trades,
            breakdown_streak_continuation_mode: mode,
            breakdowntype: bd_type,
            max_open_positions: max_open
          }
        end
      end
    end
    combos
  end

  def combination_dimension_counts
    valid_min_max_pairs = DESIRED_MIN_BREAKDOWN_SEQUENCE_LEN.product(DESIRED_MAX_BREAKDOWN_SEQUENCE_LEN)
      .count { |min_len, max_len| min_len <= max_len }

    {
      min_max_breakdown_sequence_len: valid_min_max_pairs,
      bd_start_min_breakdown_percent: DESIRED_BD_START_MIN_BREAKDOWN_PERCENT.size,
      min_breakdown_total_percent: DESIRED_MIN_BREAKDOWN_TOTAL_PERCENT.size,
      expiry_minutes: DESIRED_EXPIRY_MINUTES.size,
      after_bd_need_x_15greenc: DESIRED_AFTER_BD_NEED_X_15GREENC.size,
      entry_max_forget_pairs: entry_forget_pair_count,
      entryrange_range_percentspot: DESIRED_ENTRYRANGE_RANGE_PERCENTSPOT.size,
      closetrade_secret_tp_combos: secret_tp_combination_factor,
      tp_notsecret_range_percent: DESIRED_TP_NOTSECRET_RANGE_PERCENT.size,
      stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count: DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT.size,
      breakdowntypes: DESIRED_BREAKDOWNTYPES.size,
      max_open_positions: DESIRED_MAX_OPEN_POSITIONS.size
    }
  end

  def row_field_value(row, field)
    row[field.to_sym] || row[field]
  end

  def normalize_signature_value(value)
    s = value.to_s.strip
    case s.downcase
    when "true" then "true"
    when "false" then "false"
    else s
    end
  end

  def normalize_map_row(row)
    COMBINATION_MAP_FIELDS.each_with_object({}) do |field, normalized|
      normalized[field] = row_field_value(row, field).to_s
    end
  end

  def row_signature(row)
    COMBINATION_SIGNATURE_FIELDS
      .map { |field| normalize_signature_value(row_field_value(row, field)) }
      .join("\0")
  end

  def load_existing_combinations_map_csv(path)
    return [] unless File.exist?(path)

    table = CSV.read(path, headers: true)
    missing = COMBINATION_MAP_FIELDS - table.headers
    unless missing.empty?
      raise "Existing CSV missing columns: #{missing.join(', ')}"
    end

    table.map { |csv_row| normalize_map_row(csv_row) }
  end

  def merge_combinations_map_rows(existing_rows, generated_rows)
    tested_by_signature = {}
    existing_rows.each do |row|
      signature = row_signature(row)
      tested = normalize_signature_value(row_field_value(row, "tested?"))
      if tested == "true"
        tested_by_signature[signature] = "true"
      else
        tested_by_signature[signature] ||= "false"
      end
    end

    merged = []
    seen = {}
    matched_count = 0
    new_from_grid_count = 0
    preserved_tested_count = 0

    generated_rows.each do |row|
      signature = row_signature(row)
      next if seen[signature]

      out = normalize_map_row(row)
      if tested_by_signature.key?(signature)
        out["tested?"] = tested_by_signature[signature]
        matched_count += 1
        preserved_tested_count += 1 if tested_by_signature[signature] == "true"
      else
        out["tested?"] = "false"
        new_from_grid_count += 1
      end
      merged << out
      seen[signature] = true
    end

    orphans_added = 0
    existing_rows.each do |row|
      signature = row_signature(row)
      next if seen[signature]

      merged << normalize_map_row(row)
      seen[signature] = true
      orphans_added += 1
    end

    {
      rows: merged,
      matched_count: matched_count,
      new_from_grid_count: new_from_grid_count,
      orphans_added: orphans_added,
      preserved_tested_count: preserved_tested_count
    }
  end

  def combo_to_map_row(combo)
    {
      "tested?" => "false",
      enabled: "true",
      stop_trading_today_if_thisAlgo_losing_trades_count: 999,
      stop_trading_today_if_thisAlgo_winning_trades_count: 999,
      stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count: combo[:stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count],
      expiry_minutes: combo[:expiry_minutes],
      this_algo_max_concurrent_pending_trades: 1,
      min_breakdown_sequence_len: combo[:min_breakdown_sequence_len],
      max_breakdown_sequence_len: combo[:max_breakdown_sequence_len],
      breakdown_streak_continuation_mode: combo[:breakdown_streak_continuation_mode],
      breakdowntype: combo[:breakdowntype],
      bd_start_min_breakdown_percent: format_csv_double(combo[:bd_start_min_breakdown_percent]),
      min_breakdown_total_percent: format_csv_double(combo[:min_breakdown_total_percent]),
      after_bd_need_x_15greenc: combo[:after_bd_need_x_15greenc],
      entry_max_minutes_after_bdend: combo[:entry_max_minutes_after_bdend],
      forget_about_latest_breakdown_after_x_15m_candles: combo[:forget_about_latest_breakdown_after_x_15m_candles],
      entryrange_range_percentspot: format_csv_double(combo[:entryrange_range_percentspot]),
      secret_tp_range_percent: combo[:secret_tp_range_percent],
      secret_tp_greenguard_pricediff_at_least: format_csv_double(8.0),
      tp_enabled: "true",
      tp_notsecret_range_percent: combo[:tp_notsecret_range_percent],
      sl_enabled: "false",
      sl_points: format_csv_double(0.0),
      closetrade_after_some_time: format_csv_bool(combo[:closetrade_after_some_time]),
      closetrade_after_some_time_butOnlyIfProfit: "true",
      closetrade_after_some_time_but_ProfitPercent_Needed: format_csv_double(combo[:closetrade_after_some_time_but_ProfitPercent_Needed]),
      closetrade_after_x_minutes_from_breakdown: combo[:closetrade_after_x_minutes_from_breakdown],
      max_open_positions: combo[:max_open_positions]
    }
  end

  def write_combinations_map_csv!(path, rows)
    CSV.open(path, "w") do |csv|
      csv << COMBINATION_MAP_FIELDS
      rows.each do |row|
        normalized = normalize_map_row(row)
        csv << COMBINATION_MAP_FIELDS.map { |field| normalized[field] }
      end
    end

    rows.size
  end

  def write_merged_combinations_map_csv!(path, combinations)
    generated_rows = combinations.map { |combo| combo_to_map_row(combo) }
    existing_rows = load_existing_combinations_map_csv(path)
    merge_result = merge_combinations_map_rows(existing_rows, generated_rows)
    write_combinations_map_csv!(path, merge_result[:rows])
    merge_result
  end
end

include BreakdownCombinationsMap

if __FILE__ == $PROGRAM_NAME
  validate_entry_forget_desired_grid!

  dimension_counts = combination_dimension_counts
  total_combinations = dimension_counts.values.reduce(1, :*)
  valid_min_max_pairs = dimension_counts[:min_max_breakdown_sequence_len]

  puts "Breakdown combination map count: #{total_combinations}"
  puts
  dimension_counts.each do |name, count|
    puts "  #{name}: #{count}"
  end
  puts
  puts "  (min_breakdown_sequence_len <= max_breakdown_sequence_len: #{valid_min_max_pairs} of #{DESIRED_MIN_BREAKDOWN_SEQUENCE_LEN.size * DESIRED_MAX_BREAKDOWN_SEQUENCE_LEN.size} pairs)"
  puts

  if total_combinations.zero?
    puts "No combinations to write."
    exit 0
  end

  combinations = build_combinations
  raise "Combination build mismatch: #{combinations.size} != #{total_combinations}" if combinations.size != total_combinations

  if overwrite_csv
    existing_count = File.exist?(OUT_CSV) ? load_existing_combinations_map_csv(OUT_CSV).size : 0
    if existing_count.positive?
      puts "Existing #{OUT_CSV}: #{existing_count} row(s) — will overwrite completely (all tested?=false)."
    else
      puts "No existing #{OUT_CSV} — will create fresh (all tested?=false)."
    end
    puts

    print "Overwrite #{OUT_CSV} with #{total_combinations} grid row(s)? [y/N] "
    answer = $stdin.gets&.strip&.downcase
    unless answer == "y"
      puts "Aborted."
      exit 0
    end

    generated_rows = combinations.map { |combo| combo_to_map_row(combo) }
    row_count = write_combinations_map_csv!(OUT_CSV, generated_rows)
    puts "Wrote #{row_count} row(s) to #{OUT_CSV} (overwrite; all tested?=false)"
    puts "Columns: #{COMBINATION_MAP_FIELDS.join(', ')}"
  else
    existing_count = File.exist?(OUT_CSV) ? load_existing_combinations_map_csv(OUT_CSV).size : 0
    if existing_count.positive?
      puts "Existing #{OUT_CSV}: #{existing_count} row(s) — will merge (preserve tested?, append new, skip dupes)."
    else
      puts "No existing #{OUT_CSV} — will create fresh (all tested?=false)."
    end
    puts

    print "Merge #{total_combinations} grid row(s) into #{OUT_CSV}? [y/N] "
    answer = $stdin.gets&.strip&.downcase
    unless answer == "y"
      puts "Aborted."
      exit 0
    end

    merge_result = write_merged_combinations_map_csv!(OUT_CSV, combinations)
    puts "Wrote #{merge_result[:rows].size} row(s) to #{OUT_CSV}"
    puts "  grid: #{total_combinations} (#{merge_result[:matched_count]} matched, #{merge_result[:new_from_grid_count]} new)"
    puts "  orphans kept from old file: #{merge_result[:orphans_added]}"
    puts "  tested?=true preserved on matches: #{merge_result[:preserved_tested_count]}"
    puts "Columns: #{COMBINATION_MAP_FIELDS.join(', ')}"
  end
end
