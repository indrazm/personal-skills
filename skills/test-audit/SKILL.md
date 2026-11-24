---
name: test-audit
description: Audits, gates, and prunes unit and E2E tests so suites only keep meaningful, critical behavioral proof. Rejects on-screen text/copy assertions, string change-detector tests, duplicate layer coverage, implementation-coupled mocks, and test-only production seams. Use when writing, modifying, reviewing, or cleaning up unit or E2E tests.
---

# Test Audit

Keep unit and E2E test suites lean, trustworthy, and strictly focused on critical, meaningful behavior. Actively reject and delete nonsense tests that add noise without catching real regressions.

## Core Principles

- **Meaningful proof only:** Every test must protect critical behavior, an invariant, or a user-facing contract that actually matters if it breaks.
- **No on-screen text or string-change tests:** Do NOT test static UI copy, headings, labels, tooltips, or trivial string formatting. Changing wording on a screen must never fail a test.
- **Only test what is critical:** Prioritize high-impact flows, state invariants, business rules, data integrity, and failure boundaries over exhaustive coverage metrics.
- **Delete nonsense tests:** Remove change-detector tests, duplicate layer replays, mock-echoing tests, and the test-only production seams they forced into the codebase.
- **Delete tests when deleting code:** When production code or a feature is removed, delete its corresponding tests cleanly—NEVER write a new test asserting that the deleted code, flag, element, or behavior is gone.

## Authoring Gate (Mandatory Before Adding or Keeping Any Test)

Before writing or retaining a unit or E2E test, answer all four questions:

1. **What critical observable behavior, invariant, or independent contract does this protect?**
2. **What credible real-world bug or regression would make this test fail?**
3. **Why does existing proof miss it?** Assign one primary owner at the strongest boundary. Never replay the same check across unit, integration, and E2E layers unless a layer introduces distinct transport, persistence, or lifecycle risk. Extend existing parameterized tables or shared fixtures instead of duplicating setup.
4. **Does it require a test-only export, flag, wrapper, or injection seam with no production caller?** If yes, move the proof to a real boundary instead of polluting production code.

Additional authoring rules:

- Behavior-preserving refactors and UI copy edits must never break tests.
- Regression tests must fail before the fix for the exact intended reason and pass after the fix (report explicitly if baseline reproduction is unavailable).
- One owner regression test covers one bug; do not duplicate it across every layer the bug crossed.

## Unit vs. E2E Scope Rules

### Unit Tests

Write unit tests ONLY for meaningful, non-trivial logic:

- Core domain calculations, state transitions, invariants, parsers, validators, authorization rules, and edge-case/error handling.
- Skip trivial getters/setters, pass-through wrappers, static constants, literal string returns, and framework glue.

### E2E Tests

Write E2E tests ONLY for critical end-to-end user journeys:

- Authentication, permissions/isolation, payments/billing, core create/update/delete persistence, and multi-step critical workflows.
- Assert **real outcomes**: persisted data, API side effects, navigation/route state, access control, and interactive state changes (using stable semantic roles or test IDs).
- Never assert static screen copy, placeholder phrasing, marketing text, or exact wording.

## Nonsense & Junk Patterns to Reject or Delete

Reject in new changes and remove during audits (see `references/audit-workflow.md` for the complete catalog):

- **Screen-text & string tests:** Asserting static UI copy, error prose wording, labels, or snapshot diffs of rendered text.
- **Change detectors:** Tests coupled to internal implementation, private helpers, DOM/CSS structure, or exact mock call shapes/order.
- **Self-proving & vacuous tests:** Assertion-free smoke runs, self-comparisons, subject-generated expected values, or mocks implementing the exact behavior being asserted.
- **Duplicate contracts:** Re-testing the same rule in multiple unit suites or replaying shared helpers in every caller.
- **Copied inventories:** Mirroring static lists, exports, or config files line-for-line in assertions.
- **Deletion-proof tests:** Adding a new test to assert that removed code, deleted exports, deleted UI elements, or removed features no longer exist. When code is deleted, delete its tests—do not replace them with "confirm it was deleted" tests.
- **Test-only seams:** Production hooks, flags, exports, or wrappers invoked solely by tests.
- **Misleading tests:** Negative controls that pass on an unrelated guard, or test names claiming behavior the assertions never check.

## Retention Bar (Never Blindly Delete)

Always retain tests guarding critical contracts—slow or static does not mean disposable:

- Authorization, authentication, privacy, and security boundaries
- Data persistence, migrations, storage integrity, and concurrency/race invariants
- Public API, SDK, protocol, config, and schema contracts
- Critical end-to-end revenue or core user workflows
- Real regression tests with a clear failure mode

Treat baseline test failures as potential product bugs first: reproduce and fix the owning code rather than deleting a failing test.

## Audit & Pruning Workflow

- **Targeted cleanup or PR review:** Read `references/audit-workflow.md` before deleting any existing test; verify full owners, callers, and remaining coverage first, and delete obsolete test-only production seams alongside removed tests.
- **Whole-subsystem pruning campaign:** Read `references/pruning-campaign.md` to run an evidence-backed, lane-by-lane audit with independent preservation review.

## Red Flags

- Adding tests solely to bump line/branch coverage percentages
- Writing E2E assertions against static text on the screen
- Updating string assertions every time UI copy changes instead of deleting the change-detector test
- Writing a new test to prove deleted code or a removed feature is gone instead of simply deleting the old tests
- Keeping duplicate unit + E2E tests for the exact same low-level validation
- Deleting a failing test without confirming whether it caught a real product bug
- Leaving orphaned test-only exports, fixtures, or helpers behind after deleting tests

## Gotchas

- Judge every test by its **assertions**, not its description—many tests with critical-sounding names actually assert nothing meaningful or test a mocked stub.
- Never optimize for raw deletion counts; remove low-value tests in coherent owner batches and verify surviving suites plus unused-code checks pass cleanly.
