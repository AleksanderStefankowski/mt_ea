# example:
# DttSScPPofBBBtpSL
# 20141435257000606

d  = "2"
tt = "01"
ss = ["01", "13", "12"]
c  = ["1", "2", "3", "4"]
pp = "30"
of = ["05", "03"]
bbb = "812"
tp = ["05", "07"]
sl = ["03", "05"]

# Generate all combinations
combinations = ss.product(c, of, tp, sl).map do |s, c_val, of_val, tp_val, sl_val|
  "#{d}#{tt}#{s}#{c_val}#{pp}#{of_val}#{bbb}#{tp_val}#{sl_val}"
end

puts "\nTotal combinations: #{combinations.size}"

TRADE_INDEX_START = 25
MAGIC_NUMBERS = combinations
ENABLED      = true
TRADE_SIZE   = 100

OUTPUT_FILE = File.join(__dir__, "trade_giga_encode_output.txt")

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

# Collect all output into buffer
output_lines = []

MAGIC_NUMBERS.each_with_index do |magic, i|
  idx = TRADE_INDEX_START + i

  # Parse encoded string: DttSScPPofBBBtpSL
  direction    = magic[0].to_i
  type_id      = magic[1..2].to_i
  subset_id    = magic[3..4].to_i
  session      = magic[5].to_i
  price_prox   = magic[6..7].to_i / 10.0
  level_offset = magic[8..9].to_i / 10.0
  bbb_val      = magic[10..12]
  tp_val       = magic[13..14].to_i.to_f
  sl_val       = magic[15..16].to_i.to_f

  # Babysit logic
  babysit_enabled = (bbb_val[0] == "8")
  babysit_minute  = bbb_val[1..2].to_i

  block = []
  block << "// encoding input magic: #{magic}"
  block << "g_trade[#{idx}].enabled                  = #{ENABLED};"
  block << "g_trade[#{idx}].tradeDirectionCategory   = #{direction_to_enum(direction)};"
  block << "g_trade[#{idx}].tradeTypeId              = #{type_id};"
  block << "g_trade[#{idx}].ruleSubsetId             = #{subset_id};"
  block << "g_trade[#{idx}].sessionPdCategory        = #{session_to_enum(session)};"
  block << "g_trade[#{idx}].tradeSizePct             = #{TRADE_SIZE};"
  block << "g_trade[#{idx}].tpPoints                 = #{tp_val};"
  block << "g_trade[#{idx}].slPoints                 = #{sl_val};"
  block << "g_trade[#{idx}].livePriceDiffTrigger     = #{price_prox};"
  block << "g_trade[#{idx}].levelOffsetPoints        = #{level_offset};"
  block << "g_trade[#{idx}].levelProximityFocus      = #{level_focus(direction)};"
  block << 'g_trade[' + idx.to_s + '].bannedRanges = "22,0,23,59;0,0,1,0";'
  block << "g_trade[#{idx}].babysit_enabled          = #{babysit_enabled};"
  block << "g_trade[#{idx}].babysitStart_minute      = #{babysit_minute};"
  block << "\n"

  output_lines << block.join("\n")
end

# Write ALL to file (overwrite mode)
File.write(OUTPUT_FILE, output_lines.join("\n"))

# Print ONLY first one to console
puts "\n--- Example output (first config only) ---"
puts output_lines.first

puts "\nAll #{output_lines.size} configs saved to #{File.basename(OUTPUT_FILE)}"