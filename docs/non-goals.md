# Non-goals

What aria-knowledge does NOT aim to do. Helps prospective users self-select before installing, and explains decisions about features we have considered and declined.

## Permanently out of scope

- **Replacing version control.** Knowledge files supplement git history; they don't replace `git log` or `git blame` as authoritative sources.
- **Replacing IDE features.** `/codemap` is exploration scaffolding for AI sessions, not a symbol indexer or LSP. It cannot answer "where is this function defined" — that's what your editor does.
- **Single-user productivity tooling.** Every artifact aria-knowledge produces — knowledge files, codemaps, audit reports — is designed to be shareable via repo commits. If your goal is private notes that never leave your machine, a personal note app fits better.
- **Replacing decision-making.** The change decision framework (Rule 22) is a discipline, not a workflow engine. aria-knowledge surfaces the framework; it does not drive your decisions for you.
- **Cross-session state in the cloud.** No external service, no API keys required. State lives in plain text in your knowledge folder and your repos. If you want syncing, use git.

## Deferred (not "no," just "not now")

- **GUI configuration.** `~/.claude/aria-knowledge.local.md` stays text-only. Revisit if Claude Code's plugin UI matures and there's a clean integration point.
- **Automated knowledge promotion.** Promotion from personal → shared remains user-reviewed via `/audit-share`. Auto-promotion would require trust signals we don't currently model.
- **Multi-user workflow primitives.** No assignment, no review queues, no notifications. The plugin is single-user-with-sharing; multi-user collaboration belongs in Linear / GitHub / equivalents.
- **Usage meter on the Claude Code desktop app.** The `/statusline` meter is a terminal-only feature — the desktop app renders its own native usage indicator and does not invoke a `statusLine` command, so the meter (and the usage snapshot it writes) only updates in CLI sessions. An OpenTelemetry-based bridge is technically viable: the desktop app honors a `settings.json` `env` block and, with `CLAUDE_CODE_ENABLE_TELEMETRY` + `OTEL_METRICS_EXPORTER=otlp` + `OTEL_EXPORTER_OTLP_PROTOCOL=http/json`, emits OTLP/JSON metrics (carrying `session.id` and `account_uuid`) to a local endpoint, which a small receiver could parse into the usage snapshot. Deferred because the receiver must be a long-running local daemon holding an open port — a footprint the plugin's fire-and-forget hook model deliberately avoids. Note also that OpenTelemetry emits token/cost counters, **not** context-window percentage or 5h/7d rolling plan-usage directly (those would have to be derived or sourced elsewhere). Revisit if a daemon-free receive path appears, or if the desktop app exposes context/usage to a hook payload or a `statusLine`-equivalent surface.

## Adjacent plugins

If your fit is different, see also:

- **[aria-ex1](https://github.com/nrek/aria-ex1)** — leaner execution-first variant focused on per-repo `CODEMAP.md`, cross-repo `STITCH.md`, complexity-tiered `/distill` task specs, and edit-time change discipline. Drops the knowledge lifecycle (audits, intake, snapshot, extract, share). Choose this if you want execution-first scaffolding without the personal-knowledge-management surface.

See [`related-repo-delta-ledger.md`](related-repo-delta-ledger.md) for tracked cross-pollination between aria-knowledge and adjacent plugins.
