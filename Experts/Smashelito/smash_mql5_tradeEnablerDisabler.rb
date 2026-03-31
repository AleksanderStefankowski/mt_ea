=begin
# in the MQ5_FILE we have lines like below:
g_trade[1].enabled                  = true;
g_trade[5].enabled                  = true;
g_trade[6].enabled                  = true;
we don't know where exactly they are. 
Write a script that for each thing in range or in array_mode_list, 
and sets the value that is in set_state.
so if set_state is :false and range = [0, 3], I expect
g_trade[0].enabled                  = true;
g_trade[1].enabled                  = false;
g_trade[2].enabled                  = true;
g_trade[3].enabled                  = false;
to change to 
g_trade[0].enabled                  = false;
g_trade[1].enabled                  = false;
g_trade[2].enabled                  = false;
g_trade[3].enabled                  = false;

if I Set set_state :true and range_mode = false and array_mode_list = [0, 2], i expect
g_trade[0].enabled                  = true;
g_trade[2].enabled                  = true;
you don't need to preserve white space, but you can.
g_trade[0].enabled = true;
g_trade[2].enabled = true;

=end

MQ5_FILE = "./smashelito.mq5"
content = File.read(MQ5_FILE)

range_mode = true # false means use array_mode_list
range = [0, 12] # inclusive
array_mode_list = [0, 1, 2, 3, 6]

set_state = :true # :true or :false
state_str = set_state.to_s

# Build list of indices to modify
indices =
  if range_mode
    (range[0]..range[1]).to_a
  else
    array_mode_list
  end

# ---- STEP 1: VALIDATION (fail fast) ----
missing = []

indices.each do |idx|
  unless content.match?(/g_trade\[#{idx}\]\.enabled\s*=\s*(true|false);/)
    missing << idx
  end
end

if missing.any?
  puts "ERROR: Missing g_trade entries for indices: #{missing.inspect}"
  puts "No changes were made."
  exit(1)
end

# ---- STEP 2: SAFE REPLACEMENT ----
pattern = /g_trade\[(\d+)\]\.enabled\s*=\s*(true|false);/

updated = content.gsub(pattern) do |match|
  idx = $1.to_i

  if indices.include?(idx)
    "g_trade[#{idx}].enabled = #{state_str};"
  else
    match
  end
end

File.write(MQ5_FILE, updated)

puts "Updated indices: #{indices.inspect} -> #{state_str}"