#!/usr/bin/env ruby

require 'csv'
require_relative '../Aleksik/smash_mql5_algo_reader_lib'

FM = SmashMql5AlgoReader::FalgoMagic

# =========================================================
# CONFIG
# =========================================================

FILE_PATH = 'summary_tradeResults_all_days.tsv'
SESSION = 'full' # full, ON, RTH-IB, RTH-afterIB
MAGICPREFIX = 31
VARIABLES = 'above_PDO=true | above_midpoint=true | below_ONH=true | below_dayHighSoFar=true | openGap_info=unknown'

OUTPUT =
  format(
    'extract_list_of_variant_trades_%s_mp%s.tsv',
    SESSION,
    MAGICPREFIX
  )

# =========================================================
# ANALYSIS SETS (must match analyze_subvariants.rb)
# =========================================================

BOOLEAN_GATE_VARIABLES = %i[dayBrokePDH dayBrokePDL].freeze

ANALYSIS_SETS = [
  { name: 'full', session_filter: nil },
  { name: 'ON', session_filter: 'ON' },
  { name: 'RTH-IB', session_filter: 'RTH-IB' },
  { name: 'RTH-afterIB', session_filter: 'RTH-afterIB' }
].freeze

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

def ref_variable?(sym)
  s = sym.to_s
  s.start_with?('below_') || s.start_with?('above_')
end

def boolean_gate_variable?(sym)
  BOOLEAN_GATE_VARIABLES.include?(sym)
end

def parse_variables_string(str)
  str
    .split('|')
    .map(&:strip)
    .reject(&:empty?)
    .each_with_object({}) do |part, h|
      key, val = part.split('=', 2).map(&:strip)
      raise "Bad variable clause: #{part.inspect}" if key.nil? || val.nil?

      h[key.to_sym] = val
    end
end

def analysis_set_for_name(name)
  set = ANALYSIS_SETS.find { |s| s[:name] == name }
  raise "Unknown SESSION #{name.inspect}. Use: #{ANALYSIS_SETS.map { |s| s[:name] }.join(', ')}" unless set

  set
end

def session_allowed?(session, analysis_set)
  session_filter = analysis_set[:session_filter]
  return true if session_filter.nil?

  allowed =
    case session_filter
    when Array then session_filter
    else [session_filter]
    end

  allowed.include?(session)
end

def build_trade_from_row(row)
  magic = row['magic'].to_s.strip
  return nil if magic.empty?

  trade = {}

  FM.apply_trade_fields!(trade, magic)

  trade[:session] = row['sessionSent'].to_s.strip
  trade[:levelTag] = row['levelTag'].to_s.strip
  trade[:openGap_info] = row['openGap_info'].to_s.strip
  trade[:PD_trend] = row['PD_trend'].to_s.strip
  trade[:dayBrokePDH] = row['dayBrokePDH'].to_s.strip
  trade[:dayBrokePDL] = row['dayBrokePDL'].to_s.strip
  trade[:profit] = row['profit'].to_f
  trade[:date] = row['date'].to_s.strip
  trade[:start_time] = row['startTime'].to_s.strip

  safe_split(row['referencePointsAbove']).each do |ref|
    trade["below_#{ref}".to_sym] = true
  end

  safe_split(row['referencePointsBelow']).each do |ref|
    trade["above_#{ref}".to_sym] = true
  end

  trade
end

def trade_matches_group?(trade, group_values)
  group_values.all? do |key, expected|
    if ref_variable?(key)
      expected == 'true' && trade.key?(key) && trade[key] == true
    elsif boolean_gate_variable?(key)
      actual = trade[key].to_s.downcase == 'true'
      expected_bool = expected.to_s.downcase == 'true'
      actual == expected_bool
    else
      trade[key].to_s == expected.to_s
    end
  end
end

def profit_factor(trades)
  profits = trades.map { |t| t[:profit].to_f }

  gross_profit = profits.select(&:positive?).sum
  gross_loss = profits.select(&:negative?).sum.abs

  return 999.0 if gross_loss.zero? && gross_profit > 0
  return 0.0 if gross_loss.zero?

  gross_profit / gross_loss
end

def net_profit(trades)
  trades.sum { |t| t[:profit].to_f }
end

def winrate(trades)
  return 0 if trades.empty?

  wins = trades.count { |t| t[:profit].to_f > 0 }
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

def group_stats(trades, all_trading_day_count)
  {
    grp_trades: trades.size,
    grp_pf: profit_factor(trades).round(2),
    grp_traderate: trade_rate(trades, all_trading_day_count).round(2),
    grp_winrate: winrate(trades).round(2),
    grp_net_profit: net_profit(trades).round(2)
  }
end

# =========================================================
# MAIN
# =========================================================

analysis_set = analysis_set_for_name(SESSION)
magic_prefix = MAGICPREFIX.to_s
group_values = parse_variables_string(VARIABLES)

puts
puts "Loading #{FILE_PATH}..."
puts "SESSION=#{SESSION} MAGICPREFIX=#{magic_prefix}"
puts "VARIABLES=#{VARIABLES}"
puts

raw = File.read(FILE_PATH, encoding: 'bom|utf-8')
csv = CSV.parse(raw, headers: true, col_sep: ',')

all_trades = []
matched_rows = []
matched_trades = []

csv.each do |row|
  trade = build_trade_from_row(row)
  next if trade.nil?

  all_trades << trade
  next unless trade[:magic_prefix] == magic_prefix
  next unless session_allowed?(trade[:session], analysis_set)
  next unless trade_matches_group?(trade, group_values)

  matched_rows << row
  matched_trades << trade
end

all_trading_day_count = unique_trade_days(all_trades).size

CSV.open(OUTPUT, 'w', write_headers: true, headers: csv.headers) do |out|
  matched_rows.each { |row| out << row }
end

puts "Matched trades: #{matched_rows.size}"
puts "Wrote #{OUTPUT}"
puts

if matched_trades.any?
  stats = group_stats(matched_trades, all_trading_day_count)

  puts 'Group stats:'
  stats.each do |key, value|
    puts format('%-16s %s', key, value)
  end
  puts

  puts 'Sample start times:'
  matched_trades
    .map { |t| t[:start_time] }
    .sort
    .first(5)
    .each { |t| puts "  #{t}" }
else
  puts 'No trades matched this variant (check SESSION, MAGICPREFIX, VARIABLES).'
end

puts
puts "!!!!!!!!!!!!!!!!!!!! DID YOU REMEMBER TO SET CORRECT SESSION GROUPING? OTHERWISE EXTRACTS WRONG ORDERS !!!!!!!!!!!!"
puts 'DONE'
