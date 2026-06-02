# iPad Distribution

Air Code's iPad target is configured as an iPad-only app with a generated
asset-catalog app icon.

## App Settings

- Target: `AirCode`
- Bundle identifier: `dev.aircode.ipad`
- Display name: `Air Code`
- Category: Developer Tools
- Minimum iOS/iPadOS: 17.0
- Device family: iPad
- App icon asset: `ipad/App/Assets.xcassets/AppIcon.appiconset`
- Local network usage text: needed when the app connects to a development
  server on the same network.

`DEVELOPMENT_TEAM` is intentionally left blank in the project. Set it in Xcode
or override it from CI with your Apple Developer Team ID.

## Regenerate App Icons

The icon is deterministic and generated from a Swift/CoreGraphics script:

```sh
swift ipad/scripts/generate_app_icon.swift
```

## Terminal And Xcode Components

Air Code uses SwiftTerm as the single iPad terminal renderer.

SwiftTerm includes a Metal shader renderer, so Xcode must have the Metal
Toolchain component installed when building the default app. If Xcode shows:

```text
The Metal Toolchain was not installed and could not compile the Metal source files.
```

install it from `Xcode > Settings > Components > Metal Toolchain`, restart
Xcode, and clear the Air Code DerivedData cache:

```sh
rm -rf ~/Library/Developer/Xcode/DerivedData/AirCode-*
```

You can verify the local build environment with:

```sh
ipad/scripts/check_xcode_components.sh
```

## Build

Simulator build:

```sh
xcodebuild \
  -project ipad/AirCode.xcodeproj \
  -scheme AirCode \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Install directly on a connected iPad:

```sh
DEVELOPMENT_TEAM=YOUR_TEAM_ID ipad/scripts/install_on_device.sh
```

The device installer:

- Resolves Swift packages before building
- Builds `AirCode` with `generic/platform=iOS` by default, then installs to the
  device selected by `devicectl`
- Uses Xcode automatic signing with `-allowProvisioningUpdates`
- Installs through `xcrun devicectl`
- Launches `dev.aircode.ipad`

If no installable iPad is detected, connect and unlock the iPad, tap Trust This
Computer, and open `Xcode > Window > Devices and Simulators` once to finish
pairing. A paired but offline iPad with `tunnelState=unavailable` or
`ddiServicesAvailable=false` is intentionally skipped because `devicectl`
cannot install or launch apps on it.
You can target a specific device with `DEVICE_ID=<udid-or-device-name>`.
Override `BUILD_DESTINATION` only when you explicitly want xcodebuild to target
a specific device, for example `BUILD_DESTINATION=id=<xcode-device-id>`.

Device/archive build:

```sh
xcodebuild \
  -project ipad/AirCode.xcodeproj \
  -scheme AirCode \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/AirCode.xcarchive \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  archive
```

Export for App Store Connect or TestFlight:

```sh
xcodebuild \
  -exportArchive \
  -archivePath build/AirCode.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ipad/ExportOptions.sample.plist \
  -allowProvisioningUpdates
```
