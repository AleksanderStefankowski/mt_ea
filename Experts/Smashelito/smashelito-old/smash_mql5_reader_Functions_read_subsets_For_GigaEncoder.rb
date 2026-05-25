# ============================================================
# CONFIG
# ============================================================

require 'set'

MQ5_FILE = "./smashelito.mq5"

# ============================================================
# LOAD FILE
# ============================================================

content = File.read(MQ5_FILE)

# ============================================================
# REGEX
# ============================================================

REGEX = /(?<=[\s\(\)])(Subset_[A-Za-z0-9_]+)(?=[\s\(\)])/

# ============================================================
# EXTRACT
# ============================================================

subset_set = Set.new

content.scan(REGEX) do |match|
  subset_set << match[0]
end

# ============================================================
# PROCESS SUBSETS (SMART PARSE)
# ============================================================
# Extract:
# Subset_20114_from20113 → prefix=201, suffix=14
# Subset_40196_quant20101 → prefix=401, suffix=96

subset_groups = Hash.new { |h,k| h[k] = Set.new }

subset_set.each do |s|
  if s =~ /^Subset_(\d{3})(\d{2})/
    prefix = $1
    suffix = $2
    subset_groups[prefix] << suffix
  end
end

# Convert to sorted arrays
subset_groups_sorted = subset_groups.transform_values { |set| set.to_a.sort }

# Max suffix per prefix
largest_suffix_per_prefix = subset_groups.transform_values do |set|
  set.map(&:to_i).max
end

# ============================================================
# OUTPUT
# ============================================================

puts
puts "=== Subset_ VARIABLES (all) ==="
subset_set.to_a.sort.each { |s| puts s }

puts
puts "=== Subset_ MAX SUFFIX PER PREFIX ==="
largest_suffix_per_prefix.sort.each do |prefix, max_suffix|
  puts "Subset_#{prefix}#{format('%02d', max_suffix)}"
end

puts
puts "=== GROUPED (last 2 digits) BY FIRST 3 DIGITS ==="
subset_groups_sorted.sort.each do |prefix, suffixes|
  puts "Group #{prefix}: #{suffixes.inspect}"
  puts "\n"
end

puts
puts "Counts:"
puts "Subset_ (all): #{subset_set.size}"
puts "Subset prefixes: #{subset_groups.size}"