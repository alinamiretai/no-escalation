# io.noescalation/provenance — MCP Extension Specification

**Extension identifier:** `io.noescalation/provenance`
**Status:** Draft (pre-submission; targeting Extensions Track per SEP-2133)
**Version:** 0.1 (experimental — MAY break without notice)
**Requires:** MCP `2026-07-28` or later (stateless core)
**Reference implementation:** `proxy/` in this repository (guard + four-attack conformance suite)
**Formal model:** machine-checked in Lean 4 (`lean/`); see `CLAIMS.md`

---

> **Editor's note (pre-submission).** Sections 1–5 are the technical core and are stable against external review. Section 6 (Related Work and Positioning) is intentionally a stub pending expert feedback. This document uses BCP 14 language per SEP-2133's requirement that extension specs be worded as if part of the core specification.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all capitals, as shown here.

## 1. Abstract

This extension carries **authority provenance** on MCP tool calls: a record of the delegation chain that led to each call, together with the bound each delegating component attached. A guard positioned on the call path uses this record to enforce **no-escalation** — that a component causes no effect beyond what was conferred on it, preserved as authority is delegated, chained through deputies, and narrowed over a session.

The extension defines: the provenance object and where it rides (§3), the language in which a bound denotes a set of effects (§4), the `meet` operation that accumulates conferral down a chain (§4.3), and the processing rules a conforming guard follows (§5). The guarantee the extension provides, and the assumptions it rests on, are stated as conformance requirements (§5.4) and security considerations (§7).

## 2. Terminology

**Effect.** A tool invocation with its arguments — the unit at which authority is granted and checked. Traffic below this granularity (pagination, token refresh, cache reads) is implementation of an effect, not a separate effect.

**Component.** A participant on the call path that MAY delegate: a host, an agent, a sub-agent, or a deputy (an MCP server holding ambient credentials).

**Bound (β).** A set of effects a component is permitted to cause. Encoded on the wire as a union of rules (§4).

**Provenance chain (π).** An ordered, append-only sequence of hops, oldest first. Each hop records a component and the bound it attached when delegating. π is the wire form of the delegation history.

**effbound.** The effects a call is permitted, given π: the intersection (`meet`) of every attached bound along the chain. A guard admits a call if and only if it lies within effbound.

**Guard.** A component that constructs or extends π and enforces effbound. The reference implementation is a proxy on the stdio path between host and server.

**Conferral.** The act of a component attaching a bound when delegating. Conferral only narrows: a component MUST NOT confer authority it does not itself hold.

## 3. The Provenance Object

### 3.1 Location

A provenance chain MUST be carried in the request's `_meta` object under the key `io.noescalation/provenance`. This key follows the reverse-DNS convention for `_meta` keys (SEP-2133); it is distinct from, and sits beside, the W3C Trace Context keys (`traceparent`, `tracestate`, `baggage`) reserved by SEP-414.

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "tools/call",
  "params": {
    "name": "create_issue",
    "arguments": { "repo": "acme/app", "title": "..." },
    "_meta": {
      "io.noescalation/provenance": {
        "v": 1,
        "chain": [
          { "component": "host",    "bound": [ /* rules */ ] },
          { "component": "planner", "bound": [ /* rules */ ] }
        ]
      }
    }
  }
}
```

Because MCP `2026-07-28` is stateless — every request self-contained, no session state (SEP-2567) — the chain MUST be carried in full on every request. A guard MUST NOT rely on chain state retained from a prior request.

### 3.2 Structure

The provenance object has:

- `v` (integer, REQUIRED): schema version. This document defines `v: 1`. A guard receiving an unrecognized `v` MUST fail closed (§5.3).
- `chain` (array, REQUIRED): the hops, oldest first. Each hop is an object with:
  - `component` (string, REQUIRED): an identifier for the delegating component. Opaque to the meet; used for audit.
  - `bound` (array of rules, REQUIRED): the bound attached at this hop (§4).
- `sig` (string, OPTIONAL): a signature over the chain (§5.5). REQUIRED where π crosses a component boundary; MAY be omitted where a single guard is the sole constructor and consumer of π.

The chain is **append-only**. A component extending π MUST append a hop and MUST NOT modify, remove, or reorder existing hops.

## 4. Bounds

### 4.1 Rules

A **bound** is a JSON array of **rules**. A call is within the bound if and only if it matches **at least one** rule (rules are alternatives — union within a bound).

A **rule** is an object:

```json
{ "tool": "create_issue", "args": { "repo": { "in": ["acme/app"] } } }
```

- `tool` (string, REQUIRED): the tool name this rule permits.
- `args` (object, OPTIONAL): a map from argument name to **constraint** (§4.2). An argument not named is unconstrained.

A call `(name, arguments)` matches a rule if and only if: `name` equals the rule's `tool`, and for every constrained argument, the argument is present and its value satisfies the constraint. Unconstrained arguments place no restriction.

### 4.2 Constraints

A constraint restricts one argument's value. The constraint operators are exactly:

```
constraint ::= { "eq":     value }        // equals value
             | { "in":     [ value, ... ] } // member of the set
             | { "prefix": string }        // string starts with prefix
             | { "glob":   string }        // matches shell-glob pattern
             | { "and":    [ constraint, ... ] } // satisfies all (see §4.3)
```

A guard MUST support all five. A guard MUST NOT admit an operator outside this set; in particular, arbitrary regular expressions and numeric ranges are excluded — see §4.4 for why this set and no other.

### 4.3 The `meet`

`meet` is the operation that accumulates conferral down the chain. It has two levels, which MUST NOT be conflated:

- **Within a bound:** the rules are a **union** (a call is in the bound if it matches some rule).
- **Across hops:** the bounds are **intersected** (a call is in effbound if it is admitted by *every* hop's bound).

`effbound(π)` is therefore the meet of all hops' bounds: `meet(β₁, β₂, …, βₙ)`, where `meet` of two bounds is the rule set `{ meet(r₁, r₂) : r₁ ∈ B₁, r₂ ∈ B₂ }` with empty results dropped, and `meet` of two rules conjoins their argument constraints (dropping the rule if any argument's constraint intersection is empty).

The intersection of two constraints on the same argument MUST be exact: it MUST NOT admit a value outside either input. Where two constraints have no single-operator intersection, their meet is expressed as an `{ "and": [...] }` constraint — satisfy both — which is exact. (This is why the operator set is closed: the meet of any two constraints is always expressible, as a conjunction if not more simply.)

This `meet` corresponds to pointwise conjunction of attached bounds along the chain, the operation proved in the formal model (`Kernel.lean`, `meet_sub_hop`).

### 4.4 Why this operator set (normative rationale)

The operator set is `{eq, in, prefix, glob, and}` and no other, for one reason: **`meet` must stay in the language.** A guard computes effbound by intersecting bounds; if the intersection of two admissible constraints could not be expressed as an admissible constraint, the guard could not compute conferral, and the no-escalation guarantee would not hold at the wire level.

- `eq`, `in`, `prefix`, `glob` are each closed under intersection (with `and` capturing irreducible cases). Admitted.
- **Regular expressions are excluded**: the intersection of two regular expressions is not, in general, a regular expression, so `meet` would escape the language.
- **Numeric ranges are excluded**: no authority-bearing numeric argument has been observed in surveyed tools — numeric arguments are pagination (a resource concern, not authority) or object identifiers (authorized by their containing resource, a string, never by numeric range). A future extension version MAY add a `range` operator (it is closed under intersection) if an authority-bearing numeric argument arises.

Every admitted operator except `range` (were it added) is a string operator, reflecting that authority in this domain is denoted by strings: repository names, paths, owners, tool names.

## 5. Processing Rules

*(§5 — guard construction, extension, checking, fail-closed behavior, and conformance requirements R1–R6 — to be written next, transcribed from the reference guard.)*

## 6. Related Work and Positioning

*(Stub — pending expert feedback. Will position against the object-capability lineage, the ABLP/Taos authorization-logic tradition, DIFC, and the current wave of agent-authority mechanisms, per `reviewer-packet.md`.)*

## 7. Security Considerations

*(To be written: the assumptions the guarantee rests on (unforgeable capabilities, framework-owned provenance, deputy contract discharge, mediation), the influence channel explicitly out of scope, and the bound-selection problem as a deployment responsibility.)*

## 8. References

- [RFC2119] / [RFC8174] — BCP 14 requirement-level keywords.
- SEP-414 — W3C Trace Context propagation in `_meta`.
- SEP-2133 — MCP Extensions framework.
- SEP-2567 — stateless core (session removal).
- This repository — `CLAIMS.md` (claim ledger), `lean/` (formal model), `proxy/` (reference implementation).
