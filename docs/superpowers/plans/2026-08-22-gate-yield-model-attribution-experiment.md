# Plan — Gate-yield model attribution experiment

**Date:** 2026-08-22 · **Status:** ⚠ **AMENDED post-`/prospect` — read §0 before §1** · **Owner:** this session
**Motivating document:** `docs/value-analysis.md` finding #2 ("What remains genuinely unresolvable")
**Gate:** `knowledge/logs/prospect/2026-08-22-file-gate-yield-model-attribution-experiment.md` — verdict **PROCEED-WITH-CHANGES**, 4 of 6 sourced premises falsified

---

## 0. Amendments (post-gate — these SUPERSEDE the sections named)

Original text below is retained unedited as the decision trail. Where §0 and a later section disagree, **§0 governs.**

### A0.1 — Sample: n=12 → **n=4**. Supersedes §3.

The stratification in §3 is unsatisfiable on its own pool. Measured 2026-08-22: restricting to originals on/after **2026-07-06** (the earliest date local transcripts can confirm model + effort, which §6 requires) leaves **25** targets on disk, of which only **6** were originally clean — not 8 — and **14 of the 25 sit in one repo**, so "≤3 per repo" caps the achievable n well below 12.

**Amended sample: n=4, drawn from the 6 attributable originally-clean targets, ≤2 per top-level repo:**

| # | Original prospect | Target |
|---|---|---|
| 1 | 2026-07-06 | `archetypes/docs/superpowers/plans/2026-07-06-engine-math-fixes.md` |
| 2 | 2026-07-06 | `collab/co-studio/docs/superpowers/plans/2026-07-06-doctype-registry-unification.md` |
| 3 | 2026-07-17 | `cs/docs/superpowers/specs/2026-07-17-m2m-accessgate-rename-spec.md` |
| 4 | 2026-07-21 | `cs/cs-mobile-native/docs/superpowers/specs/2026-07-21-feed-collapsing-chrome-design.md` |

All four are originally **PROCEED (clean)** — the discriminating arm. The 4-PWC control arm from §3 is **dropped**: at n=4 it would halve the discriminating sample to buy a control for "is the gate still behaving like a gate," which the four runs' own candidate counts already answer.

### A0.2 — ⭐ Run the sourcing pass ONLY, not the full gate. Supersedes §7 steps 5–6 and §8.

`/prospect` Step 2 mandates reading `rules/retrospect-patterns.md` — measured **566,694 bytes / 5,003 lines**, ~140K tokens *per invocation*. That is what made n=12 look infeasible.

**But the pattern library is not an input to the measurement.** Tracing the skill's own dependency chain: Step 2 loads patterns "for use in §4.4"; Step 3.5 (Evidence-Sourcing Pass) takes its candidates from **Step 3**. The four compared metrics — `candidates`, `upgraded_validated`, `upgraded_falsified`, `no_movement` — are produced entirely by Steps 0 → 3 → 3.5.

⇒ **Each re-run executes Steps 0, 3, 3.5 only.** Skip Step 2 (pattern library), Step 0.5 (surfacing — it would inject *today's* corpus, which is the un-pinnable confound in §4), and Steps 4–8 (report rendering). This drops ~140K tokens per run and makes n=4 comfortable.

⚠ **State this in the published result.** The re-run arm executes a documented sub-procedure of the original arm, not the identical procedure. The comparison holds because the sub-procedure's inputs and outputs are the same, but it is not a byte-identical replay.

### A0.3 — Contamination guard: routing → **post-hoc move + verify**. Supersedes §5 items 1 and 4.

§5 item 1 specifies writing reports to a custom directory. **No such capability exists.** The skill's full documented flag surface is `--branch --group --lens --linear --linear-post --no-source --plan --session --ticket --ticket-post --todos --tracker-post`; zero match `out-dir|output-dir|--out|log_dir` (measured with a positive control), and the skill hardcodes `<knowledge_folder>/logs/prospect/`.

**Amended guard — and A0.2 mostly dissolves the problem:** running Steps 0→3→3.5 only means **no report-writing step executes at all** (that is Step 6 of the skill), so nothing should land in `logs/prospect/`. The guard therefore becomes a *verification* rather than a *routing*:

1. ⛔ **Re-freeze the baseline as the first action of execution — do not use a number written here.** It was 832 when this plan was drafted and 833 minutes later, because this plan's own gate log legitimately joined the corpus. Other sessions write here too. A contamination check against a stale constant reports contamination that never happened, which is worse than no check.
   `BASELINE=$(ls -1 <kb>/logs/prospect/*.md | wc -l)` — capture it, print it, and use that variable.
2. Record the metrics manually into `logs/experiments/2026-08-22-attribution/`.
3. After **every** run: `ls -1 <kb>/logs/prospect/*.md | wc -l` must still equal `$BASELINE`. If it does not, move the stray file immediately and record that it happened.

⛔ Residual, stated not designed away: if a run unexpectedly does write a report, there is a window in which the corpus is contaminated. Recording the expected filename before each run makes a later sweep possible.

### A0.4 — Feasibility gate before run 1

First action of execution: one `git worktree add` + `git worktree list` round-trip in the `archetypes` repo. `git worktree add` is additive and does not move a shared HEAD, but it has not been exercised in these repos this session. Failure is loud, so this is a cheap precondition rather than a risk.

### A0.5 — Unchanged and load-bearing

§2's pre-registered falsifier and its 25–35% partial band **stand verbatim.** A smaller n makes pre-registration more important, not less. §9's known weaknesses stand, plus one added: **n=4 cannot produce a transferable effect size** — it can support or refute "the gate resolves far more on the same plans," nothing finer.

---

## 1. The question

`docs/value-analysis.md` establishes that on **2026-07-25** the session model went Opus 4.8 → Opus 5, and that across that boundary `/prospect`'s per-run yield moved sharply:

| Per run | Opus 4.8 (Jul 4–24, n=87) | Opus 5 (Jul 25–Aug 22, n=226) |
|---|---:|---:|
| Premises examined | 3.49 | 4.26 |
| Share settled | 57.6% | 80.6% |
| False premises caught | 0.30 | **0.97** |

Four rival causes were ruled out by measurement (`/auto` adoption, plan size, the skill definition, reasoning-effort level) and one was quantified as a minority contributor (work mix, 13–33%). **What cannot be separated from the observational data is whether the plans contained more errors or the gate caught more of the errors already present**, because one model change moved both the plan author and the gate runner.

**This experiment separates them.** Re-run *pre-transition plans* through the *current* gate. The plans are fixed; only the gate differs.

## 2. Hypothesis and named falsifier

**H1.** Re-gating pre-transition plans under Opus 5 yields an unresolved-premise share near the current ~17–21%, not the ~42% those plans originally recorded.

**Falsifier (must be stated before running).** If the re-runs land near **~40% unresolved**, H1 is dead: the gate's resolving power is not what moved, and the 2026-07-25 step must be attributed to the plans, the work, or an unidentified factor. A result between ~25% and ~35% is a **partial** — report it as such, do not round toward the hypothesis.

**Secondary observable.** Original verdict vs re-run verdict. The strongest single result would be an originally-**clean** plan coming back with falsified premises: that is the mechanism in the document ("an unresolved premise leaves a plan looking clean") demonstrated directly rather than inferred.

## 3. Sample

Measured 2026-08-22: **585** pre-transition prospect logs carry a verdict; **457** name a target `.md`; **168** of those targets still exist on disk, spread across 11 repos (`df` 40, `aria` 39, `cs` 39, `collab` 23, `devframe` 8, `archetypes` 7, `vox` 6, `roam` 3, `cfi`/`balm`/`shopsource` 1 each).

**n = 12, stratified deliberately, not randomly:**

- **8 originally PROCEED (clean)** — the discriminating subsample. H1 predicts the new gate finds premises the old one left unresolved *here specifically*. A random sample would be ~75% needs-changes and would mostly re-confirm what is already known.
- **4 originally PROCEED-WITH-CHANGES** — control arm; confirms the re-run is behaving like a gate and not like a rubber stamp.
- **No more than 3 from any one repo**, so a single codebase's drift cannot carry the result.

## 4. The confound that must be controlled, and how

⛔ **The codebases have moved since these plans were written.** A premise unresolvable in June may be resolvable today because the code changed — nothing to do with the model. Worse, a premise about code that no longer exists may return **falsified for the wrong reason**, inflating the exact number under test.

**Control:** for each selected plan, run the gate against a `git worktree` of its repo pinned to a commit contemporaneous with the original prospect date.

- `git worktree add` is **additive** — it does not move the main tree's HEAD, so it is safe alongside live parallel sessions. ⛔ **No `git checkout` in any shared working tree.**
- Worktree root: `/private/tmp/claude-501/.../scratchpad/attrib-<repo>-<date>/` (scratchpad, not inside any repo).
- Tear down every worktree at the end (`git worktree remove`), and verify removal.

**Residual, to be reported not hidden:** the *knowledge corpus* cannot be pinned this way — the gate reads today's corpus, which is larger than June's. That advantages the re-run on any premise answerable from accumulated knowledge. Classify each re-run falsification as **(a)** findable from the pinned repo alone, or **(b)** dependent on post-June knowledge, and report the split.

## 5. ⛔ Corpus contamination — must be solved before step 1

`/prospect` writes its report to `logs/prospect/`. **Twelve synthetic re-runs would be indistinguishable from real gate runs in the exact corpus `value-analysis.md` measures**, permanently biasing every future revision — including this experiment's own baseline.

**Required handling, verified before the first run:**
1. Write re-run reports to **`logs/experiments/2026-08-22-attribution/`**, never `logs/prospect/`.
2. Stamp every re-run's frontmatter `type: prospect-experiment` (not `prospect`) and add `experiment: gate-yield-attribution-2026-08-22`.
3. Add an exclusion to the reproduction recipes in `value-analysis.md` if any file lands under `logs/prospect/` regardless.
4. **Verify two-sided after run 1, before runs 2–12:** the new report exists in the experiment directory *and* `ls logs/prospect/ | wc -l` is unchanged from its pre-run count. If run 1 wrote to `logs/prospect/`, stop and fix the routing before continuing.

## 6. Recording (per Mike's instruction: model AND effort)

Every re-run records both dials, because they are independent and either can move alone:

| Field | Source |
|---|---|
| `model` | the executing session's model |
| `effort` | the executing session's reasoning-effort level |
| `original_log` | path to the pre-transition log being replayed |
| `original_model` / `original_effort` | recovered from transcripts where available; **`unrecorded`** where not — local transcripts begin 2026-07-06, so most pre-transition originals will be `unrecorded` and that must be written, not guessed |
| `repo_pinned_at` | the worktree commit |

⚠ **Hold effort constant across all 12 runs** and state the value. Varying it mid-experiment reintroduces the rival this experiment exists to exclude.

## 7. Steps

1. **Freeze the baseline.** Record `ls logs/prospect/*.md | wc -l` and the current yield figures. Contamination check depends on this number.
2. **Select the 12** per §3; write the manifest (plan path, repo, original date, original verdict, original candidates / no_movement / falsified) to the experiment directory.
3. **Recover original model+effort** for each, from transcripts; mark `unrecorded` where absent.
4. **Create one worktree** for the first selected plan, pinned per §4.
5. **Run the gate once.** Then execute §5 item 4 — the two-sided contamination check. Do not proceed until it passes.
6. **Runs 2–12**, one worktree each, torn down after each run.
7. **Tabulate**: per plan, original vs re-run unresolved share, falsifications, verdict. Report the aggregate against §2's falsifier bands.
8. **Classify** each re-run falsification (a)/(b) per §4's residual.
9. **Tear down all worktrees**; verify none remain (`git worktree list` per touched repo).
10. **Write the result into `value-analysis.md` finding #2**, replacing the "remains genuinely unresolvable" paragraph with whatever was measured — including a null or partial result stated as such.

## 8. Cost and stopping rule

12 gate invocations at held-constant effort, plus 12 worktree setup/teardowns. **Stopping rule:** if the first 6 runs all land inside one falsifier band (all <25% or all >35% unresolved), stop and report — the remaining 6 cannot change the verdict, and spending them is waste.

## 9. Known weaknesses, stated up front

- **Opus 4.8 is no longer available**, so there is no true A/B. The 4.8 arm is the *recorded* original, gathered under conditions that cannot be fully reconstructed. This is a before/after with one arm frozen in the past.
- **n=12 is small** and deliberately non-random. It can support "the gate resolves far more on the same plans" or refute it; it cannot produce an effect size that transfers.
- **The knowledge corpus cannot be pinned** (§4 residual).
- **Single author, single workflow.** Same N=1 limit as the parent document.
