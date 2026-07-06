# frozen_string_literal: true

# Shared analysis thresholds for analyze_subvariants*.rb scripts.
# Banned calendar (aleksik non-trade dates): see aleksik_non_trade_calendar.rb + analyze_traderate_common.rb

MINIMUM_PROFITFACTOR = 1.6
CHECK_MINIMUM_TRADERATE_ENABLED = false
CHECK_MINIMUM_TRADERATE_VALUE = 0.04
CHECK_MINIMUM_TRADERATEWEEKLY_ENABLED = true
CHECK_MINIMUM_TRADERATEWEEKLY_VALUE = 0.26
MAXIMUM_PROFITFACTOR = 9999999999999999999999999.9

MAX_COMBINATION_SIZE = 4

GROUPING_SAMPLEDATES_MAX = 3

MERGE_SAME_RESULTS = true

PRINT_PROGRESS_LOG = false

def progress_puts(*args)
  puts(*args) if PRINT_PROGRESS_LOG
end

def print_trade_span_summary(trade_count:, first_date:, last_date:, trading_day_count:, full_week_mondays:, io: $stdout)
  print_loaded_trade_span_summary(
    trade_count: trade_count,
    first_date: first_date,
    last_date: last_date,
    trading_day_count: trading_day_count,
    full_week_mondays: full_week_mondays,
    io: io,
    weekly_trade_rate_check_enabled: CHECK_MINIMUM_TRADERATEWEEKLY_ENABLED,
    minimum_weekly_trade_rate: CHECK_MINIMUM_TRADERATEWEEKLY_VALUE
  )
end
