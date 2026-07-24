# Proxy Conformance Ledger

The `CLAIMS.md` discipline applied to the reference implementation. Every clause of the spec (`../provenance-schema.md`, `../conformance-spec.md`) gets a status here, so "is the tool right?" has an at-a-glance answer instead of a lurking worry. A passing test suite can make the tool look more complete than it is; this file is the corrective.

**Status vocabulary:**

| Status | Meaning |
|---|---|
| **IMPLEMENTED** | Matches the spec; exercised by a green test |
| **PARTIAL** | Implemented for the cases the target tools need; a marked gap remains |
| **DEFERRED** | Spec describes it; tool does not do it yet, by stage design |
| **DIVERGES** | Tool and spec disagree and one must change — none currently |

The rule that keeps this honest: **the spec is the authority; the tool conforms to it.** Where the tool teaches us the spec is wrong, we change the spec and re-conform. Where the tool is simply behind, we mark DEFERRED and advance it in a later stage. Neither is a silent error.

---

## Data model (`provenance.py`)

| Spec element | Status | Notes / pointer |
|---|---|---|
| π in `_meta["io.noescalation/provenance"]` | IMPLEMENTED | `attach_to_meta` / `read_from_meta`; round-trip tested |
| Bound = list of rules, call matches SOME rule (union within bound) | IMPLEMENTED | `bound_admits` |
| Rule = tool + arg constraints; unconstrained args unrestricted | IMPLEMENTED | `Rule.matches` |
| Constraint ops `{eq, in, prefix, glob}` | IMPLEMENTED | `Constraint.matches` |
| `meet` across hops = intersection (pointwise conjunction, Kernel.lean:55) | IMPLEMENTED | `meet_bounds`; self-test checks acme/app removed when planner narrows |
| `meet_constraints` for eq/in/prefix pairs | IMPLEMENTED | exact cases |
| `meet_constraints` for glob-involving / other mixed pairs | **PARTIAL** | conservative `return a` fallback, marked NOTE in code. Never hit by target tools (authority args use eq/in/prefix; glob is path-only). **Must be finished before a tool mixes glob with another op on one arg.** This is the tool's `sorry`. |
| Chain is append-only, oldest first | IMPLEMENTED | `Chain.extend` returns a new chain, never mutates |
| `range` operator | N/A (correctly absent) | verified: no authority-bearing numeric arg in target tools |

## Guard behavior (`guard.py`)

| Spec element | Status | Notes / pointer |
|---|---|---|
| Attach π on host→server `tools/call` | IMPLEMENTED | `Guard.process_outbound` |
| Check effbound, reject outside it fail-closed | IMPLEMENTED | rejects with JSON-RPC `-32001`; four-attack suite green |
| Non-`tools/call` messages relay unchanged | IMPLEMENTED | `process_outbound` early return |
| enforce / audit modes | IMPLEMENTED (enforce) / PARTIAL (audit) | audit path exists in `process_outbound`; not yet exercised by a test |
| **Multi-hop chains** (extend an *inbound* π on delegation) | **IMPLEMENTED** | `process_outbound` reads an inbound π and extends it; `test_multihop.py` green. Demonstrates T3 in code: acme/app survives both hops, acme/docs is dropped by hop-2 narrowing (confused-deputy shape), evil/app rejected (no re-amplification). The tool now shows composition, not just confinement. |
| **Membrane** (guard what comes *back*: server→host results) | **DEFERRED** | `pump_inbound` relays results unchanged. The spec's Membrane clause (never emit the underlying reference) is unenforced in the tool. |
| **Signing** π (cross-boundary A2) | **DEFERRED** | `sig` field specified; tool uses unsigned form (sound because the proxy is currently the sole constructor/consumer of π — the plaintext-proxy case the spec explicitly permits). |
| Policy source (where the host's bound comes from) | PARTIAL | passed as a constructor arg for testing; real deployment needs config loading. |

## Transport

| Spec element | Status | Notes / pointer |
|---|---|---|
| stdio, newline-delimited JSON-RPC | IMPLEMENTED | tested against fake_server |
| `_meta` preserved across a real host | **UNVERIFIED** | SEP-414 guarantees it; the fixture preserves it by construction. **The real-host check (point guard.py at Claude-in-terminal + a real MCP server) is the empirical test still owed.** Until then, "hosts preserve `_meta`" is trusted, not checked. |
| HTTP transport | DEFERRED | stdio only for now |

---

## The gaps that matter, ranked

1. **`meet_constraints` mixed pairs (PARTIAL).** The one place the tool is not-yet-correct rather than not-yet-complete. The conservative `return a` fallback for glob-involving pairs. Marked in code. Cheap to finish; needed before the operator set is exercised in full generality.

2. **Real-host `_meta` preservation (UNVERIFIED).** The one empirical claim the tool rests on and hasn't tested. Needs a real MCP host + server (Claude-in-terminal + a real MCP server). Everything else can be checked in the self-contained loop; this cannot.

3. **Membrane / result guarding (DEFERRED).** `pump_inbound` relays server→host results unchanged; the spec's Membrane clause (never emit the underlying reference in a result) is unenforced. Lower priority — the confinement and composition halves are the core; result-guarding is the next layer.

*(Closed: multi-hop composition, previously #1, now IMPLEMENTED and green — `test_multihop.py`.)*

## What is genuinely done

Confinement AND composition. Single-hop effbound enforcement catches all four benchmark attacks fail-closed (`test_attacks.py`); multi-hop delegation demonstrates T3 — conferral composing down the chain, later narrowing holding against earlier grants (`test_multihop.py`). The wire format round-trips; the `meet` matches the proved definition (Kernel.lean:55) for every case the target tools exercise. This is a reference implementation of the core of the spec — the confinement and composition halves both running and tested. Remaining gaps (mixed-operator meet, real-host `_meta`, result-guarding) are marked above, none in the core path.