require 'csv'
require 'set'

# List of magic numbers to encode (excluding last 4 digits)
fullmagic_to_encode = <<~TEXT
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
15223340057000606
15228340057000606
15229340057000606
15273340107000606
15282340157000606
16215340107000606
16221340107000606
16222340107000606
15446240107000606
16403240107000606
16407240107000606
15245240157000606
15266240157000606
15232240157000606
15244240107000606
16211340037000606
15230240107000606
15223340037000606
15228340037000606
15229340037000606
16220340037000606
15276340037000606
15280340157000606
15288340157000606
15290340157000606
15202340157000606
16208340157000606
16230340157000606
15224340057000606
15263240107000606
15218240107000606
15270340157000606
16204340157000606
15275340157000606
15352370307000606
15357370307000606
15377370307000606
15382370307000606
16216340107000606
15203340107000606
16210340107000606
16232340107000606
15219240157000606
15237240157000606
15253240157000606
15241240157000606
15258240157000606
15275340107000606
15224340037000606
16257440107000606
15204340107000606
16211340107000606
15223240157000606
15224240157000606
15228240157000606
15229240157000606
15218340037000606
15245240107000606
15266240107000606
15218340057000606
16216340157000606
15201340157000606
16215340157000606
16221340157000606
16222340157000606
16207340157000606
16229340157000606
15437240107000606
15442240107000606
15202340107000606
16208340107000606
16230340107000606
15103370157001206
15106370157001206
15109370157001206
15112370157001206
15203340157000606
16210340157000606
16232340157000606
15302370307000606
15307370307000606
15312370307000606
15317370307000606
15362370307000606
15367370307000606
15387370307000606
15392370307000606
TEXT

# Arrays for TP and SL values
tp = ["06", "08", "10", "12", "14"].uniq   # Possible TP values
sl = ["06","04", "10"].uniq # "08"  #   # Possible SL values
excluded_combinations_last_4_digits = ["1404", "1204"] # exclude the ones too extreme IMO

# Indexing constants
TRADE_INDEX_START = 0
ENABLED    = true
TRADE_SIZE = 100

# ================== BUILD FULL MAGIC NUMBERS ==================

# Remove the last 4 digits from each magic number
base_magics = fullmagic_to_encode.lines.map do |line|
  line.strip[0..12]  # Keeps the first 13 digits, removing the last 4 digits
end

# Build combinations of TP and SL for each base magic number
MAGIC_NUMBERS = []

base_magics.each do |base|
  tp.each do |tpv|
    sl.each do |slv|
      MAGIC_NUMBERS << "#{base}#{tpv}#{slv}" # Concatenate base magic with TP and SL values
    end
  end
end

# ================== HELPERS ==================

# Helper method to parse magic numbers
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

# ================== BUILD OUTPUT ==================

filtered_magic_numbers = MAGIC_NUMBERS.reject do |magic|
  excluded_combinations_last_4_digits.include?(magic[-4..-1])
end


# final_magics = MAGIC_NUMBERS
final_magics = filtered_magic_numbers

all_output = []
blocks = []

final_magics.each_with_index do |magic, i|
  data = parse_magic(magic)
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
  block << "g_trade[#{idx}].bannedRanges             = \"22,0,23,59;0,0,1,0\";"
  block << "g_trade[#{idx}].levelProximityFocus      = #{level_focus(data[:direction])};"

  blocks << block.join("\n")
end

all_output += blocks

# ================== WRITE OUTPUT ==================

File.write("ZQUANT2_3_quant_encoder_TPSLtests_output.txt", all_output.join("\n"))

# ================== CONSOLE ==================

puts "\n=== PREVIEW (FIRST BLOCK) ==="
puts blocks.first

puts "\n=== PREVIEW (LAST BLOCK) ==="
puts blocks.last
puts "\nTotal trade blocks generated: #{blocks.size}"
puts "\n(full output saved to ZQUANT2_3_quant_encoder_TPSLtests_output.txt)"