# LEDGER — Falsification Record

Every claim this project made that turned out to be wrong, what killed it, and what replaced it.

This file exists because it is the credibility argument. The definitions in `property/` are not the ones that were first written down — they are the ones that survived being attacked. A reader who wants to know whether the surviving claims were made to fight should read this file, not the abstract.

**The pattern, stated up front:** every substantive error was a **prose claim asserted ahead of a checker**. Not one survived contact with Alloy, Lean, or a deliberate adversarial hunt. None was found by re-reading.

---

## Substantive falsifications

### L1 — "NE is a safety property, so McCullough's non-composability doesn't apply"
**Killed by:** re-reading Clarkson–Schneider against the actual statement.
**What was wrong:** conflated two different properties under one name — the trace property and the state-level invariant quantifying over futures.
**Replaced by:** the NE-T / NE-S split, kept formally distinct ever since; NE-S ⇒ NE-T became T0 and is proved.

### L2 — "InitOK → NE" (v1.0's main theorem)
**Killed by:** Lean. `Sanity.composition_target_unprovable`, commit `8b4e53e`.
**What was wrong:** A1–A4 are all structural/initial conditions and cannot constrain what an untrusted component *does*. The Benchmark-2 shape satisfies InitOK and reaches an NE violation. **The counterexample had been sitting in the Alloy suite since v1** — `B2_AttachedFlags` certifies exactly this run — but the suite checked the specification side and never encoded §8's universal claim, which lived only in prose.
**Replaced by:** the two-semantics restatement (v1.1): guarded enforcement for untrusted components, contracts for trusted ones, A5 named. The false target is retained, `sorry`'d and labelled RETRACTED, as provenance of its own refutation.
**Lesson:** a green suite is green only on the questions it was asked.

### L3 — "There is no third source of effects"
**Killed by:** an adversarial hunt, requested as a gate rather than accepting confidence.
**What was wrong:** the v1.0 caretaker contract had Membrane and monotone filtered forwarding but **no Guard clause**. A contract-satisfying caretaker could perform a resource effect outside the requesting chain's conferral — the confused deputy, inside our own revocation mechanism.
**Replaced by:** Guard unified across *all* trusted components (v1.1 §7). Mechanized in `caretaker_finding.als`, then un-scripted in `noescalation_v4.als` (`V10_admits_escalation` invalid). Promoted to motivating counterexample #4.
**Lesson:** totality claims ("no other X") are the highest-risk sentence form in the project.

### L4 — "T2 requires a chain-level inductive invariant"
**Killed by:** attempting to derive the invariant. The derivation refused to produce one: `MStep_guards` already discharges every step case unconditionally.
**What was wrong:** the claim was false in the *favourable* direction — T2 is three lines, and needs no initial conditions at all.
**Replaced by:** T2 proved, with the triviality reframed as the result: effbound is turn-local, so the enforced property composes by design. The thin-direct-theorem shape recurs across this literature (Fournet–Gordon, MMT).
**Lesson:** unchecked prose errs in both directions. Optimistic errors are still errors.

### L5 — Creation-turn issuance for resumed forwards
**Killed by:** `resolver_issuance.als` C1 — the bypass exhibited, not argued.
**What was wrong:** licensing a resumed caretaker forward by the resolver's *creation* turn lets a grantee capture a continuation pre-revocation and cash it post-revocation. That is Benchmark 3 reproduced at the continuation level, undoing the structural alias-freedom decision.
**Replaced by:** invoker-turn issuance, uniform across trigger kinds. C2 UNSAT (bypass closed), C3 SAT (not over-blocking).
**Status note:** the Lean encoding still stamps from creation and scopes resolvers out by hypothesis (A6). **This is a live landmine until `invokeRes` lands.**

---

## Method catches (the discipline working)

### L6 — A vacuous check read as a green check
`caretaker_finding.als`: `RepairedSat` came back UNSAT, which made `Repaired_prevents_escalation` **vacuously** valid. The repair was validated only against a *scripted* trace. Caught by the standing rule that every `check` needs an adjacent satisfiable `run`. Non-vacuous validation moved to `noescalation_v4.als`.

### L7 — A self-contradictory scenario predicate
`ResolverSetup` v1 set `k.createdIn = t1` and `k.host = R` while `ResRule` forces `host = createdIn.actor` — unsatisfiable at every scope, so its "valid" check certified nothing. Third catch by the same witness rule.

### L8 — Scope arithmetic
`util/ordering[Turn]` makes the Turn scope **exact**; Message scope must be ≥ Turn scope or scenarios silently die. Standing rule since v1.

### L9 — Membrane binds only *fresh* messages
Discovered during mechanization of `Step_alias_preserved`: the caretaker send case needs a `pending-before` / `freshly-pending` split invisible in the English statement of Membrane. Already-in-flight messages are covered by the invariant's history, not by the contract's forward-looking promise.

### L10 — `IssuedOK` was missing from the T4 invariant
Discovered by attempting the T4 induction. T4a yields `cfg.issued e`; reaching `F e` requires `issued ⊆ F`, which is a property of *how the turn opened*, not of the performing step. Added as the fourth conjunct — conditional on the performer being a caretaker, since turns opened at non-caretakers carry unconstrained stamps. Its `startRes` case is what forced A6 into the open.

### L11 — Positioning claims corrected against primary sources
Three packet claims failed verification and were rewritten: SAFKASI called "sequential" (it handles threads, with spawn-time context inheritance); MMT credited with "no per-delegation conferral" (their no-amplification clause *is* a transfer bound — what is missing is the declarative half); and the field described as lacking formalization (LLMbda, Song et al., and AITH all predate the claim). Seven primary sources read; three corrections.

---

## What this record is evidence for

1. **The definitions were made to fight.** Five substantive claims died; each replacement was re-checked, not merely re-asserted.
2. **The instruments disagree with the author, repeatedly.** Alloy found L3, L5, L6, L7. Lean found L2, L9, L10. That is the argument for using both.
3. **The failure mode is legible and specific.** It is not "reasoning errors" in general — it is *totality claims and theorem statements written in prose before a checker saw them*. Knowing the shape of one's own error mode is worth more than a lower error count.

---

## L12 — A6 discharged, not merely scoped

**Recorded because it closes L5.** The resolver-issuance memo adopted invoker-turn licensing after C1 refuted creation-turn licensing — but the Lean encoding kept stamping from creation and excluded caretaker-hosted resolvers via an assumption (`NoCareRes`, A6). That is: the development contained a rule its own model checker had refuted, made harmless by a hypothesis.

`invokeRes` closes it. Issuance is now fixed at the invoker's turn by construction, and A6 is replaced by `InvokedOK` — a proved invariant (invocation stamps with the current filter; filters only narrow) rather than a hypothesis. Continuations are covered by T4 instead of excluded from it.

**Lesson:** a scoping assumption introduced to route around a known-wrong encoding is a deferred error, not a scoping decision. It survived two sessions and three artifacts (memo D3, the `RevInv` bundle, the CLAIMS A-table) before being discharged. Naming it in CLAIMS as *temporary* is what kept it visible.

---

## L13 — The concurrency test, and what it found (a limitation, not an error)

Not a falsification — a deliberate stress test of the suspicion, raised repeatedly, that turn-locality might be an artifact of the turn-based semantics rather than a fact about the domain.

**The test:** a concurrent model — a *set* of simultaneously-active turns over a *shared* store, with `narrow` shrinking a shared bound while other turns run. Genuine overlap, not lock-serialised interleaving (which would have re-imposed the very locality under test and proved nothing).

**Result — two-sided, and that is the point:**
- **NE survives (`CNE_holds`, one line).** The spatial property holds because effbound reads only the performer's own bound and its own message-carried context; no concurrent turn can widen them. Turn-locality of the *spatial* guarantee is real, not an encoding artifact.
- **The temporal invariant does not transfer (`CNE_startbound`).** The sequential `mixed_NES` proved effects stay within the *start-of-run* bound; under concurrency only the *current* bound is guaranteed, because a concurrent narrow can intervene. The failure direction is safe (bounds only shrink), but the happens-before order T4's revocation argument relies on is absent from the concurrent model.

**Why this is the most valuable entry in the file.** Every earlier item was a prose error caught by a checker — real, but definitional in flavour. This is a genuine structural fact about the problem: authority confinement composes under concurrency; revocation effectiveness under concurrency is open and needs explicit ordering. It is the first result that is hard in the way that matters, and it was found by building the adversarial model rather than by trusting the easy one.

**For the paper:** claim NE's concurrency-robustness as a strength; state the temporal-transfer gap as declared future work. Do not paper over it — it is the honest boundary of the current contribution, and stating it is what makes the strength credible.

---

## L14 — Spine audit: four CHECKED rows point at a missing file

A CLAIMS-vs-repo audit (every evidence pointer resolved against the actual files) found that rows **C1, C2, C3, C8** cite assertions "in v3" — `noescalation_v3.als` — which is **not present in `models/`** (only v4, alias_v11, and the specialized files are committed). The named assertions (`B1Sat`, `B1_ChainFlags`, `B2AttackSat`, `HkInRequestFlagged`, `OperatorTurnClean`) do not appear in any current `.als`.

The checks were real during development; the drift is that their evidence file was superseded and not carried forward, so the pointers are now **unreproducible**. CHECKED status with a dangling checker is the "prose ahead of a checker" failure mode (L1–L5) in a new form — a checked claim whose checker walked away.

**Resolution (choose):** (a) restore `noescalation_v3.als` so the pointers resolve; or (b) re-verify the four benchmarks in a current file and repoint, downgrading any not reproduced to STATED. Until resolved, C1/C2/C3/C8 are marked evidence-pending in CLAIMS.

**Lesson:** the spine audit is not ceremony. Every "solidify" needs one, because file consolidation silently orphans pointers even when no claim was ever false. The evidence layer drifts even when the theorem layer doesn't.

### L14 update — C1/C2 resolved, C3/C8 remain

git confirmed outcome 3: no v-series `.als` was ever committed (only one docs-reorg commit touched those paths). The B1/B2/D5/housekeeping checks were run in the Alloy GUI during development against files that never entered git.

**C1/C2 fixed properly:** B1 and B2 re-encoded in `benchmark_attacks.als` (committed). On first run Alloy found **two of eight assertions invalid** — `B1_InvisibleToPerf` (a too-strong set-subset claim; corrected to an existential) and `B2_LegitClean` (a wrong `perfBound` definition using the last hop instead of the performer's own hop). Both were *my* encoding errors, caught by the checker before they could be recorded as CHECKED. After correction, all eight commands green. C1/C2 repointed.

This is L14's own lesson enacted in miniature: re-encoding "from memory" reintroduced the exact prose-ahead-of-checker error, and only running the checker caught it. The file existing was not evidence; the file running green was.

**C3 (D5 continuation-capture) and C8 (item-6 housekeeping) remain evidence-pending** — same treatment needed (re-encode + run, or downgrade to STATED). Not blocking, but not closed.