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
input int      Max_AnyOrder_perLevel = 1; // any order is open position or pending order
input double   InpLotSize           = 0.01; // lot size for trade types
input int      HourForDailySummary   = 21;   // hour (server time) when daily summary is written (tick timestamp)
input int      MinuteForDailySummary = 30;   // minute of the hour for summary trigger

//--- Trade definition: buy_2nd_bounce (parameters only; entry rule below, no execution yet)
//    Type: buy_limit. Open price = level + PriceOffsetPips. TP/SL in pips. Expiration used for manual cancel logic.
input double   T_buy2ndBounce_LotSize           = 0.05;
input double   T_buy2ndBounce_PriceOffsetPips  = 7.0;   // desired open price = level + this many pips
input double   T_buy2ndBounce_TPPips           = 80.0;  // TP = order price + this many pips (e.g. 80 for 8 pts on US500 point=0.1)
input double   T_buy2ndBounce_SLPips           = 80.0;   // SL = order price - this many pips (e.g. 80 for 8 pts on US500 point=0.1)
// Entry rule to open: level.bounceCount == 1 && bias_long (dailyBias > 0) && no_contact (!in_contact)

//--- Trade definition: buy_4th_bounce (parameters only; entry rule below, no execution yet)
//    Type: buy_limit. Open price = level + PriceOffsetPips. TP/SL in pips. Expiration used for manual cancel logic.
input double   T_buy4thBounce_LotSize           = 0.1;
input double   T_buy4thBounce_PriceOffsetPips  = 5.0;   // desired open price = level + this many pips
input double   T_buy4thBounce_TPPips           = 60.0;  // TP = order price + this many pips (e.g. 60 for 6 pts on US500 point=0.1)
input double   T_buy4thBounce_SLPips           = 20.0;   // SL = order price - this many pips (e.g. 20 for 2 pts on US500 point=0.1)
// Entry rule to open: level.bounceCount == 3 && bias_long (dailyBias > 0) && no_contact (!in_contact)

//--- Level struct
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
   int araFileHandle;
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
   TRADE_TYPE_BUY_4TH_BOUNCE = 2
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

//--- Algorithm start date - only show trade history from this date in log allTradesHistoryForAllLevels_andAllAccountData
datetime dateWhenAlgoTradeStarted = StringToTime("2026.01.23 00:00");

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
   levels[newIndex].araFileHandle = INVALID_HANDLE;
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
//| Count open positions + pending orders for this level (trading: match by magic built from level date/price/tags + trade type) |
//+------------------------------------------------------------------+
int CountOrdersAndPositionsForLevel(int levelIndex)
{
   if(levelIndex < 0 || levelIndex >= ArraySize(levels)) return 0;
   int count = 0;
   datetime validFrom = levels[levelIndex].validFrom;
   double price = levels[levelIndex].price;
   string tagsCSV = levels[levelIndex].tagsCSV;
   long magic1 = BuildTradeMagic(validFrom, price, tagsCSV, TRADE_TYPE_BUY_2ND_BOUNCE);
   long magic2 = BuildTradeMagic(validFrom, price, tagsCSV, TRADE_TYPE_BUY_4TH_BOUNCE);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!ExtPositionInfo.SelectByIndex(i)) continue;
      if(ExtPositionInfo.Symbol() != _Symbol) continue;
      long m = ExtPositionInfo.Magic();
      if(m == magic1 || m == magic2) count++;
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ExtOrderInfo.SelectByIndex(i)) continue;
      if(ExtOrderInfo.Symbol() != _Symbol) continue;
      long m = ExtOrderInfo.Magic();
      if(m == magic1 || m == magic2) count++;
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
//| Get trade type string from trade type ID                  |
//+------------------------------------------------------------------+
string GetTradeTypeStringFromId(int tradeTypeId)
{
   switch(tradeTypeId)
   {
      case TRADE_TYPE_BUY_2ND_BOUNCE: return "buy_2nd_bounce";
      case TRADE_TYPE_BUY_4TH_BOUNCE: return "buy_4th_bounce";
      default: return "unknown";
   }
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
   datetime now = TimeCurrent();
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
      HistorySelect(0, TimeCurrent());
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

   int fh = FileOpen(fname, FILE_WRITE | FILE_TXT | FILE_READ);
   if(fh == INVALID_HANDLE)
      fh = FileOpen(fname, FILE_WRITE | FILE_TXT);
   else
      FileSeek(fh, 0, SEEK_END);

   if(fh != INVALID_HANDLE)
   {
      string acct = AccountSummary();
      string line = TimeToString(eventTime, TIME_DATE | TIME_SECONDS) + " " + acct;
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

   int tradeTypeId = GetTradeTypeIdFromMagic(HistoryOrderGetInteger(trans.order, ORDER_MAGIC));
   string tradeType = GetTradeTypeStringFromId(tradeTypeId);
   if(tradeType == "unknown") return;

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

   int tradeTypeId = GetTradeTypeIdFromMagic(HistoryDealGetInteger(trans.deal, DEAL_MAGIC));
   string tradeType = GetTradeTypeStringFromId(tradeTypeId);
   if(tradeType == "unknown") return;

   datetime fillTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   if(fillTime == 0) fillTime = TimeCurrent();
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
   if(reason != DEAL_REASON_TP && reason != DEAL_REASON_SL) return;

   ulong posId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(posId == 0) return;

   datetime closeTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   if(closeTime == 0) closeTime = TimeCurrent();

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

   int tradeTypeId = GetTradeTypeIdFromMagic(entryMagic);
   string tradeType = GetTradeTypeStringFromId(tradeTypeId);
   if(tradeType == "unknown") return;

   string kindStr = "";
   if(entryOrderTicket > 0 && HistoryOrderSelect(entryOrderTicket))
      kindStr = OrderTypeToKindString((ENUM_ORDER_TYPE)HistoryOrderGetInteger(entryOrderTicket, ORDER_TYPE));

   string eventType = (reason == DEAL_REASON_TP) ? "tp" : "sl";
   WriteTradeLog(tradeType, eventType, closeTime, kindStr, 0, 0, 0, 0, entryOrderTicket, trans.deal, posId, reason, comment, entryMagic);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(current_candle_time != 0)
      FinalizeCurrentCandle();

   for(int i=0;i<ArraySize(levels);i++)
      if(levels[i].araFileHandle != INVALID_HANDLE)
         FileClose(levels[i].araFileHandle);

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
void OnTick()
{
   double tick_price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   datetime candle_start = iTime(_Symbol,_Period,0);

   // daily summary check: execute once per day at specified tick time (hour+minute)
   MqlTick tick;
   if(SymbolInfoTick(_Symbol,tick))
   {
      MqlDateTime mt;
      TimeToStruct(tick.time, mt);
      int hour   = mt.hour;
      int minute = mt.min;
      datetime today = tick.time - (tick.time % 86400);
      if(hour == HourForDailySummary && minute == MinuteForDailySummary && today != lastDailySummaryDay)
      {
         WriteDailySummary();
         lastDailySummaryDay = today;
      }
   }

   if(candle_start != current_candle_time)
   {
      if(current_candle_time != 0)
         FinalizeCurrentCandle();

      current_candle_time = candle_start;
      candle_open  = tick_price;
      candle_high  = tick_price;
      candle_low   = tick_price;
      candle_close = tick_price;
   }
   else
   {
      if(tick_price > candle_high) candle_high = tick_price;
      if(tick_price < candle_low)  candle_low  = tick_price;
      candle_close = tick_price;
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

      string allFileName = dateStr + "-AllCandlesTickLog.txt";
      allCandlesFileHandle = FileOpen(allFileName, FILE_WRITE|FILE_TXT|FILE_READ);
      if(allCandlesFileHandle==INVALID_HANDLE)
         allCandlesFileHandle = FileOpen(allFileName, FILE_WRITE|FILE_TXT);

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

            if(levels[i].araFileHandle != INVALID_HANDLE)
               FileClose(levels[i].araFileHandle);

            string araFile = StringFormat("%s-%s_week%s_-%s_Arawevents.txt", 
                                         dateStr, levels[i].baseName, dateStr, DoubleToString(lvl,_Digits));

            levels[i].araFileHandle = FileOpen(araFile, FILE_WRITE|FILE_TXT|FILE_READ);
            if(levels[i].araFileHandle==INVALID_HANDLE)
               levels[i].araFileHandle = FileOpen(araFile, FILE_WRITE|FILE_TXT);
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
         if(levels[i].araFileHandle != INVALID_HANDLE)
         {
            FileWrite(levels[i].araFileHandle,
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

            int fh = FileOpen(lvlFile, FILE_WRITE|FILE_TXT|FILE_READ);
            if(fh==INVALID_HANDLE)
               fh = FileOpen(lvlFile, FILE_WRITE|FILE_TXT);
            else
               FileSeek(fh,0,SEEK_END);

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

         // --- Trading: price analysis vs levels → if trade triggers, try to place → if place succeeds without error, log it
         // --- Trade type: buy_2nd_bounce
         // Entry rule: bounceCount==1, bias_long, no_contact, CandlesPassedSinceLastBounce < 65, timeAllowed. Params from T_buy2ndBounce_* inputs.
         {
            const string tradeTypeBuy2ndBounce = "buy_2nd_bounce";
            int current_all_trades = CountOrdersAndPositionsForLevel(i);
            
            // Define banned time ranges for buy_2nd_bounce: {startHour, startMinute, endHour, endMinute}
            int bannedRanges2nd[][4] = {
               {0, 0, 0, 59},      // 00:00-00:59
               {15, 15, 16, 35},   // 15:15-16:35
               {21, 28, 23, 59}    // 21:28-23:59
            };
            bool timeAllowed = IsTradingAllowed(current_candle_time, bannedRanges2nd, 3);
            
            bool bias_long = (levels[i].dailyBias > 0);
            bool no_contact = !in_contact;
            bool entryRule = (levels[i].bounceCount == 1) && bias_long && no_contact && (levels[i].candlesPassedSinceLastBounce < 65);
            bool allowed = (current_all_trades < Max_AnyOrder_perLevel) && entryRule && timeAllowed;

            if(allowed)
            {
               double pip = PipSize();
               double orderPrice = NormalizeDouble(lvl + T_buy2ndBounce_PriceOffsetPips * pip, _Digits);
               double sl = NormalizeDouble(orderPrice - T_buy2ndBounce_SLPips * pip, _Digits);
               double tp = NormalizeDouble(orderPrice + T_buy2ndBounce_TPPips * pip, _Digits);
               
               // Build comment: first number = trade type ID (from TRADE_TYPE_* enum), then level, TP pips, SL pips
               string orderComment = StringFormat("%d %d %.0f %.0f",
                  (int)TRADE_TYPE_BUY_2ND_BOUNCE,
                  (int)lvl,
                  T_buy2ndBounce_TPPips,
                  T_buy2ndBounce_SLPips);

               datetime expirationTime = TimeCurrent() + 30 * 60; // 30 minutes from now
               
               // Trade builds magic from date, price, tags + trade type (tradeID 1 = buy_2nd_bounce)
               long tradeMagic = BuildTradeMagic(levels[i].validFrom, levels[i].price, levels[i].tagsCSV, TRADE_TYPE_BUY_2ND_BOUNCE);
               ExtTrade.SetExpertMagicNumber(tradeMagic);
               
               if(ExtTrade.BuyLimit(T_buy2ndBounce_LotSize, orderPrice, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expirationTime, orderComment))
               {
                  // Get the order ticket from the trade result
                  ulong orderTicket = ExtTrade.ResultOrder();
                  WriteTradeLog(tradeTypeBuy2ndBounce, "pending_created", current_candle_time, "buy_limit", orderPrice, sl, tp, 30, orderTicket, 0, 0, (ENUM_DEAL_REASON)0, orderComment, tradeMagic);
               }
               
               // Reset to EA's default magic number for other operations
               ExtTrade.SetExpertMagicNumber(EA_MAGIC);
            }
         }

         // --- Trade type: buy_4th_bounce
         // Entry rule: bounceCount==3, bias_long, no_contact, CandlesPassedSinceLastBounce < 65, timeAllowed. Params from T_buy2ndBounce_* inputs.
         {
            const string tradeTypeBuy4thBounce = "buy_4th_bounce";
            int current_all_trades = CountOrdersAndPositionsForLevel(i);
            
            // Define banned time ranges for buy_4th_bounce: {startHour, startMinute, endHour, endMinute}
            int bannedRanges4th[][4] = {
               {15, 15, 16, 35}    // 15:15-16:35 only
            };
            bool timeAllowed = IsTradingAllowed(current_candle_time, bannedRanges4th, 1);
            
            bool bias_long = (levels[i].dailyBias > 0);
            bool no_contact = !in_contact;
            bool entryRule = (levels[i].bounceCount == 3) && bias_long && no_contact && (levels[i].candlesPassedSinceLastBounce < 65);
            bool allowed = (current_all_trades < Max_AnyOrder_perLevel) && entryRule && timeAllowed;

            if(allowed)
            {
               double pip = PipSize();
               double orderPrice = NormalizeDouble(lvl + T_buy4thBounce_PriceOffsetPips * pip, _Digits);
               double sl = NormalizeDouble(orderPrice - T_buy4thBounce_SLPips * pip, _Digits);
               double tp = NormalizeDouble(orderPrice + T_buy4thBounce_TPPips * pip, _Digits);
               
               // Build comment: first number = trade type ID (from TRADE_TYPE_* enum), then level, TP pips, SL pips
               string orderComment = StringFormat("%d %d %.0f %.0f",
                  (int)TRADE_TYPE_BUY_4TH_BOUNCE,
                  (int)lvl,
                  T_buy4thBounce_TPPips,
                  T_buy4thBounce_SLPips);

               datetime expirationTime = TimeCurrent() + 30 * 60; // 30 minutes from now
               
               // Trade builds magic from date, price, tags + trade type (tradeID 2 = buy_4th_bounce)
               long tradeMagic = BuildTradeMagic(levels[i].validFrom, levels[i].price, levels[i].tagsCSV, TRADE_TYPE_BUY_4TH_BOUNCE);
               ExtTrade.SetExpertMagicNumber(tradeMagic);
               
               if(ExtTrade.BuyLimit(T_buy4thBounce_LotSize, orderPrice, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expirationTime, orderComment))
               {
                  // Get the order ticket from the trade result
                  ulong orderTicket = ExtTrade.ResultOrder();
                  WriteTradeLog(tradeTypeBuy4thBounce, "pending_created", current_candle_time, "buy_limit", orderPrice, sl, tp, 30, orderTicket, 0, 0, (ENUM_DEAL_REASON)0, orderComment, tradeMagic);
               }
               
               // Reset to EA's default magic number for other operations
               ExtTrade.SetExpertMagicNumber(EA_MAGIC);
            }
         }
      }
   }

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