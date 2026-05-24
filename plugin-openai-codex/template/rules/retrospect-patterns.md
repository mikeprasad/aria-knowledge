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

---

## architectural-claim-without-source-trace

**Tier:** canonical
**First identified:** 2026-05-05 in a real-use retrospective (the first instance Rule 34's recognition cues were calibrated against).
**One-line summary:** Asserting how an existing system currently works (or doesn't work) — especially negative-existence claims like "X doesn't enforce Y" — without reading the enforcement-layer source first.

### Detection cues
- Conversational turn frames an architectural change as needed because an existing system "doesn't" do something (negative-existence claim — the highest-confidence wrong-claim shape)
- Architectural proposal landed before any grep/read of the candidate enforcement layer (loader, registry, middleware, validator)
- Multiple turns spent designing a substitution / append / redesign pattern before the existing implementation is named
- Same shape on the docs surface: a "STILL OPEN" / "outstanding" claim in a tracker or audit doc that turns out to already be shipped, written without source-trace
- Phrase fragments: "the loader doesn't enforce…", "we currently don't…", "this isn't validated anywhere…", "X is missing from [layer]"

### Why it's a problem
Negative-existence claims about your own system survive the highest plausibility bar — the assertion sounds technical and structural, so it isn't challenged. But "X is not enforced" is *exactly* the claim that requires a source-trace, because the cost of being wrong is shipping work that duplicates existing infrastructure (or worse, replaces working code). The first calibration instance was a multi-turn architecture-substitution proposal whose target was already implemented in a 20-day-old commit at the data-loader layer; the same recognition gap also surfaced on the docs surface as a "STILL OPEN" tracker regen that listed already-shipped items.

### Counter-discipline
Before any architectural claim about how an existing system works (or doesn't work), grep for the candidate enforcement layer and read it. If the claim is negative-existence ("doesn't enforce X"), the source-trace is mandatory — the wrong-claim cost asymmetry is too high. CODEMAP enforcement-point one-liners are the standing defense; absent them, an in-line trace pass before the architectural turn is required. Aligns with Rule 34 (validate plan before executing) — the rule-text catches the trigger prospectively, this pattern catches the failure shape retrospectively.

### References
- *(seeded — first canonical reference is the 2026-05-05 cs-builder Stage 1 close-out gate retrospective in the plugin author's environment)*

---

## fix-without-call-site-audit

**Tier:** canonical
**First identified:** 2026-05-05 in a real-use cs-builder Stage 1 close-out cycle (four instances within hours of each other — the strongest single-session calibration in the canonical library).
**One-line summary:** Fixing a function-contract bug at one call site without auditing all sibling call sites of the same function for the identical gap, leading to the same defect re-shipping at the next call site discovered.

### Detection cues
- Bug fix touches a single call site of a function that is known (or knowable) to have multiple callers
- Commit message uses "fix at X" framing — naming the immediate symptom (this URL, this path, this component) — without naming the function whose contract was incomplete or "all call sites of X audited"
- Same defect pattern recurs at a sibling call site within hours or days of the original fix
- A second commit lands shortly after the first, in the same file or a sibling file, fixing what is structurally the same gap
- Phrase fragments in narrative or commit body: "this fixes [the case]…", "specifically [path]…", "for [this component]…" — without "audited all callers"

### Why it's a problem
Single-call-site fixes pass type-checking, pass tests targeting the fixed path, and ship cleanly. The sibling call site continues to fail silently until human testing surfaces it. Each missed sibling becomes a separate user-visible bug with separate deploy + retest + rollback cost. The first calibration cycle was four sequential fixes in cs-builder Stage 1: gallery merge missing pageIndex, tool-use rehost missing, action-chip render missing, and Discovery onBlur rehost missing — each fixing one call site of a recurring function-contract gap, each shipping before the next call site was audited.

### Counter-discipline
Before claiming a function-contract fix complete, grep all call sites of the function and audit each for the same gap. If any sibling call site is left unmodified, name explicitly *why* it doesn't need the same fix (e.g., "Phase 3 generation auto-applies the missing field downstream"). Treat the fix as incomplete until either every sibling is patched or every unpatched sibling has a documented exemption. The audit pass is cheap (one grep, one read per match); the alternative is sequential retest cycles each costing minutes-to-hours.

### References
- *(seeded — first canonical reference is the 2026-05-05 cs-builder Stage 1 close-out cycle in the plugin author's environment, four instances)*

---

## new-artifact-without-consumer-trace

**Tier:** canonical
**First identified:** 2026-05-05 in the same cs-builder Stage 1 close-out cycle as `fix-without-call-site-audit`, immediately after the four call-site instances — a distinct sub-shape sharing the broader completion-claim-without-trace family.
**One-line summary:** Creating a new artifact (file, route, blueprint, skill) that is consumed by an enumerator (registry, manifest, dispatch table, type union) and claiming the artifact will work end-to-end without verifying or updating the enumerator.

### Detection cues
- New file created at a path matching a plural-file shape: `*/blueprints/*.json`, `*/skills/*/SKILL.md`, `*/api/routes/*.ts`, `*/handlers/*`, `*/templates/*`
- Completion-claim language applied to the artifact: "will work end-to-end", "auto-mirrors the [registry]", "deployed", "shipped", "matches the existing entries" — without naming the discovery mechanism
- Rule 22 marker emits low-impact reasoning that elides the consumer (registry / manifest / loader / type union / dispatch table) — the artifact is described in isolation
- Verification step in the plan is "deploy completes" or "build passes" rather than "consumer enumerates the new entry"
- The artifact's directory contains 3+ sibling files of the same shape and the consumer is reachable by a single grep (e.g., `grep -rn "'restaurant'" src/`) that was not run

### Why it's a problem
Most registries are static. A new file plus a missing registry entry produces a silent absence: the build passes, type-checks pass, tests targeting the artifact pass, and only a UI-level test surfaces the gap. The completion-claim language ("will work") creates the same plausibility bar that negative-existence claims do (`architectural-claim-without-source-trace`), with the same wrong-claim cost asymmetry — shipping work that appears complete but isn't discoverable. The first calibration instance was a new blueprint file deployed to `inventory/blueprints/`, claimed to "auto-mirror" the existing blueprints; the type-picker UI read from a static registry array that listed templates by ID, and the new entry was missing from that array.

### Counter-discipline
Before claiming a new artifact complete, identify its consumer and grep the consumer for analogous entries. If the consumer is a static registry, a manifest, a type union, or a dispatch table, deploying the artifact alone is incomplete — the consumer must also be updated, and the verification claim should name the consumer explicitly. Inverse of the call-site discipline: where `fix-without-call-site-audit` covers existing-function → multiple-callers, this pattern covers new-artifact → existing-enumerator.

### References
- *(seeded — first canonical reference is the 2026-05-05 cs-builder Stage 1 close-out cycle in the plugin author's environment, bar blueprint instance)*
