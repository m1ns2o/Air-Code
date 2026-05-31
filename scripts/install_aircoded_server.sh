#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
BIN_DIR="$BACKEND_DIR/dist"
BIN_PATH="$BIN_DIR/aircoded"

PREFIX="${AIRCODE_PREFIX:-$HOME/.aircode}"
CONFIG_PATH="${AIRCODE_CONFIG:-}"
ADDR="${AIRCODE_ADDR:-127.0.0.1:8080}"
WORKSPACE_ROOT="${AIRCODE_WORKSPACE_ROOT:-}"
AGENTS="${AIRCODE_AGENTS:-codex,claude,hermes}"
LANGUAGE_SERVERS="${AIRCODE_LANGUAGE_SERVERS:-typescript,python,vue}"
SERVICE=0
YES=0
FORCE=0
DRY_RUN=0
SKIP_DEPS=0

usage() {
  cat <<'EOF'
Usage: scripts/install_aircoded_server.sh [options]

Builds the Go backend and runs `aircoded install` with deployment defaults.

Options:
  --prefix PATH              Install prefix. Default: ~/.aircode
  --config PATH              Existing config.json to copy. Omit to generate one.
  --addr HOST:PORT           Listen address for generated config. Default: 127.0.0.1:8080
  --workspace-root PATH      Workspace root for generated config. Default: <prefix>/workspaces
  --agents LIST              Agent CLIs to configure. Default: codex,claude,hermes
  --language-servers LIST    LSP servers to configure. Default: typescript,python,vue
  --service                  Install launchd/systemd user service file.
  --yes                      Run missing CLI installers without extra confirmation.
  --force                    Overwrite installed files.
  --skip-deps                Skip dependency installation such as ripgrep.
  --dry-run                  Print install plan without writing files.
  -h, --help                 Show this help.

Environment overrides:
  AIRCODE_PREFIX, AIRCODE_CONFIG, AIRCODE_ADDR, AIRCODE_WORKSPACE_ROOT,
  AIRCODE_AGENTS, AIRCODE_LANGUAGE_SERVERS
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="$2"
      shift 2
      ;;
    --config)
      CONFIG_PATH="$2"
      shift 2
      ;;
    --addr)
      ADDR="$2"
      shift 2
      ;;
    --workspace-root)
      WORKSPACE_ROOT="$2"
      shift 2
      ;;
    --agents)
      AGENTS="$2"
      shift 2
      ;;
    --language-servers)
      LANGUAGE_SERVERS="$2"
      shift 2
      ;;
    --service)
      SERVICE=1
      shift
      ;;
    --yes)
      YES=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-deps)
      SKIP_DEPS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$BIN_DIR"
echo "Building aircoded..."
(cd "$BACKEND_DIR" && go build -o "$BIN_PATH" ./cmd/aircoded)

cmd=("$BIN_PATH" install -binary "$BIN_PATH" -prefix "$PREFIX" -addr "$ADDR" -agents "$AGENTS" -language-servers "$LANGUAGE_SERVERS")

if [[ -n "$CONFIG_PATH" ]]; then
  cmd+=(-config "$CONFIG_PATH")
fi
if [[ -n "$WORKSPACE_ROOT" ]]; then
  cmd+=(-workspace-root "$WORKSPACE_ROOT")
fi
if [[ "$SERVICE" -eq 1 ]]; then
  cmd+=(-service)
fi
if [[ "$YES" -eq 1 ]]; then
  cmd+=(-yes)
fi
if [[ "$FORCE" -eq 1 ]]; then
  cmd+=(-force)
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
  cmd+=(-dry-run)
fi
if [[ "$SKIP_DEPS" -eq 1 ]]; then
  cmd+=(-skip-deps)
fi

echo "Running: ${cmd[*]}"
"${cmd[@]}"
