//+------------------------------------------------------------------+
//| smashelito_falgo5.mqh — algo5 (falgo5) profile, magic, ruleset, pipeline |
//| Included from smashelito.mq5 after globals (g_tradeResults, g_m1Rates, …). |
//+------------------------------------------------------------------+
#ifndef SMASHELITO_FALGO5_MQH
#define SMASHELITO_FALGO5_MQH

//--- falgo5 magic layout (17 decimal digits; index 0 = digit 1)
#define FALGO5_MAGIC_INDEX_SLOT1           0   // 5
#define FALGO5_MAGIC_LENGTH_SLOT1          1
#define FALGO5_MAGIC_INDEX_DIRECTION       1   // 1|2|3|4 long/short variants
#define FALGO5_MAGIC_LENGTH_DIRECTION      1
#define FALGO5_MAGIC_INDEX_DAY_OF_WEEK     2   // 1..5 Mon..Fri
#define FALGO5_MAGIC_LENGTH_DAY_OF_WEEK    1
#define FALGO5_MAGIC_INDEX_LEVEL_TIER      3   // 1..9 weekly tier
#define FALGO5_MAGIC_LENGTH_LEVEL_TIER     1
#define FALGO5_MAGIC_INDEX_BOUNCE          4   // 0..8 capped
#define FALGO5_MAGIC_LENGTH_BOUNCE         1
#define FALGO5_MAGIC_INDEX_CEILING         5   // 0..8 capped
#define FALGO5_MAGIC_LENGTH_CEILING        1
#define FALGO5_MAGIC_INDEX_OFFSET          6   // %02d tenths (long or short offset for this plan)
#define FALGO5_MAGIC_LENGTH_OFFSET         2
#define FALGO5_MAGIC_INDEX_PLAN_TRADE_NUM  8   // 0..8
#define FALGO5_MAGIC_LENGTH_PLAN_TRADE_NUM 1
#define FALGO5_MAGIC_INDEX_LEVEL_TRADE_NUM 9   // 0..8
#define FALGO5_MAGIC_LENGTH_LEVEL_TRADE_NUM 1
#define FALGO5_MAGIC_INDEX_BABYSIT_MIN     10  // 0..9
#define FALGO5_MAGIC_LENGTH_BABYSIT_MIN    1
#define FALGO5_MAGIC_INDEX_SUBSET_A        11  // reserved
#define FALGO5_MAGIC_LENGTH_SUBSET_A       1
#define FALGO5_MAGIC_INDEX_SUBSET_B        12  // reserved
#define FALGO5_MAGIC_LENGTH_SUBSET_B       1
#define FALGO5_MAGIC_INDEX_TP              13  // %02d whole points
#define FALGO5_MAGIC_LENGTH_TP             2
#define FALGO5_MAGIC_INDEX_SL              15  // %02d whole points
#define FALGO5_MAGIC_LENGTH_SL             2

#define FALGO5_DIRECTION_LONG_LIMIT        1
#define FALGO5_DIRECTION_SHORT_LIMIT       2
#define FALGO5_DIRECTION_LONG_ALT          3
#define FALGO5_DIRECTION_SHORT_ALT         4

#define FALGO5_BANNED_RANGES_MAX           8
#define FALGO5_LEVEL_TIER_MAX              9
BannedRangeMinutes g_falgo5BannedRanges[FALGO5_BANNED_RANGES_MAX];
int g_falgo5BannedRangeCount = 0;
datetime g_falgo5PlanCountersDayStart = 0;
int g_falgo5PlanTradeNumToday = 0;           // falgo5 fills today (IN deals); next magic plan # = count+1; expired pendings do not count
int g_falgo5LevelTradeNumByTier[FALGO5_LEVEL_TIER_MAX + 1];  // fills today per weekly tier (from magic)
datetime g_falgo5GatesLastLoggedBarTime = 0;
datetime g_falgo5GatesLogDayStart = 0;
bool g_falgo5OrderPlacedLastPipeline = false;

bool PlacePendingFromFalgo5Magic(long magic, double anchorLevel, double offsetPoints, double slPoints, double tpPoints, int expirationMin, double lot);
void WriteTradeLogPendingOrderFalgo5(double levelPrice, double offsetPoints, double slPoints, double tpPoints, long magic, int expirationMin);

struct Falgo5MagicKey
{
   int direction;       // 1..4
   int dayOfWeek;       // 1..5 Mon..Fri
   int levelTier;       // 1..9
   int bounceCount;     // 0..8
   int ceilingCount;    // 0..8
   int offset_tenths;   // encoded 0.1..9.9 (long or short offset for this order)
   int planTradeNum;    // 0..8
   int levelTradeNum;   // 0..8
   int babysitMinute;   // 0..9
   int subsetA;         // reserved
   int subsetB;
   int tpWhole;         // 1..99
   int slWhole;
};

//+------------------------------------------------------------------+
int Falgo5Clamp0_8(const int v) { return (v < 0) ? 0 : ((v > 8) ? 8 : v); }
int Falgo5Clamp0_9(const int v) { return (v < 0) ? 0 : ((v > 9) ? 9 : v); }

//+------------------------------------------------------------------+
bool IsFalgo5CompositeMagicSlot1(const long magic)
{
   string s = IntegerToString(magic);
   if(StringLen(s) < 1) return false;
   if(StringLen(s) >= COMPOSITE_MAGIC_STRING_LEN)
      s = MagicNumberToFixedWidthString(magic);
   int slot1 = (int)StringToInteger(StringSubstr(s, 0, 1));
   return (slot1 == MAGIC_ALGO5_SLOT1);
}

//+------------------------------------------------------------------+
bool IsAlgo5CompositeMagicSlot1(const long magic) { return IsFalgo5CompositeMagicSlot1(magic); }

//+------------------------------------------------------------------+
int Falgo5CapWholeTpSlForMagic(const double points)
{
   int w = (int)MathRound(points);
   if(w < 1) w = 1;
   if(w > 99) w = 99;
   return w;
}

//+------------------------------------------------------------------+
long BuildFalgo5MagicNumber(const Falgo5MagicKey &k)
{
   string s = StringFormat("%d%d%d%d%d%d%02d%d%d%d%d%d%02d%02d",
      MAGIC_ALGO5_SLOT1,
      k.direction,
      k.dayOfWeek,
      k.levelTier,
      Falgo5Clamp0_8(k.bounceCount),
      Falgo5Clamp0_8(k.ceilingCount),
      k.offset_tenths,
      Falgo5Clamp0_8(k.planTradeNum),
      Falgo5Clamp0_8(k.levelTradeNum),
      Falgo5Clamp0_9(k.babysitMinute),
      k.subsetA,
      k.subsetB,
      k.tpWhole,
      k.slWhole);
   if(StringLen(s) != COMPOSITE_MAGIC_STRING_LEN)
      FatalError(StringFormat("BuildFalgo5MagicNumber: len %d != %d", StringLen(s), COMPOSITE_MAGIC_STRING_LEN));
   return (long)StringToInteger(s);
}

//+------------------------------------------------------------------+
Falgo5MagicKey ParseFalgo5Magic(const long magic)
{
   Falgo5MagicKey emptyKey;
   emptyKey.direction = 0;
   emptyKey.dayOfWeek = 0;
   emptyKey.levelTier = 0;
   emptyKey.bounceCount = 0;
   emptyKey.ceilingCount = 0;
   emptyKey.offset_tenths = 0;
   emptyKey.planTradeNum = 0;
   emptyKey.levelTradeNum = 0;
   emptyKey.babysitMinute = 0;
   emptyKey.subsetA = 0;
   emptyKey.subsetB = 0;
   emptyKey.tpWhole = 0;
   emptyKey.slWhole = 0;
   if(!IsFalgo5CompositeMagicSlot1(magic))
      return emptyKey;
   string s = MagicNumberToFixedWidthString(magic);
   Falgo5MagicKey k;
   k.direction = (int)StringToInteger(StringSubstr(s, FALGO5_MAGIC_INDEX_DIRECTION, FALGO5_MAGIC_LENGTH_DIRECTION));
   k.dayOfWeek = (int)StringToInteger(StringSubstr(s, FALGO5_MAGIC_INDEX_DAY_OF_WEEK, FALGO5_MAGIC_LENGTH_DAY_OF_WEEK));
   k.levelTier = (int)StringToInteger(StringSubstr(s, FALGO5_MAGIC_INDEX_LEVEL_TIER, FALGO5_MAGIC_LENGTH_LEVEL_TIER));
   k.bounceCount = (int)StringToInteger(StringSubstr(s, FALGO5_MAGIC_INDEX_BOUNCE, FALGO5_MAGIC_LENGTH_BOUNCE));
   k.ceilingCount = (int)StringToInteger(StringSubstr(s, FALGO5_MAGIC_INDEX_CEILING, FALGO5_MAGIC_LENGTH_CEILING));
   k.offset_tenths = (int)StringToInteger(StringSubstr(s, FALGO5_MAGIC_INDEX_OFFSET, FALGO5_MAGIC_LENGTH_OFFSET));
   k.planTradeNum = (int)StringToInteger(StringSubstr(s, FALGO5_MAGIC_INDEX_PLAN_TRADE_NUM, FALGO5_MAGIC_LENGTH_PLAN_TRADE_NUM));
   k.levelTradeNum = (int)StringToInteger(StringSubstr(s, FALGO5_MAGIC_INDEX_LEVEL_TRADE_NUM, FALGO5_MAGIC_LENGTH_LEVEL_TRADE_NUM));
   k.babysitMinute = (int)StringToInteger(StringSubstr(s, FALGO5_MAGIC_INDEX_BABYSIT_MIN, FALGO5_MAGIC_LENGTH_BABYSIT_MIN));
   k.subsetA = (int)StringToInteger(StringSubstr(s, FALGO5_MAGIC_INDEX_SUBSET_A, FALGO5_MAGIC_LENGTH_SUBSET_A));
   k.subsetB = (int)StringToInteger(StringSubstr(s, FALGO5_MAGIC_INDEX_SUBSET_B, FALGO5_MAGIC_LENGTH_SUBSET_B));
   k.tpWhole = (int)StringToInteger(StringSubstr(s, FALGO5_MAGIC_INDEX_TP, FALGO5_MAGIC_LENGTH_TP));
   k.slWhole = (int)StringToInteger(StringSubstr(s, FALGO5_MAGIC_INDEX_SL, FALGO5_MAGIC_LENGTH_SL));
   return k;
}

//+------------------------------------------------------------------+
void RebuildFalgo5BannedRangesCache()
{
   g_falgo5BannedRangeCount = 0;
   ParseBannedRanges(g_falgo5Profile.bannedRanges);
   // Use g_bannedRangesCount (rows), not ArraySize — on 2D arrays ArraySize is total elements (rows×4).
   for(int i = 0; i < g_bannedRangesCount && i < FALGO5_BANNED_RANGES_MAX; i++)
   {
      g_falgo5BannedRanges[i].startMin = g_bannedRangesBuffer[i][0] * 60 + g_bannedRangesBuffer[i][1];
      g_falgo5BannedRanges[i].endMin   = g_bannedRangesBuffer[i][2] * 60 + g_bannedRangesBuffer[i][3];
      g_falgo5BannedRangeCount++;
   }
}

//+------------------------------------------------------------------+
bool Falgo5IsTradingTimeAllowed(const datetime t)
{
   MqlDateTime mt;
   TimeToStruct(t, mt);
   int curMin = mt.hour * 60 + mt.min;
   for(int i = 0; i < g_falgo5BannedRangeCount; i++)
   {
      int sm = g_falgo5BannedRanges[i].startMin;
      int em = g_falgo5BannedRanges[i].endMin;
      if(curMin >= sm && curMin <= em)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| MT5 day_of_week 1=Mon..5=Fri (magic slot 2). Weekend → -1 (calendar gate only). |
//+------------------------------------------------------------------+
int Falgo5DayOfWeekSlotFromTimeOrInvalid(const datetime t)
{
   MqlDateTime mt;
   TimeToStruct(t, mt);
   int dow = mt.day_of_week;
   if(dow >= 1 && dow <= 5)
      return dow;
   return -1;
}

//+------------------------------------------------------------------+
//| Same as OrInvalid but FatalError if not Mon..Fri (encode in magic). |
//+------------------------------------------------------------------+
int Falgo5DayOfWeekSlotFromTime(const datetime t)
{
   int slot = Falgo5DayOfWeekSlotFromTimeOrInvalid(t);
   if(slot < 1)
      FatalError(StringFormat("Falgo5DayOfWeekSlotFromTime: invalid day_of_week slot (expected 1..5 Mon..Fri) at %s",
         TimeToString(t, TIME_DATE|TIME_MINUTES)));
   return slot;
}

//+------------------------------------------------------------------+
bool Falgo5LevelShouldTrackForDayStats(const string &categories)
{
   if(LevelIsWeekly(categories))
      return true;
   string c = categories;
   StringToLower(c);
   return (StringFind(c, "daily") >= 0);
}

//+------------------------------------------------------------------+
bool Falgo5LevelEligibleForClosestAnchor(const int expandedLevelIdx)
{
   if(expandedLevelIdx < 0 || expandedLevelIdx >= g_levelsTodayCount)
      return false;
   if(g_falgo5Profile.tradesDailyLevels)
      return true;
   return LevelIsWeekly(g_levelsExpanded[expandedLevelIdx].categories);
}

//+------------------------------------------------------------------+
void Falgo5ResetPlanCountersIfNewDay(const datetime dayStart)
{
   if(g_falgo5PlanCountersDayStart == dayStart)
      return;
   g_falgo5PlanCountersDayStart = dayStart;
   g_falgo5PlanTradeNumToday = 0;
   for(int tier = 0; tier <= FALGO5_LEVEL_TIER_MAX; tier++)
      g_falgo5LevelTradeNumByTier[tier] = 0;
}

//+------------------------------------------------------------------+
bool Falgo5IsTradingDayAllowed(const datetime t)
{
   int slot = Falgo5DayOfWeekSlotFromTimeOrInvalid(t);
   if(slot < 1)
      return false;
   string days = g_falgo5Profile.tradesDays;
   if(StringLen(days) < 1)
      return true;
   return (StringFind(days, IntegerToString(slot)) >= 0);
}

//+------------------------------------------------------------------+
string Falgo5BoolCsv(const bool v) { return v ? "true" : "false"; }

//+------------------------------------------------------------------+
bool Falgo5IsTradingDayAllowedAtTime(const datetime t)
{
   return Falgo5IsTradingDayAllowed(t);
}

//+------------------------------------------------------------------+
bool Falgo5ProfileAllowsNewOrdersAtTime(const datetime t)
{
   if(!g_falgo5Profile.enabled)
      return false;
   if(!Falgo5IsTradingDayAllowedAtTime(t))
      return false;
   if(!Falgo5IsTradingTimeAllowed(t))
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Closed legacy (non-falgo5) trades before bar close — for legacy summary CSVs only. |
//+------------------------------------------------------------------+
void Falgo5LegacyDayTotalsBeforeBarClose(const datetime candleCloseTime,
   int &outCount, int &outWins, double &outPointsSum, double &outProfitSum)
{
   outCount = 0;
   outWins = 0;
   outPointsSum = 0.0;
   outProfitSum = 0.0;
   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      if(!g_tradeResults[i].foundOut)
         continue;
      if(IsFalgo5CompositeMagicSlot1(g_tradeResults[i].magic))
         continue;
      if(g_tradeResults[i].endTime >= candleCloseTime)
         continue;
      outCount++;
      if(g_tradeResults[i].profit > 0.0)
         outWins++;
      outPointsSum += g_tradeResults[i].priceDiff;
      outProfitSum += g_tradeResults[i].profit;
   }
}

//+------------------------------------------------------------------+
//| Plan/level trade nums from today's filled falgo5 deals only (not pending place/expire). |
//+------------------------------------------------------------------+
void SyncFalgo5PlanCountersFromTradeResults()
{
   g_falgo5PlanTradeNumToday = 0;
   for(int tier = 0; tier <= FALGO5_LEVEL_TIER_MAX; tier++)
      g_falgo5LevelTradeNumByTier[tier] = 0;
   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      if(!IsFalgo5CompositeMagicSlot1(g_tradeResults[i].magic))
         continue;
      g_falgo5PlanTradeNumToday++;
      Falgo5MagicKey fk = ParseFalgo5Magic(g_tradeResults[i].magic);
      if(fk.levelTier >= 1 && fk.levelTier <= FALGO5_LEVEL_TIER_MAX)
         g_falgo5LevelTradeNumByTier[fk.levelTier]++;
   }
}

//+------------------------------------------------------------------+
void UpdateFalgo5DayTradeCounts()
{
   SyncFalgo5PlanCountersFromTradeResults();
   g_falgo5DayWins = 0;
   g_falgo5DayLosses = 0;
   g_falgo5DayClosedCount = 0;
   for(int i = 0; i < g_tradeResultsCount; i++)
   {
      if(!g_tradeResults[i].foundOut)
         continue;
      if(!IsFalgo5CompositeMagicSlot1(g_tradeResults[i].magic))
         continue;
      g_falgo5DayClosedCount++;
      if(g_tradeResults[i].profit > 0.0)
         g_falgo5DayWins++;
      else if(g_tradeResults[i].profit < 0.0)
         g_falgo5DayLosses++;
   }
}

//+------------------------------------------------------------------+
bool Falgo5HasOpenPositionOnSymbol()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!ExtPositionInfo.SelectByIndex(i)) continue;
      if(ExtPositionInfo.Symbol() != _Symbol) continue;
      if(IsFalgo5CompositeMagicSlot1(ExtPositionInfo.Magic()))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool Falgo5HasPendingOrderOnSymbol()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ExtOrderInfo.SelectByIndex(i)) continue;
      if(ExtOrderInfo.Symbol() != _Symbol) continue;
      if(IsFalgo5CompositeMagicSlot1(ExtOrderInfo.Magic()))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int Falgo5GetBounceCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgo5AtBar[barIdx].closestWeeklyLevel_BounceCount_today;
}

//+------------------------------------------------------------------+
int Falgo5GetCeilingCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgo5AtBar[barIdx].closestWeeklyLevel_CeilingCount_today;
}

//+------------------------------------------------------------------+
int Falgo5GetRecentBounceCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgo5AtBar[barIdx].closestWeeklyLevel_BounceCount_recent;
}

//+------------------------------------------------------------------+
int Falgo5GetRecentCeilingCountForClosestWeeklyLevel(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay) return 0;
   return g_pullingHistoryAlgo5AtBar[barIdx].closestWeeklyLevel_CeilingCount_recent;
}

//+------------------------------------------------------------------+
//| Placement gate: recent window when recent*Bounce*Minutes > 0, else full day. |
//+------------------------------------------------------------------+
int Falgo5GetBounceCountForGate(const int barIdx)
{
   if(g_falgo5Profile.recentBounceCountToday_Minutes > 0)
      return Falgo5GetRecentBounceCountForClosestWeeklyLevel(barIdx);
   return Falgo5GetBounceCountForClosestWeeklyLevel(barIdx);
}

//+------------------------------------------------------------------+
int Falgo5GetCeilingCountForGate(const int barIdx)
{
   if(g_falgo5Profile.recentCeilingCountToday_Minutes > 0)
      return Falgo5GetRecentCeilingCountForClosestWeeklyLevel(barIdx);
   return Falgo5GetCeilingCountForClosestWeeklyLevel(barIdx);
}

//+------------------------------------------------------------------+
string Falgo5GatesColRecentBounceCount()
{
   if(g_falgo5Profile.recentBounceCountToday_Minutes <= 0)
      return "recentBounceCount0";
   return StringFormat("recentBounceCount%d", g_falgo5Profile.recentBounceCountToday_Minutes);
}

//+------------------------------------------------------------------+
string Falgo5GatesColRecentCeilingCount()
{
   if(g_falgo5Profile.recentCeilingCountToday_Minutes <= 0)
      return "recentCeilingCount0";
   return StringFormat("recentCeilingCount%d", g_falgo5Profile.recentCeilingCountToday_Minutes);
}

//+------------------------------------------------------------------+
//| Weekly tier 1..9 from tag (smash=5 center; up/down ladders). FatalError if unmapped. |
//+------------------------------------------------------------------+
int Falgo5LevelTierFromLevelIdx(const int levelIdx)
{
   if(levelIdx < 0 || levelIdx >= g_levelsTodayCount)
      FatalError(StringFormat("Falgo5LevelTierFromLevelIdx: invalid levelIdx=%d (g_levelsTodayCount=%d)", levelIdx, g_levelsTodayCount));
   string t = g_levelsExpanded[levelIdx].tag;
   string tLower = t;
   StringToLower(tLower);
   if(StringFind(tLower, "weekly") < 0)
      FatalError(StringFormat("Falgo5LevelTierFromLevelIdx: levelIdx=%d tag \"%s\" categories \"%s\" is not weekly — cannot map tier 1..9",
         levelIdx, t, g_levelsExpanded[levelIdx].categories));
   if(StringFind(tLower, "smash") >= 0)
      return 5;
   if(StringFind(tLower, "weeklydown4") >= 0 || StringFind(tLower, "weekly_down4") >= 0)
      return 1;
   if(StringFind(tLower, "weeklydown3") >= 0 || StringFind(tLower, "weekly_down3") >= 0)
      return 2;
   if(StringFind(tLower, "weeklydown2") >= 0 || StringFind(tLower, "weekly_down2") >= 0)
      return 3;
   if(StringFind(tLower, "weeklydown1") >= 0 || StringFind(tLower, "weekly_down1") >= 0)
      return 4;
   if(StringFind(tLower, "weeklydown") >= 0)
      FatalError(StringFormat("Falgo5LevelTierFromLevelIdx: levelIdx=%d tag \"%s\" — weeklydown without down1..down4 tier", levelIdx, t));
   if(StringFind(tLower, "weeklyup1") >= 0 || StringFind(tLower, "weekly_up1") >= 0)
      return 6;
   if(StringFind(tLower, "weeklyup2") >= 0 || StringFind(tLower, "weekly_up2") >= 0)
      return 7;
   if(StringFind(tLower, "weeklyup3") >= 0 || StringFind(tLower, "weekly_up3") >= 0)
      return 8;
   if(StringFind(tLower, "weeklyup") >= 0)
      return 9;
   FatalError(StringFormat("Falgo5LevelTierFromLevelIdx: levelIdx=%d tag \"%s\" categories \"%s\" — weekly tag not mapped to tier 1..9",
      levelIdx, t, g_levelsExpanded[levelIdx].categories));
   return 0;
}

//+------------------------------------------------------------------+
//| Today's weekly level price for magic levelTier (1..9); must match g_levelsExpanded. |
//+------------------------------------------------------------------+
double Falgo5WeeklyLevelPriceForTier(const int tier)
{
   for(int levelIdx = 0; levelIdx < g_levelsTodayCount; levelIdx++)
   {
      if(!LevelIsWeekly(g_levelsExpanded[levelIdx].categories))
         continue;
      if(Falgo5LevelTierFromLevelIdx(levelIdx) != tier)
         continue;
      return g_levelsExpanded[levelIdx].levelPrice;
   }
   FatalError(StringFormat("Falgo5WeeklyLevelPriceForTier: no weekly level in g_levelsExpanded for tier %d (g_levelsTodayCount=%d)",
      tier, g_levelsTodayCount));
   return 0.0;
}

//+------------------------------------------------------------------+
//| tpWhole/slWhole from magic; if secretTPSL on, scale by secretTPSL_percent (babysit-effective points). |
//+------------------------------------------------------------------+
void Falgo5EffectiveTpSlPointsFromMagicKey(const Falgo5MagicKey &k, double &outTpPoints, double &outSlPoints)
{
   outTpPoints = (double)k.tpWhole;
   outSlPoints = (double)k.slWhole;
   if(g_falgo5Profile.secretTPSL && g_falgo5Profile.secretTPSL_percent > 0)
   {
      const double frac = (double)g_falgo5Profile.secretTPSL_percent / 100.0;
      outTpPoints *= frac;
      outSlPoints *= frac;
   }
}

//+------------------------------------------------------------------+
void Falgo5EnrichTradeResultLevelTpSl(TradeResult &tr)
{
   if(!IsFalgo5CompositeMagicSlot1(tr.magic))
      return;
   Falgo5MagicKey fk = ParseFalgo5Magic(tr.magic);
   if(fk.levelTier < 1 || fk.levelTier > FALGO5_LEVEL_TIER_MAX)
      FatalError(StringFormat("Falgo5EnrichTradeResultLevelTpSl: magic %s has invalid levelTier %d",
         IntegerToString(tr.magic), fk.levelTier));
   const double levelPrice = Falgo5WeeklyLevelPriceForTier(fk.levelTier);
   double tpPts = 0.0, slPts = 0.0;
   Falgo5EffectiveTpSlPointsFromMagicKey(fk, tpPts, slPts);
   tr.level = DoubleToString(levelPrice, _Digits);
   tr.tp = DoubleToString(tpPts, 1);
   tr.sl = DoubleToString(slPts, 1);
}

//+------------------------------------------------------------------+
//| After UpdateTradeResultsForDay: fill level/tp/sl for falgo5 rows from magic (not order comment). |
//+------------------------------------------------------------------+
void Falgo5EnrichAllTradeResultsLevelTpSl()
{
   for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
      Falgo5EnrichTradeResultLevelTpSl(g_tradeResults[trIdx]);
}

//+------------------------------------------------------------------+
bool Falgo5RulesetPassesCommon(const int barIdx)
{
   if(g_falgo5Profile.stop_trading_today_if_losing_trades_count > 0 &&
      g_falgo5DayLosses >= g_falgo5Profile.stop_trading_today_if_losing_trades_count)
      return false;
   if(g_falgo5Profile.stop_trading_today_if_winning_trades_count > 0 &&
      g_falgo5DayWins >= g_falgo5Profile.stop_trading_today_if_winning_trades_count)
      return false;
   if(Falgo5HasOpenPositionOnSymbol())
      return false;
   if(Falgo5HasPendingOrderOnSymbol())
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool Falgo5RulesetPassesForLong(const int barIdx)
{
   if(!Falgo5RulesetPassesCommon(barIdx))
      return false;
   if(Falgo5GetBounceCountForGate(barIdx) > g_falgo5Profile.bounceMaxAllowed_today)
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool Falgo5RulesetPassesForShort(const int barIdx)
{
   if(!Falgo5RulesetPassesCommon(barIdx))
      return false;
   if(Falgo5GetCeilingCountForGate(barIdx) > g_falgo5Profile.ceilingMaxAllowed_today)
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool Falgo5ProfileAllowsNewOrdersNow()
{
   return Falgo5ProfileAllowsNewOrdersAtTime(g_lastTimer1Time);
}

//+------------------------------------------------------------------+
void Falgo5EvaluateGatesAtBar(const int barIdx, const datetime evalTime,
   string &outCloseVsLevel, string &outDirection, int &outTier,
   bool &outProxOK, bool &outBounceOK, bool &outCeilingOK, bool &outWeeklyOK, bool &outAnchorOK,
   bool &outMagicFree, bool &outUnderLossStop, bool &outUnderWinStop,
   bool &outNoOpenPos, bool &outNoPending, bool &outRulesetCommon, bool &outRulesetDir)
{
   outCloseVsLevel = "no_level";
   outDirection = "none";
   outTier = 0;
   outProxOK = false;
   outBounceOK = false;
   outCeilingOK = false;
   outWeeklyOK = g_falgo5Profile.tradesWeeklyLevels;
   outAnchorOK = false;
   outMagicFree = false;
   outUnderLossStop = true;
   outUnderWinStop = true;
   outNoOpenPos = !Falgo5HasOpenPositionOnSymbol();
   outNoPending = !Falgo5HasPendingOrderOnSymbol();
   outRulesetCommon = false;
   outRulesetDir = false;

   if(barIdx < 0 || barIdx >= g_barsInDay)
      return;

   const double anchor = g_pullingHistoryAlgo5AtBar[barIdx].closestWeeklyLevelToCClose;
   const double prox = g_pullingHistoryAlgo5AtBar[barIdx].closestPriceProximity;
   const double c = g_m1Rates[barIdx].close;
   const int bounce = Falgo5GetBounceCountForGate(barIdx);
   const int ceiling = Falgo5GetCeilingCountForGate(barIdx);

   if(g_falgo5Profile.stop_trading_today_if_losing_trades_count > 0)
      outUnderLossStop = (g_falgo5DayLosses < g_falgo5Profile.stop_trading_today_if_losing_trades_count);
   if(g_falgo5Profile.stop_trading_today_if_winning_trades_count > 0)
      outUnderWinStop = (g_falgo5DayWins < g_falgo5Profile.stop_trading_today_if_winning_trades_count);

   outRulesetCommon = outUnderLossStop && outUnderWinStop && outNoOpenPos && outNoPending;

   if(anchor <= 0.0)
      return;

   if(MathAbs(c - anchor) < 1e-12)
      outCloseVsLevel = "flat";
   else if(c > anchor)
   {
      outCloseVsLevel = "above";
      outDirection = "long";
      outProxOK = (prox <= g_falgo5Profile.priceProximityLongs);
      outBounceOK = (bounce <= g_falgo5Profile.bounceMaxAllowed_today);
      outCeilingOK = true;
      outRulesetDir = outRulesetCommon && outBounceOK;
   }
   else
   {
      outCloseVsLevel = "below";
      outDirection = "short";
      outProxOK = (prox <= g_falgo5Profile.priceProximityShorts);
      outBounceOK = true;
      outCeilingOK = (ceiling <= g_falgo5Profile.ceilingMaxAllowed_today);
      outRulesetDir = outRulesetCommon && outCeilingOK;
   }

   if(!outWeeklyOK || !outProxOK)
      return;

   const int levelIdx = FindExpandedLevelIndexByPrice(anchor);
   if(levelIdx < 0)
      return;
   outAnchorOK = Falgo5LevelEligibleForClosestAnchor(levelIdx);
   if(!outAnchorOK)
      return;

   outTier = Falgo5LevelTierFromLevelIdx(levelIdx);

   int dirCode = 0;
   double offPts = 0.0;
   if(outDirection == "long")
   {
      dirCode = FALGO5_DIRECTION_LONG_LIMIT;
      offPts = g_falgo5Profile.levelOffset_longs;
   }
   else if(outDirection == "short")
   {
      dirCode = FALGO5_DIRECTION_SHORT_LIMIT;
      offPts = g_falgo5Profile.levelOffset_shorts;
   }
   else
      return;

   Falgo5MagicKey planKey;
   if(!Falgo5BuildMagicKeyForPlacement(barIdx, dirCode, anchor, levelIdx, offPts, planKey))
      return;

   RefreshOccupiedMagicsCache();
   const long magic = BuildFalgo5MagicNumber(planKey);
   outMagicFree = CanPlaceNewOrderForMagic_Cached(magic);
}

//+------------------------------------------------------------------+
double Falgo5ProfileOffsetPointsForDirection(const int direction)
{
   if(direction == FALGO5_DIRECTION_LONG_LIMIT)
      return g_falgo5Profile.levelOffset_longs;
   if(direction == FALGO5_DIRECTION_SHORT_LIMIT)
      return g_falgo5Profile.levelOffset_shorts;
   return 0.0;
}

//+------------------------------------------------------------------+
//| Pending limit price from closest weekly level + profile offset (same as Place*AtLevel). |
//+------------------------------------------------------------------+
string Falgo5PlannedTradePriceForGates(const int barIdx, const string &closeVsLevel)
{
   const double anchor = g_pullingHistoryAlgo5AtBar[barIdx].closestWeeklyLevelToCClose;
   if(anchor <= 0.0)
      return "";
   int dirForPrices = 0;
   double offsetPoints = 0.0;
   if(closeVsLevel == "above")
   {
      dirForPrices = MAGIC_TRADE_LONG;
      offsetPoints = g_falgo5Profile.levelOffset_longs;
   }
   else if(closeVsLevel == "below")
   {
      dirForPrices = MAGIC_TRADE_SHORT;
      offsetPoints = g_falgo5Profile.levelOffset_shorts;
   }
   else
      return "";
   double orderPrice = 0.0, slDummy = 0.0, tpDummy = 0.0;
   PendingOrderPricesForDirection(dirForPrices, anchor, offsetPoints, 0.0, 0.0, orderPrice, slDummy, tpDummy);
   return DoubleToString(orderPrice, _Digits);
}

//+------------------------------------------------------------------+
string Falgo5OffsetPointsStrForMagic(const long magic)
{
   Falgo5MagicKey fk = ParseFalgo5Magic(magic);
   const double off = Falgo5ProfileOffsetPointsForDirection(fk.direction);
   if(fk.direction != FALGO5_DIRECTION_LONG_LIMIT && fk.direction != FALGO5_DIRECTION_SHORT_LIMIT)
      return "";
   return DoubleToString(off, 1);
}

//+------------------------------------------------------------------+
//| Raw g_levelsExpanded[].tag for trade row (from level price / magic tier). |
//+------------------------------------------------------------------+
string Falgo5LevelTagUneditedForTradeResult(const TradeResult &tr)
{
   double levelPrice = StringToDouble(tr.level);
   if(levelPrice <= 0.0)
   {
      Falgo5MagicKey fk = ParseFalgo5Magic(tr.magic);
      if(fk.levelTier >= 1 && fk.levelTier <= FALGO5_LEVEL_TIER_MAX)
      {
         const double tierPx = Falgo5WeeklyLevelPriceForTier(fk.levelTier);
         if(tierPx > 0.0)
            levelPrice = tierPx;
      }
   }
   if(levelPrice <= 0.0)
      return "";
   const int levelIdx = FindExpandedLevelIndexByPrice(levelPrice);
   if(levelIdx < 0)
      return "";
   return g_levelsExpanded[levelIdx].tag;
}

//+------------------------------------------------------------------+
void Falgo5PlanAndLevelTradeNumsFromMagic(const long magic, int &outPlanTradeNumToday, int &outLevelTradeNumToday)
{
   const Falgo5MagicKey fk = ParseFalgo5Magic(magic);
   outPlanTradeNumToday = fk.planTradeNum;
   outLevelTradeNumToday = fk.levelTradeNum;
}

//+------------------------------------------------------------------+
//| Falgo5 trade still open at candle close (from g_tradeResults day snapshot). |
//+------------------------------------------------------------------+
bool Falgo5FindOpenFalgo5TradeAsOfCloseTime(const datetime candleCloseTime, TradeResult &outTr)
{
   bool found = false;
   datetime bestStart = 0;
   for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
   {
      TradeResult tr = g_tradeResults[trIdx];
      if(!IsFalgo5CompositeMagicSlot1(tr.magic))
         continue;
      if(tr.startTime >= candleCloseTime)
         continue;
      if(tr.foundOut && tr.endTime < candleCloseTime)
         continue;
      if(!found || tr.startTime > bestStart)
      {
         outTr = tr;
         bestStart = tr.startTime;
         found = true;
      }
   }
   if(!found)
      return false;
   outTr.foundOut = true;
   outTr.endTime = candleCloseTime;
   return true;
}

//+------------------------------------------------------------------+
//| MFE/MAE in points from entry; empty strings if no open falgo5 trade at evalTime. |
//+------------------------------------------------------------------+
void Falgo5GatesMfeMaePointsAsOfClose(const datetime candleCloseTime, string &outMfePts, string &outMaePts)
{
   outMfePts = "";
   outMaePts = "";
   TradeResult tr;
   if(!Falgo5FindOpenFalgo5TradeAsOfCloseTime(candleCloseTime, tr))
      return;
   double mfePx = 0.0, maePx = 0.0;
   int mfeCandle = 0, maeCandle = 0;
   GetMFEandMAEForTrade(tr, mfePx, maePx, mfeCandle, maeCandle);
   double mfePts = 0.0, maePts = 0.0;
   GetMFEpAndMAEpForTrade(tr, mfePx, maePx, mfePts, maePts);
   outMfePts = DoubleToString(mfePts, 1);
   outMaePts = DoubleToString(maePts, 1);
}

//+------------------------------------------------------------------+
void Falgo5WriteGatesLogHeaderIfNeeded(const int fh)
{
   FileSeek(fh, 0, SEEK_END);
   if(FileTell(fh) != 0)
      return;
   FileWrite(fh,
      "barTime", "O", "H", "L", "C",
      "closestWeeklyLevel", "plannedTradePrice", "firstFailGate", "MFE", "MAE",
      "closestProximity", "bounceCount_today", Falgo5GatesColRecentBounceCount(), "ceilingCount_today", Falgo5GatesColRecentCeilingCount(),
      "closeVsLevel", "direction", "levelTier", "proximityOK", "bounceOK", "ceilingOK",
      "tradesWeeklyLevels", "anchorInExpanded",
      "plannedTradeNumber", "magicNotOccupied", "dayWins", "dayLosses",
      "underLossStopLimit", "underWinStopLimit", "noOpenFalgo5Pos", "noPendingFalgo5Order",
      "rulesetCommonOK", "rulesetDirectionOK",
      "profileEnabled", "tradingDayAllowed", "tradingTimeAllowed", "profileAllowsNewOrders",
      "orderPlacedThisBar");
}

//+------------------------------------------------------------------+
void Falgo5AppendGatesLogRow(const int barIdx)
{
   if(barIdx < 0 || barIdx >= g_barsInDay || g_m1DayStart == 0)
      return;
   const datetime barTime = g_m1Rates[barIdx].time;
   const datetime evalTime = barTime + 60;

   string closeVs = "", direction = "";
   int tier = 0;
   bool proxOK = false, bounceOK = false, ceilingOK = false, weeklyOK = false, anchorOK = false;
   bool magicFree = false;
   bool underLoss = false, underWin = false, noOpen = false, noPending = false;
   bool rulesCommon = false, rulesDir = false;
   Falgo5EvaluateGatesAtBar(barIdx, evalTime, closeVs, direction, tier,
      proxOK, bounceOK, ceilingOK, weeklyOK, anchorOK, magicFree,
      underLoss, underWin, noOpen, noPending, rulesCommon, rulesDir);

   const int plannedTradeNumber = g_falgo5PlanTradeNumToday + 1;
   const string plannedTradePrice = Falgo5PlannedTradePriceForGates(barIdx, closeVs);

   const bool profileEnabled = g_falgo5Profile.enabled;
   const bool tradingDay = Falgo5IsTradingDayAllowedAtTime(evalTime);
   const bool tradingTime = Falgo5IsTradingTimeAllowed(evalTime);
   const bool profileAllows = Falgo5ProfileAllowsNewOrdersAtTime(evalTime);

   string firstFail = "";
   if(!profileEnabled) firstFail = "profileDisabled";
   else if(!tradingDay) firstFail = "tradingDayBanned";
   else if(!tradingTime) firstFail = "tradingTimeBanned";
   else if(!underLoss) firstFail = "lossStopDayLimit";
   else if(!underWin) firstFail = "winStopDayLimit";
   else if(!noOpen) firstFail = "openFalgo5Position";
   else if(!noPending) firstFail = "pendingFalgo5Order";
   else if(g_pullingHistoryAlgo5AtBar[barIdx].closestWeeklyLevelToCClose <= 0.0) firstFail = "noClosestWeeklyLevel";
   else if(closeVs == "flat") firstFail = "closeFlatOnLevel";
   else if(!weeklyOK) firstFail = "tradesWeeklyLevelsOff";
   else if(!anchorOK) firstFail = "anchorNotEligible";
   else if(direction == "long" && !bounceOK)
   {
      if(g_falgo5Profile.recentBounceCountToday_Minutes > 0)
         firstFail = StringFormat("%s>%d", Falgo5GatesColRecentBounceCount(), g_falgo5Profile.bounceMaxAllowed_today);
      else
         firstFail = StringFormat("bounceCount>%d", g_falgo5Profile.bounceMaxAllowed_today);
   }
   else if(direction == "short" && !ceilingOK)
   {
      if(g_falgo5Profile.recentCeilingCountToday_Minutes > 0)
         firstFail = StringFormat("%s>%d", Falgo5GatesColRecentCeilingCount(), g_falgo5Profile.ceilingMaxAllowed_today);
      else
         firstFail = StringFormat("ceilingCount>%d", g_falgo5Profile.ceilingMaxAllowed_today);
   }
   else if(!magicFree) firstFail = "magicOccupied";
   else if(!proxOK) firstFail = "proximity";
   else if(rulesDir && magicFree) firstFail = "";

   string mfePts = "", maePts = "";
   Falgo5GatesMfeMaePointsAsOfClose(evalTime, mfePts, maePts);

   const string dateStr = TimeToString(g_m1DayStart, TIME_DATE);
   const string fname = dateStr + "_algo5_gates_per_minute.csv";
   int fh = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
      return;
   Falgo5WriteGatesLogHeaderIfNeeded(fh);
   FileSeek(fh, 0, SEEK_END);
   FileWrite(fh,
      TimeToString(barTime, TIME_DATE|TIME_MINUTES),
      DoubleToString(g_m1Rates[barIdx].open, _Digits),
      DoubleToString(g_m1Rates[barIdx].high, _Digits),
      DoubleToString(g_m1Rates[barIdx].low, _Digits),
      DoubleToString(g_m1Rates[barIdx].close, _Digits),
      DoubleToString(g_pullingHistoryAlgo5AtBar[barIdx].closestWeeklyLevelToCClose, _Digits),
      plannedTradePrice,
      firstFail,
      mfePts,
      maePts,
      DoubleToString(g_pullingHistoryAlgo5AtBar[barIdx].closestPriceProximity, _Digits),
      IntegerToString(g_pullingHistoryAlgo5AtBar[barIdx].closestWeeklyLevel_BounceCount_today),
      IntegerToString(g_pullingHistoryAlgo5AtBar[barIdx].closestWeeklyLevel_BounceCount_recent),
      IntegerToString(g_pullingHistoryAlgo5AtBar[barIdx].closestWeeklyLevel_CeilingCount_today),
      IntegerToString(g_pullingHistoryAlgo5AtBar[barIdx].closestWeeklyLevel_CeilingCount_recent),
      closeVs, direction, IntegerToString(tier),
      Falgo5BoolCsv(proxOK), Falgo5BoolCsv(bounceOK), Falgo5BoolCsv(ceilingOK),
      Falgo5BoolCsv(weeklyOK), Falgo5BoolCsv(anchorOK),
      IntegerToString(plannedTradeNumber),
      Falgo5BoolCsv(magicFree),
      IntegerToString(g_falgo5DayWins), IntegerToString(g_falgo5DayLosses),
      Falgo5BoolCsv(underLoss), Falgo5BoolCsv(underWin),
      Falgo5BoolCsv(noOpen), Falgo5BoolCsv(noPending),
      Falgo5BoolCsv(rulesCommon), Falgo5BoolCsv(rulesDir),
      Falgo5BoolCsv(profileEnabled), Falgo5BoolCsv(tradingDay), Falgo5BoolCsv(tradingTime),
      Falgo5BoolCsv(profileAllows),
      Falgo5BoolCsv(g_falgo5OrderPlacedLastPipeline));
   FileClose(fh);
}

//+------------------------------------------------------------------+
void Falgo5TryLogGatesForClosedMinute()
{
   if(!dailySpamLog_Algo5GatesPerMinute)
      return;
   if(g_barsInDay < 1 || g_m1DayStart == 0)
      return;
   if(g_falgo5GatesLogDayStart != g_m1DayStart)
   {
      g_falgo5GatesLogDayStart = g_m1DayStart;
      g_falgo5GatesLastLoggedBarTime = 0;
   }
   int barIdx = g_barsInDay - 2;
   if(g_barsInDay < 2)
      return;
   const datetime barTime = g_m1Rates[barIdx].time;
   if(barTime == g_falgo5GatesLastLoggedBarTime)
      return;
   g_falgo5GatesLastLoggedBarTime = barTime;
   Falgo5AppendGatesLogRow(barIdx);
}

//+------------------------------------------------------------------+
double GetTradeLotForFalgo5()
{
   return g_global_base_trade_size * ((double)g_falgo5Profile.tradeSizePct / 100.0);
}

//+------------------------------------------------------------------+
double Falgo5OpenPositionProfitPoints()
{
   const double openPrice = ExtPositionInfo.PriceOpen();
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY)
      return SymbolInfoDouble(_Symbol, SYMBOL_BID) - openPrice;
   return openPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK);
}

//+------------------------------------------------------------------+
bool Babysitf_falgo5_closeIfProfitPointsAtLeast(const long positionMagic, const double minProfitPoints)
{
   if(minProfitPoints <= 0.0)
      return false;
   const double profitPts = Falgo5OpenPositionProfitPoints();
   if(profitPts < minProfitPoints)
      return false;
   ExtTrade.SetExpertMagicNumber((ulong)positionMagic);
   const bool closed = ExtTrade.PositionClose(ExtPositionInfo.Ticket());
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   return closed;
}

//+------------------------------------------------------------------+
//| secretTPSL SL leg: close when floating loss >= minLossPoints (mirror of TP profit rule). |
//+------------------------------------------------------------------+
bool Babysitf_falgo5_closeIfLossPointsAtLeast(const long positionMagic, const double minLossPoints)
{
   if(minLossPoints <= 0.0)
      return false;
   const double profitPts = Falgo5OpenPositionProfitPoints();
   if(profitPts > -minLossPoints)
      return false;
   ExtTrade.SetExpertMagicNumber((ulong)positionMagic);
   const bool closed = ExtTrade.PositionClose(ExtPositionInfo.Ticket());
   ExtTrade.SetExpertMagicNumber(DEFAULT_ORDER_MAGIC);
   return closed;
}

//+------------------------------------------------------------------+
void Babysitf_RunAllOpenFalgo5PositionsForSymbol()
{
   for(int positionIdx = PositionsTotal() - 1; positionIdx >= 0; positionIdx--)
   {
      if(!ExtPositionInfo.SelectByIndex(positionIdx))
         continue;
      if(ExtPositionInfo.Symbol() != _Symbol)
         continue;
      const long posMagic = ExtPositionInfo.Magic();
      if(!IsFalgo5CompositeMagicSlot1(posMagic))
         continue;
      if(!g_falgo5Profile.babysit_enabled)
         continue;
      Falgo5MagicKey fk = ParseFalgo5Magic(posMagic);
      const int babysitStartMin = fk.babysitMinute;
      const int minutesOpen = (int)((g_lastTimer1Time - ExtPositionInfo.Time()) / 60);
      if(minutesOpen < babysitStartMin)
         continue;
      if(g_falgo5Profile.saving_trade_TP > 0.0)
      {
         if(Babysitf_falgo5_closeIfProfitPointsAtLeast(posMagic, PointSized(g_falgo5Profile.saving_trade_TP)))
            continue;
      }
      if(g_falgo5Profile.secretTPSL && g_falgo5Profile.secretTPSL_percent > 0)
      {
         const double secretFrac = (double)g_falgo5Profile.secretTPSL_percent / 100.0;
         if(fk.tpWhole > 0)
         {
            const double secretTpPts = PointSized((double)fk.tpWhole) * secretFrac;
            if(Babysitf_falgo5_closeIfProfitPointsAtLeast(posMagic, secretTpPts))
               continue;
         }
         if(fk.slWhole > 0)
         {
            const double secretSlPts = PointSized((double)fk.slWhole) * secretFrac;
            if(Babysitf_falgo5_closeIfLossPointsAtLeast(posMagic, secretSlPts))
               continue;
         }
      }
   }
}

//+------------------------------------------------------------------+
bool Falgo5BuildMagicKeyForPlacement(const int barIdx, const int direction, const double anchorLevel,
   const int levelExpandedIdx, const double offsetPoints, Falgo5MagicKey &outKey)
{
   if(direction != FALGO5_DIRECTION_LONG_LIMIT && direction != FALGO5_DIRECTION_SHORT_LIMIT)
      FatalError(StringFormat("Falgo5BuildMagicKeyForPlacement: unsupported direction %d", direction));
   const int tier = Falgo5LevelTierFromLevelIdx(levelExpandedIdx);
   if(tier < 1 || tier > FALGO5_LEVEL_TIER_MAX)
      FatalError(StringFormat("Falgo5BuildMagicKeyForPlacement: tier %d out of range", tier));
   const int nextLevelTradeNum = g_falgo5LevelTradeNumByTier[tier] + 1;

   outKey.direction = direction;
   outKey.dayOfWeek = Falgo5DayOfWeekSlotFromTime(g_lastTimer1Time);
   outKey.levelTier = tier;
   outKey.bounceCount = Falgo5Clamp0_8(Falgo5GetBounceCountForClosestWeeklyLevel(barIdx));
   outKey.ceilingCount = Falgo5Clamp0_8(Falgo5GetCeilingCountForClosestWeeklyLevel(barIdx));
   outKey.offset_tenths = EncodeMagicTwoDigitTenths(MathAbs(offsetPoints));
   outKey.planTradeNum = Falgo5Clamp0_8(g_falgo5PlanTradeNumToday + 1);
   outKey.levelTradeNum = Falgo5Clamp0_8(nextLevelTradeNum);
   outKey.babysitMinute = Falgo5Clamp0_9(g_falgo5Profile.babysitStart_minute);
   outKey.subsetA = 0;
   outKey.subsetB = 0;
   outKey.tpWhole = Falgo5CapWholeTpSlForMagic(g_falgo5Profile.initialTP);
   outKey.slWhole = Falgo5CapWholeTpSlForMagic(g_falgo5Profile.initialSL);
   return true;
}

//+------------------------------------------------------------------+
bool Falgo5TryPlaceOneOrderThisTick(const int barIdx)
{
   const double anchorLevel = g_pullingHistoryAlgo5AtBar[barIdx].closestWeeklyLevelToCClose;
   if(anchorLevel <= 0.0)
      return false;
   const double prox = g_pullingHistoryAlgo5AtBar[barIdx].closestPriceProximity;
   const double c = g_m1Rates[barIdx].close;
   if(MathAbs(c - anchorLevel) < 1e-12)
      return false;

   int direction = 0;
   double offsetPoints = 0.0;
   double proximityLimit = 0.0;
   if(c > anchorLevel)
   {
      direction = FALGO5_DIRECTION_LONG_LIMIT;
      offsetPoints = g_falgo5Profile.levelOffset_longs;
      proximityLimit = g_falgo5Profile.priceProximityLongs;
      if(prox > proximityLimit)
         return false;
      if(!Falgo5RulesetPassesForLong(barIdx))
         return false;
   }
   else if(c < anchorLevel)
   {
      direction = FALGO5_DIRECTION_SHORT_LIMIT;
      offsetPoints = g_falgo5Profile.levelOffset_shorts;
      proximityLimit = g_falgo5Profile.priceProximityShorts;
      if(prox > proximityLimit)
         return false;
      if(!Falgo5RulesetPassesForShort(barIdx))
         return false;
   }
   else
      return false;

   if(!g_falgo5Profile.tradesWeeklyLevels)
      return false;

   const int levelExpandedIdx = FindExpandedLevelIndexByPrice(anchorLevel);
   if(levelExpandedIdx < 0)
      FatalError(StringFormat("Falgo5TryPlaceOneOrderThisTick: anchor level %s not in g_levelsExpanded today", DoubleToString(anchorLevel, _Digits)));
   if(!Falgo5LevelEligibleForClosestAnchor(levelExpandedIdx))
      return false;

   Falgo5MagicKey planKey;
   if(!Falgo5BuildMagicKeyForPlacement(barIdx, direction, anchorLevel, levelExpandedIdx, offsetPoints, planKey))
      return false;

   const long magic = BuildFalgo5MagicNumber(planKey);
   if(!CanPlaceNewOrderForMagic_Cached(magic))
      return false;

   const int expirationMin = (direction == FALGO5_DIRECTION_LONG_LIMIT) ?
      g_falgo5Profile.long_expiry_minutes : g_falgo5Profile.short_expiry_minutes;
   const double lot = GetTradeLotForFalgo5();
   if(!PlacePendingFromFalgo5Magic(magic, anchorLevel, offsetPoints, g_falgo5Profile.initialTP, g_falgo5Profile.initialSL, expirationMin, lot))
      return false;

   g_falgo5OrderPlacedLastPipeline = true;
   WriteTradeLogPendingOrderFalgo5(anchorLevel, offsetPoints, g_falgo5Profile.initialTP, g_falgo5Profile.initialSL, magic, expirationMin);
   return true;
}

//+------------------------------------------------------------------+
//| One falgo5 placement attempt per tick (closest weekly level vs close). |
//+------------------------------------------------------------------+
void RunFalgo5TradePipeline()
{
   g_falgo5OrderPlacedLastPipeline = false;
   UpdateFalgo5DayTradeCounts();
   Babysitf_RunAllOpenFalgo5PositionsForSymbol();

   if(!Falgo5ProfileAllowsNewOrdersNow())
      return;
   if(g_barsInDay < 1)
      return;

   if(g_m1DayStart != 0)
      Falgo5ResetPlanCountersIfNewDay(g_m1DayStart);

   const int barIdx = g_barsInDay - 1;
   if(!Falgo5RulesetPassesCommon(barIdx))
      return;

   RefreshOccupiedMagicsCache();
   Falgo5TryPlaceOneOrderThisTick(barIdx);
}

//+------------------------------------------------------------------+
#define FALGO5_ALLDAYS_HEADER "date,symbol,startTime,endTime,session,magic,priceStart,priceEnd,priceDiff,profit,type,reason,volume,bothComments,level,levelTag,planTradeNumToday,levelTradeNumToday,offset,tp,sl"
#define FALGO5_ALLDAYS_COLS     21

//+------------------------------------------------------------------+
void Falgo5AppendTradeResultCells(string &cells[], const string dateStr, const TradeResult &tr)
{
   const int base = ArraySize(cells);
   ArrayResize(cells, base + FALGO5_ALLDAYS_COLS);
   cells[base + 0]  = dateStr;
   cells[base + 1]  = tr.symbol;
   cells[base + 2]  = TimeToString(tr.startTime, TIME_DATE|TIME_SECONDS);
   cells[base + 3]  = TimeToString(tr.endTime, TIME_DATE|TIME_SECONDS);
   cells[base + 4]  = tr.session;
   cells[base + 5]  = IntegerToString((long)tr.magic);
   cells[base + 6]  = DoubleToString(tr.priceStart, _Digits);
   cells[base + 7]  = DoubleToString(tr.priceEnd, _Digits);
   cells[base + 8]  = DoubleToString(tr.priceDiff, _Digits);
   cells[base + 9]  = DoubleToString(tr.profit, 2);
   cells[base + 10] = EnumToString((ENUM_DEAL_TYPE)tr.type);
   cells[base + 11] = EnumToString((ENUM_DEAL_REASON)tr.reason);
   cells[base + 12] = (string)tr.volume;
   cells[base + 13] = tr.bothComments;
   int planNum = 0, levelNum = 0;
   Falgo5PlanAndLevelTradeNumsFromMagic(tr.magic, planNum, levelNum);
   cells[base + 14] = tr.level;
   cells[base + 15] = Falgo5LevelTagUneditedForTradeResult(tr);
   cells[base + 16] = IntegerToString(planNum);
   cells[base + 17] = IntegerToString(levelNum);
   cells[base + 18] = Falgo5OffsetPointsStrForMagic(tr.magic);
   cells[base + 19] = tr.tp;
   cells[base + 20] = tr.sl;
}

//+------------------------------------------------------------------+
bool Falgo5AllDaysRowsContainTrade(const string &cells[], const int rowCount, const long magic, const datetime startTime)
{
   const string magicStr = IntegerToString(magic);
   const string startStr = TimeToString(startTime, TIME_DATE|TIME_SECONDS);
   for(int ri = 0; ri < rowCount; ri++)
   {
      const int base = ri * FALGO5_ALLDAYS_COLS;
      if(cells[base + 5] == magicStr && cells[base + 2] == startStr)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| EOD: per-day algo5 CSV (rewrite) + all-days TSV (read/merge/append today's falgo5 only). |
//+------------------------------------------------------------------+
void WriteFalgo5EodTradeResultsCsvsIfNeeded(const string dateStr, const int falgo5OutCount)
{
   if(!dailyEODlog_TradeResultsCsvFalgo5 || falgo5OutCount <= 0)
      return;

   const string csvName = dateStr + "_summaryZ_tradeResults_ALL_Day_algo5.csv";
   int fhDay = FileOpen(csvName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_CSV | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fhDay != INVALID_HANDLE)
   {
      FileWrite(fhDay, "symbol", "startTime", "endTime", "session", "magic", "priceStart", "priceEnd", "priceDiff", "profit", "type", "reason", "volume", "bothComments", "level", "levelTag", "planTradeNumToday", "levelTradeNumToday", "offset", "tp", "sl");
      for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
      {
         TradeResult tr = g_tradeResults[trIdx];
         if(!tr.foundOut || !IsFalgo5CompositeMagicSlot1(tr.magic))
            continue;
         int planNum = 0, levelNum = 0;
         Falgo5PlanAndLevelTradeNumsFromMagic(tr.magic, planNum, levelNum);
         FileWrite(fhDay, tr.symbol,
            TimeToString(tr.startTime, TIME_DATE|TIME_SECONDS),
            TimeToString(tr.endTime, TIME_DATE|TIME_SECONDS),
            tr.session,
            IntegerToString((long)tr.magic),
            DoubleToString(tr.priceStart, _Digits),
            DoubleToString(tr.priceEnd, _Digits),
            DoubleToString(tr.priceDiff, _Digits),
            DoubleToString(tr.profit, 2),
            EnumToString((ENUM_DEAL_TYPE)tr.type),
            EnumToString((ENUM_DEAL_REASON)tr.reason),
            tr.volume, tr.bothComments, tr.level, Falgo5LevelTagUneditedForTradeResult(tr),
            IntegerToString(planNum), IntegerToString(levelNum),
            Falgo5OffsetPointsStrForMagic(tr.magic), tr.tp, tr.sl);
      }
      FileClose(fhDay);
   }

   const string summaryAllName = "summary_tradeResults_all_days_algo5.tsv";
   string headerParts[];
   const int schemaCols = StringSplit(FALGO5_ALLDAYS_HEADER, ',', headerParts);
   if(schemaCols != FALGO5_ALLDAYS_COLS)
      FatalError(StringFormat("WriteFalgo5EodTradeResultsCsvsIfNeeded: schemaCols %d != FALGO5_ALLDAYS_COLS %d", schemaCols, FALGO5_ALLDAYS_COLS));

   string allDaysCells[];
   int existingRowCount = 0;
   int fhRead = FileOpen(summaryAllName, FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fhRead != INVALID_HANDLE)
   {
      for(int h = 0; h < schemaCols && !FileIsEnding(fhRead); h++)
         FileReadString(fhRead);
      while(!FileIsEnding(fhRead))
      {
         const int base = ArraySize(allDaysCells);
         ArrayResize(allDaysCells, base + schemaCols);
         int c = 0;
         for(; c < schemaCols && !FileIsEnding(fhRead); c++)
            allDaysCells[base + c] = FileReadString(fhRead);
         for(; c < schemaCols; c++)
            allDaysCells[base + c] = "";
         existingRowCount++;
      }
      FileClose(fhRead);
   }

   for(int trIdx = 0; trIdx < g_tradeResultsCount; trIdx++)
   {
      TradeResult tr = g_tradeResults[trIdx];
      if(!tr.foundOut || !IsFalgo5CompositeMagicSlot1(tr.magic))
         continue;
      if(Falgo5AllDaysRowsContainTrade(allDaysCells, existingRowCount, tr.magic, tr.startTime))
         continue;
      Falgo5AppendTradeResultCells(allDaysCells, dateStr, tr);
      existingRowCount++;
   }

   int fhAll = FileOpen(summaryAllName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fhAll != INVALID_HANDLE)
   {
      FileWrite(fhAll, "date", "symbol", "startTime", "endTime", "session", "magic", "priceStart", "priceEnd", "priceDiff", "profit", "type", "reason", "volume", "bothComments", "level", "levelTag", "planTradeNumToday", "levelTradeNumToday", "offset", "tp", "sl");
      for(int ri = 0; ri < existingRowCount; ri++)
      {
         const int base = ri * FALGO5_ALLDAYS_COLS;
         FileWrite(fhAll,
            allDaysCells[base + 0], allDaysCells[base + 1], allDaysCells[base + 2], allDaysCells[base + 3], allDaysCells[base + 4],
            allDaysCells[base + 5], allDaysCells[base + 6], allDaysCells[base + 7], allDaysCells[base + 8], allDaysCells[base + 9],
            allDaysCells[base + 10], allDaysCells[base + 11], allDaysCells[base + 12], allDaysCells[base + 13], allDaysCells[base + 14],
            allDaysCells[base + 15], allDaysCells[base + 16], allDaysCells[base + 17], allDaysCells[base + 18],
            allDaysCells[base + 19], allDaysCells[base + 20]);
      }
      FileClose(fhAll);
   }
}

#endif // SMASHELITO_FALGO5_MQH
