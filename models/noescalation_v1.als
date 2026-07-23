// noescalation_v1.als — Alloy model of the v0.3 turn semantics (kernel)
// Covers: context propagation rules 1-3,5 (§2), NE and projections (§5),
//         checklist items 7a, 7b, 1, 2 (§11).
// Deferred to v2: reference/capability transmission (benchmark 3, membrane),
//         dynamic stores, monotone B, caretaker filters, spawn (rule 4).
// Run in Alloy Analyzer 6, classic mode (no `var` used).

module noescalation_v1
open util/ordering[Turn]

// ---------- Kernel ----------

abstract sig Effect {}

sig Cap { denotes: set Effect }

abstract sig Component {
  compBound: set Effect,   // B(C); static in v1 (no attenuation steps yet)
  holds: set Cap           // store; static in v1
}

sig Context {
  parent: lone Context,
  extender: one Component,
  attBound: set Effect,    // beta attached at this hop (root bound if no parent)
  attribSet: set Component, // derived: components along the chain
  meetSet: set Effect       // derived: running meet of attached bounds
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
  originTurn: lone Turn    // none = root message (rule 5)
}

sig Resolver {
  rhost: one Component,    // where the continuation runs
  captured: one Context,   // rule 3: creation turn's context
  createdIn: one Turn
}

sig Turn {
  actor: one Component,
  inducingMsg: lone Message,
  inducingRes: lone Resolver,
  tctx: one Context,
  invokesRes: lone Resolver // resolver invoked during this turn
}

// Exactly one inducer per turn
fact TurnInducer {
  all t: Turn | (some t.inducingMsg) iff (no t.inducingRes)
}

// Rule 2 + rule 5: message contexts
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

// Rule 1: message-induced turns adopt the message's context; causality
fact TurnFromMessage {
  all t: Turn | some t.inducingMsg implies {
    t.actor = t.inducingMsg.mtarget
    t.tctx = t.inducingMsg.mctx
    (some t.inducingMsg.originTurn) implies lt[t.inducingMsg.originTurn, t]
  }
  all m: Message | lone t: Turn | t.inducingMsg = m
}

// Rule 3 (common part): resolver creation, linearity, causality
fact Resolvers {
  all r: Resolver {
    r.captured = r.createdIn.tctx
    r.rhost = r.createdIn.actor
  }
  all r: Resolver | lone t: Turn | t.invokesRes = r      // linear: invoked at most once
  all r: Resolver | lone t: Turn | t.inducingRes = r     // induces at most one turn
  all t: Turn | some t.inducingRes implies {
    t.actor = t.inducingRes.rhost
    some inv: Turn {
      inv.invokesRes = t.inducingRes
      lt[t.inducingRes.createdIn, inv]
      lt[inv, t]
    }
  }
}

// ---------- The two semantics for resolver-induced turns ----------

pred CaptureMode {  // v0.3 rule 3
  all t: Turn | some t.inducingRes implies t.tctx = t.inducingRes.captured
}
pred NaiveMode {    // refuted reply-as-ordinary-send (memo D5)
  all t: Turn | some t.inducingRes implies {
    some inv: Turn {
      inv.invokesRes = t.inducingRes
      t.tctx.parent = inv.tctx
      t.tctx.extender = inv.actor
    }
  }
}

// ---------- Occurrences and the property ----------

sig Occurrence { oeff: one Effect, inTurn: one Turn }

fact EffectsNeedCaps {  // shadow of A1/A2 at v1 granularity
  all o: Occurrence | o.oeff in o.inTurn.actor.holds.denotes
}

fun effbound[o: Occurrence]: set Effect {
  o.inTurn.actor.compBound & o.inTurn.tctx.meetSet
}
pred NE        { all o: Occurrence | o.oeff in effbound[o] }               // §5, unified
pred NE_perf   { all o: Occurrence | o.oeff in o.inTurn.actor.compBound }  // performer-only strawman

// ---------- D5 scenario (checklist 7a / 7b) ----------
// A confers rw(/project) ~ {ListSrc, WriteProj}. C1 sub-requests a listing
// from E with beta = {ListSrc}, resumes via resolver k, performs the write.

one sig A0, C10, E0 extends Component {}
one sig ListSrc, WriteProj extends Effect {}

pred D5Scenario {
  A0.compBound  = ListSrc + WriteProj
  C10.compBound = ListSrc + WriteProj
  E0.compBound  = ListSrc
  some cw, cl: Cap {
    cw.denotes = ListSrc + WriteProj and cw in C10.holds
    cl.denotes = ListSrc and cl in E0.holds
  }
  some disj t1, t2, t3: Turn, disj r1, r2: Message, k: Resolver,
       disj oL, oW: Occurrence {
    Turn = t1 + t2 + t3
    Message = r1 + r2
    Resolver = k
    Occurrence = oL + oW
    lt[t1, t2] and lt[t2, t3]
    // r1: root request A -> C1, beta1 = rw(/project)
    no r1.originTurn and r1.msender = A0 and r1.mtarget = C10
    r1.mctx.attBound = ListSrc + WriteProj
    t1.inducingMsg = r1
    // t1: C1 creates k, sends r2 to E with beta2 = {ListSrc}
    k.createdIn = t1
    r2.originTurn = t1 and r2.mtarget = E0
    r2.mctx.attBound = ListSrc
    t2.inducingMsg = r2
    // t2: E performs the listing, invokes k
    oL.oeff = ListSrc and oL.inTurn = t2
    t2.invokesRes = k
    // t3: C1 resumes, performs the write (r1's conferred work)
    t3.inducingRes = k
    oW.oeff = WriteProj and oW.inTurn = t3
    no t1.invokesRes and no t3.invokesRes
  }
}

// 7a: under naive reply semantics the legitimate write is ALWAYS flagged
//     (motivating counterexample #3: the deputy fix over-fires).
//     Expect: NO counterexample (claim is valid).
assert D5_NaiveAlwaysFlags { (D5Scenario and NaiveMode) implies not NE }
check D5_NaiveAlwaysFlags for 8 but 3 Turn, 2 Message, 1 Resolver, 2 Occurrence

//     Visualize one naive instance (expect: instance found):
run D5_NaiveInstance { D5Scenario and NaiveMode } for 8 but 3 Turn, 2 Message, 1 Resolver, 2 Occurrence

// 7b: under continuation capture the whole scenario satisfies NE.
//     Expect: NO counterexample.
assert D5_CaptureClean { (D5Scenario and CaptureMode) implies NE }
check D5_CaptureClean for 8 but 3 Turn, 2 Message, 1 Resolver, 2 Occurrence

// ---------- Benchmark 1: confused deputy (checklist 1, 2) ----------
// A (bound = TmpRead) confers only TmpRead; deputy C1b holds ambient EtcWrite
// authority and performs the write while servicing A's request.

one sig A1b, C1b extends Component {}
one sig TmpRead, EtcWrite extends Effect {}

pred B1Scenario {
  A1b.compBound = TmpRead
  C1b.compBound = TmpRead + EtcWrite       // deputy's own bound permits the write
  some ct: Cap { ct.denotes = EtcWrite and ct in C1b.holds }
  some t: Turn, m: Message, o: Occurrence {
    Turn = t and Message = m and Occurrence = o and no Resolver
    no m.originTurn and m.msender = A1b and m.mtarget = C1b
    m.mctx.attBound = TmpRead              // what A confers
    t.inducingMsg = m
    o.oeff = EtcWrite and o.inTurn = t
    no t.invokesRes
  }
}

// Checklist 1: performer-only attribution certifies the attacked run.
//   Expect: NO counterexample (the attack is invisible to NE_perf) —
//   this validity IS motivating counterexample #1.
assert B1_InvisibleToPerf { B1Scenario implies NE_perf }
check B1_InvisibleToPerf for 6 but 1 Turn, 1 Message, 1 Occurrence

// Checklist 2: chain attribution flags it. Expect: NO counterexample.
assert B1_ChainFlags { B1Scenario implies not NE }
check B1_ChainFlags for 6 but 1 Turn, 1 Message, 1 Occurrence

// ---------- Benchmark 2: re-amplification, shared service (checklist 3) ----------
// S legitimately holds src authority (from P's world) and docs authority
// (conferred by Q). P attaches beta = {SrcRW}. S writes docs during P's chain.

one sig P0, Q0, S0 extends Component {}
one sig SrcRW, DocsRW extends Effect {}

pred B2Common {
  S0.compBound = SrcRW + DocsRW
  some cs, cd: Cap {
    cs.denotes = SrcRW and cd.denotes = DocsRW
    (cs + cd) in S0.holds
  }
}
pred B2AttackP {  // docs write inside P's src-scoped chain
  B2Common
  some t: Turn, m: Message, o: Occurrence {
    Turn = t and Message = m and Occurrence = o and no Resolver
    no m.originTurn and m.msender = P0 and m.mtarget = S0
    m.mctx.attBound = SrcRW
    t.inducingMsg = m
    o.oeff = DocsRW and o.inTurn = t
    no t.invokesRes
  }
}
pred B2LegitQ {   // same write inside Q's docs-scoped chain
  B2Common
  some t: Turn, m: Message, o: Occurrence {
    Turn = t and Message = m and Occurrence = o and no Resolver
    no m.originTurn and m.msender = Q0 and m.mtarget = S0
    m.mctx.attBound = DocsRW
    t.inducingMsg = m
    o.oeff = DocsRW and o.inTurn = t
    no t.invokesRes
  }
}

// Motivating counterexample #2: performer-only certifies the attack.
assert B2_InvisibleToPerf { B2AttackP implies NE_perf }
check B2_InvisibleToPerf for 6 but 1 Turn, 1 Message, 1 Occurrence

// Attached bounds flag the attack...
assert B2_AttachedFlags { B2AttackP implies not NE }
check B2_AttachedFlags for 6 but 1 Turn, 1 Message, 1 Occurrence

// ...and do NOT flag the same effect under Q's legitimate conferral (precision).
assert B2_LegitClean { B2LegitQ implies NE }
check B2_LegitClean for 6 but 1 Turn, 1 Message, 1 Occurrence

// ---------- Sanity: the kernel admits nonempty capture-mode executions ----------
run KernelSane { CaptureMode and some Occurrence and NE } for 6
