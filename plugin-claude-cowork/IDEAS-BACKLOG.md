# aria-cowork IDEAS BACKLOG

> Sibling plugin to aria-knowledge. Skills-only, local-only as of v0.2.5 (BUILT 2026-05-08). Per-project ideas land here when they're scoped to cowork specifically (not shared aria-knowledge core).

---

### 2026-05-13 — aria-cowork — npx skills add distribution path

**Proposal:** Distribute aria-cowork's skills via `npx skills add` CLI (modeled after yizhiyanhua-ai/fireworks-tech-graph review) — alternative to current zip-artifact distribution.

**Motivation:** zip-artifact distribution requires manual download + extract + restart. `npx skills add` would be one command + auto-restart Claude Code. Aligns with reviewed reference: `[[reference_three_aria_v216_reviewed_repos]]` (fireworks-tech-graph informed P-17 candidate). Marginal cost: build a small skill registry + index endpoint.

**Source:** Routed from `intake/ideas/2026-05-13-aria-cowork-skills-cli-distribution.md` at /audit-knowledge 35th-pass (2026-05-15). Original body archived at `~/Projects/knowledge/archive/audit-2026-05-15/intake-ideas/2026-05-13-aria-cowork-skills-cli-distribution.md`.

---

## 36th-pass audit Pass 2 (2026-05-19) — routed from intake/ideas/

### 2026-05-18 — MEMORY.md index update for v0.3.0
**Proposal:** Update aria-cowork's MEMORY.md index to reflect v0.3.0+ entries. Currently lags by ~5 release versions.
**Motivation:** MEMORY.md is the canonical pointer surface; stale index = readers miss recent state.
**Source:** v0.3.0 release ceremony observation.

### 2026-05-18 — release.sh structural diff line filter
**Proposal:** release.sh should filter out structural-only diff lines (whitespace, indent, comment-prefix) when computing the CHANGES count for "no substantive changes since last release" gate. Currently every whitespace change counts.
**Motivation:** Whitespace-only commits between releases inflate the count, making the gate less useful. Real signal is content-changed lines.
**Source:** v0.3.0 release.sh first-run observation.

### 2026-05-19 — release.sh public-repo-readiness check
**Proposal:** release.sh should pre-check public-repo readiness: scan for hardcoded `/Users/` paths, internal-only references, sensitive content patterns before zipping the artifact.
**Motivation:** v1.0.0 public release ceremony surfaced a few hardcoded paths in last-minute audit. Pre-check would have caught them earlier.
**Source:** v1.0.0 release sanitization audit.

<!-- CORRECTION 2026-08-03: the 109th /audit-knowledge pass first appended this to
     aria/aria-cowork/IDEAS-BACKLOG.md — but mikeprasad/aria-cowork is an ARCHIVED,
     read-only GitHub repo (push returns 403; its final remote commit is the archive
     redirect). The live owner of the cowork port is this subtree inside aria-knowledge,
     per the 2026-05-24 consolidation. Relocated here. -->
<!-- Routed 2026-08-03 by /audit-knowledge 109th pass: 1 idea file(s) from knowledge/intake/ideas/. Full bodies preserved; originals archived at knowledge/archive/audit-2026-08-03/ideas/. -->

### 2026-07-30 — Archive the 10 probe-test debris files out of the aria-cowork knowledge tier

**Project:** aria-cowork · **Type:** refactor · **Source idea file:** `2026-07-30-aria-cowork-archive-the-ten-probe-test-debris-files.md` (routed by the 109th /audit-knowledge pass, 2026-08-03)

**Proposal:** Move `knowledge/projects/aria-cowork/probe-test/` (10 files) to `knowledge/archive/`, per the archive-not-delete rule.

**Motivation:** The files are harness output, not knowledge: `code-write-test.md`, `cowork-write-test-2026-04-30T*.md` ×3, `probe-results-2026-04-30T*.md` ×3, `transcript-capture-2026-04-30T*.md` ×3 — all dated 2026-04-30, all committed 2026-05-03, untouched since. They were the largest single block of untagged files in the corpus, and tagging them would have indexed validation-run debris as project knowledge. This pass excluded them from indexing and from tagging, but they still sit in a project tier where the next audit will re-surface them as gaps.

**Source:** Deep `/index` run, 2026-07-30 — 10 of the 14 remaining untagged files after the tagging pass (the other 4 are directory README stubs, correctly excluded).
