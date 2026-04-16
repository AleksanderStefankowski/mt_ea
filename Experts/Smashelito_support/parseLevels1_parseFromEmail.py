import csv
import json
import os
import re
from calendar import month_name
from datetime import datetime, timedelta


def month_to_number(month_str):
    for i in range(1, 13):
        if month_name[i].lower() == month_str.lower():
            return i
    raise ValueError(f"Invalid month: {month_str}")


def load_trading_dates(calendar_path):
    """Dates from CSV where day is not Saturday/Sunday (YYYY.MM.DD strings)."""
    trading = set()
    with open(calendar_path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["dayofweek"] not in ("Saturday", "Sunday"):
                trading.add(row["date"])
    return trading


def parse_first_date_in_title(date_part):
    """
    First calendar date in a weekly title string, e.g.
    'January 5-9, 2026' -> 2026.01.05
    'March 30 - April 3, 2026' -> 2026.03.30
    """
    m_year = re.search(r",\s*(\d{4})\s*$", date_part)
    if not m_year:
        raise ValueError(f"No year in date part: {date_part!r}")
    year = int(m_year.group(1))
    m_first = re.match(r"^\s*([A-Za-z]+)\s+(\d+)", date_part.strip())
    if not m_first:
        raise ValueError(f"No leading month/day in date part: {date_part!r}")
    mo = month_to_number(m_first.group(1))
    day = int(m_first.group(2))
    return f"{year:04d}.{mo:02d}.{day:02d}"


def week_trading_span(anchor_iso, trading):
    """
    All trading dates in the same ISO week as anchor; return (first, last) YYYY.MM.DD.
    """
    y, m, d = (int(x) for x in anchor_iso.split("."))
    dt = datetime(y, m, d)
    iso_y, iso_w, _ = dt.isocalendar()
    in_week = []
    for delta in range(-7, 10):
        t = dt + timedelta(days=delta)
        if t.isocalendar()[:2] != (iso_y, iso_w):
            continue
        key = f"{t.year:04d}.{t.month:02d}.{t.day:02d}"
        if key in trading:
            in_week.append(key)
    if not in_week:
        raise ValueError(f"No trading days in calendar for ISO week of {anchor_iso}")
    in_week.sort()
    return in_week[0], in_week[-1]


def parse_daily_date(date_part):
    """Single day: 'January 5, 2026' -> (iso, iso)."""
    single = re.match(r"^([A-Za-z]+)\s+(\d+),\s*(\d{4})$", date_part.strip())
    if not single:
        raise ValueError(f"Cannot parse daily date part: {date_part!r}")
    month_str, day, year_s = single.groups()
    year = int(year_s)
    mo = month_to_number(month_str)
    iso = f"{year:04d}.{mo:02d}.{int(day):02d}"
    return iso, iso


def parse_title_range(title, trading):
    date_part = title.split("|")[1].strip()
    if "Weekly" in title:
        anchor = parse_first_date_in_title(date_part)
        return week_trading_span(anchor, trading)
    return parse_daily_date(date_part)


def expand_range(token):
    """
    Expands:
        7031-43   -> [7031, 7043]
        7031-7043 -> [7031, 7043]
        7045*     -> [7045]
    """
    token = token.replace("*", "")

    if "-" not in token:
        return [int(token)]

    left, right = token.split("-")

    # Handle short range like 7031-43
    if len(right) < len(left):
        right = left[:len(left) - len(right)] + right

    return [int(left), int(right)]


def parse_plan(text, trading):
    results = []

    sections = re.split(r"\n(?=[A-Z].*?\|\s+[A-Za-z]+\s+\d)", text.strip())

    for section in sections:
        lines = [l.strip() for l in section.splitlines() if l.strip()]
        if not lines:
            continue

        title = lines[0]

        category = "weekly" if "Weekly" in title else "daily"
        start_date, end_date = parse_title_range(title, trading)

        smash = None
        ups = []
        downs = []

        for line in lines[1:]:

            smash_match = re.search(r"(above|below)\s+(\d+)", line)
            if smash_match:
                smash = int(smash_match.group(2))

            target_match = re.search(r"would target (.+)", line)
            if target_match:
                raw_targets = target_match.group(1)
                tokens = re.findall(r"\d+\*?(?:-\d+\*?)?", raw_targets)

                numbers = []
                for token in tokens:
                    numbers.extend(expand_range(token))

                if "above" in line:
                    ups.extend(numbers)
                elif "below" in line:
                    downs.extend(numbers)

        # --- Smash level ---
        if smash is not None:
            if category == "weekly":
                results.append({
                    "start": start_date,
                    "end": end_date,
                    "levelPrice": smash,
                    "categories": ["weekly", "smash"],
                    "tag": "weeklySmash",
                })
            else:
                dt = datetime.strptime(start_date, "%Y.%m.%d")
                weekday = dt.strftime("%A").lower()

                results.append({
                    "start": start_date,
                    "end": end_date,
                    "levelPrice": smash,
                    "categories": ["daily", weekday, "smash"],
                    "tag": "dailySmash",
                })

        # --- Ups (sorted ascending) ---
        for i, level in enumerate(sorted(ups), start=1):
            tag = f"{category}Up{i}"
            results.append({
                "start": start_date,
                "end": end_date,
                "levelPrice": level,
                "categories": [category],
                "tag": tag,
            })

        # --- Downs (sorted descending) ---
        for i, level in enumerate(sorted(downs, reverse=True), start=1):
            tag = f"{category}Down{i}"
            results.append({
                "start": start_date,
                "end": end_date,
                "levelPrice": level,
                "categories": [category],
                "tag": tag,
            })

    return results


if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    calendar_path = os.path.join(script_dir, "calendar_2026_dots.csv")
    email_path = os.path.join(script_dir, "levelsinfo_emailraw.txt")

    trading = load_trading_dates(calendar_path)
    with open(email_path, encoding="utf-8") as f:
        text = f.read()
    data = parse_plan(text, trading)
    out_path = os.path.join(script_dir, "levelsinfo_raw.txt")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    for row in data:
        print(row)
