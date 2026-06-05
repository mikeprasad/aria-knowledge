# ARIA Value Analysis — Evidence Digest

**Last updated:** 2026-06-06 · **Plugin version analyzed:** v2.25.0 (cost surface re-measured at v2.25.1) · **Evidence base:** N=1 (plugin author's projects)

This document summarizes measured and estimated evidence for whether ARIA is *objectively valuable* when added to Claude Code. It accompanies the [README](../README.md)'s "Evidence and limits" framing with concrete numbers.

> **Limits up front:** All evidence below is from the plugin author's own multi-project work, run on high-capability reasoning models (historically Opus 4.7 High; recent sessions span into Opus 4.8). No controlled A/B study, no inter-developer variance data, no cross-model comparison. Treat these as **calibration anchors for high-capability reasoning models**, not universal claims — results on lower-tier models may differ.

> **What changed since the 2026-05-19 (v2.18.x) revision:** the corpus is now 10–13× larger (183 `/prospect` logs and 68 `/retrospect` logs vs 14 and 15). The headline plan-quality claim *held up* under the larger sample and is now far more robust. Three things needed honest correction: (1) the **total per-session fixed cost drifted ~1.6× higher for all users** (~3,150 → ~5,000 tokens), split across *both* fixed surfaces — the skill-discovery surface grew ~1.4× (~2,700 → ~3,875 tokens; more skills, not bytes-per-skill) and the SessionStart guidance block grew ~2.4× (~450 → ~1,100 tokens; more always-on guidance bytes as features shipped). The 1.6× is the combined figure; the "guidance bytes" cause applies only to the SessionStart component. (v2.25.1 has since trimmed the SessionStart block ~11% — reflected below.) (2) the "only 1 of 14 plans was clean" framing was small-sample noise — the clean-pass rate is now ~20% and *rising over time*; (3) the retrospect-outcome finding was reframed (see finding #3). Where larger samples revealed a time trend, it is reported with its confounds named.

---

## TL;DR

| Question | Answer |
|---|---|
| **What's the core value?** | **Better code, fewer errors, fewer turns.** Higher accuracy + better reasoning + early error catching, compounding into less rework. Without ARIA, the same errors get shipped, then debugged, then re-fixed, then re-verified — each cycle is multiples of the token cost of catching it pre-execution. |
| **Does ARIA measurably improve Claude Code's output?** | **Yes — across multiple axes, now on a 12× larger sample.** 76.6% of plans submitted to `/prospect` (131 of 171) needed pre-execution corrections; only 2.9% were killed outright. ~67 canonical failure-mode patterns (plus project-scoped libraries) catch repeat drift modes. Plan cleanliness is **improving over time** (see trend below). |
| **What does ARIA cost per session?** | **~5,000 tokens fixed + ~325 tokens per edit.** On heavy edit sessions: ~37K tokens total. (Up from the v2.18.x estimate — the fixed surface grew as features shipped; v2.25.1 trimmed the SessionStart portion ~11%; see "Measured cost surface.") |
| **What does ARIA save per session?** | **Direct: 0 to ~150K tokens** (depending on knowledge intersection — typically 20–60K for corpus-engaged sessions). **Indirect (much larger): the cost of work-shipped-wrong avoided.** A single `/prospect` catch (~3K tokens to run) typically prevents a 15K+ token do-wrong → fix-after → re-verify cycle. At a ~77% needs-changes rate on non-trivial plans, avoided-rework dominates the direct savings. |
| **What's the wall-clock impact?** | **Under 1% from hooks.** Per-edit hooks are unchanged (~90–110 ms); net positive when codemap orientation or revision-avoidance kicks in. |
| **When does ARIA pay off?** | Multi-session work, established codebase, critical-path edits, or domains with 5+ relevant promoted knowledge files. |
| **When does ARIA NOT pay off?** | One-off scratch sessions, greenfield-first-session work, no-edit conversational sessions. |
| **What's the early-adopter tax?** | **Small.** Quality is net-positive from session 1 — Rule 22, `/prospect`, `/retrospect` ship day-one and don't require a corpus. Token-arithmetic catches up at ~2–4 weeks, then turns positive as the corpus builds. |

---

## What's measured vs estimated vs unmeasurable

| Axis | Fidelity | Method |
|---|---|---|
| **Token overhead** | Measured directly | Ran hooks, counted bytes, computed token equivalents |
| **Hook latency** | Measured directly | 3 runs each, minimum reported |
| **Token savings** | Estimated with named assumptions | Counterfactual: what each artifact replaces |
| **Wall-clock impact** | Qualitative + measurable subcomponents | Hook latency measurable; orientation/revision speedup estimable |
| **Output quality** | Multiple measurable proxies | Verdict distributions, pattern recurrence, audit promotion rate |
| **Output-quality *trend*** | Measured distribution, **unproven causation** | Verdict/outcome distributions bucketed by month; confounds named |
| **Cross-developer applicability** | Not measured | N=1 only |
| **Long-tail value** | Not measured | Knowledge used 6+ months out is uncomputable in a session-scoped review |

---

## Measured cost surface

> **Important:** the per-session fixed cost grew since the v2.18.x revision, and the growth is **universal, not author-specific**. Each feature shipped across v2.19→v2.25 added a few hundred bytes of always-on guidance to the SessionStart block. Only a small audit-cadence prefix (~110 bytes) is state-dependent. Every plugin user pays the larger fixed surface.

### Per-session fixed overhead

Two fixed surfaces dominate, both paid by every session (modulo prompt caching):

1. **Skill-discovery surface** — descriptions of all installed skills, used by Claude Code's natural-language dispatch. At 32 skills this is **~15,500 bytes (~3,875 tokens)** per session (was ~10,800 bytes / ~2,700 tokens at the smaller skill count).
2. **SessionStart guidance block** — the hook injects Rule 22 ordering, task-budget awareness, memory pathway, and insight-capture instructions. Steady-state floor ≈ **~4,400 bytes (~1,100 tokens)** as of v2.25.1 (was ~4,980 bytes / ~1,240 tokens at v2.25.0; ~1,800 bytes / ~450 tokens at v2.18.x). v2.25.1 trimmed ~11% by gating the TASK BUDGET block to emit only the applicable statusline branch and collapsing current (non-stale) codemaps to a name-only list — no enforcement or behavior rule removed. A backlog-due prefix adds ~110 bytes; first-run welcome is a one-time ~260 bytes.

| Per-session fixed cost | Tokens |
|---|---:|
| Skill-discovery surface (32 skills) | ~3,875 |
| SessionStart guidance floor (v2.25.1) | ~1,100 |
| **Steady-state total** | **~5,000** |
| Worst-case (audit overdue + multi-pass + config-audit + version-upgrade) | ~5,300 |

### Per-edit variable overhead

The PostEdit hook emits a ~592-byte advisory after every Edit/Write (essentially unchanged from v2.18.x). Combined with Claude's Rule 22 marker + scope-check responses, total per-edit overhead ≈ **325 tokens**.

The PreEdit hook is **silent on compliant edits** (0 bytes) — only emits its denial block when a Rule 22 marker is missing.

### Total at typical edit volumes

| Edit count | Approximate total ARIA token cost |
|---:|---:|
| 10 (light session) | ~8,250 |
| 50 (moderate) | ~21,250 |
| 100 (heavy edit day) | ~37,500 |
| 200 (large refactor) | ~70,000 |

Most of the fixed portion is cache-eligible if the session stays warm, reducing the effective input cost by roughly 10× for those segments.

### Hook latency

| Hook | Min latency |
|---|---:|
| `session-start-check.sh` | 403 ms (one-time per session) |
| `pre-edit-check.sh` | 108 ms (per Edit/Write) |
| `post-edit-check.sh` | 98 ms (per Edit/Write) |
| `pre-explore-codemap-check.sh` | 7 ms (per Glob/Grep) |
| `bash-cd-check.sh` | 88 ms (per Bash call) |
| `task-context-check.sh` | 91 ms (per Task tool dispatch) |

`session-start-check.sh` grew (191 → 403 ms) as it gained audit-cadence + config-audit + version checks, but it runs once per session. The per-edit hooks — which dominate the total fire count — are unchanged. **Wall-clock impact at 50 edits:** ~10 seconds across an entire session. Under 1% of a typical 30-minute working session. **Wall-clock isn't the cost story; tokens are.**

---

## Estimated savings surface

These are counterfactual estimates — "what ARIA replaces vs what would otherwise be done." Each is calibrated against a stated alternative. (These are unchanged in method from the v2.18.x revision; the corpus has since grown well past the break-even thresholds noted under "Early-adopter tax.")

### CODEMAP precision savings

**Alternative without CODEMAP:** Re-orient in a project via Glob + Read 5–10 files = 50–100 KB of context consumed.
**With CODEMAP:** Targeted Read of ~150 lines = ~3 KB consumed.
**Per-event delta:** ~10–22K tokens saved per "re-enter a project and orient" event.

### ADR avoidance (decision re-debate)

**Alternative without ADR:** Re-debate a settled architectural question = ~5–10K tokens of back-and-forth.
**With ADR:** Load the captured decision = ~3–5 KB.
**Per-recall delta:** ~5–7K tokens per ADR reference.

### `/context` selective load vs naive folder read

**Alternative without `/context`:** Load whole knowledge folder (now ~1,180 promoted files) or load nothing and ask blindly.
**With `/context <tag>`:** Selective load of 3–7 tagged files = ~30–60 KB.
**Per-event delta:** large reduction in tokens spent on knowledge surfacing per use; the ratio grows as the corpus does.

### `/extract` retention vs PreCompact-only

**Alternative without `/extract`:** Post-compaction transcript snapshots survive, but require re-derivation of insights at next-session start.
**With `/extract`:** Insights staged in backlog, promoted on audit, retrievable via `/context`.
**Per-promoted-item delta:** ~500–2,000 tokens of re-derivation avoided each time the topic appears.

### Rule 22 revision avoidance

**Alternative without Rule 22:** Same fix shipped wrong, retrospect catches it, re-ship cycle required.
**With Rule 22:** Pre-edit assessment catches the gap before code is written.
**Per-catch delta:** Estimated ~15K tokens per Rule 22 catch (based on at least one real session that converged in 5 turns instead of 9 — a 44% reduction).

### Aggregated per-session savings range

| Session class | Conditions | Savings range |
|---|---|---:|
| Light, greenfield, no corpus intersection | No codemap, no ADR, no `/context` | **~0 tokens** |
| Moderate, in established project | 1× codemap consult, 0–1× `/context` | 10–25K |
| Heavy, multi-day arc | 1–2× codemap, 2–3× `/context`, 1× ADR, 1× Rule 22 catch | 30–80K |
| Refactor arc with prospect/retrospect | Plus prospect+retrospect cycle prevention | 60–150K+ |

---

## Measured quality findings

This is the most important dimension and the hardest to measure rigorously. ARIA produces several auditable artifacts that allow proxy measurement of output quality. Sample sizes below are 4–12× larger than the v2.18.x revision.

### 1. Plan-quality intervention (`/prospect` verdicts)

Of 171 `/prospect` runs carrying a verdict (183 logs total):

| Verdict | Count | % |
|---|---:|---:|
| **PROCEED-WITH-CHANGES** | 131 | **76.6%** |
| PROCEED (clean) | 35 | 20.5% |
| HOLD / kill | 5 | 2.9% |

**Interpretation:** ~77% of plans needed pre-execution corrections, ~20% shipped clean, and under 3% were rejected outright. Without `/prospect`, the corrections would have been discovered *during* execution — at higher cost.

**The v2.18.x revision reported 78.6% PROCEED-WITH-CHANGES on n=14.** The larger sample confirms that headline (76.6%) with far better signal strength. It also corrects a small-sample artifact: the old "only 1 of 14 plans was clean" (7%) framing was noise — the clean-pass rate is ~20% and *rising* (below).

**Trend over time** — bucketed by month:

| Window | n | PROCEED-WITH-CHANGES | Clean PROCEED | HOLD / kill |
|---|---:|---:|---:|---:|
| Early May (≈ the v2.18.x cohort) | 24 | 79% | 8% | **12%** |
| Late May | 58 | 86% | 10% | 3% |
| June | 89 | 70% | **30%** | **0%** |

Plans entering `/prospect` are getting cleaner: outright kills fell 12% → 0% and first-pass-clean rose 8% → 30%.

**Caveats (this trend does NOT isolate ARIA as the cause):**
- **Author learning** — the plan author got better at writing plans over the same period; inseparable from "ARIA made plans better."
- **The tool trains its own user** — repeated `/prospect` use teaches the author to pre-empt what it flags. That *is* an ARIA effect, but a learning effect, not static quality.
- **Work-mix shift** — May skewed toward greenfield architecture work (inherently HOLD-prone); June skewed toward incremental polish (lower-risk by nature).

The honest claim is that the trend is **consistent with ARIA improving plan formation**, not that it proves it. `/prospect` also runs on non-trivial plans only — these rates are among complex plans, not all decisions.

**Signal strength: HIGH** for the distribution (concrete, measurable, repeatable); **MEDIUM** for the causal trend (real signal, confounded cause).

### 2. Failure-mode pattern recognition (retrospect-patterns library)

| Metric | Value |
|---|---:|
| Canonical patterns in the cross-cutting library | **~67** |
| Pattern count at v2.13.5 (origin) | 12 |
| Count at the v2.18.x revision | 27 |
| Plus project-scoped pattern libraries | `cs-builder/`, `df/`, `aria/` (new since the revision) |

The library more than doubled (27 → ~67 canonical) **and was architecturally split**: cross-cutting patterns live in `rules/retrospect-patterns.md`; project-specific ones live in `projects/<name>/retrospect-patterns.md`. Each canonical pattern was added because a retrospect identified the same failure mode at least twice. The library is calibrated against real shipped work, not theoretical anti-patterns.

**Signal strength: HIGH** for shipped work — pattern recurrence proves the library catches real drift modes.

### 3. Validation discipline (retrospect per-fix verdicts + outcome distribution)

Two distinct things are measured here, and the v2.18.x revision conflated them.

**(a) Validation honesty — per-fix verdicts.** Of 68 retrospects, **66 (97%) record explicit per-fix verdicts** (✅/KEEP/REVERT/REVISE) — "no fix marked shipped without named evidence." This is the durable signal of validation rigor, and it holds steady regardless of how the aggregate outcome lands. Compare to vanilla Claude Code, where "done" means done because the assistant said so.

**(b) Aggregate outcome distribution.** Of 61 retrospects carrying an `overall_outcome`:

| `overall_outcome` | Count | % |
|---|---:|---:|
| closed | 25 | 41% |
| partial | 23 | 38% |
| mixed | 12 | 20% |
| unresolved | 1 | 2% |

By month, clean "closed" outcomes rose **31% (May) → 56% (June)**.

**Reframe from the v2.18.x revision:** the old finding read "almost no retrospect claims a clean shipped outcome" as evidence of validation honesty. That inference was weak — outcome-label distribution measures *how much work shipped clean*, not *how rigorously it was checked*. With "closed" now the plurality (and a June majority), the old framing is retired. The rising closed-rate is *consistent with* work shipping cleaner over time (same confounds as finding #1), while the **97% per-fix-verdict rate** is the real, steady measure of validation discipline.

**Signal strength: HIGH** for per-fix-verdict presence (auditable, near-universal); **MEDIUM** for the outcome trend (confounded cause).

### 4. Knowledge promotion gate (audit cadence + promotion rate)

| Metric | Value |
|---|---:|
| Audit passes logged (cumulative) | **77** (was 24 in a 4-week window) |
| Total canonical corpus | **~1,180 files** |

The gate continues to operate as "the human is the gate." A deeper parse of the audit log (77 passes) shows the prior revision's single "~5% promotion rate" actually blended **two non-commensurable intake streams**, which is why it can't be reproduced as one clean number:

| Stream | Denominator | Promotion behavior | Measured rate |
|---|---|---|---:|
| **Transcript / subagent captures** | High-volume (50–178 per sweep) | Digest-reviewed; only the "novel tail" folds — the rest is per-task impl detail, correctly not promoted | **~10–12%** (clean pairs: 42→5, 51→5) |
| **Structured backlog entries** | Pre-curated (insights/decisions/ideas) | Dispositioned: promote / defer / reclassify / tracker / reject | Higher but heterogeneous (e.g. ~141 held → ~5 residual) |

The capture-fold rate (~10–12%) is the closest clean measure of gate conservatism, and it **confirms the gate is conservative** — ~88–90% of captures never promote. The ~1,180-file figure is the *total* canonical corpus (includes pre-ARIA and non-audit content), not an audit-promotion count, so it is not directly comparable to the prior "~113 promoted."

**Signal strength: HIGH** for cadence (measurable pass count) and capture-fold rate (clean numerator/denominator pairs); the blended single-rate framing from the prior revision is retired as non-reproducible.

### 5. Convergence speedup (single real-session example)

In one documented production session (cs-builder may18pm AUTO-PRESELECT-PROFILE-IMAGE fix):

| Metric | With ARIA's Active Knowledge Surfacing | Pre-fix baseline |
|---|---:|---:|
| Turns to converge on correct fix | **5** | 9 |
| Reduction | **44%** | — |

No new controlled convergence data has been gathered since.

**Signal strength: MEDIUM** — single data point, baseline is a retrospective claim about the same scenario type, not an A/B test.

### Summary — what ARIA measurably improves

1. **Pre-execution plan rigor.** `/prospect` flagged ~77% of plans (n=171) for correction before they shipped as written; outright kills are near zero and falling.
2. **Post-ship verification honesty.** 97% of retrospects carry explicit per-fix verdicts — "claimed done, shipped half" is structurally resisted.
3. **Failure-mode pattern recognition.** ~67 canonical patterns (plus project-scoped libraries) catch repeat drift modes the second+ time they appear.
4. **Knowledge accumulation discipline.** 77 audit passes; a conservative human-gated promotion model keeps the corpus signal-dense.
5. **Diagnostic convergence speed.** Active Knowledge Surfacing reduced turn-count by 44% on at least one real session.

### Summary — what ARIA does NOT measurably improve

1. First-time, novel-domain code quality (no corpus to draw from)
2. Single-edit decisions (Rule 22 ceremony cost > benefit at this scale)
3. Cross-developer applicability (N=1 evidence base)
4. Long-tail decision quality (months-out value uncomputable here)
5. Counterfactual "would have been wrong" cases (we can only prove plans were corrected, not that uncorrected plans would have shipped wrong)
6. **Causation behind the improving trends** (findings #1, #3) — confounded by author learning and work-mix shift

---

## When ARIA pays off

ARIA is **net-positive in token cost, wall-clock, AND output quality** when sessions meet at least one of:

1. **Codemap-bearing project.** The codebase has a CODEMAP.md, and you don't already have the structural model in working memory. Orientation savings dominate the per-session cost.
2. **Persistent-arc work.** Multi-session work where decisions or discoveries this session will be referenced next session. The capture → promote → apply cycle compounds.
3. **Critical-path editing.** Edits to files where shipping wrong has asymmetric cost (auth, migrations, schemas, routing, external services). Rule 22's per-edit overhead is trivially worth it when a single revision avoidance saves an entire re-ship cycle.
4. **Knowledge-corpus intersection.** Work touches a domain where you already have 5+ relevant promoted files. `/context` retrieval + Active Knowledge Surfacing pay off.

## When ARIA does NOT pay off

**ARIA's overhead doesn't earn its keep** when:

1. **Single-file or scratch work.** Small one-off scripts, throwaway prototypes, isolated bug investigations. The Rule 22 ceremony cost outweighs benefit for trivial changes.
2. **Greenfield + first-time domain — *only for token math*.** No existing codemap, no related ADRs, no relevant approaches/references means the corpus-based savings aren't there yet. **However:** if the work is non-trivial enough to benefit from a Rule 22 impact assessment or a `/prospect` pre-mortem, those quality interventions fire from session 1 and are typically worth the modest token overhead on their own. The "doesn't pay off" case is specifically about token economics, not output quality.
3. **No-edit conversational work.** Q&A sessions, design exploration, architectural debates without code output. Most of ARIA's per-edit cost doesn't fire, but the per-session fixed cost (~5,000 tokens, mostly cache-eligible) remains.

### Early-adopter tax

For new users, **quality is net-positive from session 1; only token-arithmetic catches up at ~2–4 weeks.** The full per-session cost lands immediately (typically ~8,250–70,000 tokens depending on edit volume, mostly cache-eligible); corpus-based token savings (codemap orientation, `/context` retrieval, ADR avoidance) require a corpus that doesn't exist yet.

**Quality benefits do *not* have an early-adopter tax.** Rule 22 edit discipline, `/prospect` plan pre-mortems, `/retrospect` per-fix validation, and the ~67-pattern retrospect-patterns library all ship with the plugin and apply from session 1. The ~77% needs-changes rate measured on `/prospect` runs does not depend on corpus size. If your work involves non-trivial plans or critical-path edits, the quality interventions typically pay for the modest token overhead on their own — well before any corpus accumulates.

**Where the token-savings curve crosses** — roughly when the corpus reaches:
- **~50+ promoted knowledge files** in the corpus
- **3+ CODEMAPs** across active projects
- **Audit cadence sustained** at ≤14 days

Once the corpus crosses those thresholds, savings reliably exceed cost on engaged sessions. (The author's corpus is now well past all three — ~1,180 files, multiple CODEMAPs, sustained cadence — which is the regime the savings estimates above assume.)

**Net:** for non-trivial work, ARIA is value-positive from day one. The early window is "quality is already net-positive while token-arithmetic catches up." Token-side break-even arrives at ~2–4 weeks.

---

## Decision-quality benefit vs token math

The token math above only captures *direct context costs and savings.* It does not capture the decision-quality benefits — the prevented re-ship cycles, the architectural-claim corrections, the failure-mode pattern recognition.

The ~77% needs-changes rate on `/prospect` runs (n=171) — with outright kills falling to zero over time — is the strongest evidence that ARIA improves *what Claude does*, not just *how cheaply Claude does it.* For workflows where decision quality matters more than token cost — which is most operationally applied AI coding work — the case for ARIA is stronger than the token-only math suggests.

---

## What this analysis is NOT claiming

- **Not a "use ARIA universally" recommendation.** Match the tool to the workflow.
- **Not a controlled-study claim.** N=1 evidence base. No A/B comparison. No inter-developer variance data.
- **Not a causal claim about the improving trends.** Findings #1 and #3 show output quality rising over time, but author learning and work-mix shift are unquantified confounds. "Consistent with ARIA working" ≠ "proves ARIA caused it."
- **Not a "tokens-only" verdict.** Decision-quality benefits are real but not directly tokenizable. They are additive to the token math, not captured by it.
- **Not a "use ARIA without modification" recommendation.** Like any opinionated tool, ARIA fits some workflows better than others. The honest scope conditions above describe what to expect.

## Revision triggers — when to re-evaluate

This analysis would need to be re-evaluated if:

- Your active project count drops below ~3 (knowledge-corpus intersection thins)
- Audit cadence stretches beyond ~14 days (operational discipline failing)
- A future Claude Code version ships a competing memory primitive (e.g., first-class persistent context native to the harness) that makes ARIA's capture pipeline partially redundant
- Anthropic ships a `~~category`-aware MCP capability-probe API that obsoletes ARIA's prose-only probe pattern (the underlying ADR-015 explicitly anticipates this revision trigger)
- The fixed per-session cost surface grows materially again (total rose ~1.6× — ~3,150 → ~5,000 tok — from v2.18 → v2.25 as features shipped; skill-discovery ~1.4× (~2,700 → ~3,875 tok) from more skills, SessionStart ~2.4× (~450 → ~1,100 tok) from guidance bytes; v2.25.1 trimmed SessionStart ~11% (~1,240 → ~1,100 tok) back. Re-measure the skill-discovery + SessionStart bytes each major release)

---

## Reproducing the measurements

The cost-side measurements above can be reproduced by anyone running the plugin:

```bash
# Hook output bytes (SessionStart is state-dependent; this is your local floor + any due-audit prefix)
echo '{}' | bash plugin-claude-code/bin/session-start-check.sh | wc -c
echo '{"file_path":"/tmp/x"}' | bash plugin-claude-code/bin/post-edit-check.sh | wc -c

# Skill-discovery surface bytes (universal fixed cost; scales with skill count)
total=0
for f in plugin-claude-code/skills/*/SKILL.md; do
  b=$(awk '/^description:/{flag=1; print; next} flag && /^[a-z_-]+:/{flag=0} flag {print}' "$f" | wc -c)
  total=$((total+b))
done; echo "$total bytes (~$((total/4)) tokens)"

# Hook latency
time bash plugin-claude-code/bin/session-start-check.sh < /dev/null
```

The quality-side measurements require a running corpus and follow the same pattern:

```bash
# Prospect verdict distribution
grep -h '^overall_verdict:' ~/Projects/knowledge/logs/prospect/*.md | sort | uniq -c

# Retrospect outcome distribution + per-fix-verdict presence
grep -h '^overall_outcome:' ~/Projects/knowledge/logs/retrospect/*.md | sort | uniq -c
grep -lE '✅|KEEP|REVERT|REVISE' ~/Projects/knowledge/logs/retrospect/*.md | wc -l

# Canonical pattern count (cross-cutting library)
grep -cE '^## [a-z0-9]+(-[a-z0-9]+)+$' ~/Projects/knowledge/rules/retrospect-patterns.md
```

> **Note on the SessionStart byte count:** the figure is **state-dependent** — a backlog-due audit prefix, a config-audit prompt, or a version-upgrade notice each add bytes. The ~4,400-byte floor (v2.25.1) reported above is the steady-state guidance block that every user receives; subtract any "audit suggested/recommended/overdue" prefix to compare against it. (It also varies slightly with the CODEMAP staleness report, which depends on git state.)

---

## Related

- [README.md](../README.md) — overall philosophy and feature surface
- [QUICKSTART.md](../QUICKSTART.md) — first-three-sessions walkthrough
- [non-goals.md](non-goals.md) — what ARIA explicitly does NOT do
- [release-validation.md](release-validation.md) — release-time validation patterns
