---
name: formal-verification
description: Guides selective, cost-aware formal verification using Dafny (with clear boundaries for TLA+/Quint and cheaper testing layers). Enforces an authoring gate, production integration modes to prevent model-code drift, anti-vacuity/anti-cheating soundness checks via scripts/verify-dafny.sh, and real-world state-machine proof patterns. Use when writing, auditing, or debugging .dfy specifications and proofs, or when formally verifying high-blast-radius invariants, financial/ledger rules, authorization logic, or state machines.
---

# Formal Verification

Test everything critical, and formally verify only the small, high-blast-radius core where a single missed edge case would cause irreversible damage. Keep proofs sound, non-vacuous, and tightly coupled to production code.

## Assurance Escalation Ladder (When to Use — and When Not To)

Formal proofs have real maintenance cost: every code change requires updating proofs. Always reach for the cheapest layer that can enforce the guarantee:

1. **Types & schema constraints:** Make illegal states unrepresentable (exhaustive unions, branded types, DB constraints). Cheapest; zero proof upkeep.
2. **Targeted unit & integration tests:** Cover known edge cases, regressions, and boundary contracts.
3. **Property-based testing / fuzzing:** Explore thousands of randomized or adversarial inputs and state sequences cheaply.
4. **Formal verification (Dafny / model checking):** Mathematical proof across *all* reachable inputs or states—reserve for invariants where "it passed tests" is still unacceptable.

### Good Candidates vs. Skip

- **Verify:** Financial/ledger arithmetic and conservation rules, authorization/isolation policies, locking/escrow/idempotency state machines, cryptographic/encoding boundaries, and small shared core algorithms many subsystems depend on.
- **Skip:** UI components, CRUD/glue code, external API wrappers, prototypes, and volatile product logic that changes weekly.

### Tool Boundaries (Dafny-First)

- **Use Dafny (default)** for sequential state machines, domain invariants, ledger/conservation rules, permissions, bounds/overflow safety, parsers, and pure algorithms (compiles to JS/TS, Go, Python, C#, Java).
- **Use TLA+ or Quint instead of Dafny** for interleaved concurrency, distributed consensus, async race conditions, retry/timeout protocols, and liveness ("eventually succeeds") properties.

## Authoring Gate (Mandatory Before Writing Any Spec)

Before creating a `.dfy` file or proving a property, answer all four questions:

1. **Blast radius:** If this property were false in production, what is the worst real damage? (If the answer is not money loss, data corruption, security/isolation bypass, deadlock, or silent invariant violation, stop and use types or tests.)
2. **Why cheaper layers miss it:** Why can't static types, unit tests, or property-based tests provide sufficient confidence?
3. **Pure core isolatability:** Can the logic be isolated into a small, stable, I/O-free kernel with zero framework dependencies?
4. **Production bridge:** Which integration mode below prevents the verified model from silently drifting away from production code?

## Production Integration Modes (Closing the Model–Code Gap)

Never leave a standalone model in `dafny/` disconnected from production code. Choose one explicit bridge before writing the spec:

- **Mode A — Compiled Verified Core (Zero Drift):** Compile the verified Dafny module directly (`dafny build` / `dafny translate`) into the target runtime (`js`, `go`, `py`, `cs`, `java`) and import it as the pure domain kernel. Best for small, self-contained rules.
- **Mode B — Executable Oracle (Differential Testing):** Compile the Dafny model as a test oracle and run property-based or fuzz tests asserting that the production implementation matches the verified model across randomized inputs and multi-step state sequences.
- **Mode C — Design-Time Spec + Runtime Guards:** Verify a tricky state machine or protocol upfront, document trusted assumptions (e.g., via an ADR), and mirror the critical preconditions and invariants as runtime assertions in production code.

## Core Specification & Proof Rules

Read `references/dafny-patterns.md` for complete Dafny 4 templates. Follow these principles on every proof:

1. **Spec first, body second:** Write `requires` and `ensures` (and `Valid` invariants) in plain words first, then in Dafny, before implementing the body.
2. **Contract ownership:** `requires` is the caller's obligation; `ensures` is the callee's promise. If a call fails to verify, check whether the caller violated a `requires` before touching the callee.
3. **Modular verification:** Dafny checks each method using only the contracts (`requires`/`ensures`) of called methods, never their bodies. If a downstream fact matters, state it in an `ensures` or `invariant`.
4. **Prefer a pure functional core:** Model state with immutable `datatype`, `map`, `seq`, and pure `function`/`predicate`. Avoid mutable classes/arrays (`reads`/`modifies` framing) unless in-place mutation itself is what you are proving.
5. **Use the state-machine inductive pattern:** For real-world systems, define `State`, `ghost predicate Valid(s)`, `Init` (proves `Valid(s0)`), and `Step(s, action)` (preserves `Valid(s) ==> Valid(s')` plus two-state safety/conservation properties like `Total(s') == Total(s)`).
6. **Separate ghost specs from compiled code (Dafny 4 syntax):** Use `ghost function` / `ghost predicate` to define meaning (erased at compile time, zero runtime cost) and compiled `function` / `method` for fast execution; prove the implementation matches the ghost spec.
7. **Model real numeric bounds:** Dafny `int` is unbounded. If production uses `int64`, `uint64`, floats, or minor units (cents/bps), explicitly enforce bounds (`newtype` or `0 <= x <= MAX`) so overflow and rounding bugs cannot slip past the proof.
8. **Loops need invariants and termination:** Every loop needs an `invariant` true before entry, preserved on every pass, and strong enough that `invariant && !guard ==> ensures`. Always include index bounds (`0 <= i <= n`) and add `decreases` when Dafny cannot infer termination.
9. **Prove one property at a time:** Start with the single highest-risk safety or conservation invariant; add the next only after the first verifies cleanly.

## Anti-Cheating & Anti-Vacuity Gate (Mandatory Before Claiming Verified)

A passing `dafny verify` proves nothing if the proof cheats or is vacuous. Every verified module MUST satisfy all four rules:

1. **Zero unsound shortcuts:** Never add `assume`, `{:axiom}`, `{:verify false}`, `{:only}` / `@VerifyOnly`, or bodyless lemmas/methods to silence the verifier. (`{:extern}` is allowed only at an explicit FFI boundary and must be documented.)
2. **Never game the contract:** Never weaken `ensures` to match buggy code, and never over-strengthen `requires` to exclude valid production callers. Fix the code or fix an objectively wrong spec.
3. **Include a witness lemma:** Write a concrete `lemma` calling the verified function/method with realistic concrete inputs and asserting the concrete expected output. This proves `requires` is satisfiable (not contradictory) and `ensures` actually constrains the result.
4. **Falsification sanity check:** Ask *"Could a wrong implementation still satisfy this spec?"* Verify (mentally or via a temporary mutation) that removing a critical check or returning a bogus value causes verification to fail.

## Execution Workflow

Resolve `<skill-dir>` to the directory containing this `SKILL.md`.

1. **Pass the Authoring Gate:** Confirm blast radius, escalation ladder, pure core boundary, and Production Integration Mode (A, B, or C).
2. **State the property first:** Write the target safety, correctness, or conservation property in plain language before writing Dafny.
3. **Model and prove incrementally:** Follow `references/dafny-patterns.md` (prefer immutable `datatype` + state-machine invariants + witness lemmas). Keep verification files isolated under a dedicated directory (e.g., `verification/` or `dafny/`).
4. **Debug failures systematically:** If verification fails or times out, read `references/proof-debugging.md` to classify whether it is an implementation bug, wrong spec, missing hint/invariant, or Z3 resource/trigger issue. Never add `assume` to move past a failure.
5. **Run the soundness & verification gate:**
   ```bash
   bash <skill-dir>/scripts/verify-dafny.sh <path-to-dfy-dir-or-files>
   ```
   This runs `dafny audit` (enforcing **0 findings**—note `dafny audit` exits `0` even with findings!), scans for banned escapes (`assume`, `{:axiom}`, `{:verify false}`, `{:only}`), and runs `dafny verify --warn-shadowing`.
6. **Connect and verify the bridge:** Wire the chosen Production Integration Mode (compile target, run differential/PBT oracle tests, or verify runtime invariant guards) and confirm production tests pass.

## Red Flags

- Writing Dafny proofs for UI, CRUD glue, or fast-changing prototype logic
- Adding `assume`, `{:axiom}`, `{:verify false}`, `{:only}`, or bodyless lemmas to make a proof turn green
- Weakening `ensures` or adding impossible `requires` to silence a failing proof instead of fixing the bug
- Leaving a standalone `dafny/` model with no compilation, differential oracle, or runtime guard tying it to production code
- Proving arithmetic on unbounded `int` while production overflows `int64` or rounds IEEE-754 floats
- Using Dafny to model interleaved multi-threaded or distributed protocols where TLA+/Quint is required
- Running `dafny audit` in CI without checking that findings equal `0`

## Gotchas

- `dafny audit` exits with status `0` even when it reports soundness findings; always enforce `0 findings` via `scripts/verify-dafny.sh`.
- In Dafny 4, `function` and `predicate` are **compiled** by default; prefix specification-only helpers with `ghost function` / `ghost predicate` so they carry zero runtime cost.
- Mutable heap framing (`reads` / `modifies`) is the #1 source of proof friction in Dafny—refactor into immutable `datatype` state transitions whenever mutation is not the property under test.
- Wall-clock `--verification-time-limit` varies across machines; for stable CI, inspect assertion costs with `--log-format text` and pin `--resource-limit` via `scripts/verify-dafny.sh --resource-limit <N>`.
