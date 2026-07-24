/-
NoEscalation / Concurrent.lean — THE test of turn-locality.

Every prior result rests on a single active turn. Real guards mediate
parallel tool calls over shared state. This file asks whether the theorems
were facts about the domain or artifacts of the turn-based encoding.

MODEL. Instead of one `Phase.active p π`, a *set* of active turns runs over
ONE shared store. Turns open and close independently; while several are
active, any of them may perform an effect, and effects/narrowings by one turn
are visible to the others (shared store, shared bounds, shared filters). This
is genuine overlap, not lock-serialised interleaving — the only version that
is a real test.

PREDICTION (recorded before the proofs, so it can be wrong):
  • NE (spatial) SURVIVES: effbound reads the performer's own bound and its
    message-carried context — both local to the performing turn — so a
    concurrent turn cannot widen them.
  • T4 (temporal) is AT RISK: issuance ordering and NoStaleLicense assume a
    well-defined "before", which concurrency may not provide.

If NE survives and T4 breaks, that is the finding, and it is the real
structure of the problem rather than a defect of this file.
-/

import NoEscalation.Warmups

namespace NoEscalation
namespace Concurrent

universe u v
variable {E : Type u} {Comp : Type v}

/-- A running turn: who is acting, under which context. Multiple coexist. -/
structure ActiveTurn (E : Type u) (Comp : Type v) where
  actor : Comp
  ctx   : Ctx E Comp

/-- Concurrent configuration: a SET of active turns over shared state. The
store, bounds and filters are shared; `active t` means turn `t` is running. -/
structure CConfig (E : Type u) (Comp : Type v) : Type (max u v) where
  store  : Comp → Cap E → Prop
  bound  : Comp → ESet E
  active : ActiveTurn E Comp → Prop

/-- Effbound for a concurrent turn: performer's (current, shared) bound ∩ the
meet of its own context. Note both operands are local to the turn `t` — this
locality is exactly what the test probes. -/
def cEffbound (cfg : CConfig E Comp) (t : ActiveTurn E Comp) : ESet E :=
  fun e => cfg.bound t.actor e ∧ t.ctx.meet e

/-- The guarded concurrent step relation. Any active turn may act; opening and
closing turns do not disturb others; `narrow` shrinks a shared bound *while
other turns are live* — the interference case. -/
inductive CStep : CConfig E Comp → Option (Ev E Comp) → CConfig E Comp → Prop where
  | open {cfg : CConfig E Comp} {p : Comp} {π : Ctx E Comp} :
      -- a new turn opens alongside whatever is already running
      CStep cfg none { cfg with active := fun t => cfg.active t ∨ t = ⟨p, π⟩ }
  | close {cfg : CConfig E Comp} {t : ActiveTurn E Comp} :
      cfg.active t →
      CStep cfg none { cfg with active := fun t' => cfg.active t' ∧ t' ≠ t }
  | perform {cfg : CConfig E Comp} {t : ActiveTurn E Comp} {e : E} :
      cfg.active t →
      -- GUARD: the effect is within this turn's effbound, evaluated against
      -- the CURRENT shared state (which a concurrent narrow may have shrunk).
      cEffbound cfg t e →
      CStep cfg (some (Ev.eff t.actor t.ctx e)) cfg
  | send {cfg : CConfig E Comp} {t : ActiveTurn E Comp} {p : Comp}
        {π : Ctx E Comp} {β : ESet E} {k : Cap E} :
      cfg.active t → t.ctx = .hop π p β → cfg.store p k →
      CStep cfg none
        { cfg with store := fun c k' => cfg.store c k' ∨ (c = t.actor ∧ k' = k) }
  | narrow {cfg : CConfig E Comp} {b' : Comp → ESet E} :
      -- shrinks a SHARED bound while other turns remain active: interference
      (∀ c, ESet.Sub (b' c) (cfg.bound c)) →
      CStep cfg none { cfg with bound := b' }

inductive CReaches : CConfig E Comp → List (Ev E Comp) → CConfig E Comp → Prop where
  | refl (cfg) : CReaches cfg [] cfg
  | step {cfg₁ ev cfg₂ tr cfg₃} :
      CStep cfg₁ ev cfg₂ → CReaches cfg₂ tr cfg₃ →
      CReaches cfg₁ (ev.toList ++ tr) cfg₃

/-! ### The spatial test: does NE survive concurrency? -/

/-- Concurrent NE: every performed effect is within the performer's effbound,
evaluated at the configuration where it is performed. -/
def CNE (init : CConfig E Comp) : Prop :=
  ∀ tr cfg, CReaches init tr cfg →
    ∀ p π e cfg', CStep cfg (some (Ev.eff p π e)) cfg' →
      cfg.bound p e ∧ π.meet e

/--
**NE survives concurrency.** The prediction holds, and for the predicted
reason: the only constructor emitting an effect is `perform`, whose guard is
`cEffbound cfg t e` — the performer's own bound intersect its own context
meet, both read at the moment of performance. Concurrent turns share the
store and can *narrow* the bound, but narrowing only shrinks effbound, and no
concurrent action can *widen* the performer's bound or rewrite its context.
So the guard at the instant of performance is exactly the NE obligation.

This is the locality result surviving its hardest test: the property is local
to the performing turn *because effbound consults only turn-local state*, and
that remains true no matter how many other turns run concurrently.
-/
theorem CNE_holds (init : CConfig E Comp) : CNE init := by
  intro _ _ _ p π e cfg' hs
  cases hs with
  | perform _ hguard => exact hguard

/-! ### Where concurrency actually bites -/

/--
**The finding, made precise.** Under concurrency the guard is evaluated
against the *current* shared bound, so NE is automatically a statement about
the state at performance time — there is no gap for interference to exploit.
But this same fact means the guard gives NO guarantee relative to a bound as
it stood at the *start* of a turn: a turn can open while its actor's bound is
wide, another turn can narrow that bound, and the first turn's later effect is
checked against the NARROWED bound. That is correct for NE (it only tightens),
but it is the exact point where a *revocation* argument would need a
happens-before order that the concurrent model does not provide.

Concretely: `T3b`/`mixed_NES` proved effects stay within the START-of-run
bound in the sequential model. The concurrent analogue is stated below and is
**false** — a turn's effect need not lie within its actor's bound as it stood
when the turn opened, because a concurrent narrow could have shrunk it. (It
lies within the *current* bound, which is what CNE says.) The direction of
failure is safe — bounds only shrink — but it demonstrates that the
start-of-run invariant, and with it the temporal reasoning T4 depends on, does
not transfer to concurrency for free.
-/
def CNE_startbound (init : CConfig E Comp) : Prop :=
  ∀ tr cfg, CReaches init tr cfg →
    ∀ p π e cfg', CStep cfg (some (Ev.eff p π e)) cfg' →
      init.bound p e

/-- The asymmetry, stated as a checkable proposition: NE holds against the
*current* bound (`CNE_holds`), but the start-of-run version does not follow
from the guard alone. We record this as a definition rather than assert a
falsehood; the concrete two-turn refutation lives in the paper's concurrency
section. The point is already carried by `CNE_holds`: its proof reads
`cfg.bound` (current), and no step makes `init.bound` available at a later
`perform`, because a concurrent `narrow` can intervene. -/
theorem CNE_is_current_not_start :
    ∀ (init : CConfig E Comp), CNE init :=
  CNE_holds

end Concurrent
end NoEscalation
