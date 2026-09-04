# User-rule lead extraction — one definition, two consumers

**Status:** GATED — gate 1 run 2026-09-05, verdict PROCEED-WITH-CHANGES; C1–C4 applied in this
revision. Report: `knowledge/logs/prospect/2026-09-05-file-user-rule-lead-extraction-one-definition.md`
**Date:** 2026-09-05
**Rolls into:** v2.52.0 (unreleased; 23 commits since v2.51.0, CHANGELOG entry already open)
**(C4) Version-slot anchor:** assumes the v2.52.0 CHANGELOG entry is still open and v2.52.0
still unreleased **as of 2026-09-05**. Per `parallel-release-version-staleness`, re-read
`CHANGELOG.md` head AND `git ls-remote --tags origin` immediately before amending — never trust
this line as authoritative at execute time.
**Reported by:** KW Low, 2026-09-05 — symptom real, diagnosis corrected by measurement (§2.3)

## 1. Problem

`bin/lib-user-rules.sh` (the always-on U-rule digest generator) and
`bin/check-rule-lead-bytes.sh` (the `/audit rules` Step 7.2 gate) each contain their own
implementation of "the rule's lead paragraph". They disagree.

The generator has exactly ONE concept of a metadata paragraph: it skips a leading
`**Origin:` block (`lib-user-rules.sh:157`). The gate has none.

Consequence — the gate reports a number about a paragraph the generator does not render:

| Rule shape | Generator renders | Gate measures | Agree? |
|---|---|---|---|
| lead first (plain) | the lead | the lead | yes |
| `**Origin:` first | the lead | the **Origin block** | **NO — live** |
| `**Last updated:` first | the **metadata line** | the metadata line | agree, both **wrong** |

Row 2 is not hypothetical: Step 7.1 instructs every promoted rule to carry an Origin
block, so an Origin-first rule is the documented output of the promotion path.

Row 3 is the reported instance: an author who leads with any metadata line ships that
line as their always-on rule body, and the gate says `OK`.

## 2. Evidence (all measured 2026-09-05 against source HEAD `9f46c43`)

### 2.1 The gate/generator divergence on Origin-first (row 2)
Fixture: one rule, `**Origin:` paragraph (62 B) then the real lead (71 B).
- Generator: `- **U1 — Origin-first rule** — The actual operative claim is here...` (the lead)
- Gate: `OK U1 62 bytes` (the Origin block)
Two implementations, two different subjects, no error.

### 2.2 The metadata-lead instance (row 3)
Fixture with `**Last updated:** <date>` first:
- Gate: `OK U1 24 bytes` / `OK U2 24 bytes`, bare exit 0
- Control (metadata line deleted): `OK U1 167 bytes` / `OK U2 77 bytes`
- Generator: `- **U1 — <title>** — Last updated: 2026-08-27` — the date IS the shipped body
- Control: the generator renders the real lead in full

### 2.3 What is NOT true (reported, falsified — do not act on it)
- *"The script always extracts the `Last updated:` line."* FALSE. On the maintainer's
  27-rule corpus it measures real leads, 53–565 B, 13 OVER / 14 OK, bare exit 1.
- *"That is the documented rule format."* FALSE. Across all six rule files (3 maintainer,
  3 plugin template) there is exactly ONE `**Last updated:` each — the file header at
  line 3. Zero per-rule. Step 7.1 specifies a lead paragraph first.
- *"A rule's operative lead never reaches the always-on tier."* FALSE. The live
  `~/.claude/rules/aria-user-rules.md` carries 27 U-rule lines, each with a real
  operative lead, and zero `Last updated` occurrences.
- ⇒ The proposed redesign (make the digest carry the lead, OR declare it name-only and
  replace Step 7.2 with a title-quality rule) is **out of scope**: both branches assume a
  premise measured false. The digest carries the lead; the 240 budget is meaningful;
  Step 7.2 is load-bearing. There is no third state to resolve.

### 2.4 Reported items already fixed in the tree (verify, do not re-fix)
- Generator missing `LC_ALL=C` — fixed at `lib-user-rules.sh:101`, with an explicit
  gawk-on-Linux note. Present in the open 2.52.0 CHANGELOG entry.
- Comment saying "240 ch" where the gate says bytes — fixed; source says BYTES.
- Generator capturing only the lead's FIRST LINE (`para == ""`) — fixed (D3).
- ⚠ All three are TRUE of the installed plugin, because **v2.51.0 is the newest release
  and v2.52.0 is unreleased** (23 commits, unpushed). Every install has the old
  generator. This is an install-lag finding, not a source defect. Release is a separate
  decision (§7 OQ1) and is NOT taken by this spec.

## 3. Scope

**In:** the definition of "the lead" and its two consumers; a metadata-paragraph concept
that covers the class, not one marker; test coverage that would fail if the two ever
diverge again.

**Out:** the 240 value (an authoring contract, changeable only as a coordinated pair —
see the generator's own comment at `:74-88`); the four-way rendering (shipped 2.52.0,
working); the digest's design; releasing 2.52.0; the ports (`lib-user-rules.sh` exists in
`plugin-claude-code` only — the antigravity build carries an explicit skip arm, so there
is no port drift to reconcile).

## 4. Design options

The defect is two implementations of one definition. Three ways to make them one:

- **D-A — a shared awk program both consume** (`-f` a common file). One implementation,
  literally. Cost: the gate must stay standalone-runnable by path (Step 7.2 invokes it
  directly), so it gains a sibling-file dependency — a `COUPLED` drift class the
  workspace's own plugin-drift tool exists to catch, and which broke `session-start-rules.sh`
  once before by shipping one file without its dependency.
- **D-B — keep two implementations, add a test asserting they agree** on a fixture corpus
  covering every shape. Cheapest. Does not prevent divergence; detects it. The generator's
  own header warns "a copy would drift silently, because nothing compares the two
  renderings" — a test IS that comparison, so this answers the stated objection.
- **D-C — the gate measures the generator's actual output** rather than re-deriving the
  lead. Agreement by construction; the gate then answers the question Step 7.2 actually
  asks ("will this lead ship intact?") instead of a proxy for it. Cost: the gate takes a
  dependency on the generator, and its output unit changes from "lead bytes" to
  "rendered-line bytes" — which would move the meaning of the 240 number.

**Recommendation: D-B + a metadata-paragraph concept in BOTH, decided by the gate.**
D-C is the most foundational but changes what 240 means, which §3 puts out of scope and
which would silently re-point an authoring contract. D-A is defensible; it is deferred
because the coupling class has already caused a live outage here and the benefit over a
comparison test is prevention-vs-detection on a two-file surface. This is the judgement
the gate should press hardest on.

## 5. Design

1. **One metadata-paragraph rule, same in both files — an ALLOW-LIST that skips, plus a
   SHAPE that warns.** A leading paragraph is skipped as metadata only when its first line
   matches a known marker (`**Origin:`, `**Last updated:`, `**Status:`, `**Superseded:`).
   A leading paragraph matching the general shape `^\*\*[A-Z][A-Za-z ]*:` but NOT on the
   list is treated as the lead AND reported by the gate as `UNKNOWNLABEL U<n>` (warning,
   non-fatal). Generalises the existing `**Origin:` arm without guessing.

   ⛔ A bare shape predicate was drafted first and FALSIFIED during drafting (§7 OQ3): it
   fires on `**Never do X:** ...`, a legitimate lead. Zero such leads exist in either real
   corpus today — so a shape predicate is guarded by DATA, not structure, and would one day
   silently eat a real rule. The allow-list can never do that; the warning is what still
   closes the class, by making an unrecognised marker LOUD instead of silently guessed.

   ⛔ **(C3) `**Why:` and `**How to apply:` are NOT on the skip list and must never be added.**
   They are body structure per Step 7.1 ("lead paragraph, Why with the dated quotes, How to
   apply, Falsifier, Origin"), so they FOLLOW the lead rather than precede it. They are the most
   tempting additions precisely because they match the shape — and skipping them would discard
   real rule content. A rule that LEADS with `**Why:` is an authoring error: warn, never skip.
2. **When metadata FOLLOWS the lead it still ends the lead** — unchanged behaviour,
   preserved for both files.
3. **A rule whose ONLY paragraph is metadata is an error, not an OK.** The gate reports
   `NOLEAD U<n>` and exits non-zero. This is the half that would have caught the reported
   instance: it converts a silent green into a loud red without asserting what the lead
   should say.
4. **The generator, on the same shape, renders title-only** — never a date as a rule body.

## 6. Acceptance criteria

- AC1 Gate and generator select the SAME paragraph for every shape in the matrix (§1),
  asserted by a test that compares them directly.
- AC2 Origin-first: gate measures 71 B (the lead), not 62 B (the block). Currently fails.
- AC3 **(corrected during execution 2026-09-05 — the original conflated two cases.)** Split:
  - **AC3a — metadata-first WITH a following lead (the REPORTED shape).** Gate skips the marker
    and measures the REAL lead; generator renders the real lead. Fixture: 167 B / 77 B.
    Was: `OK 24 bytes` exit 0, with the date shipped as the rule body.
  - **AC3b — metadata-ONLY, no operative paragraph.** Gate reports `NOLEAD` and exits non-zero;
    generator renders title-only with **no dangling separator**.
  ⚑ The original AC demanded NOLEAD for AC3a, which would have been wrong: a rule that HAS a
  lead must have it measured, not rejected. Caught by running the fixture, not by re-reading.
- AC4 A listed marker (`**Status:` first) behaves as AC3. An UNLISTED bolded label
  (`**Never do X:**` first) is treated as the LEAD and warned about — never skipped.
- AC5 (C1) The maintainer's real 27-rule corpus is BYTE-IDENTICAL before and after, in
  both the gate's output and the generator's. ⚠ This holds BECAUSE that corpus contains
  zero metadata-first AND zero Origin-first rules — measured 2026-09-05, positive-controlled.
  It is a property of the DATA, not of the change. A diff is a regression signal **only while
  that precondition holds**: re-measure the precondition, not just the diff. Step 7.1's own
  template makes Origin-first likely eventually, and on such a corpus the gate's output MUST
  change (that is AC2) — at which point AC5 would misread a correct fix as a regression.
- AC6 Existing 20 assertions in `tests/test-user-rules-digest.sh` stay green, UD7 included.
- AC7 Plugin suite bare exit 0; the CHANGELOG 2.52.0 entry is amended, not appended-to as
  a new version.
- AC8 (C2) The 6 existing assertions in `tests/test-audit-rules.sh` stay green (AR1–AR5),
  and all 20 in `tests/test-user-rules-digest.sh` stay green, UD7 included. Sourced at gate 1:
  all five AR fixture LEADS are clean against the predicate; `**Why:**` appears only as a
  FOLLOWING paragraph, which is never evaluated as a lead.

## 7. Open questions

- **OQ1 — release v2.52.0?** Not taken here. Until it ships, every install runs the
  v2.51.0 generator and none of this reaches anyone, including the reporter.
- **OQ2 — D-A vs D-B.** §4 recommends D-B; the gate should test that recommendation.
- **OQ3 — RESOLVED during drafting, 2026-09-05, by census.** Allow-list, not shape.
  Measured two-sided: the shape predicate misfires on ZERO leads across both real corpora
  (27-rule maintainer + template), and a control confirms it fires on all four metadata
  shapes AND on `**Never do X:** y` — a legitimate lead. So its safety today is a property
  of the data, not of the design. §5 item 1 now specifies allow-list-skips + shape-warns.
  Residual for the gate: is the four-marker allow-list complete, and is a non-fatal
  warning the right severity for an unknown label?
