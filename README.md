# no-escalation

Formal foundations for **dynamic authority confinement** in capability-bearing agent systems: a machine-checked property statement ("no-escalation", NE), an enforcement architecture, mechanized theorems, an adversarial benchmark suite, and an instantiation audit of a production tool server.

**The property, in one paragraph.** Fix a set E of effects (tool invocations with arguments). Every message carries an unforgeable *provenance context* π — a chain of (component, sender-chosen bound) pairs extended at each send and captured/restored by continuations. An effect occurrence by performer p under π is permitted iff it lies in **effbound = B(p) ∩ ⋂{β along π}**. **NE**: every effect occurrence lies within its effbound — a trace safety property (hence exactly monitorable), kept formally distinct from the state-level invariant EA ⊆ B and from the *influence* residue (covert channels, cross-chain intent), which is named and excluded. Attenuation and revocation are one mechanism at different filter values: spatial vs. temporal scoping of conferral.

**Status.** Property statement frozen at **v1.1** (`docs/property-note-v1.1.md` is authoritative). Lean development: all live theorems proved — T1 soundness, T2 mixed composition (three lines; the triviality is the locality result), T3's chain-conferral core, bound antitonicity + mixed-system NES, and alias-freedom preservation under the Membrane contract. Exactly one `sorry` remains, deliberately: the *retracted* v1.0 target, kept as provenance of its own refutation. T4's effectiveness statement (filters and issuance entering the state) is the remaining formalization.

## Layout

```
docs/
  property-note-v1.1.md      ← FROZEN, authoritative
  history/                   ← superseded notes (v0.1–v1.0): the hardening trail
  memos/                     ← decision memos: turn semantics; item-6 housekeeping;
                               v1.1 restatement; resolver issuance
models/                      ← Alloy 6.2 models + RESULTS.md (verdict table)
  noescalation_v1..v3.als    ← kernel → dynamics → full suite (v1.0 era)
  noescalation_v4.als        ← v1.1 validation (guarded semantics, caretaker Guard)
  caretaker_finding.als      ← isolates the confused-deputy finding
  resolver_issuance.als      ← issuance-rule discriminator (C1–C3)
  alias_v11.als              ← alias-freedom under the repaired contract
  history_vs_chain.als       ← history-based vs chain-based discriminator
instantiation/
  audit.sh, audit-output.txt ← source audit of github/github-mcp-server @ 1338dbe
  github-mcp-server-inventory.md ← bucketed findings, file:line cited
lean/                        ← Lean 4 (v4.32.0), Mathlib-free; see below
```

## Reproducing

**Alloy.** Alloy Analyzer 6.2 (sat4j). Open each `.als` in `models/`, Execute All, compare against `models/RESULTS.md`. Two conventions matter when reading verdicts: every scenario predicate has an adjacent satisfiability witness (a `check` over an uninhabited scenario proves nothing), and several commands are *deliberately* invalid or SAT — the finding, not a failure. RESULTS.md flags each.

**Lean.** Install `elan`; from `lean/`: `lake build`. Expected: builds clean with exactly one warning — `Semantics.lean` (the retracted v1.0 target). Toolchain pinned in `lean-toolchain` (v4.32.0). No Mathlib; sets are predicates.

## Change discipline

The note is frozen. Definitional changes require (1) a decision memo recording the trigger, options, and rationale, and (2) a full re-run of the model suite. This discipline is load-bearing: the project's documented error ledger — four prose theorem claims wrong before checking, three unsound and one unnecessary — was caught entirely by forcing claims into contact with a checker, twice against this repository's own frozen text.

## Method

Three instruments in a loop: **Alloy** as counterexample oracle (cheap refutation at small scope, satisfiability-witnessed), **Lean** as unbounded closer (every Alloy-validated invariant is a candidate for mechanization; two theorem statements died on contact with proof obligations), and a **production-source audit** as the reality check on the effect ontology. Findings flowed in both directions; the four motivating counterexamples in the note's benchmark section were all machine-found, one inside this project's own v1.0 contract.
