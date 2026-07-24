# Instantiation Audit — github/github-mcp-server

**Target:** github/github-mcp-server, **local server**, commit `1338dbed4a044ee26422d4212bac3a8037fdb7ff` (MIT). Hosted deployment out of scope.
**Method:** first-party grep inventory (`audit.sh` → `audit-output.txt`) plus targeted file reads. Every claim cites file:line at the pinned commit so a reviewer can re-derive it.
**Question answered:** at tool-call granularity (property-note §2), is the deputy's *housekeeping ∩ E* set empty — i.e., does chain-intersection semantics flag anything legitimate for a production tool server?
**Verdict:** **empty.** No doPrivileged-style amplification primitive is needed; the E-scoping is exact for this deputy, not merely defensible. (Decision memo: item-6 housekeeping, D1–D4.)
**NOTE:** this file was reconstructed from the audit session; diff any detail against `audit-output.txt`, which is ground truth.

## Bucket 1 — local/host effects (outside E: local disk and stderr are not protected resource space)

| Finding | Site | Notes |
|---|---|---|
| Runtime log file | `internal/ghmcp/server.go:280` | `O_CREATE\|O_APPEND`, 0600, opt-in via `LogFilePath` |
| HTTP-mode log file | `pkg/http/server.go:115` | same pattern |
| stderr logging | throughout | `log/slog` |
| Translations export | `pkg/translations/translations.go:61` | writes `github-mcp-server-config.json`, CLI-triggered (`--export-translations`) |
| Docs/test tooling | `generate_docs.go`, toolsnaps | dev tooling, **not the serving path** — excluded explicitly |

## Bucket 2 — auth plumbing (below E per the sub-effect principle, memo D1)

| Finding | Site | Notes |
|---|---|---|
| OAuth callback listener | `internal/oauth/callback.go:70` | local HTTP listener, interactive setup phase |
| Browser launch subprocess | `internal/oauth/env.go:40–47` | `xdg-open`/`open`/`rundll32`; `cmd.Stderr = io.Discard`; reaped via `go cmd.Wait()` |
| Background token refresh | `internal/oauth/manager.go:302` | goroutine; `manager.go:372` runs on `context.Background()` with `ReuseTokenSource` — genuinely detached from request contexts, consistent with plumbing-below-E |

## Bucket 3 — deputy-owned, request-turn candidates (the decider set) — ALL DISSOLVE

| Candidate | Site | Resolution |
|---|---|---|
| Per-tool-call fields telemetry | `pkg/github/fields_telemetry.go` (`recordFieldsUsage`) | **Not an effect locally**: the local server wires a **no-op metrics sink** (source comment); `pkg/observability/observability.go` injects `NewNoopMetrics` by default. Metric content is tool name + byte counts only — no payloads/identifiers. Hosted mode's `bytes_full`/`bytes_sent` counters are a response-size side channel: a concrete §9 influence-residue instance, noted, out of local scope |
| Lockdown permission cache reads | `pkg/lockdown` (`RepoAccessCache`; `queryRepoAccessInfo`, `checkPushAccess`, viewer login) | Mid-request, ambient-token, deputy-initiated — but **sub-effect implementation of the tool-level effect** (E is at tool-invocation granularity; note §2 / memo D1), like pagination or token refresh. Cache: cache2go, 5-min TTL; `lockdown.go:186` notes entries immutable because the table is **shared across instances**; tenant isolation via `WithCacheName` is by *convention*, with `TestRepoAccessCacheIsolatesViewerPerInstance` as the attacker/victim test — real-world evidence for the framework-assumption story. Cross-viewer cached-verdict filtering is influence, not authority: §9 residue |
| Network egress, serving path | grep over non-test Go source | **GitHub endpoints only** (`api.github.com`, `github.com` auth); `api.githubcopilot.com` appears only in docs tooling; zero third-party hosts; no otel/sentry/datadog/honeycomb in `go.mod` |

## Residuals (honest limits of this audit)

1. **Scope:** local server at one commit; hosted deployment (real metrics sink, GitHub-operated) not audited.
2. **Dependency I/O — CLOSED empirically.** First-party grep cannot see what dependencies do at runtime, so the claim was backed structurally only. `idle-egress-native.sh` now closes it: a binary built from the audited commit, run on the stdio transport with stdin held open and **zero tool calls**, opened **no network connections over 300 s** (per-process attribution via `lsof -i -a -p <pid>`, sampled every 5 s). Artifact: `idle-egress-capture.txt`.
   *Bounds of the claim:* 300 s window (a timer with a longer period would be missed); idle only (says nothing about behaviour under load); native build (the published Docker image is a different artifact); local mode only.
   *Separate observation, not egress:* the **build** fetches ~31 modules from the Go proxy. That is supply-chain surface inherited into the TCB, and it is a different question from whether the running binary phones home — recorded here so the two are not conflated.
3. `internal/profiler/profiler.go` appears slog-backed; runtime flag-gating unverified.
4. Single-reader audit (one person + one model); the file:line citations exist so it can be re-derived.

## What this feeds

The empty-bucket-3 verdict is the instantiation section's central evidence: *chain-intersection semantics flags nothing legitimate for a production tool server at the tool-effect level of abstraction* — the contrast case to history-based designs, which need Grant/Accept escapes (see `models/history_vs_chain.als`). The Housekeeping Deferral mechanism (memo D4) remains documented for deputies whose bucket 3 is nonempty; this one's is empty, so it is unused.