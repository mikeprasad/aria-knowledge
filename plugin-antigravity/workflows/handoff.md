# /handoff — Session Handoff

Generate a passoff package for the next reader.

## Steps

Invoke the aria-knowledge **`handoff`** skill. Two audiences:

- **Default / `auto`** — passoff to future-you in a new session. Synthesizes PROGRESS / CLAUDE / memory updates, commits, runs `/extract`, emits a paste-ready next-session opener.
- **`brief`** — coworker-facing 80–150 word prose brief (Slack/email-ready). No file writes.

Use `/handoff` for default, `/handoff auto`, or `/handoff brief`.
