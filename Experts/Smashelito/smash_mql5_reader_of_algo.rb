#!/usr/bin/env ruby
# Lists each wired algo: id, direction, bounce/ceiling params, ruleset.

MQ5_FILE = File.expand_path("smashelito.mq5", __dir__)
src = File.read(MQ5_FILE)

BOUNCE_CEILING_FIELDS = %w[
  bounceMaxAllowed_today min_bounceCount
  recentBounceCountToday_Minutes recentBounceCount_max_allowed max_weekly_bounce_allowed
  physicalCeilingMaxAllowed_today proximityCeilingMaxAllowed_today
  recentCeilingCountToday_Minutes max_weekly_ceiling_allowed
].freeze

assign_re = /
  g_algos\[AlgoSlotIndexByAlgoId\(MAGIC_ALGO(\d+)\)\]\.(\w+)\s*=\s*([^;]+);
/x

params_by_algo = Hash.new { |h, k| h[k] = {} }
src.scan(assign_re) do |id, field, value|
  params_by_algo[id.to_i][field] = value.strip
end

registry = src[/int\s+g_algoRegistryIds\[\]\s*=\s*\{([^}]+)\}/m, 1]
algo_ids = registry.scan(/MAGIC_ALGO(\d+)/).flatten.map(&:to_i)

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
  return "long"  if val.include?("ALGO_SIDE_LONG")  || val == "false"
  val
end

def parse_rule_line(line, params)
  line = line.sub(%r{//.*}, "").strip
  return nil if line.empty?

  if (m = line.match(/\AAlgoRuleAdd_CleanStreakLong\([^,]+,\s*([^,]+),\s*([^)]+)\)/))
    "CleanStreakLong(min_streak=#{resolve(m[1], params)}, min_anchorAbove=#{resolve(m[2], params)})"
  elsif (m = line.match(/\AAlgoRuleAdd_CleanStreakShort\([^,]+,\s*([^,]+),\s*([^)]+)\)/))
    "CleanStreakShort(min_streak=#{resolve(m[1], params)}, min_anchorBelow=#{resolve(m[2], params)})"
  elsif (m = line.match(/\AAlgoRuleAdd_BounceCountTooHigh\([^,]+,\s*([^)]+)\)/))
    "dailyBounceCountTooHigh(max=#{resolve(m[1], params)})"
  elsif (m = line.match(/\AAlgoRuleAdd_CeilingCountTooHigh\([^,]+,\s*([^,]+),\s*([^)]+)\)/))
    "CeilingCountTooHigh(max=#{resolve(m[1], params)}, tag=#{resolve(m[2], params)})"
  elsif (m = line.match(/\AAlgoRuleAdd_CeilingProximityCandlesTooHigh\([^,]+,\s*([^,]+),\s*([^)]+)\)/))
    "CeilingProximityCandlesTooHigh(max=#{resolve(m[1], params)}, tag=#{resolve(m[2], params)})"
  elsif (m = line.match(/\AAlgoRuleAdd_LevelOnoAbsDiffTooLow\([^,]+,\s*([^)]+)\)/))
    "LevelOnoAbsDiffTooLow(min=#{resolve(m[1], params)})"
  elsif (m = line.match(/\AAlgoRuleAdd_AnchorAboveTooHigh\([^,]+,\s*([^)]+)\)/))
    "AnchorAboveTooHigh(max=#{resolve(m[1], params)})"
  elsif (m = line.match(/\AAlgoRuleChainAdd\(slotIdx,\s*(RULE_\w+)(?:,\s*([^)]+))?\)/))
  rule = m[1]
  arg = m[2] ? resolve(m[2], params) : nil
  arg ? "#{rule}(#{arg})" : rule
  end
end

rule_switch = src[/void\s+AlgoRebuildRuleChainForSlot\b.*?switch\s*\(\s*algoId\s*\)\s*\{(.*?)\n\s*default:/m, 1]
rules_by_algo = {}
rule_switch.scan(/case\s+MAGIC_ALGO(\d+):\s*(.*?)(?=case\s+MAGIC_ALGO|\z)/m) do |id, body|
  rules_by_algo[id.to_i] = body.lines.filter_map { |ln| parse_rule_line(ln, params_by_algo[id.to_i]) }
end

algo_ids.each do |id|
  p = params_by_algo[id]
  puts "=== algo#{id} ==="
  puts "direction: #{direction(p['trades_short'])}"

  bc = BOUNCE_CEILING_FIELDS.filter_map { |f| p[f] ? "#{f}=#{p[f]}" : nil }
  puts bc.empty? ? "bounce/ceiling: (none set)" : "bounce/ceiling: #{bc.join(', ')}"

  rules = rules_by_algo[id] || []
  if rules.empty?
    puts "rules: (none)"
  else
    puts "rules:"
    rules.each { |r| puts "  - #{r}" }
  end
  puts
end

longs, shorts = algo_ids.partition { |id| direction(params_by_algo[id]["trades_short"]) == "long" }
puts "longs: #{longs.join(', ')}"
puts "shorts: #{shorts.join(', ')}"
