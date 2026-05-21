#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
BASE_URL="${BASE_URL:-http://127.0.0.1:8080}"
TOKEN="${AIR_CODE_TOKEN:-dev-token-change-me}"
LOG_FILE="${ROOT_DIR}/tmp/aircoded-smoke.log"
SERVER_BIN="${ROOT_DIR}/tmp/aircoded-smoke"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
  fi
}

"$ROOT_DIR/scripts/setup_sandbox.sh" >/dev/null

if ! curl -fsS "$BASE_URL/health" >/dev/null 2>&1; then
  mkdir -p "$ROOT_DIR/tmp"
  (cd "$ROOT_DIR/backend" && go build -o "$SERVER_BIN" ./cmd/aircoded)
  "$SERVER_BIN" -config "$ROOT_DIR/backend/config.json" >"$LOG_FILE" 2>&1 &
  SERVER_PID="$!"
  trap cleanup EXIT INT TERM

  attempts=0
  until curl -fsS "$BASE_URL/health" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 40 ]; then
      cat "$LOG_FILE" >&2 || true
      exit 1
    fi
    if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
      cat "$LOG_FILE" >&2 || true
      exit 1
    fi
    sleep 0.25
  done
fi

curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE_URL/v1/projects" >/dev/null
curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE_URL/v1/workspace-roots" >/dev/null
curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE_URL/v1/workspace-roots/sandbox/tree?path=." >/dev/null
curl -fsS -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"rootId":"sandbox","path":"sample-app"}' \
  "$BASE_URL/v1/workspace/open" >/dev/null
curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE_URL/v1/projects/sample-app/files?path=README.md" >/dev/null

printf 'backend smoke ok: %s\n' "$BASE_URL"
