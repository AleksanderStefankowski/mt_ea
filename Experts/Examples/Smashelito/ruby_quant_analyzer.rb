require "csv"
require "set"

# --- CONFIG ---
FILE = "summary_tradeResults_all_days.csv"

FILTER_KEYS = ["openGap_info","PD_trend","dayBrokePDH","dayBrokePDL"]

EXPORT_FILE_FACTORS = "ruby_factor_trade_level_metrics.tsv"
EXPORT_FILE_SETUPS  = "ruby_factor_trade_setups.tsv"

MIN_TRADES_FACTORS = 5   # Minimum trades to analyze a factor (per magic number)
MIN_TRADES_SETUPS  = 2   # Minimum trades to analyze a setup (per magic number)

# --- LOAD CSV ---
csv = CSV.read(FILE, headers: true, col_sep: "\t")

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
# TRADE NORMALIZATION
# ============================================================

trade_groups = expanded.group_by { |r| r[:trade_id] }

trade_factor_stats = Hash.new { |h,k| h[k] = [] }
setup_dict = Hash.new { |h,k| h[k] = [] }

trade_groups.each do |trade_id, rows|
  magic = rows.first[:magic]
  profit = rows.first[:profit]

  # --- factors ---
  factors = Set.new
  rows.each do |r|
    factors.add(
      r[:direction] == "above" ?
      "price below #{r[:ref]}" :
      "price above #{r[:ref]}"
    )
    r[:filters].each { |k,v| factors.add("#{k}=#{v}") }
  end

  factors.each { |f| trade_factor_stats[[magic,f]] << profit }

  # --- setups ---
  above = rows.select { |r| r[:direction] == "above" }
  below = rows.select { |r| r[:direction] == "below" }

  above.combination(2).each { |c| setup_dict[[magic,"price-below",c[0][:ref],c[1][:ref]]] << [c[0][:filters], profit] }
  below.combination(2).each { |c| setup_dict[[magic,"price-above",c[0][:ref],c[1][:ref]]] << [c[0][:filters], profit] }
  above.product(below).each { |c| setup_dict[[magic,"price-betweenH-L",c[0][:ref],c[1][:ref]]] << [c[0][:filters], profit] }
end

# ============================================================
# FACTOR FILE
# ============================================================

factor_rows = []

trade_factor_stats.each do |(magic,factor), profits|
  count = profits.size
  next if count < MIN_TRADES_FACTORS

  winrate = (profits.count { |p| p>0 } / count.to_f).round(3)
  next if winrate >= 0.4 && winrate <= 0.6

  avg = (profits.sum / count).round(2)
  factor_rows << [magic, factor, count, winrate, avg]
end

factor_rows.sort_by! { |r| -r[3] }

CSV.open(EXPORT_FILE_FACTORS, "w", col_sep: "\t") do |out|
  out << ["magic","factor","count","winrate","avg_profit"]
  factor_rows.each { |r| out << r }
end

puts "Saved factor metrics → #{EXPORT_FILE_FACTORS}"

# ============================================================
# SETUPS FILE
# ============================================================

collapsed_setups = []

setup_dict.each do |(magic, setup_type, ref1, ref2), arr|
  next if arr.size < MIN_TRADES_SETUPS

  profits = arr.map { |a| a[1] }
  filter_hashes = arr.map { |a| a[0] }

  winrate = (profits.count { |p| p>0 } / profits.size.to_f).round(3)
  next if winrate >= 0.4 && winrate <= 0.6

  shared_filters = {}
  FILTER_KEYS.each do |k|
    vals = filter_hashes.map { |h| h[k] }
    shared_filters[k] = vals.uniq.size == 1 ? vals.first : ""
  end

  avg = (profits.sum / profits.size).round(2)

  row = [magic, setup_type, ref1, ref2]
  FILTER_KEYS.each { |k| row << shared_filters[k] }
  row += [profits.size, winrate, avg]

  collapsed_setups << row
end

collapsed_setups.sort_by! { |r| -r[-2] }

CSV.open(EXPORT_FILE_SETUPS, "w", col_sep: "\t") do |out|
  out << ["magic","setup_type","ref1","ref2"] + FILTER_KEYS + ["count","winrate","avg_profit"]
  collapsed_setups.each { |r| out << r }
end

puts "Saved collapsed strategy setups → #{EXPORT_FILE_SETUPS}"

# ============================================================
# CONSOLE OUTPUT — PER MAGIC
# ============================================================

puts
puts "=== STRATEGY EDGE SUMMARY — TRADE NORMALIZED (quant) ==="
puts
puts "Current settings (per magic number):"
puts "  MIN_TRADES_FACTORS = #{MIN_TRADES_FACTORS} → Minimum trades required to analyze a factor"
puts "  MIN_TRADES_SETUPS  = #{MIN_TRADES_SETUPS}  → Minimum trades required to analyze a setup"
puts "  Winrate filters: factors/setups with 40%-60% winrate are ignored"
puts

by_magic = factor_rows.group_by { |r| r[0] }

by_magic.each do |magic, rows|
  puts "MAGIC #{magic}"

  edges = rows.map { |r| {factor: r[1], count: r[2], winrate: r[3], avg: r[4]} }

  top = edges.select { |e| e[:winrate] > 0.7 }.sort_by { |e| -e[:winrate] }.first(3)
  bottom = edges.select { |e| e[:winrate] < 0.3 }.sort_by { |e| e[:winrate] }.first(3)

  if top.any?
    puts "ALLOW:"
    top.each do |e|
      puts "#{e[:factor]} | trades=#{e[:count]} | winrate=#{(e[:winrate]*100).round(1)}% | avg=#{e[:avg]}"
    end
  end

  if bottom.any?
    puts "BAN:"
    bottom.each do |e|
      puts "#{e[:factor]} | trades=#{e[:count]} | winrate=#{(e[:winrate]*100).round(1)}% | avg=#{e[:avg]}"
    end
  end

  puts
end