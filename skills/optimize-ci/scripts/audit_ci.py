#!/usr/bin/env python3
"""Audit the last N GitHub Actions CI runs via `gh` and output a Markdown table
breaking down every job into Waiting, Setup, and Running durations at p50 and p95.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
from collections import defaultdict
from datetime import datetime
from typing import Any

SETUP_STEP_RE = re.compile(
    r"^(set up job|checkout|check out|setup|set up|install|cache|restore|configure|download|prepare)\b",
    re.IGNORECASE,
)
TEARDOWN_STEP_RE = re.compile(r"^(post |complete job)", re.IGNORECASE)


def parse_iso(ts: str | None) -> float | None:
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = math.ceil((pct / 100.0) * len(ordered)) - 1
    idx = max(0, min(idx, len(ordered) - 1))
    return ordered[idx]


def fmt_sec(seconds: float) -> str:
    if seconds < 60:
        return f"{seconds:.1f}s"
    mins = int(seconds // 60)
    rem = seconds % 60
    return f"{mins}m {rem:.1f}s"


def run_gh(args: list[str]) -> Any:
    proc = subprocess.run(["gh", *args], text=True, capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args)} failed:\n{proc.stderr.strip()}")
    return json.loads(proc.stdout)


def detect_repo(explicit_repo: str | None) -> str:
    if explicit_repo:
        return explicit_repo
    data = run_gh(["repo", "view", "--json", "nameWithOwner"])
    return str(data["nameWithOwner"])


def classify_job(job: dict[str, Any]) -> tuple[float, float, float] | None:
    created = parse_iso(job.get("created_at"))
    started = parse_iso(job.get("started_at"))
    completed = parse_iso(job.get("completed_at"))
    if created is None or started is None or completed is None:
        return None

    waiting = max(0.0, started - created)
    setup = 0.0
    running = 0.0

    steps = job.get("steps") or []
    if steps:
        for step in steps:
            name = str(step.get("name") or "")
            s_start = parse_iso(step.get("started_at"))
            s_end = parse_iso(step.get("completed_at"))
            if s_start is None or s_end is None:
                continue
            dur = max(0.0, s_end - s_start)
            if TEARDOWN_STEP_RE.match(name):
                continue
            if SETUP_STEP_RE.match(name):
                setup += dur
            else:
                running += dur
    else:
        running = max(0.0, completed - started)

    return waiting, setup, running


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Audit GitHub Actions job durations (Waiting / Setup / Running at p50 & p95)."
    )
    parser.add_argument("--repo", default=None, help="GitHub repo in owner/name format (default: current repo)")
    parser.add_argument("--limit", type=int, default=150, help="Number of recent completed runs to inspect (default: 150)")
    parser.add_argument("--workflow", default=None, help="Optional workflow filename or ID filter")
    args = parser.parse_args()

    try:
        repo = detect_repo(args.repo)
    except Exception as exc:
        print(f"Error detecting repository via gh CLI: {exc}", file=sys.stderr)
        return 1

    run_list_args = [
        "run",
        "list",
        "--repo",
        repo,
        "--status",
        "completed",
        "--limit",
        str(args.limit),
        "--json",
        "databaseId,workflowName,conclusion,event",
    ]
    if args.workflow:
        run_list_args.extend(["--workflow", args.workflow])

    try:
        runs = run_gh(run_list_args)
    except Exception as exc:
        print(f"Error listing workflow runs: {exc}", file=sys.stderr)
        return 1

    if not runs:
        print(f"No completed CI runs found for {repo}.")
        return 0

    metrics: dict[str, dict[str, list[float]]] = defaultdict(
        lambda: {"waiting": [], "setup": [], "running": [], "total": []}
    )

    for run in runs:
        run_id = run["databaseId"]
        wf_name = run.get("workflowName") or "workflow"
        try:
            payload = run_gh(["api", f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100"])
        except Exception as exc:
            print(f"Warning: skipping run {run_id}: {exc}", file=sys.stderr)
            continue
        for job in payload.get("jobs", []):
            if job.get("status") != "completed":
                continue
            classified = classify_job(job)
            if classified is None:
                continue
            w, s, r = classified
            key = f"{wf_name} / {job.get('name', 'unnamed')}"
            metrics[key]["waiting"].append(w)
            metrics[key]["setup"].append(s)
            metrics[key]["running"].append(r)
            metrics[key]["total"].append(w + s + r)

    if not metrics:
        print(f"No completed jobs found across {len(runs)} runs for {repo}.")
        return 0

    rows = []
    for job_key, buckets in metrics.items():
        rows.append(
            (
                percentile(buckets["total"], 95),
                job_key,
                len(buckets["total"]),
                percentile(buckets["waiting"], 50),
                percentile(buckets["waiting"], 95),
                percentile(buckets["setup"], 50),
                percentile(buckets["setup"], 95),
                percentile(buckets["running"], 50),
                percentile(buckets["running"], 95),
                percentile(buckets["total"], 50),
                percentile(buckets["total"], 95),
            )
        )

    rows.sort(key=lambda item: item[0], reverse=True)

    print(f"### CI Audit ({repo} — last {len(runs)} completed runs)\n")
    print("| Job | Samples | Waiting p50 | Waiting p95 | Setup p50 | Setup p95 | Running p50 | Running p95 | Total p50 | Total p95 |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for _, job_key, n, w50, w95, s50, s95, r50, r95, t50, t95 in rows:
        print(
            f"| {job_key} | {n} | {fmt_sec(w50)} | {fmt_sec(w95)} | "
            f"{fmt_sec(s50)} | {fmt_sec(s95)} | {fmt_sec(r50)} | {fmt_sec(r95)} | "
            f"{fmt_sec(t50)} | {fmt_sec(t95)} |"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
