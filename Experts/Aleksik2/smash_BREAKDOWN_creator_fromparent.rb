parent_algo = 20000000

desired_min_breakdown_sequence_len = [4]
desired_max_breakdown_sequence_len = [9]

desired_bd_start_min_breakdown_percent = [0.20]
desired_min_breakdown_total_percent = [0.40]

desired_after_bd_need_x_15greenc = [1]
desired_entry_max_minutes_after_bdend = [75]

desired_entryrange_range_percentspot = [20, 33, 50, 66, 75]
desired_secret_tp_range_percent = [0, 20, 33, 50, 66, 75] # 0 is disabled secret tp

desired_tp_notsecret_range_percent = [100]

desired_closetrade_after_x_minutes_from_breakdown = [0, 15, 30, 45, 60, 75, 90] #  0 is disabled

desired_breakdowntypes = [
    "CLOSES",
    "OHLC_AVG",
    "LOW",
    "OC_MID",
    "HL_MID",
]

desired_max_open_positions = [5]