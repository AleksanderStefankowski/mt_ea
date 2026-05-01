MQ5_FILE = "./smashelito.mq5"
subsets_to_search = "Subset_203"

content = File.read(MQ5_FILE)

# 1. Find all matching function names
function_names = content.scan(/bool\s+(#{subsets_to_search}\w*)\s*\(/).flatten.uniq

results = {}

function_names.each do |fname|
  # 2. Extract full function body using a simple brace counter
  if content =~ /bool\s+#{fname}\s*\([^\)]*\)\s*\{/
    start_idx = Regexp.last_match.begin(0)
    brace_count = 0
    i = content.index("{", start_idx)

    body_start = i
    while i < content.length
      brace_count += 1 if content[i] == "{"
      brace_count -= 1 if content[i] == "}"

      if brace_count == 0
        body_end = i
        break
      end
      i += 1
    end

    body = content[body_start..body_end]

    # 3. Every numeric literal in source order (duplicates kept); whole floats as one token
    numbers = body.scan(/\b\d+(?:\.\d+)?\b/).map do |tok|
      tok.include?(".") ? tok.to_f : tok.to_i
    end

    results[fname] = numbers
  end
end

# 4. Output
results.each do |fname, nums|
  puts "#{fname}: #{nums}"
end