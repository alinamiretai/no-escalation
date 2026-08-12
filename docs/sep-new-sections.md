# New SEP sections — merge into ext-noescalation-spec.md

These are the sections the SEP format requires that the current spec lacks.
Rationale (§6) is deliberately NOT drafted here: it requires the prior-art
reading (AIP 2603.24775, ACP 2603.18829, Five-Plane 2606.12320) first.

---

## Preamble

```
SEP: 0000                      (rename to PR number once opened)
Title: Provenance-carrying authority confinement for delegated tool calls
Author: Alina Shah <email>
Status: draft
Type: Extensions Track
Created: <date>
Requires: SEP-414 (_meta trace context), SEP-2133 (extensions framework)
```

---

## 2. Motivation

MCP calls arrive at a server with no record of the authority path that
produced them. A server sees a well-formed `tools/call` from a client holding
valid credentials, and executes it. It has no way to determine whether the
caller was acting within the authority actually conferred on it, because the
protocol carries nothing about conferral.

This is not a hypothetical gap. Delegation is now the common case: a host
agent decomposes a task and dispatches subtasks to sub-agents, which call
tools. Authority flows down that path, and at each step the delegator may
intend to confer *less* than it holds — "you may file issues, but only on this
repository." Nothing in MCP records that narrowing, and nothing at the tool
boundary checks against it.

The failure this permits is the confused deputy. A sub-agent narrowed to one
resource is induced — by prompt injection, by a malicious tool result, by an
ordinary bug — to request a different one. The request is well-formed. The
credential is valid. The server executes it. No component in the path did
anything a local check would flag: the sub-agent asked, the server answered,
and the constraint the delegator imposed was never represented anywhere it
could be enforced.

Three properties of this failure make it a protocol-level concern rather than
an implementation concern:

**It is invisible locally.** Every participant behaves correctly with respect
to the information available to it. The server cannot detect the violation
because the information needed to detect it — what the delegator conferred —
never reached the server.

**It composes badly.** Deployments increasingly chain more than two hops. A
constraint imposed at hop one must bind at hop four; without a carried record,
each hop can only enforce what it locally knows, and a narrowing is lost as
soon as the narrowing component is no longer in the request path.

**Point-of-use authorization does not address it.** OAuth scopes, RAR payloads,
and per-call authorization all answer "does this caller hold a credential
adequate for this call?" That question has a correct answer here — yes — and
the call is still outside what was conferred. The missing check is not stronger
credentials but a comparison against the delegation path.

<!-- TODO after prior-art reading: the convergence argument.
     Several independent proposals (AIP, ACP, the Five-Plane architecture,
     HDP) have adopted attenuation-along-a-chain as the mechanism. None
     specifies what the mechanism guarantees, which means implementations can
     diverge on continuation capture, revocation timing, and concurrent
     overlap without any way to detect the divergence. That is the
     protocol-level argument for a protocol-level answer. Write this only
     after reading the papers. -->

---

## 6. Backward Compatibility

This extension introduces no backward incompatibilities.

The provenance object is carried in `_meta` under the reverse-DNS key
`io.noescalation/provenance`. Per the base specification, implementations MUST
ignore `_meta` keys they do not recognize. A server that does not implement
this extension therefore behaves exactly as it does today when receiving a
request carrying π: the key is ignored and the call proceeds under whatever
authorization the server already applies. This has been verified against the
reference filesystem server (see Reference Implementation).

Clients that do not implement this extension emit no `io.noescalation`
key. A conforming guard encountering a request without π MUST apply the
partial-deployment rules in §5.3 rather than failing the request outright,
so that a non-conforming client is not broken by the presence of a conforming
guard elsewhere in the path.

The extension adds no new methods, no new message types, and no changes to
existing message schemas. It is purely additive metadata plus processing rules
for participants that opt in.

**Partial deployment.** In a chain where some hops implement the extension and
some do not, π records only the hops that participate. The guarantee degrades
correspondingly: the computed effbound reflects the bounds actually recorded,
not the bounds that would have been recorded under full deployment. A
non-participating hop appears as an absent link, not as an unbounded one.
Deployments MUST NOT interpret an incomplete chain as conferring unrestricted
authority. See §5.3.

---

## 7. Reference Implementation

A reference implementation is available at
`https://github.com/alinamiretai/no-escalation` under `proxy/`. It is a
dependency-free Python stdio proxy that constructs and extends π, computes
effbound, and rejects violations fail-closed.

**Implemented and tested:**

- Construction and extension of π across multiple hops (`guard.py`)
- `meet` over the constraint operator set, exact and sound for all operator
  pairs (`provenance.py`, self-test)
- effbound checking with fail-closed rejection (JSON-RPC error `-32001`)
- Enforce and audit modes
- Four benchmark attacks rejected (`test_attacks.py`)
- Multi-hop delegation composition: a later hop's narrowing binds against an
  earlier broader grant (`test_multihop.py`)
- `_meta` acceptance verified against the official
  `@modelcontextprotocol/server-filesystem` reference server
  (`test_meta_realhost.py`)

**Specified but not yet implemented:**

- Revocation (filter narrowing mid-session). The property is proved in the
  formal development; the running guard does not yet expose a narrow
  operation.
- Chain integrity binding (§5.5). The reference implementation is the sole
  constructor and consumer of π, so integrity holds by construction in that
  deployment and is not exercised.
- Result-side mediation. Deliberately out of scope for this version; see §7.2.

The formal development (Lean 4, Mathlib-free) accompanying the implementation
proves soundness, composition, chain conferral, revocation effectiveness, and
robustness under concurrency, and is reproducible with `lake build`. The
formal development proves properties of the *model*; it does not prove that
the Python implementation refines the model. That gap is stated explicitly
rather than elided.

---

## Additions to §5 (Processing Rules)

### 5.7 Declaring the unmediated set (NEW — normative)

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
complement of U. This is a weaker but well-defined claim, and it is the
claim a deployment with a nonempty U is entitled to make.

Rationale: every mechanism in this family — including all prior proposals
known to the author — depends on the mediated path being the only path.
Requiring U to be declared converts an unstated assumption into a checkable
deployment property. An audit method for establishing U empirically, rather
than by self-report, is demonstrated in the reference repository under
`instantiation/`.

<!-- §5.8 REMOVED: superseded by the rewritten §5.5 Chain integrity in
     ext-noescalation-spec.md, which covers the same ground. Do not merge. -->

<!-- §5.7 U-declaration: MERGED into the spec as §5.6. Do not merge again. -->
