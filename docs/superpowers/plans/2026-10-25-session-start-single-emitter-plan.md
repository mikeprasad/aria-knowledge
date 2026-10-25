# SessionStart Single Emitter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One SessionStart hook routes every message by audience — human nags to `systemMessage`, model instructions to `additionalContext` — and shows no banner on `source=compact`.

**Architecture:** `plugin-claude-code/scripts/session-start-check.sh` absorbs `session-start-rules.sh` (archived). It builds `USER_MESSAGES` and `MODEL_MESSAGES` and prints one JSON object with `printf`. Behaviour text lives in the bundled digest `plugin-claude-code/rules/aria-rules.md`; the hook emits only values.

**Tech Stack:** POSIX `sh`, `jq` in tests, the repo's two test runners (`tests/run.sh`, `plugin-claude-code/tests/run.sh`).

**Spec:** `docs/superpowers/specs/2026-10-25-session-start-single-emitter-spec.md` (prospected: `knowledge/logs/prospect/2026-10-25-file-session-start-single-emitter-spec.md`, PROCEED-WITH-CHANGES, changes folded in as §4.5a).

## Global Constraints

- Never emit with `echo`; every hook output line is `printf '%s\n'`. (F1)
- Banner (`systemMessage`): human-directed only. Model text (`additionalContext`): values + the existing compact block / CONFIG / fallback.
- On `source=compact`: no `systemMessage` at all.
- Model payload order: compact block → CONFIG (or fallback digest + U-rules + CONFIG) → `ARIA PROJECT` → tracked artifacts → `ARIA PROJECTS` (not on compact) → `ARIA CODEMAPS` → `ARIA USAGE`.
- Value-line text, verbatim:
  - `ARIA PROJECT — this session started inside configured project '<tag>'.`
  - `ARIA PROJECTS — menu: <menu>; projects root: <root>.`
  - `ARIA CODEMAPS — <CM_FULL>.`
  - `ARIA USAGE — this account's usage snapshot: <path>.`
- Every test invocation of the hook sets `HOME=<sandbox>` and `</dev/null`.
- Public repo: no private project names in any committed text; run Gate D (`plugin-claude-code/scripts/check-public-hygiene.sh`) after committing.
- Dated docs (specs, plans, CHANGELOG entries) that name `session-start-rules.sh` are records and stay as written.

## Review Focus

1. **A malformed banner taking the model context down with it** — any arm whose output is not strict JSON. Pinned by AC13 in Task 3.
2. **A test run overwriting the developer's live `~/.claude/rules`** — the merged hook writes there. Pinned by the runner guards in Task 1.
3. **First run (no audit log) losing the model payload** — the old early `exit 0`. Pinned in Task 3 (first-run arm asserts `additionalContext`).
4. **A hook invoked with an open, silent stdin hanging** — every test caller closes stdin; the full suites must finish (Task 5).
5. **Picker offered again after compaction** — `ARIA PROJECTS` must be absent on compact. Pinned in Task 4.

---

### Task 0: Baseline the generators

**Files:** none changed.

- [ ] **Step 1:** In the worktree, run `./plugin-antigravity/build.sh` and `python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`, then `git status --short`.
  Expected: no changes. Any diff is pre-existing drift — record it and keep it out of this branch's commits.

### Task 1: Guard the developer's real rules files

**Files:**
- Modify: `tests/run.sh`, `plugin-claude-code/tests/run.sh`
- Modify: `tests/repros/picker-gating.sh:30,36`, `tests/repros/session-state-token-directive.sh:30,53`, `plugin-claude-code/tests/test-count-backlog-entries.sh:107`

**Interfaces:** Produces: both runners fail with `FAIL: suite modified the real ~/.claude/rules` when either `$HOME/.claude/rules/aria-rules.md` or `aria-user-rules.md` changes bytes (or appears/disappears) during the run.

- [ ] **Step 1:** In each runner, record `cksum` (or `absent`) of the two files before the loop; after the loop compare and count a failure on any difference.
- [ ] **Step 2:** Give the three listed callers `HOME="$TMP"` (their existing sandbox; create `$TMP/.claude`) and `</dev/null`.
- [ ] **Step 3:** Run both runners. Expected: same totals as baseline (52 suites / 520 tests), guards silent.
- [ ] **Step 4:** Commit `test: runners fail when a run modifies the real rules files`.

(The guard is proven red in Task 3, Step 6, under a sandbox HOME.)

### Task 2: Digest carries the behaviour

**Files:**
- Modify: `plugin-claude-code/rules/aria-rules.md`
- Test: `plugin-claude-code/tests/test-aria-rules-digest.sh` (new `digest_has` assertions), `tests/repros/session-ledger-resolution.sh` G, `tests/repros/session-state-token-directive.sh`

**Interfaces:** Produces the directive keys Task 4's value lines rely on: the strings `ARIA PROJECTS`, `ARIA PROJECT`, `ARIA CODEMAPS`, `ARIA USAGE` each appear in the digest inside a directive stating what to do when that line reached you and that it is off otherwise.

- [ ] **Step 1: Failing tests.** Add `digest_has` assertions for: `PROJECT PICKER`, `ARIA PROJECTS`, `PROJECT CONTEXT`, `CODEMAP —` (directive), `ARIA CODEMAPS`, `ARIA USAGE`, `ARIA CONTEXT —` (passive variant), `$CLAUDE_CODE_SESSION_ID`, `never use \`ls -t\``. Re-point `session-state-token-directive.sh` to `grep -qF` the digest file instead of hook output (its ten phrases unchanged). Re-point repro G to the digest.
- [ ] **Step 2:** Run. Expected FAILs: every new `digest_has` assertion; token-directive on exactly one phrase, `state-verify gate, not a preamble` (the other nine are already in the digest — checked 2026-10-25); G (the digest carries `/tmp/aria-active-${session_id}`).
- [ ] **Step 3:** Edit the digest:
  - New section `## Conditional on a session-start value line` after the config section, opening with: absence of the line = directive off. Directives: PROJECT PICKER (current banner picker text, menu/root read from the line, resolve the tag via `projects_list` in `~/.claude/aria-knowledge.local.md`), PROJECT CONTEXT (suggest `/context <tag>` once, do not block), CODEMAP (read a listed map's Directory section before exploring that codebase; a map marked stale or possibly stale may not match the code — verify and offer `/codemap update`).
  - TASK BUDGET (snapshot-exists branch): add "If an `ARIA USAGE` line reached you, that path is this account's snapshot."
  - `active_surfacing` section: replace the ledger sentence with the banner's (`$CLAUDE_CODE_SESSION_ID`; unset or absent → proceed unfiltered; never `ls -t` the glob). Add a `### When active_surfacing is false AND index.md exists` passive ARIA CONTEXT block (banner text, `{knowledge_folder}` placeholder).
  - SESSION STATE: port the banner's missing clauses (FIFTH-argument reason, `never silently`, the terminal-entry reason, "surface it and reconcile before executing, never drive past it", "'Before you start, see X' is a state-verify gate, not a preamble"). No measurement history.
- [ ] **Step 4:** Run `./plugin-antigravity/build.sh` — `plugin-antigravity/rules/aria-rules.md` is a regenerated copy of the digest (build.sh:170-194). Expected diff: that file only (plus anything T0 recorded as pre-existing).
- [ ] **Step 5:** Run both suites. Expected: all green; G green; port-generation-idempotence green.
- [ ] **Step 6:** Commit the digest and its regenerated antigravity copy together: `fix(digest): carry the directives whose only copy was the user-facing banner`.

### Task 3: Single emitter

**Files:**
- Modify: `plugin-claude-code/scripts/session-start-check.sh`
- Move: `plugin-claude-code/scripts/session-start-rules.sh` → `plugin-claude-code/scripts/.archived/session-start-rules.sh` (header pointer: "merged into session-start-check.sh on 2026-10-25; see spec").
- Modify: `plugin-claude-code/.claude-plugin/plugin.json` (one SessionStart command)
- Test: `plugin-claude-code/tests/test-aria-rules-digest.sh`, `tests/repros/statusline-session-start.sh`, `plugin-claude-code/tests/test-user-rules-digest.sh:153`, new `tests/repros/session-start-single-emitter.sh`

**Interfaces:** Produces `session-start-check.sh` output: one line of JSON, keys `systemMessage` (optional) and `hookSpecificOutput.{hookEventName:"SessionStart", additionalContext}` (optional). Reads stdin JSON `session_id`, `source`.

- [ ] **Step 1: Failing tests** in `session-start-single-emitter.sh` (fixture: sandbox HOME, KT_CONFIG with an existing knowledge folder, an audit log dated old enough to fire a nag; every run `printf '{"session_id":"S1","source":"<src>"}' | … sh hook`):
  - AC1: `jq '.hooks.SessionStart[0].hooks|length' plugin.json` = 1, command names `session-start-check.sh`; `scripts/session-start-rules.sh` absent; `.archived/session-start-rules.sh` present.
  - AC2 (`startup`): `.systemMessage` contains `Knowledge audit` and none of the ten directive headers from spec AC2; `.hookSpecificOutput.additionalContext` contains `ARIA CONFIG —`.
  - AC3 (`compact`): `has("systemMessage")` = false; additionalContext begins with `ARIA WORKING RULES — still in force after compaction`; contains `ARIA CONFIG —`.
  - First run (no audit log): `.systemMessage` contains `ARIA Knowledge Active`; additionalContext contains `ARIA CONFIG —`.
  - AC13: `jq -e .` succeeds for: config error (malformed knowledge_folder), not configured (no config file), missing folder, first run, startup with nags, startup with no nags (fresh audit logs), compact, fallback (sandbox HOME with no rules dir).
- [ ] **Step 2:** Run it. Expected: AC1, AC2's directive-absence, AC3, first-run context, and AC13 (startup) FAIL.
- [ ] **Step 3: Implement.** In `session-start-check.sh`:
  1. After sourcing config: `INPUT=""; [ -t 0 ] || INPUT=$(cat)`; parse `SESSION_ID`, `HOOK_SOURCE` exactly as `session-start-rules.sh:46-49`. `TA_SESSION_ID` reads `$SESSION_ID`.
  2. Replace every `echo '{"systemMessage":…}'` with a call to `emit_and_exit` that prints the combined object.
  3. Move in, verbatim with comments: `kt_ensure_rules_files`, the DIGEST_WAS_PRESENT capture, CONFIG_LINE, the steady/fallback arm, and the compact block. They run immediately after the three config-error exits (not configured / config error / missing folder), BEFORE the date-epoch guard (old line 59) and the first-run branch. Every later exit — the date-epoch failure included — goes through the emitter so it carries this payload. (`grep -n 'exit' session-start-check.sh` lists them; plan gate 2026-10-25 found the date-epoch one.)
  4. First run: set the welcome as USER_MESSAGES and fall through to emission (no early exit).
  5. Delete the banner blocks RULE 22 ORDERING, TASK BUDGET, ARIA ACTIVE CONTEXT / ARIA CONTEXT, ARIA Project Context, Project Picker, SESSION STATE, INSIGHT CAPTURE, MEMORY PATHWAY, CODEMAP Found, DECISION ROUTING, STANDING USER RULES (Task 4 re-adds the computed values as model lines).
  6. When `HOOK_SOURCE = compact`, clear USER_MESSAGES.
  7. Emission: banner via `kt_json_escape`, model via `kt_json_escape_multiline`; build `{"systemMessage":…,"hookSpecificOutput":{…}}` with only the non-empty parts; `printf '%s\n'`.
  8. Keep the diagnostic log line; add `model=${#MODEL_MESSAGES}`.
- [ ] **Step 4:** `git mv` the rules script into `.archived/`, add its pointer header, update `plugin.json`.
- [ ] **Step 5: Re-point existing tests.** `test-aria-rules-digest.sh`: `HOOK=…/session-start-check.sh`; "does NOT emit systemMessage" → "banner carries no directive" (`jq -r '.systemMessage // ""'` has no `RULE 22 ORDERING`); the two F2 guards → AC1-style single-registration assertion and `kt_artifact_record_ledger` appears exactly once in `session-start-check.sh`. `statusline-session-start.sh`: `RULES_HOOK` → check script, fed `</dev/null`. `test-user-rules-digest.sh:153` → check script. Every new or re-pointed call has `HOME=<sandbox>` and stdin closed.
- [ ] **Step 6: Prove Task 1's guard.** With a sandbox HOME holding sentinel rules files, run `picker-gating.sh` as it was BEFORE Task 1 (from `git show HEAD~2:…`, HOME not isolated). Expected: sentinel bytes change and the runner guard logic reports FAIL. Then confirm the isolated version leaves them unchanged.
- [ ] **Step 7:** Run both suites. Expected: all green.
- [ ] **Step 8:** Commit `feat(session-start): one emitter routes each message by audience`.

### Task 4: Value lines

**Files:**
- Modify: `plugin-claude-code/scripts/session-start-check.sh`
- Test: `tests/repros/session-start-single-emitter.sh`, `tests/repros/picker-gating.sh`, `tests/repros/autonomy-posture.sh`

**Interfaces:** Consumes Task 3's MODEL_MESSAGES and HOOK_SOURCE. Produces the four value lines (Global Constraints, verbatim) plus `KT_ARTIFACTS_INSTRUCTION`, in the stated order.

- [ ] **Step 1: Failing tests.**
  - AC4: picker on, CWD outside any project → additionalContext contains `ARIA PROJECTS — menu: alpha (Alpha App), beta` (picker-gating's fixture menu); picker off → absent; `source=compact` with picker on → absent. Re-point `picker-gating.sh` to decode additionalContext.
  - AC5: a `CODEMAP.md` under CWD → additionalContext contains `ARIA CODEMAPS —` and its relative path.
  - AC6: configured project with a CODEMAP, `session_id` `sse-test-$$`, active surfacing on → additionalContext contains `[aria] Loaded CODEMAP directory`; the ledger (hardcoded `/tmp/aria-active-<sid>`, not TMPDIR) lists the path once; a second run with the same id emits no tracked-artifacts text. The test removes its ledger file on exit. Before the change this arm emits nothing (D4) — record it red.
  - Usage: sandbox HOME with `.claude/aria-statusline-state-x.json` → `ARIA USAGE —`.
  - `autonomy-posture.sh` B/C: assert on the digest (directive text, both variants present) and on additionalContext `autonomy=<value>`, instead of the banner.
- [ ] **Step 2:** Run. Expected: the new assertions FAIL.
- [ ] **Step 3:** Implement: compute each value at its old block's location, guarded by the old block's conditions; append to MODEL_MESSAGES in the stated order; skip `ARIA PROJECTS` when `HOOK_SOURCE = compact`.
- [ ] **Step 4:** Run both suites. Expected: all green.
- [ ] **Step 5:** Commit `feat(session-start): picker, project, CODEMAP and usage values reach the model`.

### Task 5: References, ports, measurement, live check

**Files:**
- Modify: `plugin-claude-code/skills/setup/SKILL.md`, `plugin-claude-code/skills/audit-rules/SKILL.md`, `plugin-claude-code/CONFIG.md`, `plugin-claude-code/scripts/lib-user-rules.sh` (comments), `plugin-claude-code/scripts/pre-compact-check.sh` (comments), `plugin-antigravity/build.sh` (comment beside the exclusion list), `plugin-claude-code/tests/test-audit-rules.sh` AR8
- Regenerate: `plugin-antigravity/` via `build.sh`; `plugin-cursor-template/.cursor/rules/*.mdc` via `port-skills-to-mdc.py`

- [ ] **Step 1:** Re-point each live reference from `session-start-rules.sh` to `session-start-check.sh`; AR8 expects the new name. `grep -rn 'session-start-rules' plugin-claude-code plugin-antigravity plugin-cursor-template tests` returns only `.archived/` and dated docs.
- [ ] **Step 2:** Run both generators. Expected diff: only the re-pointed references.
- [ ] **Step 3:** Run both suites + `plugin-antigravity/tests` if present + `tests/repros/port-generation-idempotence.sh`. Expected: green, guards silent, both runs finish.
- [ ] **Step 4: AC11.** Print `${#MODEL_MESSAGES}` for steady and compact at `/Users/…/Projects` with the real config and a sandbox HOME; record both numbers in the spec.
- [ ] **Step 5: AC12.** `claude -p` in a scratch dir with `--plugin-dir <worktree>/plugin-claude-code --setting-sources project`, asking the model to quote any `ARIA PROJECTS` and `ARIA CODEMAPS` lines; classify the transcript's hook records. Expected: one `hook_system_message` with nags only; `hook_additional_context` holds the value lines.
- [ ] **Step 6:** Commit `docs: point references at the single SessionStart emitter`; then run Gate D.
