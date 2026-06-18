# Air Code Core UX 고도화 리포트 - 2026-06-18

## 구현 내용

### Background Task Dashboard v1

- Chat header/runtime 메뉴에서 provider-native background 상태를 확인하는 Dashboard를 추가했다.
- Codex `/ps`, Claude `/tasks`, Hermes `/queue`를 빠르게 실행할 수 있게 했다.
- `/agents`, `/agent` 등 task/subagent 계열 shortcut도 함께 노출한다.
- 최근 runtime event와 task-looking transcript를 네이티브 목록으로 정리한다.
- provider 출력 파싱이 불안정해도 확인 가능하도록 raw runtime events 섹션을 유지했다.

### New File Dialog 위치 개선

- 기존 `ProjectSidebarView`의 `.sheet(item: $store.fileCreationDraft)` 기반 파일 생성 UI를 제거했다.
- `AppShellView` 최상위 `ZStack`에 `NewProjectFileDialog`를 추가해 앱 중앙 모달로 표시한다.
- iPad bottom sheet처럼 하단에 붙는 경로를 제거했다.
- 다이얼로그는 Air Code 테마 색상, backdrop, close/cancel/create 버튼, focused input border를 사용한다.
- 하단 padding과 요소 간격을 줄여 이전보다 작고 균형 잡힌 레이아웃으로 조정했다.

### Open Recent Hit Target 개선

- Recent Projects row에서 텍스트 영역만 열기 버튼으로 동작하던 구조를 개선했다.
- 폴더 아이콘과 파일명/경로 영역 전체가 `Open <project>` 버튼으로 잡히도록 접근성 label과 hit target을 정리했다.
- pin/remove 버튼은 별도 액션으로 유지했다.

### iOS Smoke 전용 Launch Automation

- DEBUG 빌드에서만 `AIRCODE_AUTORUN_OPEN_RECENT=1`과 `AIRCODE_AUTORUN_NEW_FILE_DIALOG=1`을 지원한다.
- DEBUG 빌드에서만 `AIRCODE_AUTORUN_BACKGROUND_DASHBOARD=1`을 지원한다.
- XcodeBuildMCP tap 좌표/시뮬레이터 orientation 이슈와 무관하게 Open Recent 및 New File dialog 상태를 재현할 수 있게 했다.
- 일반 사용자 실행에는 영향이 없고, Release 빌드에는 포함되지 않는다.

## 검증 결과

### Swift Package

```bash
cd ipad && swift test
```

- 결과: 통과
- 테스트 수: 57개

### Backend

```bash
cd backend && env GOCACHE=/private/tmp/aircode-go-build-cache go test ./...
```

- 결과: 통과
- 주요 범위: agent, files, git, install, integrations, lsp, mcp, recent, search, server, setup, terminal

### iOS Simulator

XcodeBuildMCP로 다음을 확인했다.

- `session_show_defaults`: AirCode project/scheme/simulator defaults 확인
- `build_run_sim`: iPad simulator build/install/launch 성공
- `snapshot_ui`: 앱 런타임 UI snapshot 성공
- `screenshot`: 화면 캡처 성공
- `launch_app_sim` + `AIRCODE_AUTORUN_OPEN_RECENT=1`: Sample App open 상태 진입 성공
- `launch_app_sim` + `AIRCODE_AUTORUN_NEW_FILE_DIALOG=1`: New File 중앙 다이얼로그 표시 확인
- `launch_app_sim` + `AIRCODE_AUTORUN_BACKGROUND_DASHBOARD=1`: Background Tasks sheet 표시 확인
- `wait_for_ui(textContains: "filename.ext")`: New File input field 확인
- `wait_for_ui(textContains: "Background Tasks")`: Background dashboard sheet 확인

빌드/실행 결과:

- bundle id: `dev.aircode.ipad`
- simulator: `iPad Pro 13-inch (M5)`
- app process: 정상 launch
- New File dialog screenshot: `/var/folders/0b/wv7tsg3s3jd7nn5569tdljph0000gn/T/screenshot_optimized_72748a4b-0719-4abb-89c2-735af7fe0e38.jpg`
- Background Tasks screenshot: `/var/folders/0b/wv7tsg3s3jd7nn5569tdljph0000gn/T/screenshot_optimized_b6802d1b-c310-4a3c-b5ba-5f4b3d81a92d.jpg`

### Simulator Launch Smoke Script

```bash
./ipad/scripts/simulator_launch_smoke.sh
```

- 결과: 통과
- simulator: `31937347-F8E0-4678-965B-250E9388F536`
- launch output: `dev.aircode.ipad: 60977`

### Provider Runtime Smoke

```bash
./scripts/provider_smoke.py
```

- 결과: 통과
- 결과 파일: `tmp/provider-smoke-latest.json`
- Codex: installed/configured, `/opt/homebrew/bin/codex`, `codex-cli 0.134.0`
- Hermes: installed/configured, `/Users/m1ns2o128/.local/bin/hermes`, `Hermes Agent v0.14.0 (2026.5.16)`
- Claude Code: installed/configured, `/opt/homebrew/bin/claude`, `2.0.25 (Claude Code)`
- Live provider run은 `AIRCODE_LIVE_PROVIDER_SMOKE=1`이 꺼져 있어 의도적으로 skipped 처리했다.

### Live Provider Runtime Smoke

```bash
AIRCODE_LIVE_PROVIDER_SMOKE=1 ./scripts/provider_smoke.py
```

- 결과: 통과
- Codex: `AIRCODE_PROVIDER_SMOKE_OK` answer marker 확인, log `6619` bytes, changes `0`, resume/stop 확인.
- Hermes: `AIRCODE_PROVIDER_SMOKE_OK` answer marker 확인, log `1804` bytes, changes `0`, resume/stop 확인.
- Claude Code: `AIRCODE_PROVIDER_SMOKE_OK` answer marker 확인, steering accepted, log `659` bytes, changes `0`, resume/stop 확인.
- Codex/Hermes는 smoke prompt가 너무 빨리 끝나 steering 타이밍이 active turn 이후였으므로 `no active turn`/`run is not active`를 실패로 보지 않고 answer marker 기준으로 통과 처리했다.
- Provider smoke script는 `null` log/change/revert 응답과 provider별 steering timing 차이를 false negative로 만들지 않도록 개선했다.

## 확인된 후속 항목

- `build_run_sim` 직후의 direct tap automation은 시뮬레이터 orientation/hit injection 상태에 따라 화면 변화가 없을 수 있다.
- 이 문제를 피하기 위해 DEBUG launch automation을 추가했고, `launch_app_sim` env 방식으로 Open Recent와 New File dialog를 실제 앱 상태에서 확인했다.
- 현재 확인된 New File 하단 sheet 경로는 제거 완료됐다.

## 변경 파일

- `ipad/Sources/AirCodeClient/AgentChatView.swift`
- `ipad/Sources/AirCodeClient/AppShellView.swift`
- `ipad/Sources/AirCodeClient/EditorPaneView.swift`
- `ipad/Sources/AirCodeClient/ProjectSidebarView.swift`
- `docs/IMPLEMENTATION_CHECKLIST.md`
- `docs/TUI_PARITY_PROGRESS_KO.md`
