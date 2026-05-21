# Agent Research Notes

Last updated: 2026-05-22

## Codex Plan, Reasoning, And Goals

- Verified sandbox logs show plan mode and Ultrathink are applied at the CLI boundary:
  - `run.started` records `mode=plan` and `reasoningEffort=xhigh`.
  - `process.start` includes `model_reasoning_effort="xhigh"`.
  - Session resume uses `codex exec resume <sessionId>`.
- Local `/goal` smoke test confirmed Codex CLI recognizes the command and returns current goal status.
- Official Codex docs describe `/goal` as experimental and available when `features.goals` is enabled.
- Official use-case guidance frames goals as durable objectives for long-running work with a verifiable stopping condition.

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
- Current blocker: `hermes` is not installed on this machine, so Air Code should not expose Hermes in the iPad selector until server config confirms the command exists.

## Useful Features To Add Next

- Active goal banner: show current goal objective, running/paused status, and quick `pause/resume/clear`.
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
- Hugging Face Hermes Agent integration: https://huggingface.co/docs/inference-providers/main/integrations/hermes-agent
