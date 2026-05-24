#!/usr/bin/env ruby

require 'csv'
require 'set'

# =========================================================
# CONFIG
# =========================================================

FILE_PATH = 'summary_tradeResults_all_days.tsv'

MINIMUM_TRADES_IN_GROUPING = 8

MINIMUM_PROFITFACTOR = 2.5

MAX_COMBINATION_SIZE = 4

TOP_RESULTS_TO_PRINT = 300

SAVE_CSV_TO_FILE = true
SAVE_CSV_OUTPUT = 'analyze_output.csv'

# =========================================================
# HELPERS
# =========================================================

def safe_split(str)
  return [] if str.nil?

  str
    .to_s
    .split(';')
    .map(&:strip)
    .reject(&:empty?)
end

def profit_factor(trades)
  profits =
    trades.map { |t| t[:profit].to_f }

  gross_profit =
    profits.select(&:positive?).sum

  gross_loss =
    profits.select(&:negative?).sum.abs

  return 999.0 if gross_loss.zero? && gross_profit > 0
  return 0.0 if gross_loss.zero?

  gross_profit / gross_loss
end

def net_profit(trades)
  trades.sum { |t| t[:profit].to_f }
end

def avg_trade(trades)
  return 0 if trades.empty?

  net_profit(trades) / trades.size.to_f
end

def winrate(trades)
  return 0 if trades.empty?

  wins =
    trades.count { |t| t[:profit].to_f > 0 }

  (wins.to_f / trades.size) * 100.0
end

def stringify_group(group_hash)
  group_hash.map do |k, v|
    "#{k}=#{v}"
  end.join(' | ')
end

# =========================================================
# LOAD FILE
# =========================================================

puts
puts "Loading file..."

raw =
  File.read(FILE_PATH, encoding: 'bom|utf-8')

csv =
  CSV.parse(
    raw,
    headers: true,
    col_sep: ","
  )

puts "Detected headers:"
puts csv.headers.inspect
puts

rows = []

csv.each do |row|

  magic =
    row['magic'].to_s.strip

  next if magic.empty?

  trade = {}

  # =======================================================
  # ROOT GROUP
  # =======================================================

  trade[:magic_prefix] =
    magic[0, 2]

  # =======================================================
  # DAY OF WEEK
  # 4th digit of magic
  # =======================================================

  dow_digit =
    magic[3]

  trade[:day_of_week] =
    case dow_digit
    when '1' then 'MON'
    when '2' then 'TUE'
    when '3' then 'WED'
    when '4' then 'THU'
    when '5' then 'FRI'
    else 'UNKNOWN'
    end

  # =======================================================
  # STANDARD VARIABLES
  # =======================================================

  trade[:session] =
    row['session'].to_s.strip

  trade[:levelTag] =
    row['levelTag'].to_s.strip

  trade[:openGap_info] =
    row['openGap_info'].to_s.strip

  trade[:PD_trend] =
    row['PD_trend'].to_s.strip

  trade[:dayBrokePDH] =
    row['dayBrokePDH'].to_s.strip

  trade[:dayBrokePDL] =
    row['dayBrokePDL'].to_s.strip

  trade[:profit] =
    row['profit'].to_f

  # =======================================================
  # REFERENCE POINTS
  # =======================================================

  refs_above =
    safe_split(row['referencePointsAbove'])

  refs_below =
    safe_split(row['referencePointsBelow'])

  refs_above.each do |ref|
    trade["above_#{ref}".to_sym] = true
  end

  refs_below.each do |ref|
    trade["below_#{ref}".to_sym] = true
  end

  rows << trade
end

puts "Loaded trades: #{rows.size}"

if rows.empty?
  puts
  puts "ERROR: No trades loaded."
  exit
end

# =========================================================
# VARIABLE DISCOVERY
# =========================================================

puts
puts "Discovering variables..."

base_variables = [
  :session,
  :levelTag,
  :openGap_info,
  :PD_trend,
  :dayBrokePDH,
  :dayBrokePDL,
  :day_of_week
]

dynamic_variables =
  rows
    .flat_map(&:keys)
    .uniq
    .select do |k|

      s = k.to_s

      s.start_with?('above_') ||
      s.start_with?('below_')
    end

all_variables =
  base_variables + dynamic_variables

puts "Base variables: #{base_variables.size}"
puts "Dynamic variables: #{dynamic_variables.size}"
puts "Total variables: #{all_variables.size}"

# =========================================================
# ROOT GROUPING
# =========================================================

magic_groups =
  rows.group_by { |r| r[:magic_prefix] }

puts
puts "Magic prefix groups:"

magic_groups.each do |k, v|
  puts "#{k} => #{v.size} trades"
end

results = []

# =========================================================
# ANALYSIS
# =========================================================

puts
puts "Starting analysis..."

magic_groups.each do |magic_prefix, trades|

  puts
  puts "=" * 80
  puts "MAGIC PREFIX #{magic_prefix}"
  puts "Trades: #{trades.size}"
  puts "=" * 80

  (1..MAX_COMBINATION_SIZE).each do |combo_size|

    puts
    puts "Combination size #{combo_size}"

    all_variables
      .combination(combo_size)
      .each do |vars|

      grouped =
        trades.group_by do |trade|

          vars.map do |v|

            value =
              trade.key?(v) ? trade[v] : false

            [v, value]
          end

        end

      grouped.each do |group_key, grouped_trades|

        next if grouped_trades.size <
                MINIMUM_TRADES_IN_GROUPING

        pf =
          profit_factor(grouped_trades)

        next if pf < MINIMUM_PROFITFACTOR

        results << {
          magic_prefix: magic_prefix,
          vars: vars,
          values: group_key.to_h,
          trades: grouped_trades.size,
          pf: pf,
          net_profit: net_profit(grouped_trades),
          avg_trade: avg_trade(grouped_trades),
          winrate: winrate(grouped_trades)
        }
      end
    end
  end
end

# =========================================================
# SORT RESULTS
# =========================================================

puts
puts "Sorting results..."

results.sort_by! do |r|
  [
    -r[:pf],
    -r[:net_profit],
    -r[:trades]
  ]
end
# =========================================================
# OUTPUT
# =========================================================

puts
puts "FINAL RESULTS"
puts

# ---------------------------------------------------------
# GROUP RESULTS
# magic_prefix -> trades_count
# ---------------------------------------------------------

grouped_results =
  results.group_by do |r|
    [
      r[:magic_prefix],
      r[:trades]
    ]
  end

# ---------------------------------------------------------
# PRINT
# ---------------------------------------------------------

magic_prefixes =
  grouped_results.keys
                 .map(&:first)
                 .uniq
                 .sort

magic_prefixes.each do |magic_prefix|

  ungrouped_trades = magic_groups[magic_prefix] || []
  ungrouped_pf = profit_factor(ungrouped_trades)

  puts
  puts format(
    "MAGIC PREFIX %s (ungrouped it has %d trades, %.2f profit factor)",
    magic_prefix,
    ungrouped_trades.size,
    ungrouped_pf
  )
  puts

  trade_counts =
    grouped_results.keys
                   .select { |k| k[0] == magic_prefix }
                   .map(&:last)
                   .uniq
                   .sort

  trade_counts.each do |trade_count|

    subset =
      grouped_results[
        [magic_prefix, trade_count]
      ]

    next if subset.nil? || subset.empty?

    sorted_subset =
      subset.sort_by do |r|
        [
          -r[:pf],
          -r[:net_profit]
        ]
      end

    top_results =
      sorted_subset.first(3)

    puts "TOP RESULTS WITH #{trade_count} TRADES"
    puts

    top_results.each_with_index do |r, idx|

      puts "##{idx + 1}"

      puts format(
        "PF: %.2f | WR: %.2f%% | NET: %.2f | AVG: %.2f",
        r[:pf],
        r[:winrate],
        r[:net_profit],
        r[:avg_trade]
      )

      puts stringify_group(r[:values])

      puts
    end
  end
end

puts
puts "TOTAL VALID GROUPINGS: #{results.size}"

if SAVE_CSV_TO_FILE

  magic_prefix_stats =
    magic_groups.transform_values do |trades|
      {
        trade_count: trades.size,
        pf: profit_factor(trades)
      }
    end

  csv_rows =
    results.map do |r|
      prefix_stats =
        magic_prefix_stats[r[:magic_prefix]] || { trade_count: 0, pf: 0.0 }

      {
        magic_prefix: r[:magic_prefix],
        magic_prefix_trades: prefix_stats[:trade_count],
        magic_prefix_pf: prefix_stats[:pf].round(2),
        group_trades: r[:trades],
        group_pf: r[:pf].round(2),
        group_winrate: r[:winrate].round(2),
        group_net_profit: r[:net_profit].round(2),
        group_avg_trade: r[:avg_trade].round(2),
        variable_count: r[:vars].size,
        variables: stringify_group(r[:values])
      }
    end

  csv_headers = [
    :magic_prefix,
    :magic_prefix_trades,
    :magic_prefix_pf,
    :group_trades,
    :group_pf,
    :group_winrate,
    :group_net_profit,
    :group_avg_trade,
    :variable_count,
    :variables
  ]

  CSV.open(SAVE_CSV_OUTPUT, 'w', write_headers: true, headers: csv_headers) do |out|
    csv_rows.each { |row| out << row.values_at(*csv_headers) }
  end

  puts
  puts "Saved CSV: #{SAVE_CSV_OUTPUT} (#{csv_rows.size} rows)"
end

puts
puts "DONE"