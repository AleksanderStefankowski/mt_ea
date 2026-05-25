require 'csv'

# =========================
# INPUT DATETIMES TO CHECK
# =========================
datetime_to_check = %[
2026.05.18 09:13
2026.05.18 09:14
2026.05.18 09:15
].lines.map(&:strip).reject(&:empty?)

# =========================
# FILES DIRECTORY
# =========================
files_dir = "./Files"

# =========================
# GROUP DATETIMES BY DATE
# =========================
dates_needed = datetime_to_check.map { |dt| dt.split(' ').first }.uniq

# =========================
# FIND ALL MATCHING GATE FILES
# =========================
gate_files = Dir.glob(File.join(files_dir, "*_gates_per_minute.csv"))

gate_files.select! do |file|
  filename = File.basename(file)

  dates_needed.any? do |date|
    filename.start_with?(date)
  end
end

# =========================
# PROCESS EACH FILE
# =========================
gate_files.each do |file|
  filename = File.basename(file)

  # Example:
  # 2026.05.18_algo13_gates_per_minute.csv
  algo_name = filename[/_(algo\d+)_/, 1] || filename

  puts
  puts "#{algo_name}:"

  rows_by_time = {}

  # File is TAB separated
  CSV.foreach(file, headers: true, col_sep: "\t") do |row|
    bar_time = row["barTime"]

    next unless datetime_to_check.include?(bar_time)

    rows_by_time[bar_time] = {
      firstFailGate: row["firstFailGate"],
      failGateCount: row["failGateCount"]
    }
  end

  # Print in original order
  datetime_to_check.each do |dt|
    if rows_by_time[dt]
      data = rows_by_time[dt]

      puts "#{dt}  #{data[:firstFailGate]}  #{data[:failGateCount]}"
    else
      puts "#{dt}  NOT_FOUND"
    end
  end
end