#!/usr/bin/env python3
"""Check flash desk results (data/flash/<issue>.json) before they are committed.

Usage:
    python tools/validate_flash.py FILE [FILE ...]

Exits with status 1 and prints every problem found if anything is invalid.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator, FormatChecker
except ImportError:
    sys.exit("jsonschema is missing: run  pip install -r tools/requirements.txt")

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "schema" / "flash.schema.json"
EDITION_SCHEMA = ROOT / "schema" / "edition.schema.json"


def validator() -> Draft202012Validator:
    flash = json.loads(SCHEMA.read_text(encoding="utf-8"))
    edition = json.loads(EDITION_SCHEMA.read_text(encoding="utf-8"))
    # Pull the shared impact tag definition in, so no remote lookup is needed.
    flash["$defs"] = {"impact": edition["$defs"]["impact"]}
    flash["properties"]["impact"]["items"] = {"$ref": "#/$defs/impact"}
    return Draft202012Validator(flash, format_checker=FormatChecker())


def check(path: Path, v: Draft202012Validator) -> list[str]:
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        return [f"{path}: can't read JSON ({e})"]
    out = []
    for err in sorted(v.iter_errors(doc), key=lambda e: list(e.absolute_path)):
        where = "/".join(str(p) for p in err.absolute_path) or "(root)"
        out.append(f"{path}: {where}: {err.message}")
    if not out:
        if path.stem != str(doc["issue"]):
            out.append(f"{path}: file name must be the issue number ({doc['issue']}.json)")
        targets = [(t["on"], t.get("detail")) for t in doc["impact"]]
        if len(targets) != len(set(targets)):
            out.append(f"{path}: impact: the same target appears twice")
        if doc["confirmed"] and not doc["sources"]:
            out.append(f"{path}: confirmed=true needs at least one source")
    return out


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    v = validator()
    errors = [e for p in argv for e in check(Path(p), v)]
    for e in errors:
        print(e)
    print("OK" if not errors else f"{len(errors)} problem(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
