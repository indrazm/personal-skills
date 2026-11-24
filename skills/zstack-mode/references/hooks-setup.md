# ZStack Mode Optional Hook Setup

`scripts/zstack_gate.py` works out of the box across every coding agent via direct CLI checks (`start`, `record-review`, `check`, `complete`). To enforce gates deterministically at the agent or git runtime layer, wire the same script into one of the hook configurations below.

All hook adapters store state inside `<git-dir>/zstack-state.json` (never cluttering `git status` or `.gitignore`) and stay inactive during `awaiting_task` and `awaiting_pr_approval` phases so interactive prompts ("What task?" / "Create PR?") never trigger an infinite loop.

Replace `<skill-dir>` with the installed path to `zstack-mode` (for example `.agents/skills/zstack-mode` or `~/.claude/skills/zstack-mode`).

## 1. Antigravity (`.agents/hooks.json`)

Blocks `git push` and `gh pr create` via `run_command` whenever a `zstack-mode` task is active and `code-review` or `changes-verification` has not passed for `HEAD`:

```json
{
  "zstack-pr-gate": {
    "PreToolUse": [
      {
        "matcher": "run_command",
        "hooks": [
          {
            "type": "command",
            "command": "python3 <skill-dir>/scripts/zstack_gate.py agy-pre-tool",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

## 2. Claude Code (`.claude/settings.json`)

Combines a `PreToolUse` guard on `Bash` (`git push` / `gh pr create`) with a state-aware `Stop` hook that blocks finishing an `implementing` turn before gates pass:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 <skill-dir>/scripts/zstack_gate.py claude-pre-tool"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "python3 <skill-dir>/scripts/zstack_gate.py stop-hook"
          }
        ]
      }
    ]
  }
}
```

## 3. Universal Git `pre-push` Hook (`.git/hooks/pre-push`)

Works identically across every agent and terminal workflow:

```bash
#!/usr/bin/env bash
set -euo pipefail

GIT_DIR="$(git rev-parse --git-dir)"
if [[ -f "$GIT_DIR/zstack-state.json" ]]; then
  python3 <skill-dir>/scripts/zstack_gate.py check
fi
```

Make it executable with `chmod +x .git/hooks/pre-push`. Never commit `.changes-verification-receipt.json` (keep it in `.gitignore`).
