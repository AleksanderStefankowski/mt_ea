MQ5_FILE = "./smashelito.mq5"

# Load file
lines = File.readlines(MQ5_FILE)

# Find matching lines (original pattern)
matches = lines.select { |line| line.start_with?("// encoding input magic:") }

# Find g_trade enabled lines
g_trade_matches = lines.select do |line|
  line.strip.start_with?("g_trade") && line.include?(".enabled")
end

# Determine max length to iterate safely
max_length = [matches.length, g_trade_matches.length].max

# Print both arrays side-by-side
puts "Index | Encoding Match | g_trade Match"
puts "-" * 60

(0...max_length).each do |i|
  encoding_line = matches[i]&.strip || ""
  g_trade_line = g_trade_matches[i]&.strip || ""

  puts "#{encoding_line}      | #{g_trade_line}"
end

# Print counts
puts "\nTotal encoding matches: #{matches.count}"
puts "Total g_trade matches: #{g_trade_matches.count}"