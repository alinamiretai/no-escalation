#!/usr/bin/env python3
"""
Stage-0 test: play the HOST. Launch `proxy.py fake_server.py`, send real
JSON-RPC messages into the proxy's stdin, read what comes back on its stdout,
and check the round trip. No real MCP host, no real server, no token — this is
the green check that proves the intercept-and-relay mechanic works.

What it asserts:
  1. initialize round-trips and the server's protocolVersion comes back
  2. tools/list round-trips and both toy tools come back
  3. tools/call round-trips and the echoed args are intact (nothing dropped
     or mangled by the proxy)

If this passes, the relay is correct and observable, and pi-construction +
effbound checking can be built on the `on_message` seam in the next stage.
"""

import sys
import os
import json
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
PROXY = os.path.join(HERE, "proxy.py")
SERVER = os.path.join(HERE, "fake_server.py")


def main():
    proc = subprocess.Popen(
        [sys.executable, PROXY, sys.executable, SERVER],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=None,                 # let the proxy's logs show on our terminal
        bufsize=0,
    )

    def send(obj):
        proc.stdin.write((json.dumps(obj) + "\n").encode())
        proc.stdin.flush()

    def recv():
        line = proc.stdout.readline().decode().strip()
        return json.loads(line) if line else None

    failures = []

    # 1. initialize
    send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
          "params": {"protocolVersion": "2026-07-28", "capabilities": {}}})
    r = recv()
    if not (r and r.get("id") == 1
            and r.get("result", {}).get("protocolVersion") == "2026-07-28"):
        failures.append(f"initialize round-trip failed: {r}")

    # 2. tools/list
    send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    r = recv()
    tools = r.get("result", {}).get("tools", []) if r else []
    names = {t.get("name") for t in tools}
    if names != {"read_file", "create_issue"}:
        failures.append(f"tools/list round-trip failed: got {names}")

    # 3. tools/call — the argument-integrity check
    send({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
          "params": {"name": "create_issue",
                     "arguments": {"repo": "acme/app", "title": "hello"}}})
    r = recv()
    text = ""
    if r and "result" in r:
        text = r["result"].get("content", [{}])[0].get("text", "")
    if "create_issue" not in text or "acme/app" not in text:
        failures.append(f"tools/call round-trip failed: {r}")

    # shut down: closing stdin ends the proxy, which ends the server
    proc.stdin.close()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()

    print("\n" + "=" * 50)
    if failures:
        print("STAGE 0 FAILED:")
        for f in failures:
            print("  -", f)
        sys.exit(1)
    else:
        print("STAGE 0 PASSED: intercept -> relay -> respond works.")
        print("The proxy sees every message and forwards it intact.")
        print("Next: construct pi in _meta on the host->server seam.")
    print("=" * 50)


if __name__ == "__main__":
    main()
