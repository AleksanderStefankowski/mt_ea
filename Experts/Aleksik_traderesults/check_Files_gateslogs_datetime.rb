require 'csv'
require 'time'

# =========================
# INPUT DATETIME RANGE
# =========================
datetime_range_start = "2026.05.18 13:07"
datetime_range_end   = "2026.05.18 13:11"

# =========================
# BUILD MINUTE-BY-MINUTE LIST
# =========================
start_time = Time.strptime(datetime_range_start, "%Y.%m.%d %H:%M")
end_time   = Time.strptime(datetime_range_end, "%Y.%m.%d %H:%M")

datetime_to_check = []

current_time = start_time

while current_time <= end_time
  datetime_to_check << current_time.strftime("%Y.%m.%d %H:%M")
  current_time += 60
end

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

# Optional: sort by algo number
gate_files.sort_by! do |file|
  File.basename(file)[/algo(\d+)/, 1].to_i
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

  # =========================
  # PRINT RESULTS
  # =========================
  datetime_to_check.each do |dt|
    if rows_by_time[dt]
      data = rows_by_time[dt]

      puts "#{dt}  #{data[:firstFailGate]}  #{data[:failGateCount]}"
    else
      puts "#{dt}  NOT_FOUND"
    end
  end
end