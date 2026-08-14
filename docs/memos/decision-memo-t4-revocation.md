# Decision Memo: T4 Revocation Effectiveness — Filters, Issuance, and the Statement

**Status:** proposed. Last mathematics gating the workshop paper.
**Trigger:** v1.1 §8 states T4 in prose, but filters and issuance are absent from the Lean `Config`, so "after the filter narrows to F, no out-of-filter effect with issuance after the narrowing" is currently unstatable. This memo puts them in the state and fixes the statement before any proof is attempted (freeze discipline).

## Decisions

**D1 — Filters enter `Config` as a component-indexed map, narrowing-only.**
`filters : Comp → ESet E`, with a `narrowFilter` step mirroring `narrow` for bounds. Non-caretakers' filters are unconstrained and unused. Rationale: exact mirror of the bound machinery, so `Step_bound_antitone`'s proof pattern transfers verbatim to filters.

**D2 — Issuance is materialized as a *stamp* carried on the triggering artifact, not as a global clock.**
A message records the target's filter as of its send (`m.stamp = cfg.filters m.target`); the configuration records the current turn's stamp (`cfg.issued`), set when the turn opens. Rationale: (a) it is the *local* form — everything the check needs rides with the trigger, the same principle that made effbound turn-local and T2 trivial, so the design is coherent rather than convenient; (b) it avoids a global step counter and arithmetic reasoning; (c) it instantiates the resolver-issuance memo's rule ("issuance = the turn of the triggering action") without needing to name or order turns.

**Honest consequence, stated loudly:** T4a below becomes near-definitional, exactly as T1 did. **The content of T4 is not in T4a.** It is in the conjunction with alias-freedom (T4b) and the no-stale-license invariant. Anyone who reads only T4a should conclude the mechanism was assumed, and they would be right; the theorem is that mechanism *plus* structural confinement yields the guarantee, and the induction lives in the confinement.

**D3 — Resolver-triggered turns are scoped OUT of this round, explicitly.**
`startRes` currently stamps from the resolver's creation turn — which is **creation-turn licensing, refuted by C1** (`resolver_issuance.als`). Implementing the adopted invoker-turn rule requires an explicit `invokeRes` step (three-phase resolver lifecycle: create / invoke / resume, matching `noescalation_v4.als`). T4 is therefore stated over **message-triggered turns only**, with the resolver extension named as the immediate follow-on. This is scoping, not an oversight: the rule is already decided and Alloy-validated; only its Lean encoding is deferred.

**D4 — T4's statement, in three parts.**

- **T4a (channel).** Every effect performed by a caretaker lies within its trigger's issuance stamp. *Contract; near-definitional.*
- **T4b (sole route).** No non-caretaker performs an *underlying-only* effect — one denoted solely by revocable capabilities. *Needs alias-freedom plus the `perform` precondition; this is where the earlier induction pays off.*
- **T4 (effectiveness).** Given, at configuration `cfg`: alias-freedom, `filters R ⊆ F`, and **no stale licenses** (every in-flight message targeting R already carries `stamp ⊆ F`), then along every reachable membrane- and filter-respecting trace, **no effect outside F is ever performed**. The supporting invariant `NoStaleLicense` is preserved because new sends stamp with the current filter, which antitonicity keeps inside F.

**Weak vs. strong, made explicit.** The quiesced form above is *strong* revocation, bought by the `NoStaleLicense` precondition. Dropping that precondition gives the weak form the note actually adopts: the only effects outside F are those licensed by messages already in flight when the filter narrowed. That residual window is weak revocation working as designed and **must be stated in the paper, not discovered by a reviewer**.

## Consequences for the development

- `Config` gains `filters` and `issued`; `Msg` gains `stamp`; `Res` gains `stamp`.
- `Step` gains `narrowFilter`; `startMsg`/`startRes` set `issued`; `send` constrains `m.stamp`.
- `Alias.Step_alias_preserved` needs one new case (`narrowFilter` touches neither stores nor payloads — trivial). Price of D1, paid once.
- `Warmups.Step_bound_antitone` absorbs the new constructor via its `all_goals` fallback (it does not touch `bound`).
- Existing `{cfg with …}` updates propagate the new fields unchanged, which is the correct behaviour for every other constructor.

## Honest residuals

1. **Resolver case deferred (D3), and currently encoded with the *refuted* rule.** The `startRes` stamp is creation-time; T4 excludes such turns by hypothesis. Do not let this quietly become the shipped semantics — the `invokeRes` extension is the named next task.
2. **Stamps are attached to all messages**, vacuously for non-caretaker targets. Inelegant (`Option` would be cleaner); not worth the proof friction now.
3. **The weak window is unbounded in size.** Nothing here bounds how many pre-narrowing triggers are in flight. Bounding it needs a quiescence or liveness assumption — out of scope, and to be named as such rather than glossed.
4. **Model-check before proving.** The Alloy suite covers the issuance discriminator (C1–C3) but *not* the sole-route conjunction (T4b). An Alloy check that a non-caretaker cannot perform the underlying effect under `AliasInv` is cheap insurance before spending Lean time — the standing loop, applied to the last theorem.
