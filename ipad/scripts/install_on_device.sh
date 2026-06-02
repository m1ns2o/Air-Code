#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-/tmp/AirCodeDeviceInstallDerivedData}"
BUNDLE_ID="${BUNDLE_ID:-dev.aircode.ipad}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DEVICE_ID="${DEVICE_ID:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
BUILD_DESTINATION="${BUILD_DESTINATION:-generic/platform=iOS}"

pick_device() {
  local json_path
  json_path="$(mktemp /tmp/aircode-devices.XXXXXX.json)"
  trap 'rm -f "${json_path}"' RETURN
  xcrun devicectl list devices --json-output "${json_path}" >/dev/null
  /usr/bin/python3 - "${json_path}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

devices = payload.get("result", {}).get("devices", [])

def identifier(device):
    return (
        device.get("identifier")
        or device.get("udid")
        or device.get("hardwareProperties", {}).get("udid")
        or device.get("connectionProperties", {}).get("tunnelIPAddress")
        or device.get("name")
    )

def is_installable(device):
    connection = device.get("connectionProperties", {})
    properties = device.get("deviceProperties", {})
    tunnel_state = str(connection.get("tunnelState", "")).lower()
    pairing_state = str(connection.get("pairingState", "")).lower()
    ddi_available = properties.get("ddiServicesAvailable")
    if pairing_state and pairing_state != "paired":
        return False
    if tunnel_state in {"unavailable", "disconnected"}:
        return False
    if ddi_available is False:
        return False
    return True

ipads = [
    device
    for device in devices
    if is_installable(device)
    and "ipad" in (
        str(device.get("name", ""))
        + " "
        + str(device.get("deviceType", ""))
        + " "
        + str(device.get("hardwareProperties", {}).get("deviceType", ""))
        + " "
        + str(device.get("hardwareProperties", {}).get("productType", ""))
    ).lower()
]
choice = ipads or [device for device in devices if is_installable(device)]
if not choice:
    sys.exit(1)
picked = choice[0]
value = identifier(picked)
if not value:
    sys.exit(1)
print(value)
PY
}

if [[ -z "${DEVICE_ID}" ]]; then
  if ! DEVICE_ID="$(pick_device)"; then
    cat >&2 <<'EOF'
No installable iPad was found by devicectl.

The iPad must be online with CoreDevice/DDI services available. Connect it by
USB or enable wireless debugging, then:
1. Unlock the iPad.
2. Tap Trust This Computer if prompted.
3. Open Xcode > Window > Devices and Simulators once if pairing is needed.
4. Re-run this script.

You can also pass DEVICE_ID=<udid-or-name> explicitly.
EOF
    exit 1
  fi
fi

build_args=(
  -project "${PROJECT_DIR}/AirCode.xcodeproj"
  -scheme AirCode
  -configuration "${CONFIGURATION}"
  -destination "${BUILD_DESTINATION}"
  -derivedDataPath "${DERIVED_DATA}"
  -allowProvisioningUpdates
)

if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
  build_args+=(DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}")
fi
if [[ -n "${BUNDLE_ID}" ]]; then
  build_args+=(PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}")
fi

echo "Building Air Code for device ${DEVICE_ID}..."
echo "Using build destination: ${BUILD_DESTINATION}"
rm -rf "${DERIVED_DATA}"
xcodebuild \
  -project "${PROJECT_DIR}/AirCode.xcodeproj" \
  -scheme AirCode \
  -derivedDataPath "${DERIVED_DATA}" \
  -resolvePackageDependencies
xcodebuild "${build_args[@]}" build

APP_PATH="$(find "${DERIVED_DATA}/Build/Products" -path "*/${CONFIGURATION}-iphoneos/AirCode.app" -type d -print -quit)"
if [[ -z "${APP_PATH}" ]]; then
  echo "AirCode.app was not produced under ${DERIVED_DATA}/Build/Products." >&2
  exit 1
fi

echo "Installing ${APP_PATH} on ${DEVICE_ID}..."
xcrun devicectl device install app --device "${DEVICE_ID}" "${APP_PATH}"

echo "Launching ${BUNDLE_ID}..."
xcrun devicectl device process launch --device "${DEVICE_ID}" --terminate-existing "${BUNDLE_ID}"

echo "Air Code was installed and launched on ${DEVICE_ID}."
