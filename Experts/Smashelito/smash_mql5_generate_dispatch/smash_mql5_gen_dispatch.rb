# ================== CONFIG ==================

OUTPUT_FILE = "smash_mql5_gen_dispatch_output.txt"

left_subset_id_start  = 11201
right_subset_id_start = 31201 # =nil # set to nil to disable right-side condition
subset_id_end         = 11277

# ================== VALIDATION ==================

raise "left_subset_id_start must be <= subset_id_end" if left_subset_id_start > subset_id_end

if right_subset_id_start
  diff_left  = subset_id_end - left_subset_id_start
  right_end  = right_subset_id_start + diff_left
end

# ================== GENERATION ==================

lines = []

(left_subset_id_start..subset_id_end).each_with_index do |left_id, i|
  right_id = right_subset_id_start ? right_subset_id_start + i : nil

  condition =
    if right_id
      "subsetHandlerKey == #{left_id} || subsetHandlerKey == #{right_id}"
    else
      "subsetHandlerKey == #{left_id}"
    end

  lines << "   if(#{condition})"
  lines << "      return Subset_#{left_id}(levelPx, levelIdx, kLast);"
end

# ================== OUTPUT ==================

output = lines.join("\n")

puts output
File.write(OUTPUT_FILE, output)

puts "\nSaved to: #{OUTPUT_FILE}"