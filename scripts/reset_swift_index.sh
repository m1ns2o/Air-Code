#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="${HOME}/Library/Developer/Xcode/DerivedData"

echo "Resetting Air Code Swift index/build caches..."

rm -rf "${ROOT_DIR}/.build"
rm -rf "${ROOT_DIR}/ipad/.build"

if [[ -d "${DERIVED_DATA_DIR}" ]]; then
  find "${DERIVED_DATA_DIR}" -maxdepth 1 -type d -name "AirCode-*" -print -exec rm -rf {} +
fi

echo "Resolving root Swift package for SourceKit-LSP..."
(cd "${ROOT_DIR}" && swift package resolve)

echo "Resolving iPad Swift package for Xcode/SPM..."
(cd "${ROOT_DIR}/ipad" && swift package resolve)

echo "Done. Reload VS Code/Cursor or restart SourceKit-LSP if diagnostics are still stale."
