# PORTING.md — Antigravity Port of aria-knowledge

This file tracks divergence between `plugin/` (canonical Claude Code port) and `plugin-antigravity/` (this port), per the same convention as `cursor-template/PORTING.md` and `plugin-openai-codex/`.

---

## Port overview

| Dimension | Canonical (Claude Code) | Antigravity port |
|---|---|---|
| Plugin manifest path | `.claude-plugin/plugin.json` | **`plugin.json` (flat, at plugin root)** |
| Manifest schema | Rich metadata (name, version, description, hooks block, keywords, author, license) | **Marker only: `{"name": "aria-knowledge"}`** |
| Hook config path | Inline `hooks` block in `plugin.json` | **Separate `hooks.json` at plugin root** |
| Hook JSON shape | `{"hooks": {"PreToolUse": [...]}}` | **`{"named-hook-id": {"PreToolUse": [...]}}`** — named entries at top level |
| Hook events supported | SessionStart, PreToolUse, PostToolUse, PreCompact, PostCompact, TaskCreated, Stop, Notification, etc. | **PreToolUse, PostToolUse, PreInvocation, PostInvocation, Stop** (only) |
| Hook I/O contract | Env vars (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_TRANSCRIPT_PATH`, etc.) | **stdin JSON in, stdout JSON out**; no env vars; context fields are `workspacePaths`, `transcriptPath`, `artifactDirectoryPath`, `toolCall.{name,args}`, `stepIdx` |
| Hook tool matchers | Claude Code tool names (`Edit`, `Write`, `Glob`, `Grep`, `Bash`) | **Antigravity tool names** (`write_to_file`, `replace_file_content`, `multi_replace_file_content`, `grep_search`, `find_by_name`, `run_command`) |
| Hook deny semantic | Fail-open on hook error; deny is advisory | **Documented + fail-closed**: `{"decision":"allow"|"deny"|"ask"|"force_ask"}` |
| MCP config path | `.mcp.json` at plugin root | **`mcp_config.json`** at plugin root |
| MCP HTTP URL key | `"url"` | **`"serverUrl"`** |
| MCP OAuth shape | `oauth.clientId` + `oauth.callbackPort` | **`oauth.clientId` + `oauth.clientSecret`** (or UI flow for DCR servers; redirect URI `https://antigravity.google/oauth-callback`) |
| MCP ADC support | n/a | **`authProviderType: "google_credentials"`** |
| Config file path | `~/.claude/aria-knowledge.local.md` | **`~/.gemini/antigravity/aria-knowledge.local.md`** |
| Global plugin install | `~/.claude/plugins/` | **`~/.gemini/config/plugins/`** |
| Workspace plugin install | n/a | **`.agents/plugins/` or `_agents/plugins/`** |
| Workspace skills path | n/a (Claude Code uses plugin-bundled skills) | **`.agents/skills/<folder>/SKILL.md`** (workspace) or plugin-bundled `skills/` |
| Global rules path | n/a (CLAUDE.md files) | **`~/.gemini/GEMINI.md`** (global) or `.agents/rules/*.md` (workspace) |
| Install command | `/plugin install` (or copy to `~/.claude/plugins/`) | **`/plugin marketplace add <github>`** + **`/plugin install <plugin-name>`** |
| jq dependency | not required | **required** (for stdin-JSON parsing in wrappers) |
| Hook timeout default | not documented | **30 seconds per docs/hooks** (`aria-knowledge` initially shipped 5s on all hooks → bumped to 30 in v2.20) |
| Plugin version field | In `.claude-plugin/plugin.json` `"version"` key | **`version.txt` sidecar at plugin root** (Antigravity's `plugin.json` schema is marker-only per docs/plugins; no documented version field) |
| Skill frontmatter fields | `description`, `argument-hint`, `allowed-tools`, `model`, `disable-model-invocation` | **`name` (optional) + `description` (required) only** per docs/skills; `allowed-tools` and `argument-hint` stripped in v2.20 |
| Slash-command invocation | Skills invoked via `/skill-name` natively | **Description-activated only** (agent picks skill by description-match); for true slash-command parity, ship Workflows at `.agents/workflows/` (v2.21 optional) |
| Subagent dispatch | Agent tool (programmatic) | **`invoke_subagent` / `define_subagent` tools** per docs/hooks |

---

## Architecture: Why the wrapper layer

ARIA's canonical bash hook scripts in `plugin/bin/` use Claude Code conventions: `${CLAUDE_PLUGIN_ROOT}`, `CLAUDE_TOOL_NAME`, `CLAUDE_TARGET_FILE`, etc. Antigravity exposes none of these — context comes in as stdin JSON.

Two architectural choices were available:

1. **Rewrite the canonical scripts** to parse stdin JSON natively. Adds Antigravity-specific code paths to the canonical, breaks single-source-of-truth across ports.
2. **Insert a thin wrapper layer** that reads stdin JSON, sets the env vars the canonical scripts expect, and execs them. Canonical scripts stay unchanged.

The port chose **(2)**. The wrappers live at `bin/antigravity/`; the canonical scripts at `bin/`. The shared lib `lib-antigravity-input.sh` handles the JSON-to-env translation. This means a canonical script bug fix in `plugin/bin/` automatically propagates to Antigravity at next `build.sh` run.

---

## Registered hooks (this port)

| Hook entry | Event | Matcher | Wrapper |
|---|---|---|---|
| `aria-pre-edit` | PreToolUse | `write_to_file\|replace_file_content\|multi_replace_file_content` | `bin/antigravity/pre-edit-aria.sh` |
| `aria-pre-explore` | PreToolUse | `grep_search\|find_by_name` | `bin/antigravity/pre-explore-aria.sh` |
| `aria-bash-cd` | PreToolUse | `run_command` | `bin/antigravity/bash-cd-aria.sh` |
| `aria-post-edit` | PostToolUse | `write_to_file\|replace_file_content\|multi_replace_file_content` | `bin/antigravity/post-edit-aria.sh` |
| `aria-pre-invocation` | PreInvocation | (n/a — fires every model call) | `bin/antigravity/pre-invocation-aria.sh` |

The `aria-pre-invocation` hook restores three behavioral parities the initial port lost:

1. **Session-start automation** — On `invocationNum == 0` (first call of session), injects an ephemeralMessage with audit-cadence + stale-batch-cleanup + knowledge-surfacing prompts. Restores Claude Code's SessionStart hook automatic behavior.
2. **PostToolUse → agent feedback channel** — Drains pending entries from `~/.gemini/antigravity/aria-knowledge-scope-check.log` (written by `post-edit-aria.sh`) and injects them as ephemeralMessage. Antigravity's PostToolUse protocol returns `{}` with no agent-visible reasoning; this PreInvocation drain pattern delivers Rule 22 scope-check feedback to the agent at a one-turn lag.
3. **transcriptPath caching** — Writes `transcriptPath` to `~/.gemini/antigravity/.last-transcript-path` on every call. Skills (which aren't hooks and can't read hook stdin) read this cache to know the current conversation transcript — required by `/snapshot`, `/audit-knowledge`, and `/extract`.

---

## Retired hooks

| Hook | Canonical script | Reason retired |
|---|---|---|
| `SessionStart` | `session-start-check.sh` | Not a per-turn event; Antigravity has no SessionStart event. Behavior moved to `GEMINI.md` (loaded once per session by Antigravity). |
| `PreCompact` | `pre-compact-check.sh` | Not a per-turn event; Antigravity has no PreCompact event. Behavior moved to `/snapshot` skill (manual; reads `transcriptPath` from any hook stdin). |
| `PostCompact` | `post-compact-check.sh` | Same reason as PreCompact. Session-ledger re-emission moved to `GEMINI.md` text. |
| `TaskCreated` | `task-context-check.sh` | Not a per-turn event; Antigravity has no TaskCreated equivalent. Knowledge-file surfacing moved into skills that dispatch subagents (`/distill`, `/codemap`). |

The canonical scripts are **not copied** to `plugin-antigravity/bin/` by `build.sh` (PreCompact + PostCompact case in the `for` loop). They remain in canonical `plugin/bin/` for Claude Code use.

---

## MCP-consuming skills (v2.18.0+)

All 5 ship at full strength in this port:

| Skill | `~~category` | Read/Write | Status |
|---|---|---|---|
| `/clip-thread` | `~~chat` OR `~~email` | Read | Full |
| `/extract-doc` | `~~docs` | Read | Full |
| `/meeting-notes` | `~~docs` (paste fallback) | Read | Full |
| `/sync-decisions` | `~~docs` | **Write** | Full — ADR-016 Rule 22 advisory preamble preserved verbatim |
| `/digest` | All 4 categories | Read | Full composite rollup |

---

## Pending sync items

_(none as of v2.19.2 — initial Antigravity port)_

When canonical drifts, add one line per item: `[date] [skill or file]: [description of drift]`.

---

## Known drift

_(none as of v2.20 — Phase D port-aware rewrites complete.)_

Three skills carry port-specific overlays at `overlays/skills/<name>/SKILL.md` that replace the canonical-derived bodies after `build.sh` runs:

- `skills/snapshot/SKILL.md` — reads cached `transcriptPath` instead of grep-walking `~/.claude/projects/`
- `skills/audit-knowledge/SKILL.md` — scans cached transcript + artifact-directory paths instead of Claude Code's memory + plans dirs
- `skills/audit-config/SKILL.md` — audits Antigravity surfaces (hooks.json, mcp_config.json, GEMINI.md, .agents/rules/, ARIA local config) instead of Claude Code's `.claude/settings.local.json`

Drift between canonical and overlay is detected via `diff plugin/skills/<name>/SKILL.md plugin-antigravity/overlays/skills/<name>/SKILL.md`. When canonical evolves, the overlay needs a corresponding hand-update.

---

## v2.20 closure summary

Initial port (v2.19.2) shipped 18 plan tasks across the manifest, hook layer, MCP config, GEMINI.md, 30 skills, knowledge folder template, build script, probe-hook, and docs. The v2.20 arc closed every documented Known Drift item plus surfaced 5 schema-level findings from a primary-source verification pass against `~/Projects/knowledge/intake/clippings/Google Antigravity Documentation{,1-4}.md`.

### v2.20 commits

| Commit | Phase | Change |
|---|---|---|
| `8acc86a` | A1 | Strip `allowed-tools` + `argument-hint` from all 30 SKILL.md frontmatter (Antigravity schema recognizes only `name` + `description`) |
| `1dac96b` | A2 | Bump hook timeouts 5s → 30s (Antigravity default per docs/hooks) |
| `14e03e5` | A3 | Substitute `.claude/settings.local.json` → `hooks.json` in `template/rules/change-decision-framework.md` |
| `92d04d4` | B | Add `aria-pre-invocation` hook restoring 3 behavioral parities: session-start automation (on `invocationNum == 0`), Rule 22 scope-check feedback injection (drain log → ephemeralMessage), and `transcriptPath` caching |
| `0ddc045` | C | Add `version.txt` sidecar (Antigravity plugin.json has no version field); patch `/setup` to read it |
| `cafe2bc` | D | Port-specific overlays for `/snapshot`, `/audit-knowledge`, `/audit-config` (overlay pattern at `overlays/skills/<name>/SKILL.md`); save-transcript.sh heredoc replacement; artifactDirectoryPath caching added to pre-invocation hook |

### v2.21 follow-up candidates (not parity-blocking)

- **Workflows surface** — ship `.agents/workflows/<command>.md` for the ~10 most-used user-invoked commands (`/setup`, `/handoff`, `/wrapup`, `/extract`, `/context`, `/snapshot`, `/audit-knowledge`, `/audit-config`, `/help`, `/stats`) to enable true slash-command invocation. Skills' description-activation works for now but requires the agent to recognize intent rather than the user typing the command directly.
- **Plugin-bundled rules** — per docs/plugins, plugins can ship a `rules/` subdirectory. ARIA's `template/rules/working-rules.md` could ALSO live at `plugin-antigravity/rules/working-rules.md` for Antigravity's "Always On" rule-activation mode. Optional convenience.
- **Probe-hook empirical closure** — OQ-1/2/3 (env var availability, CWD assumption, jq path) still gated on a real Antigravity install. First-session probe at `~/aria-antigravity-probe.log` resolves all three on first use; smoke test in `SMOKE-TEST.md`.

---

## Version history

| Port version | Canonical synced from | Date | Notes |
|---|---|---|---|
| 2.19.2 | `plugin/` @ v2.19.2 | 2026-05-24 | Initial Antigravity port. Prior draft (`plugin-antigravity.archive-2026-05-24-draft/`) was built on incorrect contract assumptions; this is the verified rebuild. |
| 2.20.0 | `plugin/` @ v2.19.2 | 2026-05-24 | Primary-source verification pass closed all Known Drift items + restored 3 behavioral parities via new PreInvocation hook + introduced overlay pattern for 3 misfitting skills + version.txt sidecar. 6 commits 8acc86a..cafe2bc. |
