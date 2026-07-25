# No-Escalation for Capability-Bearing Agent Systems: Property Statement

**Status:** **v1.1 — FROZEN.** All ten §11 checks model-checked green (Alloy 6.2, sat4j; files noescalation_v1/v2/v3.als). Definitional changes henceforth require a decision memo AND a full suite re-run. Incorporates: turn-semantics memo (D1–D5), item-6 housekeeping memo, restatement memo (guarded semantics + caretaker Guard), resolver-issuance memo (invoker-turn licensing), instantiation audit of github/github-mcp-server @ 1338dbed4a044ee26422d4212bac3a8037fdb7ff.

**v1.1 supersedes v1.0's §8 target theorem, which was FALSE.** Two findings forced the restatement: (a) `composition_target_unprovable` (Lean, commit 8b4e53e) — `InitOK → NE` fails because untrusted `perform` steps carried no check of any kind; (b) the **caretaker confused deputy** (Alloy `V10_admits_escalation`, invalid) — the v1.0 caretaker contract lacked Guard, so a contract-satisfying caretaker could perform outside the requesting chain's conferral. Root cause, unified: `perform` was **unchecked for untrusted components and under-checked for caretakers** — the same missing conjunct in two places.
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

## 5. The property, and the two semantic layers

**Specification layer (unguarded).** The semantics of §2 admits NE-violating runs. This is by design: attacks must be expressible, and the benchmark suite lives here.

**Enforcement layer (guarded).** `GuardedPerform`: a component performs `e` under context π only if `effbound(π) e` (i.e. `B(perf) e ∧ π.meet e`). Untrusted components step **only** via GuardedPerform (framework mediation, A5). Trusted components step unguarded but are bound by their §7 contracts, because no framework can enforce a deputy's exercise of its own ambient authority (instantiation evidence: the tool server calls the API with its own credentials, outside the orchestrator's reach).

Grounding: Schneider, *Enforceable Security Policies* (2000) — execution monitors enforce exactly the safety properties; NE is a safety property, hence monitorable. Precedent for checks-in-semantics: Fournet–Gordon (λ_sec reduction rules), Maffeis–Mitchell–Taly (capability-safe language), CaMeL (interpreter level).


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

**Guard (ALL trusted components, unified — v1.1).** A trusted component performs `e` under context π only if `effbound(π) e`. Extending this to caretakers is the confused-deputy repair; it was already the deputy obligation in v1.0.

- **Guarding deputies:** Guard. (Honest tagging remains deleted: contexts are semantic, so mislabeling is impossible by construction.)
- **Caretakers:** Guard **and** **Membrane** (never emit the underlying reference in any forward, resolution, or spawn) **and** **Monotone filtered forwarding** (perform/forward iff `e ∈ F` at `issuance(t)`; F only narrows). The filter clause applies to **both** trigger kinds — v1.0's formulation was vacuous on resolver-induced turns.

These contracts are the rely–guarantee interfaces of the composition theorem; each is a per-component lemma. Untrusted components carry no obligations; they are confined by A1/A2 and the semantics.

## 8. Assumptions and the target theorem (P7)

- **A1.** Unforgeability: capabilities, contexts, and captured contexts cannot be forged, guessed, or altered by components.
- **A2.** Ocap discipline: no ambient store; spawn passes an explicit store.
- **A3.** Trusted components satisfy §7's contracts: Guard; Membrane + monotone filtered forwarding. (Weaker than v0.2's A3 — Honest tagging removed — hence a stronger theorem.)
- **A4.** Bound monotonicity: B(C) never widens.
- **A5 (mediation, v1.1).** Untrusted components have no actuators outside the framework: every effect they cause is a GuardedPerform, or is a request whose eventual effect is performed by a trusted component under that request's context. *Failure mode, stated at the same volume as A1:* an "untrusted" component with independent network egress is outside the model. (This is the D6 transport assumption promoted from instantiation footnote to named hypothesis.)

**Theorems (v1.1).**
- **T1 Soundness.** Every guarded trace satisfies NE. *Near-definitional; the floor. Stated plainly per the Fournet–Gordon precedent — a thin guarantee, honestly labelled.*
- **T2 Mixed-system composition.** Under A5's mediation discipline, every trace of a system composed of GuardedPerform-untrusted components and contract-satisfying trusted components satisfies NE. **Proved (Lean), trivially — and the triviality is the result:** effbound is turn-local (performer bound + message-carried context), so the enforcement condition is per-step and composition follows with no induction and no initial conditions. This is the locality claim made precise, and the Fournet–Gordon thin-guarantee pattern: enforcement-in-semantics yields a thin direct theorem, with the depth relocated. *(Errata: the v1.1 freeze text predicted T2 would require a chain-level inductive invariant; false — the checker corrected the prose in the favourable direction. The invariant work belongs to T4.)*
- **T3 Attenuation soundness (spatial corollary).** Attached bounds and captured contexts confer no authority beyond the meet. *(Chain-conferral lemma: meet ⊆ every hop's β.)*
- **T4 Revocation effectiveness (temporal corollary — the hardest proof).** After the filter narrows to F, no effect outside F is performed by the caretaker with `issuance ≥ k`, given alias-freedom established at conferral and preserved. *Induction over unbounded traces and evolving reference graphs; the depth of the project lives here, which is fitting — mid-trajectory revocation was the original open problem.*

`InitOK'` replaces v1.0's `InitOK`: drop the false implicit "structural conditions suffice for untrusted components," add mediation. Its exact form co-evolves with the T2 invariant search.

## 9. Scoping decision (P4, amended)

Escalation means effects outside effective bounds. Out of scope, as one named residue — **influence without authority**: information flow through permitted effects (timing, choice among allowed effects); state-mediated cross-chain laundering (intent carried from chain r₁ into effects performed under chain r₂'s conferral); and steering via content of resolutions or messages (a downstream component shaping which in-bounds effects a continuation performs). The calculus guarantees that effects never exceed the conferral of the chain that induced them — and only that. Ruling out the residue is noninterference-shaped and inherits McCullough's non-composability obstacle; paper one states this scope, cites McCullough as the reason, and defers the information-flow variant.

Also out of scope, and named at equal volume: **A5 failure** — a component classified untrusted that possesses actuators outside the framework (independent network egress) is not covered by T2. Same category as the instantiation audit's telemetry side channel.

## 10. Known weaknesses and open questions (P5)

1. **Q1 (structured E)** — forced when the Lean transition system is written.
2. **Prior-art positioning:** Maffeis–Mitchell–Taly 2010 (authority safety via reachability); Sewell et al. 2011 (seL4 integrity); distributed-tracing / dynamic-taint literature (message-carried provenance with a security theorem?); *added:* (i) **stack inspection & history-based access control** (Abadi–Fournet 2003; Java stack inspection semantics, e.g. Wallach–Felten; Fournet–Gordon) — effbound is chain-intersection of permissions, structurally their rule transplanted to asynchronous provenance chains; continuation capture vs. doPrivileged must be compared explicitly; check for existing asynchronous/event-loop generalizations of stack inspection. (ii) **DIFC** (Asbestos; HiStar; Flume; Krohn–Tromer 2009's noninterference proof) — semantic message labels are their mechanism; the delta (safety-side conferral bounds, sender-chosen per hop, vs. lattice-propagated flow labels) must be argued, not assumed. Claimed novelty: (a) open-system compositional formulation; (b) per-delegation bounds and semantic contexts as first-class; (c) dynamic scoping (mid-trajectory narrowing/revocation) integrated with (b); (d) agent-trajectory instantiation. Verify against the papers, not summaries; the assembly is claimable only with each part cited.
3. **n2 — transport assumption (D6):** semantic π is implementable as framework-owned provenance metadata iff the framework owns the transport; components with direct network access can side-channel around it. Instantiation-layer assumption, same character as A1; one honest sentence in the instantiation section.
4. **n3 — filter/alias interaction:** the alias-freedom invariant's statement is unchanged by attenuating caretakers (it concerns references, not filters), but verify in Alloy (§11.8).
5. **Over-restriction:** continuation capture removes the resumption false positive (§11.7a); the contract-satisfying logging deputy check (§11.6) remains the guard against residual over-restriction.
6. **Linearity of resolvers** is a calculus design choice, not property-critical; confirm no check in §11 depends on it, then note it as such in the calculus section of the paper.

## 11. Alloy checklist — status after v1–v4 (files: noescalation_v1/v2/v3.als)

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

**v1.1 additions (models/noescalation_v4.als, models/resolver_issuance.als, models/caretaker_finding.als):**
11. Caretaker confused deputy, un-scripted: `V10_admits_escalation` **invalid** ⇒ motivating counterexample #4. Setup witnessed (`CareSetupSat` SAT).
12. Repair validated non-vacuously: `CareRepairedSat` SAT, `V11_prevents_escalation` valid.
13. Precision: `LegitSat` SAT, `Legit_clean` valid — legitimate revocable delegation survives the repair.
14. Variant A (caretaker chain R₁→R₂): SAT + valid.
15. Variant B (resolver-invoked caretaker): SAT + valid — *after* the first encoding was found self-contradictory (`host = createdIn.actor` vs. a hand-set host), whose "valid" reading was vacuous. Third catch by the witness rule.
16. Guarded-perform precision: SAT + valid.
17. Resolver issuance discriminator: `C1` SAT (creation-turn bypass), `C2` UNSAT (invoker-turn closes it), `C3` SAT (no over-blocking).

**Known gap:** v4 dropped payloads, so **Membrane / alias-freedom is untested under the repaired contract** — it is verified only in v3 against the v1.0 (un-Guarded) caretaker. Re-check with payloads restored before T4 is attempted.

Model-driven findings fed back into this note: attribution unification (Benchmark 1); attached bounds and NE-D (Benchmark 2); continuation capture and the naive-reply refutation (D5); alias-freedom base case (v2 counterexample); the sub-effect principle and empty-housekeeping finding (item 6 / instantiation audit); the caretaker confused deputy and the resolver-issuance gap (v1.1). **Checklist 17/17 at v1.1; frozen.** Next phase: prior-art reads (Abadi–Fournet; Maffeis–Mitchell–Taly; DIFC; McCullough/Clarkson–Schneider re-verification), then Lean mechanization beginning with the kernel transcription and the NE-S ⇒ NE lemma.

## 12. Post-freeze addendum (mechanization + concurrency)

*The frozen text above is left unedited. This section records what the subsequent Lean mechanization and the concurrency test established, corrected, or left open. Where this addendum and the frozen text disagree, this addendum is current. Full claim ledger: `CLAIMS.md`; falsification record: `LEDGER.md`.*

### 12.1 What mechanization confirmed
Every live theorem of §8 is machine-checked in Lean 4 (Mathlib-free), with one deliberate `sorry` marking the *retracted* v1.0 target as provenance. Proved: NE-S⇒NE-T (T0), soundness (T1), mixed composition (T2), chain conferral (T3), bound antitonicity and mixed-system NES (T3a/b), the full revocation stack (T4a–f), graceful degradation (T2u). Both vacuity risks are closed: NE is refutable (`Sanity`), and the caretaker contracts are jointly satisfiable *while forwarding* (`CareSanity.contracts_livable`) — so T4 is not vacuous for caretakers.

### 12.2 What mechanization corrected
- **T2 needs no inductive invariant.** §8's prediction was false in the favourable direction: composition is three lines, because effbound is turn-local. The depth relocated to T4. (LEDGER L4.)
- **A6 is discharged, not assumed.** The resolver case initially carried a scoping assumption (no caretaker-hosted resolvers) that existed only because the encoding still stamped from the *creation* turn — the rule §6 already refuted. `invokeRes` fixes issuance at the invoker's turn; the assumption is deleted and replaced by a proved invariant (`InvokedOK`). (LEDGER L12.)
- **Membrane binds only fresh messages.** Mechanizing alias-freedom surfaced a case split invisible in §7's prose: the contract's forward-looking promise covers newly-pipelined messages; already-in-flight ones are covered by the invariant's history. (LEDGER L9.)

### 12.3 The concurrency finding (the important one)
§2's turn model assumes one active turn and no shared memory. A separate concurrent semantics (`Concurrent.lean`) tests whether the results depend on that: a **set** of simultaneously-active turns over a **shared** store, narrowing visible across turns — genuine overlap, not lock-serialised interleaving.

- **Spatial NE survives (`CNE_holds`), in one line.** Because effbound reads only the performer's own bound and its own message-carried context, no concurrent turn can widen them. Turn-locality of the *spatial* guarantee is a fact about the property, not an artifact of the encoding. **This is the foundation a guard is built on, and it is sound under concurrency.**
- **The temporal invariant does not transfer for free (`CNE_startbound`).** The sequential result "effects stay within the *start-of-run* bound" (T3b) fails under concurrency: only the *current* bound is guaranteed, because a concurrent narrow can intervene between a turn opening and an effect firing. The failure direction is safe (bounds only shrink), but the happens-before order T4's revocation argument relies on is **absent** from the concurrent model.

**The honest boundary of the contribution:** authority confinement (spatial) composes under concurrency; revocation *effectiveness* under concurrency is **open** and requires an explicit happens-before relation not yet in the model. A guard may rely on the former today; the latter is declared future work. (LEDGER L13; CLAIMS T7 / T7-lim.)

### 12.4 Two note↔development gaps — resolved by decision

Both are recorded here with a decision, not left open-ended:

- **T4 weak form — per-step PROVED (`T4_weak`); trace-preservation is the named open obligation.** The development proves the *strong/quiesced* theorem outright. For the *weak* form (no quiescence), an attempt located the boundary precisely: the **per-step** statement is now proved — a caretaker's underlying-only effect is `F e ∨ StaleLicensed e`, i.e. within `F` unless licensed by a message already in flight when the filter narrowed (the residual window, named in the conclusion rather than assumed away). What remains is a single preservation lemma — that the weakened invariant `RevInvWeak` (the bundle minus `NoStaleLicense`) is maintained along a trace — which is the honest open obligation. So the weak form is not a vague deferral: it is per-step proved, with exactly one located lemma outstanding.

- **NE-S chain clause — note-only, subsumed.** §5's NE-S clause (ii), over in-flight messages and live continuations, is not mechanized. Decision: it is **marked note-only**, because the trace property NE-T (the actual safety guarantee) is proved independently in Lean, and the component clause `mixed_NES` is proved directly. Clause (ii) is an intermediate invariant of one *proof strategy* for NE-T, not a separate guarantee; the Lean reaches NE-T by another route, so the clause is not load-bearing and needs no mechanization. Not a discrepancy in what is guaranteed — only in which intermediate lemmas each artifact uses.

### 12.5 Deliberately deferred (not gaps): result-side mediation

Result-side mediation — the Membrane property applied to what a server returns (a result leaking a capability handle or the underlying reference) — is **deliberately out of scope for this version**, in both the spec (§5.2, §7.2) and the proxy (`pump_inbound` relays results unchanged). This is not an oversight or a loose end: guarding returned values is a distinct design question (what a "result bound" means) of the same character as the concurrency boundary, and belongs to follow-on work. The current contribution guards *outbound* authority; result-side guarding is named future work.

## Changelog v1.0 → v1.1

- **§8 target theorem replaced.** v1.0's `A1–A4 ⇒ NE` was false; machine-refuted in Lean (`composition_target_unprovable`, commit 8b4e53e). Replaced by T1–T4 over two semantic layers.
- **Guarded semantics added (§5)** as the enforcement layer; unguarded semantics retained as the specification layer.
- **A5 (mediation) added (§8)**, with its failure mode named in §9.
- **Caretaker Guard (§7)** — the confused-deputy repair; Guard unified across all trusted components. Model-checked: v1.0 contract admits escalation (invalid), v1.1 contract does not (valid, non-vacuous).
- **Issuance defined for resolver-induced turns (§6)** as the invoker's turn; creation-turn licensing refuted as Benchmark 3 at the continuation level. Filter clause no longer vacuous on resumed forwards.
- **§11**: seven new checks recorded; one known gap (alias-freedom under the repaired contract) flagged.
- **Method note.** Three of this project's errors were prose theorem statements asserted without a checker ("safety property ⇒ McCullough inapplicable"; "InitOK ⇒ NE"; "no third source of effects"). Each was caught by forcing contact with a proof obligation or an adversarial construction. v1.1 states no claim that has not been either proved, model-checked at scope, or explicitly flagged as open.

## Changelog v0.2 → v0.3

- Turn-based semantics; contexts re-sited from components to messages; propagation rules 1–5 (D1, D2 amended by D5).
- Continuation capture replaces the stipulated reply rule; concrete false-positive trace of the naive rule added as Alloy 7a; resolvers linear (D5).
- attributed(ε) glossed as authority provenance, not causal influence; EA restated accordingly; §9 residue named as influence-without-authority, covering laundering and resolution-content steering in one category (D5).
- Honest tagging deleted; A3 weakened, theorem strengthened (D3).
- Spawn extends context; no persistent spawn taint (D4).
- Attenuating caretakers: revocation = F = ∅; static/dynamic scoping framing; generalized effectiveness theorem (D-bonus).
- §10.1 and §10.5 removed as resolved; transport assumption and filter/alias check added.