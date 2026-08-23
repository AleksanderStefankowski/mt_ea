//+------------------------------------------------------------------+
//| Level algo family (leading digit 3): limit-buy at tagged levels. |
//+------------------------------------------------------------------+
#ifndef ALEKSIK2_LEVEL_FAM_MQH
#define ALEKSIK2_LEVEL_FAM_MQH

struct LevelNearLevelPlacementCacheEntry
{
   double price;
   int    algoNumber;
};

LevelNearLevelPlacementCacheEntry g_levelNearLevelPlacementCache[];
int                               g_levelNearLevelPlacementCacheCount = 0;

void LevelRebuildAllRuleChains();
string LevelRunRulesFirstFail(const int slotIdx, const int barIdx, const double plannedTradePrice);

//+------------------------------------------------------------------+
bool LevelAlgoPendingOrderTypeCountsForNearLevelBlock(const ENUM_ORDER_TYPE orderType)
{
   return (orderType == ORDER_TYPE_BUY_LIMIT
      || orderType == ORDER_TYPE_SELL_LIMIT
      || orderType == ORDER_TYPE_BUY_STOP
      || orderType == ORDER_TYPE_SELL_STOP
      || orderType == ORDER_TYPE_BUY_STOP_LIMIT
      || orderType == ORDER_TYPE_SELL_STOP_LIMIT);
}

//+------------------------------------------------------------------+
void LevelNearLevelPlacementCacheClear()
{
   g_levelNearLevelPlacementCacheCount = 0;
}

//+------------------------------------------------------------------+
void LevelNearLevelPlacementCacheAppend(const double price, const int algoNumber)
{
   if(price <= 0.0)
      return;
   const int n = g_levelNearLevelPlacementCacheCount;
   if(n >= ArraySize(g_levelNearLevelPlacementCache))
   {
      int newCap = (n < 1 ? 256 : n * 2);
      if(!ArrayResize(g_levelNearLevelPlacementCache, newCap))
         FatalError("LevelNearLevelPlacementCacheAppend: ArrayResize failed");
   }
   g_levelNearLevelPlacementCache[n].price = price;
   g_levelNearLevelPlacementCache[n].algoNumber = algoNumber;
   g_levelNearLevelPlacementCacheCount = n + 1;
}

//+------------------------------------------------------------------+
void LevelNearLevelPlacementCacheBuild()
{
   const int est = PositionsTotal() + OrdersTotal();
   g_levelNearLevelPlacementCacheCount = 0;
   if(est > 0)
   {
      if(!ArrayResize(g_levelNearLevelPlacementCache, est))
         FatalError("LevelNearLevelPlacementCacheBuild: ArrayResize failed");
   }
   for(int pi = PositionsTotal() - 1; pi >= 0; pi--)
   {
      if(!ExtPositionInfo.SelectByIndex(pi))
         continue;
      if(ExtPositionInfo.Symbol() != _Symbol)
         continue;
      const long magic = (long)ExtPositionInfo.Magic();
      if(!IsLevelFamilyCompositeMagic(magic))
         continue;
      LevelNearLevelPlacementCacheAppend(ExtPositionInfo.PriceOpen(), AlgoFamilyMagicNumber(magic));
   }
   for(int oi = OrdersTotal() - 1; oi >= 0; oi--)
   {
      if(!ExtOrderInfo.SelectByIndex(oi))
         continue;
      if(ExtOrderInfo.Symbol() != _Symbol)
         continue;
      const ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)ExtOrderInfo.OrderType();
      if(!LevelAlgoPendingOrderTypeCountsForNearLevelBlock(orderType))
         continue;
      const long magic = (long)ExtOrderInfo.Magic();
      if(!IsLevelFamilyCompositeMagic(magic))
         continue;
      const double px = ExtOrderInfo.PriceOpen();
      if(px <= 0.0)
         continue;
      LevelNearLevelPlacementCacheAppend(px, AlgoFamilyMagicNumber(magic));
   }
}

//+------------------------------------------------------------------+
int LevelAlgoOpenPositionsOnSymbolForAlgo(const int algoNumber)
{
   if(!IsLevelFamilyAlgoNumber(algoNumber))
      return 0;
   int n = 0;
   for(int pi = PositionsTotal() - 1; pi >= 0; pi--)
   {
      if(!ExtPositionInfo.SelectByIndex(pi))
         continue;
      if(ExtPositionInfo.Symbol() != _Symbol)
         continue;
      const long magic = (long)ExtPositionInfo.Magic();
      if(!IsLevelFamilyCompositeMagic(magic))
         continue;
      if(AlgoFamilyMagicNumber(magic) != algoNumber)
         continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
int LevelAlgoPendingOrdersOnSymbolForAlgo(const int algoNumber)
{
   if(!IsLevelFamilyAlgoNumber(algoNumber))
      return 0;
   int n = 0;
   for(int oi = OrdersTotal() - 1; oi >= 0; oi--)
   {
      if(!ExtOrderInfo.SelectByIndex(oi))
         continue;
      if(ExtOrderInfo.Symbol() != _Symbol)
         continue;
      const ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)ExtOrderInfo.OrderType();
      if(!LevelAlgoPendingOrderTypeCountsForNearLevelBlock(orderType))
         continue;
      const long magic = (long)ExtOrderInfo.Magic();
      if(!IsLevelFamilyCompositeMagic(magic))
         continue;
      if(AlgoFamilyMagicNumber(magic) != algoNumber)
         continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
int LevelCachedOpenPositionsOnSymbolForAlgo(const int algoNumber)
{
   const int cacheIdx = AlgoOccupiedCacheIndex(algoNumber);
   if(cacheIdx >= 0 && cacheIdx < ALGO_OCCUPIED_CACHE_MAX)
      return g_algoFamilyOpenCount[cacheIdx];
   return LevelAlgoOpenPositionsOnSymbolForAlgo(algoNumber);
}

//+------------------------------------------------------------------+
int LevelCachedPendingOrdersOnSymbolForAlgo(const int algoNumber)
{
   const int cacheIdx = AlgoOccupiedCacheIndex(algoNumber);
   if(cacheIdx >= 0 && cacheIdx < ALGO_OCCUPIED_CACHE_MAX)
      return g_algoFamilyPendingCount[cacheIdx];
   return LevelAlgoPendingOrdersOnSymbolForAlgo(algoNumber);
}

//+------------------------------------------------------------------+
void RebuildLevelAlgoBannedRangesCache()
{
   ParseBannedRanges(g_levelAlgoShared.bannedRanges);
   if(g_bannedRangesCount > FALGO_BANNED_RANGES_MAX)
      FatalError(StringFormat("RebuildLevelAlgoBannedRangesCache: %d banned ranges exceeds FALGO_BANNED_RANGES_MAX=%d",
         g_bannedRangesCount, FALGO_BANNED_RANGES_MAX));
   for(int i = 0; i < g_bannedRangesCount; i++)
   {
      g_levelAlgoBannedRanges[i].startMin = g_bannedRangesBuffer[i][0] * 60 + g_bannedRangesBuffer[i][1];
      g_levelAlgoBannedRanges[i].endMin   = g_bannedRangesBuffer[i][2] * 60 + g_bannedRangesBuffer[i][3];
   }
   g_levelAlgoBannedRangeCount = g_bannedRangesCount;
}

//+------------------------------------------------------------------+
void RebuildLevelAlgoSlotsRegistry()
{
   g_levelAlgoCount = 0;
   for(int a = 0; a < LEVEL_ALGO_REGISTRY_MAX; a++)
      g_levelAlgoIdToSlot[a] = -1;
   const int n = ArraySize(g_levelAlgoRegistryIds);
   for(int i = 0; i < n; i++)
   {
      if(g_levelAlgoCount >= LEVEL_ALGO_REGISTRY_MAX)
         FatalError("RebuildLevelAlgoSlotsRegistry: LEVEL_ALGO_REGISTRY_MAX exceeded");
      const int algoId = g_levelAlgoRegistryIds[i];
      g_levelAlgos[g_levelAlgoCount].algo_id = algoId;
      const int idOff = algoId - MAGIC_LEVEL30000001;
      if(idOff >= 0 && idOff < LEVEL_ALGO_REGISTRY_MAX)
         g_levelAlgoIdToSlot[idOff] = g_levelAlgoCount;
      g_levelAlgoCount++;
   }
   if(LEVEL_ALGO_REGISTRY_MAX > g_levelAlgoCount + LEVEL_ALGO_REGISTRY_MAX_HEADROOM)
      FatalError(StringFormat(
         "LEVEL_ALGO_REGISTRY_MAX=%d exceeds wired level algo count %d by more than %d",
         LEVEL_ALGO_REGISTRY_MAX, g_levelAlgoCount, LEVEL_ALGO_REGISTRY_MAX_HEADROOM));
}

//+------------------------------------------------------------------+
int LevelAlgoSlotIndexByAlgoId(const int algoNumber)
{
   if(!IsLevelFamilyAlgoNumber(algoNumber))
      return -1;
   const int idOff = algoNumber - MAGIC_LEVEL30000001;
   if(idOff >= 0 && idOff < LEVEL_ALGO_REGISTRY_MAX)
   {
      const int slot = g_levelAlgoIdToSlot[idOff];
      if(slot >= 0 && slot < g_levelAlgoCount && g_levelAlgos[slot].algo_id == algoNumber)
         return slot;
   }
   for(int i = 0; i < g_levelAlgoCount; i++)
      if(g_levelAlgos[i].algo_id == algoNumber)
         return i;
   return -1;
}

//+------------------------------------------------------------------+
bool LevelAlgoDefForNumber(const int algoNumber, LevelAlgoDef &outDef)
{
   const int idx = LevelAlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   outDef = g_levelAlgos[idx];
   return true;
}

//+------------------------------------------------------------------+
double GetTradeLotForLevelAlgo()
{
   return g_global_base_trade_size * ((double)g_levelAlgoShared.tradeSizePct / 100.0);
}

//+------------------------------------------------------------------+
bool LevelAlgoIsTradingTimeAllowed(const datetime t)
{
   MqlDateTime mt;
   TimeToStruct(t, mt);
   const int curMin = mt.hour * 60 + mt.min;
   return !FalgoIsMinutesInBannedRanges(curMin, g_levelAlgoBannedRanges, g_levelAlgoBannedRangeCount);
}

//+------------------------------------------------------------------+
bool LevelAlgoIsTradingDayAllowedAtTime(const datetime t)
{
   if(g_levelAlgoShared.use_banned_days_QOPEX && FalgoIsOpexWeekCalendarDate(t))
      return false;
   if(g_levelAlgoShared.use_banned_days_holidays && FalgoIsMarketHolidayOrShortDayCalendarDate(t))
      return false;
   const int slot = FalgoDayOfWeekSlotFromTimeOrInvalid(t);
   if(slot < 1)
      return false;
   const string days = g_levelAlgoShared.tradesDays;
   if(StringLen(days) < 1)
      return true;
   return (StringFind(days, IntegerToString(slot)) >= 0);
}

//+------------------------------------------------------------------+
bool LevelAlgoProfileAllowsPlacementAtTime(const datetime t)
{
   bool anyEnabled = false;
   for(int i = 0; i < g_levelAlgoCount; i++)
   {
      if(g_levelAlgos[i].enabled)
      {
         anyEnabled = true;
         break;
      }
   }
   if(!anyEnabled)
      return false;
   if(!BigflipperPlacementAllowedAtTime(t))
      return false;
   if(!LevelAlgoIsTradingDayAllowedAtTime(t))
      return false;
   if(!LevelAlgoIsTradingTimeAllowed(t))
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool LevelAlgoProfileAllowsPlacementAtBar(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return false;
   return LevelAlgoProfileAllowsPlacementAtTime(g_m1Rates[barIdx].time);
}

//+------------------------------------------------------------------+
bool LevelAlgoTagMatches(const string &levelTag, const string &wantTag)
{
   string t = levelTag;
   StringToLower(t);
   string w = wantTag;
   StringToLower(w);
   if(StringLen(w) < 1)
      return false;
   return (StringFind(t, w) >= 0);
}

//+------------------------------------------------------------------+
bool LevelAlgoTagMatchesAny(const string &levelTag, const string &wantTags[])
{
   const int n = ArraySize(wantTags);
   if(n < 1)
      return false;
   for(int i = 0; i < n; i++)
   {
      if(LevelAlgoTagMatches(levelTag, wantTags[i]))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
double LevelAlgoComputeOrderPrice(const LevelAlgoDef &la, const double levelPrice)
{
   const double pctPart = levelPrice * la.offset_percentage;
   const double signedPct = la.offset_positive ? pctPart : -pctPart;
   return NormalizeDouble(levelPrice + signedPct, _Digits);
}

//+------------------------------------------------------------------+
bool LevelAlgoBarInProximityAboveLevel(const double levelPrice, const double o, const double h,
   const double l, const double c, const double proximity)
{
   if(proximity <= 0.0)
      return false;
   const double vals[4] = {o, h, l, c};
   for(int i = 0; i < 4; i++)
   {
      if(vals[i] >= levelPrice && vals[i] <= levelPrice + proximity)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
double LevelAlgoOvernightOpenPrice()
{
   if(g_ONopen > 0.0)
      return g_ONopen;
   if(g_barsInDay > 0)
      return g_m1Rates[0].open;
   return 0.0;
}

//+------------------------------------------------------------------+
int LevelAlgoOccupiedTradeSlotsForAlgo(const int algoNumber)
{
   return LevelAlgoOpenPositionsOnSymbolForAlgo(algoNumber)
      + LevelAlgoPendingOrdersOnSymbolForAlgo(algoNumber);
}

//+------------------------------------------------------------------+
bool LevelAnyFamilyOccupiedOnSymbolCached()
{
   return g_levelFamilyAnyOccupied;
}

//+------------------------------------------------------------------+
bool LevelAlgoOpenOrPendingNearLevel(const double levelPrice, const LevelAlgoDef &la,
   const int thisAlgoNumber, const bool familyScope)
{
   const double radius = MathAbs(levelPrice) * la.offset_percentage * la.cannotTrade__when_levelProximity_multiplyOffset;
   if(radius <= 0.0)
      return false;
   for(int i = 0; i < g_levelNearLevelPlacementCacheCount; i++)
   {
      const LevelNearLevelPlacementCacheEntry e = g_levelNearLevelPlacementCache[i];
      if(!familyScope && e.algoNumber != thisAlgoNumber)
         continue;
      if(MathAbs(e.price - levelPrice) <= radius)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool LevelAlgoBlockedNearLevelByLevelFam(const double levelPrice, const int slotIdx)
{
   if(!g_levelAlgoShared.cannotTrade__when_levelFamOpenOrPendingNearLevel)
      return false;
   if(slotIdx < 0 || slotIdx >= g_levelAlgoCount)
      return false;
   return LevelAlgoOpenOrPendingNearLevel(levelPrice, g_levelAlgos[slotIdx], g_levelAlgos[slotIdx].algo_id, true);
}

//+------------------------------------------------------------------+
bool LevelAlgoBlockedNearLevelByThisAlgo(const double levelPrice, const int slotIdx)
{
   if(slotIdx < 0 || slotIdx >= g_levelAlgoCount)
      return false;
   if(!g_levelAlgos[slotIdx].cannotTrade__when_thisAlgoOpenOrPendingNearLevel)
      return false;
   return LevelAlgoOpenOrPendingNearLevel(levelPrice, g_levelAlgos[slotIdx], g_levelAlgos[slotIdx].algo_id, false);
}

//+------------------------------------------------------------------+
bool LevelAlgoRulesetPassesDayStopsForSlot(const int slotIdx)
{
   if(slotIdx < 0 || slotIdx >= g_levelAlgoCount)
      return false;
   const LevelAlgoDef la = g_levelAlgos[slotIdx];
   if(g_levelAlgoDayLosses[slotIdx] >= la.stop_trading_today_if_thisAlgo_losing_trades_count)
      return false;
   if(g_levelAlgoDayWins[slotIdx] >= la.stop_trading_today_if_thisAlgo_winning_trades_count)
      return false;
   if(g_levelAlgoDayTradesToday[slotIdx] >= la.stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count)
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool LevelAlgoUnderMaxOpenPositionsLimitForSlot(const int slotIdx)
{
   if(slotIdx < 0 || slotIdx >= g_levelAlgoCount)
      return true;
   if(g_levelAlgos[slotIdx].max_open_positions <= 0)
      return true;
   return BreakdownCachedOccupiedTradeSlotsForAlgo(g_levelAlgos[slotIdx].algo_id) < g_levelAlgos[slotIdx].max_open_positions;
}

//+------------------------------------------------------------------+
bool LevelAlgoUnderMaxConcurrentPendingTradesLimitForSlot(const int slotIdx)
{
   if(slotIdx < 0 || slotIdx >= g_levelAlgoCount)
      return true;
   if(g_levelAlgos[slotIdx].this_algo_max_concurrent_pending_trades <= 0)
      return true;
   return BreakdownCachedPendingTradeSlotsForAlgo(g_levelAlgos[slotIdx].algo_id)
      < g_levelAlgos[slotIdx].this_algo_max_concurrent_pending_trades;
}

//+------------------------------------------------------------------+
bool LevelAlgoUnderMaxOpenPositionsLimit(const int algoNumber)
{
   LevelAlgoDef la;
   if(!LevelAlgoDefForNumber(algoNumber, la))
      return true;
   if(la.max_open_positions <= 0)
      return true;
   return BreakdownCachedOccupiedTradeSlotsForAlgo(algoNumber) < la.max_open_positions;
}

//+------------------------------------------------------------------+
bool LevelAlgoUnderMaxConcurrentPendingTradesLimit(const int algoNumber)
{
   LevelAlgoDef la;
   if(!LevelAlgoDefForNumber(algoNumber, la))
      return true;
   if(la.this_algo_max_concurrent_pending_trades <= 0)
      return true;
   return BreakdownCachedPendingTradeSlotsForAlgo(algoNumber) < la.this_algo_max_concurrent_pending_trades;
}

//+------------------------------------------------------------------+
bool FalgoBuildMagicKeyForLevelAlgoPlacement(const int levelIdx, const double entryPrice,
   const LevelAlgoDef &la, FalgoMagicKey &outKey)
{
   outKey.direction = FALGO_DIRECTION_LONG_LIMIT;
   outKey.levelSlot = FalgoMagicLevelSlotFromLevelIdx(levelIdx);
   outKey.bounceCount = 0;
   outKey.ceilingCount = 0;
   outKey.offset_tenths = 0;
   outKey.planTradeNum = 0;
   outKey.levelTradeNum = 0;
   outKey.babysitMinute = 0;
   outKey.tpWhole = 0;
   outKey.slWhole = 0;
   outKey.secretTpPointsAbovePlanned = 0;
   outKey.ruleSwitchMap = FalgoClampRuleSwitchMap(la.rule_switch_map);

   if(la.secret_tp_profit_percent_min > 0.0)
   {
      if(entryPrice <= 0.0)
         return false;
      const double secretTpPrice = FalgoSecretTpPriceForProfitPctMin(entryPrice, la.secret_tp_profit_percent_min);
      outKey.secretTpPointsAbovePlanned = FalgoEncodeSecretTpPointsAbovePlanned(entryPrice, secretTpPrice);
      if(outKey.secretTpPointsAbovePlanned <= 0)
         return false;
   }

   if(la.secret_tp_greenguard_pricediff_at_least > 0.0)
   {
      int greenguardTenths = (int)MathRound(la.secret_tp_greenguard_pricediff_at_least * 10.0);
      if(greenguardTenths < 0)
         greenguardTenths = 0;
      if(greenguardTenths > 99)
         greenguardTenths = 99;
      outKey.offset_tenths = greenguardTenths;
   }
   return true;
}

//+------------------------------------------------------------------+
bool PlacePendingFromFalgoMagicLevel(const long magic, const double orderPrice, const double brokerTpPrice,
   const int expirationMin, const double lot)
{
   if(!IsLevelFamilyCompositeMagic(magic))
      return false;
   if(orderPrice <= 0.0 || brokerTpPrice <= orderPrice)
      return false;

   const double orderNorm = NormalizeDouble(orderPrice, _Digits);
   const double tpNorm = NormalizeDouble(brokerTpPrice, _Digits);
   if(PlacePending_ShouldSkip_BidTooCloseToOrderPrice(orderNorm, 1.0))
      return false;

   datetime expiration = TimeCurrent() + expirationMin * 60;
   const string comment = "lvlfam";
   ExtTrade.SetExpertMagicNumber(magic);
   LogPreOrderContext(magic, orderNorm, orderNorm, "BuyLimit", expirationMin);
   const bool ok = ExtTrade.BuyLimit(lot, orderNorm, _Symbol, 0.0, tpNorm, ORDER_TIME_SPECIFIED, expiration, comment);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   return ok;
}

//+------------------------------------------------------------------+
void LevelAlgoUpdateDayState()
{
   FalgoResetAllFamilyDayCountersIfNewCalendarDay();
}

//+------------------------------------------------------------------+
void LevelAlgoOpenLifetimePosMapRebuild()
{
   FalgoLifetimePosMapClear(g_levelAlgoLifetimePosMapSlot, FALGO_LIFETIME_POS_MAP_BUCKETS);
   for(int si = 0; si < LEVEL_ALGO_OPEN_LIFETIME_MAX; si++)
   {
      if(!g_levelAlgoOpenLifetime[si].active)
         continue;
      const ulong positionId = g_levelAlgoOpenLifetime[si].positionId;
      if(positionId == 0)
         continue;
      FalgoLifetimePosMapInsert(positionId, si, g_levelAlgoLifetimePosMapKey, g_levelAlgoLifetimePosMapSlot,
         FALGO_LIFETIME_POS_MAP_BUCKETS);
   }
}

//+------------------------------------------------------------------+
int LevelAlgoEnsureSecretTpLifetimeSlot(const ulong positionId, const long magic, const datetime startTime,
   const double fillPrice, const double plannedPrice)
{
   int lifeIdx = LevelAlgoOpenLifetimeSlotByPositionId(positionId);
   if(lifeIdx >= 0)
      return lifeIdx;
   for(int i = 0; i < LEVEL_ALGO_OPEN_LIFETIME_MAX; i++)
   {
      if(g_levelAlgoOpenLifetime[i].active)
         continue;
      ZeroMemory(g_levelAlgoOpenLifetime[i]);
      g_levelAlgoOpenLifetime[i].positionId = positionId;
      g_levelAlgoOpenLifetime[i].algoNumber = AlgoFamilyMagicNumber(magic);
      g_levelAlgoOpenLifetime[i].startTime = startTime;
      g_levelAlgoOpenLifetime[i].startPrice = fillPrice;
      g_levelAlgoOpenLifetime[i].plannedPrice = (plannedPrice > 0.0 ? plannedPrice : fillPrice);
      g_levelAlgoOpenLifetime[i].active = true;
      FalgoLifetimePosMapInsert(positionId, i, g_levelAlgoLifetimePosMapKey, g_levelAlgoLifetimePosMapSlot,
         FALGO_LIFETIME_POS_MAP_BUCKETS);
      FalgoLifetimeEnsureRolloverState(startTime, g_levelAlgoOpenLifetime[i].rolloverWedDayStart,
         g_levelAlgoOpenLifetime[i].withRolloverFee, g_levelAlgoOpenLifetime[i].rolloverPricediff);
      return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
bool LevelAlgoTakeOpenTradeLifetime(const ulong positionId, FalgoSecretTpLifetimeRec &outRec)
{
   ZeroMemory(outRec);
   for(int i = 0; i < LEVEL_ALGO_OPEN_LIFETIME_MAX; i++)
   {
      if(g_levelAlgoOpenLifetime[i].active && g_levelAlgoOpenLifetime[i].positionId == positionId)
      {
         outRec = g_levelAlgoOpenLifetime[i];
         g_levelAlgoOpenLifetime[i].active = false;
         LevelAlgoOpenLifetimePosMapRebuild();
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
void LevelAlgoApplyOneClosedTradeCounts(const TradeResult &tr)
{
   if(!tr.foundOut || !IsLevelFamilyCompositeMagic(tr.magic))
      return;
   const datetime dayStart = FalgoTradingDayStart();
   const datetime dayEnd = (dayStart != 0) ? (dayStart + 86400) : 0;
   if(dayStart != 0 && (tr.endTime < dayStart || tr.endTime >= dayEnd))
      return;
   const int slotIdx = LevelAlgoSlotIndexByAlgoId(AlgoFamilyMagicNumber(tr.magic));
   if(slotIdx < 0)
      return;
   if(tr.profit > 0.0)
      g_levelAlgoDayWins[slotIdx]++;
   else if(tr.profit < 0.0)
      g_levelAlgoDayLosses[slotIdx]++;
}

//+------------------------------------------------------------------+
void LevelAlgoRebuildDayCountersFromLoadedTradeResults(const datetime dayStart)
{
   for(int si = 0; si < LEVEL_ALGO_REGISTRY_MAX; si++)
   {
      g_levelAlgoDayTradesToday[si] = 0;
      g_levelAlgoDayWins[si] = 0;
      g_levelAlgoDayLosses[si] = 0;
   }

   const datetime dayEnd = (dayStart != 0) ? (dayStart + 86400) : 0;
   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      const TradeResult tr = g_tradeResults[i];
      if(!IsLevelFamilyCompositeMagic(tr.magic))
         continue;
      const int slotIdx = LevelAlgoSlotIndexByAlgoId(AlgoFamilyMagicNumber(tr.magic));
      if(slotIdx < 0)
         continue;
      if(tr.foundOut && dayStart != 0 && tr.endTime >= dayStart && tr.endTime < dayEnd)
         LevelAlgoApplyOneClosedTradeCounts(tr);
      if(FalgoTradeStartedOnTradingDay(tr, dayStart))
         g_levelAlgoDayTradesToday[slotIdx]++;
   }
}

//+------------------------------------------------------------------+
void LevelAlgoLogTradeOpenedLifetime(const ulong positionId, const long magic, const datetime fillTime,
   const double fillPrice, const ulong orderTicket)
{
   if(!IsLevelFamilyCompositeMagic(magic))
      return;
   const int algoNumber = AlgoFamilyMagicNumber(magic);
   if(!IsLevelFamilyAlgoNumber(algoNumber))
      return;

   double plannedPrice = 0.0;
   if(orderTicket > 0 && HistoryOrderSelect(orderTicket))
      plannedPrice = HistoryOrderGetDouble(orderTicket, ORDER_PRICE_OPEN);
   if(plannedPrice <= 0.0)
      plannedPrice = fillPrice;

   const double startPrice = (fillPrice > 0.0 ? fillPrice : plannedPrice);
   const datetime startTime = (fillTime > 0 ? fillTime : g_lastTimer1Time);
   const bool isNewOpen = (LevelAlgoOpenLifetimeSlotByPositionId(positionId) < 0);
   const int lifeIdx = LevelAlgoEnsureSecretTpLifetimeSlot(positionId, magic, startTime, startPrice, plannedPrice);
   if(lifeIdx >= 0)
      LevelAlgoHydrateLifetimeSecretTpFromMagic(lifeIdx, positionId, magic);
   if(isNewOpen && lifeIdx >= 0)
   {
      LevelAlgoUpdateDayState();
      const datetime dayStart = FalgoTradingDayStart();
      if(dayStart != 0 && startTime >= dayStart && startTime < dayStart + 86400)
      {
         const int slotIdx = LevelAlgoSlotIndexByAlgoId(algoNumber);
         if(slotIdx >= 0)
            g_levelAlgoDayTradesToday[slotIdx]++;
      }
   }
}

//+------------------------------------------------------------------+
void LevelAlgoLogTradeClosedLifetime(const ulong positionId, const long entryMagic, const datetime closeTime,
   const double closePriceIn, const ENUM_DEAL_REASON dealReason, const double closeProfitIn)
{
   if(!IsLevelFamilyCompositeMagic(entryMagic))
      return;

   FalgoSecretTpLifetimeRec openRec;
   datetime startTime = 0;
   double plannedPrice = 0.0;
   double startPrice = 0.0;
   bool withRolloverFee = false;
   double rolloverPricediff = 0.0;
   int tradeCustomId = 0;
   int algoNumber = AlgoFamilyMagicNumber(entryMagic);
   const bool gotOpenRec = LevelAlgoTakeOpenTradeLifetime(positionId, openRec);
   if(gotOpenRec)
   {
      algoNumber = openRec.algoNumber;
      tradeCustomId = openRec.tradeCustomId;
      startTime = openRec.startTime;
      plannedPrice = openRec.plannedPrice;
      startPrice = openRec.startPrice;
      withRolloverFee = openRec.withRolloverFee;
      rolloverPricediff = openRec.rolloverPricediff;
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
         if(!IsLevelFamilyAlgoNumber(algoNumber))
            algoNumber = AlgoFamilyMagicNumber(HistoryDealGetInteger(dealTicket, DEAL_MAGIC));
         break;
      }
   }
   if(!IsLevelFamilyAlgoNumber(algoNumber) || startTime <= 0)
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
   if(gotOpenRec)
   {
      FalgoLifetimeResolveRolloverForClose(startTime, eventTime, openRec.rolloverWedDayStart,
         openRec.withRolloverFee, openRec.rolloverPricediff, withRolloverFee, rolloverPricediff);
      FalgoBtPushClosedStats(entryMagic, startTime, openRec.mfePts, openRec.maePts, openRec.maeFirstWindowPts,
         openRec.mfeCandle1Based, openRec.maeCandle1Based, openRec.closeDecisionReason, openRec.closeDecisionDetail,
         withRolloverFee, rolloverPricediff);
   }
   FalgoAppendClosedTradeToAllDaysSummaryFromLifetime(positionId, entryMagic, startTime, startTime, eventTime,
      startPrice, closePrice, dealReason, closeProfitIn, withRolloverFee, rolloverPricediff, plannedPrice, tradeCustomId);
}

//+------------------------------------------------------------------+
bool LevelAlgoLevelTagEligibleForSlot(const int levelIdx, const int slotIdx)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount || slotIdx < 0 || slotIdx >= g_levelAlgoCount)
      return false;
   return LevelAlgoTagMatchesAny(g_levelsExpanded[levelIdx].tag, g_levelAlgos[slotIdx].trades_tags);
}

//+------------------------------------------------------------------+
int LevelAlgoPlacementScopeKindForSlot(const int slotIdx)
{
   if(slotIdx < 0 || slotIdx >= g_levelAlgoCount)
      return -1;
   const bool tradesWeekly = g_levelAlgos[slotIdx].trades_weekly;
   const bool tradesDaily = g_levelAlgos[slotIdx].trades_daily;
   if(tradesWeekly && tradesDaily)
      return LEVEL_PLACEMENT_SCOPE_BOTH;
   if(tradesWeekly)
      return LEVEL_PLACEMENT_SCOPE_WEEKLY;
   if(tradesDaily)
      return LEVEL_PLACEMENT_SCOPE_DAILY;
   return -1;
}

//+------------------------------------------------------------------+
int LevelPlacementBarLevelCountForScope(const int scopeKind)
{
   if(scopeKind == LEVEL_PLACEMENT_SCOPE_WEEKLY)
      return g_levelPlacementBarLevelCountWeekly;
   if(scopeKind == LEVEL_PLACEMENT_SCOPE_DAILY)
      return g_levelPlacementBarLevelCountDaily;
   if(scopeKind == LEVEL_PLACEMENT_SCOPE_BOTH)
      return g_levelPlacementBarLevelCountBoth;
   return 0;
}

//+------------------------------------------------------------------+
int LevelPlacementBarLevelIdxForScope(const int scopeKind, const int candidateIdx)
{
   if(scopeKind == LEVEL_PLACEMENT_SCOPE_WEEKLY)
      return g_levelPlacementBarLevelIdxWeekly[candidateIdx];
   if(scopeKind == LEVEL_PLACEMENT_SCOPE_DAILY)
      return g_levelPlacementBarLevelIdxDaily[candidateIdx];
   if(scopeKind == LEVEL_PLACEMENT_SCOPE_BOTH)
      return g_levelPlacementBarLevelIdxBoth[candidateIdx];
   return -1;
}

//+------------------------------------------------------------------+
bool LevelPlacementAnyBarLevelCandidates()
{
   return (g_levelPlacementBarLevelCountWeekly > 0
      || g_levelPlacementBarLevelCountDaily > 0
      || g_levelPlacementBarLevelCountBoth > 0);
}

//+------------------------------------------------------------------+
bool LevelBarCouldTouchAnyLevelProximity(const int barIdx, const double proximity)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || g_levelsTodayCount <= 0 || proximity <= 0.0)
      return false;
   const double h = g_m1Rates[barIdx].high;
   const double l = g_m1Rates[barIdx].low;
   double minLevelPrice = g_levelsExpanded[0].levelPrice;
   double maxLevelPrice = minLevelPrice;
   for(int levelIdx = 1; levelIdx < g_levelsTodayCount; levelIdx++)
   {
      const double levelPrice = g_levelsExpanded[levelIdx].levelPrice;
      if(levelPrice < minLevelPrice)
         minLevelPrice = levelPrice;
      if(levelPrice > maxLevelPrice)
         maxLevelPrice = levelPrice;
   }
   return (h >= minLevelPrice && l <= maxLevelPrice + proximity);
}

//+------------------------------------------------------------------+
void LevelPlacementAppendBarLevelForScope(const int scopeKind, const int levelIdx)
{
   if(scopeKind == LEVEL_PLACEMENT_SCOPE_WEEKLY)
   {
      if(g_levelPlacementBarLevelCountWeekly >= MAX_LEVELS_EXPANDED)
         FatalError("LevelPlacementAppendBarLevelForScope: weekly MAX_LEVELS_EXPANDED exceeded");
      g_levelPlacementBarLevelIdxWeekly[g_levelPlacementBarLevelCountWeekly++] = levelIdx;
      return;
   }
   if(scopeKind == LEVEL_PLACEMENT_SCOPE_DAILY)
   {
      if(g_levelPlacementBarLevelCountDaily >= MAX_LEVELS_EXPANDED)
         FatalError("LevelPlacementAppendBarLevelForScope: daily MAX_LEVELS_EXPANDED exceeded");
      g_levelPlacementBarLevelIdxDaily[g_levelPlacementBarLevelCountDaily++] = levelIdx;
      return;
   }
   if(scopeKind == LEVEL_PLACEMENT_SCOPE_BOTH)
   {
      if(g_levelPlacementBarLevelCountBoth >= MAX_LEVELS_EXPANDED)
         FatalError("LevelPlacementAppendBarLevelForScope: both MAX_LEVELS_EXPANDED exceeded");
      g_levelPlacementBarLevelIdxBoth[g_levelPlacementBarLevelCountBoth++] = levelIdx;
   }
}

//+------------------------------------------------------------------+
void LevelPlacementBuildBarLevelCandidates(const int barIdx)
{
   g_levelPlacementBarLevelCountWeekly = 0;
   g_levelPlacementBarLevelCountDaily = 0;
   g_levelPlacementBarLevelCountBoth = 0;
   if(barIdx < 0 || barIdx >= g_barsInDay || g_levelsTodayCount <= 0)
      return;

   const double proximity = g_levelAlgoShared.price_proximity_above_level;
   if(proximity <= 0.0)
      return;
   if(!LevelBarCouldTouchAnyLevelProximity(barIdx, proximity))
      return;

   bool anyNeedsBelowOno = false;
   for(int si = 0; si < g_levelAlgoCount; si++)
   {
      if(!g_levelAlgos[si].enabled)
         continue;
      if(g_levelAlgos[si].level_needs_to_be_below_ONO)
      {
         anyNeedsBelowOno = true;
         break;
      }
   }

   const datetime barTime = g_m1Rates[barIdx].time;
   const double o = g_m1Rates[barIdx].open;
   const double h = g_m1Rates[barIdx].high;
   const double l = g_m1Rates[barIdx].low;
   const double c = g_m1Rates[barIdx].close;
   const double ono = LevelAlgoOvernightOpenPrice();

   for(int levelIdx = 0; levelIdx < g_levelsTodayCount; levelIdx++)
   {
      if(LevelIsTertiary(g_levelsExpanded[levelIdx].categories))
         continue;
      const double levelPrice = g_levelsExpanded[levelIdx].levelPrice;
      if(anyNeedsBelowOno && ono > 0.0 && levelPrice >= ono)
         continue;
      if(!LevelAlgoBarInProximityAboveLevel(levelPrice, o, h, l, c, proximity))
         continue;

      const string categories = g_levelsExpanded[levelIdx].categories;
      if(LevelEligibleForAlgoLevelScope(categories, true, false, barTime))
         LevelPlacementAppendBarLevelForScope(LEVEL_PLACEMENT_SCOPE_WEEKLY, levelIdx);
      if(LevelEligibleForAlgoLevelScope(categories, false, true, barTime))
         LevelPlacementAppendBarLevelForScope(LEVEL_PLACEMENT_SCOPE_DAILY, levelIdx);
      if(LevelEligibleForAlgoLevelScope(categories, true, true, barTime))
         LevelPlacementAppendBarLevelForScope(LEVEL_PLACEMENT_SCOPE_BOTH, levelIdx);
   }
}

//+------------------------------------------------------------------+
bool LevelPlacementPassesCheapCandidateChecks(const int slotIdx, const bool familyOccupied)
{
   if(slotIdx < 0 || slotIdx >= g_levelAlgoCount)
      return false;
   if(!g_levelAlgos[slotIdx].enabled)
      return false;
   if(!LevelAlgoRulesetPassesDayStopsForSlot(slotIdx))
      return false;
   if(!LevelAlgoUnderMaxOpenPositionsLimitForSlot(slotIdx))
      return false;
   if(!LevelAlgoUnderMaxConcurrentPendingTradesLimitForSlot(slotIdx))
      return false;
   if(g_levelAlgoShared.blockPlacementIfFamilyOpenOrPending && familyOccupied)
      return false;
   if(LevelPlacementBarLevelCountForScope(LevelAlgoPlacementScopeKindForSlot(slotIdx)) <= 0)
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool AlgoTryPlaceLevelAlgoLimitBuyForSlot(const int slotIdx, const int barIdx)
{
   if(slotIdx < 0 || slotIdx >= g_levelAlgoCount)
      return false;
   if(!g_levelAlgos[slotIdx].enabled)
      return false;
   const int algoNumber = g_levelAlgos[slotIdx].algo_id;
   if(!IsLevelFamilyAlgoNumber(algoNumber))
      return false;

   const int scopeKind = LevelAlgoPlacementScopeKindForSlot(slotIdx);
   const int levelCandidateCount = LevelPlacementBarLevelCountForScope(scopeKind);
   if(levelCandidateCount <= 0)
      return false;

   const bool profOn = BacktestProfileEnabled();
   const datetime barTime = g_m1Rates[barIdx].time;
   const double ono = LevelAlgoOvernightOpenPrice();
   const double lot = GetTradeLotForLevelAlgo();

   for(int ci = 0; ci < levelCandidateCount; ci++)
   {
      const int levelIdx = LevelPlacementBarLevelIdxForScope(scopeKind, ci);
      if(levelIdx < 0)
         continue;
      if(!LevelAlgoLevelTagEligibleForSlot(levelIdx, slotIdx))
         continue;

      const double levelPrice = g_levelsExpanded[levelIdx].levelPrice;
      if(g_levelAlgos[slotIdx].level_needs_to_be_below_ONO && ono > 0.0 && levelPrice >= ono)
         continue;

      ulong profNearT0 = 0;
      if(profOn)
         profNearT0 = GetMicrosecondCount();
      if(LevelAlgoBlockedNearLevelByLevelFam(levelPrice, slotIdx))
         continue;
      if(LevelAlgoBlockedNearLevelByThisAlgo(levelPrice, slotIdx))
         continue;
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_LEVEL_ALGO_PLACEMENT_NEAR_LEVEL, profNearT0);

      const double orderPrice = LevelAlgoComputeOrderPrice(g_levelAlgos[slotIdx], levelPrice);
      if(orderPrice <= 0.0)
         continue;
      const string ruleFail = LevelRunRulesFirstFail(slotIdx, barIdx, orderPrice);
      if(ruleFail != "")
         continue;
      const double brokerTpPrice = NormalizeDouble(orderPrice + g_levelAlgos[slotIdx].real_tp, _Digits);
      if(brokerTpPrice <= orderPrice)
         continue;

      ulong profOrdT0 = 0;
      if(profOn)
         profOrdT0 = GetMicrosecondCount();

      FalgoMagicKey planKey;
      if(!FalgoBuildMagicKeyForLevelAlgoPlacement(levelIdx, orderPrice, g_levelAlgos[slotIdx], planKey))
         continue;
      const long magic = BuildAlgoMagicNumber(algoNumber, planKey);

      // Fresh terminal scan: cheap pass runs once/bar; fills can land between that check and place.
      if(g_levelAlgos[slotIdx].max_open_positions > 0 &&
         BreakdownOccupiedTradeSlotsForAlgo(algoNumber) >= g_levelAlgos[slotIdx].max_open_positions)
         continue;
      if(g_levelAlgos[slotIdx].this_algo_max_concurrent_pending_trades > 0 &&
         BreakdownPendingTradeSlotsForAlgo(algoNumber) >= g_levelAlgos[slotIdx].this_algo_max_concurrent_pending_trades)
         continue;

      if(!PlacePendingFromFalgoMagicLevel(magic, orderPrice, brokerTpPrice, g_levelAlgos[slotIdx].expiry_minutes, lot))
         continue;

      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_LEVEL_ALGO_PLACEMENT_ORDERS, profOrdT0);

      AlgoFamilyOccupiedCacheNotePendingPlaced(algoNumber);
      LevelNearLevelPlacementCacheAppend(orderPrice, algoNumber);
      FalgoBumpPlanCountersAfterPlacement(algoNumber, planKey.levelSlot);
      g_levelFamilyAnyOccupied = true;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void RunLevelAlgoPlacementOnM1Close(const int barIdx)
{
   const bool profOn = BacktestProfileEnabled();
   ulong profT0 = 0;
   if(profOn)
      profT0 = GetMicrosecondCount();

   LevelAlgoUpdateDayState();
   if(barIdx < 0 || barIdx >= g_barsInDay)
   {
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_LEVEL_ALGO_PLACEMENT_SETUP, profT0);
      return;
   }
   if(!LevelAlgoProfileAllowsPlacementAtBar(barIdx))
   {
      if(profOn)
         BacktestProfAccumulate(BACKTEST_PROF_LEVEL_ALGO_PLACEMENT_SETUP, profT0);
      return;
   }
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_LEVEL_ALGO_PLACEMENT_SETUP, profT0);

   RefreshOccupiedMagicsCache();
   LevelNearLevelPlacementCacheBuild();

   if(profOn)
      profT0 = GetMicrosecondCount();
   LevelPlacementBuildBarLevelCandidates(barIdx);
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_LEVEL_ALGO_PLACEMENT_BAR_LEVELS, profT0);

   if(!LevelPlacementAnyBarLevelCandidates())
      return;

   const bool familyOccupied = g_levelAlgoShared.blockPlacementIfFamilyOpenOrPending && g_levelFamilyAnyOccupied;
   if(familyOccupied)
      return;

   if(profOn)
      profT0 = GetMicrosecondCount();
   g_levelPlacementCandidateCount = 0;
   for(int si = 0; si < g_levelAlgoCount; si++)
   {
      if(!LevelPlacementPassesCheapCandidateChecks(si, familyOccupied))
         continue;
      g_levelPlacementCandidateSlots[g_levelPlacementCandidateCount++] = si;
   }
   if(profOn)
      BacktestProfAccumulate(BACKTEST_PROF_LEVEL_ALGO_PLACEMENT_CHEAP, profT0);

   for(int ci = 0; ci < g_levelPlacementCandidateCount; ci++)
      AlgoTryPlaceLevelAlgoLimitBuyForSlot(g_levelPlacementCandidateSlots[ci], barIdx);
}

//+------------------------------------------------------------------+
int LevelAlgoOpenLifetimeSlotByPositionId(const ulong positionId)
{
   const int mapped = FalgoLifetimePosMapFind(positionId, g_levelAlgoLifetimePosMapKey, g_levelAlgoLifetimePosMapSlot,
      FALGO_LIFETIME_POS_MAP_BUCKETS);
   if(mapped >= 0 && mapped < LEVEL_ALGO_OPEN_LIFETIME_MAX && g_levelAlgoOpenLifetime[mapped].active)
      return mapped;
   return -1;
}

//+------------------------------------------------------------------+
void LevelAlgoHydrateLifetimeRuleSwitchFromMagic(const int lifeIdx, const long magic)
{
   if(lifeIdx < 0 || lifeIdx >= LEVEL_ALGO_OPEN_LIFETIME_MAX || !g_levelAlgoOpenLifetime[lifeIdx].active)
      return;
   if(g_levelAlgoOpenLifetime[lifeIdx].ruleSwitchHydrated)
      return;
   g_levelAlgoOpenLifetime[lifeIdx].ruleSwitchMap = FalgoRuleSwitchMapFromMagic(magic);
   g_levelAlgoOpenLifetime[lifeIdx].ruleSwitchHydrated = true;
}

//+------------------------------------------------------------------+
bool LevelAlgoHydrateLifetimeSecretTpFromMagic(const int lifeIdx, const ulong positionId, const long magic)
{
   if(lifeIdx < 0 || lifeIdx >= LEVEL_ALGO_OPEN_LIFETIME_MAX || !g_levelAlgoOpenLifetime[lifeIdx].active)
      return false;
   LevelAlgoHydrateLifetimeRuleSwitchFromMagic(lifeIdx, magic);
   if(g_levelAlgoOpenLifetime[lifeIdx].secretTpPrice > 0.0)
      return true;

   double plannedPrice = g_levelAlgoOpenLifetime[lifeIdx].plannedPrice;
   if(plannedPrice <= 0.0)
      plannedPrice = g_levelAlgoOpenLifetime[lifeIdx].startPrice;
   if(plannedPrice <= 0.0)
      return false;

   const double secretTpPrice = FalgoLevelAlgoSecretTpPriceFromMagic(magic, plannedPrice);
   if(secretTpPrice <= 0.0)
      return false;

   g_levelAlgoOpenLifetime[lifeIdx].secretTpPrice = secretTpPrice;
   g_levelAlgoOpenLifetime[lifeIdx].secretTpGreenguardPricediffAtLeast = FalgoLevelAlgoGreenguardPricediffFromMagic(magic);
   return true;
}

//+------------------------------------------------------------------+
bool Babysitf_falgo_runLevelAlgoSecretTpExit(const long posMagic, const double rolloverForGuard, const int lifeIdxIn)
{
   int lifeIdx = lifeIdxIn;
   const ulong posTicket = ExtPositionInfo.Ticket();
   const ulong positionId = (ulong)ExtPositionInfo.Identifier();
   if(lifeIdx < 0)
   {
      lifeIdx = LevelAlgoEnsureSecretTpLifetimeSlot(positionId, posMagic,
         (datetime)ExtPositionInfo.Time(), ExtPositionInfo.PriceOpen(), ExtPositionInfo.PriceOpen());
   }
   if(lifeIdx < 0)
      return false;

   if(!g_levelAlgoOpenLifetime[lifeIdx].ruleSwitchHydrated)
      LevelAlgoHydrateLifetimeRuleSwitchFromMagic(lifeIdx, posMagic);
   if(!FalgoRuleSwitchAllowsSecretTpCloseNow(g_levelAlgoOpenLifetime[lifeIdx].ruleSwitchMap, g_lastTimer1Time))
      return false;

   if(g_levelAlgoOpenLifetime[lifeIdx].secretTpPrice <= 0.0)
      LevelAlgoHydrateLifetimeSecretTpFromMagic(lifeIdx, positionId, posMagic);

   const double secretTpPrice = g_levelAlgoOpenLifetime[lifeIdx].secretTpPrice;
   if(secretTpPrice <= 0.0)
      return false;

   const double entryPrice = ExtPositionInfo.PriceOpen();
   const double bid = g_liveBid;
   if(entryPrice <= 0.0 || bid <= 0.0)
      return false;

   const double greenguard = g_levelAlgoOpenLifetime[lifeIdx].secretTpGreenguardPricediffAtLeast;
   if(!FalgoSecretTpReachedWithRollover(secretTpPrice, bid, rolloverForGuard))
      return false;
   if(!FalgoSecretTpGreenGuardPriceDiffAllowsClose(greenguard, entryPrice, bid, rolloverForGuard))
      return false;

   const double rollCost = MathMax(0.0, rolloverForGuard);
   const string closeDetail = StringFormat("bid=%s|bidWithRoll=%s|secretTp=%s|fill=%s|roll=%s|greenguard=%s",
      DoubleToString(bid, _Digits), DoubleToString(bid - rollCost, _Digits), DoubleToString(secretTpPrice, _Digits),
      DoubleToString(entryPrice, _Digits), DoubleToString(rolloverForGuard, _Digits),
      DoubleToString(greenguard, _Digits));
   LevelAlgoRememberCloseDecision(positionId, "level_secretTPSL_tp", closeDetail);
   LevelAlgoRememberPendingCloseReason(positionId, "secretTP");
   FalgoFlipperPrintfManualCloseDecision("level", "secretTP", posMagic, posTicket, positionId, closeDetail);

   LevelAlgoDef la;
   string closeComment = "";
   if(LevelAlgoDefForNumber(AlgoFamilyMagicNumber(posMagic), la))
   {
      closeComment = FalgoBuildManualCloseCommentLevel(la.secret_tp_profit_percent_min,
         la.secret_tp_greenguard_pricediff_at_least, rolloverForGuard);
   }
   double profitPts = 0.0;
   double accountProfit = 0.0;
   return FalgoPositionCloseWithManualComment(posMagic, posTicket, closeComment, profitPts, accountProfit);
}

//+------------------------------------------------------------------+
void LevelAlgoHydrateSecretTpFromOpenPositionsOnInit()
{
   for(int pi = PositionsTotal() - 1; pi >= 0; pi--)
   {
      if(!ExtPositionInfo.SelectByIndex(pi))
         continue;
      if(ExtPositionInfo.Symbol() != _Symbol)
         continue;
      const long magic = (long)ExtPositionInfo.Magic();
      if(!IsLevelFamilyCompositeMagic(magic))
         continue;
      const ulong positionId = (ulong)ExtPositionInfo.Identifier();
      const int lifeIdx = LevelAlgoEnsureSecretTpLifetimeSlot(positionId, magic,
         (datetime)ExtPositionInfo.Time(), ExtPositionInfo.PriceOpen(), ExtPositionInfo.PriceOpen());
      if(lifeIdx >= 0)
      {
         LevelAlgoHydrateLifetimeSecretTpFromMagic(lifeIdx, positionId, magic);
         FalgoLifetimeEnsureRolloverState(g_levelAlgoOpenLifetime[lifeIdx].startTime,
            g_levelAlgoOpenLifetime[lifeIdx].rolloverWedDayStart,
            g_levelAlgoOpenLifetime[lifeIdx].withRolloverFee,
            g_levelAlgoOpenLifetime[lifeIdx].rolloverPricediff);
      }
   }
}

//+------------------------------------------------------------------+
void SyncLevelAlgoFamilyProfileFromInputs()
{
   RebuildLevelAlgoSlotsRegistry();
// levelbookmark
   g_levelAlgoShared.use_banned_days_QOPEX = true;
   g_levelAlgoShared.use_banned_days_holidays = false;
   g_levelAlgoShared.babysit_enabled = true;
   g_levelAlgoShared.blockPlacementIfFamilyOpenOrPending = false;
   g_levelAlgoShared.cannotTrade__when_levelFamOpenOrPendingNearLevel = false;
   g_levelAlgoShared.stop_trading_if_day_has_X_wins_0_losses = 9999;
   g_levelAlgoShared.stop_trading_if_day_has_profit_factor_above = 9999;
   g_levelAlgoShared.stop_trading_today_if_AllAlgos_losing_trades_count = 999;
   g_levelAlgoShared.stop_trading_today_if_AllAlgos_winning_trades_count = 999;
   g_levelAlgoShared.tradeSizePct = 100;
   g_levelAlgoShared.bannedRanges = "22,0,23,59;0,0,1,59"; // ban 22:00–23:59 and 00:00–01:59; 02:00+ allowed
   g_levelAlgoShared.tradesDays = "12345";
   g_levelAlgoShared.price_proximity_above_level = 25.00;

//levelalgocreator2start
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].enabled = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].enabled = true; // quantref base=30000024 new=30000037 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;midpoint below=- ratecut=0.6708 timeVSprofit=1.775 percentSum_w_roll=50.36 tradesCount=218
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].enabled = true; // quantref base=30000012 new=30000038 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;midpoint below=- ratecut=0.6718 timeVSprofit=1.772 percentSum_w_roll=50.60 tradesCount=219
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].enabled = true; // quantref base=30000036 new=30000039 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6585 timeVSprofit=1.745 percentSum_w_roll=54.63 tradesCount=214
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].enabled = true; // quantref base=30000036 new=30000040 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6585 timeVSprofit=1.745 percentSum_w_roll=54.63 tradesCount=214
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].enabled = true; // quantref base=30000024 new=30000041 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6892 timeVSprofit=1.741 percentSum_w_roll=51.81 tradesCount=224
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].enabled = true; // quantref base=30000024 new=30000042 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6892 timeVSprofit=1.741 percentSum_w_roll=51.81 tradesCount=224
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].enabled = true; // quantref base=30000012 new=30000043 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6902 timeVSprofit=1.738 percentSum_w_roll=52.05 tradesCount=225
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].enabled = true; // quantref base=30000012 new=30000044 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6902 timeVSprofit=1.738 percentSum_w_roll=52.05 tradesCount=225
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].enabled = true; // quantref base=30000011 new=30000045 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;midpoint below=- ratecut=0.6739 timeVSprofit=1.508 percentSum_w_roll=63.56 tradesCount=281
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].enabled = true; // quantref base=30000023 new=30000046 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;midpoint below=- ratecut=0.6739 timeVSprofit=1.508 percentSum_w_roll=63.56 tradesCount=281
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].enabled = true; // quantref base=30000023 new=30000047 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6882 timeVSprofit=1.495 percentSum_w_roll=64.98 tradesCount=287
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].enabled = true; // quantref base=30000023 new=30000048 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6882 timeVSprofit=1.495 percentSum_w_roll=64.98 tradesCount=287
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].enabled = true; // quantref base=30000011 new=30000049 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6882 timeVSprofit=1.495 percentSum_w_roll=64.98 tradesCount=287
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].enabled = true; // quantref base=30000011 new=30000050 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6882 timeVSprofit=1.495 percentSum_w_roll=64.98 tradesCount=287
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].enabled = true; // quantref base=30000010 new=30000051 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6949 timeVSprofit=1.386 percentSum_w_roll=86.50 tradesCount=394
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].enabled = true; // quantref base=30000010 new=30000052 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6949 timeVSprofit=1.386 percentSum_w_roll=86.50 tradesCount=394
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].enabled = true; // quantref base=30000022 new=30000053 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6949 timeVSprofit=1.386 percentSum_w_roll=86.50 tradesCount=394
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].enabled = true; // quantref base=30000022 new=30000054 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6949 timeVSprofit=1.386 percentSum_w_roll=86.50 tradesCount=394
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].enabled = true; // quantref base=30000022 new=30000055 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;midpoint below=- ratecut=0.6667 timeVSprofit=1.378 percentSum_w_roll=83.17 tradesCount=378
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].enabled = true; // quantref base=30000010 new=30000056 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;midpoint below=- ratecut=0.6667 timeVSprofit=1.378 percentSum_w_roll=83.17 tradesCount=378
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].enabled = true; // quantref base=30000034 new=30000057 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6623 timeVSprofit=1.24 percentSum_w_roll=90.02 tradesCount=355
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].enabled = true; // quantref base=30000034 new=30000058 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6623 timeVSprofit=1.24 percentSum_w_roll=90.02 tradesCount=355
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].enabled = true; // quantref base=30000035 new=30000059 modes=best_timevsprofit above=midpoint below=- ratecut=0.6789 timeVSprofit=1.232 percentSum_w_roll=53.81 tradesCount=203
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].enabled = true; // quantref base=30000035 new=30000060 modes=best_timevsprofit above=ONH;midpoint below=- ratecut=0.6789 timeVSprofit=1.232 percentSum_w_roll=53.81 tradesCount=203
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].enabled = true; // quantref base=30000035 new=30000061 modes=best_timevsprofit above=PDH;midpoint below=- ratecut=0.6789 timeVSprofit=1.232 percentSum_w_roll=53.81 tradesCount=203
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].enabled = true; // quantref base=30000020 new=30000062 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;midpoint below=- ratecut=0.6624 timeVSprofit=1.145 percentSum_w_roll=89.28 tradesCount=410
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].enabled = true; // quantref base=30000008 new=30000063 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;midpoint below=- ratecut=0.6624 timeVSprofit=1.145 percentSum_w_roll=89.28 tradesCount=410
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].enabled = true; // quantref base=30000036 new=30000064 modes=best_timevsprofit above=midpoint below=- ratecut=0.6677 timeVSprofit=1.124 percentSum_w_roll=56.71 tradesCount=217
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].enabled = true; // quantref base=30000008 new=30000065 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6866 timeVSprofit=1.123 percentSum_w_roll=92.37 tradesCount=425
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].enabled = true; // quantref base=30000008 new=30000066 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6866 timeVSprofit=1.123 percentSum_w_roll=92.37 tradesCount=425
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].enabled = true; // quantref base=30000020 new=30000067 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6866 timeVSprofit=1.123 percentSum_w_roll=92.37 tradesCount=425
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].enabled = true; // quantref base=30000020 new=30000068 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6866 timeVSprofit=1.123 percentSum_w_roll=92.37 tradesCount=425
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].enabled = true; // quantref base=30000016 new=30000069 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6531 timeVSprofit=1.005 percentSum_w_roll=100.58 tradesCount=467
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].enabled = true; // quantref base=30000016 new=30000070 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6531 timeVSprofit=1.005 percentSum_w_roll=100.58 tradesCount=467
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].enabled = true; // quantref base=30000004 new=30000071 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6531 timeVSprofit=1.005 percentSum_w_roll=100.58 tradesCount=467
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].enabled = true; // quantref base=30000004 new=30000072 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6531 timeVSprofit=1.005 percentSum_w_roll=100.58 tradesCount=467
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].enabled = true; // quantref base=30000033 new=30000073 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6705 timeVSprofit=0.971 percentSum_w_roll=118.87 tradesCount=468
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].enabled = true; // quantref base=30000033 new=30000074 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDH below=- ratecut=0.6705 timeVSprofit=0.971 percentSum_w_roll=118.87 tradesCount=468
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].enabled = true; // quantref base=30000033 new=30000075 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6705 timeVSprofit=0.971 percentSum_w_roll=118.87 tradesCount=468
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].enabled = true; // quantref base=30000014 new=30000076 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6662 timeVSprofit=0.954 percentSum_w_roll=94.88 tradesCount=439
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].enabled = true; // quantref base=30000014 new=30000077 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6662 timeVSprofit=0.954 percentSum_w_roll=94.88 tradesCount=439
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].enabled = true; // quantref base=30000002 new=30000078 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDC;dayHighSoFar below=- ratecut=0.6662 timeVSprofit=0.954 percentSum_w_roll=94.88 tradesCount=439
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].enabled = true; // quantref base=30000002 new=30000079 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDC below=- ratecut=0.6662 timeVSprofit=0.954 percentSum_w_roll=94.88 tradesCount=439
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].enabled = true; // quantref base=30000034 new=30000080 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6959 timeVSprofit=0.917 percentSum_w_roll=96.13 tradesCount=373
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].enabled = true; // quantref base=30000021 new=30000081 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDH below=- ratecut=0.7036 timeVSprofit=0.91 percentSum_w_roll=110.94 tradesCount=508
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].enabled = true; // quantref base=30000021 new=30000082 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.7036 timeVSprofit=0.91 percentSum_w_roll=110.94 tradesCount=508
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].enabled = true; // quantref base=30000021 new=30000083 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.7036 timeVSprofit=0.91 percentSum_w_roll=110.94 tradesCount=508
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].enabled = true; // quantref base=30000009 new=30000084 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;PDH below=- ratecut=0.7036 timeVSprofit=0.91 percentSum_w_roll=110.94 tradesCount=508
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].enabled = true; // quantref base=30000009 new=30000085 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.7036 timeVSprofit=0.91 percentSum_w_roll=110.94 tradesCount=508
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].enabled = true; // quantref base=30000009 new=30000086 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.7036 timeVSprofit=0.91 percentSum_w_roll=110.94 tradesCount=508
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].enabled = true; // quantref base=30000032 new=30000087 modes=best_timevsprofit above=dayHighSoFar;midpoint below=- ratecut=0.6551 timeVSprofit=0.84 percentSum_w_roll=97.00 tradesCount=378
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].enabled = true; // quantref base=30000032 new=30000088 modes=best_timevsprofit above=midpoint below=- ratecut=0.6551 timeVSprofit=0.84 percentSum_w_roll=97.00 tradesCount=378
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].enabled = true; // quantref base=30000032 new=30000089 modes=best_timevsprofit above=ONH;midpoint below=- ratecut=0.6551 timeVSprofit=0.84 percentSum_w_roll=97.00 tradesCount=378
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].enabled = true; // quantref base=30000007 new=30000090 modes=best_timevsprofit above=dayHighSoFar;midpoint below=- ratecut=0.6516 timeVSprofit=0.839 percentSum_w_roll=115.07 tradesCount=533
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].enabled = true; // quantref base=30000019 new=30000091 modes=best_timevsprofit above=midpoint below=- ratecut=0.6516 timeVSprofit=0.839 percentSum_w_roll=115.07 tradesCount=533
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].enabled = true; // quantref base=30000019 new=30000092 modes=best_timevsprofit above=ONH;midpoint below=- ratecut=0.6516 timeVSprofit=0.839 percentSum_w_roll=115.07 tradesCount=533
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].enabled = true; // quantref base=30000019 new=30000093 modes=best_timevsprofit above=dayHighSoFar;midpoint below=- ratecut=0.6516 timeVSprofit=0.839 percentSum_w_roll=115.07 tradesCount=533
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].enabled = true; // quantref base=30000007 new=30000094 modes=best_timevsprofit above=ONH;midpoint below=- ratecut=0.6516 timeVSprofit=0.839 percentSum_w_roll=115.07 tradesCount=533
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].enabled = true; // quantref base=30000007 new=30000095 modes=best_timevsprofit above=midpoint below=- ratecut=0.6516 timeVSprofit=0.839 percentSum_w_roll=115.07 tradesCount=533
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].enabled = true; // quantref base=30000028 new=30000096 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6730 timeVSprofit=0.838 percentSum_w_roll=114.14 tradesCount=457
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].enabled = true; // quantref base=30000028 new=30000097 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6730 timeVSprofit=0.838 percentSum_w_roll=114.14 tradesCount=457
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].enabled = true; // quantref base=30000028 new=30000098 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6730 timeVSprofit=0.838 percentSum_w_roll=114.14 tradesCount=457
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].enabled = true; // quantref base=30000004 new=30000099 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.7091 timeVSprofit=0.814 percentSum_w_roll=110.54 tradesCount=507
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].enabled = true; // quantref base=30000016 new=30000100 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.7091 timeVSprofit=0.814 percentSum_w_roll=110.54 tradesCount=507
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].enabled = true; // quantref base=30000031 new=30000101 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6526 timeVSprofit=0.813 percentSum_w_roll=123.41 tradesCount=494
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].enabled = true; // quantref base=30000031 new=30000102 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6526 timeVSprofit=0.813 percentSum_w_roll=123.41 tradesCount=494
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].enabled = true; // quantref base=30000031 new=30000103 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6526 timeVSprofit=0.813 percentSum_w_roll=123.41 tradesCount=494
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].enabled = true; // quantref base=30000030 new=30000104 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6551 timeVSprofit=0.793 percentSum_w_roll=129.69 tradesCount=528
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].enabled = true; // quantref base=30000030 new=30000105 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6538 timeVSprofit=0.792 percentSum_w_roll=129.47 tradesCount=527
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].enabled = true; // quantref base=30000030 new=30000106 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6538 timeVSprofit=0.792 percentSum_w_roll=129.47 tradesCount=527
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].enabled = true; // quantref base=30000014 new=30000107 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.7056 timeVSprofit=0.782 percentSum_w_roll=101.48 tradesCount=465
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].enabled = true; // quantref base=30000002 new=30000108 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.7056 timeVSprofit=0.782 percentSum_w_roll=101.48 tradesCount=465
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].enabled = true; // quantref base=30000001 new=30000109 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6934 timeVSprofit=0.78 percentSum_w_roll=128.66 tradesCount=606
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].enabled = true; // quantref base=30000001 new=30000110 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6922 timeVSprofit=0.78 percentSum_w_roll=128.47 tradesCount=605
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].enabled = true; // quantref base=30000001 new=30000111 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6922 timeVSprofit=0.78 percentSum_w_roll=128.47 tradesCount=605
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].enabled = true; // quantref base=30000013 new=30000112 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6934 timeVSprofit=0.78 percentSum_w_roll=128.66 tradesCount=606
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].enabled = true; // quantref base=30000013 new=30000113 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6922 timeVSprofit=0.78 percentSum_w_roll=128.47 tradesCount=605
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].enabled = true; // quantref base=30000013 new=30000114 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6922 timeVSprofit=0.78 percentSum_w_roll=128.47 tradesCount=605
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].enabled = true; // quantref base=30000003 new=30000115 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6876 timeVSprofit=0.762 percentSum_w_roll=133.19 tradesCount=634
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].enabled = true; // quantref base=30000003 new=30000116 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6866 timeVSprofit=0.762 percentSum_w_roll=133.00 tradesCount=633
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].enabled = true; // quantref base=30000003 new=30000117 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6866 timeVSprofit=0.762 percentSum_w_roll=133.00 tradesCount=633
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].enabled = true; // quantref base=30000015 new=30000118 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6866 timeVSprofit=0.762 percentSum_w_roll=133.00 tradesCount=633
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].enabled = true; // quantref base=30000015 new=30000119 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6866 timeVSprofit=0.762 percentSum_w_roll=133.00 tradesCount=633
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].enabled = true; // quantref base=30000015 new=30000120 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6876 timeVSprofit=0.762 percentSum_w_roll=133.19 tradesCount=634
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].enabled = true; // quantref base=30000006 new=30000121 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6921 timeVSprofit=0.745 percentSum_w_roll=131.24 tradesCount=616
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].enabled = true; // quantref base=30000006 new=30000122 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6910 timeVSprofit=0.745 percentSum_w_roll=131.08 tradesCount=615
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].enabled = true; // quantref base=30000006 new=30000123 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6910 timeVSprofit=0.745 percentSum_w_roll=131.08 tradesCount=615
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].enabled = true; // quantref base=30000018 new=30000124 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6910 timeVSprofit=0.745 percentSum_w_roll=131.08 tradesCount=615
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].enabled = true; // quantref base=30000018 new=30000125 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6921 timeVSprofit=0.745 percentSum_w_roll=131.24 tradesCount=616
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].enabled = true; // quantref base=30000018 new=30000126 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6910 timeVSprofit=0.745 percentSum_w_roll=131.08 tradesCount=615
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].enabled = true; // quantref base=30000017 new=30000127 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6574 timeVSprofit=0.695 percentSum_w_roll=147.43 tradesCount=710
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].enabled = true; // quantref base=30000005 new=30000128 modes=best_timevsprofit,best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6574 timeVSprofit=0.695 percentSum_w_roll=147.43 tradesCount=710
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].enabled = true; // quantref base=30000017 new=30000129 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6528 timeVSprofit=0.692 percentSum_w_roll=146.52 tradesCount=705
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].enabled = true; // quantref base=30000017 new=30000130 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6528 timeVSprofit=0.692 percentSum_w_roll=146.52 tradesCount=705
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].enabled = true; // quantref base=30000005 new=30000131 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6528 timeVSprofit=0.692 percentSum_w_roll=146.52 tradesCount=705
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].enabled = true; // quantref base=30000005 new=30000132 modes=best_timevsprofit,best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6528 timeVSprofit=0.692 percentSum_w_roll=146.52 tradesCount=705
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].enabled = true; // quantref base=30000026 new=30000133 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDH;PDO below=- ratecut=0.6986 timeVSprofit=0.082 percentSum_w_roll=50.16 tradesCount=204
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].enabled = true; // quantref base=30000026 new=30000134 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDO below=- ratecut=0.6986 timeVSprofit=0.082 percentSum_w_roll=50.16 tradesCount=204
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].enabled = true; // quantref base=30000025 new=30000135 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDH below=- ratecut=0.8627 timeVSprofit=0.056 percentSum_w_roll=172.08 tradesCount=704
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].enabled = true; // quantref base=30000027 new=30000136 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDH below=- ratecut=0.8666 timeVSprofit=0.055 percentSum_w_roll=178.33 tradesCount=734
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].enabled = true; // quantref base=30000029 new=30000137 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDH below=- ratecut=0.8530 timeVSprofit=0.05 percentSum_w_roll=189.05 tradesCount=789
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].enabled = true; // quantref base=30000026 new=30000138 modes=best_timevsprofit,best_timeVSprofitVSratecut above=PDH below=- ratecut=0.8938 timeVSprofit=0.048 percentSum_w_roll=63.59 tradesCount=261
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].enabled = true; // quantref base=30000035 new=30000139 modes=best_timeVSprofitVSratecut above=ONH;PDH below=- ratecut=0.6957 timeVSprofit=1.21 percentSum_w_roll=55.07 tradesCount=208
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].enabled = true; // quantref base=30000035 new=30000140 modes=best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6957 timeVSprofit=1.21 percentSum_w_roll=55.07 tradesCount=208
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].enabled = true; // quantref base=30000035 new=30000141 modes=best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6957 timeVSprofit=1.21 percentSum_w_roll=55.07 tradesCount=208
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].enabled = true; // quantref base=30000036 new=30000142 modes=best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6831 timeVSprofit=1.12 percentSum_w_roll=58.05 tradesCount=222
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].enabled = true; // quantref base=30000019 new=30000143 modes=best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6993 timeVSprofit=0.831 percentSum_w_roll=122.87 tradesCount=572
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].enabled = true; // quantref base=30000019 new=30000144 modes=best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6993 timeVSprofit=0.831 percentSum_w_roll=122.87 tradesCount=572
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].enabled = true; // quantref base=30000019 new=30000145 modes=best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6993 timeVSprofit=0.831 percentSum_w_roll=122.87 tradesCount=572
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].secret_tp_profit_percent_min = 2.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].enabled = true; // quantref base=30000007 new=30000146 modes=best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6993 timeVSprofit=0.831 percentSum_w_roll=122.87 tradesCount=572
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].enabled = true; // quantref base=30000007 new=30000147 modes=best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6993 timeVSprofit=0.831 percentSum_w_roll=122.87 tradesCount=572
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].enabled = true; // quantref base=30000007 new=30000148 modes=best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6993 timeVSprofit=0.831 percentSum_w_roll=122.87 tradesCount=572
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].secret_tp_profit_percent_min = 1.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].enabled = true; // quantref base=30000032 new=30000149 modes=best_timeVSprofitVSratecut above=ONH below=- ratecut=0.6742 timeVSprofit=0.833 percentSum_w_roll=99.71 tradesCount=389
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].enabled = true; // quantref base=30000032 new=30000150 modes=best_timeVSprofitVSratecut above=dayHighSoFar below=- ratecut=0.6742 timeVSprofit=0.833 percentSum_w_roll=99.71 tradesCount=389
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].enabled = true; // quantref base=30000032 new=30000151 modes=best_timeVSprofitVSratecut above=ONH;dayHighSoFar below=- ratecut=0.6742 timeVSprofit=0.833 percentSum_w_roll=99.71 tradesCount=389
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].secret_tp_profit_percent_min = 4.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].rule_switch_map = 0;
//levelalgocreator2end
   LevelRebuildAllRuleChains();
   RebuildLevelAlgoBannedRangesCache();
}

//+------------------------------------------------------------------+
//| Per-day gates / logic log for level algos (bigflipper). |
//+------------------------------------------------------------------+
string LevelAlgoCsvFileName(const string dateStr, const int algoNumber, const string suffix)
{
   return dateStr + "_levelalgo" + IntegerToString(algoNumber) + "_" + suffix + ".csv";
}

//+------------------------------------------------------------------+
bool LevelAlgoSlotEnabled(const int algoNumber)
{
   const int idx = LevelAlgoSlotIndexByAlgoId(algoNumber);
   if(idx < 0)
      return false;
   return g_levelAlgos[idx].enabled;
}

//+------------------------------------------------------------------+
void LevelAlgoGatesFailFlagsAppend(string &outFlags[], const string flag)
{
   if(flag == "")
      return;
   const int n = ArraySize(outFlags);
   ArrayResize(outFlags, n + 1);
   outFlags[n] = flag;
}

//+------------------------------------------------------------------+
void LevelAlgoCollectPlacementFailFlags(const int slotIdx, const int barIdx, const datetime evalTime,
   string &outFlags[], int &outEligibleCount, double &outProximityLevel, string &outLevelTag,
   double &outPlannedOrderPrice)
{
   ArrayResize(outFlags, 0);
   outEligibleCount = 0;
   outProximityLevel = 0.0;
   outLevelTag = "";
   outPlannedOrderPrice = 0.0;
   if(slotIdx < 0 || slotIdx >= g_levelAlgoCount)
      return;

   const LevelAlgoDef la = g_levelAlgos[slotIdx];
   const int algoNumber = la.algo_id;

   if(!la.enabled)
      LevelAlgoGatesFailFlagsAppend(outFlags, "profileDisabled");
   if(!LevelAlgoIsTradingDayAllowedAtTime(evalTime))
      LevelAlgoGatesFailFlagsAppend(outFlags, "tradingDayBanned");
   if(!LevelAlgoIsTradingTimeAllowed(evalTime))
      LevelAlgoGatesFailFlagsAppend(outFlags, "tradingTimeBanned");
   if(!BigflipperPlacementAllowedAtTime(evalTime))
      LevelAlgoGatesFailFlagsAppend(outFlags, "bigflipperStopAfterDate");
   if(g_levelAlgoDayLosses[slotIdx] >= la.stop_trading_today_if_thisAlgo_losing_trades_count)
      LevelAlgoGatesFailFlagsAppend(outFlags, "lossStopDayLimit");
   if(g_levelAlgoDayWins[slotIdx] >= la.stop_trading_today_if_thisAlgo_winning_trades_count)
      LevelAlgoGatesFailFlagsAppend(outFlags, "winStopDayLimit");
   if(g_levelAlgoDayWins[slotIdx] + g_levelAlgoDayLosses[slotIdx]
      >= la.stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count)
      LevelAlgoGatesFailFlagsAppend(outFlags, "todayTotalTradesLimit");
   if(!LevelAlgoUnderMaxOpenPositionsLimit(algoNumber))
      LevelAlgoGatesFailFlagsAppend(outFlags, "maxOpenPositionsReached");
   if(!LevelAlgoUnderMaxConcurrentPendingTradesLimit(algoNumber))
      LevelAlgoGatesFailFlagsAppend(outFlags, "maxConcurrentPendingReached");
   if(g_levelAlgoShared.blockPlacementIfFamilyOpenOrPending && LevelAnyFamilyOccupiedOnSymbolCached())
      LevelAlgoGatesFailFlagsAppend(outFlags, "levelFamOpenOrPendingOnSymbol");
   if(g_levelsTodayCount <= 0)
      LevelAlgoGatesFailFlagsAppend(outFlags, "noLevelsLoaded");

   if(barIdx < 0 || barIdx >= g_barsInDay)
   {
      LevelAlgoGatesFailFlagsAppend(outFlags, "invalidBarIdx");
      return;
   }
   if(ArraySize(outFlags) > 0)
      return;
   const int scopeKind = LevelAlgoPlacementScopeKindForSlot(slotIdx);
   const int scopeLevelCount = LevelPlacementBarLevelCountForScope(scopeKind);
   if(scopeLevelCount <= 0)
   {
      LevelAlgoGatesFailFlagsAppend(outFlags, "noProximityAboveLevel");
      return;
   }

   const datetime barTime = g_m1Rates[barIdx].time;
   const double ono = LevelAlgoOvernightOpenPrice();
   const double lot = GetTradeLotForLevelAlgo();

   bool anyEligible = false;
   bool anyOnoOk = false;
   bool anyNotBlockedByLevelFamNearLevel = false;
   bool anyNotBlockedByThisAlgoNearLevel = false;
   bool anyOrderPriceOk = false;
   bool anyMagicOk = false;

   for(int li = 0; li < scopeLevelCount; li++)
   {
      const int levelIdx = LevelPlacementBarLevelIdxForScope(scopeKind, li);
      if(!LevelAlgoLevelTagEligibleForSlot(levelIdx, slotIdx))
         continue;
      anyEligible = true;
      outEligibleCount++;

      const double levelPrice = g_levelsExpanded[levelIdx].levelPrice;
      if(la.level_needs_to_be_below_ONO && ono > 0.0 && levelPrice >= ono)
         continue;
      anyOnoOk = true;

      const bool blockedByLevelFamNearLevel = LevelAlgoBlockedNearLevelByLevelFam(levelPrice, slotIdx);
      const bool blockedByThisAlgoNearLevel = LevelAlgoBlockedNearLevelByThisAlgo(levelPrice, slotIdx);
      if(!blockedByLevelFamNearLevel)
         anyNotBlockedByLevelFamNearLevel = true;
      if(!blockedByThisAlgoNearLevel)
         anyNotBlockedByThisAlgoNearLevel = true;
      if(blockedByLevelFamNearLevel || blockedByThisAlgoNearLevel)
         continue;

      const double orderPrice = LevelAlgoComputeOrderPrice(la, levelPrice);
      if(orderPrice <= 0.0)
         continue;
      const double brokerTpPrice = NormalizeDouble(orderPrice + la.real_tp, _Digits);
      if(brokerTpPrice <= orderPrice)
         continue;
      anyOrderPriceOk = true;

      FalgoMagicKey planKey;
      if(!FalgoBuildMagicKeyForLevelAlgoPlacement(levelIdx, orderPrice, la, planKey))
         continue;
      anyMagicOk = true;

      outProximityLevel = levelPrice;
      outLevelTag = g_levelsExpanded[levelIdx].tag;
      outPlannedOrderPrice = orderPrice;
      return;
   }

   if(!anyEligible)
      LevelAlgoGatesFailFlagsAppend(outFlags, "noEligibleTagScope");
   else if(!anyOnoOk)
      LevelAlgoGatesFailFlagsAppend(outFlags, "noLevelBelowONO");
   else
   {
      if(g_levelAlgoShared.cannotTrade__when_levelFamOpenOrPendingNearLevel && !anyNotBlockedByLevelFamNearLevel)
         LevelAlgoGatesFailFlagsAppend(outFlags, "levelFamBlockedNearLevel");
      if(la.cannotTrade__when_thisAlgoOpenOrPendingNearLevel && !anyNotBlockedByThisAlgoNearLevel)
         LevelAlgoGatesFailFlagsAppend(outFlags, "thisAlgoBlockedNearLevel");
   }
   if(!anyOrderPriceOk && anyOnoOk
      && (!g_levelAlgoShared.cannotTrade__when_levelFamOpenOrPendingNearLevel || anyNotBlockedByLevelFamNearLevel)
      && (!la.cannotTrade__when_thisAlgoOpenOrPendingNearLevel || anyNotBlockedByThisAlgoNearLevel))
      LevelAlgoGatesFailFlagsAppend(outFlags, "invalidOrderOrBrokerTp");
   else if(!anyMagicOk && anyOrderPriceOk)
      LevelAlgoGatesFailFlagsAppend(outFlags, "magicKeyBuildFail");
}

//+------------------------------------------------------------------+
void LevelAlgoGatesLogInitFileHandles()
{
   for(int li = 0; li < LEVEL_ALGO_REGISTRY_MAX; li++)
   {
      g_levelAlgoGatesPmFileHandle[li] = INVALID_HANDLE;
      g_levelAlgoGatesPsFileHandle[li] = INVALID_HANDLE;
   }
   g_levelAlgoGatesLogFileDayStart = 0;
}

//+------------------------------------------------------------------+
void LevelAlgoGatesLogCloseAllFileHandles()
{
   for(int li = 0; li < LEVEL_ALGO_REGISTRY_MAX; li++)
   {
      if(g_levelAlgoGatesPmFileHandle[li] != INVALID_HANDLE)
      {
         FileClose(g_levelAlgoGatesPmFileHandle[li]);
         g_levelAlgoGatesPmFileHandle[li] = INVALID_HANDLE;
      }
      if(g_levelAlgoGatesPsFileHandle[li] != INVALID_HANDLE)
      {
         FileClose(g_levelAlgoGatesPsFileHandle[li]);
         g_levelAlgoGatesPsFileHandle[li] = INVALID_HANDLE;
      }
   }
}

//+------------------------------------------------------------------+
void LevelAlgoGatesLogEnsureDay()
{
   if(g_m1DayStart == 0)
      return;
   if(g_levelAlgoGatesLogFileDayStart == g_m1DayStart)
      return;
   LevelAlgoGatesLogCloseAllFileHandles();
   g_levelAlgoGatesLogFileDayStart = g_m1DayStart;
}

//+------------------------------------------------------------------+
void LevelAlgoGatesLogWriteHeaderIfEmpty(const int fh)
{
   if(fh == INVALID_HANDLE)
      return;
   FileSeek(fh, 0, SEEK_END);
   if(FileTell(fh) != 0)
      return;
   FileWrite(fh, "barTime", "O", "H", "L", "C", "ONO", "eligibleLevels", "inProximityLevel", "levelTag",
      "plannedOrderPrice", "firstFailGate", "2ndFailFlag", "3rdFailFlag", "failGateCount",
      "dayWins", "dayLosses", "trades_today", "openSlots", "pendingSlots");
}

//+------------------------------------------------------------------+
int LevelAlgoGatesLogAcquireHandle(const int slotIdx, const int algoNumber, const bool perSecond, const string dateStr)
{
   if(slotIdx < 0 || slotIdx >= LEVEL_ALGO_REGISTRY_MAX)
      FatalError(StringFormat("LevelAlgoGatesLogAcquireHandle: invalid slotIdx=%d algo=%d", slotIdx, algoNumber));
   LevelAlgoGatesLogEnsureDay();

   int fhRef = perSecond ? g_levelAlgoGatesPsFileHandle[slotIdx] : g_levelAlgoGatesPmFileHandle[slotIdx];
   if(fhRef != INVALID_HANDLE)
   {
      FileSeek(fhRef, 0, SEEK_END);
      return fhRef;
   }

   const string logSuffix = perSecond ? "gates_per_second" : "gates_per_minute";
   const string fname = LevelAlgoCsvFileName(dateStr, algoNumber, logSuffix);
   fhRef = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fhRef == INVALID_HANDLE)
      fhRef = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   FalgoFatalIfFileOpenFailed(fname, fhRef);

   LevelAlgoGatesLogWriteHeaderIfEmpty(fhRef);
   FileSeek(fhRef, 0, SEEK_END);
   if(perSecond)
      g_levelAlgoGatesPsFileHandle[slotIdx] = fhRef;
   else
      g_levelAlgoGatesPmFileHandle[slotIdx] = fhRef;
   return fhRef;
}

//+------------------------------------------------------------------+
void LevelAlgoAppendGatesLogRow(const int barIdx, const int algoNumber, const bool perSecond = false)
{
   if(!LevelAlgoSlotEnabled(algoNumber))
      return;
   if(!perSecond)
   {
      if(!bigflipper_log_level_algo_gates_per_minute)
         return;
   }
   else if(!bigflipper_log_level_algo_gates_per_second)
   {
      return;
   }
   if(barIdx < 0 || barIdx >= g_barsInDay || g_m1DayStart == 0)
      return;

   const int slotIdx = LevelAlgoSlotIndexByAlgoId(algoNumber);
   if(slotIdx < 0)
      return;

   const datetime rowTime = perSecond ? g_lastTimer1Time : g_m1Rates[barIdx].time;
   if(perSecond)
   {
      if(g_falgoGatesLogDayStart != g_m1DayStart)
      {
         g_falgoGatesLogDayStart = g_m1DayStart;
         LevelAlgoGatesLogEnsureDay();
         for(int li = 0; li < LEVEL_ALGO_REGISTRY_MAX; li++)
         {
            g_levelAlgoGatesLastLoggedBarTime[li] = 0;
            g_levelAlgoGatesPerSecondLastLoggedTime[li] = 0;
         }
      }
      if(rowTime == g_levelAlgoGatesPerSecondLastLoggedTime[slotIdx])
         return;
      g_levelAlgoGatesPerSecondLastLoggedTime[slotIdx] = rowTime;
   }

   const datetime evalTime = perSecond ? g_lastTimer1Time : (rowTime + 60);
   int eligibleCount = 0;
   double proximityLevel = 0.0;
   double plannedOrderPrice = 0.0;
   string levelTag = "";
   string failFlags[];
   LevelAlgoCollectPlacementFailFlags(slotIdx, barIdx, evalTime, failFlags, eligibleCount,
      proximityLevel, levelTag, plannedOrderPrice);

   const string firstFail = (ArraySize(failFlags) > 0 ? failFlags[0] : "");
   const string secondFail = (ArraySize(failFlags) > 1 ? failFlags[1] : "");
   const string thirdFail = (ArraySize(failFlags) > 2 ? failFlags[2] : "");
   const int failGateCount = (firstFail != "" ? ArraySize(failFlags) : 0);

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

   const double ono = LevelAlgoOvernightOpenPrice();
   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   const int fh = LevelAlgoGatesLogAcquireHandle(slotIdx, algoNumber, perSecond, dateStr);
   if(fh == INVALID_HANDLE)
      FatalError(StringFormat("LevelAlgoAppendGatesLogRow: could not open gates log algo=%d perSecond=%s",
         algoNumber, (perSecond ? "true" : "false")));
   const int timeFormat = perSecond ? (TIME_DATE | TIME_SECONDS) : (TIME_DATE | TIME_MINUTES);
   FileWrite(fh,
      TimeToString(rowTime, timeFormat),
      DoubleToString(rowO, _Digits),
      DoubleToString(rowH, _Digits),
      DoubleToString(rowL, _Digits),
      DoubleToString(rowC, _Digits),
      (ono > 0.0 ? DoubleToString(ono, _Digits) : ""),
      IntegerToString(eligibleCount),
      (proximityLevel > 0.0 ? DoubleToString(proximityLevel, _Digits) : ""),
      levelTag,
      (plannedOrderPrice > 0.0 ? DoubleToString(plannedOrderPrice, _Digits) : ""),
      firstFail, secondFail, thirdFail,
      IntegerToString(failGateCount),
      IntegerToString(g_levelAlgoDayWins[slotIdx]),
      IntegerToString(g_levelAlgoDayLosses[slotIdx]),
      IntegerToString(g_levelAlgoDayTradesToday[slotIdx]),
      IntegerToString(LevelCachedOpenPositionsOnSymbolForAlgo(algoNumber)),
      IntegerToString(LevelCachedPendingOrdersOnSymbolForAlgo(algoNumber)));
}

//+------------------------------------------------------------------+
void LevelAlgoTryLogGatesForClosedMinute()
{
   if(!bigflipper_log_level_algo_gates_per_minute)
      return;
   if(g_barsInDay < 2 || g_m1DayStart == 0)
      return;
   if(g_falgoGatesLogDayStart != g_m1DayStart)
   {
      g_falgoGatesLogDayStart = g_m1DayStart;
      LevelAlgoGatesLogEnsureDay();
      for(int li = 0; li < LEVEL_ALGO_REGISTRY_MAX; li++)
         g_levelAlgoGatesLastLoggedBarTime[li] = 0;
   }

   const int barIdx = g_barsInDay - 2;
   const datetime barTime = g_m1Rates[barIdx].time;
   EnsureOccupiedMagicsCacheInitialized();
   LevelNearLevelPlacementCacheBuild();
   LevelPlacementBuildBarLevelCandidates(barIdx);
   for(int si = 0; si < g_levelAlgoCount; si++)
   {
      const int algoNumber = g_levelAlgos[si].algo_id;
      if(!LevelAlgoSlotEnabled(algoNumber))
         continue;
      if(barTime == g_levelAlgoGatesLastLoggedBarTime[si])
         continue;
      g_levelAlgoGatesLastLoggedBarTime[si] = barTime;
      LevelAlgoAppendGatesLogRow(barIdx, algoNumber);
   }
}

//+------------------------------------------------------------------+
void LevelAlgoTryLogGatesPerSecond()
{
   if(!bigflipper_log_level_algo_gates_per_second)
      return;
   if(g_barsInDay <= 0 || g_m1DayStart == 0)
      return;
   if(!FalgoIsTimeInPerSecondLogWindow(g_lastTimer1Time))
      return;

   const int placementBarIdx = g_barsInDay - 1;
   EnsureOccupiedMagicsCacheInitialized();
   LevelNearLevelPlacementCacheBuild();
   LevelPlacementBuildBarLevelCandidates(placementBarIdx);
   for(int si = 0; si < g_levelAlgoCount; si++)
   {
      const int algoNumber = g_levelAlgos[si].algo_id;
      if(!LevelAlgoSlotEnabled(algoNumber))
         continue;
      LevelAlgoAppendGatesLogRow(placementBarIdx, algoNumber, true);
   }
}

//+------------------------------------------------------------------+
void LevelAlgoAllDaysAlgoConfigForMagic(const long magic, int &outEntryHour, int &outEntryMinute,
   double &outSecretTpProfitPctMin, double &outSecretTpGreenguardPricediff)
{
   outEntryHour = 0;
   outEntryMinute = 0;
   outSecretTpProfitPctMin = 0.0;
   outSecretTpGreenguardPricediff = 0.0;
   LevelAlgoDef la;
   if(!LevelAlgoDefForNumber(AlgoFamilyMagicNumber(magic), la))
      return;
   outSecretTpProfitPctMin = la.secret_tp_profit_percent_min;
   outSecretTpGreenguardPricediff = la.secret_tp_greenguard_pricediff_at_least;
}

#endif
