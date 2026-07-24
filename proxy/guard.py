#!/usr/bin/env python3
"""
guard.py — the proxy as a GUARD (io.noescalation reference implementation).

Stage 0 (proxy.py) relayed everything. This adds the two things that make it a
guard, on the host->server seam:

  1. CONSTRUCT: attach pi to every tools/call in _meta["io.noescalation/provenance"].
  2. CHECK: compute effbound from the chain and reject calls outside it,
     fail-closed, with a JSON-RPC error the host sees.

The policy (what the host is allowed to confer) is passed in as a bound. In a
real deployment this comes from configuration; here it is a constructor arg so
the four-attack test can set it explicitly.

Non-tools/call messages relay unchanged. A tools/call within effbound relays
(with pi attached). A tools/call outside effbound never reaches the server —
the guard answers the host with an error itself.

MODES:
  enforce (default): violations are rejected.
  audit:             violations are logged and allowed (for safe rollout).
"""

import sys
import os
import json
import threading
import subprocess
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from provenance import Chain, Rule, Constraint, META_KEY, attach_to_meta


def log(msg: str):
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
    print(f"[{ts}] [guard] {msg}", file=sys.stderr, flush=True)


class Guard:
    def __init__(self, host_component: str, host_bound: list[Rule],
                 mode: str = "enforce"):
        self.host_component = host_component
        self.host_bound = host_bound
        self.mode = mode

    def process_outbound(self, message: dict):
        """
        host->server. Returns (forward_message_or_None, reject_response_or_None).
        - forward_message set: send this to the server.
        - reject_response set: do NOT reach the server; send this back to host.
        """
        if message.get("method") != "tools/call":
            return message, None                    # not a tool call: pass through

        params = message.get("params", {})
        name = params.get("name")
        arguments = params.get("arguments", {})

        # CONSTRUCT: attach the host's conferral as pi. (Single-hop here; a
        # multi-agent host would extend an inbound chain instead.)
        chain = Chain().extend(self.host_component, self.host_bound)
        attach_to_meta(message, chain)

        # CHECK: is this call within effbound?
        if chain.admits(name, arguments):
            log(f"ALLOW {name} {json.dumps(arguments)}")
            return message, None

        # violation
        if self.mode == "audit":
            log(f"AUDIT (would reject) {name} {json.dumps(arguments)}")
            return message, None                    # allowed in audit mode
        log(f"REJECT {name} {json.dumps(arguments)}  — outside effbound")
        reject = {
            "jsonrpc": "2.0",
            "id": message.get("id"),
            "error": {
                "code": -32001,                     # extension-defined: escalation blocked
                "message": f"io.noescalation: '{name}' with these arguments is "
                           f"outside the conferred bound",
                "data": {"tool": name, "arguments": arguments},
            },
        }
        return None, reject


def pump_outbound(host_in, server_in, host_out, guard: Guard):
    """host stdin -> (guard) -> server stdin, with rejects short-circuited
    back to host stdout."""
    for line in host_in:
        raw = line.rstrip(b"\n").decode("utf-8", errors="replace")
        if not raw.strip():
            continue
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            server_in.write((raw + "\n").encode()); server_in.flush()
            continue

        forward, reject = guard.process_outbound(msg)
        if reject is not None:
            host_out.write((json.dumps(reject, separators=(",", ":")) + "\n").encode())
            host_out.flush()
        if forward is not None:
            server_in.write((json.dumps(forward, separators=(",", ":")) + "\n").encode())
            server_in.flush()


def pump_inbound(server_out, host_out):
    """server stdout -> host stdout, unchanged (stage 1 does not guard results)."""
    for line in server_out:
        host_out.write(line)
        host_out.flush()


def run(server_cmd, guard: Guard):
    log(f"launching server: {' '.join(server_cmd)}  (mode={guard.mode})")
    server = subprocess.Popen(server_cmd, stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=sys.stderr, bufsize=0)
    t_up = threading.Thread(target=pump_outbound,
                            args=(sys.stdin.buffer, server.stdin,
                                  sys.stdout.buffer, guard), daemon=True)
    t_down = threading.Thread(target=pump_inbound,
                              args=(server.stdout, sys.stdout.buffer), daemon=True)
    t_up.start(); t_down.start()
    server.wait()


if __name__ == "__main__":
    # Default policy for manual runs: create_issue on acme/app only.
    demo_bound = [Rule("create_issue", {"repo": Constraint("in", ["acme/app"])})]
    g = Guard("host", demo_bound, mode="enforce")
    if len(sys.argv) < 2:
        print("usage: guard.py <server-command> [args...]", file=sys.stderr)
        sys.exit(2)
    run(sys.argv[1:], g)
