---
description: "Scan Claude memory and plans for extractable knowledge. Use when user asks for 'knowledge audit', 'audit knowledge', 'check for extractable knowledge', 'scan memory', or at session start when audit cadence is exceeded."
argument-hint: "[detailed]"
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# /audit-knowledge — Knowledge Repository Audit

Scan `~/.claude/` memory and plan files, compare against what's already in the knowledge folder and project-level docs, and surface anything worth extracting.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract:
- `knowledge_folder` — required base path
- `audit_cadence_knowledge` — cadence in days (default 7); safety-net trigger for low-activity periods
- `audit_trigger_threshold` — backlog-entry count (default 20); primary activity-driven trigger. Tier boundaries derived via fixed offsets: `threshold` (suggested), `threshold + 15` (recommended), `threshold + 30` (overdue)
- `projects_enabled` — default `false`; controls whether project tier is audited (Step 5e)
- `projects_list` — default empty; comma-separated `tag:path` pairs; only relevant if `projects_enabled: true`
- `projects_promotion_threshold` — default `2`; minimum projects sharing a similar pattern before Step 5e suggests cross-project promotion

If the config file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Use `{knowledge_folder}` as the base path for all file operations in subsequent steps.

## Step 1: Read the Audit Log and Determine Mode

Read `{knowledge_folder}/logs/knowledge-audit-log.md`.

Note the "Last Audit" date and calculate days since.

**Compute the current trigger state** by counting `^### ` entries across the four action-eligible backlogs (insights, decisions, extraction, rules — exclude `intake/ideas/`, which routes out via the Accept submenu rather than promoting directly). Count only entries **below the first `---` separator** per file, matching the convention used by `/stats` and `/backlog`:

```bash
for f in {knowledge_folder}/intake/insights-backlog.md \
         {knowledge_folder}/intake/decisions-backlog.md \
         {knowledge_folder}/intake/extraction-backlog.md \
         {knowledge_folder}/intake/rules-backlog.md; do
  [ -f "$f" ] && awk '/^---$/{sep++; next} sep>=1 && /^### /{c++} END{print c+0}' "$f"
done | awk '{s+=$1} END{print s+0}'
```

Record the count — it feeds both the prompt message and Step 8's `Trigger:` audit-log subfield.

**Determine how this skill was invoked:**

- **User-requested** (user said `/audit-knowledge`, "audit knowledge", "scan memory", etc.): **Always run the full audit**, regardless of how recently the last audit was. Skip directly to Step 2.
- **Session-start check** (triggered by the SessionStart hook): Check whether either trigger fired.
  - **Entry-count trigger** (primary): if `backlog_count >= audit_trigger_threshold`, prompt per tier:
    - `count ≥ threshold + 30` → *"Knowledge audit overdue — N entries, plan for multi-pass. Run /audit-knowledge?"*
    - `count ≥ threshold + 15` → *"Knowledge audit recommended — N entries, near one-pass ceiling. Run /audit-knowledge?"*
    - `count ≥ threshold` → *"Knowledge audit suggested — N entries ready for review. Run /audit-knowledge?"*
  - **Elapsed-days trigger** (safety net): if no entry-count tier fired AND `days_since >= audit_cadence_knowledge`, prompt: *"Knowledge audit due — N days since last audit. Run /audit-knowledge?"*
  - **Neither fired**: report the last audit date + current backlog count + days-since, then stop. *"Last knowledge audit was N day(s) ago (YYYY-MM-DD). Backlog at M entries (threshold T). Next trigger at M=T entries or N=C days."*

## Step 1b: Check Index Freshness

Read `{knowledge_folder}/index.md` if it exists.

Several audit steps depend on index data (Step 5b entity refs + skill-knowledge drift, Step 5c tag matching, Step 6 stale files). Running against a stale or missing index produces incomplete results.

**Check:**
1. If `index.md` doesn't exist → note: "No index found. Steps 5b (entity/skill checks), 5c (tag matching), and stale file detection will be limited. Consider running `/index` after this audit."
2. If `index.md` exists → read the `Last rebuilt:` date from the header. Compare against today.
   - If **older than 7 days** AND there are pending backlog entries (from a quick line count of the 3 backlog files) → prompt: *"Index was last rebuilt N days ago and there are pending backlog items. Run `/index` first for more accurate integrity checks? (y/n)"*
   - If user says yes → run the full `/index` logic (Steps 0-10 from the /index skill), then continue with Step 2
   - If user says no → continue with degraded checks (note in Step 6 output which checks were limited)
   - If **7 days or fewer** → continue normally, index is fresh enough

This is a lightweight check — it reads one file header and counts backlog lines. The expensive work (full index rebuild) only happens if the user opts in.

## Step 2: Review Insights Backlog

Read `{knowledge_folder}/intake/insights-backlog.md`. **If the file is missing**, report it in Step 6 and suggest running `/setup` to repair the structure. Do not create it.

If there are entries below the `---` separator, these are insights captured during work sessions that need review.

For each insight entry, note it for presentation in Step 6 alongside Category C items. Insights are reviewed with the same approve/reject flow — promoted ones go to the appropriate knowledge file, rejected ones get cleared from the backlog.

## Step 2b: Review Decisions Backlog

Read `{knowledge_folder}/intake/decisions-backlog.md`. **If the file is missing**, report it in Step 6 and suggest running `/setup` to repair the structure. Do not create it.

If there are entries below the `---` separator, these are cross-project architectural decisions captured during work sessions that need review.

For each decision entry, note it for presentation in Step 6. Decisions are reviewed with the same approve/reject flow — promoted ones become full ADRs in `{knowledge_folder}/decisions/` (using ADR format), rejected ones get cleared from the backlog.

## Step 2c: Review Extraction Backlog

Read `{knowledge_folder}/intake/extraction-backlog.md`. **If the file is missing**, report it in Step 6 and suggest running `/setup` to repair the structure. Do not create it.

If there are entries below the `---` separator, these are feedback, project context, and reference items captured via `/extract` during work sessions.

For each entry, note it for presentation in Step 6. Feedback items are promoted to `~/.claude/projects/` memory as feedback memories. Project context items become project memories. Reference items become reference memories or go to `{knowledge_folder}/references/`. Rejected items get cleared from the backlog.

**Reclassification check:** If any entry reads as a feature proposal, bug report, or design idea (rather than an observation about what IS), flag it for re-routing to `intake/ideas/` (as a new per-file idea) during Step 7. Common signals: "should", "could be better if", "missing handling for", "UX gap", "would help if". Misclassified proposals will otherwise get promoted into knowledge files where they sit as documentation of things that don't exist — a known drift mode.

## Step 2c2: Review Ideas Directory

Glob `{knowledge_folder}/intake/ideas/*.md`. **If the directory is missing**, report it in Step 6 and suggest running `/setup` to repair the structure. Do not create it.

**Legacy-file detection (one-time):** Also check for `{knowledge_folder}/intake/ideas-backlog.md`. If it exists alongside `intake/ideas/`, surface a finding in Step 6 under a "Legacy Ideas Backlog" note: *"Pre-2.11 `ideas-backlog.md` detected. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/migrate-ideas-backlog.sh {knowledge_folder}` or re-run `/setup` to migrate entries into per-file format."* Do not attempt the migration from within the audit flow.

For each `*.md` file in `intake/ideas/`: read the file (frontmatter + body). Each file is one idea — feature proposal, bug report, or design idea captured via `/extract`. Ideas have a **distinct disposition** from other backlogs — they do NOT promote to knowledge files directly. Present them in their own section in Step 6 with the options:

- **Accept** — pick a destination from the submenu below. After the user approves, run the **verify-no-loss check** (below). Idea file then moves either to its destination (full-body preservation) or to `{knowledge_folder}/archive/audit-{date}/` (summary-only destinations — body preserved in archive with `demoted-to: {destination}` frontmatter)
- **Reject** — idea file moves to `{knowledge_folder}/archive/audit-{date}/` with `dismissal-reason: {one-line}` frontmatter
- **Defer** — file stays in place for the next audit cycle (no-op)
- **Reclassify** — if on review the item is actually an observation, append its content to the appropriate knowledge backlog (insights/decisions/extraction) for normal promotion, then move the idea file to `{knowledge_folder}/archive/audit-{date}/` with `reclassified-to: {backlog#section}` frontmatter

**Never delete (v2.15.1+):** Idea files are NEVER `rm`'d. Every disposition that previously deleted now moves the file — to its destination (full-body preservation) or to `archive/audit-{date}/` (with a frontmatter pointer explaining why). Rule 6 ("Don't delete — archive") is preserved without relying on git history; archive-on-disk is the canonical surface, making non-git knowledge folders first-class.

**User override (explicit, v2.15.2+):** If the user explicitly approves or asks for a deletion (phrases like *"delete without archiving"*, *"really delete this"*, *"skip the archive for this one"*), the destructive operation is permitted. The default safety floor remains archive; the override exists for cases where the user has explicit reason to skip preservation (e.g., accidentally captured sensitive content, archive-growth aversion). **Before honoring an override, surface what would have been archived** — name the file(s) and the substance about to be lost — and confirm. User-approved deletes are then honored as one-off; the override does not flip the default for subsequent files in the same audit.

### Verify-no-loss check (Accept disposition)

Before the idea file moves to its Accept destination, verify the destination preserves the idea's substantive content. This protects against the silent-summarization-then-delete failure mode (where a destination's 1-line entry replaces a multi-paragraph body).

1. **Inventory original substance**: identify which of {Why, Motivation, Implementation sketches, Source} sections exist in the idea file (frontmatter + body).
2. **Inventory destination coverage**: read the planned destination entry — does it carry text covering each substantive section present in the source?
3. **Three outcomes per idea**:
   - **Full coverage** → idea file `mv`'s to the destination as a standalone file (new ADR / approach / reference / plan / project decisions/patterns/), OR is fully expanded as a multi-paragraph entry in the destination (backlog/roadmap entries that carry the full Why/Motivation/Implementation paragraphs, not just a 1-liner). Original idea file gone from `intake/ideas/`; substance lives at destination.
   - **Insufficient coverage** (typical for summary-style destinations: 1-line ROADMAP bullets, TODO entries, tracker summaries) → idea file `mv`'s to `archive/audit-{date}/{filename}` with `demoted-to: {destination#section}` frontmatter. The destination still receives its summary entry; the archive preserves the body.
   - **Partial coverage** → surface to user: "Substantive sections X, Y from the original would be missing at {destination}. Choose: (a) expand destination to include them, (b) archive original alongside, (c) accept the compression as a knowing demotion." Default recommendation: (b) for backlog-style destinations, (a) for promotion-style destinations.

Edits/revisions during move are expected and welcome — the rule is *no useful substantive content is lost*, not *body is byte-identical to source*. Reformatting, condensing redundant phrasing, fixing grammar, recontextualizing for the destination format are all fine. The verification gate catches *loss*, not change.

**Accept submenu** — destinations:

| Destination | What happens | Detection / availability |
|-------------|--------------|--------------------------|
| `tracker` | User copies to external tracker (Linear / GitHub Issues / Jira / etc.). If `ticketing_plugins` config maps the idea's `project` tag to a plugin command, also print a one-line hint (e.g., *"Use `/foo-ticket` to draft this"*). Hint only — never auto-invoke. | always available |
| `roadmap` | Append idea body as a new entry to project-root `ROADMAP.md` (or `docs/ROADMAP.md`). Entry includes date prefix + Proposal/Motivation. | only if `ROADMAP.md` exists at project root or under `docs/` |
| `todo` | Append a single-line entry to project-root `TODO.md` (or `docs/TODO.md`). Format: `- [YYYY-MM-DD] {title} — {one-line proposal}`. | only if `TODO.md` exists at project root or under `docs/` |
| `adr` | Copy idea body into `intake/decisions-backlog.md` as a new `### YYYY-MM-DD — {title}` entry below the `---` separator. Reviewed as a decision in next audit. | always available |
| `backlog` | Append idea body to `IDEAS-BACKLOG.md` as a new `### YYYY-MM-DD — {title}` entry with Proposal/Motivation/Source. **Location depends on whether the idea's project tag appears in `projects_shared_knowledge`:** if NOT in the list (or list empty), write to `<project-root>/IDEAS-BACKLOG.md`; if IN the list, write to `<project-root>/_project-knowledge/IDEAS-BACKLOG.md` (team-visible, per `projects_list` resolution; see "Project-root detection" below). The user controls whether the project-root path is a parent container or a specific code repo via their `projects_list` config (e.g., `proj-a:proj-a` resolves the tag directly; `proj-b:path/to/proj-b` resolves to a parent of the code repo). Create the file with a header if it doesn't exist. | always available |
| `bundle` | Merge 2+ related ideas into a single file, then sub-prompt for one of the destinations above. After the merged file lands, source idea files all move to `archive/audit-{date}/` with `bundled-into: {merged-file-path}` frontmatter (bundle-merge typically compresses each source — archive preserves the originals for substance recovery). The verify-no-loss check runs against the *merged* file's destination, not the per-source individually. | offered when audit detects clusters (see "Bundle clustering" below) |
| `rule` | Append idea body to `intake/rules-backlog.md` as a new `### YYYY-MM-DD — {title}` entry. Reviewed during next audit alongside other rule candidates; promoted entries land in user memory as `feedback_*.md` records or in a project-local `working-rules.md`. | always available |

**Project-root detection:** for `roadmap`, `todo`, and `backlog` paths, the audit needs to resolve the idea's `project` tag to a filesystem path before probing for files. Resolution rules (in priority order):

1. **Tag in `projects_list`** — if `projects_enabled: true` AND the idea's `project` tag matches a `tag:path` pair in `projects_list`, resolve to that path. Paths in `projects_list` are relative to the parent directory of the knowledge folder (typically `~/Projects/`); the audit converts to absolute by prepending that parent.
2. **CWD fallback** — if the tag isn't resolvable via `projects_list` (projects tier disabled, tag missing from list, or idea's `project` is `cross` / `no-project`), fall back to the current working directory. Probe the closest ancestor of CWD containing either `.git/` or `CLAUDE.md`.
3. **No resolution possible** — if neither path strategy yields a valid directory (e.g., projects tier disabled AND CWD has no git/CLAUDE.md ancestor), omit `roadmap`, `todo`, and `backlog` from the submenu and append a one-line note to that idea's audit entry: *"roadmap/todo/backlog not offered: project path unresolved (project tag not in projects_list, no .git/ or CLAUDE.md ancestor of CWD)."* This makes the gap visible rather than silently shrinking the submenu.

Once the project root is resolved, probe for the relevant file in two locations in this order: (1) project root, (2) `docs/` subdirectory of the project root. **Tie-break when both exist:** route to the project root copy; the `docs/` copy is treated as secondary and not modified. Document the chosen path in the audit log entry so users can trace where each idea landed.

**Ticketing plugin lookup:** read `ticketing_plugins` from `~/.claude/aria-knowledge.local.md` (format: comma-separated `tag:plugin-command` pairs, e.g., `proj-a:foo-ticket,proj-b:bar-ticket`). If the idea's `project` matches a mapped tag, append a hint line under the tracker option: *"Use `/{plugin-command}` to draft this as a ticket."* Never invoke the other plugin's skill from inside this audit — the hint is informational; the user invokes manually.

**No installed-plugin probe.** The audit does **not** verify that `{plugin-command}` is actually installed on the user's system before printing the hint. This is intentional: enumerating installed plugins from inside a skill couples ARIA to Claude Code internals that could change. If the user has `ticketing_plugins: cs:foo-ticket` set but `/foo-ticket` is uninstalled, the hint still prints; the user discovers via "command not found" on invocation. Loud-fail at invocation is preferred over a silent absent hint.

**Bundle clustering** — auto-detected at audit time. Group pending idea files where:
1. `project` frontmatter matches across 2+ files, AND
2. Titles share ≥2 significant words after tokenization (see below).

**Tokenization rules** (applied to the `title:` frontmatter field — fall back to the slug portion of the filename if `title:` is missing):
- Split on whitespace AND on hyphens (kebab-case + spaces both produce tokens).
- Lowercase all tokens.
- Strip leading/trailing ASCII punctuation from each token.
- A token is **significant** if its length ≥ 3 chars AND it is not in the stop-words list: a, an, and, the, to, for, of, in, on, with, from, by, is, be, or, but, not, no, do, did, has, had, will, can.
- Word match is exact (case-insensitive after normalization). No stemming, no fuzzy matching — keeps clustering deterministic across audit runs.

**Lead entry of a cluster:** the oldest idea by the `date:` frontmatter field; if `date:` is missing or malformed, fall back to the `YYYY-MM-DD` filename prefix. Tie-break: alphabetical by full filename. The lead entry is where the audit surfaces the `bundle` option in Step 6; the other cluster members reference back to the lead.

For each detected cluster, surface a `bundle` option once in the cluster's lead entry in Step 6 (with a list of cluster members). The user chooses bundle (then picks merged-file destination + writes a one-line cluster summary) OR disposes each idea individually.

**Bundle sub-prompt destinations:** when a bundle is accepted, the sub-prompt offers `tracker | roadmap | todo | adr | backlog` (the same conditional availability rules as a single idea's submenu). **Excluded from bundle sub-prompts:** `bundle` (would recurse) and `rule` (rule candidates are intentionally one-rule-per-entry — bundling rule candidates obscures their individual review under audit Step 2c3, which expects one rule per `### YYYY-MM-DD — {title}` block).

The archive folder `{knowledge_folder}/archive/audit-{date}/` is the canonical preservation surface for any idea file whose disposition was Reject, Reclassify, Bundle, or Accept-with-insufficient-coverage. Git tracking is no longer assumed — first-class support for non-git knowledge folders. Each archived file gains frontmatter (`dismissal-reason`, `reclassified-to`, `bundled-into`, or `demoted-to`) explaining why it was archived and where its substance lives (if anywhere). After all Step 2c2 dispositions resolve, write a per-audit `{knowledge_folder}/archive/audit-{date}/MANIFEST.md` capturing the cohort:

```yaml
---
audit_date: YYYY-MM-DD
audit_pass: <pass number from audit log>
ideas_touched: N
moved_to_destination: N (full-body preservation; see per-idea audit log entries for destinations)
archived: N
  - dismissal (rejected): N
  - reclassified-to-backlog: N
  - bundled: N
  - demoted-to-summary-destination: N
---
```

Followed by a per-archived-file list with the originating idea filename + frontmatter pointer. The MANIFEST is the human-readable counterpart to the audit log; the audit log records dispositions, the MANIFEST records the archive's contents.

**Prior versions (pre-v2.15.1)** assumed `git log --all -- intake/ideas/` would recover deleted bodies. That assumption silently failed for any idea file created since the last git commit (untracked file → working-tree delete → no history). v2.15.1 archives unconditionally; never delete is the new safety floor.

Ideas never promote to `approaches/`, `decisions/`, or `rules/` directly via Accept — those land in their respective backlogs (`adr` → `decisions-backlog.md`, `rule` → `rules-backlog.md`) for normal audit-cycle review. The audit report for ideas presents the submenu inline; routing is a user action invoked by their disposition choice.

**Age annotation and stale marker:** For each idea file, compute age as `(today - idea date)` in days. Derive the idea date as follows: (1) read `date:` from YAML frontmatter; (2) if missing or malformed, fall back to the `YYYY-MM-DD` prefix of the filename. Annotate each entry with its age (`filed N days ago`). Read the staleness threshold from `~/.claude/aria-knowledge.local.md` (`ideas_staleness_threshold_days`, default 7) via `config.sh` or fallback. When `age > threshold`, append a `[STALE — still relevant?]` marker to the entry and escalate its visual weight in Step 6 (place stale entries first within the Pending Ideas section, and prompt explicitly for Accept/Reject/Defer rather than allowing implicit Defer).

This is the audit's mechanism for forcing action on long-sitting ideas. Without staleness surfacing, items accumulate silently; with it, every audit cycle either confirms an idea still matters or retires it.

## Step 2c3: Review Rules Backlog

Read `{knowledge_folder}/intake/rules-backlog.md`. **If the file is missing**, report it in Step 6 and suggest running `/setup` to repair the structure. Do not create it.

If there are entries below the `---` separator, these are rule candidates — observations or proposals about *how to work* (rather than *what is*) — staged via the `Accept → rule` path on prior idea audits, or appended directly when feedback in conversation matches a "rule of thumb" shape.

For each entry, note it for presentation in Step 6 alongside other backlogs. Rule candidates have three valid promotion targets, all inside the user memory directory or `{knowledge_folder}` (ARIA never writes to project source):
- **User memory `feedback_*.md`** — for personal/working-style rules that span projects (matches the existing feedback-memory pattern under the active project's `~/.claude/projects/{cwd-encoded}/memory/` directory)
- **Cross-project `{knowledge_folder}/rules/user-rules.md`** — for ARIA-behavior rules that should apply consistently across all the user's work (the user-owned counterpart to plugin-managed `working-rules.md`)
- **Project-tier `{knowledge_folder}/projects/{tag}/rules/working-rules.md`** — only when `projects_enabled: true` and the entry's `project` tag matches `projects_list`; for project-scoped discipline that doesn't generalize cross-project. Setup's Step 7c scaffolds the parent `rules/` subdirectory so this destination is always available when the projects tier is on.

Rejected entries get cleared from the backlog. All three promotion targets are reviewed at user approval time in Step 7 — do not auto-promote.

**Reclassification check:** if any entry reads as a feature proposal or bug report (rather than a "how to work" rule), flag it for re-routing to `intake/ideas/` during Step 7. Common signals indicating misclassification: "should add", "should fix", "would be nice if X existed". Rules describe behavior; ideas describe missing features.

## Step 2d: Review Pre-Compact Captures

Scan `{knowledge_folder}/intake/pre-compact-captures/` for `.md` files. **If the directory doesn't exist or is empty**, skip silently to Step 3.

**If snapshots exist**, report the count and total size, then ask the user:

> "Found N pre-compaction transcript snapshot(s) (total ~X KB) from previous sessions. These may contain uncaptured knowledge. Options:"
> 1. **Digest** — extract high-signal content via script, then review (~1-3K tokens per snapshot; default)
> 2. **Detailed** — read full transcripts for exhaustive review (~30-50K tokens per snapshot)
> 3. **Skip** — leave them for a future audit
> 4. **Clear** — ledger-clear all snapshots without reviewing (v2.15.2+: bodies removed but a REMOVED.md ledger records session-ids + timestamps + pointers to Claude Code's canonical transcript log)

- If **Skip** → skip to Step 3, leave files untouched
- If **Clear** → apply the **ledger-clear pattern** (v2.15.2+):
  1. Create `{knowledge_folder}/archive/audit-{date}/pre-compact-captures/` if it doesn't exist
  2. Write `{knowledge_folder}/archive/audit-{date}/pre-compact-captures/REMOVED.md` with frontmatter (`audit_date`, `removed_count`, `canonical_source: ~/.claude/projects/...`) + a per-snapshot list of filename + session-id + capture-timestamp + canonical-jsonl-pointer. See the ledger schema at the end of this section.
  3. After the ledger is written, `rm` the snapshot `.md` files from `intake/pre-compact-captures/`. Bodies are *derived copies* of Claude Code's per-session transcript log — canonical preservation is at `~/.claude/projects/{cwd-encoded}/{session-id}.jsonl` (until Claude Code rotates that log).
  4. Report count cleared, skip to Step 3.
- If **Digest** or **Detailed** → continue with the selected mode below

**Digest mode (default):** For each transcript snapshot, run the digest script to extract high-signal content before reading:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/digest-transcript.sh "{snapshot_path}" "/tmp/aria-digest-{filename}"
```

Then read the digest file (not the raw transcript). The digest keeps all user messages (truncated at 500 chars), first/last 5 lines of each assistant turn, Insight blocks, and lines containing decision/feedback signal keywords. Tool calls and results are dropped entirely. Typical reduction: **~97% fewer tokens** vs raw transcript (~1-3K tokens per snapshot vs ~30-50K+ raw).

**Detailed mode:** Read the full transcript snapshots directly. Use this when digest mode missed something in a previous audit or when the session contained complex multi-step work where mid-response context matters. Note: a single snapshot can consume 30-50K+ context tokens, so use sparingly.

For each snapshot (digest or full):
1. Note the filename (contains date and session ID, e.g., `2026-04-07_a1b2c3d4.md`)
2. Scan for extractable content — look for the same categories as `/extract`: Insight blocks, architectural decisions, feedback corrections, project context, and reference pointers
3. Note findings for presentation in Step 6 under a "Pre-Compact Captures" section

After the user reviews findings in Step 7:
- **Approved items** → append to the appropriate backlog file (insights-backlog.md, decisions-backlog.md, or extraction-backlog.md), then apply the **ledger-clear pattern** (see below) to the snapshot file — body removed, REMOVED.md ledger entry appended.
- **Rejected items** → apply the **ledger-clear pattern** to the snapshot file — body removed, REMOVED.md ledger entry appended with `disposition: rejected` and a one-line reason from the user.
- **Skip** → leave the snapshot for the next audit

### Ledger schema (v2.15.2+)

Pre-compact snapshots are *derived copies* of Claude Code's per-session transcript log at `~/.claude/projects/{cwd-encoded}/{session-id}.jsonl`. Their bodies are not preserved in the archive — only a ledger of what existed is preserved. The body's canonical source is the Claude Code transcript log (until Claude Code rotates it).

Ledger file: `{knowledge_folder}/archive/audit-{date}/pre-compact-captures/REMOVED.md`

```yaml
---
audit_date: YYYY-MM-DD
removed_count: <N>
canonical_source_pattern: ~/.claude/projects/{cwd-encoded}/{session-id}.jsonl
note: |
  Pre-compact snapshots are derived copies of Claude Code's per-session transcript log.
  Bodies are not archived here; the canonical source retains them until Claude Code rotates
  the jsonl. If a snapshot needs recovery after rotation, the body is unrecoverable.
---

# Removed pre-compact snapshots — {audit-date} audit

- {filename} | session {session-id} | captured {capture-iso8601} | disposition: clear|approved|rejected | reason: {one-line} | canonical: ~/.claude/projects/.../{session-id}.jsonl
- ...
```

Append-only — if a subsequent audit on the same date also ledgers snapshots, append rows under the same REMOVED.md. If a same-date audit folder already exists from a prior run, suffix as `audit-{date}-2/`, `-3/`, etc.

**User override (explicit, v2.15.2+):** If the user explicitly approves or asks for a snapshot deletion that skips even the ledger (phrases like *"delete the snapshots without writing a ledger"*, *"just rm them"*), the bare deletion is permitted. The default remains ledger-clear; this override exists for cases where the user has explicit reason to skip both archive AND ledger (e.g., snapshots contain sensitive content they want untraceable). **Before honoring, surface the snapshot count + canonical-source pointers that would have been ledgered** and confirm. User-approved bare deletes are one-off; subsequent snapshot operations in the same audit default back to ledger-clear.

## Step 3: Scan Memory Files

Read all `.md` files in `~/.claude/projects/` memory directories for the current project (excluding `MEMORY.md` itself).

Issue Read calls for all matching files in a single parallel tool-use block. A/B/C categorization runs in the main thread after all reads complete — do not categorize file-by-file serially.

**If the directory does not exist or contains no `.md` files:** report "No memory files found for the current project" in the Step 6 summary and skip to Step 4. Do not silently omit this section.

For each file, categorize:
- **(A) Already captured** — content is already in CLAUDE.md files, `{knowledge_folder}/`, or project docs
- **(B) Claude-implementation-specific** — operational details about Claude sessions, plans, or tooling that don't contain reusable knowledge
- **(C) Worth extracting** — contains validated approaches, non-obvious patterns, or cross-project knowledge not yet captured

## Step 4: Scan Plan Files

Read all files in `~/.claude/plans/`.

Issue Read calls for all plan files in a single parallel tool-use block. Categorization runs in the main thread after reads complete.

**If the directory does not exist or contains no files:** report "No plan files found" in the Step 6 summary and skip to Step 5. Do not silently omit this section.

Apply the same A/B/C categorization. Most plans are Category B (implementation-specific). Look specifically for:
- Validated approaches or patterns that could go in `{knowledge_folder}/approaches/`
- Cross-project decisions that could go in `{knowledge_folder}/decisions/`
- Rules or principles validated through experience that could go in `{knowledge_folder}/rules/`
- Operational knowledge (tool setup, architecture, onboarding) that could go in `{knowledge_folder}/guides/`

## Step 5: Cross-Reference with Knowledge Repository

Read the existing knowledge files to avoid duplicates:

Expand the glob patterns first (via Glob), then issue Read calls for all resolved files in a single parallel tool-use block. These file contents feed Steps 5b (integrity lint) and 5c (cross-reference) — do not re-read in those steps.

```
{knowledge_folder}/README.md
{knowledge_folder}/rules/*.md
{knowledge_folder}/approaches/*.md
{knowledge_folder}/decisions/*.md
{knowledge_folder}/guides/**/*.md
{knowledge_folder}/references/*.md
```

Also check project-level CLAUDE.md and docs files in the current working directory for already-captured knowledge.

## Step 5b: Lint Knowledge Integrity

Using the knowledge files already read in Step 5 (do not re-read), scan for internal problems across the existing knowledge base. This is not about what's missing — it's about what's broken or disconnected in what we already have.

Check for:

- **Contradictions** — rules, approaches, or decisions that conflict with each other (e.g., a rule says "always X" but an approach says "avoid X in this context" without acknowledging the rule)
- **Stale references** — file paths, rule numbers, tool names, or class names mentioned in knowledge files that no longer exist in the codebase or knowledge repo. Verify by checking the filesystem — don't rely on memory.
- **Superseded content** — decisions in `decisions/` or the decisions backlog that modify or override an existing approach or rule, but the approach/rule hasn't been updated to reflect this
- **Missing connections** — files that discuss the same concepts, patterns, or components but don't reference each other (e.g., an approach that implements a rule but doesn't cite it, or two decisions about the same system with no cross-link)
- **Stale entity references** — if `index.md` has an `## Entities` section, check that listed files still exist and still mention the entity. Flag any entries pointing to archived, renamed, or deleted files.
- **Missing entities** — scan promoted files for named tools, services, or frameworks that appear in 2+ files but are not listed in the entity index. These should be picked up by the next `/index` run, but flagging them during audit ensures awareness.
- **Skill-knowledge drift** — if `index.md` has a `## Skill Connections` section, check each connection for staleness. For each row in the table: (1) Get the skill file's modification date via `stat` or `ls -l` on `${CLAUDE_PLUGIN_ROOT}/skills/{skill_name}/SKILL.md`. (2) Get the knowledge file's `Last updated` date from its YAML frontmatter. (3) If the skill file is newer than the knowledge file, flag as potential drift — the skill may have evolved past what the knowledge doc describes. Also scan the knowledge file content for terms that may be stale relative to the skill (e.g., old names, deprecated patterns). If no `## Skill Connections` section exists in the index, skip this check silently — it means `/index` hasn't been run with Step 8c yet.

**Scope:** Only check files in `{knowledge_folder}/rules/`, `{knowledge_folder}/approaches/`, `{knowledge_folder}/decisions/`, `{knowledge_folder}/guides/`, and `{knowledge_folder}/references/`. Do not lint backlogs, logs, or templates.

**Threshold:** Only flag issues where the inconsistency is clear and actionable. "This rule could be interpreted as conflicting" is not a finding. "Rule 14 says max 3 abstraction layers; approach X recommends 5 without addressing why" IS a finding.

Note all findings for presentation in Step 6 under the new "Integrity Issues" section.

## Step 5b3: Check Cross-Skill Shared-Block Drift

Some skills inline shared logic (e.g., the group-loader block shared between `/distill` and `/stitch`). Drift between inlined copies is a latent bug — users would see different behavior in each skill.

1. Grep all files under `${CLAUDE_PLUGIN_ROOT}/skills/**/SKILL.md` for `<!-- shared-block: NAME -->` markers.
2. For each unique block `NAME`, collect the content between `<!-- shared-block: NAME -->` and `<!-- /shared-block: NAME -->` in every skill that contains it.
3. Normalize whitespace (collapse multiple spaces and blank lines to single).
4. If collected contents differ across skills for the same block name, flag as drift.

Note findings for presentation in Step 6 under a "Shared-Block Drift" section.

**Do not auto-fix drift** — only surface the finding. The resolution is a deliberate choice: update one skill to match the other, or intentionally diverge (in which case rename the block in one skill — e.g., `group-loader-distill` — so it no longer shares the name with the other).

## Step 5c: Cross-Reference Backlog Against Promoted Docs

For each pending backlog entry (from Steps 2, 2b, 2c), check whether it overlaps with existing promoted knowledge files.

**How to match:**
1. If `{knowledge_folder}/index.md` exists, read it and use the tag index for matching. Extract keywords from the backlog entry and check if any match tags in the index.
2. If no index exists, fall back to keyword matching: scan headings and first paragraphs of files in `approaches/`, `decisions/`, `guides/`, `references/` for overlapping terms.

**Two types of overlap to detect:**

**Topic overlap** — the backlog entry covers a topic that already has a promoted doc:
- A backlog insight about pagination when `approaches/api-pagination.md` exists
- Flag: "This insight may relate to existing doc `approaches/api-pagination.md` — update existing rather than create new?"

**Potential invalidation** — the backlog entry describes a change that may affect existing promoted docs:
- A clipping about a new Stripe API version when `references/stripe-webhook-patterns.md` exists
- A decision that reverses or modifies an existing approach
- Flag: "New entry about [topic] — existing `[file]` may need review or update."

Note all cross-references for presentation in Step 6. These inform the user's promotion decisions — they're not blockers.

## Step 5d: Check Codemap Staleness

Scan the current working directory for CODEMAP.md files:

```
Glob for **/CODEMAP.md in the project root
```

For each CODEMAP.md found:

1. **Read the header only** (first ~10 lines) to extract the `Last updated:` date
2. **Calculate age** in days since last update
3. **Check for codebase changes** — run `git log --name-only --since="{last_updated}" --pretty=format:"" -- {project_path}` to count files changed since the codemap was last updated
4. **Read the Build Log** (last ~30 lines) to check per-section update dates

**Staleness criteria:**
- **Stale** if more than 30 days since last update AND the codebase has changed files in that period
- **Possibly stale** if more than 14 days and >20 files changed
- **Current** otherwise

Note findings for presentation in Step 6 under a "Codemap Staleness" section.

**Do not run `/codemap update` automatically** — it consumes significant tokens. Only present the finding and let the user decide.

## Step 5d2: Check Codemap Stack-Concern Coverage

For each CODEMAP.md found in Step 5d, verify stack-level cross-cutting concerns are captured. Feature-organized codemaps systematically under-document cross-cutting framework layers (signals, migrations, URLConfs, env matrices) because those don't attach to any single feature.

1. **Detect the stack** from the codemap (grep the first ~50 lines for `Django`, `Next.js`, `Laravel`, `Expo`, or the `Stack:` header).
2. **Grep the full codemap** for expected stack-concern keywords:
   - **Django:** `URLConf tree`, `Signal registry|post_save|pre_save`, `Migration state|latest migration`, `Env matrix|env var table`
   - **Next.js / React:** `Route tree|Route overview`, `API client|interceptor`, `Env matrix`
   - **Laravel:** `Route file|routes/web.php`, `Job registry|queue`, `Service provider`, `Env matrix`
   - **Expo / React Native:** `Screen tree|Navigation config`, `API client`, `Env matrix`
3. **Flag any concern with 0 hits** as a coverage gap.

Note findings for presentation in Step 6 under a "Codemap Coverage" section.

**Do not auto-add missing sections** — only surface the finding. Same deferral as Step 5d: section additions consume significant tokens and should be run as focused `/codemap section <name>` tasks in a separate session.

## Step 5e: Cross-Project Pattern Detection

Skip this step entirely if `projects_enabled: false` or `projects_list` has fewer than 2 entries.

Scan `{knowledge_folder}/projects/{*}/patterns/*.md` (and optionally `projects/{*}/decisions/*.md` for cross-project decision detection) for files that may represent the same pattern across multiple projects.

**Detection heuristics** (consistent with `/index` Step 8d so the two skills surface the same candidates):

1. **Filename similarity:** Files with similar kebab-case names (e.g., `state-management-patterns.md` in two project subfolders). Case-insensitive equality of stem; allow minor variants (`-patterns` vs `-pattern`, plural vs singular).
2. **Tag overlap:** Files sharing 3+ tags excluding the project tags themselves (which are auto-derived from path per Decision #9).
3. **Title/summary similarity:** Files whose H1 (first `#` heading) shares 3+ significant terms (excluding stop words and project names).

**Threshold:** if a pattern appears in ≥`projects_promotion_threshold` projects (default 2), surface as a candidate.

For each candidate group, present to the user:

```
## Cross-Project Promotion Candidates

1. Pattern: "state-sync between AI and wizard"
   - projects/proj-a/patterns/state-sync.md (Last updated: 2026-04-12)
   - projects/proj-b/patterns/state-sync.md (Last updated: 2026-04-14)
   - Shared tags: state-management, agentic-ui
   - Suggested cross-project location: approaches/state-sync-between-ai-and-ui.md

   Promote to cross-project approach? (yes / no / skip)
```

If the user approves promotion:

1. **Synthesize content from the project-specific files.** Read each source file, identify common patterns, identify project-specific specializations. Draft a merged document with:
   - The shared pattern as the core content
   - Project-specific specializations called out as variants or notes
   - Original example references preserved with project attribution
2. **Show the user the synthesized draft for review.** Ask for edits or approval before writing.
3. **Write the new cross-project file** at the suggested location (typically `approaches/{name}.md`).
4. **Add the `originally_at:` provenance frontmatter field** to the new file:

```yaml
---
Last updated: YYYY-MM-DD
tags: [tag1, tag2, ...]
originally_at: projects/proj-a/patterns/state-sync.md (merged with projects/proj-b/patterns/state-sync.md on YYYY-MM-DD during cross-project promotion)
---
```

This makes consolidations greppable (`grep -r "originally_at:" knowledge/`) and survives git history truncation.

5. **Decide what to do with the source files** — present to the user:
   - **Remove** — delete each source file (the cross-project file is the new home; project context is preserved via `originally_at`). **(v2.15.2 note:** this is verify-no-loss-compliant under the never-delete rule — the cross-project destination carries the full body with revisions/edits as needed, and `originally_at:` frontmatter provides the audit trail. Source-file deletion here is delete-after-move, not delete-without-preservation. No archive needed.)
   - **Stub-and-reference** — replace each source file with a 3-line redirect:
     ```markdown
     # [Title]

     This pattern was promoted to [approaches/{name}.md](../../approaches/{name}.md) on YYYY-MM-DD as it was validated across multiple projects.
     ```
   - **Keep** — leave both source and cross-project files; useful when the project has unique context worth preserving alongside the shared pattern (rare)

   Default: **stub-and-reference** — preserves discoverability while avoiding duplication. Document the choice in Step 8's audit log entry.

6. **Update `index.md`** — append the new file to the appropriate tag sections; remove deleted source files from the index. (This happens automatically in Step 7b's index rebuild.)

If no candidates are detected, skip silently.

If candidates are detected but the user declines all promotions, note in Step 8's audit log entry: "N cross-project promotion candidates declined" (so they don't get re-suggested every audit unless evidence changes).

## Step 6: Present Findings

Present a table with ALL files scanned and their category. Only show details for Category C items.

**Output policy:** emit every subsection defined below. Subsections with no findings must emit an explicit zero-state line (e.g., "**Pending Insights:** 0 — none pending.") rather than being omitted. The four subsections that explicitly permit silent omission (Pre-Compact Captures, Codemap Staleness, Codemap Coverage, Shared-Block Drift) are conditional-on-feature-presence — they omit when the feature doesn't apply to this project, not when findings are empty. Do not collapse or shorten the structured report in pursuit of brevity — empty sections with zero-count confirmations are informational signals that the audit ran the check.

Format:

```
## Knowledge Audit Results (YYYY-MM-DD)

**Last audit:** YYYY-MM-DD (N days ago)
**Files scanned:** X memory files, Y plan files

### Summary
- Category A (already captured): X files
- Category B (Claude-specific): Y files
- Category C (worth extracting): Z files

### Pending Insights (from insights-backlog.md)

For each insight entry:
- **Date / Project / Context:** from the entry header
- **Insight:** the bullet points
- **Suggested location:** where in the knowledge folder it should go (or "clear" if not worth keeping)

If none: emit "**Pending Insights:** 0 — none pending."

### Pending Ideas (from intake/ideas/)

Present ideas in their own section. **Sort stale entries first** (age > `ideas_staleness_threshold_days`, default 7). For each entry, show:
- Date, age annotation (`filed N days ago`), project tag, short title, type (feature/bug/design/refactor/workflow)
- Stale marker `[STALE — still relevant?]` appended when age > threshold
- Proposal and motivation (one-line summary if long)
- **Disposition prompt:** two-step format — top-level choice + Accept submenu

**Top-level options (always shown):**
- `Accept → [submenu]` — pick a destination from the per-idea submenu (computed per Step 2c2 detection probes)
- `Reject` — clear with one-line reason
- `Defer` — keep in place for next audit (disallowed implicitly for stale entries)
- `Reclassify` — move to insights/decisions/extraction backlog as observation

**Accept submenu (computed per idea):** always include `tracker | adr | backlog | rule`. Conditionally include `roadmap` if `ROADMAP.md` exists at the idea's project root or under `docs/`; `todo` if `TODO.md` exists similarly; `bundle` only on the lead entry of a detected cluster (and list cluster members inline).

For stale entries, prompt explicitly (don't allow implicit Defer). For non-stale entries, Defer is fine as a no-op.

Example output:
```
### Pending Ideas (3)

- 2026-03-12 (35 days ago) — aria — refactor — simplify blueprint merge logic [STALE — still relevant?]
  Proposal: ...
  Accept → [tracker | adr | backlog | rule] / Reject / Defer / Reclassify?
  (no roadmap/todo: ROADMAP.md and TODO.md not found at aria project root or docs/)

- 2026-03-22 (25 days ago) — proj-a — bug — theme tokens missing from blueprint XYZ [STALE — still relevant?]
  Proposal: ...
  Accept → [tracker | roadmap | adr | backlog | rule] / Reject / Defer / Reclassify?
  (no todo: TODO.md not found)
  Hint: Use /foo-ticket to draft this as a ticket. (ticketing_plugins maps this project tag → foo-ticket)

- 2026-04-15 (1 day ago) — aria — feature — /setup diff prompts ahead vs diverged
  Cluster: bundle option available — also see "/setup state-aware second run" (2026-04-15) and "/setup test-mode skip re-decided" (2026-04-15) under aria project.
  Proposal: ...
  Accept → [tracker | adr | backlog | rule | bundle] / Reject / Defer / Reclassify?
```

When the user picks `Accept`, prompt: *"Destination? [tracker | roadmap | todo | adr | backlog | bundle | rule]"* (showing only the items in that idea's available submenu). Then route per the Step 2c2 specification.

**Submenu validation:** if the user names a destination that is **not** in this idea's available submenu (e.g., picks `roadmap` when ROADMAP.md doesn't exist for this project, or picks `bundle` on a non-clustered idea), do **not** auto-route to a fallback. Instead, re-prompt with a one-line explanation:

> *"`{destination}` is not available for this idea — {reason}. Pick from: [{available submenu}]."*

Reasons by destination:
- `roadmap` / `todo`: *"ROADMAP.md / TODO.md not found at {resolved project root} or its docs/ subdirectory"* (or *"project path unresolved"* per Step 2c2 resolution rules).
- `bundle`: *"this idea is not part of a detected cluster — file matches no other pending idea on project + ≥2 significant title words"*.

This makes the gap visible and forces an informed re-pick rather than silently routing to a destination the user didn't ask for.

**Between audits:** remind the user that `/context {project}` also surfaces pending ideas scoped to that project (informational, non-selectable) — for keeping the staged list visible between audit cycles without running a full review. Audit-time is for disposition; `/context` is for awareness.

If no ideas exist: emit "**Pending Ideas:** 0 — none pending."

### Pending Decisions (from decisions-backlog.md)

For each decision entry:
- **Date / Project(s) / Context:** from the entry header
- **Decision:** what was decided and why
- **Recommendation:** promote to ADR in `{knowledge_folder}/decisions/` (with suggested filename) or "clear" if already captured elsewhere

If none: emit "**Pending Decisions:** 0 — none pending."

### Pending Rules (from rules-backlog.md)

For each rule entry:
- **Date / Project(s) / Context:** from the entry header
- **Rule:** the proposed rule statement (and the "why" / "how to apply" lines if present)
- **Recommendation:** suggested promotion target — (a) **user memory** (`feedback_*.md` under the active project's `~/.claude/projects/{cwd-encoded}/memory/`) for personal/working-style rules that span projects; (b) **cross-project ARIA rule** (`{knowledge_folder}/rules/user-rules.md`) for ARIA-behavior rules that apply across all work; (c) **project-tier working rule** (`{knowledge_folder}/projects/{tag}/rules/working-rules.md` — projects tier only) for project-scoped discipline. Or "clear" if already captured elsewhere.

If none: emit "**Pending Rules:** 0 — none pending."

### Pre-Compact Captures (from intake/pre-compact-captures/)

For each snapshot with extractable content:
- **Date / Session:** from the filename
- **Findings:** extracted insights, decisions, feedback, or references
- **Recommended action:** append to appropriate backlog and delete snapshot, or delete without extracting

If no snapshots exist or none had extractable content: omit this section.

### Category C Items (if any)

For each Category C item:
- **Source:** file path
- **Knowledge type:** approaches / decisions / rules / references / **project-decisions / project-patterns** (when feature enabled)
- **Suggested location:** where in the knowledge folder it should go
- **Content summary:** what would be extracted

**Project routing logic (only if `projects_enabled: true`):**

Before defaulting to cross-project locations, check the item's tags or content for project context:

1. If the item carries a tag matching a configured project tag (from `projects_list`), suggest the corresponding project subfolder:
   - Decisions → `projects/{tag}/decisions/`
   - Reusable patterns → `projects/{tag}/patterns/`
   - Operational guides specific to the project → `projects/{tag}/guides/` (will be created on first promotion)
   - Project-specific external references → `projects/{tag}/references/` (will be created on first promotion)
2. If the item's content clearly references a project by name (e.g., mentions proj-a, proj-b, proj-c) but lacks the explicit tag, prompt the user to confirm the project tag before suggesting the location.
3. If neither tag nor content indicates a specific project, default to the cross-project tree (`approaches/`, `decisions/`, etc.) as before.

This biases new promotions toward project subfolders when the evidence is single-project, leaving the cross-project tree for genuinely cross-cutting knowledge.

If none: emit "**Category C Items:** 0 — all scanned files were Category A or B."

### Integrity Issues (from Step 5b)

If Step 5b found any issues, present them:

For each issue:
- **Type:** contradiction / stale reference / superseded content / missing connection / stale entity reference / missing entity / skill-knowledge drift
- **Files involved:** which knowledge files are affected (and which skill, for drift issues)
- **Issue:** what's wrong (for drift: include both dates — skill modified date and knowledge file last-updated date)
- **Suggested fix:** specific edit or addition to resolve it (for drift: "Review knowledge file for alignment with current skill behavior")

If no issues found: "No integrity issues detected."

### Emerging Themes (cluster detection + synthesis drafts)

Review ALL current backlog entries (not just new ones) plus any Category C items for thematic clusters. Look for:
- **Multiple insights on the same topic** → may warrant a new approach in `approaches/`
- **Multiple decisions with shared rationale** → may warrant an approach documenting the underlying pattern
- **Recurring feedback corrections** (check memory feedback files) → may warrant a new rule in `rules/`

If clusters are detected, present each one with a **draft synthesis document**:

- **Theme:** [description of the pattern]
- **Evidence:** [which backlog entries / memory files point to this]
- **Recommendation:** create new approach, rule, or rule amendment — or "not yet — need more evidence"
- **Draft:** (only if recommendation is to create)

```markdown
# [Proposed Title]

## When to Use
[Synthesized from the cluster evidence — conditions where this applies]

## When NOT to Use
[Conditions where this pattern is wrong or doesn't apply]

## The Approach / The Rule
[Core content synthesized from the individual backlog entries]

## Related
[Links to existing knowledge files that connect to this theme]

## Validated By
[Which sessions/projects produced the evidence]
```

The draft is a starting point for review, not final content. The user may edit, reject, or ask for revisions before promotion. If there isn't enough evidence for a concrete draft, say so and present the theme without one.
```

### Stale Knowledge

If `{knowledge_folder}/index.md` exists, read its `## Stale Files` section. If it has entries, present them as action items:

```
## Stale Knowledge
- N files past review threshold:
  - [file path] ([age] months, threshold: [threshold] months)

For each: review and update Last updated date? Update content? Archive if no longer relevant?
```

If no index exists, skip this section with a note: "Run `/index` to enable staleness detection."

### Codemap Staleness (from Step 5d)

If any CODEMAP.md files were found, present their status:

```
## Codemap Status

| Codemap | Last Updated | Age | Files Changed Since | Status |
|---------|-------------|-----|--------------------| -------|
| ss/CODEMAP.md | 2026-04-09 | 14 days | 23 files | Possibly stale |
| cs/CODEMAP.md | 2026-03-01 | 53 days | 87 files | Stale |

Stale codemaps can be refreshed with `/codemap update` (runs in the project directory).
Note: codemap updates involve significant codebase scanning and may consume substantial tokens.
```

If no CODEMAP.md files found: omit this section silently.

### Codemap Coverage (from Step 5d2)

If any codemap is missing stack-level cross-cutting sections, present the gap:

```
## Codemap Coverage Gaps

{codemap path} ({stack}): missing stack-level cross-cutting sections:
  - URLConf tree overview
  - Signal registry
  - Migration state
  - Env matrix

Add each via `/codemap section <name>` in a focused session. Feature-organized codemaps tend to miss these because they span all features rather than attaching to one.
```

If all codemaps have full stack-concern coverage: omit this section silently.

### Shared-Block Drift (from Step 5b3)

If any shared block has drifted across skills, present the divergence:

```
## Shared-Block Drift

`group-loader` differs between:
  - plugin/skills/distill/SKILL.md
  - plugin/skills/stitch/SKILL.md

Diff: (show the key differing lines — first ~5 differences with line context)

Resolve by:
  (a) update one skill to match the other (canonical version is the most recent intended change), or
  (b) rename the block in one skill (e.g., `group-loader-distill`) if the divergence is intentional
```

If all shared blocks are consistent across skills: omit this section silently.

### Cross-Reference Findings (from Step 5c)

For each cross-reference found:
- **Type:** topic overlap | potential invalidation
- **Backlog entry:** which entry triggered the match
- **Existing file:** which promoted doc it overlaps with
- **Recommendation:** update existing, create new alongside, or review existing for staleness

If none: emit "**Cross-Reference Findings:** 0 — no overlaps detected against promoted docs."

## Step 7: Wait for User Review

**STOP here.** Do NOT extract anything automatically.

Present Category C items, pending insights, and pending decisions. Ask the user which ones to extract/promote. Only proceed after explicit approval.

### Step 7a: Declare Batch Manifest (v2.10.0+)

After user approval and *before* executing any promotions, declare a batch manifest to enable Rule 22 ceremony compression on mechanical promotions while preserving full Rule 22 scrutiny on high-impact items. See `OVERVIEW.md` "Batch Manifests for Ceremony Reduction" for the full mechanism.

**Classify each approved op as `low` or `high` impact:**

| Impact | Typical ops | Treatment |
|--------|-------------|-----------|
| **low** (compressed directive) | Stubs from Step 5e, cross-reference additions, backlog clears, log appends, new files under `approaches/`, `guides/`, `references/` | Hook emits short acknowledgment-only directive |
| **high** (full Rule 22 fires) | New `decisions/` ADRs (new architectural commitments), new or modified `rules/` entries, promotions that change guidance/recommendations, cross-project consolidations that create new authoritative files | Full CHANGE DECISION CHECK per edit |

**Safety floor stays active regardless of manifest declaration:** (a) edits to protected paths (`CLAUDE.md`, `working-rules.md`, knowledge folder itself, user critical paths) always get full Rule 22; (b) structural signals (`auth/`, `migrations/`, `models.py`, `routes.ts`, external services like `stripe`) on a declared-low op escalate to full Rule 22; (c) any edit to a file not matched by the manifest triggers full Rule 22 as scope-drift detection.

**When in doubt about an op's impact, declare `high`** — full Rule 22 is always the safe choice.

**Write the manifest** via Bash before executing promotions:

```bash
. ${CLAUDE_PLUGIN_ROOT}/bin/config.sh
kt_batch_begin "audit-knowledge" "Audit promotion: N items per approved plan" '[
  {"file_path_pattern": "/abs/path/to/knowledge/approaches/*.md", "operation_type": "create", "impact": "low", "justification": "New approach files per approved Step 7 plan"},
  {"file_path_pattern": "/abs/path/to/knowledge/decisions/*.md", "operation_type": "create", "impact": "high", "justification": "New ADR — architectural commitment requires full scrutiny"},
  {"file_path_pattern": "/abs/path/to/knowledge/intake/*-backlog.md", "operation_type": "update", "impact": "low", "justification": "Clear promoted entries per approved plan"},
  {"file_path_pattern": "/abs/path/to/knowledge/projects/*/patterns/*.md", "operation_type": "update", "impact": "low", "justification": "Stub-and-reference after cross-project promotion"}
]'
```

Substitute `/abs/path/to/knowledge/` with the actual `knowledge_folder` from Step 0 and adjust patterns to match the specific approved items (only include patterns for op types actually approved — don't list phantom patterns).

**If `kt_batch_begin` fails** (jq missing, validation error, permission issue) — the command prints a diagnostic to stderr and returns non-zero. Proceed with the audit regardless: full Rule 22 fires on every edit as before. The manifest is a ceremony-reduction optimization, not a requirement. Don't block the audit on batch-manifest failure.

Then execute approved promotions below:

- Approved insights → move to the appropriate knowledge file, clear from backlog
- Approved decisions → create full ADR in `{knowledge_folder}/decisions/`, clear from backlog
- Approved rules → for each entry, prompt the user to pick the promotion target: (a) **user memory** — write a `feedback_*.md` file under the active project's Claude Code memory directory (typically `~/.claude/projects/{cwd-encoded}/memory/`, the same location existing `feedback_*.md` files live in) and add a one-line index entry to `MEMORY.md` in that same directory. Mirrors how feedback memories are written manually today; (b) **cross-project knowledge rule** — append to `{knowledge_folder}/rules/user-rules.md` (the user-owned rules file that ARIA never overwrites). Use this when the rule is for ARIA's own behavior across projects rather than personal/working-style; (c) **project-tier working rule** — only available when `projects_enabled: true` AND the idea has a `project` tag matching `projects_list`. Append to `{knowledge_folder}/projects/{tag}/rules/working-rules.md`; if the file or its parent `rules/` directory doesn't exist, create them from the template (see Step 7c of `/setup` for the scaffolding contract). Clear the entry from `intake/rules-backlog.md` after writing. **Never** write to paths outside `{knowledge_folder}` or the user memory directory — destinations like `{project_path}/working-rules.md` (the codebase itself) are out of scope for ARIA promotion since ARIA does not modify project source.
- Approved project-tier promotions (only if `projects_enabled: true`) → before writing, validate the target project subfolder exists. If `projects/{tag}/` is not in the user's knowledge folder, prompt: *"Project '{tag}' is not in your config (`projects_list`). Add it now? (yes adds the tag to projects_list, creates `projects/{tag}/{decisions,patterns}/` with a per-project README, then writes the file)."* If the user says yes, edit `~/.claude/aria-knowledge.local.md` to append the tag to `projects_list` (preserving existing entries), create the directory structure (mirror `/setup` Step 3's project tier scaffolding), then write the promoted file. If the user says no, fall back to the cross-project location (`approaches/` or `decisions/`) and warn that the project context is being lost.
- Approved cross-project promotion candidates from Step 5e → already handled inline in Step 5e (synthesis + `originally_at` + source disposition). No additional action here.
- Approved synthesis drafts → create the new file in the appropriate category, clear source entries from backlogs
- Approved integrity fixes → apply the fix (edit existing file, add cross-reference, archive superseded content)
- **Update existing** → for items with Step 5c cross-reference matches, merge the new content into the matched file instead of creating a new one. Read the existing file, identify where the new content fits (new section, addition to existing section, or replacement of outdated content), make the edit, update the `Last updated` date, and add/update tags if needed. Clear from backlog after updating.
- **Stale codemaps** → if the user wants to refresh a stale codemap, do NOT run it inline. Instead tell them: *"Run `/codemap update` in the {project} directory in a separate session or after this audit completes. Codemap updates scan many files and are best run as a focused task."* This avoids blowing the context window mid-audit.
- Rejected items → clear from their respective backlogs

### Cross-References on Promotion

When writing any new knowledge file during promotion, add a `## Related` section at the bottom linking to existing knowledge files that share concepts, context, or dependencies. To find related files:

1. Check which rules the new content implements, extends, or is an example of
2. Check which approaches or decisions discuss the same system, component, or pattern
3. Check if any existing file's `## Related` section should be updated to link back to the new file

Format:
```markdown
## Related
- [enforcement-mechanisms.md](../rules/enforcement-mechanisms.md) — this approach uses hook-based enforcement (mechanism tier 2-3)
- [001-compact-output-format.md](../decisions/001-compact-output-format.md) — decision that shaped the output format used here
```

Use relative paths. Each link should include a brief note explaining the relationship, not just the filename. Only link files with a genuine conceptual connection — don't link everything to everything.

If there are no Category C items, pending insights, or pending decisions, say so clearly:
> "Nothing new to extract. All knowledge-worthy items are already captured."

## Step 7b: Rebuild Knowledge Index

After all approved promotions and edits are complete, rebuild the knowledge index to capture the current state.

Run the full `/index` logic:
1. Scan all promoted folders for files and tags
2. Normalize tags (present conflicts for approval)
3. Suggest freeform-to-known tag promotions
4. Flag untagged files and offer to add tags
5. Update project-to-tag mappings
6. Detect stale files
7. Suggest cross-references between files with 2+ shared tags
8. Write `{knowledge_folder}/index.md`

**Batch the interactive prompts** — present all index health findings together rather than interrupting one at a time:

```
## Index Health
- N similar tags found: [list normalizations]
- N freeform tags eligible for promotion: [list]
- N untagged files: [list]
- N cross-reference suggestions: [list]
- Project mappings: [changes or "unchanged"]

[Approve normalizations? Promote tags? Tag files? Add cross-references?]
```

Apply approved changes, then write the final `index.md`.

If this is the first audit (no index exists yet), note: "Building knowledge index for the first time."

## Step 8: Update the Audit Log (always, even if nothing extracted)

After presenting findings (and completing any approved extractions), update `{knowledge_folder}/logs/knowledge-audit-log.md`.

Use the **structured format** below — it keeps audit logs scannable over many passes, and fields like "Counts" and "New files" are grep-able for trend analysis across audits. Previous entries in free-form paragraphs remain valid; apply this template to new entries going forward.

**If items were promoted:**

```markdown
## Last Audit
- **Date:** YYYY-MM-DD (Nth pass — short label: "routine check", "v2.8.0 continuation", "post-restructure", etc.)
- **Trigger:** count=N threshold=T days=D cadence=C — (which fired: count-tier|days|user-invoked)
- **Counts:** X insights, Y decisions, Z extractions, R rules reviewed
- **Ideas disposition:** W reviewed — accepted: A1 tracker / A2 roadmap / A3 todo / A4 adr / A5 backlog / A6 bundle / A7 rule (sum = A); B rejected; C deferred; D reclassified (omit field entirely if no ideas were in the audit; omit any zero-valued sub-counts)
- **New files:** N total — [breakdown: K approaches, L ADRs (split by tier), M patterns, etc.]
- **Extended files:** P total — [list filename: brief change, e.g. "css-gotchas.md +2 gotchas"]
- **Memory:** A new feedback, B new project, C new reference, D updates
- **Integrity fixes:** E total — [one-line each, e.g. "decisions/README.md naming convention per ADR 014"]
- **Themes:** [1-3 phrases naming the pattern clusters that drove promotions, e.g. "audit methodology synthesis", "ARIA v2.8.0 patterns"]
- **Notes:** [free text — deferred items, cross-references, notable decisions, 1-3 sentences max]
```

**If nothing promoted (empty-audit case):**

```markdown
## Last Audit
- **Date:** YYYY-MM-DD (Nth pass — "no new items" or short label)
- **Trigger:** count=N threshold=T days=D cadence=C — (which fired: count-tier|days|user-invoked)
- **Result:** No new items — [X memory files all Category A, Y plan files Category B, backlogs empty OR K entries all cleared as already-captured/stale]
- **Ideas disposition:** [optional — omit if no ideas were in the audit, else: W reviewed — accepted: A1 tracker / A2 roadmap / A3 todo / A4 adr / A5 backlog / A6 bundle / A7 rule (sum = A); B rejected; C deferred; D reclassified — omit any zero-valued sub-counts]
- **Notes:** [optional — anything worth flagging even though nothing was promoted, e.g. "clusters forming around theme X but below threshold"]
```

**Formatting rules:**
- Every field on its own line (no paragraph mashing)
- Counts are numeric; lists are comma- or newline-separated but bounded (don't dump 30 filenames into one bullet — use "27 total — [3-5 highlights]" plus "See [file] for full list" if needed)
- Notes is the escape hatch for things that don't fit — but cap at a few sentences. If the Notes section balloons past that, the audit produced enough content to deserve a dedicated summary doc, not a bloated log entry.

Also demote the previous "Last Audit" entry to the "## Previous Audits" section. If multiple audits happened in a single day (continuation passes like Pass 2 or tenth-pass), nest them under a single date header rather than creating sibling "Date: YYYY-MM-DD" entries.

## Step 8b: Clear Batch Manifest (v2.10.0+)

After the audit log is written, clear the batch manifest to unblock default Rule 22 behavior for any edits later in the session:

```bash
. ${CLAUDE_PLUGIN_ROOT}/bin/config.sh
kt_batch_end
```

Safe to call even if Step 7a's `kt_batch_begin` didn't succeed (e.g., jq missing) — the function just removes the manifest file if it exists. If the audit errors out before reaching Step 8b, `session-start-check.sh`'s stale-manifest auto-clear (30-minute threshold) recovers on the next session start so stale manifests don't silently suppress Rule 22 on unrelated edits.

## Rules

- **Never auto-extract** — always present findings for user review first
- **Be conservative with Category C** — if it's borderline, it's probably Category A or B
- **Check project docs thoroughly** — knowledge is often already captured in project-level CLAUDE.md, PROGRESS.md, or docs/ folders
- **Convert relative dates** — if a memory or plan references "last Thursday", convert to the actual date
- **Stale memories are not Category C** — outdated project status doesn't need extraction, it needs cleanup
- **Prioritize approaches and rules** — these are the highest-value extractions. Debug recipes, implementation plans, and one-time fixes are Category B
- **Watch for clusters** — individual backlog entries may not justify a knowledge file, but patterns of related entries do. The backlogs are signal generators, not just staging areas
