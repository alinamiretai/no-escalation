# Decision Memo: Issuance Semantics for Resolver-Induced Caretaker Turns

**Status:** proposed; last open item gating the v1.1 freeze. Companion to `decision-memo-restatement-v1.1.md`.
**Trigger:** encoding variant B (`noescalation_v4.als`, `ResolverSetup`) exposed that v1.0 §6's weak-revocation rule is **undefined** for caretaker turns induced by a captured continuation. "Licensed at issuance" was operationalized as `inducingMsg.originTurn`; a resolver-induced turn has no inducing message. Consequence: `ForwardFiltered` is vacuous on such turns — the filter is never consulted when a caretaker resumes through a continuation. NE survives (Guard is unconditional on trusted performers, per the v1.1 repair), but **T4 (revocation effectiveness) does not currently have a well-defined statement.**

## The question

A caretaker's turn can be triggered two ways: by a message send, or by invocation of a resolver it created. For the second, which turn's filter licenses the forward?

- **(i) Creation turn** — the turn in which the caretaker created the resolver.
- **(ii) Invoker turn** — the turn in which the resolver was invoked. **[ADOPTED]**
- **(iii) Resume turn** — the turn in which the effect is performed.

## Decision: (ii), the invoker's turn

**Principle.** Issuance is *the turn of the triggering action*, uniformly: a send at turn t_o licenses the induced caretaker turn at t_o; a resolver invocation at turn t_inv licenses the induced caretaker turn at t_inv. One rule for both trigger kinds, not two. The in-flight window (trigger → execution) is identical in both cases, preserving the weak-revocation choice of v1.0 §6 without special-casing continuations.

**Why (i) is refuted, not merely disfavoured.** Weak revocation exists because work already in the pipe cannot be killed atomically. A captured resolver held across a revocation boundary is not in-flight work — it is a *stored capability to continue*, and the holder controls when it is cashed. Under (i), an untrusted grantee induces the caretaker to create a continuation while the filter is open, retains it, and invokes it after revocation; the caretaker forwards on a stale license. **This is Benchmark 3 (stale capability defeats revocation) reproduced at the continuation level** — the very attack that made alias-freedom a *structural* invariant rather than a runtime check (v1.0 §6, Q3). Admitting it via continuations would silently undo that decision.

**Why not (iii).** It blocks the bypass but is strong revocation, inconsistent with the weak semantics chosen for message-triggered forwards, and unnecessary once (ii) closes the capture window. Retain (iii) in the paper as the *strong-revocation variant* for readers who want it; the framework supports either, and the theorem statement is parametric in the choice.

## Consequent changes

1. **§6 (v1.1):** define `issuance(t)` for a caretaker turn `t` as: `t.inducingMsg.originTurn` if message-triggered; `t.invoker` (the turn invoking the inducing resolver) if resolver-triggered. Weak revocation quantifies over `issuance(t)` uniformly.
2. **§7 (v1.1):** `ForwardFiltered` loses its `some inducingMsg` guard and applies to both trigger kinds — closing the vacuity gap.
3. **T4 statement:** "after the filter narrows to F at step k, no effect outside F is performed by the caretaker with `issuance ≥ k`" — now well-defined for both trigger kinds.
4. **Model:** restore an explicit `invokesRes` relation on Turn (present in v3, simplified away in v4's `ResRule`), so the invoker turn is nameable.

## Discriminating checks (to run before freeze)

Scenario **CaptureBeforeRevoke**: t1 G services P's request; t2 R's turn (filter ∋ ResEff) — R creates resolver k; t3 an untrusted party invokes k, but the filter has **already narrowed** (ResEff ∉ filtAt[R, t3]); t4 R resumes via k and may perform.

- **C1** — under (i) creation-turn licensing: the post-revocation forward is **SAT** ⇒ exhibits the bypass. *This instance is the memo's evidence and a paper figure: "continuation capture defeats revocation under creation-turn issuance."*
- **C2** — under (ii) invoker-turn licensing: the same scenario is **UNSAT** (no such forward) ⇒ bypass closed.
- **C3** — non-vacuity witness: under (ii), a resolver-triggered forward *whose invocation precedes narrowing* is **SAT** and clean ⇒ (ii) does not over-block legitimate resumed work.

Standing rules apply: C2's UNSAT is meaningful **only** because C3 witnesses that the contract admits resolver-triggered forwards at all.

## Honest residuals

1. (ii) leaves a genuine window: an invocation issued just before narrowing completes after it. That is weak revocation working as designed, not a hole — but the paper must state the window explicitly rather than let a reviewer discover it.
2. The uniformity argument is mine and has the shape of the totality claims this project has repeatedly falsified (ledger: three). C1–C3 are the check; do not freeze on the argument alone.
3. Interaction with alias-freedom is unexamined: a resolver is not a *reference to the underlying resource*, so the Membrane invariant should be unaffected — verify, do not assume.
