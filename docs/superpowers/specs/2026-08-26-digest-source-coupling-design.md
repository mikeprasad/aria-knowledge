# Spec — bind the always-on digest to its source by CONTENT, not rule number

Written 2026-08-26. Status: DRAFT — `/prospect` not yet run. No test code until it has.
Motivating handoff: "test-aria-rules-digest.sh:29 binds digest↔source by rule-NUMBER set,
never by content."

## 0. The defect, confirmed — and a LIVE instance, not a synthetic probe

`plugin-claude-code/tests/test-aria-rules-digest.sh` extracts rule NUMBERS from both sides:

    src_nums=$(grep '^### [0-9]' "$SRC" | sed 's/^### \([0-9]*\)\..*/\1/' | sort -n …)
    dig_nums=$(grep -o '^- \*\*Rule [0-9]*' "$DIGEST" | sed 's/^- \*\*Rule //' | sort -n …)
    assert_eq "digest covers every working rule by number" "$src_nums" "$dig_nums"

The digest's TEXT is never compared to the source's. A digest line may be arbitrarily stale
and the suite stays green.

⭐ **Live instance, measured 2026-08-26 — no mutation needed.** The Rule 23 amendment
(`4af3d98`/`b722c41`) is in the repo's digest and NOT in the installed copy. Both sides carry
the identical rule-number set 1–38, so the suite is 253/0 on either. Right now `/rules 23`
returns the pre-amendment text.

⚑ The amendment sitting stale is the one that says *"a stale rule is a defect, not an age, so
correct it at source and stamp it."* The artifact demonstrates its own rule's necessity.

⚑ **What makes this a wrong-unit defect rather than an oversight: the same test file gets it
right elsewhere.** Line 286 asserts *"digest states the tag-content condition, not mere
existence"*, and line 25 carries a positive control reasoning that without it *"the coverage
assertion below is satisfied by two empty strings."* The author understood
content-versus-existence. The digest↔source coupling is the one place it was not applied.

⚠ **This also bounds an earlier claim made elsewhere today.** "38 of 38 working rules
arrived" was a count of rule NUMBERS — the identical measure this test makes. Delivery was
confirmed; content fidelity was not, and could not have been by that instrument.

## 1. ⛔ The handoff's proposed mechanism CANNOT catch this. Measured.

Proposed: *"assert each digest line shares a distinctive phrase with its rule body."*

The live instance defeats it. Old and new Rule 23 both begin:

    never auto-add a rule; discuss first, save only on approval

and both end `A wrong rule, once saved, poisons every later session until someone catches it.`
The staleness is entirely in what was **appended** (scope, the one-step test, the falsifier
requirement). **A stale digest that is a correct-but-incomplete PREFIX of the current rule
shares every phrase it contains.** The check passes.

⇒ Any "digest ⊆ source" test is structurally blind to source ADDITIONS, and additions are
how rules actually evolve here — 4af3d98 and b722c41 are both pure appends.

## 2. What is mechanically available, and the honest claim

A semantic check ("is this summary faithful?") is not available. What IS available is:

> **the digest line for rule N was reviewed against a KNOWN VERSION of source rule N.**

That is a lockfile claim, not a quality claim, and the spec says so rather than overselling.

### Mechanism — a per-rule source fingerprint manifest

  - New artifact `plugin-claude-code/rules/digest-sources.txt`, one line per rule:
    `<rule-number> <sha256 of the source rule body>`
  - Rule body = from `^### N\.` up to the next `^### ` or `^## `, exclusive.
  - The test recomputes each hash from `$SRC` and compares to the manifest. Any mismatch
    FAILS, naming the rule and instructing: *review the digest line for Rule N against the
    changed source, then refresh the manifest.*

### Why per-rule and not whole-file

A whole-file hash fails on ANY source edit, including edits to rules whose digest line is
fine. That trains blind refreshing, which is how a gate becomes a formality. Per-rule
localises the failure to the rule that moved, which is what makes the instruction actionable.

## 3. ⛔ The gate-defeating move, and the constraint that blocks it

A refresh script makes it trivially cheap to bump a hash WITHOUT reading the digest line.
That converts this gate into a rubber stamp.

  - **The refresh MUST be a separate, deliberate command.** Never automatic, never a
    `--fix` flag on the test run, never invoked on failure.
  - The failure message must name the rule and what to compare, so the cheap path is
    "read two paragraphs", not "re-run with --fix".

Same reasoning as the deny-until ruling elsewhere today: *a gate that can be walked past is
a log line.*

## 4. Alternatives considered and rejected

| option | why rejected |
|---|---|
| shared distinctive phrase (the handoff's) | **Measured insufficient** — blind to appends; the live instance passes it. |
| digest title must match source title | Catches renames only. Both Rule 23 titles are identical; this instance passes. |
| assert regeneration is a no-op | **No generator exists.** `rules/aria-rules.md` is hand-written; `session-start-rules.sh` only copies it and `lib-user-rules.sh` builds the *user*-rules digest, a different artifact. |
| digest line length ≥ some fraction of source | A proxy that passes on wrong content of the right size. |
| hash the whole digest instead | Detects digest edits, not source drift — backwards. |

## 5. Preconditions verified

  - `SRC="$APM_ROOT/template/rules/working-rules.md"` is **repo-owned**, not the user's
    knowledge folder — so a manifest ships and is checkable on any machine. This was the
    deciding fact; a user-owned source would have made the manifest machine-specific.
  - Source headings are `### N. Title`; digest lines are `- **Rule N — Title** — summary`.
    Both already parse cleanly in the existing test.
  - Suite baseline: **253 passed / 0 failed, bare exit 0.**

## 6. Acceptance criteria

  AC1  Reverting any digest line's TEXT (numbers untouched) FAILS the suite. ⭐ The live
       installed-vs-source Rule 23 pair is the fixture — no synthetic mutation required.
  AC2  A source rule edit with no digest update FAILS, naming the rule.
  AC3  Rule-number drift still fails, i.e. the existing assertion is preserved, not replaced.
  AC4  The manifest covers exactly the source's rule set — no missing, no extra. A rule
       absent from the manifest must FAIL, not be silently skipped.
  AC5  All 253 existing controls still pass, bare exit 0.
  AC6  Mutation-verified: for each new assertion, name which control catches it and prove
       the mutation created the condition.
  AC7  No `--fix` / auto-refresh path exists in the test. Asserted, not merely omitted.

## 7. Open questions

  OQ1  Does the manifest belong in `rules/` (ships to users, visible clutter) or in
       `tests/` (test-owned, but then it is not part of the shipped contract)? Leaning
       `tests/`, since it is an instrument and not something a user reads.
  OQ2  The other three ports (antigravity, codex, cowork) each carry their own digest.
       Scope here is claude-code only, consistent with the Rule 23 amendment's own scope
       and the standing tracked-drift ruling. Flagged, not assumed.
  OQ3  Should the refresh command also print a diff of the source rule, so the reviewer
       sees what changed? Cheap and it makes the review real rather than nominal.

## 8. Non-goals

  - Verifying the digest summary is FAITHFUL. Not mechanically available; §2 states the
    weaker claim deliberately.
  - Generating the digest. That would be the strongest fix and is a much larger change.
  - Porting to the other three runtimes (OQ2).
