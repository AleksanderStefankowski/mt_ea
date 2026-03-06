"""
Read levelsinfo_raw.txt (JSON from parseLevels1), add category "stacked"
to daily levels whose levelPrice matches any weekly level in the same week.
Write result to levelsinfo_zeFinal.csv in the same directory.
"""

import os
import json
import csv
from datetime import datetime


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


def date_in_range(date_str, start_str, end_str):
    """True if date_str is >= start_str and <= end_str (dates YYYY.MM.DD)."""
    return start_str <= date_str <= end_str


def process_duplicates(levels, week_prices):
    """Mutate levels: add 'dailyIsWeekly' to categories for daily levels
    that have the same levelPrice as any weekly level in the same week."""
    for lev in levels:
        if "daily" not in lev.get("categories", []):
            continue
        daily_start = lev["start"]
        price = lev["levelPrice"]
        for (week_start, week_end), prices in week_prices.items():
            if date_in_range(daily_start, week_start, week_end) and price in prices:
                if "stacked" not in lev["categories"]:
                    lev["categories"].append("stacked")
                break


def write_csv(levels, out_path):
    """Write levels to CSV: start, end, levelPrice, categories (underscore-joined), tag."""
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["start", "end", "levelPrice", "categories", "tag"])
        for lev in levels:
            categories_str = "_".join(lev["categories"])
            w.writerow([
                lev["start"],
                lev["end"],
                lev["levelPrice"],
                categories_str,
                lev["tag"],
            ])


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    levels = load_raw(script_dir)
    week_prices = build_weekly_prices_by_week(levels)
    process_duplicates(levels, week_prices)
    out_path = os.path.join(script_dir, "levelsinfo_zeFinal.csv")
    write_csv(levels, out_path)
    print("Wrote", out_path, "with", len(levels), "levels.")


if __name__ == "__main__":
    main()
