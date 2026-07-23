# Model Suite — Expected Verdicts

Alloy Analyzer 6.2, sat4j, macOS arm64. One table per file; run Execute All and compare. **The `.als` files are authoritative for command names and scopes**; this table records expected verdicts and, critically, *how to read them* — several commands are deliberately invalid or deliberately SAT (marked ⚑ FINDING), and several UNSATs are meaningful only because an adjacent witness is SAT (standing rule 1).

Conventions: **SAT** = instance found ("consistent"); **valid** = no counterexample; **invalid** = counterexample found. With `util/ordering[Turn]`, Turn scope is exact, so Msg scope ≥ Turn scope throughout.

## noescalation_v1–v3.als (v1.0-era suite; kept frozen as the historical record)

Progressive kernel → dynamic stores/caretakers → full suite. All commands green at the v1.0 freeze (10/10 checklist items; see note §11). Highlights and reading flags:

| Command (v3 unless noted) | Verdict | Reading |
|---|---|---|
| KernelSane, WiderBetaHarmless | valid | wider-β attached bounds never change verdicts |
| B1 attribution pair | valid | ⚑ for the *InvisibleToPerf*-style checks, **validity is the indictment** of performer-only attribution — the motivating counterexample, not a success of the design under test |
| B2_AttackP / B2_AttachedFlags / B2_LegitClean | SAT / valid / valid | re-amplification flagged; legitimate shared service clean |
| D5 naive-reply check | valid | ⚑ validity indicts the naive reply rule (motivating counterexample #3) — fixed by continuation capture |
| Retention scenario pair | SAT + valid | caps legitimately reused under later chains within their meets |
| Narrow/attenuation pair | SAT + valid | attenuation binds |
| Caretaker block: CareSat, CareLive, AliasPreserved, Effectiveness, HandoffAttack, RogueForwarder, WeakStrongGap | SAT ×2, valid ×2, SAT ×3 | v1.0-contract caretaker results — **superseded for the Guard question by v4** (the v1.0 contract admits a confused deputy that these scenarios never asked about; suite lesson: scenario coverage ≠ property-over-scenario coverage) |
| OperatorTurnSat/Clean, HkInRequestSat/Flagged | SAT/valid, SAT/valid | item-6 closure: operator-turn housekeeping clean; request-turn housekeeping ≡ B2, flagged |

## caretaker_finding.als (isolated finding, scripted)

| Command | Verdict | Reading |
|---|---|---|
| SetupSat | SAT | scenario inhabited |
| V10_prevents_escalation | **invalid** | ⚑ FINDING: v1.0 caretaker contract admits an NE violation (confused deputy in our own contract) |
| RepairedSat | UNSAT | ⚑ the repair blocks this *scripted* trace — which makes the next row **vacuous**; kept as a recorded lesson in check design |
| Repaired_prevents_escalation | valid (vacuously) | certifies nothing; the non-vacuous repair validation lives in v4 |

## noescalation_v4.als (v1.1 restatement validation, un-scripted)

| Command | Verdict | Reading |
|---|---|---|
| CareSetupSat | SAT | witness |
| V10_admits_escalation | **invalid** | ⚑ FINDING (motivating counterexample #4), effect chosen by the solver, not scripted |
| CareRepairedSat | SAT | repair admits real executions — makes the next row non-vacuous |
| V11_prevents_escalation | valid | Guard-augmented caretaker contract closes the leak |
| LegitSat / Legit_clean | SAT / valid | legitimate revocable delegation survives the repair |
| ChainSat / Chain_prevents_escalation | SAT / valid | variant A: caretaker chain R₁→R₂ |
| ResolverSat / Resolver_prevents_escalation | SAT / valid | variant B: resolver-invoked caretaker. NB: the first encoding was self-contradictory (host ≠ creator) and its "valid" was vacuous — third catch by the witness rule; fixed form requires 4 Turn / 3 Msg |
| GuardedCleanSat / GuardedClean_ok | SAT / valid | guarded-perform precision |

## resolver_issuance.als (issuance-rule discriminator; memo: resolver issuance)

| Command | Verdict | Reading |
|---|---|---|
| C1_creation_admits_bypass | **SAT** | ⚑ creation-turn licensing lets a continuation captured pre-revocation cash post-revocation — Benchmark 3 at the continuation level; the instance is the paper figure |
| C2_invoker_blocks_bypass | UNSAT | invoker-turn licensing closes the bypass — meaningful only jointly with C3 |
| C3_invoker_not_overblocking | SAT | invocations preceding narrowing still complete (no over-blocking) |

## alias_v11.als (§11 gap closure: alias-freedom under the *repaired* contract)

| Command | Verdict | Reading |
|---|---|---|
| AV_SetupSat / AV_Live | SAT / SAT | witnesses (Live: the caretaker actually performs the resource effect) |
| AV_AliasPreserved | valid | alias-freedom preserved under the v1.1 contract (scope 5/5) — the claim later mechanized unboundedly in `lean/NoEscalation/Alias.lean` |
| AV_Effectiveness | valid | resource effects only via the caretaker, licensed at issuance |
| T4_fails_NE_holds | **SAT** | ⚑ FINDING: Guard and Membrane protect *different theorems* — a run where NE holds and revocation is defeated through a leaked reference. T2 and T4 are independent |

## history_vs_chain.als (Abadi–Fournet discriminator; fairness notes in file header)

| Command | Verdict | Reading |
|---|---|---|
| D3_BothFlag | SAT | both disciplines flag the naive attack (agreement row — keeps the figure honest) |
| D1_Witness / D1_HistoryOverRestricts | SAT / SAT | ⚑ legitimate multiplexing: chain-clean, history-flagged (their applet-then-SQL degradation reproduced) |
| D2_HistoryMissesDeputy | **SAT** | ⚑ history *permits* the powerful-client confused deputy — per-request intent has no representation in the history model. Incomparability established |
