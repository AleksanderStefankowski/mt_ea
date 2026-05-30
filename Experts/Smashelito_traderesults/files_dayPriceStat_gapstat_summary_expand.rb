#!/usr/bin/env ruby
# Post-process per-day gap stat logs from Strategy Tester Files/.
# Multi-row summary: one row per fill threshold (10, 20, … 100) plus ALL.
#
# Run from tester agent MQL5 folder:
#   cd "...\Agent-127.0.0.1-3000\MQL5"
#   ruby .\files_dayPriceStat_gapstat_summary_expand.rb

require 'csv'

FILES_DIR = File.join(Dir.pwd, 'Files')
OUT_GAP_D = File.join(Dir.pwd, 'dayPriceStat_and_gapstat_summaryLog_gapDowns_expanded.csv')
OUT_GAP_U = File.join(Dir.pwd, 'dayPriceStat_and_gapstat_summaryLog_gapUps_expanded.csv')

DAY_LOG_GLOB = '*_dayPriceStat_and_gapstat_log.csv'
WHICH_FILL_LEVELS = [10, 20, 25, 30, 33, 40, 50, 60, 75, 90, 100].freeze

# --- Output columns (one CSV row per which_fill_threshold_pc value) ---
#
# which_fill_threshold_pc
#   Row key: ALL = whole sample, or 10/20/25/.../100 = that EOD gap-fill % cutoff.
#
# total_calendar_days_logged
#   Count of per-day log files loaded (all days in the backtest window, any gap type).
#
# days_with_this_gap_type
#   Subset of those days that are gap-down (gapDowns file) or gap-up (gapUps file).
#
# count_gap_days_reached_fill_threshold
#   Gap-type days where EOD gap_fill_pc >= which_fill_threshold_pc (on ALL row = all gap days).
#
# count_gap_days_did_not_reach_fill_threshold
#   Gap-type days where gap_fill_pc < threshold (0 on ALL row).
#
# percent_gap_days_reached_fill_threshold
#   100 * count_reached / days_with_this_gap_type.
#
# avg_gap_fill_pc_for_filled_days
#   Mean EOD gap_fill_pc among gap days in the "reached threshold" bucket.
#   On ALL row: mean over all gap-type days (same as avg_gap_fill_pc_for_all_gap_days).
#
# avg_gap_fill_pc_for_notfilled_days
#   Mean gap_fill_pc among gap days below the threshold. Empty on ALL row.
#
# avg_Gap_as_pct_of_ONrange_for_filled_days
#   Mean Gap_as_%_of_ONrange (gap pts / ON range * 100) for the reached-threshold bucket.
#
# avg_Gap_as_pct_of_ONrange_for_notfilled_days
#   Same metric for days below threshold. Empty on ALL row.
#
# avg_gap_fill_pc_for_all_gap_days
#   Filled only on ALL row: overall mean gap_fill_pc for every gap-down/up day.
#
# avg_Gap_as_pct_of_ONrange_for_all_gap_days
#   Filled only on ALL row: overall mean gap-vs-ON-range % for every gap-down/up day.
#
SUMMARY_HEADERS = [
  'which_fill_threshold_pc',
  'total_calendar_days_logged',
  'days_with_this_gap_type',
  'count_gap_days_reached_fill_threshold',
  'count_gap_days_did_not_reach_fill_threshold',
  'percent_gap_days_reached_fill_threshold',
  'avg_gap_fill_pc_for_filled_days',
  'avg_gap_fill_pc_for_notfilled_days',
  'avg_Gap_as_pct_of_ONrange_for_filled_days',
  'avg_Gap_as_pct_of_ONrange_for_notfilled_days',
  'avg_gap_fill_pc_for_all_gap_days',
  'avg_Gap_as_pct_of_ONrange_for_all_gap_days'
].freeze

def truthy?(val)
  %w[true 1 yes].include?(val.to_s.strip.downcase)
end

def parse_float(val)
  s = val.to_s.strip
  return nil if s.empty? || s.downcase == 'unknown'
  Float(s)
rescue ArgumentError, TypeError
  nil
end

def detect_col_sep(path)
  line = File.open(path, 'r:UTF-8') { |f| f.gets }
  return "\t" if line&.include?("\t")
  ','
end

def read_csv_table(path)
  sep = detect_col_sep(path)
  text = File.read(path, encoding: 'UTF-8').sub(/\A\uFEFF/, '')
  CSV.parse(text, headers: true, col_sep: sep, liberal_parsing: true)
end

def gap_as_pct_of_onrange(row)
  v = parse_float(row['Gap_as_%_of_ONrange'])
  return v unless v.nil?

  gap = parse_float(row['gapDiff'])
  onh = parse_float(row['ONH'])
  onl = parse_float(row['ONL'])
  return nil if gap.nil? || onh.nil? || onl.nil?

  on_range = onh - onl
  return nil if on_range <= 0.0

  100.0 * gap / on_range
end

def load_day_rows(files_dir)
  pattern = File.join(files_dir, DAY_LOG_GLOB)
  paths = Dir.glob(pattern).sort
  if paths.empty?
    warn "No files matching #{pattern}"
    return []
  end

  rows = []
  skipped = []
  paths.each do |path|
    table = read_csv_table(path)
    headers = table.headers&.map { |h| h.to_s.strip } || []
    if !headers.include?('date')
      skipped << "#{File.basename(path)} (headers: #{headers.join('|')})"
      next
    end
    table.each do |row|
      date = row['date']&.strip
      next if date.nil? || date.empty?

      rows << {
        date: date,
        has_gap_down: truthy?(row['hasGapDown']),
        has_gap_up: truthy?(row['hasGapUp']),
        gap_fill_pc: parse_float(row['gap_fill_pc']) || 0.0,
        gap_as_on_pct: gap_as_pct_of_onrange(row)
      }
    end
  end

  unless skipped.empty?
    puts "Skipped #{skipped.length} file(s) (bad/missing headers):"
    skipped.each { |s| puts "  #{s}" }
  end

  rows.uniq { |r| r[:date] }
end

def avg(values)
  return nil if values.empty?
  values.sum / values.length.to_f
end

def pct(hit, total)
  return nil if total <= 0
  100.0 * hit / total.to_f
end

def fmt(val, digits = 2)
  return '' if val.nil?
  format("%.#{digits}f", val)
end

def pluck(days, key)
  days.map { |d| d[key] }.compact
end

def threshold_row(all_days, gap_days, which_fill)
  filled = gap_days.select { |d| d[:gap_fill_pc] >= which_fill }
  not_filled = gap_days.select { |d| d[:gap_fill_pc] < which_fill }
  n_gap = gap_days.length

  [
    which_fill.to_s,
    all_days.length.to_s,
    n_gap.to_s,
    filled.length.to_s,
    not_filled.length.to_s,
    fmt(pct(filled.length, n_gap)),
    fmt(avg(pluck(filled, :gap_fill_pc))),
    fmt(avg(pluck(not_filled, :gap_fill_pc))),
    fmt(avg(pluck(filled, :gap_as_on_pct))),
    fmt(avg(pluck(not_filled, :gap_as_on_pct))),
    '',  # avg_gap_fill_pc_for_all_gap_days — only on ALL row
    ''   # avg_Gap_as_pct_of_ONrange_for_all_gap_days
  ]
end

def all_row(all_days, gap_days)
  n_total = all_days.length
  n_gap = gap_days.length

  [
    'ALL',
    n_total.to_s,
    n_gap.to_s,
    n_gap.to_s,
    '0',
    n_gap.positive? ? '100.00' : '0.00',
    fmt(avg(pluck(gap_days, :gap_fill_pc))),
    '',
    fmt(avg(pluck(gap_days, :gap_as_on_pct))),
    '',
    fmt(avg(pluck(gap_days, :gap_fill_pc))),
    fmt(avg(pluck(gap_days, :gap_as_on_pct)))
  ]
end

def build_table_rows(all_days, gap_flag_key)
  gap_days = all_days.select { |d| d[gap_flag_key] }
  rows = [all_row(all_days, gap_days)]
  WHICH_FILL_LEVELS.each { |t| rows << threshold_row(all_days, gap_days, t) }
  rows
end

def write_table(path, table_rows)
  CSV.open(path, 'w', write_headers: false) do |csv|
    csv << SUMMARY_HEADERS
    table_rows.each { |row| csv << row }
  end
  puts "Wrote #{path} (#{table_rows.length} rows)"
end

unless File.directory?(FILES_DIR)
  puts "ERROR: Files directory not found: #{FILES_DIR}"
  puts "Run from tester Agent MQL5 folder (cwd = ...\\Agent-127.0.0.1-3000\\MQL5)."
  exit 1
end

all_days = load_day_rows(FILES_DIR)
if all_days.empty?
  pattern = File.join(FILES_DIR, DAY_LOG_GLOB)
  puts "ERROR: No day rows loaded. Checked: #{pattern}"
  puts "MT5 logs are usually tab-separated; ensure files are *_dayPriceStat_and_gapstat_log.csv with a date column."
  exit 1
end

puts "Loaded #{all_days.length} day(s) from #{FILES_DIR}"

write_table(OUT_GAP_D, build_table_rows(all_days, :has_gap_down))
write_table(OUT_GAP_U, build_table_rows(all_days, :has_gap_up))
