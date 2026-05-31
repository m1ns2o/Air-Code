#!/bin/sh
set -eu

REPO_URL="${AIRCODE_REPO_URL:-https://github.com/m1ns2o/air-code.git}"
REPO_REF="${AIRCODE_REF:-main}"
SOURCE_DIR="${AIRCODE_SOURCE_DIR:-$HOME/.aircode/src/air-code}"
AIRCODE_SERVICE="${AIRCODE_SERVICE:-1}"
AIRCODE_YES="${AIRCODE_YES:-1}"
AIRCODE_SKIP_BOOTSTRAP_DEPS="${AIRCODE_SKIP_BOOTSTRAP_DEPS:-0}"

log() {
  printf '%s\n' "$*" >&2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

script_dir() {
  case "$0" in
    */*)
      dirname_path=$(dirname "$0")
      (cd "$dirname_path" && pwd)
      ;;
    *)
      pwd
      ;;
  esac
}

is_repo_checkout() {
  [ -f "$1/scripts/install_aircoded_server.sh" ] && [ -d "$1/backend/cmd/aircoded" ]
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

add_pkg() {
  pkg="$1"
  case " $PACKAGES " in
    *" $pkg "*) ;;
    *) PACKAGES="$PACKAGES $pkg" ;;
  esac
}

sudo_prefix() {
  if [ "$(id -u)" = "0" ]; then
    printf ''
    return
  fi
  if need_cmd sudo; then
    printf 'sudo '
    return
  fi
  fail "missing system dependencies and sudo is not available"
}

detect_packages() {
  PACKAGES=""
  needs_git="$1"
  os_name=$(uname -s)
  case "$os_name" in
    Darwin)
      [ "$needs_git" = "1" ] && ! need_cmd git && add_pkg git
      ! need_cmd go && add_pkg go
      ! need_cmd npm && add_pkg node
      ! need_cmd curl && add_pkg curl
      ;;
    Linux)
      if need_cmd apt-get; then
        [ "$needs_git" = "1" ] && ! need_cmd git && add_pkg git
        ! need_cmd go && add_pkg golang-go
        if ! need_cmd npm; then
          add_pkg nodejs
          add_pkg npm
        fi
        ! need_cmd curl && add_pkg curl
      elif need_cmd dnf || need_cmd yum; then
        [ "$needs_git" = "1" ] && ! need_cmd git && add_pkg git
        ! need_cmd go && add_pkg golang
        if ! need_cmd npm; then
          add_pkg nodejs
          add_pkg npm
        fi
        ! need_cmd curl && add_pkg curl
      elif need_cmd pacman; then
        [ "$needs_git" = "1" ] && ! need_cmd git && add_pkg git
        ! need_cmd go && add_pkg go
        if ! need_cmd npm; then
          add_pkg nodejs
          add_pkg npm
        fi
        ! need_cmd curl && add_pkg curl
      elif need_cmd apk; then
        [ "$needs_git" = "1" ] && ! need_cmd git && add_pkg git
        ! need_cmd go && add_pkg go
        if ! need_cmd npm; then
          add_pkg nodejs
          add_pkg npm
        fi
        ! need_cmd curl && add_pkg curl
      else
        PACKAGES="__unsupported__"
      fi
      ;;
    *)
      PACKAGES="__unsupported__"
      ;;
  esac
  return 0
}

install_packages() {
  if [ "$AIRCODE_SKIP_BOOTSTRAP_DEPS" = "1" ]; then
    log "Skipping bootstrap dependency install because AIRCODE_SKIP_BOOTSTRAP_DEPS=1."
    return
  fi
  [ -n "$PACKAGES" ] || return 0
  [ "$PACKAGES" != "__unsupported__" ] || fail "automatic bootstrap dependency install is not supported on this OS; install git, Go, npm, and curl manually"

  os_name=$(uname -s)
  log "Installing bootstrap dependencies:$PACKAGES"
  case "$os_name" in
    Darwin)
      need_cmd brew || fail "Homebrew is required to auto-install bootstrap dependencies on macOS"
      # Intentional word splitting for package names.
      brew install $PACKAGES
      ;;
    Linux)
      SUDO=$(sudo_prefix)
      if need_cmd apt-get; then
        ${SUDO}apt-get update
        ${SUDO}apt-get install -y $PACKAGES
      elif need_cmd dnf; then
        ${SUDO}dnf install -y $PACKAGES
      elif need_cmd yum; then
        ${SUDO}yum install -y $PACKAGES
      elif need_cmd pacman; then
        ${SUDO}pacman -S --noconfirm $PACKAGES
      elif need_cmd apk; then
        ${SUDO}apk add $PACKAGES
      else
        fail "unsupported Linux package manager"
      fi
      ;;
    *)
      fail "unsupported OS: $os_name"
      ;;
  esac
}

ensure_bootstrap_dependencies() {
  needs_git="$1"
  detect_packages "$needs_git"
  install_packages

  [ "$needs_git" = "0" ] || need_cmd git || fail "git is required"
  need_cmd go || fail "Go is required"
  need_cmd npm || fail "npm is required for Codex/Claude/LSP installation"
  need_cmd curl || fail "curl is required for Hermes/OpenCode installers"
}

prepare_source_repo() {
  local_dir=$(script_dir)
  if is_repo_checkout "$local_dir"; then
    printf '%s\n' "$local_dir"
    return
  fi
  if is_repo_checkout "$(pwd)"; then
    printf '%s\n' "$(pwd)"
    return
  fi

  ensure_bootstrap_dependencies 1
  mkdir -p "$(dirname "$SOURCE_DIR")"
  if [ -d "$SOURCE_DIR/.git" ]; then
    log "Updating Air Code source at $SOURCE_DIR..."
    git -C "$SOURCE_DIR" fetch --depth 1 origin "$REPO_REF"
    if git -C "$SOURCE_DIR" diff --quiet && git -C "$SOURCE_DIR" diff --cached --quiet; then
      git -C "$SOURCE_DIR" checkout -q FETCH_HEAD
    else
      log "Source checkout has local changes; using existing checkout without changing files."
    fi
  else
    log "Cloning Air Code source into $SOURCE_DIR..."
    git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$SOURCE_DIR"
  fi
  printf '%s\n' "$SOURCE_DIR"
}

main() {
  repo_dir=$(prepare_source_repo)
  ensure_bootstrap_dependencies 0

  if [ "$AIRCODE_SERVICE" != "0" ]; then
    set -- --service "$@"
  fi
  if [ "$AIRCODE_YES" != "0" ]; then
    set -- --yes "$@"
  fi

  log "Starting Air Code installer from $repo_dir..."
  exec "$repo_dir/scripts/install_aircoded_server.sh" "$@"
}

main "$@"
