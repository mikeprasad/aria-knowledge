---
name: retrospect
description: "Run a structured retrospective on a commit, range, PR, release, deployment, or session after execution. Trigger on /retrospect, postmortem, release review, or what went wrong."
argument-hint: "[<scope>] [<scope-arg>] [--linear-post] [--no-source]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, WebFetch, WebSearch
---

# /retrospect — Release retrospective with validation enforcement

Run a structured retrospective on a shipped commit range (or single commit, or current session). Produces a 10-section markdown report with per-fix verdicts, validation status, action recommendations, and re-diagnosis when fixes failed. Writes findings to `knowledge/logs/retrospect/` and runs aria's standard intake. Source spec: `docs/specs/2026-05-03-retrospect-skill-design.md`.

## Step 0: Inputs & Mode Detection

Parse the invocation arguments. The first positional argument is the **scope keyword**; subsequent positional arguments are scope-specific. Seven scopes plus a no-args default:

| Scope | Trigger | Backward-compat flag (still accepted) | Bundle source |
|---|---|---|---|
| **(no args)** | `/retrospect` | — | Auto-range: last push on current branch — `git log @{push}..HEAD` if upstream is set, else `git log -10` and ask user to confirm range |
| **commit** | `/retrospect commit <hash>` | `--commit <hash>` | Single commit |
| **range** | `/retrospect range <ref1>..<ref2>` | `--range <ref1>..<ref2>` | `git log <ref1>..<ref2>` |
| **pr** | `/retrospect pr <num>` | `--pr <num>` | `gh pr view <num> --json commits` then resolve to commit SHAs |
| **session** | `/retrospect session` | `--session` | Files Claude has touched in the current conversation (read from session state, not git). No deploy yet — all fixes auto-tag 🚫 unvalidatable. |
| **release** (NEW) | `/retrospect release` | (none) | Commits since the most recent semver tag. `git describe --tags --abbrev=0` to find the tag, then `git log <tag>..HEAD`. If no tags exist on the repo, fall back to auto-range and warn the user. |
| **deployment** (NEW) | `/retrospect deployment` | (none) | Commits since the last deployment marker — see "Deployment detection cascade" below. |

**Argument parsing rules:**
- If the first positional arg matches a scope keyword (case-insensitive), use it. Otherwise treat it as auto-range and try to parse the args under the legacy flag form.
- Backward-compat flag forms (`--range`, `--pr`, `--session`, `--commit`) remain accepted indefinitely. Both `/retrospect range a..b` and `/retrospect --range a..b` resolve identically.
- Modifier flags (apply to any scope): `--linear-post` (post the retrospective verdict to detected Linear tickets at end), `--no-source` (skip Step 3.5's Evidence-Sourcing Pass).

### Deployment detection cascade (Q2.1=3)

When invoked as `/retrospect deployment`, attempt to resolve the deployment marker by trying these signals in order. First success wins; on no-success, fall through to the prompt.

1. **GitHub Releases** — `gh release view --json publishedAt,tagName 2>/dev/null` (most recent release). If returned, treat the release tag as the marker; bundle = `git log <tag>..HEAD`.
2. **Semver tags** — `git tag --sort=-creatordate | head -1`. If a tag matches `v?\d+\.\d+\.\d+` (and step 1 returned nothing), use it as the marker.
3. **Last commit on `main` (or `master`)** — `git log -1 --format=%H origin/main` (or `origin/master` if `main` doesn't exist). Treat as the marker; bundle = `git log <sha>..HEAD`. This catches projects without releases or tags.
4. **Prompt user** — if none of the above resolved (e.g., no remote, no tags, no `gh` auth), ask: "I couldn't auto-detect the last deployment for `/retrospect deployment`. Provide a marker (commit hash, tag, or ISO timestamp), or type `auto-range` to fall back to last-push behavior."

Print the resolved marker source ("Detected via gh release: v1.4.2 (2026-05-01)") in the Anchor block (§4.1) so the user can verify what the skill thought "deployment" meant.

After mode detection, gather:

1. **Goal** — Ask the user: "What was this release/range supposed to fix? (One sentence is fine.)" If they don't reply, fall back to commit message subjects + PR description.
2. **Tickets** — Scan commit messages with regex `\b([A-Z]{2,}-\d+)\b` for Linear-style ticket IDs. If any are found AND Linear MCP is available, fetch each ticket's Product/Technical Intake + recent comments. If Linear MCP is unavailable, note "ticket context unavailable" but continue.
3. **Post-deploy outcome** — Ask the user: "For each fix, what's the post-ship evidence? (✅ closed / ⚠ partial / ❌ failed / ❓ untested)" Show the per-commit list and accept inline replies. If user can't supply evidence for any fix, mark those ❓ and note that §10 will recommend instrumentation.

If scope is `session` (or invoked via `--session`), skip post-deploy outcome (no production yet) and tag all fixes 🚫 unvalidatable; their actions will resolve to HOLD-PENDING-DEPLOY.

## Step 0.5: Active Knowledge Surfacing

If the user's config (`~/.claude/aria-knowledge.local.md`) has `active_knowledge_surfacing: true` (default as of v2.15.0), surface relevant tagged knowledge BEFORE Steps 1-3 so loaded files inform pattern selection and evidence sourcing. If the field is `false`, skip this step entirely (note `Active surfacing: disabled` in the Anchor block).

**Algorithm:**

1. **Build query.** Combine, separated by spaces: the Goal sentence from Step 0; the first 3 commit subjects in the bundle range; PR title if scope is `pr`; any detected Linear ticket IDs (e.g., `LINEAR-123`); the resolved deployment marker label if scope is `deployment`; the range descriptor (e.g., `v0.4.2..HEAD`).

2. **Read the index.** `Read` `<knowledge_folder>/index.md` (resolve `<knowledge_folder>` from the config's `knowledge_folder` field). Parse the `## Tag Index` section for `### tagname` headers — that's the matching vocabulary (~77 known tags as of v2.15.0). Ignore the `## Other Tags` section (freeform tier, intentionally excluded from auto-surfacing).

3. **Tokenize.** Lowercase the query, strip punctuation to spaces, dedupe to a word set.

4. **Match.** Exact word-vs-tag equality only — no substring, no fuzzy. Collect the set of matched tags.

5. **Threshold gate.** If fewer than 2 tags matched, note `Active surfacing: 0 matches (below threshold)` in the Anchor block and skip to Step 1.

6. **Collect files.** Under each matched tag's `### tag` section, gather the `- path — description` lines. Dedupe by path. Cap at top-5 by first-appearance order.

7. **Ledger filter (best-effort).** Run `ls -t /tmp/aria-active-* 2>/dev/null | head -1` via Bash to find the current session's ledger. If found, read it and drop any matched paths already listed there. If no ledger exists, proceed unfiltered.

8. **Read matched files.** For each remaining path (up to 5), `Read` the full file into context. **Prefer files under `logs/retrospect/`** if any matched — they're prior retros on overlapping tags, which is the loop-closure case (past retros inform new retros on the same topic). If both a retro and a non-retro file match, prioritize the retro within the top-5 cap.

9. **Summarize.** Before Step 1's Anchor Block, emit a 3-line surfacing block:

    ```
    Active Knowledge Surfacing:
      Tags matched: <tag1> <tag2> ...
      Files loaded: <N> (<file1>, <file2>, ...)
      Relevance: <one sentence per file: why this informs the retrospective>
    ```

10. **Carry-forward.** These loaded files become input to Step 2 (Load Pattern Libraries — past retros may already have catalogued the relevant failure-mode patterns) and Step 3.5 (Evidence-Sourcing Pass — they may already provide validation or falsification for fixes in this range).

11. **Tracked artifacts surfacing (added v2.16.1).** After Step 10's carry-forward, ALSO surface CODEMAP + STITCH for the analyzed range's project. The shared lib at `${CLAUDE_PLUGIN_ROOT}/bin/lib-tracked-artifacts.sh` implements equivalent logic for hooks; this step inlines the algorithm for skill-context portability.

    a. **Detect project tag from changed file paths.** Run `git diff --name-only <range>` for the analyzed bundle. For each changed file, check whether any `projects_list[<tag>].path` appears as substring. Count matches per tag; pick the tag with the most matches. Tie-breaker: explicit project flag if provided. If no detection (e.g., bundle touches knowledge folder only, no project files), skip the rest of Step 11.

    b. **Resolve project root via Bash.** Parse `projects_list:` from `~/.claude/aria-knowledge.local.md` frontmatter (comma-separated `tag:path`). For the detected tag, compute `project_root = $HOME/Projects/<path>`. If directory doesn't exist, skip.

    c. **CODEMAP directory load** (if `{project_root}/CODEMAP.md` exists). Compute boundary via `awk '/^## [0-9]+\.|^---$/ && NR>5 {print NR; exit}' "{project_root}/CODEMAP.md"`; Read limit = `(end - 1)` (fallback 50 if awk empty). Compute `age = (today - mtime).days`; read `codemap_staleness_threshold_days` (default 14). If `age > 2*threshold`, refuse and emit `[refused — run /codemap update first]`. Else if `age > threshold`, annotate `[STALE — consider /codemap update]`. Else `fresh`. Unless refused: `Read {project_root}/CODEMAP.md offset=0 limit=<end-1>`.

    d. **STITCH load** (only if `{project_root}/STITCH.md` exists — multi-repo signal). Same staleness logic with `stitch_staleness_threshold_days` (default 30). Unless refused: `Read {project_root}/STITCH.md` (full file).

    e. **Ledger dedup.** Locate session ledger via `ls -t /tmp/aria-active-* 2>/dev/null | head -1`. Before loading in (c)/(d), grep ledger for each artifact path; if found, silent skip (already surfaced by earlier T-1/T-2/T-3 trigger) and emit `Tracked artifacts: (already loaded earlier this session for {tag})` in the surfacing block. After loading, append loaded paths to the ledger.

    f. **Output.** Extend the Step 9 surfacing block with a 4th line:
        ```
        Tracked artifacts: CODEMAP directory + STITCH for {tag} ({N} / {M} days fresh)
        ```
        Variants: `CODEMAP directory only` for single-repo (no STITCH); `(no CODEMAP for {tag})` if missing; `[STALE — consider /codemap update]` annotation; `(already loaded earlier this session)` if ledger-deduped; `(none — no project detected)` if (a) returned nothing.

    g. **Carry-forward.** The loaded artifacts become available to Steps 3+ — particularly Step 3 (Enumerate Fixes; CODEMAP sections map changed files to features/responsibilities) and Step 3.5 (Evidence-Sourcing Pass; CODEMAP can validate that a fix actually touches the expected feature surface).

    Skip Step 11 entirely if `active_knowledge_surfacing: false` (already gated above).

## Step 1: Print the Anchor Block

Before producing any verdict, emit the anchor so the rest of the report can be traced to inputs:

```
Anchor:
  Goal:    <stated goal>
  Mode:    <auto-range | commit | range | pr | session | release | deployment>
  Range:   <commit range descriptor, e.g. v0.4.2..HEAD, 12 commits, 38 files>
  Tickets: <LINEAR-123 (Acceptance: ...), LINEAR-456 (...) | (none) | (unavailable)>
  Outcome: <user-supplied per-fix status table | (untested) | (per-session — no deploy)>
```

## Step 2: Load Pattern Libraries

Read the canonical pattern library at `~/knowledge/rules/retrospect-patterns.md` (resolved per `~/.claude/aria-knowledge.local.md` `knowledge_root`).

If the bundle is detected to belong to a known project (commits include paths under a configured `projects_list[<tag>].project_root`), additionally read `~/knowledge/projects/<tag>/retrospect-patterns.md` if it exists.

Hold both pattern lists in context for use in §4.4 (Failure-Mode Pattern Check). Do not run pattern detection yet — this step is just loading.

## Step 3: Enumerate Fixes & Preliminary Triage

For the loaded bundle, enumerate each *fix*. A fix is one of:
- A commit whose message describes a fix or change (`fix:`, `feat:`, `refactor:`, etc.)
- A logical sub-change within a multi-concern commit (rare; usually 1 commit = 1 fix)

Number them `#1, #2, …` in commit order. For each fix, capture:
- Short SHA
- Subject line
- Files touched (path list)
- LOC added/deleted
- **Preliminary Bundle-verified?** — provisional ✅ verified / 🤷 unverified / N/A (session mode). Use the user-supplied evidence from Step 0 #3 as a starting point. Step 3.5's bundle-marker pass will attempt to upgrade 🤷 by sourcing the deployed bundle.
- **Preliminary Validated?** — provisional classification using the Step 5 taxonomy (✅ / ⚠ partial / ❌ / ❓ / 🚫). Use the user-supplied post-deploy outcome from Step 0 #3 as the starting point. Step 3.5's outcome pass will attempt to upgrade ⚠/❓/🚫 by sourcing post-deploy evidence (logs, repro tests, ticket comments). These are DRAFT values — the FINAL Validated? values emitted in §4.3 reflect post-Step-3.5 state.

If `session` scope, enumerate by file-touch sets that resolve a single concern (Codex's judgment from session context). Preliminary Bundle-verified? = N/A and Preliminary Validated? = 🚫 unvalidatable (no deploy yet).

After preliminary triage, list every fix whose Preliminary Bundle-verified? is 🤷 — these are candidates for Step 3.5's **bundle-marker pass**. Separately, list every fix whose Preliminary Validated? is ⚠ partial / ❓ unvalidated / 🚫 unvalidatable — these are candidates for Step 3.5's **outcome pass**. ❌ Invalidated fixes skip Step 3.5 (they go directly to REVERT/REDO-MINIMAL in §4.3 unless the user contests the falsification). ✅ Validated fixes also skip Step 3.5 (already confirmed).

## Step 3.5: Evidence-Sourcing Pass

Two sub-passes that run in order before the report is rendered. Goal: convert as many 🤷 / ⚠ / ❓ / 🚫 candidates from Step 3 to ✅ or ❌ as possible *before* §4.2 emits its bundle-verification verdict and §4.3 emits its per-fix Validated? verdict.

This step can be skipped with the `--no-source` flag for a quick structural review. When skipped, all preliminary statuses pass through to §4.2 and §4.3 unchanged and §4.10 lists every gap as NOT-ATTEMPTED.

The synchronous-barrier discipline applies: if a sub-pass surfaces a USER-INPUT ask, hold for response (per `feedback_hold_gate_steps`). Default to one ask at a time (per `feedback_per_item_review_cadence`).

### 3.5.1: Bundle-Marker Sub-Pass (resolves 🤷)

For each fix from Step 3 with Preliminary Bundle-verified? = 🤷, attempt to confirm the fix's code is present in the deployed bundle.

**Auto-source candidates** (most retrospects fall here):
- **Bundle fetch + grep** — `Bash curl -s <deployed-bundle-url> | grep -F '<unique-marker-string>'`. The unique marker is either a function name from the diff, a comment string the fix added, or a `[<TAG>-DIAG]` instrumentation marker. Source the deployed-bundle-url from the user (Step 0) or from common conventions (`<deploy-domain>/static/js/main.<hash>.js` for Vercel/Webpack builds).
- **WebFetch on bundle URL** — same as above but via `WebFetch` when the URL is public and HTML-wrapped.
- **CI artifact check** — `Bash gh run view <run-id> --log` (resolved from the commit's CI status) → confirm the deploy job ran AND the artifact hash matches.
- **Source-map verification** — fetch the deployed source-map, confirm it references the post-fix line numbers.
- **Deploy log inspection** — Vercel logs MCP, Bitbucket pipeline output via `gh api`, etc.

**USER-INPUT escape hatch:**
- If no bundle URL is known and the user hasn't provided one, ask: "Need a deployed-bundle URL or unique in-bundle marker for fix #N (<short-sha>: <subject>) to verify it shipped. Provide URL+marker, paste a curl-grep result, or skip (fix stays 🤷)."

Record per fix using the same shape as /prospect's 3.5.2:

```
Fix #N — bundle-marker result:
  Question:           Did fix #N's code reach the deployed bundle?
  Tool used:          <Bash curl <url> | WebFetch <url> | gh run view <id> | mcp__vercel__get_logs | ASK <surfaced-to-user>>
  Finding:            <one-paragraph factual summary, with URL anchor or grep hit>
  Verdict:            UPGRADED-TO-✅ verified | UPGRADED-TO-❌ NOT-IN-BUNDLE | NO-MOVEMENT (still 🤷) | INCONCLUSIVE
  New Bundle-verified?: <updated tag>
```

When this sub-pass completes, every fix has a final Bundle-verified? value (✅ verified / 🤷 unverified / ❌ not-in-bundle). §4.2 emits this state directly. ❌ NOT-IN-BUNDLE is a strong signal — the fix definitively did not ship; its action defaults to REVERT or RESHIP-AND-VERIFY in §4.3.

### 3.5.2: Outcome Sub-Pass (resolves ⚠ partial / ❓ unvalidated / 🚫 unvalidatable)

For each fix from Step 3 with Preliminary Validated? = ⚠ / ❓ / 🚫 AND Bundle-verified? ≠ 🤷 (a fix that didn't ship can't be outcome-validated), attempt to confirm the fix's outcome in production.

**Generate the decisive question** — what observable evidence would change the verdict from ⚠/❓/🚫 to ✅ Validated or ❌ Invalidated? Format:

```
Fix #N: <subject>
  Preliminary Validated?:  <⚠/❓/🚫>
  Decisive question:        <one-line — "what observable evidence would close this?">
  Answer source:            AUTO-SOURCEABLE | USER-INPUT | MIXED
  Sourcing plan:            <tools/queries to run>
```

**Auto-source candidates (retrospect-specific):**
- **Production log queries** — `mcp__vercel__get_logs`, `mcp__supabase__get_logs`, `Bash gh run view`, log-tail via SSH. Look for: (a) absence of the error event the fix targeted, (b) presence of the success event, (c) post-deploy regression signals.
- **Linear ticket comments** — `mcp__linear__list_comments <ticket-id>` for any ticket cited in commit messages. QA, support, and product comments often record post-deploy outcome ("verified fixed in PROD," "still reproducing," etc.). High-signal source.
- **Repro test execution** — if the bug had a documented repro and the test infrastructure is local, run it: `Bash <test-command>` (read-only or sandboxed). NEVER run repro tests that mutate production data.
- **GH commit/check status** — `Bash gh api repos/<owner>/<repo>/commits/<sha>/check-runs` → CI green / red post-fix.
- **Web fetch on monitoring dashboards** — only if URLs are known and public (rare; usually demoted to USER-INPUT).
- **`git log` on the touched files since deploy** — if other commits have already modified the same lines after the fix, that may constitute a regression signal.

**USER-INPUT escape hatch (and when to demote to it):**
- Reproduction tests that require staging access, real user accounts, or interactive QA — demote.
- Subjective acceptance ("does this feel fast enough now?") — demote.
- Anything requiring credentials Step 3.5 doesn't have authorization to use — demote.

Surface format mirrors /prospect's 3.5.3 exactly:

```
[ASK #M of K] Fix #N — <subject> (<short-sha>)

Why this matters:
  <one-line — what changes about Fix #N's verdict if we know this>

What I tried autonomously (if MIXED):
  <one-line — e.g., "Queried Vercel logs since deploy; found 0 occurrences of the targeted error and 4 of an adjacent error. Ambiguous — need your read on whether the adjacent one is a regression.">

Citations / context inline:
  <log excerpts, ticket comment quotes, test output — whatever the answer depends on>

Options:
  1) <option, with one-line consequence>
  2) <option, with one-line consequence>
  3) Other — describe in reply
  4) Skip — leave fix #N at <preliminary status>; it will HOLD-PENDING-EVIDENCE in §4.10
```

Same rules as /prospect's 3.5.3: neutral framing, separate Recommendation line allowed below options, per-question explicit pick, bare-number replies pick, "Skip" defaults to HOLD-PENDING-EVIDENCE / HOLD-PENDING-DEPLOY / HOLD-PENDING-VERIFICATION as appropriate.

Record per fix:

```
Fix #N — outcome result:
  Question:           <repeat decisive question>
  Tool used:          <listed>
  Finding:            <factual summary with citations>
  User pick (if any): <option N | "skip" | "other: <text>">
  Verdict:            UPGRADED-TO-✅ Validated | UPGRADED-TO-⚠ partial | UPGRADED-TO-❌ Invalidated | NO-MOVEMENT | INCONCLUSIVE
  New Validated?:     <updated tag with sub-tag where applicable>
```

### 3.5.3: Constraints (apply to both sub-passes)

- **Rule 33 — verify against current docs**: When sourcing third-party API/SDK behavior post-deploy, read the official current docs.
- **No credential reads** without explicit per-session permission (per `feedback_ask_before_credentials`).
- **No destructive probes** — read-only commands only. No `rm`, `git reset`, `git push`, `gh pr merge`, no migration runs, no PROD writes of any kind.
- **No PROD-mutating repro tests** — if a repro requires writing to production data, demote to USER-INPUT.
- **Time-box per fix**: ~5 tool-call rounds maximum per decisive question. INCONCLUSIVE after that; demote residual to USER-INPUT.
- **Evidence quality bar**: a single corroborating source upgrades only to ⚠ partial (with sub-tag `closed-part-of-target`). Two independent sources required for ✅ Validated. One contradicting authoritative source falsifies to ❌.

### 3.5.4: Pass Summary

When both sub-passes complete, emit a one-block summary before moving to Step 4:

```
Evidence-Sourcing Pass complete.

Bundle-marker sub-pass (§3.5.1):
  Candidates examined:        <N>
  Upgraded to ✅ verified:     <N>
  Upgraded to ❌ not-in-bundle: <N>
  No movement (still 🤷):       <N>
  Skipped by user:             <N>

Outcome sub-pass (§3.5.2):
  Candidates examined:        <N>
  Upgraded to ✅ Validated:    <N>
  Upgraded to ⚠ partial:       <N>
  Upgraded to ❌ Invalidated:  <N>
  No movement (still ⚠/❓/🚫): <N>
  Skipped by user:             <N>

Total tool calls:             ~<N>
Skipped by --no-source:       <N> (entire pass)
```

The post-pass values feed §4.2 (Bundle-verified?) and §4.3 (Validated?). The residual 🤷 / ⚠ / ❓ / 🚫 plus their attempt-status feed §4.10.

## Step 4: Produce the 10-Section Retrospective Report

Render a markdown document with the 10 sections below in order. Each section heading uses `### N. <title>` format. Sections that don't apply to the current scope are emitted with a one-line "N/A: <reason>" — never silently skipped.

### 4.1. Section 1 — Anchor & Inputs

Re-emit the anchor block from Step 1, verbatim, as Section 1 of the report. This makes the report self-contained when read outside the chat.

### 4.2. Section 2 — Bundle-Verification Gate

For each fix from Step 3, emit the **post-Step-3.5.1** Bundle-verified? status. §4.2 is the bundle-deployment ledger; its values come directly from Step 3.5.1's Bundle-Marker Sub-Pass, which already attempted to source the marker autonomously and surfaced any USER-INPUT asks that were needed.

Three possible statuses per fix:

- **✅ Verified** — bundle contains the fix's marker. Evidence comes from one of: unique in-bundle marker grep on the deployed asset (e.g., `curl https://<deployed-url>/<bundle> | grep <marker>`), deploy log + bundle hash matching the commit's CI artifact, or source-map verification. Step 3.5.1's "Tool used" + "Finding" cite the source.
- **🤷 Bundle-unverified** — Step 3.5.1 attempted to source the marker but could not confirm. Reasons captured from 3.5.1's verdict (NO-MOVEMENT, INCONCLUSIVE, or DEFERRED-BY-USER). Fix does NOT receive a Validated? status in §4.3 — its action defaults to HOLD-PENDING-VERIFICATION and §4.10 will list the residual evidence ask.
- **❌ Not-in-bundle** — Step 3.5.1 *positively confirmed* the fix did NOT ship (e.g., bundle returned 200 but the marker grep was empty, OR the deploy log shows a failed/superseded job). This is a strong signal: the fix's action defaults to RESHIP-AND-VERIFY (REDO-MINIMAL bound to a re-deploy) or REVERT (if the fix was a refactor whose absence isn't blocking) in §4.3. Validated? is N/A (can't validate code that didn't ship).

Render as a clear list per fix:

```
Fix #N: <subject> (<short-sha>)  →  <✅ Verified | 🤷 Bundle-unverified | ❌ Not-in-bundle>
  Source: <Step 3.5.1 tool/finding citation, e.g., "curl <url> | grep '[CSB-DIAG-042]' → 1 hit">
  (For 🤷) Reason: <Step 3.5.1 verdict tag>
  (For ❌) Implication: <RESHIP-AND-VERIFY or REVERT, deferred to §4.3 action>
```

If the scope is `session`, this section emits "N/A: session scope (no deploy yet)." Step 3.5.1 is also a no-op in this scope.

### 4.3. Section 3 — Per-Fix Verdict

For each fix from Step 3 that passed §4.2 (bundle verified or session mode), emit a horizontal-rule-separated block with these fields. Mirror the formatting style of the baseline review tag taxonomy (✅, ⚠ partial, ⚠ over-engineered, ⚠ theory-wrong, ⚠ counterproductive).

Required fields:
- **Status tag** — one of ✅ / ⚠ partial / ⚠ over-engineered / ⚠ theory-wrong / ⚠ counterproductive
- **Necessary?** — YES / NO / UNCLEAR with one-sentence reason
- **Complications introduced** — concrete list, or "None"
- **Minimal alternative** — "the smallest version of this change that would have addressed the goal." If the actual fix is the minimal version, write "This is the minimal version." Forces Rule 13.
- **Maintenance cost** — "what future contributors must now know / maintain because of this change." Forces Rule 12 / Rule 14.
- **Validated?** — one of the 5 statuses from Step 5, **post-Step-3.5.2**. The Step 3.5.2 outcome sub-pass had its chance to upgrade this from the preliminary value emitted in Step 3; this field reflects the FINAL state. Use 🤷 if §4.2 flagged the fix Bundle-unverified (Step 3.5.2 doesn't run on those — outcome can't be validated for code that didn't ship). Use N/A if §4.2 emitted ❌ Not-in-bundle.
- **Action** — one of: KEEP / REVERT / REDO-MINIMAL / RESHIP-AND-VERIFY / FOLLOWUP-TICKET / HOLD-PENDING-EVIDENCE / HOLD-PENDING-DEPLOY (session scope only) / HOLD-PENDING-VERIFICATION (bundle-unverified only). RESHIP-AND-VERIFY is for ❌ Not-in-bundle fixes whose code is correct but didn't ship — re-deploy and re-run /retrospect after.

Optional fields:
- **Evidence sourced** — when Step 3.5.2 produced a verdict-changing finding, summarize it in one line with citation. Example: "Auto-sourced via mcp__vercel__get_logs since deploy 2026-05-04 — 0 occurrences of error E_FOO; upgraded ❓→✅." If Step 3.5.2 produced no movement OR was skipped, omit this field.
- **Rule cite** — if a complication maps to a Universal Rule overstep, cite it inline (e.g., "violates Rule 14 — abstraction beyond purposeful layers")

Render each fix as a block, not a wide table:

```
Fix #N: <subject> (<short-sha>)
Status:                <tag>
Necessary?:            <YES/NO/UNCLEAR> — <reason>
Complications:         <list or None>
Minimal alternative:   <description>
Maintenance cost:      <description>
Validated?:            <status>  (post-Step-3.5.2)
Evidence sourced (optional): <one-line with citation>
Action:                <action>
Rule cite (optional):  <rule>
────────────────────────────────────────
```

**Hard rule (action gating):**
- KEEP requires post-Step-3.5.2 Validated? of ✅ or ⚠ partial.
- ❓ Unvalidated → HOLD-PENDING-EVIDENCE (forces §4.10 residual ask).
- 🚫 Unvalidatable → HOLD-PENDING-DEPLOY (session scope) or HOLD-PENDING-EVIDENCE (otherwise).
- 🤷 Bundle-unverified (§4.2) → HOLD-PENDING-VERIFICATION (Step 3.5.1 already attempted; user must verify).
- ❌ Not-in-bundle (§4.2) → RESHIP-AND-VERIFY (default) or REVERT (only if fix was non-blocking refactor that's safer to drop than re-ship).
- ❌ Invalidated (§4.3) → REVERT or REDO-MINIMAL (per the smallest-alternative analysis).

The hard rule mirrors /prospect's discipline: actions cannot upgrade past their evidence floor. Step 3.5 has already attempted to lift evidence floors; what remains is genuine residual uncertainty that gates action selection.

### 4.4. Section 4 — Failure-Mode Pattern Check

Run the bundle against both pattern libraries loaded in Step 2 (canonical + project-specific if applicable). Detection is judgment-based — read each pattern's "Detection cues" and assess whether the bundle, commit messages, or session transcript exhibits them.

For each pattern hit, emit:

```
[PATTERN] <pattern-name> (source: rules/retrospect-patterns.md | projects/<proj>/retrospect-patterns.md)
  Evidence: <what in the bundle/transcript triggered the hit>
  Counter-discipline: <one-line reminder of the pattern's counter-discipline>
```

If no patterns hit, emit: "No catalogued failure-mode patterns detected. (See §9 for novel patterns.)"

### 4.5. Section 5 — Cross-Change Tally

Emit raw counts only — no interpretation in v1.

```
Tally:
  Fixes shipped:                    <N>
  Validated (✅):                    <N>   (post-Step-3.5.2)
  Partially validated (⚠):           <N>   (post-Step-3.5.2)
  Invalidated (❌):                  <N>   (post-Step-3.5.2)
  Unvalidated (❓):                  <N>   (post-Step-3.5.2)
  Unvalidatable (🚫):                <N>   (post-Step-3.5.2)
  Bundle-verified (✅):              <N>   (post-Step-3.5.1, §4.2)
  Bundle-unverified (🤷):            <N>   (post-Step-3.5.1, §4.2)
  Not-in-bundle (❌):                 <N>   (post-Step-3.5.1, §4.2)
  Theory-driven refactors:          <N>
  Required by Linear acceptance:    <N>
  Discovered-during-process:        <N>
  Pattern hits this run:            <N>

Evidence-Sourcing Pass — bundle-marker sub-pass (§3.5.1):
  Candidates examined:              <N>
  Upgraded to ✅ verified:           <N>
  Upgraded to ❌ not-in-bundle:      <N>
  No movement (still 🤷):            <N>
  Skipped by user:                  <N>

Evidence-Sourcing Pass — outcome sub-pass (§3.5.2):
  Candidates examined:              <N>
  Upgraded to ✅ Validated:          <N>
  Upgraded to ⚠ partial:             <N>
  Upgraded to ❌ Invalidated:        <N>
  No movement (still ⚠/❓/🚫):       <N>
  Skipped by user:                  <N>

Sourcing pass overall:
  Total tool calls:                 ~<N>
  Skipped by --no-source:           <N>   (entire pass)
```

A "theory-driven refactor" is a fix that rewrote working code based on a hypothesis rather than a confirmed bug location. Discovered-during-process means the fix addresses a bug found while working on something else (not the original goal).

Interpretation of these counts is left to §4.6, §4.7, and §4.9.

### 4.6. Section 6 — Re-frame Check

Three questions, in order. Answer each in 1–2 sentences with the supporting evidence.

1. **Is the original problem statement still right?** Or did the bundle reveal that the user-reported bug is a different bug than the bundle was aimed at?
2. **Was the bug correctly scoped?** Single bug, or multiple bugs presenting as one?
3. **Is the user-reproducible scenario still the right test?** Or has the testing surface drifted?

If the answer to #1 is "no," explicitly note: "Re-frame triggered. Hold all fixes targeting the *previous* problem statement pending re-diagnosis (§4.7)."

### 4.7. Section 7 — Re-diagnosis

List the **surviving hypotheses** for the actual root cause (only run this section if any fix's *post-Step-3.5.2* Validated? is ❌ Invalidated or ⚠ partial, OR §4.6 triggered re-frame). For each hypothesis:

```
Hypothesis: <one-line statement>
  Used by fixes: <#1, #3, #5>
  Evidence FOR:    <observations consistent with this hypothesis — INCLUDE Step 3.5.2 sourced findings with citations>
  Evidence AGAINST: <observations inconsistent — INCLUDE Step 3.5.2 sourced findings>
  Sourcing attempted: <YES (see Step 3.5.2 result for fixes #N) | NO (auto-sourcing skipped, declined, or not categorized as auto-sourceable)>
  Confidence:      LOW / MEDIUM / HIGH
  To confirm:      <specific signal to look for — feeds §4.10>
```

Evidence FOR/AGAINST must integrate any findings from Step 3.5.2's outcome sub-pass. If Step 3.5.2 produced a finding that moved a fix to ⚠ partial (e.g., `closed-part-of-target` upgrade from ❓), cite that finding here as Evidence FOR the partial-success hypothesis AND as Evidence AGAINST the full-fix-worked hypothesis. If Step 3.5.2 produced a contradicting finding the user contested or overrode, note both perspectives.

Discarded hypotheses (ones the bundle's outcomes OR Step 3.5.2's sourcing proved wrong) are listed separately under "Hypotheses ruled out by this retrospective or sourcing pass" with one-line reasons and source citations where applicable. This is *learning*, not waste — captures what was considered AND what evidence retired it.

If all fixes are post-Step-3.5.2 ✅ validated and §4.6 didn't trigger, this section emits "N/A: all fixes validated (Step 3.5.2 closed all gaps)."

### 4.8. Section 8 — Action Verdict

Per fix, the action determined in §4.3. Render as a clear list:

```
Action verdict:
  Fix #1: <ACTION>  — <one-line reason>
  Fix #2: <ACTION>  — <one-line reason>
  ...
```

For REVERT actions, provide the exact `git revert <sha>` command. For REDO-MINIMAL actions, provide the minimal alternative diff (from §4.3). For FOLLOWUP-TICKET actions, draft a Linear ticket title + Product/Technical Intake skeleton. For RESHIP-AND-VERIFY actions (introduced when §4.2 emitted ❌ Not-in-bundle), provide: (a) the re-deploy command appropriate to the project (`gh workflow run deploy.yml --ref main`, `vercel --prod`, project-specific deploy script — pick from `aria-config.md`'s `projects_list[<tag>]` if present, otherwise prompt user), and (b) a one-line directive: "After re-deploy, re-run `/retrospect deployment` to confirm the bundle now contains the fix and validate outcome."

End with an **Overall recommendation** in 1–3 sentences.

### 4.9. Section 9 — Process Retrospective

What the prior decision-making should have done differently. Format per item:

```
What I did:               <observed behavior>
What I should have done:  <better behavior>
Trigger condition:        <how to detect this situation in the future>
Pattern reference:        <pattern-name from library | (novel)>
```

If a behavior matches an existing pattern in the library, cite it. If a behavior is *novel* (not in either pattern library), prompt the user:

> "Identified a new failure-mode pattern: `<pattern-name>`. Add to:
>   1) Canonical (`rules/retrospect-patterns.md`) — applies project-agnostic
>   2) Project-specific (`projects/<proj>/retrospect-patterns.md`)
>   3) No — surface in this report only
> Choose: "

If user chooses 1 or 2, append a new entry to the corresponding file using the format defined in `rules/retrospect-patterns.md` ("Pattern entry format" section). The new entry's "First identified" field is today's date and the current retrospective's filename.

### 4.10. Section 10 — Next-Step Evidence Ask (Residual)

Anti-speculation barrier. This section lists ONLY the **residual** evidence asks — the questions Step 3.5 either could not source autonomously, the user deferred, or were not attempted. Items resolved during Step 3.5 (✅ upgrades, ⚠ partials with Step 3.5.2 evidence, or ❌ falsifications) DO NOT appear here — they're recorded in §4.3 (`Evidence sourced` field), §4.7 (Evidence FOR/AGAINST), and §4.5 (Evidence-Sourcing Pass tally blocks).

For each remaining 🤷 / ⚠ / ❓ / 🚫 fix, emit the residual ask with its **attempt-status**:

```
For Fix #N (<subject>) — current status: <🤷 / ⚠ partial / ❓ / 🚫>
  Attempt status:    NOT-ATTEMPTED | ATTEMPTED-FAILED | DEFERRED-BY-USER | SKIPPED-BY--no-source
  Sub-pass:          BUNDLE-MARKER (§3.5.1) | OUTCOME (§3.5.2)
  Why residual:      <one-line — e.g., "Auto-source attempted via Bash curl <bundle-url>; URL returned 403. Demoted to USER-INPUT; user picked Skip.">
  What's needed:     - <specific instrumentation step 1 — log query, repro test, ticket comment, deploy log inspection, etc.>
                     - <specific instrumentation step 2>
                     - <add a unique [<TAG>-DIAG] marker so deployment verification is possible>
  Who can resolve:   <USER | AUTOMATED-RETRY-LATER (e.g., re-query logs after 1h) | EXTERNAL-PARTY <name> (e.g., QA team, customer report)>
```

Then group the residual asks by surviving hypothesis (from §4.7) so the user can see which hypothesis each piece of evidence would advance:

```
To confirm Hypothesis A (<short label, from §4.7>):
  - Fix #N residual: <one-line>
  - Fix #M residual: <one-line>

To confirm Hypothesis B (<short label>):
  - ...
```

Attempt-status meanings (mirror /prospect's §4.10):
- **NOT-ATTEMPTED** — Step 3.5 did not generate a sourcing plan for this question (rare; usually means a misclassified candidate).
- **ATTEMPTED-FAILED** — Step 3.5 ran tools but the answer wasn't found / source was unreachable / two corroborating sources couldn't be obtained / log time window had no signal.
- **DEFERRED-BY-USER** — Step 3.5 surfaced a USER-INPUT ask and the user picked "Skip".
- **SKIPPED-BY--no-source** — entire pass was skipped via the `--no-source` flag.

If all fixes are post-Step-3.5 ✅ Validated and §4.2 emitted ✅ Verified for all, emit: "N/A: all fixes validated and bundle-verified (Step 3.5 closed all gaps). Proceed to next work."

If Step 3.5 was skipped via `--no-source`, prefix every entry with "(Sourcing pass skipped — re-run `/retrospect <scope>` without `--no-source` to attempt autonomous resolution.)"

End the section with this verbatim warning:

> **Do not ship another speculative fix until at least one item in this section is satisfied. If a new fix is proposed without new evidence, re-run `/retrospect`.**

## Step 5: Validation Status Taxonomy (reference)

When assigning Validated? in §4.3, choose one of the 5 statuses below. Bundle-unverified (🤷) is a precondition gate handled in §4.2, not a status.

| Status | Definition | Required sub-tag (in report) |
|---|---|---|
| ✅ **Validated** | Evidence shows the fix achieved its stated goal in the deployed state | **Evidence type**: log event \| reproduction-then-fix-verified \| production instrumentation \| deployed-state check. "Code review confirmed" is **not** validation. |
| ⚠ **Partially validated** | Evidence shows the fix changed something, but didn't fully close the bug | **Sub-tag**: `closed-part-of-target` \| `closed-different-bug` |
| ❌ **Invalidated** | Evidence shows the fix did NOT close the bug, or introduced a regression | **Sub-tag**: `didnt-fix` \| `introduced-regression` |
| ❓ **Unvalidated — evidence requestable** | No evidence yet, but the skill can describe the specific test/check that would validate | (none) |
| 🚫 **Unvalidatable** | Cannot be validated from current vantage point (requires production traffic, edge case not yet reproduced) | (none) |

When emitting a Validated? value, always include the required sub-tag where applicable. Examples:

- `Validated?: ✅ Validated (log event: apify_schema_mismatch confirmed absent post-deploy)`
- `Validated?: ⚠ Partially validated (closed-part-of-target: rehost cap raised but profile-image source still missing)`
- `Validated?: ❌ Invalidated (didnt-fix: bug reproduces on test #3)`
- `Validated?: ❓ Unvalidated — evidence requestable: needs <specific check>`
- `Validated?: 🚫 Unvalidatable: requires production traffic to surface`

## Step 6: Write Outputs

After Step 4 produces the report, write outputs to the configured destinations:

### Always
- Render the full report to terminal (chat).

### Default (configurable in `~/.claude/aria-knowledge.local.md` under `retrospect:` block — to be added when needed)
- **Persistent log:** Write the full report to `~/knowledge/logs/retrospect/<YYYY-MM-DD>-<scope>-<slug>.md` where `<scope>` is the resolved scope keyword from Step 0 (`commit`, `range`, `pr`, `session`, `release`, `deployment`, or `auto-range` for the no-args default) and `<slug>` is derived from the goal or referenced ticket(s). Resolve `~/knowledge/` from the configured `knowledge_root`. Create the `logs/retrospect/` subfolder lazily on first use. Existing files written under the older `<YYYY-MM-DD>-<slug>.md` pattern are grandfathered (no rename).

  Prepend a structured YAML frontmatter block to the report before writing. Schema:

  ```yaml
  ---
  type: retrospect
  date: <YYYY-MM-DD>
  scope: <commit | range | pr | session | release | deployment | auto-range>
  goal: <one-line stated goal from §4.1 Anchor>
  tickets: [<LINEAR-123>, <LINEAR-456>]   # empty list if none
  fixes_count: <N>
  sourcing_pass:
    bundle_marker:
      candidates: <N>
      upgraded_verified: <N>
      upgraded_not_in_bundle: <N>
      no_movement: <N>
    outcome:
      candidates: <N>
      upgraded_validated: <N>
      upgraded_partial: <N>
      upgraded_invalidated: <N>
      no_movement: <N>
  patterns_hit: [<pattern-name-1>, <pattern-name-2>]   # from §4.4; empty list if none
  overall_outcome: <closed | partial | unresolved | mixed>   # derived from §4.5 tally + §4.8 overall recommendation
  related: [<paths to overlapping prior runs — see below>]
  tags: [retrospect, <scope>, <project-tag-if-detected>, <pattern-tag-if-applicable>]
  ---
  ```

  **`overall_outcome` derivation:** `closed` if every fix's post-Step-3.5 Validated? is ✅; `unresolved` if any fix is ❌ Invalidated or ❌ Not-in-bundle; `partial` if any fix is ⚠ partial AND none are ❌; `mixed` for any other combination.

  **`related` auto-detection (Q1.2=1, ticket-based):** Before writing, glob `~/knowledge/logs/prospect/*.md` AND `~/knowledge/logs/retrospect/*.md` for files whose frontmatter `tickets:` array shares at least one ticket ID with the current report's tickets. Record their paths (relative to `~/knowledge/`) in the `related:` array. If no tickets in the current report, leave `related:` empty. Cap at 10 most-recent overlaps.

  **`tags:` field:** always includes `retrospect` and the scope keyword. Add a project tag when the bundle is detected to belong to a configured project (commits/files match a `projects_list[<tag>].project_root`). Add pattern-name tags for any §4.4 hits. These tags make the file discoverable via `/index` and `/context` (per Q1.3=1 — `/index` extends its scan to `logs/{prospect,retrospect}/`).
- **Aria intake:** Suggest entries for the four backlogs based on the report content:
  - Insights → observations like "fix #N's theory was wrong because <evidence>"
  - Decisions → "Reverted fix #N; reapplied minimal version" with rationale
  - Approaches → instrumentation patterns that worked (e.g., "[<TAG>-DIAG] marker pattern for bundle verification")
  - Working rules → if §4.9 identified a behavior that should become a Universal Rule, suggest it (do not persist without user approval per Rule 23)

  Project-scoped intake goes to `projects/<proj>/`; agnostic intake goes to the shared knowledge tree. Follow the standard aria intake confirmation flow (suggest, user reviews, write on approval).

### Opt-in
- **Linear comment:** Only when invoked with `--linear-post`. Post a *summary* (the Overall recommendation from §4.8 + the action verdict list) to each Linear ticket detected in commit messages. Use Linear MCP `save_comment`. Never post the full report — too much detail for the ticket.

### Pattern library write-backs
If §4.9 produced a novel pattern and the user approved adding it, the pattern entry is written to either:
- `~/knowledge/rules/retrospect-patterns.md` (canonical), or
- `~/knowledge/projects/<proj>/retrospect-patterns.md` (project-specific)

Pattern write-backs are *separate* from intake — they go directly to the patterns file, not through backlog review.

## Step 7: Soft-Suggest Trigger Logic (Claude-side judgment)

When the skill is *not* directly invoked, Codex monitors user messages for cues that suggest a retrospective is warranted. When detected AND the current session has shipped recent fixes (commits in the last hour or since the last `/retrospect`), Codex offers — never auto-executes — `/retrospect`.

Cues (non-exhaustive, judgment-based):

- "still broken," "still happening," "didn't fix," "no change"
- "regression," "same outcome," "reproducing again," "same bug"
- The user shares a test session log, transcript, or repro evidence that indicates failure
- Audit-shaped requests: "review what you did," "audit the changes," "are these necessary," "what did you change"

Standard offer (paraphrase as appropriate):

> "It sounds like the last release didn't fully close the bug. Before I propose another fix, want me to run `/retrospect` on the change set first? That'll force a validation check + re-diagnosis pass before we ship anything new."

Cue weight is judgment, not regex. When the cue is faint, just acknowledge and proceed. When the cue is clear, offer. Never auto-execute from a cue — always ask.

This logic also fires the `pushback-as-cue` pattern (see `rules/retrospect-patterns.md`) — they share the same trigger surface.

## Step 8: Validation Gates

Before finalizing the retrospective, verify:

1. **Anchor printed?** §4.1 must contain Goal, Mode, Range, Tickets, Outcome lines. For `deployment` scope, must also include the resolved marker source (per Step 0's deployment-detection cascade).
2. **Evidence-Sourcing Pass run (or explicitly skipped)?** Step 3.5 must have addressed every preliminary 🤷 candidate (3.5.1 bundle-marker sub-pass) and every preliminary ⚠/❓/🚫 candidate (3.5.2 outcome sub-pass) — each must end with one of: UPGRADED-TO-✅ / UPGRADED-TO-❌ / NO-MOVEMENT / INCONCLUSIVE / DEFERRED-BY-USER / SKIPPED-BY--no-source. No silent skips. The pass summary (Step 3.5.4) must be emitted.
3. **Bundle-verification gate run?** §4.2 must address every fix from Step 3 with one of three values (✅ Verified / 🤷 Bundle-unverified / ❌ Not-in-bundle), reflecting post-Step-3.5.1 state. Each per-fix render must cite the Step 3.5.1 source.
4. **Per-fix verdicts complete?** Every fix has all required fields (Status, Necessary?, Complications, Minimal alternative, Maintenance cost, Validated?, Action). Validated? values reflect post-Step-3.5.2 state. Missing field = incomplete report.
5. **Validation hard rule respected?** No fix has Action: KEEP unless post-Step-3.5.2 Validated? is ✅ or ⚠ partial. ❌ Not-in-bundle (§4.2) → RESHIP-AND-VERIFY or REVERT. 🤷 Bundle-unverified → HOLD-PENDING-VERIFICATION. ❓/🚫 → HOLD-PENDING-EVIDENCE / HOLD-PENDING-DEPLOY. Verify the full hard-rule ladder from §4.3 before emitting.
6. **Pattern check ran?** §4.4 must reference both pattern libraries (canonical + project-specific if applicable).
7. **Tally consistent?** Counts in §4.5 must match the per-fix data in §4.3 (post-Step-3.5.2) and §4.2 (post-Step-3.5.1). The two `Evidence-Sourcing Pass` blocks in §4.5 must match Step 3.5.4's summary verbatim.
8. **Hypotheses present when needed?** §4.7 is required if any fix's *post-Step-3.5.2* Validated? was ❌ Invalidated or ⚠ partial, or §4.6 triggered re-frame. Evidence FOR/AGAINST must integrate Step 3.5.2 findings where applicable.
9. **Action verdict complete?** §4.8 must have an action for every fix in §4.3. RESHIP-AND-VERIFY actions must include the project-appropriate re-deploy command + the re-run-/retrospect directive.
10. **Residual evidence asks correctly scoped?** §4.10 must list ONLY residual items (NOT-ATTEMPTED / ATTEMPTED-FAILED / DEFERRED-BY-USER / SKIPPED-BY--no-source). Items resolved by Step 3.5 (✅ upgrades, ⚠ partials with §3.5.2 evidence, or ❌ falsifications) must NOT appear in §4.10. Cross-check: every §4.10 entry must have current status of 🤷 / ⚠ / ❓ / 🚫.
11. **Outputs written?** Confirm the persistent log was written to disk at `~/knowledge/logs/retrospect/<YYYY-MM-DD>-<scope>-<slug>.md`, with structured YAML frontmatter (type, date, scope, goal, tickets, fixes_count, sourcing_pass, patterns_hit, overall_outcome, related, tags) prepended. Confirm intake suggestions were surfaced.
12. **`related:` cross-refs computed?** If the report contains tickets, the `related:` frontmatter array must list overlapping prior runs (capped at 10) from `logs/prospect/` and `logs/retrospect/`. If empty (no tickets), confirm the empty-list state explicitly.

If any check fails, self-correct once. If self-correction can't close the gap (e.g., the user must supply evidence), surface the gap explicitly in the report rather than silently skipping.
