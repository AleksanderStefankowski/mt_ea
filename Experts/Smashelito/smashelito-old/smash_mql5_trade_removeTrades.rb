# ============================================================
# CONFIG
# ============================================================

MQ5_FILE = "./smashelito.mq5"
DELETE_RANGE = [0, 3000]  # inclusive, trade indices to delete
END_MARKER = "//tradeDeleter_ends_here. AI never edit this comment"

# ============================================================
# LOAD FILE
# ============================================================

content = File.read(MQ5_FILE)
lines = content.lines

unless lines.any? { |l| l.strip.start_with?(END_MARKER) }
  warn "Abort: sentinel not found in #{MQ5_FILE}"
  warn "Expected a line starting with: #{END_MARKER}"
  exit 1
end

# ============================================================
# PROCESS LINES
# ============================================================

new_lines = []
skip_block = false

lines.each_with_index do |line, idx|
  stripped = line.strip

  # Stop processing completely once we hit the end marker
  if stripped.start_with?(END_MARKER)
    # keep the marker and everything after it untouched
    new_lines.concat(lines[idx..-1])
    break
  end

  # Detect start of a trade block
  if stripped =~ %r{// encoding input magic: (\d+)}
    # Look ahead to find trade index in g_trade[INDEX]
    next_line_index = idx + 1
    index_line = lines[next_line_index] rescue nil
    trade_index = nil
    if index_line && index_line.strip =~ /g_trade\[(\d+)\]/
      trade_index = $1.to_i
    end

    # Determine if this block should be skipped
    if trade_index && DELETE_RANGE[0] <= trade_index && trade_index <= DELETE_RANGE[1]
      skip_block = true
      next  # skip this line
    else
      skip_block = false
    end
  end

  # Skip lines while inside a block
  next if skip_block

  # Keep the line if not skipped
  new_lines << line
end

# ============================================================
# SAVE FILE
# ============================================================

File.write(MQ5_FILE, new_lines.join)
puts "Done. Deleted trades in range #{DELETE_RANGE[0]}..#{DELETE_RANGE[1]} if present."
puts "Processing stopped at sentinel line: #{END_MARKER}"