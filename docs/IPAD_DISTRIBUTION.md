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

## Build

Simulator build:

```sh
xcodebuild \
  -project ipad/AirCode.xcodeproj \
  -scheme AirCode \
  -destination 'generic/platform=iOS Simulator' \
  build
```

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
