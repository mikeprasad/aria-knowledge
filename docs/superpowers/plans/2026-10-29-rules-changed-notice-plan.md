# Plan — rules-changed notice

**Spec:** `docs/superpowers/specs/2026-10-29-rules-changed-notice-spec.md` (amended after /prospect, log `knowledge/logs/prospect/2026-10-29-file-rules-changed-notice-spec.md`).
**Branch:** `changed-rules-notice` (worktree `aria/.wt-crn-aria-knowledge`, cut from `origin/main` `2b073ea`).
**Rules for every task:** every hook invocation sets `HOME` and closes stdin (`</dev/null` or a pipe). Read exit codes bare, never through a pipe. Each new assertion is seen red against the current hook before the fix.

## T0 — Baseline (no edits)

Run and record, each exit code bare:
- `sh tests/repros/session-start-single-emitter.sh </dev/null` → expect 40 passed.
- `sh tests/repros/statusline-session-start.sh </dev/null` → expect exit 0.
- `bash plugin-claude-code/tests/run.sh </dev/null` → expect 532 passed, 0 failed.
- `bash tests/run.sh </dev/null` → expect 54 suites.

## T1 — New repro arms, red first (`tests/repros/session-start-single-emitter.sh`)

Fixture helpers (new): `stale_digest <home>` appends one line to the installed digest; `bump_urules <kf>` appends a new `### U2 —` rule so the rendering changes; `rules_unwritable <home>` replaces `$home/.claude/rules` with a regular file so `mkdir -p` fails. `notice <file>` = the decoded context line beginning `ARIA RULES` (empty if none).

Arms (declared expectation against the CURRENT hook in brackets):
- **AC1** stale digest → startup: context begins with `ARIA RULES REFRESHED`, names `aria-rules.md`; installed digest `cmp`-equal to bundled after the run. [red: no notice]
- **AC2** immediately rerun → no `ARIA RULES` line. [green on old hook — paired with AC1 as its positive]
- **AC3** `bump_urules` → notice names `aria-user-rules.md` and not `aria-rules.md`. [red]
- **AC4** stale digest + `bump_urules` → both named. [red]
- **AC5** fresh home → notice names both installed files; context contains no `- **Rule 1 —` line; context length < 2000 characters. [red: digest body inlined]
- **AC6** `rules_unwritable` → notice `ARIA RULES NOT INSTALLED` names the bundled digest path and the source `user-rules.md`; no `- **Rule 1 —` line. [red]
- **AC7** stale digest → compact: context begins with `ARIA WORKING RULES — still in force after compaction`, and contains the notice. [red]
- **AC8** every new arm: `jq -e .` passes; `systemMessage` never contains `ARIA RULES`.
- Replace line 107's "fallback arm carries the digest" with AC5.

Run → record exactly which assertions are red; they must match the brackets.

## T2 — Implementation (`plugin-claude-code/scripts/session-start-check.sh`)

1. Add `_kt_rules_sum() { if [ -f "$1" ]; then cksum < "$1" 2>/dev/null; else echo absent; fi; }`.
2. Replace the `DIGEST_WAS_PRESENT` capture with `PRE_DIGEST=$(_kt_rules_sum "$INSTALLED_DIGEST")` and `PRE_URULES=$(_kt_rules_sum "$INSTALLED_URULES")`, keeping the ordering comment (capture BEFORE the ensure call) rewritten for the new purpose.
3. After `kt_ensure_rules_files`: if `$INSTALLED_DIGEST` is absent → build the NOT INSTALLED notice naming `$BUNDLED_DIGEST` (and `$SOURCE_URULES` when it exists). Else build the REFRESHED list from each file whose post-sum differs from its pre-sum and which now exists.
4. `MODEL_MESSAGES="${RULES_NOTICE}${CONFIG_LINE}\n"` — delete the steady/fallback `if` and the inline arm. The compact block is still prepended later, so on compact the order is compact block → notice → config.
5. Update the comment at the old line ~448 that refers to the fallback arm.

Notice texts (single lines):
- `ARIA RULES REFRESHED — <path>[ and <path>] changed or were installed at this session's start, after this session loaded its rules, so the copy in your context is the previous version or absent. Read the named file(s) now, before your next tool call, and follow the file wherever the two differ.`
- `ARIA RULES NOT INSTALLED — ~/.claude/rules could not be written, so no ARIA rules file was loaded into this session. Read <bundled digest>[ and <user-rules.md>] now, before your next tool call, and follow them for this session.`

Run T1's arms → all green.

## T3 — Re-point the tests that asserted on the inline arm

- `tests/repros/statusline-session-start.sh`: TASK BUDGET content (`resets_at`, `re-read`, `session_id`, and the absence of "judging whether to keep going") moves from the first run's context to the bundled digest file; add one assertion that the first run's context names `aria-rules.md` in an `ARIA RULES` notice.
- `plugin-claude-code/tests/test-aria-rules-digest.sh`:
  - First block: `Rule 13`, `RULE 22 ORDERING`, structure > 20 lines → assert on `$DIGEST`; assert the first-run context carries the notice. Keep "no U-rule index when user-rules.md is absent" (still true).
  - Arm block: `arm 1 leads with the rules digest` → leads with `ARIA RULES REFRESHED`; LAST rule / standing directive / user's own rules → read the path named in arm 1's notice and assert the named file contains them (keeps the 270-chars-0-rules guard's intent: the session is pointed at a file that holds the rules); config line kept; "arm 2 far smaller than arm 1" → arm 2 has no notice.
  - Worst-case block: block-presence loop and LAST rule → assert on `$DIGEST`; runaway ceiling → keep `ARIA_EMIT_RUNAWAY` as a runaway catch, lowered 40,000 → 4,000 (a reintroduced inline digest is ≥ 23,568 chars and fails loudly), and carry delivery on the begins-with assertion — not a hard ≤ 2,000 ceiling, which would couple the test to the user's config size (plan-gate A1); annotate the suite's history comments as superseded rather than deleting them (A2); "leads with the rules digest" → leads with the notice; **delete** "the delivered prefix reaches the first rule" and its needle setup, with a comment recording why (per-line `cut`, never could fail).
  - Minimal path LAST rule → `$DIGEST`.
- `plugin-claude-code/tests/test-count-backlog-entries.sh:124` and `plugin-claude-code/scripts/lib-user-rules.sh:10-11`: comments only — the inline arm no longer exists and `kt_user_rules_block` has one caller.

## T4 — Gates

All four suites, bare exit codes; real-rules guard green; `plugin-antigravity/build.sh` then `git status` (expect no change — Antigravity does not carry this hook; confirm by the regenerated tree being clean).

## T5 — Mutation checks (each must turn its named arm red, then restore from a byte backup and `cmp`)

- M1 notice never emitted → AC1, AC3, AC4, AC5, AC6, AC7 red.
- M2 pre-sum taken AFTER the ensure call → AC1, AC3, AC4 red (AC5 stays green only if absent→written is still caught — record which).
- M3 notice appended after the config line instead of before → AC1 "begins with" red.
- M4 bundled path dropped from the NOT INSTALLED notice → AC6 red.

## T6 — Docs

CHANGELOG `## Unreleased` entry; spec status → implemented.

## T7 — Commits

1. `test:` arms + re-pointed tests (red against the old hook, recorded in the message).
2. `fix(session-start):` the implementation + comments.
3. `docs:` spec, plan, CHANGELOG.
Stage named paths only. Run Gate D (`check-public-hygiene.sh`) after committing, with an upstream set.
