# Plan — `/wrapup` must demote a prior handoff before its full rewrite

STATUS: GATED — /prospect run 2026-08-26, verdict PROCEED-WITH-CHANGES. Both changes applied below
in the same edit that records them. Gate log:
`knowledge/logs/prospect/2026-08-26-file-wrapup-demotes-before-rewrite.md`.
Requested by: Mike, 2026-08-26 ("1" = fix now, stop before release).
Repo: `aria-knowledge`. Baseline: `main`, **31 commits ahead of origin, working tree DIRTY with a
parallel session's WIP** (see Constraints).

## 1. The defect, measured

`/handoff` step 3f demotes a prior unconsumed handoff into `## Pending handoffs` **before** its full
rewrite. `/wrapup` step 6.5 performs the same full rewrite and calls **only the prune**.

| runtime | `/handoff` `ledger_add` | `/wrapup` `ledger_add` |
|---|---:|---:|
| claude-code | 2 | **0** |
| antigravity | 2 | **0** |
| openai-codex | 2 | **0** |
| cowork | 0 | 0 — no Bash, no ledger in either skill; internally consistent |

`kt_ss_ledger_prune` (read from the awk in `bin/lib-session-state.sh:249`) removes **only** `###`
entries already marked `· consumed`. Against an empty ledger it is a no-op. The rewrite then replaces
`## Where we left off`, `## Next session pickup` and `## Next session prompt` — exactly where
`/handoff` writes a pickup.

⇒ **`handoff → wrapup` destroys the prior session's handoff.** `handoff → handoff` is safe.

**Live instance:** proj-a, 2026-08-26. Session `affe189f` left a handoff 8 minutes before this
session's `/wrapup`. The clobber was avoided only because the operator skipped the documented step —
which is itself a rule violation, and the correct action (demote, then write) was never taken.

## 2. ⛔ The sentence is worse than the missing call

Step 6.5 currently asserts:

> *"Unconsumed handoffs survive at full fidelity — wrapping up one session never silently discards
> another's pending pickup."*

TRUE of entries already inside `## Pending handoffs`. **FALSE of a handoff in the active body**,
which is where `/handoff` puts it. This sentence **certifies the unsafe path**, so a careful reader
is talked out of the caution that would have saved the file. A missing capability is a gap; a false
assurance is a trap.

Its sibling has the same shape: *"the prune only ever removes entries already marked consumed, so
running it cannot destroy pending work"* is offered as the reason never to skip — but the prune is
not what destroys anything. **The rewrite is.** The instruction is right and its reason is a
non-sequitur, which is precisely why it was read past.

## 3. Scope — claude-code ONLY, by precedent

⭐ **Not my preference — the adjacent in-flight design's own ruling.**
`docs/superpowers/specs/2026-08-25-handoff-resume-mode-design.md` (GATED, uncommitted) lists under
Out of scope: *"porting to cowork/codex/cursor/antigravity (tracked-drift, **Claude-Code-canonical
this round**)"*. That spec covers the READER of pending prompts (`/handoff resume`); this plan fixes
the WRITER that destroys them. They compose — and this fix is arguably a prerequisite, since a
prompt `/wrapup` deleted cannot be resumed.

⚠ **A blind three-runtime port would be WRONG anyway**: antigravity's Step 6.5 has a different md5
from claude-code/codex (measured), so the same patch does not apply to it.

## 4. Tasks

T1. `plugin-claude-code/skills/wrapup/SKILL.md` Step 6.5 — three edits:
    (a) add the demote call, mirroring 3f's wording, INCLUDING its "full-fidelity prompt — never
        collapsed" clause and its "never demote a `lastEvent: in-progress` marker" exception;
    (b) correct the false "survive at full fidelity" sentence to name the ledger-vs-body distinction;
    (c) correct the "never skip" rationale so it names the REWRITE as the destructive operation.

T2. `tests/repros/wrapup-demotes-before-rewrite.sh` — a new repro. `tests/run.sh:13` is
    `for suite in repros/*.sh`, so it is auto-discovered with no wiring.

    ⛔ IT MUST CARRY A FLOOR (gate change). The repro locates the relevant sections by text match; if
    a skill is reformatted or a heading renamed, the probe finds nothing and **every assertion below
    it passes over zero input** — a green that checked nothing. Assert FIRST that both skills'
    sections were located. This is the same defect class this plan is fixing, one level down.

T3. Record antigravity + openai-codex as **tracked drift** in this plan's close-out AND as an
    explicit one-line note inside wrapup Step 6.5 naming both runtimes as carrying the same gap.

    ⛔ SHRUNK BY THE GATE — do NOT touch `PORT-LEDGER.json`. The plan wrote the destination as a
    conditional ("if that file already tracks per-runtime skill parity"). Sourcing resolved it:
    the file is keyed by RUNTIME and each entry holds `version`, `parity_target`,
    `last_parity_pass`, `sla` — **per-runtime release metadata with NO per-skill field.** Recording
    one skill's drift there means inventing a field, which this plan forbade in the same sentence.
    A note in the file someone actually reads beats a field in a manifest nobody opens for this.

## 5. Acceptance

A1. `/wrapup` Step 6.5 names `kt_ss_ledger_add` AND orders it before the rewrite.
A2. The demote is conditioned on a prior unconsumed handoff with a different/absent `sessionId`
    (so a session does not demote its own entry — the bug `/handoff` already guards).
A3. The `in-progress` exception is carried across (never demote an in-progress marker).
A4. The false "survive at full fidelity" claim no longer appears unqualified.
A5. The "never skip" rationale names the rewrite, not the prune.
A6. `tests/run.sh` passes with the new repro included.
A7. **Symmetry:** the repro asserts `/handoff` still carries 3f, so a future edit that removes the
    demote from EITHER skill fails — the guard is on the contract, not on one file.

## 6. Mutations

M1. Delete the `ledger_add` mention from wrapup -> A1 red.
M2. Reorder so the rewrite precedes the demote -> A1 red (ordering, not mere presence).
M3. Restore the unqualified "survive at full fidelity" sentence -> A4 red.
M4. Remove 3f from `/handoff` -> A7 red (proves the guard is two-sided).

## 7. ⛔ Constraints — the repo is not clean

- **Working tree is DIRTY with another session's WIP**: `.gitignore`, `plugin-claude-code/skills/
  index/SKILL.md`, `plugin-claude-cowork/skills/index/SKILL.md`, plus the untracked handoff-resume
  spec. **Stage only the files this plan names.** Never `git add -A`.
- **31 commits ahead of origin. Do NOT push.**
- ⛔ **Do NOT run `release.sh`.** It stages from the WORKING TREE, and this repo has a recorded
  near-miss where a parallel session's uncommitted files nearly shipped into a public artifact. Mike
  scoped this run to "stop before release".
- ⚠ A source fix is **not live until reinstall** — installed currently `cmp`-matches source, so the
  running plugin keeps the bug until a release + install. Say so; do not imply the fix is active.

## 8. Out of scope

Porting to antigravity / codex / cowork (per §3). Changing `kt_ss_ledger_add`'s format or behaviour.
Any change to `/handoff`. The release ceremony. `/handoff resume` (the adjacent spec owns it).
