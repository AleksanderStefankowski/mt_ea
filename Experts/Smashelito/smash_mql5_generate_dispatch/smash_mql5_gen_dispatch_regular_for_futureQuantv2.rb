# ================== CONFIG ==================

OUTPUT_FILE = "smash_mql5_gen_dispatch_regular_for_futureQuantv2.txt"

left_subset_id_start  = 10401
right_subset_id_start = 30401 # nil allowed
subset_id_end         = 14499 # 13355

SLOTS_PER_GROUP = 99

# ================== HELPERS ==================

def parse_id(id)
  str = id.to_s.rjust(5, '0')
  first  = str[0]
  second = str[1]
  third  = str[2]
  slot   = str[3..4].to_i
  [first, second, third, slot]
end

def build_id(first, second, third, slot)
  "#{first}#{second}#{third}#{slot.to_s.rjust(2,'0')}"
end

# ================== GENERATION ==================

lines = []

f1, s1, t1, start_slot = parse_id(left_subset_id_start)
_,  _,  _, end_slot    = parse_id(subset_id_end)

start_second = s1.to_i
end_second   = subset_id_end.to_s[1].to_i

current_f = f1
fixed_third = t1  # 🚨 NEVER CHANGE THIS

(start_second..end_second).each do |second_digit|

  start_s = (second_digit == start_second) ? start_slot : 1
  end_s   = (second_digit == end_second)   ? end_slot   : SLOTS_PER_GROUP

  (start_s..end_s).each do |slot|

    left_id = build_id(current_f, second_digit.to_s, fixed_third, slot)

    if right_subset_id_start
      offset = left_id.to_i - left_subset_id_start
      right_id = right_subset_id_start + offset
      condition = "subsetHandlerKey == #{left_id} || subsetHandlerKey == #{right_id}"
    else
      condition = "subsetHandlerKey == #{left_id}"
    end

    lines << "   if(#{condition})"
    lines << "      return Subset_#{left_id}(levelPx, levelIdx, kLast);"
  end
end

# ================== OUTPUT ==================

File.write(OUTPUT_FILE, lines.join("\n"))

puts "Generated #{lines.size} dispatcher lines"
puts "Saved to: #{OUTPUT_FILE}"