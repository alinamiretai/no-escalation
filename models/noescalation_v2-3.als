// noescalation_v2.als — v0.3 semantics with dynamic stores and caretakers
// New in v2: reference passing (payloads), turn-indexed stores, caretaker
//   filters (monotone), Membrane, alias-freedom, weak-revocation licensing.
// Covers checklist: 3 (retention), 4 (handoff vs forwarding caretaker),
//   5 (retention + temporal closure), 8 (filter effectiveness); plus the
//   full v1 suite ported as regression (1, 2, 7a, 7b).
// Deferred to v3: spawn (check 9), monotone compBound / attenuation steps
//   (check 10), turn-splitting for finer linearization semantics.
// STANDING RULE 1: every scenario predicate has an adjacent `run` witnessing
//   satisfiability. A green `check` board means nothing without them.
// STANDING RULE 2: util/ordering[Turn] makes the Turn scope EXACT, and every
//   turn needs an inducer, so: Message scope >= Turn scope - (resolver-induced
//   turns available). Violating this makes scenarios UNSAT and checks vacuous
//   (this exact bug shipped in the first cut of this file; rule 1 caught it).

module noescalation_v2
open util/ordering[Turn]

// ---------- Kernel ----------

abstract sig Effect {}

sig Cap { denotes: set Effect }
sig Underlying in Cap {}          // caps designating revocable resources

abstract sig Component {
  compBound: set Effect,
  initCaps: set Cap               // store at the start; growth via payloads
}
abstract sig Caretaker extends Component {
  filter: Effect -> Turn          // e in filter.t : allowed at turn t
}
fun filtAt[R: Caretaker, t: Turn]: set Effect { R.filter.t }
fact FilterMonotone {
  all R: Caretaker, t: Turn - first | filtAt[R, t] in filtAt[R, prev[t]]
}

sig Context {
  parent: lone Context,
  extender: one Component,
  attBound: set Effect,
  attribSet: set Component,
  meetSet: set Effect
}
fact ContextAcyclic { no c: Context | c in c.^parent }
fact ContextDerived {
  all c: Context {
    (no c.parent) implies
      { c.attribSet = c.extender and c.meetSet = c.attBound }
    else
      { c.attribSet = c.parent.attribSet + c.extender
        and c.meetSet = c.parent.meetSet & c.attBound }
  }
}

sig Message {
  msender: one Component,
  mtarget: one Component,
  mctx: one Context,
  originTurn: lone Turn,
  payload: set Cap                // NEW: reference transmission
}

sig Resolver {
  rhost: one Component,
  captured: one Context,
  createdIn: one Turn
}

sig Turn {
  actor: one Component,
  inducingMsg: lone Message,
  inducingRes: lone Resolver,
  tctx: one Context,
  invokesRes: lone Resolver
}
fact TurnInducer { all t: Turn | (some t.inducingMsg) iff (no t.inducingRes) }

fact MessageContext {
  all m: Message {
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
fact TurnFromMessage {
  all t: Turn | some t.inducingMsg implies {
    t.actor = t.inducingMsg.mtarget
    t.tctx = t.inducingMsg.mctx
    (some t.inducingMsg.originTurn) implies lt[t.inducingMsg.originTurn, t]
  }
  all m: Message | lone t: Turn | t.inducingMsg = m
}
fact Resolvers {
  all r: Resolver {
    r.captured = r.createdIn.tctx
    r.rhost = r.createdIn.actor
  }
  all r: Resolver | lone t: Turn | t.invokesRes = r
  all r: Resolver | lone t: Turn | t.inducingRes = r
  all t: Turn | some t.inducingRes implies {
    t.actor = t.inducingRes.rhost
    some inv: Turn {
      inv.invokesRes = t.inducingRes
      lt[t.inducingRes.createdIn, inv]
      lt[inv, t]
    }
  }
}
pred CaptureMode {
  all t: Turn | some t.inducingRes implies t.tctx = t.inducingRes.captured
}
pred NaiveMode {
  all t: Turn | some t.inducingRes implies {
    some inv: Turn {
      inv.invokesRes = t.inducingRes
      t.tctx.parent = inv.tctx
      t.tctx.extender = inv.actor
    }
  }
}

// ---------- Dynamic stores ----------

fun stor[C: Component, t: Turn]: set Cap {
  C.initCaps +
  { c: Cap | some u: Turn | lte[u, t] and u.actor = C and c in u.inducingMsg.payload }
}
fact PayloadFromStore {  // A1 shadow: you can only send what you hold
  all m: Message {
    (some m.originTurn) implies m.payload in stor[m.msender, m.originTurn]
    else m.payload in m.msender.initCaps
  }
}

// ---------- Occurrences and properties ----------

sig Occurrence { oeff: one Effect, inTurn: one Turn }
fact EffectsNeedCaps {
  all o: Occurrence | o.oeff in stor[o.inTurn.actor, o.inTurn].denotes
}
fun effbound[o: Occurrence]: set Effect {
  o.inTurn.actor.compBound & o.inTurn.tctx.meetSet
}
pred NE      { all o: Occurrence | o.oeff in effbound[o] }
pred NE_perf { all o: Occurrence | o.oeff in o.inTurn.actor.compBound }

// ---------- Caretaker contracts (predicates, so violations are runnable) ----------

pred Membrane {  // never emit an underlying reference
  all m: Message | m.msender in Caretaker implies no (m.payload & Underlying)
}
pred ForwardWeak {  // weak revocation: license checked at ISSUANCE of the request
  all R: Caretaker, o: Occurrence | o.inTurn.actor = R implies {
    some o.inTurn.inducingMsg
    o.oeff in filtAt[R, o.inTurn.inducingMsg.originTurn]
  }
}
pred ForwardStrong {  // strong variant: license checked at PERFORMANCE
  all R: Caretaker, o: Occurrence | o.inTurn.actor = R implies
    o.oeff in filtAt[R, o.inTurn]
}
pred AliasFreeAlways {  // the invariant: underlying refs only in caretaker stores
  all t: Turn, C: Component - Caretaker | no (Underlying & stor[C, t])
}

// ---------- Caretaker cast and setup (checks 4, 8) ----------

one sig G0, P0c extends Component {}   // grantee; a principal
one sig R0 extends Caretaker {}
one sig ResEff, OtherEff extends Effect {}
one sig CU extends Cap {}

pred CareSetup {
  CU in Underlying
  CU.denotes = ResEff
  all c: Cap - CU | ResEff not in c.denotes   // only CU reaches the resource
  CU in R0.initCaps
  all C: Component - R0 | CU not in C.initCaps  // initial alias-freedom
  all m: Message | m.mtarget = R0 implies some m.originTurn  // requests, not roots
  no Resolver
}

// Non-vacuity: the setup admits executions, including live legitimate use.
run CareSat  { CareSetup } for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver
run CareLive { CareSetup and ForwardWeak and Membrane and some o: Occurrence | o.oeff = ResEff }
  for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver

pred InitConfined[c: Cap] {  // base case: confined to caretaker stores at start
  all C: Component - Caretaker | c not in C.initCaps
}
// Lemma (mirrors the Lean decomposition): Membrane PRESERVES alias-freedom —
// an underlying reference initially confined to caretaker stores stays
// confined. First cut asserted creation instead of preservation (no base
// case); Alloy refuted it with a stray Underlying cap born in a
// non-caretaker store. The Lean lemma takes exactly this corrected shape.
assert AliasPreserved {
  (CareSetup and Membrane) implies
    all c: Underlying | InitConfined[c] implies
      all t: Turn, C: Component - Caretaker | c not in stor[C, t]
}
check AliasPreserved for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver

// Necessity of ForwardWeak in Effectiveness (Membrane's necessity is already
// witnessed by HandoffAttack): a caretaker ignoring its filter licenses
// nothing — the unlicensed resource effect is reachable.
run RogueForwarder {
  CareSetup and Membrane
  some o: Occurrence {
    o.oeff = ResEff
    o.inTurn.actor = R0
    o.oeff not in filtAt[R0, o.inTurn.inducingMsg.originTurn]
  }
} for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver

// Checklist 8 (weak effectiveness): under both contracts, every resource
// effect is performed by the caretaker and was licensed at issuance.
assert Effectiveness {
  (CareSetup and Membrane and ForwardWeak) implies
    all o: Occurrence | o.oeff = ResEff implies {
      o.inTurn.actor = R0
      o.oeff in filtAt[R0, o.inTurn.inducingMsg.originTurn]
    }
}
check Effectiveness for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver

// Checklist 4, negative half: a handoff caretaker (Membrane violated) admits
// the stale-capability attack — the resource effect fires outside the filter,
// performed by a non-caretaker holding a leaked direct reference.
run HandoffAttack {
  CareSetup and ForwardWeak and not Membrane
  some o: Occurrence {
    o.oeff = ResEff
    o.inTurn.actor != R0
    ResEff not in filtAt[R0, o.inTurn]
  }
} for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver

// Linearization gap: an execution weak revocation permits and strong forbids
// (licensed at issuance, performed after the filter narrowed).
run WeakStrongGap {
  CareSetup and Membrane and ForwardWeak
  some o: Occurrence {
    o.oeff = ResEff
    o.inTurn.actor = R0
    ResEff not in filtAt[R0, o.inTurn]
  }
} for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver

// ---------- Checklist 3 / 5: retention is not escalation ----------
// G1 receives an attenuated cap under P1's chain, retains it, and uses it
// later inside Q1's legitimately wide chain: no NE violation (spatial scope
// respected). Temporal closure of retention is the Effectiveness check above.

one sig P1, Q1, G1 extends Component {}
one sig SomeEff extends Effect {}
one sig CA extends Cap {}

pred RetentionScenario {
  CA.denotes = SomeEff
  CA not in Underlying
  CA in P1.initCaps and CA not in Q1.initCaps and CA not in G1.initCaps
  G1.compBound = SomeEff
  some disj m1, m2: Message, disj t1, t2: Turn, o: Occurrence {
    Turn = t1 + t2 and Message = m1 + m2 and Occurrence = o and no Resolver
    lt[t1, t2]
    no m1.originTurn and m1.msender = P1 and m1.mtarget = G1
    m1.payload = CA and m1.mctx.attBound = SomeEff
    t1.inducingMsg = m1
    no m2.originTurn and m2.msender = Q1 and m2.mtarget = G1
    no m2.payload and m2.mctx.attBound = SomeEff
    t2.inducingMsg = m2
    o.oeff = SomeEff and o.inTurn = t2
    no Turn.invokesRes
  }
}
run RetentionSat { RetentionScenario } for 8 but 2 Turn, 2 Message, 1 Occurrence, 0 Resolver
assert RetentionClean { RetentionScenario implies NE }
check RetentionClean for 8 but 2 Turn, 2 Message, 1 Occurrence, 0 Resolver

// ---------- Regression: v1 suite (static stores via initCaps, no payloads) ----------

one sig A0, C10, E0 extends Component {}
one sig ListSrc, WriteProj extends Effect {}

pred D5Scenario {
  A0.compBound  = ListSrc + WriteProj
  C10.compBound = ListSrc + WriteProj
  E0.compBound  = ListSrc
  some cw, cl: Cap {
    cw.denotes = ListSrc + WriteProj and cw in C10.initCaps
    cl.denotes = ListSrc and cl in E0.initCaps
  }
  no Message.payload
  some disj t1, t2, t3: Turn, disj r1, r2: Message, k: Resolver,
       disj oL, oW: Occurrence {
    Turn = t1 + t2 + t3
    Message = r1 + r2
    Resolver = k
    Occurrence = oL + oW
    lt[t1, t2] and lt[t2, t3]
    no r1.originTurn and r1.msender = A0 and r1.mtarget = C10
    r1.mctx.attBound = ListSrc + WriteProj
    t1.inducingMsg = r1
    k.createdIn = t1
    r2.originTurn = t1 and r2.mtarget = E0
    r2.mctx.attBound = ListSrc
    t2.inducingMsg = r2
    oL.oeff = ListSrc and oL.inTurn = t2
    t2.invokesRes = k
    t3.inducingRes = k
    oW.oeff = WriteProj and oW.inTurn = t3
    no t1.invokesRes and no t3.invokesRes
  }
}
assert D5_NaiveAlwaysFlags { (D5Scenario and NaiveMode) implies not NE }
check D5_NaiveAlwaysFlags for 8 but 3 Turn, 2 Message, 1 Resolver, 2 Occurrence
run D5_NaiveInstance { D5Scenario and NaiveMode } for 8 but 3 Turn, 2 Message, 1 Resolver, 2 Occurrence
assert D5_CaptureClean { (D5Scenario and CaptureMode) implies NE }
check D5_CaptureClean for 8 but 3 Turn, 2 Message, 1 Resolver, 2 Occurrence

one sig A1b, C1b extends Component {}
one sig TmpRead, EtcWrite extends Effect {}

pred B1Scenario {
  A1b.compBound = TmpRead
  C1b.compBound = TmpRead + EtcWrite
  some ct: Cap { ct.denotes = EtcWrite and ct in C1b.initCaps }
  no Message.payload
  some t: Turn, m: Message, o: Occurrence {
    Turn = t and Message = m and Occurrence = o and no Resolver
    no m.originTurn and m.msender = A1b and m.mtarget = C1b
    m.mctx.attBound = TmpRead
    t.inducingMsg = m
    o.oeff = EtcWrite and o.inTurn = t
    no t.invokesRes
  }
}
run B1Sat { B1Scenario } for 6 but 1 Turn, 1 Message, 1 Occurrence, 0 Resolver
assert B1_InvisibleToPerf { B1Scenario implies NE_perf }
check B1_InvisibleToPerf for 6 but 1 Turn, 1 Message, 1 Occurrence, 0 Resolver
assert B1_ChainFlags { B1Scenario implies not NE }
check B1_ChainFlags for 6 but 1 Turn, 1 Message, 1 Occurrence, 0 Resolver

one sig P0b, Q0b, S0b extends Component {}
one sig SrcRW, DocsRW extends Effect {}

pred B2Common {
  S0b.compBound = SrcRW + DocsRW
  some cs, cd: Cap {
    cs.denotes = SrcRW and cd.denotes = DocsRW
    (cs + cd) in S0b.initCaps
  }
  no Message.payload
}
pred B2AttackP {
  B2Common
  some t: Turn, m: Message, o: Occurrence {
    Turn = t and Message = m and Occurrence = o and no Resolver
    no m.originTurn and m.msender = P0b and m.mtarget = S0b
    m.mctx.attBound = SrcRW
    t.inducingMsg = m
    o.oeff = DocsRW and o.inTurn = t
    no t.invokesRes
  }
}
pred B2LegitQ {
  B2Common
  some t: Turn, m: Message, o: Occurrence {
    Turn = t and Message = m and Occurrence = o and no Resolver
    no m.originTurn and m.msender = Q0b and m.mtarget = S0b
    m.mctx.attBound = DocsRW
    t.inducingMsg = m
    o.oeff = DocsRW and o.inTurn = t
    no t.invokesRes
  }
}
run B2AttackSat { B2AttackP } for 6 but 1 Turn, 1 Message, 1 Occurrence, 0 Resolver
run B2LegitSat { B2LegitQ } for 6 but 1 Turn, 1 Message, 1 Occurrence, 0 Resolver
assert B2_InvisibleToPerf { B2AttackP implies NE_perf }
check B2_InvisibleToPerf for 6 but 1 Turn, 1 Message, 1 Occurrence, 0 Resolver
assert B2_AttachedFlags { B2AttackP implies not NE }
check B2_AttachedFlags for 6 but 1 Turn, 1 Message, 1 Occurrence, 0 Resolver
assert B2_LegitClean { B2LegitQ implies NE }
check B2_LegitClean for 6 but 1 Turn, 1 Message, 1 Occurrence, 0 Resolver

// ---------- Kernel sanity ----------
run KernelSane { CaptureMode and some Occurrence and NE } for 6 but 0 Resolver
