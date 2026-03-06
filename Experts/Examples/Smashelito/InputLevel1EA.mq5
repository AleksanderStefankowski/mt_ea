//+------------------------------------------------------------------+
//|                                                InputLevel1EA.mq5 |
//+------------------------------------------------------------------+
//|                   MetaTrader 5 Only (MT5-specific code)          |
//|        Copyright 2026, Aleksander Stefankowski                   |
// NOTE: This EA is MetaTrader 5 (MT5) ONLY. Do NOT attempt to add MT4 code.
// All file operations and tick/candle handling are MT5-specific.
// '&' reference cannot ever be used!
//
// OVERFLOW: Magic numbers and MT5 IDs (order/deal/position) can exceed INT_MAX.
// Never cast them to (int). Use long/ulong and IntegerToString((long)value) for logging.


#property copyright "Copyright 2026, Aleksander Stefankowski"

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>

//--- Inputs
input string   InpSummaryFile       = "LevelLog.txt";
input string   InpAllCandleFile     = "AllCandlesTickLog";
input double   ProximityThreshold   = 1.0;
input double   LevelCountsAsBroken_Threshold = -2.5; // how deep close must breach to count as broken
input int      HowManyCandlesAboveLevel_CountAsPriceRecovered = 6; // for RecoverCount
input int      BounceCandlesRequired = 1; // for bounce count logic
input int      Max_OrdersPerMagic = 1; // max open positions + pending orders with this magic (same full magic number)
input double   InpLotSize           = 0.01; // lot size for trade types
input int      HourForDailySummary   = 21;   // hour (server time) when daily summary is written (tick timestamp)
input int      MinuteForDailySummary = 30;   // minute of the hour for summary trigger
input bool     InpTestingPullM1History = true;  // if true: at 21:58-22:00 write (date)_testing_pullinghistory.txt and testinglevelsplus files
input string   InpCalendarFile        = "calendar_2026_dots.csv";  // CSV in Terminal/Common/Files: date (YYYY.MM.DD),dayofmonth,dayofweek,opex,qopex
input string   InpLevelsFile          = "levelsinfo_zeFinal.csv";  // CSV in Terminal/Common/Files: start,end,levelPrice,categories,tag

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
//--- Trade type 4: 15:29 smash (level + time). As soon as 15:29 bar closed, if |price - daily smash level| < MaxDistancePoints, market buy. TP/SL in pips.
//    useLevel=true (smash), usePrice=true (distance), useTimeFilter=false (fixed 15:29 only).
input double   T_tradeType4_LotSize   = 0.01;
input double   T_tradeType4_TPPips   = 90.0;
input double   T_tradeType4_SLPips   = 90.0;
input double   T_tradeType4_MaxDistancePoints = 50.0;  // entry only if |price - level| < this (in points)

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
   TRADE_TYPE_MARKET_TEST   = 3,   // trigger at bar close: place buy then close later; no level in magic
   TRADE_TYPE_15_30_SMASH    = 4    // when 15:29 bar closed, if price near daily smash level → market buy
};

CTrade ExtTrade;
COrderInfo ExtOrderInfo;
CPositionInfo ExtPositionInfo;
CDealInfo ExtDealInfo;

//--- Tick-based candle tracking
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
datetime lastDailySummaryDay = 0; // stores the day (midnight timestamp) when summary was last written

//--- Last tick time (server); set in OnTick or OnTimer, use instead of TimeCurrent()
datetime g_lastTickTime = 0;

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
   string startStr;   // "YYYY-MM-DD"
   string endStr;    // "YYYY-MM-DD"
   double levelPrice;
   string categories; // e.g. "daily_monday_smash_stacked"
   string tag;       // e.g. "dailySmash", "weeklyUp1" (loaded but not used yet)
};
#define MAX_LEVEL_ROWS 2000
LevelInfoRow g_levels[MAX_LEVEL_ROWS];
int g_levelsCount = 0;

//--- Levels expanded (built in testing loop: each level of the day vs whole price chart; newway_Diff_CloseToLevel per bar)
struct LevelExpandedRow
{
   double levelPrice;
   string tag;
   int    count;      // number of bars
   double diffs[];    // newway_Diff_CloseToLevel = close - levelPrice per bar
   datetime times[];  // bar time per bar
};
#define MAX_LEVELS_EXPANDED 500
LevelExpandedRow g_levelsExpanded[MAX_LEVELS_EXPANDED];
int g_levelsExpandedCount = 0;

//--- Day M1 price data (updated every new bar; used by trade logic and by testing log)
#define MAX_BARS_IN_DAY 1500
MqlRates g_m1Rates[MAX_BARS_IN_DAY];  // day's bars only, index k = k-th bar of day
int g_barsInDay = 0;
datetime g_m1DayStart = 0;  // which day g_m1Rates is for (0 = not set)
// Per-bar data (filled in UpdateDayM1AndLevelsExpanded; logged in 21:59-22:00 window)
double g_levelAboveH[MAX_BARS_IN_DAY];  // level (levelPrice) above candle high; 0 if none
double g_levelBelowL[MAX_BARS_IN_DAY];  // level below candle low; 0 if none
string g_session[MAX_BARS_IN_DAY];      // "ON"|"RTH"|"sleep"

//--- Trade results for the day (deals IN/OUT paired by magic; updated every new bar in loop2; logged in 21:59-22:00)
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

//--- Static market context: previous trading day's PDO/PDH/PDL/PDC (pulled on init and in 00:00-00:03 each day; same for all bars of the day)
struct StaticMarketContext
{
   double PDOpreviousDayOpen;   // 15:30 open of previous trading day
   double PDHpreviousDayHigh;   // highest High of previous trading day
   double PDLpreviousDayLow;    // lowest Low of previous trading day
   double PDCpreviousDayClose;  // close of previous day's 22:00 candle
   string PDdate;               // previous trading day date YYYY-MM-DD (for debugging)
};
StaticMarketContext g_staticMarketContext;

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
   if(fh == INVALID_HANDLE) return false;
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
   g_staticMarketContext.PDOpreviousDayOpen  = 0;
   g_staticMarketContext.PDHpreviousDayHigh  = 0;
   g_staticMarketContext.PDLpreviousDayLow   = 0;
   g_staticMarketContext.PDCpreviousDayClose = 0;
   g_staticMarketContext.PDdate              = "";
   string prevDayStr = GetPreviousTradingDayDateString(referenceDayStart);
   if(StringLen(prevDayStr) == 0) return;
   g_staticMarketContext.PDdate = prevDayStr;
   string parts[];
   if(StringSplit(prevDayStr, '.', parts) != 3) return;  // YYYY.MM.DD
   int y = (int)StringToInteger(parts[0]);
   int mo = (int)StringToInteger(parts[1]);
   int d = (int)StringToInteger(parts[2]);
   MqlDateTime mtPrev = {0};
   mtPrev.year = y; mtPrev.mon = mo; mtPrev.day = d;
   datetime prevDayStart = StructToTime(mtPrev);
   datetime prevDayEnd   = prevDayStart + 86400;

   // PDO = 15:30 bar open, PDC = 22:00 bar close — use same bar indexing as chart (iBarShift + iOpen/iClose)
   datetime bar1530 = prevDayStart + 15*3600 + 30*60;
   datetime bar2200 = prevDayStart + 22*3600;
   int shift1530 = iBarShift(_Symbol, PERIOD_M30, bar1530, false);
   int shift2200 = iBarShift(_Symbol, PERIOD_M30, bar2200, false);
   if(shift1530 >= 0)
      g_staticMarketContext.PDOpreviousDayOpen = iOpen(_Symbol, PERIOD_M30, shift1530);
   if(shift2200 >= 0)
      g_staticMarketContext.PDCpreviousDayClose = iClose(_Symbol, PERIOD_M30, shift2200);

   // PDH/PDL = max High / min Low over the day — use same bar indexing as chart (iterate shifts for the day)
   int shiftDayStart = iBarShift(_Symbol, PERIOD_M30, prevDayStart, false);
   int shiftDayEnd   = iBarShift(_Symbol, PERIOD_M30, prevDayEnd - 1, false);  // last bar with time < prevDayEnd
   if(shiftDayStart >= 0 && shiftDayEnd >= 0)
   {
      double pdh = -1e300, pdl = 1e300;
      for(int s = shiftDayEnd; s <= shiftDayStart; s++)
      {
         double h = iHigh(_Symbol, PERIOD_M30, s);
         double l = iLow(_Symbol, PERIOD_M30, s);
         if(h > pdh) pdh = h;
         if(l < pdl) pdl = l;
      }
      if(pdh > -1e300) g_staticMarketContext.PDHpreviousDayHigh = pdh;
      if(pdl < 1e300) g_staticMarketContext.PDLpreviousDayLow = pdl;
   }
}

//+------------------------------------------------------------------+
//| Load levels CSV from Terminal/Common/Files. Format: start,end,levelPrice,categories,tag (header on first line). |
//+------------------------------------------------------------------+
bool LoadLevels()
{
   g_levelsCount = 0;
   int fh = FileOpen(InpLevelsFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE) return false;
   string line = FileReadString(fh);  // skip header
   while(!FileIsEnding(fh) && g_levelsCount < MAX_LEVEL_ROWS)
   {
      line = FileReadString(fh);
      if(StringLen(line) == 0) continue;
      string parts[];
      if(StringSplit(line, ',', parts) < 5) continue;
      g_levels[g_levelsCount].startStr   = parts[0];
      g_levels[g_levelsCount].endStr     = parts[1];
      g_levels[g_levelsCount].levelPrice = StringToDouble(parts[2]);
      g_levels[g_levelsCount].categories = parts[3];
      g_levels[g_levelsCount].tag        = parts[4];
      g_levelsCount++;
   }
   FileClose(fh);
   return (g_levelsCount > 0);
}

//+------------------------------------------------------------------+
//| Get newway_Diff_CloseToLevel from g_levelsExpanded at barTime. Key = levelPrice OR tag (use one, pass 0 or "" for the other). |
//+------------------------------------------------------------------+
double GetLevelExpandedDiff(double levelPrice, string tag, datetime barTime)
{
   for(int e = 0; e < g_levelsExpandedCount; e++)
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
//+------------------------------------------------------------------+
string GetHighestDiffInWindowString(double levelPrice, int barK, int windowBars, bool wantUp)
{
   int startBar = MathMax(0, barK - windowBars + 1);
   if(wantUp)
   {
      double maxUp = -1e300;
      for(int j = startBar; j <= barK; j++)
      {
         if(g_m1Rates[j].high > levelPrice)
         {
            double d = g_m1Rates[j].high - levelPrice;
            if(d > maxUp) maxUp = d;
         }
      }
      return (maxUp > -1e300) ? DoubleToString(maxUp, _Digits) : "never";
   }
   else
   {
      double maxDown = -1e300;
      for(int j = startBar; j <= barK; j++)
      {
         if(g_m1Rates[j].low < levelPrice)
         {
            double d = levelPrice - g_m1Rates[j].low;
            if(d > maxDown) maxDown = d;
         }
      }
      return (maxDown > -1e300) ? DoubleToString(maxDown, _Digits) : "never";
   }
}

//+------------------------------------------------------------------+
//| Pull 1M for current day into g_m1Rates and build g_levelsExpanded. Call every new bar so data is always in memory. |
//+------------------------------------------------------------------+
void UpdateDayM1AndLevelsExpanded()
{
   datetime dayStart = g_lastTickTime - (g_lastTickTime % 86400);
   string dateStr = TimeToString(dayStart, TIME_DATE);  // YYYY.MM.DD (MT5 default)
   string dayKey = dateStr;  // same format for level date range comparison (levels CSV should use YYYY.MM.DD for start/end)
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

   // Build levelsExpanded from g_m1Rates
   g_levelsExpandedCount = 0;
   for(int i = 0; i < g_levelsCount && g_levelsExpandedCount < MAX_LEVELS_EXPANDED; i++)
   {
      if(g_levels[i].startStr > dayKey || dayKey > g_levels[i].endStr) continue;
      g_levelsExpanded[g_levelsExpandedCount].levelPrice = g_levels[i].levelPrice;
      g_levelsExpanded[g_levelsExpandedCount].tag        = g_levels[i].tag;
      g_levelsExpanded[g_levelsExpandedCount].count      = g_barsInDay;
      ArrayResize(g_levelsExpanded[g_levelsExpandedCount].diffs, g_barsInDay);
      ArrayResize(g_levelsExpanded[g_levelsExpandedCount].times, g_barsInDay);
      for(int k = 0; k < g_barsInDay; k++)
      {
         g_levelsExpanded[g_levelsExpandedCount].times[k] = g_m1Rates[k].time;
         g_levelsExpanded[g_levelsExpandedCount].diffs[k] = g_m1Rates[k].close - g_levelsExpanded[g_levelsExpandedCount].levelPrice;
      }
      g_levelsExpandedCount++;
   }

   // Per-bar: level above candle high, level below candle low, session (available globally; logged in 21:59-22:00)
   for(int k = 0; k < g_barsInDay; k++)
   {
      double aboveH = 0;
      double belowL = 0;
      for(int e = 0; e < g_levelsExpandedCount; e++)
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
//| Load deals for current day, reject DEAL_TYPE_BALANCE, group by magic, pair IN/OUT into g_tradeResults. Call from loop2. |
//+------------------------------------------------------------------+
void UpdateTradeResultsForDay()
{
   g_tradeResultsCount = 0;
   g_dealCount = 0;
   datetime dayStart = g_lastTickTime - (g_lastTickTime % 86400);
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
            r.bothComments = g_dealComment[g_inIdx[p]] + "| " + g_dealComment[o];
         }
         else
         {
            r.endTime   = 0;
            r.priceEnd  = 0;
            r.priceDiff = 0;
            r.profit    = 0;
            r.reason    = 0;
            r.bothComments = g_dealComment[g_inIdx[p]] + "| NOT_FOUND";
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
long BuildMagicForTradeType3(datetime tickTime)
{
   MqlDateTime dt;
   TimeToStruct(tickTime, dt);
   string dateStr = IntegerToString(dt.year) +
                    StringFormat("%02d", dt.mon) +
                    StringFormat("%02d", dt.day);
   string magicStr = StringFormat("%d%s", (int)TRADE_TYPE_MARKET_TEST, dateStr);
   return (long)StringToInteger(magicStr);
}

//+------------------------------------------------------------------+
//| Build magic for trade type 4 (15:30 smash). No level; date only (id 4 + YYYYMMDD). |
//+------------------------------------------------------------------+
long BuildMagicForTradeType4(datetime tickTime)
{
   MqlDateTime dt;
   TimeToStruct(tickTime, dt);
   string dateStr = IntegerToString(dt.year) +
                    StringFormat("%02d", dt.mon) +
                    StringFormat("%02d", dt.day);
   string magicStr = StringFormat("%d%s", (int)TRADE_TYPE_15_30_SMASH, dateStr);
   return (long)StringToInteger(magicStr);
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
//| B_TradeLog filename = B_TradeLog_(id). e.g. 2026.03.03_B_TradeLog_3.txt |
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
   return StringFormat("%s_B_TradeLog_%s.txt", dateStr, tradeType);
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
   datetime now = g_lastTickTime;
   string dateStr = TimeToString(now, TIME_DATE);
   
   string activeLevelsFile = dateStr + "-Day_activeLevels.txt";
   int fh1 = FileOpen(activeLevelsFile, FILE_WRITE | FILE_TXT);
   if(fh1 != INVALID_HANDLE)
   {
      datetime today = now - (now % 86400);
      for(int i=0; i<ArraySize(levels); i++)
      {
         if(levels[i].validFrom <= today && levels[i].validTo >= today)
         {
            FileWrite(fh1, "levelNo=" + IntegerToString(i) + " name=" + levels[i].baseName + 
                      " price=" + DoubleToString(levels[i].price, _Digits) + 
                      " count=" + IntegerToString(levels[i].count) + 
                      " contacts=" + IntegerToString(levels[i].approxContactCount) + 
                      " bias=" + DoubleToString(levels[i].dailyBias, 0) + 
                      " bounces=" + IntegerToString(levels[i].bounceCount));
         }
      }
      FileClose(fh1);
   }
   
   string accountFile = dateStr + "-Day_EOD_accountSummary.txt";
   int fh2 = FileOpen(accountFile, FILE_WRITE | FILE_TXT);
   if(fh2 != INVALID_HANDLE)
   {
      FileWrite(fh2, "balance=" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
      FileWrite(fh2, "equity=" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
      FileWrite(fh2, "freeMargin=" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));
      FileWrite(fh2, "marginLevel=" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 1));
      FileWrite(fh2, "openPositions=" + IntegerToString(PositionsTotal()));
      FileWrite(fh2, "pendingOrders=" + IntegerToString(OrdersTotal()));
      FileClose(fh2);
   }
   
   string ordersFile = dateStr + "-AllHistoryOrders.txt";
   int fh3 = FileOpen(ordersFile, FILE_WRITE | FILE_TXT);
   if(fh3 != INVALID_HANDLE)
   {
      HistorySelect(0, g_lastTickTime);
      int totalHist = HistoryOrdersTotal();
      for(int i=0; i<totalHist; i++)
      {
         ulong ticket = HistoryOrderGetTicket(i);
         if(ticket == 0) continue;
         
         datetime orderTime = (datetime)HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP);
         if(orderTime < dateWhenAlgoTradeStarted) continue;
         
         FileWrite(fh3, "ticket=" + IntegerToString((long)ticket) + 
                   " symbol=" + HistoryOrderGetString(ticket, ORDER_SYMBOL) + 
                   " magic=" + IntegerToString((long)HistoryOrderGetInteger(ticket, ORDER_MAGIC)) +
                   " timeSetup=" + TimeToString((datetime)HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP), TIME_DATE|TIME_SECONDS) +
                   " state=" + EnumToString((ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket, ORDER_STATE)) +
                    " type=" + EnumToString((ENUM_ORDER_TYPE)HistoryOrderGetInteger(ticket, ORDER_TYPE)) + 
                   " reason=" + EnumToString((ENUM_ORDER_REASON)HistoryOrderGetInteger(ticket, ORDER_REASON)) + 
                   " volume=" + DoubleToString(HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL), 2) + 
                   " priceOpen=" + DoubleToString(HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN), _Digits) + 
                   " priceCurrent=" + DoubleToString(HistoryOrderGetDouble(ticket, ORDER_PRICE_CURRENT), _Digits) + 
                   " priceStopLoss=" + DoubleToString(HistoryOrderGetDouble(ticket, ORDER_SL), _Digits) +
                   " priceTakeProfit=" + DoubleToString(HistoryOrderGetDouble(ticket, ORDER_TP), _Digits) +
                   " timeExpiration=" + TimeToString((datetime)HistoryOrderGetInteger(ticket, ORDER_TIME_EXPIRATION), TIME_DATE|TIME_SECONDS) +
                   " activationPrice=" + DoubleToString(HistoryOrderGetDouble(ticket, ORDER_PRICE_STOPLIMIT), _Digits) +
                   " comment=" + HistoryOrderGetString(ticket, ORDER_COMMENT));
      }
      FileClose(fh3);
   }
   
   string dealsFile = dateStr + "-AllHistoryDeals.txt";
   int fh4 = FileOpen(dealsFile, FILE_WRITE | FILE_TXT);
   if(fh4 != INVALID_HANDLE)
   {
      int totalDeals = HistoryDealsTotal();
      for(int i=0; i<totalDeals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         
         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         if(dealTime < dateWhenAlgoTradeStarted) continue;
         
         FileWrite(fh4, "ticket=" + IntegerToString((long)ticket) + 
                   " symbol=" + HistoryDealGetString(ticket, DEAL_SYMBOL) + 
                   " magic=" + IntegerToString((long)HistoryDealGetInteger(ticket, DEAL_MAGIC)) +
                   " time=" + TimeToString((datetime)HistoryDealGetInteger(ticket, DEAL_TIME), TIME_DATE|TIME_SECONDS) +
                   " entry=" + EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY)) +
                   " type=" + EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE)) + 
                   " reason=" + EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON)) +
                   " volume=" + DoubleToString(HistoryDealGetDouble(ticket, DEAL_VOLUME), 2) + 
                   " price=" + DoubleToString(HistoryDealGetDouble(ticket, DEAL_PRICE), _Digits) + 
                   " profit=" + DoubleToString(HistoryDealGetDouble(ticket, DEAL_PROFIT), 2) + 
                   " ticketOrder=" + IntegerToString((long)HistoryDealGetInteger(ticket, DEAL_ORDER)) +
                   " comment=" + HistoryDealGetString(ticket, DEAL_COMMENT));
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

   int fh = OpenOrCreateForAppend(fname);
   if(fh != INVALID_HANDLE)
   {
      string acct = StringFormat("bal=%.2f eq=%.2f", AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
      string line = "time=" + TimeToString(eventTime, TIME_DATE | TIME_SECONDS) + " " + acct;
      if(StringLen(orderKind) > 0) line += " " + orderKind;
      if(orderPrice > 0)
         line += " orderPrice=" + DoubleToString(NormalizeDouble(orderPrice, _Digits), _Digits);
      line += " " + eventType;
      if(tpPrice > 0 && slPrice > 0)
         line += " tp=" + DoubleToString(NormalizeDouble(tpPrice, _Digits), _Digits) +
                 " sl=" + DoubleToString(NormalizeDouble(slPrice, _Digits), _Digits);
      if(expirationMinutes > 0)
         line += " exp=" + IntegerToString(expirationMinutes);
      if(orderTicket > 0)
         line += " orderTicket=" + IntegerToString(orderTicket);
      if(dealTicket > 0)
         line += " dealTicket=" + IntegerToString(dealTicket);
      if(positionTicket > 0)
         line += " positionTicket=" + IntegerToString(positionTicket);
      if(dealReason != (ENUM_DEAL_REASON)0)
         line += " dealReason=" + IntegerToString((int)dealReason);
      if(StringLen(comment) > 0)
         line += " comment=" + comment;
      line += " magic=" + IntegerToString((long)magic);
      FileWrite(fh, line);
      FileClose(fh);
   }
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

   g_tradeConfig[TRADE_TYPE_15_30_SMASH].useLevel = true;
   g_tradeConfig[TRADE_TYPE_15_30_SMASH].usePrice = true;
   g_tradeConfig[TRADE_TYPE_15_30_SMASH].useTimeFilter = false;
   g_tradeConfig[TRADE_TYPE_15_30_SMASH].bannedRangesStr = "";

   EventSetTimer(1);   // 1 second timer for candle-close detection

   if(!LoadCalendar())
      Print("Calendar file not loaded: ", InpCalendarFile, " (place CSV in Terminal/Common/Files)");
   else
      Print("Calendar loaded: ", g_calendarCount, " rows from ", InpCalendarFile);

   if(!LoadLevels())
   {
      Print("Levels file not loaded: ", InpLevelsFile, " (place CSV in Terminal/Common/Files)");
      return(INIT_FAILED);
   }
   Print("Levels loaded: ", g_levelsCount, " rows from ", InpLevelsFile);

   datetime today = TimeCurrent() - (TimeCurrent() % 86400);
   UpdateStaticMarketContext(today);

   // Hardcoded levels imported from levelsinfo.txt in chronological order
   AddLevel("2026.02.16_SmashWeekly", 6890, "2026.02.16 00:00", "2026.02.20 23:59", "weekly,smash");
   AddLevel("2026.02.16_weeklyUp1", 6960, "2026.02.16 00:00", "2026.02.20 23:59", "weekly,weeklyUp1");
   AddLevel("2026.02.16_weeklyUp2", 7010, "2026.02.16 00:00", "2026.02.20 23:59", "weekly,weeklyUp2");
   AddLevel("2026.02.16_weeklyUp3", 7045, "2026.02.16 00:00", "2026.02.20 23:59", "weekly,weeklyUp3");
   AddLevel("2026.02.16_weeklyUp4", 7092, "2026.02.16 00:00", "2026.02.20 23:59", "weekly,weeklyUp4");
   AddLevel("2026.02.16_weeklyUp5", 7145, "2026.02.16 00:00", "2026.02.20 23:59", "weekly,weeklyUp5");
   AddLevel("2026.02.16_weeklyDown1", 6805, "2026.02.16 00:00", "2026.02.20 23:59", "weekly,weeklyDown1");
   AddLevel("2026.02.16_weeklyDown2", 6705, "2026.02.16 00:00", "2026.02.20 23:59", "weekly,weeklyDown2");
   AddLevel("2026.02.16_weeklyDown3", 6670, "2026.02.16 00:00", "2026.02.20 23:59", "weekly,weeklyDown3");
   AddLevel("2026.02.16_weeklyDown4", 6592, "2026.02.16 00:00", "2026.02.20 23:59", "weekly,weeklyDown4");

   AddLevel("2026.02.18_SmashDaily", 6867, "2026.02.18 00:00", "2026.02.18 23:59", "daily,wednesday,smash");
   AddLevel("2026.02.18_dailyUp1", 6890, "2026.02.18 00:00", "2026.02.18 23:59", "daily,wednesday,dailyUp1");
   AddLevel("2026.02.18_dailyUp2", 6927, "2026.02.18 00:00", "2026.02.18 23:59", "daily,wednesday,dailyUp2");
   AddLevel("2026.02.18_dailyDown1", 6842, "2026.02.18 00:00", "2026.02.18 23:59", "daily,wednesday,dailyDown1");
   AddLevel("2026.02.18_dailyDown2", 6805, "2026.02.18 00:00", "2026.02.18 23:59", "daily,wednesday,dailyDown2");
   AddLevel("2026.02.18_dailyDown3", 6780, "2026.02.18 00:00", "2026.02.18 23:59", "daily,wednesday,dailyDown3");

   AddLevel("2026.02.19_SmashDaily", 6906, "2026.02.19 00:00", "2026.02.19 23:59", "daily,thursday,smash");
   AddLevel("2026.02.19_dailyUp1", 6927, "2026.02.19 00:00", "2026.02.19 23:59", "daily,thursday,dailyUp1");
   AddLevel("2026.02.19_dailyUp2", 6960, "2026.02.19 00:00", "2026.02.19 23:59", "daily,thursday,dailyUp2");
   AddLevel("2026.02.19_dailyDown1", 6875, "2026.02.19 00:00", "2026.02.19 23:59", "daily,thursday,dailyDown1");
   AddLevel("2026.02.19_dailyDown2", 6842, "2026.02.19 00:00", "2026.02.19 23:59", "daily,thursday,dailyDown2");

   AddLevel("2026.02.20_SmashDaily", 6860, "2026.02.20 00:00", "2026.02.20 23:59", "daily,friday,smash");
   AddLevel("2026.02.20_dailyUp1", 6890, "2026.02.20 00:00", "2026.02.20 23:59", "daily,friday,dailyUp1");
   AddLevel("2026.02.20_dailyUp2", 6906, "2026.02.20 00:00", "2026.02.20 23:59", "daily,friday,dailyUp2");
   AddLevel("2026.02.20_dailyUp3", 6927, "2026.02.20 00:00", "2026.02.20 23:59", "daily,friday,dailyUp3");
   AddLevel("2026.02.20_dailyDown1", 6842, "2026.02.20 00:00", "2026.02.20 23:59", "daily,friday,dailyDown1");
   AddLevel("2026.02.20_dailyDown2", 6805, "2026.02.20 00:00", "2026.02.20 23:59", "daily,friday,dailyDown2");

   AddLevel("2026.02.23_SmashWeekly", 6960, "2026.02.23 00:00", "2026.02.27 23:59", "weekly,smash");
   AddLevel("2026.02.23_weeklyUp1", 7031, "2026.02.23 00:00", "2026.02.27 23:59", "weekly,weeklyUp1");
   AddLevel("2026.02.23_weeklyUp2", 7043, "2026.02.23 00:00", "2026.02.27 23:59", "weekly,weeklyUp2");
   AddLevel("2026.02.23_weeklyUp3", 7080, "2026.02.23 00:00", "2026.02.27 23:59", "weekly,weeklyUp3");
   AddLevel("2026.02.23_weeklyUp4", 7110, "2026.02.23 00:00", "2026.02.27 23:59", "weekly,weeklyUp4");
   AddLevel("2026.02.23_weeklyUp5", 7145, "2026.02.23 00:00", "2026.02.27 23:59", "weekly,weeklyUp5");
   AddLevel("2026.02.23_weeklyUp6", 7200, "2026.02.23 00:00", "2026.02.27 23:59", "weekly,weeklyUp6");
   AddLevel("2026.02.23_weeklyDown1", 6890, "2026.02.23 00:00", "2026.02.27 23:59", "weekly,weeklyDown1");
   AddLevel("2026.02.23_weeklyDown2", 6805, "2026.02.23 00:00", "2026.02.27 23:59", "weekly,weeklyDown2");
   AddLevel("2026.02.23_weeklyDown3", 6775, "2026.02.23 00:00", "2026.02.27 23:59", "weekly,weeklyDown3");
   AddLevel("2026.02.23_weeklyDown4", 6705, "2026.02.23 00:00", "2026.02.27 23:59", "weekly,weeklyDown4");
   AddLevel("2026.02.23_weeklyDown5", 6670, "2026.02.23 00:00", "2026.02.27 23:59", "weekly,weeklyDown5");

   AddLevel("2026.02.23_SmashDaily", 6910, "2026.02.23 00:00", "2026.02.23 23:59", "daily,smash");
   AddLevel("2026.02.23_dailyUp1", 6927, "2026.02.23 00:00", "2026.02.23 23:59", "daily,dailyUp1");
   AddLevel("2026.02.23_dailyUp2", 6960, "2026.02.23 00:00", "2026.02.23 23:59", "daily,dailyUp2");
   AddLevel("2026.02.23_dailyUp3", 6998, "2026.02.23 00:00", "2026.02.23 23:59", "daily,dailyUp3");
   AddLevel("2026.02.23_dailyDown1", 6890, "2026.02.23 00:00", "2026.02.23 23:59", "daily,dailyDown1");
   AddLevel("2026.02.23_dailyDown2", 6860, "2026.02.23 00:00", "2026.02.23 23:59", "daily,dailyDown2");

   AddLevel("2026.02.24_SmashDaily", 6869, "2026.02.24 00:00", "2026.02.24 23:59", "daily,smash");
   AddLevel("2026.02.24_dailyUp1", 6893, "2026.02.24 00:00", "2026.02.24 23:59", "daily,dailyUp1");
   AddLevel("2026.02.24_dailyUp2", 6927, "2026.02.24 00:00", "2026.02.24 23:59", "daily,dailyUp2");
   AddLevel("2026.02.24_dailyDown1", 6836, "2026.02.24 00:00", "2026.02.24 23:59", "daily,dailyDown1");
   AddLevel("2026.02.24_dailyDown2", 6805, "2026.02.24 00:00", "2026.02.24 23:59", "daily,dailyDown2");
   AddLevel("2026.02.24_dailyDown3", 6775, "2026.02.24 00:00", "2026.02.24 23:59", "daily,dailyDown3");

   AddLevel("2026.02.25_SmashDaily", 6894, "2026.02.25 00:00", "2026.02.25 23:59", "daily,smash");
   AddLevel("2026.02.25_dailyUp1", 6911, "2026.02.25 00:00", "2026.02.25 23:59", "daily,dailyUp1");
   AddLevel("2026.02.25_dailyUp2", 6927, "2026.02.25 00:00", "2026.02.25 23:59", "daily,dailyUp2");
   AddLevel("2026.02.25_dailyUp3", 6960, "2026.02.25 00:00", "2026.02.25 23:59", "daily,dailyUp3");
   AddLevel("2026.02.25_dailyDown1", 6869, "2026.02.25 00:00", "2026.02.25 23:59", "daily,dailyDown1");
   AddLevel("2026.02.25_dailyDown2", 6833, "2026.02.25 00:00", "2026.02.25 23:59", "daily,dailyDown2");

   AddLevel("2026.02.26_SmashDaily", 6960, "2026.02.26 00:00", "2026.02.26 23:59", "daily,smash");
   AddLevel("2026.02.26_dailyUp1", 6976, "2026.02.26 00:00", "2026.02.26 23:59", "daily,dailyUp1");
   AddLevel("2026.02.26_dailyUp2", 6993, "2026.02.26 00:00", "2026.02.26 23:59", "daily,dailyUp2");
   AddLevel("2026.02.26_dailyUp3", 7017, "2026.02.26 00:00", "2026.02.26 23:59", "daily,dailyUp3");
   AddLevel("2026.02.26_dailyDown1", 6948, "2026.02.26 00:00", "2026.02.26 23:59", "daily,dailyDown1");
   AddLevel("2026.02.26_dailyDown2", 6927, "2026.02.26 00:00", "2026.02.26 23:59", "daily,dailyDown2");
   AddLevel("2026.02.26_dailyDown3", 6912, "2026.02.26 00:00", "2026.02.26 23:59", "daily,dailyDown3");

   AddLevel("2026.02.27_SmashDaily", 6927, "2026.02.27 00:00", "2026.02.27 23:59", "daily,smash");
   AddLevel("2026.02.27_dailyUp1", 6960, "2026.02.27 00:00", "2026.02.27 23:59", "daily,dailyUp1");
   AddLevel("2026.02.27_dailyUp2", 6890, "2026.02.27 00:00", "2026.02.27 23:59", "daily,dailyUp2");
   AddLevel("2026.02.27_dailyDown1", 6904, "2026.02.27 00:00", "2026.02.27 23:59", "daily,dailyDown1");
   AddLevel("2026.02.27_dailyDown2", 6880, "2026.02.27 00:00", "2026.02.27 23:59", "daily,dailyDown2");
   AddLevel("2026.02.27_dailyDown3", 6849, "2026.02.27 00:00", "2026.02.27 23:59", "daily,dailyDown3");

   AddLevel("2026.03.02_SmashWeekly", 6880, "2026.03.02 00:00", "2026.03.06 23:59", "weekly,smash");
   AddLevel("2026.03.02_weeklyUp1", 7030, "2026.03.02 00:00", "2026.03.06 23:59", "weekly,weeklyUp1");
   AddLevel("2026.03.02_weeklyUp2", 7060, "2026.03.02 00:00", "2026.03.06 23:59", "weekly,weeklyUp2");
   AddLevel("2026.03.02_weeklyUp3", 7120, "2026.03.02 00:00", "2026.03.06 23:59", "weekly,weeklyUp3");
   AddLevel("2026.03.02_weeklyUp4", 7160, "2026.03.02 00:00", "2026.03.06 23:59", "weekly,weeklyUp4");
   AddLevel("2026.03.02_weeklyUp5", 7960, "2026.03.02 00:00", "2026.03.06 23:59", "weekly,weeklyUp5");
   AddLevel("2026.03.02_weeklyDown1", 6805, "2026.03.02 00:00", "2026.03.06 23:59", "weekly,weeklyDown1");
   AddLevel("2026.03.02_weeklyDown2", 6730, "2026.03.02 00:00", "2026.03.06 23:59", "weekly,weeklyDown2");
   AddLevel("2026.03.02_weeklyDown3", 6700, "2026.03.02 00:00", "2026.03.06 23:59", "weekly,weeklyDown3");
   AddLevel("2026.03.02_weeklyDown4", 6670, "2026.03.02 00:00", "2026.03.06 23:59", "weekly,weeklyDown4");
   AddLevel("2026.03.02_weeklyDown5", 6592, "2026.03.02 00:00", "2026.03.06 23:59", "weekly,weeklyDown5");

   AddLevel("2026.03.02_SmashDaily", 6880, "2026.03.02 00:00", "2026.03.02 23:59", "daily,smash");
   AddLevel("2026.03.02_dailyUp1", 6904, "2026.03.02 00:00", "2026.03.02 23:59", "daily,dailyUp1");
   AddLevel("2026.03.02_dailyUp2", 6927, "2026.03.02 00:00", "2026.03.02 23:59", "daily,dailyUp2");
   AddLevel("2026.03.02_dailyUp3", 6960, "2026.03.02 00:00", "2026.03.02 23:59", "daily,dailyUp3");
   AddLevel("2026.03.02_dailyDown1", 6852, "2026.03.02 00:00", "2026.03.02 23:59", "daily,dailyDown1");
   AddLevel("2026.03.02_dailyDown2", 6829, "2026.03.02 00:00", "2026.03.02 23:59", "daily,dailyDown2");

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
      comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
      kindStr = ((ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? "market_buy" : "market_sell";
   }

   string tradeType = GetTradeTypeFromMagic(HistoryDealGetInteger(trans.deal, DEAL_MAGIC));
   if(StringLen(tradeType) == 0) return;

   datetime fillTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   if(fillTime == 0) fillTime = g_lastTickTime;
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
   if(closeTime == 0) closeTime = g_lastTickTime;

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

   int fh = FileOpen(InpSummaryFile, FILE_WRITE|FILE_TXT);
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
//| OnTimer(1s): detect new bar, load closed bar from history, run FinalizeCurrentCandle. OnTick only updates g_lastTickTime. |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_lastTickTime = TimeCurrent();

   // Daily summary: once per day at specified hour+minute
   MqlDateTime mt;
   TimeToStruct(g_lastTickTime, mt);
   datetime today = g_lastTickTime - (g_lastTickTime % 86400);
   if(mt.hour == HourForDailySummary && mt.min == MinuteForDailySummary && today != lastDailySummaryDay)
   {
      WriteDailySummary();
      lastDailySummaryDay = today;
   }

   // Candle-close detection: use chart period; bar that just closed = index 1 in history
   datetime barNow = iTime(_Symbol, _Period, 0);
   if(barNow == g_lastBarTime) return;

   g_lastBarTime = barNow;
   // Bar that just closed (shift 1)
   current_candle_time = iTime(_Symbol, _Period, 1);
   candle_open  = iOpen(_Symbol, _Period, 1);
   candle_high  = iHigh(_Symbol, _Period, 1);
   candle_low   = iLow(_Symbol, _Period, 1);
   candle_close = iClose(_Symbol, _Period, 1);

   FinalizeCurrentCandle();

   // --- Price, levels, levelsExpanded: always update in memory every new bar (for trade logic)
   UpdateDayM1AndLevelsExpanded();

   // --- Trade results for the day (deals IN/OUT paired by magic; available globally)
   UpdateTradeResultsForDay();

   // --- Per-candle day progress (trades closed by each candle close time)
   UpdateDayProgress();

   // --- Static market context: pull on new day between 00:00 and 00:03 (closed candle time)
   MqlDateTime mtBar;
   TimeToStruct(current_candle_time, mtBar);
   int minOfDayBar = mtBar.hour * 60 + mtBar.min;
   if(minOfDayBar >= 0 && minOfDayBar <= 3 && g_barsInDay > 0)
      UpdateStaticMarketContext(g_m1DayStart);

   // --- Logging only in time window (performance)
   if(InpTestingPullM1History)
   {
      MqlDateTime mtTest;
      TimeToStruct(g_lastTickTime, mtTest);
      int minOfDay = mtTest.hour * 60 + mtTest.min;
      datetime dayStart = g_lastTickTime - (g_lastTickTime % 86400);
      string dateStr = TimeToString(dayStart, TIME_DATE);
      bool inLogWindow = (minOfDay >= 21*60+58 && minOfDay <= 22*60+0);  // 21:58, 21:59, 22:00 (last bar may be 21:58 on Friday)
      bool catchUpWindow = (minOfDay > 22*60+0 && minOfDay <= 23*60+59);  // past 22:00, same day: write if file missing
      if((inLogWindow || catchUpWindow) && g_barsInDay > 0)
      {
         string logName = dateStr + "_testing_pullinghistory.txt";

         // Log pullinghistory from g_m1Rates (only once per day; if file missing, write again)
         if(!FileIsExist(logName))
         {
            int fh = FileOpen(logName, FILE_WRITE | FILE_TXT);
            if(fh != INVALID_HANDLE)
            {
               for(int k = 0; k < g_barsInDay; k++)
               {
                  FileWrite(fh, TimeToString(g_m1Rates[k].time, TIME_DATE|TIME_MINUTES),
                     " O=", DoubleToString(g_m1Rates[k].open, _Digits),
                     " H=", DoubleToString(g_m1Rates[k].high, _Digits),
                     " L=", DoubleToString(g_m1Rates[k].low, _Digits),
                     " C=", DoubleToString(g_m1Rates[k].close, _Digits),
                     " levelAboveH=", DoubleToString(g_levelAboveH[k], 0),
                     " levelBelowL=", DoubleToString(g_levelBelowL[k], 0),
                     " session=", g_session[k],
                     " dayWinRate=", DoubleToString(g_dayProgress[k].dayWinRate, 2),
                     " dayTradesCount=", IntegerToString(g_dayProgress[k].dayTradesCount),
                     " dayPointsSum=", DoubleToString(g_dayProgress[k].dayPointsSum, _Digits),
                     " dayProfitSum=", DoubleToString(g_dayProgress[k].dayProfitSum, 2),
                     " ONwinRate=", DoubleToString(g_dayProgress[k].ONwinRate, 2),
                     " ONtradeCount=", IntegerToString(g_dayProgress[k].ONtradeCount),
                     " ONpointsSum=", DoubleToString(g_dayProgress[k].ONpointsSum, _Digits),
                     " ONprofitSum=", DoubleToString(g_dayProgress[k].ONprofitSum, 2),
                     " RTHwinRate=", DoubleToString(g_dayProgress[k].RTHwinRate, 2),
                     " RTHtradeCount=", IntegerToString(g_dayProgress[k].RTHtradeCount),
                     " RTHpointsSum=", DoubleToString(g_dayProgress[k].RTHpointsSum, _Digits),
                     " RTHprofitSum=", DoubleToString(g_dayProgress[k].RTHprofitSum, 2),
                     " PDOpreviousDayOpen=", DoubleToString(g_staticMarketContext.PDOpreviousDayOpen, _Digits),
                     " PDHpreviousDayHigh=", DoubleToString(g_staticMarketContext.PDHpreviousDayHigh, _Digits),
                     " PDLpreviousDayLow=", DoubleToString(g_staticMarketContext.PDLpreviousDayLow, _Digits),
                     " PDCpreviousDayClose=", DoubleToString(g_staticMarketContext.PDCpreviousDayClose, _Digits),
                     " PDdate=", g_staticMarketContext.PDdate);
               }
               FileClose(fh);
            }
         }

         // Trade results CSV: (date)_summaryZ_tradeResults_ALL_Day.csv (only once; if missing, write again)
         string csvName = dateStr + "_summaryZ_tradeResults_ALL_Day.csv";
         if(!FileIsExist(csvName))
         {
            int fhTr = FileOpen(csvName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_CSV);
            if(fhTr != INVALID_HANDLE)
            {
               FileWrite(fhTr, "symbol", "startTime", "endTime", "session", "magic", "priceStart", "priceEnd", "priceDiff", "profit", "type", "reason", "volume", "bothComments");
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
                     DoubleToString(r.volume, 2), r.bothComments);
               }
               FileClose(fhTr);
            }
         }

         // Per-level files (only once per file per day; if missing, write again)
         int recentPriceArgument = 5;
         for(int e = 0; e < g_levelsExpandedCount; e++)
         {
            string levelFile = dateStr + "_testinglevelsplus_" + DoubleToString(g_levelsExpanded[e].levelPrice, 0) + "_" + g_levelsExpanded[e].tag + ".txt";
            if(!FileIsExist(levelFile))
            {
               int fhL = FileOpen(levelFile, FILE_WRITE | FILE_TXT);
               if(fhL != INVALID_HANDLE)
               {
                  double lvl = g_levelsExpanded[e].levelPrice;
                  for(int k = 0; k < g_levelsExpanded[e].count; k++)
                  {
                     string highestUp   = GetHighestDiffInWindowString(lvl, k, recentPriceArgument, true);
                     string highestDown = GetHighestDiffInWindowString(lvl, k, recentPriceArgument, false);
                     FileWrite(fhL, TimeToString(g_levelsExpanded[e].times[k], TIME_DATE|TIME_MINUTES),
                        " newway_Diff_CloseToLevel=", DoubleToString(g_levelsExpanded[e].diffs[k], _Digits),
                        " HighestDiffUp=", highestUp,
                        " HighestDiffUpRange=", IntegerToString(recentPriceArgument),
                        " HighestDiffDown=", highestDown,
                        " HighestDiffDownRange=", IntegerToString(recentPriceArgument));
                  }
                  FileClose(fhL);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTick: only update g_lastTickTime when a tick arrives (for accurate time in trade/expiration). |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick))
      g_lastTickTime = tick.time;
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
//| Trade type 4: as soon as 15:29 bar closed; if |price - daily smash level| < MaxDistancePoints, market buy. TP/SL in pips. |
//| Daily smash = first level eligible for this day (valid range) that has tag "smash". |
//+------------------------------------------------------------------+
void EvaluateTradeType4(datetime candleTime)
{
   MqlDateTime mt;
   TimeToStruct(candleTime, mt);
   if(mt.hour != 15 || mt.min != 29) return;

   int idx = -1;
   for(int i = 0; i < ArraySize(levels); i++)
   {
      if(candleTime < levels[i].validFrom || candleTime > levels[i].validTo) continue;
      if(StringFind(levels[i].tagsCSV, "smash") < 0) continue;
      idx = i;
      break;
   }
   if(idx < 0) return;

   double smashLevel = levels[idx].price;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double maxDistPrice = T_tradeType4_MaxDistancePoints * point;
   if(MathAbs(candle_close - smashLevel) >= maxDistPrice) return;

   long magic = BuildMagicForTradeType4(candleTime);
   if(CountOrdersAndPositionsForMagic(magic) >= Max_OrdersPerMagic) return;

   double pip = PipSize();
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = NormalizeDouble(ask - T_tradeType4_SLPips * pip, _Digits);
   double tp = NormalizeDouble(ask + T_tradeType4_TPPips * pip, _Digits);
   string orderComment = StringFormat("%d %.0f %.0f %.0f", (int)TRADE_TYPE_15_30_SMASH, smashLevel, T_tradeType4_TPPips, T_tradeType4_SLPips);

   ExtTrade.SetExpertMagicNumber(magic);
   if(ExtTrade.Buy(T_tradeType4_LotSize, _Symbol, ask, sl, tp, orderComment))
   {
      ulong orderTicket = ExtTrade.ResultOrder();
      datetime eventTime = candleTime;
      if(orderTicket > 0 && OrderSelect(orderTicket))
         eventTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      WriteTradeLog(GetTradeTypeStringFromId(TRADE_TYPE_15_30_SMASH), "pending_created", eventTime, "market_buy", ask, sl, tp, 0, orderTicket, 0, 0, (ENUM_DEAL_REASON)0, orderComment, magic);
   }
   ExtTrade.SetExpertMagicNumber(EA_MAGIC);
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

      string allFileName = dateStr + "-AllCandlesTickLog.txt";
      allCandlesFileHandle = OpenOrCreateForAppend(allFileName);

      allCandlesFileDate = candleDay;
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

            string araFile = StringFormat("%s-%s_week%s_-%s_Arawevents.txt", 
                                         dateStr, levels[i].baseName, dateStr, DoubleToString(lvl,_Digits));

            levels[i].logRawEv_fileHandle = OpenOrCreateForAppend(araFile);
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

         // --- Write Arawevents
         if(levels[i].logRawEv_fileHandle != INVALID_HANDLE)
         {
            FileWrite(levels[i].logRawEv_fileHandle,
               "T: ", TimeToString(current_candle_time,TIME_DATE|TIME_MINUTES),
               " L: ", lvl,
               " O: ", NormalizeDouble(candle_open,_Digits),
               " H: ", NormalizeDouble(candle_high,_Digits),
               " L: ", NormalizeDouble(candle_low,_Digits),
               " C: ", NormalizeDouble(candle_close,_Digits),
               " Diff_CloseToLevel: ", NormalizeDouble(diffCloseToLevel,_Digits),
               " DayBias: ", (levels[i].dailyBias>0 ? "bias_long" : "bias_short"),
               " Contact: ", (in_contact ? "in_contact" : "no_contact"),
               " ContactCount: ", levels[i].approxContactCount,
               ", BounceCount: ", levels[i].bounceCount,
               ", CandlesPassedSinceLastBounce: ", levels[i].candlesPassedSinceLastBounce,
               ", CandlesBreakLevelCount: ", levels[i].candlesBreakLevelCount,
               ", RecoverCount: ", levels[i].recoverCount);
         }

         // --- Write per-level file if physically touched
         if(physicallyTouched)
         {
            string lvlFile = StringFormat("%s-%s_week%s_-%.0f_ARawAContact.txt", 
                                         dateStr, levels[i].baseName, dateStr, lvl);

            int fh = OpenOrCreateForAppend(lvlFile);
            if(fh != INVALID_HANDLE)
            {
               FileWrite(fh,
                  "T: ", TimeToString(current_candle_time,TIME_DATE|TIME_MINUTES),
                  " O: ", candle_open,
                  " H: ", candle_high,
                  " L: ", candle_low,
                  " C: ", candle_close);
               FileClose(fh);
            }
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
               
               string orderComment = StringFormat("%d %d %.0f %.0f",
                  (int)TRADE_TYPE_BUY_2ND_BOUNCE,
                  (int)lvl,
                  T_buy2ndBounce_TPPips,
                  T_buy2ndBounce_SLPips);

               datetime expirationTime = g_lastTickTime + 30 * 60;
               
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
               
               string orderComment = StringFormat("%d %d %.0f %.0f",
                  (int)TRADE_TYPE_BUY_4TH_BOUNCE,
                  (int)lvl,
                  T_buy4thBounce_TPPips,
                  T_buy4thBounce_SLPips);

               datetime expirationTime = g_lastTickTime + 30 * 60;
               
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
   // Flow B: evaluate trade type 4 (15:30 bar close, price near daily smash level)
   EvaluateTradeType4(current_candle_time);

   if(allCandlesFileHandle != INVALID_HANDLE)
   {
      FileWrite(allCandlesFileHandle,
         "T=" + TimeToString(current_candle_time,TIME_DATE|TIME_MINUTES),
         " O=" + DoubleToString(candle_open,_Digits),
         " H=" + DoubleToString(candle_high,_Digits),
         " L=" + DoubleToString(candle_low,_Digits),
         " C=" + DoubleToString(candle_close,_Digits));
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