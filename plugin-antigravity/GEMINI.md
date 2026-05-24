# ARIA Knowledge — Antigravity Session Discipline

You have access to aria-knowledge, a persistent human-governed knowledge plugin. ARIA's five-phase lifecycle (capture → govern → promote → apply → refresh) is active. This file is the session-lifecycle equivalent of Claude Code's SessionStart hook — it loads once per session and tells you what to do at session boundaries that Antigravity's per-turn hooks cannot.

## At the start of every session

1. **Check audit cadence.** Read `~/.gemini/antigravity/aria-knowledge.local.md`. If `audit_cadence_knowledge` days have passed since the last `/audit-knowledge` (per the log at `{knowledge_folder}/logs/knowledge-audit-log.md`), surface the prompt: *"Knowledge audit is due — want me to run /audit-knowledge?"*
2. **Surface relevant knowledge.** If `active_knowledge_surfacing: true` and the user's first prompt contains project tags or topic keywords, suggest `/context <tags>` to load relevant knowledge files before answering.
3. **Check for stale batch manifest.** If `~/.gemini/antigravity/active-batch.json` exists and its `expires_at` is in the past, delete it silently.

Do these checks at most once per session, in your first response to the user.

## Rule 22 — Change Decision Framework (advisory text)

Every Edit/Write/Bash you propose triggers `pre-edit-aria.sh` / `bash-cd-aria.sh` hooks that scan for `[Rule 22]` markers and emit Antigravity's deny semantic if the change is high-impact without justification. To stay ahead of the hook:

- **Before any Edit/Write**, emit a `[Rule 22] Low Impact — <reason>` or `[Rule 22] High Impact — <reason>` marker that completes the 7-step framework (identify change → intake → criteria → solutions → rank → decide → execute).
- **After any Edit/Write**, the `post-edit-aria.sh` hook logs a scope check to `~/.gemini/antigravity/aria-knowledge-scope-check.log`. Read your own log periodically to catch scope drift.

Full framework: `~/Projects/knowledge/rules/change-decision-framework.md` (or wherever knowledge_folder points). 34 working rules: `~/Projects/knowledge/rules/working-rules.md`.

## MCP category placeholders

ARIA skills use `~~category` placeholders (e.g. `~~chat`, `~~docs`, `~~project tracker`). At install, run `cowork-plugin-customizer` to replace these with your team's connectors, or leave as-is and let skills probe at runtime per ADR-015 (capability-probe pattern).

## Snapshot before context loss

Antigravity has persistent sessions but long sessions still eventually exceed context. Before context becomes critical:

- `/snapshot` — archives current transcript via `transcriptPath` from any hook's stdin payload
- `/wrapup` — closes the session cleanly
- `/handoff` — produces a passoff brief for the next session

The session-ledger pattern (canonical PostCompact behavior) re-emerges via these manual skills — Antigravity has no PostCompact event.

## Knowledge folder

Knowledge lives at the `knowledge_folder` path in your config (`~/.gemini/antigravity/aria-knowledge.local.md`). Standard structure: `intake/`, `approaches/`, `decisions/`, `references/`, `rules/`, `projects/`, `logs/`. The folder is port-agnostic — same content works across Claude Code, Codex, Cursor, and Antigravity installs.

## Commands

`/setup` first. Then `/help` for the full command reference.
