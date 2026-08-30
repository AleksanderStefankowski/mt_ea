# frozen_string_literal: true

require 'csv'
require 'set'
require_relative 'alert_done_common'
require_relative 'analyze_algos_performance_common'
require_relative '../Aleksik_traderesults/analyze_traderate_common'

module AnalyzeAlgosReferencePointsCommon
  module_function

  REF_GROUP_SIZES = [1, 2].freeze
  UNGROUPED_REF_GROUP_SIZE = 0
  MAX_RATECUT = 1.0
  TIMEVSPROFIT_DECIMALS = AnalyzeAlgosPerformanceCommon::TIMEVSPROFIT_DECIMALS
  # Merge grouped rows with identical algo + ratecut + profitSumVSexposure + percentSum + tradesCount
  # into one row (union of ref points; mergedVariantCount > 1 when combined).
  MERGE_SAME_RESULTS = true

  OUTPUT_HEADERS =
    AnalyzeAlgosPerformanceCommon::CSV_HEADERS + %w[
      refGroupSize
      grpRefsAbove
      grpRefsBelow
      ratecut
      timeVSprofitVSratecut
      mergedVariantCount
    ].freeze

  def safe_split_refs(value)
    value.to_s.split(';').map(&:strip).reject(&:empty?)
  end

  def format_ref_list(refs)
    refs.sort.join(';')
  end

  def load_trades_with_refs(path)
    raw = File.read(path, encoding: 'bom|utf-8')
    table = CSV.parse(raw, headers: true, col_sep: ',')

    trades = []
    table.each do |row|
      algo_id = row['algoID'].to_s.strip
      next if algo_id.empty?

      start_time = AnalyzeAlgosPerformanceCommon.parse_mt_datetime(row['startTime'])
      end_time = AnalyzeAlgosPerformanceCommon.parse_mt_datetime(row['endTime'])
      sent_time = AnalyzeAlgosPerformanceCommon.parse_mt_datetime(row['sentTime'])

      trades << {
        algo_id: algo_id,
        date: row['date'].to_s.strip,
        sent_time: sent_time,
        start_time: start_time,
        end_time: end_time,
        duration_hours: AnalyzeAlgosPerformanceCommon.parse_float(row['durationHours']),
        profit_custom_with_roll:
          AnalyzeAlgosPerformanceCommon.parse_float(row['profit_custom_with_roll']) || 0.0,
        percent_increase_w_roll: AnalyzeAlgosPerformanceCommon.percent_increase_w_roll(row),
        mfe_w_roll: AnalyzeAlgosPerformanceCommon.parse_float(row['MFE_w_roll']),
        mae_w_roll: AnalyzeAlgosPerformanceCommon.parse_float(row['MAE_w_roll']),
        close_decision: row['close_decision'].to_s.strip,
        reason: row['reason'].to_s.strip,
        refs_above: safe_split_refs(row['referencePointsAbove']).to_set,
        refs_below: safe_split_refs(row['referencePointsBelow']).to_set
      }
    end

    trades
  end

  def trade_matches_ref_group?(trade, above_refs, below_refs)
    above_refs.all? { |ref| trade[:refs_above].include?(ref) } &&
      below_refs.all? { |ref| trade[:refs_below].include?(ref) }
  end

  def build_algo_ref_indices(algo_trades)
    above_counts = Hash.new(0)
    below_counts = Hash.new(0)
    above_pair_counts = Hash.new(0)
    below_pair_counts = Hash.new(0)
    cross_pair_counts = Hash.new(0)

    algo_trades.each do |trade|
      refs_above = trade[:refs_above].to_a.sort
      refs_below = trade[:refs_below].to_a.sort

      refs_above.each { |ref| above_counts[ref] += 1 }
      refs_below.each { |ref| below_counts[ref] += 1 }

      refs_above.combination(2) { |pair| above_pair_counts[pair] += 1 }
      refs_below.combination(2) { |pair| below_pair_counts[pair] += 1 }
      refs_above.product(refs_below) { |above_ref, below_ref| cross_pair_counts[[above_ref, below_ref]] += 1 }
    end

    {
      above_counts: above_counts,
      below_counts: below_counts,
      above_pair_counts: above_pair_counts,
      below_pair_counts: below_pair_counts,
      cross_pair_counts: cross_pair_counts
    }
  end

  def group_trade_count(indices, above_refs, below_refs)
    above_refs = above_refs.sort
    below_refs = below_refs.sort

    case [above_refs.size, below_refs.size]
    when [1, 0]
      indices[:above_counts][above_refs[0]]
    when [0, 1]
      indices[:below_counts][below_refs[0]]
    when [2, 0]
      indices[:above_pair_counts][above_refs]
    when [0, 2]
      indices[:below_pair_counts][below_refs]
    when [1, 1]
      indices[:cross_pair_counts][[above_refs[0], below_refs[0]]]
    else
      nil
    end
  end

  def select_group_trades(algo_trades, above_refs, below_refs)
    algo_trades.select do |trade|
      trade_matches_ref_group?(trade, above_refs, below_refs)
    end
  end

  def rounded_profit_sum_vs_exposure(value, decimals = TIMEVSPROFIT_DECIMALS)
    return nil if value.nil?

    AnalyzeAlgosPerformanceCommon.parse_float(
      AnalyzeAlgosPerformanceCommon.format_float(value, decimals)
    )
  end

  def skip_group_time_vs_profit?(group_trades, ungrouped_psve, group_timevsprofit_needs_to_be_better)
    return false unless group_timevsprofit_needs_to_be_better
    return false if ungrouped_psve.nil?

    group_psve = AnalyzeAlgosPerformanceCommon.profit_sum_vs_exposure(group_trades)
    return false if group_psve.nil?

    group_rounded = rounded_profit_sum_vs_exposure(group_psve)
    ungrouped_rounded = rounded_profit_sum_vs_exposure(ungrouped_psve)
    return false if group_rounded.nil? || ungrouped_rounded.nil?

    group_rounded <= ungrouped_rounded
  end

  def ref_group_definitions(algo_trades, group_size)
    above_refs = algo_trades.flat_map { |trade| trade[:refs_above].to_a }.uniq.sort
    below_refs = algo_trades.flat_map { |trade| trade[:refs_below].to_a }.uniq.sort
    groups = []

    case group_size
    when 1
      above_refs.each { |ref| groups << { above: [ref], below: [] } }
      below_refs.each { |ref| groups << { above: [], below: [ref] } }
    when 2
      above_refs.combination(2).each { |pair| groups << { above: pair, below: [] } }
      below_refs.combination(2).each { |pair| groups << { above: [], below: pair } }
      above_refs.product(below_refs).each do |above_ref, below_ref|
        groups << { above: [above_ref], below: [below_ref] }
      end
    else
      raise ArgumentError, "unsupported ref group size: #{group_size}"
    end

    groups
  end

  def profit_sum_vs_exposure_vs_ratecut(profit_sum_vs_exposure, ratecut)
    return nil if profit_sum_vs_exposure.nil? || ratecut.nil?

    profit_sum_vs_exposure * ratecut
  end

  def enrich_ref_group_row(row)
    psve = AnalyzeAlgosPerformanceCommon.parse_float(row[:profitSumVSexposure])
    ratecut = AnalyzeAlgosPerformanceCommon.parse_float(row[:ratecut])
    combined =
      if row[:refGroupSize] == UNGROUPED_REF_GROUP_SIZE
        nil
      else
        profit_sum_vs_exposure_vs_ratecut(psve, ratecut)
      end

    row.merge(
      timeVSprofitVSratecut:
        AnalyzeAlgosPerformanceCommon.format_float(combined, TIMEVSPROFIT_DECIMALS)
    )
  end

  def build_ungrouped_row(
    algo_id,
    algo_trades,
    pattern,
    global_first_date,
    global_last_date,
    global_trading_day_count,
    global_full_week_mondays
  )
    perf_row =
      AnalyzeAlgosPerformanceCommon.build_performance_row(
        algo_id,
        algo_trades,
        pattern,
        global_first_date,
        global_last_date,
        global_trading_day_count,
        global_full_week_mondays
      )

    enrich_ref_group_row(
      perf_row.merge(
        refGroupSize: UNGROUPED_REF_GROUP_SIZE,
        grpRefsAbove: '',
        grpRefsBelow: '',
        ratecut: AnalyzeAlgosPerformanceCommon.format_float(MAX_RATECUT, 4)
      )
    )
  end

  def merge_result_key(row)
    [
      row[:algoID].to_s,
      AnalyzeAlgosPerformanceCommon.format_float(
        AnalyzeAlgosPerformanceCommon.parse_float(row[:ratecut]), 4
      ),
      AnalyzeAlgosPerformanceCommon.format_float(
        rounded_profit_sum_vs_exposure(row[:profitSumVSexposure]), TIMEVSPROFIT_DECIMALS
      ),
      AnalyzeAlgosPerformanceCommon.format_float(
        AnalyzeAlgosPerformanceCommon.parse_float(row[:percentSum_w_roll]), 2
      ),
      row[:tradesCount].to_i
    ]
  end

  def merge_ref_group_cluster(cluster)
    return cluster.first if cluster.size == 1

    above_union =
      cluster.flat_map { |row| safe_split_refs(row[:grpRefsAbove]) }.uniq.sort
    below_union =
      cluster.flat_map { |row| safe_split_refs(row[:grpRefsBelow]) }.uniq.sort
    ref_count = above_union.size + below_union.size

    cluster.first.merge(
      refGroupSize: ref_count,
      grpRefsAbove: format_ref_list(above_union),
      grpRefsBelow: format_ref_list(below_union),
      mergedVariantCount: cluster.size
    )
  end

  def merge_equivalent_group_rows(rows, merge_same_results: MERGE_SAME_RESULTS)
    ungrouped, grouped =
      rows.partition { |row| row[:refGroupSize] == UNGROUPED_REF_GROUP_SIZE }
    return rows unless merge_same_results

    merged_grouped =
      grouped
      .group_by { |row| merge_result_key(row) }
      .values
      .map { |cluster| merge_ref_group_cluster(cluster) }

    ungrouped + merged_grouped
  end

  def stamp_merged_variant_counts!(rows)
    rows.each do |row|
      next if row.key?(:mergedVariantCount)

      row[:mergedVariantCount] =
        row[:refGroupSize] == UNGROUPED_REF_GROUP_SIZE ? '' : 1
    end
    rows
  end

  def build_ref_group_rows(
    algo_id,
    algo_trades,
    pattern,
    minimum_ratecut,
    group_timevsprofit_needs_to_be_better,
    global_first_date,
    global_last_date,
    global_trading_day_count,
    global_full_week_mondays
  )
    return [] if algo_trades.empty?

    algo_total = algo_trades.size
    ref_indices = build_algo_ref_indices(algo_trades)
    ungrouped_psve = AnalyzeAlgosPerformanceCommon.profit_sum_vs_exposure(algo_trades)
    ungrouped_row =
      build_ungrouped_row(
        algo_id,
        algo_trades,
        pattern,
        global_first_date,
        global_last_date,
        global_trading_day_count,
        global_full_week_mondays
      )
    rows = [ungrouped_row]

    REF_GROUP_SIZES.each do |group_size|
      ref_group_definitions(algo_trades, group_size).each do |group_def|
        above_refs = group_def[:above]
        below_refs = group_def[:below]

        group_count = group_trade_count(ref_indices, above_refs, below_refs)
        next if group_count.nil? || group_count.zero?

        ratecut = group_count.to_f / algo_total
        next if ratecut < minimum_ratecut

        group_trades = select_group_trades(algo_trades, above_refs, below_refs)
        next if group_trades.empty?

        next if skip_group_time_vs_profit?(
          group_trades,
          ungrouped_psve,
          group_timevsprofit_needs_to_be_better
        )

        perf_row =
          AnalyzeAlgosPerformanceCommon.build_performance_row(
            algo_id,
            group_trades,
            pattern,
            global_first_date,
            global_last_date,
            global_trading_day_count,
            global_full_week_mondays
          )

        rows << enrich_ref_group_row(
          perf_row.merge(
            refGroupSize: group_size,
            grpRefsAbove: format_ref_list(above_refs),
            grpRefsBelow: format_ref_list(below_refs),
            ratecut: AnalyzeAlgosPerformanceCommon.format_float(ratecut, 4)
          )
        )
      end
    end

    merged_rows = merge_equivalent_group_rows(rows)
    stamp_merged_variant_counts!(merged_rows)

    merged_rows.sort_by do |row|
      [
        row[:algoID].to_i,
        row[:refGroupSize].to_i,
        -AnalyzeAlgosPerformanceCommon.parse_float(row[:ratecut]).to_f,
        -AnalyzeAlgosPerformanceCommon.parse_float(row[:percentSum_w_roll]).to_f,
        row[:grpRefsAbove].to_s,
        row[:grpRefsBelow].to_s
      ]
    end
  end

  def print_group_row(row, algo_total_trades)
    trades_count = row[:tradesCount]
    ratecut_pct =
      (AnalyzeAlgosPerformanceCommon.parse_float(row[:ratecut]).to_f * 100).round(2)
    merged_note =
      if row[:mergedVariantCount].to_s.to_i > 1
        " mergedVariants=#{row[:mergedVariantCount]} refCount=#{row[:refGroupSize]} |"
      else
        ''
      end
    puts(
      "  refs above=#{row[:grpRefsAbove].empty? ? '-' : row[:grpRefsAbove]} " \
      "below=#{row[:grpRefsBelow].empty? ? '-' : row[:grpRefsBelow]} |" \
      "#{merged_note} " \
      "trades=#{trades_count}/#{algo_total_trades} ratecut=#{ratecut_pct}% | " \
      "percentSum=#{row[:percentSum_w_roll]} profit_avg=#{row[:avg_profit_custom_with_roll]} | " \
      "profitSumVSexposure=#{row[:profitSumVSexposure]} " \
      "#{row[:refGroupSize] == UNGROUPED_REF_GROUP_SIZE ? '' : "timeVSprofitVSratecut=#{row[:timeVSprofitVSratecut]} "}" \
      "traderate=#{row[:traderate]} wtraderate=#{row[:weekly_traderate]}"
    )
  end

  def row_meets_output_thresholds?(
    row,
    minimum_percent_sum_w_roll:,
    minimum_weekly_traderate:
  )
    if !minimum_percent_sum_w_roll.nil?
      percent_sum = AnalyzeAlgosPerformanceCommon.parse_float(row[:percentSum_w_roll])
      return false if percent_sum.nil? || percent_sum < minimum_percent_sum_w_roll
    end

    if !minimum_weekly_traderate.nil?
      weekly_traderate = AnalyzeAlgosPerformanceCommon.parse_float(row[:weekly_traderate])
      return false if weekly_traderate.nil? || weekly_traderate < minimum_weekly_traderate
    end

    true
  end

  def filter_output_rows(rows, minimum_percent_sum_w_roll:, minimum_weekly_traderate:)
    return rows if minimum_percent_sum_w_roll.nil? && minimum_weekly_traderate.nil?

    rows.select do |row|
      row_meets_output_thresholds?(
        row,
        minimum_percent_sum_w_roll: minimum_percent_sum_w_roll,
        minimum_weekly_traderate: minimum_weekly_traderate
      )
    end
  end

  def write_ref_group_rows(path, rows)
    CSV.open(path, 'w', write_headers: true, headers: OUTPUT_HEADERS) do |csv|
      rows.each do |row|
        csv << OUTPUT_HEADERS.map { |header| row[header.to_sym] }
      end
    end
  end

  def run(
    family_label:,
    pattern:,
    input_path:,
    output_path:,
    minimum_ratecut_percent:,
    group_timevsprofit_needs_to_be_better:,
    minimum_percent_sum_w_roll: nil,
    minimum_weekly_traderate: nil
  )
    minimum_ratecut = minimum_ratecut_percent / 100.0

    unless File.file?(input_path)
      warn "ERROR: input file not found: #{input_path}"
      exit 1
    end

    warn "Loading: #{input_path}"
    trades = load_trades_with_refs(input_path)
    if trades.empty?
      warn 'ERROR: no trades loaded.'
      exit 1
    end

    global_first_date, global_last_date, global_trading_day_count = trade_date_range(trades)
    global_full_week_mondays =
      countable_mon_fri_weeks_in_date_range(global_first_date, global_last_date)

    print_loaded_trade_span_summary(
      trade_count: trades.size,
      first_date: global_first_date,
      last_date: global_last_date,
      trading_day_count: global_trading_day_count,
      full_week_mondays: global_full_week_mondays,
      io: $stderr
    )

    trades_by_algo =
      trades
      .group_by { |trade| trade[:algo_id] }
      .sort_by { |algo_id, _| algo_id.to_i }

    all_rows = []

    puts
    puts "#{family_label} algo reference-point groups"
    puts "input: #{input_path}"
    puts "output: #{output_path}"
    puts "group sizes: #{UNGROUPED_REF_GROUP_SIZE} (ungrouped), #{REF_GROUP_SIZES.join(', ')}"
    puts "minimum ratecut: #{minimum_ratecut_percent}% (groups below this are skipped)"
    if group_timevsprofit_needs_to_be_better
      puts "GROUP_TIMEVSPROFIT_NEEDS_TO_BE_BETTER: skip groups with profitSumVSexposure <= ungrouped (after #{TIMEVSPROFIT_DECIMALS}-decimal rounding)"
    end
    if MERGE_SAME_RESULTS
      puts 'MERGE_SAME_RESULTS: merge grouped rows with identical algo/ratecut/profitSumVSexposure/percentSum/tradesCount (union refs; mergedVariantCount)'
    end
    unless minimum_percent_sum_w_roll.nil?
      puts "output excludes rows with percentSum_w_roll < #{minimum_percent_sum_w_roll}"
    end
    unless minimum_weekly_traderate.nil?
      puts "output excludes rows with weekly_traderate < #{minimum_weekly_traderate}"
    end
    puts 'ratecut = trades in group / all trades for that algo (0.00–1.00; console shows %)'
    puts 'timeVSprofitVSratecut = profitSumVSexposure × ratecut (tie-break: higher ratecut wins at same profitSumVSexposure)'
    puts

    trades_by_algo.each do |algo_id, algo_trades|
      algo_rows =
        build_ref_group_rows(
          algo_id,
          algo_trades,
          pattern,
          minimum_ratecut,
          group_timevsprofit_needs_to_be_better,
          global_first_date,
          global_last_date,
          global_trading_day_count,
          global_full_week_mondays
        )
      all_rows.concat(algo_rows)

      puts '=' * 80
      puts "ALGO #{algo_id} (#{algo_trades.size} trades)"
      puts '=' * 80

      ungrouped_rows = algo_rows.select { |row| row[:refGroupSize] == UNGROUPED_REF_GROUP_SIZE }
      puts
      puts "--- ungrouped (all trades) ---"
      if ungrouped_rows.empty?
        puts '(none)'
      else
        ungrouped_rows.each { |row| print_group_row(row, algo_trades.size) }
      end

      REF_GROUP_SIZES.each do |group_size|
        size_rows = algo_rows.select { |row| row[:refGroupSize] == group_size }
        puts
        puts "--- ref group size #{group_size} (#{size_rows.size} groups) ---"
        if size_rows.empty?
          puts '(none)'
        else
          size_rows.each { |row| print_group_row(row, algo_trades.size) }
        end
      end
      puts
    end

    output_rows =
      filter_output_rows(
        all_rows,
        minimum_percent_sum_w_roll: minimum_percent_sum_w_roll,
        minimum_weekly_traderate: minimum_weekly_traderate
      )

    write_ref_group_rows(output_path, output_rows)
    excluded_count = all_rows.size - output_rows.size
    warn "Wrote #{output_rows.size + 1} rows to #{output_path}"
    warn "Excluded #{excluded_count} rows from output (below percentSum_w_roll / weekly_traderate thresholds)" if excluded_count.positive?
    warn 'DONE'
    play_alert_done!
  end
end
