# ============================================================
# CONFIG
# ============================================================

MQ5_FILE = "./smashelito.mq5"
END_MARKER = "//tradeDeleter_ends_here. AI never edit this comment"

# ============================================================
# LOAD FILE
# ============================================================

lines = File.read(MQ5_FILE).lines

# ============================================================
# STATE
# ============================================================

first_trade_idx = nil
remove_count = 0
new_lines = []

# ============================================================
# PROCESS
# ============================================================

i = 0

while i < lines.length
  line = lines[i]
  stripped = line.strip

  # detect first trade block start
  if first_trade_idx.nil? && stripped.start_with?("// encoding input magic")
    first_trade_idx = i
  end

  # stop region at sentinel (REMOVE UP TO HERE)
  if stripped == END_MARKER
    new_lines << line   # keep sentinel
    i += 1

    # keep everything after untouched
    new_lines.concat(lines[i..-1]) if i < lines.length

    break
  end

  # count + remove everything after first trade start
  if first_trade_idx && i >= first_trade_idx
    remove_count += 1
    i += 1
    next
  end

  new_lines << line
  i += 1
end

# ============================================================
# SAVE
# ============================================================

File.write(MQ5_FILE, new_lines.join)

# ============================================================
# LOG
# ============================================================

puts "Done."
puts "Removed lines (trade block → sentinel): #{remove_count}"
puts "First trade block started at line: #{first_trade_idx || 'not found'}"