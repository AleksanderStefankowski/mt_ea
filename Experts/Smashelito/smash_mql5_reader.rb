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
subset_set = {}

content.scan(REGEX) do |match|
  word = match[0]

  if word.start_with?("Gate_")
    gate_set[word] = true
  elsif word.start_with?("Subset_")
    subset_set[word] = true
  end
end

# ============================================================
# OUTPUT
# ============================================================

puts
puts "=== Gate_ VARIABLES ==="
gate_set.keys.sort.each { |k| puts k }

puts
puts "=== Subset_ VARIABLES ==="
subset_set.keys.sort.each { |k| puts k }

puts
puts "Counts:"
puts "Gate_:   #{gate_set.size}"
puts "Subset_: #{subset_set.size}"