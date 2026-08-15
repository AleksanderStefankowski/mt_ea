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
   FalgoFlipperPrintfManualCloseDecision(bigflipper_log_level_algo_manual_close_decision,
      "level", "secretTP", posMagic, posTicket, positionId, closeDetail);

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
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000001)].secret_tp_profit_percent_min = 0.50;
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
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].secret_tp_profit_percent_min = 0.50;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000002)].trades_tags[5] = "Pivot";
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
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].secret_tp_profit_percent_min = 0.50;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000003)].offset_percentage = 0.0020;
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
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].secret_tp_profit_percent_min = 0.50;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000004)].trades_tags[5] = "Pivot";
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
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].secret_tp_profit_percent_min = 0.50;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000005)].offset_percentage = 0.0006;
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
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].secret_tp_profit_percent_min = 0.50;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].offset_percentage = 0.0020;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000006)].trades_tags[5] = "Pivot";
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
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000007)].offset_positive = true;
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
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].offset_percentage = 0.0006;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000008)].trades_tags[5] = "Pivot";
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
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].offset_positive = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000009)].offset_percentage = 0.0020;
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
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].offset_percentage = 0.0003;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].cannotTrade__when_levelProximity_multiplyOffset = 1.20;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000010)].trades_tags[5] = "Pivot";
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
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000011)].offset_percentage = 0.0006;
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
ArrayResize(g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags, 6);
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[0] = "Down1";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[1] = "Down2";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[2] = "Down3";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[3] = "Down4";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[4] = "Down5";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].trades_tags[5] = "Pivot";
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].real_tp = 555.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000012)].rule_switch_map = 0;

g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].enabled = true; // catalog L211
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_weekly = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].trades_daily = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].expiry_minutes = 120;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].this_algo_max_concurrent_pending_trades = 1;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].max_open_positions = 10;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].secret_tp_profit_percent_min = 8.00;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].secret_tp_greenguard_pricediff_at_least = 20.0;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].level_needs_to_be_below_ONO = true;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].offset_positive = false;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].offset_percentage = 0.0010;
g_levelAlgos[LevelAlgoSlotIndexByAlgoId(MAGIC_LEVEL30000013)].cannotTrade__when_levelProximity_multiplyOffset = 2.00;
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
