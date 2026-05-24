# v2.17.0 — Codex & Cursor ports added

**The first multi-port ARIA release.** Two new editor surfaces ship alongside the canonical Claude Code plugin: a Codex port (plugin-shaped) and a Cursor port (repo-skeleton-shaped). The knowledge folder schema is identical across all three — a Claude user, a Codex user, and a Cursor user can share the same `knowledge/` folder.

Two new modes also land on the Claude side: `/handoff brief` for hand-off-to-a-person prose, and `/intake doc` for structured 5-section single-doc capture. Both originated from aria-cowork v0.3.0 design work and were ported here first per the schema-source-of-truth principle.

---

## Claude (canonical) — v2.17.0

**New mode: `/handoff brief`.** Produces a copy/paste coworker brief (warm-but-professional, 80–150 words, capped at 200) instead of the default mode's next-session opener. No side effects — skips PROGRESS.md / CLAUDE.md / memory / commit / `/extract` entirely. The `[coworker]` placeholder is literal so users fill the recipient name at paste time.

**New mode: `/intake doc <url-or-title-or-path>`.** Captures a single doc with a structured body (what the doc claims / worth keeping / contested or unclear / action implied / my reaction) under `intake/docs/{YYYY-MM-DD}-{slug}.md`. New `type: intake-doc` frontmatter; new `intake/docs/` subfolder convention (lazy-created). Three source types: URL (WebFetch), file path (Read), or title-only (user fills body manually).

**Schema changes:** additive only. New `intake-doc` frontmatter type. New `intake/docs/` subfolder (lazy-created — no bootstrap on `/setup`). No breaking changes; existing knowledge folders continue to load without migration.

**Install:** download `aria-knowledge-plugin-2.17.0.zip` from this release. In Claude Code go to **Customize > Add Plugin > Local** and select it. Run `/setup` to configure your knowledge folder.

Full Claude changelog details: see [CHANGELOG.md § 2.17.0](https://github.com/mikeprasad/aria-knowledge/blob/main/CHANGELOG.md).

---

## Codex port — first public release (`2.17.0-codex.0`)

A standalone Codex port ships from [`plugin-openai-codex/`](https://github.com/mikeprasad/aria-knowledge/tree/main/plugin-openai-codex). Independent installable unit with its own `.codex-plugin/plugin.json`, `hooks.json`, and `commands/` entrypoints. Same ARIA knowledge folder schema as the canonical Claude plugin — no fork.

**Hook parity:**
- `SessionStart` cadence + setup prompts (passthrough to existing ARIA scripts)
- `PreToolUse:apply_patch` — Rule 22 impact assessment
- `PostToolUse:apply_patch` — scope-check reminders
- `PreToolUse:Bash` advisory reminders for shell commands that appear to write files
- `PreToolUse:Glob/Grep` — CODEMAP reminders for broad exploration
- `PreCompact` / `PostCompact` passthrough

**Known gaps:**
- Claude `TaskCreated` has no direct Codex equivalent yet.
- Existing skills are copied verbatim from the Claude-standard plugin in this first pass, so some prose still names Claude-specific surfaces.
- `plugin_hooks` is a Codex under-development feature — use this port as a test adapter until the hook surface is fully stable. Enable with `codex features enable plugin_hooks` before testing automatic hooks.

**Install:** download `aria-knowledge-codex-2.17.0.zip` from this release. Install via `.agents/plugins/marketplace.json` or copy the unzipped folder into a Codex local marketplace.

**Config:** Codex hooks read `~/.codex/aria-knowledge.local.md` first, then fall back to `~/.claude/aria-knowledge.local.md` — so existing ARIA Claude users can keep their existing config.

See [`plugin-openai-codex/README.md`](https://github.com/mikeprasad/aria-knowledge/blob/main/plugin-openai-codex/README.md) and [`plugin-openai-codex/PORTING.md`](https://github.com/mikeprasad/aria-knowledge/blob/main/plugin-openai-codex/PORTING.md) for the full parity matrix.

---

## Cursor port — first public release (`2.17.0-cursor.0`)

A standalone Cursor port ships from [`plugin-cursor-template/`](https://github.com/mikeprasad/aria-knowledge/tree/main/plugin-cursor-template). **Distribution shape differs from Claude and Codex:** the Cursor port is a *repo skeleton*, not a plugin install. Users unzip its contents into the root of their own project and restart Cursor.

**What's inside:**
- `.cursor/hooks.json` + `.cursor/aria-knowledge.local.md` (Cursor-native config)
- `.cursor/rules/*.mdc` — 5 compiled rule files. The 25 canonical skills are *compiled* into 5 `.mdc` files because Cursor's Rules system doesn't have a one-skill-per-folder concept.
- `AGENTS.md` — Cursor's equivalent of `CLAUDE.md`
- `knowledge/` — knowledge folder at repo root (Cursor port hoists this from Claude's nested `template/knowledge/` shape)
- `scripts/aria/*.sh` — hook scripts (Cursor's analog of Claude's `plugin/bin/`)
- `QUICKSTART.md` — Cursor-adapted quickstart

**Knowledge folder schema is fully compatible** with the Claude and Codex ports — share the same `knowledge/` across editors.

**Enforcement caveats (Cursor has no transcript access; some Claude enforcement weakens):**
- **Rule 22 is advisory-only.** Cursor's `beforeFileEdit` deny semantic is undocumented, so the port is fail-open. The port uses an edit-intent marker file (`scripts/aria/record-edit-intent.sh`) as the closest available mechanism — `beforeFileEdit` checks file+session+age and escalates warning wording on missing/stale/mismatched markers, but does not block.
- **No `PreCompact` / `PostCompact`** — Cursor has no compaction lifecycle. Replaced with task-boundary capture via the `stop` hook (`scripts/aria/capture-task-boundary.sh`) — writes a structural snapshot (git + status + diff + active batch + recent hook log), not a transcript.
- **`TaskCreated` has no Cursor equivalent.** Self-trigger instruction in `AGENTS.md` substitutes: tokenize task text, match `## Tag Index`, load files. Compliance is instruction-bound.

**Install:** download `aria-knowledge-cursor-2.17.0.zip` from this release, unzip it, and copy the contents into the root of your project. Restart Cursor.

See [`plugin-cursor-template/QUICKSTART.md`](https://github.com/mikeprasad/aria-knowledge/blob/main/plugin-cursor-template/QUICKSTART.md) for setup details and [`plugin-cursor-template/PORTING.md`](https://github.com/mikeprasad/aria-knowledge/blob/main/plugin-cursor-template/PORTING.md) for the full parity + skill→`.mdc` mapping + residual enforcement-gap matrix.

---

## Sharing a knowledge folder across editors

The Claude / Codex / Cursor ports all read and write the same knowledge folder schema. If you work across editors:

- Point each editor's `knowledge_folder` config at the same absolute path
- Knowledge files are plain markdown — git-versionable, Obsidian-compatible
- Backlogs (`intake/*.md`) are shared; `/audit-knowledge` from any editor sees the same pending items
- Audit logs (`logs/knowledge-audit-log.md`, `logs/config-audit-log.md`) are shared — cadence checks honor the most recent run regardless of which editor ran it

---

## Version scheme

| Port | Internal version | Zip artifact |
|---|---|---|
| Claude (canonical) | `2.17.0` | `aria-knowledge-plugin-2.17.0.zip` |
| Codex | `2.17.0-codex.0` | `aria-knowledge-codex-2.17.0.zip` |
| Cursor | `2.17.0-cursor.0` | `aria-knowledge-cursor-2.17.0.zip` |

Canonical version tracks the Claude port. Sibling ports use semver prerelease suffixes (`-codex.N`, `-cursor.N`) so they can bump independently between canonical releases without colliding with the canonical line.

---

## Upgrade notes

- **From v2.16.x:** drop-in replacement on the Claude side. New `intake/docs/` subfolder is lazy-created on first `/intake doc` use — no migration needed.
- **First time on Codex or Cursor:** see the per-port install instructions above. Existing ARIA users can point Codex at their existing `~/.claude/aria-knowledge.local.md` (Codex falls back to it automatically).
