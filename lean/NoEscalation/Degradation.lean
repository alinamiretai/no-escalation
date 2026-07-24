/-
NoEscalation / Degradation.lean — A5 as a dial, not a cliff.

THE PROBLEM. A5 (mediation) says untrusted components have no actuators
outside the framework. Real deployments violate it routinely: an agent with a
shell, an interpreter, or a browser can cause effects the framework never
sees. Under the strict reading, the theorems simply do not apply to such a
system — which is true, useless, and the reason conformance verdicts read as
accusations.

THE MOVE. Let a system *declare* the set U of effects that escape mediation.
Untrusted components may cause effects in U without passing the guard.
Everything outside U still obeys effbound. So instead of "the theorem does not
apply," a deployment gets "the theorem applies to E \ U, and here is U."

WHY THIS IS HONEST AND NOT A WEAKENING. U is not a free parameter for
convenience: it must be *enumerated* (conformance R5), and every effect in it
is unprotected. Shrinking U is the security work. What the theorem provides is
the guarantee that shrinking U is the *only* thing that matters — nothing
outside U leaks because of something inside it.

T2 (full mediation) is the U = ∅ corollary at the bottom of this file.
-/

import NoEscalation.Guarded

namespace NoEscalation
namespace Degradation

universe u v
variable {E : Type u} {Comp : Type v}

/-- A system description that declares its unmediated surface. -/
structure USystem (E : Type u) (Comp : Type v) extends Guarded.System E Comp where
  /-- U: effects untrusted components can cause outside the framework.
  Must be enumerated, not assumed empty (conformance R5). -/
  unmediated : ESet E

variable (Sys : USystem E Comp)

/--
The deployed step relation, with three ways an effect can arise:
  • **mediated** — an untrusted component through the guard (the ideal case);
  • **unmediated** — an untrusted component through an actuator in U (shell,
    interpreter, socket): no guard, but the effect must lie in U;
  • **trusted** — a deputy under its contract, as before.
-/
inductive UStep : Config E Comp → Option (Ev E Comp) → Config E Comp → Prop where
  | mediated {cfg ev cfg'} :
      Guarded.GStep cfg ev cfg' →
      (∀ p π e, ev = some (Ev.eff p π e) → ¬ Sys.trusted p) →
      UStep cfg ev cfg'
  | unmediated {cfg ev cfg'} :
      Step cfg ev cfg' →
      (∀ p π e, ev = some (Ev.eff p π e) → ¬ Sys.trusted p ∧ Sys.unmediated e) →
      UStep cfg ev cfg'
  | trusted {cfg ev cfg'} :
      Step cfg ev cfg' →
      (∀ p π e, ev = some (Ev.eff p π e) →
        Sys.trusted p ∧ cfg.bound p e ∧ π.meet e) →
      UStep cfg ev cfg'

inductive UReaches : Config E Comp → List (Ev E Comp) → Config E Comp → Prop where
  | refl (cfg) : UReaches cfg [] cfg
  | step {cfg₁ ev cfg₂ tr cfg₃} :
      UStep Sys cfg₁ ev cfg₂ → UReaches cfg₂ tr cfg₃ →
      UReaches cfg₁ (ev.toList ++ tr) cfg₃

/--
**Per-step degradation.** Every effect outside U satisfies effbound, whichever
way it arose. Three cases: the guard supplies it, the contract supplies it, or
the effect is in U — contradicting the hypothesis.
-/
theorem UStep_guards_outside_U {cfg : Config E Comp} {p π e cfg'}
    (hs : UStep Sys cfg (some (Ev.eff p π e)) cfg')
    (hu : ¬ Sys.unmediated e) : cfg.bound p e ∧ π.meet e := by
  cases hs with
  | mediated hg _ =>
      cases hg with
      | lift _ hguard => exact hguard p π e rfl
  | unmediated _ hun => exact absurd (hun p π e rfl).2 hu
  | trusted _ hc => exact (hc p π e rfl).2

/-- **NE modulo U**: the property, restricted to the mediated surface. -/
def UNE (init : Config E Comp) : Prop :=
  ∀ tr cfg, UReaches Sys init tr cfg →
    ∀ p π e cfg', UStep Sys cfg (some (Ev.eff p π e)) cfg' →
      ¬ Sys.unmediated e → cfg.bound p e ∧ π.meet e

/--
**T2-modulo-U (graceful degradation).** Composition survives partial
mediation: no induction, no initial conditions, exactly as in the fully
mediated case — because effbound is still turn-local. Losing mediation costs
you U and nothing else.
-/
theorem T2_modulo_U (init : Config E Comp) : UNE Sys init := by
  intro _ _ _ p π e cfg' hs hu
  exact UStep_guards_outside_U Sys hs hu

/--
**Full mediation is the U = ∅ corollary.** When nothing escapes, `¬ U e` holds
for every effect and the guarantee is unconditional — recovering T2.
-/
theorem T2_of_empty_U {Sys₀ : Guarded.System E Comp} (init : Config E Comp) :
    ∀ tr cfg, UReaches ⟨Sys₀, fun _ => False⟩ init tr cfg →
      ∀ p π e cfg', UStep ⟨Sys₀, fun _ => False⟩ cfg (some (Ev.eff p π e)) cfg' →
        cfg.bound p e ∧ π.meet e := by
  intro tr cfg hr p π e cfg' hs
  exact T2_modulo_U _ init tr cfg hr p π e cfg' hs (fun h => h)
  -- CHECK: `⟨Sys₀, fun _ => False⟩` builds a USystem from a System by
  -- declaring U empty; if anonymous-constructor inference balks, name it:
  --   `let S₀ : USystem E Comp := { toSystem := Sys₀, unmediated := fun _ => False }`

end Degradation
end NoEscalation
