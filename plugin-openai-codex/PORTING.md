# ARIA Knowledge Codex Port

This directory is the standalone Codex port of ARIA Knowledge.

The Claude Code plugin in `../plugin-claude-code/` remains the canonical implementation for the
knowledge folder and content schema. The Codex port may diverge in manifests,
commands, hook payload handling, and Codex-specific tool names, but it should not
silently fork the markdown knowledge contract.

## Stable Contract

Keep these compatible with the Claude Code-standard plugin:

- Knowledge folder layout under `template/`
- Backlog formats under `intake/`
- `index.md` sections and tag semantics
- Project tier under `projects/{tag}/`
- Team-shared tier under `_project-knowledge/`
- Rule 22 content and working-rule numbering

## Codex Adapter Surface

Codex-specific files live here:

- `.codex-plugin/plugin.json`
- `hooks.json`
- `commands/`
- `bin/codex-hook.sh`
- `bin/codex-hook.py`

The hook adapter reads the shared `~/.claude/aria-knowledge.local.md` first, then
falls back to legacy `~/.codex/aria-knowledge.local.md` for older Codex-only
installs. The shared config is intentional: Claude Code and Codex should use the
same knowledge folder, cadences, project tier, and shared-knowledge settings
unless the user explicitly overrides `KT_CONFIG` or `ARIA_KNOWLEDGE_CONFIG`.

## Current Parity Notes

- Skills should keep shared knowledge schemas compatible while using Codex-native
  metadata, config, and hook wording.
- This port tracks Claude Code ARIA `2.46.2` with Codex release label `2.46.2-codex.0` for shared knowledge templates, review skills, audit/preflight/prospect/retrospect workflows, Rule 35/Rule 36/Rule 37 content, and Codex-supported hook behavior.
- Rule 22 maps Codex file edits to `apply_patch`; Codex also supports `Edit|Write`
  matcher aliases for the same canonical tool.
- `UserPromptSubmit` is the Codex-native active-knowledge intent hook. It scans
  the prompt against the shared tag index and injects model-visible
  `additionalContext`.
- `SubagentStart` and `SubagentStop` map directly to Codex subagent hooks for
  self-report nudges and durable capture.
- `SESSION.md` in-progress state, `auto_prospect`, and `auto_retrospect` are
  implemented in the Python adapter for Codex `apply_patch` and shell outputs.
- Shell write detection is advisory in this port; preflight-before-commit can warn
  or deny based on shared config; scheduled prompts that begin with `/` are denied
  when Codex exposes the scheduler tool call to hooks.
- `/foundational-review` and `/readiness-audit` are ported as Codex-native skills. ADR-094 Claude/Cowork runtime gates are stripped, and the bundled canonical process doc is read from `${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/foundational-review/foundational-review-chain.md`.
- `/audit`, `/audit usage`, `/audit style`, `/auto`, `/preflight`, `/roadmap`, `/interview`, and `/recap` are ported as Codex-native skills with ADR-094 runtime gates stripped.
- `/aria-assist` is ported as a manual Codex skill. Claude Code's launchd scheduler and `pm-*` notifier/collector scripts are intentionally not bundled.
- `/clip`, `/clip-thread`, and `/extract-doc` are retired from active discovery and archived under `skills/.archived/`; their live workflows are handled by `/intake`, `/intake thread`, and `/intake extract`.
- Claude Code `TaskCreated` has no exact Codex event. The closest intent-based
  equivalent is `UserPromptSubmit` plus subagent boundary hooks, not per-task
  dispatch.
- Claude Code `/statusline`, `statusline-meter.sh`, and
  `usage-threshold-inject.sh` are intentionally not ported because Codex exposes
  no plugin statusline slot or usage/rate-limit percentage payload today.
- Hosted Codex web search is not on the local plugin hook path. `pre-external-fetch-check.sh` is wired for local/MCP-style `WebFetch` and `WebSearch` calls when they appear in hook payloads.
- Hooks are enabled by default in current Codex, but plugin-bundled hooks still
  require user trust review before they run.
- **Codex routes every hook through the single `bin/codex-hook.py` entrypoint, so
  post-event checks are implemented as functions inside it, not as standalone
  `.sh` scripts.** ⛔ **Do NOT copy canonical's `post-*-check.sh` files into this
  port on a parity sync.** Three of them (`post-edit-tautology-check.sh`,
  `post-plan-prospect-check.sh`, `post-push-retrospect-check.sh`) were copied in
  and shipped for a while while being referenced by nothing — their logic already
  lived in `codex-hook.py` as `tautology_message()`, `auto_prospect_message()` and
  `auto_retrospect_message()`, each defined and called. Removed 2026-08-19 per the
  Rule 6 carve-out for never-wired code. The hazard is not the wasted bytes: it is
  that the same logic in two places, with only one of them running, means a future
  edit to the shell copy silently changes nothing. **Check `codex-hook.py` for an
  existing function before adding any `bin/` script here.** Canonical retains the
  `.sh` files, which remain the reference implementation.

## v2.46.2 update (2026-08-19) — Current Claude parity pass

- Synced active Codex skill bodies and rule templates to the canonical Claude Code surfaces.
- Added Codex-native ports for `/audit`, `/audit usage`, `/audit style`, `/auto`, `/preflight`, `/roadmap`, and manual-only `/aria-assist`.
- Added Codex adapter coverage for shell write bypass warnings, preflight-before-commit gating, scheduled prompt slash-command denial, local external-fetch coverage gating, and touched-test tautology warnings.
- Preserved non-equivalents where Codex has no intent-based surface: `/statusline` and unattended ARIA Assist scheduling/notifying.

## v2.35.2 update (2026-06-22) — Consolidated intake

MCP-consuming capture now flows through active skills with Codex-native metadata:

- `intake/SKILL.md` — `thread` mode consumes `~~chat` / `~~email`; `extract` mode consumes `~~docs` page/doc sources when available
- `meeting-notes/SKILL.md` — `~~docs` page OR paste fallback → structured meeting note
- `digest/SKILL.md` — composite probe across all 4 categories → weekly rollup
- `sync-decisions/SKILL.md` — **first WRITE-side ARIA skill**; mirrors decisions to `~~docs` MCP with Rule 22 advisory preamble per ADR-016

Plus `.mcp.json` (12 MCPs across chat/email/project-tracker/docs categories) and `CONNECTORS.md` (`~~` marker convention reference) — both byte-identical to the Claude port.

### Concept-and-function-preserved-but-method-may-diverge (per Mike's D2 framing)

- **MCP runtime parity:** Codex's MCP client may or may not surface the same tool names as Claude Code's MCP client for any given vendor MCP (slack, notion, linear, etc.). The capability-probe pattern (ADR-015) degrades gracefully — if a `~~category` tool isn't available at runtime, the SKILL.md outputs the standard fallback notice ("No required MCPs connected") and stops. No SKILL.md modification needed in Codex.
- **OAuth flow surface:** Claude Code prompts for OAuth via its own MCP client. Codex's flow may differ. The `.mcp.json` declaration (with `oauth.clientId` + `callbackPort` for Slack) is the same; the runtime that consumes it differs per surface.
- **Write-side discipline:** `sync-decisions` Rule 22 advisory preamble (ADR-016) is Layer-1-only (skill prose + required output format). Codex has no PreToolUse hook on MCP tool calls; this matches Cowork's constraint and is the documented Layer-1 enforcement pattern. SKILL.md body unchanged.

Skill descriptions are Codex-native; durable knowledge templates may still mention Claude Code where the shared knowledge folder documents cross-port conventions.
