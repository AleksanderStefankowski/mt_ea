# Configuration
DESIRED_TOTAL_MAX_EXPOSURE = 0.2
POSITION_SIZE_STEP         = 0.001

algo_starting_with_1_weight = 5 # time
algo_starting_with_2_weight = 45 # bd
algo_starting_with_3_weight = 50 # level

# Input
# Each strategy can have its own maximum number of open positions.
strategies = [
  { algoID: "10000111", max_positions: 5 },
  { algoID: "20000522", max_positions: 5 },
  { algoID: "30000006", max_positions: 5 },
]

# -------------------------------------------------------------------
# Validate weights
# -------------------------------------------------------------------

weights = [
  algo_starting_with_1_weight,
  algo_starting_with_2_weight,
  algo_starting_with_3_weight
]

weights.each do |weight|
  unless weight.is_a?(Numeric) && weight >= 1 && weight <= 100
    raise "Each weight must be between 1 and 100"
  end
end

total_weight = weights.sum

unless total_weight >= 98 && total_weight <= 101
  raise "Total weights must be between 98 and 101. Current total: #{total_weight}"
end

# -------------------------------------------------------------------
# Assign target % based on the first digit of algoID.
#
# 10000111 -> 20%
# 20000522 -> 30%
# 30000006 -> 50%
#
# The weights are normalized so their total is exactly 100%.
# -------------------------------------------------------------------

results = strategies.map do |strategy|
  prefix = strategy[:algoID].to_s[0]

  target_weight =
    case prefix
    when "1"
      algo_starting_with_1_weight
    when "2"
      algo_starting_with_2_weight
    when "3"
      algo_starting_with_3_weight
    else
      raise "No weight configured for algoID #{strategy[:algoID]}"
    end

  target_percent =
    target_weight.to_f / total_weight * 100.0

  {
    algoID: strategy[:algoID],
    max_positions: strategy[:max_positions],
    target_percent: target_percent
  }
end

total_target_percent =
  results.sum { |r| r[:target_percent] }

# -------------------------------------------------------------------
# Allocate the desired total MAX exposure by family target % only.
# -------------------------------------------------------------------

results.each do |result|
  exposure_ratio =
    result[:target_percent] / total_target_percent

  result[:target_max_exposure] =
    DESIRED_TOTAL_MAX_EXPOSURE * exposure_ratio

  result[:raw_position_size] =
    result[:target_max_exposure] / result[:max_positions]

  result[:position_size] =
    (result[:raw_position_size] / POSITION_SIZE_STEP).round *
    POSITION_SIZE_STEP

  result[:max_exposure] =
    result[:position_size] * result[:max_positions]
end

# -------------------------------------------------------------------
# Output
# -------------------------------------------------------------------

separator = "-" * 88

puts "// ruby .\\ze_calculate_position_sizes_custom.rb"
puts "//Desired total max exposure: #{DESIRED_TOTAL_MAX_EXPOSURE}"
puts "//Position size step:         #{POSITION_SIZE_STEP}"
puts "//Weight total:               #{total_weight}"
puts "//algoID          max pos   target %    position size     max exposure"
puts "//#{separator}"

results.each do |result|
  puts format(
    "//%-12s %10d %9.2f%% %16.3f %16.3f",
    result[:algoID],
    result[:max_positions],
    result[:target_percent],
    result[:position_size],
    result[:max_exposure]
  )
end

puts "//#{separator}"

total_max_exposure =
  results.sum { |r| r[:max_exposure] }

puts format(
  "//%-12s %10s %9.2f%% %16s %16.3f",
  "TOTAL",
  "",
  results.sum { |r| r[:target_percent] },
  "",
  total_max_exposure
)
