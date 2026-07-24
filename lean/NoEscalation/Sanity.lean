/-
NoEscalation / Sanity.lean — degeneracy checks for the definitions, and one
FINDING.

Sanity 1: NE is refutable — the semantics admits violating runs. The witness
is Benchmark 2 (shared-service re-amplification) transcribed from the Alloy
suite (`B2AttackP` in noescalation_v3.als): a service legitimately holding a
capability performs its effect inside a chain whose conferral excludes it.

Sanity 2: NE is not trivially false — the same configuration admits a
compliant nontrivial run (the conferred effect, performed within the meet).

FINDING (`composition_target_unprovable`): the phase-two target as stated in
Semantics.lean — InitOK → NE — is UNPROVABLE: the Sanity-1 witness satisfies
InitOK. This refutes v1.0 §8 as literally written; the benchmark suite has
contained this counterexample since v1 (an NE-violating run IS what
B2_AttachedFlags certifies). Restatement required via decision memo before
the invariant search begins. Candidate restatements: guarded (enforcing)
semantics with a monitor-correctness theorem; or behavioral conditioning of
all components. See the accompanying memo discussion.
-/

import NoEscalation.Semantics

namespace NoEscalation
namespace Sanity

/-- Two effects: one the root conferral covers, one it does not. -/
inductive Ef : Type where
  | good
  | bad

/-- Two components: a root principal and a service. -/
inductive Cp : Type where
  | alice
  | bob

def goodOnly : ESet Ef := fun e => e = .good

def capGood : Cap Ef := ⟨fun e => e = .good⟩
def capBad  : Cap Ef := ⟨fun e => e = .bad⟩

/-- Root context: alice confers only `good`. -/
def π₀ : Ctx Ef Cp := .root .alice goodOnly

/-- The root request from alice to bob (no payload). `stamp` is irrelevant
here (no caretakers in this scenario); ⊤ is the neutral choice. -/
def m₀ : Msg Ef Cp :=
  { sender := .alice, target := .bob, ctx := π₀, payload := fun _ => False,
    stamp := fun _ => True }

/-- The B2 shape: bob (a shared service) legitimately holds BOTH
capabilities — `capGood` matching the conferral and `capBad` from elsewhere —
bounds are maximal, one root request pending. -/
def init : Config Ef Cp :=
  { store    := fun c k => c = .bob ∧ (k = capGood ∨ k = capBad)
    bound    := fun _ _ => True
    inflight := fun m => m = m₀
    live     := fun _ => False
    phase    := .idle
    filters  := fun _ _ => True
    issued   := fun _ => True
    invoked  := fun _ _ => False }

/-- Deliver m₀: bob's turn opens under alice's narrow context.
Trace is [] (delivery is silent). -/
private theorem reach₁ :
    Reaches init [] { init with
      phase    := .active m₀.target m₀.ctx
      issued   := m₀.stamp
      inflight := fun m' => init.inflight m' ∧ m' ≠ m₀
      store    := fun c k => init.store c k ∨ (c = m₀.target ∧ m₀.payload k) } :=
  Reaches.step (Step.startMsg rfl rfl) (Reaches.refl _)
  -- CHECK: relies on `(none).toList ++ [] ≡ []` and structure-literal
  -- projection reduction (m₀.target ≡ .bob, m₀.ctx ≡ π₀). Both should be
  -- definitional; if not, `show` the reduced type.

/-- Sanity 1 + FINDING core: NE fails at `init`. Bob performs `bad` — his
own legitimately held capability — inside alice's `good`-only chain. -/
theorem NE_refutable : ¬ NE init := by
  intro h
  have hv := h [] _ reach₁ .bob π₀ .bad _
    (Step.perform rfl ⟨capBad, Or.inl ⟨rfl, Or.inr rfl⟩, rfl⟩)
  -- hv.2 : π₀.meet .bad, which reduces to (Ef.bad = Ef.good)
  exact nomatch hv.2

/-- Sanity 2: the same configuration admits a compliant nontrivial run —
the conferred effect, performed within bound and meet. NE is not trivially
false; the definitions distinguish good runs from bad ones on one init. -/
theorem NE_livable :
    ∃ cfg₁ cfg₂, Reaches init [] cfg₁ ∧
      Step cfg₁ (some (Ev.eff .bob π₀ .good)) cfg₂ ∧
      cfg₁.bound .bob Ef.good ∧ π₀.meet Ef.good :=
  ⟨_, _, reach₁,
   Step.perform rfl ⟨capGood, Or.inl ⟨rfl, Or.inl rfl⟩, rfl⟩,
   trivial, rfl⟩

/-- THE FINDING: the phase-two target as stated (`InitOK → NE`) is
unprovable — `init` satisfies every InitOK clause yet reaches an NE
violation. v1.0 §8 requires restatement; do not attempt the invariant
search against the current target. -/
theorem composition_target_unprovable :
    ∃ cfg : Config Ef Cp, InitOK cfg ∧ ¬ NE cfg := by
  refine ⟨init, ?_, NE_refutable⟩
  refine ⟨rfl, fun _ h => h, fun _ _ _ _ _ => trivial, fun m hm => ?_⟩
  -- hm : m = m₀ (from init.inflight); subst so payload/ctx reduce
  subst hm
  exact ⟨fun _ _ hk _ => hk.elim, fun _ _ => trivial⟩

end Sanity
end NoEscalation
