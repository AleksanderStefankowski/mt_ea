#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'rbconfig'
require 'open3'
require_relative 'analyze_algos_performance_common'

self.traderate_account_for_banned_days = false

include AnalyzeAlgosPerformanceCommon

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
INPUT_PATH = File.join(SCRIPT_DIR, 'summary_tradeResults_all_days_breakdown.tsv')
ALGO_CONFIG_PATH = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos_csv.csv', SCRIPT_DIR)
BREAKDOWN_CONFIG_GENERATOR = File.expand_path('../Aleksik2/aleksik2_r_read_breakdown_algos.rb', SCRIPT_DIR)
OUTPUT_PATH = File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_output.csv')
FLASHCRASH_OUTPUT_PATH = File.join(
  SCRIPT_DIR,
  'analyze_breakdown_algos_performance_output_2025flashcrash.csv'
)
EXCEPT_FLASHCRASH_OUTPUT_PATH = File.join(
  SCRIPT_DIR,
  'analyze_breakdown_algos_performance_output_except_2025flashcrash.csv'
)
OUTPUT_TIMESTAMP_PATH = File.join(SCRIPT_DIR, 'analyze_breakdown_algos_performance_output.timestamp')

# Big run only (not 2025flashcrash): drop algos below this % of the highest tradesCount algo.
exclude_algos_with_tradecount_less_than_xpercent_of_highestTradeCountAlgo = 24

FAMILY_ALL_PATTERN = 'BREAKDOWN'

def load_breakdown_pattern_by_algo_id(path)
  unless File.file?(path)
    warn "WARNING: algo config not found: #{path}"
    return {}
  end

  raw = File.read(path, encoding: 'bom|utf-8')
  table = CSV.parse(raw, headers: true)
  table.each_with_object({}) do |row, out|
    algo_id = row['algo_id'].to_s.strip
    next if algo_id.empty?

    out[algo_id] = row['breakdown_streak_continuation_mode'].to_s.strip
  end
end

def breakdown_pattern_for_algo(algo_id, pattern_by_algo)
  pattern_by_algo[algo_id.to_s].to_s
end

def exclude_low_trade_count_algos(rows, min_percent_of_highest)
  return rows if min_percent_of_highest.nil? || min_percent_of_highest <= 0
  return rows if rows.empty?

  highest_trade_count = rows.map { |row| row[:tradesCount].to_i }.max
  return rows if highest_trade_count <= 0

  rows.reject do |row|
    row[:tradesCount].to_i * 100 <= highest_trade_count * min_percent_of_highest
  end
end

if __FILE__ == $PROGRAM_NAME

warn
warn "Refreshing aleksik2_r_read_breakdown_algos_csv.csv via #{File.basename(BREAKDOWN_CONFIG_GENERATOR)}..."
config_output, config_status = Open3.capture2e(RbConfig.ruby, BREAKDOWN_CONFIG_GENERATOR)
warn config_output unless config_output.empty?
unless config_status.success? && config_output.include?('RAN OK')
  warn "ERROR: #{File.basename(BREAKDOWN_CONFIG_GENERATOR)} did not finish successfully (expected RAN OK)"
  exit 1
end

unless File.file?(INPUT_PATH)
  warn "ERROR: input file not found: #{INPUT_PATH}"
  exit 1
end

warn "Loading: #{INPUT_PATH}"
trades = load_trades(INPUT_PATH)
if trades.empty?
  warn 'ERROR: no trades loaded.'
  exit 1
end

pattern_by_algo = load_breakdown_pattern_by_algo_id(ALGO_CONFIG_PATH)
pattern_for_algo = ->(algo_id) { breakdown_pattern_for_algo(algo_id, pattern_by_algo) }

global_first_date, global_last_date, global_trading_day_count = trade_date_range(trades)
global_full_week_mondays = countable_mon_fri_weeks_in_date_range(global_first_date, global_last_date)

print_loaded_trade_span_summary(
  trade_count: trades.size,
  first_date: global_first_date,
  last_date: global_last_date,
  trading_day_count: global_trading_day_count,
  full_week_mondays: global_full_week_mondays,
  io: $stderr
)

rows = build_rows(
  trades,
  global_first_date,
  global_last_date,
  global_trading_day_count,
  global_full_week_mondays,
  pattern_for_algo: pattern_for_algo
)

if exclude_algos_with_tradecount_less_than_xpercent_of_highestTradeCountAlgo.positive?
  before_count = rows.size
  highest_trade_count = rows.map { |row| row[:tradesCount].to_i }.max
  rows = exclude_low_trade_count_algos(
    rows,
    exclude_algos_with_tradecount_less_than_xpercent_of_highestTradeCountAlgo
  )
  excluded_count = before_count - rows.size
  min_keep = (highest_trade_count * exclude_algos_with_tradecount_less_than_xpercent_of_highestTradeCountAlgo) / 100.0
  warn "Excluded #{excluded_count} algos with tradesCount <= #{min_keep.round(2)} " \
       "(#{exclude_algos_with_tradecount_less_than_xpercent_of_highestTradeCountAlgo}% of highest #{highest_trade_count}); " \
       "#{rows.size} algos remain"
end

write_rows(
  OUTPUT_PATH,
  rows_with_family_all(
    rows,
    trades,
    FAMILY_ALL_PATTERN,
    global_first_date,
    global_last_date,
    global_trading_day_count,
    global_full_week_mondays
  )
)
warn "Wrote #{rows.size + 1} rows to #{OUTPUT_PATH} (includes ALL/#{FAMILY_ALL_PATTERN})"

flashcrash_trades = trades.select { |trade| trade_in_flashcrash_analysis_range?(trade) }
flashcrash_rows = build_flashcrash_rows(trades, pattern_for_algo: pattern_for_algo)
if flashcrash_rows.empty?
  warn "Skipped #{FLASHCRASH_OUTPUT_PATH}: no algos with a trade before " \
       "#{format_date(FLASHCRASH_TRADE_BEFORE)} and after #{format_date(FLASHCRASH_TRADE_AFTER)}"
else
  global_first_date, global_last_date, global_trading_day_count, global_full_week_mondays = flashcrash_global_context
  write_rows(
    FLASHCRASH_OUTPUT_PATH,
    rows_with_family_all(
      flashcrash_rows,
      flashcrash_trades,
      FAMILY_ALL_PATTERN,
      global_first_date,
      global_last_date,
      global_trading_day_count,
      global_full_week_mondays
    )
  )
  warn "Wrote #{flashcrash_rows.size + 1} rows to #{FLASHCRASH_OUTPUT_PATH} " \
       "(includes ALL/#{FAMILY_ALL_PATTERN}; analysis range #{format_date(FLASHCRASH_ANALYSIS_START)}..#{format_date(FLASHCRASH_ANALYSIS_END)})"
end

except_flashcrash_trades = trades_except_flashcrash_analysis_range(trades)
if except_flashcrash_trades.empty?
  warn "Skipped #{EXCEPT_FLASHCRASH_OUTPUT_PATH}: no trades outside flashcrash analysis range " \
       "#{format_date(FLASHCRASH_ANALYSIS_START)}..#{format_date(FLASHCRASH_ANALYSIS_END)}"
else
  except_first_date, except_last_date, except_trading_day_count = trade_date_range(except_flashcrash_trades)
  except_full_week_mondays = countable_mon_fri_weeks_in_date_range(except_first_date, except_last_date)
  except_rows = build_rows(
    except_flashcrash_trades,
    except_first_date,
    except_last_date,
    except_trading_day_count,
    except_full_week_mondays,
    pattern_for_algo: pattern_for_algo
  )

  if exclude_algos_with_tradecount_less_than_xpercent_of_highestTradeCountAlgo.positive?
    before_count = except_rows.size
    highest_trade_count = except_rows.map { |row| row[:tradesCount].to_i }.max
    except_rows = exclude_low_trade_count_algos(
      except_rows,
      exclude_algos_with_tradecount_less_than_xpercent_of_highestTradeCountAlgo
    )
    excluded_count = before_count - except_rows.size
    min_keep = (highest_trade_count * exclude_algos_with_tradecount_less_than_xpercent_of_highestTradeCountAlgo) / 100.0
    warn "Except-flashcrash: excluded #{excluded_count} algos with tradesCount <= #{min_keep.round(2)} " \
         "(#{exclude_algos_with_tradecount_less_than_xpercent_of_highestTradeCountAlgo}% of highest #{highest_trade_count}); " \
         "#{except_rows.size} algos remain"
  end

  write_rows(
    EXCEPT_FLASHCRASH_OUTPUT_PATH,
    rows_with_family_all(
      except_rows,
      except_flashcrash_trades,
      FAMILY_ALL_PATTERN,
      except_first_date,
      except_last_date,
      except_trading_day_count,
      except_full_week_mondays
    )
  )
  warn "Wrote #{except_rows.size + 1} rows to #{EXCEPT_FLASHCRASH_OUTPUT_PATH} " \
       "(includes ALL/#{FAMILY_ALL_PATTERN}; all trades except #{format_date(FLASHCRASH_ANALYSIS_START)}..#{format_date(FLASHCRASH_ANALYSIS_END)})"
end

File.write(OUTPUT_TIMESTAMP_PATH, Time.now.to_i.to_s)
warn 'RAN OK'

end
