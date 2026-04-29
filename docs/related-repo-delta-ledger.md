# Related-repo delta ledger

Notable changes from related Claude Code plugin repos that share ancestry or design space with aria-knowledge. Each entry is classified by adoption decision so the relationship is auditable across versions.

## Format

| Version | Change | Decision | Rationale |
| ------- | ------ | -------- | --------- |

**Decisions:**

- **IMPORT** — adopted into aria-knowledge (cite version landed)
- **OPTIONAL** — defer to a future release; valid pattern but not yet warranted
- **REJECT** — actively declined; out of scope for aria-knowledge
- **N/A** — change originated in aria-knowledge; the related repo adopted from us

## https://github.com/nrek/aria-ex1

aria-ex1 is a fork of aria-knowledge that took a different product direction: a stripped-down execution-first variant focused on deterministic task distillation. See [`non-goals.md`](non-goals.md) for the positioning between the two.

| Version | Change | Decision | Rationale |
| ------- | ------ | -------- | --------- |
| 0.1.1 | `[Rule 22]` and `[Rule 22 · Scope]` marker convention | N/A | Originated in aria-knowledge v2.10.5–v2.10.6 |
| 0.1.1 | Turn-scoped transcript walk-back for Opus 4.7 split-message harness | N/A | Originated in aria-knowledge v2.10.6 |
| 0.1.1 | `kt_detect_signals()` structural-risk patterns | N/A | Originated in aria-knowledge v2.10.0 |
| 0.1.1 | Hook regression fixtures (`tests/fixtures/`, `tests/repros/`, `tests/run.sh`) | N/A | Originated in aria-knowledge tests/ harness |
| 0.1.1 | Rule 32 — Halt on direct contradiction with a written directive | N/A | aria-knowledge has equivalent (more elaborate); convergent design under Opus 4.7 |
| 0.1.1 | Rule 18a — Producer–consumer ordering | N/A | aria-knowledge has equivalent folded into Rule 18 "Specific cases" |
| 0.1.1 | `change-decision-framework.md` Ordering / Rationalizations / Marker Convention sections | N/A | Originated in aria-knowledge |
| 0.1.1 | Trimmed `plugin.json` description | OPTIONAL | Marketplace UX improvement; defer to a future minor release |
| 0.1.1 | Non-goals doc pattern (`docs/v0.1.1-non-goals.md`) | IMPORT (v2.13.2) | Adopted as `docs/non-goals.md`; helps users self-select between adjacent plugins |
| 0.1.1 | Upstream delta ledger pattern (`docs/v0.1.1-upstream-delta-ledger.md`) | IMPORT (v2.13.2) | This file |
| 0.1.1 | Maintainer validation checklist pattern (`docs/DOGFOOD.md`) | IMPORT (v2.13.2) | Adopted as `docs/release-validation.md`, scoped to aria-knowledge's broader skill + hook surface |

Last reviewed: 2026-04-29 against aria-ex1 v0.1.1.
