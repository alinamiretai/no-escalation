#!/usr/bin/env python3
"""
provenance.py — the io.noescalation data model and pi construction.

This is the verified schema (provenance-schema.md) as code. Every structure
here corresponds to something in the Lean development:
  Constraint  ~ an argument-level predicate
  Rule        ~ one allowed (tool, args) shape
  Bound       ~ a beta: a set of effects, encoded as a union of rules
  Chain (pi)  ~ Ctx: the sequence of (component, bound) hops
  effbound    ~ B(performer) intersect the meet of the chain

MEET, the load-bearing operation (verified against Kernel.lean:55, pointwise
conjunction across hops):
  - within a bound: UNION of rules (a call matches iff it matches SOME rule)
  - across hops:    INTERSECTION of bounds (a call is allowed iff EVERY hop
                    admits it)
Do not conflate the two levels.

Operators are {eq, in, prefix, glob} — closed under intersection, so the meet
stays in the language. (regex is excluded: two regexes don't intersect to a
regex. range is excluded: no authority-bearing numeric argument exists in the
target tools; page/perPage are resource limits, identifiers are strings'
companions.)

Stage 1a uses only the construction half (build a chain, put it in _meta).
The checking half (meet + membership) is here too, unit-tested at the bottom,
so stage 1b is just wiring it into the proxy.
"""

from __future__ import annotations
import fnmatch
from dataclasses import dataclass, field
from typing import Any


META_KEY = "io.noescalation/provenance"


# --------------------------------------------------------------------------
# Constraints: argument-level predicates. Each is closed under intersection.
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class Constraint:
    op: str            # "eq" | "in" | "prefix" | "glob"
    value: Any         # scalar for eq/prefix/glob; list for in

    def matches(self, arg_value: Any) -> bool:
        if self.op == "eq":
            return arg_value == self.value
        if self.op == "in":
            return arg_value in self.value
        if self.op == "prefix":
            return isinstance(arg_value, str) and arg_value.startswith(self.value)
        if self.op == "glob":
            return isinstance(arg_value, str) and fnmatch.fnmatch(arg_value, self.value)
        raise ValueError(f"unknown op: {self.op}")

    def to_json(self):
        return {self.op: self.value}

    @staticmethod
    def from_json(d: dict) -> "Constraint":
        (op, value), = d.items()
        return Constraint(op, value)


def meet_constraints(a: Constraint, b: Constraint) -> Constraint | None:
    """
    Intersection of two constraints on the same argument, staying in the
    language. Returns None when the intersection is empty (the argument is
    then unsatisfiable, so any rule combining them is dropped).

    Only the cases needed for the target tools are implemented exactly; mixed
    operator pairs fall back to a conservative rule (see NOTE). This is the
    one place where "closed under intersection" is cashed out operationally.
    """
    if a.op == "eq" and b.op == "eq":
        return a if a.value == b.value else None
    if a.op == "in" and b.op == "in":
        common = [v for v in a.value if v in b.value]
        return Constraint("in", common) if common else None
    if a.op == "eq" and b.op == "in":
        return a if a.value in b.value else None
    if a.op == "in" and b.op == "eq":
        return b if b.value in a.value else None
    if a.op == "prefix" and b.op == "prefix":
        # one must extend the other, else disjoint
        if a.value.startswith(b.value):
            return a
        if b.value.startswith(a.value):
            return b
        return None
    if a.op == "eq" and b.op == "prefix":
        return a if str(a.value).startswith(b.value) else None
    if a.op == "prefix" and b.op == "eq":
        return b if str(b.value).startswith(a.value) else None
    # NOTE: glob-involving and other mixed pairs are conservatively treated as
    # "keep the more specific side if it implies the other, else keep both by
    # returning a — refined per real need." For the target tools, authority
    # arguments use eq/in/prefix; glob appears on paths only. Left explicit so
    # the gap is visible rather than silently wrong.
    if a.op == b.op and a.value == b.value:
        return a
    # conservative default: cannot prove non-empty intersection in-language;
    # keep `a` (tighter checking happens at membership time against both is
    # not possible here, so we under-approximate by keeping one side). Flagged.
    return a


# --------------------------------------------------------------------------
# Rules and Bounds
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class Rule:
    tool: str                              # tool name (exact; glob later if needed)
    args: dict[str, Constraint] = field(default_factory=dict)

    def matches(self, tool_name: str, arguments: dict) -> bool:
        if self.tool != tool_name:
            return False
        for arg_name, constraint in self.args.items():
            if arg_name not in arguments:
                return False            # constrained arg absent -> not matched
            if not constraint.matches(arguments[arg_name]):
                return False
        return True                     # unconstrained args are unrestricted

    def to_json(self):
        return {"tool": self.tool,
                "args": {k: v.to_json() for k, v in self.args.items()}}

    @staticmethod
    def from_json(d: dict) -> "Rule":
        return Rule(d["tool"],
                    {k: Constraint.from_json(v) for k, v in d.get("args", {}).items()})


def meet_rules(r1: Rule, r2: Rule) -> Rule | None:
    """Intersect two rules. Different tools -> disjoint. Same tool -> conjoin
    constraints argument-wise; any empty argument intersection drops the rule."""
    if r1.tool != r2.tool:
        return None
    merged: dict[str, Constraint] = {}
    for name in set(r1.args) | set(r2.args):
        c1, c2 = r1.args.get(name), r2.args.get(name)
        if c1 and c2:
            m = meet_constraints(c1, c2)
            if m is None:
                return None             # unsatisfiable argument -> drop rule
            merged[name] = m
        else:
            merged[name] = c1 or c2     # only one side constrains it
    return Rule(r1.tool, merged)


# A Bound is a list of rules: a call is in the bound iff it matches SOME rule.
Bound = list  # list[Rule]


def bound_admits(bound: list[Rule], tool_name: str, arguments: dict) -> bool:
    """Membership in a single bound: UNION of rules."""
    return any(r.matches(tool_name, arguments) for r in bound)


def meet_bounds(b1: list[Rule], b2: list[Rule]) -> list[Rule]:
    """
    Intersection of two bounds: the rule set { meet(r1,r2) } over all pairs,
    dropping empties. This is the ACROSS-HOPS operation and it is where the
    chain's conferrals accumulate.
    """
    out = []
    for r1 in b1:
        for r2 in b2:
            m = meet_rules(r1, r2)
            if m is not None:
                out.append(m)
    return out


# --------------------------------------------------------------------------
# The chain (pi) and effbound
# --------------------------------------------------------------------------

@dataclass
class Hop:
    component: str
    bound: list[Rule]

    def to_json(self):
        return {"component": self.component,
                "bound": [r.to_json() for r in self.bound]}

    @staticmethod
    def from_json(d: dict) -> "Hop":
        return Hop(d["component"], [Rule.from_json(r) for r in d.get("bound", [])])


@dataclass
class Chain:
    """pi: an append-only sequence of hops, oldest first."""
    version: int = 1
    hops: list[Hop] = field(default_factory=list)

    def extend(self, component: str, bound: list[Rule]) -> "Chain":
        """Add a hop. Returns a new Chain (append-only, never mutate history)."""
        return Chain(self.version, self.hops + [Hop(component, bound)])

    def effbound(self) -> list[Rule]:
        """
        B(performer) intersect the meet of all attached bounds = the running
        meet across every hop. Empty chain admits nothing conferred (no hop),
        so we start from the first hop and intersect the rest in.
        """
        if not self.hops:
            return []
        acc = self.hops[0].bound
        for hop in self.hops[1:]:
            acc = meet_bounds(acc, hop.bound)
        return acc

    def admits(self, tool_name: str, arguments: dict) -> bool:
        """Is this call within effbound? The guard's core question."""
        return bound_admits(self.effbound(), tool_name, arguments)

    def to_json(self):
        return {"v": self.version, "chain": [h.to_json() for h in self.hops]}

    @staticmethod
    def from_json(d: dict) -> "Chain":
        return Chain(d.get("v", 1), [Hop.from_json(h) for h in d.get("chain", [])])


def attach_to_meta(message: dict, chain: Chain) -> dict:
    """Put pi into _meta under the reserved key. Returns the modified message."""
    params = message.setdefault("params", {})
    meta = params.setdefault("_meta", {})
    meta[META_KEY] = chain.to_json()
    return message


def read_from_meta(message: dict) -> Chain | None:
    """Recover pi from a message's _meta, or None if absent."""
    meta = message.get("params", {}).get("_meta", {})
    raw = meta.get(META_KEY)
    return Chain.from_json(raw) if raw else None


# --------------------------------------------------------------------------
# Self-test: the schema's own examples, checked. Run `python3 provenance.py`.
# --------------------------------------------------------------------------

if __name__ == "__main__":
    fails = []

    # A host confers "create_issue on acme/app only"; a planner narrows nothing.
    host_bound = [Rule("create_issue", {"repo": Constraint("in", ["acme/app"])})]
    chain = Chain().extend("host", host_bound).extend("planner", host_bound)

    # in-bound call passes
    if not chain.admits("create_issue", {"repo": "acme/app", "title": "x"}):
        fails.append("legit create_issue on acme/app should be admitted")

    # out-of-bound repo rejected (this is Benchmark-2 shaped: right tool, wrong arg)
    if chain.admits("create_issue", {"repo": "evil/app", "title": "x"}):
        fails.append("create_issue on evil/app should be rejected")

    # different tool rejected (nothing conferred it)
    if chain.admits("delete_repo", {"repo": "acme/app"}):
        fails.append("delete_repo should be rejected (not conferred)")

    # narrowing across hops: planner restricts to a sub-repo it doesn't have ->
    # meet is empty for the wider repo, so even acme/app is gone if narrowed away
    narrowed = Chain().extend("host", host_bound).extend(
        "planner", [Rule("create_issue", {"repo": Constraint("in", ["acme/docs"])})])
    if narrowed.admits("create_issue", {"repo": "acme/app", "title": "x"}):
        fails.append("meet across hops should remove acme/app when planner narrows to acme/docs")
    if not narrowed.admits("create_issue", {"repo": "acme/docs", "title": "x"}):
        # acme/docs is in planner's bound but NOT host's -> meet removes it too
        pass  # correct: host never conferred acme/docs, so this SHOULD be rejected
    if narrowed.admits("create_issue", {"repo": "acme/docs", "title": "x"}):
        fails.append("acme/docs was never conferred by host; meet should reject it")

    # round-trip through _meta
    msg = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
           "params": {"name": "create_issue", "arguments": {"repo": "acme/app"}}}
    attach_to_meta(msg, chain)
    recovered = read_from_meta(msg)
    if recovered is None or recovered.to_json() != chain.to_json():
        fails.append("chain did not round-trip through _meta")

    print("=" * 50)
    if fails:
        print("PROVENANCE SELF-TEST FAILED:")
        for f in fails:
            print("  -", f)
        raise SystemExit(1)
    print("PROVENANCE SELF-TEST PASSED")
    print("  effbound admits/rejects correctly; meet across hops accumulates;")
    print("  chain round-trips through _meta.")
    print("=" * 50)
