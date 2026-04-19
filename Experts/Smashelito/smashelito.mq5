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
// COMPOSITE MAGIC: Never write the full numeric composite (entire fixed-width variant long) inside comments; use g_trade[row] or stage-2 subset disptch keys (slot1|slot2|slot3 → e.g. 10201). Cursor/IDE rules: repo .cursor/rules or project AGENTS.md.


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
input int      BounceCandlesRequired = 1; // for bounce count logic
int      Max_OrdersPerMagic = 1; // max open positions + pending orders with this magic (same full magic number)
double   InpLotSize           = 0.01; // lot size for rulesets
int      HourForDailySummary   = 21;   // hour (server time) when daily summary is written (timer/server time)
int      MinuteForDailySummary = 30;   // minute of the hour for summary trigger
bool     InpEODLogging = true;  // if true: at 21:58-22:00 write EOD logs (summaryZ_tradeResults, summary_tradeResults_all_days, pullinghistory, levels, etc.)
//--- Log to file: set false to disable that log (optimization)
//    finalLog_ = one file across whole run; dailyEODlog_ = daily once at EOD; dailySpamLog_ = daily and frequent
bool     dailyEODlog_PullingHistory   = true;  // (date)_testing_pullinghistory.csv
bool     dailyEODlog_DailySummary     = true;  // Day_activeLevels, account, orders, deals (WriteDailySummary)
bool     dailyEODlog_EodTradesSummary = false;  // (date)_summary_EOD_tradesSummary1line.csv
bool     finalLog_SummaryTrades1line  = false;  // summary_tradesSummary1line.csv
bool     finalLog_SummaryTradesPerTrade = false;  // summary_tradesSummary_perTrade.csv (one row per magic)
bool     dailyEODlog_TradeResultsCsv  = true;  // summaryZ_tradeResults_ALL_Day + summary_tradeResults_all_days
bool     dailyEODlog_TestinglevelsPlus = true;  // (date)_testinglevelsplus_(level)_(tag).csv per level
bool     dailyEODlog_BreakCheck       = true;  // levels_breakCheck files + summary
bool     dailySpamLog_LivePrice       = true;  // (date)_testing_liveprice.csv 21:35-21:37
bool     dailyEODlog_DayStat          = true;  // (date)_dayPriceStat_log.csv (TryLogDayStatForCurrentDay)
bool     finalLog_DayStatSummary      = true;  // dayPriceStat_summaryLog.csv (WriteDayStatSummaryCsv)
bool     finalLog_TradeLog            = false; // B_TradeLog_<composite per variant>.csv (WriteTradeLog)
bool     dailySpamLog_AllCandles      = true;  // (date)-AllCandlesLog_Timer1.csv
bool     finalLog_FirstLastCandle     = true;  // InpSessionFirstLastCandleFile (OnDeinit)
bool     dailySpamLog_Arawevents      = false; // Arawevents CSV + level logRawEv (FinalizeCurrentCandle)
string   InpCalendarFile        = "calendar_2026_dots.csv";  // CSV in Terminal/Common/Files: date (YYYY.MM.DD),dayofmonth,dayofweek,opex,qopex
string   InpLevelsFile          = "levelsinfo_zeFinal.csv";  // CSV in Terminal/Common/Files: start,end,levelPrice,categories,tag
double   InpBreakCheckMaxDistPoints = 9.0;  // levels_breakCheck: first candle beyond this distance in price (and all newer) excluded
bool     maemfe_testing             = false; // if true: all trades use TP=SL=3000.0 and close any position open >20 min (OnTimer)
bool     babysit_global_flipper = true; // bookmark3. when true, OnTimer may run per-row SL babysit for positions whose variant has babysit_enabled

//--- Global base trade size: actual lot = base × (trade_size_percentage/100). Each ruleset has its own percentage (10,20,...,100).
// base lot; 100% trade type = this full size; 50% = half, for example 0.1, tradesize 10 is 0.01, size 30 is 0.03
// for example, 0.5, and specific trade is 30%, would mean position 0.15, 60% = 0.30
// for example, 1.2, and specific trade is 30%, would mean position 0.36, 50% = 0.60
// profit factor danego trade jest stały przy jego różnych trade size, ale profit factor całego runu zmieni się bo zmieniają się proporcje absolutnego zysku
double   g_global_base_trade_size = 0.1; // bookmark9 basetradesize

//--- Composite magic digit 1 (pending order kind) is per row: g_trade[i].tradeDirectionCategory (MAGIC_TRADE_*). Other digits: see VariantTrade.

//--- Trades: TRADE_VARIANT_COUNT rows in g_trade[] — defaults assigned in SyncTradeVariantsFromInputs() (g_trade[i].field = …).
//    tradeDirectionCategory → slot 1; tradeTypeId → slot 2; ruleSubsetId → slot 3; sessionPdCategory → slot 4; see BuildBetterMagicNumber layout. levelProximityFocus: TRADE_LEVEL_FOCUS_BELOW | ABOVE | BOTH.
//    bannedRanges: no '|' inside string.
// bookmark4 tradecount
#define TRADE_VARIANT_COUNT 26000
#define TRADE_LEVEL_FOCUS_BELOW  1
#define TRADE_LEVEL_FOCUS_ABOVE  2
#define TRADE_LEVEL_FOCUS_BOTH   3
// Stage-2 pending: fullMagic is routed by PendingRuleSubsetPassesForFullMagic (see OnInit validation).
// Pipeline: g_trade[i].fullMagic precomputed in OnInit; BuildMagicForVariant reads cache; copies through maybe-stage-1 → maybe-stage-2 → place.

struct VariantTrade
{
   bool   enabled;
   int    tradeDirectionCategory; // 1..4 → composite magic digit 1 (MAGIC_TRADE_LONG … MAGIC_TRADE_SHORT_REVERSED)
   int    tradeTypeId;
   int    ruleSubsetId;          // 1..99 → composite slot 3 (%02d)
   int    sessionPdCategory;     // 1..4 → composite slot 4 (MAGIC_IS_ON_AND_PD_GREEN … MAGIC_IS_RTH_AND_PD_RED)
   int    tradeSizePct;
   double tpPoints;                // whole 1..99 only; composite slot 8 (%02d)
   double slPoints;                // whole 1..99 only; composite slot 9 (%02d)
   double livePriceDiffTrigger;  // composite slot 5: %02d tenths (0.1..9.9), live-price proximity vs level for pipeline gate
   double levelOffsetPoints;       // composite slot 6: %02d tenths (0.1..9.9), pending offset in PointSized points
   int    levelProximityFocus;   // TRADE_LEVEL_FOCUS_BELOW | ABOVE | BOTH
   bool   babysit_enabled;      // if true and babysit_global_flipper, OnTimer may tighten SL for this variant's positions
   int    babysitStart_minute;   // minutes after position open before babysit runs
   string bannedRanges;
   long   fullMagic;             // composite magic; filled by RebuildVariantFullMagicCache() after row fields are valid (OnInit), not rebuilt on timer
};
// Populated at startup by SyncTradeVariantsFromInputs() — edit assignments there.
VariantTrade g_trade[TRADE_VARIANT_COUNT];

//--- OnTimer pending pipeline (see RunTimerPendingNearLevelsPipeline):
//    A   prerequisites (levels, bars, nearest levels to bid)
//    B–C one pass per g_trade[] row: proximity + maybe stage 1 gates → maybeStage1Candidates (stage-2 subset rules not run yet)
//    D–E: subset rules (maybe stage 2); on pass → maybeStage2Candidates (anchor + SL/TP).
//    F   PlacePendingFromMagic (+ log)
struct PendingMaybeCandidate
{
   // Populated after maybe stage 1 (common gates); stage-2 subset rules not run yet.
   int    variantIdx;       // index into g_trade[]
   long   fullMagic;        // BuildMagicForVariant(variantIdx) at stage B–C; carried unchanged through later stages
   double nearestLevelBelowBid;
   double nearestLevelAboveBid;
   int    levelIndexBelow;
   int    levelIndexAbove;
   int    lastBarIndexToday; // kLast = g_barsInDay-1
   double pendingOffsetPoints; // g_trade[].levelOffsetPoints (PointSized units → PendingOrderPricesForDirection)
};
struct PendingMaybeStage2Candidate
{
   // Populated only after stage-2 subset rule passes (maybe stage 2 pass); F sends the order.
   int    variantIdx;
   long   fullMagic;        // copy from maybe-stage-1 candidate (same value as BuildMagicForVariant(variantIdx))
   double anchorLevelPrice;  // level used for pending anchor (focus / BOTH logic)
   double pendingOffsetPoints; // PointSized points (from stage-1)
   double slPointsInput;       // g_trade[].slPoints
   double tpPointsInput;       // g_trade[].tpPoints
};
// Resolved level for stage-2 subset rules (focus logic lives here once, not in each subset).
struct EntryLevelCtx
{
   bool   ok;
   double levelPx;
   int    levelIdx;
};
// RunTimerPendingNearLevelsPipeline() scratch only — file scope avoids MQL5 ~2 MB *stack* limit on locals and avoids per-tick ArrayResize.
PendingMaybeCandidate       g_pendingPipelineStage1[TRADE_VARIANT_COUNT];
PendingMaybeStage2Candidate g_pendingPipelineStage2[TRADE_VARIANT_COUNT];
//--- Per-variant config (index = g_trade[] row): useLevel/usePrice reserved; bannedRangesStr for time bans.
struct TradeTypeConfig
{
   bool   useLevel;        // false = variant does not use level
   bool   usePrice;        // false = no price/level distance check
   string bannedRangesStr; // "startH,startM,endH,endM;..." e.g. "0,0,2,59;20,0,23,59"; empty = no time filter
};
TradeTypeConfig g_tradeConfig[TRADE_VARIANT_COUNT];  // index by variant row 0..TRADE_VARIANT_COUNT-1
#define MAX_BANNED_RANGES 20
int g_bannedRangesBuffer[][4];       // dynamic, filled by ParseBannedRanges (OnInit rebuild path)
int g_bannedRangesCount = 0;
// Per-variant banned intervals as minutes since midnight [0..1439]; filled by RebuildAllVariantBannedRangesCache (OnInit; re-call if bannedRangesStr changes at runtime).
struct BannedRangeMinutes { int startMin; int endMin; };
BannedRangeMinutes g_variantBannedRanges[TRADE_VARIANT_COUNT][MAX_BANNED_RANGES];
int g_variantBannedRangeCount[TRADE_VARIANT_COUNT];

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
};
Level levels[];

//--- Variant composite magic + B_TradeLog (per-magic filename)
const long DEFAULT_ORDER_MAGIC = 47001; // restore CTrade magic when not using a variant composite magic
// Entry: s ≈ spread in price. Buy limit at L=level+off fills when Ask=L; sell stop at L−s triggers when Bid=L−s (same tick if Ask−Bid=s). Sell limit at S=level−off fills when Bid=S; buy stop at S+s triggers when Ask=S+s. SL/TP = PointSized points from order price — no exit spread bump.
const double g_pendingTriggerSymmetrySpread = 0.7;

// Composite magic — digit 1: pending order kind (g_trade[i].tradeDirectionCategory; see MAGIC_TRADE_* / PlacePendingFromMagic).
#define MAGIC_TRADE_LONG            1   // buy limit
#define MAGIC_TRADE_SHORT           2   // sell limit
#define MAGIC_TRADE_LONG_REVERSED   3   // sell stop at (level+off)−s — pairs buy limit Ask fill; see PlaceSellStopAtLevel
#define MAGIC_TRADE_SHORT_REVERSED  4   // buy stop at (level−off)+s — pairs sell limit Bid fill; see PlaceBuyStopAtLevel
// MAGIC_IS_*: session (ON vs RTH) + prior-day colour — encoded in composite slot 4 (see BuildBetterMagicNumber banner).
#define MAGIC_IS_ON_AND_PD_GREEN   1
#define MAGIC_IS_ON_AND_PD_RED     2
#define MAGIC_IS_RTH_AND_PD_GREEN  3
#define MAGIC_IS_RTH_AND_PD_RED    4
// Composite layout: direction, tradeType %02d, ruleSubset %02d, sessionPd (1 digit), … — see BuildBetterMagicNumber banner.
//--- Fixed layout for string decode (must match BuildBetterMagicNumber StringFormat exactly; indices 0-based)
#define COMPOSITE_MAGIC_STRING_LEN   17
// Fixed-width magic string: INDEX_* = start char for StringSubstr; LENGTH_* = how many chars.
#define COMPOSITE_MAGIC_INDEX_DIRECTION      0
#define COMPOSITE_MAGIC_LENGTH_DIRECTION     1
#define COMPOSITE_MAGIC_INDEX_TRADE_TYPE     1
#define COMPOSITE_MAGIC_LENGTH_TRADE_TYPE    2
#define COMPOSITE_MAGIC_INDEX_RULE_SUBSET    3
#define COMPOSITE_MAGIC_LENGTH_RULE_SUBSET   2
#define COMPOSITE_MAGIC_INDEX_SESSION_PD     5
#define COMPOSITE_MAGIC_LENGTH_SESSION_PD    1
#define COMPOSITE_MAGIC_INDEX_LIVE_TRIGGER   6
#define COMPOSITE_MAGIC_LENGTH_LIVE_TRIGGER  2
#define COMPOSITE_MAGIC_INDEX_LEVEL_OFFSET   8
#define COMPOSITE_MAGIC_LENGTH_LEVEL_OFFSET  2
#define COMPOSITE_MAGIC_INDEX_BABYSIT        10
#define COMPOSITE_MAGIC_LENGTH_BABYSIT       3
#define COMPOSITE_MAGIC_INDEX_TP_POINTS        13
#define COMPOSITE_MAGIC_LENGTH_TP_POINTS       2
#define COMPOSITE_MAGIC_INDEX_SL_POINTS        15
#define COMPOSITE_MAGIC_LENGTH_SL_POINTS       2

struct TradeKey
{
   int direction;
   int tradeType;
   int subset;           // rule subset %02d (composite slot 3)
   int sessionPd;        // MAGIC_IS_* 1..4 (composite slot 4)
   int triggerTenths;    // 1..99 from %02d (tenths; max 9.9)
   int offsetTenths;
   int babysitEncoded;
   int tpPointsEncoded;    // 1..99 whole points (magic slots 8–9)
   int slPointsEncoded;
};

CTrade ExtTrade;
COrderInfo ExtOrderInfo;
CPositionInfo ExtPositionInfo;
CDealInfo ExtDealInfo;

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

//--- summary_tradesSummary1line: accumulated across all EOD days (+= each EOD when we add that day)
int      g_summaryTrades_dayTradesCount = 0;
int      g_summaryTrades_dayWins = 0;
double   g_summaryTrades_dayPointsSum = 0.0;
double   g_summaryTrades_dayProfitSum = 0.0;
int      g_summaryTrades_ONtradeCount = 0;
int      g_summaryTrades_ONwins = 0;
double   g_summaryTrades_ONpointsSum = 0.0;
double   g_summaryTrades_ONprofitSum = 0.0;
int      g_summaryTrades_RTHtradeCount = 0;
int      g_summaryTrades_RTHwins = 0;
double   g_summaryTrades_RTHpointsSum = 0.0;
double   g_summaryTrades_RTHprofitSum = 0.0;
datetime g_summaryTrades_lastAddedDayStart = 0;  // avoid adding same day twice

#define MAX_PER_TRADE_MAGICS 7777 // Does not block orders. It only limits how many magics get per-magic summary rows in that reporting path. Execution does not go through this table.

struct PerTradeSummary
{
   long   magic;
   string datesList;     // comma-separated list of dates that had trades (YYYY.MM.DD)
   int    dayTradesCount;
   int    dayWins;
   double dayPointsSum;
   double dayProfitSum;
   int    ONtradeCount;
   int    ONwins;
   double ONpointsSum;
   double ONprofitSum;
   int    RTHtradeCount;
   int    RTHwins;
   double RTHpointsSum;
   double RTHprofitSum;
};
PerTradeSummary g_perTradeSummaries[MAX_PER_TRADE_MAGICS];
int g_perTradeSummariesCount = 0;

// Returns index in g_perTradeSummaries for composite magic key; adds new entry if not found (or -1 if table full).
int FindOrAddPerTradeMagic(long compositeMagicKey)
{
   for(int summaryIdx = 0; summaryIdx < g_perTradeSummariesCount; summaryIdx++)
      if(g_perTradeSummaries[summaryIdx].magic == compositeMagicKey)
         return summaryIdx;
   if(g_perTradeSummariesCount >= MAX_PER_TRADE_MAGICS)
      return -1;
   int newIdx = g_perTradeSummariesCount++;
   g_perTradeSummaries[newIdx].magic = compositeMagicKey;
   g_perTradeSummaries[newIdx].datesList = "";
   g_perTradeSummaries[newIdx].dayTradesCount = 0;
   g_perTradeSummaries[newIdx].dayWins = 0;
   g_perTradeSummaries[newIdx].dayPointsSum = 0.0;
   g_perTradeSummaries[newIdx].dayProfitSum = 0.0;
   g_perTradeSummaries[newIdx].ONtradeCount = 0;
   g_perTradeSummaries[newIdx].ONwins = 0;
   g_perTradeSummaries[newIdx].ONpointsSum = 0.0;
   g_perTradeSummaries[newIdx].ONprofitSum = 0.0;
   g_perTradeSummaries[newIdx].RTHtradeCount = 0;
   g_perTradeSummaries[newIdx].RTHwins = 0;
   g_perTradeSummaries[newIdx].RTHpointsSum = 0.0;
   g_perTradeSummaries[newIdx].RTHprofitSum = 0.0;
   return newIdx;
}

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
   string session;        // ON|RTH|sleep from startTime (same logic as candle session)
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
//| Session for candle time: ON / RTH / sleep. On daylight-savings desync dates use 14:30–21:00 for RTH; else 15:30–22:00. |
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
//| Reference points above/below trade open price at trade open time. Skips refs that are "unknown". Fills outAbove and outBelow with semicolon-separated ref names. |
//+------------------------------------------------------------------+
void GetReferencePointsAboveBelow(datetime tradeOpenTime, double tradePrice, string &outAbove, string &outBelow)
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

   double v = 0.0;
   if(g_staticMarketContext.PDOpreviousDayRTHOpen > 0.0) { v = g_staticMarketContext.PDOpreviousDayRTHOpen; if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "PDO"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "PDO"; }
   if(g_staticMarketContext.PDHpreviousDayHigh > 0.0) { v = g_staticMarketContext.PDHpreviousDayHigh; if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "PDH"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "PDH"; }
   if(g_staticMarketContext.PDLpreviousDayLow > 0.0) { v = g_staticMarketContext.PDLpreviousDayLow; if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "PDL"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "PDL"; }
   if(g_staticMarketContext.PDCpreviousDayRTHClose > 0.0) { v = g_staticMarketContext.PDCpreviousDayRTHClose; if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "PDC"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "PDC"; }
   if(g_ONhighSoFarAtBar[barIdx].hasValue) { v = g_ONhighSoFarAtBar[barIdx].value; if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "ONH"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "ONH"; }
   if(g_ONlowSoFarAtBar[barIdx].hasValue) { v = g_ONlowSoFarAtBar[barIdx].value; if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "ONL"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "ONL"; }
   if(GetRthHighSoFarAtBar(barIdx, dayStart, dateStr, v)) { if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "RTHH"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "RTHH"; }
   if(GetRthLowSoFarAtBar(barIdx, dayStart, dateStr, v)) { if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "RTHL"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "RTHL"; }
   if(GetIBlowAtBar(barIdx, v)) { if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "IBL"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "IBL"; }
   if(GetIBhighAtBar(barIdx, v)) { if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "IBH"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "IBH"; }
   if(g_dayHighSoFarAtBar[barIdx].hasValue) { v = g_dayHighSoFarAtBar[barIdx].value; if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "dayHighSoFar"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "dayHighSoFar"; }
   if(g_dayLowSoFarAtBar[barIdx].hasValue) { v = g_dayLowSoFarAtBar[barIdx].value; if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "dayLowSoFar"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "dayLowSoFar"; }
   if(g_sessionRangeMidpointAtBar[barIdx].hasValue) { v = g_sessionRangeMidpointAtBar[barIdx].value; if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "midpoint"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "midpoint"; }
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
//| can split level/tp/sl (first 3 tokens after '$' removed). Level is full price; tp/sl/entry use mod-100 tails. Optional " b<n>" when g_trade[].babysit_enabled. Magic on DEAL_MAGIC / ORDER_MAGIC. Length validated vs MT5_ORDER_COMMENT_MAX_LEN. |
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
         tradeResult.session    = GetSessionForCandleTime(tradeResult.startTime);
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
//| Copy ParseBannedRanges output into g_variantBannedRanges[variantIdx] (minutes since midnight). |
//+------------------------------------------------------------------+
void FillVariantBannedRangesMinutesFromParsedString(const int variantIdx, const string s)
{
   g_variantBannedRangeCount[variantIdx] = 0;
   ParseBannedRanges(s);
   int n = g_bannedRangesCount;
   if(n > MAX_BANNED_RANGES)
      n = MAX_BANNED_RANGES;
   for(int i = 0; i < n; i++)
   {
      g_variantBannedRanges[variantIdx][i].startMin = g_bannedRangesBuffer[i][0] * 60 + g_bannedRangesBuffer[i][1];
      g_variantBannedRanges[variantIdx][i].endMin   = g_bannedRangesBuffer[i][2] * 60 + g_bannedRangesBuffer[i][3];
   }
   g_variantBannedRangeCount[variantIdx] = n;
}

//+------------------------------------------------------------------+
//| After g_tradeConfig[].bannedRangesStr is set (OnInit or if you change bans at runtime). |
//+------------------------------------------------------------------+
void RebuildAllVariantBannedRangesCache()
{
   for(int v = 0; v < TRADE_VARIANT_COUNT; v++)
      FillVariantBannedRangesMinutesFromParsedString(v, g_tradeConfig[v].bannedRangesStr);
}

//+------------------------------------------------------------------+
//| Day-of-week suffix for magic: 0 when level has no "daily" in tags; 0..6 (Mon..Sun) when "daily". |
//| Reserved for future level-scoped magic suffixes (variant magic uses BuildMagicForVariant(variantIdx) only). |
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
//| TP/SL in magic: whole points 1..99 only (no 12.5) — PointSized display units. |
//+------------------------------------------------------------------+
int EncodeMagicTpSlWholePoints(double points, string ctxLabel)
{
   if(points < 1.0 || points > 99.0)
      FatalError(StringFormat("%s: points must be 1..99, got %s", ctxLabel, DoubleToString(points, 4)));
   double r = MathRound(points);
   if(MathAbs(points - r) > 1e-5)
      FatalError(StringFormat("%s: points must be a whole integer (e.g. 12), got %s", ctxLabel, DoubleToString(points, 4)));
   return (int)r;
}

//+------------------------------------------------------------------+
//| Babysit tail %03d for composite magic: 700 = off (numeric 700); 801..899 = on (800 + minute, minute 01..99). |
//+------------------------------------------------------------------+
int EncodeBabysitMagicThreeDigits(bool babysitEnabled, int babysitStartMinute)
{
   if(!babysitEnabled)
      return 700;
   if(babysitStartMinute < 1 || babysitStartMinute > 99)
      FatalError(StringFormat("EncodeBabysitMagicThreeDigits: when babysit enabled, minute must be 1..99, got %d", babysitStartMinute));
   return 800 + babysitStartMinute;
}

//+------------------------------------------------------------------+
//| Composite magic — 17 decimal digits concatenated (no | in stored value). Bookmark0. |
//| Layout (width = repeat slot index; not example values): 1|22|33|4|55|66||777|88|99 — 17 digits; “||” is doc-only (not in stored magic). |
//| Slot 1 (1 digit) — g_trade[].tradeDirectionCategory / PlacePendingFromMagic (MAGIC_TRADE_*), must be 1..4: |
//|   1 = MAGIC_TRADE_LONG           → buy limit pending. |
//|   2 = MAGIC_TRADE_SHORT          → sell limit pending. |
//|   3 = MAGIC_TRADE_LONG_REVERSED  → sell stop at (level+off)−s, same instant as buy limit at level+off (Bid vs Ask). |
//|   4 = MAGIC_TRADE_SHORT_REVERSED → buy stop at (level−off)+s, same instant as sell limit at level−off. |
//| Slot 2 (22): tradeTypeId as %02d, 01..99 (variant row id / config grouping). |
//| Slot 3 (33): ruleSubsetId as %02d, 01..99 (stage-2 subset disptch with slot 1+2 → BuildStage2SubsetHandlerKeyFromFullMagic). |
//| Slot 4 (4) — one digit: g_trade[].sessionPdCategory (MAGIC_IS_*), must be 1..4 — session band vs prior-day colour: |
//|   1 = MAGIC_IS_ON_AND_PD_GREEN   → ON session, PD green. |
//|   2 = MAGIC_IS_ON_AND_PD_RED     → ON session, PD red. |
//|   3 = MAGIC_IS_RTH_AND_PD_GREEN  → RTH session, PD green. |
//|   4 = MAGIC_IS_RTH_AND_PD_RED    → RTH session, PD red. |
//| Slot 5 (55): live proximity — %02d tenths via EncodeMagicTwoDigitTenths (0.1..9.9 point distance gate). |
//| Slot 6 (66): level offset points — %02d tenths via EncodeMagicTwoDigitTenths (0.1..9.9 PointSized points). |
//| Slot 7 (777) — babysit %03d via EncodeBabysitMagicThreeDigits; off vs on (hundreds digit 7 vs 8): |
//|   babysit_enabled false → stored numeric 700 → string "700" (off; hundreds digit 7). |
//|   babysit_enabled true  → 800 + babysitStart_minute (minute 01..99) → "801".."899" (on; hundreds digit 8). |
//| Slot 8 (88) — take-profit distance as %02d via EncodeMagicTpSlWholePoints: whole points only, 1..99 (no half). |
//|   Encoded value is the rounded integer point count (e.g. 12.0 → "12" → field "12" zero-padded to width 2). |
//| Slot 9 (99): SL whole points %02d, 01..99 (same rules as slot 8; EncodeMagicTpSlWholePoints). |
//| Result length = COMPOSITE_MAGIC_STRING_LEN (AssertCompositeMagicDecimalWidthOrFatal). |
//+------------------------------------------------------------------+
long BuildBetterMagicNumber(int tradeDirectionCategory, int tradeTypeId, int ruleSubsetId, int sessionPdCategory,
                            double livePriceDiffTrigger, double levelOffsetValue,
                            bool babysitEnabled, int babysitStartMinute, double tpPoints, double slPoints)
{
   if(tradeDirectionCategory < 1 || tradeDirectionCategory > 4)
      FatalError(StringFormat("BuildBetterMagicNumber: tradeDirectionCategory must be 1..4 (long/short/longRev/shortRev), got %d", tradeDirectionCategory));
   if(tradeTypeId < 1 || tradeTypeId > 99)
      FatalError(StringFormat("BuildBetterMagicNumber: tradeTypeId must be 1..99, got %d", tradeTypeId));
   if(ruleSubsetId < 1 || ruleSubsetId > 99)
      FatalError(StringFormat("BuildBetterMagicNumber: ruleSubsetId must be 1..99, got %d", ruleSubsetId));
   if(sessionPdCategory < 1 || sessionPdCategory > 4)
      FatalError(StringFormat("BuildBetterMagicNumber: sessionPdCategory must be 1..4 (MAGIC_IS_ON_AND_PD_GREEN … MAGIC_IS_RTH_AND_PD_RED), got %d", sessionPdCategory));
   int triLive = EncodeMagicTwoDigitTenths(livePriceDiffTrigger);
   int triLvl  = EncodeMagicTwoDigitTenths(levelOffsetValue);
   int bab = EncodeBabysitMagicThreeDigits(babysitEnabled, babysitStartMinute);
   int tpEnc = EncodeMagicTpSlWholePoints(tpPoints, "BuildBetterMagicNumber tpPoints");
   int slEnc = EncodeMagicTpSlWholePoints(slPoints, "BuildBetterMagicNumber slPoints");
   string s = StringFormat("%d%02d%02d%d%02d%02d%03d%02d%02d", tradeDirectionCategory, tradeTypeId, ruleSubsetId, sessionPdCategory, triLive, triLvl, bab, tpEnc, slEnc);
   if(StringLen(s) != COMPOSITE_MAGIC_STRING_LEN)
      FatalError(StringFormat("BuildBetterMagicNumber: internal error, string len %d != COMPOSITE_MAGIC_STRING_LEN %d", StringLen(s), COMPOSITE_MAGIC_STRING_LEN));
   return (long)StringToInteger(s);
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
//| Decode fixed-width composite magic string into fields (single parse path). |
//+------------------------------------------------------------------+
TradeKey ParseCompositeMagic(long magic)
{
   string s = MagicNumberToFixedWidthString(magic);
   TradeKey k;
   k.direction = (int)StringToInteger(StringSubstr(s, COMPOSITE_MAGIC_INDEX_DIRECTION, COMPOSITE_MAGIC_LENGTH_DIRECTION));
   k.tradeType = (int)StringToInteger(StringSubstr(s, COMPOSITE_MAGIC_INDEX_TRADE_TYPE, COMPOSITE_MAGIC_LENGTH_TRADE_TYPE));
   k.subset = (int)StringToInteger(StringSubstr(s, COMPOSITE_MAGIC_INDEX_RULE_SUBSET, COMPOSITE_MAGIC_LENGTH_RULE_SUBSET));
   k.sessionPd = (int)StringToInteger(StringSubstr(s, COMPOSITE_MAGIC_INDEX_SESSION_PD, COMPOSITE_MAGIC_LENGTH_SESSION_PD));
   k.triggerTenths = (int)StringToInteger(StringSubstr(s, COMPOSITE_MAGIC_INDEX_LIVE_TRIGGER, COMPOSITE_MAGIC_LENGTH_LIVE_TRIGGER));
   k.offsetTenths = (int)StringToInteger(StringSubstr(s, COMPOSITE_MAGIC_INDEX_LEVEL_OFFSET, COMPOSITE_MAGIC_LENGTH_LEVEL_OFFSET));
   k.babysitEncoded = (int)StringToInteger(StringSubstr(s, COMPOSITE_MAGIC_INDEX_BABYSIT, COMPOSITE_MAGIC_LENGTH_BABYSIT));
   k.tpPointsEncoded = (int)StringToInteger(StringSubstr(s, COMPOSITE_MAGIC_INDEX_TP_POINTS, COMPOSITE_MAGIC_LENGTH_TP_POINTS));
   k.slPointsEncoded = (int)StringToInteger(StringSubstr(s, COMPOSITE_MAGIC_INDEX_SL_POINTS, COMPOSITE_MAGIC_LENGTH_SL_POINTS));
   return k;
}

//+------------------------------------------------------------------+
//| Composite magic slot 1 — tradeDirectionCategory (1 digit, MAGIC_TRADE_*). |
//+------------------------------------------------------------------+
int CompositeMagicExtractSlot1TradeDirection(const long magic)
{
   string s = MagicNumberToFixedWidthString(magic);
   return (int)StringToInteger(StringSubstr(s, COMPOSITE_MAGIC_INDEX_DIRECTION, COMPOSITE_MAGIC_LENGTH_DIRECTION));
}

//+------------------------------------------------------------------+
//| Composite magic slot 2 — tradeTypeId (%02d). |
//+------------------------------------------------------------------+
int CompositeMagicExtractSlot2TradeTypeId(const long magic)
{
   string s = MagicNumberToFixedWidthString(magic);
   return (int)StringToInteger(StringSubstr(s, COMPOSITE_MAGIC_INDEX_TRADE_TYPE, COMPOSITE_MAGIC_LENGTH_TRADE_TYPE));
}

//+------------------------------------------------------------------+
//| Composite magic slot 3 — ruleSubsetId (%02d). |
//+------------------------------------------------------------------+
int CompositeMagicExtractSlot3RuleSubsetId(const long magic)
{
   string s = MagicNumberToFixedWidthString(magic);
   return (int)StringToInteger(StringSubstr(s, COMPOSITE_MAGIC_INDEX_RULE_SUBSET, COMPOSITE_MAGIC_LENGTH_RULE_SUBSET));
}

//+------------------------------------------------------------------+
//| Stage-2 subset disptch key: slot1×10000 + slot2×100 + slot3 (e.g. 1,02,01 → 10201). |
//| Same fields as CompositeMagicExtractSlot* / ParseCompositeMagic (single parse here). |
//+------------------------------------------------------------------+
int BuildStage2SubsetHandlerKeyFromFullMagic(const long fullMagic)
{
   TradeKey k = ParseCompositeMagic(fullMagic);
   return k.direction * 10000 + k.tradeType * 100 + k.subset;
}

//+------------------------------------------------------------------+
//| Trade variant defaults — edit here only (no InpTradeN_* globals). Called before validate. |
//+------------------------------------------------------------------+
void SyncTradeVariantsFromInputs() // bookmark1tradebegin
{  



// encoding input magic: 10345440037000606
g_trade[0].enabled                  = true;
g_trade[0].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[0].tradeTypeId              = 3;
g_trade[0].ruleSubsetId             = 45;
g_trade[0].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[0].tradeSizePct             = 100;
g_trade[0].tpPoints                 = 6.0;
g_trade[0].slPoints                 = 6.0;
g_trade[0].livePriceDiffTrigger     = 4.0;
g_trade[0].levelOffsetPoints        = 0.3;
g_trade[0].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[0].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[0].babysit_enabled          = false;
g_trade[0].babysitStart_minute      = 0;

// encoding input magic: 11229240157000606
g_trade[1].enabled                  = true;
g_trade[1].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[1].tradeTypeId              = 12;
g_trade[1].ruleSubsetId             = 29;
g_trade[1].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[1].tradeSizePct             = 100;
g_trade[1].tpPoints                 = 6.0;
g_trade[1].slPoints                 = 6.0;
g_trade[1].livePriceDiffTrigger     = 4.0;
g_trade[1].levelOffsetPoints        = 1.5;
g_trade[1].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[1].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[1].babysit_enabled          = false;
g_trade[1].babysitStart_minute      = 0;

// encoding input magic: 10353140157000606
g_trade[2].enabled                  = true;
g_trade[2].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[2].tradeTypeId              = 3;
g_trade[2].ruleSubsetId             = 53;
g_trade[2].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[2].tradeSizePct             = 100;
g_trade[2].tpPoints                 = 6.0;
g_trade[2].slPoints                 = 6.0;
g_trade[2].livePriceDiffTrigger     = 4.0;
g_trade[2].levelOffsetPoints        = 1.5;
g_trade[2].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[2].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[2].babysit_enabled          = false;
g_trade[2].babysitStart_minute      = 0;

// encoding input magic: 10239340157000606
g_trade[3].enabled                  = true;
g_trade[3].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[3].tradeTypeId              = 2;
g_trade[3].ruleSubsetId             = 39;
g_trade[3].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[3].tradeSizePct             = 100;
g_trade[3].tpPoints                 = 6.0;
g_trade[3].slPoints                 = 6.0;
g_trade[3].livePriceDiffTrigger     = 4.0;
g_trade[3].levelOffsetPoints        = 1.5;
g_trade[3].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[3].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[3].babysit_enabled          = false;
g_trade[3].babysitStart_minute      = 0;

// encoding input magic: 10338440037000606
g_trade[4].enabled                  = true;
g_trade[4].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[4].tradeTypeId              = 3;
g_trade[4].ruleSubsetId             = 38;
g_trade[4].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[4].tradeSizePct             = 100;
g_trade[4].tpPoints                 = 6.0;
g_trade[4].slPoints                 = 6.0;
g_trade[4].livePriceDiffTrigger     = 4.0;
g_trade[4].levelOffsetPoints        = 0.3;
g_trade[4].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[4].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[4].babysit_enabled          = false;
g_trade[4].babysitStart_minute      = 0;

// encoding input magic: 10394140157000606
g_trade[5].enabled                  = true;
g_trade[5].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[5].tradeTypeId              = 3;
g_trade[5].ruleSubsetId             = 94;
g_trade[5].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[5].tradeSizePct             = 100;
g_trade[5].tpPoints                 = 6.0;
g_trade[5].slPoints                 = 6.0;
g_trade[5].livePriceDiffTrigger     = 4.0;
g_trade[5].levelOffsetPoints        = 1.5;
g_trade[5].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[5].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[5].babysit_enabled          = false;
g_trade[5].babysitStart_minute      = 0;

// encoding input magic: 10269140107000606
g_trade[6].enabled                  = true;
g_trade[6].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[6].tradeTypeId              = 2;
g_trade[6].ruleSubsetId             = 69;
g_trade[6].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[6].tradeSizePct             = 100;
g_trade[6].tpPoints                 = 6.0;
g_trade[6].slPoints                 = 6.0;
g_trade[6].livePriceDiffTrigger     = 4.0;
g_trade[6].levelOffsetPoints        = 1.0;
g_trade[6].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[6].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[6].babysit_enabled          = false;
g_trade[6].babysitStart_minute      = 0;

// encoding input magic: 10335440057000606
g_trade[7].enabled                  = true;
g_trade[7].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[7].tradeTypeId              = 3;
g_trade[7].ruleSubsetId             = 35;
g_trade[7].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[7].tradeSizePct             = 100;
g_trade[7].tpPoints                 = 6.0;
g_trade[7].slPoints                 = 6.0;
g_trade[7].livePriceDiffTrigger     = 4.0;
g_trade[7].levelOffsetPoints        = 0.5;
g_trade[7].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[7].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[7].babysit_enabled          = false;
g_trade[7].babysitStart_minute      = 0;

// encoding input magic: 11229240107000606
g_trade[8].enabled                  = true;
g_trade[8].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[8].tradeTypeId              = 12;
g_trade[8].ruleSubsetId             = 29;
g_trade[8].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[8].tradeSizePct             = 100;
g_trade[8].tpPoints                 = 6.0;
g_trade[8].slPoints                 = 6.0;
g_trade[8].livePriceDiffTrigger     = 4.0;
g_trade[8].levelOffsetPoints        = 1.0;
g_trade[8].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[8].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[8].babysit_enabled          = false;
g_trade[8].babysitStart_minute      = 0;

// encoding input magic: 10306340037000606
g_trade[9].enabled                  = true;
g_trade[9].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[9].tradeTypeId              = 3;
g_trade[9].ruleSubsetId             = 6;
g_trade[9].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[9].tradeSizePct             = 100;
g_trade[9].tpPoints                 = 6.0;
g_trade[9].slPoints                 = 6.0;
g_trade[9].livePriceDiffTrigger     = 4.0;
g_trade[9].levelOffsetPoints        = 0.3;
g_trade[9].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[9].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[9].babysit_enabled          = false;
g_trade[9].babysitStart_minute      = 0;

// encoding input magic: 10316440037000606
g_trade[10].enabled                  = true;
g_trade[10].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[10].tradeTypeId              = 3;
g_trade[10].ruleSubsetId             = 16;
g_trade[10].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[10].tradeSizePct             = 100;
g_trade[10].tpPoints                 = 6.0;
g_trade[10].slPoints                 = 6.0;
g_trade[10].livePriceDiffTrigger     = 4.0;
g_trade[10].levelOffsetPoints        = 0.3;
g_trade[10].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[10].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[10].babysit_enabled          = false;
g_trade[10].babysitStart_minute      = 0;

// encoding input magic: 10353240057000606
g_trade[11].enabled                  = true;
g_trade[11].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[11].tradeTypeId              = 3;
g_trade[11].ruleSubsetId             = 53;
g_trade[11].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[11].tradeSizePct             = 100;
g_trade[11].tpPoints                 = 6.0;
g_trade[11].slPoints                 = 6.0;
g_trade[11].livePriceDiffTrigger     = 4.0;
g_trade[11].levelOffsetPoints        = 0.5;
g_trade[11].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[11].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[11].babysit_enabled          = false;
g_trade[11].babysitStart_minute      = 0;

// encoding input magic: 11229240037000606
g_trade[12].enabled                  = true;
g_trade[12].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[12].tradeTypeId              = 12;
g_trade[12].ruleSubsetId             = 29;
g_trade[12].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[12].tradeSizePct             = 100;
g_trade[12].tpPoints                 = 6.0;
g_trade[12].slPoints                 = 6.0;
g_trade[12].livePriceDiffTrigger     = 4.0;
g_trade[12].levelOffsetPoints        = 0.3;
g_trade[12].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[12].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[12].babysit_enabled          = false;
g_trade[12].babysitStart_minute      = 0;

// encoding input magic: 10311440157000606
g_trade[13].enabled                  = true;
g_trade[13].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[13].tradeTypeId              = 3;
g_trade[13].ruleSubsetId             = 11;
g_trade[13].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[13].tradeSizePct             = 100;
g_trade[13].tpPoints                 = 6.0;
g_trade[13].slPoints                 = 6.0;
g_trade[13].livePriceDiffTrigger     = 4.0;
g_trade[13].levelOffsetPoints        = 1.5;
g_trade[13].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[13].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[13].babysit_enabled          = false;
g_trade[13].babysitStart_minute      = 0;

// encoding input magic: 10348440037000606
g_trade[14].enabled                  = true;
g_trade[14].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[14].tradeTypeId              = 3;
g_trade[14].ruleSubsetId             = 48;
g_trade[14].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[14].tradeSizePct             = 100;
g_trade[14].tpPoints                 = 6.0;
g_trade[14].slPoints                 = 6.0;
g_trade[14].livePriceDiffTrigger     = 4.0;
g_trade[14].levelOffsetPoints        = 0.3;
g_trade[14].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[14].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[14].babysit_enabled          = false;
g_trade[14].babysitStart_minute      = 0;

// encoding input magic: 10337440157000606
g_trade[15].enabled                  = true;
g_trade[15].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[15].tradeTypeId              = 3;
g_trade[15].ruleSubsetId             = 37;
g_trade[15].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[15].tradeSizePct             = 100;
g_trade[15].tpPoints                 = 6.0;
g_trade[15].slPoints                 = 6.0;
g_trade[15].livePriceDiffTrigger     = 4.0;
g_trade[15].levelOffsetPoints        = 1.5;
g_trade[15].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[15].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[15].babysit_enabled          = false;
g_trade[15].babysitStart_minute      = 0;

// encoding input magic: 10312440157000606
g_trade[16].enabled                  = true;
g_trade[16].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[16].tradeTypeId              = 3;
g_trade[16].ruleSubsetId             = 12;
g_trade[16].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[16].tradeSizePct             = 100;
g_trade[16].tpPoints                 = 6.0;
g_trade[16].slPoints                 = 6.0;
g_trade[16].livePriceDiffTrigger     = 4.0;
g_trade[16].levelOffsetPoints        = 1.5;
g_trade[16].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[16].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[16].babysit_enabled          = false;
g_trade[16].babysitStart_minute      = 0;

// encoding input magic: 10227440157000606
g_trade[17].enabled                  = true;
g_trade[17].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[17].tradeTypeId              = 2;
g_trade[17].ruleSubsetId             = 27;
g_trade[17].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[17].tradeSizePct             = 100;
g_trade[17].tpPoints                 = 6.0;
g_trade[17].slPoints                 = 6.0;
g_trade[17].livePriceDiffTrigger     = 4.0;
g_trade[17].levelOffsetPoints        = 1.5;
g_trade[17].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[17].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[17].babysit_enabled          = false;
g_trade[17].babysitStart_minute      = 0;

// encoding input magic: 11220240157000606
g_trade[18].enabled                  = true;
g_trade[18].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[18].tradeTypeId              = 12;
g_trade[18].ruleSubsetId             = 20;
g_trade[18].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[18].tradeSizePct             = 100;
g_trade[18].tpPoints                 = 6.0;
g_trade[18].slPoints                 = 6.0;
g_trade[18].livePriceDiffTrigger     = 4.0;
g_trade[18].levelOffsetPoints        = 1.5;
g_trade[18].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[18].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[18].babysit_enabled          = false;
g_trade[18].babysitStart_minute      = 0;

// encoding input magic: 10341240107000606
g_trade[19].enabled                  = true;
g_trade[19].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[19].tradeTypeId              = 3;
g_trade[19].ruleSubsetId             = 41;
g_trade[19].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[19].tradeSizePct             = 100;
g_trade[19].tpPoints                 = 6.0;
g_trade[19].slPoints                 = 6.0;
g_trade[19].livePriceDiffTrigger     = 4.0;
g_trade[19].levelOffsetPoints        = 1.0;
g_trade[19].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[19].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[19].babysit_enabled          = false;
g_trade[19].babysitStart_minute      = 0;

// encoding input magic: 10237440057000606
g_trade[20].enabled                  = true;
g_trade[20].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[20].tradeTypeId              = 2;
g_trade[20].ruleSubsetId             = 37;
g_trade[20].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[20].tradeSizePct             = 100;
g_trade[20].tpPoints                 = 6.0;
g_trade[20].slPoints                 = 6.0;
g_trade[20].livePriceDiffTrigger     = 4.0;
g_trade[20].levelOffsetPoints        = 0.5;
g_trade[20].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[20].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[20].babysit_enabled          = false;
g_trade[20].babysitStart_minute      = 0;

// encoding input magic: 10331440157000606
g_trade[21].enabled                  = true;
g_trade[21].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[21].tradeTypeId              = 3;
g_trade[21].ruleSubsetId             = 31;
g_trade[21].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[21].tradeSizePct             = 100;
g_trade[21].tpPoints                 = 6.0;
g_trade[21].slPoints                 = 6.0;
g_trade[21].livePriceDiffTrigger     = 4.0;
g_trade[21].levelOffsetPoints        = 1.5;
g_trade[21].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[21].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[21].babysit_enabled          = false;
g_trade[21].babysitStart_minute      = 0;

// encoding input magic: 10269140157000606
g_trade[22].enabled                  = true;
g_trade[22].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[22].tradeTypeId              = 2;
g_trade[22].ruleSubsetId             = 69;
g_trade[22].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[22].tradeSizePct             = 100;
g_trade[22].tpPoints                 = 6.0;
g_trade[22].slPoints                 = 6.0;
g_trade[22].livePriceDiffTrigger     = 4.0;
g_trade[22].levelOffsetPoints        = 1.5;
g_trade[22].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[22].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[22].babysit_enabled          = false;
g_trade[22].babysitStart_minute      = 0;

// encoding input magic: 10267440157000606
g_trade[23].enabled                  = true;
g_trade[23].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[23].tradeTypeId              = 2;
g_trade[23].ruleSubsetId             = 67;
g_trade[23].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[23].tradeSizePct             = 100;
g_trade[23].tpPoints                 = 6.0;
g_trade[23].slPoints                 = 6.0;
g_trade[23].livePriceDiffTrigger     = 4.0;
g_trade[23].levelOffsetPoints        = 1.5;
g_trade[23].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[23].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[23].babysit_enabled          = false;
g_trade[23].babysitStart_minute      = 0;

// encoding input magic: 10304440107000606
g_trade[24].enabled                  = true;
g_trade[24].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[24].tradeTypeId              = 3;
g_trade[24].ruleSubsetId             = 4;
g_trade[24].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[24].tradeSizePct             = 100;
g_trade[24].tpPoints                 = 6.0;
g_trade[24].slPoints                 = 6.0;
g_trade[24].livePriceDiffTrigger     = 4.0;
g_trade[24].levelOffsetPoints        = 1.0;
g_trade[24].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[24].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[24].babysit_enabled          = false;
g_trade[24].babysitStart_minute      = 0;

// encoding input magic: 10219440037000606
g_trade[25].enabled                  = true;
g_trade[25].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[25].tradeTypeId              = 2;
g_trade[25].ruleSubsetId             = 19;
g_trade[25].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[25].tradeSizePct             = 100;
g_trade[25].tpPoints                 = 6.0;
g_trade[25].slPoints                 = 6.0;
g_trade[25].livePriceDiffTrigger     = 4.0;
g_trade[25].levelOffsetPoints        = 0.3;
g_trade[25].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[25].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[25].babysit_enabled          = false;
g_trade[25].babysitStart_minute      = 0;

// encoding input magic: 10313440107000606
g_trade[26].enabled                  = true;
g_trade[26].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[26].tradeTypeId              = 3;
g_trade[26].ruleSubsetId             = 13;
g_trade[26].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[26].tradeSizePct             = 100;
g_trade[26].tpPoints                 = 6.0;
g_trade[26].slPoints                 = 6.0;
g_trade[26].livePriceDiffTrigger     = 4.0;
g_trade[26].levelOffsetPoints        = 1.0;
g_trade[26].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[26].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[26].babysit_enabled          = false;
g_trade[26].babysitStart_minute      = 0;

// encoding input magic: 10334340107000606
g_trade[27].enabled                  = true;
g_trade[27].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[27].tradeTypeId              = 3;
g_trade[27].ruleSubsetId             = 34;
g_trade[27].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[27].tradeSizePct             = 100;
g_trade[27].tpPoints                 = 6.0;
g_trade[27].slPoints                 = 6.0;
g_trade[27].livePriceDiffTrigger     = 4.0;
g_trade[27].levelOffsetPoints        = 1.0;
g_trade[27].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[27].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[27].babysit_enabled          = false;
g_trade[27].babysitStart_minute      = 0;

// encoding input magic: 10311440107000606
g_trade[28].enabled                  = true;
g_trade[28].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[28].tradeTypeId              = 3;
g_trade[28].ruleSubsetId             = 11;
g_trade[28].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[28].tradeSizePct             = 100;
g_trade[28].tpPoints                 = 6.0;
g_trade[28].slPoints                 = 6.0;
g_trade[28].livePriceDiffTrigger     = 4.0;
g_trade[28].levelOffsetPoints        = 1.0;
g_trade[28].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[28].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[28].babysit_enabled          = false;
g_trade[28].babysitStart_minute      = 0;

// encoding input magic: 10386140157000606
g_trade[29].enabled                  = true;
g_trade[29].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[29].tradeTypeId              = 3;
g_trade[29].ruleSubsetId             = 86;
g_trade[29].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[29].tradeSizePct             = 100;
g_trade[29].tpPoints                 = 6.0;
g_trade[29].slPoints                 = 6.0;
g_trade[29].livePriceDiffTrigger     = 4.0;
g_trade[29].levelOffsetPoints        = 1.5;
g_trade[29].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[29].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[29].babysit_enabled          = false;
g_trade[29].babysitStart_minute      = 0;

// encoding input magic: 10341240037000606
g_trade[30].enabled                  = true;
g_trade[30].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[30].tradeTypeId              = 3;
g_trade[30].ruleSubsetId             = 41;
g_trade[30].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[30].tradeSizePct             = 100;
g_trade[30].tpPoints                 = 6.0;
g_trade[30].slPoints                 = 6.0;
g_trade[30].livePriceDiffTrigger     = 4.0;
g_trade[30].levelOffsetPoints        = 0.3;
g_trade[30].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[30].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[30].babysit_enabled          = false;
g_trade[30].babysitStart_minute      = 0;

// encoding input magic: 10232440037000606
g_trade[31].enabled                  = true;
g_trade[31].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[31].tradeTypeId              = 2;
g_trade[31].ruleSubsetId             = 32;
g_trade[31].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[31].tradeSizePct             = 100;
g_trade[31].tpPoints                 = 6.0;
g_trade[31].slPoints                 = 6.0;
g_trade[31].livePriceDiffTrigger     = 4.0;
g_trade[31].levelOffsetPoints        = 0.3;
g_trade[31].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[31].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[31].babysit_enabled          = false;
g_trade[31].babysitStart_minute      = 0;

// encoding input magic: 10291340157000606
g_trade[32].enabled                  = true;
g_trade[32].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[32].tradeTypeId              = 2;
g_trade[32].ruleSubsetId             = 91;
g_trade[32].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[32].tradeSizePct             = 100;
g_trade[32].tpPoints                 = 6.0;
g_trade[32].slPoints                 = 6.0;
g_trade[32].livePriceDiffTrigger     = 4.0;
g_trade[32].levelOffsetPoints        = 1.5;
g_trade[32].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[32].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[32].babysit_enabled          = false;
g_trade[32].babysitStart_minute      = 0;

// encoding input magic: 10330340037000606
g_trade[33].enabled                  = true;
g_trade[33].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[33].tradeTypeId              = 3;
g_trade[33].ruleSubsetId             = 30;
g_trade[33].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[33].tradeSizePct             = 100;
g_trade[33].tpPoints                 = 6.0;
g_trade[33].slPoints                 = 6.0;
g_trade[33].livePriceDiffTrigger     = 4.0;
g_trade[33].levelOffsetPoints        = 0.3;
g_trade[33].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[33].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[33].babysit_enabled          = false;
g_trade[33].babysitStart_minute      = 0;

// encoding input magic: 10237440037000606
g_trade[34].enabled                  = true;
g_trade[34].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[34].tradeTypeId              = 2;
g_trade[34].ruleSubsetId             = 37;
g_trade[34].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[34].tradeSizePct             = 100;
g_trade[34].tpPoints                 = 6.0;
g_trade[34].slPoints                 = 6.0;
g_trade[34].livePriceDiffTrigger     = 4.0;
g_trade[34].levelOffsetPoints        = 0.3;
g_trade[34].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[34].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[34].babysit_enabled          = false;
g_trade[34].babysitStart_minute      = 0;

// encoding input magic: 10242440157000606
g_trade[35].enabled                  = true;
g_trade[35].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[35].tradeTypeId              = 2;
g_trade[35].ruleSubsetId             = 42;
g_trade[35].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[35].tradeSizePct             = 100;
g_trade[35].tpPoints                 = 6.0;
g_trade[35].slPoints                 = 6.0;
g_trade[35].livePriceDiffTrigger     = 4.0;
g_trade[35].levelOffsetPoints        = 1.5;
g_trade[35].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[35].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[35].babysit_enabled          = false;
g_trade[35].babysitStart_minute      = 0;

// encoding input magic: 10344440107000606
g_trade[36].enabled                  = true;
g_trade[36].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[36].tradeTypeId              = 3;
g_trade[36].ruleSubsetId             = 44;
g_trade[36].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[36].tradeSizePct             = 100;
g_trade[36].tpPoints                 = 6.0;
g_trade[36].slPoints                 = 6.0;
g_trade[36].livePriceDiffTrigger     = 4.0;
g_trade[36].levelOffsetPoints        = 1.0;
g_trade[36].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[36].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[36].babysit_enabled          = false;
g_trade[36].babysitStart_minute      = 0;

// encoding input magic: 10220340107000606
g_trade[37].enabled                  = true;
g_trade[37].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[37].tradeTypeId              = 2;
g_trade[37].ruleSubsetId             = 20;
g_trade[37].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[37].tradeSizePct             = 100;
g_trade[37].tpPoints                 = 6.0;
g_trade[37].slPoints                 = 6.0;
g_trade[37].livePriceDiffTrigger     = 4.0;
g_trade[37].levelOffsetPoints        = 1.0;
g_trade[37].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[37].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[37].babysit_enabled          = false;
g_trade[37].babysitStart_minute      = 0;

// encoding input magic: 10335440107000606
g_trade[38].enabled                  = true;
g_trade[38].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[38].tradeTypeId              = 3;
g_trade[38].ruleSubsetId             = 35;
g_trade[38].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[38].tradeSizePct             = 100;
g_trade[38].tpPoints                 = 6.0;
g_trade[38].slPoints                 = 6.0;
g_trade[38].livePriceDiffTrigger     = 4.0;
g_trade[38].levelOffsetPoints        = 1.0;
g_trade[38].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[38].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[38].babysit_enabled          = false;
g_trade[38].babysitStart_minute      = 0;

// encoding input magic: 10209440037000606
g_trade[39].enabled                  = true;
g_trade[39].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[39].tradeTypeId              = 2;
g_trade[39].ruleSubsetId             = 9;
g_trade[39].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[39].tradeSizePct             = 100;
g_trade[39].tpPoints                 = 6.0;
g_trade[39].slPoints                 = 6.0;
g_trade[39].livePriceDiffTrigger     = 4.0;
g_trade[39].levelOffsetPoints        = 0.3;
g_trade[39].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[39].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[39].babysit_enabled          = false;
g_trade[39].babysitStart_minute      = 0;

// encoding input magic: 10281340107000606
g_trade[40].enabled                  = true;
g_trade[40].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[40].tradeTypeId              = 2;
g_trade[40].ruleSubsetId             = 81;
g_trade[40].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[40].tradeSizePct             = 100;
g_trade[40].tpPoints                 = 6.0;
g_trade[40].slPoints                 = 6.0;
g_trade[40].livePriceDiffTrigger     = 4.0;
g_trade[40].levelOffsetPoints        = 1.0;
g_trade[40].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[40].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[40].babysit_enabled          = false;
g_trade[40].babysitStart_minute      = 0;

// encoding input magic: 10306240157000606
g_trade[41].enabled                  = true;
g_trade[41].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[41].tradeTypeId              = 3;
g_trade[41].ruleSubsetId             = 6;
g_trade[41].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[41].tradeSizePct             = 100;
g_trade[41].tpPoints                 = 6.0;
g_trade[41].slPoints                 = 6.0;
g_trade[41].livePriceDiffTrigger     = 4.0;
g_trade[41].levelOffsetPoints        = 1.5;
g_trade[41].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[41].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[41].babysit_enabled          = false;
g_trade[41].babysitStart_minute      = 0;

// encoding input magic: 10220340157000606
g_trade[42].enabled                  = true;
g_trade[42].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[42].tradeTypeId              = 2;
g_trade[42].ruleSubsetId             = 20;
g_trade[42].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[42].tradeSizePct             = 100;
g_trade[42].tpPoints                 = 6.0;
g_trade[42].slPoints                 = 6.0;
g_trade[42].livePriceDiffTrigger     = 4.0;
g_trade[42].levelOffsetPoints        = 1.5;
g_trade[42].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[42].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[42].babysit_enabled          = false;
g_trade[42].babysitStart_minute      = 0;

// encoding input magic: 10310340157000606
g_trade[43].enabled                  = true;
g_trade[43].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[43].tradeTypeId              = 3;
g_trade[43].ruleSubsetId             = 10;
g_trade[43].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[43].tradeSizePct             = 100;
g_trade[43].tpPoints                 = 6.0;
g_trade[43].slPoints                 = 6.0;
g_trade[43].livePriceDiffTrigger     = 4.0;
g_trade[43].levelOffsetPoints        = 1.5;
g_trade[43].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[43].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[43].babysit_enabled          = false;
g_trade[43].babysitStart_minute      = 0;

// encoding input magic: 10335440037000606
g_trade[44].enabled                  = true;
g_trade[44].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[44].tradeTypeId              = 3;
g_trade[44].ruleSubsetId             = 35;
g_trade[44].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[44].tradeSizePct             = 100;
g_trade[44].tpPoints                 = 6.0;
g_trade[44].slPoints                 = 6.0;
g_trade[44].livePriceDiffTrigger     = 4.0;
g_trade[44].levelOffsetPoints        = 0.3;
g_trade[44].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[44].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[44].babysit_enabled          = false;
g_trade[44].babysitStart_minute      = 0;

// encoding input magic: 10314440037000606
g_trade[45].enabled                  = true;
g_trade[45].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[45].tradeTypeId              = 3;
g_trade[45].ruleSubsetId             = 14;
g_trade[45].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[45].tradeSizePct             = 100;
g_trade[45].tpPoints                 = 6.0;
g_trade[45].slPoints                 = 6.0;
g_trade[45].livePriceDiffTrigger     = 4.0;
g_trade[45].levelOffsetPoints        = 0.3;
g_trade[45].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[45].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[45].babysit_enabled          = false;
g_trade[45].babysitStart_minute      = 0;

// encoding input magic: 11214340037000606
g_trade[46].enabled                  = true;
g_trade[46].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[46].tradeTypeId              = 12;
g_trade[46].ruleSubsetId             = 14;
g_trade[46].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[46].tradeSizePct             = 100;
g_trade[46].tpPoints                 = 6.0;
g_trade[46].slPoints                 = 6.0;
g_trade[46].livePriceDiffTrigger     = 4.0;
g_trade[46].levelOffsetPoints        = 0.3;
g_trade[46].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[46].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[46].babysit_enabled          = false;
g_trade[46].babysitStart_minute      = 0;

// encoding input magic: 10339440157000606
g_trade[47].enabled                  = true;
g_trade[47].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[47].tradeTypeId              = 3;
g_trade[47].ruleSubsetId             = 39;
g_trade[47].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[47].tradeSizePct             = 100;
g_trade[47].tpPoints                 = 6.0;
g_trade[47].slPoints                 = 6.0;
g_trade[47].livePriceDiffTrigger     = 4.0;
g_trade[47].levelOffsetPoints        = 1.5;
g_trade[47].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[47].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[47].babysit_enabled          = false;
g_trade[47].babysitStart_minute      = 0;

// encoding input magic: 10306340057000606
g_trade[48].enabled                  = true;
g_trade[48].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[48].tradeTypeId              = 3;
g_trade[48].ruleSubsetId             = 6;
g_trade[48].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[48].tradeSizePct             = 100;
g_trade[48].tpPoints                 = 6.0;
g_trade[48].slPoints                 = 6.0;
g_trade[48].livePriceDiffTrigger     = 4.0;
g_trade[48].levelOffsetPoints        = 0.5;
g_trade[48].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[48].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[48].babysit_enabled          = false;
g_trade[48].babysitStart_minute      = 0;

// encoding input magic: 10264340157000606
g_trade[49].enabled                  = true;
g_trade[49].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[49].tradeTypeId              = 2;
g_trade[49].ruleSubsetId             = 64;
g_trade[49].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[49].tradeSizePct             = 100;
g_trade[49].tpPoints                 = 6.0;
g_trade[49].slPoints                 = 6.0;
g_trade[49].livePriceDiffTrigger     = 4.0;
g_trade[49].levelOffsetPoints        = 1.5;
g_trade[49].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[49].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[49].babysit_enabled          = false;
g_trade[49].babysitStart_minute      = 0;

// encoding input magic: 10315440157000606
g_trade[50].enabled                  = true;
g_trade[50].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[50].tradeTypeId              = 3;
g_trade[50].ruleSubsetId             = 15;
g_trade[50].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[50].tradeSizePct             = 100;
g_trade[50].tpPoints                 = 6.0;
g_trade[50].slPoints                 = 6.0;
g_trade[50].livePriceDiffTrigger     = 4.0;
g_trade[50].levelOffsetPoints        = 1.5;
g_trade[50].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[50].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[50].babysit_enabled          = false;
g_trade[50].babysitStart_minute      = 0;

// encoding input magic: 10377140157000606
g_trade[51].enabled                  = true;
g_trade[51].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[51].tradeTypeId              = 3;
g_trade[51].ruleSubsetId             = 77;
g_trade[51].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[51].tradeSizePct             = 100;
g_trade[51].tpPoints                 = 6.0;
g_trade[51].slPoints                 = 6.0;
g_trade[51].livePriceDiffTrigger     = 4.0;
g_trade[51].levelOffsetPoints        = 1.5;
g_trade[51].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[51].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[51].babysit_enabled          = false;
g_trade[51].babysitStart_minute      = 0;

// encoding input magic: 10205340037000606
g_trade[52].enabled                  = true;
g_trade[52].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[52].tradeTypeId              = 2;
g_trade[52].ruleSubsetId             = 5;
g_trade[52].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[52].tradeSizePct             = 100;
g_trade[52].tpPoints                 = 6.0;
g_trade[52].slPoints                 = 6.0;
g_trade[52].livePriceDiffTrigger     = 4.0;
g_trade[52].levelOffsetPoints        = 0.3;
g_trade[52].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[52].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[52].babysit_enabled          = false;
g_trade[52].babysitStart_minute      = 0;

// encoding input magic: 10279340057000606
g_trade[53].enabled                  = true;
g_trade[53].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[53].tradeTypeId              = 2;
g_trade[53].ruleSubsetId             = 79;
g_trade[53].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[53].tradeSizePct             = 100;
g_trade[53].tpPoints                 = 6.0;
g_trade[53].slPoints                 = 6.0;
g_trade[53].livePriceDiffTrigger     = 4.0;
g_trade[53].levelOffsetPoints        = 0.5;
g_trade[53].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[53].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[53].babysit_enabled          = false;
g_trade[53].babysitStart_minute      = 0;

// encoding input magic: 10302440107000606
g_trade[54].enabled                  = true;
g_trade[54].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[54].tradeTypeId              = 3;
g_trade[54].ruleSubsetId             = 2;
g_trade[54].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[54].tradeSizePct             = 100;
g_trade[54].tpPoints                 = 6.0;
g_trade[54].slPoints                 = 6.0;
g_trade[54].livePriceDiffTrigger     = 4.0;
g_trade[54].levelOffsetPoints        = 1.0;
g_trade[54].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[54].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[54].babysit_enabled          = false;
g_trade[54].babysitStart_minute      = 0;

// encoding input magic: 10233440157000606
g_trade[55].enabled                  = true;
g_trade[55].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[55].tradeTypeId              = 2;
g_trade[55].ruleSubsetId             = 33;
g_trade[55].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[55].tradeSizePct             = 100;
g_trade[55].tpPoints                 = 6.0;
g_trade[55].slPoints                 = 6.0;
g_trade[55].livePriceDiffTrigger     = 4.0;
g_trade[55].levelOffsetPoints        = 1.5;
g_trade[55].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[55].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[55].babysit_enabled          = false;
g_trade[55].babysitStart_minute      = 0;

// encoding input magic: 10345440107000606
g_trade[56].enabled                  = true;
g_trade[56].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[56].tradeTypeId              = 3;
g_trade[56].ruleSubsetId             = 45;
g_trade[56].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[56].tradeSizePct             = 100;
g_trade[56].tpPoints                 = 6.0;
g_trade[56].slPoints                 = 6.0;
g_trade[56].livePriceDiffTrigger     = 4.0;
g_trade[56].levelOffsetPoints        = 1.0;
g_trade[56].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[56].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[56].babysit_enabled          = false;
g_trade[56].babysitStart_minute      = 0;

// encoding input magic: 10282340107000606
g_trade[57].enabled                  = true;
g_trade[57].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[57].tradeTypeId              = 2;
g_trade[57].ruleSubsetId             = 82;
g_trade[57].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[57].tradeSizePct             = 100;
g_trade[57].tpPoints                 = 6.0;
g_trade[57].slPoints                 = 6.0;
g_trade[57].livePriceDiffTrigger     = 4.0;
g_trade[57].levelOffsetPoints        = 1.0;
g_trade[57].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[57].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[57].babysit_enabled          = false;
g_trade[57].babysitStart_minute      = 0;

// encoding input magic: 10243440157000606
g_trade[58].enabled                  = true;
g_trade[58].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[58].tradeTypeId              = 2;
g_trade[58].ruleSubsetId             = 43;
g_trade[58].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[58].tradeSizePct             = 100;
g_trade[58].tpPoints                 = 6.0;
g_trade[58].slPoints                 = 6.0;
g_trade[58].livePriceDiffTrigger     = 4.0;
g_trade[58].levelOffsetPoints        = 1.5;
g_trade[58].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[58].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[58].babysit_enabled          = false;
g_trade[58].babysitStart_minute      = 0;

// encoding input magic: 10248340107000606
g_trade[59].enabled                  = true;
g_trade[59].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[59].tradeTypeId              = 2;
g_trade[59].ruleSubsetId             = 48;
g_trade[59].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[59].tradeSizePct             = 100;
g_trade[59].tpPoints                 = 6.0;
g_trade[59].slPoints                 = 6.0;
g_trade[59].livePriceDiffTrigger     = 4.0;
g_trade[59].levelOffsetPoints        = 1.0;
g_trade[59].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[59].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[59].babysit_enabled          = false;
g_trade[59].babysitStart_minute      = 0;

// encoding input magic: 11210340057000606
g_trade[60].enabled                  = true;
g_trade[60].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[60].tradeTypeId              = 12;
g_trade[60].ruleSubsetId             = 10;
g_trade[60].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[60].tradeSizePct             = 100;
g_trade[60].tpPoints                 = 6.0;
g_trade[60].slPoints                 = 6.0;
g_trade[60].livePriceDiffTrigger     = 4.0;
g_trade[60].levelOffsetPoints        = 0.5;
g_trade[60].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[60].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[60].babysit_enabled          = false;
g_trade[60].babysitStart_minute      = 0;

// encoding input magic: 10335440157000606
g_trade[61].enabled                  = true;
g_trade[61].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[61].tradeTypeId              = 3;
g_trade[61].ruleSubsetId             = 35;
g_trade[61].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[61].tradeSizePct             = 100;
g_trade[61].tpPoints                 = 6.0;
g_trade[61].slPoints                 = 6.0;
g_trade[61].livePriceDiffTrigger     = 4.0;
g_trade[61].levelOffsetPoints        = 1.5;
g_trade[61].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[61].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[61].babysit_enabled          = false;
g_trade[61].babysitStart_minute      = 0;

// encoding input magic: 10344440057000606
g_trade[62].enabled                  = true;
g_trade[62].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[62].tradeTypeId              = 3;
g_trade[62].ruleSubsetId             = 44;
g_trade[62].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[62].tradeSizePct             = 100;
g_trade[62].tpPoints                 = 6.0;
g_trade[62].slPoints                 = 6.0;
g_trade[62].livePriceDiffTrigger     = 4.0;
g_trade[62].levelOffsetPoints        = 0.5;
g_trade[62].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[62].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[62].babysit_enabled          = false;
g_trade[62].babysitStart_minute      = 0;

// encoding input magic: 10269140057000606
g_trade[63].enabled                  = true;
g_trade[63].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[63].tradeTypeId              = 2;
g_trade[63].ruleSubsetId             = 69;
g_trade[63].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[63].tradeSizePct             = 100;
g_trade[63].tpPoints                 = 6.0;
g_trade[63].slPoints                 = 6.0;
g_trade[63].livePriceDiffTrigger     = 4.0;
g_trade[63].levelOffsetPoints        = 0.5;
g_trade[63].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[63].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[63].babysit_enabled          = false;
g_trade[63].babysitStart_minute      = 0;

// encoding input magic: 10242240157000606
g_trade[64].enabled                  = true;
g_trade[64].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[64].tradeTypeId              = 2;
g_trade[64].ruleSubsetId             = 42;
g_trade[64].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[64].tradeSizePct             = 100;
g_trade[64].tpPoints                 = 6.0;
g_trade[64].slPoints                 = 6.0;
g_trade[64].livePriceDiffTrigger     = 4.0;
g_trade[64].levelOffsetPoints        = 1.5;
g_trade[64].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[64].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[64].babysit_enabled          = false;
g_trade[64].babysitStart_minute      = 0;

// encoding input magic: 10338440157000606
g_trade[65].enabled                  = true;
g_trade[65].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[65].tradeTypeId              = 3;
g_trade[65].ruleSubsetId             = 38;
g_trade[65].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[65].tradeSizePct             = 100;
g_trade[65].tpPoints                 = 6.0;
g_trade[65].slPoints                 = 6.0;
g_trade[65].livePriceDiffTrigger     = 4.0;
g_trade[65].levelOffsetPoints        = 1.5;
g_trade[65].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[65].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[65].babysit_enabled          = false;
g_trade[65].babysitStart_minute      = 0;

// encoding input magic: 11207340037000606
g_trade[66].enabled                  = true;
g_trade[66].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[66].tradeTypeId              = 12;
g_trade[66].ruleSubsetId             = 7;
g_trade[66].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[66].tradeSizePct             = 100;
g_trade[66].tpPoints                 = 6.0;
g_trade[66].slPoints                 = 6.0;
g_trade[66].livePriceDiffTrigger     = 4.0;
g_trade[66].levelOffsetPoints        = 0.3;
g_trade[66].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[66].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[66].babysit_enabled          = false;
g_trade[66].babysitStart_minute      = 0;

// encoding input magic: 10225440057000606
g_trade[67].enabled                  = true;
g_trade[67].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[67].tradeTypeId              = 2;
g_trade[67].ruleSubsetId             = 25;
g_trade[67].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[67].tradeSizePct             = 100;
g_trade[67].tpPoints                 = 6.0;
g_trade[67].slPoints                 = 6.0;
g_trade[67].livePriceDiffTrigger     = 4.0;
g_trade[67].levelOffsetPoints        = 0.5;
g_trade[67].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[67].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[67].babysit_enabled          = false;
g_trade[67].babysitStart_minute      = 0;

// encoding input magic: 10226440107000606
g_trade[68].enabled                  = true;
g_trade[68].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[68].tradeTypeId              = 2;
g_trade[68].ruleSubsetId             = 26;
g_trade[68].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[68].tradeSizePct             = 100;
g_trade[68].tpPoints                 = 6.0;
g_trade[68].slPoints                 = 6.0;
g_trade[68].livePriceDiffTrigger     = 4.0;
g_trade[68].levelOffsetPoints        = 1.0;
g_trade[68].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[68].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[68].babysit_enabled          = false;
g_trade[68].babysitStart_minute      = 0;

// encoding input magic: 10333440037000606
g_trade[69].enabled                  = true;
g_trade[69].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[69].tradeTypeId              = 3;
g_trade[69].ruleSubsetId             = 33;
g_trade[69].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[69].tradeSizePct             = 100;
g_trade[69].tpPoints                 = 6.0;
g_trade[69].slPoints                 = 6.0;
g_trade[69].livePriceDiffTrigger     = 4.0;
g_trade[69].levelOffsetPoints        = 0.3;
g_trade[69].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[69].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[69].babysit_enabled          = false;
g_trade[69].babysitStart_minute      = 0;

// encoding input magic: 10279340157000606
g_trade[70].enabled                  = true;
g_trade[70].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[70].tradeTypeId              = 2;
g_trade[70].ruleSubsetId             = 79;
g_trade[70].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[70].tradeSizePct             = 100;
g_trade[70].tpPoints                 = 6.0;
g_trade[70].slPoints                 = 6.0;
g_trade[70].livePriceDiffTrigger     = 4.0;
g_trade[70].levelOffsetPoints        = 1.5;
g_trade[70].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[70].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[70].babysit_enabled          = false;
g_trade[70].babysitStart_minute      = 0;

// encoding input magic: 10233440057000606
g_trade[71].enabled                  = true;
g_trade[71].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[71].tradeTypeId              = 2;
g_trade[71].ruleSubsetId             = 33;
g_trade[71].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[71].tradeSizePct             = 100;
g_trade[71].tpPoints                 = 6.0;
g_trade[71].slPoints                 = 6.0;
g_trade[71].livePriceDiffTrigger     = 4.0;
g_trade[71].levelOffsetPoints        = 0.5;
g_trade[71].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[71].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[71].babysit_enabled          = false;
g_trade[71].babysitStart_minute      = 0;

// encoding input magic: 10259240157000606
g_trade[72].enabled                  = true;
g_trade[72].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[72].tradeTypeId              = 2;
g_trade[72].ruleSubsetId             = 59;
g_trade[72].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[72].tradeSizePct             = 100;
g_trade[72].tpPoints                 = 6.0;
g_trade[72].slPoints                 = 6.0;
g_trade[72].livePriceDiffTrigger     = 4.0;
g_trade[72].levelOffsetPoints        = 1.5;
g_trade[72].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[72].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[72].babysit_enabled          = false;
g_trade[72].babysitStart_minute      = 0;

// encoding input magic: 10345440157000606
g_trade[73].enabled                  = true;
g_trade[73].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[73].tradeTypeId              = 3;
g_trade[73].ruleSubsetId             = 45;
g_trade[73].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[73].tradeSizePct             = 100;
g_trade[73].tpPoints                 = 6.0;
g_trade[73].slPoints                 = 6.0;
g_trade[73].livePriceDiffTrigger     = 4.0;
g_trade[73].levelOffsetPoints        = 1.5;
g_trade[73].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[73].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[73].babysit_enabled          = false;
g_trade[73].babysitStart_minute      = 0;

// encoding input magic: 10225440037000606
g_trade[74].enabled                  = true;
g_trade[74].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[74].tradeTypeId              = 2;
g_trade[74].ruleSubsetId             = 25;
g_trade[74].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[74].tradeSizePct             = 100;
g_trade[74].tpPoints                 = 6.0;
g_trade[74].slPoints                 = 6.0;
g_trade[74].livePriceDiffTrigger     = 4.0;
g_trade[74].levelOffsetPoints        = 0.3;
g_trade[74].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[74].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[74].babysit_enabled          = false;
g_trade[74].babysitStart_minute      = 0;

// encoding input magic: 10370140157000606
g_trade[75].enabled                  = true;
g_trade[75].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[75].tradeTypeId              = 3;
g_trade[75].ruleSubsetId             = 70;
g_trade[75].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[75].tradeSizePct             = 100;
g_trade[75].tpPoints                 = 6.0;
g_trade[75].slPoints                 = 6.0;
g_trade[75].livePriceDiffTrigger     = 4.0;
g_trade[75].levelOffsetPoints        = 1.5;
g_trade[75].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[75].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[75].babysit_enabled          = false;
g_trade[75].babysitStart_minute      = 0;

// encoding input magic: 10330340057000606
g_trade[76].enabled                  = true;
g_trade[76].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[76].tradeTypeId              = 3;
g_trade[76].ruleSubsetId             = 30;
g_trade[76].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[76].tradeSizePct             = 100;
g_trade[76].tpPoints                 = 6.0;
g_trade[76].slPoints                 = 6.0;
g_trade[76].livePriceDiffTrigger     = 4.0;
g_trade[76].levelOffsetPoints        = 0.5;
g_trade[76].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[76].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[76].babysit_enabled          = false;
g_trade[76].babysitStart_minute      = 0;

// encoding input magic: 10308440107000606
g_trade[77].enabled                  = true;
g_trade[77].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[77].tradeTypeId              = 3;
g_trade[77].ruleSubsetId             = 8;
g_trade[77].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[77].tradeSizePct             = 100;
g_trade[77].tpPoints                 = 6.0;
g_trade[77].slPoints                 = 6.0;
g_trade[77].livePriceDiffTrigger     = 4.0;
g_trade[77].levelOffsetPoints        = 1.0;
g_trade[77].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[77].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[77].babysit_enabled          = false;
g_trade[77].babysitStart_minute      = 0;

// encoding input magic: 10231340107000606
g_trade[78].enabled                  = true;
g_trade[78].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[78].tradeTypeId              = 2;
g_trade[78].ruleSubsetId             = 31;
g_trade[78].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[78].tradeSizePct             = 100;
g_trade[78].tpPoints                 = 6.0;
g_trade[78].slPoints                 = 6.0;
g_trade[78].livePriceDiffTrigger     = 4.0;
g_trade[78].levelOffsetPoints        = 1.0;
g_trade[78].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[78].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[78].babysit_enabled          = false;
g_trade[78].babysitStart_minute      = 0;

// encoding input magic: 10305340057000606
g_trade[79].enabled                  = true;
g_trade[79].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[79].tradeTypeId              = 3;
g_trade[79].ruleSubsetId             = 5;
g_trade[79].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[79].tradeSizePct             = 100;
g_trade[79].tpPoints                 = 6.0;
g_trade[79].slPoints                 = 6.0;
g_trade[79].livePriceDiffTrigger     = 4.0;
g_trade[79].levelOffsetPoints        = 0.5;
g_trade[79].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[79].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[79].babysit_enabled          = false;
g_trade[79].babysitStart_minute      = 0;

// encoding input magic: 10347440157000606
g_trade[80].enabled                  = true;
g_trade[80].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[80].tradeTypeId              = 3;
g_trade[80].ruleSubsetId             = 47;
g_trade[80].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[80].tradeSizePct             = 100;
g_trade[80].tpPoints                 = 6.0;
g_trade[80].slPoints                 = 6.0;
g_trade[80].livePriceDiffTrigger     = 4.0;
g_trade[80].levelOffsetPoints        = 1.5;
g_trade[80].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[80].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[80].babysit_enabled          = false;
g_trade[80].babysitStart_minute      = 0;

// encoding input magic: 10338440107000606
g_trade[81].enabled                  = true;
g_trade[81].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[81].tradeTypeId              = 3;
g_trade[81].ruleSubsetId             = 38;
g_trade[81].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[81].tradeSizePct             = 100;
g_trade[81].tpPoints                 = 6.0;
g_trade[81].slPoints                 = 6.0;
g_trade[81].livePriceDiffTrigger     = 4.0;
g_trade[81].levelOffsetPoints        = 1.0;
g_trade[81].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[81].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[81].babysit_enabled          = false;
g_trade[81].babysitStart_minute      = 0;

// encoding input magic: 10203340057000606
g_trade[82].enabled                  = true;
g_trade[82].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[82].tradeTypeId              = 2;
g_trade[82].ruleSubsetId             = 3;
g_trade[82].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[82].tradeSizePct             = 100;
g_trade[82].tpPoints                 = 6.0;
g_trade[82].slPoints                 = 6.0;
g_trade[82].livePriceDiffTrigger     = 4.0;
g_trade[82].levelOffsetPoints        = 0.5;
g_trade[82].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[82].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[82].babysit_enabled          = false;
g_trade[82].babysitStart_minute      = 0;

// encoding input magic: 10287340107000606
g_trade[83].enabled                  = true;
g_trade[83].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[83].tradeTypeId              = 2;
g_trade[83].ruleSubsetId             = 87;
g_trade[83].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[83].tradeSizePct             = 100;
g_trade[83].tpPoints                 = 6.0;
g_trade[83].slPoints                 = 6.0;
g_trade[83].livePriceDiffTrigger     = 4.0;
g_trade[83].levelOffsetPoints        = 1.0;
g_trade[83].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[83].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[83].babysit_enabled          = false;
g_trade[83].babysitStart_minute      = 0;

// encoding input magic: 10279340107000606
g_trade[84].enabled                  = true;
g_trade[84].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[84].tradeTypeId              = 2;
g_trade[84].ruleSubsetId             = 79;
g_trade[84].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[84].tradeSizePct             = 100;
g_trade[84].tpPoints                 = 6.0;
g_trade[84].slPoints                 = 6.0;
g_trade[84].livePriceDiffTrigger     = 4.0;
g_trade[84].levelOffsetPoints        = 1.0;
g_trade[84].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[84].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[84].babysit_enabled          = false;
g_trade[84].babysitStart_minute      = 0;

// encoding input magic: 10215340157000606
g_trade[85].enabled                  = true;
g_trade[85].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[85].tradeTypeId              = 2;
g_trade[85].ruleSubsetId             = 15;
g_trade[85].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[85].tradeSizePct             = 100;
g_trade[85].tpPoints                 = 6.0;
g_trade[85].slPoints                 = 6.0;
g_trade[85].livePriceDiffTrigger     = 4.0;
g_trade[85].levelOffsetPoints        = 1.5;
g_trade[85].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[85].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[85].babysit_enabled          = false;
g_trade[85].babysitStart_minute      = 0;

// encoding input magic: 10215140057000606
g_trade[86].enabled                  = true;
g_trade[86].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[86].tradeTypeId              = 2;
g_trade[86].ruleSubsetId             = 15;
g_trade[86].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[86].tradeSizePct             = 100;
g_trade[86].tpPoints                 = 6.0;
g_trade[86].slPoints                 = 6.0;
g_trade[86].livePriceDiffTrigger     = 4.0;
g_trade[86].levelOffsetPoints        = 0.5;
g_trade[86].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[86].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[86].babysit_enabled          = false;
g_trade[86].babysitStart_minute      = 0;

// encoding input magic: 10316440057000606
g_trade[87].enabled                  = true;
g_trade[87].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[87].tradeTypeId              = 3;
g_trade[87].ruleSubsetId             = 16;
g_trade[87].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[87].tradeSizePct             = 100;
g_trade[87].tpPoints                 = 6.0;
g_trade[87].slPoints                 = 6.0;
g_trade[87].livePriceDiffTrigger     = 4.0;
g_trade[87].levelOffsetPoints        = 0.5;
g_trade[87].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[87].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[87].babysit_enabled          = false;
g_trade[87].babysitStart_minute      = 0;

// encoding input magic: 10213140157000606
g_trade[88].enabled                  = true;
g_trade[88].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[88].tradeTypeId              = 2;
g_trade[88].ruleSubsetId             = 13;
g_trade[88].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[88].tradeSizePct             = 100;
g_trade[88].tpPoints                 = 6.0;
g_trade[88].slPoints                 = 6.0;
g_trade[88].livePriceDiffTrigger     = 4.0;
g_trade[88].levelOffsetPoints        = 1.5;
g_trade[88].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[88].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[88].babysit_enabled          = false;
g_trade[88].babysitStart_minute      = 0;

// encoding input magic: 10228140107000606
g_trade[89].enabled                  = true;
g_trade[89].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[89].tradeTypeId              = 2;
g_trade[89].ruleSubsetId             = 28;
g_trade[89].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[89].tradeSizePct             = 100;
g_trade[89].tpPoints                 = 6.0;
g_trade[89].slPoints                 = 6.0;
g_trade[89].livePriceDiffTrigger     = 4.0;
g_trade[89].levelOffsetPoints        = 1.0;
g_trade[89].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[89].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[89].babysit_enabled          = false;
g_trade[89].babysitStart_minute      = 0;

// encoding input magic: 10353240037000606
g_trade[90].enabled                  = true;
g_trade[90].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[90].tradeTypeId              = 3;
g_trade[90].ruleSubsetId             = 53;
g_trade[90].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[90].tradeSizePct             = 100;
g_trade[90].tpPoints                 = 6.0;
g_trade[90].slPoints                 = 6.0;
g_trade[90].livePriceDiffTrigger     = 4.0;
g_trade[90].levelOffsetPoints        = 0.3;
g_trade[90].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[90].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[90].babysit_enabled          = false;
g_trade[90].babysitStart_minute      = 0;

// encoding input magic: 10205240157000606
g_trade[91].enabled                  = true;
g_trade[91].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[91].tradeTypeId              = 2;
g_trade[91].ruleSubsetId             = 5;
g_trade[91].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[91].tradeSizePct             = 100;
g_trade[91].tpPoints                 = 6.0;
g_trade[91].slPoints                 = 6.0;
g_trade[91].livePriceDiffTrigger     = 4.0;
g_trade[91].levelOffsetPoints        = 1.5;
g_trade[91].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[91].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[91].babysit_enabled          = false;
g_trade[91].babysitStart_minute      = 0;

// encoding input magic: 10315440107000606
g_trade[92].enabled                  = true;
g_trade[92].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[92].tradeTypeId              = 3;
g_trade[92].ruleSubsetId             = 15;
g_trade[92].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[92].tradeSizePct             = 100;
g_trade[92].tpPoints                 = 6.0;
g_trade[92].slPoints                 = 6.0;
g_trade[92].livePriceDiffTrigger     = 4.0;
g_trade[92].levelOffsetPoints        = 1.0;
g_trade[92].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[92].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[92].babysit_enabled          = false;
g_trade[92].babysitStart_minute      = 0;

// encoding input magic: 10276340107000606
g_trade[93].enabled                  = true;
g_trade[93].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[93].tradeTypeId              = 2;
g_trade[93].ruleSubsetId             = 76;
g_trade[93].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[93].tradeSizePct             = 100;
g_trade[93].tpPoints                 = 6.0;
g_trade[93].slPoints                 = 6.0;
g_trade[93].livePriceDiffTrigger     = 4.0;
g_trade[93].levelOffsetPoints        = 1.0;
g_trade[93].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[93].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[93].babysit_enabled          = false;
g_trade[93].babysitStart_minute      = 0;

// encoding input magic: 10202340057000606
g_trade[94].enabled                  = true;
g_trade[94].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[94].tradeTypeId              = 2;
g_trade[94].ruleSubsetId             = 2;
g_trade[94].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[94].tradeSizePct             = 100;
g_trade[94].tpPoints                 = 6.0;
g_trade[94].slPoints                 = 6.0;
g_trade[94].livePriceDiffTrigger     = 4.0;
g_trade[94].levelOffsetPoints        = 0.5;
g_trade[94].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[94].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[94].babysit_enabled          = false;
g_trade[94].babysitStart_minute      = 0;

// encoding input magic: 10340340107000606
g_trade[95].enabled                  = true;
g_trade[95].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[95].tradeTypeId              = 3;
g_trade[95].ruleSubsetId             = 40;
g_trade[95].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[95].tradeSizePct             = 100;
g_trade[95].tpPoints                 = 6.0;
g_trade[95].slPoints                 = 6.0;
g_trade[95].livePriceDiffTrigger     = 4.0;
g_trade[95].levelOffsetPoints        = 1.0;
g_trade[95].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[95].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[95].babysit_enabled          = false;
g_trade[95].babysitStart_minute      = 0;

// encoding input magic: 10250340157000606
g_trade[96].enabled                  = true;
g_trade[96].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[96].tradeTypeId              = 2;
g_trade[96].ruleSubsetId             = 50;
g_trade[96].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[96].tradeSizePct             = 100;
g_trade[96].tpPoints                 = 6.0;
g_trade[96].slPoints                 = 6.0;
g_trade[96].livePriceDiffTrigger     = 4.0;
g_trade[96].levelOffsetPoints        = 1.5;
g_trade[96].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[96].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[96].babysit_enabled          = false;
g_trade[96].babysitStart_minute      = 0;

// encoding input magic: 10207240107000606
g_trade[97].enabled                  = true;
g_trade[97].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[97].tradeTypeId              = 2;
g_trade[97].ruleSubsetId             = 7;
g_trade[97].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[97].tradeSizePct             = 100;
g_trade[97].tpPoints                 = 6.0;
g_trade[97].slPoints                 = 6.0;
g_trade[97].livePriceDiffTrigger     = 4.0;
g_trade[97].levelOffsetPoints        = 1.0;
g_trade[97].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[97].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[97].babysit_enabled          = false;
g_trade[97].babysitStart_minute      = 0;

// encoding input magic: 11220440107000606
g_trade[98].enabled                  = true;
g_trade[98].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[98].tradeTypeId              = 12;
g_trade[98].ruleSubsetId             = 20;
g_trade[98].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[98].tradeSizePct             = 100;
g_trade[98].tpPoints                 = 6.0;
g_trade[98].slPoints                 = 6.0;
g_trade[98].livePriceDiffTrigger     = 4.0;
g_trade[98].levelOffsetPoints        = 1.0;
g_trade[98].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[98].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[98].babysit_enabled          = false;
g_trade[98].babysitStart_minute      = 0;

// encoding input magic: 11208440157000606
g_trade[99].enabled                  = true;
g_trade[99].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[99].tradeTypeId              = 12;
g_trade[99].ruleSubsetId             = 8;
g_trade[99].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[99].tradeSizePct             = 100;
g_trade[99].tpPoints                 = 6.0;
g_trade[99].slPoints                 = 6.0;
g_trade[99].livePriceDiffTrigger     = 4.0;
g_trade[99].levelOffsetPoints        = 1.5;
g_trade[99].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[99].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[99].babysit_enabled          = false;
g_trade[99].babysitStart_minute      = 0;

// encoding input magic: 10281340157000606
g_trade[100].enabled                  = true;
g_trade[100].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[100].tradeTypeId              = 2;
g_trade[100].ruleSubsetId             = 81;
g_trade[100].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[100].tradeSizePct             = 100;
g_trade[100].tpPoints                 = 6.0;
g_trade[100].slPoints                 = 6.0;
g_trade[100].livePriceDiffTrigger     = 4.0;
g_trade[100].levelOffsetPoints        = 1.5;
g_trade[100].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[100].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[100].babysit_enabled          = false;
g_trade[100].babysitStart_minute      = 0;

// encoding input magic: 10350440157000606
g_trade[101].enabled                  = true;
g_trade[101].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[101].tradeTypeId              = 3;
g_trade[101].ruleSubsetId             = 50;
g_trade[101].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[101].tradeSizePct             = 100;
g_trade[101].tpPoints                 = 6.0;
g_trade[101].slPoints                 = 6.0;
g_trade[101].livePriceDiffTrigger     = 4.0;
g_trade[101].levelOffsetPoints        = 1.5;
g_trade[101].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[101].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[101].babysit_enabled          = false;
g_trade[101].babysitStart_minute      = 0;

// encoding input magic: 10238340157000606
g_trade[102].enabled                  = true;
g_trade[102].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[102].tradeTypeId              = 2;
g_trade[102].ruleSubsetId             = 38;
g_trade[102].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[102].tradeSizePct             = 100;
g_trade[102].tpPoints                 = 6.0;
g_trade[102].slPoints                 = 6.0;
g_trade[102].livePriceDiffTrigger     = 4.0;
g_trade[102].levelOffsetPoints        = 1.5;
g_trade[102].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[102].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[102].babysit_enabled          = false;
g_trade[102].babysitStart_minute      = 0;

// encoding input magic: 10204340057000606
g_trade[103].enabled                  = true;
g_trade[103].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[103].tradeTypeId              = 2;
g_trade[103].ruleSubsetId             = 4;
g_trade[103].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[103].tradeSizePct             = 100;
g_trade[103].tpPoints                 = 6.0;
g_trade[103].slPoints                 = 6.0;
g_trade[103].livePriceDiffTrigger     = 4.0;
g_trade[103].levelOffsetPoints        = 0.5;
g_trade[103].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[103].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[103].babysit_enabled          = false;
g_trade[103].babysitStart_minute      = 0;

// encoding input magic: 10303240157000606
g_trade[104].enabled                  = true;
g_trade[104].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[104].tradeTypeId              = 3;
g_trade[104].ruleSubsetId             = 3;
g_trade[104].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[104].tradeSizePct             = 100;
g_trade[104].tpPoints                 = 6.0;
g_trade[104].slPoints                 = 6.0;
g_trade[104].livePriceDiffTrigger     = 4.0;
g_trade[104].levelOffsetPoints        = 1.5;
g_trade[104].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[104].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[104].babysit_enabled          = false;
g_trade[104].babysitStart_minute      = 0;

// encoding input magic: 10281340037000606
g_trade[105].enabled                  = true;
g_trade[105].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[105].tradeTypeId              = 2;
g_trade[105].ruleSubsetId             = 81;
g_trade[105].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[105].tradeSizePct             = 100;
g_trade[105].tpPoints                 = 6.0;
g_trade[105].slPoints                 = 6.0;
g_trade[105].livePriceDiffTrigger     = 4.0;
g_trade[105].levelOffsetPoints        = 0.3;
g_trade[105].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[105].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[105].babysit_enabled          = false;
g_trade[105].babysitStart_minute      = 0;

// encoding input magic: 10353240107000606
g_trade[106].enabled                  = true;
g_trade[106].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[106].tradeTypeId              = 3;
g_trade[106].ruleSubsetId             = 53;
g_trade[106].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[106].tradeSizePct             = 100;
g_trade[106].tpPoints                 = 6.0;
g_trade[106].slPoints                 = 6.0;
g_trade[106].livePriceDiffTrigger     = 4.0;
g_trade[106].levelOffsetPoints        = 1.0;
g_trade[106].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[106].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[106].babysit_enabled          = false;
g_trade[106].babysitStart_minute      = 0;

// encoding input magic: 10218340107000606
g_trade[107].enabled                  = true;
g_trade[107].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[107].tradeTypeId              = 2;
g_trade[107].ruleSubsetId             = 18;
g_trade[107].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[107].tradeSizePct             = 100;
g_trade[107].tpPoints                 = 6.0;
g_trade[107].slPoints                 = 6.0;
g_trade[107].livePriceDiffTrigger     = 4.0;
g_trade[107].levelOffsetPoints        = 1.0;
g_trade[107].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[107].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[107].babysit_enabled          = false;
g_trade[107].babysitStart_minute      = 0;

// encoding input magic: 10343440157000606
g_trade[108].enabled                  = true;
g_trade[108].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[108].tradeTypeId              = 3;
g_trade[108].ruleSubsetId             = 43;
g_trade[108].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[108].tradeSizePct             = 100;
g_trade[108].tpPoints                 = 6.0;
g_trade[108].slPoints                 = 6.0;
g_trade[108].livePriceDiffTrigger     = 4.0;
g_trade[108].levelOffsetPoints        = 1.5;
g_trade[108].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[108].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[108].babysit_enabled          = false;
g_trade[108].babysitStart_minute      = 0;

// encoding input magic: 10238340107000606
g_trade[109].enabled                  = true;
g_trade[109].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[109].tradeTypeId              = 2;
g_trade[109].ruleSubsetId             = 38;
g_trade[109].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[109].tradeSizePct             = 100;
g_trade[109].tpPoints                 = 6.0;
g_trade[109].slPoints                 = 6.0;
g_trade[109].livePriceDiffTrigger     = 4.0;
g_trade[109].levelOffsetPoints        = 1.0;
g_trade[109].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[109].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[109].babysit_enabled          = false;
g_trade[109].babysitStart_minute      = 0;

// encoding input magic: 10201340037000606
g_trade[110].enabled                  = true;
g_trade[110].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[110].tradeTypeId              = 2;
g_trade[110].ruleSubsetId             = 1;
g_trade[110].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[110].tradeSizePct             = 100;
g_trade[110].tpPoints                 = 6.0;
g_trade[110].slPoints                 = 6.0;
g_trade[110].livePriceDiffTrigger     = 4.0;
g_trade[110].levelOffsetPoints        = 0.3;
g_trade[110].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[110].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[110].babysit_enabled          = false;
g_trade[110].babysitStart_minute      = 0;

// encoding input magic: 10287340157000606
g_trade[111].enabled                  = true;
g_trade[111].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[111].tradeTypeId              = 2;
g_trade[111].ruleSubsetId             = 87;
g_trade[111].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[111].tradeSizePct             = 100;
g_trade[111].tpPoints                 = 6.0;
g_trade[111].slPoints                 = 6.0;
g_trade[111].livePriceDiffTrigger     = 4.0;
g_trade[111].levelOffsetPoints        = 1.5;
g_trade[111].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[111].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[111].babysit_enabled          = false;
g_trade[111].babysitStart_minute      = 0;

// encoding input magic: 10205340057000606
g_trade[112].enabled                  = true;
g_trade[112].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[112].tradeTypeId              = 2;
g_trade[112].ruleSubsetId             = 5;
g_trade[112].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[112].tradeSizePct             = 100;
g_trade[112].tpPoints                 = 6.0;
g_trade[112].slPoints                 = 6.0;
g_trade[112].livePriceDiffTrigger     = 4.0;
g_trade[112].levelOffsetPoints        = 0.5;
g_trade[112].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[112].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[112].babysit_enabled          = false;
g_trade[112].babysitStart_minute      = 0;

// encoding input magic: 10290340107000606
g_trade[113].enabled                  = true;
g_trade[113].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[113].tradeTypeId              = 2;
g_trade[113].ruleSubsetId             = 90;
g_trade[113].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[113].tradeSizePct             = 100;
g_trade[113].tpPoints                 = 6.0;
g_trade[113].slPoints                 = 6.0;
g_trade[113].livePriceDiffTrigger     = 4.0;
g_trade[113].levelOffsetPoints        = 1.0;
g_trade[113].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[113].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[113].babysit_enabled          = false;
g_trade[113].babysitStart_minute      = 0;

// encoding input magic: 10279340037000606
g_trade[114].enabled                  = true;
g_trade[114].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[114].tradeTypeId              = 2;
g_trade[114].ruleSubsetId             = 79;
g_trade[114].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[114].tradeSizePct             = 100;
g_trade[114].tpPoints                 = 6.0;
g_trade[114].slPoints                 = 6.0;
g_trade[114].livePriceDiffTrigger     = 4.0;
g_trade[114].levelOffsetPoints        = 0.3;
g_trade[114].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[114].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[114].babysit_enabled          = false;
g_trade[114].babysitStart_minute      = 0;

// encoding input magic: 10336440037000606
g_trade[115].enabled                  = true;
g_trade[115].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[115].tradeTypeId              = 3;
g_trade[115].ruleSubsetId             = 36;
g_trade[115].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[115].tradeSizePct             = 100;
g_trade[115].tpPoints                 = 6.0;
g_trade[115].slPoints                 = 6.0;
g_trade[115].livePriceDiffTrigger     = 4.0;
g_trade[115].levelOffsetPoints        = 0.3;
g_trade[115].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[115].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[115].babysit_enabled          = false;
g_trade[115].babysitStart_minute      = 0;

// encoding input magic: 10334440157000606
g_trade[116].enabled                  = true;
g_trade[116].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[116].tradeTypeId              = 3;
g_trade[116].ruleSubsetId             = 34;
g_trade[116].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[116].tradeSizePct             = 100;
g_trade[116].tpPoints                 = 6.0;
g_trade[116].slPoints                 = 6.0;
g_trade[116].livePriceDiffTrigger     = 4.0;
g_trade[116].levelOffsetPoints        = 1.5;
g_trade[116].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[116].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[116].babysit_enabled          = false;
g_trade[116].babysitStart_minute      = 0;

// encoding input magic: 11214240037000606
g_trade[117].enabled                  = true;
g_trade[117].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[117].tradeTypeId              = 12;
g_trade[117].ruleSubsetId             = 14;
g_trade[117].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[117].tradeSizePct             = 100;
g_trade[117].tpPoints                 = 6.0;
g_trade[117].slPoints                 = 6.0;
g_trade[117].livePriceDiffTrigger     = 4.0;
g_trade[117].levelOffsetPoints        = 0.3;
g_trade[117].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[117].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[117].babysit_enabled          = false;
g_trade[117].babysitStart_minute      = 0;

// encoding input magic: 10210440037000606
g_trade[118].enabled                  = true;
g_trade[118].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[118].tradeTypeId              = 2;
g_trade[118].ruleSubsetId             = 10;
g_trade[118].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[118].tradeSizePct             = 100;
g_trade[118].tpPoints                 = 6.0;
g_trade[118].slPoints                 = 6.0;
g_trade[118].livePriceDiffTrigger     = 4.0;
g_trade[118].levelOffsetPoints        = 0.3;
g_trade[118].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[118].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[118].babysit_enabled          = false;
g_trade[118].babysitStart_minute      = 0;

// encoding input magic: 10348440157000606
g_trade[119].enabled                  = true;
g_trade[119].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[119].tradeTypeId              = 3;
g_trade[119].ruleSubsetId             = 48;
g_trade[119].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[119].tradeSizePct             = 100;
g_trade[119].tpPoints                 = 6.0;
g_trade[119].slPoints                 = 6.0;
g_trade[119].livePriceDiffTrigger     = 4.0;
g_trade[119].levelOffsetPoints        = 1.5;
g_trade[119].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[119].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[119].babysit_enabled          = false;
g_trade[119].babysitStart_minute      = 0;

// encoding input magic: 10348440107000606
g_trade[120].enabled                  = true;
g_trade[120].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[120].tradeTypeId              = 3;
g_trade[120].ruleSubsetId             = 48;
g_trade[120].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[120].tradeSizePct             = 100;
g_trade[120].tpPoints                 = 6.0;
g_trade[120].slPoints                 = 6.0;
g_trade[120].livePriceDiffTrigger     = 4.0;
g_trade[120].levelOffsetPoints        = 1.0;
g_trade[120].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[120].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[120].babysit_enabled          = false;
g_trade[120].babysitStart_minute      = 0;

// encoding input magic: 10214340107000606
g_trade[121].enabled                  = true;
g_trade[121].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[121].tradeTypeId              = 2;
g_trade[121].ruleSubsetId             = 14;
g_trade[121].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[121].tradeSizePct             = 100;
g_trade[121].tpPoints                 = 6.0;
g_trade[121].slPoints                 = 6.0;
g_trade[121].livePriceDiffTrigger     = 4.0;
g_trade[121].levelOffsetPoints        = 1.0;
g_trade[121].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[121].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[121].babysit_enabled          = false;
g_trade[121].babysitStart_minute      = 0;

// encoding input magic: 11220440157000606
g_trade[122].enabled                  = true;
g_trade[122].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[122].tradeTypeId              = 12;
g_trade[122].ruleSubsetId             = 20;
g_trade[122].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[122].tradeSizePct             = 100;
g_trade[122].tpPoints                 = 6.0;
g_trade[122].slPoints                 = 6.0;
g_trade[122].livePriceDiffTrigger     = 4.0;
g_trade[122].levelOffsetPoints        = 1.5;
g_trade[122].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[122].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[122].babysit_enabled          = false;
g_trade[122].babysitStart_minute      = 0;

// encoding input magic: 10330440037000606
g_trade[123].enabled                  = true;
g_trade[123].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[123].tradeTypeId              = 3;
g_trade[123].ruleSubsetId             = 30;
g_trade[123].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[123].tradeSizePct             = 100;
g_trade[123].tpPoints                 = 6.0;
g_trade[123].slPoints                 = 6.0;
g_trade[123].livePriceDiffTrigger     = 4.0;
g_trade[123].levelOffsetPoints        = 0.3;
g_trade[123].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[123].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[123].babysit_enabled          = false;
g_trade[123].babysitStart_minute      = 0;

// encoding input magic: 10337340107000606
g_trade[124].enabled                  = true;
g_trade[124].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[124].tradeTypeId              = 3;
g_trade[124].ruleSubsetId             = 37;
g_trade[124].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[124].tradeSizePct             = 100;
g_trade[124].tpPoints                 = 6.0;
g_trade[124].slPoints                 = 6.0;
g_trade[124].livePriceDiffTrigger     = 4.0;
g_trade[124].levelOffsetPoints        = 1.0;
g_trade[124].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[124].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[124].babysit_enabled          = false;
g_trade[124].babysitStart_minute      = 0;

// encoding input magic: 10332440157000606
g_trade[125].enabled                  = true;
g_trade[125].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[125].tradeTypeId              = 3;
g_trade[125].ruleSubsetId             = 32;
g_trade[125].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[125].tradeSizePct             = 100;
g_trade[125].tpPoints                 = 6.0;
g_trade[125].slPoints                 = 6.0;
g_trade[125].livePriceDiffTrigger     = 4.0;
g_trade[125].levelOffsetPoints        = 1.5;
g_trade[125].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[125].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[125].babysit_enabled          = false;
g_trade[125].babysitStart_minute      = 0;

// encoding input magic: 11207340057000606
g_trade[126].enabled                  = true;
g_trade[126].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[126].tradeTypeId              = 12;
g_trade[126].ruleSubsetId             = 7;
g_trade[126].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[126].tradeSizePct             = 100;
g_trade[126].tpPoints                 = 6.0;
g_trade[126].slPoints                 = 6.0;
g_trade[126].livePriceDiffTrigger     = 4.0;
g_trade[126].levelOffsetPoints        = 0.5;
g_trade[126].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[126].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[126].babysit_enabled          = false;
g_trade[126].babysitStart_minute      = 0;

// encoding input magic: 10283340157000606
g_trade[127].enabled                  = true;
g_trade[127].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[127].tradeTypeId              = 2;
g_trade[127].ruleSubsetId             = 83;
g_trade[127].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[127].tradeSizePct             = 100;
g_trade[127].tpPoints                 = 6.0;
g_trade[127].slPoints                 = 6.0;
g_trade[127].livePriceDiffTrigger     = 4.0;
g_trade[127].levelOffsetPoints        = 1.5;
g_trade[127].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[127].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[127].babysit_enabled          = false;
g_trade[127].babysitStart_minute      = 0;

// encoding input magic: 10227440107000606
g_trade[128].enabled                  = true;
g_trade[128].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[128].tradeTypeId              = 2;
g_trade[128].ruleSubsetId             = 27;
g_trade[128].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[128].tradeSizePct             = 100;
g_trade[128].tpPoints                 = 6.0;
g_trade[128].slPoints                 = 6.0;
g_trade[128].livePriceDiffTrigger     = 4.0;
g_trade[128].levelOffsetPoints        = 1.0;
g_trade[128].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[128].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[128].babysit_enabled          = false;
g_trade[128].babysitStart_minute      = 0;

// encoding input magic: 10226440157000606
g_trade[129].enabled                  = true;
g_trade[129].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[129].tradeTypeId              = 2;
g_trade[129].ruleSubsetId             = 26;
g_trade[129].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[129].tradeSizePct             = 100;
g_trade[129].tpPoints                 = 6.0;
g_trade[129].slPoints                 = 6.0;
g_trade[129].livePriceDiffTrigger     = 4.0;
g_trade[129].levelOffsetPoints        = 1.5;
g_trade[129].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[129].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[129].babysit_enabled          = false;
g_trade[129].babysitStart_minute      = 0;

// encoding input magic: 10207240057000606
g_trade[130].enabled                  = true;
g_trade[130].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[130].tradeTypeId              = 2;
g_trade[130].ruleSubsetId             = 7;
g_trade[130].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[130].tradeSizePct             = 100;
g_trade[130].tpPoints                 = 6.0;
g_trade[130].slPoints                 = 6.0;
g_trade[130].livePriceDiffTrigger     = 4.0;
g_trade[130].levelOffsetPoints        = 0.5;
g_trade[130].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[130].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[130].babysit_enabled          = false;
g_trade[130].babysitStart_minute      = 0;

// encoding input magic: 11207240057000606
g_trade[131].enabled                  = true;
g_trade[131].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[131].tradeTypeId              = 12;
g_trade[131].ruleSubsetId             = 7;
g_trade[131].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[131].tradeSizePct             = 100;
g_trade[131].tpPoints                 = 6.0;
g_trade[131].slPoints                 = 6.0;
g_trade[131].livePriceDiffTrigger     = 4.0;
g_trade[131].levelOffsetPoints        = 0.5;
g_trade[131].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[131].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[131].babysit_enabled          = false;
g_trade[131].babysitStart_minute      = 0;

// encoding input magic: 10336440157000606
g_trade[132].enabled                  = true;
g_trade[132].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[132].tradeTypeId              = 3;
g_trade[132].ruleSubsetId             = 36;
g_trade[132].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[132].tradeSizePct             = 100;
g_trade[132].tpPoints                 = 6.0;
g_trade[132].slPoints                 = 6.0;
g_trade[132].livePriceDiffTrigger     = 4.0;
g_trade[132].levelOffsetPoints        = 1.5;
g_trade[132].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[132].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[132].babysit_enabled          = false;
g_trade[132].babysitStart_minute      = 0;

// encoding input magic: 10240340107000606
g_trade[133].enabled                  = true;
g_trade[133].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[133].tradeTypeId              = 2;
g_trade[133].ruleSubsetId             = 40;
g_trade[133].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[133].tradeSizePct             = 100;
g_trade[133].tpPoints                 = 6.0;
g_trade[133].slPoints                 = 6.0;
g_trade[133].livePriceDiffTrigger     = 4.0;
g_trade[133].levelOffsetPoints        = 1.0;
g_trade[133].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[133].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[133].babysit_enabled          = false;
g_trade[133].babysitStart_minute      = 0;

// encoding input magic: 10288340107000606
g_trade[134].enabled                  = true;
g_trade[134].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[134].tradeTypeId              = 2;
g_trade[134].ruleSubsetId             = 88;
g_trade[134].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[134].tradeSizePct             = 100;
g_trade[134].tpPoints                 = 6.0;
g_trade[134].slPoints                 = 6.0;
g_trade[134].livePriceDiffTrigger     = 4.0;
g_trade[134].levelOffsetPoints        = 1.0;
g_trade[134].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[134].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[134].babysit_enabled          = false;
g_trade[134].babysitStart_minute      = 0;

// encoding input magic: 10330440107000606
g_trade[135].enabled                  = true;
g_trade[135].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[135].tradeTypeId              = 3;
g_trade[135].ruleSubsetId             = 30;
g_trade[135].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[135].tradeSizePct             = 100;
g_trade[135].tpPoints                 = 6.0;
g_trade[135].slPoints                 = 6.0;
g_trade[135].livePriceDiffTrigger     = 4.0;
g_trade[135].levelOffsetPoints        = 1.0;
g_trade[135].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[135].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[135].babysit_enabled          = false;
g_trade[135].babysitStart_minute      = 0;

// encoding input magic: 10334340037000606
g_trade[136].enabled                  = true;
g_trade[136].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[136].tradeTypeId              = 3;
g_trade[136].ruleSubsetId             = 34;
g_trade[136].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[136].tradeSizePct             = 100;
g_trade[136].tpPoints                 = 6.0;
g_trade[136].slPoints                 = 6.0;
g_trade[136].livePriceDiffTrigger     = 4.0;
g_trade[136].levelOffsetPoints        = 0.3;
g_trade[136].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[136].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[136].babysit_enabled          = false;
g_trade[136].babysitStart_minute      = 0;

// encoding input magic: 10233440037000606
g_trade[137].enabled                  = true;
g_trade[137].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[137].tradeTypeId              = 2;
g_trade[137].ruleSubsetId             = 33;
g_trade[137].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[137].tradeSizePct             = 100;
g_trade[137].tpPoints                 = 6.0;
g_trade[137].slPoints                 = 6.0;
g_trade[137].livePriceDiffTrigger     = 4.0;
g_trade[137].levelOffsetPoints        = 0.3;
g_trade[137].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[137].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[137].babysit_enabled          = false;
g_trade[137].babysitStart_minute      = 0;

// encoding input magic: 10246440157000606
g_trade[138].enabled                  = true;
g_trade[138].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[138].tradeTypeId              = 2;
g_trade[138].ruleSubsetId             = 46;
g_trade[138].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[138].tradeSizePct             = 100;
g_trade[138].tpPoints                 = 6.0;
g_trade[138].slPoints                 = 6.0;
g_trade[138].livePriceDiffTrigger     = 4.0;
g_trade[138].levelOffsetPoints        = 1.5;
g_trade[138].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[138].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[138].babysit_enabled          = false;
g_trade[138].babysitStart_minute      = 0;

// encoding input magic: 10242240107000606
g_trade[139].enabled                  = true;
g_trade[139].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[139].tradeTypeId              = 2;
g_trade[139].ruleSubsetId             = 42;
g_trade[139].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[139].tradeSizePct             = 100;
g_trade[139].tpPoints                 = 6.0;
g_trade[139].slPoints                 = 6.0;
g_trade[139].livePriceDiffTrigger     = 4.0;
g_trade[139].levelOffsetPoints        = 1.0;
g_trade[139].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[139].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[139].babysit_enabled          = false;
g_trade[139].babysitStart_minute      = 0;

// encoding input magic: 10305440107000606
g_trade[140].enabled                  = true;
g_trade[140].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[140].tradeTypeId              = 3;
g_trade[140].ruleSubsetId             = 5;
g_trade[140].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[140].tradeSizePct             = 100;
g_trade[140].tpPoints                 = 6.0;
g_trade[140].slPoints                 = 6.0;
g_trade[140].livePriceDiffTrigger     = 4.0;
g_trade[140].levelOffsetPoints        = 1.0;
g_trade[140].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[140].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[140].babysit_enabled          = false;
g_trade[140].babysitStart_minute      = 0;

// encoding input magic: 10232440107000606
g_trade[141].enabled                  = true;
g_trade[141].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[141].tradeTypeId              = 2;
g_trade[141].ruleSubsetId             = 32;
g_trade[141].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[141].tradeSizePct             = 100;
g_trade[141].tpPoints                 = 6.0;
g_trade[141].slPoints                 = 6.0;
g_trade[141].livePriceDiffTrigger     = 4.0;
g_trade[141].levelOffsetPoints        = 1.0;
g_trade[141].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[141].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[141].babysit_enabled          = false;
g_trade[141].babysitStart_minute      = 0;

// encoding input magic: 10269140037000606
g_trade[142].enabled                  = true;
g_trade[142].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[142].tradeTypeId              = 2;
g_trade[142].ruleSubsetId             = 69;
g_trade[142].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[142].tradeSizePct             = 100;
g_trade[142].tpPoints                 = 6.0;
g_trade[142].slPoints                 = 6.0;
g_trade[142].livePriceDiffTrigger     = 4.0;
g_trade[142].levelOffsetPoints        = 0.3;
g_trade[142].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[142].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[142].babysit_enabled          = false;
g_trade[142].babysitStart_minute      = 0;

// encoding input magic: 10221340157000606
g_trade[143].enabled                  = true;
g_trade[143].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[143].tradeTypeId              = 2;
g_trade[143].ruleSubsetId             = 21;
g_trade[143].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[143].tradeSizePct             = 100;
g_trade[143].tpPoints                 = 6.0;
g_trade[143].slPoints                 = 6.0;
g_trade[143].livePriceDiffTrigger     = 4.0;
g_trade[143].levelOffsetPoints        = 1.5;
g_trade[143].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[143].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[143].babysit_enabled          = false;
g_trade[143].babysitStart_minute      = 0;

// encoding input magic: 10348440057000606
g_trade[144].enabled                  = true;
g_trade[144].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[144].tradeTypeId              = 3;
g_trade[144].ruleSubsetId             = 48;
g_trade[144].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[144].tradeSizePct             = 100;
g_trade[144].tpPoints                 = 6.0;
g_trade[144].slPoints                 = 6.0;
g_trade[144].livePriceDiffTrigger     = 4.0;
g_trade[144].levelOffsetPoints        = 0.5;
g_trade[144].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[144].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[144].babysit_enabled          = false;
g_trade[144].babysitStart_minute      = 0;

// encoding input magic: 11221440107000606
g_trade[145].enabled                  = true;
g_trade[145].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[145].tradeTypeId              = 12;
g_trade[145].ruleSubsetId             = 21;
g_trade[145].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[145].tradeSizePct             = 100;
g_trade[145].tpPoints                 = 6.0;
g_trade[145].slPoints                 = 6.0;
g_trade[145].livePriceDiffTrigger     = 4.0;
g_trade[145].levelOffsetPoints        = 1.0;
g_trade[145].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[145].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[145].babysit_enabled          = false;
g_trade[145].babysitStart_minute      = 0;

// encoding input magic: 10345440057000606
g_trade[146].enabled                  = true;
g_trade[146].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[146].tradeTypeId              = 3;
g_trade[146].ruleSubsetId             = 45;
g_trade[146].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[146].tradeSizePct             = 100;
g_trade[146].tpPoints                 = 6.0;
g_trade[146].slPoints                 = 6.0;
g_trade[146].livePriceDiffTrigger     = 4.0;
g_trade[146].levelOffsetPoints        = 0.5;
g_trade[146].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[146].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[146].babysit_enabled          = false;
g_trade[146].babysitStart_minute      = 0;

// encoding input magic: 11222440107000606
g_trade[147].enabled                  = true;
g_trade[147].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[147].tradeTypeId              = 12;
g_trade[147].ruleSubsetId             = 22;
g_trade[147].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[147].tradeSizePct             = 100;
g_trade[147].tpPoints                 = 6.0;
g_trade[147].slPoints                 = 6.0;
g_trade[147].livePriceDiffTrigger     = 4.0;
g_trade[147].levelOffsetPoints        = 1.0;
g_trade[147].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[147].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[147].babysit_enabled          = false;
g_trade[147].babysitStart_minute      = 0;

// encoding input magic: 10341140157000606
g_trade[148].enabled                  = true;
g_trade[148].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[148].tradeTypeId              = 3;
g_trade[148].ruleSubsetId             = 41;
g_trade[148].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[148].tradeSizePct             = 100;
g_trade[148].tpPoints                 = 6.0;
g_trade[148].slPoints                 = 6.0;
g_trade[148].livePriceDiffTrigger     = 4.0;
g_trade[148].levelOffsetPoints        = 1.5;
g_trade[148].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[148].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[148].babysit_enabled          = false;
g_trade[148].babysitStart_minute      = 0;

// encoding input magic: 10313440057000606
g_trade[149].enabled                  = true;
g_trade[149].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[149].tradeTypeId              = 3;
g_trade[149].ruleSubsetId             = 13;
g_trade[149].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[149].tradeSizePct             = 100;
g_trade[149].tpPoints                 = 6.0;
g_trade[149].slPoints                 = 6.0;
g_trade[149].livePriceDiffTrigger     = 4.0;
g_trade[149].levelOffsetPoints        = 0.5;
g_trade[149].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[149].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[149].babysit_enabled          = false;
g_trade[149].babysitStart_minute      = 0;

// encoding input magic: 10226240107000606
g_trade[150].enabled                  = true;
g_trade[150].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[150].tradeTypeId              = 2;
g_trade[150].ruleSubsetId             = 26;
g_trade[150].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[150].tradeSizePct             = 100;
g_trade[150].tpPoints                 = 6.0;
g_trade[150].slPoints                 = 6.0;
g_trade[150].livePriceDiffTrigger     = 4.0;
g_trade[150].levelOffsetPoints        = 1.0;
g_trade[150].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[150].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[150].babysit_enabled          = false;
g_trade[150].babysitStart_minute      = 0;

// encoding input magic: 10303340037000606
g_trade[151].enabled                  = true;
g_trade[151].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[151].tradeTypeId              = 3;
g_trade[151].ruleSubsetId             = 3;
g_trade[151].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[151].tradeSizePct             = 100;
g_trade[151].tpPoints                 = 6.0;
g_trade[151].slPoints                 = 6.0;
g_trade[151].livePriceDiffTrigger     = 4.0;
g_trade[151].levelOffsetPoints        = 0.3;
g_trade[151].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[151].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[151].babysit_enabled          = false;
g_trade[151].babysitStart_minute      = 0;

// encoding input magic: 10318440037000606
g_trade[152].enabled                  = true;
g_trade[152].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[152].tradeTypeId              = 3;
g_trade[152].ruleSubsetId             = 18;
g_trade[152].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[152].tradeSizePct             = 100;
g_trade[152].tpPoints                 = 6.0;
g_trade[152].slPoints                 = 6.0;
g_trade[152].livePriceDiffTrigger     = 4.0;
g_trade[152].levelOffsetPoints        = 0.3;
g_trade[152].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[152].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[152].babysit_enabled          = false;
g_trade[152].babysitStart_minute      = 0;

// encoding input magic: 10344440037000606
g_trade[153].enabled                  = true;
g_trade[153].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[153].tradeTypeId              = 3;
g_trade[153].ruleSubsetId             = 44;
g_trade[153].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[153].tradeSizePct             = 100;
g_trade[153].tpPoints                 = 6.0;
g_trade[153].slPoints                 = 6.0;
g_trade[153].livePriceDiffTrigger     = 4.0;
g_trade[153].levelOffsetPoints        = 0.3;
g_trade[153].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[153].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[153].babysit_enabled          = false;
g_trade[153].babysitStart_minute      = 0;

// encoding input magic: 10330340107000606
g_trade[154].enabled                  = true;
g_trade[154].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[154].tradeTypeId              = 3;
g_trade[154].ruleSubsetId             = 30;
g_trade[154].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[154].tradeSizePct             = 100;
g_trade[154].tpPoints                 = 6.0;
g_trade[154].slPoints                 = 6.0;
g_trade[154].livePriceDiffTrigger     = 4.0;
g_trade[154].levelOffsetPoints        = 1.0;
g_trade[154].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[154].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[154].babysit_enabled          = false;
g_trade[154].babysitStart_minute      = 0;

// encoding input magic: 10248340157000606
g_trade[155].enabled                  = true;
g_trade[155].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[155].tradeTypeId              = 2;
g_trade[155].ruleSubsetId             = 48;
g_trade[155].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[155].tradeSizePct             = 100;
g_trade[155].tpPoints                 = 6.0;
g_trade[155].slPoints                 = 6.0;
g_trade[155].livePriceDiffTrigger     = 4.0;
g_trade[155].levelOffsetPoints        = 1.5;
g_trade[155].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[155].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[155].babysit_enabled          = false;
g_trade[155].babysitStart_minute      = 0;

// encoding input magic: 11220240037000606
g_trade[156].enabled                  = true;
g_trade[156].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[156].tradeTypeId              = 12;
g_trade[156].ruleSubsetId             = 20;
g_trade[156].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[156].tradeSizePct             = 100;
g_trade[156].tpPoints                 = 6.0;
g_trade[156].slPoints                 = 6.0;
g_trade[156].livePriceDiffTrigger     = 4.0;
g_trade[156].levelOffsetPoints        = 0.3;
g_trade[156].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[156].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[156].babysit_enabled          = false;
g_trade[156].babysitStart_minute      = 0;

// encoding input magic: 10307440107000606
g_trade[157].enabled                  = true;
g_trade[157].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[157].tradeTypeId              = 3;
g_trade[157].ruleSubsetId             = 7;
g_trade[157].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[157].tradeSizePct             = 100;
g_trade[157].tpPoints                 = 6.0;
g_trade[157].slPoints                 = 6.0;
g_trade[157].livePriceDiffTrigger     = 4.0;
g_trade[157].levelOffsetPoints        = 1.0;
g_trade[157].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[157].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[157].babysit_enabled          = false;
g_trade[157].babysitStart_minute      = 0;

// encoding input magic: 10341440157000606
g_trade[158].enabled                  = true;
g_trade[158].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[158].tradeTypeId              = 3;
g_trade[158].ruleSubsetId             = 41;
g_trade[158].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[158].tradeSizePct             = 100;
g_trade[158].tpPoints                 = 6.0;
g_trade[158].slPoints                 = 6.0;
g_trade[158].livePriceDiffTrigger     = 4.0;
g_trade[158].levelOffsetPoints        = 1.5;
g_trade[158].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[158].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[158].babysit_enabled          = false;
g_trade[158].babysitStart_minute      = 0;

// encoding input magic: 11221440157000606
g_trade[159].enabled                  = true;
g_trade[159].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[159].tradeTypeId              = 12;
g_trade[159].ruleSubsetId             = 21;
g_trade[159].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[159].tradeSizePct             = 100;
g_trade[159].tpPoints                 = 6.0;
g_trade[159].slPoints                 = 6.0;
g_trade[159].livePriceDiffTrigger     = 4.0;
g_trade[159].levelOffsetPoints        = 1.5;
g_trade[159].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[159].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[159].babysit_enabled          = false;
g_trade[159].babysitStart_minute      = 0;

// encoding input magic: 10250340107000606
g_trade[160].enabled                  = true;
g_trade[160].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[160].tradeTypeId              = 2;
g_trade[160].ruleSubsetId             = 50;
g_trade[160].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[160].tradeSizePct             = 100;
g_trade[160].tpPoints                 = 6.0;
g_trade[160].slPoints                 = 6.0;
g_trade[160].livePriceDiffTrigger     = 4.0;
g_trade[160].levelOffsetPoints        = 1.0;
g_trade[160].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[160].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[160].babysit_enabled          = false;
g_trade[160].babysitStart_minute      = 0;

// encoding input magic: 10240340157000606
g_trade[161].enabled                  = true;
g_trade[161].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[161].tradeTypeId              = 2;
g_trade[161].ruleSubsetId             = 40;
g_trade[161].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[161].tradeSizePct             = 100;
g_trade[161].tpPoints                 = 6.0;
g_trade[161].slPoints                 = 6.0;
g_trade[161].livePriceDiffTrigger     = 4.0;
g_trade[161].levelOffsetPoints        = 1.5;
g_trade[161].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[161].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[161].babysit_enabled          = false;
g_trade[161].babysitStart_minute      = 0;

// encoding input magic: 10218340157000606
g_trade[162].enabled                  = true;
g_trade[162].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[162].tradeTypeId              = 2;
g_trade[162].ruleSubsetId             = 18;
g_trade[162].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[162].tradeSizePct             = 100;
g_trade[162].tpPoints                 = 6.0;
g_trade[162].slPoints                 = 6.0;
g_trade[162].livePriceDiffTrigger     = 4.0;
g_trade[162].levelOffsetPoints        = 1.5;
g_trade[162].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[162].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[162].babysit_enabled          = false;
g_trade[162].babysitStart_minute      = 0;

// encoding input magic: 10219440057000606
g_trade[163].enabled                  = true;
g_trade[163].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[163].tradeTypeId              = 2;
g_trade[163].ruleSubsetId             = 19;
g_trade[163].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[163].tradeSizePct             = 100;
g_trade[163].tpPoints                 = 6.0;
g_trade[163].slPoints                 = 6.0;
g_trade[163].livePriceDiffTrigger     = 4.0;
g_trade[163].levelOffsetPoints        = 0.5;
g_trade[163].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[163].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[163].babysit_enabled          = false;
g_trade[163].babysitStart_minute      = 0;

// encoding input magic: 10331440107000606
g_trade[164].enabled                  = true;
g_trade[164].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[164].tradeTypeId              = 3;
g_trade[164].ruleSubsetId             = 31;
g_trade[164].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[164].tradeSizePct             = 100;
g_trade[164].tpPoints                 = 6.0;
g_trade[164].slPoints                 = 6.0;
g_trade[164].livePriceDiffTrigger     = 4.0;
g_trade[164].levelOffsetPoints        = 1.0;
g_trade[164].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[164].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[164].babysit_enabled          = false;
g_trade[164].babysitStart_minute      = 0;

// encoding input magic: 10236340157000606
g_trade[165].enabled                  = true;
g_trade[165].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[165].tradeTypeId              = 2;
g_trade[165].ruleSubsetId             = 36;
g_trade[165].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[165].tradeSizePct             = 100;
g_trade[165].tpPoints                 = 6.0;
g_trade[165].slPoints                 = 6.0;
g_trade[165].livePriceDiffTrigger     = 4.0;
g_trade[165].levelOffsetPoints        = 1.5;
g_trade[165].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[165].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[165].babysit_enabled          = false;
g_trade[165].babysitStart_minute      = 0;

// encoding input magic: 10273340057000606
g_trade[166].enabled                  = true;
g_trade[166].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[166].tradeTypeId              = 2;
g_trade[166].ruleSubsetId             = 73;
g_trade[166].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[166].tradeSizePct             = 100;
g_trade[166].tpPoints                 = 6.0;
g_trade[166].slPoints                 = 6.0;
g_trade[166].livePriceDiffTrigger     = 4.0;
g_trade[166].levelOffsetPoints        = 0.5;
g_trade[166].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[166].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[166].babysit_enabled          = false;
g_trade[166].babysitStart_minute      = 0;

// encoding input magic: 10274340107000606
g_trade[167].enabled                  = true;
g_trade[167].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[167].tradeTypeId              = 2;
g_trade[167].ruleSubsetId             = 74;
g_trade[167].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[167].tradeSizePct             = 100;
g_trade[167].tpPoints                 = 6.0;
g_trade[167].slPoints                 = 6.0;
g_trade[167].livePriceDiffTrigger     = 4.0;
g_trade[167].levelOffsetPoints        = 1.0;
g_trade[167].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[167].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[167].babysit_enabled          = false;
g_trade[167].babysitStart_minute      = 0;

// encoding input magic: 10341240057000606
g_trade[168].enabled                  = true;
g_trade[168].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[168].tradeTypeId              = 3;
g_trade[168].ruleSubsetId             = 41;
g_trade[168].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[168].tradeSizePct             = 100;
g_trade[168].tpPoints                 = 6.0;
g_trade[168].slPoints                 = 6.0;
g_trade[168].livePriceDiffTrigger     = 4.0;
g_trade[168].levelOffsetPoints        = 0.5;
g_trade[168].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[168].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[168].babysit_enabled          = false;
g_trade[168].babysitStart_minute      = 0;

// encoding input magic: 10247140037000606
g_trade[169].enabled                  = true;
g_trade[169].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[169].tradeTypeId              = 2;
g_trade[169].ruleSubsetId             = 47;
g_trade[169].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[169].tradeSizePct             = 100;
g_trade[169].tpPoints                 = 6.0;
g_trade[169].slPoints                 = 6.0;
g_trade[169].livePriceDiffTrigger     = 4.0;
g_trade[169].levelOffsetPoints        = 0.3;
g_trade[169].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[169].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[169].babysit_enabled          = false;
g_trade[169].babysitStart_minute      = 0;

// encoding input magic: 10302340037000606
g_trade[170].enabled                  = true;
g_trade[170].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[170].tradeTypeId              = 3;
g_trade[170].ruleSubsetId             = 2;
g_trade[170].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[170].tradeSizePct             = 100;
g_trade[170].tpPoints                 = 6.0;
g_trade[170].slPoints                 = 6.0;
g_trade[170].livePriceDiffTrigger     = 4.0;
g_trade[170].levelOffsetPoints        = 0.3;
g_trade[170].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[170].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[170].babysit_enabled          = false;
g_trade[170].babysitStart_minute      = 0;

// encoding input magic: 10222340107000606
g_trade[171].enabled                  = true;
g_trade[171].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[171].tradeTypeId              = 2;
g_trade[171].ruleSubsetId             = 22;
g_trade[171].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[171].tradeSizePct             = 100;
g_trade[171].tpPoints                 = 6.0;
g_trade[171].slPoints                 = 6.0;
g_trade[171].livePriceDiffTrigger     = 4.0;
g_trade[171].levelOffsetPoints        = 1.0;
g_trade[171].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[171].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[171].babysit_enabled          = false;
g_trade[171].babysitStart_minute      = 0;

// encoding input magic: 10301440107000606
g_trade[172].enabled                  = true;
g_trade[172].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[172].tradeTypeId              = 3;
g_trade[172].ruleSubsetId             = 1;
g_trade[172].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[172].tradeSizePct             = 100;
g_trade[172].tpPoints                 = 6.0;
g_trade[172].slPoints                 = 6.0;
g_trade[172].livePriceDiffTrigger     = 4.0;
g_trade[172].levelOffsetPoints        = 1.0;
g_trade[172].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[172].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[172].babysit_enabled          = false;
g_trade[172].babysitStart_minute      = 0;

// encoding input magic: 10289340107000606
g_trade[173].enabled                  = true;
g_trade[173].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[173].tradeTypeId              = 2;
g_trade[173].ruleSubsetId             = 89;
g_trade[173].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[173].tradeSizePct             = 100;
g_trade[173].tpPoints                 = 6.0;
g_trade[173].slPoints                 = 6.0;
g_trade[173].livePriceDiffTrigger     = 4.0;
g_trade[173].levelOffsetPoints        = 1.0;
g_trade[173].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[173].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[173].babysit_enabled          = false;
g_trade[173].babysitStart_minute      = 0;

// encoding input magic: 10222340157000606
g_trade[174].enabled                  = true;
g_trade[174].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[174].tradeTypeId              = 2;
g_trade[174].ruleSubsetId             = 22;
g_trade[174].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[174].tradeSizePct             = 100;
g_trade[174].tpPoints                 = 6.0;
g_trade[174].slPoints                 = 6.0;
g_trade[174].livePriceDiffTrigger     = 4.0;
g_trade[174].levelOffsetPoints        = 1.5;
g_trade[174].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[174].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[174].babysit_enabled          = false;
g_trade[174].babysitStart_minute      = 0;

// encoding input magic: 10316440107000606
g_trade[175].enabled                  = true;
g_trade[175].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[175].tradeTypeId              = 3;
g_trade[175].ruleSubsetId             = 16;
g_trade[175].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[175].tradeSizePct             = 100;
g_trade[175].tpPoints                 = 6.0;
g_trade[175].slPoints                 = 6.0;
g_trade[175].livePriceDiffTrigger     = 4.0;
g_trade[175].levelOffsetPoints        = 1.0;
g_trade[175].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[175].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[175].babysit_enabled          = false;
g_trade[175].babysitStart_minute      = 0;

// encoding input magic: 10287340037000606
g_trade[176].enabled                  = true;
g_trade[176].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[176].tradeTypeId              = 2;
g_trade[176].ruleSubsetId             = 87;
g_trade[176].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[176].tradeSizePct             = 100;
g_trade[176].tpPoints                 = 6.0;
g_trade[176].slPoints                 = 6.0;
g_trade[176].livePriceDiffTrigger     = 4.0;
g_trade[176].levelOffsetPoints        = 0.3;
g_trade[176].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[176].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[176].babysit_enabled          = false;
g_trade[176].babysitStart_minute      = 0;

// encoding input magic: 10264340107000606
g_trade[177].enabled                  = true;
g_trade[177].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[177].tradeTypeId              = 2;
g_trade[177].ruleSubsetId             = 64;
g_trade[177].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[177].tradeSizePct             = 100;
g_trade[177].tpPoints                 = 6.0;
g_trade[177].slPoints                 = 6.0;
g_trade[177].livePriceDiffTrigger     = 4.0;
g_trade[177].levelOffsetPoints        = 1.0;
g_trade[177].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[177].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[177].babysit_enabled          = false;
g_trade[177].babysitStart_minute      = 0;

// encoding input magic: 10253440037000606
g_trade[178].enabled                  = true;
g_trade[178].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[178].tradeTypeId              = 2;
g_trade[178].ruleSubsetId             = 53;
g_trade[178].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[178].tradeSizePct             = 100;
g_trade[178].tpPoints                 = 6.0;
g_trade[178].slPoints                 = 6.0;
g_trade[178].livePriceDiffTrigger     = 4.0;
g_trade[178].levelOffsetPoints        = 0.3;
g_trade[178].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[178].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[178].babysit_enabled          = false;
g_trade[178].babysitStart_minute      = 0;

// encoding input magic: 10234140037000606
g_trade[179].enabled                  = true;
g_trade[179].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[179].tradeTypeId              = 2;
g_trade[179].ruleSubsetId             = 34;
g_trade[179].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[179].tradeSizePct             = 100;
g_trade[179].tpPoints                 = 6.0;
g_trade[179].slPoints                 = 6.0;
g_trade[179].livePriceDiffTrigger     = 4.0;
g_trade[179].levelOffsetPoints        = 0.3;
g_trade[179].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[179].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[179].babysit_enabled          = false;
g_trade[179].babysitStart_minute      = 0;

// encoding input magic: 10249140037000606
g_trade[180].enabled                  = true;
g_trade[180].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[180].tradeTypeId              = 2;
g_trade[180].ruleSubsetId             = 49;
g_trade[180].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[180].tradeSizePct             = 100;
g_trade[180].tpPoints                 = 6.0;
g_trade[180].slPoints                 = 6.0;
g_trade[180].livePriceDiffTrigger     = 4.0;
g_trade[180].levelOffsetPoints        = 0.3;
g_trade[180].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[180].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[180].babysit_enabled          = false;
g_trade[180].babysitStart_minute      = 0;

// encoding input magic: 10289340157000606
g_trade[181].enabled                  = true;
g_trade[181].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[181].tradeTypeId              = 2;
g_trade[181].ruleSubsetId             = 89;
g_trade[181].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[181].tradeSizePct             = 100;
g_trade[181].tpPoints                 = 6.0;
g_trade[181].slPoints                 = 6.0;
g_trade[181].livePriceDiffTrigger     = 4.0;
g_trade[181].levelOffsetPoints        = 1.5;
g_trade[181].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[181].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[181].babysit_enabled          = false;
g_trade[181].babysitStart_minute      = 0;

// encoding input magic: 10347440037000606
g_trade[182].enabled                  = true;
g_trade[182].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[182].tradeTypeId              = 3;
g_trade[182].ruleSubsetId             = 47;
g_trade[182].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[182].tradeSizePct             = 100;
g_trade[182].tpPoints                 = 6.0;
g_trade[182].slPoints                 = 6.0;
g_trade[182].livePriceDiffTrigger     = 4.0;
g_trade[182].levelOffsetPoints        = 0.3;
g_trade[182].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[182].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[182].babysit_enabled          = false;
g_trade[182].babysitStart_minute      = 0;

// encoding input magic: 10334440057000606
g_trade[183].enabled                  = true;
g_trade[183].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[183].tradeTypeId              = 3;
g_trade[183].ruleSubsetId             = 34;
g_trade[183].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[183].tradeSizePct             = 100;
g_trade[183].tpPoints                 = 6.0;
g_trade[183].slPoints                 = 6.0;
g_trade[183].livePriceDiffTrigger     = 4.0;
g_trade[183].levelOffsetPoints        = 0.5;
g_trade[183].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[183].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[183].babysit_enabled          = false;
g_trade[183].babysitStart_minute      = 0;

// encoding input magic: 11229240057000606
g_trade[184].enabled                  = true;
g_trade[184].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[184].tradeTypeId              = 12;
g_trade[184].ruleSubsetId             = 29;
g_trade[184].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[184].tradeSizePct             = 100;
g_trade[184].tpPoints                 = 6.0;
g_trade[184].slPoints                 = 6.0;
g_trade[184].livePriceDiffTrigger     = 4.0;
g_trade[184].levelOffsetPoints        = 0.5;
g_trade[184].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[184].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[184].babysit_enabled          = false;
g_trade[184].babysitStart_minute      = 0;

// encoding input magic: 11222440157000606
g_trade[185].enabled                  = true;
g_trade[185].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[185].tradeTypeId              = 12;
g_trade[185].ruleSubsetId             = 22;
g_trade[185].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[185].tradeSizePct             = 100;
g_trade[185].tpPoints                 = 6.0;
g_trade[185].slPoints                 = 6.0;
g_trade[185].livePriceDiffTrigger     = 4.0;
g_trade[185].levelOffsetPoints        = 1.5;
g_trade[185].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[185].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[185].babysit_enabled          = false;
g_trade[185].babysitStart_minute      = 0;

// encoding input magic: 10313440037000606
g_trade[186].enabled                  = true;
g_trade[186].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[186].tradeTypeId              = 3;
g_trade[186].ruleSubsetId             = 13;
g_trade[186].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[186].tradeSizePct             = 100;
g_trade[186].tpPoints                 = 6.0;
g_trade[186].slPoints                 = 6.0;
g_trade[186].livePriceDiffTrigger     = 4.0;
g_trade[186].levelOffsetPoints        = 0.3;
g_trade[186].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[186].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[186].babysit_enabled          = false;
g_trade[186].babysitStart_minute      = 0;

// encoding input magic: 10287340057000606
g_trade[187].enabled                  = true;
g_trade[187].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[187].tradeTypeId              = 2;
g_trade[187].ruleSubsetId             = 87;
g_trade[187].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[187].tradeSizePct             = 100;
g_trade[187].tpPoints                 = 6.0;
g_trade[187].slPoints                 = 6.0;
g_trade[187].livePriceDiffTrigger     = 4.0;
g_trade[187].levelOffsetPoints        = 0.5;
g_trade[187].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[187].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[187].babysit_enabled          = false;
g_trade[187].babysitStart_minute      = 0;

// encoding input magic: 10338440057000606
g_trade[188].enabled                  = true;
g_trade[188].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[188].tradeTypeId              = 3;
g_trade[188].ruleSubsetId             = 38;
g_trade[188].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[188].tradeSizePct             = 100;
g_trade[188].tpPoints                 = 6.0;
g_trade[188].slPoints                 = 6.0;
g_trade[188].livePriceDiffTrigger     = 4.0;
g_trade[188].levelOffsetPoints        = 0.5;
g_trade[188].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[188].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[188].babysit_enabled          = false;
g_trade[188].babysitStart_minute      = 0;

// encoding input magic: 10333440157000606
g_trade[189].enabled                  = true;
g_trade[189].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[189].tradeTypeId              = 3;
g_trade[189].ruleSubsetId             = 33;
g_trade[189].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[189].tradeSizePct             = 100;
g_trade[189].tpPoints                 = 6.0;
g_trade[189].slPoints                 = 6.0;
g_trade[189].livePriceDiffTrigger     = 4.0;
g_trade[189].levelOffsetPoints        = 1.5;
g_trade[189].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[189].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[189].babysit_enabled          = false;
g_trade[189].babysitStart_minute      = 0;

// encoding input magic: 10334440107000606
g_trade[190].enabled                  = true;
g_trade[190].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[190].tradeTypeId              = 3;
g_trade[190].ruleSubsetId             = 34;
g_trade[190].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[190].tradeSizePct             = 100;
g_trade[190].tpPoints                 = 6.0;
g_trade[190].slPoints                 = 6.0;
g_trade[190].livePriceDiffTrigger     = 4.0;
g_trade[190].levelOffsetPoints        = 1.0;
g_trade[190].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[190].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[190].babysit_enabled          = false;
g_trade[190].babysitStart_minute      = 0;

// encoding input magic: 10275340037000606
g_trade[191].enabled                  = true;
g_trade[191].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[191].tradeTypeId              = 2;
g_trade[191].ruleSubsetId             = 75;
g_trade[191].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[191].tradeSizePct             = 100;
g_trade[191].tpPoints                 = 6.0;
g_trade[191].slPoints                 = 6.0;
g_trade[191].livePriceDiffTrigger     = 4.0;
g_trade[191].levelOffsetPoints        = 0.3;
g_trade[191].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[191].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[191].babysit_enabled          = false;
g_trade[191].babysitStart_minute      = 0;

// encoding input magic: 10204340037000606
g_trade[192].enabled                  = true;
g_trade[192].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[192].tradeTypeId              = 2;
g_trade[192].ruleSubsetId             = 4;
g_trade[192].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[192].tradeSizePct             = 100;
g_trade[192].tpPoints                 = 6.0;
g_trade[192].slPoints                 = 6.0;
g_trade[192].livePriceDiffTrigger     = 4.0;
g_trade[192].levelOffsetPoints        = 0.3;
g_trade[192].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[192].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[192].babysit_enabled          = false;
g_trade[192].babysitStart_minute      = 0;

// encoding input magic: 10281340057000606
g_trade[193].enabled                  = true;
g_trade[193].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[193].tradeTypeId              = 2;
g_trade[193].ruleSubsetId             = 81;
g_trade[193].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[193].tradeSizePct             = 100;
g_trade[193].tpPoints                 = 6.0;
g_trade[193].slPoints                 = 6.0;
g_trade[193].livePriceDiffTrigger     = 4.0;
g_trade[193].levelOffsetPoints        = 0.5;
g_trade[193].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[193].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[193].babysit_enabled          = false;
g_trade[193].babysitStart_minute      = 0;

// encoding input magic: 10303340057000606
g_trade[194].enabled                  = true;
g_trade[194].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[194].tradeTypeId              = 3;
g_trade[194].ruleSubsetId             = 3;
g_trade[194].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[194].tradeSizePct             = 100;
g_trade[194].tpPoints                 = 6.0;
g_trade[194].slPoints                 = 6.0;
g_trade[194].livePriceDiffTrigger     = 4.0;
g_trade[194].levelOffsetPoints        = 0.5;
g_trade[194].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[194].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[194].babysit_enabled          = false;
g_trade[194].babysitStart_minute      = 0;

// encoding input magic: 10235340157000606
g_trade[195].enabled                  = true;
g_trade[195].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[195].tradeTypeId              = 2;
g_trade[195].ruleSubsetId             = 35;
g_trade[195].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[195].tradeSizePct             = 100;
g_trade[195].tpPoints                 = 6.0;
g_trade[195].slPoints                 = 6.0;
g_trade[195].livePriceDiffTrigger     = 4.0;
g_trade[195].levelOffsetPoints        = 1.5;
g_trade[195].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[195].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[195].babysit_enabled          = false;
g_trade[195].babysitStart_minute      = 0;

// encoding input magic: 10350240057000606
g_trade[196].enabled                  = true;
g_trade[196].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[196].tradeTypeId              = 3;
g_trade[196].ruleSubsetId             = 50;
g_trade[196].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[196].tradeSizePct             = 100;
g_trade[196].tpPoints                 = 6.0;
g_trade[196].slPoints                 = 6.0;
g_trade[196].livePriceDiffTrigger     = 4.0;
g_trade[196].levelOffsetPoints        = 0.5;
g_trade[196].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[196].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[196].babysit_enabled          = false;
g_trade[196].babysitStart_minute      = 0;

// encoding input magic: 10314140157000606
g_trade[197].enabled                  = true;
g_trade[197].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[197].tradeTypeId              = 3;
g_trade[197].ruleSubsetId             = 14;
g_trade[197].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[197].tradeSizePct             = 100;
g_trade[197].tpPoints                 = 6.0;
g_trade[197].slPoints                 = 6.0;
g_trade[197].livePriceDiffTrigger     = 4.0;
g_trade[197].levelOffsetPoints        = 1.5;
g_trade[197].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[197].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[197].babysit_enabled          = false;
g_trade[197].babysitStart_minute      = 0;

// encoding input magic: 10304440157000606
g_trade[198].enabled                  = true;
g_trade[198].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[198].tradeTypeId              = 3;
g_trade[198].ruleSubsetId             = 4;
g_trade[198].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[198].tradeSizePct             = 100;
g_trade[198].tpPoints                 = 6.0;
g_trade[198].slPoints                 = 6.0;
g_trade[198].livePriceDiffTrigger     = 4.0;
g_trade[198].levelOffsetPoints        = 1.5;
g_trade[198].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[198].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[198].babysit_enabled          = false;
g_trade[198].babysitStart_minute      = 0;

// encoding input magic: 10249140057000606
g_trade[199].enabled                  = true;
g_trade[199].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[199].tradeTypeId              = 2;
g_trade[199].ruleSubsetId             = 49;
g_trade[199].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[199].tradeSizePct             = 100;
g_trade[199].tpPoints                 = 6.0;
g_trade[199].slPoints                 = 6.0;
g_trade[199].livePriceDiffTrigger     = 4.0;
g_trade[199].levelOffsetPoints        = 0.5;
g_trade[199].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[199].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[199].babysit_enabled          = false;
g_trade[199].babysitStart_minute      = 0;

// encoding input magic: 10253440057000606
g_trade[200].enabled                  = true;
g_trade[200].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[200].tradeTypeId              = 2;
g_trade[200].ruleSubsetId             = 53;
g_trade[200].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[200].tradeSizePct             = 100;
g_trade[200].tpPoints                 = 6.0;
g_trade[200].slPoints                 = 6.0;
g_trade[200].livePriceDiffTrigger     = 4.0;
g_trade[200].levelOffsetPoints        = 0.5;
g_trade[200].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[200].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[200].babysit_enabled          = false;
g_trade[200].babysitStart_minute      = 0;

// encoding input magic: 11229440157000606
g_trade[201].enabled                  = true;
g_trade[201].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[201].tradeTypeId              = 12;
g_trade[201].ruleSubsetId             = 29;
g_trade[201].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[201].tradeSizePct             = 100;
g_trade[201].tpPoints                 = 6.0;
g_trade[201].slPoints                 = 6.0;
g_trade[201].livePriceDiffTrigger     = 4.0;
g_trade[201].levelOffsetPoints        = 1.5;
g_trade[201].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[201].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[201].babysit_enabled          = false;
g_trade[201].babysitStart_minute      = 0;

// encoding input magic: 10232440157000606
g_trade[202].enabled                  = true;
g_trade[202].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[202].tradeTypeId              = 2;
g_trade[202].ruleSubsetId             = 32;
g_trade[202].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[202].tradeSizePct             = 100;
g_trade[202].tpPoints                 = 6.0;
g_trade[202].slPoints                 = 6.0;
g_trade[202].livePriceDiffTrigger     = 4.0;
g_trade[202].levelOffsetPoints        = 1.5;
g_trade[202].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[202].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[202].babysit_enabled          = false;
g_trade[202].babysitStart_minute      = 0;

// encoding input magic: 10275340057000606
g_trade[203].enabled                  = true;
g_trade[203].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[203].tradeTypeId              = 2;
g_trade[203].ruleSubsetId             = 75;
g_trade[203].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[203].tradeSizePct             = 100;
g_trade[203].tpPoints                 = 6.0;
g_trade[203].slPoints                 = 6.0;
g_trade[203].livePriceDiffTrigger     = 4.0;
g_trade[203].levelOffsetPoints        = 0.5;
g_trade[203].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[203].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[203].babysit_enabled          = false;
g_trade[203].babysitStart_minute      = 0;

// encoding input magic: 10301440157000606
g_trade[204].enabled                  = true;
g_trade[204].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[204].tradeTypeId              = 3;
g_trade[204].ruleSubsetId             = 1;
g_trade[204].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[204].tradeSizePct             = 100;
g_trade[204].tpPoints                 = 6.0;
g_trade[204].slPoints                 = 6.0;
g_trade[204].livePriceDiffTrigger     = 4.0;
g_trade[204].levelOffsetPoints        = 1.5;
g_trade[204].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[204].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[204].babysit_enabled          = false;
g_trade[204].babysitStart_minute      = 0;

// encoding input magic: 10213140037000606
g_trade[205].enabled                  = true;
g_trade[205].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[205].tradeTypeId              = 2;
g_trade[205].ruleSubsetId             = 13;
g_trade[205].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[205].tradeSizePct             = 100;
g_trade[205].tpPoints                 = 6.0;
g_trade[205].slPoints                 = 6.0;
g_trade[205].livePriceDiffTrigger     = 4.0;
g_trade[205].levelOffsetPoints        = 0.3;
g_trade[205].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[205].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[205].babysit_enabled          = false;
g_trade[205].babysitStart_minute      = 0;

// encoding input magic: 11230440157000606
g_trade[206].enabled                  = true;
g_trade[206].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[206].tradeTypeId              = 12;
g_trade[206].ruleSubsetId             = 30;
g_trade[206].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[206].tradeSizePct             = 100;
g_trade[206].tpPoints                 = 6.0;
g_trade[206].slPoints                 = 6.0;
g_trade[206].livePriceDiffTrigger     = 4.0;
g_trade[206].levelOffsetPoints        = 1.5;
g_trade[206].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[206].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[206].babysit_enabled          = false;
g_trade[206].babysitStart_minute      = 0;

// encoding input magic: 10209440057000606
g_trade[207].enabled                  = true;
g_trade[207].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[207].tradeTypeId              = 2;
g_trade[207].ruleSubsetId             = 9;
g_trade[207].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[207].tradeSizePct             = 100;
g_trade[207].tpPoints                 = 6.0;
g_trade[207].slPoints                 = 6.0;
g_trade[207].livePriceDiffTrigger     = 4.0;
g_trade[207].levelOffsetPoints        = 0.5;
g_trade[207].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[207].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[207].babysit_enabled          = false;
g_trade[207].babysitStart_minute      = 0;

// encoding input magic: 10215140037000606
g_trade[208].enabled                  = true;
g_trade[208].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[208].tradeTypeId              = 2;
g_trade[208].ruleSubsetId             = 15;
g_trade[208].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[208].tradeSizePct             = 100;
g_trade[208].tpPoints                 = 6.0;
g_trade[208].slPoints                 = 6.0;
g_trade[208].livePriceDiffTrigger     = 4.0;
g_trade[208].levelOffsetPoints        = 0.3;
g_trade[208].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[208].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[208].babysit_enabled          = false;
g_trade[208].babysitStart_minute      = 0;

// encoding input magic: 10245440157000606
g_trade[209].enabled                  = true;
g_trade[209].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[209].tradeTypeId              = 2;
g_trade[209].ruleSubsetId             = 45;
g_trade[209].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[209].tradeSizePct             = 100;
g_trade[209].tpPoints                 = 6.0;
g_trade[209].slPoints                 = 6.0;
g_trade[209].livePriceDiffTrigger     = 4.0;
g_trade[209].levelOffsetPoints        = 1.5;
g_trade[209].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[209].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[209].babysit_enabled          = false;
g_trade[209].babysitStart_minute      = 0;

// encoding input magic: 10216340157000606
g_trade[210].enabled                  = true;
g_trade[210].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[210].tradeTypeId              = 2;
g_trade[210].ruleSubsetId             = 16;
g_trade[210].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[210].tradeSizePct             = 100;
g_trade[210].tpPoints                 = 6.0;
g_trade[210].slPoints                 = 6.0;
g_trade[210].livePriceDiffTrigger     = 4.0;
g_trade[210].levelOffsetPoints        = 1.5;
g_trade[210].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[210].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[210].babysit_enabled          = false;
g_trade[210].babysitStart_minute      = 0;

// encoding input magic: 10214340157000606
g_trade[211].enabled                  = true;
g_trade[211].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[211].tradeTypeId              = 2;
g_trade[211].ruleSubsetId             = 14;
g_trade[211].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[211].tradeSizePct             = 100;
g_trade[211].tpPoints                 = 6.0;
g_trade[211].slPoints                 = 6.0;
g_trade[211].livePriceDiffTrigger     = 4.0;
g_trade[211].levelOffsetPoints        = 1.5;
g_trade[211].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[211].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[211].babysit_enabled          = false;
g_trade[211].babysitStart_minute      = 0;

// encoding input magic: 11207240107000606
g_trade[212].enabled                  = true;
g_trade[212].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[212].tradeTypeId              = 12;
g_trade[212].ruleSubsetId             = 7;
g_trade[212].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[212].tradeSizePct             = 100;
g_trade[212].tpPoints                 = 6.0;
g_trade[212].slPoints                 = 6.0;
g_trade[212].livePriceDiffTrigger     = 4.0;
g_trade[212].levelOffsetPoints        = 1.0;
g_trade[212].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[212].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[212].babysit_enabled          = false;
g_trade[212].babysitStart_minute      = 0;

// encoding input magic: 10331440057000606
g_trade[213].enabled                  = true;
g_trade[213].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[213].tradeTypeId              = 3;
g_trade[213].ruleSubsetId             = 31;
g_trade[213].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[213].tradeSizePct             = 100;
g_trade[213].tpPoints                 = 6.0;
g_trade[213].slPoints                 = 6.0;
g_trade[213].livePriceDiffTrigger     = 4.0;
g_trade[213].levelOffsetPoints        = 0.5;
g_trade[213].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[213].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[213].babysit_enabled          = false;
g_trade[213].babysitStart_minute      = 0;

// encoding input magic: 10350240037000606
g_trade[214].enabled                  = true;
g_trade[214].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[214].tradeTypeId              = 3;
g_trade[214].ruleSubsetId             = 50;
g_trade[214].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[214].tradeSizePct             = 100;
g_trade[214].tpPoints                 = 6.0;
g_trade[214].slPoints                 = 6.0;
g_trade[214].livePriceDiffTrigger     = 4.0;
g_trade[214].levelOffsetPoints        = 0.3;
g_trade[214].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[214].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[214].babysit_enabled          = false;
g_trade[214].babysitStart_minute      = 0;

// encoding input magic: 10288340057000606
g_trade[215].enabled                  = true;
g_trade[215].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[215].tradeTypeId              = 2;
g_trade[215].ruleSubsetId             = 88;
g_trade[215].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[215].tradeSizePct             = 100;
g_trade[215].tpPoints                 = 6.0;
g_trade[215].slPoints                 = 6.0;
g_trade[215].livePriceDiffTrigger     = 4.0;
g_trade[215].levelOffsetPoints        = 0.5;
g_trade[215].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[215].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[215].babysit_enabled          = false;
g_trade[215].babysitStart_minute      = 0;

// encoding input magic: 10312440107000606
g_trade[216].enabled                  = true;
g_trade[216].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[216].tradeTypeId              = 3;
g_trade[216].ruleSubsetId             = 12;
g_trade[216].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[216].tradeSizePct             = 100;
g_trade[216].tpPoints                 = 6.0;
g_trade[216].slPoints                 = 6.0;
g_trade[216].livePriceDiffTrigger     = 4.0;
g_trade[216].levelOffsetPoints        = 1.0;
g_trade[216].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[216].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[216].babysit_enabled          = false;
g_trade[216].babysitStart_minute      = 0;

// encoding input magic: 11207440157000606
g_trade[217].enabled                  = true;
g_trade[217].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[217].tradeTypeId              = 12;
g_trade[217].ruleSubsetId             = 7;
g_trade[217].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[217].tradeSizePct             = 100;
g_trade[217].tpPoints                 = 6.0;
g_trade[217].slPoints                 = 6.0;
g_trade[217].livePriceDiffTrigger     = 4.0;
g_trade[217].levelOffsetPoints        = 1.5;
g_trade[217].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[217].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[217].babysit_enabled          = false;
g_trade[217].babysitStart_minute      = 0;

// encoding input magic: 10234140157000606
g_trade[218].enabled                  = true;
g_trade[218].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[218].tradeTypeId              = 2;
g_trade[218].ruleSubsetId             = 34;
g_trade[218].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[218].tradeSizePct             = 100;
g_trade[218].tpPoints                 = 6.0;
g_trade[218].slPoints                 = 6.0;
g_trade[218].livePriceDiffTrigger     = 4.0;
g_trade[218].levelOffsetPoints        = 1.5;
g_trade[218].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[218].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[218].babysit_enabled          = false;
g_trade[218].babysitStart_minute      = 0;

// encoding input magic: 10236140037000606
g_trade[219].enabled                  = true;
g_trade[219].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[219].tradeTypeId              = 2;
g_trade[219].ruleSubsetId             = 36;
g_trade[219].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[219].tradeSizePct             = 100;
g_trade[219].tpPoints                 = 6.0;
g_trade[219].slPoints                 = 6.0;
g_trade[219].livePriceDiffTrigger     = 4.0;
g_trade[219].levelOffsetPoints        = 0.3;
g_trade[219].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[219].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[219].babysit_enabled          = false;
g_trade[219].babysitStart_minute      = 0;

// encoding input magic: 10289340057000606
g_trade[220].enabled                  = true;
g_trade[220].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[220].tradeTypeId              = 2;
g_trade[220].ruleSubsetId             = 89;
g_trade[220].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[220].tradeSizePct             = 100;
g_trade[220].tpPoints                 = 6.0;
g_trade[220].slPoints                 = 6.0;
g_trade[220].livePriceDiffTrigger     = 4.0;
g_trade[220].levelOffsetPoints        = 0.5;
g_trade[220].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[220].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[220].babysit_enabled          = false;
g_trade[220].babysitStart_minute      = 0;

// encoding input magic: 10318140157000606
g_trade[221].enabled                  = true;
g_trade[221].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[221].tradeTypeId              = 3;
g_trade[221].ruleSubsetId             = 18;
g_trade[221].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[221].tradeSizePct             = 100;
g_trade[221].tpPoints                 = 6.0;
g_trade[221].slPoints                 = 6.0;
g_trade[221].livePriceDiffTrigger     = 4.0;
g_trade[221].levelOffsetPoints        = 1.5;
g_trade[221].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[221].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[221].babysit_enabled          = false;
g_trade[221].babysitStart_minute      = 0;

// encoding input magic: 10344440157000606
g_trade[222].enabled                  = true;
g_trade[222].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[222].tradeTypeId              = 3;
g_trade[222].ruleSubsetId             = 44;
g_trade[222].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[222].tradeSizePct             = 100;
g_trade[222].tpPoints                 = 6.0;
g_trade[222].slPoints                 = 6.0;
g_trade[222].livePriceDiffTrigger     = 4.0;
g_trade[222].levelOffsetPoints        = 1.5;
g_trade[222].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[222].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[222].babysit_enabled          = false;
g_trade[222].babysitStart_minute      = 0;

// encoding input magic: 10333440057000606
g_trade[223].enabled                  = true;
g_trade[223].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[223].tradeTypeId              = 3;
g_trade[223].ruleSubsetId             = 33;
g_trade[223].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[223].tradeSizePct             = 100;
g_trade[223].tpPoints                 = 6.0;
g_trade[223].slPoints                 = 6.0;
g_trade[223].livePriceDiffTrigger     = 4.0;
g_trade[223].levelOffsetPoints        = 0.5;
g_trade[223].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[223].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[223].babysit_enabled          = false;
g_trade[223].babysitStart_minute      = 0;

// encoding input magic: 10347440107000606
g_trade[224].enabled                  = true;
g_trade[224].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[224].tradeTypeId              = 3;
g_trade[224].ruleSubsetId             = 47;
g_trade[224].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[224].tradeSizePct             = 100;
g_trade[224].tpPoints                 = 6.0;
g_trade[224].slPoints                 = 6.0;
g_trade[224].livePriceDiffTrigger     = 4.0;
g_trade[224].levelOffsetPoints        = 1.0;
g_trade[224].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[224].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[224].babysit_enabled          = false;
g_trade[224].babysitStart_minute      = 0;

// encoding input magic: 10290340057000606
g_trade[225].enabled                  = true;
g_trade[225].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[225].tradeTypeId              = 2;
g_trade[225].ruleSubsetId             = 90;
g_trade[225].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[225].tradeSizePct             = 100;
g_trade[225].tpPoints                 = 6.0;
g_trade[225].slPoints                 = 6.0;
g_trade[225].livePriceDiffTrigger     = 4.0;
g_trade[225].levelOffsetPoints        = 0.5;
g_trade[225].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[225].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[225].babysit_enabled          = false;
g_trade[225].babysitStart_minute      = 0;

// encoding input magic: 10259240107000606
g_trade[226].enabled                  = true;
g_trade[226].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[226].tradeTypeId              = 2;
g_trade[226].ruleSubsetId             = 59;
g_trade[226].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[226].tradeSizePct             = 100;
g_trade[226].tpPoints                 = 6.0;
g_trade[226].slPoints                 = 6.0;
g_trade[226].livePriceDiffTrigger     = 4.0;
g_trade[226].levelOffsetPoints        = 1.0;
g_trade[226].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[226].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[226].babysit_enabled          = false;
g_trade[226].babysitStart_minute      = 0;

// encoding input magic: 10282340057000606
g_trade[227].enabled                  = true;
g_trade[227].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[227].tradeTypeId              = 2;
g_trade[227].ruleSubsetId             = 82;
g_trade[227].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[227].tradeSizePct             = 100;
g_trade[227].tpPoints                 = 6.0;
g_trade[227].slPoints                 = 6.0;
g_trade[227].livePriceDiffTrigger     = 4.0;
g_trade[227].levelOffsetPoints        = 0.5;
g_trade[227].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[227].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[227].babysit_enabled          = false;
g_trade[227].babysitStart_minute      = 0;

// encoding input magic: 10330440057000606
g_trade[228].enabled                  = true;
g_trade[228].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[228].tradeTypeId              = 3;
g_trade[228].ruleSubsetId             = 30;
g_trade[228].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[228].tradeSizePct             = 100;
g_trade[228].tpPoints                 = 6.0;
g_trade[228].slPoints                 = 6.0;
g_trade[228].livePriceDiffTrigger     = 4.0;
g_trade[228].levelOffsetPoints        = 0.5;
g_trade[228].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[228].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[228].babysit_enabled          = false;
g_trade[228].babysitStart_minute      = 0;

// encoding input magic: 10329440107000606
g_trade[229].enabled                  = true;
g_trade[229].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[229].tradeTypeId              = 3;
g_trade[229].ruleSubsetId             = 29;
g_trade[229].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[229].tradeSizePct             = 100;
g_trade[229].tpPoints                 = 6.0;
g_trade[229].slPoints                 = 6.0;
g_trade[229].livePriceDiffTrigger     = 4.0;
g_trade[229].levelOffsetPoints        = 1.0;
g_trade[229].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[229].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[229].babysit_enabled          = false;
g_trade[229].babysitStart_minute      = 0;

// encoding input magic: 10216340107000606
g_trade[230].enabled                  = true;
g_trade[230].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[230].tradeTypeId              = 2;
g_trade[230].ruleSubsetId             = 16;
g_trade[230].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[230].tradeSizePct             = 100;
g_trade[230].tpPoints                 = 6.0;
g_trade[230].slPoints                 = 6.0;
g_trade[230].livePriceDiffTrigger     = 4.0;
g_trade[230].levelOffsetPoints        = 1.0;
g_trade[230].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[230].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[230].babysit_enabled          = false;
g_trade[230].babysitStart_minute      = 0;

// encoding input magic: 10280340057000606
g_trade[231].enabled                  = true;
g_trade[231].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[231].tradeTypeId              = 2;
g_trade[231].ruleSubsetId             = 80;
g_trade[231].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[231].tradeSizePct             = 100;
g_trade[231].tpPoints                 = 6.0;
g_trade[231].slPoints                 = 6.0;
g_trade[231].livePriceDiffTrigger     = 4.0;
g_trade[231].levelOffsetPoints        = 0.5;
g_trade[231].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[231].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[231].babysit_enabled          = false;
g_trade[231].babysitStart_minute      = 0;

// encoding input magic: 11210340037000606
g_trade[232].enabled                  = true;
g_trade[232].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[232].tradeTypeId              = 12;
g_trade[232].ruleSubsetId             = 10;
g_trade[232].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[232].tradeSizePct             = 100;
g_trade[232].tpPoints                 = 6.0;
g_trade[232].slPoints                 = 6.0;
g_trade[232].livePriceDiffTrigger     = 4.0;
g_trade[232].levelOffsetPoints        = 0.3;
g_trade[232].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[232].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[232].babysit_enabled          = false;
g_trade[232].babysitStart_minute      = 0;

// encoding input magic: 10331440037000606
g_trade[233].enabled                  = true;
g_trade[233].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[233].tradeTypeId              = 3;
g_trade[233].ruleSubsetId             = 31;
g_trade[233].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[233].tradeSizePct             = 100;
g_trade[233].tpPoints                 = 6.0;
g_trade[233].slPoints                 = 6.0;
g_trade[233].livePriceDiffTrigger     = 4.0;
g_trade[233].levelOffsetPoints        = 0.3;
g_trade[233].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[233].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[233].babysit_enabled          = false;
g_trade[233].babysitStart_minute      = 0;

// encoding input magic: 10334340057000606
g_trade[234].enabled                  = true;
g_trade[234].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[234].tradeTypeId              = 3;
g_trade[234].ruleSubsetId             = 34;
g_trade[234].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[234].tradeSizePct             = 100;
g_trade[234].tpPoints                 = 6.0;
g_trade[234].slPoints                 = 6.0;
g_trade[234].livePriceDiffTrigger     = 4.0;
g_trade[234].levelOffsetPoints        = 0.5;
g_trade[234].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[234].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[234].babysit_enabled          = false;
g_trade[234].babysitStart_minute      = 0;

// encoding input magic: 10337440107000606
g_trade[235].enabled                  = true;
g_trade[235].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[235].tradeTypeId              = 3;
g_trade[235].ruleSubsetId             = 37;
g_trade[235].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[235].tradeSizePct             = 100;
g_trade[235].tpPoints                 = 6.0;
g_trade[235].slPoints                 = 6.0;
g_trade[235].livePriceDiffTrigger     = 4.0;
g_trade[235].levelOffsetPoints        = 1.0;
g_trade[235].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[235].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[235].babysit_enabled          = false;
g_trade[235].babysitStart_minute      = 0;

// encoding input magic: 11214440157000606
g_trade[236].enabled                  = true;
g_trade[236].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[236].tradeTypeId              = 12;
g_trade[236].ruleSubsetId             = 14;
g_trade[236].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[236].tradeSizePct             = 100;
g_trade[236].tpPoints                 = 6.0;
g_trade[236].slPoints                 = 6.0;
g_trade[236].livePriceDiffTrigger     = 4.0;
g_trade[236].levelOffsetPoints        = 1.5;
g_trade[236].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[236].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[236].babysit_enabled          = false;
g_trade[236].babysitStart_minute      = 0;

// encoding input magic: 10232440057000606
g_trade[237].enabled                  = true;
g_trade[237].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[237].tradeTypeId              = 2;
g_trade[237].ruleSubsetId             = 32;
g_trade[237].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[237].tradeSizePct             = 100;
g_trade[237].tpPoints                 = 6.0;
g_trade[237].slPoints                 = 6.0;
g_trade[237].livePriceDiffTrigger     = 4.0;
g_trade[237].levelOffsetPoints        = 0.5;
g_trade[237].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[237].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[237].babysit_enabled          = false;
g_trade[237].babysitStart_minute      = 0;

// encoding input magic: 10210440057000606
g_trade[238].enabled                  = true;
g_trade[238].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[238].tradeTypeId              = 2;
g_trade[238].ruleSubsetId             = 10;
g_trade[238].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[238].tradeSizePct             = 100;
g_trade[238].tpPoints                 = 6.0;
g_trade[238].slPoints                 = 6.0;
g_trade[238].livePriceDiffTrigger     = 4.0;
g_trade[238].levelOffsetPoints        = 0.5;
g_trade[238].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[238].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[238].babysit_enabled          = false;
g_trade[238].babysitStart_minute      = 0;

// encoding input magic: 10273340037000606
g_trade[239].enabled                  = true;
g_trade[239].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[239].tradeTypeId              = 2;
g_trade[239].ruleSubsetId             = 73;
g_trade[239].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[239].tradeSizePct             = 100;
g_trade[239].tpPoints                 = 6.0;
g_trade[239].slPoints                 = 6.0;
g_trade[239].livePriceDiffTrigger     = 4.0;
g_trade[239].levelOffsetPoints        = 0.3;
g_trade[239].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[239].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[239].babysit_enabled          = false;
g_trade[239].babysitStart_minute      = 0;

// encoding input magic: 10347440057000606
g_trade[240].enabled                  = true;
g_trade[240].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[240].tradeTypeId              = 3;
g_trade[240].ruleSubsetId             = 47;
g_trade[240].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[240].tradeSizePct             = 100;
g_trade[240].tpPoints                 = 6.0;
g_trade[240].slPoints                 = 6.0;
g_trade[240].livePriceDiffTrigger     = 4.0;
g_trade[240].levelOffsetPoints        = 0.5;
g_trade[240].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[240].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[240].babysit_enabled          = false;
g_trade[240].babysitStart_minute      = 0;

// encoding input magic: 10330440157000606
g_trade[241].enabled                  = true;
g_trade[241].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[241].tradeTypeId              = 3;
g_trade[241].ruleSubsetId             = 30;
g_trade[241].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[241].tradeSizePct             = 100;
g_trade[241].tpPoints                 = 6.0;
g_trade[241].slPoints                 = 6.0;
g_trade[241].livePriceDiffTrigger     = 4.0;
g_trade[241].levelOffsetPoints        = 1.5;
g_trade[241].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[241].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[241].babysit_enabled          = false;
g_trade[241].babysitStart_minute      = 0;

// encoding input magic: 10266440157000606
g_trade[242].enabled                  = true;
g_trade[242].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[242].tradeTypeId              = 2;
g_trade[242].ruleSubsetId             = 66;
g_trade[242].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[242].tradeSizePct             = 100;
g_trade[242].tpPoints                 = 6.0;
g_trade[242].slPoints                 = 6.0;
g_trade[242].livePriceDiffTrigger     = 4.0;
g_trade[242].levelOffsetPoints        = 1.5;
g_trade[242].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[242].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[242].babysit_enabled          = false;
g_trade[242].babysitStart_minute      = 0;

// encoding input magic: 10305340037000606
g_trade[243].enabled                  = true;
g_trade[243].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[243].tradeTypeId              = 3;
g_trade[243].ruleSubsetId             = 5;
g_trade[243].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[243].tradeSizePct             = 100;
g_trade[243].tpPoints                 = 6.0;
g_trade[243].slPoints                 = 6.0;
g_trade[243].livePriceDiffTrigger     = 4.0;
g_trade[243].levelOffsetPoints        = 0.3;
g_trade[243].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[243].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[243].babysit_enabled          = false;
g_trade[243].babysitStart_minute      = 0;

// encoding input magic: 10289340037000606
g_trade[244].enabled                  = true;
g_trade[244].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[244].tradeTypeId              = 2;
g_trade[244].ruleSubsetId             = 89;
g_trade[244].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[244].tradeSizePct             = 100;
g_trade[244].tpPoints                 = 6.0;
g_trade[244].slPoints                 = 6.0;
g_trade[244].livePriceDiffTrigger     = 4.0;
g_trade[244].levelOffsetPoints        = 0.3;
g_trade[244].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[244].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[244].babysit_enabled          = false;
g_trade[244].babysitStart_minute      = 0;

// encoding input magic: 10343140157000606
g_trade[245].enabled                  = true;
g_trade[245].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[245].tradeTypeId              = 3;
g_trade[245].ruleSubsetId             = 43;
g_trade[245].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[245].tradeSizePct             = 100;
g_trade[245].tpPoints                 = 6.0;
g_trade[245].slPoints                 = 6.0;
g_trade[245].livePriceDiffTrigger     = 4.0;
g_trade[245].levelOffsetPoints        = 1.5;
g_trade[245].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[245].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[245].babysit_enabled          = false;
g_trade[245].babysitStart_minute      = 0;

// encoding input magic: 10236140057000606
g_trade[246].enabled                  = true;
g_trade[246].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[246].tradeTypeId              = 2;
g_trade[246].ruleSubsetId             = 36;
g_trade[246].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[246].tradeSizePct             = 100;
g_trade[246].tpPoints                 = 6.0;
g_trade[246].slPoints                 = 6.0;
g_trade[246].livePriceDiffTrigger     = 4.0;
g_trade[246].levelOffsetPoints        = 0.5;
g_trade[246].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[246].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[246].babysit_enabled          = false;
g_trade[246].babysitStart_minute      = 0;

// encoding input magic: 10307440157000606
g_trade[247].enabled                  = true;
g_trade[247].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[247].tradeTypeId              = 3;
g_trade[247].ruleSubsetId             = 7;
g_trade[247].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[247].tradeSizePct             = 100;
g_trade[247].tpPoints                 = 6.0;
g_trade[247].slPoints                 = 6.0;
g_trade[247].livePriceDiffTrigger     = 4.0;
g_trade[247].levelOffsetPoints        = 1.5;
g_trade[247].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[247].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[247].babysit_enabled          = false;
g_trade[247].babysitStart_minute      = 0;

// encoding input magic: 10305440157000606
g_trade[248].enabled                  = true;
g_trade[248].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[248].tradeTypeId              = 3;
g_trade[248].ruleSubsetId             = 5;
g_trade[248].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[248].tradeSizePct             = 100;
g_trade[248].tpPoints                 = 6.0;
g_trade[248].slPoints                 = 6.0;
g_trade[248].livePriceDiffTrigger     = 4.0;
g_trade[248].levelOffsetPoints        = 1.5;
g_trade[248].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[248].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[248].babysit_enabled          = false;
g_trade[248].babysitStart_minute      = 0;

// encoding input magic: 10203340037000606
g_trade[249].enabled                  = true;
g_trade[249].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[249].tradeTypeId              = 2;
g_trade[249].ruleSubsetId             = 3;
g_trade[249].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[249].tradeSizePct             = 100;
g_trade[249].tpPoints                 = 6.0;
g_trade[249].slPoints                 = 6.0;
g_trade[249].livePriceDiffTrigger     = 4.0;
g_trade[249].levelOffsetPoints        = 0.3;
g_trade[249].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[249].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[249].babysit_enabled          = false;
g_trade[249].babysitStart_minute      = 0;

// encoding input magic: 10247140157000606
g_trade[250].enabled                  = true;
g_trade[250].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[250].tradeTypeId              = 2;
g_trade[250].ruleSubsetId             = 47;
g_trade[250].sessionPdCategory        = MAGIC_IS_ON_AND_PD_GREEN;
g_trade[250].tradeSizePct             = 100;
g_trade[250].tpPoints                 = 6.0;
g_trade[250].slPoints                 = 6.0;
g_trade[250].livePriceDiffTrigger     = 4.0;
g_trade[250].levelOffsetPoints        = 1.5;
g_trade[250].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[250].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[250].babysit_enabled          = false;
g_trade[250].babysitStart_minute      = 0;

// encoding input magic: 10235340107000606
g_trade[251].enabled                  = true;
g_trade[251].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[251].tradeTypeId              = 2;
g_trade[251].ruleSubsetId             = 35;
g_trade[251].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[251].tradeSizePct             = 100;
g_trade[251].tpPoints                 = 6.0;
g_trade[251].slPoints                 = 6.0;
g_trade[251].livePriceDiffTrigger     = 4.0;
g_trade[251].levelOffsetPoints        = 1.0;
g_trade[251].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[251].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[251].babysit_enabled          = false;
g_trade[251].babysitStart_minute      = 0;

// encoding input magic: 10280340107000606
g_trade[252].enabled                  = true;
g_trade[252].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[252].tradeTypeId              = 2;
g_trade[252].ruleSubsetId             = 80;
g_trade[252].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[252].tradeSizePct             = 100;
g_trade[252].tpPoints                 = 6.0;
g_trade[252].slPoints                 = 6.0;
g_trade[252].livePriceDiffTrigger     = 4.0;
g_trade[252].levelOffsetPoints        = 1.0;
g_trade[252].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[252].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[252].babysit_enabled          = false;
g_trade[252].babysitStart_minute      = 0;

// encoding input magic: 10302340057000606
g_trade[253].enabled                  = true;
g_trade[253].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[253].tradeTypeId              = 3;
g_trade[253].ruleSubsetId             = 2;
g_trade[253].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_GREEN;
g_trade[253].tradeSizePct             = 100;
g_trade[253].tpPoints                 = 6.0;
g_trade[253].slPoints                 = 6.0;
g_trade[253].livePriceDiffTrigger     = 4.0;
g_trade[253].levelOffsetPoints        = 0.5;
g_trade[253].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[253].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[253].babysit_enabled          = false;
g_trade[253].babysitStart_minute      = 0;

// encoding input magic: 10226240157000606
g_trade[254].enabled                  = true;
g_trade[254].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[254].tradeTypeId              = 2;
g_trade[254].ruleSubsetId             = 26;
g_trade[254].sessionPdCategory        = MAGIC_IS_ON_AND_PD_RED;
g_trade[254].tradeSizePct             = 100;
g_trade[254].tpPoints                 = 6.0;
g_trade[254].slPoints                 = 6.0;
g_trade[254].livePriceDiffTrigger     = 4.0;
g_trade[254].levelOffsetPoints        = 1.5;
g_trade[254].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[254].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[254].babysit_enabled          = false;
g_trade[254].babysitStart_minute      = 0;

// encoding input magic: 10334440037000606
g_trade[255].enabled                  = true;
g_trade[255].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[255].tradeTypeId              = 3;
g_trade[255].ruleSubsetId             = 34;
g_trade[255].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[255].tradeSizePct             = 100;
g_trade[255].tpPoints                 = 6.0;
g_trade[255].slPoints                 = 6.0;
g_trade[255].livePriceDiffTrigger     = 4.0;
g_trade[255].levelOffsetPoints        = 0.3;
g_trade[255].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[255].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[255].babysit_enabled          = false;
g_trade[255].babysitStart_minute      = 0;

// encoding input magic: 10233440107000606
g_trade[256].enabled                  = true;
g_trade[256].tradeDirectionCategory   = MAGIC_TRADE_LONG;
g_trade[256].tradeTypeId              = 2;
g_trade[256].ruleSubsetId             = 33;
g_trade[256].sessionPdCategory        = MAGIC_IS_RTH_AND_PD_RED;
g_trade[256].tradeSizePct             = 100;
g_trade[256].tpPoints                 = 6.0;
g_trade[256].slPoints                 = 6.0;
g_trade[256].livePriceDiffTrigger     = 4.0;
g_trade[256].levelOffsetPoints        = 1.0;
g_trade[256].bannedRanges             = "22,0,23,59;0,0,1,0";
g_trade[256].levelProximityFocus      = TRADE_LEVEL_FOCUS_BELOW;
g_trade[256].babysit_enabled          = false;
g_trade[256].babysitStart_minute      = 0;

//tradeDeleter_ends_here. AI never edit this comment
//bookmark2tradeend
}

//+------------------------------------------------------------------+
//| Composite magic as long must print with exactly COMPOSITE_MAGIC_STRING_LEN decimal digits. |
//+------------------------------------------------------------------+
void AssertCompositeMagicDecimalWidthOrFatal(const long compositeMagic, const int variantIdxForMsg)
{
   string magicDecimalString = IntegerToString(compositeMagic);
   int decimalDigitCount = (int)StringLen(magicDecimalString);
   if(decimalDigitCount != COMPOSITE_MAGIC_STRING_LEN)
      FatalError(StringFormat("g_trade[%d]: composite magic has %d decimal digits (required %d) — BuildBetterMagicNumber",
         variantIdxForMsg, decimalDigitCount, COMPOSITE_MAGIC_STRING_LEN));
}

//+------------------------------------------------------------------+
//| Fill g_trade[i].fullMagic via BuildBetterMagicNumber (StringFormat path). Call once after row fields validated (OnInit only). |
//+------------------------------------------------------------------+
void RebuildVariantFullMagicCache()
{
   for(int i = 0; i < TRADE_VARIANT_COUNT; i++)
   {
      if(g_trade[i].tradeTypeId == 0)
      {
         g_trade[i].fullMagic = 0;
         continue;
      }
      g_trade[i].fullMagic = BuildBetterMagicNumber(
         g_trade[i].tradeDirectionCategory,
         g_trade[i].tradeTypeId,
         g_trade[i].ruleSubsetId,
         g_trade[i].sessionPdCategory,
         g_trade[i].livePriceDiffTrigger,
         g_trade[i].levelOffsetPoints,
         g_trade[i].babysit_enabled,
         g_trade[i].babysitStart_minute,
         g_trade[i].tpPoints,
         g_trade[i].slPoints);
   }
}

//+------------------------------------------------------------------+
//| Cached composite magic for variant row (see RebuildVariantFullMagicCache). |
//+------------------------------------------------------------------+
long BuildMagicForVariant(int variantIdx)
{
   if(variantIdx < 0 || variantIdx >= TRADE_VARIANT_COUNT)
      return 0;
   return g_trade[variantIdx].fullMagic;
}

//+------------------------------------------------------------------+
//| True if magic matches any configured variant’s BuildMagicForVariant. |
//+------------------------------------------------------------------+
bool IsVariantTradeCompositeMagic(long compositeMagic)
{
   for(int variantIdx = 0; variantIdx < TRADE_VARIANT_COUNT; variantIdx++)
      if(BuildMagicForVariant(variantIdx) == compositeMagic) return true;
   return false;
}

//+------------------------------------------------------------------+
//| g_trade[] index whose BuildMagicForVariant matches compositeMagic, or -1. |
//+------------------------------------------------------------------+
int FindVariantIndexForCompositeMagic(const long compositeMagic)
{
   for(int variantIdx = 0; variantIdx < TRADE_VARIANT_COUNT; variantIdx++)
      if(BuildMagicForVariant(variantIdx) == compositeMagic) return variantIdx;
   return -1;
}

//+------------------------------------------------------------------+
//| OnInit: validate unified magic inputs + variant table; unique composite magics per row. |
//+------------------------------------------------------------------+
void ValidateMagicCompositionOnInit()
{
   SyncTradeVariantsFromInputs();

   for(int variantIdx = 0; variantIdx < TRADE_VARIANT_COUNT; variantIdx++)
   {
      // Skip validation for uninitialized/nonexistent variants, identified by a zero tradeTypeId.
      if(g_trade[variantIdx].tradeTypeId == 0)
         continue;

      if(g_trade[variantIdx].tradeDirectionCategory < 1 || g_trade[variantIdx].tradeDirectionCategory > 4)
         FatalError(StringFormat("g_trade[%d].tradeDirectionCategory must be 1..4: 1=buy limit, 2=sell limit, 3=sell stop, 4=buy stop", variantIdx));
      if(g_trade[variantIdx].tradeTypeId < 1 || g_trade[variantIdx].tradeTypeId > 99)
         FatalError(StringFormat("g_trade[%d].tradeTypeId must be 1..99", variantIdx));
      if(g_trade[variantIdx].ruleSubsetId < 1 || g_trade[variantIdx].ruleSubsetId > 99)
         FatalError(StringFormat("g_trade[%d].ruleSubsetId must be 1..99", variantIdx));
      if(g_trade[variantIdx].sessionPdCategory < 1 || g_trade[variantIdx].sessionPdCategory > 4)
         FatalError(StringFormat("g_trade[%d].sessionPdCategory must be 1..4 (MAGIC_IS_ON_AND_PD_GREEN … MAGIC_IS_RTH_AND_PD_RED)", variantIdx));
      if(g_trade[variantIdx].livePriceDiffTrigger < 0.1 || g_trade[variantIdx].livePriceDiffTrigger > 9.9)
         FatalError(StringFormat("g_trade[%d].livePriceDiffTrigger must be 0.1..9.9 (two-digit tenths field in composite)", variantIdx));
      if(g_trade[variantIdx].levelOffsetPoints < 0.1 || g_trade[variantIdx].levelOffsetPoints > 9.9)
         FatalError(StringFormat("g_trade[%d].levelOffsetPoints must be 0.1..9.9 (two-digit tenths field in composite)", variantIdx));
      if(g_trade[variantIdx].tpPoints < 1.0 || g_trade[variantIdx].tpPoints > 99.0)
         FatalError(StringFormat("g_trade[%d].tpPoints must be 1..99", variantIdx));
      if(MathAbs(g_trade[variantIdx].tpPoints - MathRound(g_trade[variantIdx].tpPoints)) > 1e-5)
         FatalError(StringFormat("g_trade[%d].tpPoints must be a whole integer (e.g. 12), not fractional", variantIdx));
      if(g_trade[variantIdx].slPoints < 1.0 || g_trade[variantIdx].slPoints > 99.0)
         FatalError(StringFormat("g_trade[%d].slPoints must be 1..99", variantIdx));
      if(MathAbs(g_trade[variantIdx].slPoints - MathRound(g_trade[variantIdx].slPoints)) > 1e-5)
         FatalError(StringFormat("g_trade[%d].slPoints must be a whole integer (e.g. 12), not fractional", variantIdx));
      if(g_trade[variantIdx].levelProximityFocus != TRADE_LEVEL_FOCUS_BELOW &&
         g_trade[variantIdx].levelProximityFocus != TRADE_LEVEL_FOCUS_ABOVE &&
         g_trade[variantIdx].levelProximityFocus != TRADE_LEVEL_FOCUS_BOTH)
         FatalError(StringFormat("g_trade[%d].levelProximityFocus must be 1=below 2=above 3=both, got %d", variantIdx, g_trade[variantIdx].levelProximityFocus));
      if(g_trade[variantIdx].babysit_enabled &&
         (g_trade[variantIdx].babysitStart_minute < 1 || g_trade[variantIdx].babysitStart_minute > 99))
         FatalError(StringFormat("g_trade[%d]: babysit_enabled requires babysitStart_minute in 1..99, got %d", variantIdx, g_trade[variantIdx].babysitStart_minute));
   }

   RebuildVariantFullMagicCache();

   for(int variantIdx = 0; variantIdx < TRADE_VARIANT_COUNT; variantIdx++)
   {
      // Skip validation for uninitialized/nonexistent variants.
      if(g_trade[variantIdx].tradeTypeId == 0)
         continue;

      long rowCompositeMagic = BuildMagicForVariant(variantIdx);
      AssertCompositeMagicDecimalWidthOrFatal(rowCompositeMagic, variantIdx);
      TradeKey parsedKey = ParseCompositeMagic(rowCompositeMagic);
      if(parsedKey.direction != g_trade[variantIdx].tradeDirectionCategory)
         FatalError(StringFormat("ParseCompositeMagic: direction mismatch vs g_trade[%d].tradeDirectionCategory", variantIdx));
      if(parsedKey.tradeType != g_trade[variantIdx].tradeTypeId)
         FatalError("ParseCompositeMagic: tradeType mismatch variant row");
      if(parsedKey.subset != g_trade[variantIdx].ruleSubsetId)
         FatalError("ParseCompositeMagic: subset mismatch variant row");
      if(parsedKey.sessionPd != g_trade[variantIdx].sessionPdCategory)
         FatalError(StringFormat("ParseCompositeMagic: sessionPd mismatch vs g_trade[%d].sessionPdCategory", variantIdx));
      int expectedTriggerTenths = EncodeMagicTwoDigitTenths(g_trade[variantIdx].livePriceDiffTrigger);
      int expectedOffsetTenths = EncodeMagicTwoDigitTenths(g_trade[variantIdx].levelOffsetPoints);
      if(parsedKey.triggerTenths != expectedTriggerTenths)
         FatalError(StringFormat("ParseCompositeMagic: trigger block mismatch vs g_trade[%d].livePriceDiffTrigger", variantIdx));
      if(parsedKey.offsetTenths != expectedOffsetTenths)
         FatalError(StringFormat("ParseCompositeMagic: offset block mismatch vs g_trade[%d].levelOffsetPoints", variantIdx));
      int expectBabysit = 700;
      if(g_trade[variantIdx].babysit_enabled)
         expectBabysit = 800 + g_trade[variantIdx].babysitStart_minute;
      if(parsedKey.babysitEncoded != expectBabysit)
         FatalError(StringFormat("ParseCompositeMagic: babysit block mismatch vs g_trade[%d] (encoded %d, expected %d)", variantIdx, parsedKey.babysitEncoded, expectBabysit));
      int expectTp = (int)MathRound(g_trade[variantIdx].tpPoints);
      int expectSl = (int)MathRound(g_trade[variantIdx].slPoints);
      if(parsedKey.tpPointsEncoded != expectTp)
         FatalError(StringFormat("ParseCompositeMagic: TP points mismatch vs g_trade[%d].tpPoints", variantIdx));
      if(parsedKey.slPointsEncoded != expectSl)
         FatalError(StringFormat("ParseCompositeMagic: SL points mismatch vs g_trade[%d].slPoints", variantIdx));
   }

   for(int variantIdx = 0; variantIdx < TRADE_VARIANT_COUNT; variantIdx++)
   {
      long magic1 = BuildMagicForVariant(variantIdx);
      if(magic1 == 0) // Skip uninitialized variants
         continue;

      for(int otherVariantIdx = variantIdx + 1; otherVariantIdx < TRADE_VARIANT_COUNT; otherVariantIdx++)
      {
         if(magic1 == BuildMagicForVariant(otherVariantIdx))
            FatalError(StringFormat("Composite magic collision: variant %d and %d produce same magic %s", variantIdx, otherVariantIdx, IntegerToString(magic1)));
      }
   }
}

//+------------------------------------------------------------------+
//| Session+PD digit (1..4) from ParseCompositeMagic.                |
//+------------------------------------------------------------------+
int ExtractMagicSessionPdCategoryFromMagic(long compositeMagic)
{
   return ParseCompositeMagic(compositeMagic).sessionPd;
}

//+------------------------------------------------------------------+
//| Session + PD gate from composite magic slot 4 (MAGIC_IS_*_AND_PD_*). |
//| Pass the same composite magic long you attach to the order (e.g. BuildMagicForVariant(variantIdx)). |
//+------------------------------------------------------------------+
bool MeetsMagicSessionPdEntryGate(long compositeMagic, int kLast)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   int sessionPdCode = ExtractMagicSessionPdCategoryFromMagic(compositeMagic);
   string sess = g_session[kLast];
   string pd = GetPDtrendString();
   // Only != comparisons (g_session is "ON"|"RTH"|"sleep"). ON = not RTH and not sleep; RTH-style = not ON.
   switch(sessionPdCode)
   {
      case MAGIC_IS_ON_AND_PD_GREEN:
         return (sess != "RTH" && sess != "sleep" && pd != "PD_red");
      case MAGIC_IS_ON_AND_PD_RED:
         return (sess != "RTH" && sess != "sleep" && pd != "PD_green");
      case MAGIC_IS_RTH_AND_PD_GREEN:
         return (sess != "ON" && pd != "PD_red");
      case MAGIC_IS_RTH_AND_PD_RED:
         return (sess != "ON" && pd != "PD_green");
      default:
         return false;
   }
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
   int v = FindVariantIndexForCompositeMagic(compositeMagic);
   if(v < 0 || !g_trade[v].babysit_enabled) return "";
   return StringFormat(" b%d", g_trade[v].babysitStart_minute);
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
//| Single source: pending order price, SL, TP for MAGIC_TRADE_* direction (Place*AtLevel + WriteTradeLogPendingOrder). |
//| offsetPoints, slPoints, tpPoints: same units as g_trade (PointSized points); price via PointSized only. |
//+------------------------------------------------------------------+
void PendingOrderPricesForDirection(const int direction, const double levelPrice, const double offsetPoints, const double slPoints, const double tpPoints,
   double &outOrderPrice, double &outStopLoss, double &outTakeProfit)
{
   const double offPx = PointSized(offsetPoints);
   const double slPx = PointSized(slPoints);
   const double tpPx = PointSized(tpPoints);
   const double spr = g_pendingTriggerSymmetrySpread;
   switch(direction)
   {
      case MAGIC_TRADE_LONG:
         outOrderPrice = NormalizeDouble(levelPrice + offPx, _Digits);
         outStopLoss = NormalizeDouble(outOrderPrice - slPx, _Digits);
         outTakeProfit = NormalizeDouble(outOrderPrice + tpPx, _Digits);
         return;
      case MAGIC_TRADE_SHORT:
         outOrderPrice = NormalizeDouble(levelPrice - offPx, _Digits);
         outStopLoss = NormalizeDouble(outOrderPrice + slPx, _Digits);
         outTakeProfit = NormalizeDouble(outOrderPrice - tpPx, _Digits);
         return;
      case MAGIC_TRADE_LONG_REVERSED:
         outOrderPrice = NormalizeDouble(levelPrice + offPx - spr, _Digits);
         outStopLoss = NormalizeDouble(outOrderPrice +0.0 + slPx, _Digits);
         outTakeProfit = NormalizeDouble(outOrderPrice +0.0 - tpPx, _Digits);
         return;
      case MAGIC_TRADE_SHORT_REVERSED:
         // diff często to 0.1 od short-not-reversed, ale czasem są oszukane spikes i oba trejdy przegrywają.
         outOrderPrice = NormalizeDouble(levelPrice - offPx + spr, _Digits);
         outStopLoss = NormalizeDouble(outOrderPrice -0.0  - tpPx, _Digits);
         outTakeProfit = NormalizeDouble(outOrderPrice  -0.0  + slPx, _Digits);
         return;
      default:
         FatalError(StringFormat("PendingOrderPricesForDirection: invalid direction %d (expected %d..%d)",
            direction, MAGIC_TRADE_LONG, MAGIC_TRADE_SHORT_REVERSED));
   }
}

//+------------------------------------------------------------------+
//| After PlacePendingFromMagic returned true: log pending_created (order kind + prices match Place*). |
//+------------------------------------------------------------------+
void WriteTradeLogPendingOrder(double levelPrice, double offsetPoints, double slPoints, double tpPoints, long magic)
{
   string magicStrForLogFilename = IsVariantTradeCompositeMagic(magic) ? MagicNumberToFixedWidthString(magic) : "";
   ulong orderTicket = ExtTrade.ResultOrder();
   datetime eventTime = g_lastTimer1Time;
   if(orderTicket > 0 && OrderSelect(orderTicket))
      eventTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
   int dir = ParseCompositeMagic(magic).direction;
   string orderKind;
   switch(dir)
   {
      case MAGIC_TRADE_LONG:           orderKind = "buy_limit";  break;
      case MAGIC_TRADE_SHORT:          orderKind = "sell_limit"; break;
      case MAGIC_TRADE_LONG_REVERSED:  orderKind = "sell_stop";  break;
      case MAGIC_TRADE_SHORT_REVERSED: orderKind = "buy_stop";   break;
      default:
         FatalError(StringFormat("WriteTradeLogPendingOrder: invalid direction %d magic %s", dir, IntegerToString(magic)));
   }
   double orderPrice = 0.0;
   double stopLossVal = 0.0;
   double takeProfitVal = 0.0;
   PendingOrderPricesForDirection(dir, levelPrice, offsetPoints, slPoints, tpPoints, orderPrice, stopLossVal, takeProfitVal);
   string orderComment = BuildUnifiedOrderComment(levelPrice, takeProfitVal, stopLossVal, orderPrice, magic);
   WriteTradeLog(magicStrForLogFilename, "pending_created", eventTime, orderKind, orderPrice, stopLossVal, takeProfitVal, 30, orderTicket, 0, 0, (ENUM_DEAL_REASON)0, orderComment, magic);
}

//+------------------------------------------------------------------+
//| True if atTime is not inside any banned range for g_trade[variantIdx]. |
//+------------------------------------------------------------------+
bool IsTimeAllowedForTradeType(int variantIdx, datetime atTime)
{
   if(variantIdx < 0 || variantIdx >= TRADE_VARIANT_COUNT)
      return true;
   if(g_variantBannedRangeCount[variantIdx] == 0)
      return true;
   MqlDateTime mqlTime;
   TimeToStruct(atTime, mqlTime);
   int curMin = mqlTime.hour * 60 + mqlTime.min;
   for(int i = 0; i < g_variantBannedRangeCount[variantIdx]; i++)
   {
      int sm = g_variantBannedRanges[variantIdx][i].startMin;
      int em = g_variantBannedRanges[variantIdx][i].endMin;
      if(curMin >= sm && curMin <= em)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Categories string for a level (levels[].tagsCSV). Returns "" if invalid. Currently not used. |
//+------------------------------------------------------------------+
string GetCategoriesFromLevels(int levelsIdx)
{
   if(levelsIdx < 0 || levelsIdx >= ArraySize(levels)) return "";
   return levels[levelsIdx].tagsCSV;
}

//+------------------------------------------------------------------+
//| True if level at levelsIdx meets bounce entry: bounceCount==requiredBounceCount, bias_long, no_contact, candlesPassedSinceLastBounce < 65, time allowed for variant. |
//| no_contact is passed in (from current candle in_contact at close, or levels[].lastCandleInContact for OnTimer). Currently not used. |
//+------------------------------------------------------------------+
bool MeetsBuyBounceEntryRule(int levelsIdx, datetime atTime, int variantIdx, int requiredBounceCount, bool no_contact)
{
   if(levelsIdx < 0 || levelsIdx >= ArraySize(levels)) return false;
   bool bias_long = (levels[levelsIdx].dailyBias > 0);
   bool entryRule = (levels[levelsIdx].bounceCount == requiredBounceCount) && bias_long && no_contact && (levels[levelsIdx].candlesPassedSinceLastBounce < 65);
   return entryRule && IsTimeAllowedForTradeType(variantIdx, atTime);
}

//+------------------------------------------------------------------+
//| Proximity gate: which side(s) matter comes from g_trade[variantIdx].levelProximityFocus. |
//+------------------------------------------------------------------+
bool PendingVariantWithinPriceTriggerDistance(int variantIdx, double levelBelow, double levelAbove, double nearDistPts)
{
   if(variantIdx < 0 || variantIdx >= TRADE_VARIANT_COUNT) return false;
   bool nearBelow = (levelBelow > 0.0 && IsLivePriceNearLevel(levelBelow, nearDistPts));
   bool nearAbove = (levelAbove > 0.0 && IsLivePriceNearLevel(levelAbove, nearDistPts));
   int proximityFocus = g_trade[variantIdx].levelProximityFocus;
   if(proximityFocus == TRADE_LEVEL_FOCUS_BELOW) return nearBelow;
   if(proximityFocus == TRADE_LEVEL_FOCUS_ABOVE) return nearAbove;
   if(proximityFocus == TRADE_LEVEL_FOCUS_BOTH) return (nearBelow || nearAbove);
   return false;
}

//+------------------------------------------------------------------+
//| Order anchor level after entry passes (BOTH: prefer below if both in trigger band, else whichever is in band). |
//+------------------------------------------------------------------+
double PendingOrderAnchorLevelForVariant(int variantIdx, double levelBelow, double levelAbove, double nearDistPts)
{
   if(variantIdx < 0 || variantIdx >= TRADE_VARIANT_COUNT) return 0.0;
   int proximityFocus = g_trade[variantIdx].levelProximityFocus;
   if(proximityFocus == TRADE_LEVEL_FOCUS_BELOW) return levelBelow;
   if(proximityFocus == TRADE_LEVEL_FOCUS_ABOVE) return levelAbove;
   bool nearBelow = (levelBelow > 0.0 && IsLivePriceNearLevel(levelBelow, nearDistPts));
   bool nearAbove = (levelAbove > 0.0 && IsLivePriceNearLevel(levelAbove, nearDistPts));
   if(nearBelow && nearAbove) return levelBelow;
   if(nearBelow) return levelBelow;
   if(nearAbove) return levelAbove;
   return (levelBelow > 0.0 ? levelBelow : levelAbove);
}

//+------------------------------------------------------------------+
//| Variant-level policy after proximity + session/PD (levels/bid are NOT checked here — pipeline already did that). |
//| Wire g_tradeConfig[variantIdx].useLevel / usePrice here when you need extra rules per row. |
//+------------------------------------------------------------------+
bool PendingPassesRulesetPolicy(int variantIdx)
{
   if(variantIdx < 0 || variantIdx >= ArraySize(g_tradeConfig)) return true;
   return true;
}

//+------------------------------------------------------------------+
//| levelProximityFocus → single (levelPx, levelIdx) for stage-2 subset rules (keep handlers short). |
//+------------------------------------------------------------------+
EntryLevelCtx PendingBuildEntryLevelCtx(int variantIdx, double levelBelow, int idxBelow, double levelAbove, int idxAbove)
{
   EntryLevelCtx levelCtx;
   levelCtx.ok = false;
   levelCtx.levelPx = 0.0;
   levelCtx.levelIdx = -1;
   if(variantIdx < 0 || variantIdx >= TRADE_VARIANT_COUNT) return levelCtx;
   int proximityFocus = g_trade[variantIdx].levelProximityFocus;
   if(proximityFocus == TRADE_LEVEL_FOCUS_BELOW)
   {
      if(idxBelow < 0) return levelCtx;
      levelCtx.levelPx = levelBelow;
      levelCtx.levelIdx = idxBelow;
      levelCtx.ok = true;
      return levelCtx;
   }
   if(proximityFocus == TRADE_LEVEL_FOCUS_ABOVE)
   {
      if(idxAbove < 0) return levelCtx;
      levelCtx.levelPx = levelAbove;
      levelCtx.levelIdx = idxAbove;
      levelCtx.ok = true;
      return levelCtx;
   }
   if(idxBelow >= 0) { levelCtx.levelPx = levelBelow; levelCtx.levelIdx = idxBelow; levelCtx.ok = true; return levelCtx; }
   if(idxAbove >= 0) { levelCtx.levelPx = levelAbove; levelCtx.levelIdx = idxAbove; levelCtx.ok = true; return levelCtx; }
   return levelCtx;
}

//+------------------------------------------------------------------+
//| POLICY — Subset_<subsetHandlerKey> handlers (read before editing any subset): |
//| subsetHandlerKey = slot1×10000 + slot2×100 + slot3 (composite slots 1,2,3; e.g. 10201). |
//| Each implementation must be standalone (no forwarding to another handler). |
//| If two keys share logic today, duplicate the body. |
//| Do not spell full 17-digit composite values in // comments (file header rule). |
//+------------------------------------------------------------------+


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
//| True if levelPx is strictly below the day's running high so far at kLast (not an "X points" band). |
//+------------------------------------------------------------------+
bool Gate_Level_StrictlyBelowDayHighSoFar(const int kLast, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!g_dayHighSoFarAtBar[kLast].hasValue) return false;
   return (levelPx < g_dayHighSoFarAtBar[kLast].value);
}

//+------------------------------------------------------------------+
//| True if levelPx is strictly below RTH session high so far at kLast (same series as rthHighSoFar logs). |
//+------------------------------------------------------------------+
bool Gate_Level_StrictlyBelowRthHighSoFar(const int kLast, const double levelPx)
{
   if(g_m1DayStart == 0) return false;
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   double rh = 0.0;
   if(!GetRthHighSoFarAtBar(kLast, g_m1DayStart, dateStr, rh)) return false;
   return (levelPx < rh);
}

//+------------------------------------------------------------------+
//| True if levelPx is strictly above RTH session low so far at kLast (same series as rthLowSoFar / "RTHL"). |
//+------------------------------------------------------------------+
bool Gate_Level_StrictlyAboveRthLowSoFar(const int kLast, const double levelPx)
{
   if(g_m1DayStart == 0) return false;
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   double rl = 0.0;
   if(!GetRthLowSoFarAtBar(kLast, g_m1DayStart, dateStr, rl)) return false;
   return (levelPx > rl);
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
//| latestCandleOpenTime = that bar's M1 open (e.g. g_m1Rates[kLast].time). Session = GetSessionForCandleTime (ON | RTH | sleep). |
//| If session is not RTH: always returns true (gate passes) so ON/sleep (e.g. overnight) variants are not blocked by this IB-only RTH rule. |
//+------------------------------------------------------------------+
bool Gate_Level_AboveIBH(const int kLast, const datetime latestCandleOpenTime, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(GetSessionForCandleTime(latestCandleOpenTime) != "RTH") return true;
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
//| latestCandleOpenTime = that bar's M1 open. Session = GetSessionForCandleTime (ON | RTH | sleep). |
//| If session is not RTH: always returns true (gate passes) so unrelated ON/sleep trades are not filtered by this IB rule. |
//+------------------------------------------------------------------+
bool Gate_Level_AboveIBL(const int kLast, const datetime latestCandleOpenTime, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(GetSessionForCandleTime(latestCandleOpenTime) != "RTH") return true;
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
//| latestCandleOpenTime = that bar's M1 open. Session = GetSessionForCandleTime (ON | RTH | sleep). |
//| If session is not RTH: always returns true (gate passes) so unrelated ON/sleep trades are not filtered by this IB rule. |
//+------------------------------------------------------------------+
bool Gate_Level_BelowIBH(const int kLast, const datetime latestCandleOpenTime, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(GetSessionForCandleTime(latestCandleOpenTime) != "RTH") return true;
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
//| latestCandleOpenTime = that bar's M1 open. Session = GetSessionForCandleTime (ON | RTH | sleep). |
//| If session is not RTH: always returns true (gate passes) so unrelated ON/sleep trades are not filtered by this IB rule. |
//+------------------------------------------------------------------+
bool Gate_Level_BelowIBL(const int kLast, const datetime latestCandleOpenTime, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(GetSessionForCandleTime(latestCandleOpenTime) != "RTH") return true;
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
//| Gate_Level_AbsDiff_with_ONO: true when |levelPx - g_ONopen| >= minAbsDiffPoints (requires at least one M1 bar for the day). |
//+------------------------------------------------------------------+
bool Gate_Level_AbsDiff_with_ONO(const double levelPx, const double minAbsDiffPoints)
{
   if(g_barsInDay <= 0) return false;
   return (MathAbs(levelPx - g_ONopen) >= minAbsDiffPoints);
}

//+------------------------------------------------------------------+
//| True when today's RTH open is resolved and bar kLast is at/after nominal RTH open (safe to call Gate_Level_AbsDiff_with_RTHO). |
//+------------------------------------------------------------------+
bool Gate_Level_AbsDiff_with_RTHO__guard_RTHO_ready(const int kLast)
{
   if(kLast < 0 || kLast >= g_barsInDay || g_m1DayStart == 0) return false;
   if(!g_todayRTHopenValid) return false;
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   const datetime rthOpenBarTime = g_m1DayStart + GetRthOpenBarOffsetSeconds(dateStr);
   return (g_m1Rates[kLast].time >= rthOpenBarTime);
}

//+------------------------------------------------------------------+
//| Gate_Level_AbsDiff_with_RTHO: |levelPx - RTH open| >= minAbsDiffPoints. Caller MUST only invoke when g_todayRTHopenValid and bar at/after nominal RTH open; else FatalError. |
//+------------------------------------------------------------------+
bool Gate_Level_AbsDiff_with_RTHO(const double levelPx, const int kLast, const double minAbsDiffPoints)
{
   if(kLast < 0 || kLast >= g_barsInDay || g_m1DayStart == 0)
      FatalError("Gate_Level_AbsDiff_with_RTHO: invalid kLast or g_m1DayStart (only call when RTHO is set and bar is at/after nominal RTH open)");
   if(!g_todayRTHopenValid)
      FatalError("Gate_Level_AbsDiff_with_RTHO: g_todayRTHopenValid is false (only call after today's RTH open is resolved)");
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   const datetime rthOpenBarTime = g_m1DayStart + GetRthOpenBarOffsetSeconds(dateStr);
   if(g_m1Rates[kLast].time < rthOpenBarTime)
      FatalError("Gate_Level_AbsDiff_with_RTHO: bar time before nominal RTH open (only call when current bar is at/after RTH open)");
   return (MathAbs(levelPx - g_todayRTHopen) >= minAbsDiffPoints);
}

//+------------------------------------------------------------------+
//| Gate_Level_AbsDiff_with_IBH: |levelPx - IB high| >= minAbsDiffPoints. Caller MUST only invoke when IB is complete at kLast (g_IBhighAtBar[kLast].hasValue); else FatalError. |
//+------------------------------------------------------------------+
bool Gate_Level_AbsDiff_with_IBH(const double levelPx, const int kLast, const double minAbsDiffPoints)
{
   if(kLast < 0 || kLast >= g_barsInDay)
      FatalError("Gate_Level_AbsDiff_with_IBH: invalid kLast (only call when IBH is ready at kLast)");
   double ibh;
   if(!GetIBhighAtBar(kLast, ibh))
      FatalError("Gate_Level_AbsDiff_with_IBH: IB high not set at kLast (only call after last IB minute has passed)");
   return (MathAbs(levelPx - ibh) >= minAbsDiffPoints);
}

//+------------------------------------------------------------------+
//| Gate_Level_Above_PriceMidpoint: true when levelPx is strictly above session-range midpoint (day H+L)/2 at kLast. |
//+------------------------------------------------------------------+
bool Gate_Level_Above_PriceMidpoint(const int kLast, const double levelPx)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!g_sessionRangeMidpointAtBar[kLast].hasValue) return false;
   const double mid = g_sessionRangeMidpointAtBar[kLast].value;
   return (mid < levelPx);
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
   return g_dayBrokePDHAtBar[kLast];
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





// bookmark6 bookmarkSubsetStart

bool Subset_10201(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 20;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10202(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 20;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10203(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 20;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10204(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 20;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10205(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 20;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10206(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 20;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10207(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10208(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10209(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 45;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10210(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 45;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10211(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 45;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10212(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 45;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10213(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10214(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10215(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10216(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10217(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10218(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10219(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10220(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10221(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10222(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10223(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10224(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10225(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10226(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10227(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10228(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10229(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10230(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10231(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10232(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10233(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10234(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10235(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10236(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10237(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10238(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10239(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10240(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10241(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10242(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10243(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10244(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10245(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10246(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10247(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10248(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10249(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10250(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10251(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10252(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 30.0) return false;
   return true;
}

bool Subset_10253(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10254(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10255(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10256(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10257(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 30.0) return false;
   return true;
}

bool Subset_10258(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10259(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10260(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10261(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 30.0) return false;
   return true;
}

bool Subset_10262(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 30.0) return false;
   return true;
}

bool Subset_10263(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10264(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10265(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 30.0) return false;
   return true;
}

bool Subset_10266(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10267(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10268(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 10;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 30.0) return false;
   return true;
}

bool Subset_10269(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10270(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10271(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10272(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10273(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10274(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10275(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10276(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10277(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10278(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10279(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10280(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10281(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10282(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10283(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10284(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10285(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10286(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10287(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10288(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10289(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10290(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_10291(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_10292(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}



bool Subset_11201(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11202(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11203(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11204(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11205(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11206(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11207(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11208(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11209(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 30.0) return false;
   return true;
}

bool Subset_11210(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11211(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11212(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11213(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11214(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11215(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11216(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11217(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11218(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11219(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11220(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11221(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11222(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11223(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11224(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11225(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11226(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11227(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11228(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 50.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11229(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11230(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11231(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 30.0) return false;
   return true;
}

bool Subset_11232(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11233(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11234(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11235(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11236(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11237(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11238(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11239(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 30.0) return false;
   return true;
}

bool Subset_11240(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 21;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11241(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11242(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11243(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11244(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11245(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11246(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11247(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11248(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11249(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11250(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11251(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11252(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11253(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11254(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11255(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 59;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 40.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11256(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11257(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11258(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11259(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11260(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11261(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11262(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11263(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11264(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11265(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11266(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11267(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11268(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11269(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11270(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 120;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11271(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11272(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 5.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11273(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11274(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100.0, false);
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11275(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 6.0) return false;
   return true;
}

bool Subset_11276(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 200, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

bool Subset_11277(double levelPx, int levelIdx, int kLast)
{
   if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakAboveMin = 40;
   const int cleanStreakAboveMax = 240;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;

   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 300, false);
   if(StringToDouble(diffBelow) < 25.0) return false;

   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);
   if(StringToDouble(diffAbove) < 12.0) return false;
   return true;
}

// bookmark99 SubsetGentest start
bool Subset_10301(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 20; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10302(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10303(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10304(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 20; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10305(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10306(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10307(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 20; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10308(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10309(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10310(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10311(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 20; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10312(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10313(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10314(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10315(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 20; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10316(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10317(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10318(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10319(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 15.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10320(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 15.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10321(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 15.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10322(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 15.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10323(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 15.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10324(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 15.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10325(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 15.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10326(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 15.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10327(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 15.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10328(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 15.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10329(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 20; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10330(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10331(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10332(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10333(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10334(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10335(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10336(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10337(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10338(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10339(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10340(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10341(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10342(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10343(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10344(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10345(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10346(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 20; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10347(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10348(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10349(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10350(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10351(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10352(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10353(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10354(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10355(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10356(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10357(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10358(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10359(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10360(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10361(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10362(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10363(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10364(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 140;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10365(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10366(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 20; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10367(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10368(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 20; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10369(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10370(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10371(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10372(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10373(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 20; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10374(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10375(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 20; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10376(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10377(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 50.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10378(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 90;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10379(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 60;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10380(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 20; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10381(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 200;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10382(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 20; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10383(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10384(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10385(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10386(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10387(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10388(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10389(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10390(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 30.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10391(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 35; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10392(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 50; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10393(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 80; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}

bool Subset_10394(double levelPx, int levelIdx, int kLast)
{
   double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);
   if(levelAbove <= 0.0) return false;

   const double twoLevelsDiff = levelAbove - levelPx;
   if(twoLevelsDiff < 15.0) return false;
   if(twoLevelsDiff > 70.0) return false;

   const int cleanStreakAboveMin = 300;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < cleanStreakAboveMin) return false;

   const int diffAboveRange = 120; // optionally + X minutes
   const double diffAboveMin = twoLevelsDiff + 11.0;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < diffAboveMin) return false;
   return true;
}
// bookmark99 SubsetGentest end













bool Subset_20101(double levelPx, int levelIdx, int kLast)
{
   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}




























































bool Subset_20102(double levelPx, int levelIdx, int kLast) // 20101230268060808 -> 20102230268060808
{
   if(!Gate_Level_AbovePDO(levelPx)) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20103(double levelPx, int levelIdx, int kLast) // 
{
   if(!Gate_Level_AboveIBH(kLast, (kLast >= 0 && kLast < g_barsInDay) ? g_m1Rates[kLast].time : (datetime)0, levelPx)) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20104(double levelPx, int levelIdx, int kLast) 
{
   if(Gate_Level_AbovePDH(levelPx)) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20105(double levelPx, int levelIdx, int kLast) 
{
   if(!Gate_Level_Above_PriceMidpoint(kLast, levelPx)) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20106(double levelPx, int levelIdx, int kLast) 
{
   if(!Gate_Level_Above_PriceMidpoint(kLast, levelPx)) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20107(double levelPx, int levelIdx, int kLast) // Subset_20103+
{
   if(!Gate_Level_AboveIBH(kLast, (kLast >= 0 && kLast < g_barsInDay) ? g_m1Rates[kLast].time : (datetime)0, levelPx)) return false;
   if(!Gate_Level_AbovePDC(levelPx)) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20108(double levelPx, int levelIdx, int kLast) // Subset_20103+
{
   if(!Gate_Level_AbovePDC(levelPx)) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20109(double levelPx, int levelIdx, int kLast) // Subset_20101+
{
   if(!Gate_Level_AboveIBH(kLast, (kLast >= 0 && kLast < g_barsInDay) ? g_m1Rates[kLast].time : (datetime)0, levelPx)) return false;
   if(!Gate_Level_AbovePDO(levelPx)) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20110(double levelPx, int levelIdx, int kLast) // Subset_20101+
{
   if(!Gate_Level_AboveIBH(kLast, (kLast >= 0 && kLast < g_barsInDay) ? g_m1Rates[kLast].time : (datetime)0, levelPx)) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20121_parent(double levelPx, int levelIdx, int kLast)
{
   const double minDayHighOverLevelPoints = 2.0;
   const int exclusiveMaxCandlesLowAboveLevel = 45;
   const int cleanStreakBelow_Minimum = 10;

   //może zrobić też day high no more than x above level?
   const double maxDayHighOverLevelPoints = 45.0;
	if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;

   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20131_parent(double levelPx, int levelIdx, int kLast)
{
   const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 45;
   const int cleanStreakBelow_Minimum = 10;

   //może zrobić też day high no more than x above level?
   const double maxDayHighOverLevelPoints = 45.0;
	if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;

   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}
bool Subset_20141_parent(double levelPx, int levelIdx, int kLast)
{
   const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 60;
   const int cleanStreakBelow_Minimum = 3;

   //może zrobić też day high no more than x above level?
   const double maxDayHighOverLevelPoints = 60.0;
	if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;

   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}


bool Subset_40192_quant20105(double levelPx, int levelIdx, int kLast)  // Subset_20105+
{
   if(!Gate_Level_Above_PriceMidpoint(kLast, levelPx)) return false;
   if(!Gate_Level_AboveONH(kLast, levelPx)) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high n  o more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20112(double levelPx, int levelIdx, int kLast) // Subset_20101+
{
   if(!Gate_Level_AboveIBH(kLast, (kLast >= 0 && kLast < g_barsInDay) ? g_m1Rates[kLast].time : (datetime)0, levelPx)) return false;
   
   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_40199_quant20101(double levelPx, int levelIdx, int kLast) // Subset_20101+
{
   if(!Gate_Level_AboveIBH(kLast, (kLast >= 0 && kLast < g_barsInDay) ? g_m1Rates[kLast].time : (datetime)0, levelPx)) return false;
   if(!Gate_Level_Above_PriceMidpoint(kLast, levelPx)) return false;
   
   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_40198_quant20101(double levelPx, int levelIdx, int kLast) // Subset_20101+
{
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string weekdays[2];
   weekdays[0] = "monday";
   weekdays[1] = "thursday";
   if(!Gate_LevelData_Categories_have_LevelCats(weekdays, levelCats)) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_40197_quant40111_20105(double levelPx, int levelIdx, int kLast) // 40111 -> 40103
{
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string weekdays[2];
   weekdays[0] = "wednesday";
   weekdays[1] = "weekly";
   if(!Gate_LevelData_Categories_have_LevelCats(weekdays, levelCats)) return false;

   if(!Gate_Level_Above_PriceMidpoint(kLast, levelPx)) return false;
   if(!Gate_Level_AboveONH(kLast, levelPx)) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high n  o more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_40196_quant20101(double levelPx, int levelIdx, int kLast) // 20101330267000808 -> 40104330267000808
{
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string weekdays[2];
   weekdays[0] = "stacked";
   weekdays[1] = "monday";
   if(!Gate_LevelData_Categories_have_LevelCats(weekdays, levelCats)) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_40195_quant20101(double levelPx, int levelIdx, int kLast) // 20101230267001010 -> 40105230267001010. 20101430267001010 -> 40105430267001010
{
   if(!Gate_LevelData_Weekly_TagSimplified_is(levelIdx, "weeklydown")) return false;

   //const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   //może zrobić też day high no more than x above level?
   //if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20113(double levelPx, int levelIdx, int kLast) 
{
   // if(Gate_Level_AbovePDH(levelPx)) return false;

   const double minDayHighOverLevelPoints = 0.77;
   const double maxDayHighOverLevelPoints = 15.0;

   //const int exclusiveMaxCandlesLowAboveLevel = 15;
   //if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;

   const int cleanStreakBelow_Minimum = 25;
   const int cleanStreakBelow_max = 300;

   if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;
   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   
   if(!Gate_CleanStreak_NoMoreThanX_BelowLevel(levelIdx, kLast, cleanStreakBelow_max)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}



bool Subset_20114_from20113(double levelPx, int levelIdx, int kLast) // 20114435217000606
{

   if(!Gate_Day_HasGapUp()) return false;

   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string weekdays[2];
   weekdays[0] = "thursday";
   weekdays[1] = "friday";
   if(!Gate_LevelData_Categories_have_LevelCats(weekdays, levelCats)) return false;
   
   // if(Gate_Level_AbovePDH(levelPx)) return false;

   const double minDayHighOverLevelPoints = 0.77;
   const double maxDayHighOverLevelPoints = 15.0;

   //const int exclusiveMaxCandlesLowAboveLevel = 15;
   //if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;

   const int cleanStreakBelow_Minimum = 25;
   const int cleanStreakBelow_max = 300;

   if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;
   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   
   if(!Gate_CleanStreak_NoMoreThanX_BelowLevel(levelIdx, kLast, cleanStreakBelow_max)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_40194_from20113(double levelPx, int levelIdx, int kLast) 
{
   // if(Gate_Level_AbovePDH(levelPx)) return false;

   if(!Gate_LevelData_TagSimplified_is(levelIdx, "down")) return false;

   const double minDayHighOverLevelPoints = 0.77;
   const double maxDayHighOverLevelPoints = 15.0;

   //const int exclusiveMaxCandlesLowAboveLevel = 15;
   //if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;

   const int cleanStreakBelow_Minimum = 25;
   const int cleanStreakBelow_max = 300;

   if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;
   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   
   if(!Gate_CleanStreak_NoMoreThanX_BelowLevel(levelIdx, kLast, cleanStreakBelow_max)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_40193_from20113(double levelPx, int levelIdx, int kLast) 
{
   // if(Gate_Level_AbovePDH(levelPx)) return false;

   if(!Gate_Day_DayBrokePDL_is_FALSE(kLast)) return false; 

   const double minDayHighOverLevelPoints = 0.77;
   const double maxDayHighOverLevelPoints = 15.0;

   //const int exclusiveMaxCandlesLowAboveLevel = 15;
   //if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;

   const int cleanStreakBelow_Minimum = 25;
   const int cleanStreakBelow_max = 300;

   if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;
   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   
   if(!Gate_CleanStreak_NoMoreThanX_BelowLevel(levelIdx, kLast, cleanStreakBelow_max)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}


bool Subset_20201(double levelPx, int levelIdx, int kLast)
{
   //clean strik 11 udowadnia że cena było czysto poniżej levela niedawno	
   //clean strik pod levelem 24 udowadnia że teraz cena czysto i nie za długo

   //if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   ///if(kLast < 0 || kLast >= g_barsInDay) return false;

   const int cleanStreakBelowMin = 20;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;


   // highest diff above: 9 pkt ostatnie 24 świece udowadnia że cena wysoko powyżej levela niedawno	
   // highest diff above: 19 pkt ostatnie (var streak 24 + przed streakiem 30 czyli łącznie 54) świece 

   const int diffAboveRange = cleanStreakBelowMin + 30;  //+ X minutes
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 8.0) return false;

   //highest diff below: 11 pkt ostatnie 24 świece (w tym clean streaku) udowadnia że cena była nisko poniżej levela niedawno (i więcej niż nasz target TPSL)
   //udowadnia że cena wysoko powyżej levela niedawno (i 19 to więcej niż target TP SL)
   //highest diff below: 16 pkt ostatnie 2 świece udowadnia że cena była nisko poniżej levela niedawno	

   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 9.0) return false;

   return true;
}
bool Subset_20210(double levelPx, int levelIdx, int kLast)
{
   //clean strik 11 udowadnia że cena było czysto poniżej levela niedawno	

   const int cleanStreakBelowMin = 8;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;

   const int diffAboveRange = cleanStreakBelowMin + 30;  //+ X minutes
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 8.0) return false;

   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 9.0) return false;

   return true;
}
bool Subset_20220(double levelPx, int levelIdx, int kLast)
{
   const int cleanStreakBelowMin = 8;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;

   const int diffAboveRange = cleanStreakBelowMin + 30;  //+ X minutes
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 16.0) return false;

   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 16.0) return false;

   return true;
}
bool Subset_20230(double levelPx, int levelIdx, int kLast)
{
   const int cleanStreakBelowMin = 40;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;

   const int diffAboveRange = cleanStreakBelowMin + 30;  //+ X minutes
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 16.0) return false;

   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 16.0) return false;

   return true;
}
bool Subset_20240(double levelPx, int levelIdx, int kLast)
{
   const int cleanStreakBelowMin = 80;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;

   const int diffAboveRange = cleanStreakBelowMin + 30;  //+ X minutes
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 16.0) return false;

   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 16.0) return false;

   return true;
}
bool Subset_20250(double levelPx, int levelIdx, int kLast)
{
   const int cleanStreakBelowMin = 80;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;

   const int diffAboveRange = cleanStreakBelowMin + 30;  //+ X minutes
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 20.0) return false;

   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 20.0) return false;

   return true;
}
bool Subset_20260(double levelPx, int levelIdx, int kLast)
{
   const int cleanStreakBelowMin = 20;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;

   const int diffAboveRange = cleanStreakBelowMin + 30;  //+ X minutes
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 8.0) return false;

   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 16.0) return false;

   return true;
}
bool Subset_20270(double levelPx, int levelIdx, int kLast)
{
   const int cleanStreakBelowMin = 20;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;

   const int diffAboveRange = cleanStreakBelowMin + 30;  //+ X minutes
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 16.0) return false;

   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 8.0) return false;

   return true;
}


bool Subset_20301(double levelPx, int levelIdx, int kLast)
{
// short type 3 : z dołu do góry level przebity jak masło i shortujemy level wyżej. i screeny pokazują
// że ślepy short 1st touch jest słaby ale warto i tak potem przetestować taki trade type (nie 03) 

   double levelBelow = Rules_GetClosestNonTertiaryLevelBelowPrice(levelPx);
   // Check if a level was found (returns 0.0 if none) and perform logic
   if(levelBelow <= 0.0) return false;

   const double twoLevelsDiff = levelPx - levelBelow;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   // a: clean OHLC streak below trade level: 131, czyli rule > 120 lub >65
   // b: level never touched today, ale pewnie wystarczy clean streak 120

   const int cleanStreakBelowMin = 90;
   int streakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(streakBelow < cleanStreakBelowMin) return false;

   //a: (20:20 ma diff below level aż 42 pkt, dzikie rally. 6791-6762=29, 42-29=13
   //b: (biggest diff w last 35 candles to 26 pkt od 6791 (a z levelami to 6791-6778=13, 26-13 = 13 czyli 13 poniżej 2nd level)
   const int diffBelowRange = 35; //+ X minutes
   const double diffBelowMin = twoLevelsDiff + 11.0;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < diffBelowMin) return false;

   return true;
}
bool Subset_20310(double levelPx, int levelIdx, int kLast)
{
// short type 3 : z dołu do góry level przebity jak masło i shortujemy level wyżej. 
   double levelBelow = Rules_GetClosestNonTertiaryLevelBelowPrice(levelPx);
   // Check if a level was found (returns 0.0 if none) and perform logic
   if(levelBelow <= 0.0) return false;

   const double twoLevelsDiff = levelPx - levelBelow;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   // a: clean OHLC streak below trade level: 131, czyli rule > 120 lub >65
   // b: level never touched today, ale pewnie wystarczy clean streak 120

   const int cleanStreakBelowMin = 90;
   int streakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(streakBelow < cleanStreakBelowMin) return false;

   //a: (20:20 ma diff below level aż 42 pkt, dzikie rally. 6791-6762=29, 42-29=13
   //b: (biggest diff w last 35 candles to 26 pkt od 6791 (a z levelami to 6791-6778=13, 26-13 = 13 czyli 13 poniżej 2nd level)
   const int diffBelowRange = 35; //+ X minutes
   const double diffBelowMin = twoLevelsDiff + 22.0;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < diffBelowMin) return false;

   return true;
}
bool Subset_20320(double levelPx, int levelIdx, int kLast)
{
// short type 3 : z dołu do góry level przebity jak masło i shortujemy level wyżej. 
   double levelBelow = Rules_GetClosestNonTertiaryLevelBelowPrice(levelPx);
   // Check if a level was found (returns 0.0 if none) and perform logic
   if(levelBelow <= 0.0) return false;

   const double twoLevelsDiff = levelPx - levelBelow;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   // a: clean OHLC streak below trade level: 131, czyli rule > 120 lub >65
   // b: level never touched today, ale pewnie wystarczy clean streak 120

   const int cleanStreakBelowMin = 90;
   int streakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(streakBelow < cleanStreakBelowMin) return false;

   //a: (20:20 ma diff below level aż 42 pkt, dzikie rally. 6791-6762=29, 42-29=13
   //b: (biggest diff w last 35 candles to 26 pkt od 6791 (a z levelami to 6791-6778=13, 26-13 = 13 czyli 13 poniżej 2nd level)
   const int diffBelowRange = 35; //+ X minutes
   const double diffBelowMin = twoLevelsDiff + 30.0;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < diffBelowMin) return false;

   return true;
}

bool Subset_20330(double levelPx, int levelIdx, int kLast)
{
// short type 3 : z dołu do góry level przebity jak masło i shortujemy level wyżej. 
   double levelBelow = Rules_GetClosestNonTertiaryLevelBelowPrice(levelPx);
   // Check if a level was found (returns 0.0 if none) and perform logic
   if(levelBelow <= 0.0) return false;

   const double twoLevelsDiff = levelPx - levelBelow;
   if(twoLevelsDiff < 10.0) return false;
   if(twoLevelsDiff > 35.0) return false;

   // a: clean OHLC streak below trade level: 131, czyli rule > 120 lub >65
   // b: level never touched today, ale pewnie wystarczy clean streak 120

   const int cleanStreakBelowMin = 300;
   int streakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(streakBelow < cleanStreakBelowMin) return false;

   //a: (20:20 ma diff below level aż 42 pkt, dzikie rally. 6791-6762=29, 42-29=13
   //b: (biggest diff w last 35 candles to 26 pkt od 6791 (a z levelami to 6791-6778=13, 26-13 = 13 czyli 13 poniżej 2nd level)
   const int diffBelowRange = 35; //+ X minutes
   const double diffBelowMin = twoLevelsDiff + 11.0;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < diffBelowMin) return false;

   return true;
}

bool Subset_20401(double levelPx, int levelIdx, int kLast)
{
// short type 4 : 1st ever touch today, ALE na warunkach
// real trade examples:
// ONO, diff from level is 41.9 | level 60 pkt ponad ONO  | 140 pkt od ONO 
// RTHO nie ma jeszcze | level 56 pkt ponad RTHO | 150 pkt od RTHO
// ibh nie ma jeszcze | level 15 pkt ponad IBH | 96 pkt > IBH 
// proximity 1.3, gain 19  w 8 m | contact -1.4 , 25 pkt w 10 m | contact -2.4, gain 20 pkt w 3 m
   const double level_minDiff_with_ONO = 35.0;
   const double level_minDiff_with_RTHO = 35.0; // but skipped check if not set yet
   const double level_minDiff_with_IBH = 10.0; // but skipped check if not set yet

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!Gate_Level_neverTouched_ceiling(levelIdx, kLast)) return false;
   if(!Gate_Level_AbsDiff_with_ONO(levelPx, level_minDiff_with_ONO)) return false;

   if(Gate_Level_AbsDiff_with_RTHO__guard_RTHO_ready(kLast))
      if(!Gate_Level_AbsDiff_with_RTHO(levelPx, kLast, level_minDiff_with_RTHO)) return false;

   if(g_IBhighAtBar[kLast].hasValue)
      if(!Gate_Level_AbsDiff_with_IBH(levelPx, kLast, level_minDiff_with_IBH)) return false;

   return true;
}
bool Subset_20410(double levelPx, int levelIdx, int kLast)
{
// short type 4 : 1st ever touch today, ALE na warunkach
   const double level_minDiff_with_ONO = 35.0;
   const double level_minDiff_with_RTHO = 50.0; // but skipped check if not set yet
   const double level_minDiff_with_IBH = 10.0; // but skipped check if not set yet

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!Gate_Level_neverTouched_ceiling(levelIdx, kLast)) return false;
   if(!Gate_Level_AbsDiff_with_ONO(levelPx, level_minDiff_with_ONO)) return false;

   if(Gate_Level_AbsDiff_with_RTHO__guard_RTHO_ready(kLast))
      if(!Gate_Level_AbsDiff_with_RTHO(levelPx, kLast, level_minDiff_with_RTHO)) return false;

   if(g_IBhighAtBar[kLast].hasValue)
      if(!Gate_Level_AbsDiff_with_IBH(levelPx, kLast, level_minDiff_with_IBH)) return false;

   return true;
}
bool Subset_20420(double levelPx, int levelIdx, int kLast)
{
// short type 4 : 1st ever touch today, ALE na warunkach
   const double level_minDiff_with_ONO = 35.0;
   const double level_minDiff_with_RTHO = 50.0; // but skipped check if not set yet
   const double level_minDiff_with_IBH = 20.0; // but skipped check if not set yet

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!Gate_Level_neverTouched_ceiling(levelIdx, kLast)) return false;
   if(!Gate_Level_AbsDiff_with_ONO(levelPx, level_minDiff_with_ONO)) return false;

   if(Gate_Level_AbsDiff_with_RTHO__guard_RTHO_ready(kLast))
      if(!Gate_Level_AbsDiff_with_RTHO(levelPx, kLast, level_minDiff_with_RTHO)) return false;

   if(g_IBhighAtBar[kLast].hasValue)
      if(!Gate_Level_AbsDiff_with_IBH(levelPx, kLast, level_minDiff_with_IBH)) return false;

   return true;
}
bool Subset_20430(double levelPx, int levelIdx, int kLast)
{
// short type 4 : 1st ever touch today, ALE na warunkach
   const double level_minDiff_with_ONO = 35.0;
   const double level_minDiff_with_RTHO = 75.0; // but skipped check if not set yet
   const double level_minDiff_with_IBH = 20.0; // but skipped check if not set yet

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!Gate_Level_neverTouched_ceiling(levelIdx, kLast)) return false;
   if(!Gate_Level_AbsDiff_with_ONO(levelPx, level_minDiff_with_ONO)) return false;

   if(Gate_Level_AbsDiff_with_RTHO__guard_RTHO_ready(kLast))
      if(!Gate_Level_AbsDiff_with_RTHO(levelPx, kLast, level_minDiff_with_RTHO)) return false;

   if(g_IBhighAtBar[kLast].hasValue)
      if(!Gate_Level_AbsDiff_with_IBH(levelPx, kLast, level_minDiff_with_IBH)) return false;

   return true;
}
bool Subset_20440(double levelPx, int levelIdx, int kLast)
{
// short type 4 : 1st ever touch today, ALE na warunkach
   const double level_minDiff_with_ONO = 35.0;
   const double level_minDiff_with_RTHO = 75.0; // but skipped check if not set yet
   const double level_minDiff_with_IBH = 30.0; // but skipped check if not set yet

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!Gate_Level_neverTouched_ceiling(levelIdx, kLast)) return false;
   if(!Gate_Level_AbsDiff_with_ONO(levelPx, level_minDiff_with_ONO)) return false;

   if(Gate_Level_AbsDiff_with_RTHO__guard_RTHO_ready(kLast))
      if(!Gate_Level_AbsDiff_with_RTHO(levelPx, kLast, level_minDiff_with_RTHO)) return false;

   if(g_IBhighAtBar[kLast].hasValue)
      if(!Gate_Level_AbsDiff_with_IBH(levelPx, kLast, level_minDiff_with_IBH)) return false;

   return true;
}

bool Subset_20211_quant20210(double levelPx, int levelIdx, int kLast)
{
   if(!Gate_Level_AbovePDL(levelPx)) return false;
   // --- same as Subset_20210 (inlined) ---
   const int cleanStreakBelowMin = 8;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;
   const int diffAboveRange = cleanStreakBelowMin + 30;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 8.0) return false;
   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 9.0) return false;
   return true;
}

bool Subset_40191_quant40197(double levelPx, int levelIdx, int kLast)
{
   if(!Gate_Level_StrictlyBelowDayHighSoFar(kLast, levelPx)) return false;
   if(!Gate_Level_AboveONL(kLast, levelPx)) return false;
   // --- same as Subset_40197_quant40111_20105 (inlined) ---
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string weekdays[2];
   weekdays[0] = "wednesday";
   weekdays[1] = "weekly";
   if(!Gate_LevelData_Categories_have_LevelCats(weekdays, levelCats)) return false;
   if(!Gate_Level_Above_PriceMidpoint(kLast, levelPx)) return false;
   if(!Gate_Level_AboveONH(kLast, levelPx)) return false;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_40190_quant40197(double levelPx, int levelIdx, int kLast)
{
   if(!Gate_LevelData_TagSimplified_is(levelIdx, "up")) return false;
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string weekdays[2];
   weekdays[0] = "wednesday";
   weekdays[1] = "weekly";
   if(!Gate_LevelData_Categories_have_LevelCats(weekdays, levelCats)) return false;
   if(!Gate_Level_Above_PriceMidpoint(kLast, levelPx)) return false;
   if(!Gate_Level_AboveONH(kLast, levelPx)) return false;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_40189_quant40197(double levelPx, int levelIdx, int kLast)
{
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   if(!Gate_Day_DayBrokePDH_is_TRUE(kLast)) return false;
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string weekdays[2];
   weekdays[0] = "wednesday";
   weekdays[1] = "weekly";
   if(!Gate_LevelData_Categories_have_LevelCats(weekdays, levelCats)) return false;
   if(!Gate_Level_Above_PriceMidpoint(kLast, levelPx)) return false;
   if(!Gate_Level_AboveONH(kLast, levelPx)) return false;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_40188_quant40197(double levelPx, int levelIdx, int kLast)
{
   if(!Gate_Level_BelowPDH(levelPx)) return false;
   if(!Gate_Level_AbovePDC(levelPx)) return false;
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string weekdays[2];
   weekdays[0] = "wednesday";
   weekdays[1] = "weekly";
   if(!Gate_LevelData_Categories_have_LevelCats(weekdays, levelCats)) return false;
   if(!Gate_Level_Above_PriceMidpoint(kLast, levelPx)) return false;
   if(!Gate_Level_AboveONH(kLast, levelPx)) return false;
   const int exclusiveMaxCandlesLowAboveLevel = 15;
   const int cleanStreakBelow_Minimum = 20;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20261_quant20260(double levelPx, int levelIdx, int kLast)
{
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string dailyNeedle[1];
   dailyNeedle[0] = "daily";
   if(!Gate_LevelData_Categories_have_LevelCats(dailyNeedle, levelCats)) return false;
   // --- same as Subset_20260 (inlined) ---
   const int cleanStreakBelowMin = 20;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;
   const int diffAboveRange = cleanStreakBelowMin + 30;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 8.0) return false;
   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 16.0) return false;
   return true;
}

bool Subset_20262_quant20261(double levelPx, int levelIdx, int kLast)
{
   if(!Gate_Level_AbovePDC(levelPx)) return false;
   if(!Gate_Level_AboveONL(kLast, levelPx)) return false;
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string dailyNeedle[1];
   dailyNeedle[0] = "daily";
   if(!Gate_LevelData_Categories_have_LevelCats(dailyNeedle, levelCats)) return false;
   // --- same as Subset_20260 (inlined; matches Subset_20261_quant20260 stack) ---
   const int cleanStreakBelowMin = 20;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;
   const int diffAboveRange = cleanStreakBelowMin + 30;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 8.0) return false;
   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 16.0) return false;
   return true;
}

bool Subset_20202_quant20201(double levelPx, int levelIdx, int kLast)
{
   if(!Gate_Level_AbovePDL(levelPx)) return false;
   if(!Gate_Level_AbovePDC(levelPx)) return false;
   // --- same as Subset_20201 (inlined) ---
   const int cleanStreakBelowMin = 20;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;
   const int diffAboveRange = cleanStreakBelowMin + 30;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 8.0) return false;
   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 9.0) return false;
   return true;
}

bool Subset_20203_quant20201(double levelPx, int levelIdx, int kLast)
{
   const datetime tBar = (kLast >= 0 && kLast < g_barsInDay) ? g_m1Rates[kLast].time : (datetime)0;
   if(!Gate_Level_BelowIBH(kLast, tBar, levelPx)) return false;
   if(!Gate_Level_AbovePDO(levelPx)) return false;
   const int cleanStreakBelowMin = 20;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;
   const int diffAboveRange = cleanStreakBelowMin + 30;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 8.0) return false;
   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 9.0) return false;
   return true;
}

bool Subset_20204_quant20201(double levelPx, int levelIdx, int kLast)
{
   const datetime tBar = (kLast >= 0 && kLast < g_barsInDay) ? g_m1Rates[kLast].time : (datetime)0;
   if(!Gate_Level_AboveIBL(kLast, tBar, levelPx)) return false;
   if(!Gate_Level_Above_PriceMidpoint(kLast, levelPx)) return false;
   const int cleanStreakBelowMin = 20;
   int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];
   if(cleanStreakBelow < cleanStreakBelowMin) return false;
   const int diffAboveRange = cleanStreakBelowMin + 30;
   string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);
   if(diffAbove == "never" || StringToDouble(diffAbove) < 8.0) return false;
   int diffBelowRange = cleanStreakBelow - 1;
   if(diffBelowRange < 1) diffBelowRange = 1;
   string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);
   if(diffBelow == "never" || StringToDouble(diffBelow) < 9.0) return false;
   return true;
}

bool Subset_20132_quant20131(double levelPx, int levelIdx, int kLast)
{
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string dailyNeedle[1];
   dailyNeedle[0] = "daily";
   if(!Gate_LevelData_Categories_have_LevelCats(dailyNeedle, levelCats)) return false;
   // --- same as Subset_20131_parent (inlined) ---
   const double minDayHighOverLevelPoints = 0.77;
   const int exclusiveMaxCandlesLowAboveLevel = 45;
   const int cleanStreakBelow_Minimum = 10;
   const double maxDayHighOverLevelPoints = 45.0;
   if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;
   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20115_quant20114(double levelPx, int levelIdx, int kLast)
{
   if(!Gate_Day_HasGapUp()) return false;
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string dailyNeedle[1];
   dailyNeedle[0] = "daily";
   if(!Gate_LevelData_Categories_have_LevelCats(dailyNeedle, levelCats)) return false;
   // --- same tail as Subset_20114_from20113 (thu/fri replaced by daily above) ---
   const double minDayHighOverLevelPoints = 0.77;
   const double maxDayHighOverLevelPoints = 15.0;
   const int cleanStreakBelow_Minimum = 25;
   const int cleanStreakBelow_max = 300;
   if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;
   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CleanStreak_NoMoreThanX_BelowLevel(levelIdx, kLast, cleanStreakBelow_max)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20116_quant20114(double levelPx, int levelIdx, int kLast)
{
   if(!Gate_Level_BelowONH(kLast, levelPx)) return false;
   if(!Gate_Level_StrictlyAboveRthLowSoFar(kLast, levelPx)) return false;
   if(!Gate_Day_HasGapUp()) return false;
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string weekdays[2];
   weekdays[0] = "thursday";
   weekdays[1] = "friday";
   if(!Gate_LevelData_Categories_have_LevelCats(weekdays, levelCats)) return false;
   const double minDayHighOverLevelPoints = 0.77;
   const double maxDayHighOverLevelPoints = 15.0;
   const int cleanStreakBelow_Minimum = 25;
   const int cleanStreakBelow_max = 300;
   if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;
   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CleanStreak_NoMoreThanX_BelowLevel(levelIdx, kLast, cleanStreakBelow_max)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20118_quant20114(double levelPx, int levelIdx, int kLast)
{
   const datetime tBar = (kLast >= 0 && kLast < g_barsInDay) ? g_m1Rates[kLast].time : (datetime)0;
   if(!Gate_Level_StrictlyBelowRthHighSoFar(kLast, levelPx)) return false;
   if(!Gate_Level_BelowIBH(kLast, tBar, levelPx)) return false;
   if(!Gate_Day_HasGapUp()) return false;
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string weekdays[2];
   weekdays[0] = "thursday";
   weekdays[1] = "friday";
   if(!Gate_LevelData_Categories_have_LevelCats(weekdays, levelCats)) return false;
   const double minDayHighOverLevelPoints = 0.77;
   const double maxDayHighOverLevelPoints = 15.0;
   const int cleanStreakBelow_Minimum = 25;
   const int cleanStreakBelow_max = 300;
   if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;
   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CleanStreak_NoMoreThanX_BelowLevel(levelIdx, kLast, cleanStreakBelow_max)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20119_quant20114(double levelPx, int levelIdx, int kLast)
{
   if(!Gate_Level_BelowONH(kLast, levelPx)) return false;
   if(!Gate_Level_AbovePDO(levelPx)) return false;
   if(!Gate_Day_HasGapUp()) return false;
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string weekdays[2];
   weekdays[0] = "thursday";
   weekdays[1] = "friday";
   if(!Gate_LevelData_Categories_have_LevelCats(weekdays, levelCats)) return false;
   const double minDayHighOverLevelPoints = 0.77;
   const double maxDayHighOverLevelPoints = 15.0;
   const int cleanStreakBelow_Minimum = 25;
   const int cleanStreakBelow_max = 300;
   if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;
   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CleanStreak_NoMoreThanX_BelowLevel(levelIdx, kLast, cleanStreakBelow_max)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20187_quant20113(double levelPx, int levelIdx, int kLast)
{
   if(!Gate_LevelData_TagSimplified_is(levelIdx, "up")) return false;
   const double minDayHighOverLevelPoints = 0.77;
   const double maxDayHighOverLevelPoints = 15.0;
   const int cleanStreakBelow_Minimum = 25;
   const int cleanStreakBelow_max = 300;
   if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;
   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CleanStreak_NoMoreThanX_BelowLevel(levelIdx, kLast, cleanStreakBelow_max)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20186_quant20113(double levelPx, int levelIdx, int kLast)
{
   if(!Gate_Day_HasGapUp()) return false;
   const double minDayHighOverLevelPoints = 0.77;
   const double maxDayHighOverLevelPoints = 15.0;
   const int cleanStreakBelow_Minimum = 25;
   const int cleanStreakBelow_max = 300;
   if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;
   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CleanStreak_NoMoreThanX_BelowLevel(levelIdx, kLast, cleanStreakBelow_max)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

bool Subset_20185_quant20113(double levelPx, int levelIdx, int kLast)
{
   string levelCats;
   GetLevelCategories(DoubleToString(levelPx, _Digits), levelCats);
   string mondayNeedle[1];
   mondayNeedle[0] = "monday";
   if(!Gate_LevelData_Categories_have_LevelCats(mondayNeedle, levelCats)) return false;
   const double minDayHighOverLevelPoints = 0.77;
   const double maxDayHighOverLevelPoints = 15.0;
   const int cleanStreakBelow_Minimum = 25;
   const int cleanStreakBelow_max = 300;
   if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;
   if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;
   if(!Gate_CleanStreak_NoMoreThanX_BelowLevel(levelIdx, kLast, cleanStreakBelow_max)) return false;
   if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;
   return true;
}

// bookmark7 bookmarkSubsetEnd








//+------------------------------------------------------------------+
//| Stage-2: derive subsetHandlerKey from fullMagic (slots 1–3), dispatch to Subset_<key>. |
//+------------------------------------------------------------------+
bool PendingRuleSubsetPassesForFullMagic(const long fullMagic, const double levelPx, const int levelIdx, const int kLast)
{
   const int slot1 = CompositeMagicExtractSlot1TradeDirection(fullMagic);
   const int slot2 = CompositeMagicExtractSlot2TradeTypeId(fullMagic);
   const int slot3 = CompositeMagicExtractSlot3RuleSubsetId(fullMagic);
   const int subsetHandlerKey = slot1 * 10000 + slot2 * 100 + slot3;

   if(subsetHandlerKey == 10201 || subsetHandlerKey == 30201)
     return Subset_10201(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10202 || subsetHandlerKey == 30202)
      return Subset_10202(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10203 || subsetHandlerKey == 30203)
      return Subset_10203(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10204 || subsetHandlerKey == 30204)
      return Subset_10204(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10205 || subsetHandlerKey == 30205)
      return Subset_10205(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10206 || subsetHandlerKey == 30206)
      return Subset_10206(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10207 || subsetHandlerKey == 30207)
      return Subset_10207(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10208 || subsetHandlerKey == 30208)
      return Subset_10208(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10209 || subsetHandlerKey == 30209)
      return Subset_10209(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10210 || subsetHandlerKey == 30210)
      return Subset_10210(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10211 || subsetHandlerKey == 30211)
      return Subset_10211(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10212 || subsetHandlerKey == 30212)
     return Subset_10212(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10213 || subsetHandlerKey == 30213)
      return Subset_10213(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10214 || subsetHandlerKey == 30214)
      return Subset_10214(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10215 || subsetHandlerKey == 30215)
      return Subset_10215(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10216 || subsetHandlerKey == 30216)
      return Subset_10216(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10217 || subsetHandlerKey == 30217)
      return Subset_10217(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10218 || subsetHandlerKey == 30218)
      return Subset_10218(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10219 || subsetHandlerKey == 30219)
      return Subset_10219(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10220 || subsetHandlerKey == 30220)
      return Subset_10220(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10221 || subsetHandlerKey == 30221)
      return Subset_10221(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10222 || subsetHandlerKey == 30222)
      return Subset_10222(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10223 || subsetHandlerKey == 30223)
      return Subset_10223(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10224 || subsetHandlerKey == 30224)
      return Subset_10224(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10225 || subsetHandlerKey == 30225)
      return Subset_10225(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10226 || subsetHandlerKey == 30226)
      return Subset_10226(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10227 || subsetHandlerKey == 30227)
      return Subset_10227(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10228 || subsetHandlerKey == 30228)
      return Subset_10228(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10229 || subsetHandlerKey == 30229)
      return Subset_10229(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10230 || subsetHandlerKey == 30230)
      return Subset_10230(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10231 || subsetHandlerKey == 30231)
      return Subset_10231(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10232 || subsetHandlerKey == 30232)
      return Subset_10232(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10233 || subsetHandlerKey == 30233)
      return Subset_10233(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10234 || subsetHandlerKey == 30234)
      return Subset_10234(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10235 || subsetHandlerKey == 30235)
      return Subset_10235(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10236 || subsetHandlerKey == 30236)
      return Subset_10236(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10237 || subsetHandlerKey == 30237)
      return Subset_10237(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10238 || subsetHandlerKey == 30238)
      return Subset_10238(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10239 || subsetHandlerKey == 30239)
      return Subset_10239(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10240 || subsetHandlerKey == 30240)
      return Subset_10240(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10241 || subsetHandlerKey == 30241)
      return Subset_10241(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10242 || subsetHandlerKey == 30242)
      return Subset_10242(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10243 || subsetHandlerKey == 30243)
      return Subset_10243(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10244 || subsetHandlerKey == 30244)
      return Subset_10244(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10245 || subsetHandlerKey == 30245)
      return Subset_10245(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10246 || subsetHandlerKey == 30246)
      return Subset_10246(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10247 || subsetHandlerKey == 30247)
      return Subset_10247(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10248 || subsetHandlerKey == 30248)
      return Subset_10248(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10249 || subsetHandlerKey == 30249)
      return Subset_10249(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10250 || subsetHandlerKey == 30250)
      return Subset_10250(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10251 || subsetHandlerKey == 30251)
      return Subset_10251(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10252 || subsetHandlerKey == 30252)
      return Subset_10252(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10253 || subsetHandlerKey == 30253)
      return Subset_10253(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10254 || subsetHandlerKey == 30254)
      return Subset_10254(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10255 || subsetHandlerKey == 30255)
      return Subset_10255(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10256 || subsetHandlerKey == 30256)
      return Subset_10256(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10257 || subsetHandlerKey == 30257)
      return Subset_10257(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10258 || subsetHandlerKey == 30258)
      return Subset_10258(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10259 || subsetHandlerKey == 30259)
      return Subset_10259(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10260 || subsetHandlerKey == 30260)
      return Subset_10260(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10261 || subsetHandlerKey == 30261)
      return Subset_10261(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10262 || subsetHandlerKey == 30262)
      return Subset_10262(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10263 || subsetHandlerKey == 30263)
      return Subset_10263(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10264 || subsetHandlerKey == 30264)
      return Subset_10264(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10265 || subsetHandlerKey == 30265)
      return Subset_10265(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10266 || subsetHandlerKey == 30266)
      return Subset_10266(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10267 || subsetHandlerKey == 30267)
      return Subset_10267(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10268 || subsetHandlerKey == 30268)
      return Subset_10268(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10269 || subsetHandlerKey == 30269)
      return Subset_10269(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10270 || subsetHandlerKey == 30270)
      return Subset_10270(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10271 || subsetHandlerKey == 30271)
      return Subset_10271(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10272 || subsetHandlerKey == 30272)
      return Subset_10272(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10273 || subsetHandlerKey == 30273)
      return Subset_10273(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10274 || subsetHandlerKey == 30274)
      return Subset_10274(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10275 || subsetHandlerKey == 30275)
      return Subset_10275(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10276 || subsetHandlerKey == 30276)
      return Subset_10276(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10277 || subsetHandlerKey == 30277)
      return Subset_10277(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10278 || subsetHandlerKey == 30278)
      return Subset_10278(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10279 || subsetHandlerKey == 30279)
      return Subset_10279(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10280 || subsetHandlerKey == 30280)
      return Subset_10280(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10281 || subsetHandlerKey == 30281)
      return Subset_10281(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10282 || subsetHandlerKey == 30282)
      return Subset_10282(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10283 || subsetHandlerKey == 30283)
      return Subset_10283(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10284 || subsetHandlerKey == 30284)
      return Subset_10284(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10285 || subsetHandlerKey == 30285)
      return Subset_10285(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10286 || subsetHandlerKey == 30286)
      return Subset_10286(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10287 || subsetHandlerKey == 30287)
      return Subset_10287(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10288 || subsetHandlerKey == 30288)
      return Subset_10288(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10289 || subsetHandlerKey == 30289)
      return Subset_10289(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10290 || subsetHandlerKey == 30290)
      return Subset_10290(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10291 || subsetHandlerKey == 30291)
      return Subset_10291(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10292 || subsetHandlerKey == 30292)
      return Subset_10292(levelPx, levelIdx, kLast);

   if(subsetHandlerKey == 11201 || subsetHandlerKey == 31201)
      return Subset_11201(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11202 || subsetHandlerKey == 31202)
      return Subset_11202(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11203 || subsetHandlerKey == 31203)
      return Subset_11203(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11204 || subsetHandlerKey == 31204)
      return Subset_11204(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11205 || subsetHandlerKey == 31205)
      return Subset_11205(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11206 || subsetHandlerKey == 31206)
      return Subset_11206(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11207 || subsetHandlerKey == 31207)
      return Subset_11207(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11208 || subsetHandlerKey == 31208)
      return Subset_11208(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11209 || subsetHandlerKey == 31209)
      return Subset_11209(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11210 || subsetHandlerKey == 31210)
      return Subset_11210(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11211 || subsetHandlerKey == 31211)
      return Subset_11211(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11212 || subsetHandlerKey == 31212)
      return Subset_11212(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11213 || subsetHandlerKey == 31213)
      return Subset_11213(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11214 || subsetHandlerKey == 31214)
      return Subset_11214(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11215 || subsetHandlerKey == 31215)
      return Subset_11215(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11216 || subsetHandlerKey == 31216)
      return Subset_11216(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11217 || subsetHandlerKey == 31217)
      return Subset_11217(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11218 || subsetHandlerKey == 31218)
      return Subset_11218(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11219 || subsetHandlerKey == 31219)
      return Subset_11219(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11220 || subsetHandlerKey == 31220)
      return Subset_11220(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11221 || subsetHandlerKey == 31221)
      return Subset_11221(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11222 || subsetHandlerKey == 31222)
      return Subset_11222(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11223 || subsetHandlerKey == 31223)
      return Subset_11223(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11224 || subsetHandlerKey == 31224)
      return Subset_11224(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11225 || subsetHandlerKey == 31225)
      return Subset_11225(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11226 || subsetHandlerKey == 31226)
      return Subset_11226(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11227 || subsetHandlerKey == 31227)
      return Subset_11227(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11228 || subsetHandlerKey == 31228)
      return Subset_11228(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11229 || subsetHandlerKey == 31229)
      return Subset_11229(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11230 || subsetHandlerKey == 31230)
      return Subset_11230(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11231 || subsetHandlerKey == 31231)
      return Subset_11231(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11232 || subsetHandlerKey == 31232)
      return Subset_11232(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11233 || subsetHandlerKey == 31233)
      return Subset_11233(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11234 || subsetHandlerKey == 31234)
      return Subset_11234(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11235 || subsetHandlerKey == 31235)
      return Subset_11235(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11236 || subsetHandlerKey == 31236)
      return Subset_11236(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11237 || subsetHandlerKey == 31237)
      return Subset_11237(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11238 || subsetHandlerKey == 31238)
      return Subset_11238(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11239 || subsetHandlerKey == 31239)
      return Subset_11239(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11240 || subsetHandlerKey == 31240)
      return Subset_11240(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11241 || subsetHandlerKey == 31241)
      return Subset_11241(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11242 || subsetHandlerKey == 31242)
      return Subset_11242(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11243 || subsetHandlerKey == 31243)
      return Subset_11243(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11244 || subsetHandlerKey == 31244)
      return Subset_11244(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11245 || subsetHandlerKey == 31245)
      return Subset_11245(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11246 || subsetHandlerKey == 31246)
      return Subset_11246(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11247 || subsetHandlerKey == 31247)
      return Subset_11247(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11248 || subsetHandlerKey == 31248)
      return Subset_11248(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11249 || subsetHandlerKey == 31249)
      return Subset_11249(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11250 || subsetHandlerKey == 31250)
      return Subset_11250(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11251 || subsetHandlerKey == 31251)
      return Subset_11251(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11252 || subsetHandlerKey == 31252)
      return Subset_11252(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11253 || subsetHandlerKey == 31253)
      return Subset_11253(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11254 || subsetHandlerKey == 31254)
      return Subset_11254(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11255 || subsetHandlerKey == 31255)
      return Subset_11255(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11256 || subsetHandlerKey == 31256)
      return Subset_11256(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11257 || subsetHandlerKey == 31257)
      return Subset_11257(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11258 || subsetHandlerKey == 31258)
      return Subset_11258(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11259 || subsetHandlerKey == 31259)
      return Subset_11259(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11260 || subsetHandlerKey == 31260)
      return Subset_11260(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11261 || subsetHandlerKey == 31261)
      return Subset_11261(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11262 || subsetHandlerKey == 31262)
      return Subset_11262(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11263 || subsetHandlerKey == 31263)
      return Subset_11263(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11264 || subsetHandlerKey == 31264)
      return Subset_11264(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11265 || subsetHandlerKey == 31265)
      return Subset_11265(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11266 || subsetHandlerKey == 31266)
      return Subset_11266(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11267 || subsetHandlerKey == 31267)
      return Subset_11267(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11268 || subsetHandlerKey == 31268)
      return Subset_11268(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11269 || subsetHandlerKey == 31269)
      return Subset_11269(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11270 || subsetHandlerKey == 31270)
      return Subset_11270(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11271 || subsetHandlerKey == 31271)
      return Subset_11271(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11272 || subsetHandlerKey == 31272)
      return Subset_11272(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11273 || subsetHandlerKey == 31273)
      return Subset_11273(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11274 || subsetHandlerKey == 31274)
      return Subset_11274(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11275 || subsetHandlerKey == 31275)
      return Subset_11275(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11276 || subsetHandlerKey == 31276)
      return Subset_11276(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 11277 || subsetHandlerKey == 31277)
      return Subset_11277(levelPx, levelIdx, kLast);

// bookmark dispatchgen
   if(subsetHandlerKey == 10301 || subsetHandlerKey == 30301)
      return Subset_10301(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10302 || subsetHandlerKey == 30302)
      return Subset_10302(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10303 || subsetHandlerKey == 30303)
      return Subset_10303(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10304 || subsetHandlerKey == 30304)
      return Subset_10304(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10305 || subsetHandlerKey == 30305)
      return Subset_10305(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10306 || subsetHandlerKey == 30306)
      return Subset_10306(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10307 || subsetHandlerKey == 30307)
      return Subset_10307(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10308 || subsetHandlerKey == 30308)
      return Subset_10308(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10309 || subsetHandlerKey == 30309)
      return Subset_10309(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10310 || subsetHandlerKey == 30310)
      return Subset_10310(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10311 || subsetHandlerKey == 30311)
      return Subset_10311(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10312 || subsetHandlerKey == 30312)
      return Subset_10312(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10313 || subsetHandlerKey == 30313)
      return Subset_10313(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10314 || subsetHandlerKey == 30314)
      return Subset_10314(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10315 || subsetHandlerKey == 30315)
      return Subset_10315(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10316 || subsetHandlerKey == 30316)
      return Subset_10316(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10317 || subsetHandlerKey == 30317)
      return Subset_10317(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10318 || subsetHandlerKey == 30318)
      return Subset_10318(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10319 || subsetHandlerKey == 30319)
      return Subset_10319(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10320 || subsetHandlerKey == 30320)
      return Subset_10320(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10321 || subsetHandlerKey == 30321)
      return Subset_10321(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10322 || subsetHandlerKey == 30322)
      return Subset_10322(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10323 || subsetHandlerKey == 30323)
      return Subset_10323(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10324 || subsetHandlerKey == 30324)
      return Subset_10324(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10325 || subsetHandlerKey == 30325)
      return Subset_10325(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10326 || subsetHandlerKey == 30326)
      return Subset_10326(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10327 || subsetHandlerKey == 30327)
      return Subset_10327(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10328 || subsetHandlerKey == 30328)
      return Subset_10328(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10329 || subsetHandlerKey == 30329)
      return Subset_10329(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10330 || subsetHandlerKey == 30330)
      return Subset_10330(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10331 || subsetHandlerKey == 30331)
      return Subset_10331(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10332 || subsetHandlerKey == 30332)
      return Subset_10332(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10333 || subsetHandlerKey == 30333)
      return Subset_10333(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10334 || subsetHandlerKey == 30334)
      return Subset_10334(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10335 || subsetHandlerKey == 30335)
      return Subset_10335(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10336 || subsetHandlerKey == 30336)
      return Subset_10336(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10337 || subsetHandlerKey == 30337)
      return Subset_10337(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10338 || subsetHandlerKey == 30338)
      return Subset_10338(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10339 || subsetHandlerKey == 30339)
      return Subset_10339(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10340 || subsetHandlerKey == 30340)
      return Subset_10340(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10341 || subsetHandlerKey == 30341)
      return Subset_10341(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10342 || subsetHandlerKey == 30342)
      return Subset_10342(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10343 || subsetHandlerKey == 30343)
      return Subset_10343(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10344 || subsetHandlerKey == 30344)
      return Subset_10344(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10345 || subsetHandlerKey == 30345)
      return Subset_10345(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10346 || subsetHandlerKey == 30346)
      return Subset_10346(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10347 || subsetHandlerKey == 30347)
      return Subset_10347(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10348 || subsetHandlerKey == 30348)
      return Subset_10348(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10349 || subsetHandlerKey == 30349)
      return Subset_10349(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10350 || subsetHandlerKey == 30350)
      return Subset_10350(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10351 || subsetHandlerKey == 30351)
      return Subset_10351(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10352 || subsetHandlerKey == 30352)
      return Subset_10352(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10353 || subsetHandlerKey == 30353)
      return Subset_10353(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10354 || subsetHandlerKey == 30354)
      return Subset_10354(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10355 || subsetHandlerKey == 30355)
      return Subset_10355(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10356 || subsetHandlerKey == 30356)
      return Subset_10356(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10357 || subsetHandlerKey == 30357)
      return Subset_10357(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10358 || subsetHandlerKey == 30358)
      return Subset_10358(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10359 || subsetHandlerKey == 30359)
      return Subset_10359(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10360 || subsetHandlerKey == 30360)
      return Subset_10360(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10361 || subsetHandlerKey == 30361)
      return Subset_10361(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10362 || subsetHandlerKey == 30362)
      return Subset_10362(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10363 || subsetHandlerKey == 30363)
      return Subset_10363(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10364 || subsetHandlerKey == 30364)
      return Subset_10364(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10365 || subsetHandlerKey == 30365)
      return Subset_10365(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10366 || subsetHandlerKey == 30366)
      return Subset_10366(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10367 || subsetHandlerKey == 30367)
      return Subset_10367(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10368 || subsetHandlerKey == 30368)
      return Subset_10368(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10369 || subsetHandlerKey == 30369)
      return Subset_10369(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10370 || subsetHandlerKey == 30370)
      return Subset_10370(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10371 || subsetHandlerKey == 30371)
      return Subset_10371(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10372 || subsetHandlerKey == 30372)
      return Subset_10372(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10373 || subsetHandlerKey == 30373)
      return Subset_10373(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10374 || subsetHandlerKey == 30374)
      return Subset_10374(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10375 || subsetHandlerKey == 30375)
      return Subset_10375(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10376 || subsetHandlerKey == 30376)
      return Subset_10376(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10377 || subsetHandlerKey == 30377)
      return Subset_10377(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10378 || subsetHandlerKey == 30378)
      return Subset_10378(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10379 || subsetHandlerKey == 30379)
      return Subset_10379(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10380 || subsetHandlerKey == 30380)
      return Subset_10380(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10381 || subsetHandlerKey == 30381)
      return Subset_10381(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10382 || subsetHandlerKey == 30382)
      return Subset_10382(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10383 || subsetHandlerKey == 30383)
      return Subset_10383(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10384 || subsetHandlerKey == 30384)
      return Subset_10384(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10385 || subsetHandlerKey == 30385)
      return Subset_10385(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10386 || subsetHandlerKey == 30386)
      return Subset_10386(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10387 || subsetHandlerKey == 30387)
      return Subset_10387(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10388 || subsetHandlerKey == 30388)
      return Subset_10388(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10389 || subsetHandlerKey == 30389)
      return Subset_10389(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10390 || subsetHandlerKey == 30390)
      return Subset_10390(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10391 || subsetHandlerKey == 30391)
      return Subset_10391(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10392 || subsetHandlerKey == 30392)
      return Subset_10392(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10393 || subsetHandlerKey == 30393)
      return Subset_10393(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 10394 || subsetHandlerKey == 30394)
      return Subset_10394(levelPx, levelIdx, kLast);























   if(subsetHandlerKey == 20101 || subsetHandlerKey == 40101)
      return Subset_20101(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20102 || subsetHandlerKey == 40102)
      return Subset_20102(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20211 || subsetHandlerKey == 40211)
      return Subset_20211_quant20210(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20103 || subsetHandlerKey == 40103)
      return Subset_20103(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20104 || subsetHandlerKey == 40104)
      return Subset_20104(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20105 || subsetHandlerKey == 40105)
      return Subset_20105(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20106 || subsetHandlerKey == 40106)
      return Subset_20106(levelPx, levelIdx, kLast);

   if(subsetHandlerKey == 20107 || subsetHandlerKey == 40107)
      return Subset_20107(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20108 || subsetHandlerKey == 40108)
      return Subset_20108(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20109 || subsetHandlerKey == 40109)
      return Subset_20109(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20110 || subsetHandlerKey == 40110)
      return Subset_20110(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20112 || subsetHandlerKey == 40112)
      return Subset_20112(levelPx, levelIdx, kLast);

   if(subsetHandlerKey == 20113 || subsetHandlerKey == 40113)
      return Subset_20113(levelPx, levelIdx, kLast);

   if(subsetHandlerKey == 20114 || subsetHandlerKey == 40114)
      return Subset_20114_from20113(levelPx, levelIdx, kLast);

   if(subsetHandlerKey == 20115 || subsetHandlerKey == 40115)
      return Subset_20115_quant20114(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20116 || subsetHandlerKey == 40116)
      return Subset_20116_quant20114(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20117 || subsetHandlerKey == 40117)
      return Subset_20115_quant20114(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20118 || subsetHandlerKey == 40118)
      return Subset_20118_quant20114(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20119 || subsetHandlerKey == 40119)
      return Subset_20119_quant20114(levelPx, levelIdx, kLast);

   if(subsetHandlerKey == 20185 || subsetHandlerKey == 40185)
      return Subset_20185_quant20113(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20186 || subsetHandlerKey == 40186)
      return Subset_20186_quant20113(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20187 || subsetHandlerKey == 40187)
      return Subset_20187_quant20113(levelPx, levelIdx, kLast);

   if(subsetHandlerKey == 20121 || subsetHandlerKey == 40121)
      return Subset_20121_parent(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20131 || subsetHandlerKey == 40131)
      return Subset_20131_parent(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20132 || subsetHandlerKey == 40132)
      return Subset_20132_quant20131(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20141 || subsetHandlerKey == 40141)
      return Subset_20141_parent(levelPx, levelIdx, kLast);

   if(subsetHandlerKey == 20201 || subsetHandlerKey == 40201)
      return Subset_20201(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20202 || subsetHandlerKey == 40202)
      return Subset_20202_quant20201(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20203 || subsetHandlerKey == 40203)
      return Subset_20203_quant20201(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20204 || subsetHandlerKey == 40204)
      return Subset_20204_quant20201(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20210 || subsetHandlerKey == 40210)
      return Subset_20210(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20220 || subsetHandlerKey == 40220)
      return Subset_20220(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20230 || subsetHandlerKey == 40230)
      return Subset_20230(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20240 || subsetHandlerKey == 40240)
      return Subset_20240(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20250 || subsetHandlerKey == 40250)
      return Subset_20250(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20260 || subsetHandlerKey == 40260)
      return Subset_20260(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20261 || subsetHandlerKey == 40261)
      return Subset_20261_quant20260(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20262 || subsetHandlerKey == 40262)
      return Subset_20262_quant20261(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20270 || subsetHandlerKey == 40270)
      return Subset_20270(levelPx, levelIdx, kLast);

   if(subsetHandlerKey == 20301 || subsetHandlerKey == 40301)
      return Subset_20301(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20310 || subsetHandlerKey == 40310)
      return Subset_20310(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20320 || subsetHandlerKey == 40320)
      return Subset_20320(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20330 || subsetHandlerKey == 40330)
      return Subset_20330(levelPx, levelIdx, kLast);

   if(subsetHandlerKey == 20401 || subsetHandlerKey == 40401)
      return Subset_20401(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20410 || subsetHandlerKey == 40410)
      return Subset_20410(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20420 || subsetHandlerKey == 40420)
      return Subset_20420(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20430 || subsetHandlerKey == 40430)
      return Subset_20430(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 20440 || subsetHandlerKey == 40440)
      return Subset_20440(levelPx, levelIdx, kLast);


   // Explicit 4xxxx variants
   if(subsetHandlerKey == 40192 || subsetHandlerKey == 20192)
      return Subset_40192_quant20105(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 40193 || subsetHandlerKey == 20193)
      return Subset_40193_from20113(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 40194 || subsetHandlerKey == 20194)
      return Subset_40194_from20113(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 40195 || subsetHandlerKey == 20195)
      return Subset_40195_quant20101(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 40196 || subsetHandlerKey == 20196)
      return Subset_40196_quant20101(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 40197 || subsetHandlerKey == 20197)
      return Subset_40197_quant40111_20105(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 40188)
      return Subset_40188_quant40197(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 40189)
      return Subset_40189_quant40197(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 40190)
      return Subset_40190_quant40197(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 40191)
      return Subset_40191_quant40197(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 40198 || subsetHandlerKey == 20198)
      return Subset_40198_quant20101(levelPx, levelIdx, kLast);
   if(subsetHandlerKey == 40199 || subsetHandlerKey == 20199)
      return Subset_40199_quant20101(levelPx, levelIdx, kLast);


   // If an enabled variant passes stage 1 but has no stage-2 rule subset function, it's a config error.
   FatalError(StringFormat("bookmarkE1 Missing stage-2 rule subset function for subset key %d (slots %d, %d, %d), magic %s. Check PendingRuleSubsetPassesForFullMagic",
      subsetHandlerKey, slot1, slot2, slot3, IntegerToString(fullMagic)));
   return false; // Unreachable, but keeps compiler happy.
   // bookmark8 bookdispatch
}
//+------------------------------------------------------------------+
//| Validate trade_size_percentage is one of 10,20,...,100. FatalError if not. |
//+------------------------------------------------------------------+
int ValidateTradeSizePct(int pct, int variantIdx)
{
   if(pct == 10 || pct == 20 || pct == 30 || pct == 40 || pct == 50 ||
      pct == 60 || pct == 70 || pct == 80 || pct == 90 || pct == 100)
      return pct;
   FatalError(StringFormat("g_trade[%d].tradeSizePct must be one of 10,20,...,100; got %d", variantIdx, pct));
   return 100;  // unreachable
}

//+------------------------------------------------------------------+
//| Lot for g_trade[variantIdx] = global_base_trade_size × (trade_size_percentage/100). Normalized to symbol min/max/step. |
//+------------------------------------------------------------------+
double GetTradeLotForVariant(int variantIdx)
{
   double base = g_global_base_trade_size;
   int pct = 100;
   if(variantIdx >= 0 && variantIdx < TRADE_VARIANT_COUNT)
      pct = ValidateTradeSizePct(g_trade[variantIdx].tradeSizePct, variantIdx);
   double lot = base * ((double)pct / 100.0);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = NormalizeDouble(MathFloor(lot / step + 0.0001) * step, 2);
   if(lot < minLot) lot = minLot;
   return lot;
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

   // Look up the original offset from the variant config using the magic number
   int variantIdx = FindVariantIndexForCompositeMagic(magic);
   string offsetStr = "N/A";
   if(variantIdx != -1)
      offsetStr = DoubleToString(g_trade[variantIdx].levelOffsetPoints, 1);

   Print(StringFormat("Attempting %s Magic=%s Level=%s Offset=%s OrderPrice=%s ExpMin=%d Bid=%s Ask=%s StreakAbove=%d StreakBelow=%d",
         type, IntegerToString(magic), DoubleToString(levelPrice, _Digits), offsetStr, DoubleToString(orderPrice, _Digits), expirationMin,
         DoubleToString(g_liveBid, _Digits), DoubleToString(g_liveAsk, _Digits),
         sAbove, sBelow));
}

//+------------------------------------------------------------------+
//| Place a buy-limit at level with given PointSized offsets and expiration. Sets magic then restores DEFAULT_ORDER_MAGIC. Returns true if order sent successfully. |
//+------------------------------------------------------------------+
bool PlaceBuyLimitAtLevel(double levelPrice, double offsetPoints, double slPoints, double tpPoints, int expirationMin, double lot, long magic)
{
   if(maemfe_testing) { tpPoints = 3000.0; slPoints = 3000.0; }
   double orderPrice = 0.0, stopLossVal = 0.0, takeProfitVal = 0.0;
   PendingOrderPricesForDirection(MAGIC_TRADE_LONG, levelPrice, offsetPoints, slPoints, tpPoints, orderPrice, stopLossVal, takeProfitVal);
   datetime expiration = TimeCurrent() + expirationMin * 60;
   string comment = BuildUnifiedOrderComment(levelPrice, takeProfitVal, stopLossVal, orderPrice, magic);
   LogPreOrderContext(magic, levelPrice, orderPrice, "BuyLimit", expirationMin);
   ExtTrade.SetExpertMagicNumber(magic);
   bool ok = ExtTrade.BuyLimit(lot, orderPrice, _Symbol, stopLossVal, takeProfitVal, ORDER_TIME_SPECIFIED, expiration, comment);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   return ok;
}

//+------------------------------------------------------------------+
//| Sell limit: level − offset; SL above, TP below (no exit spread bump). |
//+------------------------------------------------------------------+
bool PlaceSellLimitAtLevel(double levelPrice, double offsetPoints, double slPoints, double tpPoints, int expirationMin, double lot, long magic)
{
   if(maemfe_testing) { tpPoints = 3000.0; slPoints = 3000.0; }
   double orderPrice = 0.0, stopLossVal = 0.0, takeProfitVal = 0.0;
   PendingOrderPricesForDirection(MAGIC_TRADE_SHORT, levelPrice, offsetPoints, slPoints, tpPoints, orderPrice, stopLossVal, takeProfitVal);
   datetime expiration = TimeCurrent() + expirationMin * 60;
   string comment = BuildUnifiedOrderComment(levelPrice, takeProfitVal, stopLossVal, orderPrice, magic);
   LogPreOrderContext(magic, levelPrice, orderPrice, "SellLimit", expirationMin);
   ExtTrade.SetExpertMagicNumber(magic);
   bool ok = ExtTrade.SellLimit(lot, orderPrice, _Symbol, stopLossVal, takeProfitVal, ORDER_TIME_SPECIFIED, expiration, comment);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   return ok;
}

//+------------------------------------------------------------------+
//| Sell stop at (level+off)−s: triggers on Bid; pairs buy limit at level+off (Ask). SL/TP from ref = orderPrice+s (= limit+off), same absolute prices as Buy Limit SL/TP. |
//| Short risk: SL above entry, TP below. NOTE: MT5 requires pending SellStop price < Bid; if entry ends up above Bid, placement may fail (then SellLimit is the usual fix). |
//+------------------------------------------------------------------+
bool PlaceSellStopAtLevel(double levelPrice, double offsetPoints, double slPoints, double tpPoints, int expirationMin, double lot, long magic)
{
   if(maemfe_testing) { tpPoints = 3000.0; slPoints = 3000.0; }
   double orderPrice = 0.0, stopLossVal = 0.0, takeProfitVal = 0.0;
   PendingOrderPricesForDirection(MAGIC_TRADE_LONG_REVERSED, levelPrice, offsetPoints, slPoints, tpPoints, orderPrice, stopLossVal, takeProfitVal);
   datetime expiration = TimeCurrent() + expirationMin * 60;
   string comment = BuildUnifiedOrderComment(levelPrice, takeProfitVal, stopLossVal, orderPrice, magic);
   LogPreOrderContext(magic, levelPrice, orderPrice, "SellStop", expirationMin);
   ExtTrade.SetExpertMagicNumber(magic);
   bool ok = ExtTrade.SellStop(lot, orderPrice, _Symbol, stopLossVal, takeProfitVal, ORDER_TIME_SPECIFIED, expiration, comment);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   return ok;
}

//+------------------------------------------------------------------+
//| Buy stop at (level−off)+s: triggers on Ask; pairs sell limit at level−off (Bid). SL/TP from ref = orderPrice−s: SL = SellLimit TP, TP = SellLimit SL. |
//+------------------------------------------------------------------+
bool PlaceBuyStopAtLevel(double levelPrice, double offsetPoints, double slPoints, double tpPoints, int expirationMin, double lot, long magic)
{
   if(maemfe_testing) { tpPoints = 3000.0; slPoints = 3000.0; }
   double orderPrice = 0.0, stopLossVal = 0.0, takeProfitVal = 0.0;
   PendingOrderPricesForDirection(MAGIC_TRADE_SHORT_REVERSED, levelPrice, offsetPoints, slPoints, tpPoints, orderPrice, stopLossVal, takeProfitVal);
   datetime expiration = TimeCurrent() + expirationMin * 60;
   string comment = BuildUnifiedOrderComment(levelPrice, takeProfitVal, stopLossVal, orderPrice, magic);
   LogPreOrderContext(magic, levelPrice, orderPrice, "BuyStop", expirationMin);
   ExtTrade.SetExpertMagicNumber(magic);
   bool ok = ExtTrade.BuyStop(lot, orderPrice, _Symbol, stopLossVal, takeProfitVal, ORDER_TIME_SPECIFIED, expiration, comment);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   return ok;
}

//+------------------------------------------------------------------+
//| Composite magic digit 1 (ParseCompositeMagic.direction) selects pending order type. |
//+------------------------------------------------------------------+
bool PlacePendingFromMagic(long magic, double anchorLevel, double offsetPoints, double slPoints, double tpPoints, int expirationMin, double lot)
{
   int dir = ParseCompositeMagic(magic).direction;
   switch(dir)
   {
      case MAGIC_TRADE_LONG:
         return PlaceBuyLimitAtLevel(anchorLevel, offsetPoints, slPoints, tpPoints, expirationMin, lot, magic);
      case MAGIC_TRADE_SHORT:
         return PlaceSellLimitAtLevel(anchorLevel, offsetPoints, slPoints, tpPoints, expirationMin, lot, magic);
      case MAGIC_TRADE_LONG_REVERSED:
         return PlaceSellStopAtLevel(anchorLevel, offsetPoints, slPoints, tpPoints, expirationMin, lot, magic);
      case MAGIC_TRADE_SHORT_REVERSED:
         return PlaceBuyStopAtLevel(anchorLevel, offsetPoints, slPoints, tpPoints, expirationMin, lot, magic);
      default:
         return false;
   }
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
//| Count open positions + pending orders with this exact magic (trading: limit per magic, not per level) |
//+------------------------------------------------------------------+
int CountOrdersAndPositionsForMagic(long magic)
{
   int count = 0;
   for(int posIdx = PositionsTotal() - 1; posIdx >= 0; posIdx--)
   {
      if(!ExtPositionInfo.SelectByIndex(posIdx)) continue;
      if(ExtPositionInfo.Symbol() != _Symbol) continue;
      if(ExtPositionInfo.Magic() == magic) count++;
   }
   for(int orderIdx = OrdersTotal() - 1; orderIdx >= 0; orderIdx--)
   {
      if(!ExtOrderInfo.SelectByIndex(orderIdx)) continue;
      if(ExtOrderInfo.Symbol() != _Symbol) continue;
      if(ExtOrderInfo.Magic() == magic) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Basic rule: true when no open position or pending order with this magic (allows placing new order). |
//+------------------------------------------------------------------+
bool CanPlaceNewOrderForMagic(long magic)
{
   return (CountOrdersAndPositionsForMagic(magic) == 0);
}

//+------------------------------------------------------------------+
//| Close any position opened by this EA (IsVariantTradeCompositeMagic) open longer than minutes. Sets trade magic so OUT deal pairs with IN. |
//+------------------------------------------------------------------+
void CloseAnyEAPositionThatIsXMinutesOld(int minutes)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!ExtPositionInfo.SelectByIndex(i)) continue;
      if(ExtPositionInfo.Symbol() != _Symbol) continue;
      long posMagic = ExtPositionInfo.Magic();
      if(!IsVariantTradeCompositeMagic(posMagic)) continue;
      if(g_lastTimer1Time - ExtPositionInfo.Time() <= (datetime)(minutes * 60)) continue;
      ExtTrade.SetExpertMagicNumber((ulong)posMagic);
      ExtTrade.PositionClose(ExtPositionInfo.Ticket());
      ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   }
}

//+------------------------------------------------------------------+
//| If latest closed M1 candle (bar 1) is 21:57, close all EA positions (so EOD write at 21:58 sees OUT). Sets trade magic so OUT pairs with IN. |
//+------------------------------------------------------------------+
void CloseAnyOpenTrade_atEOD_2158()
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
      if(!IsVariantTradeCompositeMagic(posMagic)) continue;
      ExtTrade.SetExpertMagicNumber((ulong)posMagic);
      ExtTrade.PositionClose(ExtPositionInfo.Ticket());
      ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   }
}

//+------------------------------------------------------------------+
//| Full composite magic as COMPOSITE_MAGIC_STRING_LEN-char string for B_TradeLog filename; "" if not a variant magic. |
//+------------------------------------------------------------------+
string GetMagicStrForLogFilename(long magic)
{
   if(!IsVariantTradeCompositeMagic(magic)) return "";
   return MagicNumberToFixedWidthString(magic);
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
   if(!finalLog_TradeLog) return;
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
int OnInit()
{
   FileDelete("summary_tradeResults_all_days.csv");

   Print("Level Logger EA initialized.");
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);

   ValidateMagicCompositionOnInit();

   for(int variantIdx = 0; variantIdx < TRADE_VARIANT_COUNT; variantIdx++)
      g_tradeConfig[variantIdx].bannedRangesStr = g_trade[variantIdx].bannedRanges;
   RebuildAllVariantBannedRangesCache();

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
//| OnTimer(1s) pending pipeline — maybe stage 1 → maybe stage 2 → place (F):                |
//|  A. Prerequisites: levels + bars; nearest levels below/above bid.                       |
//|  B–C. One loop per row: fullMagic = BuildMagicForVariant(variantIdx) once; proximity +    |
//|      stage-1 gates use that same fullMagic; store it on maybeStage1Candidates.          |
//|  D–E. Stage-2 rule disptcher (fullMagic); copy fullMagic → maybeStage2.                  |
//|  F. PlacePendingFromMagic(fullMagic,…) + log.                                           |
//+------------------------------------------------------------------+
void RunTimerPendingNearLevelsPipeline()
{
   //--- A. Prerequisites
   if(!HasAnyLevelToday() || g_barsInDay <= 0) return;
   const int lastBarIndexToday = g_barsInDay - 1; // index into g_session[], g_m1Rates[], etc. for the current (forming) bar
   const double nearestLevelBelowBid = Rules_GetClosestNonTertiaryLevelBelowPrice(g_liveBid);
   const double nearestLevelAboveBid = Rules_GetClosestNonTertiaryLevelAbovePrice(g_liveBid);
   if(nearestLevelBelowBid <= 0.0 && nearestLevelAboveBid <= 0.0) return;

   //--- B–C. Proximity, then stage-1 gates, per g_trade[] row (single loop)
   int maybeStage1Count = 0;
   for(int variantIdx = 0; variantIdx < TRADE_VARIANT_COUNT; variantIdx++)
   {
      if(!g_trade[variantIdx].enabled) continue;
      const double triggerDistancePts = g_trade[variantIdx].livePriceDiffTrigger;
      if(!PendingVariantWithinPriceTriggerDistance(variantIdx, nearestLevelBelowBid, nearestLevelAboveBid, triggerDistancePts))
         continue;

      const long fullMagic = BuildMagicForVariant(variantIdx);
      if(!IsTimeAllowedForTradeType(variantIdx, g_lastTimer1Time)) continue;
      if(!CanPlaceNewOrderForMagic(fullMagic)) continue;
      if(!MeetsMagicSessionPdEntryGate(fullMagic, lastBarIndexToday)) continue;
      if(!PendingPassesRulesetPolicy(variantIdx)) continue;

      const int levelIndexBelow = (nearestLevelBelowBid > 0.0) ? FindExpandedLevelIndexByPrice(nearestLevelBelowBid) : -1;
      const int levelIndexAbove = (nearestLevelAboveBid > 0.0) ? FindExpandedLevelIndexByPrice(nearestLevelAboveBid) : -1;
      const int proximityFocus = g_trade[variantIdx].levelProximityFocus;
      if(proximityFocus == TRADE_LEVEL_FOCUS_BELOW && levelIndexBelow < 0) continue;
      if(proximityFocus == TRADE_LEVEL_FOCUS_ABOVE && levelIndexAbove < 0) continue;
      if(proximityFocus == TRADE_LEVEL_FOCUS_BOTH && levelIndexBelow < 0 && levelIndexAbove < 0) continue;

      g_pendingPipelineStage1[maybeStage1Count].variantIdx = variantIdx;
      g_pendingPipelineStage1[maybeStage1Count].fullMagic = fullMagic;
      g_pendingPipelineStage1[maybeStage1Count].nearestLevelBelowBid = nearestLevelBelowBid;
      g_pendingPipelineStage1[maybeStage1Count].nearestLevelAboveBid = nearestLevelAboveBid;
      g_pendingPipelineStage1[maybeStage1Count].levelIndexBelow = levelIndexBelow;
      g_pendingPipelineStage1[maybeStage1Count].levelIndexAbove = levelIndexAbove;
      g_pendingPipelineStage1[maybeStage1Count].lastBarIndexToday = lastBarIndexToday;
      g_pendingPipelineStage1[maybeStage1Count].pendingOffsetPoints = g_trade[variantIdx].levelOffsetPoints;
      maybeStage1Count++;
   }
   if(maybeStage1Count == 0) return;

   //--- D–E. Stage 2: use fullMagic carried from B–C (must still match row config).
   int maybeStage2Count = 0;
   for(int stage1Idx = 0; stage1Idx < maybeStage1Count; stage1Idx++)
   {
      const PendingMaybeCandidate s1 = g_pendingPipelineStage1[stage1Idx];
      const int variantIdx = s1.variantIdx;
      const long fullMagic = s1.fullMagic;
      EntryLevelCtx entryLevel = PendingBuildEntryLevelCtx(variantIdx,
         s1.nearestLevelBelowBid, s1.levelIndexBelow, s1.nearestLevelAboveBid, s1.levelIndexAbove);
      bool ruleSubsetPasses = false;
      if(entryLevel.ok && fullMagic == BuildMagicForVariant(variantIdx))
         ruleSubsetPasses = PendingRuleSubsetPassesForFullMagic(fullMagic, entryLevel.levelPx, entryLevel.levelIdx, s1.lastBarIndexToday);
      if(!ruleSubsetPasses) continue;

      const double triggerDistancePts = g_trade[variantIdx].livePriceDiffTrigger;
      const double anchorLevelPrice = PendingOrderAnchorLevelForVariant(variantIdx,
         s1.nearestLevelBelowBid, s1.nearestLevelAboveBid, triggerDistancePts);
      if(anchorLevelPrice <= 0.0) continue;

      g_pendingPipelineStage2[maybeStage2Count].variantIdx = variantIdx;
      g_pendingPipelineStage2[maybeStage2Count].fullMagic = fullMagic;
      g_pendingPipelineStage2[maybeStage2Count].anchorLevelPrice = anchorLevelPrice;
      g_pendingPipelineStage2[maybeStage2Count].pendingOffsetPoints = s1.pendingOffsetPoints;
      g_pendingPipelineStage2[maybeStage2Count].slPointsInput = g_trade[variantIdx].slPoints;
      g_pendingPipelineStage2[maybeStage2Count].tpPointsInput = g_trade[variantIdx].tpPoints;
      maybeStage2Count++;
   }

   //--- F. Trade attempts — PlacePendingFromMagic (+ log). fullMagic carried from D–E.
   for(int placeIdx = 0; placeIdx < maybeStage2Count; placeIdx++)
   {
      const PendingMaybeStage2Candidate s2 = g_pendingPipelineStage2[placeIdx];
      const int variantIdx = s2.variantIdx;
      const long fullMagic = s2.fullMagic;
      if(fullMagic != BuildMagicForVariant(variantIdx)) continue;
      if(PlacePendingFromMagic(fullMagic, s2.anchorLevelPrice, s2.pendingOffsetPoints, s2.slPointsInput, s2.tpPointsInput, 5, GetTradeLotForVariant(variantIdx)))
         WriteTradeLogPendingOrder(s2.anchorLevelPrice, s2.pendingOffsetPoints, s2.slPointsInput, s2.tpPointsInput, fullMagic);
   }
}

//+------------------------------------------------------------------+
//| ExtPositionInfo must already select the position. After babysitStartMinute open time, tighten SL in steps from entry (only tighter). |
//| Phase 1: loss-side ladder — magnitudes 0.5..10 in same PointSized “points” as g_trade / magic TP|SL. Phase 2: profit SL same units. |
//| One snapshot at start; after successful modify, trust newSL (no ExtPositionInfo re-read in this function). |
//| No-op unless babysitEnabled (g_trade[].babysit_enabled). Negative babysitStartMinute also off. |
//+------------------------------------------------------------------+
void Babysitf_ifBSenabled_TryTightenStops_profitableSL_todo_test(const long positionMagic, const bool babysitEnabled, const int babysitStartMinute)
{
   if(!babysitEnabled) return;
   //--- 1. Babysit disabled for this row (negative minute = off).
   if(babysitStartMinute < 0) return;
   //--- 2. Age of position in whole minutes (position open time vs last 1s timer tick).
   int minutesOpen = (int)((g_lastTimer1Time - ExtPositionInfo.Time()) / 60);
   //--- 3. Do nothing until the trade has been open at least babysitStartMinute minutes.
   if(minutesOpen < babysitStartMinute) return;
   //--- 4. Ladder magnitudes (magic / g_trade points) → price via PointSized. rungOffset = SL-open (buy) / open-SL (sell) at that rung on loss side.
   double loss_mag[] = {0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0};
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tol = point * 0.5;
   //--- 5. Snapshot selected position: open, TP, ticket, side, current SL.
   double openPrice = ExtPositionInfo.PriceOpen();
   double currentTP = ExtPositionInfo.TakeProfit();
   ulong ticket = ExtPositionInfo.Ticket();
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)ExtPositionInfo.PositionType();
   double currentSL = ExtPositionInfo.StopLoss();
   //--- 6. currentOffset in price (buy: SL - open; sell: open - SL). More negative = stop further from entry on the protective side.
   double currentOffset = (posType == POSITION_TYPE_BUY) ? (currentSL - openPrice) : (openPrice - currentSL);
   //--- 7. PositionModify must use this row’s magic so the server accepts the change.
   ExtTrade.SetExpertMagicNumber((ulong)positionMagic);
   for(int targetIdx = 0; targetIdx < ArraySize(loss_mag); targetIdx++)
   {
      const double rungOffset = -PointSized(loss_mag[targetIdx]);
      //--- 8. Skip rungs already achieved or passed (would only loosen / duplicate).
      if(rungOffset <= currentOffset) continue;
      //--- 9. New SL at this rung (price).
      double newSL = (posType == POSITION_TYPE_BUY) ? openPrice + rungOffset : openPrice - rungOffset;
      newSL = NormalizeDouble(newSL, _Digits);
      //--- 10. Broker already has this SL within tolerance — stop (no pointless retries).
      if(MathAbs(newSL - currentSL) <= tol) break;
      //--- 11. Apply SL; TP unchanged. On failure, try next rung; on success, trust newSL (no ExtPositionInfo re-read in this function).
      const string sideStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      const string slWasLoss = (currentSL > 0.0) ? DoubleToString(currentSL, _Digits) : "none";
      Print(StringFormat(
               "Babysitf_ifBSenabled_TryTightenStops_profitableSL_todo_test TRY phase=loss ticket=%I64u magic=%I64d sym=%s %s open=%s SL %s -> %s TP=%s loss_rung_mag=%s minutesOpen=%d babysitStartMin=%d",
               ticket,
               positionMagic,
               _Symbol,
               sideStr,
               DoubleToString(openPrice, _Digits),
               slWasLoss,
               DoubleToString(newSL, _Digits),
               DoubleToString(currentTP, _Digits),
               DoubleToString(loss_mag[targetIdx], 1),
               minutesOpen,
               babysitStartMinute));
      if(!ExtTrade.PositionModify(ticket, newSL, currentTP))
      {
         Print(StringFormat(
                  "Babysitf_ifBSenabled_TryTightenStops_profitableSL_todo_test FAIL phase=loss ticket=%I64u retcode=%u %s",
                  ticket,
                  ExtTrade.ResultRetcode(),
                  ExtTrade.ResultRetcodeDescription()));
         continue;
      }
      currentSL = newSL;
      currentOffset = (posType == POSITION_TYPE_BUY) ? (currentSL - openPrice) : (openPrice - currentSL);
      //--- 12. Rung reached — done for this timer pass.
      if(currentOffset >= rungOffset - tol) break;
   }

   //--- 13. Phase 2 — profit-side SL: only after loss ladder is at the tightest rung (same snapshot/updates as phase 1; no re-select).
   if(currentSL <= 0.0)
   {
      ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
      return;
   }
   const double tightestLossRungOffset = -PointSized(loss_mag[0]);
   if(currentOffset < tightestLossRungOffset - tol)
   {
      ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
      return;
   }

   double profit_mag[] = {0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0};
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int pi = 0; pi < ArraySize(profit_mag); pi++)
   {
      const double pPx = PointSized(profit_mag[pi]);
      double newSL;
      if(posType == POSITION_TYPE_BUY)
      {
         newSL = NormalizeDouble(openPrice + pPx, _Digits);
         if(currentSL >= newSL - tol)
            continue;
         if(newSL >= bid)
            break;
      }
      else
      {
         newSL = NormalizeDouble(openPrice - pPx, _Digits);
         if(currentSL <= newSL + tol)
            continue;
         if(newSL <= ask)
            break;
      }
      if(MathAbs(newSL - currentSL) <= tol)
         break;
      const string sideStrP = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      const string slWasProfit = (currentSL > 0.0) ? DoubleToString(currentSL, _Digits) : "none";
      Print(StringFormat(
               "Babysitf_ifBSenabled_TryTightenStops_profitableSL_todo_test TRY phase=profit ticket=%I64u magic=%I64d sym=%s %s open=%s bid=%s ask=%s SL %s -> %s TP=%s profit_rung_mag=%s minutesOpen=%d babysitStartMin=%d",
               ticket,
               positionMagic,
               _Symbol,
               sideStrP,
               DoubleToString(openPrice, _Digits),
               DoubleToString(bid, _Digits),
               DoubleToString(ask, _Digits),
               slWasProfit,
               DoubleToString(newSL, _Digits),
               DoubleToString(currentTP, _Digits),
               DoubleToString(profit_mag[pi], 1),
               minutesOpen,
               babysitStartMinute));
      if(!ExtTrade.PositionModify(ticket, newSL, currentTP))
      {
         Print(StringFormat(
                  "Babysitf_ifBSenabled_TryTightenStops_profitableSL_todo_test FAIL phase=profit ticket=%I64u retcode=%u %s",
                  ticket,
                  ExtTrade.ResultRetcode(),
                  ExtTrade.ResultRetcodeDescription()));
         continue;
      }
      currentSL = newSL;
      break;
   }

   //--- 14. Restore default magic for the rest of the EA.
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
}

//+------------------------------------------------------------------+
//| Same timing/ladder idea as TightenStops, but tighten TP toward entry (only tighter / closer to open). |
//| Ladder magnitudes 0.5..10 in same PointSized “points” as g_trade / magic TP|SL. SL left unchanged. |
//| After successful modify: trust newTP (no ExtPositionInfo re-read in this function). |
//| No-op unless babysitEnabled (g_trade[].babysit_enabled). Negative babysitStartMinute also off. |
//+------------------------------------------------------------------+
void Babysitf_ifBSenabled_TryTightenStops_reduceTP_toTest_pointsized(const long positionMagic, const bool babysitEnabled, const int babysitStartMinute)
{
   if(!babysitEnabled) return;
   if(babysitStartMinute < 0) return;
   int minutesOpen = (int)((g_lastTimer1Time - ExtPositionInfo.Time()) / 60);
   if(minutesOpen < babysitStartMinute) return;

   double tp_mag[] = {0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0};
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tol = point * 0.5;

   double openPrice = ExtPositionInfo.PriceOpen();
   double currentSL = ExtPositionInfo.StopLoss();
   ulong ticket = ExtPositionInfo.Ticket();
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)ExtPositionInfo.PositionType();
   double currentTP = ExtPositionInfo.TakeProfit();

   // Offset in price: BUY (TP-open); SELL (open-TP). Larger = TP farther into profit side from entry.
   double currentOffset = (posType == POSITION_TYPE_BUY) ? (currentTP - openPrice) : (openPrice - currentTP);

   ExtTrade.SetExpertMagicNumber((ulong)positionMagic);
   for(int targetIdx = 0; targetIdx < ArraySize(tp_mag); targetIdx++)
   {
      const double rungPx = PointSized(tp_mag[targetIdx]);
      // Skip rungs we already tightened past (TP closer to entry than this rung).
      if(rungPx >= currentOffset - tol) continue;

      double newTP = (posType == POSITION_TYPE_BUY) ? openPrice + rungPx : openPrice - rungPx;
      newTP = NormalizeDouble(newTP, _Digits);
      if(MathAbs(newTP - currentTP) <= tol) break;
      const string sideStrTp = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      const string slStrTp = (currentSL > 0.0) ? DoubleToString(currentSL, _Digits) : "none";
      const string tpWasTp = (currentTP > 0.0) ? DoubleToString(currentTP, _Digits) : "none";
      Print(StringFormat(
               "Babysitf_ifBSenabled_TryTightenStops_reduceTP_toTest_pointsized TRY ticket=%I64u magic=%I64d sym=%s %s open=%s SL=%s TP %s -> %s tp_rung_mag=%s minutesOpen=%d babysitStartMin=%d",
               ticket,
               positionMagic,
               _Symbol,
               sideStrTp,
               DoubleToString(openPrice, _Digits),
               slStrTp,
               tpWasTp,
               DoubleToString(newTP, _Digits),
               DoubleToString(tp_mag[targetIdx], 1),
               minutesOpen,
               babysitStartMinute));
      if(!ExtTrade.PositionModify(ticket, currentSL, newTP))
      {
         Print(StringFormat(
                  "Babysitf_ifBSenabled_TryTightenStops_reduceTP_toTest_pointsized FAIL ticket=%I64u retcode=%u %s",
                  ticket,
                  ExtTrade.ResultRetcode(),
                  ExtTrade.ResultRetcodeDescription()));
         continue;
      }
      currentTP = newTP;
      currentOffset = (posType == POSITION_TYPE_BUY) ? (currentTP - openPrice) : (openPrice - currentTP);
      if(currentOffset <= rungPx + tol) break;
   }
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
}

//+------------------------------------------------------------------+
//| ExtPositionInfo must already select the position. If live quote is far enough in profit vs PriceOpen, market-close (buy: Bid; sell: Ask). |
//| profitInputPoints: same units as g_trade TP/SL; distance = PointSized(profitInputPoints). |
//| Returns true if PositionClose reported success (position may be gone). |
//+------------------------------------------------------------------+
bool Babysitf_Try_CloseForProfit(const long positionMagic, const double profitInputPoints)
{
   if(profitInputPoints <= 0.0)
      return false;

   const double minProfitDistance = PointSized(profitInputPoints);
   const double openPrice = ExtPositionInfo.PriceOpen();
   const ulong ticket = ExtPositionInfo.Ticket();
   const ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)ExtPositionInfo.PositionType();

   ExtTrade.SetExpertMagicNumber((ulong)positionMagic);
   bool closed = false;
   if(posType == POSITION_TYPE_BUY)
   {
      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid >= openPrice + minProfitDistance)
         closed = ExtTrade.PositionClose(ticket);
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(ask <= openPrice - minProfitDistance)
         closed = ExtTrade.PositionClose(ticket);
   }
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   return closed;
}


//+------------------------------------------------------------------+
//| ExtPositionInfo must already select the position.                |
//| Distance to TP: BUY uses g_liveBid; SELL uses g_liveAsk (OnTimer). |
//| Distance to SL: BUY (Bid−SL); SELL (SL−Ask).                     |
//| Proximity / open-offset use same price distance as pending TP/SL: |
//| Proximity / open-offset: PointSized(...) (see Babysitf_Try_CloseForProfit). |
//| Within 3.0 points of TP: SL = open ± 0.5 points (BUY +, SELL −). |
//| Within 3.0 points of SL: TP = open ∓ 0.5 points (BUY −, SELL +). |
//| Only tightens; returns true if PositionModify succeeds.          |
//+------------------------------------------------------------------+
bool Babysitf_SecurePosition(const long positionMagic)
{
   const double targetProximity = PointSized(1.4);
   const double secureDist = PointSized(0.7);

   const ulong ticket = ExtPositionInfo.Ticket();
   const double openPrice = ExtPositionInfo.PriceOpen();
   const double currentSL = ExtPositionInfo.StopLoss();
   const double currentTP = ExtPositionInfo.TakeProfit();
   const ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)ExtPositionInfo.PositionType();

   const double bid = g_liveBid;
   const double ask = g_liveAsk;

   double newSL = currentSL;
   double newTP = currentTP;
   bool changeSL = false;
   bool changeTP = false;

   if(posType == POSITION_TYPE_BUY)
   {
      if(currentTP > 0.0 && (currentTP - bid) <= targetProximity)
      {
         const double sl = NormalizeDouble(openPrice + secureDist, _Digits);
         if(sl < bid && (currentSL <= 0.0 || sl > currentSL))
         {
            newSL = sl;
            changeSL = true;
         }
      }
      if(currentSL > 0.0 && (bid - currentSL) <= targetProximity)
      {
         const double tp = NormalizeDouble(openPrice - secureDist, _Digits);
         if(tp > ask && (currentTP <= 0.0 || tp < currentTP))
         {
            newTP = tp;
            changeTP = true;
         }
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      if(currentTP > 0.0 && (ask - currentTP) <= targetProximity)
      {
         const double sl = NormalizeDouble(openPrice - secureDist, _Digits);
         if(sl > ask && (currentSL <= 0.0 || sl < currentSL))
         {
            newSL = sl;
            changeSL = true;
         }
      }
      if(currentSL > 0.0 && (currentSL - ask) <= targetProximity)
      {
         const double tp = NormalizeDouble(openPrice + secureDist, _Digits);
         if(tp < bid && (currentTP <= 0.0 || tp > currentTP))
         {
            newTP = tp;
            changeTP = true;
         }
      }
   }

   if(!changeSL && !changeTP)
      return false;

   if(!changeSL)
      newSL = currentSL;
   if(!changeTP)
      newTP = currentTP;

   string reasons = "";
   if(changeSL)
      reasons += (reasons != "" ? "; " : "") + "near TP: SL=open" + (posType == POSITION_TYPE_BUY ? "+" : "-") + "0.5pt";
   if(changeTP)
      reasons += (reasons != "" ? "; " : "") + "near SL: TP=open" + (posType == POSITION_TYPE_BUY ? "-" : "+") + "0.5pt";

   double distQuoteToTP = 0.0;
   double distQuoteToSL = 0.0;
   if(posType == POSITION_TYPE_BUY)
   {
      if(currentTP > 0.0)
         distQuoteToTP = currentTP - bid;
      if(currentSL > 0.0)
         distQuoteToSL = bid - currentSL;
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      if(currentTP > 0.0)
         distQuoteToTP = ask - currentTP;
      if(currentSL > 0.0)
         distQuoteToSL = currentSL - ask;
   }

   const string sideStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
   const string slWas = (currentSL > 0.0) ? DoubleToString(currentSL, _Digits) : "none";
   const string tpWas = (currentTP > 0.0) ? DoubleToString(currentTP, _Digits) : "none";
   Print(StringFormat(
            "Babysitf_SecurePosition TRY %s ticket=%I64u magic=%I64d sym=%s reasons=[%s] bid=%s ask=%s open=%s | SL %s -> %s | TP %s -> %s | distToTP=%s distToSL=%s | maxDist=%s (3.0 PointSized→price) openLegOffset=%s (0.5 PointSized→price)",
            sideStr,
            ticket,
            positionMagic,
            _Symbol,
            reasons,
            DoubleToString(bid, _Digits),
            DoubleToString(ask, _Digits),
            DoubleToString(ExtPositionInfo.PriceOpen(), _Digits),
            slWas,
            DoubleToString(newSL, _Digits),
            tpWas,
            DoubleToString(newTP, _Digits),
            DoubleToString(distQuoteToTP, _Digits),
            DoubleToString(distQuoteToSL, _Digits),
            DoubleToString(targetProximity, _Digits),
            DoubleToString(secureDist, _Digits)));

   ExtTrade.SetExpertMagicNumber((ulong)positionMagic);
   const bool ok = ExtTrade.PositionModify(ticket, newSL, newTP);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   if(!ok)
      Print(StringFormat(
               "Babysitf_SecurePosition FAIL ticket=%I64u retcode=%u %s",
               ticket,
               ExtTrade.ResultRetcode(),
               ExtTrade.ResultRetcodeDescription()));
   return ok;
}

//+------------------------------------------------------------------+
//| Closes the position if the current price is within a specified distance of the TP.
//| pointsThreshold: e.g. 0.2. Works for both long and short positions.
//+------------------------------------------------------------------+
bool Babysitf_CloseForProfit_if_AlmostTP(const long positionMagic, const double pointsThreshold)
{
   if(pointsThreshold <= 0.0) return false;

   double currentTP = ExtPositionInfo.TakeProfit();
   if(currentTP <= 0.0) return false; // Logic requires an active TP to compare against

   ulong ticket = ExtPositionInfo.Ticket();
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)ExtPositionInfo.PositionType();

   bool triggerClose = false;
   if(posType == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      // If Bid is at or above (TP - threshold), we are close enough to exit
      if(bid >= currentTP - pointsThreshold)
         triggerClose = true;
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      // If Ask is at or below (TP + threshold), we are close enough to exit
      if(ask <= currentTP + pointsThreshold)
         triggerClose = true;
   }

   if(!triggerClose) return false;

   ExtTrade.SetExpertMagicNumber((ulong)positionMagic);
   bool result = ExtTrade.PositionClose(ticket);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   return result;
}

//+------------------------------------------------------------------+
//| ExtPositionInfo must already select the position.                |
//| Do not use CObject::Type() for side — it is not POSITION_TYPE;   |
//| it returns a fixed object kind (0), which equals POSITION_TYPE_BUY.|
//+------------------------------------------------------------------+
bool ExtPositionInfo_IsBuy()
{
   return (ExtPositionInfo.PositionType() == POSITION_TYPE_BUY);
}
//+------------------------------------------------------------------+
//| ExtPositionInfo must already select the position.                |
//| Treat as "not sell-limit variant" when composite magic's MSD is not 2 |
//| (SELL_LIMIT encoding uses leading digit 2; POSITION_* has no SELL_LIMIT). |
//+------------------------------------------------------------------+
bool ExtPositionInfo__Is_NOT__SELL_LIMIT()
{
   long mag = ExtPositionInfo.Magic();
   ulong m = (mag >= 0) ? (ulong)mag : (ulong)(-mag);
   if(m == 0)
      return false;
   while(m >= 10)
      m /= 10;
   const int msd = (int)m;
   return (msd != 2);
}

//+------------------------------------------------------------------+
//| ExtPositionInfo must already select the position.                |
//| Treat as "not buy-stop variant" when composite magic's MSD is not 4 |
//| (BUY_STOP encoding uses leading digit 4; POSITION_* has no BUY_STOP). |
//+------------------------------------------------------------------+
bool ExtPositionInfo__Is_NOT__BUY_STOP()
{
   long mag = ExtPositionInfo.Magic();
   ulong m = (mag >= 0) ? (ulong)mag : (ulong)(-mag);
   if(m == 0)
      return false;
   while(m >= 10)
      m /= 10;
   const int msd = (int)m;
   return (msd != 4);
}

//+------------------------------------------------------------------+
//| ExtPositionInfo must already select the position.                |
//| BUY_LIMIT variant: composite magic's MSD is 1.                   |
//+------------------------------------------------------------------+
bool ExtPositionInfo__Is_BUY_LIMIT()
{
   long mag = ExtPositionInfo.Magic();
   ulong m = (mag >= 0) ? (ulong)mag : (ulong)(-mag);
   if(m == 0)
      return false;
   while(m >= 10)
      m /= 10;
   const int msd = (int)m;
   return (msd == 1);
}

//+------------------------------------------------------------------+
//| ExtPositionInfo must already select the position.                |
//| SELL_STOP variant: composite magic's MSD is 3.                   |
//+------------------------------------------------------------------+
bool ExtPositionInfo__Is_SELLSTOP()
{
   long mag = ExtPositionInfo.Magic();
   ulong m = (mag >= 0) ? (ulong)mag : (ulong)(-mag);
   if(m == 0)
      return false;
   while(m >= 10)
      m /= 10;
   const int msd = (int)m;
   return (msd == 3);
}

//+------------------------------------------------------------------+
//| On Timer helper |
//+------------------------------------------------------------------+
void Babysitf_RunAllOpenPositionsForSymbol()
{
   for(int positionIdx = PositionsTotal() - 1; positionIdx >= 0; positionIdx--)
   {
      if(!ExtPositionInfo.SelectByIndex(positionIdx))
         continue;
      if(ExtPositionInfo.Symbol() != _Symbol)
         continue;
      const long posMagic = ExtPositionInfo.Magic();
      if(!IsVariantTradeCompositeMagic(posMagic))
         continue;
      const int variantIdx = FindVariantIndexForCompositeMagic(posMagic);
      if(variantIdx < 0)
         continue;

      // shorty muszą być ciasne z niskim offset, trejdować na styk prawie, bo to są twarde sufity. 
      // wyłączyłem im securepos bo by było hyperactive przy ciasnym startowym SL (i TP dla revshort) od razu by pewnie przycieśniało
      //if(ExtPositionInfo__Is_NOT__SELL_LIMIT() && ExtPositionInfo__Is_NOT__BUY_STOP())
      //{
      //   if(Babysitf_SecurePosition(posMagic))
      //      continue;
      //}
      if(ExtPositionInfo__Is_BUY_LIMIT())
      {
         if(Babysitf_SecurePosition(posMagic))
            continue;
      }
      if(ExtPositionInfo__Is_SELLSTOP())
      {
         if(Babysitf_SecurePosition(posMagic))
            continue;
      }

      if(!g_trade[variantIdx].babysit_enabled)
         continue;

      Babysitf_ifBSenabled_TryTightenStops_profitableSL_todo_test(posMagic, g_trade[variantIdx].babysit_enabled, g_trade[variantIdx].babysitStart_minute);

      //if(Babysitf_CloseForProfit_if_AlmostTP(posMagic, 1.1))
      //   continue;

      // BELOW are checked ONLY if trade has babysit enabled

      // if
      //   Babysitf_Try_CloseForProfit
      // Babysitf_ifBSenabled_TryTightenStops_reduceTP_toTest_pointsized(posMagic, g_trade[variantIdx].babysit_enabled, g_trade[variantIdx].babysitStart_minute);

      //bookmark5 bookmarkbabysit
   }
}

//+------------------------------------------------------------------+
//| OnTimer(1s): detect new bar, load closed bar from history, run FinalizeCurrentCandle. Sets g_lastTimer1Time = TimeCurrent(). |
//+------------------------------------------------------------------+
void OnTimer()
{
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

   if(maemfe_testing)
      CloseAnyEAPositionThatIsXMinutesOld(10);

   // per open position, if variant has babysit_enabled run BabysitTryTightenStops after babysitStart_minute
   //if(babysit_global_flipper)
   Babysitf_RunAllOpenPositionsForSymbol();

   RunTimerPendingNearLevelsPipeline();

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
   if(barNowM1 == g_lastBarTime) return;

   g_lastBarTime = barNowM1;

   CloseAnyOpenTrade_atEOD_2158();   // closed candle 21:57 → close all EA positions (EOD write at 21:58)

   // Pull static context for today before refresh so PDC is available when building levels (single UpdateDayM1AndLevelsExpanded per bar)
   datetime dayStartForContext = g_lastTimer1Time - (g_lastTimer1Time % 86400);
   if(g_staticMarketContextPulledForDate != dayStartForContext)
   {
      UpdateStaticMarketContext(dayStartForContext);
      g_staticMarketContextPulledForDate = dayStartForContext;
   }

   // Refresh day M1 and levels first; then set closed-candle OHLC from same source (or terminal fallback)
   UpdateDayM1AndLevelsExpanded();
   SetClosedCandleOHLCFromDayM1OrTerminal();

   FinalizeCurrentCandle();

   // --- ON and RTH session high/low so far at each bar k (bars 0..k). Fresh each candle; log reads from g_*AtBar[k].
   UpdateONandRTHHighLowSoFarAtBar();

   // --- IB high/low (15:30–16:30 or 14:30–15:30); unknown before IB ends.
   UpdateIBHighLowAtBar();

   // --- Gap fill so far: % of gap filled by rthLowSoFar (gap up) or rthHighSoFar (gap down); unknown before RTH open.
   UpdateGapFillSoFarAtBar();

   // --- Trade results for the day (deals IN/OUT paired by magic; available globally)
   UpdateTradeResultsForDay();

   // --- Per-candle day progress (trades closed by each candle close time)
   UpdateDayProgress();

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

         string logName = dateStr + "_testing_pullinghistory.csv";

         // Log pullinghistory from g_m1Rates (only once per day; if file missing, write again). MT5 CSV with headers.
         if(dailyEODlog_PullingHistory && !FileIsExist(logName))
         {
            int fileHandle = FileOpen(logName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
            if(fileHandle == INVALID_HANDLE)
               FatalError("OnTimer: could not open " + logName);
            FileWrite(fileHandle, "time", "O", "H", "L", "C", "levelAboveH", "levelBelowL", "session",
                     "dayWinRate", "dayTradesCount", "dayPointsSum", "dayProfitSum",
                     "ONwinRate", "ONtradeCount", "ONpointsSum", "ONprofitSum",
                     "RTHwinRate", "RTHtradeCount", "RTHpointsSum", "RTHprofitSum",
                     "ONhighSoFar", "ONlowSoFar", "rthHighSoFar", "rthLowSoFar",
                     "dayHighSoFar", "dayLowSoFar",
                     "sessionRangeMidpoint",
                     "IBhigh", "IBlow",
                     "gapFillSoFar",
                     "RTHopen",
                     "PDOpreviousDayRTHOpen", "PDHpreviousDayHigh", "PDLpreviousDayLow", "PDCpreviousDayRTHClose", "PDdate",
                     "dayBrokePDH", "dayBrokePDL");
         for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
            {
               if(!g_ONhighSoFarAtBar[barIdx].hasValue || !g_ONlowSoFarAtBar[barIdx].hasValue)
                  FatalError("pullinghistory: ONhighSoFar/ONlowSoFar required but no ON bar so far at bar k=" + IntegerToString(barIdx) + " time=" + TimeToString(g_m1Rates[barIdx].time, TIME_DATE|TIME_MINUTES));
               double rthHVal = 0.0, rthLVal = 0.0, rthOpenVal = 0.0, ibHVal = 0.0, ibLVal = 0.0, gapFillVal = 0.0;
               string rthH    = GetRthHighSoFarAtBar(barIdx, dayStart, dateStr, rthHVal)    ? DoubleToString(rthHVal, _Digits) : "unknown";
               string rthL    = GetRthLowSoFarAtBar(barIdx, dayStart, dateStr, rthLVal)     ? DoubleToString(rthLVal, _Digits) : "unknown";
               string rthOpenStr = GetRTHopenForBar(barIdx, dayStart, dateStr, rthOpenVal) ? DoubleToString(rthOpenVal, _Digits) : "unknown";
               string ibH     = GetIBhighAtBar(barIdx, ibHVal)  ? DoubleToString(ibHVal, _Digits) : "unknown";
               string ibL     = GetIBlowAtBar(barIdx, ibLVal)   ? DoubleToString(ibLVal, _Digits) : "unknown";
               string gapFillStr = GetGapFillSoFarAtBar(barIdx, dayStart, dateStr, gapFillVal) ? DoubleToString(gapFillVal, 2) : "unknown";
               FileWrite(fileHandle, TimeToString(g_m1Rates[barIdx].time, TIME_DATE|TIME_MINUTES),
                     DoubleToString(g_m1Rates[barIdx].open, _Digits), DoubleToString(g_m1Rates[barIdx].high, _Digits), DoubleToString(g_m1Rates[barIdx].low, _Digits), DoubleToString(g_m1Rates[barIdx].close, _Digits),
                     DoubleToString(g_levelAboveH[barIdx], 0), DoubleToString(g_levelBelowL[barIdx], 0), g_session[barIdx],
                     DoubleToString(g_dayProgress[barIdx].dayWinRate * 100.0, 0), IntegerToString(g_dayProgress[barIdx].dayTradesCount), DoubleToString(g_dayProgress[barIdx].dayPointsSum, _Digits), DoubleToString(g_dayProgress[barIdx].dayProfitSum, 2),
                     DoubleToString(g_dayProgress[barIdx].ONwinRate * 100.0, 0), IntegerToString(g_dayProgress[barIdx].ONtradeCount), DoubleToString(g_dayProgress[barIdx].ONpointsSum, _Digits), DoubleToString(g_dayProgress[barIdx].ONprofitSum, 2),
                     DoubleToString(g_dayProgress[barIdx].RTHwinRate * 100.0, 0), IntegerToString(g_dayProgress[barIdx].RTHtradeCount), DoubleToString(g_dayProgress[barIdx].RTHpointsSum, _Digits), DoubleToString(g_dayProgress[barIdx].RTHprofitSum, 2),
                     DoubleToString(g_ONhighSoFarAtBar[barIdx].value, _Digits), DoubleToString(g_ONlowSoFarAtBar[barIdx].value, _Digits), rthH, rthL,
                     DoubleToString(g_dayHighSoFarAtBar[barIdx].value, _Digits), DoubleToString(g_dayLowSoFarAtBar[barIdx].value, _Digits),
                     (g_sessionRangeMidpointAtBar[barIdx].hasValue ? DoubleToString(g_sessionRangeMidpointAtBar[barIdx].value, 2) : "unknown"),
                     ibH, ibL,
                     gapFillStr,
                     rthOpenStr,
                     DoubleToString(g_staticMarketContext.PDOpreviousDayRTHOpen, _Digits), DoubleToString(g_staticMarketContext.PDHpreviousDayHigh, _Digits), DoubleToString(g_staticMarketContext.PDLpreviousDayLow, _Digits), DoubleToString(g_staticMarketContext.PDCpreviousDayRTHClose, _Digits), g_staticMarketContext.PDdate,
                     (g_dayBrokePDHAtBar[barIdx] ? "true" : "false"), (g_dayBrokePDLAtBar[barIdx] ? "true" : "false"));
            }
            FileClose(fileHandle);
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

         // Accumulate this day into all-days summary (once per day), then write summary_tradesSummary1line.csv with totals
         if(g_barsInDay > 0 && g_m1DayStart != 0 && g_m1DayStart != g_summaryTrades_lastAddedDayStart)
         {
            g_summaryTrades_dayTradesCount += g_dayProgress[kLast].dayTradesCount;
            g_summaryTrades_dayWins += (int)MathRound(g_dayProgress[kLast].dayWinRate * (double)g_dayProgress[kLast].dayTradesCount);
            g_summaryTrades_dayPointsSum += g_dayProgress[kLast].dayPointsSum;
            g_summaryTrades_dayProfitSum += g_dayProgress[kLast].dayProfitSum;
            g_summaryTrades_ONtradeCount += g_dayProgress[kLast].ONtradeCount;
            g_summaryTrades_ONwins += (int)MathRound(g_dayProgress[kLast].ONwinRate * (double)g_dayProgress[kLast].ONtradeCount);
            g_summaryTrades_ONpointsSum += g_dayProgress[kLast].ONpointsSum;
            g_summaryTrades_ONprofitSum += g_dayProgress[kLast].ONprofitSum;
            g_summaryTrades_RTHtradeCount += g_dayProgress[kLast].RTHtradeCount;
            g_summaryTrades_RTHwins += (int)MathRound(g_dayProgress[kLast].RTHwinRate * (double)g_dayProgress[kLast].RTHtradeCount);
            g_summaryTrades_RTHpointsSum += g_dayProgress[kLast].RTHpointsSum;
            g_summaryTrades_RTHprofitSum += g_dayProgress[kLast].RTHprofitSum;
            g_summaryTrades_lastAddedDayStart = g_m1DayStart;
            for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
            {
               TradeResult tradeResult = g_tradeResults[trIdx];
               if(!tradeResult.foundOut) continue;
               int idx = FindOrAddPerTradeMagic(tradeResult.magic);
               if(idx < 0) continue;
               if(StringFind(g_perTradeSummaries[idx].datesList, dateStr) < 0)
               {
                  if(StringLen(g_perTradeSummaries[idx].datesList) > 0)
                     g_perTradeSummaries[idx].datesList += ",";
                  g_perTradeSummaries[idx].datesList += dateStr;
               }
               g_perTradeSummaries[idx].dayTradesCount++;
               if(tradeResult.profit > 0) g_perTradeSummaries[idx].dayWins++;
               g_perTradeSummaries[idx].dayPointsSum += tradeResult.priceDiff;
               g_perTradeSummaries[idx].dayProfitSum += tradeResult.profit;
               string endSession = GetSessionForCandleTime(tradeResult.endTime);
               if(endSession == "ON")
               {
                  g_perTradeSummaries[idx].ONtradeCount++;
                  if(tradeResult.profit > 0) g_perTradeSummaries[idx].ONwins++;
                  g_perTradeSummaries[idx].ONpointsSum += tradeResult.priceDiff;
                  g_perTradeSummaries[idx].ONprofitSum += tradeResult.profit;
               }
               else if(endSession == "RTH")
               {
                  g_perTradeSummaries[idx].RTHtradeCount++;
                  if(tradeResult.profit > 0) g_perTradeSummaries[idx].RTHwins++;
                  g_perTradeSummaries[idx].RTHpointsSum += tradeResult.priceDiff;
                  g_perTradeSummaries[idx].RTHprofitSum += tradeResult.profit;
               }
            }
         }
         if(finalLog_SummaryTrades1line && g_barsInDay > 0)
         {
            int fileHandleEodAll = FileOpen("summary_tradesSummary1line.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
            if(fileHandleEodAll != INVALID_HANDLE)
            {
               double dayWr = (g_summaryTrades_dayTradesCount > 0) ? 100.0 * (double)g_summaryTrades_dayWins / (double)g_summaryTrades_dayTradesCount : 0.0;
               double onWr  = (g_summaryTrades_ONtradeCount > 0) ? 100.0 * (double)g_summaryTrades_ONwins / (double)g_summaryTrades_ONtradeCount : 0.0;
               double rthWr = (g_summaryTrades_RTHtradeCount > 0) ? 100.0 * (double)g_summaryTrades_RTHwins / (double)g_summaryTrades_RTHtradeCount : 0.0;
               FileWrite(fileHandleEodAll, "time", "dayWinRate", "dayTradesCount", "dayPointsSum", "dayProfitSum", "ONwinRate", "ONtradeCount", "ONpointsSum", "ONprofitSum", "RTHwinRate", "RTHtradeCount", "RTHpointsSum", "RTHprofitSum");
               FileWrite(fileHandleEodAll, TimeToString(g_m1Rates[kLast].time, TIME_DATE|TIME_MINUTES),
                  DoubleToString(dayWr, 0), IntegerToString(g_summaryTrades_dayTradesCount), DoubleToString(g_summaryTrades_dayPointsSum, _Digits), DoubleToString(g_summaryTrades_dayProfitSum, 2),
                  DoubleToString(onWr, 0), IntegerToString(g_summaryTrades_ONtradeCount), DoubleToString(g_summaryTrades_ONpointsSum, _Digits), DoubleToString(g_summaryTrades_ONprofitSum, 2),
                  DoubleToString(rthWr, 0), IntegerToString(g_summaryTrades_RTHtradeCount), DoubleToString(g_summaryTrades_RTHpointsSum, _Digits), DoubleToString(g_summaryTrades_RTHprofitSum, 2));
               FileClose(fileHandleEodAll);
            }
         }
         if(finalLog_SummaryTradesPerTrade && g_perTradeSummariesCount > 0)
         {
            int fileHandlePer = FileOpen("summary_tradesSummary_perTrade.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
            if(fileHandlePer != INVALID_HANDLE)
            {
               FileWrite(fileHandlePer, "time", "magicFirstDigit", "dates", "dayWinRate", "dayTradesCount", "dayPointsSum", "dayProfitSum", "ONwinRate", "ONtradeCount", "ONpointsSum", "ONprofitSum", "RTHwinRate", "RTHtradeCount", "RTHpointsSum", "RTHprofitSum");
               string rowTime = TimeToString(g_m1Rates[kLast].time, TIME_DATE|TIME_MINUTES);
               for(int summaryIdx = 0; summaryIdx < g_perTradeSummariesCount; summaryIdx++)
               {
                  PerTradeSummary perTradeSum = g_perTradeSummaries[summaryIdx];
                  double dayWr = (perTradeSum.dayTradesCount > 0) ? 100.0 * (double)perTradeSum.dayWins / (double)perTradeSum.dayTradesCount : 0.0;
                  double onWr  = (perTradeSum.ONtradeCount > 0) ? 100.0 * (double)perTradeSum.ONwins / (double)perTradeSum.ONtradeCount : 0.0;
                  double rthWr = (perTradeSum.RTHtradeCount > 0) ? 100.0 * (double)perTradeSum.RTHwins / (double)perTradeSum.RTHtradeCount : 0.0;
                  FileWrite(fileHandlePer, rowTime, IntegerToString((long)perTradeSum.magic), perTradeSum.datesList,
                     DoubleToString(dayWr, 0), IntegerToString(perTradeSum.dayTradesCount), DoubleToString(perTradeSum.dayPointsSum, _Digits), DoubleToString(perTradeSum.dayProfitSum, 2),
                     DoubleToString(onWr, 0), IntegerToString(perTradeSum.ONtradeCount), DoubleToString(perTradeSum.ONpointsSum, _Digits), DoubleToString(perTradeSum.ONprofitSum, 2),
                     DoubleToString(rthWr, 0), IntegerToString(perTradeSum.RTHtradeCount), DoubleToString(perTradeSum.RTHpointsSum, _Digits), DoubleToString(perTradeSum.RTHprofitSum, 2));
               }
               FileClose(fileHandlePer);
            }
         }

         // Trade results CSV: (date)_summaryZ_tradeResults_ALL_Day.csv (only once; if missing, write again). Skip when no trades.
         // Refresh trade results so OUT deals from CloseAnyOpenTrade_atEOD_2158() (same tick) are in history and paired.
         UpdateTradeResultsForDay();
         string csvName = dateStr + "_summaryZ_tradeResults_ALL_Day.csv";
         string summaryAllName = "summary_tradeResults_all_days.csv";
         bool needDailyTradeCsv = !FileIsExist(csvName);
         bool needAllDaysSummary = needDailyTradeCsv || !FileIsExist(summaryAllName);
         if(dailyEODlog_TradeResultsCsv && g_tradeResultsCount > 0 && needAllDaysSummary)
         {
            if(needDailyTradeCsv)
            {
            int fileHandleTr = FileOpen(csvName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_CSV | FILE_SHARE_READ | FILE_SHARE_WRITE);
            if(fileHandleTr == INVALID_HANDLE)
               FatalError("OnTimer: could not open " + csvName);
            {
               FileWrite(fileHandleTr, "symbol", "startTime", "endTime", "session", "magic", "priceBreakLevel_c1c2", "priceStart", "priceEnd", "priceDiff", "profit", "type", "reason", "volume", "bothComments", "level", "tp", "sl", "MFE", "MAE", "mfeCandle", "maeCandle", "MFEp", "MAEp", "MFE_c6", "MAE_c6", "MFE_c11", "MAE_c11", "MFE_c16", "MAE_c16", "SL4_c", "TP6c", "SL6c", "TP8c", "SL8c", "TP10c", "SL10c", "TP12c", "SL12c", "3c_30c_level_breakevenC", "gapFillPc_at_tradeOpenTime", "openGap_info", "PD_trend", "dayBrokePDH", "dayBrokePDL", "referencePointsAbove", "referencePointsBelow", "levelTag", "levelCats");
               for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
               {
                  TradeResult tradeResult = g_tradeResults[trIdx];
                  double mfe = 0.0, mae = 0.0;
                  int mfeCandle = 0, maeCandle = 0;
                  GetMFEandMAEForTrade(tradeResult, mfe, mae, mfeCandle, maeCandle);
                  double mfep = 0.0, maep = 0.0;
                  GetMFEpAndMAEpForTrade(tradeResult, mfe, mae, mfep, maep);
                  double mfe_c6 = 0.0, mae_c6 = 0.0, mfe_c11 = 0.0, mae_c11 = 0.0, mfe_c16 = 0.0, mae_c16 = 0.0;
                  GetMFEandMAE_cNForTrade(tradeResult, 6, mfe_c6, mae_c6);
                  GetMFEandMAE_cNForTrade(tradeResult, 11, mfe_c11, mae_c11);
                  GetMFEandMAE_cNForTrade(tradeResult, 16, mfe_c16, mae_c16);
                  string endTimeStr = tradeResult.foundOut ? TimeToString(tradeResult.endTime, TIME_DATE|TIME_SECONDS) : "NOT_FOUND";
                  string priceEndStr = tradeResult.foundOut ? DoubleToString(tradeResult.priceEnd, _Digits) : "NOT_FOUND";
                  string profitStr = tradeResult.foundOut ? DoubleToString(tradeResult.profit, 2) : "NOT_FOUND";
                  string reasonStr = tradeResult.foundOut ? EnumToString((ENUM_DEAL_REASON)tradeResult.reason) : "NOT_FOUND";
                  string typeStr = EnumToString((ENUM_DEAL_TYPE)tradeResult.type);
                  string mfeStr = (mfe != 0.0 || mae != 0.0) ? DoubleToString(mfe, _Digits) : "";
                  string maeStr = (mfe != 0.0 || mae != 0.0) ? DoubleToString(mae, _Digits) : "";
                  string mfeCandleStr = (mfeCandle > 0 || maeCandle > 0) ? IntegerToString(mfeCandle) : "";
                  string maeCandleStr = (mfeCandle > 0 || maeCandle > 0) ? IntegerToString(maeCandle) : "";
                  string mfepStr = (mfep != 0.0 || maep != 0.0) ? DoubleToString(mfep, 2) : "";
                  string maepStr = (mfep != 0.0 || maep != 0.0) ? DoubleToString(maep, 2) : "";
                  string mfe_c6Str = (mfe_c6 != 0.0 || mae_c6 != 0.0) ? DoubleToString(mfe_c6, 2) : "";
                  string mae_c6Str = (mfe_c6 != 0.0 || mae_c6 != 0.0) ? DoubleToString(mae_c6, 2) : "";
                  string mfe_c11Str = (mfe_c11 != 0.0 || mae_c11 != 0.0) ? DoubleToString(mfe_c11, 2) : "";
                  string mae_c11Str = (mfe_c11 != 0.0 || mae_c11 != 0.0) ? DoubleToString(mae_c11, 2) : "";
                  string mfe_c16Str = (mfe_c16 != 0.0 || mae_c16 != 0.0) ? DoubleToString(mfe_c16, 2) : "";
                  string mae_c16Str = (mfe_c16 != 0.0 || mae_c16 != 0.0) ? DoubleToString(mae_c16, 2) : "";
                  int sl4_c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 4, false), false);
                  int tp6c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 6, true), true);
                  int sl6c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 6, false), false);
                  int tp8c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 8, true), true);
                  int sl8c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 8, false), false);
                  int tp10c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 10, true), true);
                  int sl10c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 10, false), false);
                  int tp12c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 12, true), true);
                  int sl12c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 12, false), false);
                  string sl4_cStr = (sl4_c > 0) ? IntegerToString(sl4_c) : "";
                  string tp6cStr = (tp6c > 0) ? IntegerToString(tp6c) : "";
                  string sl6cStr = (sl6c > 0) ? IntegerToString(sl6c) : "";
                  string tp8cStr = (tp8c > 0) ? IntegerToString(tp8c) : "";
                  string sl8cStr = (sl8c > 0) ? IntegerToString(sl8c) : "";
                  string tp10cStr = (tp10c > 0) ? IntegerToString(tp10c) : "";
                  string sl10cStr = (sl10c > 0) ? IntegerToString(sl10c) : "";
                  string tp12cStr = (tp12c > 0) ? IntegerToString(tp12c) : "";
                  string sl12cStr = (sl12c > 0) ? IntegerToString(sl12c) : "";
                  int breakevenC = Get3c30cLevelBreakevenCForTrade(tradeResult);
                  string breakevenCStr = (breakevenC >= 3) ? IntegerToString(breakevenC) : "";
                  string gapFillPcStr = GetGapFillPcAtTradeOpenTime(tradeResult.startTime);
                  string isGapDownDayStr = GetIsGapDownDayString(tradeResult.startTime);
                  string pdTrendStr = GetPDtrendString();
                  string dayBrokePDHStr = GetDayBrokePDHAtTradeOpenTime(tradeResult.startTime);
                  string dayBrokePDLStr = GetDayBrokePDLAtTradeOpenTime(tradeResult.startTime);
                  string refAbove = "", refBelow = "";
                  GetReferencePointsAboveBelow(tradeResult.startTime, tradeResult.priceStart, refAbove, refBelow);
                  string levelTagStr = "", levelCatsStr = "";
                  GetLevelTagAndCatsForTrade(tradeResult.level, levelTagStr, levelCatsStr);
                  string priceBreakLevel_c1c2_Str = GetPriceBreakLevel_c1c2_ForTrade(tradeResult);
                  FileWrite(fileHandleTr, tradeResult.symbol, TimeToString(tradeResult.startTime, TIME_DATE|TIME_SECONDS), endTimeStr,
                     tradeResult.session, IntegerToString((long)tradeResult.magic), priceBreakLevel_c1c2_Str, DoubleToString(tradeResult.priceStart, _Digits), priceEndStr,
                     DoubleToString(tradeResult.priceDiff, _Digits), profitStr, typeStr, reasonStr,
                     DoubleToString(tradeResult.volume, 2), tradeResult.bothComments, tradeResult.level, tradeResult.tp, tradeResult.sl, mfeStr, maeStr, mfeCandleStr, maeCandleStr, mfepStr, maepStr, mfe_c6Str, mae_c6Str, mfe_c11Str, mae_c11Str, mfe_c16Str, mae_c16Str,
                     sl4_cStr, tp6cStr, sl6cStr, tp8cStr, sl8cStr, tp10cStr, sl10cStr, tp12cStr, sl12cStr, breakevenCStr,
                     gapFillPcStr, isGapDownDayStr, pdTrendStr, dayBrokePDHStr, dayBrokePDLStr, refAbove, refBelow, levelTagStr, levelCatsStr);
               }
               FileClose(fileHandleTr);
            }
            }

            // All-days summary: read existing file (guaranteed correct schema), merge new day in memory, write whole file.
            // NEVER try to support old files from before schema changes. We always start clean. Don't care about backward compat.
            const string TRADERESULTS_ALLDAYS_HEADER = "date,symbol,startTime,endTime,session,magic,priceBreakLevel_c1c2,priceStart,priceEnd,priceDiff,profit,type,reason,volume,bothComments,level,tp,sl,MFE,MAE,mfeCandle,maeCandle,MFEp,MAEp,MFE_c6,MAE_c6,MFE_c11,MAE_c11,MFE_c16,MAE_c16,SL4_c,TP6c,SL6c,TP8c,SL8c,TP10c,SL10c,TP12c,SL12c,3c_30c_level_breakevenC,gapFillPc_at_tradeOpenTime,openGap_info,PD_trend,dayBrokePDH,dayBrokePDL,referencePointsAbove,referencePointsBelow,levelTag,levelCats";
            string headerParts[];
            int schemaCols = StringSplit(TRADERESULTS_ALLDAYS_HEADER, ',', headerParts);
            string allDaysRows[];
            int existingRowCount = 0;
            int fileCols = 0;
            int fileHandleRead = FileOpen(summaryAllName, FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
            if(fileHandleRead != INVALID_HANDLE)
            {
               // Skip header (schemaCols fields)
               for(int h = 0; h < schemaCols && !FileIsEnding(fileHandleRead); h++)
                  FileReadString(fileHandleRead);
               // Read data rows (schemaCols per row; file always has our schema)
               while(!FileIsEnding(fileHandleRead))
               {
                  int base = ArraySize(allDaysRows);
                  ArrayResize(allDaysRows, base + schemaCols);
                  int c = 0;
                  for(; c < schemaCols && !FileIsEnding(fileHandleRead); c++)
                     allDaysRows[base + c] = FileReadString(fileHandleRead);
                  for(; c < schemaCols; c++)
                     allDaysRows[base + c] = "";
                  existingRowCount++;
               }
               FileClose(fileHandleRead);
            }
            int orderTr[];
            ArrayResize(orderTr, g_tradeResultsCount);
            for(int o = 0; o < g_tradeResultsCount; o++) orderTr[o] = o;
            SortIndicesByTradeStartAsc(orderTr);
            int cols = (fileCols > 0) ? fileCols : schemaCols;
            int newBase = existingRowCount * cols;
            ArrayResize(allDaysRows, newBase + g_tradeResultsCount * schemaCols);
            for(int ti = 0; ti < g_tradeResultsCount; ti++)
            {
               int trIdx = orderTr[ti];
               TradeResult tradeResult = g_tradeResults[trIdx];
               double mfe = 0.0, mae = 0.0;
               int mfeCandle = 0, maeCandle = 0;
               GetMFEandMAEForTrade(tradeResult, mfe, mae, mfeCandle, maeCandle);
               double mfep = 0.0, maep = 0.0;
               GetMFEpAndMAEpForTrade(tradeResult, mfe, mae, mfep, maep);
               double mfe_c6 = 0.0, mae_c6 = 0.0, mfe_c11 = 0.0, mae_c11 = 0.0, mfe_c16 = 0.0, mae_c16 = 0.0;
               GetMFEandMAE_cNForTrade(tradeResult, 6, mfe_c6, mae_c6);
               GetMFEandMAE_cNForTrade(tradeResult, 11, mfe_c11, mae_c11);
               GetMFEandMAE_cNForTrade(tradeResult, 16, mfe_c16, mae_c16);
               string endTimeStr = tradeResult.foundOut ? TimeToString(tradeResult.endTime, TIME_DATE|TIME_SECONDS) : "NOT_FOUND";
               string priceEndStr = tradeResult.foundOut ? DoubleToString(tradeResult.priceEnd, _Digits) : "NOT_FOUND";
               string profitStr = tradeResult.foundOut ? DoubleToString(tradeResult.profit, 2) : "NOT_FOUND";
               string reasonStr = tradeResult.foundOut ? EnumToString((ENUM_DEAL_REASON)tradeResult.reason) : "NOT_FOUND";
               string typeStr = EnumToString((ENUM_DEAL_TYPE)tradeResult.type);
               string mfeStr = (mfe != 0.0 || mae != 0.0) ? DoubleToString(mfe, _Digits) : "";
               string maeStr = (mfe != 0.0 || mae != 0.0) ? DoubleToString(mae, _Digits) : "";
               string mfeCandleStr = (mfeCandle > 0 || maeCandle > 0) ? IntegerToString(mfeCandle) : "";
               string maeCandleStr = (mfeCandle > 0 || maeCandle > 0) ? IntegerToString(maeCandle) : "";
               string mfepStr = (mfep != 0.0 || maep != 0.0) ? DoubleToString(mfep, 2) : "";
               string maepStr = (mfep != 0.0 || maep != 0.0) ? DoubleToString(maep, 2) : "";
               string mfe_c6Str = (mfe_c6 != 0.0 || mae_c6 != 0.0) ? DoubleToString(mfe_c6, 2) : "";
               string mae_c6Str = (mfe_c6 != 0.0 || mae_c6 != 0.0) ? DoubleToString(mae_c6, 2) : "";
               string mfe_c11Str = (mfe_c11 != 0.0 || mae_c11 != 0.0) ? DoubleToString(mfe_c11, 2) : "";
               string mae_c11Str = (mfe_c11 != 0.0 || mae_c11 != 0.0) ? DoubleToString(mae_c11, 2) : "";
               string mfe_c16Str = (mfe_c16 != 0.0 || mae_c16 != 0.0) ? DoubleToString(mfe_c16, 2) : "";
               string mae_c16Str = (mfe_c16 != 0.0 || mae_c16 != 0.0) ? DoubleToString(mae_c16, 2) : "";
               int sl4_c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 4, false), false);
               int tp6c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 6, true), true);
               int sl6c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 6, false), false);
               int tp8c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 8, true), true);
               int sl8c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 8, false), false);
               int tp10c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 10, true), true);
               int sl10c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 10, false), false);
               int tp12c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 12, true), true);
               int sl12c = GetCandleWhereLevelReached(tradeResult, GetLevelPriceForTPorSL(tradeResult, 12, false), false);
               string sl4_cStr = (sl4_c > 0) ? IntegerToString(sl4_c) : "";
               string tp6cStr = (tp6c > 0) ? IntegerToString(tp6c) : "";
               string sl6cStr = (sl6c > 0) ? IntegerToString(sl6c) : "";
               string tp8cStr = (tp8c > 0) ? IntegerToString(tp8c) : "";
               string sl8cStr = (sl8c > 0) ? IntegerToString(sl8c) : "";
               string tp10cStr = (tp10c > 0) ? IntegerToString(tp10c) : "";
               string sl10cStr = (sl10c > 0) ? IntegerToString(sl10c) : "";
               string tp12cStr = (tp12c > 0) ? IntegerToString(tp12c) : "";
               string sl12cStr = (sl12c > 0) ? IntegerToString(sl12c) : "";
               int breakevenC = Get3c30cLevelBreakevenCForTrade(tradeResult);
               string breakevenCStr = (breakevenC >= 3) ? IntegerToString(breakevenC) : "";
               string gapFillPcStr = GetGapFillPcAtTradeOpenTime(tradeResult.startTime);
               string isGapDownDayStr = GetIsGapDownDayString(tradeResult.startTime);
               string pdTrendStr = GetPDtrendString();
               string dayBrokePDHStr = GetDayBrokePDHAtTradeOpenTime(tradeResult.startTime);
               string dayBrokePDLStr = GetDayBrokePDLAtTradeOpenTime(tradeResult.startTime);
               string refAbove = "", refBelow = "";
               GetReferencePointsAboveBelow(tradeResult.startTime, tradeResult.priceStart, refAbove, refBelow);
               string levelTagStr = "", levelCatsStr = "";
               GetLevelTagAndCatsForTrade(tradeResult.level, levelTagStr, levelCatsStr);
               string priceBreakLevel_c1c2_StrAll = GetPriceBreakLevel_c1c2_ForTrade(tradeResult);
               int r = newBase + ti * schemaCols;
               allDaysRows[r++] = dateStr;
               allDaysRows[r++] = tradeResult.symbol;
               allDaysRows[r++] = TimeToString(tradeResult.startTime, TIME_DATE|TIME_SECONDS);
               allDaysRows[r++] = endTimeStr;
               allDaysRows[r++] = tradeResult.session;
               allDaysRows[r++] = IntegerToString((long)tradeResult.magic);
               allDaysRows[r++] = priceBreakLevel_c1c2_StrAll;
               allDaysRows[r++] = DoubleToString(tradeResult.priceStart, _Digits);
               allDaysRows[r++] = priceEndStr;
               allDaysRows[r++] = DoubleToString(tradeResult.priceDiff, _Digits);
               allDaysRows[r++] = profitStr;
               allDaysRows[r++] = typeStr;
               allDaysRows[r++] = reasonStr;
               allDaysRows[r++] = DoubleToString(tradeResult.volume, 2);
               allDaysRows[r++] = tradeResult.bothComments;
               allDaysRows[r++] = tradeResult.level;
               allDaysRows[r++] = tradeResult.tp;
               allDaysRows[r++] = tradeResult.sl;
               allDaysRows[r++] = mfeStr;
               allDaysRows[r++] = maeStr;
               allDaysRows[r++] = mfeCandleStr;
               allDaysRows[r++] = maeCandleStr;
               allDaysRows[r++] = mfepStr;
               allDaysRows[r++] = maepStr;
               allDaysRows[r++] = mfe_c6Str;
               allDaysRows[r++] = mae_c6Str;
               allDaysRows[r++] = mfe_c11Str;
               allDaysRows[r++] = mae_c11Str;
               allDaysRows[r++] = mfe_c16Str;
               allDaysRows[r++] = mae_c16Str;
               allDaysRows[r++] = sl4_cStr;
               allDaysRows[r++] = tp6cStr;
               allDaysRows[r++] = sl6cStr;
               allDaysRows[r++] = tp8cStr;
               allDaysRows[r++] = sl8cStr;
               allDaysRows[r++] = tp10cStr;
               allDaysRows[r++] = sl10cStr;
               allDaysRows[r++] = tp12cStr;
               allDaysRows[r++] = sl12cStr;
               allDaysRows[r++] = breakevenCStr;
               allDaysRows[r++] = gapFillPcStr;
               allDaysRows[r++] = isGapDownDayStr;
               allDaysRows[r++] = pdTrendStr;
               allDaysRows[r++] = dayBrokePDHStr;
               allDaysRows[r++] = dayBrokePDLStr;
               allDaysRows[r++] = refAbove;
               allDaysRows[r++] = refBelow;
               allDaysRows[r++] = levelTagStr;
               allDaysRows[r++] = levelCatsStr;
            }
            int fileHandleSumTr = FileOpen(summaryAllName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
            if(fileHandleSumTr != INVALID_HANDLE)
            {
               FileWrite(fileHandleSumTr, "date", "symbol", "startTime", "endTime", "session", "magic", "priceBreakLevel_c1c2", "priceStart", "priceEnd", "priceDiff", "profit", "type", "reason", "volume", "bothComments", "level", "tp", "sl", "MFE", "MAE", "mfeCandle", "maeCandle", "MFEp", "MAEp", "MFE_c6", "MAE_c6", "MFE_c11", "MAE_c11", "MFE_c16", "MAE_c16", "SL4_c", "TP6c", "SL6c", "TP8c", "SL8c", "TP10c", "SL10c", "TP12c", "SL12c", "3c_30c_level_breakevenC", "gapFillPc_at_tradeOpenTime", "openGap_info", "PD_trend", "dayBrokePDH", "dayBrokePDL", "referencePointsAbove", "referencePointsBelow", "levelTag", "levelCats");
               int totalRows = existingRowCount + g_tradeResultsCount;
               for(int ri = 0; ri < totalRows; ri++)
               {
                  int rowBase = (ri < existingRowCount) ? (ri * cols) : (newBase + (ri - existingRowCount) * schemaCols);
                  FileWrite(fileHandleSumTr, allDaysRows[rowBase], allDaysRows[rowBase+1], allDaysRows[rowBase+2], allDaysRows[rowBase+3], allDaysRows[rowBase+4], allDaysRows[rowBase+5], allDaysRows[rowBase+6], allDaysRows[rowBase+7], allDaysRows[rowBase+8], allDaysRows[rowBase+9], allDaysRows[rowBase+10], allDaysRows[rowBase+11], allDaysRows[rowBase+12], allDaysRows[rowBase+13], allDaysRows[rowBase+14], allDaysRows[rowBase+15], allDaysRows[rowBase+16], allDaysRows[rowBase+17], allDaysRows[rowBase+18], allDaysRows[rowBase+19], allDaysRows[rowBase+20], allDaysRows[rowBase+21], allDaysRows[rowBase+22], allDaysRows[rowBase+23], allDaysRows[rowBase+24], allDaysRows[rowBase+25], allDaysRows[rowBase+26], allDaysRows[rowBase+27], allDaysRows[rowBase+28], allDaysRows[rowBase+29], allDaysRows[rowBase+30], allDaysRows[rowBase+31], allDaysRows[rowBase+32], allDaysRows[rowBase+33], allDaysRows[rowBase+34], allDaysRows[rowBase+35], allDaysRows[rowBase+36], allDaysRows[rowBase+37], allDaysRows[rowBase+38], allDaysRows[rowBase+39], allDaysRows[rowBase+40], allDaysRows[rowBase+41], allDaysRows[rowBase+42], allDaysRows[rowBase+43], allDaysRows[rowBase+44], allDaysRows[rowBase+45], allDaysRows[rowBase+46], allDaysRows[rowBase+47], allDaysRows[rowBase+48]);
               }
               FileClose(fileHandleSumTr);
            }
         }

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
               FileWrite(fileHandleAra, "time", "level", "O", "H", "low", "C", "diff_CloseToLevel", "DayBias", "Contact", "ContactCount", "BounceCount", "CandlesPassedSinceLastBounce", "CandlesBreakLevelCount", "RecoverCount");
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

         // --- Track bounce
         if(levels[i].lastCandleInContact && !in_contact)
         {
            levels[i].bounceCount++;
            levels[i].candlesPassedSinceLastBounce = 0; // reset when bounce occurs
         }
         else if(levels[i].bounceCount > 0)
         {
            levels[i].candlesPassedSinceLastBounce++; // increment when bounceCount > 0 but no new bounce
         }
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