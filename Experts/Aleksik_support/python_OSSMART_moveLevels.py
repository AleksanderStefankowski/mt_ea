#!/usr/bin/env python3
# python_OSSMART_moveLevels.py
#
# Polls on a schedule, runs the Gmail levels pipeline (ruby a_gmail_api_run_all.rb),
# then copies levelsinfo_zeFinal.csv from Aleksik_support into MT5 Common/Files.
#
# Windows:  .../MQL5/Experts/Aleksik_support/levelsinfo_zeFinal.csv
#           -> %APPDATA%/MetaQuotes/Terminal/Common/Files/levelsinfo_zeFinal.csv
#
# Mac Wine: .../MetaTrader 5/MQL5/Experts/Aleksik_support/levelsinfo_zeFinal.csv
#           -> .../Terminal/Common/Files/levelsinfo_zeFinal.csv

from __future__ import annotations

import os
import platform
import shutil
import subprocess
import sys
import time
from datetime import datetime
from typing import Optional, Tuple

# ============================================================
# CONFIG
# ============================================================

run_on_time = True
# True: Mon–Fri, run once when a 10-min poll lands in 01:30–01:45 window.
# False: run immediately, then every 2 minutes.

print_polling = False
print_overwriteinfo = False

POLL_SECONDS_SCHEDULED = 10 * 60
POLL_SECONDS_IMMEDIATE = 1 * 60
SCHEDULE_HOUR = 1
SCHEDULE_MINUTE = 30
SCHEDULE_WINDOW_END_HOUR = 1
SCHEDULE_WINDOW_END_MINUTE = 45  # [01:30, 01:45) — 15 min window for 10-min polls

LEVELS_FILENAME = "levelsinfo_zeFinal.csv"
RUBY_SCRIPT = "a_gmail_api_run_all.rb"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SOURCE_FILE = os.path.join(SCRIPT_DIR, LEVELS_FILENAME)

# Windows MT5 common files (also matches hard-coded Aleks path when APPDATA is default)
WIN_COMMON_FILES = os.path.join(
    os.environ.get("APPDATA", r"C:\Users\Aleks\AppData\Roaming"),
    "MetaQuotes",
    "Terminal",
    "Common",
    "Files",
    LEVELS_FILENAME,
)

# Mac + MetaTrader 5 via Wine (override with OSSMART_MAC_WINE_* env vars if needed)
MAC_WINE_MT5_ROOT = os.environ.get(
    "OSSMART_MAC_WINE_MT5_ROOT",
    "/Users/sparkuser/Library/Application Support/"
    "net.metaquotes.wine.metatrader5/drive_c",
)
MAC_WINE_SOURCE = os.environ.get(
    "OSSMART_MAC_WINE_SOURCE",
    os.path.join(
        MAC_WINE_MT5_ROOT,
        "Program Files",
        "MetaTrader 5",
        "MQL5",
        "Experts",
        "Aleksik_support",
        LEVELS_FILENAME,
    ),
)
MAC_WINE_DEST = os.environ.get(
    "OSSMART_MAC_WINE_DEST",
    os.path.join(
        MAC_WINE_MT5_ROOT,
        "users",
        "user",
        "AppData",
        "Roaming",
        "MetaQuotes",
        "Terminal",
        "Common",
        "Files",
        LEVELS_FILENAME,
    ),
)


# ============================================================
# LOGGING
# ============================================================

def log(message: str) -> None:
    print(message, flush=True)


def poll_log(message: str) -> None:
    if print_polling:
        log(message)


def overwrite_log(message: str) -> None:
    if print_overwriteinfo:
        log(message)


# ============================================================
# ENVIRONMENT
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


def file_stats(path: str) -> Tuple[Optional[int], Optional[int]]:
    if not os.path.isfile(path):
        return None, None
    size = os.path.getsize(path)
    line_count = 0
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            line_count += chunk.count(b"\n")
    return size, line_count


def describe_path(label: str, path: str) -> None:
    exists = os.path.exists(path)
    log(f"{label}:")
    log(f"  path: {path}")
    log(f"  exists: {exists}")
    if exists:
        size, lines = file_stats(path)
        log(f"  size: {size} bytes")
        log(f"  lines: {lines}")


# ============================================================
# GMAIL PIPELINE + FILE COPY
# ============================================================

def run_gmail_pipeline() -> int:
    ruby_script = os.path.join(SCRIPT_DIR, RUBY_SCRIPT)
    if not os.path.isfile(ruby_script):
        log(f"ERROR: missing {ruby_script}")
        return 1

    log(f"Running Gmail pipeline: ruby {RUBY_SCRIPT}")
    if platform.system() == "Windows":
        result = subprocess.run(
            ["ruby", RUBY_SCRIPT],
            cwd=SCRIPT_DIR,
            check=False,
        )
    else:
        result = subprocess.run(
            ["bash", "-lc", f"ruby {RUBY_SCRIPT!r}"],
            cwd=SCRIPT_DIR,
            check=False,
        )
    if result.returncode != 0:
        log(f"WARNING: {RUBY_SCRIPT} exited with code {result.returncode}")
    return result.returncode


def overwrite_levels_file(source: str, dest: str, label: str) -> bool:
    describe_path(f"{label} destination", dest)
    describe_path(f"{label} source", source)

    if not os.path.isfile(source):
        overwrite_log(f"{label}: skip — source not found: {source}")
        return False

    dest_dir = os.path.dirname(dest)
    if not os.path.isdir(dest_dir):
        overwrite_log(f"{label}: skip — destination folder not found: {dest_dir}")
        return False

    dest_size_before, dest_lines_before = file_stats(dest)
    src_size, src_lines = file_stats(source)

    overwrite_log(f"{label}: about to overwrite")
    if dest_size_before is None:
        overwrite_log("  destination before: (missing)")
    else:
        overwrite_log(
            f"  destination before: {dest_size_before} bytes, {dest_lines_before} lines"
        )
    overwrite_log(f"  source: {src_size} bytes, {src_lines} lines")

    shutil.copy2(source, dest)

    dest_size_after, dest_lines_after = file_stats(dest)
    overwrite_log(
        f"  destination after: {dest_size_after} bytes, {dest_lines_after} lines"
    )
    log(f"{label}: copied OK")
    return True


def move_levels_for_platform(env_label: str) -> None:
    log("")
    log("--- levels file copy ---")

    if env_label == "MAC":
        overwrite_levels_file(MAC_WINE_SOURCE, MAC_WINE_DEST, "Mac Wine")
        return

    if env_label.startswith("WINDOWS"):
        overwrite_levels_file(SOURCE_FILE, WIN_COMMON_FILES, "Windows")
        return

    # Fallback: try both if paths exist (e.g. unusual Wine/Linux setup)
    log(f"Unknown environment {env_label!r}; trying Windows then Mac Wine paths")
    if os.path.isdir(os.path.dirname(WIN_COMMON_FILES)):
        overwrite_levels_file(SOURCE_FILE, WIN_COMMON_FILES, "Windows (fallback)")
    if os.path.isdir(os.path.dirname(MAC_WINE_DEST)):
        overwrite_levels_file(MAC_WINE_SOURCE, MAC_WINE_DEST, "Mac Wine (fallback)")


def run_cycle(env_label: str) -> None:
    log("")
    log("=" * 72)
    log(f"OSSMART moveLevels cycle @ {datetime.now():%Y-%m-%d %H:%M:%S}")
    log(f"Environment: {env_label}")
    log(f"Script location: {os.path.abspath(__file__)}")
    log(f"Working directory: {os.getcwd()}")
    log("=" * 72)

    run_gmail_pipeline()

    if not os.path.isfile(SOURCE_FILE):
        log(f"WARNING: local source not updated yet: {SOURCE_FILE}")
    else:
        size, lines = file_stats(SOURCE_FILE)
        log(f"Local source after pipeline: {size} bytes, {lines} lines")

    move_levels_for_platform(env_label)


# ============================================================
# SCHEDULING
# ============================================================

def is_weekday(now: datetime) -> bool:
    return now.weekday() < 5  # Mon=0 .. Fri=4


def schedule_window_start(now: datetime) -> datetime:
    return now.replace(
        hour=SCHEDULE_HOUR,
        minute=SCHEDULE_MINUTE,
        second=0,
        microsecond=0,
    )


def schedule_window_end(now: datetime) -> datetime:
    return now.replace(
        hour=SCHEDULE_WINDOW_END_HOUR,
        minute=SCHEDULE_WINDOW_END_MINUTE,
        second=0,
        microsecond=0,
    )


def in_schedule_window(now: datetime) -> bool:
    """True only during [01:30, 01:45) on the current calendar day."""
    start = schedule_window_start(now)
    end = schedule_window_end(now)
    return start <= now < end


def should_run_scheduled(now: datetime, last_run_date: Optional[datetime.date]) -> bool:
    if not is_weekday(now):
        return False
    if not in_schedule_window(now):
        return False
    if last_run_date == now.date():
        return False
    return True


def sleep_seconds() -> int:
    return POLL_SECONDS_SCHEDULED if run_on_time else POLL_SECONDS_IMMEDIATE


def main() -> int:
    env_label = detect_environment_label()
    log("python_OSSMART_moveLevels.py started")
    log(f"Environment: {env_label}")
    log(f"Script location: {os.path.abspath(__file__)}")
    log(f"run_on_time={run_on_time}  print_polling={print_polling}  "
        f"print_overwriteinfo={print_overwriteinfo}")

    if run_on_time:
        log(
            f"Polling every {POLL_SECONDS_SCHEDULED // 60} min; "
            f"job runs Mon–Fri at most once when a poll falls in "
            f"{SCHEDULE_HOUR:02d}:{SCHEDULE_MINUTE:02d}–"
            f"{SCHEDULE_WINDOW_END_HOUR:02d}:{SCHEDULE_WINDOW_END_MINUTE:02d}"
        )
    else:
        log(f"Schedule: immediate + every {POLL_SECONDS_IMMEDIATE // 60} min")

    last_run_date: Optional[datetime.date] = None

    while True:
        now = datetime.now()

        if run_on_time:
            poll_log(
                f"Poll {now:%Y-%m-%d %H:%M:%S} — weekday={is_weekday(now)} "
                f"in_schedule_window={in_schedule_window(now)} "
                f"last_run={last_run_date}"
            )
            if should_run_scheduled(now, last_run_date):
                run_cycle(env_label)
                last_run_date = now.date()
        else:
            poll_log(f"Poll {now:%Y-%m-%d %H:%M:%S} — running cycle")
            run_cycle(env_label)
            last_run_date = now.date()

        try:
            time.sleep(sleep_seconds())
        except KeyboardInterrupt:
            log("Stopped.")
            return 0


if __name__ == "__main__":
    sys.exit(main())
