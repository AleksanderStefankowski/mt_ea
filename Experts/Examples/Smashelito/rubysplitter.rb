require "csv"
require "set"

# --- CONFIG ---
FILE = "summary_tradeResults_all_days.csv"

FILTER_KEYS = ["openGap_info","PD_trend","dayBrokePDH","dayBrokePDL"]

EXPORT_FILE = "ruby_combo_summary_metrics.tsv"
EXPORT_FILE_TRADE = "ruby_factor_trade_level_metrics.tsv"

MIN_TRADES = 5
MAGIC_TO_ANALYZE = "12"

# --- LOAD CSV ---
csv = CSV.read(FILE, headers: true, col_sep: "\t")

# --- EXPAND REFERENCE POINTS ---
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
        filters: {
          "openGap_info" => row["openGap_info"],
          "PD_trend" => row["PD_trend"],
          "dayBrokePDH" => row["dayBrokePDH"],
          "dayBrokePDL" => row["dayBrokePDL"]
        }
      }
    end

    below.each do |ref|
      expanded << {
        trade_id: trade_id,
        magic: row["magic"],
        direction: "below",
        ref: ref,
        profit: row["profit"].to_f,
        filters: {
          "openGap_info" => row["openGap_info"],
          "PD_trend" => row["PD_trend"],
          "dayBrokePDH" => row["dayBrokePDH"],
          "dayBrokePDL" => row["dayBrokePDL"]
        }
      }
    end

    trade_id += 1

  end

  expanded

end

expanded = expand_rows(csv)

puts "Expanded rows count: #{expanded.size}"

# ============================================================
# COMBO ANALYSIS
# ============================================================

summary_by_magic = {}

expanded.group_by { |r| r[:magic] }.each do |magic, rows|

  grouped = rows.group_by { |r| r[:trade_id] }

  combos = Hash.new { |h,k| h[k] = [] }

  grouped.each do |trade_id, trade_rows|

    above = trade_rows.select{|r| r[:direction]=="above"}
    below = trade_rows.select{|r| r[:direction]=="below"}

    above.combination(2).each do |c|

      key = [
        "price-below",
        c[0][:ref],
        c[1][:ref],
        *FILTER_KEYS.map{|k| c[0][:filters][k]}
      ]

      combos[key] << c[0][:profit]

    end

    below.combination(2).each do |c|

      key = [
        "price-above",
        c[0][:ref],
        c[1][:ref],
        *FILTER_KEYS.map{|k| c[0][:filters][k]}
      ]

      combos[key] << c[0][:profit]

    end

    above.product(below).each do |c|

      upper = c[0][:ref]
      lower = c[1][:ref]

      key = [
        "price-betweenH-L",
        upper,
        lower,
        *FILTER_KEYS.map{|k| c[0][:filters][k]}
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

    if count == 1
      removed_single_count += 1
      next
    end

    winrate = profits.count{|p| p>0}/count.to_f
    avg = profits.sum/count

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

# sort by winrate
combo_rows.sort_by! { |r| -r[-2] }

CSV.open(EXPORT_FILE,"w",col_sep:"\t") do |out|

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

puts "\nRemoved #{removed_single_count} combo rows with count=1"
puts "Saved combo metrics → #{EXPORT_FILE}"

# ============================================================
# REFERENCE BASED EDGE SUMMARY
# ============================================================

puts "\n=== STRATEGY EDGE SUMMARY (reference based, magic #{MAGIC_TO_ANALYZE}) ==="

rows = expanded.select{|r| r[:magic]==MAGIC_TO_ANALYZE}

factor_stats = Hash.new{|h,k| h[k]=[]}

rows.each do |r|

  if r[:direction]=="above"
    factor_stats["price below #{r[:ref]}"] << r[:profit]
  else
    factor_stats["price above #{r[:ref]}"] << r[:profit]
  end

  r[:filters].each do |k,v|
    factor_stats["#{k}=#{v}"] << r[:profit]
  end

end

edges = factor_stats.map do |factor,profits|

  count = profits.size
  next if count < MIN_TRADES

  winrate = profits.count{|p|p>0}/count.to_f

  {factor: factor, count: count, winrate: winrate}

end.compact

positive = edges.sort_by{|e| -e[:winrate]}
negative = edges.sort_by{|e| e[:winrate]}

puts "\nALLOW FACTORS"

positive.first(10).each do |e|
  puts "#{e[:factor]}"
  puts "  trades: #{e[:count]}"
  puts "  winrate: #{(e[:winrate]*100).round(1)}%"
  puts
end

puts "\nBAN FACTORS"

negative.first(10).each do |e|
  puts "#{e[:factor]}"
  puts "  trades: #{e[:count]}"
  puts "  winrate: #{(e[:winrate]*100).round(1)}%"
  puts
end

# ============================================================
# TRADE NORMALIZED ANALYSIS
# ============================================================

puts "\n=== STRATEGY EDGE SUMMARY — TRADE NORMALIZED (quant version) ==="

trade_groups = expanded.group_by{|r| r[:trade_id]}

trade_factor_stats = Hash.new{|h,k| h[k]=[]}

trade_groups.each do |trade_id, rows|

  magic = rows.first[:magic]
  next unless magic == MAGIC_TO_ANALYZE

  profit = rows.first[:profit]

  factors = Set.new

  rows.each do |r|

    if r[:direction]=="above"
      factors.add("price below #{r[:ref]}")
    else
      factors.add("price above #{r[:ref]}")
    end

    r[:filters].each do |k,v|
      factors.add("#{k}=#{v}")
    end

  end

  factors.each { |f| trade_factor_stats[f] << profit }

end

factor_rows = []

trade_factor_stats.each do |factor,profits|

  count = profits.size
  next if count < MIN_TRADES

  winrate = profits.count{|p|p>0}/count.to_f
  avg = profits.sum/count

  factor_rows << [factor, count, winrate.round(3), avg.round(2)]

end

# sort by winrate
factor_rows.sort_by! { |r| -r[2] }

CSV.open(EXPORT_FILE_TRADE,"w",col_sep:"\t") do |out|

  out << ["factor","count","winrate","avg_profit"]

  factor_rows.each { |r| out << r }

end

edges_trade = factor_rows.map do |r|
  {factor: r[0], count: r[1], winrate: r[2]}
end

positive = edges_trade.sort_by{|e| -e[:winrate]}
negative = edges_trade.sort_by{|e| e[:winrate]}

puts "\nALLOW FACTORS"

positive.first(10).each do |e|
  puts "#{e[:factor]}"
  puts "  trades: #{e[:count]}"
  puts "  winrate: #{(e[:winrate]*100).round(1)}%"
  puts
end

puts "\nBAN FACTORS"

negative.first(10).each do |e|
  puts "#{e[:factor]}"
  puts "  trades: #{e[:count]}"
  puts "  winrate: #{(e[:winrate]*100).round(1)}%"
  puts
end

puts "Saved trade-normalized metrics → #{EXPORT_FILE_TRADE}"