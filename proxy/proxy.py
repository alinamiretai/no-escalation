#!/usr/bin/env python3
"""
Stage-0 pass-through MCP proxy (io.noescalation reference implementation, step 1).

WHAT IT DOES NOW: nothing but relay. The host launches THIS instead of the real
MCP server; this launches the real server and shuttles JSON-RPC messages both
ways, logging each one to stderr. No provenance, no enforcement yet — this
stage exists only to prove the core mechanic (intercept, inspect, relay) works
against real stdio framing before anything is built on top of it.

WHY PASS-THROUGH FIRST: every later capability (construct pi in _meta, check
effbound, reject on violation) bolts onto this loop. If the relay is wrong,
everything above it is wrong invisibly. So we make the relay correct and
observable first, with a test harness that needs no real host and no real
server (see test_passthrough.py).

TRANSPORT NOTE: MCP stdio framing is newline-delimited JSON — one JSON-RPC
message per line (this is the stdio convention; HTTP transport differs). We
read lines, parse, log, forward. A message we cannot parse is relayed
unchanged rather than dropped: a proxy must never silently eat traffic it
does not understand.
"""

import sys
import os
import json
import threading
import subprocess
from datetime import datetime, timezone


def log(direction: str, obj, raw: str):
    """Log one message to stderr. direction is host->server or server->host."""
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
    if obj is not None:
        method = obj.get("method")
        msg_id = obj.get("id")
        if method:                                  # a request or notification
            name = ""
            if method == "tools/call":
                name = obj.get("params", {}).get("name", "")
            tag = f"{method}{f' [{name}]' if name else ''}"
            print(f"[{ts}] {direction}  {tag}  id={msg_id}",
                  file=sys.stderr, flush=True)
        else:                                       # a response
            kind = "result" if "result" in obj else "error"
            print(f"[{ts}] {direction}  <{kind}>  id={msg_id}",
                  file=sys.stderr, flush=True)
    else:
        print(f"[{ts}] {direction}  <unparseable, relayed as-is>",
              file=sys.stderr, flush=True)


def pump(src, dst, direction: str, on_message=None):
    """
    Relay newline-delimited JSON from src to dst, logging each line.
    on_message(obj) may return a (possibly modified) obj to forward instead,
    or None to forward the original bytes unchanged. Stage 0 does not use it;
    it is the seam where pi-construction and enforcement will attach.
    """
    for line in src:
        raw = line.rstrip(b"\n").decode("utf-8", errors="replace") \
            if isinstance(line, bytes) else line.rstrip("\n")
        if not raw.strip():
            continue
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError:
            obj = None

        log(direction, obj, raw)

        out = raw
        if on_message is not None and obj is not None:
            replaced = on_message(obj)
            if replaced is not None:
                out = json.dumps(replaced, separators=(",", ":"))

        try:
            dst.write((out + "\n").encode("utf-8"))
            dst.flush()
        except (BrokenPipeError, ValueError):
            break


def main():
    if len(sys.argv) < 2:
        print("usage: proxy.py <server-command> [args...]", file=sys.stderr)
        print("  launches the real MCP server and relays stdio to/from it",
              file=sys.stderr)
        sys.exit(2)

    server_cmd = sys.argv[1:]
    print(f"[proxy] launching server: {' '.join(server_cmd)}",
          file=sys.stderr, flush=True)

    server = subprocess.Popen(
        server_cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=sys.stderr,          # server's own logs pass through to our stderr
        bufsize=0,
    )

    # host->server: our stdin  -> server stdin
    # server->host: server out -> our stdout
    t_up = threading.Thread(
        target=pump,
        args=(sys.stdin.buffer, server.stdin, "host->server"),
        daemon=True,
    )
    t_down = threading.Thread(
        target=pump,
        args=(server.stdout, sys.stdout.buffer, "server->host"),
        daemon=True,
    )
    t_up.start()
    t_down.start()

    # exit when the server exits or our stdin closes
    server.wait()
    print(f"[proxy] server exited with code {server.returncode}",
          file=sys.stderr, flush=True)


if __name__ == "__main__":
    main()
