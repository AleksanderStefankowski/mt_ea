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
    max_allowed_trades_perLevel_perDay_forThisAlgo
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
       ->(m) { "todayBounceCountTooHigh(max=#{resolve(m[1], params)})" }],
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
       ->(m) { "contactAndProximityCandlesTodayTooHigh(max=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_CeilingCountTooLow\([^,]+,\s*([^)]+)\)/,
       ->(m) { "dailyCeilingCountTooLow(min=#{resolve(m[1], params)})" }],
      [/AlgoRuleAdd_CeilingCountTooHigh\([^,]+,\s*([^,]+),\s*([^)]+)\)/,
       ->(m) { "todayCeilingCountTooHigh(max=#{resolve(m[1], params)})" }],
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

    pending_ids = []
    body_lines = []

    rule_switch.each_line do |line|
      stripped = line.sub(%r{//.*}, "").strip
      if (m = stripped.match(/\Acase\s+MAGIC_ALGO(\d+):\z/))
        pending_ids << m[1].to_i
      elsif stripped == "break;"
        pending_ids.each do |id|
          rules_by_algo[id] = body_lines.filter_map { |ln| parse_rule_line(ln, params_by_algo[id]) }
        end
        pending_ids = []
        body_lines = []
      elsif !stripped.empty? && !pending_ids.empty?
        body_lines << line
      end
    end

    rules_by_algo
  end

  # 18-digit Falgo composite magic (smashelito.mq5 layout).
  module FalgoMagic
    MAGIC_LEN = 18

    DAY_LABEL = {
      "1" => "MON",
      "2" => "TUE",
      "3" => "WED",
      "4" => "THU",
      "5" => "FRI"
    }.freeze

    module_function

    def pad_magic(raw)
      s = raw.to_s.strip
      raise ArgumentError, "Magic must be #{MAGIC_LEN} digits (got #{s.length}: #{s})" unless s.match?(/\A\d+\z/)
      raise ArgumentError, "Magic must be at most #{MAGIC_LEN} digits (got #{s.length})" if s.length > MAGIC_LEN

      s.rjust(MAGIC_LEN, "0")
    end

    def level_slot_label(slot)
      return "tertiary RTHO" if slot == 0
      return "tertiary PDrthClose" if slot == 1
      if slot >= 10 && slot <= 30
        center = 20
        return "weekly smash" if slot == center
        return "weekly up#{slot - center}" if slot > center

        return "weekly down#{center - slot}"
      end
      if slot >= 50 && slot <= 70
        center = 60
        return "daily smash" if slot == center
        return "daily up#{slot - center}" if slot > center

        return "daily down#{center - slot}"
      end
      "unknown (#{slot})"
    end

    def parse(raw_magic)
      m = pad_magic(raw_magic)
      {
        raw: m,
        algo: m[0, 2].to_i,
        direction: m[2].to_i,
        day_of_week_digit: m[3],
        day_of_week: DAY_LABEL[m[3]] || "UNKNOWN",
        level_slot: m[4, 2].to_i,
        bounce_count: m[6].to_i,
        ceiling_count: m[7].to_i,
        offset_tenths: m[8, 2].to_i,
        plan_trade_num: m[10].to_i,
        level_trade_num: m[11].to_i,
        babysit_minute: m[12].to_i,
        unused_slot: m[13].to_i,
        tp_whole: m[14, 2].to_i,
        sl_whole: m[16, 2].to_i
      }
    end

    def apply_trade_fields!(trade, raw_magic)
      d = parse(raw_magic)
      trade[:magic_prefix] = format("%02d", d[:algo])
      trade[:direction_magic] = d[:direction]
      trade[:day_of_week] = d[:day_of_week]
      trade[:levelSlot] = d[:level_slot]
      trade[:levelSlotLabel] = level_slot_label(d[:level_slot])
      trade[:bounce_count] = d[:bounce_count]
      trade[:ceiling_count] = d[:ceiling_count]
      trade[:offset_tenths] = d[:offset_tenths]
      trade[:plan_trade_num] = d[:plan_trade_num]
      trade[:level_trade_num] = d[:level_trade_num]
      trade
    end
  end
end
