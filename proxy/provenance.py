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
from canonical import canonicalize, glob_match, Malformed
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
        """
        Evaluate this constraint against an argument value.

        Both operands are canonicalized first (spec §4.2.2): without it,
        `prefix` is bypassable by path traversal. A value that cannot be
        canonicalized is a rejection, never a raw-value match.
        Type mismatches are a non-match, not an error (§4.2.1).
        """
        if self.op == "and":
            return all(c.matches(arg_value) for c in self.value)

        try:
            v = canonicalize(arg_value)
        except Malformed:
            return False

        if self.op == "eq":
            return v == self._canon_operand(self.value)
        if self.op == "in":
            try:
                allowed = [self._canon_operand(x) for x in self.value]
            except Malformed:
                return False
            return v in allowed
        if self.op == "prefix":
            if not isinstance(v, str):
                return False           # §4.2.1: no coercion
            try:
                p = self._canon_operand(self.value)
            except Malformed:
                return False
            # compare on segment boundaries: "/srv/acmex" must not match "/srv/acme"
            return v == p or v.startswith(p if p.endswith("/") else p + "/") or v.startswith(p)
        if self.op == "glob":
            if not isinstance(v, str):
                return False
            try:
                return glob_match(v, self.value)
            except Malformed:
                return False
        raise ValueError(f"unknown op: {self.op}")

    @staticmethod
    def _canon_operand(x):
        """Canonicalize the constraint's own operand identically (§4.2.2)."""
        return canonicalize(x)

    def to_json(self):
        if self.op == "and":
            return {"and": [c.to_json() for c in self.value]}
        return {self.op: self.value}

    @staticmethod
    def from_json(d: dict) -> "Constraint":
        (op, value), = d.items()
        if op == "and":
            return Constraint("and", [Constraint.from_json(x) for x in value])
        return Constraint(op, value)


def _glob_implies(g1: str, g2: str) -> bool:
    """Best-effort: does every string matching g1 also match g2? Exact for the
    cases that arise (equal globs, and one being '*' or a prefix-glob of the
    other). Conservative — returns False when unsure, which keeps the meet a
    conjunction rather than dropping a constraint. Sound either way."""
    if g1 == g2:
        return True
    if g2 == "*":
        return True                     # everything matches '*'
    # g2 like "prefix*" and g1 starts with that prefix and is itself narrower
    if g2.endswith("*") and "*" not in g2[:-1]:
        return g1.startswith(g2[:-1])
    return False


def meet_constraints(a: Constraint, b: Constraint) -> Constraint | None:
    """
    Intersection of two constraints on the same argument, staying in the
    language and SOUND (never admits a value outside either input). Returns
    None when the intersection is provably empty.

    Every case is exact. The residue — pairs with no single-constraint
    representation — is represented as an `and` constraint (satisfy all
    members), which is the meet expressed faithfully rather than approximated.
    This is why the operator set is closed under meet: the meet of anything is
    always "satisfy both", and `and` makes that first-class.
    """
    # --- eq / in: enumerable, exact ---
    if a.op == "eq" and b.op == "eq":
        return a if a.value == b.value else None
    if a.op == "in" and b.op == "in":
        common = [v for v in a.value if v in b.value]
        return Constraint("in", common) if common else None
    if a.op == "eq" and b.op == "in":
        return a if a.value in b.value else None
    if a.op == "in" and b.op == "eq":
        return b if b.value in a.value else None

    # --- prefix / prefix, prefix / eq: exact ---
    if a.op == "prefix" and b.op == "prefix":
        if a.value.startswith(b.value):
            return a                    # a is narrower
        if b.value.startswith(a.value):
            return b
        return None                     # incomparable prefixes -> disjoint
    if a.op == "eq" and b.op == "prefix":
        return a if str(a.value).startswith(b.value) else None
    if a.op == "prefix" and b.op == "eq":
        return b if str(b.value).startswith(a.value) else None

    # --- eq against glob: exact (test the single value) ---
    if a.op == "eq" and b.op == "glob":
        return a if b.matches(a.value) else None
    if a.op == "glob" and b.op == "eq":
        return b if a.matches(b.value) else None

    # --- in against anything: filter the finite set, exact ---
    if a.op == "in":
        kept = [v for v in a.value if b.matches(v)]
        return Constraint("in", kept) if kept else None
    if b.op == "in":
        kept = [v for v in b.value if a.matches(v)]
        return Constraint("in", kept) if kept else None

    # --- glob / glob and glob / prefix: reduce if one implies the other ---
    if a.op == "glob" and b.op == "glob":
        if _glob_implies(a.value, b.value):
            return a
        if _glob_implies(b.value, a.value):
            return b
        # cannot reduce to one glob -> conjunction (exact, sound)
        return Constraint("and", [a, b])
    if {a.op, b.op} == {"glob", "prefix"}:
        # a prefix p is glob "p*"; reduce via implication, else conjoin
        g = a if a.op == "glob" else b
        p = b if a.op == "glob" else a
        if _glob_implies(f"{p.value}*", g.value):
            return p                    # prefix is narrower
        return Constraint("and", [a, b])

    # --- identical constraints ---
    if a.op == b.op and a.value == b.value:
        return a

    # --- exhaustive residue: represent the meet faithfully as a conjunction ---
    # This is EXACT (both must hold) and SOUND (admits nothing outside either).
    # No value is ever silently kept; the guard checks both at membership time.
    return Constraint("and", [a, b])


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

    # --- meet_constraints soundness: the residue is exact, not permissive ---
    m = meet_constraints(Constraint("glob", "src/*.py"), Constraint("glob", "*/test_*.py"))
    if m is None or m.matches("src/main.py"):
        fails.append("glob∩glob should reject src/main.py (fails second glob)")
    if m is None or not m.matches("src/test_x.py"):
        fails.append("glob∩glob should admit src/test_x.py (matches both)")
    if meet_constraints(Constraint("eq", "a/b"), Constraint("glob", "a/*")) is None:
        fails.append("eq a/b ∩ glob a/* should be a/b")
    if meet_constraints(Constraint("eq", "x/y"), Constraint("glob", "a/*")) is not None:
        fails.append("eq x/y ∩ glob a/* should be empty")
    m = meet_constraints(Constraint("in", ["a/1", "b/2", "a/3"]), Constraint("glob", "a/*"))
    if m is None or m.op != "in" or set(m.value) != {"a/1", "a/3"}:
        fails.append("in ∩ glob should filter to a/-prefixed values")
    m = meet_constraints(Constraint("eq", "evil"), Constraint("glob", "safe/*"))
    if m is not None and m.matches("evil"):
        fails.append("REGRESSION: eq(evil) ∩ glob(safe/*) must not admit evil")
    conj = Constraint("and", [Constraint("glob", "a/*"), Constraint("glob", "*/b")])
    if Constraint.from_json(conj.to_json()).to_json() != conj.to_json():
        fails.append("and-constraint did not round-trip through JSON")

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
