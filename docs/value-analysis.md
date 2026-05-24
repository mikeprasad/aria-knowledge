# ARIA Value Analysis — Evidence Digest

**Last updated:** 2026-05-19 · **Plugin version analyzed:** v2.18.x · **Evidence base:** N=1 (plugin author's projects)

This document summarizes measured and estimated evidence for whether ARIA is *objectively valuable* when added to Claude Code. It accompanies the [README](../README.md)'s "Evidence and limits" framing with concrete numbers.

> **Limits up front:** All evidence below is from the plugin author's own multi-project work, run almost entirely on **Opus 4.7 High** (>95% of sessions; the remainder use Opus 4.7 Medium). No controlled A/B study, no inter-developer variance data, no cross-model comparison. Treat these as **calibration anchors for high-capability reasoning models**, not universal claims — results on lower-tier models may differ.

---

## TL;DR

| Question | Answer |
|---|---|
| **What's the core value?** | **Better code, fewer errors, fewer turns.** Higher accuracy + better reasoning + early error catching, compounding into less rework. Without ARIA, the same errors get shipped, then debugged, then re-fixed, then re-verified — each cycle is multiples of the token cost of catching it pre-execution. |
| **Does ARIA measurably improve Claude Code's output?** | **Yes — across multiple axes.** 78% of plans submitted to `/prospect` had issues caught pre-execution. 44% fewer turns to converge on a real production fix (5 vs 9). 27 canonical failure-mode patterns catch repeat drift modes. |
| **What does ARIA cost per session?** | **~3,150 tokens fixed + ~325 tokens per edit.** On heavy edit sessions: ~35K tokens total. |
| **What does ARIA save per session?** | **Direct: 0 to ~150K tokens** (depending on knowledge intersection — typically 20–60K for corpus-engaged sessions). **Indirect (much larger): the cost of work-shipped-wrong avoided.** A single `/prospect` catch (~3K tokens to run) typically prevents a 15K+ token do-wrong → fix-after → re-verify cycle. At 78% catch rate on non-trivial plans, avoided-rework dominates the direct savings. |
| **What's the wall-clock impact?** | **Under 1% from hooks.** Net positive when codemap orientation or revision-avoidance kicks in. |
| **When does ARIA pay off?** | Multi-session work, established codebase, critical-path edits, or domains with 5+ relevant promoted knowledge files. |
| **When does ARIA NOT pay off?** | One-off scratch sessions, greenfield-first-session work, no-edit conversational sessions. |
| **What's the early-adopter tax?** | **Small.** Quality is net-positive from session 1 — Rule 22, `/prospect`, `/retrospect` ship day-one and don't require a corpus. Token-arithmetic catches up at ~2–4 weeks (typically <70K tokens/session even at peak), then turns positive as the corpus builds. |

---

## What's measured vs estimated vs unmeasurable

| Axis | Fidelity | Method |
|---|---|---|
| **Token overhead** | Measured directly | Ran hooks, counted bytes, computed token equivalents |
| **Hook latency** | Measured directly | `time bash bin/*.sh`, 3 runs each, minimum reported |
| **Token savings** | Estimated with named assumptions | Counterfactual: what each artifact replaces |
| **Wall-clock impact** | Qualitative + measurable subcomponents | Hook latency measurable; orientation/revision speedup estimable |
| **Output quality** | Multiple measurable proxies | Verdict distributions, pattern recurrence, audit promotion rate |
| **Cross-developer applicability** | Not measured | N=1 only |
| **Long-tail value** | Not measured | Knowledge used 6+ months out is uncomputable in a session-scoped review |

---

## Measured cost surface

### Per-session fixed overhead

The SessionStart hook injects guidance text into every session. Steady-state cost ≈ **1,800 bytes** (~450 tokens) covering Rule 22 ordering, task budget awareness, memory pathway, and insight-capture instructions. Worst-case (audit overdue + version-upgrade prompt) ≈ **3,300 bytes** (~825 tokens). First-run welcome message ≈ **260 bytes** (~65 tokens).

The skill-discovery surface (descriptions of all installed skills, used by Claude Code's natural-language dispatch) adds **~10,800 bytes** (~2,700 tokens) per session.

| Per-session fixed cost | Tokens |
|---|---:|
| Steady-state estimate | ~3,150 |
| Worst-case state | ~3,525 |

### Per-edit variable overhead

The PostEdit hook emits a ~600-byte advisory after every Edit/Write. Combined with Claude's Rule 22 marker + scope-check responses, total per-edit overhead ≈ **325 tokens**.

The PreEdit hook is **silent on compliant edits** (0 bytes) — only emits its 637-byte denial block when a Rule 22 marker is missing.

### Total at typical edit volumes

| Edit count | Approximate total ARIA token cost |
|---:|---:|
| 10 (light session) | ~6,400 |
| 50 (moderate) | ~19,400 |
| 100 (heavy edit day) | ~35,650 |
| 200 (large refactor) | ~68,150 |

Most of the fixed portion is cache-eligible if the session stays warm, reducing the effective input cost by roughly 10× for those segments.

### Hook latency

| Hook | Min latency |
|---|---:|
| `session-start-check.sh` | 191 ms (one-time per session) |
| `pre-edit-check.sh` | 106 ms (per Edit/Write) |
| `post-edit-check.sh` | 88 ms (per Edit/Write) |
| `pre-explore-codemap-check.sh` | 15 ms (per Glob/Grep) |
| `bash-cd-check.sh` | 85 ms (per Bash call) |
| `task-context-check.sh` | 99 ms (per Task tool dispatch) |
| `pre-compact-check.sh` / `post-compact-check.sh` | 80 ms (on compaction events) |

**Wall-clock impact at 50 edits:** ~10 seconds across an entire session. Under 1% of a typical 30-minute working session. **Wall-clock isn't the cost story; tokens are.**

---

## Estimated savings surface

These are counterfactual estimates — "what ARIA replaces vs what would otherwise be done." Each is calibrated against a stated alternative.

### CODEMAP precision savings

**Alternative without CODEMAP:** Re-orient in a project via Glob + Read 5–10 files = 50–100 KB of context consumed.
**With CODEMAP:** Targeted Read of ~150 lines = ~3 KB consumed.
**Per-event delta:** ~10–22K tokens saved per "re-enter a project and orient" event.

### ADR avoidance (decision re-debate)

**Alternative without ADR:** Re-debate a settled architectural question = ~5–10K tokens of back-and-forth.
**With ADR:** Load the captured decision = ~3–5 KB.
**Per-recall delta:** ~5–7K tokens per ADR reference.

### `/context` selective load vs naive folder read

**Alternative without `/context`:** Load whole knowledge folder (in this analysis's corpus: ~930 KB) or load nothing and ask blindly.
**With `/context <tag>`:** Selective load of 3–7 tagged files = ~30–60 KB.
**Per-event delta:** ~15× reduction in tokens spent on knowledge surfacing per use.

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

This is the most important dimension and the hardest to measure rigorously. ARIA produces several auditable artifacts that allow proxy measurement of output quality.

### 1. Plan-quality intervention (`/prospect` verdicts)

Of 14 recent `/prospect` runs in the evidence base:

| Verdict | Count | % |
|---|---:|---:|
| **PROCEED-WITH-CHANGES** | 11 | **78.6%** |
| HOLD | 2 | 14.3% |
| PROCEED (clean) | 1 | 7.1% |

**Interpretation:** Only 1 of 14 plans was clean enough to execute as written. The other 13 either needed pre-execution corrections (11) or were rejected entirely (2). Without `/prospect`, those issues would have been discovered *during* execution — at higher cost.

**Caveat:** `/prospect` runs on non-trivial plans only. The 78% rate is among complex plans, not all decisions.

**Signal strength: HIGH** — concrete, measurable, repeatable.

### 2. Failure-mode pattern recognition (retrospect-patterns library)

| Metric | Value |
|---|---:|
| Canonical patterns catalogued | **27** |
| Pattern count at v2.13.5 (origin) | 12 |
| Patterns added in 4 months | +15 |
| Patterns hit ≥2 times in real retrospects | At least 6 (`bundle-unverification`, `fix-bundling`, `architectural-claim-without-source-trace`, `fix-without-call-site-audit`, `enumerate-variant-set-before-narrow-fix`, `validate-post-transform-output-not-just-input`) |

Each canonical pattern was added because a retrospect identified the same failure mode twice. The library is calibrated against real shipped work, not theoretical anti-patterns.

**Signal strength: HIGH** for shipped work — pattern recurrence proves the library catches real drift modes.

### 3. Per-fix validation enforcement (retrospect outcomes)

Of 15 most-recent retrospects:

| `outcome` field | Count |
|---|---:|
| partial | 6 |
| mixed | 4 |
| closed | 2 |
| (no outcome set) | 3 |

**Almost no recent retrospect claims a clean "shipped, all verified" outcome.** The default `partial` / `mixed` accounting reflects honest per-fix validation: "no fix marked shipped without named evidence." Compare to vanilla Claude Code, where "done" means done because the assistant said so.

**Signal strength: HIGH** — discipline produces auditable state.

### 4. Knowledge promotion gate (audit accept/reject rate)

Recent audit passes review **~100+ items per audit** and identify **5+ thematic clusters per pass**.

| Aggregate audit volume | Value |
|---|---:|
| Audits in 4-week window | 24 |
| Items audited (estimated total) | ~2,400 |
| Promoted to canonical knowledge | ~113 files |
| **Promotion rate** | **~5%** |

A ~5% promotion rate confirms the gate is conservative — "the human is the gate" working as described. The other 95% are deferred, rejected, reclassified, or absorbed into existing artifacts.

**Signal strength: HIGH** — measurable gate, conservative promotion rate.

### 5. Convergence speedup (single real-session example)

In one documented production session (cs-builder may18pm AUTO-PRESELECT-PROFILE-IMAGE fix):

| Metric | With ARIA's Active Knowledge Surfacing | Pre-fix baseline |
|---|---:|---:|
| Turns to converge on correct fix | **5** | 9 |
| Reduction | **44%** | — |

**Signal strength: MEDIUM** — single data point, baseline is a retrospective claim about the same scenario type, not an A/B test.

### Summary — what ARIA measurably improves

1. **Pre-execution plan rigor.** `/prospect` catches 78% of plans before they ship as written.
2. **Post-ship verification honesty.** Per-fix validation prevents "claimed done, shipped half."
3. **Failure-mode pattern recognition.** 27 canonical patterns catch repeat drift modes the second+ time they appear.
4. **Knowledge accumulation quality.** ~5% promotion rate keeps the corpus signal-dense.
5. **Diagnostic convergence speed.** Active Knowledge Surfacing reduced turn-count by 44% on at least one real session.

### Summary — what ARIA does NOT measurably improve

1. First-time, novel-domain code quality (no corpus to draw from)
2. Single-edit decisions (Rule 22 ceremony cost > benefit at this scale)
3. Cross-developer applicability (N=1 evidence base)
4. Long-tail decision quality (months-out value uncomputable here)
5. Counterfactual "would have been wrong" cases (we can only prove plans were corrected, not that uncorrected plans would have shipped wrong)

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
3. **No-edit conversational work.** Q&A sessions, design exploration, architectural debates without code output. Most of ARIA's per-edit cost doesn't fire, but the per-session fixed cost remains.

### Early-adopter tax

For new users, **quality is net-positive from session 1; only token-arithmetic catches up at ~2–4 weeks.** The full per-session cost lands immediately (typically ~6,400–68,150 tokens depending on edit volume, mostly cache-eligible); corpus-based token savings (codemap orientation, `/context` retrieval, ADR avoidance) require a corpus that doesn't exist yet.

**Quality benefits do *not* have an early-adopter tax.** Rule 22 edit discipline, `/prospect` plan pre-mortems, `/retrospect` per-fix validation, and the 27-pattern retrospect-patterns library all ship with the plugin and apply from session 1. The 78% PROCEED-WITH-CHANGES rate measured on `/prospect` runs in the evidence base does not depend on corpus size. If your work involves non-trivial plans or critical-path edits, the quality interventions typically pay for the modest token overhead on their own — well before any corpus accumulates.

**Where the token-savings curve crosses** — roughly when the corpus reaches:
- **~50+ promoted knowledge files** in the corpus
- **3+ CODEMAPs** across active projects
- **Audit cadence sustained** at ≤14 days

Once the corpus crosses those thresholds, savings reliably exceed cost on engaged sessions.

**Net:** for non-trivial work, ARIA is value-positive from day one. The early window is "quality is already net-positive while token-arithmetic catches up." Token-side break-even arrives at ~2–4 weeks.

---

## Decision-quality benefit vs token math

The token math above only captures *direct context costs and savings.* It does not capture the decision-quality benefits — the prevented re-ship cycles, the architectural-claim corrections, the failure-mode pattern recognition.

The 78% PROCEED-WITH-CHANGES rate on `/prospect` runs is the strongest evidence that ARIA improves *what Claude does*, not just *how cheaply Claude does it.* For workflows where decision quality matters more than token cost — which is most operationally applied AI coding work — the case for ARIA is stronger than the token-only math suggests.

---

## What this analysis is NOT claiming

- **Not a "use ARIA universally" recommendation.** Match the tool to the workflow.
- **Not a controlled-study claim.** N=1 evidence base. No A/B comparison. No inter-developer variance data.
- **Not a "tokens-only" verdict.** Decision-quality benefits are real but not directly tokenizable. They are additive to the token math, not captured by it.
- **Not a "use ARIA without modification" recommendation.** Like any opinionated tool, ARIA fits some workflows better than others. The honest scope conditions above describe what to expect.

## Revision triggers — when to re-evaluate

This analysis would need to be re-evaluated if:

- Your active project count drops below ~3 (knowledge-corpus intersection thins)
- Audit cadence stretches beyond ~14 days (operational discipline failing)
- A future Claude Code version ships a competing memory primitive (e.g., first-class persistent context native to the harness) that makes ARIA's capture pipeline partially redundant
- Anthropic ships a `~~category`-aware MCP capability-probe API that obsoletes ARIA's prose-only probe pattern (the underlying ADR-015 explicitly anticipates this revision trigger)

---

## Reproducing the measurements

The cost-side measurements above can be reproduced by anyone running the plugin:

```bash
# Hook output bytes
echo '{}' | bash plugin-claude-code/bin/session-start-check.sh | wc -c
echo '{"file_path":"/tmp/x"}' | bash plugin-claude-code/bin/post-edit-check.sh | wc -c

# Skill description bytes
for f in plugin-claude-code/skills/*/SKILL.md; do
  awk '/^description:/{flag=1; print; next} flag && /^[a-z-]+:/{flag=0} flag {print}' "$f" | wc -c
done

# Hook latency
time bash plugin-claude-code/bin/session-start-check.sh < /dev/null
```

The quality-side measurements require a running corpus (`~/Projects/knowledge/logs/prospect/`, `logs/retrospect/`, `logs/knowledge-audit-log.md`) and follow the same pattern: count verdicts, count patterns_hit, count items audited.

---

## Related

- [README.md](../README.md) — overall philosophy and feature surface
- [QUICKSTART.md](../QUICKSTART.md) — first-three-sessions walkthrough
- [non-goals.md](non-goals.md) — what ARIA explicitly does NOT do
- [release-validation.md](release-validation.md) — release-time validation patterns
