import base64
import re
from email import message_from_bytes
import os
import pickle

from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from google.auth.transport.requests import Request


# ============================================================
# CONFIG
# ============================================================

sent_from = "smashelito@substack.com" # and sent to asg2
parse_how_many_latest_emails = 15
email_body_text_marker = "observe the behavior around"
save_to_file = True
save_file_name = "a_gmail_api_output_overwrites_store_latest_emails.txt"

SCOPES = ['https://www.googleapis.com/auth/gmail.readonly']


# ============================================================
# AUTH
# ============================================================

def get_service():
    creds = None

    if os.path.exists('token.pickle'):
        with open('token.pickle', 'rb') as f:
            creds = pickle.load(f)

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
                'credentials.json', SCOPES)
            creds = flow.run_local_server(
                port=0,
                prompt='consent'   # 🔑 ensures new refresh token
            )

        with open('token.pickle', 'wb') as f:
            pickle.dump(creds, f)

    return build('gmail', 'v1', credentials=creds)

# ============================================================
# HELPERS
# ============================================================

def extract_text(email_msg):
    if email_msg.is_multipart():
        for part in email_msg.walk():
            if part.get_content_type() == "text/plain":
                return part.get_payload(decode=True).decode(errors="ignore")
    else:
        return email_msg.get_payload(decode=True).decode(errors="ignore")
    return ""


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


def _collect_would_target_lines(lines, max_lines=2):
    target_lines = []
    for line in lines:
        if "would target" not in line.lower():
            continue
        stripped = line.strip()
        if stripped:
            target_lines.append(stripped)
        if len(target_lines) >= max_lines:
            break
    return target_lines


def extract_block(body_text, subject_line):
    if not _subject_is_plan_email(subject_line):
        return None

    lines = body_text.splitlines()
    scoped = _lines_after_levels_of_interest(lines)

    target_lines = _collect_would_target_lines(scoped)
    if target_lines:
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
        target_lines = _collect_would_target_lines(remaining)
        if target_lines:
            return "\n".join([subject_line] + target_lines)
        if remaining:
            return "\n".join([subject_line] + remaining[:2])

    # Last resort: scan whole body
    target_lines = _collect_would_target_lines(lines)
    if target_lines:
        return "\n".join([subject_line] + target_lines)

    return None


# ============================================================
# MAIN
# ============================================================

def main():
    service = get_service()

    query = f"from:{sent_from}"

    results = service.users().messages().list(
        userId='me',
        q=query,
        maxResults=parse_how_many_latest_emails
    ).execute()

    messages = results.get('messages', [])

    if not messages:
        print("No messages found.")
        return

    email_data = []

    # ========================================================
    # STEP 1: FETCH ALL EMAILS FIRST (no ordering logic yet)
    # ========================================================
    for msg in messages:
        msg_data = service.users().messages().get(
            userId='me',
            id=msg['id'],
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
            result = f"{subject}\nMarker not found"
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
    # STEP 3: OUTPUT
    # ========================================================
    output = []

    for item in email_data:
        print("\n" + item["content"] + "\n")  # always print
        output.append(item["content"])

    if save_to_file:
        with open(save_file_name, "w", encoding="utf-8") as f:
            f.write("\n\n".join(output))

        print(f"\nSaved to {save_file_name}")


if __name__ == "__main__":
    main()