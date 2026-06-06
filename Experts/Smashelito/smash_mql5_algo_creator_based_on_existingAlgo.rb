#!/usr/bin/env ruby
# frozen_string_literal: true

# Creates a new algo in smashelito.mq5 by copying an existing one and optionally
# adding extra rules on top. Edits the four //algocreator* blocks.

MQ5_FILE = File.expand_path('smashelito.mq5', __dir__)

MIN_ALGO_ID = 10

MARKERS = {
  1 => %w[//algocreator1start //algocreator1end],
  2 => %w[//algocreator2start //algocreator2end],
  3 => %w[//algocreator3start //algocreator3end],
  4 => %w[//algocreator4start //algocreator4end]
}.freeze

DAY_OF_WEEK_SLOT = {
  'MON' => 1,
  'TUE' => 2,
  'WED' => 3,
  'THU' => 4,
  'FRI' => 5
}.freeze

# token => MQL5 call (uses AlgoDef tune fields where possible)
RULE_CATALOG = {
  'clean streak / anchor' => {
    'cleanStreakLong' => 'AlgoRuleAdd_CleanStreakLong(slotIdx, a.min_cleanOHLC_streak_count, a.min_anchorAbove_cleanStreak)',
    'cleanStreakShort' => 'AlgoRuleAdd_CleanStreakShort(slotIdx, a.min_cleanOHLC_streak_count, a.min_anchorBelow_cleanStreak)',
    'cleanStreakTooLong' => 'AlgoRuleAdd_CleanStreakTooLong(slotIdx, a.max_cleanOHLC_streak_count)',
    'anchorAboveTooHigh' => 'AlgoRuleAdd_AnchorAboveTooHigh(slotIdx, a.max_anchorAbove_cleanStreak)'
  },
  'bounce / ceiling counts (tune-backed)' => {
    'bounceCountTooHigh' => 'AlgoRuleAdd_BounceCountTooHigh(slotIdx, a.bounceMaxAllowed_today)',
    'bounceCountTooLow' => 'AlgoRuleAdd_BounceCountTooLow(slotIdx, a.min_bounceCount)',
    'recentBounceCountTooHigh' => 'AlgoRuleAdd_RecentBounceCountTooHigh(slotIdx, a.recentBounceCount_max_allowed)',
    'ceilingProximityCandlesTooHigh' => 'AlgoRuleAdd_CeilingProximityCandlesTooHigh(slotIdx, a.proximityCeilingMaxAllowed_today, "ceilingProximityCandlesTooHigh")',
    'ceilingCountTooHigh' => 'AlgoRuleAdd_CeilingCountTooHigh(slotIdx, a.physicalCeilingMaxAllowed_today, "todayCeilingCountTooHigh")',
    'ceilingCountTooLow' => 'AlgoRuleAdd_CeilingCountTooLow(slotIdx, a.min_ceilingCount)',
    'weekBounceCountTooLow' => 'AlgoRuleAdd_WeekBounceCountTooLow(slotIdx, a.min_weekly_bounce_required)',
    'weekBounceCountTooHigh' => 'AlgoRuleAdd_WeekBounceCountTooHigh(slotIdx, a.max_weekly_bounce_allowed)',
    'weekCeilingCountTooLow' => 'AlgoRuleAdd_WeekCeilingCountTooLow(slotIdx, a.min_weekly_ceiling_required)',
    'weekCeilingCountTooHigh' => 'AlgoRuleAdd_WeekCeilingCountTooHigh(slotIdx, a.max_weekly_ceiling_allowed)',
    'weekContactCandlesTooHigh' => 'AlgoRuleAdd_WeekContactCandlesTooHigh(slotIdx, a.max_weekly_contact_candles_allowed)'
  },
  'contact / ONO (tune-backed)' => {
    'dayStartEarlierWeekContactTooHigh' => 'AlgoRuleAdd_DayStartEarlierWeekContactTooHigh(slotIdx, a.max_daystart_earlierWeek_contactAndProx_allowed)',
    'dayContactTodayTooHigh' => 'AlgoRuleAdd_DayContactTodayTooHigh(slotIdx, a.max_intraday_contactAndProx_today_allowed)',
    'levelOnoAbsDiffTooLow' => 'AlgoRuleAdd_LevelOnoAbsDiffTooLow(slotIdx, a.min_levelOnoAbsDiff)',
    'onoAboveLevelTooLow' => 'AlgoRuleAdd_OnoAboveLevelTooLow(slotIdx, a.min_onoAboveLevel)',
    'onoBelowLevelTooLow' => 'AlgoRuleAdd_OnoBelowLevelTooLow(slotIdx, a.min_onoBelowLevel)'
  },
  'day high/low distance (tune or literal)' => {
    'dayLowSoFarNoMoreThanXBelowLevel' => 'AlgoRuleAdd_DayLowSoFarNoMoreThanXBelowLevel(slotIdx, a.max_dayLowSoFar_belowLevel_dist)',
    'dayLowSoFarAtLeastXBelowLevel=2.0' => 'AlgoRuleAdd_DayLowSoFarAtLeastXBelowLevel(slotIdx, 2.0)',
    'dayHighSoFarAtLeastXAboveLevel=2.0' => 'AlgoRuleAdd_DayHighSoFarAtLeastXAboveLevel(slotIdx, 2.0)',
    'dayHighSoFarNoMoreThanXAboveLevel=5.0' => 'AlgoRuleAdd_DayHighSoFarNoMoreThanXAboveLevel(slotIdx, 5.0)'
  },
  'gap / RTHO (tune-backed)' => {
    'rthoTertiaryReady' => 'AlgoRuleAdd_RthoTertiaryReady(slotIdx)',
    'dayGapDownRequired' => 'AlgoRuleAdd_DayGapDownRequired(slotIdx)',
    'dayGapUpRequired' => 'AlgoRuleAdd_DayGapUpRequired(slotIdx)',
    'gapRangePtsAbove' => 'AlgoRuleAdd_GapRangePtsAbove(slotIdx, a.min_gap_range_pts_exclusive)',
    'gapFillPcBelow' => 'AlgoRuleAdd_GapFillPcBelow(slotIdx, a.max_gap_fill_pc_exclusive)'
  },
  'day broke prior day high/low' => {
    'dayBrokePDH=true' => 'AlgoRuleAdd_DayBrokePDHtrue(slotIdx)',
    'dayBrokePDH=false' => 'AlgoRuleAdd_DayBrokePDHfalse(slotIdx)',
    'dayBrokePDL=true' => 'AlgoRuleAdd_DayBrokePDLtrue(slotIdx)',
    'dayBrokePDL=false' => 'AlgoRuleAdd_DayBrokePDLfalse(slotIdx)'
  },
  'prior day trend' => {
    'PD_trend=PD_green' => 'AlgoRuleAdd_PDgreen(slotIdx)',
    'PD_trend=PD_red' => 'AlgoRuleAdd_PDred(slotIdx)'
  },
  'open gap' => {
    'openGap_info=unknown' => 'AlgoRuleAdd_OpenGapInfoUnknown(slotIdx)',
    'openGap_info=gapUp_Day' => 'AlgoRuleAdd_DayGapUpRequired(slotIdx)',
    'openGap_info=gapDown_Day' => 'AlgoRuleAdd_DayGapDownRequired(slotIdx)'
  },
  'level tag' => {
    'levelTag=dailySmash' => 'AlgoRuleAdd_LevelTagDailySmash(slotIdx)',
    'levelTag=dailyUp1' => 'AlgoRuleAdd_LevelTagDailyUp1(slotIdx)',
    'levelTag=todayRTHopen' => 'AlgoRuleAdd_LevelTagTodayRthOpen(slotIdx)'
  },
  'session' => {
    'session=ON' => 'AlgoRuleAdd_Session(slotIdx, "ON")',
    'session=RTH-IB' => 'AlgoRuleAdd_Session(slotIdx, "RTH-IB")',
    'session=RTH-afterIB' => 'AlgoRuleAdd_Session(slotIdx, "RTH-afterIB")',
    'session=full' => 'AlgoRuleAdd_Session(slotIdx, "full")'
  },
  'day of week (pick one)' => {
    'day_of_week=MON' => '__DAY_OF_WEEK__:1',
    'day_of_week=TUE' => '__DAY_OF_WEEK__:2',
    'day_of_week=WED' => '__DAY_OF_WEEK__:3',
    'day_of_week=THU' => '__DAY_OF_WEEK__:4',
    'day_of_week=FRI' => '__DAY_OF_WEEK__:5'
  },
  'level vs PDO' => {
    'below_PDO=true' => 'AlgoRuleAdd_LevelBelowPDO(slotIdx)',
    'above_PDO=true' => 'AlgoRuleAdd_LevelAbovePDO(slotIdx)'
  },
  'level vs PDH / PDL / PDC' => {
    'below_PDH=true' => 'AlgoRuleAdd_LevelBelowPDH(slotIdx)',
    'above_PDH=true' => 'AlgoRuleAdd_LevelAbovePDH(slotIdx)',
    'below_PDL=true' => 'AlgoRuleAdd_LevelBelowPDL(slotIdx)',
    'above_PDL=true' => 'AlgoRuleAdd_LevelAbovePDL(slotIdx)',
    'below_PDC=true' => 'AlgoRuleAdd_LevelBelowPDC(slotIdx)',
    'above_PDC=true' => 'AlgoRuleAdd_LevelAbovePDC(slotIdx)'
  },
  'level vs ONH / ONL' => {
    'below_ONH=true' => 'AlgoRuleAdd_LevelBelowONH(slotIdx)',
    'above_ONH=true' => 'AlgoRuleAdd_LevelAboveONH(slotIdx)',
    'below_ONL=true' => 'AlgoRuleAdd_LevelBelowONL(slotIdx)',
    'above_ONL=true' => 'AlgoRuleAdd_LevelAboveONL(slotIdx)'
  },
  'level vs RTH high/low' => {
    'below_RTHH=true' => 'AlgoRuleAdd_LevelBelowRTHH(slotIdx)',
    'above_RTHH=true' => 'AlgoRuleAdd_LevelAboveRTHH(slotIdx)',
    'below_RTHL=true' => 'AlgoRuleAdd_LevelBelowRTHL(slotIdx)',
    'above_RTHL=true' => 'AlgoRuleAdd_LevelAboveRTHL(slotIdx)'
  },
  'level vs IB high/low' => {
    'below_IBL=true' => 'AlgoRuleAdd_LevelBelowIBL(slotIdx)',
    'above_IBL=true' => 'AlgoRuleAdd_LevelAboveIBL(slotIdx)',
    'below_IBH=true' => 'AlgoRuleAdd_LevelBelowIBH(slotIdx)',
    'above_IBH=true' => 'AlgoRuleAdd_LevelAboveIBH(slotIdx)'
  },
  'level vs day high/low so far' => {
    'below_dayHighSoFar=true' => 'AlgoRuleAdd_LevelBelowDayHighSoFar(slotIdx)',
    'above_dayHighSoFar=true' => 'AlgoRuleAdd_LevelAboveDayHighSoFar(slotIdx)',
    'below_dayLowSoFar=true' => 'AlgoRuleAdd_LevelBelowDayLowSoFar(slotIdx)',
    'above_dayLowSoFar=true' => 'AlgoRuleAdd_LevelAboveDayLowSoFar(slotIdx)'
  },
  'level vs midpoint' => {
    'below_midpoint=true' => 'AlgoRuleAdd_LevelBelowMidpoint(slotIdx)',
    'above_midpoint=true' => 'AlgoRuleAdd_LevelAboveMidpoint(slotIdx)'
  },
  'weekly contact (literal min count)' => {
    'weekContactCandlesTooLow=2' => 'AlgoRuleAdd_WeekContactCandlesTooLow(slotIdx, 2)'
  }
}.freeze

EXTRA_RULE_TO_MQL5 = RULE_CATALOG.values.reduce({}, :merge).freeze

# token=VALUE overrides for rules not stored on AlgoDef
LITERAL_RULE_PATTERNS = [
  [/\AweekContactCandlesTooLow=(\d+)\z/, 'AlgoRuleAdd_WeekContactCandlesTooLow(slotIdx, %<n>d)'],
  [/\AdayLowSoFarAtLeastXBelowLevel=([\d.]+)\z/, 'AlgoRuleAdd_DayLowSoFarAtLeastXBelowLevel(slotIdx, %<n>s)'],
  [/\AdayHighSoFarAtLeastXAboveLevel=([\d.]+)\z/, 'AlgoRuleAdd_DayHighSoFarAtLeastXAboveLevel(slotIdx, %<n>s)'],
  [/\AdayHighSoFarNoMoreThanXAboveLevel=([\d.]+)\z/, 'AlgoRuleAdd_DayHighSoFarNoMoreThanXAboveLevel(slotIdx, %<n>s)']
].freeze

# --- CONFIG (edit before running) ---

copy_from_algo_id = 18

# Rules copied from copy_from_algo_id; uncommented lines below are ADDED (duplicates skipped).
# Shorthand below_PDH also accepts below_PDH=true.
extra_rules = <<~RULES
  # --- clean streak / anchor ---
  # cleanStreakLong
  # cleanStreakShort
  # cleanStreakTooLong
  # anchorAboveTooHigh

  # --- bounce / ceiling counts (tune-backed) ---
  # bounceCountTooHigh
  # bounceCountTooLow
  # recentBounceCountTooHigh
  # ceilingProximityCandlesTooHigh
  # ceilingCountTooHigh
  # ceilingCountTooLow
  # weekBounceCountTooLow
  # weekBounceCountTooHigh
  # weekCeilingCountTooLow
  # weekCeilingCountTooHigh
  # weekContactCandlesTooHigh

  # --- contact / ONO (tune-backed) ---
  # dayStartEarlierWeekContactTooHigh
  # dayContactTodayTooHigh
  # levelOnoAbsDiffTooLow
  # onoAboveLevelTooLow
  # onoBelowLevelTooLow

  # --- day high/low distance (tune or literal) ---
  # dayLowSoFarNoMoreThanXBelowLevel
  # dayLowSoFarAtLeastXBelowLevel=2.0
  # dayHighSoFarAtLeastXAboveLevel=2.0
  # dayHighSoFarNoMoreThanXAboveLevel=5.0

  # --- gap / RTHO (tune-backed) ---
  # rthoTertiaryReady
  # dayGapDownRequired
  # dayGapUpRequired
  # gapRangePtsAbove
  # gapFillPcBelow

  # --- day broke prior day high/low ---
  # dayBrokePDH=true
  # dayBrokePDH=false
  # dayBrokePDL=true
  dayBrokePDL=false

  # --- prior day trend ---
  # PD_trend=PD_green
  # PD_trend=PD_red

  # --- open gap ---
  # openGap_info=unknown
  # openGap_info=gapUp_Day
  # openGap_info=gapDown_Day

  # --- level tag ---
  # levelTag=dailySmash
  # levelTag=dailyUp1
  # levelTag=todayRTHopen

  # --- session ---
  # session=ON
  # session=RTH-IB
  # session=RTH-afterIB
  # session=full

  # --- day of week (pick one) ---
  # day_of_week=MON
  # day_of_week=TUE
  # day_of_week=WED
  # day_of_week=THU
  # day_of_week=FRI

  # --- level vs PDO ---
  # below_PDO=true
  # above_PDO=true

  # --- level vs PDH / PDL / PDC ---
  below_PDH=true
  # above_PDH=true
  # below_PDL=true
  # above_PDL=true
  below_PDC=true
  # above_PDC=true

  # --- level vs ONH / ONL ---
  below_ONH=true
  # above_ONH=true
  below_ONL=true
  # above_ONL=true

  # --- level vs RTH high/low ---
  below_RTHH=true
  # above_RTHH=true
  below_RTHL=true
  # above_RTHL=true

  # --- level vs IB high/low ---
  below_IBL=true
  # above_IBL=true
  below_IBH=true
  # above_IBH=true

  # --- level vs day high/low so far ---
  below_dayHighSoFar=true
  # above_dayHighSoFar=true
  below_dayLowSoFar=true
  # above_dayLowSoFar=true

  # --- level vs midpoint ---
  below_midpoint=true
  # above_midpoint=true

  # --- weekly contact (literal min count; edit number) ---
  # weekContactCandlesTooLow=2
RULES

module AlgoCreator
  module_function

  def magic_const(id)
    "MAGIC_ALGO#{id}"
  end

  def read_mq5
    File.read(MQ5_FILE, encoding: 'BOM|UTF-8')
  end

  def write_mq5!(content)
    File.write(MQ5_FILE, content)
  end

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

  def print_block(block_num, inner)
    start_marker, end_marker = MARKERS.fetch(block_num)
    puts '=' * 80
    puts "BLOCK #{block_num} (#{start_marker} .. #{end_marker})"
    puts '=' * 80
    puts inner
    puts
  end

  def rules_template_all_commented
    RULE_CATALOG.flat_map do |section, rules|
      [
        "  # --- #{section} ---",
        *rules.keys.map { |token| "  # #{token}" },
        ''
      ]
    end.join("\n").rstrip
  end

  def print_rules_template!
    puts rules_template_all_commented
  end

  def existing_algo_ids(content)
    ids = content.scan(/#define\s+MAGIC_ALGO(\d+)\s+\1\b/).flatten.map(&:to_i)
    ids |= content.scan(/MAGIC_ALGO(\d+)/).flatten.map(&:to_i)
    ids.select { |id| id >= MIN_ALGO_ID }.uniq.sort
  end

  def next_unused_algo_id(content)
    ids = existing_algo_ids(content)
    raise "No algos found (expected MAGIC_ALGO#{MIN_ALGO_ID}+)" if ids.empty?

    candidate = ids.max + 1
    candidate += 1 while ids.include?(candidate)
    candidate
  end

  def registry_ids_from_block1(inner)
    inner
      .lines
      .select { |l| l.match?(/#define\s+MAGIC_ALGO(\d+)\s+\1\b/) }
      .map { |l| l[/MAGIC_ALGO(\d+)/, 1].to_i }
      .uniq
      .sort
  end

  def registry_ids(block1_inner)
    registry_ids_from_block1(block1_inner)
  end

  def format_registry_array(ids)
    body = ids.map.with_index do |id, idx|
      suffix = idx == ids.length - 1 ? '' : ','
      "   #{magic_const(id)}#{suffix}"
    end
    ["int g_algoRegistryIds[] =", '{', *body, '};'].join("\n")
  end

  def rebuild_block1(inner, new_id: nil)
    lines = inner.lines.map(&:chomp)
    raw_define_lines = lines.select { |l| l.match?(/#define\s+MAGIC_ALGO\d+/) }

    if new_id
      const = magic_const(new_id)
      raise "Algo #{new_id} already defined in algocreator1 block" if raw_define_lines.any? { |l| l.include?(const) }

      sample_define = raw_define_lines.find { |l| l.match?(/#define\s+MAGIC_ALGO\d+\s+\d+/) }
      pad =
        if sample_define&.match(/#define\s+MAGIC_ALGO\d+(\s+)\d+/)
          Regexp.last_match(1).length
        else
          16
        end
      raw_define_lines << "#define #{const}#{' ' * pad}#{new_id}"
    end

    ids = raw_define_lines
          .map { |l| l[/MAGIC_ALGO(\d+)/, 1].to_i }
          .uniq
          .sort
    existing_by_id = {}
    raw_define_lines.each { |l| existing_by_id[l[/MAGIC_ALGO(\d+)/, 1].to_i] = l }
    define_lines = ids.map do |id|
      existing_by_id[id] || "#define #{magic_const(id)}#{' ' * 16}#{id}"
    end

    comment = lines.find { |l| l.include?('wired algo magic prefixes') } ||
              '// wired algo magic prefixes — add MAGIC_ALGO* define + id here + tune block in Sync'

    [define_lines, comment, '', format_registry_array(ids)].flatten.join("\n")
  end

  def parse_block3_algo_ids(inner)
    inner
      .scan(/g_algos\[ai\]\.algo_id\s*==\s*(MAGIC_ALGO\d+)/)
      .flatten
      .map { |c| c[/(\d+)/, 1].to_i }
      .uniq
      .sort
  end

  def format_block3(ids)
    raise 'algocreator3 block is empty' if ids.empty?

    out = ["      if(g_algos[ai].algo_id == #{magic_const(ids.first)}"]
    ids[1..].each do |id|
      out << "         || g_algos[ai].algo_id == #{magic_const(id)}"
    end
    out << '         )'
    out << '         continue;'
    out.join("\n")
  end

  def rebuild_block3(inner, add_id: nil)
    ids = parse_block3_algo_ids(inner)
    ids << add_id if add_id && !ids.include?(add_id)
    format_block3(ids.sort)
  end

  def normalize_block1!(content)
    replace_inner(content, 1, rebuild_block1(extract_inner(content, 1)))
  end

  def normalize_block3!(content)
    replace_inner(content, 3, rebuild_block3(extract_inner(content, 3)))
  end

  def update_block1(inner, new_id)
    rebuild_block1(inner, new_id: new_id)
  end

  def extract_tune_block(block2_inner, source_id)
    const = magic_const(source_id)
    prefix = "   g_algos[AlgoSlotIndexByAlgoId(#{const})]"
    lines = block2_inner.lines.map(&:chomp)
    start_idx = lines.index { |l| l.start_with?(prefix) }
    raise "Tune block for algo #{source_id} not found in algocreator2" unless start_idx

    tune_lines = []
    i = start_idx
    while i < lines.length && lines[i].start_with?(prefix)
      tune_lines << lines[i]
      i += 1
    end

    raise "Empty tune block for algo #{source_id}" if tune_lines.empty?

    tune_lines.join("\n")
  end

  def clone_tune_block(tune_text, source_id, new_id)
    tune_text.gsub(magic_const(source_id), magic_const(new_id))
  end

  def update_block2(inner, source_id, new_id)
    tune = extract_tune_block(inner, source_id)
    cloned = clone_tune_block(tune, source_id, new_id)
    raise "Algo #{new_id} tune block already present in algocreator2" if inner.include?(magic_const(new_id))

    inner.rstrip + "\n\n" + cloned
  end

  def copy_from_in_weekly_exception_list?(block3_inner, source_id)
    block3_inner.include?(magic_const(source_id))
  end

  def update_block3(inner, new_id)
    const = magic_const(new_id)
    return inner if inner.include?(const)

    rebuild_block3(inner, add_id: new_id)
  end

  def extract_rule_case_block(block4_inner, source_id)
    const = magic_const(source_id)
    lines = block4_inner.lines.map(&:chomp)

    case_idx = lines.index { |l| l.match?(/^\s*case\s+#{const}\s*:/) }
    raise "Rule case for algo #{source_id} not found in algocreator4" unless case_idx

    start_idx = case_idx
    start_idx -= 1 while start_idx.positive? && lines[start_idx - 1].match?(/^\s*case\s+MAGIC_ALGO\d+\s*:/)

    break_idx = start_idx
    break_idx += 1 while break_idx < lines.length && !lines[break_idx].match?(/^\s*break\s*;/)
    raise "No break; after case #{const} in algocreator4" unless break_idx < lines.length

    lines[start_idx..break_idx].join("\n")
  end

  def extract_rule_case_block_for_id(block4_inner, algo_id)
    const = magic_const(algo_id)
    lines = block4_inner.lines.map(&:chomp)
    case_idx = lines.index { |l| l.match?(/^\s*case\s+#{const}\s*:/) }
    raise "Rule case for algo #{algo_id} not found in algocreator4" unless case_idx

    break_idx = case_idx
    break_idx += 1 while break_idx < lines.length && !lines[break_idx].match?(/^\s*break\s*;/)
    lines[case_idx..break_idx].join("\n")
  end

  def normalize_extra_rule_token(raw)
    line = raw.to_s.strip
    return nil if line.empty?
    return nil if line.start_with?('#')

    token = line.sub(/\s+#.*\z/, '').strip
    return nil if token.empty?

    token = token.sub(/\Abelow_(\w+)\z/, 'below_\1=true')
    token = token.sub(/\Aabove_(\w+)\z/, 'above_\1=true')

    if (m = token.match(/\Aday_of_week=(MON|TUE|WED|THU|FRI)\z/))
      slot = DAY_OF_WEEK_SLOT.fetch(m[1])
      return "day_of_week:#{slot}"
    end

    token
  end

  def extra_rule_lines(extra_rules_text)
    return [] if extra_rules_text.nil? || extra_rules_text.strip.empty?

    extra_rules_text
      .lines
      .map { |l| normalize_extra_rule_token(l) }
      .compact
      .uniq
  end

  def rule_call_signature(mql5_line)
    mql5_line.strip.sub(/;\z/, '')[/AlgoRuleAdd_\w+/, 0]
  end

  def mql5_line_for_extra_rule(token)
    if (m = token.match(/\Aday_of_week:(\d)\z/))
      return "         AlgoRuleAdd_DayOfWeek(slotIdx, #{m[1]});"
    end

    LITERAL_RULE_PATTERNS.each do |pattern, template|
      if (m = token.match(pattern))
        call = format(template, n: m[1])
        return "         #{call};"
      end
    end

    call = EXTRA_RULE_TO_MQL5[token]
    if call&.start_with?('__DAY_OF_WEEK__:')
      slot = call.split(':').last
      return "         AlgoRuleAdd_DayOfWeek(slotIdx, #{slot});"
    end

    raise "Unknown extra rule token: #{token.inspect} (see RULE_CATALOG in #{File.basename(__FILE__)})" unless call

    "         #{call};"
  end

  def clone_rule_case(case_text, source_id, new_id, extra_tokens)
    lines = case_text.lines.map(&:chomp)

    body_start = lines.index { |l| l.match?(/^\s*case\s+/) }
    break_idx = lines.index { |l| l.match?(/^\s*break\s*;/) }
    body = lines[(body_start + 1)...break_idx]
    body.reject! { |l| l.include?('RULE_TRADES_AT_LEVEL_LIMIT') }

    existing_sigs = body.map { |l| rule_call_signature(l) }.compact
    extra_lines = []
    extra_tokens.each do |token|
      line = mql5_line_for_extra_rule(token)
      sig = rule_call_signature(line)
      next if sig && existing_sigs.include?(sig)

      extra_lines << line
      existing_sigs << sig if sig
    end

    new_body = body + extra_lines

    out = []
    out << "      case #{magic_const(new_id)}:"
    new_body.each { |l| out << l }
    out << '         break;'
    out.join("\n")
  end

  def update_block4(inner, source_id, new_id, extra_tokens)
    raise "Algo #{new_id} rule case already present in algocreator4" if inner.match?(/^\s*case\s+#{magic_const(new_id)}\s*:/m)

    case_text = extract_rule_case_block(inner, source_id)
    cloned = clone_rule_case(case_text, source_id, new_id, extra_tokens)
    inner.rstrip + "\n" + cloned
  end

  def bump_registry_max(content, required_count)
    m = content.match(/#define\s+ALGO_FAMILY_REGISTRY_MAX\s+(\d+)/)
    return content unless m

    current = m[1].to_i
    return content if required_count <= current

    content.sub(
      /#define\s+ALGO_FAMILY_REGISTRY_MAX\s+\d+/,
      "#define ALGO_FAMILY_REGISTRY_MAX  #{required_count}"
    )
  end

  def run(copy_from:, extra_rules_text:)
    content = read_mq5
    new_id = next_unused_algo_id(content)
    source_id = copy_from.to_i

    raise "copy_from_algo_id must be >= #{MIN_ALGO_ID}" if source_id < MIN_ALGO_ID
    raise "Source algo #{source_id} not found in #{MQ5_FILE}" unless existing_algo_ids(content).include?(source_id)

    extra_tokens = extra_rule_lines(extra_rules_text)

    b1 = extract_inner(content, 1)
    b2 = extract_inner(content, 2)
    b3 = extract_inner(content, 3)
    b4 = extract_inner(content, 4)

    new_b1 = update_block1(b1, new_id)
    new_b2 = update_block2(b2, source_id, new_id)
    new_b3 = if copy_from_in_weekly_exception_list?(b3, source_id)
               update_block3(b3, new_id)
             else
               b3
             end
    new_b4 = update_block4(b4, source_id, new_id, extra_tokens)

    content = replace_inner(content, 1, new_b1)
    content = replace_inner(content, 2, new_b2)
    content = replace_inner(content, 3, new_b3)
    content = replace_inner(content, 4, new_b4)

    content = normalize_block1!(content)
    content = normalize_block3!(content)

    required_registry = registry_ids(extract_inner(content, 1)).size
    content = bump_registry_max(content, required_registry)

    write_mq5!(content)

    puts
    puts "Created algo #{new_id} (copy of algo #{source_id}) in #{MQ5_FILE}"
    puts "ALGO_FAMILY_REGISTRY_MAX set to at least #{required_registry}"
    puts "Extra rules added: #{extra_tokens.empty? ? '(none)' : extra_tokens.join(', ')}"
    puts

    print_block(1, extract_inner(content, 1))
    print_block(2, extract_tune_block(new_b2, new_id))
    print_block(3, extract_inner(content, 3))
    print_block(4, extract_rule_case_block_for_id(new_b4, new_id))

    new_id
  end

  def normalize_formatting!
    content = read_mq5
    content = normalize_block1!(content)
    content = normalize_block3!(content)
    write_mq5!(content)

    puts "Normalized algocreator1 registry + algocreator3 weekly-exception formatting in #{MQ5_FILE}"
    print_block(1, extract_inner(content, 1))
    print_block(3, extract_inner(content, 3))
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.include?('--normalize')
    AlgoCreator.normalize_formatting!
  elsif ARGV.include?('--print-rules-template')
    AlgoCreator.print_rules_template!
  else
    AlgoCreator.run(copy_from: copy_from_algo_id, extra_rules_text: extra_rules)
  end
end
