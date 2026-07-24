#!/usr/bin/env python3
"""
Minimal fake MCP server — stands in for a real one so the proxy can be tested
with no install and no token. Speaks just enough JSON-RPC to be realistic:
reads newline-delimited requests on stdin, answers on stdout.

Handles:
  initialize   -> a plausible capabilities result
  tools/list   -> two toy tools
  tools/call   -> echoes back which tool and args it received
anything else  -> a JSON-RPC "method not found" error

This is a test fixture, not part of the product. It exists so `pump` in the
proxy has something real to relay to.
"""

import sys
import json


def respond(msg_id, result=None, error=None):
    out = {"jsonrpc": "2.0", "id": msg_id}
    if error is not None:
        out["error"] = error
    else:
        out["result"] = result
    sys.stdout.write(json.dumps(out, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            continue

        method = req.get("method")
        msg_id = req.get("id")

        if method == "initialize":
            respond(msg_id, result={
                "protocolVersion": "2026-07-28",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "fake-server", "version": "0.0.1"},
            })
        elif method == "tools/list":
            respond(msg_id, result={"tools": [
                {"name": "read_file",
                 "inputSchema": {"type": "object",
                                 "properties": {"path": {"type": "string"}}}},
                {"name": "create_issue",
                 "inputSchema": {"type": "object",
                                 "properties": {"repo": {"type": "string"},
                                                "title": {"type": "string"}}}},
            ]})
        elif method == "tools/call":
            params = req.get("params", {})
            name = params.get("name")
            args = params.get("arguments", {})
            respond(msg_id, result={
                "content": [{"type": "text",
                             "text": f"fake-server ran {name} with {json.dumps(args)}"}]
            })
        elif method is not None and msg_id is None:
            # a notification (e.g. notifications/initialized) — no reply
            continue
        else:
            respond(msg_id, error={"code": -32601,
                                   "message": f"method not found: {method}"})


if __name__ == "__main__":
    main()
