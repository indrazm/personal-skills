# ADR Template & Lifecycle Reference

## Canonical Decision Record Template

Create each decision file at `docs/decision/<NNNN>-<kebab-case-slug>.md`:

```markdown
# NNNN: Meaningful Decision Title

- **Date:** YYYY-MM-DD
- **Status:** Accepted
- **Supersedes:** None
- **Superseded by:** None
- **Related:** None

## Context

Describe the problem, system constraints, and relevant prior decisions.

## Decision

State the chosen approach clearly and explain why it was selected.

## Alternatives Considered

- **Option A:** Summary of the option and why it was rejected.
- **Option B:** Summary of the option and why it was rejected.

## Consequences

- **Positive:** Expected benefits and enabled capabilities.
- **Negative / Trade-offs:** Costs, operational complexity, or follow-up work required.
```

## Bidirectional Supersession Example

When `0004-switch-to-keyset-pagination.md` replaces `0002-adopt-offset-pagination.md`:

### In the new ADR (`0004-switch-to-keyset-pagination.md`)

```markdown
- **Date:** 2026-04-12
- **Status:** Accepted
- **Supersedes:** [0002: Adopt offset pagination](./0002-adopt-offset-pagination.md)
- **Superseded by:** None
- **Related:** None
```

### In the prior ADR (`0002-adopt-offset-pagination.md`)

Update only the status header and append a concise status note; preserve the original rationale intact:

```markdown
- **Date:** 2025-11-03
- **Status:** Superseded
- **Supersedes:** None
- **Superseded by:** [0004: Switch to keyset pagination](./0004-switch-to-keyset-pagination.md)
- **Related:** None
```

Optional brief note directly beneath the metadata list:

```markdown
> **Status Note (2026-04-12):** Superseded by [0004](./0004-switch-to-keyset-pagination.md) because deep offset queries degraded beyond 100k rows.
```
