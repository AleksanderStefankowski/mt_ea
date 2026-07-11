#!/usr/bin/env ruby
# frozen_string_literal: true

# inputs (O H L C)
# 02.07.2026 16:30 expect bd cont on green next candle:
# prev_candle_ohlc = [7559.9, 7574.2, 7543.6, 7548.7]
# next_candle_ohlc = [7549.4, 7557.7, 7540.0, 7556.9]
# 0 closes     prev=    7548.7  next=    7556.9  diff=      +8.2  => NO_BREAKDOWN
# 1 ohlc_avg   prev=    7556.6  next=    7551.0  diff=      -5.6  => BD_CONTINUATION
# 2 low        prev=    7543.6  next=    7540.0  diff=      -3.6  => BD_CONTINUATION
# 3 oc_mid     prev=    7554.3  next=    7553.2  diff=      -1.1  => BD_CONTINUATION
# 4 hl_mid     prev=    7558.9  next=    7548.8  diff=     -10.0  => BD_CONTINUATION
# 02.07.2026 16:15 expect bd cont on green candle??
# prev_candle_ohlc = [7540.9, 7544.2, 7523.9, 7529.0]
# next_candle_ohlc = [7529.0, 7547.2, 7528.7, 7533.5]
# 0 closes     prev=    7529.0  next=    7533.5  diff=      +4.5  => NO_BREAKDOWN
# 1 ohlc_avg   prev=    7534.5  next=    7534.6  diff=      +0.1  => NO_BREAKDOWN
# 2 low        prev=    7523.9  next=    7528.7  diff=      +4.8  => NO_BREAKDOWN
# 3 oc_mid     prev=    7535.0  next=    7531.2  diff=      -3.7  => BD_CONTINUATION
# 4 hl_mid     prev=    7534.0  next=    7538.0  diff=      +3.9  => NO_BREAKDOWN
# 02.07.2026 19:45 expect bd finished:
# prev_candle_ohlc = [7490.2, 7490.7, 7479.2, 7481.6]
# next_candle_ohlc = [7482.4, 7508.4, 7479.7, 7501.7]
# 0 closes     prev=    7481.6  next=    7501.7  diff=     +20.1  => NO_BREAKDOWN
# 1 ohlc_avg   prev=    7485.4  next=    7493.0  diff=      +7.6  => NO_BREAKDOWN
# 2 low        prev=    7479.2  next=    7479.7  diff=      +0.5  => NO_BREAKDOWN
# 3 oc_mid     prev=    7485.9  next=    7492.0  diff=      +6.1  => NO_BREAKDOWN
# 4 hl_mid     prev=    7485.0  next=    7494.0  diff=      +9.1  => NO_BREAKDOWN

# 07.07.2026 16:30 expect bd finished:
prev_candle_ohlc = [7544.2, 7547.4, 7529.2, 7534.4]
next_candle_ohlc = [7534.7, 7546.2, 7533.7, 7541.9]
# 0 closes     prev=    7534.4  next=    7541.9  diff=      +7.5  => NO_BREAKDOWN
# 1 ohlc_avg   prev=    7538.8  next=    7539.1  diff=      +0.3  => NO_BREAKDOWN
# 2 low        prev=    7529.2  next=    7533.7  diff=      +4.5  => NO_BREAKDOWN
# 3 oc_mid     prev=    7539.3  next=    7538.3  diff=      -1.0  => BD_CONTINUATION
# 4 hl_mid     prev=    7538.3  next=    7540.0  diff=      +1.7  => NO_BREAKDOWN


# prev_candle_ohlc = [7, 7, 7, 7]
# next_candle_ohlc = [7, 7, 7, 7]

# Mirrors ENUM_BREAKDOWN_STREAK_CONTINUATION / BreakdownStreakBarMetric in aleksik.mq5.
# Continuation = next bar metric is strictly lower than previous bar metric.

BREAKDOWN_STREAK_CONTINUATION = {
  closes: 0,    # each next M15 close < previous close
  ohlc_avg: 1,  # (O+H+L+C)/4 strictly lower
  low: 2,       # low strictly lower
  oc_mid: 3,    # (open+close)/2 strictly lower
  hl_mid: 4     # (high+low)/2 strictly lower
}.freeze

Candle = Struct.new(:open, :high, :low, :close, keyword_init: true) do
  def self.parse(ohlc)
    o, h, l, c = ohlc.map { |v| Float(v) }
    new(open: o, high: h, low: l, close: c)
  end

  def metric(mode)
    case mode
    when :ohlc_avg then (open + high + low + close) / 4.0
    when :low      then low
    when :oc_mid   then (open + close) / 2.0
    when :hl_mid   then (high + low) / 2.0
    else                close # :closes
    end
  end
end

def breakdown_continuation?(prev_candle, next_candle, mode)
  prev_metric = prev_candle.metric(mode)
  next_metric = next_candle.metric(mode)
  next_metric < prev_metric
end

def format_candle(candle)
  format('O=%.1f H=%.1f L=%.1f C=%.1f', candle.open, candle.high, candle.low, candle.close)
end

def check_all_modes(prev_candle, next_candle)
  BREAKDOWN_STREAK_CONTINUATION.each do |mode, enum_id|
    prev_metric = prev_candle.metric(mode)
    next_metric = next_candle.metric(mode)
    diff = next_metric - prev_metric
    continues = next_metric < prev_metric
    puts format(
      '%d %-9s  prev=%10.1f  next=%10.1f  diff=%+10.1f  => %s',
      enum_id,
      mode.to_s,
      prev_metric,
      next_metric,
      diff,
      continues ? 'BD_CONTINUATION' : 'NO_BREAKDOWN'
    )
  end
end

if __FILE__ == $PROGRAM_NAME
  prev_candle = Candle.parse(prev_candle_ohlc)
  next_candle = Candle.parse(next_candle_ohlc)

  puts 'Breakdown streak continuation check'
  puts "Previous: #{format_candle(prev_candle)}"
  puts "Next:     #{format_candle(next_candle)}"
  puts
  check_all_modes(prev_candle, next_candle)
end
