# ZStack Mode Optional Hook Setup

`scripts/zstack_gate.sh` works out of the box across every coding agent via direct CLI checks (`start`, `record-review`, `check`, `complete`). To enforce gates deterministically at the agent or git runtime layer, wire the same script into your agent's hook or plugin configuration below.

All hook adapters store state inside `<git-dir>/zstack-state.json` (never cluttering `git status` or `.gitignore`) and stay inactive during `awaiting_task` and `awaiting_pr_approval` phases so interactive prompts ("What task?" / "Create PR?") never trigger an infinite loop.

Replace `<skill-dir>` with the installed path to `zstack-mode` (for example `.agents/skills/zstack-mode`, `~/.claude/skills/zstack-mode`, or `~/.codex/skills/zstack-mode`).

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
            "command": "bash <skill-dir>/scripts/zstack_gate.sh agy-pre-tool",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

## 2. Codex (`.codex/hooks.json` or `~/.codex/hooks.json`)

Blocks `git push` / `gh pr create` on `Bash` and blocks ending an `implementing` turn before gates pass (run `/hooks` in Codex to trust the hook after adding):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash <skill-dir>/scripts/zstack_gate.sh pre-tool-hook",
            "statusMessage": "Checking zstack-mode gates...",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash <skill-dir>/scripts/zstack_gate.sh stop-hook",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

## 3. Claude Code (`.claude/settings.json`)

Uses the same `pre-tool-hook` and state-aware `stop-hook` adapters:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash <skill-dir>/scripts/zstack_gate.sh pre-tool-hook"
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
            "command": "bash <skill-dir>/scripts/zstack_gate.sh stop-hook"
          }
        ]
      }
    ]
  }
}
```

## 4. OpenCode (`.opencode/plugins/zstack-gate.ts` or `~/.config/opencode/plugins/zstack-gate.ts`)

Intercepts `bash` tool calls via `tool.execute.before` and delegates to `zstack_gate.sh check-cmd`:

```ts
import type { Plugin } from "@opencode-ai/plugin";
import { spawnSync } from "node:child_process";

const GATE_SCRIPT = "<skill-dir>/scripts/zstack_gate.sh";

export const ZStackGatePlugin: Plugin = async ({ directory }) => ({
  "tool.execute.before": async (input, output) => {
    if (input.tool !== "bash") return;
    const command = String(output.args?.command ?? "");
    const res = spawnSync("bash", [GATE_SCRIPT, "--repo", directory, "check-cmd", command], {
      encoding: "utf-8",
    });
    if (res.status !== 0) {
      throw new Error(res.stderr?.trim() || "zstack-mode gate blocked command.");
    }
  },
});
```

## 5. Pi Coding Agent (`.pi/extensions/zstack-gate.ts` or `~/.pi/extensions/zstack-gate.ts`)

Intercepts `bash` tool calls via `tool_call` (blocking `git push` / `gh pr create` until gates pass) and checks incomplete tasks on `agent_end`:

```ts
import { spawnSync } from "node:child_process";

const GATE_SCRIPT = "<skill-dir>/scripts/zstack_gate.sh";

export default function (pi: any) {
  pi.on("tool_call", async (event: any, ctx: any) => {
    if (event.tool !== "bash") return;
    const command = String(event.args?.command ?? "");
    const cwd = String(ctx?.cwd || process.cwd());
    const res = spawnSync("bash", [GATE_SCRIPT, "--repo", cwd, "check-cmd", command], {
      encoding: "utf-8",
    });
    if (res.status !== 0) {
      return {
        block: true,
        message: res.stderr?.trim() || "zstack-mode gate blocked command.",
      };
    }
  });

  pi.on("agent_end", async (_event: any, ctx: any) => {
    const cwd = String(ctx?.cwd || process.cwd());
    const res = spawnSync("bash", [GATE_SCRIPT, "--repo", cwd, "stop-hook"], {
      encoding: "utf-8",
    });
    if (res.status !== 0 && res.stderr?.trim()) {
      console.warn(res.stderr.trim());
    }
  });
}
```

## 6. Universal Git `pre-push` Hook (`.git/hooks/pre-push`)

Works identically across every agent and terminal workflow:

```bash
#!/usr/bin/env bash
set -euo pipefail

GIT_DIR="$(git rev-parse --git-dir)"
if [[ -f "$GIT_DIR/zstack-state.json" ]]; then
  bash <skill-dir>/scripts/zstack_gate.sh check
fi
```

Make it executable with `chmod +x .git/hooks/pre-push`. Never commit `.changes-verification-receipt.json` (keep it in `.gitignore`).
