# ============================================================
# CONFIG
# ============================================================

MQ5_FILE = "./smashelito.mq5"

# ============================================================
# LOAD FILE
# ============================================================

content = File.read(MQ5_FILE)

results = []

content.each_line do |line|
  line = line.strip

  if line.start_with?("bool Subset_")
    puts line
    # Remove prefix
    cleaned = line.sub("bool Subset_", "")

    # Take part before "("
    name_part = cleaned.split("(").first

    # Keep only digits
    digits_only = name_part.gsub(/\D/, "")

    # Take first 5 characters only
    short = digits_only[0, 5]

    results << short if short && short.length == 5
  end
end

# ============================================================
# GROUPING BY FIRST 3 DIGITS
# ============================================================

groups = Hash.new { |h, k| h[k] = [] }

results.each do |val|
  key = val[0..2]         # first 3 digits
  last_two = val[-2, 2]   # last 2 characters

  groups[key] << last_two
end

# ============================================================
# OUTPUT GROUPED AS RUBY ARRAYS
# ============================================================

puts "\n=== GROUPED subset IDs (last 2 digits) BY FIRST 3 DIGITS (trade direction and type) ==="

groups.keys.sort.each do |key|
  values = groups[key]
  uniq_sorted = values.uniq.sort

  formatted = uniq_sorted.map { |v| "\"#{v}\"" }.join(", ")

  puts "Group #{key}: [#{formatted}]"
end