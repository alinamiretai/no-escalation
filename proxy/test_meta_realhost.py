#!/usr/bin/env python3
"""
test_meta_realhost.py — the one empirical claim the spec rests on, tested
against a REAL MCP server (not fake_server.py).

THE QUESTION (SEP-414 says yes; this checks it in practice):
  When a tools/call carries `io.noescalation/provenance` inside `_meta`, does a
  real, spec-compliant MCP server ACCEPT the call and complete it — rather than
  rejecting the unknown metadata? A server that choked on unknown `_meta` keys
  would break the whole approach, so this is the load-bearing empirical test.

WHAT IT DOES NOT test: whether a real HOST *originates* our `_meta` key. No host
injects io.noescalation on its own; that is what the guard is for. This tests
the design-critical half: a real server tolerates and receives the key.

SERVER USED: the official filesystem reference server, run via npx (needs Node).
  npx -y @modelcontextprotocol/server-filesystem <dir>
It speaks MCP 2025-06-18+ over stdio — a real implementation, not our fake.

HOW IT WORKS: we speak the client side of MCP directly to the real server:
  1. initialize handshake
  2. a tools/call to read_file, WITH io.noescalation/provenance in _meta
  3. check the server returns a normal result (not an error about _meta)
If the call succeeds with the key present, the key survived the trip into a
real server and was tolerated. That closes the empirical claim.
"""

import sys
import os
import json
import subprocess
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from provenance import Chain, Rule, Constraint, attach_to_meta, META_KEY


def main():
    # a scratch dir with one file for the server to read
    workdir = tempfile.mkdtemp(prefix="mcp-meta-test-")
    testfile = os.path.join(workdir, "hello.txt")
    with open(testfile, "w") as f:
        f.write("provenance survived the trip\n")

    # launch the REAL filesystem server via npx
    server_cmd = ["npx", "-y", "@modelcontextprotocol/server-filesystem", workdir]
    print(f"[test] launching real server: {' '.join(server_cmd)}", file=sys.stderr)
    print("[test] (first run downloads the package; may take ~30s)", file=sys.stderr)

    proc = subprocess.Popen(
        server_cmd,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        bufsize=0,
    )

    # give the server a moment to boot (npx resolution, node startup) and check
    # it did not immediately die
    import time
    time.sleep(2)
    if proc.poll() is not None:
        print("[test] server exited during startup", file=sys.stderr)
        _dump_stderr(proc)
        _finish(["server exited before initialize — see stderr above"], proc, workdir)
        return

    def send(obj):
        proc.stdin.write((json.dumps(obj) + "\n").encode())
        proc.stdin.flush()

    def recv(timeout=45):
        # Read one JSON-RPC line, blocking up to `timeout` seconds. Uses a
        # thread so a slow server start (package download, JIT) doesn't cause a
        # premature empty read the way select can. Skips non-JSON stdout noise.
        import threading
        result = {"line": None}
        def _read():
            while True:
                raw = proc.stdout.readline()
                if not raw:
                    return
                line = raw.decode(errors="replace").strip()
                if not line:
                    continue
                result["line"] = line
                return
        t = threading.Thread(target=_read, daemon=True)
        t.start()
        t.join(timeout)
        if result["line"] is None:
            return None
        try:
            return json.loads(result["line"])
        except json.JSONDecodeError:
            return recv(timeout)   # was server noise; wait for the next line

    failures = []

    # 1. initialize
    send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
          "params": {"protocolVersion": "2025-06-18",
                     "capabilities": {},
                     "clientInfo": {"name": "noescalation-meta-test", "version": "0.1"}}})
    init = recv()
    if not (init and init.get("id") == 1 and "result" in init):
        failures.append(f"initialize failed: {init}")
        print("[test] server did not initialize — cannot proceed", file=sys.stderr)
        _dump_stderr(proc)
        _finish(failures, proc, workdir)
        return

    server_name = init["result"].get("serverInfo", {}).get("name", "?")
    print(f"[test] real server initialized: {server_name}", file=sys.stderr)

    # notifications/initialized (required by many servers)
    send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    # 2. tools/call read_file WITH our provenance in _meta
    chain = Chain().extend("host",
                           [Rule("read_file", {"path": Constraint("prefix", workdir)})])
    call = {"jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": "read_file", "arguments": {"path": testfile}}}
    attach_to_meta(call, chain)   # <-- the key under test rides in _meta

    print(f"[test] sending read_file WITH _meta['{META_KEY}'] attached", file=sys.stderr)
    send(call)
    resp = recv()

    # 3. verdict
    if resp is None:
        failures.append("no response to tools/call (server may have rejected _meta and hung)")
    elif "error" in resp:
        # did it error specifically about _meta / provenance?
        msg = json.dumps(resp["error"])
        failures.append(f"server returned an ERROR to a call carrying _meta: {msg}")
    elif "result" in resp:
        # success — the real server accepted the call with our _meta key present
        content = json.dumps(resp["result"])
        if "provenance survived" in content:
            print("[test] server READ the file and returned its contents", file=sys.stderr)
        print("[test] SUCCESS: real server accepted tools/call carrying io.noescalation _meta", file=sys.stderr)
    else:
        failures.append(f"unexpected response shape: {resp}")

    _finish(failures, proc, workdir)


def _dump_stderr(proc):
    try:
        err = proc.stderr.read(4000).decode(errors="replace")
        if err.strip():
            print("[test] server stderr:\n" + err, file=sys.stderr)
    except Exception:
        pass


def _finish(failures, proc, workdir):
    try:
        proc.stdin.close()
        proc.terminate()
        proc.wait(timeout=5)
    except Exception:
        proc.kill()

    print("\n" + "=" * 60)
    if failures:
        print("META REAL-HOST TEST: FAILED / INCONCLUSIVE")
        for f in failures:
            print("  -", f)
        print("\nIf the failure is about _meta specifically, that is a real")
        print("finding: this server does not tolerate unknown _meta keys, and")
        print("the spec's propagation assumption needs revisiting for it.")
    else:
        print("META REAL-HOST TEST: PASSED")
        print("  A real MCP server accepted a tools/call carrying")
        print(f"  _meta['{META_KEY}'] and completed it normally.")
        print("  The design-critical half of SEP-414's _meta propagation")
        print("  (server tolerates the key) is confirmed against real code.")
    print("=" * 60)
    print(f"[test] scratch dir left at {workdir} (rm -rf when done)", file=sys.stderr)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()