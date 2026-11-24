---
name: engineering-decision
description: Records, updates, and supersedes engineering and architectural decisions in docs/decision/ as numbered Markdown files (ADRs) with bidirectional lifecycle tracking. Use when making technical trade-offs, choosing architectures, databases, or libraries, changing or canceling a prior decision, or auditing past architectural choices.
---

# Engineering Decision

Record significant engineering and architectural decisions as zero-padded sequential Markdown files under `docs/decision/` while maintaining full awareness of prior decisions and bidirectional lifecycle links.

## When to Use

- Making a technical, architectural, data-model, or tooling decision
- Evaluating trade-offs between multiple engineering approaches
- Reversing, canceling, deprecating, or superseding a prior decision
- Checking existing architectural constraints before proposing a design change

## Directory & Naming Convention

Store every decision record in `docs/decision/` using a 4-digit zero-padded sequence number and a descriptive kebab-case slug:

```text
docs/decision/
├── 0001-use-postgresql-for-primary-storage.md
├── 0002-adopt-cursor-based-pagination.md
└── 0003-migrate-auth-to-short-lived-jwt.md
```

- Always inspect `docs/decision/` before creating a new record so you know every active decision and the next sequence number.
- Never reuse numbers from `Superseded`, `Deprecated`, or `Canceled` records.

## Lifecycle & Bidirectional Awareness Rules

Every decision action MUST account for existing records in `docs/decision/`:

1. **Inspect existing decisions first:** Run `scripts/adr.sh list` (or read all files in `docs/decision/`) before proposing or writing a new decision so you do not contradict active decisions or repeat rejected options without new context.
2. **Use strict status values:**
   - `Proposed` — Under discussion, not yet finalized.
   - `Accepted` — Active decision currently in effect.
   - `Superseded` — Replaced by a newer decision (must link forward).
   - `Deprecated` — No longer recommended, pending replacement or removal.
   - `Canceled` — Withdrawn or rejected before or after implementation (document why).
3. **Maintain bidirectional links on status changes:**
   - In the **new** record, link back to the prior record (`Supersedes: [0001-...](./0001-...)` or `Related: [0002-...](./0002-...)`).
   - In the **prior** record, update `Status` to `Superseded` (or `Deprecated` / `Canceled`) and set `Superseded by: [0004-...](./0004-...)` with a brief reason. Never delete historical decision files.

## Execution Workflow

Resolve `<skill-dir>` to the directory containing this `SKILL.md`.

1. **List existing decisions:**
   ```bash
   bash <skill-dir>/scripts/adr.sh list
   ```
   Read any active, proposed, or overlapping decision files in full.
2. **Check for conflicts or supersession:** Determine whether the new decision extends, supersedes, deprecates, or cancels an existing record.
3. **Scaffold the next numbered ADR:**
   ```bash
   bash <skill-dir>/scripts/adr.sh new "Use PostgreSQL for primary storage"
   ```
   Fill in all sections (`Context`, `Decision`, `Alternatives Considered`, `Consequences`) following `references/adr-template.md`.
4. **Update affected prior records:** If replacing, deprecating, or canceling an older decision, update its metadata header and add a brief status note (see `references/adr-template.md` for the exact format).
5. **Update index if present:** If `docs/decision/README.md` exists, add the new entry and sync any changed statuses.

## Red Flags

- Recording an architectural decision only in chat or inline code comments instead of `docs/decision/`
- Creating a new ADR without listing and reading existing files in `docs/decision/`
- Leaving a replaced decision marked `Accepted`
- Deleting a canceled or superseded ADR file instead of updating its status
- Using vague slugs like `0004-update.md` instead of a descriptive title

## Gotchas

- Preserve historical records as immutable context (only update their status metadata and add a short status note when superseded or canceled).
- Keep each ADR scoped to a single decision; split unrelated architectural choices into separate numbered files.
