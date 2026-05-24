# PORTING.md — Antigravity Port of aria-knowledge

This file tracks divergence between `plugin/` (canonical Claude Code port) and `plugin-antigravity/` (this port), per the same convention as `cursor-template/PORTING.md` and `plugin-codex/`.

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

## Known drift (v2.19.2 → v2.20 follow-ups)

Semantic Claude-Code-specific references in canonical content that survived path substitution and need port-aware redesign in a follow-up pass. Substitutions can't fix these because they encode Claude Code's filesystem layout assumptions, not just config paths.

| File | Lines | Drift |
|---|---|---|
| `skills/setup/SKILL.md` | 13, 16, 303 | Reads installed version from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` — but Antigravity's `plugin.json` is at the flat root and contains only `{"name":"aria-knowledge"}` (no version field per Antigravity's documented manifest schema). The /setup skill needs a port-specific version source (e.g., a sibling `version.txt`, or read from `PORTING.md`'s version table). |
| `skills/audit-config/SKILL.md` | 9, 17, 47, 60 | Audit logic targets `.claude/settings.local.json` and `.claude/*.local.md` — Claude-Code-specific configuration surfaces. Antigravity has different surfaces (`hooks.json`, `mcp_config.json`, `~/.gemini/GEMINI.md`, `.agents/rules/`). Skill needs port-specific audit logic, possibly a separate `audit-config-antigravity` variant. |

Resolution path: a v2.20 "port-audit pass" that grep-walks every skill/template file for Claude-Code-specific surfaces and either (a) genericizes them, (b) adds port-aware conditional logic, or (c) creates port-specific skill variants where the surface delta is too large for genericization.

---

## Version history

| Port version | Canonical synced from | Date | Notes |
|---|---|---|---|
| 2.19.2 | `plugin/` @ v2.19.2 | 2026-05-24 | Initial Antigravity port. Prior draft (`plugin-antigravity.archive-2026-05-24-draft/`) was built on incorrect contract assumptions; this is the verified rebuild. |
