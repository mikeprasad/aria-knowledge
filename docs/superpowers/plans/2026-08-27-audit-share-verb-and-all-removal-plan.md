# Plan — `/audit share` becomes a verb, and `/audit all` is removed

**Status:** GATED — `/prospect` run 2026-08-27, verdict PROCEED-WITH-CHANGES; both required
changes applied below before any code. Gate log:
`knowledge/logs/prospect/2026-08-27-file-audit-share-verb-and-all-removal.md`
**Date:** 2026-08-27
**Ruling:** Mike, 2026-08-27: *"convert it and also lets remove the all command since now there are many audits"*

## Goal

1. `audit-share` joins the dispatcher as `/audit share` — canonical and advertised, with
   `/audit-share` demoted to unadvertised compat exactly like the other four (W2's posture).
2. The `all` verb is **removed** entirely.

The two interact favourably: `all` was the one place share was genuinely problematic (a
cross-tier write into a team/possibly-public repo, config-gated, wrong inside a
run-everything). Removing `all` dissolves that objection rather than forcing an exception.

## Why `all` goes

Six sub-audits is past the point where "run them all in sequence, each to completion" is a
sensible default. Three of the five current legs (`style`, `usage`, `rules`) are already
opt-in and explicitly excluded from cadence, so `all` was running three things the design
says should only ever be deliberate. Adding a sixth that writes into a shared repo makes
that worse.

## Blast radius (censused, not estimated)

⛔ **Two `all` occurrences are NOT the dispatcher verb and must not be swept:**
- `audit-share/SKILL.md:130` — `all` is an approval keyword in its own batch UI.
- `audit-style/SKILL.md:62` — `all` is a scan-scope option (ignore the session cap).

Real dispatcher-`all` surfaces: `audit/SKILL.md` `:2` (description), `:52` (verb table row),
`:53` (unknown-verb message), `:71` (menu item 6), `:87`–~`:100` (Step 3 section), `:120`
(sequencing invariant); `audit-usage/SKILL.md:76`; `help/SKILL.md:42`;
`plugin-claude-code/tests/test-audit-rules.sh:104` (AR11).

Historical design docs under `docs/superpowers/` keep their `/audit all` references — they
are dated records of what was decided then, matching the archived-tombstone precedent W2 set.

## Tasks

- **T0 — baseline.** Record both suite totals and Gate B bytes before any edit, so every
  later number has something to be compared against.
- **T1 — dispatcher.** Verb table: drop the `all` row, add `/audit share [args…]`. Unknown-verb
  message: valid verbs become knowledge, config, style, usage, rules, share. Bare menu: item 6
  becomes `share` (six entries, no `all`). Delete Step 3 (`/audit all` — Sequence + Tally) and
  renumber the steps after it. Delete the `all`-is-sequential invariant bullet. Rewrite the
  description to absorb share's trigger vocabulary and drop every `all` reference.
- **T2 — `audit-share`.** Demote the description from 454 B to the one-line internal form the
  other four carry (~200 B). Update its canonical-resolution header: `/audit share` canonical,
  hyphen form unadvertised compat. Leave its Step-4 `all` approval keyword untouched.
- **T3 — `audit-usage:76`.** Drop `/audit all` from the opt-in sentence.
- **Task 4a: Sibling-surface sync.** ⛔ The gate FALSIFIED this step as first written ("the
  `/help` row"). A ratchet-shaped census — using MC2's own regex, the instrument that will
  police this afterwards — returns **16 command-form occurrences across 5 files**. One Step
  per surface:
  - `skills/help/SKILL.md:42` verb list (drop `all`, add `share`) and `:48` (`/audit-share`
    row → `/audit share`) — 1 site
  - `QUICKSTART.md:51` — 1 site
  - `template/OVERVIEW.md:135` — 1 site
  - `skills/audit-share/SKILL.md` — 6 sites: its `#` heading, the `## /audit-share complete`
    banner, and its self-references. ⛔ Leave `:130`'s `all` approval keyword alone — it is
    not the dispatcher verb.
  - **Verification step:** re-run the census; expect 0 outside compat-marked lines.
- **T4b — the `/setup` invocation path (own checkpoint).** ⛔ `skills/setup/SKILL.md` holds 7
  sites and is **not documentation** — `:497-501` *invokes* `/audit-share` inline as the
  post-setup cold-start sweep. Behavioural surface, different failure mode from prose; update
  the advertised form and confirm the invocation still resolves by skill name.
- **T5 — tests.** AR11 asserts five legs in `/audit all` and **must go red** — rewrite it to
  assert the verb set and the absence of `all`, do not delete it — the rewrite plainly earns
  it. ⛔ **Extending the MC2 alternation to include `share` is load-bearing, not tidying** (now
  AC3): without it the newly-canonical form ships with no ratchet at all, which is
  `guard-scoped-to-the-wrong-unit` committed knowingly. Keep the archived-copies positive
  control.
- **T6 — gates.** Plugin suite, hook-repro suite, Gate B (expect headroom to GROW), release
  build.
- **T7 — version + CHANGELOG.** 2.50.0. State the removal plainly: `/audit all` now hits the
  unknown-verb branch, which lists the valid verbs — a clear message, not a silent failure.
- **T8 — release + site.** Cut the release, attach assets, verify the published zip by content;
  then sync `ariaknowledge.com` (its copy currently names `all` as a verb and lists
  `/audit-share`) and read the change back off the live site.

## Acceptance

- AC1 — `/audit share` resolves; the verb table, menu and unknown-verb message agree on exactly
  six verbs and no `all`.
- AC2 — zero dispatcher-`all` references survive, and both non-verb `all` usages are intact.
- AC3 — MC2 ratchet covers `share`; a planted `/audit-share` command form makes it red
  (seen red, not asserted). This is a gate-mandated criterion, not an implementation detail.
- AC4 — Gate B headroom is larger than the 315 B baseline (the demotion should pay for itself).
- AC5 — both suites bare exit 0.
- AC6 — live site shows the six verbs and no `all`, read back from `ariaknowledge.com`.
- AC7 — the 16-site census returns 0 command forms outside compat-marked lines, and `/setup`'s
  invocation path names the canonical form.
