SMASHELITO_FILE = "smashelito.mq5"
OUTPUT_FILE     = "ZQUANT1_0_read_table_and_build_quantV2_subsets_output.txt"

START_MARKER = "// quantspace2SubsetStart"
END_MARKER   = "// quantspace2SubsetEnd"

def extract_functions(text)
  functions = {}
  current_name = nil
  buffer = []
  brace_depth = 0

  text.each_line do |line|
    if line =~ /bool\s+(Subset_\d+)\s*\(/
      current_name = $1
      buffer = [line]
      brace_depth = line.count("{") - line.count("}")
      next
    end

    if current_name
      buffer << line
      brace_depth += line.count("{") - line.count("}")

      if brace_depth == 0
        functions[current_name] = buffer.join
        current_name = nil
        buffer = []
      end
    end
  end

  functions
end

# Read file
full_text = File.read(SMASHELITO_FILE)

# Split around markers safely
before, rest = full_text.split(START_MARKER, 2)
subset_content, after = rest.split(END_MARKER, 2)

subset_content ||= ""
after ||= ""

# Extract
smashelito_functions = extract_functions(subset_content)
output_functions     = extract_functions(File.read(OUTPUT_FILE))

# Counts
smashelito_count = smashelito_functions.size
output_count     = output_functions.size

only_in_smashelito = smashelito_functions.keys - output_functions.keys
only_in_output     = output_functions.keys - smashelito_functions.keys
in_both            = smashelito_functions.keys & output_functions.keys

# Merge explicitly
merged = {}

# 1. preserve smashelito-only
only_in_smashelito.each do |name|
  merged[name] = smashelito_functions[name]
end

# 2. overwrite common (use output)
in_both.each do |name|
  merged[name] = output_functions[name]
end

# 3. add output-only
only_in_output.each do |name|
  merged[name] = output_functions[name]
end

merged_count = merged.size

# Sort by numeric suffix
sorted = merged.sort_by { |name, _| name[/Subset_(\d+)/, 1].to_i }

# Build new subset block
new_subset = START_MARKER + "\n\n"
sorted.each do |_, func|
  new_subset << func.strip + "\n\n"
end
new_subset << END_MARKER

# Rebuild file
new_full_text = before + new_subset + after

# Write back
File.write(SMASHELITO_FILE, new_full_text)

# Final verification (re-read)
final_text = File.read(SMASHELITO_FILE)
_, rest2 = final_text.split(START_MARKER, 2)
subset2, _ = rest2.split(END_MARKER, 2)
final_functions = extract_functions(subset2 || "")

# Print required stats ONLY
puts "functions in smashelito: #{smashelito_count}"
puts "functions in output: #{output_count}"
puts "only in smashelito: #{only_in_smashelito.size}"
puts "only in output: #{only_in_output.size}"
puts "total unique before merge: #{(smashelito_functions.keys | output_functions.keys).size}"
puts "total after merge (in memory): #{merged_count}"
puts "final total in smashelito after save: #{final_functions.size}"