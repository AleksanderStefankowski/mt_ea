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


#property copyright "Copyright 2026, Aleksander Stefankowski"

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>

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
bool     dailyEODlog_EodTradesSummary = true;  // (date)_summary_EOD_tradesSummary1line.csv
bool     finalLog_SummaryTrades1line  = true;  // summary_tradesSummary1line.csv
bool     finalLog_SummaryTradesPerTrade = true;  // summary_tradesSummary_perTrade.csv (one row per magic)
bool     dailyEODlog_TradeResultsCsv  = true;  // summaryZ_tradeResults_ALL_Day + summary_tradeResults_all_days
bool     dailyEODlog_TestinglevelsPlus = true;  // (date)_testinglevelsplus_(level)_(tag).csv per level
bool     dailyEODlog_BreakCheck       = true;  // levels_breakCheck files + summary
bool     dailySpamLog_LivePrice       = true;  // (date)_testing_liveprice.csv 21:35-21:37
bool     dailyEODlog_DayStat          = true;  // (date)_dayPriceStat_log.csv (TryLogDayStatForCurrentDay)
bool     finalLog_DayStatSummary      = true;  // dayPriceStat_summaryLog.csv (WriteDayStatSummaryCsv)
bool     finalLog_TradeLog            = true;  // B_TradeLog_(id).csv (WriteTradeLog)
bool     dailySpamLog_AllCandles      = true;  // (date)-AllCandlesLog_Timer1.csv
bool     finalLog_FirstLastCandle     = true;  // InpSessionFirstLastCandleFile (OnDeinit)
bool     dailySpamLog_Arawevents      = true;  // Arawevents CSV + level logRawEv (FinalizeCurrentCandle)
string   InpCalendarFile        = "calendar_2026_dots.csv";  // CSV in Terminal/Common/Files: date (YYYY.MM.DD),dayofmonth,dayofweek,opex,qopex
string   InpLevelsFile          = "levelsinfo_zeFinal.csv";  // CSV in Terminal/Common/Files: start,end,levelPrice,categories,tag
double   InpBreakCheckMaxDistPoints = 9.0;  // levels_breakCheck: first candle beyond this distance in price (and all newer) excluded
bool     maemfe_testing             = false; // if true: all trades use TP=SL=3000.0 and close any position open >20 min (OnTimer)
bool     ontimer_babysit = true;

//--- Global base trade size: actual lot = base × (trade_size_percentage/100). Each ruleset has its own percentage (10,20,...,100).
double   g_global_base_trade_size = 0.1;  // base lot; 100% trade type = this full size; 50% = half

//--- Ruleset 121 (OnTimer: closest non-tertiary level below bid; g_cleanStreakAbove >= InpRuleset121_CleanStreakAboveMin; diff below >= 10 in 100 bars; diff above >= 12 in streak bars)
bool     InpRuleset121_Enable = true;
int      InpRuleset121_CleanStreakAboveMin = 20;   // min consecutive bars with OHLC above level (g_cleanStreakAbove)
int      InpRuleset121_TradeSizePct = 100;
double   InpRuleset121_PriceOffsetPips  = 2.6;   // order price = level + (this×10) points via InputPipsToOrderPips
double   InpRuleset121_TPPips = 12.0;
double   InpRuleset121_SLPips = 12.0;
string   InpRuleset121_BannedRanges = "22,0,23,59;0,0,1,0";

//--- Ruleset 122 (same entry logic as 121; separate inputs and magic)
bool     InpRuleset122_Enable = false;
int      InpRuleset122_CleanStreakAboveMin = 20;   // min consecutive bars with OHLC above level (g_cleanStreakAbove)
int      InpRuleset122_TradeSizePct = 100;
double   InpRuleset122_PriceOffsetPips  = 2.6;
double   InpRuleset122_TPPips = 8.0;
double   InpRuleset122_SLPips = 8.0;
string   InpRuleset122_BannedRanges = "22,0,23,59;0,0,1,0";


//--- Ruleset config: useLevel/usePrice indicate what each ruleset cares about; bannedRangesStr always applied when non-empty.
struct TradeTypeConfig
{
   bool   useLevel;        // false = ruleset does not use level
   bool   usePrice;        // false = no price/level distance check
   string bannedRangesStr; // "startH,startM,endH,endM;..." e.g. "0,0,2,59;20,0,23,59"; empty = no time filter
};
TradeTypeConfig g_tradeConfig[128];  // index by ruleset id; see EA_KNOWN_RULESET_IDS
const int MAX_BANNED_RANGES = 10;
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
};
Level levels[];

//--- Ruleset support (magic, logging)
const long EA_MAGIC = 47001; // unique magic for this EA's orders

// List of all known EA trade (ruleset) IDs that can open positions. Used e.g. by CloseAnyEAPositionThatIsXMinutesOld.
const int EA_KNOWN_RULESET_IDS[] = { 121, 122 };
#define EA_KNOWN_RULESET_COUNT 2

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
#define MAX_LEVELS_EXPANDED 500
#define MAX_BARS_IN_DAY 1500
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

#define MAX_PER_TRADE_MAGICS 128
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

// Returns index in g_perTradeSummaries for key (first digit of magic); adds new entry if not found (or -1 if table full).
int FindOrAddPerTradeMagic(long keyFirstDigit)
{
   for(int summaryIdx = 0; summaryIdx < g_perTradeSummariesCount; summaryIdx++)
      if(g_perTradeSummaries[summaryIdx].magic == keyFirstDigit)
         return summaryIdx;
   if(g_perTradeSummariesCount >= MAX_PER_TRADE_MAGICS)
      return -1;
   int newIdx = g_perTradeSummariesCount++;
   g_perTradeSummaries[newIdx].magic = keyFirstDigit;
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

// Key for per-ruleset summary grouping. Returns ruleset id (see EA_KNOWN_RULESET_IDS) so each gets its own row.
long GetRulesetKeyFromMagic(long magic)
{
   return (long)GetRulesetIdFromMagic(magic);
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
//--- Day broke PDH/PDL so far at each bar: true if dayHighSoFar>PDH / dayLowSoFar<PDL (false when PDH/PDL unavailable).
bool g_dayBrokePDHAtBar[MAX_BARS_IN_DAY];
bool g_dayBrokePDLAtBar[MAX_BARS_IN_DAY];
//--- IB (first hour of RTH) high/low: unknown before IB ends; after 16:30 (normal) or 15:30 (desync) = max/min of IB bars. Filled every OnTimer.
OptionalDouble g_IBhighAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_IBlowAtBar[MAX_BARS_IN_DAY];
//--- Gap fill so far: unknown before RTH open; after = 0–100 % based on rthLowSoFar (gap up) or rthHighSoFar (gap down). Filled every OnTimer.
OptionalDouble g_gapFillSoFarAtBar[MAX_BARS_IN_DAY];
//--- Trade results for the day
#define MAX_TRADE_RESULTS 500
#define MAX_DEALS_DAY 2000
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
int g_dealOrder[MAX_DEALS_DAY];  // sorted indices
#define MAX_IN_OUT_PER_MAGIC 200
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
   int fileHandle = FileOpen(InpCalendarFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
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
//| TP/SL level price for "N" in input pips format (same as order TP/SL: InputPipsToOrderPips(N)*PipSize()). BUY TP = priceStart+dist, SL = priceStart-dist; SELL opposite. |
//+------------------------------------------------------------------+
double GetLevelPriceForTPorSL(const TradeResult &tradeResult, int N, bool isTP)
{
   double dist = InputPipsToOrderPips((double)N) * PipSize();
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
//| Contact proximity: candle containing trade start (e.g. 14:31) + 1 candle after (e.g. 14:32). BUY: level - low (min over 2 candles). SELL: level - high (max over 2 candles). Returns "NOT_FOUND" if no level or bars missing. |
//+------------------------------------------------------------------+
string GetContactProximityForTrade(const TradeResult &tradeResult)
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
//| Find the RTH open candle of current day in g_m1Rates (14:30 on desync dates, else 15:30). FatalError if not found. Returns its open price. |
//+------------------------------------------------------------------+
double GetRTHopenCurrentDay()
{
   if(g_barsInDay <= 0 || g_m1DayStart == 0)
      FatalError("GetRTHopenCurrentDay: no day data (g_barsInDay=" + IntegerToString(g_barsInDay) + " g_m1DayStart=0)");
   string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   datetime targetTime;
   if(bool_RTHsession_Is_DaylightSavingsDesync(dateStr))
      targetTime = g_m1DayStart + 14*3600 + 30*60;   // 14:30 bar
   else
      targetTime = g_m1DayStart + 15*3600 + 30*60;   // 15:30 bar
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
      if(g_m1Rates[barIdx].time == targetTime)
         return g_m1Rates[barIdx].open;
   FatalError("GetRTHopenCurrentDay: RTH open candle not found for " + TimeToString(g_m1DayStart, TIME_DATE));
   return 0.0;  // unreachable
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
   if(g_dayHighSoFarAtBar[barIdx].hasValue && g_dayLowSoFarAtBar[barIdx].hasValue) { v = (g_dayHighSoFarAtBar[barIdx].value + g_dayLowSoFarAtBar[barIdx].value) / 2.0; if(v > tradePrice) outAbove += (outAbove != "" ? ";" : "") + "midpoint"; else if(v < tradePrice) outBelow += (outBelow != "" ? ";" : "") + "midpoint"; }
}

//+------------------------------------------------------------------+
//| Find today's RTH open bar in g_m1Rates (14:30 on desync dates, else 15:30) and assign g_todayRTHopen, g_todayRTHopenValid. |
//+------------------------------------------------------------------+
void AssignTodayRTHopenFromM1Rates(const string &dateStr)
{
   g_todayRTHopenValid = false;
   if(g_barsInDay <= 0) return;
   bool useDesync = bool_RTHsession_Is_DaylightSavingsDesync(dateStr);
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      MqlDateTime mqlTime;
      TimeToStruct(g_m1Rates[barIdx].time, mqlTime);
      if(useDesync && mqlTime.hour == 14 && mqlTime.min == 30)
         { g_todayRTHopen = g_m1Rates[barIdx].open; g_todayRTHopenValid = true; return; }
      if(!useDesync && mqlTime.hour == 15 && mqlTime.min == 30)
         { g_todayRTHopen = g_m1Rates[barIdx].open; g_todayRTHopenValid = true; return; }
   }
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
   int fileHandle = FileOpen(InpLevelsFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
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
string GetHighestDiffFromLevelInWindowString(double levelPrice, int barK, int windowBars, bool wantUp)
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

   // Ensure todayRTHopen is in g_levels when we have the RTH open bar (14:30 on desync dates, else 15:30). Use globals as single source for level and pullinghistory.
   AssignTodayRTHopenFromM1Rates(dateStr);
   TryAddTodayRTHopenLevel(dateStr);

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
//| If bothComments contains "$", remove "$", split by " "; fill result[], return count. Else return 0. |
//+------------------------------------------------------------------+
int ChangeBothCommentsToArrayOfStrings(const string &bothComments, string &result[])
{
   if(StringFind(bothComments, "$") < 0) return 0;
   string commentStr = bothComments;
   StringReplace(commentStr, "$", "");
   return StringSplit(commentStr, ' ', result);
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
   // Sort indices by magic then time
   for(int dealIdx = 0; dealIdx < g_dealCount; dealIdx++) g_dealOrder[dealIdx] = dealIdx;
   for(int dealIdx = 0; dealIdx < g_dealCount - 1; dealIdx++)
      for(int innerIdx = dealIdx + 1; innerIdx < g_dealCount; innerIdx++)
      {
         int orderA = g_dealOrder[dealIdx], orderB = g_dealOrder[innerIdx];
         if(g_dealMagic[orderA] > g_dealMagic[orderB] || (g_dealMagic[orderA] == g_dealMagic[orderB] && g_dealTime[orderA] > g_dealTime[orderB]))
         { int tmp = g_dealOrder[dealIdx]; g_dealOrder[dealIdx] = g_dealOrder[innerIdx]; g_dealOrder[innerIdx] = tmp; }
      }
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
            if(StringFind(commentsStr, "$") < 0)
               tradeResult.level = tradeResult.tp = tradeResult.sl = "";
            else
            {
               string arr[];
               ChangeBothCommentsToArrayOfStrings(commentsStr, arr);
               tradeResult.level = (ArraySize(arr) > 0) ? arr[0] : "";
               tradeResult.tp    = (ArraySize(arr) > 1) ? arr[1] : "";
               tradeResult.sl    = (ArraySize(arr) > 2) ? arr[2] : "";
            }
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
            if(StringFind(commentsStr, "$") < 0)
               tradeResult.level = tradeResult.tp = tradeResult.sl = "";
            else
            {
               string arr[];
               ChangeBothCommentsToArrayOfStrings(commentsStr, arr);
               tradeResult.level = (ArraySize(arr) > 0) ? arr[0] : "";
               tradeResult.tp    = (ArraySize(arr) > 1) ? arr[1] : "";
               tradeResult.sl    = (ArraySize(arr) > 2) ? arr[2] : "";
            }
         }
         g_tradeResults[g_tradeResultsCount++] = tradeResult;
      }
   }
}

//+------------------------------------------------------------------+
//| For each bar k, set g_dayProgress[k] from trades with endTime < candle k close time (so close at 16:45:00 counts for 16:45 bar, not 16:44). |
//+------------------------------------------------------------------+
void UpdateDayProgress()
{
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      datetime candleCloseTime;
      if(barIdx + 1 < g_barsInDay) candleCloseTime = g_m1Rates[barIdx + 1].time;
      else candleCloseTime = g_m1Rates[barIdx].time + 60;
      int wins = 0, total = 0;
      double dayPointsSum = 0, dayProfitSum = 0;
      int ONwins = 0, ONtotal = 0;
      double ONpointsSum = 0, ONprofitSum = 0;
      int RTHwins = 0, RTHtotal = 0;
      double RTHpointsSum = 0, RTHprofitSum = 0;
      for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
      {
         TradeResult tradeResult = g_tradeResults[trIdx];
         if(!tradeResult.foundOut) continue;
         if(tradeResult.endTime >= candleCloseTime) continue;
         total++;
         if(tradeResult.profit > 0) wins++;
         dayPointsSum += tradeResult.priceDiff;
         dayProfitSum += tradeResult.profit;
         string endSession = GetSessionForCandleTime(tradeResult.endTime);
         if(endSession == "ON")
         {
            ONtotal++;
            if(tradeResult.profit > 0) ONwins++;
            ONpointsSum += tradeResult.priceDiff;
            ONprofitSum += tradeResult.profit;
         }
         else if(endSession == "RTH")
         {
            RTHtotal++;
            if(tradeResult.profit > 0) RTHwins++;
            RTHpointsSum += tradeResult.priceDiff;
            RTHprofitSum += tradeResult.profit;
         }
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
//| Fill g_ONhighSoFarAtBar, g_ONlowSoFarAtBar, g_rthHighSoFarAtBar, g_rthLowSoFarAtBar, g_dayHighSoFarAtBar, g_dayLowSoFarAtBar for bars 0..g_barsInDay-1. |
//| For each bar k: ON high/low = running max/min of ON bars up to k; RTH same; day high/low = running max/min of all bars up to k. Before first ON/RTH bar, hasValue false. |
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
      for(int barIdx = 0; barIdx < barCount; barIdx++)
      {
         datetime candleCloseTime;
         if(barIdx + 1 < barCount) candleCloseTime = g_levelsExpanded[levelIdx].times[barIdx + 1];
         else candleCloseTime = g_levelsExpanded[levelIdx].times[barIdx] + 60;
         if(tradeResult.endTime >= candleCloseTime) continue;
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
//| Day-of-week suffix for magic: 0 when level has no "daily" in tags; 0..6 (Mon..Sun) when "daily". |
//| Pass to BuildMagic; use -1 for rulesets (no suffix).               |
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
//| Build magic number: trade (ruleset) id only.                      |
//| FUTURE: slot encoding [1][01][TT][00]...[00]: slot1=1, slot2=01 (script ver), slot3=trade type (05,06,07), slots4-9=00. long can hold 19 digits. |
//+------------------------------------------------------------------+
long BuildMagic(int id)
{
   return (long)id;
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
double GetClosestNonTertiaryLevelBelowPrice(double price)
{
   return GetClosestNonTertiaryLevelToPrice(price, false);
}

//+------------------------------------------------------------------+
//| Closest non-tertiary level above price. Wrapper for GetClosestNonTertiaryLevelToPrice(price, true). |
//+------------------------------------------------------------------+
double GetClosestNonTertiaryLevelAbovePrice(double price)
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
//| True if g_liveBid is within maxDistPoints of levelPrice (points, not pips). |
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
//| True if categories string contains "tertiary" (e.g. daily_tertiary_todayRTHopen). |
//+------------------------------------------------------------------+
bool LevelIsTertiary(const string &categories)
{
   return (StringFind(categories, "tertiary") >= 0);
}

//+------------------------------------------------------------------+
//| Unified order comment: $ (int)levelPrice takeProfitVal stopLossVal orderPrice commentRulesetId. Used by buy-limit rulesets. |
//+------------------------------------------------------------------+
string BuildUnifiedOrderComment(int levelPriceInt, double takeProfitVal, double stopLossVal, double orderPrice, int commentRulesetId)
{
   return StringFormat("$%d %.*f %.*f %.*f %d", levelPriceInt, _Digits, takeProfitVal, _Digits, stopLossVal, _Digits, orderPrice, commentRulesetId);
}

//+------------------------------------------------------------------+
//| After PlaceBuyLimitAtLevel returned true: log pending_created to B_TradeLog using ResultOrder() and unified comment (level, takeProfitVal, stopLossVal, orderPrice, commentRulesetId). |
//+------------------------------------------------------------------+
void WriteTradeLogPendingOrder(int commentRulesetId, double levelPrice, double offsetPips, double slPips, double tpPips, long magic)
{
   string rulesetStr = GetRulesetStringFromId(commentRulesetId);
   ulong orderTicket = ExtTrade.ResultOrder();
   datetime eventTime = g_lastTimer1Time;
   if(orderTicket > 0 && OrderSelect(orderTicket))
      eventTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
   double orderPrice = NormalizeDouble(levelPrice + offsetPips * PipSize(), _Digits);
   double stopLossVal = NormalizeDouble(orderPrice - slPips * PipSize(), _Digits);
   double takeProfitVal = NormalizeDouble(orderPrice + tpPips * PipSize(), _Digits);
   string orderComment = BuildUnifiedOrderComment((int)levelPrice, takeProfitVal, stopLossVal, orderPrice, commentRulesetId);
   WriteTradeLog(rulesetStr, "pending_created", eventTime, "buy_limit", orderPrice, stopLossVal, takeProfitVal, 30, orderTicket, 0, 0, (ENUM_DEAL_REASON)0, orderComment, magic);
}

//+------------------------------------------------------------------+
//| True if atTime is not inside any banned range for the given ruleset. |
//+------------------------------------------------------------------+
bool IsTimeAllowedForTradeType(int rulesetId, datetime atTime)
{
   if(rulesetId < 0 || rulesetId >= ArraySize(g_tradeConfig)) return true;
   if(StringLen(g_tradeConfig[rulesetId].bannedRangesStr) == 0)
      return true;
   ParseBannedRanges(g_tradeConfig[rulesetId].bannedRangesStr);
   return IsTradingAllowed(atTime, g_bannedRangesBuffer, g_bannedRangesCount);
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
//| True if level at levelsIdx meets bounce entry: bounceCount==requiredBounceCount, bias_long, no_contact, candlesPassedSinceLastBounce < 65, time allowed for rulesetId. |
//| no_contact is passed in (from current candle in_contact at close, or levels[].lastCandleInContact for OnTimer). Currently not used. |
//+------------------------------------------------------------------+
bool MeetsBuyBounceEntryRule(int levelsIdx, datetime atTime, int rulesetId, int requiredBounceCount, bool no_contact)
{
   if(levelsIdx < 0 || levelsIdx >= ArraySize(levels)) return false;
   bool bias_long = (levels[levelsIdx].dailyBias > 0);
   bool entryRule = (levels[levelsIdx].bounceCount == requiredBounceCount) && bias_long && no_contact && (levels[levelsIdx].candlesPassedSinceLastBounce < 65);
   return entryRule && IsTimeAllowedForTradeType(rulesetId, atTime);
}

//+------------------------------------------------------------------+
//| no comment
//+------------------------------------------------------------------+
bool MeetsRuleset121EntryRule(double levelBelow, int levelIdx, int kLast)
{
   if(GetPDtrendString() == "PD_red") return false;
   if(g_session[kLast] == "ON") return false;

   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < InpRuleset121_CleanStreakAboveMin) return false;
   string diffBelow = GetHighestDiffFromLevelInWindowString(levelBelow, kLast, 100, false);
   if(diffBelow == "never") return false;
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = GetHighestDiffFromLevelInWindowString(levelBelow, kLast, streakAbove, true);
   if(diffAbove == "never") return false;
   if(StringToDouble(diffAbove) < 12.0) return false;

   // rule: price recent range shouldn't be too big (below level)
   string diffBelow75 = GetHighestDiffFromLevelInWindowString(levelBelow, kLast, 75, false);
   // if(diffBelow75 != "never" && StringToDouble(diffBelow75) > 50.0) return false;
 
   // price must be below ON high so far (from UpdateONandRTHHighLowSoFarAtBar; we are in RTH so ON has run)
   if(levelBelow >= g_ONhighSoFarAtBar[kLast].value) return false;
   
   // dayHighSoFar - level must be < 25 (points)
   // if(g_dayHighSoFarAtBar[kLast].value - levelBelow >= 25.0) return false;
   return true;
}

//+------------------------------------------------------------------+
//| no comment |
//+------------------------------------------------------------------+
bool MeetsRuleset122EntryRule(double levelBelow, int levelIdx, int kLast)
{
   if(GetPDtrendString() == "PD_green") return false;
   if(g_session[kLast] == "ON") return false;
      
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < InpRuleset122_CleanStreakAboveMin) return false;
   string diffBelow = GetHighestDiffFromLevelInWindowString(levelBelow, kLast, 100, false);
   if(diffBelow == "never") return false;
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = GetHighestDiffFromLevelInWindowString(levelBelow, kLast, streakAbove, true);
   if(diffAbove == "never") return false;
   if(StringToDouble(diffAbove) < 12.0) return false;

   // rule: price recent range shouldn't be too big (below level)
   string diffBelow75 = GetHighestDiffFromLevelInWindowString(levelBelow, kLast, 75, false);
   // if(diffBelow75 != "never" && StringToDouble(diffBelow75) > 50.0) return false;
 



   // dayHighSoFar - level must be < 25 (points)
   // if(g_dayHighSoFarAtBar[kLast].value - levelBelow >= 25.0) return false;
   return true;
}

bool MeetsRuleset123EntryRule(double levelBelow, int levelIdx, int kLast)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   if(kLast < 0 || kLast >= g_barsInDay) return false;
   const int STREAK_MIN = 20;
   int streakAbove = g_cleanStreakAbove[levelIdx][kLast];
   if(streakAbove < STREAK_MIN) return false;
   string diffBelow = GetHighestDiffFromLevelInWindowString(levelBelow, kLast, 100, false);
   if(diffBelow == "never") return false;
   if(StringToDouble(diffBelow) < 10.0) return false;

   string diffAbove = GetHighestDiffFromLevelInWindowString(levelBelow, kLast, streakAbove, true);
   if(diffAbove == "never") return false;
   if(StringToDouble(diffAbove) < 12.0) return false;

   // rule: price recent range shouldn't be too big (below level)
   string diffBelow75 = GetHighestDiffFromLevelInWindowString(levelBelow, kLast, 75, false);
   // if(diffBelow75 != "never" && StringToDouble(diffBelow75) > 50.0) return false;
 

   // testing extra rules? PD_red PD_green
   if(GetPDtrendString() == "PD_red") return false;
   if(g_session[kLast] == "RTH") return false;
      

   // dayHighSoFar - level must be < 25 (points)
   // if(g_dayHighSoFarAtBar[kLast].value - levelBelow >= 25.0) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Validate trade_size_percentage is one of 10,20,30,40,50,60,70,80,90,100. FatalError if not. rulesetId = magic (BuildMagic). |
//+------------------------------------------------------------------+
int ValidateTradeSizePct(int pct, int rulesetId)
{
   if(pct == 10 || pct == 20 || pct == 30 || pct == 40 || pct == 50 ||
      pct == 60 || pct == 70 || pct == 80 || pct == 90 || pct == 100)
      return pct;
   FatalError("magic number (id) " + IntegerToString(rulesetId) + ": trade_size_percentage must be one of 10,20,30,40,50,60,70,80,90,100; got " + IntegerToString(pct));
   return 100;  // unreachable
}

//+------------------------------------------------------------------+
//| Lot for ruleset = global_base_trade_size × (trade_size_percentage/100). Normalized to symbol min/max/step. |
//+------------------------------------------------------------------+
double GetTradeLotForRuleset(int rulesetId)
{
   double base = g_global_base_trade_size;
   int pct = 100;
   if(rulesetId == 121) pct = ValidateTradeSizePct(InpRuleset121_TradeSizePct, 121);
   else if(rulesetId == 122) pct = ValidateTradeSizePct(InpRuleset122_TradeSizePct, 122);
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
//| Place a buy-limit at level with given pips and expiration. Sets magic then restores EA_MAGIC. Returns true if order sent successfully. |
//+------------------------------------------------------------------+
bool PlaceBuyLimitAtLevel(double levelPrice, double offsetPips, double slPips, double tpPips, int expirationMin, double lot, long magic, int commentRulesetId)
{
   if(maemfe_testing) { tpPips = 3000.0; slPips = 3000.0; }
   double pip = PipSize();
   double orderPrice = NormalizeDouble(levelPrice + offsetPips * pip, _Digits);
   double stopLossVal = NormalizeDouble(orderPrice - slPips * pip, _Digits);
   double takeProfitVal = NormalizeDouble(orderPrice + tpPips * pip, _Digits);
   datetime expiration = TimeCurrent() + expirationMin * 60;
   string comment = BuildUnifiedOrderComment((int)levelPrice, takeProfitVal, stopLossVal, orderPrice, commentRulesetId);
   ExtTrade.SetExpertMagicNumber(magic);
   bool ok = ExtTrade.BuyLimit(lot, orderPrice, _Symbol, stopLossVal, takeProfitVal, ORDER_TIME_SPECIFIED, expiration, comment);
   ExtTrade.SetExpertMagicNumber(EA_MAGIC);
   return ok;
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
//| Return the price distance of 1 pip. We only trade 2-decimal symbols (e.g. 123.45): 1 pip = 1 point. |
//+------------------------------------------------------------------+
double PipSize()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
//| Input params (e.g. InpRuleset*_TPPips) use display units; ×10 gives pips for PlaceBuyLimitAtLevel. Use for TP, SL, offset. |
//+------------------------------------------------------------------+
double InputPipsToOrderPips(double inputPips)
{
   return inputPips * 10.0;
}

//+------------------------------------------------------------------+
//| Open file for append (try existing first, else create). Returns handle or INVALID_HANDLE. |
//+------------------------------------------------------------------+
int OpenOrCreateForAppend(string path)
{
   int fileHandle = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_READ);
   if(fileHandle != INVALID_HANDLE)
      FileSeek(fileHandle, 0, SEEK_END);
   else
      fileHandle = FileOpen(path, FILE_WRITE | FILE_TXT);
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
//| Close any position opened by this EA (magic in EA_KNOWN_RULESET_IDS) that has been open longer than minutes. Sets trade magic so OUT deal pairs with IN. |
//+------------------------------------------------------------------+
void CloseAnyEAPositionThatIsXMinutesOld(int minutes)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!ExtPositionInfo.SelectByIndex(i)) continue;
      if(ExtPositionInfo.Symbol() != _Symbol) continue;
      long posMagic = ExtPositionInfo.Magic();
      bool isEaMagic = false;
      for(int k = 0; k < EA_KNOWN_RULESET_COUNT; k++)
         if(posMagic == BuildMagic(EA_KNOWN_RULESET_IDS[k])) { isEaMagic = true; break; }
      if(!isEaMagic) continue;
      if(g_lastTimer1Time - ExtPositionInfo.Time() <= (datetime)(minutes * 60)) continue;
      ExtTrade.SetExpertMagicNumber((ulong)posMagic);
      ExtTrade.PositionClose(ExtPositionInfo.Ticket());
      ExtTrade.SetExpertMagicNumber(EA_MAGIC);
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
      bool isEaMagic = false;
      for(int k = 0; k < EA_KNOWN_RULESET_COUNT; k++)
         if(posMagic == BuildMagic(EA_KNOWN_RULESET_IDS[k])) { isEaMagic = true; break; }
      if(!isEaMagic) continue;
      ExtTrade.SetExpertMagicNumber((ulong)posMagic);
      ExtTrade.PositionClose(ExtPositionInfo.Ticket());
      ExtTrade.SetExpertMagicNumber(EA_MAGIC);
   }
}

//+------------------------------------------------------------------+
//| Ruleset id from magic. Known IDs (EA_KNOWN_RULESET_IDS) return full id; otherwise 0. |
//+------------------------------------------------------------------+
int GetRulesetIdFromMagic(long magicNumber)
{
   for(int k = 0; k < EA_KNOWN_RULESET_COUNT; k++)
      if((long)EA_KNOWN_RULESET_IDS[k] == magicNumber) return EA_KNOWN_RULESET_IDS[k];
   return 0;
}

//+------------------------------------------------------------------+
//| B_TradeLog filename = B_TradeLog_(id). e.g. 2026.03.03_B_TradeLog_6.csv |
//+------------------------------------------------------------------+
string GetRulesetStringFromId(int rulesetId)
{
   if(rulesetId <= 0) return "";
   return IntegerToString(rulesetId);
}

//+------------------------------------------------------------------+
//| Ruleset string from magic; returns "" if unknown (use StringLen==0 to check). |
//+------------------------------------------------------------------+
string GetRulesetFromMagic(long magic)
{
   int rulesetId = GetRulesetIdFromMagic(magic);
   return (rulesetId > 0) ? GetRulesetStringFromId(rulesetId) : "";
}

//+------------------------------------------------------------------+
//| Build B_TradeLog filename by ruleset id only                     |
//+------------------------------------------------------------------+
string BuildTradeLogFileName(const string tradeType, datetime forTime)
{
   if(StringLen(tradeType) == 0) return "";
   string dateStr = TimeToString(forTime, TIME_DATE);
   return StringFormat("%s_B_TradeLog_%s.csv", dateStr, tradeType);
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
   int fileHandle1 = FileOpen(activeLevelsFile, FILE_WRITE | FILE_CSV | FILE_ANSI);
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
   int fileHandle2 = FileOpen(accountFile, FILE_WRITE | FILE_TXT);
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
   int fileHandle3 = FileOpen(ordersFile, FILE_WRITE | FILE_CSV | FILE_ANSI);
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
   int fileHandle4 = FileOpen(dealsFile, FILE_WRITE | FILE_CSV | FILE_ANSI);
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

//| comment: custom comment string (optional) |
//| magic: trade magic number when available (optional, 0 = omit from log) |
//+------------------------------------------------------------------+
void WriteTradeLog(const string tradeType, const string eventType, datetime eventTime,
                  const string orderKind = "", double orderPrice = 0, double slPrice = 0, double tpPrice = 0, int expirationMinutes = 0,
                  ulong orderTicket = 0, ulong dealTicket = 0, ulong positionTicket = 0,
                  ENUM_DEAL_REASON dealReason = (ENUM_DEAL_REASON)0, const string comment = "", long magic = 0)
{
   if(!finalLog_TradeLog) return;
   string fname = BuildTradeLogFileName(tradeType, eventTime);
   if(StringLen(fname) == 0) return;

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   int fileHandle = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(fileHandle == INVALID_HANDLE)
      fileHandle = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI);
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
   Print("Level Logger EA initialized.");
   ExtTrade.SetExpertMagicNumber(EA_MAGIC);

   // Ruleset config: useLevel/usePrice; bannedRangesStr applied when non-empty
   g_tradeConfig[121].bannedRangesStr = InpRuleset121_BannedRanges;
   g_tradeConfig[122].bannedRangesStr = InpRuleset122_BannedRanges;

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

   string tradeType = GetRulesetFromMagic(HistoryOrderGetInteger(trans.order, ORDER_MAGIC));
   if(StringLen(tradeType) == 0) return;

   datetime fillTime = (datetime)HistoryOrderGetInteger(trans.order, ORDER_TIME_DONE);
   string kindStr = OrderTypeToKindString((ENUM_ORDER_TYPE)HistoryOrderGetInteger(trans.order, ORDER_TYPE));
   long orderMagic = HistoryOrderGetInteger(trans.order, ORDER_MAGIC);
   WriteTradeLog(tradeType, "filled", fillTime, kindStr, 0, 0, 0, 0, trans.order, 0, 0, (ENUM_DEAL_REASON)0, "", orderMagic);
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

   string tradeType = GetRulesetFromMagic(HistoryDealGetInteger(trans.deal, DEAL_MAGIC));
   if(StringLen(tradeType) == 0) return;

   datetime fillTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   if(fillTime == 0) fillTime = g_lastTimer1Time;
   double fillPrice = 0;
   if(orderTicket > 0 && HistoryOrderSelect(orderTicket))
      fillPrice = HistoryOrderGetDouble(orderTicket, ORDER_PRICE_OPEN);
   if(fillPrice == 0) fillPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);

   long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   WriteTradeLog(tradeType, "filled", fillTime, kindStr, fillPrice, 0, 0, 0, orderTicket, trans.deal, 0, (ENUM_DEAL_REASON)0, comment, dealMagic);
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

   string tradeType = GetRulesetFromMagic(entryMagic);
   if(StringLen(tradeType) == 0) return;

   string kindStr = "";
   if(entryOrderTicket > 0 && HistoryOrderSelect(entryOrderTicket))
      kindStr = OrderTypeToKindString((ENUM_ORDER_TYPE)HistoryOrderGetInteger(entryOrderTicket, ORDER_TYPE));

   string eventType = "sl";
   if(reason == DEAL_REASON_TP) eventType = "tp";
   else if(reason == DEAL_REASON_EXPERT) eventType = "closed_by_ea";
   WriteTradeLog(tradeType, eventType, closeTime, kindStr, 0, 0, 0, 0, entryOrderTicket, trans.deal, posId, reason, comment, entryMagic);
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
   int fileHandleDay = FileOpen(dayStatLogName, FILE_WRITE | FILE_CSV | FILE_ANSI);
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
   int fileHandleSum = FileOpen("dayPriceStat_summaryLog.csv", FILE_WRITE | FILE_CSV | FILE_ANSI);
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
   int fileHandle = FileOpen(InpSessionFirstLastCandleFile, FILE_WRITE|FILE_TXT);
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

   // ontimer_babysit: after 11 min, try to set SL to -0.5 (price from entry); if not -0.5 try -1, -2, ... only tighter (never e.g. -6 -> -7)
   if(ontimer_babysit)
   {
      double babysit_targets[] = {-0.5, -1.0, -2.0, -3.0, -4.0, -5.0, -6.0, -7.0, -8.0, -9.0, -10.0};
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double tol = point * 0.5;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!ExtPositionInfo.SelectByIndex(i)) continue;
         if(ExtPositionInfo.Symbol() != _Symbol) continue;
         long posMagic = ExtPositionInfo.Magic();
         bool isEaMagic = false;
         for(int k = 0; k < EA_KNOWN_RULESET_COUNT; k++)
            if(posMagic == BuildMagic(EA_KNOWN_RULESET_IDS[k])) { isEaMagic = true; break; }
         if(!isEaMagic) continue;
         int minutesOpen = (int)((g_lastTimer1Time - ExtPositionInfo.Time()) / 60);
         if(minutesOpen < 11) continue;
         double openPrice = ExtPositionInfo.PriceOpen();
         double currentTP = ExtPositionInfo.TakeProfit();
         ulong ticket = ExtPositionInfo.Ticket();
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)ExtPositionInfo.PositionType();
         double currentSL = ExtPositionInfo.StopLoss();
         double currentOffset = (posType == POSITION_TYPE_BUY) ? (currentSL - openPrice) : (openPrice - currentSL);
         ExtTrade.SetExpertMagicNumber((ulong)posMagic);
         for(int t = 0; t < ArraySize(babysit_targets); t++)
         {
            double target = babysit_targets[t];
            if(target <= currentOffset) continue;   // only tighten: never e.g. -6 -> -7
            double newSL = (posType == POSITION_TYPE_BUY) ? openPrice + target : openPrice - target;
            newSL = NormalizeDouble(newSL, _Digits);
            if(MathAbs(newSL - currentSL) <= tol) break;
            if(!ExtTrade.PositionModify(ticket, newSL, currentTP)) continue;
            if(!ExtPositionInfo.SelectByTicket(ticket)) break;
            currentSL = ExtPositionInfo.StopLoss();
            currentOffset = (posType == POSITION_TYPE_BUY) ? (currentSL - openPrice) : (openPrice - currentSL);
            if(currentOffset >= target - tol) break;   // at or tighter than target
         }
         ExtTrade.SetExpertMagicNumber(EA_MAGIC);
      }
   }

   if(HasAnyLevelToday() && g_barsInDay > 0)
   {
      const int RULESET_ID_121 = 121;
      if(InpRuleset121_Enable)
      {
         double levelBelow121 = GetClosestNonTertiaryLevelBelowPrice(g_liveBid);
         int kLast = g_barsInDay - 1;
         if(levelBelow121 > 0.0 && IsLivePriceNearLevel(levelBelow121, 3.0))
         {
            int levelIdx121 = FindExpandedLevelIndexByPrice(levelBelow121);
            if(levelIdx121 >= 0 && MeetsRuleset121EntryRule(levelBelow121, levelIdx121, kLast) && IsTimeAllowedForTradeType(RULESET_ID_121, g_lastTimer1Time))
            {
               long magic121 = BuildMagic(RULESET_ID_121);
               if(CanPlaceNewOrderForMagic(magic121))
               {
                  double tp121   = InputPipsToOrderPips(InpRuleset121_TPPips);
                  double sl121   = InputPipsToOrderPips(InpRuleset121_SLPips);
                  double offsetPips121 = InputPipsToOrderPips(InpRuleset121_PriceOffsetPips);
                  if(PlaceBuyLimitAtLevel(levelBelow121, offsetPips121, sl121, tp121, 5, GetTradeLotForRuleset(RULESET_ID_121), magic121, RULESET_ID_121))
                     WriteTradeLogPendingOrder(RULESET_ID_121, levelBelow121, offsetPips121, sl121, tp121, magic121);
               }
            }
         }
      }

      // Ruleset 122: same placement pattern as 121; MeetsRuleset122EntryRule; separate inputs/magic.
      const int RULESET_ID_122 = 122;
      if(InpRuleset122_Enable)
      {
         double levelBelow122 = GetClosestNonTertiaryLevelBelowPrice(g_liveBid);
         int kLast = g_barsInDay - 1;
         if(levelBelow122 > 0.0 && IsLivePriceNearLevel(levelBelow122, 3.0))
         {
            int levelIdx122 = FindExpandedLevelIndexByPrice(levelBelow122);
            if(levelIdx122 >= 0 && MeetsRuleset122EntryRule(levelBelow122, levelIdx122, kLast) && IsTimeAllowedForTradeType(RULESET_ID_122, g_lastTimer1Time))
            {
               long magic122 = BuildMagic(RULESET_ID_122);
               if(CanPlaceNewOrderForMagic(magic122))
               {
                  double tp122   = InputPipsToOrderPips(InpRuleset122_TPPips);
                  double sl122   = InputPipsToOrderPips(InpRuleset122_SLPips);
                  double offsetPips122 = InputPipsToOrderPips(InpRuleset122_PriceOffsetPips);
                  if(PlaceBuyLimitAtLevel(levelBelow122, offsetPips122, sl122, tp122, 5, GetTradeLotForRuleset(RULESET_ID_122), magic122, RULESET_ID_122))
                     WriteTradeLogPendingOrder(RULESET_ID_122, levelBelow122, offsetPips122, sl122, tp122, magic122);
               }
            }
         }
      }
   }

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
      int fileHandle = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
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
         fileHandle = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI);
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
            int fileHandle = FileOpen(logName, FILE_WRITE | FILE_CSV | FILE_ANSI);
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
                     DoubleToString((g_dayHighSoFarAtBar[barIdx].value + g_dayLowSoFarAtBar[barIdx].value) / 2.0, 2),
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
            int fileHandleEod = FileOpen(eodSummaryName, FILE_WRITE | FILE_CSV | FILE_ANSI);
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
               int idx = FindOrAddPerTradeMagic(GetRulesetKeyFromMagic(tradeResult.magic));
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
            int fileHandleEodAll = FileOpen("summary_tradesSummary1line.csv", FILE_WRITE | FILE_CSV | FILE_ANSI);
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
            int fileHandlePer = FileOpen("summary_tradesSummary_perTrade.csv", FILE_WRITE | FILE_CSV | FILE_ANSI);
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
         if(dailyEODlog_TradeResultsCsv && g_tradeResultsCount > 0 && !FileIsExist(csvName))
         {
            int fileHandleTr = FileOpen(csvName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_CSV);
            if(fileHandleTr == INVALID_HANDLE)
               FatalError("OnTimer: could not open " + csvName);
            {
               FileWrite(fileHandleTr, "symbol", "startTime", "endTime", "session", "magic", "contactProximity", "priceStart", "priceEnd", "priceDiff", "profit", "type", "reason", "volume", "bothComments", "level", "tp", "sl", "MFE", "MAE", "mfeCandle", "maeCandle", "MFEp", "MAEp", "MFE_c6", "MAE_c6", "MFE_c11", "MAE_c11", "MFE_c16", "MAE_c16", "SL4_c", "TP6c", "SL6c", "TP8c", "SL8c", "TP10c", "SL10c", "TP12c", "SL12c", "3c_30c_level_breakevenC", "gapFillPc_at_tradeOpenTime", "openGap_info", "PD_trend", "dayBrokePDH", "dayBrokePDL", "referencePointsAbove", "referencePointsBelow", "levelTag", "levelCats");
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
                  string contactProxStr = GetContactProximityForTrade(tradeResult);
                  FileWrite(fileHandleTr, tradeResult.symbol, TimeToString(tradeResult.startTime, TIME_DATE|TIME_SECONDS), endTimeStr,
                     tradeResult.session, IntegerToString((long)tradeResult.magic), contactProxStr, DoubleToString(tradeResult.priceStart, _Digits), priceEndStr,
                     DoubleToString(tradeResult.priceDiff, _Digits), profitStr, typeStr, reasonStr,
                     DoubleToString(tradeResult.volume, 2), tradeResult.bothComments, tradeResult.level, tradeResult.tp, tradeResult.sl, mfeStr, maeStr, mfeCandleStr, maeCandleStr, mfepStr, maepStr, mfe_c6Str, mae_c6Str, mfe_c11Str, mae_c11Str, mfe_c16Str, mae_c16Str,
                     sl4_cStr, tp6cStr, sl6cStr, tp8cStr, sl8cStr, tp10cStr, sl10cStr, tp12cStr, sl12cStr, breakevenCStr,
                     gapFillPcStr, isGapDownDayStr, pdTrendStr, dayBrokePDHStr, dayBrokePDLStr, refAbove, refBelow, levelTagStr, levelCatsStr);
               }
               FileClose(fileHandleTr);
            }

            // All-days summary: read existing file (guaranteed correct schema), merge new day in memory, write whole file.
            // NEVER try to support old files from before schema changes. We always start clean. Don't care about backward compat.
            string summaryAllName = "summary_tradeResults_all_days.csv";
            const string TRADERESULTS_ALLDAYS_HEADER = "date,symbol,startTime,endTime,session,magic,contactProximity,priceStart,priceEnd,priceDiff,profit,type,reason,volume,bothComments,level,tp,sl,MFE,MAE,mfeCandle,maeCandle,MFEp,MAEp,MFE_c6,MAE_c6,MFE_c11,MAE_c11,MFE_c16,MAE_c16,SL4_c,TP6c,SL6c,TP8c,SL8c,TP10c,SL10c,TP12c,SL12c,3c_30c_level_breakevenC,gapFillPc_at_tradeOpenTime,openGap_info,PD_trend,dayBrokePDH,dayBrokePDL,referencePointsAbove,referencePointsBelow,levelTag,levelCats";
            string headerParts[];
            int schemaCols = StringSplit(TRADERESULTS_ALLDAYS_HEADER, ',', headerParts);
            string allDaysRows[];
            int existingRowCount = 0;
            int fileCols = 0;
            int fileHandleRead = FileOpen(summaryAllName, FILE_READ | FILE_CSV | FILE_ANSI);
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
            for(int o = 0; o < g_tradeResultsCount - 1; o++)
               for(int o2 = o + 1; o2 < g_tradeResultsCount; o2++)
                  if(g_tradeResults[orderTr[o2]].startTime < g_tradeResults[orderTr[o]].startTime)
                  { int tmp = orderTr[o]; orderTr[o] = orderTr[o2]; orderTr[o2] = tmp; }
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
               string contactProxStrAll = GetContactProximityForTrade(tradeResult);
               int r = newBase + ti * schemaCols;
               allDaysRows[r++] = dateStr;
               allDaysRows[r++] = tradeResult.symbol;
               allDaysRows[r++] = TimeToString(tradeResult.startTime, TIME_DATE|TIME_SECONDS);
               allDaysRows[r++] = endTimeStr;
               allDaysRows[r++] = tradeResult.session;
               allDaysRows[r++] = IntegerToString((long)tradeResult.magic);
               allDaysRows[r++] = contactProxStrAll;
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
            int fileHandleSumTr = FileOpen(summaryAllName, FILE_WRITE | FILE_CSV | FILE_ANSI);
            if(fileHandleSumTr != INVALID_HANDLE)
            {
               FileWrite(fileHandleSumTr, "date", "symbol", "startTime", "endTime", "session", "magic", "contactProximity", "priceStart", "priceEnd", "priceDiff", "profit", "type", "reason", "volume", "bothComments", "level", "tp", "sl", "MFE", "MAE", "mfeCandle", "maeCandle", "MFEp", "MAEp", "MFE_c6", "MAE_c6", "MFE_c11", "MAE_c11", "MFE_c16", "MAE_c16", "SL4_c", "TP6c", "SL6c", "TP8c", "SL8c", "TP10c", "SL10c", "TP12c", "SL12c", "3c_30c_level_breakevenC", "gapFillPc_at_tradeOpenTime", "openGap_info", "PD_trend", "dayBrokePDH", "dayBrokePDL", "referencePointsAbove", "referencePointsBelow", "levelTag", "levelCats");
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
               int fileHandleL = FileOpen(levelFile, FILE_WRITE | FILE_CSV | FILE_ANSI);
               if(fileHandleL == INVALID_HANDLE)
                  FatalError("OnTimer: could not open " + levelFile);
               FileWrite(fileHandleL, "time", "diff_CloseToLevel", "O", "H", "L", "C", "breaksLevelDown", "breaksLevelUpward", "cleanStreakAbove", "cleanStreakBelow", "aboveCnt", "abovePerc", "belowCnt", "belowPerc", "overlapStreak", "overlapC", "overlapPc", "HighestDiffUp_rangeArg", "HighestDiffUpRange", "HighestDiffDown_rangeArg", "HighestDiffDownRange", "ON_O_wasAboveL", "RTH_O_wasAboveL", "ONtradeCount_L", "ONwinRate_L", "ONpointsSum_L", "ONprofitSum_L", "RTHtradeCount_L", "RTHwinRate_L", "RTHpointsSum_L", "RTHprofitSum_L");
               double lvl = g_levelsExpanded[levelIdx].levelPrice;
               double onOpen = g_m1Rates[0].open;
               double rthOpenVal = 0.0;
               bool haveRthOpen = GetTodayRTHopenIfValid(rthOpenVal);
               for(int barIdx = 0; barIdx < g_levelsExpanded[levelIdx].count; barIdx++)
               {
                  string highestUp   = GetHighestDiffFromLevelInWindowString(lvl, barIdx, HighestDiffRange_Log, true);
                  string highestDown = GetHighestDiffFromLevelInWindowString(lvl, barIdx, HighestDiffRange_Log, false);
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
         int fileHandleBreak = FileOpen(breakCheckFile, FILE_WRITE | FILE_CSV | FILE_ANSI);
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
            int fileHandleSum = FileOpen("levels_breakCheck_breakingDown_tertiaryLevelsExcluded_summary.csv", FILE_WRITE | FILE_CSV | FILE_ANSI);
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
      int fileHandleAll = FileOpen(allFileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
      if(fileHandleAll == INVALID_HANDLE)
         fileHandleAll = FileOpen(allFileName, FILE_WRITE | FILE_CSV | FILE_ANSI);
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

            int fileHandleAra = FileOpen(araFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
            if(fileHandleAra == INVALID_HANDLE)
               fileHandleAra = FileOpen(araFile, FILE_WRITE | FILE_CSV | FILE_ANSI);
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