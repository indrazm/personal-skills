# Canonical Anvia Tool Output Format Examples

Reference templates for clean, token-efficient plain-text tool outputs in Anvia (`@anvia/core/tool`) vs. raw JSON anti-patterns.

## How Anvia Serializes Tool Return Values

In `@anvia/core`, `normalizeToolResultOutput(output)` handles `createTool` return values as follows:

| `handler` Return Value | Anvia `NormalizedToolOutput` | What Enters the LLM Context | Audit Verdict |
| :--- | :--- | :--- | :--- |
| `string` | `{ type: "text", value }` | Exact plain-text string | **PASS** (if not raw `JSON.stringify(...)`) |
| `ToolOutput.content([...])` | `{ type: "content", value }` | Text parts + multimodal file parts | **PASS** (when text parts are plain text) |
| Plain JS object / array | `{ type: "json", value }` | `JSON.stringify(value)` | **NEEDS REFACTOR** (for built-in/custom app tools) |

## Metadata Separation in Anvia

Anvia sends the tool's return value directly to the model unless reshaped by `createMiddleware({ onToolOutput })`. Keep UI/telemetry metadata out of the LLM string:

- **Timing & raw diagnostics:** Capture in `Agent.lifecycle` (`onToolStart`, `onToolFinish`) and `Agent.observability` instead of embedding `durationMs` or `bytesWritten` in the LLM output string.
- **Live UI progress / rich payloads:** Emit via `context.emitStreamEvent(...)` when streaming UI state.
- **Wrapping JSON-returning upstream tools (e.g., `@anvia/tool-sandbox`):** Use `createMiddleware({ onToolOutput })` to format structured JSON tool outputs into compact plain text before they enter the model context.

---

## 1. File Read (`read_file`)

### Anti-Pattern (JSON Object `outputSchema` — e.g., raw sandbox page object)

```ts
const readFileTool = createTool({
  name: "read_file",
  description: "Read a text file.",
  inputSchema: z.object({ path: z.string(), startLine: z.number().optional() }),
  outputSchema: z.object({
    content: z.string(),
    startLine: z.number(),
    endLine: z.number().nullable(),
    nextStartLine: z.number().nullable(),
    truncated: z.boolean(),
  }),
  execute: async ({ path, startLine }) => readPage(path, startLine), // deprecated `execute` + JSON blob!
});
```

### Canonical Anvia Plain Text (`handler` + `outputSchema: z.string()`)

```ts
const readFileTool = createTool({
  name: "read_file",
  description: "Read a bounded page of a UTF-8 text file with 1-based line numbers.",
  inputSchema: z.object({
    path: z.string().min(1).describe("Workspace-relative file path."),
    startLine: z.number().int().positive().optional().describe("1-based starting line."),
    lineCount: z.number().int().positive().max(2_000).optional(),
  }),
  outputSchema: z.string(),
  handler: async ({ path, startLine = 1, lineCount = 500 }, context) => {
    const page = await readPage(path, startLine, lineCount, context.abortSignal);
    const numbered = page.lines
      .map((line, idx) => `${String(page.startLine + idx).padStart(5, "0")}| ${line}`)
      .join("\n");

    if (!page.truncated) return numbered;
    return `${numbered}\n\n(Showing lines ${page.startLine}-${page.endLine}. Pass startLine=${page.nextStartLine} to read more.)`;
  },
});
```

Rendered LLM output:

```text
00001| import { Agent } from "@anvia/core";
00002| export const supportAgent = new Agent({
...
00200| });

(Showing lines 1-200. Pass startLine=201 to read more.)
```

> Reading a JSON file like `package.json` as `00001| {` is **valid** because the tool wrapper is line-numbered plain text.

---

## 2. Content Search (`grep` / Domain Search)

### Anti-Pattern (JSON Array)

```ts
// Serializes as [{"file":"src/auth.ts","line":42,"match":"..."}]
return matches;
```

### Canonical Plain Text

```text
Found 2 matches:

src/auth.ts:
  Line 42: const session = verifyToken(req.headers.authorization);
  Line 87: return verifyToken(token);
```

When capped:

```text
Found 100+ matches (showing first 100):

src/auth.ts:
  Line 42: ...

(Results truncated at 100 matches. Narrow the query or path filter.)
```

---

## 3. Directory / Resource Listings (`list_files`, `list_processes`, `list_ports`)

### Anti-Pattern (Nested JSON Array)

```json
{"path":"src","entries":[{"path":"src/index.ts","type":"file","size":412},{"path":"src/tools","type":"directory"}]}
```

### Canonical Plain Text

```text
src/index.ts
src/tools/
```

When capped:

```text
src/index.ts
...
(Showing first 100 of 642 entries. Pass a more specific subdirectory.)
```

---

## 4. Command Execution (`exec_command` / `bash`)

### Anti-Pattern (JSON Envelope)

```json
{"status":"exited","exitCode":1,"stdout":"1 pass\n1 fail\n","stderr":"AssertionError: expected 200","durationMs":842,"stdoutTruncated":false,"stderrTruncated":false}
```

### Canonical Plain Text

Success (`exitCode === 0` needs no noisy status/duration JSON):

```text
12 pass
0 fail
```

Failure (surface non-zero exit code or timeout so the model can react):

```text
1 pass
1 fail
AssertionError: expected 200, got 401

Exit code: 1
```

---

## 5. File & Domain Mutations (`write_file`, `edit`, domain writes)

### Anti-Pattern (JSON Status Blob or Echoing Full Content)

```ts
return { ok: true, path, bytesWritten };
```

### Canonical Plain Text (with `requiresApproval` + `operationId`)

```ts
const writeFileTool = createTool({
  name: "write_file",
  description: "Write a UTF-8 file inside the workspace.",
  inputSchema: z.object({
    path: z.string().min(1),
    content: z.string(),
  }),
  outputSchema: z.string(),
  requiresApproval: ({ path }) =>
    path.startsWith("config/") ? { reason: `Modify configuration file ${path}` } : false,
  handler: async ({ path, content }, context) => {
    await writeTextFile({
      path,
      content,
      operationId: context.operationId,
      abortSignal: context.abortSignal,
    });
    return `Wrote ${path}.`;
  },
});
```

With optional post-edit diagnostics (only when diagnostics exist):

```text
Edited src/auth.ts (lines 40-46).

Diagnostics in src/auth.ts:
  Line 44: Property 'userId' does not exist on type 'Session'.
```

---

## 6. Truncation & Spill Gate via Anvia `createMiddleware({ onToolOutput })`

### Anti-Pattern (Returning `JSON.stringify(...)` from `onToolOutput`)

```ts
return JSON.stringify({
  type: "file_reference",
  reason: "tool_output_too_large",
  chars: result.length,
  path,
});
```

### Canonical Anvia Plain-Text Output Middleware

```ts
import { writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createMiddleware } from "@anvia/core/tool";

const MAX_OUTPUT_CHARS = 32_000;
const PREVIEW_CHARS = 2_000;

export const plainTextOutputGate = createMiddleware({
  async onToolOutput({ toolName, result, internalCallId }) {
    if (result.length <= MAX_OUTPUT_CHARS) {
      return undefined;
    }

    const spillPath = join(tmpdir(), `${toolName}-${internalCallId}.txt`);
    await writeFile(spillPath, result, "utf8");

    return [
      result.slice(0, PREVIEW_CHARS),
      "",
      `[Output from ${toolName} truncated: ${result.length} chars exceeded ${MAX_OUTPUT_CHARS}-char limit.]`,
      `Full output saved to ${spillPath}. Inspect targeted ranges with read_file or narrow the query.`,
    ].join("\n");
  },
});
```

## Valid Exceptions (Do Not Flag)

1. **External `@anvia/mcp` tools:** Registered via `Agent.mcpServers`, where upstream `CallToolResult` payloads are externally controlled.
2. **Outer Anvia transport/stream envelopes:** `ToolResultEventPayload` / `{ type: "tool-result", output }` is JSON by runtime contract; only audit the inner LLM-facing `output` value.
3. **Multimodal `ToolOutput.content(...)`:** Valid when returning images, PDFs, or file parts alongside plain-text parts.
4. **JSON source files returned by `read_file`:** Line-numbered text of a `.json` file (`00001| {`) is plain-text framed file content.
