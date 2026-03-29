MQ5_FILE = "./smashelito.mq5"

# Load file
lines = File.readlines(MQ5_FILE)

# Find matching lines
matches = lines.select { |line| line.start_with?("// encoding input magic:") }

# Print matches
matches.each { |line| puts line }

# Print count
puts "\nTotal matches: #{matches.count}"