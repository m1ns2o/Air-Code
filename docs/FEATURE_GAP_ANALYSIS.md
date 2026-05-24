# Air Code Feature And Gap Analysis

Last updated: 2026-05-24

Reference docs checked:

- Codex IDE features: https://developers.openai.com/codex/ide/features
- Codex IDE slash commands: https://developers.openai.com/codex/ide/slash-commands
- Codex CLI features: https://developers.openai.com/codex/cli/features
- Codex CLI slash commands: https://developers.openai.com/codex/cli/slash-commands
- Claude Code commands: https://code.claude.com/docs/en/commands
- Claude Code extension model: https://code.claude.com/docs/en/features-overview
- Claude Code fast mode: https://code.claude.com/docs/en/fast-mode

## Implemented In Air Code

### Backend

- Go `aircoded` server with `serve`, `setup`, `doctor`, and `install` commands.
- Bearer-token auth and health check.
- Config-driven workspace roots and projects.
- VS Code-style remote folder open flow: list workspace roots, browse a root, create folder, open selected folder as a project.
- Safe relative-path file access with traversal and symlink escape checks.
- Lazy file tree, file read, file save/create, SHA-256 file version, stale `baseVersion` conflict.
- Git status, file diff, and file revert. `.aircode` metadata is hidden from git status.
- Server-stored recent projects with re-open, remove, and pin APIs.
- Ripgrep-backed project search API with a safe Go fallback.
- WebSocket event hub for project/agent/git/file-style events.
- Agent capability API for installed/configured agents.
- Agent runner abstraction for Codex, Claude Code, OpenCode, and Hermes.
- Project permission snapshot API for configured approval mode, sandbox mode, risk level, and terminal command policy.
- Integration status API for MCP, Skills, and Hooks, including the shared cross-provider MCP install command.
- Codex model, reasoning effort, Plan mode, Goal mode, session resume, and Fast mode support.
- Claude Code basic model, plan mode, generated session id, and session resume flags.
- Hermes CLI boundary with provider/model/resume argument insertion.
- Hermes native session import: Air Code can list `hermes sessions list`, import a selected session through `hermes sessions export`, persist the transcript locally, and continue it with `--resume`.
- Agent run logs under `.aircode/runs/`.
- Agent run checkpoints under `.aircode/checkpoints/`, with run-level changes and run-level revert.
- Active Goal state under `.aircode/goals.json` with active-goal API support.
- Air Code conversation/session persistence under `.aircode/conversations/` and `.aircode/sessions.json`.
- Full PTY terminal using `github.com/creack/pty`.
- Binary terminal WebSocket protocol for input, output, resize, close, exit, and error frames.
- Terminal session limits, detach cleanup, idle cleanup, and auth checks.
- Command runner remains available for quick commands, but terminal UI uses PTY.
- Setup/install recipes for Codex, Claude Code, OpenCode, and Hermes.

### iPad App

- SwiftUI app shell with Sublime-style folder-first layout.
- Left folder explorer, center tabbed editor, right chat panel, bottom terminal panel.
- Resizable folder/chat sidebars.
- Server connection defaults, saved connection settings, and Keychain token storage.
- Remote folder picker with create-folder flow.
- Native code editor based on `CodeEditorView`, with `Runestone` still only a fallback candidate.
- Material theme mapping, Go syntax configuration, line numbers, dirty state, save, and side-by-side conflict resolution.
- Parsed side-by-side diff view with line numbers, context folding, large-diff row limiting, and file revert.
- Open Recent startup view with pinned projects and Revert Run action in Changes cards.
- Explorer/Search toggle in the left sidebar, plus `/search <query>` as a native slash command.
- Cursor/Codex-like Agent Chat panel with transcript stack, transient streaming text, final answer rendering, changed-file summary, and collapsed large changes.
- Runtime timeline card for started/progress/session/final/finished agent events, with repeated progress coalescing.
- Agent selector driven by backend capabilities.
- Model selector for Codex, Claude, and Hermes provider/model pairs.
- Plan and Goal are forwarded as provider-native slash commands with Air Code run metadata. `/model`, `/diff`, Codex `/fast`, Claude `/effort`, provider session commands, review commands, aliases, and Hermes session/gateway commands prefer provider-native adapter forwarding; Ultrathink, Caveman, and Air Code `/speed` remain run-option wrappers.
- Active Goal card with run status, resume, and clear actions.
- Sidecar Permissions card for provider approval/sandbox policy and project terminal command policy.
- Sidecar Integrations card for MCP, Skills, and Hooks status across Codex, Claude Code, and Hermes.
- Provider command adapter that forwards supported Codex/Claude/Hermes built-in slash commands instead of reimplementing them as Air Code native actions.
- Slash command autocomplete and an adapter-first parser: provider built-ins are forwarded when supported, while Air Code-only editor controls stay local.
- Context Attachment for agent runs: `@file` mention autocomplete, `/mention <path>`, `/auto-context`, and selected open-file context injection. `/auto-context` sends the selected opened file buffer, not cursor-focused selection/range data yet.
- Prompt history navigation with Up/Down.
- SwiftTerm-based full terminal view with reconnect, clear, close, input, resize, and binary stream support.
- iPad-only app target, app icon, local network usage description, distribution notes, and export options sample.

## Intentionally Simplified

- Speed mode now has only `Default` and `Fast`.
- `Default` means Air Code sends no speed override. It does not auto-tune speed.
- Codex Fast is supported by sending `features.fast_mode=true` and `service_tier="fast"`.
- Claude Code Fast is not forced because it requires Claude Code 2.1.36+, Opus 4.6/4.7, usage credits, and account/org enablement. The local CLI checked during development was `2.0.25`.
- OpenCode remains lower priority and can fall back to terminal/TUI usage.

## Major Gaps Versus Codex

### Codex IDE Extension

- Provider-native IDE selection ranges are only partially covered. Air Code now supports file mentions and selected open-file context, but exact editor selection/range injection is still a future enhancement.
- Cloud delegation (`/cloud`, `/cloud-environment`, `/local`) is not implemented. Air Code runs on the user's own server instead of Codex Cloud.
- Cloud task follow-up/apply-local flow is not implemented.
- Codex IDE review commands are now forwarded through the provider adapter when supported. Air Code still lacks a review-specific parsed UI for base-branch comparison and provider review findings.
- Thread status with rate limits/context usage is not fully implemented.
- Goals are supported for starting a `/goal` run, and Air Code now has its own active-goal dashboard/state endpoint. Provider-native Codex Cloud goal orchestration remains out of scope.

### Codex CLI/TUI

- Full interactive TUI parity is not implemented: inline step approval/rejection, raw scrollback, copy latest output, queued prompt while a run is active, and prompt-history search are missing or partial. Air Code now has a native run timeline, but it is not yet a full provider tool-call inspector.
- `/permissions` is forwarded through the provider adapter when supported; the Air Code permissions card is sidecar status only. Inline approve/reject during a running agent step is not implemented yet.
- `/keymap`, `/vim`, `/theme`, `/statusline`, `/title`, and other TUI personalization commands are not implemented as native Air Code settings, except Air Code has its own theme picker.
- `/mcp`, `/skills`, and `/hooks` are forwarded through the provider adapter when supported. Air Code also has a sidecar integration status card, but provider-native editing/reload UIs for hooks, plugins, apps, and skills are still missing.
- `/mention` now attaches project files through Air Code context injection, but provider-native terminal mention behavior is not replicated exactly.
- `/agent`, `/side`, `/fork`, and subagent thread switching are forwarded where supported, but are not implemented as rich Air Code UI concepts.
- `/approve` for auto-review denial retry is not implemented.
- `/ps` and `/stop` are forwarded to Codex where supported, but background terminal/job management is not implemented as a rich Air Code UI.
- `/compact` is forwarded through the provider adapter when supported rather than implemented as an Air Code transcript compactor.
- `/init` is forwarded through the provider adapter when supported. Air Code does not provide a separate AGENTS.md authoring UI.
- Codex subagents are not exposed as first-class Air Code workers.
- Codex image inputs and image generation are not implemented.
- Codex remote TUI/app-server mode is not used; Air Code has its own server protocol instead.
- Shell completions are not relevant to the iPad app.

## Major Gaps Versus Claude Code

### Claude Code Commands And Session Features

- Full command parity is missing. Air Code exposes some slash suggestions, but most Claude built-ins are not native UI actions.
- `/add-dir` and related workspace commands are forwarded where supported. Air Code still uses one opened project folder plus configured workspace roots.
- `/clear` is forwarded through the provider adapter when supported. Air Code's own new-session behavior remains available through `/new`.
- `/resume`, `/continue`, `/branch`, `/fork`, `/rename`, `/rewind`, and aliases are forwarded where supported. Air Code's own session UI still stores one active session per provider; Hermes now has native session import, while Codex/Claude do not yet expose a full provider-native session picker in Air Code.
- `/btw`, `/checkpoint`, `/undo`, `/copy`, `/theme`, `/statusline`, and other CLI commands are forwarded where supported, but their interactive TUI screens are not represented as native iPad panels.
- `/context`, `/compact`, `/status`, `/usage`, and `/cost` are forwarded through the provider adapter when supported. Rich parsed context-window and plan/rate usage UI is not implemented yet.
- `/doctor` is available on the server CLI, not integrated as a client-side diagnostic panel.
- `/feedback` is not implemented.
- `/theme`, `/tui`, `/statusline`, `/scroll-speed`, `/terminal-setup`, `/voice`, and similar terminal UX commands are not relevant or not native in Air Code.

### Claude Code Extension Layer

- CLAUDE.md/rules authoring and discovery UI is not implemented.
- Skills management is not implemented. Air Code can list slash hints, but cannot browse, hide, invoke, edit, or install Claude skills.
- Subagent management (`/agents`) is not implemented.
- Agent teams are not implemented.
- Full MCP browser/editor UI is not implemented. Air Code now has `aircoded mcp install` for registering one MCP server with Codex, Claude Code, and Hermes together, plus an iPad status card.
- Hooks management is limited to status/guidance; editing provider-native hooks is not implemented.
- Plugins/marketplaces are not implemented.
- Code intelligence/LSP integration is not implemented yet.
- Background agents (`/background`, `/tasks`, `/stop`) are not implemented.
- `/batch` worktree decomposition is not implemented.
- `/autofix-pr`, `/schedule`/routines, `/teleport`, `/remote-control`, `/web-setup`, `/ultraplan`, and `/ultrareview` are not implemented.
- Bedrock/Vertex setup wizards are not implemented.
- PR inline comments from Claude review are not implemented.

## Product-Specific Gaps Still Worth Building

- LSP/code intelligence abstraction for later SwiftUI editor integration.
- Provider capability version checks, especially for Claude Fast and newer Claude `/verify` support.
