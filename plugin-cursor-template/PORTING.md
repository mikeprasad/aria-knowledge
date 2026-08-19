# ARIA Knowledge Cursor Port

This directory is the standalone Cursor port of ARIA Knowledge. Unlike the
Claude (`../plugin-claude-code/`) and Codex (`../plugin-openai-codex/`) ports, this is a
**repo skeleton**, not a plugin install — users unzip or copy its contents into
the root of their own project, then restart Cursor.

The Claude plugin in `../plugin-claude-code/` remains the canonical implementation for the
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
- `scripts/port-skills-to-mdc.py` — maintainer script; **full-regenerates** `aria-commands.mdc`, `aria-audit.mdc`, `aria-context.mdc`, and `aria-rule-22.mdc` from canonical sources (preserves Cursor-native `/snapshot` body and Cursor-specific audit Step 2d + Rule 22 hook sections)

## Current Parity Notes

- **Canonical parity target:** `plugin-claude-code/` @ **v2.46.2** (2026-08-16).
- **Cursor port version:** `scripts/aria/VERSION` → `2.46.2-cursor.0`.
- **ADR-094 Runtime Gates:** intentionally **omitted** in Cursor — aria-cowork is not loaded in typical Cursor sessions; namespace note lives in `aria-commands.mdc` preamble only.
- Knowledge folder schema is **fully compatible** with upstream (Rules 36–38 + Behavioral Foundation included).
- `intake/pre-compact-captures/` removed by design; `intake/task-boundary-captures/` substitutes via the `stop` hook.
- Rule 22 transcript scanning isn't available; edit-intent marker + advisory `beforeFileEdit` (see `audit/ARIA_CURSOR_AUDIT_REPORT.md` §5). Canonical deny-rate circuit breaker **not ported**.
- MCP skills (`/intake thread`, `/intake extract`, `/meeting-notes`, `/digest`, `/sync-decisions`) are compiled into `aria-commands.mdc`; connect servers via **Cursor Settings → MCP**. Connector reference: `../plugin-claude-cowork/CONNECTORS.md`. Retired `/clip`, `/clip-thread`, `/extract-doc` are folded into `/intake`.
- **New in 2.46.2-cursor.0 (from 2.36.0):** `/auto`, `/roadmap`, `/preflight`, `/audit` dispatcher, `/audit style`, `/audit usage`; `planning_paths`; preflight commit gate (v2.46.1 ERE — `git` + option tokens + whole-word `commit`); external-fetch gate (off by default); in-place bash-write warn; post-edit tautology warn (Rule 36); `session_state_tracked` + `git ls-files --error-unmatch` (v2.46.2 — `check-ignore` is the wrong test on a tracked file); SESSION.md `## Pending handoffs` ledger.

### Intentional Cursor non-ports

- `/statusline`, `/aria-assist`, `auto-runloop.sh`, `pre-cron-check.sh` (no CronCreate / no CLI statusline)
- Rule 22 transcript deny / circuit breaker (advisory + edit-intent remains)
- PreCompact / PostCompact / UserPromptSubmit usage inject
- Bundled `.mcp.json`
- `/auto self-restart` is a no-op; D1 asks rather than inferring usage; D2 is instruction-only (Cursor `/loop` analog)

### Cursor hook parity (v2.46.2)

| Canonical (Claude Code) | Cursor equivalent | Status |
|---|---|---|
| `SessionStart` | `sessionStart` | ≈ ported |
| `PreToolUse: Edit\|Write` | `beforeFileEdit` + edit-intent marker | ⚠ advisory (no transcript deny) |
| `PostToolUse: Edit\|Write` | `afterFileEdit` | ≈ ported (+ SESSION.md in-progress) |
| `PostToolUse: Write` (auto-prospect) | `afterFileEdit` → `post-plan-prospect-check.sh` | ≈ ported |
| `PostToolUse: Edit` (tautology warn) | `afterFileEdit` → `post-edit-tautology-check.sh` | ≈ ported (reads file from disk; Cursor payload often lacks the edit body) |
| `PostToolUse: Bash` (auto-retrospect) | `afterShellExecution` → `post-push-retrospect-check.sh` | ≈ ported |
| `PreToolUse: Bash` (cd surfacing) | `beforeShellExecution` | ≈ ported |
| `PreToolUse: Bash` (in-place write warn) | `beforeShellExecution` → `pre-bash-write-check.sh` | ≈ warn-only |
| `PreToolUse: Bash` (preflight commit gate) | `beforeShellExecution` → `pre-commit-preflight-check.sh` | ≈ **can deny** (`permission: deny`) |
| `PreToolUse: WebFetch\|WebSearch` | `preToolUse` + `beforeMCPExecution` → `pre-external-fetch-check.sh` | ≈ **can deny**; ships `off` |
| `PreToolUse: Glob\|Grep` | `beforeReadFile` | ≈ (broader trigger) |
| `TaskCreated` | `stop` → `task-context-check.sh` | ⚠ fires at task end, not start |
| `SubagentStart` (self-report) | `subagentStart` | ⚠ weaker — parent agentMessage only |
| `SubagentStop` (archive) | `subagentStop` | ≈ ported (transcript path unverified) |
| `PreCompact` / `PostCompact` | not wired | ✗ no transcript in hook payload (use `stop` capture) |
| `UserPromptSubmit` (usage alert) | not wired | ✗ requires Claude Code `/statusline` snapshot |
| `/statusline` skill | not ported | ✗ Claude Code CLI status line only |
| Rule 22 transcript deny | not available | ✗ instruction + edit-intent marker only |

## Drift Tracking

### A. Knowledge contract sync

**Last synced:** `plugin-claude-code/template/` @ v2.46.2. Re-audit template rule files before each release. Cursor keeps `knowledge/approaches/foundational-review-chain.md` and `intake/task-boundary-captures/` (canonical has `intake/pre-compact-captures/`).

### B. Skill → `.mdc` compilation (Cursor-only)

**Last synced:** `plugin-claude-code/skills/` @ **v2.46.2** → `.cursor/rules/*.mdc`. Adds `/auto`, `/roadmap`, `/preflight`, `/audit` + style/usage; `/interview` guided default and wrapup/handoff `session_state_tracked` ride in with canonical bodies.

**Compiled commands** in `aria-commands.mdc` (core + MCP + `/help` + `/audit-share`; aliases documented in preamble / `aria-audit.mdc`). Audit family lives in `aria-audit.mdc`.

| Canonical skill | Cursor `.mdc` | Section |
|---|---|---|
| `setup` … `wrapup` (incl. auto, roadmap, preflight, interview, recap, foundational-review, readiness-audit) | `aria-commands.mdc` | `#/…` |
| `meeting-notes`, `digest`, `sync-decisions` (+ `/intake` MCP modes) | `aria-commands.mdc` | `#/…` |
| `audit`, `audit-knowledge`, `audit-config`, `audit-style`, `audit-usage` (+ aliases) | `aria-audit.mdc` | `#/…` |
| `context`, `rules` | `aria-context.mdc` | `#/…` |
| Rule 22 framework | `aria-rule-22.mdc` | full file |
| Core lifecycle | `aria-core.mdc` | full file (hand-authored; not regenerated) |

**Re-sync workflow:**

```bash
python3 plugin-cursor-template/scripts/port-skills-to-mdc.py
# Then manually review diffs — script strips Runtime Gates and adapts paths; spot-check wrapup/handoff/help.
```

### Pending / intentional divergences

- No `.mcp.json` bundled — users configure MCP in Cursor Settings (unlike Cowork's bundled manifest).
- Enforcement weaker than Claude Code (advisory Rule 22, no PreCompact transcript).
- `aria-commands.mdc` is large (~5k lines) — future: split MCP skills into `.cursor/skills/` if Cursor skill loading matures.

## Release Workflow

```bash
./release-cursor.sh   # from repo root; reads scripts/aria/VERSION
```
