#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'alert_done_common'

DO_ALGOS_PERFORMANCE_OUTPUT_2025FLASHCRASH = false
DO_ALGOS_PERFORMANCE_OUTPUT_EXCEPT_2025FLASHCRASH = false
LOG_ALL_ROW = false

require_relative 'analyze_algos_performance_common'

self.traderate_account_for_banned_days = false
self.log_all_row = LOG_ALL_ROW

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

minimum_profitpercentsum = 80

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

rows = filter_rows_by_minimum_profit_percent_sum(
  build_rows(
    trades,
    global_first_date,
    global_last_date,
    global_trading_day_count,
    global_full_week_mondays,
    pattern_for_algo: pattern_for_algo
  ),
  minimum_profitpercentsum
)

write_rows(
  OUTPUT_PATH,
  output_rows = rows_with_family_all(
    rows,
    trades,
    FAMILY_ALL_PATTERN,
    global_first_date,
    global_last_date,
    global_trading_day_count,
    global_full_week_mondays
  )
)
warn "Wrote #{output_rows.size} rows to #{OUTPUT_PATH}" \
     "#{LOG_ALL_ROW ? " (includes ALL/#{FAMILY_ALL_PATTERN})" : ''}"

if DO_ALGOS_PERFORMANCE_OUTPUT_2025FLASHCRASH
  flashcrash_trades = trades.select { |trade| trade_in_flashcrash_analysis_range?(trade) }
  flashcrash_rows = build_flashcrash_rows(trades, pattern_for_algo: pattern_for_algo)
  if flashcrash_rows.empty?
    warn "Skipped #{FLASHCRASH_OUTPUT_PATH}: no algos with a trade before " \
         "#{format_date(FLASHCRASH_TRADE_BEFORE)} and after #{format_date(FLASHCRASH_TRADE_AFTER)}"
  else
    fc_first_date, fc_last_date, fc_trading_day_count, fc_full_week_mondays = flashcrash_global_context
    write_rows(
      FLASHCRASH_OUTPUT_PATH,
      flashcrash_output_rows = rows_with_family_all(
        flashcrash_rows,
        flashcrash_trades,
        FAMILY_ALL_PATTERN,
        fc_first_date,
        fc_last_date,
        fc_trading_day_count,
        fc_full_week_mondays
      )
    )
    warn "Wrote #{flashcrash_output_rows.size} rows to #{FLASHCRASH_OUTPUT_PATH} " \
         "#{LOG_ALL_ROW ? "(includes ALL/#{FAMILY_ALL_PATTERN}; " : '('}" \
         "analysis range #{format_date(FLASHCRASH_ANALYSIS_START)}..#{format_date(FLASHCRASH_ANALYSIS_END)})"
  end
else
  warn "Skipped #{FLASHCRASH_OUTPUT_PATH} (DO_ALGOS_PERFORMANCE_OUTPUT_2025FLASHCRASH = false)"
end

if DO_ALGOS_PERFORMANCE_OUTPUT_EXCEPT_2025FLASHCRASH
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
      except_output_rows = rows_with_family_all(
        except_rows,
        except_flashcrash_trades,
        FAMILY_ALL_PATTERN,
        except_first_date,
        except_last_date,
        except_trading_day_count,
        except_full_week_mondays
      )
    )
    warn "Wrote #{except_output_rows.size} rows to #{EXCEPT_FLASHCRASH_OUTPUT_PATH} " \
         "#{LOG_ALL_ROW ? "(includes ALL/#{FAMILY_ALL_PATTERN}; " : '('}" \
         "all trades except #{format_date(FLASHCRASH_ANALYSIS_START)}..#{format_date(FLASHCRASH_ANALYSIS_END)})"
  end
else
  warn "Skipped #{EXCEPT_FLASHCRASH_OUTPUT_PATH} (DO_ALGOS_PERFORMANCE_OUTPUT_EXCEPT_2025FLASHCRASH = false)"
end

warn 'RAN OK'

end

play_alert_done! if __FILE__ == $PROGRAM_NAME
