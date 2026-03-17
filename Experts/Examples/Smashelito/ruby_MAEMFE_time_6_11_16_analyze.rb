require 'csv'

file_path = "summary_tradeResults_all_days.csv"

data = Hash.new do |h, k|
  h[k] = {
    c6:  { mfe: [], mae: [] },
    c11: { mfe: [], mae: [] },
    c16: { mfe: [], mae: [] }
  }
end

def to_f(val)
  return nil if val.nil? || val.strip.empty?
  val.to_f
end

def avg(arr)
  return nil if arr.empty?
  arr.sum / arr.size
end

# Read CSV
CSV.foreach(file_path, headers: true, col_sep: "\t") do |row|
  magic = row["magic"]
  next if magic.nil?

  { c6: ["MFE_c6", "MAE_c6"],
    c11: ["MFE_c11", "MAE_c11"],
    c16: ["MFE_c16", "MAE_c16"] }.each do |key, (mfe_col, mae_col)|

    mfe = to_f(row[mfe_col])
    mae = to_f(row[mae_col])
    next if mfe.nil? || mae.nil?

    data[magic][key][:mfe] << mfe
    data[magic][key][:mae] << mae
  end
end

# Compute averages, efficiency, final rating, and print condensed output with outlier percentages
data.each do |magic, sets|
  sample_size = sets[:c6][:mfe].size
  puts "\n=== Magic: #{magic} (samples: #{sample_size}) ==="

  results = {}

  # Compute avg MFE, MAE, efficiency, outliers
  sets.each do |label, values|
    mfe_arr = values[:mfe]
    mae_arr = values[:mae]
    next if mfe_arr.empty?

    avg_mfe = avg(mfe_arr)
    avg_mae = avg(mae_arr).abs
    efficiency = avg_mfe / avg_mae

    # Top 3 MFE outliers with % vs average
    top_mfe = mfe_arr.max(3).map { |x| "#{x.round(2)} (+#{((x/avg_mfe - 1)*100).round(0)}%)" }
    # Worst 3 MAE outliers with % vs average
    worst_mae = mae_arr.min(3).map { |x| "#{x.round(2)} (#{((x.abs/avg_mae - 1)*100).round(0)}%)" }

    results[label] = {
      avg_mfe: avg_mfe,
      avg_mae: avg_mae,
      efficiency: efficiency,
      top_mfe: top_mfe,
      worst_mae: worst_mae
    }

    puts "\n#{label} #{label == :c6 ? '(baseline)' : ''}"
    puts "  avg reward: #{avg_mfe.round(2)}   avg risk: #{avg_mae.round(2)}    efficiency: #{efficiency.round(2)}"
    puts "  top MFE outliers: #{top_mfe.join(', ')}"
    puts "  worst MAE outliers: #{worst_mae.join(', ')}"
  end

  # Compute final rating (efficiency penalized by risk increase vs c6)
  base_mae = results[:c6][:avg_mae]
  results.each do |label, r|
    risk_factor = label == :c6 ? 1.0 : 1.0 + ((r[:avg_mae] - base_mae) / base_mae)
    r[:final_rating] = r[:efficiency] / risk_factor
  end

  # Print final rating
  puts "\nFinal rating (reward vs risk):"
  results.each do |label, r|
    puts "  #{label}: #{r[:final_rating].round(2)}"
  end
end