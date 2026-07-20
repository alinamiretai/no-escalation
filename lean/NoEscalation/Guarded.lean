/-
NoEscalation / Guarded.lean — v1.1 restatement (property-note v1.1 §5, §8).

Two semantic layers:
  • the UNGUARDED `Step` (Semantics.lean) is the specification layer — it
    admits NE-violating runs (that's what the benchmarks exercise);
  • the GUARDED step here is the enforcement layer — `gperform` carries the
    effbound check. Untrusted components step only via the guarded relation;
    trusted components step via the unguarded relation but are constrained by
    their contracts (Guard here; Membrane/filter deferred with T4).

Theorems:
  • T1 (soundness): every guarded trace satisfies NE.           [PROVED]
  • T2 (mixed composition): guarded-untrusted + contract-trusted
        + InitOK' ⇒ NE.                                          [sorry]

STATUS: unelaborated draft; `-- CHECK:` marks suspected friction.
-/

import NoEscalation.Semantics

namespace NoEscalation
namespace Guarded

universe u v
variable {E : Type u} {Comp : Type v}

/-- Trust partition (property-note §1). A predicate on components; the
mediation assumption A5 says untrusted components step only via `GStep`. -/
structure System (E : Type u) (Comp : Type v) where
  trusted : Comp → Prop

variable (Sys : System E Comp)

/--
Guarded step relation. Identical to `Step` EXCEPT `gperform` additionally
requires `effbound(π) e` — i.e. `bound p e ∧ π.meet e`. All other
constructors are lifted unchanged (a component may still start turns, send,
make resolvers, end turns, narrow bounds).
-/
inductive GStep : Config E Comp → Option (Ev E Comp) → Config E Comp → Prop where
  | lift {cfg ev cfg'} :
      Step cfg ev cfg' →
      (∀ p π e, ev = some (Ev.eff p π e) → cfg.bound p e ∧ π.meet e) →
      GStep cfg ev cfg'
  -- Every event-emitting lifted step must pass the guard; silent steps
  -- (start/send/mkRes/end/narrow) lift unconditionally since the hypothesis
  -- is vacuous for `ev = none`.

/-- Guarded reachability. -/
inductive GReaches : Config E Comp → List (Ev E Comp) → Config E Comp → Prop where
  | refl (cfg) : GReaches cfg [] cfg
  | step {cfg₁ ev cfg₂ tr cfg₃} :
      GStep cfg₁ ev cfg₂ → GReaches cfg₂ tr cfg₃ →
      GReaches cfg₁ (ev.toList ++ tr) cfg₃

/-- Guarded NE: the property, evaluated on the guarded relation. -/
def GNE (init : Config E Comp) : Prop :=
  ∀ tr cfg, GReaches init tr cfg →
    ∀ p π e cfg', GStep cfg (some (Ev.eff p π e)) cfg' →
      cfg.bound p e ∧ π.meet e

/--
**T1 (Soundness).** Every guarded step that emits an effect satisfies
effbound by construction; hence GNE holds for any init. Near-definitional —
the guard *is* the property. This is the floor (property-note §8, T1).
-/
theorem T1_soundness (init : Config E Comp) : GNE init := by
  intro _ _ _ p π e _ hs
  cases hs with
  | lift _ hguard => exact hguard p π e rfl
  -- CHECK: if `cases` complains about the implicit event, use
  -- `rcases hs with ⟨_, hguard⟩; exact hguard p π e rfl`.

/--
Corrected initial conditions (property-note §8, InitOK'). Drops v1.0's false
"structural conditions suffice for untrusted components" and adds the
mediation clause. Provisional: co-evolves with the T2 invariant search.
-/
structure InitOK' (cfg : Config E Comp) : Prop where
  idle    : cfg.phase = .idle
  noRes   : ∀ r, ¬ cfg.live r
  capsOK  : ∀ c k, cfg.store c k → ESet.Sub k.denotes (cfg.bound c)
  rootsOK : ∀ m, cfg.inflight m → ESet.Sub m.ctx.meet (cfg.bound m.target)
  -- A5 (mediation) and the trusted-contract obligations are carried by the
  -- MIXED step relation below, not by init; see `MStep`.

/--
Mixed step relation (the deployed architecture, property-note §8 T2):
  • an UNTRUSTED component steps only via the guarded relation (A5);
  • a TRUSTED component steps via the unguarded relation but must satisfy its
    Guard contract on emitted effects.
The performer of an event is read from the event; silent steps are allowed
from either class unconditionally.
-/
inductive MStep : Config E Comp → Option (Ev E Comp) → Config E Comp → Prop where
  | untrusted {cfg ev cfg'} :
      GStep cfg ev cfg' →
      (∀ p π e, ev = some (Ev.eff p π e) → ¬ Sys.trusted p) →
      MStep cfg ev cfg'
  | trusted {cfg ev cfg'} :
      Step cfg ev cfg' →
      (∀ p π e, ev = some (Ev.eff p π e) → Sys.trusted p ∧ cfg.bound p e ∧ π.meet e) →
      MStep cfg ev cfg'
  -- CHECK: silent steps (ev = none) satisfy both guards vacuously, so either
  -- constructor can carry them; that overlap is harmless for the property.

inductive MReaches : Config E Comp → List (Ev E Comp) → Config E Comp → Prop where
  | refl (cfg) : MReaches cfg [] cfg
  | step {cfg₁ ev cfg₂ tr cfg₃} :
      MStep Sys cfg₁ ev cfg₂ → MReaches cfg₂ tr cfg₃ →
      MReaches cfg₁ (ev.toList ++ tr) cfg₃

def MNE (init : Config E Comp) : Prop :=
  ∀ tr cfg, MReaches Sys init tr cfg →
    ∀ p π e cfg', MStep Sys cfg (some (Ev.eff p π e)) cfg' →
      cfg.bound p e ∧ π.meet e


/-- The single-step content of T2, which DOES hold definitionally — recorded
as a lemma both to check the encoding and to be reused by the eventual
inductive proof. Every mixed step that emits an effect satisfies effbound. -/
theorem MStep_guards {cfg : Config E Comp} {p π e cfg'}
    (hs : MStep Sys cfg (some (Ev.eff p π e)) cfg') :
    cfg.bound p e ∧ π.meet e := by
  cases hs with
  | untrusted hg _ =>
      cases hg with
      | lift _ hguard => exact hguard p π e rfl
  | trusted _ hc =>
      exact (hc p π e rfl).2
  -- CHECK: nested `cases` on the lifted GStep; if the implicit event unifies
  -- awkwardly, switch to `rcases`.


/--
**T2 (Mixed-system composition) — property-note §8, PROVED.**

Proof is three lines, and that is a FINDING, not a disappointment: because
effbound is turn-local (performer's bound + message-carried context, no
global state), the enforcement condition is per-step, and composition of the
enforced property is trivial BY DESIGN — the Fournet–Gordon thin-guarantee
pattern, landed. `MStep_guards` was the whole theorem. Note `InitOK'` is not
needed: under enforcement, NE requires no initial conditions. (The earlier
docstring claiming "the difficulty is purely the inductive strengthening"
was wrong — ledger entry: prose ahead of the checker errs in both
directions. The genuine invariant work belongs to T4: alias-freedom over
stores and in-flight payloads, a mutually-inductive pair with Membrane —
see the T4 development.)
-/
theorem T2_mixed_composition (init : Config E Comp) : MNE Sys init := by
  intro _ _ _ p π e cfg' hs
  exact MStep_guards Sys hs


end Guarded
end NoEscalation
