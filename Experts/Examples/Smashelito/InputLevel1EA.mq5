//+------------------------------------------------------------------+
//|                                                InputLevel1EA.mq5 |
//+------------------------------------------------------------------+
//|                   MetaTrader 5 Only (MT5-specific code)          |
//|        Copyright 2026, Aleksander Stefankowski                   |
// NOTE: This EA is MetaTrader 5 (MT5) ONLY. Do NOT attempt to add MT4 code.
// All file operations and tick/candle handling are MT5-specific.
// '&' reference cannot ever be used!


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

//--- Trade definition: buy_2nd_bounce (parameters only; entry rule below, no execution yet)
//    Type: buy_limit. Open price = level + PriceOffsetPips. TP/SL in pips. Expiration used for manual cancel logic.
input double   T_buy2ndBounce_LotSize           = 0.05;
input double   T_buy2ndBounce_PriceOffsetPips  = 7.0;   // desired open price = level + this many pips
input double   T_buy2ndBounce_TPPips           = 80.0;  // TP = order price + this many pips (e.g. 80 for 8 pts on US500 point=0.1)
input double   T_buy2ndBounce_SLPips           = 80.0;   // SL = order price - this many pips (e.g. 80 for 8 pts on US500 point=0.1)
input int      T_buy2ndBounce_ExpirationMinutes = 45;    // for manual cancel logic (not used as order expiry yet)
// Entry rule to open: level.bounceCount == 1 && bias_long (dailyBias > 0) && no_contact (!in_contact)

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
};
Level levels[];

//--- Trade type support
const long EA_MAGIC = 47001; // unique magic for this EA's orders
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

//+------------------------------------------------------------------+
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
}

//+------------------------------------------------------------------+
//| Pip size for current symbol (1 pip in price terms)               |
//+------------------------------------------------------------------+
double PipSize()
{
   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(d == 3 || d == 5) return SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0;
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
//| Count open positions + pending orders for a level (by comment)   |
//+------------------------------------------------------------------+
int CountOrdersAndPositionsForLevel(int levelIndex)
{
   string prefix = "L" + IntegerToString(levelIndex) + "_";
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!ExtPositionInfo.SelectByIndex(i)) continue;
      if(ExtPositionInfo.Symbol() != _Symbol || ExtPositionInfo.Magic() != EA_MAGIC) continue;
      if(StringFind(ExtPositionInfo.Comment(), prefix) == 0) count++;
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ExtOrderInfo.SelectByIndex(i)) continue;
      if(ExtOrderInfo.Symbol() != _Symbol || ExtOrderInfo.Magic() != EA_MAGIC) continue;
      if(StringFind(ExtOrderInfo.Comment(), prefix) == 0) count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Parse "L3_buy_2nd_bounce" -> levelIndex=3, tradeType="buy_2nd_bounce" |
//+------------------------------------------------------------------+
bool ParseLevelComment(const string comment, int &levelIndex, string &tradeType)
{
   if(StringFind(comment, "L") != 0) return false;
   int u = (int)StringFind(comment, "_");
   if(u <= 1) return false;
   string idxStr = StringSubstr(comment, 1, u - 1);
   levelIndex = (int)StringToInteger(idxStr);
   tradeType = StringSubstr(comment, u + 1);
   return (levelIndex >= 0 && levelIndex < ArraySize(levels) && StringLen(tradeType) > 0);
}

//+------------------------------------------------------------------+
//| Build B_TradeLog filename for a level and trade type              |
//+------------------------------------------------------------------+
string BuildTradeLogFileName(int levelIndex, const string tradeType, datetime forTime)
{
   if(levelIndex < 0 || levelIndex >= ArraySize(levels)) return "";
   string dateStr = TimeToString(forTime, TIME_DATE);
   double lvl = levels[levelIndex].price;
   return dateStr + "-" + levels[levelIndex].baseName + "_week" + dateStr +
          "_-" + DoubleToString(lvl, _Digits) + "_B_TradeLog_" + tradeType + ".txt";
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
//| Write one event line to per-level B_TradeLog (trade type)        |
//| orderKind: e.g. "buy_limit", "sell_limit", "market_buy" (optional) |
//| orderPrice/slPrice/tpPrice: if > 0, appended as prices (for pending_created) |
//+------------------------------------------------------------------+
void WriteTradeLog(int levelIndex, const string tradeType, const string eventType, datetime eventTime,
                  const string orderKind = "", double orderPrice = 0, double slPrice = 0, double tpPrice = 0)
{
   string fname = BuildTradeLogFileName(levelIndex, tradeType, eventTime);
   if(StringLen(fname) == 0) return;

   int fh = FileOpen(fname, FILE_WRITE | FILE_TXT | FILE_READ);
   if(fh == INVALID_HANDLE)
      fh = FileOpen(fname, FILE_WRITE | FILE_TXT);
   else
      FileSeek(fh, 0, SEEK_END);

   if(fh != INVALID_HANDLE)
   {
      string line = TimeToString(eventTime, TIME_DATE | TIME_SECONDS);
      if(StringLen(orderKind) > 0) line += " " + orderKind;
      if(orderPrice > 0)
         line += " orderPrice=" + DoubleToString(NormalizeDouble(orderPrice, _Digits), _Digits);
      line += " " + eventType;
      if(tpPrice > 0 && slPrice > 0)
         line += " tp=" + DoubleToString(NormalizeDouble(tpPrice, _Digits), _Digits) +
                 " sl=" + DoubleToString(NormalizeDouble(slPrice, _Digits), _Digits);
      FileWrite(fh, line);
      FileClose(fh);
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   Print("Level Logger EA initialized.");
   ExtTrade.SetExpertMagicNumber(EA_MAGIC);

   AddLevel("weeklyOneUp", 7031, "2026.02.23 00:00", "2026.02.28 23:59", "weekly");
   AddLevel("weeklySmash", 6960, "2026.02.23 00:00", "2026.02.28 23:59", "weekly,smash");
   AddLevel("weeklyOneDown", 6890, "2026.02.23 00:00", "2026.02.28 23:59", "weekly");
   AddLevel("weeklyTwoDown", 6805, "2026.02.23 00:00", "2026.02.28 23:59", "weekly");
   AddLevel("mondaySmash", 6910, "2026.02.23 00:00", "2026.02.23 23:59", "daily,monday,smash");
   AddLevel("thursdayThreeDown", 6912, "2026.02.26 00:00", "2026.02.26 23:59", "daily,thursday");
   AddLevel("fridayOneUp", 6976, "2026.02.27 00:00", "2026.02.27 23:59", "daily,friday");
   AddLevel("fridayOneDown", 6904, "2026.02.27 00:00", "2026.02.27 23:59", "daily,friday");
   AddLevel("fridayTwoDown", 6880, "2026.02.27 00:00", "2026.02.27 23:59", "daily,friday");
   AddLevel("fridayThreeDown", 6849, "2026.02.27 00:00", "2026.02.27 23:59", "daily,friday");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Log filled / TP / SL to B_TradeLog (per level per day)            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_ORDER_UPDATE && trans.order > 0)
   {
      if(!HistoryOrderSelect(trans.order)) return;
      if(HistoryOrderGetInteger(trans.order, ORDER_MAGIC) != EA_MAGIC) return;
      if(HistoryOrderGetString(trans.order, ORDER_SYMBOL) != _Symbol) return;
      if((ENUM_ORDER_STATE)HistoryOrderGetInteger(trans.order, ORDER_STATE) != ORDER_STATE_FILLED) return;

      string comment = HistoryOrderGetString(trans.order, ORDER_COMMENT);
      int levelIndex = -1;
      string tradeType = "";
      if(!ParseLevelComment(comment, levelIndex, tradeType)) return;

      datetime fillTime = (datetime)HistoryOrderGetInteger(trans.order, ORDER_TIME_DONE);
      string kindStr = OrderTypeToKindString((ENUM_ORDER_TYPE)HistoryOrderGetInteger(trans.order, ORDER_TYPE));
      WriteTradeLog(levelIndex, tradeType, "filled", fillTime, kindStr);
   }

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
   {
      if(!HistoryDealSelect(trans.deal)) return;
      if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != EA_MAGIC) return;
      if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

      // Entry deal = order filled (position opened) — log "filled" (tester often sends this instead of ORDER_UPDATE)
      if(entry == DEAL_ENTRY_IN)
      {
         ulong orderTicket = HistoryDealGetInteger(trans.deal, DEAL_ORDER);
         string comment = "";
         int levelIndex = -1;
         string tradeType = "";
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
         if(ParseLevelComment(comment, levelIndex, tradeType))
         {
            datetime fillTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
            if(fillTime == 0) fillTime = TimeCurrent();
            double fillPrice = 0;
            if(orderTicket > 0 && HistoryOrderSelect(orderTicket))
               fillPrice = HistoryOrderGetDouble(orderTicket, ORDER_PRICE_OPEN);
            if(fillPrice == 0) fillPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
            WriteTradeLog(levelIndex, tradeType, "filled", fillTime, kindStr, fillPrice, 0, 0);
         }
         return;
      }

      // Exit deal = position closed (TP or SL)
      ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
      if(reason != DEAL_REASON_TP && reason != DEAL_REASON_SL) return;

      ulong posId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      if(posId == 0) return;

      // Read closing deal time before changing history selection (selection can invalidate deal lookup)
      datetime closeTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
      if(closeTime == 0) closeTime = TimeCurrent();

      if(!HistorySelectByPosition((long)posId)) return;

      string comment = "";
      ulong entryOrderTicket = 0;
      int total = HistoryDealsTotal();
      for(int j = total - 1; j >= 0; j--)
      {
         ulong dealTicket = HistoryDealGetTicket(j);
         if(dealTicket == 0) continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
         entryOrderTicket = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
         break;
      }

      int levelIndex = -1;
      string tradeType = "";
      if(!ParseLevelComment(comment, levelIndex, tradeType)) return;

      string kindStr = "";
      if(entryOrderTicket > 0 && HistoryOrderSelect(entryOrderTicket))
         kindStr = OrderTypeToKindString((ENUM_ORDER_TYPE)HistoryOrderGetInteger(entryOrderTicket, ORDER_TYPE));

      string eventType = (reason == DEAL_REASON_TP) ? "tp" : "sl";
      WriteTradeLog(levelIndex, tradeType, eventType, closeTime, kindStr);
   }
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

            string araFile = dateStr + "-" + levels[i].baseName +
                             "_week" + dateStr +
                             "_-" + DoubleToString(lvl,_Digits) +
                             "_Arawevents.txt";

            levels[i].araFileHandle = FileOpen(araFile, FILE_WRITE|FILE_TXT|FILE_READ);
            if(levels[i].araFileHandle==INVALID_HANDLE)
               levels[i].araFileHandle = FileOpen(araFile, FILE_WRITE|FILE_TXT);
         }

         // distances
         double diffCloseToLevel = candle_close - lvl;
         double diffHL_MFE_toLevel;
         double hiOrLo;
         if(levels[i].dailyBias > 0) // long bias
         {
            diffHL_MFE_toLevel = candle_low - lvl;
            hiOrLo = candle_low;
         }
         else // short bias
         {
            diffHL_MFE_toLevel = candle_high - lvl;
            hiOrLo = candle_high;
         }

         bool physicallyTouched = (candle_low <= lvl && candle_high >= lvl);
         bool proximityTouched  = (MathAbs(diffHL_MFE_toLevel) <= ProximityThreshold);
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
            levels[i].bounceCount++;
         levels[i].lastCandleInContact = in_contact;

         // --- Write Arawevents
         if(levels[i].araFileHandle != INVALID_HANDLE)
         {
            FileWrite(levels[i].araFileHandle,
               "T: ", TimeToString(current_candle_time,TIME_DATE|TIME_MINUTES),
               " L: ", lvl,
               " C: ", NormalizeDouble(candle_close,_Digits),
               " Diff_CloseToLevel: ", NormalizeDouble(diffCloseToLevel,_Digits),
               " HiOrLo: ", NormalizeDouble(hiOrLo,_Digits),
               " Diff_HL_MFE_toLevel: ", NormalizeDouble(diffHL_MFE_toLevel,_Digits),
               " DayBias: ", (levels[i].dailyBias>0 ? "bias_long" : "bias_short"),
               " Contact: ", (in_contact ? "in_contact" : "no_contact"),
               " ContactCount: ", levels[i].approxContactCount,
               ", BounceCount: ", levels[i].bounceCount,
               ", CandlesBreakLevelCount: ", levels[i].candlesBreakLevelCount,
               ", RecoverCount: ", levels[i].recoverCount);
         }

         // --- Write per-level file if physically touched
         if(physicallyTouched)
         {
            string lvlFile = dateStr + "-" + levels[i].baseName +
                             "_week" + dateStr +
                             "_-" + DoubleToString(lvl,_Digits) + ".txt";

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

         // --- Trade type: buy_2nd_bounce
         // Entry rule: bounceCount==1, bias_long, no_contact. Params from T_buy2ndBounce_* inputs.
         {
            const string tradeTypeBuy2ndBounce = "buy_2nd_bounce";
            int current_all_trades = CountOrdersAndPositionsForLevel(i);
            bool bias_long = (levels[i].dailyBias > 0);
            bool no_contact = !in_contact;
            bool entryRule = (levels[i].bounceCount == 1) && bias_long && no_contact;
            bool allowed = (current_all_trades < Max_AnyOrder_perLevel) && entryRule;

            if(allowed)
            {
               double pip = PipSize();
               double orderPrice = NormalizeDouble(lvl + T_buy2ndBounce_PriceOffsetPips * pip, _Digits);
               double sl = NormalizeDouble(orderPrice - T_buy2ndBounce_SLPips * pip, _Digits);
               double tp = NormalizeDouble(orderPrice + T_buy2ndBounce_TPPips * pip, _Digits);
               string orderComment = "L" + IntegerToString(i) + "_" + tradeTypeBuy2ndBounce;

               if(ExtTrade.BuyLimit(T_buy2ndBounce_LotSize, orderPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, orderComment))
                  WriteTradeLog(i, tradeTypeBuy2ndBounce, "pending_created", current_candle_time, "buy_limit", orderPrice, sl, tp);
            }
         }
      }
   }

   if(allCandlesFileHandle != INVALID_HANDLE)
   {
      FileWrite(allCandlesFileHandle,
         "T: ", TimeToString(current_candle_time,TIME_DATE|TIME_MINUTES),
         " O: ", candle_open,
         " H: ", candle_high,
         " L: ", candle_low,
         " C: ", candle_close);
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