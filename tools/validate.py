#!/usr/bin/env python3
"""Check editions and index.json before they are committed.

Usage:
    python tools/validate.py              # latest.json, index.json and every edition
    python tools/validate.py FILE [FILE]  # only the given edition files

Exits with status 1 and prints every problem found if anything is invalid.
"""
from __future__ import annotations

import datetime as dt
import json
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator
except ImportError:
    sys.exit("jsonschema is missing: run  pip install -r tools/requirements.txt")

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
SCHEMA_PATH = ROOT / "schema" / "edition.schema.json"

SECTION_ORDER = ["india", "world", "currency", "markets", "built"]
SECTION_TITLES = {
    "india": "India",
    "world": "World",
    "currency": "Currency Desk",
    "markets": "Money & Markets",
    "built": "Built This Week",
}
MAX_STORIES = {"india": 5, "world": 5, "currency": 4, "markets": 5, "built": 5}
IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp")


def load_json(path: Path, errors: list[str]):
    try:
        with path.open(encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        errors.append(f"{path}: file not found")
    except json.JSONDecodeError as e:
        errors.append(f"{path}: not valid JSON ({e})")
    return None


def schema_errors(validator: Draft202012Validator, doc, label: str) -> list[str]:
    out = []
    for err in sorted(validator.iter_errors(doc), key=lambda e: list(e.absolute_path)):
        where = "/".join(str(p) for p in err.absolute_path) or "(root)"
        out.append(f"{label}: {where}: {err.message}")
    return out


def rule_errors(ed: dict, label: str) -> list[str]:
    """Rules JSON Schema can't express."""
    out = []

    def bad(msg: str):
        out.append(f"{label}: {msg}")

    date = ed.get("date", "")
    slot = ed.get("slot", "")
    if ed.get("edition_id") != f"{date}-{slot}":
        bad(f"edition_id must be '{date}-{slot}'")
    if not ed.get("generated_at", "").startswith(date):
        bad("generated_at must be on the edition's date (IST)")

    try:
        day = dt.date.fromisoformat(date)
    except ValueError:
        bad(f"date '{date}' is not a real date")
        day = None

    # Weekend Special only on Sunday morning.
    if slot == "weekend":
        if day and day.weekday() != 6:
            bad("slot 'weekend' is only for Sunday")
        if ed.get("weekend_special") is None:
            bad("a weekend edition must fill weekend_special")
    elif ed.get("weekend_special") is not None:
        bad("weekend_special must be null except in the weekend slot")
    if day and day.weekday() == 6 and slot == "morning":
        bad("Sunday morning must use slot 'weekend'")

    sections = ed.get("sections", [])
    ids = [s.get("id") for s in sections]
    if ids != SECTION_ORDER:
        bad(f"sections must be {SECTION_ORDER} in that order, got {ids}")

    seen_story_ids = set()
    leads = []
    for sec in sections:
        sid = sec.get("id")
        if sid in SECTION_TITLES and sec.get("title") != SECTION_TITLES[sid]:
            bad(f"section '{sid}' must be titled '{SECTION_TITLES[sid]}'")
        stories = sec.get("stories", [])
        if sid in MAX_STORIES and len(stories) > MAX_STORIES[sid]:
            bad(f"section '{sid}' has {len(stories)} stories, max {MAX_STORIES[sid]}")
        importances = [s.get("importance", 0) for s in stories]
        if importances != sorted(importances, reverse=True):
            bad(f"section '{sid}' stories must be sorted by importance, highest first")
        for i, st in enumerate(stories):
            stid = st.get("id", "")
            if not stid.startswith(f"{sid}-"):
                bad(f"story '{stid}' is in section '{sid}' but its id doesn't start with '{sid}-'")
            if stid in seen_story_ids:
                bad(f"story id '{stid}' appears twice")
            seen_story_ids.add(stid)
            if st.get("lead"):
                leads.append(stid)
            if st.get("verified") is False and not st.get("note"):
                bad(f"story '{stid}' is unverified, so it needs a note")
            source_names = {s.get("name") for s in st.get("sources", [])}
            if st.get("verified") is True and len(source_names) < 2:
                bad(f"story '{stid}' is verified, so it needs at least 2 different sources")
            img = st.get("image")
            if img is not None:
                if i != 0 and not st.get("lead"):
                    bad(f"story '{stid}': photos are only allowed on the lead and the first story of a section")
                path = img.get("url", "").split("?")[0].lower()
                if path.endswith(".gif"):
                    bad(f"story '{stid}': animated/GIF images are not allowed")
                elif not path.endswith(IMAGE_EXTENSIONS):
                    # Many CDNs serve photos without an extension; warn only.
                    print(f"note: {label}: story '{stid}' photo url has no jpg/png/webp extension", file=sys.stderr)
    if len(leads) != 1:
        bad(f"exactly one story must have lead=true, found {len(leads)}: {leads}")

    ws = ed.get("weekend_special")
    if ws:
        ranks = [s.get("rank") for s in ws.get("stories", [])]
        if ranks != list(range(1, len(ranks) + 1)):
            bad(f"weekend_special ranks must be 1..{len(ranks)} in order, got {ranks}")
        for st in ws.get("stories", []):
            if st.get("lead"):
                bad("weekend_special stories must have lead=false (the lead lives in sections)")
            if st.get("image") is not None:
                bad("weekend_special stories carry no photo")

    snap_ids = [s.get("id") for s in ed.get("snapshot", [])]
    if len(snap_ids) != len(set(snap_ids)):
        bad("snapshot ids must be unique")

    days = [d.get("date") for d in ed.get("week_ahead", [])]
    if days != sorted(days):
        bad("week_ahead days must be in date order")
    return out


def story_count(ed: dict) -> int:
    return sum(len(s.get("stories", [])) for s in ed.get("sections", []))


def check_edition(validator, path: Path, errors: list[str]):
    ed = load_json(path, errors)
    if ed is None:
        return None
    label = str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)
    errs = schema_errors(validator, ed, label)
    if not errs:  # rule checks assume the shape is right
        errs = rule_errors(ed, label)
    errors.extend(errs)
    return ed


def check_index(errors: list[str], editions: dict[str, dict]):
    index = load_json(DATA / "index.json", errors)
    if index is None:
        return
    if not isinstance(index.get("editions"), list) or "updated_at" not in index:
        errors.append("data/index.json: needs 'updated_at' and an 'editions' list")
        return
    listed = []
    for entry in index["editions"]:
        p = entry.get("path", "")
        listed.append(p)
        ed = editions.get(p)
        if ed is None:
            errors.append(f"data/index.json: lists '{p}' but that file is missing")
            continue
        if entry.get("edition_id") != ed.get("edition_id"):
            errors.append(f"data/index.json: '{p}' has edition_id {ed.get('edition_id')}, index says {entry.get('edition_id')}")
        if entry.get("story_count") != story_count(ed):
            errors.append(f"data/index.json: '{p}' story_count should be {story_count(ed)}")
    for p in editions:
        if p not in listed:
            errors.append(f"data/index.json: '{p}' exists but isn't listed (run tools/prune.py)")
    return index


def main(argv: list[str]) -> int:
    errors: list[str] = []
    schema = load_json(SCHEMA_PATH, errors)
    if schema is None:
        print("\n".join(errors))
        return 1
    validator = Draft202012Validator(schema)

    if argv:
        for f in argv:
            check_edition(validator, Path(f).resolve(), errors)
    else:
        editions = {}
        for p in sorted((DATA / "editions").rglob("*.json")):
            ed = check_edition(validator, p, errors)
            if ed is not None:
                editions[p.relative_to(DATA).as_posix()] = ed
        latest = check_edition(validator, DATA / "latest.json", errors)
        index = check_index(errors, editions)
        if latest is not None and index and index.get("editions"):
            newest = editions.get(index["editions"][0].get("path"))
            if newest is not None and newest != latest:
                errors.append("data/latest.json must be an exact copy of the newest edition in index.json")

    if errors:
        print(f"INVALID ({len(errors)} problem{'s' if len(errors) != 1 else ''}):")
        for e in errors:
            print(f"  - {e}")
        return 1
    print("OK: all checked files are valid")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
