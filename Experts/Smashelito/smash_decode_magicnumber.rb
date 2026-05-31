#!/usr/bin/env ruby
# Decodes 18-digit Falgo composite magic numbers (smashelito.mq5 layout).

MAGIC_LEN = 18

SLOTS = [
  { digits: "1-2",   name: "algo ID",           range: "10..99", note: "wired algo number (MAGIC_ALGO*)" },
  { digits: "3",     name: "direction",         range: "1..4",   note: "1=long limit 2=short limit 3=long alt 4=short alt" },
  { digits: "4",     name: "day of week",       range: "1..5",   note: "Mon..Fri (MT5 day_of_week)" },
  { digits: "5",     name: "level tier",        range: "1..9",   note: "ladder tier (weekly or daily; category in digit 13)" },
  { digits: "6",     name: "bounce count",      range: "0..8",   note: "capped at placement" },
  { digits: "7",     name: "ceiling count",     range: "0..8",   note: "capped at placement" },
  { digits: "8-9",   name: "offset (tenths)",   range: "00..99", note: "encoded 0.1..9.9 points (long/short offset for plan)" },
  { digits: "10",    name: "plan trade num",    range: "0..8",   note: "plan trade # today" },
  { digits: "11",    name: "level trade num",   range: "0..8",   note: "per-tier trade # today" },
  { digits: "12",    name: "babysit minute",    range: "0..9",   note: "babysit slot" },
  { digits: "13",    name: "level category",    range: "1..3",   note: "1=weekly 2=daily 3=tertiary" },
  { digits: "14",    name: "unused_slot",       range: "0..9",   note: "reserved" },
  { digits: "15-16", name: "TP (whole points)", range: "01..99", note: "whole points" },
  { digits: "17-18", name: "SL (whole points)", range: "01..99", note: "whole points" },
].freeze

DIRECTION_LABEL = {
  1 => "long limit (buy limit)",
  2 => "short limit (sell limit)",
  3 => "long alt",
  4 => "short alt",
}.freeze

DAY_LABEL = {
  1 => "Monday",
  2 => "Tuesday",
  3 => "Wednesday",
  4 => "Thursday",
  5 => "Friday",
}.freeze

LEVEL_CATEGORY_LABEL = {
  1 => "weekly",
  2 => "daily",
  3 => "tertiary",
}.freeze

DEFAULT_MAGIC = "382160004110201515"

def pad_magic(raw)
  s = raw.to_s.strip
  raise "Magic must be #{MAGIC_LEN} digits (got #{s.length}: #{s})" unless s.match?(/\A\d+\z/)
  raise "Magic must be at most #{MAGIC_LEN} digits (got #{s.length})" if s.length > MAGIC_LEN
  s.rjust(MAGIC_LEN, "0")
end

def print_slot_legend
  puts "Falgo composite magic — #{MAGIC_LEN} decimal digits"
  puts
  SLOTS.each do |slot|
    puts "#{slot[:digits].ljust(5)}  #{slot[:name]}  (#{slot[:range]})  — #{slot[:note]}"
  end
end

def parse_falgo_magic(magic)
  m = pad_magic(magic)
  {
    raw: m,
    algo: m[0, 2].to_i,
    direction: m[2].to_i,
    day_of_week: m[3].to_i,
    level_tier: m[4].to_i,
    bounce_count: m[5].to_i,
    ceiling_count: m[6].to_i,
    offset_tenths: m[7, 2].to_i,
    plan_trade_num: m[9].to_i,
    level_trade_num: m[10].to_i,
    babysit_minute: m[11].to_i,
    level_category: m[12].to_i,
    unused_slot: m[13].to_i,
    tp_whole: m[14, 2].to_i,
    sl_whole: m[16, 2].to_i,
  }
end

def direction_label(v)
  DIRECTION_LABEL[v] || "unknown (#{v})"
end

def day_label(v)
  DAY_LABEL[v] || "unknown (#{v})"
end

def level_category_label(v)
  LEVEL_CATEGORY_LABEL[v] || "unknown (#{v})"
end

def print_decoded(d)
  offset_pts = d[:offset_tenths] / 10.0

  puts "magic: #{d[:raw]}"
  puts
  puts "  algo:              #{d[:algo]}"
  puts "  direction:         #{d[:direction]}  (#{direction_label(d[:direction])})"
  puts "  day_of_week:       #{d[:day_of_week]}  (#{day_label(d[:day_of_week])})"
  puts "  level_tier:        #{d[:level_tier]}"
  puts "  bounce_count:      #{d[:bounce_count]}"
  puts "  ceiling_count:     #{d[:ceiling_count]}"
  puts "  offset_points:     #{offset_pts}  (tenths=#{d[:offset_tenths]})"
  puts "  plan_trade_num:    #{d[:plan_trade_num]}"
  puts "  level_trade_num:   #{d[:level_trade_num]}"
  puts "  babysit_minute:    #{d[:babysit_minute]}"
  puts "  level_category:    #{d[:level_category]}  (#{level_category_label(d[:level_category])})"
  puts "  unused_slot:       #{d[:unused_slot]}"
  puts "  tp_points:         #{d[:tp_whole]}"
  puts "  sl_points:         #{d[:sl_whole]}"
end

# --- part 1: slot legend ---
puts "=" * 60
puts "Part 1 — digit slots"
puts "=" * 60
print_slot_legend

# --- part 2: decode input ---
magic_input = (ARGV[0] || DEFAULT_MAGIC)
puts
puts "=" * 60
puts "Part 2 — decode"
puts "=" * 60
print_decoded(parse_falgo_magic(magic_input))
