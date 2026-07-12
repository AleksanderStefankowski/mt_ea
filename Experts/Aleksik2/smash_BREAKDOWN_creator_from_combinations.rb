
desired_min_breakdown_sequence_len = [4, 3, 6, 8]
desired_max_breakdown_sequence_len = [9, 14, 21]

desired_bd_start_min_breakdown_percent = [0.20, 0.30, 0.40, 0.60, 0.80]
desired_min_breakdown_total_percent = [0.40, 0.60, 0.80, 1.00, 2.00]

desired_after_bd_need_x_15greenc = [1, 2, 3, 4, 5]
desired_entry_max_minutes_after_bdend = [75, 50, 90]

desired_entryrange_range_percentspot = [20, 33, 50, 66, 75]
desired_secret_tp_range_percent = [0, 20, 33, 50, 66, 75, 100] # 0 is disabled secret tp

desired_tp_notsecret_range_percent = [150]

desired_closetrade_after_x_minutes_from_breakdown = [0, 15, 30, 45, 60, 75, 90] #  0 is disabled

desired_breakdowntypes = [
    "CLOSES",
    "OHLC_AVG",
    "LOW",
    "OC_MID",
    "HL_MID",
]

desired_max_open_positions = [5, 10, 2]

# write a script that prints how many possible combinations count are there, probablt a lot