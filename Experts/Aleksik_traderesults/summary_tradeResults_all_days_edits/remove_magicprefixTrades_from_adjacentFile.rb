#!/usr/bin/env ruby

require 'csv'

# =========================================================
# CONFIG
# =========================================================

MAGIC_PREFIX_LEN = 3

# Magic prefixes (first 3 digits of magic) whose trades should be removed.
MAGIC_PREFIXES_TO_REMOVE = [
  100, 102, 104, 105, 106, 110, 111, 113, 114, 115,
  101, 103, 107, 108, 109, 112, 116
].freeze

# summary_tradeResults_all_days.tsv in the same folder as this script.
FILE_PATH = File.join(__dir__, 'summary_tradeResults_all_days.tsv')

# =========================================================
# HELPERS
# =========================================================

def normalize_magic_prefix(value)
  value.to_s.strip.rjust(MAGIC_PREFIX_LEN, '0')
end

def configured_remove_prefixes
  MAGIC_PREFIXES_TO_REMOVE
    .map { |p| normalize_magic_prefix(p) }
    .uniq
    .sort
end

def magic_prefix_for_row(row)
  magic = row['magic'].to_s.strip
  return nil if magic.empty?

  magic[0, MAGIC_PREFIX_LEN]
end

# =========================================================
# MAIN
# =========================================================

remove_prefixes = configured_remove_prefixes

unless File.file?(FILE_PATH)
  warn "ERROR: File not found: #{FILE_PATH}"
  exit 1
end

raw = File.read(FILE_PATH, encoding: 'bom|utf-8')
csv = CSV.parse(raw, headers: true, col_sep: ',')
headers = csv.headers

if headers.nil? || headers.empty?
  warn 'ERROR: No header row found.'
  exit 1
end

unless headers.include?('magic')
  warn 'ERROR: Column "magic" not found in header.'
  exit 1
end

removed_by_prefix = Hash.new(0)
kept_rows = []
total_rows = 0

csv.each do |row|
  total_rows += 1
  prefix = magic_prefix_for_row(row)

  if prefix.nil?
    kept_rows << row
    next
  end

  if remove_prefixes.include?(prefix)
    removed_by_prefix[prefix] += 1
  else
    kept_rows << row
  end
end

removed_total = removed_by_prefix.values.sum
found_prefixes = removed_by_prefix.keys.sort
not_found_prefixes = remove_prefixes - found_prefixes

CSV.open(FILE_PATH, 'w', encoding: 'UTF-8', write_headers: true, headers: headers) do |out|
  kept_rows.each { |row| out << row }
end

puts
puts "File: #{FILE_PATH}"
puts "Rows before: #{total_rows}"
puts "Rows removed: #{removed_total}"
puts "Rows after: #{kept_rows.size}"
puts

if found_prefixes.any?
  puts 'Removed by prefix:'
  found_prefixes.each do |prefix|
    puts "  #{prefix}: #{removed_by_prefix[prefix]}"
  end
else
  puts 'Removed by prefix: (none matched)'
end

puts

if not_found_prefixes.any?
  puts "Prefixes not found (#{not_found_prefixes.size}):"
  not_found_prefixes.each { |prefix| puts "  #{prefix}" }
else
  puts 'Prefixes not found: 0'
end

puts
puts 'DONE'
