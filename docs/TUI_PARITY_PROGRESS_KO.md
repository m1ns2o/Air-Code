# Air Code TUI 기능 대체 진행상황

이 문서는 Codex/Claude/Hermes TUI에서 자주 쓰는 기능을 Air Code iPad UX로 옮기는 진행상황을 한국어로 추적하기 위한 문서다.

## 우선순위

- [x] 1. Context Attachment
  - [x] `@file` 파일 언급
  - [x] `/mention` 파일 첨부
  - [x] `/auto-context` selection 우선, 없으면 cursor 주변 자동 컨텍스트
  - [x] 서버 safe path resolver를 통한 파일 읽기
- [x] 2. Permission / Approval UI
  - [x] provider 권한 상태 표시
  - [x] Chat header의 Run Settings로 권한/응답 스타일/컨텍스트 설정 이동
  - [x] Codex per-run approval/sandbox override
  - [x] Claude Code `--permission-mode` per-run override
  - [x] Hermes native `/yolo` permission override
  - [x] 실행 중 approval 요청을 transcript와 분리된 urgent card로 표시하는 UI 골격
  - [x] provider inline approval event를 실제 approve/deny API로 연결
  - [x] run별 approval timeline 기록
  - [x] Approval Center pending/history UI
- [x] 3. MCP / Skills / Hooks 관리
  - [x] Codex / Claude / Hermes 공통 MCP 설치 상태
  - [x] iPad 공통 MCP 추가 UI
  - [x] provider별 skills/hooks 상태 확인
  - [x] Codex apps/connectors, Codex plugins, Claude plugins를 공통 기능처럼 섞지 않고 개별 provider 섹션으로 분리
  - [x] reload, doctor, 설정 링크를 provider-native slash command 어댑터 버튼으로 연결
  - [x] 기존 항목 browse/edit/remove UI
  - [x] MCP marketplace 검색/설치 preview UI
- [x] 4. Agent Runtime Timeline
  - [x] agent started/log/final/changes 이벤트 타임라인
  - [x] 반복 progress 로그 접기
  - [x] run별 상태 추적
  - [x] Runtime / Tool Call Inspector
- [ ] 5. Conversation Compaction / Context Usage
  - [x] provider-native context/status 사용량 어댑터 검증
  - [x] `/compact` provider adapter forwarding
  - [x] provider-native compact passthrough 정리
- [x] 6. Subagent / Branch / Rewind
  - [x] provider별 지원 가능 여부 표시
  - [x] provider-native branch/rewind adapter 설계
  - [x] subagent/task/thread/queue 진입점 UI
- [x] 7. Review UI
  - [x] `/review`, `/security-review`, `/code-review` run 태깅
  - [x] final answer best-effort finding parser
  - [x] iPad Review Findings panel

## 이번 배치

- [x] Context Attachment 구현
- [x] backend agent context 렌더링 테스트
- [x] iPad mention parser 테스트
- [x] `docs/IMPLEMENTATION_CHECKLIST.md` 완료 체크 갱신
- [x] git commit
- [x] Provider Command Adapter 전환
- [x] Provider task command adapter 전환
- [x] Provider command allowlist 확장
- [x] iPad MCP install UI
- [x] Codex/Claude/Hermes native session picker/import 공통화
- [x] provider별 plugin/connector 상태 카드 분리
- [x] Chat controls / Permission UI 재배치

## 진행 메모

- TUI 명령어는 Air Code가 임의로 재구현하지 않고, Codex/Claude/Hermes에 내장 기능이 있으면 provider adapter를 통해 우선 전달한다.
- Air Code native UI는 provider 기능을 대체하는 곳이 아니라 상태 표시, 첨부, diff, revert 같은 remote editor control plane 역할을 맡는다.
- 모든 파일 경로는 서버 project root 기준 relative path만 허용한다.
- 현재 `/auto-context`는 전체 열린 파일을 보내지 않고, CodeEditorView의 현재 selection을 우선 첨부한다. selection이 없으면 cursor 전후 60줄, 최대 20,000자만 첨부한다. 전체 파일은 `@file` 또는 `/mention <path>`가 담당한다.

### 2026-05-28 Prompt Attachments / Runtime Inspector / Approval Center / MCP Marketplace

- iPad composer가 붙여넣은 이미지를 `UIPasteboard`에서 받아 prompt attachment로 업로드한다.
- Files picker로 파일을 첨부하고, prompt 위 chip tray에서 파일명/이미지 여부를 확인한 뒤 제거할 수 있다.
- Backend `POST /v1/projects/{projectId}/attachments`가 `.aircode/attachments/{attachmentId}`에 원본과 metadata를 저장한다.
- Agent run request는 `context`와 별도로 `attachments`를 전달하며, 서버는 텍스트 preview 또는 이미지/server-local path reference를 `<aircode_attachments>` 블록으로 렌더링한다.
- Codex app-server tool call 시작/완료 이벤트를 `agent.tool.started`/`agent.tool.finished`로 normalize하고, iPad Runtime Inspector에서 Tool Calls/Logs/Approvals를 볼 수 있게 했다.
- Approval Center를 추가해 pending/history approval을 분리해서 보고, pending 항목은 Approve/Deny를 실행할 수 있다.
- MCP provider별 on/off는 제거하고, configured provider 전체에 설치하는 방식으로 단순화했다.
- `GET /v1/integrations/mcp/catalog/search`가 official MCP Registry, Smithery, Glama source를 검색하고 fallback catalog를 제공한다.
- iPad Integrations sheet에 Browse MCP 검색/preview/Install handoff를 추가했다.
- 검증:
  - `cd backend && go test ./...`
  - `cd ipad && swift test`
  - `cd ipad && xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build -quiet`
  - 임시 서버 `127.0.0.1:18084`에서 MCP catalog search, attachment upload, approval list smoke 확인 후 서버 종료

### 2026-05-28 실사용 안정성 / SourceKit 진단 정리

- `AirCodeStore.swift`에서 `AirCodeAPI` 메서드가 없다고 보이는 문제는 실제 소스 누락이 아니라, repo root에 SwiftPM manifest가 없어 VS Code/Cursor SourceKit-LSP가 오래된/부분 타입 정보를 보는 문제로 확인했다.
- root `Package.swift`를 추가해 repo root에서 열어도 `ipad/Sources/AirCodeClient`가 동일한 `AirCodeClient` target으로 인덱싱되도록 했다.
- stale SourceKit 캐시를 빠르게 지울 수 있도록 `scripts/reset_swift_index.sh`를 추가했다.
- 검증:
  - `swift package describe`
  - `swift test`
  - `cd ipad && swift test`
  - `cd backend && env GOCACHE=/private/tmp/aircode-go-build-cache go test ./...`
  - `cd ipad && xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build -quiet`

## 완료 기록

### 2026-05-24 Context Attachment

- Backend `StartRequest.context` 추가.
- 서버 agent runner가 `file`, `openFile`, `selection` 컨텍스트를 `<aircode_context>` 블록으로 렌더링하도록 구현.
- `file` 컨텍스트는 서버에서 project root 기준 safe resolver로 읽고, traversal/symlink escape는 기존 resolver 경계에서 차단.
- iPad Chat 입력창에 `@file` 자동완성 팔레트와 첨부 chip UI 추가.
- `/mention <path>`로 다음 prompt에 파일 첨부 가능.
- `/auto-context on|off|status`로 선택된 열린 파일 자동 첨부 설정 가능.
- 검증:
  - `cd backend && go test ./...`
  - `cd ipad && swift test`
  - `cd ipad && ./scripts/simulator_launch_smoke.sh`
  - `cd ipad && xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build -quiet`

### 2026-05-24 Permission Policy Panel

- Backend `GET /v1/projects/{projectId}/permissions` 추가.
- 서버가 agent별 approval mode, sandbox mode, risk level을 현재 config args 기준으로 추론.
- 프로젝트 command runner/terminal policy를 같은 응답에 포함.
- iPad Chat 상단에 Permissions 카드 추가.
- `/permissions` slash command는 이후 provider adapter forwarding으로 변경.
- 남은 작업:
  - 실제 provider run 중 inline approval/reject 이벤트를 가로채는 흐름.
  - run별 approval event log.
- 검증:
  - `cd backend && go test ./...`
  - `cd ipad && swift test`
  - `cd ipad && xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build -quiet`

### 2026-05-27 Chat Controls / Permission Settings

- Chat 상단 header에 Run Settings 버튼을 추가하고, 기존 inline Permissions 카드는 제거.
- Composer 하단은 Mode, Reasoning, Send 중심으로 축소.
- Auto Context는 입력창 위 chip bar의 토글형 컨트롤로 이동.
- Caveman은 `Run Settings > Response Style`로 이동.
- 권한 UI는 provider별 네이티브 기능을 같은 레벨로 묶어 표시:
  - Codex: approval `Ask / On Failure / Never`, sandbox `Read Only / Workspace Write / Full Access`.
  - Claude Code: native `--permission-mode`의 `plan / acceptEdits / bypassPermissions`.
  - Hermes: native `/yolo` 우회 설정.
- Backend agent runner가 per-run `approvalMode`, `sandboxMode`를 받아 provider별 CLI/app-server 옵션으로 변환.
- 실행 중 approval 이벤트가 들어오면 별도 urgent card에 Approve/Deny 버튼을 표시하도록 UI와 timeline 모델을 추가. 현재 provider adapter가 inline decision API를 노출하지 않으면 안내 메시지를 표시한다.
- Run Settings는 처음부터 large sheet로 열리며 inline title과 축소된 top padding을 사용한다.
- MCP add/edit sheet는 기본 Form 대신 Air Code 테마의 custom section UI로 변경해 상단 여백과 색상 이질감을 줄였다.
- 검증:
  - `cd backend && go test ./...`
  - `cd ipad && swift test`
  - `cd ipad && ./scripts/simulator_launch_smoke.sh`

### 2026-05-28 Inline Approval Decision API

- Backend `POST /v1/projects/{projectId}/agents/runs/{runId}/approval` 추가.
- Codex app-server의 server-initiated approval request를 Air Code `agent.approval` 이벤트로 normalize하고, Approve/Deny 선택을 app-server JSON-RPC response로 되돌려 보낸다.
- Hermes는 active run 중 `/approve` 또는 `/deny`를 runtime steering으로 전달한다.
- Claude Code는 아직 안전한 headless approval decision transport가 확인되지 않아 명확한 unsupported error를 반환한다.
- iPad `PendingApprovalCard`의 Approve/Deny 버튼이 실제 API를 호출하며, 실패 시 pending card를 유지하고 timeline/error 메시지를 남긴다.
- 검증:
  - `cd backend && go test ./...`
  - `cd ipad && swift test`

### 2026-05-28 Auto Context v2

- `NativeCodeEditor`가 CodeEditorView `Position.selections`를 읽어 현재 selection/cursor context를 `AirCodeStore`로 전달한다.
- Auto Context 기본 동작을 “선택된 열린 파일 전체”에서 “selection 우선, 없으면 cursor 주변 60줄”로 변경했다.
- Context chip은 실제 첨부 기준에 맞춰 `Selection`, `Around cursor`, `@ path` 중심으로 표시된다.
- Backend context renderer에 `cursor` attachment type을 추가하고, 기존 `selection` line range 렌더링을 테스트로 고정했다.
- 전체 파일 첨부는 그대로 `@file` mention 또는 `/mention <path>`를 사용한다.
- 검증:
  - `cd backend && go test ./...`
  - `cd ipad && swift test`

### 2026-05-28 Provider Runtime Smoke 자동화

- `scripts/provider_smoke.py` 추가.
- 스크립트는 sandbox `sample-app`만 열고, 임시 `aircoded` 서버를 구동한 뒤 종료한다. 이미 같은 주소에 서버가 있으면 기존 서버는 종료하지 않는다.
- 기본 실행은 provider capability와 CLI version만 확인하고 실제 LLM 호출은 건너뛴다.
- 실제 start/steer/stop/session resume/changes/revert run 검증은 `AIRCODE_LIVE_PROVIDER_SMOKE=1 ./scripts/provider_smoke.py`로 명시적으로 켠다.
- auth/config/credit 부족은 실패가 아니라 `skipped: auth/config missing`으로 기록한다.
- 2026-05-28 검증 결과:
  - Codex: `codex-cli 0.134.0`, configured, live skipped.
  - Hermes: `Hermes Agent v0.14.0`, configured, live skipped.
  - Claude Code: `2.0.25`, configured, live skipped.
  - 결과 JSON: `tmp/provider-smoke-latest.json`.

### 2026-05-28 Usage / Context / Cost 패널

- Backend `GET /v1/projects/{projectId}/agents/status?agent=...` 추가.
- 응답은 Air Code 저장 transcript 기준 message count, approximate chars, saved session id, provider CLI version을 항상 제공한다.
- Hermes는 안전한 headless `hermes status` 출력이 가능하면 raw status를 함께 표시한다.
- Codex/Claude는 현재 안전한 headless token/window usage 명령이 확인되지 않아 raw usage 대신 명확한 note를 반환한다.
- iPad Run Settings에 `Usage` 섹션을 추가해 provider version, session id, transcript chars, raw status/notes를 확인할 수 있게 했다.
- 검증:
  - `cd backend && go test ./...`
  - `cd ipad && swift test`
  - 임시 서버 `127.0.0.1:18083`에서 Codex/Hermes/Claude status endpoint smoke 후 서버 종료.

### 2026-05-28 Review Findings UI

- `/review`, `/security-review`, `/code-review`로 시작한 run을 review run으로 태깅한다.
- Provider final answer에서 `severity file:line message` 또는 `file:line severity message` 형태를 best-effort로 파싱한다.
- 파싱 성공 시 Chat transcript에 `Review Findings` 패널을 표시하고, severity 색상과 파일/라인을 보여준다.
- finding을 누르면 해당 파일의 diff를 열어 바로 확인할 수 있다.
- 파싱 실패 시 기존 final answer 버블을 그대로 표시해서 provider 출력 차이로 UI가 깨지지 않게 했다.
- 검증:
  - `cd backend && go test ./...`
  - `cd ipad && swift test`

### 2026-05-28 Branch / Rewind / Subagent Header UI

- Chat header에 provider-native runtime actions 메뉴를 추가했다.
- Codex는 `/agent`, `/side`, `/fork`, `/ps`를 실행 진입점으로 제공한다.
- Claude Code는 `/branch`, `/rewind`, `/agents`, `/tasks`를 실행 진입점으로 제공한다.
- Hermes는 `/thread`, `/queue`, `/rollback`을 실행 진입점으로 제공한다.
- 이 메뉴는 Air Code 자체 branch/session/subagent engine을 만들지 않고 provider slash command를 그대로 run/steering 흐름에 전달한다.
- 검증:
  - `cd ipad && swift test`

### 2026-05-24 MCP / Skills / Hooks Status

- Backend `GET /v1/integrations/status` 추가.
- MCP는 `aircoded mcp install`로 Codex, Claude Code, Hermes에 함께 등록하는 명령을 iPad에 표시.
- Backend `POST /v1/integrations/mcp/install` 추가.
- iPad Integrations 카드의 `+` 버튼에서 MCP 이름, command/http transport, args, env를 입력하면 Codex/Claude/Hermes에 동시에 등록한다.
- 서버 config의 agent command를 사용하므로 `aircoded setup/install`이 찾은 서버-local CLI 경로도 MCP 등록에 사용된다. VS Code/Cursor extension 내부 바이너리는 자동 탐색하지 않는다.
- Skills/Hooks는 provider-native 관리 영역으로 표시하고, 현재 agent 설치/설정 상태를 함께 노출.
- iPad Chat 상단에 Integrations 카드 추가.
- `/mcp`, `/skills`, `/hooks` slash command는 이후 provider adapter forwarding으로 변경.
- Hermes `/skills ...`는 기존처럼 Hermes native command로 passthrough 유지.
- 남은 작업:
  - 설치/수정 wizard를 iPad에서 안전하게 호출하는 흐름.
- 검증:
  - `cd backend && go test ./...`
  - `cd ipad && swift test`
  - `cd ipad && xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build -quiet`

### 2026-05-24 Agent Runtime Timeline

- iPad가 `agent.started`, `agent.log`, `agent.finished` 이벤트를 run별 timeline event로 누적.
- progress 이벤트는 같은 내용이 반복되면 중복 기록을 건너뜀.
- Chat 상단 Runtime 카드에서 최근 4개 이벤트를 기본 표시하고, 펼치면 최근 12개까지 확인.
- started/session/final/error/completed/stopped 상태별 아이콘과 색상 적용.
- run 전환 시 project open 흐름에서 timeline 초기화.
- 검증:
  - `cd backend && go test ./...`
  - `cd ipad && swift test`
  - `cd ipad && xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build -quiet`

### 2026-05-24 Provider Command Adapter

- Air Code 자체 compact API 대신 provider 내장 slash command를 우선 사용하도록 변경.
- `ProviderCommandAdapter`가 Codex/Claude/Hermes별 지원 command set을 가지고 parser가 provider-native prompt로 넘김.
- `/permissions`, `/mcp`, `/skills`, `/hooks`, `/compact`, `/context`, `/status`, `/usage`, `/cost` 등은 지원 agent에서 native adapter로 전달.
- `/plan`, `/goal`은 원문 slash command를 유지한 채 Air Code run metadata만 붙이고, 서버가 provider CLI 옵션을 함께 적용하도록 정리.
- `/model`, `/diff`, Codex `/fast`, Claude `/effort`, `/review`, `/security-review`, `/debug`, `/run`, `/verify`, `/simplify`, `/init`, `/clear`는 지원 provider에서 Air Code 자체 처리보다 provider-native command 전달을 우선한다.
- 추가 wrapper: Codex `/new`, `/resume`, `/stop`, `/apps`, `/debug-config`, `/sandbox-add-read-dir`, Claude `/code-review`, `/copy`, `/ide`, `/theme`, `/statusline`, `/rename`, `/allowed-tools`, `/stats`, `/checkpoint`, `/bashes`, Hermes `/provider`, `/resume`, `/thread`, `/approve`, `/deny`, `/restart`, `/update`.
- Air Code status 카드들은 slash command 대체물이 아니라 sidecar 관찰 UI로 유지.
- Provider가 지원하지 않는 명령은 full terminal에서 provider TUI를 사용하라는 메시지를 표시.
- Hermes는 `session_id:` 또는 `hermes --resume <id>` 출력 파싱으로 Air Code 세션 저장/재개를 지원한다.
- Hermes native session import 추가: 서버가 `hermes sessions list`로 CLI/Discord/Telegram/Slack 등 Hermes SQLite session 목록을 가져오고, iPad Session 메뉴에서 선택하면 `hermes sessions export --session-id <id> -`로 transcript를 가져와 Air Code saved session/conversation에 저장한다.
- Discord/Telegram/Slack 등 gateway session은 Hermes 자체 SQLite session과 gateway가 관리하므로, Air Code가 동일 session ID를 import하면 이후 Hermes prompt는 `--resume <id>`로 이어갈 수 있다. gateway 설정/토큰/채널 매핑 UI는 아직 Hermes CLI에 맡긴다.
- Codex/Claude native session import 추가: 서버가 `~/.codex/sessions/**/*.jsonl`와 `~/.claude/projects/**/*.jsonl`을 읽어 기존 provider session을 Air Code saved session/conversation으로 가져온다.
- iPad Session 메뉴는 Codex/Claude/Hermes 모두 `Native Sessions` 섹션을 사용한다.
- Native session에는 Air Code 자체 fallback 세션을 만들지 않고, provider native `sessionId`에 프로젝트 태그만 붙인다.
- 프로젝트 태그는 기본적으로 열린 프로젝트 이름/폴더명이며, Codex/Claude는 native JSONL의 `cwd`가 현재 project root 안이면 자동으로 `Current Project`로 분류한다.
- Hermes는 CLI session 목록에 프로젝트 태그가 없으므로 import 또는 실제 run으로 사용된 Hermes `sessionId`를 `.aircode/native-session-tags.json`에 기록해서 다음 조회 때 `Current Project`로 분류한다.
- Session 메뉴는 `Current Project`에 해당하는 provider별 세션 하나만 보여준다. 다른 프로젝트 세션과 session id/cwd 형태의 긴 표시값은 숨긴다.
- Integrations 카드는 공유 MCP와 별개로 Codex Apps/Connectors, Codex Plugins, Claude Plugins를 개별 provider 섹션으로 표시한다. Claude plugin manager와 Codex plugin marketplace는 서로 다른 개념이므로 공통 plugin UI로 합치지 않는다.
- `/goals`와 `.aircode/goals.json` 기반 Air Code 자체 goal 상태는 제거했다. Codex와 Claude Code 모두 provider-native `/goal`을 지원하므로 Air Code는 `/goal`을 그대로 전달하고, 상태 확인/clear/resume도 provider 세션의 `/goal`, `/goal clear`, native resume 기능에 맡긴다.
- Integrations 카드 하단에 선택된 provider가 지원하는 `/mcp`, `/skills`, `/hooks`, `/doctor`, `/debug-config`, `/config`, `/reload-mcp`, `/reload-skills`, `/reload-plugins` shortcut을 자동 필터링해 보여준다. 버튼은 Air Code native 설정을 만들지 않고 provider adapter로 그대로 실행한다.
- `GET /v1/integrations/items`가 provider CLI와 로컬 agent home을 조사해 MCP, Skills, Hooks, Apps, Plugins 항목을 section으로 반환한다.
- `POST /v1/integrations/items/action`이 지원 가능한 remove/update만 수행한다. MCP는 provider CLI remove/update를 사용하고, 로컬 Skills/Hooks는 `~/.codex`, `~/.claude`, `~/.hermes`의 허용된 user-owned root 아래 항목만 삭제한다.
- iPad Manage Integrations sheet에서 기존 항목을 browse하고, MCP는 provider별 edit/reinstall sheet로 수정하며, remove는 확인 alert 이후 실행한다. Codex cache apps/plugins와 Hermes bundled plugins처럼 provider-managed 항목은 read-only로 표시한다.
- 검증:
  - `cd backend && go test ./...`
  - `cd ipad && swift test`
  - `cd ipad && xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build -quiet`

### 2026-05-28 LSP / Code Intelligence

- Air Code 서버에 `internal/lsp` manager를 추가했다.
- 서버가 project별 language server process를 stdio JSON-RPC로 실행하고, iPad는 열린 문서의 버퍼/커서 정보만 보낸다.
- 1차 지원 언어:
  - TypeScript / JavaScript / React: `.ts`, `.tsx`, `.js`, `.jsx`
  - Python: `.py`
  - Vue: `.vue`
- Backend API:
  - `GET /v1/lsp/capabilities`
  - `POST /v1/projects/{projectId}/lsp/documents/open`
  - `POST /v1/projects/{projectId}/lsp/documents/change`
  - `POST /v1/projects/{projectId}/lsp/documents/close`
  - `GET /v1/projects/{projectId}/lsp/diagnostics`
  - `POST /v1/projects/{projectId}/lsp/completion`
  - `POST /v1/projects/{projectId}/lsp/hover`
  - `POST /v1/projects/{projectId}/lsp/definition`
  - `POST /v1/projects/{projectId}/lsp/code-actions`
- Diagnostics는 서버에서 캐시하고 `lsp.diagnostics` WebSocket 이벤트로 iPad에 push한다.
- iPad editor는 diagnostics를 CodeEditorView message로 표시하고, 하단 `Problems` 탭에서 project diagnostics를 정렬해 보여준다.
- Completion은 `Ctrl+Space` 및 `.` 입력 후 debounce로 요청한다.
- Definition은 `Cmd+B`, hover는 `Cmd+I`로 요청한다.
- 큰 파일은 2MB 초과 시 LSP sync를 끄고 상태 메시지를 반환한다.
- `aircoded setup/install`에 `-language-servers` 옵션을 추가했다.
  - 기본 추천은 TypeScript/JavaScript/React + Python.
  - Vue는 TypeScript SDK를 자동 탐색해 `--tsdk`를 붙일 수 있으면 붙인다.
- 검증:
  - `cd backend && env GOCACHE=/private/tmp/aircode-go-build-cache go test ./...`
  - `cd ipad && swift test`
  - `cd ipad && xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build -quiet`
  - `cd ipad && ./scripts/simulator_launch_smoke.sh`

### 2026-05-28 프롬프트 프리징 / TS Vue 하이라이트 안정화

- 프롬프트 전송 후 UI가 멈추는 경로를 줄이기 위해 event stream과 terminal stream 수신 루프를 detached background task로 분리했다.
- WebSocket 수신은 백그라운드에서 계속 돌고, 실제 UI 상태 변경만 main actor로 돌아오도록 정리했다.
- agent progress 로그는 너무 자주 timeline에 쌓이지 않도록 throttle을 추가했다.
- Runtime detail/title은 긴 로그가 그대로 SwiftUI 렌더 트리에 들어가지 않도록 길이를 제한했다.
- streaming 중 자동 스크롤은 반복 애니메이션을 제거해서 긴 답변/생각 로그에서 UI 부하를 줄였다.
- `.ts`, `.tsx`, `.js`, `.jsx`, `.vue` 확장자가 CodeEditorView에서 plain text로 떨어지던 문제를 수정했다.
- JavaScript / TypeScript / Vue용 LanguageConfiguration을 추가해서 기본 syntax highlight가 적용된다.
- 검증:
  - `cd ipad && swift test`
  - `cd ipad && xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build -quiet`
  - `cd ipad && ./scripts/simulator_launch_smoke.sh`

### 2026-05-28 자동완성 / 하이라이트 확장

- 자동완성이 `content.last == "."` 기준으로만 동작하던 문제를 수정했다.
- 이제 editor cursor snapshot 기준으로 `.` 입력 또는 식별자 prefix 2글자 이상 입력 시 debounce 후 completion을 요청한다.
- text change 직후 cursor snapshot 반영 지연을 줄여 자동완성 요청 위치가 stale cursor에 묶이는 문제를 완화했다.
- 서버 LSP는 completion, hover, definition, code-action 요청 직전에 현재 unsaved buffer를 language server에 먼저 sync한다.
- TypeScript language server recipe에 `.mjs`, `.cjs`, `.mts`, `.cts`를 추가했다.
- CodeEditorView syntax highlight 매핑을 다음 언어/파일로 확장했다.
  - HTML / XML / SVG
  - CSS / SCSS / Sass / Less
  - JSON / YAML / TOML / Markdown
  - Shell / Dockerfile / Makefile
  - Rust / Java / Kotlin / C / C++ / C# / PHP / Ruby / Dart
- 현재 로컬 머신에는 `typescript-language-server`, `pyright-langserver`, `vue-language-server`가 설치되어 있지 않음을 확인했다. 실제 LSP 자동완성은 서버에서 language-server 설치/setup을 완료해야 동작한다.
- 검증:
  - `cd backend && env GOCACHE=/private/tmp/aircode-go-build-cache go test ./...`
  - `cd ipad && swift test`

### 2026-05-28 LSP 설치 / 초기 서버 설정 기본값

- 로컬 개발 머신에 npm 기반 LSP CLI를 설치했다.
  - `typescript-language-server`
  - `pyright-langserver`
  - `vue-language-server`
- `backend/config.json`에 TypeScript, Python, Vue language server 경로를 기록했다.
- `aircoded setup`과 `aircoded install`의 초기 설정 흐름에서 language intelligence 기본값을 `typescript,python,vue`로 변경했다.
- LSP를 원하지 않는 배포 환경에서는 `-language-servers none`을 사용하면 건너뛸 수 있다.
- Pyright 검증 명령을 `pyright-langserver --version`에서 `pyright --version`으로 수정했다. 현재 Pyright langserver는 `--version` 단독 실행 시 stdio/socket 인자가 없다는 에러를 내기 때문이다.
- 임시 서버 포트에서 TypeScript completion API smoke를 수행했고, `cloudClient.` 입력에 대해 `connect` completion item이 반환되는 것을 확인했다.
- 검증:
  - `npm i -g typescript typescript-language-server pyright @vue/language-server`
  - `go run ./cmd/aircoded setup -config config.json -agents none -language-servers typescript,python,vue -yes`
  - `go run ./cmd/aircoded doctor -config config.json`
  - `cd backend && env GOCACHE=/private/tmp/aircode-go-build-cache go test ./...`

### 2026-05-28 자연스러운 LSP 자동완성 UX

- 자동완성 popup이 고정 우상단에 뜨던 문제를 수정했다.
- iPad에서는 CodeEditorView 내부 `UITextView`의 실제 caret rect를 읽어 SwiftUI overlay 좌표로 변환하고, popup을 커서 아래 또는 공간이 부족하면 위에 배치한다.
- 후보 품질 개선:
  - iPad 클라이언트에서 현재 prefix 기준으로 completion item을 정렬/필터링한다.
  - backend completion API도 request content와 LSP position에서 prefix를 계산해 raw language-server 후보를 정렬/필터링한다.
- TypeScript language server가 `con` 입력에서도 전역 심볼 raw list를 주는 것을 확인했고, Air Code 레이어에서 `const`, `confirm`, `console`, `continue`, `ConvolverNode`처럼 prefix 중심으로 정리되도록 보강했다.
- 임시 서버 smoke:
  - `cloudClient.` member completion에서 `connect`가 상위 후보에 포함됨.
  - `con` identifier completion에서 prefix 기반 후보가 반환됨.
  - 테스트 후 임시 서버 종료.
- 검증:
  - `cd backend && env GOCACHE=/private/tmp/aircode-go-build-cache go test ./...`
  - `cd ipad && swift test`
  - `cd ipad && xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build -quiet`
  - `cd ipad && ./scripts/simulator_launch_smoke.sh`

### 2026-05-31 Codex Goals 자동 활성화 / 서버 배포 정리

- `aircoded setup` 또는 `aircoded install`에서 Codex가 configured 상태가 되면 `${CODEX_HOME:-~/.codex}/config.toml`에 다음 설정을 자동으로 병합한다.
  - `[features]`
  - `goals = true`
- 기존 `config.toml`에 `[features]`가 있으면 `goals` 값만 `true`로 갱신하고, 다른 Codex 설정은 보존한다.
- `scripts/install_aircoded_server.sh`를 추가했다.
  - backend binary build
  - `aircoded install`
  - agent CLI 연결
  - LSP 설치/설정
  - launchd/systemd user service file 생성 옵션
  - ripgrep dependency check
- root `install.sh`를 추가했다.
  - 로컬 repo에서는 `sh install.sh` 한 줄로 서버 설치를 진행한다.
  - 배포 후에는 `curl -fsSL https://raw.githubusercontent.com/m1ns2o/air-code/main/install.sh | sh` 형태로 fresh server bootstrap이 가능하다.
  - Go, npm, curl, git 같은 bootstrap dependency는 가능한 경우 OS package manager/Homebrew로 먼저 설치한다.
- 실제 서버 배포 runbook을 `docs/SERVER_DEPLOYMENT.md`에 정리했다.
- 검증:
  - `cd backend && env GOCACHE=/private/tmp/aircode-go-build-cache go test ./...`
  - `sh -n install.sh`
  - `bash -n scripts/install_aircoded_server.sh`
  - `AIRCODE_SKIP_BOOTSTRAP_DEPS=1 AIRCODE_SERVICE=0 AIRCODE_YES=0 sh install.sh --dry-run --prefix /tmp/aircode-root-install-test --config backend/config.json --agents none --language-servers none --skip-deps`
  - `./scripts/install_aircoded_server.sh --dry-run --prefix /tmp/aircode-deploy-test --config backend/config.json --agents none --language-servers none --skip-deps`

### 2026-06-01 SwiftTerm 단일 터미널 복구

- Ghostty/libghostty 실험 경로를 제거하고 iPad 터미널을 다시 SwiftTerm 단일 구현으로 정리했다.
  - `RemoteTerminalView`는 SwiftTerm `TerminalView`만 사용한다.
  - 터미널 엔진 선택 메뉴, Ghostty 입력 모드, Ghostty binary target, Ghostty 빌드 스크립트를 제거했다.
- `053de9d Add iPad terminal IME input fallback`에서 사용했던 하단 네이티브 IME 입력바를 복구했다.
  - 한글/CJK 조합 입력은 네이티브 `TextField`에서 완성한 뒤 PTY로 UTF-8 텍스트를 보낸다.
  - LSP 자동 completion은 원래대로 editor cursor snapshot 기준 자동 trigger를 유지한다.
- 유지한 SwiftTerm 보정:
  - `Option` meta key 비활성화
  - 이후 추가했던 `TerminalInputSanitizer`와 marked text 강제 커밋 로직은 제거했다.
  - ESC+digit argument sequence sanitizer
- 검증 예정:
  - `cd ipad && swift test`
  - `cd ipad && xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet`
  - `cd backend && env GOCACHE=/private/tmp/aircode-go-build-cache go test ./...`

### 2026-06-18 Hermes 업데이트 지원

- `aircoded setup` / `aircoded install`에서 Hermes가 installed/configured 상태면 `hermes update --check`로 업데이트 가능 여부를 확인한다.
- interactive setup은 업데이트가 있으면 사용자에게 `Update Hermes now?`를 묻고, `-yes` setup/install은 `hermes update --yes`를 자동 실행한다.
- `-skip-updates` 플래그와 `AIRCODE_SKIP_UPDATES=1` wrapper 환경변수로 업데이트 체크/실행을 모두 건너뛸 수 있다.
- `aircoded doctor`는 기본적으로 read-only로 Hermes 업데이트 가능 여부만 표시하고, `aircoded doctor -update` 또는 `-update -yes`에서만 실제 업데이트를 수행한다.
- Hermes update 출력 파서는 `Update available`, `up to date`, 실패/불명 상태를 정규화한다.
- 검증:
  - `cd backend && env GOCACHE=/private/tmp/aircode-go-build-cache go test ./...`

### 2026-06-18 LSP Code Action / Rename, 파일 동기화, Git UI 보강

- LSP phase 2의 기반을 추가했다.
  - backend가 LSP `WorkspaceEdit`을 안전하게 project root 안에서만 적용한다.
  - `textDocument/codeAction` 결과 중 edit이 포함된 action은 `code-actions/apply`로 적용 가능하다.
  - `textDocument/rename`을 호출하고 반환된 edit을 같은 경로로 적용한다.
  - command-only code action은 아직 headless 안전 적용 경로가 없어 명확한 unsupported 메시지를 반환한다.
- iPad Problems 패널에 Quick Fix 버튼을 추가했다.
  - diagnostic 위치 기준으로 provider quickfix를 요청한다.
  - preferred edit이 있으면 즉시 적용하고 열린 파일/tree/git/problems를 갱신한다.
- iPad editor에 symbol rename 진입점을 추가했다.
  - `Cmd+Shift+R`로 rename dialog를 열고, provider-native rename edit을 적용한다.
- 파일 실시간 동기화를 보강했다.
  - watcher/agent file event가 오면 explorer refresh뿐 아니라 열린 파일도 refresh한다.
  - dirty가 아닌 열린 파일은 서버 최신 내용으로 갱신한다.
  - dirty 파일은 자동 overwrite하지 않고 external-change conflict 상태로 둔다.
- Source Control UI를 보강했다.
  - branch menu에서 `New Branch...`로 새 branch를 만들고 즉시 checkout할 수 있다.
  - commit box에 amend toggle을 추가했다.
  - backend에는 `git checkout -b`와 `git commit --amend` API를 추가했다.
- 검증:
  - `cd backend && env GOCACHE=/private/tmp/aircode-go-build-cache go test ./...`
  - `cd ipad && swift test`
