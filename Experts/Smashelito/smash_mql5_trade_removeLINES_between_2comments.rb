MQ5_FILE = "./smashelito.mq5"

START_MARKER = "// bookmark99 Subset Gentest start"
END_MARKER   = "// bookmark99 Subset Gentest end"
# START_MARKER = "// gentest dispatch start"
# END_MARKER   = "// gentest dispatch end"

lines = File.read(MQ5_FILE).lines

start_idx = lines.find_index { |l| l.strip.start_with?(START_MARKER) }
end_idx   = lines.find_index { |l| l.strip.start_with?(END_MARKER) }

if start_idx.nil? || end_idx.nil? || end_idx <= start_idx
  warn "Abort: markers not found or invalid order in #{MQ5_FILE}"
  exit 1
end

remove_count = end_idx - start_idx - 1

new_lines = []
new_lines += lines[0..start_idx]
new_lines += lines[end_idx..-1]

File.write(MQ5_FILE, new_lines.join)

puts "start marker found at line #{start_idx + 1}"
puts "end marker found at line #{end_idx + 1}"
puts "Removed lines count: #{remove_count}"
puts "Done."