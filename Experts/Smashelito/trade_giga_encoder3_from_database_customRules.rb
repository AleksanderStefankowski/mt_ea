=begin
do not remove comments. this script is:
C:\Users\Aleks\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856\MQL5\Experts\Smashelito\trade_giga_encoder3_from_database_customRules
I launch it like:  
ruby .\trade_giga_encoder3_from_database_customRules.rb 
it should read db:  
  C:\Users\Aleks\AppData\Roaming\MetaQuotes\Tester\47AEB69EDDAD4D73097816C71FB25856\Agent-127.0.0.1-3000\MQL5\trade_database.tsv

inside db, data is like:
magic	magic_type	olekcomment	reversedMagic	type_id	subset_id	set_dirTTsubset	set_TTsubsetSPD	set_dirTTsubsetSPD	session_pd	price_proximity	level_offsets	babysit	tp_pips	sl_pips	trading_days_count	total_trades	tradeRate_ratio	first_day	last_day	profit_factor	profit_trades_pct	net_profit	gross_profit	gross_loss
=end

require 'csv'

# -------------------------------
# CONFIG
# -------------------------------

file_path = "C:\\Users\\Aleks\\AppData\\Roaming\\MetaQuotes\\Tester\\47AEB69EDDAD4D73097816C71FB25856\\Agent-127.0.0.1-3000\\MQL5\\trade_database.tsv"

minimum_trades_to_qualify = 5
minimum_profitfactor_to_qualify = 3.0

TRADE_INDEX_START = 0
ENABLED = true
# and trade size is custom and various, see trade_size_from_pf

OUTPUT_FILE = File.join(__dir__, "trade_giga_encoder3_output.txt")

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

def trade_size_from_pf(pf)
  if pf > 12
    100
  elsif pf >= 10
    100
  elsif pf >= 8
    90
  elsif pf >= 6 # like 6.5, 7.9
    70
  elsif pf >= 4 # like 5.5
    40
  else
    30
  end
end

# -------------------------------
# READ DB
# -------------------------------

rows = CSV.read(file_path, headers: true, col_sep: "\t")

puts "Loaded rows: #{rows.size}"

# -------------------------------
# FILTER MAGIC NUMBERS
# -------------------------------

valid_rows = rows.select do |row|
  trades = row["total_trades"].to_i
  pf = row["profit_factor"].to_s == "Infinity" ? Float::INFINITY : row["profit_factor"].to_f

  trades >= minimum_trades_to_qualify &&
    pf >= minimum_profitfactor_to_qualify
end

puts "Qualified rows: #{valid_rows.size}"

MAGIC_NUMBERS = valid_rows.map { |r| r["magic"].to_s }.uniq

puts "Magic numbers selected: #{MAGIC_NUMBERS.size}"

# -------------------------------
# BUILD OUTPUT
# -------------------------------

output_lines = []
trade_size_stats = Hash.new(0)

MAGIC_NUMBERS.each_with_index do |magic, i|
  idx = TRADE_INDEX_START + i

  row = valid_rows.find { |r| r["magic"].to_s == magic }
  next unless row

  pf = row["profit_factor"].to_s == "Infinity" ? Float::INFINITY : row["profit_factor"].to_f

  trade_size_pct = trade_size_from_pf(pf)
  trade_size_stats[trade_size_pct] += 1

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
  block << "g_trade[#{idx}].tradeSizePct             = #{trade_size_pct};"
  block << "g_trade[#{idx}].tpPoints                 = #{tp_val};"
  block << "g_trade[#{idx}].slPoints                 = #{sl_val};"
  block << "g_trade[#{idx}].livePriceDiffTrigger     = #{price_prox};"
  block << "g_trade[#{idx}].levelOffsetPoints        = #{level_offset};"
  block << "g_trade[#{idx}].levelProximityFocus      = #{level_focus(direction)};"
  block << "g_trade[#{idx}].bannedRanges             = \"22,0,23,59;0,0,1,0\";"
  block << "g_trade[#{idx}].babysit_enabled          = #{babysit_enabled};"
  block << "g_trade[#{idx}].babysitStart_minute      = #{babysit_minute};"
  block << ""

  output_lines << block.join("\n")
end

# -------------------------------
# WRITE FILE
# -------------------------------

File.write(OUTPUT_FILE, output_lines.join("\n"))

puts "\n--- Example output (first config only) ---"
puts output_lines.first

puts "\nAll #{output_lines.size} configs saved to #{File.basename(OUTPUT_FILE)}"

# -------------------------------
# TRADE SIZE SUMMARY
# -------------------------------

puts "\n--- TRADE SIZE DISTRIBUTION ---"
trade_size_stats.sort_by { |k, _| k }.each do |size, count|
  puts "tradeSizePct=#{size} -> #{count} strategies"
end