# frozen_string_literal: true
# Shared parsing for smash_mql5_reader_of_algo*.rb

module SmashMql5AlgoReader
  BOUNCE_CEILING_FIELDS = %w[
    bounceMaxAllowed_today min_bounceCount
    recentBounceCountToday_Minutes recentBounceCount_max_allowed
    min_weekly_bounce_required max_weekly_bounce_allowed
    physicalCeilingMaxAllowed_today proximityCeilingMaxAllowed_today
    min_ceilingCount recentCeilingCountToday_Minutes
    min_weekly_ceiling_required max_weekly_ceiling_allowed
    max_weekly_contact_candles_allowed
  ].freeze

  CONTACT_ONO_LIMIT_FIELDS = %w[
    max_daystart_earlierWeek_contactAndProx_allowed
    max_intraday_contactAndProx_today_allowed
    min_onoAboveLevel min_onoBelowLevel min_levelOnoAbsDiff
    max_allowed_shorts_perLevel_perDay_forThisAlgo
  ].freeze

  GAP_DAY_FIELDS = %w[
    min_gap_range_pts_exclusive max_gap_fill_pc_exclusive
  ].freeze

  PLACEMENT_FIELDS = %w[
    levelOffset priceProximity expiry_minutes
    min_cleanOHLC_streak_count max_cleanOHLC_streak_count
    min_anchorAbove_cleanStreak max_anchorAbove_cleanStreak
    min_anchorBelow_cleanStreak max_dayLowSoFar_belowLevel_dist
  ].freeze

  TUNE_DAY_LIMIT_FIELDS = %w[
    stop_trading_today_if_thisAlgo_losing_trades_count
    stop_trading_today_if_thisAlgo_winning_trades_count
    stop_trading_today_if_thisAlgo_total_trades_count
  ].freeze

  ASSIGN_RE = /
    g_algos\[AlgoSlotIndexByAlgoId\(MAGIC_ALGO(\d+)\)\]\.(\w+)\s*=\s*([^;]+);
  /x

  TUNE_ASSIGN_RE = /
    g_algos\[AlgoSlotIndexByAlgoId\(MAGIC_ALGO(\d+)\)\]\.tune\.(\w+)\s*=\s*([^;]+);
  /x

  module_function

  def load_mq5(path)
    File.read(path)
  end

  def params_by_algo_from_src(src)
    params = Hash.new { |h, k| h[k] = {} }
    src.scan(ASSIGN_RE) { |id, field, value| params[id.to_i][field] = value.strip }
    params
  end

  def tune_by_algo_from_src(src)
    tune = Hash.new { |h, k| h[k] = {} }
    src.scan(TUNE_ASSIGN_RE) do |id, field, value|
      tune[id.to_i][field] = value.strip.sub(%r{//.*}, "").strip
    end
    tune
  end

  def registry_algo_ids(src)
    registry = src[/int\s+g_algoRegistryIds\[\]\s*=\s*\{([^}]+)\}/m, 1]
    registry.scan(/MAGIC_ALGO(\d+)/).flatten.map(&:to_i)
  end

  def resolve(val, params)
    val = val.strip
    if (m = val.match(/\Aa\.(\w+)\z/))
      params[m[1]] || m[1]
    elsif (m = val.match(/\A"(.*)"\z/))
      m[1]
    else
      val
    end
  end

  def direction(val)
    return "?" unless val
    return "short" if val.include?("ALGO_SIDE_SHORT") || val == "true"
    return "long" if val.include?("ALGO_SIDE_LONG") || val == "false"
    val
  end

  def bool_label(val)
    val == "true" ? "yes" : "no"
  end

  def format_fields(params, fields)
    fields.filter_map { |f| params[f] ? "#{f}=#{params[f]}" : nil }.join(", ")
  end

  def parse_rule_line(line, params)
    line = line.sub(%r{//.*}, "").strip
    return nil if line.empty?

    rules = [
      [/AlgoRuleAdd_CleanStreakLong\([^,]+,\s*([^,]+),\s*([^)]+)\)/,
       ->(m) { "CleanStreakLong(min_streak=#{resolve(m[1], params)}, min_anchorAbove=#{resolve(m[2], params)})" }],
      [/AlgoRuleAdd_CleanStreakShort\([^,]+,\s*([^,]+),\s*([^)]+)\)/,
       ->(m) { "CleanStreakShort(min_streak=#{resolve(m[1], params)}, min_anchorBelow=#{resolve(m[2], params)})" }],
      [/AlgoRuleAdd_BounceCountTooHigh\([^,]+,\s*([^)]+)\)/,
       ->(m) { "dailyBounceCountTooHigh(max=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_WeekBounceCountTooLow\([^,]+,\s*([^)]+)\)/,
       ->(m) { "WeekBounceCountTooLow(min=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_WeekBounceCountTooHigh\([^,]+,\s*([^)]+)\)/,
       ->(m) { "WeekBounceCountTooHigh(max=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_WeekCeilingCountTooLow\([^,]+,\s*([^)]+)\)/,
       ->(m) { "WeekCeilingCountTooLow(min=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_WeekCeilingCountTooHigh\([^,]+,\s*([^)]+)\)/,
       ->(m) { "WeekCeilingCountTooHigh(max=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_WeekContactCandlesTooHigh\([^,]+,\s*([^)]+)\)/,
       ->(m) { "WeekContactCandlesTooHigh(max=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_DayStartEarlierWeekContactTooHigh\([^,]+,\s*([^)]+)\)/,
       ->(m) { "earlierWeekContactTooHigh(max=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_DayContactTodayTooHigh\([^,]+,\s*([^)]+)\)/,
       ->(m) { "contactTodayTooHigh(max=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_CeilingCountTooLow\([^,]+,\s*([^)]+)\)/,
       ->(m) { "dailyCeilingCountTooLow(min=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_CeilingCountTooHigh\([^,]+,\s*([^,]+),\s*([^)]+)\)/,
       ->(m) { "CeilingCountTooHigh(max=#{resolve(m[1], params)}, tag=#{resolve(m[2], params)})" }],
      [/AlgoRuleAdd_CeilingProximityCandlesTooHigh\([^,]+,\s*([^,]+),\s*([^)]+)\)/,
       ->(m) { "CeilingProximityCandlesTooHigh(max=#{resolve(m[1], params)}, tag=#{resolve(m[2], params)})" }],
      [/AlgoRuleAdd_LevelOnoAbsDiffTooLow\([^,]+,\s*([^)]+)\)/,
       ->(m) { "LevelOnoAbsDiffTooLow(min=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_OnoAboveLevelTooLow\([^,]+,\s*([^)]+)\)/,
       ->(m) { "onoAboveLevelTooLow(min=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_OnoBelowLevelTooLow\([^,]+,\s*([^)]+)\)/,
       ->(m) { "onoBelowLevelTooLow(min=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_AnchorAboveTooHigh\([^,]+,\s*([^)]+)\)/,
       ->(m) { "AnchorAboveTooHigh(max=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_DayLowSoFarNoMoreThanXBelowLevel\([^,]+,\s*([^)]+)\)/,
       ->(m) { "dayLowSoFarBelowLevel(max=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_DayOfWeek\([^,]+,\s*([^)]+)\)/,
       ->(m) { "DayOfWeek(dow=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_Session\([^,]+,\s*([^)]+)\)/,
       ->(m) { "Session(#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_(\w+)\(slotIdx\)\s*;/,
       ->(m) { m[1] }],
      [/AlgoRuleAdd_(\w+)\(slotIdx,\s*([^)]+)\)/,
       ->(m) { args = m[2].split(",").map { |a| resolve(a, params) }.join(", ")
                "#{m[1]}(#{args})" }],
      [/AlgoRuleChainAdd\(slotIdx,\s*(RULE_\w+)(?:,\s*(.+))?\)/,
       lambda { |m|
         rule = m[1]
         if m[2]
           args = m[2].split(",").map { |a| resolve(a, params) }.join(", ")
           "#{rule}(#{args})"
         else
           rule
         end
       }]
    ]

    rules.each do |re, builder|
      next unless (m = line.match(re))
      return builder.call(m)
    end

    nil
  end

  def rules_by_algo_from_src(src, params_by_algo)
    rule_switch = src[/void\s+AlgoRebuildRuleChainForSlot\b.*?switch\s*\(\s*algoId\s*\)\s*\{(.*?)\n\s*default:/m, 1]
    rules_by_algo = {}
    return rules_by_algo unless rule_switch

    rule_switch.scan(/case\s+MAGIC_ALGO(\d+):\s*(.*?)(?=case\s+MAGIC_ALGO|\z)/m) do |id, body|
      rules_by_algo[id.to_i] = body.lines.filter_map { |ln| parse_rule_line(ln, params_by_algo[id.to_i]) }
    end
    rules_by_algo
  end
end
