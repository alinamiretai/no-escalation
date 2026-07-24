# Conformance Specification

**What this is.** The no-escalation theorems are conditional. This document turns their hypotheses into requirements on an implementation, so that "does the theorem apply to my framework?" becomes a checkable question instead of a matter of opinion.

**How to use it.** Work through R1–R6. Each states what must hold, which assumption it discharges, which theorems collapse without it, how to check it, and what to do if it fails. A framework meeting R1–R6 inherits T1–T4: effects bounded by conferral, preserved under delegation and chaining, with attenuation and revocation effective. A framework failing any of them inherits nothing from that theorem — which is useful information, not an accusation.

**Status of the verdicts.** Applied to `github/github-mcp-server` at commit `1338dbed4a044ee26422d4212bac3a8037fdb7ff`, local (stdio) mode. Verdicts cite the audit (`instantiation/audit-output.txt`, `github-mcp-server-inventory.md`, `idle-egress-capture.txt`) where evidence exists and are marked **inferred** where they rest on reading rather than measurement. Claims → `../CLAIMS.md`.

---

## R1 — No ambient authority within the mediated boundary

**Requirement.** Every component acts only on capabilities explicitly conferred on it. A component must not be able to construct or reach authority it was not given. Capabilities are unforgeable references, not names.

**Discharges** A1. **Without it:** T1, T2, T4 all fail — the `perform` precondition ("holds a denoting capability") becomes meaningless, and `T4b_sole_route` collapses since anyone can reach the resource.

**Implementable as.** Per-request credential injection: the framework hands each invocation the credential for *that* request, rather than the component holding a long-lived token it applies to everything. Capability handles opaque to the holder (no reconstruction from a string).

**How to check.** Grep for long-lived credential storage in component scope: `os.Getenv.*TOKEN`, `BearerAuthTransport`, module-level clients. Ask: if two requests with different conferrals arrive, do they use different credentials?

**Verdict: VIOLATED (intra-server).** The server holds one ambient credential and every tool uses it: `internal/ghmcp/server.go:66–98` builds REST and GraphQL clients wrapped in `BearerAuthTransport` at startup; all tool handlers share them. Per-request differentiation does not exist. *At the boundary between host and server*, the server is itself a conferred capability, so the violation is internal — which is exactly the deputy situation the theorems model.

---

## R2 — Unforgeable, framework-owned provenance on every call

**Requirement.** Every invocation carries a provenance context π: the chain of (component, attached bound) pairs that led to it, constructed by the framework and unforgeable by components. Components may *extend* a chain when delegating; they may not fabricate, truncate, or rewrite one.

**Discharges** A2. **Without it:** effbound is uncomputable. Chain attribution is unimplementable, and every theorem that mentions π is inapplicable. **This is the load-bearing requirement.**

**Implementable as.** A provenance field in the call envelope, framework-populated; or an append-only attenuating token chain (the mechanism the current IETF drafts standardize — AIP's invocation-bound capability tokens, the attenuating-tokens draft's narrowing invariants).

**How to check.** Does the protocol carry any per-call record of the delegation path? Can a component emit a call whose provenance it authored?

**Verdict: VIOLATED.** MCP tool calls carry no provenance. A handler sees arguments and session context; nothing records who conferred what, or through which chain. **This single gap is why R3 cannot be met** — a deputy cannot check effbound against a chain that does not exist.

---

## R3 — Trusted components discharge their contracts

**Requirement.** Any component holding ambient authority the framework cannot mediate (a "deputy") must itself enforce: **Guard** — perform an effect only if it lies within effbound(π); and, if it mediates a revocable resource (a "caretaker"): **Membrane** — never emit the underlying reference in any forward, resolution, or spawn; **monotone filtered forwarding** — forward only within the current filter, evaluated at issuance, with the filter only narrowing.

**Discharges** A3. **Without it:** T2's trusted branch fails; T4 fails entirely. *These three contracts are jointly satisfiable while doing real work* — proved (`CareSanity.contracts_livable`), so a failure here is an implementation gap, not an impossible ask.

**Implementable as.** An effbound check at the top of each tool handler; a proxy layer that returns handles rather than underlying clients; a filter consulted at request admission, not at effect time.

**How to check.** Does any handler compare its intended effect against the caller's conferral? Does any code path return an object from which the underlying credential or client is reachable?

**Verdict: PARTIAL.**
- *Membrane-like behaviour:* **met, incidentally.** The server never emits its credential; `pkg/http/transport/bearer.go` injects it at transport level and no handler returns a client.
- *Guard:* **not met, and not currently meetable** — blocked by R2. `pkg/lockdown` performs a content-safety check (`IsSafeContent`, `authorLockdownResult`) based on repository push access, which is a heuristic about *data provenance*, not a check against the caller's conferral.
- *Filtered forwarding:* **absent.** No revocation filter exists; `RepoAccessCache` is a permission cache with a TTL, not a narrowing filter.

---

## R4 — Bounds and filters only narrow

**Requirement.** No API widens a component's bound or a caretaker's filter. Narrowing may occur at any time; widening never does.

**Discharges** A4. **Without it:** T3a, T3b (mixed NES) and T4d fail; attenuation means nothing if it can be undone.

**Implementable as.** Make bounds immutable after conferral and express narrowing as a new, narrower conferral. Where a runtime filter exists, expose only a narrowing operation.

**How to check.** Enumerate every write to a permission structure. Is any of them a widening?

**Verdict: MET, trivially and weakly.** Toolsets and read-only mode are fixed at startup (`cmd/github-mcp-server/main.go`); no runtime API widens them. But nothing narrows them either — the bounds are *static*, so the requirement is satisfied by absence of dynamics rather than by discipline. A framework adding runtime scope changes must revisit this.

---

## R5 — Mediation: untrusted components have no unmediated actuators

**Requirement.** **Enumerate** the set U of effects untrusted components can cause outside the framework — shell, interpreter, raw sockets, browser. U may be non-empty; it may **not** be left unstated.

**Discharges** A5. **This requirement is an enumeration, not a gate.** Graceful degradation is proved (`Degradation.T2_modulo_U`): with U declared, every effect *outside* U still satisfies effbound, and composition survives partial mediation with no extra machinery. So a deployment with a shell tool does not lose the theorems — it loses exactly U. The security work is shrinking U; the theorem guarantees that shrinking U is the only thing that matters, since nothing outside U leaks on account of something inside it.

**What it does not buy.** Bounding *what* escapes is not bounding *how much harm* it does. One unmediated shell can exceed the damage of every mediated effect combined. U being declared says nothing about U being small.

**Implementable as.** Sandboxing (namespaces, seccomp, no-egress containers) — the systems technique, not a new mechanism. Where full mediation is impractical, enumerate U explicitly so the residual is named rather than assumed away.

**How to check.** Enumerate the untrusted component's tools. Any of them Turing-complete or network-capable? Then U is non-empty.

**Verdict: N/A to the server; UNDECLARED in typical deployments.** The MCP server is a *trusted deputy*, so R5 does not constrain it; measured egress at idle is nil (`idle-egress-capture.txt`, 300 s, zero connections), which corroborates its behaviour but is not what R5 asks. R5 constrains the **agent**, and a typical deployment gives the agent a shell or code-execution tool alongside MCP — so U is non-empty and, in every deployment we are aware of, **unstated**. That is the finding: not that mediation fails, but that nobody writes down what escapes it. *(Inferred — a property of hosts, outside the audited artifact.)*

---

## R6 — Enforcement at tool-call granularity

**Requirement.** The effect set E is the tool invocations with their arguments. The enforcement point sits at that boundary. Traffic below it — pagination, token refresh, cache reads, telemetry sinks — is implementation of a tool-level effect, not separate effects.

**Discharges** A6. **Without it:** the sub-effect principle fails and enforcement flags implementation traffic, producing exactly the over-restriction that forced doPrivileged-style escapes into stack inspection.

**Implementable as.** Interpose at the tool dispatch layer, not at the HTTP client.

**How to check.** Would enforcement at this point flag anything the component does legitimately on its own behalf?

**Verdict: MET, with evidence.** The audit found the in-E housekeeping set **empty** at this granularity: local writes are log/config only; the OAuth subsystem (callback listener, browser subprocess, background refresh on `context.Background()`) is plumbing below E; fields telemetry terminates in a no-op sink locally (`pkg/observability`); serving-path egress is GitHub-only. **No amplification primitive is needed** — the contrast case to history-based designs, which require Grant/Accept escapes.

---

## Summary

| | Requirement | Verdict |
|---|---|---|
| R1 | No ambient authority | **VIOLATED** (intra-server) |
| R2 | Framework-owned provenance | **VIOLATED** — *the root gap* |
| R3 | Deputy contracts | **PARTIAL** (Membrane ✓, Guard blocked by R2, filter absent) |
| R4 | Bounds only narrow | MET (trivially — static) |
| R5 | Mediation — *enumerate U* | N/A to server; U typically **undeclared** in deployment |
| R6 | Tool-call granularity | **MET** (evidenced) |

**Reading.** The enforcement *point* is right and the effect ontology fits — R6, the requirement most likely to be awkward, is met cleanly and with measurement behind it. What is missing is the **provenance layer**: R2 fails, and R2's failure is what makes R3's Guard clause unmeetable and R1's violation consequential. One gap, with knock-on effects, and it is the gap the current standards work is filling.

---

## Closing the gaps: minimal changes

1. **R2 first — everything else follows.** Add a framework-populated provenance field to the MCP call envelope: the chain of (component, attached bound) pairs, extended on delegation, unforgeable by handlers. The IETF attenuating-token drafts already carry the narrowing invariant this needs; the missing piece is *binding the chain to the invocation* and making it visible to the handler.
2. **Then R3's Guard**, which becomes a few lines per handler once π exists: compare the intended effect against `bound(self) ∩ ⋂β`.
3. **Then R1**, by injecting per-request credentials derived from the chain instead of one ambient token.
4. **R5 is a deployment decision**, not a server change: sandbox the agent's non-MCP actuators to shrink U, and declare whatever remains. By T2u the guarantee still holds on E \ U, so declaring costs nothing and buys an honest scope. Declaring is respectable; assuming is not.

## What conformance buys, and what it does not

**Buys (T1–T4):** no component causes effects beyond what was conferred; the guarantee survives delegation, chaining through deputies with their own credentials, and sub-agent structure; attenuation binds; revocation is effective, with a stated in-flight window.

**Does not buy:** anything about *influence*. A conformant agent can still be steered, by prompt injection or otherwise, into misusing authority it legitimately holds; covert channels through permitted effects are out of scope by construction (`CLAIMS.md` S1). Nor does conformance say the conferred bounds are the *right* ones — choosing them is S3, and a perfectly enforced wrong bound is a catastrophe with a proof attached.