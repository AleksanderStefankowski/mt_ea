# python_price_alert.py
#
# Polls ES=F 1-minute bars via yfinance. For each level relevant today
# (from levelsinfo_zeFinal.csv), sends a Gmail alert when price is within
# price_proximity_trigger points of the level.
#
# Upon launch (and also once every reload_levels_file_every_x_minutes),
# reads levels file levelsinfo_zeFinal and loads into memory rows relevant
# today, e.g.:
#   start       end         levelPrice  categories                      tag
#   2026.06.22  2026.06.26  7540        weekly_pivot_stacked_monday     weeklyPivot
#   2026.06.22  2026.06.26  7613        weekly_stacked_monday           weeklyUp1
#   2026.06.22  2026.06.26  7632        weekly_stacked_monday           weeklyUp2
#   2026.06.22  2026.06.26  7705        weekly                            weeklyUp3
#
# General rule: an email cannot be sent again unless the last email sent
# for that level was over can_send_email_if_x_minutes_passed minutes ago.
# An email can be sent for a given level if time allows and
# price_proximity_trigger allows.
#
# Email title format:
#   pythonOloAlertsV1 (levelprice) (leveltag) and price(L) (actual value) proximity above less than (price_proximity_trigger)
#   (or below, if price is below level but still within proximity)
#
# Email body: all levels active today sorted highest-first, with live OHLC inserted at its price position:
#   somelevelprice, tag, categories
#   liveprice O=... H=... L=... C=..., LIVEPRICE
#   somelevelprice, tag, categories
#
# use existing token.pickle
# send from aleksikstorage2@gmail.com to aleksikstorage2@gmail.com

import base64
import csv
import os
import pickle
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from email.mime.text import MIMEText
from typing import Dict, Optional, Tuple

import yfinance as yf  # python3 -m pip install yfinance
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

# ============================================================
# CONFIG
# ============================================================

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LEVELS_FILE = os.path.join(SCRIPT_DIR, "levelsinfo_zeFinal.csv")
TOKEN_FILE = os.path.join(SCRIPT_DIR, "token.pickle")  # use existing token.pickle
CREDENTIALS_FILE = os.path.join(SCRIPT_DIR, "credentials.json")

EMAIL_FROM = "aleksikstorage2@gmail.com"  # send from
EMAIL_TO = "aleksikstorage2@gmail.com"    # send to
EMAIL_SUBJECT_PREFIX = "pythonOloAlertsV1"

# general rule: an email cannot be sent again unless last email sent was over this many minutes ago
can_send_email_if_x_minutes_passed = 120

# a stacked level counts as both daily and weekly, so if weekly is false but daily true
# (or weekly true daily false), stacked email can still be sent
can_send_daily_level_emails = True
can_send_weekly_level_emails = False

# if any of O H L C, minus level, is less than this proximity, the proximity rule for email is satisfied
price_proximity_trigger = 15.0 # phone notification has delay like 3 minutes even

# script reads levels file on launch and again every this many minutes
reload_levels_file_every_x_minutes = 60

# every this many minutes, find up to 3 emails with title starting with "pythonOloAlertsV1"
# that are older than can_delete_email_older_than_x_minutes and delete each (move to bin)
check_emails_for_deletion_every_x_minutes = 30
can_delete_email_older_than_x_minutes = 45

SCOPES = [
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/gmail.modify",
]

es = yf.Ticker("ES=F")
last_seen = None  # last 1m bar timestamp already processed


# ============================================================
# LEVEL STATE (in-memory tracking per level)
# ============================================================
# For each level relevant today, loaded into program memory with:
#   levelprice, categories, tag, relevantDates  — from levels file
#   emailedCount, lastEmailTime                 — runtime tracking
#
# emailedCount increases when an email was sent for that level.
# lastEmailTime is stored at email sent time for that level.
#
# Reloading levels file cannot clear the currently tracked data of the level,
# unless it is a new day. The script refreshes what is considered current day
# date so that if reload_levels_file_every_x_minutes loads suddenly new levels
# for the live date (live date changed to a new day) it resets the daily tracking.

@dataclass
class LevelState:
    level_price: float      # levelPrice from file
    categories: str         # categories from file
    tag: str                # tag from file
    start_date: date
    end_date: date
    emailed_count: int = 0          # emailedCount — increases when email sent
    last_email_time: Optional[datetime] = None  # lastEmailTime — set at send time

    @property
    def key(self) -> Tuple[float, str]:
        return (self.level_price, self.tag)

    @property
    def relevant_dates(self) -> str:
        # relevantDates — start/end range from levels file
        return f"{self.start_date:%Y.%m.%d}-{self.end_date:%Y.%m.%d}"


# ============================================================
# GMAIL — auth, send alerts, delete old alerts
# ============================================================

def get_gmail_service():
    # use existing token.pickle (same folder as this script)
    creds = None

    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE, "rb") as f:
            creds = pickle.load(f)

    if creds:
        token_scopes = set(creds.scopes or [])
        if not all(scope in token_scopes for scope in SCOPES):
            print("token.pickle missing gmail send/modify scopes — re-authenticating...")
            creds = None

    if not creds or not creds.valid:
        from google.auth.exceptions import RefreshError

        if creds and creds.expired and creds.refresh_token:
            try:
                creds.refresh(Request())
            except RefreshError:
                print("Refresh token expired/revoked. Re-authenticating...")
                creds = None

        if not creds:
            flow = InstalledAppFlow.from_client_secrets_file(
                CREDENTIALS_FILE, SCOPES
            )
            creds = flow.run_local_server(port=0, prompt="consent")

        with open(TOKEN_FILE, "wb") as f:
            pickle.dump(creds, f)

    return build("gmail", "v1", credentials=creds)


def send_alert_email(service, subject: str, body: str) -> None:
    # send from aleksikstorage2@gmail.com to aleksikstorage2@gmail.com
    message = MIMEText(body)
    message["to"] = EMAIL_TO
    message["from"] = EMAIL_FROM
    message["subject"] = subject

    raw = base64.urlsafe_b64encode(message.as_bytes()).decode("ascii")
    service.users().messages().send(
        userId="me", body={"raw": raw}
    ).execute()


def is_alert_email(headers: dict) -> bool:
    """True if message is our self-sent pythonOloAlertsV1 alert."""
    subject = headers.get("Subject", "")
    if not subject.startswith(EMAIL_SUBJECT_PREFIX):
        return False

    from_hdr = headers.get("From", "")
    if EMAIL_FROM not in from_hdr:
        return False

    # self-sent mail: To can be missing or formatted oddly; Delivered-To is reliable in inbox
    to_hdr = headers.get("To", "")
    delivered_to = headers.get("Delivered-To", "")
    if EMAIL_TO in to_hdr or EMAIL_TO in delivered_to:
        return True

    # sent-folder copy: from us + our subject prefix is enough
    return EMAIL_FROM in from_hdr


def delete_old_alert_emails(service, max_delete: int = 3) -> int:
    # every check_emails_for_deletion_every_x_minutes, find up to 3 emails with
    # title starting with "pythonOloAlertsV1" from EMAIL_FROM that are older than
    # can_delete_email_older_than_x_minutes and delete each (move to bin)
    cutoff_ms = int(
        (datetime.now() - timedelta(minutes=can_delete_email_older_than_x_minutes)).timestamp()
        * 1000
    )

    # do not use to: in query — Gmail often fails to match self-sent inbox mail with to:
    query = f"from:{EMAIL_FROM} subject:{EMAIL_SUBJECT_PREFIX} -in:trash -in:spam"
    results = service.users().messages().list(
        userId="me",
        q=query,
        maxResults=25,
    ).execute()

    messages = results.get("messages", [])
    if not messages:
        print(f"Email cleanup: 0 messages matched query ({query})")
        return 0

    candidates = []
    skipped_young = 0
    skipped_headers = 0
    for msg in messages:
        msg_data = service.users().messages().get(
            userId="me",
            id=msg["id"],
            format="metadata",
            metadataHeaders=["From", "To", "Delivered-To", "Subject"],
        ).execute()
        headers = {
            h["name"]: h["value"]
            for h in msg_data.get("payload", {}).get("headers", [])
        }
        if not is_alert_email(headers):
            skipped_headers += 1
            continue

        internal_date = int(msg_data.get("internalDate", "0"))
        if internal_date >= cutoff_ms:
            skipped_young += 1
            continue

        candidates.append((internal_date, msg["id"], headers.get("Subject", "")))

    candidates.sort(key=lambda item: item[0])

    print(
        f"Email cleanup: matched {len(messages)}, "
        f"eligible {len(candidates)}, skipped young {skipped_young}, "
        f"skipped headers {skipped_headers}"
    )

    deleted = 0
    for _, msg_id, subject in candidates[:max_delete]:
        try:
            service.users().messages().trash(userId="me", id=msg_id).execute()
            deleted += 1
            print(f"  trashed: {subject}")
        except Exception as e:
            print(f"  trash failed for {msg_id}: {e}")

    return deleted


# ============================================================
# LEVELS — load from file, merge on reload, detect new day
# ============================================================

def parse_level_date(value: str) -> date:
    return datetime.strptime(value.strip(), "%Y.%m.%d").date()


def category_allows_email(categories: str) -> bool:
    # a stacked level counts as both daily and weekly — email allowed if either flag is on
    cats = categories.lower()
    is_stacked = "stacked" in cats
    is_weekly = "weekly" in cats
    is_daily = "daily" in cats

    if is_stacked:
        return can_send_daily_level_emails or can_send_weekly_level_emails
    if is_weekly:
        return can_send_weekly_level_emails
    if is_daily:
        return can_send_daily_level_emails
    return True


def load_levels_for_day(today: date) -> Dict[Tuple[float, str], LevelState]:
    # read levelsinfo_zeFinal, keep only rows where start <= today <= end
    levels: Dict[Tuple[float, str], LevelState] = {}

    with open(LEVELS_FILE, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            start = parse_level_date(row["start"])
            end = parse_level_date(row["end"])
            if start <= today <= end:
                level = LevelState(
                    level_price=float(row["levelPrice"]),
                    categories=row["categories"],
                    tag=row["tag"],
                    start_date=start,
                    end_date=end,
                )
                levels[level.key] = level

    return levels


def merge_levels(
    existing: Dict[Tuple[float, str], LevelState],
    fresh: Dict[Tuple[float, str], LevelState],
    new_day: bool,
) -> Dict[Tuple[float, str], LevelState]:
    # reloading levels file cannot clear tracked data unless it is a new day
    if new_day:
        return fresh  # reset emailedCount / lastEmailTime for all levels

    merged = {}
    for key, level in fresh.items():
        if key in existing:
            level.emailed_count = existing[key].emailed_count
            level.last_email_time = existing[key].last_email_time
        merged[key] = level
    return merged


def reload_levels(
    tracked_levels: Dict[Tuple[float, str], LevelState],
    current_day: Optional[date],
) -> Tuple[Dict[Tuple[float, str], LevelState], date]:
    # called on launch and every reload_levels_file_every_x_minutes;
    # refreshes current day date and resets tracking when live date changed to a new day
    today = date.today()
    fresh = load_levels_for_day(today)
    new_day = current_day is not None and today != current_day
    merged = merge_levels(tracked_levels, fresh, new_day)

    print(
        f"Loaded {len(merged)} levels for {today:%Y.%m.%d}"
        + (" (new day reset)" if new_day else "")
    )
    return merged, today


# ============================================================
# PROXIMITY / ALERTS
# ============================================================

def proximity_hit(
    level_price: float, o: float, h: float, l: float, c: float
) -> Optional[Tuple[str, float, float, str]]:
    # if any of O H L C minus level is less than price_proximity_trigger, rule is satisfied;
    # returns closest of OHLC and whether price is above or below the level
    points = [("O", o), ("H", h), ("L", l), ("C", c)]
    closest_label, closest_price = min(
        points, key=lambda item: abs(item[1] - level_price)
    )
    diff = closest_price - level_price
    distance = abs(diff)

    if distance >= price_proximity_trigger:
        return None

    direction = "above" if diff >= 0 else "below"
    return closest_label, closest_price, distance, direction


def can_send_for_level(level: LevelState, now: datetime) -> bool:
    # email cannot be sent again unless last email was over can_send_email_if_x_minutes_passed ago
    if level.last_email_time is None:
        return True
    elapsed = now - level.last_email_time
    return elapsed >= timedelta(minutes=can_send_email_if_x_minutes_passed)


def build_email_subject(
    level: LevelState, closest_label: str, closest_price: float, direction: str
) -> str:
    # email title: pythonOloAlertsV1 (levelprice) (leveltag) and price(O/H/L/C) (value) proximity above/below less than (trigger)
    return (
        f"{EMAIL_SUBJECT_PREFIX} ({level.level_price:.0f}) ({level.tag}) "
        f"and price({closest_label}) ({closest_price:.2f}) proximity {direction} "
        f"less than ({price_proximity_trigger:g})"
    )


def build_email_body(
    levels: Dict[Tuple[float, str], LevelState],
    o: float,
    h: float,
    l: float,
    c: float,
    ts: datetime,
) -> str:
    # all levels active today, highest price first; live OHLC inserted at its sorted position:
    #   somelevelprice, tag, categories
    #   somelevelprice, tag, categories
    #   liveprice O=... H=... L=... C=..., LIVEPRICE
    #   somelevelprice, tag, categories
    entries = []
    for level in levels.values():
        line = f"{level.level_price:.0f}, {level.tag}, {level.categories}"
        entries.append((level.level_price, 0, line))

    live_line = f"{c:.2f} O={o:.2f} H={h:.2f} L={l:.2f} C={c:.2f}, LIVEPRICE"
    entries.append((c, 1, live_line))  # 1 = after a level at the same price

    entries.sort(key=lambda item: (-item[0], item[1]))
    lines = [line for _, _, line in entries]

    return f"ES=F proximity alert\nBar time: {ts}\n\n" + "\n".join(lines) + "\n"


def maybe_send_alerts(
    service,
    levels: Dict[Tuple[float, str], LevelState],
    o: float,
    h: float,
    l: float,
    c: float,
    ts: datetime,
) -> None:
    # for each tracked level: check category filter, proximity, and cooldown; then send
    now = datetime.now()

    for level in levels.values():
        if not category_allows_email(level.categories):
            continue

        hit = proximity_hit(level.level_price, o, h, l, c)
        if hit is None:
            continue

        if not can_send_for_level(level, now):
            continue

        closest_label, closest_price, distance, direction = hit
        subject = build_email_subject(level, closest_label, closest_price, direction)
        body = build_email_body(levels, o, h, l, c, ts)

        send_alert_email(service, subject, body)
        level.emailed_count += 1   # emailedCount increases when email sent
        level.last_email_time = now  # lastEmailTime stored at email sent time
        print(f"Sent alert: {subject}")


# ============================================================
# MAIN LOOP — poll ES=F bars, reload levels, cleanup emails
# ============================================================

def main():
    global last_seen

    service = get_gmail_service()
    tracked_levels: Dict[Tuple[float, str], LevelState] = {}
    current_day: Optional[date] = None

    # upon launch: read levels file
    tracked_levels, current_day = reload_levels(tracked_levels, current_day)
    last_reload = time.monotonic()
    last_email_cleanup = 0.0  # run email cleanup on first loop iteration

    while True:
        try:
            now_mono = time.monotonic()

            # also once every reload_levels_file_every_x_minutes: re-read levels file
            if now_mono - last_reload >= reload_levels_file_every_x_minutes * 60:
                tracked_levels, current_day = reload_levels(
                    tracked_levels, current_day
                )
                last_reload = now_mono

            # every check_emails_for_deletion_every_x_minutes: trash old alert emails
            if now_mono - last_email_cleanup >= check_emails_for_deletion_every_x_minutes * 60:
                deleted = delete_old_alert_emails(service)
                print(f"Email cleanup done: trashed {deleted}")
                last_email_cleanup = now_mono

            # fetch latest 1m ES=F bar; only act on new bar (ts != last_seen)
            bar = es.history(period="1d", interval="1m").tail(1)
            if bar.empty:
                time.sleep(30)
                continue

            ts = bar.index[-1]

            if ts != last_seen:
                last_seen = ts
                o = float(bar["Open"].iloc[-1])
                h = float(bar["High"].iloc[-1])
                l = float(bar["Low"].iloc[-1])
                c = float(bar["Close"].iloc[-1])
                v = float(bar["Volume"].iloc[-1])

                print(
                    f"{ts} | "
                    f"O={o} H={h} L={l} C={c} V={v}"
                )

                maybe_send_alerts(service, tracked_levels, o, h, l, c, ts)

        except Exception as e:
            print("Error:", e)

        time.sleep(30)


if __name__ == "__main__":
    main()
