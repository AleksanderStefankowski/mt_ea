require 'time'

# --- CONFIG ---
first_digit = "1" # 1 long or 2 short
allowed_2nd_digit = [0, 1, 2, 3, 4]  # quantv2 space, never edit this
third_digit_trade_type = "1"

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

#### 101 
blocks = [
  ["if (!g_dayLowSoFarAtBar[kLast].hasValue) return false;"],
  ["double diffWithLowOfDay = g_dayLowSoFarAtBar[kLast].value - levelPx;"],
  ["if (diffWithLowOfDay >  15.0) return false; // too far above // HARDCODED"],
  [""],
  ["if (diffWithLowOfDay < VARIABLE) return false; // too far below", "-15.0", "-10.0", "-7.0", "-3.0"],
  ["const int cleanStreakAbove_Minimum = VARIABLE; // var",  "90", "200", "400"],
  ["if(!Gate_CleanStreak_AtLeastX_AboveLevel(levelIdx, kLast, cleanStreakAbove_Minimum)) return false;"],
  ["// also do big VARIABLE for offsset"],
]


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
all_combos = expand_blocks(blocks)

file_index = 1
slot_index = 0
output = []
total_generated = 0

all_combos.each do |lines|

  # new file if slots exhausted
  if slot_index >= TOTAL_SLOTS
    file_name = "generated_subsets_#{timestamp}_part#{file_index}.txt"
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
  file_name = "generated_subsets_#{timestamp}_part#{file_index}.txt"
  File.write(file_name, output.join("\n"))
  puts "Saved #{file_name}"
end

puts "Generated #{total_generated} subset functions"
puts "Total files: #{file_index}"