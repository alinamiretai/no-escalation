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

- `v` (integer, REQUIRED): schema version. This document defines `v: 1`. A guard receiving an unrecognized `v` MUST fail closed (§5.3). `v` applies to the provenance object as a whole, not per hop: a guard extending a chain MUST NOT alter `v`, and MUST fail closed rather than extend a chain whose `v` it does not implement.
- `chain` (array, REQUIRED): the hops, oldest first. Each hop is an object with:
  - `component` (string, REQUIRED): an identifier for the delegating component. Opaque to the meet; used for audit.
  - `bound` (array of rules, REQUIRED): the bound attached at this hop (§4).
- `sig` (string, RESERVED): reserved for a future revision specifying an integrity binding. Under this version, implementations MUST NOT populate this field, and a guard MUST ignore it if present (§5.5).

The chain is **append-only**. A component extending π MUST append a hop and MUST NOT modify, remove, or reorder existing hops.

## 4. Bounds

### 4.1 Rules

A **bound** is a JSON array of **rules**. A call is within the bound if and only if it matches **at least one** rule (rules are alternatives — union within a bound).

An **empty bound** (`[]`) admits nothing: no rule matches, so every call is
outside it. A hop attaching an empty bound confers no authority, and any chain
containing such a hop has an empty effbound. This is the correct reading of
full revocation and MUST NOT be treated as "unconstrained."

An **empty chain** (`"chain": []`) likewise confers no authority and MUST be
treated as admitting nothing. A guard MUST NOT interpret an empty chain as an
absent chain; absent provenance is handled by §5.5.1.

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

#### 4.2.1 Type compatibility

Each operator is defined over a value type. `eq` and `in` compare JSON values
for equality (§4.2.3). `prefix` and `glob` are defined over JSON strings only.

If a constraint is applied to an argument whose JSON type is incompatible with
the operator — `prefix` or `glob` against a number, boolean, null, array, or
object — the constraint MUST evaluate to **no match**. A guard MUST NOT coerce
the value to a string, and MUST NOT treat a type mismatch as an error that
bypasses the check. The rule simply fails to match, and the call is rejected
unless some other rule in the bound admits it.

#### 4.2.2 Canonicalization (normative)

Argument values MUST be canonicalized before any constraint is evaluated
against them. Without this, `prefix` and `glob` are trivially bypassable: the
string `/repo/../../etc/passwd` has the prefix `/repo/` while denoting a
location outside it.

A guard MUST apply the following, in order, to every string argument value
before matching, and MUST apply the identical transformation to the string
operand of a `prefix`, `glob`, `eq`, or `in` constraint:

1. **Unicode normalization** to NFC.
2. **Percent-decoding**, repeated until the value no longer changes, for
   arguments whose tool schema declares them to be URIs, paths, or otherwise
   percent-encoded. A guard MUST bound this to a small fixed number of
   iterations and MUST reject the call if the value has not stabilized (this
   prevents decoding-bomb inputs).
3. **Path normalization**, for arguments denoting hierarchical paths or
   resource identifiers: resolve `.` and `..` segments, collapse repeated
   separators, and remove a trailing separator. A value that resolves above
   its own root (a leading `..` that cannot be resolved) MUST be rejected as
   malformed rather than normalized to something else.

Comparison is **case-sensitive** by default. A deployment whose underlying
resources are case-insensitive (for example, a case-insensitive filesystem or
a hosting provider that treats repository names case-insensitively) MUST
case-fold both operands before comparison, and MUST document that it does so.
Applying case-sensitive comparison over case-insensitive resources admits a
bypass by case variation; applying case-folding over case-sensitive resources
over-restricts but does not escalate.

A guard MUST reject a call whose argument cannot be canonicalized (malformed
encoding, unresolvable path) rather than matching against the raw value.

Rationale: canonicalization is the boundary at which most authorization
bypasses in comparable systems occur. Making it normative and explicit — and
requiring the *same* transformation on both operands — is what makes `prefix`
and `glob` mean what a reader expects them to mean.

#### 4.2.3 `eq` and `in` comparison

`eq` and `in` compare canonicalized values. Two values are equal if they have
the same JSON type and: for strings, are equal after §4.2.2; for numbers, are
numerically equal; for booleans and null, are identical. Arrays and objects
compare by deep structural equality with object keys unordered.

#### 4.2.4 `glob` dialect (normative)

`glob` patterns are interpreted under exactly the following rules. No other
metacharacters are recognized; any other character matches itself literally.

| Pattern | Matches |
|---|---|
| `?` | exactly one character, **except** the separator `/` |
| `*` | zero or more characters, **except** the separator `/` |
| `**` | zero or more characters, **including** the separator `/` |
| `[abc]`, `[a-z]` | one character from the set or range |
| `[!abc]`, `[^abc]` | one character not in the set |
| `\` + metacharacter | the metacharacter, literally |

The `/`-exclusion for `*` and `?` is the authority-relevant choice: a bound of
`acme/*` admits `acme/app` and MUST NOT admit `acme/app/sub`. A deployment
that intends to admit arbitrary depth MUST write `acme/**` explicitly. A guard
MUST NOT implement `*` as crossing separators, because doing so silently
widens every bound written by a deployment that assumed otherwise.

Patterns MUST be matched against the whole canonicalized value, not a
substring: an implicit anchor at both ends.

A guard MUST reject a bound containing a syntactically invalid pattern
(unterminated `[`, trailing `\`) as malformed (§5.3) rather than attempting
recovery.

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

A **guard** is a component that constructs or extends π and enforces effbound. This section specifies what a conforming guard MUST do. The reference implementation (`proxy/guard.py`) follows these rules.

### 5.1 Constructing and extending π

On a `tools/call` it processes, a guard MUST determine the outbound provenance chain as follows:

1. **Read** any inbound chain from `_meta["io.noescalation/provenance"]` (§3).
2. **Extend** it by appending exactly one hop whose `component` is the guard's own component identifier and whose `bound` is the bound this component confers (its policy).
   - If no inbound chain is present, the guard MUST start a new chain (`v: 1`, empty) and append its single hop.
   - The guard MUST NOT modify, remove, or reorder existing hops (§3.2, append-only).
3. **Attach** the resulting chain to the outbound message's `_meta` under the reserved key before forwarding.

A component MUST NOT confer, in the bound it attaches, authority it does not itself hold. (This is the conferral-only-narrows discipline; a guard that attaches a bound wider than its own inbound effbound violates the extension.)

### 5.2 Checking effbound

Before forwarding a `tools/call`, the guard MUST compute `effbound` as the `meet` of every hop's bound in the extended chain (§4.3) and determine whether the call `(name, arguments)` lies within it (§4.1).

- If the call is within effbound, the guard MUST forward it (with the extended π attached).
- If the call is **not** within effbound, the guard MUST NOT forward it; it MUST respond per §5.3.

Messages that are not `tools/call` (initialization, `tools/list`, notifications, results) are outside the scope of effbound checking in this version and MUST be relayed unchanged. (Result-side mediation — the Membrane property — is reserved for a future version; see §7.)

### 5.3 Fail-closed behavior

A guard MUST fail closed. Specifically:

- A `tools/call` outside effbound MUST NOT reach the server. The guard MUST return a JSON-RPC error to the caller with code `-32001` and a `message` naming the extension and the rejected tool. The error `data` SHOULD include the tool name and arguments for audit.
- A provenance object with an unrecognized `v` or a malformed chain MUST be treated as a violation and rejected as above. A guard MUST NOT fall back to forwarding a call whose provenance it cannot parse. (Absent provenance is not malformed provenance; see §5.5.1.)
- A guard MUST NOT silently drop a message it cannot parse as JSON-RPC in a way that suppresses either the call or an error response; unparseable traffic is relayed unchanged (it is not a `tools/call` the guard can act on) rather than dropped.

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "error": {
    "code": -32001,
    "message": "io.noescalation: 'delete_repo' with these arguments is outside the conferred bound",
    "data": { "tool": "delete_repo", "arguments": { "repo": "acme/app" } }
  }
}
```

### 5.4 Modes

A guard MUST support **enforce** mode (the default), in which violations are rejected per §5.3. A guard MAY support **audit** mode, in which a violation is logged and the call is nonetheless forwarded. Audit mode exists for safe rollout — a deployment can observe what enforce mode *would* reject before enabling it. A guard in audit mode MUST record each would-be rejection. A guard's mode MUST default to enforce; audit MUST be explicit opt-in.

### 5.5 Chain integrity

This version does **not** specify a cryptographic binding for π. No signature
algorithm, serialization, or canonicalization is defined here, and this
specification therefore provides no mechanism by which a receiving guard can
detect modification of π by an intermediate component.

The consequence is explicit: a component in the request path can drop a hop,
or widen a bound it previously attached, and no conforming implementation is
required to detect it.

Deployments claiming conformance MUST therefore satisfy at least one of:

- **(a) Trusted path.** Every component that reads or extends π is trusted not
  to modify it — for example, a single guard is the sole constructor and
  consumer of π, with no untrusted component handling the chain in between.
  A deployment relying on (a) MUST document the trust boundary within which
  it holds.
- **(b) Out-of-band integrity.** An integrity binding applied outside this
  specification renders modification of π by an intermediate component
  detectable. A deployment relying on (b) MUST document the mechanism.

A deployment satisfying neither MUST NOT claim conformance, and MUST NOT rely
on this extension for confinement across mutually distrusting intermediaries.

The `sig` field in §3.2 is reserved for a future revision that specifies a
binding directly. Implementations MUST NOT populate it under this version, and
a guard MUST ignore it if present. Prior work on signed capability tokens with
per-hop attenuation demonstrates that a chained construction is achievable;
the omission here is scope, not feasibility.

### 5.5.1 Absent provenance

A guard MAY receive a `tools/call` carrying no `io.noescalation/provenance`
key — from a non-participating client, or as the first hop in a chain. This is
distinct from a malformed chain (§5.3) and MUST NOT be treated as a violation
on that basis alone.

A guard MUST be configured with one of two dispositions for absent provenance,
and the disposition MUST be explicit rather than defaulted silently:

- **originate** — the guard treats itself as the origin of the chain,
  constructs a new chain per §5.1, and checks against its own conferred bound
  alone. Appropriate where the guard sits at the trust boundary of the
  deployment and callers upstream of it are not expected to participate.
- **reject** — the guard treats absent provenance as a violation and responds
  per §5.3. Appropriate where every legitimate caller is expected to
  participate, so an absent chain indicates a bypass.

A guard MUST NOT infer unrestricted authority from an absent or incomplete
chain under either disposition. Where a chain is present but records fewer
hops than the actual delegation path (partial deployment), the computed
effbound reflects the bounds actually recorded; the guarantee degrades
accordingly and the deployment MUST account for the unrecorded hops in its
declared unmediated set (§5.7).

### 5.5.2 Capability negotiation

This extension does not require capability negotiation under SEP-2133.

The provenance object is additive metadata under a reverse-DNS `_meta` key.
A participant that does not implement the extension ignores the key and
behaves exactly as it does today (§6, Backward Compatibility); a participant
that does implement it derives no benefit from knowing whether its peer does,
because the check is performed by the guard against the chain as recorded, not
negotiated between endpoints. There is consequently no interoperability
failure that negotiation would prevent.

Deployments that require assurance their peers participate SHOULD establish
that out of band, and MUST reflect any non-participating path in their
declared unmediated set (§5.7).

### 5.6 Declaring the unmediated set

The guarantee in this specification holds over effects that traverse the
mediated path. Effects reachable by other means — in-process tool invocation,
direct system access from a code-execution tool, or any channel that does not
pass a conforming guard — are outside it.

Deployments claiming conformance MUST publish the set of authority-bearing
effects reachable outside the mediated path (the *unmediated set*, U).
Deployments MUST NOT claim conformance while treating U as empty by
assumption; U MUST be established by inspection of the deployment, not
asserted.

Where U is nonempty, the guarantee is that no-escalation holds over the
complement of U. This is a weaker but well-defined claim, and it is the claim
a deployment with a nonempty U is entitled to make. It corresponds to the
graceful-degradation result in the formal model (`Degradation.lean`, T2u).

Rationale: every mechanism in this family depends on the mediated path being
the only path. Requiring U to be declared converts an unstated assumption into
a checkable deployment property. An audit method for establishing U
empirically, rather than by self-report, is demonstrated in the reference
repository under `instantiation/`.

### 5.7 Conformance requirements

A deployment conforms to this extension if and only if it satisfies:

- **R1 (no ambient authority).** Components act only on conferred capabilities; a component cannot reach authority absent from its inbound effbound.
- **R2 (framework-owned provenance).** π is constructed by the framework/guard and is not modifiable by the components whose calls it describes. Under this version, R2 is satisfied by a documented trusted path or an out-of-band integrity binding (§5.5), not by a mechanism this specification defines. A deployment that cannot establish R2 does not conform.
- **R3 (deputy contracts).** A component holding ambient authority the guard cannot mediate enforces its own effbound check before acting.
- **R4 (bounds only narrow).** No component confers a bound wider than its inbound effbound; no operation widens an established bound.
- **R5 (mediation, or declared exception).** Every effect an untrusted component can cause is either guard-mediated or enumerated in a declared unmediated set U. The guarantee holds on all effects outside U. (A deployment MUST enumerate U rather than leave it implicit.)
- **R6 (tool-call granularity).** Enforcement is at the tool-call boundary; sub-call traffic is not separately checked.

A deployment meeting R1–R6 inherits the no-escalation guarantee proved for the formal model (`CLAIMS.md`, T1–T4): no component causes an effect outside effbound, preserved under delegation, chaining, and narrowing, with revocation effective under the stated conditions.

## 6. Related Work and Positioning

*(Stub — pending expert feedback. Will position against the object-capability lineage, the ABLP/Taos authorization-logic tradition, DIFC, and the current wave of agent-authority mechanisms, per `reviewer-packet.md`.)*

## 7. Security Considerations

This extension provides a **structural** guarantee: if its assumptions hold, effect escalation is impossible regardless of what a model intends or is induced to intend, including by prompt injection. The value of that guarantee is bounded precisely by its assumptions and its scope, both stated here without softening.

### 7.1 Assumptions the guarantee rests on

- **Unforgeable capabilities (R1).** Components cannot construct or name authority they were not conferred. If a component can synthesize a capability, effbound is meaningless.
- **Framework-owned provenance (R2).** π is constructed by the guard and not modifiable by the components it describes. A component able to rewrite its own provenance can claim any authority, and this specification defines no mechanism preventing that: R2 rests entirely on a documented trusted path or an out-of-band integrity binding (§5.5). This is the largest assumption in the trust surface and the most likely to be violated silently in a real deployment.
- **Deputy contract discharge (R3).** A component holding ambient credentials the guard cannot mediate must enforce its own effbound check. The guarantee does not cover a deputy that holds broad authority and does not self-check.
- **Mediation (R5).** Effects reach the world only through mediated calls, except for a declared set U. An unmediated actuator — a shell, an interpreter, raw network access — is outside the guarantee. A deployment that does not enumerate U has not established the precondition for the guarantee on the effects that escape.

These assumptions are the extension's trust surface. They are enumerable and checkable (that is the point of stating them as R1–R6), but they are not zero. An adversary with the capability to attack the trust surface — forging provenance, subverting a deputy, reaching an unmediated actuator — attacks *there*, not through the effbound check, which holds.

### 7.2 Out of scope

- **Influence.** This extension bounds *authority* — what a component may cause. It does not bound *influence* — what a component may communicate or induce through effects it is permitted to cause. A confined component can still be steered, by prompt injection or otherwise, into misusing authority it legitimately holds; and covert channels through permitted effects (timing, content, ordering) are not addressed. Bounding influence is a distinct property with known non-composability obstacles and is deliberately not attempted here.
- **Bound selection.** This extension enforces that effects stay within the conferred bound. It says nothing about whether the conferred bound is the *correct* one. A perfectly enforced but wrongly chosen bound is a hazard the extension does not detect. Choosing bounds that match intent is a deployment responsibility.
- **Result-side mediation.** This version checks outbound calls, not inbound results. A server returning a capability handle or sensitive content in a result is not currently constrained (the Membrane property, reserved for a future version).
- **Model-internal modification.** The extension governs effects a component causes through tool calls. It does not govern a component's modification of its own reasoning or substrate by means other than mediated calls.

### 7.3 What conformance buys, stated plainly

A conforming deployment converts one class of agent harm — effect escalation beyond conferred authority — from a property that depends on model behavior into one that depends on architecture. Within the assumptions of §7.1 and the scope of §7.2, that class of harm is structurally prevented rather than behaviorally discouraged. This is a meaningful reduction in blast radius. It is not a claim that a conforming agent is safe.

## 8. References

- [RFC2119] / [RFC8174] — BCP 14 requirement-level keywords.
- SEP-414 — W3C Trace Context propagation in `_meta`.
- SEP-2133 — MCP Extensions framework.
- SEP-2567 — stateless core (session removal).
- This repository — `CLAIMS.md` (claim ledger), `lean/` (formal model), `proxy/` (reference implementation).
