/-
NoEscalation / Kernel.lean — pure kernel: effects, contexts, meet, attribution.
Transcribes property-note v1.0 §2–§4 (frozen 2026-07; Alloy suite green).
Mathlib-free by design: sets are predicates, subset is pointwise implication.
Q1 (structured effects) is resolved here by parametricity: E and Comp are
arbitrary types; instantiations may use pairs (op, arg) etc.

STATUS: written without elaboration (no toolchain in the drafting
environment). Expect a debugging pass; suspected friction points are marked
`-- CHECK:`.
-/

namespace NoEscalation

universe u v

/-- Sets of effects, Mathlib-free. -/
abbrev ESet (E : Type u) : Type u := E → Prop

namespace ESet

variable {E : Type u}

/-- Pointwise subset. -/
def Sub (s t : ESet E) : Prop := ∀ e, s e → t e

def inter (s t : ESet E) : ESet E := fun e => s e ∧ t e

theorem Sub.refl (s : ESet E) : Sub s s := fun _ h => h

theorem Sub.trans {s t u : ESet E} (h₁ : Sub s t) (h₂ : Sub t u) : Sub s u :=
  fun e hs => h₂ e (h₁ e hs)

theorem inter_sub_left (s t : ESet E) : Sub (inter s t) s := fun _ h => h.1
theorem inter_sub_right (s t : ESet E) : Sub (inter s t) t := fun _ h => h.2

end ESet

/--
Provenance context (v1.0 §2, rules 1–5): a nonempty chain of
(extender, attached bound) pairs. `root` is a designated root context;
`hop` extends a parent at a send/spawn.
-/
inductive Ctx (E : Type u) (Comp : Type v) : Type (max u v) where
  | root (extender : Comp) (β : ESet E)
  | hop  (parent : Ctx E Comp) (extender : Comp) (β : ESet E)

namespace Ctx

variable {E : Type u} {Comp : Type v}

/-- Running meet of attached bounds along the chain (v1.0 §4). -/
def meet : Ctx E Comp → ESet E
  | .root _ β   => β
  | .hop p _ β  => fun e => meet p e ∧ β e

/-- Authority-provenance attribution (v1.0 §4): the components on the chain.
Note the reading fixed by the D5 memo: this is whose CONFERRAL licenses an
effect, not who causally influenced it. -/
def attrib : Ctx E Comp → Comp → Prop
  | .root x _,  c => c = x
  | .hop p x _, c => attrib p c ∨ c = x

/-- The extender of the last hop is always attributed. -/
theorem attrib_extender : ∀ (π : Ctx E Comp),
    attrib π (match π with | .root x _ => x | .hop _ x _ => x)
  | .root _ _   => rfl
  | .hop _ _ _  => Or.inr rfl

/-- Meets only narrow along hops (chain-monotonicity; v1.0 §4). -/
theorem meet_hop_sub (p : Ctx E Comp) (x : Comp) (β : ESet E) :
    ESet.Sub (Ctx.hop p x β).meet p.meet :=
  fun _ h => h.1

/--
Checklist item 10, one-step form (mirrors Alloy `WiderBetaHarmless`):
attaching a bound that contains the parent meet leaves the meet unchanged.
The trace-level generalization (verdict invariance under widening anywhere)
follows by induction over `Ctx` and is a phase-two lemma.
-/
theorem widerBeta_harmless {p : Ctx E Comp} {β : ESet E}
    (h : ESet.Sub p.meet β) (x : Comp) (e : E) :
    (Ctx.hop p x β).meet e ↔ p.meet e :=
  ⟨fun he => he.1, fun he => ⟨he, h e he⟩⟩

end Ctx

end NoEscalation
