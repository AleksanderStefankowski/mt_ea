#!/usr/bin/env python3
# python_OSSMART_send_DailyEmail.py
#
# Runs continually; sends Gmail with full day_summary.txt from MT5 Files.
# Uses credentials.json + token.pickle in Aleksik_support (gmail_auth_common).
#
# Windows day_summary (typical):
#   .../Terminal/<hash>/MQL5/Files/day_summary.txt
# Mac Wine:
#   .../MetaTrader 5/MQL5/Files/day_summary.txt
#
# Run from Aleksik_support:
#   python python_OSSMART_send_DailyEmail.py

from __future__ import annotations

import base64
import glob
import os
import platform
import re
import sys
import time
from datetime import date, datetime
from email.mime.text import MIMEText
from typing import Optional, Tuple

from gmail_auth_common import get_gmail_service

# ============================================================
# CONFIG
# ============================================================

send_email_on_start = False
send_email_on_time_hhmm = "22:02"  # once per calendar day when local clock hits HH:MM

POLL_SECONDS = 55
RETRY_WINDOW_MINUTES = 10  # after scheduled HH:MM, keep retrying until success or window ends
EMAIL_SUBJECT_PREFIX = "mt5"

EMAIL_FROM = "aleksikstorage2@gmail.com"
EMAIL_TO = "aleksikstorage2@gmail.com"

DAY_SUMMARY_FILENAME = "day_summary.txt"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RELATIVE_DAY_SUMMARY = os.path.normpath(
    os.path.join(SCRIPT_DIR, "..", "..", "Files", DAY_SUMMARY_FILENAME)
)

# Mac Wine MT5 Files (override with OSSMART_MAC_WINE_MT5_ROOT if needed)
MAC_WINE_MT5_ROOT = os.environ.get(
    "OSSMART_MAC_WINE_MT5_ROOT",
    "/Users/sparkuser/Library/Application Support/"
    "net.metaquotes.wine.metatrader5/drive_c",
)
MAC_WINE_DAY_SUMMARY = os.environ.get(
    "OSSMART_MAC_DAY_SUMMARY",
    os.path.join(
        MAC_WINE_MT5_ROOT,
        "Program Files",
        "MetaTrader 5",
        "MQL5",
        "Files",
        DAY_SUMMARY_FILENAME,
    ),
)

# Windows explicit fallback (this machine's terminal hash)
WIN_DAY_SUMMARY_FALLBACK = os.path.join(
    os.environ.get("APPDATA", r"C:\Users\Aleks\AppData\Roaming"),
    "MetaQuotes",
    "Terminal",
    "47AEB69EDDAD4D73097816C71FB25856",
    "MQL5",
    "Files",
    DAY_SUMMARY_FILENAME,
)

DAILY_EMAIL_GMAIL_SCOPES = [
    "https://www.googleapis.com/auth/gmail.send",
]

_RE_CLOSED_NET = re.compile(r"closedNetToday=([-\d.]+)")
_RE_OPEN_PROFIT_TOTAL = re.compile(r"openProfitTotal=([-\d.]+)")
_RE_OPEN_COUNT = re.compile(r"openCount=(\d+)")
_RE_OPEN_POSITIONS = re.compile(r"openPositions=(\d+)")  # legacy day_summary
_RE_OPEN_SIZE = re.compile(r"openSize=([-\d.]+)")
_RE_MARGIN_LEVEL = re.compile(r"percentage\s+marginLevel=([-\d.]+)")


# ============================================================
# LOGGING
# ============================================================

def log(message: str) -> None:
    print(message, flush=True)


# ============================================================
# ENVIRONMENT + day_summary.txt PATH
# ============================================================

def detect_environment_label() -> str:
    system = platform.system()
    wine_prefix = os.environ.get("WINEPREFIX")
    wine_arch = os.environ.get("WINEARCH")

    if system == "Darwin":
        return "MAC"
    if system == "Windows":
        if wine_prefix or wine_arch:
            return "WINDOWS (Wine — likely Mac host running MT5 via Wine)"
        return "WINDOWS"
    if wine_prefix or wine_arch:
        return f"LINUX/WINE ({system})"
    return system.upper()


def _windows_terminal_day_summary_candidates() -> list[str]:
    appdata = os.environ.get("APPDATA", "")
    if not appdata:
        return []
    pattern = os.path.join(appdata, "MetaQuotes", "Terminal", "*", "MQL5", "Files", DAY_SUMMARY_FILENAME)
    return sorted(glob.glob(pattern))


def day_summary_path_for_env(env_label: str) -> str:
    """Resolve day_summary.txt — prefer path relative to this script (works when run from repo)."""
    candidates: list[str] = [RELATIVE_DAY_SUMMARY]

    if env_label == "MAC":
        candidates.append(MAC_WINE_DAY_SUMMARY)
    elif env_label.startswith("WINDOWS"):
        candidates.append(WIN_DAY_SUMMARY_FALLBACK)
        candidates.extend(_windows_terminal_day_summary_candidates())

    seen = set()
    for path in candidates:
        norm = os.path.normpath(path)
        if norm in seen:
            continue
        seen.add(norm)
        if os.path.isfile(norm):
            return norm

    # Return best guess for error messages
    if env_label == "MAC":
        return MAC_WINE_DAY_SUMMARY
    if env_label.startswith("WINDOWS"):
        return WIN_DAY_SUMMARY_FALLBACK
    return RELATIVE_DAY_SUMMARY


def read_day_summary(path: str) -> Tuple[str, bool]:
    if not os.path.isfile(path):
        return f"(missing file: {path})", False
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read(), True


def parse_subject_fields(body: str) -> Tuple[str, str, str, str, str]:
    closed_net = "?"
    open_profit_total = "?"
    open_count = "?"
    open_size = "?"
    margin_level = "?"

    match = _RE_CLOSED_NET.search(body)
    if match:
        closed_net = match.group(1)

    match = _RE_OPEN_PROFIT_TOTAL.search(body)
    if match:
        open_profit_total = match.group(1)

    match = _RE_OPEN_COUNT.search(body)
    if match:
        open_count = match.group(1)
    else:
        match = _RE_OPEN_POSITIONS.search(body)
        if match:
            open_count = match.group(1)

    match = _RE_OPEN_SIZE.search(body)
    if match:
        open_size = match.group(1)
    elif open_count == "0":
        open_size = "0.000"

    match = _RE_MARGIN_LEVEL.search(body)
    if match:
        margin_level = match.group(1)

    return closed_net, open_profit_total, open_count, open_size, margin_level


def format_net_today(closed_net: str, open_profit_total: str) -> str:
    try:
        closed_value = 0.0 if closed_net == "?" else float(closed_net)
        open_value = 0.0 if open_profit_total == "?" else float(open_profit_total)
        return str(int(round(closed_value + open_value)))
    except ValueError:
        return "?"


def format_open_size_for_subject(raw: str) -> str:
    if raw == "?":
        return "?"
    try:
        return f"{float(raw):.3f}"
    except ValueError:
        return raw


def format_margin_level_for_subject(raw: str) -> str:
    if raw == "?":
        return "?"
    try:
        return f"{int(round(float(raw)))}%"
    except ValueError:
        return raw


def format_email_body(body: str) -> str:
    lines = body.splitlines()
    formatted: list[str] = []

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("closedNetToday=") or stripped.startswith("openProfitTotal="):
            if formatted and formatted[-1] != "":
                formatted.append("")
        formatted.append(line)

    return "\n".join(formatted)


def build_email_subject(body: str, when: datetime) -> str:
    closed_net, open_profit_total, open_count, open_size, margin_level = parse_subject_fields(body)
    net_today = format_net_today(closed_net, open_profit_total)
    open_size_str = format_open_size_for_subject(open_size)
    margin_level_str = format_margin_level_for_subject(margin_level)
    return (
        f"{EMAIL_SUBJECT_PREFIX} NetToday={net_today} PLN | "
        f"openCount={open_count} openSize={open_size_str} marginLevel={margin_level_str}"
    )


# ============================================================
# GMAIL
# ============================================================

def send_daily_email(service, subject: str, body: str) -> None:
    message = MIMEText(body)
    message["to"] = EMAIL_TO
    message["from"] = EMAIL_FROM
    message["subject"] = subject

    raw = base64.urlsafe_b64encode(message.as_bytes()).decode("ascii")
    service.users().messages().send(userId="me", body={"raw": raw}).execute()


def send_day_summary(service, summary_path: str, *, reason: str, when: Optional[datetime] = None) -> bool:
    when = when or datetime.now()
    body, found = read_day_summary(summary_path)
    body = format_email_body(body)
    subject = build_email_subject(body, when)
    date_label = when.strftime("%b %d")

    log("")
    log(f"--- send daily email ({date_label} {reason}) ---")
    log(f"  day_summary: {summary_path} ({'found' if found else 'MISSING'})")
    log(f"  subject: {subject}")
    log(f"  body lines: {body.count(chr(10)) + (1 if body else 0)}")

    try:
        send_daily_email(service, subject, body)
        log("  sent OK")
        return True
    except Exception as exc:
        log(f"  ERROR sending email: {exc}")
        return False


# ============================================================
# SCHEDULING
# ============================================================

def parse_hhmm(value: str) -> Tuple[int, int]:
    parts = value.strip().split(":")
    if len(parts) != 2:
        raise ValueError(f"send_email_on_time_hhmm must be HH:MM, got {value!r}")
    hour = int(parts[0])
    minute = int(parts[1])
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        raise ValueError(f"invalid time {value!r}")
    return hour, minute


def scheduled_time_today(now: datetime, hour: int, minute: int) -> datetime:
    return now.replace(hour=hour, minute=minute, second=0, microsecond=0)


def minutes_since_scheduled(now: datetime, hour: int, minute: int) -> Optional[float]:
    scheduled = scheduled_time_today(now, hour, minute)
    if now < scheduled:
        return None
    return (now - scheduled).total_seconds() / 60.0


def in_retry_window(now: datetime, hour: int, minute: int) -> bool:
    elapsed = minutes_since_scheduled(now, hour, minute)
    if elapsed is None:
        return False
    return elapsed <= RETRY_WINDOW_MINUTES


def should_attempt_scheduled_send(
    now: datetime,
    last_sent_date: Optional[date],
    hour: int,
    minute: int,
) -> bool:
    today = now.date()
    if last_sent_date == today:
        return False

    at_scheduled_minute = now.hour == hour and now.minute == minute
    if at_scheduled_minute:
        return True

    # Failed earlier (or process restarted): retry until window ends.
    return in_retry_window(now, hour, minute)


def retry_reason_label(hour: int, minute: int, attempt: int) -> str:
    if attempt <= 1:
        return f"scheduled {hour:02d}:{minute:02d}"
    return f"retry {attempt - 1} after {hour:02d}:{minute:02d}"


# ============================================================
# MAIN
# ============================================================

def main() -> int:
    env_label = detect_environment_label()
    summary_path = day_summary_path_for_env(env_label)
    schedule_hour, schedule_minute = parse_hhmm(send_email_on_time_hhmm)

    log("python_OSSMART_send_DailyEmail.py started")
    log(f"Environment: {env_label}")
    log(f"Script location: {os.path.abspath(__file__)}")
    log(f"Working directory: {os.getcwd()}")
    log(f"day_summary path: {summary_path}")
    log(f"send_email_on_start={send_email_on_start}")
    log(f"send_email_on_time_hhmm={send_email_on_time_hhmm}")
    log(f"retry window: {RETRY_WINDOW_MINUTES} min after scheduled time")
    log(f"poll every {POLL_SECONDS}s")

    service = get_gmail_service(DAILY_EMAIL_GMAIL_SCOPES)

    last_sent_date: Optional[date] = None
    pending_send_date: Optional[date] = None
    send_attempt_date: Optional[date] = None
    send_attempt_today = 0
    retry_expired_logged_date: Optional[date] = None

    if send_email_on_start:
        send_day_summary(service, summary_path, reason="startup")

    while True:
        try:
            time.sleep(POLL_SECONDS)
        except KeyboardInterrupt:
            log("Stopped.")
            return 0

        now = datetime.now()
        today = now.date()

        if pending_send_date == today and not in_retry_window(now, schedule_hour, schedule_minute):
            if retry_expired_logged_date != today:
                log("")
                log(
                    f"--- daily email retries expired ({today.strftime('%b %d')} "
                    f"after {RETRY_WINDOW_MINUTES} min past "
                    f"{schedule_hour:02d}:{schedule_minute:02d}) ---"
                )
                retry_expired_logged_date = today
            pending_send_date = None
            send_attempt_today = 0

        if not should_attempt_scheduled_send(now, last_sent_date, schedule_hour, schedule_minute):
            continue

        if send_attempt_date != today:
            send_attempt_today = 0
        send_attempt_date = today
        send_attempt_today += 1
        reason = retry_reason_label(schedule_hour, schedule_minute, send_attempt_today)
        if send_day_summary(service, summary_path, reason=reason, when=now):
            last_sent_date = today
            pending_send_date = None
            send_attempt_today = 0
        else:
            pending_send_date = today


if __name__ == "__main__":
    sys.exit(main())
