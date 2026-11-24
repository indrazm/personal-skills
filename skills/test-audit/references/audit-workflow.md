# Test Audit Workflow & Junk Pattern Catalog

Read this reference before removing or rewriting existing unit or E2E tests. Apply it together with the authoring gate in `SKILL.md`.

## Junk Patterns Catalog

Reject new occurrences and target existing occurrences for deletion unless the Retention Bar identifies a critical independent contract:

1. **On-screen copy & string tests (Unit & E2E):**
   - Asserting static headings, button text, helper copy, toast phrasing, or exact error prose when only the state/outcome matters.
   - Testing that changing a constant string or translation key renders the exact literal text.
   - Broad DOM/HTML/JSON snapshots that break on routine copy, layout, or styling edits.
2. **Vacuous & self-proving tests:**
   - Assertion-free probes ("renders without crashing" with no meaningful behavior asserted).
   - Self-comparisons, identity copiers, or expected values computed by the subject under test.
   - Mocks that re-implement the asserted logic or fabricate receipts, persistence, or ordering the real owner should produce.
3. **Implementation-coupled change detectors:**
   - Asserting exact internal helper call counts, argument shapes, or private method invocations when boundary behavior is already tested.
   - Asserting internal CSS class names, DOM nesting, or component state shape instead of observable user/API outcomes.
   - Source-text greps or exact import/export list checks that break on identifier-only refactors.
4. **Redundant layer & inventory duplication:**
   - Re-testing a shared helper inside every caller or plugin instead of once at the helper's owner.
   - Replaying identical low-level validation in both unit tests and slow E2E suites without distinct transport or persistence risk.
   - Copying static config/export manifests into tests that merely mirror production files.
5. **Broken negative controls & misnamed tests:**
   - Negative tests that pass because of an earlier unrelated guard (such as a missing fixture or validation error) rather than the intended boundary.
   - Tests whose names promise critical invariants that the inputs and assertions never actually exercise.
6. **Deletion-proof ("is deleted") tests:**
   - Tests added after removing code/features solely to assert that a deleted function, export, option, route, or UI element no longer exists. When removing code, remove its tests cleanly instead of cementing dead history into the test suite.
7. **Test-only production seams:**
   - Exports, parameters, flags, reset functions, or wrapper indirections added strictly to satisfy tests with zero production callers.

## Retention Bar

Do NOT delete tests that protect critical contracts:

- Authorization, access control, tenant isolation, privacy, and security invariants
- Database migrations, schema compatibility, persistence durability, and transaction boundaries
- Concurrency, idempotency, retry/deduplication, and ordering guarantees
- Public API, SDK, CLI, webhook, and wire-protocol contracts
- Critical E2E user flows (login/session lifecycle, checkout/billing, core state mutations persisted across reload)

When a test is slow or brittle because of bad setup (not because the contract is worthless), fix the boundary or fixture instead of deleting the contract. If a baseline test fails, verify whether it exposes a real product defect before touching the test.

## Candidate Evidence Checklist (Required Before Deletion)

Discovery must be read-only first. Before editing or deleting any test, inspect the full test file, the owning production module, callers, sibling suites, and git history, and record:

- **Target:** Exact file path and test name + what real failure (if any) it can detect.
- **Production seam check:** Non-test callers of any production export/hook/helper covered only by this test.
- **Remaining proof:** The stronger owner test that already covers the contract, or why no meaningful contract exists.
- **Why it exists:** Historical reason (if any) and what dead production/support code deleting it unlocks.
- **Verification command:** Focused command to validate the owning module and sibling suites.

If evidence is incomplete or uncertain, do NOT delete the test. Never replace a deleted junk test with another implementation-coupled test.

## Validation & Handoff

After removing or consolidating tests in coherent owner batches:

1. Remove any now-unused test-only production seams, dead fixtures, and orphaned helper files.
2. Run the owning unit and/or E2E suites and sibling suites to verify surviving coverage passes cleanly.
3. Run the repository's linter, type-checker, and dead-code/unused-export checks (if configured) to catch orphaned imports, dependencies, or support files.
4. Inspect diff stats (`git diff --numstat`) and report:
   - Junk categories and test-only seams removed
   - Critical contracts retained (and any false positives kept)
   - Verification commands executed and observed results
   - Production LOC delta vs. test/support LOC delta
   - Any real product defects discovered as follow-ups
