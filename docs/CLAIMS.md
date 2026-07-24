# CLAIMS

Every claim this project makes, with its evidence. Nothing in the paper may state more than a row here permits.

**Evidence classes — the distinction that matters most:**

| Class | Meaning | Instrument |
|---|---|---|
| **PROVED** | Holds at all scopes, machine-checked | Lean 4 (v4.32.0), Mathlib-free |
| **CHECKED** | No counterexample *within a bounded scope*, non-vacuously | Alloy 6.2 / sat4j |
| **REFUTED** | Counterexample exhibited | Lean or Alloy |
| **STATED** | Written down, no evidence yet | — |
| **RETRACTED** | Asserted, then shown false; kept as provenance | see LEDGER |
| **ASSUMPTION** | Hypothesis; by definition unevidenced. Becomes a conformance requirement | → `conformance/` |
| **EXCLUDED** | Out of scope by argument | argument cited once, referenced everywhere |

A CHECKED row is **not** a proved row. Bounded scopes are evidence, not proof. Every CHECKED row's evidence includes its non-vacuity witness; a `check` with no adjacent satisfiable `run` proves nothing and is not admissible here.

---

## T — Theorems

| ID | Claim | Status | Evidence |
|---|---|---|---|
| T0 | NE-S (state invariant) implies NE-T (trace property) | PROVED | `Semantics.NES_T.implies_NE_T` |
| T1 | Every guarded trace satisfies NE (soundness) | PROVED | `Guarded.T1_soundness` |
| T1a | Every mixed step emitting an effect satisfies effbound | PROVED | `Guarded.MStep_guards` |
| T2 | Mixed composition: guarded-untrusted + contract-trusted ⇒ NE on all traces | PROVED | `Guarded.T2_mixed_composition` (3 lines; triviality *is* the locality result — see LEDGER L4) |
| T3 | Chain conferral: the running meet is inside every attached bound on the chain | PROVED | `Warmups.meet_sub_hop`, `Warmups.effbound_sub_hop` |
| T3a | Bounds only narrow along reachable traces | PROVED | `Warmups.Step_bound_antitone`, `MStep_bound_antitone`, `MReaches_bound_antitone` |
| T3b | Mixed-system NES: emitted effects stay inside the **start-of-run** bound | PROVED | `Warmups.mixed_NES` |
| T4a | Caretaker forwards lie inside their issuance stamp | PROVED (near-definitional — not the content; see memo D2) | `Revocation.T4a_within_issuance` |
| T4b | Sole route: no non-caretaker performs an underlying-only effect | PROVED | `Revocation.T4b_sole_route` |
| T4b′ | Same claim, scope-bounded, with hypothesis shown load-bearing | CHECKED (6) | `sole_route.als`: `SoleRoute` valid; `SoleRouteLive` SAT; `WithoutAliasFreedom` SAT |
| T4c | Alias-freedom is preserved along membrane-respecting traces | PROVED | `Alias.Step_alias_preserved` → `MStep_alias_preserved` → `alias_free_along` |
| T4c′ | Same, scope-bounded, under the **repaired** (v1.1) caretaker contract | CHECKED (5/5) | `alias_v11.als`: `AV_AliasPreserved` valid; `AV_SetupSat`/`AV_Live` SAT |
| T4d | Filters only narrow | PROVED | `Revocation.Step_filter_antitone`, `MStep_filter_antitone` |
| **T4** | **Revocation effectiveness (strong/quiesced): no underlying-only effect outside F is ever performed, for message- AND resolver-triggered turns** | **PROVED** | `Revocation.T4_effectiveness`, via `RevInv_along`; supporting: `NoStaleLicense_preserved`, `RevInv_step`, `IssuedOK`, `InvokedOK` |
| T4e | Issuance for a resumed continuation is fixed at the **invoker's** turn | PROVED + CHECKED (8) | `Semantics.Step.invokeRes` + `Revocation.InvokedOK`; `resolver_issuance.als` C1/C2/C3 |
| T5 | Guard and Membrane protect **different** theorems: NE can hold while revocation fails | CHECKED (5) | `alias_v11.als`: `T4_fails_NE_holds` SAT — the reason T4 is not a corollary of monotone filters |
| T4f | **A3 is satisfiable**: a caretaker can discharge Guard + Membrane + filtered forwarding *simultaneously* and still perform the resource effect — so T4 is not vacuous for caretakers | PROVED | `CareSanity.contracts_livable` (unbounded); `alias_v11.als` `AV_Live` SAT (scope 5) |
| T6 | Chain- and history-based access control are **incomparable** | CHECKED (6) | `history_vs_chain.als`: `D3_BothFlag`, `D1_HistoryOverRestricts`, `D2_HistoryMissesDeputy` all SAT |

---

## C — Counterexample claims (each forced a definitional decision)

| ID | Claim | Status | Evidence | Forced |
|---|---|---|---|---|
| C1 | Performer-only attribution certifies the confused deputy | CHECKED (6) | v3 `B1_InvisibleToPerf` valid *(validity is the indictment)*; `B1_ChainFlags` valid; `B1Sat` SAT | chain attribution |
| C2 | Component bounds alone hide re-amplification | CHECKED (6) | v3 `B2_InvisibleToPerf` valid; `B2_AttachedFlags` valid; `B2_LegitClean` valid; `B2AttackSat`/`B2LegitSat` SAT | attached bounds |
| C3 | Naive reply semantics flags legitimate resumption | CHECKED (8) | v3 `D5_NaiveAlwaysFlags` valid *(indictment)*; `D5_CaptureClean` valid; `D5_NaiveInstance` SAT | continuation capture |
| C4 | **The v1.0 caretaker contract admits a confused deputy** — found inside our own design | REFUTED-v1.0 / CHECKED (8) | `caretaker_finding.als` `V10_prevents_escalation` invalid; un-scripted in `noescalation_v4.als` `V10_admits_escalation` invalid | caretaker Guard clause (v1.1) |
| C5 | Creation-turn issuance readmits stale-capability bypass at the continuation level | CHECKED (8) | `resolver_issuance.als`: `C1_creation_admits_bypass` SAT; `C2_invoker_blocks_bypass` UNSAT; `C3_invoker_not_overblocking` SAT | invoker-turn issuance |
| C6 | The v1.1 repair closes C4 without blocking legitimate delegation | CHECKED (8) | v4 `V11_prevents_escalation` valid + `CareRepairedSat` SAT; `Legit_clean` valid + `LegitSat` SAT; `Chain_*`, `Resolver_*` SAT+valid | — |
| C7 | Guarded perform does not over-block | CHECKED (6) | v4 `GuardedCleanSat` SAT, `GuardedClean_ok` valid | — |
| C8 | Item 6: request-turn housekeeping is a true positive; operator-turn housekeeping is clean | CHECKED (8) | v3 `HkInRequestFlagged` valid, `OperatorTurnClean` valid, both witnessed | sub-effect principle |

---

## A — Assumptions (unevidenced by definition; each becomes a conformance requirement)

| ID | Assumption | Becomes requirement |
|---|---|---|
| A1 | Capabilities are unforgeable; ocap discipline (only send what you hold) | R1: no ambient capability construction; per-request credential injection |
| A2 | Provenance contexts are framework-constructed and unforgeable by components | R2: framework-owned request tracing; components cannot synthesise π |
| A3 | Trusted components discharge their contracts: Guard (all), Membrane + monotone filtered forwarding (caretakers) | R3: deputy performs its own effbound check; proxy never returns underlying handles |
| A4 | Component bounds only narrow | R4: no bound-widening API |
| A5 | **Mediation**: untrusted components have no actuators outside the framework | R5: no direct egress from untrusted components — *the load-bearing realism assumption; cf. Flume's confined/unconfined split* |
| A6 | E is at tool-invocation granularity; sub-effect traffic is implementation | R6: enforcement point sits at the tool-call boundary |

---

## S — Scope exclusions (argued once, cited everywhere)

| ID | Excluded | Argument |
|---|---|---|
| S1 | Influence without authority: covert channels, cross-chain intent, poisoned resolutions | Hyperproperty, not trace safety; McCullough non-composability. NE is deliberately the authority half. *(Complementary formal work now exists: LLMbda's noninterference theorem.)* |
| S2 | A5 failure: a nominally-untrusted component with independent egress | Outside the model; named at the same volume as A1 |
| S3 | Bound selection — whether the β a sender chooses is the *right* one | Intent, not authority. Paper two. |
| S4 | Over-restriction analysis: when the running meet blocks legitimate work | Deferred deliberately; strongest paper-two candidate |
| S5 | Hosted deployment of the audited server; dependency I/O beyond first-party grep | Audit scope stated at commit `1338dbe`; idle-egress capture is the pending backstop |

---

## Instantiation

| ID | Claim | Status | Evidence |
|---|---|---|---|
| I1 | For a production tool server, the in-E housekeeping set is **empty** at tool-call granularity — chain-intersection flags nothing legitimate | AUDITED @ `1338dbe` | `instantiation/audit.sh`, `audit-output.txt`, `github-mcp-server-inventory.md` |
| I2 | Serving-path egress is GitHub-only; no vendor telemetry | AUDITED @ `1338dbe` | audit §5 empty, §9 shows `api.githubcopilot.com` only in docs tooling |
| I3 | The lockdown cache's cross-tenant isolation is by **convention** (`WithCacheName`), not enforcement | AUDITED @ `1338dbe` | `pkg/lockdown/lockdown.go:186`, `TestRepoAccessCacheIsolatesViewerPerInstance` |
| I4 | The server originates **no network connections at idle** (zero tool calls, 300 s, per-process) | MEASURED @ `1338dbe` | `instantiation/idle-egress-native.sh`, `idle-egress-capture.txt` — empirical backstop for I2, which grep could only establish structurally |