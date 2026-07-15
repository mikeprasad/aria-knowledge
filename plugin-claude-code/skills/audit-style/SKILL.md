---
description: "Mine your past session-log history for revealed working-style rules — how you actually work, proven by what you did (definition of done, rejection criteria, debugging approach, design taste, writing voice). Evidence-gated: a rule ships only with >=2 distinct sessions of dated verbatim quotes. Stages to the rules backlog for normal audit review. Opt-in. Trigger: '/audit style', 'mine my working style', 'audit my style'."
argument-hint: "[recent|all|window <days>]"
allowed-tools: Read, Glob, Grep, Bash, Write, Edit
---

# /audit style — Working-Style Sub-Audit

Mine your own past session-log corpus for working-style rules you have already revealed through action — not rules you're asked to invent, rules extracted from what you actually said and did across real sessions. Evidence-gated at every step: a candidate that cannot show its receipts does not ship, no matter how plausible it sounds.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/audit style` resolves to this skill — aria-knowledge (Code) is the canonical owner of all dual-port skills per ADR-094 §Part 1. The Cowork variant is namespaced-only: `/aria-cowork:audit-style`.

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/audit style` from a non-Code runtime.**
>
> This variant reads the local Claude Code transcript corpus at `~/.claude/projects/{cwd-encoded}/*.jsonl` via Bash + the bundled `extract-user-prose.py` — paths Cowork's persistent-grant model can't reach. For the Cowork-native variant, use `/aria-cowork:audit-style`.
>
> **Use `/aria-cowork:audit-style` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `aria-cowork:audit-style` with the same arguments the user provided to this invocation. Do not proceed with this skill's steps.
- **`n` / `no`** — Proceed with this (aria-knowledge) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check.

If `Bash` is available, proceed to Step 0.

**Opt-in only, never cadence-fired:** unlike `/audit-knowledge` and `/audit-config`, `/audit style` is **never** triggered by a SessionStart hook, an activity threshold, or any other automatic cadence. It runs only on an explicit, user-typed invocation (`/audit style`, "mine my working style", "audit my style"). There is no ambient trigger to suspend or account for — this gate section and Step 4b's preview gate are the only checkpoints.

## Step 0: Config + Corpus Locate

Read `~/.claude/aria-knowledge.local.md` and extract the three style-audit config keys (parsed by `config.sh` as `KT_STYLE_LOOKBACK_DAYS`, `KT_STYLE_MAX_SESSIONS`, `KT_STYLE_AUDIT_LOG`). These keys are **bare-assigned** — the config file may have no value at all for any of them, in which case the shell variable is an empty string. Apply these defaults yourself in the skill body whenever the corresponding value is empty:

- `KT_STYLE_LOOKBACK_DAYS` empty → default to **90** days.
- `KT_STYLE_MAX_SESSIONS` empty → default to **50** sessions.
- `KT_STYLE_AUDIT_LOG` empty → default to `{knowledge_folder}/logs/style-audit-log.md`.

If `~/.claude/aria-knowledge.local.md` doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

**Locate the corpus.** The session-log corpus for the current project lives at `~/.claude/projects/<cwd-encoded>/*.jsonl`, where `<cwd-encoded>` is the current working directory with `/` replaced by `-` (Claude Code's standard transcript-directory encoding). Glob that directory for `*.jsonl` files — each file is one session transcript.

**Skip subagent sessions (hard pre-filter).** Exclude any transcript whose filename begins with `agent-` (e.g. `agent-a1b2c3….jsonl`). These are subagent worker transcripts spawned by the parent session (Task/Agent dispatches, workflow workers, review agents) — they are the *agent's* execution logs, not the user's authored prose, and mining them would (a) attribute agent-authored dispatch text to the user and (b) massively inflate the corpus on any session that fanned out workers. The `agent-` filename prefix is a clean, unambiguous discriminator (Claude Code names all subagent transcripts this way). This filter runs BEFORE the count in Step 1b, so the over-cap gate sees only genuine user sessions. (Validated on a live run: a 43-file delta was 29 subagent transcripts + 14 user sessions — skipping the `agent-*` set is what made the delta tractable.)

**Read the style-audit log for incremental scope.** Read `KT_STYLE_AUDIT_LOG` (resolved path per the default above). If it exists, its most recent timestamp entry marks the boundary of the last mining pass — this run only needs to consider sessions modified/created after that timestamp (incremental scope, keeps repeat runs cheap). **If the log doesn't exist yet (first run)**, there is no prior boundary: window the initial scan to the last `KT_STYLE_LOOKBACK_DAYS` (default 90) days of session files, by file mtime or the transcript's own embedded timestamps.

**Reuse a prior external mine as a first-run boundary (avoid re-mining what's already mined).** If there is no audit-log yet BUT a prior full mine of this same corpus exists on disk — most notably a ditto run archived under `{knowledge_folder}/references/` (its `you-corpus.txt` mtime marks when it ran, and its `stats.json` records the session count/date-range it covered) — treat that prior mine's timestamp as the incremental boundary instead of doing a full-lookback re-scan. Then only the **delta** (sessions newer than that mine, after the `agent-*` skip above) needs fresh extraction; fold the delta's evidence in with the prior mine's already-reduced result rather than re-processing the whole corpus. This turns an all-time first run from a multi-million-token re-scan into a small delta mine. State clearly in the report which portion was reused vs freshly mined. (Validated on a live run: reused 1,697 prior-mined sessions + freshly mined a 10-session user delta, instead of re-scanning ~8.5M tokens.) If no such prior mine exists, fall back to the lookback window as above.

## Step 1: Extract User Prose (multi-stage filter)

The reference implementation of this filter is `extract-user-prose.py`, which lives alongside this SKILL.md at `plugin-claude-code/skills/audit-style/extract-user-prose.py`. **That script is the canonical algorithm** — this section documents the same stages in prose so the mining logic is auditable without reading Python, but the script is the executable source of truth; when in doubt about an edge case, defer to what the script actually does, or invoke it directly (`python3 .../extract-user-prose.py <session.jsonl>`) rather than re-deriving the filter by hand.

Each `.jsonl` line is one JSON object (a transcript event). The filter applies, in order:

1. **Stage 1 — role + block-type gate.** Keep only objects where `type == "user"` AND the nested `message.role == "user"`, and only the **text** content (a plain string, or list blocks with `type == "text"`). This is the load-bearing exclusion: it drops every `tool_result` block outright — tool outputs are not the user's voice, no matter how much prose they contain.
2. **Stage 2 — strip command/tool wrapper noise.** Even after Stage 1, some `role: user` events are Claude Code's own wrapper markup rather than something the user typed — local-command invocations and their echoed output/errors. Drop any text block containing `<local-command-*>`, `<command-name>`, `<command-args>`, `<local-command-stdout>`, `<local-command-caveat>`, or similar `<command-*>` tags.
3. **Stage 3 — drop skill-injection preambles and resume scaffolds.** Some `role: user` text is machine-injected context rather than something the user composed: skill-injection preambles (e.g. text beginning `Base directory for this skill:`, `Caveat:`), `<system-reminder>` blocks, and resume-scaffold text (lines beginning `Resume `). Drop any block matching these prefixes.
4. **Stage 4 — drop bare slash-commands.** A line that is just `/command` or `/command args` with no surrounding prose (starts with `/`) carries no working-style signal — it's an invocation, not a statement about how the user thinks or works. Drop it.

**Format-drift-fails-loud.** If a `.jsonl` line fails to parse as JSON, or if the transcript directory's schema no longer matches the shapes above (e.g. `message.role`/`message.content` fields renamed or restructured, `type` values changed), the skill must **surface this loudly** — report the parse/shape failure explicitly to the user with the offending file and line — and must NOT silently fall back to mining zero signal or guessing at a best-effort reinterpretation. A silent empty result set on schema drift is indistinguishable from "genuinely no signal this window," which would corrupt the receipts gate downstream (Step 3 could wrongly conclude "no evidence" when the real cause is "the extractor broke"). Report the drift, do not extract from the affected file, and continue with files that still parse.

## Step 1b: Over-Cap Gate

Before extracting from every session in scope, count how many session files fall in scope per Step 0 (incremental boundary, or the lookback window on first run).

**If sessions-to-scan > `KT_STYLE_MAX_SESSIONS`** (default 50), **STOP** — do not silently scan only the first N (that would silently bias toward whichever sessions happen to sort first, not the most relevant ones). Show the user an estimate (session count, earliest/latest date in range) and prompt:

> "Found N sessions in scope (exceeds the {max_sessions} cap). Options:"
> - **`recent`** — scan only the most recent `KT_STYLE_MAX_SESSIONS` sessions (drops the oldest ones from this pass; they remain queued for a future pass via the audit-log timestamp boundary)
> - **`all`** — scan every session in scope regardless of the cap (slower, higher token cost — shown estimate helps the user judge)
> - **`window <D>`** — narrow the scope to the last `D` days instead of the full lookback/incremental range, then re-count
> - **`cancel`** — abort this run without scanning or writing anything

Older sessions that are excluded by a `recent` or `window` choice are **not lost** — they stay queued for a later pass because the incremental boundary in `KT_STYLE_AUDIT_LOG` only advances to cover what was actually mined this run (see Step 5).

**If sessions-to-scan ≤ the cap**, proceed directly to Step 2 without prompting.

## Step 2: Infer Per Layer

For each session in scope, run the Step 1 filter to produce genuine user-prose lines (tagged with session id + date). Then cluster this prose across **all 5 mining layers** — every layer runs on every audit pass, none deferred:

1. **Definition of done** — what the user says "done" actually means in practice (e.g. what has to be true, verified, or observed before they accept a task as complete).
2. **Rejection criteria** — what the user pushes back on, redoes, or explicitly refuses, and why (the shape of "no, not like that").
3. **Debugging approach** — how the user directs root-causing versus patching, what evidence they ask to see before accepting a diagnosis, how they sequence investigation.
4. **Design taste** — recurring preferences about structure, simplicity, abstraction depth, naming, or architecture that the user states or enforces across sessions.
5. **Writing voice** — recurring stylistic instructions or corrections about tone, format, verbosity, or phrasing in written output.

For each layer, look for **recurring** patterns — the same shape of statement or correction appearing across more than one session — and draft each as a candidate one-line rule, paired with the specific prose lines that support it (the candidate's supporting quotes). A pattern seen in only one session is not yet a candidate; carry it forward as a note but do not draft a rule from single-session evidence (the receipts gate in Step 3 would reject it anyway — this just avoids wasted drafting effort).

## Step 3: RECEIPTS GATE (fail-closed)

This is the load-bearing gate of the entire skill. A candidate rule drafted in Step 2 **survives only if all three conditions hold**:

(a) **≥2 distinct sessions** — the supporting quotes must come from at least two different session transcripts (different `session` ids from the extraction), not two quotes from the same session repeated or rephrased. A pattern that only shows up once, however clearly stated, does not survive.

(b) **Dated verbatim quotes** — every supporting quote must be the literal, unparaphrased text the user typed (post-redaction, see Step 4), each tagged with the date it was said (from the transcript's timestamp). A paraphrase or a summary of "what the user seemed to mean" is not a receipt — only the actual words, dated, count as evidence.

(c) **No fabrication** — the candidate rule's stated generalization must be directly supported by the quotes attached to it, not extrapolated beyond what they say. If the rule statement claims more than the quotes demonstrate, either narrow the rule statement to match the evidence or drop it.

**If any of (a), (b), (c) fails, the candidate is DROPPED — not softened, not hedged, not staged with a caveat.** There is no partial-credit tier ("probably true but only 1 session" does not become a low-confidence entry). This is a fail-closed gate: absence of sufficient evidence means the candidate does not get written anywhere, full stop.

**Rule 36 note (this gate must be able to fail for the right reason):** the receipts gate is only meaningful if it can actually reject a candidate — a version of this step that always finds "enough" evidence, or that silently treats a single session as sufficient, would produce false passes that look identical to real ones from the outside. When implementing or later modifying this step, verify the negative case directly: deliberately test with a candidate whose only evidence is single-session, and confirm it gets dropped, not waved through. A candidate that survives only because the ≥2-session check was skipped, weakened, or never actually evaluated is a false pass, indistinguishable on the surface from a genuine one — the gate's value depends entirely on it being able to fail, and failing for the correct reason (insufficient distinct-session evidence), not an unrelated one.

## Step 3b: Source Rejection

Before treating any prose as evidence, exclude content whose origin is aria's own machinery rather than the user's independent working style — otherwise the audit would mine its own prior output back into "discovered" rules, closing a feedback loop that fabricates false corroboration.

**Never treat the following as evidence, even if they pass the Step 1 filter:**
- A message whose content is (or is dominated by) a `/command` invocation and its arguments — this is dispatch, not a statement of working style.
- Content sourced from **CLAUDE.md** (any project or workspace CLAUDE.md) — these are already-synthesized instructions, not raw user prose revealing style; mining them back "confirms" what was already written, not what was independently observed.
- Content sourced from **MEMORY.md** or any user-memory index file — same reasoning: already-synthesized, not primary evidence.
- Content sourced from an existing **`feedback_*.md`** file — this is the exact promotion output of a prior `/audit style` (or manual) pass; treating it as new evidence for a new candidate would let the skill cite its own prior conclusions as independent corroboration, silently inflating confidence without new information.

If a candidate's only supporting quotes turn out to trace back to one of these sources on closer inspection, that quote does not count toward the Step 3 receipts gate — re-evaluate whether the remaining quotes (from genuine session prose) still clear the ≥2-distinct-session bar on their own.

## Step 4: Redact + Stage

For every candidate that survives Step 3's gate, redact each surviving quote before it is written anywhere. **Mirror `extract-user-prose.py`'s `REDACTIONS` list** — the same categories (API keys, JWTs, GitHub/Slack/AWS tokens, password/secret/api-key key-value pairs, email addresses, IP addresses) must be scrubbed from the quote text, using the same patterns the reference script applies, not a looser ad hoc pass.

**If a quote cannot be safely redacted** (e.g. the secret-shaped content is structurally entangled with the sentence such that redaction would either leave a recoverable fragment or destroy the quote's meaning entirely), **drop that quote** rather than writing it in a partially-redacted or risky state. If dropping the unsafe quote causes the candidate to fall below the Step 3 receipts bar, the candidate is dropped too (redaction failure cascades through the same fail-closed logic as an evidence failure).

Redaction happens here so the report, the card, and any write all use the redacted quotes. **No file is written in this step** — where the survivors go (staged to `rules-backlog.md`, promoted to `feedback_*.md`, or nothing) is the user's choice at the Step 6 disposition gate, made against the full report + card. The redacted survivors are simply held for Steps 5–6.

**The write surface is fixed regardless of disposition:** staged survivors go to `{knowledge_folder}/intake/rules-backlog.md` (the `### YYYY-MM-DD — {title}` block below the `---` separator, rule statement + inline dated redacted receipts — the shape `/audit-knowledge` already expects). Promotion to `feedback_*.md` (or `rules/user-rules.md`) happens ONLY on the explicit promote-now disposition, and even then follows `/audit-knowledge`'s three-target logic. **The default disposition never writes `feedback_*.md`** — that stays a human-gated decision.

## Step 5: Report (the report IS the preview — nothing is written yet)

Render the full report below to the user. **No file has been written at this point** — this report, together with the Working Style card, is what the Step 6 disposition decision is made against. This replaces the old separate preview gate: the report shows exactly what *would* be staged/promoted, so the user decides against the real content.

**Output policy (emit-all — this is a fixed-structure report):** `/audit style` is a fixed-structure skill, not a one-liner — a zero count carries information, and the zero-states below are *distinct signals the user must be able to tell apart*. Emit every subsection defined below on every run, including its explicit zero-state line when it has no content. Do NOT collapse or omit an empty subsection; a silent omission is indistinguishable from "the skill didn't run that check."

### Part A — Every rule, stated individually with reasoning

Both passed and dropped candidates are stated in full — never collapse the dropped set into per-reason counts alone. Each dropped rule gets its own line with its specific reason.

```
## /audit style — <window>

### ✅ Passed the receipts gate  (M)
- **<rule statement>**  [<D> distinct sessions · confidence: <high|medium>]
    - why it passed: <one line — the recurring pattern the ≥2 sessions share>
    - [<session-8> <date>] "<redacted verbatim quote>"
    - [<session-8> <date>] "<redacted verbatim quote>"
  (repeat per passing candidate — NOT capped at 3; state all M)
  — zero-state: "0 passed — nothing eligible to stage this run."

### ✗ Dropped  (K)  — each rule + why
- **<candidate rule statement>** — dropped: <specific reason: single-session (only session X) | no verbatim quote | unredactable secret in only receipt | source-rejected (its evidence traced to a /command|CLAUDE.md|MEMORY|feedback_*)>
  (repeat per dropped candidate — state the RULE and its REASON, not just a count bucket)
  — zero-state: "0 dropped."

### Scan health
- Sessions scanned: <J> of <total-eligible>   (over-cap choice, if any: <recent|all|window N>)
- Extractor: <clean | schema-drift on P file(s): list them>   ← if P>0 this is NOT "no signal"; the extractor broke (Step 1 fail-loud) and those files were skipped
- Candidates drafted (Step 2): <N>   ·   Mined prose messages: <total>
- In-session-only (NOT in the shareable card): contradictions surfaced (#11), project-weighting of the evidence (#14) — render these here if present, but they never go into the card file.
```

**The three distinguishable zero-states** (never conflate — each has a different user action):
1. **`0 passed`, candidates drafted, extractor clean** → the gate did its job; evidence was genuinely too thin. Action: none, or widen with `/audit style all`.
2. **`0 passed` because extractor hit schema-drift** → the tool broke, NOT "no signal." Surface the drifted files (Step 1); the log boundary must NOT advance for them. Action: fix the extractor/filter.
3. **`0 mined` / very few sessions scanned** → window too thin. Action: re-run wider.

### Part B — "Your Working Style" (the shareable card)

After the rules, render a **Your Working Style** section — an ARIA-native working profile. (It occupies the same role as ditto's profile card, but is derived independently from ARIA's own knowledge — rules, memory, decision artifacts — and must not copy ditto's labels, framing, or naming shapes; see the anti-copy ban in element #1.) It is made richer by what ARIA knows that raw logs can't. Render it inline in the report AND (per Step 5b) write it as a self-contained shareable card file. Include these elements — every one that has content; omit #10 entirely if no evolution is found:

1. **Reasoning Type** — a short label (2-3 words) summarizing how the user reasons/decides. **Derive it independently every run — do NOT reuse a stock label or ditto's naming shape.** Procedure: (a) take the **top 2-3 highest-corroboration rules** (by distinct-session count) plus the through-line; (b) name what *those specific rules* add up to, using ARIA's own vocabulary of working-role nouns — e.g. **Operator, Reasoner, Reviewer, Lead, Builder, Maintainer** — paired with an adjective drawn from the user's actual dominant discipline (proof / gate / ground-truth / root-cause / long-term / etc.). The label is a **summary of the user's own top rules**, not a personality archetype. **Hard ban (anti-copy):** never emit ditto's default framing or its shape — do NOT use "Evidence-First …", do NOT use the "`<Adjective>-First <Noun>`" pattern, and do NOT carry any label forward from a prior run or example. If the top rules are all about acting only on verified proof, a label like "Proof-Based Operator" fits; if they're about a fixed pre-mortem→execute ceremony, "Gate-Driven Lead" fits — but derive from *this run's* top rules, don't pick from a menu. (Call it **Reasoning Type**, never "archetype" — "archetype" is ditto's frame.)
2. **Through-line** — one sentence capturing the pattern under all the laws, worded in ARIA's own framing (e.g. "The discipline that earns autonomy: nothing is trusted — a prior decision, a metric, a 'done' claim — until re-verified against ground truth"), NOT ditto's "the uncomfortable one" label.
3. **Work laws** — ALL passed work-domain laws, ranked by corroboration (session count), not capped.
4. **Design taste laws** — the passed design-domain laws.
5. **Writing voice laws** — the passed write-domain laws, register-split (casual input vs professional deliverable).
6. **Coverage stats — every stat LABELED with what it means**, not bare numbers. E.g.: "Sessions mined: J (distinct Claude Code conversations) · Your messages: M (only your typed prose — tool output and skill injections were filtered out) · Text volume: ≈T tokens ≈ roughly P pages of your writing · Date range: <first>→<last> · Secrets auto-redacted before analysis: R." Never emit a raw token count without saying what it represents.
7. **Corroboration vs. existing memory** — for each passed law, mark whether it **CONFIRMS** an existing `feedback_*.md`/`user-rules.md` entry (name it) or is **NEW** (not yet in memory). This is ARIA-unique — a raw-log tool cannot see the user's memory.
8. **Blind spots** — two kinds: (a) working-style dimensions ARIA HAS memory for but this mine found NO fresh evidence of (a discipline going quiet); and (b) **inferred blind spots the user may not be aware of** — asymmetries in the evidence itself (e.g. "every mined law is about verification/correctness; none about when-to-stop-polishing or delegation-trust — that absence is itself a signal"). State (b) as a careful, falsifiable observation, not a diagnosis.
9. **Decision-discipline fingerprint** — derived from the user's *artifacts* (ADRs, `/prospect`+`/retrospect` logs, the change-decision-framework usage), not messages: how they structure decisions (e.g. gate-chain ceremony, 7-step framework, ADR-with-alternatives). ARIA-unique.
10. **Evolution / drift** — ONLY if the dated evidence + memory history actually show a law changing over the range (e.g. "commit-vs-push tightened after a mid-June incident"). If no evolution is found, OMIT this element entirely — do not emit an empty "no evolution" line in the card.
12. **Consistency/confidence** — per law, a high/medium confidence from session-spread (already on each law in #3–#5).
13. **How to work with me** — a short, directive block an agent could load ("Before calling done, show it running live. Commit locally; never push unasked. On a fork you can verify, decide and show your work.").
15. **Anti-patterns I reject** — the rejection-criteria laws restated as "don'ts" (e.g. "Don't fake a green/screenshot. Don't expand a scoped fix. Don't push without asking.").

**Card is a strict subset of the report:** elements #11 (contradictions) and #14 (project-weighting) appear in Part A's Scan-health / in-session view ONLY — they must NOT be written into the shareable card file (a screenshot-safe artifact shouldn't name unresolved tensions or reveal what the user is working on). There is NO letter grade / seal (#16 excluded).

## Step 5b: Write the shareable card file

Write the Working Style card as a self-contained artifact to **`{knowledge_folder}/references/working-style/`**:
- `card-<YYYY-MM-DD>.html` — a standalone, styled, theme-aware HTML page (inline CSS, no external assets), containing elements #1–#9, #12, #13, #15 (NOT #11/#14). Dated filename so successive runs archive rather than clobber.
- `card-<YYYY-MM-DD>.md` — a markdown mirror of the same content, for diffing/grep.

Create `references/working-style/` if absent. This is the only file this skill writes unconditionally (it's a report artifact, not captured knowledge — it stages nothing and promotes nothing). If the user later declines all dispositions, the card still stands as a record of the run.

**Stamp `{knowledge_folder}/logs/style-audit-log.md`** (or `KT_STYLE_AUDIT_LOG`) with this run's timestamp + session-id range ONLY after a disposition that consumes the sessions (keep-staged or promote). On cancel, do NOT advance the boundary (the sessions stay eligible next run).

## Step 6: Disposition (single merged gate — default-first)

Present ONE decision. This is the only write-authorizing prompt (it absorbs the old preview gate — the report above already showed the exact content). Default is keep-as-recommended.

```
Disposition for the M passed rules:
  [keep]     Keep as recommended (default) — stage to rules-backlog.md for review
             at the next /audit-knowledge. Nothing written to feedback_*.md.
  [promote]  Promote the passed rules to user memory (feedback_*.md / user-rules.md)
             NOW, via /audit-knowledge's three-target logic.
  [specify]  Decide per-rule, or something else (tell me).
  [cancel]   Write nothing (the card file already saved; sessions stay eligible next run).

Press Enter / "keep" for the default.
```

- **`keep` (default, incl. bare Enter / any non-committal reply):** append the M passed rules to `rules-backlog.md` (Step 4's shape); they flow through `/audit-knowledge`'s existing `rule` disposition on the user's normal cadence. **Nothing is written to `feedback_*.md`.** Advance the audit-log boundary.
- **`promote`:** the user has explicitly authorized direct promotion — write the passed rules to `feedback_*.md` (or `rules/user-rules.md` for cross-project ARIA-behavior rules, or a project-tier `working-rules.md`) per `/audit-knowledge`'s three-target logic. This is the ONLY path that writes user memory, and only on this explicit choice. Advance the boundary.
- **`specify`:** surface the passed rules and take per-rule instructions (stage some, promote some, drop some) or any freeform direction. Follow it exactly; never invent a disposition the user didn't give.
- **`cancel`:** write nothing to backlog or memory; the card file from Step 5b remains. Do NOT advance the audit-log boundary.

**Restate the invariants:** `/audit style` is **opt-in only** (no cadence/SessionStart/threshold trigger — explicit invocation only), and its **default never writes `feedback_*.md`** — direct promotion happens only on the explicit `promote`/`specify` choice; otherwise memory is reached only through the human-gated `/audit-knowledge` review, same as any other rule-backlog entry.
