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

