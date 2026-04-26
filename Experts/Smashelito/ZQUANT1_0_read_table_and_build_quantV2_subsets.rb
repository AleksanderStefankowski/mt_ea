# key concepts in the script: magic, quantFactor: "price below IBH", subset_base_number: "10204"
# subset_function , deconstructed_quant: ["   price below IBH"], quant_function
file_path = "ZQUANT1_0_rubysplitter_quantANDLEVELS_b_ALL_QUANTED_likeconsole.tsv"
mq5_path  = "smashelito.mq5"

quant_function_insert_line = 3
save_quant_functions_to_file = true
output_file = "ZQUANT1_0_read_table_and_build_quantV2_subsets_output.txt"

# --- STEP 1: READ TSV ---
lines = File.readlines(file_path, chomp: true)
header = lines.shift.split("\t")

idx_magic       = header.index("magic")
idx_quantFactor = header.index("quantFactor")
idx_quantProfitFactor = header.index("quantProfitFactor")

raise "Missing required columns" unless idx_magic && idx_quantFactor && idx_quantProfitFactor


records = []
seen_magic = {}
lines.each_with_index do |line, i|
  next if line.strip.empty?

  cols = line.split("\t", -1)
  file_line = i + 2 # +1 header, +0-based i
  magic = cols[idx_magic]&.strip
  quant_factor = cols[idx_quantFactor]&.strip
  quant_profit_factor = cols[idx_quantProfitFactor]

  if magic.nil? || magic.empty?
    raise "Line #{file_line}: missing or empty 'magic' (#{cols.size} fields; need column index #{idx_magic} for magic). Preview: #{line[0, 160].inspect}"
  end
  if quant_factor.nil? || quant_factor.empty?
    raise "Line #{file_line}: missing or empty 'quantFactor' for magic #{magic}"
  end
  if quant_profit_factor.nil? || quant_profit_factor.to_s.strip.empty?
    raise "Line #{file_line}: missing or empty 'quantProfitFactor' for magic #{magic}"
  end
  raise "Duplicate magic found: #{magic}" if seen_magic[magic]
  seen_magic[magic] = true

  records << {
    magic: magic,
    quantFactor: quant_factor,
    quantProfitFactor: quant_profit_factor
  }
end

# --- STEP 2: LOAD MQ5 FILE ---
mq5_content = File.read(mq5_path)

# --- BASE SUBSET (5 DIGITS) ---
def base_subset_number(magic)
  s = magic.to_s
  raise "magic is empty" if s.empty?
  raise "magic must be at least 5 characters for Subset_ lookup, got: #{s.inspect}" if s.size < 5
  s[0, 5]
end

# --- OUTPUT SUBSET (10 DIGITS + SHIFT 2ND DIGIT) ---
def output_subset_number(magic, quant_profit_factor)
  s = magic.to_s
  raise "magic must be at least 10 characters for output subset, got: #{s.inspect} (#{s.size} chars)" if s.size < 10
  base10 = s[0, 10].chars
  if quant_profit_factor.to_f < 1.0
    base10[0] = (base10[0].to_i + 2).to_s
  end
  base10[1] = (base10[1].to_i + 5).to_s
  base10.join
end

def extract_subset_function(content, subset_number)
  pattern = /bool\s+Subset_#{subset_number}.*?\{.*?^\}/m
  match = content.match(pattern)
  raise "Subset function not found for #{subset_number}" unless match
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
    ["#{pad}#{qf}"]
  end
end

# --- STEP 3.5: FULL EXPLICIT MAPPING ---
def map_to_mq5_condition(line)
  raw = line.strip

  case raw

  when "PD_trend=PD_green"
    "   if(!Gate_PD_green()) return false;"
  when "PD_trend=PD_red"
    "   if(!Gate_PD_red()) return false;"
  when "gapFillPc=filled"
    "   if(!Gate_GapFilled_atBar_TOTEST(kLast)) return false;"
  when "openGap_info=gapDown_Day"
    "   if(!Gate_Day_HasGapDown()) return false;"
  when "openGap_info=gapUp_Day"
    "   if(!Gate_Day_HasGapUp()) return false;"
  when "dayBrokePDH=TRUE"
    "   if(!Gate_Day_DayBrokePDH_is_TRUE(kLast)) return false;"
  when "dayBrokePDH=FALSE"
    "   if(!Gate_Day_DayBrokePDH_is_FALSE(kLast)) return false;"
  when "dayBrokePDL=TRUE"
    "   if(!Gate_Day_DayBrokePDL_is_TRUE(kLast)) return false;"
  when "dayBrokePDL=FALSE"
    "   if(!Gate_Day_DayBrokePDL_is_FALSE(kLast)) return false;"

  # PRICE RULES (kept minimal here, extend as needed)
  when "price above IBH"
    "   if(!Gate_Level_AboveIBH(kLast, levelPx)) return false;"
  when "price above IBL"
    "   if(!Gate_Level_AboveIBL(kLast, levelPx)) return false;"
  when "price above ONH"
    "   if(!Gate_Level_AboveONH(kLast, levelPx)) return false;"
  when "price above ONL"
    "   if(!Gate_Level_AboveONL(kLast, levelPx)) return false;"
  when "price above PDC"
    "   if(!Gate_Level_AbovePDC(levelPx)) return false;"
  when "price above PDH"
    "   if(!Gate_Level_AbovePDH(levelPx)) return false;"
  when "price above PDL"
    "   if(!Gate_Level_AbovePDL(levelPx)) return false;"
  when "price above PDO"
    "   if(!Gate_Level_AbovePDO(levelPx)) return false;"
  when "price above midpoint"
    "   if(!Gate_Level_Abovemidpoint(kLast, levelPx)) return false;"
  when "price above dayHighSoFar"
    "   if(!Gate_Level_AbovedayHighSoFar(kLast, levelPx)) return false;"
  when "price above dayLowSoFar"
    "   if(!Gate_Level_AbovedayLowSoFar(kLast, levelPx)) return false;"
  when "price above RTHH"
    "   if(!Gate_Level_AboveRTHH(kLast, levelPx)) return false;"
  when "price above RTHL"
    "   if(!Gate_Level_AboveRTHL(kLast, levelPx)) return false;"

  when "price below IBH"
    "   if(!Gate_Level_BelowIBH(kLast, levelPx)) return false;"
  when "price below IBL"
    "   if(!Gate_Level_BelowIBL(kLast, levelPx)) return false;"
  when "price below ONH"
    "   if(!Gate_Level_BelowONH(kLast, levelPx)) return false;"
  when "price below ONL"
    "   if(!Gate_Level_BelowONL(kLast, levelPx)) return false;"
  when "price below PDC"
    "   if(!Gate_Level_BelowPDC(levelPx)) return false;"
  when "price below PDH"
    "   if(!Gate_Level_BelowPDH(levelPx)) return false;"
  when "price below PDL"
    "   if(!Gate_Level_BelowPDL(levelPx)) return false;"
  when "price below PDO"
    "   if(!Gate_Level_BelowPDO(levelPx)) return false;"
  when "price below midpoint"
    "   if(!Gate_Level_Belowmidpoint(kLast, levelPx)) return false;"
  when "price below dayHighSoFar"
    "   if(!Gate_Level_BelowdayHighSoFar(kLast, levelPx)) return false;"
  when "price below dayLowSoFar"
    "   if(!Gate_Level_BelowdayLowSoFar(kLast, levelPx)) return false;"
  when "price below RTHH"
    "   if(!Gate_Level_BelowRTHH(kLast, levelPx)) return false;"
  when "price below RTHL"
    "   if(!Gate_Level_BelowRTHL(kLast, levelPx)) return false;"

  else
    raise "No mapping defined for: #{raw}"
  end
end

# --- STEP 4: BUILD FUNCTION ---
def build_quant_function(subset_function, deconstructed_quant, insert_line)
  lines = subset_function.lines
  insert_idx = [insert_line, lines.length].min

  mapped_lines = deconstructed_quant.map do |l|
    map_to_mq5_condition(l) + "\n"
  end

  lines.insert(insert_idx, *mapped_lines)
  lines.join
end

# --- STEP 5: PROCESS ---
results = []
single_count = 0
double_count = 0
value_counts = Hash.new(0)


records.each do |rec|
  base = base_subset_number(rec[:magic])              # 5-digit lookup key
  out  = output_subset_number(rec[:magic], rec[:quantProfitFactor]) # 10-digit label

  subset_func = extract_subset_function(mq5_content, base)

  deconstructed = deconstruct_quant_factor(rec[:quantFactor])

  quant_func = build_quant_function(subset_func, deconstructed, quant_function_insert_line)
  single_count += 1 if deconstructed.size == 1
  double_count += 1 if deconstructed.size == 2

  # Replace function name to OUTPUT subset (optional but implied by your spec)
  quant_func = quant_func.gsub(/Subset_#{base}/, "Subset_#{out}")

  results << quant_func
end

# --- STEP 6: SAVE ---
puts "TOTAL COUNT: #{results.size}"
puts "SINGLE VALUE SETS: #{single_count}"
puts "DOUBLE VALUE SETS: #{double_count}"

puts "\nUNIQUE VALUE COUNTS:"
value_counts.sort.each do |val, count|
  puts "#{val.inspect} => #{count}"
end

if save_quant_functions_to_file
  File.open(output_file, "w") do |f|
    results.each do |func|
      f.puts func.strip
      f.puts "\n"
    end
  end

  puts "\nSaved quant functions to #{output_file}"
end