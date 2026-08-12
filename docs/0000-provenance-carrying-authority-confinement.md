# SEP-0000: Provenance-Carrying Authority Confinement for Delegated Tool Calls

- **Status**: draft
- **Type**: Extensions Track
- **Created**: 2026-07-25
- **Author(s)**: Alina Shah (@alinamiretai)
- **Sponsor**: TBD
- **PR**: TBD
- **Extension namespace**: `io.noescalation`

## Abstract

This extension carries **authority provenance** on MCP tool calls: a record of the delegation chain that led to each call, together with the bound each delegating component attached. A guard positioned on the call path uses this record to enforce **no-escalation** — that a component causes no effect beyond what was conferred on it, preserved as authority is delegated, chained through deputies, and narrowed over a session.

The extension defines: the provenance object and where it rides (§4.2), the language in which a bound denotes a set of effects (§4.3), the `meet` operation that accumulates conferral down a chain (§4.3.3), and the processing rules a conforming guard follows (§4.4). The guarantee the extension provides, and the assumptions it rests on, are stated as conformance requirements (§4.4.7) and in Security Implications.

## Motivation

MCP calls arrive at a server with no record of the authority path that produced
them. A server sees a well-formed `tools/call` from a client holding valid
credentials, and executes it. It has no way to determine whether the caller was
acting within the authority actually conferred on it, because the protocol
carries nothing about conferral.

This is not hypothetical. Delegation is now the common case: a host agent
decomposes a task and dispatches subtasks to sub-agents, which call tools.
Authority flows down that path, and at each step the delegator may intend to
confer *less* than it holds — "you may file issues, but only on this
repository." Nothing in MCP records that narrowing, and nothing at the tool
boundary checks against it.

The failure this permits is the confused deputy. A sub-agent narrowed to one
resource is induced — by prompt injection, by a malicious tool result, by an
ordinary bug — to request a different one. The request is well-formed. The
credential is valid. The server executes it. No component in the path did
anything a local check would flag: the sub-agent asked, the server answered, and
the constraint the delegator imposed was never represented anywhere it could be
enforced.

Three properties make this a protocol-level concern rather than an
implementation concern.

**It is invisible locally.** Every participant behaves correctly with respect to
the information available to it. The server cannot detect the violation because
the information needed to detect it — what the delegator conferred — never
reached the server.

**It composes badly.** Deployments increasingly chain more than two hops. A
constraint imposed at hop one must bind at hop four; without a carried record,
each hop can enforce only what it locally knows, and a narrowing is lost as soon
as the narrowing component is no longer in the request path.

**Point-of-use authorization does not address it.** OAuth scopes, RAR payloads,
and per-call authorization all answer "does this caller hold a credential
adequate for this call?" That question has a correct answer here — yes — and the
call is still outside what was conferred. The missing check is not stronger
credentials but a comparison against the delegation path.

### Convergence, and what it leaves unspecified

This gap has been independently identified by several recent proposals, which
have converged on the same mechanism: authority conferred along a delegation
chain, attenuated at each hop, with effective authority given by the
intersection of the chain. AIP carries it as an append-only token chain with
cryptographic subset enforcement at each delegation block. ACP carries it as
chained capability tokens linked by `parent_hash`, with "no privilege
escalation" as a stated protocol property. The Five-Plane reference architecture
elevates it to a structural primitive, defining the effective capability set as
the intersection of the capability sets along the delegation chain and arguing
that this construction forecloses the confused deputy.

The convergence is itself an argument for standardization: MCP's design
principles favor codifying patterns that have proven valuable across multiple
implementations over inventing new ones, and independent adoption by several
proposals is that evidence.

But convergence on a mechanism is not agreement on its semantics. None of these
proposals specifies what the mechanism guarantees under composition, under
revocation, or under concurrent execution — and where each addresses the
question at all, it does so by an explicitly bounded method (see Rationale).
Implementations can therefore diverge on continuation capture, on revocation
timing, and on concurrent overlap while each remains internally consistent, with
no way for a deployment to detect that two conforming implementations disagree
about which calls are permitted. That is a protocol-level problem, and it is the
case for a protocol-level answer: a wire format with a specified meaning, and a
conformance suite that makes disagreement detectable.

## Specification

### 1 Terminology

**Effect.** A tool invocation with its arguments — the unit at which authority is granted and checked. Traffic below this granularity (pagination, token refresh, cache reads) is implementation of an effect, not a separate effect.

**Component.** A participant on the call path that MAY delegate: a host, an agent, a sub-agent, or a deputy (an MCP server holding ambient credentials).

**Bound (β).** A set of effects a component is permitted to cause. Encoded on the wire as a union of rules (§4).

**Provenance chain (π).** An ordered, append-only sequence of hops, oldest first. Each hop records a component and the bound it attached when delegating. π is the wire form of the delegation history.

**effbound.** The effects a call is permitted, given π: the intersection (`meet`) of every attached bound along the chain. A guard admits a call if and only if it lies within effbound.

**Guard.** A component that constructs or extends π and enforces effbound. The reference implementation is a proxy on the stdio path between host and server.

**Conferral.** The act of a component attaching a bound when delegating. Conferral only narrows: a component MUST NOT confer authority it does not itself hold.

### 2 The Provenance Object

#### 3.1 Location

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

#### 3.2 Structure

The provenance object has:

- `v` (integer, REQUIRED): schema version. This document defines `v: 1`. A guard receiving an unrecognized `v` MUST fail closed (§4.4.3). `v` applies to the provenance object as a whole, not per hop: a guard extending a chain MUST NOT alter `v`, and MUST fail closed rather than extend a chain whose `v` it does not implement.
- `chain` (array, REQUIRED): the hops, oldest first. Each hop is an object with:
  - `component` (string, REQUIRED): an identifier for the delegating component. Opaque to the meet; used for audit.
  - `bound` (array of rules, REQUIRED): the bound attached at this hop (§4).
- `sig` (string, RESERVED): reserved for a future revision specifying an integrity binding. Under this version, implementations MUST NOT populate this field, and a guard MUST ignore it if present (§4.4.5).

The chain is **append-only**. A component extending π MUST append a hop and MUST NOT modify, remove, or reorder existing hops.

### 3 Bounds

#### 4.1 Rules

A **bound** is a JSON array of **rules**. A call is within the bound if and only if it matches **at least one** rule (rules are alternatives — union within a bound).

An **empty bound** (`[]`) admits nothing: no rule matches, so every call is
outside it. A hop attaching an empty bound confers no authority, and any chain
containing such a hop has an empty effbound. This is the correct reading of
full revocation and MUST NOT be treated as "unconstrained."

An **empty chain** (`"chain": []`) likewise confers no authority and MUST be
treated as admitting nothing. A guard MUST NOT interpret an empty chain as an
absent chain; absent provenance is handled by §4.4.5.1.

A **rule** is an object:

```json
{ "tool": "create_issue", "args": { "repo": { "in": ["acme/app"] } } }
```

- `tool` (string, REQUIRED): the tool name this rule permits.
- `args` (object, OPTIONAL): a map from argument name to **constraint** (§4.3.3.2). An argument not named is unconstrained.

A call `(name, arguments)` matches a rule if and only if: `name` equals the rule's `tool`, and for every constrained argument, the argument is present and its value satisfies the constraint. Unconstrained arguments place no restriction.

#### 4.2 Constraints

A constraint restricts one argument's value. The constraint operators are exactly:

```
constraint ::= { "eq":     value }        // equals value
             | { "in":     [ value, ... ] } // member of the set
             | { "prefix": string }        // string starts with prefix
             | { "glob":   string }        // matches shell-glob pattern
             | { "and":    [ constraint, ... ] } // satisfies all (see §4.3.3)
```

A guard MUST support all five. A guard MUST NOT admit an operator outside this set; in particular, arbitrary regular expressions and numeric ranges are excluded — see §4.3.4 for why this set and no other.

##### 4.2.1 Type compatibility

Each operator is defined over a value type. `eq` and `in` compare JSON values
for equality (§4.3.3.2.3). `prefix` and `glob` are defined over JSON strings only.

If a constraint is applied to an argument whose JSON type is incompatible with
the operator — `prefix` or `glob` against a number, boolean, null, array, or
object — the constraint MUST evaluate to **no match**. A guard MUST NOT coerce
the value to a string, and MUST NOT treat a type mismatch as an error that
bypasses the check. The rule simply fails to match, and the call is rejected
unless some other rule in the bound admits it.

##### 4.2.2 Canonicalization (normative)

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

##### 4.2.3 `eq` and `in` comparison

`eq` and `in` compare canonicalized values. Two values are equal if they have
the same JSON type and: for strings, are equal after §4.3.3.2.2; for numbers, are
numerically equal; for booleans and null, are identical. Arrays and objects
compare by deep structural equality with object keys unordered.

##### 4.2.4 `glob` dialect (normative)

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
(unterminated `[`, trailing `\`) as malformed (§4.4.3) rather than attempting
recovery.

#### 4.3 The `meet`

`meet` is the operation that accumulates conferral down the chain. It has two levels, which MUST NOT be conflated:

- **Within a bound:** the rules are a **union** (a call is in the bound if it matches some rule).
- **Across hops:** the bounds are **intersected** (a call is in effbound if it is admitted by *every* hop's bound).

`effbound(π)` is therefore the meet of all hops' bounds: `meet(β₁, β₂, …, βₙ)`, where `meet` of two bounds is the rule set `{ meet(r₁, r₂) : r₁ ∈ B₁, r₂ ∈ B₂ }` with empty results dropped, and `meet` of two rules conjoins their argument constraints (dropping the rule if any argument's constraint intersection is empty).

The intersection of two constraints on the same argument MUST be exact: it MUST NOT admit a value outside either input. Where two constraints have no single-operator intersection, their meet is expressed as an `{ "and": [...] }` constraint — satisfy both — which is exact. (This is why the operator set is closed: the meet of any two constraints is always expressible, as a conjunction if not more simply.)

This `meet` corresponds to pointwise conjunction of attached bounds along the chain, the operation proved in the formal model (`Kernel.lean`, `meet_sub_hop`).

#### 4.4 Why this operator set (normative rationale)

The operator set is `{eq, in, prefix, glob, and}` and no other, for one reason: **`meet` must stay in the language.** A guard computes effbound by intersecting bounds; if the intersection of two admissible constraints could not be expressed as an admissible constraint, the guard could not compute conferral, and the no-escalation guarantee would not hold at the wire level.

- `eq`, `in`, `prefix`, `glob` are each closed under intersection (with `and` capturing irreducible cases). Admitted.
- **Regular expressions are excluded**: the intersection of two regular expressions is not, in general, a regular expression, so `meet` would escape the language.
- **Numeric ranges are excluded**: no authority-bearing numeric argument has been observed in surveyed tools — numeric arguments are pagination (a resource concern, not authority) or object identifiers (authorized by their containing resource, a string, never by numeric range). A future extension version MAY add a `range` operator (it is closed under intersection) if an authority-bearing numeric argument arises.

Every admitted operator except `range` (were it added) is a string operator, reflecting that authority in this domain is denoted by strings: repository names, paths, owners, tool names.

### 4 Processing Rules

A **guard** is a component that constructs or extends π and enforces effbound. This section specifies what a conforming guard MUST do. The reference implementation (`proxy/guard.py`) follows these rules.

#### 5.1 Constructing and extending π

On a `tools/call` it processes, a guard MUST determine the outbound provenance chain as follows:

1. **Read** any inbound chain from `_meta["io.noescalation/provenance"]` (§3).
2. **Extend** it by appending exactly one hop whose `component` is the guard's own component identifier and whose `bound` is the bound this component confers (its policy).
   - If no inbound chain is present, the guard MUST start a new chain (`v: 1`, empty) and append its single hop.
   - The guard MUST NOT modify, remove, or reorder existing hops (§4.3.3.2.2, append-only).
3. **Attach** the resulting chain to the outbound message's `_meta` under the reserved key before forwarding.

A component MUST NOT confer, in the bound it attaches, authority it does not itself hold. (This is the conferral-only-narrows discipline; a guard that attaches a bound wider than its own inbound effbound violates the extension.)

#### 5.2 Checking effbound

Before forwarding a `tools/call`, the guard MUST compute `effbound` as the `meet` of every hop's bound in the extended chain (§4.3.3) and determine whether the call `(name, arguments)` lies within it (§4.3.3.1).

- If the call is within effbound, the guard MUST forward it (with the extended π attached).
- If the call is **not** within effbound, the guard MUST NOT forward it; it MUST respond per §4.4.3.

Messages that are not `tools/call` (initialization, `tools/list`, notifications, results) are outside the scope of effbound checking in this version and MUST be relayed unchanged. (Result-side mediation — the Membrane property — is reserved for a future version; see Security Implications.)

#### 5.3 Fail-closed behavior

A guard MUST fail closed. Specifically:

- A `tools/call` outside effbound MUST NOT reach the server. The guard MUST return a JSON-RPC error to the caller with code `-32001` and a `message` naming the extension and the rejected tool. The error `data` SHOULD include the tool name and arguments for audit.
- A provenance object with an unrecognized `v` or a malformed chain MUST be treated as a violation and rejected as above. A guard MUST NOT fall back to forwarding a call whose provenance it cannot parse. (Absent provenance is not malformed provenance; see §4.4.5.1.)
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

#### 5.4 Modes

A guard MUST support **enforce** mode (the default), in which violations are rejected per §4.4.3. A guard MAY support **audit** mode, in which a violation is logged and the call is nonetheless forwarded. Audit mode exists for safe rollout — a deployment can observe what enforce mode *would* reject before enabling it. A guard in audit mode MUST record each would-be rejection. A guard's mode MUST default to enforce; audit MUST be explicit opt-in.

#### 5.5 Chain integrity

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

The `sig` field in §4.3.3.2.2 is reserved for a future revision that specifies a
binding directly. Implementations MUST NOT populate it under this version, and
a guard MUST ignore it if present. Prior work on signed capability tokens with
per-hop attenuation demonstrates that a chained construction is achievable;
the omission here is scope, not feasibility.

#### 5.5.1 Absent provenance

A guard MAY receive a `tools/call` carrying no `io.noescalation/provenance`
key — from a non-participating client, or as the first hop in a chain. This is
distinct from a malformed chain (§4.4.3) and MUST NOT be treated as a violation
on that basis alone.

A guard MUST be configured with one of two dispositions for absent provenance,
and the disposition MUST be explicit rather than defaulted silently:

- **originate** — the guard treats itself as the origin of the chain,
  constructs a new chain per §4.4.1, and checks against its own conferred bound
  alone. Appropriate where the guard sits at the trust boundary of the
  deployment and callers upstream of it are not expected to participate.
- **reject** — the guard treats absent provenance as a violation and responds
  per §4.4.3. Appropriate where every legitimate caller is expected to
  participate, so an absent chain indicates a bypass.

A guard MUST NOT infer unrestricted authority from an absent or incomplete
chain under either disposition. Where a chain is present but records fewer
hops than the actual delegation path (partial deployment), the computed
effbound reflects the bounds actually recorded; the guarantee degrades
accordingly and the deployment MUST account for the unrecorded hops in its
declared unmediated set (§4.4.7).

#### 5.5.2 Capability negotiation

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
declared unmediated set (§4.4.7).

#### 5.6 Declaring the unmediated set

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

#### 5.7 Conformance requirements

A deployment conforms to this extension if and only if it satisfies:

- **R1 (no ambient authority).** Components act only on conferred capabilities; a component cannot reach authority absent from its inbound effbound.
- **R2 (framework-owned provenance).** π is constructed by the framework/guard and is not modifiable by the components whose calls it describes. Under this version, R2 is satisfied by a documented trusted path or an out-of-band integrity binding (§4.4.5), not by a mechanism this specification defines. A deployment that cannot establish R2 does not conform.
- **R3 (deputy contracts).** A component holding ambient authority the guard cannot mediate enforces its own effbound check before acting.
- **R4 (bounds only narrow).** No component confers a bound wider than its inbound effbound; no operation widens an established bound.
- **R5 (mediation, or declared exception).** Every effect an untrusted component can cause is either guard-mediated or enumerated in a declared unmediated set U. The guarantee holds on all effects outside U. (A deployment MUST enumerate U rather than leave it implicit.)
- **R6 (tool-call granularity).** Enforcement is at the tool-call boundary; sub-call traffic is not separately checked.

A deployment meeting R1–R6 inherits the no-escalation guarantee proved for the formal model (`CLAIMS.md`, T1–T4): no component causes an effect outside effbound, preserved under delegation, chaining, and narrowing, with revocation effective under the stated conditions.
## Rationale

### Related work

Four bodies of work bear directly on this proposal.

**AIP (Agent Identity Protocol).** AIP addresses agent *identity*: neither MCP
nor A2A verifies who an agent is, and a scan of ~2,000 MCP servers found none
with authentication. AIP introduces Invocation-Bound Capability Tokens, which
fuse identity, attenuated authorization, and provenance into an append-only
token chain, in two wire formats (a signed JWT for single-hop, a Biscuit token
with Datalog policies for multi-hop). Scope attenuation is enforced
cryptographically: a delegation block attempting to widen any capability fails
verification.

AIP's delegation model and this extension's are close relatives, and the
difference is worth stating precisely. AIP verifies that a *signed artifact*
is internally consistent — that block N's claimed scope is a subset of block
N−1's — at token-verification time. This extension computes an intersection at
the tool boundary from bounds recorded per hop, and specifies what that
intersection means. The two are complementary rather than competing: AIP
authenticates the chain; this extension specifies what the chain confers.

AIP's own threat model marks the relevant gap. Under "dishonest verifier" it
records: a verifier that skips signature checks, ignores policy evaluation, or
accepts expired tokens can grant unauthorized access, and AIP assumes the
verifier is trusted and correctly implemented — verifier compliance is
described as an operational concern addressed through conformance testing and
reference implementations, "not a property the protocol can enforce
cryptographically." AIP's seven-property gap analysis (public-key
verification, holder attenuation, expressive policy, cross-protocol bindings,
provenance binding, no heavy infrastructure, lifecycle awareness) does not
include a property for the semantics of the attenuation itself. This is not an
oversight on AIP's part — it is outside that paper's scope — but it locates
what this proposal adds.

**ACP (Agent Control Protocol).** ACP addresses a different axis: *temporal*
admission control. Its contribution is that properties depending on execution
history — anomaly accumulation, cooldown, rate patterns — cannot be enforced
by stateless per-request evaluation regardless of scoring function. ACP's
delegation mechanism (ACP-DCMA) states the same subset property, verified at
each hop via `parent_hash`.

ACP and this extension are orthogonal along the axis each addresses. This
extension asks whether a single call is inside what was conferred along its
chain. ACP asks whether a sequence of individually-conferred calls constitutes
an attack. Both can hold or fail independently, and ACP's own framing —
that it "does not replace" existing policy engines but "adds a stateful
enforcement layer above them" — describes the composition accurately.

ACP is the most formally rigorous of the three, and is precise about what its
rigor covers: safety and liveness properties are model-checked in TLA+ over a
bounded state space, and the paper states that "the phrase 'formally verified'
is deliberately avoided; the correct claim is: model checking of selected
safety and liveness properties under a bounded state model." The TLA+ model
further abstracts two factors (context and history) out of the risk formula it
checks. This is honest and unusual practice; it also means the bounded/
unbounded distinction is stated by the authors themselves rather than asserted
here.

**Five-Plane reference architecture.** The closest prior art to this
proposal's core construction. It defines the effective capability set of a
composite principal as the intersection of the capability sets along the
delegation chain, restricted to unexpired capabilities, and defines capability
attenuation as a structural primitive (each delegated set a subset of its
parent, enforced at delegation time and non-bypassable by composition). It
draws the same conclusion this proposal draws: attenuation-as-primitive
forecloses the classical confused deputy, because the deputy's privileges are
bounded by the intersection of the chain, by construction.

Two things follow. First, the construction in §4.3 of this specification is
not novel and this proposal does not claim it is; independent derivation by
several groups is the standardization argument, not a priority dispute.
Second, the Five-Plane architecture is explicit that its correctness
properties are "argued structurally, not formally proved," and its limitations
section states that formal verification of attenuation correctness at scale is
unsolved — that its reference implementation provides "property-based testing,
not formal verification," which "does not discharge the verification
obligation," left as future work. Its capability-set lattice claim notes that
the lattice structure "is what gives the formal-methods community a hook into
the architecture," and that properties of the form *no execution trace reaches
an effective capability set containing a capability not held by every hop in
the chain* are decidable on it.

That obligation is what the formal development accompanying this proposal
discharges for the property specified here, over unbounded chains and traces
(see Formal grounding).

**MCP authorization work.** SEP-2643 defines a structured denial envelope: how
a server communicates *why* an operation was denied and what remediation is
available. It is complementary to this proposal along a clean line — SEP-2643
concerns calls that produce a denial, this extension concerns calls that
produce none because the server has no basis to deny them. Adjacent work on
RAR metadata and multi-token client behavior addresses credential selection at
the point of use, which is likewise a different question from what a
delegation chain confers.

### Why an extension rather than adopting an existing proposal

MCP's design principles favor convergence over choice, and a reviewer is right
to ask why a fifth mechanism should exist. Three reasons.

**Scope.** AIP is an identity protocol; it exists because MCP servers do not
verify who is calling, and it necessarily bundles identity resolution, key
distribution, a Datalog policy engine, and a token format to do so. ACP is an
admission-control protocol with a risk engine, a ledger, and an institutional
trust anchor. Five-Plane is an enterprise reference architecture spanning five
planes. Each is substantially larger than the mechanism at issue here. This
extension assumes identity is handled by whatever the deployment already uses
and specifies one thing: the chain of conferred bounds, and the check against
their intersection. That is composability over specificity — the smallest
addition that expresses the property.

**Weight.** The mechanism here is a reverse-DNS `_meta` key and a subset
check. No new token format, no signature scheme, no policy runtime, no shared
state backend. This matters for interoperability over optimization: a
participant that cannot run a Biscuit verifier or a Datalog engine can still
implement this, and a participant that implements nothing at all is unaffected
(Security Implications, Backward Compatibility).

**Semantics.** This is the substantive difference. Each of the three proposals
above asserts that attenuation composes; none specifies what that guarantees.
Where a formal treatment exists it is explicitly bounded — TLA+ over a bounded
state space with an abstracted risk formula in ACP's case, property-based
testing over randomly generated chains in Five-Plane's case, and no formal
treatment in AIP's. The consequence is not that these proposals are wrong; it
is that a deployment cannot determine whether two conforming implementations
admit the same set of calls. A specification with a stated semantics and a
conformance suite makes that determinable.

### Formal grounding

The property specified here is mechanized in Lean 4, with no dependency on
Mathlib, and the development builds from a pinned toolchain. Proved over
unbounded chains and traces:

- **Soundness** — a call admitted by the guard lies within its effbound.
- **Chain conferral** — the meet is contained in every attached bound;
  equivalently, extending a chain can only shrink what is permitted, never
  widen it. This is the formal content of the attenuation primitive that the
  prior work states as a definition.
- **Composition** — the property holds in systems mixing conforming and
  non-conforming components, over the conforming subset.
- **Revocation effectiveness** — narrowing a filter mid-run is effective, with
  issuance fixed at invocation rather than at resumption. A weak form, which
  drops the quiescence assumption, is proved over traces with the residual
  window (effects licensed before the narrowing) named in the conclusion
  rather than assumed away.
- **Graceful degradation** — where some effects bypass the mediated path, the
  property holds over the complement of that unmediated set. This is the
  formal backing for the U-declaration requirement in §4.4.6.
- **Concurrency** — the property composes over a shared store under genuine
  overlap. This result is two-sided and is reported as such: spatial
  confinement survives concurrency; the temporal (revocation-timing) half does
  not transfer without an explicit happens-before order the model does not
  provide. That boundary is stated rather than elided, and it is, to the
  author's knowledge, the only treatment of attenuation under concurrent
  execution in this family of proposals.

The development proves properties of the model. It does not prove that any
implementation refines the model; that gap is stated in Security Implications and is the reason
the conformance vectors (Appendix A) exist as a separate artifact.

### Design decisions

**Why `_meta` rather than a header or a new method.** `_meta` is the
transport-independent extension point the base protocol already defines, and
unrecognized keys are ignored, which gives backward compatibility without
negotiation (§4.4.5.2). A reverse-DNS key is required for anything other than
the trace-context keys the base spec exempts. A header-based binding would be
HTTP-specific; a new method would not be an extension.

**Why the chain is self-contained per request.** The core protocol is
stateless; there is no session in which to accumulate a chain. Each request
therefore carries its own complete provenance.

**Why this operator set.** The constraint operators are `eq`, `in`, `prefix`,
`glob`, and `and`. The set is closed under intersection: the meet of any two
constraints is expressible in the same language. This is a requirement, not a
convenience — a guard must be able to compute and carry forward the
intersection of bounds attached at different hops without falling back to an
uncomputable representation. Regular expressions fail this test (the
intersection of two regular expressions is not in general a regular
expression), which is why they are excluded despite their expressiveness.
Numeric ranges were excluded on a separate empirical ground: an audit of a
production MCP server's tool schemas found that every authority-bearing
argument was a string, with numerics appearing only as pagination and
identity parameters.

**Why the meet, and not the performer's own bound.** Checking only the
performer's bound admits re-amplification: an effect inside the performer's
own grant but excluded by an earlier hop. Checking only the requester's chain
admits the confused deputy. Both are in the benchmark suite (Appendix A,
vectors C4 and C5) and both are rejected by running code in the reference
implementation.

**Why chain integrity is out of scope in this version.** Specifying an
integrity binding without a reviewed cryptographic design would be worse than
stating the gap. AIP demonstrates that a signed chained construction is
achievable; the omission here is scope, not feasibility. §4.4.5 states the
consequence explicitly and requires conforming deployments to establish a
trusted path or an out-of-band binding.

**Why declaring the unmediated set is normative.** Every mechanism in this
family — including all three surveyed above — depends on the mediated path
being the only path, and none requires that assumption to be checked.
Requiring the unmediated set to be declared converts an unstated assumption
into an auditable deployment property, and the graceful-degradation result
gives the guarantee that survives when the set is nonempty.

### Alternatives considered

**Adopt AIP and specify nothing.** Rejected because AIP requires an identity
infrastructure (DNS-resolvable identity documents or self-certifying keys, key
rotation, a Biscuit or JWT verifier) that a deployment may not want in order
to obtain confinement, and because it does not specify the semantics of the
attenuation it enforces.

**Put the bound in OAuth scopes or RAR.** Rejected because both are
point-of-use constructs: they describe what the caller holds, not what each
hop conferred. A downstream agent holding a valid credential is exactly the
case this proposal addresses.

**Server-side policy only.** Rejected because it inverts the direction of the
information. A server cannot know what a delegator upstream of its caller
intended to confer; only the delegator can state it, and only the wire can
carry it. This also preserves the working group's position that MCP defines
authorization communication rather than policy: the bound is a caller's
declaration of what it hands downstream, not a server publishing its policy,
and the server remains authoritative and free to deny anything.

**Wait for convergence.** Rejected because the mechanisms have already
converged; what has not converged is their meaning, and further independent
implementation without a specified semantics increases divergence rather than
resolving it.


## Backward Compatibility

This extension introduces no backward incompatibilities.

The provenance object is carried in `_meta` under the reverse-DNS key
`io.noescalation/provenance`. Per the base specification, implementations ignore
`_meta` keys they do not recognize. A server that does not implement this
extension therefore behaves exactly as it does today when receiving a request
carrying the key: it is ignored and the call proceeds under whatever
authorization the server already applies. This has been verified against the
official `@modelcontextprotocol/server-filesystem` reference server, which
accepted a `tools/call` carrying the key and completed a `read_file` normally.

Clients that do not implement this extension emit no `io.noescalation` key. A
conforming guard encountering a request without provenance applies the
partial-deployment rules in §4.4.5.1 rather than failing the request outright, so
a non-conforming client is not broken by the presence of a conforming guard
elsewhere in the path.

The extension adds no new methods, no new message types, and no changes to
existing message schemas. It is purely additive metadata plus processing rules
for participants that opt in. No capability negotiation is required; the
rationale is given in §4.4.5.2.

**Partial deployment.** In a chain where some hops implement the extension and
some do not, the chain records only the participating hops. The guarantee
degrades correspondingly: the computed effbound reflects the bounds actually
recorded, not the bounds that would have been recorded under full deployment. A
non-participating hop appears as an absent link, not as an unbounded one.
Deployments MUST NOT interpret an incomplete chain as conferring unrestricted
authority, and MUST account for unrecorded hops in the declared unmediated set
(§4.4.6).

## Security Implications

This extension provides a **structural** guarantee: if its assumptions hold, effect escalation is impossible regardless of what a model intends or is induced to intend, including by prompt injection. The value of that guarantee is bounded precisely by its assumptions and its scope, both stated here without softening.

### Assumptions the guarantee rests on

- **Unforgeable capabilities (R1).** Components cannot construct or name authority they were not conferred. If a component can synthesize a capability, effbound is meaningless.
- **Framework-owned provenance (R2).** π is constructed by the guard and not modifiable by the components it describes. A component able to rewrite its own provenance can claim any authority, and this specification defines no mechanism preventing that: R2 rests entirely on a documented trusted path or an out-of-band integrity binding (§4.4.5). This is the largest assumption in the trust surface and the most likely to be violated silently in a real deployment.
- **Deputy contract discharge (R3).** A component holding ambient credentials the guard cannot mediate must enforce its own effbound check. The guarantee does not cover a deputy that holds broad authority and does not self-check.
- **Mediation (R5).** Effects reach the world only through mediated calls, except for a declared set U. An unmediated actuator — a shell, an interpreter, raw network access — is outside the guarantee. A deployment that does not enumerate U has not established the precondition for the guarantee on the effects that escape.

These assumptions are the extension's trust surface. They are enumerable and checkable (that is the point of stating them as R1–R6), but they are not zero. An adversary with the capability to attack the trust surface — forging provenance, subverting a deputy, reaching an unmediated actuator — attacks *there*, not through the effbound check, which holds.

### Out of scope

- **Influence.** This extension bounds *authority* — what a component may cause. It does not bound *influence* — what a component may communicate or induce through effects it is permitted to cause. A confined component can still be steered, by prompt injection or otherwise, into misusing authority it legitimately holds; and covert channels through permitted effects (timing, content, ordering) are not addressed. Bounding influence is a distinct property with known non-composability obstacles and is deliberately not attempted here.
- **Bound selection.** This extension enforces that effects stay within the conferred bound. It says nothing about whether the conferred bound is the *correct* one. A perfectly enforced but wrongly chosen bound is a hazard the extension does not detect. Choosing bounds that match intent is a deployment responsibility.
- **Result-side mediation.** This version checks outbound calls, not inbound results. A server returning a capability handle or sensitive content in a result is not currently constrained (the Membrane property, reserved for a future version).
- **Model-internal modification.** The extension governs effects a component causes through tool calls. It does not govern a component's modification of its own reasoning or substrate by means other than mediated calls.

### What conformance buys, stated plainly

A conforming deployment converts one class of agent harm — effect escalation beyond conferred authority — from a property that depends on model behavior into one that depends on architecture. Within the assumptions of §7.1 and the scope of §7.2, that class of harm is structurally prevented rather than behaviorally discouraged. This is a meaningful reduction in blast radius. It is not a claim that a conforming agent is safe.

## Reference Implementation

A reference implementation is available at
`https://github.com/alinamiretai/no-escalation` under `proxy/`. It is a
dependency-free Python stdio proxy that constructs and extends the provenance
chain, computes effbound, and rejects violations fail-closed.

**Setup and running** (Python 3, no dependencies):

```
git clone https://github.com/alinamiretai/no-escalation
cd no-escalation/proxy
python3 provenance.py        # data-model self-test
python3 test_attacks.py      # four benchmark attacks, rejected fail-closed
python3 test_multihop.py     # multi-hop delegation composition
python3 test_vectors.py      # the conformance vectors in Appendix A
python3 test_meta_realhost.py  # _meta accepted by a real MCP server (needs Node)
```

**Implemented and tested:**

- Construction and extension of the chain across multiple hops (`guard.py`)
- `meet` over the constraint operator set, exact and sound for all operator
  pairs, verified by the meet-soundness vectors in Appendix A
- Canonicalization and the glob dialect (`canonical.py`) per §4.3.2.2 and
  §4.3.2.4
- effbound checking with fail-closed rejection (JSON-RPC error `-32001`)
- Enforce and audit modes
- Four benchmark attacks rejected (`test_attacks.py`)
- Multi-hop delegation composition: a later hop's narrowing binds against an
  earlier broader grant (`test_multihop.py`)
- The full conformance vector suite (`test_vectors.py`), passing
- `_meta` acceptance verified against a real MCP server
  (`test_meta_realhost.py`)

**Specified but not yet implemented:**

- Revocation (filter narrowing mid-session). The property is proved in the
  formal development; the running guard does not yet expose a narrow operation.
- Chain integrity binding (§4.4.5). The reference implementation is the sole
  constructor and consumer of the chain, so integrity holds by construction in
  that deployment and is not exercised.
- Result-side mediation. Deliberately out of scope for this version.

**Formal development.** The property specified here is mechanized in Lean 4
(Mathlib-free, pinned toolchain) in the same repository under `lean/`, and
reproduces with `lake build`. It proves soundness, chain conferral, composition,
revocation effectiveness, graceful degradation, and robustness under
concurrency, over unbounded chains and traces. The development proves properties
of the model; it does not prove that the Python implementation refines the
model. That gap is stated explicitly rather than elided, and is the reason the
conformance vectors exist as a separate artifact.

**Conformance vectors.** Appendix A contains a worked three-hop delegation
example and a suite of conformance vectors covering composition, degenerate
cases, constraint operators, meet soundness, and rule/argument handling. A guard
passing the suite satisfies the mechanical requirements of §4.3 and §4.4.5.1; it
does not thereby satisfy §4.4.5 (chain integrity) or §4.4.6 (declared unmediated
set), which are deployment properties and cannot be established by testing a
guard in isolation.

## Appendix A — Worked Example and Conformance Test Vectors

### A.1 A worked delegation

A host agent is granted access to two repositories. It dispatches planning to a
planner, which dispatches a subtask to a worker. Each hop narrows.

### Stage 1 — host originates

The host's guard receives a `tools/call` with no inbound provenance. Its
disposition is `originate` (§5.5.1), so it constructs a chain and appends its
own hop:

```json
{
  "v": 1,
  "chain": [
    { "component": "host",
      "bound": [
        { "tool": "create_issue", "args": { "repo": { "in": ["acme/app", "acme/docs"] } } },
        { "tool": "read_file",    "args": { "path": { "prefix": "/srv/acme/" } } }
      ] }
  ]
}
```

**effbound** = the host's bound (one hop, nothing to intersect):
`create_issue` on `acme/app` or `acme/docs`; `read_file` under `/srv/acme/`.

### Stage 2 — planner narrows

The planner dispatches a subtask that only needs one repository. Its guard
appends a hop (§5.1) and MUST NOT modify the existing one:

```json
{
  "v": 1,
  "chain": [
    { "component": "host",
      "bound": [
        { "tool": "create_issue", "args": { "repo": { "in": ["acme/app", "acme/docs"] } } },
        { "tool": "read_file",    "args": { "path": { "prefix": "/srv/acme/" } } }
      ] },
    { "component": "planner",
      "bound": [
        { "tool": "create_issue", "args": { "repo": { "eq": "acme/app" } } }
      ] }
  ]
}
```

**effbound** = meet of both hops. Computed per §4.3:

- Across hops, bounds intersect. The planner's bound contains no `read_file`
  rule, so `read_file` drops out entirely.
- For `create_issue`, the argument constraints conjoin:
  `{"in": ["acme/app","acme/docs"]} ⊓ {"eq": "acme/app"}` = `{"eq": "acme/app"}`.

Result: **`create_issue` on `acme/app` only.** Note that `acme/docs` and
`read_file` are now unreachable for everything downstream of this hop, even
though the host conferred them.

### Stage 3 — worker calls

**Accepted call.**

```json
{ "method": "tools/call",
  "params": { "name": "create_issue", "arguments": { "repo": "acme/app", "title": "Fix login" } } }
```

Within effbound. `title` is unconstrained by the rule and therefore places no
restriction (§4.1). Forwarded with π attached.

**Rejected call — the confused deputy.**

```json
{ "method": "tools/call",
  "params": { "name": "create_issue", "arguments": { "repo": "acme/docs" } } }
```

`acme/docs` is inside the *host's* bound but outside the *planner's*. The meet
excludes it. This is the case a point-of-use authorization check cannot catch:
the worker holds a valid credential and the server would execute the call.
Rejected per §5.3:

```json
{ "jsonrpc": "2.0", "id": 7,
  "error": { "code": -32001,
    "message": "io.noescalation: 'create_issue' with these arguments is outside the conferred bound",
    "data": { "tool": "create_issue", "arguments": { "repo": "acme/docs" } } } }
```

**Rejected call — attempted re-amplification.**

Suppose the worker's own guard appends a hop conferring
`{"repo": {"in": ["acme/app", "evil/pwn"]}}` — wider than what it received.
Appending it is a violation of §5.1, but even if it occurs, the meet is
unaffected: `evil/pwn` appears in no earlier hop, so it is excluded by
intersection. Widening downstream cannot restore authority (`Kernel.lean`,
`meet_hop_sub`).

---

### A.2 Conformance test vectors

Each vector is a chain, a call, and the required verdict. A conforming guard
MUST produce the stated verdict for every vector. Machine-readable form:
`vectors.json` in the reference repository.

Bounds are abbreviated: `T{args}` denotes a rule for tool `T`.

### A.2.1 Composition

| # | Chain (bounds per hop) | Call | Verdict | Tests |
|---|---|---|---|---|
| C1 | `[ create{repo:eq acme/app} ]` | `create{repo:acme/app}` | **accept** | single hop, in bound |
| C2 | `[ create{repo:eq acme/app} ]` | `create{repo:acme/docs}` | **reject** | single hop, out of bound |
| C3 | `[ create{repo:in[app,docs]}, create{repo:eq app} ]` | `create{repo:app}` | **accept** | survives narrowing |
| C4 | `[ create{repo:in[app,docs]}, create{repo:eq app} ]` | `create{repo:docs}` | **reject** | **confused deputy** — in hop 1, not hop 2 |
| C5 | `[ create{repo:eq app}, create{repo:in[app,evil]} ]` | `create{repo:evil}` | **reject** | **re-amplification** — later hop cannot widen |
| C6 | `[ create{repo:in[a,b]}, create{repo:in[b,c]}, create{repo:in[b,d]} ]` | `create{repo:b}` | **accept** | three-hop intersection |
| C7 | same as C6 | `create{repo:c}` | **reject** | in hops 2 only |
| C8 | `[ create{...}, read{...} ]` where hop 2 omits `create` | `create{...}` | **reject** | tool absent from a hop drops out |

### A.2.2 Empty and degenerate

| # | Chain | Call | Verdict | Tests |
|---|---|---|---|---|
| E1 | `[ create{repo:eq app}, [] ]` | `create{repo:app}` | **reject** | empty bound admits nothing (§4.1) |
| E2 | `chain: []` | any | **reject** | empty chain confers nothing |
| E3 | absent π, disposition `reject` | any | **reject** | §5.5.1 |
| E4 | absent π, disposition `originate` | call in guard's own bound | **accept** | §5.5.1 |
| E5 | `v: 99` | any | **reject** | unrecognized version fails closed |
| E6 | malformed chain (hop missing `bound`) | any | **reject** | §5.3 |

### A.2.3 Constraint operators

| # | Constraint | Argument value | Result | Tests |
|---|---|---|---|---|
| O1 | `{eq: "acme/app"}` | `"acme/app"` | match | |
| O2 | `{eq: "acme/app"}` | `"acme/App"` | **no match** | case-sensitive by default (§4.2.2) |
| O3 | `{in: ["a","b"]}` | `"b"` | match | |
| O4 | `{in: ["a","b"]}` | `"c"` | no match | |
| O5 | `{prefix: "/srv/acme/"}` | `"/srv/acme/x.txt"` | match | |
| O6 | `{prefix: "/srv/acme/"}` | `"/srv/acme/../../etc/passwd"` | **no match** | **path traversal** — canonicalize first (§4.2.2) |
| O7 | `{prefix: "/srv/acme/"}` | `"/srv/acme/%2e%2e/x"` | **no match** | percent-decode then normalize |
| O8 | `{glob: "acme/*"}` | `"acme/app"` | match | |
| O9 | `{glob: "acme/*"}` | `"acme/app/sub"` | **no match** | `*` MUST NOT cross `/` (§4.2.4) |
| O10 | `{glob: "acme/**"}` | `"acme/app/sub"` | match | `**` crosses `/` |
| O11 | `{glob: "acme/app"}` | `"xacme/app"` | no match | anchored at both ends |
| O12 | `{glob: "f[a-c]o"}` | `"fbo"` | match | character class |
| O13 | `{prefix: "/srv/"}` | `12345` (number) | **no match** | type mismatch, no coercion (§4.2.1) |
| O14 | `{glob: "a*"}` | `null` | **no match** | type mismatch |
| O15 | `{eq: 5}` | `5.0` | match | numeric equality (§4.2.3) |
| O16 | `{glob: "a[b"}` | any | **malformed** | invalid pattern rejected, not recovered |

### A.2.4 Meet of constraints

The meet MUST be exact: it MUST NOT admit a value outside either input, and
MUST NOT exclude a value inside both.

| # | Constraint A | Constraint B | Required meet | Tests |
|---|---|---|---|---|
| M1 | `{in: [a,b,c]}` | `{eq: b}` | `{eq: b}` | reduces |
| M2 | `{in: [a,b]}` | `{in: [b,c]}` | `{in: [b]}` | set intersection |
| M3 | `{in: [a]}` | `{in: [b]}` | **empty** — rule dropped | disjoint |
| M4 | `{prefix: "/srv/"}` | `{prefix: "/srv/acme/"}` | `{prefix: "/srv/acme/"}` | one implies other |
| M5 | `{prefix: "/a/"}` | `{prefix: "/b/"}` | **empty** — rule dropped | disjoint prefixes |
| M6 | `{eq: "acme/app"}` | `{glob: "acme/*"}` | `{eq: "acme/app"}` | eq tested against glob |
| M7 | `{eq: "acme/app/x"}` | `{glob: "acme/*"}` | **empty** | eq fails the glob (O9) |
| M8 | `{glob: "a*"}` | `{prefix: "ab"}` | `{prefix: "ab"}` or `and` | either exact form |
| M9 | `{glob: "*x"}` | `{glob: "y*"}` | `{and: [both]}` | no single-operator form; conjunction is exact |
| M10 | `{and: [X,Y]}` | `{Z}` | `{and: [X,Y,Z]}` | conjunction is associative |

**Soundness requirement.** For every meet vector, a guard MUST NOT admit a
value admitted by only one input. Vector M7 is the sharpest case: a naive
implementation reducing `eq ⊓ glob` to `eq` without testing membership admits
`acme/app/x`, which the glob excludes.

### A.2.5 Rules and arguments

| # | Bound | Call | Verdict | Tests |
|---|---|---|---|---|
| R1 | `[create{repo:eq a}, read{path:prefix /p/}]` | `read{path:/p/x}` | **accept** | union within a bound |
| R2 | `[create{repo:eq a}]` | `delete{repo:a}` | **reject** | tool not in bound |
| R3 | `[create{repo:eq a}]` | `create{repo:a, title:"anything"}` | **accept** | unconstrained arg unrestricted |
| R4 | `[create{repo:eq a}]` | `create{title:"x"}` | **reject** | constrained arg absent (§4.1) |

---

### A.3 Using these vectors

A guard passing A.2 satisfies the mechanical requirements of §4 and §5.5.1.
It does **not** thereby satisfy §5.5 (chain integrity) or §5.6 (declared
unmediated set), which are deployment properties and cannot be established by
testing the guard in isolation.


## Acknowledgments

This proposal's positioning benefited from the published work of the AIP, ACP,
and Five-Plane authors, whose independent convergence on chain attenuation
motivated the case for specifying its semantics, and whose explicit statements
about the bounds of their own formal treatments identified the gap this proposal
addresses.
