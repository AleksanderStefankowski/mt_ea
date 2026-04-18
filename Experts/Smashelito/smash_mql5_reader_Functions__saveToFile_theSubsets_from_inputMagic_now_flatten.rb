INPUT_FILE  = "smash_mql5_reader_Functions__saveToFile_theSubsets_from_inputMagic.txt"
OUTPUT_FILE = "smash_mql5_reader_Functions__saveToFile_theSubsets_from_inputMagic_now_flattened.txt.txt"

first_3_digits = "112"
starting_index = "01"
step = 1

# ================== READ ==================

content = File.read(INPUT_FILE)

# ================== EXTRACT BLOCKS ==================

blocks = content.scan(/bool\s+Subset_\d{5}.*?\{.*?\n\}/m)

raise "No blocks found!" if blocks.empty?

# ================== BUILD NEW INDICES ==================

start = starting_index.to_i

new_indices = []

blocks.size.times do |i|
  val = start + i * step

  if val > 99
    raise "ERROR: step progression exceeded 99 (got #{val}) — too many blocks"
  end

  new_indices << format("%02d", val)
end

# ================== TRANSFORM BLOCKS ==================

transformed_blocks = []

blocks.each_with_index do |block, i|
  new_suffix = new_indices[i]

  # force prefix + new suffix (e.g., Subset_11201)
  new_block = block.sub(/Subset_\d{5}/) do
    "Subset_#{first_3_digits}#{new_suffix}"
  end

  transformed_blocks << new_block
end

# ================== OUTPUT ==================

# extract full new names like 11201, 11202 etc
final_names = transformed_blocks.map do |b|
  b[/Subset_(\d{5})/, 1]
end

puts "\n=== CONFIG ==="
puts "first_3_digits: #{first_3_digits}"
puts "starting_index: #{starting_index}"
puts "step: #{step}"
puts "total blocks: #{blocks.size}"

puts "\n=== FINAL GENERATED SUBSET IDS ==="
puts final_names.join(" ")

# ================== SAVE ==================

File.write(OUTPUT_FILE, transformed_blocks.join("\n\n"))

puts "\nSaved to: #{OUTPUT_FILE}"