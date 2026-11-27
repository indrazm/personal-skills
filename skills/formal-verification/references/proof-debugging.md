# Proof Debugging & Z3 Stability Guide

When `dafny verify` fails or slows down, never patch around it with `assume`, `{:axiom}`, or `{:verify false}`. Classify the failure first, isolate the exact failing obligation, and apply the smallest sound fix.

## Step 1: Classify the Failure (4 Root Causes)

Every Dafny verification failure falls into exactly one category:

| Cause | Signal | Correct Fix |
| --- | --- | --- |
| **1. Real implementation bug** | Concrete counterexample violates a valid `ensures` or `invariant`. | Fix the implementation body; do not weaken `ensures`. |
| **2. Wrong or over-strong spec** | The property you wrote is mathematically false for valid inputs (e.g., missing a boundary case or wrong formula). | Correct the spec and verify with a concrete witness lemma. |
| **3. Missing fact / hint** | The code and spec are right, but Dafny lacks an intermediate fact, a callee `ensures`, a loop `invariant`, or a helper lemma call. | Add the missing `ensures` / `invariant` / helper lemma or `calc` step. |
| **4. Z3 timeout / brittleness** | Verification hangs, hits `--verification-time-limit` / `--resource-limit`, or flakes across edits. | Isolate the assertion, hide irrelevant definitions with `{:opaque}`, eliminate nonlinear arithmetic, or simplify quantifiers. |

## Step 2: Isolate the Exact Failing Assertion

Do not re-verify the entire project while debugging one proof. Narrow scope with Dafny 4 flags:

```bash
# Verify a single symbol (method, function, or lemma)
dafny verify verification/ledger.dfy --filter-symbol=LedgerCore.Transfer

# Verify a specific line range
dafny verify verification/ledger.dfy --filter-position=ledger.dfy:55-75

# Verify each assertion independently and report per-assertion resource cost
dafny verify verification/ledger.dfy \
  --filter-symbol=LedgerCore.Transfer \
  --isolate-assertions \
  --log-format text
```

Use `--log-format text` with `--isolate-assertions` to spot which single assertion is consuming millions of Z3 resource units.

## Step 3: Systematic Proof Tactics

### Binary-Search with `assert`
When a postcondition or invariant fails without an obvious cause:
1. Insert `assert P;` halfway through the method or proof for the intermediate fact you believe holds.
2. If the `assert` **fails**, the missing fact is earlier (or the code has a bug before that line).
3. If the `assert` **passes**, the gap is between that `assert` and the failing `ensures`.
4. Once resolved, remove redundant diagnostic `assert`s or extract reusable facts into a small `lemma`.

### Step-by-Step Algebra with `calc`
Instead of hoping Z3 bridges multi-step arithmetic or sequence/map equalities in one jump, write an explicit `calc` block so each transition is checked individually:

```dafny
calc {
  Total(m2);
== { LemmaTotalUpdate(m1, to, m1[to] + amount); }
  Total(m1) - m1[to] + (m1[to] + amount);
==
  Total(m1) + amount;
== { LemmaTotalUpdate(s.balances, from, s.balances[from] - amount); }
  Total(s.balances) - amount + amount;
==
  Total(s.balances);
}
```

### Tame Proof Context Explosion with `{:opaque}` and `reveal`
When a file grows, Z3 unfolds every function body in scope, causing timeouts on unrelated lemmas:
- Mark heavy recursive or quantified helper definitions with `{:opaque}` (or `opaque ghost function` in Dafny 4).
- Call `reveal MyHelper();` only inside the specific lemma that needs its body.

### Avoid Nonlinear Arithmetic Pitfalls
Z3 struggles with multiplication/division/modulo of two symbolic variables (`a * b`, `a / b`, `a % b`):
- Test with `--disable-nonlinear-arithmetic` to quickly reveal where a proof depends on fragile nonlinear SMT heuristics.
- Prove small arithmetic helper lemmas (e.g., monotonicity of multiplication, distributive rules) or invoke Dafny's standard library nonlinear arithmetic lemmas (`--standard-libraries`) instead of relying on Z3 to guess.

### Loop Invariant Debugging Checklist
If a `while` loop fails to verify, check which of the four obligations failed:
1. **Entry failure:** Invariant is false right before the loop. Check initial variable values.
2. **Preservation failure:** Invariant fails at the end of the loop body. Add `assert`s inside the body to inspect state before and after each update.
3. **Postcondition failure after loop:** Loop itself verifies, but `ensures` fails after the loop. Your invariant is too weak: check whether `invariant && !guard ==> ensures`.
4. **Termination failure:** Add explicit `decreases` expression (must be strictly smaller each pass and bounded below, e.g., `decreases n - i`).

## Step 4: Pin Deterministic CI Limits

Wall-clock time limits (`--verification-time-limit 30`) behave differently across developer laptops and busy CI runners.

1. Measure current resource usage locally:
   ```bash
   dafny verify verification/ledger.dfy --isolate-assertions --log-format text
   ```
2. Pin a comfortable deterministic ceiling (typically 3x–5x the highest single assertion cost) in CI using `scripts/verify-dafny.sh`:
   ```bash
   bash <skill-dir>/scripts/verify-dafny.sh --resource-limit 10000000 verification/
   ```
3. Never leave `--filter-symbol`, `--filter-position`, or `{:only}` active in committed code or CI scripts.
