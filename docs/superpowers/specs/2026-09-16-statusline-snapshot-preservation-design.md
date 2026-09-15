# Status-line snapshot preservation + doc-vs-code truth — design

**Status:** ✅ **GATED 2026-09-16 — `/prospect` verdict PROCEED-WITH-CHANGES; all required changes
applied below in the same edit that records them.** Gate log:
`knowledge/logs/prospect/2026-09-16-file-statusline-snapshot-preservation.md`.
⭐ The gate's load-bearing change: **D1's hand-maintained field list was falsified by ADR 036**
(cs-builder, Accepted 2026-04-20), which rejected exactly that shape as whack-a-mole. D1 now splits
into a preservation half and a **completeness-guard** half that must ship in the same commit.
Authored 2026-09-16. Chain named by Mike: **S**pec → **P**rospect → **P**lan → **P**rospect → **E**xecute.

---

## 1. The problem, in plain terms

Two unrelated things are wrong with the status-line meter. **Neither produces an error**, which is
why both have been live since June.

**(a) Every new session's first render silently erases the plan-usage numbers.** The meter keeps a
usage snapshot per account so the agent and the alert hook can read it. That snapshot is rewritten
*whole* on every render — and Claude Code does not include `rate_limits` in the payload until a
session's first API response. So the first render of any session drops `five_hour_pct` and
`seven_day_pct` for **the whole account**, and the usage alert cannot fire until some render
restores them. The moment most worth warning about — *"you are at 91% of your 5-hour window"* on the
first prompt of a fresh session — is the moment the alert is structurally guaranteed to be silent.

⭐ **Reframed at gate 1 on ADR 098's own terms, which is the accurate statement of the problem.**
ADR 098 (Accepted, v2.24.2) introduced the per-account key, and it rejected the alternative
*"Single file + account-tag guard"* for this reason, verbatim: *"two active sessions interleaving
renders flap the file, so a session can miss its OWN real alert."* Per-account keying closed
**cross-account** bleed. It did nothing about **same-account** interleave — two sessions on one
account still share one file. ⇒ **This fix completes ADR 098's stated intent rather than proposing a
new one**, and the failure mode it prevents is the one that ADR already called unacceptable.
Corroborated live 2026-09-09: one account's snapshot changed twice in **8 seconds** carrying two
different `session_id`s, neither of them the observing session's.

**(b) Two documents describe the feature inaccurately.** The alert threshold is documented as
"default 80" when it is in fact dormant until aria-knowledge has a config file; and the rendered
example line in both `/statusline` SKILL.mds shows a clock format the code stopped emitting on
2026-06-04.

(a) is a behaviour defect. (b) is two false claims in shipped user-facing text. They are specified
together because (b)'s threshold claim is the *documentation half of (a)'s consumer*, and touching
one without the other leaves the pair disagreeing.

---

## 2. Measured state

Every row measured **2026-09-16** unless stated. Instrument named per row, per U23.

| Claim | Value | Instrument |
|---|---|---|
| Meter last changed | `2f1bd29`, **2026-06-10** | `git log -- plugin-claude-code/bin/statusline-meter.sh` |
| Source↔installed drift | **none** — all three copies `d6088f8e29df8ac707126a8687b3ce67` | `md5 -q` on `~/.claude/`, repo, installed plugin tree |
| Installed plugin version | **2.52.8** (was 2.52.0 on 09-09) | `plugin.json` |
| Did any of the 4 target files move since 09-08? | **No** (exit 0, empty) | `git log --since` with a 4-file pathspec; **positive control: 16 commits** touched `tests/repros/` in the same window |
| `:-80` placement | `config.sh:176`, inside the `if [ -f "$KT_CONFIG" ]` block (98–288) | `grep -n` |
| Self-defaulting assignments in `config.sh` | **29 total · 29 inside the block · 0 outside** | `grep -cE 'KT_[A-Z_]+=\$\{KT_[A-Z_]+:-'` + awk line filter |
| Threshold with no config file | `KT_USAGE_ALERT_THRESHOLD=` **empty** → hook exits at its own `case ''` | sourced `config.sh` under a bare fake `HOME` vs real `HOME` (`[80]`) |
| Stale example line | `plugin-claude-code/…/SKILL.md:12` **and** `plugin-antigravity/…/SKILL.md:10` | `grep -rn '5h 24%'` |
| Antigravity meter carries the same defect | **Yes** — `jq -n` at `:235`, conditional `five_hour_pct` at `:245`, unconditional `mv -f` at `:250` | `grep -n`; full `diff` = **16 lines, every one path-only** (`~/.claude` → `~/.gemini/antigravity`) |
| `bin/` files tracked by PORT-LEDGER | **0 across all 5 ports** | parsed `PORT-LEDGER.json` |
| `plugin-antigravity/skills/statusline/SKILL.md` tracked | **Yes**, `29b6cbe1…` — the only statusline surface in the ledger | same |
| Every port's `sla` | **`undeclared`** ⇒ drift is reported but never fails `--quiet` | same + the guard's own header |
| Antigravity surfaces already drifted | **23 of 37**, and `--quiet` exits **0** | `check-port-drift.sh`; `--quiet` bare exit |
| Existing suite baseline | **35 pass, 0 fail, bare exit 0** | `sh tests/repros/statusline-usage.sh` |
| The suite itself triggers the erasure | **Yes** — `five_hour_pct` **88 → ABSENT** between its line 51 and line 84 | replayed the suite's own two payloads against an isolated `HOME` |
| Consumer consequence (2026-09-09) | healthy snapshot → `ARIA usage alert … 5-hour plan usage at 91%`; erased snapshot → **silent** | ran `usage-threshold-inject.sh` two-armed with the real config present |

### 2a. What nobody has fixed

No preservation assertion exists. The nine `five_hour_pct` hits in `tests/repros/` are either
*"a render **with** `rate_limits` writes the value"* or inject-hook fixtures. **Zero** assert
survival across a render **without** `rate_limits`.

---

## 3. Decisions

### D1 — Preserve the **account-scoped** usage fields; always overwrite the **render-scoped** fields. Not a blanket merge.

The snapshot mixes two scopes in one flat object:

| Scope | Fields | On a render lacking `rate_limits` |
|---|---|---|
| **Render-scoped** — describes *this* render | `written_at`, `model`, `runtime`, `session_id`, `context_pct` | **overwrite** (or omit, per the existing contract) |
| **Account-scoped** — describes the *account's* rolling windows | `five_hour_pct`, `five_hour_resets_at`, `seven_day_pct`, `seven_day_resets_at` | **preserve** the prior value |

**Rejected — blanket merge.** It would carry another session's `context_pct` forward. The consumer
*does* guard that (`snap_sid != SID` → `ctx=""`), but relying on a downstream guard to neutralise an
upstream lie is how the next consumer inherits a defect. The snapshot should not contain a value
it cannot justify.

**Rejected — "skip the `mv` when no usage field parsed".** Cheaper-looking and wrong: it would also
stop refreshing `session_id` and `context_pct` on exactly those renders, and the inject hook needs a
current `session_id` for its per-session context guard. It trades one silent gap for another.

**Why preserving a possibly-stale window is safe:** the consumer already expires a window past its
`resets_at` (`_expired()` → metric dropped). So a preserved-but-stale pair is ignored, not acted on.
And an API-key session has no `oauthAccount`, so it keys to `default` — a *different* file — which
structurally separates the "never had 5h data" case from the "had it, payload omitted it" case.

### D1b — the partition is guarded against a HAND-WRITTEN LITERAL, and ships in D1a's commit.

⛔ **Gate 1 falsified D1's shape.** ADR 036 (`cs-builder`, Accepted 2026-04-20, *`mergeNonEmpty`
Preservation Principle Over Narrow Field Lists*) rejected exactly this form: *"An initial narrow fix
(explicit preservation list per known-captured field) was rejected as whack-a-mole: every new capture
type would force a list update, and the fix wouldn't survive future call-site additions."* A
four-field list means a future release adding a third window is **silently erased**, with the same
invisible failure mode.

⇒ **The list becomes derived-not-hand-maintained by a completeness guard:** every key the meter can
emit must appear in **exactly one** partition. A new key added to the `jq -n` filter without a
partition assignment **fails the suite**. Precedent in this workspace: the CS serialization
program's `Serialization.TIERS` + completeness gate, which reddens when a new column appears
unclassified.

⛔⛔ **The guard compares the partitions against a hand-written literal — it must NOT iterate them.**
`guard-scoped-to-the-wrong-unit`'s 2026-08-28 cue: *"a parametrised control whose parameter source IS
the mutation target"* — a guard that loops over the partition constant cannot see a field being
**dropped** from it, because the mutation shortens the test instead of failing it. A hand-written
literal is the only form the mutation cannot also edit.

**Rejected — apply ADR 036's own `mergeNonEmpty` wholesale.** Its *objection* is adopted; its
*solution* is not. A blanket non-empty merge would **preserve `context_pct` across a `/compact`**,
and `usage-threshold-inject.sh:71` deliberately treats an absent `context_pct` as *unknown, not the
old high value*. The generic principle would reintroduce a defect the existing design prevents on
purpose (AC5).

**Rejected — split the snapshot into two files** (render-scoped + account-scoped), which would make
the distinction physical and need no list at all. ADR 098 declares *"all three consumers derive the
key identically"* **load-bearing** — *"a key-format change must land in all three or the hook
silently reads a stale/absent file."* A second file multiplies precisely that risk, and
`session-start-check.sh` globs the existing name.

### D5 — the code half and the doc half ship as SEPARATE commits.

One concern per commit. The doc corrections (D3/D4) must not ride the behaviour fix's gate, and the
behaviour fix must be revertable without reverting a documentation correction.

### D2 — Mirror the fix to the antigravity port.

Rule 38 (close the class). Basis: the two meters differ by 16 lines, **every one path-only**, so the
write block is structurally identical. The port needs **no** `PORT-LEDGER` touch — 0 `bin/` files are
tracked on any port.

⚠ Labelled honestly: that the antigravity port *shares the defect* is **inferred from a structural
diff**, not yet executed. The plan must run AC1 against it under its own paths (AC7).

### D3 — Item B is **doc-only**. The `:-80` does not move.

**29 of 29** self-defaulting assignments in `config.sh` live inside the config-exists block; **zero**
outside. That placement is the file's uniform designed posture — *no config ⇒ the plugin is
unconfigured ⇒ defaults do not apply* — not an outlier. Hoisting one line makes
`usage_alert_threshold` the sole exception among 29 siblings, which is U16's partial-restore failure:
worse to read than the uniform behaviour. Hoisting all 29 is a different, much larger change with 29
behaviour changes, and nobody asked for it.

⇒ Fix the **claim**, not the code: `usage-threshold-inject.sh`'s docstring and both SKILL.mds state
the real condition.

**Non-goal, with its trigger (§4).** There is a legitimate product question underneath — *should a
budget alert be exempt from "unconfigured ⇒ dormant", since it guards a real-world cost rather than a
knowledge-management preference?* That is Mike's call, not a silent one-line hoist.

### D4 — Item C edits **both** ports and does **not** re-baseline `PORT-LEDGER.json`.

`check-port-drift.sh --update antigravity` re-baselines **all 37** surfaces and stamps
`last_parity_pass=today` + `parity_target=<canonical>`. With **23 already drifted**, that would
launder 23 pre-existing drifts into a false clean baseline and assert a parity pass that never
happened. **Strictly dominated — excluded, not offered** (U18 step ②).

Leaving the hash stale costs nothing measurable: every SLA is `undeclared`, so `--quiet` already
exits 0 with 23 drifted surfaces. The new entry becomes the 24th, which is what `drifted` *means* —
content moved since the last baseline.

**Rejected — fix claude-code only.** Rule 38: it provably leaves the same false example reachable in
a shipped port.

---

## 4. Scope and non-goals

**In scope.** `plugin-claude-code/bin/statusline-meter.sh` · `plugin-antigravity/bin/statusline-meter.sh` ·
`plugin-claude-code/bin/usage-threshold-inject.sh` (docstring only) · both `skills/statusline/SKILL.md` ·
`tests/repros/statusline-usage.sh` (new assertions).

**Explicit non-goals**, each with the trigger that would reopen it:

| Non-goal | Reopen when |
|---|---|
| The 23 pre-existing antigravity drifts | someone declares an SLA for that port, or a real parity pass is run |
| Hoisting all 29 `config.sh` defaults outside the block | a decision is taken that an unconfigured plugin should still carry defaults |
| The product question in D3 | Mike rules on it |
| The desktop app not rendering the status line at all | a desktop bridge is designed (`docs/non-goals.md` defers it) |
| `context_pct` being another session's value in a shared-account file | it causes an observed wrong decision; the consumer's session-id guard holds today |

---

## 5. Acceptance criteria

Each must be capable of going red for a named reason. AC8 is the **outcome** criterion; the rest are
mechanism.

| # | Criterion | Expected today |
|---|---|---|
| AC1 | With a snapshot holding `five_hour_pct`, a render whose payload has no `rate_limits` leaves `five_hour_pct` **and** `five_hour_resets_at` unchanged | **RED** (measured: 88 → ABSENT) |
| AC2 | Same for `seven_day_pct` / `seven_day_resets_at` | **RED** |
| AC3 | A render **with** `rate_limits` still **overwrites** them — preservation must not become preserve-always | GREEN; must stay |
| AC4 | `written_at`, `model`, `runtime`, `session_id` are always the current render's; never preserved | GREEN; must stay |
| AC5 | A payload with no context measurement still **omits** `context_pct` (existing post-`/compact` contract, `tests/repros/statusline-meter.sh:32`) | GREEN; must stay |
| AC6 | First-ever render with no prior snapshot writes a snapshot identical in shape to today's | GREEN; must stay |
| AC7 | The antigravity port satisfies AC1–AC6 under its own `~/.gemini/antigravity` paths | **RED** (inferred, to be executed) |
| AC8 | **Outcome:** on the first prompt of a fresh session whose account 5h is over threshold, `usage-threshold-inject.sh` emits the alert | **RED** (measured silent) |
| AC9 | `usage-threshold-inject.sh`'s docstring and both SKILL.mds state the threshold's real condition | **RED** |
| AC10 | Neither SKILL.md shows a rendered example the code cannot emit; the example matches the format the existing tests pin (`↺1pm`, `↺Tue 1pm`) | **RED** |
| AC11 | ⭐ **REWRITTEN at gate 1.** The single row `plugin-antigravity/skills/statusline/SKILL.md` flips `ok → drifted`, and `check-port-drift.sh --quiet` still exits 0. ⛔ The **23 → 24 total is NON-ISOLATING and must not be asserted** — it is a count over 37 files peer sessions also write (16 commits touched `tests/repros/` in the 8 days before this spec), so it reddens for others' work and greens for none of mine. Pattern: `criterion-measures-a-shared-mutable-resource` | GREEN; must hold |
| AC12 | `tests/repros/statusline-usage.sh` bare exit 0, with a count **greater** than the 35-pass baseline by exactly the assertions added | GREEN; must hold |
| AC13 | ⭐ **ADDED at gate 1.** The prior-snapshot read tolerates **absent · empty · truncated · non-JSON** files by falling back to today's write-whole behaviour, and **never** aborts the render. Four fixtures, one per case. Rationale: the fix introduces a READ of a file peer sessions write concurrently, and the script's prime directive is *"NEVER emit an error … a broken status line is worse than a sparse one"* | **RED** (no such read exists yet) |
| AC14 | ⭐ **ADDED at gate 1 (D1b).** Every key the meter can emit appears in **exactly one** partition; the guard compares the partitions against a **hand-written literal**, so dropping a field from the partition constant **reddens** the suite rather than shortening it | **RED** |

---

## 6. Risks and traps the plan must carry

1. ⛔ **The existing suite masks AC1 and will keep masking it.** Its `snap()` helper (`:100`) rewrites
   `$SNAP` wholesale before the inject cases, so an assertion placed after it proves nothing. The new
   assertions must sit where no later wholesale write can launder them — measured: the erasure
   happens at the suite's own line 84.
2. ⛔ **The fix introduces a READ of a file other sessions write concurrently.** It must tolerate
   absent, empty, truncated and non-JSON prior snapshots by falling back to today's behaviour. The
   script's stated prime directive is *"NEVER emit an error … a broken status line is worse than a
   sparse one"* — the merge must not add an abort path.
3. ⛔ **`jq -n` always succeeds**, so `if jq -n …; then mv` is not a guard. Do not mistake it for one
   when adding the read.
4. ⚠ **The status line does not render in the desktop app**, so live verification must use the
   fake-`HOME` harness (proven two-sided 2026-09-09), never an observed terminal.
5. ⚠ **A `find -name 'statusline-meter.sh'` census returns three hits, one of which is a *test file***
   (`tests/repros/statusline-meter.sh`). Ports are two, not three.
6. ⚠ `PORT-LEDGER.json`'s `claude-code` entry has `surfaces: {}` — canonical tracks nothing. Do not
   read that as "untracked port".
7. ⛔ **ADDED at gate 1 — the antigravity port never creates `~/.gemini/antigravity/`.** Its
   `_state` and `_tmp` both live there and the script has no `mkdir`. With the directory absent,
   `jq -n > "$_tmp"` fails, `mv` is skipped, and **no snapshot is written at all** — so *"no
   snapshot"* has **two** causes on that port, and a fake-`HOME` harness that does not pre-create
   the directory would "pass" AC1 by writing nothing. ⇒ AC7 **must** assert the snapshot EXISTS
   before asserting its contents, with a positive control (a render *with* `rate_limits` writes a
   full one). ⚠ Whether this bites a real antigravity install is **unmeasured** — flagged in the
   gate log's §11 as out of scope.

---

## 7. Open questions — ALL FOUR RESOLVED AT GATE 1

Per `open-sub-decisions-carried-into-execution`: a sub-decision carried into execution defaults to
the largest version by inertia. None is carried.

- **OQ1 — drop an already-expired pair at write time? → RESOLVED: write it forward.** The consumer
  already expires any window past `resets_at` (`usage-threshold-inject.sh:65-67`), so the honesty is
  enforced at the reader. A clock read in the writer adds a failure mode to a script that runs every
  30 s, against ADR 098's *"a wrong status line is worse than a sparse one."* **Locked.**
- **OQ2 — is `account_email` render- or account-scoped? → RESOLVED: render-scoped.** It is derived
  by `kt_resolve_account` on every jq-path render, never from the payload, so it is always present
  when jq is. It must still be **named in D1b's partition** or AC14 fails. **Locked.**
- **OQ3 — AC8 in the suite or left manual? → RESOLVED: in the suite.** It is the only criterion that
  can fail for the user-visible reason, and `statusline-usage.sh` already drives both the meter and
  the hook under one isolated `HOME`. **Locked.**
- **OQ4 — any other consumer? → RESOLVED by census: exactly two.**
  `usage-threshold-inject.sh` reads the *fields*; `session-start-check.sh` gates on file *existence*
  only (`ls "$HOME"/.claude/aria-statusline-state-*.json`). No third consumer. **Locked.**
