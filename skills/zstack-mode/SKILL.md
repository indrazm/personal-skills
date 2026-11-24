---
name: zstack-mode
description: Runs an interactive task execution loop that asks for a task and backward-compatibility preference (default no), applies preferred code structure, enforces code-review and changes-verification via a deterministic gate script after every completed task, and prompts to open a pull request via create-pr on approval. Manual invocation only — do not auto-invoke unless explicitly requested by the user.
disable-model-invocation: true
---

# ZStack Mode

Operate in a disciplined, gated task loop where every completed task automatically passes independent code review and deterministic change verification before offering to open a pull request.

- **Invocation:** Manual-only (`disable-model-invocation: true`). Run only when explicitly invoked by the user.
- **Gate script:** Resolve `<skill-dir>` to the directory containing this `SKILL.md` and use `<skill-dir>/scripts/zstack_gate.py` to enforce every phase deterministically.
- **Optional runtime hooks:** See `references/hooks-setup.md` for Antigravity, Claude Code, and Git `pre-push` hook templates wired to `scripts/zstack_gate.py`.

## Execution Loop

Follow these steps strictly in order for every task:

### Step 1: Ask for the Task & Compatibility Requirement

- If the user has not yet specified a task, ask clearly what task they want to work on (and clarify any ambiguous scope or acceptance criteria before editing code).
- Ask whether **backward compatibility** is required (**default: No**).
  - Unless the user explicitly says **Yes**, do NOT add backward-compatibility shims, legacy fallbacks, deprecated aliases, or dual-path bridges—replace or delete old code cleanly.
- If the user already supplied a task when invoking `zstack-mode`, confirm scope and backward-compatibility preference (defaulting to **No** if not requested) before editing.
- Initialize the task gate before editing:
  ```bash
  python3 <skill-dir>/scripts/zstack_gate.py start --task "<short task summary>"
  ```
  (Pass `--backward-compat` only if the user explicitly requested backward compatibility.)

### Step 2: Implement the Task

- Read `references/code-structure.md` when creating new modules, files, routes, services, or greenfield structure (always respecting existing repo conventions when they differ).
- Complete the task cleanly with focused, well-scoped changes and meaningful tests.
- Use supporting skills when applicable during implementation (`debugging` for root-cause triage, `test-audit` when writing or deleting tests, `engineering-decision` for architectural decisions, `micro-animation` / `optimistic-ui` for frontend UI).

### Step 3: Run Mandatory Post-Task Gates

After completing the task—and BEFORE reporting the task done or offering to create a PR—run BOTH skills in sequence and verify through `zstack_gate.py`:

1. **Invoke `code-review`:** Delegate the diff to an independent review subagent. Resolve every `Critical:` and required finding, then record the verdict on the final commit:
   ```bash
   python3 <skill-dir>/scripts/zstack_gate.py record-review --status pass --summary "<brief verdict>"
   ```
2. **Invoke `changes-verification`:** Execute change-related tests and locally runnable CI checks against the final commit so `.changes-verification-receipt.json` passes for `HEAD`.
3. **Run the deterministic gate check:**
   ```bash
   python3 <skill-dir>/scripts/zstack_gate.py check
   ```
   - `check` verifies that both `code-review` and `.changes-verification-receipt.json` passed for the exact current `HEAD` commit SHA.
   - If `check` exits non-zero (for example, post-review edits changed `HEAD`), re-run the stale gate(s) until `check` exits `0`.

### Step 4: Ask to Create a Pull Request

Present a concise summary of:
- What was implemented
- `code-review` outcome
- `changes-verification` receipt evidence (`HEAD` SHA and verified commands)

Then explicitly ask the user: **"Would you like me to create a pull request for this task?"**

- **If the user says yes:** Invoke the `create-pr` skill, then run `python3 <skill-dir>/scripts/zstack_gate.py complete`.
- **If the user says no:** Do not push or open a PR; run `python3 <skill-dir>/scripts/zstack_gate.py complete` and ask whether the user wants to start the next task in `zstack-mode` or exit.

### Step 5: Next Task

Once the PR is opened (or skipped), ask what the next task is. Every subsequent task repeats Steps 1 through 4 with full `code-review`, `changes-verification`, and `zstack_gate.py check` gates.

## Red Flags

- Adding backward-compatibility shims, deprecated aliases, or legacy fallbacks when the user did not explicitly request backward compatibility
- Skipping `code-review`, `changes-verification`, or `zstack_gate.py check` after finishing a task, even for "small" changes
- Running `code-review` inline in the main context instead of delegating to a subagent
- Opening a PR without asking the user first
- Committing `.zstack-state.json` or `.changes-verification-receipt.json`
- Bundling multiple unrelated tasks into one unverified pass instead of gating each task individually

## Gotchas

- If `code-review` triggers edits after `changes-verification` has already run, `HEAD` changes and `zstack_gate.py check` will reject the stale receipt; re-run the stale gate(s) on the final commit.
- Never auto-invoke `zstack-mode`; wait for explicit user activation.
