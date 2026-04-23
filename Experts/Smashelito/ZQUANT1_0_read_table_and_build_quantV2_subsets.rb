file_path = "ZQUANT1_0_read_table_and_build_quantV2_subsets.tsv"
mq5_path  = "smashelito.mq5"

# --- STEP 1: READ TSV ---
lines = File.readlines(file_path, chomp: true)
header = lines.shift.split("\t")

idx_magic       = header.index("magic")
idx_quantFactor = header.index("quantFactor")

raise "Missing required columns" unless idx_magic && idx_quantFactor

records = []
seen_magic = {}

lines.each_with_index do |line, i|
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

  # Case 1: "price above X" or "price below X"
  if qf.match(/^price\s+(above|below)\s+/)
    return [qf]

  # Case 2: "price-above ..."
  elsif qf.start_with?("price-above")
    parts = qf.sub("price-above", "").strip.split(/\s+/)
    return parts.map { |p| "price above #{p}" }

  # Case 3: "price-below ..."
  elsif qf.start_with?("price-below")
    parts = qf.sub("price-below", "").strip.split(/\s+/)
    return parts.map { |p| "price below #{p}" }

  # Case 4: "price-betweenH-L X Y"
  elsif qf.start_with?("price-betweenH-L")
    parts = qf.sub("price-betweenH-L", "").strip.split(/\s+/)
    raise "Invalid betweenH-L format: #{qf}" unless parts.size >= 2

    return [
      "price below #{parts[0]}",
      "price above #{parts[1]}"
    ]
  else
    raise "Unknown quantFactor format: #{qf}"
  end
end

# --- STEP 4: PROCESS ALL RECORDS ---
results = []

records.each do |rec|
  func = extract_subset_function(mq5_content, rec[:subset_base_number])

  deconstructed = deconstruct_quant_factor(rec[:quantFactor])

  results << rec.merge(
    subset_function: func,
    deconstructed_quant: deconstructed
  )
end

# --- STEP 5: OUTPUT FIRST SET + COUNT ---
first = results.first

puts "FIRST SET:"
puts first
puts "\nTOTAL COUNT: #{results.size}"