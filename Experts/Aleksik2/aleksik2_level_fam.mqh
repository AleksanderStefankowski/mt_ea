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
   if(g_levelAlgoShared.use_banned_days && FalgoIsNonTradeCalendarDate(t))
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
   const double lot, const LevelAlgoDef &la, FalgoMagicKey &outKey)
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
      if(entryPrice <= 0.0 || lot <= 0.0)
         return false;
      const double secretTpPrice = FalgoSecretTpPriceForProfitPctMin(entryPrice, lot, la.secret_tp_profit_percent_min);
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
   const datetime dayStart = FalgoDayStartForCounterRebuild();
   if(dayStart != 0 && g_levelAlgoDayTradeCountsDayStartMarker != dayStart)
   {
      g_levelAlgoDayTradeCountsDayStartMarker = dayStart;
      for(int si = 0; si < LEVEL_ALGO_REGISTRY_MAX; si++)
      {
         g_levelAlgoDayTradesToday[si] = 0;
         g_levelAlgoDayWins[si] = 0;
         g_levelAlgoDayLosses[si] = 0;
      }
   }
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
      const double brokerTpPrice = NormalizeDouble(orderPrice + g_levelAlgos[slotIdx].real_tp, _Digits);
      if(brokerTpPrice <= orderPrice)
         continue;

      ulong profOrdT0 = 0;
      if(profOn)
         profOrdT0 = GetMicrosecondCount();

      FalgoMagicKey planKey;
      if(!FalgoBuildMagicKeyForLevelAlgoPlacement(levelIdx, orderPrice, lot, g_levelAlgos[slotIdx], planKey))
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

   const double profitPts = FalgoOpenPositionProfitPoints();
   const double accountProfit = FalgoSelectedPositionAccountProfit();
   ExtTrade.SetExpertMagicNumber((ulong)posMagic);
   const bool closed = ExtTrade.PositionClose(posTicket);
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   if(closed)
      FalgoAfterFamilyPositionClosed(posMagic, profitPts, accountProfit);
   return closed;
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
   g_levelAlgoShared.use_banned_days = false;
   g_levelAlgoShared.babysit_enabled = true;
   g_levelAlgoShared.blockPlacementIfFamilyOpenOrPending = false;
   g_levelAlgoShared.cannotTrade__when_levelFamOpenOrPendingNearLevel = false;
   g_levelAlgoShared.stop_trading_if_day_has_X_wins_0_losses = 9999;
   g_levelAlgoShared.stop_trading_if_day_has_profit_factor_above = 9999;
   g_levelAlgoShared.stop_trading_today_if_AllAlgos_losing_trades_count = 999;
   g_levelAlgoShared.stop_trading_today_if_AllAlgos_winning_trades_count = 999;
   g_levelAlgoShared.tradeSizePct = 100;
   g_levelAlgoShared.bannedRanges = "0,0,1,0"; // "21,35,23,59;0,0,1,0";
   g_levelAlgoShared.tradesDays = "12345";
   g_levelAlgoShared.price_proximity_above_level = 25.0;

//levelalgocreator2start
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000014)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000015)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000016)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000017)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000018)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000019)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000020)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000021)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000022)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000023)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000024)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000025)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000026)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000027)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000028)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000029)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000030)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000031)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000032)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000033)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000034)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000035)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000036)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000037)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000038)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000039)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000040)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000041)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000042)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000043)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000044)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000045)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000046)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000047)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000048)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000049)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000050)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000051)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000052)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000053)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000054)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000055)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000056)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000057)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000058)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000059)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000060)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000061)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000062)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000063)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000064)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000065)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000066)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000067)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000068)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000069)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000070)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000071)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000072)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000073)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000074)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000075)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000076)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000077)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000078)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000079)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000080)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000081)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000082)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000083)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000084)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000085)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000086)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000087)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000088)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000089)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000090)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000091)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000092)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000093)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000094)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000095)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000096)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000097)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000098)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000099)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000100)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000101)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000102)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000103)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000104)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000105)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000106)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000107)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000108)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000109)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000110)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000111)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000112)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000113)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000114)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000115)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000116)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000117)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000118)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000119)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000120)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000121)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000122)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000123)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000124)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000125)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000126)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000127)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000128)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000129)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000130)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000131)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000132)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000133)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000134)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000135)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000136)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000137)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000138)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000139)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000140)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000141)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000142)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000143)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000144)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000145)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000146)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000147)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000148)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000149)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].secret_tp_profit_percent_min = 8.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000150)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000151)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000152)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000153)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000154)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000155)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000156)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000157)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000158)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000159)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000160)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000161)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000162)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000163)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000164)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000165)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000166)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000167)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000168)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000169)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000170)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000171)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000172)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000173)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000174)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].secret_tp_profit_percent_min = 10.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000175)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000176)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000177)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000178)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000179)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000180)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000181)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000182)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000183)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000184)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000185)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000186)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000187)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000188)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000189)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000190)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000191)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000192)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000193)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000194)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000195)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000196)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000197)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000198)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000199)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].secret_tp_profit_percent_min = 12.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000200)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000201)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000202)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000203)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000204)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000205)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000206)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000207)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000208)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000209)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000210)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000211)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000212)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000213)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000214)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000215)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000216)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000217)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000218)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000219)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000220)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000221)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000222)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000223)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000224)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].secret_tp_profit_percent_min = 14.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000225)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000226)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000227)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000228)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000229)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].offset_percentage = 0.0002;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000230)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000231)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000232)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000233)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000234)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].offset_percentage = 0.0005;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000235)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000236)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000237)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000238)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000239)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].offset_percentage = 0.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000240)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000241)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000242)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000243)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000244)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].offset_percentage = 8.0000;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000245)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].cannotTrade__when_levelProximity_multiplyOffset = 1.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000246)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].cannotTrade__when_levelProximity_multiplyOffset = 1.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000247)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].cannotTrade__when_levelProximity_multiplyOffset = 0.5;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000248)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].cannotTrade__when_levelProximity_multiplyOffset = 0.3;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000249)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].enabled = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].trades_weekly = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].trades_daily = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 6;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].secret_tp_profit_percent_min = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].cannotTrade__when_levelProximity_multiplyOffset = 0.2;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].trades_tags, 5);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000250)].rule_switch_map = 0;
//levelalgocreator2end
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
      if(!FalgoBuildMagicKeyForLevelAlgoPlacement(levelIdx, orderPrice, lot, la, planKey))
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
