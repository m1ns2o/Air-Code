# Air Code TUI 기능 대체 진행상황

이 문서는 Codex/Claude/Hermes TUI에서 자주 쓰는 기능을 Air Code iPad UX로 옮기는 진행상황을 한국어로 추적하기 위한 문서다.

## 우선순위

- [x] 1. Context Attachment
  - [x] `@file` 파일 언급
  - [x] `/mention` 파일 첨부
  - [x] `/auto-context` selection 우선, 없으면 cursor 주변 자동 컨텍스트
  - [x] 서버 safe path resolver를 통한 파일 읽기
- [ ] 2. Permission / Approval UI
  - [x] provider 권한 상태 표시
  - [x] Chat header의 Run Settings로 권한/응답 스타일/컨텍스트 설정 이동
  - [x] Codex per-run approval/sandbox override
  - [x] Claude Code `--permission-mode` per-run override
  - [x] Hermes native `/yolo` permission override
  - [x] 실행 중 approval 요청을 transcript와 분리된 urgent card로 표시하는 UI 골격
  - [x] provider inline approval event를 실제 approve/deny API로 연결
  - [x] run별 approval timeline 기록
- [ ] 3. MCP / Skills / Hooks 관리
  - [x] Codex / Claude / Hermes 공통 MCP 설치 상태
  - [x] iPad 공통 MCP 추가 UI
  - [x] provider별 skills/hooks 상태 확인
  - [x] Codex apps/connectors, Codex plugins, Claude plugins를 공통 기능처럼 섞지 않고 개별 provider 섹션으로 분리
  - [x] reload, doctor, 설정 링크를 provider-native slash command 어댑터 버튼으로 연결
  - [x] 기존 항목 browse/edit/remove UI
- [x] 4. Agent Runtime Timeline
  - [x] agent started/log/final/changes 이벤트 타임라인
  - [x] 반복 progress 로그 접기
  - [x] run별 상태 추적
- [ ] 5. Conversation Compaction / Context Usage
  - [ ] provider-native context 사용량 어댑터 검증
  - [x] `/compact` provider adapter forwarding
  - [x] provider-native compact passthrough 정리
- [ ] 6. Subagent / Branch / Rewind
  - provider별 지원 가능 여부 표시
  - provider-native branch/rewind adapter 설계
  - subagent 실행 상태 UI

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
