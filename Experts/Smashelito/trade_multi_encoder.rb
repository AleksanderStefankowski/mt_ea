# ================== CONFIG (EDIT HERE) ==================

set_4_context =          true

set_ruleset =            false
set_ruleset_input = '13'

set_1st_digit_flipper =  false # true
set_1st_digit = 2

TRADE_INDEX_START = 0
#                 DttSScPPofBBBtpSL    DttSScPPofBBBtpSL    DttSScPPofBBBtpSL    DttSScPPofBBBtpSL

# MAGIC_NUMBERS = [
#   "10233340037000606", "10244440037000606", "10241240157000606", "10230240037000606", "10216140057000606", "10258440157000606",
#   "10234440057000606", "10202140037000606", "10249440107000606", "10266140157000606", "10264140037000606", "10204140057000606",
#   "10229440157000606", "10219340157000606", "10248440157000606", "10265440037000606"
# ]


numbers_text = <<~TEXT
15274340057000606
16262240157000606
15274340157000606
16257440057000606
16257440037000606
16208440057000606
16230440057000606
16208440037000606
16230440037000606
15201340057000606
16229340057000606
16215340037000606
16221340037000606
16222340037000606
16229340037000606
16215340057000606
16221340057000606
16222340057000606
16256440037000606
15273340157000606
16256440057000606
16214340057000606
16220340057000606
16216340057000606
16232340057000606
16256340107000606
16271340107000606
15202340037000606
16208340037000606
16230340037000606
15280340037000606
15288340037000606
15290340037000606
15201340107000606
16207340107000606
16229340107000606
15244240157000606
16211340057000606
15230240157000606
15276340057000606
16208340057000606
16230340057000606
16256340057000606
16271340057000606
15274340037000606
15263240157000606
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


# ================== HELPERS ==================

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

def apply_4_context(magic_list, enabled)
  return magic_list unless enabled && magic_list.length == 4

  magic_list.each_with_index.map do |m, i|
    m = m.to_s.dup
    m[5] = (i + 1).to_s
    m
  end
end

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

def apply_1st_digit_flipper(magic_list, enabled, digit)
  return magic_list unless enabled

  magic_list.map do |m|
    m = m.to_s.dup
    m[0] = digit.to_s
    m
  end
end

# ================== BUILD ==================

final_magics = MAGIC_NUMBERS
final_magics = apply_ruleset(final_magics, set_ruleset, set_ruleset_input)
final_magics = apply_4_context(final_magics, set_4_context)
final_magics = apply_1st_digit_flipper(final_magics, set_1st_digit_flipper, set_1st_digit)

all_output = []
blocks = []

final_magics.each_with_index do |magic, i|
  data = parse_magic(magic)
  babysit_enabled, babysit_minute = parse_babysit(data[:babysit_raw])
  idx = TRADE_INDEX_START + i

  block = []
  block << "\n// encoding input magic: #{magic}"
  block << "g_trade[#{idx}].enabled                  = #{ENABLED};"
  block << "g_trade[#{idx}].tradeDirectionCategory   = #{direction_to_enum(data[:direction])};"
  block << "g_trade[#{idx}].tradeTypeId              = #{data[:type_id]};"
  block << "g_trade[#{idx}].ruleSubsetId             = #{data[:subset_id]};"
  block << "g_trade[#{idx}].sessionPdCategory        = #{session_to_enum(data[:session])};"
  block << "g_trade[#{idx}].tradeSizePct             = #{TRADE_SIZE};"
  block << "g_trade[#{idx}].tpPoints                 = #{data[:tp]};"
  block << "g_trade[#{idx}].slPoints                 = #{data[:sl]};"
  block << "g_trade[#{idx}].livePriceDiffTrigger     = #{data[:price_prox]};"
  block << "g_trade[#{idx}].levelOffsetPoints        = #{data[:level_offset]};"
  block << "g_trade[#{idx}].bannedRanges             = \"22,0,23,59;0,0,1,0\";" # = \"21,15,23,59;0,0,1,0\";"
  block << "g_trade[#{idx}].levelProximityFocus      = #{level_focus(data[:direction])};"
  block << "g_trade[#{idx}].babysit_enabled          = #{babysit_enabled};"
  block << "g_trade[#{idx}].babysitStart_minute      = #{babysit_minute};"

  blocks << block.join("\n")
end

all_output += blocks

# ================== WRITE FULL OUTPUT ==================

File.write("trade_multi_encoder_output.txt", all_output.join("\n"))

# ================== CONSOLE (ONLY FIRST + LAST) ==================

puts "\n=== PREVIEW (FIRST BLOCK) ==="
puts blocks.first

puts "\n=== PREVIEW (LAST BLOCK) ==="
puts blocks.last
puts "\nTotal trade blocks generated: #{blocks.size}"
puts "\n(full output saved to trade_multi_encoder_output)"