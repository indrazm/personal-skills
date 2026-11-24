---
name: changes-verification
description: Enforces deterministic pre-PR verification by discovering changed files and CI workflows, running change-related tests and locally runnable CI checks via scripts/verify.sh, and writing a commit-bound verification receipt. Use before creating a pull request, after completing an implementation or fix, or when verifying that a branch is ready to ship.
---

# Changes Verification

Execute deterministic pre-merge verification backed by `scripts/verify.sh` and an optional git `pre-push` hook so every check is backed by observed command execution tied to the exact `HEAD` commit SHA.

## When to Use

- Before creating or updating a pull request (mandatory gate for `create-pr`)
- After completing a feature, refactor, or bug fix
- When asked to verify that a branch is ready for review or CI

## Mandatory Enforcement Flow

Do NOT eyeball code or skip running commands. Always execute `scripts/verify.sh` against the target repository so every check is run and recorded in `.changes-verification-receipt.json` for the exact `HEAD` commit SHA. Resolve `<skill-dir>` to the directory containing this `SKILL.md`.

### Step 1: Discover Changed Files and CI Checks

Run discovery mode first to inspect git state, changed files, and CI workflow commands:

```bash
bash <skill-dir>/scripts/verify.sh --discover-only
```

Review the output to identify:

- Whether the working tree is clean (`git status --short`).
- Every file changed relative to the base branch.
- Every CI definition (`.github/workflows/*.yml`, `.gitlab-ci.yml`, `.circleci/config.yml`, `Makefile`, `package.json`, `pyproject.toml`) and the exact commands CI will execute.

### Step 2: Execute Tests and CI-Mirrored Checks

Run `scripts/verify.sh` with every test command covering the change AND every locally runnable CI command (tests, linter, type-checker, build) using repeatable `--cmd` flags:

```bash
bash <skill-dir>/scripts/verify.sh \
  --strict \
  --cmd "<change-related test command>" \
  --cmd "<ci lint or typecheck command>" \
  --cmd "<ci test or build command>"
```

- Every `--cmd` must exit `0`. If any command fails, `verify.sh` exits `1` and writes `"passed": false`.
- Fix failures, commit the fix, and re-run `verify.sh` so `.changes-verification-receipt.json` matches the new `HEAD` SHA.

### Step 3: Optional Git Pre-Push Hook

When hard push enforcement is requested, install `scripts/pre-push-hook.sh` into `.git/hooks/pre-push`:

```bash
cp <skill-dir>/scripts/pre-push-hook.sh .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

### Step 4: Report Verification Evidence

Report the verified receipt details in your final response and PR body:

- Verified `HEAD` commit SHA
- Base ref and changed file count
- Exact commands executed and their exit codes
- Any CI-only jobs that require remote execution

## Red Flags

- Skipping `scripts/verify.sh` and claiming "tests pass" from memory
- Running `verify.sh` before the final commit (producing a stale receipt SHA)
- Omitting locally runnable CI lint, type-check, or build commands from `--cmd`
- Bypassing `.git/hooks/pre-push` with `--no-verify`

## Gotchas

- Amending or adding commits after running `verify.sh` changes `HEAD` and invalidates the receipt; always re-run `verify.sh` on the final commit.
- Never commit `.changes-verification-receipt.json`; keep it ignored via `.gitignore` or remove it after verification if required.
