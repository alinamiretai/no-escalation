# No-Escalation for Capability-Bearing Agent Systems — Reviewer Packet

*Two pages. Frozen property statement v1.1; full artifacts (Alloy models, Lean development, decision memos) available on request. Three specific questions at the end — those are what I'm asking for; anything else is a bonus.*

## The problem

LLM agent systems delegate authority across long trajectories: agents call tools, spawn sub-agents, and chain requests through services holding their own credentials. Two properties are unformalized for this setting: (1) **compositional no-escalation** — no component causes effects beyond what was conferred on it, preserved under delegation and chaining; (2) **mid-trajectory attenuation and revocation** — conferred authority narrowing or dying while a task runs.

## The property

Fix a set **E** of effects (tool invocations with arguments, at tool-call granularity — constituent API traffic is sub-effect implementation). Capabilities are unforgeable references with fixed denotations ⟦c⟧ ⊆ E. Execution is turn-based (actor-style: atomic turns, each induced by one message or one captured continuation). Every message carries a **provenance context** π — a chain of (component, attached-bound) pairs, propagated by the semantics, unforgeable by components: sends extend π with a sender-chosen bound β; continuations capture their creation turn's π and restore it on resumption.

For an effect occurrence ε with performer p and context π:
**effbound(ε) = B(p) ∩ ⋂{β : (·,β) ∈ π}**, where B(p) is p's (monotonically narrowing) component bound.

**NE (no-escalation):** every effect occurrence lies within its effbound. NE is a **trace safety property** in the sense of Clarkson & Schneider (2010), Def. p. 1168: for any violating trace, the prefix through the first out-of-bound occurrence is a bad thing — finitely observable (visible at that index) and irremediable (appended events cannot retract it, and effbound is determined by data carried at the occurrence). NE **generalizes their canonical safety example**, access control (their eq. 2.2, "every operation consistent with its requestor's rights"), from an access-control matrix indexed by (subject, object) to a conferral chain indexed by causal provenance.

Consequently NE lifts to a **subset-closed** hyperproperty ([P] = P(P), so SHP ⊂ SSC applies), which is the precise reason composition and refinement are unproblematic here: removing traces can never invalidate it. McCullough-style non-composability concerns possibilistic information-flow policies, which are *hyperliveness* (their Thm. 3: PIF ⊂ LHP) and not subset closed — a provably disjoint region of the taxonomy from where NE sits. The excluded residue (§ below) is exactly that region, so the scoping is principled rather than convenient. The state-level invariant (EA ⊆ B) quantifies over futures and is kept formally distinct from NE.

**Eventual authority** EA(C) = effects reachably attributable to C (performer or on the chain). Attribution reads as *authority provenance* — whose conferral licenses an effect — not causal influence.

## Two semantic layers and four theorems

The unguarded semantics admits NE violations by design (attacks must be expressible; a benchmark suite of confused-deputy, re-amplification, stale-revocation, and continuation-capture scenarios lives there, model-checked in Alloy). Enforcement is a **guarded** `perform` carrying the effbound check — Schneider (2000): NE is a safety property, hence exactly monitorable. Components split into **untrusted** (framework-mediated; step only via the guard — assumption A5) and **trusted** (deputies/caretakers holding ambient authority the framework cannot gate; they discharge *contracts*: Guard, plus Membrane and monotone filtered forwarding for revocation caretakers).

- **T1 Soundness** — guarded traces satisfy NE. Near-definitional; stated as the floor. *(Mechanized, Lean 4.)*
- **T2 Mixed composition** (centerpiece) — guarded-untrusted + contract-satisfying-trusted + initial conditions ⇒ NE on all traces. The per-step content is proved; the open work is the chain-level inductive invariant. *(Stated in Lean; the intended `sorry`.)*
- **T3 Attenuation soundness** — attached bounds and captured contexts confer nothing beyond the meet.
- **T4 Revocation effectiveness** — after a caretaker's filter narrows, no out-of-filter effect with issuance after the narrowing, given alias-freedom (structural, established at conferral and preserved). Issuance = the *invoker's* turn, uniformly for sends and continuation resumes; creation-turn licensing is refuted (it readmits the stale-capability attack at the continuation level — model-checked).

## Positioning (the deltas I believe are real — please attack these)

**vs. stack inspection / history-based access control (Fournet–Gordon; Abadi–Fournet):** effbound shares the intersection skeleton of history-based rights, with two validated deltas. First, *what* is intersected: their current rights intersect policy-assigned **attributes of code** over the **linear history of an execution unit** — so a multi-principal service monotonically decays to the intersection of everyone it has ever served, which is why their design requires explicit Grant/Accept amplification; our meets intersect sender-chosen **conferrals** over the **causal provenance chain of each request**, so cross-chain there is no accumulation and no amplification primitive is needed (machine-checked: the legitimate shared-service scenario passes; a production tool server's in-E housekeeping set audited empty). Second, restoration: their Accept is an explicit, audited trust step whose soundness is programmer diligence; our continuation capture restores the creation-time conferral automatically, with soundness as a theorem under the standing guard. The trade is two-way and we state it: their linear history catches caller-endangered-by-callee data poisoning (their motivating example), which for us is influence-without-authority — explicitly in the excluded residue; symmetrically, we admit the multi-principal services their model over-restricts. (Neighbors to distinguish: Edjlali et al.'s request-history policies — a different axis; Wallach–Appel–Felten's ABLP rendering of stack inspection as "says" chains — delegation chains as logical objects, sequential, stack-semantics, no meet-of-effects or mechanized safety theorem.)

**vs. DIFC (Flume; Krohn–Tromer):** labels-on-messages is their mechanism; the delta is *what the labels mean and which side of the safety/hyperproperty line the theorem lives on*. DIFC labels are lattice-propagated flow constraints, and the Flume proof is noninterference — a hyperproperty. Our contexts are sender-chosen authority conferrals, and NE is a safety property; the information-flow residue (influence without authority: covert channels, cross-chain intent, poisoned resolutions) is explicitly out of scope, with McCullough's non-composability cited as the reason. Flume's confined/unconfined split is our mediation assumption A5, deployed: components outside the reference monitor's reach are outside the theorem.

**vs. CaMeL (Debenedetti et al. 2025):** CaMeL tags *data values* with provenance (sources, allowed readers) and enforces at tool calls inside one interpreter — an information-flow mechanism with a security-game formalization and empirical evaluation. We tag *requests* with authority conferrals and prove compositional theorems about open systems including ambient-authority deputies; no mechanized or compositional statement exists in CaMeL, nor any revocation/attenuation treatment. Complementary layers: CaMeL is evidence the enforcement architecture deploys.

**vs. object-capability formalizations (Maffeis–Mitchell–Taly; Miller):** EA is authority-as-reachability in their tradition; their setting is a sequential single heap, and AuthoritySafe bounds authority *growth*; ours is open message-passing with conferral as a first-class, per-delegation object, plus the temporal axis.

## Status, honestly

Property statement frozen (v1.1) after three Alloy model generations (17 checks, every scenario satisfiability-witnessed) and a Lean development (T1 and the per-step lemma of T2 proved; T2's invariant open). The project's error history is documented: three prose theorem statements were false before checking — including v1.0's main theorem, refuted in Lean, and a confused deputy found *inside our own caretaker contract* — each caught by forcing claims into a checker. The influence residue is out of scope and stated loudly: a confined agent can still be steered to misuse authority it legitimately holds.

## The three questions

1. **Is NE well-posed?** In particular: contexts-on-messages with sender-chosen bounds, meet semantics, and continuation capture — is there a known pathology (re-entrancy, label creep, laundering) this misses?
2. **Does the safety-property claim survive?** NE as stated is a trace property and I claim McCullough-style non-composability doesn't apply; the state-level invariant (EA ⊆ B) quantifies over futures and is kept distinct. Is that separation sound as stated?
3. **What's the closest prior work I've missed?** Especially: asynchronous/event-loop generalizations of stack inspection; any formalization of message-carried *authority* (not flow) labels with a compositional theorem; anything on revocation over long-running delegation.