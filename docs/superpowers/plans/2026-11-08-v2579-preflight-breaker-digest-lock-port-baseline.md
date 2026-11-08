# Plan — v2.57.9

**Spec:** `docs/superpowers/specs/2026-11-08-v2579-preflight-breaker-digest-lock-port-baseline-spec.md`
(prospected, amended, `a0518ce`). **Worktree:** `../.wt-2.57.9-aria-knowledge`, branch `release/2.57.9`
from `origin/main` `fd79fb9`. **Stop line:** everything here is local. Merge to `main`, push, GH
release and the cowork 1.8.2 call are Mike's.

Paths are relative to the worktree root. `PCC` = `plugin-claude-code`.

Ordering rule: every test is written and **seen red** before the change it guards; every mutation
names the arm that must redden, and that arm exists at that point in the sequence.

---

## T0 — Baseline (no edits)

1. `sh tests/run.sh; echo "exit=$?"` and `sh PCC/tests/run.sh; echo "exit=$?"`, each captured to a
   file in the session scratchpad, bare exit read on its own line. Record suite and assertion counts.
2. `sh plugin-openai-codex/tests/run.sh; echo "exit=$?"`; antigravity tests if a runner exists.
3. Generators on the clean tree, so later diffs cannot absorb pre-existing drift (2026-10-22 lesson):
   `./plugin-antigravity/build.sh` and `python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`,
   then `git status --short`. Expected: no change. If anything changes, stop and commit that drift
   separately before T1, naming it as pre-existing.
4. Note: a parallel session is live in the MAIN checkout, not this worktree. Timing arm H3 can still
   flake under machine load; a single H3 failure is re-run alone before being treated as real.

## T1 — Breaker test, all four hooks (RED first)

Append block `[10c]` to `PCC/tests/test-preflight-gate.sh`, after `[10b]`:

```sh
# [10c] a COMPLIANT commit resets the breaker (v2.57.9). Contract: "three consecutive denials
# with no compliant commit between them". Before 2.57.9 nothing removed the counter, so after a
# preflight the stale count survived; if the marker was later lost (TMPDIR cleanup), the gate
# degraded after ONE denial. Driven against every port's hook — they share one input contract.
# (Red-before-fix signature, measured on all four: DENY DENY | SILENT | DENY DEGRADED.)
PF_REPO_ROOT="$(cd "$ROOT/.." && pwd)"
pf_run_h() { # HOOK CFG SID COMMAND
  printf '{"session_id":"%s","tool_input":{"command":"%s"}}' "$3" "$4" \
    | KT_CONFIG="$2" sh "$1" 2>/dev/null
}
for pf_h in plugin-claude-code/scripts plugin-antigravity/bin plugin-openai-codex/bin plugin-cursor-template/scripts/aria; do
  pf_hook="$PF_REPO_ROOT/$pf_h/pre-commit-preflight-check.sh"
  pf_sid="pfreset-$(printf '%s' "$pf_h" | cksum | cut -d' ' -f1)"
  pf_fresh "$pf_sid"
  pf_run_h "$pf_hook" "$CFG_DENY" "$pf_sid" "cd $PF_CODE && git commit -m x" >/dev/null   # deny 1
  pf_run_h "$pf_hook" "$CFG_DENY" "$pf_sid" "cd $PF_CODE && git commit -m x" >/dev/null   # deny 2
  printf 't\tSKIP\tfixture\n' > "${TMPDIR:-/tmp}/aria-preflight-$pf_sid"
  out=$(pf_run_h "$pf_hook" "$CFG_DENY" "$pf_sid" "cd $PF_CODE && git commit -m x")      # compliant
  assert_eq "breaker reset [$pf_h]: compliant commit is allowed" "0" "$(pf_has '"deny"' "$out")"
  rm -f "${TMPDIR:-/tmp}/aria-preflight-$pf_sid"                                          # marker lost
  r1=$(pf_run_h "$pf_hook" "$CFG_DENY" "$pf_sid" "cd $PF_CODE && git commit -m x")
  r2=$(pf_run_h "$pf_hook" "$CFG_DENY" "$pf_sid" "cd $PF_CODE && git commit -m x")
  r3=$(pf_run_h "$pf_hook" "$CFG_DENY" "$pf_sid" "cd $PF_CODE && git commit -m x")
  r4=$(pf_run_h "$pf_hook" "$CFG_DENY" "$pf_sid" "cd $PF_CODE && git commit -m x")
  assert_eq "breaker reset [$pf_h]: 3 denials after a compliant commit all deny" "1 1 1" \
    "$(pf_has '"deny"' "$r1") $(pf_has '"deny"' "$r2") $(pf_has '"deny"' "$r3")"
  assert_eq "breaker reset [$pf_h]: the 4th degrades" "1" "$(pf_has 'DEGRADED' "$r4")"
  pf_fresh "$pf_sid"
done

# [10d] codex only: its per-repo marker is a SECOND compliant exit and must reset too.
pf_hook="$PF_REPO_ROOT/plugin-openai-codex/bin/pre-commit-preflight-check.sh"; pf_sid=pfresetrepo
pf_fresh "$pf_sid"
pf_top=$(git -C "$PF_CODE" rev-parse --show-toplevel)
pf_rm="${TMPDIR:-/tmp}/aria-preflight-repo-$(printf '%s' "$pf_top" | cksum | cut -d' ' -f1)"
assert_eq "codex repo marker absent before [10d] (non-vacuity)" "no" "$([ -e "$pf_rm" ] && echo yes || echo no)"
pf_run_h "$pf_hook" "$CFG_DENY" "$pf_sid" "cd $PF_CODE && git commit -m x" >/dev/null
pf_run_h "$pf_hook" "$CFG_DENY" "$pf_sid" "cd $PF_CODE && git commit -m x" >/dev/null
printf 't\tSKIP\tfixture\n' > "$pf_rm"
out=$(pf_run_h "$pf_hook" "$CFG_DENY" "$pf_sid" "cd $PF_CODE && git commit -m x")
assert_eq "codex repo-marker commit is allowed" "0" "$(pf_has '"deny"' "$out")"
rm -f "$pf_rm"
r1=$(pf_run_h "$pf_hook" "$CFG_DENY" "$pf_sid" "cd $PF_CODE && git commit -m x")
r2=$(pf_run_h "$pf_hook" "$CFG_DENY" "$pf_sid" "cd $PF_CODE && git commit -m x")
r3=$(pf_run_h "$pf_hook" "$CFG_DENY" "$pf_sid" "cd $PF_CODE && git commit -m x")
assert_eq "codex repo-marker reset: 3 denials after it all deny" "1 1 1" \
  "$(pf_has '"deny"' "$r1") $(pf_has '"deny"' "$r2") $(pf_has '"deny"' "$r3")"
pf_fresh "$pf_sid"
```

Notes: `CFG_DENY` and `PF_CODE` are defined earlier in the file (block [10] and setup). Check that
`pf_fresh` also removes an agent-suffixed breaker; these sids carry no `agent_id`, so none is
written. Confirm `pf_run`'s quoting matches `pf_run_h` exactly (copy it).

**Expected RED:** the "3 denials … all deny" assertion fails on all four `[10c]` arms with
`1 0 …`-shaped output (the 2nd degrades), and `[10d]` fails the same way. The compliant-commit and
4th-degrades assertions pass on old code. Record the exact failing lines.

## T2 — Canonical fix

`PCC/scripts/pre-commit-preflight-check.sh`: move these two lines from the deny block (≈193) to
immediately before `MARKER=` (≈121):

```sh
[ -f "$SCRIPT_DIR/lib-state-key.sh" ] && . "$SCRIPT_DIR/lib-state-key.sh"
BREAKER="${TMPDIR:-/tmp}/aria-preflight-denies-$SESSION_ID$(kt_agent_suffix "$INPUT" 2>/dev/null)"
```

and change line 125 to:

```sh
# A compliant commit resets this agent's breaker: the contract is three CONSECUTIVE denials
# with no compliant commit between them (v2.57.9; before, nothing removed the counter).
[ -s "$MARKER" ] && { rm -f "$BREAKER" 2>/dev/null; exit 0; }
```

Leave the breaker comment block where it is; delete only the moved lines. Confirm `SCRIPT_DIR` is
defined above line 121 (grep). **Green:** canonical `[10c]` arm passes; others still red.

## T3 — Antigravity (regenerate)

`./plugin-antigravity/build.sh`. Then `diff <(sed 's#scripts/#bin/#g' PCC/scripts/pre-commit-preflight-check.sh)
plugin-antigravity/bin/pre-commit-preflight-check.sh` → identical. **That `diff` is the instrument for
the hook.** **Green:** antigravity arm. (Plan prospect: `port-generation-idempotence.sh` compares
`skills/template/rules` only, never `bin/`, so it says nothing about this hook. It is run in T7/T11
for the regenerated `rules/`.)

## T4 — Codex (hand-splice, two exits)

`plugin-openai-codex/bin/pre-commit-preflight-check.sh`: same move as T2 (its BREAKER is ≈186; check
it sources `lib-state-key.sh` the same way), then lines 119–120 become:

```sh
[ -s "$MARKER" ] && { rm -f "$BREAKER" 2>/dev/null; exit 0; }
[ -n "$REPO_HASH" ] && [ -s "$REPO_MARKER" ] && { rm -f "$BREAKER" 2>/dev/null; exit 0; }
```

with the same two-line comment. **Green:** codex `[10c]` arm and `[10d]`. Then
`sh plugin-openai-codex/tests/run.sh` → exit 0.

## T5 — Cursor (hand-splice, no agent suffix)

`plugin-cursor-template/scripts/aria/pre-commit-preflight-check.sh`: move
`BREAKER="${TMPDIR:-/tmp}/aria-preflight-denies-$SESSION_ID"` (≈119) above `MARKER=` (≈83); line 84
becomes the `{ rm -f "$BREAKER"; exit 0; }` form with the comment. **Green:** all `[10c]` arms + `[10d]`;
`[10]` and `[10b]` still green.

## T6 — Mutation (per port, prove each arm is load-bearing)

For each of the 4 hooks (and codex's second exit separately): byte-backup to the scratchpad, delete
that `rm -f "$BREAKER"`, run `PCC/tests/run.sh`, confirm **only that port's arm** (or only `[10d]`)
goes red and that the failure is the "3 denials … all deny" assertion. Restore from the backup,
`cmp` against it. Never `git checkout --` (restores from the index).

## T7 — Digest lock

### T7a — test first (RED)

Append to `PCC/tests/test-aria-rules-digest.sh`, after the number-set assertion:

```sh
# --- digest lock (v2.57.9) --------------------------------------------------
# The number-set check above passed a digest whose Rule 23 TEXT had been reverted (measured
# 2026-08-26). The lock binds each digest line to the source rule it summarises, in both
# directions: a source edit without a digest review, or a digest edit/revert alone, goes red
# naming the rule. Refresh with tests/relock-rules-digest.sh <rule#>... — never in bulk.
LOCK="$APM_ROOT/tests/fixtures/aria-rules.digest-lock.tsv"
. "$APM_ROOT/tests/lib-digest-lock.sh"     # kt_dl_source_sha N, kt_dl_digest_sha N
assert_eq "digest lock exists" "yes" "$([ -s "$LOCK" ] && echo yes || echo no)"
lock_nums=$(cut -f1 "$LOCK" 2>/dev/null | sort -n | tr '\n' ',')
assert_eq "digest lock has one entry per source rule" "$src_nums" "$lock_nums"
dl_bad=""
for n in $(cut -f1 "$LOCK" 2>/dev/null); do
  want_s=$(awk -F'\t' -v n="$n" '$1==n{print $2}' "$LOCK"); want_d=$(awk -F'\t' -v n="$n" '$1==n{print $3}' "$LOCK")
  [ "$(kt_dl_source_sha "$SRC" "$n")" = "$want_s" ] || dl_bad="$dl_bad source:$n"
  [ "$(kt_dl_digest_sha "$DIGEST" "$n")" = "$want_d" ] || dl_bad="$dl_bad digest:$n"
done
assert_eq "every digest line matches its locked source rule" "" "$dl_bad"
# An extraction that matched nothing hashes to the sha of empty input; a lock holding that value
# would compare equal to a broken extractor forever.
DL_EMPTY=$(printf '' | shasum -a 256 | cut -c1-64)
assert_eq "no lock field is the empty-input sha" "0" "$(grep -c "$DL_EMPTY" "$LOCK" 2>/dev/null || echo 0)"
```

A failure message names e.g. ` source:7` or ` digest:23`, so the rule and the direction are in the
output.

**Order (plan prospect):** (1) write T7b's `lib-digest-lock.sh` (pure extraction, no lock), (2) add
this test block and run it — **expected RED: "digest lock exists" and "one entry per source rule"
fail, nothing crashes**, (3) write the relock helper, (4) `--init` → green.

### T7b — extraction lib + relock helper

`PCC/tests/lib-digest-lock.sh` (dev-only; `tests/` ships in no artifact):

```sh
# Section of rule N in working-rules.md: from '### N. ' up to the next heading of level 1-3, or EOF.
kt_dl_source_sha() { awk -v n="$2" '
  $0 ~ "^### " n "\\. " {f=1; print; next}
  f && /^#{1,3} / {exit}
  f {print}' "$1" | shasum -a 256 | cut -c1-64; }
# The digest line for rule N: the single line beginning '- **Rule N — '.
kt_dl_digest_sha() { grep -E "^- \\*\\*Rule $2 — " "$1" | shasum -a 256 | cut -c1-64; }
```

⚠ An empty extraction hashes to the sha of empty input (`e3b0c4…`), which would lock silently. The
helper refuses to write that value, and the test adds: no lock field equals the empty-input sha.

`PCC/tests/relock-rules-digest.sh`:
- `--init`: refuses if the lock exists; else writes one line per source rule number.
- `<n> [<n>...]`: replaces only those rules' lines; refuses an unknown number; refuses with no
  arguments ("name the rules you reviewed").
- Refuses to write an empty-input sha (extraction failed).
- Writes to a temp file and `mv`s.

Run `--init`. **Green:** T7a assertions pass.

### T7c — force red, both directions, then the helper's contract

1. Revert Rule 23's digest line to its text at the commit before the 2026-08-26 rewrite
   (`git log -S'One-step test' -- PCC/rules/aria-rules.md` finds it). Byte-backup first. Expect
   `digest:23` only. Restore, `cmp`.
2. Change one word inside rule 7's section of `PCC/template/rules/working-rules.md`. Expect
   `source:7` only. Restore, `cmp`.
3. With the source edit from (2) still in place, `relock-rules-digest.sh 7` → green, and `diff` of the
   lock shows exactly one changed line. Restore source; `relock 7` again → lock byte-identical to
   the T7b lock.
4. `relock-rules-digest.sh` with no arguments → non-zero; `--init` with the lock present → non-zero;
   `relock 99` → non-zero.
5. Point the lib at a missing file → the empty-sha refusal fires (prove the guard can fail).

## T8 — Cowork references

1. `plugin-claude-cowork/skills/audit-knowledge/SKILL.md` lines 834 and 981 →
   `. "${CLAUDE_PLUGIN_ROOT}/scripts/config.sh"` (canonical lines 869/1011, byte-for-byte).
2. `plugin-claude-cowork/skills/audit-config/SKILL.md:164`: `${CLAUDE_PLUGIN_ROOT}/bin/config.sh` →
   `${CLAUDE_PLUGIN_ROOT}/scripts/config.sh`; the sentence after it ("Cowork has no `bin/`") stays true.
3. Check: `grep -rc 'CLAUDE_PLUGIN_ROOT}/bin/' plugin-claude-cowork/skills` totals 0;
   `grep -c '. "${CLAUDE_PLUGIN_ROOT}/scripts/config.sh"' …/audit-knowledge/SKILL.md` = 2.
4. Cowork's own gate: `plugin-claude-cowork/release.sh` description cap is unaffected (body edits);
   run its tests if any exist. No cowork version bump (Mike's call).

## T9 — Versions, docs

0. **Rebase onto local `main` first** (plan prospect). Local `main` holds 3 unpushed `CLAUDE.md`
   footer commits (11b40d9, 2ccc04b, 79f76cf) that this branch lacks; a footer added on the old base
   conflicts at T12. `git rebase main` from the worktree; this branch is only doc + code commits that
   do not touch those lines. Re-run `PCC/tests/run.sh` after. At T12, check `main` again for newer
   peer commits before merging.
1. `PCC/.claude-plugin/plugin.json` → `2.57.9`; `plugin-antigravity/plugin.json` → `2.57.9` (by hand);
   `plugin-openai-codex/.codex-plugin/plugin.json` → `2.57.9-codex.0`;
   `plugin-cursor-template/scripts/aria/VERSION` → `2.57.9-cursor.0`.
2. `./plugin-antigravity/build.sh` (syncs `version.txt`); `python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`
   (expected: no `.mdc` change — no canonical skill changed).
3. `CHANGELOG.md` `## 2.57.9 — 2026-11-08`: the three changes, the two corrected handoff framings,
   the measure-first outcomes, Ports line with the codex/cowork re-baseline justification, Versions.
4. `CLAUDE.md`: current-release lines for Antigravity, Codex, Cursor; a session footer.

## T10 — Ledger (after T9)

`sh PCC/scripts/check-port-drift.sh --update <port>` for all five ports. Then the default report:
no `lag` line for any port, every surface `ok`.

## T11 — Gates and build

1. `sh tests/run.sh` and `sh PCC/tests/run.sh`, bare exits, counts compared with T0 (expected: T0 +
   the new assertions, nothing else moved). Codex suite. `port-generation-idempotence`.
2. Commit by named paths (`git commit -- <paths>`, after checking `git diff --cached` is empty), one
   commit per concern: breaker (4 hooks + test), digest lock (lib, helper, lock, test), cowork refs,
   versions+docs+ledger.
3. Build per RELEASING.md "Releasing from a worktree" step 1: `./release.sh && ./release-antigravity.sh
   && ./release-codex.sh && ./release-cursor.sh`. Gate D reads commit messages because the branch has
   `-b` (2.57.8 lesson).
4. Artifact checks: unzip each to the scratchpad; the new `rm -f "$BREAKER"` line present in each
   port's hook; `digest-lock` absent from every zip (`unzip -l | grep -c digest-lock` = 0, with a
   positive control that `unzip -l` lists the hook).

## T12 — Close

1. `/preflight` (invoked, not inline), then `/retrospect range fd79fb9..HEAD`.
2. Copy artifacts out with `./release-worktree-finish.sh ../.wt-2.57.9-aria-knowledge` **only when Mike
   approves the merge** — until then the worktree holds the build.
3. STOP. Ask Mike: merge `release/2.57.9` into `main` + push + `publish-release.sh`; whether to cut
   cowork 1.8.2 (now carrying its earlier unreleased changes plus T8).
4. After he installs 2.57.9: the retrospect §10 #4 observation (does a still-running 2.57.8 session
   report `ARIA RULES NOT REFRESHED`?).

## Carried, not in this release

- antigravity/codex Scope-line fix (2.54.2) live check: needs a runtime that is not installed here.
- codex `setup` Step 7ea describes the pre-2.57.5 hooks: inert in codex, recorded in the spec.
- the rest of codex's and cursor's preflight behaviour remains untested beyond the breaker sequence.
