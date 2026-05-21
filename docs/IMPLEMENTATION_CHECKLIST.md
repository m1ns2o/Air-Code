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

## Next

- [ ] Add a richer folder picker with create-folder and recent-folder history.
- [ ] Add focused backend tests for workspace root traversal and symlink escape.
- [ ] Add real simulator launch smoke, not just app target build.
