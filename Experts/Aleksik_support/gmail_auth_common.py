"""Shared Gmail OAuth for Aleksik_support scripts.

One token.pickle in this folder, with all scopes used by any script, so
refresh tokens are not lost when different scripts run in different order.

Normal runs: load token.pickle → silent refresh when access token expired → no browser.
Browser opens only when token.pickle is missing, scopes changed, or refresh token is gone.
"""
from __future__ import annotations

import os
import pickle
from typing import Iterable, List, Optional

from google.auth.exceptions import RefreshError
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TOKEN_FILE = os.path.join(SCRIPT_DIR, "token.pickle")
CREDENTIALS_FILE = os.path.join(SCRIPT_DIR, "credentials.json")

# Union of every Gmail scope used in this folder — request all on (re)auth once.
ALL_GMAIL_SCOPES: List[str] = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/gmail.modify",
]


def _scopes_satisfied(creds, required_scopes: Iterable[str]) -> bool:
    granted = set(creds.scopes or [])
    return all(scope in granted for scope in required_scopes)


def _print_no_refresh_token_help() -> None:
    print()
    print("ERROR: Google did not return a refresh token.")
    print("Without it you must re-authenticate in the browser every ~hour.")
    print()
    print("Fix (do all steps):")
    print("  1. Google Cloud Console → APIs & Services → Credentials")
    print("     OAuth client type must be 'Desktop app' (NOT 'Web application').")
    print("  2. OAuth consent screen → Publishing status 'In production' (you have this).")
    print("  3. Revoke old access: https://myaccount.google.com/permissions")
    print(f"  4. Delete: {TOKEN_FILE}")
    print("  5. Re-run this script — consent screen must appear; click Allow.")
    print()
    print("Notes:")
    print("  • access_type=offline + prompt=consent is required for the first refresh token.")
    print("  • Test mode expires refresh tokens after 7 days; production does not.")
    print("  • Re-auth too often usually means token.pickle was never saved (wrong cwd)")
    print("    or the pickle has no refresh_token field.")


def _save_token(creds) -> None:
    with open(TOKEN_FILE, "wb") as handle:
        pickle.dump(creds, handle)


def _run_browser_flow(request_scopes: List[str], *, force_consent: bool):
    flow = InstalledAppFlow.from_client_secrets_file(
        CREDENTIALS_FILE,
        request_scopes,
    )
    kwargs = {
        "port": 0,
        "access_type": "offline",  # required for refresh_token
    }
    if force_consent:
        kwargs["prompt"] = "consent"
    return flow.run_local_server(**kwargs)


def _browser_authenticate(request_scopes: List[str], *, had_token_file: bool):
    if not os.path.isfile(CREDENTIALS_FILE):
        raise FileNotFoundError(
            f"Missing {CREDENTIALS_FILE} — download OAuth Desktop credentials "
            "from Google Cloud Console into Aleksik_support/"
        )

    print("Opening browser for Gmail authorization...")
    creds = _run_browser_flow(request_scopes, force_consent=not had_token_file)

    if not creds.refresh_token:
        # Re-auth after revocation: consent screen may be needed to issue a new refresh token.
        creds = _run_browser_flow(request_scopes, force_consent=True)

    if not creds.refresh_token:
        _print_no_refresh_token_help()
        raise SystemExit(1)

    _save_token(creds)
    print(f"Saved token (refresh_token present) → {TOKEN_FILE}")
    return creds


def get_gmail_service(required_scopes: Optional[Iterable[str]] = None):
    """Return an authorized Gmail API service. Refreshes access token automatically."""
    required = list(required_scopes or ALL_GMAIL_SCOPES)
    request_scopes = list(dict.fromkeys([*ALL_GMAIL_SCOPES, *required]))
    had_token_file = os.path.exists(TOKEN_FILE)

    creds = None
    if had_token_file:
        with open(TOKEN_FILE, "rb") as handle:
            creds = pickle.load(handle)

    if creds and not _scopes_satisfied(creds, request_scopes):
        missing = [s for s in request_scopes if s not in set(creds.scopes or [])]
        print(f"token.pickle missing scopes: {missing}")
        print("Re-authenticating with full scope set...")
        creds = None

    if creds and creds.valid:
        return build("gmail", "v1", credentials=creds)

    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
            _save_token(creds)
            return build("gmail", "v1", credentials=creds)
        except RefreshError:
            print("Refresh token expired or revoked. Re-authenticating...")
            creds = None

    creds = _browser_authenticate(request_scopes, had_token_file=had_token_file)
    return build("gmail", "v1", credentials=creds)
