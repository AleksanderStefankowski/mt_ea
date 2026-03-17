require 'csv'

file_path = "summary_tradeResults_all_days.csv"

data = Hash.new { |h, k| h[k] = [] }

def to_f_or_nil(val)
  return nil if val.nil? || val.strip.empty?
  val.to_f
end

# Step 1: detect all SL/TP columns dynamically
sl_cols = []
tp_cols = []

CSV.foreach(file_path, headers: true, col_sep: "\t") do |row|
  row.headers.each do |h|
    sl_cols << h if h.start_with?("SL") && !sl_cols.include?(h)
    tp_cols << h if h.start_with?("TP") && !tp_cols.include?(h)
  end
end

# Step 2: create all possible SL/TP combinations
all_combos = sl_cols.product(tp_cols)

# Print once at the top
puts "All possible TP/SL combinations: #{all_combos.inspect}"
puts "Count of possible combinations: #{all_combos.size}"

# Step 3: read CSV and gather trades per magic number
CSV.foreach(file_path, headers: true, col_sep: "\t") do |row|
  magic = row["magic"]
  next if magic.nil?

  record = {}
  all_combos.each do |sl_col, tp_col|
    sl = to_f_or_nil(row[sl_col])
    tp = to_f_or_nil(row[tp_col])

    # count skipped combos separately
    if sl.nil? && tp.nil?
      record[[sl_col, tp_col]] = { skipped: true }
      next
    end

    # blank means loss if other exists
    profit_points = if tp && sl
                      tp
                    elsif tp && sl.nil?
                      tp
                    elsif sl && tp.nil?
                      -sl
                    end

    record[[sl_col, tp_col]] = { profit_points: profit_points } if profit_points
  end

  data[magic] << record
end

# Step 4: analysis per magic number
data.each do |magic, trades|
  total_cases = trades.size * all_combos.size
  skipped_cases = trades.sum { |t| t.count { |k, v| v[:skipped] } }
  skipped_percent = (skipped_cases.to_f / total_cases * 100).round(1)

  puts "\nMagic number: #{magic} (total trades: #{trades.size})"
  puts "Trades skipped (both SL & TP blank): #{skipped_cases} (#{skipped_percent}%)"

  combination_stats = Hash.new { |h, k| h[k] = { profits: [] } }

  trades.each do |trade|
    trade.each do |combo, vals|
      next if vals[:skipped]
      combination_stats[combo][:profits] << vals[:profit_points]
    end
  end

  combo_results = combination_stats.map do |combo, vals|
    profits = vals[:profits]
    next if profits.empty?
    combo_sample_size = profits.size
    win_rate = profits.count { |p| p > 0 }.to_f / combo_sample_size
    avg_gain = profits.sum.to_f / combo_sample_size
    { combo: combo, win_rate: win_rate, avg_gain: avg_gain, sample_size: combo_sample_size }
  end.compact

  # Top 5 by win rate
  puts "\nTop 5 combinations by avg win rate:"
  combo_results.sort_by { |c| -c[:win_rate] }.first(5).each do |c|
    puts "  #{c[:combo]} => win rate: #{(c[:win_rate]*100).round(1)}%, avg gain: #{c[:avg_gain].round(2)}, samples: #{c[:sample_size]}"
  end

  # Top 5 by avg gain
  puts "\nTop 5 combinations by avg gain (points):"
  combo_results.sort_by { |c| -c[:avg_gain] }.first(5).each do |c|
    puts "  #{c[:combo]} => win rate: #{(c[:win_rate]*100).round(1)}%, avg gain: #{c[:avg_gain].round(2)}, samples: #{c[:sample_size]}"
  end
end