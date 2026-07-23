// noescalation_v4.als — v1.1 restatement validation (memo §5).
// New over v3: guarded perform (framework-mediated untrusted components);
//   caretaker Guard clause (the confused-deputy repair). This file VALIDATES
//   the restatement; the frozen v3 suite stays intact as the v1.0-era record.
//
// Faithfulness discipline (learned twice now): caretaker scenarios pin only
//   the SETUP, never the violating effect. Alloy searches for the violation.
//   Every scenario predicate carries a satisfiability witness (rule 1); with
//   util/ordering[Turn], Message scope >= Turn scope (rule 2).
//
// SCOPE of this file: the caretaker confused-deputy finding + repair + the
//   two variants + guarded-perform precision. The full v3 regression is NOT
//   re-copied here; it is unaffected (guarded perform only ADDS a conjunct on
//   the untrusted/caretaker path) and remains green in v3.

module noescalation_v4
open util/ordering[Turn]

abstract sig Effect {}
sig Cap { denotes: set Effect }
sig Underlying in Cap {}

abstract sig Component {}
sig Trusted in Component {}                 // components discharging contracts
abstract sig Caretaker extends Component { filter: Effect -> Turn }
fact CaretakersTrusted { Caretaker in Trusted }
fun filtAt[R: Caretaker, t: Turn]: set Effect { R.filter.t }
fact FilterMonotone {
  all R: Caretaker, t: Turn - first | filtAt[R, t] in filtAt[R, prev[t]]
}

sig Context {
  parent: lone Context,
  extender: one Component,
  attBound: set Effect,
  meetSet: set Effect
}
fact CtxAcyclic { no c: Context | c in c.^parent }
fact CtxMeet {
  all c: Context {
    (no c.parent) implies c.meetSet = c.attBound
    else c.meetSet = c.parent.meetSet & c.attBound
  }
}

sig Res { host: one Component, captured: one Context, createdIn: one Turn }

sig Msg {
  msender: one Component,
  mtarget: one Component,
  mctx: one Context,
  originTurn: lone Turn
}
fact MsgCtx {
  all m: Msg {
    (some m.originTurn) implies {
      m.msender = m.originTurn.actor
      m.mctx.parent = m.originTurn.tctx
      m.mctx.extender = m.originTurn.actor
    } else {
      no m.mctx.parent
      m.mctx.extender = m.msender
    }
  }
}

sig Turn {
  actor: one Component,
  inducingMsg: lone Msg,
  inducingRes: lone Res,
  invokesRes: lone Res,          // v1.1: the invoker turn must be nameable
  tctx: one Context
}
fact TurnInducer { all t: Turn | (some t.inducingMsg) iff (no t.inducingRes) }
fact TurnFromMsg {
  all t: Turn | some t.inducingMsg implies {
    t.actor = t.inducingMsg.mtarget
    t.tctx = t.inducingMsg.mctx
    (some t.inducingMsg.originTurn) implies lt[t.inducingMsg.originTurn, t]
  }
  all m: Msg | lone t: Turn | t.inducingMsg = m
}
fact ResRule {
  all r: Res { r.captured = r.createdIn.tctx and r.host = r.createdIn.actor }
  all r: Res | lone t: Turn | t.invokesRes = r      // linear
  all t: Turn | some t.inducingRes implies {
    t.actor = t.inducingRes.host
    t.tctx = t.inducingRes.captured               // D2 rule 3: capture
    some inv: Turn | inv.invokesRes = t.inducingRes
                     and lt[t.inducingRes.createdIn, inv] and lt[inv, t]
  }
}
/-- v1.1 issuance: the turn of the TRIGGERING action, uniformly. -/
fun issuance[t: Turn]: Turn {
  (some t.inducingMsg) implies t.inducingMsg.originTurn
                         else { inv: Turn | inv.invokesRes = t.inducingRes }
}

sig Occurrence { oeff: one Effect, inTurn: one Turn }
fun effbound[o: Occurrence]: set Effect { o.inTurn.tctx.meetSet }
pred NE { all o: Occurrence | o.oeff in effbound[o] }

// ---- Contracts ----
pred Guard {                                  // all trusted performers check effbound
  all o: Occurrence | o.inTurn.actor in Trusted implies o.oeff in effbound[o]
}
pred ForwardFiltered {                        // caretaker performs pass the filter
  all R: Caretaker, o: Occurrence |
    (o.inTurn.actor = R and some o.inTurn.inducingMsg) implies
      o.oeff in filtAt[R, o.inTurn.inducingMsg.originTurn]
}
// v1.0 caretaker contract: filter only, NO guard (the code under test).
pred V10Contract { ForwardFiltered }
// v1.1 caretaker contract: filter AND guard (the repair).
pred V11Contract { ForwardFiltered and Guard }

// ---------- Finding (memo #4), UN-SCRIPTED ----------
// Cast + filter state only; the occurrence's effect is NOT fixed.
one sig P, G extends Component {}
one sig R extends Caretaker {}
one sig XEff, ResEff extends Effect {}
one sig CU extends Cap {}

pred CareSetup {
  G not in Trusted                             // untrusted deputy
  CU in Underlying and CU.denotes = ResEff
  all c: Cap - CU | ResEff not in c.denotes
  no Res
  some disj t1, t2: Turn, disj m1, m2: Msg {
    Turn = t1 + t2 and Msg = m1 + m2
    lt[t1, t2]
    no m1.originTurn and m1.msender = P and m1.mtarget = G
    m1.mctx.attBound = XEff                     // P confers only XEff
    t1.inducingMsg = m1
    m2.originTurn = t1 and m2.mtarget = R       // G -> R, unguarded send
    t2.inducingMsg = m2
    ResEff in filtAt[R, m2.originTurn]          // filter still permits ResEff
    one Occurrence and Occurrence.inTurn = t2   // ONE occurrence, in R's turn
    // NB: Occurrence.oeff is FREE — Alloy chooses it.
  }
}

run CareSetupSat { CareSetup and V10Contract }
  for 8 but 2 Turn, 2 Msg, 1 Occurrence, 0 Res

// #4: under v1.0 contract, NE can fail (search, not script). Expect INVALID.
assert V10_admits_escalation { (CareSetup and V10Contract) implies NE }
check V10_admits_escalation for 8 but 2 Turn, 2 Msg, 1 Occurrence, 0 Res

// Repair: under v1.1 contract, NE holds. Expect VALID, and non-vacuous by
// the witness below (the caretaker still legitimately performs SOMETHING).
run CareRepairedSat { CareSetup and V11Contract }
  for 8 but 2 Turn, 2 Msg, 1 Occurrence, 0 Res
assert V11_prevents_escalation { (CareSetup and V11Contract) implies NE }
check V11_prevents_escalation for 8 but 2 Turn, 2 Msg, 1 Occurrence, 0 Res

// Legitimate revocable delegation is still expressible under v1.1: if P DOES
// confer ResEff (chain meet contains it), the caretaker forwards it cleanly.
pred LegitDelegation {
  G not in Trusted
  CU in Underlying and CU.denotes = ResEff
  all c: Cap - CU | ResEff not in c.denotes
  no Res
  some disj t1, t2: Turn, disj m1, m2: Msg, o: Occurrence {
    Turn = t1 + t2 and Msg = m1 + m2 and Occurrence = o
    lt[t1, t2]
    no m1.originTurn and m1.msender = P and m1.mtarget = G
    m1.mctx.attBound = XEff + ResEff            // ResEff IS conferred
    t1.inducingMsg = m1
    m2.originTurn = t1 and m2.mtarget = R
    t2.inducingMsg = m2
    ResEff in filtAt[R, m2.originTurn]
    o.oeff = ResEff and o.inTurn = t2
  }
}
run LegitSat { LegitDelegation and V11Contract }
  for 8 but 2 Turn, 2 Msg, 1 Occurrence, 0 Res
assert Legit_clean { LegitDelegation and V11Contract implies NE }
check Legit_clean for 8 but 2 Turn, 2 Msg, 1 Occurrence, 0 Res

// ---------- Variant A: caretaker chain R1 -> R2 (memo 5.4) ----------
one sig R2 extends Caretaker {}
pred ChainSetup {
  G not in Trusted
  CU in Underlying and CU.denotes = ResEff
  all c: Cap - CU | ResEff not in c.denotes
  no Res
  some disj t1, t2, t3: Turn, disj m1, m2, m3: Msg {
    Turn = t1 + t2 + t3 and Msg = m1 + m2 + m3
    lt[t1, t2] and lt[t2, t3]
    no m1.originTurn and m1.msender = P and m1.mtarget = G
    m1.mctx.attBound = XEff
    t1.inducingMsg = m1
    m2.originTurn = t1 and m2.mtarget = R        // G -> R1
    t2.inducingMsg = m2
    m3.originTurn = t2 and m3.mtarget = R2        // R1 -> R2 (forward)
    t3.inducingMsg = m3
    ResEff in filtAt[R2, m3.originTurn]
    one Occurrence and Occurrence.inTurn = t3     // effect FREE, in R2's turn
  }
}
run ChainSat { ChainSetup and V11Contract }
  for 8 but 3 Turn, 3 Msg, 1 Occurrence, 0 Res
assert Chain_prevents_escalation { ChainSetup and V11Contract implies NE }
check Chain_prevents_escalation for 8 but 3 Turn, 3 Msg, 1 Occurrence, 0 Res

// ---------- Variant B: resolver-invoked caretaker (memo 5.5) ----------
// R's turn induced by a captured resolver rather than a fresh send; Guard
// reads the CAPTURED context's meet. Effect FREE.
// NOTE (v1: self-contradictory — kept in the log as a modeling lesson):
// the first cut set `k.createdIn = t1` (G's turn) AND `k.host = R`, but
// ResRule forces host = createdIn.actor, i.e. R = G. UNSAT at every scope.
// Correct shape: R creates the resolver in R's OWN turn, then resumes under
// the captured (narrow) context. ResRule also needs an invoker turn strictly
// between creation and resume ⇒ four turns.
pred ResolverSetup {
  G not in Trusted
  CU in Underlying and CU.denotes = ResEff
  all c: Cap - CU | ResEff not in c.denotes
  some disj t1, t2, t3, t4: Turn, disj m1, m2, m3: Msg, k: Res {
    Turn = t1 + t2 + t3 + t4 and Msg = m1 + m2 + m3 and Res = k
    lt[t1, t2] and lt[t2, t3] and lt[t3, t4]
    // t1: G services P's narrow request
    no m1.originTurn and m1.msender = P and m1.mtarget = G
    m1.mctx.attBound = XEff
    t1.inducingMsg = m1
    // t2: R's turn from G's send; R creates the resolver HERE
    m2.originTurn = t1 and m2.mtarget = R
    t2.inducingMsg = m2
    k.createdIn = t2          // ⇒ k.host = R, k.captured = t2.tctx (narrow)
    // t3: intervening invoker turn (ResRule)
    no m3.originTurn and m3.mtarget = G
    t3.inducingMsg = m3
    // t4: R resumes under the CAPTURED narrow context
    t4.inducingRes = k
    ResEff in filtAt[R, t2]
    one Occurrence and Occurrence.inTurn = t4    // effect FREE
  }
}
run ResolverSat { ResolverSetup and V11Contract }
  for 8 but 4 Turn, 3 Msg, 1 Res, 1 Occurrence
assert Resolver_prevents_escalation { ResolverSetup and V11Contract implies NE }
check Resolver_prevents_escalation for 8 but 4 Turn, 3 Msg, 1 Res, 1 Occurrence

// FLAG for v1.1 (definitional gap, surfaced by encoding variant B):
// ForwardFiltered is guarded by `some o.inTurn.inducingMsg`, so it is
// VACUOUS on resolver-induced turns — the filter is never consulted when a
// caretaker resumes via a captured continuation. NE still holds there (Guard
// is unconditional on trusted performers), but REVOCATION EFFECTIVENESS (T4)
// may not: weak revocation is defined via "the issuance turn" =
// inducingMsg.originTurn, which does not exist for resolver-induced turns.
// v1.0 §6 never says which turn licenses a resumed forward. Resolve in v1.1
// (candidate: issuance = the resolver's creation turn) and re-check T4.

// ---------- Guarded-perform precision (memo 5.6, condensed) ----------
// An untrusted component's own guarded perform within a conferring chain is
// clean; the same effect outside the chain is flagged. (B2 restated on the
// guarded path.)
one sig S extends Component {}
one sig AEff, BEff extends Effect {}
pred GuardedClean {
  S not in Trusted
  some t: Turn, m: Msg, o: Occurrence {
    Turn = t and Msg = m and Occurrence = o and no Res
    no m.originTurn and m.mtarget = S
    m.mctx.attBound = AEff + BEff
    t.inducingMsg = m
    o.oeff = AEff and o.inTurn = t
  }
}
run GuardedCleanSat { GuardedClean and Guard } for 6 but 1 Turn, 1 Msg, 1 Occurrence, 0 Res
assert GuardedClean_ok { GuardedClean and Guard implies NE }
check GuardedClean_ok for 6 but 1 Turn, 1 Msg, 1 Occurrence, 0 Res

// ================= Resolver-issuance discrimination (memo C1-C3) =================
// Which turn licenses a caretaker forward when its turn is resolver-induced?
// (i) creation turn  (ii) invoker turn [ADOPTED]  (iii) resume turn.

pred FF_creation {          // (i)
  all R: Caretaker, o: Occurrence | o.inTurn.actor = R implies
    ((some o.inTurn.inducingMsg)
       implies o.oeff in filtAt[R, o.inTurn.inducingMsg.originTurn]
       else    o.oeff in filtAt[R, o.inTurn.inducingRes.createdIn])
}
pred FF_invoker {           // (ii) — uniform triggering-turn rule
  all R: Caretaker, o: Occurrence | o.inTurn.actor = R implies
    o.oeff in filtAt[R, issuance[o.inTurn]]
}

// CaptureBeforeRevoke: resolver created while the filter is open, INVOKED
// after the filter has narrowed. Effect FREE (Alloy searches).
pred CaptureBeforeRevoke {
  G not in Trusted
  CU in Underlying and CU.denotes = ResEff
  all c: Cap - CU | ResEff not in c.denotes
  some disj t1, t2, t3, t4: Turn, disj m1, m2, m3: Msg, k: Res {
    Turn = t1 + t2 + t3 + t4 and Msg = m1 + m2 + m3 and Res = k
    lt[t1, t2] and lt[t2, t3] and lt[t3, t4]
    no m1.originTurn and m1.msender = P and m1.mtarget = G
    m1.mctx.attBound = XEff + ResEff        // conferral covers ResEff: isolate the FILTER question
    t1.inducingMsg = m1
    m2.originTurn = t1 and m2.mtarget = R
    t2.inducingMsg = m2
    k.createdIn = t2                        // created while filter is open
    ResEff in filtAt[R, t2]
    no m3.originTurn and m3.mtarget = G
    t3.inducingMsg = m3
    t3.invokesRes = k                       // G cashes the continuation...
    ResEff not in filtAt[R, t3]             // ...AFTER revocation
    t4.inducingRes = k
    one Occurrence and Occurrence.inTurn = t4
    Occurrence.oeff = ResEff                // did the revoked effect get through?
  }
}

// C1: under creation-turn licensing the bypass EXISTS. Expect SAT (the hole).
run C1_creation_admits_bypass { CaptureBeforeRevoke and Membrane and Guard and FF_creation }
  for 8 but 4 Turn, 3 Msg, 1 Res, 1 Occurrence

// C2: under invoker-turn licensing it does NOT. Expect UNSAT (bypass closed).
run C2_invoker_blocks_bypass { CaptureBeforeRevoke and Membrane and Guard and FF_invoker }
  for 8 but 4 Turn, 3 Msg, 1 Res, 1 Occurrence

// C3: non-vacuity for (ii) — a resolver-triggered forward whose INVOCATION
// precedes narrowing is still permitted. Expect SAT (no over-blocking).
pred ResumeBeforeRevoke {
  G not in Trusted
  CU in Underlying and CU.denotes = ResEff
  all c: Cap - CU | ResEff not in c.denotes
  some disj t1, t2, t3, t4: Turn, disj m1, m2, m3: Msg, k: Res {
    Turn = t1 + t2 + t3 + t4 and Msg = m1 + m2 + m3 and Res = k
    lt[t1, t2] and lt[t2, t3] and lt[t3, t4]
    no m1.originTurn and m1.msender = P and m1.mtarget = G
    m1.mctx.attBound = XEff + ResEff
    t1.inducingMsg = m1
    m2.originTurn = t1 and m2.mtarget = R
    t2.inducingMsg = m2
    k.createdIn = t2
    no m3.originTurn and m3.mtarget = G
    t3.inducingMsg = m3
    t3.invokesRes = k
    ResEff in filtAt[R, t3]                 // invocation PRECEDES narrowing
    t4.inducingRes = k
    one Occurrence and Occurrence.inTurn = t4
    Occurrence.oeff = ResEff
  }
}
run C3_invoker_not_overblocking { ResumeBeforeRevoke and Membrane and Guard and FF_invoker }
  for 8 but 4 Turn, 3 Msg, 1 Res, 1 Occurrence
