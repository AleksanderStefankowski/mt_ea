import csv
import re
from calendar import month_abbr, month_name
from datetime import datetime, timedelta


def month_to_number(month_str):
    key = month_str.strip().lower()
    for i in range(1, 13):
        if month_name[i].lower() == key or month_abbr[i].lower() == key:
            return i
    raise ValueError(f"Invalid month: {month_str}")


def load_trading_dates(calendar_path):
    trading = set()
    with open(calendar_path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["dayofweek"] not in ("Saturday", "Sunday"):
                trading.add(row["date"])
    return trading


def parse_first_date_in_title(date_part):
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
    single = re.match(
        r"^([A-Za-z]+)\s+(\d+)(?:/\d+|-\d+)*,\s*(\d{4})$",
        date_part.strip(),
    )
    if not single:
        raise ValueError(f"Cannot parse daily date part: {date_part!r}")

    month_str, day, year_s = single.groups()
    year = int(year_s)
    mo = month_to_number(month_str)
    iso = f"{year:04d}.{mo:02d}.{int(day):02d}"
    return iso, iso


def parse_title_range(title, trading):
    parts = title.split("|")
    if len(parts) < 2:
        raise ValueError(f"No date part in title: {title!r}")
    date_part = parts[1].strip()
    if "Weekly" in title:
        anchor = parse_first_date_in_title(date_part)
        return week_trading_span(anchor, trading)
    return parse_daily_date(date_part)


def expand_range(token):
    token = token.replace("*", "")

    if "-" not in token:
        return [int(token)]

    left, right = token.split("-")

    if len(right) < len(left):
        right = left[: len(left) - len(right)] + right

    return [int(left), int(right)]


NARRATIVE_REJECT_RE = re.compile(
    r"\b(Acceptance|Extreme|settlement|implying|defend|UT\d+|FUT|MA\d+|VWAP|"
    r"value area|single prints|flip side|sustained buying)\b",
    re.I,
)

COMPACT_TARGET_LINE_EXAMPLE_UP = (
    "  Holding above 7354 would target 7449 / 7515 / 7565 / 7595* / 7632"
)
COMPACT_TARGET_LINE_EXAMPLE_DOWN = (
    "  Break and hold below 7354 would target 7299 / 7230 / 7200* / 7160 / 7092"
)

# Plans that don't use standard slash-list formatting (title -> normalized compact lines).
PLAN_TITLE_EXCEPTIONS = {
    "ES Daily Plan | May 15, 2024": {
        "lines": [
            "Holding above 5266 would target 5285 / 5297 / 5307",
            "Break and hold below 5260 would target 5246 / 5227",
        ],
        "pivot": 5266,
    },
}


def normalize_plan_title(title):
    t = (title or "").strip()
    return re.sub(r"^(?:(?:Re|Fwd):\s*)+", "", t, flags=re.I).strip()


def plan_title_exception(title):
    return PLAN_TITLE_EXCEPTIONS.get(normalize_plan_title(title))


def exception_body_lines(title):
    exc = plan_title_exception(title)
    return exc["lines"] if exc else None


def plan_exception_extract_block(title):
    lines = exception_body_lines(title)
    if not lines:
        return None
    return "\n".join([normalize_plan_title(title)] + lines)


def body_lines_for_plan(title, body_lines):
    exc_lines = exception_body_lines(title)
    return exc_lines if exc_lines else body_lines


def would_target_tail(line):
    match = re.search(r"would target\s+(.+)$", line, re.I)
    return match.group(1).strip() if match else ""


def would_target_direction(line):
    lower = line.lower()
    if "would target" not in lower:
        return None
    if "above" in lower:
        return "up"
    if "below" in lower:
        return "down"
    return None


def parse_slash_target_numbers(tail):
    """Parse level prices only from ' / '-separated segments (ignores dates like 2/21)."""
    if " / " not in tail:
        return []
    numbers = []
    for part in tail.split(" / "):
        part = part.strip()
        tokens = re.findall(r"\d+\*?(?:-\d+\*?)?", part)
        if not tokens:
            continue
        numbers.extend(expand_range(tokens[0].replace("*", "")))
    return numbers


def is_compact_would_target_line(line):
    """Slash-list would-target line only; narrative paragraphs are rejected."""
    if "would target" not in line.lower():
        return False
    if len(line) > 220:
        return False
    if would_target_direction(line) is None:
        return False
    tail = would_target_tail(line)
    if not tail:
        return False
    if NARRATIVE_REJECT_RE.search(tail):
        return False
    # Require slash-separated level list (rejects narrative with embedded 2/21 dates).
    if tail.count(" / ") < 1:
        return False
    return len(parse_slash_target_numbers(tail)) >= 2


def collect_compact_would_target_lines(body_lines):
    """Return best compact up/down would-target line from body (one each)."""
    best_up = None
    best_up_score = -1
    best_down = None
    best_down_score = -1

    for line in body_lines:
        stripped = line.strip()
        if not stripped or not is_compact_would_target_line(stripped):
            continue
        direction = would_target_direction(stripped)
        score = len(parse_slash_target_numbers(would_target_tail(stripped)))
        if direction == "up" and score > best_up_score:
            best_up = stripped
            best_up_score = score
        elif direction == "down" and score > best_down_score:
            best_down = stripped
            best_down_score = score

    result = []
    if best_up:
        result.append(best_up)
    if best_down:
        result.append(best_down)
    return result


def compact_target_lines_help():
    return "\n".join(
        [
            "Expected compact slash-list target lines (both required):",
            COMPACT_TARGET_LINE_EXAMPLE_UP,
            COMPACT_TARGET_LINE_EXAMPLE_DOWN,
            "Each line must use ' / ' between at least two level prices.",
            "Narrative-only paragraphs are rejected (no fallback).",
        ]
    )


def require_compact_target_lines(title, body_lines):
    body_lines = body_lines_for_plan(title, body_lines)
    lines = collect_compact_would_target_lines(body_lines)
    has_up = any(would_target_direction(line) == "up" for line in lines)
    has_down = any(would_target_direction(line) == "down" for line in lines)
    missing = []
    if not has_up:
        missing.append("up")
    if not has_down:
        missing.append("down")
    if missing:
        body_preview = "\n".join(f"  {line!r}" for line in body_lines if line.strip())
        raise ValueError(
            f"Plan missing compact slash-list {' and '.join(missing)} target line(s): {title!r}\n"
            f"{compact_target_lines_help()}\n\n"
            f"Body lines:\n{body_preview or '  (empty)'}"
        )
    return lines


def pivot_from_compact_line(line):
    pivot_match = re.search(r"(above|below)\s+(\d+)", line)
    if not pivot_match:
        return None
    return int(pivot_match.group(2))


def parse_plan_recognition_patterns_help():
    return "\n".join(
        [
            "Recognized patterns for each Daily/Weekly plan section:",
            "  title: '<symbol> Daily|Weekly Plan | <date>'",
            "  pivot: (above|below) <price> on compact target lines",
            compact_target_lines_help(),
            "  target numbers: parsed only from ' / '-separated segments after 'would target'",
        ]
    )


def format_plan_parse_debug(title, category, start_date, end_date, pivot, ups, downs, line_recognitions):
    lines = [
        parse_plan_recognition_patterns_help(),
        "",
        f"Plan: {title!r} ({category}, {start_date}..{end_date})",
        f"pivot recognized: {pivot if pivot is not None else '(none)'}",
        f"up levels: {ups!r}",
        f"down levels: {downs!r}",
        "",
        "Per-line recognition:",
    ]
    if not line_recognitions:
        lines.append("  (no body lines)")
    for i, rec in enumerate(line_recognitions, start=1):
        parts = [f"  [{i}] {rec['line']!r}"]
        if rec["pivot"]:
            parts.append(f"      pivot: {rec['pivot']}")
        if rec["target"]:
            t = rec["target"]
            direction = t["direction"] if t["direction"] else "NONE (ignored)"
            parts.append(
                f"      would target: direction={direction}, raw={t['raw']!r}, numbers={t['numbers']!r}"
            )
            if t.get("note"):
                parts.append(f"      note: {t['note']}")
        if not rec["pivot"] and not rec["target"]:
            parts.append("      (no pivot or would-target pattern matched)")
        lines.extend(parts)
    return "\n".join(lines)


def recognize_plan_body(title, body_lines):
    category = "weekly" if "Weekly" in title else "daily"
    body_lines = body_lines_for_plan(title, body_lines)
    compact_lines = require_compact_target_lines(title, body_lines)

    pivot = None
    exc = plan_title_exception(title)
    if exc and exc.get("pivot") is not None:
        pivot = exc["pivot"]

    ups = []
    downs = []
    line_recognitions = []

    for line in body_lines:
        rec = {"line": line, "pivot": None, "target": None}
        if is_compact_would_target_line(line):
            pivot_match = re.search(r"(above|below)\s+(\d+)", line)
            if pivot_match:
                pivot = int(pivot_match.group(2))
                rec["pivot"] = f"{pivot_match.group(1)} {pivot_match.group(2)}"
            tail = would_target_tail(line)
            numbers = parse_slash_target_numbers(tail)
            direction = would_target_direction(line)
            rec["target"] = {"direction": direction, "raw": tail, "numbers": numbers}
            if direction == "up":
                ups.extend(numbers)
            elif direction == "down":
                downs.extend(numbers)
        line_recognitions.append(rec)

    if pivot is None:
        for line in compact_lines:
            pivot = pivot_from_compact_line(line)
            if pivot is not None:
                break

    return {
        "title": title,
        "category": category,
        "pivot": pivot,
        "ups": ups,
        "downs": downs,
        "line_recognitions": line_recognitions,
    }


def validate_plan_recognition(recognition, start_date="?", end_date="?"):
    ups = recognition["ups"]
    downs = recognition["downs"]
    if ups and downs:
        return

    missing = []
    if not ups:
        missing.append("up")
    if not downs:
        missing.append("down")
    debug = format_plan_parse_debug(
        recognition["title"],
        recognition["category"],
        start_date,
        end_date,
        recognition["pivot"],
        ups,
        downs,
        recognition["line_recognitions"],
    )
    raise ValueError(f"Plan missing {' and '.join(missing)} levels.\n{debug}")


def validate_plan_extract(content, trading=None):
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    if not lines:
        raise ValueError("Empty plan extract.")

    title = lines[0]
    if "Marker not found" in content:
        raise ValueError(
            "Plan extract marker not found.\n"
            f"{parse_plan_recognition_patterns_help()}\n\n"
            f"Extracted content:\n{content}"
        )

    if not re.search(r"\b(Daily|Weekly)\s+Plan\b", title, re.I):
        return

    recognition = recognize_plan_body(title, lines[1:])

    start_date = end_date = "?"
    if trading is not None:
        try:
            start_date, end_date = parse_title_range(title, trading)
        except (ValueError, IndexError) as exc:
            start_date = end_date = f"(date parse failed: {exc})"

    validate_plan_recognition(recognition, start_date, end_date)
