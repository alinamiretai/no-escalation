# Wire Format for π — Design Memo

The one genuinely new design decision in the spec. Everything else formalizes a mechanism that exists; this invents how the provenance chain rides on an MCP call. Four decisions, each with the options, a recommended strawman, and why. Decisions are yours; the strawman is where I'd start.

The target is MCP's JSON-RPC. A tool call today is:

```json
{ "jsonrpc": "2.0", "id": 7, "method": "tools/call",
  "params": { "name": "create_issue", "arguments": { "repo": "acme/app", "title": "..." } } }
```

The question is what to add and how.

---

## Decision 1 — How does a bound denote a set of effects?

A bound β is a set of permitted effects. Effects are tool calls with arguments (A6/R6). So β must describe "which (tool, argument) combinations are allowed." Options, weakest to strongest:

**(a) Tool-name allowlist.** β is a set of tool names. `create_issue` is in or out; arguments unconstrained.
- *Pro:* trivial to implement, check, and read. *Con:* can't express "issues on repo X only" — and that restriction is the whole point of attenuation. Too coarse.

**(b) Tool + argument constraints.** β is a set of (tool name, predicate-on-arguments) pairs. `create_issue` where `repo ∈ {acme/app}`.
- *Pro:* expresses real attenuation; matches how people think about agent permissions. *Con:* needs a predicate language, and that language is now part of your spec's surface.

**(c) Full predicate over the call.** β is an arbitrary decidable predicate over the whole JSON-RPC params.
- *Pro:* maximally expressive. *Con:* unbounded complexity; "arbitrary predicate" is unimplementable as a wire format — it becomes "ship code," which reintroduces the trust problem the capability model exists to avoid.

**STRAWMAN: (b), with a deliberately small constraint language.** A bound is a list of rules; a rule is a tool-name pattern plus a set of argument constraints; a constraint is `field op value` where `op ∈ {eq, in, prefix, glob}`. This covers "these tools, with these argument shapes" — the 90% case — while staying finite, checkable, and human-readable. Escalating to a richer language later is a versioned extension; starting rich is a trap.

```json
{ "tool": "create_issue", "args": { "repo": { "in": ["acme/app", "acme/docs"] } } }
```

Meet (intersection of two bounds) is then: rules present in both, argument constraints conjoined. Decidable, and the meet of two glob/in constraints is straightforward. **Your call: is `{eq, in, prefix, glob}` the right operator set, or do you need one more (regex? numeric range)?** Resist "all of them."

---

## Decision 2 — How is the chain encoded?

π is a sequence of (component, attached-bound) hops. Options:

**(a) Explicit array, plaintext.** π is a JSON array of `{component, bound}` objects, extended by appending.
- *Pro:* transparent, debuggable, trivially inspectable by the guard. *Con:* unauthenticated — a component could rewrite an earlier hop. Fine if the guard is the only party constructing/reading π and components never touch it; not fine if π crosses a trust boundary in the clear.

**(b) Signed chain (macaroon-style).** Each hop appends a caveat and chains an HMAC, so earlier hops can't be altered without detection. This is what the IETF attenuating-token drafts do.
- *Pro:* unforgeable across trust boundaries (discharges A2 properly); aligns with the standards work you want to join. *Con:* key management, and the guard must verify rather than just read.

**STRAWMAN: (a) for the prototype, (b) as the specified target.** The proxy in Move 2 *is* the only constructor and reader of π — it sits between host and server and no untrusted component handles the chain — so plaintext is sound *for that architecture* and lets you build without a crypto layer. But the *spec* should specify the signed form, because A2 (unforgeable, framework-owned) is a real requirement and the drafts you're joining assume it. State both: "conforming implementations MUST prevent component forgery of π; a proxy that solely constructs and consumes π MAY use an unsigned representation; implementations where π crosses a component boundary MUST use the signed chain of §X." **Your call: is that split honest, or does specifying two representations weaken the spec?** I think it's honest and matches Lampson's own "the channel is not part of the TCB" move — but it's a judgment.

---

## Decision 3 — Where does π live on the call?

**(a) A new top-level `params` field**, e.g. `params._provenance`.
- *Pro:* survives as part of the normal call; every handler sees it. *Con:* pollutes the tool's argument namespace; a server that validates its schema strictly might reject unknown fields.

**(b) MCP `_meta`.** MCP reserves `_meta` on requests for exactly this — out-of-band metadata that isn't tool arguments.
- *Pro:* the designed-for location; won't collide with tool schemas; ignored by servers that don't understand it. *Con:* you rely on hosts/servers preserving `_meta` (the spec says they should).

**STRAWMAN: (b), `_meta`.** It's the field MCP put there for this, and using it means a provenance-unaware server ignores π rather than choking on it — which is exactly the graceful-degradation story you want for adoption. The guard reads `_meta.provenance`, checks effbound, strips or forwards it per policy.

```json
{ "jsonrpc": "2.0", "id": 7, "method": "tools/call",
  "params": {
    "name": "create_issue",
    "arguments": { "repo": "acme/app", "title": "..." },
    "_meta": { "io.noescalation.provenance": { "chain": [ ... ], "sig": "..." } }
  } }
```

**Your call: is `_meta` reliably preserved across the hosts you care about?** This is empirical — worth testing in the Move 2 pass-through prototype before committing the spec to it.

---

## Decision 4 — What does the guard do on a violation?

Not strictly wire format, but it belongs in the spec and shapes the proxy.

**(a) Reject the call** with a JSON-RPC error (effbound violation → error response to the host).
**(b) Strip and downgrade** — remove the offending arguments and forward a narrowed call.
**(c) Log-only** (audit mode) — allow, but record.

**STRAWMAN: (a) as default, (c) as an explicit mode.** Fail-closed is the safe default and matches "the guard prevents the effect." Log-only is essential for *deployment* — nobody turns on a new guard in enforce mode against production traffic, they run it in audit first and watch. Specify both; make enforce the default and audit an opt-in. (b) is tempting but silently altering calls is a footgun — skip it in v0.

---

## Summary of strawman (what to build and specify unless you override)

| Decision | Strawman |
|---|---|
| Bound denotation | tool + argument constraints; ops `{eq, in, prefix, glob}` |
| Chain encoding | plaintext for the proxy; signed chain specified as the cross-boundary requirement |
| Location | MCP `_meta`, key `io.noescalation.provenance` |
| Violation | fail-closed default; audit (log-only) mode opt-in |

## The four decisions you actually need to make

1. Is `{eq, in, prefix, glob}` the right constraint operator set? (Add at most one; resist "all.")
2. Is the plaintext-proxy / signed-spec split honest, or should the spec mandate one representation?
3. Empirical: is `_meta` preserved across your target host(s)? (Test in the Move 2 pass-through.)
4. Fail-closed default with audit mode — agreed, or different?

Once these are settled, the same decisions feed straight into (a) the normative spec language and (b) the proxy's data structures. Nothing here is wasted on either path.
