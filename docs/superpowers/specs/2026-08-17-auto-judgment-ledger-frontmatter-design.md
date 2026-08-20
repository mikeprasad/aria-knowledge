# Design spec — frontmatter for `/auto` judgment ledgers

**Status:** DRAFT, for review. **Date:** 2026-08-17. **Author:** 116th `/audit-knowledge` pass.
**Repo:** `aria-knowledge` (skill change). **Filed from:** `knowledge/` Step-A untagged census.

⚠ **Not committed to this repo.** `aria-knowledge` currently holds 18 uncommitted files from another
session and is 1 ahead of `origin/main`. Per the 2026-08-11 precedent (*hold a repo mid-work rather
than commit into it*), this spec is written and left for review rather than committed.

---

## 1. The problem, measured

The 116th `/audit-knowledge` pass censused untagged files in `knowledge/`. After tagging 10 genuine
references and archiving 10 debris files, **49 untagged files remain and every one is under
`logs/`** — meaning they are invisible to the tag matcher and unreachable by `/context`, `/ask` and
the index.

**The first framing was too broad and is retracted.** "The `/auto`, `/prospect` and `/preflight`
skills emit ledgers without frontmatter" is false:

| family | files | with frontmatter | without |
|---|---:|---:|---:|
| `logs/prospect/` | 779 | **779** | 0 |
| `logs/retrospect/` | 319 | **319** | 0 |
| `logs/check/` | 2 | 2 | 0 |
| `logs/preflight/` | 2 | 1 | 1 |
| **`logs/auto/`** | **58** | **17** | **41** |
| `logs/` (root) | 5 | 1 | 4 |

`/prospect` and `/retrospect` are **100% reliable across 1,098 files**. The defect is confined to
`logs/auto/` judgment ledgers.

## 2. Root cause

`plugin-claude-code/skills/auto/SKILL.md:76-77` pins the **path**:

> Write to `<knowledge_folder>/logs/auto/<YYYY-MM-DD>-<slug>-judgments.md`, resolving
> `knowledge_folder` from `~/.claude/aria-knowledge.local.md`. Create `logs/auto/` lazily.

…and pins **no schema at all** — `auto-judgment-ledger` appears **0 times** in the skill. So the
ledger is *session-authored*, not template-emitted. Files that carry frontmatter carry it because
that session chose to.

⛔ **A skill-change cutover was hypothesised and FALSIFIED:** both forms coexist on the same day
(`2026-07-30` has one of each), and the split is 4/3 in July and 13/38 in August. There is no
version boundary to point at.

⛔ **And there is no de-facto schema to codify.** Across the 17 files that *do* carry frontmatter
there are **23 distinct keys**; only four appear in a majority — `tags:` (14), `date:` (12),
`arc:` (12), `type:` (11). The rest (`mode`, `model`, `status`, `specs`, `spec`, `prospect`, `plan`,
`modifiers`, `entries`, `toggle`, `tickets`, `ticket`, `scope`, `repos`, `related`, `project`,
`originally_at`, `on_complete`, `dispositions`, `branch`) appear once or twice. **Codifying "what the
17 do" is therefore not available as an option** — they disagree with each other.

## 3. The question this spec must answer first

**Should judgment ledgers be TAGGED (indexed as knowledge) or merely STRUCTURED (queryable)?**
These are different asks and the spec should not conflate them.

- **Tagged** puts ~58 and growing ledger files into the tag index. `logs/prospect/` + `logs/retrospect/`
  already contribute **1,098 tagged files** to an index of 7,452 entries — so ledgers *would* be
  consistent with existing practice, and inconsistent treatment is arguably the current defect.
- **Structured** would let a future tool answer *"show me every pending judgment across all arcs"* —
  which is a real recurring need (this pass alone touched three ledgers with pending entries) and is
  currently answerable only by grepping prose.

⚠ **They pull in opposite directions on volume.** Tagging adds ~58 low-signal entries to a matcher
whose value depends on precision; structuring adds none. It is possible the right answer is
**structure without tags** — a `type:` and `status:` with **no `tags:` key at all**, which leaves
them out of the tag index deliberately and makes `## Untagged Files` correct rather than noisy.

## 4. Options

| # | Option | Effect | Cost |
|---|---|---|---|
| **A** | Pin a minimal frontmatter block in `auto/SKILL.md` (`type`, `date`, `arc`, `status`), **no `tags:`** | New ledgers become queryable; they stay out of the tag index by design | One skill edit. `## Untagged Files` still counts them — needs §5 |
| **B** | As A, plus `tags:` | Ledgers become tag-indexed like prospect/retrospect logs | Adds ~58 growing low-signal entries to the matcher |
| **C** | Teach the index generator to treat `logs/auto/` as intentionally untagged | Fixes the *reporting* noise, changes nothing about queryability | No skill change; leaves the real gap |
| **D** | Do nothing | — | The count grows and trains its reader to ignore `## Untagged Files` |

**Recommendation: A + C.** A closes the real gap (queryability) at the point of emission; C stops the
untagged report counting a population that is untagged *on purpose*. B is deferred until someone
names a retrieval question that tags would answer and `type:`/`status:` would not — on current
evidence the recurring question is *"which judgments are pending?"*, which is a `status:` query.

## 5. Backfill

⛔ **Recommend NOT backfilling the 41.** A ledger is a dated record of a past arc; rewriting 41 of
them to add metadata edits history for a reporting metric. The measured need is *"find pending
judgments"*, and pending entries live in **recent** ledgers, which the fix covers going forward.
If a backfill is wanted later it should be `status:` only, derived by reading each file — not
guessed from the filename.

## 6. Acceptance criteria

- **AC1** `auto/SKILL.md` states the frontmatter block verbatim, with the keys and an example.
- **AC2** A new `/auto` arc emits a ledger whose frontmatter parses as YAML and carries all four keys.
  ⚠ *Verified by running an arc, not by reading the skill* — the failure mode here is precisely a
  skill that says something no session does.
- **AC3** `## Untagged Files` in `knowledge/index.md` no longer counts `logs/auto/` — verified by a
  before/after count and a **negative control** (a genuinely untagged file elsewhere still appears).
- **AC4** The 41 existing ledgers are **unchanged** (asserted, not assumed: `git status` clean for
  `logs/auto/` after the change).
- **AC5** `/prospect` and `/retrospect` emission is **unaffected** — 779 and 319 files still 100%
  frontmatter. This is a regression check, not a formality: the fix touches a sibling skill family.

## 7. Known risk — RETIRED BY MEASUREMENT (2026-08-17 `/prospect`)

**The original text of this section argued that the change is "a skill instruction, not code —
nothing enforces it", called the 17-vs-41 split evidence that unenforced instructions are followed
inconsistently, and named this "the weakest part of this design".**

⛔ **That was argued where it was measurable, and the measurement says the opposite.** A natural
experiment already existed in this repo, with perfect separation:

| skill | pins a YAML frontmatter schema in SKILL.md? | compliance |
|---|---|---:|
| `/prospect` | **yes** | **779 / 779 (100%)** |
| `/retrospect` | **yes** | **319 / 319 (100%)** |
| `/auto` | no | 17 / 58 (29%) |
| `/preflight` | no | 1 / 2 (50%) |

Two independent treated sources, two independent controls, n ≈ 1,098 on the treated side.
**Instruction-level pinning demonstrably works at scale in this exact system.** The 17-vs-41 split
is not evidence that instructions fail — it is evidence that `/auto` was never given one.

⚑ **The process lesson is worth more than the correction:** a "known risk" section is where a spec
is most likely to reason where it could measure, because the register is speculative by convention.
Before writing one, ask whether the risk is a claim about the world that something already on disk
can answer. Catalogued by that prospect as `unsourced-risk-section`.

⚠ **AC2 still stands and is still the real test.** The evidence above raises the prior; it does not
observe this specific instruction being followed. If AC2 fails on the first arc after the change,
the conclusion is unchanged from the original text — the ledger needs a template or a hook, not
better wording.

## 8. Scope gap, stated rather than left implicit (added 2026-08-17 by `/prospect`)

§1's table shows `logs/` **root** carries 4 untagged files; §4's options cover only `logs/auto/`.
The four are `knowledge-audit-log.md`, `config-audit-log.md`, and two one-off 2026-05 manifests.

⛔ **Neither option C nor the property-keyed C′ reaches them** — they have *no frontmatter at all*,
so a property test keyed on "has frontmatter, deliberately no `tags:`" fails for them exactly as it
does for a genuinely-neglected file. **Deliberately out of scope here:** the two audit logs are
append-only operational records with a different lifecycle from a per-arc ledger, and the two 2026-05
manifests are one-offs. They need their own decision, not this spec's.

⚠ **Consequence for AC3, which must be read with this:** "Untagged Files no longer counts
`logs/auto/`" is satisfiable **while the reported count stays nonzero** (4 root + 1 preflight). The
AC measures the fix, not the outcome the fix exists to produce. Either widen it to name the expected
residual explicitly, or accept that a reader will still see a nonzero count they cannot act on.

## 9. Prospect verdict

`/prospect file …` run 2026-08-17 → **PROCEED-WITH-CHANGES**.
Log: `knowledge/logs/prospect/2026-08-17-file-auto-judgment-ledger-frontmatter.md`.

- **Step #1 (pin the block): PROCEED** — ✅ pre-validated by the natural experiment above.
- **Step #3 (index generator): SHRINK** — ❌ falsified as specced. Option C proposed a hardcoded
  `logs/auto/` path exception in `tools/build-index.py`, whose **own header** declares its scope as
  *"sections that are a pure function of file frontmatter"*. Re-specify as the **property-keyed**
  form: *has frontmatter AND deliberately no `tags:`* ⇒ report as structured-intentionally-untagged.
  That generalises to `logs/preflight/` and any future family for free, and cannot rot on a rename.
  Catalogued as `path-exception-contradicts-stated-scope`.
- **Steps #2, #4, #5, #6: PROCEED.** #2 carries a named acceptable risk (ledgers would be treated
  unlike their tagged siblings; reversible in one line).
- **Residual, USER-owned:** is a judgment ledger a *knowledge artifact* (tag it, like
  prospect/retrospect logs) or an *operational record* (structure it, don't tag it)? That is a
  decision, not a measurement — whether the existing 1,098 sibling tags are actually used for
  retrieval is not observable without query telemetry this system does not have.

---

## 10. RULING — a judgment ledger IS a knowledge artifact (Mike, 2026-08-18)

**Mike ruled the §3 question: "A its a knowledge artifact."** ⇒ Ledgers get `tags:`. This selects
spec **Option B**, not the recommended **A + C** — and it changes the plan in three ways, two of
which make it *smaller*.

### 10.1 T1's block gains `tags:`, and the no-tags paragraph is RETRACTED

⛔ The T1 insert's paragraph beginning *"No `tags:` key. A ledger is an operational record of one
arc, not a knowledge artifact…"* is **retracted in full and must not be shipped.**

⭐ **The tag convention is taken from the corpus, not invented.** The two best-formed existing
ledgers both use the same shape, so the block should say:

```
type: auto-judgment-ledger
date: <YYYY-MM-DD>
arc: "<one line naming the arc this ledger belongs to>"
status: <all-dispositioned | has-pending>
tags: [<project-tag(s)>, judgment-ledger, d7]
```

Observed verbatim in `logs/auto/2026-08-17-port-drift-live-lag-judgments.md`
(`tags: [aria, aria-knowledge, judgment-ledger, d7]`) and
`logs/auto/2026-07-30-auto-modifiers-and-session-md-judgments.md`
(`tags: [aria, aria-knowledge, aria-atlas, judgment-ledger, d7]`). `judgment-ledger` is the type
tag and `d7` cites the standing directive that mandates the artifact.

⚑ **`status` keeps its justification unchanged** — it answers *"which arcs have judgments waiting?"*,
which no tag can answer. And the ruling is **corroborated by the corpus**: of the **19** ledgers
carrying frontmatter, **16 already carry `tags:`**. Sessions that bothered with frontmatter at all
were already treating the ledger as knowledge. The ruling formalises practice rather than imposing it.

### 10.2 T2/T3 are DROPPED — the ruling deletes the work

T2/T3 built a *"has frontmatter, deliberately no `tags:`"* bucket in `tools/build-index.py` so
ledgers could be reported as structured-but-intentionally-untagged. **Under this ruling that bucket's
population is zero** — a tagged ledger is just a tagged file and leaves `## Untagged Files` by the
ordinary path.

Measured 2026-08-18: of **80** untagged files, **72** are `logs/auto/`; the non-auto remainder is
**8** (two hand-authored `logs/prospect/` logs, six `logs/`-root or `logs/preflight/` files) and
**none of them carry frontmatter at all**, so the property test would not match those either.

⇒ **Do not widen `parse_file` to a 3-tuple. Do not touch `build-index.py`.** ⚑ Worth noting because
it inverts the usual direction: the ruling that **adds** a field to the emitted artifact **removes** a
code change from the plan.

### 10.3 Backfill REOPENS, and the ruling flips its recommendation

§5 recommended **not** backfilling, because rewriting dated records to move *a reporting metric* is
not worth it. **That ground does not survive the ruling.** If a ledger is a knowledge artifact, an
untagged ledger is unreachable by the tag matcher, `/context` and `/ask` — a **retrieval failure**,
not a cosmetic. It is the same argument that justified tagging the seven `train-mikes-agent-*`
references in the 116th pass.

Measured 2026-08-18: **69 ledgers on disk · 19 with frontmatter · 16 with `tags:`** ⇒ **53
unreachable.**

⚠ **Not decided here.** Backfilling means deriving `arc` and `status` by **reading** each of 53 files.
`status` cannot be guessed from a filename, and guessing it wrong manufactures a false
`all-dispositioned` over a pending judgment — the worst available error for this field. That is a real
pass of work and Mike's call. §5 is marked **superseded**, not deleted.

### 10.4 AC3 and AC5 are rewritten — AC5 would have FAILED AT BASELINE

- **AC3 (was):** *`## Untagged Files` no longer counts `logs/auto/`.* → **Now:** a new ledger appears
  in the **Tag Index** under its declared tags — before/after entry count plus a negative control (a
  genuinely untagged file elsewhere still appears in `## Untagged Files`). ⚠ The untagged count does
  **not** go clean without §10.3's backfill; stated so a reader does not read a nonzero count as failure.
- **AC5 (was):** *`/prospect` and `/retrospect` still 100% — 779 and 319.* ⛔ **That AC would now FAIL
  AT BASELINE for a reason unrelated to this change.** Measured 2026-08-18: `logs/prospect/` is
  **801 of 803**. → **Now:** compliance must not **decrease** from the value captured at T0 — a
  no-regression assertion, not an absolute.

⚑ **And that measurement REFINES §7's natural experiment rather than breaking it.** The separation
holds overwhelmingly — **99.75%** vs 29% — but the mechanism statement needs its bound: **pinning a
schema binds the SKILL'S OUTPUT; it cannot bind a session that hand-authors the artifact without
invoking the skill.** Both exceptions are prose logs written by hand (one records *"Requested by Mike
('A prospect and censis')"*). ⇒ This is a **second, independent reason AC2 matters**, and it is not
fixable by better wording in `auto/SKILL.md`.
