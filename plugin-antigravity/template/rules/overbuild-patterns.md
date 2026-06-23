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
