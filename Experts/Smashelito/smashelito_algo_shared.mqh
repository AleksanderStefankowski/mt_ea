//+------------------------------------------------------------------+
//| smashelito_algo_shared.mqh — shared algo family (5..9): magic, logs, helpers |
//+------------------------------------------------------------------+
#ifndef SMASHELITO_ALGO_SHARED_MQH
#define SMASHELITO_ALGO_SHARED_MQH

#define MAGIC_ALGO5_SLOT1           5   // long1
#define MAGIC_ALGO6_SLOT1           6   // long2
#define MAGIC_ALGO7_SLOT1           7   // short1
#define MAGIC_ALGO8_SLOT1           8   // reserved
#define MAGIC_ALGO9_SLOT1           9   // reserved
#define MAGIC_ALGO_FAMILY_SLOT_MIN  MAGIC_ALGO5_SLOT1
#define MAGIC_ALGO_FAMILY_SLOT_MAX  MAGIC_ALGO9_SLOT1
#define ALGO_FAMILY_SLOT_COUNT      (MAGIC_ALGO_FAMILY_SLOT_MAX - MAGIC_ALGO_FAMILY_SLOT_MIN + 1)

//+------------------------------------------------------------------+
int AlgoFamilySlotArrayIndex(const int algoSlot1)
{
   if(algoSlot1 < MAGIC_ALGO_FAMILY_SLOT_MIN || algoSlot1 > MAGIC_ALGO_FAMILY_SLOT_MAX)
      return -1;
   return algoSlot1 - MAGIC_ALGO_FAMILY_SLOT_MIN;
}

//+------------------------------------------------------------------+
int AlgoFamilyMagicSlot1(const long magic)
{
   string s = MagicNumberToFixedWidthString(magic);
   if(StringLen(s) < 1)
      return -1;
   return (int)StringToInteger(StringSubstr(s, 0, 1));
}

//+------------------------------------------------------------------+
bool IsAlgoCompositeMagicSlot1(const long magic, const int algoSlot1)
{
   return (AlgoFamilyMagicSlot1(magic) == algoSlot1);
}

//+------------------------------------------------------------------+
bool IsAnyAlgoFamilyCompositeMagic(const long magic)
{
   const int slot = AlgoFamilyMagicSlot1(magic);
   return (slot >= MAGIC_ALGO_FAMILY_SLOT_MIN && slot <= MAGIC_ALGO_FAMILY_SLOT_MAX);
}

//+------------------------------------------------------------------+
bool IsFalgo5CompositeMagicSlot1(const long magic) { return IsAlgoCompositeMagicSlot1(magic, MAGIC_ALGO5_SLOT1); }
bool IsAlgo5CompositeMagicSlot1(const long magic) { return IsFalgo5CompositeMagicSlot1(magic); }
bool IsAlgo6CompositeMagicSlot1(const long magic) { return IsAlgoCompositeMagicSlot1(magic, MAGIC_ALGO6_SLOT1); }
bool IsAlgo7CompositeMagicSlot1(const long magic) { return IsAlgoCompositeMagicSlot1(magic, MAGIC_ALGO7_SLOT1); }

//+------------------------------------------------------------------+
//| (date)_algo{N}_{suffix}.csv — e.g. 20260511_algo5_gates_per_minute.csv |
//+------------------------------------------------------------------+
string AlgoFamilyCsvFileName(const string dateStr, const int algoSlot1, const string suffix)
{
   return dateStr + "_algo" + IntegerToString(algoSlot1) + "_" + suffix + ".csv";
}

#endif
