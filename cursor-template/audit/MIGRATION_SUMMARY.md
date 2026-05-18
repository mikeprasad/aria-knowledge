# ARIA Cursor Port — Audit & Fix Summary (2026-05-18)

## Upstream sync
Upstream HEAD `965d69a` is at version **2.16.1** — same as the port's basis. Only commit on top of 2.16.1 is `965d69a docs: add QUICKSTART.md`. No feature/code porting required; the documentation addition was forward-ported as a Cursor-adapted QUICKSTART.

## Fixes applied to `/home/user/workspace/aria-knowledge`

1. **Added Cursor frontmatter to all 5 `.cursor/rules/*.mdc` files** (`description`, `globs`, `alwaysApply`). Cursor's project-rules spec requires this YAML block; the port shipped without it. `aria-core.mdc` and `aria-rule-22.mdc` use `alwaysApply: true`; the others scope their globs.
2. **Added missing skills to `.cursor/rules/aria-commands.mdc`**: `/help` (full reference table) and `/audit-share` (full step-by-step with Cursor config paths). Documented aliases `/knowledge-audit`, `/config-audit`, `/share-audit` in the relevant rule preambles.
3. **Synced `AGENTS.md`** command table from 15 to 22 canonical commands + 3 aliases (added `/help`, `/audit-share`, `/distill`, `/stitch`, `/prospect`, `/retrospect`, `/handoff`). All 25 upstream skills now reachable.
4. **Added Cursor-adapted `QUICKSTART.md`** at the port root, mirroring upstream's new doc with a "what's different from Claude Code" section, the edit-intent marker workflow, and Cursor Cloud agent caveats.

## Validation
- `python3 -m json.tool .cursor/hooks.json` → OK
- YAML frontmatter on all 5 `.mdc` files → OK (all 3 fields present, parsed cleanly)
- `.cursor/aria-knowledge.local.md` → OK (`knowledge_folder`, cadences, `last_setup_version: 2.16.1`)
- `bash -n` on all 13 scripts → OK
- Hook payload smoke tests (sessionStart, beforeFileEdit ±marker, afterFileEdit, beforeShellExecution, beforeReadFile, stop) → all hooks fire, all emitted JSON valid; marker write→verify→consume cycle confirmed end-to-end (intent marker consumed only on matching successful edit)
- `grep -E 'transcript_path|tool_use_id|PreCompact|PostCompact|pre-compact-captures|save-transcript|CLAUDE_PLUGIN_ROOT|~/.claude' scripts/aria/*.sh` → only legacy-doc comments, zero active dependencies
- Protected-file matching now hits `AGENTS.md|working-rules.md|change-decision-framework.md|enforcement-mechanisms.md|hooks.json` (no stale `CLAUDE.md|plugin.json`)

## Files changed
| File | Change |
|---|---|
| `.cursor/rules/aria-rule-22.mdc` | + frontmatter |
| `.cursor/rules/aria-core.mdc` | + frontmatter |
| `.cursor/rules/aria-context.mdc` | + frontmatter + alias note |
| `.cursor/rules/aria-audit.mdc` | + frontmatter + alias notes (`/knowledge-audit`, `/config-audit`) |
| `.cursor/rules/aria-commands.mdc` | + frontmatter + `/share-audit` alias note + `/help` SKILL + `/audit-share` SKILL |
| `AGENTS.md` | command table expanded from 15 to 22 commands + 3 aliases |
| `QUICKSTART.md` | **NEW** — Cursor-adapted from upstream `965d69a` |

No scripts modified. No knowledge folder schema changes. Knowledge folder remains fully compatible with upstream — Claude Code and Cursor repos can share the same folder.

## Tests run
- JSON parse + YAML frontmatter validation on all manifests/rules
- bash -n on every script
- End-to-end hook smoke run with synthetic Cursor payloads — JSON output validation on every non-empty response, marker lifecycle verified, `knowledge/intake/task-boundary-captures/` write verified
- Protected-file branch exercised on `AGENTS.md` edit without marker → escalated-wording advisory emitted as expected

## Remaining gaps (Cursor-level, not port bugs)
1. **No structural Rule 22 deny** — Cursor's `beforeFileEdit` hook spec doesn't document a stable agent-side deny. The port stays fail-open with escalated wording on protected files; if Cursor adds a deny semantic later, the protected-file branch can flip to fail-closed.
2. **No `TaskCreated` event** — context surfacing fires on `stop` (task end), with a self-trigger instruction in `AGENTS.md` for task start.
3. **No transcript access** — Rule 22 enforcement is via edit-intent markers, not transcript inspection. Discipline is instruction-bound rather than structurally verified.
4. **`sessionStart` / `stop` don't fire in Cursor Cloud agents** — for cloud, the `.cursor/rules/*.mdc` instructions carry the workflow (knowledge-folder reads/writes still work).

All four are Cursor-platform limitations documented in `ARIA_CURSOR_AUDIT_REPORT.md` §5 with concrete proposed-future-fixes if Cursor adds the capability.

## Artifacts written
- `/home/user/workspace/ARIA_CURSOR_AUDIT_REPORT.md` — full audit report (parity matrix, fixes, enforcement gaps, file change log)
- `/home/user/workspace/ARIA_CURSOR_FILE_TREE.txt` — file tree (53 entries)
- `/tmp/claude_code_output.md` — this summary

## Zip regeneration
**Recommended.** Existing `aria-knowledge-cursor-2.16.1-shippable.zip` and `aria-knowledge-cursor-2.16.1-source.zip` in `/home/user/workspace/` predate the frontmatter + skill fixes. Main agent can re-run the `_aria_zip_stage` packaging flow on the updated tree to capture the audit fixes.
