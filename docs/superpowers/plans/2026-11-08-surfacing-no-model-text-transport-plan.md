# Active Surfacing — No Model-Transported Text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** No instruction tells a model to compose a shell command containing free text; every hook runtime ranks the user's prompt in code.

**Architecture:** One shared capture core (`lib-prompt-surface.sh`) turns prompt text into ledger-filtered, ranked `ARIA ACTIVE —` injection text; the Claude Code, Cursor and Antigravity hooks are thin I/O adapters over it. The CLI gains reference inputs (`--file`, `--git-range`) so skills never carry text; the directive and value line drop every command template.

**Tech Stack:** POSIX sh + awk, `jq` (hook JSON only), bash test harnesses (`tests/run.sh`, `plugin-claude-code/tests/run.sh`), bats (`plugin-antigravity/tests`).

**Spec:** `docs/superpowers/specs/2026-11-08-surfacing-no-model-text-transport-spec.md` (gate 1 PROCEED-WITH-CHANGES, C1–C6 applied).

## Global Constraints

- PUBLIC repo: fixtures and docs use placeholders only (`proj-a`, `proj-b`, `proj-c`, `site-1`). Run `sh plugin-claude-code/scripts/check-public-hygiene.sh` AFTER each commit.
- No model-facing instruction composes a shell command containing free text. Forbidden in any tracked instruction file: `<<'ARIA_TASK'`, `aria-surface.sh" -`, `"<task`, `"<the query`.
- CLI exit 0 always; `unavailable: <reason>` for could-not-look; nothing only for nofire.
- `--git-range`: each side matches `^[A-Za-z0-9._/~^@{}][A-Za-z0-9._/~^@{}-]*$` (no leading `-`); git called with `--end-of-options`.
- Hooks fail silent to the model; every failure appends `<UTC> <runtime> <step> <reason>` to `${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}/aria-surface-hook.log`.
- Hook latency: p95 ≤ 150 ms warm on a ~45k-line index (Claude Code prompt hook, Cursor `beforeSubmitPrompt`, Antigravity PreInvocation responsibility).
- Injection text: `ARIA ACTIVE — <n> knowledge file(s) for this task (tags: …). Read them before answering and say in one line which you used and why:` + one absolute path per line; < 10,000 chars.
- Session ledger stays `/tmp/aria-active-<sanitised id>`; ledger lines are paths relative to the knowledge folder.
- `plugin-claude-code/rules/aria-rules.md` ≤ 26,198 bytes.
- Host premises are docs as read 2026-11-08 via Context7 + one Antigravity App transcript measured 2026-11-08; hooks log `cursor_version` / `modelName` to the debug log.
- Libs and CLI copies byte-identical across claude-code, openai-codex, cursor-template, antigravity (antigravity via `sh plugin-antigravity/build.sh`; regenerate it in every task that changes a canonical script). NEVER `check-port-drift.sh --update all`.
- Run everything under sh/bash only.

## Review Focus

- A prompt or referenced file containing backticks, `$(…)`, `$HOME` and a bare `ARIA_TASK` line → ranked as literal words, nothing executes → Task 1 `file_content_is_never_shell`, Task 2 `core_hostile_text_literal`.
- A `--git-range` value starting with `-` (`--output=/tmp/x..HEAD`) → `unavailable: invalid --git-range`, git never sees an option → Task 1 `git_range_leading_dash_rejected`.
- Cursor: two prompts in one conversation → each generation injected once, the second not suppressed by the first's pending file → Task 3 `inject_once_per_generation`.
- Antigravity: several model invocations within one user turn → one injection for that USER_INPUT, none repeated → Task 4 `inject_once_per_user_input`.
- Missing jq / transcript / index → silent to the model AND one line in the debug log → Task 2 `core_failure_logged`, Task 3 `capture_silent_without_jq`, Task 4 `no_transcript_logged`.

## Gate-2 amendments (/prospect 2026-11-08, PROCEED-WITH-CHANGES — `knowledge/logs/prospect/2026-11-08-file-plan-surfacing-no-model-text-transport.md`)

- **G1 (Task 2):** the config-value cache filename carries the config-path key — `aria-prompt-config-<cksum of the resolved config path>.cache` — because the ports read different configs (claude-code/codex `~/.claude/…`, cursor `<repo>/.cursor/…`, antigravity `~/.gemini/antigravity/…`) and one fixed name would thrash between runtimes and Cursor workspaces. Add arm `core_two_configs_two_caches` (alternate two configs; the second call for each is a cache hit — no rebuild).
- **G2 (Task 3):** `prompt-capture-check.sh` replaces any older pending file for the same conversation and prunes pending files older than 24 h for any conversation. Add arm `stale_pending_pruned`.
- **G3 (Task 4):** the newest USER_INPUT is found in the last 400 transcript lines only (`tail -n 400`), never a full-file scan per model call; measure p95 on a synthetic transcript of ≥ 1,100 lines.

---

### Task 1: CLI reference inputs (`--file`, `--git-range`)

**Files:**
- Modify: `plugin-claude-code/scripts/aria-surface.sh`
- Test: `tests/repros/surfacing-cli-references.sh` (new)
- Regenerate: `plugin-antigravity/bin/aria-surface.sh` (build.sh); copy to `plugin-openai-codex/bin/` and `plugin-cursor-template/scripts/aria/` (byte-identical)

**Interfaces:**
- Produces: `sh aria-surface.sh --file '<path>' [--git-range '<a>..<b>']` → same output contract as today (tags line + paths | nothing | `unavailable: …`). Query = Markdown headings (`^#{1,6} `) of the file + its first 40 non-blank lines, plus up to 20 `git log --format=%s --end-of-options <a>..<b>` subjects. Positional text and `-` stay for programmatic callers.

- [ ] **Step 1: Write failing tests** in `surfacing-cli-references.sh` (fixture index `tests/repros/fixtures/surfacing/index.md`, isolated HOME/TMPDIR/KT_SURFACE_CACHE_DIR, scratch config + git repo):
  - `file_ranks_from_content` — a file whose heading says `proj-b payments` → `tags:` includes `proj-b payments`, first path carries proj-b.
  - `git_range_ranks_from_subjects` — a scratch repo with a commit subject `proj-b payments retry` → same.
  - `file_content_is_never_shell` — file content with `` `touch $T/m1` ``, `$(touch $T/m2)`, a line `ARIA_TASK`, then `touch $T/m3` → no marker file exists; output is a tags line or empty, never an error.
  - `git_range_leading_dash_rejected` — `--git-range '--output=$T/x..HEAD'` → stdout `unavailable: invalid --git-range`, `$T/x` absent.
  - `file_missing_unavailable` — `--file '$T/none.md'` → `unavailable: invalid --file`.
  - `exit_always_zero` — every arm above exits 0.
- [ ] **Step 2: Run** `sh tests/repros/surfacing-cli-references.sh` — expect FAIL (flags unknown).
- [ ] **Step 3: Implement** argument parsing in `aria-surface.sh`: `--file`, `--git-range` (validation per Global Constraints; `git rev-parse --verify --end-of-options` both sides in the file's/cwd's repo), build the query, call `kt_index_match` as today. Update the header comment: references for models, positional/stdin for programs only.
- [ ] **Step 4: Run** the new suite + `sh tests/repros/surfacing-rank.sh` + `sh tests/run.sh` — all bare exit 0.
- [ ] **Step 5: Commit** `feat(surfacing): aria-surface.sh takes --file and --git-range references`; hygiene gate.

### Task 2: Shared capture core; Claude Code hook becomes an adapter

**Files:**
- Create: `plugin-claude-code/scripts/lib-prompt-surface.sh`
- Modify: `plugin-claude-code/scripts/prompt-context-check.sh` (keep stdin/jq/JSON I/O only)
- Test: `plugin-claude-code/tests/test-prompt-surface-core.sh` (new); `plugin-claude-code/tests/test-prompt-context-check.sh` must stay green unchanged
- Regenerate antigravity (build.sh); copy the lib to `plugin-cursor-template/scripts/aria/`

**Interfaces:**
- Produces (sourced, POSIX sh; requires `KT_PS_SCRIPT_DIR` = the dir holding config.sh + lib-index-match.sh):
  - `kt_ps_load_config` → sets KT_KNOWLEDGE_FOLDER, KT_ACTIVE_SURFACING, KT_PROJECTS_ENABLED, KT_PROJECTS_LIST, KT_CONFIGURED, KT_CONFIG_ERROR via the existing data-only config cache (moved verbatim from prompt-context-check.sh; header `aria-prompt-config 1`).
  - `kt_ps_strip_pasted` — stdin → stdout, removes `<pasted_content …>` … `</pasted_content …>` blocks (moved from the hook).
  - `kt_ps_surface <text> <ledger_path>` → prints the injection text (format per Global Constraints) or nothing; sets `KT_PS_STATUS` ∈ {`injected`, `nothing-new`, `nofire`, `disabled`, `error:<step>`}; records the ledger only when it printed.
  - `kt_ps_log <runtime> <step> <reason>` → appends one line to the debug log (never stdout).
  - `kt_ps_sanitize_id <raw>` → `[A-Za-z0-9._-]` only.

- [ ] **Step 1: Write failing tests** in `test-prompt-surface-core.sh`: `core_injects_paths` (fixture fires → text starts `ARIA ACTIVE — `, absolute paths, status `injected`); `core_nothing_new` (second call same ledger → empty, `nothing-new`); `core_disabled` (`active_knowledge_surfacing: false` → `disabled`); `core_hostile_text_literal` (backticks/`$(…)`/`ARIA_TASK` line → no marker file); `core_failure_logged` (index missing → `error:…`, one line in the debug log, nothing on stdout); `core_strip_pasted`; `core_sanitize_id` (`x/../y` → `x..y`).
- [ ] **Step 2: Run** — expect FAIL (lib absent).
- [ ] **Step 3: Implement** the lib by MOVING the logic out of `prompt-context-check.sh`; the hook keeps jq extraction, `kt_ps_strip_pasted`, `kt_ps_surface`, and the `jq -n --arg` JSON emission.
- [ ] **Step 4: Run** `sh plugin-claude-code/tests/run.sh` (both hook tests green, existing 53-arm suite unchanged) + `sh tests/run.sh`; re-measure hook warm p95 on the real index (fresh process, read-only, fake session id) — ≤ 150 ms.
- [ ] **Step 5: Commit** `refactor(surfacing): one shared capture core; the Claude Code prompt hook is an adapter`; hygiene gate.

### Task 3: Cursor capture hooks

**Files:**
- Create: `plugin-cursor-template/scripts/aria/prompt-capture-check.sh`, `plugin-cursor-template/scripts/aria/prompt-context-inject.sh`
- Modify: `plugin-cursor-template/.cursor/hooks.json` (add `beforeSubmitPrompt` and `postToolUse` entries)
- Test: `tests/repros/cursor-prompt-capture.sh` (new)

**Interfaces:**
- Consumes: Task 2's `kt_ps_*` (cursor copy of the lib; `KT_PS_SCRIPT_DIR` = `scripts/aria`).
- Produces: `beforeSubmitPrompt` stdin `{prompt, conversation_id, generation_id, cursor_version, …}` → stdout always `{"continue":true}`; writes `<cache dir>/aria-cursor-pending-<sid(conversation)>-<sid(generation)>` holding the injection text. `postToolUse` stdin `{conversation_id, generation_id, …}` → `{"additional_context":"<text>"}` once and deletes the pending file; otherwise `{}`. Ledger `/tmp/aria-active-<sid(conversation_id)>`.

- [ ] **Step 1: Write failing tests**: `capture_always_continues` (any input, incl. malformed → `{"continue":true}`); `inject_once_per_generation` (capture g1 → inject g1 returns context, second postToolUse g1 returns `{}`; capture g2 → inject g2 returns its own context); `capture_silent_without_jq` (PATH farm without jq → `{"continue":true}` printed by the shell fallback, debug-log line written); `inject_paths_only` (no file bodies, < 10,000 chars); `hooks_json_registered` (`jq` finds both commands); `cursor_version_logged`.
- [ ] **Step 2: Run** — expect FAIL.
- [ ] **Step 3: Implement** both scripts (resolve the repo root with `git rev-parse --show-toplevel` like sibling Cursor hooks; config from `.cursor/aria-knowledge.local.md` via the port's config.sh); `{"continue":true}` must be printed even if everything else fails.
- [ ] **Step 4: Run** the new suite + `sh tests/run.sh`; measure `beforeSubmitPrompt` warm p95 on the real index (scratch Cursor config pointing at it, read-only) — ≤ 150 ms.
- [ ] **Step 5: Commit** `feat(cursor): capture hooks rank each prompt in code and inject once per generation`; hygiene gate.

### Task 4: Antigravity PreInvocation capture

**Files:**
- Modify: `plugin-antigravity/bin/antigravity/pre-invocation-aria.sh` (new responsibility 4)
- Test: `plugin-antigravity/tests/test-pre-invocation-aria.bats` (extend); fixture `plugin-antigravity/tests/fixtures/transcript-user-input.jsonl` (new, measured schema: `type`, `content`, `source`, `status`, `step_index`, `created_at`; user turns `type:"USER_INPUT"`, `source:"USER_EXPLICIT"`)

**Interfaces:**
- Consumes: Task 2's `kt_ps_*` (antigravity copy via build.sh; `KT_PS_SCRIPT_DIR` = `bin`).
- Produces: on each invocation, newest `USER_INPUT` whose `step_index` is not in `<cache dir>/aria-ag-surfaced-<sid(conversationId)>` → append `{"ephemeralMessage":"<text>"}` to `injectSteps`, record the step_index; existing responsibilities 1–3 unchanged.

- [ ] **Step 1: Write failing tests**: `inject_once_per_user_input` (two invocations, same newest USER_INPUT → one injection); `new_user_input_injects_again`; `no_user_input_silent`; `malformed_line_ignored`; `no_transcript_logged` (debug-log line, existing outputs unchanged); `existing_responsibilities_unchanged` (session-start message on invocationNum 0 and scope-log drain still present); `modelName_logged`.
- [ ] **Step 2: Run** `bats plugin-antigravity/tests/test-pre-invocation-aria.bats` — expect FAIL.
- [ ] **Step 3: Implement** responsibility 4 with `jq` over the transcript (last USER_INPUT), `kt_ps_surface`, state file.
- [ ] **Step 4: Run** all antigravity bats + `sh tests/run.sh` (idempotence); measure the responsibility's warm p95 on the real index with a synthetic transcript — ≤ 150 ms.
- [ ] **Step 5: Commit** `feat(antigravity): PreInvocation ranks the newest user input in code`; hygiene gate.

### Task 5: Instructions carry no text transport

**Files:**
- Modify: `plugin-claude-code/rules/aria-rules.md` (ARIA ACTIVE CONTEXT block: delete branch (b)); `plugin-claude-code/scripts/session-start-check.sh` (ARIA SURFACE path-only); port emitters `plugin-openai-codex/bin/session-start-check.sh`, `plugin-cursor-template/scripts/aria/session-start-check.sh`, `plugin-antigravity/bin/antigravity/pre-invocation-aria.sh` (same; name each runtime's hook as the source); skills `plugin-claude-code/skills/{prospect,retrospect}/SKILL.md`, `plugin-openai-codex/skills/{prospect,retrospect}/SKILL.md`, `plugin-claude-cowork/skills/{prospect,retrospect}/SKILL.md` (Cowork: wording only — keep by-hand, no shell); regenerate antigravity skills (build.sh) and cursor `.mdc` (`python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`)
- Test: `tests/repros/surfacing-ranking-verbatim.sh` (extend: class guard); `tests/repros/session-start-single-emitter.sh` (ARIA SURFACE path-only)

**Interfaces:**
- Consumes: Task 1's `--file` / `--git-range`.
- Produces: Step 0.5 item "2–6" runs `sh '<ARIA SURFACE path or plugin-root form>' --file '<plan/spec path>'` and/or `--git-range '<a>..<b>'`; for text-only scopes, write the text to a scratch file with the runtime's file-write tool, then `--file`. Directive: (a) injection is the source wherever hooks run (none = read nothing); (c) only where no hook can run, match by hand per the canonical paragraph.

- [ ] **Step 1: Write failing tests**: `no_text_transport_anywhere` (class guard over every tracked instruction file in all ports; planted copy fails; census prints the files scanned); `skills_use_references` (all CLI-running Step 0.5 copies contain `--file` and `--git-range`); `surface_line_path_only` (ARIA SURFACE line has no `run:`/`<<`); `digest_within_bound` (`wc -c` ≤ 26198).
- [ ] **Step 2: Run** — expect FAIL.
- [ ] **Step 3: Edit** all listed files; regenerate antigravity and cursor.
- [ ] **Step 4: Run** `sh tests/run.sh`, `sh plugin-claude-code/tests/run.sh`, `sh plugin-openai-codex/tests/run.sh`, antigravity bats, `tests/repros/claude-ai-upload-limits.sh`; Gate B and Cowork summed descriptions unchanged; per-rule digest lock green without relock.
- [ ] **Step 5: Commit** `refactor(surfacing): instructions pass references, never task text`; hygiene gate.

### Task 6: Port ledger, CHANGELOG

**Files:**
- Modify: `PORT-LEDGER.json` (via `check-port-drift.sh --update <port>` per port, only after verifying that port's changed surfaces; never `--update all`); `plugin-claude-code/scripts/check-port-drift.sh` if `lib-prompt-surface.sh` must be tracked per port (add it beside lib-index-match.sh / aria-surface.sh); `CHANGELOG.md` (`[Unreleased]`)
- Test: `tests/repros/surfacing-ranking-verbatim.sh` (`libs_identical` covers lib-prompt-surface.sh copies)

- [ ] **Step 1: Write failing test** `prompt_surface_libs_identical` (cursor + antigravity + claude-code copies byte-identical).
- [ ] **Step 2: Run** — expect FAIL if any copy lags.
- [ ] **Step 3: Sync copies; re-baseline per port; CHANGELOG**: replace the heredoc sentence with references-only; add Cursor capture (beforeSubmitPrompt rank, postToolUse inject; no injection on a tool-free answer) and Antigravity PreInvocation capture; both unverified in a live runtime (owed); the debug log path.
- [ ] **Step 4: Run** every suite + drift check + idempotence — bare exit 0.
- [ ] **Step 5: Commit** `chore(ports): shared capture core tracked; changelog for capture hooks`; hygiene gate.

After Task 6: whole-branch review on the most capable model (spec C5), then `/retrospect` on the range; stop before any version bump, push or release.
