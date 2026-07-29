# frozen_string_literal: true

require 'csv'
require 'date'
require 'set'
require 'rbconfig'
require 'open3'

module CompareVariableAnalysisLib
  module_function

  def read_csv(path)
    raw = File.read(path, encoding: 'bom|utf-8')
    CSV.parse(raw, headers: true)
  end

  def parse_float(value)
    text = value.to_s.strip
    return nil if text.empty?

    Float(text)
  rescue ArgumentError, TypeError
    nil
  end

  def format_percent(numerator, denominator)
    return 'n/a' if denominator.zero?

    format('%.1f%%', 100.0 * numerator / denominator)
  end

  def format_float(value, decimals = 3)
    return '' if value.nil?

    format("%.#{decimals}f", value)
  end

  def format_date(date)
    return '' if date.nil?

    date.strftime('%Y.%m.%d')
  end

  def average(values)
    nums = values.compact
    return nil if nums.empty?

    nums.sum.to_f / nums.size
  end

  def percent_better_than(better, worse)
    return nil if better.nil? || worse.nil? || worse.zero?

    ((better - worse) / worse.abs) * 100.0
  end

  def compare_variable_sort_key(value)
    text = value.to_s
    return [0, text.to_i, text] if text.match?(/\A-?\d+\z/)

    [1, text]
  end

  def better_than_worse_line(prefix:, field_name:, left_value:, left_avg:, right_value:, right_avg:, decimals: 3, label: nil, min_percent_diff: nil)
    return nil if left_avg.nil? || right_avg.nil?

    metric_prefix = label ? "#{label}: " : ''

    if left_avg == right_avg
      return nil if min_percent_diff

      return "#{prefix}#{metric_prefix}#{field_name}=#{left_value} and #{field_name}=#{right_value} tie " \
             "(#{format_float(left_avg, decimals)})"
    end

    if left_avg > right_avg
      better_value, better_avg = left_value, left_avg
      worse_value, worse_avg = right_value, right_avg
    else
      better_value, better_avg = right_value, right_avg
      worse_value, worse_avg = left_value, left_avg
    end

    pct = percent_better_than(better_avg, worse_avg)
    return nil if min_percent_diff && pct < min_percent_diff

    "#{prefix}#{metric_prefix}#{field_name}=#{better_value} (#{format_float(better_avg, decimals)}) is " \
      "#{format('%.1f%%', pct)} better than #{field_name}=#{worse_value} (#{format_float(worse_avg, decimals)})"
  end

  def config_signature_excluding(row, *exclude_headers)
    exclude = exclude_headers.map(&:to_s).to_set
    exclude.add('algo_id')
    row.headers
       .reject { |header| exclude.include?(header) }
       .map { |header| row[header].to_s }
       .join("\x1f")
  end

  def build_variable_compare_run(matched_rows, compare_variable, signature_exclude_variables: [])
    excluded = (['algo_id', compare_variable] + signature_exclude_variables).uniq
    groups = Hash.new { |hash, key| hash[key] = [] }
    matched_rows.each do |entry|
      signature = config_signature_excluding(entry[:config], *excluded)
      groups[signature] << entry
    end

    output_rows = []
    pairs = []
    paired_algo_ids = Set.new
    group_id = 0
    total_pairs = 0

    sorted_groups =
      groups.sort_by do |_signature, entries|
        entries.map { |entry| entry[:algo_id].to_i }.min
      end

    sorted_groups.each do |_signature, entries|
      next unless entries.size >= 2

      variable_values = entries.map { |entry| entry[:config][compare_variable].to_s }.uniq
      next if variable_values.size < 2

      group_id += 1
      pair_id = 0

      entries.combination(2).each do |left, right|
        next if left[:config][compare_variable].to_s == right[:config][compare_variable].to_s

        pair_id += 1
        total_pairs += 1
        paired_algo_ids << left[:algo_id]
        paired_algo_ids << right[:algo_id]
        pairs << { group_id: group_id, pair_id: pair_id, left: left, right: right }
        output_rows << merged_compare_row(group_id, pair_id, left[:config], left[:perf])
        output_rows << merged_compare_row(group_id, pair_id, right[:config], right[:perf])
      end
    end

    unpaired_id = 0
    matched_rows
      .reject { |entry| paired_algo_ids.include?(entry[:algo_id]) }
      .sort_by { |entry| entry[:algo_id].to_i }
      .each do |entry|
        unpaired_id += 1
        output_rows << merged_compare_row("unpaired-#{unpaired_id}", '', entry[:config], entry[:perf])
      end

    output_rows.sort_by! do |row|
      [
        compare_output_group_sort_key(row['group_id']),
        row['pair_id'].to_s.empty? ? 0 : row['pair_id'].to_i,
        row['perf_algoID'].to_i
      ]
    end

    {
      pairs: pairs,
      output_rows: output_rows,
      group_count: group_id,
      pair_count: total_pairs,
      unpaired_count: matched_rows.size - paired_algo_ids.size,
      unpaired_written: unpaired_id,
      paired_algo_ids: paired_algo_ids
    }
  end

  def merged_compare_row(group_id, pair_id, config_row, perf_row)
    out = { 'group_id' => group_id, 'pair_id' => pair_id }
    config_row.headers.each { |header| out["config_#{header}"] = config_row[header] }
    perf_row.headers.each { |header| out["perf_#{header}"] = perf_row[header] }
    out
  end

  def write_compare_pairs_csv(output_path, output_rows, compare_variable, closetrade_config_columns: [])
    leading_columns = [
      'group_id',
      'pair_id',
      "config_#{compare_variable}",
      'config_algo_id',
      'perf_avgDurationHours',
      'perf_timeVSprofit',
      'perf_percentSum_w_roll',
      *closetrade_config_columns.map { |column| "config_#{column}" }
    ]
    all_headers = output_rows.flat_map(&:keys).uniq
    headers = leading_columns + (all_headers - leading_columns).sort

    CSV.open(output_path, 'w', write_headers: true, headers: headers) do |csv|
      output_rows.each do |row|
        csv << headers.map { |header| row[header] }
      end
    end
  end

  def print_variable_compare_summary(compare_variable, perf_row_count, run_result)
    pairs = run_result[:pairs]
    paired_entries = paired_entries_from_pairs(pairs)

    puts "compare variable: #{compare_variable}"
    puts "grouping excludes: algo_id, #{compare_variable}, and the other compare variable"
    puts "algos in analyze_breakdown_algos_performance_output: #{perf_row_count}"
    puts "algos without a pair: #{run_result[:unpaired_count]} (#{format_percent(run_result[:unpaired_count], perf_row_count)} of all)"
    puts "groups found: #{run_result[:group_count]}"
    puts "pairs found: #{run_result[:pair_count]}"
    puts "unpaired groups written: #{run_result[:unpaired_written]}"

    compare_analysis_lines(pairs, compare_variable).each { |line| puts line }
  end

  def build_variable_pair_stats(pairs, compare_variable, perf_field)
    stats = Hash.new do |hash, key|
      hash[key] = { appearances: 0, wins: 0, ties: 0, missing: 0, values: [] }
    end

    pairs.each do |pair|
      left_value = pair[:left][:config][compare_variable].to_s
      right_value = pair[:right][:config][compare_variable].to_s
      left_metric = parse_float(pair[:left][:perf][perf_field])
      right_metric = parse_float(pair[:right][:perf][perf_field])

      stats[left_value][:appearances] += 1
      stats[right_value][:appearances] += 1

      if left_metric.nil? || right_metric.nil?
        stats[left_value][:missing] += 1
        stats[right_value][:missing] += 1
        next
      end

      stats[left_value][:values] << left_metric
      stats[right_value][:values] << right_metric

      if left_metric > right_metric
        stats[left_value][:wins] += 1
      elsif right_metric > left_metric
        stats[right_value][:wins] += 1
      else
        stats[left_value][:ties] += 1
        stats[right_value][:ties] += 1
      end
    end

    stats
  end

  def paired_entries_from_pairs(pairs)
    pairs.flat_map { |pair| [pair[:left], pair[:right]] }.uniq { |entry| entry[:algo_id] }
  end

  SECRET_TP_CONFIG_FIELD = 'secret_tp_range_percent'

  def secret_tp_zero?(entry)
    value = parse_float(entry[:config][SECRET_TP_CONFIG_FIELD])
    return true if value.nil?

    value.zero?
  end

  def pairs_for_secret_tp_group(pairs, zero_group:)
    pairs.select do |pair|
      left_zero = secret_tp_zero?(pair[:left])
      right_zero = secret_tp_zero?(pair[:right])
      zero_group ? (left_zero && right_zero) : (!left_zero && !right_zero)
    end
  end

  def metrics_for_entries(entries)
    {
      timeVSprofit: average(entries.map { |entry| parse_float(entry[:perf]['timeVSprofit']) }),
      percentSum_w_roll: average(entries.map { |entry| parse_float(entry[:perf]['percentSum_w_roll']) }),
      avgDurationHours: average(entries.map { |entry| parse_float(entry[:perf]['avgDurationHours']) }),
      tradesCount: average(entries.map { |entry| parse_float(entry[:perf]['tradesCount']) })
    }
  end

  def per_algo_averages_by_value(paired_entries, compare_variable, perf_field)
    paired_entries
      .group_by { |entry| entry[:config][compare_variable].to_s }
      .transform_values { |group| average(group.map { |entry| parse_float(entry[:perf][perf_field]) }) }
  end

  def variable_pair_stats_lines(label, compare_variable, stats, paired_entries, perf_field, show_avg_comparison: true, avg_decimals: 3, sort_key: nil, sort_by_avg: false, min_percent_diff: nil)
    sort_key ||= method(:compare_variable_sort_key)
    lines = ["#{label} higher in head-to-head pairs:"]
    return lines if stats.empty?

    per_algo_averages = per_algo_averages_by_value(paired_entries, compare_variable, perf_field)
    sorted_stats =
      if sort_by_avg
        stats.sort_by do |value, _|
          avg = per_algo_averages[value]
          [avg.nil? ? 1 : 0, -(avg || 0), value]
        end
      else
        stats.sort_by { |value, _| sort_key.call(value) }
      end

    sorted_stats.each do |value, row|
      comparable = row[:appearances] - row[:missing]
      avg = per_algo_averages[value]
      avg_text = show_avg_comparison ? ", avg #{label}=#{format_float(avg, avg_decimals)} (per algo)" : ''
      lines << "  #{compare_variable}=#{value}: #{row[:wins]}/#{comparable} " \
                "(#{format_percent(row[:wins], comparable)})#{avg_text}"
    end

    return lines unless show_avg_comparison

    sorted_values = per_algo_averages.keys.sort_by { |value| sort_key.call(value) }
    return lines if sorted_values.size < 2

    sorted_values.combination(2).each do |left_value, right_value|
      line = better_than_worse_line(
        prefix: '  ', field_name: compare_variable,
        left_value: left_value, left_avg: per_algo_averages[left_value],
        right_value: right_value, right_avg: per_algo_averages[right_value],
        decimals: avg_decimals, label: label, min_percent_diff: min_percent_diff
      )
      lines << line if line
    end

    lines
  end

  def perf_field_analysis_lines_with_secret_tp_split(label, perf_field, pairs, compare_variable, avg_decimals: 3, sort_key: nil, sort_by_avg: false, min_percent_diff: nil)
    line_opts = {}
    line_opts[:sort_key] = sort_key if sort_key
    line_opts[:sort_by_avg] = true if sort_by_avg
    line_opts[:min_percent_diff] = min_percent_diff if min_percent_diff
    lines = []
    lines.concat(variable_pair_stats_lines(label, compare_variable,
                                           build_variable_pair_stats(pairs, compare_variable, perf_field),
                                           paired_entries_from_pairs(pairs), perf_field,
                                           avg_decimals: avg_decimals, **line_opts))

    zero_secret_tp_pairs = pairs_for_secret_tp_group(pairs, zero_group: true)
    unless zero_secret_tp_pairs.empty?
      lines << ''
      lines.concat(variable_pair_stats_lines("#{label} group 0 secret TP", compare_variable,
                                             build_variable_pair_stats(zero_secret_tp_pairs, compare_variable, perf_field),
                                             paired_entries_from_pairs(zero_secret_tp_pairs), perf_field,
                                             avg_decimals: avg_decimals, **line_opts))
    end

    non_zero_secret_tp_pairs = pairs_for_secret_tp_group(pairs, zero_group: false)
    unless non_zero_secret_tp_pairs.empty?
      lines << ''
      lines.concat(variable_pair_stats_lines("#{label} group non 0 secret TP", compare_variable,
                                             build_variable_pair_stats(non_zero_secret_tp_pairs, compare_variable, perf_field),
                                             paired_entries_from_pairs(non_zero_secret_tp_pairs), perf_field,
                                             avg_decimals: avg_decimals, **line_opts))
    end

    lines
  end

  def compare_analysis_lines(pairs, compare_variable, sort_key: nil, sort_by_avg: false, min_percent_diff: nil, include_secret_tp_split: true)
    return ['(no pairs)'] if pairs.empty?

    line_opts = {}
    line_opts[:sort_key] = sort_key if sort_key
    line_opts[:sort_by_avg] = true if sort_by_avg
    line_opts[:min_percent_diff] = min_percent_diff if min_percent_diff
    paired_entries = paired_entries_from_pairs(pairs)
    lines = []
    lines.concat(variable_pair_stats_lines('perf_timeVSprofit', compare_variable,
                                           build_variable_pair_stats(pairs, compare_variable, 'timeVSprofit'),
                                           paired_entries, 'timeVSprofit', **line_opts))
    lines << ''
    if include_secret_tp_split
      lines.concat(perf_field_analysis_lines_with_secret_tp_split('perf_percentSum_w_roll', 'percentSum_w_roll',
                                                                  pairs, compare_variable, avg_decimals: 2,
                                                                  **line_opts))
      lines << ''
      lines.concat(perf_field_analysis_lines_with_secret_tp_split('perf_avgDurationHours', 'avgDurationHours',
                                                                  pairs, compare_variable, **line_opts))
      lines << ''
      lines.concat(perf_field_analysis_lines_with_secret_tp_split('perf_tradesCount', 'tradesCount',
                                                                  pairs, compare_variable, avg_decimals: 2,
                                                                  **line_opts))
    else
      lines.concat(variable_pair_stats_lines('perf_percentSum_w_roll', compare_variable,
                                             build_variable_pair_stats(pairs, compare_variable, 'percentSum_w_roll'),
                                             paired_entries, 'percentSum_w_roll', avg_decimals: 2, **line_opts))
      lines << ''
      lines.concat(variable_pair_stats_lines('perf_avgDurationHours', compare_variable,
                                             build_variable_pair_stats(pairs, compare_variable, 'avgDurationHours'),
                                             paired_entries, 'avgDurationHours', **line_opts))
      lines << ''
      lines.concat(variable_pair_stats_lines('perf_tradesCount', compare_variable,
                                             build_variable_pair_stats(pairs, compare_variable, 'tradesCount'),
                                             paired_entries, 'tradesCount', avg_decimals: 2, **line_opts))
    end
    lines
  end

  def unpaired_group?(group_id)
    group_id.to_s.start_with?('unpaired-')
  end

  def compare_output_group_sort_key(group_id)
    text = group_id.to_s
    if (match = text.match(/\Aunpaired-(\d+)\z/))
      [2, match[1].to_i]
    elsif text.match?(/\A\d+\z/)
      [0, text.to_i]
    else
      [1, text]
    end
  end

  def hash_from_prefixed_columns(row, prefix)
    row.headers.each_with_object({}) do |header, memo|
      next unless header.start_with?(prefix)

      memo[header.delete_prefix(prefix)] = row[header]
    end
  end

  def entry_from_compare_row(row, compare_variable)
    {
      algo_id: row["config_algo_id"].to_s,
      config: hash_from_prefixed_columns(row, 'config_'),
      perf: hash_from_prefixed_columns(row, 'perf_')
    }
  end

  def load_pairs_from_compare_csv(path, compare_variable)
    table = read_csv(path)
    config_col = "config_#{compare_variable}"

    pairs = []
    paired_rows = table.reject { |row| unpaired_group?(row['group_id']) }
    paired_rows.group_by { |row| [row['group_id'].to_s, row['pair_id'].to_s] }.each_value do |rows|
      next if rows.size < 2

      sorted_rows = rows.sort_by { |row| row['config_algo_id'].to_i }
      left = entry_from_compare_row(sorted_rows[0], compare_variable)
      right = entry_from_compare_row(sorted_rows[1], compare_variable)
      next if left[:config][compare_variable].to_s == right[:config][compare_variable].to_s

      pairs << { left: left, right: right }
    end

    tested_arguments =
      paired_rows
      .map { |row| row[config_col].to_s.strip }
      .reject(&:empty?)
      .uniq
      .sort_by { |value| compare_variable_sort_key(value) }

    [pairs, tested_arguments]
  end

  def pairs_for_pattern(pairs, pattern)
    pairs.select do |pair|
      pair[:left][:perf]['pattern'].to_s == pattern && pair[:right][:perf]['pattern'].to_s == pattern
    end
  end

  def metrics_by_argument(entries, compare_variable, tested_arguments)
    tested_arguments.to_h do |arg|
      group = entries.select { |entry| entry[:config][compare_variable].to_s == arg.to_s }
      [
        arg,
        {
          tradesCount: average(group.map { |entry| parse_float(entry[:perf]['tradesCount']) }),
          percentSum_w_roll: average(group.map { |entry| parse_float(entry[:perf]['percentSum_w_roll']) }),
          timeVSprofit: average(group.map { |entry| parse_float(entry[:perf]['timeVSprofit']) }),
          avgDurationHours: average(group.map { |entry| parse_float(entry[:perf]['avgDurationHours']) })
        }
      ]
    end
  end

  def perf_date_span(entries)
    dates =
      entries.flat_map do |entry|
        [Date.strptime(entry[:perf]['firstTradeDate'].to_s, '%Y.%m.%d'),
         Date.strptime(entry[:perf]['lastTradeDate'].to_s, '%Y.%m.%d')]
      rescue ArgumentError
        []
      end.compact
    return [nil, nil] if dates.empty?

    [dates.min, dates.max]
  end

  PERF_OUTPUT_TIMESTAMP_FILENAME = 'analyze_breakdown_algos_performance_output.timestamp'
  PERF_OUTPUT_MAX_AGE_SECONDS = 8 * 60

  def perf_output_timestamp_path(script_dir)
    File.join(script_dir, PERF_OUTPUT_TIMESTAMP_FILENAME)
  end

  def perf_output_generated_at(script_dir)
    path = perf_output_timestamp_path(script_dir)
    return nil unless File.file?(path)

    Integer(File.read(path, encoding: 'bom|utf-8').strip)
  rescue ArgumentError, TypeError
    nil
  end

  def perf_output_recent?(script_dir, max_age_seconds = PERF_OUTPUT_MAX_AGE_SECONDS)
    perf_path = File.join(script_dir, 'analyze_breakdown_algos_performance_output.csv')
    generated_at = perf_output_generated_at(script_dir)
    return false unless File.file?(perf_path) && generated_at

    Time.now.to_i - generated_at < max_age_seconds
  end

  def refresh_breakdown_algos_performance_output!(script_dir)
    if perf_output_recent?(script_dir)
      generated_at = perf_output_generated_at(script_dir)
      age_min = ((Time.now.to_i - generated_at) / 60.0).round(1)
      warn
      warn "Using recent analyze_breakdown_algos_performance_output*.csv " \
           "(generated #{age_min} min ago; skip refresh if < #{PERF_OUTPUT_MAX_AGE_SECONDS / 60} min)"
      warn
      return
    end

    perf_generator = File.join(script_dir, 'analyze_breakdown_algos_performance_to_csv.rb')
    warn
    warn "Refreshing analyze_breakdown_algos_performance_output*.csv via #{File.basename(perf_generator)}..."
    perf_output, perf_status = Open3.capture2e(RbConfig.ruby, perf_generator)
    warn perf_output unless perf_output.empty?
    unless perf_status.success? && perf_output.include?('RAN OK')
      warn "ERROR: #{File.basename(perf_generator)} did not finish successfully (expected RAN OK)"
      exit 1
    end
    warn
  end
end
