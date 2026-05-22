# Air Code Implementation Checklist

Last updated: 2026-05-22

## Current Status

- [x] Backend entrypoint restored: `cd backend && go run ./cmd/aircoded -config config.json`.
- [x] Backend now defaults to sandbox project access instead of the Air Code source repo.
- [x] Sandbox test folder created at `aircode-sandbox/sample-app`.
- [x] Server exposes workspace roots and open-folder APIs for VS Code-style folder selection.
- [x] iPad client has remote folder browsing/opening state and sidebar UI wiring.
- [x] iOS `AirCode.xcodeproj` app target restored and linked to local `AirCodeClient` Swift Package product.
- [x] Chat composer controls moved to the lower composer toolbar: model, Plan, Ultrathink, Caveman.
- [x] Agent streaming is transient: progress is shown while running, final transcript keeps final answer/changes.
- [x] Agent final answers no longer become red just because the text contains the word "error"; backend sends `kind`.
- [x] Large Changes blocks collapse scaffold-style to the first 3 files.
- [x] CodeEditorView syntax/theme colors now follow the selected Air Code Material theme.
- [x] Folder and chat sidebars can be resized by dragging their split handles.
- [x] Go files now use a custom `LanguageConfiguration.go()` so `.go` files receive syntax highlighting.
- [x] Remote folder browsing moved out of the Explorer tree into an Open Folder sheet.
- [x] Open Folder action uses a plain folder icon; folder creation uses the folder-plus icon inside the picker.
- [x] Open Folder picker can create a new folder under the selected remote folder and open it immediately.
- [x] Agent runs now write inspectable JSONL logs under `.aircode/runs/` in the opened project.
- [x] Codex reasoning is selected as levels (`Auto`, `Low`, `Medium`, `High`, `Ultrathink`) instead of a single boolean toggle.
- [x] Codex sessions are saved per project in `.aircode/sessions.json` and resumed with `codex exec resume` when enabled.
- [x] Remote run logs remain available server-side for debugging, but are no longer shown in the client UI.
- [x] Plan mode and Ultrathink were verified in sandbox run logs: `mode=plan`, `reasoningEffort=xhigh`, and CLI args include `model_reasoning_effort="xhigh"`.
- [x] Client-side run log viewer was removed; logs remain server-side under `.aircode/runs/` for debugging.
- [x] Agent provider and session controls moved to the Chat header.
- [x] Composer toolbar now includes concrete Codex model selection (`GPT-5.5`, `GPT-5.4`, `5.4 Mini`, `5.3 Codex`, `5.3 Spark`, `GPT-5.2`).
- [x] Goal mode added for `/goal` workflows, with `features.goals=true` passed to Codex CLI and `/goal` inserted at the start of the prompt.
- [x] Plan mode now starts Codex with the native `/plan` slash command instead of relying only on prompt decoration.
- [x] `aircoded` now has explicit `serve`, `setup`, and `doctor` subcommands while keeping the old `-config` run form compatible.
- [x] `aircoded serve` supports `-addr` overrides so smoke tests can run on isolated ports when a local server is already active.
- [x] `aircoded setup` can configure Codex, Claude Code, OpenCode, and Hermes install state in `config.json`; Caveman remains an internal chat mode.
- [x] Agent capabilities API added at `GET /v1/agents/capabilities` so the iPad selector uses installed/configured server agents instead of a hardcoded list.
- [x] Hermes provider boundary added as a CLI runner using `hermes chat --quiet -q "{{prompt}}"`, with provider/model arg insertion ready.
- [x] Full backend terminal sessions added with Go PTY, terminal create/close HTTP routes, and authenticated terminal WebSocket streams.
- [x] iPad bottom panel now uses SwiftTerm instead of the command-runner text field.
- [x] iPad terminal supports create, close, clear, reconnect, input forwarding, resize forwarding, and backend output rendering.
- [x] Terminal WebSocket now uses binary frames for PTY data, resize, close, exit, and error messages instead of JSON text frames.
- [x] Terminal sessions now track attach/detach state; detached sessions are reclaimed before enforcing `maxSessions`, and a configurable `detachedTimeoutSeconds` closes disconnected PTYs.
- [x] Terminal auto-start now retries after connection/project bootstrap, fixing the startup state that could leave the bottom panel stuck on `Disconnected`.
- [x] SwiftTerm is pinned to `1.13.0`; upstream `main` currently fails to compile due a missing `SyncDebug` symbol.
- [x] Agent setup now resolves commands from `PATH`, `~/.local/bin`, and Homebrew paths so Hermes installed by the official script is detected by Air Code.
- [x] Hermes is installed at `/Users/m1ns2o128/.local/bin/hermes` and enabled in `backend/config.json`.
- [x] `aircoded install` added for deployment server files: binary copy, config install/generation, and optional launchd/systemd user service files.
- [x] `aircoded install` now asks which agent CLIs to connect during install and can install/configure Codex, Claude Code, Hermes, or OpenCode in the same flow.
- [x] Scripted server installs can pass `-agents codex,claude,hermes`, `-agents none`, `-skip-agents`, and `-yes`.

## Verified

- [x] `cd backend && go test ./...`
- [x] `cd backend && go run ./cmd/aircoded setup -config config.json -check-only`
- [x] `cd backend && go run ./cmd/aircoded doctor -config config.json`
- [x] `cd backend && go run ./cmd/aircoded -config config.json`
- [x] `GET /health`
- [x] `GET /v1/projects`
- [x] `GET /v1/workspace-roots`
- [x] `GET /v1/workspace-roots/sandbox/tree?path=.`
- [x] `POST /v1/workspace/open`
- [x] `GET /v1/projects/sample-app/files?path=README.md`
- [x] `POST /v1/projects/sample-app/command`
- [x] `GET /v1/agents/capabilities`
- [x] `POST /v1/projects/sample-app/terminals`
- [x] `POST /v1/projects/sample-app/terminals/{terminalId}/close`
- [x] Backend server test verifies terminal WebSocket auth rejection and binary `input -> PTY -> output` streaming.
- [x] Backend server test verifies Korean UTF-8 input through binary terminal WebSocket: `한글입력`.
- [x] `cd backend && go run ./cmd/aircoded setup -config config.json -agents hermes -yes`
- [x] `cd backend && go run ./cmd/aircoded doctor -config config.json` reports Hermes ready.
- [x] `cd backend && go run ./cmd/aircoded install -dry-run -prefix /tmp/aircode-install-test -addr 127.0.0.1:18080 -service`
- [x] `/Users/m1ns2o128/.local/bin/hermes doctor`
- [x] `/Users/m1ns2o128/.local/bin/hermes chat --quiet -q "Return exactly: AIRCODE_HERMES_OK"` was attempted and correctly failed with provider/model configuration missing.
- [x] Backend install tests verify the install wizard can prompt for `codex` and write the configured agent command into the deployed config.
- [x] Backend install tests verify `-agents none` skips agent setup.
- [x] Install smoke with a fake `codex` binary verifies `aircoded install -agents codex` writes `agents.codex.enabled=true`, `installStatus=configured`, and keeps deployed config permissions at `0600`.
- [x] `cd ipad && swift build`
- [x] `cd ipad && swift test`
- [x] `cd ipad && xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build`
- [x] `CodeEditorView` Material theme mapping compiles in Swift Package and iOS app target.
- [x] Open Folder sheet and Go syntax configuration compile in Swift Package and iOS app target.
- [x] `POST /v1/workspace/folders` smoke tested on a temporary backend port.
- [x] Backend `project.CreateFolder` unit tests cover create/open and path-like name rejection.
- [x] Local Codex CLI checked: `codex exec resume [SESSION_ID] [PROMPT]` and `model_reasoning_effort` config overrides are available.
- [x] Local Codex `/goal` smoke: `codex exec "/goal"` returned the current goal status, confirming the slash command is recognized.

## Next

- [ ] Add a richer folder picker with create-folder and recent-folder history.
- [ ] Add focused backend tests for workspace root traversal and symlink escape.
- [ ] Run a successful real Hermes chat after choosing a provider with `hermes model` or adding a provider API key to `~/.hermes/.env`.
- [ ] Add a dedicated active-goal status endpoint if Codex exposes goal state through a stable noninteractive API.
- [ ] Add real simulator launch smoke, not just app target build.
