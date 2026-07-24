#!/usr/bin/env python3
"""
test_multihop.py — the DELEGATION suite. This is the one that exercises
composition (T2/T3), not just single-hop confinement.

Scenario: a two-hop chain.
  hop 1 (host):    confers create_issue on {acme/app, acme/docs}
  hop 2 (planner): narrows to create_issue on {acme/app}

The agent then makes calls. effbound is the MEET across both hops:
  {acme/app, acme/docs} ∩ {acme/app} = {acme/app}

The security claims this checks — each is a property the single-hop suite
CANNOT reach:

  T3 (conferral composes):     acme/app survives both hops -> ALLOWED
  narrowing holds:             acme/docs was in hop 1 but dropped by hop 2's
                               narrowing -> REJECTED, even though the host alone
                               would have allowed it. This is the confused-deputy
                               shape: a later hop's restriction is not undone by
                               an earlier hop's broader grant.
  no re-amplification:         a third repo neither hop conferred -> REJECTED

We simulate the two hops by pre-attaching hop 1's pi to the message (as if it
arrived from an upstream guard), then running guard.py as hop 2. That is
exactly what read_from_meta + extend do in the delegation path.
"""

import sys
import os
import json
import subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from provenance import Chain, Rule, Constraint, attach_to_meta

HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(HERE, "guard.py")
SERVER = os.path.join(HERE, "fake_server.py")

# hop 1: the host's broad conferral, as an inbound chain the planner receives
HOST_BOUND = [Rule("create_issue",
                   {"repo": Constraint("in", ["acme/app", "acme/docs"])})]
INBOUND = Chain().extend("host", HOST_BOUND)


def run_case(tool, args):
    """Send a call with hop-1 pi already attached, through guard.py acting as
    hop 2 (the planner, which narrows to acme/app in guard.py's __main__)."""
    msg = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
           "params": {"name": tool, "arguments": args}}
    attach_to_meta(msg, INBOUND)          # simulate arrival from upstream guard

    proc = subprocess.Popen(
        [sys.executable, GUARD, sys.executable, SERVER],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=None, bufsize=0,
    )
    proc.stdin.write((json.dumps(msg) + "\n").encode()); proc.stdin.flush()
    line = proc.stdout.readline().decode().strip()
    proc.stdin.close()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
    resp = json.loads(line) if line else {}
    if "error" in resp and resp["error"].get("code") == -32001:
        return "rejected"
    if "result" in resp:
        return "allowed"
    return "unknown"


def main():
    cases = [
        ("T3 compose: acme/app survives both hops",
         "create_issue", {"repo": "acme/app", "title": "x"}, "allowed"),
        ("narrowing holds: acme/docs dropped by hop 2 (confused deputy)",
         "create_issue", {"repo": "acme/docs", "title": "x"}, "rejected"),
        ("no re-amplification: evil/app in neither hop",
         "create_issue", {"repo": "evil/app", "title": "x"}, "rejected"),
    ]

    print("=" * 60)
    print("MULTI-HOP DELEGATION SUITE (composition / T3)")
    print("  hop1 host: {acme/app, acme/docs}   hop2 planner: {acme/app}")
    print("  effbound  = meet = {acme/app}")
    print("-" * 60)
    failures = []
    for label, tool, args, expected in cases:
        got = run_case(tool, args)
        ok = got == expected
        print(f"  [{'PASS' if ok else 'FAIL'}] {label}")
        print(f"         expected {expected}, got {got}")
        if not ok:
            failures.append(label)

    print("=" * 60)
    if failures:
        print(f"MULTI-HOP SUITE FAILED: {len(failures)} case(s)")
        sys.exit(1)
    print("MULTI-HOP SUITE PASSED")
    print("  Conferral composes down the chain; a later hop's narrowing holds")
    print("  against an earlier hop's broader grant. This is T3 in running code")
    print("  — the composition half, which the single-hop suite cannot show.")
    print("=" * 60)


if __name__ == "__main__":
    main()
