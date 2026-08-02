#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'analyze_algos_performance_common'

self.traderate_account_for_banned_days = false

include AnalyzeAlgosPerformanceCommon

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
INPUT_PATH = File.join(SCRIPT_DIR, 'summary_tradeResults_all_days_level.tsv')
OUTPUT_PATH = File.join(SCRIPT_DIR, 'analyze_level_algos_performance_output.csv')
FLASHCRASH_OUTPUT_PATH = File.join(
  SCRIPT_DIR,
  'analyze_level_algos_performance_output_2025flashcrash.csv'
)
EXCEPT_FLASHCRASH_OUTPUT_PATH = File.join(
  SCRIPT_DIR,
  'analyze_level_algos_performance_output_except_2025flashcrash.csv'
)
OUTPUT_TIMESTAMP_PATH = File.join(SCRIPT_DIR, 'analyze_level_algos_performance_output.timestamp')

FAMILY_ALL_PATTERN = 'LEVEL'
pattern_for_algo = ->(_algo_id) { 'LEVEL' }

if __FILE__ == $PROGRAM_NAME

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
  fc_first_date, fc_last_date, fc_trading_day_count, fc_full_week_mondays = flashcrash_global_context
  write_rows(
    FLASHCRASH_OUTPUT_PATH,
    rows_with_family_all(
      flashcrash_rows,
      flashcrash_trades,
      FAMILY_ALL_PATTERN,
      fc_first_date,
      fc_last_date,
      fc_trading_day_count,
      fc_full_week_mondays
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
