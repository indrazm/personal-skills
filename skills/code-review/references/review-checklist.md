# Code Review Checklist

Use this reference during subagent code reviews to audit changes systematically across all five axes, propose concrete structural remedies, and evaluate change sizing.

## The Five-Axis Audit

### 1. Correctness

- Does the implementation satisfy every requirement in the spec or task description?
- Are boundary and failure paths handled (null/undefined, empty inputs, timeouts, partial failures, off-by-one boundaries)?
- Do tests assert observable behavior rather than private implementation details, and would they fail on a regression?
- Are there race conditions, non-atomic state updates, or stale-cache inconsistencies?

### 2. Readability & Simplicity

- Are identifiers clear and aligned with repository naming conventions?
- Is control flow direct without deeply nested branches, callbacks, or chained ternaries?
- Do new abstractions earn their complexity (avoid generalizing before the third concrete use case)?
- Are dead-code artifacts removed (unused variables, commented-out blocks, obsolete compatibility shims)?
- Are new conditionals placed in an appropriate helper/policy instead of bolted onto an unrelated flow?

### 3. Architecture

- Does the change follow established project conventions and preserve module boundaries?
- Do dependencies flow in one direction without introducing cycles?
- Does a refactor reduce cognitive load (fewer concepts to track) rather than merely moving code around?
- Is feature-specific logic kept out of shared/core modules?
- Are type boundaries explicit rather than masked by unchecked casts, `any`, or silent fallbacks?

### 4. Security

- Is untrusted and external input validated and sanitized at system boundaries?
- Are secrets, tokens, and credentials absent from source files, logs, and version control?
- Are authentication and authorization enforced on every protected path?
- Are database queries parameterized (no string interpolation) and outputs encoded against injection/XSS?
- Are newly added dependencies trustworthy and free of known vulnerabilities?

### 5. Performance

- Are there N+1 queries, unbounded loops, or unpaginated data fetches?
- Are synchronous blocking calls used on async or request-handling paths?
- Are there avoidable UI re-renders, missing memoization on expensive work, or large allocations in hot paths?

## Structural Remedies

When reporting a structural issue, propose the exact refactoring move rather than merely labeling code "complex":

- Replace branching chains with a typed discriminated model or explicit dispatch map.
- Collapse duplicated branches into a single unified path.
- Separate orchestration (I/O, retries, wiring) from pure domain logic.
- Move feature-specific helpers out of shared packages into their owning module.
- Reuse an existing canonical utility instead of introducing a near-duplicate.
- Narrow types at boundaries so downstream null/type checks disappear.
- Remove pass-through wrappers that add indirection without clarifying intent.

## Change Sizing & Splitting

Evaluate whether the change is scoped cleanly for review:

- **~100 lines changed:** Ideal; reviewable in one pass.
- **~300 lines changed:** Acceptable for one cohesive logical change.
- **~1000+ lines changed:** Too large; recommend splitting (excluding pure file deletions or mechanical codemods).

Watch overall file growth (~1000 lines signals decomposition) and keep refactors separate from behavior changes. When recommending a split, suggest a concrete strategy:

- **Stacked:** Land a small foundational change first, then stack dependent changes on top.
- **By ownership:** Split files requiring different domain reviewers.
- **Horizontal:** Land interfaces/stubs first, followed by implementations and callers.
- **Vertical:** Slice a feature into smaller end-to-end deliverables.

## Dead Code & Dependency Hygiene

- List unreachable or unused code left behind by a refactor explicitly before deleting it.
- Prefer standard-library APIs and existing repo utilities over adding new packages.
- Inspect dependency upgrades individually via changelogs and lockfile diffs rather than blind bulk bumps.
