// benchmark_attacks.als — the B1 (confused deputy / performer-only attribution)
// and B2 (re-amplification / component-bounds-only) benchmarks, re-encoded as a
// standalone reproducible file.
//
// WHY THIS FILE EXISTS (LEDGER L14): CLAIMS rows C1 and C2 cited assertions
// (B1Sat, B1_ChainFlags, B2AttackSat, ...) that lived in early development
// files never committed to git. The checks were real but unreproducible. This
// file restores them under the exact names CLAIMS references, so the evidence
// pointers resolve to something runnable.
//
// The same two attacks are checked at three levels: here (Alloy, bounded),
// in Lean (T1/T2, unbounded), and in the proxy's test_attacks.py (running
// code). Three independent witnesses to the same counterexamples.
//
// EXPECTED VERDICTS:
//   B1_InvisibleToPerf   valid   (performer-only attribution CANNOT see the
//                                 deputy misuse — validity IS the indictment)
//   B1_ChainFlags        valid   (chain attribution DOES flag it)
//   B1Sat                SAT     (the scenario is inhabited, not vacuous)
//   B2_InvisibleToPerf   valid   (component bounds alone hide re-amplification)
//   B2_AttachedFlags     valid   (attached bounds catch it)
//   B2_LegitClean        valid   (a legitimate call is not flagged)
//   B2AttackSat          SAT     (attack inhabited)
//   B2LegitSat           SAT     (legit case inhabited)

module benchmark_attacks

open util/ordering[Turn]

sig Effect {}
sig Comp {}
sig Turn { actor: one Comp }

// A hop attaches a component and a bound (set of effects it confers).
sig Hop { who: one Comp, beta: set Effect }
// A chain is an ordered list of hops (modeled as a sequence via next).
sig Chain { hops: seq Hop }

// An occurrence: an effect performed in a turn, under a chain.
sig Occ { eff: one Effect, turn: one Turn, chain: one Chain, performer: one Comp }

// ---- Attribution readings ----

// Performer-only: attributes an occurrence solely to who performed it.
fun attributedPerf[o: Occ]: set Comp { o.performer }

// Chain attribution: every component on the chain is attributed.
fun attributedChain[o: Occ]: set Comp { o.chain.hops.elems.who }

// effbound under the chain: intersection of all attached bounds.
fun chainMeet[c: Chain]: set Effect {
  { e: Effect | all h: c.hops.elems | e in h.beta }
}

// ---- B1: the confused deputy ----
// A deputy performs an effect NOT conferred by the chain (outside the meet).
// Performer-only attribution names ONLY the deputy, so the requesting
// components — whose grant was exceeded — are invisible.

pred B1_ConfusedDeputy[o: Occ] {
  o.eff not in chainMeet[o.chain]
  some (o.chain.hops.elems.who - o.performer)   // a requester distinct from performer
}

// Performer-only attribution is INVISIBLE: some chain component that is not the
// performer goes unattributed. (Validity is the indictment.)
assert B1_InvisibleToPerf {
  all o: Occ | B1_ConfusedDeputy[o] implies
    some c: (o.chain.hops.elems.who - o.performer) | c not in attributedPerf[o]
}

// Chain attribution DOES flag it: the requesters are attributed.
assert B1_ChainFlags {
  all o: Occ | B1_ConfusedDeputy[o] implies
    (o.chain.hops.elems.who - o.performer) in attributedChain[o]
}

pred B1Sat { some o: Occ | B1_ConfusedDeputy[o] }

// ---- B2: re-amplification ----
// The performer's OWN bound is the beta at the performer's own hop. An effect
// can lie inside that bound yet outside the chain meet, because an EARLIER hop
// narrowed it away. Component-bounds-only checking misses it; the meet catches it.

fun perfBound[o: Occ]: set Effect {
  { e: Effect | some h: o.chain.hops.elems | h.who = o.performer and e in h.beta }
}

pred B2_ReAmplify[o: Occ] {
  o.eff in perfBound[o]                    // inside performer's own bound
  o.eff not in chainMeet[o.chain]          // outside the chain meet
}

assert B2_InvisibleToPerf {
  all o: Occ | B2_ReAmplify[o] implies o.eff in perfBound[o]
}
assert B2_AttachedFlags {
  all o: Occ | B2_ReAmplify[o] implies o.eff not in chainMeet[o.chain]
}

// A legit call is inside the chain meet. The meet is contained in EVERY hop's
// bound, including the performer's, so a legit effect is necessarily inside the
// performer's own bound. That containment is what B2_LegitClean checks.
pred B2_Legit[o: Occ] {
  o.eff in chainMeet[o.chain]
  some h: o.chain.hops.elems | h.who = o.performer   // performer is on the chain
}
assert B2_LegitClean {
  all o: Occ | B2_Legit[o] implies o.eff in perfBound[o]
}

pred B2AttackSat { some o: Occ | B2_ReAmplify[o] }
pred B2LegitSat  { some o: Occ | B2_Legit[o] }

// ---- run them ----
check B1_InvisibleToPerf for 6
check B1_ChainFlags for 6
run B1Sat for 6
check B2_InvisibleToPerf for 6
check B2_AttachedFlags for 6
check B2_LegitClean for 6
run B2AttackSat for 6
run B2LegitSat for 6
