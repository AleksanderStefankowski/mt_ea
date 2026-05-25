MQ5_FILE = "./smashelito.mq5"

# Load file
lines = File.readlines(MQ5_FILE)

# Find matching lines
matches = lines.select { |line| line.start_with?("// encoding input magic:") }

# Extract magic numbers
magic_numbers = matches.map do |line|
  line.split(":").last.strip
end

# Formatting
magics_per_line = 7

puts "MAGIC_NUMBERS = ["

magic_numbers.each_slice(magics_per_line) do |slice|
  formatted = slice.map { |m| "\"#{m}\"" }.join(", ")
  puts "  #{formatted},"
end

puts "]"

# Stats: build 2-char codes from 1st and 3rd digit
codes_1_3 = magic_numbers.map do |m|
  next nil if m.length < 3
  "#{m[0]}#{m[2]}"
end.compact.uniq

puts "\n1st and 3rd digit combined (unique values): #{codes_1_3.join(" ")}"
puts "\nTotal encoding matches: #{matches.count}"