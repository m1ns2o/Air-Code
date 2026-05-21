# Air Code

Native iPad thin client plus Go backend for a remote AI coding editor.

## Local Backend

The default backend config intentionally points at a sandbox project, not this source repo:

- Workspace root: `./aircode-sandbox`
- Open project: `./aircode-sandbox/sample-app`

Run from the repo root:

```sh
./scripts/setup_sandbox.sh
cd backend
go run ./cmd/aircoded -config config.json
```

Health check:

```sh
curl http://127.0.0.1:8080/health
```

Authenticated API check:

```sh
curl -H 'Authorization: Bearer dev-token-change-me' http://127.0.0.1:8080/v1/projects
```

## iPad Client

The Swift package contains the reusable SwiftUI client shell, and `AirCode.xcodeproj`
contains the iOS app target:

```sh
cd ipad
swift build
swift test
xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build
```
