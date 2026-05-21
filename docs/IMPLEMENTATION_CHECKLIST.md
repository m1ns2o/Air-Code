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

## Verified

- [x] `cd backend && go test ./...`
- [x] `cd backend && go run ./cmd/aircoded -config config.json`
- [x] `GET /health`
- [x] `GET /v1/projects`
- [x] `GET /v1/workspace-roots`
- [x] `GET /v1/workspace-roots/sandbox/tree?path=.`
- [x] `POST /v1/workspace/open`
- [x] `GET /v1/projects/sample-app/files?path=README.md`
- [x] `POST /v1/projects/sample-app/command`
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
- [ ] Add optional Hermes provider integration after installing/configuring `hermes` on the server.
- [ ] Add a dedicated active-goal status endpoint if Codex exposes goal state through a stable noninteractive API.
- [ ] Add real simulator launch smoke, not just app target build.
