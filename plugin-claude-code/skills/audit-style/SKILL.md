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

**Read the style-audit log for incremental scope.** Read `KT_STYLE_AUDIT_LOG` (resolved path per the default above). If it exists, its most recent timestamp entry marks the boundary of the last mining pass — this run only needs to consider sessions modified/created after that timestamp (incremental scope, keeps repeat runs cheap). **If the log doesn't exist yet (first run)**, there is no prior boundary: window the initial scan to the last `KT_STYLE_LOOKBACK_DAYS` (default 90) days of session files, by file mtime or the transcript's own embedded timestamps.

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

**Append survivors to `{knowledge_folder}/intake/rules-backlog.md`**, following the same entry shape `/audit-knowledge` already expects for rule candidates (`### YYYY-MM-DD — {title}` block below the `---` separator), with the candidate's rule statement plus its inline dated receipts (session + date + redacted verbatim quote, for each supporting quote). This is the **only** knowledge-folder file this skill writes to for candidate content.

**This skill NEVER writes to any `feedback_*.md` file, directly or indirectly.** `feedback_*.md` is user-memory content, and promotion into user memory is a human-gated decision that happens later, during `/audit-knowledge`'s existing `rule` disposition review (see Step 5). `/audit style`'s entire write surface for candidates is the append to `rules-backlog.md`; it stages, it does not promote.

## Step 4b: Preview-First

**On the first-ever run of this skill** (no prior `KT_STYLE_AUDIT_LOG` entry exists), or whenever a run produces more than a small handful of new candidates, do not write anything yet. Instead, **show the candidates and their receipts** — the full list of survivors from Step 3/4, each with its rule statement and its redacted dated quotes — and wait for an explicit `y`/`n` from the user before appending anything to `rules-backlog.md`.

- **`y`** — proceed to write the survivors to `rules-backlog.md` and stamp the audit log (Step 5).
- **`n`** or no response — write nothing; report what would have been written, and do not advance the incremental boundary in the style-audit log (so the same sessions are eligible for mining again on the next run, rather than being silently skipped).

This preview gate exists because the receipts gate (Step 3) is necessarily judgment-laden at the margins (e.g. whether two quotes are "genuinely" the same recurring pattern) — a first run should let the user sanity-check the skill's calibration before it starts writing autonomously on subsequent runs.

## Step 5: Report + Hand Off

Report a one-line summary: `N mined, M passed, K dropped` — where `N` is the total candidate rules drafted in Step 2, `M` is how many survived the Step 3 gate (and Step 4's redaction) and were written to `rules-backlog.md`, and `K = N - M` is how many were dropped (with a brief one-line reason bucket, e.g. "K dropped: single-session evidence").

**Stamp `{knowledge_folder}/logs/style-audit-log.md`** (or the `KT_STYLE_AUDIT_LOG` path if configured) with the timestamp of this run and the session-id range covered, so the next run's Step 0 can resume incrementally from this boundary.

**Point at the existing promotion path** — do not describe a new one. The candidates just appended to `rules-backlog.md` are picked up by the existing `/audit-knowledge` audit cycle's **`rule` disposition** (see `/audit-knowledge` Step 2c3 and the Accept submenu's `rule` destination), which reviews rule-backlog entries and, on user approval, promotes them into **user memory `feedback_*.md`** (or the cross-project `rules/user-rules.md`, or a project-tier `working-rules.md`, per that skill's existing three-target logic). `/audit style` does not duplicate or bypass that review — it only feeds the same intake queue every other rule candidate goes through.

**Restate the invariants:** this skill is **opt-in only** — it does not run on any cadence, SessionStart check, or activity threshold, only on explicit invocation — and it **never writes `feedback_*.md` directly**; promotion into user memory always passes through the human-gated `/audit-knowledge` review, same as any other rule-backlog entry.
