# Subsystem Test-Pruning Campaign

Use this workflow when auditing and pruning an entire subsystem's unit and E2E test surface in one coherent effort. Every lane follows the principles, junk-pattern rules, and retention bar in `SKILL.md` and `references/audit-workflow.md`. Complete each stage's exit criterion before starting the next.

## 1. Baseline

Record the subsystem's test and support line counts plus every in-scope unit and E2E test file's pass/fail status at a pinned base commit SHA. Separate baseline failures into their own list—they frequently expose real product bugs rather than stale tests.

**Done when:** Every in-scope test file has a recorded baseline result.

## 2. Partition into Owner Lanes

Split the test surface into **lanes** aligned with production ownership boundaries (for example: auth, billing, persistence, API transport, UI state, E2E journeys, shared harness)—never by arbitrary file prefixes.

**Done when:** Every unit test, E2E spec, and shared fixture owned by the subsystem belongs to exactly one lane.

## 3. Read-Only Per-Lane Ledger

Audit each lane in read-only mode (parallelizable across independent lanes). Read every test declaration in full—including parameterized tables—alongside its production owner, entry points, callers, and history. Assign every test declaration one mark plus a one-line evidence note:

- `R` (**Retain**): Name the critical contract and credible regression it catches.
- `F` (**Fix**): Retain the contract, but repair a broken or vacuous assertion (e.g., an E2E test asserting static screen copy instead of persisted state, or a negative control passing on the wrong guard).
- `C` (**Consolidate**): Name the stronger boundary owner or shared table absorbing the assertion first.
- `D` (**Delete**): Name the stronger remaining proof, or explain why no meaningful contract exists (e.g., string change-detector or mock echo).

Judge every test strictly by its assertions, never by its title.

**Done when:** Every declaration in the lane has a mark and concrete evidence.

## 4. Layer Plan & Keeper Selection

Run a second read-only pass over the ledger to identify redundant **layers** (for example, mocked unit suites replaying rules already proven by a real boundary or E2E suite, or E2E specs checking low-level copy/formatting). Name one **keeper** suite per contract—preferring the real boundary over mocked collaborators—and list retired files, migrated assertions, and unlocked test-only production seams.

**Done when:** Every lane plan names retired files, keepers per contract, migrated assertions, and seams to remove.

## 5. Lane-by-Lane Cutover

Apply edits one lane at a time; serialize shared harness/fixture edits under one owner. Remove unlocked test-only production seams (injection hooks, reset exports, unused helpers) in the same lane. Record recurring anti-patterns discovered during pruning in the repo's `AGENTS.md` so junk tests do not return.

**Done when:** Every lane plan is applied and all keeper unit/E2E suites pass.

## 6. Independent Preservation Review & Mutation Check

Have an independent review subagent compare deleted coverage against the surviving keepers per boundary group to catch:
- Critical contracts that lost their only proof
- Unreachable or vacuous assertions in new/consolidated keepers

For every restored contract, introduce one deliberate **mutation** in the production owner, verify the keeper fails, and revert the mutation byte-for-byte.

**Done when:** Every real gap is restored with a caught mutation or rejected with source evidence.

## 7. Product Defects

Any baseline failure that survives into a keeper is a real bug. Fix it at the owning production layer in a separate commit, proving the fix with a failing control run (before fix) and passing run (after fix). Log unrelated defects as follow-ups rather than mixing them into the pruning diff.

**Done when:** Every repaired defect has control and post-fix proof on the same harness.

## 8. Reconcile & Handoff

Before shipping, run full unit/E2E keeper suites plus dead-code/unused-export checks and report:

- Baseline vs. final test/support LOC (with production LOC delta reported separately)
- Lanes audited, retired layers, and keeper suites
- Preservation gaps caught and verified via mutation
- Product defects fixed or filed as follow-ups
