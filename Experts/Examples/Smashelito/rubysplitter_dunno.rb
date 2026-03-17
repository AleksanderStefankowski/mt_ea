require "csv"
require "set"

# --- CONFIG ---
FILE = "summary_tradeResults_all_days.csv"

FILTER_KEYS = ["openGap_info","PD_trend","dayBrokePDH","dayBrokePDL"]

EXPORT_FILE = "rubysplitter_dunno_combo_summary_metrics.tsv"

MIN_TRADES = 4               # Minimum trades per magic number to consider a factor/combo for console output
SAVE_COMBO_MIN_TRADES = 3    # Minimum trades per magic number to save to file
EXCLUDE_WINRATE_MIN = 0.39   # Exclude factors/combos with winrate between 0.39 and 0.61
EXCLUDE_WINRATE_MAX = 0.61

# --- LOAD CSV ---
csv = CSV.read(FILE, headers: true, col_sep: "\t")

puts "Input configuration:"
puts "  MIN_TRADES (per magic number) = #{MIN_TRADES}"
puts "  SAVE_COMBO_MIN_TRADES = #{SAVE_COMBO_MIN_TRADES}"
puts "  FILTER_KEYS = #{FILTER_KEYS.join(", ")}"
puts "  EXCLUDE_WINRATE_MIN = #{EXCLUDE_WINRATE_MIN}, EXCLUDE_WINRATE_MAX = #{EXCLUDE_WINRATE_MAX}"
puts "Expanded rows count: #{csv.size}"

# ============================================================
# EXPAND REFERENCE POINTS
# ============================================================

def expand_rows(csv)
  expanded = []
  trade_id = 1

  csv.each do |row|
    above = (row["referencePointsAbove"] || "").split(";")
    below = (row["referencePointsBelow"] || "").split(";")

    above.each do |ref|
      expanded << {
        trade_id: trade_id,
        magic: row["magic"],
        direction: "above",
        ref: ref,
        profit: row["profit"].to_f,
        filters: FILTER_KEYS.map { |k| [k,row[k]] }.to_h
      }
    end

    below.each do |ref|
      expanded << {
        trade_id: trade_id,
        magic: row["magic"],
        direction: "below",
        ref: ref,
        profit: row["profit"].to_f,
        filters: FILTER_KEYS.map { |k| [k,row[k]] }.to_h
      }
    end

    trade_id += 1
  end

  expanded
end

expanded = expand_rows(csv)

# ============================================================
# COMBO ANALYSIS
# ============================================================

summary_by_magic = {}

expanded.group_by { |r| r[:magic] }.each do |magic, rows|
  grouped = rows.group_by { |r| r[:trade_id] }

  combos = Hash.new { |h,k| h[k] = [] }

  grouped.each do |trade_id, trade_rows|
    above = trade_rows.select { |r| r[:direction] == "above" }
    below = trade_rows.select { |r| r[:direction] == "below" }

    above.combination(2).each do |c|
      key = [
        "price-below",
        c[0][:ref],
        c[1][:ref],
        *FILTER_KEYS.map { |k| c[0][:filters][k] }
      ]
      combos[key] << c[0][:profit]
    end

    below.combination(2).each do |c|
      key = [
        "price-above",
        c[0][:ref],
        c[1][:ref],
        *FILTER_KEYS.map { |k| c[0][:filters][k] }
      ]
      combos[key] << c[0][:profit]
    end

    above.product(below).each do |c|
      key = [
        "price-betweenH-L",
        c[0][:ref],
        c[1][:ref],
        *FILTER_KEYS.map { |k| c[0][:filters][k] }
      ]
      combos[key] << c[0][:profit]
    end
  end

  summary_by_magic[magic] = combos
end

removed_single_count = 0
combo_rows = []

summary_by_magic.each do |magic, combos|
  combos.each do |key, profits|
    count = profits.size
    next if count < SAVE_COMBO_MIN_TRADES

    winrate = profits.count { |p| p > 0 } / count.to_f
    next if winrate >= EXCLUDE_WINRATE_MIN && winrate <= EXCLUDE_WINRATE_MAX

    avg = profits.sum / count.to_f

    combo_rows << [
      magic,
      key[0],
      key[1],
      key[2],
      *key[3..],
      count,
      winrate.round(3),
      avg.round(2)
    ]
  end
end

# sort by winrate descending
combo_rows.sort_by! { |r| -r[-2] }

CSV.open(EXPORT_FILE, "w", col_sep: "\t") do |out|
  out << [
    "magic",
    "combo_position",
    "ref1",
    "ref2",
    *FILTER_KEYS,
    "count",
    "winrate",
    "avg_profit"
  ]
  combo_rows.each { |row| out << row }
end

puts "\nRemoved #{removed_single_count} combo rows with count < #{SAVE_COMBO_MIN_TRADES}"
puts "Saved combo metrics → #{EXPORT_FILE}"

# ============================================================
# REFERENCE BASED EDGE SUMMARY — PER MAGIC NUMBER (compact columns)
# ============================================================

puts "\n=== STRATEGY EDGE SUMMARY (reference based) ==="
puts "Note: factors with winrate between #{EXCLUDE_WINRATE_MIN} and #{EXCLUDE_WINRATE_MAX} were excluded."

expanded.group_by { |r| r[:magic] }.each do |magic, rows|
  factor_stats = Hash.new { |h,k| h[k] = [] }

  rows.each do |r|
    factor = r[:direction] == "above" ? "price below #{r[:ref]}" : "price above #{r[:ref]}"
    factor_stats[factor] << r[:profit]
    r[:filters].each { |k,v| factor_stats["#{k}=#{v}"] << r[:profit] }
  end

  edges = factor_stats.map do |factor, profits|
    count = profits.size
    next if count < MIN_TRADES
    winrate = profits.count { |p| p > 0 } / count.to_f
    next if winrate >= EXCLUDE_WINRATE_MIN && winrate <= EXCLUDE_WINRATE_MAX
    { factor: factor, count: count, winrate: winrate }
  end.compact

  positive = edges.sort_by { |e| -e[:winrate] }.first(10)
  negative = edges.sort_by { |e| e[:winrate] }.first(10)

  # Print compact columns
  puts "\nMAGIC #{magic}"
  puts "%-45s | %-45s" % ["ALLOW FACTORS", "BAN FACTORS"]
  puts "-"*45 + "-|-" + "-"*45

  max_rows = [positive.size, negative.size].max
  (0...max_rows).each do |i|
    allow_str = positive[i] ? "#{(positive[i][:winrate]*100).round(1)}%, #{positive[i][:count]} trades, #{positive[i][:factor]}" : ""
    ban_str   = negative[i] ? "#{(negative[i][:winrate]*100).round(1)}%, #{negative[i][:count]} trades, #{negative[i][:factor]}" : ""
    puts "%-45s | %-45s" % [allow_str, ban_str]
  end
end