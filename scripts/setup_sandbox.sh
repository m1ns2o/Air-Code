#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SANDBOX="$ROOT_DIR/aircode-sandbox/sample-app"

mkdir -p "$SANDBOX/src"

cat > "$SANDBOX/README.md" <<'EOF'
# Air Code Sandbox

This folder is safe for Air Code agent testing.
EOF

cat > "$SANDBOX/src/main.go" <<'EOF'
package main

import "fmt"

func main() {
	fmt.Println("hello from air code sandbox")
}
EOF

if [ ! -d "$SANDBOX/.git" ]; then
  git init "$SANDBOX" >/dev/null
fi

git -C "$SANDBOX" add .
git -C "$SANDBOX" commit -m "Seed sandbox sample app" >/dev/null 2>&1 || true

printf 'Sandbox ready: %s\n' "$SANDBOX"
