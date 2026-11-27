# Dafny 4 Specification & Modeling Patterns

Use these Dafny 4 templates as starting points for real-world critical logic. All snippets below use Dafny 4 syntax (`function`/`predicate` are compiled by default; `ghost function`/`ghost predicate` are erased at compile time).

## Pattern 1: State-Machine Inductive Invariant (Ledger / Conservation)

Most high-cost production bugs live in state transitions (money transfers, escrow, permissions, locks, rate limits, job queues). Model them with an immutable `datatype`, a `Valid` invariant, an `Init` constructor, and pure `Step` transitions that prove both **invariant preservation** and **two-state properties** (e.g., conservation of total balance).

```dafny
module LedgerCore {
  const MAX_BALANCE: int := 1_000_000_000 // model minor units (e.g., cents) with explicit cap

  datatype State = State(balances: map<string, int>)

  ghost predicate Valid(s: State) {
    forall acct :: acct in s.balances ==> 0 <= s.balances[acct] <= MAX_BALANCE
  }

  ghost function Total(m: map<string, int>): int
    decreases |m|
  {
    if |m| == 0 then 0
    else
      var k :| k in m;
      m[k] + Total(m - {k})
  }

  lemma LemmaTotalRemove(m: map<string, int>, k: string)
    requires k in m
    ensures Total(m) == m[k] + Total(m - {k})
  {
    var k0 :| k0 in m && Total(m) == m[k0] + Total(m - {k0});
    if k0 == k {
    } else {
      assert k in (m - {k0});
      LemmaTotalRemove(m - {k0}, k);
      assert k0 in (m - {k});
      LemmaTotalRemove(m - {k}, k0);
      assert (m - {k0}) - {k} == (m - {k}) - {k0};
    }
  }

  lemma LemmaTotalUpdate(m: map<string, int>, k: string, v: int)
    requires k in m
    ensures Total(m[k := v]) == Total(m) - m[k] + v
  {
    var m' := m[k := v];
    assert k in m';
    assert m' - {k} == m - {k};
    LemmaTotalRemove(m, k);
    LemmaTotalRemove(m', k);
  }

  function Init(accounts: map<string, int>): State
    requires forall a :: a in accounts ==> 0 <= accounts[a] <= MAX_BALANCE
    ensures Valid(Init(accounts))
  {
    State(accounts)
  }

  function Transfer(s: State, from: string, to: string, amount: int): State
    requires Valid(s)
    requires from in s.balances && to in s.balances
    requires from != to
    requires 0 < amount <= s.balances[from]
    requires s.balances[to] + amount <= MAX_BALANCE
    ensures Valid(Transfer(s, from, to, amount))
    ensures Total(Transfer(s, from, to, amount).balances) == Total(s.balances)
    ensures Transfer(s, from, to, amount).balances[from] == s.balances[from] - amount
    ensures Transfer(s, from, to, amount).balances[to] == s.balances[to] + amount
  {
    var m1 := s.balances[from := s.balances[from] - amount];
    var m2 := m1[to := m1[to] + amount];
    LemmaTotalUpdate(s.balances, from, s.balances[from] - amount);
    LemmaTotalUpdate(m1, to, m1[to] + amount);
    State(m2)
  }

  // Witness lemma: proves requires are satisfiable and ensures are non-vacuous
  lemma WitnessTransfer()
  {
    var s0 := Init(map["alice" := 100, "bob" := 40]);
    var s1 := Transfer(s0, "alice", "bob", 25);
    assert s1.balances["alice"] == 75;
    assert s1.balances["bob"] == 65;
  }
}
```

Why this pattern scales well:
- Zero heap framing (`reads`/`modifies`) because `State` is an immutable `datatype`.
- `Valid(s)` is inductive: proved once at `Init` and preserved by every transition.
- `Transfer` proves safety (`0 <= balance <= MAX_BALANCE`), conservation (`Total` unchanged), and exact effect on sender/receiver.
- `WitnessTransfer` proves the contract is reachable on concrete inputs.

## Pattern 2: Separate Ghost Spec from Fast Implementation

Define the mathematical meaning as a simple `ghost function` (clear, obviously right, never compiled), then prove the fast imperative `method` produces the exact same result.

```dafny
module SpecVsImpl {
  ghost function SumUpTo(n: nat): nat {
    if n == 0 then 0 else n + SumUpTo(n - 1)
  }

  method ComputeSum(n: nat) returns (total: nat)
    ensures total == SumUpTo(n)
  {
    total := 0;
    var i: nat := 0;
    while i < n
      invariant 0 <= i <= n
      invariant total == SumUpTo(i)
      decreases n - i
    {
      i := i + 1;
      total := total + i;
    }
  }

  lemma WitnessSum()
  {
    assert SumUpTo(4) == 10;
  }
}
```

Loop invariant rule of thumb:
1. **Bounds:** Always state index bounds (`0 <= i <= n`).
2. **Entry:** True right before the loop starts (`i == 0 && total == SumUpTo(0)`).
3. **Preservation:** Maintained by each loop iteration.
4. **Exit:** `invariant && !(i < n)` implies `i == n`, which implies `total == SumUpTo(n)`.
5. **Termination:** State `decreases n - i` explicitly whenever Dafny cannot infer it.

## Pattern 3: Modeling Bounded Integers & Minor Units

Dafny's `int` is arbitrary-precision mathematical integers. When production code runs on fixed-width integers or floats:

- **Prefer integer minor units** (cents, satoshis, basis points) instead of floating point (`real` in Dafny is exact mathematical reals, not IEEE-754 floats).
- **Use `newtype` for fixed-width bounds** so Dafny automatically generates overflow proof obligations on every arithmetic operation:

```dafny
module BoundedMath {
  newtype Int64 = x: int | -0x8000_0000_0000_0000 <= x < 0x8000_0000_0000_0000
  newtype Cents = x: int | 0 <= x <= 1_000_000_000_000

  function SafeAdd(a: Cents, b: Cents): Cents
    requires (a as int) + (b as int) <= 1_000_000_000_000
    ensures (SafeAdd(a, b) as int) == (a as int) + (b as int)
  {
    a + b
  }
}
```

## Pattern 4: Strengthening Weak Specs & Anti-Vacuity Checks

Always test your spec against two failure modes:

- **Too weak (`ensures` allows wrong answers):**
  - Weak: `ensures r >= a && r >= b` (satisfied by returning `a + b + 999999`).
  - Strong: `ensures r >= a && r >= b && (r == a || r == b)`.
- **Vacuous (`requires` is impossible):**
  - Broken: `requires x > 10 && x < 5` (any `ensures`, even `ensures false`, verifies!).
  - Guard: Always write a concrete `Witness*` lemma that invokes the function/method with real inputs and asserts expected concrete outputs.

## Pattern 5: Bridging Dafny to Production Code

### Mode A — Compiled Verified Core

Translate or build directly into the host language and import the generated module as a read-only artifact:

```bash
dafny translate js --output:src/verified/ledger verification/ledger.dfy
# or targets: go | py | cs | java
```

Keep a CI check asserting that the generated artifact matches the verified `.dfy` source (no hand edits to generated code).

### Mode B — Executable Oracle (Differential Testing)

1. Compile the Dafny model to JS/Python/Go in a test-only directory (`dafny translate ...`).
2. Write a property-based test (`fast-check`, `Hypothesis`, `proptest`) that generates random valid initial states and sequences of actions.
3. Apply each action to both the compiled Dafny oracle and the production implementation, asserting observable state equivalence after every step.

### Mode C — Design-Time Spec + Runtime Guards

When compiling Dafny into the runtime or test suite is impractical:
1. Document the verified properties and trusted assumptions (e.g., an ADR linking to `verification/*.dfy`).
2. Mirror every `requires` guard and key `Valid` postcondition as explicit runtime assertions at the production boundary.
3. Update the `.dfy` spec whenever the production state machine changes.
