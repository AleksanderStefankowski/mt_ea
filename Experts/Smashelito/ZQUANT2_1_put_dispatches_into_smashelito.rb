SMASHELITO_FILE = "smashelito.mq5"

SUBSET_START = "// quantspace2SubsetStart"
SUBSET_END   = "// quantspace2SubsetEnd"

DISPATCH_START = "// quantspace1DispatchStart"
DISPATCH_END   = "// quantspace1DispatchEnd"

def extract_subset_names(text)
  names = []

  text.each_line do |line|
    if line =~ /bool\s+(Subset_(\d+))\s*\(/
      names << [$1, $2]  # ["Subset_123", "123"]
    end
  end

  names
end

# Read file
full_text = File.read(SMASHELITO_FILE)

# -------------------------
# Extract subset section
# -------------------------
before_subset, rest_subset = full_text.split(SUBSET_START, 2)
subset_content, after_subset = rest_subset.split(SUBSET_END, 2)

subset_content ||= ""

subset_names = extract_subset_names(subset_content)

# Sort by numeric key
sorted = subset_names.sort_by { |(_, num)| num.to_i }

# -------------------------
# Build dispatch block
# -------------------------
dispatch_block = DISPATCH_START + "\n\n"

sorted.each do |(full_name, num)|
  dispatch_block << "            if(subsetHandlerKey10 == #{num})\n"
  dispatch_block << "               return #{full_name}(levelPx, levelIdx, kLast);\n"
end

dispatch_block << "\n" + DISPATCH_END

# -------------------------
# Replace dispatch section
# -------------------------
before_dispatch, rest_dispatch = full_text.split(DISPATCH_START, 2)
_, after_dispatch = rest_dispatch.split(DISPATCH_END, 2)

new_full_text = before_dispatch + dispatch_block + after_dispatch

# Write back
File.write(SMASHELITO_FILE, new_full_text)

# Optional: print count
puts "Total subset functions found: #{sorted.size}"
puts "Dispatch section updated."