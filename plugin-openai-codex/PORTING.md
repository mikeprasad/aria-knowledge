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
- This port tracks Claude Code ARIA `2.57.4` (release label `2.57.4-codex.1`; parity re-verified 2026-10-25, see that section) for shared knowledge templates, review skills, audit/preflight/prospect/retrospect workflows, Rule 35/Rule 36/Rule 37 content, and Codex-supported hook behavior.
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

## 2.57.4-codex.1 update (2026-10-25) — Codex transcript locator; parity re-verified

- **`/snapshot` reads Codex's own session store.** `bin/save-transcript.sh` finds this thread's rollout
  at `${CODEX_HOME:-~/.codex}/sessions/YYYY/MM/DD/rollout-<timestamp>-<thread id>.jsonl` by
  `$CODEX_THREAD_ID` (Codex sets it in every shell command), then by an id passed as an argument, and
  checks the file's first `session_meta` record names the same thread. A known id with no match, or a
  mismatched `session_meta`, exits 1 and writes nothing. With no id at all it takes the newest rollout
  and prints `⚠ GUESSED`. Sources: Codex docs (via context7) and the on-disk store.
- **Capture filenames use the LAST 8 characters of the id** (`kt_codex_id_short` in `bin/config.sh`),
  in `save-transcript.sh`, `pre-compact-check.sh` and `subagent-stop-capture.sh`. Codex ids are
  UUIDv7, whose leading characters are a timestamp: of 57 local rollouts, 37 shared their first 8
  characters (`019e3929`), so first-8 names let sessions overwrite each other's capture; the last 8
  had 0 duplicates. Do not "restore" `cut -c1-8` on a parity sync — canonical can keep first-8
  because Claude Code ids are random UUIDv4.
- **Tests:** five in `tests/test_codex_port.py` (own thread over a newer sibling sharing its prefix,
  id argument + `CODEX_HOME`, unknown and mismatched ids write nothing, no-id `GUESSED`, pre-compact
  name), all seen red on the previous helper; two mutations (first-8 helper, `session_meta` check
  removed) each turned their intended tests red.
- **Parity re-verified against canonical 2.57.4.** The 26 canonical skills changed since 2.55.1 add 96
  lines. Every added line absent here is one of: a `scripts/` path rename, the `/auto` self-restart
  section (not ported), or `/setup` Step 7ea text whose `session-start-rules.sh` this port does not
  ship (the step self-gates to `skip`). The 2.57.4 external-fetch hook change was already here.

## v2.55.1 update (2026-10-14) — Current Claude parity pass

Skills were brought from canonical v2.46.4 to v2.55.1 by a **3-way merge per skill** (base =
canonical v2.46.4, ours = this port, theirs = canonical HEAD), with base and theirs first
rewritten into Codex form (Codex frontmatter, ADR-094 gate stripped) so that only real content
conflicts remained (16, each resolved by hand). Codex adaptations below survived the merge.

- **New skill `/audit rules`** (`skills/audit-rules/`). The merged `/audit` dispatcher routes
  `rules` to it. Ships `bin/check-rule-lead-bytes.sh` for its lead byte-check. Step 6 differs from
  canonical: Codex has no instruction-file digest, so the step verifies the rule's `### U<n>`
  header, which `session-start-check.sh` injects each session.
- **`bin/lib-session-state.sh` now carries the full ledger** (`kt_ss_ledger_add/_prune/_candidates/
  _mark_consumed/_mark_superseded/_token_locate/_consume_active`, `kt_ss_active_is_newer`,
  `kt_ss_read_active_*`). Before this, `/handoff` and `/wrapup` called `kt_ss_ledger_add` and
  `_prune` while the lib defined neither. Codex is now the fourth port in the per-function parity
  arm of `tests/repros/session-state.sh` (block N). The `AGENTS.md` root marker is kept.
- **SessionStart** carries canonical's token-resume SESSION STATE procedure
  (`aria-handoff: <project>/<sid>@<at>` → `kt_ss_ledger_token_locate` → `consume_active` /
  `mark_consumed`) and the `/audit <verb>` nudges.
- **Removed, never wired:** `bin/pre-edit-check.sh` and `bin/post-edit-check.sh`. No commit ever
  referenced them from `hooks.json` or the adapter; `codex-hook.py` implements both inline. Same
  class as the three `post-*-check.sh` removed 2026-08-19 — do not re-copy them on a parity sync.
- **Added dependency:** `bin/lib-state-key.sh` (sourced by the merged `pre-external-fetch-check.sh`;
  without it that hook emitted nothing — caught by the port suite).
- **Adapted, not ported:** `/auto`'s "Runtime precondition — Bash required" section (routes to
  Cowork gates; Codex always has a shell) is removed. ⚠ *Corrected 2026-10-25:* this bullet also said
  the `/handoff` and `/wrapup` "Rule 22 bypasses through the shell" step is a self-report because Codex
  has no writer for that ledger. That was superseded in the same pass: `codex-hook.py` runs
  `pre-bash-write-check.sh`, which writes `${TMPDIR}/aria-r22-bypass-<session_id>`, and both skills
  read it (covered by `test_pre_tool_use_shell_records_in_place_write_to_bypass_ledger`).
- ✅ **Closed 2026-10-25 in 2.57.4-codex.1** (see that section). Was: `/snapshot` → `bin/save-transcript.sh` searches Claude Code's
  `~/.claude/projects`, not Codex's own session store. It now prints a `GUESSED` warning instead of
  silently capturing, but a Codex transcript locator still needs writing against current Codex docs.

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
