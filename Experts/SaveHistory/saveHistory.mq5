//+------------------------------------------------------------------+
//|                                                  saveHistory.mq5 |
//| One-shot export: account deal history + M1/levels-based metrics |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "1.00"

//--- Export window (server time; edit before attaching EA). Plain constants here (not EA parameters dialog).
const string ExportRangeStartStr = "2026.01.20 00:00";
const string ExportRangeEndStr   = "2026.04.22 00:00";

//--- Output: 49 columns (date + 48), same schema as legacy summary_tradeResults_all_days
#define OUT_CSV_NAME "summary_tradeResults_all_days.csv"

string   InpCalendarFile = "calendar_2026_dots.csv";  // Terminal/Common/Files
string   InpLevelsFile   = "levelsinfo_zeFinal.csv"; // Terminal/Common/Files

const double tertiaryLevel_tooTight_toAdd_proximity = 2.0;

#define MAX_CALENDAR_ROWS   400
#define MAX_LEVEL_ROWS      2000
#define MAX_LEVELS_EXPANDED 500
#define MAX_BARS_IN_DAY     1500
#define MAX_TRADE_RESULTS   500
#define MAX_DEALS_DAY       2000
#define MAX_IN_OUT_PER_MAGIC 200

void FatalError(const string msg)
{
   Print("FATAL: ", msg);
   ExpertRemove();
}

//+------------------------------------------------------------------+
struct CalendarRow
{
   string dateStr;
   int    dayofmonth;
   string dayofweek;
   bool   opex;
   bool   qopex;
};
CalendarRow g_calendar[MAX_CALENDAR_ROWS];
int g_calendarCount = 0;

struct LevelInfoRow
{
   string startStr;
   string endStr;
   double levelPrice;
   string categories;
   string tag;
};
LevelInfoRow g_levels[MAX_LEVEL_ROWS];
int g_levelsTotalCount = 0;

struct LevelExpandedRow
{
   double   levelPrice;
   string   tag;
   string   categories;
   int      count;
   double   diffs[];
   datetime times[];
};
LevelExpandedRow g_levelsExpanded[MAX_LEVELS_EXPANDED];
int g_levelsTodayCount = 0;

struct StaticMarketContext
{
   double PDOpreviousDayRTHOpen;
   double PDHpreviousDayHigh;
   double PDLpreviousDayLow;
   double PDCpreviousDayRTHClose;
   string PDdate;
};
StaticMarketContext g_staticMarketContext;
datetime g_staticMarketContextPulledForDate = 0;

struct OptionalDouble { bool hasValue; double value; };

MqlRates g_m1Rates[MAX_BARS_IN_DAY];
int      g_barsInDay = 0;
datetime g_m1DayStart = 0;
string   g_session[MAX_BARS_IN_DAY];

double   g_todayRTHopen = 0.0;
bool     g_todayRTHopenValid = false;

OptionalDouble g_ONhighSoFarAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_ONlowSoFarAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_rthHighSoFarAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_rthLowSoFarAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_dayHighSoFarAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_dayLowSoFarAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_sessionRangeMidpointAtBar[MAX_BARS_IN_DAY];
bool           g_dayBrokePDHAtBar[MAX_BARS_IN_DAY];
bool           g_dayBrokePDLAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_IBhighAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_IBlowAtBar[MAX_BARS_IN_DAY];
OptionalDouble g_gapFillSoFarAtBar[MAX_BARS_IN_DAY];

struct TradeResult
{
   string   symbol;
   datetime startTime;
   datetime endTime;
   long     magic;
   double   priceStart;
   double   priceEnd;
   double   priceDiff;
   double   profit;
   long     type;
   long     reason;
   double   volume;
   string   bothComments;
   string   level;
   string   tp;
   string   sl;
   string   session;
   bool     foundOut;
};
TradeResult g_tradeResults[MAX_TRADE_RESULTS];
int g_tradeResultsCount = 0;

datetime g_dealTime[MAX_DEALS_DAY];
long     g_dealMagic[MAX_DEALS_DAY];
int      g_dealEntry[MAX_DEALS_DAY];
double   g_dealPrice[MAX_DEALS_DAY];
double   g_dealProfit[MAX_DEALS_DAY];
long     g_dealType[MAX_DEALS_DAY];
long     g_dealReason[MAX_DEALS_DAY];
double   g_dealVolume[MAX_DEALS_DAY];
string   g_dealSymbol[MAX_DEALS_DAY];
string   g_dealComment[MAX_DEALS_DAY];
int g_dealCount = 0;
int g_dealOrder[MAX_DEALS_DAY];
int g_dealOrderTmp[MAX_DEALS_DAY];
int g_inIdx[MAX_IN_OUT_PER_MAGIC];
int g_outIdx[MAX_IN_OUT_PER_MAGIC];

//+------------------------------------------------------------------+
bool LoadCalendar()
{
   g_calendarCount = 0;
   int fh = FileOpen(InpCalendarFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
   {
      FatalError("Calendar file could not be opened: " + InpCalendarFile + " (Terminal/Common/Files)");
      return false;
   }
   FileReadString(fh);
   while(!FileIsEnding(fh) && g_calendarCount < MAX_CALENDAR_ROWS)
   {
      string line = FileReadString(fh);
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
   if(g_calendarCount <= 0)
      FatalError("Calendar file is empty: " + InpCalendarFile);
   return true;
}

string GetPreviousTradingDayDateString(const datetime dayStart)
{
   string key = TimeToString(dayStart, TIME_DATE);
   int foundIdx = -1;
   for(int i = 0; i < g_calendarCount; i++)
      if(g_calendar[i].dateStr == key) { foundIdx = i; break; }
   if(foundIdx <= 0) return "";
   int prevIdx = foundIdx - 1;
   while(prevIdx >= 0 && (g_calendar[prevIdx].dayofweek == "Saturday" || g_calendar[prevIdx].dayofweek == "Sunday"))
      prevIdx--;
   if(prevIdx < 0) return "";
   return g_calendar[prevIdx].dateStr;
}

//+------------------------------------------------------------------+
//| Day-of-week string from calendar CSV for YYYY.MM.DD, or "" if not listed. |
//+------------------------------------------------------------------+
string LookupCalendarDayOfWeek(const string dateStr)
{
   for(int i = 0; i < g_calendarCount; i++)
      if(g_calendar[i].dateStr == dateStr)
         return g_calendar[i].dayofweek;
   return "";
}

bool bool_RTHsession_Is_DaylightSavingsDesync(const string dateStr)
{
   string normalized = dateStr;
   if(StringFind(dateStr, "-") >= 0)
      StringReplace(normalized, "-", ".");
   static string ds[] = {
      "2026.03.08", "2026.03.09", "2026.03.10", "2026.03.11", "2026.03.12",
      "2026.03.13", "2026.03.14", "2026.03.15", "2026.03.16", "2026.03.17",
      "2026.03.18", "2026.03.19", "2026.03.20", "2026.03.21", "2026.03.22",
      "2026.03.23", "2026.03.24", "2026.03.25", "2026.03.26", "2026.03.27",
      "2026.03.28",
      "2026.10.25", "2026.10.26", "2026.10.27", "2026.10.28", "2026.10.29",
      "2026.10.30", "2026.10.31"
   };
   for(int i = 0; i < ArraySize(ds); i++)
      if(ds[i] == normalized) return true;
   return false;
}

int GetRthOpenBarOffsetSeconds(const string dateStr)
{
   if(bool_RTHsession_Is_DaylightSavingsDesync(dateStr))
      return 14*3600 + 30*60;
   return 15*3600 + 30*60;
}

string GetSessionForCandleTime(const datetime t)
{
   MqlDateTime mqlTime;
   TimeToStruct(t, mqlTime);
   int minOfDay = mqlTime.hour * 60 + mqlTime.min;
   string dateStr = TimeToString(t, TIME_DATE);
   if(bool_RTHsession_Is_DaylightSavingsDesync(dateStr))
   {
      if(minOfDay < 14*60+30) return "ON";
      if(minOfDay <= 20*60+59) return "RTH";
      return "sleep";
   }
   if(minOfDay < 15*60+30) return "ON";
   if(minOfDay <= 22*60+0) return "RTH";
   return "sleep";
}

void UpdateStaticMarketContext(const datetime referenceDayStart)
{
   g_staticMarketContext.PDOpreviousDayRTHOpen   = 0;
   g_staticMarketContext.PDHpreviousDayHigh    = 0;
   g_staticMarketContext.PDLpreviousDayLow     = 0;
   g_staticMarketContext.PDCpreviousDayRTHClose  = 0;
   g_staticMarketContext.PDdate                  = "";
   string prevDayStr = GetPreviousTradingDayDateString(referenceDayStart);
   if(StringLen(prevDayStr) == 0)
      FatalError("UpdateStaticMarketContext: no previous trading day for " + TimeToString(referenceDayStart, TIME_DATE));
   g_staticMarketContext.PDdate = prevDayStr;
   string parts[];
   if(StringSplit(prevDayStr, '.', parts) != 3)
      FatalError("UpdateStaticMarketContext: invalid prev day format " + prevDayStr);
   MqlDateTime mtPrev = {0};
   mtPrev.year = (int)StringToInteger(parts[0]);
   mtPrev.mon  = (int)StringToInteger(parts[1]);
   mtPrev.day  = (int)StringToInteger(parts[2]);
   datetime prevDayStart = StructToTime(mtPrev);
   datetime prevDayEnd   = prevDayStart + 86400;

   datetime barPDO, barPDC;
   if(bool_RTHsession_Is_DaylightSavingsDesync(prevDayStr))
   {
      barPDO = prevDayStart + 14*3600 + 30*60;
      barPDC = prevDayStart + 20*3600 + 59*60;
   }
   else
   {
      barPDO = prevDayStart + 15*3600 + 30*60;
      barPDC = prevDayStart + 21*3600 + 59*60;
   }
   int shiftPDO_M1 = iBarShift(_Symbol, PERIOD_M1, barPDO, false);
   int shiftPDC_M1 = iBarShift(_Symbol, PERIOD_M1, barPDC, false);
   if(shiftPDO_M1 >= 0)
      g_staticMarketContext.PDOpreviousDayRTHOpen = iOpen(_Symbol, PERIOD_M1, shiftPDO_M1);
   if(shiftPDC_M1 >= 0)
      g_staticMarketContext.PDCpreviousDayRTHClose = iClose(_Symbol, PERIOD_M1, shiftPDC_M1);

   int shiftDayStart = iBarShift(_Symbol, PERIOD_M30, prevDayStart, false);
   int shiftDayEnd   = iBarShift(_Symbol, PERIOD_M30, prevDayEnd - 1, false);
   if(shiftDayStart < 0 || shiftDayEnd < 0)
      FatalError("UpdateStaticMarketContext: no M30 bars for previous day " + prevDayStr);
   double pdh = -1e300, pdl = 1e300;
   for(int shiftIdx = shiftDayEnd; shiftIdx <= shiftDayStart; shiftIdx++)
   {
      double high = iHigh(_Symbol, PERIOD_M30, shiftIdx);
      double low  = iLow(_Symbol, PERIOD_M30, shiftIdx);
      if(high > pdh) pdh = high;
      if(low < pdl) pdl = low;
   }
   if(pdh <= -1e300 || pdl >= 1e300 || pdh == 0.0 || pdl == 0.0)
      FatalError("UpdateStaticMarketContext: invalid PDH/PDL for " + prevDayStr);
   g_staticMarketContext.PDHpreviousDayHigh = pdh;
   g_staticMarketContext.PDLpreviousDayLow  = pdl;
}

void LoadLevelsForDate(const string &dateStr)
{
   g_levelsTotalCount = 0;
   int fh = FileOpen(InpLevelsFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      FatalError("Levels file could not be opened: " + InpLevelsFile + " (Terminal/Common/Files)");
   FileReadString(fh);
   while(!FileIsEnding(fh) && g_levelsTotalCount < MAX_LEVEL_ROWS)
   {
      string line = FileReadString(fh);
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
   FileClose(fh);
}

bool LoadM1BarsForDay(const datetime dayStart, const string &dateStr)
{
   g_barsInDay = 0;
   g_m1DayStart = 0;
   int barsFromDayStart = iBarShift(_Symbol, PERIOD_M1, dayStart, false);
   if(barsFromDayStart < 0)
      return false;
   MqlRates tmp[];
   int countToCopy = barsFromDayStart + 1;
   int copied = CopyRates(_Symbol, PERIOD_M1, 0, countToCopy, tmp);
   if(copied <= 0) return false;
   int barsInDay = 0;
   for(int i = 0; i < copied; i++)
      if(TimeToString(tmp[i].time, TIME_DATE) == dateStr) barsInDay++;
   if(barsInDay <= 0 || barsInDay > MAX_BARS_IN_DAY) return false;
   int idx = 0;
   for(int i = 0; i < copied && idx < barsInDay; i++)
   {
      if(TimeToString(tmp[i].time, TIME_DATE) != dateStr) continue;
      g_m1Rates[idx++] = tmp[i];
   }
   g_barsInDay  = barsInDay;
   g_m1DayStart = dayStart;
   return true;
}

void AssignTodayRTHopenFromM1Rates(const string &dateStr)
{
   g_todayRTHopenValid = false;
   if(g_barsInDay <= 0) return;
   bool useDesync = bool_RTHsession_Is_DaylightSavingsDesync(dateStr);
   for(int i = 0; i < g_barsInDay; i++)
   {
      MqlDateTime mqlTime;
      TimeToStruct(g_m1Rates[i].time, mqlTime);
      if(useDesync && mqlTime.hour == 14 && mqlTime.min == 30)
      {
         g_todayRTHopen = g_m1Rates[i].open;
         g_todayRTHopenValid = true;
         return;
      }
      if(!useDesync && mqlTime.hour == 15 && mqlTime.min == 30)
      {
         g_todayRTHopen = g_m1Rates[i].open;
         g_todayRTHopenValid = true;
         return;
      }
   }
}

void TryAppendTodayRTHopenLevel(const string &dateStr)
{
   if(!g_todayRTHopenValid) return;
   for(int i = 0; i < g_levelsTotalCount; i++)
      if(g_levels[i].tag == "todayRTHopen" && g_levels[i].startStr == dateStr && g_levels[i].endStr == dateStr)
         return;
   for(int i = 0; i < g_levelsTotalCount; i++)
      if(g_levels[i].startStr <= dateStr && dateStr <= g_levels[i].endStr &&
         MathAbs(g_levels[i].levelPrice - g_todayRTHopen) < tertiaryLevel_tooTight_toAdd_proximity)
         return;
   if(g_levelsTotalCount >= MAX_LEVEL_ROWS)
      FatalError("TryAppendTodayRTHopenLevel: g_levels full");
   int j = g_levelsTotalCount++;
   g_levels[j].startStr   = dateStr;
   g_levels[j].endStr     = dateStr;
   g_levels[j].levelPrice = g_todayRTHopen;
   g_levels[j].categories = "daily_tertiary_todayRTHopen";
   g_levels[j].tag        = "todayRTHopen";
}

void TryAppendPDClevel(const string &dateStr)
{
   if(g_staticMarketContextPulledForDate != g_m1DayStart) return;
   if(g_staticMarketContext.PDCpreviousDayRTHClose <= 0.0) return;
   double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
   for(int i = 0; i < g_levelsTotalCount; i++)
      if(g_levels[i].startStr <= dateStr && dateStr <= g_levels[i].endStr &&
         MathAbs(g_levels[i].levelPrice - pdc) < tertiaryLevel_tooTight_toAdd_proximity)
         return;
   if(g_levelsTotalCount >= MAX_LEVEL_ROWS)
      FatalError("TryAppendPDClevel: g_levels full");
   int j = g_levelsTotalCount++;
   g_levels[j].startStr   = dateStr;
   g_levels[j].endStr     = dateStr;
   g_levels[j].levelPrice = pdc;
   g_levels[j].categories = "daily_tertiary_PDrthClose";
   g_levels[j].tag        = "PDrthClose";
}

void RebuildLevelsExpanded(const string &dayKey)
{
   g_levelsTodayCount = 0;
   for(int li = 0; li < g_levelsTotalCount && g_levelsTodayCount < MAX_LEVELS_EXPANDED; li++)
   {
      if(g_levels[li].startStr > dayKey || dayKey > g_levels[li].endStr) continue;
      int e = g_levelsTodayCount++;
      g_levelsExpanded[e].levelPrice  = g_levels[li].levelPrice;
      g_levelsExpanded[e].tag         = g_levels[li].tag;
      g_levelsExpanded[e].categories  = g_levels[li].categories;
      g_levelsExpanded[e].count       = g_barsInDay;
      ArrayResize(g_levelsExpanded[e].diffs, g_barsInDay);
      ArrayResize(g_levelsExpanded[e].times, g_barsInDay);
      for(int b = 0; b < g_barsInDay; b++)
      {
         g_levelsExpanded[e].times[b] = g_m1Rates[b].time;
         g_levelsExpanded[e].diffs[b]  = g_m1Rates[b].close - g_levelsExpanded[e].levelPrice;
      }
   }
}

void FillSessionsForDay()
{
   for(int i = 0; i < g_barsInDay; i++)
      g_session[i] = GetSessionForCandleTime(g_m1Rates[i].time);
}

void UpdateONandRTHHighLowSoFarAtBar()
{
   bool firstON = true, firstRTH = true;
   double runONhigh = 0, runONlow = 0, runRTHhigh = 0, runRTHlow = 0;
   double runDayHigh = (g_barsInDay > 0) ? g_m1Rates[0].high : 0;
   double runDayLow  = (g_barsInDay > 0) ? g_m1Rates[0].low  : 0;
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      runDayHigh = MathMax(runDayHigh, g_m1Rates[barIdx].high);
      runDayLow  = MathMin(runDayLow,  g_m1Rates[barIdx].low);
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
         else { runONhigh = MathMax(runONhigh, g_m1Rates[barIdx].high); runONlow = MathMin(runONlow, g_m1Rates[barIdx].low); }
         g_ONhighSoFarAtBar[barIdx].hasValue = true;
         g_ONhighSoFarAtBar[barIdx].value    = runONhigh;
         g_ONlowSoFarAtBar[barIdx].hasValue  = true;
         g_ONlowSoFarAtBar[barIdx].value     = runONlow;
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
         else { runRTHhigh = MathMax(runRTHhigh, g_m1Rates[barIdx].high); runRTHlow = MathMin(runRTHlow, g_m1Rates[barIdx].low); }
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

bool IsBarRTHIB(const datetime barTime)
{
   MqlDateTime mqlTime;
   TimeToStruct(barTime, mqlTime);
   int minOfDay = mqlTime.hour * 60 + mqlTime.min;
   string dateStr = TimeToString(barTime, TIME_DATE);
   if(bool_RTHsession_Is_DaylightSavingsDesync(dateStr))
      return (minOfDay >= 14*60+30 && minOfDay <= 15*60+30);
   return (minOfDay >= 15*60+30 && minOfDay <= 16*60+30);
}

void UpdateIBHighLowAtBar()
{
   if(g_barsInDay <= 0 || g_m1DayStart == 0) return;
   string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   datetime lastIBBarTime;
   if(bool_RTHsession_Is_DaylightSavingsDesync(dateStr))
      lastIBBarTime = g_m1DayStart + 15*3600 + 30*60;
   else
      lastIBBarTime = g_m1DayStart + 16*3600 + 30*60;
   double ibHigh = -1e300, ibLow = 1e300;
   bool ibComplete = false;
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      if(IsBarRTHIB(g_m1Rates[barIdx].time))
      {
         ibHigh = MathMax(ibHigh, g_m1Rates[barIdx].high);
         ibLow  = MathMin(ibLow,  g_m1Rates[barIdx].low);
      }
      if(g_m1Rates[barIdx].time >= lastIBBarTime)
         ibComplete = true;
      bool hasIBhigh = ibComplete && (ibHigh > -1e299);
      bool hasIBlow  = ibComplete && (ibLow < 1e299);
      g_IBhighAtBar[barIdx].hasValue = hasIBhigh;
      if(hasIBhigh) g_IBhighAtBar[barIdx].value = ibHigh;
      g_IBlowAtBar[barIdx].hasValue  = hasIBlow;
      if(hasIBlow)  g_IBlowAtBar[barIdx].value  = ibLow;
   }
}

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
         filled = MathMax(0.0, MathMin(range_size, range_top - rthL));
      else
         filled = MathMax(0.0, MathMin(range_size, rthH - range_bottom));
      double pct = MathMin(100.0, (filled / range_size) * 100.0);
      g_gapFillSoFarAtBar[barIdx].hasValue = true;
      g_gapFillSoFarAtBar[barIdx].value    = pct;
   }
}

bool GetGapFillSoFarAtBar(const int barIdx, const datetime dayStart, const string &dateStr, double &outVal)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   datetime rthOpenBarTime = dayStart + GetRthOpenBarOffsetSeconds(dateStr);
   if(g_m1Rates[barIdx].time < rthOpenBarTime) return false;
   if(!g_gapFillSoFarAtBar[barIdx].hasValue) return false;
   outVal = g_gapFillSoFarAtBar[barIdx].value;
   return true;
}

bool GetRthHighSoFarAtBar(const int barIdx, const datetime dayStart, const string &dateStr, double &outVal)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   datetime rthOpenBarTime = dayStart + GetRthOpenBarOffsetSeconds(dateStr);
   if(g_m1Rates[barIdx].time < rthOpenBarTime) return false;
   if(!g_rthHighSoFarAtBar[barIdx].hasValue) return false;
   outVal = g_rthHighSoFarAtBar[barIdx].value;
   return true;
}

bool GetRthLowSoFarAtBar(const int barIdx, const datetime dayStart, const string &dateStr, double &outVal)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   datetime rthOpenBarTime = dayStart + GetRthOpenBarOffsetSeconds(dateStr);
   if(g_m1Rates[barIdx].time < rthOpenBarTime) return false;
   if(!g_rthLowSoFarAtBar[barIdx].hasValue) return false;
   outVal = g_rthLowSoFarAtBar[barIdx].value;
   return true;
}

bool GetIBhighAtBar(const int barIdx, double &outVal)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   if(!g_IBhighAtBar[barIdx].hasValue) return false;
   outVal = g_IBhighAtBar[barIdx].value;
   return true;
}

bool GetIBlowAtBar(const int barIdx, double &outVal)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return false;
   if(!g_IBlowAtBar[barIdx].hasValue) return false;
   outVal = g_IBlowAtBar[barIdx].value;
   return true;
}

string GetGapFillPcAtTradeOpenTime(const datetime tradeOpenTime)
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

string GetIsGapDownDayString(const datetime tradeOpenTime)
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

string GetDayBrokePDHAtTradeOpenTime(const datetime tradeOpenTime)
{
   datetime barOpenTime = tradeOpenTime - (tradeOpenTime % 60);
   int barIdx = -1;
   for(int i = 0; i < g_barsInDay; i++)
      if(g_m1Rates[i].time == barOpenTime) { barIdx = i; break; }
   if(barIdx < 0) return "unknown";
   return g_dayBrokePDHAtBar[barIdx] ? "true" : "false";
}

string GetDayBrokePDLAtTradeOpenTime(const datetime tradeOpenTime)
{
   datetime barOpenTime = tradeOpenTime - (tradeOpenTime % 60);
   int barIdx = -1;
   for(int i = 0; i < g_barsInDay; i++)
      if(g_m1Rates[i].time == barOpenTime) { barIdx = i; break; }
   if(barIdx < 0) return "unknown";
   return g_dayBrokePDLAtBar[barIdx] ? "true" : "false";
}

string GetPDtrendString()
{
   double pdo = g_staticMarketContext.PDOpreviousDayRTHOpen;
   double pdc = g_staticMarketContext.PDCpreviousDayRTHClose;
   if(pdo <= 0.0 || pdc <= 0.0) return "unknown";
   if(pdc > pdo) return "PD_green";
   if(pdc < pdo) return "PD_red";
   return "unknown";
}

// Reference points above/below levelPrice at tradeOpenTime's M1 bar (caller supplies strategy level only).
void GetReferencePointsAboveBelow(const datetime tradeOpenTime, const double levelPrice, string &outAbove, string &outBelow)
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
   double v;
   if(g_staticMarketContext.PDOpreviousDayRTHOpen > 0.0)
   {
      v = g_staticMarketContext.PDOpreviousDayRTHOpen;
      if(v > levelPrice) outAbove += (outAbove != "" ? ";" : "") + "PDO";
      else if(v < levelPrice) outBelow += (outBelow != "" ? ";" : "") + "PDO";
   }
   if(g_staticMarketContext.PDHpreviousDayHigh > 0.0)
   {
      v = g_staticMarketContext.PDHpreviousDayHigh;
      if(v > levelPrice) outAbove += (outAbove != "" ? ";" : "") + "PDH";
      else if(v < levelPrice) outBelow += (outBelow != "" ? ";" : "") + "PDH";
   }
   if(g_staticMarketContext.PDLpreviousDayLow > 0.0)
   {
      v = g_staticMarketContext.PDLpreviousDayLow;
      if(v > levelPrice) outAbove += (outAbove != "" ? ";" : "") + "PDL";
      else if(v < levelPrice) outBelow += (outBelow != "" ? ";" : "") + "PDL";
   }
   if(g_staticMarketContext.PDCpreviousDayRTHClose > 0.0)
   {
      v = g_staticMarketContext.PDCpreviousDayRTHClose;
      if(v > levelPrice) outAbove += (outAbove != "" ? ";" : "") + "PDC";
      else if(v < levelPrice) outBelow += (outBelow != "" ? ";" : "") + "PDC";
   }
   if(g_ONhighSoFarAtBar[barIdx].hasValue)
   {
      v = g_ONhighSoFarAtBar[barIdx].value;
      if(v > levelPrice) outAbove += (outAbove != "" ? ";" : "") + "ONH";
      else if(v < levelPrice) outBelow += (outBelow != "" ? ";" : "") + "ONH";
   }
   if(g_ONlowSoFarAtBar[barIdx].hasValue)
   {
      v = g_ONlowSoFarAtBar[barIdx].value;
      if(v > levelPrice) outAbove += (outAbove != "" ? ";" : "") + "ONL";
      else if(v < levelPrice) outBelow += (outBelow != "" ? ";" : "") + "ONL";
   }
   if(GetRthHighSoFarAtBar(barIdx, dayStart, dateStr, v))
   {
      if(v > levelPrice) outAbove += (outAbove != "" ? ";" : "") + "RTHH";
      else if(v < levelPrice) outBelow += (outBelow != "" ? ";" : "") + "RTHH";
   }
   if(GetRthLowSoFarAtBar(barIdx, dayStart, dateStr, v))
   {
      if(v > levelPrice) outAbove += (outAbove != "" ? ";" : "") + "RTHL";
      else if(v < levelPrice) outBelow += (outBelow != "" ? ";" : "") + "RTHL";
   }
   if(GetIBlowAtBar(barIdx, v))
   {
      if(v > levelPrice) outAbove += (outAbove != "" ? ";" : "") + "IBL";
      else if(v < levelPrice) outBelow += (outBelow != "" ? ";" : "") + "IBL";
   }
   if(GetIBhighAtBar(barIdx, v))
   {
      if(v > levelPrice) outAbove += (outAbove != "" ? ";" : "") + "IBH";
      else if(v < levelPrice) outBelow += (outBelow != "" ? ";" : "") + "IBH";
   }
   if(g_dayHighSoFarAtBar[barIdx].hasValue)
   {
      v = g_dayHighSoFarAtBar[barIdx].value;
      if(v > levelPrice) outAbove += (outAbove != "" ? ";" : "") + "dayHighSoFar";
      else if(v < levelPrice) outBelow += (outBelow != "" ? ";" : "") + "dayHighSoFar";
   }
   if(g_dayLowSoFarAtBar[barIdx].hasValue)
   {
      v = g_dayLowSoFarAtBar[barIdx].value;
      if(v > levelPrice) outAbove += (outAbove != "" ? ";" : "") + "dayLowSoFar";
      else if(v < levelPrice) outBelow += (outBelow != "" ? ";" : "") + "dayLowSoFar";
   }
   if(g_sessionRangeMidpointAtBar[barIdx].hasValue)
   {
      v = g_sessionRangeMidpointAtBar[barIdx].value;
      if(v > levelPrice) outAbove += (outAbove != "" ? ";" : "") + "midpoint";
      else if(v < levelPrice) outBelow += (outBelow != "" ? ";" : "") + "midpoint";
   }
}

double Instrument_PointStepSize() { return SymbolInfoDouble(_Symbol, SYMBOL_POINT); }

double PointSized(const double points) { return points * 10.0 * Instrument_PointStepSize(); }

void GetMFEandMAEForTrade(const TradeResult &tradeResult, double &mfe, double &mae, int &mfeCandle, int &maeCandle)
{
   mfe = 0.0;
   mae = 0.0;
   mfeCandle = 0;
   maeCandle = 0;
   if(!tradeResult.foundOut || tradeResult.endTime == 0 || g_barsInDay <= 0) return;
   datetime startPlus1Min = tradeResult.startTime + 60;
   datetime firstBarTime  = startPlus1Min - (startPlus1Min % 60);
   datetime lastBarTime   = tradeResult.endTime - (tradeResult.endTime % 60);
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
   else
   {
      mfe = lowestLow;
      mae = highestHigh;
      mfeCandle = candleLowestLow;
      maeCandle = candleHighestHigh;
   }
}

void GetMFEandMAE_cNForTrade(const TradeResult &tradeResult, const int candleCount, double &mfe_out, double &mae_out)
{
   mfe_out = 0.0;
   mae_out = 0.0;
   if(g_barsInDay <= 0) return;
   datetime firstBarTime = tradeResult.startTime - (tradeResult.startTime % 60);
   datetime lastBarTime = firstBarTime + (candleCount - 1) * 60;
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
   else
   {
      mfe_out = tradeResult.priceStart - lowestLow;
      mae_out = tradeResult.priceStart - highestHigh;
   }
}

void GetMFEpAndMAEpForTrade(const TradeResult &tradeResult, const double mfe, const double mae, double &mfep, double &maep)
{
   mfep = 0.0;
   maep = 0.0;
   if(mfe == 0.0 && mae == 0.0) return;
   if(tradeResult.type == (long)DEAL_TYPE_BUY)
   {
      if(mfe > 0.0) mfep = mfe - tradeResult.priceStart;
      if(mae > 0.0) maep = mae - tradeResult.priceStart;
   }
   else
   {
      if(mae > 0.0) mfep = tradeResult.priceStart - mae;
      if(mfe > 0.0) maep = tradeResult.priceStart - mfe;
   }
}

double GetLevelPriceForTPorSL(const TradeResult &tradeResult, const int N, const bool isTP)
{
   double dist = PointSized((double)N);
   if(tradeResult.type == (long)DEAL_TYPE_BUY)
      return isTP ? tradeResult.priceStart + dist : tradeResult.priceStart - dist;
   return isTP ? tradeResult.priceStart - dist : tradeResult.priceStart + dist;
}

int GetCandleWhereLevelReached(const TradeResult &tradeResult, const double levelPrice, const bool isTP)
{
   if(g_barsInDay <= 0) return 0;
   datetime firstBarTime = tradeResult.startTime - (tradeResult.startTime % 60);
   datetime lastBarTime = firstBarTime + 29 * 60;
   bool isBuy = (tradeResult.type == (long)DEAL_TYPE_BUY);
   for(int barIdx = 0; barIdx < g_barsInDay; barIdx++)
   {
      datetime barTime = g_m1Rates[barIdx].time;
      if(barTime < firstBarTime) continue;
      if(barTime > lastBarTime) break;
      int candleNum = (int)((barTime - firstBarTime) / 60) + 1;
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

int Get3c30cLevelBreakevenCForTrade(const TradeResult &tradeResult)
{
   if(StringLen(tradeResult.level) == 0 || g_barsInDay <= 0) return 0;
   double levelVal = StringToDouble(tradeResult.level);
   const double LEVEL_OFFSET_POINTS = 3.0;
   double threshold = (tradeResult.type == (long)DEAL_TYPE_BUY) ? (levelVal + LEVEL_OFFSET_POINTS) : (levelVal - LEVEL_OFFSET_POINTS);
   datetime firstBarTime = tradeResult.startTime - (tradeResult.startTime % 60);
   datetime lastBarTime = firstBarTime + 29 * 60;
   double ohlc[30][4];
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

string GetPriceBreakLevel_c1c2_ForTrade(const TradeResult &tradeResult)
{
   if(StringLen(tradeResult.level) == 0 || g_barsInDay <= 0) return "NOT_FOUND";
   double levelVal = StringToDouble(tradeResult.level);
   datetime currBarTime = tradeResult.startTime - (tradeResult.startTime % 60);
   datetime nextBarTime = currBarTime + 60;
   double v1 = 0.0, v2 = 0.0;
   bool has1 = false, has2 = false;
   for(int i = 0; i < g_barsInDay; i++)
   {
      if(g_m1Rates[i].time == currBarTime)
      {
         v1 = (tradeResult.type == (long)DEAL_TYPE_BUY) ? g_m1Rates[i].low : g_m1Rates[i].high;
         has1 = true;
      }
      if(g_m1Rates[i].time == nextBarTime)
      {
         v2 = (tradeResult.type == (long)DEAL_TYPE_BUY) ? g_m1Rates[i].low : g_m1Rates[i].high;
         has2 = true;
      }
   }
   if(!has1 && !has2) return "NOT_FOUND";
   double cp;
   if(tradeResult.type == (long)DEAL_TYPE_BUY)
   {
      if(has1 && has2) cp = MathMin(levelVal - v1, levelVal - v2);
      else cp = has1 ? (levelVal - v1) : (levelVal - v2);
   }
   else
   {
      if(has1 && has2) cp = MathMax(levelVal - v1, levelVal - v2);
      else cp = has1 ? (levelVal - v1) : (levelVal - v2);
   }
   return DoubleToString(cp, _Digits);
}

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

string BuildBothComments(const string &entryComment, const string &outComment, const bool foundOut)
{
   if(foundOut) return entryComment + "| " + outComment;
   return entryComment + "| NOT_FOUND";
}

int ChangeBothCommentsToArrayOfStrings(const string &bothComments, string &result[])
{
   if(StringFind(bothComments, "$") < 0) return 0;
   string commentStr = bothComments;
   StringReplace(commentStr, "$", "");
   return StringSplit(commentStr, ' ', result);
}

double Loghelper_MergeLevelWithTpSl(const double level, const double tpOrSl)
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

void MergeSortDealOrder()
{
   int n = g_dealCount;
   for(int i = 0; i < n; i++)
      g_dealOrder[i] = i;
   if(n <= 1) return;
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
            if(takeP) g_dealOrderTmp[o++] = g_dealOrder[p++];
            else      g_dealOrderTmp[o++] = g_dealOrder[q++];
         }
         while(p < m) g_dealOrderTmp[o++] = g_dealOrder[p++];
         while(q < i1) g_dealOrderTmp[o++] = g_dealOrder[q++];
      }
      ArrayCopy(g_dealOrder, g_dealOrderTmp, 0, 0, n);
      w *= 2;
   }
}

void SortIndicesByTradeStartAsc(int &indices[])
{
   int n = ArraySize(indices);
   if(n <= 1) return;
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
            if(g_tradeResults[ap].startTime <= g_tradeResults[aq].startTime)
               tmp[o++] = indices[p++];
            else
               tmp[o++] = indices[q++];
         }
         while(p < m) tmp[o++] = indices[p++];
         while(q < i1) tmp[o++] = indices[q++];
      }
      ArrayCopy(indices, tmp, 0, 0, n);
      w *= 2;
   }
}

void UpdateTradeResultsForDay(const datetime dayStart)
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
   }
   MergeSortDealOrder();
   int dealIdx = 0;
   while(dealIdx < g_dealCount && g_tradeResultsCount < MAX_TRADE_RESULTS)
   {
      long mag = g_dealMagic[g_dealOrder[dealIdx]];
      int inCount = 0, outCount = 0;
      while(dealIdx < g_dealCount && g_dealMagic[g_dealOrder[dealIdx]] == mag)
      {
         int idx = g_dealOrder[dealIdx];
         if(g_dealEntry[idx] == (int)DEAL_ENTRY_IN)
         {
            if(inCount < MAX_IN_OUT_PER_MAGIC) g_inIdx[inCount++] = idx;
         }
         else if(g_dealEntry[idx] == (int)DEAL_ENTRY_OUT)
         {
            if(outCount < MAX_IN_OUT_PER_MAGIC) g_outIdx[outCount++] = idx;
         }
         dealIdx++;
      }
      for(int pairIdx = 0; pairIdx < inCount && g_tradeResultsCount < MAX_TRADE_RESULTS; pairIdx++)
      {
         TradeResult tradeResult;
         tradeResult.symbol     = g_dealSymbol[g_inIdx[pairIdx]];
         tradeResult.startTime  = g_dealTime[g_inIdx[pairIdx]];
         tradeResult.magic      = g_dealMagic[g_inIdx[pairIdx]];
         tradeResult.priceStart = g_dealPrice[g_inIdx[pairIdx]];
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
               tradeResult.priceDiff = tradeResult.priceStart - tradeResult.priceEnd;
            tradeResult.profit = g_dealProfit[outIdx];
            tradeResult.reason = g_dealReason[outIdx];
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

void WriteTradeResultsHeader(const int fh)
{
   FileWrite(fh,
      "date", "symbol", "startTime", "endTime", "session", "magic", "priceBreakLevel_c1c2",
      "priceStart", "priceEnd", "priceDiff", "profit", "type", "reason", "volume", "bothComments",
      "level", "tp", "sl", "MFE", "MAE", "mfeCandle", "maeCandle", "MFEp", "MAEp",
      "MFE_c6", "MAE_c6", "MFE_c11", "MAE_c11", "MFE_c16", "MAE_c16",
      "SL4_c", "TP6c", "SL6c", "TP8c", "SL8c", "TP10c", "SL10c", "TP12c", "SL12c",
      "3c_30c_level_breakevenC", "gapFillPc_at_tradeOpenTime", "openGap_info", "PD_trend",
      "dayBrokePDH", "dayBrokePDL", "referencePointsAbove", "referencePointsBelow", "levelTag", "levelCats");
}

void WriteOneTradeRow(const int fh, const string &dateStr, const TradeResult &tradeResult)
{
   double mfe = 0.0, mae = 0.0, mfep = 0.0, maep = 0.0;
   double mfe_c6 = 0.0, mae_c6 = 0.0, mfe_c11 = 0.0, mae_c11 = 0.0, mfe_c16 = 0.0, mae_c16 = 0.0;
   int mfeCandle = 0, maeCandle = 0;
   GetMFEandMAEForTrade(tradeResult, mfe, mae, mfeCandle, maeCandle);
   GetMFEpAndMAEpForTrade(tradeResult, mfe, mae, mfep, maep);
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
   // Legacy / manual deals may have no '$' comment → empty level; still export row with blank ref columns.
   if(StringLen(tradeResult.level) > 0)
      GetReferencePointsAboveBelow(tradeResult.startTime, StringToDouble(tradeResult.level), refAbove, refBelow);
   string levelTagStr = "", levelCatsStr = "";
   GetLevelTagAndCatsForTrade(tradeResult.level, levelTagStr, levelCatsStr);
   string priceBreakStr = GetPriceBreakLevel_c1c2_ForTrade(tradeResult);

   FileWrite(fh,
      dateStr,
      tradeResult.symbol,
      TimeToString(tradeResult.startTime, TIME_DATE|TIME_SECONDS),
      endTimeStr,
      tradeResult.session,
      IntegerToString((long)tradeResult.magic),
      priceBreakStr,
      DoubleToString(tradeResult.priceStart, _Digits),
      priceEndStr,
      DoubleToString(tradeResult.priceDiff, _Digits),
      profitStr,
      typeStr,
      reasonStr,
      DoubleToString(tradeResult.volume, 2),
      tradeResult.bothComments,
      tradeResult.level,
      tradeResult.tp,
      tradeResult.sl,
      mfeStr,
      maeStr,
      mfeCandleStr,
      maeCandleStr,
      mfepStr,
      maepStr,
      mfe_c6Str,
      mae_c6Str,
      mfe_c11Str,
      mae_c11Str,
      mfe_c16Str,
      mae_c16Str,
      sl4_cStr,
      tp6cStr,
      sl6cStr,
      tp8cStr,
      sl8cStr,
      tp10cStr,
      sl10cStr,
      tp12cStr,
      sl12cStr,
      breakevenCStr,
      gapFillPcStr,
      isGapDownDayStr,
      pdTrendStr,
      dayBrokePDHStr,
      dayBrokePDLStr,
      refAbove,
      refBelow,
      levelTagStr,
      levelCatsStr);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(MQLInfoInteger(MQL_TESTER) != 0)
      FatalError("saveHistory: do not run in Strategy Tester — account history is not available. Attach on live chart.");

   LoadCalendar();

   datetime rangeStart = StringToTime(ExportRangeStartStr);
   datetime rangeEnd   = StringToTime(ExportRangeEndStr);
   if(!HistorySelect(rangeStart, rangeEnd + 86400))
      FatalError("saveHistory: HistorySelect failed for export range (enable trading history / check permissions).");

   int dealsInRange = 0;
   int hn = HistoryDealsTotal();
   for(int i = 0; i < hn; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      long dtype = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dtype == (long)DEAL_TYPE_BALANCE) continue;
      datetime t = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(t >= rangeStart && t < rangeEnd + 86400)
         dealsInRange++;
   }
   if(dealsInRange == 0)
      FatalError("saveHistory: no deals found for " + _Symbol + " in " + TimeToString(rangeStart, TIME_DATE) + " .. " + TimeToString(rangeEnd, TIME_DATE) + " (wrong account or no trades).");

   string csvFullPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + OUT_CSV_NAME;
   Print("saveHistory: starting export | symbol=", _Symbol,
         " | chart TF=", EnumToString((ENUM_TIMEFRAMES)_Period),
         " | date range (inclusive days, server): ", ExportRangeStartStr, " .. ", ExportRangeEndStr,
         " | output file: ", OUT_CSV_NAME,
         " | full path: ", csvFullPath);

   int fh = FileOpen(OUT_CSV_NAME, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      FatalError("saveHistory: could not open " + OUT_CSV_NAME + " for write (MQL5/Files).");
   WriteTradeResultsHeader(fh);

   int totalRowsWritten = 0;

   for(datetime dayStart = rangeStart; dayStart <= rangeEnd; dayStart += 86400)
   {
      string dateStr = TimeToString(dayStart, TIME_DATE);
      LoadLevelsForDate(dateStr);
      g_staticMarketContextPulledForDate = dayStart;
      UpdateStaticMarketContext(dayStart);

      if(!LoadM1BarsForDay(dayStart, dateStr))
      {
         string dow = LookupCalendarDayOfWeek(dateStr);
         string hint = "";
         if(dow == "Saturday" || dow == "Sunday")
            hint = "expected for cash index (weekend; no RTH session). ";
         else if(dow != "")
            hint = "calendar says " + dow + "; ";
         Print("saveHistory: skip ", dateStr, (dow != "" ? " (" + dow + ")" : ""), " — no M1 bars for this day. ", hint,
               "Other causes: holiday, symbol not in Market Watch, or history not downloaded.");
         continue;
      }
      AssignTodayRTHopenFromM1Rates(dateStr);
      TryAppendTodayRTHopenLevel(dateStr);
      TryAppendPDClevel(dateStr);
      RebuildLevelsExpanded(dateStr);
      FillSessionsForDay();
      UpdateONandRTHHighLowSoFarAtBar();
      UpdateIBHighLowAtBar();
      UpdateGapFillSoFarAtBar();

      UpdateTradeResultsForDay(dayStart);
      int orderTr[];
      ArrayResize(orderTr, g_tradeResultsCount);
      for(int o = 0; o < g_tradeResultsCount; o++)
         orderTr[o] = o;
      SortIndicesByTradeStartAsc(orderTr);

      for(int ti = 0; ti < g_tradeResultsCount; ti++)
      {
         WriteOneTradeRow(fh, dateStr, g_tradeResults[orderTr[ti]]);
         totalRowsWritten++;
      }
   }

   FileClose(fh);
   Print("saveHistory: finished OK | data rows written: ", IntegerToString(totalRowsWritten), " (plus CSV header row) | symbol=", _Symbol);
   Print("saveHistory: OUTPUT SAVED — full path: ", csvFullPath);
   Print("saveHistory: OUTPUT SAVED — folder: ", TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\");
   Print("saveHistory: OUTPUT SAVED — file name: ", OUT_CSV_NAME, " (local MQL5 Files, not Common\\Files)");
   Print("saveHistory: date range used (inclusive): ", ExportRangeStartStr, " .. ", ExportRangeEndStr);
   if(totalRowsWritten == 0)
      FatalError("saveHistory: no trade rows written (check symbol and date range).");
   ExpertRemove();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {}

void OnTick() {}
