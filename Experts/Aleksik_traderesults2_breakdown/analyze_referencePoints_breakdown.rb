#!/usr/bin/env ruby
# frozen_string_literal: true

# Reference-point grouping for breakdown algos.
# Reads summary_tradeResults_all_days_breakdown.tsv.

require_relative 'analyze_algos_performance_common'
require_relative 'analyze_referencePoints_common'

self.traderate_account_for_banned_days = false

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))

# Skip ref groups whose share of that algo's trades is below this % (0–100).
MINIMUM_RATECUT_PERCENT = 70

# Skip grouped rows whose timeVSprofit is not above that algo's ungrouped row.
GROUP_TIMEVSPROFIT_NEEDS_TO_BE_BETTER = true

AnalyzeAlgosReferencePointsCommon.run(
  family_label: 'breakdown',
  pattern: 'BREAKDOWN',
  input_path: File.join(SCRIPT_DIR, 'summary_tradeResults_all_days_breakdown.tsv'),
  output_path: File.join(SCRIPT_DIR, 'analyze_referencePoints_breakdown_output.csv'),
  minimum_ratecut_percent: MINIMUM_RATECUT_PERCENT,
  group_timevsprofit_needs_to_be_better: GROUP_TIMEVSPROFIT_NEEDS_TO_BE_BETTER
)
