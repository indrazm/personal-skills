---
name: agent-tool-audit
description: Audit Anvia (@anvia/core) tool definitions, createTool handlers, output schemas, and onToolOutput middlewares against plain-text formatting conventions, metadata separation, truncation guardrails, and runtime safety hygiene. Use when reviewing or building Anvia tools, checking whether tools return raw JSON vs. structured plain text, verifying line-number anchoring, or hardening tool contracts. Manual invocation only — do not auto-invoke unless explicitly requested by the user.
disable-model-invocation: true
---

# Agent Tool Audit (Anvia)

Evaluate every `createTool(...)` / `Tool` implementation, `@anvia/tool-sandbox` wrapper, and `createMiddleware({ onToolOutput })` handler in an Anvia codebase against plain-text LLM output conventions and Anvia runtime best practices, and produce a concrete refactoring report.

- **Invocation:** Manual-only (`disable-model-invocation: true`). Run only when explicitly invoked by the user.

## When to Use

- Reviewing existing Anvia tools (`createTool`, custom `Tool` implementations, `@anvia/tool-sandbox` tools, `agent.asTool(...)`) for token efficiency, LLM readability, and Anvia runtime hygiene.
- Designing new `@anvia/core/tool` handlers and verifying their return shape (`string` / `ToolOutput.content(...)` vs. raw JSON objects).
- Auditing `createMiddleware({ onToolOutput })` truncation/spill gates to ensure they emit clean plain text rather than `JSON.stringify(...)` blobs.

## Core Principles (Anvia-Optimized)

1. **Plain Formatted Text over JSON (`string` or `ToolOutput.content`):** In Anvia, returning an object/array from `createTool` causes `normalizeToolResultOutput` to wrap it as `{ type: "json" }`, which `toolOutputToText` serializes via raw `JSON.stringify(...)` into the LLM context. Built-in and application tools must return clean, formatted `string` outputs (with `outputSchema: z.string()` or no JSON object `outputSchema`)—or `ToolOutput.content([...])` when returning multimodal text + files—never raw JSON objects, arrays, or `JSON.stringify(...)` strings.
2. **Metadata Separation via Anvia Observability / Lifecycle / Middleware:** Keep UI and telemetry metadata (`durationMs`, `bytesWritten`, `stdoutTruncated`, `exitCode: 0`, full diffs, raw records) out of the LLM-facing string. Emit UI/telemetry state via `Agent.lifecycle` (`onToolFinish`), `Agent.observability`, or `ToolCallContext.emitStreamEvent(...)`—or reshape structured outputs into compact plain text inside `createMiddleware({ onToolOutput })`. Only surface metadata inside the text string when the model needs it to decide the next step (e.g., non-zero exit code, pagination cursor, truncation notice).
3. **Line-Number Anchoring:** File-reading tools (`read_file` / custom readers) must prefix lines with 1-based line numbers (`00001| ` or `L1:`) and append a plain-text pagination footer (`Showing lines 1-200 of 420. Call read_file with startLine=201 to continue.`) instead of returning `{ content, startLine, endLine, nextStartLine, truncated }` JSON.
4. **Compact, Scannable Search & List Results:** Search tools should group matches by file path with line numbers (`path/to/file.ts:\n  Line 42: ...`). Directory/list tools (`list_files`, `list_processes`, `list_ports`) should emit compact newline-separated entries instead of JSON arrays of objects.
5. **Actionable Confirmations:** Mutation tools (`write_file`, `edit`, domain write tools) should return concise confirmation strings (plus compiler/linter/validation diagnostics if triggered) instead of echoing the full payload or returning `{ ok: true, path, bytesWritten }` JSON blobs.
6. **Hard Truncation Guardrails & Anvia Runtime Hygiene:**
   - Enforce line and byte caps inside high-volume tools AND backstop with a `createMiddleware({ onToolOutput })` output gate that truncates or spills oversized results to disk and returns a **plain-text** pointer (not `JSON.stringify({ type: "file_reference", ... })`).
   - Use `handler` instead of deprecated `execute` in `createTool(...)`.
   - Keep `createTool({ examples })` concise (rendered into tool descriptions on every turn), add concise `.describe(...)` hints on non-obvious Zod `inputSchema` fields, propagate `context.abortSignal` and `context.operationId` (for `@anvia/durable` idempotency), and set `requiresApproval` on destructive/irreversible tools.

## Audit Workflow

1. **Discover & Inventory:** Locate all `createTool(...)` calls, custom `Tool` objects, `@anvia/tool-sandbox` registrations, `agent.asTool(...)` wrappers, and `createMiddleware({ onToolOutput })` middlewares. Read `references/format-examples.md` for canonical Anvia plain-text templates and refactoring patterns.
2. **Audit Each Tool & Output Middleware:** Inspect what enters the LLM context (return value of `handler`/`execute`, `outputSchema`, and `onToolOutput` replacements) plus Anvia runtime hygiene (`handler` vs `execute`, `abortSignal`/`operationId`, `requiresApproval`, `examples` bloat) and grade each item:
   - `PASS`: Returns clean, bounded plain text (or `ToolOutput.content` for multimodal), separates UI/telemetry metadata cleanly, and follows Anvia runtime hygiene.
   - `NEEDS REFACTOR`: Returns raw JSON objects/arrays or `JSON.stringify(...)`, lacks line numbers or truncation guardrails, uses deprecated `execute`, or leaks noisy metadata into LLM tokens.
3. **Generate Report:** Output a Markdown summary table (`Tool / Middleware`, `File Path`, `Current Return Shape`, `Status`, `Issues Found`), followed by exact before/after TypeScript diffs showing how to refactor failing tools (including `onToolOutput` adapters when wrapping upstream tools like `createSandboxTools`).
4. **Optional Automated Guard:** If the repository has a test suite for tools, recommend adding the invariant check in `scripts/assert-plain-text-output.js` against `tool.call(...)` results and `tool_result` stream events to prevent regressions.

## Gotchas

- Do not flag external `@anvia/mcp` servers (registered via `Agent.mcpServers`) for returning JSON payloads; MCP tool schemas are externally controlled. (Do flag MCP tools mistakenly passed into `Agent.tools`.)
- Do not confuse the outer provider/stream transport envelope (`ToolResultEventPayload` / `{ type: "tool-result", output }`) with the inner LLM-facing `output` value.
- If a file happens to contain JSON content (e.g., `package.json`), `read_file` returning line-numbered JSON text (`00001| {`) is valid because the tool wrapper itself is line-numbered plain text.
- If using `@anvia/tool-sandbox`'s built-in `createSandboxTools(...)` (whose default `outputSchema` returns JSON objects), do not fork the package unnecessarily—recommend formatting its outputs into compact plain text via a dedicated Anvia `createMiddleware({ onToolOutput })` adapter.
- Never auto-invoke `agent-tool-audit`; wait for explicit user activation.
