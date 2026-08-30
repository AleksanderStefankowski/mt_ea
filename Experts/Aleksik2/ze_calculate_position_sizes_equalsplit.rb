# Configuration
DESIRED_TOTAL_MAX_EXPOSURE = 0.3
POSITION_SIZE_STEP         = 0.001

# Input
# Each strategy can have its own maximum number of open positions.
strategies = [
  { algoID: "10000111", percentsum: 165.37, max_positions: 5 },
  { algoID: "20000522", percentsum: 102.00, max_positions: 5 },
  { algoID: "30000006", percentsum: 130.50, max_positions: 5 },
]

# -------------------------------------------------------------------
# Calculate inverse-profit weights.
#
# Lower percentSum => larger position allocation.
# This makes the expected profit contribution approximately equal.
# -------------------------------------------------------------------

inverse_weights = strategies.map do |strategy|
  {
    algoID: strategy[:algoID],
    percentsum: strategy[:percentsum],
    max_positions: strategy[:max_positions],
    inverse_weight: 1.0 / strategy[:percentsum]
  }
end

total_inverse_weight =
  inverse_weights.sum { |s| s[:inverse_weight] }

# -------------------------------------------------------------------
# Allocate the desired TOTAL MAX EXPOSURE according to the ratios.
#
# target_max_exposure = total exposure × ratio
#
# position_size = target exposure / family's max positions
# -------------------------------------------------------------------

results = inverse_weights.map do |strategy|
  ratio =
    strategy[:inverse_weight] / total_inverse_weight

  target_max_exposure =
    DESIRED_TOTAL_MAX_EXPOSURE * ratio

  raw_position_size =
    target_max_exposure / strategy[:max_positions]

  {
    algoID: strategy[:algoID],
    max_positions: strategy[:max_positions],
    percentsum: strategy[:percentsum],
    ratio: ratio,
    raw_position_size: raw_position_size
  }
end

# -------------------------------------------------------------------
# Round position sizes to the configured step.
# -------------------------------------------------------------------

results.each do |result|
  result[:position_size] =
    (result[:raw_position_size] / POSITION_SIZE_STEP).round *
    POSITION_SIZE_STEP

  result[:max_exposure] =
    result[:position_size] * result[:max_positions]
end

# -------------------------------------------------------------------
# Output as a comment block.
# -------------------------------------------------------------------

separator = "-" * 82

puts "//Desired total max exposure: #{DESIRED_TOTAL_MAX_EXPOSURE}"
puts "//Position size step:         #{POSITION_SIZE_STEP}"
puts "//algoID          max pos   percentSum    ratio %    position size     max exposure"
puts "//#{separator}"

results.each do |result|
  puts format(
    "//%-12s %10d %12.2f %9.2f%% %16.3f %16.3f",
    result[:algoID],
    result[:max_positions],
    result[:percentsum],
    result[:ratio] * 100,
    result[:position_size],
    result[:max_exposure]
  )
end

puts "//#{separator}"

total_ratio =
  results.sum { |r| r[:ratio] }

total_max_exposure =
  results.sum { |r| r[:max_exposure] }

puts format(
  "//%-12s %10s %12s %9.2f%% %16s %16.3f",
  "TOTAL",
  "",
  "",
  total_ratio * 100,
  "",
  total_max_exposure
)