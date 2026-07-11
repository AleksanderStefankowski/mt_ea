//+------------------------------------------------------------------+
//|                                                    aleksik2.mq5 |
//+------------------------------------------------------------------+
//|                   MetaTrader 5 Only (MT5-specific code)          |
//|        Copyright 2026, Aleksander Stefankowski                   |
// COMPOSITE MAGIC: 18-digit fixed-width magics; first 3 digits = algo number (100..999). Never paste full magic in comments.
// aleksik2: breakdown algo family (200..299) + level/market data logging. Level-family trade algos (100..199) removed.
// Future algo families (e.g. open-gap) wire their own registry + Run*TradePipeline.


#property copyright "Copyright 2026, Aleksander Stefankowski"

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>

//--- MT5 hard limit for ORDER_COMMENT / deal comment on many builds (truncate beyond this breaks parsing intent).
#define MT5_ORDER_COMMENT_MAX_LEN 31

//--- Stops EA and further execution when required data/handle is missing (no silent fallbacks).
void FatalError(string msg)
{
   Print("FATAL: ", msg);
   ExpertRemove();
}
string   InpSessionFirstLastCandleFile = "SessionFirstLastCandle.txt";  // written in OnDeinit: symbol, timeframe, first/last candle OHLC
string   InpAllCandleFile     = "AllCandlesLog_Timer1";
double   LevelCountsAsBroken_Threshold = -2.5; // how deep close must breach to count as broken
input int      HowManyCandlesAboveLevel_CountAsPriceRecovered = 6; // for RecoverCount
// false: skip per-bar UpdateTradeResultsForDay (no HistorySelect each M1); g_tradeResults cleared each bar — EOD block still calls UpdateTradeResultsForDay once before trade-results CSV (and after EOD closes). Intraday pullinghistory/dayProgress rows stay deal-empty until that EOD refresh.
input bool     InpLoadTradeResultsFromHistory = true;
bool     InpEODLogging = true;  // if true: write EOD logs in eod_log_start/end window (pullinghistory, trade results, levels, etc.)
//--- Log to file: set false to disable that log (optimization)
//    finalLog_ = one file across whole run; dailyEODlog_ = daily once at EOD; dailySpamLog_ = daily and frequent
bool     dailyEODlog_DailySummary     = true;  // Day_activeLevels, account, orders, deals (WriteDailySummary)
bool     dailyEODlog_EodTradesSummary = false;  // (date)_summary_EOD_tradesSummary1line.csv
bool     dailyEODlog_BreakCheck       = true;  // levels_breakCheck files + summary
bool     dailySpamLog_LivePrice       = false;  // (date)_testing_liveprice.csv 21:35-21:37
bool     dailyEODlog_DayStat          = true;  // (date)_dayPriceStat_and_gapstat_log.csv (TryLogDayStatForCurrentDay)
bool     dailyEODlog_Gaplog           = false;  // LOWPERFORMANCE? (date)_gaplog.csv — per M1: PDC/RTH open, gap fill %, gap range, Gap_as_%_of_ONrange, ON, closest levels
bool     dailyLog_StaticMarketContext = true;  // (date)_staticMarketContext_log.csv — PDO/PDH/PDL/PDC once per day right after UpdateStaticMarketContext

bool     finalLog_DayStatSummary      = false;  // dayPriceStat_and_gapstat_summaryLog_gapDowns.csv + _gapUps.csv (WriteDayStatSummaryCsv)
bool     finalLog_TradeLog            = false; // (date)_B_TradeLog_algoN.csv per wired algo (WriteTradeLog)
bool     dailySpamLog_AllCandles      = true;  // (date)-AllCandlesLog_Timer1.csv
bool     finalLog_FirstLastCandle     = true;  // InpSessionFirstLastCandleFile (OnDeinit)
bool     finalLog_benchmark_buyAndHold = true;  // benchmark_buyAndHold.csv — first/last day OHLC + diff (OnInit truncate)
string   InpCalendarFile        = "calendar_2026_dots.csv";  // CSV in Terminal/Common/Files: date (YYYY.MM.DD),dayofmonth,dayofweek,opex,qopex
string   InpLevelsFile          = "levelsinfo_zeFinal.csv";  // CSV in Terminal/Common/Files: start,end,levelPrice,categories,tag (multi-year OK)
double   InpBreakCheckMaxDistPoints = 9.0;  // levels_breakCheck: first candle beyond this distance in price (and all newer) excluded
bool     maemfe_testing             = false; // if tru: all trades use TP=SL=3000.0 and close any position open >20 min (OnTimer)
bool     bigflipper_log_algo_trade_results_csv             = false; // (date)_summaryZ_tradeResults_ALL_Day_algoN.csv
bool     bigflipper_log_summary_tradeResults_all_days      = true;  // summary_tradeResults_all_days.tsv (level family only)
bool     bigflipper_log_summary_tradeResults_all_days_algo = false; // summary_tradeResults_all_days_algoN.tsv (per level algo)
bool     bigflipper_log_summary_tradeResults_all_days_breakdown = true;  // summary_tradeResults_all_days_breakdown.tsv
bool     bigflipper_log_breakdown_trade_lifetime             = true;  // bdalgoN_alltrades_log.csv + benchmark_all_algos_breakdown.csv — truncated on OnInit each run
bool     bigflipper_log_all_breakdowns                       = true;  // all_breakdowns_{type}_streakNorMore.csv + all_breakdowns_summaries.csv — per run, OnInit truncate
#define  BREAKDOWN_AUDIT_LOG_MIN_STREAK_ARG                   3
double   BREAKDOWN_AUDIT_LOG_FIRST_CANDLE_BREAKDOWN_PERCENT_ARG = 0.20;  // strong-red M15 start gate for audit log only
//--- Big flippers bookmark: master off for heavy algo logs (when false, no write for any registered algo)
bool     dailyLog_algoFamilyDayStartWeekPerspective = true;  // (date)_algofamily_dayStart_weekPerspective.csv — today-loaded levels vs week M1 at day start only
bool     dailyEODlog_PullingHistoryAlgoFamily = false;  // (date)_pullinghistory_a_algofamily_weekly.csv + _daily.csv (same neutral columns; scope differs by filename)
bool     bigflipper_log_B_TradeLog                        = false;  // (date)_B_TradeLog_algoN.csv
bool     bigflipper_log_testinglevelsplus                 = false;  // (date)_testinglevelsplus_(level)_(tag).csv per level
bool     bigflipper_log_Arawevents                        = false;  // (date)-(date)_Arawevents_(level)_(tag)_week_(date).csv per level
bool     bigflipper_log_algo_gates_per_minute              = true;  // (date)_algoN_gates_per_minute.csv — enabled algos only
int      eod_log_start_hour                                =  21;  // originally 21 // EOD log window start (server time; broker clock incl. DST)
int      eod_log_start_minute                              =  58;  // originally 58
int      eod_log_end_hour                                  =  22;  // originally 22 EOD log window end inclusive (server time)
int      eod_log_end_minute                                =   0;  // originally 0
//--- Per-second logs (shared time window below)
bool     bigflipper_log_testing_algofamily_per_second      = true;  // (date)_pullinghistory_b_algofamily_per_second_weekly.csv + _daily.csv
bool     bigflipper_log_algo_gates_per_second              = true;  // (date)_algoN_gates_per_second.csv — enabled algos only
bool     bigflipper_log_algo_trade_telemetry_per_second    = true;  // (date)_algoN_trade_telemetry_per_second.csv
bool     bigflipper_log_algo_velocity_parameter_testing_per_second = false;  // (date)_algoN_velocity_parameter_testing.csv
int      per_second_log_start_hour                         =   10;  // shared inclusive window start (server time) — all 4 per-second logs above
int      per_second_log_start_minute                       =  33;
int      per_second_log_end_hour                           =  10;  // shared inclusive window end (server time)
int      per_second_log_end_minute                         =  36;
bool     backtest_profile_enabled                          = true;   // strategy tester only: section wall-time → backtest_profile_*.tsv
// false: backtest — incremental closed bars only; full replay on new day / track change / bar shrink.
// true: live-safe — same incremental base + forming-bar scratch pass + full replay on gap / reconnect / revised last closed bar.
bool     bigflipper_pullinghistory_always_full_replay      = false; // ALGOBOOKMARKLIVE
bool     bigflipper_tradeResult_referencePoints_excludeTooClose = false;  // trade-results CSV: omit reference points too close to level
double   tradeResult_referencePointMinAbsDiffFromLevel = 4.0; //bookmark // price points; |ref - level| < this counts as too close when flipper above is on
int      tradeResult_referencePoints_movingLookback_seconds = 180;  // bookmark moving trade-result context: bar at (startTime - this); refs, dayBrokePDH/PDL
int      tradeResult_maeFirst_window_seconds = 15;  // bookmark // trade-results CSV column MAEfirst{N}: worst MAE in first N seconds (telemetry per-second)

int FalgoTradeResultMaeFirstWindowSeconds()
{
   if(tradeResult_maeFirst_window_seconds < 1)
      return 1;
   return tradeResult_maeFirst_window_seconds;
}

string FalgoTradeResultMaeFirstCsvColumnName()
{
   return "MAEfirst" + IntegerToString(FalgoTradeResultMaeFirstWindowSeconds());
}

bool     babysit_global_flipper = true; // bookmark3. when true, OnTimer may run per-row SL babysit for positions whose variant has babysit_enabled
bool     babysit_secret_TPSL = true; // if true, I will be using bigger TPSL but aim to auto close via _Xpercent_onWayTo_

//--- Global base trade size: actual lot = base × (trade_size_percentage/100). Each ruleset has its own percentage (10,20,...,100).
// base lot; 100% trade type = this full size; 50% = half, for example 0.1, tradesize 10 is 0.01, size 30 is 0.03
// for example, 0.5, and specific trade is 30%, would mean position 0.15, 60% = 0.30
// for example, 1.2, and specific trade is 30%, would mean position 0.36, 50% = 0.60
// profit factor danego trade jest stały przy jego różnych trade size, ale profit factor całego runu zmieni się bo zmieniają się proporcje absolutnego zysku


double   g_global_base_trade_size = 0.001; //  0.001 min. bookmark9 basetradesize basesize defaultsize globalsize
#define TRADE_VARIANT_COUNT_MAX_LOTSIZE 4.0
const double one_lot_equals_xPLN = 65000.0;  // PLN notional per 1.0 lot; 0.001 lot => 65 PLN deposit equivalent
const double ACCOUNT_SIZE_PLN_FOR_TRADE_SIZE = 50000000.0; //  5000000.0/ PLN budget ceiling vs ValidateBaseTradeSizeVsAccountBudgetOnInit()

// OnTimer (1s): FatalError if (used margin / equity)×100 exceeds this (terminal-style deposit load as % of equity locked in margin). 0 = disabled.
double   DepositLoadFatalThresholdPct = 0.0; // ≤ 0 disables the check

//--- Algo family pipeline: per-algo open/pending on _Symbol (refreshed once per tick via RefreshOccupiedMagicsCache).
bool   g_occupiedAlgoFamilySlots[1000];  // index = algo number 100..999: open position or pending on _Symbol
#define MAX_BANNED_RANGES 20
int g_bannedRangesBuffer[][4];       // dynamic, filled by ParseBannedRanges
int g_bannedRangesCount = 0;

struct Level
{
   string baseName;
   double price;
   datetime validFrom;
   datetime validTo;
   string tagsCSV;
   int count;
   double dailyBias;
   bool biasSetToday;
   datetime lastBiasDate;
   int logRawEv_fileHandle;
   int candlesBreakLevelCount;
   int recoverCount;
   int consecutiveRecoverCandles;
};
Level levels[];

//--- Algo-family composite magic (18 digits); B_TradeLog groups by algo prefix (algo10, algo16, …)
const long DEFAULT_ORDER_MAGIC = 47001; // restore CTrade magic when not using an algo composite magic

// First 3 digits = algo number 100..999.
#define COMPOSITE_MAGIC_STRING_LEN   18
CTrade ExtTrade;
COrderInfo ExtOrderInfo;
CPositionInfo ExtPositionInfo;
CDealInfo ExtDealInfo;


//+------------------------------------------------------------------+
//| OnTimer: stop EA if used margin exceeds threshold % of equity (same idea as MT5 deposit load; not margin/freeMargin×100). |
//| DepositLoadFatalThresholdPct ≤ 0 disables the check. |
//+------------------------------------------------------------------+
void CheckDepositLoadFatalIfExceeded()
{
   if(DepositLoadFatalThresholdPct <= 0.0) return;
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double marginUsed = AccountInfoDouble(ACCOUNT_MARGIN);
   if(equity <= 0.0) return;
   const double loadPct = 100.0 * marginUsed / equity;
   if(loadPct > DepositLoadFatalThresholdPct)
      FatalError(StringFormat("Deposit load %.2f%% (margin/equity×100) exceeds %.2f%% — equity=%.2f margin=%.2f freeMargin=%.2f symbol=%s",
         loadPct, DepositLoadFatalThresholdPct, equity, marginUsed, AccountInfoDouble(ACCOUNT_MARGIN_FREE), _Symbol));
}

//--- Timer-based candle tracking
datetime current_candle_time = 0;
double candle_open=0, candle_high=0, candle_low=0, candle_close=0;

//--- First/last candle summary
datetime first_candle_time = 0;
double first_open, first_high, first_low, first_close;
datetime last_candle_time = 0;
double last_open, last_high, last_low, last_close;

//--- Per-day AllCandles log
int allCandlesFileHandle = INVALID_HANDLE;
datetime allCandlesFileDate = 0;

//--- Daily summary tracking
//--- EOD account snapshot (filled when WriteDailySummary runs; log reads from here)
double EODpulled_balance = 0.0;
double EODpulled_equity = 0.0;
double EODpulled_freeMargin = 0.0;
double EODpulled_marginLevel = 0.0;
int EODpulled_openPositions = 0;
int EODpulled_pendingOrders = 0;

//--- Current time (server); set in OnTimer(1s), use instead of TimeCurrent()
datetime g_lastTimer1Time = 0;

//--- OnTimer(1s) wall time (GetMicrosecondCount): min/max elapsed µs per calendar day; one Print at 21:30 (GetTickCount64 is ~16ms quantum on Windows—too coarse here)
datetime g_onTimerDuration_dayStart = 0;
ulong    g_onTimerDuration_minUsToday = 0;
ulong    g_onTimerDuration_maxUsToday = 0;
int      g_onTimerDuration_samplesToday = 0;
datetime g_onTimerDuration_logged2130ForDay = 0;

//--- Backtest section profiler (GetMicrosecondCount wall time; tester only when backtest_profile_enabled)
#define BACKTEST_PROF_FALGO_PLACEMENT           0
#define BACKTEST_PROF_BREAKDOWN_PLACEMENT       1
#define BACKTEST_PROF_GATES_LOG_PER_SECOND      2
#define BACKTEST_PROF_GATES_LOG_PER_MINUTE      3
#define BACKTEST_PROF_BABYSIT                   4
#define BACKTEST_PROF_TELEMETRY_PER_SEC         5
#define BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_NEW_DAY      6
#define BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_COPY_RATES   7
#define BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_RTH_PDC        8
#define BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_EXPAND_DIFFS   9
#define BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_BREAKS        10
#define BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_STREAKS       11
#define BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_ABOVE_BELOW   12
#define BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_PULLINGHISTORY_TRACK_SETUP 13
#define BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_PULLINGHISTORY_FORWARD_PASS 14
#define BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_PULLINGHISTORY_CLOSEST_SNAP 15
#define BACKTEST_PROF_TRADE_RESULTS_HISTORY     16
#define BACKTEST_PROF_M1_BAR_CLOSE_SET_OHLC     17
#define BACKTEST_PROF_M1_BAR_CLOSE_FINALIZE_CANDLE 18
#define BACKTEST_PROF_M1_BAR_CLOSE_ATBAR_STATS  19
#define BACKTEST_PROF_M1_BAR_CLOSE_DAY_PROGRESS 20
#define BACKTEST_PROF_M1_BAR_CLOSE_ACCOUNT_BAR_STATS 21
#define BACKTEST_PROF_M1_BAR_CLOSE_LEVEL_TRADE_STATS 22
#define BACKTEST_PROF_M1_BAR_CLOSE_GATES_FALGO  23
#define BACKTEST_PROF_M1_BAR_CLOSE_GAPLOG       24
#define BACKTEST_PROF_M1_BAR_CLOSE_EOD_LOGGING  25
#define BACKTEST_PROF_ONTIMER_TOTAL             26
#define BACKTEST_PROF_FALGO_DAY_TRADE_COUNTS    27
#define BACKTEST_PROF_ALGOFAMILY_LOG_PER_SECOND 28
#define BACKTEST_PROF_BREAKDOWN_AUDIT_SCAN      29
#define BACKTEST_PROF_BENCHMARK_BUY_HOLD        30
#define BACKTEST_PROF_STATIC_MARKET_CONTEXT     31
#define BACKTEST_PROF_TRADE_RESULTS_ENRICH      32
#define BACKTEST_PROF_TRADE_RESULTS_EOD_FLUSH   33
#define BACKTEST_PROF_BREAKDOWN_BENCHMARK_ALGOS 34
#define BACKTEST_PROF_SUMMARY_TRADE_RESULTS_TSV 35
#define BACKTEST_PROF_SECTION_COUNT             36

struct BacktestProfBucket
{
   ulong totalUs;
   ulong maxUs;
   int   calls;
};

BacktestProfBucket g_backtestProfRunTotals[BACKTEST_PROF_SECTION_COUNT];
BacktestProfBucket g_backtestProfDayTotals[BACKTEST_PROF_SECTION_COUNT];
datetime           g_backtestProfTrackingDayStart = 0;

//+------------------------------------------------------------------+
bool BacktestProfileEnabled()
{
   if(!backtest_profile_enabled)
      return false;
   return (bool)MQLInfoInteger(MQL_TESTER);
}

//+------------------------------------------------------------------+
string BacktestProfSectionLabel(const int section)
{
   switch(section)
   {
      case BACKTEST_PROF_FALGO_PLACEMENT:          return "falgo_placement";
      case BACKTEST_PROF_BREAKDOWN_PLACEMENT:      return "breakdown_placement";
      case BACKTEST_PROF_GATES_LOG_PER_SECOND:     return "gates_log_per_second";
      case BACKTEST_PROF_GATES_LOG_PER_MINUTE:     return "gates_log_per_minute";
      case BACKTEST_PROF_BABYSIT:                  return "babysit";
      case BACKTEST_PROF_TELEMETRY_PER_SEC:        return "telemetry_per_sec";
      case BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_NEW_DAY:       return "update_day_m1_levels_new_day_reload";
      case BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_COPY_RATES:    return "update_day_m1_levels_copy_rates";
      case BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_RTH_PDC:       return "update_day_m1_levels_rth_pdc_levels";
      case BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_EXPAND_DIFFS:   return "update_day_m1_levels_expand_diffs";
      case BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_BREAKS:        return "update_day_m1_levels_breaks";
      case BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_STREAKS:       return "update_day_m1_levels_streaks";
      case BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_ABOVE_BELOW:   return "update_day_m1_levels_above_below_session";
      case BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_PULLINGHISTORY_TRACK_SETUP: return "update_day_m1_levels_pullinghistory_track_setup";
      case BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_PULLINGHISTORY_FORWARD_PASS: return "update_day_m1_levels_pullinghistory_forward_pass";
      case BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_PULLINGHISTORY_CLOSEST_SNAP: return "update_day_m1_levels_pullinghistory_closest_snap";
      case BACKTEST_PROF_TRADE_RESULTS_HISTORY:    return "trade_results_history";
      case BACKTEST_PROF_M1_BAR_CLOSE_SET_OHLC:    return "m1_bar_close_set_ohlc";
      case BACKTEST_PROF_M1_BAR_CLOSE_FINALIZE_CANDLE: return "m1_bar_close_finalize_candle";
      case BACKTEST_PROF_M1_BAR_CLOSE_ATBAR_STATS: return "m1_bar_close_atbar_stats";
      case BACKTEST_PROF_M1_BAR_CLOSE_DAY_PROGRESS: return "m1_bar_close_day_progress";
      case BACKTEST_PROF_M1_BAR_CLOSE_ACCOUNT_BAR_STATS: return "m1_bar_close_account_bar_stats";
      case BACKTEST_PROF_M1_BAR_CLOSE_LEVEL_TRADE_STATS: return "m1_bar_close_level_trade_stats";
      case BACKTEST_PROF_M1_BAR_CLOSE_GATES_FALGO: return "m1_bar_close_gates_log";
      case BACKTEST_PROF_M1_BAR_CLOSE_GAPLOG:      return "m1_bar_close_gaplog";
      case BACKTEST_PROF_M1_BAR_CLOSE_EOD_LOGGING: return "m1_bar_close_eod_logging";
      case BACKTEST_PROF_ONTIMER_TOTAL:            return "ontimer_total";
      case BACKTEST_PROF_FALGO_DAY_TRADE_COUNTS:   return "falgo_day_trade_counts";
      case BACKTEST_PROF_ALGOFAMILY_LOG_PER_SECOND: return "algofamily_log_per_second";
      case BACKTEST_PROF_BREAKDOWN_AUDIT_SCAN:    return "breakdown_audit_scan";
      case BACKTEST_PROF_BENCHMARK_BUY_HOLD:      return "benchmark_buy_hold";
      case BACKTEST_PROF_STATIC_MARKET_CONTEXT:   return "static_market_context";
      case BACKTEST_PROF_TRADE_RESULTS_ENRICH:    return "trade_results_enrich";
      case BACKTEST_PROF_TRADE_RESULTS_EOD_FLUSH: return "trade_results_eod_flush";
      case BACKTEST_PROF_BREAKDOWN_BENCHMARK_ALGOS: return "breakdown_benchmark_algos";
      case BACKTEST_PROF_SUMMARY_TRADE_RESULTS_TSV: return "summary_trade_results_tsv";
   }
   return "unknown";
}

//+------------------------------------------------------------------+
void BacktestProfZeroBuckets(BacktestProfBucket &buckets[])
{
   for(int i = 0; i < BACKTEST_PROF_SECTION_COUNT; i++)
   {
      buckets[i].totalUs = 0;
      buckets[i].maxUs = 0;
      buckets[i].calls = 0;
   }
}

//+------------------------------------------------------------------+
void BacktestProfAccumulate(const int section, const ulong t0)
{
   if(section < 0 || section >= BACKTEST_PROF_SECTION_COUNT)
      return;
   const ulong elapsed = GetMicrosecondCount() - t0;
   g_backtestProfRunTotals[section].totalUs += elapsed;
   g_backtestProfRunTotals[section].calls++;
   if(elapsed > g_backtestProfRunTotals[section].maxUs)
      g_backtestProfRunTotals[section].maxUs = elapsed;
   g_backtestProfDayTotals[section].totalUs += elapsed;
   g_backtestProfDayTotals[section].calls++;
   if(elapsed > g_backtestProfDayTotals[section].maxUs)
      g_backtestProfDayTotals[section].maxUs = elapsed;
}

//+------------------------------------------------------------------+
ulong BacktestProfSumProfiledUsExceptOnTimer(const BacktestProfBucket &buckets[])
{
   ulong sum = 0;
   for(int i = 0; i < BACKTEST_PROF_SECTION_COUNT; i++)
   {
      if(i == BACKTEST_PROF_ONTIMER_TOTAL)
         continue;
      sum += buckets[i].totalUs;
   }
   return sum;
}

//+------------------------------------------------------------------+
void BacktestProfWriteOneBucketRow(const int fh, const string datePrefix, const int section,
   const BacktestProfBucket &buckets[], const ulong denomUs)
{
   if(buckets[section].calls <= 0 && buckets[section].totalUs == 0)
      return;
   const double totalMs = (double)buckets[section].totalUs / 1000.0;
   const double totalS = (double)buckets[section].totalUs / 1000000.0;
   const double totalMin = totalS / 60.0;
   const double avgMs = (buckets[section].calls > 0) ? totalMs / (double)buckets[section].calls : 0.0;
   const double maxMs = (double)buckets[section].maxUs / 1000.0;
   const double pct = (section == BACKTEST_PROF_ONTIMER_TOTAL || denomUs == 0) ? 0.0 :
      100.0 * (double)buckets[section].totalUs / (double)denomUs;
   if(StringLen(datePrefix) > 0)
   {
      FileWrite(fh, datePrefix, BacktestProfSectionLabel(section),
         DoubleToString(totalS, 2), DoubleToString(totalMin, 2), IntegerToString(buckets[section].calls),
         DoubleToString(avgMs, 3), DoubleToString(maxMs, 3), DoubleToString(pct, 1));
   }
   else
   {
      FileWrite(fh, BacktestProfSectionLabel(section),
         DoubleToString(totalS, 2), DoubleToString(totalMin, 2), IntegerToString(buckets[section].calls),
         DoubleToString(avgMs, 3), DoubleToString(maxMs, 3), DoubleToString(pct, 1));
   }
}

//+------------------------------------------------------------------+
void BacktestProfWriteBucketRows(const int fh, const string datePrefix, const BacktestProfBucket &buckets[])
{
   const ulong denomUs = BacktestProfSumProfiledUsExceptOnTimer(buckets);
   for(int i = 0; i < BACKTEST_PROF_SECTION_COUNT; i++)
   {
      if(i == BACKTEST_PROF_ONTIMER_TOTAL)
         continue;
      BacktestProfWriteOneBucketRow(fh, datePrefix, i, buckets, denomUs);
   }
   BacktestProfWriteOneBucketRow(fh, datePrefix, BACKTEST_PROF_ONTIMER_TOTAL, buckets, denomUs);
}

//+------------------------------------------------------------------+
void BacktestProfWriteDayRows(const datetime dayStart, const BacktestProfBucket &buckets[])
{
   const string dateStr = TimeToString(dayStart, TIME_DATE);
   const string fileName = "backtest_profile_by_day.tsv";
   int fh = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   const bool writeHeader = (FileSize(fh) == 0);
   FileSeek(fh, 0, SEEK_END);
   if(writeHeader)
      FileWrite(fh, "date", "section", "total_s", "total_minutes", "calls", "avg_ms", "max_ms", "pct_of_profiled");
   BacktestProfWriteBucketRows(fh, dateStr, buckets);
   FileClose(fh);
}

//+------------------------------------------------------------------+
void BacktestProfFlushCurrentDayIfNeeded()
{
   if(!BacktestProfileEnabled() || g_backtestProfTrackingDayStart == 0)
      return;
   BacktestProfWriteDayRows(g_backtestProfTrackingDayStart, g_backtestProfDayTotals);
}

//+------------------------------------------------------------------+
void BacktestProfOnTimerDayRollover(const datetime dayStart)
{
   if(!BacktestProfileEnabled())
      return;
   if(g_backtestProfTrackingDayStart == 0)
   {
      g_backtestProfTrackingDayStart = dayStart;
      return;
   }
   if(dayStart == g_backtestProfTrackingDayStart)
      return;
   BacktestProfWriteDayRows(g_backtestProfTrackingDayStart, g_backtestProfDayTotals);
   BacktestProfZeroBuckets(g_backtestProfDayTotals);
   g_backtestProfTrackingDayStart = dayStart;
}

//+------------------------------------------------------------------+
void BacktestProfWriteRunSummary()
{
   if(!BacktestProfileEnabled())
      return;
   BacktestProfFlushCurrentDayIfNeeded();
   const string fileName = "backtest_profile_run_summary.tsv";
   int fh = FileOpen(fileName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   FileWrite(fh, "section", "total_s", "total_minutes", "calls", "avg_ms", "max_ms", "pct_of_profiled");
   BacktestProfWriteBucketRows(fh, "", g_backtestProfRunTotals);
   FileClose(fh);
   Print("Backtest profile: ", fileName, " and backtest_profile_by_day.tsv (Tester Files folder)");
}

//--- Live price (updated every OnTimer ~1s); use for proximity/display without reading terminal each time
double g_liveBid = 0.0;
double g_liveAsk = 0.0;

//--- For OnTimer: last bar time we processed (current bar start time)
datetime g_lastBarTime = 0;

//--- Algorithm start date - only show trade history from this date in log allTradesHistoryForAllLevels_andAllAccountData
datetime dateWhenAlgoTradeStarted = StringToTime("2026.01.23 00:00");

//--- Calendar (loaded from CSV in OnInit)
struct CalendarRow
{
   string dateStr;    // "YYYY.MM.DD" (MT5 default, matches TimeToString(..., TIME_DATE))
   int    dayofmonth;
   string dayofweek;
   bool   opex;
   bool   qopex;
};
#define MAX_CALENDAR_ROWS 1100
CalendarRow g_calendar[MAX_CALENDAR_ROWS];
int g_calendarCount = 0;

//--- Levels (loaded from levelsinfo_zeFinal CSV in OnInit)
struct LevelInfoRow
{
   string startStr;   // "YYYY.MM.DD"
   string endStr;     // "YYYY.MM.DD"
   double levelPrice;
   string categories; // e.g. "daily_monday_pivot_stacked"
   string tag;       // e.g. "dailyPivot", "weeklyUp1" (loaded but not used yet)
};
#define MAX_LEVEL_ROWS 5000  // max levels active on one day; CSV may span many years (~4000+ rows total)
LevelInfoRow g_levels[MAX_LEVEL_ROWS];
int g_levelsTotalCount = 0;  // levels for current day only (reloaded each new day)
string g_levelsLoadedForDate = "";  // YYYY.MM.DD for which g_levels was loaded (empty = not yet loaded)

//--- Levels expanded (built in testing loop: each level of the day vs whole price chart; newway_Diff_CloseToLevel per bar)
struct LevelExpandedRow
{
   double levelPrice;
   string tag;
   string categories;  // from CSV; used to exclude tertiary from break-check summary
   string categoriesLower;  // lowercase copy; hot paths avoid repeated StringToLower
   int    count;      // number of bars
   double diffs[];    // newway_Diff_CloseToLevel = close - levelPrice per bar
   datetime times[];  // bar time per bar
};
#define MAX_LEVELS_EXPANDED 500 // per day (must be <= MAX_LEVEL_ROWS)
#define MAX_BARS_IN_DAY 1500 // a day has 1440 minutes
LevelExpandedRow g_levelsExpanded[MAX_LEVELS_EXPANDED];
int g_levelsTodayCount = 0;  // levels valid for current day (from g_levels); per-bar data in g_levelsExpanded[e]
// Per (level e, bar k): candle breaks level down/up (from g_m1Rates OHLC); filled in UpdateDayM1AndLevelsExpanded; logged in testinglevelsplus
bool g_breaksLevelDown[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];    // true if open > level AND close < level
bool g_breaksLevelUpward[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];  // true if open < level AND close > level
// Per (level e, bar k): number of consecutive bars (from k-1 backward) with all OHLC above/below level
int  g_cleanStreakAbove[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
int  g_cleanStreakBelow[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
// Per (level e, bar k): count and % of bars 0..k (so far today) with all OHLC above/below level
int    g_aboveCnt[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
double g_abovePerc[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
int    g_belowCnt[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
double g_belowPerc[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
// Per (level e, bar k): overlap = level between H and L; streak = consecutive overlapping bars backward; overlapC/overlapPc = count and % so far today
int    g_overlapStreak[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
int    g_overlapC[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
double g_overlapPc[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
// Per (level e, bar k): trade history for this level as of bar k close (trades with endTime < bar k close); minute-by-minute tracking
int    g_ONtradeCount_L[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
int    g_ONwins_L[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
double g_ONpointsSum_L[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
double g_ONprofitSum_L[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
int    g_RTHtradeCount_L[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
int    g_RTHwins_L[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
double g_RTHpointsSum_L[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];
double g_RTHprofitSum_L[MAX_LEVELS_EXPANDED][MAX_BARS_IN_DAY];

//--- Day M1 price data (updated every new bar; used by trade logic and by testing log)
MqlRates g_m1Rates[MAX_BARS_IN_DAY];  // day's bars only, index k = k-th bar of day
int g_barsInDay = 0;
datetime g_m1DayStart = 0;  // which day g_m1Rates is for (0 = not set)
datetime g_buyHoldFirstDayStart = 0;
double   g_buyHoldCompletedTradingMinutes = 0.0;
int      g_buyHoldSnapshotM1BarCount = 0;
double   g_buyHoldFirstOOD = 0.0;
double   g_buyHoldFirstHOD = 0.0;
double   g_buyHoldFirstLOD = 0.0;
double   g_buyHoldFirstCOD = 0.0;
bool     g_buyHoldFirstDayFrozen = false;
double   g_buyHoldRunMaxHigh = 0.0;
double   g_buyHoldRunMinLow = 0.0;
bool     g_buyHoldRunExtremesInit = false;
datetime g_buyHoldSnapshotDayStart = 0;
double   g_buyHoldSnapshotOOD = 0.0;
double   g_buyHoldSnapshotHOD = 0.0;
double   g_buyHoldSnapshotLOD = 0.0;
double   g_buyHoldSnapshotCOD = 0.0;
bool     g_buyHoldSnapshotValid = false;
datetime g_buyHoldDayOhlcDayStart = 0;
int      g_buyHoldDayOhlcBarsDone = 0;
double   g_buyHoldDayCachedOOD = 0.0;
double   g_buyHoldDayCachedHOD = 0.0;
double   g_buyHoldDayCachedLOD = 0.0;

double   g_sortedLevelPrices[MAX_LEVELS_EXPANDED];
int      g_sortedLevelPriceCount = 0;
datetime g_aboveBelowIncDayStart = 0;
int      g_aboveBelowIncLevelCount = 0;
int      g_aboveBelowIncBarsDone = 0;

datetime g_pullingHistoryPsFileDayStart = 0;
int      g_pullingHistoryPsWeeklyFh = INVALID_HANDLE;
int      g_pullingHistoryPsDailyFh = INVALID_HANDLE;
double g_ONopen = 0.0;      // Open of first (oldest) candle of the day; set when we have at least 1 bar for the day
double g_todayRTHopen = 0.0;       // RTH open (14:30 or 15:30 bar open) for current day when available
bool   g_todayRTHopenValid = false; // true once we have the RTH open bar for the day (set in UpdateDayM1AndLevelsExpanded; log as "unknown" when false)
// Per-bar data (filled in UpdateDayM1AndLevelsExpanded; logged in 21:58-22:00 window)
double g_levelAboveH[MAX_BARS_IN_DAY];  // level (levelPrice) above candle high; 0 if none
double g_levelBelowL[MAX_BARS_IN_DAY];  // level below candle low; 0 if none
string g_session[MAX_BARS_IN_DAY];      // "ON"|"RTH"|"sleep"

//--- Day stat: open gap down (RTH open < PD RTH close). Set once after 21:30 candle; logged per day and in summary.
bool     dayStat_hasGapDown = false;
bool     dayStat_hasGapUp = false;   // RTH open > PD RTH close
double   dayStat_openGapDown_percentageFill = 0.0;  // % of gap range (PD RTH close ↔ today RTH open) filled by day's H/L; 0..100
double   dayStat_gapDiff = 0.0;   // debug: range size (top - bottom)
double   dayStat_maxBeforeGapfillAttempt_over_5 = 0.0;  // max pts away from gap before first fill jump > over_5 (EOD; same as gaplog)
bool     dayStat_maxBeforeGapfillAttempt_valid = false;
double   dayStat_rthHigh = 0.0;   // debug: RTH session highest high
double   dayStat_rthLow  = 0.0;   // debug: RTH session lowest low
double   dayStat_onHigh  = 0.0;   // ON session high (same day, bars with session=ON)
double   dayStat_onLow   = 0.0;   // ON session low (same day)
bool     dayStat_ONH_t_RTH = false;  // true if rthHigh >= ONH (RTH took out overnight high)
bool     dayStat_ONL_t_RTH = false;  // true if rthLow <= ONL (RTH took out overnight low)
bool     dayStat_ONboth_t_RTH = false; // true if both ONH_t_RTH and ONL_t_RTH
double   dayStat_spreadHighestSeen = 0.0;  // highest spread (ask - bid) seen today; reset each new day
double   dayStat_spreadLowestSeen = 0.0;   // lowest spread (ask - bid) seen today; reset each new day
int      dayStat_totalDays = 0;
int      dayStat_daysWithGapDown = 0;
int      dayStat_daysWithoutGapDown = 0;
double   dayStat_gapDown_fillPercentSum = 0.0;  // sum of percentage_gap_filled for gap-down days (for avg)
double   dayStat_gapDown_rangeSum = 0.0;      // sum of gap range pts (|RTHopen-PDC|) on gap-down days
int      dayStat_daysWithGapDown_10fill = 0;   // gap-down days with percentage_gap_filled >= 10
int      dayStat_daysWithGapDown_20fill = 0;   // gap-down days with percentage_gap_filled >= 20
int      dayStat_daysWithGapDown_25fill = 0;   // gap-down days with percentage_gap_filled >= 25
int      dayStat_daysWithGapDown_30fill = 0;   // gap-down days with percentage_gap_filled >= 30
int      dayStat_daysWithGapDown_33fill = 0;   // gap-down days with percentage_gap_filled >= 33
int      dayStat_daysWithGapDown_40fill = 0;   // gap-down days with percentage_gap_filled >= 40
int      dayStat_daysWithGapDown_50fill = 0;   // gap-down days with percentage_gap_filled >= 50
int      dayStat_daysWithGapDown_60fill = 0;   // gap-down days with percentage_gap_filled >= 60
int      dayStat_daysWithGapDown_75fill = 0;   // gap-down days with percentage_gap_filled >= 75
int      dayStat_daysWithGapDown_90fill = 0;   // gap-down days with percentage_gap_filled >= 90
int      dayStat_daysWithGapDown_100fill = 0;  // gap-down days with percentage_gap_filled >= 100
datetime dayStat_lastLoggedDayStart = 0;  // avoid logging same day twice

//--- algofamily_dayStart_weekPerspective: today-loaded weekly+daily levels vs week M1 once at day start (not intraday)
struct AlgoFamilyDayStartWeekPerspectiveRow
{
   double levelPrice;
   string tag;
   string categories;
   string levelKind;           // weekly | daily | stacked
   string levelActiveFrom;     // CSV start YYYY.MM.DD
   string levelActiveTo;       // CSV end YYYY.MM.DD
   double maxPriceAbove;       // max(high - level) when high > level (M1 week scan)
   double maxPriceBelow;       // max(level - low) when low < level
   bool   brokenBool;          // M1 week: level between min ONO & max other high, or min other low & max ONO
   int    countONO_too_close_10p; // days in week where |level - that day's ONO| < 10
   int    contact1m_earlierThisWeek_physicalContactCount;       // M1 earlier this week: level in [low, high]
   int    contact1m_earlierThisWeek_contactAndProximityCount;   // M1 earlier this week: physical or proximity_threshold on OHLC
   int    bounceCount;         // M1 week total
   int    ceilingCount;
   int    ceilingProximityCandles;
};
#define MAX_ALGOFAMILY_DAYSTART_WEEK_LEVELS 60
#define ALGO5_WEEK_ON_TOO_CLOSE_POINTS 10.0
AlgoFamilyDayStartWeekPerspectiveRow g_algoFamilyDayStartWeekPerspective[MAX_ALGOFAMILY_DAYSTART_WEEK_LEVELS];
int      g_algoFamilyDayStartWeekPerspectiveCount = 0;
string   g_algoFamilyDayStartWeekPerspectiveEvaluatedForDate = "";  // YYYY.MM.DD last (re)evaluated

//--- pullinghistory_a_algofamily_{weekly|daily}: per-bar closest-level snapshot (neutral columns; weekly vs daily scope in filename only).
struct PullingHistoryAlgoFamilyBarSnap
{
   double   closestWeeklyLevelToCClose;
   int      closestWeeklyLevelExpandedIdx;  // index in g_levelsExpanded; -1 if none (same source as level price)
   double   closestPriceProximity;   // min gap candle OHLC range to closest weekly level (0 if overlap)
   double   currentCandle_AvgOf_OHLCnumbers;
   datetime cleanOHLC_streak_startTime;
   int      cleanOHLC_streak_count;
   double   cleanOHLC_streak_avgOfOHLC;
   double   closestWeeklyLevel_anchorAbove_within_cleanOHLC_streak;
   datetime closestWeeklyLevel_anchorAbove_time;
   double   closestWeeklyLevel_anchorBelow_within_cleanOHLC_streak;
   datetime closestWeeklyLevel_anchorBelow_time;
   int      closestWeeklyLevel_BounceCount_today;
   int      closestWeeklyLevel_CeilingCount_today;
   int      closestWeeklyLevel_CeilingProximityCandles_today;
   int      closestWeeklyLevel_BounceCount_recent;
   int      closestWeeklyLevel_CeilingCount_recent;
   int      closestWeeklyLevel_CeilingProximityCandles_recent;
   int      closestWeeklyLevel_physicalContactCount_today;
   int      closestWeeklyLevel_contactAndProximityCount_today;
   bool     accOpenTradeNowBool;       // symbol day trades open at this bar's close
   datetime accOpenTradeTime;          // startTime of latest still-open trade; 0 if none
   datetime accLastClosedTradeTime;    // max endTime among trades closed before this bar's close; 0 if none
   double   dayWinRate;                // mirror g_dayProgress (closed trades before bar close)
   int      dayTradesCount;
   double   dayPointsSum;
   double   dayProfitSum;
   double   dayProfitFactor;           // grossProfit/grossLoss; 999 when no losses and grossProfit>0
};
PullingHistoryAlgoFamilyBarSnap g_pullingHistoryAlgoFamilyWeeklyAtBar[MAX_BARS_IN_DAY]; // weekly-scope closest
PullingHistoryAlgoFamilyBarSnap g_pullingHistoryAlgoFamilyDailyAtBar[MAX_BARS_IN_DAY]; // daily-scope closest (stacked/daily + weekday filter)

//--- algo family: shared profile + per-algo rules (algo10, algo11, algo12)
struct AlgoSharedProfile
{
   int    tradeSizePct;
   string bannedRanges;
   bool   babysit_enabled;
   bool   mode_switching_enabled;  // master: when false, no neutral/strong/bad/terrible modes (secretTPSL + broker TP/SL only)
   bool   strong_trade_mode_enabled;     // family: strong momentum; per-algo tune applies only when master + this true
   bool   neutral_trade_mode_enabled;    // family: neutral TP exit
   bool   badtrade_mode_enabled;         // family: bad-trade recovery latch/exit
   bool   terribletrade_mode_enabled;    // family: terrible-trade recovery latch/exit
   string tradesDays;              // e.g. "12345" = Mon..Fri
   bool   secretTPSL;
   int    secretTPSL_percent;
   double initialTP;
   double initialSL;
   double extra_offset_all_longs;   // added to every long placement offset (0 = unchanged)
   double extra_offset_all_shorts;  // added to every short placement offset (0 = unchanged)
   int    revenge_long_allowed_perdayCount;
   int    revenge_short_allowed_perdayCount;
   double revenge_initialTP;
   double revenge_initialSL;
   int    stop_trading_today_if_AllAlgos_losing_trades_count;
   int    stop_trading_today_if_AllAlgos_winning_trades_count;
   bool   blockPlacementIfFamilyOpenOrPending;  // whole algo family: block any algo placement when any family open/pending on _Symbol
   int    stop_trading_if_day_has_X_wins_0_losses;       // family: stop all algos today when wins>=X and losses==0 (infinity PF cap)
   double stop_trading_if_day_has_profit_factor_above;   // family: stop all algos today when PF>this and at least 1 loss today
   int    bounce_minimum_clean_ohlc_to_qualify;          // bounce: need this many clean OHLC bars after contact-from-above (contact-clean-contact = 1 = noise)
   int    ceiling_minimum_clean_ohlc_to_qualify;         // ceiling: need this many clean OHLC bars after contact-from-below
   double bounce_minimum_HighestLow_levelDiff_to_qualify;  // bounce: highest low during clean streak must be >= this above level
   double ceiling_minimum_LowestHigh_levelDiff_to_qualify; // ceiling: lowest high during clean streak must be >= this below level
   double proximity_threshold;                           // contactCount, ceilingProximityCandles, Arawevents (physical touch always counts)
   double bounce_event_proximity_threshold;              // bounce event contact episode (physical touch always counts)
   double ceiling_event_proximity_threshold;             // ceiling event contact episode (physical touch always counts)
};

struct AlgoPerAlgoTune
{
   int    stop_trading_today_if_thisAlgo_losing_trades_count;  // stop when losses >= this
   int    stop_trading_today_if_thisAlgo_winning_trades_count;  // stop when wins >= this
   int    stop_trading_today_if_thisAlgo_total_trades_count;  // stop when wins+losses >= this
   int    babysitStart_minute;
   double neutral_trade_TP;                    // signed; 0=breakeven; close when profit >= target
   double strong_trade_TP;                     // signed; 0=breakeven; close when profit >= target
   bool   strong_trade_mode_enabled;
   bool   neutral_trade_mode_enabled;
   bool   badtrade_mode_enabled;
   bool   terribletrade_mode_enabled;
   double strong_trade_eval_min_profit_pts;
   double strong_trade_min_velocity_trigger;
   int    strong_trade_velocity_window_seconds;
   bool   strong_trade_stall_mode_uses_avgvelocity_weakening; // true: avg weaken pct; false: instant vel <= max (+ giveback)
   double strong_trade_stall_velocity_max_trigger;
   double strong_trade_stall_giveback_pts_trigger;
   double strong_trade_stall_avgvelocity_weaken_pct; // avgvelocity_stall: fire when avg < peak*(1-pct/100)
   double strong_trade_stall_min_close_profit_pts;
   int    telemetry_velocity_window_seconds;
   int    telemetry_avg_velocity_window_seconds;
   int    start_mae_care_after_x_seconds;      // MAE_post_xx: 0 until this trade age; then track min profit from that second
   double badtrade_MaePostX_trigger;           // negative MAE_post_xx latch depth when badtrade_mode_enabled
   int    badtrade_totalRedSeconds_minTrigger; // min total red seconds required to latch bad trade
   double badtrade_try_save_TP;                // signed; 0=breakeven; close when profit >= target
   double terribletrade_MaePostX_trigger;      // negative MAE_post_xx latch depth when terribletrade_mode_enabled
   int    terribletrade_consecutiveRedSeconds_minTrigger;  // min consecutive red seconds required to latch terrible trade
   double terribletrade_avgProfitVelocity10_trigger;       // avg profit velocity (10s window) must be < this to latch
   double terribletrade_try_smaller_loss_TP;   // signed; 0=breakeven; close when profit >= target
};

enum ENUM_ALGO_RULE
{
   RULE_CLEAN_STREAK_LONG,
   RULE_CLEAN_STREAK_TOO_LONG,
   RULE_ANCHOR_ABOVE_TOO_HIGH,
   RULE_CLEAN_STREAK_SHORT,
   RULE_BOUNCE_COUNT_TOO_HIGH,
   RULE_BOUNCE_COUNT_TOO_LOW,
   RULE_RECENT_BOUNCE_TOO_HIGH,
   RULE_CEILING_COUNT_TOO_HIGH,
   RULE_CEILING_COUNT_TOO_LOW,
   RULE_CEILING_PROXIMITY_CANDLES_TOO_HIGH,
   RULE_TRADES_AT_LEVEL_LIMIT,
   RULE_WEEK_BOUNCE_TOO_HIGH,
   RULE_WEEK_BOUNCE_TOO_LOW,
   RULE_WEEK_CEILING_TOO_HIGH,
   RULE_WEEK_CEILING_TOO_LOW,
   RULE_WEEK_CONTACT_CANDLES_TOO_HIGH,
   RULE_WEEK_CONTACT_CANDLES_TOO_LOW,
   RULE_LEVEL_ONO_ABS_DIFF_TOO_LOW,
   RULE_ONO_ABOVE_LEVEL_TOO_LOW,
   RULE_ONO_BELOW_LEVEL_TOO_LOW,
   RULE_DAYSTART_EARLIER_WEEK_CONTACT_TOO_HIGH,
   RULE_DAY_CONTACT_TODAY_TOO_HIGH,
   RULE_PD_RED,
   RULE_PD_GREEN,
   RULE_DAY_BROKE_PDL,
   RULE_DAY_BROKE_PDH,
   RULE_LEVEL_ABOVE_ONL,
   RULE_LEVEL_BELOW_ONL,
   RULE_LEVEL_BELOW_ONH,
   RULE_LEVEL_BELOW_DAY_HIGH,
   RULE_LEVEL_BELOW_PDH,
   RULE_LEVEL_ABOVE_DAY_LOW,
   RULE_DAY_LOW_SOFAR_NO_MORE_THAN_X_BELOW_LEVEL,
   RULE_DAY_LOW_SOFAR_AT_LEAST_X_BELOW_LEVEL,
   RULE_DAY_HIGH_SOFAR_AT_LEAST_X_ABOVE_LEVEL,
   RULE_DAY_HIGH_SOFAR_NO_MORE_THAN_X_ABOVE_LEVEL,
   RULE_LEVEL_ABOVE_PDL,
   RULE_LEVEL_BELOW_PDC,
   RULE_LEVEL_BELOW_PDO,
   RULE_LEVEL_BELOW_MIDPOINT,
   RULE_LEVEL_ABOVE_MIDPOINT,
   RULE_LEVEL_BELOW_IBH,
   RULE_LEVEL_ABOVE_ONH,
   RULE_LEVEL_ABOVE_DAY_HIGH,
   RULE_LEVEL_ABOVE_PDO,
   RULE_DAY_BROKE_PDL_TRUE,
   RULE_DAY_OF_WEEK,
   RULE_SESSION,
   RULE_DAY_GAP_DOWN_REQUIRED,
   RULE_GAP_RANGE_PTS_ABOVE,
   RULE_GAP_FILL_PC_BELOW,
   RULE_RTHO_TERTIARY_READY,
   RULE_DAY_GAP_UP_REQUIRED,
   RULE_LEVEL_BELOW_DAY_LOW,
   RULE_LEVEL_BELOW_RTHH,
   RULE_LEVEL_BELOW_RTHL,
   RULE_LEVEL_BELOW_IBL,
   RULE_LEVEL_ABOVE_PDC,
   RULE_LEVEL_ABOVE_IBH,
   RULE_LEVEL_ABOVE_IBL,
   RULE_LEVEL_ABOVE_RTHL,
   RULE_OPEN_GAP_UNKNOWN,
   RULE_LEVEL_ABOVE_PDH,
   RULE_LEVEL_BELOW_PDL,
   RULE_LEVEL_ABOVE_RTHH,
   RULE_DAY_BROKE_PDH_TRUE,
   RULE_LEVEL_TAG
};

#define ALGO_RULES_MAX            22
#define ALGO_FAMILY_REGISTRY_MAX  1
#define ALGO_FAMILY_REGISTRY_MAX_HEADROOM 3  // max may exceed wired algo count by at most this
//algobookmarkMAX

struct AlgoRuleEntry
{
   ENUM_ALGO_RULE rule_id;
   int            i0;
   int            i1;
   double         d0;
   double         d1;
   string         s0;
};

struct AlgoDef
{
   int            algo_id;
   bool           enabled;
   bool           trades_short;
   bool           tradesWeeklyLevels;  // per-algo; required in algocreator2 (at least one level type must be true)
   bool           tradesDailyLevels;
   bool           tradesTertiaryTodayRTHOLevel;  // today's RTH-open tertiary level (after nominal RTH open)
   AlgoPerAlgoTune tune;
   double         levelOffset;
   double         priceProximity;
   int            expiry_minutes;
   int            recentBounceCountToday_Minutes;
   int            recentCeilingCountToday_Minutes;
   double         min_anchorAbove_cleanStreak;
   double         max_anchorAbove_cleanStreak;
   double         min_anchorBelow_cleanStreak;
   int            min_cleanOHLC_streak_count;
   int            max_cleanOHLC_streak_count;
   int            bounceMaxAllowed_today;
   int            min_bounceCount;
   int            recentBounceCount_max_allowed;
   int            physicalCeilingMaxAllowed_today;
   int            proximityCeilingMaxAllowed_today;
   int            max_allowed_trades_perLevel_perDay_forThisAlgo;
   int            min_weekly_bounce_required;   // week bounce on closest level must be >= this (weekBounceCountTooLow rule)
   int            max_weekly_bounce_allowed;
   int            min_ceilingCount;             // daily ceiling on closest level must be >= this (ceilingCountTooLow rule)
   int            min_weekly_ceiling_required;  // week ceiling on closest level must be >= this (weekCeilingCountTooLow rule)
   int            max_weekly_ceiling_allowed;
   int            max_weekly_contact_candles_allowed;  // weekContactCandlesTooHigh rule
   double         min_levelOnoAbsDiff;
   double         min_onoAboveLevel;  // ONO - level >= this (onoAboveLevelTooLow rule)
   double         min_onoBelowLevel;  // level - ONO >= this (onoBelowLevelTooLow rule)
   int            max_daystart_earlierWeek_contactAndProx_allowed;  // dayStartEarlierWeekContactTooHigh rule
   int            max_intraday_contactAndProx_today_allowed;        // dayContactTodayTooHigh rule
   double         max_dayLowSoFar_belowLevel_dist;  // dayLowSoFarNoMoreThanXBelowLevel rule
   double         min_gap_range_pts_exclusive;      // gapRangePtsAbove rule
   double         max_gap_fill_pc_exclusive;        // gapFillPcBelow rule
};

AlgoSharedProfile g_algoShared;
AlgoDef           g_algos[ALGO_FAMILY_REGISTRY_MAX];
int               g_algoCount = 0;

//--- Breakdown algo family (magic 200..299): M15 breakdown signal algos — no levels
#define BREAKDOWN_ALGO_REGISTRY_MAX           12
#define BREAKDOWN_ALGO_REGISTRY_MAX_HEADROOM    11  // reserve slots for planned 8+ algos before all are wired in breakdowncreator1
#define MAGIC_BREAKDOWN_FAMILY_SLOT_MIN        200
#define MAGIC_BREAKDOWN_FAMILY_SLOT_MAX        299

struct BreakdownAlgoSharedProfile
{
   int    tradeSizePct;
   string bannedRanges;
   string tradesDays;
   bool   babysit_enabled;
   bool   blockPlacementIfFamilyOpenOrPending;
   int    stop_trading_today_if_AllAlgos_losing_trades_count;
   int    stop_trading_today_if_AllAlgos_winning_trades_count;
   int    stop_trading_if_day_has_X_wins_0_losses;
   double stop_trading_if_day_has_profit_factor_above;
};

#define BREAKDOWN_GREENS_AFTER_BD_MAX            32
#define BREAKDOWN_STREAK_CONTINUATION_COUNT      5

enum ENUM_BREAKDOWN_STREAK_CONTINUATION
{  // algobookmark bdtype
   BREAKDOWN_STREAK_CONTINUATION_CLOSES = 0,    // each next M15 close < previous close
   BREAKDOWN_STREAK_CONTINUATION_OHLC_AVG = 1,  // (O+H+L+C)/4 strictly lower
   BREAKDOWN_STREAK_CONTINUATION_LOW = 2,       // low strictly lower
   BREAKDOWN_STREAK_CONTINUATION_OC_MID = 3,    // (open+close)/2 strictly lower
   BREAKDOWN_STREAK_CONTINUATION_HL_MID = 4     // (high+low)/2 strictly lower
};

struct BreakdownAlgoDef
{
   int            algo_id;
   bool           enabled;
   int            stop_trading_today_if_thisAlgo_losing_trades_count;
   int            stop_trading_today_if_thisAlgo_winning_trades_count;
   int            stop_trading_today_if_thisAlgo_total_trades_count;
   int            expiry_minutes;
   int            max_trades_per_breakdown_per_day;
   double         entryrange_range_percentspot;       // entry on low→firstGreen range: 50=midpoint, 33=lower retrace
   int            min_breakdown_sequence_len;
   int            max_breakdown_sequence_len;   // 0=no cap; red M15 streak length must be <= this
   ENUM_BREAKDOWN_STREAK_CONTINUATION breakdown_streak_continuation_mode;  // how streak extends after strong-red start
   double         bd_start_min_breakdown_percent;  // strong-red M15 start: (H-L)/L*100 must be >= this
   double         min_breakdown_total_percent;
   int            after_bd_need_x_15greenc;   // entry after Nth green M15 after breakdown end (1=first green)
   int            entry_max_minutes_after_bdend;
   int            forget_about_latest_breakdown_after_x_15m_candles;  // 0=never forget; gates stop reporting breakdownEndTooOld after endTime + N*15m
   bool           closetrade_after_some_time;
   bool           closetrade_after_some_time_butOnlyIfProfit;
   double         closetrade_after_some_time_but_ProfitPercent_Needed;  // min open P/L % vs lot×one_lot_equals_xPLN
   int            closetrade_after_x_minutes_from_breakdown;  // minutes after g_breakdown15mSnap.endTime; needs closetrade_after_some_time
   bool           sl_enabled;
   double         sl_points;
   bool           secret_tp_enabled;
   int            secret_tp_range_percent;
   double         secret_tp_greenguard_pricediff_at_least;  // after bid>=secretTp: skip if bid-entry < this (price); 0=off
   bool           tp_enabled;
   int            tp_notsecret_range_percent;  // % of (startHigh-breakdownLow) from low; 100=start, 120/150=above start
   int            max_open_positions;          // max simultaneous open positions + pending orders (carryover days OK)
   AlgoRuleEntry  rules[ALGO_RULES_MAX];
   int            rule_count;
};

BreakdownAlgoSharedProfile g_breakdownAlgoShared;
BreakdownAlgoDef           g_breakdownAlgos[BREAKDOWN_ALGO_REGISTRY_MAX];
int                        g_breakdownAlgoCount = 0;
int                        g_breakdownAlgoDayWins[BREAKDOWN_ALGO_REGISTRY_MAX];
int                        g_breakdownAlgoDayLosses[BREAKDOWN_ALGO_REGISTRY_MAX];
int                        g_breakdownFamilyDayWins = 0;
int                        g_breakdownFamilyDayLosses = 0;
double                     g_breakdownFamilyDayGrossProfit = 0.0;
double                     g_breakdownFamilyDayGrossLossAbs = 0.0;
datetime                   g_breakdownGatesLastLoggedBarTime[BREAKDOWN_ALGO_REGISTRY_MAX];
datetime                   g_breakdownGatesPerSecondLastLoggedTime[BREAKDOWN_ALGO_REGISTRY_MAX];
datetime                   g_breakdownGatesCloseTelBarTime[BREAKDOWN_ALGO_REGISTRY_MAX];
double                     g_breakdownGatesCloseTelMfePts[BREAKDOWN_ALGO_REGISTRY_MAX];
double                     g_breakdownGatesCloseTelMaePts[BREAKDOWN_ALGO_REGISTRY_MAX];
bool                       g_breakdownGatesCloseTelValid[BREAKDOWN_ALGO_REGISTRY_MAX];
int                        g_breakdownGatesPmFileHandle[BREAKDOWN_ALGO_REGISTRY_MAX];
int                        g_breakdownGatesPsFileHandle[BREAKDOWN_ALGO_REGISTRY_MAX];
datetime                   g_breakdownGatesLogFileDayStart = 0;
bool                       g_breakdownFamilyHadCloseThisPipelinePass = false;
int                        g_breakdownAlgoPlanTradeNumToday[BREAKDOWN_ALGO_REGISTRY_MAX];
int                        g_breakdownAlgoLevelTradeNumToday[BREAKDOWN_ALGO_REGISTRY_MAX];
int                        g_breakdownAlgoTradesAll[BREAKDOWN_ALGO_REGISTRY_MAX];
datetime                   g_breakdownAlgoLastPlacedEndTime[BREAKDOWN_ALGO_REGISTRY_MAX];
double                     g_breakdownAlgoLastPlacedStartHigh[BREAKDOWN_ALGO_REGISTRY_MAX];
double                     g_breakdownAlgoLastPlacedBreakdownLow[BREAKDOWN_ALGO_REGISTRY_MAX];

struct BreakdownAlgoBenchmarkAcc
{
   int    tradesClosed;
   int    wins;
   int    losses;
   double sumPriceDiff;
   double sumMfePts;
   double sumMaePts;
   int    telCount;
   double sumLifetimeHours;
};

BreakdownAlgoBenchmarkAcc g_breakdownAlgoBenchmarkAcc[BREAKDOWN_ALGO_REGISTRY_MAX];

#define BREAKDOWN_OPEN_LIFETIME_MAX 32
#define BREAKDOWN_PENDING_PLANNED_MAX 32

struct BreakdownOpenTradeLifetimeRec
{
   ulong    positionId;
   int      algoNumber;
   datetime startTime;
   datetime breakdownSequenceEndTime;
   double   plannedPrice;
   double   startPrice;
   double   realSLprice;
   double   realTPprice;
   string   pendingCloseReason;
   bool     active;
};

struct BreakdownPendingPlannedPriceRec
{
   long     magic;
   double   plannedPrice;
   bool     active;
};

BreakdownOpenTradeLifetimeRec  g_breakdownOpenLifetime[BREAKDOWN_OPEN_LIFETIME_MAX];
BreakdownPendingPlannedPriceRec g_breakdownPendingPlannedPrice[BREAKDOWN_PENDING_PLANNED_MAX];

// Base calendar overrides (YYYY.MM.DD): non-trade days block all placement; daily-only days restrict to daily/stacked levels.
string g_falgoNonTradeDates[];
string g_falgoDailyLevelsOnlyDates[];

#define ALGOFAMILY_BOUNCE_CEILING_EVENTS_MAX 64

//--- Per weekly level: running day state (updated every bar; log uses closest level's state at each bar)
struct WeeklyLevelAlgoFamilyDayState
{
   double   levelPrice;
   int      physicalContactCount_today;
   int      contactAndProximityCount_today;
   int      bounceCount_today;
   int      ceilingCount_today;
   int      ceilingProximityCandles_today;
   int      candlesPassedSinceLastBounce;
   int      candlesPassedSinceLastCeiling;
   datetime bounceEventTimes[ALGOFAMILY_BOUNCE_CEILING_EVENTS_MAX];
   int      bounceEventCount;
   datetime ceilingEventTimes[ALGOFAMILY_BOUNCE_CEILING_EVENTS_MAX];
   int      ceilingEventCount;
   datetime ceilingProximityCandleTimes[ALGOFAMILY_BOUNCE_CEILING_EVENTS_MAX];
   int      ceilingProximityCandleCount;
   bool     lastInBounceContact;
   bool     lastInCeilingContact;
   bool     contactFromAbove;
   bool     contactFromBelow;
   int    bounceCleanOhlcSinceContact;
   int    ceilingCleanOhlcSinceContact;
   double bounceHighestLowSinceContact;    // max low during bounce clean streak (closest low to level from above)
   double ceilingLowestHighSinceContact;   // min high during ceiling clean streak (closest high to level from below)
   bool     lastInPhysicalContact;
   bool     contactFromBelowPhysical;
   datetime cleanStreakStartTime;
   int      cleanStreakCount;
   double   cleanStreakOHLCSum;
   bool     cleanStreakIsAbove;
   double   anchorAbove;      // clean-above streak: max(high - level)
   datetime anchorAboveTime;
   double   anchorBelow;      // clean-below streak: max(level - low)
   datetime anchorBelowTime;
};
int g_weeklyAlgoFamilyTrackExpandedIdx[MAX_ALGOFAMILY_DAYSTART_WEEK_LEVELS];  // index into g_levelsExpanded
int g_weeklyAlgoFamilyTrackCount = 0;

//--- Incremental pullinghistory forward pass: persist state across M1 closes; live-safe mode adds forming-bar scratch pass + integrity full replay.
WeeklyLevelAlgoFamilyDayState g_pullingHistoryIncStates[MAX_ALGOFAMILY_DAYSTART_WEEK_LEVELS];
datetime g_pullingHistoryIncDayStart = 0;
int      g_pullingHistoryIncLastBarIdx = -1;
int      g_pullingHistoryIncTrackCountSnapshot = 0;
int      g_pullingHistoryIncTrackExpandedSnapshot[MAX_ALGOFAMILY_DAYSTART_WEEK_LEVELS];
datetime g_pullingHistoryIncSnapTime[MAX_BARS_IN_DAY];
double   g_pullingHistoryIncSnapOpen[MAX_BARS_IN_DAY];
double   g_pullingHistoryIncSnapHigh[MAX_BARS_IN_DAY];
double   g_pullingHistoryIncSnapLow[MAX_BARS_IN_DAY];
double   g_pullingHistoryIncSnapClose[MAX_BARS_IN_DAY];

//--- Incremental M1 bar-close @bar stats (session H/L, IB, gap, day progress, level trades); live-safe adds forming-bar slot refresh.
datetime g_m1BarCloseStatsIncDayStart = 0;
int      g_m1BarCloseStatsIncLastClosedBarIdx = -1;
bool     g_sessionHlIncFirstON = true;
bool     g_sessionHlIncFirstRTH = true;
double   g_sessionHlIncRunONhigh = 0.0;
double   g_sessionHlIncRunONlow = 0.0;
double   g_sessionHlIncRunRTHhigh = 0.0;
double   g_sessionHlIncRunRTHlow = 0.0;
double   g_sessionHlIncRunDayHigh = 0.0;
double   g_sessionHlIncRunDayLow = 0.0;
double   g_ibHlIncIbHigh = -1e300;
double   g_ibHlIncIbLow = 1e300;
bool     g_ibHlIncIbComplete = false;
int      g_gapAttemptIncRthOpenBarIdx = -1;
int      g_gapAttemptIncAttemptBarIdx = -1;
double   g_gapAttemptIncPrevFill = -1.0;
double   g_gapAttemptIncRunningMaxAway = 0.0;
double   g_gapAttemptIncFinalMaxAway = 0.0;
int      g_dayProgressIncP = 0;
int      g_dayProgressIncWins = 0;
int      g_dayProgressIncTotal = 0;
double   g_dayProgressIncDayPointsSum = 0.0;
double   g_dayProgressIncDayProfitSum = 0.0;
double   g_dayProgressIncDayGrossProfit = 0.0;
double   g_dayProgressIncDayGrossLoss = 0.0;
int      g_dayProgressIncONwins = 0;
int      g_dayProgressIncONtotal = 0;
double   g_dayProgressIncONpointsSum = 0.0;
double   g_dayProgressIncONprofitSum = 0.0;
int      g_dayProgressIncRTHwins = 0;
int      g_dayProgressIncRTHtotal = 0;
double   g_dayProgressIncRTHpointsSum = 0.0;
double   g_dayProgressIncRTHprofitSum = 0.0;
int      g_levelTradeStatsIncAppliedTradeCount = 0;
int      g_m1BarCloseStatsIncBarStart = 0;
int      g_m1BarCloseStatsIncBarEndInclusive = -1;
int      g_m1BarCloseStatsFormingBarIdx = -1;
bool     g_m1BarCloseStatsIncNeedFullRescan = false;
bool     g_m1BarCloseStatsIncRangeActive = false;
bool     g_m1BarCloseTerminalWasConnected = true;

struct AlgoFamilyLevelDayStatsAtBar
{
   int bounceCount_today;
   int ceilingCount_today;
   int ceilingProximityCandles_today;
   int physicalContactCount_today;
   int contactAndProximityCount_today;
   int candlesPassedSinceLastBounce;
   int candlesPassedSinceLastCeiling;
   int bounceCount_recent;
   int ceilingCount_recent;
   int ceilingProximityCandles_recent;
   double anchorAbove;
   double anchorBelow;
   int cleanStreakCount;
};
AlgoFamilyLevelDayStatsAtBar g_algoFamilyLevelStatsAtBar[MAX_ALGOFAMILY_DAYSTART_WEEK_LEVELS][MAX_BARS_IN_DAY];

//--- Gap-up mirror (RTH open > PD RTH close)
double   dayStat_openGapUp_percentageFill = 0.0;
int      dayStat_daysWithGapUp = 0;
int      dayStat_daysWithoutGapUp = 0;
double   dayStat_gapUp_fillPercentSum = 0.0;
double   dayStat_gapUp_rangeSum = 0.0;        // sum of gap range pts on gap-up days
int      dayStat_daysWithGapUp_10fill = 0;
int      dayStat_daysWithGapUp_20fill = 0;
int      dayStat_daysWithGapUp_25fill = 0;
int      dayStat_daysWithGapUp_30fill = 0;
int      dayStat_daysWithGapUp_33fill = 0;
int      dayStat_daysWithGapUp_40fill = 0;
int      dayStat_daysWithGapUp_50fill = 0;
int      dayStat_daysWithGapUp_60fill = 0;
int      dayStat_daysWithGapUp_75fill = 0;
int      dayStat_daysWithGapUp_90fill = 0;
int      dayStat_daysWithGapUp_100fill = 0;

//--- ON tested by RTH: counts for summary freq %
int      dayStat_daysONH_tested = 0;   // days when rthHigh >= ONH
int      dayStat_daysONL_tested = 0;   // days when rthLow <= ONL
int      dayStat_daysONboth_tested = 0; // days when both ONH and ONL tested same day

//--- Levels break check aggregate (all days, tertiary excluded): running sums for ON, RTHIB, RTHcnt; written at 22:00 to levels_breakCheck_breakingDown_tertiaryLevelsExcluded_summary.csv
double   g_agg_ONbreakDown_sumCandles = 0, g_agg_ONbreakDown_sumAvg = 0, g_agg_ONbreakDown_sumMed = 0;
int      g_agg_ONbreakDown_n = 0;
double   g_agg_ONbreakUp_sumCandles   = 0, g_agg_ONbreakUp_sumAvg   = 0, g_agg_ONbreakUp_sumMed   = 0;
int      g_agg_ONbreakUp_n   = 0;
double   g_agg_RTHbreakDown_sumCandles = 0, g_agg_RTHbreakDown_sumAvg = 0, g_agg_RTHbreakDown_sumMed = 0;
int      g_agg_RTHbreakDown_n = 0;
double   g_agg_RTHIBbreakDown_sumCandles = 0, g_agg_RTHIBbreakDown_sumAvg = 0, g_agg_RTHIBbreakDown_sumMed = 0;
int      g_agg_RTHIBbreakDown_n = 0;
double   g_agg_RTHcntbreakDown_sumCandles = 0, g_agg_RTHcntbreakDown_sumAvg = 0, g_agg_RTHcntbreakDown_sumMed = 0;
int      g_agg_RTHcntbreakDown_n = 0;
double   g_agg_RTHbreakUp_sumCandles   = 0, g_agg_RTHbreakUp_sumAvg   = 0, g_agg_RTHbreakUp_sumMed   = 0;
int      g_agg_RTHbreakUp_n   = 0;
datetime g_breakCheck_lastAggregatedDay = 0;  // only aggregate once per day
int      g_breakCheck_daysCount = 0;          // number of days with at least one non-tertiary level (for summary daysCount column)

//--- Optional double (hasValue false = no value; used for RTH/ON high-low so far and for "never" in diff window).
struct OptionalDouble { bool hasValue; double value; };

//--- ON session high/low so far at each bar k (bars 0..k with session=ON). Filled every OnTimer; log reads from here.
OptionalDouble g_ONhighSoFarAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_ONlowSoFarAtBar[MAX_BARS_IN_DAY];
//--- RTH session high/low so far at each bar k (bars 0..k with session=RTH). Filled every OnTimer; log reads from here.
OptionalDouble g_rthHighSoFarAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_rthLowSoFarAtBar[MAX_BARS_IN_DAY];
//--- Day high/low so far at each bar k (bars 0..k, whole day). Filled every OnTimer; log reads from here.
OptionalDouble g_dayHighSoFarAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_dayLowSoFarAtBar[MAX_BARS_IN_DAY];
//--- (dayHighSoFar + dayLowSoFar) / 2 at bar k; filled with day H/L in UpdateONandRTHHighLowSoFarAtBar.
OptionalDouble g_sessionRangeMidpointAtBar[MAX_BARS_IN_DAY];
//--- Day broke PDH/PDL so far at each bar: true if dayHighSoFar>PDH / dayLowSoFar<PDL (false when PDH/PDL unavailable).
bool g_dayBrokePDHAtBar[MAX_BARS_IN_DAY];
bool g_dayBrokePDLAtBar[MAX_BARS_IN_DAY];
//--- IB (first hour of RTH) high/low: unknown before IB ends; after 16:30 (normal) or 15:30 (desync) = max/min of IB bars. Filled every OnTimer.
OptionalDouble g_IBhighAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_IBlowAtBar[MAX_BARS_IN_DAY];
//--- Gap fill so far: unknown before RTH open; after = 0–100 % based on rthLowSoFar (gap up) or rthHighSoFar (gap down). Filled every OnTimer.
OptionalDouble g_gapFillSoFarAtBar[MAX_BARS_IN_DAY];
//--- Max price movement away from gap (pts) from RTH open through bar before first gap-fill attempt (fill % jump > gapFillAttempt_minIncreasePc).
OptionalDouble g_maxBeforeGapfillAttempt_over_5AtBar[MAX_BARS_IN_DAY];
//--- Trade results for the day
#define MAX_TRADE_RESULTS 7777
#define MAX_DEALS_DAY 7777
struct TradeResult
{
   string symbol;
   datetime sentTime;     // pending order ORDER_TIME_SETUP (placement)
   datetime startTime;    // entry fill (IN deal time)
   datetime endTime;      // 0 when entry out not found
   long magic;
   double priceStart;
   double priceEnd;       // 0 when entry out not found
   double priceDiff;
   double profit;         // from entry out; 0 when not found
   long type;             // DEAL_TYPE_BUY/SELL from entry in
   long reason;           // DEAL_REASON_* from entry out; undefined when not found
   double volume;
   string bothComments;
   string level;          // for now test: same as bothComments; later parsed from entry comment
   string tp;            // for now test: same as bothComments; later parsed from entry comment
   string sl;            // for now test: same as bothComments; later parsed from entry comment
   string sessionSent;    // ON|RTH-IB|RTH-afterIB|sleep from sentTime (GetSessionForTradeTime)
   bool foundOut;
};
TradeResult g_tradeResults[MAX_TRADE_RESULTS];
int g_tradeResultsCount = 0;
datetime g_tradeResultsEodFlushedForDayStart = 0;  // calendar day (00:00) for which EOD trade-results CSV flush already ran
// Temp deal buffers for UpdateTradeResultsForDay (sort by magic then time)
datetime g_dealTime[MAX_DEALS_DAY];
long g_dealMagic[MAX_DEALS_DAY];
int g_dealEntry[MAX_DEALS_DAY];
double g_dealPrice[MAX_DEALS_DAY];
double g_dealProfit[MAX_DEALS_DAY];
long g_dealType[MAX_DEALS_DAY];
long g_dealReason[MAX_DEALS_DAY];
double g_dealVolume[MAX_DEALS_DAY];
string g_dealSymbol[MAX_DEALS_DAY];
string g_dealComment[MAX_DEALS_DAY];
ulong g_dealTicket[MAX_DEALS_DAY];
int g_dealCount = 0;
int g_dealOrder[MAX_DEALS_DAY];     // sorted indices by magic, time
int g_dealOrderTmp[MAX_DEALS_DAY];  // merge sort buffer
#define MAX_IN_OUT_PER_MAGIC 1000
int g_inIdx[MAX_IN_OUT_PER_MAGIC];
int g_outIdx[MAX_IN_OUT_PER_MAGIC];

//--- Per-candle day progress (trades closed by candle close time; filled in UpdateDayProgress after UpdateTradeResultsForDay)
struct DayProgressBar
{
   double dayWinRate;   // wins/total for trades with endTime < candle close; 0 if no trades
   int dayTradesCount;  // count of trades with endTime < candle close
   double dayPointsSum;
   double dayProfitSum;
   double dayProfitFactor;  // grossProfit/grossLoss; 999 when no losses and grossProfit>0
   // Session-specific: trades whose endTime falls in ON vs RTH (ON stops at last ON candle, RTH starts at first RTH candle)
   double ONwinRate;
   int ONtradeCount;
   double ONpointsSum;
   double ONprofitSum;
   double RTHwinRate;
   int RTHtradeCount;
   double RTHpointsSum;
   double RTHprofitSum;
};
DayProgressBar g_dayProgress[MAX_BARS_IN_DAY];

//--- Static market context: previous trading day's PDO/PDH/PDL/PDC (pulled when we have at least one closed candle for current day; same for all bars of the day)
struct StaticMarketContext
{
   double PDOpreviousDayRTHOpen;   // open of previous day's 1m candle 15:30 (M1)
   double PDHpreviousDayHigh;   // highest High of previous trading day
   double PDLpreviousDayLow;    // lowest Low of previous trading day
   double PDCpreviousDayRTHClose;  // close of previous day's 1m candle 21:59 (M1) — that candle ends at 22:00
   string PDdate;               // previous trading day date YYYY.MM.DD (for debugging)
};
StaticMarketContext g_staticMarketContext;
datetime g_staticMarketContextPulledForDate = 0;  // day-start we last pulled for; 0 = never pulled
// Proximity (price distance): do not add PDrthClose or todayRTHopen if a level valid for that day is within this distance (only when flipper true)
const bool   tertiaryLevel_tooTight_featureFlipper = false;
const double tertiaryLevel_tooTight_toAdd_proximity = 2.0;
const double gapFillAttempt_minIncreasePc = 5.0;  // first fill attempt: rise > this vs 0/unknown or vs prior bar, only while prior fill <= this (6->12 is not a new attempt)

//+------------------------------------------------------------------+
//| Check if trading is allowed based on time restrictions            |
//+------------------------------------------------------------------+
bool IsTradingAllowed(datetime candleTime, int &bannedRanges[][4], int rangeCount)
{
   MqlDateTime mqlTime;
   TimeToStruct(candleTime, mqlTime);
   int hour = mqlTime.hour;
   int minute = mqlTime.min;
   
   // Convert to minutes since midnight for easier comparison
   int currentMinutes = hour * 60 + minute;
   
   // Check if current time falls within any banned range
   for(int rangeIdx = 0; rangeIdx < rangeCount; rangeIdx++)
   {
      int startHour = bannedRanges[rangeIdx][0];
      int startMinute = bannedRanges[rangeIdx][1];
      int endHour = bannedRanges[rangeIdx][2];
      int endMinute = bannedRanges[rangeIdx][3];
      
      int startMinutes = startHour * 60 + startMinute;
      int endMinutes = endHour * 60 + endMinute;
      
      if(currentMinutes >= startMinutes && currentMinutes <= endMinutes)
         return false; // Trading not allowed
   }
   
   return true; // Trading allowed
}

//+------------------------------------------------------------------+
//| Load calendar CSV from MQL5/Files. Format: date,dayofmonth,dayofweek,opex,qopex (header on first line). |
//+------------------------------------------------------------------+
bool LoadCalendar()
{
   g_calendarCount = 0;
   int fileHandle = FileOpen(InpCalendarFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandle == INVALID_HANDLE)
   {
      FatalError("Calendar file could not be opened: " + InpCalendarFile + " (place CSV in Terminal/Common/Files)");
      return false;
   }
   string line = FileReadString(fileHandle);  // skip header
   while(!FileIsEnding(fileHandle) && g_calendarCount < MAX_CALENDAR_ROWS)
   {
      line = FileReadString(fileHandle);
      if(StringLen(line) == 0) continue;
      string parts[];
      if(StringSplit(line, ',', parts) < 5) continue;
      g_calendar[g_calendarCount].dateStr    = parts[0];
      g_calendar[g_calendarCount].dayofmonth = (int)StringToInteger(parts[1]);
      g_calendar[g_calendarCount].dayofweek  = parts[2];
      g_calendar[g_calendarCount].opex       = (StringFind(parts[3], "True") == 0);
      g_calendar[g_calendarCount].qopex      = (StringFind(parts[4], "True") == 0);
      g_calendarCount++;
   }
   FileClose(fileHandle);
   return (g_calendarCount > 0);
}

//+------------------------------------------------------------------+
//| Return dayofweek string for the given date from loaded calendar, or "" if not found. |
//+------------------------------------------------------------------+
string GetCalendarDayOfWeek(datetime dt)
{
   string key = TimeToString(dt, TIME_DATE);  // YYYY.MM.DD to match calendar
   for(int calIdx = 0; calIdx < g_calendarCount; calIdx++)
      if(g_calendar[calIdx].dateStr == key) return g_calendar[calIdx].dayofweek;
   return "";
}

//+------------------------------------------------------------------+
//| Session for candle/bar time: ON / RTH / sleep (g_session, gates). Desync: RTH 14:30–20:59; else 15:30–22:00. |
//+------------------------------------------------------------------+
string GetSessionForCandleTime(datetime t)
{
   MqlDateTime mqlTime;
   TimeToStruct(t, mqlTime);
   int minOfDay = mqlTime.hour * 60 + mqlTime.min;
   string dateStr = TimeToString(t, TIME_DATE);
   if(bool_RTHsession_Is_DaylightSavingsDesync(dateStr))
   {
      if(minOfDay < 14*60+30) return "ON";   // before 14:30
      if(minOfDay <= 20*60+59) return "RTH"; // 14:30 to 20:59
      return "sleep";
   }
   else
   {
      if(minOfDay < 15*60+30) return "ON";   // before 15:30
      if(minOfDay <= 22*60+0) return "RTH";   // 15:30 to 22:00
      return "sleep";
   }
}

//+------------------------------------------------------------------+
//| Session at pending sent time (sessionSent) for summary_tradeResults_all_days: ON until RTH open; RTH-IB first RTH hour; RTH-afterIB until RTH end; sleep after. |
//| Boundaries match IsBarRTHIB / IsBarRTHcnt (desync via GetRthOpenBarOffsetSeconds). |
//+------------------------------------------------------------------+
string GetSessionForTradeTime(datetime t)
{
   datetime dayStart;
   string dateStr;
   GetDayStartAndDateStr(t, dayStart, dateStr);
   const datetime rthOpen = dayStart + GetRthOpenBarOffsetSeconds(dateStr);
   const datetime rthAfterIbStart = rthOpen + 3600 + 60;   // 15:31 desync, 16:31 normal
   const datetime rthEndExclusive = bool_RTHsession_Is_DaylightSavingsDesync(dateStr)
      ? dayStart + 21*3600
      : dayStart + 22*3600 + 60;
   if(t < rthOpen)
      return "ON";
   if(t < rthAfterIbStart)
      return "RTH-IB";
   if(t < rthEndExclusive)
      return "RTH-afterIB";
   return "sleep";
}

//+------------------------------------------------------------------+
//| True if t is in the EOD log window (eod_log_start..eod_log_end inclusive, server time). |
//| Uses TimeToStruct → broker/server clock (DST when the terminal/server adjusts). |
//| WARNING: A window too narrow or shifted late can miss ticks in the tester and skip EOD files. |
//+------------------------------------------------------------------+
bool IsInEODLogWindow(datetime t)
{
   MqlDateTime mql;
   TimeToStruct(t, mql);
   const int minuteOfDay = mql.hour * 60 + mql.min;
   const int startMin = eod_log_start_hour * 60 + eod_log_start_minute;
   const int endMin = eod_log_end_hour * 60 + eod_log_end_minute;
   if(startMin <= endMin)
      return (minuteOfDay >= startMin && minuteOfDay <= endMin);
   return (minuteOfDay >= startMin || minuteOfDay <= endMin);
}

//+------------------------------------------------------------------+
//| Set outDayStart = start of day (00:00) and outDateStr = YYYY.MM.DD for the given time. |
//+------------------------------------------------------------------+
void GetDayStartAndDateStr(datetime t, datetime &outDayStart, string &outDateStr)
{
   outDayStart = t - (t % 86400);
   outDateStr  = TimeToString(outDayStart, TIME_DATE);
}

//+------------------------------------------------------------------+
//| MFE/MAE from day M1: candles from 1 min after start to bar containing endTime. BUY: MFE=highest high, MAE=lowest low. SELL: MFE=lowest low, MAE=highest high. If range is 0 candles, use only the candle of end time. |
//| mfeCandle, maeCandle = 1-based index of the candle in that range that had the MFE/MAE price (0 if not found). |
//+------------------------------------------------------------------+
void GetMFEandMAEForTrade(const TradeResult &tradeResult, double &mfe, double &mae, int &mfeCandle, int &maeCandle)
{
   mfe = 0.0;
   mae = 0.0;
   mfeCandle = 0;
   maeCandle = 0;
   if(!tradeResult.foundOut || tradeResult.endTime == 0 || g_barsInDay <= 0) return;
   datetime startPlus1Min = tradeResult.startTime + 60;
   datetime firstBarTime  = startPlus1Min - (startPlus1Min % 60);  // bar open 1 min after start (e.g. 01:22:00)
   datetime lastBarTime   = tradeResult.endTime - (tradeResult.endTime % 60);  // bar open that contains endTime (e.g. 01:26:00)
   double highestHigh = 0.0, lowestLow = 0.0;
   int candleHighestHigh = 0, candleLowestLow = 0;
   int candleNum = 0;
   bool found = false;
   if(firstBarTime <= lastBarTime)
   {
      for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
      {
         datetime barTime = g_m1Rates[barIdx].time;
         if(barTime < firstBarTime) continue;
         if(barTime > lastBarTime) break;
         candleNum++;
         if(!found)
         {
            highestHigh = g_m1Rates[barIdx].high;
            lowestLow = g_m1Rates[barIdx].low;
            candleHighestHigh = candleNum;
            candleLowestLow = candleNum;
            found = true;
         }
         else
         {
            if(g_m1Rates[barIdx].high > highestHigh) { highestHigh = g_m1Rates[barIdx].high; candleHighestHigh = candleNum; }
            if(g_m1Rates[barIdx].low < lowestLow)    { lowestLow = g_m1Rates[barIdx].low;   candleLowestLow = candleNum; }
         }
      }
   }
   if(!found)
   {
      for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
         if(g_m1Rates[barIdx].time == lastBarTime)
         {
            highestHigh = g_m1Rates[barIdx].high;
            lowestLow   = g_m1Rates[barIdx].low;
            candleHighestHigh = 1;
            candleLowestLow   = 1;
            found = true;
            break;
         }
   }
   if(!found) return;
   if(tradeResult.type == (long)DEAL_TYPE_BUY)
   {
      mfe = highestHigh;
      mae = lowestLow;
      mfeCandle = candleHighestHigh;
      maeCandle = candleLowestLow;
   }
   else  // DEAL_TYPE_SELL
   {
      mfe = lowestLow;
      mae = highestHigh;
      mfeCandle = candleLowestLow;
      maeCandle = candleHighestHigh;
   }
}

//+------------------------------------------------------------------+
//| MFE_cN/MAE_cN from day M1: candles 1 to N from trade start (candle 1 = bar containing startTime). |
//| Only uses startTime; does not care whether trade was closed. Same units as MFEp/MAEp: points from fill price. |
//| BUY: MFE = highestHigh - priceStart, MAE = lowestLow - priceStart. SELL: MFE = priceStart - lowestLow, MAE = priceStart - highestHigh. |
//+------------------------------------------------------------------+
void GetMFEandMAE_cNForTrade(const TradeResult &tradeResult, int candleCount, double &mfe_out, double &mae_out)
{
   mfe_out = 0.0;
   mae_out = 0.0;
   if(g_barsInDay <= 0) return;
   datetime firstBarTime = tradeResult.startTime - (tradeResult.startTime % 60);
   datetime lastBarTime = firstBarTime + (candleCount - 1) * 60;  // candle N
   double highestHigh = 0.0, lowestLow = 0.0;
   bool found = false;
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      datetime barTime = g_m1Rates[barIdx].time;
      if(barTime < firstBarTime) continue;
      if(barTime > lastBarTime) break;
      if(!found)
      {
         highestHigh = g_m1Rates[barIdx].high;
         lowestLow = g_m1Rates[barIdx].low;
         found = true;
      }
      else
      {
         if(g_m1Rates[barIdx].high > highestHigh) highestHigh = g_m1Rates[barIdx].high;
         if(g_m1Rates[barIdx].low < lowestLow) lowestLow = g_m1Rates[barIdx].low;
      }
   }
   if(!found) return;
   if(tradeResult.type == (long)DEAL_TYPE_BUY)
   {
      mfe_out = highestHigh - tradeResult.priceStart;
      mae_out = lowestLow - tradeResult.priceStart;
   }
   else  // DEAL_TYPE_SELL
   {
      mfe_out = tradeResult.priceStart - lowestLow;
      mae_out = tradeResult.priceStart - highestHigh;
   }
}

//+------------------------------------------------------------------+
//| Calculate MFEp and MAEp (Maximum Favorable/Adverse Excursion) from MFE/MAE prices and priceStart. |
//| MFEp (long): highestHigh - priceStart. MFEp (short): priceStart - lowestLow. |
//| MAEp (long): lowestLow - priceStart. MAEp (short): priceStart - highestHigh. |
//+------------------------------------------------------------------+
void GetMFEpAndMAEpForTrade(const TradeResult &tradeResult, double mfe, double mae, double &mfep, double &maep)
{
   mfep = 0.0;
   maep = 0.0;
   if(mfe == 0.0 && mae == 0.0) return;  // no MFE/MAE data available
   if(tradeResult.type == (long)DEAL_TYPE_BUY)
   {
      // For long: MFEp = highestHigh - priceStart, MAEp = lowestLow - priceStart
      if(mfe > 0.0) mfep = mfe - tradeResult.priceStart;
      if(mae > 0.0) maep = mae - tradeResult.priceStart;
   }
   else  // DEAL_TYPE_SELL
   {
      // For short: MFEp = priceStart - lowestLow, MAEp = priceStart - highestHigh
      if(mae > 0.0) mfep = tradeResult.priceStart - mae;  // mae for sell is lowestLow
      if(mfe > 0.0) maep = tradeResult.priceStart - mfe;  // mfe for sell is highestHigh
   }
}

//+------------------------------------------------------------------+
//| TP/SL level price for "N" in PointSized points (same distance as pending TP/SL: PointSized(N)). BUY TP = priceStart+dist, SL = priceStart-dist; SELL opposite. |
//+------------------------------------------------------------------+
double GetLevelPriceForTPorSL(const TradeResult &tradeResult, int N, bool isTP)
{
   double dist = PointSized((double)N);
   if(tradeResult.type == (long)DEAL_TYPE_BUY)
      return isTP ? tradeResult.priceStart + dist : tradeResult.priceStart - dist;
   return isTP ? tradeResult.priceStart - dist : tradeResult.priceStart + dist;
}

//+------------------------------------------------------------------+
//| First candle (1-based, 1..30) from trade start where OHLC reached level. Candle 1 = bar containing startTime; range = 30 minutes. |
//| isTP: BUY = high>=level, SELL = low<=level. !isTP (SL): BUY = low<=level, SELL = high>=level. Returns 0 if never reached. |
//+------------------------------------------------------------------+
int GetCandleWhereLevelReached(const TradeResult &tradeResult, double levelPrice, bool isTP)
{
   if(g_barsInDay <= 0) return 0;
   datetime firstBarTime = tradeResult.startTime - (tradeResult.startTime % 60);
   datetime lastBarTime = firstBarTime + 29 * 60;  // 30 candles: 0..29 min after first bar
   bool isBuy = (tradeResult.type == (long)DEAL_TYPE_BUY);
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      datetime barTime = g_m1Rates[barIdx].time;
      if(barTime < firstBarTime) continue;
      if(barTime > lastBarTime) break;
      int candleNum = (int)((barTime - firstBarTime) / 60) + 1;  // 1-based
      double h = g_m1Rates[barIdx].high, l = g_m1Rates[barIdx].low;
      bool hit = false;
      if(isTP)
         hit = isBuy ? (h >= levelPrice) : (l <= levelPrice);
      else
         hit = isBuy ? (l <= levelPrice) : (h >= levelPrice);
      if(hit) return candleNum;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| 3c_30c_level_breakevenC: first N (3..30) such that avg(OHLC over candles 1..N) is above level+3 (BUY) or below level-3 (SELL). |
//| Candles 1..30 from trade start. Returns 0 if no level, or no such N in 3..30. |
//+------------------------------------------------------------------+
int Get3c30cLevelBreakevenCForTrade(const TradeResult &tradeResult)
{
   if(StringLen(tradeResult.level) == 0 || g_barsInDay <= 0) return 0;
   double levelVal = StringToDouble(tradeResult.level);
   const double LEVEL_OFFSET_POINTS = 3.0;
   double threshold = (tradeResult.type == (long)DEAL_TYPE_BUY) ? (levelVal + LEVEL_OFFSET_POINTS) : (levelVal - LEVEL_OFFSET_POINTS);
   datetime firstBarTime = tradeResult.startTime - (tradeResult.startTime % 60);
   datetime lastBarTime = firstBarTime + 29 * 60;
   double ohlc[30][4];  // [candle 0..29][O,H,L,C]
   int numBars = 0;
   for(int barIdx = 0; barIdx < g_barsInDay && numBars < 30; barIdx++)
   {
      datetime barTime = g_m1Rates[barIdx].time;
      if(barTime < firstBarTime) continue;
      if(barTime > lastBarTime) break;
      ohlc[numBars][0] = g_m1Rates[barIdx].open;
      ohlc[numBars][1] = g_m1Rates[barIdx].high;
      ohlc[numBars][2] = g_m1Rates[barIdx].low;
      ohlc[numBars][3] = g_m1Rates[barIdx].close;
      numBars++;
   }
   for(int N = 3; N <= 30 && N <= numBars; N++)
   {
      double sum = 0.0;
      for(int i = 0; i < N; i++)
         sum += ohlc[i][0] + ohlc[i][1] + ohlc[i][2] + ohlc[i][3];
      double avg = sum / (4.0 * (double)N);
      if(tradeResult.type == (long)DEAL_TYPE_BUY) { if(avg > threshold) return N; }
      else { if(avg < threshold) return N; }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| priceBreakLevel_c1c2: candle containing trade start (c1) + next candle (c2). BUY: level - low (min over 2). SELL: level - high (max over 2). Returns "NOT_FOUND" if no level or bars missing. |
//+------------------------------------------------------------------+
string GetPriceBreakLevel_c1c2_ForTrade(const TradeResult &tradeResult)
{
   if(StringLen(tradeResult.level) == 0 || g_barsInDay <= 0) return "NOT_FOUND";
   double levelVal = StringToDouble(tradeResult.level);
   datetime currBarTime = tradeResult.startTime - (tradeResult.startTime % 60);  // candle containing trade (e.g. 14:31)
   datetime nextBarTime = currBarTime + 60;                                       // 1 candle after (e.g. 14:32)
   double v1 = 0.0, v2 = 0.0;
   bool has1 = false, has2 = false;
   for(int i = 0; i < g_barsInDay; i++)
   {
      if(g_m1Rates[i].time == currBarTime)
         { v1 = (tradeResult.type == (long)DEAL_TYPE_BUY) ? g_m1Rates[i].low : g_m1Rates[i].high; has1 = true; }
      if(g_m1Rates[i].time == nextBarTime)
         { v2 = (tradeResult.type == (long)DEAL_TYPE_BUY) ? g_m1Rates[i].low : g_m1Rates[i].high; has2 = true; }
   }
   if(!has1 && !has2) return "NOT_FOUND";
   double cp;
   if(tradeResult.type == (long)DEAL_TYPE_BUY)
   {
      if(has1 && has2) cp = MathMin(levelVal - v1, levelVal - v2);
      else cp = has1 ? (levelVal - v1) : (levelVal - v2);
   }
   else  // DEAL_TYPE_SELL
   {
      if(has1 && has2) cp = MathMax(levelVal - v1, levelVal - v2);
      else cp = has1 ? (levelVal - v1) : (levelVal - v2);
   }
   return DoubleToString(cp, _Digits);
}

//+------------------------------------------------------------------+
//| Returns "yes" if openPrice > level, "no" otherwise; "unknown" if not yet known. |
//+------------------------------------------------------------------+
string GetOpenWasAboveLevelString(double openPrice, double level, bool known)
{
   if(!known) return "unknown";
   return (openPrice > level) ? "yes" : "no";
}

//+------------------------------------------------------------------+
//| Gap fill % at trade open time. Delegates to GetGapFillSoFarAtBar. Returns "unknown" before RTH open. |
//+------------------------------------------------------------------+
string GetGapFillPcAtTradeOpenTime(datetime tradeOpenTime)
{
   datetime barOpenTime = tradeOpenTime - (tradeOpenTime % 60);
   int barIdx = -1;
   for(int i = 0; i < g_barsInDay; i++)
      if(g_m1Rates[i].time == barOpenTime) { barIdx = i; break; }
   double val = 0.0;
   datetime dayStart = g_m1DayStart;
   string dateStr = TimeToString(dayStart, TIME_DATE);
   if(!GetGapFillSoFarAtBar(barIdx, dayStart, dateStr, val)) return "unknown";
   return DoubleToString(val, 2);
}

//+------------------------------------------------------------------+
//| Gap day type at trade open time. Returns "gapUp_Day" if PDC < RTHopen, "gapDown_Day" if PDC > RTHopen, "unknown" if trade before RTH open or data unavailable. |
//+------------------------------------------------------------------+
string GetIsGapDownDayString(datetime tradeOpenTime)
{
   datetime dayStart = g_m1DayStart;
   string dateStr = TimeToString(dayStart, TIME_DATE);
   datetime rthOpenBarTime = dayStart + GetRthOpenBarOffsetSeconds(dateStr);
   if(tradeOpenTime < rthOpenBarTime) return "unknown";
   if(!g_todayRTHopenValid || g_staticMarketContext.PDCpreviousDayRTHClose <= 0.0) return "unknown";
   double rthOpen = g_todayRTHopen;
   double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
   if(rthOpen > pdc) return "gapUp_Day";
   if(rthOpen < pdc) return "gapDown_Day";
   return "unknown";
}

//+------------------------------------------------------------------+
int TradeResultMovingLookbackBarIdx(const datetime tradeOpenTime)
{
   const int lookbackSec = (tradeResult_referencePoints_movingLookback_seconds > 0) ?
      tradeResult_referencePoints_movingLookback_seconds : 0;
   const datetime movingRefTime = tradeOpenTime - lookbackSec;
   const datetime movingBarOpenTime = movingRefTime - (movingRefTime % 60);
   for(int i = 0; i < g_barsInDay; i++)
      if(g_m1Rates[i].time == movingBarOpenTime)
         return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Day broke PDH at trade-result context bar (startTime - moving lookback). |
//+------------------------------------------------------------------+
string GetDayBrokePDHAtTradeOpenTime(datetime tradeOpenTime)
{
   const int barIdx = TradeResultMovingLookbackBarIdx(tradeOpenTime);
   if(barIdx < 0) return "unknown";
   return g_dayBrokePDHAtBar[barIdx] ? "true" : "false";
}

//+------------------------------------------------------------------+
//| Day broke PDL at trade-result context bar (startTime - moving lookback). |
//+------------------------------------------------------------------+
string GetDayBrokePDLAtTradeOpenTime(datetime tradeOpenTime)
{
   const int barIdx = TradeResultMovingLookbackBarIdx(tradeOpenTime);
   if(barIdx < 0) return "unknown";
   return g_dayBrokePDLAtBar[barIdx] ? "true" : "false";
}

//+------------------------------------------------------------------+
//| Prior day trend from PDO vs PDC. Returns "PD_green" (PDC>PDO), "PD_red" (PDC<PDO), "unknown" if data unavailable. |
//+------------------------------------------------------------------+
string GetPDtrendString()
{
   double pdo = g_staticMarketContext.PDOpreviousDayRTHOpen;
   double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
   if(pdo <= 0.0 || pdc <= 0.0) return "unknown";
   if(pdc > pdo) return "PD_green";
   if(pdc < pdo) return "PD_red";
   return "unknown";
}

//+------------------------------------------------------------------+
//| Gate_PD_green: prior-day trend is PD_green (PDC > PDO). False if unknown or PD_red. |
//+------------------------------------------------------------------+
bool Gate_PD_green()
{
   return (GetPDtrendString() == "PD_green");
}

//+------------------------------------------------------------------+
//| Gate_PD_red: prior-day trend is PD_red (PDC < PDO). False if unknown or PD_green. |
//+------------------------------------------------------------------+
bool Gate_PD_red()
{
   return (GetPDtrendString() == "PD_red");
}

//+------------------------------------------------------------------+
//| Resolve RTH open for gap stats: (1) exact 15:30/14:30 bar (2) else latest M1 that day with time < target. Otherwise false (caller FatalError). |
//| No session lookup needed here; g_m1Rates[0..g_barsInDay) is already that calendar day's slice. |
//+------------------------------------------------------------------+
bool TryResolveRTHopenPriceForDay(const string &dateStr, double &outOpen)
{
   outOpen = 0.0;
   if(g_barsInDay <= 0 || g_m1DayStart == 0) return false;
   datetime targetTime;
   if(bool_RTHsession_Is_DaylightSavingsDesync(dateStr))
      targetTime = g_m1DayStart + 14*3600 + 30*60;
   else
      targetTime = g_m1DayStart + 15*3600 + 30*60;
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
      if(g_m1Rates[barIdx].time == targetTime)
      {
         outOpen = g_m1Rates[barIdx].open;
         return true;
      }
   int bestIdx = -1;
   datetime bestT = 0;
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      datetime t = g_m1Rates[barIdx].time;
      if(t < targetTime && (bestIdx < 0 || t > bestT))
      {
         bestT = t;
         bestIdx = barIdx;
      }
   }
   if(bestIdx >= 0)
   {
      outOpen = g_m1Rates[bestIdx].open;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| RTH open for day-stat / gap logic. Short sessions: latest M1 before nominal open; else FatalError. |
//+------------------------------------------------------------------+
double GetRTHopenCurrentDay()
{
   if(g_barsInDay <= 0 || g_m1DayStart == 0)
      FatalError("GetRTHopenCurrentDay: no day data (g_barsInDay=" + IntegerToString(g_barsInDay) + " g_m1DayStart=0)");
   string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   double o;
   if(!TryResolveRTHopenPriceForDay(dateStr, o))
      FatalError("GetRTHopenCurrentDay: no exact nominal RTH open bar and no M1 with time before it for " + dateStr);
   return o;
}

//+------------------------------------------------------------------+
//| Safe getter for today's RTH open. Returns true and sets outRthOpen only when g_todayRTHopenValid; otherwise false (do not use outRthOpen). |
//+------------------------------------------------------------------+
bool GetTodayRTHopenIfValid(double &outRthOpen)
{
   if(!g_todayRTHopenValid) return false;
   outRthOpen = g_todayRTHopen;
   return true;
}

//+------------------------------------------------------------------+
//| Safe getter for rthHighSoFar at bar. Returns true only when bar is at/after RTH open and value known; then sets outVal. Otherwise false (do not use outVal). |
//+------------------------------------------------------------------+
bool GetRthHighSoFarAtBar(int barIdx, datetime dayStart, const string &dateStr, double &outVal)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   datetime rthOpenBarTime = dayStart + GetRthOpenBarOffsetSeconds(dateStr);
   if(g_m1Rates[barIdx].time < rthOpenBarTime) return false;
   if(!g_rthHighSoFarAtBar[barIdx].hasValue) return false;
   outVal = g_rthHighSoFarAtBar[barIdx].value;
   return true;
}

//+------------------------------------------------------------------+
//| Safe getter for rthLowSoFar at bar. Returns true only when bar is at/after RTH open and value known; then sets outVal. Otherwise false (do not use outVal). |
//+------------------------------------------------------------------+
bool GetRthLowSoFarAtBar(int barIdx, datetime dayStart, const string &dateStr, double &outVal)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   datetime rthOpenBarTime = dayStart + GetRthOpenBarOffsetSeconds(dateStr);
   if(g_m1Rates[barIdx].time < rthOpenBarTime) return false;
   if(!g_rthLowSoFarAtBar[barIdx].hasValue) return false;
   outVal = g_rthLowSoFarAtBar[barIdx].value;
   return true;
}

//+------------------------------------------------------------------+
//| Safe getter for RTHopen for a given bar. Returns true only when bar is at/after RTH open and g_todayRTHopenValid; then sets outVal. Otherwise false (do not use outVal). |
//+------------------------------------------------------------------+
bool GetRTHopenForBar(int barIdx, datetime dayStart, const string &dateStr, double &outVal)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   if(!g_todayRTHopenValid) return false;
   datetime rthOpenBarTime = dayStart + GetRthOpenBarOffsetSeconds(dateStr);
   if(g_m1Rates[barIdx].time < rthOpenBarTime) return false;
   outVal = g_todayRTHopen;
   return true;
}

//+------------------------------------------------------------------+
//| Safe getter for IBhigh at bar. Returns true only when IB complete and value known; then sets outVal. Otherwise false (do not use outVal). |
//+------------------------------------------------------------------+
bool GetIBhighAtBar(int barIdx, double &outVal)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   if(!g_IBhighAtBar[barIdx].hasValue) return false;
   outVal = g_IBhighAtBar[barIdx].value;
   return true;
}

//+------------------------------------------------------------------+
//| Safe getter for IBlow at bar. Returns true only when IB complete and value known; then sets outVal. Otherwise false (do not use outVal). |
//+------------------------------------------------------------------+
bool GetIBlowAtBar(int barIdx, double &outVal)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   if(!g_IBlowAtBar[barIdx].hasValue) return false;
   outVal = g_IBlowAtBar[barIdx].value;
   return true;
}

//+------------------------------------------------------------------+
//| Safe getter for ON session high so far at bar. False before any ON bar in the day (do not use outVal). |
//+------------------------------------------------------------------+
bool GetONhighSoFarAtBar(int barIdx, double &outVal)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   if(!g_ONhighSoFarAtBar[barIdx].hasValue) return false;
   outVal = g_ONhighSoFarAtBar[barIdx].value;
   return true;
}

//+------------------------------------------------------------------+
//| Safe getter for ON session low so far at bar. False before any ON bar in the day (do not use outVal). |
//+------------------------------------------------------------------+
bool GetONlowSoFarAtBar(int barIdx, double &outVal)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   if(!g_ONlowSoFarAtBar[barIdx].hasValue) return false;
   outVal = g_ONlowSoFarAtBar[barIdx].value;
   return true;
}

//+------------------------------------------------------------------+
//| Safe getter for gapFillSoFar at bar. Returns true only when bar is at/after RTH open and value known; then sets outVal (0–100). Otherwise false (do not use outVal). |
//+------------------------------------------------------------------+
bool GetGapFillSoFarAtBar(int barIdx, datetime dayStart, const string &dateStr, double &outVal)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   datetime rthOpenBarTime = dayStart + GetRthOpenBarOffsetSeconds(dateStr);
   if(g_m1Rates[barIdx].time < rthOpenBarTime) return false;
   if(!g_gapFillSoFarAtBar[barIdx].hasValue) return false;
   outVal = g_gapFillSoFarAtBar[barIdx].value;
   return true;
}

//+------------------------------------------------------------------+
//| Reference points above/below level at trade open. PDO/PDH/PDL/PDC: static. ONH/ONL/RTH/IB/day H-L/midpoint: M1 bar at (startTime - tradeResult_referencePoints_movingLookback_seconds). Skips unknown refs. Tie at level → above. |
//+------------------------------------------------------------------+
void GetReferencePointsAboveBelow(datetime tradeOpenTime, double levelPrice, string &outAbove, string &outBelow)
{
   outAbove = "";
   outBelow = "";
   const int movingBarIdx = TradeResultMovingLookbackBarIdx(tradeOpenTime);
   datetime dayStart = g_m1DayStart;
   string dateStr = TimeToString(dayStart, TIME_DATE);

   const bool rp_excludeTooClose = bigflipper_tradeResult_referencePoints_excludeTooClose;
   const double rp_minAbs = tradeResult_referencePointMinAbsDiffFromLevel;
   double v = 0.0;
   if(g_staticMarketContext.PDOpreviousDayRTHOpen > 0.0) { v = g_staticMarketContext.PDOpreviousDayRTHOpen; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "PDO"; else outBelow += (outBelow != "" ? ";" : "") + "PDO"; } }
   if(g_staticMarketContext.PDHpreviousDayHigh > 0.0) { v = g_staticMarketContext.PDHpreviousDayHigh; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "PDH"; else outBelow += (outBelow != "" ? ";" : "") + "PDH"; } }
   if(g_staticMarketContext.PDLpreviousDayLow > 0.0) { v = g_staticMarketContext.PDLpreviousDayLow; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "PDL"; else outBelow += (outBelow != "" ? ";" : "") + "PDL"; } }
   if(g_staticMarketContext.PDCpreviousDayRTHClose > 0.0) { v = g_staticMarketContext.PDCpreviousDayRTHClose; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "PDC"; else outBelow += (outBelow != "" ? ";" : "") + "PDC"; } }
   if(movingBarIdx < 0)
      return;
   if(g_ONhighSoFarAtBar[movingBarIdx].hasValue) { v = g_ONhighSoFarAtBar[movingBarIdx].value; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "ONH"; else outBelow += (outBelow != "" ? ";" : "") + "ONH"; } }
   if(g_ONlowSoFarAtBar[movingBarIdx].hasValue) { v = g_ONlowSoFarAtBar[movingBarIdx].value; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "ONL"; else outBelow += (outBelow != "" ? ";" : "") + "ONL"; } }
   if(GetRthHighSoFarAtBar(movingBarIdx, dayStart, dateStr, v)) { if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "RTHH"; else outBelow += (outAbove != "" ? ";" : "") + "RTHH"; } }
   if(GetRthLowSoFarAtBar(movingBarIdx, dayStart, dateStr, v)) { if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "RTHL"; else outBelow += (outBelow != "" ? ";" : "") + "RTHL"; } }
   if(GetIBlowAtBar(movingBarIdx, v)) { if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "IBL"; else outBelow += (outBelow != "" ? ";" : "") + "IBL"; } }
   if(GetIBhighAtBar(movingBarIdx, v)) { if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "IBH"; else outBelow += (outBelow != "" ? ";" : "") + "IBH"; } }
   if(g_dayHighSoFarAtBar[movingBarIdx].hasValue) { v = g_dayHighSoFarAtBar[movingBarIdx].value; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "dayHighSoFar"; else outBelow += (outBelow != "" ? ";" : "") + "dayHighSoFar"; } }
   if(g_dayLowSoFarAtBar[movingBarIdx].hasValue) { v = g_dayLowSoFarAtBar[movingBarIdx].value; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "dayLowSoFar"; else outBelow += (outBelow != "" ? ";" : "") + "dayLowSoFar"; } }
   if(g_sessionRangeMidpointAtBar[movingBarIdx].hasValue) { v = g_sessionRangeMidpointAtBar[movingBarIdx].value; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "midpoint"; else outBelow += (outBelow != "" ? ";" : "") + "midpoint"; } }
}

//+------------------------------------------------------------------+
//| Find today's RTH open bar in g_m1Rates (14:30 on desync dates, else 15:30) and assign g_todayRTHopen, g_todayRTHopenValid. |
//+------------------------------------------------------------------+
void AssignTodayRTHopenFromM1Rates(const string &dateStr)
{
   g_todayRTHopenValid = false;
   if(g_barsInDay <= 0) return;
   double o;
   if(!TryResolveRTHopenPriceForDay(dateStr, o))
      FatalError("AssignTodayRTHopenFromM1Rates: no exact nominal RTH open bar and no M1 with time before it for " + dateStr);
   g_todayRTHopen = o;
   g_todayRTHopenValid = true;
}

//+------------------------------------------------------------------+
double FalgoTodayRthOpenPriceMatchTolerance()
{
   return MathMax(Instrument_PointStepSize(), 1e-6);
}

//+------------------------------------------------------------------+
//| Keep legacy levels[] row in sync when todayRTHopen exists in g_levels. |
//+------------------------------------------------------------------+
void SyncTodayRthOpenInLevelsArray(const string &todayStr)
{
   const string wantBase = todayStr + "_todayRTHopen";
   for(int i = 0; i < ArraySize(levels); i++)
   {
      if(levels[i].baseName != wantBase)
         continue;
      levels[i].price   = g_todayRTHopen;
      levels[i].tagsCSV = "daily_tertiary_todayRTHopen";
      return;
   }
}

//+------------------------------------------------------------------+
//| Ensure today's RTH-open tertiary level exists; price/categories always follow M1 RTH open. |
//+------------------------------------------------------------------+
void TryAddTodayRTHopenLevel(const string &dateStr)
{
   if(!g_todayRTHopenValid) return;
   const string todayStr = dateStr;
   const string categories = "daily_tertiary_todayRTHopen";
   int existingIdx = -1;
   for(int levelIdx = 0; levelIdx < g_levelsTotalCount; levelIdx++)
   {
      if(g_levels[levelIdx].tag != "todayRTHopen" || g_levels[levelIdx].startStr != todayStr || g_levels[levelIdx].endStr != todayStr)
         continue;
      existingIdx = levelIdx;
      break;
   }
   if(existingIdx >= 0)
   {
      g_levels[existingIdx].levelPrice = g_todayRTHopen;
      g_levels[existingIdx].categories = categories;
      SyncTodayRthOpenInLevelsArray(todayStr);
      return;
   }
   if(tertiaryLevel_tooTight_featureFlipper)
   {
      for(int levelIdx = 0; levelIdx < g_levelsTotalCount; levelIdx++)
         if(g_levels[levelIdx].startStr <= todayStr && todayStr <= g_levels[levelIdx].endStr &&
            MathAbs(g_levels[levelIdx].levelPrice - g_todayRTHopen) < tertiaryLevel_tooTight_toAdd_proximity)
            return;
   }
   if(g_levelsTotalCount >= MAX_LEVEL_ROWS)
      FatalError("todayRTHopen: RTH open bar found but g_levels full (g_levelsTotalCount=" + IntegerToString(g_levelsTotalCount) + ")");
   AddLevel(todayStr + "_todayRTHopen", g_todayRTHopen, todayStr + " 00:00", todayStr + " 23:59", categories);
   g_levels[g_levelsTotalCount].startStr   = todayStr;
   g_levels[g_levelsTotalCount].endStr     = todayStr;
   g_levels[g_levelsTotalCount].levelPrice = g_todayRTHopen;
   g_levels[g_levelsTotalCount].categories = categories;
   g_levels[g_levelsTotalCount].tag        = "todayRTHopen";
   g_levelsTotalCount++;
}

//+------------------------------------------------------------------+
//| If static PDC is available, add PDrthClose tertiary level once per day (same dedup as todayRTHopen). |
//+------------------------------------------------------------------+
void TryAddPDrthCloseLevel(const string &dateStr)
{
   if(g_staticMarketContextPulledForDate != g_m1DayStart || g_staticMarketContext.PDCpreviousDayRTHClose <= 0.0)
      return;
   const string todayStr = dateStr;
   const double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
   for(int levelIdx = 0; levelIdx < g_levelsTotalCount; levelIdx++)
      if(g_levels[levelIdx].tag == "PDrthClose" && g_levels[levelIdx].startStr == todayStr && g_levels[levelIdx].endStr == todayStr)
         return;
   if(tertiaryLevel_tooTight_featureFlipper)
   {
      for(int levelIdx = 0; levelIdx < g_levelsTotalCount; levelIdx++)
      {
         if(g_levels[levelIdx].startStr > todayStr || todayStr > g_levels[levelIdx].endStr) continue;
         if(MathAbs(g_levels[levelIdx].levelPrice - pdc) < tertiaryLevel_tooTight_toAdd_proximity)
            return;
      }
   }
   if(g_levelsTotalCount >= MAX_LEVEL_ROWS)
      FatalError("PDrthClose: static PDC available but g_levels full (g_levelsTotalCount=" + IntegerToString(g_levelsTotalCount) + ")");
   const string categories = "daily_tertiary_PDrthClose";
   AddLevel(todayStr + "_PDrthClose", pdc, todayStr + " 00:00", todayStr + " 23:59", categories);
   g_levels[g_levelsTotalCount].startStr   = todayStr;
   g_levels[g_levelsTotalCount].endStr     = todayStr;
   g_levels[g_levelsTotalCount].levelPrice = pdc;
   g_levels[g_levelsTotalCount].categories = categories;
   g_levels[g_levelsTotalCount].tag        = "PDrthClose";
   g_levelsTotalCount++;
}

//+------------------------------------------------------------------+
//| True if bar time (open time) is in RTHIB window: first hour of RTH (14:30–15:30 on desync, else 15:30–16:30). |
//+------------------------------------------------------------------+
bool IsBarRTHIB(datetime barTime)
{
   MqlDateTime mqlTime;
   TimeToStruct(barTime, mqlTime);
   int minOfDay = mqlTime.hour * 60 + mqlTime.min;
   string dateStr = TimeToString(barTime, TIME_DATE);
   if(bool_RTHsession_Is_DaylightSavingsDesync(dateStr))
      return (minOfDay >= 14*60+30 && minOfDay <= 15*60+30);
   return (minOfDay >= 15*60+30 && minOfDay <= 16*60+30);
}

//+------------------------------------------------------------------+
//| True if bar time (open time) is in RTHcnt window: after RTHIB (15:31+ on desync, else 16:31+). |
//+------------------------------------------------------------------+
bool IsBarRTHcnt(datetime barTime)
{
   MqlDateTime mqlTime;
   TimeToStruct(barTime, mqlTime);
   int minOfDay = mqlTime.hour * 60 + mqlTime.min;
   string dateStr = TimeToString(barTime, TIME_DATE);
   if(bool_RTHsession_Is_DaylightSavingsDesync(dateStr))
      return (minOfDay >= 15*60+31);
   return (minOfDay >= 16*60+31);
}

//+------------------------------------------------------------------+
//| Median of first elemCount elements of arr[]. Resizes arr to elemCount and sorts in place. Returns 0 if elemCount<=0. |
//+------------------------------------------------------------------+
double GetMedianDoubleArray(double &arr[], int elemCount)
{
   if(elemCount <= 0) return 0.0;
   ArrayResize(arr, elemCount);
   ArraySort(arr);
   if(elemCount % 2 == 1) return arr[elemCount/2];
   return (arr[elemCount/2 - 1] + arr[elemCount/2]) / 2.0;
}

//+------------------------------------------------------------------+
//| Session type for break-down stats (first close above level, then distances). |
//+------------------------------------------------------------------+
enum BREAKCHECK_SESSION { BREAKCHECK_ON, BREAKCHECK_RTHIB, BREAKCHECK_RTHCNT };

struct BreakCheckSessionResult
{
   int    firstCloseAbove;
   int    count;
   double avg;
   double median;
   string rangeStartStr;
};

//+------------------------------------------------------------------+
//| True if bar index k is in the given break-check session. |
//+------------------------------------------------------------------+
bool BarInSession(int k, BREAKCHECK_SESSION sessionType)
{
   switch(sessionType)
   {
      case BREAKCHECK_ON:     return (g_session[k] == "ON");
      case BREAKCHECK_RTHIB:  return IsBarRTHIB(g_m1Rates[k].time);
      case BREAKCHECK_RTHCNT: return IsBarRTHcnt(g_m1Rates[k].time);
      default: return false;
   }
}

//+------------------------------------------------------------------+
//| First close above level in session, then collect break-down distances (low < level, d <= maxDist); return n, avg, median, rangeStartStr. |
//+------------------------------------------------------------------+
BreakCheckSessionResult BreakCheckSessionStats(double lvl, double maxDist, BREAKCHECK_SESSION sessionType)
{
   BreakCheckSessionResult sessionResult;
   sessionResult.firstCloseAbove = g_barsInDay;
   sessionResult.count = 0;
   sessionResult.avg = 0.0;
   sessionResult.median = 0.0;
   sessionResult.rangeStartStr = "";

   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      if(!BarInSession(barIdx, sessionType)) continue;
      if(g_m1Rates[barIdx].close > lvl) { sessionResult.firstCloseAbove = barIdx; break; }
   }

   double values[];
   ArrayResize(values, g_barsInDay);
   double sum = 0.0;
   for(int barIdx = sessionResult.firstCloseAbove; barIdx < g_barsInDay; barIdx++)
   {
      if(!BarInSession(barIdx, sessionType)) continue;
      if(g_m1Rates[barIdx].low >= lvl) continue;
      double dist = lvl - g_m1Rates[barIdx].low;
      if(dist > maxDist) break;
      if(dist <= maxDist) { values[sessionResult.count++] = dist; sum += dist; }
   }
   sessionResult.avg    = (sessionResult.count > 0) ? sum / (double)sessionResult.count : 0.0;
   sessionResult.median = GetMedianDoubleArray(values, sessionResult.count);
   sessionResult.rangeStartStr = (sessionResult.firstCloseAbove < g_barsInDay) ? TimeToString(g_m1Rates[sessionResult.firstCloseAbove].time, TIME_DATE|TIME_MINUTES) : "";

   return sessionResult;
}

//+------------------------------------------------------------------+
//| Session high/low over g_barsInDay for bars where g_session[k] == sessionName. Sets outHigh/outLow (undefined if !hasAny). |
//+------------------------------------------------------------------+
void GetSessionHighLow(const string sessionName, double &outHigh, double &outLow, bool &hasAny)
{
   outHigh = -1e300;
   outLow  = 1e300;
   hasAny  = false;
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      if(g_session[barIdx] != sessionName) continue;
      hasAny = true;
      if(g_m1Rates[barIdx].high > outHigh) outHigh = g_m1Rates[barIdx].high;
      if(g_m1Rates[barIdx].low  < outLow)  outLow  = g_m1Rates[barIdx].low;
   }
}

//+------------------------------------------------------------------+
//| True if dateStr (YYYY.MM.DD or YYYY-MM-DD) is a daylight-savings desync date: RTH session times differ (use 14:30 open / 20:59 close for PDO/PDC). |
//+------------------------------------------------------------------+
bool bool_RTHsession_Is_DaylightSavingsDesync(const string dateStr)
{
   // Normalize to YYYY.MM.DD so we match calendar/TimeToString(TIME_DATE) and the list below
   string normalized = dateStr;
   if(StringFind(dateStr, "-") >= 0)
      StringReplace(normalized, "-", ".");  // modifies normalized in place; returns int (count)
   static string daylightSavings_desync_dates[] = {
      "2026.03.08", "2026.03.09", "2026.03.10", "2026.03.11", "2026.03.12",
      "2026.03.13", "2026.03.14", "2026.03.15", "2026.03.16", "2026.03.17",
      "2026.03.18", "2026.03.19", "2026.03.20", "2026.03.21", "2026.03.22",
      "2026.03.23", "2026.03.24", "2026.03.25", "2026.03.26", "2026.03.27",
      "2026.03.28",
      "2026.10.25", "2026.10.26", "2026.10.27", "2026.10.28", "2026.10.29",
      "2026.10.30", "2026.10.31"
   };
   for(int i = 0; i < ArraySize(daylightSavings_desync_dates); i++)
      if(daylightSavings_desync_dates[i] == normalized)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| RTH open bar offset in seconds from day start. Desync dates: 14:30 (52200); normal: 15:30 (55800). |
//+------------------------------------------------------------------+
int GetRthOpenBarOffsetSeconds(const string dateStr)
{
   int offset;
   if(bool_RTHsession_Is_DaylightSavingsDesync(dateStr))
      offset = 14*3600 + 30*60;
   else
      offset = 15*3600 + 30*60;
   return offset;
}

//+------------------------------------------------------------------+
//| True if server-calendar midnight dayStart is Sunday (MqlDateTime.day_of_week 0 = Sunday). |
//+------------------------------------------------------------------+
bool IsCalendarDaySunday(datetime dayStart)
{
   MqlDateTime m;
   TimeToStruct(dayStart, m);
   return (m.day_of_week == 0);
}

//+------------------------------------------------------------------+
//| Return previous trading day date string (YYYY.MM.DD) from calendar: go back 1 day, skip Saturday/Sunday. "" if not found. |
//+------------------------------------------------------------------+
string GetPreviousTradingDayDateString(datetime dayStart)
{
   string key = TimeToString(dayStart, TIME_DATE);  // YYYY.MM.DD to match calendar
   int foundIdx = -1;
   for(int calIdx = 0; calIdx < g_calendarCount; calIdx++)
      if(g_calendar[calIdx].dateStr == key) { foundIdx = calIdx; break; }
   if(foundIdx <= 0) return "";
   int prevIdx = foundIdx - 1;
   while(prevIdx >= 0 && (g_calendar[prevIdx].dayofweek == "Saturday" || g_calendar[prevIdx].dayofweek == "Sunday"))
      prevIdx--;
   if(prevIdx < 0) return "";
   return g_calendar[prevIdx].dateStr;
}

//+------------------------------------------------------------------+
//| Pull previous trading day's PDO/PDH/PDL/PDC from M30, overwrite g_staticMarketContext. referenceDayStart = today 00:00. |
//| PDO/PDC use iBarShift+iOpen/iClose so we match chart bars; PDH/PDL from CopyRates over the day. |
//+------------------------------------------------------------------+
void UpdateStaticMarketContext(datetime referenceDayStart)
{
   g_staticMarketContext.PDOpreviousDayRTHOpen  = 0;
   g_staticMarketContext.PDHpreviousDayHigh  = 0;
   g_staticMarketContext.PDLpreviousDayLow   = 0;
   g_staticMarketContext.PDCpreviousDayRTHClose = 0;
   g_staticMarketContext.PDdate              = "";
   string prevDayStr = GetPreviousTradingDayDateString(referenceDayStart);
   if(StringLen(prevDayStr) == 0)
   {
      FatalError("UpdateStaticMarketContext: no previous trading day for " + TimeToString(referenceDayStart, TIME_DATE));
      return;
   }
   g_staticMarketContext.PDdate = prevDayStr;
   string parts[];
   if(StringSplit(prevDayStr, '.', parts) != 3)
   {
      FatalError("UpdateStaticMarketContext: invalid prev day format " + prevDayStr);
      return;
   }
   int year = (int)StringToInteger(parts[0]);
   int month = (int)StringToInteger(parts[1]);
   int day = (int)StringToInteger(parts[2]);
   MqlDateTime mtPrev = {0};
   mtPrev.year = year; mtPrev.mon = month; mtPrev.day = day;
   datetime prevDayStart = StructToTime(mtPrev);
   datetime prevDayEnd   = prevDayStart + 86400;

   // PDO = RTH open (M1), PDC = RTH close (M1). On daylight-savings desync dates use 14:30 / 21:00; else 15:30 / 21:59.
   datetime barPDO, barPDC;
   if(bool_RTHsession_Is_DaylightSavingsDesync(prevDayStr))
   {
      barPDO = prevDayStart + 14*3600 + 30*60;   // 14:30
      barPDC = prevDayStart + 20*3600 + 59*60;  // 20:59
   }
   else
   {
      barPDO = prevDayStart + 15*3600 + 30*60;   // 15:30
      barPDC = prevDayStart + 21*3600 + 59*60;  // 21:59
   }
   int shiftPDO_M1 = iBarShift(_Symbol, PERIOD_M1, barPDO, false);
   int shiftPDC_M1 = iBarShift(_Symbol, PERIOD_M1, barPDC, false);
   if(shiftPDO_M1 >= 0)
      g_staticMarketContext.PDOpreviousDayRTHOpen = iOpen(_Symbol, PERIOD_M1, shiftPDO_M1);
   if(shiftPDC_M1 >= 0)
      g_staticMarketContext.PDCpreviousDayRTHClose = iClose(_Symbol, PERIOD_M1, shiftPDC_M1);

   // PDH/PDL = max High / min Low over the day — use same bar indexing as chart (iterate shifts for the day)
   int shiftDayStart = iBarShift(_Symbol, PERIOD_M30, prevDayStart, false);
   int shiftDayEnd   = iBarShift(_Symbol, PERIOD_M30, prevDayEnd - 1, false);  // last bar with time < prevDayEnd
   if(shiftDayStart < 0 || shiftDayEnd < 0)
   {
      FatalError("UpdateStaticMarketContext: no M30 bars for previous day " + prevDayStr + " (shiftDayStart=" + IntegerToString(shiftDayStart) + " shiftDayEnd=" + IntegerToString(shiftDayEnd) + ")");
      return;
   }
   double pdh = -1e300, pdl = 1e300;
   for(int shiftIdx = shiftDayEnd; shiftIdx <= shiftDayStart; shiftIdx++)
   {
      double high = iHigh(_Symbol, PERIOD_M30, shiftIdx);
      double low = iLow(_Symbol, PERIOD_M30, shiftIdx);
      if(high > pdh) pdh = high;
      if(low < pdl) pdl = low;
   }
   if(pdh <= -1e300 || pdl >= 1e300)
   {
      FatalError("UpdateStaticMarketContext: no valid PDH/PDL for previous day " + prevDayStr + " (no bars in range)");
      return;
   }
   if(pdh == 0.0 || pdl == 0.0)
   {
      FatalError("UpdateStaticMarketContext: PDH or PDL is zero for previous day " + prevDayStr);
      return;
   }
   g_staticMarketContext.PDHpreviousDayHigh = pdh;
   g_staticMarketContext.PDLpreviousDayLow = pdl;
   LogStaticMarketContextForDay(referenceDayStart);
}

//+------------------------------------------------------------------+
//| Once per day, right after prior-day PDO/PDH/PDL/PDC are pulled (early OnTimer on new day). |
//+------------------------------------------------------------------+
void LogStaticMarketContextForDay(const datetime referenceDayStart)
{
   if(!dailyLog_StaticMarketContext || referenceDayStart == 0)
      return;
   const string dateStr = TimeToString(referenceDayStart, TIME_DATE);
   const string fname = dateStr + "_staticMarketContext_log.csv";
   if(FileIsExist(fname))
      return;
   int fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   FileWrite(fh, "date", "PDdate", "PDO", "PDH", "PDL", "PDC", "PD_trend");
   FileWrite(fh, dateStr, g_staticMarketContext.PDdate,
      DoubleToString(g_staticMarketContext.PDOpreviousDayRTHOpen, _Digits),
      DoubleToString(g_staticMarketContext.PDHpreviousDayHigh, _Digits),
      DoubleToString(g_staticMarketContext.PDLpreviousDayLow, _Digits),
      DoubleToString(g_staticMarketContext.PDCpreviousDayRTHClose, _Digits),
      GetPDtrendString());
   FileClose(fh);
}

//+------------------------------------------------------------------+
//| Load levels for a single day from CSV. Only rows where startStr <= dateStr <= endStr are added. |
//| Format: start,end,levelPrice,categories,tag (header on first line). start/end YYYY.MM.DD. |
//+------------------------------------------------------------------+
bool LoadLevelsForDate(const string &dateStr)
{
   g_levelsTotalCount = 0;
   int fileHandle = FileOpen(InpLevelsFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandle == INVALID_HANDLE)
   {
      FatalError("Levels file could not be opened: " + InpLevelsFile + " (place CSV in Terminal/Common/Files)");
      return false;
   }
   string line = FileReadString(fileHandle);  // skip header
   while(!FileIsEnding(fileHandle))
   {
      line = FileReadString(fileHandle);
      if(StringLen(line) == 0) continue;
      string parts[];
      if(StringSplit(line, ',', parts) < 5) continue;
      string startStr = parts[0];
      string endStr   = parts[1];
      if(endStr < dateStr || startStr > dateStr)
         continue;
      if(g_levelsTotalCount >= MAX_LEVEL_ROWS)
      {
         FileClose(fileHandle);
         FatalError("LoadLevelsForDate: too many levels for " + dateStr + " (max " + IntegerToString(MAX_LEVEL_ROWS) + ")");
         return false;
      }
      g_levels[g_levelsTotalCount].startStr   = startStr;
      g_levels[g_levelsTotalCount].endStr     = endStr;
      g_levels[g_levelsTotalCount].levelPrice = StringToDouble(parts[2]);
      g_levels[g_levelsTotalCount].categories = parts[3];
      g_levels[g_levelsTotalCount].tag        = parts[4];
      g_levelsTotalCount++;
   }
   FileClose(fileHandle);
   return true;  // file read ok (count may be 0 if no levels for this day)
}

//+------------------------------------------------------------------+
//| Get newway_Diff_CloseToLevel from g_levelsExpanded at barTime. Key = levelPrice OR tag (use one, pass 0 or "" for the other). |
//+------------------------------------------------------------------+
double GetLevelExpandedDiff(double levelPrice, string tag, datetime barTime)
{
   for(int levelIdx = 0; levelIdx < g_levelsTodayCount; levelIdx++)
   {
      if(levelPrice > 0 && g_levelsExpanded[levelIdx].levelPrice != levelPrice) continue;
      if(StringLen(tag) > 0 && g_levelsExpanded[levelIdx].tag != tag) continue;
      for(int barIdx = 0; barIdx < g_levelsExpanded[levelIdx].count; barIdx++)
         if(g_levelsExpanded[levelIdx].times[barIdx] == barTime)
            return g_levelsExpanded[levelIdx].diffs[barIdx];
      return 0;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| In last windowBars ending at bar barK: Up = max(high-level) when high>level; Down = max(level-low) when low<level. |
//| Returns "never" if no bar had price above level (Up) or below level (Down); else returns value as string. |
//| Uses OptionalDouble in memory (no -1e300 sentinel). |
//+------------------------------------------------------------------+
string Rules_GetHighestDiffFromLevelInWindowString(double levelPrice, int barK, int windowBars, bool wantUp)
{
   int startBar = MathMax(0, barK - windowBars + 1);
   OptionalDouble result;
   result.hasValue = false;
   if(wantUp)
   {
      for(int barIdx = startBar; barIdx <= barK; barIdx++)
      {
         if(g_m1Rates[barIdx].high > levelPrice)
         {
            double diff = g_m1Rates[barIdx].high - levelPrice;
            if(!result.hasValue || diff > result.value)
            {
               result.hasValue = true;
               result.value = diff;
            }
         }
      }
   }
   else
   {
      for(int barIdx = startBar; barIdx <= barK; barIdx++)
      {
         if(g_m1Rates[barIdx].low < levelPrice)
         {
            double diff = levelPrice - g_m1Rates[barIdx].low;
            if(!result.hasValue || diff > result.value)
            {
               result.hasValue = true;
               result.value = diff;
            }
         }
      }
   }
   return result.hasValue ? DoubleToString(result.value, _Digits) : "never";
}

//+------------------------------------------------------------------+
//| O(1) bar predicates for level-bar stats (hot path).              |
//+------------------------------------------------------------------+
bool IsBarCleanAbove(double o, double h, double l, double c, double level)
{
   return (o > level && h > level && l > level && c > level);
}
bool IsBarCleanBelow(double o, double h, double l, double c, double level)
{
   return (o < level && h < level && l < level && c < level);
}
bool IsBarOverlap(double low, double high, double level)
{
   return (low <= level && level <= high);
}

//+------------------------------------------------------------------+
//| Physical contact only: level within bar range [low, high]. |
//+------------------------------------------------------------------+
bool IsBarInPhysicalContactWithLevel(const double o, const double h, const double l, const double c, const double level)
{
   return IsBarOverlap(l, h, level);
}

//+------------------------------------------------------------------+
//| In contact with level (physical touch or proxThreshold on O/H/L/C). |
//+------------------------------------------------------------------+
bool IsBarInProximityContactWithLevel(const double o, const double h, const double l, const double c,
   const double level, const double proxThreshold)
{
   if(IsBarInPhysicalContactWithLevel(o, h, l, c, level)) return true;
   if(proxThreshold <= 0.0) return false;
   if(MathAbs(o - level) <= proxThreshold) return true;
   if(MathAbs(h - level) <= proxThreshold) return true;
   if(MathAbs(l - level) <= proxThreshold) return true;
   if(MathAbs(c - level) <= proxThreshold) return true;
   return false;
}

//+------------------------------------------------------------------+
//| In contact with level (physical touch or g_algoShared.proximity_threshold on O/H/L/C). |
//+------------------------------------------------------------------+
bool IsBarInContactWithLevel(double o, double h, double l, double c, double level)
{
   return IsBarInProximityContactWithLevel(o, h, l, c, level, g_algoShared.proximity_threshold);
}

//+------------------------------------------------------------------+
//| CSV suffix from g_algoShared.proximity_threshold: 0.01->"001", 0.3->"03". |
//+------------------------------------------------------------------+
string FalgoContactAndProximityCountSuffixForLogColumns()
{
   const double t = g_algoShared.proximity_threshold;
   if(t < 0.1)
      return StringFormat("%03d", (int)MathRound(t * 100.0));
   return StringFormat("%02d", (int)MathRound(t * 10.0));
}

//+------------------------------------------------------------------+
string FalgoLogCol_contactAndProximityCount(const string namePrefix)
{
   return namePrefix + "contactAndProximityCount_" + FalgoContactAndProximityCountSuffixForLogColumns();
}

//+------------------------------------------------------------------+
//| Min price distance from bar range to level (0 if overlap; else low-level or level-high). |
//+------------------------------------------------------------------+
double GetBarClosestPriceProximityToLevel(double h, double l, double level)
{
   if(l <= level && level <= h) return 0.0;
   if(l > level) return l - level;
   return level - h;
}

//+------------------------------------------------------------------+
bool AlgoBarIsFormingM1Bar(const int barIdx)
{
   if(barIdx < 0 || g_barsInDay <= 0 || barIdx != g_barsInDay - 1)
      return false;
   return (g_m1Rates[barIdx].time == g_lastTimer1Time - (g_lastTimer1Time % 60));
}

//+------------------------------------------------------------------+
//| Last closed M1 bar index in g_m1Rates (forming bar at g_barsInDay-1 is excluded). |
//+------------------------------------------------------------------+
int PullingHistoryLastClosedBarIdx()
{
   if(g_barsInDay <= 0)
      return -1;
   if(g_barsInDay >= 2 && AlgoBarIsFormingM1Bar(g_barsInDay - 1))
      return g_barsInDay - 2;
   return g_barsInDay - 1;
}

//+------------------------------------------------------------------+
bool M1BarCloseLiveSafeMode()
{
   return bigflipper_pullinghistory_always_full_replay;
}

//+------------------------------------------------------------------+
bool M1BarCloseReconnectRequiresFullRescan()
{
   if(!M1BarCloseLiveSafeMode())
      return false;
   const bool connected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   if(!connected)
   {
      g_m1BarCloseTerminalWasConnected = false;
      return false;
   }
   if(!g_m1BarCloseTerminalWasConnected)
   {
      g_m1BarCloseTerminalWasConnected = true;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool M1BarCloseClosedBarsHaveGap(const int lastClosedBarIdx, const int incLastClosedBarIdx)
{
   if(incLastClosedBarIdx < 0)
      return false;
   return (lastClosedBarIdx > incLastClosedBarIdx + 1);
}

//+------------------------------------------------------------------+
bool M1BarCloseStatsNeedsIntegrityFullRescan(const int lastClosedBarIdx)
{
   if(g_m1BarCloseStatsIncDayStart != g_m1DayStart)
      return true;
   if(g_m1BarCloseStatsIncLastClosedBarIdx > lastClosedBarIdx)
      return true;
   if(M1BarCloseClosedBarsHaveGap(lastClosedBarIdx, g_m1BarCloseStatsIncLastClosedBarIdx))
      return true;
   if(M1BarCloseReconnectRequiresFullRescan())
      return true;
   return false;
}

//+------------------------------------------------------------------+
void M1BarCloseStatsIncResetDayState()
{
   g_m1BarCloseStatsIncDayStart = 0;
   g_m1BarCloseStatsIncLastClosedBarIdx = -1;
   M1BarCloseStatsIncResetRunningState();
}

//+------------------------------------------------------------------+
void M1BarCloseStatsIncResetRunningState()
{
   g_sessionHlIncFirstON = true;
   g_sessionHlIncFirstRTH = true;
   g_sessionHlIncRunONhigh = 0.0;
   g_sessionHlIncRunONlow = 0.0;
   g_sessionHlIncRunRTHhigh = 0.0;
   g_sessionHlIncRunRTHlow = 0.0;
   g_sessionHlIncRunDayHigh = 0.0;
   g_sessionHlIncRunDayLow = 0.0;
   g_ibHlIncIbHigh = -1e300;
   g_ibHlIncIbLow = 1e300;
   g_ibHlIncIbComplete = false;
   g_gapAttemptIncRthOpenBarIdx = -1;
   g_gapAttemptIncAttemptBarIdx = -1;
   g_gapAttemptIncPrevFill = -1.0;
   g_gapAttemptIncRunningMaxAway = 0.0;
   g_gapAttemptIncFinalMaxAway = 0.0;
   g_dayProgressIncP = 0;
   g_dayProgressIncWins = 0;
   g_dayProgressIncTotal = 0;
   g_dayProgressIncDayPointsSum = 0.0;
   g_dayProgressIncDayProfitSum = 0.0;
   g_dayProgressIncDayGrossProfit = 0.0;
   g_dayProgressIncDayGrossLoss = 0.0;
   g_dayProgressIncONwins = 0;
   g_dayProgressIncONtotal = 0;
   g_dayProgressIncONpointsSum = 0.0;
   g_dayProgressIncONprofitSum = 0.0;
   g_dayProgressIncRTHwins = 0;
   g_dayProgressIncRTHtotal = 0;
   g_dayProgressIncRTHpointsSum = 0.0;
   g_dayProgressIncRTHprofitSum = 0.0;
   g_levelTradeStatsIncAppliedTradeCount = 0;
}

//+------------------------------------------------------------------+
//| barEndInclusive: last bar to update. Returns false if nothing to do. needFullRescan true => barStart is 0. |
//+------------------------------------------------------------------+
bool M1BarCloseStatsPrepareBarRange(int &barStart, int &barEndInclusive, bool &needFullRescan)
{
   needFullRescan = false;
   g_m1BarCloseStatsFormingBarIdx = -1;
   const int lastClosedBarIdx = PullingHistoryLastClosedBarIdx();
   barEndInclusive = lastClosedBarIdx;
   if(barEndInclusive < 0)
      return false;

   if(M1BarCloseLiveSafeMode())
   {
      needFullRescan = M1BarCloseStatsNeedsIntegrityFullRescan(lastClosedBarIdx);
      const int formingIdx = g_barsInDay - 1;
      if(formingIdx >= 0 && AlgoBarIsFormingM1Bar(formingIdx))
         g_m1BarCloseStatsFormingBarIdx = formingIdx;
   }
   else if(g_m1BarCloseStatsIncDayStart != g_m1DayStart || g_m1BarCloseStatsIncLastClosedBarIdx > lastClosedBarIdx)
      needFullRescan = true;

   if(needFullRescan)
   {
      M1BarCloseStatsIncResetRunningState();
      g_m1BarCloseStatsIncLastClosedBarIdx = -1;
      g_m1BarCloseStatsIncDayStart = g_m1DayStart;
      barStart = 0;
   }
   else
      barStart = g_m1BarCloseStatsIncLastClosedBarIdx + 1;
   return (barStart <= barEndInclusive);
}

//+------------------------------------------------------------------+
void M1BarCloseStatsCommitBarRange()
{
   const int lastClosedBarIdx = PullingHistoryLastClosedBarIdx();
   if(lastClosedBarIdx >= 0)
      g_m1BarCloseStatsIncLastClosedBarIdx = lastClosedBarIdx;
}

//+------------------------------------------------------------------+
bool M1BarCloseStatsBeginUpdate()
{
   g_m1BarCloseStatsIncRangeActive = M1BarCloseStatsPrepareBarRange(
      g_m1BarCloseStatsIncBarStart, g_m1BarCloseStatsIncBarEndInclusive, g_m1BarCloseStatsIncNeedFullRescan);
   return g_m1BarCloseStatsIncRangeActive;
}

//+------------------------------------------------------------------+
void M1BarCloseStatsEndUpdate()
{
   if(g_m1BarCloseStatsIncRangeActive)
      M1BarCloseStatsCommitBarRange();
   g_m1BarCloseStatsIncRangeActive = false;
}

//+------------------------------------------------------------------+
bool M1BarCloseStatsBarRangeActive()
{
   return g_m1BarCloseStatsIncRangeActive;
}

//+------------------------------------------------------------------+
void AlgoLiveOhlcAndProximityAtBar(const int algoNumber, const int barIdx, double &o, double &h, double &l, double &c, double &prox)
{
   o = g_m1Rates[barIdx].open;
   h = g_m1Rates[barIdx].high;
   l = g_m1Rates[barIdx].low;
   c = g_m1Rates[barIdx].close;
   if(AlgoBarIsFormingM1Bar(barIdx))
   {
      h = MathMax(h, g_liveBid);
      l = MathMin(l, g_liveBid);
      c = g_liveBid;
   }
   const double anchor = FalgoClosestLevelPriceAtBarForAlgo(algoNumber, barIdx);
   prox = (anchor > 0.0) ? GetBarClosestPriceProximityToLevel(h, l, anchor) : 0.0;
}

//+------------------------------------------------------------------+
//| Reset one weekly level's algo-family pullinghistory day state.           |
//+------------------------------------------------------------------+
void ResetWeeklyLevelAlgoFamilyDayState(WeeklyLevelAlgoFamilyDayState &st, double levelPrice)
{
   st.levelPrice = levelPrice;
   st.physicalContactCount_today = 0;
   st.contactAndProximityCount_today = 0;
   st.bounceCount_today = 0;
   st.ceilingCount_today = 0;
   st.ceilingProximityCandles_today = 0;
   st.candlesPassedSinceLastBounce = 0;
   st.candlesPassedSinceLastCeiling = 0;
   st.bounceEventCount = 0;
   st.ceilingEventCount = 0;
   st.ceilingProximityCandleCount = 0;
   st.lastInBounceContact = false;
   st.lastInCeilingContact = false;
   st.contactFromAbove = false;
   st.contactFromBelow = false;
   st.bounceCleanOhlcSinceContact = 0;
   st.ceilingCleanOhlcSinceContact = 0;
   st.bounceHighestLowSinceContact = 0.0;
   st.ceilingLowestHighSinceContact = 0.0;
   st.lastInPhysicalContact = false;
   st.contactFromBelowPhysical = false;
   st.cleanStreakStartTime = 0;
   st.cleanStreakCount = 0;
   st.cleanStreakOHLCSum = 0.0;
   st.cleanStreakIsAbove = false;
   st.anchorAbove = 0.0;
   st.anchorAboveTime = 0;
   st.anchorBelow = 0.0;
   st.anchorBelowTime = 0;
}

//+------------------------------------------------------------------+
//| Weekly + daily + stacked levels: stacked = weekly+daily hybrid; daily-only algos use weekday substrings. |
//+------------------------------------------------------------------+
bool AlgoFamilyLevelShouldTrackForDayStatsLocal(const string &categories)
{
   if(LevelIsWeeklyKind(categories))
      return true;
   return LevelIsDailyKind(categories);
}

//+------------------------------------------------------------------+
int AlgoFamilyCountEventTimesInLookbackMinutes(const datetime &eventTimes[], const int eventCount,
   const datetime asOfBarTime, const int lookbackMinutes)
{
   if(lookbackMinutes <= 0 || eventCount <= 0)
      return 0;
   const datetime windowStart = asOfBarTime - (datetime)lookbackMinutes * 60;
   int n = 0;
   for(int i = 0; i < eventCount; i++)
   {
      if(eventTimes[i] >= windowStart && eventTimes[i] <= asOfBarTime)
         n++;
   }
   return n;
}

//+------------------------------------------------------------------+
void AlgoFamilyRecordBounceEvent(WeeklyLevelAlgoFamilyDayState &st, const datetime barTime)
{
   if(st.bounceEventCount < ALGOFAMILY_BOUNCE_CEILING_EVENTS_MAX)
      st.bounceEventTimes[st.bounceEventCount++] = barTime;
}

//+------------------------------------------------------------------+
void AlgoFamilyRecordCeilingEvent(WeeklyLevelAlgoFamilyDayState &st, const datetime barTime)
{
   if(st.ceilingEventCount < ALGOFAMILY_BOUNCE_CEILING_EVENTS_MAX)
      st.ceilingEventTimes[st.ceilingEventCount++] = barTime;
}

//+------------------------------------------------------------------+
void AlgoFamilyRecordCeilingProximityCandle(WeeklyLevelAlgoFamilyDayState &st, const datetime barTime)
{
   if(st.ceilingProximityCandleCount < ALGOFAMILY_BOUNCE_CEILING_EVENTS_MAX)
      st.ceilingProximityCandleTimes[st.ceilingProximityCandleCount++] = barTime;
}

//+------------------------------------------------------------------+
//| Bounce/ceiling core: separate proximity thresholds per event type; then >=N clean OHLC bars. |
//| ceilingProximityCandles: each M1 bar in proximity_threshold contact from below. |
//+------------------------------------------------------------------+
void ApplyBounceCeilingOnBarCore(const double o, const double h, const double l, const double c, const double levelPrice,
   bool &lastInBounceContact, bool &lastInCeilingContact, bool &contactFromAbove, bool &contactFromBelow,
   int &bounceCleanOhlcSinceContact, int &ceilingCleanOhlcSinceContact,
   double &bounceHighestLowSinceContact, double &ceilingLowestHighSinceContact,
   int &outBounceInc, int &outCeilingInc, int &outCeilingProxInc)
{
   outBounceInc = 0;
   outCeilingInc = 0;
   outCeilingProxInc = 0;

   const bool in_bounce_prox = IsBarInProximityContactWithLevel(o, h, l, c, levelPrice, g_algoShared.bounce_event_proximity_threshold);
   const bool in_ceiling_prox = IsBarInProximityContactWithLevel(o, h, l, c, levelPrice, g_algoShared.ceiling_event_proximity_threshold);
   const bool in_prox_candle_prox = IsBarInProximityContactWithLevel(o, h, l, c, levelPrice, g_algoShared.proximity_threshold);

   if(in_bounce_prox)
   {
      contactFromAbove = (c >= levelPrice);
      bounceCleanOhlcSinceContact = 0;
      bounceHighestLowSinceContact = 0.0;
   }
   if(in_ceiling_prox)
   {
      contactFromBelow = (c < levelPrice);
      ceilingCleanOhlcSinceContact = 0;
      ceilingLowestHighSinceContact = 0.0;
   }
   if(in_prox_candle_prox && c < levelPrice)
      outCeilingProxInc = 1;

   if(!in_bounce_prox)
   {
      if(contactFromAbove && IsBarCleanAbove(o, h, l, c, levelPrice))
      {
         if(bounceCleanOhlcSinceContact == 0)
            bounceHighestLowSinceContact = l;
         else
            bounceHighestLowSinceContact = MathMax(bounceHighestLowSinceContact, l);
         bounceCleanOhlcSinceContact++;
      }
      else if(bounceCleanOhlcSinceContact > 0 && !IsBarCleanAbove(o, h, l, c, levelPrice))
      {
         bounceCleanOhlcSinceContact = 0;
         bounceHighestLowSinceContact = 0.0;
      }
   }

   if(!in_ceiling_prox)
   {
      if(contactFromBelow && IsBarCleanBelow(o, h, l, c, levelPrice))
      {
         if(ceilingCleanOhlcSinceContact == 0)
            ceilingLowestHighSinceContact = h;
         else
            ceilingLowestHighSinceContact = MathMin(ceilingLowestHighSinceContact, h);
         ceilingCleanOhlcSinceContact++;
      }
      else if(ceilingCleanOhlcSinceContact > 0 && !IsBarCleanBelow(o, h, l, c, levelPrice))
      {
         ceilingCleanOhlcSinceContact = 0;
         ceilingLowestHighSinceContact = 0.0;
      }
   }

   const bool bounceCandle = (!in_bounce_prox && l > levelPrice);
   const bool ceilingCandle = (!in_ceiling_prox && h < levelPrice);
   const int bounceMin = g_algoShared.bounce_minimum_clean_ohlc_to_qualify;
   const int ceilingMin = g_algoShared.ceiling_minimum_clean_ohlc_to_qualify;
   const double bounceMinLowDiff = g_algoShared.bounce_minimum_HighestLow_levelDiff_to_qualify;
   const double ceilingMinHighDiff = g_algoShared.ceiling_minimum_LowestHigh_levelDiff_to_qualify;

   bool qualifyBounce = false;
   if(bounceCandle && contactFromAbove)
   {
      if(bounceMin <= 0)
         qualifyBounce = lastInBounceContact;
      else
         qualifyBounce = (bounceCleanOhlcSinceContact >= bounceMin);
      if(qualifyBounce && bounceMinLowDiff > 0.0)
         qualifyBounce = (bounceHighestLowSinceContact - levelPrice >= bounceMinLowDiff);
   }
   if(qualifyBounce)
   {
      outBounceInc = 1;
      contactFromAbove = false;
      bounceCleanOhlcSinceContact = 0;
      bounceHighestLowSinceContact = 0.0;
   }

   bool qualifyCeiling = false;
   if(ceilingCandle && contactFromBelow)
   {
      if(ceilingMin <= 0)
         qualifyCeiling = lastInCeilingContact;
      else
         qualifyCeiling = (ceilingCleanOhlcSinceContact >= ceilingMin);
      if(qualifyCeiling && ceilingMinHighDiff > 0.0)
         qualifyCeiling = (levelPrice - ceilingLowestHighSinceContact >= ceilingMinHighDiff);
   }
   if(qualifyCeiling)
   {
      outCeilingInc = 1;
      contactFromBelow = false;
      ceilingCleanOhlcSinceContact = 0;
      ceilingLowestHighSinceContact = 0.0;
   }

   if(!in_bounce_prox && !lastInBounceContact)
   {
      contactFromAbove = false;
      bounceCleanOhlcSinceContact = 0;
      bounceHighestLowSinceContact = 0.0;
   }
   if(!in_ceiling_prox && !lastInCeilingContact)
   {
      contactFromBelow = false;
      ceilingCleanOhlcSinceContact = 0;
      ceilingLowestHighSinceContact = 0.0;
   }
   lastInBounceContact = in_bounce_prox;
   lastInCeilingContact = in_ceiling_prox;
}

//+------------------------------------------------------------------+
void AlgoFamilyApplyBounceCeilingOnBar(WeeklyLevelAlgoFamilyDayState &st,
   const double o, const double h, const double l, const double c, const datetime barTime,
   const bool recordEvents)
{
   int bounceInc = 0, ceilingInc = 0, ceilingProxInc = 0;
   ApplyBounceCeilingOnBarCore(o, h, l, c, st.levelPrice,
      st.lastInBounceContact, st.lastInCeilingContact, st.contactFromAbove, st.contactFromBelow,
      st.bounceCleanOhlcSinceContact, st.ceilingCleanOhlcSinceContact,
      st.bounceHighestLowSinceContact, st.ceilingLowestHighSinceContact,
      bounceInc, ceilingInc, ceilingProxInc);
   if(ceilingProxInc > 0)
   {
      st.ceilingProximityCandles_today += ceilingProxInc;
      if(recordEvents)
         AlgoFamilyRecordCeilingProximityCandle(st, barTime);
   }
   if(bounceInc > 0)
   {
      st.bounceCount_today += bounceInc;
      st.candlesPassedSinceLastBounce = 0;
      if(recordEvents)
         AlgoFamilyRecordBounceEvent(st, barTime);
   }
   else if(st.bounceCount_today > 0)
      st.candlesPassedSinceLastBounce++;
   if(ceilingInc > 0)
   {
      st.ceilingCount_today += ceilingInc;
      st.candlesPassedSinceLastCeiling = 0;
      if(recordEvents)
         AlgoFamilyRecordCeilingEvent(st, barTime);
   }
   else if(st.ceilingProximityCandles_today > 0 || st.ceilingCount_today > 0)
      st.candlesPassedSinceLastCeiling++;
}

//+------------------------------------------------------------------+
void AlgoFamilyDayLevelStatsForLevelAsOfTime(const double levelPrice, const datetime asOfTime,
   int &outBounce, int &outCeiling, int &outProx, int &outContact,
   int &outCandlesSinceBounce, int &outCandlesSinceCeiling)
{
   outBounce = 0;
   outCeiling = 0;
   outProx = 0;
   outContact = 0;
   outCandlesSinceBounce = 0;
   outCandlesSinceCeiling = 0;
   if(levelPrice <= 0.0 || asOfTime <= 0 || g_barsInDay <= 0)
      return;

   int lastBarIdx = -1;
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      if(g_m1Rates[barIdx].time + 60 <= asOfTime)
         lastBarIdx = barIdx;
      else
         break;
   }
   if(lastBarIdx < 0)
      return;

   WeeklyLevelAlgoFamilyDayState st;
   ResetWeeklyLevelAlgoFamilyDayState(st, levelPrice);
   for(int barIdx = 0; barIdx <= lastBarIdx; barIdx++)
   {
      const double o = g_m1Rates[barIdx].open, h = g_m1Rates[barIdx].high;
      const double l = g_m1Rates[barIdx].low, c = g_m1Rates[barIdx].close;
      if(IsBarInContactWithLevel(o, h, l, c, levelPrice))
         outContact++;
      AlgoFamilyApplyBounceCeilingOnBar(st, o, h, l, c, g_m1Rates[barIdx].time, false);
   }
   outBounce = st.bounceCount_today;
   outCeiling = st.ceilingCount_today;
   outProx = st.ceilingProximityCandles_today;
   outCandlesSinceBounce = st.candlesPassedSinceLastBounce;
   outCandlesSinceCeiling = st.candlesPassedSinceLastCeiling;
}

//+------------------------------------------------------------------+
//| Day bounce/ceiling for one level through last M1 bar closed at or before asOfTime. |
//+------------------------------------------------------------------+
void AlgoFamilyDayBounceCeilingForLevelAsOfTime(const double levelPrice, const datetime asOfTime,
   int &outBounce, int &outCeiling)
{
   int prox = 0, contact = 0, sinceB = 0, sinceC = 0;
   AlgoFamilyDayLevelStatsForLevelAsOfTime(levelPrice, asOfTime, outBounce, outCeiling, prox, contact, sinceB, sinceC);
}

//+------------------------------------------------------------------+
int AlgoFamilyDayStartWeekPerspectiveBounceForLevel(const double levelPrice)
{
   for(int rowIdx = 0; rowIdx < g_algoFamilyDayStartWeekPerspectiveCount; rowIdx++)
   {
      if(MathAbs(g_algoFamilyDayStartWeekPerspective[rowIdx].levelPrice - levelPrice) < 1e-9)
         return g_algoFamilyDayStartWeekPerspective[rowIdx].bounceCount;
   }
   return 0;
}

//+------------------------------------------------------------------+
int AlgoFamilyDayStartWeekPerspectiveCeilingForLevel(const double levelPrice)
{
   for(int rowIdx = 0; rowIdx < g_algoFamilyDayStartWeekPerspectiveCount; rowIdx++)
   {
      if(MathAbs(g_algoFamilyDayStartWeekPerspective[rowIdx].levelPrice - levelPrice) < 1e-9)
         return g_algoFamilyDayStartWeekPerspective[rowIdx].ceilingCount;
   }
   return 0;
}

//+------------------------------------------------------------------+
int Falgo_DayStart_ContactAndProxC_1m_EarlierThisWeek(const double levelPrice)
{
   for(int rowIdx = 0; rowIdx < g_algoFamilyDayStartWeekPerspectiveCount; rowIdx++)
   {
      if(MathAbs(g_algoFamilyDayStartWeekPerspective[rowIdx].levelPrice - levelPrice) < 1e-9)
         return g_algoFamilyDayStartWeekPerspective[rowIdx].contact1m_earlierThisWeek_contactAndProximityCount;
   }
   return 0;
}

//+------------------------------------------------------------------+
void AlgoFamilyDayContactCountForLevelAsOfTime(const double levelPrice, const datetime asOfTime, int &outContact)
{
   outContact = 0;
   if(levelPrice <= 0.0 || asOfTime <= 0 || g_barsInDay <= 0)
      return;

   int lastBarIdx = -1;
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      if(g_m1Rates[barIdx].time + 60 <= asOfTime)
         lastBarIdx = barIdx;
      else
         break;
   }
   if(lastBarIdx < 0)
      return;

   for(int barIdx = 0; barIdx <= lastBarIdx; barIdx++)
   {
      const double o = g_m1Rates[barIdx].open, h = g_m1Rates[barIdx].high;
      const double l = g_m1Rates[barIdx].low, c = g_m1Rates[barIdx].close;
      if(IsBarInContactWithLevel(o, h, l, c, levelPrice))
         outContact++;
   }
}

//+------------------------------------------------------------------+
int FalgoDayContactCountForLevelAsOfTime(const double levelPrice, const datetime asOfTime)
{
   int bounce = 0, ceiling = 0, prox = 0, contact = 0, sinceB = 0, sinceC = 0;
   AlgoFamilyDayLevelStatsForLevelAsOfTime(levelPrice, asOfTime, bounce, ceiling, prox, contact, sinceB, sinceC);
   return contact;
}

//+------------------------------------------------------------------+
int AlgoFamilyTrackIdxForLevelPrice(const double levelPrice)
{
   if(levelPrice <= 0.0)
      return -1;
   for(int trackIdx = 0; trackIdx < g_weeklyAlgoFamilyTrackCount; trackIdx++)
   {
      const double tracked = g_levelsExpanded[g_weeklyAlgoFamilyTrackExpandedIdx[trackIdx]].levelPrice;
      if(MathAbs(tracked - levelPrice) < 1e-9)
         return trackIdx;
   }
   return -1;
}

//+------------------------------------------------------------------+
int FalgoBarIdxForDayOpenTime(const datetime barOpenTime)
{
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
      if(g_m1Rates[barIdx].time == barOpenTime)
         return barIdx;
   return -1;
}

//+------------------------------------------------------------------+
void FalgoGetAlgoFamilyLevelDayStatsAtBar(const double levelPrice, const int barIdx,
   int &outBounce, int &outCeiling, int &outProx, int &outContact,
   int &outCandlesSinceBounce, int &outCandlesSinceCeiling)
{
   const int trackIdx = AlgoFamilyTrackIdxForLevelPrice(levelPrice);
   if(trackIdx >= 0 && barIdx >= 0 && barIdx < g_barsInDay)
   {
      const AlgoFamilyLevelDayStatsAtBar s = g_algoFamilyLevelStatsAtBar[trackIdx][barIdx];
      outBounce = s.bounceCount_today;
      outCeiling = s.ceilingCount_today;
      outProx = s.ceilingProximityCandles_today;
      outContact = s.contactAndProximityCount_today;
      outCandlesSinceBounce = s.candlesPassedSinceLastBounce;
      outCandlesSinceCeiling = s.candlesPassedSinceLastCeiling;
      return;
   }
   if(barIdx >= 0 && barIdx < g_barsInDay)
   {
      AlgoFamilyDayLevelStatsForLevelAsOfTime(levelPrice, g_m1Rates[barIdx].time + 60,
         outBounce, outCeiling, outProx, outContact, outCandlesSinceBounce, outCandlesSinceCeiling);
      return;
   }
   outBounce = 0;
   outCeiling = 0;
   outProx = 0;
   outContact = 0;
   outCandlesSinceBounce = 0;
   outCandlesSinceCeiling = 0;
}

//+------------------------------------------------------------------+
int Falgo_GetWeekContactAndProxC_ForLevelAtBar(const int barIdx, const double levelPrice)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || levelPrice <= 0.0)
      return 0;
   const datetime asOfTime = g_m1Rates[barIdx].time + 60;
   int dayContact = 0;
   AlgoFamilyDayContactCountForLevelAsOfTime(levelPrice, asOfTime, dayContact);
   return Falgo_DayStart_ContactAndProxC_1m_EarlierThisWeek(levelPrice) + dayContact;
}

//+------------------------------------------------------------------+
int Falgo_ContactAndProxC_Today_ForLevelAtBar(const int barIdx, const double levelPrice)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || levelPrice <= 0.0)
      return 0;
   int bounce = 0, ceiling = 0, prox = 0, contact = 0, sinceB = 0, sinceC = 0;
   FalgoGetAlgoFamilyLevelDayStatsAtBar(levelPrice, barIdx, bounce, ceiling, prox, contact, sinceB, sinceC);
   return contact;
}

//+------------------------------------------------------------------+
int FalgoGetWeekContactCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return 0;
   const double levelPrice = g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevelToCClose;
   return Falgo_GetWeekContactAndProxC_ForLevelAtBar(barIdx, levelPrice);
}

//+------------------------------------------------------------------+
void PullingHistoryAlgoFamilyClearClosestFields(PullingHistoryAlgoFamilyBarSnap &snap)
{
   snap.closestWeeklyLevelToCClose = 0.0;
   snap.closestWeeklyLevelExpandedIdx = -1;
   snap.closestPriceProximity = 0.0;
   snap.cleanOHLC_streak_startTime = 0;
   snap.cleanOHLC_streak_count = 0;
   snap.cleanOHLC_streak_avgOfOHLC = 0.0;
   snap.closestWeeklyLevel_anchorAbove_within_cleanOHLC_streak = 0.0;
   snap.closestWeeklyLevel_anchorAbove_time = 0;
   snap.closestWeeklyLevel_anchorBelow_within_cleanOHLC_streak = 0.0;
   snap.closestWeeklyLevel_anchorBelow_time = 0;
   snap.closestWeeklyLevel_BounceCount_today = 0;
   snap.closestWeeklyLevel_CeilingCount_today = 0;
   snap.closestWeeklyLevel_CeilingProximityCandles_today = 0;
   snap.closestWeeklyLevel_BounceCount_recent = 0;
   snap.closestWeeklyLevel_CeilingCount_recent = 0;
   snap.closestWeeklyLevel_CeilingProximityCandles_recent = 0;
   snap.closestWeeklyLevel_physicalContactCount_today = 0;
   snap.closestWeeklyLevel_contactAndProximityCount_today = 0;
}

//+------------------------------------------------------------------+
void PullingHistoryAlgoFamilyFillClosestFields(PullingHistoryAlgoFamilyBarSnap &snap,
   const WeeklyLevelAlgoFamilyDayState &st, const int expandedIdx,
   const double h, const double l, const datetime barTime,
   const AlgoFamilyLevelDayStatsAtBar &statsAtBar)
{
   snap.closestWeeklyLevelToCClose = st.levelPrice;
   snap.closestWeeklyLevelExpandedIdx = expandedIdx;
   snap.closestPriceProximity = GetBarClosestPriceProximityToLevel(h, l, st.levelPrice);
   snap.cleanOHLC_streak_startTime = st.cleanStreakStartTime;
   snap.cleanOHLC_streak_count = st.cleanStreakCount;
   snap.cleanOHLC_streak_avgOfOHLC = (st.cleanStreakCount > 0) ?
      st.cleanStreakOHLCSum / (4.0 * (double)st.cleanStreakCount) : 0.0;
   snap.closestWeeklyLevel_anchorAbove_within_cleanOHLC_streak = st.anchorAbove;
   snap.closestWeeklyLevel_anchorAbove_time = st.anchorAboveTime;
   snap.closestWeeklyLevel_anchorBelow_within_cleanOHLC_streak = st.anchorBelow;
   snap.closestWeeklyLevel_anchorBelow_time = st.anchorBelowTime;
   snap.closestWeeklyLevel_BounceCount_today = st.bounceCount_today;
   snap.closestWeeklyLevel_CeilingCount_today = st.ceilingCount_today;
   snap.closestWeeklyLevel_CeilingProximityCandles_today = st.ceilingProximityCandles_today;
   snap.closestWeeklyLevel_BounceCount_recent = statsAtBar.bounceCount_recent;
   snap.closestWeeklyLevel_CeilingCount_recent = statsAtBar.ceilingCount_recent;
   snap.closestWeeklyLevel_CeilingProximityCandles_recent = statsAtBar.ceilingProximityCandles_recent;
   snap.closestWeeklyLevel_physicalContactCount_today = st.physicalContactCount_today;
   snap.closestWeeklyLevel_contactAndProximityCount_today = st.contactAndProximityCount_today;
}

//+------------------------------------------------------------------+
void PullingHistoryIncSaveTrackSnapshot()
{
   g_pullingHistoryIncTrackCountSnapshot = g_weeklyAlgoFamilyTrackCount;
   for(int i = 0; i < g_weeklyAlgoFamilyTrackCount; i++)
      g_pullingHistoryIncTrackExpandedSnapshot[i] = g_weeklyAlgoFamilyTrackExpandedIdx[i];
}

//+------------------------------------------------------------------+
bool PullingHistoryIncTrackListMatches()
{
   if(g_pullingHistoryIncTrackCountSnapshot != g_weeklyAlgoFamilyTrackCount)
      return false;
   for(int i = 0; i < g_weeklyAlgoFamilyTrackCount; i++)
   {
      if(g_pullingHistoryIncTrackExpandedSnapshot[i] != g_weeklyAlgoFamilyTrackExpandedIdx[i])
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void PullingHistoryIncMarkBarSnapshot(const int barIdx)
{
   g_pullingHistoryIncSnapTime[barIdx] = g_m1Rates[barIdx].time;
   g_pullingHistoryIncSnapOpen[barIdx] = g_m1Rates[barIdx].open;
   g_pullingHistoryIncSnapHigh[barIdx] = g_m1Rates[barIdx].high;
   g_pullingHistoryIncSnapLow[barIdx] = g_m1Rates[barIdx].low;
   g_pullingHistoryIncSnapClose[barIdx] = g_m1Rates[barIdx].close;
}

//+------------------------------------------------------------------+
bool PullingHistoryIncBarSnapshotMatches(const int barIdx)
{
   if(g_pullingHistoryIncSnapTime[barIdx] != g_m1Rates[barIdx].time)
      return false;
   if(MathAbs(g_pullingHistoryIncSnapOpen[barIdx] - g_m1Rates[barIdx].open) > 1e-12)
      return false;
   if(MathAbs(g_pullingHistoryIncSnapHigh[barIdx] - g_m1Rates[barIdx].high) > 1e-12)
      return false;
   if(MathAbs(g_pullingHistoryIncSnapLow[barIdx] - g_m1Rates[barIdx].low) > 1e-12)
      return false;
   if(MathAbs(g_pullingHistoryIncSnapClose[barIdx] - g_m1Rates[barIdx].close) > 1e-12)
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool PullingHistoryNeedsFullReplay(const int lastClosedBarIdx)
{
   if(g_pullingHistoryIncDayStart != g_m1DayStart)
      return true;
   if(!PullingHistoryIncTrackListMatches())
      return true;
   if(g_pullingHistoryIncLastBarIdx > lastClosedBarIdx)
      return true;

   if(!M1BarCloseLiveSafeMode())
      return false;

   if(g_pullingHistoryIncLastBarIdx < 0)
      return true;
   if(M1BarCloseClosedBarsHaveGap(lastClosedBarIdx, g_pullingHistoryIncLastBarIdx))
      return true;
   if(M1BarCloseReconnectRequiresFullRescan())
      return true;
   if(lastClosedBarIdx >= 0 && !PullingHistoryIncBarSnapshotMatches(lastClosedBarIdx))
      return true;
   return false;
}

//+------------------------------------------------------------------+
void PullingHistoryIncResetRunningStates()
{
   for(int trackIdx = 0; trackIdx < g_weeklyAlgoFamilyTrackCount; trackIdx++)
      ResetWeeklyLevelAlgoFamilyDayState(g_pullingHistoryIncStates[trackIdx],
         g_levelsExpanded[g_weeklyAlgoFamilyTrackExpandedIdx[trackIdx]].levelPrice);
   g_pullingHistoryIncLastBarIdx = -1;
}

//+------------------------------------------------------------------+
void PullingHistoryCopyStatesToScratch(WeeklyLevelAlgoFamilyDayState &scratch[])
{
   for(int trackIdx = 0; trackIdx < g_weeklyAlgoFamilyTrackCount; trackIdx++)
      scratch[trackIdx] = g_pullingHistoryIncStates[trackIdx];
}

//+------------------------------------------------------------------+
void PullingHistoryProcessFormingBarLive()
{
   const int formingIdx = g_barsInDay - 1;
   if(formingIdx < 0 || !AlgoBarIsFormingM1Bar(formingIdx))
      return;

   WeeklyLevelAlgoFamilyDayState scratch[MAX_ALGOFAMILY_DAYSTART_WEEK_LEVELS];
   PullingHistoryCopyStatesToScratch(scratch);
   int closestWeeklyTrackIdx = -1;
   int closestDailyTrackIdx = -1;
   PullingHistoryAlgoFamilyProcessOneBar(formingIdx, scratch, closestWeeklyTrackIdx, closestDailyTrackIdx);
   g_pullingHistoryIncSnapTime[formingIdx] = g_m1Rates[formingIdx].time;
   g_pullingHistoryIncSnapOpen[formingIdx] = g_m1Rates[formingIdx].open;
   g_pullingHistoryIncSnapHigh[formingIdx] = g_m1Rates[formingIdx].high;
   g_pullingHistoryIncSnapLow[formingIdx] = g_m1Rates[formingIdx].low;
   g_pullingHistoryIncSnapClose[formingIdx] = g_m1Rates[formingIdx].close;
}

//+------------------------------------------------------------------+
void PullingHistoryAlgoFamilyProcessOneBar(const int barIdx, WeeklyLevelAlgoFamilyDayState &states[],
   int &closestWeeklyTrackIdx, int &closestDailyTrackIdx)
{
   closestWeeklyTrackIdx = -1;
   closestDailyTrackIdx = -1;
   double closestWeeklyDist = 1e300;
   double closestDailyDist = 1e300;

   const double o = g_m1Rates[barIdx].open, h = g_m1Rates[barIdx].high, l = g_m1Rates[barIdx].low, c = g_m1Rates[barIdx].close;
   const datetime barTime = g_m1Rates[barIdx].time;

   for(int trackIdx = 0; trackIdx < g_weeklyAlgoFamilyTrackCount; trackIdx++)
   {
      double lvl = states[trackIdx].levelPrice;
      if(IsBarInPhysicalContactWithLevel(o, h, l, c, lvl))
         states[trackIdx].physicalContactCount_today++;
      if(IsBarInContactWithLevel(o, h, l, c, lvl))
         states[trackIdx].contactAndProximityCount_today++;
      AlgoFamilyApplyBounceCeilingOnBar(states[trackIdx], o, h, l, c, barTime, true);
      bool cleanAbove = IsBarCleanAbove(o, h, l, c, lvl);
      bool cleanBelow = IsBarCleanBelow(o, h, l, c, lvl);
      if(cleanAbove || cleanBelow)
      {
         bool continueStreak = (states[trackIdx].cleanStreakCount > 0) &&
            ((cleanAbove && states[trackIdx].cleanStreakIsAbove) || (cleanBelow && !states[trackIdx].cleanStreakIsAbove));
         if(states[trackIdx].cleanStreakCount == 0 || continueStreak)
         {
            if(states[trackIdx].cleanStreakCount == 0)
            {
               states[trackIdx].cleanStreakStartTime = barTime;
               states[trackIdx].cleanStreakIsAbove = cleanAbove;
               states[trackIdx].anchorAbove = 0.0;
               states[trackIdx].anchorAboveTime = 0;
               states[trackIdx].anchorBelow = 0.0;
               states[trackIdx].anchorBelowTime = 0;
            }
            states[trackIdx].cleanStreakCount++;
            states[trackIdx].cleanStreakOHLCSum += o + h + l + c;
            if(states[trackIdx].cleanStreakIsAbove && h > lvl)
            {
               double distAbove = h - lvl;
               if(distAbove > states[trackIdx].anchorAbove)
               {
                  states[trackIdx].anchorAbove = distAbove;
                  states[trackIdx].anchorAboveTime = barTime;
               }
            }
            if(!states[trackIdx].cleanStreakIsAbove && l < lvl)
            {
               double distBelow = lvl - l;
               if(distBelow > states[trackIdx].anchorBelow)
               {
                  states[trackIdx].anchorBelow = distBelow;
                  states[trackIdx].anchorBelowTime = barTime;
               }
            }
         }
         else
         {
            states[trackIdx].cleanStreakStartTime = barTime;
            states[trackIdx].cleanStreakCount = 1;
            states[trackIdx].cleanStreakOHLCSum = o + h + l + c;
            states[trackIdx].cleanStreakIsAbove = cleanAbove;
            states[trackIdx].anchorAbove = 0.0;
            states[trackIdx].anchorAboveTime = 0;
            states[trackIdx].anchorBelow = 0.0;
            states[trackIdx].anchorBelowTime = 0;
            if(cleanAbove && h > lvl)
            {
               states[trackIdx].anchorAbove = h - lvl;
               states[trackIdx].anchorAboveTime = barTime;
            }
            if(cleanBelow && l < lvl)
            {
               states[trackIdx].anchorBelow = lvl - l;
               states[trackIdx].anchorBelowTime = barTime;
            }
         }
      }
      else
      {
         states[trackIdx].cleanStreakCount = 0;
         states[trackIdx].cleanStreakStartTime = 0;
         states[trackIdx].cleanStreakOHLCSum = 0.0;
         states[trackIdx].anchorAbove = 0.0;
         states[trackIdx].anchorAboveTime = 0;
         states[trackIdx].anchorBelow = 0.0;
         states[trackIdx].anchorBelowTime = 0;
      }
      g_algoFamilyLevelStatsAtBar[trackIdx][barIdx].bounceCount_today = states[trackIdx].bounceCount_today;
      g_algoFamilyLevelStatsAtBar[trackIdx][barIdx].ceilingCount_today = states[trackIdx].ceilingCount_today;
      g_algoFamilyLevelStatsAtBar[trackIdx][barIdx].ceilingProximityCandles_today = states[trackIdx].ceilingProximityCandles_today;
      g_algoFamilyLevelStatsAtBar[trackIdx][barIdx].physicalContactCount_today = states[trackIdx].physicalContactCount_today;
      g_algoFamilyLevelStatsAtBar[trackIdx][barIdx].contactAndProximityCount_today = states[trackIdx].contactAndProximityCount_today;
      g_algoFamilyLevelStatsAtBar[trackIdx][barIdx].candlesPassedSinceLastBounce = states[trackIdx].candlesPassedSinceLastBounce;
      g_algoFamilyLevelStatsAtBar[trackIdx][barIdx].candlesPassedSinceLastCeiling = states[trackIdx].candlesPassedSinceLastCeiling;
      g_algoFamilyLevelStatsAtBar[trackIdx][barIdx].bounceCount_recent =
         AlgoFamilyCountEventTimesInLookbackMinutes(states[trackIdx].bounceEventTimes, states[trackIdx].bounceEventCount,
            barTime, AlgoFamilyRecentBounceLookbackMinutes());
      g_algoFamilyLevelStatsAtBar[trackIdx][barIdx].ceilingCount_recent =
         AlgoFamilyCountEventTimesInLookbackMinutes(states[trackIdx].ceilingEventTimes, states[trackIdx].ceilingEventCount,
            barTime, AlgoFamilyRecentCeilingLookbackMinutes());
      g_algoFamilyLevelStatsAtBar[trackIdx][barIdx].ceilingProximityCandles_recent =
         AlgoFamilyCountEventTimesInLookbackMinutes(states[trackIdx].ceilingProximityCandleTimes, states[trackIdx].ceilingProximityCandleCount,
            barTime, AlgoFamilyRecentCeilingLookbackMinutes());
      g_algoFamilyLevelStatsAtBar[trackIdx][barIdx].anchorAbove = states[trackIdx].anchorAbove;
      g_algoFamilyLevelStatsAtBar[trackIdx][barIdx].anchorBelow = states[trackIdx].anchorBelow;
      g_algoFamilyLevelStatsAtBar[trackIdx][barIdx].cleanStreakCount = states[trackIdx].cleanStreakCount;

      const int expandedIdx = g_weeklyAlgoFamilyTrackExpandedIdx[trackIdx];
      const string cLower = g_levelsExpanded[expandedIdx].categoriesLower;
      const double d = MathAbs(c - lvl);
      if(LevelEligibleForAlgoLevelScopeLower(cLower, true, false, barTime))
      {
         if(d < closestWeeklyDist) { closestWeeklyDist = d; closestWeeklyTrackIdx = trackIdx; }
      }
      if(LevelEligibleForAlgoLevelScopeLower(cLower, false, true, barTime))
      {
         if(d < closestDailyDist) { closestDailyDist = d; closestDailyTrackIdx = trackIdx; }
      }
   }

   const double candleAvg = (o + h + l + c) / 4.0;
   g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].currentCandle_AvgOf_OHLCnumbers = candleAvg;
   g_pullingHistoryAlgoFamilyDailyAtBar[barIdx].currentCandle_AvgOf_OHLCnumbers = candleAvg;
   if(closestWeeklyTrackIdx < 0)
      PullingHistoryAlgoFamilyClearClosestFields(g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx]);
   else
      PullingHistoryAlgoFamilyFillClosestFields(g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx],
         states[closestWeeklyTrackIdx], g_weeklyAlgoFamilyTrackExpandedIdx[closestWeeklyTrackIdx], h, l, barTime,
         g_algoFamilyLevelStatsAtBar[closestWeeklyTrackIdx][barIdx]);
   if(closestDailyTrackIdx < 0)
      PullingHistoryAlgoFamilyClearClosestFields(g_pullingHistoryAlgoFamilyDailyAtBar[barIdx]);
   else
      PullingHistoryAlgoFamilyFillClosestFields(g_pullingHistoryAlgoFamilyDailyAtBar[barIdx],
         states[closestDailyTrackIdx], g_weeklyAlgoFamilyTrackExpandedIdx[closestDailyTrackIdx], h, l, barTime,
         g_algoFamilyLevelStatsAtBar[closestDailyTrackIdx][barIdx]);
}

//+------------------------------------------------------------------+
//| Forward pass: per level day stats + per-bar closest-level snapshots (weekly + daily scopes). |
//| Live-safe mode: incremental closed bars + forming-bar scratch pass; full replay on integrity violations only. |
//+------------------------------------------------------------------+
void UpdatePullingHistoryAlgoFamilyPerBarStats()
{
   const bool profOn = BacktestProfileEnabled();
   ulong profT0 = 0;
   if(profOn)
      profT0 = GetMicrosecondCount();

   g_weeklyAlgoFamilyTrackCount = 0;
   for(int levelIdx = 0; levelIdx < g_levelsTodayCount && g_weeklyAlgoFamilyTrackCount < MAX_ALGOFAMILY_DAYSTART_WEEK_LEVELS; levelIdx++)
   {
      if(!AlgoFamilyLevelShouldTrackForDayStatsLocal(g_levelsExpanded[levelIdx].categories))
         continue;
      g_weeklyAlgoFamilyTrackExpandedIdx[g_weeklyAlgoFamilyTrackCount++] = levelIdx;
   }

   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_PULLINGHISTORY_TRACK_SETUP, profT0);

   if(g_m1DayStart == 0 || g_barsInDay <= 0)
   {
      g_pullingHistoryIncDayStart = 0;
      g_pullingHistoryIncLastBarIdx = -1;
      return;
   }

   const int lastClosedBarIdx = PullingHistoryLastClosedBarIdx();
   const bool needFullReplay = PullingHistoryNeedsFullReplay(lastClosedBarIdx);
   const int barEndInclusive = lastClosedBarIdx;

   if(barEndInclusive < 0)
   {
      if(M1BarCloseLiveSafeMode())
         PullingHistoryProcessFormingBarLive();
      PullingHistoryIncSaveTrackSnapshot();
      return;
   }

   int barStart = 0;
   if(needFullReplay)
   {
      PullingHistoryIncResetRunningStates();
      g_pullingHistoryIncDayStart = g_m1DayStart;
      barStart = 0;
   }
   else
      barStart = g_pullingHistoryIncLastBarIdx + 1;

   if(barStart <= barEndInclusive)
   {
      for(int barIdx = barStart; barIdx <= barEndInclusive; barIdx++)
      {
         int closestWeeklyTrackIdx = -1;
         int closestDailyTrackIdx = -1;
         if(profOn)
            profT0 = GetMicrosecondCount();
         PullingHistoryAlgoFamilyProcessOneBar(barIdx, g_pullingHistoryIncStates, closestWeeklyTrackIdx, closestDailyTrackIdx);
         if(profOn)
         {
            BacktestProfAccumulate(BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_PULLINGHISTORY_FORWARD_PASS, profT0);
            profT0 = GetMicrosecondCount();
            BacktestProfAccumulate(BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_PULLINGHISTORY_CLOSEST_SNAP, profT0);
         }
         PullingHistoryIncMarkBarSnapshot(barIdx);
      }
   }

   g_pullingHistoryIncLastBarIdx = lastClosedBarIdx;
   if(M1BarCloseLiveSafeMode())
      PullingHistoryProcessFormingBarLive();
   PullingHistoryIncSaveTrackSnapshot();
}

//+------------------------------------------------------------------+
//| Per-bar account + day trade stats for algo-family log (after UpdateDayProgress; uses g_tradeResults + g_dayProgress). |
//+------------------------------------------------------------------+
void UpdatePullingHistoryAlgoFamilyAccountBarStats()
{
   if(!M1BarCloseStatsBarRangeActive())
   {
      FalgoOverlayLiveDayStatsOnLastBar();
      return;
   }

   const int barStart = g_m1BarCloseStatsIncBarStart;
   const int barEndInclusive = g_m1BarCloseStatsIncBarEndInclusive;

   for(int barIdx = barStart; barIdx <= barEndInclusive; barIdx++)
   {
      datetime candleCloseTime;
      if(barIdx + 1 < g_barsInDay)
         candleCloseTime = g_m1Rates[barIdx + 1].time;
      else
         candleCloseTime = g_m1Rates[barIdx].time + 60;

      g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].dayWinRate = g_dayProgress[barIdx].dayWinRate;
      g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].dayTradesCount = g_dayProgress[barIdx].dayTradesCount;
      g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].dayPointsSum = g_dayProgress[barIdx].dayPointsSum;
      g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].dayProfitSum = g_dayProgress[barIdx].dayProfitSum;
      g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].dayProfitFactor = g_dayProgress[barIdx].dayProfitFactor;
      g_pullingHistoryAlgoFamilyDailyAtBar[barIdx].dayWinRate = g_dayProgress[barIdx].dayWinRate;
      g_pullingHistoryAlgoFamilyDailyAtBar[barIdx].dayTradesCount = g_dayProgress[barIdx].dayTradesCount;
      g_pullingHistoryAlgoFamilyDailyAtBar[barIdx].dayPointsSum = g_dayProgress[barIdx].dayPointsSum;
      g_pullingHistoryAlgoFamilyDailyAtBar[barIdx].dayProfitSum = g_dayProgress[barIdx].dayProfitSum;
      g_pullingHistoryAlgoFamilyDailyAtBar[barIdx].dayProfitFactor = g_dayProgress[barIdx].dayProfitFactor;

      bool openNow = false;
      datetime openTime = 0;
      datetime lastClosed = 0;
      for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
      {
         TradeResult tr = g_tradeResults[trIdx];
         if(tr.startTime >= candleCloseTime)
            continue;
         if(tr.foundOut && tr.endTime < candleCloseTime && tr.endTime > lastClosed)
            lastClosed = tr.endTime;
         bool stillOpen = (!tr.foundOut || tr.endTime >= candleCloseTime);
         if(stillOpen)
         {
            openNow = true;
            if(tr.startTime > openTime)
               openTime = tr.startTime;
         }
      }
      g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].accOpenTradeNowBool = openNow;
      g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].accOpenTradeTime = openNow ? openTime : 0;
      g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].accLastClosedTradeTime = lastClosed;
      g_pullingHistoryAlgoFamilyDailyAtBar[barIdx].accOpenTradeNowBool = openNow;
      g_pullingHistoryAlgoFamilyDailyAtBar[barIdx].accOpenTradeTime = openNow ? openTime : 0;
      g_pullingHistoryAlgoFamilyDailyAtBar[barIdx].accLastClosedTradeTime = lastClosed;
   }

   if(g_m1BarCloseStatsFormingBarIdx >= 0 && barEndInclusive >= 0)
   {
      const int formingIdx = g_m1BarCloseStatsFormingBarIdx;
      g_pullingHistoryAlgoFamilyWeeklyAtBar[formingIdx].dayWinRate = g_dayProgress[formingIdx].dayWinRate;
      g_pullingHistoryAlgoFamilyWeeklyAtBar[formingIdx].dayTradesCount = g_dayProgress[formingIdx].dayTradesCount;
      g_pullingHistoryAlgoFamilyWeeklyAtBar[formingIdx].dayPointsSum = g_dayProgress[formingIdx].dayPointsSum;
      g_pullingHistoryAlgoFamilyWeeklyAtBar[formingIdx].dayProfitSum = g_dayProgress[formingIdx].dayProfitSum;
      g_pullingHistoryAlgoFamilyWeeklyAtBar[formingIdx].dayProfitFactor = g_dayProgress[formingIdx].dayProfitFactor;
      g_pullingHistoryAlgoFamilyDailyAtBar[formingIdx].dayWinRate = g_dayProgress[formingIdx].dayWinRate;
      g_pullingHistoryAlgoFamilyDailyAtBar[formingIdx].dayTradesCount = g_dayProgress[formingIdx].dayTradesCount;
      g_pullingHistoryAlgoFamilyDailyAtBar[formingIdx].dayPointsSum = g_dayProgress[formingIdx].dayPointsSum;
      g_pullingHistoryAlgoFamilyDailyAtBar[formingIdx].dayProfitSum = g_dayProgress[formingIdx].dayProfitSum;
      g_pullingHistoryAlgoFamilyDailyAtBar[formingIdx].dayProfitFactor = g_dayProgress[formingIdx].dayProfitFactor;
   }
   FalgoOverlayLiveDayStatsOnLastBar();
}

//+------------------------------------------------------------------+
//| For a given level and bar index: count consecutive bars (barIndex-1, barIndex-2, ...) with all OHLC above or below level. |
//| above=true: all OHLC > level. above=false: all OHLC < level. If current candle cuts the level, streak is 0. |
//+------------------------------------------------------------------+
int GetCleanStreakForLevel(double level, int barIndex, bool above)
{
   int streak = 0;
   for(int barIdx = barIndex - 1; barIdx >= 0; barIdx--)
   {
      bool clean = above
         ? (g_m1Rates[barIdx].open > level && g_m1Rates[barIdx].high > level && g_m1Rates[barIdx].low > level && g_m1Rates[barIdx].close > level)
         : (g_m1Rates[barIdx].open < level && g_m1Rates[barIdx].high < level && g_m1Rates[barIdx].low < level && g_m1Rates[barIdx].close < level);
      if(clean)
         streak++;
      else
         break;
   }
   return streak;
}

//+------------------------------------------------------------------+
//| Count bars in [fromBar, toBar] (inclusive) where all OHLC is above (above=true) or below (above=false) level. |
//+------------------------------------------------------------------+
int CountCleanBarsInRange(double level, int fromBar, int toBar, bool above)
{
   int count = 0;
   for(int barIdx = fromBar; barIdx <= toBar; barIdx++)
   {
      bool clean = above
         ? (g_m1Rates[barIdx].open > level && g_m1Rates[barIdx].high > level && g_m1Rates[barIdx].low > level && g_m1Rates[barIdx].close > level)
         : (g_m1Rates[barIdx].open < level && g_m1Rates[barIdx].high < level && g_m1Rates[barIdx].low < level && g_m1Rates[barIdx].close < level);
      if(clean) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Count consecutive bars (barIndex-1, barIndex-2, ...) with level between bar H and L (low <= level <= high). |
//+------------------------------------------------------------------+
int GetOverlapStreakForLevel(double level, int barIndex)
{
   int streak = 0;
   for(int barIdx = barIndex - 1; barIdx >= 0; barIdx--)
   {
      if(g_m1Rates[barIdx].low <= level && level <= g_m1Rates[barIdx].high)
         streak++;
      else
         break;
   }
   return streak;
}

//+------------------------------------------------------------------+
//| Count bars in [fromBar, toBar] (inclusive) where level is between bar H and L. |
//+------------------------------------------------------------------+
int CountOverlapBarsInRange(double level, int fromBar, int toBar)
{
   int count = 0;
   for(int barIdx = fromBar; barIdx <= toBar; barIdx++)
      if(g_m1Rates[barIdx].low <= level && level <= g_m1Rates[barIdx].high) count++;
   return count;
}

//+------------------------------------------------------------------+
//| Pull 1M for current day into g_m1Rates and build g_levelsExpanded. Call every new bar so data is always in memory. |
//+------------------------------------------------------------------+
void BuyHoldBenchmarkUpdate(const bool forceFinalWrite = false);
void BuyHoldBenchmarkResetOnInit();
void BuyHoldBenchmarkOnDayRollover();
void RebuildSortedLevelPricesForToday();
int SortedLevelFirstAboveIdx(const double high);
int SortedLevelLastBelowIdx(const double low);
void PullingHistoryPsLogCloseHandles();

void UpdateDayM1AndLevelsExpanded()
{
   const bool profOn = BacktestProfileEnabled();
   ulong profT0 = 0;

   datetime dayStart = g_lastTimer1Time - (g_lastTimer1Time % 86400);
   string dateStr = TimeToString(dayStart, TIME_DATE);  // YYYY.MM.DD (MT5 default)
   string dayKey = dateStr;  // levels stored as YYYY.MM.DD

   // On new day: reload levels for this day only (by time range); close level log handles before rebuild
   if(dateStr != g_levelsLoadedForDate)
   {
      BuyHoldBenchmarkOnDayRollover();
      if(profOn)
         profT0 = GetMicrosecondCount();
      for(int i = 0; i < ArraySize(levels); i++)
         if(levels[i].logRawEv_fileHandle != INVALID_HANDLE)
            { FileClose(levels[i].logRawEv_fileHandle); levels[i].logRawEv_fileHandle = INVALID_HANDLE; }
      if(!LoadLevelsForDate(dateStr))
         return;  // file open failed; keep previous levels
      g_levelsLoadedForDate = dateStr;
      BuildLevelsFromCSV();
      RefreshAlgoFamilyDayStartWeekPerspective(g_lastTimer1Time);
      dayStat_spreadHighestSeen = 0.0;  // reset for new day
      dayStat_spreadLowestSeen = 0.0;
      for(int bsi = 0; bsi < BREAKDOWN_ALGO_REGISTRY_MAX; bsi++)
      {
         g_breakdownAlgoLastPlacedEndTime[bsi] = 0;
         g_breakdownAlgoLastPlacedStartHigh[bsi] = 0.0;
         g_breakdownAlgoLastPlacedBreakdownLow[bsi] = 0.0;
      }
      ZeroMemory(g_breakdown15mSnap);
      g_breakdown15mSnapByAlgoAsOf = 0;
      for(int bdci = 0; bdci < BREAKDOWN_ALGO_REGISTRY_MAX; bdci++)
         g_breakdown15mSnapByAlgoSlotReady[bdci] = false;
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_NEW_DAY, profT0);
   }

   MqlDateTime mtDay;
   TimeToStruct(dayStart, mtDay);

   if(profOn)
      profT0 = GetMicrosecondCount();
   MqlRates m1Rates[];
   int barsFromDayStart = iBarShift(_Symbol, PERIOD_M1, dayStart, false);
   if(barsFromDayStart < 0) { g_barsInDay = 0; g_m1DayStart = 0; if(profOn) BacktestProfAccumulate(BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_COPY_RATES, profT0); return; }

   int countToCopy = barsFromDayStart + 1;
   int copied = CopyRates(_Symbol, PERIOD_M1, 0, countToCopy, m1Rates);
   if(copied <= 0) { g_barsInDay = 0; g_m1DayStart = 0; if(profOn) BacktestProfAccumulate(BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_COPY_RATES, profT0); return; }

   int barsInDay = 0;
   for(int barIdx = 0; barIdx < copied; barIdx++)
      if(TimeToString(m1Rates[barIdx].time, TIME_DATE) == dateStr) barsInDay++;

   if(barsInDay <= 0 || barsInDay > MAX_BARS_IN_DAY) { g_barsInDay = 0; g_m1DayStart = 0; if(profOn) BacktestProfAccumulate(BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_COPY_RATES, profT0); return; }

   int idxDay = 0;
   for(int barIdx = 0; barIdx < copied && idxDay < barsInDay; barIdx++)
   {
      if(TimeToString(m1Rates[barIdx].time, TIME_DATE) != dateStr) continue;
      g_m1Rates[idxDay] = m1Rates[barIdx];
      idxDay++;
   }
   g_barsInDay = barsInDay;
   g_m1DayStart = dayStart;
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_COPY_RATES, profT0);

   if(profOn)
      profT0 = GetMicrosecondCount();
   // No cash-style RTH open on calendar Sunday; resolving it can fatal (sparse M1 vs 14:30 desync target).
   if(IsCalendarDaySunday(dayStart))
      g_todayRTHopenValid = false;
   else
   {
      // Ensure todayRTHopen is in g_levels when we have the RTH open bar (14:30 on desync dates, else 15:30). Use globals as single source for level and pullinghistory.
      AssignTodayRTHopenFromM1Rates(dateStr);
      TryAddTodayRTHopenLevel(dateStr);
   }

   TryAddPDrthCloseLevel(dateStr);
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_RTH_PDC, profT0);

   if(profOn)
      profT0 = GetMicrosecondCount();
   // Build levelsExpanded from g_levels (full-day bars; todayRTHopen is in g_levels like any other level)
   g_levelsTodayCount = 0;
   for(int levelIdx = 0; levelIdx < g_levelsTotalCount; levelIdx++)
   {
      if(g_levels[levelIdx].startStr > dayKey || dayKey > g_levels[levelIdx].endStr) continue;
      if(g_levelsTodayCount >= MAX_LEVELS_EXPANDED)
         FatalError("UpdateDayM1AndLevelsExpanded: too many expanded levels for " + dayKey + " (max " + IntegerToString(MAX_LEVELS_EXPANDED) + ")");
      g_levelsExpanded[g_levelsTodayCount].levelPrice = g_levels[levelIdx].levelPrice;
      g_levelsExpanded[g_levelsTodayCount].tag        = g_levels[levelIdx].tag;
      g_levelsExpanded[g_levelsTodayCount].categories = g_levels[levelIdx].categories;
      g_levelsExpanded[g_levelsTodayCount].categoriesLower = g_levels[levelIdx].categories;
      StringToLower(g_levelsExpanded[g_levelsTodayCount].categoriesLower);
      g_levelsExpanded[g_levelsTodayCount].count      = g_barsInDay;
      ArrayResize(g_levelsExpanded[g_levelsTodayCount].diffs, g_barsInDay);
      ArrayResize(g_levelsExpanded[g_levelsTodayCount].times, g_barsInDay);
      for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
      {
         g_levelsExpanded[g_levelsTodayCount].times[barIdx] = g_m1Rates[barIdx].time;
         g_levelsExpanded[g_levelsTodayCount].diffs[barIdx] = g_m1Rates[barIdx].close - g_levelsExpanded[g_levelsTodayCount].levelPrice;
      }
      g_levelsTodayCount++;
   }
   RebuildSortedLevelPricesForToday();
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_EXPAND_DIFFS, profT0);

   if(profOn)
      profT0 = GetMicrosecondCount();
   // Per (level levelIdx, bar barIdx): breaksLevelDown / breaksLevelUpward from candle open/close vs level
   for(int levelIdx = 0; levelIdx < g_levelsTodayCount; levelIdx++)
      for(int barIdx = 0; barIdx < g_levelsExpanded[levelIdx].count; barIdx++)
      {
         double levelPrice = g_levelsExpanded[levelIdx].levelPrice;
         g_breaksLevelDown[levelIdx][barIdx]   = (g_m1Rates[barIdx].open > levelPrice && g_m1Rates[barIdx].close < levelPrice);
         g_breaksLevelUpward[levelIdx][barIdx] = (g_m1Rates[barIdx].open < levelPrice && g_m1Rates[barIdx].close > levelPrice);
      }
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_BREAKS, profT0);

   if(profOn)
      profT0 = GetMicrosecondCount();
   // Per (level levelIdx, bar barIdx): all level-bar stats in one forward pass (streaks and counts incremental to avoid O(bars^2))
   for(int levelIdx = 0; levelIdx < g_levelsTodayCount; levelIdx++)
   {
      double levelPrice = g_levelsExpanded[levelIdx].levelPrice;
      int barCount = g_levelsExpanded[levelIdx].count;
      int prevAbove = 0, prevBelow = 0, prevOverlap = 0;  // bar barIdx-1 state
      int runAbove = 0, runBelow = 0, runOverlap = 0;     // running streaks
      int sumAbove = 0, sumBelow = 0, sumOverlap = 0;     // running counts 0..barIdx
      for(int barIdx = 0; barIdx < barCount; barIdx++)
      {
         double open_ = g_m1Rates[barIdx].open, high_ = g_m1Rates[barIdx].high, low_ = g_m1Rates[barIdx].low, close_ = g_m1Rates[barIdx].close;
         int curAbove  = IsBarCleanAbove(open_, high_, low_, close_, levelPrice) ? 1 : 0;
         int curBelow  = IsBarCleanBelow(open_, high_, low_, close_, levelPrice) ? 1 : 0;
         int curOverlap = IsBarOverlap(low_, high_, levelPrice) ? 1 : 0;

         int streakAbove, streakBelow, streakOverlap;
         if(barIdx == 0) { streakAbove = 0; streakBelow = 0; streakOverlap = 0; }
         else
         {
            streakAbove  = prevAbove  ? 1 + runAbove  : 0;
            streakBelow  = prevBelow  ? 1 + runBelow  : 0;
            streakOverlap = prevOverlap ? 1 + runOverlap : 0;
         }
         g_cleanStreakAbove[levelIdx][barIdx] = streakAbove;
         g_cleanStreakBelow[levelIdx][barIdx] = streakBelow;
         g_overlapStreak[levelIdx][barIdx]    = streakOverlap;

         sumAbove += curAbove; sumBelow += curBelow; sumOverlap += curOverlap;
         g_aboveCnt[levelIdx][barIdx] = sumAbove;
         g_belowCnt[levelIdx][barIdx] = sumBelow;
         g_overlapC[levelIdx][barIdx] = sumOverlap;

         int totalSoFar = barIdx + 1;
         g_abovePerc[levelIdx][barIdx] = (totalSoFar > 0) ? (100.0 * sumAbove / totalSoFar) : 0.0;
         g_belowPerc[levelIdx][barIdx] = (totalSoFar > 0) ? (100.0 * sumBelow / totalSoFar) : 0.0;
         g_overlapPc[levelIdx][barIdx] = (totalSoFar > 0) ? (100.0 * sumOverlap / totalSoFar) : 0.0;

         runAbove   = curAbove  ? 1 + runAbove   : 0;
         runBelow   = curBelow  ? 1 + runBelow   : 0;
         runOverlap = curOverlap ? 1 + runOverlap : 0;
         prevAbove = curAbove; prevBelow = curBelow; prevOverlap = curOverlap;
      }
   }
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_STREAKS, profT0);

   if(profOn)
      profT0 = GetMicrosecondCount();
   // Per-bar: level above candle high, level below candle low, session (sorted levels + binary search; incremental on new bars).
   int aboveBelowBarStart = 0;
   if(g_aboveBelowIncDayStart == g_m1DayStart && g_aboveBelowIncLevelCount == g_levelsTodayCount && g_barsInDay > 0)
   {
      if(g_barsInDay > g_aboveBelowIncBarsDone)
         aboveBelowBarStart = g_aboveBelowIncBarsDone;
      else if(g_barsInDay == g_aboveBelowIncBarsDone)
         aboveBelowBarStart = g_barsInDay - 1;
   }
   else
   {
      g_aboveBelowIncDayStart = g_m1DayStart;
      g_aboveBelowIncLevelCount = g_levelsTodayCount;
      aboveBelowBarStart = 0;
   }
   for(int barIdx = aboveBelowBarStart; barIdx < g_barsInDay; barIdx++)
   {
      const double barHigh = g_m1Rates[barIdx].high;
      const double barLow = g_m1Rates[barIdx].low;
      double aboveH = 0.0;
      double belowL = 0.0;
      const int aboveIdx = SortedLevelFirstAboveIdx(barHigh);
      if(aboveIdx >= 0)
         aboveH = g_sortedLevelPrices[aboveIdx];
      const int belowIdx = SortedLevelLastBelowIdx(barLow);
      if(belowIdx >= 0)
         belowL = g_sortedLevelPrices[belowIdx];
      g_levelAboveH[barIdx] = aboveH;
      g_levelBelowL[barIdx] = belowL;
      g_session[barIdx] = GetSessionForCandleTime(g_m1Rates[barIdx].time);
   }
   g_aboveBelowIncBarsDone = g_barsInDay;
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_UPDATE_DAY_M1_LEVELS_ABOVE_BELOW, profT0);

   UpdatePullingHistoryAlgoFamilyPerBarStats();
   BuyHoldBenchmarkUpdate();
}

//+------------------------------------------------------------------+
void RebuildSortedLevelPricesForToday()
{
   const int prevLevelCount = g_sortedLevelPriceCount;
   g_sortedLevelPriceCount = g_levelsTodayCount;
   double tmp[];
   ArrayResize(tmp, g_levelsTodayCount);
   for(int i = 0; i < g_levelsTodayCount; i++)
      tmp[i] = g_levelsExpanded[i].levelPrice;
   if(g_sortedLevelPriceCount > 1)
      ArraySort(tmp);
   for(int i = 0; i < g_levelsTodayCount; i++)
      g_sortedLevelPrices[i] = tmp[i];
   if(g_sortedLevelPriceCount != prevLevelCount)
      g_aboveBelowIncLevelCount = -1;
}

//+------------------------------------------------------------------+
int SortedLevelFirstAboveIdx(const double high)
{
   if(g_sortedLevelPriceCount <= 0)
      return -1;
   int lo = 0;
   int hi = g_sortedLevelPriceCount;
   while(lo < hi)
   {
      const int mid = (lo + hi) / 2;
      if(g_sortedLevelPrices[mid] <= high)
         lo = mid + 1;
      else
         hi = mid;
   }
   if(lo >= g_sortedLevelPriceCount)
      return -1;
   return lo;
}

//+------------------------------------------------------------------+
int SortedLevelLastBelowIdx(const double low)
{
   if(g_sortedLevelPriceCount <= 0)
      return -1;
   int lo = 0;
   int hi = g_sortedLevelPriceCount;
   while(lo < hi)
   {
      const int mid = (lo + hi) / 2;
      if(g_sortedLevelPrices[mid] < low)
         lo = mid + 1;
      else
         hi = mid;
   }
   if(lo <= 0)
      return -1;
   return lo - 1;
}

//+------------------------------------------------------------------+
string BuyHoldBenchmarkFileName()
{
   return "benchmark_buyAndHold.csv";
}

//+------------------------------------------------------------------+
void BuyHoldBenchmarkResetOnInit()
{
   g_buyHoldFirstDayStart = 0;
   g_buyHoldCompletedTradingMinutes = 0.0;
   g_buyHoldSnapshotM1BarCount = 0;
   g_buyHoldFirstOOD = 0.0;
   g_buyHoldFirstHOD = 0.0;
   g_buyHoldFirstLOD = 0.0;
   g_buyHoldFirstCOD = 0.0;
   g_buyHoldFirstDayFrozen = false;
   g_buyHoldRunMaxHigh = 0.0;
   g_buyHoldRunMinLow = 0.0;
   g_buyHoldRunExtremesInit = false;
   g_buyHoldSnapshotDayStart = 0;
   g_buyHoldSnapshotOOD = 0.0;
   g_buyHoldSnapshotHOD = 0.0;
   g_buyHoldSnapshotLOD = 0.0;
   g_buyHoldSnapshotCOD = 0.0;
   g_buyHoldSnapshotValid = false;
   g_buyHoldDayOhlcDayStart = 0;
   g_buyHoldDayOhlcBarsDone = 0;
   g_buyHoldDayCachedOOD = 0.0;
   g_buyHoldDayCachedHOD = 0.0;
   g_buyHoldDayCachedLOD = 0.0;
   g_aboveBelowIncDayStart = 0;
   g_aboveBelowIncLevelCount = 0;
   g_aboveBelowIncBarsDone = 0;
   g_sortedLevelPriceCount = 0;
   PullingHistoryPsLogCloseHandles();

   if(!finalLog_benchmark_buyAndHold)
      return;
   int fh = FileOpen(BuyHoldBenchmarkFileName(), FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   FileWrite(fh, "row", "date", "OOD", "HOD", "LOD", "COD", "buy_hold_pnl_firstOpen_lastClose",
      "max_high_since_first_ood", "min_low_since_first_ood",
      "sum_lifetime_hours", "sum_lifetime_days", "hours_vs_pricediff_ratio");
   FileClose(fh);
}

//+------------------------------------------------------------------+
double BuyHoldSpanTradingMinutes()
{
   return g_buyHoldCompletedTradingMinutes + (double)g_buyHoldSnapshotM1BarCount;
}

//+------------------------------------------------------------------+
bool BuyHoldDayOhlcFromM1(double &ood, double &hod, double &lod, double &cod)
{
   if(g_barsInDay <= 0 || g_m1DayStart == 0)
      return false;

   if(g_m1DayStart != g_buyHoldDayOhlcDayStart || g_buyHoldDayOhlcBarsDone <= 0)
   {
      g_buyHoldDayCachedOOD = g_m1Rates[0].open;
      g_buyHoldDayCachedHOD = g_m1Rates[0].high;
      g_buyHoldDayCachedLOD = g_m1Rates[0].low;
      for(int barIdx = 1; barIdx < g_barsInDay; barIdx++)
      {
         g_buyHoldDayCachedHOD = MathMax(g_buyHoldDayCachedHOD, g_m1Rates[barIdx].high);
         g_buyHoldDayCachedLOD = MathMin(g_buyHoldDayCachedLOD, g_m1Rates[barIdx].low);
      }
      g_buyHoldDayOhlcDayStart = g_m1DayStart;
      g_buyHoldDayOhlcBarsDone = g_barsInDay;
   }
   else if(g_barsInDay > g_buyHoldDayOhlcBarsDone)
   {
      for(int barIdx = g_buyHoldDayOhlcBarsDone; barIdx < g_barsInDay; barIdx++)
      {
         g_buyHoldDayCachedHOD = MathMax(g_buyHoldDayCachedHOD, g_m1Rates[barIdx].high);
         g_buyHoldDayCachedLOD = MathMin(g_buyHoldDayCachedLOD, g_m1Rates[barIdx].low);
      }
      g_buyHoldDayOhlcBarsDone = g_barsInDay;
   }

   ood = g_buyHoldDayCachedOOD;
   hod = g_buyHoldDayCachedHOD;
   lod = g_buyHoldDayCachedLOD;
   int codIdx = PullingHistoryLastClosedBarIdx();
   if(codIdx < 0)
      codIdx = g_barsInDay - 1;
   cod = g_m1Rates[codIdx].close;
   return true;
}

//+------------------------------------------------------------------+
void BuyHoldBenchmarkWriteFile(const datetime lastDayStart, const double lastOOD, const double lastHOD,
   const double lastLOD, const double lastCOD)
{
   if(!finalLog_benchmark_buyAndHold || g_buyHoldFirstDayStart == 0)
      return;

   const double oodDiff = lastOOD - g_buyHoldFirstOOD;
   const double hodDiff = lastHOD - g_buyHoldFirstHOD;
   const double lodDiff = lastLOD - g_buyHoldFirstLOD;
   const double codDiff = lastCOD - g_buyHoldFirstCOD;
   const double buyHoldPnl = lastCOD - g_buyHoldFirstOOD;
   const double maxHighSinceFirst = g_buyHoldRunExtremesInit ? (g_buyHoldRunMaxHigh - g_buyHoldFirstOOD) : 0.0;
   const double minLowSinceFirst = g_buyHoldRunExtremesInit ? (g_buyHoldRunMinLow - g_buyHoldFirstOOD) : 0.0;
   const double spanMinutes = BuyHoldSpanTradingMinutes();
   const double sumLifetimeHours = spanMinutes / 60.0;
   const double sumLifetimeDays = sumLifetimeHours / 24.0;
   const string hoursVsPricediffRatio = (MathAbs(buyHoldPnl) > 0.0)
      ? DoubleToString(sumLifetimeHours / buyHoldPnl, 4) : "";

   int fh = FileOpen(BuyHoldBenchmarkFileName(), FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   FileWrite(fh, "row", "date", "OOD", "HOD", "LOD", "COD", "buy_hold_pnl_firstOpen_lastClose",
      "max_high_since_first_ood", "min_low_since_first_ood",
      "sum_lifetime_hours", "sum_lifetime_days", "hours_vs_pricediff_ratio");
   FileWrite(fh, "first_day",
      TimeToString(g_buyHoldFirstDayStart, TIME_DATE),
      DoubleToString(g_buyHoldFirstOOD, _Digits),
      DoubleToString(g_buyHoldFirstHOD, _Digits),
      DoubleToString(g_buyHoldFirstLOD, _Digits),
      DoubleToString(g_buyHoldFirstCOD, _Digits),
      "", "", "", "", "", "");
   FileWrite(fh, "last_day",
      TimeToString(lastDayStart, TIME_DATE),
      DoubleToString(lastOOD, _Digits),
      DoubleToString(lastHOD, _Digits),
      DoubleToString(lastLOD, _Digits),
      DoubleToString(lastCOD, _Digits),
      "", "", "", "", "", "");
   FileWrite(fh, "diff", "",
      DoubleToString(oodDiff, _Digits),
      DoubleToString(hodDiff, _Digits),
      DoubleToString(lodDiff, _Digits),
      DoubleToString(codDiff, _Digits),
      DoubleToString(buyHoldPnl, _Digits),
      DoubleToString(maxHighSinceFirst, _Digits),
      DoubleToString(minLowSinceFirst, _Digits),
      DoubleToString(sumLifetimeHours, 1),
      DoubleToString(sumLifetimeDays, 1),
      hoursVsPricediffRatio);
   FileClose(fh);
}

//+------------------------------------------------------------------+
void BuyHoldBenchmarkOnDayRollover()
{
   if(!finalLog_benchmark_buyAndHold || !g_buyHoldSnapshotValid || g_buyHoldFirstDayStart == 0)
      return;
   if(!g_buyHoldFirstDayFrozen)
      g_buyHoldFirstDayFrozen = true;
   BuyHoldBenchmarkWriteFile(g_buyHoldSnapshotDayStart, g_buyHoldSnapshotOOD, g_buyHoldSnapshotHOD,
      g_buyHoldSnapshotLOD, g_buyHoldSnapshotCOD);
   if(g_buyHoldSnapshotM1BarCount > 0)
      g_buyHoldCompletedTradingMinutes += (double)g_buyHoldSnapshotM1BarCount;
}

//+------------------------------------------------------------------+
void BuyHoldBenchmarkUpdate(const bool forceFinalWrite)
{
   if(!finalLog_benchmark_buyAndHold || g_m1DayStart == 0)
      return;

   const bool profOn = BacktestProfileEnabled();
   ulong profT0 = 0;
   if(profOn)
      profT0 = GetMicrosecondCount();

   double dayOOD = 0.0, dayHOD = 0.0, dayLOD = 0.0, dayCOD = 0.0;
   if(!BuyHoldDayOhlcFromM1(dayOOD, dayHOD, dayLOD, dayCOD))
   {
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_BENCHMARK_BUY_HOLD, profT0);
      return;
   }

   int codBarIdx = PullingHistoryLastClosedBarIdx();
   if(codBarIdx < 0)
      codBarIdx = g_barsInDay - 1;
   g_buyHoldSnapshotM1BarCount = (codBarIdx >= 0 ? codBarIdx + 1 : 0);

   if(g_buyHoldFirstDayStart == 0)
   {
      g_buyHoldFirstDayStart = g_m1DayStart;
      g_buyHoldFirstOOD = dayOOD;
      g_buyHoldFirstHOD = dayHOD;
      g_buyHoldFirstLOD = dayLOD;
      g_buyHoldFirstCOD = dayCOD;
      g_buyHoldRunMaxHigh = dayHOD;
      g_buyHoldRunMinLow = dayLOD;
      g_buyHoldRunExtremesInit = true;
      g_buyHoldSnapshotDayStart = g_m1DayStart;
      g_buyHoldSnapshotOOD = dayOOD;
      g_buyHoldSnapshotHOD = dayHOD;
      g_buyHoldSnapshotLOD = dayLOD;
      g_buyHoldSnapshotCOD = dayCOD;
      g_buyHoldSnapshotValid = true;
      if(forceFinalWrite)
         BuyHoldBenchmarkWriteFile(g_m1DayStart, dayOOD, dayHOD, dayLOD, dayCOD);
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_BENCHMARK_BUY_HOLD, profT0);
      return;
   }

   if(!g_buyHoldFirstDayFrozen)
   {
      if(g_m1DayStart == g_buyHoldFirstDayStart)
      {
         g_buyHoldFirstOOD = dayOOD;
         g_buyHoldFirstHOD = dayHOD;
         g_buyHoldFirstLOD = dayLOD;
         g_buyHoldFirstCOD = dayCOD;
         g_buyHoldRunMaxHigh = MathMax(g_buyHoldRunMaxHigh, dayHOD);
         g_buyHoldRunMinLow = MathMin(g_buyHoldRunMinLow, dayLOD);
         g_buyHoldSnapshotDayStart = g_m1DayStart;
         g_buyHoldSnapshotOOD = dayOOD;
         g_buyHoldSnapshotHOD = dayHOD;
         g_buyHoldSnapshotLOD = dayLOD;
         g_buyHoldSnapshotCOD = dayCOD;
         g_buyHoldSnapshotValid = true;
         if(forceFinalWrite)
            BuyHoldBenchmarkWriteFile(g_m1DayStart, dayOOD, dayHOD, dayLOD, dayCOD);
         if(profOn)
            BacktestProfAccumulate(BACKTEST_PROF_BENCHMARK_BUY_HOLD, profT0);
         return;
      }
      g_buyHoldFirstDayFrozen = true;
   }

   g_buyHoldRunMaxHigh = MathMax(g_buyHoldRunMaxHigh, dayHOD);
   g_buyHoldRunMinLow = MathMin(g_buyHoldRunMinLow, dayLOD);
   g_buyHoldSnapshotDayStart = g_m1DayStart;
   g_buyHoldSnapshotOOD = dayOOD;
   g_buyHoldSnapshotHOD = dayHOD;
   g_buyHoldSnapshotLOD = dayLOD;
   g_buyHoldSnapshotCOD = dayCOD;
   g_buyHoldSnapshotValid = true;

   if(forceFinalWrite)
      BuyHoldBenchmarkWriteFile(g_m1DayStart, dayOOD, dayHOD, dayLOD, dayCOD);
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_BENCHMARK_BUY_HOLD, profT0);
}

//+------------------------------------------------------------------+
//| Build combined entry|exit comment string; no duplication.         |
//+------------------------------------------------------------------+
string BuildBothComments(const string &entryComment, const string &outComment, bool foundOut)
{
   if(foundOut)
      return entryComment + "| " + outComment;
   return entryComment + "| NOT_FOUND";
}

//+------------------------------------------------------------------+
//| EA order comment sentinel: leading '$' marks BuildUnifiedOrderComment format so UpdateTradeResultsForDay |
//| can split level/tp/sl (first 3 tokens after '$' removed). Level is full price; tp/sl/entry use mod-100 tails. Magic on DEAL_MAGIC / ORDER_MAGIC. Length validated vs MT5_ORDER_COMMENT_MAX_LEN. |
//+------------------------------------------------------------------+
int ChangeBothCommentsToArrayOfStrings(const string &bothComments, string &result[])
{
   if(StringFind(bothComments, "$") < 0) return 0;
   string commentStr = bothComments;
   StringReplace(commentStr, "$", "");
   return StringSplit(commentStr, ' ', result);
}

double Loghelper_MergeLevelWithTpSl(double level, double tpOrSl)
{
   int levelInt = (int)level;
   double levelFrac = level - levelInt;

   int tpInt = (int)tpOrSl;
   double tpFrac = tpOrSl - tpInt;

   int prefix = levelInt / 100;
   int newInt = prefix * 100 + tpInt;

   return newInt + tpFrac;
}

void Loghelper_FillLevelTpSlFromBothComments(const string &bothComments, string &outLevel, string &outTp, string &outSl)
{
   if(StringFind(bothComments, "$") < 0)
   {
      outLevel = outTp = outSl = "";
      return;
   }
   string arr[];
   ChangeBothCommentsToArrayOfStrings(bothComments, arr);
   outLevel = (ArraySize(arr) > 0) ? arr[0] : "";
   outTp    = (ArraySize(arr) > 1) ? arr[1] : "";
   outSl    = (ArraySize(arr) > 2) ? arr[2] : "";

   if(StringLen(outLevel) >= 2)
   {
      double levelVal = StringToDouble(outLevel);
      if(outTp != "") outTp = DoubleToString(Loghelper_MergeLevelWithTpSl(levelVal, StringToDouble(outTp)), 1);
      if(outSl != "") outSl = DoubleToString(Loghelper_MergeLevelWithTpSl(levelVal, StringToDouble(outSl)), 1);
   }
}

//+------------------------------------------------------------------+
//| Sort g_dealOrder[0..g_dealCount-1] by deal magic asc, then time asc (O(n log n)). |
//+------------------------------------------------------------------+
void MergeSortDealOrder()
{
   int n = g_dealCount;
   for(int i = 0; i < n; i++)
      g_dealOrder[i] = i;
   if(n <= 1)
      return;
   int w = 1;
   while(w < n)
   {
      for(int i0 = 0; i0 < n; i0 += 2 * w)
      {
         int m = MathMin(i0 + w, n);
         int i1 = MathMin(i0 + 2 * w, n);
         int p = i0, q = m, o = i0;
         while(p < m && q < i1)
         {
            int ap = g_dealOrder[p], aq = g_dealOrder[q];
            bool takeP = (g_dealMagic[ap] < g_dealMagic[aq]) ||
                         (g_dealMagic[ap] == g_dealMagic[aq] && g_dealTime[ap] <= g_dealTime[aq]);
            if(takeP)
               g_dealOrderTmp[o++] = g_dealOrder[p++];
            else
               g_dealOrderTmp[o++] = g_dealOrder[q++];
         }
         while(p < m)
            g_dealOrderTmp[o++] = g_dealOrder[p++];
         while(q < i1)
            g_dealOrderTmp[o++] = g_dealOrder[q++];
      }
      ArrayCopy(g_dealOrder, g_dealOrderTmp, 0, 0, n);
      w *= 2;
   }
}

//+------------------------------------------------------------------+
//| Sort indices[] by g_tradeResults[idx].startTime ascending (O(n log n)); used for EOD CSV ordering. |
//+------------------------------------------------------------------+
void SortIndicesByTradeStartAsc(int &indices[])
{
   int n = ArraySize(indices);
   if(n <= 1)
      return;
   int tmp[];
   ArrayResize(tmp, n);
   int w = 1;
   while(w < n)
   {
      for(int i0 = 0; i0 < n; i0 += 2 * w)
      {
         int m = MathMin(i0 + w, n);
         int i1 = MathMin(i0 + 2 * w, n);
         int p = i0, q = m, o = i0;
         while(p < m && q < i1)
         {
            int ap = indices[p], aq = indices[q];
            bool takeP = (g_tradeResults[ap].startTime <= g_tradeResults[aq].startTime);
            if(takeP)
               tmp[o++] = indices[p++];
            else
               tmp[o++] = indices[q++];
         }
         while(p < m)
            tmp[o++] = indices[p++];
         while(q < i1)
            tmp[o++] = indices[q++];
      }
      ArrayCopy(indices, tmp, 0, 0, n);
      w *= 2;
   }
}

//+------------------------------------------------------------------+
//| Pending created time from entry deal → DEAL_ORDER → ORDER_TIME_SETUP. FatalError if missing. |
//+------------------------------------------------------------------+
datetime FalgoSentTimeFromInDeal(const ulong inDealTicket)
{
   const ulong orderTicket = HistoryDealGetInteger(inDealTicket, DEAL_ORDER);
   if(orderTicket == 0)
      FatalError(StringFormat("FalgoSentTimeFromInDeal: DEAL_ORDER missing for deal %I64u", inDealTicket));
   if(!HistoryOrderSelect(orderTicket))
      FatalError(StringFormat("FalgoSentTimeFromInDeal: HistoryOrderSelect failed order %I64u deal %I64u", orderTicket, inDealTicket));
   const datetime setup = (datetime)HistoryOrderGetInteger(orderTicket, ORDER_TIME_SETUP);
   if(setup <= 0)
      FatalError(StringFormat("FalgoSentTimeFromInDeal: ORDER_TIME_SETUP missing order %I64u deal %I64u", orderTicket, inDealTicket));
   return setup;
}

//+------------------------------------------------------------------+
//| Load deals for [dayStart, dayStart+86400), pair IN/OUT into g_tradeResults. |
//+------------------------------------------------------------------+
void UpdateTradeResultsForDayStart(const datetime dayStart)
{
   g_tradeResultsCount = 0;
   g_dealCount = 0;
   datetime dayEnd = dayStart + 86400;
   if(!HistorySelect(dayStart, dayEnd)) return;
   int total = HistoryDealsTotal();
   for(int dealIdx = 0; dealIdx < total && g_dealCount < MAX_DEALS_DAY; dealIdx++)
   {
      ulong ticket = HistoryDealGetTicket(dealIdx);
      if(ticket == 0) continue;
      long dtype = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dtype == (long)DEAL_TYPE_BALANCE) continue;
      string sym = HistoryDealGetString(ticket, DEAL_SYMBOL);
      if(sym != _Symbol) continue;
      datetime t = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(t < dayStart || t >= dayEnd) continue;
      int idx = g_dealCount++;
      g_dealTime[idx]    = t;
      g_dealMagic[idx]   = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      g_dealEntry[idx]   = (int)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      g_dealPrice[idx]   = HistoryDealGetDouble(ticket, DEAL_PRICE);
      g_dealProfit[idx]  = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      g_dealType[idx]    = HistoryDealGetInteger(ticket, DEAL_TYPE);
      g_dealReason[idx]  = HistoryDealGetInteger(ticket, DEAL_REASON);
      g_dealVolume[idx]  = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      g_dealSymbol[idx]  = sym;
      g_dealComment[idx] = HistoryDealGetString(ticket, DEAL_COMMENT);
      g_dealTicket[idx]  = ticket;
   }
   MergeSortDealOrder();
   // Group by magic, pair IN with next OUT
   int dealIdx = 0;
   while(dealIdx < g_dealCount && g_tradeResultsCount < MAX_TRADE_RESULTS)
   {
      long mag = g_dealMagic[g_dealOrder[dealIdx]];
      int inCount = 0, outCount = 0;
      while(dealIdx < g_dealCount && g_dealMagic[g_dealOrder[dealIdx]] == mag)
      {
         int idx = g_dealOrder[dealIdx];
         if(g_dealEntry[idx] == (int)DEAL_ENTRY_IN)  { if(inCount < MAX_IN_OUT_PER_MAGIC) g_inIdx[inCount++] = idx; }
         else if(g_dealEntry[idx] == (int)DEAL_ENTRY_OUT) { if(outCount < MAX_IN_OUT_PER_MAGIC) g_outIdx[outCount++] = idx; }
         dealIdx++;
      }
      for(int pairIdx = 0; pairIdx < inCount && g_tradeResultsCount < MAX_TRADE_RESULTS; pairIdx++)
      {
         TradeResult tradeResult;
         tradeResult.symbol      = g_dealSymbol[g_inIdx[pairIdx]];
         tradeResult.startTime   = g_dealTime[g_inIdx[pairIdx]];
         tradeResult.sentTime    = FalgoSentTimeFromInDeal(g_dealTicket[g_inIdx[pairIdx]]);
         tradeResult.magic       = g_dealMagic[g_inIdx[pairIdx]];
         tradeResult.priceStart  = g_dealPrice[g_inIdx[pairIdx]];
         tradeResult.type       = g_dealType[g_inIdx[pairIdx]];
         tradeResult.volume     = g_dealVolume[g_inIdx[pairIdx]];
         tradeResult.foundOut   = (pairIdx < outCount);
         tradeResult.sessionSent = GetSessionForTradeTime(tradeResult.sentTime);
         if(tradeResult.foundOut)
         {
            int outIdx = g_outIdx[pairIdx];
            tradeResult.endTime   = g_dealTime[outIdx];
            tradeResult.priceEnd  = g_dealPrice[outIdx];
            if(tradeResult.type == (long)DEAL_TYPE_BUY)
               tradeResult.priceDiff = tradeResult.priceEnd - tradeResult.priceStart;
            else
               tradeResult.priceDiff = tradeResult.priceStart - tradeResult.priceEnd;   // DEAL_TYPE_SELL
            tradeResult.profit    = g_dealProfit[outIdx];
            tradeResult.reason    = g_dealReason[outIdx];
            string commentsStr = BuildBothComments(g_dealComment[g_inIdx[pairIdx]], g_dealComment[outIdx], true);
            tradeResult.bothComments = commentsStr;
            Loghelper_FillLevelTpSlFromBothComments(commentsStr, tradeResult.level, tradeResult.tp, tradeResult.sl);
         }
         else
         {
            tradeResult.endTime   = 0;
            tradeResult.priceEnd  = 0;
            tradeResult.priceDiff = 0;
            tradeResult.profit    = 0;
            tradeResult.reason    = 0;
            string commentsStr = BuildBothComments(g_dealComment[g_inIdx[pairIdx]], "", false);
            tradeResult.bothComments = commentsStr;
            Loghelper_FillLevelTpSlFromBothComments(commentsStr, tradeResult.level, tradeResult.tp, tradeResult.sl);
         }
         g_tradeResults[g_tradeResultsCount++] = tradeResult;
      }
   }
}

//+------------------------------------------------------------------+
void UpdateTradeResultsForDay()
{
   const datetime dayStart = g_lastTimer1Time - (g_lastTimer1Time % 86400);
   UpdateTradeResultsForDayStart(dayStart);
}

//+------------------------------------------------------------------+
//| Profit factor from gross win/loss sums (999 = no losses but positive profit). |
//+------------------------------------------------------------------+
double ProfitFactorFromGross(const double grossProfit, const double grossLossAbs)
{
   if(grossLossAbs <= 0.0)
      return (grossProfit > 0.0) ? 999.0 : 0.0;
   return grossProfit / grossLossAbs;
}

string FormatDayProfitFactorForCsv(const double profitFactor)
{
   if(profitFactor >= 999.0)
      return "Infinity";
   return DoubleToString(profitFactor, 2);
}

//+------------------------------------------------------------------+
//| For each bar k, set g_dayProgress[k] from trades with endTime < candle k close time (so close at 16:45:00 counts for 16:45 bar, not 16:44). |
//| Same totals as nested loops: closed trades sorted by endTime, one sweep as candle close advances. |
//+------------------------------------------------------------------+
void UpdateDayProgress()
{
   if(!M1BarCloseStatsBarRangeActive())
      return;

   int closedIdx[MAX_TRADE_RESULTS];
   string closedSess[MAX_TRADE_RESULTS];
   int nc = 0;
   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      if(!g_tradeResults[i].foundOut)
         continue;
      closedIdx[nc] = i;
      closedSess[nc] = GetSessionForCandleTime(g_tradeResults[i].endTime);
      nc++;
   }
   for(int a = 1; a < nc; a++)
   {
      int keyIdx = closedIdx[a];
      datetime keyT = g_tradeResults[keyIdx].endTime;
      string keyS = closedSess[a];
      int b = a - 1;
      while(b >= 0 && g_tradeResults[closedIdx[b]].endTime > keyT)
      {
         closedIdx[b + 1] = closedIdx[b];
         closedSess[b + 1] = closedSess[b];
         b--;
      }
      closedIdx[b + 1] = keyIdx;
      closedSess[b + 1] = keyS;
   }

   const int barStart = g_m1BarCloseStatsIncBarStart;
   const int barEndInclusive = g_m1BarCloseStatsIncBarEndInclusive;

   int p = 0;
   int wins = 0, total = 0;
   double dayPointsSum = 0, dayProfitSum = 0;
   double dayGrossProfit = 0, dayGrossLoss = 0;
   int ONwins = 0, ONtotal = 0;
   double ONpointsSum = 0, ONprofitSum = 0;
   int RTHwins = 0, RTHtotal = 0;
   double RTHpointsSum = 0, RTHprofitSum = 0;

   if(barStart > 0)
   {
      p = g_dayProgressIncP;
      wins = g_dayProgressIncWins;
      total = g_dayProgressIncTotal;
      dayPointsSum = g_dayProgressIncDayPointsSum;
      dayProfitSum = g_dayProgressIncDayProfitSum;
      dayGrossProfit = g_dayProgressIncDayGrossProfit;
      dayGrossLoss = g_dayProgressIncDayGrossLoss;
      ONwins = g_dayProgressIncONwins;
      ONtotal = g_dayProgressIncONtotal;
      ONpointsSum = g_dayProgressIncONpointsSum;
      ONprofitSum = g_dayProgressIncONprofitSum;
      RTHwins = g_dayProgressIncRTHwins;
      RTHtotal = g_dayProgressIncRTHtotal;
      RTHpointsSum = g_dayProgressIncRTHpointsSum;
      RTHprofitSum = g_dayProgressIncRTHprofitSum;
   }

   for(int barIdx = barStart; barIdx <= barEndInclusive; barIdx++)
   {
      datetime candleCloseTime;
      if(barIdx + 1 < g_barsInDay)
         candleCloseTime = g_m1Rates[barIdx + 1].time;
      else
         candleCloseTime = g_m1Rates[barIdx].time + 60;
      while(p < nc && g_tradeResults[closedIdx[p]].endTime < candleCloseTime)
      {
         TradeResult tr = g_tradeResults[closedIdx[p]];
         total++;
         if(tr.profit > 0)
            wins++;
         dayPointsSum += tr.priceDiff;
         dayProfitSum += tr.profit;
         if(tr.profit > 0.0)
            dayGrossProfit += tr.profit;
         else if(tr.profit < 0.0)
            dayGrossLoss += -tr.profit;
         string endSession = closedSess[p];
         if(endSession == "ON")
         {
            ONtotal++;
            if(tr.profit > 0)
               ONwins++;
            ONpointsSum += tr.priceDiff;
            ONprofitSum += tr.profit;
         }
         else if(endSession == "RTH")
         {
            RTHtotal++;
            if(tr.profit > 0)
               RTHwins++;
            RTHpointsSum += tr.priceDiff;
            RTHprofitSum += tr.profit;
         }
         p++;
      }
      g_dayProgress[barIdx].dayWinRate   = (total > 0) ? (double)wins / (double)total : 0.0;
      g_dayProgress[barIdx].dayTradesCount = total;
      g_dayProgress[barIdx].dayPointsSum = dayPointsSum;
      g_dayProgress[barIdx].dayProfitSum = dayProfitSum;
      g_dayProgress[barIdx].dayProfitFactor = ProfitFactorFromGross(dayGrossProfit, dayGrossLoss);
      g_dayProgress[barIdx].ONwinRate   = (ONtotal > 0) ? (double)ONwins / (double)ONtotal : 0.0;
      g_dayProgress[barIdx].ONtradeCount = ONtotal;
      g_dayProgress[barIdx].ONpointsSum = ONpointsSum;
      g_dayProgress[barIdx].ONprofitSum = ONprofitSum;
      g_dayProgress[barIdx].RTHwinRate   = (RTHtotal > 0) ? (double)RTHwins / (double)RTHtotal : 0.0;
      g_dayProgress[barIdx].RTHtradeCount = RTHtotal;
      g_dayProgress[barIdx].RTHpointsSum = RTHpointsSum;
      g_dayProgress[barIdx].RTHprofitSum = RTHprofitSum;
   }

   if(barEndInclusive >= 0)
   {
      g_dayProgressIncP = p;
      g_dayProgressIncWins = wins;
      g_dayProgressIncTotal = total;
      g_dayProgressIncDayPointsSum = dayPointsSum;
      g_dayProgressIncDayProfitSum = dayProfitSum;
      g_dayProgressIncDayGrossProfit = dayGrossProfit;
      g_dayProgressIncDayGrossLoss = dayGrossLoss;
      g_dayProgressIncONwins = ONwins;
      g_dayProgressIncONtotal = ONtotal;
      g_dayProgressIncONpointsSum = ONpointsSum;
      g_dayProgressIncONprofitSum = ONprofitSum;
      g_dayProgressIncRTHwins = RTHwins;
      g_dayProgressIncRTHtotal = RTHtotal;
      g_dayProgressIncRTHpointsSum = RTHpointsSum;
      g_dayProgressIncRTHprofitSum = RTHprofitSum;
   }

   if(g_m1BarCloseStatsFormingBarIdx >= 0 && barEndInclusive >= 0)
      g_dayProgress[g_m1BarCloseStatsFormingBarIdx] = g_dayProgress[barEndInclusive];
}

//+------------------------------------------------------------------+
//| Fill g_ONhighSoFarAtBar, g_ONlowSoFarAtBar, g_rthHighSoFarAtBar, g_rthLowSoFarAtBar, g_dayHighSoFarAtBar, g_dayLowSoFarAtBar, g_sessionRangeMidpointAtBar for bars 0..g_barsInDay-1. |
//| For each bar k: ON high/low = running max/min of ON bars up to k; RTH same; day high/low = running max/min of all bars up to k; sessionRangeMidpoint = (dayHigh+dayLow)/2. Before first ON/RTH bar, hasValue false. |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void UpdateONandRTHHighLowSoFarAtBarOneBar(const int barIdx,
   bool &firstON, bool &firstRTH,
   double &runONhigh, double &runONlow, double &runRTHhigh, double &runRTHlow,
   double &runDayHigh, double &runDayLow)
{
   if(barIdx == 0)
   {
      runDayHigh = g_m1Rates[barIdx].high;
      runDayLow = g_m1Rates[barIdx].low;
   }
   else
   {
      runDayHigh = MathMax(runDayHigh, g_m1Rates[barIdx].high);
      runDayLow  = MathMin(runDayLow, g_m1Rates[barIdx].low);
   }
   g_dayHighSoFarAtBar[barIdx].hasValue = true;
   g_dayHighSoFarAtBar[barIdx].value    = runDayHigh;
   g_dayLowSoFarAtBar[barIdx].hasValue  = true;
   g_dayLowSoFarAtBar[barIdx].value     = runDayLow;
   g_sessionRangeMidpointAtBar[barIdx].hasValue = true;
   g_sessionRangeMidpointAtBar[barIdx].value    = (runDayHigh + runDayLow) / 2.0;
   const double pdh = g_staticMarketContext.PDHpreviousDayHigh;
   const double pdl = g_staticMarketContext.PDLpreviousDayLow;
   g_dayBrokePDHAtBar[barIdx] = (pdh > 0.0 && runDayHigh > pdh);
   g_dayBrokePDLAtBar[barIdx] = (pdl > 0.0 && runDayLow < pdl);

   if(g_session[barIdx] == "ON")
   {
      if(firstON) { runONhigh = g_m1Rates[barIdx].high; runONlow = g_m1Rates[barIdx].low; firstON = false; }
      else        { runONhigh = MathMax(runONhigh, g_m1Rates[barIdx].high); runONlow = MathMin(runONlow, g_m1Rates[barIdx].low); }
      g_ONhighSoFarAtBar[barIdx].hasValue = true;
      g_ONhighSoFarAtBar[barIdx].value    = runONhigh;
      g_ONlowSoFarAtBar[barIdx].hasValue = true;
      g_ONlowSoFarAtBar[barIdx].value    = runONlow;
   }
   else
   {
      g_ONhighSoFarAtBar[barIdx].hasValue = !firstON;
      g_ONhighSoFarAtBar[barIdx].value    = runONhigh;
      g_ONlowSoFarAtBar[barIdx].hasValue  = !firstON;
      g_ONlowSoFarAtBar[barIdx].value     = runONlow;
   }
   if(g_session[barIdx] == "RTH")
   {
      if(firstRTH) { runRTHhigh = g_m1Rates[barIdx].high; runRTHlow = g_m1Rates[barIdx].low; firstRTH = false; }
      else         { runRTHhigh = MathMax(runRTHhigh, g_m1Rates[barIdx].high); runRTHlow = MathMin(runRTHlow, g_m1Rates[barIdx].low); }
      g_rthHighSoFarAtBar[barIdx].hasValue = true;
      g_rthHighSoFarAtBar[barIdx].value    = runRTHhigh;
      g_rthLowSoFarAtBar[barIdx].hasValue  = true;
      g_rthLowSoFarAtBar[barIdx].value     = runRTHlow;
   }
   else
   {
      g_rthHighSoFarAtBar[barIdx].hasValue = !firstRTH;
      g_rthHighSoFarAtBar[barIdx].value    = runRTHhigh;
      g_rthLowSoFarAtBar[barIdx].hasValue  = !firstRTH;
      g_rthLowSoFarAtBar[barIdx].value     = runRTHlow;
   }
}

//+------------------------------------------------------------------+
void UpdateONandRTHHighLowSoFarAtBar()
{
   if(!M1BarCloseStatsBarRangeActive())
      return;

   const int barStart = g_m1BarCloseStatsIncBarStart;
   const int barEndInclusive = g_m1BarCloseStatsIncBarEndInclusive;

   bool firstON = true, firstRTH = true;
   double runONhigh = 0, runONlow = 0, runRTHhigh = 0, runRTHlow = 0;
   double runDayHigh = 0, runDayLow = 0;
   if(barStart > 0)
   {
      firstON = g_sessionHlIncFirstON;
      firstRTH = g_sessionHlIncFirstRTH;
      runONhigh = g_sessionHlIncRunONhigh;
      runONlow = g_sessionHlIncRunONlow;
      runRTHhigh = g_sessionHlIncRunRTHhigh;
      runRTHlow = g_sessionHlIncRunRTHlow;
      runDayHigh = g_sessionHlIncRunDayHigh;
      runDayLow = g_sessionHlIncRunDayLow;
   }
   else if(g_barsInDay > 0)
   {
      runDayHigh = g_m1Rates[0].high;
      runDayLow = g_m1Rates[0].low;
   }

   for(int barIdx = barStart; barIdx <= barEndInclusive; barIdx++)
      UpdateONandRTHHighLowSoFarAtBarOneBar(barIdx, firstON, firstRTH, runONhigh, runONlow, runRTHhigh, runRTHlow, runDayHigh, runDayLow);

   g_sessionHlIncFirstON = firstON;
   g_sessionHlIncFirstRTH = firstRTH;
   g_sessionHlIncRunONhigh = runONhigh;
   g_sessionHlIncRunONlow = runONlow;
   g_sessionHlIncRunRTHhigh = runRTHhigh;
   g_sessionHlIncRunRTHlow = runRTHlow;
   g_sessionHlIncRunDayHigh = runDayHigh;
   g_sessionHlIncRunDayLow = runDayLow;

   if(g_m1BarCloseStatsFormingBarIdx >= 0)
   {
      bool scratchFirstON = g_sessionHlIncFirstON;
      bool scratchFirstRTH = g_sessionHlIncFirstRTH;
      double scratchONhigh = g_sessionHlIncRunONhigh;
      double scratchONlow = g_sessionHlIncRunONlow;
      double scratchRTHhigh = g_sessionHlIncRunRTHhigh;
      double scratchRTHlow = g_sessionHlIncRunRTHlow;
      double scratchDayHigh = g_sessionHlIncRunDayHigh;
      double scratchDayLow = g_sessionHlIncRunDayLow;
      UpdateONandRTHHighLowSoFarAtBarOneBar(g_m1BarCloseStatsFormingBarIdx, scratchFirstON, scratchFirstRTH,
         scratchONhigh, scratchONlow, scratchRTHhigh, scratchRTHlow, scratchDayHigh, scratchDayLow);
   }
}

//+------------------------------------------------------------------+
//| Fill g_IBhighAtBar, g_IBlowAtBar: IB = first hour of RTH (15:30–16:30 normal, 14:30–15:30 desync). hasValue false before last IB bar; after, value = max high / min low of IB bars. |
//+------------------------------------------------------------------+
void UpdateIBHighLowAtBar()
{
   if(g_barsInDay <= 0 || g_m1DayStart == 0 || !M1BarCloseStatsBarRangeActive()) return;

   const int barStart = g_m1BarCloseStatsIncBarStart;
   const int barEndInclusive = g_m1BarCloseStatsIncBarEndInclusive;

   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   datetime lastIBBarTime;
   if(bool_RTHsession_Is_DaylightSavingsDesync(dateStr))
      lastIBBarTime = g_m1DayStart + 15*3600 + 30*60;
   else
      lastIBBarTime = g_m1DayStart + 16*3600 + 30*60;

   double ibHigh = -1e300, ibLow = 1e300;
   bool ibComplete = false;
   if(barStart > 0)
   {
      ibHigh = g_ibHlIncIbHigh;
      ibLow = g_ibHlIncIbLow;
      ibComplete = g_ibHlIncIbComplete;
   }

   for(int barIdx = barStart; barIdx <= barEndInclusive; barIdx++)
   {
      if(IsBarRTHIB(g_m1Rates[barIdx].time))
      {
         ibHigh = MathMax(ibHigh, g_m1Rates[barIdx].high);
         ibLow  = MathMin(ibLow, g_m1Rates[barIdx].low);
      }
      if(g_m1Rates[barIdx].time >= lastIBBarTime)
         ibComplete = true;

      const bool hasIBhigh = ibComplete && (ibHigh > -1e299);
      const bool hasIBlow  = ibComplete && (ibLow < 1e299);
      g_IBhighAtBar[barIdx].hasValue = hasIBhigh;
      if(hasIBhigh) g_IBhighAtBar[barIdx].value = ibHigh;
      g_IBlowAtBar[barIdx].hasValue  = hasIBlow;
      if(hasIBlow)  g_IBlowAtBar[barIdx].value  = ibLow;
   }

   g_ibHlIncIbHigh = ibHigh;
   g_ibHlIncIbLow = ibLow;
   g_ibHlIncIbComplete = ibComplete;

   if(g_m1BarCloseStatsFormingBarIdx >= 0 && barEndInclusive >= 0)
   {
      const int formingIdx = g_m1BarCloseStatsFormingBarIdx;
      g_IBhighAtBar[formingIdx] = g_IBhighAtBar[barEndInclusive];
      g_IBlowAtBar[formingIdx] = g_IBlowAtBar[barEndInclusive];
   }
}

//+------------------------------------------------------------------+
//| Fill g_gapFillSoFarAtBar: % of gap filled so far. Gap up (RTHopen>PDC): use rthLowSoFar (fill from top). Gap down (RTHopen<PDC): use rthHighSoFar (fill from bottom). Unknown before RTH open. |
//+------------------------------------------------------------------+
void UpdateGapFillSoFarAtBar()
{
   if(g_barsInDay <= 0 || g_m1DayStart == 0 || !M1BarCloseStatsBarRangeActive()) return;
   if(!g_todayRTHopenValid || g_staticMarketContext.PDCpreviousDayRTHClose <= 0.0) return;
   const double rthOpen = g_todayRTHopen;
   const double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
   const double range_top    = MathMax(pdc, rthOpen);
   const double range_bottom = MathMin(pdc, rthOpen);
   const double range_size   = range_top - range_bottom;
   const bool isGapUp = (rthOpen > pdc);
   if(range_size <= 0.0) return;

   const int barStart = g_m1BarCloseStatsIncBarStart;
   const int barEndInclusive = g_m1BarCloseStatsIncBarEndInclusive;
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   const datetime rthOpenBarTime = g_m1DayStart + GetRthOpenBarOffsetSeconds(dateStr);

   for(int barIdx = barStart; barIdx <= barEndInclusive; barIdx++)
   {
      if(g_m1Rates[barIdx].time < rthOpenBarTime)
      {
         g_gapFillSoFarAtBar[barIdx].hasValue = false;
         continue;
      }
      if(!g_rthHighSoFarAtBar[barIdx].hasValue || !g_rthLowSoFarAtBar[barIdx].hasValue)
      {
         g_gapFillSoFarAtBar[barIdx].hasValue = false;
         continue;
      }
      const double rthH = g_rthHighSoFarAtBar[barIdx].value;
      const double rthL = g_rthLowSoFarAtBar[barIdx].value;
      double filled = 0.0;
      if(isGapUp)
         filled = MathMax(0.0, MathMin(range_size, range_top - rthL));
      else
         filled = MathMax(0.0, MathMin(range_size, rthH - range_bottom));
      const double pct = MathMin(100.0, (filled / range_size) * 100.0);
      g_gapFillSoFarAtBar[barIdx].hasValue = true;
      g_gapFillSoFarAtBar[barIdx].value    = pct;
   }
}

//+------------------------------------------------------------------+
//| Points price moved away from gap (widening) at bar: gap up = RTH high above range top; gap down = RTH low below range bottom. |
//+------------------------------------------------------------------+
double GapfillAwayFromGapPointsAtBar(const int barIdx, const double rangeTop, const double rangeBottom, const bool isGapUp)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0.0;
   if(!g_rthHighSoFarAtBar[barIdx].hasValue || !g_rthLowSoFarAtBar[barIdx].hasValue) return 0.0;
   if(isGapUp)
   {
      const double away = g_rthHighSoFarAtBar[barIdx].value - rangeTop;
      return (away > 0.0) ? away : 0.0;
   }
   const double away = rangeBottom - g_rthLowSoFarAtBar[barIdx].value;
   return (away > 0.0) ? away : 0.0;
}

//+------------------------------------------------------------------+
//| Per bar: max movement away from gap before first fill attempt (first jump >over_5 from <=over_5 or unknown). Frozen after that bar. |
//+------------------------------------------------------------------+
void UpdateGapFillAttemptStatsAtBar()
{
   if(g_barsInDay <= 0 || g_m1DayStart == 0 || !M1BarCloseStatsBarRangeActive()) return;
   if(!g_todayRTHopenValid || g_staticMarketContext.PDCpreviousDayRTHClose <= 0.0) return;

   const double rthOpen = g_todayRTHopen;
   const double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
   const double rangeTop = MathMax(pdc, rthOpen);
   const double rangeBottom = MathMin(pdc, rthOpen);
   const double rangeSize = rangeTop - rangeBottom;
   if(rangeSize <= 0.0) return;

   const bool isGapUp = (rthOpen > pdc);
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   const datetime rthOpenBarTime = g_m1DayStart + GetRthOpenBarOffsetSeconds(dateStr);
   const int barStart = g_m1BarCloseStatsIncBarStart;
   const int barEndInclusive = g_m1BarCloseStatsIncBarEndInclusive;
   const bool fullPass = g_m1BarCloseStatsIncNeedFullRescan;

   if(fullPass)
   {
      dayStat_maxBeforeGapfillAttempt_valid = false;
      for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
         g_maxBeforeGapfillAttempt_over_5AtBar[barIdx].hasValue = false;
   }

   int rthOpenBarIdx = g_gapAttemptIncRthOpenBarIdx;
   if(rthOpenBarIdx < 0 || fullPass)
   {
      rthOpenBarIdx = -1;
      for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
      {
         if(g_m1Rates[barIdx].time >= rthOpenBarTime) { rthOpenBarIdx = barIdx; break; }
      }
   }
   if(rthOpenBarIdx < 0) return;

   int attemptBarIdx = fullPass ? -1 : g_gapAttemptIncAttemptBarIdx;
   double prevFill = fullPass ? -1.0 : g_gapAttemptIncPrevFill;
   double runningMaxAway = fullPass ? 0.0 : g_gapAttemptIncRunningMaxAway;
   double finalMaxAway = fullPass ? 0.0 : g_gapAttemptIncFinalMaxAway;

   if(attemptBarIdx >= 0 && !fullPass)
   {
      for(int barIdx = barStart; barIdx <= barEndInclusive; barIdx++)
      {
         if(g_m1Rates[barIdx].time < rthOpenBarTime) continue;
         g_maxBeforeGapfillAttempt_over_5AtBar[barIdx].hasValue = true;
         g_maxBeforeGapfillAttempt_over_5AtBar[barIdx].value = (barIdx >= attemptBarIdx) ? finalMaxAway : g_maxBeforeGapfillAttempt_over_5AtBar[barIdx].value;
      }
   }
   else
   {
      const int scanStart = fullPass ? rthOpenBarIdx : MathMax(rthOpenBarIdx, barStart);
      for(int barIdx = scanStart; barIdx <= (fullPass ? g_barsInDay - 1 : barEndInclusive); barIdx++)
      {
         if(g_m1Rates[barIdx].time < rthOpenBarTime) continue;
         double fill = 0.0;
         if(!GetGapFillSoFarAtBar(barIdx, g_m1DayStart, dateStr, fill)) continue;
         const double fillBaseline = (prevFill >= 0.0) ? prevFill : 0.0;
         const bool priorStillUnfilled = (prevFill < 0.0 || prevFill <= gapFillAttempt_minIncreasePc);
         if(attemptBarIdx < 0 && priorStillUnfilled && (fill - fillBaseline) > gapFillAttempt_minIncreasePc)
         {
            attemptBarIdx = barIdx;
            finalMaxAway = 0.0;
            for(int j = rthOpenBarIdx; j < attemptBarIdx; j++)
            {
               const double awayBefore = GapfillAwayFromGapPointsAtBar(j, rangeTop, rangeBottom, isGapUp);
               if(awayBefore > finalMaxAway) finalMaxAway = awayBefore;
            }
            runningMaxAway = finalMaxAway;
            g_maxBeforeGapfillAttempt_over_5AtBar[barIdx].hasValue = true;
            g_maxBeforeGapfillAttempt_over_5AtBar[barIdx].value = finalMaxAway;
            prevFill = fill;
            continue;
         }
         const double away = GapfillAwayFromGapPointsAtBar(barIdx, rangeTop, rangeBottom, isGapUp);
         if(away > runningMaxAway) runningMaxAway = away;
         g_maxBeforeGapfillAttempt_over_5AtBar[barIdx].hasValue = true;
         g_maxBeforeGapfillAttempt_over_5AtBar[barIdx].value = (attemptBarIdx >= 0 && barIdx >= attemptBarIdx) ? finalMaxAway : runningMaxAway;
         prevFill = fill;
      }

      if(fullPass && attemptBarIdx >= 0)
      {
         finalMaxAway = 0.0;
         for(int j = rthOpenBarIdx; j < attemptBarIdx; j++)
         {
            const double awayBefore = GapfillAwayFromGapPointsAtBar(j, rangeTop, rangeBottom, isGapUp);
            if(awayBefore > finalMaxAway) finalMaxAway = awayBefore;
         }
         for(int barIdx = attemptBarIdx; barIdx < g_barsInDay; barIdx++)
         {
            if(g_m1Rates[barIdx].time < rthOpenBarTime) continue;
            g_maxBeforeGapfillAttempt_over_5AtBar[barIdx].hasValue = true;
            g_maxBeforeGapfillAttempt_over_5AtBar[barIdx].value = finalMaxAway;
         }
      }
   }

   if(attemptBarIdx < 0)
      finalMaxAway = runningMaxAway;

   g_gapAttemptIncRthOpenBarIdx = rthOpenBarIdx;
   g_gapAttemptIncAttemptBarIdx = attemptBarIdx;
   g_gapAttemptIncPrevFill = prevFill;
   g_gapAttemptIncRunningMaxAway = runningMaxAway;
   g_gapAttemptIncFinalMaxAway = finalMaxAway;

   dayStat_maxBeforeGapfillAttempt_over_5 = finalMaxAway;
   dayStat_maxBeforeGapfillAttempt_valid = true;
}

//+------------------------------------------------------------------+
//| Smallest barIdx where candle close time > endTime (same close rule as UpdateLevelTradeStats); barCount if none. |
//+------------------------------------------------------------------+
int LevelExpandedFirstBarWhereCloseAfter(datetime &times[], int barCount, datetime endTime)
{
   int lo = 0, hi = barCount - 1, ans = barCount;
   while(lo <= hi)
   {
      int mid = (lo + hi) / 2;
      datetime cclose;
      if(mid + 1 < barCount)
         cclose = times[mid + 1];
      else
         cclose = times[mid] + 60;
      if(cclose > endTime)
      {
         ans = mid;
         hi = mid - 1;
      }
      else
         lo = mid + 1;
   }
   return ans;
}

//+------------------------------------------------------------------+
//| Per (level e, bar k): aggregate trades whose level matches levelPrice and endTime < bar k close. Same frequency as trade results. |
//+------------------------------------------------------------------+
void UpdateLevelTradeStats()
{
   if(!M1BarCloseStatsBarRangeActive())
      return;

   const double tolerance = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 1e-6);
   const bool fullPass = g_m1BarCloseStatsIncNeedFullRescan;

   if(fullPass)
   {
      for(int levelIdx = 0; levelIdx < g_levelsTodayCount; levelIdx++)
      {
         int barCount = g_levelsExpanded[levelIdx].count;
         for(int barIdx = 0; barIdx < barCount; barIdx++)
         {
            g_ONtradeCount_L[levelIdx][barIdx] = 0;
            g_ONwins_L[levelIdx][barIdx] = 0;
            g_ONpointsSum_L[levelIdx][barIdx] = 0.0;
            g_ONprofitSum_L[levelIdx][barIdx] = 0.0;
            g_RTHtradeCount_L[levelIdx][barIdx] = 0;
            g_RTHwins_L[levelIdx][barIdx] = 0;
            g_RTHpointsSum_L[levelIdx][barIdx] = 0.0;
            g_RTHprofitSum_L[levelIdx][barIdx] = 0.0;
         }
      }
      for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
      {
         TradeResult tradeResult = g_tradeResults[trIdx];
         if(StringLen(tradeResult.level) == 0 || !tradeResult.foundOut) continue;
         double levelVal = StringToDouble(tradeResult.level);
         int levelIdx = -1;
         for(int idx = 0; idx < g_levelsTodayCount; idx++)
         {
            if(MathAbs(g_levelsExpanded[idx].levelPrice - levelVal) < tolerance) { levelIdx = idx; break; }
         }
         if(levelIdx < 0) continue;
         string endSession = GetSessionForCandleTime(tradeResult.endTime);
         int barCount = g_levelsExpanded[levelIdx].count;
         int firstBar = LevelExpandedFirstBarWhereCloseAfter(g_levelsExpanded[levelIdx].times, barCount, tradeResult.endTime);
         if(firstBar >= barCount) continue;
         if(endSession == "ON")
         {
            for(int barIdx = firstBar; barIdx < barCount; barIdx++)
            {
               g_ONtradeCount_L[levelIdx][barIdx]++;
               if(tradeResult.profit > 0) g_ONwins_L[levelIdx][barIdx]++;
               g_ONpointsSum_L[levelIdx][barIdx] += tradeResult.priceDiff;
               g_ONprofitSum_L[levelIdx][barIdx] += tradeResult.profit;
            }
         }
         else if(endSession == "RTH")
         {
            for(int barIdx = firstBar; barIdx < barCount; barIdx++)
            {
               g_RTHtradeCount_L[levelIdx][barIdx]++;
               if(tradeResult.profit > 0) g_RTHwins_L[levelIdx][barIdx]++;
               g_RTHpointsSum_L[levelIdx][barIdx] += tradeResult.priceDiff;
               g_RTHprofitSum_L[levelIdx][barIdx] += tradeResult.profit;
            }
         }
      }
      g_levelTradeStatsIncAppliedTradeCount = g_tradeResultsCount;
      return;
   }

   const int barStart = g_m1BarCloseStatsIncBarStart;
   const int barEndInclusive = g_m1BarCloseStatsIncBarEndInclusive;
   for(int levelIdx = 0; levelIdx < g_levelsTodayCount; levelIdx++)
   {
      const int barCount = g_levelsExpanded[levelIdx].count;
      const int levelBarEnd = MathMin(barEndInclusive, barCount - 1);
      if(levelBarEnd < barStart)
         continue;
      const double levelPrice = g_levelsExpanded[levelIdx].levelPrice;

      for(int barIdx = barStart; barIdx <= levelBarEnd; barIdx++)
      {
         if(barIdx == 0)
         {
            g_ONtradeCount_L[levelIdx][barIdx] = 0;
            g_ONwins_L[levelIdx][barIdx] = 0;
            g_ONpointsSum_L[levelIdx][barIdx] = 0.0;
            g_ONprofitSum_L[levelIdx][barIdx] = 0.0;
            g_RTHtradeCount_L[levelIdx][barIdx] = 0;
            g_RTHwins_L[levelIdx][barIdx] = 0;
            g_RTHpointsSum_L[levelIdx][barIdx] = 0.0;
            g_RTHprofitSum_L[levelIdx][barIdx] = 0.0;
         }
         else
         {
            g_ONtradeCount_L[levelIdx][barIdx] = g_ONtradeCount_L[levelIdx][barIdx - 1];
            g_ONwins_L[levelIdx][barIdx] = g_ONwins_L[levelIdx][barIdx - 1];
            g_ONpointsSum_L[levelIdx][barIdx] = g_ONpointsSum_L[levelIdx][barIdx - 1];
            g_ONprofitSum_L[levelIdx][barIdx] = g_ONprofitSum_L[levelIdx][barIdx - 1];
            g_RTHtradeCount_L[levelIdx][barIdx] = g_RTHtradeCount_L[levelIdx][barIdx - 1];
            g_RTHwins_L[levelIdx][barIdx] = g_RTHwins_L[levelIdx][barIdx - 1];
            g_RTHpointsSum_L[levelIdx][barIdx] = g_RTHpointsSum_L[levelIdx][barIdx - 1];
            g_RTHprofitSum_L[levelIdx][barIdx] = g_RTHprofitSum_L[levelIdx][barIdx - 1];
         }

         datetime candleCloseTime;
         if(barIdx + 1 < barCount)
            candleCloseTime = g_levelsExpanded[levelIdx].times[barIdx + 1];
         else
            candleCloseTime = g_levelsExpanded[levelIdx].times[barIdx] + 60;
         datetime prevCloseTime = 0;
         if(barIdx > 0)
         {
            if(barIdx < barCount)
               prevCloseTime = g_levelsExpanded[levelIdx].times[barIdx];
            else
               prevCloseTime = g_levelsExpanded[levelIdx].times[barIdx - 1] + 60;
         }

         for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
         {
            TradeResult tradeResult = g_tradeResults[trIdx];
            if(StringLen(tradeResult.level) == 0 || !tradeResult.foundOut) continue;
            if(MathAbs(StringToDouble(tradeResult.level) - levelPrice) >= tolerance) continue;
            if(tradeResult.endTime >= candleCloseTime) continue;
            if(barIdx > 0 && tradeResult.endTime < prevCloseTime) continue;

            string endSession = GetSessionForCandleTime(tradeResult.endTime);
            if(endSession == "ON")
            {
               g_ONtradeCount_L[levelIdx][barIdx]++;
               if(tradeResult.profit > 0) g_ONwins_L[levelIdx][barIdx]++;
               g_ONpointsSum_L[levelIdx][barIdx] += tradeResult.priceDiff;
               g_ONprofitSum_L[levelIdx][barIdx] += tradeResult.profit;
            }
            else if(endSession == "RTH")
            {
               g_RTHtradeCount_L[levelIdx][barIdx]++;
               if(tradeResult.profit > 0) g_RTHwins_L[levelIdx][barIdx]++;
               g_RTHpointsSum_L[levelIdx][barIdx] += tradeResult.priceDiff;
               g_RTHprofitSum_L[levelIdx][barIdx] += tradeResult.profit;
            }
         }
      }
   }
   g_levelTradeStatsIncAppliedTradeCount = g_tradeResultsCount;
}

//+------------------------------------------------------------------+
//| Parse banned ranges string "startH,startM,endH,endM;..." into g_bannedRangesBuffer, set g_bannedRangesCount. |
//+------------------------------------------------------------------+
void ParseBannedRanges(const string s)
{
   g_bannedRangesCount = 0;
   ArrayResize(g_bannedRangesBuffer, 0);
   if(StringLen(s) == 0) return;
   string parts[];
   int partCount = StringSplit(s, ';', parts);
   if(partCount <= 0) return;
   for(int rangeIdx = 0; rangeIdx < partCount && g_bannedRangesCount < MAX_BANNED_RANGES; rangeIdx++)
   {
      string nums[];
      if(StringSplit(parts[rangeIdx], ',', nums) != 4) continue;
      ArrayResize(g_bannedRangesBuffer, g_bannedRangesCount + 1);
      g_bannedRangesBuffer[g_bannedRangesCount][0] = (int)StringToInteger(nums[0]);
      g_bannedRangesBuffer[g_bannedRangesCount][1] = (int)StringToInteger(nums[1]);
      g_bannedRangesBuffer[g_bannedRangesCount][2] = (int)StringToInteger(nums[2]);
      g_bannedRangesBuffer[g_bannedRangesCount][3] = (int)StringToInteger(nums[3]);
      g_bannedRangesCount++;
   }
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Day-of-week suffix for magic: 0 when level has no "daily" in tags; 0..6 (Mon..Sun) when "daily". |
//| Reserved for future level-scoped magic suffixes. |
//+------------------------------------------------------------------+
int GetDayOfWeekSuffixForLevel(datetime validFrom, string tagsCSV)
{
   if(StringFind(tagsCSV, "daily") < 0) return 0;
   MqlDateTime dt;
   TimeToStruct(validFrom, dt);
   int mt5Day = dt.day_of_week;
   if(mt5Day == 0) mt5Day = 7;
   return mt5Day - 1;
}

//+------------------------------------------------------------------+
//| Clamp to [0.1,9.9], round to 0.1; return int 1..99 for %02d (two-digit tenths field in composite). |
//+------------------------------------------------------------------+
int EncodeMagicTwoDigitTenths(double v)
{
   double clamped = MathMax(0.1, MathMin(9.9, v));
   int tenthsInt = (int)MathRound(clamped * 10.0);
   if(tenthsInt < 1) tenthsInt = 1;
   if(tenthsInt > 99) tenthsInt = 99;
   return tenthsInt;
}

//+------------------------------------------------------------------+
//| Magic long → exactly COMPOSITE_MAGIC_STRING_LEN decimal chars (left-pad with zeros). |
//+------------------------------------------------------------------+
string MagicNumberToFixedWidthString(long magic)
{
   string s = IntegerToString(magic);
   if(StringLen(s) > COMPOSITE_MAGIC_STRING_LEN)
      FatalError(StringFormat("MagicNumberToFixedWidthString: value has %d digits, max %d", StringLen(s), COMPOSITE_MAGIC_STRING_LEN));
   while(StringLen(s) < COMPOSITE_MAGIC_STRING_LEN)
      s = "0" + s;
   return s;
}



//+------------------------------------------------------------------+
//| Algo family magic: first 3 digits = algo number 100..999 (shared helpers)
//+------------------------------------------------------------------+

#define MAGIC_ALGO_FAMILY_SLOT_MIN  100
#define MAGIC_ALGO_FAMILY_SLOT_MAX  999

#define FALGO_MAGIC_LENGTH_ALGO     3

#define ALGO_SIDE_LONG   false   // buy limit above weekly level
#define ALGO_SIDE_SHORT  true    // sell limit below weekly level

//algocreator1start
   // Level-family trade algos (100..199) not wired in aleksik2.
int g_algoRegistryIds[] = { };
//algocreator1end

//breakdowncreator1start
#define MAGIC_BREAKDOWN200             200
#define MAGIC_BREAKDOWN201             201
#define MAGIC_BREAKDOWN202             202
#define MAGIC_BREAKDOWN203             203
#define MAGIC_BREAKDOWN204             204

int g_breakdownRegistryIds[] =
{
   MAGIC_BREAKDOWN200,
   MAGIC_BREAKDOWN201,
   MAGIC_BREAKDOWN202,
   MAGIC_BREAKDOWN203,
   MAGIC_BREAKDOWN204
};
//breakdowncreator1end

//+------------------------------------------------------------------+
void RebuildBreakdownAlgoSlotsRegistry()
{
   g_breakdownAlgoCount = 0;
   const int n = ArraySize(g_breakdownRegistryIds);
   for(int i = 0; i < n; i++)
   {
      if(g_breakdownAlgoCount >= BREAKDOWN_ALGO_REGISTRY_MAX)
         FatalError("RebuildBreakdownAlgoSlotsRegistry: BREAKDOWN_ALGO_REGISTRY_MAX exceeded");
      g_breakdownAlgos[g_breakdownAlgoCount].algo_id = g_breakdownRegistryIds[i];
      g_breakdownAlgoCount++;
   }
   if(BREAKDOWN_ALGO_REGISTRY_MAX > g_breakdownAlgoCount + BREAKDOWN_ALGO_REGISTRY_MAX_HEADROOM)
      FatalError(StringFormat(
         "BREAKDOWN_ALGO_REGISTRY_MAX=%d exceeds wired breakdown algo count %d by more than %d",
         BREAKDOWN_ALGO_REGISTRY_MAX, g_breakdownAlgoCount, BREAKDOWN_ALGO_REGISTRY_MAX_HEADROOM));
}

//+------------------------------------------------------------------+
int BreakdownAlgoSlotIndexByAlgoId(const int algoNumber)
{
   for(int i = 0; i < g_breakdownAlgoCount; i++)
   {
      if(g_breakdownAlgos[i].algo_id == algoNumber)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
bool BreakdownAlgoDefForNumber(const int algoNumber, BreakdownAlgoDef &outDef)
{
   const int idx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   outDef = g_breakdownAlgos[idx];
   return true;
}

//+------------------------------------------------------------------+
bool IsBreakdownFamilyAlgoNumber(const int algoNumber)
{
   return (algoNumber >= MAGIC_BREAKDOWN_FAMILY_SLOT_MIN && algoNumber <= MAGIC_BREAKDOWN_FAMILY_SLOT_MAX);
}

//+------------------------------------------------------------------+
bool IsLevelFamilyAlgoNumber(const int algoNumber)
{
   return (algoNumber >= MAGIC_ALGO_FAMILY_SLOT_MIN && algoNumber <= 199);
}

//+------------------------------------------------------------------+
bool IsBreakdownFamilyCompositeMagic(const long magic)
{
   return IsBreakdownFamilyAlgoNumber(AlgoFamilyMagicNumber(magic));
}

//+------------------------------------------------------------------+
bool IsLevelFamilyCompositeMagic(const long magic)
{
   return IsLevelFamilyAlgoNumber(AlgoFamilyMagicNumber(magic));
}

//+------------------------------------------------------------------+
string BreakdownAlgoCsvFileName(const string dateStr, const int algoNumber, const string suffix)
{
   return dateStr + "_bdalgo" + IntegerToString(algoNumber) + "_" + suffix + ".csv";
}

//+------------------------------------------------------------------+
string BreakdownTradeLifetimeRunLogFileName(const int algoNumber)
{
   return "bdalgo" + IntegerToString(algoNumber) + "_alltrades_log.csv";
}

//+------------------------------------------------------------------+
string BreakdownContinuationModeLogSlug(const ENUM_BREAKDOWN_STREAK_CONTINUATION mode);

string BreakdownBenchmarkAllAlgosFileName()
{
   return "benchmark_all_algos_breakdown.csv";
}

//+------------------------------------------------------------------+
void BreakdownBenchmarkAllAlgosReset()
{
   for(int i = 0; i < BREAKDOWN_ALGO_REGISTRY_MAX; i++)
   {
      g_breakdownAlgoBenchmarkAcc[i].tradesClosed = 0;
      g_breakdownAlgoBenchmarkAcc[i].wins = 0;
      g_breakdownAlgoBenchmarkAcc[i].losses = 0;
      g_breakdownAlgoBenchmarkAcc[i].sumPriceDiff = 0.0;
      g_breakdownAlgoBenchmarkAcc[i].sumMfePts = 0.0;
      g_breakdownAlgoBenchmarkAcc[i].sumMaePts = 0.0;
      g_breakdownAlgoBenchmarkAcc[i].telCount = 0;
      g_breakdownAlgoBenchmarkAcc[i].sumLifetimeHours = 0.0;
   }
}

//+------------------------------------------------------------------+
void BreakdownBenchmarkAllAlgosWrite()
{
   if(!bigflipper_log_breakdown_trade_lifetime)
      return;

   const bool profOn = BacktestProfileEnabled();
   ulong profT0 = 0;
   if(profOn)
      profT0 = GetMicrosecondCount();

   int fh = FileOpen(BreakdownBenchmarkAllAlgosFileName(), FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;

   FileWrite(fh, "algo_id", "continuation_type", "trades_closed", "wins", "losses", "win_rate_pct",
      "sum_priceDiff", "avg_priceDiff", "avg_mfe_pts", "avg_mae_pts", "avg_lifetime_hours",
      "sum_lifetime_minutes", "sum_lifetime_hours", "sum_lifetime_days", "hours_vs_pricediff_ratio");

   for(int i = 0; i < g_breakdownAlgoCount; i++)
   {
      const int algoNumber = g_breakdownAlgos[i].algo_id;
      const int slotIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
      if(slotIdx < 0)
         continue;
      const BreakdownAlgoBenchmarkAcc acc = g_breakdownAlgoBenchmarkAcc[slotIdx];
      const int n = acc.tradesClosed;
      const double avgPriceDiff = (n > 0) ? acc.sumPriceDiff / (double)n : 0.0;
      const double winRate = (n > 0) ? (100.0 * (double)acc.wins / (double)n) : 0.0;
      const double avgMfe = (acc.telCount > 0) ? acc.sumMfePts / (double)acc.telCount : 0.0;
      const double avgMae = (acc.telCount > 0) ? acc.sumMaePts / (double)acc.telCount : 0.0;
      const double avgLifetime = (n > 0) ? acc.sumLifetimeHours / (double)n : 0.0;
      const double sumLifetimeMinutes = acc.sumLifetimeHours * 60.0;
      const double sumLifetimeDays = acc.sumLifetimeHours / 24.0;
      const string hoursVsPricediffRatio = (MathAbs(acc.sumPriceDiff) > 0.0)
         ? DoubleToString(acc.sumLifetimeHours / acc.sumPriceDiff, 4) : "";
      const ENUM_BREAKDOWN_STREAK_CONTINUATION mode = g_breakdownAlgos[slotIdx].breakdown_streak_continuation_mode;

      FileWrite(fh,
         IntegerToString(algoNumber),
         BreakdownContinuationModeLogSlug(mode),
         IntegerToString(n),
         IntegerToString(acc.wins),
         IntegerToString(acc.losses),
         DoubleToString(winRate, 2),
         DoubleToString(acc.sumPriceDiff, _Digits),
         DoubleToString(avgPriceDiff, _Digits),
         (acc.telCount > 0 ? DoubleToString(avgMfe, 1) : ""),
         (acc.telCount > 0 ? DoubleToString(avgMae, 1) : ""),
         (n > 0 ? DoubleToString(avgLifetime, 1) : ""),
         (n > 0 ? DoubleToString(sumLifetimeMinutes, 1) : ""),
         (n > 0 ? DoubleToString(acc.sumLifetimeHours, 1) : ""),
         (n > 0 ? DoubleToString(sumLifetimeDays, 1) : ""),
         hoursVsPricediffRatio);
   }
   FileClose(fh);
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_BREAKDOWN_BENCHMARK_ALGOS, profT0);
}

//+------------------------------------------------------------------+
void BreakdownBenchmarkAllAlgosAccumulateClose(const int algoNumber, const double startPrice, const double endPrice,
   const double lifetimeHours, const double mfePts, const double maePts, const bool hasTel)
{
   if(!bigflipper_log_breakdown_trade_lifetime || startPrice <= 0.0 || endPrice <= 0.0)
      return;
   const int slotIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(slotIdx < 0)
      return;

   BreakdownAlgoBenchmarkAcc acc = g_breakdownAlgoBenchmarkAcc[slotIdx];
   const double priceDiff = endPrice - startPrice;
   acc.tradesClosed++;
   acc.sumPriceDiff += priceDiff;
   acc.sumLifetimeHours += lifetimeHours;
   if(priceDiff > 0.0)
      acc.wins++;
   else if(priceDiff < 0.0)
      acc.losses++;
   if(hasTel)
   {
      acc.sumMfePts += mfePts;
      acc.sumMaePts += maePts;
      acc.telCount++;
   }
   g_breakdownAlgoBenchmarkAcc[slotIdx] = acc;
   BreakdownBenchmarkAllAlgosWrite();
}

void BreakdownWriteTradeLifetimeRunLogHeader(const int fh)
{
   FileWrite(fh, "eventTime", "startTime", "eventType", "close_reason",
      "plannedPrice", "startPrice", "realSLprice", "realTPprice", "endPrice", "priceDiff", "lifetimeHours",
      "mfe", "mae", "trades_today", "trades_all");
}

void BreakdownResetTradeLifetimeRunLogsOnInit()
{
   BreakdownBenchmarkAllAlgosReset();
   if(!bigflipper_log_breakdown_trade_lifetime)
      return;
   for(int i = 0; i < g_breakdownAlgoCount; i++)
   {
      const int algoNumber = g_breakdownAlgos[i].algo_id;
      if(!IsBreakdownFamilyAlgoNumber(algoNumber))
         continue;
      const string fname = BreakdownTradeLifetimeRunLogFileName(algoNumber);
      int fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(fh == INVALID_HANDLE)
         continue;
      BreakdownWriteTradeLifetimeRunLogHeader(fh);
      FileClose(fh);
   }
   BreakdownBenchmarkAllAlgosWrite();
}

//+------------------------------------------------------------------+
void BreakdownRememberPendingPlannedPrice(const long magic, const double plannedPrice)
{
   if(magic <= 0 || plannedPrice <= 0.0)
      return;
   for(int i = 0; i < BREAKDOWN_PENDING_PLANNED_MAX; i++)
   {
      if(g_breakdownPendingPlannedPrice[i].active && g_breakdownPendingPlannedPrice[i].magic == magic)
      {
         g_breakdownPendingPlannedPrice[i].plannedPrice = plannedPrice;
         return;
      }
   }
   for(int i = 0; i < BREAKDOWN_PENDING_PLANNED_MAX; i++)
   {
      if(!g_breakdownPendingPlannedPrice[i].active)
      {
         g_breakdownPendingPlannedPrice[i].magic = magic;
         g_breakdownPendingPlannedPrice[i].plannedPrice = plannedPrice;
         g_breakdownPendingPlannedPrice[i].active = true;
         return;
      }
   }
}

//+------------------------------------------------------------------+
double BreakdownTakePendingPlannedPrice(const long magic)
{
   for(int i = 0; i < BREAKDOWN_PENDING_PLANNED_MAX; i++)
   {
      if(g_breakdownPendingPlannedPrice[i].active && g_breakdownPendingPlannedPrice[i].magic == magic)
      {
         const double p = g_breakdownPendingPlannedPrice[i].plannedPrice;
         g_breakdownPendingPlannedPrice[i].active = false;
         return p;
      }
   }
   return 0.0;
}

//+------------------------------------------------------------------+
void BreakdownRegisterOpenTradeLifetime(const ulong positionId, const int algoNumber,
   const datetime startTime, const datetime breakdownSequenceEndTime, const double plannedPrice, const double startPrice,
   const double realSLprice, const double realTPprice)
{
   if(positionId == 0 || algoNumber <= 0 || startTime <= 0)
      return;
   for(int i = 0; i < BREAKDOWN_OPEN_LIFETIME_MAX; i++)
   {
      if(g_breakdownOpenLifetime[i].active && g_breakdownOpenLifetime[i].positionId == positionId)
      {
         g_breakdownOpenLifetime[i].algoNumber = algoNumber;
         g_breakdownOpenLifetime[i].startTime = startTime;
         g_breakdownOpenLifetime[i].breakdownSequenceEndTime = breakdownSequenceEndTime;
         g_breakdownOpenLifetime[i].plannedPrice = plannedPrice;
         g_breakdownOpenLifetime[i].startPrice = startPrice;
         g_breakdownOpenLifetime[i].realSLprice = realSLprice;
         g_breakdownOpenLifetime[i].realTPprice = realTPprice;
         return;
      }
   }
   for(int i = 0; i < BREAKDOWN_OPEN_LIFETIME_MAX; i++)
   {
      if(!g_breakdownOpenLifetime[i].active)
      {
         g_breakdownOpenLifetime[i].positionId = positionId;
         g_breakdownOpenLifetime[i].algoNumber = algoNumber;
         g_breakdownOpenLifetime[i].startTime = startTime;
         g_breakdownOpenLifetime[i].breakdownSequenceEndTime = breakdownSequenceEndTime;
         g_breakdownOpenLifetime[i].plannedPrice = plannedPrice;
         g_breakdownOpenLifetime[i].startPrice = startPrice;
         g_breakdownOpenLifetime[i].realSLprice = realSLprice;
         g_breakdownOpenLifetime[i].realTPprice = realTPprice;
         g_breakdownOpenLifetime[i].active = true;
         return;
      }
   }
}

//+------------------------------------------------------------------+
bool BreakdownOpenLifetimeBreakdownEnd(const ulong positionId, datetime &outBreakdownEnd)
{
   outBreakdownEnd = 0;
   for(int i = 0; i < BREAKDOWN_OPEN_LIFETIME_MAX; i++)
   {
      if(g_breakdownOpenLifetime[i].active && g_breakdownOpenLifetime[i].positionId == positionId)
      {
         outBreakdownEnd = g_breakdownOpenLifetime[i].breakdownSequenceEndTime;
         return (outBreakdownEnd > 0);
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool BreakdownTakeOpenTradeLifetime(const ulong positionId, BreakdownOpenTradeLifetimeRec &outRec)
{
   ZeroMemory(outRec);
   for(int i = 0; i < BREAKDOWN_OPEN_LIFETIME_MAX; i++)
   {
      if(g_breakdownOpenLifetime[i].active && g_breakdownOpenLifetime[i].positionId == positionId)
      {
         outRec = g_breakdownOpenLifetime[i];
         g_breakdownOpenLifetime[i].active = false;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
void BreakdownRememberPendingCloseReason(const ulong positionId, const string reason)
{
   if(positionId == 0 || reason == "")
      return;
   for(int i = 0; i < BREAKDOWN_OPEN_LIFETIME_MAX; i++)
   {
      if(g_breakdownOpenLifetime[i].active && g_breakdownOpenLifetime[i].positionId == positionId)
         g_breakdownOpenLifetime[i].pendingCloseReason = reason;
   }
}

string BreakdownTradeLifetimeCloseReasonFromExit(const ENUM_DEAL_REASON dealReason,
   const ulong positionId, const long entryMagic, const datetime startTime);

string BreakdownLifetimeLogPriceCol(const double price)
{
   return (price > 0.0 ? DoubleToString(price, _Digits) : "");
}

void BreakdownResolveBrokerTpSlForLifetimeLog(const int algoNumber, const datetime atTime, const double plannedPrice,
   double &outRealSLprice, double &outRealTPprice)
{
   const int algoSlot = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(algoSlot < 0)
      return;
   const BreakdownAlgoDef bd = g_breakdownAlgos[algoSlot];
   const Breakdown15mState bdSnap = Breakdown15mSnapForAlgo(algoNumber, atTime);
   if(outRealTPprice <= 0.0 && bd.tp_enabled)
   {
      outRealTPprice = FalgoBreakdownPriceAtRangePercent(bdSnap.breakdownLow, bdSnap.startHigh,
         bd.tp_notsecret_range_percent);
   }
   if(outRealSLprice <= 0.0 && bd.sl_enabled && plannedPrice > 0.0 && bd.sl_points > 0.0)
      outRealSLprice = NormalizeDouble(plannedPrice - PointSized(bd.sl_points), _Digits);
}

//+------------------------------------------------------------------+
string BreakdownLifetimeLogTelemetryPtsCol(const double pts, const bool fill)
{
   if(!fill)
      return "";
   return DoubleToString(pts, 1);
}

//+------------------------------------------------------------------+
void BreakdownStashGatesCloseTelemetry(const int algoNumber, const datetime closeTime,
   const long entryMagic, const datetime startTime)
{
   const int slotIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(slotIdx < 0 || closeTime <= 0 || startTime <= 0)
      return;
   FalgoClosedTradeTelemetrySummary telSummary;
   if(!FalgoGetTelemetrySummaryForTrade(entryMagic, startTime, telSummary))
      return;
   g_breakdownGatesCloseTelBarTime[slotIdx] = closeTime - (closeTime % 60);
   g_breakdownGatesCloseTelMfePts[slotIdx] = telSummary.mfePts;
   g_breakdownGatesCloseTelMaePts[slotIdx] = telSummary.maePts;
   g_breakdownGatesCloseTelValid[slotIdx] = true;
}

//+------------------------------------------------------------------+
void BreakdownTakeGatesCloseTelemetryForBar(const int slotIdx, const datetime barOpenTime,
   double &outMfePts, double &outMaePts, bool &outFilled)
{
   outMfePts = 0.0;
   outMaePts = 0.0;
   outFilled = false;
   if(slotIdx < 0 || !g_breakdownGatesCloseTelValid[slotIdx])
      return;
   if(g_breakdownGatesCloseTelBarTime[slotIdx] != barOpenTime)
      return;
   outMfePts = g_breakdownGatesCloseTelMfePts[slotIdx];
   outMaePts = g_breakdownGatesCloseTelMaePts[slotIdx];
   outFilled = true;
   g_breakdownGatesCloseTelValid[slotIdx] = false;
}

//+------------------------------------------------------------------+
int BreakdownAlgoTradesTodayForLog(const int algoNumber)
{
   return BreakdownPlanTradeNumToday(algoNumber);
}

//+------------------------------------------------------------------+
int BreakdownAlgoTradesAllForLog(const int algoNumber)
{
   const int idx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return 0;
   return g_breakdownAlgoTradesAll[idx];
}

//+------------------------------------------------------------------+
void BreakdownAppendTradeLifetimeLogRow(const int algoNumber, const datetime eventTime, const datetime startTime,
   const string eventType, const string closeReason, const double plannedPrice, const double startPrice,
   const double realSLprice, const double realTPprice, const double endPrice, const double lifetimeHours,
   const double mfePts = 0.0, const double maePts = 0.0, const bool fillMaeMfe = false)
{
   if(!bigflipper_log_breakdown_trade_lifetime)
      return;
   if(!IsBreakdownFamilyAlgoNumber(algoNumber))
      return;

   const string fname = BreakdownTradeLifetimeRunLogFileName(algoNumber);
   int fh = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   FileSeek(fh, 0, SEEK_END);
   const bool hasEndPrice = (endPrice > 0.0);
   const string priceDiffStr = (hasEndPrice && startPrice > 0.0)
      ? DoubleToString(endPrice - startPrice, _Digits)
      : "";
   FileWrite(fh,
      TimeToString(eventTime, TIME_DATE|TIME_SECONDS),
      TimeToString(startTime, TIME_DATE|TIME_SECONDS),
      eventType,
      closeReason,
      DoubleToString(plannedPrice, _Digits),
      DoubleToString(startPrice, _Digits),
      BreakdownLifetimeLogPriceCol(realSLprice),
      BreakdownLifetimeLogPriceCol(realTPprice),
      (hasEndPrice ? DoubleToString(endPrice, _Digits) : ""),
      priceDiffStr,
      (eventType == "trade closed" ? DoubleToString(lifetimeHours, 2) : ""),
      BreakdownLifetimeLogTelemetryPtsCol(mfePts, fillMaeMfe),
      BreakdownLifetimeLogTelemetryPtsCol(maePts, fillMaeMfe),
      IntegerToString(BreakdownAlgoTradesTodayForLog(algoNumber)),
      IntegerToString(BreakdownAlgoTradesAllForLog(algoNumber)));
   FileClose(fh);
}

//+------------------------------------------------------------------+
void BreakdownLogTradeOpenedLifetime(const ulong positionId, const long magic, const datetime fillTime,
   const double fillPrice, const ulong orderTicket)
{
   if(!bigflipper_log_breakdown_trade_lifetime || !IsBreakdownFamilyCompositeMagic(magic))
      return;
   const int algoNumber = AlgoFamilyMagicNumber(magic);
   if(!IsBreakdownFamilyAlgoNumber(algoNumber))
      return;

   double plannedPrice = BreakdownTakePendingPlannedPrice(magic);
   if(plannedPrice <= 0.0 && orderTicket > 0 && HistoryOrderSelect(orderTicket))
      plannedPrice = HistoryOrderGetDouble(orderTicket, ORDER_PRICE_OPEN);
   if(plannedPrice <= 0.0)
      plannedPrice = fillPrice;

   const double startPrice = (fillPrice > 0.0 ? fillPrice : plannedPrice);
   const datetime startTime = (fillTime > 0 ? fillTime : g_lastTimer1Time);
   double realSLprice = 0.0;
   double realTPprice = 0.0;
   if(orderTicket > 0 && HistoryOrderSelect(orderTicket))
   {
      realTPprice = HistoryOrderGetDouble(orderTicket, ORDER_TP);
      realSLprice = HistoryOrderGetDouble(orderTicket, ORDER_SL);
   }
   BreakdownResolveBrokerTpSlForLifetimeLog(algoNumber, startTime, plannedPrice, realSLprice, realTPprice);
   RefreshGlobalBreakdown15mSnap(startTime);
   const Breakdown15mState bdSnap = Breakdown15mSnapForAlgo(algoNumber, startTime);
   const datetime breakdownEnd = bdSnap.endTime;
   BreakdownRegisterOpenTradeLifetime(positionId, algoNumber, startTime, breakdownEnd, plannedPrice, startPrice,
      realSLprice, realTPprice);
   const int algoIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(algoIdx >= 0)
      g_breakdownAlgoTradesAll[algoIdx]++;
   BreakdownAppendTradeLifetimeLogRow(algoNumber, startTime, startTime, "trade opened", "",
      plannedPrice, startPrice, realSLprice, realTPprice, 0.0, 0.0);
}

//+------------------------------------------------------------------+
void BreakdownLogTradeClosedLifetime(const ulong positionId, const long entryMagic, const datetime closeTime,
   const double closePriceIn, const ENUM_DEAL_REASON dealReason)
{
   if(!bigflipper_log_breakdown_trade_lifetime || !IsBreakdownFamilyCompositeMagic(entryMagic))
      return;

   BreakdownOpenTradeLifetimeRec openRec;
   datetime startTime = 0;
   double plannedPrice = 0.0;
   double startPrice = 0.0;
   double realSLprice = 0.0;
   double realTPprice = 0.0;
   string pendingCloseReason = "";
   int algoNumber = AlgoFamilyMagicNumber(entryMagic);
   ulong entryOrderTicket = 0;
   if(BreakdownTakeOpenTradeLifetime(positionId, openRec))
   {
      algoNumber = openRec.algoNumber;
      startTime = openRec.startTime;
      plannedPrice = openRec.plannedPrice;
      startPrice = openRec.startPrice;
      realSLprice = openRec.realSLprice;
      realTPprice = openRec.realTPprice;
      pendingCloseReason = openRec.pendingCloseReason;
   }
   else if(HistorySelectByPosition((long)positionId))
   {
      for(int j = 0; j < HistoryDealsTotal(); j++)
      {
         const ulong dealTicket = HistoryDealGetTicket(j);
         if(dealTicket == 0)
            continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_IN)
            continue;
         startTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
         startPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
         plannedPrice = startPrice;
         entryOrderTicket = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
         if(!IsBreakdownFamilyAlgoNumber(algoNumber))
            algoNumber = AlgoFamilyMagicNumber(HistoryDealGetInteger(dealTicket, DEAL_MAGIC));
         break;
      }
   }
   if(entryOrderTicket > 0 && HistoryOrderSelect(entryOrderTicket))
   {
      realTPprice = HistoryOrderGetDouble(entryOrderTicket, ORDER_TP);
      realSLprice = HistoryOrderGetDouble(entryOrderTicket, ORDER_SL);
   }
   if(startTime > 0)
      BreakdownResolveBrokerTpSlForLifetimeLog(algoNumber, startTime, plannedPrice, realSLprice, realTPprice);
   if(!IsBreakdownFamilyAlgoNumber(algoNumber) || startTime <= 0)
      return;

   double closePrice = closePriceIn;
   if(closePrice <= 0.0 && HistorySelectByPosition((long)positionId))
   {
      for(int j = HistoryDealsTotal() - 1; j >= 0; j--)
      {
         const ulong dealTicket = HistoryDealGetTicket(j);
         if(dealTicket == 0)
            continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
            continue;
         closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
         break;
      }
   }

   const datetime eventTime = (closeTime > 0 ? closeTime : g_lastTimer1Time);
   const double lifetimeHours = (double)MathMax(0, eventTime - startTime) / 3600.0;
   string closeReason = pendingCloseReason;
   if(closeReason == "")
      closeReason = BreakdownTradeLifetimeCloseReasonFromExit(dealReason, positionId, entryMagic, startTime);
   FalgoClosedTradeTelemetrySummary telSummary;
   const bool hasTel = FalgoGetTelemetrySummaryForTrade(entryMagic, startTime, telSummary);
   BreakdownStashGatesCloseTelemetry(algoNumber, eventTime, entryMagic, startTime);
   BreakdownAppendTradeLifetimeLogRow(algoNumber, eventTime, startTime, "trade closed", closeReason,
      plannedPrice, startPrice, realSLprice, realTPprice, closePrice, lifetimeHours,
      telSummary.mfePts, telSummary.maePts, hasTel);
   BreakdownBenchmarkAllAlgosAccumulateClose(algoNumber, startPrice, closePrice, lifetimeHours,
      telSummary.mfePts, telSummary.maePts, hasTel);
}

//+------------------------------------------------------------------+
string FalgoEodTradeResultsDailyCsvName(const string dateStr, const int algoNumber)
{
   if(IsBreakdownFamilyAlgoNumber(algoNumber))
      return dateStr + "_summaryZ_tradeResults_ALL_Day_bdalgo" + IntegerToString(algoNumber) + ".csv";
   return dateStr + "_summaryZ_tradeResults_ALL_Day_algo" + IntegerToString(algoNumber) + ".csv";
}

//+------------------------------------------------------------------+
string FalgoAllDaysSummaryFileNameForAlgo(const int algoNumber)
{
   if(IsBreakdownFamilyAlgoNumber(algoNumber))
      return "summary_tradeResults_all_days_bdalgo" + IntegerToString(algoNumber) + ".tsv";
   return "summary_tradeResults_all_days_algo" + IntegerToString(algoNumber) + ".tsv";
}

//+------------------------------------------------------------------+
bool FalgoAlgoRegisteredForEodTradeResults(const int algoNumber)
{
   return (AlgoSlotIndexByAlgoId(algoNumber) >= 0 || BreakdownAlgoSlotIndexByAlgoId(algoNumber) >= 0);
}

//+------------------------------------------------------------------+
void RebuildAlgoSlotsRegistry()
{
   g_algoCount = 0;
   const int n = ArraySize(g_algoRegistryIds);
   for(int i = 0; i < n; i++)
   {
      if(g_algoCount >= ALGO_FAMILY_REGISTRY_MAX)
         FatalError("RebuildAlgoSlotsRegistry: ALGO_FAMILY_REGISTRY_MAX exceeded");
      g_algos[g_algoCount].algo_id = g_algoRegistryIds[i];
      g_algos[g_algoCount].trades_short = false;
      g_algoCount++;
   }
   if(ALGO_FAMILY_REGISTRY_MAX > g_algoCount + ALGO_FAMILY_REGISTRY_MAX_HEADROOM)
      FatalError(StringFormat(
         "ALGO_FAMILY_REGISTRY_MAX=%d exceeds wired algo count %d by more than %d — lower #define ALGO_FAMILY_REGISTRY_MAX (comment //algobookmarkMAX)",
         ALGO_FAMILY_REGISTRY_MAX, g_algoCount, ALGO_FAMILY_REGISTRY_MAX_HEADROOM));
}

//+------------------------------------------------------------------+
int AlgoSlotIndexByAlgoId(const int algoNumber)
{
   for(int i = 0; i < g_algoCount; i++)
   {
      if(g_algos[i].algo_id == algoNumber)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
int AlgoFamilySlotArrayIndex(const int algoNumber)
{
   return AlgoSlotIndexByAlgoId(algoNumber);
}

//+------------------------------------------------------------------+
bool AlgoSlotTradesShort(const int algoNumber)
{
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   return g_algos[idx].trades_short;
}

//+------------------------------------------------------------------+
bool AlgoProfileEnabled(const int algoNumber)
{
   if(IsBreakdownFamilyAlgoNumber(algoNumber))
   {
      const int idx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
      if(idx < 0)
         return false;
      return g_breakdownAlgos[idx].enabled;
   }
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   return g_algos[idx].enabled;
}

//+------------------------------------------------------------------+
bool AlgoFamilyBlocksPlacementOnOpenOrPending()
{
   return g_algoShared.blockPlacementIfFamilyOpenOrPending;
}

//+------------------------------------------------------------------+
bool AlgoLoadTuneForAlgo(const int algoNumber, AlgoPerAlgoTune &outTune)
{
   if(IsBreakdownFamilyAlgoNumber(algoNumber))
      return false;
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   outTune = g_algos[idx].tune;
   return true;
}

int AlgoFamilyMagicNumber(const long magic)
{
   string s = MagicNumberToFixedWidthString(magic);
   if(StringLen(s) < FALGO_MAGIC_LENGTH_ALGO)
      return -1;
   return (int)StringToInteger(StringSubstr(s, 0, FALGO_MAGIC_LENGTH_ALGO));
}

//+------------------------------------------------------------------+
bool IsShortAlgoCompositeMagic(const long magic)
{
   return AlgoSlotTradesShort(AlgoFamilyMagicNumber(magic));
}

//+------------------------------------------------------------------+
bool IsAlgoCompositeMagic(const long magic, const int algoNumber)
{
   return (AlgoFamilyMagicNumber(magic) == algoNumber);
}

//+------------------------------------------------------------------+
bool IsAnyAlgoFamilyCompositeMagic(const long magic)
{
   const int algoNumber = AlgoFamilyMagicNumber(magic);
   return IsLevelFamilyAlgoNumber(algoNumber) || IsBreakdownFamilyAlgoNumber(algoNumber);
}

//+------------------------------------------------------------------+
//| (date)_algo{N}_{suffix}.csv — e.g. 20260511_algo10_gates_per_minute.csv |
//+------------------------------------------------------------------+
string AlgoFamilyCsvFileName(const string dateStr, const int algoNumber, const string suffix)
{
   return dateStr + "_algo" + IntegerToString(algoNumber) + "_" + suffix + ".csv";
}


//+------------------------------------------------------------------+
//| Algo family (algo 100..999): Falgo* helpers, pipelines, telemetry, EOD logs (inline below). |
//+------------------------------------------------------------------+


//--- Falgo magic layout (18 decimal digits; index 0 = digit 1)
#define FALGO_MAGIC_INDEX_ALGO            0   // 100..999
#define FALGO_MAGIC_INDEX_DIRECTION       3   // 1|2|3|4 long/short variants
#define FALGO_MAGIC_LENGTH_DIRECTION      1
#define FALGO_MAGIC_INDEX_DAY_OF_WEEK     4   // 1..5 Mon..Fri
#define FALGO_MAGIC_LENGTH_DAY_OF_WEEK    1
#define FALGO_MAGIC_INDEX_LEVEL_SLOT      5   // %02d level tag slot (00=RTHO; 01=PDC; 10..35 weekly; 50..80 daily)
#define FALGO_MAGIC_LENGTH_LEVEL_SLOT     2
#define FALGO_MAGIC_INDEX_BOUNCE          7   // 0..8 capped
#define FALGO_MAGIC_LENGTH_BOUNCE         1
#define FALGO_MAGIC_INDEX_CEILING         8   // 0..8 capped
#define FALGO_MAGIC_LENGTH_CEILING        1
#define FALGO_MAGIC_INDEX_OFFSET          9   // %02d tenths (long or short offset for this plan)
#define FALGO_MAGIC_LENGTH_OFFSET         2
#define FALGO_MAGIC_INDEX_PLAN_TRADE_NUM  11  // 0..8
#define FALGO_MAGIC_LENGTH_PLAN_TRADE_NUM 1
#define FALGO_MAGIC_INDEX_LEVEL_TRADE_NUM 12  // 0..8
#define FALGO_MAGIC_LENGTH_LEVEL_TRADE_NUM 1
#define FALGO_MAGIC_INDEX_BABYSIT_MIN     13  // 0..9
#define FALGO_MAGIC_LENGTH_BABYSIT_MIN    1
#define FALGO_MAGIC_INDEX_TP              14  // %02d whole points
#define FALGO_MAGIC_LENGTH_TP             2
#define FALGO_MAGIC_INDEX_SL              16  // %02d whole points
#define FALGO_MAGIC_LENGTH_SL             2

#define FALGO_MAGIC_LEVEL_SLOT_RTHO          0   // todayRTHopen
#define FALGO_MAGIC_LEVEL_SLOT_PDRTHCLOSE    1   // PDrthClose (prior day RTH close)
#define FALGO_MAGIC_LEVEL_SLOT_BREAKDOWN     2   // breakdown midpoint (no level row)
#define FALGO_MAGIC_LEVEL_SLOT_TERTIARY      0   // alias: todayRTHopen
#define FALGO_MAGIC_LEVEL_SLOT_WEEKLY_MIN   10
#define FALGO_MAGIC_LEVEL_SLOT_WEEKLY_MAX   35
#define FALGO_MAGIC_LEVEL_SLOT_WEEKLY_PIVOT 20
#define FALGO_MAGIC_LEVEL_SLOT_DAILY_MIN    50
#define FALGO_MAGIC_LEVEL_SLOT_DAILY_MAX    80
#define FALGO_MAGIC_LEVEL_SLOT_DAILY_PIVOT  60
#define FALGO_MAGIC_LEVEL_SLOT_COUNT        100
#define FALGO_DIRECTION_LONG_LIMIT        1
#define FALGO_DIRECTION_SHORT_LIMIT       2
#define FALGO_DIRECTION_LONG_ALT          3
#define FALGO_DIRECTION_SHORT_ALT         4

//+------------------------------------------------------------------+
double AlgoExtraOffsetForDirection(const int direction)
{
   if(direction == FALGO_DIRECTION_LONG_LIMIT || direction == FALGO_DIRECTION_LONG_ALT)
      return g_algoShared.extra_offset_all_longs;
   if(direction == FALGO_DIRECTION_SHORT_LIMIT || direction == FALGO_DIRECTION_SHORT_ALT)
      return g_algoShared.extra_offset_all_shorts;
   return 0.0;
}

//+------------------------------------------------------------------+
bool AlgoPlacementParamsForAlgo(const int algoNumber, const int direction, double &offsetPoints, double &proximityLimit, int &expirationMin)
{
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   offsetPoints = g_algos[idx].levelOffset + AlgoExtraOffsetForDirection(direction);
   proximityLimit = g_algos[idx].priceProximity;
   expirationMin = g_algos[idx].expiry_minutes;
   return true;
}

#define FALGO_BANNED_RANGES_MAX           8

struct BannedRangeMinutes { int startMin; int endMin; };
BannedRangeMinutes g_falgoBannedRanges[FALGO_BANNED_RANGES_MAX];
int g_falgoBannedRangeCount = 0;
datetime g_falgoPlanCountersDayStart = 0;
datetime g_falgoDayTradeCountsDayStart = 0;
int g_algoPlanTradeNumToday[ALGO_FAMILY_REGISTRY_MAX];  // per wired algo (10–15); next plan # = count+1
int g_algoLevelTradeNumByMagicSlot[ALGO_FAMILY_REGISTRY_MAX][FALGO_MAGIC_LEVEL_SLOT_COUNT];
int g_algoDayWins[ALGO_FAMILY_REGISTRY_MAX];
int g_algoDayLosses[ALGO_FAMILY_REGISTRY_MAX];
int g_algoFamilyDayWins = 0;
int g_algoFamilyDayLosses = 0;
double g_algoFamilyDayGrossProfit = 0.0;
double g_algoFamilyDayGrossLossAbs = 0.0;
int g_falgoFamilyLastClosedBarIdx = -1;
bool g_algoFamilyHadCloseThisPipelinePass = false;

//+------------------------------------------------------------------+
datetime FalgoTradingDayStart()
{
   if(g_m1DayStart != 0)
      return g_m1DayStart;
   if(g_lastTimer1Time > 0)
      return g_lastTimer1Time - (g_lastTimer1Time % 86400);
   return 0;
}

//+------------------------------------------------------------------+
bool FalgoTradeStartedOnTradingDay(const TradeResult &tr, const datetime dayStart)
{
   if(dayStart == 0)
      return true;
   const datetime dayEnd = dayStart + 86400;
   datetime t = tr.startTime;
   if(t == 0)
      t = tr.sentTime;
   return (t >= dayStart && t < dayEnd);
}

//+------------------------------------------------------------------+
bool FalgoBarIsDedicatedToTradeCloseForFamily(const int barIdx)
{
   if(!AlgoFamilyBlocksPlacementOnOpenOrPending())
      return false;
   if(g_algoFamilyHadCloseThisPipelinePass)
      return true;
   if(g_falgoFamilyLastClosedBarIdx >= 0 && barIdx == g_falgoFamilyLastClosedBarIdx)
      return true;
   return false;
}

//+------------------------------------------------------------------+
void FalgoResetAllDayCounterStateForNewTradingDay()
{
   for(int si = 0; si < ALGO_FAMILY_REGISTRY_MAX; si++)
   {
      g_algoDayWins[si] = 0;
      g_algoDayLosses[si] = 0;
      g_algoPlanTradeNumToday[si] = 0;
      for(int levelSlot = 0; levelSlot < FALGO_MAGIC_LEVEL_SLOT_COUNT; levelSlot++)
         g_algoLevelTradeNumByMagicSlot[si][levelSlot] = 0;
   }
   g_algoFamilyDayWins = 0;
   g_algoFamilyDayLosses = 0;
   g_algoFamilyDayGrossProfit = 0.0;
   g_algoFamilyDayGrossLossAbs = 0.0;
   g_falgoFamilyLastClosedBarIdx = -1;
   g_algoFamilyHadCloseThisPipelinePass = false;
   for(int ri = 0; ri < ALGO_FAMILY_REGISTRY_MAX; ri++)
      g_falgoLastTradeClosedBarIdx[ri] = -1;
}

//+------------------------------------------------------------------+
bool AlgoFamilyAnyEnabled()
{
   for(int i = 0; i < g_algoCount; i++)
   {
      if(g_algos[i].enabled)
         return true;
   }
   for(int i = 0; i < g_breakdownAlgoCount; i++)
   {
      if(g_breakdownAlgos[i].enabled)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool AlgoSlotEnabled(const int algoNumber)
{
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   return AlgoProfileEnabled(algoNumber);
}

//+------------------------------------------------------------------+
bool AlgoDailySpamLogGatesEnabled(const int algoNumber)
{
   if(!bigflipper_log_algo_gates_per_minute)
      return false;
   return AlgoSlotEnabled(algoNumber);
}

//+------------------------------------------------------------------+
bool AlgoEodTradeResultsLoggingEnabled(const int algoNumber)
{
   if(!bigflipper_log_algo_trade_results_csv)
      return false;
   return FalgoAlgoRegisteredForEodTradeResults(algoNumber);
}

//+------------------------------------------------------------------+
bool AlgoEodTradeResultsAllDaysPerAlgoLoggingEnabled(const int algoNumber)
{
   if(!bigflipper_log_summary_tradeResults_all_days_algo)
      return false;
   return FalgoAlgoRegisteredForEodTradeResults(algoNumber);
}

//+------------------------------------------------------------------+
bool AlgoFamilyEodTradeResultsAllDaysLoggingEnabled()
{
   return bigflipper_log_summary_tradeResults_all_days;
}

//+------------------------------------------------------------------+
bool BreakdownFamilyEodTradeResultsAllDaysLoggingEnabled()
{
   return bigflipper_log_summary_tradeResults_all_days_breakdown;
}

//+------------------------------------------------------------------+
bool AlgoLoadPerAlgoTune(const int algoNumber, AlgoPerAlgoTune &outTune)
{
   return AlgoLoadTuneForAlgo(algoNumber, outTune);
}

//+------------------------------------------------------------------+
bool BreakdownAlgoSlotEnabled(const int algoNumber)
{
   const int idx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   return g_breakdownAlgos[idx].enabled;
}

//+------------------------------------------------------------------+
bool BreakdownFamilyBlocksPlacementOnOpenOrPending()
{
   return g_breakdownAlgoShared.blockPlacementIfFamilyOpenOrPending;
}

//+------------------------------------------------------------------+
//| Placement only (new orders): trading day + banned-time windows. Babysit/secretTP/SL ignore trading time. |
//+------------------------------------------------------------------+
bool BreakdownProfileAllowsPlacementAtTime(const datetime t)
{
   bool anyEnabled = false;
   for(int i = 0; i < g_breakdownAlgoCount; i++)
   {
      if(g_breakdownAlgos[i].enabled)
      {
         anyEnabled = true;
         break;
      }
   }
   if(!anyEnabled)
      return false;
   if(!FalgoIsTradingDayAllowedAtTime(t))
      return false;
   if(!FalgoIsTradingTimeAllowed(t))
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool BreakdownProfileAllowsNewOrdersNow()
{
   return BreakdownProfileAllowsPlacementAtTime(g_lastTimer1Time);
}

//+------------------------------------------------------------------+
double GetTradeLotForBreakdown()
{
   return g_global_base_trade_size * ((double)g_breakdownAlgoShared.tradeSizePct / 100.0);
}

//+------------------------------------------------------------------+
bool BreakdownRulesetPassesDayStops(const int algoNumber)
{
   const int idx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(idx >= 0)
   {
      const BreakdownAlgoDef bd = g_breakdownAlgos[idx];
      if(g_breakdownAlgoDayLosses[idx] >= bd.stop_trading_today_if_thisAlgo_losing_trades_count)
         return false;
      if(g_breakdownAlgoDayWins[idx] >= bd.stop_trading_today_if_thisAlgo_winning_trades_count)
         return false;
      if(g_breakdownAlgoDayWins[idx] + g_breakdownAlgoDayLosses[idx] >= bd.stop_trading_today_if_thisAlgo_total_trades_count)
         return false;
   }
   if(g_breakdownFamilyDayLosses >= g_breakdownAlgoShared.stop_trading_today_if_AllAlgos_losing_trades_count)
      return false;
   if(g_breakdownFamilyDayWins >= g_breakdownAlgoShared.stop_trading_today_if_AllAlgos_winning_trades_count)
      return false;
   return true;
}

//+------------------------------------------------------------------+
double BreakdownFamilyDayProfitFactorToday()
{
   return ProfitFactorFromGross(g_breakdownFamilyDayGrossProfit, g_breakdownFamilyDayGrossLossAbs);
}

//+------------------------------------------------------------------+
string BreakdownFamilyDayStopFirstFailLabel()
{
   if(g_breakdownAlgoShared.stop_trading_if_day_has_X_wins_0_losses > 0 &&
      g_breakdownFamilyDayLosses == 0 &&
      g_breakdownFamilyDayWins >= g_breakdownAlgoShared.stop_trading_if_day_has_X_wins_0_losses)
   {
      return StringFormat("familyWinStop(%d wins 0 losses vs %d)",
         g_breakdownFamilyDayWins, g_breakdownAlgoShared.stop_trading_if_day_has_X_wins_0_losses);
   }
   if(g_breakdownAlgoShared.stop_trading_if_day_has_profit_factor_above > 0.0 &&
      g_breakdownFamilyDayLosses >= 1)
   {
      const double pf = BreakdownFamilyDayProfitFactorToday();
      if(pf > g_breakdownAlgoShared.stop_trading_if_day_has_profit_factor_above)
      {
         return StringFormat("familyProfitFactorStop(%s vs %s)",
            FormatDayProfitFactorForCsv(pf),
            DoubleToString(g_breakdownAlgoShared.stop_trading_if_day_has_profit_factor_above, 1));
      }
   }
   return "";
}

//+------------------------------------------------------------------+
int FalgoRegistrySlotForAlgoNumber(const int algoNumber)
{
   return AlgoSlotIndexByAlgoId(algoNumber);
}

//+------------------------------------------------------------------+
bool FalgoBarIsDedicatedToTradeCloseForAlgo(const int barIdx, const int algoSlot1)
{
   const int ri = FalgoRegistrySlotForAlgoNumber(algoSlot1);
   if(ri < 0 || barIdx < 0 || barIdx >= g_barsInDay)
      return false;
   if(barIdx >= 0 && g_falgoLastTradeClosedBarIdx[ri] >= 0 && barIdx == g_falgoLastTradeClosedBarIdx[ri])
      return true;
   if(!g_falgoTelemetryAtBar[barIdx][ri].valid)
      return false;
   return g_falgoTelemetryAtBar[barIdx][ri].tradeClosedOnThisBar;
}

//+------------------------------------------------------------------+
bool FalgoRulesetPassesCloseBarForAlgo(const int algoSlot1, const int barIdx)
{
   if(FalgoBarIsDedicatedToTradeCloseForAlgo(barIdx, algoSlot1))
      return false;
   if(FalgoBarIsDedicatedToTradeCloseForFamily(barIdx))
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool BreakdownRulesetPassesCommonForPlacement(const int algoNumber, const int barIdx)
{
   if(!FalgoRulesetPassesCloseBarForAlgo(algoNumber, barIdx))
      return false;
   if(!BreakdownRulesetPassesDayStops(algoNumber))
      return false;
   if(!BreakdownUnderMaxOpenPositionsLimit(algoNumber))
      return false;
   if(BreakdownFamilyBlocksPlacementOnOpenOrPending())
   {
      if(BreakdownHasOpenPositionOnSymbol())
         return false;
      if(BreakdownHasPendingOrderOnSymbol())
         return false;
      if(g_breakdownFamilyHadCloseThisPipelinePass)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool BreakdownHasOpenPositionOnSymbol()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!ExtPositionInfo.SelectByIndex(i))
         continue;
      if(ExtPositionInfo.Symbol() != _Symbol)
         continue;
      if(IsBreakdownFamilyCompositeMagic(ExtPositionInfo.Magic()))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool BreakdownHasPendingOrderOnSymbol()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ExtOrderInfo.SelectByIndex(i))
         continue;
      if(ExtOrderInfo.Symbol() != _Symbol)
         continue;
      if(IsBreakdownFamilyCompositeMagic(ExtOrderInfo.Magic()))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int BreakdownOccupiedTradeSlotsForAlgo(const int algoNumber)
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!ExtPositionInfo.SelectByIndex(i))
         continue;
      if(ExtPositionInfo.Symbol() != _Symbol)
         continue;
      const long m = ExtPositionInfo.Magic();
      if(!IsBreakdownFamilyCompositeMagic(m))
         continue;
      if(AlgoFamilyMagicNumber(m) == algoNumber)
         n++;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ExtOrderInfo.SelectByIndex(i))
         continue;
      if(ExtOrderInfo.Symbol() != _Symbol)
         continue;
      const long m = ExtOrderInfo.Magic();
      if(!IsBreakdownFamilyCompositeMagic(m))
         continue;
      if(AlgoFamilyMagicNumber(m) == algoNumber)
         n++;
   }
   return n;
}

//+------------------------------------------------------------------+
bool BreakdownUnderMaxOpenPositionsLimit(const int algoNumber)
{
   BreakdownAlgoDef bd;
   if(!BreakdownAlgoDefForNumber(algoNumber, bd))
      return true;
   if(bd.max_open_positions <= 0)
      return true;
   return BreakdownOccupiedTradeSlotsForAlgo(algoNumber) < bd.max_open_positions;
}

//+------------------------------------------------------------------+
string BreakdownMaxOpenPositionsFailLabel(const int algoNumber)
{
   if(BreakdownUnderMaxOpenPositionsLimit(algoNumber))
      return "";
   BreakdownAlgoDef bd;
   if(!BreakdownAlgoDefForNumber(algoNumber, bd))
      return "maxOpenPositionsReached";
   return StringFormat("maxOpenPositionsReached(%d/%d)",
      BreakdownOccupiedTradeSlotsForAlgo(algoNumber), bd.max_open_positions);
}

//+------------------------------------------------------------------+
int BreakdownPlanTradeNumToday(const int algoNumber)
{
   const int idx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return 0;
   return g_breakdownAlgoPlanTradeNumToday[idx];
}

//+------------------------------------------------------------------+
int BreakdownLevelTradeNumTodayAtMagicLevelSlot(const int algoNumber, const int levelSlot)
{
   const int idx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0 || levelSlot < 0 || levelSlot >= FALGO_MAGIC_LEVEL_SLOT_COUNT)
      return 0;
   return g_breakdownAlgoLevelTradeNumToday[idx];
}

//+------------------------------------------------------------------+
void BreakdownBumpPlanCountersAfterPlacement(const int algoNumber, const int levelSlot)
{
   const int algoIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(algoIdx < 0)
      return;
   g_breakdownAlgoPlanTradeNumToday[algoIdx]++;
   if(FalgoMagicLevelSlotIsValid(levelSlot))
      g_breakdownAlgoLevelTradeNumToday[algoIdx]++;
}

//+------------------------------------------------------------------+
void UpdateBreakdownDayTradeCounts()
{
   const datetime dayStart = FalgoTradingDayStart();
   static datetime s_breakdownDayTradeCountsDayStart = 0;
   if(dayStart != 0 && s_breakdownDayTradeCountsDayStart != dayStart)
   {
      s_breakdownDayTradeCountsDayStart = dayStart;
      g_breakdownFamilyDayWins = 0;
      g_breakdownFamilyDayLosses = 0;
      g_breakdownFamilyDayGrossProfit = 0.0;
      g_breakdownFamilyDayGrossLossAbs = 0.0;
      for(int si = 0; si < BREAKDOWN_ALGO_REGISTRY_MAX; si++)
      {
         g_breakdownAlgoDayWins[si] = 0;
         g_breakdownAlgoDayLosses[si] = 0;
         g_breakdownAlgoPlanTradeNumToday[si] = 0;
         g_breakdownAlgoLevelTradeNumToday[si] = 0;
         g_breakdownAlgoLastPlacedEndTime[si] = 0;
         g_breakdownAlgoLastPlacedStartHigh[si] = 0.0;
         g_breakdownAlgoLastPlacedBreakdownLow[si] = 0.0;
      }
   }

   SyncBreakdownPlanCountersFromTradeResults();

   int histFamilyWins = 0, histFamilyLosses = 0;
   int histAlgoWins[BREAKDOWN_ALGO_REGISTRY_MAX];
   int histAlgoLosses[BREAKDOWN_ALGO_REGISTRY_MAX];
   for(int si = 0; si < BREAKDOWN_ALGO_REGISTRY_MAX; si++)
   {
      histAlgoWins[si] = 0;
      histAlgoLosses[si] = 0;
   }
   const datetime dayEnd = (dayStart != 0) ? (dayStart + 86400) : 0;
   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      if(!g_tradeResults[i].foundOut)
         continue;
      if(!IsBreakdownFamilyCompositeMagic(g_tradeResults[i].magic))
         continue;
      if(dayStart != 0 && (g_tradeResults[i].endTime < dayStart || g_tradeResults[i].endTime >= dayEnd))
         continue;
      const int algoIdx = BreakdownAlgoSlotIndexByAlgoId(AlgoFamilyMagicNumber(g_tradeResults[i].magic));
      if(g_tradeResults[i].profit > 0.0)
      {
         histFamilyWins++;
         if(algoIdx >= 0)
            histAlgoWins[algoIdx]++;
      }
      else if(g_tradeResults[i].profit < 0.0)
      {
         histFamilyLosses++;
         if(algoIdx >= 0)
            histAlgoLosses[algoIdx]++;
      }
   }
   g_breakdownFamilyDayWins = MathMax(g_breakdownFamilyDayWins, histFamilyWins);
   g_breakdownFamilyDayLosses = MathMax(g_breakdownFamilyDayLosses, histFamilyLosses);
   for(int si = 0; si < BREAKDOWN_ALGO_REGISTRY_MAX; si++)
   {
      g_breakdownAlgoDayWins[si] = MathMax(g_breakdownAlgoDayWins[si], histAlgoWins[si]);
      g_breakdownAlgoDayLosses[si] = MathMax(g_breakdownAlgoDayLosses[si], histAlgoLosses[si]);
   }
}

//+------------------------------------------------------------------+
bool AlgoLoadPerAlgoTuneForMagic(const long magic, AlgoPerAlgoTune &outTune)
{
   return AlgoLoadPerAlgoTune(AlgoFamilyMagicNumber(magic), outTune);
}

//+------------------------------------------------------------------+
int AlgoDayWinsForSlot(const int algoSlot1)
{
   const int idx = AlgoFamilySlotArrayIndex(algoSlot1);
   if(idx < 0)
      return 0;
   return g_algoDayWins[idx];
}

//+------------------------------------------------------------------+
int AlgoDayLossesForSlot(const int algoSlot1)
{
   const int idx = AlgoFamilySlotArrayIndex(algoSlot1);
   if(idx < 0)
      return 0;
   return g_algoDayLosses[idx];
}

//+------------------------------------------------------------------+
double AlgoFamilyDayProfitFactorToday()
{
   return ProfitFactorFromGross(g_algoFamilyDayGrossProfit, g_algoFamilyDayGrossLossAbs);
}

//+------------------------------------------------------------------+
string AlgoFamilyDayStopFirstFailLabel()
{
   if(g_algoShared.stop_trading_if_day_has_X_wins_0_losses > 0 &&
      g_algoFamilyDayLosses == 0 &&
      g_algoFamilyDayWins >= g_algoShared.stop_trading_if_day_has_X_wins_0_losses)
   {
      return StringFormat("familyWinStop(%d wins 0 losses vs %d)",
         g_algoFamilyDayWins, g_algoShared.stop_trading_if_day_has_X_wins_0_losses);
   }
   if(g_algoShared.stop_trading_if_day_has_profit_factor_above > 0.0 &&
      g_algoFamilyDayLosses >= 1)
   {
      const double pf = AlgoFamilyDayProfitFactorToday();
      if(pf > g_algoShared.stop_trading_if_day_has_profit_factor_above)
      {
         return StringFormat("familyProfitFactorStop(%s vs %s)",
            FormatDayProfitFactorForCsv(pf),
            DoubleToString(g_algoShared.stop_trading_if_day_has_profit_factor_above, 1));
      }
   }
   return "";
}

//+------------------------------------------------------------------+
bool AlgoFamilyDayAllowsNewTrades()
{
   return (AlgoFamilyDayStopFirstFailLabel() == "");
}

//+------------------------------------------------------------------+
bool AlgoRulesetPassesDayStops(const int algoSlot1)
{
   if(IsBreakdownFamilyAlgoNumber(algoSlot1))
      return BreakdownRulesetPassesDayStops(algoSlot1);
   AlgoPerAlgoTune tune;
   if(!AlgoLoadPerAlgoTune(algoSlot1, tune))
      return true;
   const int idx = AlgoFamilySlotArrayIndex(algoSlot1);
   if(idx >= 0)
   {
      if(g_algoDayLosses[idx] >= tune.stop_trading_today_if_thisAlgo_losing_trades_count)
         return false;
      if(g_algoDayWins[idx] >= tune.stop_trading_today_if_thisAlgo_winning_trades_count)
         return false;
      if(g_algoDayWins[idx] + g_algoDayLosses[idx] >= tune.stop_trading_today_if_thisAlgo_total_trades_count)
         return false;
   }
   if(g_algoFamilyDayLosses >= g_algoShared.stop_trading_today_if_AllAlgos_losing_trades_count)
      return false;
   if(g_algoFamilyDayWins >= g_algoShared.stop_trading_today_if_AllAlgos_winning_trades_count)
      return false;
   if(!AlgoFamilyDayAllowsNewTrades())
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool AlgoDayStopUnderLossLimit(const int algoSlot1, bool &outUnderThisAlgo, bool &outUnderAllAlgos)
{
   outUnderThisAlgo = true;
   outUnderAllAlgos = true;
   AlgoPerAlgoTune tune;
   if(!AlgoLoadPerAlgoTune(algoSlot1, tune))
      return (outUnderThisAlgo && outUnderAllAlgos);
   if(IsBreakdownFamilyAlgoNumber(algoSlot1))
   {
      const int idx = BreakdownAlgoSlotIndexByAlgoId(algoSlot1);
      if(idx >= 0)
      {
         const BreakdownAlgoDef bd = g_breakdownAlgos[idx];
         outUnderThisAlgo = (g_breakdownAlgoDayLosses[idx] < bd.stop_trading_today_if_thisAlgo_losing_trades_count);
      }
      outUnderAllAlgos = (g_breakdownFamilyDayLosses < g_breakdownAlgoShared.stop_trading_today_if_AllAlgos_losing_trades_count);
      return (outUnderThisAlgo && outUnderAllAlgos);
   }
   const int idx = AlgoFamilySlotArrayIndex(algoSlot1);
   if(idx >= 0)
      outUnderThisAlgo = (g_algoDayLosses[idx] < tune.stop_trading_today_if_thisAlgo_losing_trades_count);
   outUnderAllAlgos = (g_algoFamilyDayLosses < g_algoShared.stop_trading_today_if_AllAlgos_losing_trades_count);
   return (outUnderThisAlgo && outUnderAllAlgos);
}

//+------------------------------------------------------------------+
bool AlgoDayStopUnderWinLimit(const int algoSlot1, bool &outUnderThisAlgo, bool &outUnderAllAlgos)
{
   outUnderThisAlgo = true;
   outUnderAllAlgos = true;
   AlgoPerAlgoTune tune;
   if(!AlgoLoadPerAlgoTune(algoSlot1, tune))
      return (outUnderThisAlgo && outUnderAllAlgos);
   if(IsBreakdownFamilyAlgoNumber(algoSlot1))
   {
      const int idx = BreakdownAlgoSlotIndexByAlgoId(algoSlot1);
      if(idx >= 0)
      {
         const BreakdownAlgoDef bd = g_breakdownAlgos[idx];
         outUnderThisAlgo = (g_breakdownAlgoDayWins[idx] < bd.stop_trading_today_if_thisAlgo_winning_trades_count);
      }
      outUnderAllAlgos = (g_breakdownFamilyDayWins < g_breakdownAlgoShared.stop_trading_today_if_AllAlgos_winning_trades_count);
      return (outUnderThisAlgo && outUnderAllAlgos);
   }
   const int idx = AlgoFamilySlotArrayIndex(algoSlot1);
   if(idx >= 0)
      outUnderThisAlgo = (g_algoDayWins[idx] < tune.stop_trading_today_if_thisAlgo_winning_trades_count);
   outUnderAllAlgos = (g_algoFamilyDayWins < g_algoShared.stop_trading_today_if_AllAlgos_winning_trades_count);
   return (outUnderThisAlgo && outUnderAllAlgos);
}

//+------------------------------------------------------------------+
int AlgoPlanTradeNumToday(const int algoSlot1)
{
   const int idx = AlgoFamilySlotArrayIndex(algoSlot1);
   if(idx < 0)
      return 0;
   return g_algoPlanTradeNumToday[idx];
}

//+------------------------------------------------------------------+
int AlgoLevelTradeNumTodayAtMagicLevelSlot(const int algoSlot1, const int levelSlot)
{
   const int idx = AlgoFamilySlotArrayIndex(algoSlot1);
   if(idx < 0 || levelSlot < 0 || levelSlot >= FALGO_MAGIC_LEVEL_SLOT_COUNT)
      return 0;
   if(!FalgoMagicLevelSlotIsValid(levelSlot))
      return 0;
   return g_algoLevelTradeNumByMagicSlot[idx][levelSlot];
}

datetime g_algoGatesLastLoggedBarTime[ALGO_FAMILY_REGISTRY_MAX];
datetime g_algoGatesPerSecondLastLoggedTime[ALGO_FAMILY_REGISTRY_MAX];
datetime g_falgoGatesLogDayStart = 0;

#define FALGO_TELEMETRY_PROFIT_RING_MAX   130
#define FALGO_OPEN_TELEMETRY_MAX          8
#define FALGO_CLOSED_TELEMETRY_MAX        64
#define FALGO_VELOCITY_PARAM_TEST_COUNT   11
#define FALGO_VELOCITY_LOG_SCALE 10.0  // native velocity unit: pts per 10 sec (profitVelocity, tune thresholds, all comparisons)
int g_velocityParameterTestedSec[FALGO_VELOCITY_PARAM_TEST_COUNT] = {3, 5, 8, 10, 15, 20, 30, 45, 60, 90, 120}; // bookmark
#define FALGO_EXIT_MODE_NEUTRAL           "neutral"
#define FALGO_EXIT_MODE_NEUTRAL_TRADE     "neutral_trade"
#define FALGO_EXIT_MODE_GOOD_MOMENTUM     "good_momentum"
#define FALGO_EXIT_MODE_BAD_TRADE         "bad_trade"
#define FALGO_EXIT_MODE_TERRIBLE_TRADE    "terrible_trade"
#define FALGO_TELEMETRY_EVENT_TICK        "telemetry"
#define FALGO_TELEMETRY_EVENT_CLOSE       "close_decision"

struct FalgoOpenTradeTelemetry
{
   bool     active;
   ulong    positionTicket;
   long     magic;
   datetime tradeStartTime;
   int      tradeAgeSeconds;
   int      secondsGreen;
   int      secondsRed;
   int      consecutiveGreen;
   int      consecutiveRed;
   double   openProfitPts;
   double   mfePts;
   double   maePts;
   double   maeFirstWindowPts;  // worst floating P/L (pts) during first tradeResult_maeFirst_window_seconds
   double   maePostXPts;
   int      mfeCandle1Based;
   int      maeCandle1Based;
   int      timeToReachNeutralTpSeconds;
   double   avgProfitVelocity;
   int      avgVelocitySampleCount;
   double   avgProfitVelocityParamTest[FALGO_VELOCITY_PARAM_TEST_COUNT];
   double   profitRing[FALGO_TELEMETRY_PROFIT_RING_MAX];
   datetime timeRing[FALGO_TELEMETRY_PROFIT_RING_MAX];
   int      ringCount;
   int      ringWriteIdx;
   int      lastBarIdx;
   bool     aimStrongTp;
   double   strongMomentumPeakAvgVelocity;  // max avgProfitVelocity since aimStrongTp (avgvelocity_stall mode)
   bool     badTradeMode;
   bool     terribleTradeMode;
   string   exitMode;
   string   exitModePrev;
   bool     exitModeChanged;
   string   closeDecisionReason;  // set when babysit decides to close; copied to trade-results CSV
   string   closeDecisionDetail;
   datetime breakdownSequenceEndTime;   // M15 breakdown end (breakdown family algos)
   datetime breakdownTimeExitDeadline;    // close open position when g_lastTimer1Time >= this
   double   breakdownStartHigh;           // breakdown_sequence_startprice (broker TP anchor)
   double   breakdownLow;                 // breakdown low (secret TP range anchor)
};

struct Breakdown15mState
{
   bool     hasBreakdown;
   bool     sequenceActive;
   int      activeLength;
   int      endedLength;
   datetime startTime;
   double   startHigh;
   datetime endTime;
   double   breakdownLow;
   int      greensAfterBdCount;
   double   greensAfterBdHigh[BREAKDOWN_GREENS_AFTER_BD_MAX];
   datetime greensAfterBdBarEndTime[BREAKDOWN_GREENS_AFTER_BD_MAX];
   double   firstGreenHigh;                 // 1st green after bd (logs); placement uses after_bd_need_x_15greenc
   datetime firstGreenBarEndTime;           // M15 open + 15 min for 1st green close
   double   midpoint;
   double   totalPercent;
};

Breakdown15mState g_breakdown15mSnap;
Breakdown15mState g_breakdown15mSnapByAlgoSlot[BREAKDOWN_ALGO_REGISTRY_MAX];
bool              g_breakdown15mSnapByAlgoSlotReady[BREAKDOWN_ALGO_REGISTRY_MAX];
datetime          g_breakdown15mSnapByAlgoAsOf = 0;

#define BREAKDOWN_AUDIT_LOG_DEDUP_MAX 50000
struct BreakdownAuditLogDedupKey
{
   datetime startTime;
   int      mode;
};
BreakdownAuditLogDedupKey g_breakdownAuditLoggedKeys[BREAKDOWN_AUDIT_LOG_DEDUP_MAX];
int                       g_breakdownAuditLoggedCount = 0;

struct BreakdownAuditSummaryAcc
{
   int    count;
   double sumStreak;
   double sumFirstCandlePct;
   double sumTotalPercent;
   double minTotalPercent;
   double maxTotalPercent;
   bool   hasTotalPercent;
};

BreakdownAuditSummaryAcc g_breakdownAuditSummaryAcc[BREAKDOWN_STREAK_CONTINUATION_COUNT];

datetime g_breakdownAuditScanDayStart = 0;
datetime g_breakdownAuditLastM15CompleteTime = 0;

void BreakdownResetAllBreakdownsAuditLogsOnInit();
void BreakdownAuditLogScanDay(const datetime dayStart, const datetime upToM1BarTime);
bool BreakdownAuditShouldScanOnM1Close(const datetime dayStart, const datetime upToM1BarTime);
void BreakdownAuditLogScanDayIfNeeded(const datetime dayStart, const datetime upToM1BarTime, const bool force = false);

void ComputeBreakdown15mState(const datetime dayStart, const datetime upToM1BarTime, const double strongRangePctMin,
   const int forgetAfterMinutes, const ENUM_BREAKDOWN_STREAK_CONTINUATION continuationMode, Breakdown15mState &out);
Breakdown15mState Breakdown15mSnapForAlgo(const int algoNumber, const datetime asOfTime);

struct FalgoTelemetryBarSnap
{
   bool     valid;
   long     magic;              // composite magic of trade that produced this bar snap
   int      tradeAgeSeconds;
   double   openProfitPts;
   int      secondsGreen;
   int      secondsRed;
   double   greenRatio;
   int      consecutiveGreen;
   int      consecutiveRed;
   double   profitVelocity;
   double   mfePts;
   double   maePts;
   double   profitFromPeak;
   bool     tradeClosedOnThisBar;
};

struct FalgoClosedTradeTelemetrySummary
{
   long     magic;
   datetime startTime;
   int      secondsGreen;
   int      secondsRed;
   double   greenRatioAtClose;
   double   avgProfitVelocity;
   double   mfePts;
   double   maePts;
   double   maeFirstWindowPts;
   int      mfeCandle1Based;
   int      maeCandle1Based;
   int      timeToReachNeutralTpSeconds;
   string   closeDecision;
   string   closeDetail;
};

FalgoOpenTradeTelemetry g_falgoOpenTelemetrySlots[FALGO_OPEN_TELEMETRY_MAX];
int g_falgoOpenTelemetryCtx = -1;

//+------------------------------------------------------------------+
string BreakdownTradeLifetimeCloseReasonFromExit(const ENUM_DEAL_REASON dealReason,
   const ulong positionId, const long entryMagic, const datetime startTime)
{
   if(dealReason == DEAL_REASON_TP)
      return "realTP";
   if(dealReason != DEAL_REASON_EXPERT)
      return "";
   for(int i = 0; i < FALGO_OPEN_TELEMETRY_MAX; i++)
   {
      if(g_falgoOpenTelemetrySlots[i].positionTicket == positionId
         || (g_falgoOpenTelemetrySlots[i].magic == entryMagic && g_falgoOpenTelemetrySlots[i].tradeStartTime == startTime))
      {
         const string r = g_falgoOpenTelemetrySlots[i].closeDecisionReason;
         if(r == "breakdown_midpoint_time_exit")
            return "timeTrigger";
         if(r == "breakdown_secretTPSL_tp")
            return "secretTP";
         break;
      }
   }
   return "";
}

// Per registry slot (algo 10..16): one bar snap per M1 bar — no cross-algo overwrite.
FalgoTelemetryBarSnap g_falgoTelemetryAtBar[MAX_BARS_IN_DAY][ALGO_FAMILY_REGISTRY_MAX];
FalgoClosedTradeTelemetrySummary g_falgoClosedTelemetry[FALGO_CLOSED_TELEMETRY_MAX];
int g_falgoClosedTelemetryCount = 0;
datetime g_falgoTelemetryLastUpdateTime = 0;
datetime g_falgoTelemetryDayStart = 0;
int g_falgoLastTradeClosedBarIdx[ALGO_FAMILY_REGISTRY_MAX];

struct FalgoMagicKey
{
   int direction;       // 1..4
   int dayOfWeek;       // 1..5 Mon..Fri
   int levelSlot;       // 00=RTHO; 01=PDC; 10..35 weekly; 50..80 daily; breakdown slot
   int bounceCount;     // 0..8
   int ceilingCount;    // 0..8
   int offset_tenths;   // encoded 0.1..9.9 (long or short offset for this order)
   int planTradeNum;    // 0..8
   int levelTradeNum;   // 0..8
   int babysitMinute;   // 0..9
   int tpWhole;         // 1..99
   int slWhole;
};

//+------------------------------------------------------------------+
int FalgoClamp0_8(const int v) { return (v < 0) ? 0 : ((v > 8) ? 8 : v); }
int FalgoClamp0_9(const int v) { return (v < 0) ? 0 : ((v > 9) ? 9 : v); }

//+------------------------------------------------------------------+
int FalgoCapWholeTpSlForMagic(const double points)
{
   int w = (int)MathRound(points);
   if(w < 1) w = 1;
   if(w > 99) w = 99;
   return w;
}

//+------------------------------------------------------------------+
long BuildAlgoMagicNumber(const int algoNumber, const FalgoMagicKey &k)
{
   if(!FalgoMagicLevelSlotIsValid(k.levelSlot))
      FatalError(StringFormat("BuildAlgoMagicNumber: algo%d invalid levelSlot %d (00=RTHO; 01=PDC; 10..35 weekly; 50..80 daily)",
         algoNumber, k.levelSlot));
   string s = StringFormat("%03d%d%d%02d%d%d%02d%d%d%d%02d%02d",
      algoNumber,
      k.direction,
      k.dayOfWeek,
      k.levelSlot,
      FalgoClamp0_8(k.bounceCount),
      FalgoClamp0_8(k.ceilingCount),
      k.offset_tenths,
      FalgoClamp0_8(k.planTradeNum),
      FalgoClamp0_8(k.levelTradeNum),
      FalgoClamp0_9(k.babysitMinute),
      k.tpWhole,
      k.slWhole);
   if(StringLen(s) != COMPOSITE_MAGIC_STRING_LEN)
      FatalError(StringFormat("BuildAlgoMagicNumber: algo%d len %d != %d", algoNumber, StringLen(s), COMPOSITE_MAGIC_STRING_LEN));
   return (long)StringToInteger(s);
}

//+------------------------------------------------------------------+
FalgoMagicKey ParseFalgoMagic(const long magic)
{
   FalgoMagicKey emptyKey;
   emptyKey.direction = 0;
   emptyKey.dayOfWeek = 0;
   emptyKey.levelSlot = 0;
   emptyKey.bounceCount = 0;
   emptyKey.ceilingCount = 0;
   emptyKey.offset_tenths = 0;
   emptyKey.planTradeNum = 0;
   emptyKey.levelTradeNum = 0;
   emptyKey.babysitMinute = 0;
   emptyKey.tpWhole = 0;
   emptyKey.slWhole = 0;
   if(!IsAnyAlgoFamilyCompositeMagic(magic))
      return emptyKey;
   string s = MagicNumberToFixedWidthString(magic);
   FalgoMagicKey k;
   k.direction = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_DIRECTION, FALGO_MAGIC_LENGTH_DIRECTION));
   k.dayOfWeek = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_DAY_OF_WEEK, FALGO_MAGIC_LENGTH_DAY_OF_WEEK));
   k.levelSlot = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_LEVEL_SLOT, FALGO_MAGIC_LENGTH_LEVEL_SLOT));
   k.bounceCount = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_BOUNCE, FALGO_MAGIC_LENGTH_BOUNCE));
   k.ceilingCount = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_CEILING, FALGO_MAGIC_LENGTH_CEILING));
   k.offset_tenths = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_OFFSET, FALGO_MAGIC_LENGTH_OFFSET));
   k.planTradeNum = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_PLAN_TRADE_NUM, FALGO_MAGIC_LENGTH_PLAN_TRADE_NUM));
   k.levelTradeNum = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_LEVEL_TRADE_NUM, FALGO_MAGIC_LENGTH_LEVEL_TRADE_NUM));
   k.babysitMinute = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_BABYSIT_MIN, FALGO_MAGIC_LENGTH_BABYSIT_MIN));
   k.tpWhole = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_TP, FALGO_MAGIC_LENGTH_TP));
   k.slWhole = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_SL, FALGO_MAGIC_LENGTH_SL));
   return k;
}

//+------------------------------------------------------------------+
void RebuildFalgoBannedRangesCache()
{
   g_falgoBannedRangeCount = 0;
   ParseBannedRanges(g_algoShared.bannedRanges);
   // Use g_bannedRangesCount (rows), not ArraySize — on 2D arrays ArraySize is total elements (rows×4).
   for(int i = 0; i < g_bannedRangesCount && i < FALGO_BANNED_RANGES_MAX; i++)
   {
      g_falgoBannedRanges[i].startMin = g_bannedRangesBuffer[i][0] * 60 + g_bannedRangesBuffer[i][1];
      g_falgoBannedRanges[i].endMin   = g_bannedRangesBuffer[i][2] * 60 + g_bannedRangesBuffer[i][3];
      g_falgoBannedRangeCount++;
   }
}

//+------------------------------------------------------------------+
bool FalgoIsTradingTimeAllowed(const datetime t)
{
   MqlDateTime mt;
   TimeToStruct(t, mt);
   int curMin = mt.hour * 60 + mt.min;
   for(int i = 0; i < g_falgoBannedRangeCount; i++)
   {
      int sm = g_falgoBannedRanges[i].startMin;
      int em = g_falgoBannedRanges[i].endMin;
      if(curMin >= sm && curMin <= em)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| MT5 day_of_week 1=Mon..5=Fri (magic index 3). Weekend → -1 (calendar gate only). |
//+------------------------------------------------------------------+
int FalgoDayOfWeekSlotFromTimeOrInvalid(const datetime t)
{
   MqlDateTime mt;
   TimeToStruct(t, mt);
   int dow = mt.day_of_week;
   if(dow >= 1 && dow <= 5)
      return dow;
   return -1;
}

//+------------------------------------------------------------------+
//| Same as OrInvalid but FatalError if not Mon..Fri (encode in magic). |
//+------------------------------------------------------------------+
int FalgoDayOfWeekSlotFromTime(const datetime t)
{
   int slot = FalgoDayOfWeekSlotFromTimeOrInvalid(t);
   if(slot < 1)
      FatalError(StringFormat("FalgoDayOfWeekSlotFromTime: invalid day_of_week slot (expected 1..5 Mon..Fri) at %s",
         TimeToString(t, TIME_DATE|TIME_MINUTES)));
   return slot;
}

//+------------------------------------------------------------------+
bool FalgoLevelShouldTrackForDayStats(const string &categories)
{
   if(LevelIsWeeklyKind(categories))
      return true;
   return LevelIsDailyKind(categories);
}

//+------------------------------------------------------------------+
bool LevelIsStacked(const string &categories)
{
   string c = categories;
   StringToLower(c);
   return (StringFind(c, "stacked") >= 0);
}

//+------------------------------------------------------------------+
bool LevelIsWeeklyKind(const string &categories)
{
   return LevelIsWeekly(categories) || LevelIsStacked(categories);
}

//+------------------------------------------------------------------+
bool LevelIsDailyKind(const string &categories)
{
   string c = categories;
   StringToLower(c);
   if(StringFind(c, "tertiary") >= 0)
      return false;
   return (StringFind(c, "daily") >= 0 || StringFind(c, "stacked") >= 0);
}

//+------------------------------------------------------------------+
//| Daily/stacked levels must name at least one monday..sunday in categories; true only on matching weekday. |
//+------------------------------------------------------------------+
bool LevelCategoriesActiveOnDayOfWeekLower(const string &cLower, const int mt5DayOfWeek)
{
   bool foundAnyDay = false;
   if(StringFind(cLower, "sunday") >= 0)    { foundAnyDay = true; if(mt5DayOfWeek == 0) return true; }
   if(StringFind(cLower, "monday") >= 0)    { foundAnyDay = true; if(mt5DayOfWeek == 1) return true; }
   if(StringFind(cLower, "tuesday") >= 0)   { foundAnyDay = true; if(mt5DayOfWeek == 2) return true; }
   if(StringFind(cLower, "wednesday") >= 0) { foundAnyDay = true; if(mt5DayOfWeek == 3) return true; }
   if(StringFind(cLower, "thursday") >= 0)  { foundAnyDay = true; if(mt5DayOfWeek == 4) return true; }
   if(StringFind(cLower, "friday") >= 0)    { foundAnyDay = true; if(mt5DayOfWeek == 5) return true; }
   if(StringFind(cLower, "saturday") >= 0)  { foundAnyDay = true; if(mt5DayOfWeek == 6) return true; }
   if(!foundAnyDay)
      FatalError(StringFormat("LevelCategoriesActiveOnDayOfWeek: daily/stacked level categories missing monday..sunday token: \"%s\"", cLower));
   return false;
}

//+------------------------------------------------------------------+
bool LevelCategoriesActiveOnDayOfWeek(const string &categories, const int mt5DayOfWeek)
{
   string c = categories;
   StringToLower(c);
   return LevelCategoriesActiveOnDayOfWeekLower(c, mt5DayOfWeek);
}

//+------------------------------------------------------------------+
//| Pre-lowercased categories (see LevelExpandedRow.categoriesLower). |
//+------------------------------------------------------------------+
bool LevelEligibleForAlgoLevelScopeLower(const string &cLower, const bool tradesWeekly, const bool tradesDaily, const datetime asOfTime)
{
   if(StringFind(cLower, "tertiary") >= 0)
      return false;

   const bool stacked = (StringFind(cLower, "stacked") >= 0);
   const bool dailyKind = (StringFind(cLower, "daily") >= 0 || stacked);
   const bool weeklyKind = (StringFind(cLower, "weekly") >= 0 || stacked);

   if(FalgoIsDailyLevelsOnlyCalendarDate(asOfTime))
   {
      if(!dailyKind)
         return false;
      MqlDateTime mt;
      TimeToStruct(asOfTime, mt);
      if(stacked)
      {
         if(tradesWeekly || tradesDaily)
            return LevelCategoriesActiveOnDayOfWeekLower(cLower, mt.day_of_week);
         return false;
      }
      if(tradesDaily)
         return LevelCategoriesActiveOnDayOfWeekLower(cLower, mt.day_of_week);
      return false;
   }

   if(tradesWeekly && weeklyKind)
      return true;

   if(tradesDaily && dailyKind)
   {
      MqlDateTime mt;
      TimeToStruct(asOfTime, mt);
      return LevelCategoriesActiveOnDayOfWeekLower(cLower, mt.day_of_week);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Stacked = weekly+daily: weekly algos / both-enabled → whole week; daily-only → weekday substrings required (FatalError if missing). |
//+------------------------------------------------------------------+
bool LevelEligibleForAlgoLevelScope(const string &categories, const bool tradesWeekly, const bool tradesDaily, const datetime asOfTime)
{
   string c = categories;
   StringToLower(c);
   return LevelEligibleForAlgoLevelScopeLower(c, tradesWeekly, tradesDaily, asOfTime);
}

//+------------------------------------------------------------------+
datetime FalgoLevelEligibilityTimeForBar(const int barIdx)
{
   if(barIdx >= 0 && barIdx < g_barsInDay)
      return g_m1Rates[barIdx].time;
   if(g_m1DayStart != 0)
      return g_m1DayStart;
   datetime ctx = g_lastTimer1Time;
   return (ctx != 0 ? ctx : TimeCurrent());
}

//+------------------------------------------------------------------+
bool LevelIsDailyNonTertiary(const string &categories)
{
   return LevelIsDailyKind(categories);
}

//+------------------------------------------------------------------+
//| Base calendar overrides: non-trade dates + daily/stacked-only dates (YYYY.MM.DD). |
//+------------------------------------------------------------------+
void RebuildFalgoCalendarOverrideDateLists()
{
   // algobookmark banned days
   string nonTrade[] = {
      // 2024 — market holidays
      "2024.01.01", "2024.01.15", "2024.02.19", "2024.03.29", "2024.05.27", "2024.06.19",
      "2024.07.04", "2024.09.02", "2024.11.28", "2024.12.25",
      // 2024 — early close / special
      "2024.07.03", "2024.11.29", "2024.12.24",
      // 2024 — OpEx weeks (Mon–Fri)
      "2024.03.11", "2024.03.12", "2024.03.13", "2024.03.14", "2024.03.15",
      "2024.06.17", "2024.06.18", "2024.06.20", "2024.06.21",
      "2024.09.16", "2024.09.17", "2024.09.18", "2024.09.19", "2024.09.20",
      "2024.12.16", "2024.12.17", "2024.12.18", "2024.12.19", "2024.12.20",
      // 2025 — market holidays
      "2025.01.01", "2025.01.20", "2025.02.17", "2025.04.18", "2025.05.26", "2025.06.19",
      "2025.07.04", "2025.09.01", "2025.11.27", "2025.12.25",
      // 2025 — early close / special
      "2025.07.03", "2025.11.28", "2025.12.24",
      // 2025 — OpEx weeks (Mon–Fri)
      "2025.03.17", "2025.03.18", "2025.03.19", "2025.03.20", "2025.03.21",
      "2025.06.16", "2025.06.17", "2025.06.18", "2025.06.20",
      "2025.09.15", "2025.09.16", "2025.09.17", "2025.09.18", "2025.09.19",
      "2025.12.15", "2025.12.16", "2025.12.17", "2025.12.18", "2025.12.19",
      // 2026 — market holidays
      "2026.01.01", "2026.01.19", "2026.02.16", "2026.04.03", "2026.05.25", "2026.06.19",
      "2026.07.03", "2026.09.07", "2026.11.26", "2026.12.25",
      // 2026 — OpEx weeks (Mon–Fri)
      "2026.03.16", "2026.03.17", "2026.03.18", "2026.03.19", "2026.03.20",
      "2026.06.15", "2026.06.16", "2026.06.17", "2026.06.18",
      "2026.09.14", "2026.09.15", "2026.09.16", "2026.09.17", "2026.09.18",
      "2026.12.14", "2026.12.15", "2026.12.16", "2026.12.17", "2026.12.18"
   };
   string dailyOnly[] = {
   };
   ArrayResize(g_falgoNonTradeDates, ArraySize(nonTrade));
   for(int i = 0; i < ArraySize(nonTrade); i++)
      g_falgoNonTradeDates[i] = nonTrade[i];
   ArrayResize(g_falgoDailyLevelsOnlyDates, ArraySize(dailyOnly));
   for(int i = 0; i < ArraySize(dailyOnly); i++)
      g_falgoDailyLevelsOnlyDates[i] = dailyOnly[i];
}

//+------------------------------------------------------------------+
string FalgoNormalizeDateStr(string dateStr)
{
   if(StringFind(dateStr, "-") >= 0)
      StringReplace(dateStr, "-", ".");
   return dateStr;
}

//+------------------------------------------------------------------+
bool FalgoDateStrInList(const string dateStr, const string &dates[])
{
   const string key = FalgoNormalizeDateStr(dateStr);
   for(int i = 0; i < ArraySize(dates); i++)
      if(dates[i] == key)
         return true;
   return false;
}

//+------------------------------------------------------------------+
bool FalgoIsNonTradeCalendarDate(const datetime t)
{
   return FalgoDateStrInList(TimeToString(t, TIME_DATE), g_falgoNonTradeDates);
}

//+------------------------------------------------------------------+
bool FalgoIsDailyLevelsOnlyCalendarDate(const datetime t)
{
   if(FalgoIsNonTradeCalendarDate(t))
      return false;
   return FalgoDateStrInList(TimeToString(t, TIME_DATE), g_falgoDailyLevelsOnlyDates);
}

//+------------------------------------------------------------------+
bool AlgoTradesWeeklyLevels(const int algoNumber)
{
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   return g_algos[idx].tradesWeeklyLevels;
}

//+------------------------------------------------------------------+
bool AlgoTradesDailyLevels(const int algoNumber)
{
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   return g_algos[idx].tradesDailyLevels;
}

//+------------------------------------------------------------------+
bool AlgoTradesAnyLevels(const int algoNumber)
{
   return AlgoTradesWeeklyLevels(algoNumber) || AlgoTradesDailyLevels(algoNumber)
      || AlgoTradesTertiaryTodayRTHOLevel(algoNumber);
}

//+------------------------------------------------------------------+
bool FalgoMagicLevelSlotIsBreakdownMidpoint(const int levelSlot)
{
   return (levelSlot == FALGO_MAGIC_LEVEL_SLOT_BREAKDOWN);
}

//+------------------------------------------------------------------+
bool FalgoLevelEligibleForAlgo(const int expandedLevelIdx, const int algoNumber, const datetime asOfTime)
{
   if(expandedLevelIdx < 0 || expandedLevelIdx >= g_levelsTodayCount)
      return false;
   if(FalgoIsDailyLevelsOnlyCalendarDate(asOfTime) && AlgoTradesTertiaryTodayRTHOLevel(algoNumber))
      return false;
   if(AlgoTradesTertiaryTodayRTHOLevel(algoNumber))
      return LevelIsTodayRthOpenTertiary(g_levelsExpanded[expandedLevelIdx].categories);
   return LevelEligibleForAlgoLevelScope(g_levelsExpanded[expandedLevelIdx].categories,
      AlgoTradesWeeklyLevels(algoNumber), AlgoTradesDailyLevels(algoNumber), asOfTime);
}

//+------------------------------------------------------------------+
bool FalgoLevelEligibleForAlgo(const int expandedLevelIdx, const int algoNumber)
{
   return FalgoLevelEligibleForAlgo(expandedLevelIdx, algoNumber, FalgoLevelEligibilityTimeForBar(-1));
}

//+------------------------------------------------------------------+
int FalgoClosestExpandedLevelIdxAtBarForAlgo(const int algoNumber, const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return -1;
   if(AlgoTradesTertiaryTodayRTHOLevel(algoNumber))
   {
      if(FalgoIsDailyLevelsOnlyCalendarDate(g_m1Rates[barIdx].time))
         return -1;
      return FalgoTodayRthOpenTertiaryExpandedIdx(barIdx);
   }
   const bool tradesWeekly = AlgoTradesWeeklyLevels(algoNumber);
   const bool tradesDaily = AlgoTradesDailyLevels(algoNumber);
   if(tradesWeekly && !tradesDaily)
      return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevelExpandedIdx;
   if(tradesDaily && !tradesWeekly)
      return g_pullingHistoryAlgoFamilyDailyAtBar[barIdx].closestWeeklyLevelExpandedIdx;

   const double c = g_m1Rates[barIdx].close;
   int bestIdx = -1;
   double bestDist = 1e300;
   for(int trackIdx = 0; trackIdx < g_weeklyAlgoFamilyTrackCount; trackIdx++)
   {
      const int expandedIdx = g_weeklyAlgoFamilyTrackExpandedIdx[trackIdx];
      if(!FalgoLevelEligibleForAlgo(expandedIdx, algoNumber, g_m1Rates[barIdx].time))
         continue;
      const double d = MathAbs(c - g_levelsExpanded[expandedIdx].levelPrice);
      if(d < bestDist)
      {
         bestDist = d;
         bestIdx = expandedIdx;
      }
   }
   return bestIdx;
}

//+------------------------------------------------------------------+
double FalgoClosestLevelPriceAtBarForAlgo(const int algoNumber, const int barIdx)
{
   const int levelIdx = FalgoClosestExpandedLevelIdxAtBarForAlgo(algoNumber, barIdx);
   if(levelIdx < 0)
      return 0.0;
   if(AlgoTradesTertiaryTodayRTHOLevel(algoNumber) && g_todayRTHopenValid)
      return g_todayRTHopen;
   return g_levelsExpanded[levelIdx].levelPrice;
}

//+------------------------------------------------------------------+
double FalgoProximityToClosestLevelAtBarForAlgo(const int algoNumber, const int barIdx)
{
   const double levelPx = FalgoClosestLevelPriceAtBarForAlgo(algoNumber, barIdx);
   if(levelPx <= 0.0 || barIdx < 0 || barIdx >= g_barsInDay)
      return 0.0;
   return MathAbs(g_m1Rates[barIdx].close - levelPx);
}

//+------------------------------------------------------------------+
void FalgoFillPullingSnapFromLevelStatsCache(const int expandedIdx, const int barIdx,
   const AlgoFamilyLevelDayStatsAtBar &stats, PullingHistoryAlgoFamilyBarSnap &outSnap)
{
   const double levelPrice = g_levelsExpanded[expandedIdx].levelPrice;
   const double h = g_m1Rates[barIdx].high;
   const double l = g_m1Rates[barIdx].low;
   PullingHistoryAlgoFamilyClearClosestFields(outSnap);
   outSnap.closestWeeklyLevelToCClose = levelPrice;
   outSnap.closestWeeklyLevelExpandedIdx = expandedIdx;
   outSnap.closestPriceProximity = GetBarClosestPriceProximityToLevel(h, l, levelPrice);
   outSnap.cleanOHLC_streak_count = stats.cleanStreakCount;
   outSnap.closestWeeklyLevel_anchorAbove_within_cleanOHLC_streak = stats.anchorAbove;
   outSnap.closestWeeklyLevel_anchorBelow_within_cleanOHLC_streak = stats.anchorBelow;
   outSnap.closestWeeklyLevel_BounceCount_today = stats.bounceCount_today;
   outSnap.closestWeeklyLevel_CeilingCount_today = stats.ceilingCount_today;
   outSnap.closestWeeklyLevel_CeilingProximityCandles_today = stats.ceilingProximityCandles_today;
   outSnap.closestWeeklyLevel_BounceCount_recent = stats.bounceCount_recent;
   outSnap.closestWeeklyLevel_CeilingCount_recent = stats.ceilingCount_recent;
   outSnap.closestWeeklyLevel_CeilingProximityCandles_recent = stats.ceilingProximityCandles_recent;
   outSnap.closestWeeklyLevel_physicalContactCount_today = stats.physicalContactCount_today;
   outSnap.closestWeeklyLevel_contactAndProximityCount_today = stats.contactAndProximityCount_today;
}

//+------------------------------------------------------------------+
bool FalgoTryGetAlgoFamilyLevelStatsCacheAtBar(const double levelPrice, const int barIdx,
   AlgoFamilyLevelDayStatsAtBar &outStats)
{
   const int trackIdx = AlgoFamilyTrackIdxForLevelPrice(levelPrice);
   if(trackIdx >= 0 && barIdx >= 0 && barIdx < g_barsInDay)
   {
      outStats = g_algoFamilyLevelStatsAtBar[trackIdx][barIdx];
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool FalgoPullingHistoryClosestSnapAtBarForAlgo(const int algoNumber, const int barIdx,
   PullingHistoryAlgoFamilyBarSnap &outSnap)
{
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return false;
   const bool tradesWeekly = AlgoTradesWeeklyLevels(algoNumber);
   const bool tradesDaily = AlgoTradesDailyLevels(algoNumber);
   if(tradesWeekly && !tradesDaily)
   {
      outSnap = g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx];
      return (outSnap.closestWeeklyLevelExpandedIdx >= 0);
   }
   if(tradesDaily && !tradesWeekly)
   {
      outSnap = g_pullingHistoryAlgoFamilyDailyAtBar[barIdx];
      return (outSnap.closestWeeklyLevelExpandedIdx >= 0);
   }
   if(!tradesWeekly && !tradesDaily)
      return false;

   const int expandedIdx = FalgoClosestExpandedLevelIdxAtBarForAlgo(algoNumber, barIdx);
   if(expandedIdx < 0)
      return false;
   const double levelPrice = g_levelsExpanded[expandedIdx].levelPrice;
   AlgoFamilyLevelDayStatsAtBar stats;
   if(FalgoTryGetAlgoFamilyLevelStatsCacheAtBar(levelPrice, barIdx, stats))
   {
      FalgoFillPullingSnapFromLevelStatsCache(expandedIdx, barIdx, stats, outSnap);
      return true;
   }
   int dummyContact = 0, dummySinceB = 0, dummySinceC = 0;
   FalgoGetAlgoFamilyLevelDayStatsAtBar(levelPrice, barIdx,
      stats.bounceCount_today, stats.ceilingCount_today, stats.ceilingProximityCandles_today, dummyContact,
      dummySinceB, dummySinceC);
   stats.bounceCount_recent = 0;
   stats.ceilingCount_recent = 0;
   stats.ceilingProximityCandles_recent = 0;
   stats.anchorAbove = 0.0;
   stats.anchorBelow = 0.0;
   stats.cleanStreakCount = 0;
   FalgoFillPullingSnapFromLevelStatsCache(expandedIdx, barIdx, stats, outSnap);
   return true;
}

//+------------------------------------------------------------------+
double FalgoLevelAnchorValueInSnapStreak(const PullingHistoryAlgoFamilyBarSnap &snap, const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return 0.0;
   const double levelPx = snap.closestWeeklyLevelToCClose;
   if(levelPx <= 0.0)
      return 0.0;
   const double closePx = g_m1Rates[barIdx].close;
   if(closePx > levelPx)
      return snap.closestWeeklyLevel_anchorAbove_within_cleanOHLC_streak;
   if(closePx < levelPx)
      return snap.closestWeeklyLevel_anchorBelow_within_cleanOHLC_streak;
   return 0.0;
}

//+------------------------------------------------------------------+
bool FalgoPullingHistorySnapForLevelAtBar(const double levelPrice, const int barIdx,
   PullingHistoryAlgoFamilyBarSnap &outSnap)
{
   if(levelPrice <= 0.0 || barIdx < 0 || barIdx >= g_barsInDay)
      return false;
   if(MathAbs(g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevelToCClose - levelPrice) < 1e-9)
   {
      outSnap = g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx];
      return true;
   }
   if(MathAbs(g_pullingHistoryAlgoFamilyDailyAtBar[barIdx].closestWeeklyLevelToCClose - levelPrice) < 1e-9)
   {
      outSnap = g_pullingHistoryAlgoFamilyDailyAtBar[barIdx];
      return true;
   }
   int expandedIdx = -1;
   const int trackIdx = AlgoFamilyTrackIdxForLevelPrice(levelPrice);
   if(trackIdx >= 0)
      expandedIdx = g_weeklyAlgoFamilyTrackExpandedIdx[trackIdx];
   else
   {
      for(int i = 0; i < g_levelsTodayCount; i++)
      {
         if(MathAbs(g_levelsExpanded[i].levelPrice - levelPrice) < 1e-9)
         {
            expandedIdx = i;
            break;
         }
      }
   }
   if(expandedIdx < 0)
      return false;
   AlgoFamilyLevelDayStatsAtBar stats;
   if(!FalgoTryGetAlgoFamilyLevelStatsCacheAtBar(levelPrice, barIdx, stats))
   {
      int dummyContact = 0, dummySinceB = 0, dummySinceC = 0;
      FalgoGetAlgoFamilyLevelDayStatsAtBar(levelPrice, barIdx,
         stats.bounceCount_today, stats.ceilingCount_today, stats.ceilingProximityCandles_today, dummyContact,
         dummySinceB, dummySinceC);
      stats.bounceCount_recent = 0;
      stats.ceilingCount_recent = 0;
      stats.ceilingProximityCandles_recent = 0;
      stats.anchorAbove = 0.0;
      stats.anchorBelow = 0.0;
      stats.cleanStreakCount = 0;
   }
   FalgoFillPullingSnapFromLevelStatsCache(expandedIdx, barIdx, stats, outSnap);
   return true;
}

//+------------------------------------------------------------------+
int FalgoGetDayBounceCountForLevelAtBar(const int barIdx, const double levelPrice)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || levelPrice <= 0.0)
      return 0;
   AlgoFamilyLevelDayStatsAtBar s;
   if(FalgoTryGetAlgoFamilyLevelStatsCacheAtBar(levelPrice, barIdx, s))
      return s.bounceCount_today;
   int dBounce = 0, dCeiling = 0;
   AlgoFamilyDayBounceCeilingForLevelAsOfTime(levelPrice, g_m1Rates[barIdx].time + 60, dBounce, dCeiling);
   return dBounce;
}

//+------------------------------------------------------------------+
int FalgoGetDayCeilingCountForLevelAtBar(const int barIdx, const double levelPrice)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || levelPrice <= 0.0)
      return 0;
   AlgoFamilyLevelDayStatsAtBar s;
   if(FalgoTryGetAlgoFamilyLevelStatsCacheAtBar(levelPrice, barIdx, s))
      return s.ceilingCount_today;
   int dBounce = 0, dCeiling = 0;
   AlgoFamilyDayBounceCeilingForLevelAsOfTime(levelPrice, g_m1Rates[barIdx].time + 60, dBounce, dCeiling);
   return dCeiling;
}

//+------------------------------------------------------------------+
int FalgoGetDayCeilingProximityCandlesForLevelAtBar(const int barIdx, const double levelPrice)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || levelPrice <= 0.0)
      return 0;
   AlgoFamilyLevelDayStatsAtBar s;
   if(FalgoTryGetAlgoFamilyLevelStatsCacheAtBar(levelPrice, barIdx, s))
      return s.ceilingProximityCandles_today;
   int bounce = 0, ceiling = 0, prox = 0, contact = 0, sinceB = 0, sinceC = 0;
   AlgoFamilyDayLevelStatsForLevelAsOfTime(levelPrice, g_m1Rates[barIdx].time + 60,
      bounce, ceiling, prox, contact, sinceB, sinceC);
   return prox;
}

//+------------------------------------------------------------------+
int FalgoGetRecentBounceCountForLevelAtBar(const int barIdx, const double levelPrice)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || levelPrice <= 0.0)
      return 0;
   AlgoFamilyLevelDayStatsAtBar s;
   if(FalgoTryGetAlgoFamilyLevelStatsCacheAtBar(levelPrice, barIdx, s))
      return s.bounceCount_recent;
   return 0;
}

//+------------------------------------------------------------------+
int FalgoGetRecentCeilingCountForLevelAtBar(const int barIdx, const double levelPrice)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || levelPrice <= 0.0)
      return 0;
   AlgoFamilyLevelDayStatsAtBar s;
   if(FalgoTryGetAlgoFamilyLevelStatsCacheAtBar(levelPrice, barIdx, s))
      return s.ceilingCount_recent;
   return 0;
}

//+------------------------------------------------------------------+
int FalgoLevelCleanOHLCStreakAtBarForExpandedIdx(const int expandedIdx, const int barIdx)
{
   if(expandedIdx < 0 || barIdx < 0 || barIdx >= g_barsInDay)
      return 0;
   const double levelPx = g_levelsExpanded[expandedIdx].levelPrice;
   if(levelPx <= 0.0)
      return 0;
   const double closePx = g_m1Rates[barIdx].close;
   if(closePx > levelPx)
      return g_cleanStreakAbove[expandedIdx][barIdx];
   if(closePx < levelPx)
      return g_cleanStreakBelow[expandedIdx][barIdx];
   return 0;
}

//+------------------------------------------------------------------+
double FalgoLevelAnchorValueInStreakAtBarForExpandedIdx(const int expandedIdx, const int barIdx)
{
   if(expandedIdx < 0 || barIdx < 0 || barIdx >= g_barsInDay)
      return 0.0;
   const double levelPx = g_levelsExpanded[expandedIdx].levelPrice;
   if(levelPx <= 0.0)
      return 0.0;
   const double closePx = g_m1Rates[barIdx].close;
   AlgoFamilyLevelDayStatsAtBar s;
   if(FalgoTryGetAlgoFamilyLevelStatsCacheAtBar(levelPx, barIdx, s))
   {
      if(closePx > levelPx)
         return s.anchorAbove;
      if(closePx < levelPx)
         return s.anchorBelow;
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| Closest level category mismatch → gates firstFail (from level categories). |
//+------------------------------------------------------------------+
string AlgoClosestLevelCategoryGateFailLabelForAlgo(const int expandedLevelIdx, const int algoNumber)
{
   if(expandedLevelIdx < 0 || expandedLevelIdx >= g_levelsTodayCount)
      return "noClosestLevelExpanded";

   const string categories = g_levelsExpanded[expandedLevelIdx].categories;
   if(LevelIsTertiary(categories))
      return "closestLevelIsTertiary";
   if(LevelIsStacked(categories))
      return "closestLevelIsStacked";
   if(LevelIsWeekly(categories))
      return "closestLevelIsWeekly";
   if(LevelIsDailyKind(categories))
      return "closestLevelIsDaily";

   FatalError(StringFormat(
      "AlgoClosestLevelCategoryGateFailLabelForAlgo: algo %d level idx %d categories \"%s\" — not weekly/daily/stacked/tertiary",
      algoNumber, expandedLevelIdx, categories));
   return "";
}

int FalgoClosestExpandedLevelIdxAtBar(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return -1;
   return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevelExpandedIdx;
}

//+------------------------------------------------------------------+
//| Closest weekly level: clean OHLC streak on price side (above→g_cleanStreakAbove, below→g_cleanStreakBelow). |
//+------------------------------------------------------------------+
int FalgoLevelCleanOHLCStreakAtBar(const int barIdx)
{
   const int levelIdx = FalgoClosestExpandedLevelIdxAtBar(barIdx);
   if(levelIdx < 0 || barIdx < 0 || barIdx >= g_barsInDay)
      return 0;
   const double levelPx = g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevelToCClose;
   if(levelPx <= 0.0)
      return 0;
   const double closePx = g_m1Rates[barIdx].close;
   if(closePx > levelPx)
      return g_cleanStreakAbove[levelIdx][barIdx];
   if(closePx < levelPx)
      return g_cleanStreakBelow[levelIdx][barIdx];
   return 0;
}

//+------------------------------------------------------------------+
double FalgoLevelAnchorValueInStreakAtBar(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return 0.0;
   const double levelPx = g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevelToCClose;
   if(levelPx <= 0.0)
      return 0.0;
   const double closePx = g_m1Rates[barIdx].close;
   if(closePx > levelPx)
      return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevel_anchorAbove_within_cleanOHLC_streak;
   if(closePx < levelPx)
      return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevel_anchorBelow_within_cleanOHLC_streak;
   return 0.0;
}

//+------------------------------------------------------------------+
string AlgoClosestLevelGateFailLabelForAlgo(const int expandedLevelIdx, const int algoNumber)
{
   if(!FalgoLevelEligibleForAlgo(expandedLevelIdx, algoNumber, FalgoLevelEligibilityTimeForBar(-1)))
      return AlgoClosestLevelCategoryGateFailLabelForAlgo(expandedLevelIdx, algoNumber);
   return "";
}

//+------------------------------------------------------------------+
string AlgoClosestLevelGateFailLabelForAlgoAtBar(const int expandedLevelIdx, const int algoNumber, const int barIdx)
{
   if(!FalgoLevelEligibleForAlgo(expandedLevelIdx, algoNumber, FalgoLevelEligibilityTimeForBar(barIdx)))
      return AlgoClosestLevelCategoryGateFailLabelForAlgo(expandedLevelIdx, algoNumber);
   return "";
}

//+------------------------------------------------------------------+
void FalgoResetPlanCountersIfNewDay(const datetime dayStart)
{
   if(dayStart == 0 || g_falgoPlanCountersDayStart == dayStart)
      return;
   g_falgoPlanCountersDayStart = dayStart;
   for(int ai = 0; ai < ALGO_FAMILY_REGISTRY_MAX; ai++)
   {
      g_algoPlanTradeNumToday[ai] = 0;
      for(int levelSlot = 0; levelSlot < FALGO_MAGIC_LEVEL_SLOT_COUNT; levelSlot++)
         g_algoLevelTradeNumByMagicSlot[ai][levelSlot] = 0;
   }
}

//+------------------------------------------------------------------+
void FalgoBumpPlanCountersAfterPlacement(const int algoNumber, const int levelSlot)
{
   const int algoIdx = AlgoFamilySlotArrayIndex(algoNumber);
   if(algoIdx < 0)
      return;
   g_algoPlanTradeNumToday[algoIdx]++;
   if(FalgoMagicLevelSlotIsValid(levelSlot))
      g_algoLevelTradeNumByMagicSlot[algoIdx][levelSlot]++;
}

//+------------------------------------------------------------------+
bool FalgoIsTradingDayAllowed(const datetime t)
{
   if(FalgoIsNonTradeCalendarDate(t))
      return false;
   int slot = FalgoDayOfWeekSlotFromTimeOrInvalid(t);
   if(slot < 1)
      return false;
   string days = g_algoShared.tradesDays;
   if(StringLen(days) < 1)
      return true;
   return (StringFind(days, IntegerToString(slot)) >= 0);
}

//+------------------------------------------------------------------+
string FalgoBoolCsv(const bool v) { return v ? "true" : "false"; }

//+------------------------------------------------------------------+
bool FalgoIsTradingDayAllowedAtTime(const datetime t)
{
   return FalgoIsTradingDayAllowed(t);
}

//+------------------------------------------------------------------+
//| Placement only: day + banned-time + family day stops. Open-position babysit ignores trading time. |
//+------------------------------------------------------------------+
bool FalgoProfileAllowsPlacementAtTime(const datetime t)
{
   if(!AlgoFamilyAnyEnabled())
      return false;
   if(!FalgoIsTradingDayAllowedAtTime(t))
      return false;
   if(!FalgoIsTradingTimeAllowed(t))
      return false;
   if(!AlgoFamilyDayAllowsNewTrades())
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool FalgoProfileAllowsNewOrdersNow()
{
   return FalgoProfileAllowsPlacementAtTime(g_lastTimer1Time);
}

//+------------------------------------------------------------------+
//| Plan/level trade nums from today's filled Falgo deals only (not pending place/expire). |
//+------------------------------------------------------------------+
void SyncFalgoPlanCountersFromTradeResults()
{
   const datetime dayStart = FalgoTradingDayStart();

   int histPlan[ALGO_FAMILY_REGISTRY_MAX];
   int histLevel[ALGO_FAMILY_REGISTRY_MAX][FALGO_MAGIC_LEVEL_SLOT_COUNT];
   for(int ai = 0; ai < ALGO_FAMILY_REGISTRY_MAX; ai++)
   {
      histPlan[ai] = 0;
      for(int levelSlot = 0; levelSlot < FALGO_MAGIC_LEVEL_SLOT_COUNT; levelSlot++)
         histLevel[ai][levelSlot] = 0;
   }

   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      if(!IsAnyAlgoFamilyCompositeMagic(g_tradeResults[i].magic))
         continue;
      if(!FalgoTradeStartedOnTradingDay(g_tradeResults[i], dayStart))
         continue;
      if(IsBreakdownFamilyCompositeMagic(g_tradeResults[i].magic))
         continue;
      const int algoIdx = AlgoFamilySlotArrayIndex(AlgoFamilyMagicNumber(g_tradeResults[i].magic));
      if(algoIdx < 0)
         continue;
      histPlan[algoIdx]++;
      FalgoMagicKey fk = ParseFalgoMagic(g_tradeResults[i].magic);
      if(!FalgoMagicLevelSlotIsValid(fk.levelSlot))
         continue;
      histLevel[algoIdx][fk.levelSlot]++;
   }

   for(int ai = 0; ai < ALGO_FAMILY_REGISTRY_MAX; ai++)
   {
      g_algoPlanTradeNumToday[ai] = MathMax(g_algoPlanTradeNumToday[ai], histPlan[ai]);
      for(int levelSlot = 0; levelSlot < FALGO_MAGIC_LEVEL_SLOT_COUNT; levelSlot++)
         g_algoLevelTradeNumByMagicSlot[ai][levelSlot] =
            MathMax(g_algoLevelTradeNumByMagicSlot[ai][levelSlot], histLevel[ai][levelSlot]);
   }
}

//+------------------------------------------------------------------+
void SyncBreakdownPlanCountersFromTradeResults()
{
   const datetime dayStart = FalgoTradingDayStart();

   int histPlan[BREAKDOWN_ALGO_REGISTRY_MAX];
   int histLevel[BREAKDOWN_ALGO_REGISTRY_MAX];
   for(int bi = 0; bi < BREAKDOWN_ALGO_REGISTRY_MAX; bi++)
   {
      histPlan[bi] = 0;
      histLevel[bi] = 0;
   }

   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      if(!IsBreakdownFamilyCompositeMagic(g_tradeResults[i].magic))
         continue;
      if(!FalgoTradeStartedOnTradingDay(g_tradeResults[i], dayStart))
         continue;
      const int algoIdx = BreakdownAlgoSlotIndexByAlgoId(AlgoFamilyMagicNumber(g_tradeResults[i].magic));
      if(algoIdx < 0)
         continue;
      histPlan[algoIdx]++;
      FalgoMagicKey fk = ParseFalgoMagic(g_tradeResults[i].magic);
      if(FalgoMagicLevelSlotIsValid(fk.levelSlot))
         histLevel[algoIdx]++;
   }

   for(int bi = 0; bi < BREAKDOWN_ALGO_REGISTRY_MAX; bi++)
   {
      g_breakdownAlgoPlanTradeNumToday[bi] = MathMax(g_breakdownAlgoPlanTradeNumToday[bi], histPlan[bi]);
      g_breakdownAlgoLevelTradeNumToday[bi] = MathMax(g_breakdownAlgoLevelTradeNumToday[bi], histLevel[bi]);
   }
}

//+------------------------------------------------------------------+
void UpdateFalgoDayTradeCounts()
{
   const datetime dayStart = FalgoTradingDayStart();
   if(dayStart != 0 && g_falgoDayTradeCountsDayStart != dayStart)
   {
      g_falgoDayTradeCountsDayStart = dayStart;
      g_falgoPlanCountersDayStart = dayStart;
      FalgoResetAllDayCounterStateForNewTradingDay();
   }

   SyncFalgoPlanCountersFromTradeResults();

   int histFamilyWins = 0;
   int histFamilyLosses = 0;
   int histAlgoWins[ALGO_FAMILY_REGISTRY_MAX];
   int histAlgoLosses[ALGO_FAMILY_REGISTRY_MAX];
   for(int si = 0; si < ALGO_FAMILY_REGISTRY_MAX; si++)
   {
      histAlgoWins[si] = 0;
      histAlgoLosses[si] = 0;
   }
   double histGrossProfit = 0.0;
   double histGrossLossAbs = 0.0;
   const datetime dayEnd = (dayStart != 0) ? (dayStart + 86400) : 0;

   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      if(!g_tradeResults[i].foundOut)
         continue;
      if(!IsLevelFamilyCompositeMagic(g_tradeResults[i].magic))
         continue;
      if(dayStart != 0 && (g_tradeResults[i].endTime < dayStart || g_tradeResults[i].endTime >= dayEnd))
         continue;
      const int algoIdx = AlgoFamilySlotArrayIndex(AlgoFamilyMagicNumber(g_tradeResults[i].magic));
      if(g_tradeResults[i].profit > 0.0)
      {
         histFamilyWins++;
         histGrossProfit += g_tradeResults[i].profit;
         if(algoIdx >= 0)
            histAlgoWins[algoIdx]++;
      }
      else if(g_tradeResults[i].profit < 0.0)
      {
         histFamilyLosses++;
         histGrossLossAbs += -g_tradeResults[i].profit;
         if(algoIdx >= 0)
            histAlgoLosses[algoIdx]++;
      }
   }

   // Keep babysit bumps until today's g_tradeResults catches up on next M1 bar.
   g_algoFamilyDayWins = MathMax(g_algoFamilyDayWins, histFamilyWins);
   g_algoFamilyDayLosses = MathMax(g_algoFamilyDayLosses, histFamilyLosses);
   for(int si = 0; si < ALGO_FAMILY_REGISTRY_MAX; si++)
   {
      g_algoDayWins[si] = MathMax(g_algoDayWins[si], histAlgoWins[si]);
      g_algoDayLosses[si] = MathMax(g_algoDayLosses[si], histAlgoLosses[si]);
   }
   g_algoFamilyDayGrossProfit = MathMax(g_algoFamilyDayGrossProfit, histGrossProfit);
   g_algoFamilyDayGrossLossAbs = MathMax(g_algoFamilyDayGrossLossAbs, histGrossLossAbs);
}

//+------------------------------------------------------------------+
void AlgoFamilyDayStopBumpFromBabysitClose(const long positionMagic, const double profitPtsBeforeClose,
   const double accountProfitBeforeClose)
{
   if(!IsAnyAlgoFamilyCompositeMagic(positionMagic))
      return;
   const int algoNumber = AlgoFamilyMagicNumber(positionMagic);
   if(IsBreakdownFamilyAlgoNumber(algoNumber))
   {
      const int algoIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
      if(profitPtsBeforeClose > 0.0)
      {
         g_breakdownFamilyDayWins++;
         if(algoIdx >= 0)
            g_breakdownAlgoDayWins[algoIdx]++;
      }
      else if(profitPtsBeforeClose < 0.0)
      {
         g_breakdownFamilyDayLosses++;
         if(algoIdx >= 0)
            g_breakdownAlgoDayLosses[algoIdx]++;
      }
      return;
   }
   const int algoIdx = AlgoFamilySlotArrayIndex(algoNumber);
   if(profitPtsBeforeClose > 0.0)
   {
      g_algoFamilyDayWins++;
      if(algoIdx >= 0)
         g_algoDayWins[algoIdx]++;
   }
   else if(profitPtsBeforeClose < 0.0)
   {
      g_algoFamilyDayLosses++;
      if(algoIdx >= 0)
         g_algoDayLosses[algoIdx]++;
   }
   if(accountProfitBeforeClose > 0.0)
      g_algoFamilyDayGrossProfit += accountProfitBeforeClose;
   else if(accountProfitBeforeClose < 0.0)
      g_algoFamilyDayGrossLossAbs += -accountProfitBeforeClose;
}

//+------------------------------------------------------------------+
void FalgoAfterFamilyPositionClosed(const long positionMagic, const double profitPtsBeforeClose,
   const double accountProfitBeforeClose, const int telemetrySlotIdx)
{
   AlgoFamilyDayStopBumpFromBabysitClose(positionMagic, profitPtsBeforeClose, accountProfitBeforeClose);

   const int closedBarIdx = FalgoBarIdxForDayTime(g_lastTimer1Time);
   const int algoNumber = AlgoFamilyMagicNumber(positionMagic);
   if(IsBreakdownFamilyAlgoNumber(algoNumber))
   {
      if(BreakdownFamilyBlocksPlacementOnOpenOrPending())
         g_breakdownFamilyHadCloseThisPipelinePass = true;
   }
   else
   {
      const int ri = FalgoRegistrySlotForAlgoNumber(algoNumber);
      if(ri >= 0 && closedBarIdx >= 0)
         g_falgoLastTradeClosedBarIdx[ri] = closedBarIdx;
      if(AlgoFamilyBlocksPlacementOnOpenOrPending() && closedBarIdx >= 0)
         g_falgoFamilyLastClosedBarIdx = closedBarIdx;
      if(AlgoFamilyBlocksPlacementOnOpenOrPending())
         g_algoFamilyHadCloseThisPipelinePass = true;
   }

   if(telemetrySlotIdx >= 0)
   {
      g_falgoOpenTelemetryCtx = telemetrySlotIdx;
      FalgoOnFalgoTradeClosedThisBar();
      FalgoTelemetryPushClosedSummaryFromOpen();
      FalgoTelemetryClearOpenState();
      g_falgoOpenTelemetryCtx = -1;
   }
}

//+------------------------------------------------------------------+
double FalgoSelectedPositionAccountProfit()
{
   return ExtPositionInfo.Profit() + ExtPositionInfo.Swap() + ExtPositionInfo.Commission();
}

//+------------------------------------------------------------------+
//| Open P/L as % of position deposit equivalent: lot × one_lot_equals_xPLN. |
//+------------------------------------------------------------------+
double FalgoOpenPositionProfitPctOfPositionDeposit()
{
   if(one_lot_equals_xPLN <= 0.0)
      return 0.0;
   const double lot = ExtPositionInfo.Volume();
   if(lot <= 0.0)
      return 0.0;
   const double positionDepositPln = lot * one_lot_equals_xPLN;
   if(positionDepositPln <= 0.0)
      return 0.0;
   return 100.0 * FalgoSelectedPositionAccountProfit() / positionDepositPln;
}

//+------------------------------------------------------------------+
void FalgoOverlayLiveDayStatsOnLastBar()
{
   if(g_barsInDay <= 0)
      return;

   const int kLast = g_barsInDay - 1;
   const int liveClosed = g_breakdownFamilyDayWins + g_breakdownFamilyDayLosses;
   if(liveClosed <= g_dayProgress[kLast].dayTradesCount)
      return;

   g_dayProgress[kLast].dayTradesCount = liveClosed;
   g_dayProgress[kLast].dayWinRate = (liveClosed > 0)
      ? ((double)g_algoFamilyDayWins / (double)liveClosed)
      : 0.0;
   g_dayProgress[kLast].dayProfitSum = g_breakdownFamilyDayGrossProfit - g_breakdownFamilyDayGrossLossAbs;
   g_dayProgress[kLast].dayProfitFactor = AlgoFamilyDayProfitFactorToday();

   g_pullingHistoryAlgoFamilyWeeklyAtBar[kLast].dayWinRate = g_dayProgress[kLast].dayWinRate;
   g_pullingHistoryAlgoFamilyWeeklyAtBar[kLast].dayTradesCount = g_dayProgress[kLast].dayTradesCount;
   g_pullingHistoryAlgoFamilyWeeklyAtBar[kLast].dayProfitSum = g_dayProgress[kLast].dayProfitSum;
   g_pullingHistoryAlgoFamilyWeeklyAtBar[kLast].dayProfitFactor = g_dayProgress[kLast].dayProfitFactor;
   g_pullingHistoryAlgoFamilyDailyAtBar[kLast].dayWinRate = g_dayProgress[kLast].dayWinRate;
   g_pullingHistoryAlgoFamilyDailyAtBar[kLast].dayTradesCount = g_dayProgress[kLast].dayTradesCount;
   g_pullingHistoryAlgoFamilyDailyAtBar[kLast].dayProfitSum = g_dayProgress[kLast].dayProfitSum;
   g_pullingHistoryAlgoFamilyDailyAtBar[kLast].dayProfitFactor = g_dayProgress[kLast].dayProfitFactor;

   if(g_breakdownFamilyHadCloseThisPipelinePass && g_lastTimer1Time > 0)
   {
      g_pullingHistoryAlgoFamilyWeeklyAtBar[kLast].accLastClosedTradeTime = g_lastTimer1Time;
      g_pullingHistoryAlgoFamilyDailyAtBar[kLast].accLastClosedTradeTime = g_lastTimer1Time;
   }
}

//+------------------------------------------------------------------+
bool FalgoHasOpenPositionOnSymbol()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!ExtPositionInfo.SelectByIndex(i)) continue;
      if(ExtPositionInfo.Symbol() != _Symbol) continue;
      if(IsAnyAlgoFamilyCompositeMagic(ExtPositionInfo.Magic()))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool FalgoHasPendingOrderOnSymbol()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ExtOrderInfo.SelectByIndex(i)) continue;
      if(ExtOrderInfo.Symbol() != _Symbol) continue;
      if(IsAnyAlgoFamilyCompositeMagic(ExtOrderInfo.Magic()))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Core algo-family rule: this algo slot (10..15) has an open position on _Symbol. |
//+------------------------------------------------------------------+
bool AlgoHasOpenPositionOnSymbol(const int algoNumber)
{
   if(algoNumber < MAGIC_ALGO_FAMILY_SLOT_MIN || algoNumber > MAGIC_ALGO_FAMILY_SLOT_MAX)
      return false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!ExtPositionInfo.SelectByIndex(i)) continue;
      if(ExtPositionInfo.Symbol() != _Symbol) continue;
      if(AlgoFamilyMagicNumber(ExtPositionInfo.Magic()) == algoNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool AlgoHasPendingOrderOnSymbol(const int algoNumber)
{
   if(algoNumber < MAGIC_ALGO_FAMILY_SLOT_MIN || algoNumber > MAGIC_ALGO_FAMILY_SLOT_MAX)
      return false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ExtOrderInfo.SelectByIndex(i)) continue;
      if(ExtOrderInfo.Symbol() != _Symbol) continue;
      if(AlgoFamilyMagicNumber(ExtOrderInfo.Magic()) == algoNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool AlgoHasOpenOrPendingOnSymbol(const int algoNumber)
{
   return AlgoHasOpenPositionOnSymbol(algoNumber) || AlgoHasPendingOrderOnSymbol(algoNumber);
}

//+------------------------------------------------------------------+
bool CanPlaceNewOrderForAlgo(const int algoNumber)
{
   return !AlgoHasOpenOrPendingOnSymbol(algoNumber);
}

//+------------------------------------------------------------------+
double FalgoOpenPositionProfitPoints()
{
   const double openPrice = ExtPositionInfo.PriceOpen();
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY)
      return SymbolInfoDouble(_Symbol, SYMBOL_BID) - openPrice;
   return openPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK);
}

//+------------------------------------------------------------------+
int FalgoGetBounceCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevel_BounceCount_today;
}

//+------------------------------------------------------------------+
int FalgoGetCeilingCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevel_CeilingCount_today;
}

//+------------------------------------------------------------------+
int FalgoGetCeilingProximityCandlesForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevel_CeilingProximityCandles_today;
}

//+------------------------------------------------------------------+
int FalgoGetWeekBounceCountForLevelAtBar(const int barIdx, const double levelPrice)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || levelPrice <= 0.0)
      return 0;
   const datetime asOfTime = g_m1Rates[barIdx].time + 60;
   int dBounce = 0, dCeiling = 0;
   AlgoFamilyDayBounceCeilingForLevelAsOfTime(levelPrice, asOfTime, dBounce, dCeiling);
   return AlgoFamilyDayStartWeekPerspectiveBounceForLevel(levelPrice) + dBounce;
}

//+------------------------------------------------------------------+
int FalgoGetWeekCeilingCountForLevelAtBar(const int barIdx, const double levelPrice)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || levelPrice <= 0.0)
      return 0;
   const datetime asOfTime = g_m1Rates[barIdx].time + 60;
   int dBounce = 0, dCeiling = 0;
   AlgoFamilyDayBounceCeilingForLevelAsOfTime(levelPrice, asOfTime, dBounce, dCeiling);
   return AlgoFamilyDayStartWeekPerspectiveCeilingForLevel(levelPrice) + dCeiling;
}

//+------------------------------------------------------------------+
int FalgoGetWeekBounceCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return 0;
   const double levelPrice = g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevelToCClose;
   return FalgoGetWeekBounceCountForLevelAtBar(barIdx, levelPrice);
}

//+------------------------------------------------------------------+
int FalgoGetWeekCeilingCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return 0;
   const double levelPrice = g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevelToCClose;
   return FalgoGetWeekCeilingCountForLevelAtBar(barIdx, levelPrice);
}

//+------------------------------------------------------------------+
int FalgoGetRecentBounceCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevel_BounceCount_recent;
}

//+------------------------------------------------------------------+
int FalgoGetRecentCeilingCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].closestWeeklyLevel_CeilingCount_recent;
}

//+------------------------------------------------------------------+
//| Open Falgo trade telemetry (1s OnTimer): green/red time, velocity, peak profit. |
//+------------------------------------------------------------------+
int FalgoOpenTelemetryFindSlotByTicket(const ulong ticket)
{
   if(ticket == 0)
      return -1;
   for(int si = 0; si < FALGO_OPEN_TELEMETRY_MAX; si++)
   {
      if(g_falgoOpenTelemetrySlots[si].active && g_falgoOpenTelemetrySlots[si].positionTicket == ticket)
         return si;
   }
   return -1;
}

//+------------------------------------------------------------------+
int FalgoOpenTelemetryFindSlotByMagicStart(const long magic, const datetime startTime)
{
   for(int si = 0; si < FALGO_OPEN_TELEMETRY_MAX; si++)
   {
      if(!g_falgoOpenTelemetrySlots[si].active)
         continue;
      if(g_falgoOpenTelemetrySlots[si].magic == magic && g_falgoOpenTelemetrySlots[si].tradeStartTime == startTime)
         return si;
   }
   return -1;
}

//+------------------------------------------------------------------+
int FalgoOpenTelemetryAllocSlot()
{
   for(int si = 0; si < FALGO_OPEN_TELEMETRY_MAX; si++)
   {
      if(!g_falgoOpenTelemetrySlots[si].active)
         return si;
   }
   return -1;
}

//+------------------------------------------------------------------+
bool FalgoPositionTicketStillOpen(const ulong ticket)
{
   if(ticket == 0)
      return false;
   if(!ExtPositionInfo.SelectByTicket(ticket))
      return false;
   if(ExtPositionInfo.Symbol() != _Symbol)
      return false;
   return IsAnyAlgoFamilyCompositeMagic(ExtPositionInfo.Magic());
}

//+------------------------------------------------------------------+
void FalgoTelemetryClearOpenState()
{
   if(g_falgoOpenTelemetryCtx < 0 || g_falgoOpenTelemetryCtx >= FALGO_OPEN_TELEMETRY_MAX)
      return;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active = false;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].positionTicket = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeStartTime = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsGreen = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsRed = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveGreen = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveRed = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts = 0.0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts = 0.0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePts = 0.0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maeFirstWindowPts = 0.0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePostXPts = 0.0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfeCandle1Based = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maeCandle1Based = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].timeToReachNeutralTpSeconds = -1;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocity = 0.0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgVelocitySampleCount = 0;
   ArrayInitialize(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocityParamTest, 0.0);
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].ringCount = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].ringWriteIdx = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].lastBarIdx = -1;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].aimStrongTp = false;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].strongMomentumPeakAvgVelocity = 0.0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].badTradeMode = false;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].terribleTradeMode = false;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitMode = FALGO_EXIT_MODE_NEUTRAL;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitModePrev = "";
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitModeChanged = false;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].closeDecisionReason = "";
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].closeDecisionDetail = "";
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].breakdownSequenceEndTime = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].breakdownTimeExitDeadline = 0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].breakdownStartHigh = 0.0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].breakdownLow = 0.0;
   ArrayInitialize(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].profitRing, 0.0);
   ArrayInitialize(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].timeRing, 0);
}

//+------------------------------------------------------------------+
void FalgoTelemetryClearAllOpenSlots()
{
   for(int si = 0; si < FALGO_OPEN_TELEMETRY_MAX; si++)
   {
      g_falgoOpenTelemetryCtx = si;
      FalgoTelemetryClearOpenState();
   }
   g_falgoOpenTelemetryCtx = -1;
}

//+------------------------------------------------------------------+
void FalgoInitPerAlgoTelemetryDayState()
{
   for(int ri = 0; ri < ALGO_FAMILY_REGISTRY_MAX; ri++)
      g_falgoLastTradeClosedBarIdx[ri] = -1;
   FalgoClearTelemetryBarSnaps();
}

//+------------------------------------------------------------------+
void FalgoClearTelemetryBarSnaps()
{
   for(int barIdx = 0; barIdx < MAX_BARS_IN_DAY; barIdx++)
   {
      for(int ri = 0; ri < ALGO_FAMILY_REGISTRY_MAX; ri++)
      {
         g_falgoTelemetryAtBar[barIdx][ri].valid = false;
         g_falgoTelemetryAtBar[barIdx][ri].tradeClosedOnThisBar = false;
      }
   }
}

//+------------------------------------------------------------------+
//| 1-based M1 minute index from trade open bar through atTime (per-second telemetry). |
//+------------------------------------------------------------------+
int FalgoTradeMinuteCandle1BasedFromStart(const datetime tradeStartTime, const datetime atTime)
{
   if(tradeStartTime <= 0 || atTime < tradeStartTime)
      return 0;
   const datetime startBarOpen = tradeStartTime - (tradeStartTime % 60);
   const datetime atBarOpen = atTime - (atTime % 60);
   return (int)((atBarOpen - startBarOpen) / 60) + 1;
}

//+------------------------------------------------------------------+
void FalgoTelemetrySnapOpenStateToBar(const int barIdx, const bool tradeClosedOnThisBar = false)
{
   if(g_falgoOpenTelemetryCtx < 0 || g_falgoOpenTelemetryCtx >= FALGO_OPEN_TELEMETRY_MAX)
      return;
   if(barIdx < 0 || barIdx >= g_barsInDay || !g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active)
      return;
   FalgoTelemetryBarSnap snap;
   snap.valid = true;
   snap.magic = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic;
   snap.tradeAgeSeconds = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds;
   snap.openProfitPts = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts;
   snap.secondsGreen = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsGreen;
   snap.secondsRed = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsRed;
   snap.greenRatio = FalgoTelemetryGreenRatioFromOpen();
   snap.consecutiveGreen = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveGreen;
   snap.consecutiveRed = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveRed;
   AlgoPerAlgoTune telTune;
   if(FalgoLoadTelemetryTuneForMagic(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic, telTune))
      snap.profitVelocity = FalgoTelemetryProfitVelocityWindowSeconds(telTune.telemetry_velocity_window_seconds);
   else
      snap.profitVelocity = 0.0;
   snap.mfePts = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts;
   snap.maePts = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePts;
   snap.profitFromPeak = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts - g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts;
   snap.tradeClosedOnThisBar = tradeClosedOnThisBar;
   const int regSlot = FalgoRegistrySlotForAlgoNumber(AlgoFamilyMagicNumber(snap.magic));
   if(regSlot < 0)
      return;
   g_falgoTelemetryAtBar[barIdx][regSlot] = snap;
}

//+------------------------------------------------------------------+
void FalgoTelemetrySnapOpenStateToLastBar(const bool tradeClosedOnThisBar = false)
{
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].lastBarIdx >= 0)
      FalgoTelemetrySnapOpenStateToBar(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].lastBarIdx, tradeClosedOnThisBar);
   else
   {
      const int barIdx = FalgoBarIdxForDayTime(g_lastTimer1Time);
      if(barIdx >= 0)
         FalgoTelemetrySnapOpenStateToBar(barIdx, tradeClosedOnThisBar);
   }
}

//+------------------------------------------------------------------+
void FalgoGatesTelemetryStringsFromBarSnap(const FalgoTelemetryBarSnap &snap,
   string &outTradeAge, string &outOpenProfit, string &outSecGreen, string &outSecRed, string &outGreenRatio,
   string &outConsecGreen, string &outConsecRed, string &outProfitVelocity, string &outPeakProfit, string &outProfitFromPeak)
{
   outTradeAge = IntegerToString(snap.tradeAgeSeconds);
   outOpenProfit = DoubleToString(snap.openProfitPts, 1);
   outSecGreen = IntegerToString(snap.secondsGreen);
   outSecRed = IntegerToString(snap.secondsRed);
   outGreenRatio = DoubleToString(snap.greenRatio, 4);
   outConsecGreen = IntegerToString(snap.consecutiveGreen);
   outConsecRed = IntegerToString(snap.consecutiveRed);
   outProfitVelocity = DoubleToString(snap.profitVelocity, 3);
   outPeakProfit = DoubleToString(snap.mfePts, 1);
   outProfitFromPeak = DoubleToString(snap.profitFromPeak, 1);
}

//+------------------------------------------------------------------+
void FalgoResetTelemetryIfNewDay(const datetime dayStart)
{
   if(dayStart == 0)
      return;
   if(g_falgoTelemetryDayStart == dayStart)
      return;
   g_falgoTelemetryDayStart = dayStart;
   g_falgoClosedTelemetryCount = 0;
   g_falgoTelemetryLastUpdateTime = 0;
   FalgoInitPerAlgoTelemetryDayState();
   FalgoTelemetryClearAllOpenSlots();
}

//+------------------------------------------------------------------+
double FalgoTelemetryGreenRatioFromOpen()
{
   if(g_falgoOpenTelemetryCtx < 0 || g_falgoOpenTelemetryCtx >= FALGO_OPEN_TELEMETRY_MAX)
      return 0.0;
   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active || g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds <= 0)
      return 0.0;
   return (double)g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsGreen / (double)g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds;
}

//+------------------------------------------------------------------+
void FalgoTelemetryPushProfitSample(const datetime sampleTime, const double profitPts)
{
   const int cap = FALGO_TELEMETRY_PROFIT_RING_MAX;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].profitRing[g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].ringWriteIdx] = profitPts;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].timeRing[g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].ringWriteIdx] = sampleTime;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].ringWriteIdx = (g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].ringWriteIdx + 1) % cap;
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].ringCount < cap)
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].ringCount++;
}

//+------------------------------------------------------------------+
double FalgoTelemetryProfitVelocityWindowSeconds(const int windowSec)
{
   if(g_falgoOpenTelemetryCtx < 0 || g_falgoOpenTelemetryCtx >= FALGO_OPEN_TELEMETRY_MAX)
      return 0.0;
   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active || windowSec <= 0 || g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds <= 0)
      return 0.0;
   const int cap = FALGO_TELEMETRY_PROFIT_RING_MAX;
   const datetime targetTime = g_lastTimer1Time - windowSec;
   double oldProfit = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts;
   bool found = false;
   for(int age = 0; age < g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].ringCount; age++)
   {
      const int idx = (g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].ringWriteIdx - 1 - age + cap) % cap;
      if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].timeRing[idx] <= targetTime)
      {
         oldProfit = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].profitRing[idx];
         found = true;
         break;
      }
   }
   if(!found && g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].ringCount > 0)
   {
      const int oldestIdx = (g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].ringWriteIdx - g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].ringCount + cap) % cap;
      oldProfit = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].profitRing[oldestIdx];
   }
   int deltaSec = windowSec;
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds < deltaSec)
      deltaSec = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds;
   if(deltaSec <= 0)
      return 0.0;
   return (g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts - oldProfit) / (double)deltaSec * FALGO_VELOCITY_LOG_SCALE;
}

//+------------------------------------------------------------------+
//| FILE_CSV treats comma as column break — strip/replace in free-text fields. |
//+------------------------------------------------------------------+
string FalgoSanitizeCsvCell(const string s)
{
   if(s == "")
      return s;
   string out = s;
   StringReplace(out, ",", ";");
   StringReplace(out, "\r", " ");
   StringReplace(out, "\n", " ");
   return out;
}

//+------------------------------------------------------------------+
string AlgoGatesColProfitVelocity(const int algoSlot1)
{
   AlgoPerAlgoTune tune;
   if(!AlgoLoadPerAlgoTune(algoSlot1, tune) || tune.telemetry_velocity_window_seconds <= 0)
      return "profitVelocity_0";
   return StringFormat("profitVelocity_%d_x10", tune.telemetry_velocity_window_seconds);
}

//+------------------------------------------------------------------+
string AlgoGatesColAvgProfitVelocity(const int algoSlot1)
{
   AlgoPerAlgoTune tune;
   if(!AlgoLoadPerAlgoTune(algoSlot1, tune) || tune.telemetry_avg_velocity_window_seconds <= 0)
      return "avg_profitVelocity_0";
   return StringFormat("avg_profitVelocity_%d_x10", tune.telemetry_avg_velocity_window_seconds);
}

//+------------------------------------------------------------------+
string AlgoGatesColMaePostX(const int algoSlot1)
{
   AlgoPerAlgoTune tune;
   if(!AlgoLoadPerAlgoTune(algoSlot1, tune) || tune.start_mae_care_after_x_seconds <= 0)
      return "MAE_post_0";
   return StringFormat("MAE_post_%d", tune.start_mae_care_after_x_seconds);
}

//+------------------------------------------------------------------+
string FalgoGatesColProfitVelocity()
{
   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active)
   {
      if(g_algoCount > 0)
         return AlgoGatesColProfitVelocity(g_algos[0].algo_id);
      return "profitVelocity_0";
   }
   return AlgoGatesColProfitVelocity(AlgoFamilyMagicNumber(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic));
}

//+------------------------------------------------------------------+
string FalgoGatesColAvgProfitVelocity()
{
   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active)
   {
      if(g_algoCount > 0)
         return AlgoGatesColAvgProfitVelocity(g_algos[0].algo_id);
      return "avg_profitVelocity_0";
   }
   return AlgoGatesColAvgProfitVelocity(AlgoFamilyMagicNumber(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic));
}

//+------------------------------------------------------------------+
void FalgoTelemetryInitFromSelectedPosition()
{
   FalgoTelemetryClearOpenState();
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active = true;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].positionTicket = ExtPositionInfo.Ticket();
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic = ExtPositionInfo.Magic();
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeStartTime = ExtPositionInfo.Time();
   const double profitPts = FalgoOpenPositionProfitPoints();
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts = profitPts;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts = profitPts;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePts = profitPts;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maeFirstWindowPts = profitPts;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePostXPts = 0.0;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfeCandle1Based = FalgoTradeMinuteCandle1BasedFromStart(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeStartTime, g_lastTimer1Time);
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maeCandle1Based = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfeCandle1Based;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].lastBarIdx = FalgoBarIdxForDayTime(g_lastTimer1Time);
   const long posMagic = ExtPositionInfo.Magic();
   if(IsBreakdownFamilyCompositeMagic(posMagic))
   {
      const int algoNumber = AlgoFamilyMagicNumber(posMagic);
      const int bIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
      datetime breakdownEnd = 0;
      BreakdownOpenLifetimeBreakdownEnd((ulong)ExtPositionInfo.Identifier(), breakdownEnd);
      if(breakdownEnd > 0)
      {
         g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].breakdownSequenceEndTime = breakdownEnd;
         int exitMinAfterEnd = 60;
         if(bIdx >= 0 && g_breakdownAlgos[bIdx].closetrade_after_some_time)
            exitMinAfterEnd = g_breakdownAlgos[bIdx].closetrade_after_x_minutes_from_breakdown;
         g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].breakdownTimeExitDeadline =
            breakdownEnd + exitMinAfterEnd * 60;
      }
      if(bIdx >= 0)
      {
         g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].breakdownStartHigh = g_breakdownAlgoLastPlacedStartHigh[bIdx];
         g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].breakdownLow = g_breakdownAlgoLastPlacedBreakdownLow[bIdx];
      }
   }
   FalgoTelemetryPushProfitSample(g_lastTimer1Time, profitPts);
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].lastBarIdx >= 0)
      FalgoTelemetrySnapOpenStateToBar(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].lastBarIdx);
}

//+------------------------------------------------------------------+
void FalgoTelemetryFillSummaryFromOpen(FalgoClosedTradeTelemetrySummary &outSummary)
{
   outSummary.magic = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic;
   outSummary.startTime = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeStartTime;
   outSummary.secondsGreen = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsGreen;
   outSummary.secondsRed = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsRed;
   outSummary.greenRatioAtClose = FalgoTelemetryGreenRatioFromOpen();
   outSummary.avgProfitVelocity = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocity;
   outSummary.mfePts = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts;
   outSummary.maePts = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePts;
   outSummary.maeFirstWindowPts = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maeFirstWindowPts;
   outSummary.mfeCandle1Based = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfeCandle1Based;
   outSummary.maeCandle1Based = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maeCandle1Based;
   outSummary.timeToReachNeutralTpSeconds = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].timeToReachNeutralTpSeconds;
   outSummary.closeDecision = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].closeDecisionReason;
   outSummary.closeDetail = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].closeDecisionDetail;
}

//+------------------------------------------------------------------+
void FalgoTelemetryPushClosedSummaryFromOpen()
{
   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active)
      return;
   if(g_falgoClosedTelemetryCount >= FALGO_CLOSED_TELEMETRY_MAX)
      return;
   FalgoClosedTradeTelemetrySummary summary;
   FalgoTelemetryFillSummaryFromOpen(summary);
   for(int i = 0; i < g_falgoClosedTelemetryCount; i++)
   {
      if(g_falgoClosedTelemetry[i].magic == summary.magic && g_falgoClosedTelemetry[i].startTime == summary.startTime)
         return;
   }
   g_falgoClosedTelemetry[g_falgoClosedTelemetryCount] = summary;
   g_falgoClosedTelemetryCount++;
}

//+------------------------------------------------------------------+
bool FalgoFindClosedTelemetrySummary(const long magic, const datetime startTime, FalgoClosedTradeTelemetrySummary &outSummary)
{
   for(int i = 0; i < g_falgoClosedTelemetryCount; i++)
   {
      if(g_falgoClosedTelemetry[i].magic == magic && g_falgoClosedTelemetry[i].startTime == startTime)
      {
         outSummary = g_falgoClosedTelemetry[i];
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool FalgoGetTelemetrySummaryForTrade(const long magic, const datetime startTime, FalgoClosedTradeTelemetrySummary &outSummary)
{
   if(FalgoFindClosedTelemetrySummary(magic, startTime, outSummary))
      return true;
   const int slotIdx = FalgoOpenTelemetryFindSlotByMagicStart(magic, startTime);
   if(slotIdx < 0)
      return false;
   g_falgoOpenTelemetryCtx = slotIdx;
   FalgoTelemetryFillSummaryFromOpen(outSummary);
   return true;
}

//+------------------------------------------------------------------+
int FalgoStrongMomentumVelocityWindowSeconds(const AlgoPerAlgoTune &tune)
{
   if(tune.strong_trade_velocity_window_seconds > 0)
      return tune.strong_trade_velocity_window_seconds;
   if(tune.telemetry_velocity_window_seconds > 0)
      return tune.telemetry_velocity_window_seconds;
   return 5;
}

//+------------------------------------------------------------------+
bool FalgoStrongMomentumDetectPower(const double profitPts, const AlgoPerAlgoTune &tune)
{
   if(profitPts < PointSized(tune.strong_trade_eval_min_profit_pts))
      return false;
   const double vel = FalgoTelemetryProfitVelocityWindowSeconds(FalgoStrongMomentumVelocityWindowSeconds(tune));
   if(vel < tune.strong_trade_min_velocity_trigger)
      return false;
   return true;
}

//+------------------------------------------------------------------+
double FalgoTerribleTradeAvgProfitVelocity10(const AlgoPerAlgoTune &tune)
{
   if(tune.telemetry_avg_velocity_window_seconds == 10)
      return g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocity;
   return FalgoTelemetryProfitVelocityWindowSeconds(10);
}

//+------------------------------------------------------------------+
bool AlgoModeSwitchingEnabled()
{
   return g_algoShared.mode_switching_enabled;
}

//+------------------------------------------------------------------+
bool AlgoStrongTradeModeActive(const AlgoPerAlgoTune &tune)
{
   return AlgoModeSwitchingEnabled() && g_algoShared.strong_trade_mode_enabled && tune.strong_trade_mode_enabled;
}

//+------------------------------------------------------------------+
bool AlgoNeutralTradeModeActive(const AlgoPerAlgoTune &tune)
{
   return AlgoModeSwitchingEnabled() && g_algoShared.neutral_trade_mode_enabled && tune.neutral_trade_mode_enabled;
}

//+------------------------------------------------------------------+
bool AlgoBadTradeModeActive(const AlgoPerAlgoTune &tune)
{
   return AlgoModeSwitchingEnabled() && g_algoShared.badtrade_mode_enabled && tune.badtrade_mode_enabled;
}

//+------------------------------------------------------------------+
bool AlgoTerribleTradeModeActive(const AlgoPerAlgoTune &tune)
{
   return AlgoModeSwitchingEnabled() && g_algoShared.terribletrade_mode_enabled && tune.terribletrade_mode_enabled;
}

//+------------------------------------------------------------------+
void AlgoClearTradeRecoveryModeFlags()
{
   if(g_falgoOpenTelemetryCtx < 0 || g_falgoOpenTelemetryCtx >= FALGO_OPEN_TELEMETRY_MAX)
      return;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].badTradeMode = false;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].terribleTradeMode = false;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].aimStrongTp = false;
}

//+------------------------------------------------------------------+
bool FalgoBadTradeLatchConditionsMet(const AlgoPerAlgoTune &tune)
{
   if(!AlgoBadTradeModeActive(tune))
      return false;
   if(tune.badtrade_MaePostX_trigger >= 0.0)
      return false;
   if(tune.start_mae_care_after_x_seconds > 0 &&
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds < tune.start_mae_care_after_x_seconds)
      return false;
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePostXPts > PointSized(tune.badtrade_MaePostX_trigger))
      return false;
   if(tune.badtrade_totalRedSeconds_minTrigger > 0 &&
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsRed < tune.badtrade_totalRedSeconds_minTrigger)
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool FalgoTerribleTradeLatchConditionsMet(const AlgoPerAlgoTune &tune)
{
   if(!AlgoTerribleTradeModeActive(tune))
      return false;
   if(tune.terribletrade_MaePostX_trigger >= 0.0)
      return false;
   if(tune.start_mae_care_after_x_seconds > 0 &&
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds < tune.start_mae_care_after_x_seconds)
      return false;
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePostXPts > PointSized(tune.terribletrade_MaePostX_trigger))
      return false;
   if(tune.terribletrade_consecutiveRedSeconds_minTrigger > 0 &&
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveRed < tune.terribletrade_consecutiveRedSeconds_minTrigger)
      return false;
   if(tune.terribletrade_avgProfitVelocity10_trigger > 0.0 &&
      FalgoTerribleTradeAvgProfitVelocity10(tune) >= tune.terribletrade_avgProfitVelocity10_trigger)
      return false;
   return true;
}

//+------------------------------------------------------------------+
void FalgoTryLatchTradeRecoveryModes(const AlgoPerAlgoTune &tune)
{
   if(!AlgoModeSwitchingEnabled())
      return;
   if(FalgoTerribleTradeLatchConditionsMet(tune))
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].terribleTradeMode = true;
   if(FalgoBadTradeLatchConditionsMet(tune))
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].badTradeMode = true;
}

//+------------------------------------------------------------------+
void FalgoTryLatchStrongMomentumIfNeeded(const AlgoPerAlgoTune &tune, const double profitPts)
{
   if(!AlgoStrongTradeModeActive(tune) || g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].aimStrongTp)
      return;
   const double nearNeutral = (MathAbs(tune.neutral_trade_TP) > 0.0)
      ? PointSized(MathAbs(tune.neutral_trade_TP)) * 0.85
      : PointSized(tune.strong_trade_eval_min_profit_pts);
   if(profitPts >= nearNeutral && FalgoStrongMomentumDetectPower(profitPts, tune))
   {
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].aimStrongTp = true;
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].strongMomentumPeakAvgVelocity =
         g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocity;
   }
}

//+------------------------------------------------------------------+
void FalgoStrongMomentumUpdatePeakAvgIfAiming()
{
   if(g_falgoOpenTelemetryCtx < 0 || g_falgoOpenTelemetryCtx >= FALGO_OPEN_TELEMETRY_MAX)
      return;
   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].aimStrongTp)
      return;
   const double avg = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocity;
   if(avg > g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].strongMomentumPeakAvgVelocity)
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].strongMomentumPeakAvgVelocity = avg;
}

//+------------------------------------------------------------------+
string FalgoExitModeString(const AlgoPerAlgoTune &tune)
{
   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active)
      return FALGO_EXIT_MODE_NEUTRAL;
   const FalgoMagicKey fk = ParseFalgoMagic(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic);
   const int minutesOpen = (g_lastTimer1Time > 0 && g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeStartTime > 0)
      ? (int)((g_lastTimer1Time - g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeStartTime) / 60)
      : (g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds / 60);
   if(minutesOpen < fk.babysitMinute)
      return FALGO_EXIT_MODE_NEUTRAL;
   if(AlgoModeSwitchingEnabled())
   {
      if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].terribleTradeMode)
         return FALGO_EXIT_MODE_TERRIBLE_TRADE;
      if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].badTradeMode)
         return FALGO_EXIT_MODE_BAD_TRADE;
      if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].aimStrongTp)
         return FALGO_EXIT_MODE_GOOD_MOMENTUM;
   }
   if(!AlgoNeutralTradeModeActive(tune))
      return FALGO_EXIT_MODE_NEUTRAL;
   return FALGO_EXIT_MODE_NEUTRAL_TRADE;
}

//+------------------------------------------------------------------+
void FalgoUpdateExitModeEachSecond(const AlgoPerAlgoTune &tune)
{
   if(!AlgoModeSwitchingEnabled())
      AlgoClearTradeRecoveryModeFlags();
   else
      FalgoTryLatchStrongMomentumIfNeeded(tune, g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts);
   const string prev = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitMode;
   const string next = FalgoExitModeString(tune);
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitModePrev = prev;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitMode = next;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitModeChanged = (g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds > 1 && prev != next);
}

//+------------------------------------------------------------------+
void FalgoAppendTelemetryPerSecondRow(const string eventType, const string closeReason, const string closeDetail)
{
   if(!bigflipper_log_algo_trade_telemetry_per_second)
      return;
   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active)
      return;
   if(!FalgoIsTimeInPerSecondLogWindow(g_lastTimer1Time))
      return;
   AlgoPerAlgoTune telTune;
   if(!FalgoLoadTelemetryTuneForMagic(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic, telTune))
      return;
   const datetime dayStart = g_lastTimer1Time - (g_lastTimer1Time % 86400);
   const string dateStr = TimeToString(dayStart, TIME_DATE);
   const string fname = AlgoFamilyCsvFileName(dateStr, AlgoFamilyMagicNumber(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic), "trade_telemetry_per_second");
   int fh = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   FileSeek(fh, 0, SEEK_END);
   if(FileTell(fh) == 0)
   {
      const int algoNum = AlgoFamilyMagicNumber(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic);
      FileWrite(fh,
         "time", "openProfitPts", "MFE", "MAE", AlgoGatesColMaePostX(algoNum), "tradeAgeSeconds",
         "secondsGreen", "secondsRed", "greenRatio", "consecutiveGreen", "consecutiveRed",
         AlgoGatesColProfitVelocity(algoNum),
         AlgoGatesColAvgProfitVelocity(algoNum),
         "profitFromPeak",
         "exit_mode", "exit_mode_prev",
         "event_type", "close_reason", "close_detail",
         "magic", "positionTicket");
   }
   const double profitVelocity = FalgoTelemetryProfitVelocityWindowSeconds(telTune.telemetry_velocity_window_seconds);
   const double profitFromPeak = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts - g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts;
   FileWrite(fh,
      TimeToString(g_lastTimer1Time, TIME_DATE|TIME_SECONDS),
      DoubleToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts, 1),
      DoubleToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts, 1),
      DoubleToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePts, 1),
      DoubleToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePostXPts, 1),
      IntegerToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds),
      IntegerToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsGreen),
      IntegerToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsRed),
      DoubleToString(FalgoTelemetryGreenRatioFromOpen(), 4),
      IntegerToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveGreen),
      IntegerToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveRed),
      DoubleToString(profitVelocity, 3),
      DoubleToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocity, 3),
      DoubleToString(profitFromPeak, 1),
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitMode,
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitModePrev,
      eventType,
      FalgoSanitizeCsvCell(closeReason),
      FalgoSanitizeCsvCell(closeDetail),
      IntegerToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic),
      IntegerToString((long)g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].positionTicket));
   FileClose(fh);
}

//+------------------------------------------------------------------+
void FalgoTryLogTelemetryPerSecond()
{
   FalgoAppendTelemetryPerSecondRow(FALGO_TELEMETRY_EVENT_TICK, "", "");
}

//+------------------------------------------------------------------+
string FalgoVelocityParamTestHeaderLine()
{
   string hdr = "time,magic,positionTicket,openProfitPts,MFE,MAE,tradeAgeSeconds,profitFromPeak";
   for(int pi = 0; pi < FALGO_VELOCITY_PARAM_TEST_COUNT; pi++)
   {
      const string w = IntegerToString(g_velocityParameterTestedSec[pi]);
      hdr += ",profitVelocity_" + w + "_x10";
      hdr += ",avg_profitVelocity_" + w + "_x10";
   }
   return hdr;
}

//+------------------------------------------------------------------+
string FalgoVelocityParamTestDataLine()
{
   const double profitFromPeak = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts - g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts;
   string row = StringFormat("%s,%s,%s,%.1f,%.1f,%.1f,%d,%.1f",
      TimeToString(g_lastTimer1Time, TIME_DATE|TIME_SECONDS),
      IntegerToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic),
      IntegerToString((long)g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].positionTicket),
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts,
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts,
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePts,
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds,
      profitFromPeak);
   for(int pi = 0; pi < FALGO_VELOCITY_PARAM_TEST_COUNT; pi++)
   {
      const int windowSec = g_velocityParameterTestedSec[pi];
      const double profitVel = FalgoTelemetryProfitVelocityWindowSeconds(windowSec);
      const double avgVel = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocityParamTest[pi];
      row += StringFormat(",%.3f,%.3f", profitVel, avgVel);
   }
   return row;
}

//+------------------------------------------------------------------+
void FalgoUpdateVelocityParamTestAverages()
{
   if(!bigflipper_log_algo_velocity_parameter_testing_per_second || !g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active)
      return;
   const int sampleCount = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgVelocitySampleCount;
   if(sampleCount <= 0)
      return;
   for(int pi = 0; pi < FALGO_VELOCITY_PARAM_TEST_COUNT; pi++)
   {
      const double velW = FalgoTelemetryProfitVelocityWindowSeconds(g_velocityParameterTestedSec[pi]);
      if(sampleCount == 1)
         g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocityParamTest[pi] = velW;
      else
      {
         g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocityParamTest[pi] =
            ((g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocityParamTest[pi] * (sampleCount - 1)) + velW)
            / (double)sampleCount;
      }
   }
}

//+------------------------------------------------------------------+
void FalgoTryLogVelocityParameterTesting()
{
   if(!bigflipper_log_algo_velocity_parameter_testing_per_second || !g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active)
      return;
   if(!FalgoIsTimeInPerSecondLogWindow(g_lastTimer1Time))
      return;
   const datetime dayStart = g_lastTimer1Time - (g_lastTimer1Time % 86400);
   const string dateStr = TimeToString(dayStart, TIME_DATE);
   const string fname = AlgoFamilyCsvFileName(dateStr, AlgoFamilyMagicNumber(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic),
      "velocity_parameter_testing");
   int fh = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      fh = FileOpen(fname, FILE_WRITE | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   FileSeek(fh, 0, SEEK_END);
   if(FileTell(fh) == 0)
      FileWriteString(fh, FalgoVelocityParamTestHeaderLine() + "\r\n");
   FileWriteString(fh, FalgoVelocityParamTestDataLine() + "\r\n");
   FileClose(fh);
}

//+------------------------------------------------------------------+
bool FalgoLoadTelemetryTuneForMagic(const long magic, AlgoPerAlgoTune &outTune)
{
   ZeroMemory(outTune);
   if(IsBreakdownFamilyCompositeMagic(magic))
      return true;
   return AlgoLoadPerAlgoTuneForMagic(magic, outTune);
}

//+------------------------------------------------------------------+
void FalgoOpenTelemetryUpdateMaePostX(const AlgoPerAlgoTune &tune, const double profitPts)
{
   const int age = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds;
   const int startSec = tune.start_mae_care_after_x_seconds;
   if(startSec <= 0 || age < startSec)
   {
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePostXPts = 0.0;
      return;
   }
   if(age == startSec)
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePostXPts = profitPts;
   else if(profitPts < g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePostXPts)
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePostXPts = profitPts;
}

//+------------------------------------------------------------------+
void FalgoTelemetryUpdateOneSecondFromSelectedPosition()
{
   AlgoPerAlgoTune telTune;
   if(!FalgoLoadTelemetryTuneForMagic(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic, telTune))
      return;
   const double profitPts = FalgoOpenPositionProfitPoints();
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds++;
   if(profitPts > 0.0)
   {
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsGreen++;
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveGreen++;
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveRed = 0;
   }
   else if(profitPts < 0.0)
   {
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsRed++;
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveRed++;
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveGreen = 0;
   }
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts = profitPts;
   if(profitPts > g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts)
   {
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts = profitPts;
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfeCandle1Based = FalgoTradeMinuteCandle1BasedFromStart(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeStartTime, g_lastTimer1Time);
   }
   if(profitPts < g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePts)
   {
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePts = profitPts;
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maeCandle1Based = FalgoTradeMinuteCandle1BasedFromStart(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeStartTime, g_lastTimer1Time);
   }
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds <= FalgoTradeResultMaeFirstWindowSeconds() &&
      profitPts < g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maeFirstWindowPts)
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maeFirstWindowPts = profitPts;
   FalgoOpenTelemetryUpdateMaePostX(telTune, profitPts);
   FalgoTryLatchTradeRecoveryModes(telTune);
   if(AlgoNeutralTradeModeActive(telTune) &&
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].timeToReachNeutralTpSeconds < 0 &&
      profitPts >= PointSized(telTune.neutral_trade_TP))
   {
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].timeToReachNeutralTpSeconds = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds;
   }
   FalgoTelemetryPushProfitSample(g_lastTimer1Time, profitPts);
   const double velAvgWindow = FalgoTelemetryProfitVelocityWindowSeconds(telTune.telemetry_avg_velocity_window_seconds);
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgVelocitySampleCount++;
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgVelocitySampleCount == 1)
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocity = velAvgWindow;
   else
   {
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocity =
         ((g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocity * (g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgVelocitySampleCount - 1)) + velAvgWindow)
         / (double)g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgVelocitySampleCount;
   }
   FalgoStrongMomentumUpdatePeakAvgIfAiming();
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].lastBarIdx = FalgoBarIdxForDayTime(g_lastTimer1Time);
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].lastBarIdx >= 0)
      FalgoTelemetrySnapOpenStateToBar(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].lastBarIdx);
   FalgoUpdateExitModeEachSecond(telTune);
   FalgoUpdateVelocityParamTestAverages();
   FalgoTryLogTelemetryPerSecond();
   FalgoTryLogVelocityParameterTesting();
}

//+------------------------------------------------------------------+
void FalgoUpdateOpenTradeTelemetryEachSecond()
{
   if(g_lastTimer1Time == 0)
      return;
   const datetime dayStart = g_lastTimer1Time - (g_lastTimer1Time % 86400);
   FalgoResetTelemetryIfNewDay(dayStart);
   if(g_falgoTelemetryLastUpdateTime == g_lastTimer1Time)
      return;
   g_falgoTelemetryLastUpdateTime = g_lastTimer1Time;

   for(int si = 0; si < FALGO_OPEN_TELEMETRY_MAX; si++)
   {
      if(!g_falgoOpenTelemetrySlots[si].active)
         continue;
      if(FalgoPositionTicketStillOpen(g_falgoOpenTelemetrySlots[si].positionTicket))
         continue;
      g_falgoOpenTelemetryCtx = si;
      FalgoOnFalgoTradeClosedThisBar();
      FalgoTelemetryPushClosedSummaryFromOpen();
      FalgoTelemetryClearOpenState();
   }

   for(int positionIdx = PositionsTotal() - 1; positionIdx >= 0; positionIdx--)
   {
      if(!ExtPositionInfo.SelectByIndex(positionIdx))
         continue;
      if(ExtPositionInfo.Symbol() != _Symbol)
         continue;
      if(!IsAnyAlgoFamilyCompositeMagic(ExtPositionInfo.Magic()))
         continue;

      const ulong ticket = ExtPositionInfo.Ticket();
      const long magic = ExtPositionInfo.Magic();
      const datetime startTime = ExtPositionInfo.Time();
      int slotIdx = FalgoOpenTelemetryFindSlotByTicket(ticket);
      if(slotIdx < 0)
      {
         slotIdx = FalgoOpenTelemetryAllocSlot();
         if(slotIdx < 0)
            continue;
         g_falgoOpenTelemetryCtx = slotIdx;
         FalgoTelemetryInitFromSelectedPosition();
         continue;
      }

      g_falgoOpenTelemetryCtx = slotIdx;
      if(g_falgoOpenTelemetrySlots[slotIdx].magic != magic ||
         g_falgoOpenTelemetrySlots[slotIdx].tradeStartTime != startTime)
      {
         FalgoOnFalgoTradeClosedThisBar();
         FalgoTelemetryPushClosedSummaryFromOpen();
         FalgoTelemetryInitFromSelectedPosition();
         continue;
      }

      FalgoTelemetryUpdateOneSecondFromSelectedPosition();
   }
   g_falgoOpenTelemetryCtx = -1;
}

//+------------------------------------------------------------------+
//| Gates CSV column names for recent bounce/ceiling windows (max window across wired algos). |
//+------------------------------------------------------------------+
string FalgoGatesColRecentBounceCount()
{
   const int maxMin = AlgoFamilyRecentBounceLookbackMinutes();
   if(maxMin <= 0)
      return "recentBounceCount0";
   return StringFormat("recentBounceCount%d", maxMin);
}

//+------------------------------------------------------------------+
string FalgoGatesColRecentCeilingCount()
{
   const int maxMin = AlgoFamilyRecentCeilingLookbackMinutes();
   if(maxMin <= 0)
      return "recentCeilingCount0";
   return StringFormat("recentCeilingCount%d", maxMin);
}

//+------------------------------------------------------------------+
//| Magic digits 5-6: level tag slot (00=RTHO; 01=PDC; weekly pivot=20; daily pivot=60). |
//+------------------------------------------------------------------+
bool FalgoMagicLevelSlotIsValid(const int levelSlot)
{
   if(levelSlot == FALGO_MAGIC_LEVEL_SLOT_RTHO)
      return true;
   if(levelSlot == FALGO_MAGIC_LEVEL_SLOT_PDRTHCLOSE)
      return true;
   if(levelSlot == FALGO_MAGIC_LEVEL_SLOT_BREAKDOWN)
      return true;
   if(levelSlot >= FALGO_MAGIC_LEVEL_SLOT_WEEKLY_MIN && levelSlot <= FALGO_MAGIC_LEVEL_SLOT_WEEKLY_MAX)
      return true;
   if(levelSlot >= FALGO_MAGIC_LEVEL_SLOT_DAILY_MIN && levelSlot <= FALGO_MAGIC_LEVEL_SLOT_DAILY_MAX)
      return true;
   return false;
}

//+------------------------------------------------------------------+
int FalgoReadLadderStepAfterKeywordInTag(const string &tLower, const string keyword)
{
   const int pos = StringFind(tLower, keyword);
   if(pos < 0)
      return 0;
   int idx = pos + (int)StringLen(keyword);
   int step = 0;
   while(idx < StringLen(tLower))
   {
      const ushort ch = StringGetCharacter(tLower, idx);
      if(ch >= '0' && ch <= '9')
      {
         step = step * 10 + (ch - '0');
         idx++;
      }
      else
         break;
   }
   return (step > 0) ? step : 1;
}

//+------------------------------------------------------------------+
int FalgoMagicLevelSlotFromLevelIdx(const int levelIdx)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount)
      FatalError(StringFormat("FalgoMagicLevelSlotFromLevelIdx: invalid levelIdx=%d (g_levelsTodayCount=%d)", levelIdx, g_levelsTodayCount));
   const string cats = g_levelsExpanded[levelIdx].categories;
   if(LevelIsTodayRthOpenTertiary(cats))
      return FALGO_MAGIC_LEVEL_SLOT_RTHO;
   if(LevelIsPDrthCloseTertiary(cats))
      return FALGO_MAGIC_LEVEL_SLOT_PDRTHCLOSE;

   string tLower = g_levelsExpanded[levelIdx].tag;
   StringToLower(tLower);

   bool weeklyBand;
   if(StringFind(tLower, "weekly") >= 0)
      weeklyBand = true;
   else if(StringFind(tLower, "daily") >= 0)
      weeklyBand = false;
   else if(LevelIsWeeklyKind(cats))
      weeklyBand = true;
   else if(LevelIsDailyKind(cats) && !LevelIsWeekly(cats))
      weeklyBand = false;
   else
      FatalError(StringFormat("FalgoMagicLevelSlotFromLevelIdx: levelIdx=%d tag \"%s\" categories \"%s\" — not weekly/daily/tertiary",
         levelIdx, g_levelsExpanded[levelIdx].tag, cats));

   const int center = weeklyBand ? FALGO_MAGIC_LEVEL_SLOT_WEEKLY_PIVOT : FALGO_MAGIC_LEVEL_SLOT_DAILY_PIVOT;
   const int bandMin = weeklyBand ? FALGO_MAGIC_LEVEL_SLOT_WEEKLY_MIN : FALGO_MAGIC_LEVEL_SLOT_DAILY_MIN;
   const int bandMax = weeklyBand ? FALGO_MAGIC_LEVEL_SLOT_WEEKLY_MAX : FALGO_MAGIC_LEVEL_SLOT_DAILY_MAX;

   int slot = center;
   if(StringFind(tLower, "pivot") >= 0)
      slot = center;
   else if(StringFind(tLower, "down") >= 0)
      slot = center - FalgoReadLadderStepAfterKeywordInTag(tLower, "down");
   else if(StringFind(tLower, "up") >= 0)
      slot = center + FalgoReadLadderStepAfterKeywordInTag(tLower, "up");
   else
      FatalError(StringFormat("FalgoMagicLevelSlotFromLevelIdx: levelIdx=%d tag \"%s\" — no pivot/up/down ladder token",
         levelIdx, g_levelsExpanded[levelIdx].tag));

   if(slot < bandMin || slot > bandMax)
      FatalError(StringFormat("FalgoMagicLevelSlotFromLevelIdx: levelIdx=%d tag \"%s\" → slot %d outside %d..%d",
         levelIdx, g_levelsExpanded[levelIdx].tag, slot, bandMin, bandMax));
   return slot;
}

//+------------------------------------------------------------------+
int FalgoExpandedLevelIdxForMagicLevelSlot(const int levelSlot)
{
   if(!FalgoMagicLevelSlotIsValid(levelSlot))
      return -1;

   int matchIdx = -1;
   int matchCount = 0;
   for(int levelIdx = 0; levelIdx < g_levelsTodayCount; levelIdx++)
   {
      if(FalgoMagicLevelSlotFromLevelIdx(levelIdx) != levelSlot)
         continue;
      matchCount++;
      matchIdx = levelIdx;
   }
   if(matchCount == 0)
      return -1;
   if(matchCount == 1)
      return matchIdx;
   FatalError(StringFormat("FalgoExpandedLevelIdxForMagicLevelSlot: levelSlot %02d matches %d levels (expected 1)",
      levelSlot, matchCount));
   return -1;
}

//+------------------------------------------------------------------+
int FalgoResolveExpandedLevelIdxFromMagicKey(const FalgoMagicKey &fk)
{
   if(FalgoMagicLevelSlotIsBreakdownMidpoint(fk.levelSlot))
      return -1;
   if(!FalgoMagicLevelSlotIsValid(fk.levelSlot))
      FatalError(StringFormat("FalgoResolveExpandedLevelIdxFromMagicKey: invalid levelSlot %d (00=RTHO; 01=PDC; 10..35 weekly; 50..80 daily)",
         fk.levelSlot));
   const int expandedIdx = FalgoExpandedLevelIdxForMagicLevelSlot(fk.levelSlot);
   if(expandedIdx < 0)
      FatalError(StringFormat("FalgoResolveExpandedLevelIdxFromMagicKey: no g_levelsExpanded row for levelSlot %02d (g_levelsTodayCount=%d)",
         fk.levelSlot, g_levelsTodayCount));
   return expandedIdx;
}

//+------------------------------------------------------------------+
double FalgoLevelPriceForMagicKey(const FalgoMagicKey &fk)
{
   if(FalgoMagicLevelSlotIsBreakdownMidpoint(fk.levelSlot))
      return 0.0;
   const int levelIdx = FalgoResolveExpandedLevelIdxFromMagicKey(fk);
   return g_levelsExpanded[levelIdx].levelPrice;
}

//+------------------------------------------------------------------+
//| tpWhole/slWhole from magic; if secretTPSL on, scale by secretTPSL_percent (babysit-effective points). |
//+------------------------------------------------------------------+
void FalgoEffectiveTpSlPointsFromMagicKey(const FalgoMagicKey &k, double &outTpPoints, double &outSlPoints)
{
   outTpPoints = (double)k.tpWhole;
   outSlPoints = (double)k.slWhole;
   if(g_algoShared.secretTPSL && g_algoShared.secretTPSL_percent > 0)
   {
      const double frac = (double)g_algoShared.secretTPSL_percent / 100.0;
      outTpPoints *= frac;
      outSlPoints *= frac;
   }
}

//+------------------------------------------------------------------+
void FalgoEnrichTradeResultLevelTpSl(TradeResult &tr)
{
   if(!IsAnyAlgoFamilyCompositeMagic(tr.magic))
      return;
   FalgoMagicKey fk = ParseFalgoMagic(tr.magic);
   if(!FalgoMagicLevelSlotIsValid(fk.levelSlot))
      FatalError(StringFormat("FalgoEnrichTradeResultLevelTpSl: magic %s invalid levelSlot %d",
         IntegerToString(tr.magic), fk.levelSlot));
   const double levelPrice = FalgoLevelPriceForMagicKey(fk);
   double tpPts = 0.0, slPts = 0.0;
   FalgoEffectiveTpSlPointsFromMagicKey(fk, tpPts, slPts);
   if(FalgoMagicLevelSlotIsBreakdownMidpoint(fk.levelSlot))
   {
      const double planned = BreakdownPlannedPriceForTradeResult(tr);
      if(planned > 0.0)
         tr.level = DoubleToString(planned, _Digits);
      else if(StringLen(tr.level) == 0 && tr.priceStart > 0.0)
         tr.level = DoubleToString(tr.priceStart, _Digits);
   }
   else
      tr.level = DoubleToString(levelPrice, _Digits);
   tr.tp = DoubleToString(tpPts, 1);
   tr.sl = DoubleToString(slPts, 1);
}

//+------------------------------------------------------------------+
//| After UpdateTradeResultsForDay: fill level/tp/sl for Falgo rows from magic (not order comment). |
//+------------------------------------------------------------------+
void FalgoEnrichAllTradeResultsLevelTpSl()
{
   const bool profOn = BacktestProfileEnabled();
   ulong profT0 = 0;
   if(profOn)
      profT0 = GetMicrosecondCount();
   for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
      FalgoEnrichTradeResultLevelTpSl(g_tradeResults[trIdx]);
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_TRADE_RESULTS_ENRICH, profT0);
}

//+------------------------------------------------------------------+
double FalgoProfileOffsetPointsForDirection(const int direction)
{
   double base = 0.0;
   for(int i = 0; i < g_algoCount; i++)
   {
      if(direction == FALGO_DIRECTION_LONG_LIMIT && !g_algos[i].trades_short)
         base = g_algos[i].levelOffset;
      if(direction == FALGO_DIRECTION_SHORT_LIMIT && g_algos[i].trades_short)
         base = g_algos[i].levelOffset;
   }
   return base + AlgoExtraOffsetForDirection(direction);
}

//+------------------------------------------------------------------+
double FalgoProfileOffsetPointsForMagic(const long magic)
{
   FalgoMagicKey fk = ParseFalgoMagic(magic);
   const int algoNumber = AlgoFamilyMagicNumber(magic);
   double offsetPoints = 0.0, proximityLimit = 0.0;
   int expirationMin = 0;
   if(AlgoPlacementParamsForAlgo(algoNumber, fk.direction, offsetPoints, proximityLimit, expirationMin))
      return offsetPoints;
   return FalgoProfileOffsetPointsForDirection(fk.direction);
}

//+------------------------------------------------------------------+
double FalgoProfileOffsetPointsFromPriceDelta(const double priceDelta)
{
   const double step = 10.0 * Instrument_PointStepSize();
   if(step <= 0.0)
      return priceDelta;
   return priceDelta / step;
}

//+------------------------------------------------------------------+
string FalgoOffsetPointsStrForMagic(const long magic)
{
   FalgoMagicKey fk = ParseFalgoMagic(magic);
   const double off = FalgoProfileOffsetPointsForMagic(magic);
   if(fk.direction != FALGO_DIRECTION_LONG_LIMIT && fk.direction != FALGO_DIRECTION_SHORT_LIMIT)
      return "";
   return DoubleToString(off, 1);
}

//+------------------------------------------------------------------+
string FalgoOffsetPriceUnitsStrForTrade(const TradeResult &tr)
{
   FalgoMagicKey fk = ParseFalgoMagic(tr.magic);
   if(fk.direction != FALGO_DIRECTION_LONG_LIMIT && fk.direction != FALGO_DIRECTION_SHORT_LIMIT)
      return "";
   const double levelPx = StringToDouble(tr.level);
   if(levelPx > 0.0 && tr.priceStart > 0.0)
   {
      if(fk.direction == FALGO_DIRECTION_LONG_LIMIT)
         return DoubleToString(FalgoProfileOffsetPointsFromPriceDelta(tr.priceStart - levelPx), 1);
      return DoubleToString(FalgoProfileOffsetPointsFromPriceDelta(levelPx - tr.priceStart), 1);
   }
   return FalgoOffsetPointsStrForMagic(tr.magic);
}

//+------------------------------------------------------------------+
string FalgoLevelTagUneditedForTradeResult(const TradeResult &tr)
{
   if(!IsAnyAlgoFamilyCompositeMagic(tr.magic))
   {
      const int levelIdx = FindExpandedLevelIndexByPrice(StringToDouble(tr.level));
      if(levelIdx < 0)
         return "";
      return g_levelsExpanded[levelIdx].tag;
   }
   const FalgoMagicKey fk = ParseFalgoMagic(tr.magic);
   const int levelIdx = FalgoResolveExpandedLevelIdxFromMagicKey(fk);
   if(levelIdx < 0)
      return "";
   return g_levelsExpanded[levelIdx].tag;
}

//+------------------------------------------------------------------+
void FalgoPlanAndLevelTradeNumsFromMagic(const long magic, int &outPlanTradeNumToday, int &outLevelTradeNumToday)
{
   const FalgoMagicKey fk = ParseFalgoMagic(magic);
   outPlanTradeNumToday = fk.planTradeNum;
   outLevelTradeNumToday = fk.levelTradeNum;
}

//+------------------------------------------------------------------+
string FalgoLevelSlotStrForMagic(const long magic)
{
   if(!IsAnyAlgoFamilyCompositeMagic(magic))
      return "";
   const FalgoMagicKey fk = ParseFalgoMagic(magic);
   return StringFormat("%02d", fk.levelSlot);
}

//+------------------------------------------------------------------+
bool FalgoMagicKeyIsShortDirection(const FalgoMagicKey &k)
{
   return (k.direction == FALGO_DIRECTION_SHORT_LIMIT || k.direction == FALGO_DIRECTION_SHORT_ALT);
}

//+------------------------------------------------------------------+
bool FalgoClosestLevelMagicSlotAtBarForAlgo(const int algoNumber, const int barIdx, int &outLevelSlot)
{
   outLevelSlot = 0;
   const int levelIdx = FalgoClosestExpandedLevelIdxAtBarForAlgo(algoNumber, barIdx);
   if(levelIdx < 0)
      return false;
   outLevelSlot = FalgoMagicLevelSlotFromLevelIdx(levelIdx);
   return true;
}

//+------------------------------------------------------------------+
int FalgoTradeCountTodayAtLevelSlotForThisAlgo(const int algoNumber, const int levelSlot)
{
   if(!FalgoMagicLevelSlotIsValid(levelSlot))
      return 0;
   const int slotIdx = AlgoSlotIndexByAlgoId(algoNumber);
   const bool wantShort = (slotIdx >= 0 && g_algos[slotIdx].trades_short);
   const datetime dayStart = FalgoTradingDayStart();
   int count = 0;
   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      if(!IsAlgoCompositeMagic(g_tradeResults[i].magic, algoNumber))
         continue;
      if(!FalgoTradeStartedOnTradingDay(g_tradeResults[i], dayStart))
         continue;
      const FalgoMagicKey fk = ParseFalgoMagic(g_tradeResults[i].magic);
      if(fk.levelSlot != levelSlot || FalgoMagicKeyIsShortDirection(fk) != wantShort)
         continue;
      count++;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ExtOrderInfo.SelectByIndex(i))
         continue;
      if(ExtOrderInfo.Symbol() != _Symbol)
         continue;
      const long magic = ExtOrderInfo.Magic();
      if(!IsAlgoCompositeMagic(magic, algoNumber))
         continue;
      const FalgoMagicKey fk = ParseFalgoMagic(magic);
      if(fk.levelSlot != levelSlot || FalgoMagicKeyIsShortDirection(fk) != wantShort)
         continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
bool FalgoTelemetryBarSnapMatchesAlgo(const int barIdx, const int algoSlot1)
{
   const int ri = FalgoRegistrySlotForAlgoNumber(algoSlot1);
   if(ri < 0 || barIdx < 0 || barIdx >= g_barsInDay)
      return false;
   if(!g_falgoTelemetryAtBar[barIdx][ri].valid)
      return false;
   return IsAlgoCompositeMagic(g_falgoTelemetryAtBar[barIdx][ri].magic, algoSlot1);
}

//+------------------------------------------------------------------+
//| Trade closed: telemetry snap + per-algo close-bar gate only (no OrderDelete). |
//+------------------------------------------------------------------+
void FalgoOnFalgoTradeClosedThisBar()
{
   if(g_falgoOpenTelemetryCtx < 0 || g_falgoOpenTelemetryCtx >= FALGO_OPEN_TELEMETRY_MAX)
      return;
   const int algoNumber = AlgoFamilyMagicNumber(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic);
   const int ri = FalgoRegistrySlotForAlgoNumber(algoNumber);
   FalgoTelemetrySnapOpenStateToLastBar(true);
   if(ri >= 0)
   {
      int closedBarIdx = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].lastBarIdx;
      if(closedBarIdx < 0)
         closedBarIdx = FalgoBarIdxForDayTime(g_lastTimer1Time);
      g_falgoLastTradeClosedBarIdx[ri] = closedBarIdx;
   }
}

//+------------------------------------------------------------------+
int FalgoBarIdxForDayTime(const datetime t)
{
   if(g_barsInDay <= 0)
      return -1;
   const datetime barOpen = t - (t % 60);
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      if(g_m1Rates[barIdx].time == barOpen)
         return barIdx;
   }
   return -1;
}

//+------------------------------------------------------------------+
int FalgoSnapBarIdxAsOfTime(const datetime t)
{
   if(g_barsInDay <= 0)
      return -1;
   int best = -1;
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      if(g_m1Rates[barIdx].time + 60 <= t)
         best = barIdx;
      else
         break;
   }
   return best;
}

//+------------------------------------------------------------------+
void PullingHistoryAlgoFamilyOhlcAsOfTime(const datetime t, double &o, double &h, double &l, double &c)
{
   o = 0.0;
   h = 0.0;
   l = 0.0;
   c = 0.0;
   const int formingIdx = FalgoBarIdxForDayTime(t);
   if(formingIdx >= 0 && g_m1Rates[formingIdx].time == t - (t % 60))
   {
      o = g_m1Rates[formingIdx].open;
      h = MathMax(g_m1Rates[formingIdx].high, g_liveBid);
      l = MathMin(g_m1Rates[formingIdx].low, g_liveBid);
      c = g_liveBid;
      return;
   }
   const int snapIdx = FalgoSnapBarIdxAsOfTime(t);
   if(snapIdx >= 0)
   {
      o = g_m1Rates[snapIdx].open;
      h = g_m1Rates[snapIdx].high;
      l = g_m1Rates[snapIdx].low;
      c = g_m1Rates[snapIdx].close;
   }
}

//+------------------------------------------------------------------+
void PullingHistoryAlgoFamilyWriteCsvHeader(const int fh)
{
   const string colClosestProx = FalgoLogCol_contactAndProximityCount("ClosestLevel_");
   FileWrite(fh, "time", "O", "H", "L", "C",
            "ClosestLevelToCClose",
            "closestPriceProximity",
            "sessionRangeMidpoint",
            "currentCandle_AvgOf_OHLCnumbers",
            "cleanOHLC_streak_startTime", "cleanOHLC_streak_count", "cleanOHLC_streak_avgOfOHLC",
            "ClosestLevel_anchorAbove_within_cleanOHLC_streak", "ClosestLevel_anchorAbove_time",
            "ClosestLevel_anchorBelow_within_cleanOHLC_streak", "ClosestLevel_anchorBelow_time",
            "ClosestLevel_BounceCount_today",
            StringFormat("recentBounceCount%d", AlgoFamilyRecentBounceLookbackMinutes()),
            "ClosestLevel_CeilingCount_today",
            "ClosestLevel_CeilingProximityCandles_today",
            StringFormat("recentCeilingCount%d", AlgoFamilyRecentCeilingLookbackMinutes()),
            "ClosestLevel_physicalContactCount_today",
            colClosestProx,
            "accOpenTradeNowBool", "accOpenTradeTime", "accLastClosedTradeTime",
            "dayWinRate", "dayTradesCount", "dayPointsSum", "dayProfitSum", "dayProfitFactor",
            "gap_fill_pc");
}

//+------------------------------------------------------------------+
void PullingHistoryAlgoFamilyWriteCsvRowFromSnap(const int fh, const datetime rowTime, const PullingHistoryAlgoFamilyBarSnap &snap,
   const int snapBarIdx, const double o, const double h, const double l, const double c, const int timeFormat)
{
   if(snapBarIdx < 0 || snapBarIdx >= g_barsInDay)
      return;
   string streakStartStr = (snap.cleanOHLC_streak_count > 0) ?
      TimeToString(snap.cleanOHLC_streak_startTime, TIME_DATE|TIME_MINUTES) : "";
   string anchorAboveTimeStr = (snap.closestWeeklyLevel_anchorAbove_time > 0) ?
      TimeToString(snap.closestWeeklyLevel_anchorAbove_time, TIME_DATE|TIME_MINUTES) : "";
   string anchorBelowTimeStr = (snap.closestWeeklyLevel_anchorBelow_time > 0) ?
      TimeToString(snap.closestWeeklyLevel_anchorBelow_time, TIME_DATE|TIME_MINUTES) : "";
   string accOpenTimeStr = (snap.accOpenTradeTime > 0) ?
      TimeToString(snap.accOpenTradeTime, TIME_DATE|TIME_MINUTES) : "";
   string accLastClosedStr = (snap.accLastClosedTradeTime > 0) ?
      TimeToString(snap.accLastClosedTradeTime, TIME_DATE|TIME_MINUTES) : "";
   string gapFillPcStr = "unknown";
   if(g_m1DayStart != 0)
   {
      const string dateStrGap = TimeToString(g_m1DayStart, TIME_DATE);
      double gapFillVal = 0.0;
      if(GetGapFillSoFarAtBar(snapBarIdx, g_m1DayStart, dateStrGap, gapFillVal))
         gapFillPcStr = DoubleToString(gapFillVal, 2);
   }
   FileWrite(fh, TimeToString(rowTime, timeFormat),
            DoubleToString(o, _Digits), DoubleToString(h, _Digits), DoubleToString(l, _Digits), DoubleToString(c, _Digits),
            DoubleToString(snap.closestWeeklyLevelToCClose, _Digits),
            DoubleToString(snap.closestPriceProximity, _Digits),
            (g_sessionRangeMidpointAtBar[snapBarIdx].hasValue ? DoubleToString(g_sessionRangeMidpointAtBar[snapBarIdx].value, 2) : "unknown"),
            DoubleToString(snap.currentCandle_AvgOf_OHLCnumbers, _Digits),
            streakStartStr, IntegerToString(snap.cleanOHLC_streak_count), DoubleToString(snap.cleanOHLC_streak_avgOfOHLC, _Digits),
            DoubleToString(snap.closestWeeklyLevel_anchorAbove_within_cleanOHLC_streak, _Digits), anchorAboveTimeStr,
            DoubleToString(snap.closestWeeklyLevel_anchorBelow_within_cleanOHLC_streak, _Digits), anchorBelowTimeStr,
            IntegerToString(snap.closestWeeklyLevel_BounceCount_today),
            IntegerToString(snap.closestWeeklyLevel_BounceCount_recent),
            IntegerToString(snap.closestWeeklyLevel_CeilingCount_today),
            IntegerToString(snap.closestWeeklyLevel_CeilingProximityCandles_today),
            IntegerToString(snap.closestWeeklyLevel_CeilingCount_recent),
            IntegerToString(snap.closestWeeklyLevel_physicalContactCount_today),
            IntegerToString(snap.closestWeeklyLevel_contactAndProximityCount_today),
            (snap.accOpenTradeNowBool ? "true" : "false"), accOpenTimeStr, accLastClosedStr,
            DoubleToString(snap.dayWinRate * 100.0, 0), IntegerToString(snap.dayTradesCount),
            DoubleToString(snap.dayPointsSum, _Digits), DoubleToString(snap.dayProfitSum, 2),
            FormatDayProfitFactorForCsv(snap.dayProfitFactor),
            gapFillPcStr);
}

//+------------------------------------------------------------------+
void PullingHistoryAlgoFamilyWriteCsvRow(const int fh, const datetime rowTime, const int snapBarIdx,
   const double o, const double h, const double l, const double c, const int timeFormat)
{
   PullingHistoryAlgoFamilyWriteCsvRowFromSnap(fh, rowTime, g_pullingHistoryAlgoFamilyWeeklyAtBar[snapBarIdx],
      snapBarIdx, o, h, l, c, timeFormat);
}

//+------------------------------------------------------------------+
void PullingHistoryAlgoFamilyWriteEodCsv(const string dateStr, const string scopeSuffix)
{
   const string logName = dateStr + "_pullinghistory_a_algofamily_" + scopeSuffix + ".csv";
   if(FileIsExist(logName))
      return;
   int fh = FileOpen(logName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      FatalError("PullingHistoryAlgoFamilyWriteEodCsv: could not open " + logName);
   PullingHistoryAlgoFamilyWriteCsvHeader(fh);
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      PullingHistoryAlgoFamilyBarSnap snap;
      if(scopeSuffix == "daily")
         snap = g_pullingHistoryAlgoFamilyDailyAtBar[barIdx];
      else
         snap = g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx];
      PullingHistoryAlgoFamilyWriteCsvRowFromSnap(fh, g_m1Rates[barIdx].time, snap, barIdx,
         g_m1Rates[barIdx].open, g_m1Rates[barIdx].high, g_m1Rates[barIdx].low, g_m1Rates[barIdx].close,
         TIME_DATE|TIME_MINUTES);
   }
   FileClose(fh);
}

//+------------------------------------------------------------------+
void PullingHistoryPsLogCloseHandles()
{
   if(g_pullingHistoryPsWeeklyFh != INVALID_HANDLE)
   {
      FileClose(g_pullingHistoryPsWeeklyFh);
      g_pullingHistoryPsWeeklyFh = INVALID_HANDLE;
   }
   if(g_pullingHistoryPsDailyFh != INVALID_HANDLE)
   {
      FileClose(g_pullingHistoryPsDailyFh);
      g_pullingHistoryPsDailyFh = INVALID_HANDLE;
   }
   g_pullingHistoryPsFileDayStart = 0;
}

//+------------------------------------------------------------------+
int PullingHistoryPsAcquireHandle(const string dateStr, const string scopeSuffix)
{
   const datetime dayStart = StringToTime(dateStr);
   if(dayStart != g_pullingHistoryPsFileDayStart)
   {
      PullingHistoryPsLogCloseHandles();
      g_pullingHistoryPsFileDayStart = dayStart;
   }

   int fhRef = (scopeSuffix == "daily") ? g_pullingHistoryPsDailyFh : g_pullingHistoryPsWeeklyFh;
   if(fhRef != INVALID_HANDLE)
   {
      FileSeek(fhRef, 0, SEEK_END);
      return fhRef;
   }

   const string fname = dateStr + "_pullinghistory_b_algofamily_per_second_" + scopeSuffix + ".csv";
   fhRef = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fhRef == INVALID_HANDLE)
      fhRef = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fhRef == INVALID_HANDLE)
      return INVALID_HANDLE;

   FileSeek(fhRef, 0, SEEK_END);
   if(FileTell(fhRef) == 0)
      PullingHistoryAlgoFamilyWriteCsvHeader(fhRef);
   FileSeek(fhRef, 0, SEEK_END);
   if(scopeSuffix == "daily")
      g_pullingHistoryPsDailyFh = fhRef;
   else
      g_pullingHistoryPsWeeklyFh = fhRef;
   return fhRef;
}

//+------------------------------------------------------------------+
void PullingHistoryAlgoFamilyAppendPerSecondRow(const string dateStr, const string scopeSuffix,
   const datetime rowTime, const int snapBarIdx, const double o, const double h, const double l, const double c)
{
   const int fh = PullingHistoryPsAcquireHandle(dateStr, scopeSuffix);
   if(fh == INVALID_HANDLE)
      return;
   PullingHistoryAlgoFamilyBarSnap snap;
   if(scopeSuffix == "daily")
      snap = g_pullingHistoryAlgoFamilyDailyAtBar[snapBarIdx];
   else
      snap = g_pullingHistoryAlgoFamilyWeeklyAtBar[snapBarIdx];
   PullingHistoryAlgoFamilyWriteCsvRowFromSnap(fh, rowTime, snap, snapBarIdx, o, h, l, c, TIME_DATE|TIME_SECONDS);
}

//+------------------------------------------------------------------+
bool FalgoIsTimeInPerSecondLogWindow(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   const int minuteOfDay = dt.hour * 60 + dt.min;
   const int startMin = per_second_log_start_hour * 60 + per_second_log_start_minute;
   const int endMin = per_second_log_end_hour * 60 + per_second_log_end_minute;
   if(startMin <= endMin)
      return (minuteOfDay >= startMin && minuteOfDay <= endMin);
   return (minuteOfDay >= startMin || minuteOfDay <= endMin);
}

//+------------------------------------------------------------------+
double GetTradeLotForFalgo()
{
   return g_global_base_trade_size * ((double)g_algoShared.tradeSizePct / 100.0);
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool FalgoBabysitPositionMatchesOpenTelemetry()
{
   const int slotIdx = FalgoOpenTelemetryFindSlotByTicket(ExtPositionInfo.Ticket());
   if(slotIdx < 0)
      return false;
   if(g_falgoOpenTelemetrySlots[slotIdx].magic != ExtPositionInfo.Magic())
      return false;
   g_falgoOpenTelemetryCtx = slotIdx;
   return true;
}

//+------------------------------------------------------------------+
void FalgoTryLogTelemetryCloseDecision(const string closeReason, const string closeDetail)
{
   if(closeReason == "")
      return;
   if(!FalgoBabysitPositionMatchesOpenTelemetry())
      return;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts = FalgoOpenPositionProfitPoints();
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].closeDecisionReason = closeReason;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].closeDecisionDetail = closeDetail;
   FalgoAppendTelemetryPerSecondRow(FALGO_TELEMETRY_EVENT_CLOSE, closeReason, closeDetail);
}

//+------------------------------------------------------------------+
void FalgoStrongMomentumStallFlagsVelocity(const AlgoPerAlgoTune &tune,
   bool &outVelocityStall, bool &outGivebackStall)
{
   outVelocityStall = false;
   outGivebackStall = false;
   const double profitPts = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts;
   const double giveback = profitPts - g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts;
   const double vel = FalgoTelemetryProfitVelocityWindowSeconds(FalgoStrongMomentumVelocityWindowSeconds(tune));
   if(vel <= tune.strong_trade_stall_velocity_max_trigger)
      outVelocityStall = true;
   if(tune.strong_trade_stall_giveback_pts_trigger > 0.0 &&
      giveback <= -PointSized(tune.strong_trade_stall_giveback_pts_trigger))
      outGivebackStall = true;
}

//+------------------------------------------------------------------+
bool FalgoStrongMomentumAvgVelocityWeakenStall(const AlgoPerAlgoTune &tune)
{
   if(tune.strong_trade_stall_avgvelocity_weaken_pct <= 0.0)
      return false;
   const double peak = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].strongMomentumPeakAvgVelocity;
   const double avg = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocity;
   if(peak <= 0.0)
      return false;
   const double floor = peak * (1.0 - tune.strong_trade_stall_avgvelocity_weaken_pct / 100.0);
   return (avg < floor);
}

//+------------------------------------------------------------------+
bool FalgoStrongMomentumDetectStall(const AlgoPerAlgoTune &tune)
{
   if(tune.strong_trade_stall_mode_uses_avgvelocity_weakening)
      return FalgoStrongMomentumAvgVelocityWeakenStall(tune);
   bool velocityStall = false;
   bool givebackStall = false;
   FalgoStrongMomentumStallFlagsVelocity(tune, velocityStall, givebackStall);
   return velocityStall || givebackStall;
}

//+------------------------------------------------------------------+
string FalgoStrongMomentumStallReasonDetail(const AlgoPerAlgoTune &tune)
{
   if(tune.strong_trade_stall_mode_uses_avgvelocity_weakening)
   {
      const double peak = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].strongMomentumPeakAvgVelocity;
      const double avg = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocity;
      const double floor = (peak > 0.0 && tune.strong_trade_stall_avgvelocity_weaken_pct > 0.0)
         ? peak * (1.0 - tune.strong_trade_stall_avgvelocity_weaken_pct / 100.0) : 0.0;
      return StringFormat("avgvelocity_stall|avg=%.4f|peak=%.4f|floor=%.4f|weakenPct=%.1f",
         avg, peak, floor, tune.strong_trade_stall_avgvelocity_weaken_pct);
   }
   bool velocityStall = false;
   bool givebackStall = false;
   FalgoStrongMomentumStallFlagsVelocity(tune, velocityStall, givebackStall);
   string reasons = "";
   if(velocityStall)
      reasons = (reasons == "" ? "stall_velocity" : reasons + "|stall_velocity");
   if(givebackStall)
      reasons = (reasons == "" ? "stall_giveback" : reasons + "|stall_giveback");
   const double profitPts = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts;
   const double giveback = profitPts - g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts;
   const double vel = FalgoTelemetryProfitVelocityWindowSeconds(FalgoStrongMomentumVelocityWindowSeconds(tune));
   return StringFormat("%s|vel=%.3f|velMax=%.3f|giveback=%.1f|givebackMax=%.1f",
      reasons,
      vel, tune.strong_trade_stall_velocity_max_trigger,
      giveback, PointSized(tune.strong_trade_stall_giveback_pts_trigger));
}

//+------------------------------------------------------------------+
//| Strong-momentum babysit: latch aimStrongTp when accelerating near neutral TP; |
//| skip neutral TP while aiming for strong_trade_TP; close on stall or strong TP. |
//| Returns true if position closed. Sets outSkipNeutralTp when still holding for strong TP. |
//+------------------------------------------------------------------+
bool Babysitf_falgo_runStrongMomentumBabysit(const long posMagic, bool &outSkipNeutralTp)
{
   outSkipNeutralTp = false;
   AlgoPerAlgoTune tune;
   if(!AlgoLoadPerAlgoTuneForMagic(posMagic, tune))
      return false;
   if(!AlgoStrongTradeModeActive(tune) || !FalgoBabysitPositionMatchesOpenTelemetry())
      return false;

   const double profitPts = FalgoOpenPositionProfitPoints();
   const double stallMinClosePts = PointSized(tune.strong_trade_stall_min_close_profit_pts);

   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].aimStrongTp)
   {
      FalgoTryLatchStrongMomentumIfNeeded(tune, profitPts);
   }

   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].aimStrongTp)
      return false;

   FalgoStrongMomentumUpdatePeakAvgIfAiming();
   outSkipNeutralTp = true;
   const double strongTpPts = PointSized(tune.strong_trade_TP);
   if(profitPts >= strongTpPts)
   {
      return Babysitf_falgo_closeIfProfitTargetTune(posMagic, tune.strong_trade_TP, "strong_momentum_strong_tp",
         StringFormat("profit=%.1f|threshold=%.1f", profitPts, strongTpPts));
   }
   if(FalgoStrongMomentumDetectStall(tune) && profitPts >= stallMinClosePts)
   {
      return Babysitf_falgo_closeIfProfitPointsAtLeast(posMagic, stallMinClosePts, "strong_momentum_stall",
         StringFormat("profit=%.1f|stallMinClose=%.1f|%s", profitPts, stallMinClosePts,
            FalgoStrongMomentumStallReasonDetail(tune)));
   }
   return false;
}

//+------------------------------------------------------------------+
bool Babysitf_falgo_closeIfProfitPointsAtLeast(const long positionMagic, const double minProfitPoints,
   const string closeReason = "", const string closeDetail = "")
{
   if(minProfitPoints <= 0.0)
      return false;
   const double profitPts = FalgoOpenPositionProfitPoints();
   if(profitPts < minProfitPoints)
      return false;
   FalgoTryLogTelemetryCloseDecision(closeReason,
      (closeDetail == "" ? StringFormat("profit=%.1f|threshold=%.1f", profitPts, minProfitPoints) : closeDetail));
   const ulong posTicket = ExtPositionInfo.Ticket();
   const int telSlot = FalgoOpenTelemetryFindSlotByTicket(posTicket);
   const double accountProfit = FalgoSelectedPositionAccountProfit();
   ExtTrade.SetExpertMagicNumber((ulong)positionMagic);
   const bool closed = ExtTrade.PositionClose(posTicket);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   if(closed)
      FalgoAfterFamilyPositionClosed(positionMagic, profitPts, accountProfit, telSlot);
   return closed;
}

//+------------------------------------------------------------------+
bool Babysitf_falgo_closeIfProfitPointsAtOrAbove(const long positionMagic, const double minProfitPointsThreshold,
   const string closeReason = "", const string closeDetail = "")
{
   const double profitPts = FalgoOpenPositionProfitPoints();
   if(profitPts < minProfitPointsThreshold)
      return false;
   FalgoTryLogTelemetryCloseDecision(closeReason,
      (closeDetail == "" ? StringFormat("profit=%.1f|threshold=%.1f", profitPts, minProfitPointsThreshold) : closeDetail));
   const ulong posTicket = ExtPositionInfo.Ticket();
   const int telSlot = FalgoOpenTelemetryFindSlotByTicket(posTicket);
   const double accountProfit = FalgoSelectedPositionAccountProfit();
   ExtTrade.SetExpertMagicNumber((ulong)positionMagic);
   const bool closed = ExtTrade.PositionClose(posTicket);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   if(closed)
      FalgoAfterFamilyPositionClosed(positionMagic, profitPts, accountProfit, telSlot);
   return closed;
}

//+------------------------------------------------------------------+
//| Tune target in points (signed); 0=breakeven. Close when open profit >= PointSized(target). |
//+------------------------------------------------------------------+
bool Babysitf_falgo_closeIfProfitTargetTune(const long positionMagic, const double targetPointsTune,
   const string closeReason = "", const string closeDetail = "")
{
   const double targetPts = PointSized(targetPointsTune);
   return Babysitf_falgo_closeIfProfitPointsAtOrAbove(positionMagic, targetPts, closeReason,
      (closeDetail == "" ? StringFormat("profit=%.1f|threshold=%.1f", FalgoOpenPositionProfitPoints(), targetPts) : closeDetail));
}

//+------------------------------------------------------------------+
//| terribleTrade: latch when mae depth + consecutive red seconds + avgProfitVelocity10 all met; |
//| close when open profit >= terribletrade_try_smaller_loss_TP. |
//+------------------------------------------------------------------+
bool Babysitf_falgo_runTerribleTradeBabysit(const long posMagic)
{
   AlgoPerAlgoTune tune;
   if(!AlgoLoadPerAlgoTuneForMagic(posMagic, tune))
      return false;
   if(!AlgoTerribleTradeModeActive(tune))
      return false;
   if(!FalgoBabysitPositionMatchesOpenTelemetry())
      return false;

   FalgoTryLatchTradeRecoveryModes(tune);
   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].terribleTradeMode)
      return false;

   const double targetPts = PointSized(tune.terribletrade_try_smaller_loss_TP);
   return Babysitf_falgo_closeIfProfitTargetTune(posMagic, tune.terribletrade_try_smaller_loss_TP,
      "terribletrade_try_smaller_loss_TP",
      StringFormat("profit=%.1f|target=%.1f|MAE_post=%.1f", FalgoOpenPositionProfitPoints(), targetPts,
         g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePostXPts));
}

//+------------------------------------------------------------------+
//| badTrade: latch when mae depth + total red seconds both met; |
//| close when open profit >= badtrade_try_save_TP. |
//+------------------------------------------------------------------+
bool Babysitf_falgo_runBadTradeBabysit(const long posMagic)
{
   AlgoPerAlgoTune tune;
   if(!AlgoLoadPerAlgoTuneForMagic(posMagic, tune))
      return false;
   if(!AlgoBadTradeModeActive(tune))
      return false;
   if(!FalgoBabysitPositionMatchesOpenTelemetry())
      return false;

   FalgoTryLatchTradeRecoveryModes(tune);
   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].badTradeMode || g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].terribleTradeMode)
      return false;

   const double targetPts = PointSized(tune.badtrade_try_save_TP);
   return Babysitf_falgo_closeIfProfitTargetTune(posMagic, tune.badtrade_try_save_TP, "badtrade_try_save_TP",
      StringFormat("profit=%.1f|target=%.1f|MAE_post=%.1f", FalgoOpenPositionProfitPoints(), targetPts,
         g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePostXPts));
}

//+------------------------------------------------------------------+
//| secretTPSL SL leg: close when floating loss >= minLossPoints (mirror of TP profit rule). |
//+------------------------------------------------------------------+
bool Babysitf_falgo_closeIfLossPointsAtLeast(const long positionMagic, const double minLossPoints,
   const string closeReason = "", const string closeDetail = "")
{
   if(minLossPoints <= 0.0)
      return false;
   const double profitPts = FalgoOpenPositionProfitPoints();
   if(profitPts > -minLossPoints)
      return false;
   FalgoTryLogTelemetryCloseDecision(closeReason,
      (closeDetail == "" ? StringFormat("profit=%.1f|lossThreshold=-%.1f", profitPts, minLossPoints) : closeDetail));
   const ulong posTicket = ExtPositionInfo.Ticket();
   const int telSlot = FalgoOpenTelemetryFindSlotByTicket(posTicket);
   const double accountProfit = FalgoSelectedPositionAccountProfit();
   ExtTrade.SetExpertMagicNumber((ulong)positionMagic);
   const bool closed = ExtTrade.PositionClose(posTicket);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   if(closed)
      FalgoAfterFamilyPositionClosed(positionMagic, profitPts, accountProfit, telSlot);
   return closed;
}

//+------------------------------------------------------------------+
double FalgoBreakdownPriceAtRangePercent(const double breakdownLow, const double rangeTop, const double rangePercent)
{
   if(rangeTop <= breakdownLow || rangePercent <= 0.0)
      return 0.0;
   return NormalizeDouble(breakdownLow + (rangePercent / 100.0) * (rangeTop - breakdownLow), _Digits);
}

//+------------------------------------------------------------------+
int BreakdownNeedGreen15mCount(const BreakdownAlgoDef &bd)
{
   return (bd.after_bd_need_x_15greenc < 1) ? 1 : bd.after_bd_need_x_15greenc;
}

//+------------------------------------------------------------------+
bool BreakdownTriggerGreenForAlgo(const Breakdown15mState &st, const BreakdownAlgoDef &bd,
   double &outHigh, datetime &outBarEndTime)
{
   outHigh = 0.0;
   outBarEndTime = 0;
   const int need = BreakdownNeedGreen15mCount(bd);
   if(st.greensAfterBdCount < need)
      return false;
   const int idx = need - 1;
   outHigh = st.greensAfterBdHigh[idx];
   outBarEndTime = st.greensAfterBdBarEndTime[idx];
   return (outHigh > 0.0 && outBarEndTime > 0);
}

//+------------------------------------------------------------------+
double BreakdownEntryPriceForAlgo(const BreakdownAlgoDef &bd, const Breakdown15mState &st)
{
   double triggerHigh = 0.0;
   datetime triggerEnd = 0;
   if(!BreakdownTriggerGreenForAlgo(st, bd, triggerHigh, triggerEnd))
      return 0.0;
   if(triggerHigh <= st.breakdownLow)
      return 0.0;
   return FalgoBreakdownPriceAtRangePercent(st.breakdownLow, triggerHigh, bd.entryrange_range_percentspot);
}

//+------------------------------------------------------------------+
//| Long breakdown: secret TP only when bid reached secretTp above entry; greenguard only then. |
//+------------------------------------------------------------------+
bool BreakdownSecretTpGreenGuardAllowsClose(const BreakdownAlgoDef &bd, const double entryPrice,
   const double secretTpPrice, const double bidPrice)
{
   if(bd.secret_tp_greenguard_pricediff_at_least <= 0.0)
      return true;
   if(entryPrice <= 0.0 || secretTpPrice <= 0.0 || bidPrice <= 0.0)
      return false;
   if(secretTpPrice <= entryPrice)
      return false;
   const double currentProfitDistance = bidPrice - entryPrice;
   return (currentProfitDistance >= bd.secret_tp_greenguard_pricediff_at_least);
}

//+------------------------------------------------------------------+
bool Babysitf_falgo_runBreakdownSecretTpExit(const long posMagic)
{
   const int algoNumber = AlgoFamilyMagicNumber(posMagic);
   BreakdownAlgoDef bd;
   if(!BreakdownAlgoDefForNumber(algoNumber, bd))
      return false;
   if(!bd.secret_tp_enabled || bd.secret_tp_range_percent <= 0)
      return false;

   const ulong posTicket = ExtPositionInfo.Ticket();
   const int slotIdx = FalgoOpenTelemetryFindSlotByTicket(posTicket);
   double startHigh = 0.0;
   double breakdownLow = 0.0;
   if(slotIdx >= 0)
   {
      startHigh = g_falgoOpenTelemetrySlots[slotIdx].breakdownStartHigh;
      breakdownLow = g_falgoOpenTelemetrySlots[slotIdx].breakdownLow;
   }
   const int bIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(startHigh <= 0.0 || breakdownLow <= 0.0)
   {
      if(bIdx >= 0)
      {
         startHigh = g_breakdownAlgoLastPlacedStartHigh[bIdx];
         breakdownLow = g_breakdownAlgoLastPlacedBreakdownLow[bIdx];
      }
   }
   const double secretTpPrice = FalgoBreakdownPriceAtRangePercent(breakdownLow, startHigh, bd.secret_tp_range_percent);
   if(secretTpPrice <= 0.0)
      return false;

   const double entryPrice = ExtPositionInfo.PriceOpen();
   if(entryPrice <= 0.0)
      return false;
   if(secretTpPrice <= entryPrice)
      return false;

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid < secretTpPrice)
      return false;

   if(!BreakdownSecretTpGreenGuardAllowsClose(bd, entryPrice, secretTpPrice, bid))
      return false;

   if(slotIdx >= 0)
      g_falgoOpenTelemetryCtx = slotIdx;
   FalgoTryLogTelemetryCloseDecision("breakdown_secretTPSL_tp",
      StringFormat("bid=%s|secretTp=%s|low=%s|start=%s|pct=%d",
         DoubleToString(bid, _Digits), DoubleToString(secretTpPrice, _Digits),
         DoubleToString(breakdownLow, _Digits), DoubleToString(startHigh, _Digits),
         bd.secret_tp_range_percent));
   BreakdownRememberPendingCloseReason((ulong)ExtPositionInfo.Identifier(), "secretTP");
   const int telSlot = slotIdx;
   const double profitPts = FalgoOpenPositionProfitPoints();
   const double accountProfit = FalgoSelectedPositionAccountProfit();
   ExtTrade.SetExpertMagicNumber((ulong)posMagic);
   const bool closed = ExtTrade.PositionClose(posTicket);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   if(closed)
      FalgoAfterFamilyPositionClosed(posMagic, profitPts, accountProfit, telSlot);
   return closed;
}

//+------------------------------------------------------------------+
bool Babysitf_falgo_runBreakdownMidpointTimeExit(const long posMagic)
{
   const int algoNumber = AlgoFamilyMagicNumber(posMagic);
   BreakdownAlgoDef bd;
   if(!BreakdownAlgoDefForNumber(algoNumber, bd))
      return false;
   if(!bd.closetrade_after_some_time)
      return false;

   const ulong posTicket = ExtPositionInfo.Ticket();
   const int slotIdx = FalgoOpenTelemetryFindSlotByTicket(posTicket);
   datetime deadline = 0;
   datetime breakdownEnd = 0;
   if(slotIdx >= 0)
   {
      deadline = g_falgoOpenTelemetrySlots[slotIdx].breakdownTimeExitDeadline;
      breakdownEnd = g_falgoOpenTelemetrySlots[slotIdx].breakdownSequenceEndTime;
   }
   if(deadline <= 0)
   {
      BreakdownOpenLifetimeBreakdownEnd((ulong)ExtPositionInfo.Identifier(), breakdownEnd);
      if(breakdownEnd > 0)
         deadline = breakdownEnd + bd.closetrade_after_x_minutes_from_breakdown * 60;
   }
   if(deadline <= 0 || g_lastTimer1Time < deadline)
      return false;

   const double profitPct = FalgoOpenPositionProfitPctOfPositionDeposit();
   if(bd.closetrade_after_some_time_butOnlyIfProfit
      && profitPct < bd.closetrade_after_some_time_but_ProfitPercent_Needed)
      return false;

   if(slotIdx >= 0)
      g_falgoOpenTelemetryCtx = slotIdx;
   FalgoTryLogTelemetryCloseDecision("breakdown_midpoint_time_exit",
      StringFormat("now=%s|deadline=%s|breakdownEnd=%s|profitPct=%.2f|profitNeeded=%.2f|onlyIfProfit=%s",
         TimeToString(g_lastTimer1Time, TIME_DATE|TIME_MINUTES),
         TimeToString(deadline, TIME_DATE|TIME_MINUTES),
         TimeToString(breakdownEnd, TIME_DATE|TIME_MINUTES),
         profitPct, bd.closetrade_after_some_time_but_ProfitPercent_Needed,
         (bd.closetrade_after_some_time_butOnlyIfProfit ? "true" : "false")));
   BreakdownRememberPendingCloseReason((ulong)ExtPositionInfo.Identifier(), "timeTrigger");
   const int telSlot = slotIdx;
   const double profitPts = FalgoOpenPositionProfitPoints();
   const double accountProfit = FalgoSelectedPositionAccountProfit();
   ExtTrade.SetExpertMagicNumber((ulong)posMagic);
   const bool closed = ExtTrade.PositionClose(posTicket);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   if(closed)
      FalgoAfterFamilyPositionClosed(posMagic, profitPts, accountProfit, telSlot);
   return closed;
}

//+------------------------------------------------------------------+
//| Breakdown open positions: secret TP, time exit — not gated by tradingTimeBanned. |
//+------------------------------------------------------------------+
void Babysitf_RunBreakdownOpenPositionsForSymbol()
{
   if(!g_breakdownAlgoShared.babysit_enabled)
      return;
   for(int positionIdx = PositionsTotal() - 1; positionIdx >= 0; positionIdx--)
   {
      if(!ExtPositionInfo.SelectByIndex(positionIdx))
         continue;
      if(ExtPositionInfo.Symbol() != _Symbol)
         continue;
      const long posMagic = ExtPositionInfo.Magic();
      if(!IsBreakdownFamilyCompositeMagic(posMagic))
         continue;
      if(Babysitf_falgo_runBreakdownSecretTpExit(posMagic))
         continue;
      Babysitf_falgo_runBreakdownMidpointTimeExit(posMagic);
   }
}

//+------------------------------------------------------------------+
bool FalgoBuildMagicKeyForBreakdownPlacement(const int algoNumber, const int direction, FalgoMagicKey &outKey)
{
   if(direction != FALGO_DIRECTION_LONG_LIMIT)
      return false;
   const int levelSlot = FALGO_MAGIC_LEVEL_SLOT_BREAKDOWN;
   const int nextLevelTradeNum = BreakdownLevelTradeNumTodayAtMagicLevelSlot(algoNumber, levelSlot) + 1;
   outKey.direction = direction;
   outKey.dayOfWeek = FalgoDayOfWeekSlotFromTime(g_lastTimer1Time);
   outKey.levelSlot = levelSlot;
   outKey.bounceCount = 0;
   outKey.ceilingCount = 0;
   outKey.offset_tenths = 0;
   outKey.planTradeNum = FalgoClamp0_8(BreakdownPlanTradeNumToday(algoNumber) + 1);
   outKey.levelTradeNum = FalgoClamp0_8(nextLevelTradeNum);
   outKey.babysitMinute = 0;
   const int bIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   outKey.slWhole = 0;
   outKey.tpWhole = 0;
   if(bIdx >= 0 && g_breakdownAlgos[bIdx].sl_enabled && g_breakdownAlgos[bIdx].sl_points > 0.0)
      outKey.slWhole = FalgoCapWholeTpSlForMagic(g_breakdownAlgos[bIdx].sl_points);
   if(bIdx >= 0 && g_breakdownAlgos[bIdx].tp_enabled)
   {
      const Breakdown15mState bdSnap = Breakdown15mSnapForAlgo(algoNumber, g_lastTimer1Time);
      const double entryPrice = BreakdownEntryPriceForAlgo(g_breakdownAlgos[bIdx], bdSnap);
      const double brokerTp = FalgoBreakdownPriceAtRangePercent(bdSnap.breakdownLow, bdSnap.startHigh,
         g_breakdownAlgos[bIdx].tp_notsecret_range_percent);
      if(entryPrice > 0.0 && brokerTp > entryPrice)
      {
         const double tpPts = FalgoProfileOffsetPointsFromPriceDelta(brokerTp - entryPrice);
         outKey.tpWhole = FalgoCapWholeTpSlForMagic(MathMax(0.0, tpPts));
      }
   }
   return true;
}

//+------------------------------------------------------------------+
int BreakdownNormalizeStreakContinuationMode(const ENUM_BREAKDOWN_STREAK_CONTINUATION mode)
{
   if(mode < BREAKDOWN_STREAK_CONTINUATION_CLOSES || mode >= BREAKDOWN_STREAK_CONTINUATION_COUNT)
      return BREAKDOWN_STREAK_CONTINUATION_CLOSES;
   return (int)mode;
}

//+------------------------------------------------------------------+
double BreakdownStreakBarMetric(const MqlRates &bar, const ENUM_BREAKDOWN_STREAK_CONTINUATION continuationMode)
{
   switch(continuationMode)
   {
      case BREAKDOWN_STREAK_CONTINUATION_OHLC_AVG:
         return (bar.open + bar.high + bar.low + bar.close) / 4.0;
      case BREAKDOWN_STREAK_CONTINUATION_LOW:
         return bar.low;
      case BREAKDOWN_STREAK_CONTINUATION_OC_MID:
         return (bar.open + bar.close) / 2.0;
      case BREAKDOWN_STREAK_CONTINUATION_HL_MID:
         return (bar.high + bar.low) / 2.0;
      case BREAKDOWN_STREAK_CONTINUATION_CLOSES:
      default:
         return bar.close;
   }
}

//+------------------------------------------------------------------+
double BreakdownStartMinPercentForAlgoDef(const BreakdownAlgoDef &bd)
{
   return (bd.bd_start_min_breakdown_percent > 0.0) ? bd.bd_start_min_breakdown_percent : 0.20;
}

//+------------------------------------------------------------------+
void EnsureBreakdown15mSnapForAlgoSlot(const int algoSlot, const datetime asOfTime)
{
   if(algoSlot < 0 || algoSlot >= BREAKDOWN_ALGO_REGISTRY_MAX)
      return;
   if(g_breakdown15mSnapByAlgoAsOf != asOfTime)
   {
      g_breakdown15mSnapByAlgoAsOf = asOfTime;
      for(int i = 0; i < BREAKDOWN_ALGO_REGISTRY_MAX; i++)
         g_breakdown15mSnapByAlgoSlotReady[i] = false;
   }
   if(g_breakdown15mSnapByAlgoSlotReady[algoSlot])
      return;
   const BreakdownAlgoDef bd = g_breakdownAlgos[algoSlot];
   const datetime dayStart = asOfTime - (asOfTime % 86400);
   const double startPct = BreakdownStartMinPercentForAlgoDef(bd);
   const int forgetMin = bd.forget_about_latest_breakdown_after_x_15m_candles * 15;
   ComputeBreakdown15mState(dayStart, asOfTime, startPct, forgetMin, bd.breakdown_streak_continuation_mode,
      g_breakdown15mSnapByAlgoSlot[algoSlot]);
   g_breakdown15mSnapByAlgoSlotReady[algoSlot] = true;
}

//+------------------------------------------------------------------+
Breakdown15mState Breakdown15mSnapForAlgo(const int algoNumber, const datetime asOfTime)
{
   Breakdown15mState empty;
   ZeroMemory(empty);
   const int slot = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(slot < 0)
      return empty;
   EnsureBreakdown15mSnapForAlgoSlot(slot, asOfTime);
   return g_breakdown15mSnapByAlgoSlot[slot];
}

//+------------------------------------------------------------------+
void RefreshGlobalBreakdown15mSnap(const datetime asOfTime)
{
   int slot = BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200);
   if(slot < 0)
   {
      for(int i = 0; i < g_breakdownAlgoCount; i++)
      {
         if(g_breakdownAlgos[i].enabled)
         {
            slot = i;
            break;
         }
      }
   }
   if(slot < 0)
   {
      ZeroMemory(g_breakdown15mSnap);
      return;
   }
   EnsureBreakdown15mSnapForAlgoSlot(slot, asOfTime);
   g_breakdown15mSnap = g_breakdown15mSnapByAlgoSlot[slot];
}

//+------------------------------------------------------------------+
bool BreakdownAlgoHasClosedTradeToday(const int algoNumber)
{
   const int slotIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(slotIdx >= 0 && (g_breakdownAlgoDayWins[slotIdx] + g_breakdownAlgoDayLosses[slotIdx]) > 0)
      return true;

   const datetime dayStart = FalgoTradingDayStart();
   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      if(!IsBreakdownFamilyCompositeMagic(g_tradeResults[i].magic))
         continue;
      if(AlgoFamilyMagicNumber(g_tradeResults[i].magic) != algoNumber)
         continue;
      if(!g_tradeResults[i].foundOut)
         continue;
      if(g_tradeResults[i].startTime > 0 && FalgoTradeStartedOnTradingDay(g_tradeResults[i], dayStart))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
string BreakdownAlgoOrderStateBlockReason(const int algoNumber)
{
   if(AlgoHasPendingOrderOnSymbol(algoNumber))
      return "algoOrderPending";
   if(AlgoHasOpenPositionOnSymbol(algoNumber))
      return "algoOrderOpen";
   return "";
}

//+------------------------------------------------------------------+
string BreakdownSameBreakdownClosedBlockReason(const int algoNumber, const datetime breakdownEndTime)
{
   const int slotIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(slotIdx < 0 || breakdownEndTime <= 0)
      return "";
   if(g_breakdownAlgoLastPlacedEndTime[slotIdx] != breakdownEndTime)
      return "";
   if(BreakdownAlgoHasClosedTradeToday(algoNumber))
      return "breakdownAlreadyTraded";
   return "";
}

//+------------------------------------------------------------------+
//| Same-breakdown placement gate: pending vs open vs closed for this breakdown sequence. |
//+------------------------------------------------------------------+
string BreakdownSameBreakdownPlacementBlockReason(const int algoNumber, const datetime breakdownEndTime)
{
   const string orderState = BreakdownAlgoOrderStateBlockReason(algoNumber);
   if(orderState != "")
      return orderState;
   return BreakdownSameBreakdownClosedBlockReason(algoNumber, breakdownEndTime);
}

//+------------------------------------------------------------------+
string BreakdownMidpointEntryBlockReason(const int algoNumber, const Breakdown15mState &st, const datetime now)
{
   BreakdownAlgoDef bd;
   if(!BreakdownAlgoDefForNumber(algoNumber, bd))
      return "algoNotRegistered";

   const string orderState = BreakdownAlgoOrderStateBlockReason(algoNumber);
   if(orderState != "")
      return orderState;

   if(!st.hasBreakdown)
      return "noBreakdownYet";
   if(st.sequenceActive)
   {
      if(bd.max_breakdown_sequence_len > 0 && st.activeLength > bd.max_breakdown_sequence_len)
         return StringFormat("breakdownLengthTooLong(%d vs max %d)", st.activeLength, bd.max_breakdown_sequence_len);
      return StringFormat("breakdownActive(len=%d)", st.activeLength);
   }
   if(st.endedLength < bd.min_breakdown_sequence_len)
      return StringFormat("breakdownLengthTooShort(%d vs %d)", st.endedLength, bd.min_breakdown_sequence_len);
   if(bd.max_breakdown_sequence_len > 0 && st.endedLength > bd.max_breakdown_sequence_len)
      return StringFormat("breakdownLengthTooLong(%d vs max %d)", st.endedLength, bd.max_breakdown_sequence_len);
   if(-st.totalPercent < bd.min_breakdown_total_percent)
      return StringFormat("breakdownDropTooSmall(%.2f%% vs min %.2f%%)", -st.totalPercent, bd.min_breakdown_total_percent);
   if(st.endTime <= 0)
      return "noBreakdownEndTime";
   if(now < st.endTime)
      return "beforeBreakdownEnd";
   const int needGreen = BreakdownNeedGreen15mCount(bd);
   if(st.greensAfterBdCount < needGreen)
      return StringFormat("needMoreGreen15m(%d vs %d)", st.greensAfterBdCount, needGreen);
   double triggerHigh = 0.0;
   datetime triggerBarEnd = 0;
   if(!BreakdownTriggerGreenForAlgo(st, bd, triggerHigh, triggerBarEnd))
      return "noTriggerGreenEntryPrice";
   if(triggerHigh <= st.breakdownLow)
      return "noTriggerGreenEntryPrice";
   const double entryPrice = BreakdownEntryPriceForAlgo(bd, st);
   if(entryPrice <= 0.0)
      return "noTriggerGreenEntryPrice";
   if(now < triggerBarEnd)
      return StringFormat("beforeGreen15mClose(%d)", needGreen);
   const int forgetMinutes = bd.forget_about_latest_breakdown_after_x_15m_candles * 15;
   if(forgetMinutes > 0 && now - st.endTime > forgetMinutes * 60)
      return "";
   const string sameBdClosed = BreakdownSameBreakdownClosedBlockReason(algoNumber, st.endTime);
   if(sameBdClosed != "")
      return sameBdClosed;
   if(now - st.endTime > bd.entry_max_minutes_after_bdend * 60)
      return "breakdownEndTooOld";
   return "";
}

//+------------------------------------------------------------------+
bool BreakdownMidpointEntryAllowed(const int algoNumber, const Breakdown15mState &st, const datetime now)
{
   return (BreakdownMidpointEntryBlockReason(algoNumber, st, now) == "");
}

//+------------------------------------------------------------------+
string BreakdownPlannedTradePriceForGates(const int algoNumber, const datetime evalTime, const Breakdown15mState &st)
{
   BreakdownAlgoDef bd;
   if(!BreakdownAlgoDefForNumber(algoNumber, bd))
      return "";
   double triggerHigh = 0.0;
   datetime triggerBarEnd = 0;
   if(!BreakdownTriggerGreenForAlgo(st, bd, triggerHigh, triggerBarEnd))
      return "";
   if(evalTime < triggerBarEnd)
      return "";
   const double entryPrice = BreakdownEntryPriceForAlgo(bd, st);
   if(entryPrice <= 0.0)
      return "";
   return DoubleToString(entryPrice, _Digits);
}

//+------------------------------------------------------------------+
double BreakdownPlannedTradePriceAtEval(const int algoNumber, const int barIdx, const datetime evalTime)
{
   const Breakdown15mState bdSnap = Breakdown15mSnapForAlgo(algoNumber, evalTime);
   const string plannedStr = BreakdownPlannedTradePriceForGates(algoNumber, evalTime, bdSnap);
   if(StringLen(plannedStr) == 0)
      return 0.0;
   return StringToDouble(plannedStr);
}

//+------------------------------------------------------------------+
struct FalgoTradeLegacyContextCols
{
   string mfeCandle;
   string maeCandle;
   string breakevenC;
   string gapFillPc;
   string openGapInfo;
   string pdTrend;
   string dayBrokePDH;
   string dayBrokePDL;
   string refAbove;
   string refBelow;
   string levelCats;
};

//+------------------------------------------------------------------+
double BreakdownPlannedPriceForTradeResult(const TradeResult &tr)
{
   const datetime dayStart = (tr.startTime > 0 ? tr.startTime : tr.sentTime);
   if(dayStart > 0 && tr.sentTime > 0 && HistorySelect(dayStart - (dayStart % 86400), dayStart - (dayStart % 86400) + 86400))
   {
      for(int i = HistoryOrdersTotal() - 1; i >= 0; i--)
      {
         const ulong orderTicket = HistoryOrderGetTicket(i);
         if(orderTicket == 0 || !HistoryOrderSelect(orderTicket))
            continue;
         if(HistoryOrderGetString(orderTicket, ORDER_SYMBOL) != tr.symbol)
            continue;
         if(HistoryOrderGetInteger(orderTicket, ORDER_MAGIC) != tr.magic)
            continue;
         if((datetime)HistoryOrderGetInteger(orderTicket, ORDER_TIME_SETUP) != tr.sentTime)
            continue;
         const double planned = HistoryOrderGetDouble(orderTicket, ORDER_PRICE_OPEN);
         if(planned > 0.0)
            return planned;
      }
   }
   if(StringLen(tr.level) > 0)
   {
      const double fromLevel = StringToDouble(tr.level);
      if(fromLevel > 0.0)
         return fromLevel;
   }
   return tr.priceStart;
}

//+------------------------------------------------------------------+
double FalgoLevelPriceForTradeResult(const TradeResult &tr)
{
   if(!IsAnyAlgoFamilyCompositeMagic(tr.magic))
      return StringToDouble(tr.level);
   return FalgoLevelPriceForMagicKey(ParseFalgoMagic(tr.magic));
}

//+------------------------------------------------------------------+
void FalgoFillTradeLegacyContextCols(const TradeResult &tr, FalgoTradeLegacyContextCols &out)
{
   out.mfeCandle = "";
   out.maeCandle = "";
   out.breakevenC = "";
   out.gapFillPc = "";
   out.openGapInfo = "";
   out.pdTrend = "";
   out.dayBrokePDH = "";
   out.dayBrokePDL = "";
   out.refAbove = "";
   out.refBelow = "";
   out.levelCats = "";

   FalgoClosedTradeTelemetrySummary telSummary;
   if(FalgoGetTelemetrySummaryForTrade(tr.magic, tr.startTime, telSummary))
   {
      if(telSummary.mfeCandle1Based > 0)
         out.mfeCandle = IntegerToString(telSummary.mfeCandle1Based);
      if(telSummary.maeCandle1Based > 0)
         out.maeCandle = IntegerToString(telSummary.maeCandle1Based);
   }

   const int breakevenC = Get3c30cLevelBreakevenCForTrade(tr);
   if(breakevenC >= 3)
      out.breakevenC = IntegerToString(breakevenC);

   out.gapFillPc = GetGapFillPcAtTradeOpenTime(tr.startTime);
   out.openGapInfo = GetIsGapDownDayString(tr.startTime);
   out.pdTrend = GetPDtrendString();
   out.dayBrokePDH = GetDayBrokePDHAtTradeOpenTime(tr.startTime);
   out.dayBrokePDL = GetDayBrokePDLAtTradeOpenTime(tr.startTime);

   const FalgoMagicKey fk = ParseFalgoMagic(tr.magic);
   if(IsAnyAlgoFamilyCompositeMagic(tr.magic) && !IsBreakdownFamilyCompositeMagic(tr.magic))
      out.levelCats = g_levelsExpanded[FalgoResolveExpandedLevelIdxFromMagicKey(fk)].categories;

   const double levelPrice = (IsBreakdownFamilyCompositeMagic(tr.magic)
      ? BreakdownPlannedPriceForTradeResult(tr)
      : FalgoLevelPriceForTradeResult(tr));
   if(levelPrice > 0.0)
   {
      GetReferencePointsAboveBelow(tr.startTime, levelPrice, out.refAbove, out.refBelow);
      if(out.levelCats == "")
      {
         string levelTagDummy = "";
         const string levelStr = (StringLen(tr.level) > 0) ? tr.level : DoubleToString(levelPrice, _Digits);
         GetLevelTagAndCatsForTrade(levelStr, levelTagDummy, out.levelCats);
      }
   }
}

//+------------------------------------------------------------------+
//| w/d bounce & ceiling at trade open: dayStart_weekPerspective prior days + today through last closed M1 before startTime. |
//+------------------------------------------------------------------+
void FalgoFillTradeBounceCeilingCountsAtStart(const TradeResult &tr,
   int &outWBounce, int &outDBounce, int &outWCeiling, int &outDCeiling)
{
   outWBounce = 0;
   outDBounce = 0;
   outWCeiling = 0;
   outDCeiling = 0;
   if(tr.startTime <= 0)
      return;

   const double levelPrice = FalgoLevelPriceForTradeResult(tr);
   if(levelPrice <= 0.0)
      return;

   AlgoFamilyDayBounceCeilingForLevelAsOfTime(levelPrice, tr.startTime, outDBounce, outDCeiling);
   outWBounce = AlgoFamilyDayStartWeekPerspectiveBounceForLevel(levelPrice) + outDBounce;
   outWCeiling = AlgoFamilyDayStartWeekPerspectiveCeilingForLevel(levelPrice) + outDCeiling;
}

//+------------------------------------------------------------------+
#define FALGO_ALLDAYS_COLS              47
#define FALGO_BREAKDOWN_ALLDAYS_COLS    42

string FalgoAllDaysTradeResultsHeader()
{
   return "date,symbol,sentTime,startTime,endTime,sessionSent,magic,priceStart,priceEnd,priceDiff,profit,type,level,levelTag,levelSlot,MFE,MAE,"
      + FalgoTradeResultMaeFirstCsvColumnName()
      + ",mfeCandle,maeCandle,close_decision,close_detail,reason,volume,bothComments,planTradeNumToday,levelTradeNumToday,offset,tp,sl,greenRatio_at_close,avg_profitVelocity_5,secondsGreen,secondsRed,3c_30c_level_breakevenC,gapFillPc_at_tradeOpenTime,openGap_info,PD_trend,dayBrokePDH,dayBrokePDL,referencePointsAbove,referencePointsBelow,levelCats,wCeilingC,dCeilingC,wBounceC,dBounceC";
}

//+------------------------------------------------------------------+
string FalgoBreakdownAllDaysTradeResultsHeader()
{
   return "date,symbol,sentTime,startTime,endTime,sessionSent,magic,priceStart,priceEnd,priceDiff,profit,type,level,MFE,MAE,"
      + FalgoTradeResultMaeFirstCsvColumnName()
      + ",mfeCandle,maeCandle,close_decision,close_detail,reason,volume,bothComments,planTradeNumToday,levelTradeNumToday,offset,tp,sl,greenRatio_at_close,avg_profitVelocity_5,secondsGreen,secondsRed,3c_30c_level_breakevenC,gapFillPc_at_tradeOpenTime,openGap_info,PD_trend,dayBrokePDH,dayBrokePDL,referencePointsAbove,referencePointsBelow,secret_tp_range_percent,closetrade_after_x_minutes_from_breakdown";
}

//+------------------------------------------------------------------+
void FalgoFileWriteAllDaysHeader(const int fh, const string header)
{
   FileWriteString(fh, header + "\r\n");
}

//+------------------------------------------------------------------+
void FalgoFileWriteAllDaysRowFromCells(const int fh, const string &cells[], const int base, const int colCount)
{
   string row = FalgoSanitizeCsvCell(cells[base + 0]);
   for(int c = 1; c < colCount; c++)
      row += "," + FalgoSanitizeCsvCell(cells[base + c]);
   FileWriteString(fh, row + "\r\n");
}

//+------------------------------------------------------------------+
//| Read all-days trade-results file: one line = one row; exact colCount only. |
//+------------------------------------------------------------------+
void FalgoReadAllDaysTradeResultsFromFile(const string fileName, string &outCells[], int &outRowCount, const int colCount)
{
   outRowCount = 0;
   ArrayResize(outCells, 0);
   int fh = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   bool headerSkipped = false;
   while(!FileIsEnding(fh))
   {
      string line = FileReadString(fh);
      if(StringLen(line) == 0)
         continue;
      if(!headerSkipped)
      {
         headerSkipped = true;
         if(StringFind(line, "date,") == 0)
            continue;
      }
      string parts[];
      if(StringSplit(line, ',', parts) != colCount)
         continue;
      const int base = ArraySize(outCells);
      ArrayResize(outCells, base + colCount);
      for(int c = 0; c < colCount; c++)
         outCells[base + c] = parts[c];
      outRowCount++;
   }
   FileClose(fh);
}

//+------------------------------------------------------------------+
void FalgoWriteAllDaysTradeResultsToFile(const string fileName, const string &cells[], const int rowCount,
   const string header, const int colCount)
{
   int fh = FileOpen(fileName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   FalgoFileWriteAllDaysHeader(fh, header);
   for(int ri = 0; ri < rowCount; ri++)
      FalgoFileWriteAllDaysRowFromCells(fh, cells, ri * colCount, colCount);
   FileClose(fh);
}

//+------------------------------------------------------------------+
void FalgoAppendTradeResultCells(string &cells[], const string dateStr, const TradeResult &tr)
{
   const int base = ArraySize(cells);
   ArrayResize(cells, base + FALGO_ALLDAYS_COLS);
   cells[base + 0]  = dateStr;
   cells[base + 1]  = tr.symbol;
   cells[base + 2]  = TimeToString(tr.sentTime, TIME_DATE|TIME_SECONDS);
   cells[base + 3]  = TimeToString(tr.startTime, TIME_DATE|TIME_SECONDS);
   cells[base + 4]  = TimeToString(tr.endTime, TIME_DATE|TIME_SECONDS);
   cells[base + 5]  = FalgoSanitizeCsvCell(tr.sessionSent);
   cells[base + 6]  = IntegerToString((long)tr.magic);
   cells[base + 7]  = DoubleToString(tr.priceStart, _Digits);
   cells[base + 8]  = DoubleToString(tr.priceEnd, _Digits);
   cells[base + 9]  = DoubleToString(tr.priceDiff, _Digits);
   cells[base + 10] = DoubleToString(tr.profit, 2);
   cells[base + 11] = FalgoSanitizeCsvCell(EnumToString((ENUM_DEAL_TYPE)tr.type));
   int planNum = 0, levelNum = 0;
   FalgoPlanAndLevelTradeNumsFromMagic(tr.magic, planNum, levelNum);
   cells[base + 12] = FalgoSanitizeCsvCell(tr.level);
   cells[base + 13] = FalgoSanitizeCsvCell(FalgoLevelTagUneditedForTradeResult(tr));
   cells[base + 14] = FalgoSanitizeCsvCell(FalgoLevelSlotStrForMagic(tr.magic));
   FalgoClosedTradeTelemetrySummary telSummary;
   const bool hasTel = FalgoGetTelemetrySummaryForTrade(tr.magic, tr.startTime, telSummary);
   FalgoTradeLegacyContextCols legacyCtx;
   FalgoFillTradeLegacyContextCols(tr, legacyCtx);
   if(hasTel)
   {
      cells[base + 15] = DoubleToString(telSummary.mfePts, 1);
      cells[base + 16] = DoubleToString(telSummary.maePts, 1);
      cells[base + 17] = DoubleToString(telSummary.maeFirstWindowPts, 1);
      cells[base + 20] = FalgoSanitizeCsvCell(telSummary.closeDecision);
      cells[base + 21] = FalgoSanitizeCsvCell(telSummary.closeDetail);
      cells[base + 30] = DoubleToString(telSummary.greenRatioAtClose, 4);
      cells[base + 31] = DoubleToString(telSummary.avgProfitVelocity, 3);
      cells[base + 32] = IntegerToString(telSummary.secondsGreen);
      cells[base + 33] = IntegerToString(telSummary.secondsRed);
   }
   else
   {
      cells[base + 15] = "";
      cells[base + 16] = "";
      cells[base + 17] = "";
      cells[base + 20] = "";
      cells[base + 21] = "";
      cells[base + 30] = "";
      cells[base + 31] = "";
      cells[base + 32] = "";
      cells[base + 33] = "";
   }
   cells[base + 18] = FalgoSanitizeCsvCell(legacyCtx.mfeCandle);
   cells[base + 19] = FalgoSanitizeCsvCell(legacyCtx.maeCandle);
   cells[base + 22] = FalgoSanitizeCsvCell(EnumToString((ENUM_DEAL_REASON)tr.reason));
   cells[base + 23] = (string)tr.volume;
   cells[base + 24] = FalgoSanitizeCsvCell(tr.bothComments);
   cells[base + 25] = IntegerToString(planNum);
   cells[base + 26] = IntegerToString(levelNum);
   cells[base + 27] = FalgoOffsetPriceUnitsStrForTrade(tr);
   cells[base + 28] = FalgoSanitizeCsvCell(tr.tp);
   cells[base + 29] = FalgoSanitizeCsvCell(tr.sl);
   cells[base + 34] = FalgoSanitizeCsvCell(legacyCtx.breakevenC);
   cells[base + 35] = FalgoSanitizeCsvCell(legacyCtx.gapFillPc);
   cells[base + 36] = FalgoSanitizeCsvCell(legacyCtx.openGapInfo);
   cells[base + 37] = FalgoSanitizeCsvCell(legacyCtx.pdTrend);
   cells[base + 38] = FalgoSanitizeCsvCell(legacyCtx.dayBrokePDH);
   cells[base + 39] = FalgoSanitizeCsvCell(legacyCtx.dayBrokePDL);
   cells[base + 40] = FalgoSanitizeCsvCell(legacyCtx.refAbove);
   cells[base + 41] = FalgoSanitizeCsvCell(legacyCtx.refBelow);
   cells[base + 42] = FalgoSanitizeCsvCell(legacyCtx.levelCats);
   int wBounceC = 0, dBounceC = 0, wCeilingC = 0, dCeilingC = 0;
   FalgoFillTradeBounceCeilingCountsAtStart(tr, wBounceC, dBounceC, wCeilingC, dCeilingC);
   cells[base + 43] = IntegerToString(wCeilingC);
   cells[base + 44] = IntegerToString(dCeilingC);
   cells[base + 45] = IntegerToString(wBounceC);
   cells[base + 46] = IntegerToString(dBounceC);
}

//+------------------------------------------------------------------+
void BreakdownAllDaysAlgoConfigForMagic(const long magic, int &outSecretTpRangePct, int &outCloseAfterMinFromBd)
{
   outSecretTpRangePct = 0;
   outCloseAfterMinFromBd = 0;
   BreakdownAlgoDef bd;
   if(!BreakdownAlgoDefForNumber(AlgoFamilyMagicNumber(magic), bd))
      return;
   outSecretTpRangePct = bd.secret_tp_range_percent;
   outCloseAfterMinFromBd = bd.closetrade_after_x_minutes_from_breakdown;
}

//+------------------------------------------------------------------+
void FalgoAppendBreakdownTradeResultCells(string &cells[], const string dateStr, const TradeResult &tr)
{
   const int base = ArraySize(cells);
   ArrayResize(cells, base + FALGO_BREAKDOWN_ALLDAYS_COLS);
   cells[base + 0]  = dateStr;
   cells[base + 1]  = tr.symbol;
   cells[base + 2]  = TimeToString(tr.sentTime, TIME_DATE|TIME_SECONDS);
   cells[base + 3]  = TimeToString(tr.startTime, TIME_DATE|TIME_SECONDS);
   cells[base + 4]  = TimeToString(tr.endTime, TIME_DATE|TIME_SECONDS);
   cells[base + 5]  = FalgoSanitizeCsvCell(tr.sessionSent);
   cells[base + 6]  = IntegerToString((long)tr.magic);
   cells[base + 7]  = DoubleToString(tr.priceStart, _Digits);
   cells[base + 8]  = DoubleToString(tr.priceEnd, _Digits);
   cells[base + 9]  = DoubleToString(tr.priceDiff, _Digits);
   cells[base + 10] = DoubleToString(tr.profit, 2);
   cells[base + 11] = FalgoSanitizeCsvCell(EnumToString((ENUM_DEAL_TYPE)tr.type));
   int planNum = 0, levelNum = 0;
   FalgoPlanAndLevelTradeNumsFromMagic(tr.magic, planNum, levelNum);
   cells[base + 12] = FalgoSanitizeCsvCell(tr.level);
   FalgoClosedTradeTelemetrySummary telSummary;
   const bool hasTel = FalgoGetTelemetrySummaryForTrade(tr.magic, tr.startTime, telSummary);
   FalgoTradeLegacyContextCols legacyCtx;
   FalgoFillTradeLegacyContextCols(tr, legacyCtx);
   if(hasTel)
   {
      cells[base + 13] = DoubleToString(telSummary.mfePts, 1);
      cells[base + 14] = DoubleToString(telSummary.maePts, 1);
      cells[base + 15] = DoubleToString(telSummary.maeFirstWindowPts, 1);
      cells[base + 18] = FalgoSanitizeCsvCell(telSummary.closeDecision);
      cells[base + 19] = FalgoSanitizeCsvCell(telSummary.closeDetail);
      cells[base + 28] = DoubleToString(telSummary.greenRatioAtClose, 4);
      cells[base + 29] = DoubleToString(telSummary.avgProfitVelocity, 3);
      cells[base + 30] = IntegerToString(telSummary.secondsGreen);
      cells[base + 31] = IntegerToString(telSummary.secondsRed);
   }
   else
   {
      cells[base + 13] = "";
      cells[base + 14] = "";
      cells[base + 15] = "";
      cells[base + 18] = "";
      cells[base + 19] = "";
      cells[base + 28] = "";
      cells[base + 29] = "";
      cells[base + 30] = "";
      cells[base + 31] = "";
   }
   cells[base + 16] = FalgoSanitizeCsvCell(legacyCtx.mfeCandle);
   cells[base + 17] = FalgoSanitizeCsvCell(legacyCtx.maeCandle);
   cells[base + 20] = FalgoSanitizeCsvCell(EnumToString((ENUM_DEAL_REASON)tr.reason));
   cells[base + 21] = (string)tr.volume;
   cells[base + 22] = FalgoSanitizeCsvCell(tr.bothComments);
   cells[base + 23] = IntegerToString(planNum);
   cells[base + 24] = IntegerToString(levelNum);
   cells[base + 25] = FalgoOffsetPriceUnitsStrForTrade(tr);
   cells[base + 26] = FalgoSanitizeCsvCell(tr.tp);
   cells[base + 27] = FalgoSanitizeCsvCell(tr.sl);
   cells[base + 32] = FalgoSanitizeCsvCell(legacyCtx.breakevenC);
   cells[base + 33] = FalgoSanitizeCsvCell(legacyCtx.gapFillPc);
   cells[base + 34] = FalgoSanitizeCsvCell(legacyCtx.openGapInfo);
   cells[base + 35] = FalgoSanitizeCsvCell(legacyCtx.pdTrend);
   cells[base + 36] = FalgoSanitizeCsvCell(legacyCtx.dayBrokePDH);
   cells[base + 37] = FalgoSanitizeCsvCell(legacyCtx.dayBrokePDL);
   cells[base + 38] = FalgoSanitizeCsvCell(legacyCtx.refAbove);
   cells[base + 39] = FalgoSanitizeCsvCell(legacyCtx.refBelow);
   int secretTpPct = 0, closeAfterMin = 0;
   BreakdownAllDaysAlgoConfigForMagic(tr.magic, secretTpPct, closeAfterMin);
   cells[base + 40] = IntegerToString(secretTpPct);
   cells[base + 41] = IntegerToString(closeAfterMin);
}

//+------------------------------------------------------------------+
bool FalgoAllDaysRowsContainTrade(const string &cells[], const int rowCount, const long magic, const datetime startTime,
   const int colCount)
{
   const string magicStr = IntegerToString(magic);
   const string startStr = TimeToString(startTime, TIME_DATE|TIME_SECONDS);
   for(int ri = 0; ri < rowCount; ri++)
   {
      const int base = ri * colCount;
      if(cells[base + 6] == magicStr && cells[base + 3] == startStr)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Reorder all-days flat cell rows by startTime column ascending (family summary only). |
//+------------------------------------------------------------------+
void FalgoSortAllDaysCellRowsByStartTimeAsc(string &cells[], const int rowCount, const int colCount)
{
   if(rowCount <= 1)
      return;
   int indices[];
   ArrayResize(indices, rowCount);
   for(int i = 0; i < rowCount; i++)
      indices[i] = i;

   int tmp[];
   ArrayResize(tmp, rowCount);
   int w = 1;
   while(w < rowCount)
   {
      for(int i0 = 0; i0 < rowCount; i0 += 2 * w)
      {
         int m = MathMin(i0 + w, rowCount);
         int i1 = MathMin(i0 + 2 * w, rowCount);
         int p = i0, q = m, o = i0;
         while(p < m && q < i1)
         {
            const datetime tP = StringToTime(cells[indices[p] * colCount + 3]);
            const datetime tQ = StringToTime(cells[indices[q] * colCount + 3]);
            if(tP <= tQ)
               tmp[o++] = indices[p++];
            else
               tmp[o++] = indices[q++];
         }
         while(p < m)
            tmp[o++] = indices[p++];
         while(q < i1)
            tmp[o++] = indices[q++];
      }
      ArrayCopy(indices, tmp, 0, 0, rowCount);
      w *= 2;
   }

   string sorted[];
   ArrayResize(sorted, rowCount * colCount);
   for(int ri = 0; ri < rowCount; ri++)
   {
      const int srcBase = indices[ri] * colCount;
      const int dstBase = ri * colCount;
      for(int c = 0; c < colCount; c++)
         sorted[dstBase + c] = cells[srcBase + c];
   }
   ArrayCopy(cells, sorted);
}

//+------------------------------------------------------------------+
//| EOD: per-day algoN CSV (rewrite) + all-days TSV (read/merge/append today's rows for that algo only). |
//+------------------------------------------------------------------+
void WriteAlgoEodTradeResultsCsvsIfNeeded(const string dateStr, const int algoSlot1, const int algoOutCount)
{
   if(algoOutCount <= 0)
      return;

   const bool writeDailyCsv = AlgoEodTradeResultsLoggingEnabled(algoSlot1);
   const bool writeAllDaysPerAlgo = AlgoEodTradeResultsAllDaysPerAlgoLoggingEnabled(algoSlot1);
   if(!writeDailyCsv && !writeAllDaysPerAlgo)
      return;

   if(writeDailyCsv)
   {
   const string csvName = FalgoEodTradeResultsDailyCsvName(dateStr, algoSlot1);
   int fhDay = FileOpen(csvName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_CSV | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fhDay != INVALID_HANDLE)
   {
      FileWrite(fhDay, "symbol", "sentTime", "startTime", "endTime", "sessionSent", "magic", "priceStart", "priceEnd", "priceDiff", "profit", "type",
         "level", "levelTag", "levelSlot",
         "MFE", "MAE", FalgoTradeResultMaeFirstCsvColumnName(), "mfeCandle", "maeCandle", "close_decision", "close_detail",
         "reason", "volume", "bothComments", "planTradeNumToday", "levelTradeNumToday", "offset", "tp", "sl",
         "greenRatio_at_close", AlgoGatesColAvgProfitVelocity(algoSlot1), "secondsGreen", "secondsRed",
         "3c_30c_level_breakevenC", "gapFillPc_at_tradeOpenTime", "openGap_info", "PD_trend", "dayBrokePDH", "dayBrokePDL",
         "referencePointsAbove", "referencePointsBelow", "levelCats",
         "wCeilingC", "dCeilingC", "wBounceC", "dBounceC");
      for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
      {
         TradeResult tr = g_tradeResults[trIdx];
         if(!tr.foundOut || !IsAlgoCompositeMagic(tr.magic, algoSlot1))
            continue;
         int planNum = 0, levelNum = 0;
         FalgoPlanAndLevelTradeNumsFromMagic(tr.magic, planNum, levelNum);
         FalgoClosedTradeTelemetrySummary telSummary;
         const bool hasTel = FalgoGetTelemetrySummaryForTrade(tr.magic, tr.startTime, telSummary);
         FalgoTradeLegacyContextCols legacyCtx;
         FalgoFillTradeLegacyContextCols(tr, legacyCtx);
         int wBounceC = 0, dBounceC = 0, wCeilingC = 0, dCeilingC = 0;
         FalgoFillTradeBounceCeilingCountsAtStart(tr, wBounceC, dBounceC, wCeilingC, dCeilingC);
         FileWrite(fhDay, tr.symbol,
            TimeToString(tr.sentTime, TIME_DATE|TIME_SECONDS),
            TimeToString(tr.startTime, TIME_DATE|TIME_SECONDS),
            TimeToString(tr.endTime, TIME_DATE|TIME_SECONDS),
            tr.sessionSent,
            IntegerToString((long)tr.magic),
            DoubleToString(tr.priceStart, _Digits),
            DoubleToString(tr.priceEnd, _Digits),
            DoubleToString(tr.priceDiff, _Digits),
            DoubleToString(tr.profit, 2),
            EnumToString((ENUM_DEAL_TYPE)tr.type),
            tr.level, FalgoLevelTagUneditedForTradeResult(tr), FalgoLevelSlotStrForMagic(tr.magic),
            (hasTel ? DoubleToString(telSummary.mfePts, 1) : ""),
            (hasTel ? DoubleToString(telSummary.maePts, 1) : ""),
            (hasTel ? DoubleToString(telSummary.maeFirstWindowPts, 1) : ""),
            legacyCtx.mfeCandle, legacyCtx.maeCandle,
            (hasTel ? FalgoSanitizeCsvCell(telSummary.closeDecision) : ""),
            (hasTel ? FalgoSanitizeCsvCell(telSummary.closeDetail) : ""),
            EnumToString((ENUM_DEAL_REASON)tr.reason),
            tr.volume, tr.bothComments,
            IntegerToString(planNum), IntegerToString(levelNum),
            FalgoOffsetPriceUnitsStrForTrade(tr), FalgoSanitizeCsvCell(tr.tp), FalgoSanitizeCsvCell(tr.sl),
            (hasTel ? DoubleToString(telSummary.greenRatioAtClose, 4) : ""),
            (hasTel ? DoubleToString(telSummary.avgProfitVelocity, 3) : ""),
            (hasTel ? IntegerToString(telSummary.secondsGreen) : ""),
            (hasTel ? IntegerToString(telSummary.secondsRed) : ""),
            legacyCtx.breakevenC,
            legacyCtx.gapFillPc, legacyCtx.openGapInfo, legacyCtx.pdTrend,
            legacyCtx.dayBrokePDH, legacyCtx.dayBrokePDL,
            legacyCtx.refAbove, legacyCtx.refBelow, legacyCtx.levelCats,
            IntegerToString(wCeilingC), IntegerToString(dCeilingC),
            IntegerToString(wBounceC), IntegerToString(dBounceC));
      }
      FileClose(fhDay);
   }
   }

   if(!writeAllDaysPerAlgo)
      return;

   const string summaryAllName = FalgoAllDaysSummaryFileNameForAlgo(algoSlot1);
   string headerParts[];
   const int schemaCols = StringSplit(FalgoAllDaysTradeResultsHeader(), ',', headerParts);
   if(schemaCols != FALGO_ALLDAYS_COLS)
      FatalError(StringFormat("WriteAlgoEodTradeResultsCsvsIfNeeded: schemaCols %d != FALGO_ALLDAYS_COLS %d", schemaCols, FALGO_ALLDAYS_COLS));

   string allDaysCells[];
   int existingRowCount = 0;
   FalgoReadAllDaysTradeResultsFromFile(summaryAllName, allDaysCells, existingRowCount, FALGO_ALLDAYS_COLS);

   for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
   {
      TradeResult tr = g_tradeResults[trIdx];
      if(!tr.foundOut || !IsAlgoCompositeMagic(tr.magic, algoSlot1))
         continue;
      if(FalgoAllDaysRowsContainTrade(allDaysCells, existingRowCount, tr.magic, tr.startTime, FALGO_ALLDAYS_COLS))
         continue;
      FalgoAppendTradeResultCells(allDaysCells, dateStr, tr);
      existingRowCount++;
   }

   FalgoSortAllDaysCellRowsByStartTimeAsc(allDaysCells, existingRowCount, FALGO_ALLDAYS_COLS);
   FalgoWriteAllDaysTradeResultsToFile(summaryAllName, allDaysCells, existingRowCount,
      FalgoAllDaysTradeResultsHeader(), FALGO_ALLDAYS_COLS);
}

//+------------------------------------------------------------------+
//| EOD: all-days TSV across level-family algos — read/merge/append today's level rows only. |
//+------------------------------------------------------------------+
void WriteAlgoFamilyAllDaysTradeResultsSummaryIfNeeded(const string dateStr)
{
   if(!AlgoFamilyEodTradeResultsAllDaysLoggingEnabled())
      return;

   const bool profOn = BacktestProfileEnabled();
   ulong profT0 = 0;
   if(profOn)
      profT0 = GetMicrosecondCount();

   int familyOutCount = 0;
   for(int trScan = 0; trScan < g_tradeResultsCount; trScan++)
   {
      if(!g_tradeResults[trScan].foundOut)
         continue;
      if(IsLevelFamilyCompositeMagic(g_tradeResults[trScan].magic))
         familyOutCount++;
   }
   if(familyOutCount <= 0)
   {
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_SUMMARY_TRADE_RESULTS_TSV, profT0);
      return;
   }

   const string summaryAllName = "summary_tradeResults_all_days.tsv";
   string headerParts[];
   const int schemaCols = StringSplit(FalgoAllDaysTradeResultsHeader(), ',', headerParts);
   if(schemaCols != FALGO_ALLDAYS_COLS)
      FatalError(StringFormat("WriteAlgoFamilyAllDaysTradeResultsSummaryIfNeeded: schemaCols %d != FALGO_ALLDAYS_COLS %d", schemaCols, FALGO_ALLDAYS_COLS));

   string allDaysCells[];
   int existingRowCount = 0;
   FalgoReadAllDaysTradeResultsFromFile(summaryAllName, allDaysCells, existingRowCount, FALGO_ALLDAYS_COLS);

   for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
   {
      TradeResult tr = g_tradeResults[trIdx];
      if(!tr.foundOut || !IsLevelFamilyCompositeMagic(tr.magic))
         continue;
      if(FalgoAllDaysRowsContainTrade(allDaysCells, existingRowCount, tr.magic, tr.startTime, FALGO_ALLDAYS_COLS))
         continue;
      FalgoAppendTradeResultCells(allDaysCells, dateStr, tr);
      existingRowCount++;
   }

   FalgoSortAllDaysCellRowsByStartTimeAsc(allDaysCells, existingRowCount, FALGO_ALLDAYS_COLS);
   FalgoWriteAllDaysTradeResultsToFile(summaryAllName, allDaysCells, existingRowCount,
      FalgoAllDaysTradeResultsHeader(), FALGO_ALLDAYS_COLS);
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_SUMMARY_TRADE_RESULTS_TSV, profT0);
}

//+------------------------------------------------------------------+
//| EOD: all-days TSV across breakdown-family algos. |
//+------------------------------------------------------------------+
void WriteBreakdownFamilyAllDaysTradeResultsSummaryIfNeeded(const string dateStr)
{
   if(!BreakdownFamilyEodTradeResultsAllDaysLoggingEnabled())
      return;

   const bool profOn = BacktestProfileEnabled();
   ulong profT0 = 0;
   if(profOn)
      profT0 = GetMicrosecondCount();

   int familyOutCount = 0;
   for(int trScan = 0; trScan < g_tradeResultsCount; trScan++)
   {
      if(!g_tradeResults[trScan].foundOut)
         continue;
      if(IsBreakdownFamilyCompositeMagic(g_tradeResults[trScan].magic))
         familyOutCount++;
   }
   if(familyOutCount <= 0)
   {
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_SUMMARY_TRADE_RESULTS_TSV, profT0);
      return;
   }

   const string summaryAllName = "summary_tradeResults_all_days_breakdown.tsv";
   string headerParts[];
   const int schemaCols = StringSplit(FalgoBreakdownAllDaysTradeResultsHeader(), ',', headerParts);
   if(schemaCols != FALGO_BREAKDOWN_ALLDAYS_COLS)
      FatalError(StringFormat("WriteBreakdownFamilyAllDaysTradeResultsSummaryIfNeeded: schemaCols %d != FALGO_BREAKDOWN_ALLDAYS_COLS %d", schemaCols, FALGO_BREAKDOWN_ALLDAYS_COLS));

   string allDaysCells[];
   int existingRowCount = 0;
   FalgoReadAllDaysTradeResultsFromFile(summaryAllName, allDaysCells, existingRowCount, FALGO_BREAKDOWN_ALLDAYS_COLS);

   for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
   {
      TradeResult tr = g_tradeResults[trIdx];
      if(!tr.foundOut || !IsBreakdownFamilyCompositeMagic(tr.magic))
         continue;
      if(FalgoAllDaysRowsContainTrade(allDaysCells, existingRowCount, tr.magic, tr.startTime, FALGO_BREAKDOWN_ALLDAYS_COLS))
         continue;
      FalgoAppendBreakdownTradeResultCells(allDaysCells, dateStr, tr);
      existingRowCount++;
   }

   FalgoSortAllDaysCellRowsByStartTimeAsc(allDaysCells, existingRowCount, FALGO_BREAKDOWN_ALLDAYS_COLS);
   FalgoWriteAllDaysTradeResultsToFile(summaryAllName, allDaysCells, existingRowCount,
      FalgoBreakdownAllDaysTradeResultsHeader(), FALGO_BREAKDOWN_ALLDAYS_COLS);
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_SUMMARY_TRADE_RESULTS_TSV, profT0);
}

//+------------------------------------------------------------------+
void WriteAlgoFamilyEodTradeResultsCsvsIfNeeded(const string dateStr)
{
   for(int si = 0; si < FALGO_OPEN_TELEMETRY_MAX; si++)
   {
      if(!g_falgoOpenTelemetrySlots[si].active)
         continue;
      g_falgoOpenTelemetryCtx = si;
      FalgoTelemetryPushClosedSummaryFromOpen();
      FalgoTelemetryClearOpenState();
   }
   g_falgoOpenTelemetryCtx = -1;

   for(int si = 0; si < g_breakdownAlgoCount; si++)
   {
      const int algoNumber = g_breakdownAlgos[si].algo_id;
      int algoOutCount = 0;
      for(int trScan = 0; trScan < g_tradeResultsCount; trScan++)
      {
         if(!g_tradeResults[trScan].foundOut)
            continue;
         if(IsAlgoCompositeMagic(g_tradeResults[trScan].magic, algoNumber))
            algoOutCount++;
      }
      WriteAlgoEodTradeResultsCsvsIfNeeded(dateStr, algoNumber, algoOutCount);
   }

   WriteAlgoFamilyAllDaysTradeResultsSummaryIfNeeded(dateStr);
   WriteBreakdownFamilyAllDaysTradeResultsSummaryIfNeeded(dateStr);
}

//+------------------------------------------------------------------+
bool TradeResultsEodAlreadyFlushedForDay(const datetime dayStart)
{
   return (dayStart != 0 && dayStart == g_tradeResultsEodFlushedForDayStart);
}

//+------------------------------------------------------------------+
void MarkTradeResultsEodFlushedForDay(const datetime dayStart)
{
   if(TradeResultsEodAlreadyFlushedForDay(dayStart))
      return;
   g_tradeResultsEodFlushedForDayStart = dayStart;
}

//+------------------------------------------------------------------+
bool M1SameCalendarDayExistsAfter(const datetime barTime)
{
   const string barDate = TimeToString(barTime, TIME_DATE);
   const datetime probe = barTime + 60;
   const int sh = iBarShift(_Symbol, PERIOD_M1, probe, false);
   if(sh < 0)
      return false;
   return (TimeToString(iTime(_Symbol, PERIOD_M1, sh), TIME_DATE) == barDate);
}

//+------------------------------------------------------------------+
void FlushTradeResultsForDayIfNeeded(const datetime dayStart)
{
   if(!InpEODLogging || !InpLoadTradeResultsFromHistory)
      return;
   if(TradeResultsEodAlreadyFlushedForDay(dayStart))
      return;

   const bool profOn = BacktestProfileEnabled();
   ulong profT0 = 0;
   if(profOn)
      profT0 = GetMicrosecondCount();

   const string dateStr = TimeToString(dayStart, TIME_DATE);
   UpdateTradeResultsForDayStart(dayStart);
   FalgoEnrichAllTradeResultsLevelTpSl();
   WriteAlgoFamilyEodTradeResultsCsvsIfNeeded(dateStr);
   MarkTradeResultsEodFlushedForDay(dayStart);

   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_TRADE_RESULTS_EOD_FLUSH, profT0);
}

//+------------------------------------------------------------------+
//| After UpdateDayM1: last M1 of calendar day in feed (e.g. Good Friday 15:13) with no same-day bar at +1 min. |
//+------------------------------------------------------------------+
void TryFlushTradeResultsIfLastBarOfDayInFeed()
{
   if(!InpEODLogging || !InpLoadTradeResultsFromHistory)
      return;
   if(g_barsInDay <= 0 || g_m1DayStart == 0)
      return;
   if(TradeResultsEodAlreadyFlushedForDay(g_m1DayStart))
      return;

   const datetime lastBarTime = g_m1Rates[g_barsInDay - 1].time;
   if(M1SameCalendarDayExistsAfter(lastBarTime))
      return;

   FlushTradeResultsForDayIfNeeded(g_m1DayStart);
}

//+------------------------------------------------------------------+
//| Fallback when 21:58 EOD window was missed. Day rollover flushes every skipped calendar day
//| between barClosed and barOpen (not only barClosed's day). Same-day gap > 1 min if 21:58 did not run. |
//+------------------------------------------------------------------+
void TryFlushTradeResultsEodFallback(const datetime barOpen, const datetime barClosed)
{
   if(!InpEODLogging || !InpLoadTradeResultsFromHistory)
      return;
   if(barOpen <= 0 || barClosed <= 0)
      return;

   const datetime closedDayStart = barClosed - (barClosed % 86400);
   const string dateOpen = TimeToString(barOpen, TIME_DATE);
   const string dateClosed = TimeToString(barClosed, TIME_DATE);

   if(dateOpen != dateClosed)
   {
      const datetime openDayStart = barOpen - (barOpen % 86400);
      for(datetime d = closedDayStart; d < openDayStart; d += 86400)
         FlushTradeResultsForDayIfNeeded(d);
      return;
   }

   if((barOpen - barClosed) <= 60)
      return;
   if(TradeResultsEodAlreadyFlushedForDay(closedDayStart))
      return;

   FlushTradeResultsForDayIfNeeded(closedDayStart);
}

//+------------------------------------------------------------------+
//| Algo family profile defaults (shared + wired algos 10–14). |
//+------------------------------------------------------------------+
void SyncAlgoFamilyProfileFromInputs()
{  // algobookmark1 — level DATA COLLECTION profile (bounce/ceiling/proximity); no level-family trade algos in aleksik2
   RebuildAlgoSlotsRegistry();
   RebuildFalgoCalendarOverrideDateLists();

   g_algoShared.bounce_minimum_clean_ohlc_to_qualify = 2;
   g_algoShared.ceiling_minimum_clean_ohlc_to_qualify = 2;
   g_algoShared.bounce_minimum_HighestLow_levelDiff_to_qualify = 0.9;
   g_algoShared.ceiling_minimum_LowestHigh_levelDiff_to_qualify = 0.9;
   g_algoShared.proximity_threshold = 0.3;
   g_algoShared.bounce_event_proximity_threshold = 0.6;
   g_algoShared.ceiling_event_proximity_threshold = 0.01;

   g_algoShared.tradeSizePct = 100;
   g_algoShared.bannedRanges = "21,35,23,59;0,0,1,0";
   g_algoShared.tradesDays = "12345";

   RebuildFalgoBannedRangesCache();
}
//+------------------------------------------------------------------+
//| Breakdown algo family profile (magic 200..299). |
//+------------------------------------------------------------------+
void SyncBreakdownFamilyProfileFromInputs()
{
   RebuildBreakdownAlgoSlotsRegistry();

   g_breakdownAlgoShared.babysit_enabled = true;
   g_breakdownAlgoShared.blockPlacementIfFamilyOpenOrPending = false;
   g_breakdownAlgoShared.stop_trading_if_day_has_X_wins_0_losses = 9999;
   g_breakdownAlgoShared.stop_trading_if_day_has_profit_factor_above = 9999;
   g_breakdownAlgoShared.stop_trading_today_if_AllAlgos_losing_trades_count = 999;
   g_breakdownAlgoShared.stop_trading_today_if_AllAlgos_winning_trades_count = 999;
   g_breakdownAlgoShared.tradeSizePct = 100;
   g_breakdownAlgoShared.bannedRanges = "21,35,23,59;0,0,1,0";
   g_breakdownAlgoShared.tradesDays = "12345";
   // /to do;
   //bd algo fam blockking typres: simple blocking: new bd order not allowed if any bd algo if bd algo order exists 
   // recency time blocking: neew bd order not allowed an order exists with open time closed than X minutes like 90 minutes 
   // price range blocking: new bd order not allowed if abs diff of (plannedtradeeprice - any open tradee's open price) would be less than X , like 50.0


// bdbookmark
//breakdowncreator2start
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].expiry_minutes = 15;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].min_breakdown_sequence_len = 4; // more important starts here and below:
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].max_breakdown_sequence_len = 9;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].breakdown_streak_continuation_mode = BREAKDOWN_STREAK_CONTINUATION_CLOSES;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].bd_start_min_breakdown_percent = 0.20;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].min_breakdown_total_percent = 0.40;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].after_bd_need_x_15greenc = 1;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].entry_max_minutes_after_bdend = 75; // 45
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].forget_about_latest_breakdown_after_x_15m_candles = 6;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].entryrange_range_percentspot = 60.0; // 35.0
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].secret_tp_enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].secret_tp_range_percent = 53;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].secret_tp_greenguard_pricediff_at_least = 8.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].tp_enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].tp_notsecret_range_percent = 100;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].sl_enabled = false;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].sl_points = 0.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].closetrade_after_some_time = false;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].closetrade_after_some_time_butOnlyIfProfit = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].closetrade_after_some_time_but_ProfitPercent_Needed = 2.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].closetrade_after_x_minutes_from_breakdown = 90;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].stop_trading_today_if_thisAlgo_total_trades_count = 3;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].max_trades_per_breakdown_per_day = 1;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN200)].max_open_positions = 5;


g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].expiry_minutes = 15;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].min_breakdown_sequence_len = 4; // more important starts here and below:
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].max_breakdown_sequence_len = 9;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].breakdown_streak_continuation_mode = BREAKDOWN_STREAK_CONTINUATION_OHLC_AVG;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].bd_start_min_breakdown_percent = 0.20;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].min_breakdown_total_percent = 0.40;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].after_bd_need_x_15greenc = 1;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].entry_max_minutes_after_bdend = 75; // 45
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].forget_about_latest_breakdown_after_x_15m_candles = 6;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].entryrange_range_percentspot = 60.0; // 35.0
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].secret_tp_enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].secret_tp_range_percent = 53;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].secret_tp_greenguard_pricediff_at_least = 8.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].tp_enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].tp_notsecret_range_percent = 100;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].sl_enabled = false;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].sl_points = 0.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].closetrade_after_some_time = false;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].closetrade_after_some_time_butOnlyIfProfit = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].closetrade_after_some_time_but_ProfitPercent_Needed = 2.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].closetrade_after_x_minutes_from_breakdown = 90;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].stop_trading_today_if_thisAlgo_total_trades_count = 3;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].max_trades_per_breakdown_per_day = 1;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN201)].max_open_positions = 5;


g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].expiry_minutes = 15;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].min_breakdown_sequence_len = 4; // more important starts here and below:
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].max_breakdown_sequence_len = 9;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].breakdown_streak_continuation_mode = BREAKDOWN_STREAK_CONTINUATION_LOW;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].bd_start_min_breakdown_percent = 0.20;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].min_breakdown_total_percent = 0.40;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].after_bd_need_x_15greenc = 1;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].entry_max_minutes_after_bdend = 75; // 45
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].forget_about_latest_breakdown_after_x_15m_candles = 6;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].entryrange_range_percentspot = 60.0; // 35.0
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].secret_tp_enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].secret_tp_range_percent = 53;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].secret_tp_greenguard_pricediff_at_least = 8.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].tp_enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].tp_notsecret_range_percent = 100;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].sl_enabled = false;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].sl_points = 0.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].closetrade_after_some_time = false;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].closetrade_after_some_time_butOnlyIfProfit = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].closetrade_after_some_time_but_ProfitPercent_Needed = 2.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].closetrade_after_x_minutes_from_breakdown = 90;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].stop_trading_today_if_thisAlgo_total_trades_count = 3;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].max_trades_per_breakdown_per_day = 1;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN202)].max_open_positions = 5;


g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].expiry_minutes = 15;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].min_breakdown_sequence_len = 4; // more important starts here and below:
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].max_breakdown_sequence_len = 9;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].breakdown_streak_continuation_mode = BREAKDOWN_STREAK_CONTINUATION_OC_MID;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].bd_start_min_breakdown_percent = 0.20;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].min_breakdown_total_percent = 0.40;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].after_bd_need_x_15greenc = 1;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].entry_max_minutes_after_bdend = 75; // 45
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].forget_about_latest_breakdown_after_x_15m_candles = 6;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].entryrange_range_percentspot = 60.0; // 35.0
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].secret_tp_enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].secret_tp_range_percent = 53;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].secret_tp_greenguard_pricediff_at_least = 8.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].tp_enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].tp_notsecret_range_percent = 100;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].sl_enabled = false;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].sl_points = 0.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].closetrade_after_some_time = false;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].closetrade_after_some_time_butOnlyIfProfit = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].closetrade_after_some_time_but_ProfitPercent_Needed = 2.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].closetrade_after_x_minutes_from_breakdown = 90;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].stop_trading_today_if_thisAlgo_total_trades_count = 3;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].max_trades_per_breakdown_per_day = 1;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN203)].max_open_positions = 5;


g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].expiry_minutes = 15;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].min_breakdown_sequence_len = 4; // more important starts here and below:
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].max_breakdown_sequence_len = 9;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].breakdown_streak_continuation_mode = BREAKDOWN_STREAK_CONTINUATION_HL_MID;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].bd_start_min_breakdown_percent = 0.20;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].min_breakdown_total_percent = 0.40;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].after_bd_need_x_15greenc = 1;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].entry_max_minutes_after_bdend = 75; // 45
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].forget_about_latest_breakdown_after_x_15m_candles = 6;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].entryrange_range_percentspot = 60.0; // 35.0
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].secret_tp_enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].secret_tp_range_percent = 53;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].secret_tp_greenguard_pricediff_at_least = 8.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].tp_enabled = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].tp_notsecret_range_percent = 100;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].sl_enabled = false;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].sl_points = 0.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].closetrade_after_some_time = false;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].closetrade_after_some_time_butOnlyIfProfit = true;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].closetrade_after_some_time_but_ProfitPercent_Needed = 2.0;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].closetrade_after_x_minutes_from_breakdown = 90;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].stop_trading_today_if_thisAlgo_total_trades_count = 3;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].max_trades_per_breakdown_per_day = 1;
g_breakdownAlgos[BreakdownAlgoSlotIndexByAlgoId(MAGIC_BREAKDOWN204)].max_open_positions = 5;

//breakdowncreator2end
   BreakdownRebuildAllRuleChains();
}

//+------------------------------------------------------------------+
//| OnInit: load algo family profile defaults and validate at least one algo slot is enabled. |
//+------------------------------------------------------------------+
void ValidateMagicCompositionOnInit()
{
   SyncAlgoFamilyProfileFromInputs();
   SyncBreakdownFamilyProfileFromInputs();
   if(!AlgoFamilyAnyEnabled())
      FatalError("Enable at least one algo family slot.");
}

//+------------------------------------------------------------------+
//| Index in levels[] for given level price valid at atTime, or -1 if not found. |
//+------------------------------------------------------------------+
int FindLevelIndexByPriceAndTime(double levelPrice, datetime atTime)
{
   for(int i = 0; i < ArraySize(levels); i++)
      if(levels[i].price == levelPrice && atTime >= levels[i].validFrom && atTime <= levels[i].validTo)
         return i;
   return -1;
}

//+------------------------------------------------------------------+
//| True if at least one level is loaded for today (g_levelsExpanded). |
//+------------------------------------------------------------------+
bool HasAnyLevelToday()
{
   return (g_levelsTodayCount > 0);
}

//+------------------------------------------------------------------+
//| Categories string for level from g_levelsExpanded. Returns "" if invalid. |
//+------------------------------------------------------------------+
string GetCategoriesFromExpanded(int levelIdx)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return "";
   return g_levelsExpanded[levelIdx].categories;
}

//+------------------------------------------------------------------+
//| Closest non-tertiary level to price. wantAbove: true = lowest level above price; false = highest level below price. Returns 0.0 if none. |
//+------------------------------------------------------------------+
double GetClosestNonTertiaryLevelToPrice(double price, bool wantAbove)
{
   double best = 0.0;
   double tolerance = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 1e-6);
   for(int idx = 0; idx < g_levelsTodayCount; idx++)
   {
      if(LevelIsTertiary(g_levelsExpanded[idx].categories)) continue;
      double lvl = g_levelsExpanded[idx].levelPrice;
      if(wantAbove)
         { if(lvl > price + tolerance && (best == 0.0 || lvl < best)) best = lvl; }
      else
         { if(lvl < price - tolerance && (best == 0.0 || lvl > best)) best = lvl; }
   }
   return best;
}

//+------------------------------------------------------------------+
//| Closest non-tertiary level below price. Wrapper for GetClosestNonTertiaryLevelToPrice(price, false). |
//+------------------------------------------------------------------+
double Rules_GetClosestNonTertiaryLevelBelowPrice(double price)
{
   return GetClosestNonTertiaryLevelToPrice(price, false);
}

//+------------------------------------------------------------------+
//| Closest non-tertiary level above price. Wrapper for GetClosestNonTertiaryLevelToPrice(price, true). |
//+------------------------------------------------------------------+
double Rules_GetClosestNonTertiaryLevelAbovePrice(double price)
{
   return GetClosestNonTertiaryLevelToPrice(price, true);
}

//+------------------------------------------------------------------+
//| Index in g_levelsExpanded for given level price, or -1 if not found. |
//+------------------------------------------------------------------+
int FindExpandedLevelIndexByPrice(double levelPrice)
{
   for(int idx = 0; idx < g_levelsTodayCount; idx++)
      if(g_levelsExpanded[idx].levelPrice == levelPrice)
         return idx;
   return -1;
}

//+------------------------------------------------------------------+
//| Gap day type at bar: gapUp_Day / gapDown_Day / flat_Day / unknown (before RTH open or missing PDC/RTH). |
//+------------------------------------------------------------------+
string GaplogGapDayTypeAtBar(const int barIdx, const datetime dayStart, const string &dateStr)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || dayStart == 0) return "unknown";
   const datetime rthOpenBarTime = dayStart + GetRthOpenBarOffsetSeconds(dateStr);
   if(g_m1Rates[barIdx].time < rthOpenBarTime) return "unknown";
   if(!g_todayRTHopenValid || g_staticMarketContext.PDCpreviousDayRTHClose <= 0.0) return "unknown";
   const double rthOpen = g_todayRTHopen;
   const double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
   if(rthOpen > pdc) return "gapUp_Day";
   if(rthOpen < pdc) return "gapDown_Day";
   return "flat_Day";
}

//+------------------------------------------------------------------+
//| Closest non-tertiary level above/below refPrice as price|tag|weekly|daily, or unknown. |
//+------------------------------------------------------------------+
string GaplogFormatClosestLevelCell(const double refPrice, const bool wantAbove)
{
   const double lvl = GetClosestNonTertiaryLevelToPrice(refPrice, wantAbove);
   if(lvl <= 0.0) return "unknown";
   const int levelIdx = FindExpandedLevelIndexByPrice(lvl);
   if(levelIdx < 0)
      return DoubleToString(lvl, _Digits);
   string scope = "other";
   if(LevelIsWeeklyKind(g_levelsExpanded[levelIdx].categories))
      scope = "weekly";
   else if(StringFind(g_levelsExpanded[levelIdx].categories, "daily") >= 0)
      scope = "daily";
   return DoubleToString(lvl, _Digits) + "|" + g_levelsExpanded[levelIdx].tag + "|" + scope;
}

//+------------------------------------------------------------------+
//| gapPts / (onHigh - onLow) * 100, e.g. gap 2 pts / ON range 20 pts => 10.00 |
//+------------------------------------------------------------------+
string GapAsPctOfONrangeStr(const double gapPts, const double onHigh, const double onLow)
{
   const double onRange = onHigh - onLow;
   if(onRange <= 0.0)
      return "unknown";
   return DoubleToString(100.0 * gapPts / onRange, 2);
}

//+------------------------------------------------------------------+
void GaplogWriteCsvHeader(const int fh)
{
   FileWrite(fh, "datetime", "pdclose", "rthopen", "gap_day_type", "gap_fill_pc",
      "gap_range_pts", "ON_open", "ON_low", "ON_high", "Gap_as_%_of_ONrange", "rthHigh", "rthLow",
      "max_before_gapfillAttempt_over_5",
      "closest_level_above_gap", "closest_level_below_gap");
}

//+------------------------------------------------------------------+
//| Append one gaplog row for barIdx (after UpdateGapFillSoFarAtBar and g_ONopen). Post-RTH columns unknown until RTH open known. |
//+------------------------------------------------------------------+
void GaplogAppendBarRow(const int barIdx)
{
   if(!dailyEODlog_Gaplog || barIdx < 0 || barIdx >= g_barsInDay || g_m1DayStart == 0)
      return;
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   const string fname = dateStr + "_gaplog.csv";
   int fh = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   FileSeek(fh, 0, SEEK_END);
   if(FileTell(fh) == 0)
      GaplogWriteCsvHeader(fh);

   const double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
   const string pdCloseStr = (pdc > 0.0) ? DoubleToString(pdc, _Digits) : "unknown";

   const bool rthKnown = g_todayRTHopenValid;
   const string rthOpenStr = rthKnown ? DoubleToString(g_todayRTHopen, _Digits) : "unknown";
   const string gapDayTypeStr = GaplogGapDayTypeAtBar(barIdx, g_m1DayStart, dateStr);

   string gapFillPcStr = "unknown";
   string gapRangePtsStr = "unknown";
   string onOpenStr = "unknown";
   string onLowStr = "unknown";
   string onHighStr = "unknown";
   string gapAsPctOfONrangeStr = "unknown";
   string rthHighStr = "unknown";
   string rthLowStr = "unknown";
   string maxBeforeGapfillAttemptStr = "unknown";
   string closestAboveStr = "unknown";
   string closestBelowStr = "unknown";

   if(rthKnown && pdc > 0.0)
   {
      double gapFillVal = 0.0;
      if(GetGapFillSoFarAtBar(barIdx, g_m1DayStart, dateStr, gapFillVal))
         gapFillPcStr = DoubleToString(gapFillVal, 2);

      const double rangeTop = MathMax(pdc, g_todayRTHopen);
      const double rangeBottom = MathMin(pdc, g_todayRTHopen);
      gapRangePtsStr = DoubleToString(rangeTop - rangeBottom, _Digits);

      if(g_barsInDay > 0)
         onOpenStr = DoubleToString(g_ONopen, _Digits);
      double onL = 0.0, onH = 0.0;
      if(GetONlowSoFarAtBar(barIdx, onL))
         onLowStr = DoubleToString(onL, _Digits);
      if(GetONhighSoFarAtBar(barIdx, onH))
         onHighStr = DoubleToString(onH, _Digits);
      if(GetONlowSoFarAtBar(barIdx, onL) && GetONhighSoFarAtBar(barIdx, onH))
         gapAsPctOfONrangeStr = GapAsPctOfONrangeStr(rangeTop - rangeBottom, onH, onL);
      double rthH = 0.0, rthL = 0.0;
      if(GetRthHighSoFarAtBar(barIdx, g_m1DayStart, dateStr, rthH))
         rthHighStr = DoubleToString(rthH, _Digits);
      if(GetRthLowSoFarAtBar(barIdx, g_m1DayStart, dateStr, rthL))
         rthLowStr = DoubleToString(rthL, _Digits);
      if(g_maxBeforeGapfillAttempt_over_5AtBar[barIdx].hasValue)
         maxBeforeGapfillAttemptStr = DoubleToString(g_maxBeforeGapfillAttempt_over_5AtBar[barIdx].value, _Digits);

      closestAboveStr = GaplogFormatClosestLevelCell(rangeTop, true);
      closestBelowStr = GaplogFormatClosestLevelCell(rangeBottom, false);
   }

   FileWrite(fh,
      TimeToString(g_m1Rates[barIdx].time, TIME_DATE|TIME_MINUTES),
      pdCloseStr, rthOpenStr, gapDayTypeStr, gapFillPcStr,
      gapRangePtsStr, onOpenStr, onLowStr, onHighStr, gapAsPctOfONrangeStr, rthHighStr, rthLowStr,
      maxBeforeGapfillAttemptStr, closestAboveStr, closestBelowStr);
   FileClose(fh);
}

//+------------------------------------------------------------------+
//| Look up level in g_levelsExpanded by price (tradeResult.level string). Fills outTag (e.g. dailyPivot) and outCats (e.g. daily_monday_pivot_stacked). Empty if not found. |
//+------------------------------------------------------------------+
void GetLevelTagAndCatsForTrade(const string &levelStr, string &outTag, string &outCats)
{
   outTag = "";
   outCats = "";
   if(StringLen(levelStr) == 0) return;
   double levelVal = StringToDouble(levelStr);
   double tolerance = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 1e-6);
   for(int idx = 0; idx < g_levelsTodayCount; idx++)
   {
      if(MathAbs(g_levelsExpanded[idx].levelPrice - levelVal) < tolerance)
      {
         outTag  = g_levelsExpanded[idx].tag;
         outCats = g_levelsExpanded[idx].categories;
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Level categories string (levels file column → g_levelsExpanded[].categories) for this price. Same lookup as GetLevelTagAndCatsForTrade. Empty if not found. |
//+------------------------------------------------------------------+
void GetLevelCategories(const string &levelStr, string &outCategories)
{
   outCategories = "";
   if(StringLen(levelStr) == 0) return;
   double levelVal = StringToDouble(levelStr);
   double tolerance = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 1e-6);
   for(int idx = 0; idx < g_levelsTodayCount; idx++)
   {
      if(MathAbs(g_levelsExpanded[idx].levelPrice - levelVal) < tolerance)
      {
         outCategories = g_levelsExpanded[idx].categories;
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Level tag string (levels file column → g_levelsExpanded[].tag) for this price. Same lookup as GetLevelCategories. Empty if not found. |
//+------------------------------------------------------------------+
void GetLevelTag(const string &levelStr, string &outTag)
{
   outTag = "";
   if(StringLen(levelStr) == 0) return;
   double levelVal = StringToDouble(levelStr);
   double tolerance = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 1e-6);
   for(int idx = 0; idx < g_levelsTodayCount; idx++)
   {
      if(MathAbs(g_levelsExpanded[idx].levelPrice - levelVal) < tolerance)
      {
         outTag = g_levelsExpanded[idx].tag;
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| ON session trade count so far at barIdx (g_dayProgress). Returns 0 if barIdx invalid. |
//+------------------------------------------------------------------+
int GetONtradeCount(int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_dayProgress[barIdx].ONtradeCount;
}

//+------------------------------------------------------------------+
//| ON session win rate (0..1) at barIdx (g_dayProgress). Returns 0.0 if barIdx invalid or no trades. |
//+------------------------------------------------------------------+
double GetONwinRate(int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0.0;
   return g_dayProgress[barIdx].ONwinRate;
}

//+------------------------------------------------------------------+
//| algo-family pullinghistory globals at barIdx (g_pullingHistoryAlgoFamilyWeeklyAtBar; filled after UpdateDayProgress). |
//+------------------------------------------------------------------+
int GetAlgoFamilyDayTradesCount(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].dayTradesCount;
}

double GetAlgoFamilyDayWinRate(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0.0;
   return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].dayWinRate;
}

double GetAlgoFamilyDayPointsSum(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0.0;
   return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].dayPointsSum;
}

double GetAlgoFamilyDayProfitSum(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0.0;
   return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].dayProfitSum;
}

bool GetAlgoFamilyAccOpenTradeNow(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].accOpenTradeNowBool;
}

datetime GetAlgoFamilyAccOpenTradeTime(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].accOpenTradeTime;
}

datetime GetAlgoFamilyAccLastClosedTradeTime(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyWeeklyAtBar[barIdx].accLastClosedTradeTime;
}

//+------------------------------------------------------------------+
//| True if g_liveBid is within maxDistPoints of levelPrice (raw price distance, not PointSized). |
//+------------------------------------------------------------------+
bool IsLivePriceNearLevel(double levelPrice, double maxDistPoints)
{
   return (MathAbs(g_liveBid - levelPrice) < maxDistPoints);
}

//+------------------------------------------------------------------+
//| True if categories/tags string contains "weekly".                |
//+------------------------------------------------------------------+
bool LevelIsWeekly(const string &categoriesOrTags)
{
   return (StringFind(categoriesOrTags, "weekly") >= 0);
}

//+------------------------------------------------------------------+
//| Monday 00:00 server time of the calendar week containing t.       |
//+------------------------------------------------------------------+
datetime GetWeekMondayStart(datetime t)
{
   datetime dayStart = t - (t % 86400);
   MqlDateTime mt;
   TimeToStruct(dayStart, mt);
   int daysSinceMonday = (mt.day_of_week == 0) ? 6 : (mt.day_of_week - 1);
   return dayStart - (datetime)daysSinceMonday * 86400;
}

//+------------------------------------------------------------------+
//| True if t falls on Monday (server time).                          |
//+------------------------------------------------------------------+
bool IsMondayDatetime(datetime t)
{
   MqlDateTime mt;
   TimeToStruct(t, mt);
   return (mt.day_of_week == 1);
}

//+------------------------------------------------------------------+
//| Label for dayStart weekPerspective log (weekly / daily / stacked). |
//+------------------------------------------------------------------+
string LevelKindLabelFromCategories(const string &categories)
{
   if(LevelIsStacked(categories))
      return "stacked";
   if(LevelIsWeekly(categories))
      return "weekly";
   if(LevelIsDailyKind(categories))
      return "daily";
   return "other";
}

//+------------------------------------------------------------------+
//| Fill g_algoFamilyDayStartWeekPerspective[] — today-loaded weekly+daily only (not future CSV days). |
//+------------------------------------------------------------------+
void CollectActiveLevelsForDayStartWeekPerspective(const string dateStr)
{
   g_algoFamilyDayStartWeekPerspectiveCount = 0;
   for(int levelIdx = 0; levelIdx < g_levelsTotalCount && g_algoFamilyDayStartWeekPerspectiveCount < MAX_ALGOFAMILY_DAYSTART_WEEK_LEVELS; levelIdx++)
   {
      if(!AlgoFamilyLevelShouldTrackForDayStatsLocal(g_levels[levelIdx].categories))
         continue;
      if(g_levels[levelIdx].startStr > dateStr || dateStr > g_levels[levelIdx].endStr)
         continue;
      int rowIdx = g_algoFamilyDayStartWeekPerspectiveCount++;
      g_algoFamilyDayStartWeekPerspective[rowIdx].levelPrice = g_levels[levelIdx].levelPrice;
      g_algoFamilyDayStartWeekPerspective[rowIdx].tag = g_levels[levelIdx].tag;
      g_algoFamilyDayStartWeekPerspective[rowIdx].categories = g_levels[levelIdx].categories;
      g_algoFamilyDayStartWeekPerspective[rowIdx].levelKind = LevelKindLabelFromCategories(g_levels[levelIdx].categories);
      g_algoFamilyDayStartWeekPerspective[rowIdx].levelActiveFrom = g_levels[levelIdx].startStr;
      g_algoFamilyDayStartWeekPerspective[rowIdx].levelActiveTo = g_levels[levelIdx].endStr;
      g_algoFamilyDayStartWeekPerspective[rowIdx].maxPriceAbove = 0.0;
      g_algoFamilyDayStartWeekPerspective[rowIdx].maxPriceBelow = 0.0;
      g_algoFamilyDayStartWeekPerspective[rowIdx].brokenBool = false;
      g_algoFamilyDayStartWeekPerspective[rowIdx].countONO_too_close_10p = 0;
      g_algoFamilyDayStartWeekPerspective[rowIdx].contact1m_earlierThisWeek_physicalContactCount = 0;
      g_algoFamilyDayStartWeekPerspective[rowIdx].contact1m_earlierThisWeek_contactAndProximityCount = 0;
      g_algoFamilyDayStartWeekPerspective[rowIdx].bounceCount = 0;
      g_algoFamilyDayStartWeekPerspective[rowIdx].ceilingCount = 0;
      g_algoFamilyDayStartWeekPerspective[rowIdx].ceilingProximityCandles = 0;
   }
}

//+------------------------------------------------------------------+
void AlgoFamilyDayStartWeekPerspectiveEvalBounceCeiling(const MqlRates &weekRates[], int barCount, datetime weekStart)
{
   for(int rowIdx = 0; rowIdx < g_algoFamilyDayStartWeekPerspectiveCount; rowIdx++)
   {
      const double lvl = g_algoFamilyDayStartWeekPerspective[rowIdx].levelPrice;
      WeeklyLevelAlgoFamilyDayState st;
      ResetWeeklyLevelAlgoFamilyDayState(st, lvl);
      for(int barIdx = 0; barIdx < barCount; barIdx++)
      {
         if(weekRates[barIdx].time < weekStart)
            continue;
         AlgoFamilyApplyBounceCeilingOnBar(st,
            weekRates[barIdx].open, weekRates[barIdx].high, weekRates[barIdx].low, weekRates[barIdx].close,
            weekRates[barIdx].time, false);
      }
      g_algoFamilyDayStartWeekPerspective[rowIdx].bounceCount = st.bounceCount_today;
      g_algoFamilyDayStartWeekPerspective[rowIdx].ceilingCount = st.ceilingCount_today;
      g_algoFamilyDayStartWeekPerspective[rowIdx].ceilingProximityCandles = st.ceilingProximityCandles_today;
   }
}

//+------------------------------------------------------------------+
//| Scan current-week M1 for one level; update g_algoFamilyDayStartWeekPerspective[rowIdx]. |
//+------------------------------------------------------------------+
void AlgoFamilyDayStartWeekPerspectiveAccumulateLevel(int rowIdx, const MqlRates &weekRates[], int barCount,
   datetime weekStart, datetime todayDayStart)
{
   if(rowIdx < 0 || rowIdx >= g_algoFamilyDayStartWeekPerspectiveCount) return;
   double lvl = g_algoFamilyDayStartWeekPerspective[rowIdx].levelPrice;
   for(int barIdx = 0; barIdx < barCount; barIdx++)
   {
      if(weekRates[barIdx].time < weekStart) continue;
      const double o = weekRates[barIdx].open;
      double hi = weekRates[barIdx].high;
      double lo = weekRates[barIdx].low;
      const double c = weekRates[barIdx].close;
      if(hi > lvl)
         g_algoFamilyDayStartWeekPerspective[rowIdx].maxPriceAbove = MathMax(g_algoFamilyDayStartWeekPerspective[rowIdx].maxPriceAbove, hi - lvl);
      if(lo < lvl)
         g_algoFamilyDayStartWeekPerspective[rowIdx].maxPriceBelow = MathMax(g_algoFamilyDayStartWeekPerspective[rowIdx].maxPriceBelow, lvl - lo);
      if(weekRates[barIdx].time < todayDayStart)
      {
         if(IsBarInPhysicalContactWithLevel(o, hi, lo, c, lvl))
            g_algoFamilyDayStartWeekPerspective[rowIdx].contact1m_earlierThisWeek_physicalContactCount++;
         if(IsBarInContactWithLevel(o, hi, lo, c, lvl))
            g_algoFamilyDayStartWeekPerspective[rowIdx].contact1m_earlierThisWeek_contactAndProximityCount++;
      }
   }
}

//+------------------------------------------------------------------+
//| Per calendar day in weekRates: ONO = open of first M1 bar (like g_ONopen). Count days per level where |level - ONO| < threshold. |
//+------------------------------------------------------------------+
void AlgoFamilyDayStartWeekPerspectiveEvalONOtooClose(const MqlRates &weekRates[], int barCount, datetime weekStart)
{
   datetime dayStarts[7];
   double   dayONO[7];
   int dayCount = 0;
   for(int barIdx = 0; barIdx < barCount; barIdx++)
   {
      if(weekRates[barIdx].time < weekStart) continue;
      datetime barDay = weekRates[barIdx].time - (weekRates[barIdx].time % 86400);
      bool dayKnown = false;
      for(int dayIdx = 0; dayIdx < dayCount; dayIdx++)
      {
         if(dayStarts[dayIdx] == barDay) { dayKnown = true; break; }
      }
      if(!dayKnown && dayCount < 7)
      {
         dayStarts[dayCount] = barDay;
         dayONO[dayCount] = weekRates[barIdx].open;
         dayCount++;
      }
   }
   for(int rowIdx = 0; rowIdx < g_algoFamilyDayStartWeekPerspectiveCount; rowIdx++)
   {
      double lvl = g_algoFamilyDayStartWeekPerspective[rowIdx].levelPrice;
      g_algoFamilyDayStartWeekPerspective[rowIdx].countONO_too_close_10p = 0;
      for(int dayIdx = 0; dayIdx < dayCount; dayIdx++)
      {
         if(MathAbs(lvl - dayONO[dayIdx]) < ALGO5_WEEK_ON_TOO_CLOSE_POINTS)
            g_algoFamilyDayStartWeekPerspective[rowIdx].countONO_too_close_10p++;
      }
   }
}

//+------------------------------------------------------------------+
//| brokenBool: level strictly between week min ONO and max high of non-ONO M1 bars, or between min low of non-ONO bars and max ONO. |
//+------------------------------------------------------------------+
void AlgoFamilyDayStartWeekPerspectiveEvalBrokenBool(const MqlRates &weekRates[], int barCount, datetime weekStart)
{
   double minONO = 1e300, maxONO = -1e300;
   double maxOtherHigh = -1e300, minOtherLow = 1e300;
   bool hasONO = false, hasOther = false;
   datetime prevBarDay = 0;
   for(int barIdx = 0; barIdx < barCount; barIdx++)
   {
      if(weekRates[barIdx].time < weekStart) continue;
      datetime barDay = weekRates[barIdx].time - (weekRates[barIdx].time % 86400);
      bool isONOBar = (barDay != prevBarDay);
      prevBarDay = barDay;
      if(isONOBar)
      {
         hasONO = true;
         double ono = weekRates[barIdx].open;
         if(ono < minONO) minONO = ono;
         if(ono > maxONO) maxONO = ono;
      }
      else
      {
         hasOther = true;
         if(weekRates[barIdx].high > maxOtherHigh) maxOtherHigh = weekRates[barIdx].high;
         if(weekRates[barIdx].low < minOtherLow) minOtherLow = weekRates[barIdx].low;
      }
   }
   for(int rowIdx = 0; rowIdx < g_algoFamilyDayStartWeekPerspectiveCount; rowIdx++)
   {
      double lvl = g_algoFamilyDayStartWeekPerspective[rowIdx].levelPrice;
      g_algoFamilyDayStartWeekPerspective[rowIdx].brokenBool = false;
      if(!hasONO || !hasOther) continue;
      if(minONO < lvl && lvl < maxOtherHigh)
         g_algoFamilyDayStartWeekPerspective[rowIdx].brokenBool = true;
      if(minOtherLow < lvl && lvl < maxONO)
         g_algoFamilyDayStartWeekPerspective[rowIdx].brokenBool = true;
   }
}

//+------------------------------------------------------------------+
//| Sort g_algoFamilyDayStartWeekPerspective[] by levelPrice descending (highest first). |
//+------------------------------------------------------------------+
void AlgoFamilyDayStartWeekPerspectiveSortByLevelPriceDesc()
{
   for(int sortIdx = 0; sortIdx < g_algoFamilyDayStartWeekPerspectiveCount - 1; sortIdx++)
      for(int innerIdx = sortIdx + 1; innerIdx < g_algoFamilyDayStartWeekPerspectiveCount; innerIdx++)
         if(g_algoFamilyDayStartWeekPerspective[innerIdx].levelPrice > g_algoFamilyDayStartWeekPerspective[sortIdx].levelPrice)
         {
            AlgoFamilyDayStartWeekPerspectiveRow swapTmp = g_algoFamilyDayStartWeekPerspective[sortIdx];
            g_algoFamilyDayStartWeekPerspective[sortIdx] = g_algoFamilyDayStartWeekPerspective[innerIdx];
            g_algoFamilyDayStartWeekPerspective[innerIdx] = swapTmp;
         }
}

//+------------------------------------------------------------------+
//| Write (date)_algofamily_dayStart_weekPerspective.csv (day-start snapshot; not updated intraday). |
//+------------------------------------------------------------------+
void WriteAlgoFamilyDayStartWeekPerspectiveLog(const string dateStr, datetime weekMondayStart)
{
   if(!dailyLog_algoFamilyDayStartWeekPerspective) return;
   AlgoFamilyDayStartWeekPerspectiveSortByLevelPriceDesc();
   string logName = dateStr + "_algofamily_dayStart_weekPerspective.csv";
   int fileHandle = FileOpen(logName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandle == INVALID_HANDLE)
   {
      Print("WriteAlgoFamilyDayStartWeekPerspectiveLog: could not open ", logName);
      return;
   }
   const string colEarlierProx = FalgoLogCol_contactAndProximityCount("contact1m_earlierThisWeek_");
   FileWrite(fileHandle, "date", "weekMondayStart", "levelPrice", "tag", "categories", "levelKind", "levelActiveFrom", "levelActiveTo",
             "maxPriceAbove", "maxPriceBelow", "brokenBool", "countONO_too_close_10p",
             "contact1m_earlierThisWeek_physicalContactCount", colEarlierProx,
             "BounceCount", "CeilingCount", "CeilingProximityCandles");
   string weekStartStr = TimeToString(weekMondayStart, TIME_DATE);
   for(int rowIdx = 0; rowIdx < g_algoFamilyDayStartWeekPerspectiveCount; rowIdx++)
   {
      FileWrite(fileHandle, dateStr, weekStartStr,
                DoubleToString(g_algoFamilyDayStartWeekPerspective[rowIdx].levelPrice, _Digits),
                g_algoFamilyDayStartWeekPerspective[rowIdx].tag,
                g_algoFamilyDayStartWeekPerspective[rowIdx].categories,
                g_algoFamilyDayStartWeekPerspective[rowIdx].levelKind,
                g_algoFamilyDayStartWeekPerspective[rowIdx].levelActiveFrom,
                g_algoFamilyDayStartWeekPerspective[rowIdx].levelActiveTo,
                DoubleToString(g_algoFamilyDayStartWeekPerspective[rowIdx].maxPriceAbove, _Digits),
                DoubleToString(g_algoFamilyDayStartWeekPerspective[rowIdx].maxPriceBelow, _Digits),
                (g_algoFamilyDayStartWeekPerspective[rowIdx].brokenBool ? "true" : "false"),
                IntegerToString(g_algoFamilyDayStartWeekPerspective[rowIdx].countONO_too_close_10p),
                IntegerToString(g_algoFamilyDayStartWeekPerspective[rowIdx].contact1m_earlierThisWeek_physicalContactCount),
                IntegerToString(g_algoFamilyDayStartWeekPerspective[rowIdx].contact1m_earlierThisWeek_contactAndProximityCount),
                IntegerToString(g_algoFamilyDayStartWeekPerspective[rowIdx].bounceCount),
                IntegerToString(g_algoFamilyDayStartWeekPerspective[rowIdx].ceilingCount),
                IntegerToString(g_algoFamilyDayStartWeekPerspective[rowIdx].ceilingProximityCandles));
   }
   FileClose(fileHandle);
}

//+------------------------------------------------------------------+
//| Rebuild algofamily_dayStart_weekPerspective at day start only (OnInit + each new day). |
//+------------------------------------------------------------------+
void RefreshAlgoFamilyDayStartWeekPerspective(datetime refTime)
{
   if(refTime == 0)
      refTime = TimeCurrent();
   datetime dayStart = refTime - (refTime % 86400);
   string dateStr = TimeToString(dayStart, TIME_DATE);
   if(dateStr == g_algoFamilyDayStartWeekPerspectiveEvaluatedForDate)
      return;

   CollectActiveLevelsForDayStartWeekPerspective(dateStr);
   datetime weekMondayStart = GetWeekMondayStart(refTime);

   if(g_algoFamilyDayStartWeekPerspectiveCount > 0)
   {
      MqlRates weekRates[];
      int copiedM1 = CopyRates(_Symbol, PERIOD_M1, weekMondayStart, refTime, weekRates);
      if(copiedM1 > 0)
      {
         for(int rowIdx = 0; rowIdx < g_algoFamilyDayStartWeekPerspectiveCount; rowIdx++)
            AlgoFamilyDayStartWeekPerspectiveAccumulateLevel(rowIdx, weekRates, copiedM1, weekMondayStart, dayStart);
         AlgoFamilyDayStartWeekPerspectiveEvalONOtooClose(weekRates, copiedM1, weekMondayStart);
         AlgoFamilyDayStartWeekPerspectiveEvalBrokenBool(weekRates, copiedM1, weekMondayStart);
         AlgoFamilyDayStartWeekPerspectiveEvalBounceCeiling(weekRates, copiedM1, weekMondayStart);
      }
      else
         Print("RefreshAlgoFamilyDayStartWeekPerspective: M1 CopyRates returned ", copiedM1,
               " for week starting ", TimeToString(weekMondayStart, TIME_DATE));
   }

   WriteAlgoFamilyDayStartWeekPerspectiveLog(dateStr, weekMondayStart);
   g_algoFamilyDayStartWeekPerspectiveEvaluatedForDate = dateStr;
}

//+------------------------------------------------------------------+
//| g_levelsExpanded[levelIdx].tag only; levelIdx must be stage-1 row (no price re-match, no other fallback). |
//| outSimple is "weeklypivot" | "weeklydown" | "weeklyup" or "". Lowercase tag; order pivot → down → up so weeklydown before weeklyup. |
//+------------------------------------------------------------------+
void GetLevelTagWeeklySimplified(const int levelIdx, string &outSimple)
{
   outSimple = "";
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return;
   string t = g_levelsExpanded[levelIdx].tag;
   StringToLower(t);
   if(StringFind(t, "weekly") < 0) return;
   if(StringFind(t, "pivot") >= 0)
   {
      outSimple = "weeklypivot";
      return;
   }
   if(StringFind(t, "weeklydown") >= 0 || StringFind(t, "weekly_down") >= 0)
   {
      outSimple = "weeklydown";
      return;
   }
   if(StringFind(t, "weeklyup") >= 0 || StringFind(t, "weekly_up") >= 0)
   {
      outSimple = "weeklyup";
      return;
   }
}

//+------------------------------------------------------------------+
//| g_levelsExpanded[levelIdx].tag only; levelIdx must be stage-1 row (no price re-match, no other fallback). |
//| outSimple is "pivot" | "down" | "up" or "". Lowercase tag; order pivot → down → up (so weeklydown before weeklyup). |
//| Daily + weekly: dailyPivot/weeklyPivot, dailyDown*/weeklyDown*, dailyUp*/weeklyUp* (+ *_down / *_up spellings). |
//+------------------------------------------------------------------+
void GetLevelTagSimplified(const int levelIdx, string &outSimple)
{
   outSimple = "";
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return;
   string t = g_levelsExpanded[levelIdx].tag;
   StringToLower(t);
   if(StringFind(t, "pivot") >= 0)
   {
      outSimple = "pivot";
      return;
   }
   if(StringFind(t, "weeklydown") >= 0 || StringFind(t, "weekly_down") >= 0 ||
      StringFind(t, "dailydown") >= 0 || StringFind(t, "daily_down") >= 0)
   {
      outSimple = "down";
      return;
   }
   if(StringFind(t, "weeklyup") >= 0 || StringFind(t, "weekly_up") >= 0 ||
      StringFind(t, "dailyup") >= 0 || StringFind(t, "daily_up") >= 0)
   {
      outSimple = "up";
      return;
   }
}

//+------------------------------------------------------------------+
//| True if categories string contains "tertiary" (e.g. daily_tertiary_todayRTHopen). |
//+------------------------------------------------------------------+
bool LevelIsTertiary(const string &categories)
{
   return (StringFind(categories, "tertiary") >= 0);
}

//+------------------------------------------------------------------+
bool LevelIsTodayRthOpenTertiary(const string &categories)
{
   if(!LevelIsTertiary(categories))
      return false;
   return (StringFind(categories, "todayRTHopen") >= 0);
}

//+------------------------------------------------------------------+
bool LevelIsPDrthCloseTertiary(const string &categories)
{
   if(!LevelIsTertiary(categories))
      return false;
   return (StringFind(categories, "PDrthClose") >= 0);
}

//+------------------------------------------------------------------+
bool AlgoTradesTertiaryTodayRTHOLevel(const int algoNumber)
{
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   return g_algos[idx].tradesTertiaryTodayRTHOLevel;
}

//+------------------------------------------------------------------+
int FalgoTodayRthOpenTertiaryExpandedIdx(const int barIdx)
{
   if(!g_todayRTHopenValid || barIdx < 0 || barIdx >= g_barsInDay || g_m1DayStart == 0)
      return -1;
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   const datetime rthOpenBarTime = g_m1DayStart + GetRthOpenBarOffsetSeconds(dateStr);
   if(g_m1Rates[barIdx].time < rthOpenBarTime)
      return -1;
   const double tol = FalgoTodayRthOpenPriceMatchTolerance();
   int tagMatchIdx = -1;
   for(int levelIdx = 0; levelIdx < g_levelsTodayCount; levelIdx++)
   {
      if(g_levelsExpanded[levelIdx].tag != "todayRTHopen")
         continue;
      if(!LevelIsTertiary(g_levelsExpanded[levelIdx].categories))
         continue;
      if(MathAbs(g_levelsExpanded[levelIdx].levelPrice - g_todayRTHopen) <= tol)
         return levelIdx;
      if(tagMatchIdx < 0)
         tagMatchIdx = levelIdx;
   }
   return tagMatchIdx;
}

//+------------------------------------------------------------------+
//| keyLower must already be lowercased. outDayOfWeek = MqlDateTime.day_of_week (0=Sunday..6=Saturday). |
//+------------------------------------------------------------------+
bool LevelData_Categories_have_LevelCats(const string &keyLower, int &outDayOfWeek)
{
   if(keyLower == "sunday")    { outDayOfWeek = 0; return true; }
   if(keyLower == "monday")    { outDayOfWeek = 1; return true; }
   if(keyLower == "tuesday")   { outDayOfWeek = 2; return true; }
   if(keyLower == "wednesday") { outDayOfWeek = 3; return true; }
   if(keyLower == "thursday")  { outDayOfWeek = 4; return true; }
   if(keyLower == "friday")    { outDayOfWeek = 5; return true; }
   if(keyLower == "saturday")  { outDayOfWeek = 6; return true; }
   return false;
}

//+------------------------------------------------------------------+
//| True if categories contains any needle substring (case-insensitive). Empty categories → false. |
//| Needle is one of monday..sunday: require substring in categories AND that weekday equals the |
//| simulated calendar day from g_lastTimer1Time (set in OnTimer 1s; Strategy Tester time), or |
//| TimeCurrent() if the timer has not run yet (g_lastTimer1Time == 0). |
//| Other needles (pivot, weekly, stacked, …): substring only, unchanged. |
//+------------------------------------------------------------------+
bool Gate_LevelData_Categories_have_LevelCats(const string &needles[], const string &categories)
{
   if(StringLen(categories) == 0) return false;
   string s = categories;
   StringToLower(s);
   datetime ctx = g_lastTimer1Time;
   if(ctx == 0)
      ctx = TimeCurrent();
   MqlDateTime cal;
   TimeToStruct(ctx, cal);
   const int simulatedDayOfWeek = cal.day_of_week;
   const int n = ArraySize(needles);
   for(int i = 0; i < n; i++)
   {
      if(StringLen(needles[i]) == 0) continue;
      string key = needles[i];
      StringToLower(key);
      if(StringFind(s, key) < 0) continue;
      int needleDayOfWeek = -1;
      if(LevelData_Categories_have_LevelCats(key, needleDayOfWeek))
      {
         if(needleDayOfWeek != simulatedDayOfWeek) continue;
      }
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| True when GetLevelTagWeeklySimplified equals want (e.g. "weeklypivot" | "weeklydown" | "weeklyup"). want must match returned bucket string exactly. |
//+------------------------------------------------------------------+
bool Gate_LevelData_Weekly_TagSimplified_is(const int levelIdx, const string &want)
{
   string s;
   GetLevelTagWeeklySimplified(levelIdx, s); // result can be "weeklypivot" | "weeklydown" | "weeklyup" or ""
   return (s == want);
}

//+------------------------------------------------------------------+
//| True when GetLevelTagSimplified equals want (e.g. "down", "up" or "pivot"). want must match returned bucket string exactly. |
//+------------------------------------------------------------------+
bool Gate_LevelData_TagSimplified_is(const int levelIdx, const string &want)
{
   string s;
   GetLevelTagSimplified(levelIdx, s);
   return (s == want);
}

//+------------------------------------------------------------------+
//| True when g_levelsExpanded tag for levelPx matches wantTag (case-insensitive). |
//+------------------------------------------------------------------+
bool Gate_LevelTagIs(const double levelPx, const string wantTagLower)
{
   const int levelIdx = FindExpandedLevelIndexByPrice(levelPx);
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount)
      return false;
   string t = g_levelsExpanded[levelIdx].tag;
   StringToLower(t);
   return (t == wantTagLower);
}

//+------------------------------------------------------------------+
//| True when openGap_info at bar is unknown (before RTH open or missing PDC/RTH open). |
//+------------------------------------------------------------------+
bool Gate_OpenGapInfoIsUnknownAtBar(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || g_m1DayStart == 0)
      return false;
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   return (GaplogGapDayTypeAtBar(barIdx, g_m1DayStart, dateStr) == "unknown");
}

//+------------------------------------------------------------------+
//| For tp/sl/entry only: last two digits of whole part + fractional (6904.6→04.6). Level uses full DoubleToString in BuildUnifiedOrderComment. |
//+------------------------------------------------------------------+
string ShortPriceTailForOrderComment(const double price)
{
   double sign = (price < 0.0) ? -1.0 : 1.0;
   double ap = MathAbs(price);
   double w = MathFloor(ap + 1e-12);
   int hh = (int)MathMod(w, 100.0);
   if(hh < 0) hh += 100;
   double fr = NormalizeDouble(ap - w, _Digits);
   string fracFull = DoubleToString(fr, _Digits);
   int dotPos = StringFind(fracFull, ".");
   string fracSuffix = (dotPos >= 0) ? StringSubstr(fracFull, dotPos) : "";
   string core = StringFormat("%02d", hh) + fracSuffix;
   if(sign < 0.0) return "-" + core;
   return core;
}

//+------------------------------------------------------------------+
//| " b<n>" if variant has babysit_enabled (n = babysitStart_minute); else "". |
//+------------------------------------------------------------------+
string BabysitOrderCommentSuffixFromMagic(const long compositeMagic)
{
   return "";
}

//+------------------------------------------------------------------+
//| Unified pending comment: $ fullLevel shortTP shortSL shortEntry [b<n>]. Fails fast if longer than MT5 cap. |
//+------------------------------------------------------------------+
string BuildUnifiedOrderComment(double levelPrice, double takeProfitVal, double stopLossVal, double orderPrice, const long magicForBabysit)
{
   string levelStr = DoubleToString(NormalizeDouble(levelPrice, _Digits), _Digits);
   string s = "$" + levelStr + " " + ShortPriceTailForOrderComment(takeProfitVal) + " "
              + ShortPriceTailForOrderComment(stopLossVal) + " " + ShortPriceTailForOrderComment(orderPrice)
              + BabysitOrderCommentSuffixFromMagic(magicForBabysit);
   int n = (int)StringLen(s);
   if(n > MT5_ORDER_COMMENT_MAX_LEN)
      FatalError(StringFormat("Order comment length %d > MT5_ORDER_COMMENT_MAX_LEN %d: \"%s\" (try lower _Digits or shorter babysit tag)",
         n, MT5_ORDER_COMMENT_MAX_LEN, s));
   return s;
}

//+------------------------------------------------------------------+
//| Reusable stage-2 gates (prefix Gate_). Bounds checked inside each. |
//+------------------------------------------------------------------+
//| Gate_DayHighSoFar_AtLeastX_AboveLevel: day high so far ≥ levelPx + x (price units; x = e.g. 2.0). |
//+------------------------------------------------------------------+
bool Gate_DayHighSoFar_AtLeastX_AboveLevel(const int kLast, const double levelPx, const double x)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!g_dayHighSoFarAtBar[kLast].hasValue) return false;
   return (g_dayHighSoFarAtBar[kLast].value >= levelPx + x);
}
//+------------------------------------------------------------------+
//| Gate_DayHighSoFar_NoMoreThanX_AboveLevel:                         |
//| day high so far ≤ levelPx + x (price units; x = e.g. 2.0).        |
//+------------------------------------------------------------------+
bool Gate_DayHighSoFar_NoMoreThanX_AboveLevel(const int kLast, const double levelPx, const double x)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!g_dayHighSoFarAtBar[kLast].hasValue) return false;
   return (g_dayHighSoFarAtBar[kLast].value <= levelPx + x);
}
//+------------------------------------------------------------------+
//| Gate_DayLowSoFar_AtLeastX_BelowLevel: day low so far ≤ levelPx - x (price units; x = e.g. 2.0). |
//+------------------------------------------------------------------+
bool Gate_DayLowSoFar_AtLeastX_BelowLevel(const int kLast, const double levelPx, const double x)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!g_dayLowSoFarAtBar[kLast].hasValue) return false;
   return (g_dayLowSoFarAtBar[kLast].value <= levelPx - x);
}
//+------------------------------------------------------------------+
//| Gate_DayLowSoFar_NoMoreThanX_BelowLevel:                         |
//| day low so far ≥ levelPx - x (price units; x = e.g. 2.0).        |
//+------------------------------------------------------------------+
bool Gate_DayLowSoFar_NoMoreThanX_BelowLevel(const int kLast, const double levelPx, const double x)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!g_dayLowSoFarAtBar[kLast].hasValue) return false;
   return (g_dayLowSoFarAtBar[kLast].value >= levelPx - x);
}

//+------------------------------------------------------------------+
//| True if levelPx is strictly below the day's running high so far at kLast (not an "X points" band). |
//+------------------------------------------------------------------+
bool Gate_Level_BelowdayHighSoFar(const int kLast, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!g_dayHighSoFarAtBar[kLast].hasValue) return false;
   return (levelPx < g_dayHighSoFarAtBar[kLast].value);
}
//+------------------------------------------------------------------+
//| True if levelPx is strictly below the day's running low so far at kLast (not an "X points" band). |
//+------------------------------------------------------------------+
bool Gate_Level_BelowdayLowSoFar(const int kLast, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!g_dayLowSoFarAtBar[kLast].hasValue) return false;
   return (levelPx < g_dayLowSoFarAtBar[kLast].value);
}
//+------------------------------------------------------------------+
//| True if levelPx is strictly above the day's running high so far at kLast (not an "X points" band). |
//+------------------------------------------------------------------+
bool Gate_Level_AbovedayHighSoFar(const int kLast, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!g_dayHighSoFarAtBar[kLast].hasValue) return false;
   return (levelPx > g_dayHighSoFarAtBar[kLast].value);
}
//+------------------------------------------------------------------+
//| True if levelPx is strictly above the day's running low so far at kLast (not an "X points" band). |
//+------------------------------------------------------------------+
bool Gate_Level_AbovedayLowSoFar(const int kLast, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!g_dayLowSoFarAtBar[kLast].hasValue) return false;
   return (levelPx > g_dayLowSoFarAtBar[kLast].value);
}

//+------------------------------------------------------------------+
//| True if levelPx is strictly below RTH session high so far at kLast (same series as rthHighSoFar logs). |
//+------------------------------------------------------------------+
bool Gate_Level_BelowRTHH(const int kLast, const double levelPx)
{
   if(g_m1DayStart == 0) return false;
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   double rthHighSoFar = 0.0;
   const bool gotRthHighSoFar = GetRthHighSoFarAtBar(kLast, g_m1DayStart, dateStr, rthHighSoFar);
   if(!gotRthHighSoFar)
      return false;
   return (levelPx < rthHighSoFar);
}

//+------------------------------------------------------------------+
//| True if levelPx is strictly above RTH session high so far at kLast (same series as rthHighSoFar logs). |
//+------------------------------------------------------------------+
bool Gate_Level_AboveRTHH(const int kLast, const double levelPx)
{
   if(g_m1DayStart == 0) return false;
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   double rthHighSoFar = 0.0;
   const bool gotRthHighSoFar = GetRthHighSoFarAtBar(kLast, g_m1DayStart, dateStr, rthHighSoFar);
   if(!gotRthHighSoFar)
      return false;
   return (levelPx > rthHighSoFar);
}

//+------------------------------------------------------------------+
//| True if levelPx is strictly above RTH session low so far at kLast (same series as rthLowSoFar / "RTHL"). |
//+------------------------------------------------------------------+
bool Gate_Level_AboveRTHL(const int kLast, const double levelPx)
{
   if(g_m1DayStart == 0) return false;
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   double rthLowSoFar = 0.0;
   const bool gotRthLowSoFar = GetRthLowSoFarAtBar(kLast, g_m1DayStart, dateStr, rthLowSoFar);
   if(!gotRthLowSoFar)
      return false;
   return (levelPx > rthLowSoFar);
}

//+------------------------------------------------------------------+
//| True if levelPx is strictly below RTH session low so far at kLast (same series as rthLowSoFar / "RTHL"). |
//+------------------------------------------------------------------+
bool Gate_Level_BelowRTHL(const int kLast, const double levelPx)
{
   if(g_m1DayStart == 0) return false;
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   double rthLowSoFar = 0.0;
   const bool gotRthLowSoFar = GetRthLowSoFarAtBar(kLast, g_m1DayStart, dateStr, rthLowSoFar);
   if(!gotRthLowSoFar)
      return false;
   return (levelPx < rthLowSoFar);
}

//+------------------------------------------------------------------+
//| Gate_CandleLows_FewerThanX_BelowLevel: count of bars [0..kLast] with low < levelPx is strictly < x (x e.g. 15 ⇒ 0..14 allowed). |
//+------------------------------------------------------------------+
bool Gate_CandleLows_FewerThanX_BelowLevel(const int kLast, const double levelPx, const int x)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(x <= 0) return false;
   int countLowBelow = 0;
   for(int k = 0; k <= kLast; k++)
   {
      if(g_m1Rates[k].low < levelPx)
      {
         countLowBelow++;
         if(countLowBelow >= x)
            return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Gate_CandleLows_FewerThanX_AboveLevel: count of bars [0..kLast] with low > levelPx is strictly < x (same exclusive rule as BelowLevel). |
//+------------------------------------------------------------------+
bool Gate_CandleLows_FewerThanX_AboveLevel(const int kLast, const double levelPx, const int x)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(x <= 0) return false;
   int countLowAbove = 0;
   for(int k = 0; k <= kLast; k++)
   {
      if(g_m1Rates[k].low > levelPx)
      {
         countLowAbove++;
         if(countLowAbove >= x)
            return false;
      }
   }
   return true;
}
//+------------------------------------------------------------------+
//| Gate_CandleHighs_FewerThanX_BelowLevel: count of bars [0..kLast] with high < levelPx is strictly < x (same exclusive rule). |
//+------------------------------------------------------------------+
bool Gate_CandleHighs_FewerThanX_BelowLevel(const int kLast, const double levelPx, const int x)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(x <= 0) return false;
   int countHighBelow = 0;
   for(int k = 0; k <= kLast; k++)
   {
      if(g_m1Rates[k].high < levelPx)
      {
         countHighBelow++;
         if(countHighBelow >= x)
            return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Gate_CandleHighs_FewerThanX_AboveLevel: count of bars [0..kLast] with high > levelPx is strictly < x (same exclusive rule). |
//+------------------------------------------------------------------+
bool Gate_CandleHighs_FewerThanX_AboveLevel(const int kLast, const double levelPx, const int x)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(x <= 0) return false;
   int countHighAbove = 0;
   for(int k = 0; k <= kLast; k++)
   {
      if(g_m1Rates[k].high > levelPx)
      {
         countHighAbove++;
         if(countHighAbove >= x)
            return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Gate_CleanStreak_AtLeastX_AboveLevel: OHLC clean streak above level ≥ x bars (g_cleanStreakAbove). |
//+------------------------------------------------------------------+
bool Gate_CleanStreak_AtLeastX_AboveLevel(const int levelIdx, const int kLast, const int x)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   return (g_cleanStreakAbove[levelIdx][kLast] >= x);
}

//+------------------------------------------------------------------+
//| Gate_CleanStreak_AtLeastX_BelowLevel: OHLC clean streak below level ≥ x bars (g_cleanStreakBelow). |
//+------------------------------------------------------------------+
bool Gate_CleanStreak_AtLeastX_BelowLevel(const int levelIdx, const int kLast, const int x)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   return (g_cleanStreakBelow[levelIdx][kLast] >= x);
}
//+------------------------------------------------------------------+
//| Gate_CleanStreak_NoMoreThanX_BelowLevel:                          |
//| OHLC clean streak below level ≤ x bars (g_cleanStreakBelow).      |
//+------------------------------------------------------------------+
bool Gate_CleanStreak_NoMoreThanX_BelowLevel(const int levelIdx, const int kLast, const int x)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   return (g_cleanStreakBelow[levelIdx][kLast] <= x);
}
//+------------------------------------------------------------------+
//| Gate_CleanStreak_NoMoreThanX_AboveLevel:                          |
//| OHLC clean streak above level ≤ x bars (g_cleanStreakAbove).      |
//+------------------------------------------------------------------+
bool Gate_CleanStreak_NoMoreThanX_AboveLevel(const int levelIdx, const int kLast, const int x)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   return (g_cleanStreakAbove[levelIdx][kLast] <= x);
}
//+------------------------------------------------------------------+
//| Gate_Level_AbovePDO: level price strictly above previous day RTH open (PDO). |
//+------------------------------------------------------------------+
bool Gate_Level_AbovePDO(const double levelPx)
{
   const double pdo = g_staticMarketContext.PDOpreviousDayRTHOpen;
   if(pdo <= 0.0) return false;
   return (levelPx > pdo);
}

//+------------------------------------------------------------------+
//| Gate_Level_AbovePDH: level price strictly above previous day high (PDH). False if PDH unavailable. |
//+------------------------------------------------------------------+
bool Gate_Level_AbovePDH(const double levelPx)
{
   const double pdh = g_staticMarketContext.PDHpreviousDayHigh;
   if(pdh <= 0.0) return false;
   return (levelPx > pdh);
}

//+------------------------------------------------------------------+
//| Gate_Level_AbovePDC: level price strictly above previous day RTH close (PDC). False if PDC unavailable. |
//+------------------------------------------------------------------+
bool Gate_Level_AbovePDC(const double levelPx)
{
   const double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
   if(pdc <= 0.0) return false;
   return (levelPx > pdc);
}

//+------------------------------------------------------------------+
//| Gate_Level_AbovePDL: level price strictly above previous day low (PDL). False if PDL unavailable. |
//+------------------------------------------------------------------+
bool Gate_Level_AbovePDL(const double levelPx)
{
   const double pdl = g_staticMarketContext.PDLpreviousDayLow;
   if(pdl <= 0.0) return false;
   return (levelPx > pdl);
}

//+------------------------------------------------------------------+
//| Gate_Level_BelowPDO: level price strictly below previous day RTH open (PDO). |
//+------------------------------------------------------------------+
bool Gate_Level_BelowPDO(const double levelPx)
{
   const double pdo = g_staticMarketContext.PDOpreviousDayRTHOpen;
   if(pdo <= 0.0) return false;
   return (levelPx < pdo);
}

//+------------------------------------------------------------------+
//| Gate_Level_BelowPDH: level price strictly below previous day high (PDH). False if PDH unavailable. |
//+------------------------------------------------------------------+
bool Gate_Level_BelowPDH(const double levelPx)
{
   const double pdh = g_staticMarketContext.PDHpreviousDayHigh;
   if(pdh <= 0.0) return false;
   return (levelPx < pdh);
}

//+------------------------------------------------------------------+
//| Gate_Level_BelowPDC: level price strictly below previous day RTH close (PDC). False if PDC unavailable. |
//+------------------------------------------------------------------+
bool Gate_Level_BelowPDC(const double levelPx)
{
   const double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
   if(pdc <= 0.0) return false;
   return (levelPx < pdc);
}

//+------------------------------------------------------------------+
//| Gate_Level_BelowPDL: level price strictly below previous day low (PDL). False if PDL unavailable. |
//+------------------------------------------------------------------+
bool Gate_Level_BelowPDL(const double levelPx)
{
   const double pdl = g_staticMarketContext.PDLpreviousDayLow;
   if(pdl <= 0.0) return false;
   return (levelPx < pdl);
}

//+------------------------------------------------------------------+
//| Gate_Level_AboveIBH: in RTH, true only if levelPx > IB high at kLast; false for first hour of RTH (when IB not ready). |
//| Uses g_m1Rates[kLast].time for session (GetSessionForCandleTime: ON | RTH | sleep). |
//| If session is not RTH: always returns true (gate passes) so ON/sleep (e.g. overnight) variants are not blocked by this IB-only RTH rule. |
//+------------------------------------------------------------------+
bool Gate_Level_AboveIBH(const int kLast, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   const datetime tBar = g_m1Rates[kLast].time;
   if(GetSessionForCandleTime(tBar) != "RTH") return true;
   double ibh;
   if(!GetIBhighAtBar(kLast, ibh)) return false;
   return (levelPx > ibh);
}

//+------------------------------------------------------------------+
//| Gate_Level_AboveONH: level strictly above ON session high so far at kLast. False if no ONH yet at that bar, or level not above ONH. |
//+------------------------------------------------------------------+
bool Gate_Level_AboveONH(const int kLast, const double levelPx)
{
   double onh;
   if(!GetONhighSoFarAtBar(kLast, onh)) return false;
   return (levelPx > onh);
}

//+------------------------------------------------------------------+
//| Gate_Level_AboveIBL: in RTH, true only if levelPx > IB low at kLast; false for first hour of RTH (when IB not ready). |
//| Uses g_m1Rates[kLast].time for session (GetSessionForCandleTime: ON | RTH | sleep). |
//| If session is not RTH: always returns true (gate passes) so unrelated ON/sleep trades are not filtered by this IB rule. |
//+------------------------------------------------------------------+
bool Gate_Level_AboveIBL(const int kLast, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   const datetime tBar = g_m1Rates[kLast].time;
   if(GetSessionForCandleTime(tBar) != "RTH") return true;
   double ibl;
   if(!GetIBlowAtBar(kLast, ibl)) return false;
   return (levelPx > ibl);
}

//+------------------------------------------------------------------+
//| Gate_Level_AboveONL: level strictly above ON session low so far at kLast. False if no ONL yet at that bar, or level not above ONL. |
//+------------------------------------------------------------------+
bool Gate_Level_AboveONL(const int kLast, const double levelPx)
{
   double onl;
   if(!GetONlowSoFarAtBar(kLast, onl)) return false;
   return (levelPx > onl);
}

//+------------------------------------------------------------------+
//| Gate_Level_BelowIBH: in RTH, true only if levelPx < IB high at kLast; false for first hour of RTH (when IB not ready). |
//| Uses g_m1Rates[kLast].time for session (GetSessionForCandleTime: ON | RTH | sleep). |
//| If session is not RTH: always returns true (gate passes) so unrelated ON/sleep trades are not filtered by this IB rule. |
//+------------------------------------------------------------------+
bool Gate_Level_BelowIBH(const int kLast, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   const datetime tBar = g_m1Rates[kLast].time;
   if(GetSessionForCandleTime(tBar) != "RTH") return true;
   double ibh;
   if(!GetIBhighAtBar(kLast, ibh)) return false;
   return (levelPx < ibh);
}

//+------------------------------------------------------------------+
//| Gate_Level_BelowONH: level strictly below ON session high so far at kLast. False if no ONH yet at that bar, or level not below ONH. |
//+------------------------------------------------------------------+
bool Gate_Level_BelowONH(const int kLast, const double levelPx)
{
   double onh;
   if(!GetONhighSoFarAtBar(kLast, onh)) return false;
   return (levelPx < onh);
}

//+------------------------------------------------------------------+
//| Gate_Level_BelowIBL: in RTH, true only if levelPx < IB low at kLast; false for first hour of RTH (when IB not ready). |
//| Uses g_m1Rates[kLast].time for session (GetSessionForCandleTime: ON | RTH | sleep). |
//| If session is not RTH: always returns true (gate passes) so unrelated ON/sleep trades are not filtered by this IB rule. |
//+------------------------------------------------------------------+
bool Gate_Level_BelowIBL(const int kLast, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   const datetime tBar = g_m1Rates[kLast].time;
   if(GetSessionForCandleTime(tBar) != "RTH") return true;
   double ibl;
   if(!GetIBlowAtBar(kLast, ibl)) return false;
   return (levelPx < ibl);
}

//+------------------------------------------------------------------+
//| Gate_Level_BelowONL: level strictly below ON session low so far at kLast. False if no ONL yet at that bar, or level not below ONL. |
//+------------------------------------------------------------------+
bool Gate_Level_BelowONL(const int kLast, const double levelPx)
{
   double onl;
   if(!GetONlowSoFarAtBar(kLast, onl)) return false;
   return (levelPx < onl);
}

//+------------------------------------------------------------------+
//| Gate_Level_neverTouched_ceiling: no overlap bars yet and no clean-above bars so far (same idea as testinglevelsplus: overlapC 0, abovePerc 0). |
//+------------------------------------------------------------------+
bool Gate_Level_neverTouched_ceiling(const int levelIdx, const int kLast)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(g_overlapC[levelIdx][kLast] != 0) return false;
   if(g_abovePerc[levelIdx][kLast] > 0.0) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Gate_Level_neverTouched_floor: no overlap bars yet and no clean-below bars so far (overlapC 0, belowPerc 0). |
//+------------------------------------------------------------------+
bool Gate_Level_neverTouched_floor(const int levelIdx, const int kLast)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(g_overlapC[levelIdx][kLast] != 0) return false;
   if(g_belowPerc[levelIdx][kLast] > 0.0) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Gate_Level_AbsDiff_with_ONO_atLeastX
//+------------------------------------------------------------------+
bool Gate_Level_AbsDiff_with_ONO_atLeastX(const double levelPx, const double minAbsDiffPoints)
{
   if(g_barsInDay <= 0) return false;
   return (MathAbs(levelPx - g_ONopen) >= minAbsDiffPoints);
}

//+------------------------------------------------------------------+
bool Gate_ONO_AboveLevelByAtLeastX(const double levelPx, const double minDiffPoints)
{
   if(g_barsInDay <= 0) return false;
   return (g_ONopen - levelPx >= minDiffPoints);
}

//+------------------------------------------------------------------+
bool Gate_ONO_BelowLevelByAtLeastX(const double levelPx, const double minDiffPoints)
{
   if(g_barsInDay <= 0) return false;
   return (levelPx - g_ONopen >= minDiffPoints);
}

//+------------------------------------------------------------------+
bool Gate_DayStartEarlierWeekContact_NoMoreThanX(const double levelPx, const int maxAllowed)
{
   return (Falgo_DayStart_ContactAndProxC_1m_EarlierThisWeek(levelPx) <= maxAllowed);
}

//+------------------------------------------------------------------+
bool Gate_DayContactToday_NoMoreThanX(const int barIdx, const double levelPx, const int maxAllowed)
{
   return (Falgo_ContactAndProxC_Today_ForLevelAtBar(barIdx, levelPx) <= maxAllowed);
}

//+------------------------------------------------------------------+
//| Closest-weekly-level bounce/ceiling gates (reusable; not tied to a single algo). |
//+------------------------------------------------------------------+
bool Gate_BounceCount_AtLeastX(const int barIdx, const int minCount)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetBounceCountForClosestWeeklyLevel(barIdx) >= minCount);
}

bool Gate_BounceCount_NoMoreThanX(const int barIdx, const int maxAllowed)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetBounceCountForClosestWeeklyLevel(barIdx) <= maxAllowed);
}

bool Gate_RecentBounceCount_NoMoreThanX(const int barIdx, const int maxAllowed)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetRecentBounceCountForClosestWeeklyLevel(barIdx) < maxAllowed);
}

bool Gate_WeekBounceCount_NoMoreThanX(const int barIdx, const int maxAllowed)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetWeekBounceCountForClosestWeeklyLevel(barIdx) <= maxAllowed);
}

bool Gate_WeekBounceCount_AtLeastX(const int barIdx, const int minCount)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetWeekBounceCountForClosestWeeklyLevel(barIdx) >= minCount);
}

bool Gate_CeilingCount_NoMoreThanX(const int barIdx, const int maxAllowed)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetCeilingCountForClosestWeeklyLevel(barIdx) <= maxAllowed);
}

bool Gate_CeilingCount_AtLeastX(const int barIdx, const int minCount)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetCeilingCountForClosestWeeklyLevel(barIdx) >= minCount);
}

bool Gate_WeekCeilingCount_AtLeastX(const int barIdx, const int minCount)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetWeekCeilingCountForClosestWeeklyLevel(barIdx) >= minCount);
}

bool Gate_WeekContactCandles_NoMoreThanX(const int barIdx, const int maxAllowed)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetWeekContactCountForClosestWeeklyLevel(barIdx) <= maxAllowed);
}

bool Gate_WeekContactCandles_AtLeastX(const int barIdx, const int minCount)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetWeekContactCountForClosestWeeklyLevel(barIdx) >= minCount);
}

//+------------------------------------------------------------------+
bool Gate_CeilingProximityCandles_NoMoreThanX(const int barIdx, const int maxAllowed)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetCeilingProximityCandlesForClosestWeeklyLevel(barIdx) <= maxAllowed);
}

//+------------------------------------------------------------------+
bool Gate_WeekCeilingCount_NoMoreThanX(const int barIdx, const int maxAllowed)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetWeekCeilingCountForClosestWeeklyLevel(barIdx) <= maxAllowed);
}

bool Gate_TradesAtLevel_UnderDailyLimit(const int barIdx, const int algoNumber, const int maxTradesPerLevel)
{
   int levelSlot = 0;
   if(!FalgoClosestLevelMagicSlotAtBarForAlgo(algoNumber, barIdx, levelSlot))
      return true;
   if(!FalgoMagicLevelSlotIsValid(levelSlot))
      return true;
   return (FalgoTradeCountTodayAtLevelSlotForThisAlgo(algoNumber, levelSlot) < maxTradesPerLevel);
}

//+------------------------------------------------------------------+
//| analyze-style firstFail labels for gates above ("" = pass). |
//+------------------------------------------------------------------+
string GateFailLabelIntVs(const string tag, const int current, const int required)
{
   return StringFormat("%s(%d vs %d)", tag, current, required);
}

string GateFailLabelDbl1Vs(const string tag, const double current, const double required)
{
   return StringFormat("%s(%s vs %s)", tag, DoubleToString(current, 1), DoubleToString(required, 1));
}

string GateFailLabelPxVs(const string tag, const double current, const double required)
{
   return StringFormat("%s(%s vs %s)", tag, DoubleToString(current, _Digits), DoubleToString(required, _Digits));
}

string GateFail_BounceCount_TooLow(const int barIdx, const double tradeLevel, const int minCount)
{
   const int bounce = FalgoGetDayBounceCountForLevelAtBar(barIdx, tradeLevel);
   if(bounce < minCount)
      return GateFailLabelIntVs("bounceTooLow", bounce, minCount);
   return "";
}

string GateFail_BounceCount_TooHigh(const int barIdx, const double tradeLevel, const int maxAllowed)
{
   const int bounce = FalgoGetDayBounceCountForLevelAtBar(barIdx, tradeLevel);
   if(bounce > maxAllowed)
      return GateFailLabelIntVs("todayBounceCountTooHigh", bounce, maxAllowed);
   return "";
}

string GateFail_RecentBounceCount_TooHigh(const int barIdx, const double tradeLevel, const int maxAllowed)
{
   const int recent = FalgoGetRecentBounceCountForLevelAtBar(barIdx, tradeLevel);
   if(recent >= maxAllowed)
      return GateFailLabelIntVs("recentBounceTooHigh", recent, maxAllowed);
   return "";
}

string GateFail_WeekBounceCount_TooHigh(const int barIdx, const double tradeLevel, const int maxAllowed)
{
   const int wb = FalgoGetWeekBounceCountForLevelAtBar(barIdx, tradeLevel);
   if(wb > maxAllowed)
      return GateFailLabelIntVs("weeklyBounceCountTooHigh", wb, maxAllowed);
   return "";
}

string GateFail_WeekBounceCount_TooLow(const int barIdx, const double tradeLevel, const int minCount)
{
   const int wb = FalgoGetWeekBounceCountForLevelAtBar(barIdx, tradeLevel);
   if(wb < minCount)
      return GateFailLabelIntVs("weeklyBounceCountTooLow", wb, minCount);
   return "";
}

string GateFail_CeilingCount_TooHigh(const int barIdx, const double tradeLevel, const int maxAllowed, const string failLabel)
{
   const int ceiling = FalgoGetDayCeilingCountForLevelAtBar(barIdx, tradeLevel);
   if(ceiling > maxAllowed)
      return GateFailLabelIntVs(failLabel, ceiling, maxAllowed);
   return "";
}

string GateFail_CeilingCount_TooLow(const int barIdx, const double tradeLevel, const int minCount)
{
   const int ceiling = FalgoGetDayCeilingCountForLevelAtBar(barIdx, tradeLevel);
   if(ceiling < minCount)
      return GateFailLabelIntVs("ceilingTooLow", ceiling, minCount);
   return "";
}

//+------------------------------------------------------------------+
string GateFail_CeilingProximityCandles_TooHigh(const int barIdx, const double tradeLevel, const int maxAllowed, const string failLabel)
{
   const int prox = FalgoGetDayCeilingProximityCandlesForLevelAtBar(barIdx, tradeLevel);
   if(prox > maxAllowed)
      return GateFailLabelIntVs(failLabel, prox, maxAllowed);
   return "";
}

//+------------------------------------------------------------------+
string GateFail_WeekCeilingCount_TooHigh(const int barIdx, const double tradeLevel, const int maxAllowed)
{
   const int wc = FalgoGetWeekCeilingCountForLevelAtBar(barIdx, tradeLevel);
   if(wc > maxAllowed)
      return GateFailLabelIntVs("weeklyCeilingCountTooHigh", wc, maxAllowed);
   return "";
}

string GateFail_WeekCeilingCount_TooLow(const int barIdx, const double tradeLevel, const int minCount)
{
   const int wc = FalgoGetWeekCeilingCountForLevelAtBar(barIdx, tradeLevel);
   if(wc < minCount)
      return GateFailLabelIntVs("weeklyCeilingCountTooLow", wc, minCount);
   return "";
}

string GateFail_WeekContactCandles_TooHigh(const int barIdx, const double tradeLevel, const int maxAllowed)
{
   const int contact = Falgo_GetWeekContactAndProxC_ForLevelAtBar(barIdx, tradeLevel);
   if(contact > maxAllowed)
      return GateFailLabelIntVs("weeklyContactCandlesTooHigh", contact, maxAllowed);
   return "";
}

string GateFail_WeekContactCandles_TooLow(const int barIdx, const double tradeLevel, const int minCount)
{
   const int contact = Falgo_GetWeekContactAndProxC_ForLevelAtBar(barIdx, tradeLevel);
   if(contact < minCount)
      return GateFailLabelIntVs("weeklyContactCandlesTooLow", contact, minCount);
   return "";
}

string GateFail_LevelOnoAbsDiff_TooLow(const double levelPx, const double minAbsDiffPoints)
{
   if(!Gate_Level_AbsDiff_with_ONO_atLeastX(levelPx, minAbsDiffPoints))
      return GateFailLabelDbl1Vs("levelOnoAbsDiffTooLow", MathAbs(levelPx - g_ONopen), minAbsDiffPoints);
   return "";
}

string GateFail_ONO_AboveLevel_TooLow(const double levelPx, const double minDiffPoints)
{
   if(!Gate_ONO_AboveLevelByAtLeastX(levelPx, minDiffPoints))
      return GateFailLabelDbl1Vs("onoAboveLevelTooLow", g_ONopen - levelPx, minDiffPoints);
   return "";
}

string GateFail_ONO_BelowLevel_TooLow(const double levelPx, const double minDiffPoints)
{
   if(!Gate_ONO_BelowLevelByAtLeastX(levelPx, minDiffPoints))
      return GateFailLabelDbl1Vs("onoBelowLevelTooLow", levelPx - g_ONopen, minDiffPoints);
   return "";
}

string GateFail_DayStartEarlierWeekContact_TooHigh(const double levelPx, const int maxAllowed)
{
   const int contact = Falgo_DayStart_ContactAndProxC_1m_EarlierThisWeek(levelPx);
   if(contact > maxAllowed)
      return GateFailLabelIntVs("earlierWeekContactTooHigh", contact, maxAllowed);
   return "";
}

string GateFail_DayContactToday_TooHigh(const int barIdx, const double levelPx, const int maxAllowed)
{
   const int contact = Falgo_ContactAndProxC_Today_ForLevelAtBar(barIdx, levelPx);
   if(contact > maxAllowed)
      return GateFailLabelIntVs("contactAndProximityCandlesTodayTooHigh", contact, maxAllowed);
   return "";
}

string GateFail_TradesAtLevel_Limit(const int barIdx, const int algoNumber, const int maxTradesPerLevel)
{
   if(!Gate_TradesAtLevel_UnderDailyLimit(barIdx, algoNumber, maxTradesPerLevel))
   {
      int levelSlot = 0;
      if(!FalgoClosestLevelMagicSlotAtBarForAlgo(algoNumber, barIdx, levelSlot))
         return "tradesAtLevelLimit";
      return GateFailLabelIntVs("tradesAtLevelLimit",
         FalgoTradeCountTodayAtLevelSlotForThisAlgo(algoNumber, levelSlot), maxTradesPerLevel);
   }
   return "";
}

string GateFail_PD_red()
{
   if(!Gate_PD_red()) return "PD_red";
   return "";
}

string GateFail_PD_green()
{
   if(!Gate_PD_green()) return "PD_green";
   return "";
}

string GateFail_Day_DayBrokePDL(const int barIdx)
{
   if(!Gate_Day_DayBrokePDL_is_FALSE(barIdx)) return "dayBrokePDL";
   return "";
}

string GateFail_Day_DayBrokePDH(const int barIdx)
{
   if(!Gate_Day_DayBrokePDH_is_FALSE(barIdx)) return "dayBrokePDH";
   return "";
}

string GateFail_Day_GapDownRequired()
{
   if(!Gate_Day_HasGapDown()) return "notGapDownDay";
   return "";
}

string GateFail_Day_GapUpRequired()
{
   if(!Gate_Day_HasGapUp()) return "notGapUpDay";
   return "";
}

string GateFail_LevelTag(const double levelPx, const string wantTagLower)
{
   if(!Gate_LevelTagIs(levelPx, wantTagLower)) return "levelTag_" + wantTagLower;
   return "";
}

string GateFail_OpenGapInfo_Unknown(const int barIdx)
{
   if(!Gate_OpenGapInfoIsUnknownAtBar(barIdx)) return "openGapInfoNotUnknown";
   return "";
}

string GateFail_GapRangePts_Above(const double minPtsExclusive)
{
   const double rangePts = FalgoOpenGapRangePts();
   if(!Gate_GapRangePts_AboveX(minPtsExclusive))
      return GateFailLabelDbl1Vs("gapRangePtsTooLow", rangePts, minPtsExclusive);
   return "";
}

string GateFail_GapFillPc_Below(const int barIdx, const double maxPcExclusive)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || g_m1DayStart == 0)
      return "gapFillPcUnknown";
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   double pct = 0.0;
   if(!GetGapFillSoFarAtBar(barIdx, g_m1DayStart, dateStr, pct))
      return "gapFillPcUnknown";
   if(!Gate_GapFillPc_BelowX(barIdx, maxPcExclusive))
      return GateFailLabelDbl1Vs("gapFillPcTooHigh", pct, maxPcExclusive);
   return "";
}

string GateFail_RthoTertiaryLevelReady(const int barIdx)
{
   if(!Gate_RthoTertiaryLevelReadyAtBar(barIdx))
      return "rthoTertiaryNotReady";
   return "";
}

string GateFail_Level_BelowPDH(const double levelPx)
{
   if(!Gate_Level_BelowPDH(levelPx))
   {
      const double pdh = g_staticMarketContext.PDHpreviousDayHigh;
      if(pdh > 0.0)
         return GateFailLabelPxVs("belowPDH", levelPx, pdh);
      return StringFormat("belowPDH(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_AbovePDH(const double levelPx)
{
   if(!Gate_Level_AbovePDH(levelPx))
   {
      const double pdh = g_staticMarketContext.PDHpreviousDayHigh;
      if(pdh > 0.0)
         return GateFailLabelPxVs("abovePDH", levelPx, pdh);
      return StringFormat("abovePDH(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_AbovePDL(const double levelPx)
{
   if(!Gate_Level_AbovePDL(levelPx))
   {
      const double pdl = g_staticMarketContext.PDLpreviousDayLow;
      if(pdl > 0.0)
         return GateFailLabelPxVs("abovePDL", levelPx, pdl);
      return StringFormat("abovePDL(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_BelowPDL(const double levelPx)
{
   if(!Gate_Level_BelowPDL(levelPx))
   {
      const double pdl = g_staticMarketContext.PDLpreviousDayLow;
      if(pdl > 0.0)
         return GateFailLabelPxVs("belowPDL", levelPx, pdl);
      return StringFormat("belowPDL(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_BelowPDC(const double levelPx)
{
   if(!Gate_Level_BelowPDC(levelPx))
   {
      const double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
      if(pdc > 0.0)
         return GateFailLabelPxVs("belowPDC", levelPx, pdc);
      return StringFormat("belowPDC(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_BelowPDO(const double levelPx)
{
   if(!Gate_Level_BelowPDO(levelPx))
   {
      const double pdo = g_staticMarketContext.PDOpreviousDayRTHOpen;
      if(pdo > 0.0)
         return GateFailLabelPxVs("belowPDO", levelPx, pdo);
      return StringFormat("belowPDO(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_Belowmidpoint(const int barIdx, const double levelPx)
{
   if(!Gate_Level_Belowmidpoint(barIdx, levelPx))
   {
      if(g_sessionRangeMidpointAtBar[barIdx].hasValue)
         return GateFailLabelPxVs("belowMidpoint", levelPx, g_sessionRangeMidpointAtBar[barIdx].value);
      return StringFormat("belowMidpoint(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_BelowIBH(const int barIdx, const double levelPx)
{
   if(!Gate_Level_BelowIBH(barIdx, levelPx))
   {
      double ibh = 0.0;
      if(GetIBhighAtBar(barIdx, ibh))
         return GateFailLabelPxVs("belowIBH", levelPx, ibh);
      return StringFormat("belowIBH(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_BelowIBL(const int barIdx, const double levelPx)
{
   if(!Gate_Level_BelowIBL(barIdx, levelPx))
   {
      double ibl = 0.0;
      if(GetIBlowAtBar(barIdx, ibl))
         return GateFailLabelPxVs("belowIBL", levelPx, ibl);
      return StringFormat("belowIBL(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_BelowdayLowSoFar(const int barIdx, const double levelPx)
{
   if(!Gate_Level_BelowdayLowSoFar(barIdx, levelPx))
   {
      if(g_dayLowSoFarAtBar[barIdx].hasValue)
         return GateFailLabelPxVs("belowDayLowSoFar", levelPx, g_dayLowSoFarAtBar[barIdx].value);
      return StringFormat("belowDayLowSoFar(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_BelowRTHH(const int barIdx, const double levelPx)
{
   if(!Gate_Level_BelowRTHH(barIdx, levelPx))
   {
      if(g_m1DayStart == 0) return "belowRTHH";
      const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
      double rthHighSoFar = 0.0;
      if(GetRthHighSoFarAtBar(barIdx, g_m1DayStart, dateStr, rthHighSoFar))
         return GateFailLabelPxVs("belowRTHH", levelPx, rthHighSoFar);
      return StringFormat("belowRTHH(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_AboveRTHH(const int barIdx, const double levelPx)
{
   if(!Gate_Level_AboveRTHH(barIdx, levelPx))
   {
      if(g_m1DayStart == 0) return "aboveRTHH";
      const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
      double rthHighSoFar = 0.0;
      if(GetRthHighSoFarAtBar(barIdx, g_m1DayStart, dateStr, rthHighSoFar))
         return GateFailLabelPxVs("aboveRTHH", levelPx, rthHighSoFar);
      return StringFormat("aboveRTHH(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_BelowRTHL(const int barIdx, const double levelPx)
{
   if(!Gate_Level_BelowRTHL(barIdx, levelPx))
   {
      if(g_m1DayStart == 0) return "belowRTHL";
      const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
      double rthLowSoFar = 0.0;
      if(GetRthLowSoFarAtBar(barIdx, g_m1DayStart, dateStr, rthLowSoFar))
         return GateFailLabelPxVs("belowRTHL", levelPx, rthLowSoFar);
      return StringFormat("belowRTHL(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Day_DayBrokePDL_true(const int barIdx)
{
   if(!Gate_Day_DayBrokePDL_is_TRUE(barIdx)) return "dayBrokePDL";
   return "";
}

string GateFail_Day_DayBrokePDH_true(const int barIdx)
{
   if(!Gate_Day_DayBrokePDH_is_TRUE(barIdx)) return "dayBrokePDH";
   return "";
}

string GateFail_DayOfWeek(const int barIdx, const int requiredDowSlot)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return "invalidBar";
   const int dow = FalgoDayOfWeekSlotFromTimeOrInvalid(g_m1Rates[barIdx].time);
   if(dow != requiredDowSlot)
      return StringFormat("dayOfWeek(%d vs %d)", dow, requiredDowSlot);
   return "";
}

string GateFail_Session(const int barIdx, const string requiredSession)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return "invalidBar";
   const string session = GetSessionForTradeTime(g_m1Rates[barIdx].time);
   if(requiredSession == "full")
   {
      if(session == "sleep")
         return StringFormat("session(%s vs %s)", session, requiredSession);
      return "";
   }
   if(session != requiredSession)
      return StringFormat("session(%s vs %s)", session, requiredSession);
   return "";
}

string GateFail_Level_AbovedayLowSoFar(const int barIdx, const double levelPx)
{
   if(!Gate_Level_AbovedayLowSoFar(barIdx, levelPx))
   {
      if(g_dayLowSoFarAtBar[barIdx].hasValue)
         return GateFailLabelPxVs("aboveDayLowSoFar", levelPx, g_dayLowSoFarAtBar[barIdx].value);
      return StringFormat("aboveDayLowSoFar(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_AboveONL(const int barIdx, const double levelPx)
{
   if(!Gate_Level_AboveONL(barIdx, levelPx))
   {
      double onl = 0.0;
      if(GetONlowSoFarAtBar(barIdx, onl))
         return GateFailLabelPxVs("aboveONL", levelPx, onl);
      return StringFormat("aboveONL(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_BelowONL(const int barIdx, const double levelPx)
{
   if(!Gate_Level_BelowONL(barIdx, levelPx))
   {
      double onl = 0.0;
      if(GetONlowSoFarAtBar(barIdx, onl))
         return GateFailLabelPxVs("belowONL", levelPx, onl);
      return StringFormat("belowONL(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_BelowONH(const int barIdx, const double levelPx)
{
   if(!Gate_Level_BelowONH(barIdx, levelPx))
   {
      double onh = 0.0;
      if(GetONhighSoFarAtBar(barIdx, onh))
         return GateFailLabelPxVs("belowONH", levelPx, onh);
      return StringFormat("belowONH(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_BelowdayHighSoFar(const int barIdx, const double levelPx)
{
   if(!Gate_Level_BelowdayHighSoFar(barIdx, levelPx))
   {
      if(g_dayHighSoFarAtBar[barIdx].hasValue)
         return GateFailLabelPxVs("belowDayHighSoFar", levelPx, g_dayHighSoFarAtBar[barIdx].value);
      return StringFormat("belowDayHighSoFar(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_AbovedayHighSoFar(const int barIdx, const double levelPx)
{
   if(!Gate_Level_AbovedayHighSoFar(barIdx, levelPx))
   {
      if(g_dayHighSoFarAtBar[barIdx].hasValue)
         return GateFailLabelPxVs("aboveDayHighSoFar", levelPx, g_dayHighSoFarAtBar[barIdx].value);
      return StringFormat("aboveDayHighSoFar(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_AboveONH(const int barIdx, const double levelPx)
{
   if(!Gate_Level_AboveONH(barIdx, levelPx))
   {
      double onh = 0.0;
      if(GetONhighSoFarAtBar(barIdx, onh))
         return GateFailLabelPxVs("aboveONH", levelPx, onh);
      return StringFormat("aboveONH(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_Abovemidpoint(const int barIdx, const double levelPx)
{
   if(!Gate_Level_Abovemidpoint(barIdx, levelPx))
   {
      if(g_sessionRangeMidpointAtBar[barIdx].hasValue)
         return GateFailLabelPxVs("aboveMidpoint", levelPx, g_sessionRangeMidpointAtBar[barIdx].value);
      return StringFormat("aboveMidpoint(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_AbovePDO(const double levelPx)
{
   if(!Gate_Level_AbovePDO(levelPx))
   {
      const double pdo = g_staticMarketContext.PDOpreviousDayRTHOpen;
      if(pdo > 0.0)
         return GateFailLabelPxVs("abovePDO", levelPx, pdo);
      return StringFormat("abovePDO(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_AbovePDC(const double levelPx)
{
   if(!Gate_Level_AbovePDC(levelPx))
   {
      const double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
      if(pdc > 0.0)
         return GateFailLabelPxVs("abovePDC", levelPx, pdc);
      return StringFormat("abovePDC(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_AboveIBH(const int barIdx, const double levelPx)
{
   if(!Gate_Level_AboveIBH(barIdx, levelPx))
   {
      double ibh = 0.0;
      if(GetIBhighAtBar(barIdx, ibh))
         return GateFailLabelPxVs("aboveIBH", levelPx, ibh);
      return StringFormat("aboveIBH(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_AboveIBL(const int barIdx, const double levelPx)
{
   if(!Gate_Level_AboveIBL(barIdx, levelPx))
   {
      double ibl = 0.0;
      if(GetIBlowAtBar(barIdx, ibl))
         return GateFailLabelPxVs("aboveIBL", levelPx, ibl);
      return StringFormat("aboveIBL(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_Level_AboveRTHL(const int barIdx, const double levelPx)
{
   if(!Gate_Level_AboveRTHL(barIdx, levelPx))
   {
      if(g_m1DayStart == 0) return "aboveRTHL";
      const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
      double rthLowSoFar = 0.0;
      if(GetRthLowSoFarAtBar(barIdx, g_m1DayStart, dateStr, rthLowSoFar))
         return GateFailLabelPxVs("aboveRTHL", levelPx, rthLowSoFar);
      return StringFormat("aboveRTHL(%s)", DoubleToString(levelPx, _Digits));
   }
   return "";
}

string GateFail_CleanStreak_Long(const int barIdx, const double tradeLevel, const double minAnchorAbove, const int minStreakCount)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || tradeLevel <= 0.0) return "";
   PullingHistoryAlgoFamilyBarSnap snap;
   if(!FalgoPullingHistorySnapForLevelAtBar(tradeLevel, barIdx, snap))
      return "";
   const double anchorAbove = snap.closestWeeklyLevel_anchorAbove_within_cleanOHLC_streak;
   const int streakCount = snap.cleanOHLC_streak_count;
   if(anchorAbove <= minAnchorAbove)
      return GateFailLabelDbl1Vs("anchorAboveTooLow", anchorAbove, minAnchorAbove);
   if(streakCount <= minStreakCount)
      return GateFailLabelIntVs("cleanOHLC_streakTooShort", streakCount, minStreakCount);
   return "";
}

string GateFail_CleanStreak_TooLong(const int barIdx, const double tradeLevel, const int maxStreakCountExclusive)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || tradeLevel <= 0.0) return "";
   PullingHistoryAlgoFamilyBarSnap snap;
   if(!FalgoPullingHistorySnapForLevelAtBar(tradeLevel, barIdx, snap))
      return "";
   const int streakCount = snap.cleanOHLC_streak_count;
   if(streakCount >= maxStreakCountExclusive)
      return GateFailLabelIntVs("cleanOHLC_streakTooLong", streakCount, maxStreakCountExclusive);
   return "";
}

string GateFail_AnchorAbove_TooHigh(const int barIdx, const double tradeLevel, const double maxAnchorAboveExclusive)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || tradeLevel <= 0.0) return "";
   PullingHistoryAlgoFamilyBarSnap snap;
   if(!FalgoPullingHistorySnapForLevelAtBar(tradeLevel, barIdx, snap))
      return "";
   const double anchorAbove = snap.closestWeeklyLevel_anchorAbove_within_cleanOHLC_streak;
   if(anchorAbove >= maxAnchorAboveExclusive)
      return GateFailLabelDbl1Vs("anchorAboveTooHigh", anchorAbove, maxAnchorAboveExclusive);
   return "";
}

string GateFail_CleanStreak_Short(const int barIdx, const double tradeLevel, const double minAnchorBelow, const int minStreakCount)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || tradeLevel <= 0.0) return "";
   PullingHistoryAlgoFamilyBarSnap snap;
   if(!FalgoPullingHistorySnapForLevelAtBar(tradeLevel, barIdx, snap))
      return "";
   const double anchorBelow = snap.closestWeeklyLevel_anchorBelow_within_cleanOHLC_streak;
   const int streakCount = snap.cleanOHLC_streak_count;
   if(anchorBelow <= minAnchorBelow)
      return GateFailLabelDbl1Vs("anchorBelowTooLow", anchorBelow, minAnchorBelow);
   if(streakCount <= minStreakCount)
      return GateFailLabelIntVs("cleanOHLC_streakTooShort", streakCount, minStreakCount);
   return "";
}

string GateFail_DayLowSoFar_NoMoreThanX_BelowLevel(const int barIdx, const double levelPx, const double x)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return "";
   if(!g_dayLowSoFarAtBar[barIdx].hasValue)
      return "dayLowSoFarUnknown";
   const double minAllowedDayLow = levelPx - x;
   if(!Gate_DayLowSoFar_NoMoreThanX_BelowLevel(barIdx, levelPx, x))
      return GateFailLabelPxVs("dayLowTooFarBelowLevel", g_dayLowSoFarAtBar[barIdx].value, minAllowedDayLow);
   return "";
}

string GateFail_DayLowSoFar_AtLeastX_BelowLevel(const int barIdx, const double levelPx, const double x)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return "";
   if(!g_dayLowSoFarAtBar[barIdx].hasValue)
      return "dayLowSoFarUnknown";
   const double maxAllowedDayLow = levelPx - x;
   if(!Gate_DayLowSoFar_AtLeastX_BelowLevel(barIdx, levelPx, x))
      return GateFailLabelPxVs("dayLowNotFarEnoughBelowLevel", g_dayLowSoFarAtBar[barIdx].value, maxAllowedDayLow);
   return "";
}

string GateFail_DayHighSoFar_AtLeastX_AboveLevel(const int barIdx, const double levelPx, const double x)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return "";
   if(!g_dayHighSoFarAtBar[barIdx].hasValue)
      return "dayHighSoFarUnknown";
   const double minAllowedDayHigh = levelPx + x;
   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(barIdx, levelPx, x))
      return GateFailLabelPxVs("dayHighNotFarEnoughAboveLevel", g_dayHighSoFarAtBar[barIdx].value, minAllowedDayHigh);
   return "";
}

string GateFail_DayHighSoFar_NoMoreThanX_AboveLevel(const int barIdx, const double levelPx, const double x)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return "";
   if(!g_dayHighSoFarAtBar[barIdx].hasValue)
      return "dayHighSoFarUnknown";
   const double maxAllowedDayHigh = levelPx + x;
   if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(barIdx, levelPx, x))
      return GateFailLabelPxVs("dayHighTooFarAboveLevel", g_dayHighSoFarAtBar[barIdx].value, maxAllowedDayHigh);
   return "";
}

void AlgoRuleAdd_RecentBounceCountTooHigh(const int slotIdx, const int maxAllowed)
{
   BreakdownRuleChainAdd(slotIdx, RULE_RECENT_BOUNCE_TOO_HIGH, maxAllowed);
}

void AlgoRuleAdd_WeekBounceCountTooLow(const int slotIdx, const int minCount)
{
   BreakdownRuleChainAdd(slotIdx, RULE_WEEK_BOUNCE_TOO_LOW, minCount);
}

void AlgoRuleAdd_WeekBounceCountTooHigh(const int slotIdx, const int maxAllowed)
{
   BreakdownRuleChainAdd(slotIdx, RULE_WEEK_BOUNCE_TOO_HIGH, maxAllowed);
}

void AlgoRuleAdd_WeekCeilingCountTooLow(const int slotIdx, const int minCount)
{
   BreakdownRuleChainAdd(slotIdx, RULE_WEEK_CEILING_TOO_LOW, minCount);
}

void AlgoRuleAdd_WeekCeilingCountTooHigh(const int slotIdx, const int maxAllowed)
{
   BreakdownRuleChainAdd(slotIdx, RULE_WEEK_CEILING_TOO_HIGH, maxAllowed);
}

void AlgoRuleAdd_PDgreen(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_PD_GREEN);
}

void AlgoRuleAdd_PDred(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_PD_RED);
}

void AlgoRuleAdd_LevelBelowONH(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_ONH);
}

//+------------------------------------------------------------------+
//| Breakdown rule engine: ordered rule chains per slot (g_breakdownAlgos[].rules). |
//| Level-named rules evaluate against planned trade price, not closest level. |
//+------------------------------------------------------------------+
void BreakdownRuleChainClear(const int slotIdx)
{
   g_breakdownAlgos[slotIdx].rule_count = 0;
}

//+------------------------------------------------------------------+
void BreakdownRuleChainAdd(const int slotIdx, const ENUM_ALGO_RULE ruleId,
                      const int i0 = 0, const int i1 = 0,
                      const double d0 = 0.0, const double d1 = 0.0,
                      const string s0 = "")
{
   if(slotIdx < 0 || slotIdx >= g_breakdownAlgoCount)
      FatalError("BreakdownRuleChainAdd: invalid slotIdx");
   if(g_breakdownAlgos[slotIdx].rule_count >= ALGO_RULES_MAX)
      FatalError(StringFormat("BreakdownRuleChainAdd: ALGO_RULES_MAX exceeded for algo %d", g_breakdownAlgos[slotIdx].algo_id));
   const int r = g_breakdownAlgos[slotIdx].rule_count;
   g_breakdownAlgos[slotIdx].rules[r].rule_id = ruleId;
   g_breakdownAlgos[slotIdx].rules[r].i0 = i0;
   g_breakdownAlgos[slotIdx].rules[r].i1 = i1;
   g_breakdownAlgos[slotIdx].rules[r].d0 = d0;
   g_breakdownAlgos[slotIdx].rules[r].d1 = d1;
   g_breakdownAlgos[slotIdx].rules[r].s0 = s0;
   g_breakdownAlgos[slotIdx].rule_count++;
}

//+------------------------------------------------------------------+
string EvalAlgoRule(const int algoId, const AlgoRuleEntry &rule, const int barIdx, const double plannedTradePrice)
{
   switch(rule.rule_id)
   {
      case RULE_CLEAN_STREAK_LONG:
         return GateFail_CleanStreak_Long(barIdx, plannedTradePrice, rule.d0, rule.i0);
      case RULE_CLEAN_STREAK_TOO_LONG:
         return GateFail_CleanStreak_TooLong(barIdx, plannedTradePrice, rule.i0);
      case RULE_ANCHOR_ABOVE_TOO_HIGH:
         return GateFail_AnchorAbove_TooHigh(barIdx, plannedTradePrice, rule.d0);
      case RULE_CLEAN_STREAK_SHORT:
         return GateFail_CleanStreak_Short(barIdx, plannedTradePrice, rule.d0, rule.i0);
      case RULE_BOUNCE_COUNT_TOO_HIGH:
         return GateFail_BounceCount_TooHigh(barIdx, plannedTradePrice, rule.i0);
      case RULE_BOUNCE_COUNT_TOO_LOW:
         return GateFail_BounceCount_TooLow(barIdx, plannedTradePrice, rule.i0);
      case RULE_RECENT_BOUNCE_TOO_HIGH:
         return GateFail_RecentBounceCount_TooHigh(barIdx, plannedTradePrice, rule.i0);
      case RULE_CEILING_COUNT_TOO_HIGH:
         return GateFail_CeilingCount_TooHigh(barIdx, plannedTradePrice, rule.i0, rule.s0);
      case RULE_CEILING_COUNT_TOO_LOW:
         return GateFail_CeilingCount_TooLow(barIdx, plannedTradePrice, rule.i0);
      case RULE_CEILING_PROXIMITY_CANDLES_TOO_HIGH:
         return GateFail_CeilingProximityCandles_TooHigh(barIdx, plannedTradePrice, rule.i0, rule.s0);
      case RULE_TRADES_AT_LEVEL_LIMIT:
         return "";  // level-family only
      case RULE_WEEK_BOUNCE_TOO_HIGH:
         return GateFail_WeekBounceCount_TooHigh(barIdx, plannedTradePrice, rule.i0);
      case RULE_WEEK_BOUNCE_TOO_LOW:
         return GateFail_WeekBounceCount_TooLow(barIdx, plannedTradePrice, rule.i0);
      case RULE_WEEK_CEILING_TOO_HIGH:
         return GateFail_WeekCeilingCount_TooHigh(barIdx, plannedTradePrice, rule.i0);
      case RULE_WEEK_CEILING_TOO_LOW:
         return GateFail_WeekCeilingCount_TooLow(barIdx, plannedTradePrice, rule.i0);
      case RULE_WEEK_CONTACT_CANDLES_TOO_HIGH:
         return GateFail_WeekContactCandles_TooHigh(barIdx, plannedTradePrice, rule.i0);
      case RULE_WEEK_CONTACT_CANDLES_TOO_LOW:
         return GateFail_WeekContactCandles_TooLow(barIdx, plannedTradePrice, rule.i0);
      case RULE_LEVEL_ONO_ABS_DIFF_TOO_LOW:
         return GateFail_LevelOnoAbsDiff_TooLow(plannedTradePrice, rule.d0);
      case RULE_ONO_ABOVE_LEVEL_TOO_LOW:
         return GateFail_ONO_AboveLevel_TooLow(plannedTradePrice, rule.d0);
      case RULE_ONO_BELOW_LEVEL_TOO_LOW:
         return GateFail_ONO_BelowLevel_TooLow(plannedTradePrice, rule.d0);
      case RULE_DAYSTART_EARLIER_WEEK_CONTACT_TOO_HIGH:
         return GateFail_DayStartEarlierWeekContact_TooHigh(plannedTradePrice, rule.i0);
      case RULE_DAY_CONTACT_TODAY_TOO_HIGH:
         return GateFail_DayContactToday_TooHigh(barIdx, plannedTradePrice, rule.i0);
      case RULE_PD_RED:
         return GateFail_PD_red();
      case RULE_PD_GREEN:
         return GateFail_PD_green();
      case RULE_DAY_BROKE_PDL:
         return GateFail_Day_DayBrokePDL(barIdx);
      case RULE_DAY_BROKE_PDH:
         return GateFail_Day_DayBrokePDH(barIdx);
      case RULE_DAY_BROKE_PDH_TRUE:
         return GateFail_Day_DayBrokePDH_true(barIdx);
      case RULE_LEVEL_ABOVE_ONL:
         return GateFail_Level_AboveONL(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_ONL:
         return GateFail_Level_BelowONL(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_ONH:
         return GateFail_Level_BelowONH(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_DAY_HIGH:
         return GateFail_Level_BelowdayHighSoFar(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_DAY_LOW:
         return GateFail_Level_BelowdayLowSoFar(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_PDH:
         return GateFail_Level_BelowPDH(plannedTradePrice);
      case RULE_LEVEL_ABOVE_PDH:
         return GateFail_Level_AbovePDH(plannedTradePrice);
      case RULE_LEVEL_ABOVE_DAY_LOW:
         return GateFail_Level_AbovedayLowSoFar(barIdx, plannedTradePrice);
      case RULE_DAY_LOW_SOFAR_NO_MORE_THAN_X_BELOW_LEVEL:
         return GateFail_DayLowSoFar_NoMoreThanX_BelowLevel(barIdx, plannedTradePrice, rule.d0);
      case RULE_DAY_LOW_SOFAR_AT_LEAST_X_BELOW_LEVEL:
         return GateFail_DayLowSoFar_AtLeastX_BelowLevel(barIdx, plannedTradePrice, rule.d0);
      case RULE_DAY_HIGH_SOFAR_AT_LEAST_X_ABOVE_LEVEL:
         return GateFail_DayHighSoFar_AtLeastX_AboveLevel(barIdx, plannedTradePrice, rule.d0);
      case RULE_DAY_HIGH_SOFAR_NO_MORE_THAN_X_ABOVE_LEVEL:
         return GateFail_DayHighSoFar_NoMoreThanX_AboveLevel(barIdx, plannedTradePrice, rule.d0);
      case RULE_LEVEL_ABOVE_PDL:
         return GateFail_Level_AbovePDL(plannedTradePrice);
      case RULE_LEVEL_BELOW_PDL:
         return GateFail_Level_BelowPDL(plannedTradePrice);
      case RULE_LEVEL_ABOVE_PDC:
         return GateFail_Level_AbovePDC(plannedTradePrice);
      case RULE_LEVEL_BELOW_PDC:
         return GateFail_Level_BelowPDC(plannedTradePrice);
      case RULE_LEVEL_BELOW_PDO:
         return GateFail_Level_BelowPDO(plannedTradePrice);
      case RULE_LEVEL_BELOW_MIDPOINT:
         return GateFail_Level_Belowmidpoint(barIdx, plannedTradePrice);
      case RULE_LEVEL_ABOVE_MIDPOINT:
         return GateFail_Level_Abovemidpoint(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_IBH:
         return GateFail_Level_BelowIBH(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_IBL:
         return GateFail_Level_BelowIBL(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_RTHH:
         return GateFail_Level_BelowRTHH(barIdx, plannedTradePrice);
      case RULE_LEVEL_ABOVE_RTHH:
         return GateFail_Level_AboveRTHH(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_RTHL:
         return GateFail_Level_BelowRTHL(barIdx, plannedTradePrice);
      case RULE_LEVEL_TAG:
         return GateFail_LevelTag(plannedTradePrice, rule.s0);
      case RULE_OPEN_GAP_UNKNOWN:
         return GateFail_OpenGapInfo_Unknown(barIdx);
      case RULE_LEVEL_ABOVE_ONH:
         return GateFail_Level_AboveONH(barIdx, plannedTradePrice);
      case RULE_LEVEL_ABOVE_DAY_HIGH:
         return GateFail_Level_AbovedayHighSoFar(barIdx, plannedTradePrice);
      case RULE_LEVEL_ABOVE_PDO:
         return GateFail_Level_AbovePDO(plannedTradePrice);
      case RULE_LEVEL_ABOVE_IBH:
         return GateFail_Level_AboveIBH(barIdx, plannedTradePrice);
      case RULE_LEVEL_ABOVE_IBL:
         return GateFail_Level_AboveIBL(barIdx, plannedTradePrice);
      case RULE_LEVEL_ABOVE_RTHL:
         return GateFail_Level_AboveRTHL(barIdx, plannedTradePrice);
      case RULE_DAY_BROKE_PDL_TRUE:
         return GateFail_Day_DayBrokePDL_true(barIdx);
      case RULE_DAY_OF_WEEK:
         return GateFail_DayOfWeek(barIdx, rule.i0);
      case RULE_SESSION:
         return GateFail_Session(barIdx, rule.s0);
      case RULE_DAY_GAP_DOWN_REQUIRED:
         return GateFail_Day_GapDownRequired();
      case RULE_DAY_GAP_UP_REQUIRED:
         return GateFail_Day_GapUpRequired();
      case RULE_GAP_RANGE_PTS_ABOVE:
         return GateFail_GapRangePts_Above(rule.d0);
      case RULE_GAP_FILL_PC_BELOW:
         return GateFail_GapFillPc_Below(barIdx, rule.d0);
      case RULE_RTHO_TERTIARY_READY:
         return GateFail_RthoTertiaryLevelReady(barIdx);
   }
   return "unknownRule";
}

//+------------------------------------------------------------------+
string BreakdownRunRulesFirstFail(const int slotIdx, const int barIdx, const datetime evalTime)
{
   if(slotIdx < 0 || slotIdx >= g_breakdownAlgoCount)
      return "unknownAlgo";
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return "invalidBar";
   const double plannedTradePrice = BreakdownPlannedTradePriceAtEval(g_breakdownAlgos[slotIdx].algo_id, barIdx, evalTime);
   if(plannedTradePrice <= 0.0)
      return "";  // no planned price yet — skip rule chain (entry gates handle timing)
   for(int r = 0; r < g_breakdownAlgos[slotIdx].rule_count; r++)
   {
      const string f = EvalAlgoRule(g_breakdownAlgos[slotIdx].algo_id,
         g_breakdownAlgos[slotIdx].rules[r], barIdx, plannedTradePrice);
      if(f != "")
         return f;
   }
   return "";
}

//+------------------------------------------------------------------+
void BreakdownRebuildRuleChainForSlot(const int slotIdx)
{
   if(slotIdx < 0 || slotIdx >= g_breakdownAlgoCount)
      return;
   const int algoId = g_breakdownAlgos[slotIdx].algo_id;
   BreakdownRuleChainClear(slotIdx);
   switch(algoId)
   {
      // algobookmark breakdown rules
//breakdowncreator4start
      case MAGIC_BREAKDOWN200:
         // wire breakdown gates vs planned trade price here (AlgoRuleAdd_LevelBelowONH etc.)
         break;
      case MAGIC_BREAKDOWN201:
         // wire breakdown gates vs planned trade price here (AlgoRuleAdd_LevelBelowONH etc.)
         break;
      case MAGIC_BREAKDOWN202:
         // wire breakdown gates vs planned trade price here (AlgoRuleAdd_LevelBelowONH etc.)
         break;
      case MAGIC_BREAKDOWN203:
         // wire breakdown gates vs planned trade price here (AlgoRuleAdd_LevelBelowONH etc.)
         break;
      case MAGIC_BREAKDOWN204:
         // wire breakdown gates vs planned trade price here (AlgoRuleAdd_LevelBelowONH etc.)
         break;
//breakdowncreator4end
      default:
         break;
   }
}

//+------------------------------------------------------------------+
void BreakdownRebuildAllRuleChains()
{
   for(int i = 0; i < g_breakdownAlgoCount; i++)
      BreakdownRebuildRuleChainForSlot(i);
}

//+------------------------------------------------------------------+
void BreakdownGatesLogInitFileHandles()
{
   for(int bi = 0; bi < BREAKDOWN_ALGO_REGISTRY_MAX; bi++)
   {
      g_breakdownGatesPmFileHandle[bi] = INVALID_HANDLE;
      g_breakdownGatesPsFileHandle[bi] = INVALID_HANDLE;
   }
   g_breakdownGatesLogFileDayStart = 0;
}

//+------------------------------------------------------------------+
void BreakdownGatesLogCloseAllFileHandles()
{
   for(int bi = 0; bi < BREAKDOWN_ALGO_REGISTRY_MAX; bi++)
   {
      if(g_breakdownGatesPmFileHandle[bi] != INVALID_HANDLE)
      {
         FileClose(g_breakdownGatesPmFileHandle[bi]);
         g_breakdownGatesPmFileHandle[bi] = INVALID_HANDLE;
      }
      if(g_breakdownGatesPsFileHandle[bi] != INVALID_HANDLE)
      {
         FileClose(g_breakdownGatesPsFileHandle[bi]);
         g_breakdownGatesPsFileHandle[bi] = INVALID_HANDLE;
      }
   }
}

//+------------------------------------------------------------------+
void BreakdownGatesLogEnsureDay()
{
   if(g_m1DayStart == 0)
      return;
   if(g_breakdownGatesLogFileDayStart == g_m1DayStart)
      return;
   BreakdownGatesLogCloseAllFileHandles();
   g_breakdownGatesLogFileDayStart = g_m1DayStart;
}

//+------------------------------------------------------------------+
void BreakdownGatesLogWriteHeaderIfEmpty(const int fh)
{
   if(fh == INVALID_HANDLE)
      return;
   FileSeek(fh, 0, SEEK_END);
   if(FileTell(fh) != 0)
      return;
   FileWrite(fh, "barTime", "O", "H", "L", "C",
      "breakdown_sequence_starttime", "breakdown_sequence_startprice",
      "breakdown_endtime", "breakdown_low", "ended_length",
      "firstGreen15mC_afterBreakdown_high", "midpoint", "minutes_since_end",
      "plannedTradePrice", "firstFailGate", "2ndFailFlag", "3rdFailFlag", "failGateCount",
      "dayWins", "dayLosses", "mfe", "mae", "trades_today", "trades_all");
}

//+------------------------------------------------------------------+
int BreakdownGatesLogAcquireHandle(const int slotIdx, const int algoNumber, const bool perSecond, const string dateStr)
{
   if(slotIdx < 0 || slotIdx >= BREAKDOWN_ALGO_REGISTRY_MAX)
      return INVALID_HANDLE;
   BreakdownGatesLogEnsureDay();

   int fhRef = perSecond ? g_breakdownGatesPsFileHandle[slotIdx] : g_breakdownGatesPmFileHandle[slotIdx];
   if(fhRef != INVALID_HANDLE)
   {
      FileSeek(fhRef, 0, SEEK_END);
      return fhRef;
   }

   const string logSuffix = perSecond ? "gates_per_second" : "gates_per_minute";
   const string fname = BreakdownAlgoCsvFileName(dateStr, algoNumber, logSuffix);
   fhRef = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fhRef == INVALID_HANDLE)
      fhRef = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fhRef == INVALID_HANDLE)
      return INVALID_HANDLE;

   BreakdownGatesLogWriteHeaderIfEmpty(fhRef);
   FileSeek(fhRef, 0, SEEK_END);
   if(perSecond)
      g_breakdownGatesPsFileHandle[slotIdx] = fhRef;
   else
      g_breakdownGatesPmFileHandle[slotIdx] = fhRef;
   return fhRef;
}

//+------------------------------------------------------------------+
void AlgoGatesFailFlagsAppend(string &outFlags[], const string flag)
{
   if(flag == "")
      return;
   const int n = ArraySize(outFlags);
   ArrayResize(outFlags, n + 1);
   outFlags[n] = flag;
}

//+------------------------------------------------------------------+
void AlgoGatesCollectBreakdownPlacementFailFlags(const int algoNumber, const int barIdx,
   const bool profileEnabled, const bool tradingDay, const bool tradingTime,
   const bool underLoss, const bool underWin, const bool underOpenLimit,
   const bool tradeCloseDedicatedBar, const bool familyBlock,
   const Breakdown15mState &bdSnap,
   string &outFlags[], const datetime evalTime)
{
   ArrayResize(outFlags, 0);
   if(!profileEnabled) AlgoGatesFailFlagsAppend(outFlags, "profileDisabled");
   if(!tradingDay) AlgoGatesFailFlagsAppend(outFlags, "tradingDayBanned");
   if(!tradingTime) AlgoGatesFailFlagsAppend(outFlags, "tradingTimeBanned");
   const string familyDayStop = BreakdownFamilyDayStopFirstFailLabel();
   if(familyDayStop != "") AlgoGatesFailFlagsAppend(outFlags, familyDayStop);
   if(!underLoss) AlgoGatesFailFlagsAppend(outFlags, "lossStopDayLimit");
   if(!underWin) AlgoGatesFailFlagsAppend(outFlags, "winStopDayLimit");
   if(!underOpenLimit)
   {
      const string openLimit = BreakdownMaxOpenPositionsFailLabel(algoNumber);
      AlgoGatesFailFlagsAppend(outFlags, (openLimit != "" ? openLimit : "maxOpenPositionsReached"));
   }
   if(tradeCloseDedicatedBar) AlgoGatesFailFlagsAppend(outFlags, "tradeClosedThisBar");
   if(familyBlock && g_breakdownFamilyHadCloseThisPipelinePass) AlgoGatesFailFlagsAppend(outFlags, "tradeClosedThisPipelineFam");
   if(familyBlock && BreakdownHasOpenPositionOnSymbol()) AlgoGatesFailFlagsAppend(outFlags, "openFalgoPositionFam");
   if(familyBlock && BreakdownHasPendingOrderOnSymbol()) AlgoGatesFailFlagsAppend(outFlags, "pendingFalgoOrderFam");

   const string entryBlock = BreakdownMidpointEntryBlockReason(algoNumber, bdSnap, evalTime);
   if(entryBlock != "")
      AlgoGatesFailFlagsAppend(outFlags, entryBlock);

   const int slotIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(slotIdx >= 0)
   {
      for(int r = 0; r < g_breakdownAlgos[slotIdx].rule_count; r++)
      {
         const double plannedTradePrice = BreakdownPlannedTradePriceAtEval(algoNumber, barIdx, evalTime);
         const string ruleFail = EvalAlgoRule(g_breakdownAlgos[slotIdx].algo_id,
            g_breakdownAlgos[slotIdx].rules[r], barIdx, plannedTradePrice);
         if(ruleFail != "")
            AlgoGatesFailFlagsAppend(outFlags, ruleFail);
      }
   }
}

//+------------------------------------------------------------------+
void BreakdownAppendGatesLogRow(const int barIdx, const int algoNumber, const bool perSecond = false)
{
   if(!BreakdownAlgoSlotEnabled(algoNumber))
      return;
   if(!perSecond)
   {
      if(!bigflipper_log_algo_gates_per_minute)
         return;
   }
   else if(!bigflipper_log_algo_gates_per_second)
   {
      return;
   }
   if(barIdx < 0 || barIdx >= g_barsInDay || g_m1DayStart == 0)
      return;

   const int slotIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(slotIdx < 0)
      return;

   const datetime rowTime = perSecond ? g_lastTimer1Time : g_m1Rates[barIdx].time;
   if(perSecond)
   {
      if(g_falgoGatesLogDayStart != g_m1DayStart)
      {
         g_falgoGatesLogDayStart = g_m1DayStart;
         BreakdownGatesLogEnsureDay();
         for(int bi = 0; bi < BREAKDOWN_ALGO_REGISTRY_MAX; bi++)
         {
            g_breakdownGatesLastLoggedBarTime[bi] = 0;
            g_breakdownGatesPerSecondLastLoggedTime[bi] = 0;
            g_breakdownGatesCloseTelValid[bi] = false;
         }
      }
      if(rowTime == g_breakdownGatesPerSecondLastLoggedTime[slotIdx])
         return;
      g_breakdownGatesPerSecondLastLoggedTime[slotIdx] = rowTime;
   }

   const datetime evalTime = perSecond ? g_lastTimer1Time : (rowTime + 60);
   const Breakdown15mState bdSnap = Breakdown15mSnapForAlgo(algoNumber, evalTime);

   bool underLoss = true, underAllAlgosLoss = true;
   AlgoDayStopUnderLossLimit(algoNumber, underLoss, underAllAlgosLoss);
   bool underWin = true, underAllAlgosWin = true;
   AlgoDayStopUnderWinLimit(algoNumber, underWin, underAllAlgosWin);
   underLoss = underLoss && underAllAlgosLoss;
   underWin = underWin && underAllAlgosWin;

   const bool profileEnabled = AlgoProfileEnabled(algoNumber);
   const bool tradingDay = FalgoIsTradingDayAllowedAtTime(evalTime);
   const bool tradingTime = FalgoIsTradingTimeAllowed(evalTime);
   const bool underOpenLimit = BreakdownUnderMaxOpenPositionsLimit(algoNumber);
   const bool tradeCloseDedicatedBar = !FalgoRulesetPassesCloseBarForAlgo(algoNumber, barIdx);
   const bool familyBlock = BreakdownFamilyBlocksPlacementOnOpenOrPending();

   string failFlags[];
   AlgoGatesCollectBreakdownPlacementFailFlags(algoNumber, barIdx,
      profileEnabled, tradingDay, tradingTime, underLoss, underWin, underOpenLimit,
      tradeCloseDedicatedBar, familyBlock, bdSnap, failFlags, evalTime);
   string firstFail = (ArraySize(failFlags) > 0 ? failFlags[0] : "");
   string secondFail = (ArraySize(failFlags) > 1 ? failFlags[1] : "");
   string thirdFail = (ArraySize(failFlags) > 2 ? failFlags[2] : "");
   int failGateCount = (firstFail != "" ? ArraySize(failFlags) : 0);
   const string plannedTradePrice = BreakdownPlannedTradePriceForGates(algoNumber, evalTime, bdSnap);
   const double minutesSinceEnd = (bdSnap.endTime > 0 && evalTime >= bdSnap.endTime)
      ? (double)(evalTime - bdSnap.endTime) / 60.0 : 0.0;
   const int seqLen = bdSnap.sequenceActive ? bdSnap.activeLength : bdSnap.endedLength;

   double rowO = 0.0, rowH = 0.0, rowL = 0.0, rowC = 0.0;
   if(perSecond)
      PullingHistoryAlgoFamilyOhlcAsOfTime(g_lastTimer1Time, rowO, rowH, rowL, rowC);
   else
   {
      rowO = g_m1Rates[barIdx].open;
      rowH = g_m1Rates[barIdx].high;
      rowL = g_m1Rates[barIdx].low;
      rowC = g_m1Rates[barIdx].close;
   }

   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   const int fh = BreakdownGatesLogAcquireHandle(slotIdx, algoNumber, perSecond, dateStr);
   if(fh == INVALID_HANDLE)
      return;
   const int timeFormat = perSecond ? (TIME_DATE|TIME_SECONDS) : (TIME_DATE|TIME_MINUTES);
   double gatesMfePts = 0.0, gatesMaePts = 0.0;
   bool gatesCloseTelFilled = false;
   if(!perSecond)
      BreakdownTakeGatesCloseTelemetryForBar(slotIdx, rowTime, gatesMfePts, gatesMaePts, gatesCloseTelFilled);
   FileWrite(fh,
      TimeToString(rowTime, timeFormat),
      DoubleToString(rowO, _Digits),
      DoubleToString(rowH, _Digits),
      DoubleToString(rowL, _Digits),
      DoubleToString(rowC, _Digits),
      (bdSnap.hasBreakdown && bdSnap.startTime > 0
         ? TimeToString(bdSnap.startTime, TIME_DATE|TIME_MINUTES) : ""),
      (bdSnap.hasBreakdown && bdSnap.startHigh > 0.0
         ? DoubleToString(bdSnap.startHigh, _Digits) : ""),
      (bdSnap.endTime > 0 ? TimeToString(bdSnap.endTime, TIME_DATE|TIME_MINUTES) : ""),
      DoubleToString(bdSnap.breakdownLow, _Digits),
      IntegerToString(seqLen),
      (bdSnap.firstGreenHigh > 0.0 ? DoubleToString(bdSnap.firstGreenHigh, _Digits) : ""),
      DoubleToString(bdSnap.midpoint, _Digits),
      DoubleToString(minutesSinceEnd, 1),
      plannedTradePrice,
      firstFail, secondFail, thirdFail,
      IntegerToString(failGateCount),
      IntegerToString(g_breakdownAlgoDayWins[slotIdx]),
      IntegerToString(g_breakdownAlgoDayLosses[slotIdx]),
      BreakdownLifetimeLogTelemetryPtsCol(gatesMfePts, !perSecond && gatesCloseTelFilled),
      BreakdownLifetimeLogTelemetryPtsCol(gatesMaePts, !perSecond && gatesCloseTelFilled),
      IntegerToString(BreakdownAlgoTradesTodayForLog(algoNumber)),
      IntegerToString(BreakdownAlgoTradesAllForLog(algoNumber)));
}

//+------------------------------------------------------------------+
void FalgoTryLogGatesForClosedMinute()
{
   if(!bigflipper_log_algo_gates_per_minute)
      return;
   if(g_barsInDay < 1 || g_m1DayStart == 0)
      return;
   if(g_falgoGatesLogDayStart != g_m1DayStart)
   {
      g_falgoGatesLogDayStart = g_m1DayStart;
      BreakdownGatesLogEnsureDay();
      for(int bi = 0; bi < BREAKDOWN_ALGO_REGISTRY_MAX; bi++)
      {
         g_breakdownGatesLastLoggedBarTime[bi] = 0;
         g_breakdownGatesPerSecondLastLoggedTime[bi] = 0;
         g_breakdownGatesCloseTelValid[bi] = false;
      }
   }
   const int barIdx = g_barsInDay - 2;
   if(g_barsInDay < 2)
      return;
   const datetime barTime = g_m1Rates[barIdx].time;
   const datetime evalTime = barTime + 60;
   for(int si = 0; si < g_breakdownAlgoCount; si++)
   {
      if(!g_breakdownAlgos[si].enabled)
         continue;
      EnsureBreakdown15mSnapForAlgoSlot(si, evalTime);
   }
   const bool profOn = BacktestProfileEnabled();
   ulong profT0 = 0;
   for(int bi = 0; bi < g_breakdownAlgoCount; bi++)
   {
      const int algoNumber = g_breakdownAlgos[bi].algo_id;
      if(!BreakdownAlgoSlotEnabled(algoNumber))
         continue;
      if(barTime == g_breakdownGatesLastLoggedBarTime[bi])
         continue;
      g_breakdownGatesLastLoggedBarTime[bi] = barTime;
      if(profOn)
         profT0 = GetMicrosecondCount();
      BreakdownAppendGatesLogRow(barIdx, algoNumber);
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_GATES_LOG_PER_MINUTE, profT0);
   }
}

//+------------------------------------------------------------------+
void FalgoTryLogAlgoFamilyPerSecond()
{
   if(!FalgoIsTimeInPerSecondLogWindow(g_lastTimer1Time))
      return;
   if(!bigflipper_log_testing_algofamily_per_second && !bigflipper_log_algo_gates_per_second)
      return;
   if(g_barsInDay <= 0 || g_m1DayStart == 0)
      return;
   const int snapBarIdx = FalgoSnapBarIdxAsOfTime(g_lastTimer1Time);
   if(snapBarIdx < 0)
      return;
   const datetime dayStart = g_lastTimer1Time - (g_lastTimer1Time % 86400);
   const string dateStr = TimeToString(dayStart, TIME_DATE);
   if(bigflipper_log_testing_algofamily_per_second)
   {
      const bool profOn = BacktestProfileEnabled();
      ulong profT0 = 0;
      if(profOn)
         profT0 = GetMicrosecondCount();
      double o = 0.0, h = 0.0, l = 0.0, c = 0.0;
      PullingHistoryAlgoFamilyOhlcAsOfTime(g_lastTimer1Time, o, h, l, c);
      PullingHistoryAlgoFamilyAppendPerSecondRow(dateStr, "weekly", g_lastTimer1Time, snapBarIdx, o, h, l, c);
      PullingHistoryAlgoFamilyAppendPerSecondRow(dateStr, "daily", g_lastTimer1Time, snapBarIdx, o, h, l, c);
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_ALGOFAMILY_LOG_PER_SECOND, profT0);
   }
   if(bigflipper_log_algo_gates_per_second)
   {
      const bool profOn = BacktestProfileEnabled();
      ulong profT0 = 0;
      const int placementBarIdx = g_barsInDay - 1;
      for(int bi = 0; bi < g_breakdownAlgoCount; bi++)
      {
         const int algoNumber = g_breakdownAlgos[bi].algo_id;
         if(!BreakdownAlgoSlotEnabled(algoNumber))
            continue;
         const int slotIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
         if(slotIdx < 0)
            continue;
         if(g_lastTimer1Time == g_breakdownGatesPerSecondLastLoggedTime[slotIdx])
            continue;
         if(profOn)
            profT0 = GetMicrosecondCount();
         BreakdownAppendGatesLogRow(placementBarIdx, algoNumber, true);
         if(profOn)
            BacktestProfAccumulate(BACKTEST_PROF_GATES_LOG_PER_SECOND, profT0);
      }
   }
}

//+------------------------------------------------------------------+
bool AlgoTryPlaceBreakdownMidpointOrder(const int algoNumber, const int barIdx)
{
   const int algoSlot = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
   if(algoSlot < 0 || !IsBreakdownFamilyAlgoNumber(algoNumber))
      return false;
   if(!AlgoProfileEnabled(algoNumber))
      return false;
   if(!BreakdownRulesetPassesCommonForPlacement(algoNumber, barIdx))
      return false;
   const string ruleFail = BreakdownRunRulesFirstFail(algoSlot, barIdx, g_lastTimer1Time);
   if(ruleFail != "")
      return false;
   if(BreakdownAlgoOrderStateBlockReason(algoNumber) != "")
      return false;
   const Breakdown15mState bdSnap = Breakdown15mSnapForAlgo(algoNumber, g_lastTimer1Time);
   if(!BreakdownMidpointEntryAllowed(algoNumber, bdSnap, g_lastTimer1Time))
      return false;

   const BreakdownAlgoDef bd = g_breakdownAlgos[algoSlot];
   const double orderAnchor = BreakdownEntryPriceForAlgo(bd, bdSnap);
   if(orderAnchor <= 0.0)
      return false;
   double brokerTpPrice = 0.0;
   if(bd.tp_enabled)
   {
      brokerTpPrice = FalgoBreakdownPriceAtRangePercent(bdSnap.breakdownLow, bdSnap.startHigh,
         bd.tp_notsecret_range_percent);
      if(brokerTpPrice <= orderAnchor)
         return false;
   }

   FalgoMagicKey planKey;
   if(!FalgoBuildMagicKeyForBreakdownPlacement(algoNumber, FALGO_DIRECTION_LONG_LIMIT, planKey))
      return false;

   const long magic = BuildAlgoMagicNumber(algoNumber, planKey);
   if(!BreakdownUnderMaxOpenPositionsLimit(algoNumber))
      return false;

   const double lot = GetTradeLotForBreakdown();
   if(!PlacePendingFromFalgoMagicBreakdown(magic, orderAnchor, bd.tp_enabled, brokerTpPrice, bd.sl_enabled, bd.sl_points,
      bd.expiry_minutes, lot))
      return false;

   g_breakdownAlgoLastPlacedEndTime[algoSlot] = bdSnap.endTime;
   g_breakdownAlgoLastPlacedStartHigh[algoSlot] = bdSnap.startHigh;
   g_breakdownAlgoLastPlacedBreakdownLow[algoSlot] = bdSnap.breakdownLow;
   BreakdownBumpPlanCountersAfterPlacement(algoNumber, planKey.levelSlot);
   BreakdownRememberPendingPlannedPrice(magic, orderAnchor);
   WriteTradeLogPendingOrderBreakdown(magic, orderAnchor, bd.tp_enabled, brokerTpPrice, bd.sl_enabled, bd.sl_points, bd.expiry_minutes);
   return true;
}

//+------------------------------------------------------------------+
string AlgoBreakdownPlacementBlockReasonFirstFail(const int algoNumber, const int barIdx)
{
   if(BreakdownAlgoSlotIndexByAlgoId(algoNumber) < 0)
      return "algoNotRegistered";
   if(!AlgoProfileEnabled(algoNumber))
      return "profileDisabled";
   const string orderState = BreakdownAlgoOrderStateBlockReason(algoNumber);
   if(orderState != "")
      return orderState;
   if(!BreakdownProfileAllowsPlacementAtTime(g_lastTimer1Time))
   {
      if(!FalgoIsTradingDayAllowedAtTime(g_lastTimer1Time))
         return "tradingDayBanned";
      if(!FalgoIsTradingTimeAllowed(g_lastTimer1Time))
         return "tradingTimeBanned";
      return "profileNoNewOrdersNow";
   }
   if(!BreakdownRulesetPassesCommonForPlacement(algoNumber, barIdx))
   {
      if(!FalgoRulesetPassesCloseBarForAlgo(algoNumber, barIdx))
         return "tradeClosedThisBar";
      if(!BreakdownRulesetPassesDayStops(algoNumber))
         return "lossStopDayLimit";
      const string openLimit = BreakdownMaxOpenPositionsFailLabel(algoNumber);
      if(openLimit != "")
         return openLimit;
      if(BreakdownFamilyBlocksPlacementOnOpenOrPending())
      {
         if(BreakdownHasOpenPositionOnSymbol())
            return "openFalgoPositionFam";
         if(BreakdownHasPendingOrderOnSymbol())
            return "pendingFalgoOrderFam";
         if(g_breakdownFamilyHadCloseThisPipelinePass)
            return "tradeClosedThisPipelineFam";
      }
      const int ruleSlotIdx = BreakdownAlgoSlotIndexByAlgoId(algoNumber);
      if(ruleSlotIdx >= 0)
      {
         const string ruleFail = BreakdownRunRulesFirstFail(ruleSlotIdx, barIdx, g_lastTimer1Time);
         if(ruleFail != "")
            return ruleFail;
      }
      return "rulesetFail";
   }

   const Breakdown15mState bdSnap = Breakdown15mSnapForAlgo(algoNumber, g_lastTimer1Time);
   const string entryBlock = BreakdownMidpointEntryBlockReason(algoNumber, bdSnap, g_lastTimer1Time);
   if(entryBlock != "")
      return entryBlock;

   BreakdownAlgoDef bdAnchor;
   if(!BreakdownAlgoDefForNumber(algoNumber, bdAnchor))
      return "algoNotRegistered";
   const double orderAnchor = BreakdownEntryPriceForAlgo(bdAnchor, bdSnap);
   if(orderAnchor <= 0.0)
      return "noTriggerGreenEntryPrice";
   if(PlacePending_ShouldSkip_BidTooCloseToOrderPrice(orderAnchor, 1.0))
      return StringFormat("bidTooCloseToOrder(%s vs %s)", DoubleToString(g_liveBid, _Digits), DoubleToString(orderAnchor, _Digits));

   return "";
}

//+------------------------------------------------------------------+
void RunBreakdownBabysitOnly()
{
   const bool profOn = BacktestProfileEnabled();
   ulong profT0 = 0;
   if(profOn)
      profT0 = GetMicrosecondCount();
   Babysitf_RunBreakdownOpenPositionsForSymbol();
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_BABYSIT, profT0);
}

//+------------------------------------------------------------------+
void RunBreakdownPlacementOnM1Close(const int barIdx)
{
   const bool profOn = BacktestProfileEnabled();
   ulong profT0 = 0;

   g_breakdownFamilyHadCloseThisPipelinePass = false;
   UpdateBreakdownDayTradeCounts();

   // Same pipeline pass as legacy RunBreakdownTradePipeline: babysit then placement (close-this-bar gate).
   if(profOn)
      profT0 = GetMicrosecondCount();
   Babysitf_RunBreakdownOpenPositionsForSymbol();
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_BABYSIT, profT0);

   if(!BreakdownProfileAllowsPlacementAtTime(g_lastTimer1Time))
      return;
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return;

   RefreshGlobalBreakdown15mSnap(g_lastTimer1Time);
   RefreshOccupiedMagicsCache();
   for(int si = 0; si < g_breakdownAlgoCount; si++)
   {
      if(!g_breakdownAlgos[si].enabled)
         continue;
      if(profOn)
         profT0 = GetMicrosecondCount();
      AlgoTryPlaceBreakdownMidpointOrder(g_breakdownAlgos[si].algo_id, barIdx);
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_BREAKDOWN_PLACEMENT, profT0);
   }
}

//+------------------------------------------------------------------+
int AlgoFamilyRecentBounceLookbackMinutes()
{
   int maxMin = 0;
   for(int i = 0; i < g_algoCount; i++)
   {
      if(g_algos[i].recentBounceCountToday_Minutes > maxMin)
         maxMin = g_algos[i].recentBounceCountToday_Minutes;
   }
   return maxMin;
}

//+------------------------------------------------------------------+
int AlgoFamilyRecentCeilingLookbackMinutes()
{
   int maxMin = 0;
   for(int i = 0; i < g_algoCount; i++)
   {
      if(g_algos[i].recentCeilingCountToday_Minutes > maxMin)
         maxMin = g_algos[i].recentCeilingCountToday_Minutes;
   }
   return maxMin;
}

//+------------------------------------------------------------------+
//| True when today's RTH open is resolved and bar kLast is at/after nominal RTH open (safe to call Gate_Level_AbsDiff_with_RTHO_atLeastX). |
//+------------------------------------------------------------------+
bool Gate_Level_AbsDiff_with_RTHO_guard_RTHO_ready(const int kLast)
{
   if(kLast < 0 || kLast >= g_barsInDay || g_m1DayStart == 0) return false;
   if(!g_todayRTHopenValid) return false;
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   const datetime rthOpenBarTime = g_m1DayStart + GetRthOpenBarOffsetSeconds(dateStr);
   return (g_m1Rates[kLast].time >= rthOpenBarTime);
}

//+------------------------------------------------------------------+
//| Gate_Level_AbsDiff_with_RTHO_atLeastX: |levelPx - RTH open| >= minAbsDiffPoints. Caller MUST only invoke when g_todayRTHopenValid and bar at/after nominal RTH open; else FatalError. |
//+------------------------------------------------------------------+
bool Gate_Level_AbsDiff_with_RTHO_atLeastX(const double levelPx, const int kLast, const double minAbsDiffPoints)
{
   if(kLast < 0 || kLast >= g_barsInDay || g_m1DayStart == 0)
      FatalError("Gate_Level_AbsDiff_with_RTHO_atLeastX: invalid kLast or g_m1DayStart (only call when RTHO is set and bar is at/after nominal RTH open)");
   if(!g_todayRTHopenValid)
      FatalError("Gate_Level_AbsDiff_with_RTHO_atLeastX: g_todayRTHopenValid is false (only call after today's RTH open is resolved)");
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   const datetime rthOpenBarTime = g_m1DayStart + GetRthOpenBarOffsetSeconds(dateStr);
   if(g_m1Rates[kLast].time < rthOpenBarTime)
      FatalError("Gate_Level_AbsDiff_with_RTHO_atLeastX: bar time before nominal RTH open (only call when current bar is at/after RTH open)");
   return (MathAbs(levelPx - g_todayRTHopen) >= minAbsDiffPoints);
}

//+------------------------------------------------------------------+
//| Gate_Level_AbsDiff_with_IBH_atLeastX: |levelPx - IB high| >= minAbsDiffPoints. Caller MUST only invoke when IB is complete at kLast (g_IBhighAtBar[kLast].hasValue); else FatalError. |
//+------------------------------------------------------------------+
bool Gate_Level_AbsDiff_with_IBH_atLeastX(const double levelPx, const int kLast, const double minAbsDiffPoints)
{
   if(kLast < 0 || kLast >= g_barsInDay)
      FatalError("Gate_Level_AbsDiff_with_IBH_atLeastX: invalid kLast (only call when IBH is ready at kLast)");
   double ibh;
   if(!GetIBhighAtBar(kLast, ibh))
      FatalError("Gate_Level_AbsDiff_with_IBH_atLeastX: IB high not set at kLast (only call after last IB minute has passed)");
   return (MathAbs(levelPx - ibh) >= minAbsDiffPoints);
}

//+------------------------------------------------------------------+
//| Gate_Level_Abovemidpoint: true when levelPx is strictly above session-range price midpoint (day H+L)/2 at kLast. |
//+------------------------------------------------------------------+
bool Gate_Level_Abovemidpoint(const int kLast, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!g_sessionRangeMidpointAtBar[kLast].hasValue) return false;
   const double mid = g_sessionRangeMidpointAtBar[kLast].value;
   return (levelPx > mid);
}

//+------------------------------------------------------------------+
//| Gate_Level_Belowmidpoint: true when levelPx is strictly below session-range price midpoint (day H+L)/2 at kLast. |
//+------------------------------------------------------------------+
bool Gate_Level_Belowmidpoint(const int kLast, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!g_sessionRangeMidpointAtBar[kLast].hasValue) return false;
   const double mid = g_sessionRangeMidpointAtBar[kLast].value;
   return (levelPx < mid);
}

//+------------------------------------------------------------------+
//| Gap down day: today's RTH open < prior day RTH close (PDC). Same rule as dayPriceStat_and_gapstat_log hasGapDown once logged; uses g_todayRTHopen so valid after RTH open bar exists. |
//+------------------------------------------------------------------+
bool Gate_Day_HasGapDown()
{
   if(!g_todayRTHopenValid || g_staticMarketContext.PDCpreviousDayRTHClose <= 0.0) return false;
   return (g_todayRTHopen < g_staticMarketContext.PDCpreviousDayRTHClose);
}

//+------------------------------------------------------------------+
//| Gap up day: RTH open > PDC. Same as dayPriceStat_and_gapstat_log hasGapUp. |
//+------------------------------------------------------------------+
bool Gate_Day_HasGapUp()
{
   if(!g_todayRTHopenValid || g_staticMarketContext.PDCpreviousDayRTHClose <= 0.0) return false;
   return (g_todayRTHopen > g_staticMarketContext.PDCpreviousDayRTHClose);
}

//+------------------------------------------------------------------+
double FalgoOpenGapRangePts()
{
   if(!g_todayRTHopenValid || g_staticMarketContext.PDCpreviousDayRTHClose <= 0.0)
      return 0.0;
   return MathAbs(g_todayRTHopen - g_staticMarketContext.PDCpreviousDayRTHClose);
}

//+------------------------------------------------------------------+
bool Gate_GapRangePts_AboveX(const double minPtsExclusive)
{
   return (FalgoOpenGapRangePts() > minPtsExclusive);
}

//+------------------------------------------------------------------+
bool Gate_GapFillPc_BelowX(const int barIdx, const double maxPcExclusive)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || g_m1DayStart == 0)
      return false;
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   double pct = 0.0;
   if(!GetGapFillSoFarAtBar(barIdx, g_m1DayStart, dateStr, pct))
      return false;
   return (pct < maxPcExclusive);
}

//+------------------------------------------------------------------+
bool Gate_RthoTertiaryLevelReadyAtBar(const int barIdx)
{
   return (FalgoTodayRthOpenTertiaryExpandedIdx(barIdx) >= 0);
}

bool Gate_Day_DayBrokePDH_is_TRUE(const int kLast)
{
   return g_dayBrokePDHAtBar[kLast];
}
bool Gate_Day_DayBrokePDH_is_FALSE(const int kLast)
{
   return !g_dayBrokePDHAtBar[kLast];
}

bool Gate_Day_DayBrokePDL_is_TRUE(const int kLast)
{
   return g_dayBrokePDLAtBar[kLast];
}
bool Gate_Day_DayBrokePDL_is_FALSE(const int kLast)
{
   return !g_dayBrokePDLAtBar[kLast];
}

//+------------------------------------------------------------------+
//| Gap-fill state at bar kLast from g_gapFillSoFarAtBar (same % as pullinghistory_a/b column gap_fill_pc). |
//| "unknown" if before RTH open or value not computed; "filled" if pct >= 90; else "unfilled". |
//+------------------------------------------------------------------+
string GetGapFillStatus_atBar(const int kLast)
{
   if(g_m1DayStart == 0) return "unknown";
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   double pct = 0.0;
   if(!GetGapFillSoFarAtBar(kLast, g_m1DayStart, dateStr, pct)) return "unknown";
   if(pct >= 90.0) return "filled";
   return "unfilled";
}

//+------------------------------------------------------------------+
//| True if GetGapFillStatus_atBar(kLast) == "filled" (gap fill % >= 90 at that bar). |
//+------------------------------------------------------------------+
bool Gate_GapFilled_atBar_TOTEST(const int kLast)
{
   return (GetGapFillStatus_atBar(kLast) == "filled");
}

//+------------------------------------------------------------------+
//| True if GetGapFillStatus_atBar(kLast) == "unfilled" (known pct < 90 at that bar). False if "filled" or "unknown". |
//+------------------------------------------------------------------+
bool Gate_GapUnfilled_atBar_TOTEST(const int kLast)
{
   return (GetGapFillStatus_atBar(kLast) == "unfilled");
}


//+------------------------------------------------------------------+
//| Helper to log context before order placement (Magic, Level, Bid/Ask, Streaks). |
//+------------------------------------------------------------------+
void LogPreOrderContext(long magic, double levelPrice, double orderPrice, string type, int expirationMin)
{
   int levelIdx = FindExpandedLevelIndexByPrice(levelPrice);
   int kLast = g_barsInDay - 1;
   int sAbove = -1, sBelow = -1;
   if(levelIdx >= 0 && kLast >= 0 && kLast < MAX_BARS_IN_DAY)
   {
      sAbove = g_cleanStreakAbove[levelIdx][kLast];
      sBelow = g_cleanStreakBelow[levelIdx][kLast];
   }

   // Look up offset from Falgo magic when applicable
   string offsetStr = "N/A";
   if(IsAnyAlgoFamilyCompositeMagic(magic))
   {
      FalgoMagicKey fk = ParseFalgoMagic(magic);
      offsetStr = DoubleToString((double)fk.offset_tenths / 10.0, 1);
   }

   Print(StringFormat("Attempting %s Magic=%s Level=%s Offset=%s OrderPrice=%s ExpMin=%d Bid=%s Ask=%s StreakAbove=%d StreakBelow=%d",
         type, IntegerToString(magic), DoubleToString(levelPrice, _Digits), offsetStr, DoubleToString(orderPrice, _Digits), expirationMin,
         DoubleToString(g_liveBid, _Digits), DoubleToString(g_liveAsk, _Digits),
         sAbove, sBelow));
}

//+------------------------------------------------------------------+
//| If |g_liveBid − orderPrice| < minRaw, do not send pending (avoids Invalid price / too-tight vs last bid). Raw symbol price units. |
//+------------------------------------------------------------------+
bool PlacePending_ShouldSkip_BidTooCloseToOrderPrice(const double orderPrice, const double minRaw = 1.0)
{
   return (MathAbs(g_liveBid - orderPrice) < minRaw);
}


//+------------------------------------------------------------------+
//| Falgo pending breakdown: buy limit at computed midpoint entry price. |
//+------------------------------------------------------------------+
bool PlacePendingFromFalgoMagicBreakdown(const long magic, const double orderPrice, const bool tpEnabled,
   const double tpPriceAbs, const bool slEnabled, const double slPoints, const int expirationMin, const double lot)
{
   if(!IsBreakdownFamilyCompositeMagic(magic))
      return false;
   if(orderPrice <= 0.0)
      return false;

   const double orderNorm = NormalizeDouble(orderPrice, _Digits);
   double tpNorm = 0.0;
   if(tpEnabled)
   {
      if(tpPriceAbs <= 0.0)
         return false;
      tpNorm = NormalizeDouble(tpPriceAbs, _Digits);
      if(tpNorm <= orderNorm)
         return false;
   }
   if(PlacePending_ShouldSkip_BidTooCloseToOrderPrice(orderNorm, 1.0))
      return false;

   double slNorm = 0.0;
   if(slEnabled && slPoints > 0.0)
      slNorm = NormalizeDouble(orderNorm - PointSized(slPoints), _Digits);

   datetime expiration = TimeCurrent() + expirationMin * 60;
   const string comment = "Falgo_breakdown";
   ExtTrade.SetExpertMagicNumber(magic);
   LogPreOrderContext(magic, orderNorm, orderNorm, "BuyLimit", expirationMin);
   const bool ok = ExtTrade.BuyLimit(lot, orderNorm, _Symbol, slNorm, tpNorm, ORDER_TIME_SPECIFIED, expiration, comment);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   return ok;
}

//+------------------------------------------------------------------+
void WriteTradeLogPendingOrderBreakdown(const long magic, const double orderPrice, const bool tpEnabled,
   const double tpPriceAbs, const bool slEnabled, const double slPoints, const int expirationMin)
{
   if(!IsBreakdownFamilyCompositeMagic(magic))
      return;
   string magicStrForLogFilename = GetMagicStrForLogFilename(magic);
   if(StringLen(magicStrForLogFilename) == 0)
      return;
   ulong orderTicket = ExtTrade.ResultOrder();
   datetime eventTime = g_lastTimer1Time;
   if(orderTicket > 0 && OrderSelect(orderTicket))
      eventTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
   const double orderNorm = NormalizeDouble(orderPrice, _Digits);
   double tpNorm = 0.0;
   if(tpEnabled && tpPriceAbs > 0.0)
      tpNorm = NormalizeDouble(tpPriceAbs, _Digits);
   double slNorm = 0.0;
   if(slEnabled && slPoints > 0.0)
      slNorm = NormalizeDouble(orderNorm - PointSized(slPoints), _Digits);
   WriteTradeLog(magicStrForLogFilename, "pending_created", eventTime, "buy_limit", orderNorm, slNorm, tpNorm,
      expirationMin, orderTicket, 0, 0, (ENUM_DEAL_REASON)0, "Falgo_breakdown", magic);
}

//+------------------------------------------------------------------+
//| Build levels[] from g_levels[] (CSV). One Level per row; baseName = start_tag, validFrom/To from start/end. |
//+------------------------------------------------------------------+
void BuildLevelsFromCSV()
{
   ArrayResize(levels, g_levelsTotalCount);
   for(int levelIdx = 0; levelIdx < g_levelsTotalCount; levelIdx++)
   {
      levels[levelIdx].baseName  = g_levels[levelIdx].startStr + "_" + g_levels[levelIdx].tag;
      levels[levelIdx].price     = g_levels[levelIdx].levelPrice;
      levels[levelIdx].validFrom = StringToTime(g_levels[levelIdx].startStr + " 00:00");
      levels[levelIdx].validTo   = StringToTime(g_levels[levelIdx].endStr + " 23:59");
      levels[levelIdx].tagsCSV   = g_levels[levelIdx].categories;
      levels[levelIdx].count     = 0;
      levels[levelIdx].dailyBias = 0;
      levels[levelIdx].biasSetToday = false;
      levels[levelIdx].lastBiasDate = 0;
      levels[levelIdx].logRawEv_fileHandle = INVALID_HANDLE;
      levels[levelIdx].candlesBreakLevelCount = 0;
      levels[levelIdx].recoverCount = 0;
      levels[levelIdx].consecutiveRecoverCandles = 0;
   }
}

void AddLevel(string baseName, double price, string from, string to, string tagsCSV)
{
   int newIndex = ArraySize(levels);
   ArrayResize(levels, newIndex + 1);

   levels[newIndex].baseName  = baseName;
   levels[newIndex].price     = price;
   levels[newIndex].validFrom = StringToTime(from);
   levels[newIndex].validTo   = StringToTime(to);
   levels[newIndex].tagsCSV   = tagsCSV;
   levels[newIndex].count     = 0;
   levels[newIndex].dailyBias = 0;
   levels[newIndex].biasSetToday = false;
   levels[newIndex].lastBiasDate = 0;
   levels[newIndex].logRawEv_fileHandle = INVALID_HANDLE;
   levels[newIndex].candlesBreakLevelCount = 0;
   levels[newIndex].recoverCount = 0;
   levels[newIndex].consecutiveRecoverCandles = 0;
}

//+------------------------------------------------------------------+
//| MT5 minimal price step for _Symbol (SYMBOL_POINT). Not a PointSized point. |
//+------------------------------------------------------------------+
double Instrument_PointStepSize()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
//| Custom “point” (e.g. 6895.5→6896.5 = 1): g_trade / magic display units → price distance. |
//| Formula: points × 10 × Instrument_PointStepSize() (legacy ×10 encoding). |
//+------------------------------------------------------------------+
double PointSized(double points)
{
   return points * 10.0 * Instrument_PointStepSize();
}

//+------------------------------------------------------------------+
//| Open file for append (try existing first, else create). Returns handle or INVALID_HANDLE. |
//+------------------------------------------------------------------+
int OpenOrCreateForAppend(string path)
{
   int fileHandle = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_READ | FILE_SHARE_READ);
   if(fileHandle != INVALID_HANDLE)
      FileSeek(fileHandle, 0, SEEK_END);
   else
      fileHandle = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_SHARE_READ);
   return fileHandle;
}

//+------------------------------------------------------------------+
//| One terminal pass: mark algo slots 100..999 with open position or pending on _Symbol. Call once per timer tick before placement. |
//+------------------------------------------------------------------+
void RefreshOccupiedMagicsCache()
{
   for(int a = MAGIC_ALGO_FAMILY_SLOT_MIN; a <= MAGIC_ALGO_FAMILY_SLOT_MAX; a++)
      g_occupiedAlgoFamilySlots[a] = false;

   for(int posIdx = PositionsTotal() - 1; posIdx >= 0; posIdx--)
   {
      if(!ExtPositionInfo.SelectByIndex(posIdx)) continue;
      if(ExtPositionInfo.Symbol() != _Symbol) continue;
      const long m = ExtPositionInfo.Magic();
      if(!IsAnyAlgoFamilyCompositeMagic(m)) continue;
      const int algoNumber = AlgoFamilyMagicNumber(m);
      if(algoNumber >= MAGIC_ALGO_FAMILY_SLOT_MIN && algoNumber <= MAGIC_ALGO_FAMILY_SLOT_MAX)
         g_occupiedAlgoFamilySlots[algoNumber] = true;
   }
   for(int orderIdx = OrdersTotal() - 1; orderIdx >= 0; orderIdx--)
   {
      if(!ExtOrderInfo.SelectByIndex(orderIdx)) continue;
      if(ExtOrderInfo.Symbol() != _Symbol) continue;
      const long m = ExtOrderInfo.Magic();
      if(!IsAnyAlgoFamilyCompositeMagic(m)) continue;
      const int algoNumber = AlgoFamilyMagicNumber(m);
      if(algoNumber >= MAGIC_ALGO_FAMILY_SLOT_MIN && algoNumber <= MAGIC_ALGO_FAMILY_SLOT_MAX)
         g_occupiedAlgoFamilySlots[algoNumber] = true;
   }
}

//+------------------------------------------------------------------+
//| After RefreshOccupiedMagicsCache: true when this algo has no open/pending on _Symbol. |
//+------------------------------------------------------------------+
bool CanPlaceNewOrderForAlgo_Cached(const int algoNumber)
{
   if(algoNumber < MAGIC_ALGO_FAMILY_SLOT_MIN || algoNumber > MAGIC_ALGO_FAMILY_SLOT_MAX)
      return false;
   return !g_occupiedAlgoFamilySlots[algoNumber];
}

//+------------------------------------------------------------------+
//| Close any algo-family position open longer than minutes. Sets trade magic so OUT deal pairs with IN. |
//+------------------------------------------------------------------+
void CloseAnyEAPositionThatIsXMinutesOld(int minutes)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!ExtPositionInfo.SelectByIndex(i)) continue;
      if(ExtPositionInfo.Symbol() != _Symbol) continue;
      long posMagic = ExtPositionInfo.Magic();
      if(!IsAnyAlgoFamilyCompositeMagic(posMagic)) continue;
      if(g_lastTimer1Time - ExtPositionInfo.Time() <= (datetime)(minutes * 60)) continue;
      const ulong posTicket = ExtPositionInfo.Ticket();
      const int telSlot = FalgoOpenTelemetryFindSlotByTicket(posTicket);
      const double profitPts = FalgoOpenPositionProfitPoints();
      const double accountProfit = FalgoSelectedPositionAccountProfit();
      ExtTrade.SetExpertMagicNumber((ulong)posMagic);
      const bool closed = ExtTrade.PositionClose(posTicket);
      ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
      if(closed)
         FalgoAfterFamilyPositionClosed(posMagic, profitPts, accountProfit, telSlot);
   }
}

//+------------------------------------------------------------------+
//| B_TradeLog file tag from magic prefix (algo10, algo16, …); "" if not algo-family magic. |
//+------------------------------------------------------------------+
string GetMagicStrForLogFilename(long magic)
{
   if(!IsAnyAlgoFamilyCompositeMagic(magic))
      return "";
   const int algoNumber = AlgoFamilyMagicNumber(magic);
   if(algoNumber < MAGIC_ALGO_FAMILY_SLOT_MIN || algoNumber > MAGIC_ALGO_FAMILY_SLOT_MAX)
      return "";
   return "algo" + IntegerToString(algoNumber);
}

//+------------------------------------------------------------------+
//| Build B_TradeLog filename: YYYY.MM.DD_B_TradeLog_algoN.csv |
//+------------------------------------------------------------------+
string BuildTradeLogFileName(const string magicStrForLogFilename, datetime forTime)
{
   if(StringLen(magicStrForLogFilename) == 0) return "";
   string dateStr = TimeToString(forTime, TIME_DATE);
   return StringFormat("%s_B_TradeLog_%s.csv", dateStr, magicStrForLogFilename);
}

//+------------------------------------------------------------------+
//| Convert ORDER_TYPE to log string (buy_limit, sell_limit, market_buy, etc.) |
//+------------------------------------------------------------------+
string OrderTypeToKindString(ENUM_ORDER_TYPE orderType)
{
   switch(orderType)
   {
      case ORDER_TYPE_BUY:       return "market_buy";
      case ORDER_TYPE_SELL:      return "market_sell";
      case ORDER_TYPE_BUY_LIMIT: return "buy_limit";
      case ORDER_TYPE_SELL_LIMIT: return "sell_limit";
      case ORDER_TYPE_BUY_STOP:  return "buy_stop";
      case ORDER_TYPE_SELL_STOP: return "sell_stop";
      default: return "unknown";
   }
}

//+------------------------------------------------------------------+
//| Return a summary string containing account statistics such as    |
//| open positions, pending orders, history orders, and balance.     |
//+------------------------------------------------------------------+
string AccountSummary()
{
   int posCount   = PositionsTotal();
   int ordCount   = OrdersTotal();
   int histOrders = HistoryOrdersTotal();
   int histDeals  = HistoryDealsTotal();
   double bal     = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   // additional metrics (free margin, margin level, etc.) can be added if needed
   return StringFormat("(pos=%d pending=%d histOrd=%d histDeals=%d bal=%.2f eq=%.2f)",
                       posCount, ordCount, histOrders, histDeals, bal, equity);
}

//+------------------------------------------------------------------+
//| Write daily summary files in plain text format                        |
//| Creates separate files for different data types                      |
//+------------------------------------------------------------------+
void WriteDailySummary()
{
   datetime now = g_lastTimer1Time;
   string dateStr = TimeToString(now, TIME_DATE);
   
   string activeLevelsFile = dateStr + "-Day_activeLevels.csv";
   int fileHandle1 = FileOpen(activeLevelsFile, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandle1 == INVALID_HANDLE)
      FatalError("WriteDailySummary: could not open " + activeLevelsFile);
   {
      FileWrite(fileHandle1, "levelNo", "name", "price", "count", "contacts", "bias", "bounces", "levelTag", "levelCats");
      datetime today = now - (now % 86400);
      int validIndices[];
      ArrayResize(validIndices, ArraySize(levels));
      int validCount = 0;
      for(int i = 0; i < ArraySize(levels); i++)
      {
         if(levels[i].validFrom <= today && levels[i].validTo >= today)
            validIndices[validCount++] = i;
      }
      for(int a = 0; a < validCount - 1; a++)
         for(int b = a + 1; b < validCount; b++)
            if(levels[validIndices[a]].price < levels[validIndices[b]].price)
            {
               int t = validIndices[a];
               validIndices[a] = validIndices[b];
               validIndices[b] = t;
            }
      for(int k = 0; k < validCount; k++)
      {
         int i = validIndices[k];
         string tagStr = (i < g_levelsTotalCount) ? g_levels[i].tag : "";
         string catsStr = (i < g_levelsTotalCount) ? g_levels[i].categories : "";
         int dayBounce = 0, dayCeiling = 0, dayProx = 0, dayContact = 0, sinceB = 0, sinceC = 0;
         if(g_barsInDay > 0)
            AlgoFamilyDayLevelStatsForLevelAsOfTime(levels[i].price, g_m1Rates[g_barsInDay - 1].time + 60,
               dayBounce, dayCeiling, dayProx, dayContact, sinceB, sinceC);
         FileWrite(fileHandle1, IntegerToString(i), levels[i].baseName, DoubleToString(levels[i].price, _Digits),
                   IntegerToString(levels[i].count), IntegerToString(dayContact),
                   DoubleToString(levels[i].dailyBias, 0), IntegerToString(dayBounce), tagStr, catsStr);
      }
      FileClose(fileHandle1);
   }
   
   string accountFile = dateStr + "-Day_EOD_accountSummary.txt";
   int fileHandle2 = FileOpen(accountFile, FILE_WRITE | FILE_TXT | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandle2 == INVALID_HANDLE)
      FatalError("WriteDailySummary: could not open " + accountFile);
   {
      EODpulled_balance       = AccountInfoDouble(ACCOUNT_BALANCE);
      EODpulled_equity       = AccountInfoDouble(ACCOUNT_EQUITY);
      EODpulled_freeMargin  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      EODpulled_marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      EODpulled_openPositions = PositionsTotal();
      EODpulled_pendingOrders = OrdersTotal();
      FileWrite(fileHandle2, "balance=" + DoubleToString(EODpulled_balance, 2));
      FileWrite(fileHandle2, "equity=" + DoubleToString(EODpulled_equity, 2));
      FileWrite(fileHandle2, "freeMargin=" + DoubleToString(EODpulled_freeMargin, 2));
      FileWrite(fileHandle2, "marginLevel=" + DoubleToString(EODpulled_marginLevel, 1));
      FileWrite(fileHandle2, "openPositions=" + IntegerToString(EODpulled_openPositions));
      FileWrite(fileHandle2, "pendingOrders=" + IntegerToString(EODpulled_pendingOrders));
      FileClose(fileHandle2);
   }
   
   string ordersFile = dateStr + "-not_from_globals_AllHistoryOrders.csv";
   int fileHandle3 = FileOpen(ordersFile, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandle3 == INVALID_HANDLE)
      FatalError("WriteDailySummary: could not open " + ordersFile);
   {
      FileWrite(fileHandle3, "ticket", "symbol", "magic", "timeSetup", "state", "type", "reason", "volume", "priceOpen", "priceCurrent", "priceStopLoss", "priceTakeProfit", "timeExpiration", "activationPrice", "comment");
      HistorySelect(0, g_lastTimer1Time);
      int totalHist = HistoryOrdersTotal();
      for(int i=0; i<totalHist; i++)
      {
         ulong ticket = HistoryOrderGetTicket(i);
         if(ticket == 0) continue;
         
         datetime orderTime = (datetime)HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP);
         if(orderTime < dateWhenAlgoTradeStarted) continue;
         
         FileWrite(fileHandle3, IntegerToString((long)ticket), HistoryOrderGetString(ticket, ORDER_SYMBOL),
                   IntegerToString((long)HistoryOrderGetInteger(ticket, ORDER_MAGIC)),
                   TimeToString((datetime)HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP), TIME_DATE|TIME_SECONDS),
                   EnumToString((ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket, ORDER_STATE)),
                   EnumToString((ENUM_ORDER_TYPE)HistoryOrderGetInteger(ticket, ORDER_TYPE)),
                   EnumToString((ENUM_ORDER_REASON)HistoryOrderGetInteger(ticket, ORDER_REASON)),
                   DoubleToString(HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL), 2),
                   DoubleToString(HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN), _Digits),
                   DoubleToString(HistoryOrderGetDouble(ticket, ORDER_PRICE_CURRENT), _Digits),
                   DoubleToString(HistoryOrderGetDouble(ticket, ORDER_SL), _Digits),
                   DoubleToString(HistoryOrderGetDouble(ticket, ORDER_TP), _Digits),
                   TimeToString((datetime)HistoryOrderGetInteger(ticket, ORDER_TIME_EXPIRATION), TIME_DATE|TIME_SECONDS),
                   DoubleToString(HistoryOrderGetDouble(ticket, ORDER_PRICE_STOPLIMIT), _Digits),
                   HistoryOrderGetString(ticket, ORDER_COMMENT));
      }
      FileClose(fileHandle3);
   }
   
   string dealsFile = dateStr + "-not_from_globals_AllHistoryDeals.csv";
   int fileHandle4 = FileOpen(dealsFile, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandle4 == INVALID_HANDLE)
      FatalError("WriteDailySummary: could not open " + dealsFile);
   {
      FileWrite(fileHandle4, "ticket", "symbol", "magic", "time", "entry", "type", "reason", "volume", "price", "profit", "ticketOrder", "comment");
      int totalDeals = HistoryDealsTotal();
      for(int i=0; i<totalDeals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         
         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         if(dealTime < dateWhenAlgoTradeStarted) continue;
         
         FileWrite(fileHandle4, IntegerToString((long)ticket), HistoryDealGetString(ticket, DEAL_SYMBOL),
                   IntegerToString((long)HistoryDealGetInteger(ticket, DEAL_MAGIC)),
                   TimeToString((datetime)HistoryDealGetInteger(ticket, DEAL_TIME), TIME_DATE|TIME_SECONDS),
                   EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY)),
                   EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE)),
                   EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON)),
                   DoubleToString(HistoryDealGetDouble(ticket, DEAL_VOLUME), 2),
                   DoubleToString(HistoryDealGetDouble(ticket, DEAL_PRICE), _Digits),
                   DoubleToString(HistoryDealGetDouble(ticket, DEAL_PROFIT), 2),
                   IntegerToString((long)HistoryDealGetInteger(ticket, DEAL_ORDER)),
                   HistoryDealGetString(ticket, DEAL_COMMENT));
      }
      FileClose(fileHandle4);
   }
}

//| magicStrForLogFilename: algo tag (algo10, …) → (date)_B_TradeLog_<tag>.csv (see GetMagicStrForLogFilename). |
//| comment: custom comment string (optional) |
//| magic: trade magic number when available (optional, 0 = omit from log row) |
//+------------------------------------------------------------------+
void WriteTradeLog(const string magicStrForLogFilename, const string eventType, datetime eventTime,
                  const string orderKind = "", double orderPrice = 0, double slPrice = 0, double tpPrice = 0, int expirationMinutes = 0,
                  ulong orderTicket = 0, ulong dealTicket = 0, ulong positionTicket = 0,
                  ENUM_DEAL_REASON dealReason = (ENUM_DEAL_REASON)0, const string comment = "", long magic = 0)
{
   if(!bigflipper_log_B_TradeLog || !finalLog_TradeLog) return;
   string fname = BuildTradeLogFileName(magicStrForLogFilename, eventTime);
   if(StringLen(fname) == 0) return;

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   int fileHandle = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandle == INVALID_HANDLE)
      fileHandle = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandle == INVALID_HANDLE)
      FatalError("WriteTradeLog: could not open " + fname);
   FileSeek(fileHandle, 0, SEEK_END);
   if(FileTell(fileHandle) == 0)
      FileWrite(fileHandle, "time", "balance", "equity", "orderKind", "orderPrice", "eventType", "tp", "sl", "exp", "orderTicket", "dealTicket", "positionTicket", "dealReason", "comment", "magic");
   FileWrite(fileHandle, TimeToString(eventTime, TIME_DATE|TIME_SECONDS), DoubleToString(bal, 2), DoubleToString(equity, 2),
             orderKind, (orderPrice > 0 ? DoubleToString(NormalizeDouble(orderPrice, _Digits), _Digits) : ""), eventType,
             (tpPrice > 0 ? DoubleToString(NormalizeDouble(tpPrice, _Digits), _Digits) : ""), (slPrice > 0 ? DoubleToString(NormalizeDouble(slPrice, _Digits), _Digits) : ""),
             (expirationMinutes > 0 ? IntegerToString(expirationMinutes) : ""),
             (orderTicket > 0 ? IntegerToString((long)orderTicket) : ""), (dealTicket > 0 ? IntegerToString((long)dealTicket) : ""), (positionTicket > 0 ? IntegerToString((long)positionTicket) : ""),
             (dealReason != (ENUM_DEAL_REASON)0 ? IntegerToString((int)dealReason) : ""), comment, IntegerToString((long)magic));
   FileClose(fileHandle);
}

//+------------------------------------------------------------------+
//| OnInit: g_global_base_trade_size × one_lot × max concurrent aim must not exceed PLN budget. |
//+------------------------------------------------------------------+
void ValidateBaseTradeSizeVsAccountBudgetOnInit()
{
   const int    max_trade_count_aim_for = 15;
   const double requiredPln = g_global_base_trade_size * one_lot_equals_xPLN * (double)max_trade_count_aim_for;
   if(requiredPln > ACCOUNT_SIZE_PLN_FOR_TRADE_SIZE)
      FatalError(StringFormat(
         "Base trade size vs account (PLN): g_global_base_trade_size=%s × one_lot_equals_xPLN=%.0f × max_trade_count_aim_for=%d = %s exceeds ACCOUNT_SIZE_PLN_FOR_TRADE_SIZE=%s. Lower g_global_base_trade_size or raise ACCOUNT_SIZE_PLN_FOR_TRADE_SIZE.",
         DoubleToString(g_global_base_trade_size, 4), one_lot_equals_xPLN, max_trade_count_aim_for,
         DoubleToString(requiredPln, 2), DoubleToString(ACCOUNT_SIZE_PLN_FOR_TRADE_SIZE, 2)));
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(g_global_base_trade_size > TRADE_VARIANT_COUNT_MAX_LOTSIZE)
      FatalError(StringFormat(
         "g_global_base_trade_size %s exceeds TRADE_VARIANT_COUNT_MAX_LOTSIZE (%s). Lower base lot or raise the cap.",
         DoubleToString(g_global_base_trade_size, 4),
         DoubleToString((double)TRADE_VARIANT_COUNT_MAX_LOTSIZE, 2)));

   Print("aleksik2 (breakdown + level data logging) initialized.");
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);

   ValidateMagicCompositionOnInit();
   FalgoInitPerAlgoTelemetryDayState();
   BreakdownResetTradeLifetimeRunLogsOnInit();
   BreakdownResetAllBreakdownsAuditLogsOnInit();
   BreakdownGatesLogInitFileHandles();
   BuyHoldBenchmarkResetOnInit();
   g_m1BarCloseTerminalWasConnected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);

   EventSetTimer(1);   // 1 second timer for candle-close detection

   g_liveBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_liveAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(!LoadCalendar())
      Print("Calendar file not loaded: ", InpCalendarFile, " (place CSV in Terminal/Common/Files)");
   else
      Print("Calendar loaded: ", g_calendarCount, " rows from ", InpCalendarFile);

   datetime dayStartInit = TimeCurrent() - (TimeCurrent() % 86400);
   string todayStrInit = TimeToString(dayStartInit, TIME_DATE);
   if(!LoadLevelsForDate(todayStrInit))
   {
      Print("Levels file not loaded: ", InpLevelsFile, " (place CSV in Terminal/Common/Files)");
      return(INIT_FAILED);
   }
   g_levelsLoadedForDate = todayStrInit;
   Print("Levels loaded for ", todayStrInit, ": ", g_levelsTotalCount, " rows from ", InpLevelsFile);
   BuildLevelsFromCSV();
   RefreshAlgoFamilyDayStartWeekPerspective(TimeCurrent());

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Logic: price analysis vs levels → if trade triggers, try to place → if place succeeds, log it. |
//| Also log filled/TP/SL when broker notifies (OnTradeTransaction).   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_ORDER_UPDATE && trans.order > 0)
   {
      HandleOrderUpdate(trans);
      return;
   }

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
   {
      HandleDealAdd(trans);
      return;
   }
}

//+------------------------------------------------------------------+
void HandleOrderUpdate(const MqlTradeTransaction& trans)
{
   if(!HistoryOrderSelect(trans.order)) return;
   if(HistoryOrderGetString(trans.order, ORDER_SYMBOL) != _Symbol) return;
   if((ENUM_ORDER_STATE)HistoryOrderGetInteger(trans.order, ORDER_STATE) != ORDER_STATE_FILLED) return;

   string magicStrForLogFilename = GetMagicStrForLogFilename(HistoryOrderGetInteger(trans.order, ORDER_MAGIC));
   if(StringLen(magicStrForLogFilename) == 0) return;

   datetime fillTime = (datetime)HistoryOrderGetInteger(trans.order, ORDER_TIME_DONE);
   string kindStr = OrderTypeToKindString((ENUM_ORDER_TYPE)HistoryOrderGetInteger(trans.order, ORDER_TYPE));
   long orderMagic = HistoryOrderGetInteger(trans.order, ORDER_MAGIC);
   WriteTradeLog(magicStrForLogFilename, "filled", fillTime, kindStr, 0, 0, 0, 0, trans.order, 0, 0, (ENUM_DEAL_REASON)0, "", orderMagic);
}

//+------------------------------------------------------------------+
void HandleDealAdd(const MqlTradeTransaction& trans)
{
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

   if(entry == DEAL_ENTRY_IN)
   {
      HandleEntryDeal(trans);
      return;
   }

   HandleExitDeal(trans);
}

//+------------------------------------------------------------------+
void HandleEntryDeal(const MqlTradeTransaction& trans)
{
   ulong orderTicket = HistoryDealGetInteger(trans.deal, DEAL_ORDER);
   string comment = "";
   string kindStr = "unknown";

   if(orderTicket > 0 && HistoryOrderSelect(orderTicket))
   {
      comment = HistoryOrderGetString(orderTicket, ORDER_COMMENT);
      kindStr = OrderTypeToKindString((ENUM_ORDER_TYPE)HistoryOrderGetInteger(orderTicket, ORDER_TYPE));
   }
   else
   {
      // Entry deal always has an order in MT5; if order missing, leave comment empty and infer kind from deal type only
      kindStr = ((ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? "market_buy" : "market_sell";
   }

   string magicStrForLogFilename = GetMagicStrForLogFilename(HistoryDealGetInteger(trans.deal, DEAL_MAGIC));
   if(StringLen(magicStrForLogFilename) == 0) return;

   datetime fillTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   if(fillTime == 0) fillTime = g_lastTimer1Time;
   double fillPrice = 0;
   if(orderTicket > 0 && HistoryOrderSelect(orderTicket))
      fillPrice = HistoryOrderGetDouble(orderTicket, ORDER_PRICE_OPEN);
   if(fillPrice == 0) fillPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);

   long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   const ulong positionId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   BreakdownLogTradeOpenedLifetime(positionId, dealMagic, fillTime, fillPrice, orderTicket);
   WriteTradeLog(magicStrForLogFilename, "filled", fillTime, kindStr, fillPrice, 0, 0, 0, orderTicket, trans.deal, 0, (ENUM_DEAL_REASON)0, comment, dealMagic);
}

//+------------------------------------------------------------------+
void HandleExitDeal(const MqlTradeTransaction& trans)
{
   ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
   // Log TP, SL, and EA-initiated close (DEAL_REASON_EXPERT)
   bool isTpSl = (reason == DEAL_REASON_TP || reason == DEAL_REASON_SL);
   bool isExpertClose = (reason == DEAL_REASON_EXPERT);
   if(!isTpSl && !isExpertClose) return;

   const double closePrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);

   ulong posId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(posId == 0) return;

   datetime closeTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   if(closeTime == 0) closeTime = g_lastTimer1Time;

   if(!HistorySelectByPosition((long)posId)) return;

   string comment = "";
   ulong entryOrderTicket = 0;
   long entryMagic = 0;
   int total = HistoryDealsTotal();
   for(int j = total - 1; j >= 0; j--)
   {
      ulong dealTicket = HistoryDealGetTicket(j);
      if(dealTicket == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
      entryOrderTicket = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
      entryMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      break;
   }

   if(IsBreakdownFamilyCompositeMagic(entryMagic))
      BreakdownLogTradeClosedLifetime(posId, entryMagic, closeTime, closePrice, reason);

   string magicStrForLogFilename = GetMagicStrForLogFilename(entryMagic);
   if(StringLen(magicStrForLogFilename) == 0) return;

   string kindStr = "";
   if(entryOrderTicket > 0 && HistoryOrderSelect(entryOrderTicket))
      kindStr = OrderTypeToKindString((ENUM_ORDER_TYPE)HistoryOrderGetInteger(entryOrderTicket, ORDER_TYPE));

   string eventType = "sl";
   if(reason == DEAL_REASON_TP) eventType = "tp";
   else if(reason == DEAL_REASON_EXPERT) eventType = "closed_by_ea";

   WriteTradeLog(magicStrForLogFilename, eventType, closeTime, kindStr, 0, 0, 0, 0, entryOrderTicket, trans.deal, posId, reason, comment, entryMagic);
}

//+------------------------------------------------------------------+
//| If current day not yet logged and we have RTH open + PDC: compute dayStat, write per-day CSV, update totals. Return true if wrote. |
//+------------------------------------------------------------------+
void AccumulateGapDownThresholds(double pctFill)
{
   dayStat_daysWithGapDown++;
   dayStat_gapDown_fillPercentSum += pctFill;
   dayStat_gapDown_rangeSum += dayStat_gapDiff;
   if(pctFill >= 10.0) dayStat_daysWithGapDown_10fill++;
   if(pctFill >= 20.0) dayStat_daysWithGapDown_20fill++;
   if(pctFill >= 25.0) dayStat_daysWithGapDown_25fill++;
   if(pctFill >= 30.0) dayStat_daysWithGapDown_30fill++;
   if(pctFill >= 33.0) dayStat_daysWithGapDown_33fill++;
   if(pctFill >= 40.0) dayStat_daysWithGapDown_40fill++;
   if(pctFill >= 50.0) dayStat_daysWithGapDown_50fill++;
   if(pctFill >= 60.0) dayStat_daysWithGapDown_60fill++;
   if(pctFill >= 75.0) dayStat_daysWithGapDown_75fill++;
   if(pctFill >= 90.0) dayStat_daysWithGapDown_90fill++;
   if(pctFill >= 100.0) dayStat_daysWithGapDown_100fill++;
}

void AccumulateGapUpThresholds(double pctFill)
{
   dayStat_daysWithGapUp++;
   dayStat_gapUp_fillPercentSum += pctFill;
   dayStat_gapUp_rangeSum += dayStat_gapDiff;
   if(pctFill >= 10.0) dayStat_daysWithGapUp_10fill++;
   if(pctFill >= 20.0) dayStat_daysWithGapUp_20fill++;
   if(pctFill >= 25.0) dayStat_daysWithGapUp_25fill++;
   if(pctFill >= 30.0) dayStat_daysWithGapUp_30fill++;
   if(pctFill >= 33.0) dayStat_daysWithGapUp_33fill++;
   if(pctFill >= 40.0) dayStat_daysWithGapUp_40fill++;
   if(pctFill >= 50.0) dayStat_daysWithGapUp_50fill++;
   if(pctFill >= 60.0) dayStat_daysWithGapUp_60fill++;
   if(pctFill >= 75.0) dayStat_daysWithGapUp_75fill++;
   if(pctFill >= 90.0) dayStat_daysWithGapUp_90fill++;
   if(pctFill >= 100.0) dayStat_daysWithGapUp_100fill++;
}

//+------------------------------------------------------------------+
//| Compute 11 gap-fill frequency percentages: pcts[i] = 100 * counts[i] / daysWith (or 0 if daysWith==0). counts[] and pcts[] must have size >= 11. |
//+------------------------------------------------------------------+
void ComputeGapFillFreqs(int daysWith, int &counts[], double &pcts[])
{
   const int nThresh = 11;
   ArrayResize(pcts, nThresh);
   if(daysWith <= 0)
   {
      for(int i = 0; i < nThresh; i++) pcts[i] = 0.0;
      return;
   }
   double denom = (double)daysWith;
   for(int i = 0; i < nThresh; i++)
      pcts[i] = 100.0 * (double)counts[i] / denom;
}

//+------------------------------------------------------------------+
//| If current day not yet logged and we have RTH open + PDC: compute dayStat, write per-day CSV, update totals. Return true if wrote. |
//+------------------------------------------------------------------+
bool TryLogDayStatForCurrentDay()
{
   if(g_barsInDay <= 0 || g_m1DayStart == 0 || g_staticMarketContext.PDCpreviousDayRTHClose <= 0.0 || dayStat_lastLoggedDayStart == g_m1DayStart)
      return false;
   if(IsCalendarDaySunday(g_m1DayStart))
      return false;
   double rthOpen = GetRTHopenCurrentDay();
   double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
   dayStat_hasGapDown = (rthOpen < pdc);
   dayStat_hasGapUp = (rthOpen > pdc);

   // Range from the two numbers (higher = top, lower = bottom); % gap filled = share of range touched by RTH session H/L only
   double range_top    = MathMax(pdc, rthOpen);
   double range_bottom = MathMin(pdc, rthOpen);
   double range_size   = range_top - range_bottom;

   double highestHigh = -1e300, lowestLow = 1e300;
   bool hasRTH = false;
   GetSessionHighLow("RTH", highestHigh, lowestLow, hasRTH);
   if(!hasRTH || range_size <= 0.0)
      dayStat_openGapDown_percentageFill = (range_size <= 0.0 ? 100.0 : 0.0);
   else
   {
      double overlap_bottom = MathMax(range_bottom, lowestLow);
      double overlap_top    = MathMin(range_top, highestHigh);
      double filled_points  = MathMax(0.0, overlap_top - overlap_bottom);
      dayStat_openGapDown_percentageFill = MathMin(100.0, (filled_points / range_size) * 100.0);
   }
   dayStat_openGapUp_percentageFill = (dayStat_hasGapUp && range_size > 0.0) ? dayStat_openGapDown_percentageFill : 0.0;  // same range, same fill %
   dayStat_gapDiff = range_size;
   dayStat_rthHigh = hasRTH ? highestHigh : 0.0;
   dayStat_rthLow  = hasRTH ? lowestLow  : 0.0;

   double onHigh = -1e300, onLow = 1e300;
   bool hasON = false;
   GetSessionHighLow("ON", onHigh, onLow, hasON);
   dayStat_onHigh = hasON ? onHigh : 0.0;
   dayStat_onLow  = hasON ? onLow  : 0.0;
   dayStat_ONH_t_RTH = (hasRTH && hasON && dayStat_rthHigh >= dayStat_onHigh);
   dayStat_ONL_t_RTH = (hasRTH && hasON && dayStat_rthLow <= dayStat_onLow);
   dayStat_ONboth_t_RTH = (dayStat_ONH_t_RTH && dayStat_ONL_t_RTH);

   UpdateGapFillAttemptStatsAtBar();
   const string maxBeforeGapfillAttemptStr = dayStat_maxBeforeGapfillAttempt_valid ?
      DoubleToString(dayStat_maxBeforeGapfillAttempt_over_5, _Digits) : "unknown";
   const string gapAsPctOfONrangeStr = (hasON && dayStat_onHigh > dayStat_onLow) ?
      GapAsPctOfONrangeStr(dayStat_gapDiff, dayStat_onHigh, dayStat_onLow) : "unknown";

   string dateStrStat = TimeToString(g_m1DayStart, TIME_DATE);
   string dayStatLogName = dateStrStat + "_dayPriceStat_and_gapstat_log.csv";
   if(dailyEODlog_DayStat)
   {
   int fileHandleDay = FileOpen(dayStatLogName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandleDay != INVALID_HANDLE)
   {
      FileWrite(fileHandleDay, "date", "hasGapDown", "hasGapUp", "RTHopen", "PD_RTH_Close", "gap_fill_pc", "gapDiff", "gapRangePts", "rthHigh", "rthLow", "ONH", "ONL", "Gap_as_%_of_ONrange", "ONH_t_RTH", "ONL_t_RTH", "ONboth_t_RTH", "max_before_gapfillAttempt_over_5", "spreadHighestSeen", "spreadLowestSeen", "PD_trend");
      FileWrite(fileHandleDay, dateStrStat, (dayStat_hasGapDown ? "true" : "false"), (dayStat_hasGapUp ? "true" : "false"), DoubleToString(rthOpen, _Digits), DoubleToString(pdc, _Digits), DoubleToString(dayStat_openGapDown_percentageFill, 2), DoubleToString(dayStat_gapDiff, _Digits), DoubleToString(dayStat_gapDiff, _Digits), DoubleToString(dayStat_rthHigh, _Digits), DoubleToString(dayStat_rthLow, _Digits), DoubleToString(dayStat_onHigh, _Digits), DoubleToString(dayStat_onLow, _Digits), gapAsPctOfONrangeStr, (dayStat_ONH_t_RTH ? "true" : "false"), (dayStat_ONL_t_RTH ? "true" : "false"), (dayStat_ONboth_t_RTH ? "true" : "false"), maxBeforeGapfillAttemptStr, DoubleToString(dayStat_spreadHighestSeen, 2), DoubleToString(dayStat_spreadLowestSeen, 2), GetPDtrendString());
      FileClose(fileHandleDay);
   }
   }

   dayStat_totalDays++;
   if(dayStat_hasGapDown)
      AccumulateGapDownThresholds(dayStat_openGapDown_percentageFill);
   else
      dayStat_daysWithoutGapDown++;
   if(dayStat_hasGapUp)
      AccumulateGapUpThresholds(dayStat_openGapUp_percentageFill);
   else
      dayStat_daysWithoutGapUp++;
   if(dayStat_ONH_t_RTH) dayStat_daysONH_tested++;
   if(dayStat_ONL_t_RTH) dayStat_daysONL_tested++;
   if(dayStat_ONboth_t_RTH) dayStat_daysONboth_tested++;
   dayStat_lastLoggedDayStart = g_m1DayStart;
   return true;
}

//+------------------------------------------------------------------+
//| Write gap-down / gap-up dayStat summary CSVs. Recalculate at 21:35 so current day is included. |
//+------------------------------------------------------------------+
void WriteDayStatSummaryCsv()
{
   double daysONH_t_freq = (dayStat_totalDays > 0) ? (100.0 * (double)dayStat_daysONH_tested / (double)dayStat_totalDays) : 0.0;
   double daysONL_t_freq = (dayStat_totalDays > 0) ? (100.0 * (double)dayStat_daysONL_tested / (double)dayStat_totalDays) : 0.0;
   double daysONHL_t = (dayStat_totalDays > 0) ? (100.0 * (double)dayStat_daysONboth_tested / (double)dayStat_totalDays) : 0.0;

   double avgFillD = (dayStat_daysWithGapDown > 0) ? dayStat_gapDown_fillPercentSum / (double)dayStat_daysWithGapDown : 0.0;
   double avgGapRangePtsD = (dayStat_daysWithGapDown > 0) ? dayStat_gapDown_rangeSum / (double)dayStat_daysWithGapDown : 0.0;
   int countsD[11];
   countsD[0] = dayStat_daysWithGapDown_10fill;  countsD[1] = dayStat_daysWithGapDown_20fill;  countsD[2] = dayStat_daysWithGapDown_25fill;
   countsD[3] = dayStat_daysWithGapDown_30fill;  countsD[4] = dayStat_daysWithGapDown_33fill;  countsD[5] = dayStat_daysWithGapDown_40fill;
   countsD[6] = dayStat_daysWithGapDown_50fill;  countsD[7] = dayStat_daysWithGapDown_60fill;  countsD[8] = dayStat_daysWithGapDown_75fill;
   countsD[9] = dayStat_daysWithGapDown_90fill;  countsD[10] = dayStat_daysWithGapDown_100fill;
   double pctsD[];
   ComputeGapFillFreqs(dayStat_daysWithGapDown, countsD, pctsD);

   int fileHandleGapD = FileOpen("dayPriceStat_and_gapstat_summaryLog_gapDowns.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandleGapD != INVALID_HANDLE)
   {
      FileWrite(fileHandleGapD, "days", "daysGapD", "daysNoGD", "gapD_avg_fill", "avgGapRangePts", "gD_10_f", "gD_20_f", "gD_25_f", "gD_30_f", "gD_33_f", "gD_40_f", "gD_50_f", "gD_60_f", "gD_75_f", "gD_90_f", "gD_100_f",
                "daysONH_t_freq", "daysONL_t_freq", "daysONHL_t");
      FileWrite(fileHandleGapD, IntegerToString(dayStat_totalDays), IntegerToString(dayStat_daysWithGapDown), IntegerToString(dayStat_daysWithoutGapDown), DoubleToString(avgFillD, 2), DoubleToString(avgGapRangePtsD, _Digits),
                DoubleToString(pctsD[0], 2), DoubleToString(pctsD[1], 2), DoubleToString(pctsD[2], 2), DoubleToString(pctsD[3], 2), DoubleToString(pctsD[4], 2), DoubleToString(pctsD[5], 2), DoubleToString(pctsD[6], 2), DoubleToString(pctsD[7], 2), DoubleToString(pctsD[8], 2), DoubleToString(pctsD[9], 2), DoubleToString(pctsD[10], 2),
                DoubleToString(daysONH_t_freq, 2), DoubleToString(daysONL_t_freq, 2), DoubleToString(daysONHL_t, 2));
      FileClose(fileHandleGapD);
   }

   double avgFillU = (dayStat_daysWithGapUp > 0) ? dayStat_gapUp_fillPercentSum / (double)dayStat_daysWithGapUp : 0.0;
   double avgGapRangePtsU = (dayStat_daysWithGapUp > 0) ? dayStat_gapUp_rangeSum / (double)dayStat_daysWithGapUp : 0.0;
   int countsU[11];
   countsU[0] = dayStat_daysWithGapUp_10fill;  countsU[1] = dayStat_daysWithGapUp_20fill;  countsU[2] = dayStat_daysWithGapUp_25fill;
   countsU[3] = dayStat_daysWithGapUp_30fill;  countsU[4] = dayStat_daysWithGapUp_33fill;  countsU[5] = dayStat_daysWithGapUp_40fill;
   countsU[6] = dayStat_daysWithGapUp_50fill;  countsU[7] = dayStat_daysWithGapUp_60fill;  countsU[8] = dayStat_daysWithGapUp_75fill;
   countsU[9] = dayStat_daysWithGapUp_90fill;  countsU[10] = dayStat_daysWithGapUp_100fill;
   double pctsU[];
   ComputeGapFillFreqs(dayStat_daysWithGapUp, countsU, pctsU);

   int fileHandleGapU = FileOpen("dayPriceStat_and_gapstat_summaryLog_gapUps.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandleGapU != INVALID_HANDLE)
   {
      FileWrite(fileHandleGapU, "days", "daysGapUp", "daysNoGU", "gapU_avg_fill", "avgGapRangePts", "gU_10_f", "gU_20_f", "gU_25_f", "gU_30_f", "gU_33_f", "gU_40_f", "gU_50_f", "gU_60_f", "gU_75_f", "gU_90_f", "gU_100_f",
                "daysONH_t_freq", "daysONL_t_freq", "daysONHL_t");
      FileWrite(fileHandleGapU, IntegerToString(dayStat_totalDays), IntegerToString(dayStat_daysWithGapUp), IntegerToString(dayStat_daysWithoutGapUp), DoubleToString(avgFillU, 2), DoubleToString(avgGapRangePtsU, _Digits),
                DoubleToString(pctsU[0], 2), DoubleToString(pctsU[1], 2), DoubleToString(pctsU[2], 2), DoubleToString(pctsU[3], 2), DoubleToString(pctsU[4], 2), DoubleToString(pctsU[5], 2), DoubleToString(pctsU[6], 2), DoubleToString(pctsU[7], 2), DoubleToString(pctsU[8], 2), DoubleToString(pctsU[9], 2), DoubleToString(pctsU[10], 2),
                DoubleToString(daysONH_t_freq, 2), DoubleToString(daysONL_t_freq, 2), DoubleToString(daysONHL_t, 2));
      FileClose(fileHandleGapU);
   }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   BacktestProfWriteRunSummary();
   BreakdownGatesLogCloseAllFileHandles();
   PullingHistoryPsLogCloseHandles();
   BuyHoldBenchmarkUpdate(true);

   if(current_candle_time != 0)
      FinalizeCurrentCandle();

   if(bigflipper_log_all_breakdowns && g_m1DayStart > 0 && g_barsInDay >= 1)
   {
      datetime upToM1BarTime = g_lastTimer1Time;
      if(g_barsInDay >= 2)
         upToM1BarTime = g_m1Rates[g_barsInDay - 2].time + 60;
      BreakdownAuditLogScanDayIfNeeded(g_m1DayStart, upToM1BarTime, true);
   }

   for(int i=0;i<ArraySize(levels);i++)
      if(levels[i].logRawEv_fileHandle != INVALID_HANDLE)
         FileClose(levels[i].logRawEv_fileHandle);

   if(allCandlesFileHandle != INVALID_HANDLE)
      FileClose(allCandlesFileHandle);

   if(finalLog_FirstLastCandle)
   {
   int fileHandle = FileOpen(InpSessionFirstLastCandleFile, FILE_WRITE | FILE_TXT | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandle != INVALID_HANDLE)
   {
      FileWrite(fileHandle,"----------------------------------------");
      FileWrite(fileHandle,"Symbol: ",_Symbol);
      FileWrite(fileHandle,"Timeframe: ",EnumToString(_Period));

      FileWrite(fileHandle,"First Candle:");
      FileWrite(fileHandle,"  Time: ",TimeToString(first_candle_time,TIME_DATE|TIME_SECONDS));
      FileWrite(fileHandle,"  O: ",first_open," H: ",first_high," L: ",first_low," C: ",first_close);

      FileWrite(fileHandle,"Last Candle:");
      FileWrite(fileHandle,"  Time: ",TimeToString(last_candle_time,TIME_DATE|TIME_SECONDS));
      FileWrite(fileHandle,"  O: ",last_open," H: ",last_high," L: ",last_low," C: ",last_close);

      FileWrite(fileHandle,"----------------------------------------");
      FileClose(fileHandle);
   }
   }
}


//+------------------------------------------------------------------+
//| End of OnTimer: elapsed µs via GetMicrosecondCount (fine-grained); at 21:30 once per day Print min/max for that day. |
//+------------------------------------------------------------------+
void OnTimer_FinishDurationStatsAndMaybeLog2130(const ulong t0)
{
   const ulong t1 = GetMicrosecondCount();
   const ulong elapsed = t1 - t0;

   const datetime dayStart = g_lastTimer1Time - (g_lastTimer1Time % 86400);
   if(g_onTimerDuration_dayStart != dayStart)
   {
      g_onTimerDuration_dayStart = dayStart;
      g_onTimerDuration_minUsToday = elapsed;
      g_onTimerDuration_maxUsToday = elapsed;
      g_onTimerDuration_samplesToday = 1;
      g_onTimerDuration_logged2130ForDay = 0;
   }
   else
   {
      if(elapsed < g_onTimerDuration_minUsToday)
         g_onTimerDuration_minUsToday = elapsed;
      if(elapsed > g_onTimerDuration_maxUsToday)
         g_onTimerDuration_maxUsToday = elapsed;
      g_onTimerDuration_samplesToday++;
   }

   MqlDateTime dt;
   TimeToStruct(g_lastTimer1Time, dt);
   if(dt.hour == 21 && dt.min == 30 && g_onTimerDuration_logged2130ForDay != dayStart)
   {
      g_onTimerDuration_logged2130ForDay = dayStart;
      if(g_onTimerDuration_samplesToday > 0)
      {
         const string fastMs = DoubleToString((double)g_onTimerDuration_minUsToday / 1000.0, 3);
         const string slowMs = DoubleToString((double)g_onTimerDuration_maxUsToday / 1000.0, 3);
         Print(StringFormat(
                  "OnTimer(1s) today %s — fastest=%s ms slowest=%s ms (%d runs)",
                  TimeToString(dayStart, TIME_DATE),
                  fastMs,
                  slowMs,
                  g_onTimerDuration_samplesToday));
      }
   }
}

//+------------------------------------------------------------------+
//| OnTimer(1s): detect new bar, load closed bar from history, run FinalizeCurrentCandle. Sets g_lastTimer1Time = TimeCurrent(). |
//+------------------------------------------------------------------+
void OnTimer()
{
   const ulong onTimerT0 = GetMicrosecondCount();
   const bool profOn = BacktestProfileEnabled();
   ulong profT0 = 0;

   g_lastTimer1Time = TimeCurrent();
   if(profOn)
      BacktestProfOnTimerDayRollover(g_lastTimer1Time - (g_lastTimer1Time % 86400));
   g_liveBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_liveAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = g_liveAsk - g_liveBid;
   if(spread > 0.0)
   {
      if(dayStat_spreadHighestSeen == 0.0 || spread > dayStat_spreadHighestSeen)
         dayStat_spreadHighestSeen = spread;
      if(dayStat_spreadLowestSeen == 0.0 || spread < dayStat_spreadLowestSeen)
         dayStat_spreadLowestSeen = spread;
   }

   CheckDepositLoadFatalIfExceeded();

   if(maemfe_testing)
      CloseAnyEAPositionThatIsXMinutesOld(10);

   if(profOn)
      profT0 = GetMicrosecondCount();
   FalgoUpdateOpenTradeTelemetryEachSecond();
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_TELEMETRY_PER_SEC, profT0);
   RunBreakdownBabysitOnly();

   FalgoTryLogAlgoFamilyPerSecond();

   MqlDateTime mqlTime;
   TimeToStruct(g_lastTimer1Time, mqlTime);
   datetime today = g_lastTimer1Time - (g_lastTimer1Time % 86400);

   // Temporary: log live price + closed candle date + OHLC every second 21:35-21:37. CSV with headers: time, liveBid, liveAsk, closed_candle_time, closed_O, closed_H, closed_L, closed_C
   if(dailySpamLog_LivePrice && mqlTime.hour == 21 && mqlTime.min >= 35 && mqlTime.min <= 37 && g_barsInDay > 0)
   {
      // g_m1Rates is oldest-first: [0]=first bar of day, [g_barsInDay-1]=last; closed candle = second-to-last when >=2 bars
      int kClosed = (g_barsInDay >= 2) ? g_barsInDay - 2 : g_barsInDay - 1;
      datetime closedTime = g_m1Rates[kClosed].time;
      double closedO = g_m1Rates[kClosed].open, closedH = g_m1Rates[kClosed].high, closedL = g_m1Rates[kClosed].low, closedC = g_m1Rates[kClosed].close;
      string fname = TimeToString(today, TIME_DATE) + "_testing_liveprice.csv";
      int fileHandle = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(fileHandle != INVALID_HANDLE)
      {
         FileSeek(fileHandle, 0, SEEK_END);
         if(FileTell(fileHandle) == 0)
            FileWrite(fileHandle, "time", "liveBid", "liveAsk", "closed_candle_time", "closed_O", "closed_H", "closed_L", "closed_C");
         FileWrite(fileHandle, TimeToString(g_lastTimer1Time, TIME_DATE|TIME_SECONDS), DoubleToString(g_liveBid, _Digits), DoubleToString(g_liveAsk, _Digits),
                   TimeToString(closedTime, TIME_DATE|TIME_SECONDS), DoubleToString(closedO, _Digits), DoubleToString(closedH, _Digits), DoubleToString(closedL, _Digits), DoubleToString(closedC, _Digits));
         FileClose(fileHandle);
      }
      else
      {
         fileHandle = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
         if(fileHandle == INVALID_HANDLE)
            FatalError("OnTimer: could not open liveprice CSV " + fname);
         FileWrite(fileHandle, "time", "liveBid", "liveAsk", "closed_candle_time", "closed_O", "closed_H", "closed_L", "closed_C");
         FileWrite(fileHandle, TimeToString(g_lastTimer1Time, TIME_DATE|TIME_SECONDS), DoubleToString(g_liveBid, _Digits), DoubleToString(g_liveAsk, _Digits),
                   TimeToString(closedTime, TIME_DATE|TIME_SECONDS), DoubleToString(closedO, _Digits), DoubleToString(closedH, _Digits), DoubleToString(closedL, _Digits), DoubleToString(closedC, _Digits));
         FileClose(fileHandle);
      }
   }

   // At 21:35: ensure current day is in dayStat (if missed at 21:30), then recalculate summary CSV so it always includes current day
   if(mqlTime.hour == 21 && mqlTime.min == 35 && g_barsInDay > 0)
   {
      TryLogDayStatForCurrentDay();
      WriteDayStatSummaryCsv();
   }

   // Candle-close detection: use M1 so "new candle" is always one closed M1 bar; bar that just closed = last bar of day M1 (g_m1Rates) after refresh
   datetime barNowM1 = iTime(_Symbol, PERIOD_M1, 0);
   if(barNowM1 == g_lastBarTime)
   {
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_ONTIMER_TOTAL, onTimerT0);
      OnTimer_FinishDurationStatsAndMaybeLog2130(onTimerT0);
      return;
   }

   g_lastBarTime = barNowM1;

   const datetime barClosedM1 = iTime(_Symbol, PERIOD_M1, 1);
   TryFlushTradeResultsEodFallback(barNowM1, barClosedM1);

   // Pull static context for today before refresh so PDC is available when building levels (single UpdateDayM1AndLevelsExpanded per bar)
   datetime dayStartForContext = g_lastTimer1Time - (g_lastTimer1Time % 86400);
   if(g_staticMarketContextPulledForDate != dayStartForContext)
   {
      if(profOn)
         profT0 = GetMicrosecondCount();
      UpdateStaticMarketContext(dayStartForContext);
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_STATIC_MARKET_CONTEXT, profT0);
      g_staticMarketContextPulledForDate = dayStartForContext;
   }

   // Refresh day M1 and levels first; then set closed-candle OHLC from same source (or terminal fallback)
   UpdateDayM1AndLevelsExpanded();
   TryFlushTradeResultsIfLastBarOfDayInFeed();

   if(bigflipper_log_all_breakdowns && g_m1DayStart > 0 && g_barsInDay >= 2)
   {
      const datetime upToM1BarTime = g_m1Rates[g_barsInDay - 2].time + 60;
      if(profOn)
         profT0 = GetMicrosecondCount();
      BreakdownAuditLogScanDayIfNeeded(g_m1DayStart, upToM1BarTime);
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_BREAKDOWN_AUDIT_SCAN, profT0);
   }

   if(profOn)
      profT0 = GetMicrosecondCount();
   SetClosedCandleOHLCFromDayM1OrTerminal();
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_M1_BAR_CLOSE_SET_OHLC, profT0);

   if(profOn)
      profT0 = GetMicrosecondCount();
   FinalizeCurrentCandle();
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_M1_BAR_CLOSE_FINALIZE_CANDLE, profT0);

   M1BarCloseStatsBeginUpdate();
   if(profOn)
      profT0 = GetMicrosecondCount();
   // --- ON and RTH session high/low so far at each bar k (bars 0..k). Fresh each candle; log reads from g_*AtBar[k].
   UpdateONandRTHHighLowSoFarAtBar();

   // --- IB high/low (15:30–16:30 or 14:30–15:30); unknown before IB ends.
   UpdateIBHighLowAtBar();

   // --- Gap fill so far: % of gap filled by rthLowSoFar (gap up) or rthHighSoFar (gap down); unknown before RTH open.
   UpdateGapFillSoFarAtBar();
   UpdateGapFillAttemptStatsAtBar();
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_M1_BAR_CLOSE_ATBAR_STATS, profT0);

   // --- Trade results for the day (deals IN/OUT paired by magic; available globally)
   if(InpLoadTradeResultsFromHistory)
   {
      if(profOn)
         profT0 = GetMicrosecondCount();
      UpdateTradeResultsForDay();
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_TRADE_RESULTS_HISTORY, profT0);
      FalgoEnrichAllTradeResultsLevelTpSl();
   }
   else
   {
      g_tradeResultsCount = 0;
      g_dealCount = 0;
   }

   if(profOn)
      profT0 = GetMicrosecondCount();
   // --- Per-candle day progress (trades closed by each candle close time)
   UpdateDayProgress();
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_M1_BAR_CLOSE_DAY_PROGRESS, profT0);

   if(profOn)
      profT0 = GetMicrosecondCount();
   UpdateFalgoDayTradeCounts();
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_FALGO_DAY_TRADE_COUNTS, profT0);

   if(profOn)
      profT0 = GetMicrosecondCount();
   FalgoTryLogGatesForClosedMinute();
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_M1_BAR_CLOSE_GATES_FALGO, profT0);

   if(g_barsInDay >= 1)
   {
      const int placementBarIdx = (g_barsInDay >= 2) ? g_barsInDay - 2 : g_barsInDay - 1;
      RunBreakdownPlacementOnM1Close(placementBarIdx);
   }

   if(profOn)
      profT0 = GetMicrosecondCount();
   UpdatePullingHistoryAlgoFamilyAccountBarStats();
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_M1_BAR_CLOSE_ACCOUNT_BAR_STATS, profT0);

   if(profOn)
      profT0 = GetMicrosecondCount();
   // --- Per-level trade stats (trade results whose level matches levelPrice; ON/RTH by endTime)
   UpdateLevelTradeStats();
   M1BarCloseStatsEndUpdate();
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_M1_BAR_CLOSE_LEVEL_TRADE_STATS, profT0);

   // --- Static market context: pulled before UpdateDayM1AndLevelsExpanded(); set ONopen from first candle whenever we have bars.
   if(g_barsInDay > 0)
   {
      if(profOn)
         profT0 = GetMicrosecondCount();
      // g_m1Rates is oldest-first: [0]=first bar of day
      g_ONopen = g_m1Rates[0].open;
      GaplogAppendBarRow(g_barsInDay - 1);
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_M1_BAR_CLOSE_GAPLOG, profT0);
   }
   
   if(InpEODLogging)
   {
      if(profOn)
         profT0 = GetMicrosecondCount();
      datetime dayStart;
      string dateStr;
      GetDayStartAndDateStr(g_lastTimer1Time, dayStart, dateStr);
      if(IsInEODLogWindow(g_lastTimer1Time) && g_barsInDay > 0)
      {
         int kLast = g_barsInDay - 1;
         MqlDateTime mtEod;
         TimeToStruct(g_lastTimer1Time, mtEod);
         int minOfDay = mtEod.hour * 60 + mtEod.min;
         // Daily summary (Day_activeLevels, EOD account, AllHistoryOrders, AllHistoryDeals) — once per day when file missing
         if(dailyEODlog_DailySummary && !FileIsExist(dateStr + "-Day_activeLevels.csv"))
            WriteDailySummary();


         if(dailyEODlog_PullingHistoryAlgoFamily)
         {
            UpdateTradeResultsForDay();
            FalgoEnrichAllTradeResultsLevelTpSl();
            UpdateDayProgress();
            UpdatePullingHistoryAlgoFamilyAccountBarStats();
            PullingHistoryAlgoFamilyWriteEodCsv(dateStr, "weekly");
            PullingHistoryAlgoFamilyWriteEodCsv(dateStr, "daily");
         }

         // EOD one-line trades summary: same trade stats as latest row of pullinghistory (date)_summary_EOD_tradesSummary1line.csv. Skip if no trades (empty day).
         string eodSummaryName = dateStr + "_summary_EOD_tradesSummary1line.csv";
         if(dailyEODlog_EodTradesSummary && !FileIsExist(eodSummaryName) && kLast >= 0 && g_dayProgress[kLast].dayTradesCount > 0)
         {
            int fileHandleEod = FileOpen(eodSummaryName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
            if(fileHandleEod != INVALID_HANDLE)
            {
               FileWrite(fileHandleEod, "time", "dayWinRate", "dayTradesCount", "dayPointsSum", "dayProfitSum", "ONwinRate", "ONtradeCount", "ONpointsSum", "ONprofitSum", "RTHwinRate", "RTHtradeCount", "RTHpointsSum", "RTHprofitSum");
               FileWrite(fileHandleEod, TimeToString(g_m1Rates[kLast].time, TIME_DATE|TIME_MINUTES),
                  DoubleToString(g_dayProgress[kLast].dayWinRate * 100.0, 0), IntegerToString(g_dayProgress[kLast].dayTradesCount), DoubleToString(g_dayProgress[kLast].dayPointsSum, _Digits), DoubleToString(g_dayProgress[kLast].dayProfitSum, 2),
                  DoubleToString(g_dayProgress[kLast].ONwinRate * 100.0, 0), IntegerToString(g_dayProgress[kLast].ONtradeCount), DoubleToString(g_dayProgress[kLast].ONpointsSum, _Digits), DoubleToString(g_dayProgress[kLast].ONprofitSum, 2),
                  DoubleToString(g_dayProgress[kLast].RTHwinRate * 100.0, 0), IntegerToString(g_dayProgress[kLast].RTHtradeCount), DoubleToString(g_dayProgress[kLast].RTHpointsSum, _Digits), DoubleToString(g_dayProgress[kLast].RTHprofitSum, 2));
               FileClose(fileHandleEod);
            }
         }


         WriteAlgoFamilyEodTradeResultsCsvsIfNeeded(dateStr);
         MarkTradeResultsEodFlushedForDay(dayStart);

         // Per-level files (only once per file per day; if missing, write again). MT5 CSV with headers.
         const int HighestDiffRange_Log = 15;  // window in bars for both HighestDiffUp and HighestDiffDown in logs
         if(bigflipper_log_testinglevelsplus)
         for(int levelIdx = 0; levelIdx < g_levelsTodayCount; levelIdx++)
         {
            string levelFile = dateStr + "_testinglevelsplus_" + DoubleToString(g_levelsExpanded[levelIdx].levelPrice, _Digits) + "_" + g_levelsExpanded[levelIdx].tag + ".csv";
            if(!FileIsExist(levelFile))
            {
               int fileHandleL = FileOpen(levelFile, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
               if(fileHandleL == INVALID_HANDLE)
                  FatalError("OnTimer: could not open " + levelFile);
               FileWrite(fileHandleL, "time", "diff_CloseToLevel", "O", "H", "L", "C", "breaksLevelDown", "breaksLevelUpward", "cleanStreakAbove", "cleanStreakBelow", "aboveCnt", "abovePerc", "belowCnt", "belowPerc", "overlapStreak", "overlapC", "overlapPc", "HighestDiffUp_rangeArg", "HighestDiffUpRange", "HighestDiffDown_rangeArg", "HighestDiffDownRange", "ON_O_wasAboveL", "RTH_O_wasAboveL", "ONtradeCount_L", "ONwinRate_L", "ONpointsSum_L", "ONprofitSum_L", "RTHtradeCount_L", "RTHwinRate_L", "RTHpointsSum_L", "RTHprofitSum_L");
               double lvl = g_levelsExpanded[levelIdx].levelPrice;
               double onOpen = g_m1Rates[0].open;
               double rthOpenVal = 0.0;
               bool haveRthOpen = GetTodayRTHopenIfValid(rthOpenVal);
               for(int barIdx = 0; barIdx < g_levelsExpanded[levelIdx].count; barIdx++)
               {
                  string highestUp   = Rules_GetHighestDiffFromLevelInWindowString(lvl, barIdx, HighestDiffRange_Log, true);
                  string highestDown = Rules_GetHighestDiffFromLevelInWindowString(lvl, barIdx, HighestDiffRange_Log, false);
                  bool onKnown   = (barIdx > 0);
                  bool rthKnown  = haveRthOpen && (GetSessionForCandleTime(g_levelsExpanded[levelIdx].times[barIdx]) != "ON");
                  string onAboveStr  = GetOpenWasAboveLevelString(onOpen, lvl, onKnown);
                  string rthAboveStr = GetOpenWasAboveLevelString(rthOpenVal, lvl, rthKnown);
                  FileWrite(fileHandleL, TimeToString(g_levelsExpanded[levelIdx].times[barIdx], TIME_DATE|TIME_MINUTES),
                     DoubleToString(g_levelsExpanded[levelIdx].diffs[barIdx], _Digits),
                     DoubleToString(g_m1Rates[barIdx].open, _Digits), DoubleToString(g_m1Rates[barIdx].high, _Digits), DoubleToString(g_m1Rates[barIdx].low, _Digits), DoubleToString(g_m1Rates[barIdx].close, _Digits),
                     (g_breaksLevelDown[levelIdx][barIdx] ? "true" : "false"), (g_breaksLevelUpward[levelIdx][barIdx] ? "true" : "false"),
                     IntegerToString(g_cleanStreakAbove[levelIdx][barIdx]), IntegerToString(g_cleanStreakBelow[levelIdx][barIdx]),
                     IntegerToString(g_aboveCnt[levelIdx][barIdx]), DoubleToString(g_abovePerc[levelIdx][barIdx], 2), IntegerToString(g_belowCnt[levelIdx][barIdx]), DoubleToString(g_belowPerc[levelIdx][barIdx], 2),
                     IntegerToString(g_overlapStreak[levelIdx][barIdx]), IntegerToString(g_overlapC[levelIdx][barIdx]), DoubleToString(g_overlapPc[levelIdx][barIdx], 2),
                     highestUp, IntegerToString(HighestDiffRange_Log), highestDown, IntegerToString(HighestDiffRange_Log),
                     onAboveStr, rthAboveStr,
                     IntegerToString(g_ONtradeCount_L[levelIdx][barIdx]), DoubleToString((g_ONtradeCount_L[levelIdx][barIdx] > 0) ? (double)g_ONwins_L[levelIdx][barIdx] / (double)g_ONtradeCount_L[levelIdx][barIdx] * 100.0 : 0.0, 0), DoubleToString(g_ONpointsSum_L[levelIdx][barIdx], _Digits), DoubleToString(g_ONprofitSum_L[levelIdx][barIdx], 2),
                     IntegerToString(g_RTHtradeCount_L[levelIdx][barIdx]), DoubleToString((g_RTHtradeCount_L[levelIdx][barIdx] > 0) ? (double)g_RTHwins_L[levelIdx][barIdx] / (double)g_RTHtradeCount_L[levelIdx][barIdx] * 100.0 : 0.0, 0), DoubleToString(g_RTHpointsSum_L[levelIdx][barIdx], _Digits), DoubleToString(g_RTHprofitSum_L[levelIdx][barIdx], 2));
               }
               FileClose(fileHandleL);
            }
         }

         // Levels break check: one row per level (EOD 21:58). Separate ON (til 15:30) and RTH (15:30 onward). Rows sorted by levelPrice.
         if(dailyEODlog_BreakCheck)
         {
         string breakCheckFile = dateStr + "_levels_breakCheck_breakingDown.csv";
         int fileHandleBreak = FileOpen(breakCheckFile, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
         if(fileHandleBreak != INVALID_HANDLE)
         {
            string cutoffStr = IntegerToString((int)MathRound(InpBreakCheckMaxDistPoints));
            FileWrite(fileHandleBreak, "levelPrice", "ONrangeStartTime", "ONcountCandles_" + cutoffStr, "ONaverage_" + cutoffStr, "ONmedian_" + cutoffStr, "RTHIBrangeStartTime", "RTHIBcountCandles_" + cutoffStr, "RTHIBaverage_" + cutoffStr, "RTHIBmedian_" + cutoffStr, "RTHcntrangeStartTime", "RTHcntcountCandles_" + cutoffStr, "RTHcntaverage_" + cutoffStr, "RTHcntmedian_" + cutoffStr);
            bool accumulateToday = (g_m1DayStart != 0 && g_m1DayStart != g_breakCheck_lastAggregatedDay);
            int order[];
            ArrayResize(order, g_levelsTodayCount);
            for(int sortIdx = 0; sortIdx < g_levelsTodayCount; sortIdx++) order[sortIdx] = sortIdx;
            for(int sortIdx = 0; sortIdx < g_levelsTodayCount; sortIdx++)
               for(int innerIdx = sortIdx + 1; innerIdx < g_levelsTodayCount; innerIdx++)
                  if(g_levelsExpanded[order[innerIdx]].levelPrice < g_levelsExpanded[order[sortIdx]].levelPrice)
                  { int swapTmp = order[sortIdx]; order[sortIdx] = order[innerIdx]; order[innerIdx] = swapTmp; }
            for(int sortIdx = 0; sortIdx < g_levelsTodayCount; sortIdx++)
            {
               int levelIdx = order[sortIdx];
               double lvl = g_levelsExpanded[levelIdx].levelPrice;
               double maxDist = InpBreakCheckMaxDistPoints;  // always in price

               BreakCheckSessionResult onRes    = BreakCheckSessionStats(lvl, maxDist, BREAKCHECK_ON);
               BreakCheckSessionResult rthibRes = BreakCheckSessionStats(lvl, maxDist, BREAKCHECK_RTHIB);
               BreakCheckSessionResult rthcntRes = BreakCheckSessionStats(lvl, maxDist, BREAKCHECK_RTHCNT);

               FileWrite(fileHandleBreak, DoubleToString(lvl, _Digits),
                  onRes.rangeStartStr, IntegerToString(onRes.count), DoubleToString(onRes.avg, _Digits), DoubleToString(onRes.median, _Digits),
                  rthibRes.rangeStartStr, IntegerToString(rthibRes.count), DoubleToString(rthibRes.avg, _Digits), DoubleToString(rthibRes.median, _Digits),
                  rthcntRes.rangeStartStr, IntegerToString(rthcntRes.count), DoubleToString(rthcntRes.avg, _Digits), DoubleToString(rthcntRes.median, _Digits));
               if(accumulateToday)
               {
                  bool excludeTertiary = (StringFind(g_levelsExpanded[levelIdx].categories, "tertiary") >= 0);
                  if(!excludeTertiary)
                  {
                     g_agg_ONbreakDown_sumCandles += onRes.count; g_agg_ONbreakDown_sumAvg += onRes.avg; g_agg_ONbreakDown_sumMed += onRes.median; g_agg_ONbreakDown_n++;
                     g_agg_RTHIBbreakDown_sumCandles += rthibRes.count; g_agg_RTHIBbreakDown_sumAvg += rthibRes.avg; g_agg_RTHIBbreakDown_sumMed += rthibRes.median; g_agg_RTHIBbreakDown_n++;
                     g_agg_RTHcntbreakDown_sumCandles += rthcntRes.count; g_agg_RTHcntbreakDown_sumAvg += rthcntRes.avg; g_agg_RTHcntbreakDown_sumMed += rthcntRes.median; g_agg_RTHcntbreakDown_n++;
                  }
               }
            }
            if(accumulateToday) { g_breakCheck_lastAggregatedDay = g_m1DayStart; g_breakCheck_daysCount++; }
            FileClose(fileHandleBreak);
         }
         // At 22:00 write single aggregate log (no date in name): type, avgcandles, avgavg, avgmedian for all 4 types
         if(minOfDay == 22*60+0)
         {
            int fileHandleSum = FileOpen("levels_breakCheck_breakingDown_tertiaryLevelsExcluded_summary.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
            if(fileHandleSum != INVALID_HANDLE)
            {
               FileWrite(fileHandleSum, "timerangeType", "avgCandleCount", "avgOfAvg", "avgOfMedian", "daysCount", "totalLevelCount");
               int daysCount = g_breakCheck_daysCount;
               double countDbl;
               countDbl = (double)g_agg_ONbreakDown_n;   FileWrite(fileHandleSum, "ON",   (countDbl > 0 ? DoubleToString(g_agg_ONbreakDown_sumCandles/countDbl, 2) : "0"), (countDbl > 0 ? DoubleToString(g_agg_ONbreakDown_sumAvg/countDbl, _Digits) : "0"), (countDbl > 0 ? DoubleToString(g_agg_ONbreakDown_sumMed/countDbl, _Digits) : "0"), IntegerToString(daysCount), IntegerToString(g_agg_ONbreakDown_n));
               countDbl = (double)g_agg_RTHIBbreakDown_n; FileWrite(fileHandleSum, "RTHIB", (countDbl > 0 ? DoubleToString(g_agg_RTHIBbreakDown_sumCandles/countDbl, 2) : "0"), (countDbl > 0 ? DoubleToString(g_agg_RTHIBbreakDown_sumAvg/countDbl, _Digits) : "0"), (countDbl > 0 ? DoubleToString(g_agg_RTHIBbreakDown_sumMed/countDbl, _Digits) : "0"), IntegerToString(daysCount), IntegerToString(g_agg_RTHIBbreakDown_n));
               countDbl = (double)g_agg_RTHcntbreakDown_n; FileWrite(fileHandleSum, "RTHcnt", (countDbl > 0 ? DoubleToString(g_agg_RTHcntbreakDown_sumCandles/countDbl, 2) : "0"), (countDbl > 0 ? DoubleToString(g_agg_RTHcntbreakDown_sumAvg/countDbl, _Digits) : "0"), (countDbl > 0 ? DoubleToString(g_agg_RTHcntbreakDown_sumMed/countDbl, _Digits) : "0"), IntegerToString(daysCount), IntegerToString(g_agg_RTHcntbreakDown_n));
               FileClose(fileHandleSum);
            }
         }
         }
      }
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_M1_BAR_CLOSE_EOD_LOGGING, profT0);
   }
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_ONTIMER_TOTAL, onTimerT0);
   OnTimer_FinishDurationStatsAndMaybeLog2130(onTimerT0);
}

//+------------------------------------------------------------------+
//| Set closed-candle globals (current_candle_time, candle_open/high/low/close) from day M1 or terminal. |
//| When g_barsInDay > 0 uses g_m1Rates (bar that just closed = second-to-last); else uses terminal M1 bar 1. |
//+------------------------------------------------------------------+
void SetClosedCandleOHLCFromDayM1OrTerminal()
{
   if(g_barsInDay > 0)
   {
      int kClosed = (g_barsInDay >= 2) ? g_barsInDay - 2 : g_barsInDay - 1;
      current_candle_time = g_m1Rates[kClosed].time;
      candle_open  = g_m1Rates[kClosed].open;
      candle_high  = g_m1Rates[kClosed].high;
      candle_low   = g_m1Rates[kClosed].low;
      candle_close = g_m1Rates[kClosed].close;
   }
   else
   {
      current_candle_time = iTime(_Symbol, PERIOD_M1, 1);
      candle_open  = iOpen(_Symbol, PERIOD_M1, 1);
      candle_high  = iHigh(_Symbol, PERIOD_M1, 1);
      candle_low   = iLow(_Symbol, PERIOD_M1, 1);
      candle_close = iClose(_Symbol, PERIOD_M1, 1);
   }
}

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES BreakdownPeriodTimeframe(const int periodMinutes)
{
   if(periodMinutes < 1)
      FatalError("Breakdown period minutes must be >= 1");
   const ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)periodMinutes;
   if(PeriodSeconds(tf) != periodMinutes * 60)
      FatalError("Breakdown unsupported period minutes: " + IntegerToString(periodMinutes));
   return tf;
}

//+------------------------------------------------------------------+
int BreakdownCopyCompletedPeriodBarsToday(const datetime dayStart, const datetime upToM1BarTime,
   const int periodMinutes, MqlRates &outRates[])
{
   ArrayResize(outRates, 0);
   if(upToM1BarTime < dayStart || periodMinutes < 1)
      return 0;

   const ENUM_TIMEFRAMES tf = BreakdownPeriodTimeframe(periodMinutes);
   const int barCompleteOffsetSec = periodMinutes * 60;  // include bar only after its last M1 has closed
   const string dayStr = TimeToString(dayStart, TIME_DATE);
   int shiftStart = iBarShift(_Symbol, tf, dayStart, false);
   int shiftEnd = iBarShift(_Symbol, tf, upToM1BarTime, false);
   if(shiftStart < 0 || shiftEnd < 0)
      return 0;
   if(shiftStart < shiftEnd)
   {
      const int tmp = shiftStart;
      shiftStart = shiftEnd;
      shiftEnd = tmp;
   }

   const int count = shiftStart - shiftEnd + 1;
   if(count <= 0)
      return 0;

   MqlRates rawRates[];
   if(CopyRates(_Symbol, tf, shiftEnd, count, rawRates) <= 0)
      return 0;

   int outCount = 0;
   for(int barIdx = 0; barIdx < ArraySize(rawRates); barIdx++)
   {
      if(TimeToString(rawRates[barIdx].time, TIME_DATE) != dayStr)
         continue;
      if(rawRates[barIdx].time + barCompleteOffsetSec > upToM1BarTime)
         continue;
      ArrayResize(outRates, outCount + 1);
      outRates[outCount] = rawRates[barIdx];
      outCount++;
   }
   return outCount;
}

//+------------------------------------------------------------------+
bool BreakdownBarIsStrongRedStart(const MqlRates &bar, const double strongRangePctMin)
{
   if(bar.close >= bar.open)
      return false;
   if(bar.low <= 0.0)
      return false;
   const double rangePct = (bar.high - bar.low) / bar.low * 100.0;
   return (rangePct >= strongRangePctMin);
}

//+------------------------------------------------------------------+
//| First strong red M15 starts breakdown; length grows while each next M15 metric is strictly lower. |
//+------------------------------------------------------------------+
bool BreakdownBuild15mSequenceFromStart(const MqlRates &m15[], const int barCount, const int startIdx,
   const double strongRangePctMin, const ENUM_BREAKDOWN_STREAK_CONTINUATION continuationMode,
   Breakdown15mState &out, int &outNextScanIdx)
{
   ZeroMemory(out);
   outNextScanIdx = barCount;
   if(startIdx < 0 || startIdx >= barCount)
      return false;
   if(!BreakdownBarIsStrongRedStart(m15[startIdx], strongRangePctMin))
      return false;

   out.hasBreakdown = true;
   out.startTime = m15[startIdx].time;
   out.startHigh = m15[startIdx].high;

   int sequenceLen = 1;
   double streakLowest = m15[startIdx].low;
   double prevMetric = BreakdownStreakBarMetric(m15[startIdx], continuationMode);
   int sequenceEndIdx = startIdx;
   bool sequenceActive = true;
   int breakIdx = barCount;

   for(int barIdx = startIdx + 1; barIdx < barCount; barIdx++)
   {
      const double barMetric = BreakdownStreakBarMetric(m15[barIdx], continuationMode);
      if(barMetric >= prevMetric)
      {
         sequenceActive = false;
         breakIdx = barIdx;
         break;
      }
      sequenceLen++;
      sequenceEndIdx = barIdx;
      prevMetric = barMetric;
      if(m15[barIdx].low < streakLowest)
         streakLowest = m15[barIdx].low;
   }

   out.breakdownLow = streakLowest;
   if(out.startHigh > 0.0)
      out.totalPercent = (streakLowest - out.startHigh) / out.startHigh * 100.0;

   if(sequenceActive)
   {
      out.sequenceActive = true;
      out.activeLength = sequenceLen;
      outNextScanIdx = barCount;
      return true;
   }

   out.sequenceActive = false;
   out.endedLength = sequenceLen;
   out.endTime = m15[sequenceEndIdx].time + 15 * 60;
   outNextScanIdx = breakIdx;

   out.greensAfterBdCount = 0;
   for(int barIdx = breakIdx; barIdx < barCount && out.greensAfterBdCount < BREAKDOWN_GREENS_AFTER_BD_MAX; barIdx++)
   {
      if(m15[barIdx].close <= m15[barIdx].open)
         continue;
      const int gi = out.greensAfterBdCount;
      out.greensAfterBdHigh[gi] = m15[barIdx].high;
      out.greensAfterBdBarEndTime[gi] = m15[barIdx].time + 15 * 60;
      out.greensAfterBdCount++;
   }
   if(out.greensAfterBdCount > 0)
   {
      out.firstGreenHigh = out.greensAfterBdHigh[0];
      out.firstGreenBarEndTime = out.greensAfterBdBarEndTime[0];
      out.midpoint = (streakLowest + out.firstGreenHigh) / 2.0;
   }
   return true;
}

//+------------------------------------------------------------------+
//| All intraday M15 breakdown sequences; snap = latest not forgotten (so algo can hunt next breakdown). |
//+------------------------------------------------------------------+
void ComputeBreakdown15mState(const datetime dayStart, const datetime upToM1BarTime, const double strongRangePctMin,
   const int forgetAfterMinutes, const ENUM_BREAKDOWN_STREAK_CONTINUATION continuationMode, Breakdown15mState &out)
{
   ZeroMemory(out);
   MqlRates m15[];
   const int barCount = BreakdownCopyCompletedPeriodBarsToday(dayStart, upToM1BarTime, 15, m15);
   if(barCount <= 0)
      return;

   const ENUM_BREAKDOWN_STREAK_CONTINUATION mode = (ENUM_BREAKDOWN_STREAK_CONTINUATION)
      BreakdownNormalizeStreakContinuationMode(continuationMode);

   Breakdown15mState best;
   ZeroMemory(best);
   bool haveBest = false;
   int scanIdx = 0;
   while(scanIdx < barCount)
   {
      int startIdx = -1;
      for(int barIdx = scanIdx; barIdx < barCount; barIdx++)
      {
         if(BreakdownBarIsStrongRedStart(m15[barIdx], strongRangePctMin))
         {
            startIdx = barIdx;
            break;
         }
      }
      if(startIdx < 0)
         break;

      Breakdown15mState seq;
      int nextScanIdx = barCount;
      if(!BreakdownBuild15mSequenceFromStart(m15, barCount, startIdx, strongRangePctMin, mode, seq, nextScanIdx))
      {
         scanIdx = startIdx + 1;
         continue;
      }

      const bool forgotten = (!seq.sequenceActive && forgetAfterMinutes > 0 && seq.endTime > 0
         && upToM1BarTime > seq.endTime + forgetAfterMinutes * 60);
      if(!forgotten)
      {
         best = seq;
         haveBest = true;
      }

      scanIdx = (seq.sequenceActive ? barCount : nextScanIdx);
   }

   if(haveBest)
      out = best;
}

//+------------------------------------------------------------------+
string BreakdownContinuationModeLogSlug(const ENUM_BREAKDOWN_STREAK_CONTINUATION mode)
{
   switch(mode)
   {
      case BREAKDOWN_STREAK_CONTINUATION_CLOSES:   return "closes";
      case BREAKDOWN_STREAK_CONTINUATION_OHLC_AVG: return "ohlc_avg";
      case BREAKDOWN_STREAK_CONTINUATION_LOW:      return "low";
      case BREAKDOWN_STREAK_CONTINUATION_OC_MID:   return "oc_mid";
      case BREAKDOWN_STREAK_CONTINUATION_HL_MID:   return "hl_mid";
   }
   return "unknown";
}

//+------------------------------------------------------------------+
string BreakdownAuditLogFirstCandlePctColName(const double pctArg)
{
   string s = DoubleToString(pctArg, 2);
   StringReplace(s, ".", "_");
   return "1st_candle_breakdown_percent_arg_" + s;
}

//+------------------------------------------------------------------+
string BreakdownAuditLogFileName(const ENUM_BREAKDOWN_STREAK_CONTINUATION mode)
{
   return StringFormat("all_breakdowns_%s_streak%dorMore.csv",
      BreakdownContinuationModeLogSlug(mode), BREAKDOWN_AUDIT_LOG_MIN_STREAK_ARG);
}

//+------------------------------------------------------------------+
string BreakdownAuditSummaryFileName()
{
   return "all_breakdowns_summaries.csv";
}

//+------------------------------------------------------------------+
void BreakdownAuditSummaryReset()
{
   for(int modeIdx = 0; modeIdx < BREAKDOWN_STREAK_CONTINUATION_COUNT; modeIdx++)
   {
      g_breakdownAuditSummaryAcc[modeIdx].count = 0;
      g_breakdownAuditSummaryAcc[modeIdx].sumStreak = 0.0;
      g_breakdownAuditSummaryAcc[modeIdx].sumFirstCandlePct = 0.0;
      g_breakdownAuditSummaryAcc[modeIdx].sumTotalPercent = 0.0;
      g_breakdownAuditSummaryAcc[modeIdx].minTotalPercent = 0.0;
      g_breakdownAuditSummaryAcc[modeIdx].maxTotalPercent = 0.0;
      g_breakdownAuditSummaryAcc[modeIdx].hasTotalPercent = false;
   }
}

//+------------------------------------------------------------------+
void BreakdownAuditSummaryAccumulate(const int modeIdx, const Breakdown15mState &seq, const double firstCandlePct)
{
   if(modeIdx < 0 || modeIdx >= BREAKDOWN_STREAK_CONTINUATION_COUNT)
      return;
   BreakdownAuditSummaryAcc acc = g_breakdownAuditSummaryAcc[modeIdx];
   acc.count++;
   acc.sumStreak += (double)seq.endedLength;
   acc.sumFirstCandlePct += firstCandlePct;
   acc.sumTotalPercent += seq.totalPercent;
   if(!acc.hasTotalPercent)
   {
      acc.minTotalPercent = seq.totalPercent;
      acc.maxTotalPercent = seq.totalPercent;
      acc.hasTotalPercent = true;
   }
   else
   {
      acc.minTotalPercent = MathMin(acc.minTotalPercent, seq.totalPercent);
      acc.maxTotalPercent = MathMax(acc.maxTotalPercent, seq.totalPercent);
   }
   g_breakdownAuditSummaryAcc[modeIdx] = acc;
}

//+------------------------------------------------------------------+
void BreakdownAuditSummaryWrite()
{
   if(!bigflipper_log_all_breakdowns)
      return;

   const string fname = BreakdownAuditSummaryFileName();
   int fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;

   const string col1stArg = BreakdownAuditLogFirstCandlePctColName(BREAKDOWN_AUDIT_LOG_FIRST_CANDLE_BREAKDOWN_PERCENT_ARG);
   const string colStreakArg = StringFormat("streak_arg_%d", BREAKDOWN_AUDIT_LOG_MIN_STREAK_ARG);
   FileWrite(fh, "breakdown_type", colStreakArg, col1stArg, "count",
      "avg_streak_length", "avg_1st_candle_breakdown_percent", "avg_breakdown_total_percent",
      "min_breakdown_total_percent", "max_breakdown_total_percent");

   for(int modeIdx = 0; modeIdx < BREAKDOWN_STREAK_CONTINUATION_COUNT; modeIdx++)
   {
      const ENUM_BREAKDOWN_STREAK_CONTINUATION mode = (ENUM_BREAKDOWN_STREAK_CONTINUATION)modeIdx;
      const BreakdownAuditSummaryAcc acc = g_breakdownAuditSummaryAcc[modeIdx];
      const int n = acc.count;
      const double avgStreak = (n > 0) ? acc.sumStreak / (double)n : 0.0;
      const double avg1stPct = (n > 0) ? acc.sumFirstCandlePct / (double)n : 0.0;
      const double avgTotalPct = (n > 0) ? acc.sumTotalPercent / (double)n : 0.0;
      const string minTotalStr = (n > 0 && acc.hasTotalPercent) ? DoubleToString(acc.minTotalPercent, 2) : "";
      const string maxTotalStr = (n > 0 && acc.hasTotalPercent) ? DoubleToString(acc.maxTotalPercent, 2) : "";

      FileWrite(fh,
         BreakdownContinuationModeLogSlug(mode),
         IntegerToString(BREAKDOWN_AUDIT_LOG_MIN_STREAK_ARG),
         DoubleToString(BREAKDOWN_AUDIT_LOG_FIRST_CANDLE_BREAKDOWN_PERCENT_ARG, 2),
         IntegerToString(n),
         DoubleToString(avgStreak, 2),
         DoubleToString(avg1stPct, 2),
         DoubleToString(avgTotalPct, 2),
         minTotalStr,
         maxTotalStr);
   }
   FileClose(fh);
}

//+------------------------------------------------------------------+
string BreakdownAuditLogHeader()
{
   return StringFormat("breakdown_start,breakdown_end,%s,streak_arg_%d,breakdown_start_price,breakdown_end_price,breakdown_total_percent",
      BreakdownAuditLogFirstCandlePctColName(BREAKDOWN_AUDIT_LOG_FIRST_CANDLE_BREAKDOWN_PERCENT_ARG),
      BREAKDOWN_AUDIT_LOG_MIN_STREAK_ARG);
}

//+------------------------------------------------------------------+
void BreakdownAuditLogWriteHeader(const int fh)
{
   const string col1st = BreakdownAuditLogFirstCandlePctColName(BREAKDOWN_AUDIT_LOG_FIRST_CANDLE_BREAKDOWN_PERCENT_ARG);
   const string colStreak = StringFormat("streak_arg_%d", BREAKDOWN_AUDIT_LOG_MIN_STREAK_ARG);
   FileWrite(fh, "breakdown_start", "breakdown_end", col1st, colStreak,
      "breakdown_start_price", "breakdown_end_price", "breakdown_total_percent");
}

//+------------------------------------------------------------------+
bool BreakdownAuditLogAlreadyLogged(const datetime startTime, const int mode)
{
   for(int i = 0; i < g_breakdownAuditLoggedCount; i++)
   {
      if(g_breakdownAuditLoggedKeys[i].startTime == startTime && g_breakdownAuditLoggedKeys[i].mode == mode)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void BreakdownAuditLogMarkLogged(const datetime startTime, const int mode)
{
   if(g_breakdownAuditLoggedCount >= BREAKDOWN_AUDIT_LOG_DEDUP_MAX)
      return;
   g_breakdownAuditLoggedKeys[g_breakdownAuditLoggedCount].startTime = startTime;
   g_breakdownAuditLoggedKeys[g_breakdownAuditLoggedCount].mode = mode;
   g_breakdownAuditLoggedCount++;
}

//+------------------------------------------------------------------+
double BreakdownFirstCandleRangePctFromM15(const MqlRates &m15[], const int barCount, const datetime startTime)
{
   for(int barIdx = 0; barIdx < barCount; barIdx++)
   {
      if(m15[barIdx].time != startTime)
         continue;
      if(m15[barIdx].low <= 0.0)
         return 0.0;
      return (m15[barIdx].high - m15[barIdx].low) / m15[barIdx].low * 100.0;
   }
   return 0.0;
}

//+------------------------------------------------------------------+
void BreakdownAuditLogAppendRow(const ENUM_BREAKDOWN_STREAK_CONTINUATION mode, const Breakdown15mState &seq,
   const double firstCandleRangePct)
{
   const string fname = BreakdownAuditLogFileName(mode);
   int fh = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   FileSeek(fh, 0, SEEK_END);
   FileWrite(fh,
      TimeToString(seq.startTime, TIME_DATE|TIME_MINUTES),
      TimeToString(seq.endTime, TIME_DATE|TIME_MINUTES),
      DoubleToString(firstCandleRangePct, 2),
      IntegerToString(seq.endedLength),
      DoubleToString(seq.startHigh, _Digits),
      DoubleToString(seq.breakdownLow, _Digits),
      DoubleToString(seq.totalPercent, 2));
   FileClose(fh);
}

//+------------------------------------------------------------------+
void BreakdownResetAllBreakdownsAuditLogsOnInit()
{
   g_breakdownAuditLoggedCount = 0;
   g_breakdownAuditScanDayStart = 0;
   g_breakdownAuditLastM15CompleteTime = 0;
   BreakdownAuditSummaryReset();
   if(!bigflipper_log_all_breakdowns)
      return;
   for(int modeIdx = 0; modeIdx < BREAKDOWN_STREAK_CONTINUATION_COUNT; modeIdx++)
   {
      const string fname = BreakdownAuditLogFileName((ENUM_BREAKDOWN_STREAK_CONTINUATION)modeIdx);
      int fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(fh == INVALID_HANDLE)
         continue;
      BreakdownAuditLogWriteHeader(fh);
      FileClose(fh);
   }
   BreakdownAuditSummaryWrite();
}

//+------------------------------------------------------------------+
//| True when a new M15 bar has fully closed since the last audit scan (M1 timer only). |
//+------------------------------------------------------------------+
bool BreakdownAuditShouldScanOnM1Close(const datetime dayStart, const datetime upToM1BarTime)
{
   if(dayStart != g_breakdownAuditScanDayStart)
   {
      g_breakdownAuditScanDayStart = dayStart;
      g_breakdownAuditLastM15CompleteTime = 0;
   }

   const int shift = iBarShift(_Symbol, PERIOD_M15, upToM1BarTime, false);
   if(shift < 0)
      return false;

   datetime m15BarOpen = iTime(_Symbol, PERIOD_M15, shift);
   datetime m15BarComplete = m15BarOpen + 15 * 60;
   if(upToM1BarTime < m15BarComplete)
   {
      if(shift + 1 >= iBars(_Symbol, PERIOD_M15))
         return false;
      m15BarOpen = iTime(_Symbol, PERIOD_M15, shift + 1);
      m15BarComplete = m15BarOpen + 15 * 60;
   }

   if(m15BarComplete <= g_breakdownAuditLastM15CompleteTime)
      return false;
   g_breakdownAuditLastM15CompleteTime = m15BarComplete;
   return true;
}

//+------------------------------------------------------------------+
void BreakdownAuditLogScanDayIfNeeded(const datetime dayStart, const datetime upToM1BarTime, const bool force)
{
   if(!bigflipper_log_all_breakdowns || dayStart <= 0 || upToM1BarTime < dayStart)
      return;
   if(!force && !BreakdownAuditShouldScanOnM1Close(dayStart, upToM1BarTime))
      return;
   BreakdownAuditLogScanDay(dayStart, upToM1BarTime);
}

//+------------------------------------------------------------------+
//| Per-run audit: all completed M15 breakdowns (independent of algos) for each continuation type. |
//+------------------------------------------------------------------+
void BreakdownAuditLogScanDay(const datetime dayStart, const datetime upToM1BarTime)
{
   if(!bigflipper_log_all_breakdowns || dayStart <= 0 || upToM1BarTime < dayStart)
      return;

   MqlRates m15[];
   const int barCount = BreakdownCopyCompletedPeriodBarsToday(dayStart, upToM1BarTime, 15, m15);
   if(barCount <= 0)
      return;

   const double strongRangePctMin = BREAKDOWN_AUDIT_LOG_FIRST_CANDLE_BREAKDOWN_PERCENT_ARG;
   const int minStreak = BREAKDOWN_AUDIT_LOG_MIN_STREAK_ARG;

   for(int modeIdx = 0; modeIdx < BREAKDOWN_STREAK_CONTINUATION_COUNT; modeIdx++)
   {
      const ENUM_BREAKDOWN_STREAK_CONTINUATION mode = (ENUM_BREAKDOWN_STREAK_CONTINUATION)modeIdx;
      int scanIdx = 0;
      while(scanIdx < barCount)
      {
         int startIdx = -1;
         for(int barIdx = scanIdx; barIdx < barCount; barIdx++)
         {
            if(BreakdownBarIsStrongRedStart(m15[barIdx], strongRangePctMin))
            {
               startIdx = barIdx;
               break;
            }
         }
         if(startIdx < 0)
            break;

         Breakdown15mState seq;
         int nextScanIdx = barCount;
         if(!BreakdownBuild15mSequenceFromStart(m15, barCount, startIdx, strongRangePctMin, mode, seq, nextScanIdx))
         {
            scanIdx = startIdx + 1;
            continue;
         }

         if(!seq.sequenceActive && seq.endedLength >= minStreak && seq.endTime > 0
            && !BreakdownAuditLogAlreadyLogged(seq.startTime, modeIdx))
         {
            const double firstCandlePct = BreakdownFirstCandleRangePctFromM15(m15, barCount, seq.startTime);
            BreakdownAuditLogAppendRow(mode, seq, firstCandlePct);
            BreakdownAuditLogMarkLogged(seq.startTime, modeIdx);
            BreakdownAuditSummaryAccumulate(modeIdx, seq, firstCandlePct);
         }

         scanIdx = (seq.sequenceActive ? barCount : nextScanIdx);
      }
   }
   BreakdownAuditSummaryWrite();
}

//+------------------------------------------------------------------+
void FinalizeCurrentCandle()
{
   datetime candleDay = current_candle_time - (current_candle_time % 86400);
   string dateStr = TimeToString(current_candle_time,TIME_DATE);

   if(dailySpamLog_AllCandles && allCandlesFileDate != candleDay)
   {
      if(allCandlesFileHandle != INVALID_HANDLE)
         FileClose(allCandlesFileHandle);

      string allFileName = dateStr + "-AllCandlesLog_Timer1.csv";
      int fileHandleAll = FileOpen(allFileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(fileHandleAll == INVALID_HANDLE)
         fileHandleAll = FileOpen(allFileName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(fileHandleAll == INVALID_HANDLE)
         FatalError("FinalizeCurrentCandle: could not open " + allFileName);
      FileSeek(fileHandleAll, 0, SEEK_END);
      if(FileTell(fileHandleAll) == 0)
         FileWrite(fileHandleAll, "time", "O", "H", "L", "C", "spreadOf_lastTick");
      allCandlesFileHandle = fileHandleAll;
      allCandlesFileDate = candleDay;
   }

   // Day stat: once after 21:30 candle, set dayStat_hasGapDown (RTH open < PD RTH close) and write dayPriceStat_and_gapstat_log + summaryLog_gapDowns / _gapUps
   {
      MqlDateTime mqlTime;
      TimeToStruct(current_candle_time, mqlTime);
      if(mqlTime.hour == 21 && mqlTime.min == 30)
      {
         TryLogDayStatForCurrentDay();  // per-day log written (or skipped by dailyEODlog_DayStat inside)
         if(finalLog_DayStatSummary)
            WriteDayStatSummaryCsv();
      }
   }

   for(int i=0;i<ArraySize(levels);i++)
   {
      if(current_candle_time >= levels[i].validFrom && current_candle_time <= levels[i].validTo)
      {
         double lvl = levels[i].price;

         // daily bias
         if(levels[i].lastBiasDate != candleDay)
         {
            levels[i].dailyBias = (candle_close > lvl ? 1 : -1);
            levels[i].lastBiasDate = candleDay;
            levels[i].recoverCount = 0;
            levels[i].consecutiveRecoverCandles = 0;
            levels[i].candlesBreakLevelCount = 0;
            levels[i].count = 0;

            if(levels[i].logRawEv_fileHandle != INVALID_HANDLE)
               FileClose(levels[i].logRawEv_fileHandle);

            if(bigflipper_log_Arawevents)
            {
            string levelTag = levels[i].baseName;
            const string tagPrefix = dateStr + "_";
            if(StringFind(levelTag, tagPrefix) == 0)
               levelTag = StringSubstr(levelTag, StringLen(tagPrefix));
            string araFile = StringFormat("%s-%s_Arawevents_%s_%s_week_%s.csv",
               dateStr, dateStr, DoubleToString(MathAbs(lvl), _Digits), levelTag, dateStr);

            int fileHandleAra = FileOpen(araFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
            if(fileHandleAra == INVALID_HANDLE)
               fileHandleAra = FileOpen(araFile, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
            if(fileHandleAra == INVALID_HANDLE)
               FatalError("FinalizeCurrentCandle: could not open " + araFile);
            FileSeek(fileHandleAra, 0, SEEK_END);
            if(FileTell(fileHandleAra) == 0)
            {
               const string colAraProx = FalgoLogCol_contactAndProximityCount("ClosestLevel_");
               FileWrite(fileHandleAra, "time", "level", "O", "H", "low", "C", "closestPriceProximity", "DayBias", "Contact",
                  "ClosestLevel_physicalContactCount_today", colAraProx,
                  "ClosestLevel_BounceCount_today", "CandlesPassedSinceLastBounce",
                  "ClosestLevel_CeilingCount_today", "ClosestLevel_CeilingProximityCandles_today", "CandlesPassedSinceLastCeiling",
                  "CandlesBreakLevelCount", "RecoverCount");
            }
            levels[i].logRawEv_fileHandle = fileHandleAra;
            }
            else
               levels[i].logRawEv_fileHandle = INVALID_HANDLE;
         }

         const double closestPriceProximity = GetBarClosestPriceProximityToLevel(candle_high, candle_low, lvl);
         const bool physicallyTouched = IsBarInPhysicalContactWithLevel(candle_open, candle_high, candle_low, candle_close, lvl);
         const bool in_contact = IsBarInContactWithLevel(candle_open, candle_high, candle_low, candle_close, lvl);
         const int barIdx = FalgoBarIdxForDayOpenTime(current_candle_time);
         int bounceCountToday = 0, ceilingCountToday = 0, proxCountToday = 0;
         int physicalContactCountToday = 0, contactAndProximityCountToday = 0;
         int candlesSinceBounce = 0, candlesSinceCeiling = 0;
         FalgoGetAlgoFamilyLevelDayStatsAtBar(lvl, barIdx,
            bounceCountToday, ceilingCountToday, proxCountToday, contactAndProximityCountToday,
            candlesSinceBounce, candlesSinceCeiling);
         const int trackIdxAra = AlgoFamilyTrackIdxForLevelPrice(lvl);
         if(trackIdxAra >= 0 && barIdx >= 0 && barIdx < g_barsInDay)
            physicalContactCountToday = g_algoFamilyLevelStatsAtBar[trackIdxAra][barIdx].physicalContactCount_today;

         if(physicallyTouched) levels[i].count++;

         // --- Track broken level
         bool breached = false;
         if(levels[i].dailyBias > 0 && candle_low - lvl <= LevelCountsAsBroken_Threshold) breached = true;
         if(levels[i].dailyBias < 0 && candle_high - lvl >= -LevelCountsAsBroken_Threshold) breached = true;
         if(breached) levels[i].candlesBreakLevelCount++;

         // --- Track recovery
         bool fullCandleAbove = (levels[i].dailyBias > 0 ? candle_low > lvl : candle_high < lvl);
         if(fullCandleAbove)
            levels[i].consecutiveRecoverCandles++;
         else
            levels[i].consecutiveRecoverCandles = 0;

         if(levels[i].consecutiveRecoverCandles >= HowManyCandlesAboveLevel_CountAsPriceRecovered)
         {
            levels[i].recoverCount++;
            levels[i].consecutiveRecoverCandles = 0;
         }

         // --- Write Arawevents (CSV row)
         if(levels[i].logRawEv_fileHandle != INVALID_HANDLE)
         {
            FileWrite(levels[i].logRawEv_fileHandle,
               TimeToString(current_candle_time, TIME_DATE|TIME_MINUTES),
               DoubleToString(lvl, _Digits),
               DoubleToString(candle_open, _Digits), DoubleToString(candle_high, _Digits), DoubleToString(candle_low, _Digits), DoubleToString(candle_close, _Digits),
               DoubleToString(closestPriceProximity, _Digits),
               (levels[i].dailyBias > 0 ? "bias_long" : "bias_short"),
               (in_contact ? "in_contact" : "no_contact"),
               IntegerToString(physicalContactCountToday),
               IntegerToString(contactAndProximityCountToday),
               IntegerToString(bounceCountToday),
               IntegerToString(candlesSinceBounce),
               IntegerToString(ceilingCountToday),
               IntegerToString(proxCountToday),
               IntegerToString(candlesSinceCeiling),
               IntegerToString(levels[i].candlesBreakLevelCount),
               IntegerToString(levels[i].recoverCount));
         }

      }
   }

   if(allCandlesFileHandle != INVALID_HANDLE)
   {
      double spread = g_liveAsk - g_liveBid;
      FileWrite(allCandlesFileHandle,
         TimeToString(current_candle_time, TIME_DATE|TIME_MINUTES),
         DoubleToString(candle_open, _Digits), DoubleToString(candle_high, _Digits), DoubleToString(candle_low, _Digits), DoubleToString(candle_close, _Digits),
         DoubleToString(spread, _Digits));
   }

   if(first_candle_time==0)
   {
      first_candle_time=current_candle_time;
      first_open=candle_open; first_high=candle_high;
      first_low=candle_low;   first_close=candle_close;
   }

   last_candle_time=current_candle_time;
   last_open=candle_open; last_high=candle_high;
   last_low=candle_low;   last_close=candle_close;

   current_candle_time=0;
}