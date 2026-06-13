require "csv"
require "set"
# DttSScPPofBBBtpSL
# 40190430037001206

TRADE_INDEX_START = 0

# --- INPUT DATA ---
numbers_text = <<~TEXT
magic	profit_factor
40188430107001204	2.88
20114230057001204	3.01
20115430107000806	3.03
20117430107000806	3.03
20261430157001206	3.07
20132430157001004	3.16
40190130107000606	3.19
20115430157000804	3.34
20117430157000804	3.34
40188430157001004	3.64
20115330107000606	4.01
20117330107000606	4.01
20186430037000806	4.15
20115330057000804	4.27
20117330057000804	4.27
20186430057000806	4.29
20115230037000804	4.62
20117230037000804	4.62
20115230057000604	4.63
20117230057000604	4.63
20115430037000806	4.78
20117430037000806	4.78
20115230107000604	4.78
20117230107000604	4.78
20261430107001206	4.9
20115430057000806	5.02
20117430057000806	5.02
20114330157000606	5.09
20114330107000606	5.17
20115230157001206	5.35
20117230157001206	5.35
20202130157000606	6.26
20203130157000606	6.26
20202330157000606	6.77
20202330107000606	7.08
20118330057000804	8.17
20261430057001206	8.19
20114330037000804	8.23
20116430107001206	8.29
20203330107000604	8.78
20116430157001206	8.96
20114330057000804	10.22
20185430157001004	11.66
20114430037001206	12.39
20261430037000806	12.68
20114430057001206	12.9
20114430107001206	14.4
20114430157001206	15.64
40190430037001206	Infinity
40190430057001204	Infinity
40190430107000804	Infinity
40188130157001204	Infinity
40188130107001204	Infinity
40188130057001004	Infinity
20187230157000606	Infinity
20187230107000606	Infinity
TEXT

# --- PARSE INPUT CORRECTLY ---
MAGIC_ROWS = CSV.parse(numbers_text, headers: true, col_sep: "\t").map do |row|
  {
    magic: row["magic"],
    pf: row["profit_factor"]
  }
end

# --- CONFIG ---
ENABLED = true

# --- TRADE SIZE FROM PF ---
def trade_size_from_pf(pf_raw)
  pf = (pf_raw == "Infinity") ? Float::INFINITY : pf_raw.to_f

  if pf > 12
    100
  elsif pf >= 10
    100
  elsif pf >= 8
    90 # 90
  elsif pf >= 6 # like 6.5, 7.9
    70 # 70
  elsif pf >= 4 # like 5.5
    50 # 50
  elsif pf >= 2.5 # like 2.8
    30 # 30
  else
    20
  end
end

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

# --- BUILD FINAL MAGIC LIST ---
final_magics = MAGIC_ROWS.map { |r| r[:magic] }

final_magics.each_with_index do |magic, i|
  data = parse_magic(magic)
  babysit_enabled, babysit_minute = parse_babysit(data[:babysit_raw])

  idx = TRADE_INDEX_START + i
  pf  = MAGIC_ROWS[i][:pf]
  trade_size = trade_size_from_pf(pf)

  puts "\n"
  puts "// encoding input magic: #{magic} | pf=#{pf}"
  puts "g_trade[#{idx}].enabled                  = #{ENABLED};"
  puts "g_trade[#{idx}].tradeDirectionCategory   = #{direction_to_enum(data[:direction])};"
  puts "g_trade[#{idx}].tradeTypeId              = #{data[:type_id]};"
  puts "g_trade[#{idx}].ruleSubsetId             = #{data[:subset_id]};"
  puts "g_trade[#{idx}].sessionPdCategory        = #{session_to_enum(data[:session])};"
  puts "g_trade[#{idx}].tradeSizePct             = #{trade_size};"
  puts "g_trade[#{idx}].tpPoints                 = #{data[:tp]};"
  puts "g_trade[#{idx}].slPoints                 = #{data[:sl]};"
  puts "g_trade[#{idx}].livePriceDiffTrigger     = #{data[:price_prox]};"
  puts "g_trade[#{idx}].levelOffsetPoints        = #{data[:level_offset]};"
  puts "g_trade[#{idx}].levelProximityFocus      = #{level_focus(data[:direction])};"
  puts 'g_trade[' + idx.to_s + '].bannedRanges = "21,15,23,59;0,0,1,0";'
  puts "g_trade[#{idx}].babysit_enabled          = #{babysit_enabled};"
  puts "g_trade[#{idx}].babysitStart_minute      = #{babysit_minute};"
  puts "\n"
end