# Decision Memo: Turn Semantics and Context Siting (resolves §10.1, §10.5)

**Status:** decided, pending two verifications (D5, D6 below). Companion to `no-escalation-property-note-v0.2.md`; applying the patches below yields v0.3.

## Decisions

**D1 — Turn-based semantics.** The calculus's unit of execution is the *turn*: an atomic run of one component induced by exactly one message, during which the component may perform effects, send messages, spawn, and update local state. No re-entrancy within a turn; no shared-memory concurrency between components. Precedent: E-style vats (Miller, *Robust Composition*, Part II); actor model (Agha 1986). This is the standard ocap concurrency model, not a bespoke restriction.

**D2 — Contexts are semantic labels on messages.** π is attached and propagated by the calculus, not read or written by components — unforgeable, like references (A1 extends to π).
- A turn adopts the inducing message's π.
- Every effect performed in the turn carries that π.
- Every send in the turn carries π · (sender, β), with β chosen by the sender.
- **Reply rule:** a reply to request r carries the π that the requester held when it sent r; the resuming turn therefore continues the original chain. (Verification D5.)
- Root/initial messages in the starting configuration carry designated root contexts.
- Consequence: "which request does this effect belong to?" has a unique answer per occurrence. §10.1's interleaving problem does not arise; a component may serve many chains across turns with correct attribution per turn.

**D3 — Honest tagging is deleted from the trusted-deputy contract.** Under D2, mislabeling is impossible by construction; the obligation was an artifact of component-sited contexts. A3 weakens to Guard (deputies) and Membrane + monotone forwarding (caretakers) only — a strictly stronger theorem.
- Laundering, reclassified: (i) *message-mediated* laundering is impossible (self-sends inherit π); (ii) *state-mediated* laundering (memorize intent during chain r₁, act during a legitimately wide chain r₂) yields effects within r₂'s conferral — what escapes r₁ is information/intent, which is the noninterference-shaped residue already excluded by §9. Patch §9 to name this explicitly (P4).

**D4 — Spawn extends the current context.** spawn during a turn is send-like: child store = what the spawner passed (A2); the child's initialization turn runs under π(turn) · (spawner, β_spawn). Later turns of the child take π from their own inducing messages, so spawn context does not persistently taint the child; the shared-service-child scenario is benign under D2. Fresh-⟨⟩ spawn is rejected: it is an attribution-laundering primitive and disconnects children from mid-trajectory narrowing.

**D-bonus — Attenuating caretakers.** Since every β is frozen at send time, mid-trajectory narrowing is caretaker-mediated by necessity. Generalize the caretaker: it holds a filter F ⊆ E with the monotone rule F′ ⊆ F, forwards an invocation iff its effect ∈ F; revocation is the special case F = ∅. Effectiveness theorem generalizes: after F narrows, no post-narrowing-issued effect attributable through the caretaker lies outside F (alias-freedom proviso; weak linearization unchanged). Attenuation and revocation are one mechanism at different filter values; the project's two problems become one theorem about monotone filters (dynamic scoping) plus frozen bounds (static scoping).

## Verifications owed before freezing

**D5 — Reply-rule simulation.** Hand-simulate: A →r₁ C1 →r₂ E; E replies; C1 resumes and performs an effect (expect π = ⟨A,·⟩·⟨C1,·⟩ path restored). Then: E sends C1 a *fresh* message with wide β; C1's turn runs under E's chain (expect: correct, and any cross-use of r₁'s intent is the D3(ii) out-of-scope case, not a mislabeling). Any route that lets an effect run under a chain that did not causally induce its turn refutes D2's reply rule.

> **Outcome (resolved, with amendment).** Reply-as-ordinary-send is refuted: the resumption context inherits the sub-request's β, flagging the requester's own remaining work (concrete false-positive trace in v0.3 §11, check 7a). D2's reply clause is replaced by **continuation capture**: a resolver/continuation capability captures its creation turn's π; invoking it induces a turn under the captured context. No distinguished reply kind. Amendments carried into v0.3: (i) continuation-capture rule in §2; (ii) attributed(ε) glossed as authority provenance, not causal influence — influence-without-authority named as the §9 residue; (iii) resolvers linear (single-use) as a calculus design note. v0.3 is authoritative over this memo where they differ.

**D6 — Transport assumption at the instantiation layer.** Semantic π is implementable as framework-maintained provenance metadata (tracing headers on tool calls) *iff the framework owns the transport*. Components with direct network access can side-channel around it. State as an instantiation-layer assumption (alongside A1's unforgeability, which has the same character); one honest sentence in the instantiation section, not a calculus change.

## Patches: v0.2 → v0.3

**P1 (replaces §2's context paragraph):**
> **Turns and contexts.** Execution proceeds in *turns*: atomic runs of one component, each induced by exactly one message (D1). Every message carries a **provenance context** π — a sequence of (component, attached-bound) pairs — attached and propagated by the semantics and unforgeable by components (D2). A turn adopts its inducing message's π; effects performed in the turn carry it; sends extend it with (sender, β); replies carry the π held by the requester at request time; spawns extend it as sends do (D4). Root messages carry designated root contexts. Contexts are the operational content of chain attribution; their unforgeability is part of A1.

**P2 (§7, trusted components):** delete the Honest-tagging clause; Guard stands alone for deputies. Replace the caretaker's obligations with: **Membrane** (never emit the underlying reference) and **Monotone filtered forwarding** (forward an invocation iff its effect ∈ current filter F; F only narrows; weak linearization).

**P3 (§6):** rewrite around attenuating caretakers per D-bonus: static scoping (attenuated denotations at conferral; attached bounds frozen at send) vs. dynamic scoping (caretaker filters, monotone, revocation = F = ∅); generalized effectiveness theorem; retention paragraph unchanged in substance but now phrased as "temporal/dynamic scoping."

**P4 (§9):** add: state-mediated cross-chain laundering — a component carrying intent from one chain into effects performed under another chain's conferral — is an information-flow property and is out of scope with the rest of the noninterference residue; the calculus guarantees effects never exceed the conferral of the chain that induced them, and only that.

**P5 (§10):** delete items 1 and 5 (resolved by D1–D4). Add: (n1) D5 reply-rule verification; (n2) D6 transport assumption for the instantiation section; (n3) check that the attenuating-caretaker generalization doesn't complicate the alias-freedom invariant (the invariant's statement is unchanged — references, not filters — but verify in Alloy).

**P6 (§11 Alloy checklist):** add — 7. Reply-rule check (encode D5's two scenarios; assert every effect's π equals its turn's inducing chain). 8. Attenuating caretaker: narrow F mid-run; assert no post-narrowing effect outside F escapes through the caretaker; then re-run the handoff-caretaker negative check against the filtered version. 9. Spawn taint check: child spawned under r₁ later services r₂; assert r₂-turn effects carry r₂'s chain only.

**P7 (§8):** A1 extended to context unforgeability; A3 restated per P2 (note in the changelog that A3 is weaker than v0.2's — theorem strengthened).
