# no-escalation

A guard that stops AI agents from exceeding the permissions they were delegated — and a machine-checked proof that it holds across delegation chains.

```
git clone https://github.com/alinamiretai/no-escalation
cd no-escalation/proxy
python3 test_attacks.py
```

Four delegation attacks — including the classic confused deputy — rejected fail-closed. `test_multihop.py` runs the composition case: a planner narrows a worker's access, and the narrowing holds even though a broader grant exists upstream.

## What is here

(A) a property with an adversarial benchmark suite; (B) machine-checked theorems — soundness, composition, chain conferral, revocation effectiveness, graceful degradation, and concurrency-robustness; (C) a conformance criterion applied to a production MCP server; (D) a reference implementation — the guard above; (E) a draft MCP extension (`io.noescalation/provenance`) aligning the wire format to the live MCP `2026-07-28` SEPs.

## The property, precisely

Fix a set E of effects (tool invocations with arguments). Every message carries a provenance context π — a chain of (component, sender-chosen bound) pairs, extended at each send and captured/restored by continuations. An effect occurrence by performer p under π is permitted iff it lies in **effbound = B(p) ∩ ⋂{β along π}**. **NE** (no-escalation): every effect occurrence lies within its effbound — a trace safety property (hence exactly monitorable, per Schneider 2000), kept formally distinct from the state-level invariant EA ⊆ B and from the *influence* residue (covert channels, cross-chain intent), which is named and excluded, not solved. Attenuation and revocation are one mechanism at different filter values: spatial vs. temporal scoping of conferral.

**Chain integrity is a deployment assumption, not a property of the format.** π's tamper-resistance holds in the reference implementation because the guard is the sole constructor and consumer of π. Carrying π across mutually distrusting intermediaries requires an integrity binding (signing) that this draft does not yet specify — see `ext-noescalation-spec.md` §7.

## Status

**Property** frozen at v1.1 (`no-escalation-property-note-v1.1.md` authoritative; §12 addendum records post-freeze results).

**Lean development** — every live theorem proved, one deliberate `sorry` (the *retracted* v1.0 target, kept as provenance of its own refutation):

| | Theorem | |
|---|---|---|
| T1 | Soundness | guard implies effbound |
| T2 | Mixed composition | three lines — the triviality *is* the locality result |
| T2u | Graceful degradation | NE holds on E∖U for a declared unmediated set U |
| T3 | Chain conferral | meet ⊆ every attached bound |
| T4 | **Revocation effectiveness** | full stack proved (T4a–f); weak (no-quiescence) form proved over traces (T4w) |
| T7 | **NE composes under concurrency** | over a shared store — the spatial property is not an artifact of turn-based semantics |

The concurrency result is two-sided and stated honestly: spatial confinement survives genuine overlap (`Concurrent.CNE_holds`); the *temporal* start-of-run invariant does not transfer for free (`CNE_startbound`) — revocation under concurrency needs an explicit happens-before order the model does not yet provide. This is the located boundary of the current contribution, not a hidden gap.

**Reference implementation** (`proxy/`) — a stdio MCP guard: constructs/extends π in `_meta`, computes effbound, rejects violations fail-closed, tested against a real MCP server (`test_meta_realhost.py`, the reference filesystem server). **Not yet implemented:** revocation (proved in Lean, not wired into the running guard) and result-side mediation (deliberately deferred — see Scope).

**Claim discipline** — every claim carries an ID, an evidence *class* (PROVED = Lean/unbounded, CHECKED = Alloy/bounded, STATED, REFUTED, ...), and a pointer, in `CLAIMS.md`. `LEDGER.md` is the falsification record: every substantive error this project made was a prose claim that ran ahead of a checker, caught by forcing contact with one.

## Layout

```
no-escalation-property-note-v1.1.md   <- FROZEN property statement (authoritative)
CLAIMS.md                             <- every claim: ID, evidence class, pointer
LEDGER.md                             <- falsification record (L1-L14)
conformance-spec.md                   <- A1-A6 -> R1-R6, applied to a real MCP server
ext-noescalation-spec.md              <- draft io.noescalation MCP extension (BCP-14)
provenance-schema.md                  <- the wire format, derived + verified both ways

lean/NoEscalation/                    <- Lean 4 (v4.32.0), Mathlib-free; sets as predicates
  Kernel . Semantics . Guarded . Warmups . Alias . Revocation
  . CareSanity (A3 satisfiable) . Degradation (T2u) . Concurrent (T7) . Sanity

models/                               <- Alloy 6.2 (sat4j) + RESULTS.md verdict table
  noescalation_v4.als                 <- v1.1 validation (guarded semantics, caretaker Guard)
  benchmark_attacks.als               <- B1/B2 (confused deputy, re-amplification)
  benchmark_capture_housekeeping.als  <- C3/C8 (continuation capture, sub-effect principle)
  caretaker_finding.als . resolver_issuance.als . alias_v11.als
  . history_vs_chain.als . sole_route.als

proxy/                                <- reference implementation (Python, stdio)
  proxy.py         <- stage-0 pass-through relay
  provenance.py    <- the verified schema as code (bounds, meet, pi in _meta)
  guard.py         <- effbound enforcement, multi-hop, fail-closed
  test_attacks.py . test_multihop.py . test_passthrough.py . test_meta_realhost.py
  CONFORMANCE.md   <- spec-clause ledger: IMPLEMENTED / PARTIAL / DEFERRED

instantiation/                        <- source + runtime audit of github/github-mcp-server @ 1338dbe
  audit.sh . github-mcp-server-inventory.md . idle-egress-native.sh
```

## Reproducing

**Proxy.** Python 3, no dependencies. From `proxy/`:
```
python3 provenance.py       # data-model self-test
python3 test_passthrough.py # stage-0 relay
python3 test_attacks.py     # the four benchmark attacks, rejected fail-closed
python3 test_multihop.py    # delegation composition (T3) in running code
python3 test_meta_realhost.py  # provenance survives a real MCP server (needs Node)
```

**Lean.** Install `elan`; from `lean/`: `lake build`. Expected: clean build, exactly one `sorry` warning (`Semantics.lean`, the retracted v1.0 target). Toolchain pinned in `lean-toolchain`.

**Alloy.** Alloy Analyzer 6.2 (sat4j). Open each `.als` in `models/`, Execute All, compare against `RESULTS.md`. Two conventions when reading verdicts: every scenario predicate has an adjacent satisfiability witness (a `check` over an uninhabited scenario proves nothing — watch for `0 vars`, which flags a vacuous check), and several commands are *deliberately* invalid or SAT — that is the finding, not a failure.

## Method

Three instruments in a loop: Alloy as counterexample oracle (cheap refutation at small scope, satisfiability-witnessed), Lean as unbounded closer (Alloy-validated invariants become mechanization candidates; two theorem statements died on contact with proof obligations), and a production-source audit as the reality check on the effect ontology — extended into a running guard, which turns the wire format into something executable and the benchmark attacks into an executable conformance suite. The four motivating counterexamples were machine-found, one inside this project's own v1.0 contract.

The property note is frozen; definitional changes require a decision memo and a full model re-run. `LEDGER.md` records every error this discipline caught, including three found while re-encoding evidence for this repository's own claim ledger.

## Scope

This work bounds **authority** (what a component may cause), not **influence**: a confined agent can still be steered, by prompt injection or otherwise, into misusing authority it legitimately holds, and covert channels through permitted effects are out of scope by construction. It assumes the system stays within the mediated framework — the unmediated set U must be **declared**, not assumed empty (T2u gives the guarantee that survives when U is nonempty). It enforces that effects stay within the conferred bound, not that the conferred bound is the right one. Result-side mediation (whether a returned value leaks a capability) is a distinct design question, deliberately deferred.

Within those limits, one class of agent harm is made structurally impossible rather than behaviorally discouraged. It is not a claim that a conforming agent is safe. See `ext-noescalation-spec.md` §7 and `CLAIMS.md` (S1-S4) for the full statement.
