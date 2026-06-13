#!/usr/bin/env ruby
# Exports wired algos to CSV: id, direction, enabled, level scopes, gate params, ruleset.

require "csv"
require_relative "smash_mql5_algo_reader_lib"

MQ5_FILE = File.expand_path("aleksik.mq5", __dir__)
OUT_CSV  = File.expand_path("smash_mql5_reader_of_algo_csv_output.csv", __dir__)
src = SmashMql5AlgoReader.load_mq5(MQ5_FILE)

params_by_algo = SmashMql5AlgoReader.params_by_algo_from_src(src)
tune_by_algo = SmashMql5AlgoReader.tune_by_algo_from_src(src)
algo_ids = SmashMql5AlgoReader.registry_algo_ids(src)
rules_by_algo = SmashMql5AlgoReader.rules_by_algo_from_src(src, params_by_algo)

shared_weekly = src[/g_algoShared\.tradesWeeklyLevels\s*=\s*(\w+)/, 1]
shared_daily  = src[/g_algoShared\.tradesDailyLevels\s*=\s*(\w+)/, 1]

def rules_cell(rules)
  return "" if rules.empty?
  rules.join(" | ")
end

CSV.open(OUT_CSV, "w") do |csv|
  csv << [
    "algo id",
    "direction",
    "enabled?",
    "trades weekly?",
    "trades daily?",
    "earlier_week_contact_max",
    "contact_today_max",
    "ono_above_min",
    "ono_below_min",
    "trades_per_level_max",
    "trades_per_day_total_stop",
    "bounce_ceiling_params",
    "placement_params",
    "rules"
  ]

  algo_ids.each do |id|
    p = params_by_algo[id]
    t = tune_by_algo[id]
    weekly = p["tradesWeeklyLevels"] || shared_weekly
    daily  = p["tradesDailyLevels"]  || shared_daily
    rules  = rules_by_algo[id] || []

    csv << [
      id,
      SmashMql5AlgoReader.direction(p["trades_short"]),
      SmashMql5AlgoReader.bool_label(p["enabled"]),
      SmashMql5AlgoReader.bool_label(weekly),
      SmashMql5AlgoReader.bool_label(daily),
      p["max_daystart_earlierWeek_contactAndProx_allowed"] || "",
      p["max_intraday_contactAndProx_today_allowed"] || "",
      p["min_onoAboveLevel"] || "",
      p["min_onoBelowLevel"] || "",
      p["max_allowed_trades_perLevel_perDay_forThisAlgo"] || "",
      t["stop_trading_today_if_thisAlgo_total_trades_count"] || "",
      SmashMql5AlgoReader.format_fields(p, SmashMql5AlgoReader::BOUNCE_CEILING_FIELDS),
      SmashMql5AlgoReader.format_fields(p, SmashMql5AlgoReader::PLACEMENT_FIELDS),
      rules_cell(rules)
    ]
  end
end

puts OUT_CSV
