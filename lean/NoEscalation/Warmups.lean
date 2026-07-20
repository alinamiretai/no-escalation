/-
NoEscalation / Warmups.lean — two banked theorems ahead of the T4 development.

  • T3 core (chain conferral): meet π ⊆ β for every hop (C, β) in π, and the
    consequent effbound ⊆ every attached bound. Induction over Ctx.
  • bound antitonicity along MReaches: bounds only narrow, so any reachable
    configuration's bound ⊆ the start's. Induction over MReaches.
  • mixed-system NES (a state view): combining T2 with antitonicity, at every
    reachable configuration every emitted effect stays within the START bound
    too — the property is stable under the whole run, not just per step.

STATUS: unelaborated draft; `-- CHECK:` marks suspected friction.
-/

import NoEscalation.Guarded

namespace NoEscalation
namespace Warmups

universe u v
variable {E : Type u} {Comp : Type v}

/-! ### T3 core: chain conferral -/

/-- The attached bound at a specific hop. `HopBound π C β` means π contains a
hop whose extender is `C` with attached bound `β` (or `C` is the root with
root bound `β`). -/
inductive HopBound : Ctx E Comp → Comp → ESet E → Prop where
  | root (x β)          : HopBound (.root x β) x β
  | here (p x β)        : HopBound (.hop p x β) x β
  | there {p x β C γ}   : HopBound p C γ → HopBound (.hop p x β) C γ

/-- **T3 core.** The running meet is contained in every attached bound along
the chain. Induction over the context. -/
theorem meet_sub_hop :
    ∀ (π : Ctx E Comp) (C : Comp) (β : ESet E),
      HopBound π C β → ESet.Sub π.meet β
  | .root _ _, _, _, .root _ _ => ESet.Sub.refl _
  | .hop _ _ _, _, _, .here _ _ _ => fun _ he => he.2
  | .hop p _ _, C, γ, .there h   => fun e he => meet_sub_hop p C γ h e he.1

/-- Consequence: if an effect is within a context's meet, it is within every
attached bound along that context. Directly usable wherever T3 is invoked. -/
theorem effbound_sub_hop {π : Ctx E Comp} {C : Comp} {β : ESet E} {e : E}
    (h : HopBound π C β) (hin : π.meet e) : β e :=
  meet_sub_hop π C β h e hin

/-! ### Bound antitonicity along reachability -/

variable (Sys : Guarded.System E Comp)

/-- Single-step antitonicity at the *unguarded* level: only `narrow` touches
`bound`, and it narrows by hypothesis. Proving this separately avoids nested
`cases` on `MStep`/`GStep`/`Step` at once. -/
theorem Step_bound_antitone {cfg : Config E Comp} {ev cfg'}
    (hs : Step cfg ev cfg') :
    ∀ c, ESet.Sub (cfg'.bound c) (cfg.bound c) := by
  intro c
  cases hs
  case narrow h => exact h c
  all_goals exact ESet.Sub.refl _
  -- CHECK: non-narrow constructors leave `bound` untouched, so the structure
  -- update reduces definitionally and `refl` closes them.

/-- A single mixed step never widens any component's bound. -/
theorem MStep_bound_antitone {cfg ev cfg'} (hs : Guarded.MStep Sys cfg ev cfg') :
    ∀ c, ESet.Sub (cfg'.bound c) (cfg.bound c) := by
  intro c
  cases hs with
  | untrusted hg _ =>
      cases hg with
      | lift hstep _ => exact Step_bound_antitone hstep c
  | trusted hstep _ => exact Step_bound_antitone hstep c

/-- Bounds only narrow along a whole reachable trace. -/
theorem MReaches_bound_antitone {cfg tr cfg'}
    (hr : Guarded.MReaches Sys cfg tr cfg') :
    ∀ c, ESet.Sub (cfg'.bound c) (cfg.bound c) := by
  induction hr with
  | refl _ => intro c; exact ESet.Sub.refl _
  | step hstep _ ih =>
      intro c
      exact ESet.Sub.trans (ih c) (MStep_bound_antitone Sys hstep c)
  -- CHECK: transitivity order — (cfg'' ⊆ cfg') then (cfg' ⊆ cfg). ih gives
  -- the tail (cfg'' ⊆ cfg' side), MStep gives the head. If flipped, swap args.

/-! ### Mixed-system NES (state view) -/

/-- **Mixed-system NES.** At every reachable configuration, an emitted effect
lies within its performer's bound *as it was at the start of the run* — not
merely the current bound. Combines T2 (per-step effbound) with antitonicity.
This is the state-level companion the note (§5) keeps distinct from NE. -/
theorem mixed_NES {init : Config E Comp} :
    ∀ tr cfg, Guarded.MReaches Sys init tr cfg →
      ∀ p π e cfg', Guarded.MStep Sys cfg (some (Ev.eff p π e)) cfg' →
        init.bound p e := by
  intro tr cfg hr p π e cfg' hs
  have hnow : cfg.bound p e ∧ π.meet e := Guarded.MStep_guards Sys hs
  exact (MReaches_bound_antitone Sys hr p) e hnow.1
  -- CHECK: `MStep_guards` returns `cfg.bound p e ∧ π.meet e`; we take .1 and
  -- push it back along antitonicity to the initial bound.

end Warmups
end NoEscalation
