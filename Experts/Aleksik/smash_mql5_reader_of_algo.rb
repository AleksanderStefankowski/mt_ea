#!/usr/bin/env ruby
# Lists each wired algo: id, direction, bounce/ceiling/contact/ONO params, ruleset.

require_relative "smash_mql5_algo_reader_lib"

MQ5_FILE = File.expand_path("aleksik.mq5", __dir__)
src = SmashMql5AlgoReader.load_mq5(MQ5_FILE)

params_by_algo = SmashMql5AlgoReader.params_by_algo_from_src(src)
tune_by_algo = SmashMql5AlgoReader.tune_by_algo_from_src(src)
algo_ids = SmashMql5AlgoReader.registry_algo_ids(src)
rules_by_algo = SmashMql5AlgoReader.rules_by_algo_from_src(src, params_by_algo)

algo_ids.each do |id|
  p = params_by_algo[id]
  t = tune_by_algo[id]
  puts "--- algo#{id} ---"
  puts "direction: #{SmashMql5AlgoReader.direction(p['trades_short'])}"
  puts "enabled: #{p['enabled'] || '?'}"
  puts "levels: weekly=#{p['tradesWeeklyLevels'] || 'shared'}, daily=#{p['tradesDailyLevels'] || 'shared'}, rthoTertiary=#{p['tradesTertiaryTodayRTHOLevel'] || 'false'}"

  gap = SmashMql5AlgoReader.format_fields(p, SmashMql5AlgoReader::GAP_DAY_FIELDS)
  puts gap.empty? ? "gap day: (none set)" : "gap day: #{gap}"

  bc = SmashMql5AlgoReader.format_fields(p, SmashMql5AlgoReader::BOUNCE_CEILING_FIELDS)
  puts bc.empty? ? "bounce/ceiling: (none set)" : "bounce/ceiling: #{bc}"

  contact = SmashMql5AlgoReader.format_fields(p, SmashMql5AlgoReader::CONTACT_ONO_LIMIT_FIELDS)
  puts contact.empty? ? "contact/ONO/limits: (none set)" : "contact/ONO/limits: #{contact}"

  place = SmashMql5AlgoReader.format_fields(p, SmashMql5AlgoReader::PLACEMENT_FIELDS)
  puts place.empty? ? "placement: (none set)" : "placement: #{place}"

  daylim = SmashMql5AlgoReader.format_fields(t, SmashMql5AlgoReader::TUNE_DAY_LIMIT_FIELDS)
  puts daylim.empty? ? "day stops: (none set)" : "day stops: #{daylim}"

  rules = rules_by_algo[id] || []
  if rules.empty?
    puts "rules: (none)"
  else
    puts "rules:"
    rules.each { |r| puts "  - #{r}" }
  end
  puts
end

longs, shorts = algo_ids.partition { |id| SmashMql5AlgoReader.direction(params_by_algo[id]["trades_short"]) == "long" }
longs_enabled, longs_disabled = longs.partition { |id| params_by_algo[id]["enabled"] == "true" }
shorts_enabled, shorts_disabled = shorts.partition { |id| params_by_algo[id]["enabled"] == "true" }
all_enabled = algo_ids.select { |id| params_by_algo[id]["enabled"] == "true" }
all_disabled = algo_ids.select { |id| params_by_algo[id]["enabled"] != "true" }
puts "longs (enabled): #{longs_enabled.join(', ')}"
puts "longs (disabled): #{longs_disabled.join(', ')}"
puts "shorts (enabled): #{shorts_enabled.join(', ')}"
puts "shorts (disabled): #{shorts_disabled.join(', ')}"
puts "all (enabled): #{all_enabled.join(', ')}"
puts "all (disabled): #{all_disabled.join(', ')}"
