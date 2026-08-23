import json
import os
import re
from datetime import datetime

from gmail_plan_parse_common import (
    load_trading_dates,
    parse_title_range,
    recognize_plan_body,
    validate_plan_recognition,
)

print_levels_to_console = False


def normalize_level_record(lev):
    tag = lev.get("tag", "")
    if tag == "weeklySmash":
        lev["tag"] = "weeklyPivot"
    elif tag == "dailySmash":
        lev["tag"] = "dailyPivot"

    cats = lev.get("categories", [])
    lev["categories"] = [
        "pivot" if c == "smash" else c.replace("smash", "pivot") if "smash" in c else c
        for c in cats
    ]
    return lev


def normalize_level_list(levels):
    for lev in levels:
        normalize_level_record(lev)
    return levels


def parse_plan(text, trading):
    results = []

    sections = re.split(r"\n(?=[A-Z].*?\|\s+[A-Za-z]+\s+\d)", text.strip())

    for section in sections:
        lines = [line.strip() for line in section.splitlines() if line.strip()]
        if not lines:
            continue

        title = lines[0]

        if "Marker not found" in title or not re.search(r"\b(Daily|Weekly)\s+Plan\b", title, re.I):
            continue

        try:
            start_date, end_date = parse_title_range(title, trading)
        except (ValueError, IndexError) as exc:
            print(f"SKIP parse: {title!r} — {exc}")
            continue

        recognition = recognize_plan_body(title, lines[1:])
        validate_plan_recognition(recognition, start_date, end_date)

        category = recognition["category"]
        pivot = recognition["pivot"]
        ups = recognition["ups"]
        downs = recognition["downs"]

        if pivot is not None:
            if category == "weekly":
                results.append(
                    normalize_level_record(
                        {
                            "start": start_date,
                            "end": end_date,
                            "levelPrice": pivot,
                            "categories": ["weekly", "pivot"],
                            "tag": "weeklyPivot",
                        }
                    )
                )
            else:
                dt = datetime.strptime(start_date, "%Y.%m.%d")
                weekday = dt.strftime("%A").lower()

                results.append(
                    normalize_level_record(
                        {
                            "start": start_date,
                            "end": end_date,
                            "levelPrice": pivot,
                            "categories": ["daily", weekday, "pivot"],
                            "tag": "dailyPivot",
                        }
                    )
                )

        for i, level in enumerate(sorted(ups), start=1):
            results.append(
                {
                    "start": start_date,
                    "end": end_date,
                    "levelPrice": level,
                    "categories": [category],
                    "tag": f"{category}Up{i}",
                }
            )

        for i, level in enumerate(sorted(downs, reverse=True), start=1):
            results.append(
                {
                    "start": start_date,
                    "end": end_date,
                    "levelPrice": level,
                    "categories": [category],
                    "tag": f"{category}Down{i}",
                }
            )

    return results


if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))

    calendar_path = os.path.join(script_dir, "calendar_2026_dots.csv")
    email_path = os.path.join(script_dir, "a_gmail_api_output_overwrites_store_latest_emails.txt")

    trading = load_trading_dates(calendar_path)

    with open(email_path, encoding="utf-8") as f:
        text = f.read()

    data = parse_plan(text, trading)

    out_path = os.path.join(script_dir, "a_gmail_api2step_parse_append_to_ALLRAW_output.txt")

    existing = []
    if os.path.exists(out_path):
        with open(out_path, "r", encoding="utf-8") as f:
            try:
                existing = normalize_level_list(json.load(f))
            except json.JSONDecodeError:
                existing = []

    combined = existing + data

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(combined, f, indent=2)

    if print_levels_to_console:
        for row in data:
            print(row)
