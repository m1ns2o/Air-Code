# Air Code TUI 기능 대체 진행상황

이 문서는 Codex/Claude/Hermes TUI에서 자주 쓰는 기능을 Air Code iPad UX로 옮기는 진행상황을 한국어로 추적하기 위한 문서다.

## 우선순위

- [x] 1. Context Attachment
  - [x] `@file` 파일 언급
  - [x] `/mention` 파일 첨부
  - [x] `/auto-context` 현재 열린 파일 자동 컨텍스트
  - [x] 서버 safe path resolver를 통한 파일 읽기
- [ ] 2. Permission / Approval UI
  - [x] provider 권한 상태 표시
  - [ ] 위험 작업 승인/거절 플로우
  - [ ] run별 approval 로그
- [ ] 3. MCP / Skills / Hooks 관리
  - [x] Codex / Claude / Hermes 공통 MCP 설치 상태
  - [x] provider별 skills/hooks 상태 확인
  - [ ] reload, doctor, 설정 링크
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

## 진행 메모

- TUI 명령어는 Air Code가 임의로 재구현하지 않고, Codex/Claude/Hermes에 내장 기능이 있으면 provider adapter를 통해 우선 전달한다.
- Air Code native UI는 provider 기능을 대체하는 곳이 아니라 상태 표시, 첨부, diff, revert 같은 remote editor control plane 역할을 맡는다.
- 모든 파일 경로는 서버 project root 기준 relative path만 허용한다.
- 현재 `/auto-context`는 editor cursor/focus/selection이 아니라 선택된 열린 파일의 전체 편집 버퍼를 첨부한다. selection/range 기반 auto context는 아직 미구현이다.

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

### 2026-05-24 MCP / Skills / Hooks Status

- Backend `GET /v1/integrations/status` 추가.
- MCP는 `aircoded mcp install`로 Codex, Claude Code, Hermes에 함께 등록하는 명령을 iPad에 표시.
- Skills/Hooks는 provider-native 관리 영역으로 표시하고, 현재 agent 설치/설정 상태를 함께 노출.
- iPad Chat 상단에 Integrations 카드 추가.
- `/mcp`, `/skills`, `/hooks` slash command는 이후 provider adapter forwarding으로 변경.
- Hermes `/skills ...`는 기존처럼 Hermes native command로 passthrough 유지.
- 남은 작업:
  - provider별 reload/doctor 버튼.
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
- Air Code status 카드들은 slash command 대체물이 아니라 sidecar 관찰 UI로 유지.
- Provider가 지원하지 않는 명령은 full terminal에서 provider TUI를 사용하라는 메시지를 표시.
- 검증:
  - `cd backend && go test ./...`
  - `cd ipad && swift test`
  - `cd ipad && xcodebuild -project AirCode.xcodeproj -scheme AirCode -destination 'generic/platform=iOS Simulator' build -quiet`
