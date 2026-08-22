# ARIA Value Analysis — Evidence Digest

**Last updated:** 2026-08-22 · **Plugin version analyzed:** v2.46.5 (working tree; latest published tag v2.46.4) · **Evidence base:** N=1 (plugin author's projects)

This document summarizes measured and estimated evidence for whether ARIA is *objectively valuable* when added to Claude Code. It accompanies the [README](../README.md)'s "Evidence and limits" framing with concrete numbers.

> **Limits up front:** All evidence below is from the plugin author's own multi-project work. No controlled A/B study, no inter-developer variance data, no cross-model comparison. Treat these as **calibration anchors for high-capability reasoning models**, not universal claims — results on lower-tier models may differ.
>
> ⚠ **One limit was promoted from footnote to headline this revision.** Previous revisions mentioned the underlying model in passing. It turns out the **session model changed mid-corpus, on a datable day, and that change moved the quality metrics more than anything else measured here.** A gate's behaviour is a product of *its skill definition **and** the model executing it* — and only the first half is version-controlled. Any revision of this document that compares numbers across time must establish which model produced them. See **"Corpus context"** and **finding #2**.

> **What changed since the 2026-07-19 (v2.40.2) revision.** The corpus grew by roughly half: **811 `/prospect` logs carrying a verdict (832 total) and 336 `/retrospect` logs** (vs 546 and 213; +49% and +58%). Three things moved:
>
> 1. ⭐ **ARIA's gates got substantially more effective — measured three ways — and that is what forced a metric to be retired.** Comparing adjacent three-week windows either side of the **2026-07-25** Opus 4.8 → Opus 5 transition, each `/prospect` run now **examines more of a plan's premises** (3.49 → 4.26), **settles a far higher share of them** (57.6% → 80.6%), and **catches 3.3× more false premises per run** (0.30 → 0.97). More of every plan is actually being checked, and more errors are being caught before execution.
>    ⚠ Of those three, **premises-examined and false-premises-caught are robust counts; share-settled is confounded** — an experiment on 2026-08-22 established that `no_movement` pools capability-limited premises with structurally-unresolvable ones, and could not size the split. Quote the 3.3×. Detail in finding #2.
>    ⛔ **The consequence is that the "plans are getting cleaner over time" claim is RETIRED — as a measurement artifact, not as a regression.** The needs-changes verdict rate rose 66.7% → 73.0% (69% → 89% across that same transition), *because* a premise the gate cannot settle leaves a plan looking clean, and the gate now settles most of them. **The verdict rate is a readout of detection, not of plan quality**, and it never measured plan quality in either direction — June's flattering 63% came from a gate examining fewer premises (2.98/run) and settling fewer of them (64.9%). Nothing about ARIA, the plans, or the work got worse; a number that was being read as a quality score turned out to be a sensitivity score.
> 2. ⭐ **A new and much stronger evidence axis is now measurable: the Evidence-Sourcing Pass.** Both gates record, per run, how many unsupported premises were converted to validated or falsified. Across 795 prospect runs: **2,928 candidate premises → 1,630 validated, 401 falsified.** That is a *direct count of caught errors* — not a proxy — and it upgrades "two thirds of plans needed changes" (which could be nitpicks) to "**401 specific premises were measured false before any code shipped**." On the retrospect side, **71 fixes believed shipped were found absent from the actual bundle.**
> 3. **On cost, the picture splits cleanly and reassuringly.** A same-state differential (the v2.40.2 hook and the v2.46.5 hook run against *identical* local state) shows SessionStart output growing **5,788 → 8,451 bytes (+46%)** — but **+1,776 B of that is a user-authored rules index that only exists if you write one**, and +550 B is an `autonomy`-posture directive absent at ship default. The **universal floor grew only +337 B (~+84 tok)**. Skill count rose 34 → **36**, skill-discovery surface ~18,519 → **19,541 B**. The prior revision's named tripwire fired and was resolved by **raising** the budget (18,944 → 19,968), not trimming — headroom is again ~2%. **New:** the per-edit hooks roughly doubled in latency (98 → 180 ms, 108 → 200 ms), and one new hook's latency **scales with corpus size**.
>
> *(Prior lineage, retained for the decision trail: the v2.30.1 → v2.40.2 revision grew the corpus ~1.9×, moved the needs-changes rate 74.5% → 66.7%, grew the pattern library 88 → 120, and moved fixed cost to ~5,500 tok. The v2.25.x → v2.30.1 revision grew the corpus ~1.6×, settled the rate at 74.5%, and moved fixed cost to ~5,470 tok before v2.30.1 trimmed it to ~4,990. Earlier, v2.18.x → v2.25.x grew the corpus 10–13×, corrected fixed cost ~1.6× upward, and retired a small-sample "only 1 of 14 was clean" artifact. **Every one of those revisions read the needs-changes rate as a quality score without recording which model produced it** — a gap this revision closes going forward but cannot close retroactively.)*

---

## TL;DR

| Question | Answer |
|---|---|
| **What's the core value?** | **Better code, fewer errors, fewer turns.** Higher accuracy + better reasoning + early error catching, compounding into less rework. Without ARIA, the same errors get shipped, then debugged, then re-fixed, then re-verified — each cycle is multiples of the token cost of catching it pre-execution. |
| **Does ARIA measurably improve Claude Code's output?** | **Yes, and this revision has the strongest evidence yet** — a direct count rather than a proxy. Across 795 `/prospect` runs the Evidence-Sourcing Pass **falsified 401 premises before execution**; `/retrospect` caught **71 fixes believed shipped but absent from the bundle**. 185 canonical failure-mode patterns catch repeat drift modes. |
| **Are ARIA's gates getting more effective?** | **Yes, and it is the clearest signal in this revision.** Per run, across the 2026-07-25 model transition: premises examined **3.49 → 4.26** and false premises caught **0.30 → 0.97 (3.3×)** — both robust counts. Share-settled rose too (57.6% → 80.6%) but that one is **confounded**; a 2026-08-22 experiment established that and could not size it. |
| **So is the underlying *plan quality* improving?** | **Not measurable from this data, and no longer claimed in either direction.** The gates' sensitivity changed mid-corpus, so the verdict series measures the instrument as much as the subject. This is a limit on the metric — **not** a finding that anything got worse. |
| **Won't better models make ARIA unnecessary?** | **The data points the other way.** The largest movement in four months of quality data came from the model getting better at settling a factual question — and ARIA's yield rose *with* it, 3.3× on false premises caught. The gates don't supply that capability, they **spend** it on a plan's premises. Value rises with model capability rather than being eroded by it. |
| **What does ARIA cost per session?** | **~5,850 tokens fixed + ~325 tokens per edit** (default config). Heavy edit sessions: ~38K total. A *fully configured* session (user rules authored + `autonomy` posture + tag match) pays up to ~7,000 fixed. The universal floor grew only ~84 tok since the last revision. |
| **What does ARIA save per session?** | **Direct: 0 to ~150K tokens** (typically 20–60K for corpus-engaged sessions). **Indirect (much larger): the cost of work-shipped-wrong avoided.** A single `/prospect` catch (~3K tokens to run) typically prevents a 15K+ token do-wrong → fix-after → re-verify cycle. At ~1 falsified premise per run under the current gate, avoided-rework dominates the direct savings. |
| **What's the wall-clock impact?** | **Still ~1–2% from hooks**, but no longer flat: per-edit hooks roughly doubled (~380 ms combined per edit; ~19 s across 50 edits). One hook (external-fetch interception) costs ~1.7 s per new surface and **grows with corpus size**. |
| **When does ARIA pay off?** | Multi-session work, established codebase, critical-path edits, domains with 5+ relevant promoted knowledge files, or a high-capability model to spend. |
| **When does ARIA NOT pay off?** | One-off scratch sessions, greenfield-first-session work, no-edit conversational sessions. |
| **What's the early-adopter cost?** | **Small, and smaller than the raw byte growth suggests.** Quality is net-positive from session 1. Two of the three largest cost increases since the last revision are *opt-in* — a new user pays neither. Token-arithmetic catches up at ~2–4 weeks. |

---

## What's measured vs estimated vs unmeasurable

| Axis | Fidelity | Method |
|---|---|---|
| **Token overhead** | Measured directly | Ran hooks, counted bytes, computed token equivalents |
| **Token overhead *attribution*** | Measured directly (new this revision) | Ran the v2.40.2 hook and the v2.46.5 hook against identical local state; diffed by segment |
| **Hook latency** | Measured directly | 3–5 runs each, minimum reported, clock outside the process spawn |
| **Token savings** | Estimated with named assumptions | Counterfactual: what each artifact replaces |
| **Wall-clock impact** | Qualitative + measurable subcomponents | Hook latency measurable; orientation/revision speedup estimable |
| **Errors caught pre-execution** | **Measured directly** (new this revision) | Evidence-Sourcing Pass frontmatter: candidates → validated / falsified / no-movement |
| **Gate effectiveness (yield) over time** | **Measured directly** (new this revision) | Premises examined, share settled, and falsifications **per run**, by window |
| **Which model produced a given gate run** | **Reconstructed, not recorded** | Recovered from transcript metadata; no `model:` field exists in gate frontmatter yet |
| **Output quality** | Multiple measurable proxies | Verdict distributions, pattern recurrence, audit promotion rate |
| **Plan-quality *trend*** | **Not measurable** — the instrument's sensitivity changed mid-series | Trend claims withdrawn in both directions |
| **Cross-developer applicability** | Not measured | N=1 only |
| **Long-tail value** | Not measured | Knowledge used 6+ months out is uncomputable in a session-scoped review |

---

## Corpus context — what was actually being measured

Numbers in this document come from one author's gate logs over roughly four months. Because the headline findings turn on *when* and *on what*, the shape of that corpus is part of the evidence rather than background:

| Month | `/prospect` runs | `/retrospect` runs | Mean plan size (steps) | Session model |
|---|---:|---:|---:|---|
| May | 82 | 36 | 10.3 | Opus 4.7 / 4.8 |
| June | 396 | 128 | 7.0 | Opus 4.8 |
| July | 156 | 90 | 8.4 | Opus 4.8 → **Opus 5 (from the 25th)** |
| August (to 22nd) | 177 | 66 | 7.0 | Opus 5 |

**Model timeline.** Recovered from local transcript metadata: `claude-opus-4-8` last appears **2026-07-25**; `claude-opus-5` first appears **2026-07-25** and is the session model continuously thereafter. `claude-fable-5` appears throughout in a secondary role, and `claude-sonnet-5` twice. ⚠ **Bound worth stating:** this was reconstructed from the most recent ~160 transcripts, so the *end* of the 4.8 era is well established but its start is truncated by the sampling window. The transition date is solid; the tail is not.

**Work mix.** The measured window spans a design-system/CSS framework, this plugin itself, a client product monorepo, a mobile rebuild, an agency-tooling workspace, and one mature production web/backend codebase. That last one is the highest needs-changes project in nearly every month and rises from 5 of 82 runs in May to **104 of 177 (59%) in August**, as work there shifted to security-critical backend material — authorization boundaries, serialization audiences, credential-disclosure fixes, a database-engine upgrade. That composition shift is real and is quantified in finding #2; it is *not* the main driver.

**Volume is not uniform.** June alone is 49% of the prospect corpus. Any aggregate over the whole window is substantially a June average, which is why per-month and per-window figures are reported throughout rather than pooled totals alone.

---

## Measured cost surface

> **Important:** the per-session fixed cost is **universal, not author-specific** — but *how much of it you pay depends on how much you have configured*, and that distinction is larger this revision than ever before. The headline byte growth (+46% on SessionStart) is mostly **opt-in surface**: a rules index that exists only if you author one, and an autonomy directive absent at ship default.

### Attribution: what actually grew (same-state differential)

The cleanest instrument available this revision — extract the v2.40.2 hook from git, run it against the *same* local state as the current hook, and diff by segment. Environment held constant, so every delta is plugin-driven:

| SessionStart segment | v2.40.2 | v2.46.5 | Δ | Universal? |
|---|---:|---:|---:|---|
| RULE 22 ORDERING | 731 | 731 | — | yes |
| TASK BUDGET | 913 | 913 | — | yes |
| SESSION STATE | 1,282 | 1,619 | **+337** | yes |
| INSIGHT CAPTURE | 241 | 241 | — | yes |
| MEMORY PATHWAY | 309 | 309 | — | yes |
| ARIA ACTIVE CONTEXT | 903 | 903 | — | post-`/setup` |
| ARIA Project Context | 248 | 248 | — | on project match |
| CODEMAP staleness | 235 | 235 | — | git-state dependent |
| audit-overdue prefixes | 270 | 270 | — | cadence dependent |
| DECISION ROUTING | 656 | 1,206 | **+550** | only if `autonomy` ≠ `default` |
| STANDING USER RULES | 0 | 1,776 | **+1,776 (new)** | only if you author `rules/user-rules.md` |
| **Total** | **5,788 B** | **8,451 B** | **+2,663 (+46%)** | |

**Read this carefully before treating +46% as your cost.** Nine of eleven segments are byte-identical. All of the growth is three segments, and **two of the three are opt-in**: the largest single addition (1,776 B) is an index of the user's *own* authored rules, which a new install does not have, and the second (550 B) fires only under a non-default `autonomy` posture. Using the prior revision's own floor definition — which this differential reproduces **exactly** at 3,476 B — the universal floor moved **3,476 → 3,813 B (~870 → ~953 tok, +9.7%)**.

### Per-session fixed overhead

1. **Skill-discovery surface** — descriptions of all installed skills, used by Claude Code's natural-language dispatch. At 36 skills this is **19,541 bytes (~4,885 tokens)** per session (was ~18,519 B / ~4,629 tok at 34 skills). The growth is **skill-count-driven**: two additions in this window (`/preflight`, `/audit usage`), not bytes-per-description creep. `release.sh` enforces a budget, now baselined at **19,968** — *raised* from 18,944 in this window. Live 19,541 leaves ~427 B (~2.1%) of headroom, so the same "trim or raise" decision recurs at the next skill addition. **This is now a recurring decision, not a one-time tripwire.**
2. **SessionStart guidance block** — steady-state floor ≈ **3,813 bytes (~953 tokens)** for a default-config session. Config-/state-dependent add-ons stack on top, as tabulated above.

| Per-session fixed cost | Tokens |
|---|---:|
| Skill-discovery surface (36 skills, v2.46.5) | ~4,885 |
| SessionStart guidance floor (default config) | ~953 |
| **Steady-state total (default config)** | **~5,850** |
| + `autonomy` posture (DECISION ROUTING) | +~301 |
| + user-authored rules index (19 rules measured) | +~444 |
| + knowledge-tag ACTIVE CONTEXT | +~225 |
| + project-context match | +~62 |
| + CODEMAP staleness / audit-overdue prefixes | +~125 |
| Worst case (everything firing) | **~7,000** |

### Per-edit variable overhead

The PostEdit hook emits a **592-byte** advisory after every Edit/Write — unchanged since v2.18.x. Combined with Claude's Rule 22 marker + scope-check responses, total per-edit overhead ≈ **325 tokens**.

The PreEdit hook remains **silent on compliant edits (0 bytes)**, emitting only its denial block when a Rule 22 marker is missing. ⚠ *Measurement note:* a synthetic invocation with no transcript path returns a 292-byte **fail-open diagnostic** ("could not verify this edit"), not a real per-edit cost. Do not count it.

**The hook surface roughly quintupled in count without adding tokens.** The plugin now ships 30+ hook scripts (was ~6 measured), including tautology detection on edits, a Bash-write guard, plan/push gate reminders, a commit preflight, and an external-fetch interceptor. Measured on their happy path, **eight of them emit 0 bytes** — the expanded surface buys enforcement at latency cost, not token cost. Positive controls confirm the instruments are live rather than dead: the codemap pre-explore hook emits 201 B when a CODEMAP exists, and the external-fetch hook emits 443 B when a local reference covers the requested surface. (Two hooks — `bash-cd-check`, `task-context-check` — could not be made to emit under synthetic input because they are gated on a per-session ledger; their triggered byte cost is **unmeasured this pass**, not zero.)

### Total at typical edit volumes

| Edit count | Approximate total ARIA token cost |
|---:|---:|
| 10 (light session) | ~9,100 |
| 50 (moderate) | ~22,100 |
| 100 (heavy edit day) | ~38,350 |
| 200 (large refactor) | ~70,850 |

Most of the fixed portion is cache-eligible if the session stays warm, reducing the effective input cost by roughly 10× for those segments.

### Hook latency

| Hook | v2.40.2 | v2.46.5 | Fires on |
|---|---:|---:|---|
| `session-start-check.sh` | 403 ms | **496 ms** | once per session |
| `pre-edit-check.sh` | 108 ms | **200 ms** | per Edit/Write |
| `post-edit-check.sh` | 98 ms | **180 ms** | per Edit/Write |
| `bash-cd-check.sh` | 88 ms | **163 ms** | per Bash call |
| `task-context-check.sh` | 91 ms | **156 ms** | per Task dispatch |
| `pre-explore-codemap-check.sh` | 7 ms | **8 ms** | per Glob/Grep |
| `usage-threshold-inject.sh` | — | 192 ms | per user prompt |
| `post-edit-tautology-check.sh` | — | 8 ms | per Edit/Write |
| `pre-bash-write-check.sh` | — | 10 ms | per Bash call |
| `pre-commit-preflight-check.sh` | — | 11 ms | per commit command |
| `pre-external-fetch-check.sh` | — | **1,748 ms** | per new external surface |

**The prior revision's "per-edit hooks are unchanged" claim no longer holds** — they roughly doubled. Combined per-edit cost is now ~380 ms, so **wall-clock at 50 edits is ~19 seconds** (was ~10 s), plus ~10 s of per-Bash and per-prompt hooks across a session. Still on the order of **1–2% of a 30-minute working session**, and tokens remain the real cost story — but the trend is worth watching rather than assuming flat.

⚠ **One new cost genuinely scales with the corpus.** `pre-external-fetch-check.sh` runs a recursive `grep` across the knowledge corpus to decide whether a local reference already covers an outbound fetch. At **3,260 markdown files** that costs ~1.7 s. It fires once per surface per session and *saves* an external fetch when it hits — but it is the first hook whose latency is a function of corpus size, and the corpus only grows. **This is a named revision trigger** (below).

---

## Estimated savings surface

These are counterfactual estimates — "what ARIA replaces vs what would otherwise be done." Each is calibrated against a stated alternative. Method is unchanged from the v2.18.x revision; the corpus is now far past the break-even thresholds noted under "Early-adopters."

### CODEMAP precision savings

**Alternative:** Re-orient via Glob + Read 5–10 files = 50–100 KB of context consumed.
**With CODEMAP:** Targeted Read of ~150 lines = ~3 KB.
**Per-event delta:** ~10–22K tokens per "re-enter a project and orient" event.

### ADR avoidance (decision re-debate)

**Alternative:** Re-debate a settled architectural question = ~5–10K tokens of back-and-forth.
**With ADR:** Load the captured decision = ~3–5 KB.
**Per-recall delta:** ~5–7K tokens per ADR reference.

### `/context` selective load vs naive folder read

**Alternative:** Load the whole knowledge folder (now **952 promoted files** across the canonical content dirs) or load nothing and ask blindly.
**With `/context <tag>`:** Selective load of 3–7 tagged files = ~30–60 KB.
**Per-event delta:** large reduction per use; the ratio grows as the corpus does.

### External-fetch interception (new this revision)

**Alternative:** Fetch a public doc page already mirrored in the corpus = one round trip plus the fetched page's tokens.
**With the interceptor:** a 443-byte pointer at the local reference, once per surface per session.
**Per-catch delta:** roughly the size of the avoided page (commonly 5–20K tokens), at a cost of ~1.7 s. Counted as savings only when it hits; when it misses it is pure latency.

### `/extract` retention vs PreCompact-only

**Alternative:** Post-compaction snapshots survive but require re-derivation of insights next session.
**With `/extract`:** Insights staged in backlog, promoted on audit, retrievable via `/context`.
**Per-promoted-item delta:** ~500–2,000 tokens of re-derivation avoided each time the topic recurs.

### Rule 22 revision avoidance

**Alternative:** Same fix shipped wrong, retrospect catches it, re-ship cycle required.
**With Rule 22:** Pre-edit assessment catches the gap before code is written.
**Per-catch delta:** ~15K tokens per catch (based on at least one real session that converged in 5 turns instead of 9 — a 44% reduction).

### Aggregated per-session savings range

| Session class | Conditions | Savings range |
|---|---|---:|
| Light, greenfield, no corpus intersection | No codemap, no ADR, no `/context` | **~0 tokens** |
| Moderate, in established project | 1× codemap consult, 0–1× `/context` | 10–25K |
| Heavy, multi-day arc | 1–2× codemap, 2–3× `/context`, 1× ADR, 1× Rule 22 catch | 30–80K |
| Refactor arc with prospect/retrospect | Plus prospect+retrospect cycle prevention | 60–150K+ |

---

## Measured quality findings

Sample sizes are now ~24–58× the v2.18.x revision (811 `/prospect` runs carrying a verdict and 336 `/retrospect` logs, vs 14 and 15).

### 1. Errors caught before execution (Evidence-Sourcing Pass) — *strongest evidence in this document*

This axis is new to the analysis, though the data has been accumulating since May. Both gates run an Evidence-Sourcing Pass that identifies unsupported premises in a plan and attempts to resolve each one against ground truth, recording the result in frontmatter. Unlike a verdict label, this is a **direct count of errors caught**, not a proxy for them.

Across **795 prospect runs** carrying a parseable block:

| Outcome | Count | % of candidates |
|---|---:|---:|
| Candidate premises examined | **2,928** | — |
| Upgraded → **validated** | 1,630 | 55.7% |
| Upgraded → **FALSIFIED** | **401** | **13.7%** |
| No movement (unresolvable in-pass) | 918 | 31.4% |

**401 premises a plan depended on were measured false before any code was written.** These are not stylistic corrections; a falsified premise is a plan whose stated basis was wrong.

⚠ **401 is a floor, not a level — and the gap is large.** The no-movement column is the tell: nearly a third of all examined premises were never resolved either way, because falsifications can only be found among premises the pass can actually settle. Most of this corpus predates the step-change in resolving power described in finding #2. *For illustration only:* at the current gate's measured yield of ~0.95 falsifications per run, the same 811-run corpus would have produced roughly **770** rather than 401.

On the retrospect side the same machinery runs against shipped work, and its most striking column is bundle verification:

| Retrospect sourcing outcome | Count |
|---|---:|
| Fix claims verified present in the shipped bundle | 711 |
| **Fix claims found ABSENT from the bundle** | **71** |
| Outcome claims validated | 700 |
| Outcome claims partially validated | 198 |
| Outcome claims **invalidated** | 10 |

**71 fixes were believed shipped and were not in the bundle.** That is the single most concrete "ARIA caught something vanilla tooling would not" number in this analysis — a green local test says nothing about whether the change reached the artifact.

**Signal strength: HIGH.** Numerator and denominator are both explicit in machine-readable frontmatter across 795/811 runs (98%); the measure does not depend on interpreting a verdict label.

### 2. Gate effectiveness, and why a *rising* needs-changes rate is a good sign

> **In plain terms — read this before the numbers.**
>
> When a gate reviews a plan, it lists the plan's assumptions and tries to check each one. Every assumption ends in one of three piles:
>
> 1. **confirmed true**
> 2. **proven false**
> 3. **couldn't tell**
>
> Only pile 2 forces a "needs changes" verdict. Pile 3 does nothing — an unchecked assumption leaves the plan *looking* fine.
>
> The gate used to land in pile 3 on **42%** of assumptions. It now lands there on **17%**. So it genuinely checks far more of each plan, finds more of the errors that were already there, and the "needs changes" percentage goes **up** as a result.
>
> **The one-line version:** this number tracks how well we *find* problems, not how many problems exist. It rose because the finding got better.
>
> It is the same shape as a hospital reporting more diagnoses after installing a better scanner. Patients did not get sicker; detection improved. Publishing "our patients are getting sicker" would be reading the scanner, not the patients — and that is exactly the error three prior revisions of this document made in the opposite direction, treating a *falling* rate as proof of rising quality.

#### What improved, measured three ways

Adjacent, non-overlapping windows either side of **2026-07-25**, the day the session model went Opus 4.8 → Opus 5. Per `/prospect` run:

| Gate yield, per run | Opus 4.8 (Jul 4–24, n=87) | Opus 5 (Jul 25–Aug 22, n=226) | Change | Status |
|---|---:|---:|---:|---|
| Premises examined | 3.49 | 4.26 | **+22%** | robust |
| Share of them settled | 57.6% | 80.6% | +23 pts | ⚠ **confounded — see below** |
| Premises **settled** per run | 2.16 | 3.44 | 1.6× | ⚠ same confound |
| **False premises caught** per run | 0.30 | 0.97 | **3.3×** | **robust — quote this one** |

**The robust finding is the last row: 3.3× more false premises caught before execution, per run.** A falsification requires positively establishing that a premise is false, so it cannot be manufactured by reclassifying anything. Premises-examined is likewise a plain count. Together they say the gate looks at more of each plan and catches materially more of what is wrong in it — the largest single movement in four months of quality data.

⚠ **The two middle rows are confounded, and an experiment run on 2026-08-22 is what found it.** Their complement is `no_movement`, which **pools two categorically different things**: premises the gate *attempted and could not settle* (capability-limited — a better model fixes these) and premises that are **🚫 Unverifiable-yet by design** — needing a package install, a running backend, live data, or a named human's review (**no model fixes these**). If the *composition* shifted between eras, the settled share rises with zero capability change.

The experiment was designed to separate them by re-gating pre-transition plans, and **died on its first target**: all six of that plan's unresolved premises were `NOT-ATTEMPTED by design`, so a re-run could not move them regardless of model. Attempting to settle the composition question from the logs instead also failed — the attempt-status markers over-count relative to the frontmatter tally (structural markers per `no_movement` premise: 0.80 in the 4.8 arm, **1.61** in the Opus 5 arm; a ratio above 1 proves prose mentions exceed tallied premises). ⇒ **The magnitude of the settled-share gain is unknown.** Some of the +23 points is real capability; how much is unmeasurable with the current schema. Full record: `logs/experiments/2026-08-22-attribution/RESULT.md`.

The monthly series shows the same thing, with June as the low point rather than a high one:

| Month | n | Premises/run | Share settled | **Falsifications/run** |
|---|---:|---:|---:|---:|
| May | 82 | 5.23 | 61.3% | 0.77 |
| June | 396 | 2.98 | 64.9% | **0.23** |
| July | 156 | 3.72 | 64.1% | 0.51 |
| August | 177 | 4.20 | **82.7%** | **0.95** |

#### The verdict distribution, and why it is retired as a quality measure

Of 811 `/prospect` runs carrying a verdict:

| Verdict | Count | % |
|---|---:|---:|
| **PROCEED-WITH-CHANGES** | 592 | **73.0%** |
| PROCEED (clean) | 197 | 24.3% |
| HOLD / kill | 22 | 2.7% |

By half-month, alongside the column that explains it:

| Window | n | Needs changes | Clean | Premises/run | **Unresolved / examined** |
|---|---:|---:|---:|---:|---:|
| May a | 18 | 78% | 17% | 7.00 | 37.3% |
| May b | 64 | 86% | 8% | 4.73 | 39.3% |
| Jun a | 213 | 66% | 33% | 3.26 | 36.7% |
| Jun b | 183 | 59% | 39% | 2.66 | 32.9% |
| Jul a | 49 | 65% | 33% | 3.24 | 42.8% |
| Jul b | 107 | 79% | 20% | 3.93 | 33.3% |
| **Aug a** | 115 | **91%** | 4% | 4.12 | **18.4%** |
| **Aug b** | 62 | 85% | 5% | 4.35 | **15.6%** |

Monthly, unresolved-per-examined runs **38.7% → 35.1% → 35.9% → 17.3%**: flat for three months, then halved.

**The mechanism.** Halving the unresolved rate moves ~20 percentage points of examined premises out of "unsettled" and into "settled." Those split into validated and falsified, and **every falsified one forces a needs-changes verdict**. So a plan of unchanged quality now produces a worse-looking verdict. The rate is a **sensitivity readout**: the unresolved share fell ~2.4× (42.4% → 17.3%), equivalently settled premises rose ~1.4× (57.6% → 82.7%). Quote whichever matches the question — "detection improved 2.4×" conflates them and overstates the gain.

**This cuts both ways, which is why the claim is retired rather than inverted.** June's flattering 63% needs-changes rate came from a gate examining the *fewest* premises per run (2.98) and settling the *fewest* of them (64.9%) — the cleanest-looking month was the least thoroughly checked one. The metric was never measuring plan quality in either direction.

⛔ **Therefore: prior revisions' reading of a falling needs-changes rate as evidence of rising plan quality is withdrawn, and no replacement trend claim is made.** Use the yield table above for evidence of gate effectiveness, and finding #1 for evidence of errors caught.

#### Locating the change: it is dated, and it is not a month boundary

**Nearly the whole verdict jump — 69.0% → 87.8% — lands in the seven days after the transition.** The gate's skill definition did not change across it (`/prospect`'s SKILL.md moved 623 → 624 lines over one commit, "make `/prospect` and `/retrospect` tracker-agnostic"). What changed was the model executing it.

⚠ **A control that failed, reported because the failure is instructive.** The first attempt to locate the change split the corpus at seven candidate dates and compared before/after. That showed a large gap at *every* late split date with no unique discontinuity at 07-25 — which reads as a drift, and is how this was first written up. **That instrument cannot distinguish a step from a drift**, because sliding the split date changes the composition of *both* buckets: the "before" side keeps absorbing pre-step data, so a genuine step also produces a monotone Δ. Adjacent non-overlapping windows are the correct instrument, and they show the discontinuity.

#### Rival explanations, and how each was ruled out

| Candidate cause | Test | Result |
|---|---|---|
| **`/auto` arc adoption** | Autonomous-arc judgment ledgers went **7 (Jul) → 69 (Aug)**, a 10× workflow change. If arcs drove it, the rate should jump with them. | **Ruled out.** The rate was already 87.8% in Jul 25–31, before the explosion, and moved only to 89.3% across it (+1.5 pts). *(A within-August split was attempted and is degenerate — 175 of 177 August runs fall on days that also carry an arc ledger.)* |
| **Plan size** | Mean `steps_count` by month. | **Ruled out; moves the wrong way.** August (6.98) ≈ June (6.95), the two extremes of the series. July had *larger* plans (8.38) and a *lower* rate. Size does predict verdicts in general — 61% at 2–4 steps, 72% at 5–9, 83% at 10+ — so this is a real driver that simply did not move here. |
| **Work mix** | Standardization decomposition: apply the earlier period's per-project rates to the later period's project mix. | **Real but minority.** June→August: mix **+8.7** of +26.4 pts (**33%**). July→August: mix **+1.9** of +14.9 pts (**13%**). The other 67–87% happened *inside* the same projects. |
| **The skill definition** | `git log` + line count on the gate's SKILL.md across the window. | **Ruled out.** One commit, +1 line, unrelated to strictness. |
| **Reasoning-effort level** | A *second* unversioned dial, and the obvious rival to the model itself. Effort is recorded per session in local transcripts (top-level `effort` field); compared across the boundary. | **Ruled out — measured unchanged.** `xhigh` was **70%** of pre-transition sessions (16 of 23) and **71%** after (169 of 238); no shift in mix. ⚠ Bound: local transcripts begin 2026-07-06, so this control covers the July transition only — May/June effort is unmeasurable, and the June figures in the series above therefore carry no effort control. |

Within-project needs-changes rates, which is what makes the decomposition legible (projects de-identified; only cells with n ≥ 15 are readable):

| Project | May | June | July | August |
|---|---:|---:|---:|---:|
| A — mature production web/backend | 80% (n=5) | 79% (n=44) | 71% (n=70) | **88% (n=104)** |
| B — CSS framework / design system | 71% (n=14) | 51% (n=86) | 75% (n=45) | — (n=3) |
| C — this plugin | 88% (n=17) | 65% (n=44) | — (n=7) | — (n=6) |
| D — client product monorepo | — | 52% (n=23) | 93% (n=15) | 88% (n=35) |

June's low aggregate comes from breadth — six projects with substantial n at ~51–65%. August's high aggregate is 59% one project, and **that project's own rate also rose 71% → 88%**, which is the within-project component the decomposition isolates.

#### What remains genuinely unresolvable

**One model change moved both the plan author and the gate runner**, because the same model does both. So "the plans contained more errors" and "the gate caught more of the errors already there" cannot be fully separated by this data. Two things can be said:

- The **unresolved-premise rate is unambiguously a gate-capability measure** — it counts premises the gate failed to settle, which says nothing about whether the plan was right. It halved. So at least that component is capability.
- The **falsified share of *settled* premises also rose** — 9.5% (Jun b) → 15.4% (Jul a) → 23.5% (Jul b) → 29.2% (Aug a) → 24.5% (Aug b). Better resolving power does not by itself explain that; either the gate also got better at correctly identifying falsity, or the plans really did contain more false premises, or both. This part stays confounded.

**An experiment was designed, gated and run to settle this on 2026-08-22. It returned no attribution result, and the reason is itself the finding.**

The design: re-gate pre-transition plans under the current model — same plans, different gate — with each repository pinned to a `git worktree` at the plan's contemporaneous commit so codebase drift could not masquerade as gate capability. Sample n=5, 37 premises, pre-registered falsifier bands, contamination guard against a frozen corpus baseline.

⛔ **Target 1 was unusable.** All six of its unresolved premises were recorded `NOT-ATTEMPTED by design` — they required a package install, a running backend, a live backfill inspection, or a named colleague's review. **No model resolves those by reasoning harder.** A re-run would have reproduced all six and read as a clean refutation of the hypothesis while actually measuring a defect in the sample.

**Re-selected on premise *category* rather than verdict, two runs completed: 1 of 2 settled.** ✅ One premise the 4.8 gate had left as *"fixture not located this pass"* was resolved at the pinned commit down to the fixture's name, file, line and semantics. ❌ The other turned out to be a **third** category — *unresolvable by absence*: the enum it asked about did not exist at that commit (zero `: String, Codable` declarations, positive-controlled against 146 `enum` declarations in the same tree). So a re-run **can** settle premises the older gate left open; that is now demonstrated rather than argued.

⛔ **But the population, not the design, is the limit.** Auditing all 19 attributable targets: 5 carried an `ATTEMPTED-FAILED` label, and reading their actual text showed **3 of those 5 were mislabelled structural** — so **the label is as unreliable as the tally**, and the entire attributable window contains roughly **one** genuinely capability-limited premise. n≈1 cannot size a 23-point gain.

That exposed the real problem, which is in the metric rather than the experiment: **`no_movement` pools capability-limited premises with structurally-unresolvable ones**, and the two respond to a better model in opposite ways. Falling back to settling the composition from the logs also failed — attempt-status markers over-count against the frontmatter tally (0.80 structural markers per `no_movement` premise in the 4.8 arm, **1.61** in the Opus 5 arm; above 1 proves prose mentions exceed tallied premises).

⇒ **The question stands open, and it is now known to be unanswerable from the current schema.** What would answer it is three fields rather than an experiment — split the tally at write time, and the next model transition is measurable from the logs on day one:

```yaml
sourcing_pass:
  no_movement_capability: N   # attempted, could not settle — a better model may fix
  no_movement_structural: N   # 🚫 needs execution / install / live data / a human
```

⚑ **Process note worth keeping.** The `/prospect` gate on that plan caught 4 of 6 stated premises before execution — and missed this one entirely, because the killer premise ("the unresolved premises in our sample are the kind a better model could resolve") was never written down as a premise by the plan *or* the gate. **A pre-mortem checks the premises you wrote; it cannot check the one you did not think to write.** Which is the argument for executing the smallest real slice early instead of perfecting the plan. Full record: `logs/experiments/2026-08-22-attribution/RESULT.md`.

**Signal strength: HIGH** for the yield table (three independent per-run measures moving together across a dated boundary) and for the verdict distribution as a *rate of intervention*. **The plan-quality-trend reading is withdrawn in both directions** on the grounds that a metric whose sensitivity changed mid-series cannot measure a trend in its subject.

### 3. Failure-mode pattern recognition (retrospect-patterns library)

| Metric | Value |
|---|---:|
| Canonical patterns in the cross-cutting library | **185** (at the moment of measurement; **186** after this session added one — see below) |
| At the v2.40.2 revision | 120 |
| At the v2.30.1 revision | 88 |
| At the v2.25.x revision | ~67 |
| At the v2.18.x revision | 27 |
| At v2.13.5 (origin) | 12 |
| Project-scoped `retrospect-patterns.md` libraries | 7 files, 41 patterns |
| Additional project pattern topic files | 86 |
| **Pattern hits recorded across gate logs** | **1,877** across 837 logs (72% of all gate runs) |
| Canonical patterns that have fired ≥1× | **107 of 185 (58%)** |

The library grew 120 → 185 canonical (+54%) and remains architecturally split: cross-cutting patterns in `rules/retrospect-patterns.md`, project-specific ones under `projects/<name>/`. Each canonical pattern was added because a retrospect identified the same failure mode at least twice — the library grows only on observed recurrence, and 58% of it has demonstrably fired in a logged run.

Most-hit patterns, which is where the library earns its keep:

| Hits | Pattern |
|---:|---|
| 96 | `guard-scoped-to-the-wrong-unit` |
| 88 | `architectural-claim-without-source-trace` |
| 61 | `open-sub-decisions-carried-into-execution` |
| 44 | `bundle-unverification` |
| 31 | `judgment-confused-with-evidence` |
| 28 | `fix-without-call-site-audit` |
| 27 | `green-gate-only-covers-its-sample-set` |

⚠ **A governance limit worth naming, and it is a real one.** 604 distinct pattern names appear across the gate logs; only 253 are defined as entries in any pattern file. Of the **231 names hit two or more times** — the recurrence bar that is supposed to trigger canonicalization — **143 have no canonical entry anywhere**, including the third-most-hit name in the corpus (61 hits). Pattern *naming* has outrun pattern *canonicalization*. This does not invalidate the 185 that exist, but it means the library is a lagging index of what the gates actually catch, and "185 patterns" understates the taxonomy in active use while overstating how much of it is written down.

**Signal strength: HIGH** for the library's catch rate on shipped work; **MEDIUM** for the library as a complete taxonomy — the 143-name backlog is the gap.

### 4. Validation discipline (retrospect per-fix verdicts + outcome distribution)

**(a) Validation honesty — per-fix verdicts.** Of 336 retrospects, **331 (98.5%) record explicit per-fix verdicts** (✅/KEEP/REVERT/REVISE) — "no fix marked shipped without named evidence." The rate is stable across four revisions now (97% → 98% → 98.5%) at ever-larger samples, and **notably it did not move across the model transition** — unlike the verdict distribution. That is what a structural measure looks like: it counts whether the discipline was followed, not how hard the gate could look. It is the most stable number in this document. Compare to vanilla Claude Code, where "done" means done because the assistant said so.

**(b) Aggregate outcome distribution.** Of 320 retrospects carrying an `overall_outcome`:

| `overall_outcome` | Count | % |
|---|---:|---:|
| closed | 164 | 51.3% |
| partial | 122 | 38.1% |
| mixed | 31 | 9.7% |
| unresolved | 3 | 0.9% |

"closed" remains the plurality (51.3%). By month: **31% (May) → 66% (June) → 49% (July) → 38% (August)**. This series spans the same instrument change as finding #2 and is subject to the same caution — a retrospect that verifies more thoroughly finds more residual work, so a falling "closed" share is not by itself a quality signal. **Do not read it as a trend.**

**Signal strength: HIGH** for per-fix-verdict presence (auditable, near-universal, stable across four revisions and one model transition); **the outcome series is not interpretable as a trend.**

### 5. Knowledge promotion gate (audit cadence + promotion rate)

| Metric | Value |
|---|---:|
| Audit passes (self-numbered ordinal, authoritative) | **117** |
| Dated entries in `logs/knowledge-audit-log.md` | 80 |
| Materialized `archive/audit-<date>/` sweeps | **47** (was 33) |
| Total canonical corpus | **952 files** across the six content dirs |

> **Corpus-count reconciliation (method preserved from the prior revision).** The 952 figure counts `.md` files in the six canonical content dirs (`approaches` 136 · `references` 102 · `projects` 672 · `rules` 8 · `guides` 17 · `decisions` 17), up from ~890. A broad `.md` sweep of the whole knowledge folder returns **3,260** (was ~2,400) — neither is wrong, they measure different sets. The content-dir count remains the reproducible one. Three audit denominators are equally defensible and are reported rather than blended: the log's own **117th-pass** ordinal, **80** dated entries, and **47** archived sweeps.

**The gate has become measurably more conservative.** Across the three most recent passes that read all backlog streams at body level:

| Pass | Entries read | Promoted | Rate |
|---|---:|---:|---:|
| 117th | 148 | 10 | 6.8% |
| 116th | 266 | 9 | 3.4% |
| 115th | 187 | 15 | 8.0% |
| **Pooled** | **601** | **34** | **5.7%** |

That is down from the ~10–12% capture-fold rate reported last revision — consistent with a saturating corpus, where a growing share of new captures duplicates material already promoted. **~94% of reviewed entries never promote.** The gate is doing its job; the human is still the gate.

**Signal strength: HIGH** for cadence and for the promotion rate (clean numerator/denominator pairs from three consecutive full-read passes).

### 6. Convergence speedup (single real-session example)

| Metric | With ARIA's Active Knowledge Surfacing | Pre-fix baseline |
|---|---:|---:|
| Turns to converge on correct fix | **5** | 9 |
| Reduction | **44%** | — |

No new controlled convergence data has been gathered since. **Signal strength: MEDIUM** — single data point, baseline is a retrospective claim about the same scenario type, not an A/B test.

### Summary — what ARIA measurably improves

1. **Gate effectiveness, and it rose sharply this window.** Per run: premises examined 3.49 → 4.26 and **false premises caught 0.30 → 0.97 (3.3×)** — both robust counts. (Share-settled also rose 57.6% → 80.6%, but that figure is **confounded** and its magnitude is unknown — see finding #2.)
2. **Catching false premises before execution.** 401 premises measured false across 795 prospect runs — a direct count, not a proxy, and a floor rather than a level.
3. **Catching work that did not actually ship.** 71 fixes believed shipped were found absent from the bundle; 10 outcome claims invalidated outright.
4. **Pre-execution plan rigor.** `/prospect` flagged 73.0% of 811 plans for correction before they shipped as written — 89% under the current gate, which settles far more of what it examines.
5. **Post-ship verification honesty.** 98.5% of retrospects (331/336) carry explicit per-fix verdicts — stable across four revisions, three doublings of sample size, and one model transition.
6. **Failure-mode pattern recognition.** 185 canonical patterns, 58% of them demonstrably fired, 1,877 recorded hits across 72% of gate runs.
7. **Knowledge accumulation discipline.** A conservative human-gated model promoting ~5.7% of reviewed entries into a 952-file corpus.
8. **Diagnostic convergence speed.** 44% turn-count reduction on at least one real session.

### Summary — what ARIA does NOT measurably improve

1. First-time, novel-domain code quality (no corpus to draw from)
2. Single-edit decisions (Rule 22 ceremony cost > benefit at this scale)
3. Cross-developer applicability (N=1 evidence base)
4. Long-tail decision quality (months-out value uncomputable here)
5. Counterfactual "would have been wrong" cases — with one narrowing: a *falsified premise* is closer to proof of avoided error than a corrected plan is, though still not proof the uncorrected plan would have shipped wrong

**And one item that belongs here as a measurement limit rather than a shortfall:** the **trend in underlying plan quality** is not measurable from this corpus. The gates' sensitivity changed mid-window, so the verdict and outcome series track the instrument as much as the subject. **This is not a finding that plan quality declined** — the gate-yield table shows the gates catching more, not the work getting worse. It means one particular number should not be quoted as a quality trend in either direction.

---

## When ARIA pays off

ARIA is **net-positive in token cost, wall-clock, AND output quality** when sessions meet at least one of:

1. **Codemap-bearing project.** The codebase has a CODEMAP.md and you don't already hold the structural model. Orientation savings dominate the per-session cost.
2. **Persistent-arc work.** Multi-session work where this session's decisions get referenced next session. The capture → promote → apply cycle compounds.
3. **Critical-path editing.** Edits where shipping wrong has asymmetric cost (auth, migrations, schemas, routing, external services). **This revision's August data is the case in point:** on exactly this work mix, the gates falsified ~1 premise per run.
4. **Knowledge-corpus intersection.** Work touches a domain with 5+ relevant promoted files. `/context` retrieval + Active Knowledge Surfacing pay off.
5. **A high-capability model to spend.** New this revision, and the effect is large: the same gate definition on the same author's work went from settling 58% of a plan's premises to 83%, and from 0.30 to 0.97 falsifications per run. ARIA's gates are **leverage on model capability**, not a substitute for it. This is the direct answer to "won't better models make this unnecessary?" — measured here, better models made it *more* productive, because the gates are what aim that capability at a plan's premises and record the result.

## When ARIA does NOT pay off

1. **Single-file or scratch work.** One-off scripts, throwaway prototypes, isolated bug investigations. Rule 22 ceremony outweighs benefit for trivial changes.
2. **Greenfield + first-time domain — *only for token math*.** No codemap, no ADRs, no relevant references means corpus-based savings aren't there yet. **However:** if the work is non-trivial enough to benefit from a Rule 22 assessment or a `/prospect` pre-mortem, those fire from session 1. The "doesn't pay off" case is about token economics, not output quality.
3. **No-edit conversational work.** Q&A, design exploration, architectural debate without code output. Most per-edit cost doesn't fire, but the ~5,850-token fixed cost (mostly cache-eligible) remains.

### Early-adopters

**Quality is net-positive from session 1; only token-arithmetic catches up at ~2–4 weeks.** The full per-session cost lands immediately (~9,100–70,850 tokens depending on edit volume, mostly cache-eligible); corpus-based savings require a corpus that doesn't exist yet.

**Two of the three largest cost increases this revision do not apply to a new user at all** — the 1,776-byte user-rules index requires rules you have authored, and the 550-byte autonomy directive requires a non-default posture. A fresh default install pays the ~5,850-token steady state, of which the universal floor grew only ~84 tokens since the last revision.

**Quality benefits carry no early-adopter cost.** Rule 22 edit discipline, `/prospect` pre-mortems and their Evidence-Sourcing Pass, `/retrospect` per-fix validation, and the 185-pattern library all ship with the plugin and apply from session 1. **None of the headline quality numbers depend on corpus size** — the 401 falsified premises were caught by measuring the codebase in front of the gate, not by consulting accumulated knowledge.

**Where the token-savings curve crosses** — roughly when the corpus reaches:
- **~50+ promoted knowledge files**
- **3+ CODEMAPs** across active projects
- **Audit cadence sustained** at ≤14 days

(The author's corpus is well past all three — 952 canonical files, multiple CODEMAPs, 117 audit passes — which is the regime the savings estimates assume.)

**Net:** for non-trivial work, ARIA is value-positive from day one. Token-side break-even arrives at ~2–4 weeks.

---

## Decision-quality benefit vs token math

The token math captures only *direct context costs and savings*. It does not capture prevented re-ship cycles, corrected architectural claims, or failure-mode recognition.

This revision sharpens the argument twice over.

**First, the evidence got harder.** Previously the strongest claim was a verdict rate — "two thirds of plans needed changes" — which a skeptic could reasonably discount as nitpicking. It is now a **count of specific false premises caught before execution (401, and ~1 per run at the current gate's yield) and specific fixes caught as never-shipped (71)**. Those are errors that would otherwise have surfaced during or after execution, at multiples of the cost.

**Second, it reframes what the gates are for.** The largest movement in four months of quality data came from the model getting better at settling a question against ground truth — and ARIA's yield rose 3.3× alongside it. The gates do not supply that capability; they **spend** it, on the premises a plan is resting on, before the code is written. Without a gate, nothing enumerates a plan's assumptions, nothing tries to settle them, and nothing records which ones turned out false. That makes ARIA's value a rising function of model capability rather than a fixed overhead awaiting obsolescence.

For workflows where decision quality matters more than token cost — which is most operationally applied AI coding work — the case for ARIA is stronger than the token-only math suggests. And it is strongest precisely where the stakes are highest: on the asymmetric-cost work where a plan's premises are most likely to be wrong and most expensive to get wrong.

---

## What this analysis is NOT claiming

- **Not a "use ARIA universally" recommendation.** Match the tool to the workflow.
- **Not a controlled-study claim.** N=1 evidence base. No A/B comparison. No inter-developer variance data.
- **Not a claim that anything got worse.** The needs-changes rate rose, and that is a detection effect: over the same window the gates examined more premises per run, settled more of them, and caught 3.3× more false ones. Nothing here indicates a regression in the plugin, the gates, or the work.
- **Not a claim about the trend in underlying plan quality, in either direction.** Retired this revision because the instrument's sensitivity changed mid-series on a datable day. Prior revisions' readings of a falling rate as rising quality are superseded.
- **Not a controlled model comparison.** The Opus 4.8 → Opus 5 finding is an observational before/after on one author's corpus, with work mix moving at the same time and no randomization. It locates *when* the gate's behaviour changed and rules out four rival causes; it does not measure model quality.
- **Not a claim that a falsified premise equals a prevented bug.** It equals a plan whose stated basis was wrong, corrected before execution. Strong, but not the same thing.
- **Not a "tokens-only" verdict.** Decision-quality benefits are real but not directly tokenizable. Additive to the token math, not captured by it.
- **Not a "use ARIA without modification" recommendation.** Like any opinionated tool, ARIA fits some workflows better than others.

## Revision triggers — when to re-evaluate

- ⭐ **The session model — or the reasoning-effort level — changes.** New this revision and now the **first** trigger, because the model transition produced the largest measured movement in the quality data, larger than work mix, plan size, and workflow changes combined. On any such transition, re-measure per-run gate yield (premises examined, share settled, falsifications per run) before comparing verdict rates across the boundary. **Corollary: gate logs should carry BOTH a `model:` and an `effort:` frontmatter field.** Neither exists today, which is why establishing the 2026-07-25 date and ruling out effort as its cause both required transcript archaeology rather than a one-line query. **Two fields, because they are independent dials and either can move alone** — this revision found the model changed and effort did not, and the opposite is equally possible.
  ⭐ **And a third requirement, which is the only durable output of the 2026-08-22 experiment: split the `no_movement` tally at write time.**
  ```yaml
  sourcing_pass:
    no_movement_capability: N   # attempted, could not settle — a better model may fix
    no_movement_structural: N   # 🚫 needs execution / install / live data / a human
  ```
  Pooled, as it is today, the field cannot distinguish "the gate got better" from "this month's plans had fewer execution-gated premises" — which is exactly why the experiment built to settle that question could not run. Split, the next model transition is answerable from the logs on day one at zero extra cost. **Five fields total (`model`, `effort`, and the split) turn a multi-day investigation into a query.** Both are recoverable from local transcripts *while those transcripts survive* (`message.model` and a top-level `effort` field), which is precisely the fragility that makes recording them in the log worth doing: the effort control above could only reach back to 2026-07-06 because that is where local transcripts start.
- Your active project count drops below ~3 (knowledge-corpus intersection thins)
- Audit cadence stretches beyond ~14 days (operational discipline failing)
- A future Claude Code version ships a competing memory primitive (first-class persistent context native to the harness) that makes ARIA's capture pipeline partially redundant
- Anthropic ships a category-aware MCP capability-probe API that obsoletes ARIA's prose-only probe pattern (ADR-015 explicitly anticipates this)
- **The skill-discovery budget squeeze recurs.** Live 19,541 B against a 19,968 B tripwire is ~2% headroom — the same position as last revision, which was resolved by *raising* the budget from 18,944. Treat this as a recurring per-skill decision: each addition forces trim-or-raise. **Re-measure skill-discovery + SessionStart bytes every major release**, and prefer the same-state hook differential (recipe below) over comparing to a recorded number.
- ⭐ **Per-edit hook latency is no longer flat.** It roughly doubled this window (98 → 180 ms, 108 → 200 ms). Two more doublings would put a 100-edit session into the minute range, at which point wall-clock stops being a footnote. Re-measure per release.
- ⭐ **One hook's cost now scales with the corpus.** `pre-external-fetch-check.sh` greps the corpus (3,260 files → ~1.7 s). If the corpus doubles, so does that hook. Watch for it needing an index rather than a scan.
- ⚠ **The pattern-canonicalization backlog (143 recurring names undefined) needs draining or the library stops being a usable index of what the gates catch.**

---

## Reproducing the measurements

⚠ **Four of the prior revision's recipes returned wrong answers this pass, and one *new* control failed. Corrected versions are below — the errors are the durable part, so each is named.** Set `KB` to your configured knowledge folder first:

```bash
KB=~/Projects/knowledge   # your configured knowledge folder
```

### Cost side

```bash
# Hook output bytes (SessionStart is state-dependent — this is YOUR local total, not the floor)
echo '{}' | bash plugin-claude-code/bin/session-start-check.sh | wc -c
echo '{"file_path":"/tmp/x"}' | bash plugin-claude-code/bin/post-edit-check.sh | wc -c

# Skill-discovery surface bytes (universal fixed cost; scales with skill count)
total=0
for f in plugin-claude-code/skills/*/SKILL.md; do
  b=$(awk '/^description:/{flag=1; print; next} flag && /^[a-z_-]+:/{flag=0} flag {print}' "$f" | wc -c)
  total=$((total+b))
done; echo "$total bytes (~$((total/4)) tokens)"
grep -n 'ARIA_SKILL_BUDGET=' release.sh    # the tripwire to compare against
```

**Same-state attribution differential (the recipe to prefer).** Comparing today's byte count to a number recorded a month ago conflates plugin growth with local-state change. Hold the environment constant instead — extract the old hook and run both:

```bash
mkdir -p /tmp/ariaold/bin
for f in session-start-check.sh config.sh lib-index-match.sh lib-session-state.sh lib-tracked-artifacts.sh; do
  git show "v2.40.2:plugin-claude-code/bin/$f" > "/tmp/ariaold/bin/$f" 2>/dev/null
done
echo '{}' | bash /tmp/ariaold/bin/session-start-check.sh          | wc -c   # old hook, same state
echo '{}' | bash plugin-claude-code/bin/session-start-check.sh    | wc -c   # new hook, same state
```

Then split by segment marker (`RULE 22 ORDERING`, `SESSION STATE`, `DECISION ROUTING`, `STANDING USER RULES`, …) to see which segments moved and whether each is universal or opt-in. **Do not publish a total without that split** — this revision's raw +46% is mostly opt-in surface.

**Latency:** put the clock *outside* the process spawn. Timing each run with two `python3` invocations adds ~50–60 ms per sample, which inflates an 8 ms hook by ~3×. Time N iterations in one wrapper and take the minimum.

### Quality side

**Measure gate YIELD first — it is the metric that means what it appears to mean.** Per-run premises examined, share settled, and falsifications per run. The verdict distribution is downstream of all three and moves with the gate's sensitivity, so it should never be quoted as a quality trend on its own.

```bash
# Per-run yield over a window (edit the date bounds)
python3 - <<'PY'
import glob, re, datetime, os
KB = os.path.expanduser('~/Projects/knowledge')
LO, HI = '2026-07-25', '2026-08-22'
n = c = v = f = nm = 0
for p in glob.glob(f'{KB}/logs/prospect/*.md'):
    m = re.search(r'/(2026-\d\d-\d\d)', p)
    if not m or not (LO <= m.group(1) <= HI): continue
    fm = open(p, encoding='utf-8', errors='replace').read().split('\n---', 1)[0]
    if not re.search(r'^overall_verdict:', fm, re.M): continue
    g = lambda k: int(x.group(1)) if (x := re.search(rf'^\s+{k}:\s*(\d+)', fm, re.M)) else 0
    n += 1; c += g('candidates'); v += g('upgraded_validated')
    f += g('upgraded_falsified'); nm += g('no_movement')
print(f"runs {n} | premises/run {c/n:.2f} | settled {100*(c-nm)/c:.1f}% "
      f"| falsified/run {f/n:.2f} | validated/run {v/n:.2f}")
PY

# Verdict distribution (downstream of the above; some values carry trailing '#' comments)
grep -h '^overall_verdict:' "$KB"/logs/prospect/*.md | sed 's/#.*//' | awk '{print $2}' | sort | uniq -c

# Evidence-Sourcing Pass totals — prospect (2-space indent, flat block)
for k in candidates upgraded_validated upgraded_falsified no_movement; do
  printf '%-22s' "$k"
  grep -h "^  $k:" "$KB"/logs/prospect/*.md | awk '{print $2}' | paste -sd+ - | bc
done

# Retrospect outcomes + per-fix-verdict presence
grep -h '^overall_outcome:' "$KB"/logs/retrospect/*.md | sed 's/#.*//' | awk '{print $2}' | sort | uniq -c
grep -lE '✅|KEEP|REVERT|REVISE' "$KB"/logs/retrospect/*.md | wc -l

# Canonical pattern count (cross-cutting library)
grep -cE '^## [a-z0-9]+(-[a-z0-9]+)+$' "$KB"/rules/retrospect-patterns.md
```

**Which model produced a gate run.** No `model:` field exists in gate frontmatter (see revision triggers). Until one does, recover the timeline from transcript metadata — and state the sampling bound, because a truncated window makes an era's *start* look later than it was:

```bash
python3 - <<'PY'
import glob, json, os, collections
seen = collections.defaultdict(list)
for fp in sorted(glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')))[-160:]:
    try:
        for i, line in enumerate(open(fp, encoding='utf-8', errors='replace')):
            if i > 40: break
            o = json.loads(line)
            m, ts = (o.get('message') or {}).get('model'), o.get('timestamp')
            if m and ts: seen[m].append(ts[:10]); break
    except Exception: pass
for m, ds in sorted(seen.items(), key=lambda x: -len(x[1])):
    print(f"{m:24} n={len(ds):4d}  first {min(ds)}  last {max(ds)}")
PY
```

**Locating a change in gate sensitivity.** Compute unresolved-per-examined (`no_movement / candidates`) over **adjacent, non-overlapping windows**, not by sliding a split date.

> ⚠ **Control that failed, and why it fails.** Splitting the corpus at successive dates and comparing before/after shows a large gap at *every* late date, with no unique discontinuity — which reads as a drift. It cannot distinguish a step from a drift, because sliding the boundary changes the composition of **both** buckets: the "before" side keeps absorbing pre-step data, so a real step also yields a monotone Δ. Use fixed adjacent windows of equal length either side of the candidate date.

**Separating work mix from within-project change.** A standardization decomposition: apply the earlier period's per-project rates to the later period's project mix. The gap between that counterfactual and the earlier actual is the **mix** effect; the remainder to the later actual is the **within-project** effect. Report both — an early draft of this revision published a mix explanation for something that was 67–87% within-project.

**Corrected recipe 1 — retrospect sourcing pass is NESTED, not flat.** The prospect recipe's `^  key:` pattern returns **0** on retrospect logs, which reads exactly like "the field doesn't exist." It does: retrospect nests two sub-blocks (`bundle_marker`, `outcome`) at 4-space indent, with different key names per block (`upgraded_verified` / `upgraded_not_in_bundle` vs `upgraded_validated` / `upgraded_partial` / `upgraded_invalidated`). Use `^    $k:` and parse per block — the two blocks share a `candidates` and a `no_movement` key, so a flat sum silently merges them.

**Corrected recipe 2 — audit passes are not `## `-delimited.** `grep -cE '^## '` on the audit log returns 66, *below* the prior revision's 114, implying the log shrank. It didn't; the log is a "Last Audit" block plus `- **Date:**` bullets, and each pass self-numbers in prose. Read the ordinal:

```bash
grep -oE '[0-9]+(st|nd|rd|th) pass' "$KB"/logs/knowledge-audit-log.md \
  | grep -oE '^[0-9]+' | sort -rn | head -1          # authoritative pass count
grep -cE '^- \*\*Date:\*\*' "$KB"/logs/knowledge-audit-log.md   # dated entries
ls -1d "$KB"/archive/audit-* | wc -l                             # materialized sweeps
```

**Corrected recipe 3 — scope `patterns_hit` to its own block.** A naive `^\s+- kebab-case$` sweep matches indented list items under *any* frontmatter key and reported **647 distinct patterns against a 185-pattern library** — a count exceeding its own universe, which is the tell. Parse only the lines under `patterns_hit:` (both the inline `[a, b]` and block-list forms appear), then intersect with the `^## ` headings in the pattern files.

**Corrected recipe 4 — project pattern libraries live in two places.** Scoping a census to `projects/*/retrospect-patterns.md` reports the corpus's third-most-hit pattern name as undefined. Patterns also live under `projects/*/patterns/*.md` (86 files) under varying heading conventions. Glob both before claiming a name is uncanonicalized.

> **General note on all of the above:** every census here needs a **positive control in the same invocation**. A `grep | wc -l` returning 0 is indistinguishable from a broken pattern, a missing path, or a shell quoting error — and four of this revision's first-pass numbers were wrong in exactly that way. State what the control was, not just the result. The same discipline applies one level up: a *control* can also be the wrong instrument for the question, as the split-date test above was.

> **Note on SessionStart bytes:** the figure is **state-dependent** — audit-due prefixes, config-audit prompts, project matches, CODEMAP staleness, `autonomy` posture, and a user-authored rules index each add bytes. The ~3,813-byte floor above is the universal guidance block; subtract the conditional segments to compare against it.

---

## Related

- [README.md](../README.md) — overall philosophy and feature surface
- [QUICKSTART.md](../QUICKSTART.md) — first-three-sessions walkthrough
- [non-goals.md](non-goals.md) — what ARIA explicitly does NOT do
- [release-validation.md](release-validation.md) — release-time validation patterns
