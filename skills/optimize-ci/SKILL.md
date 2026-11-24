---
name: optimize-ci
description: Audits and optimizes repository CI pipelines to achieve sub-1-minute p50 and sub-2-minute p95 PR check durations without reducing coverage or hiding failures. Manual invocation only — do not auto-invoke unless explicitly requested by the user.
disable-model-invocation: true
---

# Optimize CI

Make the repository's CI as fast as possible without letting it lie.

- **Target:** PR checks complete in **< 1 minute (p50)** and **< 2 minutes (p95)**.
- **Invocation:** Manual-only (`disable-model-invocation: true`). Run only when explicitly invoked by the user.

## Non-Negotiable Rules (Outrank Speed)

1. **Full suite on merge:** Run the full test suite in a merge queue before anything reaches `main`. Test selection only narrows PR feedback.
2. **Never hide failures:** Never add retries, widen timeouts, or skip tests. Treat every flaky check as a bug and fix its root cause.
3. **Never check less:** Lint rules and required checks may only stay the same or grow.

## Phase 1: Audit (Do This First)

Before changing any workflow or toolchain, pull the last 150 CI runs via the GitHub CLI (`gh`). Resolve `<skill-dir>` to the directory containing this `SKILL.md` and run:

```bash
bash <skill-dir>/scripts/audit_ci.sh --limit 150
```

Output a Markdown table breaking down every job into **Waiting**, **Setup**, and **Running** durations at **p50** and **p95**. Always fix the biggest bottleneck bucket first.

## Phase 2: Target Budgets & Architecture

### Waiting (`< 5s`)
- Configure GitHub Actions `concurrency` groups to cancel in-progress branch runs when new commits are pushed.
- Switch to warm self-hosted runners or GitHub larger runners if queue wait times exceed `5s`.

### Setup (`< 15s`)
- Bake the toolchain into the runner image where possible.
- Use blobless clones (`filter: blob:none`).
- Seed PR caches from `main` (target `> 95%` cache hit rate) and cache `node_modules`.

### Pipeline Shape
- Run lint, typecheck, build, and tests in parallel.
- Fold fast checks (lint, format, typecheck) into a single job that reports all failures together.
- Ensure no required job waits on another required job.

### Slowest Job (`< 35s` total)
- **Lint (`< 1s`):** Run via `bun run lint` (reading existing `.oxlintrc.json` with max rules enabled).
- **Format (`< 1s`):** Run via `bun run fmt`.
- **Typecheck (`< 5s`):** Run TypeScript 7 (`tsgo --noEmit`) via `bun run check`.
- **Tests (`< 30s` per shard):** Run `bun test` (keeping existing `vitest` imports). Isolate modules—not processes—reset state between files, and randomize execution order to expose state leaks.

### Tooling Consolidation
- Standardize on `bun` for installs and script execution.
- Remove `npm`, `yarn`, `pnpm`, Prettier, ESLint, Vitest, and Jest (retain only the binary powering `lint`/`fmt`).
- Pin exact canary versions when required for reproducibility.

### Sharding
- Scale CPU cores before adding shards; match worker count to available cores and give each shard an isolated throwaway database.
- Split any test file taking `> 20s`.
- Balance shards using historical file timings recorded on `main`, and verify 100% test-file coverage across all shards.

### PR Test Selection
- Run only tests reachable from the PR diff.
- Explicitly list global inputs (such as lockfiles, CI workflows, and shared config) that trigger a full suite run.
- Verify selection integrity by intentionally hiding a breaking change and confirming CI catches it.

### Test Suite Pruning (Evidence-Based)
- Log every test failure fixed over a 2-week window as either a *caught regression* or a *change detector*.
- Delete pure change-detector tests and ban those patterns in `AGENTS.md`.
- Never delete tests covering authorization, privacy, migrations, or concurrency.

### Local Guardrails (`< 9s`)
- Enforce formatting and linting on `pre-commit` and full CI parity on `pre-push` using `hk` git hooks (not prose instructions in `AGENTS.md`, which agents skip).

### Enforce Budgets (Final PR)
- Once optimization is complete, enforce hard job timeouts matching these budgets so CI fails immediately on speed regressions.

## Migration & Execution Rules

- **Side-by-Side Verification:** Treat the tools above as defaults; keep an existing tool only with measured proof. Before replacing any tool, run old and new side by side and log anything the new tool misses.
- **One Small PR Per Change:** Submit one focused PR per optimization step, including real before/after timing measurements in the PR description.
- **Autonomy First:** Execute every change you can independently. Compile items requiring an account, secret, or spend increase into a single list with estimated monthly costs.
- **Final Report:** Conclude with a before-and-after comparison of total CI duration (p50 and p95) and estimated monthly cost.
