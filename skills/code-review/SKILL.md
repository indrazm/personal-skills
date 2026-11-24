---
name: code-review
description: Performs multi-axis code review across correctness, readability, architecture, security, and performance by delegating to an independent subagent. Use when asked to review a PR, diff, file, or code snippet, before merging any change, or when auditing code quality.
---

# Code Review

Review every change before merge across five axes: correctness, readability, architecture, security, and performance.

**Approval standard:** Approve a change when it clearly improves overall code health, even if it is not perfect. Prioritize continuous improvement over personal style preferences.

## When to Use

- Before merging a pull request or branch
- After completing a feature implementation, bug fix, or refactor
- When auditing code written by yourself, another agent, or a human
- When asked to review a diff, file, or inline code snippet

## Mandatory Subagent Delegation

Do NOT perform the code review in the main conversation context. Always delegate the review to an independent subagent using your subagent/task delegation tool so the reviewer operates with fresh context and zero author bias.

- **Single-focus review:** Spawn one review subagent with the task/spec context, target diff or files, and instructions to read `references/review-checklist.md`.
- **Large or multi-module review:** Partition files by logical boundary, spawn review subagents in parallel, and synthesize their findings after all finish.
- **Self-authored code:** If you wrote the code in the current session, explicitly instruct the review subagent to treat the diff as untrusted external code and verify it independently against the spec and tests.
- **No subagent support:** If the current runtime provides no subagent/delegation capability, explicitly inform the user before proceeding rather than silently self-reviewing.

## Execution Workflow

1. **Gather context:** Collect the spec or task requirements, git diff or target files, and latest test output before delegating.
2. **Delegate review:** Spawn the independent review subagent with the gathered context and direct it to apply `references/review-checklist.md`:
   - Inspect tests first to verify intent, edge-case coverage, and regression protection.
   - Audit every changed file across all five axes (correctness, readability, architecture, security, performance).
   - Verify every candidate finding against callers, type/runtime guards, and tests before reporting it.
   - Order findings by impact (correctness and security first, then architecture, then minor items) using these severity labels:
     - `Critical:` Blocks merge (security flaw, data loss risk, broken behavior). Must include a concrete fix.
     - `(no prefix)` Required change: Must be resolved before merge (missing regression test, broken abstraction, poor error handling). Must include a concrete fix.
     - `Optional:` / `Consider:` Actionable improvement worth evaluating, not blocking.
     - `Nit:` Minor style or formatting preference; safe to ignore.
     - `FYI:` Informational context only.
3. **Synthesize and gate:** After the review subagent reports back, confirm every `Critical:` and required finding is resolved and that tests and builds pass before recommending approval.

## Red Flags

- Reviewing your own code in the main context instead of delegating to a subagent
- Approving without inspecting the diff or rubber-stamping with no evidence
- Checking only whether tests pass while ignoring security, architecture, or edge cases
- Allowing bug-fix changes without regression tests
- Deferring required fixes with "clean up later"
- Relocating complexity across files without reducing what a reader must track

## Gotchas

- Treat AI-generated code with extra skepticism; plausible-looking diffs frequently hide subtle edge-case or invariant bugs.
- Never bury a correctness or security issue under a pile of style nits.
- Zero findings is a valid review outcome; do not invent issues just to produce feedback.
- Focus feedback strictly on the code and invariants, not subjective stylistic preferences.
