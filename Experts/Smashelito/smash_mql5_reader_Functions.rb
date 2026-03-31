# ============================================================
# CONFIG
# ============================================================

MQ5_FILE = "./smashelito.mq5"

# ============================================================
# LOAD FILE
# ============================================================

content = File.read(MQ5_FILE)

# ============================================================
# REGEX
# ============================================================
# Match words that:
# - start with Gate_ or Subset_
# - are bounded by space, ( or )
# - consist of letters, numbers, underscore

REGEX = /(?<=[\s\(\)])(Gate_[A-Za-z0-9_]+|Subset_[A-Za-z0-9_]+)(?=[\s\(\)])/


# ============================================================
# EXTRACT
# ============================================================

gate_set   = {}
subset_set = Set.new

content.scan(REGEX) do |match|
  word = match[0]

  if word.start_with?("Gate_")
    gate_set[word] = true
  elsif word.start_with?("Subset_")
    subset_set << word
  end
end

# ============================================================
# PROCESS SUBSETS BY PREFIX
# ============================================================

# Hash: { "302" => [1,2,3,...] }
subset_groups = Hash.new { |h,k| h[k] = [] }

subset_set.each do |s|
  if s =~ /^Subset_(\d{3})(\d{2})$/
    prefix = $1
    suffix = $2.to_i
    subset_groups[prefix] << suffix
  end
end

# Get largest suffix per prefix
largest_suffix_per_prefix = subset_groups.transform_values { |arr| arr.max }

# ============================================================
# OUTPUT
# ============================================================

puts
puts "=== Gate_ VARIABLES ==="
gate_set.keys.sort.each { |k| puts k }

puts
puts "=== Subset_ VARIABLES (all) ==="
subset_set.to_a.sort.each { |s| puts s }

puts
puts "=== Subset_ MAX SUFFIX PER PREFIX ==="
largest_suffix_per_prefix.sort.each do |prefix, max_suffix|
  puts "Subset_#{prefix}#{format('%02d', max_suffix)}"
end

puts
puts "Counts:"
puts "Gate_:   #{gate_set.size}"
puts "Subset_ (all): #{subset_set.size}"
puts "Subset prefixes: #{largest_suffix_per_prefix.size}"