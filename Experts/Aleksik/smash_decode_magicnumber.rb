#!/usr/bin/env ruby
# Decodes 18-digit Falgo composite magic numbers (aleksik.mq5 layout).

require_relative "smash_mql5_algo_reader_lib"

FM = SmashMql5AlgoReader::FalgoMagic
MAGIC_LEN = FM::MAGIC_LEN

SLOTS = [
  { digits: "1-2",   name: "algo ID",           range: "10..99", note: "wired algo number (MAGIC_ALGO*)" },
  { digits: "3",     name: "direction",         range: "1..4",   note: "1=long limit 2=short limit 3=long alt 4=short alt" },
  { digits: "4",     name: "day of week",       range: "1..5",   note: "Mon..Fri (MT5 day_of_week)" },
  { digits: "5-6",   name: "level slot",        range: "00..99", note: "00=RTHO; 01=PDC; 10..30 weekly (pivot=20); 50..70 daily (pivot=60)" },
  { digits: "7",     name: "bounce count",      range: "0..8",   note: "capped at placement" },
  { digits: "8",     name: "ceiling count",     range: "0..8",   note: "capped at placement" },
  { digits: "9-10",  name: "offset (tenths)",   range: "00..99", note: "encoded 0.1..9.9 points (long/short offset for plan)" },
  { digits: "11",    name: "plan trade num",    range: "0..8",   note: "plan trade # today" },
  { digits: "12",    name: "level trade num",   range: "0..8",   note: "per-level-slot trade # today" },
  { digits: "13",    name: "babysit minute",    range: "0..9",   note: "babysit slot" },
  { digits: "14",    name: "unused_slot",       range: "0..9",   note: "reserved" },
  { digits: "15-16", name: "TP (whole points)", range: "01..99", note: "whole points" },
  { digits: "17-18", name: "SL (whole points)", range: "01..99", note: "whole points" }
].freeze

DIRECTION_LABEL = {
  1 => "long limit (buy limit)",
  2 => "short limit (sell limit)",
  3 => "long alt",
  4 => "short alt"
}.freeze

DEFAULT_MAGIC = "151200250511001515"

def print_slot_legend
  puts "Falgo composite magic — #{MAGIC_LEN} decimal digits"
  puts
  SLOTS.each do |slot|
    puts "#{slot[:digits].ljust(5)}  #{slot[:name]}  (#{slot[:range]})  — #{slot[:note]}"
  end
end

def direction_label(v)
  DIRECTION_LABEL[v] || "unknown (#{v})"
end

def print_decoded(d)
  offset_pts = d[:offset_tenths] / 10.0

  puts "magic: #{d[:raw]}"
  puts
  puts "  algo:              #{d[:algo]}"
  puts "  direction:         #{d[:direction]}  (#{direction_label(d[:direction])})"
  puts "  day_of_week:       #{d[:day_of_week_digit]}  (#{d[:day_of_week]})"
  puts "  level_slot:        #{format('%02d', d[:level_slot])}  (#{FM.level_slot_label(d[:level_slot])})"
  puts "  bounce_count:      #{d[:bounce_count]}"
  puts "  ceiling_count:     #{d[:ceiling_count]}"
  puts "  offset_points:     #{offset_pts}  (tenths=#{d[:offset_tenths]})"
  puts "  plan_trade_num:    #{d[:plan_trade_num]}"
  puts "  level_trade_num:   #{d[:level_trade_num]}"
  puts "  babysit_minute:    #{d[:babysit_minute]}"
  puts "  unused_slot:       #{d[:unused_slot]}"
  puts "  tp_points:         #{d[:tp_whole]}"
  puts "  sl_points:         #{d[:sl_whole]}"
end

# --- part 1: slot legend ---
puts "-" * 60
puts "Part 1 — digit slots"
puts "-" * 60
print_slot_legend

# --- part 2: decode input ---
magic_input = (ARGV[0] || DEFAULT_MAGIC)
puts
puts "-" * 60
puts "Part 2 — decode"
puts "-" * 60
print_decoded(FM.parse(magic_input))
