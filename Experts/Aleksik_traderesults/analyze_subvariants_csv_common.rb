# frozen_string_literal: true

require 'csv'
require 'set'

module AnalyzeSubvariantsCsvCommon
  SESSION_SUPERSEDES_FULL = %w[ON RTH-IB RTH-afterIB].freeze
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

  def ref_variable?(sym)
    s = sym.to_s
    s.start_with?('below_') || s.start_with?('above_')
  end

  def values_fingerprint(values)
    values
      .sort_by { |k, _| k.to_s }
      .filter_map do |k, v|
        if ref_variable?(k)
          next unless v == true

          "#{k}=true"
        else
          "#{k}=#{v}"
        end
      end
      .join('|')
  end

  def grouping_row_fingerprint(result)
    [
      result[:magic_prefix].to_s,
      result[:trades],
      result[:pf].round(4),
      result[:grouping_sampledates].to_s,
      values_fingerprint(result[:values] || {})
    ]
  end

  def trades_for_analysis_set(trades, analysis_set)
    session_filter = analysis_set[:session_filter]
    return trades if session_filter.nil?

    allowed = session_filter.is_a?(Array) ? session_filter : [session_filter]
    trades.select { |t| allowed.include?(t[:session]) }
  end

  def trade_pool_fingerprint(trades)
    trades
      .map { |t| t[:start_time].to_s }
      .reject(&:empty?)
      .sort
      .join("\n")
  end

  def redundant_full_magic_prefixes(magic_groups, analysis_sets)
    full_config = analysis_sets.find { |s| s[:name].to_s == 'full' }
    return Set.new unless full_config

    redundant = Set.new
    magic_groups.each do |magic_prefix, prefix_trades|
      full_trades = trades_for_analysis_set(prefix_trades, full_config)
      full_fp = trade_pool_fingerprint(full_trades)
      next if full_fp.empty?

      superseded =
        SESSION_SUPERSEDES_FULL.any? do |session_name|
          session_config = analysis_sets.find { |s| s[:name].to_s == session_name }
          next false unless session_config

          session_trades = trades_for_analysis_set(prefix_trades, session_config)
          trade_pool_fingerprint(session_trades) == full_fp
        end

      redundant << magic_prefix if superseded
    end
    redundant
  end

  def remove_full_rows_redundant_with_session_sets(results, magic_groups:, analysis_sets:)
    session_row_fingerprints = Set.new
    results.each do |r|
      next unless SESSION_SUPERSEDES_FULL.include?(r[:analysis_set].to_s)

      session_row_fingerprints << grouping_row_fingerprint(r)
    end

    redundant_prefixes = redundant_full_magic_prefixes(magic_groups, analysis_sets)

    before = results.size
    filtered =
      results.reject do |r|
        next false unless r[:analysis_set].to_s == 'full'

        redundant_prefixes.include?(r[:magic_prefix]) ||
          session_row_fingerprints.include?(grouping_row_fingerprint(r))
      end

    [filtered, before - filtered.size, redundant_prefixes]
  end

  def drop_redundant_full_results!(results, magic_groups:, analysis_sets:)
    filtered, removed, redundant_prefixes =
      remove_full_rows_redundant_with_session_sets(
        results,
        magic_groups: magic_groups,
        analysis_sets: analysis_sets
      )

    if removed.positive?
      puts
      puts format(
        'Drop redundant full rows: %d -> %d (%d removed; %d magic_prefixes where full trade pool matches a session set)',
        results.size,
        filtered.size,
        removed,
        redundant_prefixes.size
      )
    end

    filtered
  end

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
