//| Algo rule engine: ordered rule chains per slot (g_breakdownAlgos[].rules). |
//+------------------------------------------------------------------+
void BreakdownRuleChainClear(const int slotIdx)
{
   g_breakdownAlgos[slotIdx].rule_count = 0;
}

//+------------------------------------------------------------------+
void BreakdownRuleChainAdd(const int slotIdx, const ENUM_ALGO_RULE ruleId,
                      const int i0 = 0, const int i1 = 0,
                      const double d0 = 0.0, const double d1 = 0.0,
                      const string s0 = "")
{
   if(slotIdx < 0 || slotIdx >= g_breakdownAlgoCount)
      FatalError("BreakdownRuleChainAdd: invalid slotIdx");
   if(g_breakdownAlgos[slotIdx].rule_count >= ALGO_RULES_MAX)
      FatalError(StringFormat("BreakdownRuleChainAdd: ALGO_RULES_MAX exceeded for algo %d", g_breakdownAlgos[slotIdx].algo_id));
   const int r = g_breakdownAlgos[slotIdx].rule_count;
   g_breakdownAlgos[slotIdx].rules[r].rule_id = ruleId;
   g_breakdownAlgos[slotIdx].rules[r].i0 = i0;
   g_breakdownAlgos[slotIdx].rules[r].i1 = i1;
   g_breakdownAlgos[slotIdx].rules[r].d0 = d0;
   g_breakdownAlgos[slotIdx].rules[r].d1 = d1;
   g_breakdownAlgos[slotIdx].rules[r].s0 = s0;
   g_breakdownAlgos[slotIdx].rule_count++;
}

//+------------------------------------------------------------------+
void AlgoRuleAdd_CleanStreakLong(const int slotIdx, const int minStreakCount, const double minAnchorAbove)
{
   BreakdownRuleChainAdd(slotIdx, RULE_CLEAN_STREAK_LONG, minStreakCount, 0, minAnchorAbove);
}

void AlgoRuleAdd_CleanStreakShort(const int slotIdx, const int minStreakCount, const double minAnchorBelow)
{
   BreakdownRuleChainAdd(slotIdx, RULE_CLEAN_STREAK_SHORT, minStreakCount, 0, minAnchorBelow);
}

void AlgoRuleAdd_CleanStreakTooLong(const int slotIdx, const int maxStreakCountExclusive)
{
   BreakdownRuleChainAdd(slotIdx, RULE_CLEAN_STREAK_TOO_LONG, maxStreakCountExclusive);
}

void AlgoRuleAdd_BounceCountTooHigh(const int slotIdx, const int maxAllowed)
{
   BreakdownRuleChainAdd(slotIdx, RULE_BOUNCE_COUNT_TOO_HIGH, maxAllowed);
}

void AlgoRuleAdd_BounceCountTooLow(const int slotIdx, const int minCount)
{
   BreakdownRuleChainAdd(slotIdx, RULE_BOUNCE_COUNT_TOO_LOW, minCount);
}

void AlgoRuleAdd_RecentBounceCountTooHigh(const int slotIdx, const int maxAllowed)
{
   BreakdownRuleChainAdd(slotIdx, RULE_RECENT_BOUNCE_TOO_HIGH, maxAllowed);
}

void AlgoRuleAdd_CeilingProximityCandlesTooHigh(const int slotIdx, const int maxAllowed, const string failTag)
{
   BreakdownRuleChainAdd(slotIdx, RULE_CEILING_PROXIMITY_CANDLES_TOO_HIGH, maxAllowed, 0, 0, 0, failTag);
}

void AlgoRuleAdd_CeilingCountTooHigh(const int slotIdx, const int maxAllowed, const string failTag)
{
   BreakdownRuleChainAdd(slotIdx, RULE_CEILING_COUNT_TOO_HIGH, maxAllowed, 0, 0, 0, failTag);
}

void AlgoRuleAdd_LevelOnoAbsDiffTooLow(const int slotIdx, const double minAbsDiff)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ONO_ABS_DIFF_TOO_LOW, 0, 0, minAbsDiff);
}

void AlgoRuleAdd_OnoAboveLevelTooLow(const int slotIdx, const double minDiff)
{
   BreakdownRuleChainAdd(slotIdx, RULE_ONO_ABOVE_LEVEL_TOO_LOW, 0, 0, minDiff);
}

void AlgoRuleAdd_OnoBelowLevelTooLow(const int slotIdx, const double minDiff)
{
   BreakdownRuleChainAdd(slotIdx, RULE_ONO_BELOW_LEVEL_TOO_LOW, 0, 0, minDiff);
}

void AlgoRuleAdd_DayStartEarlierWeekContactTooHigh(const int slotIdx, const int maxAllowed)
{
   BreakdownRuleChainAdd(slotIdx, RULE_DAYSTART_EARLIER_WEEK_CONTACT_TOO_HIGH, maxAllowed);
}

void AlgoRuleAdd_DayContactTodayTooHigh(const int slotIdx, const int maxAllowed)
{
   BreakdownRuleChainAdd(slotIdx, RULE_DAY_CONTACT_TODAY_TOO_HIGH, maxAllowed);
}

void AlgoRuleAdd_WeekBounceCountTooLow(const int slotIdx, const int minCount)
{
   BreakdownRuleChainAdd(slotIdx, RULE_WEEK_BOUNCE_TOO_LOW, minCount);
}

void AlgoRuleAdd_WeekBounceCountTooHigh(const int slotIdx, const int maxAllowed)
{
   BreakdownRuleChainAdd(slotIdx, RULE_WEEK_BOUNCE_TOO_HIGH, maxAllowed);
}

void AlgoRuleAdd_CeilingCountTooLow(const int slotIdx, const int minCount)
{
   BreakdownRuleChainAdd(slotIdx, RULE_CEILING_COUNT_TOO_LOW, minCount);
}

void AlgoRuleAdd_WeekCeilingCountTooLow(const int slotIdx, const int minCount)
{
   BreakdownRuleChainAdd(slotIdx, RULE_WEEK_CEILING_TOO_LOW, minCount);
}

void AlgoRuleAdd_WeekCeilingCountTooHigh(const int slotIdx, const int maxAllowed)
{
   BreakdownRuleChainAdd(slotIdx, RULE_WEEK_CEILING_TOO_HIGH, maxAllowed);
}

void AlgoRuleAdd_WeekContactCandlesTooHigh(const int slotIdx, const int maxAllowed)
{
   BreakdownRuleChainAdd(slotIdx, RULE_WEEK_CONTACT_CANDLES_TOO_HIGH, maxAllowed);
}

void AlgoRuleAdd_WeekContactCandlesTooLow(const int slotIdx, const int minCount)
{
   BreakdownRuleChainAdd(slotIdx, RULE_WEEK_CONTACT_CANDLES_TOO_LOW, minCount);
}

void AlgoRuleAdd_AnchorAboveTooHigh(const int slotIdx, const double maxAnchorAbove)
{
   BreakdownRuleChainAdd(slotIdx, RULE_ANCHOR_ABOVE_TOO_HIGH, 0, 0, maxAnchorAbove);
}

void AlgoRuleAdd_DayLowSoFarNoMoreThanXBelowLevel(const int slotIdx, const double maxBelowDist)
{
   BreakdownRuleChainAdd(slotIdx, RULE_DAY_LOW_SOFAR_NO_MORE_THAN_X_BELOW_LEVEL, 0, 0, maxBelowDist);
}

void AlgoRuleAdd_DayLowSoFarAtLeastXBelowLevel(const int slotIdx, const double minBelowDist)
{
   BreakdownRuleChainAdd(slotIdx, RULE_DAY_LOW_SOFAR_AT_LEAST_X_BELOW_LEVEL, 0, 0, minBelowDist);
}

void AlgoRuleAdd_DayHighSoFarAtLeastXAboveLevel(const int slotIdx, const double minAboveDist)
{
   BreakdownRuleChainAdd(slotIdx, RULE_DAY_HIGH_SOFAR_AT_LEAST_X_ABOVE_LEVEL, 0, 0, minAboveDist);
}

void AlgoRuleAdd_DayHighSoFarNoMoreThanXAboveLevel(const int slotIdx, const double maxAboveDist)
{
   BreakdownRuleChainAdd(slotIdx, RULE_DAY_HIGH_SOFAR_NO_MORE_THAN_X_ABOVE_LEVEL, 0, 0, maxAboveDist);
}

void AlgoRuleAdd_LevelAbovePDL(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_PDL);
}

void AlgoRuleAdd_LevelBelowPDL(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_PDL);
}

void AlgoRuleAdd_LevelAboveONL(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_ONL);
}

void AlgoRuleAdd_LevelBelowPDC(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_PDC);
}

void AlgoRuleAdd_LevelBelowPDO(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_PDO);
}

void AlgoRuleAdd_PDgreen(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_PD_GREEN);
}

void AlgoRuleAdd_PDred(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_PD_RED);
}

void AlgoRuleAdd_DayBrokePDHfalse(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_DAY_BROKE_PDH);
}

void AlgoRuleAdd_DayBrokePDHtrue(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_DAY_BROKE_PDH_TRUE);
}

void AlgoRuleAdd_DayBrokePDLfalse(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_DAY_BROKE_PDL);
}

void AlgoRuleAdd_LevelBelowPDH(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_PDH);
}

void AlgoRuleAdd_LevelAbovePDH(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_PDH);
}

void AlgoRuleAdd_LevelBelowONL(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_ONL);
}

void AlgoRuleAdd_LevelBelowONH(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_ONH);
}

void AlgoRuleAdd_LevelBelowDayHighSoFar(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_DAY_HIGH);
}

void AlgoRuleAdd_LevelBelowDayLowSoFar(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_DAY_LOW);
}

void AlgoRuleAdd_LevelAboveDayLowSoFar(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_DAY_LOW);
}

void AlgoRuleAdd_LevelBelowMidpoint(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_MIDPOINT);
}

void AlgoRuleAdd_LevelAboveMidpoint(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_MIDPOINT);
}

void AlgoRuleAdd_LevelAboveONH(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_ONH);
}

void AlgoRuleAdd_LevelAboveDayHighSoFar(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_DAY_HIGH);
}

void AlgoRuleAdd_LevelAbovePDO(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_PDO);
}

void AlgoRuleAdd_LevelBelowIBH(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_IBH);
}

void AlgoRuleAdd_LevelBelowIBL(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_IBL);
}

void AlgoRuleAdd_LevelBelowRTHH(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_RTHH);
}

void AlgoRuleAdd_LevelAboveRTHH(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_RTHH);
}

void AlgoRuleAdd_LevelBelowRTHL(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_BELOW_RTHL);
}

void AlgoRuleAdd_LevelTag(const int slotIdx, const string tag)
{
   string want = tag;
   StringToLower(want);
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_TAG, 0, 0, 0, 0, want);
}

void AlgoRuleAdd_OpenGapInfoUnknown(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_OPEN_GAP_UNKNOWN);
}

void AlgoRuleAdd_LevelAbovePDC(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_PDC);
}

void AlgoRuleAdd_LevelAboveIBH(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_IBH);
}

void AlgoRuleAdd_LevelAboveIBL(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_IBL);
}

void AlgoRuleAdd_LevelAboveRTHL(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_LEVEL_ABOVE_RTHL);
}

void AlgoRuleAdd_DayBrokePDLtrue(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_DAY_BROKE_PDL_TRUE);
}

void AlgoRuleAdd_DayOfWeek(const int slotIdx, const int dowSlotMon1Fri5)
{
   BreakdownRuleChainAdd(slotIdx, RULE_DAY_OF_WEEK, dowSlotMon1Fri5);
}

void AlgoRuleAdd_Session(const int slotIdx, const string requiredSession)
{
   BreakdownRuleChainAdd(slotIdx, RULE_SESSION, 0, 0, 0, 0, requiredSession);
}

void AlgoRuleAdd_DayGapDownRequired(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_DAY_GAP_DOWN_REQUIRED);
}

void AlgoRuleAdd_DayGapUpRequired(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_DAY_GAP_UP_REQUIRED);
}

void AlgoRuleAdd_GapRangePtsAbove(const int slotIdx, const double minPtsExclusive)
{
   BreakdownRuleChainAdd(slotIdx, RULE_GAP_RANGE_PTS_ABOVE, 0, 0, minPtsExclusive);
}

void AlgoRuleAdd_GapFillPcBelow(const int slotIdx, const double maxPcExclusive)
{
   BreakdownRuleChainAdd(slotIdx, RULE_GAP_FILL_PC_BELOW, 0, 0, maxPcExclusive);
}

void AlgoRuleAdd_RthoTertiaryReady(const int slotIdx)
{
   BreakdownRuleChainAdd(slotIdx, RULE_RTHO_TERTIARY_READY);
}

//+------------------------------------------------------------------+
string EvalAlgoRule(const int algoId, const AlgoRuleEntry &rule, const int barIdx, const double plannedTradePrice)
{
   switch(rule.rule_id)
   {
      case RULE_CLEAN_STREAK_LONG:
         return GateFail_CleanStreak_Long(barIdx, plannedTradePrice, rule.d0, rule.i0);
      case RULE_CLEAN_STREAK_TOO_LONG:
         return GateFail_CleanStreak_TooLong(barIdx, plannedTradePrice, rule.i0);
      case RULE_ANCHOR_ABOVE_TOO_HIGH:
         return GateFail_AnchorAbove_TooHigh(barIdx, plannedTradePrice, rule.d0);
      case RULE_CLEAN_STREAK_SHORT:
         return GateFail_CleanStreak_Short(barIdx, plannedTradePrice, rule.d0, rule.i0);
      case RULE_BOUNCE_COUNT_TOO_HIGH:
         return GateFail_BounceCount_TooHigh(barIdx, plannedTradePrice, rule.i0);
      case RULE_BOUNCE_COUNT_TOO_LOW:
         return GateFail_BounceCount_TooLow(barIdx, plannedTradePrice, rule.i0);
      case RULE_RECENT_BOUNCE_TOO_HIGH:
         return GateFail_RecentBounceCount_TooHigh(barIdx, plannedTradePrice, rule.i0);
      case RULE_CEILING_COUNT_TOO_HIGH:
         return GateFail_CeilingCount_TooHigh(barIdx, plannedTradePrice, rule.i0, rule.s0);
      case RULE_CEILING_COUNT_TOO_LOW:
         return GateFail_CeilingCount_TooLow(barIdx, plannedTradePrice, rule.i0);
      case RULE_CEILING_PROXIMITY_CANDLES_TOO_HIGH:
         return GateFail_CeilingProximityCandles_TooHigh(barIdx, plannedTradePrice, rule.i0, rule.s0);
      case RULE_TRADES_AT_LEVEL_LIMIT:
         return "";  // level-family only
      case RULE_WEEK_BOUNCE_TOO_HIGH:
         return GateFail_WeekBounceCount_TooHigh(barIdx, plannedTradePrice, rule.i0);
      case RULE_WEEK_BOUNCE_TOO_LOW:
         return GateFail_WeekBounceCount_TooLow(barIdx, plannedTradePrice, rule.i0);
      case RULE_WEEK_CEILING_TOO_HIGH:
         return GateFail_WeekCeilingCount_TooHigh(barIdx, plannedTradePrice, rule.i0);
      case RULE_WEEK_CEILING_TOO_LOW:
         return GateFail_WeekCeilingCount_TooLow(barIdx, plannedTradePrice, rule.i0);
      case RULE_WEEK_CONTACT_CANDLES_TOO_HIGH:
         return GateFail_WeekContactCandles_TooHigh(barIdx, plannedTradePrice, rule.i0);
      case RULE_WEEK_CONTACT_CANDLES_TOO_LOW:
         return GateFail_WeekContactCandles_TooLow(barIdx, plannedTradePrice, rule.i0);
      case RULE_LEVEL_ONO_ABS_DIFF_TOO_LOW:
         return GateFail_LevelOnoAbsDiff_TooLow(plannedTradePrice, rule.d0);
      case RULE_ONO_ABOVE_LEVEL_TOO_LOW:
         return GateFail_ONO_AboveLevel_TooLow(plannedTradePrice, rule.d0);
      case RULE_ONO_BELOW_LEVEL_TOO_LOW:
         return GateFail_ONO_BelowLevel_TooLow(plannedTradePrice, rule.d0);
      case RULE_DAYSTART_EARLIER_WEEK_CONTACT_TOO_HIGH:
         return GateFail_DayStartEarlierWeekContact_TooHigh(plannedTradePrice, rule.i0);
      case RULE_DAY_CONTACT_TODAY_TOO_HIGH:
         return GateFail_DayContactToday_TooHigh(barIdx, plannedTradePrice, rule.i0);
      case RULE_PD_RED:
         return GateFail_PD_red();
      case RULE_PD_GREEN:
         return GateFail_PD_green();
      case RULE_DAY_BROKE_PDL:
         return GateFail_Day_DayBrokePDL(barIdx);
      case RULE_DAY_BROKE_PDH:
         return GateFail_Day_DayBrokePDH(barIdx);
      case RULE_DAY_BROKE_PDH_TRUE:
         return GateFail_Day_DayBrokePDH_true(barIdx);
      case RULE_LEVEL_ABOVE_ONL:
         return GateFail_Level_AboveONL(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_ONL:
         return GateFail_Level_BelowONL(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_ONH:
         return GateFail_Level_BelowONH(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_DAY_HIGH:
         return GateFail_Level_BelowdayHighSoFar(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_DAY_LOW:
         return GateFail_Level_BelowdayLowSoFar(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_PDH:
         return GateFail_Level_BelowPDH(plannedTradePrice);
      case RULE_LEVEL_ABOVE_PDH:
         return GateFail_Level_AbovePDH(plannedTradePrice);
      case RULE_LEVEL_ABOVE_DAY_LOW:
         return GateFail_Level_AbovedayLowSoFar(barIdx, plannedTradePrice);
      case RULE_DAY_LOW_SOFAR_NO_MORE_THAN_X_BELOW_LEVEL:
         return GateFail_DayLowSoFar_NoMoreThanX_BelowLevel(barIdx, plannedTradePrice, rule.d0);
      case RULE_DAY_LOW_SOFAR_AT_LEAST_X_BELOW_LEVEL:
         return GateFail_DayLowSoFar_AtLeastX_BelowLevel(barIdx, plannedTradePrice, rule.d0);
      case RULE_DAY_HIGH_SOFAR_AT_LEAST_X_ABOVE_LEVEL:
         return GateFail_DayHighSoFar_AtLeastX_AboveLevel(barIdx, plannedTradePrice, rule.d0);
      case RULE_DAY_HIGH_SOFAR_NO_MORE_THAN_X_ABOVE_LEVEL:
         return GateFail_DayHighSoFar_NoMoreThanX_AboveLevel(barIdx, plannedTradePrice, rule.d0);
      case RULE_LEVEL_ABOVE_PDL:
         return GateFail_Level_AbovePDL(plannedTradePrice);
      case RULE_LEVEL_BELOW_PDL:
         return GateFail_Level_BelowPDL(plannedTradePrice);
      case RULE_LEVEL_ABOVE_PDC:
         return GateFail_Level_AbovePDC(plannedTradePrice);
      case RULE_LEVEL_BELOW_PDC:
         return GateFail_Level_BelowPDC(plannedTradePrice);
      case RULE_LEVEL_BELOW_PDO:
         return GateFail_Level_BelowPDO(plannedTradePrice);
      case RULE_LEVEL_BELOW_MIDPOINT:
         return GateFail_Level_Belowmidpoint(barIdx, plannedTradePrice);
      case RULE_LEVEL_ABOVE_MIDPOINT:
         return GateFail_Level_Abovemidpoint(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_IBH:
         return GateFail_Level_BelowIBH(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_IBL:
         return GateFail_Level_BelowIBL(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_RTHH:
         return GateFail_Level_BelowRTHH(barIdx, plannedTradePrice);
      case RULE_LEVEL_ABOVE_RTHH:
         return GateFail_Level_AboveRTHH(barIdx, plannedTradePrice);
      case RULE_LEVEL_BELOW_RTHL:
         return GateFail_Level_BelowRTHL(barIdx, plannedTradePrice);
      case RULE_LEVEL_TAG:
         return GateFail_LevelTag(plannedTradePrice, rule.s0);
      case RULE_OPEN_GAP_UNKNOWN:
         return GateFail_OpenGapInfo_Unknown(barIdx);
      case RULE_LEVEL_ABOVE_ONH:
         return GateFail_Level_AboveONH(barIdx, plannedTradePrice);
      case RULE_LEVEL_ABOVE_DAY_HIGH:
         return GateFail_Level_AbovedayHighSoFar(barIdx, plannedTradePrice);
      case RULE_LEVEL_ABOVE_PDO:
         return GateFail_Level_AbovePDO(plannedTradePrice);
      case RULE_LEVEL_ABOVE_IBH:
         return GateFail_Level_AboveIBH(barIdx, plannedTradePrice);
      case RULE_LEVEL_ABOVE_IBL:
         return GateFail_Level_AboveIBL(barIdx, plannedTradePrice);
      case RULE_LEVEL_ABOVE_RTHL:
         return GateFail_Level_AboveRTHL(barIdx, plannedTradePrice);
      case RULE_DAY_BROKE_PDL_TRUE:
         return GateFail_Day_DayBrokePDL_true(barIdx);
      case RULE_DAY_OF_WEEK:
         return GateFail_DayOfWeek(barIdx, rule.i0);
      case RULE_SESSION:
         return GateFail_Session(barIdx, rule.s0);
      case RULE_DAY_GAP_DOWN_REQUIRED:
         return GateFail_Day_GapDownRequired();
      case RULE_DAY_GAP_UP_REQUIRED:
         return GateFail_Day_GapUpRequired();
      case RULE_GAP_RANGE_PTS_ABOVE:
         return GateFail_GapRangePts_Above(rule.d0);
      case RULE_GAP_FILL_PC_BELOW:
         return GateFail_GapFillPc_Below(barIdx, rule.d0);
      case RULE_RTHO_TERTIARY_READY:
         return GateFail_RthoTertiaryLevelReady(barIdx);
   }
   return "unknownRule";
}

//+------------------------------------------------------------------+
string BreakdownRunRulesFirstFail(const int slotIdx, const int barIdx, const datetime evalTime)
{
   if(slotIdx < 0 || slotIdx >= g_breakdownAlgoCount)
      return "unknownAlgo";
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return "invalidBar";
   const double plannedTradePrice = BreakdownPlannedTradePriceAtEval(g_breakdownAlgos[slotIdx].algo_id, barIdx, evalTime);
   for(int r = 0; r < algo.rule_count; r++)
   {
      const string f = EvalAlgoRule(g_breakdownAlgos[slotIdx].algo_id, g_breakdownAlgos[slotIdx].rules[r], barIdx, plannedTradePrice);
      if(f != "")
         return f;
   }
   return "";
}

//+------------------------------------------------------------------+
int BreakdownRunRulesFailCount(const int slotIdx, const int barIdx, const datetime evalTime)
{
   if(slotIdx < 0 || slotIdx >= g_breakdownAlgoCount)
      return 0;
   if(barIdx < 0 || barIdx >= g_barsInDay)
      return 0;
   const double plannedTradePrice = FalgoClosestLevelPriceAtBarForAlgo(g_breakdownAlgos[slotIdx].algo_id, barIdx);
   int failCount = 0;
   for(int r = 0; r < algo.rule_count; r++)
   {
      if(EvalAlgoRule(g_breakdownAlgos[slotIdx].algo_id, g_breakdownAlgos[slotIdx].rules[r], barIdx, plannedTradePrice) != "")
         failCount++;
   }
   return failCount;
}

//+------------------------------------------------------------------+
int AlgoGatesPlacementFailCount(const int algoSlot1, const int barIdx,
   const bool profileEnabled, const bool tradingDay, const bool tradingTime,
   const bool underLoss, const bool underWin,
   const bool noOpen, const bool tradeCloseDedicatedBar, const bool noPending,
   const bool familyBlock, const bool isShortAlgo,
   const string closeVs, const string direction,
   const bool weeklyOK, const bool closestLevelCategoryOK, const bool proxOK,
   const bool bounceOK, const bool ceilingOK, const bool magicFree)
{
   int c = 0;
   if(AlgoFamilyDayStopFirstFailLabel() != "") c++;
   if(!profileEnabled) c++;
   if(!tradingDay) c++;
   if(!tradingTime) c++;
   if(!underLoss) c++;
   if(!underWin) c++;
   if(!noOpen) c++;
   if(tradeCloseDedicatedBar) c++;
   if(!noPending) c++;
   if(familyBlock && FalgoHasOpenPositionOnSymbol()) c++;
   if(familyBlock && FalgoHasPendingOrderOnSymbol()) c++;
   if(closeVs == "no_level") c++;
   if(closeVs == "flat") c++;
   if(!isShortAlgo && closeVs == "below") c++;
   if(isShortAlgo && closeVs == "above") c++;
   if(!weeklyOK) c++;
   if(!proxOK) c++;
   if(!closestLevelCategoryOK) c++;
   const int slotIdx = AlgoSlotIndexByAlgoId(algoSlot1);
   if(direction == "long")
   {
      if(!bounceOK)
      {
         const int ruleFails = BreakdownRunRulesFailCount(slotIdx, barIdx);
         c += (ruleFails > 0 ? ruleFails : 1);
      }
   }
   else if(direction == "short")
   {
      if(!ceilingOK)
      {
         const int ruleFails = BreakdownRunRulesFailCount(slotIdx, barIdx);
         c += (ruleFails > 0 ? ruleFails : 1);
      }
   }
   if((direction == "long" || direction == "short") && !magicFree)
      c++;
   return c;
}

//+------------------------------------------------------------------+
void BreakdownRebuildRuleChainForSlot(const int slotIdx)
{
   if(slotIdx < 0 || slotIdx >= g_breakdownAlgoCount)
      return;
   const int algoId = g_breakdownAlgos[slotIdx].algo_id;
   const AlgoDef a = g_breakdownAlgos[slotIdx];
   BreakdownRuleChainClear(slotIdx);
   switch(algoId)
   {
      // algobookmark breakdown rules
//breakdowncreator4start
      case MAGIC_BREAKDOWN20000000:
         // wire breakdown gates vs planned trade price here (BreakdownRuleAdd_*)
         break;
//breakdowncreator4end
      default:

         break;
   }
}

//+------------------------------------------------------------------+
void BreakdownRebuildAllRuleChains()
{
   for(int i = 0; i < g_breakdownAlgoCount; i++)
      BreakdownRebuildRuleChainForSlot(i);
}

//+------------------------------------------------------------------+
int AlgoFamilyRecentBounceLookbackMinutes()
{
   int maxMin = 0;
   for(int i = 0; i < g_breakdownAlgoCount; i++)
   {
      if(g_breakdownAlgos[i].recentBounceCountToday_Minutes > maxMin)
         maxMin = g_breakdownAlgos[i].recentBounceCountToday_Minutes;
   }
   return maxMin;
}

//+------------------------------------------------------------------+
int AlgoFamilyRecentCeilingLookbackMinutes()
{
   int maxMin = 0;
   for(int i = 0; i < g_breakdownAlgoCount; i++)
   {
      if(g_breakdownAlgos[i].recentCeilingCountToday_Minutes > maxMin)
         maxMin = g_breakdownAlgos[i].recentCeilingCountToday_Minutes;
   }
   return maxMin;
}

