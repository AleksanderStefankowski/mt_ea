# example:
# DttSScPPofBBBtpSL
# 20141435257000606

=begin trade_db_reader.rb :
=end

=begin output of read smashelito (smash_mql5_reader_Functions_read_subsets_For_GigaEncoder)
=== GROUPED (last 2 digits) BY FIRST 3 DIGITS ===
Group 102: ["01", "02", "03", "04", "05", "06", "07", "08"]
Group 201: ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "12", "13", "14", "21", "31", "41"]
Group 202: ["01", "10", "20", "30", "40", "50", "60", "70"]
Group 203: ["01", "10", "20", "30"]
Group 204: ["01", "10", "20", "30", "40"]
Group 401: ["92", "93", "94", "95", "96", "97", "98", "99"]
=end

=begin output of read smashelito trades-only (smash_mql5_reader_Functions_read_subsets_For_GigaEncoder_BUT_read_only_from_trades_for_testing_TPSL_offset_etc)
=== GROUPED (last 2 digits) BY FIRST 3 DIGITS ===
Group 201: ["14", "15", "16", "17", "18", "19", "32", "85", "86", "87"]
Group 202: ["02", "03", "04", "20", "60", "61", "62"]
Group 401: ["88", "89", "90", "91"]
Group 402: ["11"]
=end

text = <<~TEXT
Group 201: ["14", "15", "16", "17", "18", "19", "32", "85", "86", "87"]
Group 202: ["02", "03", "04", "20", "60", "61", "62"]
Group 401: ["88", "89", "90", "91"]
Group 402: ["11"]
TEXT

TRADE_INDEX_START = 0
ENABLED    = true
TRADE_SIZE = 100

c   = ["1", "2", "3", "4"].uniq
pp  = "30"
of  = ["05", "10", "03", "15"] # I removed 15 (1.5 offset) as shorts should be tight? let's see result
bbb = "700"
tp  = ["06", "08", "10", "12"].uniq
sl  = ["06", "04"].uniq

all_combinations = []

# -------------------------------
# PARSE GROUPS
# -------------------------------
text.each_line do |line|
  next if line.strip.empty?

  match = line.match(/Group\s+(\d+):\s+(\[.*\])/)
  next unless match

  group_id = match[1]          # "202"
  ss       = eval(match[2])    # ["01", "10", ...]

  d  = group_id[0]             # first digit
  tt = group_id[1..2]          # second + third digits

  combinations = ss.product(c, of, tp, sl).map do |s, c_val, of_val, tp_val, sl_val|
    "#{d}#{tt}#{s}#{c_val}#{pp}#{of_val}#{bbb}#{tp_val}#{sl_val}"
  end

  all_combinations.concat(combinations)
end

# -------------------------------
# FINAL SET
# -------------------------------
MAGIC_NUMBERS = all_combinations.uniq

puts "\nTotal final combinations: #{MAGIC_NUMBERS.size}"

OUTPUT_FILE = File.join(__dir__, "trade_giga_encoder2_output.txt")

# -------------------------------
# ENUM HELPERS
# -------------------------------
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

# -------------------------------
# BUILD OUTPUT
# -------------------------------
output_lines = []

MAGIC_NUMBERS.each_with_index do |magic, i|
  idx = TRADE_INDEX_START + i

  direction    = magic[0].to_i
  type_id      = magic[1..2].to_i
  subset_id    = magic[3..4].to_i
  session      = magic[5].to_i
  price_prox   = magic[6..7].to_i / 10.0
  level_offset = magic[8..9].to_i / 10.0
  bbb_val      = magic[10..12]
  tp_val       = magic[13..14].to_i.to_f
  sl_val       = magic[15..16].to_i.to_f

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

# -------------------------------
# WRITE FILE
# -------------------------------
File.write(OUTPUT_FILE, output_lines.join("\n"))

puts "\n--- Example output (first config only) ---"
puts output_lines.first

puts "\nAll #{output_lines.size} configs saved to #{File.basename(OUTPUT_FILE)}"