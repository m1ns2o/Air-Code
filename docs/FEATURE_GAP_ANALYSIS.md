# Air Code Feature And Gap Analysis

Last updated: 2026-05-28

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
- Provider runtime status API with transcript counts, saved session metadata, CLI version, and raw safe provider status when available.
- Agent runner abstraction for Codex, Claude Code, OpenCode, and Hermes.
- Inline approval decision API for active agent runs.
- Project permission snapshot API for configured approval mode, sandbox mode, risk level, and terminal command policy.
- Integration status API for MCP, Skills, and Hooks, including the shared cross-provider MCP install command.
- Codex model, reasoning effort, Plan mode, Goal mode, session resume, and Fast mode support.
- Codex app-server approval requests are normalized into Air Code pending approval events and answered through the app-server JSON-RPC response path.
- Claude Code basic model, plan mode, generated session id, and session resume flags.
- Hermes CLI boundary with provider/model/resume argument insertion.
- Hermes runtime approvals can be steered through native `/approve` and `/deny` commands.
- Hermes native session import: Air Code can list `hermes sessions list`, import a selected session through `hermes sessions export`, persist the transcript locally, and continue it with `--resume`.
- Agent run logs under `.aircode/runs/`.
- Agent run checkpoints under `.aircode/checkpoints/`, with run-level changes and run-level revert.
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
- Sidecar Permissions card for provider approval/sandbox policy and project terminal command policy.
- Sidecar Integrations card for MCP, Skills, and Hooks status across Codex, Claude Code, and Hermes.
- Integration inventory and management sheet for browsing MCP, Skills, Hooks, Apps, Plugins, and provider marketplaces, with MCP edit/reinstall and supported remove actions.
- Provider command adapter that forwards supported Codex/Claude/Hermes built-in slash commands instead of reimplementing them as Air Code native actions.
- Slash command autocomplete and an adapter-first parser: provider built-ins are forwarded when supported, while Air Code-only editor controls stay local.
- Context Attachment for agent runs: `@file` mention autocomplete, `/mention <path>`, `/auto-context`, selection-first context, and cursor-nearby context injection. Full-file context remains explicit through `@file` or `/mention`.
- Pending approval urgent card calls the backend approval decision API for Codex app-server and Hermes-supported runs.
- Run Settings includes a Usage section for provider version, saved session id, transcript size, raw provider status, and notes.
- Review runs started with `/review`, `/security-review`, or `/code-review` can render parsed Review Findings with severity, file, line, and diff navigation.
- Chat header has provider-native Branch/Rewind/Subagent runtime action entrypoints for Codex, Claude Code, and Hermes.
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

- Provider-native IDE selection ranges are covered by Air Code's own context injection path: selection is sent first and cursor-nearby context is used when no selection exists. This is not the Codex extension protocol, but it covers the core iPad editing workflow.
- Cloud delegation (`/cloud`, `/cloud-environment`, `/local`) is not implemented. Air Code runs on the user's own server instead of Codex Cloud.
- Cloud task follow-up/apply-local flow is not implemented.
- Codex IDE review commands are forwarded through the provider adapter when supported, and Air Code now has a best-effort Review Findings panel. Base-branch selection and provider-native review metadata are still not fully modeled.
- Thread status with rate limits/context usage is partially implemented through the provider status API and Run Settings Usage section. Provider-native token/rate fields are only shown when a safe headless command exposes them.
- Goals are forwarded through provider-native `/goal`. Air Code does not keep a separate `.aircode/goals.json` goal store or `/goals` command.

### Codex CLI/TUI

- Full interactive TUI parity is not implemented: raw scrollback, copy latest output, rich tool-call inspection, and prompt-history search are missing or partial. Air Code now has a native run timeline, runtime steering, and inline approval for Codex app-server/Hermes paths, but it is not yet a full provider TUI replacement.
- `/permissions` is forwarded through the provider adapter when supported; the Air Code permissions card is sidecar status. Inline approve/reject is implemented for Codex app-server approval requests and Hermes `/approve`/`/deny` steering, while Claude remains unsupported until a safe headless decision transport is available.
- `/keymap`, `/vim`, `/theme`, `/statusline`, `/title`, and other TUI personalization commands are not implemented as native Air Code settings, except Air Code has its own theme picker.
- `/mcp`, `/skills`, and `/hooks` are forwarded through the provider adapter when supported. Air Code also has a sidecar integration status card, provider-native shortcut buttons for doctor/config/reload commands, and an inventory sheet for browse/edit/remove where the provider exposes a safe CLI or local user-owned path.
- `/mention` now attaches project files through Air Code context injection, but provider-native terminal mention behavior is not replicated exactly.
- `/agent`, `/side`, `/fork`, branch, rewind, thread, queue, and rollback entrypoints are exposed in the Chat header as provider-native runtime actions. They are still command-forwarding entrypoints rather than rich Air Code-native panels.
- `/approve` for auto-review denial retry is not implemented.
- `/ps` and `/stop` are available through provider-native command forwarding or Air Code run controls, but background terminal/job management is not implemented as a rich Air Code UI.
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
- `/resume`, `/continue`, `/branch`, `/fork`, `/rename`, `/rewind`, and aliases are forwarded where supported. Air Code's own session UI still stores one active native session id per provider, imports Hermes/Codex/Claude native histories, and segments them by project tag. It does not implement a separate fallback session engine. Rich provider-native branch/rename/rewind panels are still not implemented.
- `/btw`, `/checkpoint`, `/undo`, `/copy`, `/theme`, `/statusline`, and other CLI commands are forwarded where supported, but their interactive TUI screens are not represented as native iPad panels.
- `/context`, `/compact`, `/status`, `/usage`, and `/cost` are forwarded through the provider adapter when supported. Air Code also has a provider status API and Usage section, but rich parsed provider token/rate/window UI depends on provider-safe headless output and is still limited.
- `/doctor` can be launched from the integration shortcuts when the selected provider supports it, but Air Code does not parse its output into a dedicated diagnostic panel yet.
- `/feedback` is not implemented.
- `/theme`, `/tui`, `/statusline`, `/scroll-speed`, `/terminal-setup`, `/voice`, and similar terminal UX commands are not relevant or not native in Air Code.

### Claude Code Extension Layer

- CLAUDE.md/rules authoring and discovery UI is not implemented.
- Skills management is partially implemented. Air Code can browse local user-owned skill folders and remove them safely, but provider marketplace browsing/install/edit flows still rely on provider CLI/TUI commands.
- Subagent management (`/agents`) is exposed as a provider-native runtime action/command, but Air Code does not yet render provider subagents as first-class native objects.
- Agent teams are not implemented.
- Full MCP browser/editor UI is partially implemented. Air Code now has `aircoded mcp install`, an iPad MCP add/edit sheet, provider MCP inventory, and provider-native remove actions. Deep provider-specific OAuth/login/test flows still rely on the provider CLI/TUI.
- Hooks management is partially implemented for local user-owned hook paths, but provider-native hook schema editing is not implemented.
- Plugins/marketplaces are partially implemented as inventory. The Integrations card separates Codex apps/connectors, Codex plugin marketplaces, Claude plugin manager, and Hermes bundled plugins because they are not shared concepts; provider-managed cache/bundled entries are read-only.
- Code intelligence/LSP integration is not implemented yet.
- Background agents (`/background`, `/tasks`, `/stop`) are exposed through provider-native command forwarding where supported, but Air Code does not yet render a native background-agent/task dashboard.
- `/batch` worktree decomposition is not implemented.
- `/autofix-pr`, `/schedule`/routines, `/teleport`, `/remote-control`, `/web-setup`, `/ultraplan`, and `/ultrareview` are not implemented.
- Bedrock/Vertex setup wizards are not implemented.
- PR inline comments from Claude review are not implemented.

## Product-Specific Gaps Still Worth Building

- LSP/code intelligence abstraction for later SwiftUI editor integration.
- Rich provider-native usage parsing for Codex/Claude when safe headless `/usage`, `/cost`, or `/context` transport becomes available.
- First-class native panels for provider subagents, task queues, branch/rewind history, and background jobs if providers expose stable machine-readable state.
