#!/usr/bin/env ruby
# frozen_string_literal: true

# Cartesian product of desired_* arrays -> REPLACE all level algos in:
#   aleksik2.mq5            (registry + MAGIC_LEVEL* defines + LEVEL_ALGO_REGISTRY_MAX)
#   aleksik2_level_fam.mqh  (g_levelAlgos[...] param blocks)
#
# Does NOT append — deletes previous wired level algos and writes a fresh set from combo #1.

require "set"

MQ5_FILE = File.expand_path("aleksik2.mq5", __dir__)
LEVEL_FAM_FILE = File.expand_path("aleksik2_level_fam.mqh", __dir__)

LEVEL_ALGO_ID_MIN = 30_000_001
LEVEL_ALGO_ID_MAX = 39_999_999

MQ5_MARKERS = {
  1 => %w[//levelalgocreator1start //levelalgocreator1end]
}.freeze

LEVEL_FAM_MARKERS = {
  2 => %w[//levelalgocreator2start //levelalgocreator2end]
}.freeze

# --- edit combination grids here ---
DESIRED_MAX_OPEN_POSITIONS = [10].freeze
DESIRED_EXPIRY_MINUTES = [120].freeze

# :both -> trades_weekly=true, trades_daily=true
# :weekly -> trades_weekly=true, trades_daily=false
# :daily  -> trades_weekly=false, trades_daily=true
DESIRED_TRADES_WHAT_LEVELS = %i[both].freeze # [both weekly daily, both has highest profit, weekly has highest timevsprofit with OK profit. daily serves no purpose then?]

DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT = [10].freeze   # [1, 3: 3 is better]
#  [1, 3, 10] 10 is best? somehow had better avgtimeVSprofit and better avgavgDurationHours than 3.

DESIRED_SECRET_TP_PROFIT_PERCENT_MIN = [2.0, 8.0, 12.0, 30.0].freeze 
# [2.0, 4.0, 8.0, 25.0 tutaj 4 ma wszystko lepsze niz 2, a 8 i 25: wiekszy profit, slabsze timevsprofit] 
# [4.0, 6.0, 10.0, 20.0], stil more profit if higher target, but 10.0 had best profitvstime
# [8.0, 10.0, 12.0, 14.0, 20.0]
# 20 means SPX go up by 1% (leverage 1:20)
# [8.0, 10.0, 12.0, 14.0, 20.0] as always, higher means more profit


DESIRED_PRICE_PROXIMITY_ABOVE_LEVEL = [25.0].freeze
DESIRED_LEVEL_NEEDS_TO_BE_BELOW_ONO = [true].freeze # [true, false] seems no diff, can retest later with less options. we only trade down levels so this is irrelevant
DESIRED_OFFSET_POSITIVE = [true, false].freeze # true had 30% more profit than false
DESIRED_OFFSET_PERCENTAGE = [0.0003, 0.0006].freeze # [false, 0.0020 is very bad]  |   [0.0005, 0.0020 true, 20 has a bit more profit via more trades, but worse profitVStime]
DESIRED_CANNOT_TRADE__WHEN_LEVELPROXIMITY_MULTIPLYOFFSET = [1.2].freeze # 1.25 should properly block stacking multiple open trades on the same level. and profit still great
# group                              algo       percent_sum  timeVSprofit gross_profit
# ------------------------------------------------------------------------------------
# true, 0.0006, 1.2                  30000169   331.33       0.026        3735.40 # 1.2 always better than 2.0.  and from [0.0006, 0.001, 0.002] 6 always best
# true, 0.0006, 2.0                  30000171   323.99       0.027        3685.84
# true, 0.0010, 1.2                  30000173   304.62       0.025        3458.16
# true, 0.0010, 2.0                  30000175   279.26       0.026        3188.03
# true, 0.0020, 1.2                  30000177   290.79       0.028        3301.39
# true, 0.0020, 2.0                  30000179   260.50       0.029        2960.69
# false, 0.0006, 1.2                 30000181   294.27       0.025        3358.84  # FALSE ALWAYS WORSE THAN TRUE but with high multiply and offset the timevsprofit can be higher
# false, 0.0006, 2.0                 30000183   287.58       0.026        3285.64
# false, 0.0010, 1.2                 30000185   279.28       0.027        3206.02
# false, 0.0010, 2.0                 30000187   266.44       0.028        3043.53
# false, 0.0020, 1.2                 30000189   240.49       0.030        2757.34
# false, 0.0020, 2.0                 30000191   215.26       0.035        2451.79


# ([4.0, 1.0] 1.0 more trades than 4.0 so more profit, but worse avgDuration)
#  [1.0 129% profit  0.037 ratio , 0.5 146% profit  0.033 ratio] 
# [1.5, 1.0, 0.8, 0.5, 0.3] 1.5 super bad, but can test 1.2 vs 1.0.   1.0 had best timevsprift with OK profit, but 0.3 best profit. 
# [1.2, 1.0, 0.5, 0.3, 0.15] 1.2 never good, 0.5 had best percent_sum, tVSprof best for 0.2




# removed "all_up" as it had terrible stats. removed "all_tags". Removed "all_down". "all_down_pivot" has more trades so more profit, but much weaker timeVSprofit. For now let's go for max profit with 
DESIRED_TRADES_TAGS_PRESET = %i[
  all_down_pivot

  
].freeze

TRADES_TAGS_BY_PRESET = {
  all_tags: (1..5).map { |n| "Down#{n}" } + (1..5).map { |n| "Up#{n}" } + %w[Pivot],
  all_down: (1..5).map { |n| "Down#{n}" },
  all_up: (1..5).map { |n| "Up#{n}" },
  all_down_pivot: (1..5).map { |n| "Down#{n}" } + %w[Pivot]
}.freeze

COMBO_FIELDS = %i[
  max_open_positions
  expiry_minutes
  trades_what_levels
  stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
  secret_tp_profit_percent_min
  level_needs_to_be_below_ONO
  offset_positive
  offset_percentage
  cannotTrade__when_levelProximity_multiplyOffset
  trades_tags_preset
].freeze

module LevelCombinationsCreator
  module_function

  def marker_line_re(marker)
    /^\s*#{Regexp.escape(marker)}\s*$/
  end

  def extract_inner(content, markers)
    start_marker, end_marker = markers
    lines = content.lines
    start_idx = lines.index { |l| l.match?(marker_line_re(start_marker)) }
    end_idx = lines.index { |l| l.match?(marker_line_re(end_marker)) }
    unless start_idx && end_idx && end_idx > start_idx
      raise "Could not find block (#{start_marker} .. #{end_marker})"
    end

    lines[(start_idx + 1)...end_idx].join.rstrip
  end

  def replace_inner(content, markers, new_inner)
    start_marker, end_marker = markers
    lines = content.lines
    start_idx = lines.index { |l| l.match?(marker_line_re(start_marker)) }
    end_idx = lines.index { |l| l.match?(marker_line_re(end_marker)) }
    unless start_idx && end_idx && end_idx > start_idx
      raise "Could not find block (#{start_marker} .. #{end_marker})"
    end

    before = lines[0..start_idx].join
    after = lines[end_idx..].join
    "#{before}#{new_inner.rstrip}\n#{after}"
  end

  def level_registry_max(mq5_content)
    m = mq5_content.match(/#define\s+LEVEL_ALGO_REGISTRY_MAX\s+(\d+)/)
    raise "LEVEL_ALGO_REGISTRY_MAX not found in #{MQ5_FILE}" unless m

    m[1].to_i
  end

  def level_registry_max_headroom(mq5_content)
    m = mq5_content.match(/#define\s+LEVEL_ALGO_REGISTRY_MAX_HEADROOM\s+(\d+)/)
    raise "LEVEL_ALGO_REGISTRY_MAX_HEADROOM not found in #{MQ5_FILE}" unless m

    m[1].to_i
  end

  def set_level_registry_max(mq5_content, new_max)
    unless mq5_content.sub!(
      /#define\s+LEVEL_ALGO_REGISTRY_MAX\s+\d+/,
      format("#define LEVEL_ALGO_REGISTRY_MAX                  %d", new_max)
    )
      raise "Failed to update LEVEL_ALGO_REGISTRY_MAX in #{MQ5_FILE}"
    end

    mq5_content
  end

  def level_magic_const(algo_id)
    format("MAGIC_LEVEL%08d", algo_id)
  end

  def registry_algo_ids(mq5_content)
    block = extract_inner(mq5_content, MQ5_MARKERS[1])
    block.scan(/MAGIC_LEVEL(\d+)/).flatten.map(&:to_i).uniq.sort
  end

  def rebuild_registry_inner(algo_ids)
    lines = []
    lines << "int g_levelAlgoRegistryIds[] ="
    lines << "{"
    algo_ids.each { |algo_id| lines << "   #{level_magic_const(algo_id)}," }
    lines[-1] = lines[-1].sub(/,\z/, "") unless algo_ids.empty?
    lines << "};"
    lines.join("\n")
  end

  def replace_magic_level_defines(mq5_content, algo_ids)
    new_block = algo_ids.map do |algo_id|
      format("#define %-28s %d", level_magic_const(algo_id), algo_id)
    end.join("\n") + "\n"

    unless mq5_content.sub!(/(?:#define MAGIC_LEVEL\d+\s+\d+\s*\n)+/, new_block)
      raise "Failed to replace MAGIC_LEVEL* defines in #{MQ5_FILE}"
    end

    mq5_content
  end

  def trades_scope_for(preset)
    case preset
    when :both then { trades_weekly: true, trades_daily: true }
    when :weekly then { trades_weekly: true, trades_daily: false }
    when :daily then { trades_weekly: false, trades_daily: true }
    else
      raise "Unknown trades_what_levels preset: #{preset.inspect}"
    end
  end

  def normalize_combo_value(value)
    text = value.to_s.strip
    return "" if text.empty?

    downcased = text.downcase
    return "true" if %w[true 1 yes].include?(downcased)
    return "false" if %w[false 0 no].include?(downcased)

    return format("%.10g", Float(text)) if text.match?(/\A-?\d+(?:\.\d+)?\z/)

    text
  end

  def combo_signature(combo)
    tags = TRADES_TAGS_BY_PRESET.fetch(combo[:trades_tags_preset])
    fields = COMBO_FIELDS.map { |field| normalize_combo_value(combo[field]) }
    fields.join("\x1f") + "\x1f" + tags.join("|")
  end

  def combination_dimension_counts
    {
      max_open_positions: DESIRED_MAX_OPEN_POSITIONS.size,
      expiry_minutes: DESIRED_EXPIRY_MINUTES.size,
      trades_what_levels: DESIRED_TRADES_WHAT_LEVELS.size,
      stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count:
        DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT.size,
      secret_tp_profit_percent_min: DESIRED_SECRET_TP_PROFIT_PERCENT_MIN.size,
      level_needs_to_be_below_ONO: DESIRED_LEVEL_NEEDS_TO_BE_BELOW_ONO.size,
      offset_positive: DESIRED_OFFSET_POSITIVE.size,
      offset_percentage: DESIRED_OFFSET_PERCENTAGE.size,
      cannotTrade__when_levelProximity_multiplyOffset:
        DESIRED_CANNOT_TRADE__WHEN_LEVELPROXIMITY_MULTIPLYOFFSET.size,
      trades_tags_preset: DESIRED_TRADES_TAGS_PRESET.size
    }
  end

  def build_combinations
    combos = []
    seen = Set.new

    DESIRED_MAX_OPEN_POSITIONS.product(
      DESIRED_EXPIRY_MINUTES,
      DESIRED_TRADES_WHAT_LEVELS,
      DESIRED_STOP_TRADING_TODAY_IF_THISALGO_TODAYTOTAL_TRADES_COUNT,
      DESIRED_SECRET_TP_PROFIT_PERCENT_MIN,
      DESIRED_LEVEL_NEEDS_TO_BE_BELOW_ONO,
      DESIRED_OFFSET_POSITIVE,
      DESIRED_OFFSET_PERCENTAGE,
      DESIRED_CANNOT_TRADE__WHEN_LEVELPROXIMITY_MULTIPLYOFFSET,
      DESIRED_TRADES_TAGS_PRESET
    ) do |max_open, expiry, trades_scope, stop_total, secret_tp, below_ono, offset_pos, offset_pct, multiply_offset, tags_preset|
      combo = {
        max_open_positions: max_open,
        expiry_minutes: expiry,
        trades_what_levels: trades_scope,
        stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count: stop_total,
        secret_tp_profit_percent_min: secret_tp,
        level_needs_to_be_below_ONO: below_ono,
        offset_positive: offset_pos,
        offset_percentage: offset_pct,
        cannotTrade__when_levelProximity_multiplyOffset: multiply_offset,
        trades_tags_preset: tags_preset
      }.merge(trades_scope_for(trades_scope))

      signature = combo_signature(combo)
      next if seen.include?(signature)

      seen << signature
      combos << combo
    end

    combos
  end

  def format_mq5_double(value, decimals = 2)
    format("%.#{decimals}f", value.to_f)
  end

  def format_mq5_bool(value)
    value ? "true" : "false"
  end

  def build_trades_tags_lines(slot, tags)
    lines = []
    lines << "ArrayResize(g_levelAlgos[#{slot}].trades_tags, #{tags.size});"
    tags.each_with_index do |tag, idx|
      lines << %(g_levelAlgos[#{slot}].trades_tags[#{idx}] = "#{tag}";)
    end
    lines.join("\n")
  end

  def family_price_proximity_above_level
    if DESIRED_PRICE_PROXIMITY_ABOVE_LEVEL.size != 1
      warn "DESIRED_PRICE_PROXIMITY_ABOVE_LEVEL has #{DESIRED_PRICE_PROXIMITY_ABOVE_LEVEL.size} values; " \
           "using first (#{DESIRED_PRICE_PROXIMITY_ABOVE_LEVEL.first}) as family-wide g_levelAlgoShared.price_proximity_above_level"
    end
    DESIRED_PRICE_PROXIMITY_ABOVE_LEVEL.first
  end

  def set_family_price_proximity!(level_fam_content, proximity)
    line = "g_levelAlgoShared.price_proximity_above_level = #{format_mq5_double(proximity)};"
    if level_fam_content.match?(/g_levelAlgoShared\.price_proximity_above_level\s*=/)
      unless level_fam_content.sub!(
        /g_levelAlgoShared\.price_proximity_above_level\s*=\s*[^;]+;/,
        line
      )
        raise "Failed to update g_levelAlgoShared.price_proximity_above_level in #{LEVEL_FAM_FILE}"
      end
    else
      unless level_fam_content.sub!(
        /(\/\/levelalgocreator2start)/,
        "#{line}\n\\1"
      )
        raise "Could not insert g_levelAlgoShared.price_proximity_above_level before //levelalgocreator2start"
      end
    end

    level_fam_content
  end

  def build_algo_params_block(algo_id, combo)
    const = level_magic_const(algo_id)
    slot = "LevelAlgoSlotIndexByAlgoId(#{const})"
    tags = TRADES_TAGS_BY_PRESET.fetch(combo[:trades_tags_preset])

    lines = []
    lines << "g_levelAlgos[#{slot}].enabled = true;"
    lines << "g_levelAlgos[#{slot}].trades_weekly = #{format_mq5_bool(combo[:trades_weekly])};"
    lines << "g_levelAlgos[#{slot}].trades_daily = #{format_mq5_bool(combo[:trades_daily])};"
    lines << "g_levelAlgos[#{slot}].stop_trading_today_if_thisAlgo_losing_trades_count = 999;"
    lines << "g_levelAlgos[#{slot}].stop_trading_today_if_thisAlgo_winning_trades_count = 999;"
    lines << "g_levelAlgos[#{slot}].stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count = #{combo[:stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count]};"
    lines << "g_levelAlgos[#{slot}].expiry_minutes = #{combo[:expiry_minutes]};"
    lines << "g_levelAlgos[#{slot}].this_algo_max_concurrent_pending_trades = 1;"
    lines << "g_levelAlgos[#{slot}].max_open_positions = #{combo[:max_open_positions]};"
    lines << "g_levelAlgos[#{slot}].secret_tp_profit_percent_min = #{format_mq5_double(combo[:secret_tp_profit_percent_min])};"
    lines << "g_levelAlgos[#{slot}].secret_tp_greenguard_pricediff_at_least = 20.0;"
    lines << "g_levelAlgos[#{slot}].level_needs_to_be_below_ONO = #{format_mq5_bool(combo[:level_needs_to_be_below_ONO])};"
    lines << "g_levelAlgos[#{slot}].offset_positive = #{format_mq5_bool(combo[:offset_positive])};"
    lines << "g_levelAlgos[#{slot}].offset_percentage = #{format_mq5_double(combo[:offset_percentage], 4)};"
    lines << "g_levelAlgos[#{slot}].cannotTrade__when_levelProximity_multiplyOffset = #{format_mq5_double(combo[:cannotTrade__when_levelProximity_multiplyOffset], 2)};"
    lines << "g_levelAlgos[#{slot}].cannotTrade__when_thisAlgoOpenOrPendingNearLevel = true;"
    lines << build_trades_tags_lines(slot, tags)
    lines << "g_levelAlgos[#{slot}].real_tp = 555.0;"
    lines << "g_levelAlgos[#{slot}].rule_switch_map = 0;"
    lines.join("\n")
  end

  def algo_ids_for_count(count)
    raise "Need at least one level algo combination" if count <= 0

    last_id = LEVEL_ALGO_ID_MIN + count - 1
    raise "Ran out of level algo ids below #{LEVEL_ALGO_ID_MAX}" if last_id > LEVEL_ALGO_ID_MAX

    (LEVEL_ALGO_ID_MIN..last_id).to_a
  end

  def apply_combinations_overwrite!(mq5_content, level_fam_content, combinations)
    algo_ids = algo_ids_for_count(combinations.size)
    required_registry_max = combinations.size

    mq5_content = set_level_registry_max(mq5_content, required_registry_max)
    mq5_content = replace_magic_level_defines(mq5_content, algo_ids)

    registry_inner = rebuild_registry_inner(algo_ids)
    mq5_content = replace_inner(mq5_content, MQ5_MARKERS[1], registry_inner)

    params_inner =
      combinations.zip(algo_ids).map do |combo, algo_id|
        build_algo_params_block(algo_id, combo)
      end.join("\n\n")

    level_fam_content = replace_inner(level_fam_content, LEVEL_FAM_MARKERS[2], params_inner)
    level_fam_content = set_family_price_proximity!(level_fam_content, family_price_proximity_above_level)

    [mq5_content, level_fam_content]
  end
end

include LevelCombinationsCreator

if __FILE__ == $PROGRAM_NAME
  dimension_counts = combination_dimension_counts
  total_combinations = dimension_counts.values.reduce(1, :*)

  puts "Level algo combination count: #{total_combinations}"
  puts
  dimension_counts.each do |name, count|
    puts "  #{name}: #{count}"
  end
  puts
  puts "  trades_what_levels: #{DESIRED_TRADES_WHAT_LEVELS.join(', ')}"
  puts "  trades_tags presets: #{DESIRED_TRADES_TAGS_PRESET.join(', ')}"
  puts "  family price_proximity_above_level: #{family_price_proximity_above_level}"
  puts

  mq5_content = File.read(MQ5_FILE, encoding: "bom|utf-8")
  level_fam_content = File.read(LEVEL_FAM_FILE, encoding: "bom|utf-8")

  registry_max = level_registry_max(mq5_content)
  registry_headroom = level_registry_max_headroom(mq5_content)
  wired_ids = registry_algo_ids(mq5_content)

  all_combinations = build_combinations
  if all_combinations.size != total_combinations
    raise "Combination build mismatch: #{all_combinations.size} unique != #{total_combinations} cartesian"
  end

  new_algo_ids = algo_ids_for_count(all_combinations.size)
  required_registry_max = all_combinations.size

  puts "Registry slot capacity:    #{registry_max} (LEVEL_ALGO_REGISTRY_MAX in aleksik2.mq5)"
  puts "Registry headroom:         #{registry_headroom} (max unused slots above wired count)"
  puts "Currently wired level IDs: #{wired_ids.size} (#{wired_ids.join(', ')})"
  puts "Will REPLACE with:         #{all_combinations.size} algos"
  puts "New algo ID range:         #{new_algo_ids.first}..#{new_algo_ids.last}"
  puts "Required registry slots:   #{required_registry_max}"
  if required_registry_max > registry_max
    puts "Will raise LEVEL_ALGO_REGISTRY_MAX: #{registry_max} -> #{required_registry_max}"
  end
  puts
  puts "Mode: OVERWRITE (previous level algos in creator blocks are removed)"
  puts

  if all_combinations.empty?
    puts "No level algo combinations to create."
    exit 0
  end

  print "Overwrite level algos with #{all_combinations.size} combination(s)? [y/N] "
  answer = $stdin.gets&.strip&.downcase
  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  updated_mq5, updated_level_fam = apply_combinations_overwrite!(mq5_content, level_fam_content, all_combinations)
  File.write(MQ5_FILE, updated_mq5)
  File.write(LEVEL_FAM_FILE, updated_level_fam)

  puts "Wrote #{all_combinations.size} level algo(s): #{new_algo_ids.join(', ')}"
  puts "LEVEL_ALGO_REGISTRY_MAX: #{registry_max} -> #{required_registry_max}" if required_registry_max != registry_max
  puts MQ5_FILE
  puts LEVEL_FAM_FILE
end
