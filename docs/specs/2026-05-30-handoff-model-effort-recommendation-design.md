# `/handoff` Model + Effort Recommendation — Design Spec

**Status:** Draft for review
**Date:** 2026-05-30
**Author:** Mike Prasad (with Claude)
**Plugin:** `aria-knowledge`
**Skill folder:** `plugin-claude-code/skills/handoff/`
**Scope:** `plugin-claude-code` only (Claude Code port). Other ports (cowork, codex, cursor, antigravity) deliberately out of scope for this change.

---

## 1. Motivation

The `/handoff` next-session opener tells the next reader *where* to resume and *what* to do first — but not *how heavily to think* about it. A resume that opens on novel architecture wants a different posture than one that opens on a mechanical doc sweep. Today the user re-derives that judgment from scratch each time they start the next session.

This change has the current session — which has the most context about what comes next — emit a single recommendation line: which **model family** and **effort level** the next session should run on, with a one-line rationale. The current session is the right place to make this call because it already synthesizes the next session's character (Step 2) to build the opener.

## 2. Scope & Placement

### In scope
- Default mode (`/handoff`) and auto mode (`/handoff auto`) — the two modes that emit a next-session opener.

### Out of scope
- **Brief mode (`/handoff brief`)** — addressed to a person, no session-resume mechanics. Untouched.
- **Other ports** — cowork/codex/cursor/antigravity. Effort/model selection is a Claude Code concept that does not map cleanly to every runtime; port later as a normal sync if desired.
- **Frontmatter / description** — unchanged. This is not a new trigger surface, and the cowork description char-cap concern does not apply (Claude Code only).

### Placement: in-block only

The recommendation is **one line inside the next-session opener fenced block** (Step 3e), directly under the `Resume …` line. It is *not* duplicated after the block.

Rationale: Step 8 already echoes the full fenced opener back to the user. So the in-block line is seen by **both** audiences for free — the user (in the Step 8 report, before they pick a model) and the next Claude instance (on paste). A second after-block copy would be pure redundancy.

What each audience does with it:
- **User, before pasting** — acts on it by selecting the model/effort in the UI (`/model`, `/effort`). This is where the *model choice* has teeth.
- **Next Claude instance, on paste** — the model is already running, so the line can't change it; its value is (a) the **effort/posture cue**, which a running model *can* act on, and (b) a **mismatch self-check** ("flagged as needing Opus · xhigh — consider switching before we go deep").

## 3. The Recommendation Rubric

The skill picks the row matching the next session's **hardest first action** (from the Step 2 synthesis: `Next steps` + `Open threads` + `Current state`). Both axes (model + effort) descend together as a single difficulty gradient, so the matched row doubles as the rationale skeleton.

| Next session's character | Recommend |
|---|---|
| Novel architecture · deeply ambiguous · high asymmetric failure cost · gnarly debugging | `Opus · xhigh` (`max` only if truly hard — session-only, may overthink) |
| Design + hard multi-step implementation, real ambiguity | `Opus · high` |
| Standard implementation with a clear-ish plan, moderate complexity | `Opus · medium` |
| Planning is the hard part, execution mechanical | `opusplan` |
| Well-specified implementation, moderate mechanical work | `Sonnet · high` |
| Routine mechanical execution (sweeps, renames, doc edits, plan already written) | `Sonnet · medium` |
| Trivial lookups / status checks | `Haiku` |

### Naming convention (durability)
- **De-versioned.** Write only the model family (`Opus` / `Sonnet` / `Haiku`). A bare family name denotes the **latest version of that family** (e.g. `Opus` = current Opus). Never write a version number — the version is the only part that rots, and this repo already de-versioned shipped model references in v2.20.3.
- **Effort ladder:** `low · medium · high · xhigh · max` (Opus and Sonnet support effort; Haiku does not). `max` is session-only and may overthink — recommend it only for genuinely hard work.
- **`opusplan`** is the Opus-plans-then-Sonnet-executes alias — recommend it when planning is the hard part and execution is mechanical.

### Rules for the recommendation
- **Always include a one-line rationale** in parentheses on the line below, grounded in the first action.
- **Uncertain / no strong signal → `Opus · high`**, rationale "general session, no strong signal."
- **Spans tiers → recommend the higher tier** and say so in the rationale.
- **`Haiku` carries no effort suffix** (no `·` level) — Haiku does not support the effort setting.

## 4. Output Shape

The opener template (Step 3e) gains one labeled line + rationale, directly under the `Resume …` line:

```
{project-marker}
Resume {project-name} from {YYYY-MM-DD} handoff.

Suggested next session: Opus · xhigh
  (first action is architectural design with ambiguous scope)

Read first:
- {PROGRESS.md path} (latest entry)
- {primary CLAUDE.md path}
- {any relevant memory file paths}

Where we left off:
- ...
```

## 5. Implementation Surface (`plugin-claude-code/skills/handoff/SKILL.md`)

1. **Step 3e** — add a short rubric subsection (the table + naming convention + the recommendation rules above) and add the `Suggested next session:` line to the opener template, positioned under the `Resume …` line.
2. **Rules section** — add one line: *"The next-session opener always carries a `Suggested next session:` line (default + auto modes only) — de-versioned model family + effort level + a one-line rationale. Brief mode does not."*
3. **No change to Step 8** — it re-emits the full opener, so the line rides along automatically.
4. **No change to Step 2B (brief)** — explicitly excluded.

### Non-skill housekeeping
- **Version:** patch bump `plugin-claude-code/.claude-plugin/plugin.json` 2.20.3 → 2.20.4.
- **CHANGELOG:** add a `v2.20.4` entry (Claude Code only; note ports not re-synced, mirroring the v2.20.3 "Pending follow-up" convention).

## 6. Testing / Verification

- **Self-consistency:** the rubric rows, the naming convention, and the example output line must agree (e.g. `Haiku` has no effort suffix; `Opus · xhigh` matches the top row).
- **Smoke:** dry-run the skill mentally against two synthesis shapes — (a) "next is design an auth model, scope unclear" → expect `Opus · xhigh`; (b) "next is run the rename sweep from the written plan" → expect `Sonnet · medium`.
- **No regression:** brief mode still emits no opener and no recommendation; Step 8 still echoes the opener (now including the new line).

## 7. Risks & Non-Goals

- **Non-goal:** auto-setting the model. The line is advisory; the user/runtime selects the model. Documented explicitly so no one expects the paste to switch models.
- **Risk — rubric drift vs. `/help` table:** `/help` uses "Highest-capability Opus / Sonnet (mid-tier)" tier language; this feature uses family-name form (`Opus`/`Sonnet`/`Haiku`). Both are de-versioned and compatible; the difference is stylistic and intentional (the opener line favors a terse `Family · effort` token). Not reconciled here.
- **Risk — port divergence:** only Claude Code gets this. Tracked as a follow-up, consistent with the v2.20.3 scoping precedent.
