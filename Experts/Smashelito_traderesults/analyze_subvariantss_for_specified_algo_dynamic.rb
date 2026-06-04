#!/usr/bin/env ruby

require 'csv'
require 'set'
require_relative '../Smashelito/smash_mql5_algo_reader_lib'

FM = SmashMql5AlgoReader::FalgoMagic

# =========================================================
# CONFIG
# =========================================================

FILE_PATH = 'summary_tradeResults_all_days.tsv'

# Only analyze these algo magic prefixes (first 2 digits of magic). Integers or strings ok.
MAGIC_PREFIXES_TO_ANALYZE = [14]

# Minimum grp size sweep: collect at min, then per session keep rows at highest threshold still non-empty.
TRADE_COUNT_RANGE = [4, 40].freeze

# Same session slice + PF + sample dates → one row; split variables on |, union uniq tokens.
MERGE_SAME_RESULTS = true

MINIMUM_PROFITFACTOR = 2.75
# Profit Factor (PF)	Winrate (WR)
# 0.2	16.67%
# 0.33	24.81%
# 0.5	33.33%
# 0.75	42.86%
# 1	50.00%
# 2	66.67%
# 2.5	71.43%
# 3	75.00%
# 3.5	77.78%
# 4	80.00%
# 4.5	81.82%
# 5	83.33%
# 6	85.71%
# 7	87.50%
MAXIMUM_PROFITFACTOR = 9999999999999999999999999.9
# Collect pf >= MIN (including above MAX). Per analysis_set + magic_prefix: anchor = max
# grp_trades among in-range rows; keep in-range + out-of-range rows with grp_trades == anchor.
# Profit Factor (PF)	Required Win Rate
# 6	85.71%
# 5	83.33%
# 4	80.00%
# 3	75.00%
# 2.75	73.33%

MAX_COMBINATION_SIZE = 4

GROUPING_SAMPLEDATES_MAX = 20

SAVE_CSV_TO_FILE = true
SAVE_CSV_OUTPUT = 'analyze_subvariantss_for_specified_algo_dynamic_o.csv'



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

def normalize_magic_prefix(value)
  value.to_s.strip.rjust(2, '0')
end

def configured_magic_prefixes
  MAGIC_PREFIXES_TO_ANALYZE.map { |p| normalize_magic_prefix(p) }.uniq.sort
end

def trade_count_thresholds
  TRADE_COUNT_RANGE.min.upto(TRADE_COUNT_RANGE.max).to_a
end

def results_for_analysis_set(results, analysis_set_name)
  results.select { |r| r[:analysis_set] == analysis_set_name }
end

def highest_threshold_with_results(set_results, thresholds)
  thresholds.reverse.find do |threshold|
    set_results.any? { |r| r[:trades] >= threshold }
  end
end

def results_at_threshold(set_results, threshold)
  set_results.select { |r| r[:trades] >= threshold }
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

def variable_tokens_from_group_string(group_string)
  group_string
    .split('|')
    .map(&:strip)
    .reject(&:empty?)
end

def variable_tokens_for_result(result)
  variable_tokens_from_group_string(stringify_group(result[:values]))
end

def merge_same_results_rows(results)
  return results unless MERGE_SAME_RESULTS

  results
    .group_by do |r|
      [
        r[:analysis_set],
        r[:magic_prefix],
        r[:pf].round(4),
        r[:grouping_sampledates]
      ]
    end
    .values
    .map do |bucket|
      base = bucket.first
      merged_variables =
        bucket
          .flat_map { |r| variable_tokens_for_result(r) }
          .uniq
          .sort

      base.merge(merged_variables: merged_variables)
    end
end

def variables_for_csv_row(result)
  tokens = result[:merged_variables] || variable_tokens_for_result(result)
  tokens.join(' | ')
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

raw =
  File.read(FILE_PATH, encoding: 'bom|utf-8')

csv =
  CSV.parse(
    raw,
    headers: true,
    col_sep: ","
  )

allowed_magic_prefixes = configured_magic_prefixes

if allowed_magic_prefixes.empty?
  puts 'ERROR: MAGIC_PREFIXES_TO_ANALYZE is empty.'
  exit 1
end

rows = []

csv.each do |row|

  magic =
    row['magic'].to_s.strip

  next if magic.empty?

  magic_prefix = magic[0, 2]
  next unless allowed_magic_prefixes.include?(magic_prefix)

  trade = {}

  FM.apply_trade_fields!(trade, magic)
  trade[:magic_prefix] = magic_prefix

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

all_trading_day_count =
  unique_trade_days(rows).size

if rows.empty?
  all_prefixes_in_file =
    csv
      .map { |row| row['magic'].to_s.strip }
      .reject(&:empty?)
      .map { |magic| magic[0, 2] }
      .uniq
      .sort

  puts
  puts "ERROR: No trades loaded for magic prefixes: #{allowed_magic_prefixes.join(', ')}"
  puts "Prefixes present in file: #{all_prefixes_in_file.join(', ')}"
  exit 1
end

# =========================================================
# VARIABLE DISCOVERY
# =========================================================

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

magic_groups =
  rows.group_by { |r| r[:magic_prefix] }

results = []
min_trades_collect = TRADE_COUNT_RANGE.min

# =========================================================
# ANALYSIS (collect at TRADE_COUNT_RANGE.min; threshold applied later)
# =========================================================

ANALYSIS_SETS.each do |analysis_set|
  set_variables = variables_for_analysis_set(all_variables, analysis_set)

  magic_groups.each do |magic_prefix, prefix_trades|
    trades = trades_for_analysis_set(prefix_trades, analysis_set)
    next if trades.empty?

    (1..MAX_COMBINATION_SIZE).each do |combo_size|
      set_variables.combination(combo_size).each do |vars|
        grouped =
          trades.group_by do |trade|
            group_key_for_trade(trade, vars)
          end

        grouped.each do |group_key, grouped_trades|
          next if group_key.nil?
          next if grouped_trades.size < min_trades_collect

          pf = profit_factor(grouped_trades)
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

results = filter_results_by_pf_trade_count_anchor(results)

results.sort_by! do |r|
  [-r[:pf], -r[:net_profit], -r[:trades]]
end

# =========================================================
# DYNAMIC THRESHOLD PER SESSION SLICE
# =========================================================

thresholds = trade_count_thresholds
csv_results = []
slice_summaries = []

ANALYSIS_SETS.each do |analysis_set|
  set_name = analysis_set[:name]
  set_results = results_for_analysis_set(results, set_name)
  threshold = highest_threshold_with_results(set_results, thresholds)

  if threshold.nil?
    slice_summaries << { set_name: set_name, threshold: nil, best: nil }
    next
  end

  kept = results_at_threshold(set_results, threshold)
  kept.each { |r| r[:min_trades_threshold] = threshold }
  csv_results.concat(kept)

  slice_summaries << {
    set_name: set_name,
    threshold: threshold,
    best: nil
  }
end

csv_results = merge_same_results_rows(csv_results)

slice_summaries.each do |summary|
  next if summary[:threshold].nil?

  set_rows =
    csv_results.select { |r| r[:analysis_set] == summary[:set_name] }

  summary[:best] =
    set_rows.max_by { |r| [r[:pf], r[:net_profit], r[:trades]] } unless set_rows.empty?
end

# =========================================================
# OUTPUT
# =========================================================

puts
slice_summaries.each do |summary|
  if summary[:best].nil?
    puts format('%s | no results', summary[:set_name])
    next
  end

  best = summary[:best]
  puts format(
    '%s | min_trades=%d | pf=%.2f | grp_trades=%d',
    summary[:set_name],
    summary[:threshold],
    best[:pf],
    best[:trades]
  )
end

if SAVE_CSV_TO_FILE
  prefix_stats_by_set = {}
  ANALYSIS_SETS.each do |analysis_set|
    magic_groups.each do |magic_prefix, prefix_trades|
      set_trades = trades_for_analysis_set(prefix_trades, analysis_set)
      key = [analysis_set[:name], magic_prefix]
      prefix_stats_by_set[key] = {
        trade_count: set_trades.size,
        pf: profit_factor(set_trades),
        trade_rate: trade_rate(set_trades, all_trading_day_count)
      }
    end
  end

  csv_rows =
    csv_results.map do |r|
      prefix_stats =
        prefix_stats_by_set[[r[:analysis_set], r[:magic_prefix]]] ||
        { trade_count: 0, pf: 0.0, trade_rate: 0.0 }

      {
        analysis_set: r[:analysis_set],
        min_trades_threshold: r[:min_trades_threshold],
        magic_prefix: r[:magic_prefix],
        magic_prefix_trades: prefix_stats[:trade_count],
        magic_prefix_pf: prefix_stats[:pf].round(2),
        magic_prefix_trade_rate: prefix_stats[:trade_rate].round(2),
        grp_trades: r[:trades],
        grp_pf: r[:pf].round(2),
        grp_traderate: r[:group_trade_rate].round(2),
        grp_winrate: r[:winrate].round(2),
        grp_net_profit: r[:net_profit].round(2),
        variable_count: (r[:merged_variables] || variable_tokens_for_result(r)).size,
        variables: variables_for_csv_row(r),
        grouping_sampledates: r[:grouping_sampledates]
      }
    end

  csv_headers = [
    :analysis_set,
    :min_trades_threshold,
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
end

# system(
#   'powershell -NoProfile -Command "Add-Type -AssemblyName PresentationCore; $player = New-Object System.Windows.Media.MediaPlayer; $player.Open((Get-Item \"alert.mp3\").FullName); $player.Play(); Start-Sleep -Seconds 2"'
# )