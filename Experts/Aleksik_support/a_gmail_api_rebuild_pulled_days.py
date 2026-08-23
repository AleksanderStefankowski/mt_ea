"""
Pull latest Gmail plans (step 1 must have run), parse them, and rebuild the full
Gmail pull date span:

  1. Drop every ALLRAW / zeFinal row whose start falls inside [min_start, max_end]
     from the fresh parse (wipes orphans like wrong week-end dates or wrong years)
  2. Insert freshly parsed levels for that span
  3. Run stacking / CSV write (same as step 3), sorted by start/end/tag

Rows before the Gmail pull span (earlier than pull_after_date in a_gmail_api.py)
are kept untouched.

Use a_gmail_api_run_rebuild_pulled_days.rb to run Gmail API + this script.
Git diff on levelsinfo_zeFinal.csv shows how far bad ingest reached.
"""

import json
import os
import sys

from gmail_auth_common import SCRIPT_DIR
from gmail_plan_parse_common import load_trading_dates

os.chdir(SCRIPT_DIR)
sys.path.insert(0, SCRIPT_DIR)

from a_gmail_api2step_parse_append_to_ALLRAW import normalize_level_list, parse_plan
from a_gmail_api3step_processDuplicates__saveAs_zeFinal2 import (
    build_weekly_prices_by_week,
    ensure_daily_weekdays,
    load_csv_levels,
    process_duplicates,
    remove_identical_duplicate_lines,
    sync_to_mt5_common_files,
    write_csv,
)

ALLRAW_PATH = os.path.join(SCRIPT_DIR, "a_gmail_api2step_parse_append_to_ALLRAW_output.txt")
EMAIL_PATH = os.path.join(SCRIPT_DIR, "a_gmail_api_output_overwrites_store_latest_emails.txt")
CALENDAR_PATH = os.path.join(SCRIPT_DIR, "calendar_2026_dots.csv")
ZEFINAL_PATH = os.path.join(SCRIPT_DIR, "levelsinfo_zeFinal.csv")


def range_tag_key(lev):
    return (lev["start"], lev["end"], lev["tag"])


def gmail_pull_span(levels):
    """Inclusive calendar span covered by the latest Gmail parse."""
    starts = [lev["start"] for lev in levels]
    ends = [lev["end"] for lev in levels]
    return min(starts), max(ends)


def level_in_gmail_span(lev, span_start, span_end):
    """True when this row's start date lies inside the Gmail pull span."""
    return span_start <= lev["start"] <= span_end


def dedupe_by_range_tag(levels):
    """One row per (start, end, tag); later rows win."""
    merged = {}
    for lev in levels:
        merged[range_tag_key(lev)] = lev
    return list(merged.values())


def load_allraw():
    if not os.path.exists(ALLRAW_PATH):
        return []
    with open(ALLRAW_PATH, encoding="utf-8") as f:
        try:
            return normalize_level_list(json.load(f))
        except json.JSONDecodeError:
            return []


def save_allraw(levels):
    with open(ALLRAW_PATH, "w", encoding="utf-8") as f:
        json.dump(levels, f, indent=2)


def filter_out_gmail_span(levels, span_start, span_end):
    return [
        lev for lev in levels
        if not level_in_gmail_span(lev, span_start, span_end)
    ]


def sort_levels(levels):
    return sorted(levels, key=lambda lev: (lev["start"], lev["end"], lev["tag"]))


def parse_gmail_output():
    trading = load_trading_dates(CALENDAR_PATH)
    with open(EMAIL_PATH, encoding="utf-8") as f:
        text = f.read()
    return dedupe_by_range_tag(parse_plan(text, trading))


def print_pulled_summary(fresh_levels, span_start, span_end):
    ranges = {(lev["start"], lev["end"]) for lev in fresh_levels}
    print(f"Gmail pull span: {span_start} .. {span_end}")
    print(f"Distinct (start, end) in fresh parse: {len(ranges)}")


def main():
    fresh_levels = parse_gmail_output()
    if not fresh_levels:
        print("No levels parsed from Gmail output — nothing to rebuild.")
        return 1

    span_start, span_end = gmail_pull_span(fresh_levels)
    print_pulled_summary(fresh_levels, span_start, span_end)
    print(f"Fresh parsed level rows: {len(fresh_levels)}")

    allraw_before = load_allraw()
    allraw_kept = filter_out_gmail_span(allraw_before, span_start, span_end)
    allraw_removed = len(allraw_before) - len(allraw_kept)
    allraw_new = sort_levels(allraw_kept + fresh_levels)
    save_allraw(allraw_new)
    print(
        f"ALLRAW: removed {allraw_removed} rows inside Gmail span, "
        f"added {len(fresh_levels)}, total {len(allraw_new)}"
    )

    existing_levels = []
    if os.path.exists(ZEFINAL_PATH):
        existing_levels = load_csv_levels(ZEFINAL_PATH)
    zefinal_kept = filter_out_gmail_span(existing_levels, span_start, span_end)
    zefinal_removed = len(existing_levels) - len(zefinal_kept)
    levels = sort_levels(zefinal_kept + fresh_levels)
    print(
        f"zeFinal: removed {zefinal_removed} rows inside Gmail span "
        f"({span_start}..{span_end}), kept {len(zefinal_kept)} older rows, "
        f"added {len(fresh_levels)} rebuilt rows"
    )

    ensure_daily_weekdays(levels)
    week_prices = build_weekly_prices_by_week(levels)
    process_duplicates(levels, week_prices)
    written, skipped_daily_stacked = write_csv(levels, ZEFINAL_PATH)
    remove_identical_duplicate_lines(ZEFINAL_PATH)

    print(f"Wrote {ZEFINAL_PATH} ({written} rows, skipped {skipped_daily_stacked} daily+stacked)")
    sync_to_mt5_common_files(ZEFINAL_PATH)
    print()
    print("Done. Run: git diff levelsinfo_zeFinal.csv")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
