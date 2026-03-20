require "csv"
require "set"

# --- CONFIG ---
FILE = "summary_tradeResults_all_days.csv"
DELIMITER = "\t" # adjust if your CSV is comma separated

# --- HELPER METHODS ---
def calculate_stats(trades)
  total_trades = trades.size
  return nil if total_trades == 0

  net_profit   = trades.map { |t| t[:profit] }.sum
  gross_profit = trades.select { |t| t[:profit] > 0 }.map { |t| t[:profit] }.sum
  gross_loss   = trades.select { |t| t[:profit] < 0 }.map { |t| t[:profit] }.sum.abs
  profit_factor = gross_loss > 0 ? (gross_profit / gross_loss) : Float::INFINITY

  profit_trades_count = trades.count { |t| t[:profit] > 0 }
  loss_trades_count   = trades.count { |t| t[:profit] < 0 }

  profit_trades_pct = (profit_trades_count / total_trades.to_f * 100).round(1)
  loss_trades_pct   = (loss_trades_count / total_trades.to_f * 100).round(1)

  long_trades      = trades.select { |t| t[:type] == "DEAL_TYPE_BUY" }
  short_trades     = trades.select { |t| t[:type] == "DEAL_TYPE_SELL" }
  long_win_pct     = long_trades.size > 0 ? (long_trades.count { |t| t[:profit] > 0 } / long_trades.size.to_f * 100).round(1) : "N/A"
  short_win_pct    = short_trades.size > 0 ? (short_trades.count { |t| t[:profit] > 0 } / short_trades.size.to_f * 100).round(1) : "N/A"

  {
    total_trades: total_trades,
    net_profit: net_profit.round(2),
    gross_profit: gross_profit.round(2),
    gross_loss: gross_loss.round(2),
    profit_factor: profit_factor.round(2),
    profit_trades_pct: profit_trades_pct,
    loss_trades_pct: loss_trades_pct,
    long_win_pct: long_win_pct,
    short_win_pct: short_win_pct
  }
end

# --- LOAD CSV ---
trades = []
CSV.foreach(FILE, headers: true, col_sep: DELIMITER) do |row|
  trades << {
    magic: row["magic"],
    profit: row["profit"].to_f,
    type: row["type"]
  }
end

# --- OVERALL STATS ---
puts "\nOVERALL TRADES STATISTICS ---"
overall_stats = calculate_stats(trades)
overall_stats.each do |k,v|
  puts "%-20s : %s" % [k.to_s, v]
end

# --- PER MAGIC NUMBER STATS ---
puts "\nPER MAGIC NUMBER STATISTICS ---"
trades.group_by { |t| t[:magic] }.each do |magic, magic_trades|
  stats = calculate_stats(magic_trades)
  puts "\nMAGIC #{magic}"
  stats.each do |k,v|
    puts "%-20s : %s" % [k.to_s, v]
  end
end