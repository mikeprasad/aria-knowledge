# Release validation

Pre-release checklist for aria-knowledge maintainers. Run this before tagging a release to catch regressions that the hook test suite (`tests/run.sh`) doesn't surface — drifted skill prose, renamed commands, broken `/setup` flows on existing config.

## Workspace

Use a placeholder multi-repo workspace (e.g. `~/release-validation/`) with at least:

- One backend-style repo (`./your-backend-repo/`)
- One frontend-style repo (`./your-frontend-repo/`)
- A knowledge folder at any path

If the release changes config schema, run validation against both a fresh `~/.claude/aria-knowledge.local.md` and a copy of the previous version's config (backwards-compat check).

## Phase 1 — Setup

- [ ] `/setup` writes `~/.claude/aria-knowledge.local.md` with current schema and current `last_setup_version`.
- [ ] Re-running `/setup` on existing config is non-destructive (preserves user values; updates only documented fields).
- [ ] If the release introduces new config fields, `/setup` prompts for them; if it removes fields, no error on the obsolete keys.

## Phase 2 — Exploration

- [ ] `/codemap create` in the backend repo produces a stack-appropriate file.
- [ ] `/codemap create` in the frontend repo produces a stack-appropriate file (different sections than backend).
- [ ] `/stitch create <group>` produces a stitch file at the configured `stitch_path` with auth flow + endpoint table sections populated.

## Phase 3 — Capture

- [ ] `/extract` writes new files to the configured knowledge folder with correct frontmatter.
- [ ] `/clip` saves a URL or text snippet to intake.
- [ ] `/snapshot` saves the current transcript to intake.
- [ ] `/intake` bulk-imports from a directory.

## Phase 4 — Audit

- [ ] `/audit-knowledge` surfaces extractable knowledge from memory and plans.
- [ ] `/audit-config` flags drift in CLAUDE.md and config files.
- [ ] `/audit-share` walks personal knowledge folders and recommends shared destinations correctly per `projects_groups[tag]` (single-repo and multi-repo project groups both work).

## Phase 5 — Lookup

- [ ] `/rules <number>` and `/rules <keyword>` both resolve.
- [ ] `/context <topic>` returns matching files.
- [ ] `/help` lists current commands accurately (no renamed commands missing).
- [ ] `/stats` reports current knowledge base health.

## Phase 6 — Hooks

- [ ] `tests/run.sh` passes on all fixtures.
- [ ] PreToolUse Edit on a fresh transcript denies on missing `[Rule 22]` marker; recovery message names the expected format.
- [ ] PostToolUse outputs `[Rule 22 · Scope]` markers in PASS / CONDITIONAL / FAIL / OK shapes as appropriate.
- [ ] PreCompact captures transcript; PostCompact prompts for review.
- [ ] SessionStart audit cadence checks fire on schedule.

## Phase 7 — Distill

- [ ] `/distill` micro tier produces objective + scope + DoD only.
- [ ] `/distill` standard tier adds dependencies and QA.
- [ ] `/distill` full tier adds frontend / backend / database sections only when work touches those layers.
- [ ] `/distill --group=<group>` loads CODEMAPs as cited context.

## Phase 8 — Release artifacts

- [ ] `release.sh` runs cleanly with no errors.
- [ ] Generated zip contains `plugin-claude-code/.claude-plugin/plugin.json` exactly once.
- [ ] Generated zip excludes `.DS_Store`, `__MACOSX`, `.claude/settings*`.
- [ ] `marketplace.json` synced to `plugin.json` version (auto-sync confirmed by `release.sh` log).
- [ ] CHANGELOG entry exists for the new version with date, narrative, sections, and upgrade notes.

## After validation

The two-commit release pattern:

1. Commit source changes (one commit on `main`).
2. Run `release.sh` (auto-syncs `marketplace.json`, builds zip, verifies).
3. Commit release artifacts (second commit — synced `marketplace.json` + new zip).
4. Push to GitHub.
5. Verify the GitHub repo browser reflects the new version (CHANGELOG, plugin.json, marketplace.json all in sync).
