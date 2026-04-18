require 'time'

starting_subset = "13"
max_per_file = 97 - starting_subset.to_i

trade_type      = "102"

timestamp = Time.now.strftime("%Y%m%d_%H%M")

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
blocks = [
  ["if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;"],
  [""],
  ["if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;"],
  ["if(kLast < 0 || kLast >= g_barsInDay) return false;"],
  [""],
  ["const int cleanStreakAboveMin = VARIABLE;", "10", "21", "40"], # na koniec jeszcze potestować min streak 60, 120, i maks większy 
  ["const int cleanStreakAboveMax = VARIABLE;", "59", "120", "240"],
  ["int streakAbove = g_cleanStreakAbove[levelIdx][kLast];"],
  ["if(streakAbove < cleanStreakAboveMin || streakAbove > cleanStreakAboveMax) return false;"],
  [""],
  ["string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, VARIABLE, false);", "50.0","100.0", "200", "300"],
  ["if(StringToDouble(diffBelow) < VARIABLE) return false;",  "5.0", "10.0", "25.0", "40.0"],
  [""],
  ["string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);"],
  ["if(StringToDouble(diffAbove) < VARIABLE) return false;", "6.0", "12.0", "30.0", "45.0"],
]

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

def build_function(subset_id, trade_type, lines)
  func_name = "Subset_#{trade_type}#{subset_id}"

  out = []
  out << "bool #{func_name}(double levelPx, int levelIdx, int kLast)"
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

all_combos = expand_blocks(blocks)

start_num = starting_subset.to_i

file_index = 1

all_combos.each_slice(max_per_file) do |slice|
  output = []

  slice.each_with_index do |lines, i|
    subset_number = (start_num + i).to_s.rjust(2, "0")
    output << build_function(subset_number, trade_type, lines)
  end

  file_name = "#{trade_type}generated_subsets_#{timestamp}_part#{file_index}.txt"
  File.write(file_name, output.join("\n"))

  file_index += 1
end

puts "Generated #{all_combos.size} subset functions"
puts "Saved into #{file_index - 1} files"