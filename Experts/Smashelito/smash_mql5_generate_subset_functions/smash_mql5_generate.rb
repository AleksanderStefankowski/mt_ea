require 'time'

starting_subset = "01"
trade_type      = "102"

timestamp = Time.now.strftime("%Y%m%d_%H%M")
OUTPUT_FILE = "#{trade_type}generated_subsets_dateTime#{timestamp}.txt"

blocks = [
  ["if(levelPx >= g_ONhighSoFarAtBar[kLast].value) return false;"],
  [""],
  ["if(levelIdx < 0 || levelIdx >= g_levelsTodayCount) return false;"],
  ["if(kLast < 0 || kLast >= g_barsInDay) return false;"],
  [""],
  ["const int cleanStreakAboveMin = VARIABLE;", "20", "60", "120", "240", "45"],
  ["int streakAbove = g_cleanStreakAbove[levelIdx][kLast];"],
  ["if(streakAbove < cleanStreakAboveMin) return false;"],
  [""],
  ["string diffBelow = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, 100, false);"],
  ["if(diffBelow == \"never\" || StringToDouble(diffBelow) < VARIABLE) return false;", "5.0", "10.0", "25.0", "40.0"],
  [""],
  ["string diffAbove = Rules_GetHighestDiffFromLevelInWindowString(levelPx, kLast, streakAbove, true);"],
  ["if(diffAbove == \"never\" || StringToDouble(diffAbove) < VARIABLE) return false;", "6.0", "12.0", "30.0", "45.0"],
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

def build_function(index, subset_id, trade_type, lines)
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

# -------------------------------
# MAIN
# -------------------------------

all_combos = expand_blocks(blocks)

start_num = starting_subset.to_i

output = []

all_combos.each_with_index do |lines, i|
  subset_number = (start_num + i).to_s.rjust(2, "0")
  output << build_function(i, subset_number, trade_type, lines)
end

File.write(OUTPUT_FILE, output.join("\n"))

puts "Generated #{all_combos.size} subset functions"
puts "Saved to #{OUTPUT_FILE}"