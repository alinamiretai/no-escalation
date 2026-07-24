#!/usr/bin/env bash
# idle-egress.sh — closes residual #2 of github-mcp-server-inventory.md.
#
# QUESTION: with zero tool calls, does the server originate any network
# traffic? The source audit (audit.sh) showed no third-party endpoints in the
# serving path; this is the empirical backstop, and it also covers dependency
# I/O that first-party grep cannot see.
#
# EVIDENCE CHAIN: builds from the audited commit rather than pulling a
# published image, so this artifact and the source inventory describe the
# same code. If you use the published image instead, record its digest and
# say so — a build is not a commit.
#
# TWO EXPERIMENTS:
#   A. no-network control — does it even start without egress? Tests whether
#      network is *required* at startup.
#   B. idle capture      — with network available, what does it actually send
#      over N seconds of doing nothing? Tests whether it phones home.
#
# Experiment B is the one that matters. A is cheap corroboration.

set -uo pipefail

COMMIT="1338dbed4a044ee26422d4212bac3a8037fdb7ff"
SRC="${SRC:-$HOME/github-mcp-server}"
TAG="ghmcp-audit:${COMMIT:0:7}"
SECS="${SECS:-300}"          # capture window; 5 min catches minute-scale timers
OUT="${OUT:-idle-egress-capture.txt}"

echo "=== provenance ==="
cd "$SRC" || { echo "source tree not at $SRC; set SRC=..."; exit 1; }
git rev-parse HEAD
[ "$(git rev-parse HEAD)" = "$COMMIT" ] || echo "WARNING: HEAD != audited commit"

echo "=== build from pinned source ==="
docker build -t "$TAG" . || { echo "build failed"; exit 1; }

echo
echo "=== experiment A: no network at all ==="
echo "(server should still start; a crash here means egress is REQUIRED)"
timeout 15 docker run --rm -i --network none \
  -e GITHUB_PERSONAL_ACCESS_TOKEN=dummy-not-a-real-token \
  "$TAG" stdio < /dev/null
echo "exit=$?  (124 = still running when timeout fired = started fine)"

echo
echo "=== experiment B: idle capture, ${SECS}s ==="
docker rm -f mcp-idle >/dev/null 2>&1
docker run -d --name mcp-idle -i \
  -e GITHUB_PERSONAL_ACCESS_TOKEN=dummy-not-a-real-token \
  "$TAG" stdio >/dev/null || { echo "server failed to start"; exit 1; }
sleep 2

# tcpdump inside the SERVER's network namespace: sees everything it sends,
# including DNS. Host-level capture would miss this on macOS (Docker Desktop
# runs containers inside a VM).
docker run --rm --net=container:mcp-idle \
  --cap-add=NET_ADMIN --cap-add=NET_RAW nicolaka/netshoot \
  timeout "$SECS" tcpdump -n -i any -q 2>/dev/null | tee "$OUT"

docker rm -f mcp-idle >/dev/null 2>&1

echo
echo "=== summary ==="
echo "packets captured: $(grep -c . "$OUT" 2>/dev/null || echo 0)"
echo "distinct destinations:"
grep -oE '> [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$OUT" 2>/dev/null | sort -u || echo "  (none)"
echo
echo "READING THE RESULT:"
echo "  empty / no packets      -> claim holds: no idle egress. Record in the"
echo "                             inventory as residual #2 CLOSED."
echo "  DNS only                -> note it; resolution without connection is"
echo "                             still egress and should be reported, not hidden."
echo "  connections to any host -> FINDING. Identify the host and trace it to"
echo "                             source; the source audit missed something,"
echo "                             which is exactly what this experiment is for."
