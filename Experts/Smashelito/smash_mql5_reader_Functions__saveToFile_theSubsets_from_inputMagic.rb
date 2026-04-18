MQ5_FILE = "./smashelito.mq5"

magic_input = <<~TEXT
10309440157000606
10312240157000606
10304140157000606
10312140157000606
TEXT

# ================== STEP 1: GET SUBSETS ==================

pull_subsets = magic_input.lines.map(&:strip).reject(&:empty?).map { |m| m[0..4] }.uniq

puts "Pulling subsets: #{pull_subsets}"

# ================== STEP 2: READ FILE ==================

content = File.read(MQ5_FILE)

# ================== STEP 3: EXTRACT BLOCKS ==================

blocks = []

# Regex explanation:
# - matches "bool Subset_XXXXX..." where XXXXX is 5 digits
# - captures full function body including nested braces safely (simple level)
regex = /bool\s+Subset_(\d{5}.*?)\{.*?\n\}/m

content.scan(regex) do |match|
  full_match = $&   # entire matched block
  subset_id = match[0][0..4]

  if pull_subsets.include?(subset_id)
    blocks << full_match
  end
end

# ================== STEP 4: OUTPUT ==================

if blocks.any?
  puts "\n=== EXAMPLE MATCHED BLOCK ==="
  puts blocks.first
else
  puts "\nNo matching blocks found."
end

puts "\nTotal matched subset blocks: #{blocks.size}"

# ================== STEP 5: SAVE ==================

output_file = "smash_mql5_reader_Functions__saveToFile_theSubsets_from_inputMagic.txt"

File.write(output_file, blocks.join("\n\n"))

puts "\nSaved to: #{output_file}"