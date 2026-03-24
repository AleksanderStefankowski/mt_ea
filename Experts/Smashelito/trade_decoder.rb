trades = '''
   g_trade[0].enabled                  = true; // good
   g_trade[0].tradeDirectionCategory   = MAGIC_TRADE_LONG;   // buy limit (or 1..4)
   g_trade[0].tradeTypeId          = 2;
   g_trade[0].ruleSubsetId         = 1; // not used in EA logic; only encoded in composite magic (custom meaning — Aleksander)
   g_trade[0].sessionPdCategory    = MAGIC_IS_RTH_AND_PD_GREEN;
   g_trade[0].tradeSizePct         = 100;
   g_trade[0].tpPips               = 12.0;
   g_trade[0].slPips               = 12.0;
   g_trade[0].livePriceDiffTrigger = 3.0;
   g_trade[0].levelOffsetPips      = 2.6;
   g_trade[0].levelProximityFocus  = TRADE_LEVEL_FOCUS_BELOW;
   g_trade[0].bannedRanges         = "22,0,23,59;0,0,1,0";
   g_trade[0].babysit_enabled      = true;
   g_trade[0].babysitStart_minute  = 11;
'''


# --- ENUM MAPPINGS ---
DIR_MAP = {
  "MAGIC_TRADE_LONG" => 1,
  "MAGIC_TRADE_SHORT" => 2,
  "MAGIC_TRADE_LONG_REVERSED" => 3,
  "MAGIC_TRADE_SHORT_REVERSED" => 4
}

SESSION_MAP = {
  "MAGIC_IS_ON_AND_PD_GREEN" => 1,
  "MAGIC_IS_ON_AND_PD_RED" => 2,
  "MAGIC_IS_RTH_AND_PD_GREEN" => 3,
  "MAGIC_IS_RTH_AND_PD_RED" => 4
}

# --- CLEAN INPUT (remove comments) ---
clean = trades.gsub(/\/\/.*$/, "")

# --- PARSE ---
data = {}

clean.each_line do |line|
  next if line.strip.empty?

  if line =~ /g_trade\[(\d+)\]\.(\w+)\s*=\s*(.+);/
    idx = $1.to_i
    key = $2
    val = $3.strip

    data[idx] ||= {}
    data[idx][key] = val
  end
end

# --- HELPERS ---
def encode_2digit_tenths(val)
  (val.to_f * 10).round.to_s.rjust(2, "0")
end
def format_magic_slots(m)
  [
    m[0],        # 1
    m[1..2],     # 02
    m[3..4],     # 01
    m[5],        # 3
    m[6..7],     # 30
    m[8..9],     # 26
    m[10..12],   # 811
    m[13..14],   # 12
    m[15..16]    # 12
  ].join(" ")
end
def encode_tp_sl(val)
  val.to_i.to_s.rjust(2, "0")
end

def encode_babysit(enabled, minute)
  if enabled == "true"
    (800 + minute.to_i).to_s
  else
    "700"
  end
end

# --- BUILD MAGIC ---
def build_magic(t)
  dir   = DIR_MAP[t["tradeDirectionCategory"]]
  type  = t["tradeTypeId"].to_i.to_s.rjust(2, "0")
  subset= t["ruleSubsetId"].to_i.to_s.rjust(2, "0")
  sess  = SESSION_MAP[t["sessionPdCategory"]]

  prox  = encode_2digit_tenths(t["livePriceDiffTrigger"])
  off   = encode_2digit_tenths(t["levelOffsetPips"])

  baby  = encode_babysit(t["babysit_enabled"], t["babysitStart_minute"])

  tp    = encode_tp_sl(t["tpPips"])
  sl    = encode_tp_sl(t["slPips"])

  "#{dir}#{type}#{subset}#{sess}#{prox}#{off}#{baby}#{tp}#{sl}"
end

# --- OUTPUT ---
data.sort.each do |idx, t|
  puts "\n"
  puts "g_trade[#{idx}].enabled                  = #{t["enabled"]};"
  puts "g_trade[#{idx}].tradeDirectionCategory   = #{t["tradeDirectionCategory"]};"
  puts "g_trade[#{idx}].tradeTypeId              = #{t["tradeTypeId"]};"
  puts "g_trade[#{idx}].ruleSubsetId             = #{t["ruleSubsetId"]};"
  puts "g_trade[#{idx}].sessionPdCategory        = #{t["sessionPdCategory"]};"
  puts "g_trade[#{idx}].tradeSizePct             = #{t["tradeSizePct"]};"
  puts "g_trade[#{idx}].tpPips                   = #{t["tpPips"]};"
  puts "g_trade[#{idx}].slPips                   = #{t["slPips"]};"
  puts "g_trade[#{idx}].livePriceDiffTrigger     = #{t["livePriceDiffTrigger"]};"
  puts "g_trade[#{idx}].levelOffsetPips          = #{t["levelOffsetPips"]};"
  puts "g_trade[#{idx}].levelProximityFocus      = #{t["levelProximityFocus"]};"
  puts "g_trade[#{idx}].bannedRanges = #{t["bannedRanges"]};"
  puts "g_trade[#{idx}].babysit_enabled          = #{t["babysit_enabled"]};"

  # normalize babysit minute (optional improvement)
  babysit_min = t["babysit_enabled"] == "true" ? t["babysitStart_minute"] : "0"
  puts "g_trade[#{idx}].babysitStart_minute      = #{babysit_min};"

  magic = build_magic(t)
  puts "MAGIC:           #{magic}"
  puts "--MAGIC SLOTTED: D TT SS C PR OF BBY TP SL"
  puts "--MAGIC SLOTTED: #{format_magic_slots(magic)}"
end