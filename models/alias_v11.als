// alias_v11.als — closes the §11 known gap: alias-freedom and revocation
// effectiveness under the REPAIRED (v1.1) caretaker contract.
// v3 verified these against the v1.0 contract only; v4 dropped payloads.
// This file restores dynamic stores (v2 machinery) + v1.1 contracts (Guard
// unified across trusted components; Membrane; monotone filtered forwarding).
//
// Also exhibits a structural fact worth a paper paragraph: Guard and
// Membrane protect DIFFERENT theorems. Guard ⇒ NE; Membrane ⇒ revocation
// effectiveness (T4). A leaked underlying reference held by a GUARDED
// untrusted component defeats revocation WITHOUT violating NE, when the
// chain's conferral covers the effect (run T4_fails_NE_holds, expect SAT).
//
// No resolvers here (0 Res): alias-freedom concerns reference flow through
// payloads; continuations carry no capabilities. Issuance is message-only.
// Standing rules: every scenario witnessed; Msg scope >= Turn scope.

module alias_v11
open util/ordering[Turn]

abstract sig Effect {}
sig Cap { denotes: set Effect }
sig Underlying in Cap {}

abstract sig Component { initCaps: set Cap }
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

sig Msg {
  msender: one Component,
  mtarget: one Component,
  mctx: one Context,
  originTurn: lone Turn,
  payload: set Cap
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

sig Turn { actor: one Component, inducingMsg: one Msg, tctx: one Context }
fact TurnFromMsg {
  all t: Turn {
    t.actor = t.inducingMsg.mtarget
    t.tctx = t.inducingMsg.mctx
    (some t.inducingMsg.originTurn) implies lt[t.inducingMsg.originTurn, t]
  }
  all m: Msg | lone t: Turn | t.inducingMsg = m
}

// Dynamic stores (v2 closed form): initial caps + everything received in
// payloads of messages inducing this component's turns up to t.
fun stor[C: Component, t: Turn]: set Cap {
  C.initCaps +
  { c: Cap | some u: Turn | lte[u, t] and u.actor = C and c in u.inducingMsg.payload }
}
fact PayloadFromStore {
  all m: Msg {
    (some m.originTurn) implies m.payload in stor[m.msender, m.originTurn]
    else m.payload in m.msender.initCaps
  }
}

sig Occurrence { oeff: one Effect, inTurn: one Turn }
fact EffectsNeedCaps {
  all o: Occurrence | o.oeff in stor[o.inTurn.actor, o.inTurn].denotes
}
fun effbound[o: Occurrence]: set Effect { o.inTurn.tctx.meetSet }
pred NE { all o: Occurrence | o.oeff in effbound[o] }

// ---- v1.1 contracts ----
pred GuardAll {           // guarded semantics for untrusted + Guard for trusted:
  all o: Occurrence | o.oeff in effbound[o]     // every performer effbound-checked
}
// (Encoding note: in the mixed system both classes end up effbound-checked —
// untrusted by the semantics, trusted by contract — so one predicate serves.)
pred Membrane {
  all m: Msg | m.msender in Caretaker implies no (m.payload & Underlying)
}
pred FFiltered {          // v1.1: filter licensed at issuance (message-only here)
  all R: Caretaker, o: Occurrence | o.inTurn.actor = R implies
    o.oeff in filtAt[R, o.inTurn.inducingMsg.originTurn]
}
pred V11 { GuardAll and Membrane and FFiltered }

// ---- Cast and setup ----
one sig P, G extends Component {}
one sig R0 extends Caretaker {}
one sig XEff, ResEff extends Effect {}
one sig CU extends Cap {}

pred Setup {
  G not in Trusted
  CU in Underlying and CU.denotes = ResEff
  all c: Cap - CU | ResEff not in c.denotes
  CU in R0.initCaps
  all C: Component - R0 | CU not in C.initCaps      // initial alias-freedom for CU
  all m: Msg | m.mtarget = R0 implies some m.originTurn
}

run AV_SetupSat { Setup and V11 } for 8 but 5 Turn, 5 Msg, 3 Occurrence
run AV_Live { Setup and V11 and some o: Occurrence | o.oeff = ResEff }
  for 8 but 5 Turn, 5 Msg, 3 Occurrence

pred InitConfined[c: Cap] { all C: Component - Caretaker | c not in C.initCaps }

// Gap-closure 1: alias PRESERVATION under the repaired contract.
assert AV_AliasPreserved {
  (Setup and V11) implies
    all c: Underlying | InitConfined[c] implies
      all t: Turn, C: Component - Caretaker | c not in stor[C, t]
}
check AV_AliasPreserved for 8 but 5 Turn, 5 Msg, 3 Occurrence

// Gap-closure 2: effectiveness under the repaired contract — every resource
// effect is performed by the caretaker and licensed at issuance.
assert AV_Effectiveness {
  (Setup and V11) implies
    all o: Occurrence | o.oeff = ResEff implies {
      o.inTurn.actor = R0
      o.oeff in filtAt[R0, o.inTurn.inducingMsg.originTurn]
    }
}
check AV_Effectiveness for 8 but 5 Turn, 5 Msg, 3 Occurrence

// The structural point: Guard does NOT substitute for Membrane.
// Membrane violated, GuardAll intact, conferral wide → the leaked reference
// yields a post-clear resource effect by G — T4 defeated — while NE HOLDS.
run T4_fails_NE_holds {
  Setup and GuardAll and FFiltered and not Membrane
  NE
  some o: Occurrence {
    o.oeff = ResEff
    o.inTurn.actor = G
    ResEff not in filtAt[R0, o.inTurn]      // after the filter cleared
  }
} for 8 but 5 Turn, 5 Msg, 3 Occurrence
