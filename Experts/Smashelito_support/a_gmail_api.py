import base64
from email import message_from_bytes
import os
import pickle

from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from google.auth.transport.requests import Request


# ============================================================
# CONFIG
# ============================================================

sent_from = "smashelito@substack.com"
parse_how_many_latest_emails = 2
email_body_text_marker = "observe the behavior around"
save_to_file = True
save_file_name = "a_gmail_api_output_overwrites.txt"

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
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(
                'credentials.json', SCOPES)
            creds = flow.run_local_server(port=0)

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


def extract_block(body_text, subject_line):
    lines = body_text.splitlines()

    start_idx = None
    for i, line in enumerate(lines):
        if email_body_text_marker in line:
            start_idx = i
            break

    if start_idx is None:
        return None

    remaining = lines[start_idx + 1:]
    remaining = [l for l in remaining if l.strip()]
    content_lines = remaining[:2]

    return "\n".join([subject_line] + content_lines)


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
        else:
            result = f"{subject}\nMarker not found"

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