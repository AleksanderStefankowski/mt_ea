# --- CONFIG ---
MQ5_FILE = "./smashelito.mq5"
RANGE = 13..28          # inclusive, g_trade indices
NEW_LEVEL_OFFSET = 0.5  # new value to set

# --- READ FILE ---
content = File.read(MQ5_FILE)

# --- PROCESS LINES ---
updated_content = content.lines.map do |line|
  if line =~ /g_trade\[(\d+)\]\.levelOffsetPoints\s*=\s*[\d.]+;/
    index = $1.to_i
    if RANGE.include?(index)
      old_line = line.strip
      line = line.sub(/= [\d.]+;/, "= #{NEW_LEVEL_OFFSET};")
      puts "Updated g_trade[#{index}]:"
      puts "  Before: #{old_line}"
      puts "  After : #{line.strip}"
      puts "-" * 40
    end
  end
  line
end.join

# --- WRITE BACK ---
File.write(MQ5_FILE, updated_content)

puts "✅ Updated g_trade[#{RANGE.begin}..#{RANGE.end}].levelOffsetPoints to #{NEW_LEVEL_OFFSET}"