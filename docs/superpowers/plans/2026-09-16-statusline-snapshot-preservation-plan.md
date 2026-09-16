# Plan — status-line snapshot preservation + doc truth

**Status:** ✅ **GATED 2026-09-16 — gate 2 verdict PROCEED-WITH-CHANGES; all four required changes
applied below in the same edit that records them.**
Spec: `docs/superpowers/specs/2026-09-16-statusline-snapshot-preservation-design.md` (GATED).
Gate 1: `knowledge/logs/prospect/2026-09-16-file-statusline-snapshot-preservation.md`.
Gate 2: `knowledge/logs/prospect/2026-09-16-file-statusline-snapshot-preservation-plan-gate2.md`.
Chain: **S**pec → **P**rospect ✅ → **P**lan ✅ → **P**rospect ✅ → **E**xecute ← *next*.

⭐ **Gate 2's blocking find: T6's mutation M3 named a control that no task created** — so the one
mutation guarding the render/snapshot separation was unfalsifiable. Fixed by **AC4b** in T1.
Also folded: T2's mechanism is now **empirically anchored** (prototyped against 7 inputs during the
gate, moving it ⚠ → ✅); the non-atomic read is **stated, not locked** (F2); `cut` without `-s` is
**resolved as correct** with its reason recorded (F3); T0's trip-wire bound is pinned to the pre-arc
HEAD so it cannot self-match (F5).

**Three commits, in this order.** C1 code+tests (claude-code) · C2 the antigravity mirror ·
C3 doc-only. Per spec D5: one concern per commit, and the doc half must not ride the code half's gate.

---

## T0 — Trip-wire (STOP on any mismatch)

Re-derive, do not trust the spec's numbers — they were measured on 2026-09-16 and peers write this repo.

Set once, and note **why it is a variable rather than a literal**: this repo is **public**, and
`release.sh` Gate D (`check-public-hygiene.sh`) fires fatally on `/Users/<real-account>` in tracked
content — its `HOME_PLACEHOLDERS` allow `you`/`me`/`alice` and nothing else. A literal home path here
would both leak a username and add to that gate.

```sh
ARIA=$(git rev-parse --show-toplevel)   # run from anywhere inside the aria-knowledge checkout
```

```sh
(cd "$ARIA" && sh tests/repros/statusline-usage.sh; echo "bare exit=$?")
```
Expect **`35 pass, 0 fail`**, bare exit **0**.

```sh
(cd "$ARIA" && git log 2a41329..HEAD --oneline -- \
  plugin-claude-code/bin/statusline-meter.sh plugin-antigravity/bin/statusline-meter.sh \
  plugin-claude-code/bin/usage-threshold-inject.sh \
  plugin-claude-code/skills/statusline/SKILL.md plugin-antigravity/skills/statusline/SKILL.md)
```
Expect **empty**. Anything here means a peer moved a target file → re-read before editing.
⭐ **F5 (gate 2): the bound is the pre-arc HEAD `2a41329`, NOT `--since=<today>`.** A date bound
self-matches the moment C1 lands, so re-running the trip-wire mid-arc would flag my own commits as
peer movement. A commit bound cannot drift.

```sh
(cd "$ARIA" && sh plugin-claude-code/bin/check-port-drift.sh \
  | awk '$2=="plugin-antigravity/skills/statusline/SKILL.md"{print $3}')
```
Expect **`ok`** — this is AC11's *isolating* baseline. ⛔ Do **not** record the 23/37 total; it is
non-isolating (spec AC11).

⚠ **Concurrency:** `tests/repros/statusline-usage.sh` writes only under its own `mktemp -d`, so it is
safe to run beside peers. It does **not** touch the real `~/.claude`.

---

## T1 — Assertions FIRST, and they must be red for the right reason

Add to `tests/repros/statusline-usage.sh`. ⛔ **Placement is load-bearing: these must sit in the
meter section, BEFORE the `usage-threshold-inject.sh` section's `snap()` helper (currently ~line
100).** `snap()` rewrites `$SNAP` wholesale; an assertion after it proves nothing — that is exactly
how the existing suite executes this defect at its own line 84 and still reports 35/0.

Fixtures derive from the payload contract the script's own header enumerates
(`.model.display_name`, `.context_window.used_percentage`, `.rate_limits.*`, `.effort.level`,
`.session_id`), cross-checked against `references/claude-code-session-and-hooks.md` — **not** from
this plan's assumption (`test-fixture-mirrors-the-bug`).

New cases, in order:

| AC | Case | Assertion |
|---|---|---|
| AC1 | render FULL (5h 88), then render a payload with **no `rate_limits`** | `$SNAP` still carries `"five_hour_pct": 88` **and** `five_hour_resets_at` |
| AC2 | same | `$SNAP` still carries `seven_day_pct` + `seven_day_resets_at` |
| AC3 | render FULL, then render FULL with 5h **12** | `$SNAP` carries `12` — preservation must not become preserve-always |
| AC4 | render FULL (sid `S-old`), then no-`rate_limits` with sid `S-new` | `session_id` is `S-new`; `written_at`/`model`/`runtime` are the current render's |
| **AC4b** | ⭐ **ADDED at gate 2 (F1) — the blocking find.** render FULL, then no-`rate_limits` | the **rendered status line** carries **no `5h`** and **no `7d`** segment. ⛔ Asserted on the RENDERED OUTPUT, never the snapshot. This is M3's control and the *only* assertion guarding the render/snapshot separation — preserving into the display variables would show a **stale** 5h on a fresh session, the *"a wrong status line is worse than a sparse one"* failure ADR 098 names. Without AC4b, M3 cannot go red and the risk is unguarded. |
| AC5 | render FULL, then a payload with no `context_window` | `context_pct` is **ABSENT** (existing post-`/compact` contract, `tests/repros/statusline-meter.sh:32`) |
| AC6 | fresh `HOME`, no prior snapshot, render FULL | snapshot written, same shape as today |

**Pre-declared expectation for the T1 run:** AC1 and AC2 **RED**; AC3–AC6 **GREEN**.
⛔ If AC1/AC2 come back green, **STOP** — the assertion is not reaching the defect (most likely it
landed after `snap()`), and a green here is the failure mode this whole task exists to avoid.

---

## T2 — Implement the scoped preservation (`plugin-claude-code/bin/statusline-meter.sh`)

⛔ **Snapshot-only variables. Never touch the render path.** `five_i`, `week_i`, `five_reset`,
`week_reset` are consumed by the `5h`/`7d` display segments *above* the snapshot block. Preserving
into them would show a **stale** 5h on a fresh session's first render, which is precisely the
*"a wrong status line is worse than a sparse one"* failure ADR 098 names.

⛔ **Preserve per WINDOW, as a pair — never field-by-field.** If the payload supplies a percentage
but no `resets_at` (a real, tested shape — the suite's `NORST` case), field-wise defaulting would
pair a **fresh percentage with a stale reset**, and `_expired()` in the consumer would then expire
(or fail to expire) the wrong window. Rule: the window's percentage decides; if it is present both
fields come from this render, even when the reset is empty.

Insert immediately after `_at=$(date -u …)` and before the `jq -n` call:

```sh
  # Preserve the ACCOUNT-scoped usage windows when this payload carries none.
  # rate_limits is absent until a session's first API response, so a whole-file
  # rewrite here erases the account's 5h/7d for every concurrent session (spec §1).
  # Render-scoped fields (written_at/model/runtime/session_id/context_pct/account_*)
  # are ALWAYS this render's — see the partition in tests (AC14).
  # Fails soft by construction: absent / empty / truncated / non-JSON prior file -> all
  # four read empty -> today's write-whole behaviour, and the render never aborts (AC13).
  # MEASURED 2026-09-16 against 7 inputs: jq exits 5 and prints NOTHING on the three malformed
  # cases; a well-formed file with no usage keys yields three bare tabs (all four empty); an
  # explicit `"five_hour_pct": null` correctly preserves only the 7d pair.
  # `cut` deliberately has NO -s: the filter emits exactly three tabs or nothing at all, so the
  # tab-free branch where cut would return the whole line is UNREACHABLE. Do not "harden" it.
  # NOT atomic across concurrent sessions, and that is accepted: if a peer writes a fresher value
  # between this read and this write, usage goes stale by at most one render (refreshInterval 30s).
  # That is strictly better than the pre-fix behaviour, where the same interleave ERASED it.
  # Do not add locking.
  _prev=$(jq -r '[(.five_hour_pct//""),(.five_hour_resets_at//""),(.seven_day_pct//""),(.seven_day_resets_at//"")]|@tsv' "$_state" 2>/dev/null)
  _snap_five="$five_i"; _snap_five_reset="$five_reset"
  _snap_week="$week_i"; _snap_week_reset="$week_reset"
  if [ -z "$_snap_five" ]; then
    _snap_five=$(printf '%s' "$_prev" | cut -f1)
    _snap_five_reset=$(printf '%s' "$_prev" | cut -f2)
  fi
  if [ -z "$_snap_week" ]; then
    _snap_week=$(printf '%s' "$_prev" | cut -f3)
    _snap_week_reset=$(printf '%s' "$_prev" | cut -f4)
  fi
```

Then change **only** the four `--arg` values (the jq filter body is untouched — a preserved value is
non-empty, so the existing conditional-omit logic already does the right thing):

- `--arg five "$five_i"` → `--arg five "$_snap_five"`
- `--arg five_reset "$five_reset"` → `--arg five_reset "$_snap_five_reset"`
- `--arg seven "$week_i"` → `--arg seven "$_snap_week"`
- `--arg seven_reset "$week_reset"` → `--arg seven_reset "$_snap_week_reset"`

**Cost:** one extra `jq` spawn per render (~3 ms), on a script that already runs `jq` 7 times.

**Pre-declared:** AC1/AC2 flip to GREEN; AC3–AC6 stay GREEN; the full suite stays bare exit 0.

---

## T3 — AC13: the new read must tolerate a file peers write concurrently

Four fixtures against `$SNAP` before a no-`rate_limits` render: **absent** · **empty file** ·
**truncated JSON** (`{"five_hour_pct":`) · **non-JSON** (`not json`). Each must produce a written
snapshot and a rendered line, with exit 0 — degrading to write-whole.

**Red-ability:** proven by M5 below, not asserted. Without a mutation these four can pass
vacuously.

---

## T4 — AC14: the partition guard, compared against a HAND-WRITTEN LITERAL

Assert that the union of the two partitions equals the set of keys the meter can emit, where the
expected set is a **literal list in the test**, not derived from the script:

```
written_at model runtime session_id account_email account_uuid
context_pct five_hour_pct five_hour_resets_at seven_day_pct seven_day_resets_at
```

Render-scoped: `written_at model runtime session_id account_email account_uuid context_pct`
(`account_email` is render-scoped per spec OQ2 — resolver-derived, present on every jq-path render).
Account-scoped: `five_hour_pct five_hour_resets_at seven_day_pct seven_day_resets_at`.

⛔ **The guard must NOT iterate the partition constant** — `guard-scoped-to-the-wrong-unit`'s
2026-08-28 cue: a control whose parameter source *is* the mutation target cannot see a field being
dropped from it; the mutation shortens the test instead of failing it. Compare a jq-extracted key
set from a real full-payload render against the hand-written literal, both directions.

---

## T5 — AC8: the outcome criterion

One sequenced case: seed the account's snapshot over threshold → render a **fresh session's** first
payload (no `rate_limits`, new `session_id`) → run `usage-threshold-inject.sh` with that session id
and the real threshold config → **expect the 5-hour alert**.

Today this is RED (measured 2026-09-09: healthy snapshot emits `5-hour plan usage at 91%`, erased
snapshot is silent). It is the only criterion that fails for the user-visible reason.

⚠ `KT_CONFIG` must be supplied, exactly as the suite's existing inject cases do — with no config
file the threshold resolves empty and the hook exits silently (spec D3), which would make this case
pass-by-silence in the wrong direction.

---

## T6 — Mutations (each pre-declared with the ONE control that must catch it)

Restore from a **byte backup** + `cmp` after each, and clear `__pycache__`-equivalent staleness
(n/a for `sh`). Never `git checkout --` (discards uncommitted work on a shared tree).

| # | Mutation | Named control that MUST redden | Expected |
|---|---|---|---|
| M1 | drop the `if [ -z "$_snap_five" ]` preservation | AC1 (five-hour arm) **only** | RED |
| M2 | preserve field-by-field instead of per-window | the AC1 mismatched-pair arm | RED |
| M3 | preserve into `five_i` (the render var) instead of `_snap_five` | **AC4b** (T1) — the rendered line carries no `5h`/`7d` on a no-`rate_limits` render. ⭐ Gate 2 caught that this control did not exist; AC4b creates it | RED |
| M4 | delete one field from the partition literal's account-scoped list | AC14 | RED — ⛔ if this *shortens* the test instead, the guard is iterating its own source and T4 is wrong |
| M5 | remove `2>/dev/null` from the `_prev` read | AC13's non-JSON fixture | RED |
| M6 | make preservation unconditional (preserve even when the payload has a value) | AC3 | RED |

⛔ **M3 and M4 are the two that would be skipped and are the two that matter.** M3 guards the
render/snapshot separation that no other assertion covers; M4 is the only proof the completeness
guard can fail at all.

---

## T7 — AC7: STOP-ON-FAIL gate BEFORE the antigravity mirror

Per gate 1, this is a gate, not a checkbox (`theory-driven-mechanism-without-empirical-confirmation`).

1. `mkdir -p "$FAKE/.gemini/antigravity"` — ⛔ **mandatory**: the port's script has no `mkdir`, so
   without it `jq > "$_tmp"` fails, `mv` is skipped, and **no snapshot is written at all**
   (spec §6 trap 7). A harness missing this "passes" AC1 by writing nothing.
2. **Positive control first:** render WITH `rate_limits` → assert the snapshot **exists** and carries
   `five_hour_pct`. If this fails, the harness is wrong, not the port.
3. Then reproduce AC1 against the port: FULL, then no-`rate_limits` → expect `five_hour_pct`
   **ERASED** (i.e. the defect confirmed).

⛔ **If step 3 does NOT reproduce, STOP and reassess** — H2 (the port shares the defect) is
structural inference from a 16-line path-only diff, and a non-reproduction means the inference is
wrong, not that the port is fine.

---

## T8 — Mirror to `plugin-antigravity/bin/statusline-meter.sh` → C2

Same edit, path-substituted. Re-run T7's step 3 → now GREEN. **No `PORT-LEDGER` touch** — 0 `bin/`
files are tracked on any of the 5 ports (measured).

---

## T9 — Doc corrections → C3 (doc-only, separate commit)

1. `plugin-claude-code/bin/usage-threshold-inject.sh` docstring — the threshold is 80 **once
   aria-knowledge is configured**; with no config file injection is dormant (on-demand reading still
   works). Basis: 29/29 self-defaulting assignments live inside `config.sh`'s `if [ -f "$KT_CONFIG" ]`
   block; **zero** outside. ⛔ The code does **not** change (spec D3).
2. Both `skills/statusline/SKILL.md` — same correction to *"default 80%, configurable in `/setup`"*.
3. Both `skills/statusline/SKILL.md` example line — replace
   `5h 24% ↺01:00 │ 7d 88%` with the format the code emits and the suite already pins
   (`↺1pm`, `↺Tue 1pm` at `statusline-usage.sh:73,75`): `5h 24% ↺1pm │ 7d 88% ↺Tue 1pm`.

⚠ Triage recorded at gate 1: items 1–2 are tier-2 (the claim misleads about whether a budget alert
is armed); item 3 is tier-3 cosmetic. All ship because Mike enumerated them; item 3 can be dropped
without reopening the arc.

---

## T10 — AC11 (isolating form only)

```sh
(cd "$ARIA" && sh plugin-claude-code/bin/check-port-drift.sh \
  | awk '$2=="plugin-antigravity/skills/statusline/SKILL.md"{print $3}')
(cd "$ARIA" && sh plugin-claude-code/bin/check-port-drift.sh --quiet >/dev/null 2>&1; echo "quiet exit=$?")
```
Expect that one row `ok → drifted`, and `--quiet` still **0**. ⛔ Do **not** re-baseline
(`--update antigravity` re-stamps all 37 surfaces and `last_parity_pass`, laundering the 23
pre-existing drifts and asserting a parity pass that never happened — spec D4).

---

## T11 — Close

Full `tests/repros/statusline-usage.sh` bare exit 0, count = 35 + assertions added (state the
arithmetic). Then `/preflight file` on the changed set. Then `/retrospect range <C1^>..<C3>`.

⛔ **Not pushed, not released.** aria-knowledge is a public plugin; a release is its own ceremony
(version bump + CHANGELOG + `gh release create` + port re-baseline decisions) and is **not** in this
plan's scope. The installed copy at `~/.claude/aria-statusline-meter.sh` is a **copy** — it does not
change until the user re-runs `/statusline`, which is the documented refresh step and is Mike's call.

---

## Traps carried from the spec (do not re-derive)

1. Assertions after `snap()` prove nothing — the suite already executes this defect and reports 35/0.
2. `jq -n` always succeeds, so `if jq -n …; then mv` is **not** a guard.
3. The status line does not render in the desktop app — verify via the fake-`HOME` harness, never an
   observed terminal.
4. `find -name statusline-meter.sh` returns **three** hits; one is a test file. Ports are **two**.
5. `PORT-LEDGER.json`'s `claude-code` entry has `surfaces: {}` — that is canonical, not untracked.
6. The antigravity port never creates its own state directory (see T7 step 1).
