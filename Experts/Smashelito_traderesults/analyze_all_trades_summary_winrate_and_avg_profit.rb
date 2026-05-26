#!/usr/bin/env ruby

require 'csv'
require 'set'

# =========================================================
# CONFIG
# =========================================================

FILE_PATH = 'summary_tradeResults_all_days.tsv'

this script should read the file, and print this to console:
winrate across all traades
avg profit of winning trades
avg profit of losing trades

also group by magic prefix (2 first digits).
and print per prefix:
winrate across all traades
avg profit of winning trades
avg profit of losing trades