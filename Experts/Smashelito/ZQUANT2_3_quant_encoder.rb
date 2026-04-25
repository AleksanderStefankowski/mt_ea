SMASHELITO_FILE = "smashelito.mq5"

SUBSET_START = "// quantspace2SubsetStart"
SUBSET_END   = "// quantspace2SubsetEnd"

babysit = "700"
tp = ["06"].uniq # "08"
sl = ["06"].uniq

TRADE_INDEX_START = 0

ENABLED    = true
TRADE_SIZE = 100

# ================== EXTRACT PARTIAL MAGICS ==================

def extract_partial_magics(file)
  lines = File.readlines(file, encoding: "utf-8")

  inside = false
  partials = []

  lines.each do |line|
    if line.include?(SUBSET_START)
      inside = true
      next
    end

    if line.include?(SUBSET_END)
      inside = false
      next
    end

    next unless inside

    if line =~ /Subset_(\d+)/
      partials << $1
    end
  end

  partials.uniq
end

# ================== BUILD FULL MAGIC NUMBERS ==================

partials = extract_partial_magics(SMASHELITO_FILE)

# attach babysit
base_magics = partials.map { |p| p + babysit }

# build combinations
MAGIC_NUMBERS = []

base_magics.each do |base|
  tp.each do |tpv|
    sl.each do |slv|
      MAGIC_NUMBERS << "#{base}#{tpv}#{slv}"
    end
  end
end

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

# ================== BUILD OUTPUT ==================

final_magics = MAGIC_NUMBERS

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
  block << "g_trade[#{idx}].bannedRanges             = \"22,0,23,59;0,0,1,0\";"
  block << "g_trade[#{idx}].levelProximityFocus      = #{level_focus(data[:direction])};"
  block << "g_trade[#{idx}].babysit_enabled          = #{babysit_enabled};"
  block << "g_trade[#{idx}].babysitStart_minute      = #{babysit_minute};"

  blocks << block.join("\n")
end

all_output += blocks

# ================== WRITE OUTPUT ==================

File.write("ZQUANT2_3_quant_encoder_output.txt", all_output.join("\n"))

# ================== CONSOLE ==================

puts "\n=== PREVIEW (FIRST BLOCK) ==="
puts blocks.first

puts "\n=== PREVIEW (LAST BLOCK) ==="
puts blocks.last
puts "\nTotal trade blocks generated: #{blocks.size}"
puts "\n(full output saved to ZQUANT2_3_quant_encoder_output.txt)"