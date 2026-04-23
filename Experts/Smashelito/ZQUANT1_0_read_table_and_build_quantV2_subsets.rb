file_path = "ZQUANT1_0_read_table_and_build_quantV2_subsets.tsv"
mq5_path  = "smashelito.mq5"

quant_function_insert_line = 3  # configurable
save_quant_functions_to_file = true
output_file = "ZQUANT1_0_read_table_and_build_quantV2_subsets_output.txt"

# --- STEP 1: READ TSV ---
lines = File.readlines(file_path, chomp: true)
header = lines.shift.split("\t")

idx_magic       = header.index("magic")
idx_quantFactor = header.index("quantFactor")

raise "Missing required columns" unless idx_magic && idx_quantFactor

records = []
seen_magic = {}

lines.each do |line|
  cols = line.split("\t")

  magic = cols[idx_magic]
  quant_factor = cols[idx_quantFactor]

  raise "Duplicate magic found: #{magic}" if seen_magic[magic]
  seen_magic[magic] = true

  subset_base_number = magic[0, 5]

  records << {
    magic: magic,
    quantFactor: quant_factor,
    subset_base_number: subset_base_number
  }
end

# --- STEP 2: LOAD MQ5 FILE ---
mq5_content = File.read(mq5_path)

def extract_subset_function(content, subset_base_number)
  pattern = /bool\s+Subset_#{subset_base_number}.*?\{.*?^\}/m
  match = content.match(pattern)
  raise "Subset function not found for #{subset_base_number}" unless match
  match[0]
end

# --- STEP 3: DECONSTRUCT quantFactor ---
def deconstruct_quant_factor(qf)
  qf = qf.strip
  pad = "   "

  if qf.match(/^price\s+(above|below)\s+/)
    ["#{pad}#{qf}"]

  elsif qf.start_with?("price-above")
    parts = qf.sub("price-above", "").strip.split(/\s+/)
    parts.map { |p| "#{pad}price above #{p}" }

  elsif qf.start_with?("price-below")
    parts = qf.sub("price-below", "").strip.split(/\s+/)
    parts.map { |p| "#{pad}price below #{p}" }

  elsif qf.start_with?("price-betweenH-L")
    parts = qf.sub("price-betweenH-L", "").strip.split(/\s+/)
    raise "Invalid betweenH-L format: #{qf}" unless parts.size >= 2

    [
      "#{pad}price below #{parts[0]}",
      "#{pad}price above #{parts[1]}"
    ]
  else
    raise "Unknown quantFactor format: #{qf}"
  end
end

# --- STEP 4: BUILD quant_function ---
def build_quant_function(subset_function, deconstructed_quant, insert_line)
  lines = subset_function.lines
  insert_idx = [insert_line, lines.length].min

  lines.insert(insert_idx, *deconstructed_quant.map { |l| l + "\n" })
  lines.join
end

# --- STEP 5: PROCESS ALL RECORDS ---
results = []

single_count = 0
double_count = 0
value_counts = Hash.new(0)

records.each do |rec|
  func = extract_subset_function(mq5_content, rec[:subset_base_number])
  deconstructed = deconstruct_quant_factor(rec[:quantFactor])
  quant_func = build_quant_function(func, deconstructed, quant_function_insert_line)

  # stats
  single_count += 1 if deconstructed.size == 1
  double_count += 1 if deconstructed.size == 2

  deconstructed.each { |v| value_counts[v] += 1 }

  results << quant_func
end

# --- STEP 6: PRINT STATS ---
puts "TOTAL COUNT: #{results.size}"
puts "SINGLE VALUE SETS: #{single_count}"
puts "DOUBLE VALUE SETS: #{double_count}"

puts "\nUNIQUE VALUE COUNTS:"
value_counts.sort.each do |val, count|
  puts "#{val.inspect} => #{count}"
end

# --- STEP 7: SAVE CLEAN FUNCTIONS ---
if save_quant_functions_to_file
  File.open(output_file, "w") do |f|
    results.each do |func|
      f.puts func.strip
      f.puts "\n\n"  # spacing between functions
    end
  end

  puts "\nSaved quant functions to #{output_file}"
end