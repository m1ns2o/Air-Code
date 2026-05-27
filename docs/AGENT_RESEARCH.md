# Agent Research Notes

Last updated: 2026-05-24

## Codex Plan, Reasoning, And Goals

- Verified sandbox logs show plan mode and Ultrathink are applied at the CLI boundary:
  - `run.started` records `mode=plan` and `reasoningEffort=xhigh`.
  - `process.start` includes `model_reasoning_effort="xhigh"`.
  - Session resume uses `codex exec resume <sessionId>`.
- Plan mode now uses the native `/plan` slash command for new runs.
- Local `/goal` smoke test confirmed Codex CLI recognizes the command and returns current goal status.
- Official Codex docs describe `/goal` as experimental and available when `features.goals` is enabled.
- Official use-case guidance frames goals as durable objectives for long-running work with a verifiable stopping condition.
- Official Claude Code docs also list `/goal [condition|clear]`; Air Code therefore forwards `/goal` to both Codex and Claude Code instead of keeping a separate Air Code goal store.

## Hermes Agent Fit

- Hermes Agent is an open-source Nous Research CLI for coding, research, and development tasks.
- It has a noninteractive path that fits Air Code's backend runner:
  - `hermes chat -q "prompt"` for one-shot chat with tool output.
  - `hermes -z "prompt"` for final-answer-only programmatic output.
  - `--resume <session>`, `--continue`, `--provider`, and `--model` for session/model control.
- Strong integration candidates:
  - Add `hermes` as another backend `AgentProvider`.
  - Store Hermes session IDs alongside Codex sessions in `.aircode/sessions.json`.
  - Map Air Code model/provider menus to Hermes `--provider` and `--model`.
  - Surface Hermes skills/memory later as a separate "Memory/Skills" section, not in the core composer.
- Current local status:
  - Hermes is installed at `/Users/m1ns2o128/.local/bin/hermes`.
  - `aircoded setup -agents hermes -yes` enables Hermes in `backend/config.json`, records the absolute command path, and enables Hermes `model.openai_runtime=codex_app_server` for OpenAI Codex runs.
  - `hermes doctor` passes the CLI/dependency checks, but reports non-Codex provider setup still needs attention.
  - Hermes v0.14.0 currently fails on the direct `openai-codex` responses runtime with `Error: 'NoneType' object is not iterable`; the `codex_app_server` runtime works for OpenAI Codex smoke tests.
- Implemented v1 integration path:
  - `aircoded setup` can record Hermes install/configure state.
  - `GET /v1/agents/capabilities` exposes Hermes only as selectable when installed and configured.
  - The backend runner renders `--provider`, `--model`, and `--resume` before the prompt when Hermes runs provide those options.
  - Hermes session resume is enabled in capability metadata. The runner parses `session_id:` and `hermes --resume <id>` output and stores the ID under `.aircode/sessions.json`.
  - The setup/capability resolver checks `PATH`, `~/.local/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`, because the official installer can add `hermes` to shell startup files that are not loaded by the running server process.

## Hermes Sessions And Messaging Gateway

- Official Hermes docs describe sessions as shared storage across CLI and messaging platforms such as Telegram, Discord, Slack, WhatsApp, Signal, Matrix, and Teams.
- CLI resume paths:
  - `hermes --continue` or `hermes -c` resumes the most recent CLI session.
  - `hermes --resume <session>` or `hermes -r <session>` resumes a specific session by ID or title.
  - `hermes sessions list` can be used to find session IDs.
- Messaging platform path:
  - `hermes gateway setup` configures Telegram/Discord/Slack style bots.
  - `hermes gateway` starts the always-on gateway.
  - Gateway conversations are stored as Hermes sessions with full message history, so a session can theoretically be continued from another surface if the target session ID/title is known and Hermes exposes it through `hermes sessions`.
- Air Code current support:
  - Air Code can continue a Hermes session when the CLI prints a parsable ID.
  - Air Code can list Hermes-native sessions through `hermes sessions list` and import a selected session through `hermes sessions export --session-id <id> -`.
  - Imported Hermes sessions are stored in the project `.aircode/sessions.json` and `.aircode/conversations/hermes.json`, so the next Hermes prompt can continue with `--resume <id>`.
  - Air Code does not yet start or supervise `hermes gateway`, manage Discord tokens, or map a Discord channel/thread to an Air Code project. Those remain Hermes CLI responsibilities.

## Useful Features To Add Next

- Provider-native goal status: use `/goal`, `/goal pause`, `/goal resume`, and `/goal clear` through the selected provider instead of storing a separate Air Code goal record.
- Goal template composer: objective, constraints, validation command, stop condition.
- Background run queue: show long-running goal/agent runs independently from chat scroll.
- Checkpoint summaries: compact "what changed / what passed / what remains" messages for long runs.
- `/ps` integration: inspect background terminals from the iPad client.
- `/diff`, `/review`, and `/permissions` shortcuts as explicit header actions instead of raw slash text.
- Agent capability registry from the server so the iPad UI only shows installed/configured agents.

## Sources

- Codex CLI slash commands: https://developers.openai.com/codex/cli/slash-commands
- Codex Follow a goal use case: https://developers.openai.com/codex/use-cases/follow-goals
- Hermes Agent GitHub: https://github.com/NousResearch/hermes-agent
- Hermes CLI commands: https://hermes-agent.nousresearch.com/docs/reference/cli-commands/
- Hermes sessions: https://hermes-agent.nousresearch.com/docs/user-guide/sessions/
- Hermes CLI guide: https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/cli.md
- Hugging Face Hermes Agent integration: https://huggingface.co/docs/inference-providers/main/integrations/hermes-agent
