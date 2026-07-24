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

SCOPE (memo D3): message-triggered turns only. `startRes` currently stamps
from the resolver's CREATION turn — the rule C1 refuted — so resolver-induced
turns are excluded by hypothesis. The `invokeRes` extension is the follow-on.

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
  | startRes _ _ => exact h m hm hc
  | perform _ _  => exact h m hm hc
  | mkRes _ _ _  => exact h m hm hc
  | endTurn _    => exact h m hm hc
  | narrow _     => exact h m hm hc
  | narrowFilter _ => exact h m hm hc
  | send hphase hsender hctx hpay hstamp =>
      -- `hm : cfg.inflight m ∨ m = m✝`; the left disjunct is `h`, the right
      -- needs `hstamp` (stamp = current filter) plus `hfil` (filter ⊆ F).
      sorry
  -- CHECK: if the anonymous-constructor cases mismatch (`hm` shape differs per
  -- constructor because `inflight` is updated differently), split with
  -- `cases hm with | inl … | inr …` inside the `send` branch only.

/-! ### T4 — effectiveness -/

/-- A trace respecting both trusted-component contracts in play. -/
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
**T4 (revocation effectiveness, strong/quiesced form).**

If at `cfg` alias-freedom holds, the caretaker filters are inside `F`, and no
stale licenses are pending, then along every membrane- and filter-respecting
trace, no effect outside `F` is ever performed.

Proof shape: induct along `RevTrace`, carrying the conjunction
`AliasInv ∧ FiltersIn ∧ NoStaleLicense`; at an emitting step, split on whether
the performer is a caretaker — non-caretaker is impossible by T4b, caretaker
lands inside `issued`, and `issued` came from a stamp that `NoStaleLicense`
puts inside `F`.

The last link (turn-opening carries the stamp into `cfg.issued`) is the one
piece not yet stated as a lemma; it is the message-triggered analogue of the
resolver gap in D3, and is the first thing to write next.
-/
theorem T4_effectiveness {F : ESet E} {init : Config E Comp}
    (hinv : Alias.AliasInv S init)
    (hfil : FiltersIn S F init)
    (hstale : NoStaleLicense S F init) :
    ∀ tr cfg, RevTrace S F init tr cfg →
      ∀ p π e cfg', Guarded.MStep S.toSystem cfg (some (Ev.eff p π e)) cfg' →
        UnderlyingOnly S e → F e := by
  sorry

end Revocation
end NoEscalation
