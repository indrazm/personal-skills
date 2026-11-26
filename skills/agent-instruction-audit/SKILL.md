---
name: agent-instruction-audit
description: Audit Anvia (@anvia/core) agent instructions, context assembly, middlewares, and tool/runtime configuration against coding-agent operating principles, prompt-caching hygiene, and tool-schema alignment. Use when reviewing, debugging, or optimizing Anvia Agent instances and prompt-building code. Manual invocation only — do not auto-invoke unless explicitly requested by the user.
disable-model-invocation: true
---

# Agent Instruction Audit (Anvia)

Evaluate an Anvia (`@anvia/core`) `Agent` definition, its `instructions`, `context`, `skills`, `middlewares`, and runtime options against core autonomous agent conventions, producing a concise TL;DR scorecard and gap analysis.

- **Invocation:** Manual-only (`disable-model-invocation: true`). Run only when explicitly invoked by the user.

## When to Use

- Auditing an Anvia `new Agent({ ... })` setup or instruction builder for missing guardrails, behavioral drift, or conflicting directives.
- Checking Anvia prompt-caching hygiene across `Agent.instructions`, `Agent.skills`, `Agent.context` (`Document`, `ContextSource`, `VectorContext`), and `onCompletionRequest` middlewares.
- Verifying alignment between `instructions` and registered `tools`, `mcpServers`, `skills`, `ToolIndex`, `toolConcurrency`, `maxTurns`, and `requiresApproval` / `guardrails`.

## Evaluation Rubric

Read `references/agent-instruction-principles.md` for Anvia-specific criteria and anti-patterns, then grade the agent setup against these 9 rules:

1. **Autonomous Persistence:** Owns tasks end-to-end without stopping for routine confirmations, and sets a sufficient `maxTurns` budget (avoiding premature exhaustion on multi-step tool loops).
2. **Inspect First:** Reads state/files and inspects schemas or callers before mutating; zero guessing.
3. **Parallel Batching:** Instructs parallel read/search tool calls AND enables `toolConcurrency > 1` on `agent.generate(...)` / `agent.stream(...)` (noting Anvia serializes batches containing `requiresApproval` or question tools).
4. **Dedicated Tools Over Shell:** Prefers dedicated registered `createTool(...)` / `skills` / `mcpServers` tools over raw `exec_command` shell invocations whenever a dedicated tool exists.
5. **Minimal Diffs:** Scopes edits and mutations strictly to the task; avoids unrequested refactors or side effects.
6. **Self-Verification:** Runs verification tools/checks after mutations and resolves failures before producing the final output (or matching `outputSchema`).
7. **Action & Workspace Safety:** Protects destructive/irreversible actions structurally via `requiresApproval`, `Agent.guardrails`, or `@anvia/tool-sandbox` command/path policies—not prose alone—and forbids reverting unrelated user changes.
8. **Context Precedence:** Separates static `instructions`, progressive `skills`, static/retrieved `Agent.context` (`Document` / `ContextSource` / `VectorContext`), and trailing runtime context with a clear override hierarchy.
9. **Harness Hygiene (Anvia):** Keeps `Agent.instructions`, `skills`, and `Tool.definition` (`examples`) static and deterministic for prefix caching; places volatile per-turn context at the tail; matches every referenced tool/arg name to registered `tools`/`mcpServers`/`skills`/`ToolIndex`; contains zero conflicting rules.

## Audit Workflow

1. **Locate & Read:** Find `new Agent(...)` constructors, instruction builders, `createMiddleware({ onCompletionRequest })` hooks, `Agent.context` sources, `loadSkills(...)`, `guardrails`, `agent.generate(...)`/`agent.stream(...)` call sites, and all registered `createTool(...)` / `mcpServers` / `ToolIndex` / `agent.asTool(...)` definitions.
2. **Score Each Rule:** Grade every rule from 1 to 9 as `PASS`, `PARTIAL`, or `MISSING`, citing exact file paths and line numbers from the codebase.
3. **Identify Anvia Risks:** Flag contradictory directives, prefix-cache breakers (timestamps, `runId`, `sessionId`, or dynamic state interpolated into `Agent.instructions` or prepended in `onCompletionRequest`), bloated `createTool({ examples })` prompt overhead, `toolConcurrency` bottlenecks, `maxTurns` starvation, and phantom/mismatched tool names.
4. **Deliver TL;DR Report:** Present a concise Markdown Scorecard Table (`Rule`, `Status`, `Evidence / Gap`) followed by a prioritized **Top Issues** section with exact file/line citations and concrete Anvia fixes.

## Gotchas

- Keep the output strictly TL;DR (Scorecard Table + Top Issues). Do not generate a full rewritten `instructions` block unless the user explicitly asks for one.
- Always inspect runtime assembly, not just static strings: Anvia concatenates `[options.instructions, skills.instructions]`, injects `Agent.context` documents before non-system `chatHistory` (`orderedRequestMessages`), and allows `onCompletionRequest` middleware to mutate `request.instructions` or `request.chatHistory` per turn.
- Remember `createTool({ examples })` appends worked examples to every tool's `description` on every turn—flag verbose examples that bloat the static prefix.
- Never auto-invoke `agent-instruction-audit`; wait for explicit user activation.
