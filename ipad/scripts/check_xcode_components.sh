#!/usr/bin/env bash
set -euo pipefail

echo "Air Code iPad Xcode component check"

if ! command -v xcode-select >/dev/null 2>&1; then
  echo "error: xcode-select is not available. Install Xcode first." >&2
  exit 1
fi

developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "${developer_dir}" || ! -d "${developer_dir}" ]]; then
  cat >&2 <<'MSG'
error: Xcode developer directory is not configured.
Open Xcode once, accept its license if prompted, then run:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
MSG
  exit 1
fi

echo "Xcode developer directory: ${developer_dir}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun is not available from the selected Xcode." >&2
  exit 1
fi

metal_path="$(xcrun -f metal 2>/dev/null || true)"
if [[ -z "${metal_path}" || ! -x "${metal_path}" ]]; then
  cat >&2 <<'MSG'
error: Metal Toolchain is missing.

Air Code uses SwiftTerm for the full iPad terminal. SwiftTerm includes a Metal
shader renderer, so Xcode needs the Metal Toolchain component to compile it.

Fix:
  1. Open Xcode > Settings > Components.
  2. Install Metal Toolchain.
  3. Restart Xcode.
  4. Clear only Air Code's DerivedData cache:
       rm -rf ~/Library/Developer/Xcode/DerivedData/AirCode-*
  5. Rebuild:
       cd ipad
       xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' clean build
MSG
  exit 1
fi

echo "Metal compiler: ${metal_path}"
xcrun metal -v 2>&1 | sed -n '1,4p'

echo "OK: required Xcode components are available."
