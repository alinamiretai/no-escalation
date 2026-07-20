/-
NoEscalation / Alias.lean — T4's structural prerequisite: alias-freedom
preservation under the Membrane contract, option B (contracts as conditions
on steps, theorems conditional on them).

The Alloy scope-check of this claim is AV_AliasPreserved (alias_v11.als,
valid at scope 5/5). This file is its unbounded generalization.

Structure (the pattern learned from Step_bound_antitone):
  Step-level lemma → mechanical lift to MStep → induction along MReaches.

Two clauses, mutually inductive across steps:
  A (stores):   no non-caretaker holds an underlying capability;
  B (in-flight): no pending message's payload contains one.
`startMsg` preserves A via B; `send` preserves B via A (non-caretaker
sender) or Membrane (caretaker sender); the other five constructors touch
neither stores nor payloads.

STATUS: unelaborated draft; `-- CHECK:` marks suspected friction.
-/

import NoEscalation.Warmups

namespace NoEscalation
namespace Alias

universe u v
variable {E : Type u} {Comp : Type v}

/-- System description extended with the caretaker cast and the designated
revocable ("underlying") capabilities. -/
structure CareSystem (E : Type u) (Comp : Type v)
    extends Guarded.System E Comp where
  caretaker  : Comp → Prop
  underlying : Cap E → Prop
  care_trusted : ∀ c, caretaker c → trusted c

variable (S : CareSystem E Comp)

/--
Membrane, delta-style (option B): a *predicate on steps*, not part of the
step relation. Any message pending after the step that was not pending
before, whose sender is a caretaker, carries no underlying capability.
Stated on configurations only — no inspection of the step constructor.
-/
def MembraneOK (cfg cfg' : Config E Comp) : Prop :=
  ∀ m : Msg E Comp, ¬ cfg.inflight m → cfg'.inflight m →
    S.caretaker m.sender → ∀ k, m.payload k → ¬ S.underlying k

/-- The invariant: clause A (stores) and clause B (in-flight). -/
structure AliasInv (cfg : Config E Comp) : Prop where
  stores   : ∀ C k, ¬ S.caretaker C → cfg.store C k → ¬ S.underlying k
  inflight : ∀ m k, cfg.inflight m → m.payload k → ¬ S.underlying k

/--
Step-level preservation. The seven cases:
  startMsg — store gains the payload; clause B on the consumed message keeps
             clause A; pending set shrinks so clause B survives;
  startRes / perform / mkRes / endTurn / narrow — stores and inflight
             untouched (or shrink);
  send     — pending set gains one message; its payload comes from the
             sender's store (PayloadFromStore is a side condition of the
             constructor): non-caretaker sender → clean by clause A;
             caretaker sender → clean by MembraneOK.
-/
theorem Step_alias_preserved {cfg ev cfg'}
    (hs : Step cfg ev cfg')
    (hmem : MembraneOK S cfg cfg')
    (hinv : AliasInv S cfg) : AliasInv S cfg' := by
  cases hs with
  | startMsg hphase hin =>
      constructor
      · -- stores: old store or the delivered payload
        intro C k hC hstore
        cases hstore with
        | inl hold => exact hinv.stores C k hC hold
        | inr hnew => exact hinv.inflight _ k hin hnew.2
      · -- inflight: subset of the old pending set
        intro m k hm hk
        exact hinv.inflight m k hm.1 hk
  | startRes hphase hlive =>
      exact ⟨hinv.stores, hinv.inflight⟩
      -- CHECK: startRes changes `live` and `phase` only; if the structure
      -- update does not reduce definitionally under the anonymous
      -- constructor, use `constructor <;> intro ... <;> exact hinv....`.
  | perform hphase hcap =>
      exact hinv
  | send hphase hsender hctx hpay =>
      constructor
      · intro C k hC hstore
        exact hinv.stores C k hC hstore
      · -- inflight: old messages by clause B; the new message m by cases on
        -- whether its sender is a caretaker.
        intro m k hm hk
        cases hm with
        | inl hold => exact hinv.inflight m k hold hk
        | inr hnew =>
          subst hnew
          by_cases hc : S.caretaker m.sender
          · -- caretaker sender: MembraneOK covers the newly pending message
            by_cases hpend : cfg.inflight m
            · exact hinv.inflight m k hpend hk
            · exact hmem m hpend (Or.inr rfl) hc k hk
          · -- non-caretaker sender: payload from its store, clean by clause A
            rw [hsender] at hc
            exact hinv.stores _ k hc (hpay k hk)
      -- CHECK/DELIBERATE: the two sorries above are left as YOUR two cases —
      -- they are the entire mathematical content of this lemma, and the
      -- surrounding scaffolding guarantees they are the only two. Hints:
      -- caretaker case — you need "m was not already pending" to invoke
      --   `hmem`; if m was already pending, clause B covers it (fold into
      --   the `inl` branch or case on `cfg.inflight m`).
      -- non-caretaker case — `hpay k hk : cfg.store m.sender k` after
      --   rewriting with `hsender`; then `hinv.stores` closes it.
      -- If `subst hnew` fails (m' = m orientation), use `cases hnew` or
      -- rewrite the disjunct as needed.
  | mkRes hphase hhost hcap =>
      exact ⟨hinv.stores, hinv.inflight⟩
  | endTurn hphase =>
      exact ⟨hinv.stores, hinv.inflight⟩
  | narrow hnar =>
      exact ⟨hinv.stores, hinv.inflight⟩

/-- Lift to the mixed relation (mechanical, per the Step_bound_antitone
pattern). -/
theorem MStep_alias_preserved {cfg ev cfg'}
    (hs : Guarded.MStep S.toSystem cfg ev cfg')
    (hmem : MembraneOK S cfg cfg')
    (hinv : AliasInv S cfg) : AliasInv S cfg' := by
  cases hs with
  | untrusted hg _ =>
      cases hg with
      | lift hstep _ => exact Step_alias_preserved S hstep hmem hinv
  | trusted hstep _ => exact Step_alias_preserved S hstep hmem hinv

/-- A trace is membrane-respecting if every step in it is. Threaded through
reachability the same way the trace itself is. -/
inductive MembraneTrace : Config E Comp → List (Ev E Comp) → Config E Comp → Prop where
  | refl (cfg) : MembraneTrace cfg [] cfg
  | step {cfg₁ ev cfg₂ tr cfg₃} :
      Guarded.MStep S.toSystem cfg₁ ev cfg₂ →
      MembraneOK S cfg₁ cfg₂ →
      MembraneTrace cfg₂ tr cfg₃ →
      MembraneTrace cfg₁ (ev.toList ++ tr) cfg₃

/-- **Alias-freedom along membrane-respecting traces** — the unbounded
generalization of Alloy's AV_AliasPreserved, and T4's load-bearing
invariant: established at conferral (the hypothesis), preserved thereafter
(this theorem). -/
theorem alias_free_along {init : Config E Comp} (hinit : AliasInv S init) :
    ∀ tr cfg, MembraneTrace S init tr cfg → AliasInv S cfg := by
  intro tr cfg hr
  induction hr with
  | refl _ => exact hinit
  | step hstep hmem _ ih =>
      exact ih (MStep_alias_preserved S hstep hmem hinit)
  -- CHECK: induction-hypothesis plumbing — `ih` expects the invariant at the
  -- intermediate configuration; if the motive comes out backwards, switch to
  -- a forward recursion: prove `AliasInv cfg₂` first via
  -- `MStep_alias_preserved`, then apply `ih` to it. The comment form above
  -- assumes ih : AliasInv cfg₂ → AliasInv cfg₃; adjust names to what the
  -- goal state shows.

end Alias
end NoEscalation
