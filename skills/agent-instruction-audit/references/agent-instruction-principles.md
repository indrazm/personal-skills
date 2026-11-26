# Anvia Agent Instruction & Harness Principles

Detailed grading rubric, Anvia-specific anti-patterns, and prompt-caching hygiene reference for `agent-instruction-audit`.

## How Anvia Assembles Model Requests

In `@anvia/core`, requests are assembled in this exact order before reaching the provider (`resolveAgentOptions` → `orderedRequestMessages`):

1. **System instructions:** `[Agent.instructions, Agent.skills.instructions].join("\n\n")` (plus any `role: "system"` entries in `chatHistory`).
2. **Tool definitions:** Registered static `Agent.tools`, `Agent.skills.tools` (`get_skill_instructions`, `get_skill_reference`, `get_skill_script`, `run_skill_script`), `Agent.mcpServers`, `ProviderTool`, and dynamically selected `ToolIndex` definitions. Any `createTool({ examples })` entries are appended directly to each tool's `description` on every turn.
3. **Context documents (`Agent.context`):** Static `Document` objects, `VectorContext`, and `ContextSource` outputs are normalized via `normalizeDocuments(...)` into `<file id: ...>` blocks inside a `user` message **before** non-system `chatHistory`.
4. **Conversation history:** Non-system `chatHistory` (user prompt, assistant turns, tool calls, tool results, and any `Agent.memory` compacted history).
5. **Per-turn middleware:** `AgentMiddleware.onCompletionRequest({ turn, request })` can inspect or rewrite `request` before each provider call.

## Grading Scale

- **`PASS`**: Explicitly enforced in `instructions` and/or structurally backed by Anvia runtime options, aligned with registered tool schemas, and uncontradicted across middlewares/context.
- **`PARTIAL`**: Implied or vague in prose, missing the backing Anvia runtime configuration (e.g., parallel batching instructed without `toolConcurrency > 1`, safety only in prose without `requiresApproval`/`guardrails`), or weakened elsewhere.
- **`MISSING`**: Absent from both `instructions` and runtime config, or actively violated by the agent setup.

---

## The 9 Evaluation Rules (Anvia-Optimized)

### 1. Autonomous Persistence

- **PASS Criteria:** `instructions` clearly instructs the agent to complete the task end-to-end without pausing for routine confirmations, AND `Agent.maxTurns` (or per-run `maxTurns`) is sized appropriately for multi-step tool workflows (default is `20`; avoid starving complex agents with `maxTurns: 2`–`4`). For subagents exposed via `agent.asTool({ suspension: "reject" })`, instructions explicitly forbid asking interactive follow-up questions that would suspend or stall the parent run.
- **PARTIAL Criteria:** Thorough instructions exist, but `maxTurns` is too low for expected tool steps or stop/continue boundaries are vague.
- **Anti-Patterns:**
  - Asking "Would you like me to proceed?" in an autonomous agent instead of reserving suspension for real `requiresApproval` or question-tool interactions.
  - Giving an agent `skills` + verification tools while capping `maxTurns: 2`.

### 2. Inspect First

- **PASS Criteria:** Requires inspecting existing state, files, or records via read-only tools before calling mutating tools or asserting facts. Forbids guessing IDs, paths, flags, or schemas.
- **PARTIAL Criteria:** Mentions "check context first" without banning guesswork or requiring pre-mutation inspection.
- **Anti-Patterns:**
  - Calling `write_file`, `exec_command`, or domain mutation tools before reading the target state.
  - Hallucinating record IDs or file paths instead of querying lookup/list tools first.

### 3. Parallel Batching

- **PASS Criteria:** BOTH conditions hold:
  1. `instructions` directs the model to emit independent read-only/search tool calls in parallel in a single turn.
  2. Call sites pass `toolConcurrency > 1` to `agent.generate({ ..., toolConcurrency })` or `agent.stream({ ..., toolConcurrency })` when concurrent execution is desired.
- **PARTIAL Criteria:** `instructions` asks for parallel calls, but call sites leave `toolConcurrency` at `1` (sequential execution), OR `toolConcurrency > 1` is set without guiding the model to batch independent reads.
- **Anti-Patterns:**
  - Mixing a `requiresApproval` tool or question tool into a read-only batch expecting parallelism (Anvia's `ToolCallExecutor.maySuspend` automatically forces sequential execution for any turn containing a potentially suspending tool).
  - Prompt examples showing serial one-tool-per-turn patterns for independent lookups.

### 4. Dedicated Tools Over Shell

- **PASS Criteria:** Directs the agent to use dedicated registered tools (`read_file`, `write_file`, `list_files`, domain `createTool(...)` tools, `skills` tools, or `mcpServers` tools) instead of shelling out through `exec_command` (`cat`, `sed`, `find`, `curl`) whenever a dedicated tool exists, citing the exact registered names.
- **PARTIAL Criteria:** Discourages shell usage generically without naming the exact Anvia tools registered on the `Agent`.
- **Anti-Patterns:**
  - Instructions referencing tools not registered on the `Agent` (e.g., telling an `@anvia/tool-sandbox` agent to call `edit` or `grep` when only `exec_command`, `read_file`, `write_file`, and `list_files` are registered).
  - Using `exec_command("cat ...")` when `read_file` is available.

### 5. Minimal Diffs

- **PASS Criteria:** Instructs the agent to scope edits and mutations strictly to the user's request, follow local conventions, and avoid drive-by refactoring, unrelated formatting churn, or unnecessary tool mutations.
- **PARTIAL Criteria:** Generic quality advice ("write clean code") without forbidding unrelated edits or extra mutations.
- **Anti-Patterns:**
  - Encouraging broad cleanup of untouched files or records.
  - Instructing full-file rewrites without warning about preserving unrelated content when using `write_file`.

### 6. Self-Verification

- **PASS Criteria:** Requires running verification steps (tests, typecheckers, linters, or read-back checks) after mutations, reading real tool output, and fixing failures before returning. When `outputSchema` is configured on `Agent`, instructions align with the schema contract without contradicting structured output formatting.
- **PARTIAL Criteria:** Suggests "verify if possible" without requiring failure remediation or evidence-based reporting.
- **Anti-Patterns:**
  - Finishing immediately after a mutation without running a check or verifying state.
  - Instructing markdown/prose formatting in `instructions` that conflicts with `Agent.outputSchema` structured extraction.

### 7. Action & Workspace Safety

- **PASS Criteria:** Combines clear `instructions` safety rules (no destructive git/workspace commands like `git reset --hard`, `rm -rf`, force-push, and no reverting unrelated user changes) WITH Anvia structural controls where applicable:
  - `requiresApproval` (static boolean, `{ reason }`, or predicate) on destructive/irreversible `createTool` definitions
  - `Agent.guardrails` for input/output policy enforcement
  - `@anvia/tool-sandbox` policies (`exec.commands` allow/block lists, `exec.maxTimeoutMs`, `writeFile.maxBytes`, `readFile.maxBytes`)
- **PARTIAL Criteria:** Safety exists only as prose in `instructions` while destructive tools execute with no `requiresApproval`, guardrail, or sandbox command policy.
- **Anti-Patterns:**
  - Relying exclusively on "please do not run dangerous commands" when `exec_command` has unrestricted shell access.
  - Instructing `git reset` or `git checkout .` to undo mistakes.

### 8. Context Precedence

- **PASS Criteria:** Uses Anvia's layered context model intentionally with clear precedence:
  - `Agent.instructions`: durable behavioral rules & safety policy (highest precedence)
  - `Agent.skills`: progressive on-demand procedures (`loadSkills(...)`) instead of stuffing every workflow into `instructions`
  - `Agent.context`: static `Document`s or retrieved `ContextSource` / `VectorContext` grounded data (clearly marked as untrusted/reference data when external)
  - Trailing user message / runtime metadata: session-specific environment state (`cwd`, branch, user locale, repo overrides)
- **PARTIAL Criteria:** Dumps large playbooks directly into `instructions` instead of `skills`/`context`, or lacks precedence rules when retrieved `context` conflicts with `instructions`.
- **Anti-Patterns:**
  - Treating untrusted retrieved `VectorContext` / `ContextSource` documents with the same authority as system `instructions` (prompt-injection risk).
  - Repeating identical guidance across `instructions`, `skills`, and `Agent.context` documents.

### 9. Harness Hygiene (Anvia)

Check all three sub-dimensions across `new Agent(...)`, `createTool(...)`, `Agent.context`, and `middlewares`:

1. **Prompt-Caching Prefix Stability:**
   - **Good prefix order:**
     1. Static `Agent.instructions` (byte-identical across turns and runs)
     2. Static `Agent.skills` summaries (deterministic order)
     3. Deterministic tool definitions (`Agent.tools`, `mcpServers`) with concise descriptions and minimal `examples`
     4. Static `Document` entries in `Agent.context` (placed before dynamic `ContextSource` / `VectorContext` if mixed)
     5. Volatile per-turn context (timestamps, `runId`, `sessionId`, git status, dynamic user state) injected in the **trailing user message** — NEVER at the top of `Agent.instructions`
   - **Anvia Cache-Breaker Anti-Patterns:**
     - Interpolating `new Date()`, `Date.now()`, UUIDs, request IDs, or volatile per-request state into `new Agent({ instructions: ... })` when reusing prompts across turns/sessions.
     - Using `createMiddleware({ onCompletionRequest })` to prepend dynamic timestamps, turn counters, or changing state to `request.instructions` or system messages on every turn.
     - Creating a fresh dynamic `ContextSource` that changes text on every turn ahead of long `chatHistory` when the data could be fetched on-demand by a tool or placed at the tail.
     - Overloading `createTool({ examples })` with long worked examples across many static tools (rendered into every tool description on every turn).
2. **Tool-Schema Alignment:**
   - Cross-check every tool name and parameter mentioned in `instructions` and `skills` against registered `Agent.tools`, `Agent.mcpServers`, `Agent.skills.tools`, `ToolIndex`, and `agent.asTool(...)`.
   - Flag phantom tools, renamed tools, wrong parameter names, and MCP tools mistakenly passed to `Agent.tools` instead of `Agent.mcpServers`.
3. **Zero Conflicting Directives:**
   - Flag contradictions across `Agent.instructions`, `Agent.skills`, `Agent.guardrails`, `outputSchema`, and `onCompletionRequest` middlewares.

---

## TL;DR Output Format

Keep the audit report strictly concise—do not emit a rewritten `instructions` string unless requested:

```markdown
### Anvia Agent Instruction Audit Scorecard

| # | Rule | Status | Evidence / Gap |
| :-: | :--- | :---: | :--- |
| 1 | Autonomous Persistence | PASS / PARTIAL / MISSING | `src/agent.ts:18-42` — concise evidence or missing config |
| ... | ... | ... | ... |

### Top Issues

1. **[High] <Issue Title>** (`src/agent.ts:L18-L26`)
   - **Risk:** Concrete Anvia impact (e.g., dynamic timestamp in `instructions` busts prefix cache every turn; `toolConcurrency` omitted so batched reads serialize).
   - **Fix:** Exact targeted change to `AgentOptions`, middleware, or instructions.
```
