
# desired_min_breakdown_sequence_len = [4, 3, 6, 8]
# desired_max_breakdown_sequence_len = [9, 14, 21]

# desired_bd_start_min_breakdown_percent = [0.20, 0.30, 0.40, 0.60, 0.80]
# desired_min_breakdown_total_percent = [0.40, 0.60, 0.80, 1.00, 2.00]

# desired_after_bd_need_x_15greenc = [1, 2, 3, 4, 5]
# desired_entry_max_minutes_after_bdend = [75, 50, 90]

# desired_entryrange_range_percentspot = [20, 33, 50, 66, 75]
# desired_secret_tp_range_percent = [0, 20, 33, 50, 66, 75, 100] # 0 is disabled secret tp

# desired_tp_notsecret_range_percent = [150]

# desired_closetrade_after_x_minutes_from_breakdown = [0, 15, 30, 45, 60, 75, 90] #  0 is disabled

# desired_breakdowntypes = [
#     "CLOSES",
#     "OHLC_AVG",
#     "LOW",
#     "OC_MID",
#     "HL_MID",
# ]

# desired_max_open_positions = [5, 10, 2]


#!/usr/bin/env ruby
# frozen_string_literal: true
# Cartesian product of desired_* arrays -> new breakdown algos in aleksik2.mq5.

require_relative "../Aleksik/smash_mql5_algo_reader_lib"

MQ5_FILE = File.expand_path("aleksik2.mq5", __dir__)
PARENT_ALGO = 20_000_000
BREAKDOWN_ID_MIN = 20_000_000
BREAKDOWN_ID_MAX = 99_999_999

MARKERS = {
  1 => %w[//breakdowncreator1start //breakdowncreator1end],
  2 => %w[//breakdowncreator2start //breakdowncreator2end],
  4 => %w[//breakdowncreator4start //breakdowncreator4end]
}.freeze

BREAKDOWN_TYPE_TO_MODE = {
  "CLOSES" => "BREAKDOWN_STREAK_CONTINUATION_CLOSES",
  "OHLC_AVG" => "BREAKDOWN_STREAK_CONTINUATION_OHLC_AVG",
  "LOW" => "BREAKDOWN_STREAK_CONTINUATION_LOW",
  "OC_MID" => "BREAKDOWN_STREAK_CONTINUATION_OC_MID",
  "HL_MID" => "BREAKDOWN_STREAK_CONTINUATION_HL_MID"
}.freeze

# --- edit combination grids here ---
DESIRED_MIN_BREAKDOWN_SEQUENCE_LEN = [4].freeze
DESIRED_MAX_BREAKDOWN_SEQUENCE_LEN = [9].freeze # , 21

DESIRED_BD_START_MIN_BREAKDOWN_PERCENT = [0.20].freeze
DESIRED_MIN_BREAKDOWN_TOTAL_PERCENT = [0.40].freeze

DESIRED_AFTER_BD_NEED_X_15GREENC = [1].freeze
DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND = [75].freeze

DESIRED_ENTRYRANGE_RANGE_PERCENTSPOT = [20].freeze
DESIRED_SECRET_TP_RANGE_PERCENT = [0, 20].freeze # 0 is disabled secret tp

DESIRED_TP_NOTSECRET_RANGE_PERCENT = [150].freeze

DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN = [90].freeze # 0 is disabled
DESIRED_MAX_OPEN_POSITIONS = [5].freeze
DESIRED_BREAKDOWNTYPES = [
  "CLOSES",
  "OHLC_AVG"
  # "LOW",
  # "OC_MID",
  # "HL_MID",
].freeze

module BreakdownCombinationsCreator
  module_function

  def marker_line_re(marker)
    /^\s*#{Regexp.escape(marker)}\s*$/
  end

  def extract_inner(content, block_num)
    start_marker, end_marker = MARKERS.fetch(block_num)
    lines = content.lines
    start_idx = lines.index { |l| l.match?(marker_line_re(start_marker)) }
    end_idx = lines.index { |l| l.match?(marker_line_re(end_marker)) }
    unless start_idx && end_idx && end_idx > start_idx
      raise "Could not find block #{block_num} (#{start_marker} .. #{end_marker})"
    end

    lines[(start_idx + 1)...end_idx].join.rstrip
  end

  def replace_inner(content, block_num, new_inner)
    start_marker, end_marker = MARKERS.fetch(block_num)
    lines = content.lines
    start_idx = lines.index { |l| l.match?(marker_line_re(start_marker)) }
    end_idx = lines.index { |l| l.match?(marker_line_re(end_marker)) }
    unless start_idx && end_idx && end_idx > start_idx
      raise "Could not find block #{block_num} (#{start_marker} .. #{end_marker})"
    end

    before = lines[0..start_idx].join
    after = lines[end_idx..].join
    "#{before}#{new_inner.rstrip}\n#{after}"
  end

  def breakdown_registry_max(content)
    m = content.match(/#define\s+BREAKDOWN_ALGO_REGISTRY_MAX\s+(\d+)/)
    raise "BREAKDOWN_ALGO_REGISTRY_MAX not found in #{MQ5_FILE}" unless m

    m[1].to_i
  end

  def registry_algo_ids(content)
    block = extract_inner(content, 1)
    block.scan(/MAGIC_BREAKDOWN(\d+)/).flatten.map(&:to_i).uniq.sort
  end

  def magic_const(algo_id)
    "MAGIC_BREAKDOWN#{algo_id}"
  end

  def format_mq5_double(value)
    format("%.2f", value.to_f)
  end

  def build_combinations
    combos = []
    DESIRED_MIN_BREAKDOWN_SEQUENCE_LEN.product(
      DESIRED_MAX_BREAKDOWN_SEQUENCE_LEN,
      DESIRED_BD_START_MIN_BREAKDOWN_PERCENT,
      DESIRED_MIN_BREAKDOWN_TOTAL_PERCENT,
      DESIRED_AFTER_BD_NEED_X_15GREENC,
      DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND,
      DESIRED_ENTRYRANGE_RANGE_PERCENTSPOT,
      DESIRED_SECRET_TP_RANGE_PERCENT,
      DESIRED_TP_NOTSECRET_RANGE_PERCENT,
      DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN,
      DESIRED_BREAKDOWNTYPES,
      DESIRED_MAX_OPEN_POSITIONS
    ) do |min_len, max_len, bd_start_pct, min_total_pct, after_greenc, entry_min, entryrange_pct, secret_tp, tp_notsecret, close_after_min, bd_type, max_open|
      next if min_len > max_len

      mode = BREAKDOWN_TYPE_TO_MODE[bd_type]
      raise "Unknown breakdowntype #{bd_type.inspect}" unless mode

      combos << {
        min_breakdown_sequence_len: min_len,
        max_breakdown_sequence_len: max_len,
        bd_start_min_breakdown_percent: bd_start_pct,
        min_breakdown_total_percent: min_total_pct,
        after_bd_need_x_15greenc: after_greenc,
        entry_max_minutes_after_bdend: entry_min,
        entryrange_range_percentspot: entryrange_pct,
        secret_tp_range_percent: secret_tp,
        tp_notsecret_range_percent: tp_notsecret,
        closetrade_after_x_minutes_from_breakdown: close_after_min,
        breakdown_streak_continuation_mode: mode,
        max_open_positions: max_open
      }
    end
    combos
  end

  def combination_dimension_counts
    valid_min_max_pairs = DESIRED_MIN_BREAKDOWN_SEQUENCE_LEN.product(DESIRED_MAX_BREAKDOWN_SEQUENCE_LEN)
      .count { |min_len, max_len| min_len <= max_len }

    {
      min_max_breakdown_sequence_len: valid_min_max_pairs,
      bd_start_min_breakdown_percent: DESIRED_BD_START_MIN_BREAKDOWN_PERCENT.size,
      min_breakdown_total_percent: DESIRED_MIN_BREAKDOWN_TOTAL_PERCENT.size,
      after_bd_need_x_15greenc: DESIRED_AFTER_BD_NEED_X_15GREENC.size,
      entry_max_minutes_after_bdend: DESIRED_ENTRY_MAX_MINUTES_AFTER_BDEND.size,
      entryrange_range_percentspot: DESIRED_ENTRYRANGE_RANGE_PERCENTSPOT.size,
      secret_tp_range_percent: DESIRED_SECRET_TP_RANGE_PERCENT.size,
      tp_notsecret_range_percent: DESIRED_TP_NOTSECRET_RANGE_PERCENT.size,
      closetrade_after_x_minutes_from_breakdown: DESIRED_CLOSETRADE_AFTER_X_MINUTES_FROM_BREAKDOWN.size,
      breakdowntypes: DESIRED_BREAKDOWNTYPES.size,
      max_open_positions: DESIRED_MAX_OPEN_POSITIONS.size
    }
  end

  def rebuild_registry_inner(all_ids)
    lines = []
    all_ids.each do |algo_id|
      const = magic_const(algo_id)
      lines << "#define #{const}#{' ' * (28 - const.length)}#{algo_id}"
    end
    lines << ""
    lines << "int g_breakdownRegistryIds[] ="
    lines << "{"
    all_ids.each { |algo_id| lines << "   #{magic_const(algo_id)}," }
    lines[-1] = lines[-1].sub(/,\z/, "") unless all_ids.empty?
    lines << "};"
    lines.join("\n")
  end

  def build_algo_params_block(algo_id, combo)
    const = magic_const(algo_id)
    slot = "BreakdownAlgoSlotIndexByAlgoId(#{const})"
    secret_tp_enabled = combo[:secret_tp_range_percent] != 0
    secret_tp_percent = combo[:secret_tp_range_percent]

    <<~MQL5.rstrip

      g_breakdownAlgos[#{slot}].enabled = true;
      g_breakdownAlgos[#{slot}].stop_trading_today_if_thisAlgo_losing_trades_count = 999;
      g_breakdownAlgos[#{slot}].stop_trading_today_if_thisAlgo_winning_trades_count = 999;
      g_breakdownAlgos[#{slot}].expiry_minutes = 15;
      g_breakdownAlgos[#{slot}].min_breakdown_sequence_len = #{combo[:min_breakdown_sequence_len]}; // more important starts here and below:
      g_breakdownAlgos[#{slot}].max_breakdown_sequence_len = #{combo[:max_breakdown_sequence_len]};
      g_breakdownAlgos[#{slot}].breakdown_streak_continuation_mode = #{combo[:breakdown_streak_continuation_mode]};
      g_breakdownAlgos[#{slot}].bd_start_min_breakdown_percent = #{format_mq5_double(combo[:bd_start_min_breakdown_percent])};
      g_breakdownAlgos[#{slot}].min_breakdown_total_percent = #{format_mq5_double(combo[:min_breakdown_total_percent])};
      g_breakdownAlgos[#{slot}].after_bd_need_x_15greenc = #{combo[:after_bd_need_x_15greenc]};
      g_breakdownAlgos[#{slot}].entry_max_minutes_after_bdend = #{combo[:entry_max_minutes_after_bdend]};
      g_breakdownAlgos[#{slot}].forget_about_latest_breakdown_after_x_15m_candles = 6;
      g_breakdownAlgos[#{slot}].entryrange_range_percentspot = #{format_mq5_double(combo[:entryrange_range_percentspot])};
      g_breakdownAlgos[#{slot}].secret_tp_enabled = #{secret_tp_enabled ? 'true' : 'false'};
      g_breakdownAlgos[#{slot}].secret_tp_range_percent = #{secret_tp_percent};
      g_breakdownAlgos[#{slot}].secret_tp_greenguard_pricediff_at_least = 8.0;
      g_breakdownAlgos[#{slot}].tp_enabled = true;
      g_breakdownAlgos[#{slot}].tp_notsecret_range_percent = #{combo[:tp_notsecret_range_percent]};
      g_breakdownAlgos[#{slot}].sl_enabled = false;
      g_breakdownAlgos[#{slot}].sl_points = 0.0;
      g_breakdownAlgos[#{slot}].closetrade_after_some_time = false;
      g_breakdownAlgos[#{slot}].closetrade_after_some_time_butOnlyIfProfit = true;
      g_breakdownAlgos[#{slot}].closetrade_after_some_time_but_ProfitPercent_Needed = 2.0;
      g_breakdownAlgos[#{slot}].closetrade_after_x_minutes_from_breakdown = #{combo[:closetrade_after_x_minutes_from_breakdown]};
      g_breakdownAlgos[#{slot}].stop_trading_today_if_thisAlgo_total_trades_count = 3;
      g_breakdownAlgos[#{slot}].max_trades_per_breakdown_per_day = 1;
      g_breakdownAlgos[#{slot}].max_open_positions = #{combo[:max_open_positions]};
    MQL5
  end

  def append_params_block(inner, algo_id, combo)
    block = build_algo_params_block(algo_id, combo)
    return inner if inner.include?("BreakdownAlgoSlotIndexByAlgoId(#{magic_const(algo_id)})")

    inner.rstrip + "\n\n" + block
  end

  def append_rule_case(inner, algo_id)
    const = magic_const(algo_id)
    return inner if inner.match?(/^\s*case\s+#{const}\s*:/m)

    inner.rstrip + "\n" + <<~MQL5.rstrip
      case #{const}:
         // wire breakdown gates vs planned trade price here (AlgoRuleAdd_LevelBelowONH etc.)
         break;
    MQL5
  end

  def next_algo_ids(existing_ids, count)
    raise "Need at least one new algo id" if count <= 0

    ids = existing_ids.dup
    out = []
    candidate = ids.empty? ? BREAKDOWN_ID_MIN : ids.max + 1
    while out.size < count
      raise "Ran out of breakdown algo ids below #{BREAKDOWN_ID_MAX}" if candidate > BREAKDOWN_ID_MAX

      unless ids.include?(candidate)
        out << candidate
        ids << candidate
      end
      candidate += 1
    end
    out
  end

  def apply_combinations!(content, combinations)
    existing_ids = registry_algo_ids(content)
    new_ids = next_algo_ids(existing_ids, combinations.size)
    all_ids = (existing_ids + new_ids).uniq.sort

    inner1 = rebuild_registry_inner(all_ids)
    inner2 = extract_inner(content, 2)
    inner4 = extract_inner(content, 4)

    combinations.zip(new_ids).each do |combo, algo_id|
      inner2 = append_params_block(inner2, algo_id, combo)
      inner4 = append_rule_case(inner4, algo_id)
    end

    content = replace_inner(content, 1, inner1)
    content = replace_inner(content, 2, inner2)
    replace_inner(content, 4, inner4)
  end
end

include BreakdownCombinationsCreator

if __FILE__ == $PROGRAM_NAME
  dimension_counts = combination_dimension_counts
  total_combinations = dimension_counts.values.reduce(1, :*)
  valid_min_max_pairs = dimension_counts[:min_max_breakdown_sequence_len]

  puts "Breakdown algo combination count: #{total_combinations}"
  puts
  dimension_counts.each do |name, count|
    puts "  #{name}: #{count}"
  end
  puts
  puts "  (min_breakdown_sequence_len <= max_breakdown_sequence_len: #{valid_min_max_pairs} of #{DESIRED_MIN_BREAKDOWN_SEQUENCE_LEN.size * DESIRED_MAX_BREAKDOWN_SEQUENCE_LEN.size} pairs)"
  puts

  content = SmashMql5AlgoReader.load_mq5(MQ5_FILE)
  registry_max = breakdown_registry_max(content)
  wired_ids = registry_algo_ids(content)
  empty_slots = registry_max - wired_ids.size

  puts "Breakdown registry capacity: #{registry_max}"
  puts "Wired breakdown algos:       #{wired_ids.size} (#{wired_ids.join(', ')})"
  puts "Empty slots:                 #{empty_slots}"
  puts

  if total_combinations > empty_slots
    puts "NOT ENOUGH SLOTS: need #{total_combinations} empty slot(s), have #{empty_slots}."
    puts "Raise BREAKDOWN_ALGO_REGISTRY_MAX in aleksik2.mq5 or reduce combination grid."
    exit 1
  end

  if total_combinations.zero?
    puts "No combinations to create."
    exit 0
  end

  print "Create #{total_combinations} breakdown algo(s) in #{MQ5_FILE}? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  combinations = build_combinations
  raise "Combination build mismatch: #{combinations.size} != #{total_combinations}" if combinations.size != total_combinations

  updated = apply_combinations!(content, combinations)
  File.write(MQ5_FILE, updated)

  new_ids = registry_algo_ids(updated).last(total_combinations)
  puts "Created #{total_combinations} breakdown algo(s): #{new_ids.join(', ')}"
  puts MQ5_FILE
end
