wrwite a script here that reaads the summary_tradeResults_all_days_breakdown



aggregates each algo trades via the algoID column

then calculates stats for it
algoID
first trade date, last trade date,
trade count
tradedDaysCount



max_notrades_streak

avg_notrades_streak

avgMFE , avgMAE, avgDurationHours (we have one of the columns is about duration in hours), 
avgFillDelay (it's about sent time vs start time)
avg_profit_custom_with_roll

and after the simple stats we do cooler metrics columns:

  timeVSprofit, so if 2 trades have the smae profit, but one hass only 50% duration, it means it has double the effectiveness. the bigger number, probably the shorter trade duration

  trade rate: check first and last date in the file, regardless of algoID (no aggregation, all algos exist int he same dayspan range) trade, to calculate the total day span, 
and use that to calculate the trade rate of each algo (where a trade rate 0.80 means 80% of tradable days traded, means trade was open. be aware some trades are intraday, 

some span multiday, so just care about the trade start time) 
weekly_traderate

Avg Open Exposure: on any day that a trade was opened on that day, what was the peak trade open count, and then do the avg open trade count across all days that had a trade of that algo
Peak Open Exposure: the highest open count of this algo


save output to csv