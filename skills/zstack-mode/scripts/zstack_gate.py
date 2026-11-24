#!/usr/bin/env python3
"""Deterministic task gate for zstack-mode.

Tracks task state in .zstack-state.json (gitignored), verifies both independent
code-review and changes-verification receipts match the exact HEAD commit SHA,
and provides hook adapters for Antigravity, Claude Code, and git pre-push.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE_FILENAME = "zstack-state.json"
FALLBACK_STATE_FILE = ".zstack-state.json"
VERIFICATION_RECEIPT = ".changes-verification-receipt.json"
PR_OR_PUSH_RE = re.compile(r"\b(git\s+push|gh\s+pr\s+create)\b")


def state_path(repo: Path) -> Path:
    proc = subprocess.run(
        ["git", "rev-parse", "--git-dir"],
        cwd=repo,
        text=True,
        capture_output=True,
    )
    if proc.returncode == 0 and proc.stdout.strip():
        git_dir = Path(proc.stdout.strip())
        if not git_dir.is_absolute():
            git_dir = (repo / git_dir).resolve()
        return git_dir / STATE_FILENAME
    return repo / FALLBACK_STATE_FILE


def git_head(repo: Path) -> str | None:
    proc = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=repo,
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def load_json(path: Path) -> dict[str, object] | None:
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else None
    except Exception:
        return None


def save_state(repo: Path, state: dict[str, object]) -> None:
    state["updated_at_utc"] = datetime.now(timezone.utc).isoformat()
    target = state_path(repo)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def evaluate_gates(repo: Path) -> tuple[bool, list[str], dict[str, object] | None]:
    state = load_json(state_path(repo))
    if not state:
        return False, ["No active zstack-mode task state. Run `zstack_gate.py start --task \"...\"` first."], None

    head = git_head(repo)
    if not head:
        return False, ["Repository has no valid HEAD commit."], state

    issues: list[str] = []

    review = state.get("code_review")
    if not isinstance(review, dict) or review.get("status") != "pass":
        issues.append("`code-review` gate not passed. Delegate review to an independent subagent and record pass.")
    elif review.get("commit_sha") != head:
        issues.append(
            f"`code-review` receipt is stale ({review.get('commit_sha')} != HEAD {head}). "
            "Re-run `code-review` and record pass on HEAD."
        )

    receipt = load_json(repo / VERIFICATION_RECEIPT)
    if not receipt:
        issues.append(
            f"Missing {VERIFICATION_RECEIPT}. Run `changes-verification` (`verify.py`) on HEAD."
        )
    elif receipt.get("passed") is not True:
        issues.append("`changes-verification` did not pass. Fix failures and re-run `verify.py`.")
    elif receipt.get("commit_sha") != head:
        issues.append(
            f"`changes-verification` receipt is stale ({receipt.get('commit_sha')} != HEAD {head}). "
            "Re-run `changes-verification` on HEAD."
        )

    return len(issues) == 0, issues, state


def cmd_start(repo: Path, task: str, backward_compat: bool) -> int:
    state: dict[str, object] = {
        "task": task.strip(),
        "phase": "implementing",
        "backward_compatible": backward_compat,
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "code_review": None,
    }
    save_state(repo, state)
    compat_label = "yes" if backward_compat else "no (default)"
    print(f"Started zstack-mode task: {task.strip()} (backward_compatible={compat_label})")
    return 0


def cmd_record_review(repo: Path, status: str, summary: str) -> int:
    state = load_json(state_path(repo))
    if not state:
        print("Error: no active zstack-mode task state. Run `start` first.", file=sys.stderr)
        return 1
    head = git_head(repo)
    if not head:
        print("Error: repository has no valid HEAD commit.", file=sys.stderr)
        return 1
    state["code_review"] = {
        "status": status,
        "commit_sha": head,
        "summary": summary.strip(),
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
    }
    if status == "pass":
        state["phase"] = "reviewed"
    save_state(repo, state)
    print(f"Recorded code-review={status} for HEAD {head}")
    return 0


def cmd_check(repo: Path) -> int:
    ok, issues, state = evaluate_gates(repo)
    if not ok:
        for item in issues:
            print(f"BLOCKED: {item}", file=sys.stderr)
        return 1
    assert state is not None
    state["phase"] = "awaiting_pr_approval"
    save_state(repo, state)
    print(f"PASSED: All zstack-mode gates verified for HEAD {git_head(repo)}. Ready to ask user about PR.")
    return 0


def cmd_complete(repo: Path) -> int:
    state = load_json(state_path(repo))
    if state:
        state["phase"] = "awaiting_task"
        save_state(repo, state)
    print("Task closed. zstack-mode phase set to awaiting_task.")
    return 0


def cmd_status(repo: Path) -> int:
    state = load_json(state_path(repo))
    if not state:
        print("No active zstack-mode state.")
        return 0
    print(json.dumps(state, indent=2))
    return 0


def cmd_stop_hook(repo: Path) -> int:
    state = load_json(state_path(repo))
    if not state:
        return 0
    phase = state.get("phase")
    if phase in ("awaiting_task", "awaiting_pr_approval"):
        return 0
    ok, issues, _ = evaluate_gates(repo)
    if ok:
        return 0
    print(
        "zstack-mode Stop gate blocked completion:\n- " + "\n- ".join(issues),
        file=sys.stderr,
    )
    return 2


def cmd_claude_pre_tool(repo: Path) -> int:
    raw = sys.stdin.read().strip()
    command = ""
    if raw:
        try:
            payload = json.loads(raw)
            tool_input = payload.get("tool_input") or {}
            command = str(tool_input.get("command") or "")
        except Exception:
            command = raw
    if command and not PR_OR_PUSH_RE.search(command):
        return 0
    state = load_json(state_path(repo))
    if not state or state.get("phase") == "awaiting_task":
        return 0
    ok, issues, _ = evaluate_gates(repo)
    if ok:
        return 0
    print(
        "zstack-mode blocked git push / PR creation:\n- " + "\n- ".join(issues),
        file=sys.stderr,
    )
    return 2


def cmd_agy_pre_tool(repo: Path) -> int:
    raw = sys.stdin.read().strip()
    command = ""
    cwd = repo
    if raw:
        try:
            payload = json.loads(raw)
            if payload.get("cwd"):
                cwd = Path(str(payload["cwd"]))
            args = (payload.get("toolCall") or {}).get("args") or {}
            command = str(args.get("CommandLine") or "")
        except Exception:
            pass
    if not PR_OR_PUSH_RE.search(command):
        print(json.dumps({"decision": "allow"}))
        return 0
    state = load_json(state_path(cwd))
    if not state or state.get("phase") == "awaiting_task":
        print(json.dumps({"decision": "allow"}))
        return 0
    ok, issues, _ = evaluate_gates(cwd)
    if ok:
        print(json.dumps({"decision": "allow"}))
        return 0
    print(
        json.dumps(
            {
                "decision": "deny",
                "reason": "zstack-mode gate incomplete: " + " | ".join(issues),
            }
        )
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Deterministic zstack-mode gate and hook helper.")
    parser.add_argument("--repo", default=".", help="Repository root path (default: .)")
    sub = parser.add_subparsers(dest="command", required=True)

    start_p = sub.add_parser("start", help="Start a new zstack-mode task")
    start_p.add_argument("--task", required=True, help="Short task description")
    start_p.add_argument(
        "--backward-compat",
        action="store_true",
        help="Set if user explicitly requested backward compatibility (default: false)",
    )

    rev_p = sub.add_parser("record-review", help="Record independent code-review verdict for HEAD")
    rev_p.add_argument("--status", required=True, choices=("pass", "fail"))
    rev_p.add_argument("--summary", default="", help="Brief summary of review outcome")

    sub.add_parser("check", help="Verify code-review and changes-verification gates match HEAD")
    sub.add_parser("complete", help="Mark task done and transition to awaiting_task")
    sub.add_parser("status", help="Print current .zstack-state.json")
    sub.add_parser("stop-hook", help="State-aware Stop hook (exits 2 only when gates are incomplete)")
    sub.add_parser("claude-pre-tool", help="Claude Code PreToolUse hook for Bash")
    sub.add_parser("agy-pre-tool", help="Antigravity PreToolUse hook for run_command")

    args = parser.parse_args()
    repo = Path(args.repo).resolve()

    if args.command == "start":
        return cmd_start(repo, args.task, args.backward_compat)
    if args.command == "record-review":
        return cmd_record_review(repo, args.status, args.summary)
    if args.command == "check":
        return cmd_check(repo)
    if args.command == "complete":
        return cmd_complete(repo)
    if args.command == "status":
        return cmd_status(repo)
    if args.command == "stop-hook":
        return cmd_stop_hook(repo)
    if args.command == "claude-pre-tool":
        return cmd_claude_pre_tool(repo)
    if args.command == "agy-pre-tool":
        return cmd_agy_pre_tool(repo)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
