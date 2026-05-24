//+------------------------------------------------------------------+
//|                                                    smashelito.mq5 |
//+------------------------------------------------------------------+
//|                   MetaTrader 5 Only (MT5-specific code)          |
//|        Copyright 2026, Aleksander Stefankowski                   |
// NOTE: This EA is MetaTrader 5 (MT5) ONLY. Do NOT attempt to add MT4 code.
// All file operations and timer/candle handling are MT5-specific.
// '&' reference cannot ever be used!
//
// OVERFLOW: Magic numbers and MT5 IDs (order/deal/position) can exceed INT_MAX.
// Never cast them to (int). Use long/ulong and IntegerToString((long)value) for logging.
// COMPOSITE MAGIC: 18-digit fixed-width magics; first 2 digits = algo number (10..99). Never paste full magic in comments.


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
double   ProximityThreshold   = 1.0;
double   LevelCountsAsBroken_Threshold = -2.5; // how deep close must breach to count as broken
input int      HowManyCandlesAboveLevel_CountAsPriceRecovered = 6; // for RecoverCount
// false: skip per-bar UpdateTradeResultsForDay (no HistorySelect each M1); g_tradeResults cleared each bar — EOD block still calls UpdateTradeResultsForDay once before trade-results CSV (and after EOD closes). Intraday pullinghistory/dayProgress rows stay deal-empty until that EOD refresh.
input bool     InpLoadTradeResultsFromHistory = true;
bool     InpEODLogging = true;  // if true: at 21:58-22:00 write EOD logs (pullinghistory_algofamily, algo trade results, levels, etc.)
//--- Log to file: set false to disable that log (optimization)
//    finalLog_ = one file across whole run; dailyEODlog_ = daily once at EOD; dailySpamLog_ = daily and frequent
bool     dailyEODlog_PullingHistoryAlgoFamily = true;  // (date)_testing_pullinghistory_algofamily.csv (closest weekly level + algo family columns)
bool     dailyEODlog_DailySummary     = true;  // Day_activeLevels, account, orders, deals (WriteDailySummary)
bool     dailyEODlog_EodTradesSummary = true;  // (date)_summary_EOD_tradesSummary1line.csv
// Trade-results CSV referencePointsAbove/Below: min distance when bigflipper_tradeResult_referencePoints_excludeTooClose is true (see bigflipper block).
double   tradeResult_referencePointMinAbsDiffFromLevel = 4.0; //bookmark // price points; omit ref when |ref - level| < this and exclusion bigflipper is on
bool     dailyEODlog_TestinglevelsPlus =      true;     // (date)_testinglevelsplus_(level)_(tag).csv per level
bool     dailyEODlog_BreakCheck       = true;  // levels_breakCheck files + summary
bool     dailySpamLog_LivePrice       = true;  // (date)_testing_liveprice.csv 21:35-21:37
bool     dailyEODlog_DayStat          = true;  // (date)_dayPriceStat_log.csv (TryLogDayStatForCurrentDay)
bool     dailyLog_StaticMarketContext = true;  // (date)_staticMarketContext_log.csv — PDO/PDH/PDL/PDC once per day right after UpdateStaticMarketContext
bool     dailyLog_algoFamilyWeekPerspective = true;  // (date)_algofamily_weekPerspective.csv — weekly levels vs current-week M1 (skipped on Monday)
bool     velocity_parameter_testing = true;  // (date)_algoN_velocity_parameter_testing.csv — profitVelocity + avg per tested window (open trade, persecond_debug)
bool     finalLog_DayStatSummary      = true;  // dayPriceStat_summaryLog.csv (WriteDayStatSummaryCsv)
bool     finalLog_TradeLog            = true; // B_TradeLog_<composite per algo>.csv (WriteTradeLog)
bool     dailySpamLog_AllCandles      = true;  // (date)-AllCandlesLog_Timer1.csv
bool     finalLog_FirstLastCandle     = true;  // InpSessionFirstLastCandleFile (OnDeinit)
bool     dailySpamLog_Arawevents      = true; // Arawevents CSV + level logRawEv (FinalizeCurrentCandle)
string   InpCalendarFile        = "calendar_2026_dots.csv";  // CSV in Terminal/Common/Files: date (YYYY.MM.DD),dayofmonth,dayofweek,opex,qopex
string   InpLevelsFile          = "levelsinfo_zeFinal.csv";  // CSV in Terminal/Common/Files: start,end,levelPrice,categories,tag
double   InpBreakCheckMaxDistPoints = 9.0;  // levels_breakCheck: first candle beyond this distance in price (and all newer) excluded
bool     maemfe_testing             = false; // if true: all trades use TP=SL=3000.0 and close any position open >20 min (OnTimer)
//--- Big flippers bookmark: master off for heavy algo logs (when false, no write for any registered algo)
bool     bigflipper_log_algo_gates_per_minute              = true;  // (date)_algoN_gates_per_minute.csv — all wired algos
bool     bigflipper_log_algo_trade_results_csv             = true;  // per-algo EOD CSV + all-days TSV + summary_tradeResults_all_days.tsv
bool     bigflipper_log_B_TradeLog                         = true;  // (date)_B_TradeLog_<magic>.csv
bool     bigflipper_log_algo_velocity_parameter_testing    = false;  // (date)_algoN_velocity_parameter_testing.csv
bool     bigflipper_log_algo__trade_telemetry_per_second   = false;  // (date)_algoN_trade_telemetry_per_second.csv
bool     bigflipper_tradeResult_referencePoints_excludeTooClose = false;  // trade-results CSV: omit any ref when |ref - level| < tradeResult_referencePointMinAbsDiffFromLevel
bool     babysit_global_flipper = true; // bookmark3. when true, OnTimer may run per-row SL babysit for positions whose variant has babysit_enabled
bool     babysit_secret_TPSL = true; // if true, I will be using bigger TPSL but aim to auto close via _Xpercent_onWayTo_

//--- Global base trade size: actual lot = base × (trade_size_percentage/100). Each ruleset has its own percentage (10,20,...,100).
// base lot; 100% trade type = this full size; 50% = half, for example 0.1, tradesize 10 is 0.01, size 30 is 0.03
// for example, 0.5, and specific trade is 30%, would mean position 0.15, 60% = 0.30
// for example, 1.2, and specific trade is 30%, would mean position 0.36, 50% = 0.60
// profit factor danego trade jest stały przy jego różnych trade size, ale profit factor całego runu zmieni się bo zmieniają się proporcje absolutnego zysku


double   g_global_base_trade_size = 0.001; //  0.001 min. bookmark9 basetradesize basesize defaultsize globalsize
#define TRADE_VARIANT_COUNT_MAX_LOTSIZE 4.0
const double ACCOUNT_SIZE_PLN_FOR_TRADE_SIZE = 50000000.0; //  5000000.0/ PLN budget ceiling vs ValidateBaseTradeSizeVsAccountBudgetOnInit()

// OnTimer (1s): FatalError if (used margin / equity)×100 exceeds this (terminal-style deposit load as % of equity locked in margin). 0 = disabled.
double   DepositLoadFatalThresholdPct = 0.0; // ≤ 0 disables the check

//--- Algo family pipeline: per-algo open/pending on _Symbol (refreshed once per tick via RefreshOccupiedMagicsCache).
bool   g_occupiedAlgoFamilySlots[100];  // index = algo number 10..99: open position or pending on _Symbol
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
   int approxContactCount;
   double dailyBias;
   bool biasSetToday;
   datetime lastBiasDate;
   int logRawEv_fileHandle;
   int candlesBreakLevelCount;
   int recoverCount;
   int bounceCount;
   int consecutiveRecoverCandles;
   bool lastCandleInContact;
   int candlesPassedSinceLastBounce;
   int ceilingCount;
   int candlesPassedSinceLastCeiling;
   bool contactFromBelow;  // true while in-contact episode approached from below (close < level)
};
Level levels[];

//--- Algo-family composite magic (18 digits) + B_TradeLog filename
const long DEFAULT_ORDER_MAGIC = 47001; // restore CTrade magic when not using an algo composite magic

// First 2 digits = algo number 10..99 (10, 11, 12 active; 13..99 reserved).
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
#define MAX_CALENDAR_ROWS 367
CalendarRow g_calendar[MAX_CALENDAR_ROWS];
int g_calendarCount = 0;

//--- Levels (loaded from levelsinfo_zeFinal CSV in OnInit)
struct LevelInfoRow
{
   string startStr;   // "YYYY.MM.DD"
   string endStr;     // "YYYY.MM.DD"
   double levelPrice;
   string categories; // e.g. "daily_monday_smash_stacked"
   string tag;       // e.g. "dailySmash", "weeklyUp1" (loaded but not used yet)
};
#define MAX_LEVEL_ROWS 2000
LevelInfoRow g_levels[MAX_LEVEL_ROWS];
int g_levelsTotalCount = 0;  // levels for current day only (reloaded each new day)
string g_levelsLoadedForDate = "";  // YYYY.MM.DD for which g_levels was loaded (empty = not yet loaded)

//--- Levels expanded (built in testing loop: each level of the day vs whole price chart; newway_Diff_CloseToLevel per bar)
struct LevelExpandedRow
{
   double levelPrice;
   string tag;
   string categories;  // from CSV; used to exclude tertiary from break-check summary
   int    count;      // number of bars
   double diffs[];    // newway_Diff_CloseToLevel = close - levelPrice per bar
   datetime times[];  // bar time per bar
};
#define MAX_LEVELS_EXPANDED 500 // per day
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

//--- algofamily_weekPerspective: active weekly levels vs current-week M1 (rebuilt OnInit + each new day)
struct AlgoFamilyWeekPerspectiveRow
{
   double levelPrice;
   string tag;
   string categories;
   double maxPriceAbove;       // max(high - level) when high > level
   double maxPriceBelow;       // max(level - low) when low < level
   int    touchedProx_09_C;    // bars with proximity overlap band: low <= level+0.9 && high >= level-0.9
   bool   brokenBool;          // price traversed level this week: level between min ONO & max other high, or between min other low & max ONO
   int    countONO_too_close_10p; // days in week where |level - that day's ONO| < 10 (ONO = first M1 open, same as g_ONopen)
   int    candle_overlap_1m_C; // bars with low <= level <= high
   int    bounceCount;         // week total: first no-contact candle fully above level after contact (Arawevents bounce logic)
   int    ceilingCount;        // week total: first no-contact candle fully below after in-contact-from-below (Arawevents ceiling logic)
};
#define MAX_ALGOFAMILY_WEEK_LEVELS 25   // ~20 weekly levels per week + small headroom
#define ALGO5_WEEK_PROX_TOUCH_POINTS 0.9
#define ALGO5_WEEK_ON_TOO_CLOSE_POINTS 10.0
AlgoFamilyWeekPerspectiveRow g_algoFamilyWeekPerspective[MAX_ALGOFAMILY_WEEK_LEVELS];
int      g_algoFamilyWeekPerspectiveCount = 0;
string   g_algoFamilyWeekPerspectiveEvaluatedForDate = "";  // YYYY.MM.DD last (re)evaluated

//--- testing_pullinghistory_algofamily: per-bar snapshot (weekly stats in UpdatePullingHistoryAlgoFamilyPerBarStats; account+day in UpdatePullingHistoryAlgoFamilyAccountBarStats after UpdateDayProgress). As-of each bar's candle close time.
struct PullingHistoryAlgoFamilyBarSnap
{
   double   closestWeeklyLevelToCClose;
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
   int      closestWeeklyLevel_BounceCount_recent;
   int      closestWeeklyLevel_CeilingCount_recent;
   int      closestWeeklyLevel_contactCount_today;
   bool     accOpenTradeNowBool;       // symbol day trades open at this bar's close
   datetime accOpenTradeTime;          // startTime of latest still-open trade; 0 if none
   datetime accLastClosedTradeTime;    // max endTime among trades closed before this bar's close; 0 if none
   double   dayWinRate;                // mirror g_dayProgress (closed trades before bar close)
   int      dayTradesCount;
   double   dayPointsSum;
   double   dayProfitSum;
};
PullingHistoryAlgoFamilyBarSnap g_pullingHistoryAlgoFamilyAtBar[MAX_BARS_IN_DAY];

//--- algo family: shared profile + per-algo rules (algo10, algo11, algo12)
struct AlgoSharedProfile
{
   int    tradeSizePct;
   string bannedRanges;
   bool   babysit_enabled;
   bool   tradesWeeklyLevels;
   bool   tradesDailyLevels;
   string tradesDays;              // e.g. "12345" = Mon..Fri
   bool   secretTPSL;
   int    secretTPSL_percent;
   double initialTP;
   double initialSL;
   bool   persecond_debug_enabled;
   int    persecond_debug_start_hour;
   int    persecond_debug_start_minute;
   int    persecond_debug_end_hour;
   int    persecond_debug_end_minute;
   int    revenge_long_allowed_perdayCount;
   int    revenge_short_allowed_perdayCount;
   double revenge_initialTP;
   double revenge_initialSL;
   int    stop_trading_today_if_AllAlgos_losing_trades_count;
   int    stop_trading_today_if_AllAlgos_winning_trades_count;
};

struct AlgoPerAlgoTune
{
   int    stop_trading_today_if_thisAlgo_losing_trades_count;
   int    stop_trading_today_if_thisAlgo_winning_trades_count;
   int    babysitStart_minute;
   double neutral_trade_TP;                    // signed; 0=breakeven; close when profit >= target
   double strong_trade_TP;                     // signed; 0=breakeven; close when profit >= target
   bool   strong_trade_mode_enabled;
   bool   badtrade_mode_enabled;
   bool   terribletrade_mode_enabled;
   double strong_trade_eval_min_profit_pts;
   double strong_trade_min_velocity_trigger;
   int    strong_trade_velocity_window_seconds;
   double strong_trade_stall_velocity_max_trigger;
   double strong_trade_stall_giveback_pts_trigger;
   double strong_trade_stall_min_close_profit_pts;
   int    telemetry_velocity_window_seconds;
   int    telemetry_avg_velocity_window_seconds;
   bool   trade_telemetry_per_second_enabled;  // (date)_algoN_trade_telemetry_per_second.csv during persecond_debug window
   double badtrade_profit_trigger;             // negative mae latch depth when badtrade_mode_enabled
   int    badtrade_totalRedSeconds_minTrigger; // min total red seconds required to latch bad trade
   double badtrade_try_save_TP;                // signed; 0=breakeven; close when profit >= target
   double terribletrade_profit_trigger;        // negative mae latch depth when terribletrade_mode_enabled
   int    terribletrade_consecutiveRedSeconds_minTrigger;  // min consecutive red seconds required to latch terrible trade
   double terribletrade_avgProfitVelocity10_trigger;       // avg profit velocity (10s window) must be < this to latch
   double terribletrade_try_smaller_loss_TP;   // signed; 0=breakeven; close when profit >= target
};

enum ENUM_ALGO_RULE
{
   RULE_CLEAN_STREAK_LONG,
   RULE_CLEAN_STREAK_SHORT,
   RULE_BOUNCE_COUNT_TOO_HIGH,
   RULE_BOUNCE_COUNT_TOO_LOW,
   RULE_RECENT_BOUNCE_TOO_HIGH,
   RULE_CEILING_COUNT_TOO_HIGH,
   RULE_SHORTS_AT_LEVEL_LIMIT,
   RULE_CLOSEST_WEEKLY_LEVEL_MISSING,
   RULE_WEEK_BOUNCE_TOO_HIGH,
   RULE_WEEK_CEILING_TOO_HIGH,
   RULE_LEVEL_ONO_ABS_DIFF_TOO_LOW,
   RULE_PD_RED,
   RULE_DAY_BROKE_PDL,
   RULE_DAY_BROKE_PDH,
   RULE_LEVEL_ABOVE_ONL,
   RULE_LEVEL_BELOW_DAY_HIGH,
   RULE_LEVEL_BELOW_PDH,
   RULE_LEVEL_ABOVE_DAY_LOW
};

#define ALGO_RULES_MAX            16
#define ALGO_FAMILY_REGISTRY_MAX  10

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
   bool           blockPlacementIfFamilyOpenOrPending;
   bool           trades_short;
   AlgoPerAlgoTune tune;
   double         levelOffset;
   double         priceProximity;
   int            expiry_minutes;
   int            recentBounceCountToday_Minutes;
   int            recentCeilingCountToday_Minutes;
   double         min_anchorAbove_cleanStreak;
   double         min_anchorBelow_cleanStreak;
   int            min_cleanOHLC_streak_count;
   int            bounceMaxAllowed_today;
   int            min_bounceCount;
   int            recentBounceCount_max_allowed;
   int            ceilingMaxAllowed_today;
   int            max_allowed_shorts_perLevel_perDay_forThisAlgo;
   int            max_weekly_bounce_allowed;
   int            max_weekly_ceiling_allowed;
   double         min_levelOnoAbsDiff;
   AlgoRuleEntry  rules[ALGO_RULES_MAX];
   int            rule_count;
};

AlgoSharedProfile g_algoShared;
AlgoDef           g_algos[ALGO_FAMILY_REGISTRY_MAX];
int               g_algoCount = 0;

#define ALGOFAMILY_BOUNCE_CEILING_EVENTS_MAX 64

//--- Per weekly level: running day state (updated every bar; log uses closest level's state at each bar)
struct WeeklyLevelAlgoFamilyDayState
{
   double   levelPrice;
   int      contactCount_today;
   int      bounceCount_today;
   int      ceilingCount_today;
   datetime bounceEventTimes[ALGOFAMILY_BOUNCE_CEILING_EVENTS_MAX];
   int      bounceEventCount;
   datetime ceilingEventTimes[ALGOFAMILY_BOUNCE_CEILING_EVENTS_MAX];
   int      ceilingEventCount;
   bool     lastInContact;
   bool     contactFromBelow;
   datetime cleanStreakStartTime;
   int      cleanStreakCount;
   double   cleanStreakOHLCSum;
   bool     cleanStreakIsAbove;
   double   anchorAbove;      // clean-above streak: max(high - level)
   datetime anchorAboveTime;
   double   anchorBelow;      // clean-below streak: max(level - low)
   datetime anchorBelowTime;
};
int g_weeklyAlgoFamilyTrackExpandedIdx[MAX_ALGOFAMILY_WEEK_LEVELS];  // index into g_levelsExpanded
int g_weeklyAlgoFamilyTrackCount = 0;

//--- Gap-up mirror (RTH open > PD RTH close)
double   dayStat_openGapUp_percentageFill = 0.0;
int      dayStat_daysWithGapUp = 0;
int      dayStat_daysWithoutGapUp = 0;
double   dayStat_gapUp_fillPercentSum = 0.0;
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
//--- Trade results for the day
#define MAX_TRADE_RESULTS 7777
#define MAX_DEALS_DAY 7777
struct TradeResult
{
   string symbol;
   datetime startTime;
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
   string session;        // ON|RTH-IB|RTH-afterIB|sleep from startTime (GetSessionForTradeTime)
   bool foundOut;
};
TradeResult g_tradeResults[MAX_TRADE_RESULTS];
int g_tradeResultsCount = 0;
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
// Proximity (price distance): do not add PDrthClose or todayRTHopen if a level valid for that day is within this distance
const double tertiaryLevel_tooTight_toAdd_proximity = 2.0;

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
//| Session at trade open time for summary_tradeResults_all_days: ON until RTH open; RTH-IB first RTH hour; RTH-afterIB until RTH end; sleep after. |
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
//| True if t is in the EOD log window (21:58–22:00 inclusive). Used to gate pullinghistory and other daily logs. |
//| WARNING: Setting the window even 1 minute later (e.g. 21:59) can break EOD logging: the tester may not deliver a tick in that later minute, so summaryZ_tradeResults and summary_tradeResults_all_days may never be written. |
//+------------------------------------------------------------------+
bool IsInEODLogWindow(datetime t)
{
   MqlDateTime mql;
   TimeToStruct(t, mql);
   int minOfDay = mql.hour * 60 + mql.min;
   return (minOfDay >= 21*60+58 && minOfDay <= 22*60+0);
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
//| Day broke PDH at trade open time. Returns "true"/"false" based on g_dayBrokePDHAtBar; "unknown" if bar not found. |
//+------------------------------------------------------------------+
string GetDayBrokePDHAtTradeOpenTime(datetime tradeOpenTime)
{
   datetime barOpenTime = tradeOpenTime - (tradeOpenTime % 60);
   int barIdx = -1;
   for(int i = 0; i < g_barsInDay; i++)
      if(g_m1Rates[i].time == barOpenTime) { barIdx = i; break; }
   if(barIdx < 0) return "unknown";
   return g_dayBrokePDHAtBar[barIdx] ? "true" : "false";
}

//+------------------------------------------------------------------+
//| Day broke PDL at trade open time. Returns "true"/"false" based on g_dayBrokePDLAtBar; "unknown" if bar not found. |
//+------------------------------------------------------------------+
string GetDayBrokePDLAtTradeOpenTime(datetime tradeOpenTime)
{
   datetime barOpenTime = tradeOpenTime - (tradeOpenTime % 60);
   int barIdx = -1;
   for(int i = 0; i < g_barsInDay; i++)
      if(g_m1Rates[i].time == barOpenTime) { barIdx = i; break; }
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
//| Reference points above/below the trade level price at trade open time (M1 bar at tradeOpenTime). Skips refs that are "unknown". When bigflipper_tradeResult_referencePoints_excludeTooClose: omit ref if |ref - level| < tradeResult_referencePointMinAbsDiffFromLevel. Tie at level → above. |
//+------------------------------------------------------------------+
void GetReferencePointsAboveBelow(datetime tradeOpenTime, double levelPrice, string &outAbove, string &outBelow)
{
   outAbove = "";
   outBelow = "";
   datetime barOpenTime = tradeOpenTime - (tradeOpenTime % 60);
   int barIdx = -1;
   for(int i = 0; i < g_barsInDay; i++)
      if(g_m1Rates[i].time == barOpenTime) { barIdx = i; break; }
   if(barIdx < 0) return;
   datetime dayStart = g_m1DayStart;
   string dateStr = TimeToString(dayStart, TIME_DATE);

   const bool rp_excludeTooClose = bigflipper_tradeResult_referencePoints_excludeTooClose;
   const double rp_minAbs = tradeResult_referencePointMinAbsDiffFromLevel;
   double v = 0.0;
   if(g_staticMarketContext.PDOpreviousDayRTHOpen > 0.0) { v = g_staticMarketContext.PDOpreviousDayRTHOpen; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "PDO"; else outBelow += (outBelow != "" ? ";" : "") + "PDO"; } }
   if(g_staticMarketContext.PDHpreviousDayHigh > 0.0) { v = g_staticMarketContext.PDHpreviousDayHigh; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "PDH"; else outBelow += (outBelow != "" ? ";" : "") + "PDH"; } }
   if(g_staticMarketContext.PDLpreviousDayLow > 0.0) { v = g_staticMarketContext.PDLpreviousDayLow; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "PDL"; else outBelow += (outBelow != "" ? ";" : "") + "PDL"; } }
   if(g_staticMarketContext.PDCpreviousDayRTHClose > 0.0) { v = g_staticMarketContext.PDCpreviousDayRTHClose; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "PDC"; else outBelow += (outBelow != "" ? ";" : "") + "PDC"; } }
   if(g_ONhighSoFarAtBar[barIdx].hasValue) { v = g_ONhighSoFarAtBar[barIdx].value; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "ONH"; else outBelow += (outBelow != "" ? ";" : "") + "ONH"; } }
   if(g_ONlowSoFarAtBar[barIdx].hasValue) { v = g_ONlowSoFarAtBar[barIdx].value; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "ONL"; else outBelow += (outBelow != "" ? ";" : "") + "ONL"; } }
   if(GetRthHighSoFarAtBar(barIdx, dayStart, dateStr, v)) { if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "RTHH"; else outBelow += (outBelow != "" ? ";" : "") + "RTHH"; } }
   if(GetRthLowSoFarAtBar(barIdx, dayStart, dateStr, v)) { if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "RTHL"; else outBelow += (outBelow != "" ? ";" : "") + "RTHL"; } }
   if(GetIBlowAtBar(barIdx, v)) { if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "IBL"; else outBelow += (outBelow != "" ? ";" : "") + "IBL"; } }
   if(GetIBhighAtBar(barIdx, v)) { if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "IBH"; else outBelow += (outBelow != "" ? ";" : "") + "IBH"; } }
   if(g_dayHighSoFarAtBar[barIdx].hasValue) { v = g_dayHighSoFarAtBar[barIdx].value; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "dayHighSoFar"; else outBelow += (outBelow != "" ? ";" : "") + "dayHighSoFar"; } }
   if(g_dayLowSoFarAtBar[barIdx].hasValue) { v = g_dayLowSoFarAtBar[barIdx].value; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "dayLowSoFar"; else outBelow += (outBelow != "" ? ";" : "") + "dayLowSoFar"; } }
   if(g_sessionRangeMidpointAtBar[barIdx].hasValue) { v = g_sessionRangeMidpointAtBar[barIdx].value; if(!rp_excludeTooClose || MathAbs(v - levelPrice) >= rp_minAbs) { if(v >= levelPrice) outAbove += (outAbove != "" ? ";" : "") + "midpoint"; else outBelow += (outBelow != "" ? ";" : "") + "midpoint"; } }
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
//| If we have valid today RTH open, add it as a tertiary level (todayRTHopen) unless already present or too close to another level. |
//+------------------------------------------------------------------+
void TryAddTodayRTHopenLevel(const string &dateStr)
{
   if(!g_todayRTHopenValid) return;
   const string todayStr = dateStr;
   bool alreadyAdded = false;
   for(int levelIdx = 0; levelIdx < g_levelsTotalCount; levelIdx++)
      if(g_levels[levelIdx].tag == "todayRTHopen" && g_levels[levelIdx].startStr == todayStr && g_levels[levelIdx].endStr == todayStr)
      { alreadyAdded = true; break; }
   if(alreadyAdded) return;
   bool tooClose = false;
   for(int levelIdx = 0; levelIdx < g_levelsTotalCount; levelIdx++)
      if(g_levels[levelIdx].startStr <= todayStr && todayStr <= g_levels[levelIdx].endStr &&
         MathAbs(g_levels[levelIdx].levelPrice - g_todayRTHopen) < tertiaryLevel_tooTight_toAdd_proximity)
      { tooClose = true; break; }
   if(tooClose) return;
   if(g_levelsTotalCount >= MAX_LEVEL_ROWS)
      FatalError("todayRTHopen: RTH open bar found but g_levels full (g_levelsTotalCount=" + IntegerToString(g_levelsTotalCount) + ")");
   AddLevel(todayStr + "_todayRTHopen", g_todayRTHopen, todayStr + " 00:00", todayStr + " 23:59", "daily_tertiary_todayRTHopen");
   g_levels[g_levelsTotalCount].startStr   = todayStr;
   g_levels[g_levelsTotalCount].endStr     = todayStr;
   g_levels[g_levelsTotalCount].levelPrice = g_todayRTHopen;
   g_levels[g_levelsTotalCount].categories = "daily_tertiary_todayRTHopen";
   g_levels[g_levelsTotalCount].tag        = "todayRTHopen";
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
   while(!FileIsEnding(fileHandle) && g_levelsTotalCount < MAX_LEVEL_ROWS)
   {
      line = FileReadString(fileHandle);
      if(StringLen(line) == 0) continue;
      string parts[];
      if(StringSplit(line, ',', parts) < 5) continue;
      string startStr = parts[0];
      string endStr   = parts[1];
      if(startStr <= dateStr && dateStr <= endStr)
      {
         g_levels[g_levelsTotalCount].startStr   = startStr;
         g_levels[g_levelsTotalCount].endStr     = endStr;
         g_levels[g_levelsTotalCount].levelPrice = StringToDouble(parts[2]);
         g_levels[g_levelsTotalCount].categories = parts[3];
         g_levels[g_levelsTotalCount].tag        = parts[4];
         g_levelsTotalCount++;
      }
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
//| In contact with level (physical touch or ProximityThreshold on O/H/L/C). |
//+------------------------------------------------------------------+
bool IsBarInContactWithLevel(double o, double h, double l, double c, double level)
{
   if(l <= level && level <= h) return true;
   if(MathAbs(o - level) <= ProximityThreshold) return true;
   if(MathAbs(h - level) <= ProximityThreshold) return true;
   if(MathAbs(l - level) <= ProximityThreshold) return true;
   if(MathAbs(c - level) <= ProximityThreshold) return true;
   return false;
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
//| Reset one weekly level's algo-family pullinghistory day state.           |
//+------------------------------------------------------------------+
void ResetWeeklyLevelAlgoFamilyDayState(WeeklyLevelAlgoFamilyDayState &st, double levelPrice)
{
   st.levelPrice = levelPrice;
   st.contactCount_today = 0;
   st.bounceCount_today = 0;
   st.ceilingCount_today = 0;
   st.bounceEventCount = 0;
   st.ceilingEventCount = 0;
   st.lastInContact = false;
   st.contactFromBelow = false;
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
//| Weekly + daily levels: day stats tracked; closest anchor uses weekly only when tradesDailyLevels=false. |
//+------------------------------------------------------------------+
bool AlgoFamilyLevelShouldTrackForDayStatsLocal(const string &categories)
{
   if(LevelIsWeekly(categories))
      return true;
   string c = categories;
   StringToLower(c);
   return (StringFind(c, "daily") >= 0);
}

bool AlgoFamilyLevelEligibleForClosestAnchorLocal(const int expandedLevelIdx)
{
   if(expandedLevelIdx < 0 || expandedLevelIdx >= g_levelsTodayCount)
      return false;
   if(g_algoShared.tradesDailyLevels)
      return true;
   return LevelIsWeekly(g_levelsExpanded[expandedLevelIdx].categories);
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
//| One M1 bar: bounce/ceiling latch (same rules as pullinghistory + weekPerspective). |
//+------------------------------------------------------------------+
void AlgoFamilyApplyBounceCeilingOnBar(WeeklyLevelAlgoFamilyDayState &st,
   const double o, const double h, const double l, const double c, const datetime barTime,
   const bool recordEvents)
{
   bool in_contact = IsBarInContactWithLevel(o, h, l, c, st.levelPrice);
   if(in_contact)
   {
      if(c < st.levelPrice) st.contactFromBelow = true;
      if(c >= st.levelPrice) st.contactFromBelow = false;
   }
   bool bounceCandle = (!in_contact && l > st.levelPrice);
   if(st.lastInContact && bounceCandle)
   {
      st.bounceCount_today++;
      if(recordEvents)
         AlgoFamilyRecordBounceEvent(st, barTime);
      st.contactFromBelow = false;
   }
   bool ceilingCandle = (!in_contact && h < st.levelPrice);
   if(st.lastInContact && ceilingCandle && st.contactFromBelow)
   {
      st.ceilingCount_today++;
      if(recordEvents)
         AlgoFamilyRecordCeilingEvent(st, barTime);
      st.contactFromBelow = false;
   }
   if(!in_contact && !st.lastInContact)
      st.contactFromBelow = false;
   st.lastInContact = in_contact;
}

//+------------------------------------------------------------------+
//| Day bounce/ceiling for one level through last M1 bar closed at or before asOfTime. |
//+------------------------------------------------------------------+
void AlgoFamilyDayBounceCeilingForLevelAsOfTime(const double levelPrice, const datetime asOfTime,
   int &outBounce, int &outCeiling)
{
   outBounce = 0;
   outCeiling = 0;
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
      AlgoFamilyApplyBounceCeilingOnBar(st, o, h, l, c, g_m1Rates[barIdx].time, false);
   }
   outBounce = st.bounceCount_today;
   outCeiling = st.ceilingCount_today;
}

//+------------------------------------------------------------------+
int AlgoFamilyWeekPerspectiveBounceForLevel(const double levelPrice)
{
   for(int rowIdx = 0; rowIdx < g_algoFamilyWeekPerspectiveCount; rowIdx++)
   {
      if(MathAbs(g_algoFamilyWeekPerspective[rowIdx].levelPrice - levelPrice) < 1e-9)
         return g_algoFamilyWeekPerspective[rowIdx].bounceCount;
   }
   return 0;
}

//+------------------------------------------------------------------+
int AlgoFamilyWeekPerspectiveCeilingForLevel(const double levelPrice)
{
   for(int rowIdx = 0; rowIdx < g_algoFamilyWeekPerspectiveCount; rowIdx++)
   {
      if(MathAbs(g_algoFamilyWeekPerspective[rowIdx].levelPrice - levelPrice) < 1e-9)
         return g_algoFamilyWeekPerspective[rowIdx].ceilingCount;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Forward pass: per weekly level day stats + per-bar closest-level snapshot. |
//+------------------------------------------------------------------+
void UpdatePullingHistoryAlgoFamilyPerBarStats()
{
   g_weeklyAlgoFamilyTrackCount = 0;
   for(int levelIdx = 0; levelIdx < g_levelsTodayCount && g_weeklyAlgoFamilyTrackCount < MAX_ALGOFAMILY_WEEK_LEVELS; levelIdx++)
   {
      if(!AlgoFamilyLevelShouldTrackForDayStatsLocal(g_levelsExpanded[levelIdx].categories))
         continue;
      g_weeklyAlgoFamilyTrackExpandedIdx[g_weeklyAlgoFamilyTrackCount++] = levelIdx;
   }
   WeeklyLevelAlgoFamilyDayState states[MAX_ALGOFAMILY_WEEK_LEVELS];
   for(int trackIdx = 0; trackIdx < g_weeklyAlgoFamilyTrackCount; trackIdx++)
      ResetWeeklyLevelAlgoFamilyDayState(states[trackIdx], g_levelsExpanded[g_weeklyAlgoFamilyTrackExpandedIdx[trackIdx]].levelPrice);

   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      double o = g_m1Rates[barIdx].open, h = g_m1Rates[barIdx].high, l = g_m1Rates[barIdx].low, c = g_m1Rates[barIdx].close;
      datetime barTime = g_m1Rates[barIdx].time;
      for(int trackIdx = 0; trackIdx < g_weeklyAlgoFamilyTrackCount; trackIdx++)
      {
         double lvl = states[trackIdx].levelPrice;
         bool in_contact = IsBarInContactWithLevel(o, h, l, c, lvl);
         if(in_contact)
            states[trackIdx].contactCount_today++;
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
      }

      int closestTrackIdx = -1;
      double closestDist = 1e300;
      for(int trackIdx = 0; trackIdx < g_weeklyAlgoFamilyTrackCount; trackIdx++)
      {
         const int expandedIdx = g_weeklyAlgoFamilyTrackExpandedIdx[trackIdx];
         if(!AlgoFamilyLevelEligibleForClosestAnchorLocal(expandedIdx))
            continue;
         double d = MathAbs(c - states[trackIdx].levelPrice);
         if(d < closestDist) { closestDist = d; closestTrackIdx = trackIdx; }
      }
      g_pullingHistoryAlgoFamilyAtBar[barIdx].currentCandle_AvgOf_OHLCnumbers = (o + h + l + c) / 4.0;
      if(closestTrackIdx < 0)
      {
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevelToCClose = 0.0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestPriceProximity = 0.0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].cleanOHLC_streak_startTime = 0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].cleanOHLC_streak_count = 0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].cleanOHLC_streak_avgOfOHLC = 0.0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_anchorAbove_within_cleanOHLC_streak = 0.0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_anchorAbove_time = 0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_anchorBelow_within_cleanOHLC_streak = 0.0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_anchorBelow_time = 0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_BounceCount_today = 0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_CeilingCount_today = 0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_BounceCount_recent = 0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_CeilingCount_recent = 0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_contactCount_today = 0;
      }
      else
      {
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevelToCClose = states[closestTrackIdx].levelPrice;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestPriceProximity =
            GetBarClosestPriceProximityToLevel(h, l, states[closestTrackIdx].levelPrice);
         g_pullingHistoryAlgoFamilyAtBar[barIdx].cleanOHLC_streak_startTime = states[closestTrackIdx].cleanStreakStartTime;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].cleanOHLC_streak_count = states[closestTrackIdx].cleanStreakCount;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].cleanOHLC_streak_avgOfOHLC = (states[closestTrackIdx].cleanStreakCount > 0) ?
            states[closestTrackIdx].cleanStreakOHLCSum / (4.0 * (double)states[closestTrackIdx].cleanStreakCount) : 0.0;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_anchorAbove_within_cleanOHLC_streak = states[closestTrackIdx].anchorAbove;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_anchorAbove_time = states[closestTrackIdx].anchorAboveTime;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_anchorBelow_within_cleanOHLC_streak = states[closestTrackIdx].anchorBelow;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_anchorBelow_time = states[closestTrackIdx].anchorBelowTime;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_BounceCount_today = states[closestTrackIdx].bounceCount_today;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_CeilingCount_today = states[closestTrackIdx].ceilingCount_today;
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_BounceCount_recent =
            AlgoFamilyCountEventTimesInLookbackMinutes(states[closestTrackIdx].bounceEventTimes, states[closestTrackIdx].bounceEventCount,
               barTime, AlgoFamilyRecentBounceLookbackMinutes());
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_CeilingCount_recent =
            AlgoFamilyCountEventTimesInLookbackMinutes(states[closestTrackIdx].ceilingEventTimes, states[closestTrackIdx].ceilingEventCount,
               barTime, AlgoFamilyRecentCeilingLookbackMinutes());
         g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_contactCount_today = states[closestTrackIdx].contactCount_today;
      }
   }
}

//+------------------------------------------------------------------+
//| Per-bar account + day trade stats for algo-family log (after UpdateDayProgress; uses g_tradeResults + g_dayProgress). |
//+------------------------------------------------------------------+
void UpdatePullingHistoryAlgoFamilyAccountBarStats()
{
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      datetime candleCloseTime;
      if(barIdx + 1 < g_barsInDay)
         candleCloseTime = g_m1Rates[barIdx + 1].time;
      else
         candleCloseTime = g_m1Rates[barIdx].time + 60;

      g_pullingHistoryAlgoFamilyAtBar[barIdx].dayWinRate = g_dayProgress[barIdx].dayWinRate;
      g_pullingHistoryAlgoFamilyAtBar[barIdx].dayTradesCount = g_dayProgress[barIdx].dayTradesCount;
      g_pullingHistoryAlgoFamilyAtBar[barIdx].dayPointsSum = g_dayProgress[barIdx].dayPointsSum;
      g_pullingHistoryAlgoFamilyAtBar[barIdx].dayProfitSum = g_dayProgress[barIdx].dayProfitSum;

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
      g_pullingHistoryAlgoFamilyAtBar[barIdx].accOpenTradeNowBool = openNow;
      g_pullingHistoryAlgoFamilyAtBar[barIdx].accOpenTradeTime = openNow ? openTime : 0;
      g_pullingHistoryAlgoFamilyAtBar[barIdx].accLastClosedTradeTime = lastClosed;
   }
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
void UpdateDayM1AndLevelsExpanded()
{
   datetime dayStart = g_lastTimer1Time - (g_lastTimer1Time % 86400);
   string dateStr = TimeToString(dayStart, TIME_DATE);  // YYYY.MM.DD (MT5 default)
   string dayKey = dateStr;  // levels stored as YYYY.MM.DD

   // On new day: reload levels for this day only (by time range); close level log handles before rebuild
   if(dateStr != g_levelsLoadedForDate)
   {
      for(int i = 0; i < ArraySize(levels); i++)
         if(levels[i].logRawEv_fileHandle != INVALID_HANDLE)
            { FileClose(levels[i].logRawEv_fileHandle); levels[i].logRawEv_fileHandle = INVALID_HANDLE; }
      if(!LoadLevelsForDate(dateStr))
         return;  // file open failed; keep previous levels
      g_levelsLoadedForDate = dateStr;
      BuildLevelsFromCSV();
      RefreshAlgoFamilyWeekPerspective(g_lastTimer1Time);
      dayStat_spreadHighestSeen = 0.0;  // reset for new day
      dayStat_spreadLowestSeen = 0.0;
   }

   MqlDateTime mtDay;
   TimeToStruct(dayStart, mtDay);

   MqlRates m1Rates[];
   int barsFromDayStart = iBarShift(_Symbol, PERIOD_M1, dayStart, false);
   if(barsFromDayStart < 0) { g_barsInDay = 0; g_m1DayStart = 0; return; }

   int countToCopy = barsFromDayStart + 1;
   int copied = CopyRates(_Symbol, PERIOD_M1, 0, countToCopy, m1Rates);
   if(copied <= 0) { g_barsInDay = 0; g_m1DayStart = 0; return; }

   int barsInDay = 0;
   for(int barIdx = 0; barIdx < copied; barIdx++)
      if(TimeToString(m1Rates[barIdx].time, TIME_DATE) == dateStr) barsInDay++;

   if(barsInDay <= 0 || barsInDay > MAX_BARS_IN_DAY) { g_barsInDay = 0; g_m1DayStart = 0; return; }

   int idxDay = 0;
   for(int barIdx = 0; barIdx < copied && idxDay < barsInDay; barIdx++)
   {
      if(TimeToString(m1Rates[barIdx].time, TIME_DATE) != dateStr) continue;
      g_m1Rates[idxDay] = m1Rates[barIdx];
      idxDay++;
   }
   g_barsInDay = barsInDay;
   g_m1DayStart = dayStart;

   // No cash-style RTH open on calendar Sunday; resolving it can fatal (sparse M1 vs 14:30 desync target).
   if(IsCalendarDaySunday(dayStart))
      g_todayRTHopenValid = false;
   else
   {
      // Ensure todayRTHopen is in g_levels when we have the RTH open bar (14:30 on desync dates, else 15:30). Use globals as single source for level and pullinghistory.
      AssignTodayRTHopenFromM1Rates(dateStr);
      TryAddTodayRTHopenLevel(dateStr);
   }

   // Add PD RTH Close as a level for today only if static context was pulled for this day and no level is within proximity
   if(g_staticMarketContextPulledForDate == g_m1DayStart && g_staticMarketContext.PDCpreviousDayRTHClose > 0.0)
   {
      string todayStr = dateStr;
      double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
      bool PDrthLevel_tooClose_to_regularLevel = false;
      for(int levelIdx = 0; levelIdx < g_levelsTotalCount; levelIdx++)
      {
         if(g_levels[levelIdx].startStr > todayStr || todayStr > g_levels[levelIdx].endStr) continue;
         if(MathAbs(g_levels[levelIdx].levelPrice - pdc) < tertiaryLevel_tooTight_toAdd_proximity) { PDrthLevel_tooClose_to_regularLevel = true; break; }
      }
      if(!PDrthLevel_tooClose_to_regularLevel && g_levelsTotalCount < MAX_LEVEL_ROWS)
      {
         string categories = "daily_tertiary_PDrthClose";
         string baseName = todayStr + "_PDrthClose";
         AddLevel(baseName, pdc, todayStr + " 00:00", todayStr + " 23:59", categories);
         g_levels[g_levelsTotalCount].startStr   = todayStr;
         g_levels[g_levelsTotalCount].endStr    = todayStr;
         g_levels[g_levelsTotalCount].levelPrice = pdc;
         g_levels[g_levelsTotalCount].categories = categories;
         g_levels[g_levelsTotalCount].tag       = "PDrthClose";
         g_levelsTotalCount++;
      }
   }

   // Build levelsExpanded from g_levels (full-day bars; todayRTHopen is in g_levels like any other level)
   g_levelsTodayCount = 0;
   for(int levelIdx = 0; levelIdx < g_levelsTotalCount && g_levelsTodayCount < MAX_LEVELS_EXPANDED; levelIdx++)
   {
      if(g_levels[levelIdx].startStr > dayKey || dayKey > g_levels[levelIdx].endStr) continue;
      g_levelsExpanded[g_levelsTodayCount].levelPrice = g_levels[levelIdx].levelPrice;
      g_levelsExpanded[g_levelsTodayCount].tag        = g_levels[levelIdx].tag;
      g_levelsExpanded[g_levelsTodayCount].categories = g_levels[levelIdx].categories;
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

   // Per (level levelIdx, bar barIdx): breaksLevelDown / breaksLevelUpward from candle open/close vs level
   for(int levelIdx = 0; levelIdx < g_levelsTodayCount; levelIdx++)
      for(int barIdx = 0; barIdx < g_levelsExpanded[levelIdx].count; barIdx++)
      {
         double levelPrice = g_levelsExpanded[levelIdx].levelPrice;
         g_breaksLevelDown[levelIdx][barIdx]   = (g_m1Rates[barIdx].open > levelPrice && g_m1Rates[barIdx].close < levelPrice);
         g_breaksLevelUpward[levelIdx][barIdx] = (g_m1Rates[barIdx].open < levelPrice && g_m1Rates[barIdx].close > levelPrice);
      }

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

   // Per-bar: level above candle high, level below candle low, session (available globally; logged in 21:58-22:00)
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      double aboveH = 0;
      double belowL = 0;
      for(int levelIdx = 0; levelIdx < g_levelsTodayCount; levelIdx++)
      {
         double levelPrice = g_levelsExpanded[levelIdx].levelPrice;
         if(levelPrice > g_m1Rates[barIdx].high && (aboveH == 0 || levelPrice < aboveH)) aboveH = levelPrice;
         if(levelPrice < g_m1Rates[barIdx].low  && (belowL == 0 || levelPrice > belowL)) belowL = levelPrice;
      }
      g_levelAboveH[barIdx] = aboveH;
      g_levelBelowL[barIdx] = belowL;
      g_session[barIdx] = GetSessionForCandleTime(g_m1Rates[barIdx].time);
   }

   UpdatePullingHistoryAlgoFamilyPerBarStats();
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
//| Load deals for current day, reject DEAL_TYPE_BALANCE, group by magic, pair IN/OUT into g_tradeResults. Call from loop2. |
//+------------------------------------------------------------------+
void UpdateTradeResultsForDay()
{
   g_tradeResultsCount = 0;
   g_dealCount = 0;
   datetime dayStart = g_lastTimer1Time - (g_lastTimer1Time % 86400);
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
         tradeResult.magic       = g_dealMagic[g_inIdx[pairIdx]];
         tradeResult.priceStart  = g_dealPrice[g_inIdx[pairIdx]];
         tradeResult.type       = g_dealType[g_inIdx[pairIdx]];
         tradeResult.volume     = g_dealVolume[g_inIdx[pairIdx]];
         tradeResult.foundOut   = (pairIdx < outCount);
         tradeResult.session    = GetSessionForTradeTime(tradeResult.startTime);
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
//| For each bar k, set g_dayProgress[k] from trades with endTime < candle k close time (so close at 16:45:00 counts for 16:45 bar, not 16:44). |
//| Same totals as nested loops: closed trades sorted by endTime, one sweep as candle close advances. |
//+------------------------------------------------------------------+
void UpdateDayProgress()
{
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

   int p = 0;
   int wins = 0, total = 0;
   double dayPointsSum = 0, dayProfitSum = 0;
   int ONwins = 0, ONtotal = 0;
   double ONpointsSum = 0, ONprofitSum = 0;
   int RTHwins = 0, RTHtotal = 0;
   double RTHpointsSum = 0, RTHprofitSum = 0;

   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
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
      g_dayProgress[barIdx].ONwinRate   = (ONtotal > 0) ? (double)ONwins / (double)ONtotal : 0.0;
      g_dayProgress[barIdx].ONtradeCount = ONtotal;
      g_dayProgress[barIdx].ONpointsSum = ONpointsSum;
      g_dayProgress[barIdx].ONprofitSum = ONprofitSum;
      g_dayProgress[barIdx].RTHwinRate   = (RTHtotal > 0) ? (double)RTHwins / (double)RTHtotal : 0.0;
      g_dayProgress[barIdx].RTHtradeCount = RTHtotal;
      g_dayProgress[barIdx].RTHpointsSum = RTHpointsSum;
      g_dayProgress[barIdx].RTHprofitSum = RTHprofitSum;
   }
}

//+------------------------------------------------------------------+
//| Fill g_ONhighSoFarAtBar, g_ONlowSoFarAtBar, g_rthHighSoFarAtBar, g_rthLowSoFarAtBar, g_dayHighSoFarAtBar, g_dayLowSoFarAtBar, g_sessionRangeMidpointAtBar for bars 0..g_barsInDay-1. |
//| For each bar k: ON high/low = running max/min of ON bars up to k; RTH same; day high/low = running max/min of all bars up to k; sessionRangeMidpoint = (dayHigh+dayLow)/2. Before first ON/RTH bar, hasValue false. |
//+------------------------------------------------------------------+
void UpdateONandRTHHighLowSoFarAtBar()
{
   bool firstON = true, firstRTH = true;
   double runONhigh = 0, runONlow = 0, runRTHhigh = 0, runRTHlow = 0;
   double runDayHigh = (g_barsInDay > 0) ? g_m1Rates[0].high : 0, runDayLow = (g_barsInDay > 0) ? g_m1Rates[0].low : 0;
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      runDayHigh = MathMax(runDayHigh, g_m1Rates[barIdx].high);
      runDayLow  = MathMin(runDayLow, g_m1Rates[barIdx].low);
      g_dayHighSoFarAtBar[barIdx].hasValue = true;
      g_dayHighSoFarAtBar[barIdx].value    = runDayHigh;
      g_dayLowSoFarAtBar[barIdx].hasValue  = true;
      g_dayLowSoFarAtBar[barIdx].value     = runDayLow;
      g_sessionRangeMidpointAtBar[barIdx].hasValue = true;
      g_sessionRangeMidpointAtBar[barIdx].value    = (runDayHigh + runDayLow) / 2.0;
      double pdh = g_staticMarketContext.PDHpreviousDayHigh;
      double pdl = g_staticMarketContext.PDLpreviousDayLow;
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
}

//+------------------------------------------------------------------+
//| Fill g_IBhighAtBar, g_IBlowAtBar: IB = first hour of RTH (15:30–16:30 normal, 14:30–15:30 desync). hasValue false before last IB bar; after, value = max high / min low of IB bars. |
//+------------------------------------------------------------------+
void UpdateIBHighLowAtBar()
{
   if(g_barsInDay <= 0 || g_m1DayStart == 0) return;
   string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   datetime lastIBBarTime;
   if(bool_RTHsession_Is_DaylightSavingsDesync(dateStr))
      lastIBBarTime = g_m1DayStart + 15*3600 + 30*60;   // 15:30
   else
      lastIBBarTime = g_m1DayStart + 16*3600 + 30*60;   // 16:30

   double ibHigh = -1e300, ibLow = 1e300;
   bool ibComplete = false;

   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      if(IsBarRTHIB(g_m1Rates[barIdx].time))
      {
         ibHigh = MathMax(ibHigh, g_m1Rates[barIdx].high);
         ibLow  = MathMin(ibLow, g_m1Rates[barIdx].low);
      }
      if(g_m1Rates[barIdx].time >= lastIBBarTime)
         ibComplete = true;

      bool hasIBhigh = ibComplete && (ibHigh > -1e299);
      bool hasIBlow  = ibComplete && (ibLow < 1e299);
      g_IBhighAtBar[barIdx].hasValue = hasIBhigh;
      if(hasIBhigh) g_IBhighAtBar[barIdx].value = ibHigh;  // do not write sentinel when invalid
      g_IBlowAtBar[barIdx].hasValue  = hasIBlow;
      if(hasIBlow)  g_IBlowAtBar[barIdx].value  = ibLow;
   }
}

//+------------------------------------------------------------------+
//| Fill g_gapFillSoFarAtBar: % of gap filled so far. Gap up (RTHopen>PDC): use rthLowSoFar (fill from top). Gap down (RTHopen<PDC): use rthHighSoFar (fill from bottom). Unknown before RTH open. |
//+------------------------------------------------------------------+
void UpdateGapFillSoFarAtBar()
{
   if(g_barsInDay <= 0 || g_m1DayStart == 0) return;
   if(!g_todayRTHopenValid || g_staticMarketContext.PDCpreviousDayRTHClose <= 0.0) return;
   double rthOpen = g_todayRTHopen;
   double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
   double range_top    = MathMax(pdc, rthOpen);
   double range_bottom = MathMin(pdc, rthOpen);
   double range_size   = range_top - range_bottom;
   bool isGapUp = (rthOpen > pdc);
   if(range_size <= 0.0) return;

   string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   datetime rthOpenBarTime = g_m1DayStart + GetRthOpenBarOffsetSeconds(dateStr);

   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
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
      double rthH = g_rthHighSoFarAtBar[barIdx].value;
      double rthL = g_rthLowSoFarAtBar[barIdx].value;
      double filled = 0.0;
      if(isGapUp)
         filled = MathMax(0.0, MathMin(range_size, range_top - rthL));  // how far down from top
      else
         filled = MathMax(0.0, MathMin(range_size, rthH - range_bottom));  // how far up from bottom
      double pct = MathMin(100.0, (filled / range_size) * 100.0);
      g_gapFillSoFarAtBar[barIdx].hasValue = true;
      g_gapFillSoFarAtBar[barIdx].value    = pct;
   }
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
   double tolerance = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 1e-6);
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
//| Algo family magic: first 2 digits = algo number 10..99 (shared helpers)
//+------------------------------------------------------------------+

#define MAGIC_ALGO_FAMILY_SLOT_MIN  10
#define MAGIC_ALGO_FAMILY_SLOT_MAX  99

#define FALGO_MAGIC_LENGTH_ALGO     2

#define ALGO_SIDE_LONG   false   // buy limit above weekly level
#define ALGO_SIDE_SHORT  true    // sell limit below weekly level


#define MAGIC_ALGO10                10
#define MAGIC_ALGO11                11
#define MAGIC_ALGO12                12
#define MAGIC_ALGO13                13
#define MAGIC_ALGO14                14
#define MAGIC_ALGO15                15
#define MAGIC_ALGO16                16
// algobookmark0 above and below
// wired algo magic prefixes — add MAGIC_ALGO* define + id here + tune block in Sync
int g_algoRegistryIds[] =
{
   MAGIC_ALGO10, MAGIC_ALGO11, MAGIC_ALGO12, MAGIC_ALGO13,
   MAGIC_ALGO14, MAGIC_ALGO15, MAGIC_ALGO16
};

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
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   return g_algos[idx].enabled;
}

//+------------------------------------------------------------------+
bool AlgoProfileBlocksOnFamilyOpenOrPendingForAlgo(const int algoNumber)
{
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return true;
   return g_algos[idx].blockPlacementIfFamilyOpenOrPending;
}

//+------------------------------------------------------------------+
bool AlgoLoadTuneForAlgo(const int algoNumber, AlgoPerAlgoTune &outTune)
{
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   outTune = g_algos[idx].tune;
   return true;
}

//+------------------------------------------------------------------+
bool AlgoPlacementParamsForAlgo(const int algoNumber, double &offsetPoints, double &proximityLimit, int &expirationMin)
{
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   offsetPoints = g_algos[idx].levelOffset;
   proximityLimit = g_algos[idx].priceProximity;
   expirationMin = g_algos[idx].expiry_minutes;
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
   return (algoNumber >= MAGIC_ALGO_FAMILY_SLOT_MIN && algoNumber <= MAGIC_ALGO_FAMILY_SLOT_MAX);
}

//+------------------------------------------------------------------+
//| (date)_algo{N}_{suffix}.csv — e.g. 20260511_algo10_gates_per_minute.csv |
//+------------------------------------------------------------------+
string AlgoFamilyCsvFileName(const string dateStr, const int algoNumber, const string suffix)
{
   return dateStr + "_algo" + IntegerToString(algoNumber) + "_" + suffix + ".csv";
}


//+------------------------------------------------------------------+
//| Algo family: Falgo pipeline, rules, telemetry, EOD logs
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| smashelito_falgo.mqh — algo family (algo 10..99): Falgo* helpers, pipelines, telemetry |
//| Included from smashelito.mq5 after globals (g_tradeResults, g_m1Rates, …). |
//+------------------------------------------------------------------+


//--- Falgo magic layout (18 decimal digits; index 0 = digit 1)
#define FALGO_MAGIC_INDEX_ALGO            0   // 10..99
#define FALGO_MAGIC_INDEX_DIRECTION       2   // 1|2|3|4 long/short variants
#define FALGO_MAGIC_LENGTH_DIRECTION      1
#define FALGO_MAGIC_INDEX_DAY_OF_WEEK     3   // 1..5 Mon..Fri
#define FALGO_MAGIC_LENGTH_DAY_OF_WEEK    1
#define FALGO_MAGIC_INDEX_LEVEL_TIER      4   // 1..9 weekly tier
#define FALGO_MAGIC_LENGTH_LEVEL_TIER     1
#define FALGO_MAGIC_INDEX_BOUNCE          5   // 0..8 capped
#define FALGO_MAGIC_LENGTH_BOUNCE         1
#define FALGO_MAGIC_INDEX_CEILING         6   // 0..8 capped
#define FALGO_MAGIC_LENGTH_CEILING        1
#define FALGO_MAGIC_INDEX_OFFSET          7   // %02d tenths (long or short offset for this plan)
#define FALGO_MAGIC_LENGTH_OFFSET         2
#define FALGO_MAGIC_INDEX_PLAN_TRADE_NUM  9   // 0..8
#define FALGO_MAGIC_LENGTH_PLAN_TRADE_NUM 1
#define FALGO_MAGIC_INDEX_LEVEL_TRADE_NUM 10  // 0..8
#define FALGO_MAGIC_LENGTH_LEVEL_TRADE_NUM 1
#define FALGO_MAGIC_INDEX_BABYSIT_MIN     11  // 0..9
#define FALGO_MAGIC_LENGTH_BABYSIT_MIN    1
#define FALGO_MAGIC_INDEX_SUBSET_A        12  // reserved
#define FALGO_MAGIC_LENGTH_SUBSET_A       1
#define FALGO_MAGIC_INDEX_SUBSET_B        13  // reserved
#define FALGO_MAGIC_LENGTH_SUBSET_B       1
#define FALGO_MAGIC_INDEX_TP              14  // %02d whole points
#define FALGO_MAGIC_LENGTH_TP             2
#define FALGO_MAGIC_INDEX_SL              16  // %02d whole points
#define FALGO_MAGIC_LENGTH_SL             2

#define FALGO_DIRECTION_LONG_LIMIT        1
#define FALGO_DIRECTION_SHORT_LIMIT       2
#define FALGO_DIRECTION_LONG_ALT          3
#define FALGO_DIRECTION_SHORT_ALT         4

#define FALGO_BANNED_RANGES_MAX           8
#define FALGO_LEVEL_TIER_MAX              9

struct BannedRangeMinutes { int startMin; int endMin; };
BannedRangeMinutes g_falgoBannedRanges[FALGO_BANNED_RANGES_MAX];
int g_falgoBannedRangeCount = 0;
datetime g_falgoPlanCountersDayStart = 0;
int g_algoPlanTradeNumToday[ALGO_FAMILY_REGISTRY_MAX];  // per wired algo (10/11/12); next plan # = count+1
int g_algoLevelTradeNumByTier[ALGO_FAMILY_REGISTRY_MAX][FALGO_LEVEL_TIER_MAX + 1];
int g_algoDayWins[ALGO_FAMILY_REGISTRY_MAX];
int g_algoDayLosses[ALGO_FAMILY_REGISTRY_MAX];
int g_algoFamilyDayWins = 0;
int g_algoFamilyDayLosses = 0;

//+------------------------------------------------------------------+
bool AlgoFamilyAnyEnabled()
{
   for(int i = 0; i < g_algoCount; i++)
   {
      if(g_algos[i].enabled)
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
   return (AlgoSlotIndexByAlgoId(algoNumber) >= 0);
}

//+------------------------------------------------------------------+
bool AlgoEodTradeResultsLoggingEnabled(const int algoNumber)
{
   if(!bigflipper_log_algo_trade_results_csv)
      return false;
   return (AlgoSlotIndexByAlgoId(algoNumber) >= 0);
}

//+------------------------------------------------------------------+
bool AlgoFamilyEodTradeResultsAllDaysLoggingEnabled()
{
   return bigflipper_log_algo_trade_results_csv;
}

//+------------------------------------------------------------------+
bool AlgoProfileBlocksOnFamilyOpenOrPending(const int algoNumber)
{
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return true;
   return AlgoProfileBlocksOnFamilyOpenOrPendingForAlgo(algoNumber);
}

//+------------------------------------------------------------------+
bool AlgoLoadPerAlgoTune(const int algoNumber, AlgoPerAlgoTune &outTune)
{
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   return AlgoLoadTuneForAlgo(algoNumber, outTune);
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
bool AlgoRulesetPassesDayStops(const int algoSlot1)
{
   AlgoPerAlgoTune tune;
   if(!AlgoLoadPerAlgoTune(algoSlot1, tune))
      return true;
   const int idx = AlgoFamilySlotArrayIndex(algoSlot1);
   if(idx >= 0)
   {
      if(tune.stop_trading_today_if_thisAlgo_losing_trades_count > 0 &&
         g_algoDayLosses[idx] >= tune.stop_trading_today_if_thisAlgo_losing_trades_count)
         return false;
      if(tune.stop_trading_today_if_thisAlgo_winning_trades_count > 0 &&
         g_algoDayWins[idx] >= tune.stop_trading_today_if_thisAlgo_winning_trades_count)
         return false;
   }
   if(g_algoShared.stop_trading_today_if_AllAlgos_losing_trades_count > 0 &&
      g_algoFamilyDayLosses >= g_algoShared.stop_trading_today_if_AllAlgos_losing_trades_count)
      return false;
   if(g_algoShared.stop_trading_today_if_AllAlgos_winning_trades_count > 0 &&
      g_algoFamilyDayWins >= g_algoShared.stop_trading_today_if_AllAlgos_winning_trades_count)
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool AlgoDayStopUnderLossLimit(const int algoSlot1, bool &outUnderThisAlgo, bool &outUnderAllAlgos)
{
   outUnderThisAlgo = true;
   outUnderAllAlgos = true;
   AlgoPerAlgoTune tune;
   if(AlgoLoadPerAlgoTune(algoSlot1, tune))
   {
      const int idx = AlgoFamilySlotArrayIndex(algoSlot1);
      if(idx >= 0 && tune.stop_trading_today_if_thisAlgo_losing_trades_count > 0)
         outUnderThisAlgo = (g_algoDayLosses[idx] < tune.stop_trading_today_if_thisAlgo_losing_trades_count);
   }
   if(g_algoShared.stop_trading_today_if_AllAlgos_losing_trades_count > 0)
      outUnderAllAlgos = (g_algoFamilyDayLosses < g_algoShared.stop_trading_today_if_AllAlgos_losing_trades_count);
   return (outUnderThisAlgo && outUnderAllAlgos);
}

//+------------------------------------------------------------------+
bool AlgoDayStopUnderWinLimit(const int algoSlot1, bool &outUnderThisAlgo, bool &outUnderAllAlgos)
{
   outUnderThisAlgo = true;
   outUnderAllAlgos = true;
   AlgoPerAlgoTune tune;
   if(AlgoLoadPerAlgoTune(algoSlot1, tune))
   {
      const int idx = AlgoFamilySlotArrayIndex(algoSlot1);
      if(idx >= 0 && tune.stop_trading_today_if_thisAlgo_winning_trades_count > 0)
         outUnderThisAlgo = (g_algoDayWins[idx] < tune.stop_trading_today_if_thisAlgo_winning_trades_count);
   }
   if(g_algoShared.stop_trading_today_if_AllAlgos_winning_trades_count > 0)
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
int AlgoLevelTradeNumTodayAtTier(const int algoSlot1, const int tier)
{
   const int idx = AlgoFamilySlotArrayIndex(algoSlot1);
   if(idx < 0 || tier < 0 || tier > FALGO_LEVEL_TIER_MAX)
      return 0;
   return g_algoLevelTradeNumByTier[idx][tier];
}

datetime g_algoGatesLastLoggedBarTime[ALGO_FAMILY_REGISTRY_MAX];
datetime g_falgoGatesLogDayStart = 0;
bool g_falgoOrderPlacedLastPipeline = false;

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
   bool     badTradeMode;
   bool     terribleTradeMode;
   string   exitMode;
   string   exitModePrev;
   bool     exitModeChanged;
   string   closeDecisionReason;  // set when babysit decides to close; copied to trade-results CSV
   string   closeDecisionDetail;
};

struct FalgoTelemetryBarSnap
{
   bool     valid;
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
   int      mfeCandle1Based;
   int      maeCandle1Based;
   int      timeToReachNeutralTpSeconds;
   string   closeDecision;
   string   closeDetail;
};

FalgoOpenTradeTelemetry g_falgoOpenTelemetrySlots[FALGO_OPEN_TELEMETRY_MAX];
int g_falgoOpenTelemetryCtx = -1;
FalgoTelemetryBarSnap g_falgoTelemetryAtBar[MAX_BARS_IN_DAY];
FalgoClosedTradeTelemetrySummary g_falgoClosedTelemetry[FALGO_CLOSED_TELEMETRY_MAX];
int g_falgoClosedTelemetryCount = 0;
datetime g_falgoTelemetryLastUpdateTime = 0;
datetime g_falgoTelemetryDayStart = 0;
int g_falgoLastTradeClosedBarIdx = -1;

bool PlacePendingFromFalgoMagic(long magic, double anchorLevel, double offsetPoints, double slPoints, double tpPoints, int expirationMin, double lot);
void WriteTradeLogPendingOrderFalgo(double levelPrice, double offsetPoints, double slPoints, double tpPoints, long magic, int expirationMin);

struct FalgoMagicKey
{
   int direction;       // 1..4
   int dayOfWeek;       // 1..5 Mon..Fri
   int levelTier;       // 1..9
   int bounceCount;     // 0..8
   int ceilingCount;    // 0..8
   int offset_tenths;   // encoded 0.1..9.9 (long or short offset for this order)
   int planTradeNum;    // 0..8
   int levelTradeNum;   // 0..8
   int babysitMinute;   // 0..9
   int subsetA;         // reserved
   int subsetB;
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
   string s = StringFormat("%02d%d%d%d%d%d%02d%d%d%d%d%d%02d%02d",
      algoNumber,
      k.direction,
      k.dayOfWeek,
      k.levelTier,
      FalgoClamp0_8(k.bounceCount),
      FalgoClamp0_8(k.ceilingCount),
      k.offset_tenths,
      FalgoClamp0_8(k.planTradeNum),
      FalgoClamp0_8(k.levelTradeNum),
      FalgoClamp0_9(k.babysitMinute),
      k.subsetA,
      k.subsetB,
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
   emptyKey.levelTier = 0;
   emptyKey.bounceCount = 0;
   emptyKey.ceilingCount = 0;
   emptyKey.offset_tenths = 0;
   emptyKey.planTradeNum = 0;
   emptyKey.levelTradeNum = 0;
   emptyKey.babysitMinute = 0;
   emptyKey.subsetA = 0;
   emptyKey.subsetB = 0;
   emptyKey.tpWhole = 0;
   emptyKey.slWhole = 0;
   if(!IsAnyAlgoFamilyCompositeMagic(magic))
      return emptyKey;
   string s = MagicNumberToFixedWidthString(magic);
   FalgoMagicKey k;
   k.direction = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_DIRECTION, FALGO_MAGIC_LENGTH_DIRECTION));
   k.dayOfWeek = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_DAY_OF_WEEK, FALGO_MAGIC_LENGTH_DAY_OF_WEEK));
   k.levelTier = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_LEVEL_TIER, FALGO_MAGIC_LENGTH_LEVEL_TIER));
   k.bounceCount = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_BOUNCE, FALGO_MAGIC_LENGTH_BOUNCE));
   k.ceilingCount = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_CEILING, FALGO_MAGIC_LENGTH_CEILING));
   k.offset_tenths = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_OFFSET, FALGO_MAGIC_LENGTH_OFFSET));
   k.planTradeNum = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_PLAN_TRADE_NUM, FALGO_MAGIC_LENGTH_PLAN_TRADE_NUM));
   k.levelTradeNum = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_LEVEL_TRADE_NUM, FALGO_MAGIC_LENGTH_LEVEL_TRADE_NUM));
   k.babysitMinute = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_BABYSIT_MIN, FALGO_MAGIC_LENGTH_BABYSIT_MIN));
   k.subsetA = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_SUBSET_A, FALGO_MAGIC_LENGTH_SUBSET_A));
   k.subsetB = (int)StringToInteger(StringSubstr(s, FALGO_MAGIC_INDEX_SUBSET_B, FALGO_MAGIC_LENGTH_SUBSET_B));
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
   if(LevelIsWeekly(categories))
      return true;
   string c = categories;
   StringToLower(c);
   return (StringFind(c, "daily") >= 0);
}

//+------------------------------------------------------------------+
bool FalgoLevelEligibleForClosestAnchor(const int expandedLevelIdx)
{
   if(expandedLevelIdx < 0 || expandedLevelIdx >= g_levelsTodayCount)
      return false;
   if(g_algoShared.tradesDailyLevels)
      return true;
   return LevelIsWeekly(g_levelsExpanded[expandedLevelIdx].categories);
}

//+------------------------------------------------------------------+
void FalgoResetPlanCountersIfNewDay(const datetime dayStart)
{
   if(g_falgoPlanCountersDayStart == dayStart)
      return;
   g_falgoPlanCountersDayStart = dayStart;
   for(int ai = 0; ai < ALGO_FAMILY_REGISTRY_MAX; ai++)
   {
      g_algoPlanTradeNumToday[ai] = 0;
      for(int tier = 0; tier <= FALGO_LEVEL_TIER_MAX; tier++)
         g_algoLevelTradeNumByTier[ai][tier] = 0;
   }
}

//+------------------------------------------------------------------+
bool FalgoIsTradingDayAllowed(const datetime t)
{
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
bool FalgoProfileAllowsNewOrdersAtTime(const datetime t)
{
   if(!AlgoFamilyAnyEnabled())
      return false;
   if(!FalgoIsTradingDayAllowedAtTime(t))
      return false;
   if(!FalgoIsTradingTimeAllowed(t))
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Plan/level trade nums from today's filled Falgo deals only (not pending place/expire). |
//+------------------------------------------------------------------+
void SyncFalgoPlanCountersFromTradeResults()
{
   for(int ai = 0; ai < ALGO_FAMILY_REGISTRY_MAX; ai++)
   {
      g_algoPlanTradeNumToday[ai] = 0;
      for(int tier = 0; tier <= FALGO_LEVEL_TIER_MAX; tier++)
         g_algoLevelTradeNumByTier[ai][tier] = 0;
   }
   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      if(!IsAnyAlgoFamilyCompositeMagic(g_tradeResults[i].magic))
         continue;
      const int algoIdx = AlgoFamilySlotArrayIndex(AlgoFamilyMagicNumber(g_tradeResults[i].magic));
      if(algoIdx < 0)
         continue;
      g_algoPlanTradeNumToday[algoIdx]++;
      FalgoMagicKey fk = ParseFalgoMagic(g_tradeResults[i].magic);
      if(fk.levelTier >= 1 && fk.levelTier <= FALGO_LEVEL_TIER_MAX)
         g_algoLevelTradeNumByTier[algoIdx][fk.levelTier]++;
   }
}

//+------------------------------------------------------------------+
void UpdateFalgoDayTradeCounts()
{
   SyncFalgoPlanCountersFromTradeResults();
   for(int si = 0; si < ALGO_FAMILY_REGISTRY_MAX; si++)
   {
      g_algoDayWins[si] = 0;
      g_algoDayLosses[si] = 0;
   }
   g_algoFamilyDayWins = 0;
   g_algoFamilyDayLosses = 0;
   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      if(!g_tradeResults[i].foundOut)
         continue;
      if(!IsAnyAlgoFamilyCompositeMagic(g_tradeResults[i].magic))
         continue;
      const int algoIdx = AlgoFamilySlotArrayIndex(AlgoFamilyMagicNumber(g_tradeResults[i].magic));
      if(g_tradeResults[i].profit > 0.0)
      {
         g_algoFamilyDayWins++;
         if(algoIdx >= 0)
            g_algoDayWins[algoIdx]++;
      }
      else if(g_tradeResults[i].profit < 0.0)
      {
         g_algoFamilyDayLosses++;
         if(algoIdx >= 0)
            g_algoDayLosses[algoIdx]++;
      }
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
   return g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_BounceCount_today;
}

//+------------------------------------------------------------------+
int FalgoGetCeilingCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_CeilingCount_today;
}

//+------------------------------------------------------------------+
int FalgoGetWeekBounceCountForLevelAtBar(const int barIdx, const double levelPrice)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || levelPrice <= 0.0)
      return 0;
   const datetime asOfTime = g_m1Rates[barIdx].time + 60;
   int dBounce = 0, dCeiling = 0;
   AlgoFamilyDayBounceCeilingForLevelAsOfTime(levelPrice, asOfTime, dBounce, dCeiling);
   return AlgoFamilyWeekPerspectiveBounceForLevel(levelPrice) + dBounce;
}

//+------------------------------------------------------------------+
int FalgoGetWeekCeilingCountForLevelAtBar(const int barIdx, const double levelPrice)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || levelPrice <= 0.0)
      return 0;
   const datetime asOfTime = g_m1Rates[barIdx].time + 60;
   int dBounce = 0, dCeiling = 0;
   AlgoFamilyDayBounceCeilingForLevelAsOfTime(levelPrice, asOfTime, dBounce, dCeiling);
   return AlgoFamilyWeekPerspectiveCeilingForLevel(levelPrice) + dCeiling;
}

//+------------------------------------------------------------------+
int FalgoGetWeekBounceCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return 0;
   const double levelPrice = g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevelToCClose;
   return FalgoGetWeekBounceCountForLevelAtBar(barIdx, levelPrice);
}

//+------------------------------------------------------------------+
int FalgoGetWeekCeilingCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return 0;
   const double levelPrice = g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevelToCClose;
   return FalgoGetWeekCeilingCountForLevelAtBar(barIdx, levelPrice);
}

//+------------------------------------------------------------------+
int FalgoGetRecentBounceCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_BounceCount_recent;
}

//+------------------------------------------------------------------+
int FalgoGetRecentCeilingCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_CeilingCount_recent;
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
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].badTradeMode = false;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].terribleTradeMode = false;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitMode = FALGO_EXIT_MODE_NEUTRAL;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitModePrev = "";
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitModeChanged = false;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].closeDecisionReason = "";
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].closeDecisionDetail = "";
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
void FalgoClearTelemetryBarSnaps()
{
   for(int barIdx = 0; barIdx < MAX_BARS_IN_DAY; barIdx++)
   {
      g_falgoTelemetryAtBar[barIdx].valid = false;
      g_falgoTelemetryAtBar[barIdx].tradeClosedOnThisBar = false;
   }
}

//+------------------------------------------------------------------+
bool FalgoBarIsDedicatedToTradeClose(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return false;
   return (g_falgoTelemetryAtBar[barIdx].valid && g_falgoTelemetryAtBar[barIdx].tradeClosedOnThisBar);
}

//+------------------------------------------------------------------+
void FalgoCancelAllPendingFalgoOrdersOnSymbol()
{
   for(int orderIdx = OrdersTotal() - 1; orderIdx >= 0; orderIdx--)
   {
      if(!ExtOrderInfo.SelectByIndex(orderIdx))
         continue;
      if(ExtOrderInfo.Symbol() != _Symbol)
         continue;
      if(!IsAnyAlgoFamilyCompositeMagic(ExtOrderInfo.Magic()))
         continue;
      ExtTrade.SetExpertMagicNumber((ulong)ExtOrderInfo.Magic());
      ExtTrade.OrderDelete(ExtOrderInfo.Ticket());
      ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   }
}

//+------------------------------------------------------------------+
void FalgoOnFalgoTradeClosedThisBar()
{
   FalgoTelemetrySnapOpenStateToLastBar(true);
   g_falgoLastTradeClosedBarIdx = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].lastBarIdx;
   if(g_falgoLastTradeClosedBarIdx < 0)
      g_falgoLastTradeClosedBarIdx = FalgoBarIdxForDayTime(g_lastTimer1Time);
   FalgoCancelAllPendingFalgoOrdersOnSymbol();
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
   snap.tradeAgeSeconds = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds;
   snap.openProfitPts = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts;
   snap.secondsGreen = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsGreen;
   snap.secondsRed = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsRed;
   snap.greenRatio = FalgoTelemetryGreenRatioFromOpen();
   snap.consecutiveGreen = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveGreen;
   snap.consecutiveRed = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveRed;
   AlgoPerAlgoTune telTune;
   if(AlgoLoadPerAlgoTuneForMagic(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic, telTune))
      snap.profitVelocity = FalgoTelemetryProfitVelocityWindowSeconds(telTune.telemetry_velocity_window_seconds);
   else
      snap.profitVelocity = 0.0;
   snap.mfePts = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts;
   snap.maePts = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePts;
   snap.profitFromPeak = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].openProfitPts - g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfePts;
   snap.tradeClosedOnThisBar = tradeClosedOnThisBar;
   g_falgoTelemetryAtBar[barIdx] = snap;
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
   g_falgoLastTradeClosedBarIdx = -1;
   FalgoClearTelemetryBarSnaps();
   FalgoTelemetryClearAllOpenSlots();
}

//+------------------------------------------------------------------+
bool FalgoSelectFirstOpenFalgoPositionOnSymbol()
{
   for(int positionIdx = PositionsTotal() - 1; positionIdx >= 0; positionIdx--)
   {
      if(!ExtPositionInfo.SelectByIndex(positionIdx))
         continue;
      if(ExtPositionInfo.Symbol() != _Symbol)
         continue;
      if(!IsAnyAlgoFamilyCompositeMagic(ExtPositionInfo.Magic()))
         continue;
      return true;
   }
   return false;
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
bool FalgoIsTimeInPerSecondDebugWindow(const datetime t)
{
   if(!g_algoShared.persecond_debug_enabled)
      return false;
   MqlDateTime dt;
   TimeToStruct(t, dt);
   const int minuteOfDay = dt.hour * 60 + dt.min;
   const int startMin = g_algoShared.persecond_debug_start_hour * 60 + g_algoShared.persecond_debug_start_minute;
   const int endMin = g_algoShared.persecond_debug_end_hour * 60 + g_algoShared.persecond_debug_end_minute;
   if(startMin <= endMin)
      return (minuteOfDay >= startMin && minuteOfDay <= endMin);
   return (minuteOfDay >= startMin || minuteOfDay <= endMin);
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
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfeCandle1Based = FalgoTradeMinuteCandle1BasedFromStart(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeStartTime, g_lastTimer1Time);
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maeCandle1Based = g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].mfeCandle1Based;
   g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].lastBarIdx = FalgoBarIdxForDayTime(g_lastTimer1Time);
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
bool FalgoBadTradeLatchConditionsMet(const AlgoPerAlgoTune &tune)
{
   if(!tune.badtrade_mode_enabled)
      return false;
   if(tune.badtrade_profit_trigger >= 0.0)
      return false;
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePts > PointSized(tune.badtrade_profit_trigger))
      return false;
   if(tune.badtrade_totalRedSeconds_minTrigger > 0 &&
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsRed < tune.badtrade_totalRedSeconds_minTrigger)
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool FalgoTerribleTradeLatchConditionsMet(const AlgoPerAlgoTune &tune)
{
   if(!tune.terribletrade_mode_enabled)
      return false;
   if(tune.terribletrade_profit_trigger >= 0.0)
      return false;
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePts > PointSized(tune.terribletrade_profit_trigger))
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
   if(FalgoTerribleTradeLatchConditionsMet(tune))
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].terribleTradeMode = true;
   if(FalgoBadTradeLatchConditionsMet(tune))
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].badTradeMode = true;
}

//+------------------------------------------------------------------+
void FalgoTryLatchStrongMomentumIfNeeded(const AlgoPerAlgoTune &tune, const double profitPts)
{
   if(!tune.strong_trade_mode_enabled || g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].aimStrongTp)
      return;
   const double nearNeutral = (MathAbs(tune.neutral_trade_TP) > 0.0)
      ? PointSized(MathAbs(tune.neutral_trade_TP)) * 0.85
      : PointSized(tune.strong_trade_eval_min_profit_pts);
   if(profitPts >= nearNeutral && FalgoStrongMomentumDetectPower(profitPts, tune))
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].aimStrongTp = true;
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
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].terribleTradeMode)
      return FALGO_EXIT_MODE_TERRIBLE_TRADE;
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].badTradeMode)
      return FALGO_EXIT_MODE_BAD_TRADE;
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].aimStrongTp)
      return FALGO_EXIT_MODE_GOOD_MOMENTUM;
   return FALGO_EXIT_MODE_NEUTRAL_TRADE;
}

//+------------------------------------------------------------------+
void FalgoUpdateExitModeEachSecond(const AlgoPerAlgoTune &tune)
{
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
   if(!bigflipper_log_algo__trade_telemetry_per_second)
      return;
   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active)
      return;
   if(!FalgoIsTimeInPerSecondDebugWindow(g_lastTimer1Time))
      return;
   AlgoPerAlgoTune telTune;
   if(!AlgoLoadPerAlgoTuneForMagic(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic, telTune))
      return;
   if(!telTune.trade_telemetry_per_second_enabled)
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
      FileWrite(fh,
         "time", "openProfitPts", "MFE", "MAE", "tradeAgeSeconds",
         "secondsGreen", "secondsRed", "greenRatio", "consecutiveGreen", "consecutiveRed",
         AlgoGatesColProfitVelocity(AlgoFamilyMagicNumber(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic)),
         AlgoGatesColAvgProfitVelocity(AlgoFamilyMagicNumber(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic)),
         "profitFromPeak", "timeToReachNeutralTpSeconds",
         "exit_mode", "exit_mode_prev", "exit_mode_changed",
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
      IntegerToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].tradeAgeSeconds),
      IntegerToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsGreen),
      IntegerToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].secondsRed),
      DoubleToString(FalgoTelemetryGreenRatioFromOpen(), 4),
      IntegerToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveGreen),
      IntegerToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].consecutiveRed),
      DoubleToString(profitVelocity, 3),
      DoubleToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].avgProfitVelocity, 3),
      DoubleToString(profitFromPeak, 1),
      (g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].timeToReachNeutralTpSeconds >= 0
         ? IntegerToString(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].timeToReachNeutralTpSeconds) : ""),
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitMode,
      g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitModePrev,
      (g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].exitModeChanged ? "true" : "false"),
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
   if(!bigflipper_log_algo_velocity_parameter_testing || !velocity_parameter_testing || !g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active)
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
   if(!bigflipper_log_algo_velocity_parameter_testing || !velocity_parameter_testing || !g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].active)
      return;
   if(!FalgoIsTimeInPerSecondDebugWindow(g_lastTimer1Time))
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
void FalgoTelemetryUpdateOneSecondFromSelectedPosition()
{
   AlgoPerAlgoTune telTune;
   if(!AlgoLoadPerAlgoTuneForMagic(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].magic, telTune))
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
   FalgoTryLatchTradeRecoveryModes(telTune);
   if(g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].timeToReachNeutralTpSeconds < 0 &&
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
//| Gates CSV column names for recent bounce/ceiling windows (algo11 uses bounce recent window). |
//+------------------------------------------------------------------+
string FalgoGatesColRecentBounceCount()
{
   const int idx = AlgoSlotIndexByAlgoId(MAGIC_ALGO11);
   if(idx < 0 || g_algos[idx].recentBounceCountToday_Minutes <= 0)
      return "recentBounceCount0";
   return StringFormat("recentBounceCount%d", g_algos[idx].recentBounceCountToday_Minutes);
}

//+------------------------------------------------------------------+
string FalgoGatesColRecentCeilingCount()
{
   const int idx = AlgoSlotIndexByAlgoId(MAGIC_ALGO12);
   if(idx < 0 || g_algos[idx].recentCeilingCountToday_Minutes <= 0)
      return "recentCeilingCount0";
   return StringFormat("recentCeilingCount%d", g_algos[idx].recentCeilingCountToday_Minutes);
}

//+------------------------------------------------------------------+
//| Weekly tier 1..9 from tag (smash=5 center; up/down ladders). FatalError if unmapped. |
//+------------------------------------------------------------------+
int FalgoLevelTierFromLevelIdx(const int levelIdx)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount)
      FatalError(StringFormat("FalgoLevelTierFromLevelIdx: invalid levelIdx=%d (g_levelsTodayCount=%d)", levelIdx, g_levelsTodayCount));
   string t = g_levelsExpanded[levelIdx].tag;
   string tLower = t;
   StringToLower(tLower);
   if(StringFind(tLower, "weekly") < 0)
      FatalError(StringFormat("FalgoLevelTierFromLevelIdx: levelIdx=%d tag \"%s\" categories \"%s\" is not weekly — cannot map tier 1..9",
         levelIdx, t, g_levelsExpanded[levelIdx].categories));
   if(StringFind(tLower, "smash") >= 0)
      return 5;
   if(StringFind(tLower, "weeklydown4") >= 0 || StringFind(tLower, "weekly_down4") >= 0)
      return 1;
   if(StringFind(tLower, "weeklydown3") >= 0 || StringFind(tLower, "weekly_down3") >= 0)
      return 2;
   if(StringFind(tLower, "weeklydown2") >= 0 || StringFind(tLower, "weekly_down2") >= 0)
      return 3;
   if(StringFind(tLower, "weeklydown1") >= 0 || StringFind(tLower, "weekly_down1") >= 0)
      return 4;
   if(StringFind(tLower, "weeklydown") >= 0)
      FatalError(StringFormat("FalgoLevelTierFromLevelIdx: levelIdx=%d tag \"%s\" — weeklydown without down1..down4 tier", levelIdx, t));
   if(StringFind(tLower, "weeklyup1") >= 0 || StringFind(tLower, "weekly_up1") >= 0)
      return 6;
   if(StringFind(tLower, "weeklyup2") >= 0 || StringFind(tLower, "weekly_up2") >= 0)
      return 7;
   if(StringFind(tLower, "weeklyup3") >= 0 || StringFind(tLower, "weekly_up3") >= 0)
      return 8;
   if(StringFind(tLower, "weeklyup") >= 0)
      return 9;
   FatalError(StringFormat("FalgoLevelTierFromLevelIdx: levelIdx=%d tag \"%s\" categories \"%s\" — weekly tag not mapped to tier 1..9",
      levelIdx, t, g_levelsExpanded[levelIdx].categories));
   return 0;
}

//+------------------------------------------------------------------+
//| Today's weekly level price for magic levelTier (1..9); must match g_levelsExpanded. |
//+------------------------------------------------------------------+
double FalgoWeeklyLevelPriceForTier(const int tier)
{
   for(int levelIdx = 0; levelIdx < g_levelsTodayCount; levelIdx++)
   {
      if(!LevelIsWeekly(g_levelsExpanded[levelIdx].categories))
         continue;
      if(FalgoLevelTierFromLevelIdx(levelIdx) != tier)
         continue;
      return g_levelsExpanded[levelIdx].levelPrice;
   }
   FatalError(StringFormat("FalgoWeeklyLevelPriceForTier: no weekly level in g_levelsExpanded for tier %d (g_levelsTodayCount=%d)",
      tier, g_levelsTodayCount));
   return 0.0;
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
   if(fk.levelTier < 1 || fk.levelTier > FALGO_LEVEL_TIER_MAX)
      FatalError(StringFormat("FalgoEnrichTradeResultLevelTpSl: magic %s has invalid levelTier %d",
         IntegerToString(tr.magic), fk.levelTier));
   const double levelPrice = FalgoWeeklyLevelPriceForTier(fk.levelTier);
   double tpPts = 0.0, slPts = 0.0;
   FalgoEffectiveTpSlPointsFromMagicKey(fk, tpPts, slPts);
   tr.level = DoubleToString(levelPrice, _Digits);
   tr.tp = DoubleToString(tpPts, 1);
   tr.sl = DoubleToString(slPts, 1);
}

//+------------------------------------------------------------------+
//| After UpdateTradeResultsForDay: fill level/tp/sl for Falgo rows from magic (not order comment). |
//+------------------------------------------------------------------+
void FalgoEnrichAllTradeResultsLevelTpSl()
{
   for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
      FalgoEnrichTradeResultLevelTpSl(g_tradeResults[trIdx]);
}

//+------------------------------------------------------------------+
bool FalgoRulesetPassesCommonShared(const int barIdx)
{
   if(barIdx >= 0 && g_falgoLastTradeClosedBarIdx >= 0 && barIdx == g_falgoLastTradeClosedBarIdx)
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool AlgoRulesetPassesCommonForPlacement(const int algoSlot1, const int barIdx)
{
   if(!FalgoRulesetPassesCommonShared(barIdx))
      return false;
   if(!AlgoRulesetPassesDayStops(algoSlot1))
      return false;
   if(!CanPlaceNewOrderForAlgo_Cached(algoSlot1))
      return false;
   if(AlgoProfileBlocksOnFamilyOpenOrPending(algoSlot1))
   {
      if(FalgoHasOpenPositionOnSymbol())
         return false;
      if(FalgoHasPendingOrderOnSymbol())
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool FalgoRulesetPassesCommon(const int barIdx)
{
   if(!FalgoRulesetPassesCommonShared(barIdx))
      return false;
   if(FalgoHasOpenPositionOnSymbol())
      return false;
   if(FalgoHasPendingOrderOnSymbol())
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Per-algo ordered rule chains (g_algos[].rules). |
//+------------------------------------------------------------------+
string AlgoRulesGateFirstFail(const int algoNumber, const int barIdx)
{
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return "unknownAlgo";
   return AlgoRunRulesFirstFail(idx, barIdx);
}

//+------------------------------------------------------------------+
void AlgoRulesGateFirstFailOrRulesetDisabled(const int algoNumber, const int barIdx, string &firstFail)
{
   const string fail = AlgoRulesGateFirstFail(algoNumber, barIdx);
   firstFail = (fail != "" ? fail : "rulesetDisabled");
}

//+------------------------------------------------------------------+
bool AlgoRulesetPassesForAlgo(const int algoNumber, const int barIdx)
{
   const int idx = AlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   if(!g_algos[idx].enabled)
      return false;
   return (AlgoRunRulesFirstFail(idx, barIdx) == "");
}

//+------------------------------------------------------------------+
bool FalgoMagicKeyIsShortDirection(const FalgoMagicKey &k)
{
   return (k.direction == FALGO_DIRECTION_SHORT_LIMIT || k.direction == FALGO_DIRECTION_SHORT_ALT);
}

//+------------------------------------------------------------------+
int FalgoClosestWeeklyLevelTierAtBar(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return 0;
   const double anchor = g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevelToCClose;
   if(anchor <= 0.0)
      return 0;
   const int levelIdx = FindExpandedLevelIndexByPrice(anchor);
   if(levelIdx < 0)
      return 0;
   return FalgoLevelTierFromLevelIdx(levelIdx);
}

//+------------------------------------------------------------------+
int FalgoShortTradeCountTodayAtTierForThisAlgo(const int algoNumber, const int tier)
{
   if(tier < 1 || tier > FALGO_LEVEL_TIER_MAX)
      return 0;
   int count = 0;
   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      if(!IsAlgoCompositeMagic(g_tradeResults[i].magic, algoNumber))
         continue;
      const FalgoMagicKey fk = ParseFalgoMagic(g_tradeResults[i].magic);
      if(fk.levelTier != tier || !FalgoMagicKeyIsShortDirection(fk))
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
      if(fk.levelTier != tier || !FalgoMagicKeyIsShortDirection(fk))
         continue;
      count++;
   }
   return count;
}


//+------------------------------------------------------------------+
bool AlgoRulesetPassesForPlacement(const int algoNumber, const int barIdx)
{
   if(!AlgoRulesetPassesCommonForPlacement(algoNumber, barIdx))
      return false;
   return AlgoRulesetPassesForAlgo(algoNumber, barIdx);
}

//+------------------------------------------------------------------+
bool FalgoProfileAllowsNewOrdersNow()
{
   return FalgoProfileAllowsNewOrdersAtTime(g_lastTimer1Time);
}

//+------------------------------------------------------------------+
void AlgoEvaluateGatesAtBarForAlgo(const int algoSlot1, const int barIdx, const datetime evalTime,
   string &outCloseVsLevel, string &outDirection, int &outTier,
   bool &outProxOK, bool &outBounceOK, bool &outCeilingOK, bool &outWeeklyOK, bool &outAnchorOK,
   bool &outMagicFree, bool &outUnderLossStop, bool &outUnderWinStop,
   bool &outNoOpenPos, bool &outNoPending, bool &outRulesetCommon, bool &outRulesetDir)
{
   outCloseVsLevel = "no_level";
   outDirection = "none";
   outTier = 0;
   outProxOK = false;
   outBounceOK = false;
   outCeilingOK = false;
   outWeeklyOK = g_algoShared.tradesWeeklyLevels;
   outAnchorOK = false;
   outMagicFree = false;
   outUnderLossStop = true;
   outUnderWinStop = true;
   outNoOpenPos = !AlgoHasOpenPositionOnSymbol(algoSlot1);
   outNoPending = !AlgoHasPendingOrderOnSymbol(algoSlot1);
   outRulesetCommon = false;
   outRulesetDir = false;

   if(barIdx < 0 || barIdx >= g_barsInDay)
      return;

   const double anchor = g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevelToCClose;
   const double prox = g_pullingHistoryAlgoFamilyAtBar[barIdx].closestPriceProximity;
   const double c = g_m1Rates[barIdx].close;

   bool underThisAlgoLoss = true, underAllAlgosLoss = true;
   bool underThisAlgoWin = true, underAllAlgosWin = true;
   AlgoDayStopUnderLossLimit(algoSlot1, underThisAlgoLoss, underAllAlgosLoss);
   AlgoDayStopUnderWinLimit(algoSlot1, underThisAlgoWin, underAllAlgosWin);
   outUnderLossStop = underThisAlgoLoss && underAllAlgosLoss;
   outUnderWinStop = underThisAlgoWin && underAllAlgosWin;

   const bool tradeCloseDedicatedBar = FalgoBarIsDedicatedToTradeClose(barIdx);
   outRulesetCommon = outUnderLossStop && outUnderWinStop && !tradeCloseDedicatedBar && outNoOpenPos && outNoPending;
   if(AlgoProfileBlocksOnFamilyOpenOrPending(algoSlot1))
      outRulesetCommon = outRulesetCommon && !FalgoHasOpenPositionOnSymbol() && !FalgoHasPendingOrderOnSymbol();

   if(anchor <= 0.0)
      return;

   const bool isShortAlgo = AlgoSlotTradesShort(algoSlot1);
   double proxLimit = 0.0;
   double placementOffsetDummy = 0.0;
   int placementExpDummy = 0;
   if(!AlgoPlacementParamsForAlgo(algoSlot1, placementOffsetDummy, proxLimit, placementExpDummy))
      return;

   if(MathAbs(c - anchor) < 1e-12)
      outCloseVsLevel = "flat";
   else if(c > anchor)
      outCloseVsLevel = "above";
   else
      outCloseVsLevel = "below";

   if(isShortAlgo)
   {
      if(outCloseVsLevel != "below")
         return;
      outDirection = "short";
      outProxOK = (prox <= proxLimit);
      outBounceOK = true;
      outCeilingOK = AlgoRulesetPassesForAlgo(algoSlot1, barIdx);
      outRulesetDir = outRulesetCommon && outCeilingOK;
   }
   else
   {
      if(outCloseVsLevel != "above")
         return;
      outDirection = "long";
      outProxOK = (prox <= proxLimit);
      outBounceOK = AlgoRulesetPassesForAlgo(algoSlot1, barIdx);
      outCeilingOK = true;
      outRulesetDir = outRulesetCommon && outBounceOK;
   }

   if(!outWeeklyOK || !outProxOK)
      return;

   const int levelIdx = FindExpandedLevelIndexByPrice(anchor);
   if(levelIdx < 0)
      return;
   outAnchorOK = FalgoLevelEligibleForClosestAnchor(levelIdx);
   if(!outAnchorOK)
      return;

   outTier = FalgoLevelTierFromLevelIdx(levelIdx);

   RefreshOccupiedMagicsCache();
   outMagicFree = CanPlaceNewOrderForAlgo_Cached(algoSlot1);
}

//+------------------------------------------------------------------+
double FalgoProfileOffsetPointsForDirection(const int direction)
{
   if(direction == FALGO_DIRECTION_LONG_LIMIT)
   {
      const int idx = AlgoSlotIndexByAlgoId(MAGIC_ALGO10);
      if(idx >= 0)
         return g_algos[idx].levelOffset;
   }
   if(direction == FALGO_DIRECTION_SHORT_LIMIT)
   {
      const int idx = AlgoSlotIndexByAlgoId(MAGIC_ALGO12);
      if(idx >= 0)
         return g_algos[idx].levelOffset;
   }
   return 0.0;
}

//+------------------------------------------------------------------+
double FalgoProfileOffsetPointsForMagic(const long magic)
{
   const int algoNumber = AlgoFamilyMagicNumber(magic);
   double offsetPoints = 0.0, proximityLimit = 0.0;
   int expirationMin = 0;
   if(AlgoPlacementParamsForAlgo(algoNumber, offsetPoints, proximityLimit, expirationMin))
      return offsetPoints;
   return FalgoProfileOffsetPointsForDirection(ParseFalgoMagic(magic).direction);
}

//+------------------------------------------------------------------+
//| Falgo limit price: closestWeeklyLevel + PointSized(signed offset). Long +1.0 → +1.0 price (7405→7406). |
//+------------------------------------------------------------------+
void FalgoPendingOrderPricesForDirection(const int FalgoDirection, const double levelPrice, const double offsetPoints,
   const double slPoints, const double tpPoints,
   double &outOrderPrice, double &outStopLoss, double &outTakeProfit)
{
   const double offPx = PointSized(offsetPoints);
   const double slPx = PointSized(slPoints);
   const double tpPx = PointSized(tpPoints);
   switch(FalgoDirection)
   {
      case FALGO_DIRECTION_LONG_LIMIT:
         outOrderPrice = NormalizeDouble(levelPrice + offPx, _Digits);
         outStopLoss = NormalizeDouble(outOrderPrice - slPx, _Digits);
         outTakeProfit = NormalizeDouble(outOrderPrice + tpPx, _Digits);
         return;
      case FALGO_DIRECTION_SHORT_LIMIT:
         outOrderPrice = NormalizeDouble(levelPrice - offPx, _Digits);
         outStopLoss = NormalizeDouble(outOrderPrice + slPx, _Digits);
         outTakeProfit = NormalizeDouble(outOrderPrice - tpPx, _Digits);
         return;
      default:
         FatalError(StringFormat("FalgoPendingOrderPricesForDirection: unsupported direction %d", FalgoDirection));
   }
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
string FalgoPlannedTradePriceForGates(const int barIdx, const string &closeVsLevel, const int algoNumber)
{
   const double anchor = g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevelToCClose;
   if(anchor <= 0.0)
      return "";
   int FalgoDir = 0;
   double offsetPoints = 0.0;
   double proxDummy = 0.0;
   int expDummy = 0;
   if(closeVsLevel == "above")
   {
      if(AlgoSlotTradesShort(algoNumber))
         return "";
      FalgoDir = FALGO_DIRECTION_LONG_LIMIT;
      if(!AlgoPlacementParamsForAlgo(algoNumber, offsetPoints, proxDummy, expDummy))
         return "";
   }
   else if(closeVsLevel == "below")
   {
      if(!AlgoSlotTradesShort(algoNumber))
         return "";
      FalgoDir = FALGO_DIRECTION_SHORT_LIMIT;
      if(!AlgoPlacementParamsForAlgo(algoNumber, offsetPoints, proxDummy, expDummy))
         return "";
   }
   else
      return "";
   double orderPrice = 0.0, slDummy = 0.0, tpDummy = 0.0;
   FalgoPendingOrderPricesForDirection(FalgoDir, anchor, offsetPoints, 0.0, 0.0, orderPrice, slDummy, tpDummy);
   return DoubleToString(orderPrice, _Digits);
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
//| Raw g_levelsExpanded[].tag for trade row (from level price / magic tier). |
//+------------------------------------------------------------------+
string FalgoLevelTagUneditedForTradeResult(const TradeResult &tr)
{
   double levelPrice = StringToDouble(tr.level);
   if(levelPrice <= 0.0)
   {
      FalgoMagicKey fk = ParseFalgoMagic(tr.magic);
      if(fk.levelTier >= 1 && fk.levelTier <= FALGO_LEVEL_TIER_MAX)
      {
         const double tierPx = FalgoWeeklyLevelPriceForTier(fk.levelTier);
         if(tierPx > 0.0)
            levelPrice = tierPx;
      }
   }
   if(levelPrice <= 0.0)
      return "";
   const int levelIdx = FindExpandedLevelIndexByPrice(levelPrice);
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
//| Falgo trade still open at candle close (from g_tradeResults day snapshot). |
//+------------------------------------------------------------------+
bool FalgoFindOpenFalgoTradeAsOfCloseTime(const datetime candleCloseTime, TradeResult &outTr)
{
   bool found = false;
   datetime bestStart = 0;
   for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
   {
      TradeResult tr = g_tradeResults[trIdx];
      if(!IsAnyAlgoFamilyCompositeMagic(tr.magic))
         continue;
      if(tr.startTime >= candleCloseTime)
         continue;
      if(tr.foundOut && tr.endTime < candleCloseTime)
         continue;
      if(!found || tr.startTime > bestStart)
      {
         outTr = tr;
         bestStart = tr.startTime;
         found = true;
      }
   }
   if(!found)
      return false;
   outTr.foundOut = true;
   outTr.endTime = candleCloseTime;
   return true;
}

//+------------------------------------------------------------------+
//| Live Falgo position when g_tradeResults lag (gates log runs before UpdateTradeResultsForDay). |
//+------------------------------------------------------------------+
bool FalgoTryBuildTradeResultFromLiveOpenFalgoPosition(const datetime candleCloseTime, TradeResult &outTr)
{
   if(!FalgoSelectFirstOpenFalgoPositionOnSymbol())
      return false;
   const datetime startTime = ExtPositionInfo.Time();
   if(startTime >= candleCloseTime)
      return false;
   outTr.symbol = _Symbol;
   outTr.startTime = startTime;
   outTr.endTime = candleCloseTime;
   outTr.magic = ExtPositionInfo.Magic();
   outTr.priceStart = ExtPositionInfo.PriceOpen();
   outTr.priceEnd = 0.0;
   outTr.type = (ExtPositionInfo.PositionType() == POSITION_TYPE_BUY) ? (long)DEAL_TYPE_BUY : (long)DEAL_TYPE_SELL;
   outTr.foundOut = false;
   return true;
}

//+------------------------------------------------------------------+
bool FalgoFindFalgoTradeForGatesBar(const int barIdx, const datetime evalTime, TradeResult &outTr)
{
   if(FalgoFindOpenFalgoTradeAsOfCloseTime(evalTime, outTr))
      return true;
   if(FalgoTryBuildTradeResultFromLiveOpenFalgoPosition(evalTime, outTr))
      return true;
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return false;
   const datetime barOpen = g_m1Rates[barIdx].time;
   bool found = false;
   datetime bestStart = 0;
   for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
   {
      TradeResult tr = g_tradeResults[trIdx];
      if(!IsAnyAlgoFamilyCompositeMagic(tr.magic))
         continue;
      if(tr.startTime >= evalTime)
         continue;
      if(!tr.foundOut || tr.endTime < barOpen || tr.endTime > evalTime)
         continue;
      if(!found || tr.startTime > bestStart)
      {
         outTr = tr;
         bestStart = tr.startTime;
         found = true;
      }
   }
   if(!found)
      return false;
   outTr.endTime = evalTime;
   return true;
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Gates MFE/MAE = lifetime best/worst floating P/L (pts) from per-second telemetry. |
//+------------------------------------------------------------------+
bool FalgoGatesMfeMaeLifetimeFromBarSnaps(const datetime startTime, const int throughBarIdx,
   string &outMfePts, string &outMaePts)
{
   const int entryBarIdx = FalgoBarIdxForDayTime(startTime);
   if(entryBarIdx < 0 || throughBarIdx < entryBarIdx)
      return false;
   double peak = 0.0;
   double mae = 0.0;
   bool found = false;
   for(int b = entryBarIdx; b <= throughBarIdx && b < g_barsInDay; b++)
   {
      if(!g_falgoTelemetryAtBar[b].valid)
         continue;
      if(!found)
      {
         peak = g_falgoTelemetryAtBar[b].mfePts;
         mae = g_falgoTelemetryAtBar[b].maePts;
         found = true;
      }
      else
      {
         if(g_falgoTelemetryAtBar[b].mfePts > peak)
            peak = g_falgoTelemetryAtBar[b].mfePts;
         if(g_falgoTelemetryAtBar[b].maePts < mae)
            mae = g_falgoTelemetryAtBar[b].maePts;
      }
   }
   if(!found)
      return false;
   outMfePts = DoubleToString(peak, 1);
   outMaePts = DoubleToString(mae, 1);
   return true;
}

//+------------------------------------------------------------------+
bool FalgoGatesMfeMaeLifetimeForTrade(const TradeResult &tr, const int throughBarIdx,
   string &outMfePts, string &outMaePts)
{
   const int slotIdx = FalgoOpenTelemetryFindSlotByMagicStart(tr.magic, tr.startTime);
   if(slotIdx >= 0)
   {
      outMfePts = DoubleToString(g_falgoOpenTelemetrySlots[slotIdx].mfePts, 1);
      outMaePts = DoubleToString(g_falgoOpenTelemetrySlots[slotIdx].maePts, 1);
      return true;
   }
   FalgoClosedTradeTelemetrySummary closedSum;
   if(FalgoFindClosedTelemetrySummary(tr.magic, tr.startTime, closedSum))
   {
      outMfePts = DoubleToString(closedSum.mfePts, 1);
      outMaePts = DoubleToString(closedSum.maePts, 1);
      return true;
   }
   return FalgoGatesMfeMaeLifetimeFromBarSnaps(tr.startTime, throughBarIdx, outMfePts, outMaePts);
}

//+------------------------------------------------------------------+
//| MFE/MAE in points for one gates row (lifetime telemetry while trade was open). |
//+------------------------------------------------------------------+
void FalgoGatesMfeMaePointsForBar(const int barIdx, string &outMfePts, string &outMaePts)
{
   outMfePts = "";
   outMaePts = "";
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return;
   const datetime barOpen = g_m1Rates[barIdx].time;
   const datetime evalTime = barOpen + 60;
   TradeResult tr;
   if(!FalgoFindFalgoTradeForGatesBar(barIdx, evalTime, tr))
      return;
   FalgoGatesMfeMaeLifetimeForTrade(tr, barIdx, outMfePts, outMaePts);
}

//+------------------------------------------------------------------+
void AlgoWriteGatesLogHeaderIfNeeded(const int fh, const int algoSlot1)
{
   FileSeek(fh, 0, SEEK_END);
   if(FileTell(fh) != 0)
      return;
   if(algoSlot1 == MAGIC_ALGO15)
   {
      FileWrite(fh,
         "barTime", "O", "H", "L", "C",
         "closestWeeklyLevel", "plannedTradePrice", "firstFailGate", "MFE", "MAE",
         "tradeAgeSeconds", "openProfitPts", "secondsGreen", "secondsRed", "greenRatio",
         "consecutiveGreen", "consecutiveRed", AlgoGatesColProfitVelocity(algoSlot1), "profitFromPeak",
         "closestProximity", "level_cleanOHLC_streak", "bounceCount_today", FalgoGatesColRecentBounceCount(), "ceilingCount_today", FalgoGatesColRecentCeilingCount(),
         "closeVsLevel", "direction", "levelTier", "proximityOK", "bounceOK", "ceilingOK",
         "tradesWeeklyLevels", "anchorInExpanded",
         "plannedTradeNumber", "magicNotOccupied", "dayWins", "dayLosses",
         "underLossStopLimit", "underWinStopLimit", "noOpenFalgoPos", "noPendingFalgoOrder",
         "rulesetCommonOK", "rulesetDirectionOK",
         "tradingDayAllowed", "tradingTimeAllowed", "profileAllowsNewOrders");
      return;
   }
   FileWrite(fh,
      "barTime", "O", "H", "L", "C",
      "closestWeeklyLevel", "plannedTradePrice", "firstFailGate", "MFE", "MAE",
      "tradeAgeSeconds", "openProfitPts", "secondsGreen", "secondsRed", "greenRatio",
      "consecutiveGreen", "consecutiveRed", AlgoGatesColProfitVelocity(algoSlot1), "profitFromPeak",
      "closestProximity", "bounceCount_today", FalgoGatesColRecentBounceCount(), "ceilingCount_today", FalgoGatesColRecentCeilingCount(),
      "closeVsLevel", "direction", "levelTier", "proximityOK", "bounceOK", "ceilingOK",
      "tradesWeeklyLevels", "anchorInExpanded",
      "plannedTradeNumber", "magicNotOccupied", "dayWins", "dayLosses",
      "underLossStopLimit", "underWinStopLimit", "noOpenFalgoPos", "noPendingFalgoOrder",
      "rulesetCommonOK", "rulesetDirectionOK",
      "tradingDayAllowed", "tradingTimeAllowed", "profileAllowsNewOrders");
}

//+------------------------------------------------------------------+
void AlgoAppendGatesLogRow(const int barIdx, const int algoSlot1)
{
   if(!bigflipper_log_algo_gates_per_minute)
      return;
   if(barIdx < 0 || barIdx >= g_barsInDay || g_m1DayStart == 0)
      return;
   const datetime barTime = g_m1Rates[barIdx].time;
   const datetime evalTime = barTime + 60;

   string closeVs = "", direction = "";
   int tier = 0;
   bool proxOK = false, bounceOK = false, ceilingOK = false, weeklyOK = false, anchorOK = false;
   bool magicFree = false;
   bool underLoss = false, underWin = false, noOpen = false, noPending = false;
   bool rulesCommon = false, rulesDir = false;
   AlgoEvaluateGatesAtBarForAlgo(algoSlot1, barIdx, evalTime, closeVs, direction, tier,
      proxOK, bounceOK, ceilingOK, weeklyOK, anchorOK, magicFree,
      underLoss, underWin, noOpen, noPending, rulesCommon, rulesDir);

   const int plannedTradeNumber = AlgoPlanTradeNumToday(algoSlot1) + 1;
   const string plannedTradePrice = FalgoPlannedTradePriceForGates(barIdx, closeVs, algoSlot1);

   const bool profileEnabled = AlgoSlotEnabled(algoSlot1);
   const bool tradingDay = FalgoIsTradingDayAllowedAtTime(evalTime);
   const bool tradingTime = FalgoIsTradingTimeAllowed(evalTime);
   const bool profileAllows = FalgoProfileAllowsNewOrdersAtTime(evalTime);
   const bool tradeCloseDedicatedBar = FalgoBarIsDedicatedToTradeClose(barIdx);
   const bool familyBlock = AlgoProfileBlocksOnFamilyOpenOrPending(algoSlot1);
   const bool isShortAlgo = AlgoSlotTradesShort(algoSlot1);

   string firstFail = "";
   if(!profileEnabled) firstFail = "profileDisabled";
   else if(!tradingDay) firstFail = "tradingDayBanned";
   else if(!tradingTime) firstFail = "tradingTimeBanned";
   else if(!underLoss) firstFail = "lossStopDayLimit";
   else if(!underWin) firstFail = "winStopDayLimit";
   else if(!noOpen) firstFail = "openAlgoPosition";
   else if(tradeCloseDedicatedBar) firstFail = "tradeClosedThisBar";
   else if(!noPending) firstFail = "pendingAlgoOrder";
   else if(familyBlock && FalgoHasOpenPositionOnSymbol()) firstFail = "openFalgoPosition";
   else if(familyBlock && FalgoHasPendingOrderOnSymbol()) firstFail = "pendingFalgoOrder";
   else if(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevelToCClose <= 0.0) firstFail = "noClosestWeeklyLevel";
   else if(closeVs == "flat") firstFail = "closeFlatOnLevel";
   else if(!isShortAlgo && closeVs == "below") firstFail = "longOnly_closeBelowLevel";
   else if(isShortAlgo && closeVs == "above") firstFail = "shortOnly_closeAboveLevel";
   else if(!weeklyOK) firstFail = "tradesWeeklyLevelsOff";
   else if(!anchorOK) firstFail = "anchorNotEligible";
   else if(direction == "long")
   {
      if(!bounceOK)
         AlgoRulesGateFirstFailOrRulesetDisabled(algoSlot1, barIdx, firstFail);
   }
   else if(direction == "short")
   {
      if(!ceilingOK)
         AlgoRulesGateFirstFailOrRulesetDisabled(algoSlot1, barIdx, firstFail);
   }
   else if(!magicFree) firstFail = "algoOccupied";
   else if(!proxOK) firstFail = "proximity";
   else if(rulesDir && magicFree) firstFail = "";

   string mfePts = "", maePts = "";
   const bool telBarSnapValid = (barIdx >= 0 && barIdx < g_barsInDay && g_falgoTelemetryAtBar[barIdx].valid);
   if(!noOpen || telBarSnapValid || tradeCloseDedicatedBar)
      FalgoGatesMfeMaePointsForBar(barIdx, mfePts, maePts);

   string telTradeAge = "", telOpenProfit = "", telSecGreen = "", telSecRed = "", telGreenRatio = "";
   string telConsecGreen = "", telConsecRed = "", telProfitVelocity = "", telProfitFromPeak = "";
   if(telBarSnapValid)
   {
      string telMfeDummy = "";
      FalgoGatesTelemetryStringsFromBarSnap(g_falgoTelemetryAtBar[barIdx],
         telTradeAge, telOpenProfit, telSecGreen, telSecRed, telGreenRatio,
         telConsecGreen, telConsecRed, telProfitVelocity, telMfeDummy, telProfitFromPeak);
   }
   else if(!noOpen)
   {
      int telSlotIdx = -1;
      TradeResult gatesTr;
      if(FalgoFindFalgoTradeForGatesBar(barIdx, evalTime, gatesTr) &&
         IsAlgoCompositeMagic(gatesTr.magic, algoSlot1))
         telSlotIdx = FalgoOpenTelemetryFindSlotByMagicStart(gatesTr.magic, gatesTr.startTime);
      if(telSlotIdx < 0)
      {
         for(int si = 0; si < FALGO_OPEN_TELEMETRY_MAX; si++)
         {
            if(!g_falgoOpenTelemetrySlots[si].active)
               continue;
            if(IsAlgoCompositeMagic(g_falgoOpenTelemetrySlots[si].magic, algoSlot1))
            {
               telSlotIdx = si;
               break;
            }
         }
      }
      if(telSlotIdx >= 0)
      {
         g_falgoOpenTelemetryCtx = telSlotIdx;
         AlgoPerAlgoTune rowTelTune;
         if(AlgoLoadPerAlgoTuneForMagic(g_falgoOpenTelemetrySlots[telSlotIdx].magic, rowTelTune))
         {
            telTradeAge = IntegerToString(g_falgoOpenTelemetrySlots[telSlotIdx].tradeAgeSeconds);
            telOpenProfit = DoubleToString(g_falgoOpenTelemetrySlots[telSlotIdx].openProfitPts, 1);
            telSecGreen = IntegerToString(g_falgoOpenTelemetrySlots[telSlotIdx].secondsGreen);
            telSecRed = IntegerToString(g_falgoOpenTelemetrySlots[telSlotIdx].secondsRed);
            telGreenRatio = DoubleToString(FalgoTelemetryGreenRatioFromOpen(), 4);
            telConsecGreen = IntegerToString(g_falgoOpenTelemetrySlots[telSlotIdx].consecutiveGreen);
            telConsecRed = IntegerToString(g_falgoOpenTelemetrySlots[telSlotIdx].consecutiveRed);
            telProfitVelocity = DoubleToString(
               FalgoTelemetryProfitVelocityWindowSeconds(rowTelTune.telemetry_velocity_window_seconds), 3);
            telProfitFromPeak = DoubleToString(g_falgoOpenTelemetrySlots[telSlotIdx].openProfitPts - g_falgoOpenTelemetrySlots[telSlotIdx].mfePts, 1);
         }
      }
   }

   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   const string fname = AlgoFamilyCsvFileName(dateStr, algoSlot1, "gates_per_minute");
   int fh = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   AlgoWriteGatesLogHeaderIfNeeded(fh, algoSlot1);
   FileSeek(fh, 0, SEEK_END);
   if(algoSlot1 == MAGIC_ALGO15)
   {
      FileWrite(fh,
         TimeToString(barTime, TIME_DATE|TIME_MINUTES),
         DoubleToString(g_m1Rates[barIdx].open, _Digits),
         DoubleToString(g_m1Rates[barIdx].high, _Digits),
         DoubleToString(g_m1Rates[barIdx].low, _Digits),
         DoubleToString(g_m1Rates[barIdx].close, _Digits),
         DoubleToString(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevelToCClose, _Digits),
         plannedTradePrice,
         firstFail,
         mfePts,
         maePts,
         telTradeAge,
         telOpenProfit,
         telSecGreen,
         telSecRed,
         telGreenRatio,
         telConsecGreen,
         telConsecRed,
         telProfitVelocity,
         telProfitFromPeak,
         DoubleToString(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestPriceProximity, _Digits),
         IntegerToString(g_pullingHistoryAlgoFamilyAtBar[barIdx].cleanOHLC_streak_count),
         IntegerToString(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_BounceCount_today),
         IntegerToString(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_BounceCount_recent),
         IntegerToString(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_CeilingCount_today),
         IntegerToString(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_CeilingCount_recent),
         closeVs, direction, IntegerToString(tier),
         FalgoBoolCsv(proxOK), FalgoBoolCsv(bounceOK), FalgoBoolCsv(ceilingOK),
         FalgoBoolCsv(weeklyOK), FalgoBoolCsv(anchorOK),
         IntegerToString(plannedTradeNumber),
         FalgoBoolCsv(magicFree),
         IntegerToString(AlgoDayWinsForSlot(algoSlot1)), IntegerToString(AlgoDayLossesForSlot(algoSlot1)),
         FalgoBoolCsv(underLoss), FalgoBoolCsv(underWin),
         FalgoBoolCsv(noOpen), FalgoBoolCsv(noPending),
         FalgoBoolCsv(rulesCommon), FalgoBoolCsv(rulesDir),
         FalgoBoolCsv(tradingDay), FalgoBoolCsv(tradingTime),
         FalgoBoolCsv(profileAllows));
   }
   else
   {
      FileWrite(fh,
         TimeToString(barTime, TIME_DATE|TIME_MINUTES),
         DoubleToString(g_m1Rates[barIdx].open, _Digits),
         DoubleToString(g_m1Rates[barIdx].high, _Digits),
         DoubleToString(g_m1Rates[barIdx].low, _Digits),
         DoubleToString(g_m1Rates[barIdx].close, _Digits),
         DoubleToString(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevelToCClose, _Digits),
         plannedTradePrice,
         firstFail,
         mfePts,
         maePts,
         telTradeAge,
         telOpenProfit,
         telSecGreen,
         telSecRed,
         telGreenRatio,
         telConsecGreen,
         telConsecRed,
         telProfitVelocity,
         telProfitFromPeak,
         DoubleToString(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestPriceProximity, _Digits),
         IntegerToString(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_BounceCount_today),
         IntegerToString(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_BounceCount_recent),
         IntegerToString(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_CeilingCount_today),
         IntegerToString(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_CeilingCount_recent),
         closeVs, direction, IntegerToString(tier),
         FalgoBoolCsv(proxOK), FalgoBoolCsv(bounceOK), FalgoBoolCsv(ceilingOK),
         FalgoBoolCsv(weeklyOK), FalgoBoolCsv(anchorOK),
         IntegerToString(plannedTradeNumber),
         FalgoBoolCsv(magicFree),
         IntegerToString(AlgoDayWinsForSlot(algoSlot1)), IntegerToString(AlgoDayLossesForSlot(algoSlot1)),
         FalgoBoolCsv(underLoss), FalgoBoolCsv(underWin),
         FalgoBoolCsv(noOpen), FalgoBoolCsv(noPending),
         FalgoBoolCsv(rulesCommon), FalgoBoolCsv(rulesDir),
         FalgoBoolCsv(tradingDay), FalgoBoolCsv(tradingTime),
         FalgoBoolCsv(profileAllows));
   }
   FileClose(fh);
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
      for(int gi = 0; gi < ALGO_FAMILY_REGISTRY_MAX; gi++)
         g_algoGatesLastLoggedBarTime[gi] = 0;
   }
   int barIdx = g_barsInDay - 2;
   if(g_barsInDay < 2)
      return;
   const datetime barTime = g_m1Rates[barIdx].time;
   for(int si = 0; si < g_algoCount; si++)
   {
      const int algoNumber = g_algos[si].algo_id;
      if(barTime == g_algoGatesLastLoggedBarTime[si])
         continue;
      g_algoGatesLastLoggedBarTime[si] = barTime;
      AlgoAppendGatesLogRow(barIdx, algoNumber);
   }
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
void FalgoStrongMomentumStallFlags(const AlgoPerAlgoTune &tune,
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
bool FalgoStrongMomentumDetectStall(const AlgoPerAlgoTune &tune)
{
   bool velocityStall = false;
   bool givebackStall = false;
   FalgoStrongMomentumStallFlags(tune, velocityStall, givebackStall);
   return velocityStall || givebackStall;
}

//+------------------------------------------------------------------+
string FalgoStrongMomentumStallReasonDetail(const AlgoPerAlgoTune &tune)
{
   bool velocityStall = false;
   bool givebackStall = false;
   FalgoStrongMomentumStallFlags(tune, velocityStall, givebackStall);
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
   if(!tune.strong_trade_mode_enabled || !FalgoBabysitPositionMatchesOpenTelemetry())
      return false;

   const double profitPts = FalgoOpenPositionProfitPoints();
   const double stallMinClosePts = PointSized(tune.strong_trade_stall_min_close_profit_pts);

   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].aimStrongTp)
   {
      FalgoTryLatchStrongMomentumIfNeeded(tune, profitPts);
   }

   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].aimStrongTp)
      return false;

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
   ExtTrade.SetExpertMagicNumber((ulong)positionMagic);
   const bool closed = ExtTrade.PositionClose(ExtPositionInfo.Ticket());
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
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
   ExtTrade.SetExpertMagicNumber((ulong)positionMagic);
   const bool closed = ExtTrade.PositionClose(ExtPositionInfo.Ticket());
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
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
   if(!tune.terribletrade_mode_enabled)
      return false;
   if(!FalgoBabysitPositionMatchesOpenTelemetry())
      return false;

   FalgoTryLatchTradeRecoveryModes(tune);
   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].terribleTradeMode)
      return false;

   const double targetPts = PointSized(tune.terribletrade_try_smaller_loss_TP);
   return Babysitf_falgo_closeIfProfitTargetTune(posMagic, tune.terribletrade_try_smaller_loss_TP,
      "terribletrade_try_smaller_loss_TP",
      StringFormat("profit=%.1f|target=%.1f|MAE=%.1f", FalgoOpenPositionProfitPoints(), targetPts,
         g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePts));
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
   if(!tune.badtrade_mode_enabled)
      return false;
   if(!FalgoBabysitPositionMatchesOpenTelemetry())
      return false;

   FalgoTryLatchTradeRecoveryModes(tune);
   if(!g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].badTradeMode || g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].terribleTradeMode)
      return false;

   const double targetPts = PointSized(tune.badtrade_try_save_TP);
   return Babysitf_falgo_closeIfProfitTargetTune(posMagic, tune.badtrade_try_save_TP, "badtrade_try_save_TP",
      StringFormat("profit=%.1f|target=%.1f|MAE=%.1f", FalgoOpenPositionProfitPoints(), targetPts,
         g_falgoOpenTelemetrySlots[g_falgoOpenTelemetryCtx].maePts));
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
   ExtTrade.SetExpertMagicNumber((ulong)positionMagic);
   const bool closed = ExtTrade.PositionClose(ExtPositionInfo.Ticket());
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   return closed;
}

//+------------------------------------------------------------------+
void Babysitf_RunAllOpenFalgoPositionsForSymbol()
{
   for(int positionIdx = PositionsTotal() - 1; positionIdx >= 0; positionIdx--)
   {
      if(!ExtPositionInfo.SelectByIndex(positionIdx))
         continue;
      if(ExtPositionInfo.Symbol() != _Symbol)
         continue;
      const long posMagic = ExtPositionInfo.Magic();
      if(!IsAnyAlgoFamilyCompositeMagic(posMagic))
         continue;
      if(!g_algoShared.babysit_enabled)
         continue;
      AlgoPerAlgoTune posTune;
      if(!AlgoLoadPerAlgoTuneForMagic(posMagic, posTune))
         continue;
      FalgoMagicKey fk = ParseFalgoMagic(posMagic);
      const int babysitStartMin = fk.babysitMinute;
      const int minutesOpen = (int)((g_lastTimer1Time - ExtPositionInfo.Time()) / 60);
      if(minutesOpen < babysitStartMin)
         continue;
      if(Babysitf_falgo_runTerribleTradeBabysit(posMagic))
         continue;
      if(Babysitf_falgo_runBadTradeBabysit(posMagic))
         continue;
      bool skipNeutralTp = false;
      if(Babysitf_falgo_runStrongMomentumBabysit(posMagic, skipNeutralTp))
         continue;
      if(!skipNeutralTp)
      {
         if(Babysitf_falgo_closeIfProfitTargetTune(posMagic, posTune.neutral_trade_TP, "neutral_trade_TP"))
            continue;
      }
      if(g_algoShared.secretTPSL && g_algoShared.secretTPSL_percent > 0)
      {
         const double secretFrac = (double)g_algoShared.secretTPSL_percent / 100.0;
         if(fk.tpWhole > 0)
         {
            const double secretTpPts = PointSized((double)fk.tpWhole) * secretFrac;
            if(Babysitf_falgo_closeIfProfitPointsAtLeast(posMagic, secretTpPts, "secretTPSL_tp",
               StringFormat("profit=%.1f|threshold=%.1f|tpWhole=%d|pct=%d", FalgoOpenPositionProfitPoints(),
                  secretTpPts, fk.tpWhole, g_algoShared.secretTPSL_percent)))
               continue;
         }
         if(fk.slWhole > 0)
         {
            const double secretSlPts = PointSized((double)fk.slWhole) * secretFrac;
            if(Babysitf_falgo_closeIfLossPointsAtLeast(posMagic, secretSlPts, "secretTPSL_sl",
               StringFormat("profit=%.1f|lossThreshold=-%.1f|slWhole=%d|pct=%d", FalgoOpenPositionProfitPoints(),
                  secretSlPts, fk.slWhole, g_algoShared.secretTPSL_percent)))
               continue;
         }
      }
   }
}

//+------------------------------------------------------------------+
bool FalgoBuildMagicKeyForPlacement(const int algoSlot1, const int barIdx, const int direction, const double anchorLevel,
   const int levelExpandedIdx, const double offsetPoints, FalgoMagicKey &outKey)
{
   if(direction != FALGO_DIRECTION_LONG_LIMIT && direction != FALGO_DIRECTION_SHORT_LIMIT)
      FatalError(StringFormat("FalgoBuildMagicKeyForPlacement: unsupported direction %d", direction));
   const int tier = FalgoLevelTierFromLevelIdx(levelExpandedIdx);
   if(tier < 1 || tier > FALGO_LEVEL_TIER_MAX)
      FatalError(StringFormat("FalgoBuildMagicKeyForPlacement: tier %d out of range", tier));
   const int nextLevelTradeNum = AlgoLevelTradeNumTodayAtTier(algoSlot1, tier) + 1;

   outKey.direction = direction;
   outKey.dayOfWeek = FalgoDayOfWeekSlotFromTime(g_lastTimer1Time);
   outKey.levelTier = tier;
   outKey.bounceCount = FalgoClamp0_8(FalgoGetBounceCountForClosestWeeklyLevel(barIdx));
   outKey.ceilingCount = FalgoClamp0_8(FalgoGetCeilingCountForClosestWeeklyLevel(barIdx));
   outKey.offset_tenths = EncodeMagicTwoDigitTenths(MathAbs(offsetPoints));
   outKey.planTradeNum = FalgoClamp0_8(AlgoPlanTradeNumToday(algoSlot1) + 1);
   outKey.levelTradeNum = FalgoClamp0_8(nextLevelTradeNum);
   AlgoPerAlgoTune placeTune;
   if(!AlgoLoadPerAlgoTune(algoSlot1, placeTune))
      FatalError(StringFormat("FalgoBuildMagicKeyForPlacement: unknown algo slot %d", algoSlot1));
   outKey.babysitMinute = FalgoClamp0_9(placeTune.babysitStart_minute);
   outKey.subsetA = 0;
   outKey.subsetB = 0;
   outKey.tpWhole = FalgoCapWholeTpSlForMagic(g_algoShared.initialTP);
   outKey.slWhole = FalgoCapWholeTpSlForMagic(g_algoShared.initialSL);
   return true;
}

//+------------------------------------------------------------------+
bool AlgoTryPlaceOrderThisTick(const int algoNumber, const int barIdx)
{
   if(AlgoSlotIndexByAlgoId(algoNumber) < 0)
      return false;
   if(!AlgoProfileEnabled(algoNumber))
      return false;

   const double anchorLevel = g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevelToCClose;
   if(anchorLevel <= 0.0)
      return false;
   const double prox = g_pullingHistoryAlgoFamilyAtBar[barIdx].closestPriceProximity;
   const double c = g_m1Rates[barIdx].close;
   if(MathAbs(c - anchorLevel) < 1e-12)
      return false;

   int direction = 0;
   double offsetPoints = 0.0;
   double proximityLimit = 0.0;
   int expirationMin = 0;
   if(c > anchorLevel)
   {
      if(AlgoSlotTradesShort(algoNumber))
         return false;
      direction = FALGO_DIRECTION_LONG_LIMIT;
      if(!AlgoPlacementParamsForAlgo(algoNumber, offsetPoints, proximityLimit, expirationMin))
         return false;
      if(!AlgoRulesetPassesForPlacement(algoNumber, barIdx))
         return false;
   }
   else if(c < anchorLevel)
   {
      if(!AlgoSlotTradesShort(algoNumber))
         return false;
      direction = FALGO_DIRECTION_SHORT_LIMIT;
      if(!AlgoPlacementParamsForAlgo(algoNumber, offsetPoints, proximityLimit, expirationMin))
         return false;
      if(prox > proximityLimit)
         return false;
      if(!AlgoRulesetPassesForPlacement(algoNumber, barIdx))
         return false;
   }
   else
      return false;

   if(prox > proximityLimit)
      return false;

   if(!g_algoShared.tradesWeeklyLevels)
      return false;

   const int levelExpandedIdx = FindExpandedLevelIndexByPrice(anchorLevel);
   if(levelExpandedIdx < 0)
      FatalError(StringFormat("AlgoTryPlaceOrderThisTick algo%d: anchor level %s not in g_levelsExpanded today",
         algoNumber, DoubleToString(anchorLevel, _Digits)));
   if(!FalgoLevelEligibleForClosestAnchor(levelExpandedIdx))
      return false;

   FalgoMagicKey planKey;
   if(!FalgoBuildMagicKeyForPlacement(algoNumber, barIdx, direction, anchorLevel, levelExpandedIdx, offsetPoints, planKey))
      return false;

   const long magic = BuildAlgoMagicNumber(algoNumber, planKey);
   if(!CanPlaceNewOrderForAlgo_Cached(algoNumber))
      return false;

   const double lot = GetTradeLotForFalgo();
   if(!PlacePendingFromFalgoMagic(magic, anchorLevel, offsetPoints, g_algoShared.initialTP, g_algoShared.initialSL, expirationMin, lot))
      return false;

   g_falgoOrderPlacedLastPipeline = true;
   WriteTradeLogPendingOrderFalgo(anchorLevel, offsetPoints, g_algoShared.initialTP, g_algoShared.initialSL, magic, expirationMin);
   return true;
}

//+------------------------------------------------------------------+
//| Iterate enabled algos in registry order — one placement attempt per tick max. |
//+------------------------------------------------------------------+
void RunFalgoTradePipeline()
{
   g_falgoOrderPlacedLastPipeline = false;
   UpdateFalgoDayTradeCounts();
   Babysitf_RunAllOpenFalgoPositionsForSymbol();

   if(!FalgoProfileAllowsNewOrdersNow())
      return;
   if(g_barsInDay < 1)
      return;

   if(g_m1DayStart != 0)
      FalgoResetPlanCountersIfNewDay(g_m1DayStart);

   const int barIdx = g_barsInDay - 1;
   if(!FalgoRulesetPassesCommonShared(barIdx))
      return;

   RefreshOccupiedMagicsCache();
   for(int si = 0; si < g_algoCount; si++)
   {
      if(!g_algos[si].enabled)
         continue;
      AlgoTryPlaceOrderThisTick(g_algos[si].algo_id, barIdx);
      if(g_falgoOrderPlacedLastPipeline)
         break;
   }
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
double FalgoLevelPriceForTradeResult(const TradeResult &tr)
{
   double levelPrice = StringToDouble(tr.level);
   if(levelPrice <= 0.0)
   {
      FalgoMagicKey fk = ParseFalgoMagic(tr.magic);
      if(fk.levelTier >= 1 && fk.levelTier <= FALGO_LEVEL_TIER_MAX)
      {
         const double tierPx = FalgoWeeklyLevelPriceForTier(fk.levelTier);
         if(tierPx > 0.0)
            levelPrice = tierPx;
      }
   }
   return levelPrice;
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

   const double levelPrice = FalgoLevelPriceForTradeResult(tr);
   if(levelPrice > 0.0)
   {
      GetReferencePointsAboveBelow(tr.startTime, levelPrice, out.refAbove, out.refBelow);
      string levelTagDummy = "";
      const string levelStr = (StringLen(tr.level) > 0) ? tr.level : DoubleToString(levelPrice, _Digits);
      GetLevelTagAndCatsForTrade(levelStr, levelTagDummy, out.levelCats);
   }
}

//+------------------------------------------------------------------+
//| w/d bounce & ceiling at trade open: weekPerspective prior days + today through last closed M1 before startTime. |
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
   outWBounce = AlgoFamilyWeekPerspectiveBounceForLevel(levelPrice) + outDBounce;
   outWCeiling = AlgoFamilyWeekPerspectiveCeilingForLevel(levelPrice) + outDCeiling;
}

//+------------------------------------------------------------------+
#define FALGO_ALLDAYS_HEADER "date,symbol,startTime,endTime,session,magic,priceStart,priceEnd,priceDiff,profit,type,MFE,MAE,mfeCandle,maeCandle,close_decision,close_detail,reason,volume,bothComments,level,levelTag,planTradeNumToday,levelTradeNumToday,offset,tp,sl,greenRatio_at_close,avg_profitVelocity_5,secondsGreen,secondsRed,time_to_reach_neutral_TP,3c_30c_level_breakevenC,gapFillPc_at_tradeOpenTime,openGap_info,PD_trend,dayBrokePDH,dayBrokePDL,referencePointsAbove,referencePointsBelow,levelCats,wCeilingC,dCeilingC,wBounceC,dBounceC"
#define FALGO_ALLDAYS_COLS     45

//+------------------------------------------------------------------+
void FalgoFileWriteAllDaysHeader(const int fh)
{
   FileWriteString(fh, FALGO_ALLDAYS_HEADER + "\r\n");
}

//+------------------------------------------------------------------+
void FalgoFileWriteAllDaysRowFromCells(const int fh, const string &cells[], const int base)
{
   string row = FalgoSanitizeCsvCell(cells[base + 0]);
   for(int c = 1; c < FALGO_ALLDAYS_COLS; c++)
      row += "," + FalgoSanitizeCsvCell(cells[base + c]);
   FileWriteString(fh, row + "\r\n");
}

//+------------------------------------------------------------------+
//| Read all-days trade-results file: one line = one row; exact FALGO_ALLDAYS_COLS only. |
//+------------------------------------------------------------------+
void FalgoReadAllDaysTradeResultsFromFile(const string fileName, string &outCells[], int &outRowCount)
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
      if(StringSplit(line, ',', parts) != FALGO_ALLDAYS_COLS)
         continue;
      const int base = ArraySize(outCells);
      ArrayResize(outCells, base + FALGO_ALLDAYS_COLS);
      for(int c = 0; c < FALGO_ALLDAYS_COLS; c++)
         outCells[base + c] = parts[c];
      outRowCount++;
   }
   FileClose(fh);
}

//+------------------------------------------------------------------+
void FalgoWriteAllDaysTradeResultsToFile(const string fileName, const string &cells[], const int rowCount)
{
   int fh = FileOpen(fileName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   FalgoFileWriteAllDaysHeader(fh);
   for(int ri = 0; ri < rowCount; ri++)
      FalgoFileWriteAllDaysRowFromCells(fh, cells, ri * FALGO_ALLDAYS_COLS);
   FileClose(fh);
}

//+------------------------------------------------------------------+
void FalgoAppendTradeResultCells(string &cells[], const string dateStr, const TradeResult &tr)
{
   const int base = ArraySize(cells);
   ArrayResize(cells, base + FALGO_ALLDAYS_COLS);
   cells[base + 0]  = dateStr;
   cells[base + 1]  = tr.symbol;
   cells[base + 2]  = TimeToString(tr.startTime, TIME_DATE|TIME_SECONDS);
   cells[base + 3]  = TimeToString(tr.endTime, TIME_DATE|TIME_SECONDS);
   cells[base + 4]  = FalgoSanitizeCsvCell(tr.session);
   cells[base + 5]  = IntegerToString((long)tr.magic);
   cells[base + 6]  = DoubleToString(tr.priceStart, _Digits);
   cells[base + 7]  = DoubleToString(tr.priceEnd, _Digits);
   cells[base + 8]  = DoubleToString(tr.priceDiff, _Digits);
   cells[base + 9]  = DoubleToString(tr.profit, 2);
   cells[base + 10] = FalgoSanitizeCsvCell(EnumToString((ENUM_DEAL_TYPE)tr.type));
   FalgoClosedTradeTelemetrySummary telSummary;
   const bool hasTel = FalgoGetTelemetrySummaryForTrade(tr.magic, tr.startTime, telSummary);
   FalgoTradeLegacyContextCols legacyCtx;
   FalgoFillTradeLegacyContextCols(tr, legacyCtx);
   if(hasTel)
   {
      cells[base + 11] = DoubleToString(telSummary.mfePts, 1);
      cells[base + 12] = DoubleToString(telSummary.maePts, 1);
      cells[base + 15] = FalgoSanitizeCsvCell(telSummary.closeDecision);
      cells[base + 16] = FalgoSanitizeCsvCell(telSummary.closeDetail);
      cells[base + 27] = DoubleToString(telSummary.greenRatioAtClose, 4);
      cells[base + 28] = DoubleToString(telSummary.avgProfitVelocity, 3);
      cells[base + 29] = IntegerToString(telSummary.secondsGreen);
      cells[base + 30] = IntegerToString(telSummary.secondsRed);
      cells[base + 31] = (telSummary.timeToReachNeutralTpSeconds >= 0
         ? IntegerToString(telSummary.timeToReachNeutralTpSeconds) : "");
   }
   else
   {
      cells[base + 11] = "";
      cells[base + 12] = "";
      cells[base + 15] = "";
      cells[base + 16] = "";
      cells[base + 27] = "";
      cells[base + 28] = "";
      cells[base + 29] = "";
      cells[base + 30] = "";
      cells[base + 31] = "";
   }
   cells[base + 13] = FalgoSanitizeCsvCell(legacyCtx.mfeCandle);
   cells[base + 14] = FalgoSanitizeCsvCell(legacyCtx.maeCandle);
   cells[base + 17] = FalgoSanitizeCsvCell(EnumToString((ENUM_DEAL_REASON)tr.reason));
   cells[base + 18] = (string)tr.volume;
   cells[base + 19] = FalgoSanitizeCsvCell(tr.bothComments);
   int planNum = 0, levelNum = 0;
   FalgoPlanAndLevelTradeNumsFromMagic(tr.magic, planNum, levelNum);
   cells[base + 20] = FalgoSanitizeCsvCell(tr.level);
   cells[base + 21] = FalgoSanitizeCsvCell(FalgoLevelTagUneditedForTradeResult(tr));
   cells[base + 22] = IntegerToString(planNum);
   cells[base + 23] = IntegerToString(levelNum);
   cells[base + 24] = FalgoOffsetPriceUnitsStrForTrade(tr);
   cells[base + 25] = FalgoSanitizeCsvCell(tr.tp);
   cells[base + 26] = FalgoSanitizeCsvCell(tr.sl);
   cells[base + 32] = FalgoSanitizeCsvCell(legacyCtx.breakevenC);
   cells[base + 33] = FalgoSanitizeCsvCell(legacyCtx.gapFillPc);
   cells[base + 34] = FalgoSanitizeCsvCell(legacyCtx.openGapInfo);
   cells[base + 35] = FalgoSanitizeCsvCell(legacyCtx.pdTrend);
   cells[base + 36] = FalgoSanitizeCsvCell(legacyCtx.dayBrokePDH);
   cells[base + 37] = FalgoSanitizeCsvCell(legacyCtx.dayBrokePDL);
   cells[base + 38] = FalgoSanitizeCsvCell(legacyCtx.refAbove);
   cells[base + 39] = FalgoSanitizeCsvCell(legacyCtx.refBelow);
   cells[base + 40] = FalgoSanitizeCsvCell(legacyCtx.levelCats);
   int wBounceC = 0, dBounceC = 0, wCeilingC = 0, dCeilingC = 0;
   FalgoFillTradeBounceCeilingCountsAtStart(tr, wBounceC, dBounceC, wCeilingC, dCeilingC);
   cells[base + 41] = IntegerToString(wCeilingC);
   cells[base + 42] = IntegerToString(dCeilingC);
   cells[base + 43] = IntegerToString(wBounceC);
   cells[base + 44] = IntegerToString(dBounceC);
}

//+------------------------------------------------------------------+
bool FalgoAllDaysRowsContainTrade(const string &cells[], const int rowCount, const long magic, const datetime startTime)
{
   const string magicStr = IntegerToString(magic);
   const string startStr = TimeToString(startTime, TIME_DATE|TIME_SECONDS);
   for(int ri = 0; ri < rowCount; ri++)
   {
      const int base = ri * FALGO_ALLDAYS_COLS;
      if(cells[base + 5] == magicStr && cells[base + 2] == startStr)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Reorder all-days flat cell rows by startTime column ascending (family summary only). |
//+------------------------------------------------------------------+
void FalgoSortAllDaysCellRowsByStartTimeAsc(string &cells[], const int rowCount)
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
            const datetime tP = StringToTime(cells[indices[p] * FALGO_ALLDAYS_COLS + 2]);
            const datetime tQ = StringToTime(cells[indices[q] * FALGO_ALLDAYS_COLS + 2]);
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
   ArrayResize(sorted, rowCount * FALGO_ALLDAYS_COLS);
   for(int ri = 0; ri < rowCount; ri++)
   {
      const int srcBase = indices[ri] * FALGO_ALLDAYS_COLS;
      const int dstBase = ri * FALGO_ALLDAYS_COLS;
      for(int c = 0; c < FALGO_ALLDAYS_COLS; c++)
         sorted[dstBase + c] = cells[srcBase + c];
   }
   ArrayCopy(cells, sorted);
}

//+------------------------------------------------------------------+
//| EOD: per-day algoN CSV (rewrite) + all-days TSV (read/merge/append today's rows for that algo only). |
//+------------------------------------------------------------------+
void WriteAlgoEodTradeResultsCsvsIfNeeded(const string dateStr, const int algoSlot1, const int algoOutCount)
{
   if(!AlgoEodTradeResultsLoggingEnabled(algoSlot1) || algoOutCount <= 0)
      return;

   const string csvName = dateStr + "_summaryZ_tradeResults_ALL_Day_algo" + IntegerToString(algoSlot1) + ".csv";
   int fhDay = FileOpen(csvName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_CSV | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fhDay != INVALID_HANDLE)
   {
      FileWrite(fhDay, "symbol", "startTime", "endTime", "session", "magic", "priceStart", "priceEnd", "priceDiff", "profit", "type",
         "MFE", "MAE", "mfeCandle", "maeCandle", "close_decision", "close_detail",
         "reason", "volume", "bothComments", "level", "levelTag", "planTradeNumToday", "levelTradeNumToday", "offset", "tp", "sl",
         "greenRatio_at_close", AlgoGatesColAvgProfitVelocity(algoSlot1), "secondsGreen", "secondsRed", "time_to_reach_neutral_TP",
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
            TimeToString(tr.startTime, TIME_DATE|TIME_SECONDS),
            TimeToString(tr.endTime, TIME_DATE|TIME_SECONDS),
            tr.session,
            IntegerToString((long)tr.magic),
            DoubleToString(tr.priceStart, _Digits),
            DoubleToString(tr.priceEnd, _Digits),
            DoubleToString(tr.priceDiff, _Digits),
            DoubleToString(tr.profit, 2),
            EnumToString((ENUM_DEAL_TYPE)tr.type),
            (hasTel ? DoubleToString(telSummary.mfePts, 1) : ""),
            (hasTel ? DoubleToString(telSummary.maePts, 1) : ""),
            legacyCtx.mfeCandle, legacyCtx.maeCandle,
            (hasTel ? FalgoSanitizeCsvCell(telSummary.closeDecision) : ""),
            (hasTel ? FalgoSanitizeCsvCell(telSummary.closeDetail) : ""),
            EnumToString((ENUM_DEAL_REASON)tr.reason),
            tr.volume, tr.bothComments, tr.level, FalgoLevelTagUneditedForTradeResult(tr),
            IntegerToString(planNum), IntegerToString(levelNum),
            FalgoOffsetPriceUnitsStrForTrade(tr), FalgoSanitizeCsvCell(tr.tp), FalgoSanitizeCsvCell(tr.sl),
            (hasTel ? DoubleToString(telSummary.greenRatioAtClose, 4) : ""),
            (hasTel ? DoubleToString(telSummary.avgProfitVelocity, 3) : ""),
            (hasTel ? IntegerToString(telSummary.secondsGreen) : ""),
            (hasTel ? IntegerToString(telSummary.secondsRed) : ""),
            (hasTel && telSummary.timeToReachNeutralTpSeconds >= 0
               ? IntegerToString(telSummary.timeToReachNeutralTpSeconds) : ""),
            legacyCtx.breakevenC,
            legacyCtx.gapFillPc, legacyCtx.openGapInfo, legacyCtx.pdTrend,
            legacyCtx.dayBrokePDH, legacyCtx.dayBrokePDL,
            legacyCtx.refAbove, legacyCtx.refBelow, legacyCtx.levelCats,
            IntegerToString(wCeilingC), IntegerToString(dCeilingC),
            IntegerToString(wBounceC), IntegerToString(dBounceC));
      }
      FileClose(fhDay);
   }

   const string summaryAllName = "summary_tradeResults_all_days_algo" + IntegerToString(algoSlot1) + ".tsv";
   string headerParts[];
   const int schemaCols = StringSplit(FALGO_ALLDAYS_HEADER, ',', headerParts);
   if(schemaCols != FALGO_ALLDAYS_COLS)
      FatalError(StringFormat("WriteAlgoEodTradeResultsCsvsIfNeeded: schemaCols %d != FALGO_ALLDAYS_COLS %d", schemaCols, FALGO_ALLDAYS_COLS));

   string allDaysCells[];
   int existingRowCount = 0;
   FalgoReadAllDaysTradeResultsFromFile(summaryAllName, allDaysCells, existingRowCount);

   for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
   {
      TradeResult tr = g_tradeResults[trIdx];
      if(!tr.foundOut || !IsAlgoCompositeMagic(tr.magic, algoSlot1))
         continue;
      if(FalgoAllDaysRowsContainTrade(allDaysCells, existingRowCount, tr.magic, tr.startTime))
         continue;
      FalgoAppendTradeResultCells(allDaysCells, dateStr, tr);
      existingRowCount++;
   }

   FalgoSortAllDaysCellRowsByStartTimeAsc(allDaysCells, existingRowCount);
   FalgoWriteAllDaysTradeResultsToFile(summaryAllName, allDaysCells, existingRowCount);
}

//+------------------------------------------------------------------+
//| EOD: all-days TSV across algo10+11+12 — read/merge/append today's family rows. |
//+------------------------------------------------------------------+
void WriteAlgoFamilyAllDaysTradeResultsSummaryIfNeeded(const string dateStr)
{
   if(!AlgoFamilyEodTradeResultsAllDaysLoggingEnabled())
      return;

   int familyOutCount = 0;
   for(int trScan = 0; trScan < g_tradeResultsCount; trScan++)
   {
      if(!g_tradeResults[trScan].foundOut)
         continue;
      if(IsAnyAlgoFamilyCompositeMagic(g_tradeResults[trScan].magic))
         familyOutCount++;
   }
   if(familyOutCount <= 0)
      return;

   const string summaryAllName = "summary_tradeResults_all_days.tsv";
   string headerParts[];
   const int schemaCols = StringSplit(FALGO_ALLDAYS_HEADER, ',', headerParts);
   if(schemaCols != FALGO_ALLDAYS_COLS)
      FatalError(StringFormat("WriteAlgoFamilyAllDaysTradeResultsSummaryIfNeeded: schemaCols %d != FALGO_ALLDAYS_COLS %d", schemaCols, FALGO_ALLDAYS_COLS));

   string allDaysCells[];
   int existingRowCount = 0;
   FalgoReadAllDaysTradeResultsFromFile(summaryAllName, allDaysCells, existingRowCount);

   for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
   {
      TradeResult tr = g_tradeResults[trIdx];
      if(!tr.foundOut || !IsAnyAlgoFamilyCompositeMagic(tr.magic))
         continue;
      if(FalgoAllDaysRowsContainTrade(allDaysCells, existingRowCount, tr.magic, tr.startTime))
         continue;
      FalgoAppendTradeResultCells(allDaysCells, dateStr, tr);
      existingRowCount++;
   }

   FalgoSortAllDaysCellRowsByStartTimeAsc(allDaysCells, existingRowCount);
   FalgoWriteAllDaysTradeResultsToFile(summaryAllName, allDaysCells, existingRowCount);
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

   for(int si = 0; si < g_algoCount; si++)
   {
      const int algoNumber = g_algos[si].algo_id;
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
}

//+------------------------------------------------------------------+
//| Algo family profile defaults (shared + algo10/11/12). |
//+------------------------------------------------------------------+
void SyncAlgoFamilyProfileFromInputs()
{  // algobookmark1 — shared + individual tune blocks
   RebuildAlgoSlotsRegistry();
   //=== SHARED TUNE BLOCK ===
   g_algoShared.stop_trading_today_if_AllAlgos_losing_trades_count  = 999;
   g_algoShared.stop_trading_today_if_AllAlgos_winning_trades_count = 999;
   g_algoShared.babysit_enabled                                = true;
   // per-algo (date)_algoN_trade_telemetry_per_second.csv window
   g_algoShared.persecond_debug_enabled                        = true;
   g_algoShared.persecond_debug_start_hour                     =   0;
   g_algoShared.persecond_debug_start_minute                   =  20;
   g_algoShared.persecond_debug_end_hour                       =  22;
   g_algoShared.persecond_debug_end_minute                     =  59;
   g_algoShared.secretTPSL                                     = true;
   g_algoShared.secretTPSL_percent                             = 50;
   //=== algo10 TUNE BLOCK ===
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].trades_short                                     = ALGO_SIDE_LONG;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].enabled                                         = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].blockPlacementIfFamilyOpenOrPending             = false;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.stop_trading_today_if_thisAlgo_losing_trades_count      =  2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.stop_trading_today_if_thisAlgo_winning_trades_count     =  4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.babysitStart_minute                                     =  0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.neutral_trade_TP                                         =  2.1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.strong_trade_TP                                         =  3.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.strong_trade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.badtrade_mode_enabled                                    = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.terribletrade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.strong_trade_eval_min_profit_pts                      =  1.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.strong_trade_min_velocity_trigger                             = 0.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.strong_trade_velocity_window_seconds                  =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.strong_trade_stall_velocity_max_trigger                       = 0.1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.strong_trade_stall_giveback_pts_trigger                       =  99.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.strong_trade_stall_min_close_profit_pts               =  2.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.telemetry_velocity_window_seconds                        = 10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.telemetry_avg_velocity_window_seconds                    =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.trade_telemetry_per_second_enabled                       = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.badtrade_profit_trigger                                  =  -4.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.badtrade_totalRedSeconds_minTrigger                      =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.badtrade_try_save_TP                                      =   1.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.terribletrade_profit_trigger                             =  -5.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.terribletrade_consecutiveRedSeconds_minTrigger            =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.terribletrade_avgProfitVelocity10_trigger                 = 0.02;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].tune.terribletrade_try_smaller_loss_TP                           =  -2.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].bounceMaxAllowed_today                          =  3;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].min_anchorAbove_cleanStreak                     =  3.2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].min_cleanOHLC_streak_count                      =    6;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].levelOffset                               = 0.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].priceProximity                             =  4.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO10)].expiry_minutes                              =  5;
   //=== algo11 TUNE BLOCK ===
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].trades_short                                     = ALGO_SIDE_LONG;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].enabled                                         = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].blockPlacementIfFamilyOpenOrPending             = false;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.stop_trading_today_if_thisAlgo_losing_trades_count      =  2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.stop_trading_today_if_thisAlgo_winning_trades_count     =  4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.babysitStart_minute                                     =  0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.neutral_trade_TP                                         =  2.1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.strong_trade_TP                                         =  3.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.strong_trade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.badtrade_mode_enabled                                    = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.terribletrade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.strong_trade_eval_min_profit_pts                      =  1.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.strong_trade_min_velocity_trigger                             = 0.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.strong_trade_velocity_window_seconds                  =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.strong_trade_stall_velocity_max_trigger                       = -1.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.strong_trade_stall_giveback_pts_trigger                       =  99.0; // 0.4. 99 disables 
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.strong_trade_stall_min_close_profit_pts               =  2.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.telemetry_velocity_window_seconds                        = 10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.telemetry_avg_velocity_window_seconds                    =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.trade_telemetry_per_second_enabled                       = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.badtrade_profit_trigger                                  =  -3.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.badtrade_totalRedSeconds_minTrigger                      =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.badtrade_try_save_TP                                     =   1.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.terribletrade_profit_trigger                             =  -5.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.terribletrade_consecutiveRedSeconds_minTrigger            =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.terribletrade_avgProfitVelocity10_trigger                 = 0.02;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].tune.terribletrade_try_smaller_loss_TP                           =  -2.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].min_bounceCount                                 =  2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].recentBounceCountToday_Minutes                   = 600;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].recentBounceCount_max_allowed                   =  1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].min_anchorAbove_cleanStreak                     =  8.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].min_cleanOHLC_streak_count                      =    6;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].levelOffset                               = 0.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].priceProximity                             =  4.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].expiry_minutes                              =  5;
   //=== algo12 TUNE BLOCK ===
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].trades_short                                     = ALGO_SIDE_SHORT;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].enabled                                         = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].blockPlacementIfFamilyOpenOrPending             = false;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.stop_trading_today_if_thisAlgo_losing_trades_count      =  2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.stop_trading_today_if_thisAlgo_winning_trades_count     =  4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.babysitStart_minute                                     =  0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.neutral_trade_TP                                         =  2.1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.strong_trade_TP                                         =  3.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.strong_trade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.badtrade_mode_enabled                                    = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.terribletrade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.strong_trade_eval_min_profit_pts                      =  1.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.strong_trade_min_velocity_trigger                             = 0.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.strong_trade_velocity_window_seconds                  =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.strong_trade_stall_velocity_max_trigger                       = 0.1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.strong_trade_stall_giveback_pts_trigger                       =  99.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.strong_trade_stall_min_close_profit_pts               =  2.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.telemetry_velocity_window_seconds                        = 10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.telemetry_avg_velocity_window_seconds                    =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.trade_telemetry_per_second_enabled                       = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.badtrade_profit_trigger                                  =  -3.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.badtrade_totalRedSeconds_minTrigger                      =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.badtrade_try_save_TP                                     =   1.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.terribletrade_profit_trigger                             =  -5.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.terribletrade_consecutiveRedSeconds_minTrigger            =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.terribletrade_avgProfitVelocity10_trigger                 = 0.02;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].tune.terribletrade_try_smaller_loss_TP                           =  -2.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].ceilingMaxAllowed_today                         =  2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].max_allowed_shorts_perLevel_perDay_forThisAlgo                =  1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].recentCeilingCountToday_Minutes                 = 300;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].min_anchorBelow_cleanStreak                     = 11.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].min_cleanOHLC_streak_count                      =    2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].levelOffset                              =  1.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].priceProximity                            =  5.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].expiry_minutes                              =  8;
   //=== algo13 TUNE BLOCK (algo10-like: long, zero bounce, anchor>6, |level-ONO|>=12) ===
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].trades_short                                     = ALGO_SIDE_LONG;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].enabled                                         = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].blockPlacementIfFamilyOpenOrPending             = false;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.stop_trading_today_if_thisAlgo_losing_trades_count      =  2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.stop_trading_today_if_thisAlgo_winning_trades_count     =  4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.babysitStart_minute                                     =  0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.neutral_trade_TP                                         =  2.1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.strong_trade_TP                                         =  3.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.strong_trade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.badtrade_mode_enabled                                    = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.terribletrade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.strong_trade_eval_min_profit_pts                      =  1.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.strong_trade_min_velocity_trigger                             = 0.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.strong_trade_velocity_window_seconds                  =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.strong_trade_stall_velocity_max_trigger                       = 0.1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.strong_trade_stall_giveback_pts_trigger                       =  99.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.strong_trade_stall_min_close_profit_pts               =  2.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.telemetry_velocity_window_seconds                        = 10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.telemetry_avg_velocity_window_seconds                    =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.trade_telemetry_per_second_enabled                       = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.badtrade_profit_trigger                                  =  -4.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.badtrade_totalRedSeconds_minTrigger                      =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.badtrade_try_save_TP                                      =   1.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.terribletrade_profit_trigger                             =  -5.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.terribletrade_consecutiveRedSeconds_minTrigger            =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.terribletrade_avgProfitVelocity10_trigger                 = 0.02;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].tune.terribletrade_try_smaller_loss_TP                           =  -2.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].max_weekly_bounce_allowed                       =  0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].bounceMaxAllowed_today                          =  0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].min_levelOnoAbsDiff                             = 12.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].min_anchorAbove_cleanStreak                     =  6.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].min_cleanOHLC_streak_count                      =    6;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].levelOffset                               = 0.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].priceProximity                             =  4.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO13)].expiry_minutes                              =  5;
   //=== algo14 TUNE BLOCK (algo12-like: short, zero ceiling, anchor>6, |level-ONO|>=12) ===
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].trades_short                                     = ALGO_SIDE_SHORT;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].enabled                                         = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].blockPlacementIfFamilyOpenOrPending             = false;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.stop_trading_today_if_thisAlgo_losing_trades_count      =  2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.stop_trading_today_if_thisAlgo_winning_trades_count     =  4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.babysitStart_minute                                     =  0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.neutral_trade_TP                                         =  2.1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.strong_trade_TP                                         =  3.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.strong_trade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.badtrade_mode_enabled                                    = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.terribletrade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.strong_trade_eval_min_profit_pts                      =  1.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.strong_trade_min_velocity_trigger                             = 0.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.strong_trade_velocity_window_seconds                  =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.strong_trade_stall_velocity_max_trigger                       = 0.1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.strong_trade_stall_giveback_pts_trigger                       =  99.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.strong_trade_stall_min_close_profit_pts               =  2.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.telemetry_velocity_window_seconds                        = 10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.telemetry_avg_velocity_window_seconds                    =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.trade_telemetry_per_second_enabled                       = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.badtrade_profit_trigger                                  =  -3.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.badtrade_totalRedSeconds_minTrigger                      =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.badtrade_try_save_TP                                     =   1.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.terribletrade_profit_trigger                             =  -5.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.terribletrade_consecutiveRedSeconds_minTrigger            =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.terribletrade_avgProfitVelocity10_trigger                 = 0.02;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].tune.terribletrade_try_smaller_loss_TP                           =  -2.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].max_weekly_ceiling_allowed                      =  0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].ceilingMaxAllowed_today                         =  0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].min_levelOnoAbsDiff                             = 12.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].max_allowed_shorts_perLevel_perDay_forThisAlgo                =  1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].recentCeilingCountToday_Minutes                 = 300;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].min_anchorBelow_cleanStreak                     =  6.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].min_cleanOHLC_streak_count                      =    2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].levelOffset                              =  1.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].priceProximity                            =  5.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO14)].expiry_minutes                              =  8;
   //=== algo15 TUNE BLOCK (long; PD_red / dayBrokePDL=false / aboveONL / belowDayHighSoFar gates) ===
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].trades_short                                     = ALGO_SIDE_LONG;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].enabled                                         = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].blockPlacementIfFamilyOpenOrPending             = false;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.stop_trading_today_if_thisAlgo_losing_trades_count      =  2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.stop_trading_today_if_thisAlgo_winning_trades_count     =  4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.babysitStart_minute                                     =  0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.neutral_trade_TP                                         =  2.1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.strong_trade_TP                                         =  3.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.strong_trade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.badtrade_mode_enabled                                    = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.terribletrade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.strong_trade_eval_min_profit_pts                      =  1.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.strong_trade_min_velocity_trigger                             = 0.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.strong_trade_velocity_window_seconds                  =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.strong_trade_stall_velocity_max_trigger                       = 0.1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.strong_trade_stall_giveback_pts_trigger                       =  99.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.strong_trade_stall_min_close_profit_pts               =  2.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.telemetry_velocity_window_seconds                        = 10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.telemetry_avg_velocity_window_seconds                    =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.trade_telemetry_per_second_enabled                       = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.badtrade_profit_trigger                                  =  -4.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.badtrade_totalRedSeconds_minTrigger                      =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.badtrade_try_save_TP                                      =   1.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.terribletrade_profit_trigger                             =  -5.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.terribletrade_consecutiveRedSeconds_minTrigger            =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.terribletrade_avgProfitVelocity10_trigger                 = 0.02;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].tune.terribletrade_try_smaller_loss_TP                           =  -2.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].bounceMaxAllowed_today                          =  3;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].min_anchorAbove_cleanStreak                     =  3.2;  
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].min_cleanOHLC_streak_count                      =    6;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].levelOffset                               = 0.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].priceProximity                             =  4.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO15)].expiry_minutes                              =  5;
   //=== algo16 TUNE BLOCK (algo12-like short + dayBrokePDH=false | belowPDH | aboveDayLowSoFar) ===
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].trades_short                                     = ALGO_SIDE_SHORT;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].enabled                                         = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].blockPlacementIfFamilyOpenOrPending             = false;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.stop_trading_today_if_thisAlgo_losing_trades_count      =  2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.stop_trading_today_if_thisAlgo_winning_trades_count     =  4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.babysitStart_minute                                     =  0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.neutral_trade_TP                                         =  2.1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.strong_trade_TP                                         =  3.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.strong_trade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.badtrade_mode_enabled                                    = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.terribletrade_mode_enabled                               = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.strong_trade_eval_min_profit_pts                      =  1.8;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.strong_trade_min_velocity_trigger                             = 0.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.strong_trade_velocity_window_seconds                  =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.strong_trade_stall_velocity_max_trigger                       = 0.1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.strong_trade_stall_giveback_pts_trigger                       =  99.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.strong_trade_stall_min_close_profit_pts               =  2.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.telemetry_velocity_window_seconds                        = 10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.telemetry_avg_velocity_window_seconds                    =   10;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.trade_telemetry_per_second_enabled                       = true;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.badtrade_profit_trigger                                  =  -3.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.badtrade_totalRedSeconds_minTrigger                      =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.badtrade_try_save_TP                                     =   1.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.terribletrade_profit_trigger                             =  -5.5;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.terribletrade_consecutiveRedSeconds_minTrigger            =   90;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.terribletrade_avgProfitVelocity10_trigger                 = 0.02;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].tune.terribletrade_try_smaller_loss_TP                           =  -2.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].ceilingMaxAllowed_today                         =  2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].max_allowed_shorts_perLevel_perDay_forThisAlgo                =  1;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].recentCeilingCountToday_Minutes                 = 300;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].min_anchorBelow_cleanStreak                     = 11.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].min_cleanOHLC_streak_count                      =    2;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].levelOffset                              =  1.4;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].priceProximity                            =  5.0;
   g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO16)].expiry_minutes                              =  8;
   //=== algobookmark3 end tune blocks ===

   g_algoShared.tradeSizePct = 100;
   g_algoShared.bannedRanges = "21,35,23,59;0,0,1,0";
   g_algoShared.tradesWeeklyLevels = true;
   g_algoShared.tradesDailyLevels = false;
   g_algoShared.tradesDays = "12345";
   g_algoShared.initialTP = 22.0;
   g_algoShared.initialSL = 22.0;
   g_algoShared.revenge_long_allowed_perdayCount = 1;
   g_algoShared.revenge_short_allowed_perdayCount = 1;
   g_algoShared.revenge_initialTP = 24.0;
   g_algoShared.revenge_initialSL = 24.0;
   AlgoRebuildAllRuleChains();
   RebuildFalgoBannedRangesCache();
}

//+------------------------------------------------------------------+
//| OnInit: load algo family profile defaults and validate at least one algo slot is enabled. |
//+------------------------------------------------------------------+
void ValidateMagicCompositionOnInit()
{
   SyncAlgoFamilyProfileFromInputs();
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
//| Look up level in g_levelsExpanded by price (tradeResult.level string). Fills outTag (e.g. dailySmash) and outCats (e.g. daily_monday_smash_stacked). Empty if not found. |
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
//| algo-family pullinghistory globals at barIdx (g_pullingHistoryAlgoFamilyAtBar; filled after UpdateDayProgress). |
//+------------------------------------------------------------------+
int GetAlgoFamilyDayTradesCount(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyAtBar[barIdx].dayTradesCount;
}

double GetAlgoFamilyDayWinRate(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0.0;
   return g_pullingHistoryAlgoFamilyAtBar[barIdx].dayWinRate;
}

double GetAlgoFamilyDayPointsSum(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0.0;
   return g_pullingHistoryAlgoFamilyAtBar[barIdx].dayPointsSum;
}

double GetAlgoFamilyDayProfitSum(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0.0;
   return g_pullingHistoryAlgoFamilyAtBar[barIdx].dayProfitSum;
}

bool GetAlgoFamilyAccOpenTradeNow(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return g_pullingHistoryAlgoFamilyAtBar[barIdx].accOpenTradeNowBool;
}

datetime GetAlgoFamilyAccOpenTradeTime(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyAtBar[barIdx].accOpenTradeTime;
}

datetime GetAlgoFamilyAccLastClosedTradeTime(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgoFamilyAtBar[barIdx].accLastClosedTradeTime;
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
//| Fill g_algoFamilyWeekPerspective[] with today's active weekly levels (zeroed stats). |
//+------------------------------------------------------------------+
void CollectActiveWeeklyLevelsForAlgoFamily(const string dateStr)
{
   g_algoFamilyWeekPerspectiveCount = 0;
   for(int levelIdx = 0; levelIdx < g_levelsTotalCount && g_algoFamilyWeekPerspectiveCount < MAX_ALGOFAMILY_WEEK_LEVELS; levelIdx++)
   {
      if(!LevelIsWeekly(g_levels[levelIdx].categories)) continue;
      if(g_levels[levelIdx].startStr > dateStr || dateStr > g_levels[levelIdx].endStr) continue;
      int rowIdx = g_algoFamilyWeekPerspectiveCount++;
      g_algoFamilyWeekPerspective[rowIdx].levelPrice = g_levels[levelIdx].levelPrice;
      g_algoFamilyWeekPerspective[rowIdx].tag = g_levels[levelIdx].tag;
      g_algoFamilyWeekPerspective[rowIdx].categories = g_levels[levelIdx].categories;
      g_algoFamilyWeekPerspective[rowIdx].maxPriceAbove = 0.0;
      g_algoFamilyWeekPerspective[rowIdx].maxPriceBelow = 0.0;
      g_algoFamilyWeekPerspective[rowIdx].touchedProx_09_C = 0;
      g_algoFamilyWeekPerspective[rowIdx].brokenBool = false;
      g_algoFamilyWeekPerspective[rowIdx].countONO_too_close_10p = 0;
      g_algoFamilyWeekPerspective[rowIdx].candle_overlap_1m_C = 0;
      g_algoFamilyWeekPerspective[rowIdx].bounceCount = 0;
      g_algoFamilyWeekPerspective[rowIdx].ceilingCount = 0;
   }
}

//+------------------------------------------------------------------+
//| Week bounce/ceiling counts per level (same rules as Arawevents FinalizeCurrentCandle). |
//+------------------------------------------------------------------+
void AlgoFamilyWeekPerspectiveEvalBounceCeiling(const MqlRates &weekRates[], int barCount, datetime weekStart)
{
   for(int rowIdx = 0; rowIdx < g_algoFamilyWeekPerspectiveCount; rowIdx++)
   {
      double lvl = g_algoFamilyWeekPerspective[rowIdx].levelPrice;
      g_algoFamilyWeekPerspective[rowIdx].bounceCount = 0;
      g_algoFamilyWeekPerspective[rowIdx].ceilingCount = 0;
      bool lastCandleInContact = false;
      bool contactFromBelow = false;
      for(int barIdx = 0; barIdx < barCount; barIdx++)
      {
         if(weekRates[barIdx].time < weekStart) continue;
         double op = weekRates[barIdx].open;
         double hi = weekRates[barIdx].high;
         double lo = weekRates[barIdx].low;
         double cl = weekRates[barIdx].close;
         bool physicallyTouched = (lo <= lvl && hi >= lvl);
         bool proximityTouched  = (MathAbs(op - lvl) <= ProximityThreshold ||
                                 MathAbs(hi - lvl) <= ProximityThreshold ||
                                 MathAbs(lo - lvl) <= ProximityThreshold ||
                                 MathAbs(cl - lvl) <= ProximityThreshold);
         bool in_contact = physicallyTouched || proximityTouched;
         if(in_contact && cl < lvl)
            contactFromBelow = true;
         if(in_contact && cl >= lvl)
            contactFromBelow = false;
         bool bounceCandle = (!in_contact && lo > lvl);
         if(lastCandleInContact && bounceCandle)
         {
            g_algoFamilyWeekPerspective[rowIdx].bounceCount++;
            contactFromBelow = false;
         }
         bool ceilingCandle = (!in_contact && hi < lvl);
         if(lastCandleInContact && ceilingCandle && contactFromBelow)
         {
            g_algoFamilyWeekPerspective[rowIdx].ceilingCount++;
            contactFromBelow = false;
         }
         if(!in_contact && !lastCandleInContact)
            contactFromBelow = false;
         lastCandleInContact = in_contact;
      }
   }
}

//+------------------------------------------------------------------+
//| Scan current-week M1 for one weekly level; update g_algoFamilyWeekPerspective[rowIdx]. |
//+------------------------------------------------------------------+
void AlgoFamilyWeekPerspectiveAccumulateLevel(int rowIdx, const MqlRates &weekRates[], int barCount, datetime weekStart)
{
   if(rowIdx < 0 || rowIdx >= g_algoFamilyWeekPerspectiveCount) return;
   double lvl = g_algoFamilyWeekPerspective[rowIdx].levelPrice;
   for(int barIdx = 0; barIdx < barCount; barIdx++)
   {
      if(weekRates[barIdx].time < weekStart) continue;
      double hi = weekRates[barIdx].high;
      double lo = weekRates[barIdx].low;
      double cl = weekRates[barIdx].close;
      if(hi > lvl)
         g_algoFamilyWeekPerspective[rowIdx].maxPriceAbove = MathMax(g_algoFamilyWeekPerspective[rowIdx].maxPriceAbove, hi - lvl);
      if(lo < lvl)
         g_algoFamilyWeekPerspective[rowIdx].maxPriceBelow = MathMax(g_algoFamilyWeekPerspective[rowIdx].maxPriceBelow, lvl - lo);
      if(lo <= lvl + ALGO5_WEEK_PROX_TOUCH_POINTS && hi >= lvl - ALGO5_WEEK_PROX_TOUCH_POINTS)
         g_algoFamilyWeekPerspective[rowIdx].touchedProx_09_C++;
      if(lo <= lvl && lvl <= hi)
         g_algoFamilyWeekPerspective[rowIdx].candle_overlap_1m_C++;
   }
}

//+------------------------------------------------------------------+
//| Per calendar day in weekRates: ONO = open of first M1 bar (like g_ONopen). Count days per level where |level - ONO| < threshold. |
//+------------------------------------------------------------------+
void AlgoFamilyWeekPerspectiveEvalONOtooClose(const MqlRates &weekRates[], int barCount, datetime weekStart)
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
   for(int rowIdx = 0; rowIdx < g_algoFamilyWeekPerspectiveCount; rowIdx++)
   {
      double lvl = g_algoFamilyWeekPerspective[rowIdx].levelPrice;
      g_algoFamilyWeekPerspective[rowIdx].countONO_too_close_10p = 0;
      for(int dayIdx = 0; dayIdx < dayCount; dayIdx++)
      {
         if(MathAbs(lvl - dayONO[dayIdx]) < ALGO5_WEEK_ON_TOO_CLOSE_POINTS)
            g_algoFamilyWeekPerspective[rowIdx].countONO_too_close_10p++;
      }
   }
}

//+------------------------------------------------------------------+
//| brokenBool: level strictly between week min ONO and max high of non-ONO M1 bars, or between min low of non-ONO bars and max ONO. |
//+------------------------------------------------------------------+
void AlgoFamilyWeekPerspectiveEvalBrokenBool(const MqlRates &weekRates[], int barCount, datetime weekStart)
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
   for(int rowIdx = 0; rowIdx < g_algoFamilyWeekPerspectiveCount; rowIdx++)
   {
      double lvl = g_algoFamilyWeekPerspective[rowIdx].levelPrice;
      g_algoFamilyWeekPerspective[rowIdx].brokenBool = false;
      if(!hasONO || !hasOther) continue;
      if(minONO < lvl && lvl < maxOtherHigh)
         g_algoFamilyWeekPerspective[rowIdx].brokenBool = true;
      if(minOtherLow < lvl && lvl < maxONO)
         g_algoFamilyWeekPerspective[rowIdx].brokenBool = true;
   }
}

//+------------------------------------------------------------------+
//| Sort g_algoFamilyWeekPerspective[] by levelPrice descending (highest first). |
//+------------------------------------------------------------------+
void AlgoFamilyWeekPerspectiveSortByLevelPriceDesc()
{
   for(int sortIdx = 0; sortIdx < g_algoFamilyWeekPerspectiveCount - 1; sortIdx++)
      for(int innerIdx = sortIdx + 1; innerIdx < g_algoFamilyWeekPerspectiveCount; innerIdx++)
         if(g_algoFamilyWeekPerspective[innerIdx].levelPrice > g_algoFamilyWeekPerspective[sortIdx].levelPrice)
         {
            AlgoFamilyWeekPerspectiveRow swapTmp = g_algoFamilyWeekPerspective[sortIdx];
            g_algoFamilyWeekPerspective[sortIdx] = g_algoFamilyWeekPerspective[innerIdx];
            g_algoFamilyWeekPerspective[innerIdx] = swapTmp;
         }
}

//+------------------------------------------------------------------+
//| Write (date)_algofamily_weekPerspective.csv from globals.             |
//+------------------------------------------------------------------+
void WriteAlgoFamilyWeekPerspectiveLog(const string dateStr, datetime weekMondayStart)
{
   if(!dailyLog_algoFamilyWeekPerspective) return;
   AlgoFamilyWeekPerspectiveSortByLevelPriceDesc();
   string logName = dateStr + "_algofamily_weekPerspective.csv";
   int fileHandle = FileOpen(logName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandle == INVALID_HANDLE)
   {
      Print("WriteAlgoFamilyWeekPerspectiveLog: could not open ", logName);
      return;
   }
   FileWrite(fileHandle, "date", "weekMondayStart", "levelPrice", "tag", "categories",
             "maxPriceAbove", "maxPriceBelow", "touchedProxBool_09_C", "brokenBool", "countONO_too_close_10p", "1mCandle_overlapC",
             "BounceCount", "CeilingCount");
   string weekStartStr = TimeToString(weekMondayStart, TIME_DATE);
   for(int rowIdx = 0; rowIdx < g_algoFamilyWeekPerspectiveCount; rowIdx++)
   {
      FileWrite(fileHandle, dateStr, weekStartStr,
                DoubleToString(g_algoFamilyWeekPerspective[rowIdx].levelPrice, _Digits),
                g_algoFamilyWeekPerspective[rowIdx].tag,
                g_algoFamilyWeekPerspective[rowIdx].categories,
                DoubleToString(g_algoFamilyWeekPerspective[rowIdx].maxPriceAbove, _Digits),
                DoubleToString(g_algoFamilyWeekPerspective[rowIdx].maxPriceBelow, _Digits),
                IntegerToString(g_algoFamilyWeekPerspective[rowIdx].touchedProx_09_C),
                (g_algoFamilyWeekPerspective[rowIdx].brokenBool ? "true" : "false"),
                IntegerToString(g_algoFamilyWeekPerspective[rowIdx].countONO_too_close_10p),
                IntegerToString(g_algoFamilyWeekPerspective[rowIdx].candle_overlap_1m_C),
                IntegerToString(g_algoFamilyWeekPerspective[rowIdx].bounceCount),
                IntegerToString(g_algoFamilyWeekPerspective[rowIdx].ceilingCount));
   }
   FileClose(fileHandle);
}

//+------------------------------------------------------------------+
//| Rebuild algofamily_weekPerspective memory + log (OnInit and each new day). Monday: log only, no week M1 scan. |
//+------------------------------------------------------------------+
void RefreshAlgoFamilyWeekPerspective(datetime refTime)
{
   if(refTime == 0)
      refTime = TimeCurrent();
   datetime dayStart = refTime - (refTime % 86400);
   string dateStr = TimeToString(dayStart, TIME_DATE);
   if(dateStr == g_algoFamilyWeekPerspectiveEvaluatedForDate)
      return;

   CollectActiveWeeklyLevelsForAlgoFamily(dateStr);
   datetime weekMondayStart = GetWeekMondayStart(refTime);
   bool mondaySkipped = IsMondayDatetime(refTime);

   if(!mondaySkipped && g_algoFamilyWeekPerspectiveCount > 0)
   {
      MqlRates weekRates[];
      int copied = CopyRates(_Symbol, PERIOD_M1, weekMondayStart, refTime, weekRates);
      if(copied > 0)
      {
         for(int rowIdx = 0; rowIdx < g_algoFamilyWeekPerspectiveCount; rowIdx++)
            AlgoFamilyWeekPerspectiveAccumulateLevel(rowIdx, weekRates, copied, weekMondayStart);
         AlgoFamilyWeekPerspectiveEvalONOtooClose(weekRates, copied, weekMondayStart);
         AlgoFamilyWeekPerspectiveEvalBrokenBool(weekRates, copied, weekMondayStart);
         AlgoFamilyWeekPerspectiveEvalBounceCeiling(weekRates, copied, weekMondayStart);
      }
      else
         Print("RefreshAlgoFamilyWeekPerspective: CopyRates returned ", copied, " for week starting ", TimeToString(weekMondayStart, TIME_DATE));
   }

   WriteAlgoFamilyWeekPerspectiveLog(dateStr, weekMondayStart);
   g_algoFamilyWeekPerspectiveEvaluatedForDate = dateStr;
}

//+------------------------------------------------------------------+
//| g_levelsExpanded[levelIdx].tag only; levelIdx must be stage-1 row (no price re-match, no other fallback). |
//| outSimple is "weeklysmash" | "weeklydown" | "weeklyup" or "". Lowercase tag; order smash → down → up so weeklydown before weeklyup. |
//+------------------------------------------------------------------+
void GetLevelTagWeeklySimplified(const int levelIdx, string &outSimple)
{
   outSimple = "";
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return;
   string t = g_levelsExpanded[levelIdx].tag;
   StringToLower(t);
   if(StringFind(t, "weekly") < 0) return;
   if(StringFind(t, "smash") >= 0)
   {
      outSimple = "weeklysmash";
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
//| outSimple is "smash" | "down" | "up" or "". Lowercase tag; order smash → down → up (so weeklydown before weeklyup). |
//| Daily + weekly: dailySmash/weeklySmash, dailyDown*/weeklyDown*, dailyUp*/weeklyUp* (+ *_down / *_up spellings). |
//+------------------------------------------------------------------+
void GetLevelTagSimplified(const int levelIdx, string &outSimple)
{
   outSimple = "";
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return;
   string t = g_levelsExpanded[levelIdx].tag;
   StringToLower(t);
   if(StringFind(t, "smash") >= 0)
   {
      outSimple = "smash";
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
//| Other needles (smash, weekly, stacked, …): substring only, unchanged. |
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
//| True when GetLevelTagWeeklySimplified equals want (e.g. "weeklysmash" | "weeklydown" | "weeklyup"). want must match returned bucket string exactly. |
//+------------------------------------------------------------------+
bool Gate_LevelData_Weekly_TagSimplified_is(const int levelIdx, const string &want)
{
   string s;
   GetLevelTagWeeklySimplified(levelIdx, s); // result can be "weeklysmash" | "weeklydown" | "weeklyup" or ""
   return (s == want);
}

//+------------------------------------------------------------------+
//| True when GetLevelTagSimplified equals want (e.g. "down", "up" or "smash"). want must match returned bucket string exactly. |
//+------------------------------------------------------------------+
bool Gate_LevelData_TagSimplified_is(const int levelIdx, const string &want)
{
   string s;
   GetLevelTagSimplified(levelIdx, s);
   return (s == want);
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
//| Closest-weekly-level bounce/ceiling gates (reusable; not tied to a single algo). |
//+------------------------------------------------------------------+
bool Gate_ClosestWeeklyLevel_HasValue(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevelToCClose > 0.0);
}

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

bool Gate_CeilingCount_NoMoreThanX(const int barIdx, const int maxAllowed)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetCeilingCountForClosestWeeklyLevel(barIdx) <= maxAllowed);
}

bool Gate_WeekCeilingCount_NoMoreThanX(const int barIdx, const int maxAllowed)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   return (FalgoGetWeekCeilingCountForClosestWeeklyLevel(barIdx) <= maxAllowed);
}

bool Gate_ShortsAtLevel_UnderDailyLimit(const int barIdx, const int algoNumber, const int maxShortsPerLevel)
{
   if(maxShortsPerLevel <= 0) return true;
   const int tier = FalgoClosestWeeklyLevelTierAtBar(barIdx);
   if(tier < 1) return true;
   return (FalgoShortTradeCountTodayAtTierForThisAlgo(algoNumber, tier) < maxShortsPerLevel);
}

//+------------------------------------------------------------------+
//| analyze-style firstFail labels for gates above ("" = pass). |
//+------------------------------------------------------------------+
string GateFail_ClosestWeeklyLevel_Missing(const int barIdx)
{
   if(!Gate_ClosestWeeklyLevel_HasValue(barIdx)) return "noClosestWeeklyLevel";
   return "";
}

string GateFail_BounceCount_TooLow(const int barIdx, const int minCount)
{
   if(!Gate_BounceCount_AtLeastX(barIdx, minCount)) return "bounceTooLow";
   return "";
}

string GateFail_BounceCount_TooHigh(const int barIdx, const int maxAllowed, const string failLabel)
{
   if(!Gate_BounceCount_NoMoreThanX(barIdx, maxAllowed)) return failLabel;
   return "";
}

string GateFail_RecentBounceCount_TooHigh(const int barIdx, const int maxAllowed)
{
   if(!Gate_RecentBounceCount_NoMoreThanX(barIdx, maxAllowed)) return "recentBounceTooHigh";
   return "";
}

string GateFail_WeekBounceCount_TooHigh(const int barIdx, const int maxAllowed)
{
   if(!Gate_WeekBounceCount_NoMoreThanX(barIdx, maxAllowed)) return "weeklyBounceCountTooHigh";
   return "";
}

string GateFail_CeilingCount_TooHigh(const int barIdx, const int maxAllowed, const string failLabel)
{
   if(!Gate_CeilingCount_NoMoreThanX(barIdx, maxAllowed)) return failLabel;
   return "";
}

string GateFail_WeekCeilingCount_TooHigh(const int barIdx, const int maxAllowed)
{
   if(!Gate_WeekCeilingCount_NoMoreThanX(barIdx, maxAllowed)) return "weeklyCeilingCountTooHigh";
   return "";
}

string GateFail_LevelOnoAbsDiff_TooLow(const double levelPx, const double minAbsDiffPoints)
{
   if(!Gate_Level_AbsDiff_with_ONO_atLeastX(levelPx, minAbsDiffPoints)) return "levelOnoAbsDiffTooLow";
   return "";
}

string GateFail_ShortsAtLevel_Limit(const int barIdx, const int algoNumber, const int maxShortsPerLevel)
{
   if(!Gate_ShortsAtLevel_UnderDailyLimit(barIdx, algoNumber, maxShortsPerLevel)) return "shortsAtLevelLimit";
   return "";
}

string GateFail_PD_red()
{
   if(!Gate_PD_red()) return "PD_red";
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

string GateFail_Level_BelowPDH(const double levelPx)
{
   if(!Gate_Level_BelowPDH(levelPx)) return "belowPDH";
   return "";
}

string GateFail_Level_AbovedayLowSoFar(const int barIdx, const double levelPx)
{
   if(!Gate_Level_AbovedayLowSoFar(barIdx, levelPx)) return "aboveDayLowSoFar";
   return "";
}

string GateFail_Level_AboveONL(const int barIdx, const double levelPx)
{
   if(!Gate_Level_AboveONL(barIdx, levelPx)) return "aboveONL";
   return "";
}

string GateFail_Level_BelowdayHighSoFar(const int barIdx, const double levelPx)
{
   if(!Gate_Level_BelowdayHighSoFar(barIdx, levelPx)) return "belowDayHighSoFar";
   return "";
}

string GateFail_CleanStreak_Long(const int barIdx, const double minAnchorAbove, const int minStreakCount)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return "";
   if(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_anchorAbove_within_cleanOHLC_streak <= minAnchorAbove)
      return "anchorAboveTooLow";
   if(g_pullingHistoryAlgoFamilyAtBar[barIdx].cleanOHLC_streak_count <= minStreakCount)
      return "cleanOHLC_streakTooShort";
   return "";
}

string GateFail_CleanStreak_Short(const int barIdx, const double minAnchorBelow, const int minStreakCount)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return "";
   if(g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevel_anchorBelow_within_cleanOHLC_streak <= minAnchorBelow)
      return "anchorBelowTooLow";
   if(g_pullingHistoryAlgoFamilyAtBar[barIdx].cleanOHLC_streak_count <= minStreakCount)
      return "cleanOHLC_streakTooShort";
   return "";
}

//+------------------------------------------------------------------+
//| Algo rule engine: ordered rule chains per slot (g_algos[].rules). |
//+------------------------------------------------------------------+
void AlgoRuleChainClear(const int slotIdx)
{
   g_algos[slotIdx].rule_count = 0;
}

//+------------------------------------------------------------------+
void AlgoRuleChainAdd(const int slotIdx, const ENUM_ALGO_RULE ruleId,
                      const int i0 = 0, const int i1 = 0,
                      const double d0 = 0.0, const double d1 = 0.0,
                      const string s0 = "")
{
   if(slotIdx < 0 || slotIdx >= g_algoCount)
      FatalError("AlgoRuleChainAdd: invalid slotIdx");
   if(g_algos[slotIdx].rule_count >= ALGO_RULES_MAX)
      FatalError(StringFormat("AlgoRuleChainAdd: ALGO_RULES_MAX exceeded for algo %d", g_algos[slotIdx].algo_id));
   const int r = g_algos[slotIdx].rule_count;
   g_algos[slotIdx].rules[r].rule_id = ruleId;
   g_algos[slotIdx].rules[r].i0 = i0;
   g_algos[slotIdx].rules[r].i1 = i1;
   g_algos[slotIdx].rules[r].d0 = d0;
   g_algos[slotIdx].rules[r].d1 = d1;
   g_algos[slotIdx].rules[r].s0 = s0;
   g_algos[slotIdx].rule_count++;
}

//+------------------------------------------------------------------+
string EvalAlgoRule(const AlgoDef &algo, const AlgoRuleEntry &rule, const int barIdx, const double tradeLevel)
{
   switch(rule.rule_id)
   {
      case RULE_CLEAN_STREAK_LONG:
         return GateFail_CleanStreak_Long(barIdx, rule.d0, rule.i0);
      case RULE_CLEAN_STREAK_SHORT:
         return GateFail_CleanStreak_Short(barIdx, rule.d0, rule.i0);
      case RULE_BOUNCE_COUNT_TOO_HIGH:
         return GateFail_BounceCount_TooHigh(barIdx, rule.i0, rule.s0);
      case RULE_BOUNCE_COUNT_TOO_LOW:
         return GateFail_BounceCount_TooLow(barIdx, rule.i0);
      case RULE_RECENT_BOUNCE_TOO_HIGH:
         return GateFail_RecentBounceCount_TooHigh(barIdx, rule.i0);
      case RULE_CEILING_COUNT_TOO_HIGH:
         return GateFail_CeilingCount_TooHigh(barIdx, rule.i0, rule.s0);
      case RULE_SHORTS_AT_LEVEL_LIMIT:
         return GateFail_ShortsAtLevel_Limit(barIdx, algo.algo_id, rule.i0);
      case RULE_CLOSEST_WEEKLY_LEVEL_MISSING:
         return GateFail_ClosestWeeklyLevel_Missing(barIdx);
      case RULE_WEEK_BOUNCE_TOO_HIGH:
         return GateFail_WeekBounceCount_TooHigh(barIdx, rule.i0);
      case RULE_WEEK_CEILING_TOO_HIGH:
         return GateFail_WeekCeilingCount_TooHigh(barIdx, rule.i0);
      case RULE_LEVEL_ONO_ABS_DIFF_TOO_LOW:
         return GateFail_LevelOnoAbsDiff_TooLow(tradeLevel, rule.d0);
      case RULE_PD_RED:
         return GateFail_PD_red();
      case RULE_DAY_BROKE_PDL:
         return GateFail_Day_DayBrokePDL(barIdx);
      case RULE_DAY_BROKE_PDH:
         return GateFail_Day_DayBrokePDH(barIdx);
      case RULE_LEVEL_ABOVE_ONL:
         return GateFail_Level_AboveONL(barIdx, tradeLevel);
      case RULE_LEVEL_BELOW_DAY_HIGH:
         return GateFail_Level_BelowdayHighSoFar(barIdx, tradeLevel);
      case RULE_LEVEL_BELOW_PDH:
         return GateFail_Level_BelowPDH(tradeLevel);
      case RULE_LEVEL_ABOVE_DAY_LOW:
         return GateFail_Level_AbovedayLowSoFar(barIdx, tradeLevel);
   }
   return "unknownRule";
}

//+------------------------------------------------------------------+
string AlgoRunRulesFirstFail(const int slotIdx, const int barIdx)
{
   if(slotIdx < 0 || slotIdx >= g_algoCount)
      return "unknownAlgo";
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return "invalidBar";
   const double tradeLevel = g_pullingHistoryAlgoFamilyAtBar[barIdx].closestWeeklyLevelToCClose;
   const AlgoDef algo = g_algos[slotIdx];
   for(int r = 0; r < algo.rule_count; r++)
   {
      const string f = EvalAlgoRule(algo, algo.rules[r], barIdx, tradeLevel);
      if(f != "")
         return f;
   }
   return "";
}

//+------------------------------------------------------------------+
void AlgoRebuildRuleChainForSlot(const int slotIdx)
{
   if(slotIdx < 0 || slotIdx >= g_algoCount)
      return;
   const int algoId = g_algos[slotIdx].algo_id;
   const AlgoDef a = g_algos[slotIdx];
   AlgoRuleChainClear(slotIdx);
   switch(algoId)
   {
      // algobookmark rules
      case MAGIC_ALGO10:
         AlgoRuleChainAdd(slotIdx, RULE_CLEAN_STREAK_LONG, a.min_cleanOHLC_streak_count, 0, a.min_anchorAbove_cleanStreak);
         AlgoRuleChainAdd(slotIdx, RULE_BOUNCE_COUNT_TOO_HIGH, a.bounceMaxAllowed_today, 0, 0, 0, "bounceCountTooHigh");
         break;
      case MAGIC_ALGO11:
         AlgoRuleChainAdd(slotIdx, RULE_CLEAN_STREAK_LONG, a.min_cleanOHLC_streak_count, 0, a.min_anchorAbove_cleanStreak);
         AlgoRuleChainAdd(slotIdx, RULE_BOUNCE_COUNT_TOO_LOW, a.min_bounceCount);
         AlgoRuleChainAdd(slotIdx, RULE_RECENT_BOUNCE_TOO_HIGH, a.recentBounceCount_max_allowed);
         break;
      case MAGIC_ALGO12:
         AlgoRuleChainAdd(slotIdx, RULE_CLEAN_STREAK_SHORT, a.min_cleanOHLC_streak_count, 0, a.min_anchorBelow_cleanStreak);
         AlgoRuleChainAdd(slotIdx, RULE_CEILING_COUNT_TOO_HIGH, a.ceilingMaxAllowed_today, 0, 0, 0, "ceilingCountTooHigh");
         AlgoRuleChainAdd(slotIdx, RULE_SHORTS_AT_LEVEL_LIMIT, a.max_allowed_shorts_perLevel_perDay_forThisAlgo);
         break;
      case MAGIC_ALGO13:
         AlgoRuleChainAdd(slotIdx, RULE_CLEAN_STREAK_LONG, a.min_cleanOHLC_streak_count, 0, a.min_anchorAbove_cleanStreak);
         AlgoRuleChainAdd(slotIdx, RULE_CLOSEST_WEEKLY_LEVEL_MISSING);
         AlgoRuleChainAdd(slotIdx, RULE_BOUNCE_COUNT_TOO_HIGH, a.bounceMaxAllowed_today, 0, 0, 0, "dailyBounceCountTooHigh");
         AlgoRuleChainAdd(slotIdx, RULE_WEEK_BOUNCE_TOO_HIGH, a.max_weekly_bounce_allowed);
         AlgoRuleChainAdd(slotIdx, RULE_LEVEL_ONO_ABS_DIFF_TOO_LOW, 0, 0, a.min_levelOnoAbsDiff);
         break;
      case MAGIC_ALGO14:
         AlgoRuleChainAdd(slotIdx, RULE_CLEAN_STREAK_SHORT, a.min_cleanOHLC_streak_count, 0, a.min_anchorBelow_cleanStreak);
         AlgoRuleChainAdd(slotIdx, RULE_CLOSEST_WEEKLY_LEVEL_MISSING);
         AlgoRuleChainAdd(slotIdx, RULE_CEILING_COUNT_TOO_HIGH, a.ceilingMaxAllowed_today, 0, 0, 0, "dailyCeilingCountTooHigh");
         AlgoRuleChainAdd(slotIdx, RULE_WEEK_CEILING_TOO_HIGH, a.max_weekly_ceiling_allowed);
         AlgoRuleChainAdd(slotIdx, RULE_LEVEL_ONO_ABS_DIFF_TOO_LOW, 0, 0, a.min_levelOnoAbsDiff);
         AlgoRuleChainAdd(slotIdx, RULE_SHORTS_AT_LEVEL_LIMIT, a.max_allowed_shorts_perLevel_perDay_forThisAlgo);
         break;
      case MAGIC_ALGO15:
         AlgoRuleChainAdd(slotIdx, RULE_CLEAN_STREAK_LONG, a.min_cleanOHLC_streak_count, 0, a.min_anchorAbove_cleanStreak);
         AlgoRuleChainAdd(slotIdx, RULE_BOUNCE_COUNT_TOO_HIGH, a.bounceMaxAllowed_today, 0, 0, 0, "bounceCountTooHigh");
         AlgoRuleChainAdd(slotIdx, RULE_CLOSEST_WEEKLY_LEVEL_MISSING);
         AlgoRuleChainAdd(slotIdx, RULE_PD_RED);
         AlgoRuleChainAdd(slotIdx, RULE_DAY_BROKE_PDL);
         AlgoRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_ONL);
         AlgoRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_DAY_HIGH);
         break;
      case MAGIC_ALGO16:
         AlgoRuleChainAdd(slotIdx, RULE_CLEAN_STREAK_SHORT, a.min_cleanOHLC_streak_count, 0, a.min_anchorBelow_cleanStreak);
         AlgoRuleChainAdd(slotIdx, RULE_CEILING_COUNT_TOO_HIGH, a.ceilingMaxAllowed_today, 0, 0, 0, "ceilingCountTooHigh");
         AlgoRuleChainAdd(slotIdx, RULE_SHORTS_AT_LEVEL_LIMIT, a.max_allowed_shorts_perLevel_perDay_forThisAlgo);
         AlgoRuleChainAdd(slotIdx, RULE_CLOSEST_WEEKLY_LEVEL_MISSING);
         AlgoRuleChainAdd(slotIdx, RULE_DAY_BROKE_PDH);
         AlgoRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_PDH);
         AlgoRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_DAY_LOW);
         break;
      default:
         break;
   }
}

//+------------------------------------------------------------------+
void AlgoRebuildAllRuleChains()
{
   for(int i = 0; i < g_algoCount; i++)
      AlgoRebuildRuleChainForSlot(i);
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
//| Gap down day: today's RTH open < prior day RTH close (PDC). Same rule as dayPriceStat_log hasGapDown once logged; uses g_todayRTHopen so valid after RTH open bar exists. |
//+------------------------------------------------------------------+
bool Gate_Day_HasGapDown()
{
   if(!g_todayRTHopenValid || g_staticMarketContext.PDCpreviousDayRTHClose <= 0.0) return false;
   return (g_todayRTHopen < g_staticMarketContext.PDCpreviousDayRTHClose);
}

//+------------------------------------------------------------------+
//| Gap up day: RTH open > PDC. Same as dayPriceStat_log hasGapUp. |
//+------------------------------------------------------------------+
bool Gate_Day_HasGapUp()
{
   if(!g_todayRTHopenValid || g_staticMarketContext.PDCpreviousDayRTHClose <= 0.0) return false;
   return (g_todayRTHopen > g_staticMarketContext.PDCpreviousDayRTHClose);
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
//| Gap-fill state at bar kLast from g_gapFillSoFarAtBar (same % as pullinghistory gapFillSoFar). |
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
//| Falgo pending: direction 1=buy limit, 2=sell limit (magic slot 2). |
//| Limit price = closestWeeklyLevel + PointSized(signed levelOffset) (FalgoPendingOrderPricesForDirection). |
//+------------------------------------------------------------------+
bool PlacePendingFromFalgoMagic(long magic, double anchorLevel, double offsetPoints, double slPoints, double tpPoints, int expirationMin, double lot)
{
   if(!IsAnyAlgoFamilyCompositeMagic(magic))
      return false;
   FalgoMagicKey fk = ParseFalgoMagic(magic);
   double orderPrice = 0.0, stopLossVal = 0.0, takeProfitVal = 0.0;
   FalgoPendingOrderPricesForDirection(fk.direction, anchorLevel, offsetPoints, slPoints, tpPoints,
      orderPrice, stopLossVal, takeProfitVal);
   if(PlacePending_ShouldSkip_BidTooCloseToOrderPrice(orderPrice, 1.0))
      return false;
   datetime expiration = TimeCurrent() + expirationMin * 60;
   const string comment = "Falgo_placeholder";
   ExtTrade.SetExpertMagicNumber(magic);
   bool ok = false;
   switch(fk.direction)
   {
      case FALGO_DIRECTION_LONG_LIMIT:
         LogPreOrderContext(magic, anchorLevel, orderPrice, "BuyLimit", expirationMin);
         ok = ExtTrade.BuyLimit(lot, orderPrice, _Symbol, stopLossVal, takeProfitVal, ORDER_TIME_SPECIFIED, expiration, comment);
         break;
      case FALGO_DIRECTION_SHORT_LIMIT:
         LogPreOrderContext(magic, anchorLevel, orderPrice, "SellLimit", expirationMin);
         ok = ExtTrade.SellLimit(lot, orderPrice, _Symbol, stopLossVal, takeProfitVal, ORDER_TIME_SPECIFIED, expiration, comment);
         break;
      default:
         ok = false;
   }
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   return ok;
}

//+------------------------------------------------------------------+
void WriteTradeLogPendingOrderFalgo(double levelPrice, double offsetPoints, double slPoints, double tpPoints, long magic, int expirationMin)
{
   if(!IsAnyAlgoFamilyCompositeMagic(magic))
      return;
   string magicStrForLogFilename = MagicNumberToFixedWidthString(magic);
   ulong orderTicket = ExtTrade.ResultOrder();
   datetime eventTime = g_lastTimer1Time;
   if(orderTicket > 0 && OrderSelect(orderTicket))
      eventTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
   FalgoMagicKey fk = ParseFalgoMagic(magic);
   string orderKind;
   switch(fk.direction)
   {
      case FALGO_DIRECTION_LONG_LIMIT:
         orderKind = "buy_limit";
         break;
      case FALGO_DIRECTION_SHORT_LIMIT:
         orderKind = "sell_limit";
         break;
      default:
         FatalError(StringFormat("WriteTradeLogPendingOrderFalgo: unsupported direction %d magic %s", fk.direction, IntegerToString(magic)));
   }
   double orderPrice = 0.0;
   double stopLossVal = 0.0;
   double takeProfitVal = 0.0;
   FalgoPendingOrderPricesForDirection(fk.direction, levelPrice, offsetPoints, slPoints, tpPoints,
      orderPrice, stopLossVal, takeProfitVal);
   const string orderComment = "Falgo_placeholder";
   WriteTradeLog(magicStrForLogFilename, "pending_created", eventTime, orderKind, orderPrice, stopLossVal, takeProfitVal, expirationMin, orderTicket, 0, 0, (ENUM_DEAL_REASON)0, orderComment, magic);
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
      levels[levelIdx].approxContactCount = 0;
      levels[levelIdx].dailyBias = 0;
      levels[levelIdx].biasSetToday = false;
      levels[levelIdx].lastBiasDate = 0;
      levels[levelIdx].logRawEv_fileHandle = INVALID_HANDLE;
      levels[levelIdx].candlesBreakLevelCount = 0;
      levels[levelIdx].recoverCount = 0;
      levels[levelIdx].bounceCount = 0;
      levels[levelIdx].consecutiveRecoverCandles = 0;
      levels[levelIdx].lastCandleInContact = false;
      levels[levelIdx].candlesPassedSinceLastBounce = 0;
      levels[levelIdx].ceilingCount = 0;
      levels[levelIdx].candlesPassedSinceLastCeiling = 0;
      levels[levelIdx].contactFromBelow = false;
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
   levels[newIndex].approxContactCount = 0;
   levels[newIndex].dailyBias = 0;
   levels[newIndex].biasSetToday = false;
   levels[newIndex].lastBiasDate = 0;
   levels[newIndex].logRawEv_fileHandle = INVALID_HANDLE;
   levels[newIndex].candlesBreakLevelCount = 0;
   levels[newIndex].recoverCount = 0;
   levels[newIndex].bounceCount = 0;
   levels[newIndex].consecutiveRecoverCandles = 0;
   levels[newIndex].lastCandleInContact = false;
   levels[newIndex].candlesPassedSinceLastBounce = 0;
   levels[newIndex].ceilingCount = 0;
   levels[newIndex].candlesPassedSinceLastCeiling = 0;
   levels[newIndex].contactFromBelow = false;
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
//| One terminal pass: mark algo slots 10..99 with open position or pending on _Symbol. Call once per timer tick before placement. |
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
      ExtTrade.SetExpertMagicNumber((ulong)posMagic);
      ExtTrade.PositionClose(ExtPositionInfo.Ticket());
      ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   }
}


//+------------------------------------------------------------------+
//| At 21:57 close all open algo-family positions (so EOD write at 21:58 sees OUT). |
//+------------------------------------------------------------------+
void CloseAnyOpenTrade_atEOD_2158_falgo()
{
   datetime lastClosedBarTime = iTime(_Symbol, PERIOD_M1, 1);
   MqlDateTime mtClosed;
   TimeToStruct(lastClosedBarTime, mtClosed);
   if(mtClosed.hour != 21 || mtClosed.min != 57) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!ExtPositionInfo.SelectByIndex(i)) continue;
      if(ExtPositionInfo.Symbol() != _Symbol) continue;
      long posMagic = ExtPositionInfo.Magic();
      if(!IsAnyAlgoFamilyCompositeMagic(posMagic)) continue;
      ExtTrade.SetExpertMagicNumber((ulong)posMagic);
      ExtTrade.PositionClose(ExtPositionInfo.Ticket());
      ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   }
}

//+------------------------------------------------------------------+
//| Full composite magic as COMPOSITE_MAGIC_STRING_LEN-char string for B_TradeLog filename; "" if not algo-family magic. |
//+------------------------------------------------------------------+
string GetMagicStrForLogFilename(long magic)
{
   if(IsAnyAlgoFamilyCompositeMagic(magic))
      return MagicNumberToFixedWidthString(magic);
   return "";
}

//+------------------------------------------------------------------+
//| Build B_TradeLog filename: YYYY.MM.DD_B_TradeLog_<fixed-width composite string>.csv |
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
         FileWrite(fileHandle1, IntegerToString(i), levels[i].baseName, DoubleToString(levels[i].price, _Digits),
                   IntegerToString(levels[i].count), IntegerToString(levels[i].approxContactCount),
                   DoubleToString(levels[i].dailyBias, 0), IntegerToString(levels[i].bounceCount), tagStr, catsStr);
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

//| magicStrForLogFilename: full composite magic as a string → B_TradeLog_<date>_<that>.csv (see GetMagicStrForLogFilename). |
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
   const double one_lot = 65000.0;
   const int    max_trade_count_aim_for = 15;
   const double requiredPln = g_global_base_trade_size * one_lot * (double)max_trade_count_aim_for;
   if(requiredPln > ACCOUNT_SIZE_PLN_FOR_TRADE_SIZE)
      FatalError(StringFormat(
         "Base trade size vs account (PLN): g_global_base_trade_size=%s × one_lot=%.0f × max_trade_count_aim_for=%d = %s exceeds ACCOUNT_SIZE_PLN_FOR_TRADE_SIZE=%s. Lower g_global_base_trade_size or raise ACCOUNT_SIZE_PLN_FOR_TRADE_SIZE.",
         DoubleToString(g_global_base_trade_size, 4), one_lot, max_trade_count_aim_for,
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

   Print("Level Logger EA initialized.");
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);

   ValidateMagicCompositionOnInit();

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
   RefreshAlgoFamilyWeekPerspective(TimeCurrent());

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
//| Compute 10 gap-fill frequency percentages: pcts[i] = 100 * counts[i] / daysWith (or 0 if daysWith==0). counts[] and pcts[] must have size >= 10. |
//+------------------------------------------------------------------+
void ComputeGapFillFreqs(int daysWith, int &counts[], double &pcts[])
{
   ArrayResize(pcts, 10);
   if(daysWith <= 0)
   {
      for(int i = 0; i < 10; i++) pcts[i] = 0.0;
      return;
   }
   double denom = (double)daysWith;
   for(int i = 0; i < 10; i++)
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

   string dateStrStat = TimeToString(g_m1DayStart, TIME_DATE);
   string dayStatLogName = dateStrStat + "_dayPriceStat_log.csv";
   if(dailyEODlog_DayStat)
   {
   int fileHandleDay = FileOpen(dayStatLogName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandleDay != INVALID_HANDLE)
   {
      FileWrite(fileHandleDay, "date", "hasGapDown", "hasGapUp", "RTHopen", "PD_RTH_Close", "gap_fill_pc", "gapDiff", "rthHigh", "rthLow", "ONH", "ONL", "ONH_t_RTH", "ONL_t_RTH", "ONboth_t_RTH", "spreadHighestSeen", "spreadLowestSeen", "PD_trend");
      FileWrite(fileHandleDay, dateStrStat, (dayStat_hasGapDown ? "true" : "false"), (dayStat_hasGapUp ? "true" : "false"), DoubleToString(rthOpen, _Digits), DoubleToString(pdc, _Digits), DoubleToString(dayStat_openGapDown_percentageFill, 2), DoubleToString(dayStat_gapDiff, _Digits), DoubleToString(dayStat_rthHigh, _Digits), DoubleToString(dayStat_rthLow, _Digits), DoubleToString(dayStat_onHigh, _Digits), DoubleToString(dayStat_onLow, _Digits), (dayStat_ONH_t_RTH ? "true" : "false"), (dayStat_ONL_t_RTH ? "true" : "false"), (dayStat_ONboth_t_RTH ? "true" : "false"), DoubleToString(dayStat_spreadHighestSeen, 2), DoubleToString(dayStat_spreadLowestSeen, 2), GetPDtrendString());
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
//| Write dayStat summary CSV (totalDays, daysWithGapDown, daysWithoutGapDown). Recalculate at 21:35 so current day is included. |
//+------------------------------------------------------------------+
void WriteDayStatSummaryCsv()
{
   int fileHandleSum = FileOpen("dayPriceStat_summaryLog.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fileHandleSum != INVALID_HANDLE)
   {
      double avgFillD = (dayStat_daysWithGapDown > 0) ? dayStat_gapDown_fillPercentSum / (double)dayStat_daysWithGapDown : 0.0;
      int countsD[10];
      countsD[0] = dayStat_daysWithGapDown_20fill;  countsD[1] = dayStat_daysWithGapDown_25fill;  countsD[2] = dayStat_daysWithGapDown_30fill;
      countsD[3] = dayStat_daysWithGapDown_33fill;  countsD[4] = dayStat_daysWithGapDown_40fill;  countsD[5] = dayStat_daysWithGapDown_50fill;
      countsD[6] = dayStat_daysWithGapDown_60fill;  countsD[7] = dayStat_daysWithGapDown_75fill;  countsD[8] = dayStat_daysWithGapDown_90fill;
      countsD[9] = dayStat_daysWithGapDown_100fill;
      double pctsD[];
      ComputeGapFillFreqs(dayStat_daysWithGapDown, countsD, pctsD);

      double avgFillU = (dayStat_daysWithGapUp > 0) ? dayStat_gapUp_fillPercentSum / (double)dayStat_daysWithGapUp : 0.0;
      int countsU[10];
      countsU[0] = dayStat_daysWithGapUp_20fill;  countsU[1] = dayStat_daysWithGapUp_25fill;  countsU[2] = dayStat_daysWithGapUp_30fill;
      countsU[3] = dayStat_daysWithGapUp_33fill;  countsU[4] = dayStat_daysWithGapUp_40fill;  countsU[5] = dayStat_daysWithGapUp_50fill;
      countsU[6] = dayStat_daysWithGapUp_60fill;  countsU[7] = dayStat_daysWithGapUp_75fill;  countsU[8] = dayStat_daysWithGapUp_90fill;
      countsU[9] = dayStat_daysWithGapUp_100fill;
      double pctsU[];
      ComputeGapFillFreqs(dayStat_daysWithGapUp, countsU, pctsU);

      double daysONH_t_freq = (dayStat_totalDays > 0) ? (100.0 * (double)dayStat_daysONH_tested / (double)dayStat_totalDays) : 0.0;
      double daysONL_t_freq = (dayStat_totalDays > 0) ? (100.0 * (double)dayStat_daysONL_tested / (double)dayStat_totalDays) : 0.0;
      double daysONHL_t = (dayStat_totalDays > 0) ? (100.0 * (double)dayStat_daysONboth_tested / (double)dayStat_totalDays) : 0.0;
      FileWrite(fileHandleSum, "days", "daysGapD", "daysNoGD", "gapD_avg_fill", "gD_20_f", "gD_25_f", "gD_30_f", "gD_33_f", "gD_40_f", "gD_50_f", "gD_60_f", "gD_75_f", "gD_90_f", "gD_100_f",
                "daysGapUp", "daysNoGU", "gapU_avg_fill", "gU_20_f", "gU_25_f", "gU_30_f", "gU_33_f", "gU_40_f", "gU_50_f", "gU_60_f", "gU_75_f", "gU_90_f", "gU_100_f",
                "daysONH_t_freq", "daysONL_t_freq", "daysONHL_t");
      FileWrite(fileHandleSum, IntegerToString(dayStat_totalDays), IntegerToString(dayStat_daysWithGapDown), IntegerToString(dayStat_daysWithoutGapDown), DoubleToString(avgFillD, 2),
                DoubleToString(pctsD[0], 2), DoubleToString(pctsD[1], 2), DoubleToString(pctsD[2], 2), DoubleToString(pctsD[3], 2), DoubleToString(pctsD[4], 2), DoubleToString(pctsD[5], 2), DoubleToString(pctsD[6], 2), DoubleToString(pctsD[7], 2), DoubleToString(pctsD[8], 2), DoubleToString(pctsD[9], 2),
                IntegerToString(dayStat_daysWithGapUp), IntegerToString(dayStat_daysWithoutGapUp), DoubleToString(avgFillU, 2),
                DoubleToString(pctsU[0], 2), DoubleToString(pctsU[1], 2), DoubleToString(pctsU[2], 2), DoubleToString(pctsU[3], 2), DoubleToString(pctsU[4], 2), DoubleToString(pctsU[5], 2), DoubleToString(pctsU[6], 2), DoubleToString(pctsU[7], 2), DoubleToString(pctsU[8], 2), DoubleToString(pctsU[9], 2),
                DoubleToString(daysONH_t_freq, 2), DoubleToString(daysONL_t_freq, 2), DoubleToString(daysONHL_t, 2));
      FileClose(fileHandleSum);
   }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   if(current_candle_time != 0)
      FinalizeCurrentCandle();

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
   g_lastTimer1Time = TimeCurrent();
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

   FalgoUpdateOpenTradeTelemetryEachSecond();

   RunFalgoTradePipeline();

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
      OnTimer_FinishDurationStatsAndMaybeLog2130(onTimerT0);
      return;
   }

   g_lastBarTime = barNowM1;

   CloseAnyOpenTrade_atEOD_2158_falgo();   // algo family magics; EOD write at 21:58 sees OUT

   // Pull static context for today before refresh so PDC is available when building levels (single UpdateDayM1AndLevelsExpanded per bar)
   datetime dayStartForContext = g_lastTimer1Time - (g_lastTimer1Time % 86400);
   if(g_staticMarketContextPulledForDate != dayStartForContext)
   {
      UpdateStaticMarketContext(dayStartForContext);
      g_staticMarketContextPulledForDate = dayStartForContext;
   }

   // Refresh day M1 and levels first; then set closed-candle OHLC from same source (or terminal fallback)
   UpdateDayM1AndLevelsExpanded();
   FalgoTryLogGatesForClosedMinute();
   SetClosedCandleOHLCFromDayM1OrTerminal();

   FinalizeCurrentCandle();

   // --- ON and RTH session high/low so far at each bar k (bars 0..k). Fresh each candle; log reads from g_*AtBar[k].
   UpdateONandRTHHighLowSoFarAtBar();

   // --- IB high/low (15:30–16:30 or 14:30–15:30); unknown before IB ends.
   UpdateIBHighLowAtBar();

   // --- Gap fill so far: % of gap filled by rthLowSoFar (gap up) or rthHighSoFar (gap down); unknown before RTH open.
   UpdateGapFillSoFarAtBar();

   // --- Trade results for the day (deals IN/OUT paired by magic; available globally)
   if(InpLoadTradeResultsFromHistory)
   {
      UpdateTradeResultsForDay();
      FalgoEnrichAllTradeResultsLevelTpSl();
   }
   else
   {
      g_tradeResultsCount = 0;
      g_dealCount = 0;
   }

   // --- Per-candle day progress (trades closed by each candle close time)
   UpdateDayProgress();
   UpdateFalgoDayTradeCounts();
   UpdatePullingHistoryAlgoFamilyAccountBarStats();

   // --- Per-level trade stats (trade results whose level matches levelPrice; ON/RTH by endTime)
   UpdateLevelTradeStats();

   // --- Static market context: pulled before UpdateDayM1AndLevelsExpanded(); set ONopen from first candle whenever we have bars.
   if(g_barsInDay > 0)
   {
      // g_m1Rates is oldest-first: [0]=first bar of day
      g_ONopen = g_m1Rates[0].open;
   }
   
   if(InpEODLogging)
   {
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


         string logNameAlgoFamily = dateStr + "_testing_pullinghistory_algofamily.csv";
         if(dailyEODlog_PullingHistoryAlgoFamily && !FileIsExist(logNameAlgoFamily))
         {
            UpdateTradeResultsForDay();
            FalgoEnrichAllTradeResultsLevelTpSl();
            UpdateDayProgress();
            UpdatePullingHistoryAlgoFamilyAccountBarStats();
            int fileHandleAlgoFamily = FileOpen(logNameAlgoFamily, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
            if(fileHandleAlgoFamily == INVALID_HANDLE)
               FatalError("OnTimer: could not open " + logNameAlgoFamily);
            FileWrite(fileHandleAlgoFamily, "time", "O", "H", "L", "C",
                     "ClosestWeeklyLevelToCClose",
                     "closestPriceProximity",
                     "sessionRangeMidpoint",
                     "currentCandle_AvgOf_OHLCnumbers",
                     "cleanOHLC_streak_startTime", "cleanOHLC_streak_count", "cleanOHLC_streak_avgOfOHLC",
                     "ClosestWeeklyLevel_anchorAbove_within_cleanOHLC_streak", "ClosestWeeklyLevel_anchorAbove_time",
                     "ClosestWeeklyLevel_anchorBelow_within_cleanOHLC_streak", "ClosestWeeklyLevel_anchorBelow_time",
                     "ClosestWeeklyLevel_BounceCount_today",
                     StringFormat("recentBounceCount%d", g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO11)].recentBounceCountToday_Minutes),
                     "ClosestWeeklyLevel_CeilingCount_today",
                     StringFormat("recentCeilingCount%d", g_algos[AlgoSlotIndexByAlgoId(MAGIC_ALGO12)].recentCeilingCountToday_Minutes),
                     "ClosestWeeklyLevel_contactCount_today",
                     "accOpenTradeNowBool", "accOpenTradeTime", "accLastClosedTradeTime",
                     "dayWinRate", "dayTradesCount", "dayPointsSum", "dayProfitSum");
            for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
            {
               PullingHistoryAlgoFamilyBarSnap snap = g_pullingHistoryAlgoFamilyAtBar[barIdx];
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
               FileWrite(fileHandleAlgoFamily, TimeToString(g_m1Rates[barIdx].time, TIME_DATE|TIME_MINUTES),
                     DoubleToString(g_m1Rates[barIdx].open, _Digits), DoubleToString(g_m1Rates[barIdx].high, _Digits), DoubleToString(g_m1Rates[barIdx].low, _Digits), DoubleToString(g_m1Rates[barIdx].close, _Digits),
                     DoubleToString(snap.closestWeeklyLevelToCClose, _Digits),
                     DoubleToString(snap.closestPriceProximity, _Digits),
                     (g_sessionRangeMidpointAtBar[barIdx].hasValue ? DoubleToString(g_sessionRangeMidpointAtBar[barIdx].value, 2) : "unknown"),
                     DoubleToString(snap.currentCandle_AvgOf_OHLCnumbers, _Digits),
                     streakStartStr, IntegerToString(snap.cleanOHLC_streak_count), DoubleToString(snap.cleanOHLC_streak_avgOfOHLC, _Digits),
                     DoubleToString(snap.closestWeeklyLevel_anchorAbove_within_cleanOHLC_streak, _Digits), anchorAboveTimeStr,
                     DoubleToString(snap.closestWeeklyLevel_anchorBelow_within_cleanOHLC_streak, _Digits), anchorBelowTimeStr,
                     IntegerToString(snap.closestWeeklyLevel_BounceCount_today),
                     IntegerToString(snap.closestWeeklyLevel_BounceCount_recent),
                     IntegerToString(snap.closestWeeklyLevel_CeilingCount_today),
                     IntegerToString(snap.closestWeeklyLevel_CeilingCount_recent),
                     IntegerToString(snap.closestWeeklyLevel_contactCount_today),
                     (snap.accOpenTradeNowBool ? "true" : "false"), accOpenTimeStr, accLastClosedStr,
                     DoubleToString(snap.dayWinRate * 100.0, 0), IntegerToString(snap.dayTradesCount), DoubleToString(snap.dayPointsSum, _Digits), DoubleToString(snap.dayProfitSum, 2));
            }
            FileClose(fileHandleAlgoFamily);
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

         // Per-level files (only once per file per day; if missing, write again). MT5 CSV with headers.
         const int HighestDiffRange_Log = 15;  // window in bars for both HighestDiffUp and HighestDiffDown in logs
         if(dailyEODlog_TestinglevelsPlus)
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
   }
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

   // Day stat: once after 21:30 candle, set dayStat_hasGapDown (RTH open < PD RTH close) and write dayPriceStat_log + dayPriceStat_summaryLog
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
            levels[i].bounceCount = 0;
            levels[i].candlesPassedSinceLastBounce = 0;
            levels[i].ceilingCount = 0;
            levels[i].candlesPassedSinceLastCeiling = 0;
            levels[i].contactFromBelow = false;
            levels[i].recoverCount = 0;
            levels[i].consecutiveRecoverCandles = 0;
            levels[i].candlesBreakLevelCount = 0;
            levels[i].lastCandleInContact = false;
            levels[i].count = 0;
            levels[i].approxContactCount = 0;

            if(levels[i].logRawEv_fileHandle != INVALID_HANDLE)
               FileClose(levels[i].logRawEv_fileHandle);

            if(dailySpamLog_Arawevents)
            {
            string araFile = StringFormat("%s-%s_week%s_-%s_Arawevents.csv", 
                                         dateStr, levels[i].baseName, dateStr, DoubleToString(lvl,_Digits));

            int fileHandleAra = FileOpen(araFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
            if(fileHandleAra == INVALID_HANDLE)
               fileHandleAra = FileOpen(araFile, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
            if(fileHandleAra == INVALID_HANDLE)
               FatalError("FinalizeCurrentCandle: could not open " + araFile);
            FileSeek(fileHandleAra, 0, SEEK_END);
            if(FileTell(fileHandleAra) == 0)
               FileWrite(fileHandleAra, "time", "level", "O", "H", "low", "C", "diff_CloseToLevel", "DayBias", "Contact", "ContactCount", "BounceCount", "CandlesPassedSinceLastBounce", "CeilingCount", "CandlesPassedSinceLastCeiling", "CandlesBreakLevelCount", "RecoverCount");
            levels[i].logRawEv_fileHandle = fileHandleAra;
            }
            else
               levels[i].logRawEv_fileHandle = INVALID_HANDLE;
         }

         // OHLC values
         double diffCloseToLevel = candle_close - lvl;
         double diffOpenToLevel = candle_open - lvl;
         double diffHighToLevel = candle_high - lvl;
         double diffLowToLevel = candle_low - lvl;

         bool physicallyTouched = (candle_low <= lvl && candle_high >= lvl);
         bool proximityTouched  = (MathAbs(diffOpenToLevel) <= ProximityThreshold || 
                                   MathAbs(diffHighToLevel) <= ProximityThreshold || 
                                   MathAbs(diffLowToLevel) <= ProximityThreshold || 
                                   MathAbs(diffCloseToLevel) <= ProximityThreshold);
         bool in_contact        = physicallyTouched || proximityTouched;

         if(physicallyTouched) levels[i].count++;
         if(in_contact) levels[i].approxContactCount++;

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

         // --- Contact-from-below episode (for ceiling)
         if(in_contact && candle_close < lvl)
            levels[i].contactFromBelow = true;
         if(in_contact && candle_close >= lvl)
            levels[i].contactFromBelow = false;

         // --- Bounce: first no-contact candle fully above level after contact (always above; no bias)
         bool bounceCandle = (!in_contact && candle_low > lvl);
         if(levels[i].lastCandleInContact && bounceCandle)
         {
            levels[i].bounceCount++;
            levels[i].candlesPassedSinceLastBounce = 0;
            levels[i].contactFromBelow = false;
         }
         else if(levels[i].bounceCount > 0)
            levels[i].candlesPassedSinceLastBounce++;

         // --- Ceiling: first no-contact candle fully below level after in-contact-from-below
         bool ceilingCandle = (!in_contact && candle_high < lvl);
         if(levels[i].lastCandleInContact && ceilingCandle && levels[i].contactFromBelow)
         {
            levels[i].ceilingCount++;
            levels[i].candlesPassedSinceLastCeiling = 0;
            levels[i].contactFromBelow = false;
         }
         else if(levels[i].ceilingCount > 0)
            levels[i].candlesPassedSinceLastCeiling++;

         if(!in_contact && !levels[i].lastCandleInContact)
            levels[i].contactFromBelow = false;

         levels[i].lastCandleInContact = in_contact;

         // --- Write Arawevents (CSV row)
         if(levels[i].logRawEv_fileHandle != INVALID_HANDLE)
         {
            FileWrite(levels[i].logRawEv_fileHandle,
               TimeToString(current_candle_time, TIME_DATE|TIME_MINUTES),
               DoubleToString(lvl, _Digits),
               DoubleToString(candle_open, _Digits), DoubleToString(candle_high, _Digits), DoubleToString(candle_low, _Digits), DoubleToString(candle_close, _Digits),
               DoubleToString(diffCloseToLevel, _Digits),
               (levels[i].dailyBias > 0 ? "bias_long" : "bias_short"),
               (in_contact ? "in_contact" : "no_contact"),
               IntegerToString(levels[i].approxContactCount),
               IntegerToString(levels[i].bounceCount),
               IntegerToString(levels[i].candlesPassedSinceLastBounce),
               IntegerToString(levels[i].ceilingCount),
               IntegerToString(levels[i].candlesPassedSinceLastCeiling),
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