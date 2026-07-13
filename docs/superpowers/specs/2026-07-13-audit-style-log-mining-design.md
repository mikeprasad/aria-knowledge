# Design: `/audit` dispatcher + `/audit style` log-mining sub-audit

**Date:** 2026-07-13
**Status:** Draft — awaiting spec review
**Origin:** Comparison of [ohad6k/ditto](https://github.com/ohad6k/ditto) against aria-knowledge. Two ditto ideas judged worth porting: (1) log-corpus mining of *revealed* working-style, and (2) a fail-closed dated-receipts evidence gate. This spec ports both onto aria's existing promotion pipeline and introduces an `/audit` dispatcher.

## Problem

aria-knowledge captures knowledge from the **live conversation** (`/extract`) and from staged backlogs (`/audit-knowledge`), plus config/docs drift (`/audit-config`). It has **no mechanism to mine the user's own past session logs** — the `.jsonl` corpus that already contains, in revealed form, how the user actually works ("done means it runs live", "fix the one thing", "asks for proof before trusting external state"). ditto's insight: *memory is what you told the model; the logs are what your work proved.* aria hand-authors these `feedback_*.md` rules (396 of them today); it never derives them from evidence.

Two gaps:
1. **No revealed-preference mining.** Working-style rules are stated, never mined from the log corpus aria already archives.
2. **No fail-closed evidence bar.** `/extract` dumps everything to backlogs; there is no "≥2 distinct sessions + dated verbatim quotes or it doesn't ship" discipline on inferred behavioral rules.

A third, user-raised opportunity: the audit family (`/audit-knowledge`, `/audit-config`) has no umbrella entry point.

## Non-goals

- **Not** adopting `ditto.py` as a runtime dependency. aria implements the ideas as a native skill; ditto is run once as a diagnostic mirror only (see §Ditto diagnostic).
- **Not** merging `/audit-knowledge` + `/audit-config` bodies into one skill (rejected: ~1250-line mega-skill violating single-purpose; big regression surface). The dispatcher composes; the sub-skills stay the engines.
- **Not** mining `decisions` — those are point-in-time project choices already captured via `/extract` → `decisions-backlog.md` → ADRs. `/audit style` mines *manner of working*, not *choices made*.
- **Not** writing the numbered universal `working-rules.md` (plugin-managed). Mined candidates target user memory `feedback_*.md` (tier a) and optionally cross-project `user-rules.md` (tier b).
- **Not** auto-promoting. `/audit style` proposes to `rules-backlog.md`; promotion stays human-gated via the existing `/audit-knowledge` `rule` disposition.

## Naming decisions (resolved during brainstorming)

- **`/audit style`** — semantically most correct: "style" = *characteristic manner of doing something*, the exact union of the mined layers (work behavior + design taste + writing voice). `decisions` rejected (collides with existing stream); `habits` narrows to involuntary subset; `patterns` over-broad; `history` names the input not the output; `profile` names the rendered artifact not the extracted rules.
- **`/audit`** — the dispatcher/umbrella verb.

## Section 1 — `/audit` dispatcher

New skill `/audit` unifying the audit family. Existing `/audit-knowledge` and `/audit-config` **stay intact as engines**; the dispatcher delegates.

**Grammar:**

| Input | Behavior |
|---|---|
| `/audit` (bare) | Menu: `knowledge / config / style / all` (recognition-not-recall) |
| `/audit knowledge` | Delegate to `/audit-knowledge` (skip menu) |
| `/audit config` | Delegate to `/audit-config` (skip menu) |
| `/audit style` | Run the new style sub-audit (skip menu) |
| `/audit all` | Run knowledge → config → style in sequence |
| `/audit <unknown>` | List valid verbs (no silent fail) |

**Back-compat:** `/audit-knowledge` and `/audit-config` remain directly invocable — the SessionStart cadence nudge points at them, and years of muscle memory reference them. The dispatcher is purely additive.

**SessionStart hook:** mechanism unchanged (it only emits a text nudge, never invokes a skill — verified in `bin/session-start-check.sh`, which concatenates `"...Run /audit-knowledge?"` strings and exits). One copy edit: the nudge may mention `/audit` as the umbrella while still naming the specific verbs.

## Section 2 — `/audit style` sub-audit (both ditto ideas)

Five steps. Reuses aria's existing promotion pipeline; the only new machinery is corpus-reading, inference, and the receipts gate.

```
past .jsonl logs → filter to USER msgs → infer candidates → RECEIPTS GATE → rules-backlog.md → (existing /audit-knowledge review) → feedback_*.md
  (the corpus)       (idea #1: mining)      (cluster)        (idea #2)         (staging)              user picks 'rule'            (user memory, tier a)
```

**Step 0 — Resolve config + locate corpus.** Read `~/.claude/aria-knowledge.local.md` for `knowledge_folder`. Locate the session-log dir (`~/.claude/projects/<cwd-encoded>/`). Scope is incremental: read `style-audit-log.md` for the last-mined timestamp; scan only `.jsonl` newer than that. First run = bounded look-back (see §3).

**Step 1 — Extract user-authored messages.** Walk the `.jsonl` files; keep only user-role messages; discard tool output, assistant turns, file dumps. **Reject aria's own artifacts as sources:** skip any message that is a `/command` invocation; never treat CLAUDE.md / MEMORY.md / existing `feedback_*.md` content as evidence. (Prevents a feedback loop where aria re-mines its own output.)

**Step 2 — Infer candidate rules.** Cluster authored messages into recurring working-style patterns across five layers: definition-of-done, rejection criteria, debugging approach, design taste, writing voice. Each candidate = one-line rule + supporting quotes.

**Step 3 — RECEIPTS GATE (idea #2, fail-closed).** A candidate survives only if:
- **≥2 distinct sessions** support it (not 2 quotes from one session), AND
- quotes are **dated + verbatim** (real substrings of real messages, with session date), AND
- **no fabrication** — if no real quote can be produced, the candidate is **dropped, not softened**.

Failing candidates are discarded. A "did-not-qualify" tail may list them for transparency (count only, or one-line reasons), but they are never written to a backlog.

**Step 4 — Stage to `rules-backlog.md`.** Surviving candidates append to the existing `rules-backlog.md`, each carrying receipts inline (redacted per §3). No promotion here.

**Step 5 — Report + hand off.** Summary: `N mined, M passed gate, K dropped`. Candidates promote through the **existing `/audit-knowledge` `rule` disposition → tier (a) `feedback_*.md`** path (tier b `user-rules.md` optional for genuinely cross-cutting rules). `/audit style` invents **no** new review gate or destination.

## Section 3 — Safety envelope

**Foundational fact:** `/audit style` is a **skill** (markdown + `allowed-tools: Read, Glob, Grep, Write, Edit`), not a script. It runs inside aria as Claude following instructions — it does **not** shell out to `ditto.py`. Safety = aria's normal tool-permission + Rule 22 model, plus explicit bounds:

1. **Reads are local + read-only.** Corpus = `~/.claude/projects/<cwd-encoded>/*.jsonl` (already on disk). No network tool in `allowed-tools`. Inference happens in the model already processing the session — no extra provider call, no egress beyond the current turn. Strictly less exposure than ditto (which can call an external model on flag+key; `/audit style` never does).

2. **Writes confined to two paths.** Only `rules-backlog.md` (append) and `style-audit-log.md` (timestamp). **Cannot write `feedback_*.md` directly** — promotion is the human-gated `/audit-knowledge` step. No deletes (Rule 6). Enforced by `allowed-tools` + step instructions + Rule 22 hook.

3. **First-run bounded; over-cap prompts the user.** Config `style_lookback_days` (default 90) windows the first run. Config `style_max_sessions` (default 50) is the over-cap threshold. When the corpus to scan exceeds the cap, **stop and prompt** — do not silently scan-the-cap-and-log-the-rest:
   > Found **N sessions** newer than last mine (cap M). Proceed?
   > - `recent` — scan M most-recent (older stay queued for later)
   > - `all` — scan all N (slower + more tokens; show estimate first)
   > - `window <D>` — scan last D days only
   > - `cancel` — do nothing
   
   Older sessions stay queued via the `style-audit-log.md` timestamp, so `all`-later still works. Nothing is lost; the user owns the depth/cost trade.

4. **Redaction before write.** Mined quotes get written to `rules-backlog.md` (which lives in `knowledge_folder` — potentially synced/committed). Apply a redaction pass mirroring ditto's `REDACTIONS`: API keys (`sk-*`, `sk_live_*`), JWTs, AWS/GitHub/Slack tokens, `password=`/`secret=`/`api_key=`, emails, IPs. A quote whose secret cannot be cleanly excised is **dropped, not written**.

5. **Preview-first.** The first `/audit style` (and any run exceeding a new-candidate threshold) shows a dry-run preview — "N candidates + receipts, nothing written yet — proceed? (y/n)" — before touching `rules-backlog.md`. Incremental small-delta runs may write directly.

6. **Opt-in only.** Never fired by the SessionStart nudge; never part of bare `/audit`'s menu-default execution. Runs only when explicitly selected. A deliberate periodic pass, not routine.

Composition: bounds #3 and #5 are distinct gates — #3 decides *how much to scan*, #5 decides *whether to write what was mined*. Both fail safe (resolve toward doing less / not writing).

## Section 4 — ditto safety brief + one-time diagnostic run

### Part A — Safety brief (grounded in `ditto.py` source, ~2,500 lines)

| Dimension | Finding | Verdict |
|---|---|---|
| Network (runtime) | stdlib-only; no requests/socket/urllib in mining path | Safe |
| Subprocess/eval | none | Safe |
| Reads | `~/.claude/projects/`, `~/.codex/sessions/`, `~/.copilot/session-state/` (local) | Expected |
| Writes | `~/.ditto/` + output dir (default cwd); confined | Contained |
| Deletes | only corrupted-segment quarantine + optional stale-dir cleanup | Narrow |
| Redaction | `REDACTIONS` runs in `mine_files()` before write | Best-effort |
| Model provider | only on explicit invocation with user-supplied creds; not by default | Opt-in |

**Two caveats (stated, not blockers):**
1. **Install touches network once.** `npx skills add …` and `curl -O …ditto.py` are bootstrap downloads. The tool makes no runtime network calls; getting it does. **Mitigation:** download `ditto.py`, pin/read it, run the pinned local copy — never `npx`-execute unpinned (Rule 33).
2. **Redaction is best-effort** (README says "inspect output before sharing"). A novel secret format won't match. **Mitigation:** run against logs only; eyeball outputs before sharing outward.

**Net:** safe to run locally as a read-only diagnostic given (a) pin-don't-npx, (b) dry-run/local-model, no provider key, (c) inspect before sharing.

### Part B — Diagnostic run (gated, each step)

Purpose: a **mirror**, not adoption — compare ditto's surfaced patterns against the 396 hand-authored `feedback_*.md`; capture any genuinely-new, receipted pattern back into aria through the normal gate.

1. **Fetch + pin** — download `ditto.py` to scratchpad; show sha256 + skim of network/write/delete lines to confirm the brief. No execution yet.
2. **Dry-run** — `python ditto.py --dry-run` against `~/.claude/projects/`, no provider key (local-only). Writes nothing.
3. **Card** — `python ditto.py --card` → profile card + `you.md` into scratchpad (not the knowledge folder), local model only.
4. **Compare + capture** — diff surfaced patterns against existing `feedback_*.md`; new+receipted → propose as `rules-backlog.md` candidate through the normal gate (never auto-written to memory).
5. **Clean up** — remove `~/.ditto/` cache + scratchpad outputs unless the user keeps them.

**Prohibited-action note:** ditto needs no credentials; none will be entered. A step wanting a provider API key is a stop — the user supplies it deliberately if ever. The default path uses no key.

## Section 5 — Rollout + testing

### Rollout: Claude-Code-canonical first (matches ADR-013/014 and every recent skill addition)

| Port | This release | Why |
|---|---|---|
| plugin-claude-code | Ships `/audit` + `/audit style` | Canonical; corpus-read + Bash + hooks native |
| plugin-claude-cowork | Tracked-drift | 9000-char summed-description cap near-full (needs coordinated trim); log-corpus access differs |
| plugin-openai-codex | Tracked-drift | Different log dir (`~/.codex/sessions/`) — corpus-locate needs Codex adapter |
| plugin-cursor-template | Tracked-drift | `.mdc` recompile via `port-skills-to-mdc.py` at next re-sync |
| plugin-antigravity | Tracked-drift | `build.sh` overlay regen at next parity pass |

Concretely: two new skill folders (`skills/audit/`, `skills/audit-style/`); `PORT-LEDGER.json` + `check-port-drift.sh` record both surfaces + version-pair trap; no other-port files touched this round.

### Config keys (additive; every user gets them on next `/setup` diff)

- `style_lookback_days` (default 90) — first-run window
- `style_max_sessions` (default 50) — over-cap prompt threshold
- `style_audit_log` — path, mirrors knowledge/config audit logs

Wired into `/setup` (write + validate), `CONFIG.md`, `QUICKSTART.md`, `/audit-config` Step 3b (Missing-Known-Fields cascade auto-enumerates).

### Testing

**A. Dispatcher — repro `audit-dispatch.sh`:** bare `/audit` → 4-option menu; `/audit knowledge|config|style` → delegate, skip menu; `/audit all` → sequence; `/audit-knowledge` / `/audit-config` still directly invocable; unknown subcommand → lists verbs.

**B. `/audit style` — repro `audit-style.sh`, fixture-driven:**
- **Fixture:** synthetic `.jsonl` (2+ sessions repeating a pattern; 1 session with a one-off; a file with a fake `sk-` secret; an aria `/command` message; a `feedback_*.md`-shaped message).
- **Receipts gate (load-bearing):** 2+-session pattern **passes**; single-session one-off **dropped**; no-verbatim-quote candidate **dropped** (positive + negative, Rule 15 RED→GREEN both directions).
- **Source rejection:** the `/command` and `feedback_*.md`-shaped messages are **not** used as evidence.
- **Redaction:** fake `sk-` secret redacted or quote dropped before write — grep output backlog to prove no secret survives.
- **Over-cap prompt:** >cap fixture triggers `recent/all/window/cancel`, not silent scan.
- **Write confinement:** only `rules-backlog.md` + `style-audit-log.md` touched; grep-assert **no** `feedback_*.md` write.
- **Rule 36 mutation:** the gate test must **fail** if the ≥2-session guard is removed (detects the guard's absence, not just presence).

**C. Live dogfood (Rule 20):** run `/audit style` for real against a small real window — confirm receipted candidates produced, nothing leaks, nothing auto-promotes. Then the ditto diagnostic (§4) as cross-check.

**D. Release gates (`release.sh`):** Gate A both suites green; Gate B skill-discovery byte budget — two new skills add description bytes; re-baseline `ARIA_SKILL_BUDGET` if the delta exceeds headroom (live ≈17,721/18,944); Gate C port-drift report.

## Open questions

None blocking. Deferred to plan/implementation:
- Exact default values for `style_lookback_days` / `style_max_sessions` (90/50 are starting proposals).
- Whether the "did-not-qualify" tail lists reasons or count-only (transparency vs noise).
- Whether `/audit all` runs `style` unconditionally or only when there's new corpus since last mine.
