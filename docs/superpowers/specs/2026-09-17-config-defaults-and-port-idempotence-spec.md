---
type: spec
date: 2026-09-17
status: ✅ GATED
goal: "Close two guard/config classes: config.sh defaults must resolve without a config file; the generated antigravity port must be provably regenerable"
units: 2
tickets: []
related:
  - docs/superpowers/specs/2026-09-16-statusline-snapshot-preservation-design.md
  - ../../../knowledge/projects/aria/decisions/099-account-resolution-is-runtime-specific.md
gate: ../../../../knowledge/logs/prospect/2026-09-17-file-config-defaults-and-port-idempotence.md
gate_verdict: PROCEED-WITH-CHANGES (F1–F4 applied below)
tags: [spec, aria-knowledge, config, ports, guards]
---

# Spec — config default resolution + port-generation idempotence

Two units, ruled by Mike on 2026-09-17 out of the statusline snapshot-preservation arc's
open items. They share a repo and a release, not a mechanism — separate commits, separate
acceptance, and either can ship without the other.

> ⛔ **Paths in this document are written `$ARIA`** (`ARIA=$(git rev-parse --show-toplevel)`).
> This repo is public and Gate D (`bin/check-public-hygiene.sh`) is FATAL on release; a real
> home path in tracked content fails it. Do not substitute one while editing.

---

## Unit A — config.sh defaults resolve unconditionally

### A0. Problem, in plain terms

A user who installs the status-line meter (`/statusline`) but never runs `/setup` sees live
5-hour and 7-day percentages on their status line while the **automated budget warning is
silently switched off**. Nothing errors. They would only discover it by noticing an alert
that never arrived.

### A1. Mechanism (measured 2026-09-17, not inferred)

`plugin-claude-code/bin/config.sh:98` opens `if [ -f "$KT_CONFIG" ]` and closes at `:288`.
**Every** self-defaulting value lives inside it — 29 of 29, zero outside. So with no config
file at `~/.claude/aria-knowledge.local.md`, `KT_USAGE_ALERT_THRESHOLD` is the empty string
rather than `80`, and `usage-threshold-inject.sh:54`'s `case '' ` guard exits 0.

Two-arm probe, both arms run:

```
real HOME -> KT_USAGE_ALERT_THRESHOLD=[80]
bare HOME -> KT_USAGE_ALERT_THRESHOLD=[]
```

### A2. The actual defect (D1)

**`config.sh` conflates two different questions inside one `if`:**

1. *"Is this knob set to X?"* — 29 pure constants plus their validators. Always answerable;
   needs no config file.
2. *"Is aria-knowledge configured?"* — a genuine precondition, because
   `KT_KNOWLEDGE_FOLDER` is **parsed-only** (`:102`) with no default, and is correctly empty
   without a config.

Question 2 already has a dedicated carrier: **`KT_CONFIGURED`**, set `false` at `:6`, `true`
at `:99`, and forced back to `false` by the three `knowledge_folder` validators at
`:212`–`:222`. It is already consumed by at least 7 call sites, e.g.
`post-plan-prospect-check.sh:12`, `post-push-retrospect-check.sh:13`,
`post-edit-check.sh:30`, `post-compact-check.sh:11`, `bash-cd-check.sh:22`.

⇒ The fix is **not** to hoist one default (that would make it the sole exception among 29
siblings — the partial-restore shape U16 forbids). It is to separate the two questions:
knob resolution moves out, the precondition stays in and keeps being carried by
`KT_CONFIGURED`.

### A3. Scope partition (D2) — measured, two contiguous ranges, no interleaving

| Range | Content | Disposition |
|---|---|---|
| `:99`–`:101` | `KT_CONFIGURED=true` | **stays** |
| `:102`–`:145` | 42 YAML parse lines | **stays** — require the file |
| **`:146`–`:211`** | 29 `${X:-Y}` defaults · 3 `tr -d ' '` normalizations · the `usage_alert_threshold` and `preflight_gate` validators | **moves out** |
| `:212`–`:225` | `knowledge_folder` validation → `KT_CONFIGURED=false` + `KT_CONFIG_ERROR` | **stays** |
| **`:226`–`:287`** | numeric/boolean validator `case` statements (themselves default-setters) | **moves out** |

⚠ **The validators must move with the defaults.** They are not merely checks — each one
*assigns* a default on an invalid value (`''|*[!0-9]*) KT_CADENCE_KNOWLEDGE=7 ;;`). Moving
`${X:-Y}` alone would leave an unconfigured install with resolved-but-unvalidated knobs,
which is a third state that exists today nowhere and is worse than either.

### A4. Why this is behaviour-preserving for the configured case (D3) — provable, not merely tested

Every line in both movable ranges is **idempotent on an already-valid value**:

- `X=${X:-Y}` is a no-op when `X` is non-empty.
- `case "$X" in ''|*[!0-9]*) X=N ;; esac` is a no-op when `X` is already numeric.
- `case "$X" in true|false) ;; *) X=true ;; esac` is a no-op when `X` is already boolean.
- `X=$(printf '%s' "$X" | tr -d ' ')` is a no-op when `X` holds no spaces.

So for **any** input where a config file was parsed, running them after `fi` yields byte-identical
variable state. The only reachable behaviour change is the unconfigured path — the target.

**Order safety, measured both directions:**
- Neither movable range references `KT_CONFIGURED`, `KT_KNOWLEDGE_FOLDER` or
  `KT_CONFIG_ERROR` (grep, both ranges, empty).
- The `knowledge_folder` validators read *only* those three, none of which is defaulted.
⇒ the `knowledge_folder` block running *before* the defaults is safe.
- Everything after `fi` (`:290`+) is function **definitions**; they read config at call time,
  so placement of the moved ranges immediately after `fi` is correct.

### A5. Consequence to state explicitly (D4)

After this change, an install with the meter but no config **gains a working usage alert**,
because `usage-threshold-inject.sh` deliberately does not gate on `KT_CONFIGURED` — it gates
on the snapshot existing and the threshold being numeric. That is the desired outcome and it
arrives as a *consequence* of separating the two questions, **not** as a carve-out.

Features that genuinely need a knowledge folder are unaffected: they gate on
`KT_CONFIGURED`, which is still `false` without a config.

⚠ Also true and worth stating: `KT_AUTO_CAPTURE` and `KT_ACTIVE_SURFACING` default `true`.
They will now resolve `true` unconfigured — but every consumer of them pairs the check with
`KT_CONFIGURED` or a non-empty `KT_KNOWLEDGE_FOLDER` (AC-A5 verifies this rather than
assuming it).

### A6. Acceptance criteria — Unit A

- **AC-A1.** Bare `HOME` (no config file): `KT_USAGE_ALERT_THRESHOLD` = `80`.
- **AC-A2.** Bare `HOME`: `KT_CONFIGURED` = `false` and `KT_KNOWLEDGE_FOLDER` is empty.
  *(the precondition must NOT be weakened — this is the guard against over-shooting)*
- **AC-A3.** Bare `HOME`: all 29 knobs are non-empty and each equals its documented default.
- **AC-A4.** **Configured case is byte-identical.** Dump all `KT_*` variables before and
  after the change against a real config fixture; the two dumps must be identical.
  *(this is the load-bearing criterion for "behaviour-preserving")*
  ⛔ **The "before" dump MUST come from the pre-change file, obtained as
  `git show HEAD:plugin-claude-code/bin/config.sh` written to a temp path and sourced there**
  — not from a dump taken after editing. A post-edit "before" is non-discriminating and would
  pass for any change whatsoever. *(gate F4 —
  `identity-test-oracle-for-behavior-preserving-optimization`)*
- **AC-A5 — REPLACED at gate F1.** The original censused two knobs, chosen because their
  defaults are `true`. That is the wrong property: what makes a consumer sensitive is
  **testing EMPTINESS**, not the default's value. The AC is now the measured partition below,
  which IS the safety argument and must be re-derivable by the commands named:

  1. **30 knobs** change value on an unconfigured install (derived from the two movable
     ranges, not hand-listed).
  2. **7 of them have an emptiness-sensitive or arithmetic consumer** —
     `KT_AUDIT_TRIGGER_THRESHOLD`, `KT_CADENCE_CONFIG`, `KT_CADENCE_KNOWLEDGE`,
     `KT_CADENCE_UPDATE`, `KT_EXTERNAL_FETCH_MAX_HITS`, `KT_RETROSPECT_BRANCHES`,
     `KT_RETROSPECT_MIN_COMMITS`.
  3. **All 7 are UNREACHABLE unconfigured**, verified empirically not by reading:
     `session-start-check.sh:36` exits on `KT_CONFIGURED = false` (bare `HOME` run → exit 0,
     159 bytes of "not configured", **zero stderr** — so no arithmetic on an empty value ever
     evaluates); `pre-external-fetch-check.sh:23` exits unless the gate is `on` (default
     `off`); `post-push-retrospect-check.sh:13`–`:14` exits on `KT_CONFIGURED` and on
     `auto_retrospect` (default `off`).
  4. **10 consumers source `config.sh` without gating on `KT_CONFIGURED`** (control: 14 do
     gate, so the census discriminates). Of those 10: **7 read no changing knob**;
     `pre-commit-preflight-check.sh:67` self-defends with `${KT_PREFLIGHT_GATE:-warn}` so its
     value is identical before and after; `pre-external-fetch-check.sh:23` exits for both
     `''` and `off`; and **`usage-threshold-inject.sh:52` is the single reachable behaviour
     change — the intended one.**

  ⇒ **Unit A's entire user-visible effect on an unconfigured install is that the usage alert
  starts working.** Every other reachable consequence is provably nil.
  ⚠ Do NOT restate this as "only one consumer is ungated" — that claim was measured FALSE
  (10 are). The conclusion holds for a different reason, and conflating the two loses the
  reason.
- **AC-A6.** A malformed config (present file, unparseable `knowledge_folder`) still yields
  `KT_CONFIGURED=false` **and** resolved defaults — the previously-unreachable combination
  that is now correct.
- **AC-A7.** Zero `${KT_` self-defaulting assignments remain inside the `if` block; zero
  validator `case` statements remain inside it except the `knowledge_folder` ones.
- **AC-A8.** The full repro suite is bare exit 0, and `tests/repros/statusline-usage.sh`
  specifically stays at its current assertion count with zero failures.

### A7. Mutations — Unit A

| # | Mutation | Named control that MUST fire |
|---|---|---|
| M-A1 | Move the defaults out but leave the validators inside | AC-A3 (a knob resolves but unvalidated → at least one knob differs from its documented default on a malformed value) |
| M-A2 | Move the `knowledge_folder` validators out too | AC-A2 (`KT_CONFIGURED` would read `true`-ish / the error would not set) |
| M-A3 | Place the moved ranges *before* the `if` instead of after | AC-A4 (a parsed config value would be overwritten by its default → configured dump differs) |
| M-A4 | Hoist only `KT_USAGE_ALERT_THRESHOLD` | AC-A3 (the other 28 stay empty) |

---

## Unit B — port-generation idempotence guard

### B0. Problem, in plain terms

This repo carries a standing rule — *"run the generator; never hand-patch a generated port"* —
and **nothing enforces it.** Hand-edit `plugin-antigravity/bin/statusline-meter.sh` and every
check passes: no test runs `build.sh`, and that file is tracked by no ledger surface. The edit
survives until someone runs the generator, which silently overwrites it.

### B1. Why the existing guard structurally cannot cover it (D5)

`PORT-LEDGER.json` guards surfaces by **sha256 parity against canonical**. Measured census
2026-09-17: `claude-cowork` 25 surfaces · `openai-codex` 42 · `cursor-template` 2 ·
`antigravity` 36 · `claude-code` 0. Every port's `sla` is `undeclared`.

But `build.sh` **deliberately** rewrites `$HOME/.claude` → `$HOME/.gemini/antigravity` and
`.claude.json` → `.gemini/antigravity.json`. A path-adapted generated file therefore **can
never** hash-match canonical — tracking it as a surface would pin it permanently "drifted".
Measured: the canonical and ported meters differ on 16 lines and **every one is a path swap**
(filtering the diff for non-path lines returns empty).

⇒ Hash parity is the wrong instrument for this file class. The right question is not
*"does it match canonical?"* but **"does regenerating it change anything?"**

`claude-code`'s 0 surfaces is correct for the same reason — canonical is the source, so there
is nothing to compare it against.

### B2. Decision (D6) — assert generator idempotence, in an isolated copy

Add one repro that copies canonical + port into a temp dir preserving their relative layout,
runs the copied `build.sh`, and asserts the regenerated port is identical to the committed one.

⛔ **It must NOT run `build.sh` in the live worktree.** Measured: `build.sh` does
`rm -rf "$DST/skills"`, `rm -rf "$DST/template"`, `rm -rf "$DST/rules"` where `DST` is its own
directory. This tree is shared with parallel sessions, so an in-place run would destroy a
peer's uncommitted port work — which is the *same hazard class* this arc already documented,
where a peer's `build.sh` run committed another session's uncommitted fix into the port.

Isolation is cheap and was measured: 3.7 MB / 291 files across exactly two directories, and
`build.sh` reads nothing outside them (`REPO` is derived from its own `$SCRIPT_DIR/..`).

### B3. Acceptance criteria — Unit B

- **AC-B1.** The repro passes today (the committed port already equals generator output —
  measured 2026-09-17: `build.sh` exit 0, zero files changed, against a control of one file
  that was dirty beforehand).
- **AC-B2.** The repro goes **RED** when any ported file is hand-edited.
- **AC-B3.** The live worktree is **unchanged** by a run of the repro — asserted by the repro
  itself, with `git status --porcelain` compared before and after.
- **AC-B4.** The repro reports **which** files differ, not merely that some do — a guard that
  says "drift" without naming it costs the next reader the whole diff.
- **AC-B5 — CORRECTED at gate F2 (blocking).** The original said "skip, not a pass". ⛔ **A
  skip IS a pass**: `tests/run.sh:15` counts `sh "$suite"` exit 0 as a passing suite, so an
  unrunnable generator would aggregate as green. ⇒ when `build.sh` is absent or exits
  non-zero the repro **prints `VOID` and exits NON-ZERO**. And the verdict must rest on
  **positive evidence the generator executed** — `build.sh`'s own final output line, or the
  mtime of a file it is known to rewrite — never on an empty diff, because an empty diff is
  also exactly what a never-executed generator produces.
  *(gate F2 — `false-green-from-an-instrument-that-never-ran`)*
- **AC-B6.** Full suite bare exit 0; suite count rises by exactly 1.
- **AC-B7 — added at gate F3.** The comparison TARGET is the real committed port (so the
  shipping composition is what gets judged), but the generator's **INPUT is a replica**. Assert
  copy fidelity before trusting any verdict: file counts and a checksum manifest of both copied
  trees must match their originals. Record at the code that the input is a copy **and why** —
  an in-place run would `rm -rf` a peer's uncommitted port work — so a later reader does not
  "simplify" it into the live tree. *(gate F3 — `guard-measures-a-replica-of-its-subject`,
  which fires only partially here: the pattern's core failure mode is avoided by design.)*

### B4. Mutations — Unit B

| # | Mutation | Named control that MUST fire |
|---|---|---|
| M-B1 | Hand-edit one line of the copied port's meter | AC-B2 |
| M-B2 | Make `build.sh` exit 1 | AC-B5 (must SKIP loudly, not pass) |
| M-B3 | Point the repro at the live tree instead of the copy | AC-B3 (worktree changes → red) |
| M-B4 | Have the repro report a bare boolean instead of paths | AC-B4 |

---

## Non-goals (both units)

- **Declaring SLAs on the ledger ports.** Considered and excluded: it closes a *different*
  hole (hash-tracked surfaces) and may immediately redden on legitimate adaptations that must
  be triaged first. Reopen trigger: a port drift that the idempotence guard cannot see.
- **A behavioural bats suite for the port's meter.** Excluded on principle: the port is
  generated, so its behaviour is *derived* from canonical; a duplicate suite restates one
  contract in two harnesses and drifts from it. `bats` 1.13.0 is installed, so this is not an
  effort argument.
- **Porting Unit A's restructure by hand.** `plugin-antigravity`'s `config.sh` is generated —
  run `build.sh`, never hand-patch (which is exactly what Unit B then guards).
- **A release.** Version bump, CHANGELOG and `gh release create` are their own ceremony and
  are not in this spec.

## Rollback

Unit A is a pure code move in one file — `git revert` restores it exactly; no data, no
migration, no persisted state. Unit B is an added test file; deleting it is a full rollback.
The two commits are independent in both directions.
