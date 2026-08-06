# frozen_string_literal: true

require 'csv'
require 'date'
require 'set'
require_relative '../Aleksik_traderesults/analyze_traderate_common'

module AnalyzeAlgosPerformanceCommon
  module_function

  CSV_HEADERS = %w[
    algoID
    pattern
    firstTradeDate
    lastTradeDate
    tradesCount
    tradedDaysCount
    max_notrades_streak
    avg_notrades_streak
    avgMFE_w_roll
    avgMAE_w_roll
    avgDurationHours
    longestDurationHours
    longestDurationDays
    avgFillDelaySeconds
    avg_profit_custom_with_roll
    gross_profit
    gross_loss
    profit_factor
    percentSum_w_roll
    avg_time_at_peak_exposure_hours
    timeVSprofit
    max_time_at_peak_exposure_hours
    max_time_at_peak_exposure_days
    traderate
    weekly_traderate
    avg_open_exposure
    peak_open_exposure
    main_close_reason
  ].freeze

  FLASHCRASH_TRADE_BEFORE = Date.new(2025, 2, 14)
  FLASHCRASH_TRADE_AFTER = Date.new(2025, 7, 1)
  FLASHCRASH_ANALYSIS_START = Date.new(2025, 1, 1)
  FLASHCRASH_ANALYSIS_END = Date.new(2025, 7, 17)

  MIN_DURATION_HOURS = 0.000001

  ALL_TRADE_SUMMARY_FILES = %w[
    summary_tradeResults_all_days_breakdown.tsv
    summary_tradeResults_all_days_time.tsv
    summary_tradeResults_all_days_level.tsv
  ].freeze

  def parse_mt_datetime(value)
    text = value.to_s.strip
    return nil if text.empty?

    DateTime.strptime(text, '%Y.%m.%d %H:%M:%S')
  rescue ArgumentError
    nil
  end

  def parse_float(value)
    text = value.to_s.strip
    return nil if text.empty?

    Float(text)
  rescue ArgumentError, TypeError
    nil
  end

  def format_float(value, decimals = 4)
    return '' if value.nil?

    format("%.#{decimals}f", value)
  end

  def format_date(date)
    return '' if date.nil?

    date.strftime('%Y.%m.%d')
  end

  def load_trades(path)
    raw = File.read(path, encoding: 'bom|utf-8')
    table = CSV.parse(raw, headers: true, col_sep: ',')

    trades = []
    table.each do |row|
      algo_id = row['algoID'].to_s.strip
      next if algo_id.empty?

      start_time = parse_mt_datetime(row['startTime'])
      end_time = parse_mt_datetime(row['endTime'])
      sent_time = parse_mt_datetime(row['sentTime'])
      trade_date = row['date'].to_s.strip

      trades << {
        algo_id: algo_id,
        date: trade_date,
        sent_time: sent_time,
        start_time: start_time,
        end_time: end_time,
        duration_hours: parse_float(row['durationHours']),
        profit_custom_with_roll: parse_float(row['profit_custom_with_roll']) || 0.0,
        percent_increase_w_roll: percent_increase_w_roll(row),
        mfe_w_roll: parse_float(row['MFE_w_roll']),
        mae_w_roll: parse_float(row['MAE_w_roll']),
        close_decision: row['close_decision'].to_s.strip,
        reason: row['reason'].to_s.strip
      }
    end

    trades
  end

  def load_trades_from_summary_files(script_dir, filenames = ALL_TRADE_SUMMARY_FILES)
    filenames.flat_map do |filename|
      path = File.join(script_dir, filename)
      next [] unless File.file?(path)

      load_trades(path)
    end
  end

  def percent_increase_w_roll(row)
    parsed = parse_float(row['percentIncrease_w_roll'])
    return parsed unless parsed.nil?

    price_start = parse_float(row['priceStart'])
    price_diff = parse_float(row['priceDiff'])
    return nil if price_start.nil? || price_diff.nil? || price_start <= 0.0

    100.0 * price_diff / price_start
  end

  def percent_sum(trades)
    trades.sum { |trade| trade[:percent_increase_w_roll].to_f }
  end

  def average(values)
    nums = values.compact
    return nil if nums.empty?

    nums.sum.to_f / nums.size
  end

  def fill_delay_seconds(trade)
    return nil unless trade[:sent_time] && trade[:start_time]

    (trade[:start_time] - trade[:sent_time]) * 86_400
  end

  def duration_hours_from_column(trade)
    duration = trade[:duration_hours]
    return nil if duration.nil? || duration.negative?

    duration
  end

  def trade_time_label(trade)
    start_s = trade[:start_time] ? trade[:start_time].strftime('%Y.%m.%d %H:%M:%S') : '(missing)'
    end_s = trade[:end_time] ? trade[:end_time].strftime('%Y.%m.%d %H:%M:%S') : '(missing)'
    "startTime=#{start_s} endTime=#{end_s}"
  end

  def duration_hours_from_times(trade)
    return nil unless trade[:start_time] && trade[:end_time]

    hours = (trade[:end_time] - trade[:start_time]) * 24
    hours.negative? ? nil : hours
  end

  def duration_hours_for_time_vs_profit!(trade)
    hours = duration_hours_from_times(trade)
    hours = trade[:duration_hours] if hours.nil?

    if hours.nil?
      raise "ERROR: timeVSprofit: durationHours missing for algo #{trade[:algo_id]} #{trade_time_label(trade)}"
    end
    if hours < MIN_DURATION_HOURS
      raise "ERROR: timeVSprofit: durationHours=#{hours} < #{MIN_DURATION_HOURS} for algo #{trade[:algo_id]} #{trade_time_label(trade)}"
    end

    hours
  end

  def time_vs_profit(trades)
    return nil if trades.empty?

    profits = trades.map { |trade| trade[:profit_custom_with_roll].to_f }
    hours_list = trades.map { |trade| duration_hours_for_time_vs_profit!(trade) }

    avg_profit = average(profits)
    avg_hours = average(hours_list)
    return nil if avg_profit.nil? || avg_hours.nil? || avg_hours < MIN_DURATION_HOURS

    avg_profit / avg_hours
  end

  def day_range(date)
    start = DateTime.new(date.year, date.month, date.day, 0, 0, 0)
    [start, start + 1]
  end

  def build_open_close_events(trades, range_start = nil, range_end = nil)
    events = []

    trades.each do |trade|
      start_time = trade[:start_time]
      end_time = trade[:end_time]
      next unless start_time && end_time && end_time > start_time

      start_t = start_time.to_time
      end_t = end_time.to_time
      next if range_end && start_t >= range_end
      next if range_start && end_t <= range_start

      clip_start = range_start ? [start_t, range_start].max : start_t
      clip_end = range_end ? [end_t, range_end].min : end_t
      next unless clip_end > clip_start

      events << [clip_start, 1]
      events << [clip_end, -1]
    end

    events.sort_by { |time, delta| [time, -delta] }
  end

  def max_concurrent_open(trades, range_start = nil, range_end = nil)
    events = build_open_close_events(trades, range_start, range_end)
    count = 0
    max_count = 0

    events.each do |_time, delta|
      count += delta
      max_count = [max_count, count].max
    end

    max_count
  end

  def peak_exposure_time_stats(trades)
    events = build_open_close_events(trades)
    return { peak: 0, max_hours: 0.0, avg_hours: 0.0 } if events.empty?

    count = 0
    peak = 0
    events.each { |_time, delta| count += delta; peak = [peak, count].max }
    return { peak: 0, max_hours: 0.0, avg_hours: 0.0 } if peak.zero?

    count = 0
    in_peak = false
    peak_start = nil
    peak_intervals = []

    events.each do |time, delta|
      count += delta
      if !in_peak && count == peak
        in_peak = true
        peak_start = time
      elsif in_peak && count < peak
        peak_intervals << (time - peak_start)
        in_peak = false
        peak_start = nil
      end
    end

    return { peak: peak, max_hours: 0.0, avg_hours: 0.0 } if peak_intervals.empty?

    max_seconds = peak_intervals.max
    avg_seconds = peak_intervals.sum.to_f / peak_intervals.size
    {
      peak: peak,
      max_hours: max_seconds / 3600.0,
      avg_hours: avg_seconds / 3600.0
    }
  end

  def open_days_for_algo(trades)
    trades
      .map { |trade| parse_trade_date(trade[:date]) }
      .compact
      .uniq
  end

  def avg_open_exposure(trades)
    days = open_days_for_algo(trades)
    return 0.0 if days.empty?

    daily_peaks =
      days.map do |date|
        day_start, day_end = day_range(date)
        max_concurrent_open(trades, day_start.to_time, day_end.to_time)
      end

    daily_peaks.sum.to_f / daily_peaks.size
  end

  def peak_open_exposure(trades)
    daily_peaks =
      open_days_for_algo(trades).map do |date|
        day_start, day_end = day_range(date)
        max_concurrent_open(trades, day_start.to_time, day_end.to_time)
      end

    return 0 if daily_peaks.empty?

    daily_peaks.max
  end

  def no_trades_streaks(trades, first_date, last_date)
    return [] if first_date.nil? || last_date.nil?

    trade_dates = countable_unique_trade_days(trades).to_set
    streaks = []
    current_streak = 0
    date = first_date

    while date <= last_date
      if countable_weekday?(date)
        if trade_dates.include?(date)
          streaks << current_streak if current_streak.positive?
          current_streak = 0
        else
          current_streak += 1
        end
      end
      date += 1
    end

    streaks << current_streak if current_streak.positive?
    streaks
  end

  def max_no_trades_streak(trades, first_date, last_date)
    streaks = no_trades_streaks(trades, first_date, last_date)
    streaks.empty? ? 0 : streaks.max
  end

  def avg_no_trades_streak(trades, first_date, last_date)
    streaks = no_trades_streaks(trades, first_date, last_date)
    return 0.0 if streaks.empty?

    streaks.sum.to_f / streaks.size
  end

  def trade_on_date(trade)
    parse_trade_date(trade[:date]) || trade[:start_time]&.to_date
  end

  def algo_eligible_for_flashcrash?(algo_trades)
    dates = algo_trades.filter_map { |trade| trade_on_date(trade) }
    return false if dates.empty?

    dates.any? { |date| date < FLASHCRASH_TRADE_BEFORE } &&
      dates.any? { |date| date > FLASHCRASH_TRADE_AFTER }
  end

  def trade_in_flashcrash_analysis_range?(trade)
    date = trade_on_date(trade)
    return false if date.nil?

    date >= FLASHCRASH_ANALYSIS_START && date <= FLASHCRASH_ANALYSIS_END
  end

  def trades_except_flashcrash_analysis_range(trades)
    trades.reject { |trade| trade_in_flashcrash_analysis_range?(trade) }
  end

  def flashcrash_global_context
    [
      FLASHCRASH_ANALYSIS_START,
      FLASHCRASH_ANALYSIS_END,
      countable_weekday_count_in_range(FLASHCRASH_ANALYSIS_START, FLASHCRASH_ANALYSIS_END),
      countable_mon_fri_weeks_in_date_range(FLASHCRASH_ANALYSIS_START, FLASHCRASH_ANALYSIS_END)
    ]
  end

  def build_performance_row(algo_id, trades, pattern, global_first_date, global_last_date,
    global_trading_day_count, global_full_week_mondays, aggregate_row: false)
    first_date, last_date, = trade_date_range(trades)
    durations = trades.filter_map { |t| duration_hours_from_column(t) }
    longest_duration_hours = durations.max
    gross_profit, gross_loss = gross_profit_and_loss_custom_with_roll(trades)

    row = {
      algoID: algo_id,
      pattern: pattern,
      firstTradeDate: format_date(first_date),
      lastTradeDate: format_date(last_date),
      tradesCount: trades.size,
      tradedDaysCount: countable_unique_trade_days(trades).size,
      max_notrades_streak: max_no_trades_streak(trades, global_first_date, global_last_date),
      avg_notrades_streak: format_float(avg_no_trades_streak(trades, global_first_date, global_last_date), 2),
      avgMFE_w_roll: format_float(average(trades.map { |t| t[:mfe_w_roll] }), 1),
      avgMAE_w_roll: format_float(average(trades.map { |t| t[:mae_w_roll] }), 1),
      avgDurationHours: format_float(average(durations), 2),
      longestDurationHours: format_float(longest_duration_hours, 2),
      longestDurationDays: format_float(longest_duration_hours.nil? ? nil : longest_duration_hours / 24.0, 2),
      avgFillDelaySeconds: format_float(average(trades.map { |t| fill_delay_seconds(t) }), 2),
      avg_profit_custom_with_roll: format_float(average(trades.map { |t| t[:profit_custom_with_roll] }), 2),
      gross_profit: format_float(gross_profit, 2),
      gross_loss: format_float(gross_loss, 2),
      profit_factor: format_profit_factor(profit_factor_from_gross(gross_profit, gross_loss)),
      percentSum_w_roll: format_float(percent_sum(trades), 2),
      timeVSprofit: format_float(time_vs_profit(trades), 3),
      traderate: format_float(trade_rate(trades, global_trading_day_count), 2),
      weekly_traderate: format_float(weekly_trade_rate(trades, global_full_week_mondays), 2),
      main_close_reason: main_close_reason_for_trades(trades)
    }

    if aggregate_row
      row[:avg_time_at_peak_exposure_hours] = ''
      row[:max_time_at_peak_exposure_hours] = ''
      row[:max_time_at_peak_exposure_days] = ''
      row[:avg_open_exposure] = ''
      row[:peak_open_exposure] = ''
    else
      exposure_stats = peak_exposure_time_stats(trades)
      row[:avg_time_at_peak_exposure_hours] = format_float(exposure_stats[:avg_hours], 2)
      row[:max_time_at_peak_exposure_hours] = format_float(exposure_stats[:max_hours], 2)
      row[:max_time_at_peak_exposure_days] = format_float(exposure_stats[:max_hours] / 24.0, 2)
      row[:avg_open_exposure] = format_float(avg_open_exposure(trades), 2)
      row[:peak_open_exposure] = peak_open_exposure(trades)
    end

    row
  end

  def build_rows(trades, global_first_date, global_last_date, global_trading_day_count,
    global_full_week_mondays, pattern_for_algo:)
    trades
      .group_by { |trade| trade[:algo_id] }
      .sort_by { |algo_id, _| algo_id.to_i }
      .map do |algo_id, algo_trades|
        build_performance_row(
          algo_id,
          algo_trades,
          pattern_for_algo.call(algo_id),
          global_first_date,
          global_last_date,
          global_trading_day_count,
          global_full_week_mondays
        )
      end
  end

  def build_all_aggregate_row(trades, global_first_date, global_last_date, global_trading_day_count,
    global_full_week_mondays, pattern:)
    return nil if trades.empty?

    build_performance_row(
      'ALL',
      trades,
      pattern,
      global_first_date,
      global_last_date,
      global_trading_day_count,
      global_full_week_mondays,
      aggregate_row: true
    )
  end

  def rows_with_family_all(algo_rows, all_trades, family_pattern, global_first_date, global_last_date,
    global_trading_day_count, global_full_week_mondays)
    all_row = build_all_aggregate_row(
      all_trades,
      global_first_date,
      global_last_date,
      global_trading_day_count,
      global_full_week_mondays,
      pattern: family_pattern
    )
    all_row ? [all_row] + algo_rows : algo_rows
  end

  def row_field(row, key)
    row[key.to_s] || row[key.to_sym]
  end

  def parse_row_float(row, key)
    parse_float(row_field(row, key)) || 0.0
  end

  def parse_row_int(row, key)
    row_field(row, key).to_i
  end

  def weighted_average_from_rows(rows, value_key, weight_key = 'tradesCount')
    total_weight = rows.sum { |row| parse_row_int(row, weight_key) }
    return nil if total_weight.zero?

    rows.sum { |row| parse_row_float(row, value_key) * parse_row_int(row, weight_key) } / total_weight
  end

  def family_all_rows(rows)
    rows.select do |row|
      row_field(row, :algoID).to_s == 'ALL' && row_field(row, :pattern).to_s != 'ALL'
    end
  end

  def build_merged_all_row_from_family_all_rows(family_all_rows)
    return nil if family_all_rows.nil? || family_all_rows.empty?

    gross_profit = family_all_rows.sum { |row| parse_row_float(row, :gross_profit) }
    gross_loss = family_all_rows.sum { |row| parse_row_float(row, :gross_loss) }
    trades_count = family_all_rows.sum { |row| parse_row_int(row, :tradesCount) }
    return nil if trades_count.zero?

    first_dates = family_all_rows.map { |row| parse_trade_date(row_field(row, :firstTradeDate)) }.compact
    last_dates = family_all_rows.map { |row| parse_trade_date(row_field(row, :lastTradeDate)) }.compact
    total_net = gross_profit - gross_loss
    longest_duration_hours = family_all_rows.map { |row| parse_row_float(row, :longestDurationHours) }.max

    {
      algoID: 'ALL',
      pattern: 'ALL',
      firstTradeDate: format_date(first_dates.min),
      lastTradeDate: format_date(last_dates.max),
      tradesCount: trades_count,
      tradedDaysCount: '',
      max_notrades_streak: '',
      avg_notrades_streak: '',
      avgMFE_w_roll: format_float(weighted_average_from_rows(family_all_rows, :avgMFE_w_roll), 1),
      avgMAE_w_roll: format_float(weighted_average_from_rows(family_all_rows, :avgMAE_w_roll), 1),
      avgDurationHours: format_float(weighted_average_from_rows(family_all_rows, :avgDurationHours), 2),
      longestDurationHours: format_float(longest_duration_hours, 2),
      longestDurationDays: format_float(longest_duration_hours.nil? ? nil : longest_duration_hours / 24.0, 2),
      avgFillDelaySeconds: format_float(weighted_average_from_rows(family_all_rows, :avgFillDelaySeconds), 2),
      avg_profit_custom_with_roll: format_float(total_net / trades_count, 2),
      gross_profit: format_float(gross_profit, 2),
      gross_loss: format_float(gross_loss, 2),
      profit_factor: format_profit_factor(profit_factor_from_gross(gross_profit, gross_loss)),
      percentSum_w_roll: format_float(family_all_rows.sum { |row| parse_row_float(row, :percentSum_w_roll) }, 2),
      avg_time_at_peak_exposure_hours: '',
      timeVSprofit: format_float(weighted_average_from_rows(family_all_rows, :timeVSprofit), 3),
      max_time_at_peak_exposure_hours: '',
      max_time_at_peak_exposure_days: '',
      traderate: '',
      weekly_traderate: '',
      avg_open_exposure: '',
      peak_open_exposure: '',
      main_close_reason: ''
    }
  end

  FAMILY_ALL_PATTERN_ORDER = {
    'BREAKDOWN' => 0,
    'TIME' => 1,
    'LEVEL' => 2
  }.freeze

  def performance_row_sort_key(row)
    algo_id = row_field(row, :algoID).to_s
    pattern = row_field(row, :pattern).to_s
    return [-2, 0] if algo_id == 'ALL' && pattern == 'ALL'
    return [-1, FAMILY_ALL_PATTERN_ORDER.fetch(pattern, 99)] if algo_id == 'ALL'

    [algo_id.to_i, 0]
  end

  def sort_performance_rows(rows)
    rows.sort_by { |row| performance_row_sort_key(row) }
  end

  def build_flashcrash_rows(trades, pattern_for_algo:)
    trades_by_algo = trades.group_by { |trade| trade[:algo_id] }
    eligible_algo_ids =
      trades_by_algo
      .select { |_algo_id, algo_trades| algo_eligible_for_flashcrash?(algo_trades) }
      .keys

    return [] if eligible_algo_ids.empty?

    global_first_date, global_last_date, global_trading_day_count, global_full_week_mondays =
      flashcrash_global_context

    eligible_algo_ids.sort_by(&:to_i).filter_map do |algo_id|
      algo_trades =
        trades_by_algo[algo_id].select { |trade| trade_in_flashcrash_analysis_range?(trade) }
      next if algo_trades.empty?

      build_performance_row(
        algo_id,
        algo_trades,
        pattern_for_algo.call(algo_id),
        global_first_date,
        global_last_date,
        global_trading_day_count,
        global_full_week_mondays
      )
    end
  end

  def write_rows(path, rows)
    CSV.open(path, 'w', write_headers: true, headers: CSV_HEADERS) do |csv|
      rows.each do |row|
        csv << CSV_HEADERS.map { |header| row[header.to_sym] }
      end
    end
  end

  OUTPUT_TIMESTAMP_MAX_AGE_SECONDS = 8 * 60

  # Human-editable refresh stamp (.txt) for analyze_ALL_algos_performance_to_csv.rb only.
  # Far-future time => skip refresh until you edit it back.
  # Format of the timestamp line: YYYY-MM-DD HH:MM:SS (local). Legacy unix epoch still accepted.
  def write_output_timestamp_txt!(path, time = Time.now)
    stamp = time.strftime('%Y-%m-%d %H:%M:%S')
    File.write(
      path,
      <<~TXT
        # analyze_ALL_algos_performance_to_csv.rb only.
        # Parent skips family scripts if this time is within the last 8 minutes of now.
        # Family scripts run manually always refresh (no timestamp check).
        # Set a far-future time (e.g. 2099-01-01 00:00:00) to skip refresh until you change it.
        # Format: YYYY-MM-DD HH:MM:SS (local time)
        #{stamp}
      TXT
    )
  end

  def output_timestamp_recent?(path, max_age_seconds = OUTPUT_TIMESTAMP_MAX_AGE_SECONDS)
    generated_at = read_output_timestamp_txt(path)
    return false unless generated_at

    Time.now.to_i - generated_at < max_age_seconds
  end

  def output_timestamp_age_label(path)
    generated_at = read_output_timestamp_txt(path)
    return 'no stamp' unless generated_at

    age_sec = Time.now.to_i - generated_at
    if age_sec.negative?
      'future-dated stamp (manual skip)'
    else
      "#{(age_sec / 60.0).round(1)} min ago"
    end
  end

  def read_output_timestamp_txt(path)
    return nil unless File.file?(path)

    line = File.readlines(path, encoding: 'bom|utf-8')
               .map { |l| l.strip }
               .find { |l| !l.empty? && !l.start_with?('#') }
    return nil if line.nil? || line.empty?

    if line.match?(/\A\d+\z/)
      return Integer(line)
    end

    Time.strptime(line, '%Y-%m-%d %H:%M:%S').to_i
  rescue ArgumentError, TypeError
    begin
      Time.strptime(line, '%Y.%m.%d %H:%M:%S').to_i
    rescue ArgumentError, TypeError
      nil
    end
  end
end
