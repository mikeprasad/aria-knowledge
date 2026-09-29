# Shape-agnostic backlog live-entry count — plan (2026-09-29)

**Status:** PROSPECTED 2026-09-29 — PROCEED-WITH-CHANGES (`knowledge/logs/prospect/2026-09-29-file-shape-agnostic-backlog-count.md`); both changes folded in below. Do not release or push without Mike.

**Source:** `knowledge/intake/ideas/2026-09-05-aria-audit-step1-counter-should-probe-wrong-heading-level-arrivals.md`
(incl. 2026-09-26 update) and `…/2026-08-27-aria-extract-writes-entries-at-the-wrong-heading-level.md`.

## Problem

Every backlog count in the plugin is `awk '… sep>=1 && /^### /{c++}'`. At the 127th pass it reported
**117** against a true live population of **181** (35% under-report): **53** standalone `## ` entries and
**11** `####` entries postdating the last pass were structurally invisible. Invisible entries are never
audited, because the count is also the pass's own scope.

Three contracts are missing, and each has produced mis-levelled entries:

1. **Capture contract.** The always-on INSIGHT CAPTURE directive names no heading level, so sessions
   invent `## <date> — <session>` group headers with bullets or `####` children.
2. **Clearing contract.** `/audit knowledge` says only "clear from backlog". Every pass since has
   improvised *demote `###`→`####` in place, body kept* (Rule 6), adding a disposition marker only
   sometimes. So an unmarked `####` is **ambiguous by construction**: nothing on disk separates
   "processed by a pass" from "born at the wrong level".
3. **Counting contract.** Two copies of the counter disagree on scope: the audit skill counts four
   backlogs (rules added in CHANGELOG line ~2840), `session-start-check.sh` still counts three.

## Measured this session (2026-09-29, knowledge corpus at `19beafb3`)

| Arm | Count | Note |
|---|---|---|
| `### ` below first `---` | **11** | insights 9 · decisions 2 · extraction 0 · rules 0 |
| `## ` with a non-blank body before the next heading | **2** | insights L14331, L14420 (bullets). The other 7 `## ` are group headers (blank line then `####`) |
| `####` dated ≥ last pass (2026-09-26) **without** a marker | **19** | decisions 6 · extraction 13 — all introduced by `f7af393d` (sweep), 3 min before the 127th pass commit `de05d441` |
| `####` dated ≥ last pass **with** a marker | 5 | insights 4 · extraction 1 |
| Heading lines inside `<!-- -->` blocks | 0 | guard kept anyway — clearing comments are free text |

⛔ **The idea's date-only rule is falsified here.** It assumed "a `####` postdating the last pass cannot
be demoted history". The 127th pass is stamped **2026-09-26** (machine clock PDT) and demoted entries
dated **2026-09-27** (JST). Mixed clocks put a ±1-day skew between entry dates and pass stamps, so a
date comparison bounds the search window but cannot classify.

⛔ **Authorship of the 19 is undeterminable from git** — the 127th recorded that uncommitted demotions
get swept into peers' commits in the shared tree. They are reported as *suspects*, not asserted live or
dead. They clear when the next pass marks them.

Marker vocabulary in use on `####` headings (202 total): `DISPOSITIONED` 96 · `PROMOTED` 54 · `HOMED` 30 ·
`CLEARED` 11 · 11 singletons (`VERIFIED-HOMED`, `ALREADY-PROMOTED`, `SUPERSEDED`, `ROUTED`, `RESOLVED`,
`FOLDED`, `DECLINED-AS-RULE`, `ACCEPTED`, …).

## Decision

**One shared counter; the `####` arm gated on a disposition marker; the three contracts written down.**

Rejected:
- *Patch only the audit skill's awk* — leaves the session-start trigger (which decides when an audit is
  prompted) under-reporting, and leaves the 3-vs-4-file drift. Fails Rule 38.
- *Date-only `####` arm (the idea's sketch)* — 19–24 false positives today from clock skew.
- *Per-pass watermark comment* — needs every pass to write it, cannot classify existing history, and
  concurrent appends during a pass land on the wrong side of it.

## Definitions (the contract the script implements)

Scope: the four action-eligible backlogs, lines **below the first `^---$`**, excluding `<!-- … -->` regions.
A **block** starts at any `^#{2,4} ` heading and runs to the next such heading.

- **canonical** — a `### ` block. (Same as today's counter: this is the control.)
- **h2-entry** — a `## ` block whose body holds a non-blank line. A `## ` with an empty body is a group
  header and is not counted.
- **h4-suspect** — a `#### YYYY-MM-DD` block with date ≥ the last pass's date, with **no** disposition
  marker in its heading or body. Marker = `\[[A-Z]{3,}[A-Z-]*` followed by a space, colon, em dash
  or `]` (lenient reader — prospect found 3 real undated markers, e.g. `[ALREADY-PROMOTED — …]`,
  that a date-requiring pattern misses; the writer contract below is stricter). With no audit log (fresh install) the arm is off.
- **live** = canonical + h2-entry + h4-suspect.

**Known bound (stated, not fixed):** an *undated* `####` born at the wrong level stays invisible — there
is nothing to window it by. Every writer contract below requires a date, which is the mitigation.

## Units

**U1 — `plugin-claude-code/bin/count-backlog-entries.sh`** (POSIX sh + awk, no new dependency).
- `count-backlog-entries.sh <knowledge_folder>` → one line per backlog + `TOTAL` line, each
  `canonical=N h2=N h4suspect=N live=N`, plus `cutoff=YYYY-MM-DD|none`.
- `--total` → the live number only (for the hook). `--list` → one line per non-`###` live block:
  `<file>:<line>: <kind>: <heading>`.
- Last-pass date parsed exactly as `session-start-check.sh` does today (first `- **Date:**` line of
  `logs/knowledge-audit-log.md`).
- Missing backlog files are skipped and named, never an error.

**U2 — tests.** New `plugin-claude-code/tests/test-count-backlog-entries.sh` on fixtures, each expectation
declared before running:
- positive: a fixture with 2 `###`, 1 `## `-with-body, 1 `## ` group header, 1 unmarked dated `####`
  after the cutoff, 1 marked one, 1 unmarked one *before* the cutoff, 1 heading inside a comment, 1
  `###` *above* the first `---`, 1 dated `####` after the cutoff carrying an UNDATED marker
  (`[SUPERSEDED by …]`) → `canonical=2 h2=1 h4suspect=1 live=4`.
- each arm forced red by mutation (drop the marker test → h4suspect 2; drop the body test → h2 2; drop
  the comment guard → +1; drop the separator guard → canonical 3).
- no audit log → h4suspect arm off.
- real corpus: run against the maintainer's `<knowledge_folder>` and require canonical **11**, h2 **2**,
  h4suspect **19** (re-measure immediately before, peers append — the check is the three arms matching
  an independent Python census, not the literal numbers).

**U3 — `session-start-check.sh`** calls U1 `--total` (fallback 0 on any failure, as today). Scope becomes
four backlogs. When h2+h4suspect > 0 the prompt gains `(N not at ### level)`. ⛔ Prospect: NO existing
test covers this count or its message (census exit 1), so add a hook-level test on a fixture knowledge
folder — the tier prompt with and without the suffix, and the fallback when the script is missing.

**U4 — `/audit knowledge` SKILL.md.**
- Step 1: replace the awk with U1; record canonical AND live; the `--list` output feeds Step 6 as a
  "Mis-levelled entries" finding. The Step 8 `Trigger:` field records both numbers.
- Step 7 (new explicit clearing contract): *clearing an entry = demote its heading to `#### ` in place,
  body preserved, and append `[<DISPOSITION> YYYY-MM-DD (<Nth> pass) → <destination>]` to the heading*;
  DISPOSITION ∈ {PROMOTED, HOMED, DISPOSITIONED, CLEARED, REJECTED, DEFERRED-stays-###}. An h2-entry is
  re-levelled to `#### ` with a marker; an h4-suspect gets a marker. ⛔ Never demote without the marker —
  an unmarked `####` is indistinguishable from a wrong-level arrival.

**U5 — INSIGHT CAPTURE contract** in `rules/aria-rules.md` and the duplicate string in
`session-start-check.sh`: append *"Each entry is one `### YYYY-MM-DD — <project> — <title>` heading with its
body under it — never a `## ` group header or a `####`, which the audit counter cannot see."* Add a
digest assertion in `tests/test-aria-rules-digest.sh`.

**U6 — `/stats` and `/backlog` SKILL.md** — the count description points at U1 (with the `###` rule kept as
the fallback description). `/backlog`'s archive routine is unchanged.

**U7 — ports.** Hook copies in `plugin-openai-codex/bin/session-start-check.sh` and
`plugin-cursor-template/scripts/aria/session-start-check.sh` get the script copied beside them (both dirs
already carry their own lib copies); `plugin-antigravity/bin/antigravity/pre-invocation-aria.sh` calls
`$CLAUDE_PLUGIN_ROOT/bin/count-backlog-entries.sh`, which `build.sh` copies with every canonical `bin/*.sh`; skill ports regenerate via `plugin-antigravity/build.sh` and
`plugin-cursor-template/scripts/port-skills-to-mdc.py`; codex and cowork skill copies hand-edited.
Cowork has no Bash — its Step 1 keeps the prose rule with the three arms described. Re-baseline
`PORT-LEDGER.json` only for ports actually synced.

## Out of scope (recorded, not dropped)
- `/extract` assert-after-write (08-27 idea sketch 1) — a second writer-side guard; the counter now
  detects its failure mode regardless. Separate change.
- Marking the 19 current suspects — that is the next audit pass's job under the new contract.
- Release, tag, push — Mike.

## Success criteria
1. `sh plugin-claude-code/tests/run.sh` and `sh tests/run.sh` bare exit 0, suite counts not lower than
   before (baseline taken first).
2. Every U2 mutation observed red for the named arm.
3. Real corpus: three arms agree with an independent Python census.
4. Hook and skill call the same script; `grep` finds no remaining copy of the `^### ` count awk in
   `plugin-claude-code/{bin,skills}` outside U1 — except `/setup`'s count of the legacy
   `ideas-backlog.md` (a migration check on a different file, deliberately out of scope).
