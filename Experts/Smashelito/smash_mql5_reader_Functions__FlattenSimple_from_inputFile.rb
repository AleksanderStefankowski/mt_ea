require "set"

INPUT_FILE  = "smash_mql5_reader_Functions__saveToFile_theSubsets_from_inputMagic.txt"
OUTPUT_FILE = "smash_mql5_reader_Functions__FlattenSimple_from_inputFile_output.txt"

second_digits_allowed = [0, 1, 2, 3, 4]
starting_subset = 21306

SLOTS_PER_DIGIT = 99

content = File.read(INPUT_FILE)

functions = content.scan(/bool\s+Subset_\d+\s*\([^)]*\)\s*\{.*?\n\}/m)
raise "No functions found" if functions.empty?

# ---------------- decode ----------------

digits = starting_subset.to_s.chars.map(&:to_i)

a = digits[0]        # 1st digit (fixed)
b = digits[1]        # 2nd digit (constrained)
c = digits[2]        # 3rd digit (fixed)
slot = digits[3..4].join.to_i

unless second_digits_allowed.include?(b)
  raise "Invalid starting second digit: #{b}"
end

# ensure slot starts valid
if slot < 1 || slot > 99
  raise "Slot must be 01–99, got #{slot}"
end

# ---------------- builder ----------------

def build_id(a, b, c, d)
  (a * 10000) + (b * 1000) + (c * 100) + d
end

result = content.dup

functions.each_with_index do |fn, idx|

  new_id = build_id(a, b, c, slot)

  old_name = fn[/Subset_\d+/]
  new_name = "Subset_#{new_id}"

  result.gsub!(old_name, new_name)

  # ---------------- increment logic ----------------

  slot += 1

  if slot > 99
    slot = 1   # reset to 01

    b += 1

    unless second_digits_allowed.include?(b)
      raise "Second digit overflow: #{b} not allowed"
    end
  end
end

File.write(OUTPUT_FILE, result)

puts "Done. Renamed #{functions.size} functions."