# ================== CONFIG (EDIT HERE) ==================
#               DttSScPPofBBBtpSL
MAGIC_NUMBER = "40102230267000808"
TRADE_INDEX  = 35


ENABLED      = true
TRADE_SIZE   = 100
# =======================================================

=begin
//+------------------------------------------------------------------+
//| Composite magic — 17 decimal digits concatenated (no | in stored value). Bookmark2. |
//| Layout (width = repeat slot index; not example values): 1|22|33|4|55|66||777|88|99 — 17 digits; “||” is doc-only (not in stored magic). |
//| Slot 1 (1 digit) — g_trade[].tradeDirectionCategory / PlacePendingFromMagic (MAGIC_TRADE_*), must be 1..4: |
//|   1 = MAGIC_TRADE_LONG           → buy limit pending. |
//|   2 = MAGIC_TRADE_SHORT          → sell limit pending. |
//|   3 = MAGIC_TRADE_LONG_REVERSED  → sell stop (reversed long); entry −s; SL/TP from fill; see PlaceSellStopAtLevel. |
//|   4 = MAGIC_TRADE_SHORT_REVERSED → buy stop (reversed short); entry +s; SL/TP from fill; see PlaceBuyStopAtLevel. |
//| Slot 2 (22): tradeTypeId as %02d, 01..99 (variant row id / config grouping). |
//| Slot 3 (33): ruleSubsetId as %02d, 01..99 (stage-2 subset dispatch with slot 1+2 → BuildStage2SubsetHandlerKeyFromFullMagic). |
//| Slot 4 (4) — one digit: g_trade[].sessionPdCategory (MAGIC_IS_*), must be 1..4 — session band vs prior-day colour: |
//|   1 = MAGIC_IS_ON_AND_PD_GREEN   |
//|   2 = MAGIC_IS_ON_AND_PD_RED     |
//|   3 = MAGIC_IS_RTH_AND_PD_GREEN  |
//|   4 = MAGIC_IS_RTH_AND_PD_RED    |
//| Slot 5 (55): live proximity — %02d tenths (0.1..9.9). |
//| Slot 6 (66): level offset pips — %02d tenths (0.1..9.9). |
//| Slot 7 (777): babysit |
//| Slot 8 (88): TP pips |
//| Slot 9 (99): SL pips |
//+------------------------------------------------------------------+
=end


# --- PARSE MAGIC ---
def parse_magic(m)
  raise "Magic must be 17 digits" unless m.length == 17

  {
    direction: m[0].to_i,
    type_id: m[1..2].to_i,
    subset_id: m[3..4].to_i,
    session: m[5].to_i,
    price_prox: m[6..7].to_i / 10.0,
    level_offset: m[8..9].to_i / 10.0,
    babysit_raw: m[10..12],
    tp: m[13..14].to_i.to_f,
    sl: m[15..16].to_i.to_f
  }
end

# --- MAPPINGS ---
def direction_to_enum(val)
  case val
  when 1 then "MAGIC_TRADE_LONG"
  when 2 then "MAGIC_TRADE_SHORT"
  when 3 then "MAGIC_TRADE_LONG_REVERSED"
  when 4 then "MAGIC_TRADE_SHORT_REVERSED"
  else "UNKNOWN"
  end
end

def session_to_enum(val)
  case val
  when 1 then "MAGIC_IS_ON_AND_PD_GREEN"
  when 2 then "MAGIC_IS_ON_AND_PD_RED"
  when 3 then "MAGIC_IS_RTH_AND_PD_GREEN"
  when 4 then "MAGIC_IS_RTH_AND_PD_RED"
  else "UNKNOWN"
  end
end

def level_focus(direction)
  case direction
  when 1, 3 then "TRADE_LEVEL_FOCUS_BELOW"
  when 2, 4 then "TRADE_LEVEL_FOCUS_ABOVE"
  else "UNKNOWN"
  end
end

def parse_babysit(raw)
  val = raw.to_i
  if val >= 800
    return true, val - 800
  else
    return false, 0
  end
end

# --- BUILD OUTPUT ---
data = parse_magic(MAGIC_NUMBER)

babysit_enabled, babysit_minute = parse_babysit(data[:babysit_raw])

idx = TRADE_INDEX
puts "\n"
puts "// encoding input magic: #{MAGIC_NUMBER}"
puts "g_trade[#{idx}].enabled                  = #{ENABLED};"
puts "g_trade[#{idx}].tradeDirectionCategory   = #{direction_to_enum(data[:direction])};"
puts "g_trade[#{idx}].tradeTypeId              = #{data[:type_id]};"
puts "g_trade[#{idx}].ruleSubsetId             = #{data[:subset_id]};"
puts "g_trade[#{idx}].sessionPdCategory        = #{session_to_enum(data[:session])};"
puts "g_trade[#{idx}].tradeSizePct             = #{TRADE_SIZE};"
puts "g_trade[#{idx}].tpPoints                 = #{data[:tp]};"
puts "g_trade[#{idx}].slPoints                 = #{data[:sl]};"
puts "g_trade[#{idx}].livePriceDiffTrigger     = #{data[:price_prox]};"
puts "g_trade[#{idx}].levelOffsetPoints        = #{data[:level_offset]};"
puts "g_trade[#{idx}].levelProximityFocus      = #{level_focus(data[:direction])};"
puts 'g_trade[' + idx.to_s + '].bannedRanges = "22,0,23,59;0,0,1,0";'
puts "g_trade[#{idx}].babysit_enabled          = #{babysit_enabled};"
puts "g_trade[#{idx}].babysitStart_minute      = #{babysit_minute};"
puts "\n"