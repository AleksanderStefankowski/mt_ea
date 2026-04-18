# ================== CONFIG (EDIT HERE) ==================

set_4_context =          true

set_ruleset =            false
set_ruleset_input = '13'

set_1st_digit_flipper =  false # true
set_1st_digit = 2

TRADE_INDEX_START = 0
#                 DttSScPPofBBBtpSL    DttSScPPofBBBtpSL    DttSScPPofBBBtpSL    DttSScPPofBBBtpSL
# MAGIC_NUMBERS = [
#   "40190130107000604", "40188130057000804", "20187330057000604", "20117330057000804", "20118330057000804",
#   "20114430107000806", "20115430107000804", "20132430057000806", "20186430057000806", "40211230057000606",
#   "20116330107000606", "20119330057000606", "40189130057000806", "20261430057000806", "20185430057000806",
#   "20203330107000604", "20220330107000604", "20204330057000604", "20260330107000604", "20262330107000606",
#   "20202330107000606", "40191130107000606", "40191130107000806", 
# ]

numbers_text = <<~TEXT
10266440037000606
10209440157000606

TEXT
MAGIC_NUMBERS = numbers_text.lines.map(&:chomp)



ENABLED      = true
TRADE_SIZE   = 100
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
//| Slot 6 (66): level offset points — %02d tenths (0.1..9.9). |
//| Slot 7 (777): babysit |
//| Slot 8 (88): TP points |
//| Slot 9 (99): SL points |
//+------------------------------------------------------------------+
=end
# --- PARSE MAGIC ---
def parse_magic(m)
  m = m.to_s
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

# --- APPLY CONTEXT OVERRIDE ---
def apply_4_context(magic_list, enabled)
  return magic_list unless enabled && magic_list.length == 4

  magic_list.each_with_index.map do |m, i|
    m = m.to_s.dup
    m[5] = (i + 1).to_s
    m
  end
end

# --- APPLY RULESET OVERRIDE ---
def apply_ruleset(magic_list, enabled, input)
  return magic_list unless enabled

  raise "ruleset input must be 2 digits" unless input.to_s.length == 2

  magic_list.map do |m|
    m = m.to_s.dup
    m[3] = input[0]
    m[4] = input[1]
    m
  end
end

# --- APPLY 1ST DIGIT FLIPPER ---
def apply_1st_digit_flipper(magic_list, enabled, digit)
  return magic_list unless enabled

  magic_list.map do |m|
    m = m.to_s.dup
    m[0] = digit.to_s
    m
  end
end

# --- BUILD OUTPUT ---


final_magics = MAGIC_NUMBERS
final_magics = apply_ruleset(final_magics, set_ruleset, set_ruleset_input)
final_magics = apply_4_context(final_magics, set_4_context)
final_magics = apply_1st_digit_flipper(final_magics, set_1st_digit_flipper, set_1st_digit)

print "\n"
print final_magics
print "\n"

final_magics.each_with_index do |magic, i|
  data = parse_magic(magic)
  babysit_enabled, babysit_minute = parse_babysit(data[:babysit_raw])

  idx = TRADE_INDEX_START + i

  puts "\n"
  puts "// encoding input magic: #{magic}"
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
end