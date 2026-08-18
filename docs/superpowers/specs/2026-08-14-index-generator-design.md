---
Last updated: 2026-08-14
status: SUPERSEDED BY IMPLEMENTATION — the generator was built independently on 2026-08-14 (116th pass); retained as the reasoning record + one open AC
tags: [index, generator, knowledge-retrieval, aria-knowledge, tooling, determinism, skill-design]
---

# `/index`: split the deterministic GENERATION from the judgment

> ⛔ **SUPERSEDED BY IMPLEMENTATION — read this before acting on anything below.**
> On **2026-08-18** this spec was re-verified and the generator **already exists**:
> `knowledge/tools/build-index.py` — tracked, 312 lines, `--validate` / `--write` / `--verbose`,
> shipped by the **116th `/audit-knowledge` pass on 2026-08-14** (the same day this spec was written,
> by a different session). It regenerated Tag Index + Other Tags against a corpus of **2,047** files
> (Tag Index 7,015 → 7,282 entries).
>
> **It independently satisfies this spec's core criteria** — AC1 is its documented design principle
> (*"a generator that cannot reproduce the current index is not trusted to replace it; run `--validate`
> before `--write`, always"*), AC2's scope is enforced in the script via a declared `SCAN_ROOTS`, and
> AC4 was verified two-sided (a `--write` rehearsal on a copy left all nine judgment sections
> byte-identical by checksum, with a negative control proving the splice ran). AC3's em-dash trap is
> **moot rather than unmet**: the generator emits from the corpus and splices, so it never parses
> `- path — Title` back out.
>
> ⇒ **Do NOT build from §5.** The scope it recommends is what shipped.
>
> ✅ **ONE criterion remains genuinely open — AC8.** `build-index.py` lives in `knowledge/tools/`, not
> in `plugin-claude-code/bin/`, so it does **not ship with the plugin**: another machine, or another
> user of `/index`, does not get it, and the SKILL.md cannot rely on its presence. That is the only
> actionable item left here.
>
> ⚠ Also still open, from the 116th pass's own header: `## Untagged Files` reads **34** where the true
> figure is **64**, and the **12 tags from ADRs 014/015 still have no Known Tags section**
> (`dependencies` and `upgrade` are load-bearing for the CS upgrade program).

**History (superseded — see the banner above).** Spec written **2026-08-14**; the measurements in §2/§3
were taken **2026-08-12** during the 114th `/audit-knowledge` pass. Gate:
`knowledge/logs/prospect/2026-08-14-file-index-generator-design.md` → **PROCEED-WITH-CHANGES**.
This revision incorporates that verdict and three owner decisions (§9).

✅ **The release-hold claim carried by earlier drafts of this spec was FALSE — retracted 2026-08-14.**
Those drafts said *"aria-knowledge is HELD mid-release, newest tag v2.44.1, the hold has spanned two
version bumps."* Measured after `git fetch --tags`: tag **`v2.45.1` → `e186953`** exists on the
remote, the GitHub release was **published 2026-08-13 17:55 UTC with 6 assets**, and `main` is
`e36a434` == `origin/main`, 0 ahead. **The release completed the day before the claim was made.**

⚑ **Cause, recorded because it is a reusable instrument error:** the check was `git tag -l` /
`git tag --sort=-creatordate` — the **LOCAL** tag list. Tags do not arrive on an ordinary `git fetch`.
A local tag list carries no information about the remote's tags, exactly as `git ls-files` carries
none about what was pushed. ⇒ **Verify a release with `git ls-remote --tags` (or `gh release view`),
never with `git tag`.** Sibling of the recorded *"ask the REMOTE whether an exclusion held, not your
local index"* rule — same shape, and the branch-side instrument (`ls-remote`) was in use correctly in
the same session without being pointed at tags.

⇒ **There is no hold.** This spec, and any code built from it, can be committed normally.

## 1. The problem

`/index` is a **skill** — Steps 0–10 executed by hand each pass. Three measured consequences:

1. **No generator survives a session.** The 110th and 111th passes describe *"the same generator as
   the 08-05 rebuild, reused unchanged"*; it was written to an ephemeral scratchpad and is gone.
   Measured: the knowledge repo holds **exactly one** script (unrelated, inside a reference corpus);
   `tools/` does not exist; the plugin's only index-related script is `lib-index-match.sh`, a
   **consumer**.
2. ⭐ **The rebuild is skipped even when explicitly requested — two consecutive passes, different
   sessions, same day.** The 114th pass (2026-08-12) did registration-only and said so. The **115th
   pass (2026-08-14) was invoked with `index deep` in its own arguments and the index was still not
   rebuilt** — measured immediately after: header still reads *"2026-08-12 (114th pass) —
   REGISTRATION-ONLY"*, Tag Index byte-stable at 363 sections / 7,015 pairs. This is the single
   strongest argument for the generator: the cost is high enough to defeat an explicit instruction.
3. **Producer/consumer asymmetry.** The index is *written* by expensive manual work and *read*
   automatically by `kt_index_match` on every task via hooks. A stale index returns **plausible
   results rather than errors**, so nothing surfaces the gap.

## 2. The measurement that decides the design

Two read-only probes, 2026-08-12, with negative controls (known-tagged file → 20 tags; missing file →
`None`; both passed). Re-verified 2026-08-14: Tag Index unchanged at 363 / 7,015.

| Measure | Value |
|---|---|
| Live Tag Index | **363** sections · **7,015** (tag,file) pairs · **1,909** files |
| Sections that exist only in `index.md` (judgment-invented) | **0** |
| Pairs reproduced exactly from frontmatter + path-derivation | **6,997 / 7,015 = 99.74 %** |
| Genuine dead links | **6 pairs / 2 files** |
| Residual mismatch | **12 pairs**, all no-frontmatter project READMEs — still derivable from path |
| Full frontmatter scan cost | **0.55 s** over 2,079 files |

⇒ **The Tag Index is, to measurement error, a pure function of `(corpus frontmatter, file path)`.**

⛔ **SCOPE BOUND — the figure covers the TAG INDEX ONLY.** The probe parsed the range
`"## Tag Index"` → `"## Other Tags"`. It says nothing about Other Tags (2,275 tags), Stale Files, or
the Projects map. The prospect flagged the first draft of this spec for carrying 99.74 % onto four
unmeasured surfaces (novel pattern `scope-exceeds-the-measurement`); v1 is scoped to what was measured.

## 3. Traps measured while probing — both were bugs in the probe that found them

- ⛔ **The `- path — Title` line format is NOT unambiguously parseable.** `split(" — ")[0]` truncates
  `references/sources/Full-Stack Audit Guide — Android, Backend & Web Frontend.md`, which then reads
  as a dead link. **16 of 21 apparent dead links were this artifact.** The parser must resolve the
  **longest prefix that exists on disk**, or the emitted format must delimit the path unambiguously.
- ⛔ **Project tags are auto-derived from PATH, not frontmatter** (`skills/index/SKILL.md:491`).
  `projects/aria/decisions/037-…` carries `tags: [claude-code, architecture, process, deployment]` —
  **no `aria`** — and is correctly filed under `### aria`. A frontmatter-only deriver reports **27
  false drift pairs**. The rule must also apply to files with **no frontmatter at all**.

⚑ Both surfaced only from a *second* probe. A section labelled "measured" is not exempt from
re-measurement.

## 4. The frame gap, and how it closes

The first draft's stated goal was *"stop the index drifting."* The gate found the plan could ship in
full without achieving it: **a generator makes rebuilds cheap; it does not make anyone run one.**

✅ **RESOLVED — and not by adding an invocation surface.** `/audit-knowledge` **Step 1b already runs a
drift check, and it carries zero information**: it compares `index.md`'s `Last rebuilt:` date against
*today* with a 7-day threshold. That is a clock-based staleness guard — false-positive by
construction (fires when N days pass though nothing changed) and false-negative (green at N−1 days
though the corpus moved).

**Both directions were measured this session without looking for them:**
- **False negative:** at 4 days Step 1b reads *fresh* — while the index carried 6 dead links, 12
  unregistered pairs, and both new ADRs missing.
- **Inverse error:** the session handoff asserted *"stale, the corpus has moved well past it"* — a true
  observation attached to a verdict its own threshold could not support.

⇒ **`--check` is not new scope. It is the correct FORM of a check that already exists.** Replacing a
clock comparison with a content comparison needs no new hook.

⛔ **A SessionStart hook was considered and REJECTED on measurement.** The argument for it — *"a
detector nothing invokes is worth nothing"* — rests on a **false premise here**. Measured audit-pass
cadence over the last 14 passes: gaps of 2,2,1,1,3,2,1,5,0,4,3,1,2 days — **mean 2.1, median 2, max
5**. And `bin/session-start-check.sh:146–155` **already** prompts *"Run /audit knowledge?"* on a count
or days trigger. Step 1b is invoked roughly every two days by an existing mechanism; a second hook
would duplicate a working pathway and add session-start noise for no coverage gain.

**Goal therefore stands as stated:** stop the index drifting — achieved by fixing what Step 1b
compares, not by adding a surface.

## 5. Proposed design (v1, post-gate)

```
plugin-claude-code/bin/build-index.py         # NEW — deterministic; no network, no LLM
plugin-claude-code/bin/index-vocabulary.json  # NEW — checked-in judgment: the known-tags LIST
skills/audit-knowledge/SKILL.md               # CHANGED — Step 1b: content check, not clock check
skills/index/SKILL.md                         # CHANGED — orchestrate; DEFERRED to slice 2
```

- **`build-index.py <knowledge_folder> --vocabulary <file> [--check]`** emits **the Tag Index and
  Untagged Files only**. Pure function of `(corpus, vocabulary)`; same inputs → byte-identical output.
- **Emits to stdout; never writes `index.md`.** No partial-write risk, and `--check` falls out of the
  same code path for free.
- **`--check`** re-emits and diffs against the existing `index.md` without writing, reporting
  added / removed / moved pairs. **Warns and always exits 0** (§9 D2) — the index is a retrieval aid,
  not a correctness gate; blocking on it would punish unrelated work.
- **Unreadable or absent index ⇒ UNDETERMINED, never a pass.**
- **`index-vocabulary.json` = the known-tags LIST only** (363 entries, already present as
  `## Known Tags`). Alias and normalization schema are **slice 2** — that is where the recorded
  `cs`→`css` hazard lives, and it needs a review surface named first (§10).
- **Dead links: report, then drop** (§9 D3). Regeneration naturally omits a path that no longer
  exists; `--check` names each dropped path first, so a genuine deletion is distinguishable from a
  rename.

**Out of v1, each needing its own evidence:** Other Tags (2,275 tags, unmeasured) · Stale Files
(ADR-117 policy is judgment) · the Projects map · `skills/index/SKILL.md` orchestration · alias and
normalization schema · Semantic Hints, Entities, Skill Connections, Cross-Reference Suggestions
(these four **carry forward untouched** — see AC4).

## 6. Acceptance criteria

- **AC1 — Reproduction gate (the trust gate).** At a pinned commit, `--check` reproduces the current
  Tag Index exactly: **363 sections, 6,997 of 7,015 pairs**. The **18 non-matching pairs are
  individually enumerated and classified** (6 dead links, 12 no-frontmatter READMEs) — **not** absorbed
  into a tolerance. ⛔ A percentage threshold is the wrong unit and is rejected: it lets a new defect
  net against a fixed one. Assert the **set** (ADR 2026-015).
- **AC2 — Purity.** Two runs over an unchanged corpus produce byte-identical output; collation is
  explicitly specified.
- **AC3 — The ` — ` trap has a red test.** A fixture whose *filename* contains ` — ` round-trips
  emit→parse→emit unchanged. **Must be seen to fail** against a naive `split(" — ")[0]` parser first.
- **AC4 — Non-destructive on carried sections.** Semantic Hints, Entities, Skill Connections and
  Cross-Reference Suggestions survive **byte-identically**. Mutation-checked: corrupt one row, the
  guard fires. *(Prevents repeating the earlier detector that would have deleted 276 of 320 rows.)*
- **AC5 — Dead-instrument control.** An **empty** corpus must **fail loudly**, not emit an empty index;
  a deliberately broken frontmatter block must be reported, not skipped. Both mutation-verified.
  ⛔ Without this, a broken scan emits a plausible small index and the retrieval layer silently shrinks.
- **AC6 — Path-derivation covered both ways.** A `projects/<tag>/…` file **with** frontmatter and one
  **without** both receive `<tag>`; a non-project file does not.
- **AC7 — Port discipline, measured — 3 hosts + 1 deliberate divergence.** Step 1b exists in **all
  four** `audit-knowledge` ports (1008 / 947 / 947 / 979 lines). Script hosting is **not** uniform:
  `plugin-claude-code` **35** scripts, `plugin-antigravity` **25**, `plugin-openai-codex` **21**,
  **`plugin-claude-cowork` 0 — it structurally cannot host a generator** (consistent with ADR-005,
  which already has it skipping Step 11). ⇒ Three ports get the script-backed content check; **cowork
  retains a skill-side path and that divergence is documented as intended**, not as drift.
  ⛔ The first draft's *"port the change to the other three"* was **falsified** — the ports are not
  copies (index SKILL.md: 674 / 650 / 653 / 291 lines, four distinct md5s).
- **AC8 — The generator ships**, in `plugin-claude-code/bin/`, so it survives the session that wrote
  it. ⚠ The installed plugin layout is **FLAT**, not repo-shaped — resolve its path the way existing
  `bin/` scripts do.
- **AC9 — Drift signal is provable.** After the Step 1b swap, one deliberate corpus edit (add a tagged
  file) must make `--check` report exactly that pair. ⛔ Absence-acceptance needs a **before** control
  and a **did-it-run** control; a clean `--check` is otherwise indistinguishable from a check that
  never executed.

## 7. Risks

| Risk | Why it matters | Control |
|---|---|---|
| Regeneration silently drops entries | A dropped pair is an unfindable file, and it fails **silently** | AC1 enumerated set + AC4 byte-identical carry-forward |
| "Clean" run over a broken scan | An empty/partial emit looks like a healthy small index | AC5 |
| A green `--check` that never ran | Silence is not evidence | AC9's two controls |
| Normalization destroys a project tag | Recorded near-miss `cs`→`css` | Deferred to slice 2; v1 ships the list only |
| Vocabulary drifts from corpus | A known tag with zero files, or a 40-file freeform tag | `--check` reports both |
| Cowork divergence read as drift | It cannot host a script | AC7 documents it as intended |
| ~~Committing into a held release~~ **RETRACTED 2026-08-14** | The premise was false — `v2.45.1` shipped 2026-08-13 with 6 assets; the check had read the LOCAL tag list | None needed. Verify a release with `git ls-remote --tags` / `gh release view`, never `git tag` |

## 8. Open questions — status after the gate

- **OQ1 Python or shell? ✅ RESOLVED — Python.** 1 `.py` already ships; **4 of 35** `bin/` scripts
  invoke `python3`; **11** depend on `jq`. No new dependency class.
- **OQ2 Write or emit? ✅ RESOLVED — emit to stdout.** Safer, and `--check` composes for free.
- **OQ3 Dead links: fix or drop? ✅ RESOLVED — report, then drop** (§9 D3).
- **OQ4 `--check` as a hook? ✅ RESOLVED — NO.** Rejected on measured cadence (median 2 days) plus the
  existing session-start nag. Lives in Step 1b.
- **OQ5 Vocabulary shape? ✅ RESOLVED — one global file.** Per-tier adds a join for no measured benefit
  at 363 tags.
- **OQ6 (NEW, open)** — what review surface catches a bad tag merge before it lands? Blocks slice 2,
  not v1. See §10.

## 9. Owner decisions taken 2026-08-14

- **D1 — Invocation: Step 1b only, no new hook.** Owner asked *"why not in audit-knowledge?"*;
  measurement agreed and my hook recommendation was withdrawn (§4).
- **D2 — On drift: warn, always exit 0.** Matches `reconcile-memory-rows.sh`. ⚠ The run-log variant was
  *not* chosen, so silence is not self-proving; AC9's did-it-run control carries that weight instead.
- **D3 — Dead links: report, then drop.**

## 10. Residual evidence asks

```
Before SLICE 2 (alias + normalization schema) can start — Hypothesis B: vocabulary-as-data
  Attempt status:  NOT-ATTEMPTED (not auto-sourceable)
  What's needed:   - Name the review surface that catches a bad merge before it lands (OQ6)
                   - Decide whether a merge entry requires a `reason` field
  Who can resolve: USER

Before the generator extends past the Tag Index
  Attempt status:  NOT-ATTEMPTED (deliberately outside the probe's scope)
  What's needed:   - A probe over Other Tags (2,275 tags) with its own negative control
                   - A decision on whether ADR-117 staleness policy is expressible as data
  Who can resolve: AUTOMATED-RETRY-LATER
```

## Related

- `knowledge/logs/prospect/2026-08-14-file-index-generator-design.md` — the gate this revision answers
- `skills/audit-knowledge/SKILL.md` Step 1b — the clock check being replaced (4 ports)
- `skills/index/SKILL.md` — orchestration change, deferred to slice 2
- `bin/lib-index-match.sh` — the **consumer**; its matching contract constrains the Known Tags set
- `bin/session-start-check.sh:146–155` — the existing invocation pressure that made a second hook redundant
- `knowledge/decisions/2026-015-gate-exception-as-narrowest-nameable-unit.md` — AC1's assert-the-set
  reasoning and AC5's dead-instrument control
- `knowledge/approaches/instrument-validity-before-evidence.md` — §3's two probe bugs are catalogued
  shapes there; §4's clock-vs-content finding is the `currency_guard_compares_to_latest_not_to_the_clock`
  rule applied to the index
- ADR-094 (canonical port) · ADR-005 (why cowork diverges) · ADR-117 (staleness exempts decision records)
