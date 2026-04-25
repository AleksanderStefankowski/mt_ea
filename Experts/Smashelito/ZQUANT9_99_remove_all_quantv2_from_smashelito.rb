SMASHELITO_FILE = "smashelito.mq5"

SUBSET_START = "// quantspace2SubsetStart"
SUBSET_END   = "// quantspace2SubsetEnd"

DISPATCH_START = "// quantspace1DispatchStart"
DISPATCH_END   = "// quantspace1DispatchEnd"


def clean_section(lines, start_marker, end_marker)
  output = []
  i = 0

  while i < lines.length
    line = lines[i]

    if line.include?(start_marker)
      output << line.rstrip + "\n"
      output << "\n"
      output << "\n"

      i += 1
      # Skip everything until end marker
      while i < lines.length && !lines[i].include?(end_marker)
        i += 1
      end

      # Add end marker if found
      if i < lines.length
        output << lines[i].rstrip + "\n"
      end
    else
      output << line
    end

    i += 1
  end

  output
end


lines = File.readlines(SMASHELITO_FILE, encoding: "utf-8")

# Clean both sections
lines = clean_section(lines, SUBSET_START, SUBSET_END)
lines = clean_section(lines, DISPATCH_START, DISPATCH_END)

File.open(SMASHELITO_FILE, "w", encoding: "utf-8") do |f|
  f.write(lines.join)
end