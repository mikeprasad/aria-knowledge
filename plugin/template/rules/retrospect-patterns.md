<!-- plugin-managed: ARIA writes this file. Customize freely — your edits appear as diff prompts on plugin updates. -->

# Retrospect — Failure-Mode Pattern Library (Canonical)

This is the canonical, project-agnostic library of process failure patterns that the `/retrospect` skill checks for in every retrospective. New canonical patterns are added here over time as they emerge from real retrospectives. Project-specific patterns belong in `projects/<proj>/retrospect-patterns.md`.

## How patterns are used

When `/retrospect` runs, Claude reads each pattern's **detection cues** and judges whether the current bundle (commits, diffs, session transcript, deploy logs) exhibits them. Detection is judgment-based, not regex; in v2 some textual cues may be automated.

Each pattern hit is reported in the retrospective's §4.4 (Failure-Mode Pattern Check) section.

## Pattern entry format

Each pattern has the following structure:

- `## <pattern-name>` — kebab-case identifier
- `**Tier:**` canonical | project-specific (`<project>`)
- `**First identified:**` `<date>` in `<retrospective-source>`
- `**One-line summary:**` what the pattern is in one sentence
- `### Detection cues` — bulleted list of what to look for
- `### Why it's a problem` — 2–3 sentences on the failure mode
- `### Counter-discipline` — the behavior that prevents it
- `### References` — list of retrospectives where this pattern fired

---

## diagnose-from-shape-not-path

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Building theories from the *shape* of observed data (DB pattern, log fingerprint, error frequency) rather than tracing the actual code path the user's reproducer hits.

### Detection cues
- Commit messages or session transcripts that justify a fix with phrases like "the data is consistent with X" or "this matches a Y pattern" without a concrete code-path trace
- Multiple fixes targeting the same observed symptom from different angles in one bundle (the spread itself is a tell that the cause was inferred, not located)
- Hypotheses that name a *category* of bug (race condition, stale cache, drift) but not a specific function or line

### Why it's a problem
Pattern matching from memory is faster than tracing, so it feels like progress. But shape-consistency is not causation: many distinct bugs produce identical data shapes. Shipping a fix on shape-only evidence leaves a non-trivial probability that the actual code path is untouched.

### Counter-discipline
Before writing a fix, articulate the *exact* line(s) of code believed to be wrong and the *exact* control-flow trace that reaches them in the user's reproducer. If the trace can't be articulated, instrument first (see `bundle-unverification` and `speculative-iteration` for related disciplines).

### References
- *(seeded — first canonical reference will be the retrospect skill's first real-use retrospective)*

---

## fix-bundling

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Shipping multiple fixes per deploy, making attribution impossible when the bug reproduces.

### Detection cues
- A single deploy/release range containing 3+ fixes that target distinct hypotheses for the same user-facing bug
- Commit messages that bundle "fix A + fix B + improvement C" rather than one concern per commit
- No clear primary fix; the bundle relies on "one of these will work" reasoning

### Why it's a problem
When a bundle ships and the bug reproduces, you cannot tell which fix was load-bearing, which was harmless, and which made things worse. Rollback becomes coarse and re-diagnosis is muddied. The bundle also creates pressure to ship every fix at once, eliminating the deploy-per-bug feedback loop.

### Counter-discipline
One deploy per user-facing bug. Bonus fixes (typos, refactors, secondary issues) ship in their own deploys. Atomic commits get half the way there; deploy granularity gets the rest.

### References
- *(seeded)*

---

## bundle-unverification

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Assuming "deploy succeeded → my code is running" without verifying the deployed bundle actually contains the fix.

### Detection cues
- No unique in-bundle marker (a string, function name, comment) added with the fix
- "Deploy succeeded" claimed solely from CI green or a deploy-platform OK message
- Browser-cached bundles or stale CDN edges not ruled out as a confounder when a fix appears not to work

### Why it's a problem
A successful deploy guarantees the artifact uploaded; it does not guarantee the user's session is running it. Cached bundles, stale workers, edge-cache lag, and source-map mismatches can all silently serve old code. Without a verifiable in-bundle marker, "this fix didn't work" and "this fix didn't ship" are indistinguishable.

### Counter-discipline
Add a unique marker to every non-trivial fix (e.g., a `[FIX-<id>]` console.log, a renamed function, a new exported constant). After deploy, confirm the marker is present in the served artifact (curl + grep, network-tab inspection, or source-map check) before treating "the bug still reproduces" as evidence about the fix.

### References
- *(seeded)*

---

## speculative-iteration

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Shipping ≥2 fixes for the same bug without adding diagnostic instrumentation between them.

### Detection cues
- Two or more sequential commits/deploys that fix the same user-facing bug, with each one trying a different hypothesis
- No instrumentation commit between attempts (no console.log, no DB query, no measurement)
- The phrase "let me try X" or equivalent in session transcripts after the first failed fix

### Why it's a problem
After the first fix fails, the right move is to gather *new* evidence — not to ship another theory. Speculative iteration burns deploy cycles, user-test cycles, and trust, while preserving the original information deficit that produced the wrong fix in the first place. Each subsequent attempt has the same expected probability of success as the first.

### Counter-discipline
After a failed fix, the next deploy must be either (a) a revert + minimal-instrumentation deploy, or (b) an instrumentation-only deploy. No new fix ships until at least one new datum is in hand.

### References
- *(seeded)*

---

## judgment-confused-with-evidence

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Treating "this hypothesis is consistent with all available evidence" as proof, when it is only a survival check.

### Detection cues
- Self-justifying language like "this is the most consistent with the data" or "all the evidence points to X"
- Confidence high, falsification test absent
- A theory that hasn't been actively challenged by trying to *disprove* it

### Why it's a problem
Multiple distinct hypotheses can be simultaneously consistent with the same evidence. "Survives the evidence" is the lowest bar a hypothesis must clear, not the highest. Mistaking it for "is true" leads directly to shipping speculative fixes confidently.

### Counter-discipline
For any hypothesis with high confidence, name the *specific signal* that would distinguish it from at least one alternative — and go gather that signal before acting. If you cannot name a discriminating signal, the hypothesis is not yet falsifiable in your current setup.

### References
- *(seeded)*

---

## phrase-tell-consistent-with-evidence

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** The literal phrase "consistent with all evidence" / "the data is consistent with X" is a high-leverage textual flag for `judgment-confused-with-evidence`.

### Detection cues
- Exact phrases in commit messages, session transcripts, or PR descriptions: "consistent with the data," "consistent with all evidence," "the data is consistent with," "matches a pattern of"
- Variants: "fits the pattern of," "looks like a [known issue type]"

### Why it's a problem
When this phrasing appears alongside a fix decision, the decision has typically been made on shape-evidence consistency rather than on direct code-path observation. The phrase is a reliable retrospective predictor of speculative fixing.

### Counter-discipline
When you notice the phrase forming in your own output, replace it with: "to confirm X, I'd need to see [specific signal]. Let's instrument for it." This converts a closure into a falsification test.

### References
- *(seeded)*

---

## pattern-matched-from-memory

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Invoking a remembered failure mode (logout race, stale cache, etc.) without tracing the *current* code path to confirm the same mode applies.

### Detection cues
- Diagnostic language that references a *prior* incident or named bug class as evidence for the current diagnosis
- Fix design that mirrors a past fix structurally without a fresh trace of the current code

### Why it's a problem
The same symptom can appear in different code paths. A remembered failure mode is a hypothesis-generator, not a hypothesis-confirmer. Treating memory as evidence skips the trace and inherits the previous incident's blind spots.

### Counter-discipline
When a remembered pattern feels like a match, treat it as one candidate hypothesis among several. Add it to the §7 (Re-diagnosis) hypothesis list with explicit "Evidence FOR / AGAINST" — not as the working theory.

### References
- *(seeded)*

---

## pushback-as-cue

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** When the user pushes back ("review and validate," "audit the changes"), the right response is "yes, let's audit" — not "let me try one more thing."

### Detection cues
- User messages with audit cues ("review what you did," "are these changes necessary," "stop and look at this") followed by Claude proposing another fix
- Claude responses that frame pushback as a request for more diagnosis-by-Claude rather than a stop-signal

### Why it's a problem
Pushback is information: the user has detected that the speculative loop is unproductive and is offering an explicit course correction. Continuing to fix is overriding that signal with self-confidence.

### Counter-discipline
Treat audit-shaped pushback as a `/retrospect` invocation by default. Offer the retrospective; if the user declines, then return to fixing — but only with their explicit redirect.

### References
- *(seeded)*

---

## user-not-recruited

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Diagnosing remotely from logs and code when asking the user to inspect their own browser/state would be faster.

### Detection cues
- Multiple speculative fixes for a state-related bug without ever asking the user to inspect their localStorage / IndexedDB / cookies / network panel / state-store contents
- Long internal hypothesis chains where a single 30-second user check would have falsified or confirmed the chain

### Why it's a problem
The user is at the keyboard with full access to runtime state. Claude is reading code from a thousand miles away (architecturally). For state-shape bugs, recruiting the user as a diagnostic collaborator is often the fastest path to ground truth.

### Counter-discipline
For any non-trivial state bug, before the second fix attempt, ask the user a specific check: "in DevTools, run `<exact code>` and tell me what it returns" or "show me localStorage keys matching `<pattern>`."
