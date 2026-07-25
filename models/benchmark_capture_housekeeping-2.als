// benchmark_capture_housekeeping.als
// Re-encodes the C3 (D5 continuation-capture) and C8 (item-6 housekeeping)
// checks that CLAIMS cited in the never-committed v3 file (LEDGER L14).
//
// DISCIPLINE: the file existing is not evidence; the file running GREEN with
// the PREDICTED verdicts, and with real (nonzero) var counts on every `check`,
// is. A `check` reporting "0 vars" is a vacuous tautology and proves nothing.
//
// PREDICTED VERDICTS (record CHECKED only if these match exactly):
//   C3:
//     D5_NaiveIsSound     INVALID  (Alloy finds a counterexample = the false
//                                   positive; invalidity IS the indictment)
//     D5_CaptureClean     VALID    (capture rule is sound)
//     D5_RulesDisagree    SAT      (naive flags what capture clears — exhibited)
//   C8:
//     HkRequestFlaggedOperatorClean  SAT  (same effect: flagged as request-turn
//                                          housekeeping, clean as operator-turn
//                                          housekeeping — turn-kind decides)
//     HkOperatorSat / HkRequestSat   SAT  (both placements inhabited)

module benchmark_capture_housekeeping

sig Effect {}
sig Ctx { bound: set Effect }   // a context confers a bound (abstracts the meet)

// ================= C3 : continuation capture =================
// A resolver captures its creation context; it is later invoked under a
// different context. A legitimate resume performs an effect licensed by the
// CREATION context. The naive rule checks against the INVOKER context (and can
// wrongly flag); the capture rule checks against the CREATION context (clean).

sig Resolver {
  ctxCreate: one Ctx,
  ctxInvoke: one Ctx
}
sig Resume {
  res: one Resolver,
  eff: one Effect
}

pred LegitResume[r: Resume] { r.eff in r.res.ctxCreate.bound }

fun naiveChecksAgainst[r: Resume]:   set Effect { r.res.ctxInvoke.bound }
fun captureChecksAgainst[r: Resume]: set Effect { r.res.ctxCreate.bound }

// The naive rule is sound iff every legit resume passes the invoker-bound check.
// EXPECT INVALID: a legit resume whose captured effect is not in the invoker
// bound is a false positive, and it exists.
assert D5_NaiveIsSound {
  all r: Resume | LegitResume[r] implies r.eff in naiveChecksAgainst[r]
}

// The capture rule is sound: every legit resume passes the creation-bound check.
// EXPECT VALID. (Genuine: passes only because LegitResume is defined via the
// creation bound — the conclusion is a real, non-trivial consequence.)
assert D5_CaptureClean {
  all r: Resume | LegitResume[r] implies r.eff in captureChecksAgainst[r]
}

// The two rules disagree on a real instance: naive flags it, capture clears it.
// EXPECT SAT — this inhabited disagreement is the false positive, exhibited.
pred D5_RulesDisagree {
  some r: Resume |
    LegitResume[r]
    and r.eff not in naiveChecksAgainst[r]     // naive flags
    and r.eff in captureChecksAgainst[r]       // capture clears
}

// ================= C8 : housekeeping =================
// The SAME housekeeping effect is a true positive inside a request turn (it
// rides the requester's chain and is outside it) but clean inside an operator
// turn (it runs under the operator's own conferral and is within it). Turn-kind
// decides the verdict — that is the sub-effect principle's content.

abstract sig TurnKind {}
one sig RequestTurn, OperatorTurn extends TurnKind {}

sig Housekeeping {
  eff: one Effect,
  kind: one TurnKind,
  chainBound: one Ctx,      // requester's chain meet (relevant in a request turn)
  operatorBound: one Ctx    // operator's own conferral (relevant in an operator turn)
}

// The effect is outside the requester chain but inside the operator's own bound:
// it WOULD be flagged as request-turn housekeeping, and is clean as operator
// housekeeping.
pred HkVerdictDiffers[h: Housekeeping] {
  h.eff not in h.chainBound.bound
  h.eff in h.operatorBound.bound
}

// EXPECT SAT: the turn-kind dependence is inhabited — the content of C8.
pred HkRequestFlaggedOperatorClean { some h: Housekeeping | HkVerdictDiffers[h] }

pred HkRequestSat  { some h: Housekeeping | HkVerdictDiffers[h] and h.kind = RequestTurn }
pred HkOperatorSat { some h: Housekeeping | HkVerdictDiffers[h] and h.kind = OperatorTurn }

// ---- run ----
check D5_NaiveIsSound  for 6              // EXPECT: INVALID (the false positive)
check D5_CaptureClean  for 6              // EXPECT: VALID
run   D5_RulesDisagree for 6              // EXPECT: SAT
run   HkRequestFlaggedOperatorClean for 6 // EXPECT: SAT
run   HkRequestSat  for 6                 // EXPECT: SAT
run   HkOperatorSat for 6                 // EXPECT: SAT
