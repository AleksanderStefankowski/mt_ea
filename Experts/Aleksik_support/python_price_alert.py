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
# An email can be sent for a given level if time allows, price_proximity_trigger allows,
# and alert_proximity_above / alert_proximity_below allow that direction.
#
# Email title format:
#   pythonOloAlertsV1 7476.25 (price-O) proximity above 7472 (dailyUp1) : less than 15
#   (or below, if price is below level but still within proximity)
#
# Email body line 1-3: ES=F proximity alert / Email sent: (local time) / Bar time: (candle)
# then all levels active today sorted highest-first, with live OHLC inserted at its price position:
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
from datetime import date, datetime, timedelta, timezone
from email.header import decode_header, make_header
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
can_send_weekly_level_emails = True

# if any of O H L C, minus level, is less than this proximity, the proximity rule for email is satisfied
price_proximity_trigger = 12.5 # phone notification has delay like 3 minutes even
alert_proximity_above = True
alert_proximity_below = True

# script reads levels file on launch and again every this many minutes
reload_levels_file_every_x_minutes = 60

# every this many minutes, trash all emails with title starting with "pythonOloAlertsV1"
# that are older than can_delete_email_older_than_x_minutes (move to bin)
check_emails_for_deletion_every_x_minutes = 120 # but do first check immediately after launch
can_delete_email_older_than_x_minutes = 600

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


def decode_email_header(value: str) -> str:
    if not value:
        return ""
    try:
        parts = decode_header(value)
        chunks = []
        for text, charset in parts:
            if isinstance(text, bytes):
                chunks.append(text.decode(charset or "utf-8", errors="replace"))
            else:
                chunks.append(str(text))
        return "".join(chunks)
    except Exception:
        try:
            return str(make_header(decode_header(value)))
        except Exception:
            return value


def list_all_message_ids(service, query: str, page_size: int = 100):
    """Paginate Gmail list until all matching message ids are collected."""
    message_ids = []
    page_token = None

    while True:
        kwargs = {"userId": "me", "q": query, "maxResults": page_size}
        if page_token:
            kwargs["pageToken"] = page_token

        results = service.users().messages().list(**kwargs).execute()
        for msg in results.get("messages", []):
            message_ids.append(msg["id"])

        page_token = results.get("nextPageToken")
        if not page_token:
            break

    return message_ids


def delete_old_alert_emails(service) -> int:
    # trash all emails with title starting with "pythonOloAlertsV1" that are older than
    # can_delete_email_older_than_x_minutes (move to bin)
    cutoff_ms = int(
        (
            datetime.now(timezone.utc)
            - timedelta(minutes=can_delete_email_older_than_x_minutes)
        ).timestamp()
        * 1000
    )

    # count ALL with subject prefix (paginated); do not use to: — fails on self-sent mail
    query = f"subject:{EMAIL_SUBJECT_PREFIX} -in:trash -in:spam"
    message_ids = list_all_message_ids(service, query)

    print(f"Email cleanup: {len(message_ids)} total with subject {EMAIL_SUBJECT_PREFIX}")

    if not message_ids:
        print(f"Email cleanup: 0 messages matched query ({query})")
        return 0

    candidates = []
    older_than_cutoff_count = 0
    eligible_count = 0
    skipped_young = 0
    skipped_subject = 0

    for msg_id in message_ids:
        msg_data = service.users().messages().get(
            userId="me",
            id=msg_id,
            format="metadata",
            metadataHeaders=["Subject"],
        ).execute()

        # age first — Gmail query already matched subject; internalDate is UTC ms
        internal_date = int(msg_data.get("internalDate", "0"))
        if internal_date >= cutoff_ms:
            skipped_young += 1
            continue

        older_than_cutoff_count += 1

        headers = {
            h["name"]: h["value"]
            for h in msg_data.get("payload", {}).get("headers", [])
        }
        subject = decode_email_header(headers.get("Subject", ""))
        # only reject if Subject header is present but clearly not our alert
        if subject and not subject.startswith(EMAIL_SUBJECT_PREFIX):
            skipped_subject += 1
            continue

        eligible_count += 1
        candidates.append((
            internal_date,
            msg_id,
            subject or EMAIL_SUBJECT_PREFIX,
        ))

    candidates.sort(key=lambda item: item[0])

    print(
        f"Email cleanup: {older_than_cutoff_count} older than "
        f"{can_delete_email_older_than_x_minutes} min "
        f"(skipped young {skipped_young})"
    )
    print(
        f"Email cleanup: {eligible_count} eligible to trash "
        f"(skipped subject {skipped_subject})"
    )

    deleted = 0
    for _, msg_id, subject in candidates:
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
    # email title: pythonOloAlertsV1 7476.25 (price-O) proximity above 7472 (dailyUp1) : less than 15
    return (
        f"{EMAIL_SUBJECT_PREFIX} {closest_price:.2f} (price-{closest_label}) "
        f"proximity {direction} {level.level_price:.0f} ({level.tag}) "
        f": less than {price_proximity_trigger:g}"
    )


def build_email_body(
    levels: Dict[Tuple[float, str], LevelState],
    o: float,
    h: float,
    l: float,
    c: float,
    ts: datetime,
    send_time: datetime,
) -> str:
    entries = []
    for level in levels.values():
        line = f"{level.level_price:.0f}, {level.tag}, {level.categories}"
        entries.append((level.level_price, 0, line))

    live_line = f"{c:.2f} O={o:.2f} H={h:.2f} L={l:.2f} C={c:.2f}, LIVEPRICE"
    entries.append((c, 1, live_line))  # 1 = after a level at the same price

    entries.sort(key=lambda item: (-item[0], item[1]))
    lines = [line for _, _, line in entries]

    return (
        f"ES=F proximity alert\n"
        f"Email sent: {send_time:%Y-%m-%d %H:%M:%S}\n"
        f"Bar time: {ts}\n\n"
        + "\n".join(lines)
        + "\n"
    )


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

        closest_label, closest_price, distance, direction = hit

        if direction == "above" and not alert_proximity_above:
            continue
        if direction == "below" and not alert_proximity_below:
            continue

        if not can_send_for_level(level, now):
            continue

        subject = build_email_subject(level, closest_label, closest_price, direction)
        send_time = datetime.now()
        body = build_email_body(levels, o, h, l, c, ts, send_time)

        send_alert_email(service, subject, body)
        level.emailed_count += 1
        level.last_email_time = send_time
        print(f"Sent alert: {subject}")


# ============================================================
# MAIN LOOP — poll ES=F bars, reload levels, cleanup emails
# ============================================================

def run_email_cleanup(service) -> int:
    print("Running email cleanup check...")
    deleted = delete_old_alert_emails(service)
    print(f"Email cleanup done: trashed {deleted}")
    if deleted > 0:
        print("Sleeping 3 seconds after trash before price checks...")
        time.sleep(3)
    return deleted


def main():
    global last_seen

    service = get_gmail_service()
    tracked_levels: Dict[Tuple[float, str], LevelState] = {}
    current_day: Optional[date] = None

    # upon launch: read levels file
    tracked_levels, current_day = reload_levels(tracked_levels, current_day)
    run_email_cleanup(service)
    last_reload = time.monotonic()
    last_email_cleanup = time.monotonic()

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
                run_email_cleanup(service)
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
