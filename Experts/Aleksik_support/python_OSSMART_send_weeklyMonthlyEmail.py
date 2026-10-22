import os
import re
import base64
import time
from datetime import datetime, timezone, date, timedelta
from email.message import EmailMessage
from collections import defaultdict

from gmail_auth_common import SCRIPT_DIR, get_gmail_service


# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------

os.chdir(SCRIPT_DIR)

EMAIL_ADDRESS = "aleksikstorage2@gmail.com"

SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send",
]

PRINT_DAILY_RESULTS = False
PRINT_WEEKLY_RESULTS = True
PRINT_MONTHLY_RESULTS = True

CHECK_TIMES = ["22:22", "23:37"]


def get_service():
    return get_gmail_service(SCOPES)


# -------------------------------------------------------------------
# Date and number helpers
# -------------------------------------------------------------------

def get_current_month_range():
    now = datetime.now(timezone.utc)

    month_start = datetime(
        now.year, now.month, 1, tzinfo=timezone.utc
    )

    if now.month == 12:
        next_month_start = datetime(
            now.year + 1, 1, 1, tzinfo=timezone.utc
        )
    else:
        next_month_start = datetime(
            now.year, now.month + 1, 1, tzinfo=timezone.utc
        )

    return month_start, next_month_start


def format_date(dt):
    return dt.strftime("%Y.%m.%d")


def format_number(value):
    return f"{value:,.2f}".rstrip("0").rstrip(".")


def format_subject_number(value):
    return f"{value:.2f}".rstrip("0").rstrip(".")


def decode_base64url(data):
    if not data:
        return b""

    padding = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + padding)


# -------------------------------------------------------------------
# Email body extraction
# -------------------------------------------------------------------

def get_text_from_payload(payload):
    mime_type = payload.get("mimeType", "")
    body_data = payload.get("body", {}).get("data")

    if mime_type == "text/plain" and body_data:
        return decode_base64url(body_data).decode(
            "utf-8", errors="replace"
        )

    parts = payload.get("parts", [])

    for part in parts:
        if part.get("mimeType") == "text/plain":
            text = get_text_from_payload(part)
            if text:
                return text

    for part in parts:
        text = get_text_from_payload(part)
        if text:
            return text

    if mime_type == "text/html" and body_data:
        html = decode_base64url(body_data).decode(
            "utf-8", errors="replace"
        )
        return re.sub(r"<[^>]+>", " ", html)

    return ""


def extract_net_today(subject):
    match = re.search(
        r"\bNetToday\s*=\s*(-?\d+(?:[.,]\d+)?)",
        subject,
        re.IGNORECASE,
    )

    if not match:
        return None

    return float(match.group(1).replace(",", "."))


def extract_closed_static_balance(body):
    match = re.search(
        r"closed\s+static\s+balance\s*=\s*(-?\d+(?:[.,]\d+)?)",
        body,
        re.IGNORECASE,
    )

    if not match:
        return None

    return float(match.group(1).replace(",", "."))


# -------------------------------------------------------------------
# Gmail message parsing
# -------------------------------------------------------------------

def get_email_datetime(internal_date_ms):
    return datetime.fromtimestamp(
        int(internal_date_ms) / 1000,
        tz=timezone.utc,
    )


def fetch_and_parse_email(service, message_id):
    message = (
        service.users()
        .messages()
        .get(
            userId="me",
            id=message_id,
            format="full",
        )
        .execute()
    )

    payload = message.get("payload", {})
    headers = payload.get("headers", [])

    header_map = {
        header.get("name", "").lower(): header.get("value", "")
        for header in headers
    }

    subject = header_map.get("subject", "")
    sender = header_map.get("from", "")
    recipient = header_map.get("to", "")

    if EMAIL_ADDRESS.lower() not in sender.lower():
        return None

    if EMAIL_ADDRESS.lower() not in recipient.lower():
        return None

    subject_lower = subject.lower()

    if "mt5" not in subject_lower:
        return None

    if "week" in subject_lower or "month" in subject_lower:
        return None

    internal_date = message.get("internalDate")
    if not internal_date:
        return None

    email_dt = get_email_datetime(internal_date)
    month_start, next_month_start = get_current_month_range()

    if not (month_start <= email_dt < next_month_start):
        return None

    body = get_text_from_payload(payload)

    closed_static_balance = extract_closed_static_balance(body)
    net_today = extract_net_today(subject)

    if closed_static_balance is None or net_today is None:
        return None

    return {
        "timestamp": int(internal_date),
        "datetime": email_dt,
        "date": format_date(email_dt),
        "closed_static_balance": closed_static_balance,
        "NetToday": net_today,
    }


def list_all_message_ids(service, query):
    message_ids = []
    page_token = None

    while True:
        response = (
            service.users()
            .messages()
            .list(
                userId="me",
                q=query,
                maxResults=500,
                pageToken=page_token,
            )
            .execute()
        )

        message_ids.extend(
            item["id"]
            for item in response.get("messages", [])
        )

        page_token = response.get("nextPageToken")

        if not page_token:
            break

    return message_ids


def fetch_current_month_results(service):
    month_start, next_month_start = get_current_month_range()

    after_date = month_start.strftime("%Y/%m/%d")
    before_date = next_month_start.strftime("%Y/%m/%d")

    query = (
        f"from:{EMAIL_ADDRESS} "
        f"to:{EMAIL_ADDRESS} "
        f"after:{after_date} "
        f"before:{before_date} "
        "subject:mt5"
    )

    message_ids = list_all_message_ids(service, query)
    results = []

    for message_id in message_ids:
        try:
            result = fetch_and_parse_email(service, message_id)
            if result is not None:
                results.append(result)

        except Exception as exc:
            print(f"Could not parse message {message_id}: {exc}")

    results.sort(key=lambda item: item["timestamp"])
    return results


# -------------------------------------------------------------------
# Aggregation helpers
# -------------------------------------------------------------------

def get_weekly_groups(results):
    groups = defaultdict(list)

    for result in results:
        dt = result["datetime"].date()
        monday = dt - timedelta(days=dt.weekday())
        groups[monday].append(result)

    return groups


def calculate_period_summary(period_results):
    period_results = sorted(
        period_results,
        key=lambda item: item["timestamp"],
    )

    first_record = period_results[0]
    last_record = period_results[-1]

    starting_balance = (
        first_record["closed_static_balance"]
        - first_record["NetToday"]
    )
    ending_balance = last_record["closed_static_balance"]

    net_gain = sum(
        item["NetToday"] for item in period_results
    )

    growth_percent = (
        (ending_balance / starting_balance - 1) * 100
        if starting_balance != 0
        else 0.0
    )

    return {
        "starting_balance": starting_balance,
        "ending_balance": ending_balance,
        "net_gain": net_gain,
        "growth_percent": growth_percent,
    }


def get_last_weekday_of_month(year, month):
    if month == 12:
        current = date(year + 1, 1, 1) - timedelta(days=1)
    else:
        current = date(year, month + 1, 1) - timedelta(days=1)

    while current.weekday() >= 5:
        current -= timedelta(days=1)

    return current


# -------------------------------------------------------------------
# Optional report printing
# -------------------------------------------------------------------

def print_daily_results(results):
    print()
    print("DAILY RESULTS")
    print("=============")

    for result in results:
        print([
            result["date"],
            f'{result["closed_static_balance"]:.2f}',
            format_number(result["NetToday"]),
        ])


def print_weekly_results(results):
    print()
    print("WEEKLY RESULTS (MONDAY–FRIDAY)")
    print("==============================")

    if not results:
        print("No results for this month.")
        return

    month_start, next_month_start = get_current_month_range()
    month_first_day = month_start.date()
    month_last_day = (next_month_start - timedelta(days=1)).date()

    for monday in sorted(get_weekly_groups(results)):
        week_results = sorted(
            get_weekly_groups(results)[monday],
            key=lambda item: item["timestamp"],
        )

        friday = monday + timedelta(days=4)
        display_start = max(monday, month_first_day)
        display_end = min(friday, month_last_day)

        summary = calculate_period_summary(week_results)

        print([
            f"{format_date(datetime.combine(display_start, datetime.min.time()))}"
            f" - "
            f"{format_date(datetime.combine(display_end, datetime.min.time()))}",
            f'{summary["starting_balance"]:.2f}',
            f'{summary["ending_balance"]:.2f}',
            format_number(summary["net_gain"]),
            f'{summary["growth_percent"]:.2f}%',
        ])


def print_monthly_results(results):
    print()
    print("MONTHLY RESULTS")
    print("===============")

    if not results:
        print("No results for this month.")
        return

    summary = calculate_period_summary(results)
    now = datetime.now(timezone.utc)

    last_weekday = get_last_weekday_of_month(
        now.year, now.month
    )

    print([
        format_date(datetime.combine(last_weekday, datetime.min.time())),
        f'{summary["starting_balance"]:.2f}',
        f'{summary["ending_balance"]:.2f}',
        format_number(summary["net_gain"]),
        f'{summary["growth_percent"]:.2f}%',
    ])


# -------------------------------------------------------------------
# Sending and duplicate checking
# -------------------------------------------------------------------

def send_email(service, subject, body):
    message = EmailMessage()
    message["To"] = EMAIL_ADDRESS
    message["From"] = EMAIL_ADDRESS
    message["Subject"] = subject
    message.set_content(body)

    encoded_message = base64.urlsafe_b64encode(
        message.as_bytes()
    ).decode("utf-8")

    response = (
        service.users()
        .messages()
        .send(
            userId="me",
            body={"raw": encoded_message},
        )
        .execute()
    )

    print(f"Email sent: {subject}")


def was_subject_sent_today(service, subject, today):
    tomorrow = today + timedelta(days=1)

    query = (
        "in:sent "
        f"after:{today.strftime('%Y/%m/%d')} "
        f"before:{tomorrow.strftime('%Y/%m/%d')} "
        "subject:mt5"
    )

    for message_id in list_all_message_ids(service, query):
        try:
            message = (
                service.users()
                .messages()
                .get(
                    userId="me",
                    id=message_id,
                    format="metadata",
                    metadataHeaders=["Subject"],
                )
                .execute()
            )

            internal_date = message.get("internalDate")
            if not internal_date:
                continue

            if get_email_datetime(internal_date).date() != today:
                continue

            headers = message.get("payload", {}).get("headers", [])

            message_subject = next(
                (
                    header.get("value", "")
                    for header in headers
                    if header.get("name", "").lower() == "subject"
                ),
                "",
            )

            if message_subject == subject:
                return True

        except Exception as exc:
            print(f"Could not check sent message {message_id}: {exc}")

    return False


# -------------------------------------------------------------------
# Weekly email status
# -------------------------------------------------------------------

def maybe_send_weekly_email(service, results, today):
    if today.weekday() != 4:
        next_friday = today + timedelta(days=(4 - today.weekday()) % 7 or 7)
        print(f"weekly not sent, waiting for date: {next_friday}")
        return

    today_str = format_date(
        datetime.combine(today, datetime.min.time())
    )

    today_records = [
        result for result in results
        if result["date"] == today_str
    ]

    if not today_records:
        print(f"weekly not sent, waiting for date: {today}")
        return

    monday = today - timedelta(days=today.weekday())

    week_results = [
        result for result in results
        if monday <= result["datetime"].date() <= today
    ]

    if not week_results:
        print(f"weekly not sent, waiting for date: {today}")
        return

    summary = calculate_period_summary(week_results)
    date_range = (
        f"{format_date(datetime.combine(monday, datetime.min.time()))}"
        f" - "
        f"{format_date(datetime.combine(today, datetime.min.time()))}"
    )

    subject = (
        f"mt5 email=week "
        f"netGain={format_subject_number(summary['net_gain'])} "
        f"grow={summary['growth_percent']:.2f}% "
        f"dateRange={date_range} "
        f"month={today.month} year={today.year}"
    )

    if was_subject_sent_today(service, subject, today):
        print("weekly email already sent today")
        return

    body = (
        f"Weekly report: {date_range}\n"
        f"Starting balance: {summary['starting_balance']:.2f}\n"
        f"Ending balance: {summary['ending_balance']:.2f}\n"
        f"Net gain: {format_subject_number(summary['net_gain'])}\n"
        f"Growth: {summary['growth_percent']:.2f}%\n"
    )

    send_email(service, subject, body)


# -------------------------------------------------------------------
# Monthly email status
# -------------------------------------------------------------------

def maybe_send_monthly_email(service, results, today):
    last_weekday = get_last_weekday_of_month(
        today.year, today.month
    )

    if today != last_weekday:
        print(f"monthly not sent, waiting for date: {last_weekday}")
        return

    target_date = format_date(
        datetime.combine(last_weekday, datetime.min.time())
    )

    target_records = [
        result for result in results
        if result["date"] == target_date
    ]

    if not target_records:
        print(f"monthly not sent, waiting for date: {last_weekday}")
        return

    month_results = [
        result for result in results
        if (
            result["datetime"].year == today.year
            and result["datetime"].month == today.month
            and result["datetime"].date() <= last_weekday
        )
    ]

    if not month_results:
        print(f"monthly not sent, waiting for date: {last_weekday}")
        return

    summary = calculate_period_summary(month_results)
    date_text = format_date(
        datetime.combine(last_weekday, datetime.min.time())
    )

    subject = (
        f"mt5 email=month "
        f"netGain={format_subject_number(summary['net_gain'])} "
        f"grow={summary['growth_percent']:.2f}% "
        f"date={date_text} "
        f"month={today.month} year={today.year}"
    )

    if was_subject_sent_today(service, subject, today):
        print("monthly email already sent today")
        return

    body = (
        f"Monthly report: {date_text}\n"
        f"Starting balance: {summary['starting_balance']:.2f}\n"
        f"Ending balance: {summary['ending_balance']:.2f}\n"
        f"Net gain: {format_subject_number(summary['net_gain'])}\n"
        f"Growth: {summary['growth_percent']:.2f}%\n"
    )

    send_email(service, subject, body)


# -------------------------------------------------------------------
# One check
# -------------------------------------------------------------------

def run_check():
    check_time = datetime.now(timezone.utc)
    print()
    print("=" * 60)
    print(f"GMAIL CHECK: {check_time.strftime('%Y-%m-%d %H:%M:%S UTC')}")
    print("=" * 60)

    try:
        service = get_service()
        results = fetch_current_month_results(service)

        if PRINT_DAILY_RESULTS:
            print_daily_results(results)

        if PRINT_WEEKLY_RESULTS:
            print_weekly_results(results)

        if PRINT_MONTHLY_RESULTS:
            print_monthly_results(results)

        today = datetime.now(timezone.utc).date()

        maybe_send_weekly_email(service, results, today)
        maybe_send_monthly_email(service, results, today)

    except Exception as exc:
        print(f"Check failed: {exc}")


# -------------------------------------------------------------------
# Loop: check every day at 22:22 and 23:37 UTC
# -------------------------------------------------------------------

def main():
    print("MT5 weekly/monthly email monitor started.")
    print("Scheduled checks: " + ", ".join(CHECK_TIMES) + " UTC")

    completed_checks = set()

    while True:
        now = datetime.now(timezone.utc)
        current_date = now.date()

        # Remove older dates so the set remains small.
        completed_checks = {
            item for item in completed_checks
            if item[0] == current_date
        }

        for scheduled_time in CHECK_TIMES:
            hour, minute = map(int, scheduled_time.split(":"))
            scheduled_dt = datetime(
                now.year, now.month, now.day,
                hour, minute, 0,
                tzinfo=timezone.utc,
            )

            check_key = (current_date, scheduled_time)

            if now >= scheduled_dt and check_key not in completed_checks:
                run_check()
                completed_checks.add(check_key)

        time.sleep(5)


if __name__ == "__main__":
    main()