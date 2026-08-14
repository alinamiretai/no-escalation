# No-Escalation for Capability-Bearing Agent Systems: Property Statement

**Status:** **v1.0 — FROZEN.** All ten §11 checks model-checked green (Alloy 6.2, sat4j; files noescalation_v1/v2/v3.als). Definitional changes henceforth require a decision memo AND a full suite re-run. Incorporates: turn-semantics memo (D1–D5), item-6 housekeeping memo (D1–D5), two model-driven corrections (alias-freedom base case; NE-S/NE-T attribution unification), instantiation audit of github/github-mcp-server @ 1338dbed4a044ee26422d4212bac3a8037fdb7ff.
**Purpose:** fix the formal property this project proves.

## 1. Scope and threat model

Systems of *components* (agents, sub-agents, tool servers, caretakers) hold capabilities, invoke tools, exchange messages, and spawn sub-components over long trajectories. Components are partitioned into **untrusted** (adversarial: arbitrary strategies, collusion, no capability or context forging) and **trusted** (satisfy explicit contract obligations, §7; each obligation is a per-component lemma in the mechanization — "trusted" means *carries a proof obligation*, not *assumed safe*).

The property concerns **effect escalation only**: causing effects beyond conferred authority. Influence and information flow are out of scope (§9).

## 2. Effects, turns, contexts

- Fix a set **E** of atomic observable effects: tool invocations *with arguments*, spawns, sends. Argument-level granularity is required or attenuation is inexpressible. (**Q1, open:** finite E for Alloy; structured E permitted from the start in Lean.)
- **Turns (D1).** Execution proceeds in *turns*: atomic runs of one component, each induced by exactly one message, during which the component may perform effects, send messages, create continuations, spawn, and update local state. No re-entrancy within a turn; no shared memory between components. (Precedent: E-style vats, Miller *Robust Composition* Part II; actor model, Agha 1986.)
- **Contexts (D2, amended).** Every message carries a **provenance context** π — a sequence of (component, attached-bound) pairs — attached and propagated by the semantics, unforgeable by components (part of A1). Propagation rules:
  1. A turn adopts its inducing message's π; every effect performed in the turn carries that π.
  2. Every send during the turn carries π · (sender, β), with β ⊆ E chosen by the sender.
  3. **Continuation capture.** A continuation/resolver created during a turn captures the turn's π; invoking it induces a turn at its host under the *captured* context, not the invoker's chain. There is no distinguished "reply" message kind; replies are resolver invocations. Resolvers are **linear** (single-use).
  4. Spawn extends context as sends do (D4): the child's initialization turn runs under π(turn) · (spawner, β_spawn); the child's later turns take π from their own inducing messages (no persistent spawn taint).
  5. Root messages in the initial configuration carry designated root contexts.
- A **trace** is the sequence of effect occurrences ε, each carrying perf(ε) and π(ε).

## 3. Capabilities, stores, direct authority

- A **capability** c is an unforgeable reference with **fixed** denotation ⟦c⟧ ⊆ E. Attenuation: c′ with ⟦c′⟧ ⊆ ⟦c⟧. (Fixed denotations survive dynamic narrowing via §6.)
- Each component C has a store σ(C). **Direct authority:** DA(C) = ⋃ { ⟦c⟧ : c ∈ σ(C) } (Miller's *permission*; Bishop–Snyder de jure).
- **Ocap discipline (A2).** No ambient/global store. A freshly spawned component's store is exactly what its spawner passed; untrusted components acquire capabilities only by receiving them.

## 4. Attribution and bounds

- **Component bounds.** Each C carries B(C) ⊆ E, with **monotonicity (A4)**: B′(C) ⊆ B(C) on every transition.
- **Attached bounds.** Chosen freely per send (rule 2); no side condition (a wider β is harmless under the meet — verify in Alloy, §11.10).
- **Attribution (the single relation).** attributed(ε) = { perf(ε) } ∪ { C : (C, ·) ∈ π(ε) }.
  **Reading (D5 amendment):** attributed tracks **authority provenance** — whose conferral licenses ε — not **causal influence** — who shaped ε's occurrence or content. A component that steers another's in-bounds behavior (poisoned reply content, timing, stashed intent) exercises influence without authority; that residue is out of scope by §9.
- **Effective bound.** effbound(ε) = B(perf(ε)) ∩ ⋂ { β : (·, β) ∈ π(ε) }.

## 5. The property

- **NE (no-escalation).** On every trace, every effect occurrence ε satisfies ε ∈ effbound(ε).
  - Projection **NE-T**: ε ∈ B(perf(ε)). Projection **NE-D**: ε ∈ ⋂ β over π(ε).
  - NE is prefix-closed and finitely refutable — a safety property over individual traces (Alpern–Schneider), not a hyperproperty; McCullough-style non-composability of noninterference does not apply. (Re-verify against McCullough 1987/88 and Clarkson–Schneider 2010 before publication.)
- **EA (eventual authority).** EA(C) = { e : some reachable continuation of the current configuration contains an occurrence ε of e with C ∈ attributed(ε) }. Strictly authority, per §4's reading; there is no claim that EA bounds influence. The DA/EA gap remains the confused deputy's habitat.
- **NE-S (inductive invariant, sketch).** In every reachable configuration: (i) for every C, effects reachably attributable to C through root-context action lie within B(C); (ii) for every in-flight message and live continuation with context π, effects reachably performable under π lie within ⋂β(π) ∩ B(holder). NE-S quantifies over futures — a configuration predicate, proved by rely–guarantee.
- **Lemma chain:** NE-S at all reachable configurations ⇒ NE on all traces. (Immediate from definitions, or the definitions are wrong.)

## 6. Static and dynamic scoping of conferral (P3)

Conferred authority is scoped two ways; the project's two original problems are exactly these:

- **Static scoping** — fixed at conferral: attenuated denotations (⟦c′⟧ ⊆ ⟦c⟧) passed in requests; attached bounds β frozen at send; captured contexts frozen at continuation creation. Nothing static narrows mid-flight — by design.
- **Dynamic scoping** — **attenuating caretakers (D-bonus).** A caretaker R holds a filter F ⊆ E with the monotone rule F′ ⊆ F, and forwards an invocation iff its effect ∈ F. **Revocation is the case F = ∅.** The grantee holds c_R with fixed ⟦c_R⟧ = { invoke(R, ·) }; authority over the underlying resource reaches the grantee only through EA, via R. All mid-trajectory narrowing is caretaker-mediated; frozen β's and captured π's are never retro-narrowed.
- **Effectiveness (target theorem, generalized).** If R's filter narrows to F at step k, then no effect outside F attributable through R is *issued* after k — provided the **alias-freedom invariant**: direct references to filtered resources occur only in caretaker stores, *established at conferral and preserved thereafter* (the base case is part of the proviso — preservation is claimed, not creation; model-checking caught an assert that omitted the base case). Structural (reference-graph well-formedness preserved by all transitions), not a runtime check (refuted by Benchmark 3). **Weak linearization:** invocations issued before the narrowing may complete; the theorem quantifies over post-narrowing issuance.
- **Retention is not escalation.** Later own-initiative use of a retained, statically-scoped capability stays within conferred static scope; temporally bounded intent is expressed by caretaker routing, not by a stronger static property (Benchmark 4).

## 7. The trusted-component class and its contracts (P2)

- **Guarding deputies** (components with ambient authority — e.g., a tool server holding its own credentials): **Guard** — perform an effect using ambient authority under context π only if the effect ∈ effbound under π. (Honest tagging deleted: under D2, contexts are semantic; mislabeling is impossible by construction.)
- **Caretakers:** **Membrane** — never emit the underlying reference in any forward, resolution, or spawn; **Monotone filtered forwarding** — forward iff effect ∈ F; F only narrows; weak linearization per §6.

These contracts are the rely–guarantee interfaces of the composition theorem; each is a per-component lemma. Untrusted components carry no obligations; they are confined by A1/A2 and the semantics.

## 8. Assumptions and the target theorem (P7)

- **A1.** Unforgeability: capabilities, contexts, and captured contexts cannot be forged, guessed, or altered by components.
- **A2.** Ocap discipline: no ambient store; spawn passes an explicit store.
- **A3.** Trusted components satisfy §7's contracts: Guard; Membrane + monotone filtered forwarding. (Weaker than v0.2's A3 — Honest tagging removed — hence a stronger theorem.)
- **A4.** Bound monotonicity: B(C) never widens.

**Target theorem (composition).** Under A1–A4, every reachable configuration satisfies NE-S; hence every trace satisfies NE. Proof architecture: rely–guarantee over §7 contracts; stability of each contract under steps of other contract-satisfying components; preservation of the alias-freedom invariant. **Corollaries:** static-scoping soundness (attenuation + attached bounds + captured contexts) and dynamic-scoping effectiveness (filter narrowing, with revocation as F = ∅).

## 9. Scoping decision (P4, amended)

Escalation means effects outside effective bounds. Out of scope, as one named residue — **influence without authority**: information flow through permitted effects (timing, choice among allowed effects); state-mediated cross-chain laundering (intent carried from chain r₁ into effects performed under chain r₂'s conferral); and steering via content of resolutions or messages (a downstream component shaping which in-bounds effects a continuation performs). The calculus guarantees that effects never exceed the conferral of the chain that induced them — and only that. Ruling out the residue is noninterference-shaped and inherits McCullough's non-composability obstacle; paper one states this scope, cites McCullough as the reason, and defers the information-flow variant.

## 10. Known weaknesses and open questions (P5)

1. **Q1 (structured E)** — forced when the Lean transition system is written.
2. **Prior-art positioning:** Maffeis–Mitchell–Taly 2010 (authority safety via reachability); Sewell et al. 2011 (seL4 integrity); distributed-tracing / dynamic-taint literature (message-carried provenance with a security theorem?); *added:* (i) **stack inspection & history-based access control** (Abadi–Fournet 2003; Java stack inspection semantics, e.g. Wallach–Felten; Fournet–Gordon) — effbound is chain-intersection of permissions, structurally their rule transplanted to asynchronous provenance chains; continuation capture vs. doPrivileged must be compared explicitly; check for existing asynchronous/event-loop generalizations of stack inspection. (ii) **DIFC** (Asbestos; HiStar; Flume; Krohn–Tromer 2009's noninterference proof) — semantic message labels are their mechanism; the delta (safety-side conferral bounds, sender-chosen per hop, vs. lattice-propagated flow labels) must be argued, not assumed. Claimed novelty: (a) open-system compositional formulation; (b) per-delegation bounds and semantic contexts as first-class; (c) dynamic scoping (mid-trajectory narrowing/revocation) integrated with (b); (d) agent-trajectory instantiation. Verify against the papers, not summaries; the assembly is claimable only with each part cited.
3. **n2 — transport assumption (D6):** semantic π is implementable as framework-owned provenance metadata iff the framework owns the transport; components with direct network access can side-channel around it. Instantiation-layer assumption, same character as A1; one honest sentence in the instantiation section.
4. **n3 — filter/alias interaction:** the alias-freedom invariant's statement is unchanged by attenuating caretakers (it concerns references, not filters), but verify in Alloy (§11.8).
5. **Over-restriction:** continuation capture removes the resumption false positive (§11.7a); the contract-satisfying logging deputy check (§11.6) remains the guard against residual over-restriction.
6. **Linearity of resolvers** is a calculus design choice, not property-critical; confirm no check in §11 depends on it, then note it as such in the calculus section of the paper.

## 11. Alloy checklist — status after v1–v3 (files: noescalation_v1/v2/v3.als)

Complete, 9 of 10, all scope-bounded (≤ 6 turns) — "model-checked at scope N," never "verified":

1. ✅ Performer-only invisibility reproduced (`B1_InvisibleToPerf` valid — validity is the indictment). Motivating counterexample #1.
2. ✅ Chain attribution flags it (`B1_ChainFlags`).
3. ✅ Shared-service re-amplification invisible to per-component properties (`B2_InvisibleToPerf`, #2); attached bounds flag the attack (`B2_AttachedFlags`) and pass the legitimate twin (`B2_LegitClean` — the precision check).
4. ✅ Handoff caretaker admits the stale-capability attack (`HandoffAttack` SAT); forwarding caretaker effective (`Effectiveness` valid, non-vacuous per `CareLive`; supporting lemma `AliasPreserved` in preservation form — the creation form was refuted by the model, see §6).
5. ✅ Untrusted retention clean (`RetentionClean`); temporal closure via caretaker = check 4/8.
6. ✅ **Resolved** per `decision-memo-item6-housekeeping.md`: E at tool-invocation granularity (sub-effect implementation traffic below E); source audit of a production deputy found the housekeeping∩E set empty; deferral documented as the general mechanism. Model-checked: `OperatorTurnClean` valid (deputized work in a narrow chain + own housekeeping under operator conferral coexist cleanly in one trace); `HkInRequestFlagged` valid (same effect inside the request turn is a true positive, ≡ B2); both scenarios witnessed SAT.
7. ✅ (a) Naive-reply false positive reproduced (`D5_NaiveAlwaysFlags`, #3); (b) continuation capture clean (`D5_CaptureClean`).
8. ✅ Filter narrowing effective at issuance (`Effectiveness` under `ForwardWeak`); weak/strong gap exhibited (`WeakStrongGap` SAT); necessity of both contract clauses witnessed (`HandoffAttack`, `RogueForwarder`).
9. ✅ No spawn taint (`SpawnNoTaint`) *and* spawn conferral binds the init turn (`SpawnScopeBinds`).
10. ✅ Wider-β one-step lemma (`WiderBetaHarmless`); inductive generalization owed to Lean.

Model-driven findings fed back into this note: attribution unification (Benchmark 1); attached bounds and NE-D (Benchmark 2); continuation capture and the naive-reply refutation (D5); alias-freedom base case (v2 counterexample); the sub-effect principle and empty-housekeeping finding (item 6 / instantiation audit). **Checklist complete 10/10; v1.0 frozen.** Next phase: prior-art reads (Abadi–Fournet; Maffeis–Mitchell–Taly; DIFC; McCullough/Clarkson–Schneider re-verification), then Lean mechanization beginning with the kernel transcription and the NE-S ⇒ NE lemma.

## Changelog v0.2 → v0.3

- Turn-based semantics; contexts re-sited from components to messages; propagation rules 1–5 (D1, D2 amended by D5).
- Continuation capture replaces the stipulated reply rule; concrete false-positive trace of the naive rule added as Alloy 7a; resolvers linear (D5).
- attributed(ε) glossed as authority provenance, not causal influence; EA restated accordingly; §9 residue named as influence-without-authority, covering laundering and resolution-content steering in one category (D5).
- Honest tagging deleted; A3 weakened, theorem strengthened (D3).
- Spawn extends context; no persistent spawn taint (D4).
- Attenuating caretakers: revocation = F = ∅; static/dynamic scoping framing; generalized effectiveness theorem (D-bonus).
- §10.1 and §10.5 removed as resolved; transport assumption and filter/alias check added.
