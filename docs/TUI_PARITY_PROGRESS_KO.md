# Air Code TUI 기능 대체 진행상황

이 문서는 Codex/Claude/Hermes TUI에서 자주 쓰는 기능을 Air Code iPad UX로 옮기는 진행상황을 한국어로 추적하기 위한 문서다.

## 우선순위

- [x] 1. Context Attachment
  - [x] `@file` 파일 언급
  - [x] `/mention` 파일 첨부
  - [x] `/auto-context` 현재 열린 파일 자동 컨텍스트
  - [x] 서버 safe path resolver를 통한 파일 읽기
- [ ] 2. Permission / Approval UI
  - provider 권한 상태 표시
  - 위험 작업 승인/거절 플로우
  - run별 approval 로그
- [ ] 3. MCP / Skills / Hooks 관리
  - Codex / Claude / Hermes 공통 MCP 설치 상태
  - provider별 skills/hooks 상태 확인
  - reload, doctor, 설정 링크
- [ ] 4. Agent Runtime Timeline
  - tool call, command, diff, warning 이벤트 타임라인
  - 긴 로그 접기
  - run별 상태 추적
- [ ] 5. Conversation Compaction / Context Usage
  - context 사용량 표시
  - `/compact` Air Code native 처리
  - provider-native compact passthrough 정리
- [ ] 6. Subagent / Branch / Rewind
  - provider별 지원 가능 여부 표시
  - Air Code native branch/rewind UX 설계
  - subagent 실행 상태 UI

## 이번 배치

- [x] Context Attachment 구현
- [x] backend agent context 렌더링 테스트
- [x] iPad mention parser 테스트
- [x] `docs/IMPLEMENTATION_CHECKLIST.md` 완료 체크 갱신
- [x] git commit

## 진행 메모

- TUI 명령어를 1:1 텍스트 메뉴로 복사하기보다, iPad에서 자연스러운 패널/칩/토글 UI로 옮기는 방향을 기본으로 한다.
- Provider native 기능이 CLI 내부 상태에만 존재하는 경우에는 먼저 Air Code native metadata로 대체하고, 이후 provider API/CLI가 안정적인 부분부터 연결한다.
- 모든 파일 경로는 서버 project root 기준 relative path만 허용한다.

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
