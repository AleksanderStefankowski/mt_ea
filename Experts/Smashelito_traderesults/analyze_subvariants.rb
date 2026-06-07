#!/usr/bin/env ruby

require 'csv'
require 'set'
require_relative '../Smashelito/smash_mql5_algo_reader_lib'

FM = SmashMql5AlgoReader::FalgoMagic

# =========================================================
# CONFIG
# =========================================================

FILE_PATH = 'summary_tradeResults_all_days.tsv'

MINIMUM_TRADES_IN_GROUPING_FULL = 7
MINIMUM_TRADES_IN_GROUPING_ON = 4
MINIMUM_TRADES_IN_GROUPING_RTHafterIB = 7
MINIMUM_TRADES_IN_GROUPING_RTHIB = 4

MINIMUM_PROFITFACTOR = 2.75
MAXIMUM_PROFITFACTOR = 4.0
# Collect pf >= MIN (including above MAX). Per analysis_set + magic_prefix: anchor = max
# grp_trades among in-range rows; keep in-range + out-of-range rows with grp_trades == anchor.
# Profit Factor (PF)	Required Win Rate
# 6	85.71%
# 5	83.33%
# 4	80.00%
# 3	75.00%
# 2.75	73.33%

MAX_COMBINATION_SIZE = 4

TOP_RESULTS_TO_PRINT = 300
GROUPING_SAMPLEDATES_MAX = 20

SAVE_CSV_TO_FILE = true
SAVE_CSV_OUTPUT = 'analyze_subvariants_output.csv'
SAVE_CSV_ONLY_THE_SESSIONROWS_WITH_HIGHEST_TRADE_COUNT = true

# =========================================================






# Only these booleans may appear as =false gates in output/rules.
BOOLEAN_GATE_VARIABLES = %i[dayBrokePDH dayBrokePDL].freeze

# IBL/IBH/RTHH/RTHL reference gates only meaningful after IB hour (not ON or RTH-IB at open).
RTH_IB_REFERENCE_NAMES = %w[IBL IBH RTHH RTHL].freeze

ANALYSIS_SETS = [
  {
    name: 'full',
    session_filter: nil,
    exclude_rth_ib_vars: true
  },
  {
    name: 'ON',
    session_filter: 'ON',
    exclude_rth_ib_vars: true
  },
  {
    name: 'RTH-IB',
    session_filter: 'RTH-IB',
    exclude_rth_ib_vars: true
  },
  {
    name: 'RTH-afterIB',
    session_filter: 'RTH-afterIB',
    exclude_rth_ib_vars: false
  }
].freeze

# =========================================================
# HELPERS
# =========================================================

def minimum_trades_for_analysis_set(analysis_set_name)
  case analysis_set_name
  when 'full' then MINIMUM_TRADES_IN_GROUPING_FULL
  when 'ON' then MINIMUM_TRADES_IN_GROUPING_ON
  when 'RTH-afterIB' then MINIMUM_TRADES_IN_GROUPING_RTHafterIB
  when 'RTH-IB' then MINIMUM_TRADES_IN_GROUPING_RTHIB
  else
    raise "Unknown analysis set for minimum trades: #{analysis_set_name.inspect}"
  end
end

def pf_in_range?(pf)
  pf >= MINIMUM_PROFITFACTOR && pf <= MAXIMUM_PROFITFACTOR
end

def filter_results_by_pf_trade_count_anchor(results)
  results
    .group_by { |r| [r[:analysis_set], r[:magic_prefix]] }
    .flat_map do |_key, bucket|
      in_range = bucket.select { |r| pf_in_range?(r[:pf]) }
      anchor_trade_count = in_range.map { |r| r[:trades] }.max

      next [] if anchor_trade_count.nil?

      bucket.select do |r|
        pf_in_range?(r[:pf]) || r[:trades] == anchor_trade_count
      end
    end
end

def filter_results_to_session_highest_trade_count(results)
  max_trades_by_session =
    results
      .group_by { |r| r[:analysis_set] }
      .transform_values { |bucket| bucket.map { |r| r[:trades] }.max }

  results.select do |r|
    r[:trades] == max_trades_by_session[r[:analysis_set]]
  end
end

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

def winrate(trades)
  return 0 if trades.empty?

  wins =
    trades.count { |t| t[:profit].to_f > 0 }

  (wins.to_f / trades.size) * 100.0
end

def unique_trade_days(trades)
  trades
    .map { |t| t[:date] }
    .reject(&:empty?)
    .uniq
end

def trade_rate(trades, total_trading_days)
  return 0.0 if total_trading_days.zero?

  (unique_trade_days(trades).size.to_f / total_trading_days) * 100.0
end

def sample_start_times(trades, max_samples = GROUPING_SAMPLEDATES_MAX)
  trades
    .map { |t| t[:start_time] }
    .reject(&:empty?)
    .sort
    .first(max_samples)
    .join('; ')
end

def stringify_group(group_hash)
  group_hash.filter_map do |k, v|
    if ref_variable?(k)
      next unless v == true

      "#{k}=true"
    else
      "#{k}=#{v}"
    end
  end.join(' | ')
end

def ref_variable?(sym)
  s = sym.to_s
  s.start_with?('below_') || s.start_with?('above_')
end

def rth_ib_ref_variable?(sym)
  return false unless ref_variable?(sym)

  ref_name = sym.to_s.sub(/\A(below_|above_)/, '')
  RTH_IB_REFERENCE_NAMES.include?(ref_name)
end

def boolean_gate_variable?(sym)
  BOOLEAN_GATE_VARIABLES.include?(sym)
end

def group_key_for_trade(trade, vars)
  vars.map do |v|
    if ref_variable?(v)
      return nil unless trade.key?(v) && trade[v] == true

      [v, true]
    elsif boolean_gate_variable?(v)
      [v, trade[v].to_s.downcase == 'true']
    else
      [v, trade[v].to_s]
    end
  end
end

def variables_for_analysis_set(all_variables, analysis_set)
  vars = all_variables

  if analysis_set[:exclude_rth_ib_vars]
    vars = vars.reject { |v| rth_ib_ref_variable?(v) }
  end

  # full pools all sessions; session-specific sets have a constant session — never group by it.
  vars = vars.reject { |v| v == :session }

  vars
end

def trades_for_analysis_set(trades, analysis_set)
  session_filter = analysis_set[:session_filter]
  return trades if session_filter.nil?

  allowed =
    case session_filter
    when Array then session_filter
    else [session_filter]
    end

  trades.select { |t| allowed.include?(t[:session]) }
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

  FM.apply_trade_fields!(trade, magic)

  # =======================================================
  # STANDARD VARIABLES
  # =======================================================

  trade[:session] =
    row['sessionSent'].to_s.strip

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

  trade[:date] =
    row['date'].to_s.strip

  trade[:start_time] =
    row['startTime'].to_s.strip

  # =======================================================
  # REFERENCE POINTS
  # =======================================================

  refs_above =
    safe_split(row['referencePointsAbove'])

  refs_below =
    safe_split(row['referencePointsBelow'])

  # referencePointsAbove = ref price above trade level → level is below ref
  # referencePointsBelow = ref price below trade level → level is above ref
  refs_above.each do |ref|
    trade["below_#{ref}".to_sym] = true
  end

  refs_below.each do |ref|
    trade["above_#{ref}".to_sym] = true
  end

  rows << trade
end

puts "Loaded trades: #{rows.size}"

all_trading_day_count =
  unique_trade_days(rows).size

puts "Days with any trade: #{all_trading_day_count}"

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

      s.start_with?('below_') ||
      s.start_with?('above_')
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

ANALYSIS_SETS.each do |analysis_set|

  puts
  puts "#" * 80
  puts "ANALYSIS SET: #{analysis_set[:name]}"
  puts "#" * 80

  set_variables =
    variables_for_analysis_set(all_variables, analysis_set)

  puts "Variables in set: #{set_variables.size}"

  magic_groups.each do |magic_prefix, prefix_trades|

    trades =
      trades_for_analysis_set(prefix_trades, analysis_set)

    next if trades.empty?

    puts
    puts "-" * 80
    puts "MAGIC PREFIX #{magic_prefix} [#{analysis_set[:name]}]"
    puts "Trades: #{trades.size}"
    puts "-" * 80

    (1..MAX_COMBINATION_SIZE).each do |combo_size|

      puts
      puts "Combination size #{combo_size}"

      set_variables
        .combination(combo_size)
        .each do |vars|

        grouped =
          trades.group_by do |trade|
            group_key_for_trade(trade, vars)
          end

        grouped.each do |group_key, grouped_trades|

          next if group_key.nil?

          next if grouped_trades.size <
                  minimum_trades_for_analysis_set(analysis_set[:name])

          pf =
            profit_factor(grouped_trades)

          next if pf < MINIMUM_PROFITFACTOR

          results << {
            analysis_set: analysis_set[:name],
            magic_prefix: magic_prefix,
            vars: vars,
            values: group_key.to_h,
            trades: grouped_trades.size,
            pf: pf,
            net_profit: net_profit(grouped_trades),
            winrate: winrate(grouped_trades),
            group_trade_rate: trade_rate(grouped_trades, all_trading_day_count),
            grouping_sampledates: sample_start_times(grouped_trades)
          }
        end
      end
    end
  end
end

raw_result_count = results.size
results = filter_results_by_pf_trade_count_anchor(results)

puts
puts format(
  "PF range filter: %d -> %d groupings (kept in-range + out-of-range with same trade count as best in-range per magic prefix)",
  raw_result_count,
  results.size
)

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
      r[:analysis_set],
      r[:magic_prefix],
      r[:trades]
    ]
  end

# ---------------------------------------------------------
# PRINT
# ---------------------------------------------------------

analysis_set_names =
  grouped_results.keys
                 .map(&:first)
                 .uniq
                 .sort

analysis_set_names.each do |analysis_set_name|

  analysis_set_config =
    ANALYSIS_SETS.find { |s| s[:name] == analysis_set_name }

  magic_prefixes =
    grouped_results.keys
                   .select { |k| k[0] == analysis_set_name }
                   .map { |k| k[1] }
                   .uniq
                   .sort

  magic_prefixes.each do |magic_prefix|

    prefix_trades = magic_groups[magic_prefix] || []
    ungrouped_trades =
      trades_for_analysis_set(prefix_trades, analysis_set_config)
    ungrouped_pf = profit_factor(ungrouped_trades)
    ungrouped_trade_rate =
      trade_rate(ungrouped_trades, all_trading_day_count)

    puts
    puts format(
      "MAGIC PREFIX %s [%s] (ungrouped it has %d trades, %.2f profit factor, %.2f%% trade rate)",
      magic_prefix,
      analysis_set_name,
      ungrouped_trades.size,
      ungrouped_pf,
      ungrouped_trade_rate
    )
    puts

    trade_counts =
      grouped_results.keys
                     .select { |k| k[0] == analysis_set_name && k[1] == magic_prefix }
                     .map(&:last)
                     .uniq
                     .sort

    trade_counts.each do |trade_count|

      subset =
        grouped_results[
          [analysis_set_name, magic_prefix, trade_count]
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
          "PF: %.2f | WR: %.2f%% | NET: %.2f | TR: %.2f%%",
          r[:pf],
          r[:winrate],
          r[:net_profit],
          r[:group_trade_rate]
        )

        puts stringify_group(r[:values])
        puts "Sample start times: #{r[:grouping_sampledates]}"

        puts
      end
    end
  end
end

puts
total_groupings = results.size
puts "TOTAL VALID GROUPINGS: #{total_groupings}"

counts_by_set =
  results
    .group_by { |r| r[:analysis_set] }
    .transform_values(&:size)

{
  'full' => 'FULL',
  'ON' => 'ON',
  'RTH-IB' => 'RTHIB',
  'RTH-afterIB' => 'RTHAFTERIB'
}.each do |set_name, label|
  count = counts_by_set[set_name] || 0
  pct =
    if total_groupings.zero?
      0.0
    else
      (count.to_f / total_groupings) * 100.0
    end
  puts format('%s COUNT: %d (%.1f%% of total)', label, count, pct)
end

if SAVE_CSV_TO_FILE

  prefix_stats_by_set = {}
  ANALYSIS_SETS.each do |analysis_set|
    magic_groups.each do |magic_prefix, prefix_trades|
      set_trades =
        trades_for_analysis_set(prefix_trades, analysis_set)
      key = [analysis_set[:name], magic_prefix]
      prefix_stats_by_set[key] = {
        trade_count: set_trades.size,
        pf: profit_factor(set_trades),
        trade_rate: trade_rate(set_trades, all_trading_day_count)
      }
    end
  end

  csv_results = results
  if SAVE_CSV_ONLY_THE_SESSIONROWS_WITH_HIGHEST_TRADE_COUNT
    csv_results = filter_results_to_session_highest_trade_count(results)
    puts
    puts format(
      'CSV session highest trade count filter: %d -> %d rows',
      results.size,
      csv_results.size
    )
    csv_results
      .group_by { |r| r[:analysis_set] }
      .sort_by { |set_name, _| set_name }
      .each do |set_name, bucket|
        puts format('  %s: grp_trades=%d (%d rows)', set_name, bucket.first[:trades], bucket.size)
      end
  end

  csv_rows =
    csv_results.map do |r|
      prefix_stats =
        prefix_stats_by_set[[r[:analysis_set], r[:magic_prefix]]] ||
        { trade_count: 0, pf: 0.0, trade_rate: 0.0 }

      {
        analysis_set: r[:analysis_set],
        magic_prefix: r[:magic_prefix],
        magic_prefix_trades: prefix_stats[:trade_count],
        magic_prefix_pf: prefix_stats[:pf].round(2),
        magic_prefix_trade_rate: prefix_stats[:trade_rate].round(2),
        grp_trades: r[:trades],
        grp_pf: r[:pf].round(2),
        grp_traderate: r[:group_trade_rate].round(2),
        grp_winrate: r[:winrate].round(2),
        grp_net_profit: r[:net_profit].round(2),
        variable_count: r[:vars].size,
        variables: stringify_group(r[:values]),
        grouping_sampledates: r[:grouping_sampledates]
      }
    end

  csv_headers = [
    :analysis_set,
    :magic_prefix,
    :magic_prefix_trades,
    :magic_prefix_pf,
    :magic_prefix_trade_rate,
    :grp_trades,
    :grp_pf,
    :grp_traderate,
    :grp_winrate,
    :grp_net_profit,
    :variable_count,
    :variables,
    :grouping_sampledates
  ]

  CSV.open(SAVE_CSV_OUTPUT, 'w', write_headers: true, headers: csv_headers) do |out|
    csv_rows.each { |row| out << row.values_at(*csv_headers) }
  end

  puts
  puts "Saved CSV: #{SAVE_CSV_OUTPUT} (#{csv_rows.size} rows)"
end

puts
puts "DONE"

system(
  'powershell -NoProfile -Command "Add-Type -AssemblyName PresentationCore; $player = New-Object System.Windows.Media.MediaPlayer; $player.Open((Get-Item \"alert.mp3\").FullName); $player.Play(); Start-Sleep -Seconds 2"'
)