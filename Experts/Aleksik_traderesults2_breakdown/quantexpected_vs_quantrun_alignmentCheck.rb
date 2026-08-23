#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare quant-ref algo run stats vs expected stats embedded in quantref comments.
#
# Run stats are always computed from summary_tradeResults_all_days_*.tsv (raw trade logs).
#
# Outputs (one per family):
#   quantexpected_vs_quantrun_alignmentCheck_breakdown.csv
#   quantexpected_vs_quantrun_alignmentCheck_level.csv
#   quantexpected_vs_quantrun_alignmentCheck_time.csv

require_relative 'quantexpected_vs_quantrun_alignmentCheck_common'

run_full_quant_alignment_check! if __FILE__ == $PROGRAM_NAME
