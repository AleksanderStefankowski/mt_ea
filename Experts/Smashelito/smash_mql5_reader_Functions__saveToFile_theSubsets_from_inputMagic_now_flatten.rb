require "set"

INPUT_FILE  = "smash_mql5_reader_Functions__saveToFile_theSubsets_from_inputMagic.txt"
OUTPUT_FILE = "smash_mql5_reader_Functions__saveToFile_theSubsets_from_inputMagic_now_flatten.txt"

# ================== CONFIG ==================

first_digit = "1"
second_digits_allowed = [0, 1, 2, 3, 4]
third_digit = "4"

starting_index_digits4th5th = "01"

SLOTS_PER_SECOND_DIGIT = 99
TOTAL_SLOTS = second_digits_allowed.size * SLOTS_PER_SECOND_DIGIT

# ================== LOAD ==================

content = File.read(INPUT_FILE)

# ================== EXTRACT BLOCKS ==================

blocks = content.scan(/bool\s+Subset_\d{5}.*?\{.*?\n\}/m)
raise "No blocks found!" if blocks.empty?

if blocks.size > TOTAL_SLOTS
  raise "Too many blocks (#{blocks.size}) for available slots (#{TOTAL_SLOTS})"
end

# ================== BUILD IDS ==================

start_suffix = starting_index_digits4th5th.to_i
raise "Invalid starting_index_digits4th5th" if start_suffix < 1 || start_suffix > 99

current_slot = start_suffix - 1

new_ids = []

blocks.size.times do |i|
  slot = current_slot + i

  digit_idx = slot / SLOTS_PER_SECOND_DIGIT
  suffix_idx = slot % SLOTS_PER_SECOND_DIGIT

  if digit_idx >= second_digits_allowed.size
    raise "ERROR: exceeded allowed second digits at block #{i}"
  end

  second_digit = second_digits_allowed[digit_idx]
  suffix = format("%02d", suffix_idx + 1)

  full_id = "#{first_digit}#{second_digit}#{third_digit}#{suffix}"
  new_ids << full_id
end

# ================== TRANSFORM BLOCKS ==================

transformed_blocks = []

blocks.each_with_index do |block, i|
  new_id = new_ids[i]

  new_block = block.sub(/Subset_\d{5}/, "Subset_#{new_id}")
  transformed_blocks << new_block
end

# ================== OUTPUT ==================

puts "\n=== CONFIG ==="
puts "first_digit: #{first_digit}"
puts "second_digits_allowed: #{second_digits_allowed.inspect}"
puts "third_digit: #{third_digit}"
puts "start_suffix: #{starting_index_digits4th5th}"
puts "total blocks: #{blocks.size}"

puts "\n=== FINAL GENERATED SUBSET IDS ==="
puts new_ids.join(" ")

# ================== SAVE ==================

File.write(OUTPUT_FILE, transformed_blocks.join("\n\n"))

puts "\nSaved to: #{OUTPUT_FILE}"