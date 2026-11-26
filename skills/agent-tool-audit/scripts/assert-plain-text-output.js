#!/usr/bin/env node
/**
 * Invariant check for Anvia (@anvia/core) agent tool outputs.
 *
 * Accepts:
 *  - A raw string returned by a `createTool` handler or `onToolOutput` middleware
 *  - A raw JS value returned by `tool.call(args)` (rejects plain JSON objects/arrays)
 *  - An Anvia `RichToolOutput` created by `ToolOutput.content([...])`
 *  - An Anvia `NormalizedToolOutput` (`{ type: "text" | "json" | "content" | "error-text" | "error-json", value }`)
 *  - An Anvia `ToolResultEventPayload` (`{ type: "tool_result", toolName, output, result }`)
 *
 * Usage in Anvia tool test suites (Vitest / Bun / Node):
 *   import { assertPlainTextToolOutput } from './assert-plain-text-output.js';
 *   const out = await grepTool.call({ query: "Agent" });
 *   assertPlainTextToolOutput("grep", out);
 *
 * Usage as a CLI check:
 *   node assert-plain-text-output.js --tool grep --file sample-output.txt
 *   cat sample-output.txt | node assert-plain-text-output.js --tool read_file
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ANVIA_RICH_TOOL_OUTPUT = Symbol.for("anvia.tool-output.content");
const LINE_NUMBER_PREFIX_RE = /^(?:\d+\|\s?|L\d+:\s?|\s*\d+:\s?)/;
const DEFAULT_MAX_BYTES = 64 * 1024;
const DEFAULT_MAX_LINES = 2500;
const READ_TOOL_NAMES = new Set(["read", "read_file", "view_file"]);

/**
 * Determine whether a string is a raw top-level JSON object or array.
 * Line-numbered JSON files (e.g. `00001| {`) will not match because their
 * prefix makes JSON.parse fail cleanly.
 *
 * @param {string} text
 * @returns {boolean}
 */
export function isRawJsonContainer(text) {
  const trimmed = text.trim();
  if (!trimmed) return false;
  const first = trimmed[0];
  const last = trimmed[trimmed.length - 1];
  const looksObject = first === "{" && last === "}";
  const looksArray = first === "[" && last === "]";
  if (!looksObject && !looksArray) return false;

  try {
    const parsed = JSON.parse(trimmed);
    return parsed !== null && typeof parsed === "object";
  } catch {
    return false;
  }
}

function isPlainRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isRichToolOutput(value) {
  return (
    typeof value === "object" &&
    value !== null &&
    value[ANVIA_RICH_TOOL_OUTPUT] === true &&
    Array.isArray(value.content)
  );
}

function isNormalizedToolOutput(value) {
  if (!isPlainRecord(value) || typeof value.type !== "string") return false;
  return (
    value.type === "text" ||
    value.type === "error-text" ||
    value.type === "json" ||
    value.type === "error-json" ||
    value.type === "content" ||
    value.type === "execution-denied"
  );
}

function isToolResultEventPayload(value) {
  return (
    isPlainRecord(value) &&
    value.type === "tool_result" &&
    typeof value.toolName === "string" &&
    "output" in value
  );
}

function checkTextString(toolName, text, { allowJson, requireLineNumbers, maxBytes, maxLines }) {
  const violations = [];

  if (!allowJson && isRawJsonContainer(text)) {
    violations.push(
      `Tool "${toolName}" returned a raw serialized JSON object/array to the LLM context. Format as compact plain text and move UI/telemetry fields to lifecycle, observability, or emitStreamEvent.`
    );
  }

  const byteLength = Buffer.byteLength(text, "utf8");
  if (Number.isFinite(maxBytes) && byteLength > maxBytes) {
    violations.push(
      `Tool "${toolName}" output is ${byteLength} bytes, exceeding the ${maxBytes}-byte truncation guardrail.`
    );
  }

  const lines = text.length === 0 ? [] : text.split(/\r?\n/);
  if (Number.isFinite(maxLines) && lines.length > maxLines) {
    violations.push(
      `Tool "${toolName}" output has ${lines.length} lines, exceeding the ${maxLines}-line truncation guardrail.`
    );
  }

  if (requireLineNumbers && text.trim().length > 0) {
    const firstNonEmptyLine = lines.find((line) => line.trim().length > 0) ?? "";
    if (!LINE_NUMBER_PREFIX_RE.test(firstNonEmptyLine)) {
      violations.push(
        `Read tool "${toolName}" output lacks 1-based line-number anchoring (expected prefix like "00001| " or "L1:"). First line: ${JSON.stringify(firstNonEmptyLine.slice(0, 80))}`
      );
    }
  }

  return violations;
}

/**
 * Validate an Anvia tool's LLM-facing output and return all violations.
 *
 * @param {string} toolName
 * @param {unknown} output
 * @param {object} [options]
 * @param {boolean} [options.allowJson=false] Exempt external/MCP tools that legitimately return JSON.
 * @param {boolean} [options.requireLineNumbers] Require 1-based line-number prefixes (defaults true for read tools).
 * @param {number} [options.maxBytes=65536] Hard byte budget for a single tool response.
 * @param {number} [options.maxLines=2500] Hard line budget for a single tool response.
 * @returns {string[]} List of violation messages (empty if valid).
 */
export function validatePlainTextToolOutput(toolName, output, options = {}) {
  if (isToolResultEventPayload(output)) {
    return validatePlainTextToolOutput(toolName || output.toolName, output.output, options);
  }

  const resolvedOptions = {
    allowJson: options.allowJson ?? false,
    requireLineNumbers:
      options.requireLineNumbers ?? READ_TOOL_NAMES.has(toolName.toLowerCase()),
    maxBytes: options.maxBytes ?? DEFAULT_MAX_BYTES,
    maxLines: options.maxLines ?? DEFAULT_MAX_LINES,
  };

  if (typeof output === "string") {
    return checkTextString(toolName, output, resolvedOptions);
  }

  if (isRichToolOutput(output)) {
    const textParts = output.content
      .filter((part) => isPlainRecord(part) && part.type === "text" && typeof part.text === "string")
      .map((part) => part.text);
    return checkTextString(toolName, textParts.join("\n"), resolvedOptions);
  }

  if (isNormalizedToolOutput(output)) {
    if (output.type === "text" || output.type === "error-text") {
      return checkTextString(toolName, String(output.value ?? ""), resolvedOptions);
    }

    if (output.type === "content" && Array.isArray(output.value)) {
      const textParts = output.value
        .filter((part) => isPlainRecord(part) && part.type === "text" && typeof part.text === "string")
        .map((part) => part.text);
      return checkTextString(toolName, textParts.join("\n"), resolvedOptions);
    }

    if (output.type === "execution-denied") {
      return [];
    }

    if (output.type === "json" || output.type === "error-json") {
      if (resolvedOptions.allowJson) return [];
      return [
        `Tool "${toolName}" produced an Anvia "${output.type}" output, which serializes as raw JSON into the LLM context. Return a formatted string (or ToolOutput.content(...)) instead.`,
      ];
    }
  }

  if (resolvedOptions.allowJson && output !== null && typeof output === "object") {
    return [];
  }

  return [
    `Tool "${toolName}" returned ${output === null ? "null" : Array.isArray(output) ? "an array" : typeof output} instead of a plain-text string (Anvia will serialize non-string JSON values with JSON.stringify).`,
  ];
}

/**
 * Throw an Error if the Anvia tool output violates plain-text harness invariants.
 *
 * @param {string} toolName
 * @param {unknown} output
 * @param {Parameters<typeof validatePlainTextToolOutput>[2]} [options]
 */
export function assertPlainTextToolOutput(toolName, output, options = {}) {
  const violations = validatePlainTextToolOutput(toolName, output, options);
  if (violations.length > 0) {
    throw new Error(
      `Anvia tool output audit failed for "${toolName}":\n- ${violations.join("\n- ")}`
    );
  }
}

function parseArgs(argv) {
  const args = {
    tool: "unknown",
    file: null,
    allowJson: false,
    requireLineNumbers: undefined,
    maxBytes: DEFAULT_MAX_BYTES,
    maxLines: DEFAULT_MAX_LINES,
    help: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    if (flag === "-h" || flag === "--help") {
      args.help = true;
    } else if (flag === "--tool" && argv[i + 1]) {
      args.tool = argv[++i];
    } else if (flag === "--file" && argv[i + 1]) {
      args.file = argv[++i];
    } else if (flag === "--allow-json") {
      args.allowJson = true;
    } else if (flag === "--require-line-numbers") {
      args.requireLineNumbers = true;
    } else if (flag === "--no-line-numbers") {
      args.requireLineNumbers = false;
    } else if (flag === "--max-bytes" && argv[i + 1]) {
      args.maxBytes = Number(argv[++i]);
    } else if (flag === "--max-lines" && argv[i + 1]) {
      args.maxLines = Number(argv[++i]);
    } else {
      throw new Error(`Unknown or incomplete option: ${flag}`);
    }
  }

  return args;
}

function printUsage() {
  console.log(`Usage:
  assert-plain-text-output.js --tool <name> [--file <path>] [--allow-json]
                              [--require-line-numbers | --no-line-numbers]
                              [--max-bytes <N>] [--max-lines <N>]

Reads tool output from --file or stdin and exits non-zero if any Anvia
plain-text tool-output invariant fails.`);
}

async function runCli() {
  let args;
  try {
    args = parseArgs(process.argv.slice(2));
  } catch (err) {
    console.error(`Error: ${err.message}`);
    printUsage();
    process.exit(1);
  }

  if (args.help) {
    printUsage();
    process.exit(0);
  }

  const content = args.file
    ? fs.readFileSync(args.file, "utf8")
    : fs.readFileSync(0, "utf8");

  const violations = validatePlainTextToolOutput(args.tool, content, {
    allowJson: args.allowJson,
    requireLineNumbers: args.requireLineNumbers,
    maxBytes: args.maxBytes,
    maxLines: args.maxLines,
  });

  if (violations.length > 0) {
    console.error(`FAIL (${args.tool}):`);
    for (const violation of violations) {
      console.error(`  - ${violation}`);
    }
    process.exit(1);
  }

  console.log(`PASS (${args.tool})`);
}

const isDirectExecution =
  process.argv[1] &&
  path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isDirectExecution) {
  runCli();
}
