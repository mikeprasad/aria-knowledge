# Plan — port-drift guard reports live canonical lag

**Date:** 2026-08-17
**Scope:** `plugin-claude-code/bin/check-port-drift.sh`, `tests/repros/port-drift-check.sh`, `release.sh`
**Mode:** `/auto full unattended` · on-complete `stop`
**Constraint:** canonical `plugin-claude-code` only; local commits only; no version bump (canonical 2.46.1 is the parallel session's cadence).

## Problem (measured 2026-08-17, at HEAD)

`check-port-drift.sh` is the machine replacement for prose "tracked-drift narration" (v2.30.0),
built because hand-vigilance on the five-port distribution "had already produced its failure
class twice". It currently cannot report how far a port has fallen behind canonical.

Three measured facts:

1. **Canonical files are never hashed.** `port_surface_paths()` for `claude-code` is
   `: ;  # baseline — version only, no surfaces`, and `PORT-LEDGER.json` confirms
   `claude-code.surfaces` is empty. Every surface comparison is a port file against its own
   recorded sha — a tripwire for "this port file changed since we baselined it".
2. **The one canonical-aware signal is frozen.** The lag line (`check-port-drift.sh:188-191`)
   compares `port.version` against `port.parity_target`. Both are ledger fields written
   together by `--update`, so they are equal by construction at baseline time and never
   diverge as canonical moves on afterwards. Measured: antigravity reads `2.36.0 / 2.36.0`
   → no lag line, while canonical is `2.46.1`.
3. **The one lag line that does fire is a constant.** Only `claude-cowork` fires
   (`1.4.0 → 2.36.0`), and it fires permanently, because cowork versions on an independent
   `1.x` scheme that can never equal a `2.x` target. A permanent signal is not a detector.

Corroborating observation: v2.46.0 and v2.46.1 shipped during the investigation. Ports fell
two further versions behind and Gate C reported nothing new.

## Non-goals (deliberate, with reasons)

- **No canonical↔port CONTENT hashing.** `cursor-template` compiles to `.mdc` and
  `claude-cowork` has port-divergent bodies by design (ADR-014), so content comparison would
  be permanent noise for two of four ports. Version-level lag is the right granularity, and
  the script header already states this ("does NOT regenerate ports from canonical").
- **No change to `version-pair-drift`.** It is antigravity-internal (its `version.txt` vs its
  own `plugin.json`) and unrelated to canonical.
- **No version bump, no release, no push.**

## Tasks

### T1 — lag compares `parity_target` against LIVE canonical

`check-port-drift.sh:188-191`. Replace the `version` vs `parity_target` comparison with
`parity_target` vs the live canonical version from `canonical_version()` (already defined at
`:75`).

Rationale for this exact substitution over a special-case fix: cowork's permanent false
positive is a *symptom* of comparing the port's own version, not a case needing an exemption.
Removing that operand fixes the false positive and makes lag live in one change — closing the
class rather than patching an instance (Rule 38).

**AMENDMENT A1 (from /prospect 2026-08-17 — MANDATORY, do not skip).** `canonical_version()`
is **tolerant by design**: it returns empty when `$ROOT/plugin-claude-code/.claude-plugin/plugin.json`
is absent (`:76-77`). That is correct for its original caller (`--update` stamping, where an
absent manifest should not crash a re-baseline) and **silently wrong at the new call site**,
where empty makes `parity_target != ""` true for *every* port — so every port reports lag.

Resolve canonical **once**, and when it is empty emit **no lag line at all**: lag is undefined
without a reference point. This failure mode is *created by* this change — under the old
comparison an empty canonical was inert. It is the same shape as the defect being repaired (a
pattern correct in one branch, meaningless in the branch it moves to).

Acceptance:
- a port whose `parity_target` differs from live canonical reports `lag`
- a port whose `parity_target` equals live canonical does not
- **canonical unresolvable (manifest absent) → NO lag line for any port, and no crash** (A1)
- `claude-code` remains excluded from the lag line (it is the baseline)
- the line stays informational: it must not touch `_fail`

### T2 — `version_for_target_compare()` becomes dead

`:99`. Its sole purpose is normalising `-codex.N` / `-cursor.N` off the port's own version for
the T1 comparison. Once that operand is gone it has no caller. Remove it (Rule 6's carve-out:
never-wired-after-change code may be removed cleanly), or if retained, carry a Rule 37 removal
trigger. Verify zero callers by grep before deleting.

### T3 — rewrite Part D of `tests/repros/port-drift-check.sh`

⚠ **Two of its three assertions go VACUOUS, not red.** "codex prerelease suffix produced false
lag" and "cursor prerelease suffix produced false lag" assert an *absence*; once suffixes leave
the comparison they pass whether or not the feature exists. They must be REPLACED, not adjusted.
The third ("real version lag should still be reported") encodes the old semantics and needs
rewriting against the new ones.

New assertions must cover:
- `parity_target` behind live canonical → `lag` reported
- `parity_target` equal to live canonical → no lag reported
- a port whose own `version` differs wildly from canonical (cowork's `1.x` shape) but whose
  `parity_target` is current → **no** lag (the false-positive regression guard)
- `claude-code` never reports lag
- the lag line does not change the exit code

**AMENDMENT A2 (from /prospect 2026-08-17 — MANDATORY).** Sourcing found that **no existing
fixture writes `plugin-claude-code/.claude-plugin/plugin.json`** — every test points
`PORT_LEDGER_ROOT` at a bare temp dir, and the only manifest any fixture creates is
`plugin-antigravity/plugin.json` (`:65`). Since `canonical_version()` resolves against `$ROOT`
(`:76`), the seam *does* fully control the comparison — but Part D must now **write a canonical
manifest fixture** to exercise lag at all. Add, on top of the assertions below:

- a fixture writing `$ROOT/plugin-claude-code/.claude-plugin/plugin.json` at a chosen version
- an assertion that an **absent** manifest produces **no lag line and no crash** (the A1 guard),
  observed red before trusted green

Each new assertion observed RED before being trusted green. Use the `PORT_LEDGER` /
`PORT_LEDGER_ROOT` test seams already documented at `:30-31` — confirmed sufficient by sourcing.

### T4 — resolve the stale flag day

`release.sh:94,97` and `check-port-drift.sh:33-34` carry `TODO(v2.31.0): make fatal`. Canonical
is 2.46.1 — the flag day has slipped 15 minor versions, which makes it a false promise rather
than a plan (Rule 37: a temporary thing that never named a real removal trigger became
permanent).

Resolution: delete the version-numbered TODO and record the actual gating condition. Fatality
should key on a **declared SLA**, machinery that already exists and is `undeclared` on all five
ports; `is_failure()` already tolerates `undeclared` by construction. So Gate C stays advisory
until an SLA is declared, and becomes meaningfully fatal per-port automatically when one is.

## Verification

- `sh -n` parse check on the modified script, bare exit
- `tests/repros/port-drift-check.sh` via `tests/run.sh`, **bare exit code**, never piped
- full plugin suite bare exit
- `./release.sh` Gate A/B/C green; expect ALL FOUR ports to newly report lag — that is the fix
  working, not a regression
- mechanical public-hygiene sweep (no internal project names) before the final commit
- `git diff --cached --name-only` verified before every commit; parallel-session WIP untouched

## Risks

- **R1 — a wrong comparison direction silently inverts the guard.** Mitigated by T3's
  equal-vs-behind pair, both observed red.
- **R2 — staging a parallel session's file.** Mitigated by named staging + pre-commit diff check.
- **R3 — the new lag output changes Gate C's shape and could surprise the parallel session's
  next release.** Accepted and surfaced at close: the line is informational, cannot fail the
  gate (`is_failure` is called only on surface statuses and the antigravity version-pair), and
  reporting real lag is the point.
