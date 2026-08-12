/-
NoEscalation / Semantics.lean — turn-based operational semantics, traces,
and the property statements. Transcribes property-note v1.0 §2–§5 and
mirrors the Alloy kernel (noescalation_v3.als), with turns decomposed into
phase-locked micro-steps: a `startMsg`/`startRes` acquires the turn lock,
`perform`/`send`/`mkRes` execute under it, `endTurn` releases it. Atomicity
of turns is preserved because no other component can step while the phase
is `active` — mirrors Alloy's globally ordered turns, and gives clean
induction.

DEFERRED (phase two, per the v1.0 plan): spawn discipline, caretakers and
filters (trusted-component contracts, D5 of the item-6 memo), the chain-level
NES clause, the inductive strengthening, and the composition proof itself.

STATUS: unelaborated draft; `-- CHECK:` marks suspected friction.
-/

import NoEscalation.Kernel

namespace NoEscalation

universe u v

variable {E : Type u} {Comp : Type v}

/-- A capability: unforgeable reference with a fixed denotation (v1.0 §3). -/
structure Cap (E : Type u) : Type u where
  denotes : ESet E

/-- Messages carry semantic contexts, capability payloads, and (T4) the
issuance stamp: the target's filter as of this send. -/
structure Msg (E : Type u) (Comp : Type v) : Type (max u v) where
  sender  : Comp
  target  : Comp
  ctx     : Ctx E Comp
  payload : Cap E → Prop
  stamp   : ESet E

/-- A resolver/continuation: captures its creation context (D2 rule 3).
No stamp here — issuance is fixed at INVOCATION (`invokeRes`), per the
resolver-issuance memo and C1/C2/C3. -/
structure Res (E : Type u) (Comp : Type v) : Type (max u v) where
  host     : Comp
  captured : Ctx E Comp

/-- Turn lock: `active p π` = component `p` is mid-turn under context `π`. -/
inductive Phase (E : Type u) (Comp : Type v) : Type (max u v) where
  | idle
  | active (performer : Comp) (ctx : Ctx E Comp)

/-- Configurations. Stores and message pools are predicates (sets); NE is a
safety property, so multiplicity is irrelevant. -/
structure Config (E : Type u) (Comp : Type v) : Type (max u v) where
  store    : Comp → Cap E → Prop
  bound    : Comp → ESet E
  inflight : Msg E Comp → Prop
  live     : Res E Comp → Prop
  phase    : Phase E Comp
  /-- T4/D1: per-component revocation filter; narrows only. Meaningful for
  caretakers, unconstrained elsewhere. -/
  filters  : Comp → ESet E
  /-- T4/D2: the issuance stamp of the currently open turn, set when the turn
  opens from its trigger. Irrelevant while idle. -/
  issued   : ESet E
  /-- Resolvers that have been invoked, paired with the stamp taken at the
  moment of invocation (invoker-turn licensing). -/
  invoked  : Res E Comp → ESet E → Prop
  /-- T4-weak: the accumulated union of stamps of caretaker messages that have
  been CONSUMED by `startMsg`. Grows monotonically. This is the issuance
  history the weak revocation form needs: when a turn opens from an in-flight
  message and that message leaves the in-flight set, its licensing stamp is
  retained here so the weak-invariant disjunct still has a witness. Irrelevant
  to the strong (quiesced) form, which never has stale messages. -/
  issuedHistory : ESet E

/-- Observable events: effect occurrences with performer and context. -/
inductive Ev (E : Type u) (Comp : Type v) : Type (max u v) where
  | eff (performer : Comp) (ctx : Ctx E Comp) (e : E)

/--
The step relation. Side conditions encode A1/A2 (unforgeability, ocap
discipline): capabilities move only via payloads senders hold; contexts are
constructed only by the rules; resolvers are linear (consumed by `startRes`).
Note `perform` requires a capability but NOT bound membership — effects CAN
violate NE; NE is the property under test, not a semantic invariant.
-/
inductive Step : Config E Comp → Option (Ev E Comp) → Config E Comp → Prop where
  | startMsg {cfg : Config E Comp} {m : Msg E Comp} :
      cfg.phase = .idle → cfg.inflight m →
      Step cfg none
        { cfg with
          phase    := .active m.target m.ctx
          issued   := m.stamp                         -- T4/D2
          inflight := fun m' => cfg.inflight m' ∧ m' ≠ m
          issuedHistory := fun e => cfg.issuedHistory e ∨ m.stamp e  -- T4-weak: retain consumed stamp
          store    := fun c k => cfg.store c k ∨ (c = m.target ∧ m.payload k) }
  | startRes {cfg : Config E Comp} {r : Res E Comp} {σ : ESet E} :
      cfg.phase = .idle → cfg.live r → cfg.invoked r σ →
      Step cfg none
        { cfg with
          phase   := .active r.host r.captured
          issued  := σ                                -- invoker-turn licensing
          live    := fun r' => cfg.live r' ∧ r' ≠ r    -- linearity: consumed
          invoked := fun r' σ' => cfg.invoked r' σ' ∧ r' ≠ r }
  | perform {cfg : Config E Comp} {p : Comp} {π : Ctx E Comp} {e : E} :
      cfg.phase = .active p π →
      (∃ k, cfg.store p k ∧ k.denotes e) →
      Step cfg (some (.eff p π e)) cfg
  | send {cfg : Config E Comp} {p : Comp} {π : Ctx E Comp}
         {m : Msg E Comp} {β : ESet E} :
      cfg.phase = .active p π →
      m.sender = p →
      m.ctx = .hop π p β →                      -- D2 rule 2: context extension
      (∀ k, m.payload k → cfg.store p k) →      -- A1: only send what you hold
      m.stamp = cfg.filters m.target →          -- T4/D2: stamp at issuance
      Step cfg none
        { cfg with inflight := fun m' => cfg.inflight m' ∨ m' = m }
  | mkRes {cfg : Config E Comp} {p : Comp} {π : Ctx E Comp} {r : Res E Comp} :
      cfg.phase = .active p π →
      r.host = p → r.captured = π →             -- D2 rule 3: capture
      Step cfg none
        { cfg with live := fun r' => cfg.live r' ∨ r' = r }
  | endTurn {cfg : Config E Comp} {p : Comp} {π : Ctx E Comp} :
      cfg.phase = .active p π →
      Step cfg none { cfg with phase := .idle }
  | invokeRes {cfg : Config E Comp} {p : Comp} {π : Ctx E Comp} {r : Res E Comp} :
      cfg.phase = .active p π →
      cfg.live r →
      -- Issuance is fixed HERE, at the invoker's turn: the stamp is the
      -- host's filter as it stands now. Creation-turn licensing was refuted
      -- (resolver_issuance.als C1); resume-turn licensing is strong
      -- revocation, inconsistent with the weak rule chosen for messages.
      Step cfg none
        { cfg with
          invoked := fun r' σ =>
            cfg.invoked r' σ ∨ (r' = r ∧ σ = cfg.filters r.host) }
  | narrow {cfg : Config E Comp} {b' : Comp → ESet E} :
      (∀ c, ESet.Sub (b' c) (cfg.bound c)) →    -- A4: bounds only narrow
      Step cfg none { cfg with bound := b' }
  | narrowFilter {cfg : Config E Comp} {f' : Comp → ESet E} :
      (∀ c, ESet.Sub (f' c) (cfg.filters c)) →  -- T4/D1: filters only narrow
      Step cfg none { cfg with filters := f' }

/-- Multi-step reachability, accumulating the event trace. -/
inductive Reaches : Config E Comp → List (Ev E Comp) → Config E Comp → Prop where
  | refl (cfg : Config E Comp) : Reaches cfg [] cfg
  | step {cfg₁ : Config E Comp} {ev : Option (Ev E Comp)}
         {cfg₂ : Config E Comp} {tr : List (Ev E Comp)} {cfg₃ : Config E Comp} :
      Step cfg₁ ev cfg₂ → Reaches cfg₂ tr cfg₃ →
      Reaches cfg₁ (ev.toList ++ tr) cfg₃
      -- CHECK: `(some x).toList ++ tr` should be defeq to `x :: tr`;
      -- if elaboration balks downstream, add simp lemmas Option.toList / List.append.

/-- v1.0 §5: NE, the unified property. Every performable effect at every
reachable configuration lies within its effective bound
(performer's bound ∩ chain meet). -/
def NE (init : Config E Comp) : Prop :=
  ∀ tr cfg, Reaches init tr cfg →
    ∀ p π e cfg', Step cfg (some (Ev.eff p π e)) cfg' →
      cfg.bound p e ∧ π.meet e

/-- Projection NE-T (component view). -/
def NE_T (init : Config E Comp) : Prop :=
  ∀ tr cfg, Reaches init tr cfg →
    ∀ p π e cfg', Step cfg (some (Ev.eff p π e)) cfg' →
      cfg.bound p e

/-- v1.0 §5: eventual authority — effects reachably attributable to `c`
from `cfg`, under the authority-provenance reading of attribution. -/
def EA (cfg : Config E Comp) (c : Comp) (e : E) : Prop :=
  ∃ tr cfg', Reaches cfg tr cfg' ∧
    ∃ p π, (Ev.eff p π e) ∈ tr ∧ (p = c ∨ π.attrib c)

/-- v1.0 §5: NE-S, component clause — EA within bound at every reachable
configuration. The chain clause (over in-flight and captured contexts) is
the phase-two inductive strengthening and is deliberately NOT stated yet:
its correct form is the discovery work. -/
def NES_T (init : Config E Comp) : Prop :=
  ∀ tr cfg, Reaches init tr cfg → ∀ c e, EA cfg c e → cfg.bound c e

/-- The note's promised "immediate" lemma (v1.0 §5), NE-T half:
the state invariant implies the trace property. -/
theorem NES_T.implies_NE_T {init : Config E Comp} (h : NES_T init) :
    NE_T init := by
  intro tr cfg hr p π e cfg' hs
  apply h tr cfg hr p e
  refine ⟨[Ev.eff p π e], cfg', ?_, p, π, List.Mem.head _, Or.inl rfl⟩
  exact Reaches.step hs (Reaches.refl cfg')
  -- CHECK: relies on `(some ev).toList ++ [] ≡ [ev]` definitionally.
  -- Fallback: `have := Reaches.step hs (Reaches.refl cfg'); simpa using this`.

/--
CANDIDATE base case for the composition theorem — v1.0 §8's A1–A4 plus
initial conditions. Explicitly provisional: the invariant search will
revise these clauses; that revision is the core of phase two.
-/
structure InitOK (cfg : Config E Comp) : Prop where
  idle    : cfg.phase = .idle
  noRes   : ∀ r, ¬ cfg.live r
  capsOK  : ∀ c k, cfg.store c k → ESet.Sub k.denotes (cfg.bound c)
  rootsOK : ∀ m, cfg.inflight m →
    (∀ k e, m.payload k → k.denotes e → m.ctx.meet e) ∧
    ESet.Sub m.ctx.meet (cfg.bound m.target)
  -- CHECK/DESIGN: rootsOK is a guess at "root conferrals are honest";
  -- almost certainly too strong or too weak. Revising it IS the work.

/--
RETRACTED (v1.0 → v1.1). This target — `InitOK → NE` — is FALSE. Refuted by
`Sanity.composition_target_unprovable`: the B2 shape satisfies InitOK yet
reaches an NE violation, because untrusted `perform` steps carry no check.
The corrected target is `Guarded.T2_mixed_composition` (see Guarded.lean),
stated over the two-semantics hybrid with the mediation assumption A5.
Kept here, sorry'd, as provenance — do NOT attempt to prove it.
-/
theorem composition_target {init : Config E Comp} (h : InitOK init) :
    NE init := by
  sorry

end NoEscalation
