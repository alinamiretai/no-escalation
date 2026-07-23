// resolver_issuance.als — standalone discriminator for memo
// `decision-memo-resolver-issuance.md` (checks C1–C3).
//
// QUESTION: when a caretaker's turn is induced by a captured resolver,
// which turn's filter licenses the forward?
//   (i)  creation turn   (ii) invoker turn [proposed]   (iii) resume turn
//
// C1 (i) admits a post-revocation forward  → expect SAT  (the bypass)
// C2 (ii) blocks it                        → expect UNSAT
// C3 (ii) still allows pre-revocation work → expect SAT  (no over-blocking)
//
// C2's UNSAT is meaningful ONLY given C3's SAT (standing rule 1).
// Self-contained: no payloads, no Membrane (untested here by design — see
// the v1.1 suite item on alias-freedom under the repaired contract).

module resolver_issuance
open util/ordering[Turn]

abstract sig Effect {}
sig Cap { denotes: set Effect }
sig Underlying in Cap {}

abstract sig Component {}
sig Trusted in Component {}
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
  invokesRes: lone Res,
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
  all r: Res | lone t: Turn | t.invokesRes = r
  all t: Turn | some t.inducingRes implies {
    t.actor = t.inducingRes.host
    t.tctx = t.inducingRes.captured
    some inv: Turn | inv.invokesRes = t.inducingRes
                     and lt[t.inducingRes.createdIn, inv] and lt[inv, t]
  }
}

// Issuance: the turn of the TRIGGERING action. Exactly one branch is
// non-empty for any turn (TurnInducer), so union is the conditional.
fun issuance[t: Turn]: Turn {
  t.inducingMsg.originTurn + { inv: Turn | inv.invokesRes = t.inducingRes }
}

sig Occurrence { oeff: one Effect, inTurn: one Turn }
fun effbound[o: Occurrence]: set Effect { o.inTurn.tctx.meetSet }
pred NE { all o: Occurrence | o.oeff in effbound[o] }

pred Guard {
  all o: Occurrence | o.inTurn.actor in Trusted implies o.oeff in effbound[o]
}

// (i) creation-turn licensing
pred FF_creation {
  all R: Caretaker, o: Occurrence | o.inTurn.actor = R implies
    ((some o.inTurn.inducingMsg)
       implies o.oeff in filtAt[R, o.inTurn.inducingMsg.originTurn]
       else    o.oeff in filtAt[R, o.inTurn.inducingRes.createdIn])
}
// (ii) invoker-turn licensing — uniform triggering-turn rule
pred FF_invoker {
  all R: Caretaker, o: Occurrence | o.inTurn.actor = R implies
    o.oeff in filtAt[R, issuance[o.inTurn]]
}

one sig P, G extends Component {}
one sig R extends Caretaker {}
one sig XEff, ResEff extends Effect {}
one sig CU extends Cap {}

// Resolver created while the filter is OPEN, invoked AFTER it narrows.
// Conferral deliberately covers ResEff so the FILTER is the only question.
pred CaptureBeforeRevoke {
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
    ResEff in filtAt[R, t2]            // filter open at creation
    no m3.originTurn and m3.mtarget = G
    t3.inducingMsg = m3
    t3.invokesRes = k                  // G cashes the continuation...
    ResEff not in filtAt[R, t3]        // ...after revocation
    t4.inducingRes = k
    one Occurrence and Occurrence.inTurn = t4
    Occurrence.oeff = ResEff
  }
}

// Same, but the INVOCATION precedes narrowing (legitimate resumed work).
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
    ResEff in filtAt[R, t3]            // invocation PRECEDES narrowing
    t4.inducingRes = k
    one Occurrence and Occurrence.inTurn = t4
    Occurrence.oeff = ResEff
  }
}

// C1 — expect SAT: creation-turn licensing admits the post-revocation forward.
run C1_creation_admits_bypass { CaptureBeforeRevoke and Guard and FF_creation }
  for 8 but 4 Turn, 3 Msg, 1 Res, 1 Occurrence

// C2 — expect UNSAT: invoker-turn licensing closes it.
run C2_invoker_blocks_bypass { CaptureBeforeRevoke and Guard and FF_invoker }
  for 8 but 4 Turn, 3 Msg, 1 Res, 1 Occurrence

// C3 — expect SAT: (ii) does not over-block legitimate resumed work.
run C3_invoker_not_overblocking { ResumeBeforeRevoke and Guard and FF_invoker }
  for 8 but 4 Turn, 3 Msg, 1 Res, 1 Occurrence
