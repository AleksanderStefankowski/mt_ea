MQ5_FILE = "./smashelito.mq5"

lines = File.readlines(MQ5_FILE)

# -----------------------------
# Extract encoding lines
# -----------------------------
matches = lines.select { |line| line.start_with?("// encoding input magic:") }

magic_numbers = matches.map do |line|
  line.split("// encoding input magic:")[1].strip.split.first
end

# -----------------------------
# g_trade lines
# -----------------------------
g_trade_matches = lines.select do |line|
  line.strip.start_with?("g_trade") && line.include?(".enabled")
end

# -----------------------------
# Side-by-side debug print
# -----------------------------
max_length = [matches.length, g_trade_matches.length].max

puts "Index | Encoding Match | g_trade Match"
puts "-" * 60

(0...max_length).each do |i|
  puts "#{matches[i]&.strip || ""}      | #{g_trade_matches[i]&.strip || ""}"
end

puts "\nTotal encoding matches: #{matches.count}"
puts "Total g_trade matches: #{g_trade_matches.count}"

# -----------------------------
# MAGIC ARRAY PRINT
# -----------------------------
puts "\nMAGIC_ARRAY = ["
magic_numbers.each_slice(5) do |slice|
  puts "  " + slice.map { |m| "\"#{m}\"" }.join(", ") + ","
end
puts "]"

# -----------------------------
# GROUPING LOGIC
# -----------------------------
groups = Hash.new { |h, k| h[k] = [] }

magic_numbers.each do |m|
  next unless m && m.length >= 5

  group_key = m[0,3]   # first 3 digits
  suffix    = m[3,2]   # next 2 digits

  groups[group_key] << suffix
end

# sort groups + values
groups.each do |k, v|
  groups[k] = v.uniq.sort
end

# -----------------------------
# PRINT GROUPED RESULT
# -----------------------------
puts "\n=== GROUPED (last 2 digits) BY FIRST 3 DIGITS ==="

groups.keys.sort.each do |key|
  list = groups[key]
  puts "Group #{key}: #{list.inspect}"
end