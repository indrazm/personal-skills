---
name: oxlint-setup
description: Sets up and maintains the standard Bun + oxlint + oxfmt configuration and custom 14-rule JS plugin (no-comments, no-barrel-file, no-atom-import, no-base-ui-outside-ui, no-native-primitives, padded-if, no-array-filter-map, no-module-mocking, and more). Use when bootstrapping linting in a repository, migrating from ESLint/Prettier to oxlint/oxfmt, or adding custom oxlint rules.
---

# Oxlint Standard Setup

Install and maintain the standard strict `oxlint` + `oxfmt` configuration and custom 14-rule JS plugin (`zstack/*`) bundled in `assets/oxlint/`.

## When to Use

- Bootstrapping linting and formatting in a new TypeScript / Bun repository
- Migrating an existing repo from ESLint/Prettier to `bun lint` (`oxlint`) and `bun fmt` (`oxfmt`)
- Adding, auditing, or testing custom JS lint rules in `tooling/oxlint/`

## Bundled Assets

- `assets/.oxlintrc.json` — Strict baseline (`correctness`, `suspicious`, `perf` = `error`) with `typescript`, `unicorn`, `oxc`, `import`, and all 14 `zstack/*` custom rules.
- `assets/.oxfmtrc.json` — Standard ignore patterns for `bun fmt`.
- `assets/oxlint/` — Complete JS plugin (`plugin.mjs`), shared AST helpers (`shared/`), Bun test harness (`testing/lint.mjs`), and all 14 rules with unit tests (`rules/*.mjs`, `rules/*.test.mjs`):
  - **Architecture & UI:** `no-atom-import`, `no-barrel-file`, `no-base-ui-outside-ui`, `no-native-primitives`
  - **Code hygiene & style:** `no-comments`, `padded-if`, `no-conditional-spread`
  - **Type safety & performance:** `no-array-filter-map`, `no-chained-type-assertions`, `no-reduce-accumulator-copy`, `no-reflect-apply`, `no-reflect-get`, `no-unknown-type-aliases`
  - **Testing discipline:** `no-module-mocking`

## Workflow

Resolve `<skill-dir>` to the directory containing this `SKILL.md`.

### Step 1: Scaffold Config & Plugin

Run `scripts/apply-oxlint.sh` against the target repository (skips existing files unless `--force` is passed):

```bash
bash <skill-dir>/scripts/apply-oxlint.sh --repo .
```

This installs:
- `tooling/oxlint/` (plugin, 14 rules, unit tests, shared helpers)
- `.oxlintrc.json`
- `.oxfmtrc.json`

### Step 2: Tailor to Repository Layout

Inspect the target repo and adjust `.oxlintrc.json` if needed:

- Add repo-specific generated paths to `ignorePatterns` (keep UI primitives directory such as `packages/ui/src` or `src/components` ignored if wrapping native HTML elements).
- For backend-only repos without React/Base UI/Jotai, keep the rules enabled (they are no-ops without matching files) or disable UI-only rules explicitly if requested.
- Wire root `package.json` scripts:
  ```json
  {
    "scripts": {
      "lint": "bun lint",
      "lint:fix": "bun lint --fix",
      "format": "bun fmt",
      "format:check": "bun fmt --check"
    }
  }
  ```

### Step 3: Verify Rules & Codebase

1. Run the custom rule unit test suite:
   ```bash
   bun test tooling/oxlint
   ```
2. Run the linter and formatter check across the repo:
   ```bash
   bun lint && bun fmt --check
   ```
3. Fix any surfaced violations at the root rather than weakening rules.

## Red Flags

- Weakening or disabling rules in `.oxlintrc.json` to silence real violations instead of fixing code
- Adding a new custom rule to `tooling/oxlint/rules/` without a co-located `*.test.mjs` file
- Keeping ESLint or Prettier configs alongside `oxlint`/`oxfmt` after migration completes

## Gotchas

- `zstack/no-chained-type-assertions` is intentionally relaxed only for test files (`**/*.test.ts`, `**/*.test.tsx`, `e2e/**`, `**/testing/**`) via `overrides` in `.oxlintrc.json`.
- `zstack/no-comments` preserves tool directives (`@ts-*`, `oxlint-disable`, `/// <reference>`).
