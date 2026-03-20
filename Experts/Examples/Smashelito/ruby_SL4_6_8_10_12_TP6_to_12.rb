require 'csv'
require 'time'

file_path = "summary_tradeResults_all_days.csv"

# =======================
# CONFIG
# =======================
PRINT_ALL_WINRATE = false
PRINT_ALL_GAIN    = true
PRINT_ALL_BE      = false

minimum_trades = 5
skip_results_with_winrate_between = [40, 60]  # in %

# =======================
# DATA STRUCTURE
# =======================
data = Hash.new { |h, k| h[k] = [] }
date_ranges = Hash.new { |h, k| h[k] = { min: nil, max: nil } }

def to_f_or_nil(val)
  return nil if val.nil? || val.strip.empty?
  val.to_f
end

def parse_date(val)
  return nil if val.nil? || val.strip.empty?
  Time.parse(val) rescue nil
end

# =======================
# STEP 1: detect SL/TP columns
# =======================
sl_cols = []
tp_cols = []

CSV.foreach(file_path, headers: true, col_sep: "\t") do |row|
  row.headers.each do |h|
    sl_cols << h if h.start_with?("SL") && !sl_cols.include?(h)
    tp_cols << h if h.start_with?("TP") && !tp_cols.include?(h)
  end
end

# =======================
# STEP 2: combinations
# =======================
all_combos = sl_cols.product(tp_cols)

puts "All possible TP/SL combinations: #{all_combos.inspect}"
puts "Count of possible combinations: #{all_combos.size}"

# =======================
# STEP 3: read CSV
# =======================
CSV.foreach(file_path, headers: true, col_sep: "\t") do |row|
  magic = row["magic"]
  next if magic.nil?

  trade_date = parse_date(row["startTime"] || row["date"])
  if trade_date
    if date_ranges[magic][:min].nil? || trade_date < date_ranges[magic][:min]
      date_ranges[magic][:min] = trade_date
    end
    if date_ranges[magic][:max].nil? || trade_date > date_ranges[magic][:max]
      date_ranges[magic][:max] = trade_date
    end
  end

  record = {}

  all_combos.each do |sl_col, tp_col|
    sl = to_f_or_nil(row[sl_col])
    tp = to_f_or_nil(row[tp_col])
    breakeven_c = to_f_or_nil(row["3c_30c_level_breakevenC"])

    if sl.nil? && tp.nil?
      record[[sl_col, tp_col]] = { skipped: true }
      next
    end

    profit_points =
      if tp && sl
        tp
      elsif tp && sl.nil?
        tp
      elsif sl && tp.nil?
        -sl
      end

    if profit_points
      record[[sl_col, tp_col]] = {
        profit_points: profit_points,
        breakeven_candle: breakeven_c
      }
    end
  end

  data[magic] << record
end

# =======================
# STEP 4: analysis
# =======================
data.each do |magic, trades|
  total_cases = trades.size * all_combos.size
  skipped_cases = trades.sum { |t| t.count { |_, v| v[:skipped] } }
  skipped_percent = (skipped_cases.to_f / total_cases * 100).round(1)

  min_d = date_ranges[magic][:min]
  max_d = date_ranges[magic][:max]

  min_str = min_d ? min_d.strftime("%Y-%m-%d") : "N/A"
  max_str = max_d ? max_d.strftime("%Y-%m-%d") : "N/A"

  puts "\nMagic number: #{magic} (total trades: #{trades.size}, range: #{min_str} → #{max_str}) ----------------------------"
  puts "Trades skipped (both SL & TP blank): #{skipped_cases} (#{skipped_percent}%)"

  combination_stats = Hash.new { |h, k| h[k] = { profits: [], breakeven_candles: [] } }

  trades.each do |trade|
    trade.each do |combo, vals|
      next if vals[:skipped]

      combination_stats[combo][:profits] << vals[:profit_points]

      if vals[:breakeven_candle]
        combination_stats[combo][:breakeven_candles] << vals[:breakeven_candle]
      end
    end
  end

  combo_results = combination_stats.map do |combo, vals|
    profits = vals[:profits]
    next if profits.empty?

    sample_size = profits.size
    next if sample_size < minimum_trades

    win_rate = profits.count { |p| p > 0 }.to_f / sample_size
    win_rate_pct = win_rate * 100

    # ✅ skip mid win-rate zone
    if win_rate_pct >= skip_results_with_winrate_between[0] &&
       win_rate_pct <= skip_results_with_winrate_between[1]
      next
    end

    avg_gain = profits.sum.to_f / sample_size

    breakevens = vals[:breakeven_candles]
    avg_breakeven = breakevens.empty? ? nil : (breakevens.sum.to_f / breakevens.size)

    {
      combo: combo,
      win_rate: win_rate,
      avg_gain: avg_gain,
      sample_size: sample_size,
      avg_breakeven: avg_breakeven
    }
  end.compact

  if combo_results.empty?
    puts "\nNo combinations meet filters (min_trades=#{minimum_trades}, skipped winrate #{skip_results_with_winrate_between})"
    next
  end

  # =======================
  # WIN RATE
  # =======================
  puts "\nTop combinations by avg win rate:"
  sorted = combo_results.sort_by { |c| -c[:win_rate] }
  list = PRINT_ALL_WINRATE ? sorted : sorted.first(5)

  puts PRINT_ALL_WINRATE ? "  (printing ALL #{sorted.size})" : "  (top 5)"

  list.each do |c|
    puts "  #{c[:combo]} => win rate: #{(c[:win_rate]*100).round(1)}%, avg gain: #{c[:avg_gain].round(2)}, samples: #{c[:sample_size]}, avg breakeven: #{c[:avg_breakeven]&.round(2)}"
  end

  # =======================
  # AVG GAIN
  # =======================
  puts "\nTop combinations by avg gain:"
  sorted = combo_results.sort_by { |c| -c[:avg_gain] }
  list = PRINT_ALL_GAIN ? sorted : sorted.first(5)

  puts PRINT_ALL_GAIN ? "  (printing ALL #{sorted.size})" : "  (top 5)"

  list.each do |c|
    puts "  #{c[:combo]} => avg gain: #{c[:avg_gain].round(2)}, win rate: #{(c[:win_rate]*100).round(1)}%, avg breakeven: #{c[:avg_breakeven]&.round(2)}"
  end

  # =======================
  # BREAKEVEN
  # =======================
  puts "\nTop combinations by earliest breakeven:"
  sorted = combo_results.select { |c| c[:avg_breakeven] }.sort_by { |c| c[:avg_breakeven] }
  list = PRINT_ALL_BE ? sorted : sorted.first(5)

  puts PRINT_ALL_BE ? "  (printing ALL #{sorted.size})" : "  (top 5)"

  list.each do |c|
    puts "  #{c[:combo]} => avg breakeven: #{c[:avg_breakeven].round(2)}, win rate: #{(c[:win_rate]*100).round(1)}%, avg gain: #{c[:avg_gain].round(2)}"
  end
end