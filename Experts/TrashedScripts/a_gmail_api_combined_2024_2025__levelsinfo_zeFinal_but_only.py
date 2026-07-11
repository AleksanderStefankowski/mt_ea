"""
Combined pipeline (steps 1–3 from a_gmail_api_run_all.rb):
  1. Pull smashelito@substack.com emails from 2024-01-01 through 2025-12-31
  2. Parse all emails into level records
  3. Process stacked/duplicates and write one CSV

Output: levelsinfo_zeFinal_but_only_2024_2025.csv (does not overwrite levelsinfo_zeFinal.csv)
"""

import argparse
import base64
import os
import sys
from email import message_from_bytes

# ============================================================
# CONFIG
# ============================================================

SENT_FROM = "smashelito@substack.com"
EMAIL_BODY_TEXT_MARKER = "observe the behavior around"

# Gmail query dates (inclusive start, exclusive end)
GMAIL_AFTER = "2024/01/01"
GMAIL_BEFORE = "2026/01/01"

OUTPUT_CSV_NAME = "levelsinfo_zeFinal_but_only_2024_2025.csv"
EMAILS_CACHE_NAME = "a_gmail_api_combined_2024_2025_emails_cache.txt"

# ============================================================
# Import helpers from existing step scripts (same directory)
# ============================================================

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import a_gmail_api as gmail_step1
import a_gmail_api2step_parse_append_to_ALLRAW as parse_step2
import a_gmail_api3step_processDuplicates__saveAs_zeFinal2 as finalize_step3


def gmail_query():
    return f"from:{SENT_FROM} after:{GMAIL_AFTER} before:{GMAIL_BEFORE}"


def list_all_message_ids(service, query):
    """Paginate through Gmail list API (500 per page)."""
    message_ids = []
    page_token = None

    while True:
        kwargs = {
            "userId": "me",
            "q": query,
            "maxResults": 500,
        }
        if page_token:
            kwargs["pageToken"] = page_token

        results = service.users().messages().list(**kwargs).execute()
        batch = results.get("messages", [])
        if batch:
            message_ids.extend(msg["id"] for msg in batch)

        page_token = results.get("nextPageToken")
        if not page_token:
            break

    return message_ids


def fetch_and_extract_emails(service, query):
    """Fetch every message in query, extract plan block, return oldest→newest."""
    ids = list_all_message_ids(service, query)
    print(f"Gmail messages matching query: {len(ids)}")

    email_data = []
    for idx, msg_id in enumerate(ids, start=1):
        msg_data = service.users().messages().get(
            userId="me",
            id=msg_id,
            format="raw",
        ).execute()

        raw_data = base64.urlsafe_b64decode(msg_data["raw"].encode("ASCII"))
        email_msg = message_from_bytes(raw_data)
        body = gmail_step1.extract_text(email_msg)
        subject = email_msg.get("Subject")

        extracted = gmail_step1.extract_block(body, subject)
        if extracted:
            content = extracted
        else:
            content = f"{subject}\nMarker not found"

        email_data.append({
            "time": int(msg_data.get("internalDate", "0")),
            "content": content,
        })

        if idx % 50 == 0 or idx == len(ids):
            print(f"  fetched {idx}/{len(ids)}")

    email_data.sort(key=lambda x: x["time"])
    return email_data


def save_email_cache(email_data, path):
    blocks = [item["content"] for item in email_data]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n\n".join(blocks))
    print(f"Saved email cache: {path} ({len(blocks)} emails)")


def parse_all_emails(email_text, calendar_path):
    trading = parse_step2.load_trading_dates(calendar_path)
    levels = parse_step2.parse_plan(email_text, trading)
    return parse_step2.normalize_level_list(levels)


def finalize_levels(levels, out_path):
    finalize_step3.ensure_daily_weekdays(levels)
    week_prices = finalize_step3.build_weekly_prices_by_week(levels)
    finalize_step3.process_duplicates(levels, week_prices)

    written, skipped_daily_stacked = finalize_step3.write_csv(levels, out_path)
    finalize_step3.remove_identical_duplicate_lines(out_path)

    cats_strs = ["_".join(lev["categories"]) for lev in levels]
    n_daily_stacked = sum(1 for s in cats_strs if "daily" in s and "stacked" in s)
    n_weekly_stacked = sum(1 for s in cats_strs if "weekly" in s and "stacked" in s)

    print(f"Wrote {out_path}")
    print(f"Total parsed levels: {len(levels)}")
    print(f"CSV rows written: {written}")
    print(f"Daily levels containing 'stacked' (skipped in CSV): {n_daily_stacked}")
    print(f"Weekly levels containing 'stacked': {n_weekly_stacked}")
    print(f"Levels not written (daily and stacked): {skipped_daily_stacked}")


def load_email_cache(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    blocks = [b for b in text.split("\n\n") if b.strip()]
    print(f"Loaded email cache: {path} ({len(blocks)} emails)")
    return blocks


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--from-cache",
        action="store_true",
        help="Skip Gmail fetch; parse existing email cache file",
    )
    args = parser.parse_args()

    query = gmail_query()
    print("Gmail query:", query)

    calendar_path = os.path.join(SCRIPT_DIR, "calendar_2026_dots.csv")
    if not os.path.exists(calendar_path):
        print(f"ERROR: calendar not found: {calendar_path}")
        sys.exit(1)

    out_path = os.path.join(SCRIPT_DIR, OUTPUT_CSV_NAME)
    cache_path = os.path.join(SCRIPT_DIR, EMAILS_CACHE_NAME)

    if args.from_cache:
        if not os.path.exists(cache_path):
            print(f"ERROR: cache not found: {cache_path}")
            sys.exit(1)
        combined_text = "\n\n".join(load_email_cache(cache_path))
    else:
        service = gmail_step1.get_service()
        email_data = fetch_and_extract_emails(service, query)

        if not email_data:
            print("No emails found in range.")
            sys.exit(1)

        save_email_cache(email_data, cache_path)
        combined_text = "\n\n".join(item["content"] for item in email_data)

    levels = parse_all_emails(combined_text, calendar_path)

    if not levels:
        print("No levels parsed from emails.")
        sys.exit(1)

    finalize_levels(levels, out_path)

    print()
    print("Done. Copy to MT5 Common/Files if needed:")
    print(r"  C:\Users\Aleks\AppData\Roaming\MetaQuotes\Terminal\Common\Files")
    print(f"  as {OUTPUT_CSV_NAME}")


if __name__ == "__main__":
    main()
