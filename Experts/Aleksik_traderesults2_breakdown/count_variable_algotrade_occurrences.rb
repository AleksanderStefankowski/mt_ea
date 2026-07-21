#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'set'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR) read it
PERF_PATH = File.join(SCRIPT_DIR, 'summary_tradeResults_all_days_breakdown.csv')  read 

THE POINT OF THE SCRIPT IS TO READ THE TRADES FILE, READ CONFIG FILE, CHECK THE CHECKED VARIABLE NAME, AND COUNT OCCURRENCES OF TRADES WITH THAT VARIABLE VALUE, SPLIT BY EACH ENCOUNTERED VALUE (HERE EXPECT 50, 110, 75)

# Change this to compare algos that differ only in another config field.
# Supported COMPARE_VARIABLE values (any column in aleksik2_r_read_breakdown_algos_csv.csv except algo_id):
#   enabled
#   quant_rules
#   rules
#   stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
#   expiry_minutes
#   breakdown_streak_continuation_mode
#   min_breakdown_sequence_len
#   max_breakdown_sequence_len
#   bd_start_min_breakdown_percent
#   min_breakdown_total_percent
#   after_bd_need_x_15greenc
#   entry_max_minutes_after_bdend
#   entryrange_range_percentspot
#   secret_tp_range_percent
#   tp_notsecret_range_percent
#   closetrade_after_some_time
#   closetrade_after_some_time_butOnlyIfProfit
#   closetrade_after_some_time_but_ProfitPercent_Needed
#   closetrade_after_x_minutes_from_breakdown
#   max_open_positions
COUNT_VARIABLE = 'entry_max_minutes_after_bdend'




CLOSETRADE_CONFIG_COLUMNS = %w[
  closetrade_after_some_time
  closetrade_after_some_time_butOnlyIfProfit
  closetrade_after_some_time_but_ProfitPercent_Needed
  closetrade_after_x_minutes_from_breakdown
].freeze
