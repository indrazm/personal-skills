---
name: zstack-mode
description: Runs an interactive task execution loop that asks for a task, completes it, enforces both code-review and changes-verification after every completed task, and prompts to open a pull request via create-pr on approval. Manual invocation only — do not auto-invoke unless explicitly requested by the user.
disable-model-invocation: true
---

# ZStack Mode

Operate in a disciplined, gated task loop where every completed task automatically passes independent code review and deterministic change verification before offering to open a pull request.

- **Invocation:** Manual-only (`disable-model-invocation: true`). Run only when explicitly invoked by the user.

## Execution Loop

Follow these steps strictly in order for every task:

### Step 1: Ask for the Task

- If the user has not yet specified a task, ask clearly what task they want to work on (and clarify any ambiguous scope or acceptance criteria before editing code).
- If the user already supplied a task when invoking `zstack-mode`, confirm the scope briefly and proceed directly to execution.

### Step 2: Implement the Task

- Complete the task cleanly with focused, well-scoped changes and tests.
- Use supporting skills when applicable during implementation (for example, `debugging` when diagnosing failures, `engineering-decision` for architectural decisions, or `micro-animation` / `optimistic-ui` for frontend motion and state updates).

### Step 3: Run Mandatory Post-Task Gates

After completing the task—and BEFORE reporting the task done or offering to create a PR—run BOTH skills in sequence:

1. **Invoke `code-review`:** Delegate the diff to an independent review subagent. Resolve every `Critical:` and required finding before proceeding.
2. **Invoke `changes-verification`:** Execute change-related tests and locally runnable CI checks against the final commit so `.changes-verification-receipt.json` passes for `HEAD`.

If fixes are required by either gate, apply the fixes and re-run the affected gate(s) until both `code-review` and `changes-verification` pass cleanly on the final state.

### Step 4: Ask to Create a Pull Request

Present a concise summary of:
- What was implemented
- `code-review` outcome
- `changes-verification` receipt evidence (`HEAD` SHA and verified commands)

Then explicitly ask the user: **"Would you like me to create a pull request for this task?"**

- **If the user says yes:** Invoke the `create-pr` skill.
- **If the user says no:** Do not push or open a PR; ask whether the user wants to start the next task in `zstack-mode` or exit.

### Step 5: Next Task

Once the PR is opened (or skipped), ask what the next task is. Every subsequent task repeats Steps 1 through 4 with full `code-review` and `changes-verification` gates.

## Red Flags

- Skipping `code-review` or `changes-verification` after finishing a task, even for "small" changes
- Running `code-review` inline in the main context instead of delegating to a subagent
- Opening a PR without asking the user first
- Running `create-pr` with a stale verification receipt after post-review edits
- Bundling multiple unrelated tasks into one unverified pass instead of gating each task individually

## Gotchas

- If `code-review` triggers edits after `changes-verification` has already run, always re-run `changes-verification` on the updated commit so the receipt matches `HEAD`.
- Never auto-invoke `zstack-mode`; wait for explicit user activation.
