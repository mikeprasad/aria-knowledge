# Plan — 2.57.8: rules-writer version guard (I-2) · consume_active expected token (I-4) · release worktree copy-out (I-5)

**Spec:** `docs/superpowers/specs/2026-11-07-rules-writer-version-guard-and-consume-expected-token-spec.md` (revision 2)
**Spec prospect:** `knowledge/logs/prospect/2026-11-07-file-rules-writer-guard-consume-token-release-worktree.md`
**Worktree:** `../.wt-2578-aria-knowledge`, branch `release/2.57.8`, cut from `origin/main` = `478fe4e`
before the first commit (shared-tree ancestry rule).
**Push and release need the maintainer's go — this plan stops before both.**

Symbols named below were grep-checked against `478fe4e` (U11): `kt_ss_ledger_consume_active`,
`kt_ss_read_active_token`, `kt_ss_read_live_prompt`, `kt_ss_ledger_add`, `kt_ss_ledger_mark_consumed`,
`kt_ss_ledger_token_locate`, `kt_ensure_rules_files`, `_kt_rules_sum`, `emit`, `kt_user_rules_block`,
`RULES_NOTICE`; `plugin-antigravity/build.sh` copies `rules/*.md` (line 183) and canonical scripts
into `bin/` (line 244).

## T0 — Baseline

Run `tests/run.sh` and `plugin-claude-code/tests/run.sh` in the worktree with stdin closed; record
suite counts and bare exits. Every later comparison is by suite name against this baseline.

## T0b — Generators on the clean tree (added by the plan prospect)

Run `plugin-antigravity/build.sh` and `python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`
before any edit; expect `git status` to show no change. Any change found here is pre-existing drift
and is committed separately (or reported), never absorbed into a fix commit.

## T1 — I-4 tests first (RED)

Added by the plan prospect — **block X, behavioural parity across all four libs** (`_Q_LIBS`
pattern from block Q, not byte parity, which block Q rules out): for each port's
`lib-session-state.sh`, source it in a subshell and run W1 (mismatch → exit 2, byte-identical) and
W5 (match → exit 0, consumed). Declared on `478fe4e`: W1 fails in all four, W5 passes in all four.

`tests/repros/session-state.sh`, new block W after V:
- W1 (B1) slot token B, call with A → exit 2, `cmp` byte-identical.
- W2 (B2) no token argument → exit 1, byte-identical.
- W3 (B4) slot prose quotes A, first token line B, call with A → exit 2, byte-identical.
- W4 (B5) in-progress marker, empty fence, absent file — each with a token → exit 2, byte-identical.
- W5 (B3) slot A, call with `aria-handoff: p/A-sid@A-at` (prefix form) → exit 0, consumed.
- V1/V2/V5 updated to pass the token; V1 also asserts exit 0.

**Declared expectation on `478fe4e`'s lib:** W1, W2, W3 fail because the function consumes and exits 0
(the defect); W4 fails on exit code only (byte-identical already holds); W5 passes already (it ignores
the argument), so it is a positive guard, not landing evidence. Record the actual result.

## T2 — I-4 implementation

Canonical `plugin-claude-code/scripts/lib-session-state.sh`:
1. `<token>` = `$4`; strip optional `aria-handoff:` prefix and leading spaces; take what follows the
   first `/`; split at the first `@`; trim. Empty sid or at → stderr + `return 1`.
2. Read the slot's token with `kt_ss_read_active_token`; if empty or `≠ sid|at` → stderr naming
   expected and found (`(none)` when empty) + `return 2`. This also covers no file / empty slot /
   marker / empty fence, since those have no token line.
3. Body from `kt_ss_read_live_prompt`; empty → `return 2` (defensive; unreachable after step 2 unless
   the token line sits outside a live body).
4. Demote with the parsed sid/at (no longer the front-matter fallback); demote check failure → `return 3`.
5. `mark_consumed` with the at.
6. Clear: the awk is given `esid`/`eat`; it tracks the first `aria-handoff:` line in the ACTIVE
   section; at END, if that token ≠ expected, `exit 3` and the shell skips `mv`, returning 2.
7. Comment block above the function records the contract (exit codes, why required, the residual).

Then copy the function verbatim into `plugin-openai-codex/bin/lib-session-state.sh` and
`plugin-cursor-template/scripts/aria/lib-session-state.sh` (they were byte-identical before; assert
identical after with the same `sed -n '/^kt_ss_ledger_consume_active/,/^}/p'` diff), and regenerate
Antigravity with `plugin-antigravity/build.sh`. GREEN: block W + V.

## T3 — I-4 directive text (B6)

Replace the `'|active' takes kt_ss_ledger_consume_active …` clause in:
`plugin-claude-code/rules/aria-rules.md`, `plugin-openai-codex/bin/session-start-check.sh:292`,
`plugin-cursor-template/scripts/aria/session-start-check.sh:312` (keeping each port's
`<your session id, or 'codex'/'cursor' …>` wording), and Antigravity via `build.sh`. New clause adds
`<the same token>` as the fourth argument and: *it refuses (non-zero) when the active slot no longer
holds that token — a peer wrote or moved a prompt after you located it; then re-run
kt_ss_ledger_token_locate with the same token and act on the new result, and never consume whatever
is now active.*

Tests: `tests/repros/session-state-token-directive.sh` gains two `chk` lines (fourth argument; the
refusal instruction) on the Claude Code digest, plus the same two needles section-scoped to the
SESSION STATE string in the Codex and Cursor hooks and in the regenerated Antigravity digest. Seen RED
before the text change.

⚠ Digest size: re-run `plugin-claude-code/tests/test-aria-rules-digest.sh` — it carries a ratchet on
the delivered payload; if the clause trips it, shorten the clause, do not raise the ratchet silently.

## T4 — I-2 tests first (RED)

`tests/repros/session-start-single-emitter.sh`, new arms VG1–VG8 (fake `HOME`, stdin closed, the
existing harness): A1 newer-stamped digest kept + NOT REFRESHED line + no REFRESHED; A2 same for
U-rules; A3 older stamp replaced + REFRESHED; A4 unstamped replaced and stamped; A5 absent written and
stamped, no NOT REFRESHED; A6 stamp-only difference → stamp updated, no REFRESHED; A7 newer stamp,
identical body → no NOT REFRESHED; A8 `2.57.10` beats `2.57.9` (fixture stamps `2.57.10` against a
fake plugin version — use a copy of the scripts dir with a modified `plugin.json` so the real one is
untouched). **Declared expectation on `478fe4e`:** A1, A2, A3's stamp assertion, A4, A5's stamp, A6,
A8 fail; A7 passes vacuously (no stamp logic) — labelled a non-regression guard.

## T5 — I-2 implementation

`session-start-check.sh`:
- `KT_SELF_VERSION` from `$SCRIPT_DIR/../.claude-plugin/plugin.json` (grep/sed, first `"version"`).
- `kt_stamp_of <file>` → version from line 1 if it matches `<!-- aria-knowledge X -->`, else empty.
- `kt_version_newer A B` → 0 if A > B numerically per dot field (non-digits stripped per field; empty
  either side → 1).
- Digest arm: render `stamp + bundled` to a temp in `$RULES_DIR` (name not ending `.md`); identical →
  drop temp; installed exists and its stamp is newer than mine → drop temp, record the file in
  `KT_RULES_HELD`; else `mv`.
- U-rules arm: stamp line before the existing header, same three-way outcome.
- `_kt_rules_sum` drops a leading stamp line before `cksum` (D6a).
- `RULES_NOTICE`: when `KT_RULES_HELD` is non-empty, the NOT REFRESHED line (D5). Only "would have
  changed" files are recorded, because identical renders are dropped first.
- Update the two D6b byte-compare tests to: line 1 = stamp naming the plugin version; lines 2..N
  `cmp`-identical to the bundled file.
- `plugin-claude-code/skills/setup/SKILL.md` Step 7ea and `/setup`'s wording that describes the
  writer: add one sentence on the stamp and the newer-version hold (plus the Antigravity/Codex copies
  of that sentence via their generators / by hand where the setup skill is hand-synced).

GREEN: VG1–VG8 + both updated tests + the real-rules guard.

## T6 — I-5 (RED then GREEN)

`tests/repros/release-worktree-finish.sh` (hermetic, `mktemp -d` repo with an ignored `*.zip` rule):
C1 control — plain `git worktree remove` deletes the ignored zip (must PASS on any code: proves the
test sees the loss); C2 helper copies byte-identical and removes the worktree; C3 unwritable
destination → non-zero, worktree + zip remain; C4 no artifacts → non-zero, worktree stays,
`--no-artifacts` removes; C5 main checkout as argument → refused. **Expectation before the helper
exists:** C1 passes, C2–C5 fail on "helper not found". (Weak RED by construction — the helper is new;
the load-bearing RED is C1, which shows the loss the helper prevents.)

`release-worktree-finish.sh` at the repo root, per spec D11. `RELEASING.md`: new section "Releasing
from a worktree" with ordered steps, ending: copy out and verify with the helper, *then* removal;
never `git worktree remove --force` a release worktree.

C6 live: `git worktree add` a scratch worktree of this repo at the release branch tip, run
`./release.sh` there, record the built zip checksums, run the helper, assert the worktree is gone
and each zip exists in the main checkout with the recorded checksum. Must run before the final
release build (it writes the same 2.57.8 names into the main checkout).

## T7 — Full verification

Bare exits, stdin closed: `tests/run.sh`, `plugin-claude-code/tests/run.sh`,
`plugin-openai-codex/tests/run.sh`, `plugin-antigravity/tests/` runner,
`tests/repros/port-generation-idempotence.sh`; `python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`
then `git status` (expect no `.mdc` change unless the setup sentence reaches it); Gate D
(`check-public-hygiene.sh`) AFTER committing; compare suite names against T0.

## T8 — Release prep (local only)

Version 2.57.8 in the five manifest files the 2.57.7 release commit touched
(`plugin-claude-code/.claude-plugin/plugin.json`, `plugin-antigravity/plugin.json`,
`plugin-antigravity/version.txt`, `plugin-openai-codex/.codex-plugin/plugin.json` → `2.57.8-codex.0`,
`plugin-cursor-template/scripts/aria/VERSION` → `2.57.8-cursor.0`); CHANGELOG `## 2.57.8`;
`PORT-LEDGER.json` re-baselined for each touched port after `check-port-drift.sh` shows only the
expected surfaces; build with `./release.sh`, `./release-antigravity.sh`, `./release-codex.sh`,
`./release-cursor.sh` (Cowork untouched — no Cowork surface changed); commit with explicit paths;
`/retrospect range 478fe4e..HEAD`; aria-knowledge `CLAUDE.md` footer + version lines. Merge to `main`
fast-forward, then remove this worktree with the new helper. **Stop: push, tag, `gh release create`,
`publish-release.sh --apply` wait for the go.**

## Order and checkpoints

T0 → T1 (record RED) → T2 (GREEN) → T3 → T4 (record RED) → T5 (GREEN) → T6 → T7 → T8. Each task
commits separately so any one reverts alone.
