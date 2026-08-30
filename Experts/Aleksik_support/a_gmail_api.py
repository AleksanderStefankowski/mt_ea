import base64
import html as html_module
import os
import re
import sys
from email import message_from_bytes

from gmail_auth_common import SCRIPT_DIR, get_gmail_service
from gmail_plan_parse_common import (
    collect_compact_would_target_lines,
    is_compact_would_target_line,
    load_trading_dates,
    plan_exception_extract_block,
    require_compact_target_lines,
    validate_plan_extract,
    would_target_direction,
)

# Always read/write next to this script (ruby runner may use another cwd).
os.chdir(SCRIPT_DIR)


# ============================================================
# CONFIG
# ============================================================

sent_from = "smashelito@substack.com" # and sent to asg2
# Date filter: pull on/after this date (YYYY.MM.DD). Set "" to disable.
pull_after_date = "2024.01.01"
# Cap how many latest messages to fetch (Gmail returns newest first). None = no cap, paginate all.
# Example: max_latest_emails = 500  -> one quick pull of the 500 most recent only.
max_latest_emails = 10
email_body_text_marker = "observe the behavior around"
save_to_file = True
save_file_name = os.path.join(
    SCRIPT_DIR, "a_gmail_api_output_overwrites_store_latest_emails.txt"
)

READONLY_SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"]


def get_service():
    return get_gmail_service(READONLY_SCOPES)

# ============================================================
# HELPERS
# ============================================================

def _html_to_plain(html_text):
    text = re.sub(r"(?is)<(script|style).*?>.*?</\1>", "", html_text)
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"(?i)</p>", "\n", text)
    text = re.sub(r"(?i)</div>", "\n", text)
    text = re.sub(r"(?i)</li>", "\n", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = html_module.unescape(text)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return text


def extract_body_text(email_msg):
    plain = ""
    html = ""
    if email_msg.is_multipart():
        for part in email_msg.walk():
            ctype = part.get_content_type()
            payload = part.get_payload(decode=True)
            if not payload:
                continue
            decoded = payload.decode(errors="ignore")
            if ctype == "text/plain" and not plain:
                plain = decoded
            elif ctype == "text/html" and not html:
                html = decoded
    else:
        plain = email_msg.get_payload(decode=True).decode(errors="ignore")

    chunks = []
    if plain:
        chunks.append(plain)
    if html:
        chunks.append(_html_to_plain(html))
    return "\n\n".join(chunks)


def extract_text(email_msg):
    return extract_body_text(email_msg)


def _subject_is_plan_email(subject_line):
    if not subject_line:
        return False
    if re.search(r"\bRecap\b", subject_line, re.I):
        return False
    return bool(re.search(r"\b(Daily|Weekly)\s+Plan\b", subject_line, re.I))


def _lines_after_levels_of_interest(lines):
    for i, line in enumerate(lines):
        if "levels of interest" in line.lower():
            return lines[i + 1 :]
    return lines


def _find_compact_would_target_lines_in_text(text):
    pattern = re.compile(
        r"(?:Holding|Break and hold)\s+.+?(?:above|below)\s+\d+.+?would target\s+"
        r"(?:\d+\*?(?:-\d+\*?)?\s*/\s*)+\d+\*?(?:-\d+\*?)?",
        re.I,
    )
    return [
        match.group(0).strip()
        for match in pattern.finditer(text)
        if is_compact_would_target_line(match.group(0).strip())
    ]


def _collect_would_target_lines(lines, full_text=""):
    candidates = []
    for line in lines:
        stripped = line.strip()
        if stripped:
            candidates.append(stripped)
    for line in _find_compact_would_target_lines_in_text(full_text):
        if line not in candidates:
            candidates.append(line)
    return collect_compact_would_target_lines(candidates)


def _require_compact_target_lines(subject_line, lines, full_text):
    target_lines = _collect_would_target_lines(lines, full_text)
    has_up = any(would_target_direction(line) == "up" for line in target_lines)
    has_down = any(would_target_direction(line) == "down" for line in target_lines)
    if has_up and has_down:
        return target_lines
    scoped = [line.strip() for line in lines if line.strip()]
    return require_compact_target_lines(subject_line, scoped)


def extract_block(body_text, subject_line):
    if not _subject_is_plan_email(subject_line):
        return None

    exception_block = plan_exception_extract_block(subject_line)
    if exception_block:
        return exception_block

    lines = body_text.splitlines()
    scoped = _lines_after_levels_of_interest(lines)

    for candidate_lines in (
        scoped,
        [l.strip() for l in lines if l.strip()],
    ):
        target_lines = _collect_would_target_lines(candidate_lines, body_text)
        has_up = any(would_target_direction(line) == "up" for line in target_lines)
        has_down = any(would_target_direction(line) == "down" for line in target_lines)
        if has_up and has_down:
            return "\n".join([subject_line] + target_lines)

    # Legacy marker fallback (older/newer wording variants)
    marker_variants = (
        email_body_text_marker,
        "observe the behavior at",
        "closely observe the behavior around",
        "will closely observe",
        "will observe",
    )
    start_idx = None
    for i, line in enumerate(lines):
        lower = line.lower()
        if any(marker in lower for marker in marker_variants):
            start_idx = i
            break

    if start_idx is not None:
        remaining = [l.strip() for l in lines[start_idx + 1 :] if l.strip()]
        target_lines = _collect_would_target_lines(remaining, body_text)
        has_up = any(would_target_direction(line) == "up" for line in target_lines)
        has_down = any(would_target_direction(line) == "down" for line in target_lines)
        if has_up and has_down:
            return "\n".join([subject_line] + target_lines)

    require_compact_target_lines(
        subject_line,
        [line.strip() for line in lines if line.strip()],
    )


def _gmail_after_clause(iso_dot_date):
    """Convert YYYY.MM.DD to Gmail search after:YYYY/MM/DD."""
    y, m, d = iso_dot_date.split(".")
    return f"after:{y}/{int(m)}/{int(d)}"


def _build_gmail_query():
    parts = [f"from:{sent_from}"]
    if pull_after_date:
        parts.append(_gmail_after_clause(pull_after_date))
    return " ".join(parts)


def fetch_all_message_ids(service, query, max_ids=None):
    """Paginate Gmail messages.list (500/page). Newest first. Optional max_ids cap."""
    message_ids = []
    page_token = None
    page = 0
    while True:
        page += 1
        page_size = 500
        if max_ids is not None:
            remaining = max_ids - len(message_ids)
            if remaining <= 0:
                break
            page_size = min(500, remaining)
        kwargs = {"userId": "me", "q": query, "maxResults": page_size}
        if page_token:
            kwargs["pageToken"] = page_token
        results = service.users().messages().list(**kwargs).execute()
        batch = results.get("messages", [])
        message_ids.extend(msg["id"] for msg in batch)
        print(f"  page {page}: +{len(batch)} ids (total {len(message_ids)})")
        if max_ids is not None and len(message_ids) >= max_ids:
            message_ids = message_ids[:max_ids]
            break
        page_token = results.get("nextPageToken")
        if not page_token:
            break
    return message_ids


# ============================================================
# MAIN
# ============================================================

def main():
    service = get_service()

    query = _build_gmail_query()
    cap = max_latest_emails if max_latest_emails else None
    print(f"Gmail query: {query}")
    if cap:
        print(f"Max latest messages: {cap}")
    else:
        print("Max latest messages: (no cap, paginate all)")

    message_ids = fetch_all_message_ids(service, query, max_ids=cap)
    print(f"Fetched {len(message_ids)} message id(s)")

    if not message_ids:
        print("No messages found.")
        return

    email_data = []

    # ========================================================
    # STEP 1: FETCH ALL EMAILS FIRST (no ordering logic yet)
    # ========================================================
    for msg_id in message_ids:
        msg_data = service.users().messages().get(
            userId='me',
            id=msg_id,
            format='raw'  # needed for internalDate
        ).execute()

        raw_data = base64.urlsafe_b64decode(
            msg_data['raw'].encode('ASCII')
        )

        email_msg = message_from_bytes(raw_data)

        body = extract_text(email_msg)
        subject = email_msg.get('Subject')

        extracted = extract_block(body, subject)

        if extracted:
            result = extracted
        elif _subject_is_plan_email(subject):
            raise ValueError(f"Plan extract marker not found: {subject!r}")
        else:
            print(f"Skip non-plan email: {subject}")
            continue

        email_data.append({
            "time": int(msg_data.get("internalDate", "0")),
            "content": result
        })

    # ========================================================
    # STEP 2: SORT IN MEMORY (oldest → newest)
    # ========================================================
    email_data.sort(key=lambda x: x["time"])

    # ========================================================
    # STEP 3: VALIDATE THEN OUTPUT (no save if validation fails)
    # ========================================================
    calendar_path = os.path.join(SCRIPT_DIR, "calendar_2026_dots.csv")
    trading = load_trading_dates(calendar_path)

    output = []

    for item in email_data:
        print("\n" + item["content"] + "\n")  # always print
        validate_plan_extract(item["content"], trading)
        output.append(item["content"])

    if save_to_file:
        with open(save_file_name, "w", encoding="utf-8") as f:
            f.write("\n\n".join(output))

        print(f"\nSaved to {save_file_name}")


if __name__ == "__main__":
    try:
        main()
    except ValueError as exc:
        print(f"\nERROR:\n{exc}", file=sys.stderr)
        sys.exit(1)