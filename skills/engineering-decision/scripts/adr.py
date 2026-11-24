#!/usr/bin/env python3
"""Deterministic helper for listing and scaffolding numbered ADRs in docs/decision/."""

from __future__ import annotations

import argparse
import re
import sys
from datetime import date
from pathlib import Path

ADR_FILE_RE = re.compile(r"^(\d{4})-(.+)\.md$")
STATUS_RE = re.compile(r"^\s*-\s*\*\*Status:\*\*\s*(.+?)\s*$", re.MULTILINE)
TITLE_RE = re.compile(r"^#\s*(?:\d{4}:\s*)?(.+?)\s*$", re.MULTILINE)
VALID_STATUSES = ("Proposed", "Accepted", "Superseded", "Deprecated", "Canceled")


def slugify(title: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    slug = re.sub(r"-{2,}", "-", slug)
    return slug


def scan_adrs(decision_dir: Path) -> list[dict[str, str | int]]:
    records: list[dict[str, str | int]] = []
    if not decision_dir.is_dir():
        return records
    for path in sorted(decision_dir.iterdir()):
        if not path.is_file():
            continue
        match = ADR_FILE_RE.match(path.name)
        if not match:
            continue
        num = int(match.group(1))
        text = path.read_text(encoding="utf-8", errors="replace")
        status_match = STATUS_RE.search(text)
        title_match = TITLE_RE.search(text)
        records.append(
            {
                "number": num,
                "code": match.group(1),
                "filename": path.name,
                "status": status_match.group(1) if status_match else "Unknown",
                "title": title_match.group(1) if title_match else match.group(2),
            }
        )
    return sorted(records, key=lambda r: int(r["number"]))


def cmd_list(decision_dir: Path) -> int:
    records = scan_adrs(decision_dir)
    if not records:
        print(f"No decision records found in {decision_dir}. Next number: 0001")
        return 0
    for rec in records:
        print(f"{rec['code']} | {rec['status']:<10} | {rec['title']} ({rec['filename']})")
    next_num = int(records[-1]["number"]) + 1
    print(f"\nTotal: {len(records)} | Next number: {next_num:04d}")
    return 0


def cmd_new(decision_dir: Path, title: str, status: str, supersedes: str | None) -> int:
    slug = slugify(title)
    if not slug:
        print("Error: title must produce a non-empty kebab-case slug.", file=sys.stderr)
        return 1

    records = scan_adrs(decision_dir)
    next_num = (int(records[-1]["number"]) + 1) if records else 1
    code = f"{next_num:04d}"

    decision_dir.mkdir(parents=True, exist_ok=True)
    target = decision_dir / f"{code}-{slug}.md"
    if target.exists():
        print(f"Error: file already exists: {target}", file=sys.stderr)
        return 1

    supersedes_val = supersedes if supersedes else "None"
    content = (
        f"# {code}: {title.strip()}\n\n"
        f"- **Date:** {date.today().isoformat()}\n"
        f"- **Status:** {status}\n"
        f"- **Supersedes:** {supersedes_val}\n"
        f"- **Superseded by:** None\n"
        f"- **Related:** None\n\n"
        f"## Context\n\n"
        f"Describe the problem, technical constraints, and relevant prior decisions.\n\n"
        f"## Decision\n\n"
        f"State the chosen approach clearly and explain why it was selected.\n\n"
        f"## Alternatives Considered\n\n"
        f"- **Option A:** Brief summary and why it was not chosen.\n"
        f"- **Option B:** Brief summary and why it was not chosen.\n\n"
        f"## Consequences\n\n"
        f"- **Positive:** Expected benefits and improvements.\n"
        f"- **Negative / Trade-offs:** Costs, complexity, or follow-up work required.\n"
    )
    target.write_text(content, encoding="utf-8")
    print(f"Created {target}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Manage numbered ADR files in docs/decision/.")
    parser.add_argument(
        "--dir",
        default="docs/decision",
        help="Path to the decision directory (default: docs/decision)",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="List existing ADRs, statuses, and the next sequence number")

    new_p = sub.add_parser("new", help="Create the next sequential ADR file from the template")
    new_p.add_argument("title", help="Meaningful decision title")
    new_p.add_argument(
        "--status",
        default="Accepted",
        choices=VALID_STATUSES,
        help="Initial decision status (default: Accepted)",
    )
    new_p.add_argument(
        "--supersedes",
        default=None,
        help="Optional Markdown link to a superseded decision",
    )

    args = parser.parse_args()
    decision_dir = Path(args.dir)

    if args.command == "list":
        return cmd_list(decision_dir)
    if args.command == "new":
        return cmd_new(decision_dir, args.title, args.status, args.supersedes)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
