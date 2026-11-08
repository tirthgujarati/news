#!/usr/bin/env python3
"""Delete editions older than the repo keeps, then rebuild data/index.json.

The repo is only a drop box: the phone keeps the full archive. The repo keeps
the last KEEP_DAYS days so a phone that wasn't opened for a while can catch up.

Usage:
    python tools/prune.py                 # keep the last 7 days (IST)
    python tools/prune.py --days 7 --today 2026-11-02
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
EDITIONS = DATA / "editions"
FLASH = DATA / "flash"
KEEP_DAYS = 7
IST = dt.timezone(dt.timedelta(hours=5, minutes=30))
SLOT_ORDER = {"weekend": 0, "morning": 1, "midday": 2, "evening": 3}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=KEEP_DAYS)
    ap.add_argument("--today", help="YYYY-MM-DD in IST (default: now)")
    args = ap.parse_args()

    now = dt.datetime.now(IST)
    today = dt.date.fromisoformat(args.today) if args.today else now.date()
    cutoff = today - dt.timedelta(days=args.days)

    kept = []
    for path in sorted(EDITIONS.rglob("*.json")):
        with path.open(encoding="utf-8") as f:
            ed = json.load(f)
        if dt.date.fromisoformat(ed["date"]) < cutoff:
            path.unlink()
            print(f"deleted {path.relative_to(ROOT).as_posix()}")
            continue
        kept.append((path, ed))

    # Flash desk results: same 7 days, by when they were checked.
    for path in sorted(FLASH.glob("*.json")) if FLASH.is_dir() else []:
        with path.open(encoding="utf-8") as f:
            checked = dt.datetime.fromisoformat(json.load(f)["checked_at"])
        if checked.astimezone(IST).date() < cutoff:
            path.unlink()
            print(f"deleted {path.relative_to(ROOT).as_posix()}")

    # Remove month/year folders left empty.
    for d in sorted(EDITIONS.rglob("*"), key=lambda p: len(p.parts), reverse=True):
        if d.is_dir() and not any(d.iterdir()):
            d.rmdir()

    kept.sort(key=lambda pe: (pe[1]["date"], SLOT_ORDER[pe[1]["slot"]]), reverse=True)
    index = {
        "updated_at": now.replace(microsecond=0).isoformat(),
        "editions": [
            {
                "edition_id": ed["edition_id"],
                "title": ed["title"],
                "path": path.relative_to(DATA).as_posix(),
                "story_count": sum(len(s["stories"]) for s in ed["sections"]),
            }
            for path, ed in kept
        ],
    }
    with (DATA / "index.json").open("w", encoding="utf-8", newline="\n") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"index.json: {len(kept)} edition(s), keeping from {cutoff.isoformat()}")


if __name__ == "__main__":
    main()
