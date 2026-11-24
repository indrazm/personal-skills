#!/usr/bin/env python3
"""Deterministic pre-PR changes verification runner.

Inspects git state, changed files, and CI definitions, runs all specified
test/CI commands, and writes .changes-verification-receipt.json tied to HEAD.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def run_git(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        text=True,
        capture_output=True,
    )


def detect_base_ref(cwd: Path, explicit_base: str | None) -> str | None:
    if explicit_base:
        return explicit_base
    for candidate in ("origin/main", "main", "origin/master", "master"):
        res = run_git(["rev-parse", "--verify", "--quiet", candidate], cwd)
        if res.returncode == 0:
            return candidate
    return None


def extract_ci_info(repo_root: Path) -> tuple[list[str], list[str]]:
    ci_files: list[str] = []
    commands: list[str] = []

    gh_dir = repo_root / ".github" / "workflows"
    if gh_dir.is_dir():
        for wf in sorted(list(gh_dir.glob("*.yml")) + list(gh_dir.glob("*.yaml"))):
            ci_files.append(str(wf.relative_to(repo_root)))
            lines = wf.read_text(encoding="utf-8", errors="replace").splitlines()
            i = 0
            while i < len(lines):
                line = lines[i]
                match = re.match(r"^(\s*)(?:-\s*)?run:\s*(.*)$", line)
                if not match:
                    i += 1
                    continue
                base_indent = len(match.group(1))
                cmd = match.group(2).strip()
                if cmd in ("|", "|-", "|+", ">", ">-", ">+"):
                    block_cmds: list[str] = []
                    i += 1
                    while i < len(lines):
                        nxt = lines[i]
                        if nxt.strip() == "":
                            i += 1
                            continue
                        nxt_indent = len(nxt) - len(nxt.lstrip(" "))
                        if nxt_indent <= base_indent:
                            break
                        stripped = nxt.strip()
                        if stripped and not stripped.startswith("#"):
                            block_cmds.append(stripped)
                        i += 1
                    if block_cmds:
                        commands.append(f"[{wf.name}] {' && '.join(block_cmds)}")
                    continue
                if cmd:
                    commands.append(f"[{wf.name}] {cmd}")
                i += 1

    for rel in (".gitlab-ci.yml", ".circleci/config.yml", "Makefile", "pyproject.toml"):
        path = repo_root / rel
        if path.is_file():
            ci_files.append(rel)

    pkg = repo_root / "package.json"
    if pkg.is_file():
        ci_files.append("package.json")
        try:
            data = json.loads(pkg.read_text(encoding="utf-8"))
            scripts = data.get("scripts", {})
            if isinstance(scripts, dict):
                for key, val in scripts.items():
                    if any(tok in key for tok in ("test", "lint", "type", "check", "build")):
                        commands.append(f"[package.json:{key}] {val}")
        except json.JSONDecodeError:
            pass

    return ci_files, commands


def main() -> int:
    parser = argparse.ArgumentParser(description="Run pre-PR changes verification.")
    parser.add_argument("--repo", default=".", help="Path to git repository root")
    parser.add_argument("--base", default=None, help="Base git ref for diff comparison")
    parser.add_argument("--strict", action="store_true", help="Fail if working tree is dirty")
    parser.add_argument("--discover-only", action="store_true", help="List changed files and CI commands without running checks")
    parser.add_argument("--cmd", action="append", default=[], help="Command to execute and record (repeatable)")
    args = parser.parse_args()

    repo_root = Path(args.repo).resolve()
    head_res = run_git(["rev-parse", "HEAD"], repo_root)
    if head_res.returncode != 0:
        print("Error: not inside a valid git repository with commits.", file=sys.stderr)
        return 1
    head_sha = head_res.stdout.strip()

    status_res = run_git(["status", "--short"], repo_root)
    dirty_files = [
        line
        for line in status_res.stdout.splitlines()
        if line.strip() and line.strip() != "?? .changes-verification-receipt.json"
    ]

    base_ref = detect_base_ref(repo_root, args.base)
    if base_ref:
        diff_res = run_git(["diff", "--name-only", f"{base_ref}...HEAD"], repo_root)
        changed_files = [line for line in diff_res.stdout.splitlines() if line.strip()]
    else:
        diff_res = run_git(["diff", "--name-only", "HEAD~1..HEAD"], repo_root)
        if diff_res.returncode == 0:
            changed_files = [line for line in diff_res.stdout.splitlines() if line.strip()]
        else:
            tree_res = run_git(["diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD"], repo_root)
            changed_files = [line for line in tree_res.stdout.splitlines() if line.strip()]

    ci_files, ci_commands = extract_ci_info(repo_root)

    print(f"HEAD SHA: {head_sha}")
    print(f"Base Ref: {base_ref or 'N/A'}")
    print(f"Dirty Working Tree Items: {len(dirty_files)}")
    print(f"Changed Files ({len(changed_files)}):")
    for f in changed_files:
        print(f"  - {f}")
    print(f"CI Files Found ({len(ci_files)}): {', '.join(ci_files) if ci_files else 'None'}")
    if ci_commands:
        print("Extracted CI / Script Commands:")
        for c in ci_commands:
            print(f"  - {c}")

    if args.discover_only:
        return 0

    if args.strict and dirty_files:
        print("Error: --strict enabled and working tree has uncommitted changes.", file=sys.stderr)
        return 1

    if not args.cmd:
        print("Error: at least one --cmd check must be provided.", file=sys.stderr)
        return 1

    executed_checks: list[dict[str, object]] = []
    all_passed = True

    for command in args.cmd:
        print(f"\n>>> Running: {command}")
        proc = subprocess.run(command, cwd=repo_root, shell=True)
        passed = proc.returncode == 0
        executed_checks.append(
            {
                "command": command,
                "exit_code": proc.returncode,
                "passed": passed,
            }
        )
        if not passed:
            all_passed = False
            print(f"<<< FAILED (exit {proc.returncode}): {command}", file=sys.stderr)
        else:
            print(f"<<< PASSED: {command}")

    receipt = {
        "commit_sha": head_sha,
        "base_ref": base_ref,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "dirty_tree": bool(dirty_files),
        "changed_files": changed_files,
        "ci_files_found": ci_files,
        "executed_checks": executed_checks,
        "passed": all_passed,
    }
    receipt_path = repo_root / ".changes-verification-receipt.json"
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"\nWrote receipt: {receipt_path} (passed={all_passed})")

    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
