# frozen_string_literal: true

require 'csv'

module AnalyzeSubvariantsCsvCommon
  HEADERS = [
    :analysis_set,
    :min_trades_threshold,
    :magic_prefix,
    :magic_prefix_trades,
    :magic_prefix_pf,
    :magic_prefix_traderate,
    :magic_prefix_weekly_traderate,
    :grp_trades,
    :grp_pf,
    :grp_traderate,
    :grp_weekly_traderate,
    :grp_winrate,
    :grp_net_profit,
    :variable_count,
    :variables,
    :grouping_sampledates
  ].freeze

  module_function

  def annotate_min_trades_threshold(results)
    results.map do |r|
      next r if r.key?(:min_trades_threshold) && !r[:min_trades_threshold].nil?

      r.merge(min_trades_threshold: yield(r))
    end
  end

  def build_row(result, prefix_stats:, variables:, variable_count:)
    {
      analysis_set: result[:analysis_set],
      min_trades_threshold: result[:min_trades_threshold],
      magic_prefix: result[:magic_prefix],
      magic_prefix_trades: prefix_stats[:trade_count],
      magic_prefix_pf: prefix_stats[:pf].round(2),
      magic_prefix_traderate: prefix_stats[:trade_rate].round(2),
      magic_prefix_weekly_traderate: (prefix_stats[:weekly_trade_rate] || 0.0).round(2),
      grp_trades: result[:trades],
      grp_pf: result[:pf].round(2),
      grp_traderate: result[:group_trade_rate].round(2),
      grp_weekly_traderate: (result[:group_weekly_trade_rate] || 0.0).round(2),
      grp_winrate: result[:winrate].round(2),
      grp_net_profit: result[:net_profit].round(2),
      variable_count: variable_count,
      variables: variables,
      grouping_sampledates: result[:grouping_sampledates]
    }
  end

  def write_csv(path, rows)
    CSV.open(path, 'w', write_headers: true, headers: HEADERS) do |out|
      rows.each { |row| out << row.values_at(*HEADERS) }
    end
  end
end
