"""Sends push notifications to the apex app through Firebase Cloud Messaging.

Run by .github/workflows/notify.yml with the files a push added:
  python tools/notify.py data/editions/2026/11/03-midday.json data/flash/7.json

- A new edition -> topic "editions": "Midday Edition is ready".
- A new flash desk result -> topic "flash": tells the phone's Flash engine to
  read the Opus answer now (the phone shows it; no text is sent).

Needs the FCM_SERVICE_ACCOUNT secret (a Firebase service account key, JSON).
Without it this does nothing, so the repo works before Firebase is set up.
"""

import json
import os
import re
import sys

SCOPE = "https://www.googleapis.com/auth/firebase.messaging"


def edition_message(path):
    with open(path, encoding="utf-8") as f:
        e = json.load(f)
    stories = [s for sec in e.get("sections", []) for s in sec.get("stories", [])]
    if not stories:
        return None
    lead = next((s for s in stories if s.get("lead")), stories[0])
    n = len(stories)
    return {
        "topic": "editions",
        "data": {
            "type": "edition",
            "title": f"{e.get('title', 'New edition')} is ready",
            "text": f"{n} {'story' if n == 1 else 'stories'} · {lead.get('headline', '')}",
        },
        "android": {"priority": "high", "ttl": "21600s"},
    }


def flash_message(path):
    issue = re.search(r"(\d+)\.json$", path)
    if not issue:
        return None
    return {
        "topic": "flash",
        "data": {"type": "flash", "issue": issue.group(1)},
        "android": {"priority": "high", "ttl": "900s"},
    }


def messages(paths):
    out = []
    for p in paths:
        p = p.replace("\\", "/")
        if p.startswith("data/editions/") and p.endswith(".json"):
            m = edition_message(p)
        elif re.fullmatch(r"data/flash/\d+\.json", p):
            m = flash_message(p)
        else:
            m = None
        if m:
            out.append(m)
    return out


def main(paths):
    msgs = messages(paths)
    if not msgs:
        print("Nothing to send.")
        return 0
    key = os.environ.get("FCM_SERVICE_ACCOUNT", "").strip()
    if not key:
        print("No FCM_SERVICE_ACCOUNT secret: skipping push notifications.")
        return 0

    import requests
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    info = json.loads(key)
    creds = service_account.Credentials.from_service_account_info(info, scopes=[SCOPE])
    creds.refresh(Request())
    url = f"https://fcm.googleapis.com/v1/projects/{info['project_id']}/messages:send"
    failed = 0
    for m in msgs:
        r = requests.post(url, json={"message": m}, headers={"Authorization": f"Bearer {creds.token}"}, timeout=20)
        what = m["data"].get("title") or f"flash #{m['data'].get('issue')}"
        if r.ok:
            print(f"Sent: {what}")
        else:
            failed += 1
            print(f"Failed ({r.status_code}): {what}: {r.text[:300]}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
