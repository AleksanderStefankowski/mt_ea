"""
Read levelsinfo_raw.txt (JSON from parseLevels1), add category "stacked"
to daily levels whose levelPrice matches any weekly level in the same week.
Add weekday to every daily level's categories (same as daily smash).
Extend weekly levels' categories with "stacked" and weekdays when stacked with daily(s).
Write result to levelsinfo_zeFinal.csv, skipping levels that have both daily and stacked.
"""

import os
import json
import csv
from datetime import datetime

WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def load_raw(script_dir):
    path = os.path.join(script_dir, "levelsinfo_raw.txt")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def build_weekly_prices_by_week(levels):
    """Return dict: (start, end) -> set of levelPrices for that week."""
    week_prices = {}
    for lev in levels:
        if "weekly" not in lev.get("categories", []):
            continue
        key = (lev["start"], lev["end"])
        week_prices.setdefault(key, set()).add(lev["levelPrice"])
    return week_prices


def weekday_from_date(date_str):
    """Return weekday string from YYYY.MM.DD (e.g. 'monday')."""
    dt = datetime.strptime(date_str, "%Y.%m.%d")
    return dt.strftime("%A").lower()


def ensure_daily_weekdays(levels):
    """Ensure every daily level has its weekday in categories (same as daily smash)."""
    for lev in levels:
        cats = lev.get("categories", [])
        if "daily" not in cats:
            continue
        has_weekday = any(d in cats for d in WEEKDAYS)
        if not has_weekday:
            wd = weekday_from_date(lev["start"])
            i = cats.index("daily") + 1
            cats.insert(i, wd)


def date_in_range(date_str, start_str, end_str):
    """True if date_str is >= start_str and <= end_str (dates YYYY.MM.DD)."""
    return start_str <= date_str <= end_str


def process_duplicates(levels, week_prices):
    """Mark daily levels as stacked when price matches weekly in same week; record weekdays
    per (week, price). Then extend weekly levels' categories with stacked + weekdays."""
    # (week_start, week_end, price) -> set of weekdays of daily levels that stack
    stacked_weekdays = {}
    for lev in levels:
        if "daily" not in lev.get("categories", []):
            continue
        daily_start = lev["start"]
        price = lev["levelPrice"]
        wd = weekday_from_date(daily_start)
        for (week_start, week_end), prices in week_prices.items():
            if date_in_range(daily_start, week_start, week_end) and price in prices:
                if "stacked" not in lev["categories"]:
                    lev["categories"].append("stacked")
                key = (week_start, week_end, price)
                stacked_weekdays.setdefault(key, set()).add(wd)
                break
    # Extend weekly levels that are stacked with daily(s)
    for lev in levels:
        if "weekly" not in lev.get("categories", []):
            continue
        key = (lev["start"], lev["end"], lev["levelPrice"])
        days = stacked_weekdays.get(key)
        if not days:
            continue
        if "stacked" not in lev["categories"]:
            lev["categories"].append("stacked")
        for wd in sorted(days):
            if wd not in lev["categories"]:
                lev["categories"].append(wd)


def write_csv(levels, out_path):
    """Write levels to CSV: start, end, levelPrice, categories (underscore-joined), tag.
    Skip any level whose categories string contains both 'daily' and 'stacked'.
    Returns (rows_written, rows_skipped_daily_stacked)."""
    written = 0
    skipped = 0
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["start", "end", "levelPrice", "categories", "tag"])
        for lev in levels:
            categories_str = "_".join(lev["categories"])
            if "daily" in categories_str and "stacked" in categories_str:
                skipped += 1
                continue
            w.writerow([
                lev["start"],
                lev["end"],
                lev["levelPrice"],
                categories_str,
                lev["tag"],
            ])
            written += 1
    return written, skipped


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    levels = load_raw(script_dir)
    ensure_daily_weekdays(levels)
    week_prices = build_weekly_prices_by_week(levels)
    process_duplicates(levels, week_prices)
    out_path = os.path.join(script_dir, "levelsinfo_zeFinal.csv")
    written, skipped_daily_stacked = write_csv(levels, out_path)
    cats_strs = ["_".join(lev["categories"]) for lev in levels]
    n_daily_stacked = sum(1 for s in cats_strs if "daily" in s and "stacked" in s)
    n_weekly_stacked = sum(1 for s in cats_strs if "weekly" in s and "stacked" in s)
    print("Wrote", out_path)
    print("Total levels:", len(levels))
    print("Daily levels containing 'stacked':", n_daily_stacked)
    print("Weekly levels containing 'stacked':", n_weekly_stacked)
    print("Levels not written (daily and stacked):", skipped_daily_stacked)


if __name__ == "__main__":
    main()
