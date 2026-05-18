---
name: daily-audit
description: >
  First-message audit substitute for Cowork. Use when user says "/daily-audit", "/aria-cowork:daily-audit", "audit check", "daily check", "session start audit", or at the start of a Cowork session to surface audit-cadence status. Cowork has no SessionStart hook (per ADR-004); this skill is the manual equivalent — checks /audit-knowledge + /audit-config cadences and recommends invocation if overdue. Cowork-only — not ported to aria-knowledge (which uses session-start-check.sh hook for this) (v1.0.0).
argument-hint: ""
---

# /daily-audit — First-Message Audit Cadence Check (Cowork-Only)

Check audit-cadence status at session start and recommend `/audit-knowledge` or `/audit-config` invocation if overdue. The Cowork-side equivalent of aria-knowledge's `session-start-check.sh` hook, which Cowork cannot run (per [ADR-004](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/004-hook-replacement-strategy.md)).

**Cowork-only skill.** Does not ship in aria-knowledge — aria-knowledge users get the same coverage automatically via SessionStart hook. The asymmetric application of bidirectional flow per [ADR-014](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/014-bidirectional-feature-flow.md) row 1 (cowork-only when there's no aria-knowledge analog).

## Step 0: Resolve config

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract:

- `knowledge_folder` (the absolute path)
- `last_audit_date` (when `/audit-knowledge` was last run; absent if never)
- `audit_cadence_days` (cadence threshold; default 3 if absent)
- `last_config_audit_date` (when `/audit-config` was last run; absent if never)
- `config_audit_cadence_days` (cadence threshold; default 14 if absent)
- `daily_audit_last_run` (when `/daily-audit` was last invoked; for self-throttling)

If `aria-config.md` doesn't exist, stop with: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

For all subsequent file operations in this skill, use the absolute path from `knowledge_folder` directly. Cowork resolves absolute paths via the persistent grant from `claude_desktop_config.json` per ADR-008.

## Step 1: Compute Cadence Status

For each tracked audit, compute days since last run:

| Audit | Cadence threshold | Days since last run | Status |
|---|---|---|---|
| `/audit-knowledge` | `audit_cadence_days` (default 3) | <today> − `last_audit_date` | <on-track / overdue / never> |
| `/audit-config` | `config_audit_cadence_days` (default 14) | <today> − `last_config_audit_date` | <on-track / overdue / never> |

**Status semantics:**

- **never:** field is absent in aria-config.md → first time tracking; status = recommend.
- **on-track:** `days_since <= cadence_days` → no action needed.
- **overdue:** `days_since > cadence_days` → recommend invocation.

**Stale ideas check (composes with `/audit-knowledge`'s stale-first surfacing):**

Count files in `<knowledge_folder>/intake/ideas/` whose `date:` frontmatter field is older than `ideas_staleness_threshold_days` (default 7). If count > 0, surface as part of the recommendation (`/audit-knowledge` will route them).

## Step 2: Report Status + Recommend

Compose a single status block summarizing all checks:

```
Daily audit check — <YYYY-MM-DD>

| Audit | Status | Last run | Cadence |
|---|---|---|---|
| /audit-knowledge | <on-track / overdue (N days past) / never> | <YYYY-MM-DD> | <N> days |
| /audit-config | <on-track / overdue (N days past) / never> | <YYYY-MM-DD> | <N> days |

Stale ideas in intake/ideas/: <N> (threshold: <M> days)
```

**Recommendation logic:**

- If BOTH on-track AND zero stale ideas → output: *"All audits current. Nothing to surface today."* Stop.
- If knowledge-audit overdue OR stale ideas present → recommend `/audit-knowledge`.
- If config-audit overdue → recommend `/audit-config`.
- If both overdue → recommend both, in priority order (knowledge first since stale ideas accumulate faster).

Recommendation format:

```
Recommended next actions:

1. Run `/audit-knowledge` — N stale ideas in intake/, M days since last audit (cadence: K days).
2. Run `/audit-config` — P days since last config audit (cadence: Q days).

You can also defer by running `/daily-audit` again later — this check is non-blocking.
```

## Step 3: Self-Throttle (Optional)

Update `daily_audit_last_run: <YYYY-MM-DD>` in aria-config.md. If `/daily-audit` is invoked again the same day, the check still runs (audit status doesn't change within a day, but new stale ideas might appear); the throttle field is informational for future enhancement (e.g., "you already ran daily-audit today; status unchanged").

This step is OPTIONAL — write only if aria-config.md is writable in the current session context. If the write fails, skip silently (the cadence check still succeeded).

## Rules

- **Recommend only, never auto-invoke.** The user runs `/audit-knowledge` or `/audit-config` themselves. This skill is the SessionStart-substitute notification surface, not an auto-trigger.
- **Non-blocking.** If a user wants to skip the recommendation and continue with their actual work, that's fine. The check produces a status report, not a gate.
- **Idempotent within a day.** Running `/daily-audit` twice on the same day produces the same status (unless new ideas have arrived). The skill is safe to re-invoke.
- **Surface stale ideas count, not detail.** The skill doesn't enumerate which ideas are stale — that's `/audit-knowledge`'s job. This skill is the "go check audit-knowledge" pointer.
- **No MCP probe.** This skill is purely local; it doesn't read from any external system.

## Notes

- **Cowork-only.** Per [ADR-014](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/014-bidirectional-feature-flow.md) row 1 (cowork-only when there's no aria-knowledge analog). aria-knowledge users get this coverage automatically via `session-start-check.sh` hook fired on SessionStart — Code's hook surface provides what Cowork's runtime cannot.
- **Manual invocation pattern.** Best run at the start of a Cowork session before deep work. Users may also bake `/daily-audit` into their wrapup routine if they prefer end-of-session cadence surfacing instead of session-start.
- **Composes with `/wrapup` and `/handoff`.** Those skills already prompt for `/extract`; `/daily-audit` provides the symmetric session-start surface. Together they bookend a session with audit hygiene.
- **No new schema.** Uses existing `last_audit_date`, `audit_cadence_days`, `last_config_audit_date`, `config_audit_cadence_days`, `ideas_staleness_threshold_days` fields from aria-config.md. Adds optional `daily_audit_last_run:` informational field.
- **Future-portability bridge** (per aria-cowork v0.2.5 README): if Cowork ever exposes a SessionStart-like hook surface, this skill could collapse to a hook + a thin reminder body — matching aria-knowledge's pattern. Until then, manual invocation IS the mechanism per ADR-004.
- **No MCP dependency** — does not appear in `CONNECTORS.md`'s skill-table because it consumes zero `~~category` placeholders.
