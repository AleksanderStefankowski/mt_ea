#!/usr/bin/env ruby
# frozen_string_literal: true

# Console-only alignment summary for a fixed list of quant algo IDs.
# No CSV output. No ref-pattern analysis section.

require_relative 'quantexpected_vs_quantrun_alignmentCheck_common'

EXACT_ALGO_IDS = <<~IDS
20001013
20001263
20001053
20001104
20001031
30000064
30000061
30000071
30000063
30000062
10000014
10000016
10000015
10000011
10000019
20000763
20000761
20001306
20001155
20001144
30000066
30000057
30000068
30000044
30000043
10000010
10000009
10000017
10000018
10000013
IDS

def parse_exact_algo_ids(text)
  text.lines.map(&:strip).grep(/^\d+$/)
end

if __FILE__ == $PROGRAM_NAME
  run_exact_algo_ids_check!(parse_exact_algo_ids(EXACT_ALGO_IDS))
end
