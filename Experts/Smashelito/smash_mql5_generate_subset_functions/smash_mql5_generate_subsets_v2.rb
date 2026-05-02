require 'time'

# --- CONFIG ---
first_digit = "2" # 1 long or 2 short
allowed_2nd_digit = [0, 1, 2, 3, 4]  # quantv2 space, never edit this
third_digit_trade_type = "4"

timestamp = Time.now.strftime("%Y%m%d_%H%M")

SLOTS_PER_DIGIT = 99 # never edit this
TOTAL_SLOTS = allowed_2nd_digit.size * SLOTS_PER_DIGIT  # 495
# --- BLOCKS ---

##### DONE
##### 102 czyli long type 02, tu tylko g_cleanStreakAbove
# blocks = [
  # ["if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;"],
  # [""],
  # ["if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;"],
  # ["if(kLast < 0 || kLast >= g_barsInDay) return false;"],
  # [""],
  # ["const int cleanStreakAboveMin = VARIABLE;", "20", "60", "120", "240", "45"],
  # ["int streakAbove = g_cleanStreakAbove[levelIdx][kLast];"],
  # ["if(streakAbove < cleanStreakAboveMin) return false;"],
  # [""],
  # ["string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);"],
  # ["if(diffBelow == \"never\" || StringToDouble(diffBelow) < VARIABLE) return false;", "5.0", "10.0", "25.0", "40.0"],
  # [""],
  # ["string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);"],
  # ["if(diffAbove == \"never\" || StringToDouble(diffAbove) < VARIABLE) return false;", "6.0", "12.0", "30.0", "45.0"],
# ]  
##### DONE
##### 102 czyli long type 02, tu tylko zasięg między cleanStreakAboveMin cleanStreakAboveMax
######## poza tymi dwoma blocks, nie zrobiłem jeszcze "wariant diffabove sprawdzany w polowie streaku" ani "wariant diffabove  + godzina wiecej niz streak"
# blocks = [
#   ["if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;"],
#   [""],
#   ["if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;"],
#   ["if(kLast < 0 || kLast >= g_barsInDay) return false;"],
#   [""],
#   ["const int cleanStreakAboveMin = VARIABLE;", "10", "21", "40"], # na koniec jeszcze potestować min streak 60, 120, i maks większy. To jeszcze nie było zrobione! 
#   ["const int cleanStreakAboveMax = VARIABLE;", "59", "120", "240"],
#   ["int streakAbove = g_cleanStreakAbove[levelIdx][kLast];"],
#   ["if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;"],
#   [""],
#   ["string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, VARIABLE, false);", "50.0","100.0", "200", "300"],
#   ["if(StringToDouble(diffBelow) < VARIABLE) return false;",  "5.0", "10.0", "25.0", "40.0"],
#   [""],
#   ["string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);"],
#   ["if(StringToDouble(diffAbove) < VARIABLE) return false;", "6.0", "12.0", "30.0", "45.0"],
# ]

##### 103 
# blocks = [
#   ["double levelAbove = Rules_GetClosestNonTertiaryLevelAbovePrice(levelPx);"],
#   ["if(levelAbove <= 0.0) return false;"],
#   [""],

#   ["const double twoLevelsDiff = levelAbove - levelPx;"],
#   ["if(twoLevelsDiff < VARIABLE) return false;", "15.0"],
#   ["if(twoLevelsDiff > VARIABLE) return false;", "35.0", "15.0", "50.0", "70.0"],
#   [""],

#   ["const int cleanStreakAboveMin = VARIABLE;", "90", "60", "140", "200", "300"],
#   ["int streakAbove = g_cleanStreakAbove[levelIdx][kLast];"],
#   ["if(streakAbove < cleanStreakAboveMin) return false;"],
#   [""],

#   ["const int diffAboveRange = VARIABLE;", "20", "35", "50", "80", "120"],
#   ["const double diffAboveMin = twoLevelsDiff + 11.0;"],
#   ["string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);"],
#   ["if(diffAbove == \"never\" || StringToDouble(diffAbove) < diffAboveMin) return false;"],
# ]

#### 101 wyniki miało super słabe, ale to pewnie dlatego że niskie trade count i jednocześnie niedużo VARIABLES
# blocks = [
#   ["if (!g_dayLowSoFarAtBar[kLast].hasValue) return false;"],
#   ["double diffWithLowOfDay = g_dayLowSoFarAtBar[kLast].value - levelPx;"],
#   ["if (diffWithLowOfDay >  15.0) return false; // too far above // HARDCODED"],
#   [""],
#   ["if (diffWithLowOfDay < VARIABLE) return false; // too far below", "-15.0", "-10.0", "-7.0", "-3.0"],
#   ["const int cleanStreakAbove_Minimum = VARIABLE; // var",  "90", "200", "400"],
#   ["if(!Gate_CleanStreak_AtLeastX_AboveLevel(levelIdx, kLast, cleanStreakAbove_Minimum)) return false;"],
#   ["// also do big VARIABLE for offsset"],
# ]
########### template for AI to rewrite a function. empty lines are [""], no return true ############################
# blocks = [ 
#   ["if (!g_dayLowSoFarAtBar[kLast].hasValue) return false;"],
#   ["double diffWithLowOfDay = g_dayLowSoFarAtBar[kLast].value - levelPx;"],
#   ["if (diffWithLowOfDay >  15.0) return false; // too far above // HARDCODED"],
#   [""],
#   ["if (diffWithLowOfDay < -15.0) return false; // too far below"],
#   ["const int cleanStreakAbove_Minimum = 200; // var"],
#   ["if(!Gate_CleanStreak_AtLeastX_AboveLevel(levelIdx, kLast, cleanStreakAbove_Minimum)) return false;"],
# ]
################################################################################################################

######## 201
# blocks = [
#   ["const double minDayHighOverLevelPoints = VARIABLE;", "0.77", "2.0"],
#   ["const double maxDayHighOverLevelPoints = VARIABLE;", "15.0", "10.0", "3.0", "25.0", "1.0"], # ["15.0", "10.0", "3.0", "25.0", "1.0"]
#   ["const int exclusiveMaxCandlesLowAboveLevel = VARIABLE;", "0" , "15", "45", "900"], # to do sprawdzenia tez, 0, 45, 
#   ["if(!Gate_CandleLows_FewerThanX_AboveLevel(kLast, levelPx, exclusiveMaxCandlesLowAboveLevel)) return false;"],
#   ["const int cleanStreakBelow_Minimum = VARIABLE;", "3", "10", "15", "25"], # ["3", "10", "15", "25"]
#   ["const int cleanStreakBelow_max = VARIABLE;", "45", "60", "300", "900"], # ["45", "60", "300", "900"]  # There are 1440 minutes in a day
#   ["if(!Gate_DayHighSoFar_NoMoreThanX_AboveLevel(kLast, levelPx, maxDayHighOverLevelPoints)) return false;"],
#   ["if(!Gate_DayHighSoFar_AtLeastX_AboveLevel(kLast, levelPx, minDayHighOverLevelPoints)) return false;"],
#   ["if(!Gate_CleanStreak_NoMoreThanX_BelowLevel(levelIdx, kLast, cleanStreakBelow_max)) return false;"],
#   ["if(!Gate_CleanStreak_AtLeastX_BelowLevel(levelIdx, kLast, cleanStreakBelow_Minimum)) return false;"]
# ]
####### 202
# blocks = [
#   ["const int cleanStreakBelowMin = VARIABLE;", "8", "20", "40", "80", "200"],
#   ["int cleanStreakBelow = g_cleanStreakBelow[levelIdx][kLast];"],
#   ["if(cleanStreakBelow < cleanStreakBelowMin) return false;"],
#   ["const int diffAboveRange = cleanStreakBelowMin + VARIABLE;  //+ X minutes", "1", "30", "60", "180"], 
#   ["string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffAboveRange, true);"],
#   ["if(diffAbove == \"never\" || StringToDouble(diffAbove) < VARIABLE) return false;", "8.0", "16.0", "25.0", "45.0"],
#   ["int diffBelowRange = cleanStreakBelow - 1;"],
#   ["if(diffBelowRange < 1) diffBelowRange = 1;"],
#   ["string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);"],
#   ["if(diffBelow == \"never\" || StringToDouble(diffBelow) < VARIABLE) return false;", "8.0", "16.0", "25.0", "45.0"],
# ]
####### 203
# blocks = [
#   ["// short type 3 : z dołu do góry level przebity jak masło i shortujemy level wyżej. "],
#   ["double levelBelow = Rules_GetClosestNonTertiaryLevelBelowPrice(levelPx);"],
#   ["if(levelBelow <= 0.0) return false;"],
#   [""],
#   ["const double twoLevelsDiff = levelPx - levelBelow;"],
#   ["if(twoLevelsDiff < VARIABLE) return false;", "6.0", "10.0", "15.0"], # maybe try 6.0
#   ["if(twoLevelsDiff > VARIABLE) return false;", "18.0", "25.0", "31.0"],
#   [""],
#   ["// a: clean OHLC streak below trade level: 131, czyli rule > 120 lub >65"],
#   ["// b: level never touched today, ale pewnie wystarczy clean streak 120"],
#   [""],
#   ["const int cleanStreakBelowMin = VARIABLE;", "30", "60", "90", "300", "500"], 
#   ["int streakBelow = g_cleanStreakBelow[levelIdx][kLast];"],
#   ["if(streakBelow < cleanStreakBelowMin) return false;"],
#   [""],
#   ["//a: (20:20 ma diff below level aż 42 pkt, dzikie rally. 6791-6762=29, 42-29=13"],
#   ["//b: (biggest diff w last 35 candles to 26 pkt od 6791 (a z levelami to 6791-6778=13, 26-13 = 13 czyli 13 poniżej 2nd level)"],
#   ["const int diffBelowRange = VARIABLE; //+ X minutes", "1", "30", "60", "180"],
#   ["const double diffBelowMin = twoLevelsDiff + VARIABLE;", "11.0", "22.0", "30.0"], 
#   ["string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, diffBelowRange, false);"],
#   ["if(diffBelow == \"never\" || StringToDouble(diffBelow) < diffBelowMin) return false;"]
# ]
######### 104
# // real trade examples:
# // ONO, diff from level is 41.9 | level 60 pkt ponizej ONO  | 140 pkt od ONO 
# // RTHO nie ma jeszcze | level 56 pkt ponizej RTHO | 150 pkt od RTHO
# // ibh nie ma jeszcze | level 15 pkt ponizej IBH | 96 pkt < IBH 
# // proximity 1.3, gain 19  w 8 m | contact -1.4 , 25 pkt w 10 m | contact -2.4, gain 20 pkt w 3 m
	# //"highgest diff ponad trade level to 25 wyżej, last 56 min, co jest wyżej niż level up o 3.7 pkt, niezużo ale to overnigh i early hours of ON)"
	# //"highgest diff ponad trade level to 40 wyżej, last 46 min"
blocks = [
  ["const double level_minDiff_with_ONO = VARIABLE;", "10.0", "20.0", "35.0", "50.0"],
  ["const double level_minDiff_with_RTHO = VARIABLE; // but skipped check if not set yet", "10.0", "20.0", "35.0", "50.0"],
  ["const double level_minDiff_with_IBH = VARIABLE; // but skipped check if not set yet", "10.0", "20.0"],
  [""],
  ["if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;"],
  ["if(kLast < 0 || kLast >= g_barsInDay) return false;"],
  ["if(!Gate_Level_neverTouched_floor(levelIdx, kLast)) return false;"],
  ["if(!Gate_Level_AbsDiff_with_ONO_atLeastX(levelPx, level_minDiff_with_ONO)) return false;"],
  [""],
  ["if(Gate_Level_AbsDiff_with_RTHO_guard_RTHO_ready(kLast))"],
  ["   if(!Gate_Level_AbsDiff_with_RTHO_atLeastX(levelPx, kLast, level_minDiff_with_RTHO)) return false;"],
  ["if(g_IBhighAtBar[kLast].hasValue)"],
  ["   if(!Gate_Level_AbsDiff_with_IBH_atLeastX(levelPx, kLast, level_minDiff_with_IBH)) return false;"],
  ["string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, VARIABLE, true);", "45", "90", "200", "20"],
  ["if(diffAbove == \"never\" || StringToDouble(diffAbove) < VARIABLE) return false;", "10.0", "15.0", "25.0", "40.0", "60.0"],
]
####### 204
blocks = [
  ["const double level_minDiff_with_ONO = VARIABLE;", "5.0", "20.0", "35.0", "60.0", "100.0", "140.0"],
  ["const double level_minDiff_with_RTHO = VARIABLE; // but skipped check if not set yet", "5.0", "15.0", "35.0", "50.0", "75.0", "95.0"],
  ["const double level_minDiff_with_IBH = VARIABLE; // but skipped check if not set yet", "10.0", "20.0", "30.0", "55.0", "80.0", "105.0"],
  [""],
  ["if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;"],
  ["if(kLast < 0 || kLast >= g_barsInDay) return false;"],
  ["if(!Gate_Level_neverTouched_ceiling(levelIdx, kLast)) return false;"],
  ["if(!Gate_Level_AbsDiff_with_ONO_atLeastX(levelPx, level_minDiff_with_ONO)) return false;"],
  [""],
  ["if(Gate_Level_AbsDiff_with_RTHO_guard_RTHO_ready(kLast))"],
  ["   if(!Gate_Level_AbsDiff_with_RTHO_atLeastX(levelPx, kLast, level_minDiff_with_RTHO)) return false;"],
  [""],
  ["if(g_IBhighAtBar[kLast].hasValue)"],
  ["   if(!Gate_Level_AbsDiff_with_IBH_atLeastX(levelPx, kLast, level_minDiff_with_IBH)) return false;"]
]
# --- VALIDATION ---
def validate_blocks!(blocks)
  blocks.each_with_index do |block, idx|
    next if block.length <= 1

    template = block[0]

    unless template.include?("VARIABLE")
      raise "Validation error in block ##{idx}: template must contain 'VARIABLE'\nBlock: #{block.inspect}"
    end
  end
end

# --- EXPAND ---
def expand_blocks(blocks)
  combos = [[]]

  blocks.each do |block|
    template = block[0]

    if block.length == 1
      combos.each { |c| c << template }
      next
    end

    values = block[1..]

    new_combos = []
    combos.each do |combo|
      values.each do |val|
        line = template.gsub("VARIABLE", val.to_s)
        new_combos << (combo + [line])
      end
    end

    combos = new_combos
  end

  combos
end

# --- BUILD FUNCTION ---
def build_function(full_id, lines)
  out = []
  out << "bool Subset_#{full_id}(double levelPx, int levelIdx, int kLast)"
  out << "{"

  lines.each do |line|
    if line.strip.empty?
      out << ""
    else
      out << "   #{line}"
    end
  end

  out << "   return true;"
  out << "}"
  out << ""

  out.join("\n")
end

# --- MAIN ---
validate_blocks!(blocks)

all_combos = expand_blocks(blocks)

file_index = 1
slot_index = 0
output = []
total_generated = 0

all_combos.each do |lines|

  # new file if slots exhausted
  if slot_index >= TOTAL_SLOTS
    file_name = "smash_mql5_generate_subsets_v2__#{timestamp}_part#{file_index}.txt"
    File.write(file_name, output.join("\n"))
    puts "Saved #{file_name}"

    file_index += 1
    slot_index = 0
    output = []
  end

  # map slot_index → digit + suffix
  digit_idx = slot_index / SLOTS_PER_DIGIT
  suffix_idx = slot_index % SLOTS_PER_DIGIT

  second_digit = allowed_2nd_digit[digit_idx]
  suffix = (suffix_idx + 1).to_s.rjust(2, "0")

  full_id = "#{first_digit}#{second_digit}#{third_digit_trade_type}#{suffix}"

  output << build_function(full_id, lines)

  slot_index += 1
  total_generated += 1
end

# save last file
if output.any?
  file_name = "smash_mql5_generate_subsets_v2__#{timestamp}_part#{file_index}.txt"
  File.write(file_name, output.join("\n"))
  puts "Saved #{file_name}"
end

puts "Generated #{total_generated} subset functions"
puts "Total files: #{file_index}"