// caretaker_finding.als — isolates memo item 5.2.
// QUESTION: does the v1.0 caretaker contract (Membrane + monotone filtered
// forwarding, NO Guard) admit an NE violation? If SAT, motivating
// counterexample #4 is real and the v1.1 restatement is warranted. If UNSAT,
// the finding is wrong and the memo goes back.
//
// Faithfulness discipline: the caretaker's contract is encoded LITERALLY as
// filter-check-only. NE is checked as a genuine assertion. The violating
// trace is NOT scripted — Alloy searches for it. Scope pinned; every
// scenario predicate carries a satisfiability witness (standing rule 1).

module caretaker_finding
open util/ordering[Turn]

abstract sig Effect {}
sig Cap { denotes: set Effect }
sig Underlying in Cap {}

abstract sig Component {}
abstract sig Caretaker extends Component { filter: Effect -> Turn }
fun filtAt[R: Caretaker, t: Turn]: set Effect { R.filter.t }

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
  inducingMsg: one Msg,
  tctx: one Context
}
fact TurnFromMsg {
  all t: Turn {
    t.actor = t.inducingMsg.mtarget
    t.tctx = t.inducingMsg.mctx
    (some t.inducingMsg.originTurn) implies lt[t.inducingMsg.originTurn, t]
  }
  all m: Msg | lone t: Turn | t.inducingMsg = m
}

sig Occurrence { oeff: one Effect, inTurn: one Turn }

// Component bounds (maximal here — the leak is a MEET failure, not a bound
// failure, so bounds are deliberately permissive to isolate the cause).
fun effbound[o: Occurrence]: set Effect { o.inTurn.tctx.meetSet }
pred NE { all o: Occurrence | o.oeff in effbound[o] }

// ---- v1.0 caretaker contract, encoded LITERALLY (the code under test) ----
pred Membrane {                 // never emit the underlying reference
  all m: Msg | m.msender in Caretaker implies no Underlying  // no payloads here; vacuously ok
}
pred ForwardFiltered {          // performs by a caretaker pass its filter — NO effbound
  all R: Caretaker, o: Occurrence | o.inTurn.actor = R implies
    o.oeff in filtAt[R, o.inTurn.inducingMsg.originTurn]
}
pred V10CaretakerContract { Membrane and ForwardFiltered }

// ---- The setup: one principal, one untrusted deputy, one caretaker ----
one sig P, G extends Component {}        // P principal, G untrusted
one sig R extends Caretaker {}
one sig XEff, ResEff extends Effect {}   // XEff conferred; ResEff is the resource
one sig CU extends Cap {}

pred Setup {
  CU in Underlying and CU.denotes = ResEff
  all c: Cap - CU | ResEff not in c.denotes
  // P confers only XEff to G; G routes a request to R; R's filter still holds ResEff.
  some disj t1, t2: Turn, disj m1, m2: Msg, o: Occurrence {
    Turn = t1 + t2 and Msg = m1 + m2 and Occurrence = o
    lt[t1, t2]
    // m1: P -> G, root, narrow conferral {XEff}
    no m1.originTurn and m1.msender = P and m1.mtarget = G
    m1.mctx.attBound = XEff
    t1.inducingMsg = m1
    // m2: G -> R, sent during t1 (unguarded send), extends the chain
    m2.originTurn = t1 and m2.mtarget = R
    t2.inducingMsg = m2
    // R's filter permits ResEff at m2's issuance turn (not yet revoked)
    ResEff in filtAt[R, m2.originTurn]
    // R performs the resource effect
    o.oeff = ResEff and o.inTurn = t2
  }
}

// Non-vacuity: the setup, WITH the v1.0 contract satisfied, has instances.
run SetupSat { Setup and V10CaretakerContract }
  for 8 but 2 Turn, 2 Msg, 1 Occurrence

// THE QUESTION: under the v1.0 contract, can NE fail?
// Expect: counterexample FOUND (assertion invalid) ⇒ finding real.
assert V10_prevents_escalation { (Setup and V10CaretakerContract) implies NE }
check V10_prevents_escalation for 8 but 2 Turn, 2 Msg, 1 Occurrence

// Control: the REPAIRED contract adds Guard. Expect NE to hold.
pred Guard { all o: Occurrence | o.oeff in effbound[o] }  // performer checks meet
pred RepairedContract { Membrane and ForwardFiltered and Guard }
run RepairedSat { Setup and RepairedContract }
  for 8 but 2 Turn, 2 Msg, 1 Occurrence   // may be UNSAT if repair blocks THIS trace — see note
assert Repaired_prevents_escalation { (Setup and RepairedContract) implies NE }
check Repaired_prevents_escalation for 8 but 2 Turn, 2 Msg, 1 Occurrence
