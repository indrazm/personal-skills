---
name: create-pr
description: Creates pull requests after enforcing a mandatory changes-verification gate, verifying branch hygiene and diff size, and writing evidence-backed PR descriptions. Use when asked to create a PR, open a pull request, push a branch for review, or prepare changes for merge.
---

# Create PR

Execute a structured pull request workflow gated by `changes-verification`. Never open a PR without observed test execution and locally mirrored CI checks recorded for the final commit.

## When to Use

- When asked to create, open, or draft a pull request
- When preparing a feature, bug fix, or refactor branch for review and merge

## Mandatory Pre-PR Gate

Do NOT push or create a pull request until `changes-verification` passes on the final commit:

1. Run the `changes-verification` skill on the current branch.
2. Confirm all change-related tests and all locally runnable CI checks (tests, lint, type-check, build) exit `0`.
3. If any check fails, stop, fix the root cause, commit the fix, and re-run `changes-verification` so the receipt matches the new `HEAD` SHA.

## Workflow

### Step 1: Verify Branch Hygiene and Diff Size

- Confirm the working tree is clean (`git status --short` produces no output) and the branch is cleanly up to date with the target base branch.
- Inspect diff size with `git diff --stat <base>...HEAD`. Target focused diffs (~100 to 300 lines). If the diff mixes unrelated refactors with feature work or exceeds ~1000 lines, propose splitting it before opening the PR.
- If the branch has not been reviewed yet, run `code-review` before opening the PR when appropriate.

### Step 2: Draft Title and Body

Compose a standalone PR title and body:

- **Title:** Short, imperative, and specific (for example, `fix(api): deduplicate user query join`).
- **What & Why:** Summarize what changed, why the change is needed, key trade-offs, and linked issues.
- **Verification:** Include the concrete evidence from `changes-verification`: verified `HEAD` commit SHA, commands executed, observed pass/fail status, and any CI-only jobs that will run remotely.

### Step 3: Push and Open the PR

- Confirm the target base branch if ambiguous; never push directly to `main` or `master` without explicit user instruction.
- Push the branch (`git push -u origin <branch>`).
- Open the pull request (for example via `gh pr create --base <base> --title "..." --body "..."`).
- Return the PR URL and a concise summary of the verified checks.

## Red Flags

- Opening a PR before `changes-verification` passes on the final `HEAD` commit
- Claiming "tests pass" in the PR body without observed command output
- Leaving debug logs, temporary files, or unrelated edits in the diff
- Using vague PR titles such as "Fix bug" or "Update code"

## Gotchas

- When CI defines path-filtered workflows or matrix jobs, explicitly note in the PR Verification section which jobs were mirrored locally and which run only in CI.
- Never force-push over shared branches without explicit user confirmation.
