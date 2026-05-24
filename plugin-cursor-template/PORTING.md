# ARIA Knowledge Cursor Port

This directory is the standalone Cursor port of ARIA Knowledge. Unlike the
Claude (`../plugin/`) and Codex (`../plugin-openai-codex/`) ports, this is a
**repo skeleton**, not a plugin install — users unzip or copy its contents into
the root of their own project, then restart Cursor.

The Claude plugin in `../plugin/` remains the canonical implementation for the
knowledge folder and content schema. The Cursor port may diverge in hook
mechanics, rule packaging, and enforcement strength, but it must not silently
fork the markdown knowledge contract.

## Stable Contract

Keep these compatible with the Claude-standard plugin:

- Knowledge folder layout under `knowledge/` (mirrors `plugin-claude-code/template/`,
  except hoisted to root rather than nested under `template/`)
- Backlog formats under `knowledge/intake/`
- `knowledge/index.md` sections and tag semantics
- Project tier under `knowledge/projects/{tag}/`
- Rule 22 content (`knowledge/rules/change-decision-framework.md`) and
  working-rule numbering (`knowledge/rules/working-rules.md`)

## Cursor Adapter Surface

Cursor-specific files live here:

- `.cursor/hooks.json` — Cursor hook registration
- `.cursor/aria-knowledge.local.md` — config equivalent of `~/.claude/aria-knowledge.local.md`
- `.cursor/rules/*.mdc` — 5 compiled rule files (see mapping table below)
- `AGENTS.md` — Cursor's equivalent of `CLAUDE.md`; loaded as persistent context
- `scripts/aria/*.sh` — hook scripts (Cursor analog of Claude's `plugin-claude-code/bin/`)
- `scripts/aria/VERSION` — port version file (Cursor has no `plugin.json`)

## Current Parity Notes

- The Cursor port is frozen at upstream `2.16.1` as audited 2026-05-18.
- Knowledge folder schema is **fully compatible** with upstream — a Claude Code
  user and a Cursor user can share the same `knowledge/` folder across editors.
- `intake/pre-compact-captures/` was removed by design (Cursor has no
  compaction lifecycle); `intake/task-boundary-captures/` substitutes via the
  `stop` hook.
- `TaskCreated` has no direct Cursor equivalent. Self-trigger instructions in
  `AGENTS.md` substitute when the agent honors them.
- Rule 22 transcript scanning isn't available (no transcript path exposed to
  Cursor hooks). The port uses an edit-intent marker file written by
  `scripts/aria/record-edit-intent.sh` and checked by `pre-edit-check.sh`. This
  is advisory-only — Cursor's `beforeFileEdit` deny semantic is undocumented,
  so the port is fail-open. If Cursor later publishes a stable deny semantic,
  swap `pre-edit-check.sh` to emit `{"permission":"deny", …}` on protected
  paths missing a marker.
- See `audit/ARIA_CURSOR_AUDIT_REPORT.md` §5 for the full enforcement-gap matrix.

## Drift Tracking

Two surfaces drift independently. Update the "last synced" line under each
section when you push a sync commit.

### A. Knowledge contract sync

The canonical source is `plugin-claude-code/template/`. The Cursor port mirrors it at
`cursor-template/knowledge/` (hoisted to root, not nested under `template/`).
The Codex port mirrors it at `plugin-openai-codex/template/` (verbatim).

**Last synced:** `plugin-claude-code/` @ v2.16.1 → `cursor-template/` (2026-05-18, audit
build).

**Files that must stay in lockstep across all three ports:**

| Canonical (`plugin-claude-code/template/`) | Cursor (`cursor-template/`) | Notes |
|---|---|---|
| `template/README.md` | `knowledge/README.md` | User-facing folder intro |
| `template/OVERVIEW.md` | `knowledge/OVERVIEW.md` | Lifecycle + structure overview |
| `template/LOCAL.md` | `knowledge/LOCAL.md` | Local-config explainer |
| `template/aliases.md` | `knowledge/aliases.md` | Tag alias dictionary |
| `template/rules/working-rules.md` | `knowledge/rules/working-rules.md` | The 34 universal rules |
| `template/rules/change-decision-framework.md` | `knowledge/rules/change-decision-framework.md` | Rule 22 framework + worked examples |
| `template/rules/enforcement-mechanisms.md` | `knowledge/rules/enforcement-mechanisms.md` | Enforcement tier model |
| `template/rules/retrospect-patterns.md` | `knowledge/rules/retrospect-patterns.md` | Pattern library — high churn |
| `template/rules/user-rules.md` | `knowledge/rules/user-rules.md` | User-specific rules |
| `template/rules/user-examples.md` | `knowledge/rules/user-examples.md` | Examples of user rules |
| `template/intake/insights-backlog.md` | `knowledge/intake/insights-backlog.md` | Format only — instance content is per-user |
| `template/intake/decisions-backlog.md` | `knowledge/intake/decisions-backlog.md` | Format only |
| `template/intake/extraction-backlog.md` | `knowledge/intake/extraction-backlog.md` | Format only |
| `template/intake/rules-backlog.md` | `knowledge/intake/rules-backlog.md` | Format only |
| `template/intake/ideas/README.md` | `knowledge/intake/ideas/README.md` | Ideas backlog format |
| `template/distill/TASK.schema.md` | `knowledge/distill/TASK.schema.md` | `/distill` contract |
| `template/stitch/STITCH.template.md` | `knowledge/stitch/STITCH.template.md` | `/stitch` contract |

**Sync rule:** any edit to a `plugin-claude-code/template/**` file in the canonical list
above requires the same edit to be applied to the Cursor and Codex copies
before the next release. Validate before tagging.

### B. Skill → `.mdc` compilation (Cursor-only)

Cursor's Rules system loads `.mdc` files from `.cursor/rules/` as persistent
context. There is no equivalent of Claude's `skills/<name>/SKILL.md` folder
shape. The 25 canonical skills (in `plugin-claude-code/skills/`) are compiled into 5 `.mdc`
files. When a canonical `SKILL.md` changes, the matching section in the right
`.mdc` file needs a hand edit.

**Last synced:** `plugin-claude-code/skills/` @ v2.16.1 → `.cursor/rules/` (2026-05-18,
audit build). All 22 canonical skills + 3 aliases present.

**Skill → `.mdc` mapping:**

| Canonical skill (`plugin-claude-code/skills/<name>/SKILL.md`) | Cursor `.mdc` file | Section heading |
|---|---|---|
| `setup` | `aria-commands.mdc` | `#/setup` |
| `help` | `aria-commands.mdc` | `#/help` |
| `extract` | `aria-commands.mdc` | `#/extract` |
| `audit-knowledge` (+ alias `knowledge-audit`) | `aria-audit.mdc` | `#/audit-knowledge` |
| `audit-config` (+ alias `config-audit`) | `aria-audit.mdc` | `#/audit-config` |
| `audit-share` (+ alias `share-audit`) | `aria-commands.mdc` | `#/audit-share` |
| `context` | `aria-context.mdc` | `#/context` |
| `rules` | `aria-context.mdc` | `#/rules` |
| `index` | `aria-commands.mdc` | `#/index` |
| `backlog` | `aria-commands.mdc` | `#/backlog` |
| `stats` | `aria-commands.mdc` | `#/stats` |
| `ask` | `aria-commands.mdc` | `#/ask` |
| `clip` | `aria-commands.mdc` | `#/clip` |
| `intake` | `aria-commands.mdc` | `#/intake` |
| `codemap` | `aria-commands.mdc` | `#/codemap` |
| `distill` | `aria-commands.mdc` | `#/distill` |
| `stitch` | `aria-commands.mdc` | `#/stitch` |
| `handoff` | `aria-commands.mdc` | `#/handoff` |
| `prospect` | `aria-commands.mdc` | `#/prospect` |
| `retrospect` | `aria-commands.mdc` | `#/retrospect` |
| `snapshot` | `aria-commands.mdc` | `#/snapshot` (repurposed — task-boundary capture, not transcript) |
| `wrapup` | `aria-commands.mdc` | `#/wrapup` |
| `clip-thread` (v2.18.0+) | `aria-commands.mdc` | `#/clip-thread` — **pending compilation** (see Pending sync items) |
| `extract-doc` (v2.18.0+) | `aria-commands.mdc` | `#/extract-doc` — **pending compilation** |
| `meeting-notes` (v2.18.0+) | `aria-commands.mdc` | `#/meeting-notes` — **pending compilation** |
| `digest` (v2.18.0+) | `aria-commands.mdc` | `#/digest` — **pending compilation** |
| `sync-decisions` (v2.18.0+) | `aria-commands.mdc` | `#/sync-decisions` — **pending compilation** (WRITE-side; embeds ADR-016 Rule 22 advisory preamble) |
| (Rule 22 framework body, from `plugin-claude-code/template/rules/change-decision-framework.md`) | `aria-rule-22.mdc` | full file, verbatim |
| (ARIA core lifecycle prose) | `aria-core.mdc` | full file |

**Sync rule:** when a canonical `SKILL.md` gains material new behavior (new
flags, new arguments, new output sections), update the matching section in the
mapped `.mdc` file in the same commit, or open a tracked TODO in this file.
Cosmetic edits (typo fixes, prose polish) can batch until the next port refresh.

### Pending sync items

> When you notice canonical drift that hasn't been ported to Cursor yet, add it
> here. Keep entries terse: `- <canonical path> @ <version or date>: <what changed>`.

- `plugin-claude-code/skills/clip-thread/SKILL.md` @ v2.18.0: new MCP-consuming skill (`~~chat` / `~~email` thread capture). **Pending .mdc compilation into `aria-commands.mdc`.** Concept declared in mapping table above; method (Cursor MCP runtime fit) needs validation pass before compilation.
- `plugin-claude-code/skills/extract-doc/SKILL.md` @ v2.18.0: new MCP-consuming skill (`~~docs` page decomposition to intake-backlog). **Pending .mdc compilation into `aria-commands.mdc`.**
- `plugin-claude-code/skills/meeting-notes/SKILL.md` @ v2.18.0: new MCP-consuming skill (transcript folding with paste fallback). **Pending .mdc compilation into `aria-commands.mdc`.** Paste-fallback branch makes this skill the most Cursor-friendly of the 5 — usable without any MCP runtime support.
- `plugin-claude-code/skills/digest/SKILL.md` @ v2.18.0: new MCP-consuming skill (composite-MCP weekly rollup). **Pending .mdc compilation into `aria-commands.mdc`.**
- `plugin-claude-code/skills/sync-decisions/SKILL.md` @ v2.18.0: new **WRITE-side** MCP-consuming skill (mirror decisions to `~~docs` MCP). Embeds ADR-016 Rule 22 advisory preamble. **Pending .mdc compilation into `aria-commands.mdc`.** Highest care item — write-side discipline must port verbatim if compiled.
- `plugin/.mcp.json` + `plugin/CONNECTORS.md` @ v2.18.0: NOT mirrored to `cursor-template/` in v2.18.0-cursor.0. Cursor's MCP runtime support needs validation pass (concept-and-function-preserved-but-method-may-diverge per Mike's D2 framing on the v2.18.0 release). When Cursor MCP integration is verified, copy these files + compile the 5 skills in one paired update.
- _Cursor `2.18.0-cursor.0` VERSION bumped on 2026-05-18 to track the canonical release; SKILL.md compilation deferred per the same pattern as `2.17.0-cursor.0` (which also bumped VERSION without re-syncing `/handoff brief` + `/intake doc` modes from v2.17.0)._

## Release Workflow (independent)

The Cursor port is released as a standalone zip artifact (separate from
`plugin-claude-code/`'s `release.sh`). The audit build at `archive/aria-knowledge-cursor-2.16.1-audited-source.zip`
is the reference for the current shape. Re-stage and re-zip from
`cursor-template/` when cutting a new Cursor port version.
