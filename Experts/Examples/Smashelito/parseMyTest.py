text = '''	
ES Weekly Plan | February 16-20, 2026
Break and hold above 6890 would target 6960 / 7010 / 7045* / 7092 / 7145

Holding below 6890 would target 6805 / 6705 / 6670* / 6592


Daily Plan | February 18, 2026
Break and hold above 6867 would target 6890 / 6927

Holding below 6867 would target 6842 / 6805 / 6780

Daily Plan | February 19, 2026

Break and hold above 6906 would target 6927 / 6960

Holding below 6906 would target 6875 / 6842

Daily Plan | February 20, 2026

Holding above 6860 would target 6890 / 6906 / 6927

Break and hold below 6860 would target 6842 / 6805

ES Weekly Plan | February 23-27, 2026
Break and hold above 6960 would target 7031-43 / 7080 / 7110* / 7145 / 7200

Holding below 6960 would target 6890 / 6805 / 6775* / 6705 / 6670

Daily Plan | February 23, 2026

Holding above 6910 would target 6927 / 6960 / 6998

Break and hold below 6910 would target 6890 / 6860

Daily Plan | February 24, 2026
Break and hold above 6869 would target 6893 / 6927

Holding below 6869 would target 6836 / 6805 / 6775

Daily Plan | February 25, 2026

Break and hold above 6894 would target 6911 / 6927 / 6960

Holding below 6894 would target 6869 / 6833

Daily Plan | February 26, 2026
Holding above 6960 would target 6976 / 6993 / 7017

Break and hold below 6960 would target 6948 / 6927 / 6912


Daily Plan | February 27, 2026

Break and hold above 6931 would target 6960 / 6976

Holding below 6927 would target 6904 / 6880 / 6849'''	



import re
from calendar import month_name


def month_to_number(month_str):
    for i in range(1, 13):
        if month_name[i].lower() == month_str.lower():
            return i
    raise ValueError(f"Invalid month: {month_str}")


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


def parse_dates(title):
    """
    Returns (start_iso, end_iso)
    """
    date_part = title.split("|")[1].strip()

    month_str, rest = date_part.split(" ", 1)
    month = month_to_number(month_str)

    if "-" in rest:
        days_part, year = rest.split(",")
        start_day, end_day = days_part.split("-")
        year = int(year.strip())

        start_iso = f"{year:04d}-{month:02d}-{int(start_day):02d}"
        end_iso = f"{year:04d}-{month:02d}-{int(end_day):02d}"
    else:
        day, year = rest.split(",")
        year = int(year.strip())

        start_iso = f"{year:04d}-{month:02d}-{int(day):02d}"
        end_iso = start_iso

    return start_iso, end_iso


def parse_plan(text):
    results = []

    sections = re.split(r'\n(?=[A-Z].*?\|\s+[A-Za-z]+\s+\d)', text.strip())

    for section in sections:
        lines = [l.strip() for l in section.splitlines() if l.strip()]
        if not lines:
            continue

        title = lines[0]

        category = "weekly" if "Weekly" in title else "daily"
        start_date, end_date = parse_dates(title)

        smash = None
        ups = []
        downs = []

        for line in lines[1:]:

            smash_match = re.search(r'(above|below)\s+(\d+)', line)
            if smash_match:
                smash = int(smash_match.group(2))

            target_match = re.search(r'would target (.+)', line)
            if target_match:
                raw_targets = target_match.group(1)
                tokens = re.findall(r'\d+\*?(?:-\d+\*?)?', raw_targets)

                numbers = []
                for token in tokens:
                    numbers.extend(expand_range(token))

                if "above" in line:
                    ups.extend(numbers)
                elif "below" in line:
                    downs.extend(numbers)

        if smash is not None:
            results.append({
                "category": category,
                "start": start_date,
                "end": end_date,
                "type": "smash",
                "level": smash
            })

        for i, level in enumerate(sorted(ups), start=1):
            results.append({
                "category": category,
                "start": start_date,
                "end": end_date,
                "type": f"{category}Up{i}",
                "level": level
            })

        for i, level in enumerate(sorted(downs, reverse=True), start=1):
            results.append({
                "category": category,
                "start": start_date,
                "end": end_date,
                "type": f"{category}Down{i}",
                "level": level
            })

    return results


# ---- Usage ----
data = parse_plan(text)

for row in data:
    print(row)