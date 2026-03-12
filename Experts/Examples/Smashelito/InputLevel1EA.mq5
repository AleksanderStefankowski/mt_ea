//+------------------------------------------------------------------+
//|                                                InputLevel1EA.mq5 |
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
input string   InpSessionFirstLastCandleFile = "SessionFirstLastCandle.txt";  // written in OnDeinit: symbol, timeframe, first/last candle OHLC
input string   InpAllCandleFile     = "AllCandlesLog_Timer1";
input double   ProximityThreshold   = 1.0;
input double   LevelCountsAsBroken_Threshold = -2.5; // how deep close must breach to count as broken
input int      HowManyCandlesAboveLevel_CountAsPriceRecovered = 6; // for RecoverCount
input int      BounceCandlesRequired = 1; // for bounce count logic
input int      Max_OrdersPerMagic = 1; // max open positions + pending orders with this magic (same full magic number)
input double   InpLotSize           = 0.01; // lot size for rulesets
input int      HourForDailySummary   = 21;   // hour (server time) when daily summary is written (timer/server time)
input int      MinuteForDailySummary = 30;   // minute of the hour for summary trigger
input bool     InpTestingPullM1History = true;  // if true: at 21:58-22:00 write (date)_testing_pullinghistory.csv and testinglevelsplus files
//--- Log to file: set false to disable that log (optimization)
//    finalLog_ = one file across whole run; dailyEODlog_ = daily once at EOD; dailySpamLog_ = daily and frequent
input bool     dailyEODlog_PullingHistory   = true;  // (date)_testing_pullinghistory.csv
input bool     dailyEODlog_DailySummary     = true;  // Day_activeLevels, account, orders, deals (WriteDailySummary)
input bool     dailyEODlog_EodTradesSummary = true;  // (date)_summary_EOD_tradesSummary1line.csv
input bool     finalLog_SummaryTrades1line  = true;  // summary_tradesSummary1line.csv
input bool     finalLog_SummaryTradesPerTrade = true;  // summary_tradesSummary_perTrade.csv (one row per magic)
input bool     dailyEODlog_TradeResultsCsv  = true;  // summaryZ_tradeResults_ALL_Day + summary_tradeResults_all_days
input bool     dailyEODlog_TestinglevelsPlus = true;  // (date)_testinglevelsplus_(level)_(tag).csv per level
input bool     dailyEODlog_BreakCheck       = true;  // levels_breakCheck files + summary
input bool     dailySpamLog_LivePrice       = true;  // (date)_testing_liveprice.csv 21:35-21:37
input bool     dailyEODlog_DayStat          = true;  // (date)_dayPriceStat_log.csv (TryLogDayStatForCurrentDay)
input bool     finalLog_DayStatSummary      = true;  // dayPriceStat_summaryLog.csv (WriteDayStatSummaryCsv)
input bool     finalLog_TradeLog            = true;  // B_TradeLog_(id).csv (WriteTradeLog)
input bool     dailySpamLog_AllCandles      = true;  // (date)-AllCandlesLog_Timer1.csv
input bool     finalLog_FirstLastCandle     = true;  // InpSessionFirstLastCandleFile (OnDeinit)
input bool     dailySpamLog_Arawevents      = true;  // Arawevents CSV + level logRawEv (FinalizeCurrentCandle)
input string   InpCalendarFile        = "calendar_2026_dots.csv";  // CSV in Terminal/Common/Files: date (YYYY.MM.DD),dayofmonth,dayofweek,opex,qopex
input string   InpLevelsFile          = "levelsinfo_zeFinal.csv";  // CSV in Terminal/Common/Files: start,end,levelPrice,categories,tag
input double   InpBreakCheckMaxDistPoints = 9.0;  // levels_breakCheck: first candle beyond this distance in price (and all newer) excluded
input bool     maemfe_testing             = true; // if true: all trades use TP=SL=3000.0 and close any position open >20 min (OnTimer)


//--- Ruleset 6: OnTimer params (offset/TP/SL pips, banned time ranges). Lot = InpRuleset6_LotSize.
input bool     InpRuleset6_Enable = true;   // disable trade. if false, ruleset 6 does not place orders
input double   InpRuleset6_PriceOffsetPips  = 7.0;   // order price = level + this many pips
input double   InpRuleset6_TPPips           = 8.0;   // TP (daily); ×10 = pips from order price
input double   InpRuleset6_SLPips           = 8.0;   // SL (daily); ×10 = pips
input double   InpRuleset6_TPPips_Weekly    = 10.0;  // TP when level categories contain "weekly"
input double   InpRuleset6_SLPips_Weekly    = 10.0;  // SL when level categories contain "weekly"
input string   InpRuleset6_BannedRanges = "0,0,0,59;15,15,16,35;21,28,23,59";  // startH,startM,endH,endM;...
//--- Ruleset 6: OnTimer every ~1s, liveBid near levelBelow (<3pts); entry: bounceCount==1, bias_long, no_contact, time filter; then buy limit at level+offset
input double   InpRuleset6_LotSize = 0.01;  // lot for ruleset 6 buy limit


//--- Ruleset 7: OnTimer params (offset/TP/SL pips, banned time ranges). Lot = InpRuleset7_LotSize.
input bool     InpRuleset7_Enable = true;   // if false, ruleset 7 does not place orders
input double   InpRuleset7_PriceOffsetPips  = 5.0;   // order price = level + this many pips
input double   InpRuleset7_TPPips           = 6.0;   // TP (daily); ×10 = pips from order price
input double   InpRuleset7_SLPips           = 2.0;   // SL (daily); ×10 = pips
input double   InpRuleset7_TPPips_Weekly    = 8.0;   // TP when level categories contain "weekly"
input double   InpRuleset7_SLPips_Weekly    = 3.0;   // SL when level categories contain "weekly"
input string   InpRuleset7_BannedRanges = "15,15,16,35";  // startH,startM,endH,endM;...
//--- Ruleset 7: same as 6 but bounceCount==3 and ruleset 7 banned time ranges; buy limit at level+offset
input double   InpRuleset7_LotSize = 0.01;  // lot for ruleset 7 buy limit


//--- Ruleset 5: cleanFirstBounceON (rulecheck in OnTimer: |liveBid-levelBelowL|<3pts, HighestDiffUp>12, overlapC==0, session ON, then buy limit)
input bool     InpRuleset5_Enable = true;   // if false, ruleset 5 does not place orders
input double   InpRuleset5_LotSize = 0.01;  // lot for ruleset 5 buy limit
input double   InpRuleset5_PriceOffsetPips  = 2.6;   // order price = level + (this×10) points; converted to pips for PlaceBuyLimitAtLevel
input double   InpRuleset5_TPPips           = 3.2;   // TP (daily); ×10 = pips from order price
input double   InpRuleset5_SLPips           = 5.0;   // SL (daily); ×10 = pips
input double   InpRuleset5_TPPips_Weekly    = 6.0;   // TP when level categories contain "weekly"
input double   InpRuleset5_SLPips_Weekly    = 6.0;   // SL when level categories contain "weekly"
input string   InpRuleset5_BannedRanges    = "0,0,0,55";  // startH,startM,endH,endM;... (e.g. 00:00–00:15)



//--- Ruleset config: useLevel/usePrice/useTimeFilter indicate what each ruleset cares about; bannedRangesStr from input.
struct TradeTypeConfig
{
   bool   useLevel;        // false = ruleset does not use level
   bool   usePrice;        // false = no price/level distance check
   bool   useTimeFilter;   // true = apply banned ranges; false = no time filter or fixed time only
   string bannedRangesStr; // "startH,startM,endH,endM;..." e.g. "0,0,2,59;20,0,23,59"
};
TradeTypeConfig g_tradeConfig[8];   // index by ruleset id 6 or 7
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

// Ruleset IDs used for time filter and magic (6 = bounceCount==1 style, 7 = bounceCount==3 style)
enum RULESET_ID
{
   RULESET_6 = 6,
   RULESET_7 = 7
};

// List of all known EA trade (ruleset) IDs that can open positions. Used e.g. by CloseAnyEAPositionThatIsXMinutesOld.
const int EA_KNOWN_RULESET_IDS[] = { 5, 6, 7 };
#define EA_KNOWN_RULESET_COUNT 3

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
int g_levelsTotalCount = 0;  // total levels (all dates); subset for today → g_levelsTodayCount

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
// Per-bar data (filled in UpdateDayM1AndLevelsExpanded; logged in 21:59-22:00 window)
double g_levelAboveH[MAX_BARS_IN_DAY];  // level (levelPrice) above candle high; 0 if none
double g_levelBelowL[MAX_BARS_IN_DAY];  // level below candle low; 0 if none
string g_session[MAX_BARS_IN_DAY];      // "ON"|"RTH"|"sleep"

//--- Day stat: open gap down (RTH open < PD RTH close). Set once after 21:30 candle; logged per day and in summary.
bool     dayStat_day_had_OpenGapDown_bool = false;
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

// First digit of magic (e.g. 6... or 7...). Used to group per-ruleset summary.
long FirstDigitOfMagic(long magic)
{
   long num = magic;
   if(num < 0) num = -num;
   while(num >= 10) num /= 10;
   return num;
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
//| Session for candle time: before 15:30 ON, 15:30-22:00 RTH, else sleep. |
//+------------------------------------------------------------------+
string GetSessionForCandleTime(datetime t)
{
   MqlDateTime mqlTime;
   TimeToStruct(t, mqlTime);
   int minOfDay = mqlTime.hour * 60 + mqlTime.min;
   if(minOfDay < 15*60+30) return "ON";   // before 15:30
   if(minOfDay <= 22*60+0) return "RTH"; // 15:30 to 22:00
   return "sleep";
}

//+------------------------------------------------------------------+
//| MFE/MAE from day M1: candles from 1 min after start to bar containing endTime. BUY: MFE=highest high, MAE=lowest low. SELL: MFE=lowest low, MAE=highest high. If range is 0 candles, use only the candle of end time. |
//+------------------------------------------------------------------+
void GetMFEandMAEForTrade(const TradeResult &tradeResult, double &mfe, double &mae)
{
   mfe = 0.0;
   mae = 0.0;
   if(!tradeResult.foundOut || tradeResult.endTime == 0 || g_barsInDay <= 0) return;
   datetime startPlus1Min = tradeResult.startTime + 60;
   datetime firstBarTime  = startPlus1Min - (startPlus1Min % 60);  // bar open 1 min after start (e.g. 01:22:00)
   datetime lastBarTime   = tradeResult.endTime - (tradeResult.endTime % 60);  // bar open that contains endTime (e.g. 01:26:00)
   double highestHigh = 0.0, lowestLow = 0.0;
   bool found = false;
   if(firstBarTime <= lastBarTime)
   {
      for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
      {
         datetime barTime = g_m1Rates[barIdx].time;
         if(barTime < firstBarTime) continue;
         if(barTime > lastBarTime) break;
         if(!found) { highestHigh = g_m1Rates[barIdx].high; lowestLow = g_m1Rates[barIdx].low; found = true; }
         else
         {
            if(g_m1Rates[barIdx].high > highestHigh) highestHigh = g_m1Rates[barIdx].high;
            if(g_m1Rates[barIdx].low < lowestLow) lowestLow = g_m1Rates[barIdx].low;
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
            found = true;
            break;
         }
   }
   if(!found) return;
   if(tradeResult.type == (long)DEAL_TYPE_BUY)
   {
      mfe = highestHigh;
      mae = lowestLow;
   }
   else  // DEAL_TYPE_SELL
   {
      mfe = lowestLow;
      mae = highestHigh;
   }
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
//| Find the 15:30 candle of current day in g_m1Rates. FatalError if not found. Returns its open price. |
//+------------------------------------------------------------------+
double GetRTHopenCurrentDay()
{
   if(g_barsInDay <= 0 || g_m1DayStart == 0)
      FatalError("GetRTHopenCurrentDay: no day data (g_barsInDay=" + IntegerToString(g_barsInDay) + " g_m1DayStart=0)");
   datetime targetTime = g_m1DayStart + 15*3600 + 30*60;  // 15:30 bar open time
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
      if(g_m1Rates[barIdx].time == targetTime)
         return g_m1Rates[barIdx].open;
   FatalError("GetRTHopenCurrentDay: 15:30 candle not found for " + TimeToString(g_m1DayStart, TIME_DATE));
   return 0.0;  // unreachable
}

//+------------------------------------------------------------------+
//| True if bar time (open time) is in RTHIB window: 15:30 to 16:30 inclusive. |
//+------------------------------------------------------------------+
bool IsBarRTHIB(datetime barTime)
{
   MqlDateTime mqlTime;
   TimeToStruct(barTime, mqlTime);
   int minOfDay = mqlTime.hour * 60 + mqlTime.min;
   return (minOfDay >= 15*60+30 && minOfDay <= 16*60+30);
}

//+------------------------------------------------------------------+
//| True if bar time (open time) is in RTHcnt window: 16:31 onward. |
//+------------------------------------------------------------------+
bool IsBarRTHcnt(datetime barTime)
{
   MqlDateTime mqlTime;
   TimeToStruct(barTime, mqlTime);
   int minOfDay = mqlTime.hour * 60 + mqlTime.min;
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

   // PDO = open of 1m candle 15:30 (M1), PDC = close of 1m candle 21:59 (M1) — that candle ends at 22:00
   datetime bar1530 = prevDayStart + 15*3600 + 30*60;
   datetime bar2159 = prevDayStart + 21*3600 + 59*60;
   int shift1530M1 = iBarShift(_Symbol, PERIOD_M1, bar1530, false);
   int shift2159M1 = iBarShift(_Symbol, PERIOD_M1, bar2159, false);
   if(shift1530M1 >= 0)
      g_staticMarketContext.PDOpreviousDayRTHOpen = iOpen(_Symbol, PERIOD_M1, shift1530M1);
   if(shift2159M1 >= 0)
      g_staticMarketContext.PDCpreviousDayRTHClose = iClose(_Symbol, PERIOD_M1, shift2159M1);

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
//| Load levels CSV from Terminal/Common/Files. Format: start,end,levelPrice,categories,tag (header on first line). start/end YYYY.MM.DD. |
//+------------------------------------------------------------------+
bool LoadLevels()
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
      g_levels[g_levelsTotalCount].startStr   = parts[0];
      g_levels[g_levelsTotalCount].endStr     = parts[1];
      g_levels[g_levelsTotalCount].levelPrice = StringToDouble(parts[2]);
      g_levels[g_levelsTotalCount].categories = parts[3];
      g_levels[g_levelsTotalCount].tag        = parts[4];
      g_levelsTotalCount++;
   }
   FileClose(fileHandle);
   return (g_levelsTotalCount > 0);
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
string GetHighestDiffInWindowString(double levelPrice, int barK, int windowBars, bool wantUp)
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

   // Ensure todayRTHopen is in g_levels when we have the 15:30 bar (data-driven; no reliance on new-bar event timing)
   {
      double open1530 = 0;
      for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
      {
         MqlDateTime mqlTime;
         TimeToStruct(g_m1Rates[barIdx].time, mqlTime);
         if(mqlTime.hour == 15 && mqlTime.min == 30)
            { open1530 = g_m1Rates[barIdx].open; break; }
      }
      if(open1530 != 0)
      {
         string todayStr = dateStr;
         bool alreadyAdded = false;
         for(int levelIdx = 0; levelIdx < g_levelsTotalCount; levelIdx++)
            if(g_levels[levelIdx].tag == "todayRTHopen" && g_levels[levelIdx].startStr == todayStr && g_levels[levelIdx].endStr == todayStr)
            { alreadyAdded = true; break; }
         bool tooClose = false;
         if(!alreadyAdded)
            for(int levelIdx = 0; levelIdx < g_levelsTotalCount; levelIdx++)
               if(g_levels[levelIdx].startStr <= todayStr && todayStr <= g_levels[levelIdx].endStr &&
                  MathAbs(g_levels[levelIdx].levelPrice - open1530) < tertiaryLevel_tooTight_toAdd_proximity)
               { tooClose = true; break; }
         if(!alreadyAdded && !tooClose && g_levelsTotalCount < MAX_LEVEL_ROWS)
         {
            AddLevel(todayStr + "_todayRTHopen", open1530, todayStr + " 00:00", todayStr + " 23:59", "daily_tertiary_todayRTHopen");
            g_levels[g_levelsTotalCount].startStr   = todayStr;
            g_levels[g_levelsTotalCount].endStr     = todayStr;
            g_levels[g_levelsTotalCount].levelPrice = open1530;
            g_levels[g_levelsTotalCount].categories = "daily_tertiary_todayRTHopen";
            g_levels[g_levelsTotalCount].tag        = "todayRTHopen";
            g_levelsTotalCount++;
         }
         else if(!alreadyAdded && !tooClose && g_levelsTotalCount >= MAX_LEVEL_ROWS)
            FatalError("todayRTHopen: 15:30 bar found but g_levels full (g_levelsTotalCount=" + IntegerToString(g_levelsTotalCount) + ")");
      }
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

         g_cleanStreakAbove[levelIdx][barIdx] = (barIdx == 0) ? 0 : (prevAbove ? 1 + runAbove : 0);
         g_cleanStreakBelow[levelIdx][barIdx] = (barIdx == 0) ? 0 : (prevBelow ? 1 + runBelow : 0);
         g_overlapStreak[levelIdx][barIdx]    = (barIdx == 0) ? 0 : (prevOverlap ? 1 + runOverlap : 0);

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

   // Per-bar: level above candle high, level below candle low, session (available globally; logged in 21:59-22:00)
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
      datetime candleCloseTime = (barIdx + 1 < g_barsInDay) ? g_m1Rates[barIdx + 1].time : (g_m1Rates[barIdx].time + 60);
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
         datetime candleCloseTime = (barIdx + 1 < barCount) ? g_levelsExpanded[levelIdx].times[barIdx + 1] : (g_levelsExpanded[levelIdx].times[barIdx] + 60);
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
//| Level below candle low at barIdx (g_levelBelowL). Returns 0.0 if barIdx invalid or no level. |
//+------------------------------------------------------------------+
double GetLevelBelow(int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0.0;
   return g_levelBelowL[barIdx];
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
//| Categories string for ruleset 5 (g_levelsExpanded). Returns "" if invalid. |
//+------------------------------------------------------------------+
string GetCategoriesFromExpanded(int levelIdx)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return "";
   return g_levelsExpanded[levelIdx].categories;
}

//+------------------------------------------------------------------+
//| Categories string for ruleset 6/7 (levels[].tagsCSV). Returns "" if invalid. |
//+------------------------------------------------------------------+
string GetCategoriesFromLevels(int levelsIdx)
{
   if(levelsIdx < 0 || levelsIdx >= ArraySize(levels)) return "";
   return levels[levelsIdx].tagsCSV;
}

//+------------------------------------------------------------------+
//| True if ruleset 5 entry conditions: HighestDiffUp > min, overlapC==0, session ON. Uses g_levelsExpanded[levelIdx], kLast. |
//+------------------------------------------------------------------+
bool MeetsRuleset5EntryRule(double levelBelow, int levelIdx, int kLast)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;
   const int HIGHEST_DIFF_UP_WINDOW = 15;
   const double HIGHEST_DIFF_UP_MIN = 9.0;
   string highestUp = GetHighestDiffInWindowString(levelBelow, kLast, HIGHEST_DIFF_UP_WINDOW, true);
   if(highestUp == "never") return false;
   if(StringToDouble(highestUp) <= HIGHEST_DIFF_UP_MIN) return false;
   if(g_overlapC[levelIdx][kLast] != 0) return false;
   if(g_session[kLast] != "ON") return false;
   return true;
}

//+------------------------------------------------------------------+
//| Unified order comment: $ (int)levelPrice takeProfitVal stopLossVal orderPrice commentRulesetId. Used by rulesets 5, 6, 7. |
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
   if(!g_tradeConfig[rulesetId].useTimeFilter || StringLen(g_tradeConfig[rulesetId].bannedRangesStr) == 0)
      return true;
   ParseBannedRanges(g_tradeConfig[rulesetId].bannedRangesStr);
   return IsTradingAllowed(atTime, g_bannedRangesBuffer, g_bannedRangesCount);
}

//+------------------------------------------------------------------+
//| True if level at levelsIdx meets ruleset 6/7 bounce entry: bounceCount==requiredBounceCount, bias_long, no_contact, candlesPassedSinceLastBounce < 65, time allowed for rulesetId. |
//| no_contact is passed in (from current candle in_contact at close, or levels[].lastCandleInContact for OnTimer). |
//+------------------------------------------------------------------+
bool MeetsBuyBounceEntryRule(int levelsIdx, datetime atTime, int rulesetId, int requiredBounceCount, bool no_contact)
{
   if(levelsIdx < 0 || levelsIdx >= ArraySize(levels)) return false;
   bool bias_long = (levels[levelsIdx].dailyBias > 0);
   bool entryRule = (levels[levelsIdx].bounceCount == requiredBounceCount) && bias_long && no_contact && (levels[levelsIdx].candlesPassedSinceLastBounce < 65);
   return entryRule && IsTimeAllowedForTradeType(rulesetId, atTime);
}

//+------------------------------------------------------------------+
//| True if level at levelsIdx meets ruleset 6 entry rule (bounceCount==1, bias_long, no_contact, candlesPassedSinceLastBounce < 65) and time allowed at atTime. |
//+------------------------------------------------------------------+
bool MeetsRuleset6EntryRule(int levelsIdx, datetime atTime)
{
   if(levelsIdx < 0 || levelsIdx >= ArraySize(levels)) return false;
   return MeetsBuyBounceEntryRule(levelsIdx, atTime, RULESET_6, 1, !levels[levelsIdx].lastCandleInContact);
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

double PipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5) return SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0;
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
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
//| Extract ruleset id from magic number (first digit).           |
//| Magic is long; never cast to int (overflow). Use long for string. |
//+------------------------------------------------------------------+
//| Ruleset id from magic (leading digit(s)); returns 0 if unknown. |
//+------------------------------------------------------------------+
int GetRulesetIdFromMagic(long magicNumber)
{
   string magicStr = IntegerToString((long)magicNumber);
   if(StringLen(magicStr) > 0)
      return (int)StringToInteger(StringSubstr(magicStr, 0, 1));
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
      FileWrite(fileHandle1, "levelNo", "name", "price", "count", "contacts", "bias", "bounces");
      datetime today = now - (now % 86400);
      for(int i=0; i<ArraySize(levels); i++)
      {
         if(levels[i].validFrom <= today && levels[i].validTo >= today)
         {
            FileWrite(fileHandle1, IntegerToString(i), levels[i].baseName, DoubleToString(levels[i].price, _Digits),
                      IntegerToString(levels[i].count), IntegerToString(levels[i].approxContactCount),
                      DoubleToString(levels[i].dailyBias, 0), IntegerToString(levels[i].bounceCount));
         }
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

   // Ruleset config: useLevel/usePrice/useTimeFilter indicate what each ruleset cares about (level, price, time)
   g_tradeConfig[RULESET_6].useLevel = true;
   g_tradeConfig[RULESET_6].usePrice = true;
   g_tradeConfig[RULESET_6].useTimeFilter = true;
   g_tradeConfig[RULESET_6].bannedRangesStr = InpRuleset6_BannedRanges;

   g_tradeConfig[5].useTimeFilter = true;
   g_tradeConfig[5].bannedRangesStr = InpRuleset5_BannedRanges;

   g_tradeConfig[RULESET_7].useLevel = true;
   g_tradeConfig[RULESET_7].usePrice = true;
   g_tradeConfig[RULESET_7].useTimeFilter = true;
   g_tradeConfig[RULESET_7].bannedRangesStr = InpRuleset7_BannedRanges;

   EventSetTimer(1);   // 1 second timer for candle-close detection

   g_liveBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_liveAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(!LoadCalendar())
      Print("Calendar file not loaded: ", InpCalendarFile, " (place CSV in Terminal/Common/Files)");
   else
      Print("Calendar loaded: ", g_calendarCount, " rows from ", InpCalendarFile);

   if(!LoadLevels())
   {
      Print("Levels file not loaded: ", InpLevelsFile, " (place CSV in Terminal/Common/Files)");
      return(INIT_FAILED);
   }
   Print("Levels loaded: ", g_levelsTotalCount, " rows from ", InpLevelsFile);
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
   dayStat_day_had_OpenGapDown_bool = (rthOpen < pdc);
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
      FileWrite(fileHandleDay, "date", "hasGapDown", "hasGapUp", "RTHopen", "PD_RTH_Close", "gap_fill_pc", "gapDiff", "rthHigh", "rthLow", "ONH", "ONL", "ONH_t_RTH", "ONL_t_RTH", "ONboth_t_RTH");
      FileWrite(fileHandleDay, dateStrStat, (dayStat_day_had_OpenGapDown_bool ? "true" : "false"), (dayStat_hasGapUp ? "true" : "false"), DoubleToString(rthOpen, _Digits), DoubleToString(pdc, _Digits), DoubleToString(dayStat_openGapDown_percentageFill, 2), DoubleToString(dayStat_gapDiff, _Digits), DoubleToString(dayStat_rthHigh, _Digits), DoubleToString(dayStat_rthLow, _Digits), DoubleToString(dayStat_onHigh, _Digits), DoubleToString(dayStat_onLow, _Digits), (dayStat_ONH_t_RTH ? "true" : "false"), (dayStat_ONL_t_RTH ? "true" : "false"), (dayStat_ONboth_t_RTH ? "true" : "false"));
      FileClose(fileHandleDay);
   }
   }

   dayStat_totalDays++;
   if(dayStat_day_had_OpenGapDown_bool)
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

   if(maemfe_testing)
      CloseAnyEAPositionThatIsXMinutesOld(20);

   // Rulecheck: on timer, use latest candle's levelBelow. If g_liveBid near levelBelow (IsLivePriceNearLevel) → ruleset 5 cleanFirstBounceON; then ruleset 6.
   if(g_barsInDay > 0 && g_levelsTodayCount > 0)
   {
      const int RULESET_ID_CLEAN_FIRST_BOUNCE_ON = 5;

      if(InpRuleset5_Enable)
      {
         double levelBelow = GetLevelBelow(g_barsInDay - 1);
         int kLast = g_barsInDay - 1;
         if(IsLivePriceNearLevel(levelBelow, 3.0))
         {
            int levelIdx = FindExpandedLevelIndexByPrice(levelBelow);
            if(levelIdx >= 0 && MeetsRuleset5EntryRule(levelBelow, levelIdx, kLast) && IsTimeAllowedForTradeType(RULESET_ID_CLEAN_FIRST_BOUNCE_ON, g_lastTimer1Time))
            {
               long magic = BuildMagic(RULESET_ID_CLEAN_FIRST_BOUNCE_ON);
               if(CountOrdersAndPositionsForMagic(magic) == 0)
               {
                  int overnightTradeCount = GetONtradeCount(kLast);
                  double overnightWinRate = GetONwinRate(kLast);
                  bool blockOnePerfect = (overnightTradeCount == 1 && overnightWinRate >= 1.0);
                  if(!blockOnePerfect && overnightTradeCount < 3)
                  {
                     string categories = GetCategoriesFromExpanded(levelIdx);
                     bool weekly = LevelIsWeekly(categories);
                     double tp = (weekly ? InpRuleset5_TPPips_Weekly : InpRuleset5_TPPips) * 10.0;
                     double sl = (weekly ? InpRuleset5_SLPips_Weekly : InpRuleset5_SLPips) * 10.0;
                     double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                     double offsetPips5 = (InpRuleset5_PriceOffsetPips * 10.0) * point / PipSize();
                     if(PlaceBuyLimitAtLevel(levelBelow, offsetPips5, sl, tp, 15, InpRuleset5_LotSize, magic, RULESET_ID_CLEAN_FIRST_BOUNCE_ON))
                        WriteTradeLogPendingOrder(RULESET_ID_CLEAN_FIRST_BOUNCE_ON, levelBelow, offsetPips5, sl, tp, magic);
                  }
               }
            }
         }
      }

      // Ruleset 6: every OnTimer, live price near levelBelow; entry (bounceCount==1, bias_long, no_contact, time filter); buy limit at level+offset.
      const int RULESET_ID_6 = 6;
      if(InpRuleset6_Enable)
      {
         double levelBelow6 = GetLevelBelow(g_barsInDay - 1);
         if(IsLivePriceNearLevel(levelBelow6, 3.0))
         {
            int levelsIdx = FindLevelIndexByPriceAndTime(levelBelow6, g_lastTimer1Time);
            if(levelsIdx >= 0 && MeetsRuleset6EntryRule(levelsIdx, g_lastTimer1Time))
            {
               long magic6 = BuildMagic(RULESET_ID_6);
               if(CountOrdersAndPositionsForMagic(magic6) == 0)
               {
                  string categories = GetCategoriesFromLevels(levelsIdx);
                  bool weekly = LevelIsWeekly(categories);
                  double tp = (weekly ? InpRuleset6_TPPips_Weekly : InpRuleset6_TPPips) * 10.0;
                  double sl = (weekly ? InpRuleset6_SLPips_Weekly : InpRuleset6_SLPips) * 10.0;
                  if(PlaceBuyLimitAtLevel(levelBelow6, InpRuleset6_PriceOffsetPips, sl, tp, 30, InpRuleset6_LotSize, magic6, RULESET_ID_6))
                     WriteTradeLogPendingOrder(RULESET_ID_6, levelBelow6, InpRuleset6_PriceOffsetPips, sl, tp, magic6);
               }
            }
         }
      }

      // Ruleset 7: same as 6 but bounceCount==3 and ruleset 7 banned time ranges; buy limit at level+offset.
      const int RULESET_ID_7 = 7;
      if(InpRuleset7_Enable)
      {
         double levelBelow7 = GetLevelBelow(g_barsInDay - 1);
         if(IsLivePriceNearLevel(levelBelow7, 3.0))
         {
            int levelsIdx7 = FindLevelIndexByPriceAndTime(levelBelow7, g_lastTimer1Time);
            if(levelsIdx7 >= 0 && MeetsBuyBounceEntryRule(levelsIdx7, g_lastTimer1Time, RULESET_7, 3, !levels[levelsIdx7].lastCandleInContact))
            {
               long magic7 = BuildMagic(RULESET_ID_7);
               if(CountOrdersAndPositionsForMagic(magic7) == 0)
               {
                  string categories = GetCategoriesFromLevels(levelsIdx7);
                  bool weekly = LevelIsWeekly(categories);
                  double tp = (weekly ? InpRuleset7_TPPips_Weekly : InpRuleset7_TPPips) * 10.0;
                  double sl = (weekly ? InpRuleset7_SLPips_Weekly : InpRuleset7_SLPips) * 10.0;
                  if(PlaceBuyLimitAtLevel(levelBelow7, InpRuleset7_PriceOffsetPips, sl, tp, 30, InpRuleset7_LotSize, magic7, RULESET_ID_7))
                     WriteTradeLogPendingOrder(RULESET_ID_7, levelBelow7, InpRuleset7_PriceOffsetPips, sl, tp, magic7);
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

   if(maemfe_testing)
      CloseAnyEAPositionThatIsXMinutesOld(20);

   // Pull static context for today before refresh so PDC is available when building levels (single UpdateDayM1AndLevelsExpanded per bar)
   datetime dayStartForContext = g_lastTimer1Time - (g_lastTimer1Time % 86400);
   if(g_staticMarketContextPulledForDate != dayStartForContext)
   {
      UpdateStaticMarketContext(dayStartForContext);
      g_staticMarketContextPulledForDate = dayStartForContext;
   }

   // Refresh day M1 and levels first; then "the bar that just closed" = last bar in day M1 (same source as all level-bar stats)
   UpdateDayM1AndLevelsExpanded();

   if(g_barsInDay > 0)
   {
      // g_m1Rates is oldest-first: [0]=first bar of day, [g_barsInDay-1]=last; bar that just closed = second-to-last when >=2 bars
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

   FinalizeCurrentCandle();

   // --- ON and RTH session high/low so far at each bar k (bars 0..k). Fresh each candle; log reads from g_*AtBar[k].
   bool firstON = true, firstRTH = true;
   double runONhigh = 0, runONlow = 0, runRTHhigh = 0, runRTHlow = 0;
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
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
   // --- Logging only in time window (performance)
   if(InpTestingPullM1History)
   {
      MqlDateTime mtTest;
      TimeToStruct(g_lastTimer1Time, mtTest);
      int minOfDay = mtTest.hour * 60 + mtTest.min;
      datetime dayStart = g_lastTimer1Time - (g_lastTimer1Time % 86400);
      string dateStr = TimeToString(dayStart, TIME_DATE);
      bool inLogWindow = (minOfDay >= 21*60+58 && minOfDay <= 22*60+0);  // 21:58, 21:59, 22:00 (last bar may be 21:58 on Friday)
      if(inLogWindow && g_barsInDay > 0)
      {
         int kLast = g_barsInDay - 1;
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
                     "PDOpreviousDayRTHOpen", "PDHpreviousDayHigh", "PDLpreviousDayLow", "PDCpreviousDayRTHClose", "PDdate");
         for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
            {
               if(!g_ONhighSoFarAtBar[barIdx].hasValue || !g_ONlowSoFarAtBar[barIdx].hasValue)
                  FatalError("pullinghistory: ONhighSoFar/ONlowSoFar required but no ON bar so far at bar k=" + IntegerToString(barIdx) + " time=" + TimeToString(g_m1Rates[barIdx].time, TIME_DATE|TIME_MINUTES));
               string rthH = g_rthHighSoFarAtBar[barIdx].hasValue ? DoubleToString(g_rthHighSoFarAtBar[barIdx].value, _Digits) : "";
               string rthL = g_rthLowSoFarAtBar[barIdx].hasValue ? DoubleToString(g_rthLowSoFarAtBar[barIdx].value, _Digits) : "";
               FileWrite(fileHandle, TimeToString(g_m1Rates[barIdx].time, TIME_DATE|TIME_MINUTES),
                     DoubleToString(g_m1Rates[barIdx].open, _Digits), DoubleToString(g_m1Rates[barIdx].high, _Digits), DoubleToString(g_m1Rates[barIdx].low, _Digits), DoubleToString(g_m1Rates[barIdx].close, _Digits),
                     DoubleToString(g_levelAboveH[barIdx], 0), DoubleToString(g_levelBelowL[barIdx], 0), g_session[barIdx],
                     DoubleToString(g_dayProgress[barIdx].dayWinRate * 100.0, 0), IntegerToString(g_dayProgress[barIdx].dayTradesCount), DoubleToString(g_dayProgress[barIdx].dayPointsSum, _Digits), DoubleToString(g_dayProgress[barIdx].dayProfitSum, 2),
                     DoubleToString(g_dayProgress[barIdx].ONwinRate * 100.0, 0), IntegerToString(g_dayProgress[barIdx].ONtradeCount), DoubleToString(g_dayProgress[barIdx].ONpointsSum, _Digits), DoubleToString(g_dayProgress[barIdx].ONprofitSum, 2),
                     DoubleToString(g_dayProgress[barIdx].RTHwinRate * 100.0, 0), IntegerToString(g_dayProgress[barIdx].RTHtradeCount), DoubleToString(g_dayProgress[barIdx].RTHpointsSum, _Digits), DoubleToString(g_dayProgress[barIdx].RTHprofitSum, 2),
                     DoubleToString(g_ONhighSoFarAtBar[barIdx].value, _Digits), DoubleToString(g_ONlowSoFarAtBar[barIdx].value, _Digits), rthH, rthL,
                     DoubleToString(g_staticMarketContext.PDOpreviousDayRTHOpen, _Digits), DoubleToString(g_staticMarketContext.PDHpreviousDayHigh, _Digits), DoubleToString(g_staticMarketContext.PDLpreviousDayLow, _Digits), DoubleToString(g_staticMarketContext.PDCpreviousDayRTHClose, _Digits), g_staticMarketContext.PDdate);
            }
            FileClose(fileHandle);
         }

         // EOD one-line trades summary: same trade stats as latest row of pullinghistory (date)_summary_EOD_tradesSummary1line.csv
         string eodSummaryName = dateStr + "_summary_EOD_tradesSummary1line.csv";
         if(dailyEODlog_EodTradesSummary && !FileIsExist(eodSummaryName))
         {
            int fileHandleEod = FileOpen(eodSummaryName, FILE_WRITE | FILE_CSV | FILE_ANSI);
            if(fileHandleEod != INVALID_HANDLE)
            {
               FileWrite(fileHandleEod, "time", "dayWinRate", "dayTradesCount", "dayPointsSum", "dayProfitSum", "ONwinRate", "ONtradeCount", "ONpointsSum", "ONprofitSum", "RTHwinRate", "RTHtradeCount", "RTHpointsSum", "RTHprofitSum");
               if(kLast >= 0)
               {
                  FileWrite(fileHandleEod, TimeToString(g_m1Rates[kLast].time, TIME_DATE|TIME_MINUTES),
                     DoubleToString(g_dayProgress[kLast].dayWinRate * 100.0, 0), IntegerToString(g_dayProgress[kLast].dayTradesCount), DoubleToString(g_dayProgress[kLast].dayPointsSum, _Digits), DoubleToString(g_dayProgress[kLast].dayProfitSum, 2),
                     DoubleToString(g_dayProgress[kLast].ONwinRate * 100.0, 0), IntegerToString(g_dayProgress[kLast].ONtradeCount), DoubleToString(g_dayProgress[kLast].ONpointsSum, _Digits), DoubleToString(g_dayProgress[kLast].ONprofitSum, 2),
                     DoubleToString(g_dayProgress[kLast].RTHwinRate * 100.0, 0), IntegerToString(g_dayProgress[kLast].RTHtradeCount), DoubleToString(g_dayProgress[kLast].RTHpointsSum, _Digits), DoubleToString(g_dayProgress[kLast].RTHprofitSum, 2));
               }
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
               int idx = FindOrAddPerTradeMagic(FirstDigitOfMagic(tradeResult.magic));
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

         // Trade results CSV: (date)_summaryZ_tradeResults_ALL_Day.csv (only once; if missing, write again)
         string csvName = dateStr + "_summaryZ_tradeResults_ALL_Day.csv";
         if(dailyEODlog_TradeResultsCsv && !FileIsExist(csvName))
         {
            int fileHandleTr = FileOpen(csvName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_CSV);
            if(fileHandleTr == INVALID_HANDLE)
               FatalError("OnTimer: could not open " + csvName);
            {
               FileWrite(fileHandleTr, "symbol", "startTime", "endTime", "session", "magic", "priceStart", "priceEnd", "priceDiff", "profit", "type", "reason", "volume", "bothComments", "level", "tp", "sl", "MFE", "MAE");
               for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
               {
                  TradeResult tradeResult = g_tradeResults[trIdx];
                  double mfe = 0.0, mae = 0.0;
                  GetMFEandMAEForTrade(tradeResult, mfe, mae);
                  string endTimeStr = tradeResult.foundOut ? TimeToString(tradeResult.endTime, TIME_DATE|TIME_SECONDS) : "NOT_FOUND";
                  string priceEndStr = tradeResult.foundOut ? DoubleToString(tradeResult.priceEnd, _Digits) : "NOT_FOUND";
                  string profitStr = tradeResult.foundOut ? DoubleToString(tradeResult.profit, 2) : "NOT_FOUND";
                  string reasonStr = tradeResult.foundOut ? EnumToString((ENUM_DEAL_REASON)tradeResult.reason) : "NOT_FOUND";
                  string typeStr = EnumToString((ENUM_DEAL_TYPE)tradeResult.type);
                  string mfeStr = (mfe != 0.0 || mae != 0.0) ? DoubleToString(mfe, _Digits) : "";
                  string maeStr = (mfe != 0.0 || mae != 0.0) ? DoubleToString(mae, _Digits) : "";
                  FileWrite(fileHandleTr, tradeResult.symbol, TimeToString(tradeResult.startTime, TIME_DATE|TIME_SECONDS), endTimeStr,
                     tradeResult.session, IntegerToString((long)tradeResult.magic), DoubleToString(tradeResult.priceStart, _Digits), priceEndStr,
                     DoubleToString(tradeResult.priceDiff, _Digits), profitStr, typeStr, reasonStr,
                     DoubleToString(tradeResult.volume, 2), tradeResult.bothComments, tradeResult.level, tradeResult.tp, tradeResult.sl, mfeStr, maeStr);
               }
               FileClose(fileHandleTr);
            }

            // All-days summary: read existing file into memory, add current day with MFE/MAE, write full file in overwrite mode.
            string summaryAllName = "summary_tradeResults_all_days.csv";
            #define TRADERESULTS_ALLDAYS_COLS 19
            string allDaysRows[];
            int existingRowCount = 0;
            int fileHandleRead = FileOpen(summaryAllName, FILE_READ | FILE_CSV | FILE_ANSI);
            if(fileHandleRead != INVALID_HANDLE)
            {
               for(int h = 0; h < TRADERESULTS_ALLDAYS_COLS && !FileIsEnding(fileHandleRead); h++)
                  FileReadString(fileHandleRead);
               while(!FileIsEnding(fileHandleRead))
               {
                  int base = ArraySize(allDaysRows);
                  ArrayResize(allDaysRows, base + TRADERESULTS_ALLDAYS_COLS);
                  int c = 0;
                  for(; c < TRADERESULTS_ALLDAYS_COLS && !FileIsEnding(fileHandleRead); c++)
                     allDaysRows[base + c] = FileReadString(fileHandleRead);
                  if(c == TRADERESULTS_ALLDAYS_COLS)
                     existingRowCount++;
                  else
                     ArrayResize(allDaysRows, base);
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
            int newBase = existingRowCount * TRADERESULTS_ALLDAYS_COLS;
            ArrayResize(allDaysRows, newBase + g_tradeResultsCount * TRADERESULTS_ALLDAYS_COLS);
            for(int ti = 0; ti < g_tradeResultsCount; ti++)
            {
               int trIdx = orderTr[ti];
               TradeResult tradeResult = g_tradeResults[trIdx];
               double mfe = 0.0, mae = 0.0;
               GetMFEandMAEForTrade(tradeResult, mfe, mae);
               string endTimeStr = tradeResult.foundOut ? TimeToString(tradeResult.endTime, TIME_DATE|TIME_SECONDS) : "NOT_FOUND";
               string priceEndStr = tradeResult.foundOut ? DoubleToString(tradeResult.priceEnd, _Digits) : "NOT_FOUND";
               string profitStr = tradeResult.foundOut ? DoubleToString(tradeResult.profit, 2) : "NOT_FOUND";
               string reasonStr = tradeResult.foundOut ? EnumToString((ENUM_DEAL_REASON)tradeResult.reason) : "NOT_FOUND";
               string typeStr = EnumToString((ENUM_DEAL_TYPE)tradeResult.type);
               string mfeStr = (mfe != 0.0 || mae != 0.0) ? DoubleToString(mfe, _Digits) : "";
               string maeStr = (mfe != 0.0 || mae != 0.0) ? DoubleToString(mae, _Digits) : "";
               int r = newBase + ti * TRADERESULTS_ALLDAYS_COLS;
               allDaysRows[r++] = dateStr;
               allDaysRows[r++] = tradeResult.symbol;
               allDaysRows[r++] = TimeToString(tradeResult.startTime, TIME_DATE|TIME_SECONDS);
               allDaysRows[r++] = endTimeStr;
               allDaysRows[r++] = tradeResult.session;
               allDaysRows[r++] = IntegerToString((long)tradeResult.magic);
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
            }
            int fileHandleSumTr = FileOpen(summaryAllName, FILE_WRITE | FILE_CSV | FILE_ANSI);
            if(fileHandleSumTr != INVALID_HANDLE)
            {
               FileWrite(fileHandleSumTr, "date", "symbol", "startTime", "endTime", "session", "magic", "priceStart", "priceEnd", "priceDiff", "profit", "type", "reason", "volume", "bothComments", "level", "tp", "sl", "MFE", "MAE");
               int totalRows = existingRowCount + g_tradeResultsCount;
               for(int ri = 0; ri < totalRows; ri++)
               {
                  int base = ri * TRADERESULTS_ALLDAYS_COLS;
                  FileWrite(fileHandleSumTr, allDaysRows[base], allDaysRows[base+1], allDaysRows[base+2], allDaysRows[base+3], allDaysRows[base+4], allDaysRows[base+5], allDaysRows[base+6], allDaysRows[base+7], allDaysRows[base+8], allDaysRows[base+9], allDaysRows[base+10], allDaysRows[base+11], allDaysRows[base+12], allDaysRows[base+13], allDaysRows[base+14], allDaysRows[base+15], allDaysRows[base+16], allDaysRows[base+17], allDaysRows[base+18]);
               }
               FileClose(fileHandleSumTr);
            }
            #undef TRADERESULTS_ALLDAYS_COLS
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
               double rthOpen = GetRTHopenCurrentDay();
               for(int barIdx = 0; barIdx < g_levelsExpanded[levelIdx].count; barIdx++)
               {
                  string highestUp   = GetHighestDiffInWindowString(lvl, barIdx, HighestDiffRange_Log, true);
                  string highestDown = GetHighestDiffInWindowString(lvl, barIdx, HighestDiffRange_Log, false);
                  bool onKnown   = (barIdx > 0);
                  bool rthKnown  = (GetSessionForCandleTime(g_levelsExpanded[levelIdx].times[barIdx]) != "ON");
                  string onAboveStr  = GetOpenWasAboveLevelString(onOpen, lvl, onKnown);
                  string rthAboveStr = GetOpenWasAboveLevelString(rthOpen, lvl, rthKnown);
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

         // Levels break check: one row per level (21:58). Separate ON (til 15:30) and RTH (15:30 onward). Rows sorted by levelPrice.
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
         FileWrite(fileHandleAll, "time", "O", "H", "L", "C");
      allCandlesFileHandle = fileHandleAll;
      allCandlesFileDate = candleDay;
   }

   // Day stat: once after 21:30 candle, set dayStat_day_had_OpenGapDown_bool (RTH open < PD RTH close) and write dayPriceStat_log + dayPriceStat_summaryLog
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

         // --- Flow B: ruleset 6/7 place orders from OnTimer.
      }
   }

   if(allCandlesFileHandle != INVALID_HANDLE)
   {
      FileWrite(allCandlesFileHandle,
         TimeToString(current_candle_time, TIME_DATE|TIME_MINUTES),
         DoubleToString(candle_open, _Digits), DoubleToString(candle_high, _Digits), DoubleToString(candle_low, _Digits), DoubleToString(candle_close, _Digits));
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