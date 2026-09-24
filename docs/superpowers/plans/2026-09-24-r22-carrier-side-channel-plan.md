# Plan — Rule 22 carrier side channel (SPPPE gate 3)

**Spec:** `docs/superpowers/specs/2026-09-24-r22-carrier-side-channel-spec.md` (prospected: `knowledge/logs/prospect/2026-09-24-file-r22-carrier-side-channel-spec.md`, PROCEED-WITH-CHANGES, all four changes applied). **Version:** 2.54.0 (new mechanism + new hook registration ⇒ minor). **Stops at:** local commit — no push, no release, no install (install = Mike; auto mode blocks self-modifying the governing hook).

**Gate 4 changes (applied — `knowledge/logs/prospect/2026-09-24-file-r22-carrier-side-channel-plan.md`):**
- **A.** `plugin-antigravity/build.sh` copies every `bin/*.sh` except a skip list. Add `pre-bash-r22-carrier.sh` to that list (antigravity registers no recorder; shipping it would repeat the dead-file class the 2026-08-26 comment removed). Done in T6 before regenerating.
- **B.** Recorder and consumer hand `$INPUT` to python with `printf '%s' "$INPUT"`, never `echo` (`tests/repros/hook-json-extraction.sh`: POSIX `echo` mangles escapes and a guard fails open silently).

## T1 — Tests first: `tests/repros/r22-carrier-side-channel.sh`
TMPDIR-isolated, hook stdin fixtures copy the docs' field names verbatim (`session_id`, `prompt_id`, `transcript_path`, `tool_name`, `tool_input`, `tool_use_id`, `agent_id`). Transcript fixtures reuse `tests/fixtures/transcript-cc21280-real-base.jsonl`.
- **Recorder:** C1 line-start carrier in `command` → state file with the prompt_id · C2 mid-line mention → no file · C3 no marker → no file · C4 `agent_id` → agent-scoped file name · C11 garbage stdin / any input → empty stdout, exit 0.
- **Consumer:** C5 state + matching prompt_id + target line ABSENT from transcript (cap 5000 ms) → allow in < 2 s (proves no transcript dependency) · C6 second edit, same prompt, no new carrier, no-marker transcript → deny (ADR 062) · C7 prompt_id mismatch → deny + state file removed · C8 carrier under agent X, edit on main thread → deny, agent X file untouched · C9 carrier in session A, edit in session B → deny · C10 edit input without prompt_id, state present → deny + state removed.
- **Fallback:** W1 text-marker transcript whose target line is appended at +2.5 s, env UNSET → allow (default > 1.5 s).
- **Registration (structural, jq):** R1 `pre-bash-r22-carrier.sh` registered under `PreToolUse` `Bash` · R2 `pre-edit-check.sh` timeout = 45 · R3 default cap in the hook < timeout×1000.
Run against the current code; declare expected reds first: C1–C11 red (no recorder / no consumer) except C2/C3/C6/C8/C9 which pass vacuously today (deny paths) — note which; W1, R1–R3 red.

## T2 — Recorder `plugin-claude-code/bin/pre-bash-r22-carrier.sh`
POSIX sh. `INPUT=$(cat)`; fast path `case "$INPUT" in *'[Rule 22'*) ;; *) exit 0 ;; esac`; then python3 json parse; anchored regex on every string in `tool_input`; key = sanitised `session_id` (fallback transcript basename) + `.agent-<sanitised agent_id>` when present; write `{prompt_id, tool_use_id, recorded_at}` to `${TMPDIR:-/tmp}/aria-r22-carrier-<key>.tmp` then `mv`. All errors → silent exit 0. Register in `plugin.json` as a 4th entry under the existing `PreToolUse` `Bash` matcher, timeout 5.

## T3 — Consumer in `plugin-claude-code/bin/pre-edit-check.sh`
Claude Code branch only (`STEP_INDEX` empty). After the existing `SESSION_KEY` block: python3 json parse of `$INPUT` for `prompt_id` / `agent_id` (json, not grep — `agent_id`'s position in the object is undocumented and an Edit's own content could contain the literal); build the same key; if the state file exists read its `prompt_id`, `rm -f` it, and set `COMPLIANT="yes"` iff both prompt ids are non-empty and equal. Guard the transcript detector with `if [ "$COMPLIANT" != "yes" ]`. Raise the default wait `"1500"` → `"40000"` (both the default string and the ValueError fallback). `plugin.json`: the pre-edit entry's `"timeout": 5` → `45` (anchor on the `pre-edit-check.sh` command line — `"timeout": 5` occurs 13×).

## T4 — Existing suites
Time each of the 6 suites that invoke the hook before and after T3. Only where runtime grows (expected: `4-8-thinking-and-failopen.sh` case E), add `export ARIA_R22_FLUSH_WAIT_MS=${ARIA_R22_FLUSH_WAIT_MS:-300}` with a comment. Do not edit suites whose runtime is unchanged.

## T5 — Docs (same wording in all four)
Deny message, `rules/aria-rules.md` RULE 22 ORDERING, `bin/session-start-check.sh`, `template/rules/change-decision-framework.md` "Second channel": the heredoc carrier is now recorded when the Bash call runs (instant, transcript-independent); visible text still counts but may wait for the response to be written; Bash-less agents use visible text.

## T6 — Verify
Mutations (restore by byte backup + `cmp`), each with its named control: drop prompt equality → C7 · drop `rm` → C6 · drop agent key → C8 · recorder unanchored → C2 · recorder writes without marker → C3 · default wait back to 1500 → W1 · timeout not raised → R2 · consumer guard removed (always run transcript) → C5. Old-hook run of the final suite: fails exactly the predicted set. Full `tests/run.sh` + `plugin-claude-code/tests/run.sh` bare exit 0; `plugin-antigravity/build.sh` then port idempotence; gate D after staging.

## T7 — Release prep (local)
CHANGELOG 2.54.0; version in both manifests; `check-port-drift.sh --update antigravity` + `--update claude-code`; `/preflight`; commit by explicit path. Then ask Mike: push + release + install + `/reload-plugins` → AC9 live.
