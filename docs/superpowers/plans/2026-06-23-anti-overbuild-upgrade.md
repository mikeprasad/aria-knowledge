# Anti-Over-Build Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a simplification-marker convention (Rule 13 clause) + an opt-in `overbuild` review lens (shared by `/prospect`, `/retrospect`, `/readiness-audit`) to aria-knowledge, ported from the Ponytail project — minimal footprint, no new skill, no new numbered rule.

**Architecture:** One new shared rules file (`overbuild-patterns.md`) holds the ladder + smell library; three existing review skills gain an opt-in `--lens=overbuild` mode (or per-surface probe) that reads it; existing Rule 13 gains a marker clause. Build + test fully on the canonical `plugin-claude-code` port first, then propagate to the other 4 ports (codex, cursor, antigravity, cowork) and re-baseline `PORT-LEDGER.json` — because ports are hand-maintained, NOT regenerated from canonical (per `check-port-drift.sh`: cursor compiles to `.mdc`, cowork has port-divergent bodies by ADR-014).

**Tech Stack:** Markdown (rules + skill docs), POSIX shell tests (`tests/test-*.sh` sourcing `test-lib.sh`, `assert_eq` idiom), `jq`, `rsync`-based release scripts, `PORT-LEDGER.json` sha256 drift ledger.

## Global Constraints

- **No new numbered working rule** — the marker is a CLAUSE on existing Rule 13 (working-rules.md, currently 35 rules). Verbatim bias: "Write only as much as needed" (Rule 28).
- **No new standalone skill** — the lens is a mode on 3 existing skills.
- **Marker token = `aria:simplification`** — verified collision-free across cs/ss/df on 2026-06-23. Do NOT change the token without re-running the collision grep.
- **The lens is OPT-IN** — bare `/prospect`, `/retrospect`, `/readiness-audit` must be byte-for-byte unchanged in behavior. The lens activates only on the explicit `--lens=overbuild` flag (prospect/retrospect) or as a named per-surface probe (readiness-audit).
- **`--lens=overbuild` slots into the existing "Modifier flags (apply to any scope)" mechanism** — verified present in both prospect & retrospect SKILL.md Step 0. Compose, don't rebuild the parser.
- **Every over-build finding must cite the failed ladder rung AND a concrete leaner alternative** — a finding that can't name the smaller version is suppressed (reuses prospect's existing discipline). Marker-respect: a hunk already carrying `aria:simplification` is reported "resolved (marked)", never flagged.
- **Canonical port = `plugin-claude-code/`.** Rules live at `template/rules/`; skills at `skills/<name>/SKILL.md`. Cursor port uses `knowledge/rules/` and compiles to `.mdc`.
- **Pattern entry format mirrors `retrospect-patterns.md` exactly:** `## <pattern-name>` / `**Tier:**` / `**First identified:**` / `**One-line summary:**` / `### Detection cues` / `### Why it's a problem` / `### Counter-discipline` / `### References`.
- **Version:** minor bump `2.35.x → 2.36.0`. CHANGELOG attribution per ADR-014.

## File Structure (canonical port; replicated to 4 others in Phase 2)

| File | Responsibility | Action |
|---|---|---|
| `plugin-claude-code/template/rules/overbuild-patterns.md` | The ladder + seed smell library — single source of truth | Create |
| `plugin-claude-code/template/rules/working-rules.md` | Rule 13 gains the simplification-marker clause | Modify (Rule 13, ~line 89) |
| `plugin-claude-code/skills/prospect/SKILL.md` | `--lens=overbuild` forward mode (plan-time) | Modify |
| `plugin-claude-code/skills/retrospect/SKILL.md` | `--lens=overbuild` backward mode (diff-time) + marker-respect | Modify |
| `plugin-claude-code/skills/readiness-audit/SKILL.md` | over-build per-surface probe (repo sweep) | Modify |
| `plugin-claude-code/tests/test-overbuild.sh` | Mechanical tests: marker regex + flag-documented lint | Create |
| `PORT-LEDGER.json` | Re-baseline the 5 changed surfaces × ports | Modify (Phase 2) |

---

## Phase 1 — Canonical port (plugin-claude-code), build + green

### Task 1: Marker grammar + its mechanical test

The only executable-testable artifact in this feature is the marker token's greppable shape. Lock it with a regex test FIRST so the convention has a machine-checkable definition the lens can rely on.

**Files:**
- Create: `plugin-claude-code/tests/test-overbuild.sh`

**Interfaces:**
- Produces: the canonical marker regex `aria:simplification — .+ \| limitation: .+ \| upgrade: .+` (skills and Rule 13 clause both reference this exact shape).

- [ ] **Step 1: Write the failing test**

```sh
# shellcheck shell=sh
# test-overbuild.sh — anti-over-build upgrade: marker grammar + lens-documented lint
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

# --- marker grammar: a well-formed aria:simplification marker matches; malformed ones don't ---
MARKER_RE='aria:simplification — .+ \| limitation: .+ \| upgrade: .+'

good='// aria:simplification — used native Date instead of date-fns | limitation: no TZ math | upgrade: add date-fns if TZ bugs appear'
bad_no_upgrade='// aria:simplification — used native Date | limitation: no TZ math'
bad_generic='// TODO: simplify this later'

assert_eq "marker: well-formed matches" "1" \
  "$(printf '%s\n' "$good" | grep -Eq "$MARKER_RE" && echo 1 || echo 0)"
assert_eq "marker: missing upgrade rejected" "0" \
  "$(printf '%s\n' "$bad_no_upgrade" | grep -Eq "$MARKER_RE" && echo 1 || echo 0)"
assert_eq "marker: generic TODO not a marker" "0" \
  "$(printf '%s\n' "$bad_generic" | grep -Eq "$MARKER_RE" && echo 1 || echo 0)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh plugin-claude-code/tests/run.sh 2>&1 | grep -A3 test-overbuild`
Expected: FAIL — `test-overbuild.sh` exists but the suite has no `overbuild-patterns.md` yet to anchor the regex; at minimum the file is new and unverified. (If `run.sh` sources it cleanly and all 3 asserts already pass on the regex alone, that is acceptable — the regex is self-contained; proceed.)

- [ ] **Step 3: (No implementation needed — the regex IS the artifact under test.)**

The marker grammar is a string contract, not code. Step 1's `MARKER_RE` is the definition. No further implementation in this task.

- [ ] **Step 4: Run test to verify it passes**

Run: `sh plugin-claude-code/tests/run.sh`
Expected: tail shows `N passed, 0 failed` including the 3 marker asserts.

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/tests/test-overbuild.sh
git commit -m "test: add marker-grammar contract for anti-over-build upgrade"
```

---

### Task 2: Create the shared `overbuild-patterns.md` library

**Files:**
- Create: `plugin-claude-code/template/rules/overbuild-patterns.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a file with two top-level sections — `## The over-build ladder` (6 rungs, each cross-referencing a working rule) and one `## <pattern-name>` block per seed smell, in `retrospect-patterns.md` entry format. The three lens tasks (3, 4, 5) read this file by path.

- [ ] **Step 1: Write the file** (complete content — no placeholders)

```markdown
# Over-Build — Pattern Library (Canonical)

> Ported 2026-06-23 from the Ponytail project (github.com/DietrichGebert/ponytail).
> Shared source of truth for the `overbuild` review lens used by `/prospect`,
> `/retrospect`, and `/readiness-audit`. Mirrors the entry format of
> `retrospect-patterns.md`.

## How patterns are used

When a skill runs with the `overbuild` lens, Claude walks the ladder below for each
planned step (prospect), diff hunk (retrospect), or surface (readiness-audit), then
checks the change against each smell's detection cues. Detection is judgment-based,
not regex. Every finding MUST cite the failed ladder rung AND a concrete leaner
alternative; a finding that cannot name the smaller version is suppressed. A change
already carrying an `aria:simplification` marker is reported "resolved (marked)",
never flagged.

## The over-build ladder

Apply in order. The first rung that resolves the need wins; stop there.

1. **Needed?** — Is this feature/step actually required by the stated goal? If not, skip it. (Rule 13 — YAGNI)
2. **Stdlib?** — Does the language/standard library already do it? Use that. (Rule 12)
3. **Platform-native?** — Is there a built-in platform feature (HTML input type, OS API, framework primitive)? Use that. (feedback: framework-classes-before-custom-CSS, native edition)
4. **Installed dependency?** — Is a dep already in the tree that does it? Use it; don't add another. (Rule 12)
5. **One line?** — Can it be a single expression instead of a new abstraction? Write the one line. (Rule 14)
6. **Minimal build** — Only now write the smallest code that works, and mark any deliberate simplification with `aria:simplification` (Rule 13 clause).

## Pattern entry format

Each pattern below uses: `## <name>` · `**Tier:**` · `**First identified:**` · `**One-line summary:**` · `### Detection cues` · `### Why it's a problem` · `### Counter-discipline` · `### References`.

## speculative-abstraction

**Tier:** canonical
**First identified:** 2026-06-23 in anti-over-build-upgrade plan
**One-line summary:** Introducing an interface/base-class/generic before a second concrete use case exists.

### Detection cues
- A new abstraction layer with exactly one implementation.
- "We'll need this later" / "to make it extensible" with no current second caller.

### Why it's a problem
Abstraction beyond purposeful layers (Rule 14) adds indirection a reader must traverse for zero current benefit, and the eventual real use case rarely matches the guessed shape.

### Counter-discipline
Inline the single use. Extract the abstraction when the SECOND caller appears (rule of two).

### References
- Rule 14 (abstraction has diminishing returns); ladder rung 5.

## dependency-for-a-oneliner

**Tier:** canonical
**First identified:** 2026-06-23 in anti-over-build-upgrade plan
**One-line summary:** Adding a package to do what stdlib, a platform feature, or one line already does.

### Detection cues
- A new entry in package.json / requirements.txt whose use is a single function call.
- Importing a util library (left-pad-class) for trivial string/array/date work.

### Why it's a problem
Every dependency is a maintenance, security, and coupling cost (Rule 12) that a one-liner avoids entirely.

### Counter-discipline
Walk ladder rungs 2–5 before rung 4's "add a dep". Name the stdlib/native/one-line alternative.

### References
- Rule 12 (minimize dependencies); ladder rungs 2–5.

## config-knob-nobody-asked-for

**Tier:** canonical
**First identified:** 2026-06-23 in anti-over-build-upgrade plan
**One-line summary:** Adding a configurable option/flag/parameter no requirement called for.

### Detection cues
- A new function parameter / env var / settings field with one caller passing the default.
- "In case someone wants to…" framing with no named someone.

### Why it's a problem
Speculative configurability multiplies the state space to test and document for a need that does not exist yet.

### Counter-discipline
Hard-code the only value actually used. Add the knob when a real second value is requested.

### References
- Rule 13 (simplest solution wins); ladder rung 1.

## premature-generalization

**Tier:** canonical
**First identified:** 2026-06-23 in anti-over-build-upgrade plan
**One-line summary:** Solving a broader problem than the one posed ("handle any X" when one X was asked).

### Detection cues
- A function that accepts a type union / strategy map where one branch is ever hit.
- A loop/dispatcher over a collection that always has one element.

### Why it's a problem
Generalizing on a guessed axis (Rule 14) is usually generalized on the WRONG axis; the real variation appears elsewhere.

### Counter-discipline
Solve the specific case. Generalize against observed variation, not imagined variation.

### References
- Rule 14; ladder rungs 1 & 6.

## framework-for-a-function

**Tier:** canonical
**First identified:** 2026-06-23 in anti-over-build-upgrade plan
**One-line summary:** Standing up a framework/system/pipeline where a single function (or its absence) suffices.

### Detection cues
- A new "manager/registry/engine/orchestrator" whose total behavior is one transform.
- Build tooling / plugin system introduced for one consumer.

### Why it's a problem
The scaffolding outweighs the payload; future readers must learn the framework to find the one line that matters.

### Counter-discipline
Ship the function. Promote to a system when ≥3 consumers share real structure.

### References
- Rule 13, Rule 14; ladder rung 6.

## unmarked-simplification

**Tier:** canonical
**First identified:** 2026-06-23 in anti-over-build-upgrade plan
**One-line summary:** A deliberate simpler-path choice on non-trivial logic that carries no `aria:simplification` marker — indistinguishable from an accidental gap.

### Detection cues
- Non-trivial logic with an obvious omitted case (no TZ math, no pagination, happy-path only) and NO marker explaining the choice.
- A reviewer cannot tell "chose not to" from "forgot to".

### Why it's a problem
Without the marker (Rule 13 clause / Rule 21 inline), the simplification is an undocumented assumption; the over-build lens cannot tell a sound choice from a real bug, and re-flags it forever.

### Counter-discipline
Add the marker: `aria:simplification — <what> | limitation: <gap> | upgrade: <path>`. This is the ONLY smell whose fix is to ADD a line, not remove one.

### References
- Rule 13 (marker clause); Rule 21 (document decisions); ladder rung 6.
```

- [ ] **Step 2: Verify format parity with the sibling library**

Run: `diff <(grep -oE '^### (Detection cues|Why it.s a problem|Counter-discipline|References)$' plugin-claude-code/template/rules/retrospect-patterns.md | sort -u) <(grep -oE '^### (Detection cues|Why it.s a problem|Counter-discipline|References)$' plugin-claude-code/template/rules/overbuild-patterns.md | sort -u)`
Expected: no output (the four `###` sub-headers match the canonical format).

- [ ] **Step 3: Commit**

```bash
git add plugin-claude-code/template/rules/overbuild-patterns.md
git commit -m "feat: add overbuild-patterns.md shared lens library (ladder + 6 seed smells)"
```

---

### Task 3: Add the simplification-marker clause to Rule 13

**Files:**
- Modify: `plugin-claude-code/template/rules/working-rules.md` (Rule 13, ~line 89-92)

**Interfaces:**
- Consumes: the marker grammar from Task 1.
- Produces: the agent-facing convention that emits the markers Task 4's lens consumes.

- [ ] **Step 1: Read the exact current Rule 13 text**

Run: `sed -n '89,96p' plugin-claude-code/template/rules/working-rules.md`
Expected: the Rule 13 heading + body. Capture the exact trailing text to anchor the append.

- [ ] **Step 2: Append the clause** (after Rule 13's existing body, before Rule 14's `### 14` heading)

```markdown

**Mark deliberate simplifications.** When you choose a simpler solution over a more complete one on non-trivial logic, leave an inline marker recording the trade-off:
`<comment> aria:simplification — <what was simplified> | limitation: <known gap> | upgrade: <path if the gap bites>`
A simplification without its marker is an undocumented assumption (Rule 21, inline). The marker is what lets `/retrospect --lens=overbuild` tell a *chosen* simplification from an *accidental* gap. Comment syntax follows the host language (`//`, `#`, `<!-- -->`).
```

- [ ] **Step 3: Verify the rule count did NOT change**

Run: `grep -cE '^### [0-9]+\. ' plugin-claude-code/template/rules/working-rules.md`
Expected: `35` (unchanged — the clause is inside Rule 13, not a new rule).

- [ ] **Step 4: Verify the marker example in the rule matches the Task 1 regex**

Run: `grep -oE 'aria:simplification — .+ \| limitation: .+ \| upgrade: .+' plugin-claude-code/template/rules/working-rules.md`
Expected: one match (the clause's example conforms to the contract).

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/template/rules/working-rules.md
git commit -m "feat: add simplification-marker clause to Rule 13"
```

---

### Task 4: Add `--lens=overbuild` to /retrospect (backward lens + marker-respect)

Retrospect first (before prospect) because it is the marker's primary consumer and exercises the full ladder + marker-respect logic; prospect is then a forward-only simplification of the same mode.

**Files:**
- Modify: `plugin-claude-code/skills/retrospect/SKILL.md`

**Interfaces:**
- Consumes: `overbuild-patterns.md` (Task 2), marker grammar (Task 1).
- Produces: the `--lens=overbuild` modifier flag + a §"Over-build lens" mode section that prospect (Task 5) mirrors forward.

- [ ] **Step 1: Document the flag in the modifier-flags line**

Find the line (Step 0): `- Modifier flags (apply to any scope): \`--linear-post\` ... \`--no-source\` ...` and append:
```markdown
 `--lens=overbuild` (run the over-build review pass — see "Over-build lens" section; opt-in, off by default).
```
Also append ` [--lens=overbuild]` to the `argument-hint:` frontmatter.

- [ ] **Step 2: Add the mode section** (new `## Over-build lens (opt-in: --lens=overbuild)` section near the end, before Step 8 Validation Gates)

```markdown
## Over-build lens (opt-in: `--lens=overbuild`)

Off unless `--lens=overbuild` is passed. When off, this skill behaves exactly as documented above — zero behavior change. When on, after the standard per-fix pass, run one additional pass over the in-scope diff:

1. **Load the rubric.** Read `template/rules/overbuild-patterns.md` (resolve via the same `knowledge_root`/template path used for `retrospect-patterns.md`). Hold the ladder + smell list.
2. **Walk each diff hunk** against the ladder, then the smell detection cues.
3. **Marker-respect.** If a hunk carries an `aria:simplification` marker matching `aria:simplification — .+ | limitation: .+ | upgrade: .+`, report it as `resolved (marked)` and do NOT flag it. An obvious simplification with NO marker is the `unmarked-simplification` smell.
4. **Emit findings** in the existing per-fix block style, each REQUIRING: the failed ladder rung, the matched smell name, and a concrete leaner alternative. A finding that cannot name the smaller version is suppressed (matches this skill's existing "name the smaller version or it's not a finding" discipline).
5. **Verdict mapping.** Over-build findings map to the existing verdict vocabulary: `dependency-for-a-oneliner`/`framework-for-a-function` → recommend revert-and-shrink; `unmarked-simplification` → recommend add-the-marker (not a revert).

Findings append to the report as an `### Over-build lens` subsection; they never alter the non-lens verdicts.
```

- [ ] **Step 3: Test — flag is documented (lint)**

Add to `plugin-claude-code/tests/test-overbuild.sh`:
```sh
RS="$ROOT/skills/retrospect/SKILL.md"
assert_eq "retrospect: lens flag documented" "1" \
  "$(grep -cE -- '--lens=overbuild' "$RS" | awk '{print ($1>0)?1:0}')"
assert_eq "retrospect: reads overbuild-patterns" "1" \
  "$(grep -cq 'overbuild-patterns.md' "$RS" && echo 1 || echo 0)"
assert_eq "retrospect: marker-respect present" "1" \
  "$(grep -cq 'resolved (marked)' "$RS" && echo 1 || echo 0)"
```

- [ ] **Step 4: Run the suite**

Run: `sh plugin-claude-code/tests/run.sh`
Expected: tail `N passed, 0 failed` (the 3 new retrospect asserts pass).

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/skills/retrospect/SKILL.md plugin-claude-code/tests/test-overbuild.sh
git commit -m "feat: add --lens=overbuild backward mode + marker-respect to /retrospect"
```

---

### Task 5: Add `--lens=overbuild` to /prospect (forward lens)

**Files:**
- Modify: `plugin-claude-code/skills/prospect/SKILL.md`

**Interfaces:**
- Consumes: `overbuild-patterns.md` (Task 2); the mode shape from Task 4 (forward variant).
- Produces: the `--lens=overbuild` modifier flag on prospect.

- [ ] **Step 1: Document the flag** — same as Task 4 Step 1, on prospect's modifier-flags line + `argument-hint:`.

- [ ] **Step 2: Add the mode section** (`## Over-build lens (opt-in: --lens=overbuild)`, before Step 8 Validation Gates)

```markdown
## Over-build lens (opt-in: `--lens=overbuild`)

Off unless `--lens=overbuild` is passed. When on, after the standard per-step pass, check each PLANNED step against `template/rules/overbuild-patterns.md`:

1. Load the ladder + smells.
2. For each step, find the lowest ladder rung that would resolve its need. If the step proposes a higher rung than necessary (e.g. adds a dependency where a one-liner works), it fails that rung.
3. A failing step yields a SHRINK verdict (existing vocabulary) citing the failed rung + the concrete leaner alternative; an unnecessary step yields KILL. A step whose smaller form cannot be named is NOT flagged.
4. Findings fold into §4.3 per-step verdicts (the Action becomes SHRINK/KILL with the over-build reason) — no separate section needed, since prospect is already per-step.

Forward counterpart of `/retrospect --lens=overbuild`; same rubric, applied to a plan instead of a diff.
```

- [ ] **Step 3: Test — flag is documented (lint)**

Add to `test-overbuild.sh`:
```sh
PS="$ROOT/skills/prospect/SKILL.md"
assert_eq "prospect: lens flag documented" "1" \
  "$(grep -cq -- '--lens=overbuild' "$PS" && echo 1 || echo 0)"
assert_eq "prospect: reads overbuild-patterns" "1" \
  "$(grep -cq 'overbuild-patterns.md' "$PS" && echo 1 || echo 0)"
```

- [ ] **Step 4: Run the suite**

Run: `sh plugin-claude-code/tests/run.sh`
Expected: `N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/skills/prospect/SKILL.md plugin-claude-code/tests/test-overbuild.sh
git commit -m "feat: add --lens=overbuild forward mode to /prospect"
```

---

### Task 6: Add the over-build probe to /readiness-audit (per-surface dispatch)

**Files:**
- Modify: `plugin-claude-code/skills/readiness-audit/SKILL.md`

**Interfaces:**
- Consumes: `overbuild-patterns.md` (Task 2).
- Produces: an over-build entry in the skill's per-surface Explore-agent dispatch list (read-only).

- [ ] **Step 1: Read the dispatch step** to anchor the edit

Run: `grep -n "Dispatch exploration agents per surface" plugin-claude-code/skills/readiness-audit/SKILL.md`
Expected: the line (~70) introducing the per-surface agent dispatch.

- [ ] **Step 2: Add the over-build surface** to that dispatch list

```markdown
- **Over-build surface (opt-in via `--for` text mentioning bloat/over-engineering, or always when scope is a code repo):** dispatch one read-only Explore agent to walk `template/rules/overbuild-patterns.md`'s ladder + smells across the surface's source. It reports candidate over-build sites (each: file:line, matched smell, failed ladder rung, concrete leaner alternative). It respects `aria:simplification` markers — a marked site is reported "resolved", never flagged. Read-only per the skill's existing guardrail: it reports what it would change, never mutates a build artifact.
```

- [ ] **Step 3: Test — probe documented (lint)**

Add to `test-overbuild.sh`:
```sh
RA="$ROOT/skills/readiness-audit/SKILL.md"
assert_eq "readiness-audit: overbuild probe present" "1" \
  "$(grep -cq 'overbuild-patterns.md' "$RA" && echo 1 || echo 0)"
assert_eq "readiness-audit: probe is read-only" "1" \
  "$(grep -cq 'never mutates a build artifact' "$RA" && echo 1 || echo 0)"
```

- [ ] **Step 4: Run the suite**

Run: `sh plugin-claude-code/tests/run.sh`
Expected: `N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/skills/readiness-audit/SKILL.md plugin-claude-code/tests/test-overbuild.sh
git commit -m "feat: add over-build probe to /readiness-audit per-surface dispatch"
```

---

### Task 7: Canonical-port gate — full suite green + opt-in guard

**Files:** none (verification task).

- [ ] **Step 1: Run the full canonical suite**

Run: `sh plugin-claude-code/tests/run.sh`
Expected: `N passed, 0 failed` — all marker + lint asserts pass.

- [ ] **Step 2: Opt-in guard — confirm no default-on wording leaked**

Run: `grep -nE "lens=overbuild" plugin-claude-code/skills/*/SKILL.md | grep -viE "opt-in|off (by )?default|unless|when on|when off"`
Expected: no lines that introduce the flag as default-on. (Every mention is gated as opt-in.)

- [ ] **Step 3: Manual behavioral spot-check (the one non-mechanical test)**

The steps above are BUILD-time verification (suite green, flag documented) — they prove the artifact-as-text is correct, NOT that the lens *behaves* when an agent interprets it at runtime. Those are different seams (lint proves doc==intent; this run proves agent==intent). Do one human-eyeballed run.

**Spot-check target = `/retrospect` only, deliberately.** Retrospect is the only lens with non-trivial runtime behavior to observe — the ladder walk PLUS the marker-respect logic PLUS standalone findings. `/prospect`'s lens folds into its existing per-step verdicts and `/readiness-audit`'s is a read-only agent probe; both reuse the *same* `overbuild-patterns.md` rubric retrospect exercises here, and each is covered by the flag-documented lint asserts in its own task (Tasks 5, 6). One rich run validates the shared rubric.

Create a throwaway fixture diff with exactly two hunks:
  1. an over-built hunk — adds a dependency to do what one stdlib line does (a `dependency-for-a-oneliner`)
  2. a simplified hunk carrying a valid marker:
     `// aria:simplification — happy-path only | limitation: no retry | upgrade: add backoff if flaky`

Run `/retrospect --lens=overbuild` (branch or file scope) against it. Confirm BOTH:
  - hunk 1 is flagged, citing the failed ladder rung + a named leaner alternative
  - hunk 2 is reported "resolved (marked)" and NOT flagged

If either fails, the lens wording in Task 4 is wrong — fix Task 4's mode section and re-run. This is the only check that proves the lens *works*, not just that it's *documented*.

- [ ] **Step 4: Commit (if any fixups were needed; else skip)**

```bash
git add -A && git commit -m "test: canonical-port gate green for anti-over-build upgrade"
```

---

## Phase 2 — Propagate to 4 ports + re-baseline ledger

> Ports are hand-maintained, not regenerated from canonical (per `check-port-drift.sh`). Each port gets the same 4 content edits adapted to its layout: codex & cowork use `template/rules/` + `skills/`; cursor uses `knowledge/rules/` and the rules compile to `.mdc`; antigravity uses `template/rules/` + `rules/`. Cowork skill bodies may diverge (ADR-014) — preserve existing divergences, add the lens mode in the cowork voice.

### Task 8: Replicate to codex, antigravity, cowork, cursor

**Files:**
- Modify (per port, ×4): `<port>/.../rules/overbuild-patterns.md` (create), `<port>/.../rules/working-rules.md` (Rule 13 clause), `<port>/skills/{prospect,retrospect}/SKILL.md` (or port equivalent), `<port>/skills/readiness-audit/SKILL.md`.
- For cursor: after copying rules into `knowledge/rules/`, run the cursor `.mdc` compile step.

**Interfaces:**
- Consumes: the canonical files from Phase 1 as the content source.
- Produces: 4 port trees carrying the same convention + lens.

- [ ] **Step 1: Copy the new pattern file into each port's rules dir**

```bash
for p in plugin-openai-codex plugin-antigravity plugin-claude-cowork; do
  cp plugin-claude-code/template/rules/overbuild-patterns.md "$p/template/rules/overbuild-patterns.md"
done
cp plugin-claude-code/template/rules/overbuild-patterns.md plugin-cursor-template/knowledge/rules/overbuild-patterns.md
```

- [ ] **Step 2: Apply the Rule 13 clause to each port's working-rules.md**

Repeat Task 3 Step 2's append in each of: `plugin-openai-codex/template/rules/working-rules.md`, `plugin-antigravity/template/rules/working-rules.md`, `plugin-claude-cowork/template/rules/working-rules.md`, `plugin-cursor-template/knowledge/rules/working-rules.md`. Verify rule count unchanged per port (`grep -cE '^### [0-9]+\. '`).

- [ ] **Step 3: Apply the lens mode to each port's prospect/retrospect/readiness-audit skills**

For codex & antigravity: copy the canonical `## Over-build lens` sections + flag lines verbatim into the matching SKILL.md. For cowork: add the same mode adapted to the cowork variant's voice, preserving its existing ADR-014 divergences (do NOT clobber cowork-specific bodies). Cursor has no dual-port skills surface for these — skip skill edits there if absent; confirm with `ls plugin-cursor-template/skills 2>/dev/null`.

- [ ] **Step 4: Cursor `.mdc` compile**

Run the cursor rules compile (per `release-cursor.sh`'s build step) so `overbuild-patterns` + the Rule 13 change land in compiled `.mdc`. Run: `grep -rn "release-cursor" -l . ; sh release-cursor.sh --build-only 2>/dev/null || echo "use the compile step documented in release-cursor.sh"`

- [ ] **Step 5: Commit**

```bash
git add plugin-openai-codex plugin-antigravity plugin-claude-cowork plugin-cursor-template
git commit -m "feat: propagate anti-over-build upgrade to codex/antigravity/cowork/cursor ports"
```

---

### Task 9: Re-baseline PORT-LEDGER.json + drift check

**Files:**
- Modify: `PORT-LEDGER.json`

- [ ] **Step 1: Re-baseline every port's changed surfaces**

Run: `sh plugin-claude-code/bin/check-port-drift.sh --update all`
Expected: ledger updated; each port's `last_parity_pass` stamped today, hashes recomputed for the 5 changed surfaces.

- [ ] **Step 2: Verify drift check passes**

Run: `sh plugin-claude-code/bin/check-port-drift.sh`
Expected: no `DRIFTED` (out-of-SLA) surfaces for the changed files.

- [ ] **Step 3: Commit**

```bash
git add PORT-LEDGER.json
git commit -m "chore: re-baseline PORT-LEDGER for anti-over-build upgrade surfaces"
```

---

### Task 10: Version bump + CHANGELOG

**Files:**
- Modify: `plugin-claude-code/.claude-plugin/plugin.json` (+ per-port plugin.json), `CHANGELOG.md`

- [ ] **Step 1: Bump version 2.35.x → 2.36.0** in each port's `.claude-plugin/plugin.json` (and `PORT-LEDGER.json` version fields if it carries them).

- [ ] **Step 2: Add CHANGELOG entry** (per ADR-014 attribution) under a new `## 2.36.0` heading: summarize the marker clause, the `overbuild` lens on 3 skills, and the new pattern library; credit the Ponytail port.

- [ ] **Step 3: Run the release dry-run / Gate A**

Run: `sh plugin-claude-code/tests/run.sh` (Gate A) then inspect `release.sh` Gate B/C output without publishing.
Expected: Gate A green; Gate C drift check clean.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: bump aria-knowledge to 2.36.0 (anti-over-build upgrade)"
```

---

## Self-Review

**1. Spec coverage:**
- Surface 1 (Rule 13 clause) → Task 3. ✅
- Surface 2 (`overbuild-patterns.md`) → Task 2. ✅
- Surface 3 (`/prospect` lens) → Task 5. ✅
- Surface 4 (`/retrospect` lens + marker-respect) → Task 4. ✅
- Surface 5 (`/readiness-audit` per-surface probe — corrected) → Task 6. ✅
- Noise control (opt-in, name-alternative-or-suppress, marker-respect) → Global Constraints + Task 4 Step 2 + Task 7 Step 2. ✅
- Multi-port propagation → Phase 2 (Tasks 8–9). ✅
- Versioning → Task 10. ✅
- Testing (marker fixture, marked-not-flagged, opt-in-unchanged) → Task 1 + Task 7 Step 2. ⚠ Partial: see note.

**Note on testing scope (honest, not a placeholder):** This feature is ~95% prose (a rule clause, a pattern library, skill-doc mode sections an agent interprets at runtime). The only machine-checkable artifacts are (a) the marker regex contract (Task 1) and (b) lint asserts that each skill documents the flag and reads the library (Tasks 4–6). The spec's "assert /retrospect --lens surfaces the smell / does not flag a marked hunk" tests are **behavioral over an LLM-interpreted doc** — not unit-testable in the shell harness without invoking a model. Building a model-in-the-loop test rig for this would itself be `framework-for-a-function` over-build. Resolution: the lint + regex tests guard the contract mechanically; the behavioral assertions are validated by a one-time manual `/retrospect --lens=overbuild` run against a hand-made fixture diff during Task 7 (documented there as Step 2's spirit). Flagged for the plan-prospect to rule on.

**2. Placeholder scan:** No TBD/TODO/"implement later". Every code/content step shows full content. One intentional `|| echo "use the compile step…"` fallback in Task 8 Step 4 because the exact cursor compile invocation lives in `release-cursor.sh` and should be read at execution, not guessed (Rule 33).

**3. Type/name consistency:** Marker regex `aria:simplification — .+ \| limitation: .+ \| upgrade: .+` identical in Task 1, Task 3, Task 4. Flag `--lens=overbuild` identical across Tasks 4/5/6. Library filename `overbuild-patterns.md` identical throughout. Pattern names match between Task 2 definitions and the verdict-mapping references in Tasks 4–5.
