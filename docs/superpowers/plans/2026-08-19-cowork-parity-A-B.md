# Plan — cowork parity A + B (/interview guided cadence, /intake consolidation)

**Date:** 2026-08-19
**Repo:** `aria-knowledge`, branch `main`
**Authorization:** Mike, 2026-08-19 — "Close A+B+C first, release after."

**C is executed as a rescope, not a reduction.** Both of its blockers are measured, not
judged, and both are hard:

- **Description cap.** cowork's summed `SKILL.md` description budget is **8,722 / 9,000**,
  with empirical *install failure* at 9,233. B frees 959 (clip 286 + clip-thread 305 +
  extract-doc 368); C costs 2,702 (audit 404 + audit-share 440 + audit-style 424 +
  recap 829 + roadmap 605). Net **10,465** — over the hard cap by 1,465. `release.sh`
  fails the build, and past that number the plugin does not install.
- **Bash.** All five C skills declare `Bash` in `allowed-tools`. **0 of 27** cowork skills
  do; 25 of 36 canonical skills do (positive control). Cowork is skills-only with no
  shell. `audit-style` mines `~/.claude/projects/*.jsonl` via Bash plus a bundled Python
  script — impossible in a runtime with neither. `recap`'s commit/push/pull modes are pure
  git (3 of its 5 modes). Each needs a cowork-native redesign, which is a design decision
  per skill, not a port.

C therefore returns to Mike as a design question. A and B proceed now — and B *improves*
the constraint C is blocked by, so it is the correct first move regardless of C's outcome.

---

## Measured starting state

| Item | Canonical | Cowork |
|---|---|---|
| `/interview` cadence | `guided`=8 `socratic`=6 `battery`=11 | `guided`=**0** `socratic`=4 `battery`=5 |
| `/interview` size | 163 lines | 156 lines (92-line diff) |
| `clip` / `clip-thread` / `extract-doc` | **retired** to `skills/.archived/` (v2.33.0) | still shipping as 3 live skills |
| description budget | n/a | 8,722 / 9,000 (warn 8,500) |

---

## Global constraints

- **B is BREAKING for cowork users.** Three invocable skills stop existing under their own
  names. Per Rule 6 they are archived with pointer headers, never deleted, and their
  triggers must be absorbed into `/intake`'s description so discovery survives.
- **Cowork has no Bash and no MCP-free assumption.** `clip-thread` and `extract-doc` are
  MCP-consuming; `/intake`'s cowork variant must keep those paths, not inherit canonical's
  Bash-flavoured ones.
- **The description budget is the gate that bites.** Every description change is measured
  by `release.sh`, not estimated.
- Ports are hand-maintained, never regenerated (ADR-014). Cowork bodies may diverge; the
  *schema* may not.
- Shared working tree: stage named paths, never `git add <dir>` (that already swept a
  parallel session's `skills/index/SKILL.md` into a staged set this session).

---

## Tasks

### A — `/interview` guided cadence

- **A1** Diff canonical vs cowork `/interview`; classify each of the 92 lines as
  (i) cadence mechanism, (ii) cowork-divergent-by-design, (iii) incidental drift.
- **A2** Port the guided-cadence mechanism only: `guided` as default, dialogs of 1–4
  mutually-independent questions re-derived after each, `--socratic` pinned to grain 1,
  `--battery` opt-in and offered once past ~12 questions.
- **A3** Preserve cowork divergences: namespaced skill refs, no Bash, the platform-generic
  naming of the question affordance (so a runtime without a picker degrades rather than
  being instructed to use an absent tool).
- **A4** Verify: `guided` > 0 in cowork; `battery` no longer described as the default;
  description length unchanged (frontmatter untouched).

### B — `/intake` consolidation

- **B1** Read canonical's `/intake` dispatcher grammar and its `.archived/` pointer-header
  convention. Read cowork's `clip`, `clip-thread`, `extract-doc` bodies for the MCP paths
  that must survive.
- **B2** Extend cowork's `/intake` to dispatch by input shape — bare URL/text clips whole;
  `extract <src>` decomposes; `doc <src>` reflection artifact; `thread <id>` pulls via MCP.
  Keep cowork's MCP mechanics; do not inherit Bash-flavoured canonical text.
- **B3** Move the 3 skills to `plugin-claude-cowork/skills/.archived/` with pointer headers
  (Rule 6 — archive, never delete).
- **B4** Absorb their triggers into `/intake`'s description so `/clip`-shaped requests still
  route. This is the step that costs budget; measure after.
- **B5** Confirm `/audit-knowledge` Step 2f (Review Clippings) exists in cowork — canonical
  added it in v2.33.0 precisely because clipped items were otherwise never reviewed. If
  absent, that is part of the same consolidation, not a separate gap.
- **B6** Grep for dangling references to the three retired names across cowork.

### Shared

- **S1** Bump cowork 1.6.0 → **1.7.0** (breaking-ish minor: skills retired + a behavioural
  default changed; cowork is pre-2.0 and has used minor for capability change throughout).
- **S2** CHANGELOG entry naming A, B, the budget arithmetic, and C's two blockers.
- **S3** Full gates: repro suite, canonical plugin tests, cowork `release.sh` (which runs
  the description-budget preflight and the now-repaired template-parity check).

---

## Named risks

- **R1 — budget.** B4 absorbs 3 skills' triggers into one description. If `/intake`'s
  description grows by more than the 959 freed, the net is worse. **Measure after B4, before
  S1**; if over 8,500, trim `/intake`'s prose rather than dropping triggers.
- **R2 — discovery loss.** A user typing `/clip` after B must still land somewhere useful.
  The archived pointer headers plus absorbed triggers are the mitigation; verify by grepping
  the description for each retired name.
- **R3 — MCP path regression.** `clip-thread` and `extract-doc` carry cowork-only MCP
  mechanics. Copying canonical's `/intake` wholesale would silently drop them. Diff the
  cowork bodies into the new dispatcher rather than replacing.
- **R4 — A's 92-line diff contains non-cadence drift.** Porting it wholesale would import
  canonical's Bash assumptions. A1's classification is what prevents that.
- **R5 — shared tree.** Another session holds `skills/index/SKILL.md` in both cowork and
  canonical. Never stage by directory.
