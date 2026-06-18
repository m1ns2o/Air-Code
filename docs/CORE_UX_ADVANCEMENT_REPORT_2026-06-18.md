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

빌드/실행 결과:

- bundle id: `dev.aircode.ipad`
- simulator: `iPad Pro 13-inch (M5)`
- app process: 정상 launch

## 확인된 후속 항목

- 현재 simulator Open Recent 화면에서 tap automation으로 최근 프로젝트를 눌러도 프로젝트 전환이 발생하지 않는 상태가 관찰됐다.
- 앱 렌더링과 빌드/실행은 정상이고, 이번 New File 변경은 하단 sheet 코드를 제거한 구조 변경으로 확인했다.
- 실제 프로젝트가 열린 상태에서 New File 버튼을 누르면 새 중앙 다이얼로그 경로만 사용된다.
- Open Recent tap 미동작은 file dialog 변경과 별개로, 최근 프로젝트 open request 또는 UI automation 좌표/상태 문제를 후속 진단해야 한다.

## 변경 파일

- `ipad/Sources/AirCodeClient/AgentChatView.swift`
- `ipad/Sources/AirCodeClient/AppShellView.swift`
- `ipad/Sources/AirCodeClient/ProjectSidebarView.swift`
- `docs/IMPLEMENTATION_CHECKLIST.md`
- `docs/TUI_PARITY_PROGRESS_KO.md`

