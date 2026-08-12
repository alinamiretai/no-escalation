#!/usr/bin/env python3
"""
test_vectors.py — run the spec's conformance vectors (Appendix A.2) against
this implementation.

This is a SPEC-CONFORMANCE test, not a unit test. Each vector states a verdict
the specification REQUIRES. A failure means the spec and the implementation
disagree, and one of them is wrong. Triage each failure rather than assuming
the implementation is correct.

Known-failing at time of writing (these are implementation bugs the spec pass
exposed, not bad vectors):
  O6, O7  - prefix is bypassable by path traversal; no canonicalization (§4.2.2)
  O9      - glob '*' crosses '/' via fnmatch; spec forbids it (§4.2.4)

Run:  python3 test_vectors.py
"""

import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from provenance import Constraint, Rule, Chain, meet_constraints

PASS, FAIL, results = 0, 0, []


def check(vid, desc, got, want):
    global PASS, FAIL
    ok = (got == want)
    if ok: PASS += 1
    else:  FAIL += 1
    results.append((ok, vid, desc, got, want))


def c(**kw):
    """Constraint shorthand: c(eq='x'), c(prefix='/a/'), c(glob='a/*')."""
    (op, val), = kw.items()
    return Constraint("in" if op == "in_" else op, val)


# ---------------------------------------------------------------------------
# A.2.3 Constraint operators
# ---------------------------------------------------------------------------
print("=== A.2.3 constraint operators ===")

check("O1",  "eq matches exact",           c(eq="acme/app").matches("acme/app"), True)
check("O2",  "eq case-sensitive",          c(eq="acme/app").matches("acme/App"), False)
check("O3",  "in member",                  c(in_=["a","b"]).matches("b"), True)
check("O4",  "in non-member",              c(in_=["a","b"]).matches("c"), False)
check("O5",  "prefix matches",             c(prefix="/srv/acme/").matches("/srv/acme/x.txt"), True)
check("O6",  "prefix TRAVERSAL rejected",  c(prefix="/srv/acme/").matches("/srv/acme/../../etc/passwd"), False)
check("O7",  "prefix pct-encoded rejected",c(prefix="/srv/acme/").matches("/srv/acme/%2e%2e/x"), False)
check("O8",  "glob single level",          c(glob="acme/*").matches("acme/app"), True)
check("O9",  "glob * NOT across /",        c(glob="acme/*").matches("acme/app/sub"), False)
check("O10", "glob ** across /",           c(glob="acme/**").matches("acme/app/sub"), True)
check("O11", "glob anchored both ends",    c(glob="acme/app").matches("xacme/app"), False)
check("O12", "glob char class",            c(glob="f[a-c]o").matches("fbo"), True)
check("O13", "type mismatch: prefix/num",  c(prefix="/srv/").matches(12345), False)
check("O14", "type mismatch: glob/null",   c(glob="a*").matches(None), False)
check("O15", "numeric equality 5 == 5.0",  c(eq=5).matches(5.0), True)

# ---------------------------------------------------------------------------
# A.2.4 Meet of constraints — SOUNDNESS is what matters here.
# A meet must not admit a value that either input rejects.
# ---------------------------------------------------------------------------
print("=== A.2.4 meet soundness ===")

def meet_admits(a, b, value):
    """Does the computed meet admit `value`?  None if meet is empty."""
    m = meet_constraints(a, b)
    if m is None:
        return None
    return m.matches(value)

def sound(vid, desc, a, b, value):
    """The meet must admit `value` iff BOTH inputs admit it."""
    both = a.matches(value) and b.matches(value)
    got = meet_admits(a, b, value)
    got = False if got is None else got
    check(vid, desc, got, both)

sound("M1", "in ∩ eq admits b",        c(in_=["a","b","c"]), c(eq="b"), "b")
sound("M1b","in ∩ eq excludes a",      c(in_=["a","b","c"]), c(eq="b"), "a")
sound("M2", "in ∩ in admits b",        c(in_=["a","b"]),     c(in_=["b","c"]), "b")
sound("M2b","in ∩ in excludes a",      c(in_=["a","b"]),     c(in_=["b","c"]), "a")
sound("M3", "disjoint in ∩ in",        c(in_=["a"]),         c(in_=["b"]), "a")
sound("M4", "prefix ∩ prefix nested",  c(prefix="/srv/"),    c(prefix="/srv/acme/"), "/srv/acme/x")
sound("M4b","prefix ∩ prefix outside", c(prefix="/srv/"),    c(prefix="/srv/acme/"), "/srv/other/x")
sound("M5", "disjoint prefixes",       c(prefix="/a/"),      c(prefix="/b/"), "/a/x")
sound("M6", "eq ∩ glob admits",        c(eq="acme/app"),     c(glob="acme/*"), "acme/app")
sound("M7", "eq ∩ glob EXCLUDES deep", c(eq="acme/app/x"),   c(glob="acme/*"), "acme/app/x")
sound("M8", "glob ∩ prefix",           c(glob="a*"),         c(prefix="ab"), "abc")
sound("M9", "glob ∩ glob conjunction", c(glob="*x"),         c(glob="y*"), "yx")
sound("M9b","glob ∩ glob excl left",   c(glob="*x"),         c(glob="y*"), "zx")

# ---------------------------------------------------------------------------
# A.2.1 / A.2.5 Composition and rules — via Chain.effbound
# ---------------------------------------------------------------------------
print("=== A.2.1 composition ===")

def admits(chain: Chain, tool: str, args: dict) -> bool:
    eb = chain.effbound()
    return any(r.matches(tool, args) for r in eb)

host_wide = [Rule("create_issue", {"repo": c(in_=["acme/app", "acme/docs"])})]
plan_narrow = [Rule("create_issue", {"repo": c(eq="acme/app")})]

ch1 = Chain().extend("host", host_wide)
ch2 = Chain().extend("host", host_wide).extend("planner", plan_narrow)

check("C1", "single hop in bound",   admits(ch1, "create_issue", {"repo": "acme/app"}), True)
check("C2", "single hop out",        admits(ch1, "create_issue", {"repo": "evil/x"}), False)
check("C3", "survives narrowing",    admits(ch2, "create_issue", {"repo": "acme/app"}), True)
check("C4", "CONFUSED DEPUTY",       admits(ch2, "create_issue", {"repo": "acme/docs"}), False)

# re-amplification: a later hop tries to confer MORE than it received
ch5 = (Chain().extend("host", [Rule("create_issue", {"repo": c(eq="acme/app")})])
              .extend("worker", [Rule("create_issue", {"repo": c(in_=["acme/app","evil/pwn"])})]))
check("C5", "RE-AMPLIFICATION",      admits(ch5, "create_issue", {"repo": "evil/pwn"}), False)

# tool absent from a later hop drops out entirely
ch8 = (Chain().extend("host", [Rule("create_issue", {}), Rule("read_file", {})])
              .extend("planner", [Rule("create_issue", {})]))
check("C8", "tool absent from hop",  admits(ch8, "read_file", {}), False)

print("=== A.2.5 rules and arguments ===")
r_bound = [Rule("create_issue", {"repo": c(eq="a")})]
chR = Chain().extend("host", r_bound)
check("R2", "tool not in bound",     admits(chR, "delete_repo", {"repo": "a"}), False)
check("R3", "unconstrained arg free",admits(chR, "create_issue", {"repo": "a", "title": "x"}), True)
check("R4", "constrained arg absent",admits(chR, "create_issue", {"title": "x"}), False)

# ---------------------------------------------------------------------------
print()
print("=" * 68)
for ok, vid, desc, got, want in results:
    if not ok:
        print(f"  FAIL {vid:5s} {desc:32s} got={got!r:8s} want={want!r}")
print("=" * 68)
print(f"{PASS} passed, {FAIL} failed, {PASS+FAIL} total")
if FAIL:
    print()
    print("Each failure is a spec/implementation disagreement. Decide which is")
    print("wrong before changing either. O6/O7/O9 are known implementation bugs.")
sys.exit(1 if FAIL else 0)
