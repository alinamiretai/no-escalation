// noescalation_v3.als — v0.3 semantics, final modeling round
// New in v3: spawn (subset sig + creation discipline; contexts need NO new
//   rules — spawn-taint impossibility falls out of message-sited contexts,
//   which is D4's claim made executable), turn-indexed monotone bounds
//   (attenuation steps expressible), wider-beta one-step lemma.
// Covers checklist: 9 (spawn taint), 10 (wider beta; one-step form — the
//   inductive generalization is Lean's job), attenuation-binds companion;
//   plus the full v2 suite (1-5, 7a, 7b, 8, contracts) as regression.
// Remaining for Lean, not Alloy: EA/NE-S invariants, unbounded induction,
//   the composition theorem, turn-splitting linearization refinements.
// STANDING RULE 1: every scenario predicate has an adjacent `run` witnessing
//   satisfiability. A green `check` board means nothing without them.
// STANDING RULE 2: util/ordering[Turn] makes the Turn scope EXACT, and every
//   turn needs an inducer, so: Message scope >= Turn scope - (resolver-induced
//   turns available). Violating this makes scenarios UNSAT and checks vacuous
//   (this exact bug shipped in the first cut of v2; rule 1 caught it).

module noescalation_v3
open util/ordering[Turn]

// ---------- Kernel ----------

abstract sig Effect {}

sig Cap { denotes: set Effect }
sig Underlying in Cap {}

abstract sig Component {
  bound: Effect -> Turn,          // B(C) at each turn; monotone (A4)
  initCaps: set Cap
}
fun bAt[C: Component, t: Turn]: set Effect { C.bound.t }
fact BoundMonotone {
  all C: Component, t: Turn - first | bAt[C, t] in bAt[C, prev[t]]
}

abstract sig Caretaker extends Component {
  filter: Effect -> Turn
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
  payload: set Cap
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

// ---------- Spawn (v0.3 §2 rule 4 / D4) ----------
// Spawn is send-like: the spawn message's context governs the init turn via
// the ordinary TurnFromMessage rule — no new context machinery. New facts:
// creation discipline only.

sig Spawned in Component { spawnedBy: one Message }
fact SpawnSemantics {
  all C: Spawned {
    C.spawnedBy.mtarget = C
    no C.initCaps                     // A2: fresh store = exactly what was passed
    all t: Turn | t.actor = C implies // no activity before the init turn
      { some it: Turn | it.inducingMsg = C.spawnedBy and lte[it, t] }
    all m: Message | m.msender = C implies some m.originTurn  // no root sends
  }
}

// ---------- Dynamic stores ----------

fun stor[C: Component, t: Turn]: set Cap {
  C.initCaps +
  { c: Cap | some u: Turn | lte[u, t] and u.actor = C and c in u.inducingMsg.payload }
}
fact PayloadFromStore {
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
  bAt[o.inTurn.actor, o.inTurn] & o.inTurn.tctx.meetSet
}
pred NE      { all o: Occurrence | o.oeff in effbound[o] }
pred NE_perf { all o: Occurrence | o.oeff in bAt[o.inTurn.actor, o.inTurn] }

// ---------- Checklist 10: wider beta is harmless (one-step lemma) ----------
// A hop whose attached bound contains the parent meet leaves the meet
// unchanged. The full claim — verdict invariance under widening anywhere in
// any chain — follows by induction over Context; that induction is Lean's.

assert WiderBetaHarmless {
  all c: Context | (some c.parent and c.parent.meetSet in c.attBound)
    implies c.meetSet = c.parent.meetSet
}
check WiderBetaHarmless for 8

// ---------- Spawn cast and scenarios (checklist 9) ----------
// K is spawned under a NARROW conferral ({KEff}), receiving a cap for both
// KEff and LEff. Later, an unrelated principal Q2 engages K under a WIDE
// chain ({KEff, LEff}).

one sig P2, Q2, K extends Component {}
one sig KEff, LEff extends Effect {}
one sig CK extends Cap {}

pred SpawnCommon {
  CK.denotes = KEff + LEff
  CK in P2.initCaps
  K in Spawned
  K.bound = (KEff + LEff) -> Turn
  some disj ms, m2: Message, disj t1, t2: Turn {
    Turn = t1 + t2 and Message = ms + m2 and no Resolver
    lt[t1, t2]
    // spawn: root from P2, narrow conferral, cap passed in payload
    no ms.originTurn and ms.msender = P2 and ms.mtarget = K
    ms.payload = CK and ms.mctx.attBound = KEff
    K.spawnedBy = ms
    t1.inducingMsg = ms                // K's initialization turn
    // later, unrelated wide engagement
    no m2.originTurn and m2.msender = Q2 and m2.mtarget = K
    no m2.payload and m2.mctx.attBound = KEff + LEff
    t2.inducingMsg = m2
    no Turn.invokesRes
  }
}
// Variant A — the taint test: K performs LEff in Q2's turn. Judged ONLY by
// Q2's chain (message-sited contexts): no violation. A component-sited or
// spawn-tainting semantics would flag it.
pred SpawnLater { SpawnCommon and some o: Occurrence { Occurrence = o and o.oeff = LEff and o.inTurn = last } }
run SpawnLaterSat { SpawnLater } for 8 but 2 Turn, 2 Message, 1 Occurrence, 0 Resolver
assert SpawnNoTaint { SpawnLater implies NE }
check SpawnNoTaint for 8 but 2 Turn, 2 Message, 1 Occurrence, 0 Resolver

// Variant B — the conferral test: K performs LEff in its INIT turn, outside
// the narrow spawn bound. Must be flagged: spawn conferral binds the init turn.
pred SpawnInit { SpawnCommon and some o: Occurrence { Occurrence = o and o.oeff = LEff and o.inTurn = first } }
run SpawnInitSat { SpawnInit } for 8 but 2 Turn, 2 Message, 1 Occurrence, 0 Resolver
assert SpawnScopeBinds { SpawnInit implies not NE }
check SpawnScopeBinds for 8 but 2 Turn, 2 Message, 1 Occurrence, 0 Resolver

// ---------- Attenuation step (companion to checklist 10; exercises A4) ----------
// Q2's own bound narrows mid-run: {KEff, LEff} at t1, {KEff} at t2. A
// post-narrowing LEff inside a wide chain is flagged by the component bound.

pred NarrowScenario {
  some ck2: Cap { ck2.denotes = KEff + LEff and ck2 in Q2.initCaps }
  some disj t1, t2: Turn, disj m1, m2: Message, o: Occurrence {
    Turn = t1 + t2 and Message = m1 + m2 and Occurrence = o and no Resolver
    lt[t1, t2]
    Q2.bound.t1 = KEff + LEff
    Q2.bound.t2 = KEff
    no m1.originTurn and m1.mtarget = Q2 and m1.mctx.attBound = KEff + LEff
    t1.inducingMsg = m1
    no m2.originTurn and m2.mtarget = Q2 and m2.mctx.attBound = KEff + LEff
    t2.inducingMsg = m2
    o.oeff = LEff and o.inTurn = t2
    no Turn.invokesRes
  }
}
run NarrowSat { NarrowScenario } for 8 but 2 Turn, 2 Message, 1 Occurrence, 0 Resolver
assert AttenuationBinds { NarrowScenario implies not NE }
check AttenuationBinds for 8 but 2 Turn, 2 Message, 1 Occurrence, 0 Resolver

// ---------- Item 6b: operator-turn housekeeping precision ----------
// (Closes §11 item 6 per decision-memo-item6-housekeeping.md, D3/D4.)
// Deputy D6 holds own caps for deputized work (WorkEff) and housekeeping
// (HkEff). At t1 it services a narrow client chain, performing only the
// conferred work. At t2 it performs its housekeeping in an OPERATOR-induced
// turn whose conferral covers HkEff. Both accountings hold in one trace.

one sig Op6, P6, D6 extends Component {}
one sig WorkEff, HkEff extends Effect {}
one sig CW, CH extends Cap {}

pred Op6Common {
  CW.denotes = WorkEff
  CH.denotes = HkEff
  (CW + CH) in D6.initCaps
  D6.bound = (WorkEff + HkEff) -> Turn
}
pred OperatorTurnScenario {
  Op6Common
  some disj m1, m2: Message, disj t1, t2: Turn, disj o1, o2: Occurrence {
    Turn = t1 + t2 and Message = m1 + m2 and Occurrence = o1 + o2 and no Resolver
    lt[t1, t2]
    // t1: narrow client chain; deputy performs only the conferred work
    no m1.originTurn and m1.msender = P6 and m1.mtarget = D6
    m1.mctx.attBound = WorkEff
    t1.inducingMsg = m1
    o1.oeff = WorkEff and o1.inTurn = t1
    // t2: operator-induced turn; conferral covers housekeeping
    no m2.originTurn and m2.msender = Op6 and m2.mtarget = D6
    m2.mctx.attBound = WorkEff + HkEff
    t2.inducingMsg = m2
    o2.oeff = HkEff and o2.inTurn = t2
    no Turn.invokesRes
  }
}
run OperatorTurnSat { OperatorTurnScenario } for 8 but 2 Turn, 2 Message, 2 Occurrence, 0 Resolver
assert OperatorTurnClean { OperatorTurnScenario implies NE }
check OperatorTurnClean for 8 but 2 Turn, 2 Message, 2 Occurrence, 0 Resolver

// Local restatement of 6a (structurally = B2_AttackP/B2_AttachedFlags):
// the SAME housekeeping effect inside the narrow REQUEST turn is a true
// positive — cross-chain deputy-owned effects are flagged, by design.
pred HousekeepingInRequest {
  Op6Common
  some m1: Message, t1: Turn, o: Occurrence {
    Turn = t1 and Message = m1 and Occurrence = o and no Resolver
    no m1.originTurn and m1.msender = P6 and m1.mtarget = D6
    m1.mctx.attBound = WorkEff
    t1.inducingMsg = m1
    o.oeff = HkEff and o.inTurn = t1
    no t1.invokesRes
  }
}
run HkInRequestSat { HousekeepingInRequest } for 8 but 1 Turn, 1 Message, 1 Occurrence, 0 Resolver
assert HkInRequestFlagged { HousekeepingInRequest implies not NE }
check HkInRequestFlagged for 8 but 1 Turn, 1 Message, 1 Occurrence, 0 Resolver

// ---------- Caretaker cast and suite (checks 4, 8; regression from v2) ----------

one sig G0, P0c extends Component {}
one sig R0 extends Caretaker {}
one sig ResEff, OtherEff extends Effect {}
one sig CU extends Cap {}

pred CareSetup {
  CU in Underlying
  CU.denotes = ResEff
  all c: Cap - CU | ResEff not in c.denotes
  CU in R0.initCaps
  all C: Component - R0 | CU not in C.initCaps
  all m: Message | m.mtarget = R0 implies some m.originTurn
  no Resolver
}
pred Membrane {
  all m: Message | m.msender in Caretaker implies no (m.payload & Underlying)
}
pred ForwardWeak {
  all R: Caretaker, o: Occurrence | o.inTurn.actor = R implies {
    some o.inTurn.inducingMsg
    o.oeff in filtAt[R, o.inTurn.inducingMsg.originTurn]
  }
}
pred ForwardStrong {
  all R: Caretaker, o: Occurrence | o.inTurn.actor = R implies
    o.oeff in filtAt[R, o.inTurn]
}

run CareSat  { CareSetup } for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver
run CareLive { CareSetup and ForwardWeak and Membrane and some o: Occurrence | o.oeff = ResEff }
  for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver

pred InitConfined[c: Cap] {
  all C: Component - Caretaker | c not in C.initCaps
}
assert AliasPreserved {
  (CareSetup and Membrane) implies
    all c: Underlying | InitConfined[c] implies
      all t: Turn, C: Component - Caretaker | c not in stor[C, t]
}
check AliasPreserved for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver

assert Effectiveness {
  (CareSetup and Membrane and ForwardWeak) implies
    all o: Occurrence | o.oeff = ResEff implies {
      o.inTurn.actor = R0
      o.oeff in filtAt[R0, o.inTurn.inducingMsg.originTurn]
    }
}
check Effectiveness for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver

run HandoffAttack {
  CareSetup and ForwardWeak and not Membrane
  some o: Occurrence {
    o.oeff = ResEff
    o.inTurn.actor != R0
    ResEff not in filtAt[R0, o.inTurn]
  }
} for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver

run RogueForwarder {
  CareSetup and Membrane
  some o: Occurrence {
    o.oeff = ResEff
    o.inTurn.actor = R0
    o.oeff not in filtAt[R0, o.inTurn.inducingMsg.originTurn]
  }
} for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver

run WeakStrongGap {
  CareSetup and Membrane and ForwardWeak
  some o: Occurrence {
    o.oeff = ResEff
    o.inTurn.actor = R0
    ResEff not in filtAt[R0, o.inTurn]
  }
} for 8 but 5 Turn, 5 Message, 3 Occurrence, 0 Resolver

// ---------- Retention (checks 3, 5; regression) ----------

one sig P1, Q1, G1 extends Component {}
one sig SomeEff extends Effect {}
one sig CA extends Cap {}

pred RetentionScenario {
  CA.denotes = SomeEff
  CA not in Underlying
  CA in P1.initCaps and CA not in Q1.initCaps and CA not in G1.initCaps
  G1.bound = SomeEff -> Turn
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

// ---------- D5 / Benchmarks 1-2 (regression) ----------

one sig A0, C10, E0 extends Component {}
one sig ListSrc, WriteProj extends Effect {}

pred D5Scenario {
  A0.bound  = (ListSrc + WriteProj) -> Turn
  C10.bound = (ListSrc + WriteProj) -> Turn
  E0.bound  = ListSrc -> Turn
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
  A1b.bound = TmpRead -> Turn
  C1b.bound = (TmpRead + EtcWrite) -> Turn
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
  S0b.bound = (SrcRW + DocsRW) -> Turn
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
