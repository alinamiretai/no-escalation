/-
NoEscalation / CareSanity.lean — A3 is satisfiable.

WHY THIS FILE EXISTS. T4 is conditional on caretakers discharging three
obligations at once: Guard (effbound), Membrane (never emit the underlying
reference), and filtered forwarding (only within the issuance stamp). Nothing
in the development rules out those three being *jointly unsatisfiable for any
caretaker that does useful work* — and if they were, T4 would be vacuously
true precisely where it is supposed to bite. A theorem whose hypotheses can
only be met by a component that never forwards anything is not a theorem about
revocation.

Alloy witnesses this at scope 5 (`alias_v11.als`, `AV_Live` SAT). This file is
the unbounded counterpart: an explicit caretaker that satisfies all three
contracts AND performs the resource effect, with the T4 invariant holding.

This is the `Sanity.lean` discipline applied to the trusted side. Sanity.lean
showed NE is refutable (the property can fail); this shows the contracts are
livable (the hypotheses can hold non-trivially). Both are needed before either
theorem means anything.
-/

import NoEscalation.Revocation

namespace NoEscalation
namespace CareSanity

/-- One effect: the revocable resource operation. -/
inductive Ef where
  | res
  deriving DecidableEq

/-- A principal (untrusted) and a caretaker (trusted). -/
inductive Cp where
  | prin
  | care
  deriving DecidableEq

/-- The underlying, revocable capability. -/
def capU : Cap Ef := ⟨fun _ => True⟩

def S : Alias.CareSystem Ef Cp where
  trusted    := fun c => c = Cp.care
  caretaker  := fun c => c = Cp.care
  underlying := fun k => k = capU
  care_trusted := fun _ h => h

/-- The principal confers everything it has; the question here is whether the
*contracts* are satisfiable, not whether attenuation works (that is T3). -/
def π₀ : Ctx Ef Cp := .root Cp.prin (fun _ => True)

def m₀ : Msg Ef Cp :=
  { sender := .prin, target := .care, ctx := π₀,
    payload := fun _ => False,          -- Membrane: no reference travels
    stamp   := fun _ => True }          -- filter open at issuance

/-- Caretaker holds the underlying capability; nobody else holds anything. -/
def init : Config Ef Cp :=
  { store    := fun c k => c = Cp.care ∧ k = capU
    bound    := fun _ _ => True
    inflight := fun m => m = m₀
    live     := fun _ => False
    phase    := .idle
    filters  := fun _ _ => True
    issued   := fun _ => True
    invoked  := fun _ _ => False }

/-- The caretaker's turn, opened from the pending request. -/
def cfg₁ : Config Ef Cp :=
  { init with
    phase    := .active Cp.care π₀
    issued   := m₀.stamp
    inflight := fun m => init.inflight m ∧ m ≠ m₀
    store    := fun c k => init.store c k ∨ (c = m₀.target ∧ m₀.payload k) }

theorem opens : Step init none cfg₁ := Step.startMsg rfl rfl

/-- The caretaker forwards: it performs the resource effect. `perform` leaves
the configuration unchanged, so the post-state is `cfg₁` again. -/
theorem forwards : Step cfg₁ (some (Ev.eff Cp.care π₀ Ef.res)) cfg₁ :=
  Step.perform rfl ⟨capU, Or.inl ⟨rfl, rfl⟩, trivial⟩

/-! ### All three contracts hold at that step -/

theorem guard_holds : cfg₁.bound Cp.care Ef.res ∧ π₀.meet Ef.res :=
  ⟨trivial, trivial⟩

theorem membrane_holds : Alias.MembraneOK S cfg₁ cfg₁ := by
  intro m hnot hyes _ _ _
  exact absurd hyes hnot

theorem filter_holds :
    Revocation.FilteredOK S cfg₁ (some (Ev.eff Cp.care π₀ Ef.res)) := by
  intro _ _ _ _ _
  trivial

/-! ### And the T4 invariant holds there -/

theorem alias_holds : Alias.AliasInv S cfg₁ := by
  constructor
  · -- stores: only the caretaker holds anything, and it IS a caretaker
    intro C k hC hstore
    cases hstore with
    | inl hold => exact absurd hold.1 hC
    | inr hnew => exact hnew.2.elim
  · -- inflight: the pending set is empty after the message is consumed
    intro m k hm _
    exact absurd hm.1 hm.2

theorem revinv_holds : Revocation.RevInv S (fun _ => True) cfg₁ := by
  refine ⟨alias_holds, ?_, ?_, ?_, ?_⟩
  · intro _ _ _ _; trivial
  · intro m hm _; exact absurd hm.1 hm.2
  · intro _ _ _ _ _ _; trivial
  · intro _ _ hinvk _; exact hinvk.elim

/--
**A3 is satisfiable.** There is a caretaker that discharges Guard, Membrane
and filtered forwarding *simultaneously*, under the T4 invariant, **and still
performs the resource effect**. T4 is therefore not vacuous for caretakers.
-/
theorem contracts_livable :
    Revocation.RevInv S (fun _ => True) cfg₁ ∧
    S.caretaker Cp.care ∧
    Step cfg₁ (some (Ev.eff Cp.care π₀ Ef.res)) cfg₁ ∧
    Revocation.FilteredOK S cfg₁ (some (Ev.eff Cp.care π₀ Ef.res)) ∧
    Alias.MembraneOK S cfg₁ cfg₁ ∧
    (cfg₁.bound Cp.care Ef.res ∧ π₀.meet Ef.res) :=
  ⟨revinv_holds, rfl, forwards, filter_holds, membrane_holds, guard_holds⟩

end CareSanity
end NoEscalation
