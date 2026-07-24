#!/usr/bin/env bash
# idle-egress-native.sh — closes residual #2 of github-mcp-server-inventory.md
# WITHOUT Docker. Builds the audited source and watches the process's own
# network connections.
#
# Why this is better evidence than a packet capture: `lsof -i -a -p <pid>`
# attributes connections to THIS PROCESS. A host tcpdump would capture every
# packet on the machine and require you to argue about which were the
# server's. Here there is nothing to argue about.
#
# QUESTION: with zero tool calls, does the server open any network connection?
#
# READING THE RESULT:
#   no connections ever            -> claim holds; residual #2 CLOSED.
#   connections to api.github.com  -> expected in principle (that is its job),
#                                     but at IDLE it is a finding: nothing was
#                                     requested. Trace it to source.
#   connections anywhere else      -> FINDING. The source audit missed
#                                     something, which is what this is for.
#   DNS resolution only            -> report it. Resolution without connection
#                                     is still egress; do not quietly omit it.

set -uo pipefail

COMMIT="1338dbed4a044ee26422d4212bac3a8037fdb7ff"
SRC="${SRC:-$HOME/github-mcp-server}"
SECS="${SECS:-300}"           # total watch window
EVERY="${EVERY:-5}"           # poll interval
OUT="${OUT:-idle-egress-capture.txt}"
BIN="/tmp/ghmcp-audit"

exec > >(tee "$OUT") 2>&1

echo "=== provenance ==="
cd "$SRC" || { echo "source tree not at $SRC; set SRC=..."; exit 1; }
git rev-parse HEAD
[ "$(git rev-parse HEAD)" = "$COMMIT" ] && echo "matches audited commit" \
  || echo "WARNING: HEAD != audited commit $COMMIT"

command -v go >/dev/null || { echo "go not installed (brew install go)"; exit 1; }
go version

echo
echo "=== build from pinned source ==="
go build -o "$BIN" ./cmd/github-mcp-server || { echo "build failed"; exit 1; }
ls -l "$BIN"

echo
echo "=== run idle (stdio transport, stdin held open, no requests sent) ==="
FIFO=$(mktemp -u /tmp/ghmcp-fifo.XXXXXX)
mkfifo "$FIFO"
sleep "$((SECS + 30))" > "$FIFO" &
HOLDER=$!
GITHUB_PERSONAL_ACCESS_TOKEN=dummy-not-a-real-token \
  "$BIN" stdio < "$FIFO" > /dev/null 2>&1 &
PID=$!
sleep 2

if ! kill -0 "$PID" 2>/dev/null; then
  echo "server exited immediately — check invocation/flags before trusting a null result"
  kill "$HOLDER" 2>/dev/null; rm -f "$FIFO"; exit 1
fi
echo "server pid=$PID, watching ${SECS}s every ${EVERY}s"

echo
echo "=== connection samples ==="
FOUND=0
for i in $(seq 1 $((SECS / EVERY))); do
  SNAP=$(lsof -i -a -p "$PID" -n -P 2>/dev/null | tail -n +2)
  if [ -n "$SNAP" ]; then
    FOUND=1
    echo "[t+$((i * EVERY))s]"
    echo "$SNAP"
  fi
  kill -0 "$PID" 2>/dev/null || { echo "server exited at t+$((i * EVERY))s"; break; }
  sleep "$EVERY"
done

kill "$PID" "$HOLDER" 2>/dev/null
rm -f "$FIFO"

echo
echo "=== summary ==="
if [ "$FOUND" -eq 0 ]; then
  echo "NO network connections observed over ${SECS}s at idle."
  echo "-> residual #2 CLOSED: the server does not phone home when unused."
else
  echo "Connections observed — see samples above. Identify each destination"
  echo "and trace it to source before recording a verdict."
fi
