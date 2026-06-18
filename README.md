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
go run ./cmd/aircoded serve -config config.json
```

Use `-addr` when you want an isolated local instance:

```sh
go run ./cmd/aircoded serve -config config.json -addr 127.0.0.1:18080
```

Agent installer/status commands:

```sh
cd backend
go run ./cmd/aircoded setup -config config.json
go run ./cmd/aircoded doctor -config config.json
go run ./cmd/aircoded doctor -config config.json -update
```

Register one MCP server with Codex, Claude Code, and Hermes together:

```sh
cd backend
go run ./cmd/aircoded mcp install -name my-tools -command /path/to/mcp-server -arg stdio -providers codex,claude,hermes
```

Preview the provider commands without changing provider config:

```sh
go run ./cmd/aircoded mcp install -name my-tools -command /path/to/mcp-server -arg stdio -dry-run
```

Install server files for deployment:

```sh
sh install.sh
```

Or, from a fresh remote machine after this repository is published:

```sh
curl -fsSL https://raw.githubusercontent.com/m1ns2o/air-code/main/install.sh | sh
```

If you already have the repository checked out and want to copy the development config:

```sh
./scripts/install_aircoded_server.sh --config backend/config.json --service
```

During install, Air Code asks whether to connect agent CLIs. Choose any
combination of `codex`, `claude`, `hermes`, and `opencode`; missing CLIs show
their installer commands and can be installed/configured in the same flow.

For scripted installs, pass the agents explicitly:

```sh
./scripts/install_aircoded_server.sh --config backend/config.json --service --agents codex,claude,hermes --yes
```

Useful install flags:

- By default, `aircoded install` checks for `rg` and installs `ripgrep` when it is missing. macOS uses Homebrew; Linux uses the available package manager (`apt-get`, `dnf`, `yum`, `pacman`, or `apk`).
- `-skip-deps`: skip server dependency installation such as `ripgrep`.
- `-agents codex,claude,hermes`: install/configure these agent CLIs after server files are installed.
- `-agents none` or `-skip-agents`: install only the server files and skip agent integration.
- `-yes`: run missing-agent installer commands without the extra confirmation prompt.
- When Hermes is configured, setup/install checks `hermes update --check`; interactive runs ask before updating, while `-yes` applies the update. Use `-skip-updates` to skip this.
- When Codex is configured, setup/install also enables Codex Goals by writing `features.goals = true` into `${CODEX_HOME:-~/.codex}/config.toml`.

This installs:

- `~/.aircode/bin/aircoded`
- `~/.aircode/etc/config.json`
- `~/Library/LaunchAgents/com.aircode.aircoded.plist` on macOS when `-service` is set
- `~/.config/systemd/user/aircoded.service` on Linux when `-service` is set

If you omit `-config`, the installer generates a deployment config with a random token and a default workspace root under `~/.aircode/workspaces`.

Full server deployment notes are in `docs/SERVER_DEPLOYMENT.md`.

Health check:

```sh
curl http://127.0.0.1:8080/health
```

Authenticated API check:

```sh
curl -H 'Authorization: Bearer dev-token-change-me' http://127.0.0.1:8080/v1/projects
```

Terminal sessions are enabled for the sandbox config and are exposed through:

- `POST /v1/projects/{projectId}/terminals`
- `WS /v1/projects/{projectId}/terminals/{terminalId}/stream`
- `POST /v1/projects/{projectId}/terminals/{terminalId}/close`

The terminal stream uses binary WebSocket frames:

- `0x01 + raw bytes`: terminal data, client-to-server input or server-to-client output
- `0x02 + cols:uint16 + rows:uint16`: resize
- `0x03`: close
- `0x04`: exit
- `0x05 + utf8`: error

Terminal session limits are controlled per project with `maxSessions`.
Disconnected PTYs are reclaimed before the limit is enforced, and
`detachedTimeoutSeconds` controls how long a detached terminal may wait for
reconnect before it is closed.

## iPad Client

The Swift package contains the reusable SwiftUI client shell, and `AirCode.xcodeproj`
contains the iOS app target:

```sh
cd ipad
swift build
swift test
xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build
```

iPad app distribution notes are in `docs/IPAD_DISTRIBUTION.md`. The Xcode
target includes the generated app icon asset catalog, is iPad-only, and can be
archived with a `DEVELOPMENT_TEAM` override for your Apple Developer account.
