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
input double   InpLotSize           = 0.01; // lot size for trade types
input int      HourForDailySummary   = 21;   // hour (server time) when daily summary is written (timer/server time)
input int      MinuteForDailySummary = 30;   // minute of the hour for summary trigger
input bool     InpTestingPullM1History = true;  // if true: at 21:58-22:00 write (date)_testing_pullinghistory.csv and testinglevelsplus files
input string   InpCalendarFile        = "calendar_2026_dots.csv";  // CSV in Terminal/Common/Files: date (YYYY.MM.DD),dayofmonth,dayofweek,opex,qopex
input string   InpLevelsFile          = "levelsinfo_zeFinal.csv";  // CSV in Terminal/Common/Files: start,end,levelPrice,categories,tag
input double   InpBreakCheckMaxDistPoints = 9.0;  // levels_breakCheck: first candle beyond this distance in price (and all newer) excluded

//--- Trade definition: buy_2nd_bounce (parameters only; entry rule below, no execution yet)
//    Type: buy_limit. Open price = level + PriceOffsetPips. TP/SL in pips. Expiration used for manual cancel logic.
input double   T_buy2ndBounce_LotSize           = 0.05;
input double   T_buy2ndBounce_PriceOffsetPips  = 7.0;   // desired open price = level + this many pips
input double   T_buy2ndBounce_TPPips           = 80.0;  // TP = order price + this many pips (e.g. 80 for 8 pts on US500 point=0.1)
input double   T_buy2ndBounce_SLPips           = 80.0;   // SL = order price - this many pips (e.g. 80 for 8 pts on US500 point=0.1)
// Entry rule to open: level.bounceCount == 1 && bias_long (dailyBias > 0) && no_contact (!in_contact)
input string   T_tradeType1_BannedRanges = "0,0,0,59;15,15,16,35;21,28,23,59";  // startH,startM,endH,endM;...
//--- Trade definition: buy_4th_bounce (parameters only; entry rule below, no execution yet)
//    Type: buy_limit. Open price = level + PriceOffsetPips. TP/SL in pips. Expiration used for manual cancel logic.
input double   T_buy4thBounce_LotSize           = 0.1;
input double   T_buy4thBounce_PriceOffsetPips  = 5.0;   // desired open price = level + this many pips
input double   T_buy4thBounce_TPPips           = 60.0;  // TP = order price + this many pips (e.g. 60 for 6 pts on US500 point=0.1)
input double   T_buy4thBounce_SLPips           = 20.0;   // SL = order price - this many pips (e.g. 20 for 2 pts on US500 point=0.1)
// Entry rule to open: level.bounceCount == 3 && bias_long (dailyBias > 0) && no_contact (!in_contact)
input string   T_tradeType2_BannedRanges = "15,15,16,35";  // startH,startM,endH,endM;...
//--- Trade type 3: market_test (no level; magic has no level component)
//    Flow B: trigger as soon as bar closed. Place buy at trigger minute; close at close minute. No bar-end time.
//    useLevel=false, usePrice=false, useTimeFilter=true + banned ranges input.
input double   T_tradeType3_LotSize   = 0.01;
input int      T_tradeType3_TPPoints = 9000;  // TP/SL distance in points (not pips)
input int      T_tradeType3_SLPoints = 9000;
input string   T_tradeType3_BannedRanges = "0,0,2,59;20,0,23,59";  // startH,startM,endH,endM per range; ";" separated

//--- Trade type config: useLevel/usePrice/useTimeFilter indicate what trade cares about; bannedRangesStr from input.
struct TradeTypeConfig
{
   bool   useLevel;        // false = trade does not use level (e.g. type 3)
   bool   usePrice;        // false = no price/level distance check (e.g. type 3)
   bool   useTimeFilter;   // true = apply banned ranges; false = no time filter or fixed time only
   string bannedRangesStr; // "startH,startM,endH,endM;..." e.g. "0,0,2,59;20,0,23,59"
};
TradeTypeConfig g_tradeConfig[5];   // index by TRADE_TYPE_ID 1..4
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

//--- Trade type support
const long EA_MAGIC = 47001; // unique magic for this EA's orders

// Trade type IDs
enum TRADE_TYPE_ID
{
   TRADE_TYPE_BUY_2ND_BOUNCE = 1,
   TRADE_TYPE_BUY_4TH_BOUNCE = 2,
   TRADE_TYPE_MARKET_TEST   = 3   // trigger at bar close: place buy then close later; no level in magic
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
   MqlDateTime mt;
   TimeToStruct(candleTime, mt);
   int hour = mt.hour;
   int minute = mt.min;
   
   // Convert to minutes since midnight for easier comparison
   int currentMinutes = hour * 60 + minute;
   
   // Check if current time falls within any banned range
   for(int i = 0; i < rangeCount; i++)
   {
      int startHour = bannedRanges[i][0];
      int startMinute = bannedRanges[i][1];
      int endHour = bannedRanges[i][2];
      int endMinute = bannedRanges[i][3];
      
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
   int fh = FileOpen(InpCalendarFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
   {
      FatalError("Calendar file could not be opened: " + InpCalendarFile + " (place CSV in Terminal/Common/Files)");
      return false;
   }
   string line = FileReadString(fh);  // skip header
   while(!FileIsEnding(fh) && g_calendarCount < MAX_CALENDAR_ROWS)
   {
      line = FileReadString(fh);
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
   FileClose(fh);
   return (g_calendarCount > 0);
}

//+------------------------------------------------------------------+
//| Return dayofweek string for the given date from loaded calendar, or "" if not found. |
//+------------------------------------------------------------------+
string GetCalendarDayOfWeek(datetime dt)
{
   string key = TimeToString(dt, TIME_DATE);  // YYYY.MM.DD to match calendar
   for(int i = 0; i < g_calendarCount; i++)
      if(g_calendar[i].dateStr == key) return g_calendar[i].dayofweek;
   return "";
}

//+------------------------------------------------------------------+
//| Session for candle time: before 15:30 ON, 15:30-22:00 RTH, else sleep. |
//+------------------------------------------------------------------+
string GetSessionForCandleTime(datetime t)
{
   MqlDateTime mt;
   TimeToStruct(t, mt);
   int minOfDay = mt.hour * 60 + mt.min;
   if(minOfDay < 15*60+30) return "ON";   // before 15:30
   if(minOfDay <= 22*60+0) return "RTH"; // 15:30 to 22:00
   return "sleep";
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
   for(int k = 0; k < g_barsInDay; k++)
      if(g_m1Rates[k].time == targetTime)
         return g_m1Rates[k].open;
   FatalError("GetRTHopenCurrentDay: 15:30 candle not found for " + TimeToString(g_m1DayStart, TIME_DATE));
   return 0.0;  // unreachable
}

//+------------------------------------------------------------------+
//| True if bar time (open time) is in RTHIB window: 15:30 to 16:30 inclusive. |
//+------------------------------------------------------------------+
bool IsBarRTHIB(datetime barTime)
{
   MqlDateTime mt;
   TimeToStruct(barTime, mt);
   int minOfDay = mt.hour * 60 + mt.min;
   return (minOfDay >= 15*60+30 && minOfDay <= 16*60+30);
}

//+------------------------------------------------------------------+
//| True if bar time (open time) is in RTHcnt window: 16:31 onward. |
//+------------------------------------------------------------------+
bool IsBarRTHcnt(datetime barTime)
{
   MqlDateTime mt;
   TimeToStruct(barTime, mt);
   int minOfDay = mt.hour * 60 + mt.min;
   return (minOfDay >= 16*60+31);
}

//+------------------------------------------------------------------+
//| Median of first n elements of arr[]. Resizes arr to n and sorts in place. Returns 0 if n<=0. |
//+------------------------------------------------------------------+
double GetMedianDoubleArray(double &arr[], int n)
{
   if(n <= 0) return 0.0;
   ArrayResize(arr, n);
   ArraySort(arr);
   if(n % 2 == 1) return arr[n/2];
   return (arr[n/2 - 1] + arr[n/2]) / 2.0;
}

//+------------------------------------------------------------------+
//| Session type for break-down stats (first close above level, then distances). |
//+------------------------------------------------------------------+
enum BREAKCHECK_SESSION { BREAKCHECK_ON, BREAKCHECK_RTHIB, BREAKCHECK_RTHCNT };

struct BreakCheckSessionResult
{
   int    firstCloseAbove;
   int    n;
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
   BreakCheckSessionResult r;
   r.firstCloseAbove = g_barsInDay;
   r.n = 0;
   r.avg = 0.0;
   r.median = 0.0;
   r.rangeStartStr = "";

   for(int k = 0; k < g_barsInDay; k++)
   {
      if(!BarInSession(k, sessionType)) continue;
      if(g_m1Rates[k].close > lvl) { r.firstCloseAbove = k; break; }
   }

   double values[];
   ArrayResize(values, g_barsInDay);
   double sum = 0.0;
   for(int k = r.firstCloseAbove; k < g_barsInDay; k++)
   {
      if(!BarInSession(k, sessionType)) continue;
      if(g_m1Rates[k].low >= lvl) continue;
      double d = lvl - g_m1Rates[k].low;
      if(d > maxDist) break;
      if(d <= maxDist) { values[r.n++] = d; sum += d; }
   }
   r.avg    = (r.n > 0) ? sum / (double)r.n : 0.0;
   r.median = GetMedianDoubleArray(values, r.n);
   r.rangeStartStr = (r.firstCloseAbove < g_barsInDay) ? TimeToString(g_m1Rates[r.firstCloseAbove].time, TIME_DATE|TIME_MINUTES) : "";

   return r;
}

//+------------------------------------------------------------------+
//| Session high/low over g_barsInDay for bars where g_session[k] == sessionName. Sets outHigh/outLow (undefined if !hasAny). |
//+------------------------------------------------------------------+
void GetSessionHighLow(const string sessionName, double &outHigh, double &outLow, bool &hasAny)
{
   outHigh = -1e300;
   outLow  = 1e300;
   hasAny  = false;
   for(int k = 0; k < g_barsInDay; k++)
   {
      if(g_session[k] != sessionName) continue;
      hasAny = true;
      if(g_m1Rates[k].high > outHigh) outHigh = g_m1Rates[k].high;
      if(g_m1Rates[k].low  < outLow)  outLow  = g_m1Rates[k].low;
   }
}

//+------------------------------------------------------------------+
//| Return previous trading day date string (YYYY.MM.DD) from calendar: go back 1 day, skip Saturday/Sunday. "" if not found. |
//+------------------------------------------------------------------+
string GetPreviousTradingDayDateString(datetime dayStart)
{
   string key = TimeToString(dayStart, TIME_DATE);  // YYYY.MM.DD to match calendar
   int i = -1;
   for(int j = 0; j < g_calendarCount; j++)
      if(g_calendar[j].dateStr == key) { i = j; break; }
   if(i <= 0) return "";
   int j = i - 1;
   while(j >= 0 && (g_calendar[j].dayofweek == "Saturday" || g_calendar[j].dayofweek == "Sunday"))
      j--;
   if(j < 0) return "";
   return g_calendar[j].dateStr;
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
   int y = (int)StringToInteger(parts[0]);
   int mo = (int)StringToInteger(parts[1]);
   int d = (int)StringToInteger(parts[2]);
   MqlDateTime mtPrev = {0};
   mtPrev.year = y; mtPrev.mon = mo; mtPrev.day = d;
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
   for(int s = shiftDayEnd; s <= shiftDayStart; s++)
   {
      double h = iHigh(_Symbol, PERIOD_M30, s);
      double l = iLow(_Symbol, PERIOD_M30, s);
      if(h > pdh) pdh = h;
      if(l < pdl) pdl = l;
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
   int fh = FileOpen(InpLevelsFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
   {
      FatalError("Levels file could not be opened: " + InpLevelsFile + " (place CSV in Terminal/Common/Files)");
      return false;
   }
   string line = FileReadString(fh);  // skip header
   while(!FileIsEnding(fh) && g_levelsTotalCount < MAX_LEVEL_ROWS)
   {
      line = FileReadString(fh);
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
   FileClose(fh);
   return (g_levelsTotalCount > 0);
}

//+------------------------------------------------------------------+
//| Get newway_Diff_CloseToLevel from g_levelsExpanded at barTime. Key = levelPrice OR tag (use one, pass 0 or "" for the other). |
//+------------------------------------------------------------------+
double GetLevelExpandedDiff(double levelPrice, string tag, datetime barTime)
{
   for(int e = 0; e < g_levelsTodayCount; e++)
   {
      if(levelPrice > 0 && g_levelsExpanded[e].levelPrice != levelPrice) continue;
      if(StringLen(tag) > 0 && g_levelsExpanded[e].tag != tag) continue;
      for(int k = 0; k < g_levelsExpanded[e].count; k++)
         if(g_levelsExpanded[e].times[k] == barTime)
            return g_levelsExpanded[e].diffs[k];
      return 0;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| In last windowBars ending at bar k: Up = max(high-level) when high>level; Down = max(level-low) when low<level. |
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
      for(int j = startBar; j <= barK; j++)
      {
         if(g_m1Rates[j].high > levelPrice)
         {
            double d = g_m1Rates[j].high - levelPrice;
            if(!result.hasValue || d > result.value)
            {
               result.hasValue = true;
               result.value = d;
            }
         }
      }
   }
   else
   {
      for(int j = startBar; j <= barK; j++)
      {
         if(g_m1Rates[j].low < levelPrice)
         {
            double d = levelPrice - g_m1Rates[j].low;
            if(!result.hasValue || d > result.value)
            {
               result.hasValue = true;
               result.value = d;
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
   for(int j = barIndex - 1; j >= 0; j--)
   {
      bool clean = above
         ? (g_m1Rates[j].open > level && g_m1Rates[j].high > level && g_m1Rates[j].low > level && g_m1Rates[j].close > level)
         : (g_m1Rates[j].open < level && g_m1Rates[j].high < level && g_m1Rates[j].low < level && g_m1Rates[j].close < level);
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
   int cnt = 0;
   for(int j = fromBar; j <= toBar; j++)
   {
      bool clean = above
         ? (g_m1Rates[j].open > level && g_m1Rates[j].high > level && g_m1Rates[j].low > level && g_m1Rates[j].close > level)
         : (g_m1Rates[j].open < level && g_m1Rates[j].high < level && g_m1Rates[j].low < level && g_m1Rates[j].close < level);
      if(clean) cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
//| Count consecutive bars (barIndex-1, barIndex-2, ...) with level between bar H and L (low <= level <= high). |
//+------------------------------------------------------------------+
int GetOverlapStreakForLevel(double level, int barIndex)
{
   int streak = 0;
   for(int j = barIndex - 1; j >= 0; j--)
   {
      if(g_m1Rates[j].low <= level && level <= g_m1Rates[j].high)
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
   int cnt = 0;
   for(int j = fromBar; j <= toBar; j++)
      if(g_m1Rates[j].low <= level && level <= g_m1Rates[j].high) cnt++;
   return cnt;
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
   for(int b = 0; b < copied; b++)
      if(TimeToString(m1Rates[b].time, TIME_DATE) == dateStr) barsInDay++;

   if(barsInDay <= 0 || barsInDay > MAX_BARS_IN_DAY) { g_barsInDay = 0; g_m1DayStart = 0; return; }

   int idxDay = 0;
   for(int b = 0; b < copied && idxDay < barsInDay; b++)
   {
      if(TimeToString(m1Rates[b].time, TIME_DATE) != dateStr) continue;
      g_m1Rates[idxDay] = m1Rates[b];
      idxDay++;
   }
   g_barsInDay = barsInDay;
   g_m1DayStart = dayStart;

   // Ensure todayRTHopen is in g_levels when we have the 15:30 bar (data-driven; no reliance on new-bar event timing)
   {
      double open1530 = 0;
      for(int k = 0; k < g_barsInDay; k++)
      {
         MqlDateTime mt;
         TimeToStruct(g_m1Rates[k].time, mt);
         if(mt.hour == 15 && mt.min == 30)
            { open1530 = g_m1Rates[k].open; break; }
      }
      if(open1530 != 0)
      {
         string todayStr = dateStr;
         bool alreadyAdded = false;
         for(int i = 0; i < g_levelsTotalCount; i++)
            if(g_levels[i].tag == "todayRTHopen" && g_levels[i].startStr == todayStr && g_levels[i].endStr == todayStr)
            { alreadyAdded = true; break; }
         bool tooClose = false;
         if(!alreadyAdded)
            for(int i = 0; i < g_levelsTotalCount; i++)
               if(g_levels[i].startStr <= todayStr && todayStr <= g_levels[i].endStr &&
                  MathAbs(g_levels[i].levelPrice - open1530) < tertiaryLevel_tooTight_toAdd_proximity)
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

   // Build levelsExpanded from g_levels (full-day bars; todayRTHopen is in g_levels like any other level)
   g_levelsTodayCount = 0;
   for(int i = 0; i < g_levelsTotalCount && g_levelsTodayCount < MAX_LEVELS_EXPANDED; i++)
   {
      if(g_levels[i].startStr > dayKey || dayKey > g_levels[i].endStr) continue;
      g_levelsExpanded[g_levelsTodayCount].levelPrice = g_levels[i].levelPrice;
      g_levelsExpanded[g_levelsTodayCount].tag        = g_levels[i].tag;
      g_levelsExpanded[g_levelsTodayCount].categories = g_levels[i].categories;
      g_levelsExpanded[g_levelsTodayCount].count      = g_barsInDay;
      ArrayResize(g_levelsExpanded[g_levelsTodayCount].diffs, g_barsInDay);
      ArrayResize(g_levelsExpanded[g_levelsTodayCount].times, g_barsInDay);
      for(int k = 0; k < g_barsInDay; k++)
      {
         g_levelsExpanded[g_levelsTodayCount].times[k] = g_m1Rates[k].time;
         g_levelsExpanded[g_levelsTodayCount].diffs[k] = g_m1Rates[k].close - g_levelsExpanded[g_levelsTodayCount].levelPrice;
      }
      g_levelsTodayCount++;
   }

   // Per (level e, bar k): breaksLevelDown / breaksLevelUpward from candle open/close vs level
   for(int e = 0; e < g_levelsTodayCount; e++)
      for(int k = 0; k < g_levelsExpanded[e].count; k++)
      {
         double lp = g_levelsExpanded[e].levelPrice;
         g_breaksLevelDown[e][k]   = (g_m1Rates[k].open > lp && g_m1Rates[k].close < lp);
         g_breaksLevelUpward[e][k] = (g_m1Rates[k].open < lp && g_m1Rates[k].close > lp);
      }

   // Per (level e, bar k): all level-bar stats in one forward pass (streaks and counts incremental to avoid O(bars^2))
   for(int e = 0; e < g_levelsTodayCount; e++)
   {
      double lp = g_levelsExpanded[e].levelPrice;
      int cnt = g_levelsExpanded[e].count;
      int prevAbove = 0, prevBelow = 0, prevOverlap = 0;  // bar k-1 state
      int runAbove = 0, runBelow = 0, runOverlap = 0;     // running streaks
      int sumAbove = 0, sumBelow = 0, sumOverlap = 0;     // running counts 0..k
      for(int k = 0; k < cnt; k++)
      {
         double o = g_m1Rates[k].open, h = g_m1Rates[k].high, l_ = g_m1Rates[k].low, c = g_m1Rates[k].close;
         int curAbove  = IsBarCleanAbove(o, h, l_, c, lp) ? 1 : 0;
         int curBelow  = IsBarCleanBelow(o, h, l_, c, lp) ? 1 : 0;
         int curOverlap = IsBarOverlap(l_, h, lp) ? 1 : 0;

         g_cleanStreakAbove[e][k] = (k == 0) ? 0 : (prevAbove ? 1 + runAbove : 0);
         g_cleanStreakBelow[e][k] = (k == 0) ? 0 : (prevBelow ? 1 + runBelow : 0);
         g_overlapStreak[e][k]    = (k == 0) ? 0 : (prevOverlap ? 1 + runOverlap : 0);

         sumAbove += curAbove; sumBelow += curBelow; sumOverlap += curOverlap;
         g_aboveCnt[e][k] = sumAbove;
         g_belowCnt[e][k] = sumBelow;
         g_overlapC[e][k] = sumOverlap;

         int totalSoFar = k + 1;
         g_abovePerc[e][k] = (totalSoFar > 0) ? (100.0 * sumAbove / totalSoFar) : 0.0;
         g_belowPerc[e][k] = (totalSoFar > 0) ? (100.0 * sumBelow / totalSoFar) : 0.0;
         g_overlapPc[e][k] = (totalSoFar > 0) ? (100.0 * sumOverlap / totalSoFar) : 0.0;

         runAbove   = curAbove  ? 1 + runAbove   : 0;
         runBelow   = curBelow  ? 1 + runBelow   : 0;
         runOverlap = curOverlap ? 1 + runOverlap : 0;
         prevAbove = curAbove; prevBelow = curBelow; prevOverlap = curOverlap;
      }
   }

   // Per-bar: level above candle high, level below candle low, session (available globally; logged in 21:59-22:00)
   for(int k = 0; k < g_barsInDay; k++)
   {
      double aboveH = 0;
      double belowL = 0;
      for(int e = 0; e < g_levelsTodayCount; e++)
      {
         double lp = g_levelsExpanded[e].levelPrice;
         if(lp > g_m1Rates[k].high && (aboveH == 0 || lp < aboveH)) aboveH = lp;
         if(lp < g_m1Rates[k].low  && (belowL == 0 || lp > belowL)) belowL = lp;
      }
      g_levelAboveH[k] = aboveH;
      g_levelBelowL[k] = belowL;
      g_session[k] = GetSessionForCandleTime(g_m1Rates[k].time);
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
   string s = bothComments;
   StringReplace(s, "$", "");
   return StringSplit(s, ' ', result);
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
   for(int i = 0; i < total && g_dealCount < MAX_DEALS_DAY; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
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
   for(int i = 0; i < g_dealCount; i++) g_dealOrder[i] = i;
   for(int i = 0; i < g_dealCount - 1; i++)
      for(int j = i + 1; j < g_dealCount; j++)
      {
         int a = g_dealOrder[i], b = g_dealOrder[j];
         if(g_dealMagic[a] > g_dealMagic[b] || (g_dealMagic[a] == g_dealMagic[b] && g_dealTime[a] > g_dealTime[b]))
         { int tmp = g_dealOrder[i]; g_dealOrder[i] = g_dealOrder[j]; g_dealOrder[j] = tmp; }
      }
   // Group by magic, pair IN with next OUT
   int i = 0;
   while(i < g_dealCount && g_tradeResultsCount < MAX_TRADE_RESULTS)
   {
      long mag = g_dealMagic[g_dealOrder[i]];
      int inCount = 0, outCount = 0;
      while(i < g_dealCount && g_dealMagic[g_dealOrder[i]] == mag)
      {
         int idx = g_dealOrder[i];
         if(g_dealEntry[idx] == (int)DEAL_ENTRY_IN)  { if(inCount < MAX_IN_OUT_PER_MAGIC) g_inIdx[inCount++] = idx; }
         else if(g_dealEntry[idx] == (int)DEAL_ENTRY_OUT) { if(outCount < MAX_IN_OUT_PER_MAGIC) g_outIdx[outCount++] = idx; }
         i++;
      }
      for(int p = 0; p < inCount && g_tradeResultsCount < MAX_TRADE_RESULTS; p++)
      {
         TradeResult r;
         r.symbol      = g_dealSymbol[g_inIdx[p]];
         r.startTime   = g_dealTime[g_inIdx[p]];
         r.magic       = g_dealMagic[g_inIdx[p]];
         r.priceStart  = g_dealPrice[g_inIdx[p]];
         r.type       = g_dealType[g_inIdx[p]];
         r.volume     = g_dealVolume[g_inIdx[p]];
         r.foundOut   = (p < outCount);
         r.session    = GetSessionForCandleTime(r.startTime);
         if(r.foundOut)
         {
            int o = g_outIdx[p];
            r.endTime   = g_dealTime[o];
            r.priceEnd  = g_dealPrice[o];
            if(r.type == (long)DEAL_TYPE_BUY)
               r.priceDiff = r.priceEnd - r.priceStart;
            else
               r.priceDiff = r.priceStart - r.priceEnd;   // DEAL_TYPE_SELL
            r.profit    = g_dealProfit[o];
            r.reason    = g_dealReason[o];
            string commentsStr = BuildBothComments(g_dealComment[g_inIdx[p]], g_dealComment[o], true);
            r.bothComments = commentsStr;
            if(StringFind(commentsStr, "$") < 0)
               r.level = r.tp = r.sl = "";
            else
            {
               string arr[];
               ChangeBothCommentsToArrayOfStrings(commentsStr, arr);
               r.level = (ArraySize(arr) > 0) ? arr[0] : "";
               r.tp    = (ArraySize(arr) > 1) ? arr[1] : "";
               r.sl    = (ArraySize(arr) > 2) ? arr[2] : "";
            }
         }
         else
         {
            r.endTime   = 0;
            r.priceEnd  = 0;
            r.priceDiff = 0;
            r.profit    = 0;
            r.reason    = 0;
            string commentsStr = BuildBothComments(g_dealComment[g_inIdx[p]], "", false);
            r.bothComments = commentsStr;
            if(StringFind(commentsStr, "$") < 0)
               r.level = r.tp = r.sl = "";
            else
            {
               string arr[];
               ChangeBothCommentsToArrayOfStrings(commentsStr, arr);
               r.level = (ArraySize(arr) > 0) ? arr[0] : "";
               r.tp    = (ArraySize(arr) > 1) ? arr[1] : "";
               r.sl    = (ArraySize(arr) > 2) ? arr[2] : "";
            }
         }
         g_tradeResults[g_tradeResultsCount++] = r;
      }
   }
}

//+------------------------------------------------------------------+
//| For each bar k, set g_dayProgress[k] from trades with endTime < candle k close time (so close at 16:45:00 counts for 16:45 bar, not 16:44). |
//+------------------------------------------------------------------+
void UpdateDayProgress()
{
   for(int k = 0; k < g_barsInDay; k++)
   {
      datetime candleCloseTime = (k + 1 < g_barsInDay) ? g_m1Rates[k + 1].time : (g_m1Rates[k].time + 60);
      int wins = 0, total = 0;
      double dayPointsSum = 0, dayProfitSum = 0;
      int ONwins = 0, ONtotal = 0;
      double ONpointsSum = 0, ONprofitSum = 0;
      int RTHwins = 0, RTHtotal = 0;
      double RTHpointsSum = 0, RTHprofitSum = 0;
      for(int tr = 0; tr < g_tradeResultsCount; tr++)
      {
         TradeResult r = g_tradeResults[tr];
         if(!r.foundOut) continue;
         if(r.endTime >= candleCloseTime) continue;
         total++;
         if(r.profit > 0) wins++;
         dayPointsSum += r.priceDiff;
         dayProfitSum += r.profit;
         string endSession = GetSessionForCandleTime(r.endTime);
         if(endSession == "ON")
         {
            ONtotal++;
            if(r.profit > 0) ONwins++;
            ONpointsSum += r.priceDiff;
            ONprofitSum += r.profit;
         }
         else if(endSession == "RTH")
         {
            RTHtotal++;
            if(r.profit > 0) RTHwins++;
            RTHpointsSum += r.priceDiff;
            RTHprofitSum += r.profit;
         }
      }
      g_dayProgress[k].dayWinRate   = (total > 0) ? (double)wins / (double)total : 0.0;
      g_dayProgress[k].dayTradesCount = total;
      g_dayProgress[k].dayPointsSum = dayPointsSum;
      g_dayProgress[k].dayProfitSum = dayProfitSum;
      g_dayProgress[k].ONwinRate   = (ONtotal > 0) ? (double)ONwins / (double)ONtotal : 0.0;
      g_dayProgress[k].ONtradeCount = ONtotal;
      g_dayProgress[k].ONpointsSum = ONpointsSum;
      g_dayProgress[k].ONprofitSum = ONprofitSum;
      g_dayProgress[k].RTHwinRate   = (RTHtotal > 0) ? (double)RTHwins / (double)RTHtotal : 0.0;
      g_dayProgress[k].RTHtradeCount = RTHtotal;
      g_dayProgress[k].RTHpointsSum = RTHpointsSum;
      g_dayProgress[k].RTHprofitSum = RTHprofitSum;
   }
}

//+------------------------------------------------------------------+
//| Per (level e, bar k): aggregate trades whose level matches levelPrice and endTime < bar k close. Same frequency as trade results. |
//+------------------------------------------------------------------+
void UpdateLevelTradeStats()
{
   double tol = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 1e-6);
   for(int e = 0; e < g_levelsTodayCount; e++)
   {
      int cnt = g_levelsExpanded[e].count;
      for(int k = 0; k < cnt; k++)
      {
         g_ONtradeCount_L[e][k] = 0;
         g_ONwins_L[e][k] = 0;
         g_ONpointsSum_L[e][k] = 0.0;
         g_ONprofitSum_L[e][k] = 0.0;
         g_RTHtradeCount_L[e][k] = 0;
         g_RTHwins_L[e][k] = 0;
         g_RTHpointsSum_L[e][k] = 0.0;
         g_RTHprofitSum_L[e][k] = 0.0;
      }
   }
   for(int tr = 0; tr < g_tradeResultsCount; tr++)
   {
      TradeResult r = g_tradeResults[tr];
      if(StringLen(r.level) == 0 || !r.foundOut) continue;
      double lv = StringToDouble(r.level);
      int e = -1;
      for(int i = 0; i < g_levelsTodayCount; i++)
      {
         if(MathAbs(g_levelsExpanded[i].levelPrice - lv) < tol) { e = i; break; }
      }
      if(e < 0) continue;
      string endSession = GetSessionForCandleTime(r.endTime);
      int cnt = g_levelsExpanded[e].count;
      for(int k = 0; k < cnt; k++)
      {
         datetime candleCloseTime = (k + 1 < cnt) ? g_levelsExpanded[e].times[k + 1] : (g_levelsExpanded[e].times[k] + 60);
         if(r.endTime >= candleCloseTime) continue;
         if(endSession == "ON")
         {
            g_ONtradeCount_L[e][k]++;
            if(r.profit > 0) g_ONwins_L[e][k]++;
            g_ONpointsSum_L[e][k] += r.priceDiff;
            g_ONprofitSum_L[e][k] += r.profit;
         }
         else if(endSession == "RTH")
         {
            g_RTHtradeCount_L[e][k]++;
            if(r.profit > 0) g_RTHwins_L[e][k]++;
            g_RTHpointsSum_L[e][k] += r.priceDiff;
            g_RTHprofitSum_L[e][k] += r.profit;
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
   int n = StringSplit(s, ';', parts);
   if(n <= 0) return;
   for(int i = 0; i < n && g_bannedRangesCount < MAX_BANNED_RANGES; i++)
   {
      string nums[];
      if(StringSplit(parts[i], ',', nums) != 4) continue;
      ArrayResize(g_bannedRangesBuffer, g_bannedRangesCount + 1);
      g_bannedRangesBuffer[g_bannedRangesCount][0] = (int)StringToInteger(nums[0]);
      g_bannedRangesBuffer[g_bannedRangesCount][1] = (int)StringToInteger(nums[1]);
      g_bannedRangesBuffer[g_bannedRangesCount][2] = (int)StringToInteger(nums[2]);
      g_bannedRangesBuffer[g_bannedRangesCount][3] = (int)StringToInteger(nums[3]);
      g_bannedRangesCount++;
   }
}

//+------------------------------------------------------------------+
//| Build magic number for a trade. Trade uses date, price, tags, and trade type. |
//| Level and magic are unrelated; level is not used here.            |
//+------------------------------------------------------------------+
long BuildTradeMagic(datetime validFrom, double price, string tagsCSV, TRADE_TYPE_ID tradeTypeId)
{
   MqlDateTime dt;
   TimeToStruct(validFrom, dt);
   
   string dateStr = IntegerToString(dt.year) + 
                    StringFormat("%02d", dt.mon) + 
                    StringFormat("%02d", dt.day);
   
   string levelPriceStr = DoubleToString(price, 0);
   StringReplace(levelPriceStr, ".", "");
   
   int dayOfWeek = 0;
   if(StringFind(tagsCSV, "daily") != -1)
   {
      int mt5Day = dt.day_of_week;
      if(mt5Day == 0) mt5Day = 7;
      dayOfWeek = mt5Day - 1;
   }
   
   string magicStr = StringFormat("%d%s%s%d", tradeTypeId, dateStr, levelPriceStr, dayOfWeek);
   return (long)StringToInteger(magicStr);
}

//+------------------------------------------------------------------+
//| Build magic for trade type 3 (market_test). No level; date only (id 3 + YYYYMMDD). |
//+------------------------------------------------------------------+
long BuildMagicForTradeType3(datetime timer1Time)
{
   MqlDateTime dt;
   TimeToStruct(timer1Time, dt);
   string dateStr = IntegerToString(dt.year) +
                    StringFormat("%02d", dt.mon) +
                    StringFormat("%02d", dt.day);
   string magicStr = StringFormat("%d%s", (int)TRADE_TYPE_MARKET_TEST, dateStr);
   return (long)StringToInteger(magicStr);
}

//+------------------------------------------------------------------+
//| Build levels[] from g_levels[] (CSV). One Level per row; baseName = start_tag, validFrom/To from start/end. |
//+------------------------------------------------------------------+
void BuildLevelsFromCSV()
{
   ArrayResize(levels, g_levelsTotalCount);
   for(int i = 0; i < g_levelsTotalCount; i++)
   {
      levels[i].baseName  = g_levels[i].startStr + "_" + g_levels[i].tag;
      levels[i].price     = g_levels[i].levelPrice;
      levels[i].validFrom = StringToTime(g_levels[i].startStr + " 00:00");
      levels[i].validTo   = StringToTime(g_levels[i].endStr + " 23:59");
      levels[i].tagsCSV   = g_levels[i].categories;
      levels[i].count     = 0;
      levels[i].approxContactCount = 0;
      levels[i].dailyBias = 0;
      levels[i].biasSetToday = false;
      levels[i].lastBiasDate = 0;
      levels[i].logRawEv_fileHandle = INVALID_HANDLE;
      levels[i].candlesBreakLevelCount = 0;
      levels[i].recoverCount = 0;
      levels[i].bounceCount = 0;
      levels[i].consecutiveRecoverCandles = 0;
      levels[i].lastCandleInContact = false;
      levels[i].candlesPassedSinceLastBounce = 0;
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
   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(d == 3 || d == 5) return SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0;
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
//| Open file for append (try existing first, else create). Returns handle or INVALID_HANDLE. |
//+------------------------------------------------------------------+
int OpenOrCreateForAppend(string path)
{
   int h = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_READ);
   if(h != INVALID_HANDLE)
      FileSeek(h, 0, SEEK_END);
   else
      h = FileOpen(path, FILE_WRITE | FILE_TXT);
   return h;
}

//+------------------------------------------------------------------+
//| Count open positions + pending orders with this exact magic (trading: limit per magic, not per level) |
//+------------------------------------------------------------------+
int CountOrdersAndPositionsForMagic(long magic)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!ExtPositionInfo.SelectByIndex(i)) continue;
      if(ExtPositionInfo.Symbol() != _Symbol) continue;
      if(ExtPositionInfo.Magic() == magic) count++;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ExtOrderInfo.SelectByIndex(i)) continue;
      if(ExtOrderInfo.Symbol() != _Symbol) continue;
      if(ExtOrderInfo.Magic() == magic) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Extract trade type ID from magic number (first digit).           |
//| Magic is long; never cast to int (overflow). Use long for string. |
//+------------------------------------------------------------------+
int GetTradeTypeIdFromMagic(long magicNumber)
{
   string magicStr = IntegerToString((long)magicNumber);
   if(StringLen(magicStr) > 0)
      return (int)StringToInteger(StringSubstr(magicStr, 0, 1));
   return 0;
}

//+------------------------------------------------------------------+
//| B_TradeLog filename = B_TradeLog_(id). e.g. 2026.03.03_B_TradeLog_3.csv |
//+------------------------------------------------------------------+
string GetTradeTypeStringFromId(int tradeTypeId)
{
   if(tradeTypeId <= 0) return "";
   return IntegerToString(tradeTypeId);
}

//+------------------------------------------------------------------+
//| Trade type string from magic; returns "" if unknown (use StringLen==0 to check). |
//+------------------------------------------------------------------+
string GetTradeTypeFromMagic(long magic)
{
   int id = GetTradeTypeIdFromMagic(magic);
   return (id > 0) ? GetTradeTypeStringFromId(id) : "";
}

//+------------------------------------------------------------------+
//| Build B_TradeLog filename by trade type only                     |
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
   double eq      = AccountInfoDouble(ACCOUNT_EQUITY);
   // additional metrics (free margin, margin level, etc.) can be added if needed
   return StringFormat("(pos=%d pending=%d histOrd=%d histDeals=%d bal=%.2f eq=%.2f)",
                       posCount, ordCount, histOrders, histDeals, bal, eq);
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
   int fh1 = FileOpen(activeLevelsFile, FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(fh1 == INVALID_HANDLE)
      FatalError("WriteDailySummary: could not open " + activeLevelsFile);
   {
      FileWrite(fh1, "levelNo", "name", "price", "count", "contacts", "bias", "bounces");
      datetime today = now - (now % 86400);
      for(int i=0; i<ArraySize(levels); i++)
      {
         if(levels[i].validFrom <= today && levels[i].validTo >= today)
         {
            FileWrite(fh1, IntegerToString(i), levels[i].baseName, DoubleToString(levels[i].price, _Digits),
                      IntegerToString(levels[i].count), IntegerToString(levels[i].approxContactCount),
                      DoubleToString(levels[i].dailyBias, 0), IntegerToString(levels[i].bounceCount));
         }
      }
      FileClose(fh1);
   }
   
   string accountFile = dateStr + "-Day_EOD_accountSummary.txt";
   int fh2 = FileOpen(accountFile, FILE_WRITE | FILE_TXT);
   if(fh2 == INVALID_HANDLE)
      FatalError("WriteDailySummary: could not open " + accountFile);
   {
      EODpulled_balance       = AccountInfoDouble(ACCOUNT_BALANCE);
      EODpulled_equity       = AccountInfoDouble(ACCOUNT_EQUITY);
      EODpulled_freeMargin  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      EODpulled_marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      EODpulled_openPositions = PositionsTotal();
      EODpulled_pendingOrders = OrdersTotal();
      FileWrite(fh2, "balance=" + DoubleToString(EODpulled_balance, 2));
      FileWrite(fh2, "equity=" + DoubleToString(EODpulled_equity, 2));
      FileWrite(fh2, "freeMargin=" + DoubleToString(EODpulled_freeMargin, 2));
      FileWrite(fh2, "marginLevel=" + DoubleToString(EODpulled_marginLevel, 1));
      FileWrite(fh2, "openPositions=" + IntegerToString(EODpulled_openPositions));
      FileWrite(fh2, "pendingOrders=" + IntegerToString(EODpulled_pendingOrders));
      FileClose(fh2);
   }
   
   string ordersFile = dateStr + "-not_from_globals_AllHistoryOrders.csv";
   int fh3 = FileOpen(ordersFile, FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(fh3 == INVALID_HANDLE)
      FatalError("WriteDailySummary: could not open " + ordersFile);
   {
      FileWrite(fh3, "ticket", "symbol", "magic", "timeSetup", "state", "type", "reason", "volume", "priceOpen", "priceCurrent", "priceStopLoss", "priceTakeProfit", "timeExpiration", "activationPrice", "comment");
      HistorySelect(0, g_lastTimer1Time);
      int totalHist = HistoryOrdersTotal();
      for(int i=0; i<totalHist; i++)
      {
         ulong ticket = HistoryOrderGetTicket(i);
         if(ticket == 0) continue;
         
         datetime orderTime = (datetime)HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP);
         if(orderTime < dateWhenAlgoTradeStarted) continue;
         
         FileWrite(fh3, IntegerToString((long)ticket), HistoryOrderGetString(ticket, ORDER_SYMBOL),
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
      FileClose(fh3);
   }
   
   string dealsFile = dateStr + "-not_from_globals_AllHistoryDeals.csv";
   int fh4 = FileOpen(dealsFile, FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(fh4 == INVALID_HANDLE)
      FatalError("WriteDailySummary: could not open " + dealsFile);
   {
      FileWrite(fh4, "ticket", "symbol", "magic", "time", "entry", "type", "reason", "volume", "price", "profit", "ticketOrder", "comment");
      int totalDeals = HistoryDealsTotal();
      for(int i=0; i<totalDeals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         
         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         if(dealTime < dateWhenAlgoTradeStarted) continue;
         
         FileWrite(fh4, IntegerToString((long)ticket), HistoryDealGetString(ticket, DEAL_SYMBOL),
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
      FileClose(fh4);
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
   string fname = BuildTradeLogFileName(tradeType, eventTime);
   if(StringLen(fname) == 0) return;

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   int fh = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(fh == INVALID_HANDLE)
      fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(fh == INVALID_HANDLE)
      FatalError("WriteTradeLog: could not open " + fname);
   FileSeek(fh, 0, SEEK_END);
   if(FileTell(fh) == 0)
      FileWrite(fh, "time", "balance", "equity", "orderKind", "orderPrice", "eventType", "tp", "sl", "exp", "orderTicket", "dealTicket", "positionTicket", "dealReason", "comment", "magic");
   FileWrite(fh, TimeToString(eventTime, TIME_DATE|TIME_SECONDS), DoubleToString(bal, 2), DoubleToString(eq, 2),
             orderKind, (orderPrice > 0 ? DoubleToString(NormalizeDouble(orderPrice, _Digits), _Digits) : ""), eventType,
             (tpPrice > 0 ? DoubleToString(NormalizeDouble(tpPrice, _Digits), _Digits) : ""), (slPrice > 0 ? DoubleToString(NormalizeDouble(slPrice, _Digits), _Digits) : ""),
             (expirationMinutes > 0 ? IntegerToString(expirationMinutes) : ""),
             (orderTicket > 0 ? IntegerToString((long)orderTicket) : ""), (dealTicket > 0 ? IntegerToString((long)dealTicket) : ""), (positionTicket > 0 ? IntegerToString((long)positionTicket) : ""),
             (dealReason != (ENUM_DEAL_REASON)0 ? IntegerToString((int)dealReason) : ""), comment, IntegerToString((long)magic));
   FileClose(fh);
}

//+------------------------------------------------------------------+
int OnInit()
{
   Print("Level Logger EA initialized.");
   ExtTrade.SetExpertMagicNumber(EA_MAGIC);

   // Trade type config: useLevel/usePrice/useTimeFilter indicate what each trade cares about (level, price, time)
   g_tradeConfig[TRADE_TYPE_BUY_2ND_BOUNCE].useLevel = true;
   g_tradeConfig[TRADE_TYPE_BUY_2ND_BOUNCE].usePrice = true;
   g_tradeConfig[TRADE_TYPE_BUY_2ND_BOUNCE].useTimeFilter = true;
   g_tradeConfig[TRADE_TYPE_BUY_2ND_BOUNCE].bannedRangesStr = T_tradeType1_BannedRanges;

   g_tradeConfig[TRADE_TYPE_BUY_4TH_BOUNCE].useLevel = true;
   g_tradeConfig[TRADE_TYPE_BUY_4TH_BOUNCE].usePrice = true;
   g_tradeConfig[TRADE_TYPE_BUY_4TH_BOUNCE].useTimeFilter = true;
   g_tradeConfig[TRADE_TYPE_BUY_4TH_BOUNCE].bannedRangesStr = T_tradeType2_BannedRanges;

   g_tradeConfig[TRADE_TYPE_MARKET_TEST].useLevel = false;
   g_tradeConfig[TRADE_TYPE_MARKET_TEST].usePrice = false;
   g_tradeConfig[TRADE_TYPE_MARKET_TEST].useTimeFilter = true;
   g_tradeConfig[TRADE_TYPE_MARKET_TEST].bannedRangesStr = T_tradeType3_BannedRanges;

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

   string tradeType = GetTradeTypeFromMagic(HistoryOrderGetInteger(trans.order, ORDER_MAGIC));
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

   string tradeType = GetTradeTypeFromMagic(HistoryDealGetInteger(trans.deal, DEAL_MAGIC));
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

   string tradeType = GetTradeTypeFromMagic(entryMagic);
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
   int fhDay = FileOpen(dayStatLogName, FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(fhDay != INVALID_HANDLE)
   {
      FileWrite(fhDay, "date", "hasGapDown", "hasGapUp", "RTHopen", "PD_RTH_Close", "gap_fill_pc", "gapDiff", "rthHigh", "rthLow", "ONH", "ONL", "ONH_t_RTH", "ONL_t_RTH", "ONboth_t_RTH");
      FileWrite(fhDay, dateStrStat, (dayStat_day_had_OpenGapDown_bool ? "true" : "false"), (dayStat_hasGapUp ? "true" : "false"), DoubleToString(rthOpen, _Digits), DoubleToString(pdc, _Digits), DoubleToString(dayStat_openGapDown_percentageFill, 2), DoubleToString(dayStat_gapDiff, _Digits), DoubleToString(dayStat_rthHigh, _Digits), DoubleToString(dayStat_rthLow, _Digits), DoubleToString(dayStat_onHigh, _Digits), DoubleToString(dayStat_onLow, _Digits), (dayStat_ONH_t_RTH ? "true" : "false"), (dayStat_ONL_t_RTH ? "true" : "false"), (dayStat_ONboth_t_RTH ? "true" : "false"));
      FileClose(fhDay);
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
   int fhSum = FileOpen("dayPriceStat_summaryLog.csv", FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(fhSum != INVALID_HANDLE)
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
      FileWrite(fhSum, "days", "daysGapD", "daysNoGD", "gapD_avg_fill", "gD_20_f", "gD_25_f", "gD_30_f", "gD_33_f", "gD_40_f", "gD_50_f", "gD_60_f", "gD_75_f", "gD_90_f", "gD_100_f",
                "daysGapUp", "daysNoGU", "gapU_avg_fill", "gU_20_f", "gU_25_f", "gU_30_f", "gU_33_f", "gU_40_f", "gU_50_f", "gU_60_f", "gU_75_f", "gU_90_f", "gU_100_f",
                "daysONH_t_freq", "daysONL_t_freq", "daysONHL_t");
      FileWrite(fhSum, IntegerToString(dayStat_totalDays), IntegerToString(dayStat_daysWithGapDown), IntegerToString(dayStat_daysWithoutGapDown), DoubleToString(avgFillD, 2),
                DoubleToString(pctsD[0], 2), DoubleToString(pctsD[1], 2), DoubleToString(pctsD[2], 2), DoubleToString(pctsD[3], 2), DoubleToString(pctsD[4], 2), DoubleToString(pctsD[5], 2), DoubleToString(pctsD[6], 2), DoubleToString(pctsD[7], 2), DoubleToString(pctsD[8], 2), DoubleToString(pctsD[9], 2),
                IntegerToString(dayStat_daysWithGapUp), IntegerToString(dayStat_daysWithoutGapUp), DoubleToString(avgFillU, 2),
                DoubleToString(pctsU[0], 2), DoubleToString(pctsU[1], 2), DoubleToString(pctsU[2], 2), DoubleToString(pctsU[3], 2), DoubleToString(pctsU[4], 2), DoubleToString(pctsU[5], 2), DoubleToString(pctsU[6], 2), DoubleToString(pctsU[7], 2), DoubleToString(pctsU[8], 2), DoubleToString(pctsU[9], 2),
                DoubleToString(daysONH_t_freq, 2), DoubleToString(daysONL_t_freq, 2), DoubleToString(daysONHL_t, 2));
      FileClose(fhSum);
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

   int fh = FileOpen(InpSessionFirstLastCandleFile, FILE_WRITE|FILE_TXT);
   if(fh != INVALID_HANDLE)
   {
      FileWrite(fh,"----------------------------------------");
      FileWrite(fh,"Symbol: ",_Symbol);
      FileWrite(fh,"Timeframe: ",EnumToString(_Period));

      FileWrite(fh,"First Candle:");
      FileWrite(fh,"  Time: ",TimeToString(first_candle_time,TIME_DATE|TIME_SECONDS));
      FileWrite(fh,"  O: ",first_open," H: ",first_high," L: ",first_low," C: ",first_close);

      FileWrite(fh,"Last Candle:");
      FileWrite(fh,"  Time: ",TimeToString(last_candle_time,TIME_DATE|TIME_SECONDS));
      FileWrite(fh,"  O: ",last_open," H: ",last_high," L: ",last_low," C: ",last_close);

      FileWrite(fh,"----------------------------------------");
      FileClose(fh);
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

   MqlDateTime mt;
   TimeToStruct(g_lastTimer1Time, mt);
   datetime today = g_lastTimer1Time - (g_lastTimer1Time % 86400);

   // Temporary: log live price + closed candle date + OHLC every second 21:35-21:37. CSV with headers: time, liveBid, liveAsk, closed_candle_time, closed_O, closed_H, closed_L, closed_C
   if(mt.hour == 21 && mt.min >= 35 && mt.min <= 37 && g_barsInDay > 0)
   {
      // g_m1Rates is oldest-first: [0]=first bar of day, [g_barsInDay-1]=last; closed candle = second-to-last when >=2 bars
      int kClosed = (g_barsInDay >= 2) ? g_barsInDay - 2 : g_barsInDay - 1;
      datetime closedTime = g_m1Rates[kClosed].time;
      double closedO = g_m1Rates[kClosed].open, closedH = g_m1Rates[kClosed].high, closedL = g_m1Rates[kClosed].low, closedC = g_m1Rates[kClosed].close;
      string fname = TimeToString(today, TIME_DATE) + "_testing_liveprice.csv";
      int fh = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
      if(fh != INVALID_HANDLE)
      {
         FileSeek(fh, 0, SEEK_END);
         if(FileTell(fh) == 0)
            FileWrite(fh, "time", "liveBid", "liveAsk", "closed_candle_time", "closed_O", "closed_H", "closed_L", "closed_C");
         FileWrite(fh, TimeToString(g_lastTimer1Time, TIME_DATE|TIME_SECONDS), DoubleToString(g_liveBid, _Digits), DoubleToString(g_liveAsk, _Digits),
                   TimeToString(closedTime, TIME_DATE|TIME_SECONDS), DoubleToString(closedO, _Digits), DoubleToString(closedH, _Digits), DoubleToString(closedL, _Digits), DoubleToString(closedC, _Digits));
         FileClose(fh);
      }
      else
      {
         fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI);
         if(fh == INVALID_HANDLE)
            FatalError("OnTimer: could not open liveprice CSV " + fname);
         FileWrite(fh, "time", "liveBid", "liveAsk", "closed_candle_time", "closed_O", "closed_H", "closed_L", "closed_C");
         FileWrite(fh, TimeToString(g_lastTimer1Time, TIME_DATE|TIME_SECONDS), DoubleToString(g_liveBid, _Digits), DoubleToString(g_liveAsk, _Digits),
                   TimeToString(closedTime, TIME_DATE|TIME_SECONDS), DoubleToString(closedO, _Digits), DoubleToString(closedH, _Digits), DoubleToString(closedL, _Digits), DoubleToString(closedC, _Digits));
         FileClose(fh);
      }
   }

   // At 21:35: ensure current day is in dayStat (if missed at 21:30), then recalculate summary CSV so it always includes current day
   if(mt.hour == 21 && mt.min == 35 && g_barsInDay > 0)
   {
      TryLogDayStatForCurrentDay();
      WriteDayStatSummaryCsv();
   }

   // Candle-close detection: use M1 so "new candle" is always one closed M1 bar; bar that just closed = last bar of day M1 (g_m1Rates) after refresh
   datetime barNowM1 = iTime(_Symbol, PERIOD_M1, 0);
   if(barNowM1 == g_lastBarTime) return;

   g_lastBarTime = barNowM1;

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
   for(int k = 0; k < g_barsInDay; k++)
   {
      if(g_session[k] == "ON")
      {
         if(firstON) { runONhigh = g_m1Rates[k].high; runONlow = g_m1Rates[k].low; firstON = false; }
         else        { runONhigh = MathMax(runONhigh, g_m1Rates[k].high); runONlow = MathMin(runONlow, g_m1Rates[k].low); }
         g_ONhighSoFarAtBar[k].hasValue = true;
         g_ONhighSoFarAtBar[k].value    = runONhigh;
         g_ONlowSoFarAtBar[k].hasValue = true;
         g_ONlowSoFarAtBar[k].value    = runONlow;
      }
      else
      {
         g_ONhighSoFarAtBar[k].hasValue = !firstON;
         g_ONhighSoFarAtBar[k].value    = runONhigh;
         g_ONlowSoFarAtBar[k].hasValue  = !firstON;
         g_ONlowSoFarAtBar[k].value     = runONlow;
      }
      if(g_session[k] == "RTH")
      {
         if(firstRTH) { runRTHhigh = g_m1Rates[k].high; runRTHlow = g_m1Rates[k].low; firstRTH = false; }
         else         { runRTHhigh = MathMax(runRTHhigh, g_m1Rates[k].high); runRTHlow = MathMin(runRTHlow, g_m1Rates[k].low); }
         g_rthHighSoFarAtBar[k].hasValue = true;
         g_rthHighSoFarAtBar[k].value    = runRTHhigh;
         g_rthLowSoFarAtBar[k].hasValue  = true;
         g_rthLowSoFarAtBar[k].value     = runRTHlow;
      }
      else
      {
         g_rthHighSoFarAtBar[k].hasValue = !firstRTH;
         g_rthHighSoFarAtBar[k].value    = runRTHhigh;
         g_rthLowSoFarAtBar[k].hasValue  = !firstRTH;
         g_rthLowSoFarAtBar[k].value     = runRTHlow;
      }
   }

   // --- Trade results for the day (deals IN/OUT paired by magic; available globally)
   UpdateTradeResultsForDay();

   // --- Per-candle day progress (trades closed by each candle close time)
   UpdateDayProgress();

   // --- Per-level trade stats (trade results whose level matches levelPrice; ON/RTH by endTime)
   UpdateLevelTradeStats();

   // --- Static market context: pull when we have at least one closed candle for current day and haven't pulled for that day yet. Set ONopen from first candle whenever we have bars.
   if(g_barsInDay > 0)
   {
      // g_m1Rates is oldest-first: [0]=first bar of day
      g_ONopen = g_m1Rates[0].open;
      if(g_m1DayStart != 0 && g_staticMarketContextPulledForDate != g_m1DayStart)
      {
         UpdateStaticMarketContext(g_m1DayStart);
         g_staticMarketContextPulledForDate = g_m1DayStart;
         // Add PD RTH Close as a level for today only if no level eligible for that day is within 2 of PD RTH Close
         if(g_staticMarketContext.PDCpreviousDayRTHClose > 0.0)
         {
            string todayStr = TimeToString(g_m1DayStart, TIME_DATE);
            double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
            bool PDrthLevel_tooClose_to_regularLevel = false;
            for(int i = 0; i < g_levelsTotalCount; i++)
            {
               if(g_levels[i].startStr > todayStr || todayStr > g_levels[i].endStr) continue;
               if(MathAbs(g_levels[i].levelPrice - pdc) < tertiaryLevel_tooTight_toAdd_proximity) { PDrthLevel_tooClose_to_regularLevel = true; break; }
            }
            if(!PDrthLevel_tooClose_to_regularLevel)
            {
               string categories = "daily_tertiary_PDrthClose";
               string baseName = todayStr + "_PDrthClose";
               AddLevel(baseName, pdc, todayStr + " 00:00", todayStr + " 23:59", categories);
               if(g_levelsTotalCount < MAX_LEVEL_ROWS)
               {
                  g_levels[g_levelsTotalCount].startStr   = todayStr;
                  g_levels[g_levelsTotalCount].endStr    = todayStr;
                  g_levels[g_levelsTotalCount].levelPrice = pdc;
                  g_levels[g_levelsTotalCount].categories = categories;
                  g_levels[g_levelsTotalCount].tag       = "PDrthClose";
                  g_levelsTotalCount++;
                  UpdateDayM1AndLevelsExpanded();
               }
            }
         }
      }
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
         // Daily summary (Day_activeLevels, EOD account, AllHistoryOrders, AllHistoryDeals) — once per day when file missing
         if(!FileIsExist(dateStr + "-Day_activeLevels.csv"))
            WriteDailySummary();

         string logName = dateStr + "_testing_pullinghistory.csv";

         // Log pullinghistory from g_m1Rates (only once per day; if file missing, write again). MT5 CSV with headers.
         if(!FileIsExist(logName))
         {
            int fh = FileOpen(logName, FILE_WRITE | FILE_CSV | FILE_ANSI);
            if(fh == INVALID_HANDLE)
               FatalError("OnTimer: could not open " + logName);
            FileWrite(fh, "time", "O", "H", "L", "C", "levelAboveH", "levelBelowL", "session",
                     "dayWinRate", "dayTradesCount", "dayPointsSum", "dayProfitSum",
                     "ONwinRate", "ONtradeCount", "ONpointsSum", "ONprofitSum",
                     "RTHwinRate", "RTHtradeCount", "RTHpointsSum", "RTHprofitSum",
                     "ONhighSoFar", "ONlowSoFar", "rthHighSoFar", "rthLowSoFar",
                     "PDOpreviousDayRTHOpen", "PDHpreviousDayHigh", "PDLpreviousDayLow", "PDCpreviousDayRTHClose", "PDdate");
            for(int k = 0; k < g_barsInDay; k++)
            {
               if(!g_ONhighSoFarAtBar[k].hasValue || !g_ONlowSoFarAtBar[k].hasValue)
                  FatalError("pullinghistory: ONhighSoFar/ONlowSoFar required but no ON bar so far at bar k=" + IntegerToString(k) + " time=" + TimeToString(g_m1Rates[k].time, TIME_DATE|TIME_MINUTES));
               string rthH = g_rthHighSoFarAtBar[k].hasValue ? DoubleToString(g_rthHighSoFarAtBar[k].value, _Digits) : "";
               string rthL = g_rthLowSoFarAtBar[k].hasValue ? DoubleToString(g_rthLowSoFarAtBar[k].value, _Digits) : "";
               FileWrite(fh, TimeToString(g_m1Rates[k].time, TIME_DATE|TIME_MINUTES),
                     DoubleToString(g_m1Rates[k].open, _Digits), DoubleToString(g_m1Rates[k].high, _Digits), DoubleToString(g_m1Rates[k].low, _Digits), DoubleToString(g_m1Rates[k].close, _Digits),
                     DoubleToString(g_levelAboveH[k], 0), DoubleToString(g_levelBelowL[k], 0), g_session[k],
                     DoubleToString(g_dayProgress[k].dayWinRate * 100.0, 0), IntegerToString(g_dayProgress[k].dayTradesCount), DoubleToString(g_dayProgress[k].dayPointsSum, _Digits), DoubleToString(g_dayProgress[k].dayProfitSum, 2),
                     DoubleToString(g_dayProgress[k].ONwinRate * 100.0, 0), IntegerToString(g_dayProgress[k].ONtradeCount), DoubleToString(g_dayProgress[k].ONpointsSum, _Digits), DoubleToString(g_dayProgress[k].ONprofitSum, 2),
                     DoubleToString(g_dayProgress[k].RTHwinRate * 100.0, 0), IntegerToString(g_dayProgress[k].RTHtradeCount), DoubleToString(g_dayProgress[k].RTHpointsSum, _Digits), DoubleToString(g_dayProgress[k].RTHprofitSum, 2),
                     DoubleToString(g_ONhighSoFarAtBar[k].value, _Digits), DoubleToString(g_ONlowSoFarAtBar[k].value, _Digits), rthH, rthL,
                     DoubleToString(g_staticMarketContext.PDOpreviousDayRTHOpen, _Digits), DoubleToString(g_staticMarketContext.PDHpreviousDayHigh, _Digits), DoubleToString(g_staticMarketContext.PDLpreviousDayLow, _Digits), DoubleToString(g_staticMarketContext.PDCpreviousDayRTHClose, _Digits), g_staticMarketContext.PDdate);
            }
            FileClose(fh);
         }

         // EOD one-line trades summary: same trade stats as latest row of pullinghistory (date)_summary_EOD_tradesSummary1line.csv
         string eodSummaryName = dateStr + "_summary_EOD_tradesSummary1line.csv";
         if(!FileIsExist(eodSummaryName))
         {
            int fhEod = FileOpen(eodSummaryName, FILE_WRITE | FILE_CSV | FILE_ANSI);
            if(fhEod != INVALID_HANDLE)
            {
               FileWrite(fhEod, "time", "dayWinRate", "dayTradesCount", "dayPointsSum", "dayProfitSum", "ONwinRate", "ONtradeCount", "ONpointsSum", "ONprofitSum", "RTHwinRate", "RTHtradeCount", "RTHpointsSum", "RTHprofitSum");
               int kLast = g_barsInDay - 1;
               if(kLast >= 0)
               {
                  FileWrite(fhEod, TimeToString(g_m1Rates[kLast].time, TIME_DATE|TIME_MINUTES),
                     DoubleToString(g_dayProgress[kLast].dayWinRate * 100.0, 0), IntegerToString(g_dayProgress[kLast].dayTradesCount), DoubleToString(g_dayProgress[kLast].dayPointsSum, _Digits), DoubleToString(g_dayProgress[kLast].dayProfitSum, 2),
                     DoubleToString(g_dayProgress[kLast].ONwinRate * 100.0, 0), IntegerToString(g_dayProgress[kLast].ONtradeCount), DoubleToString(g_dayProgress[kLast].ONpointsSum, _Digits), DoubleToString(g_dayProgress[kLast].ONprofitSum, 2),
                     DoubleToString(g_dayProgress[kLast].RTHwinRate * 100.0, 0), IntegerToString(g_dayProgress[kLast].RTHtradeCount), DoubleToString(g_dayProgress[kLast].RTHpointsSum, _Digits), DoubleToString(g_dayProgress[kLast].RTHprofitSum, 2));
               }
               FileClose(fhEod);
            }
         }

         // Accumulate this day into all-days summary (once per day), then write summary_tradesSummary1line.csv with totals
         if(g_barsInDay > 0 && g_m1DayStart != 0 && g_m1DayStart != g_summaryTrades_lastAddedDayStart)
         {
            int kLast = g_barsInDay - 1;
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
         }
         if(g_barsInDay > 0)
         {
            int fhEodAll = FileOpen("summary_tradesSummary1line.csv", FILE_WRITE | FILE_CSV | FILE_ANSI);
            if(fhEodAll != INVALID_HANDLE)
            {
               double dayWr = (g_summaryTrades_dayTradesCount > 0) ? 100.0 * (double)g_summaryTrades_dayWins / (double)g_summaryTrades_dayTradesCount : 0.0;
               double onWr  = (g_summaryTrades_ONtradeCount > 0) ? 100.0 * (double)g_summaryTrades_ONwins / (double)g_summaryTrades_ONtradeCount : 0.0;
               double rthWr = (g_summaryTrades_RTHtradeCount > 0) ? 100.0 * (double)g_summaryTrades_RTHwins / (double)g_summaryTrades_RTHtradeCount : 0.0;
               FileWrite(fhEodAll, "time", "dayWinRate", "dayTradesCount", "dayPointsSum", "dayProfitSum", "ONwinRate", "ONtradeCount", "ONpointsSum", "ONprofitSum", "RTHwinRate", "RTHtradeCount", "RTHpointsSum", "RTHprofitSum");
               int kLast = g_barsInDay - 1;
               FileWrite(fhEodAll, TimeToString(g_m1Rates[kLast].time, TIME_DATE|TIME_MINUTES),
                  DoubleToString(dayWr, 0), IntegerToString(g_summaryTrades_dayTradesCount), DoubleToString(g_summaryTrades_dayPointsSum, _Digits), DoubleToString(g_summaryTrades_dayProfitSum, 2),
                  DoubleToString(onWr, 0), IntegerToString(g_summaryTrades_ONtradeCount), DoubleToString(g_summaryTrades_ONpointsSum, _Digits), DoubleToString(g_summaryTrades_ONprofitSum, 2),
                  DoubleToString(rthWr, 0), IntegerToString(g_summaryTrades_RTHtradeCount), DoubleToString(g_summaryTrades_RTHpointsSum, _Digits), DoubleToString(g_summaryTrades_RTHprofitSum, 2));
               FileClose(fhEodAll);
            }
         }

         // Trade results CSV: (date)_summaryZ_tradeResults_ALL_Day.csv (only once; if missing, write again)
         string csvName = dateStr + "_summaryZ_tradeResults_ALL_Day.csv";
         if(!FileIsExist(csvName))
         {
            int fhTr = FileOpen(csvName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_CSV);
            if(fhTr == INVALID_HANDLE)
               FatalError("OnTimer: could not open " + csvName);
            {
               FileWrite(fhTr, "symbol", "startTime", "endTime", "session", "magic", "priceStart", "priceEnd", "priceDiff", "profit", "type", "reason", "volume", "bothComments", "level", "tp", "sl");
               for(int tr = 0; tr < g_tradeResultsCount; tr++)
               {
                  TradeResult r = g_tradeResults[tr];
                  string endTimeStr = r.foundOut ? TimeToString(r.endTime, TIME_DATE|TIME_SECONDS) : "NOT_FOUND";
                  string priceEndStr = r.foundOut ? DoubleToString(r.priceEnd, _Digits) : "NOT_FOUND";
                  string profitStr = r.foundOut ? DoubleToString(r.profit, 2) : "NOT_FOUND";
                  string reasonStr = r.foundOut ? EnumToString((ENUM_DEAL_REASON)r.reason) : "NOT_FOUND";
                  string typeStr = EnumToString((ENUM_DEAL_TYPE)r.type);
                  FileWrite(fhTr, r.symbol, TimeToString(r.startTime, TIME_DATE|TIME_SECONDS), endTimeStr,
                     r.session, IntegerToString((long)r.magic), DoubleToString(r.priceStart, _Digits), priceEndStr,
                     DoubleToString(r.priceDiff, _Digits), profitStr, typeStr, reasonStr,
                     DoubleToString(r.volume, 2), r.bothComments, r.level, r.tp, r.sl);
               }
               FileClose(fhTr);
            }

            // Append same day's results to all-days summary (single file, no date in name)
            string summaryAllName = "summary_tradeResults_all_days.csv";
            int fhSumTr = FileOpen(summaryAllName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
            if(fhSumTr != INVALID_HANDLE)
            {
               FileSeek(fhSumTr, 0, SEEK_END);
               if(FileTell(fhSumTr) == 0)
                  FileWrite(fhSumTr, "date", "symbol", "startTime", "endTime", "session", "magic", "priceStart", "priceEnd", "priceDiff", "profit", "type", "reason", "volume", "bothComments", "level", "tp", "sl");
               for(int tr = 0; tr < g_tradeResultsCount; tr++)
               {
                  TradeResult r = g_tradeResults[tr];
                  string endTimeStr = r.foundOut ? TimeToString(r.endTime, TIME_DATE|TIME_SECONDS) : "NOT_FOUND";
                  string priceEndStr = r.foundOut ? DoubleToString(r.priceEnd, _Digits) : "NOT_FOUND";
                  string profitStr = r.foundOut ? DoubleToString(r.profit, 2) : "NOT_FOUND";
                  string reasonStr = r.foundOut ? EnumToString((ENUM_DEAL_REASON)r.reason) : "NOT_FOUND";
                  string typeStr = EnumToString((ENUM_DEAL_TYPE)r.type);
                  FileWrite(fhSumTr, dateStr, r.symbol, TimeToString(r.startTime, TIME_DATE|TIME_SECONDS), endTimeStr,
                     r.session, IntegerToString((long)r.magic), DoubleToString(r.priceStart, _Digits), priceEndStr,
                     DoubleToString(r.priceDiff, _Digits), profitStr, typeStr, reasonStr,
                     DoubleToString(r.volume, 2), r.bothComments, r.level, r.tp, r.sl);
               }
               FileClose(fhSumTr);
            }
         }

         // Per-level files (only once per file per day; if missing, write again). MT5 CSV with headers.
         int recentPriceArgument = 5;
         for(int e = 0; e < g_levelsTodayCount; e++)
         {
            string levelFile = dateStr + "_testinglevelsplus_" + DoubleToString(g_levelsExpanded[e].levelPrice, _Digits) + "_" + g_levelsExpanded[e].tag + ".csv";
            if(!FileIsExist(levelFile))
            {
               int fhL = FileOpen(levelFile, FILE_WRITE | FILE_CSV | FILE_ANSI);
               if(fhL == INVALID_HANDLE)
                  FatalError("OnTimer: could not open " + levelFile);
               FileWrite(fhL, "time", "diff_CloseToLevel", "O", "H", "L", "C", "breaksLevelDown", "breaksLevelUpward", "cleanStreakAbove", "cleanStreakBelow", "aboveCnt", "abovePerc", "belowCnt", "belowPerc", "overlapStreak", "overlapC", "overlapPc", "HighestDiffUp_rangeArg", "HighestDiffUpRange", "HighestDiffDown_rangeArg", "HighestDiffDownRange", "ON_O_wasAboveL", "RTH_O_wasAboveL", "ONtradeCount_L", "ONwinRate_L", "ONpointsSum_L", "ONprofitSum_L", "RTHtradeCount_L", "RTHwinRate_L", "RTHpointsSum_L", "RTHprofitSum_L");
               double lvl = g_levelsExpanded[e].levelPrice;
               double onOpen = g_m1Rates[0].open;
               double rthOpen = GetRTHopenCurrentDay();
               for(int k = 0; k < g_levelsExpanded[e].count; k++)
               {
                  string highestUp   = GetHighestDiffInWindowString(lvl, k, recentPriceArgument, true);
                  string highestDown = GetHighestDiffInWindowString(lvl, k, recentPriceArgument, false);
                  bool onKnown   = (k > 0);
                  bool rthKnown  = (GetSessionForCandleTime(g_levelsExpanded[e].times[k]) != "ON");
                  string onAboveStr  = GetOpenWasAboveLevelString(onOpen, lvl, onKnown);
                  string rthAboveStr = GetOpenWasAboveLevelString(rthOpen, lvl, rthKnown);
                  FileWrite(fhL, TimeToString(g_levelsExpanded[e].times[k], TIME_DATE|TIME_MINUTES),
                     DoubleToString(g_levelsExpanded[e].diffs[k], _Digits),
                     DoubleToString(g_m1Rates[k].open, _Digits), DoubleToString(g_m1Rates[k].high, _Digits), DoubleToString(g_m1Rates[k].low, _Digits), DoubleToString(g_m1Rates[k].close, _Digits),
                     (g_breaksLevelDown[e][k] ? "true" : "false"), (g_breaksLevelUpward[e][k] ? "true" : "false"),
                     IntegerToString(g_cleanStreakAbove[e][k]), IntegerToString(g_cleanStreakBelow[e][k]),
                     IntegerToString(g_aboveCnt[e][k]), DoubleToString(g_abovePerc[e][k], 2), IntegerToString(g_belowCnt[e][k]), DoubleToString(g_belowPerc[e][k], 2),
                     IntegerToString(g_overlapStreak[e][k]), IntegerToString(g_overlapC[e][k]), DoubleToString(g_overlapPc[e][k], 2),
                     highestUp, IntegerToString(recentPriceArgument), highestDown, IntegerToString(recentPriceArgument),
                     onAboveStr, rthAboveStr,
                     IntegerToString(g_ONtradeCount_L[e][k]), DoubleToString((g_ONtradeCount_L[e][k] > 0) ? (double)g_ONwins_L[e][k] / (double)g_ONtradeCount_L[e][k] * 100.0 : 0.0, 0), DoubleToString(g_ONpointsSum_L[e][k], _Digits), DoubleToString(g_ONprofitSum_L[e][k], 2),
                     IntegerToString(g_RTHtradeCount_L[e][k]), DoubleToString((g_RTHtradeCount_L[e][k] > 0) ? (double)g_RTHwins_L[e][k] / (double)g_RTHtradeCount_L[e][k] * 100.0 : 0.0, 0), DoubleToString(g_RTHpointsSum_L[e][k], _Digits), DoubleToString(g_RTHprofitSum_L[e][k], 2));
               }
               FileClose(fhL);
            }
         }

         // Levels break check: one row per level (21:58). Separate ON (til 15:30) and RTH (15:30 onward). Rows sorted by levelPrice.
         string breakCheckFile = dateStr + "_levels_breakCheck_breakingDown.csv";
         int fhBreak = FileOpen(breakCheckFile, FILE_WRITE | FILE_CSV | FILE_ANSI);
         if(fhBreak != INVALID_HANDLE)
         {
            string cutoffStr = IntegerToString((int)MathRound(InpBreakCheckMaxDistPoints));
            FileWrite(fhBreak, "levelPrice", "ONrangeStartTime", "ONcountCandles_" + cutoffStr, "ONaverage_" + cutoffStr, "ONmedian_" + cutoffStr, "RTHIBrangeStartTime", "RTHIBcountCandles_" + cutoffStr, "RTHIBaverage_" + cutoffStr, "RTHIBmedian_" + cutoffStr, "RTHcntrangeStartTime", "RTHcntcountCandles_" + cutoffStr, "RTHcntaverage_" + cutoffStr, "RTHcntmedian_" + cutoffStr);
            bool accumulateToday = (g_m1DayStart != 0 && g_m1DayStart != g_breakCheck_lastAggregatedDay);
            int order[];
            ArrayResize(order, g_levelsTodayCount);
            for(int i = 0; i < g_levelsTodayCount; i++) order[i] = i;
            for(int i = 0; i < g_levelsTodayCount; i++)
               for(int j = i + 1; j < g_levelsTodayCount; j++)
                  if(g_levelsExpanded[order[j]].levelPrice < g_levelsExpanded[order[i]].levelPrice)
                  { int t = order[i]; order[i] = order[j]; order[j] = t; }
            for(int i = 0; i < g_levelsTodayCount; i++)
            {
               int e = order[i];
               double lvl = g_levelsExpanded[e].levelPrice;
               double maxDist = InpBreakCheckMaxDistPoints;  // always in price

               BreakCheckSessionResult onRes    = BreakCheckSessionStats(lvl, maxDist, BREAKCHECK_ON);
               BreakCheckSessionResult rthibRes = BreakCheckSessionStats(lvl, maxDist, BREAKCHECK_RTHIB);
               BreakCheckSessionResult rthcntRes = BreakCheckSessionStats(lvl, maxDist, BREAKCHECK_RTHCNT);

               FileWrite(fhBreak, DoubleToString(lvl, _Digits),
                  onRes.rangeStartStr, IntegerToString(onRes.n), DoubleToString(onRes.avg, _Digits), DoubleToString(onRes.median, _Digits),
                  rthibRes.rangeStartStr, IntegerToString(rthibRes.n), DoubleToString(rthibRes.avg, _Digits), DoubleToString(rthibRes.median, _Digits),
                  rthcntRes.rangeStartStr, IntegerToString(rthcntRes.n), DoubleToString(rthcntRes.avg, _Digits), DoubleToString(rthcntRes.median, _Digits));
               if(accumulateToday)
               {
                  bool excludeTertiary = (StringFind(g_levelsExpanded[e].categories, "tertiary") >= 0);
                  if(!excludeTertiary)
                  {
                     g_agg_ONbreakDown_sumCandles += onRes.n; g_agg_ONbreakDown_sumAvg += onRes.avg; g_agg_ONbreakDown_sumMed += onRes.median; g_agg_ONbreakDown_n++;
                     g_agg_RTHIBbreakDown_sumCandles += rthibRes.n; g_agg_RTHIBbreakDown_sumAvg += rthibRes.avg; g_agg_RTHIBbreakDown_sumMed += rthibRes.median; g_agg_RTHIBbreakDown_n++;
                     g_agg_RTHcntbreakDown_sumCandles += rthcntRes.n; g_agg_RTHcntbreakDown_sumAvg += rthcntRes.avg; g_agg_RTHcntbreakDown_sumMed += rthcntRes.median; g_agg_RTHcntbreakDown_n++;
                  }
               }
            }
            if(accumulateToday) { g_breakCheck_lastAggregatedDay = g_m1DayStart; g_breakCheck_daysCount++; }
            FileClose(fhBreak);
         }
         // At 22:00 write single aggregate log (no date in name): type, avgcandles, avgavg, avgmedian for all 4 types
         if(minOfDay == 22*60+0)
         {
            int fhSum = FileOpen("levels_breakCheck_breakingDown_tertiaryLevelsExcluded_summary.csv", FILE_WRITE | FILE_CSV | FILE_ANSI);
            if(fhSum != INVALID_HANDLE)
            {
               FileWrite(fhSum, "timerangeType", "avgCandleCount", "avgOfAvg", "avgOfMedian", "daysCount", "totalLevelCount");
               int daysCount = g_breakCheck_daysCount;
               double n;
               n = (double)g_agg_ONbreakDown_n;   FileWrite(fhSum, "ON",   (n > 0 ? DoubleToString(g_agg_ONbreakDown_sumCandles/n, 2) : "0"), (n > 0 ? DoubleToString(g_agg_ONbreakDown_sumAvg/n, _Digits) : "0"), (n > 0 ? DoubleToString(g_agg_ONbreakDown_sumMed/n, _Digits) : "0"), IntegerToString(daysCount), IntegerToString(g_agg_ONbreakDown_n));
               n = (double)g_agg_RTHIBbreakDown_n; FileWrite(fhSum, "RTHIB", (n > 0 ? DoubleToString(g_agg_RTHIBbreakDown_sumCandles/n, 2) : "0"), (n > 0 ? DoubleToString(g_agg_RTHIBbreakDown_sumAvg/n, _Digits) : "0"), (n > 0 ? DoubleToString(g_agg_RTHIBbreakDown_sumMed/n, _Digits) : "0"), IntegerToString(daysCount), IntegerToString(g_agg_RTHIBbreakDown_n));
               n = (double)g_agg_RTHcntbreakDown_n; FileWrite(fhSum, "RTHcnt", (n > 0 ? DoubleToString(g_agg_RTHcntbreakDown_sumCandles/n, 2) : "0"), (n > 0 ? DoubleToString(g_agg_RTHcntbreakDown_sumAvg/n, _Digits) : "0"), (n > 0 ? DoubleToString(g_agg_RTHcntbreakDown_sumMed/n, _Digits) : "0"), IntegerToString(daysCount), IntegerToString(g_agg_RTHcntbreakDown_n));
               FileClose(fhSum);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Type 3: trigger as soon as bar closed. Place buy at trigger minute; close at close minute. No bar-end time logic. |
//+------------------------------------------------------------------+
void EvaluateTradeType3(datetime candleTime)
{
   MqlDateTime mt;
   TimeToStruct(candleTime, mt);
   int minute = mt.min;
   if(minute != 29 && minute != 44) return;

   if(g_tradeConfig[TRADE_TYPE_MARKET_TEST].useTimeFilter && StringLen(g_tradeConfig[TRADE_TYPE_MARKET_TEST].bannedRangesStr) > 0)
   {
      ParseBannedRanges(g_tradeConfig[TRADE_TYPE_MARKET_TEST].bannedRangesStr);
      if(!IsTradingAllowed(candleTime, g_bannedRangesBuffer, g_bannedRangesCount)) return;
   }

   long magic = BuildMagicForTradeType3(candleTime);

   if(minute == 29)
   {
      if(CountOrdersAndPositionsForMagic(magic) >= Max_OrdersPerMagic) return;

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double slPoints = (double)T_tradeType3_SLPoints;
      double tpPoints = (double)T_tradeType3_TPPoints;
      string orderComment = StringFormat("%d", (int)TRADE_TYPE_MARKET_TEST);
      ExtTrade.SetExpertMagicNumber(magic);

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = NormalizeDouble(ask - slPoints * point, _Digits);
      double tp = NormalizeDouble(ask + tpPoints * point, _Digits);
      if(ExtTrade.Buy(T_tradeType3_LotSize, _Symbol, ask, sl, tp, orderComment))
      {
         ulong orderTicket = ExtTrade.ResultOrder();
         datetime eventTime = candleTime;
         if(orderTicket > 0 && OrderSelect(orderTicket))
            eventTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         WriteTradeLog(GetTradeTypeStringFromId(TRADE_TYPE_MARKET_TEST), "pending_created", eventTime, "market_buy", ask, sl, tp, 0, orderTicket, 0, 0, (ENUM_DEAL_REASON)0, orderComment, magic);
      }

      ExtTrade.SetExpertMagicNumber(EA_MAGIC);
   }
   else // close minute: close any position(s) with trade type 3 magic (id 3 + date)
   {
      ExtTrade.SetExpertMagicNumber(magic);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!ExtPositionInfo.SelectByIndex(i)) continue;
         if(ExtPositionInfo.Symbol() != _Symbol) continue;
         if(ExtPositionInfo.Magic() != magic) continue;
         ulong ticket = ExtPositionInfo.Ticket();
         double closePrice = ExtPositionInfo.PriceCurrent();
         ExtTrade.PositionClose(ticket);
         WriteTradeLog(GetTradeTypeStringFromId(TRADE_TYPE_MARKET_TEST), "closed_by_ea", candleTime, "market_buy", closePrice, 0, 0, 0, 0, 0, ticket, (ENUM_DEAL_REASON)0, "", magic);
      }
      ExtTrade.SetExpertMagicNumber(EA_MAGIC);
   }
}

//+------------------------------------------------------------------+
void FinalizeCurrentCandle()
{
   datetime candleDay = current_candle_time - (current_candle_time % 86400);
   string dateStr = TimeToString(current_candle_time,TIME_DATE);

   if(allCandlesFileDate != candleDay)
   {
      if(allCandlesFileHandle != INVALID_HANDLE)
         FileClose(allCandlesFileHandle);

      string allFileName = dateStr + "-AllCandlesLog_Timer1.csv";
      int fhAll = FileOpen(allFileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
      if(fhAll == INVALID_HANDLE)
         fhAll = FileOpen(allFileName, FILE_WRITE | FILE_CSV | FILE_ANSI);
      if(fhAll == INVALID_HANDLE)
         FatalError("FinalizeCurrentCandle: could not open " + allFileName);
      FileSeek(fhAll, 0, SEEK_END);
      if(FileTell(fhAll) == 0)
         FileWrite(fhAll, "time", "O", "H", "L", "C");
      allCandlesFileHandle = fhAll;
      allCandlesFileDate = candleDay;
   }

   // Day stat: once after 21:30 candle, set dayStat_day_had_OpenGapDown_bool (RTH open < PD RTH close) and write dayPriceStat_log + dayPriceStat_summaryLog
   {
      MqlDateTime mt;
      TimeToStruct(current_candle_time, mt);
      if(mt.hour == 21 && mt.min == 30)
      {
         if(TryLogDayStatForCurrentDay())
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

            string araFile = StringFormat("%s-%s_week%s_-%s_Arawevents.csv", 
                                         dateStr, levels[i].baseName, dateStr, DoubleToString(lvl,_Digits));

            int fhAra = FileOpen(araFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
            if(fhAra == INVALID_HANDLE)
               fhAra = FileOpen(araFile, FILE_WRITE | FILE_CSV | FILE_ANSI);
            if(fhAra == INVALID_HANDLE)
               FatalError("FinalizeCurrentCandle: could not open " + araFile);
            FileSeek(fhAra, 0, SEEK_END);
            if(FileTell(fhAra) == 0)
               FileWrite(fhAra, "time", "level", "O", "H", "low", "C", "diff_CloseToLevel", "DayBias", "Contact", "ContactCount", "BounceCount", "CandlesPassedSinceLastBounce", "CandlesBreakLevelCount", "RecoverCount");
            levels[i].logRawEv_fileHandle = fhAra;
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

         // --- Flow B: for each trade type, if time OK and price/levels OK, do this type (types 1,2 per level here; types 3,4 once after loop)
         // --- Trade type 1 (buy_2nd_bounce): level + price + time. Entry rule: bounceCount==1, bias_long, no_contact, timeAllowed.
         {
            string tradeTypeStr = GetTradeTypeStringFromId(TRADE_TYPE_BUY_2ND_BOUNCE);
            long tradeMagic = BuildTradeMagic(levels[i].validFrom, levels[i].price, levels[i].tagsCSV, TRADE_TYPE_BUY_2ND_BOUNCE);
            int current_all_trades = CountOrdersAndPositionsForMagic(tradeMagic);
            
            bool timeAllowed = true;
            if(g_tradeConfig[TRADE_TYPE_BUY_2ND_BOUNCE].useTimeFilter && StringLen(g_tradeConfig[TRADE_TYPE_BUY_2ND_BOUNCE].bannedRangesStr) > 0)
            {
               ParseBannedRanges(g_tradeConfig[TRADE_TYPE_BUY_2ND_BOUNCE].bannedRangesStr);
               timeAllowed = IsTradingAllowed(current_candle_time, g_bannedRangesBuffer, g_bannedRangesCount);
            }
            
            bool bias_long = (levels[i].dailyBias > 0);
            bool no_contact = !in_contact;
            bool entryRule = (levels[i].bounceCount == 1) && bias_long && no_contact && (levels[i].candlesPassedSinceLastBounce < 65);
            bool allowed = (current_all_trades < Max_OrdersPerMagic) && entryRule && timeAllowed;

            if(allowed)
            {
               double pip = PipSize();
               double orderPrice = NormalizeDouble(lvl + T_buy2ndBounce_PriceOffsetPips * pip, _Digits);
               double sl = NormalizeDouble(orderPrice - T_buy2ndBounce_SLPips * pip, _Digits);
               double tp = NormalizeDouble(orderPrice + T_buy2ndBounce_TPPips * pip, _Digits);
               
               string orderComment = StringFormat("$%d %.0f %.0f %d",
                  (int)lvl,
                  T_buy2ndBounce_TPPips,
                  T_buy2ndBounce_SLPips,
                  (int)TRADE_TYPE_BUY_2ND_BOUNCE);

               datetime expirationTime = g_lastTimer1Time + 30 * 60;
               
               ExtTrade.SetExpertMagicNumber(tradeMagic);
               
               if(ExtTrade.BuyLimit(T_buy2ndBounce_LotSize, orderPrice, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expirationTime, orderComment))
               {
                  ulong orderTicket = ExtTrade.ResultOrder();
                  datetime eventTime = current_candle_time;
                  if(orderTicket > 0 && OrderSelect(orderTicket))
                     eventTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
                  WriteTradeLog(tradeTypeStr, "pending_created", eventTime, "buy_limit", orderPrice, sl, tp, 30, orderTicket, 0, 0, (ENUM_DEAL_REASON)0, orderComment, tradeMagic);
               }
               
               ExtTrade.SetExpertMagicNumber(EA_MAGIC);
            }
         }

         // --- Trade type 2 (buy_4th_bounce): level + price + time. Entry rule: bounceCount==3, bias_long, no_contact, timeAllowed.
         {
            string tradeTypeStr = GetTradeTypeStringFromId(TRADE_TYPE_BUY_4TH_BOUNCE);
            long tradeMagic = BuildTradeMagic(levels[i].validFrom, levels[i].price, levels[i].tagsCSV, TRADE_TYPE_BUY_4TH_BOUNCE);
            int current_all_trades = CountOrdersAndPositionsForMagic(tradeMagic);
            
            bool timeAllowed = true;
            if(g_tradeConfig[TRADE_TYPE_BUY_4TH_BOUNCE].useTimeFilter && StringLen(g_tradeConfig[TRADE_TYPE_BUY_4TH_BOUNCE].bannedRangesStr) > 0)
            {
               ParseBannedRanges(g_tradeConfig[TRADE_TYPE_BUY_4TH_BOUNCE].bannedRangesStr);
               timeAllowed = IsTradingAllowed(current_candle_time, g_bannedRangesBuffer, g_bannedRangesCount);
            }
            
            bool bias_long = (levels[i].dailyBias > 0);
            bool no_contact = !in_contact;
            bool entryRule = (levels[i].bounceCount == 3) && bias_long && no_contact && (levels[i].candlesPassedSinceLastBounce < 65);
            bool allowed = (current_all_trades < Max_OrdersPerMagic) && entryRule && timeAllowed;

            if(allowed)
            {
               double pip = PipSize();
               double orderPrice = NormalizeDouble(lvl + T_buy4thBounce_PriceOffsetPips * pip, _Digits);
               double sl = NormalizeDouble(orderPrice - T_buy4thBounce_SLPips * pip, _Digits);
               double tp = NormalizeDouble(orderPrice + T_buy4thBounce_TPPips * pip, _Digits);
               
               string orderComment = StringFormat("$%d %.0f %.0f %d",
                  (int)lvl,
                  T_buy4thBounce_TPPips,
                  T_buy4thBounce_SLPips,
                  (int)TRADE_TYPE_BUY_4TH_BOUNCE);

               datetime expirationTime = g_lastTimer1Time + 30 * 60;
               
               ExtTrade.SetExpertMagicNumber(tradeMagic);
               
               if(ExtTrade.BuyLimit(T_buy4thBounce_LotSize, orderPrice, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expirationTime, orderComment))
               {
                  ulong orderTicket = ExtTrade.ResultOrder();
                  datetime eventTime = current_candle_time;
                  if(orderTicket > 0 && OrderSelect(orderTicket))
                     eventTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
                  WriteTradeLog(tradeTypeStr, "pending_created", eventTime, "buy_limit", orderPrice, sl, tp, 30, orderTicket, 0, 0, (ENUM_DEAL_REASON)0, orderComment, tradeMagic);
               }
               
               ExtTrade.SetExpertMagicNumber(EA_MAGIC);
            }
         }
      }
   }

   // Flow B: evaluate trade type 3 (time filter only; trigger at candle close)
   EvaluateTradeType3(current_candle_time);

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