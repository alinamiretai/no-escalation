# Decision Memo: Item 6 — Housekeeping Effects and the Guard Contract

**Status:** decided. Closes §11 item 6 of `no-escalation-property-note-v0.3.md`; unblocks the v1.0 freeze.
**Evidence base:** source audit of github/github-mcp-server (local server), commit `1338dbed4a044ee26422d4212bac3a8037fdb7ff`, MIT-licensed; grep inventory in `audit-output.txt`; targeted file reads (`fields_telemetry.go`, `observability.go`, `internal/oauth/env.go`, `internal/profiler/profiler.go`).

## The question

Chain-intersection semantics (effbound) flags any deputy-owned effect performed during a request turn whose meet excludes it. Is this over-restriction (the stack-inspection problem, requiring a doPrivileged-style escape), or correct behavior?

## Decisions

**D1 — E is at tool-invocation granularity; sub-effect implementation traffic is below E.** (Restates and operationalizes note §2.) A tool-level effect's constituent operations — pagination requests, enforcement reads (the lockdown cache's permission/visibility queries), token acquisition and refresh, connection management — are the *implementation* of that effect, not effects themselves. They are attributed to the tool-level effect that occasioned them and are governed by its bound. Consequence: the audit's only bucket-3-shaped candidates (lockdown enforcement reads mid-request; OAuth refresh on a background context) dissolve by principle, not by case-by-case ruling.

**D2 — For this instantiation, the housekeeping set intersected with E is empty (evidence-backed).**
Audit results at the pinned commit:
- Local filesystem: runtime log file (opt-in `LogFilePath`), stderr/slog, `--export-translations` config write, docs/test tooling. All outside E (local disk is not protected resource space).
- Network egress in the serving path: GitHub API and GitHub auth endpoints only; zero third-party hosts (grep over non-test Go source). No vendor telemetry, no update checks.
- Metrics: `recordFieldsUsage` terminates in an injected no-op sink in the local server ("the local server wires a no-op metrics sink" — source comment); metric names carry tool + byte counts only, never payloads or identifiers.
- Subprocess: OS browser launcher for the interactive OAuth flow; auth plumbing below E per D1.
- The RepoAccessCache is in-memory state; its externally visible face is (a) enforcement reads (below E per D1) and (b) filtering decisions possibly derived from another viewer's cached verdict — the latter is influence, not authority, and falls in the §9 residue. Cross-tenant isolation of this cache is by *convention* (`WithCacheName`), not enforcement — an instantiation-section observation supporting the framework-assumptions story.

**D3 — Resolution of item 6: correct-as-is, with scoping stated.** No doPrivileged analog enters the core calculus. The apparent over-restriction was an artifact of imagining in-E housekeeping that, for a real production deputy, does not exist. Deputy-owned effects that *are* in E and occur in request turns outside the meet are true positives (cross-chain service; = Benchmark 2), and the Alloy suite already validates both directions (B2_AttachedFlags / B2_LegitClean).

**D4 — Housekeeping Deferral is documented as the general mechanism, not required here.** For deputies whose bucket 3 is nonempty (in-E, deputy-owned, no-client-governs effects), the sanctioned pattern is: buffer during request turns (state, below E); perform in operator-induced turns under operator conferral. Soundness: confers no authority the deputy lacks; self-sends cannot fake it (they inherit request π); the intent carried across turns is §9 residue. Adds an operator principal to the trust story — stated in assumptions when used. Not exercised in this instantiation.

**D5 — Guard contract, final form (for the Lean development).** For a trusted deputy D: *every tool-level effect D performs under context π lies within effbound(π)*, where tool-level is per D1. No housekeeping clause; no privilege primitive. (Honest-tagging remains deleted per the turn-semantics memo; contexts are semantic.)

## Alloy closure of item 6

- 6a (request-turn deputy-owned in-E effect outside meet → flagged): structurally identical to `B2_AttackP` / `B2_AttachedFlags`. Recorded as covered; no new scenario.
- 6b (operator-turn precision, validating D4's substrate): encoded in `noescalation_v3.als` as `OperatorTurnScenario` / `OperatorTurnClean` (coexistence trace: deputized work within a narrow chain at t1, own housekeeping under operator conferral at t2), with `HousekeepingInRequest` / `HkInRequestFlagged` as the local restatement of 6a. **Ran green** (both checks valid, both witnesses SAT; full v3 regression unchanged). Item 6 closed; v1.0 freeze executed.

## Honest residuals

1. Scope: the audit covers the **local** server at one commit. The hosted deployment (real metrics sink, GitHub-operated) is out of scope; if instantiated later, its metric byte-counters are a concrete §9 size side channel.
2. Dependency I/O is only partially excluded by first-party grep; the idle-run egress capture (proxy/tcpdump on the Docker image, zero tool calls) remains the recommended empirical backstop and should be run before the instantiation section is written.
3. `internal/profiler` appears slog-backed; whether it is flag-gated at runtime was not verified.
4. This audit is one person plus one model reading source; the inventory table (appendix) cites file:line for every claim so a reviewer can re-derive it.

## Consequences

- §11 item 6: ⛔ → ✅ (resolved by D1–D3; 6b pending encode).
- v1.0 freeze of the property statement proceeds after 6b runs clean.
- The paper gains: the sub-effect principle (D1) as one paragraph in the definitions; the empty-bucket finding as the instantiation section's central evidence ("for a production tool server, chain-intersection semantics flags nothing legitimate"); deferral (D4) and the doPrivileged lineage as one related-work paragraph.
