#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-/tmp/AirCodeSimulatorSmokeDerivedData}"
BUNDLE_ID="${BUNDLE_ID:-dev.aircode.ipad}"

pick_device() {
  xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
devices = [d for group in data.get("devices", {}).values() for d in group if d.get("isAvailable")]
booted_ipads = [d for d in devices if d.get("state") == "Booted" and "iPad" in d.get("name", "")]
ipads = [d for d in devices if "iPad" in d.get("name", "")]
booted = [d for d in devices if d.get("state") == "Booted"]
choice = (booted_ipads or ipads or booted or devices)
if not choice:
    sys.exit(1)
print(choice[0]["udid"])
'
}

DEVICE_ID="${DEVICE_ID:-$(pick_device)}"
if [[ -z "${DEVICE_ID}" ]]; then
  echo "No available iOS simulator device found." >&2
  exit 1
fi

echo "Using simulator: ${DEVICE_ID}"
xcrun simctl boot "${DEVICE_ID}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${DEVICE_ID}" -b

rm -rf "${DERIVED_DATA}"
xcodebuild \
  -project "${ROOT_DIR}/AirCode.xcodeproj" \
  -scheme AirCode \
  -configuration Debug \
  -destination "id=${DEVICE_ID}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet \
  build

APP_PATH="$(find "${DERIVED_DATA}/Build/Products" -path "*/Debug-iphonesimulator/AirCode.app" -type d -print -quit)"
if [[ -z "${APP_PATH}" ]]; then
  echo "AirCode.app was not produced under ${DERIVED_DATA}/Build/Products." >&2
  exit 1
fi

xcrun simctl install "${DEVICE_ID}" "${APP_PATH}"
LAUNCH_OUTPUT="$(xcrun simctl launch "${DEVICE_ID}" "${BUNDLE_ID}")"
echo "${LAUNCH_OUTPUT}"

if [[ "${LAUNCH_OUTPUT}" != *"pid:"* && ! "${LAUNCH_OUTPUT}" =~ :[[:space:]]*[0-9]+$ ]]; then
  echo "Launch did not report a process id." >&2
  exit 1
fi

echo "Air Code simulator launch smoke passed."
