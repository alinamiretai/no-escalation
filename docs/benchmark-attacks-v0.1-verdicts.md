# Benchmark Attacks vs. Property Note v0.1: Scenarios and Verdicts

**Status:** working note, v0.1. Companion to `no-escalation-property-note.md`.
**Method:** each attack is stated concretely, then evaluated on two questions — (i) can the v0.1 definitions *express* the attack, and (ii) do NE-T / NE-S correctly *flag* it? A definition set that cannot express an attack, or that certifies an attacked run as safe, is refuted.

---

## Attack 1 — Confused deputy across a chained tool call

**Scenario.** Component A (untrusted planner) has B(A) = { read(/tmp/\*) }. Component C1 (file service) holds ambient capability c_T with ⟦c_T⟧ = { write(p) : all paths p }, so B(C1) ⊇ ⟦c_T⟧. A sends C1 the request "write(/etc/passwd)". C1 invokes c_T; effect e = write(/etc/passwd) occurs. e ∈ ⟦c_T⟧, e ∉ B(A).

**Verdict on v0.1.**
- *Latent inconsistency found.* EA (§3 of the note) attributes effects by **chain** ("induced by a message chain originating from C"); NE-T (§4) says "attributed to C" without fixing the relation. Under performer-attribution, e belongs to C1, e ∈ B(C1), **NE-T holds — attack invisible**. Under the chain reading, e ∈ EA(A) ⊄ B(A), **NE-S violated**. The two properties disagree because they silently use different attribution relations; the lemma NE-S ⇒ NE-T forced them to coincide without a decision being made. v0.1 is internally inconsistent on this point.
- *Forced fix.* Define **one** attribution relation, shared by EA and NE-T, and it must be chain-based: performer-only attribution certifies this run as safe and is therefore refuted.

**Resolution of Q2.** Split by trust:
- **Untrusted components:** resolution R3 (capability-confinement). No ambient authority; a deputy acts for A only with capabilities A passed in the request. The attack is unconstructible among untrusted components.
- **Trusted deputies with ambient authority** (unavoidable in the target domain — a tool server holding its own API key *is* an ambient c_T): these become **trusted components** whose rely–guarantee contract includes a **guard obligation**: exercise ambient capability c_T for a request only if the request's attached bound (see Attack 2) permits the resulting effect. This is R2 applied locally, as a proof obligation, rather than globally as label machinery.
- Consequence for the composition theorem: the trusted-component contracts are the assume–guarantee interfaces. The theorem's assumption set is now explicit: (a) ocap discipline for untrusted components, (b) each trusted deputy discharges its guard obligation.

---

## Attack 2 — Re-amplification of attenuated delegation

**Scenario.** Parent P holds c, ⟦c⟧ = { rw(p) : p under /project }. P delegates c↾A to sub-agent S with ⟦c↾A⟧ = { rw(p) : p under /project/src }, intending src-only scope. S also holds c′ with ⟦c′⟧ = { rw(p) : p under /project/docs }, granted by another principal Q. While working P's task, S writes /project/docs/plan.md.

**Case (a): S freshly spawned by P.** Then S holding c′ at all is the anomaly. **Fix is structural:** the calculus has no ambient/global store (ocap discipline); a fresh component's store is exactly what its spawner passed. Attack unconstructible. This is an assumption to state, not a theorem to prove.

**Case (b): S is a shared pre-existing service.** S legitimately holds both capabilities.
- DA(S) = ⟦c↾A⟧ ∪ ⟦c′⟧; B(S) legitimately covers both (Q granted docs).
- The docs-write is in B(S): **NE-T holds**. EA(S) ⊆ B(S): **NE-S holds**. **Both properties certify the attacked run as safe.**
- *Diagnosis:* "what P intended to confer" appears nowhere in the formalism. P's intent for this delegation (src only) is strictly narrower than both B(P) and B(S); no per-component object can represent a per-delegation intent. **v0.1's per-component bounds are refuted as sufficient.**

**Forced fix — attached bounds and NE-D.**
- Every send/delegation carries an **attached bound** β chosen by the sender, with monotonicity β ⊆ (current bound of the sending chain); a request chain's effective bound is the running meet of attached bounds.
- New property **NE-D (delegation-level no-escalation):** every effect attributed (chain-based) to a request chain lies within the chain's effective bound.
- Note the reduction: case (b) is the confused deputy again — S combining non-request-derived authority with a request. The chain machinery from Attack 1 handles both; the benchmark suite is coherent, not three unrelated patches.

---

## Attack 3 — Stale capability after mid-trajectory revocation

**Scenario.** P delegates access to resource r to S via revocation cell R: S holds c_R; invoking c_R forwards to underlying c (⟦c⟧ = effects on r) while R is uncleared. At step k, P clears R. At step k+1, S invokes a cached direct reference c_direct to r, bypassing R. Effect on r occurs after revocation.

**Verdict on v0.1.**
- *Definition breaks.* v0.1 fixes ⟦c⟧ ⊆ E statically. A revocable capability's effective authority is state-dependent, so either (i) denotations become state-indexed, ⟦c⟧ : State → ℘(E) — which infects DA, attenuation-as-⊆, and every downstream definition — or (ii) denotations stay fixed and the caretaker is modeled as a **component**: ⟦c_R⟧ = { invoke(R, ·) } only; authority over r reaches S only through EA, via R's forwarding behavior.
- **Adopt (ii).** DA stays simple; revocation effectiveness becomes a theorem in exactly the project's language:
  > **Revocation effectiveness.** If at step k the cell R is cleared, then for all steps ≥ k, ⟦c⟧ ∩ EA(S) = ∅ — *provided* no direct reference to c exists outside caretaker stores.
- *Resolution of Q3:* the proviso is the decision. **Structural (reference-graph) revocation:** well-formedness invariant *"direct references to revocable resources occur only in caretaker stores"*, preserved inductively by all transitions. Requires the caretaker to be a **forwarding proxy** (invocations cross; the underlying reference never does), i.e., Redell's caretaker / Miller's membrane done right. The runtime-check alternative is refuted by this scenario by construction: the cached reference's invocation path never visits the check.
- The caretaker joins the trusted-component class from Attack 1; its contract obligation is the membrane invariant (never emit the underlying reference, in any message or return value).

**New decision surfaced: in-flight effects.** An invocation issued through R before step k that lands after k. Choose a linearization semantics:
- **Weak revocation:** in-flight invocations complete; no new invocations after the clear. Realistic for agent trajectories; provable.
- **Strong revocation:** in-flight invocations are killed at the clear.
Commit to **weak** for the core theorem and state it explicitly in the revocation-effectiveness theorem (quantify over invocations *issued* after k).

---

## Synthesis: what the three attacks force

All three converge on one architecture:

1. **Single chain-based attribution relation**, shared by EA, NE-T, and NE-D. (Attack 1)
2. **Attached per-delegation bounds** with running-meet semantics; property NE-D added. (Attack 2)
3. **Ocap discipline** — no ambient store — as the structural assumption for untrusted components. (Attacks 1a-analog, 2a)
4. **A trusted-component class** with explicit contract obligations: guarding deputies (check request bound before exercising ambient authority) and caretakers (membrane invariant). These contracts are the rely–guarantee interfaces of the composition theorem. (Attacks 1, 3)
5. **Fixed denotations; revocation lives in EA**; weak-revocation linearization. (Attack 3)

## Change list: property note v0.1 → v0.2

- [ ] §3: define the attribution relation once (chain-based, inductively: an effect is attributed to every component on the inducing request chain, and to its performer). Use it in EA, NE-T, NE-D.
- [ ] §3/§4: add attached bounds on sends/delegations; monotonicity condition β ⊆ chain bound; define chain effective bound as running meet.
- [ ] §4: add NE-D; restate lemma structure (NE-S ⇒ NE-T; relation of NE-D to NE-S — likely NE-D is a family of NE-T-style properties indexed by chains, needing its own inductive invariant).
- [ ] §2/§3: state the ocap discipline assumption (no ambient store; fresh components hold exactly what the spawner passed).
- [ ] New §: the trusted-component class and its two contract obligations (guard; membrane). Note explicitly: the composition theorem is conditional on these obligations, and each obligation is a per-component lemma to be discharged in the mechanization.
- [ ] §5: rewrite revocation with fixed denotations + caretaker-as-component; state the revocation-effectiveness theorem with the alias-freedom invariant as proviso; commit to weak revocation.
- [ ] §7: add to known weaknesses — running-meet label semantics risks over-restriction (a trusted deputy doing legitimate internal work, e.g. logging, while servicing a narrow request); decide whether deputies act under dual attribution (own authority for own effects, chain bound for request-derived effects) — candidate answer: yes, and the guard obligation is exactly the discipline separating the two.

## Alloy checklist derived from this note

Encode and check, in order:
1. Deputy scenario with performer-attribution → expect NE-T to hold (reproduces the invisibility, as the paper's motivating counterexample).
2. Same with chain attribution + attached bounds → expect violation flagged; then add the guard obligation to C1 → expect no counterexample at scope 5–6.
3. Shared-service re-amplification without attached bounds → expect NE-S to hold while the attack succeeds (second motivating counterexample); with NE-D → flagged.
4. Caretaker with a transition that emits the underlying reference → expect membrane invariant violation and post-clear effect; with forwarding-proxy caretaker → expect revocation-effectiveness to hold.
