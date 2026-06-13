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

# Each metric: Block C (all gap days), Block A (filled), Block B (not-filled) — adjacent triplets.
SUMMARY_HEADERS = [
  'which_fill_threshold_pc',
  'all_days_count',
  'gap_days_count',
  'fill_reached_daycount',
  'fill_NOTreached_daycount',
  'daysreached_percent',
  'avg_gap_fill_pc_for_all_gap_days',
  'avg_gap_fill_pc_for_filled_days',
  'avg_gap_fill_pc_for_notfilled_days',
  'avg_max_before_gapfillAttempt_over_5_for_all_gap_days',
  'avg_max_before_gapfillAttempt_over_5_for_filled_days',
  'avg_max_before_gapfillAttempt_over_5_for_notfilled_days',
  'avg_Gap_as_pct_of_ONrange_for_all_gap_days',
  'avg_Gap_as_pct_of_ONrange_for_filled_days',
  'avg_Gap_as_pct_of_ONrange_for_notfilled_days',
  'avgGapRangePts',
  'avgGapRangePts_for_filled_days',
  'avgGapRangePts_for_notfilled_days'
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
        gap_as_on_pct: gap_as_pct_of_onrange(row),
        gap_range_pts: parse_float(row['gapRangePts']) || parse_float(row['gapDiff']),
        max_before_gapfill_attempt_over_5: parse_float(row['max_before_gapfillAttempt_over_5'])
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

# gap_fill_pc, max_before_gapfillAttempt_over_5, Gap_as_%_of_ONrange, gapRangePts (gapDiff alias)
def bucket_metric_cells(days)
  [
    fmt(avg(pluck(days, :gap_fill_pc))),
    fmt(avg(pluck(days, :max_before_gapfill_attempt_over_5))),
    fmt(avg(pluck(days, :gap_as_on_pct))),
    fmt(avg(pluck(days, :gap_range_pts)))
  ]
end

# Per metric index: all_gap (C), filled (A), not_filled (B).
def metric_cells_cab(all_gap_days, filled_days, notfilled_days)
  c = bucket_metric_cells(all_gap_days)
  a = bucket_metric_cells(filled_days)
  b = bucket_metric_cells(notfilled_days)
  4.times.flat_map { |i| [c[i], a[i], b[i]] }
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
    *metric_cells_cab([], filled, not_filled)
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
    *metric_cells_cab(gap_days, gap_days, [])
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
