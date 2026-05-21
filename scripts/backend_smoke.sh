#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://127.0.0.1:8080}"
TOKEN="${AIR_CODE_TOKEN:-dev-token-change-me}"

curl -fsS "$BASE_URL/health" >/dev/null
curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE_URL/v1/projects" >/dev/null
curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE_URL/v1/workspace-roots" >/dev/null
curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE_URL/v1/workspace-roots/sandbox/tree?path=." >/dev/null
curl -fsS -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"rootId":"sandbox","path":"sample-app"}' \
  "$BASE_URL/v1/workspace/open" >/dev/null
curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE_URL/v1/projects/sample-app/files?path=README.md" >/dev/null

printf 'backend smoke ok: %s\n' "$BASE_URL"
