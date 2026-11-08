---
status: DRAFT — /prospect gate 1 PROCEED-WITH-CHANGES, C1–C7 applied; awaiting plan
date: 2026-11-08
owner: Mike (approval: "SPPP then hold for E", 2026-11-08)
supersedes: nothing (first spec for surfacing ranking)
evidence: maintainer knowledge folder — idea + retrospect, 2026-11-07 (measured on a real index of ~5,000 files)
---

# Active surfacing — one tested source of truth, project-first ranking

## 1. Problem

Active surfacing picks up to 5 knowledge files for a task from `## Tag Index` in the user's
`index.md`. Which 5 it picks decides whether the right knowledge reaches a session. Today:

1. **The selection algorithm exists in ~17 copies, in three forms, with three different orders.**
   - 4 shell copies of `kt_index_match` (`lib-index-match.sh` in plugin-claude-code, -antigravity,
     -openai-codex, -cursor-template) rank matched tags by **tag-name length, longest first**.
   - ~5 copies of the `ARIA ACTIVE CONTEXT` rules text (digest + session-start emitters) describe
     the steps in prose for the model to execute, with **no order at all** ("cap at top-5").
   - 8 copies of `/prospect` + `/retrospect` Step 0.5 say **"top-5 by first-appearance order"**.
2. **The model path is non-deterministic.** A live check (2026-11-08, a fresh session) found
   the session inventing its own ranking because the text gives none; it noted alphabetical order
   would have loaded 5 unrelated notes.
3. **Name length is an inverted proxy for specificity.** Project tags are often short, generic tags long (`payments`, `citation`). Measured worst case: "add the
   site-1 roof job to the proj-b payments tab" → the hook order loads 5 payments logs from an UNRELATED
   project, because `payments` (8 chars) outranks `proj-b`'s real 5-char tag.
4. **Copies have drifted and nothing detects it.** The Codex copy lacks the hyphen-preserving
   tokenizer the other three carry (diff 2026-11-08); `PORT-LEDGER.json` has 0 entries for
   `lib-index-match.sh`; no test anywhere calls `kt_index_match`.
5. **A configured project can be invisible.** Surfacing reads only `### ` headers under
   `## Tag Index`; a project in `projects_list` whose tag was never hand-promoted cannot surface at all (two real
   projects were invisible this way until the maintainer promoted them by hand, 2026-11-07).
6. **Aliases are ignored.** Known Tags supports `tag [aliases: a, b]`; the matcher reads headers only
   (`grep -c aliases lib-index-match.sh` = 0).

## 2. Evidence (measured 2026-11-07/08 on the maintainer's real index)

13 realistic phrasings — 8 for two projects (proj-a, proj-b), 3 for a third (proj-c) + 2 ARIA controls. "Relevant" = file carries the task's
project tag or lives under `projects/<p>/`.

| Ranking | Fires | Relevant of top-5 | Authored |
|---|---|---|---|
| B0 current hook (length-desc, path order) | 9/13 | 30/65 | 4 |
| C5 project-first | 12/13 | 60/65 | 38 |
| C6 C5 + task-word overlap | 12/13 | 60/65 | 29 (task-specific logs replace generic authored) |

Controls stay 5/5 under C5/C6. C6 is the only variant whose top-5 for the proj-b payments task
contains both files the live-check session named as most relevant. The single miss in all variants
matches no known tag ("validate the site-1 record for its skylights") — only aliases (D4) reach it.
⚠ Bound: 13 phrasings, partly author-written; task-level relevance checked on one task. AC9 re-measures.

## 3. Goals / non-goals

**Goals.** One definition of "which files to surface", executed by code wherever a runtime can run
code; a defined ranking that puts the user's project and task first; configured projects surfaceable
by construction; drift between copies detectable; the behaviour tested in both directions.

**Non-goals.** Semantic/embedding retrieval (new dependency, non-deterministic; revisit only if the
lexical ranking measures insufficient on real messages). Changing the 5-file cap. Changing how
`index.md` is generated (`build-index.py`) beyond what D3 needs. The Cowork port gaining hooks.

## 4. Design

### D1 — One executable source of truth
`kt_index_match` (plugin-claude-code `scripts/lib-index-match.sh`) is THE implementation. Every other
copy either calls it or is a verbatim copy guarded by a test:
- **Shell ports** (antigravity, codex, cursor-template): byte-identical copies of the canonical lib,
  registered in `PORT-LEDGER.json` so `check-port-drift.sh` reports drift. The Codex lag is closed.
- **A CLI entry** `scripts/aria-surface.sh "<text>"` wraps the lib and prints the ranked paths and the
  matched tags, for skills and for any caller that is not a hook.
- **Model-executed prose** shrinks to one canonical paragraph stating the ranking (D2) exactly, used
  only where no code can run (Cowork). It is copied verbatim and a test fails on divergence.

### D1a — Prompt-time surfacing hook (Claude Code)
The rules text says the hooks cover TaskCreated / Bash-cd / PostCompact and the prose "covers the
SessionStart→first-user-message gap". Close that gap deterministically: a `UserPromptSubmit` hook
(the event is already registered — `usage-threshold-inject.sh`) runs `kt_index_match` on the prompt,
applies the existing per-session ledger (`kt_match_filter_ledger` / `kt_match_record_ledger`), and
injects the ranked list as `additionalContext`. The `ARIA ACTIVE CONTEXT` directive then becomes
"read the files ARIA injected and say which and why" — the model no longer runs the algorithm.
- **Input (C1).** Tokenize only the words the user wrote: strip every `<pasted_content …>` …
  `</pasted_content …>` block first (the host expands pasted text into `prompt`; a pasted log would
  otherwise match dozens of tags).
- **Cadence (C3).** Run on every prompt; inject only when a not-yet-surfaced file (per the session
  ledger) ranks in the top 5; otherwise emit nothing. This replaces "once per session and on topic
  change", which no code can evaluate.
- **Latency (C2).** Measured 2026-11-08 on a 44,480-line index: the current lib takes 507–657 ms per
  match (nested shell loops); one `awk` pass over the index takes ~224 ms. Requirement: parse the
  Tag Index once into a cache keyed on the content checksum (`cksum`) of `index.md` — portable across
  BSD/GNU, unlike `stat` mtime (gate 2) — and answer from the cache —
  **p95 ≤ 150 ms warm** on that index; a cache miss may exceed it once. Exit 0, never block the prompt.
- **Host premises, version-stamped (C4).** Read 2026-11-08 from code.claude.com/docs/en/hooks on
  Claude Code 2.1.319 (CLI, measured): input carries `prompt` + `session_id`; output must be
  `hookSpecificOutput.additionalContext` (top level is silently ignored); a value over 10,000 chars
  is replaced by a file path + 2,000-char preview — inject PATHS only, never file bodies. Re-check
  these on a host upgrade.

### D2 — The ranking (applies to every copy)
Matching is unchanged: lowercase, hyphen-preserving + split tokens, exact token == tag.
Firing: **≥2 matched tags, OR ≥1 matched project tag** (a project the user named is the strongest
signal there is). Candidate files = union of files under matched tags, deduped. Order:
1. carries a matched **project** tag;
2. carries **more** of the matched tags;
3. more **task-word overlap** — task words (stopwords removed, length >2) found in the file's path or
   index description;
4. **authored** (not under `logs/`) before logs;
5. **rarest** matched tag it carries (fewest files);
6. index order (stable tie-break).
Cap: 5 (unchanged).

### D3 — Configured projects are surfaceable by construction
The match vocabulary = `### ` headers under `## Tag Index` ∪ tags in `projects_list` (`KT_PROJECTS_LIST`,
`config.sh:119`). For a project tag, candidate files = its Tag Index section (if any) ∪ index lines
whose path starts with `projects/<tag>/`. No index rebuild is required for a newly configured project
to surface.

### D4 — Aliases honoured
`tag [aliases: …]` in `## Known Tags` maps each alias token to its canonical tag before matching.
The list is separated by commas OR whitespace — both occur today (`[aliases: a, b]`,
`[aliases: threejs three.js]`); parse both (C5).
Enables e.g. `proj-b [aliases: site-1, site-2]` — a task that names a site but not its project. Adding aliases is a vocabulary edit (`/index`),
not part of this change.

### D5 — Tests (the matcher's first)
A fixture `index.md` + config under `tests/repros/fixtures/` and `tests/repros/surfacing-rank.sh`,
run by `tests/run.sh`. Fixtures are synthetic (`proj-a` …) — this repo is public. Run the lib under
`sh`/`bash` only: under zsh it word-splits differently and reads 0 matches for queries that match
(measured 2026-11-08) (C7). Each arm states its expected value and is seen RED against the current lib
before it goes green:
- project-first beats a longer generic tag (`proj-b`+`payments` → proj-b files first);
- a file carrying two matched tags outranks one carrying one;
- task-word overlap breaks a tie;
- authored before logs on an otherwise-equal tie;
- a lone project tag fires; a lone non-project tag does NOT fire (negative arm);
- a configured project with no Tag Index section still surfaces its `projects/<tag>/` files (D3);
- an alias token matches its canonical tag (D4);
- ledger filter still drops already-surfaced paths (regression);
- verbatim-prose guard: every non-code copy of the ranking paragraph equals the canonical one.

## 5. Acceptance criteria
- AC1 `kt_index_match` implements D2 + D3 + D4; the 4 shell copies are byte-identical; all 4 are in
  `PORT-LEDGER.json` and `check-port-drift.sh` is clean.
- AC2 `scripts/aria-surface.sh` prints ranked paths + matched tags; exit 0 always.
- AC3 A `UserPromptSubmit` surfacing hook injects the ranked list (Claude Code), honours the ledger,
  is silent unless a not-yet-surfaced file ranks, strips pasted blocks before matching, injects paths
  only, never blocks the prompt (exit 0), and meets p95 ≤ 150 ms warm on a ~45k-line index.
- AC4 `ARIA ACTIVE CONTEXT` no longer describes a selection algorithm for Claude Code; the digest test
  (`test-aria-rules-digest.sh`) is updated and still asserts the directive is present.
- AC5 The 8 Step 0.5 copies call `aria-surface.sh` (code ports) or carry the canonical paragraph
  (Cowork); none says "first-appearance order".
- AC6 `tests/repros/surfacing-rank.sh` passes, every arm having been seen red first; `tests/run.sh` green.
- AC7 Measured by running the REAL lib under `bash` (not a re-implementation) on the 13-phrasing set: ≥60/65 relevant, controls 5/5, the proj-b payments task's
  top-5 contains that project's payments-plan log.
- AC8 Ports: antigravity / codex / cursor rebuilt; cowork text updated; release notes name the
  behaviour change (more surfacing on single project-tag messages).
- AC9 Before release: re-measure on ≥30 real opening messages sampled from past transcripts, report
  fired-rate, project relevance@5 AND task relevance@5 (a judgement per file) vs B0; a regression on
  the controls blocks release. The messages and results stay in the maintainer's private knowledge
  folder; anything committed here uses placeholders (C6, C7).

## 6. Risks
- **More firing.** A lone project tag now fires (e.g. any message naming a short project tag). Bounded by the
  per-session ledger (each file loads once) and the 5 cap; AC9 measures it.
- **Prompt latency.** A shell hook on every prompt; must stay bounded (index parse once, early exit
  when the index or config is absent). Measure p95 on the real index.
- **Policy change.** The lib header calls threshold + cap "a deliberate cross-cutting policy change";
  this spec changes the threshold rule and is approved as such by the owner.
- **Task-word overlap is lexical** and can favour files that merely share a common word; stopwords +
  length >2 + its position AFTER project/matched-tag count limit the effect.

## 7. Questions resolved at /prospect gate 1 (2026-11-08)
- OQ1 cadence → every prompt, ledger-deduped, silent unless something new ranks (D1a, C3).
- OQ2 → REPLACE the model-executed algorithm on Claude Code; the hook makes it redundant and AC9 is
  the safety net.
- OQ3 → Codex / Antigravity hook equivalents are deferred; those ports get the identical lib and the
  canonical ranking paragraph now.
- OQ4 → Cowork keeps the canonical prose paragraph; it has no execution path.
