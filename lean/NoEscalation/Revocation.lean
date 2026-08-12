/-
NoEscalation / Revocation.lean — T4: revocation effectiveness.
Implements `decision-memo-t4-revocation.md` (D1–D4).

Three parts, of deliberately unequal depth:
  • T4a (channel)    — caretaker forwards lie within their issuance stamp.
                       NEAR-DEFINITIONAL, exactly as T1 was. Not the content.
  • T4b (sole route) — no non-caretaker performs an underlying-only effect.
                       Rests on alias-freedom; this is where the earlier
                       induction pays off.
  • T4 (effectiveness) — the conjunction, over traces, via the NoStaleLicense
                       invariant. Strong form (quiesced); the weak form the
                       note adopts is the same statement minus the quiescence
                       precondition, whose residual window is the declared
                       weak-revocation gap.

SCOPE: message- AND resolver-triggered turns. `invokeRes` fixes issuance at
the invoker's turn (resolver-issuance memo; C1/C2/C3), so caretaker-hosted
continuations are covered by the theorem rather than excluded. The former A6
scoping assumption is deleted.

STATUS: unelaborated draft; `-- CHECK:` marks suspected friction.
-/

import NoEscalation.Alias

namespace NoEscalation
namespace Revocation

universe u v
variable {E : Type u} {Comp : Type v}
variable (S : Alias.CareSystem E Comp)

/-! ### Filters only narrow (mirrors Warmups.Step_bound_antitone) -/

theorem Step_filter_antitone {cfg : Config E Comp} {ev cfg'}
    (hs : Step cfg ev cfg') :
    ∀ c, ESet.Sub (cfg'.filters c) (cfg.filters c) := by
  intro c
  cases hs
  case narrowFilter h => exact h c
  all_goals exact ESet.Sub.refl _

theorem MStep_filter_antitone {cfg ev cfg'}
    (hs : Guarded.MStep S.toSystem cfg ev cfg') :
    ∀ c, ESet.Sub (cfg'.filters c) (cfg.filters c) := by
  intro c
  cases hs with
  | untrusted hg _ => cases hg with
    | lift hstep _ => exact Step_filter_antitone hstep c
  | trusted hstep _ => exact Step_filter_antitone hstep c

/-! ### T4a — the channel clause (near-definitional; see memo D2) -/

/-- The caretaker's filtered-forwarding contract, as a condition on a step:
if the performer is a caretaker, the effect lies within the turn's issuance
stamp. (v1.1 §7; stated delta-style like `MembraneOK`, option B.) -/
def FilteredOK (cfg : Config E Comp) (ev : Option (Ev E Comp)) : Prop :=
  ∀ p π e, ev = some (Ev.eff p π e) → S.caretaker p → cfg.issued e

/-- **T4a.** Immediate from the contract. Recorded so the shape of T4 is
visible, and so that no reader mistakes it for the theorem. -/
theorem T4a_within_issuance {cfg : Config E Comp} {p π e}
    (hfilt : FilteredOK S cfg (some (Ev.eff p π e)))
    (hc : S.caretaker p) : cfg.issued e :=
  hfilt p π e rfl hc

/-! ### T4b — the sole-route clause (rests on alias-freedom) -/

/-- An effect is *underlying-only* when every capability denoting it is a
revocable (underlying) capability — i.e. the caretaker's resource is the sole
means of causing it. -/
def UnderlyingOnly (e : E) : Prop := ∀ k : Cap E, k.denotes e → S.underlying k

/-- **T4b.** Under alias-freedom, a non-caretaker cannot perform an
underlying-only effect at all: performing requires holding a denoting
capability, every such capability is underlying, and clause A of `AliasInv`
says non-caretakers hold none. -/
theorem T4b_sole_route {cfg : Config E Comp} {p π e cfg'}
    (hinv : Alias.AliasInv S cfg)
    (hu : UnderlyingOnly S e)
    (hnc : ¬ S.caretaker p)
    (hs : Step cfg (some (Ev.eff p π e)) cfg') : False := by
  cases hs with
  | perform hphase hcap =>
      obtain ⟨k, hstore, hden⟩ := hcap
      exact hinv.stores p k hnc hstore (hu k hden)
  -- CHECK: `perform` is the only constructor emitting `some _`; Lean should
  -- discharge the rest by index mismatch. If it complains, add
  -- `all_goals simp_all` or explicit `case … => cases ‹_ = _›`.

/-! ### The supporting invariant: no stale licenses -/

/-- Every in-flight message targeting a caretaker already carries a stamp
inside `F`. This is T4's analogue of `AliasInv`: the thing that must be true
of pending work for revocation to bite immediately. -/
def NoStaleLicense (F : ESet E) (cfg : Config E Comp) : Prop :=
  ∀ m : Msg E Comp, cfg.inflight m → S.caretaker m.target → ESet.Sub m.stamp F

/-- Filters staying inside `F` is itself preserved (antitonicity). -/
def FiltersIn (F : ESet E) (cfg : Config E Comp) : Prop :=
  ∀ c, S.caretaker c → ESet.Sub (cfg.filters c) F

theorem FiltersIn_preserved {F : ESet E} {cfg ev cfg'}
    (hs : Step cfg ev cfg') (h : FiltersIn S F cfg) : FiltersIn S F cfg' := by
  intro c hc
  exact ESet.Sub.trans (Step_filter_antitone hs c) (h c hc)

/--
Preservation of `NoStaleLicense`. The only constructor that can add a pending
message is `send`, and its stamp is the target's *current* filter, which
`FiltersIn` keeps inside `F`; every other constructor shrinks or preserves the
pending set.

The `send` case is the mathematical content and is left as the exercise, in
the same spirit as the `Alias` send-case: the scaffolding guarantees it is the
only thing outstanding.
-/
theorem NoStaleLicense_preserved {F : ESet E} {cfg ev cfg'}
    (hs : Step cfg ev cfg')
    (hfil : FiltersIn S F cfg)
    (h : NoStaleLicense S F cfg) : NoStaleLicense S F cfg' := by
  intro m hm hc
  cases hs with
  | startMsg _ _ => exact h m hm.1 hc
  | startRes _ _ _ => exact h m hm hc
  | invokeRes _ _ => exact h m hm hc
  | perform _ _  => exact h m hm hc
  | mkRes _ _ _  => exact h m hm hc
  | endTurn _    => exact h m hm hc
  | narrow _     => exact h m hm hc
  | narrowFilter _ => exact h m hm hc
  | send hphase hsender hctx hpay hstamp =>
      -- `hm : cfg.inflight m ∨ m = <the new message>`
      cases hm with
      | inl hold => exact h m hold hc
      | inr hnew =>
          subst hnew
          rw [hstamp]
          exact hfil _ hc
      -- CHECK: if `subst hnew` objects to the orientation, use
      --   `rw [hnew] at hc ⊢; rw [hstamp]; exact hfil _ hc`
  -- CHECK: if the anonymous-constructor cases mismatch (`hm` shape differs per
  -- constructor because `inflight` is updated differently), split with
  -- `cases hm with | inl … | inr …` inside the `send` branch only.

/-! ### The remaining conjuncts (surfaced by attempting the induction) -/

/--
The open turn's issuance stamp is inside `F` — **conditionally on the turn's
performer being a caretaker**. The condition is necessary: turns opened at
non-caretakers carry unconstrained stamps, and nothing needs them.

This conjunct was not in the memo. Attempting the induction produced it: T4a
gives `cfg.issued e`, and to conclude `F e` you need `issued ⊆ F`, which is a
property of *how the turn opened*, not of the performing step.
-/
def IssuedOK (F : ESet E) (cfg : Config E Comp) : Prop :=
  ∀ p π, cfg.phase = Phase.active p π → S.caretaker p → ESet.Sub cfg.issued F

/--
**Invoked stamps are inside F.** Replaces the old `NoCareRes` scoping
assumption (A6), which existed only because `startRes` used to stamp from the
resolver's *creation* turn — the rule C1 refuted.

With `invokeRes` fixing issuance at the invoker's turn, this is a genuine
invariant rather than a hypothesis: invocation stamps with the host's filter
as it stands then, and filters only narrow. Caretaker-hosted resolvers are
therefore fully in scope, and A6 is deleted.
-/
def InvokedOK (F : ESet E) (cfg : Config E Comp) : Prop :=
  ∀ r σ, cfg.invoked r σ → S.caretaker r.host → ESet.Sub σ F

/-- The full T4 invariant. -/
structure RevInv (F : ESet E) (cfg : Config E Comp) : Prop where
  alias  : Alias.AliasInv S cfg
  filt   : FiltersIn S F cfg
  stale  : NoStaleLicense S F cfg
  issued : IssuedOK S F cfg
  invk   : InvokedOK S F cfg

/-! ### T4 — effectiveness -/

/-- A trace respecting every trusted-component obligation in play. -/
inductive RevTrace (F : ESet E) :
    Config E Comp → List (Ev E Comp) → Config E Comp → Prop where
  | refl (cfg) : RevTrace F cfg [] cfg
  | step {cfg₁ ev cfg₂ tr cfg₃} :
      Guarded.MStep S.toSystem cfg₁ ev cfg₂ →
      Alias.MembraneOK S cfg₁ cfg₂ →
      FilteredOK S cfg₁ ev →
      RevTrace F cfg₂ tr cfg₃ →
      RevTrace F cfg₁ (ev.toList ++ tr) cfg₃

/--
Preservation of the bundle across one *unguarded* step (lifted below).
Three conjuncts are discharged elsewhere; `IssuedOK` and `InvokedOK` are here.

`IssuedOK`'s two opening cases are the content: a message-triggered turn gets
its stamp bounded by `NoStaleLicense`, a resolver-triggered turn by
`InvokedOK`. The second case is what `invokeRes` bought — before it, that case
was discharged by the A6 scoping assumption instead of by a proof.
-/
theorem RevInv_step {F : ESet E} {cfg ev cfg'}
    (hs : Step cfg ev cfg')
    (hmem : Alias.MembraneOK S cfg cfg')
    (h : RevInv S F cfg) : RevInv S F cfg' := by
  refine ⟨Alias.Step_alias_preserved S hs hmem h.alias,
          FiltersIn_preserved S hs h.filt,
          NoStaleLicense_preserved S hs h.filt h.stale,
          ?_, ?_⟩
  · -- IssuedOK
    intro p π hphase hc
    cases hs with
    | startMsg _ hin =>
        simp only [Phase.active.injEq] at hphase
        obtain ⟨hp, _⟩ := hphase
        subst hp
        exact h.stale _ hin hc
    | startRes _ _ hinvk =>
        -- issued = the stamp taken at INVOCATION; InvokedOK bounds it.
        simp only [Phase.active.injEq] at hphase
        obtain ⟨hp, _⟩ := hphase
        subst hp
        exact h.invk _ _ hinvk hc
    | invokeRes _ _ => exact h.issued p π hphase hc
    | perform _ _ => exact h.issued p π hphase hc
    | send _ _ _ _ _ => exact h.issued p π hphase hc
    | mkRes _ _ _ => exact h.issued p π hphase hc
    | endTurn _ =>
        have hcon : Phase.idle = Phase.active p π := hphase
        simp at hcon
    | narrow _ => exact h.issued p π hphase hc
    | narrowFilter _ => exact h.issued p π hphase hc
  · -- InvokedOK
    intro r σ hinvk hc
    cases hs with
    | invokeRes _ _ =>
        cases hinvk with
        | inl hold => exact h.invk r σ hold hc
        | inr hnew =>
            obtain ⟨hr, hσ⟩ := hnew
            subst hr; subst hσ
            exact h.filt _ hc
    | startRes _ _ _ => exact h.invk r σ hinvk.1 hc
    | startMsg _ _ => exact h.invk r σ hinvk hc
    | perform _ _ => exact h.invk r σ hinvk hc
    | send _ _ _ _ _ => exact h.invk r σ hinvk hc
    | mkRes _ _ _ => exact h.invk r σ hinvk hc
    | endTurn _ => exact h.invk r σ hinvk hc
    | narrow _ => exact h.invk r σ hinvk hc
    | narrowFilter _ => exact h.invk r σ hinvk hc

theorem RevInv_mstep {F : ESet E} {cfg ev cfg'}
    (hs : Guarded.MStep S.toSystem cfg ev cfg')
    (hmem : Alias.MembraneOK S cfg cfg')
    (h : RevInv S F cfg) : RevInv S F cfg' := by
  cases hs with
  | untrusted hg _ => cases hg with
    | lift hstep _ => exact RevInv_step S hstep hmem h
  | trusted hstep _ => exact RevInv_step S hstep hmem h

/-- The bundle survives a whole trace. -/
theorem RevInv_along {F : ESet E} {init : Config E Comp}
    (h : RevInv S F init) :
    ∀ tr cfg, RevTrace S F init tr cfg → RevInv S F cfg := by
  intro tr cfg hr
  induction hr with
  | refl _ => exact h
  | step hstep hmem _ _ ih => exact ih (RevInv_mstep S hstep hmem h)

/--
**T4 (revocation effectiveness, strong/quiesced form).**

Given at `init`: alias-freedom, caretaker filters inside `F`, no stale
licenses pending, the open turn's stamp inside `F`, and every already-invoked
resolver's stamp inside `F` — then along every membrane- and
filter-respecting trace, **no underlying-only effect outside `F` is ever
performed**.

No scoping assumption on resolvers: with `invokeRes` fixing issuance at the
invoker's turn, caretaker-hosted continuations are covered by the theorem
rather than excluded from it.

The proof is the case split the whole development was built for: a
non-caretaker performer is impossible by `T4b_sole_route` (alias-freedom), and
a caretaker performer lands inside `issued ⊆ F` by `T4a` and `IssuedOK`.

Weak form (what the note adopts): drop `NoStaleLicense` from the hypotheses
and the conclusion holds except for effects licensed by messages already in
flight when the filter narrowed. That residual window is weak revocation
working as designed, and belongs in the paper explicitly.
-/
theorem T4_effectiveness {F : ESet E} {init : Config E Comp}
    (h : RevInv S F init) :
    ∀ tr cfg, RevTrace S F init tr cfg →
      ∀ p π e cfg', FilteredOK S cfg (some (Ev.eff p π e)) →
        Step cfg (some (Ev.eff p π e)) cfg' →
        UnderlyingOnly S e → F e := by
  intro tr cfg hr p π e cfg' hfilt hs hu
  have hcfg : RevInv S F cfg := RevInv_along S h tr cfg hr
  by_cases hc : S.caretaker p
  · -- caretaker: T4a puts e in the stamp, IssuedOK puts the stamp in F
    have hiss : cfg.issued e := T4a_within_issuance S hfilt hc
    -- the performing step is in an open turn at p
    cases hs with
    | perform hphase _ => exact hcfg.issued p π hphase hc e hiss
  · -- non-caretaker: impossible
    exact absurd (T4b_sole_route S hcfg.alias hu hc hs) (by simp)
  -- CHECK: the `absurd` step turns `False` into anything; if Lean objects,
  -- `exact (T4b_sole_route S hcfg.alias hu hc hs).elim`.

/--
**T4 weak form (attempt).** The note adopts this: without quiescence
(`NoStaleLicense`), no underlying-only effect outside `F` is performed EXCEPT
those licensed by a message already in flight when the filter narrowed.

We state it as a disjunction: `F e ∨ StaleLicensed e`, where `StaleLicensed`
means some in-flight message at `cfg` carries a stamp admitting `e`. This is
the honest weak statement — the residual window is named in the conclusion,
not assumed away in the hypotheses.

EXPERIMENT: the `RevInv` bundle carries `NoStaleLicense`; here we drop it and
see how far the remaining conjuncts reach. Prediction: the non-caretaker case
still closes (alias-freedom is untouched), but the caretaker case needs the
disjunct because `IssuedOK` no longer has `NoStaleLicense` backing the stamp
of a turn opened from a stale message.
-/
def StaleLicensed (cfg : Config E Comp) (e : E) : Prop :=
  cfg.issuedHistory e

/-- **Weak issued-clause.** The open turn's stamp is inside `F` OR inside the
issuance history — the accumulated stamps of consumed caretaker messages.
Witnessing against history (not current inflight) is what makes this
preservable: `startMsg` moves a consumed message's stamp into `issuedHistory`,
so the disjunct keeps a witness after the message leaves the in-flight set. -/
def IssuedOKWeak (F : ESet E) (cfg : Config E Comp) : Prop :=
  ∀ p π, cfg.phase = .active p π → S.caretaker p →
    ESet.Sub cfg.issued F ∨ ESet.Sub cfg.issued cfg.issuedHistory

/-- The weak invariant: alias + filters + invoked as before; the issued clause
carries the history disjunct. `NoStaleLicense` is dropped. -/
structure RevInvWeak (F : ESet E) (cfg : Config E Comp) : Prop where
  alias  : Alias.AliasInv S cfg
  filt   : FiltersIn S F cfg
  issued : IssuedOKWeak S F cfg
  invk   : InvokedOK S F cfg

/-- Weak per-step conclusion: within `F`, or licensed by the issuance history. -/
theorem T4_weak {F : ESet E} {cfg : Config E Comp}
    (hinv : RevInvWeak S F cfg) :
    ∀ p π e cfg', FilteredOK S cfg (some (Ev.eff p π e)) →
      Step cfg (some (Ev.eff p π e)) cfg' →
      UnderlyingOnly S e → F e ∨ StaleLicensed cfg e := by
  intro p π e cfg' hfilt hs hu
  by_cases hc : S.caretaker p
  · have hiss : cfg.issued e := T4a_within_issuance S hfilt hc
    cases hs with
    | perform hphase _ =>
        rcases hinv.issued p π hphase hc with hF | hH
        · exact Or.inl (hF e hiss)
        · exact Or.inr (hH e hiss)
  · exact absurd (T4b_sole_route S hinv.alias hu hc hs) (by simp)

/-- **Weak preservation.** `RevInvWeak` survives every step. The `startMsg`
case — which broke the naive attempt because it consumes its witnessing
message — now closes: `startMsg` sets `issued := m.stamp` AND accumulates
`m.stamp` into `issuedHistory`, so the history disjunct is discharged by
`subset_union_right`. The field was designed to hold exactly what the consumed
message leaves behind. -/
theorem RevInvWeak_step {F : ESet E} {cfg ev cfg'}
    (hs : Step cfg ev cfg')
    (hmem : Alias.MembraneOK S cfg cfg')
    (h : RevInvWeak S F cfg) : RevInvWeak S F cfg' := by
  refine ⟨Alias.Step_alias_preserved S hs hmem h.alias,
          FiltersIn_preserved S hs h.filt, ?_, ?_⟩
  · -- IssuedOKWeak
    intro p π hphase hc
    cases hs with
    | startMsg hidle hin =>
        -- issued' = m.stamp, and issuedHistory' = old ∨ m.stamp. So issued' is
        -- a subset of issuedHistory' by the right injection: the history
        -- disjunct closes exactly because startMsg just recorded m.stamp.
        right
        intro e he
        exact Or.inr he
    | startRes _ _ hinvk =>
        simp only [Phase.active.injEq] at hphase
        obtain ⟨hp, _⟩ := hphase
        subst hp
        left
        intro e he
        exact h.invk _ _ hinvk hc e he
    | invokeRes _ _ => exact h.issued p π hphase hc
    | perform _ _ => exact h.issued p π hphase hc
    | send _ _ _ _ _ => exact h.issued p π hphase hc
    | mkRes _ _ _ => exact h.issued p π hphase hc
    | endTurn _ =>
        have hcon : Phase.idle = Phase.active p π := hphase
        simp at hcon
    | narrow _ => exact h.issued p π hphase hc
    | narrowFilter _ => exact h.issued p π hphase hc
  · -- InvokedOK (unchanged from strong proof)
    intro r σ hinvk hc
    cases hs with
    | invokeRes _ _ =>
        cases hinvk with
        | inl hold => exact h.invk r σ hold hc
        | inr hnew =>
            obtain ⟨hr, hσ⟩ := hnew
            subst hr; subst hσ
            exact h.filt _ hc
    | startRes _ _ _ => exact h.invk r σ hinvk.1 hc
    | startMsg _ _ => exact h.invk r σ hinvk hc
    | perform _ _ => exact h.invk r σ hinvk hc
    | send _ _ _ _ _ => exact h.invk r σ hinvk hc
    | mkRes _ _ _ => exact h.invk r σ hinvk hc
    | endTurn _ => exact h.invk r σ hinvk hc
    | narrow _ => exact h.invk r σ hinvk hc
    | narrowFilter _ => exact h.invk r σ hinvk hc

/-- Weak bundle survives a multi-step (mirrors `RevInv_mstep`). -/
theorem RevInvWeak_mstep {F : ESet E} {cfg ev cfg'}
    (hs : Guarded.MStep S.toSystem cfg ev cfg')
    (hmem : Alias.MembraneOK S cfg cfg')
    (h : RevInvWeak S F cfg) : RevInvWeak S F cfg' := by
  cases hs with
  | untrusted hg _ => cases hg with
    | lift hstep _ => exact RevInvWeak_step S hstep hmem h
  | trusted hstep _ => exact RevInvWeak_step S hstep hmem h

/-- The weak bundle survives a whole trace (mirrors `RevInv_along`). -/
theorem RevInvWeak_along {F : ESet E} {init : Config E Comp}
    (h : RevInvWeak S F init) :
    ∀ tr cfg, RevTrace S F init tr cfg → RevInvWeak S F cfg := by
  intro tr cfg hr
  induction hr with
  | refl _ => exact h
  | step hstep hmem _ _ ih => exact ih (RevInvWeak_mstep S hstep hmem h)

/--
**T4 weak form (trace theorem).** Given the weak invariant at `init` (no
quiescence), along every membrane- and filter-respecting trace, every
underlying-only effect is inside `F` OR licensed by the issuance history — the
accumulated stamps of consumed caretaker messages. Revocation is effective
except for effects whose license was already issued into history before the
narrowing; the residual is bounded by actually-issued licenses, never
arbitrary. (Broader than "in flight at narrow-time" — it is "ever issued into
history" — the price of a config-level invariant.)
-/
theorem T4_weak_trace {F : ESet E} {init : Config E Comp}
    (h : RevInvWeak S F init) :
    ∀ tr cfg, RevTrace S F init tr cfg →
      ∀ p π e cfg', FilteredOK S cfg (some (Ev.eff p π e)) →
        Step cfg (some (Ev.eff p π e)) cfg' →
        UnderlyingOnly S e → F e ∨ StaleLicensed cfg e := by
  intro tr cfg hr p π e cfg' hfilt hs hu
  exact T4_weak S (RevInvWeak_along S h tr cfg hr) p π e cfg' hfilt hs hu


end Revocation
end NoEscalation
