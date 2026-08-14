# Decision Memo: Restatement of the Composition Target (v1.0 → v1.1)

**Status:** proposed; gates the invariant search and the v1.1 freeze.
**Trigger:** two machine-checked / adversarially-constructed findings against v1.0 §7–§8.
1. `composition_target_unprovable` (Lean, commit 8b4e53e): `InitOK → NE` is false — the B2 shape satisfies InitOK yet violates NE. Untrusted components' `perform` steps carry no check of any kind; A1–A4 are structural and cannot prevent escalation.
2. **Caretaker confused-deputy** (this memo, §2): a contract-satisfying caretaker (v1.0 §7 obligations = Membrane + monotone filtered forwarding, *no Guard*) performs a resource effect outside the requesting chain's conferral. The mixed-system theorem as first drafted is also false.

Root cause, unified: v1.0 left `perform` **unchecked for untrusted components** and **under-checked for caretakers** — the same missing conjunct (effbound membership at the performer) in two places.

**Grounding:** Schneider, "Enforceable Security Policies" (2000) — execution monitors enforce exactly the safety properties. NE is a trace safety property (v1.0 §5), hence monitorable; the restatement makes the monitor explicit. Precedent for enforcement-in-semantics: Fournet–Gordon (λ_sec, checks in the reduction rules), Maffeis–Mitchell–Taly (capability-safe *language*), CaMeL (interpreter-level). Behavioral conditioning of all components is rejected: vacuous for untrusted LLM components, and the only option with no precedent.

## 1. The two-semantics hybrid

Keep the current **unguarded** semantics as the *specification layer* — the benchmark suite and Alloy models live on it; NE-violating runs are what the attack scenarios exhibit and must remain expressible.

Add a **guarded** `perform` for components the framework mediates:

> **GuardedPerform.** `cfg.phase = .active p π` and `(∃ k, store p k ∧ k.denotes e)` and **`effbound(π) e`** (i.e. `bound p e ∧ π.meet e`) ⟹ step emitting `eff p π e`.

Untrusted components step only via GuardedPerform (framework mediation). Trusted components step via unguarded `perform` but are constrained by their **contracts** (§3) — because the framework cannot enforce a deputy's exercise of its own ambient authority (the audit's GitHub-token finding: the server calls the API outside the orchestrator's reach).

**New assumption A5 (mediation).** Untrusted components have no actuators outside the framework: every effect they cause is a GuardedPerform, or is a request whose eventual effect is performed by a trusted component under that request's context. *Honest failure mode:* an "untrusted" component with independent network egress (direct sockets, a side channel) violates A5 and is outside the model — this is the D6 transport assumption promoted from instantiation footnote to named hypothesis, and the paper must state it at the same volume as A1.

## 2. The caretaker confused-deputy (the finding)

Trace (all mixed-system assumptions hold):
- Untrusted G is guarded. P sends G a request with meet `{X}`; ResEff ∉ {X}.
- G holds `c_R` (old grant) routed through caretaker R; R's filter F ∋ ResEff (not yet revoked).
- During G's P-turn, G **sends** an invocation to R. Sends are unguarded — correctly (wider-β-harmless depends on it).
- R's turn opens under π = ⟨P…⟩·(G, β_G). R's v1.0 contract: ResEff ∈ F at issuance ✓; underlying reference never emitted ✓ — **contract satisfied**. R performs ResEff.
- ResEff ∉ meet(π): P conferred only {X}. **NE violated.**

R is Hardy's confused deputy: it holds ambient authority (the underlying capability — the caretaker's entire purpose), services requests, and consulted the *grantor's* dynamic filter while never consulting the *requester's* chain conferral. Invisible to the Alloy suite because `Effectiveness` asserts *who performs and whether the filter licensed it*, never NE, in a scenario disjoint from the NE checks. **Suite lesson:** scenario coverage ≠ property-over-scenario coverage.

## 3. Repaired trusted-component contracts (§7 rewrite)

**Guard (all trusted components, unified).** A trusted component performs `e` under context π only if `effbound(π) e`. This is the single missing conjunct; it was already the deputy obligation (v1.0 §7) — the repair is *extending it to caretakers*, not inventing it.

- **Guarding deputies:** Guard. (unchanged)
- **Caretakers:** Guard **and** Membrane **and** monotone filtered forwarding: forward/perform an underlying effect iff `e ∈ F` **and** `effbound(π) e`.

Corollaries survive: effectiveness *strengthens* (strictly fewer forwards); legitimate revocable delegation still passes, because a proper grant places the resource effects in the chain's β, satisfying both conjuncts.

Rejected alternative — guarding *sends*: breaks wider-β-harmless and places the check at the party lacking the authority. Guard belongs at the performer (ocap discipline; same placement as the item-6 D5 resolution).

## 4. Theorems (for the Lean development)

- **T1 Soundness.** Every guarded trace satisfies NE. *(Near-definitional; the floor. State it plainly per the Fournet–Gordon precedent — thin guarantee, honestly labeled.)*
- **T2 Mixed-system composition (centerpiece).** Under A1–A5 and InitOK', every trace of a system of GuardedPerform-untrusted components and contract-satisfying trusted components satisfies NE. *Real content:* trusted performs carry no semantic check, so A3's obligations thread through the turn induction; rely–guarantee with the honest deployed architecture.
- **T3 Attenuation soundness (spatial corollary).** Attached bounds + captured contexts confer no authority beyond the meet. *(Chain-conferral lemma: meet ⊆ every hop's β; five-line induction over Ctx.)*
- **T4 Revocation effectiveness (temporal corollary — now the hardest proof).** After filter narrowing, no post-issuance effect outside F is attributable through the caretaker, given alias-freedom **established at conferral and preserved** (base case + induction over unbounded traces and evolving reference graphs; the Lean generalization of the corrected `AliasPreserved`). Depth migrates here — fitting, as mid-trajectory revocation was the original "mostly unaddressed" problem.

`InitOK'` revises `InitOK` (the Lean `sorry`'d structure): drop the false implicit "structural conditions suffice for untrusted components," add the mediation clause. Exact form co-evolves with the T2 invariant search — that co-evolution is the work.

## 5. Alloy additions (before v1.1 freeze)

1. **GuardedStep**: a `perform` variant carrying the effbound conjunct; untrusted performers restricted to it.
2. **Counterexample (motivating #4)**: v1.0 caretaker contract (no Guard) + the §2 trace → NE violation SAT. The paper figure: "our own v1.1-predecessor contract contained a confused deputy."
3. **Repair valid**: Guard-augmented caretaker + §2 setup → NE holds (no counterexample, scope 5–6), non-vacuous (witness the legitimate revocable-delegation run).
4. **Variant A — caretaker chain**: R₁ forwards to R₂; assert the final performer's Guard binds against the full chain → NE holds.
5. **Variant B — resolver-invoked caretaker**: R invoked via a captured resolver rather than a fresh send; Guard reads the captured context's meet → NE holds.
6. **Precision regression**: re-run B2-legit, retention, operator-turn against GuardedStep → still clean (guarding doesn't over-block).

Standing rules 1–2 apply (every scenario gets a satisfiability witness; watch turn/message scope arithmetic).

## 6. Patch list v1.0 → v1.1

- [ ] §5: add GuardedPerform semantics as the enforcement layer; unguarded semantics retained as specification layer.
- [ ] §7: unify Guard across all trusted components; add Guard to the caretaker contract (Membrane + monotone filtered forwarding + Guard).
- [ ] §8: A5 (mediation) added; target theorem replaced by T1–T2; InitOK → InitOK'; corollaries → T3–T4.
- [ ] §9: A5's failure mode (independent egress) noted alongside the influence residue — same category as the telemetry side channel.
- [ ] §11: Alloy items 1–6 above; note the suite lesson (assert the property over the caretaker scenario, not only the caretaker's local contract).
- [ ] Changelog: root cause (unchecked/under-checked `perform`), both findings, the meta-note on totality-claim discipline.

## 7. Honest residuals

1. **Totality-claim ledger:** three prose claims asserted without a checker have now been false ("it's a safety property so McCullough doesn't apply" — corrected to the NE-T/NE-S split; "InitOK → NE"; "no third source of effects"). Each caught by forcing contact with a proof obligation or adversarial construction. The variant hunts (§5.4–5.5) are encoded, not trusted, for exactly this reason.
2. **T2's induction is unwritten** — the mixed performer/guarded case split is the real difficulty; expect InitOK' to change under it.
3. **A5 is the load-bearing realism assumption.** If real agent deployments routinely give components independent egress, T2 is true but its hypothesis is often false — an instantiation-section honesty obligation, not a calculus fix.
