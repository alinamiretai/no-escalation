#!/usr/bin/env bash
# Instantiation audit: github/github-mcp-server, local server.
# Run from the repo root. Pin the commit before interpreting output:
#   git rev-parse HEAD   # expected 1338dbed4a044ee26422d4212bac3a8037fdb7ff
set -u
echo "=== commit ==="; git rev-parse HEAD
echo "=== 1. outbound HTTP clients ==="
grep -rn "http.NewRequest\|http.Get\|http.Post\|&http.Client{" --include='*.go' .
echo "=== 2. non-GitHub hosts ==="
grep -rn "https://" --include='*.go' . | grep -v _test.go
echo "=== 3. local filesystem writes ==="
grep -rn "os.Create\|os.WriteFile\|os.OpenFile\|MkdirTemp\|ioutil.Write" --include='*.go' .
echo "=== 4. logging / telemetry ==="
grep -rn "log/slog\|logrus\|zerolog\|Stderr\|otel\|opentelemetry\|sentry\|telemetry\|analytics" --include='*.go' .
echo "=== 5. telemetry deps in go.mod ==="
grep -n "otel\|sentry\|datadog\|honeycomb" go.mod
echo "=== 6. background activity (effects with no inducing request) ==="
grep -rn "go func\|time.Ticker\|time.AfterFunc\|NewTimer\|func init(" --include='*.go' .
echo "=== 7. auth plumbing ==="
grep -rn "oauth2\|TokenSource\|RoundTripper\|Transport" --include='*.go' .
echo "=== 8. caching / conditional requests ==="
grep -rni "cache\|etag\|If-None-Match\|Last-Modified" --include='*.go' .
echo "=== 9. endpoint check ==="
grep -rn "api.github.com\|githubcopilot\|collector\|ingest\|analytics" --include='*.go' . | grep -v _test.go
