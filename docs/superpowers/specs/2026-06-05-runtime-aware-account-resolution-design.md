# Runtime-Aware Account Resolution for Statusline Usage Tracking — Design

**Date:** 2026-06-05
**Status:** Draft (pending Mike review)
**Component:** `plugin-claude-code/bin/statusline-meter.sh`, `plugin-claude-code/bin/usage-threshold-inject.sh`, `plugin-claude-code/bin/session-start-check.sh` (TASK BUDGET reader — 3rd consumer, found in prospect)
**Version:** 2.24.2 → **2.24.3** (patch; matches the 2.24.1/2.24.2 statusline-fix cadence)
**Prospect:** `knowledge/logs/prospect/2026-06-05-file-runtime-aware-account-resolution.md` — verdict PROCEED-WITH-CHANGES (changes folded in)
**Extends/qualifies:** ADR-098 (statusline per-account usage-state, v2.24.2)
**Promotes to:** ADR-099 — *account resolution is runtime-specific, not `~/.claude.json`-universal*

---

## 1. Problem

The status-line meter (writes a usage snapshot) and the `UserPromptSubmit` inject hook
(reads it, alerts on threshold) both resolve the session's account from
`~/.claude.json → .oauthAccount`. That file is the **standalone Claude Code CLI**
credential store.

When Claude Code runs **hosted inside Claude Desktop** (binary at
`~/Library/Application Support/Claude/claude-code-vm/<ver>/`, full plugin-claude-code
hooks firing), `~/.claude.json` still reports the *CLI* login while the real session
account is the *Desktop* login. Result:

- The meter labels usage with the wrong account and keys the snapshot file by the wrong
  account UUID.
- The inject hook, keying the same wrong way, reads a snapshot belonging to a different
  account/runtime and alerts on it.
- v2.24.2's per-account keying (ADR-098) is **silently defeated**: both runtimes resolve
  to the *same* (CLI) UUID, so they collide in one shared state file.

**Confirmed empirically (2026-06-05, this session):**
- `CLAUDE_CODE_ENTRYPOINT=claude-desktop`, `__CFBundleIdentifier=com.anthropic.claudefordesktop`,
  `claude-code-vm/2.1.161/` present → Desktop-hosted.
- `~/.claude.json` reports the CLI login account (`<cli-account-uuid>` / the CLI user's email).
- This session's real account is a *different* user (`<session-account-uuid>`).
- The snapshot `aria-statusline-state-<cli-account-uuid>.json` showed `five_hour_pct: 100` —
  correct for the CLI account, **wrong for this Desktop session** (real usage much lower) —
  and the inject hook fired a false "5-hour 100%" alert.

### 1a. Secondary bug — staleness (affects MULTIPLE readers, not just the inject hook)

The snapshot is only overwritten when the meter next renders. On **resume-after-hours**, the
file holds the last pre-gap value until the first render of the resumed session — which races
against the agent's first action. So *any* consumer that reads it before that render sees a
stale figure. Three readers exist; none currently checks freshness:

1. **`usage-threshold-inject.sh`** reads `five_hour_pct` + `five_hour_resets_at` but never
   compares `resets_at` to *now* → can alert on a pre-reset figure.
2. **The agent, via the SessionStart TASK BUDGET instruction** (`session-start-check.sh`),
   reads the snapshot on demand before `/handoff`/`/wrapup`/compaction — and may also **recall
   a pre-gap number from conversation context instead of re-reading**.
3. `seven_day_resets_at` is not even stored today, so the 7-day figure can't be checked at all.

**Observed 2026-06-05, 4:44pm:** live statusline = `26%, resets 5pm` (correct), but the agent's
wrap-up prose said *"5-hr usage is at the cap (resets 12:00)"* — a stale snapshot whose
`resets_at` (12:00) is already in the past. `now > five_hour_resets_at` identifies it exactly.

**Fix principle:** staleness is a *data* property (`now > resets_at`), so **every reader must
enforce it** — the inject hook (skip the alert) AND the agent (the TASK BUDGET instruction must
teach the rule + tell the agent to re-read fresh, not recall earlier numbers).

### 1b. Tertiary bug — `context_pct` is session-scoped but stored account-scoped

5h/7d usage is **per-account** (correctly shared across that account's sessions). But
`context_window.used_percentage` is **per-session** — it describes *one session's* window. Storing
it in the account-keyed snapshot means:

- Two concurrent sessions of the same account **clobber each other's `context_pct`**.
- A resumed session reads its own **pre-gap** `context_pct` until the next render.
- `context_pct` has **no `resets_at`**, so the §1a staleness guard cannot detect its staleness.

**Observed 2026-06-05:** the inject hook warned *"context window at 82%"* (the morning snapshot's
~78-82) while the live session was at **26%** against its 1M window. A second session then
**confabulated a "~200k baseline" explanation** to reconcile the stale number with reality —
i.e. the stale alert didn't just mislead, it induced a false root-cause theory. (Both readers use
the same `context_window.used_percentage`, which is window-relative per docs; the separate
`exceeds_200k_tokens` flag is unrelated. There is no dual-baseline; the discrepancy was staleness.)

**Fix principle:** a metric is trustworthy only when it is **attributable** AND **fresh**, and the
two tests differ by metric scope:

| Metric | Scope | Attribution | Freshness |
|--------|-------|-------------|-----------|
| 5h / 7d | per-account | account key (resolver) | `now ≤ resets_at` |
| `context_pct` | per-session | `snapshot.session_id == live session_id` | non-`null` measurement (not post-`/compact` sentinel) |

So the snapshot must stamp `session_id`, and readers (inject hook + agent instruction) trust
`context_pct` only when it is **this session's** and reflects a **real measurement** — otherwise
treat context as unknown (no alert / "unknown", never another session's or a post-`/compact`
figure). *(No write-age window: context% is conversation-scoped and restored on resume, so it
doesn't go wall-clock-stale; and `refreshInterval` re-stamps `written_at` anyway — see §4.7.)*

---

## 2. Constraints

- **Hard constraint:** the Desktop account *identity* (email) lives in Electron's encrypted
  Cookies/token store. A POSIX shell hook cannot read it, and probing that store is
  out of bounds. We must resolve identity **without** decrypting anything.
- **Prime directive (existing):** "a broken status line is worse than a sparse one" — every
  field guarded, errors suppressed, missing data omitted, never a non-zero on screen.
- **Must not regress:** the v2.24.2 CLI multi-account behavior. Two CLI accounts on one
  machine must still each see only their own usage.
- **Rule 33:** verified against current docs — the statusline payload (docs v2.1.90) and the
  hooks payload/env expose **no** account/email/org field. The only *documented* runtime
  discriminator is `CLAUDE_CODE_REMOTE` (web vs local; unset for local-Desktop, so it does
  not distinguish Desktop-hosted from CLI). `CLAUDE_CODE_ENTRYPOINT` exists empirically but
  is **undocumented** — usable as a signal, not as a dependency.

---

## 3. Key discovery — the account UUID *is* recoverable (plain, not encrypted)

Claude Desktop organizes its session state by account in **plain folder names**:

```
~/Library/Application Support/Claude/claude-code-sessions/<accountUUID>/<orgUUID>/local_<id>.json
```

- The first path segment is the **per-user account UUID**; the second is the org UUID.
  Proof: the CLI user's `accountUuid` (from `~/.claude.json`) appears as a first-level
  folder, sibling to the other user accounts; org UUIDs appear only at the second level,
  shared across user folders.
- Each Desktop session file stores the live session id as `cliSessionId`, which equals the
  `.session_id` in both the statusline payload and the hook payload. Grepping for the
  current `session_id` resolves to exactly one `<account>/<org>/` path in **~9 ms** over
  324 files / 25 MB.
- The same account UUID also appears in the injected `$PATH` segment
  `local-agent-mode-sessions/<accountUUID>/<orgUUID>/…` (env-only, no filesystem read).

This gives us the **per-user account UUID** (canonical, exactly what keying needs — and
*more precise* than email, which was only ever the display segment, never the key) **without
touching the encrypted identity store**. The email remains unreadable under Desktop; that is
acceptable because it was display-only.

---

## 4. Design

### 4.1 A runtime-aware account resolver (shared logic, inlined in both scripts)

Replaces the unconditional `~/.claude.json` read. Produces `(key, runtime, email)`:

```
resolve_account(session_id):
  CLDIR = "$HOME/Library/Application Support/Claude"

  # Tier 1 — env-only PATH parse (cheapest; runs on every render).
  # ONE awk pass over $PATH (split on ':') for the first
  # local-agent-mode-sessions/<UUID>/<UUID> match, then POSIX parameter
  # expansion to split — NO pipes, NO cut, NO grep|head (see §4.6 Performance).
  pair = awk_first_match($PATH, 'local-agent-mode-sessions/<UUID>/<UUID>')
  rest = ${pair#local-agent-mode-sessions/}
  acct = ${rest%%/*}; org = ${rest#*/}; org = ${org%%/*}
  # structural validation: accounts CONTAIN orgs, never the reverse
  if acct and [ -d "$CLDIR/claude-code-sessions/$acct/$org" ]:
      return (acct, "desktop", "")

  # Desktop-hosting signal (undocumented, best-effort, false-positive-safe):
  desktop = (CLAUDE_CODE_ENTRYPOINT == "claude-desktop")
            or (CLAUDE_CODE_EXECPATH contains "claude-code-vm" or "/Claude/claude-code/")
            or (__CFBundleIdentifier contains "claudefordesktop")

  # Tier 2 — authoritative FS lookup by the real session id.
  # GATED behind a Desktop signal so a genuine CLI session (even on a machine
  # that ALSO has Desktop installed) never pays the ~15ms recursive grep.
  if desktop and session_id and [ -d "$CLDIR/claude-code-sessions" ]:
      hit = first file under claude-code-sessions/*/*/ containing session_id
      if hit: return (account_segment_of(hit), "desktop", "")

  # Tier 3 — Desktop detected but unresolved -> graceful degrade
  if desktop:
      return ("desktop-unknown", "desktop-unknown", "")

  # Tier 4 — CLI / VS Code / API-key path = v2.24.2, BYTE-FOR-BYTE UNCHANGED
  uuid  = jq .oauthAccount.accountUuid   ~/.claude.json   # may be empty (API-key)
  email = jq .oauthAccount.emailAddress  ~/.claude.json
  return (uuid or "default", "cli", email)
```

**Why this ordering is safe**

- A standalone CLI session never has the `local-agent-mode-sessions` PATH segment, has no
  Desktop signal, and its session id is not stored under `claude-code-sessions/` (CLI uses
  `~/.claude/projects/`), so Tier 1 misses, Tier 2 is skipped (gate false), Tier 3 is
  skipped, and Tier 4 runs → identical to today. The resolution method is itself the
  runtime discriminator; the Desktop signal is only a *gate* for the expensive fallback and
  the degrade case, never the primary identification.
- The `[ -d <acct>/<org> ]` check guarantees Tier 1 returns the **user account**, never the
  org (the `skills-plugin/<org>/<acct>` PATH variant cannot satisfy it, and the regex only
  matches the `<acct>/<org>` form).
- Tier 3 only fires when a Desktop signal is present but resolution failed — the rare,
  honestly-degraded case.

### 4.6 Performance (measured 2026-06-05, per single invocation = 5-iter total ÷ 5)

These run on hot paths (meter per status-line render — async, off the model's token path;
inject hook once per user prompt), so the budget is "imperceptible", not "zero".

| Path | Cost | Notes |
|------|------|-------|
| OLD v2.24.2 | ~7 ms | 2× `jq` on `~/.claude.json` (63 KB — cheap) |
| NEW Tier 1, **naive** pipeline | ~13 ms | `printf｜tr｜grep｜head` + 2× `cut` = ~5 subprocess spawns |
| NEW Tier 1, **required** impl | ~3–5 ms (target) | **one `awk`** + parameter expansion + one `[ -d ]` stat |
| NEW Tier 2 (gated fallback) | ~15 ms | recursive `grep` over `claude-code-sessions/` (25 MB) |
| NEW Tier 4 (CLI) | ~Tier 1 + ~7 ms | failed PATH parse, then the same 2× `jq` as OLD |

**Cost is dominated by subprocess-spawn count, not file I/O.** Therefore: (a) Tier 1 MUST
be a single `awk` + shell parameter expansion (not a pipeline) so the common cases land at
or below the OLD cost; (b) Tier 2's grep is gated behind a Desktop signal so CLI never pays
it. Token usage is unaffected (pure shell, zero model tokens) and the inject hook's
*injection* tokens trend **down** — correct keying + the staleness guard remove false-alert
injections (and the costly model reactions a false "100%" can trigger).

### 4.7 Freshness mechanism — `refreshInterval` (primary) + guards (backstop)

**Why staleness happens (verified vs docs):** the meter writes the snapshot only when the
status line renders — *after each new assistant message*, after `/compact`, on permission-mode
or vim-mode change (debounced 300ms). It does **not** poll. So the snapshot is refreshed
several times during an active tool-using turn, but is **frozen while idle / on resume** (no
assistant message ⇒ no render) until the first reply of the resumed session completes. The
inject hook (`UserPromptSubmit`) and a mid-turn agent read therefore see *the previous turn's*
snapshot — fine during active use (seconds old), stale on resume-turn-1.

**`refreshInterval: 30s`** (set in the `statusLine` settings object by the `/statusline` wiring)
keeps the **5h/7d values current during idle** — the one place a timer genuinely helps: those
values can change in *another* session while this one sits idle, and resets-based staleness only
tells you a window *expired*, not that the figure drifted low. The timer keeps the displayed line
and the snapshot current so the agent/alert see real current 5h/7d usage. Cost: a ~5 ms meter run
every 30s while Claude Code is open — **no API tokens** (docs confirm the status line is local),
**no extra alerts** (alerts fire on `UserPromptSubmit`, band-gated, independent of the render
timer). It is a **value-currency/UX** mechanism, **not** a correctness mechanism.

**The guards are the correctness floor**, independent of the timer: 5h/7d use `resets_at`
(absolute wall-clock — timer-re-stamp-proof); context% uses `session_id` match + `null`-guard
(NOT write-age — see §4.4 2b and the meter null-handling below). There is **no `written_at`
freshness window** and **no `context_freshness_seconds` constant** — both dropped by the
2026-06-05 re-prospect (the window was defeated by the timer's `written_at` re-stamp AND
unnecessary, since context% is conversation-scoped and restored on resume).

**Meter null-handling (required):** `current_usage`/`context_window.used_percentage` is `null`
before the first API call and immediately after `/compact`. On those renders the meter must NOT
write a stale `context_pct` — it omits the field (or writes it as absent) so the inject hook's
null-guard skips context rather than surfacing a pre-`/compact` figure.

**Alternatives considered and rejected** (decision trail):
- *Increase the render debounce* — **not possible** (the 300ms debounce + event triggers are
  Claude-Code-internal, not plugin-configurable) and wrong-direction (would reduce active-use
  freshness, do nothing for the idle hole).
- *Relocate the inject hook to a different event* — **no gain**: no hook payload carries usage
  data (it only rides the status-line payload → snapshot), so any event reads the same file;
  and `UserPromptSubmit` is the only event that can inject a warning into the model's context.
  The "one render behind" property is structural, not a hook-placement artifact.

### 4.2 Wiring — inlined, self-contained (no external `source`)

Three scripts need the resolver, with two different runtime situations:

- `usage-threshold-inject.sh` and `session-start-check.sh` run **in-place** in `bin/` and
  **already `source config.sh`** → the **canonical resolver lives as a function in
  `config.sh`** (`kt_resolve_account`), reused by both with zero duplication.
- `statusline-meter.sh` is **copied standalone** to `~/.claude/aria-statusline-meter.sh` by
  `/statusline` (loses `CLAUDE_PLUGIN_ROOT`, cannot reliably `source` a sibling) → it carries
  an **inlined mirror** of the same function.

To prevent drift between the `config.sh` canonical and the meter's inlined mirror, a
**structural sync-test** asserts the two function bodies are identical (delimited by marker
comments `# >>> kt_resolve_account` / `# <<< kt_resolve_account` in both files).

(Alternative considered: a separate `bin/account-resolve.sh` copied alongside the meter by
`/statusline` — rejected: adds a file the meter depends on existing, a new way for the status
line to break, violating the prime directive.)

### 4.3 Snapshot schema (additions)

| Field | Change |
|-------|--------|
| `account_uuid` | now the **resolved** per-user UUID (Desktop) or `~/.claude.json` UUID (CLI) |
| `account_email` | written **only on the CLI path**; omitted under Desktop |
| `runtime` | **NEW** — `"cli"` \| `"desktop"` \| `"desktop-unknown"` |
| `seven_day_resets_at` | **NEW** — stored so the 7-day figure can be staleness-checked |
| `session_id` | **NEW** — the writing session's id, so `context_pct` (session-scoped) is only trusted by the same session (per §1b) |
| `written_at` | already present — informational only (snapshot write time); NOT used as a freshness gate (see §4.7) |
| `context_pct` | written only when `current_usage` is non-`null`; omitted on the post-`/compact`/pre-first-call sentinel (per §4.7 meter null-handling) |

State file key: `~/.claude/aria-statusline-state-<key>.json` where `<key>` is the resolved
account UUID (Desktop or CLI) / `desktop-unknown` / `default`.

### 4.4 Inject-hook changes

1. **Read key via the same resolver** so reader and writer always agree.
2. **Staleness guard (5h/7d):** if `five_hour_resets_at` is set and `now > five_hour_resets_at`,
   ignore `five_hour_pct` (expired window — do not alert). Same for `seven_day_resets_at`.
2b. **Context guard (per §1b; SHRUNK by re-prospect 2026-06-05):** alert on `context_pct` only
   when `snapshot.session_id == live session_id` (the hook payload carries `.session_id`) AND the
   meter actually had a context measurement to write (i.e. the snapshot's context is not the
   `null`/absent post-`/compact` sentinel). **No write-age window** — it was dropped: context% is
   conversation-scoped and restored on resume (so it doesn't go wall-clock-stale like 5h/7d), and a
   `written_at` window is defeated anyway by the `refreshInterval` re-stamp (no trigger field to
   distinguish a timer tick — see §4.7). The real harms are **cross-session clobber** (→ `session_id`
   match) and **post-`/compact`** (→ `null`-guard; `current_usage` is `null` after `/compact` and
   before the first API call).
3. **Degrade only on `runtime == "desktop-unknown"`: SUPPRESS the alert** (locked 2026-06-05)
   — inject nothing; never assert an account we can't attribute (honors the prime directive).
   When `runtime == "desktop"` (resolution succeeded) the alert is correct for the real
   account and fires normally — **no caveat needed.**

### 4.4b Session-start guardrail (third consumer — found in prospect)

`session-start-check.sh` builds the TASK BUDGET pointer `USAGE_SNAP` from a key `_uk`
resolved from `~/.claude.json` (lines ~232-236) — the same bug. Under Desktop it tells the
agent to read another account's snapshot. **Fix (two parts):**

1. **Key:** replace its inline `_uk` block with a call to the shared `kt_resolve_account` (it
   already sources `config.sh`), so the path it surfaces matches what the meter writes and the
   inject hook reads.
2. **Staleness rule in the instruction (covers §1a reader #2):** the TASK BUDGET message must
   tell the agent to **re-read the snapshot fresh at judgment time** (not recall usage numbers
   mentioned earlier in the conversation), and to treat the `five_hour_pct`/`seven_day_pct` as
   **stale/expired when the current time is past `five_hour_resets_at`/`seven_day_resets_at`**
   (that window has reset; the real current value is lower/unknown — do not report the stored
   figure as current). For **`context_pct`**, only treat it as current when the snapshot's
   `session_id` matches this session AND `context_pct` is present (non-`null`); otherwise treat
   context as unknown (it's another session's, or a post-`/compact` sentinel) — never report it
   or rationalize it. (No write-age check — context% is conversation-scoped, restored on resume.)
   This is the only staleness/scope defense on the agent-read path, since the agent never runs
   the inject hook's guards.

### 4.5 Status-line display (meter)

- Email segment shown **only when `runtime == "cli"`** (the one case the email is trusted).
- Under Desktop, the email segment is omitted. Exact replacement marker (e.g. a dim
  `⌂ desktop` hint vs. silent omission) is **deferred** per Mike — out of scope for this
  spec; default is silent omission until decided.

---

## 5. Error handling / degradation

| Situation | Behavior |
|-----------|----------|
| `jq` missing | unchanged: meter → model-only, no snapshot; inject → silent no-op |
| Desktop, resolution succeeds | correct per-user key + alert; email omitted |
| Desktop, resolution fails | key `desktop-unknown`; alert **suppressed**; email omitted |
| CLI / VS Code / API-key | v2.24.2 unchanged (key by `~/.claude.json` UUID; email shown) |
| `claude-code-sessions/` absent | Tiers 1–2 miss → Tier 3/4 (never errors) |
| Snapshot 5h/7d past `resets_at` | inject ignores that metric (no stale alert) |
| Snapshot `session_id` ≠ live session | inject skips `context_pct` (other session's); 5h/7d still evaluated |
| `context_pct` absent/`null` (post-`/compact`/pre-first-call) | inject skips `context_pct`; 5h/7d still evaluated |

---

## 6. Testing (TDD — failing tests first)

Shell-level tests with crafted fixtures (fake `$PATH`, fake `claude-code-sessions/` tree,
fake `~/.claude.json`, fake snapshot):

1. **CLI unchanged:** no Desktop signals → key = `~/.claude.json` accountUuid, email shown.
2. **CLI multi-account no-regress:** two `~/.claude.json` UUIDs → two distinct keys.
3. **Desktop resolved (PATH):** `$PATH` has `local-agent-mode-sessions/<acct>/<org>` and the
   dir exists → key = `<acct>`, runtime `desktop`, no email.
4. **Desktop resolved (FS fallback):** PATH parse blocked, session id present in
   `claude-code-sessions/<acct>/<org>/` → key = `<acct>`.
5. **Org-not-user guard:** flipped `skills-plugin/<org>/<acct>` form must NOT yield the org.
6. **Desktop unresolved:** Desktop signal present, no resolvable account → `desktop-unknown`,
   alert suppressed.
7. **Staleness:** snapshot `five_hour_pct=100`, `five_hour_resets_at` in the past →
   no 5-hour alert. Same for 7-day.
8. **Reader/writer agreement:** meter, inject, AND `session-start-check.sh` resolve the
   identical key for the same env (all three consumers, not just two).
9. **Structural sync:** the meter's inlined `kt_resolve_account` mirror is byte-identical to
   the `config.sh` canonical (compare the marker-delimited bodies).
10. **desktop-unknown suppression:** Desktop signal present, account unresolved → inject
    injects nothing (no alert) and the snapshot is keyed `desktop-unknown`.
11. **Agent-read staleness instruction:** `session-start-check.sh`'s TASK BUDGET message
    contains the "re-read fresh, don't recall earlier numbers" directive, the
    `now > resets_at ⇒ stale` rule for 5h and 7d, AND the context session-match+recency rule
    (string-presence assertion, since the behavior itself is agent-side).
12. **Context cross-session guard:** snapshot `session_id` ≠ live `session_id` → inject does
    NOT alert on `context_pct` (even if over threshold), but still evaluates 5h/7d.
13. **Context null-guard:** `context_pct` absent/`null` in the snapshot (post-`/compact`) →
    no context alert; meter omits `context_pct` when `current_usage` is `null`.
14. **Context happy path:** matching `session_id` + present `context_pct` + over threshold →
    context alert fires (no regression of the legitimate case).

---

## 7. Deliverables

1. `config.sh`: add canonical `kt_resolve_account`. Edits to `statusline-meter.sh` (inlined
   mirror + schema incl. `session_id` + key), `usage-threshold-inject.sh` (resolver + 5h/7d
   staleness guard + context session-match+freshness guard + suppress-on-`desktop-unknown`),
   and `session-start-check.sh` (resolver for `_uk` + TASK BUDGET staleness/scope instruction).
   Context guard = `session_id` match + `null`-guard (no write-age window / no freshness constant —
   dropped by re-prospect). Meter omits `context_pct` when `current_usage` is `null`.
2. **Version bump 2.24.2 → 2.24.3** (locked — matches the 2.24.1/2.24.2 statusline-patch
   cadence) + CHANGELOG entry.
3. **ADR-099** at `~/Projects/knowledge/projects/aria/decisions/099-…md` (number confirmed
   free) — **two** durable principles: (a) *account resolution is runtime-specific, not
   `~/.claude.json`-universal* (supersedes ADR-098's "key by `~/.claude.json`" reasoning for
   the Desktop runtime); (b) *a persisted usage metric is trustworthy only when **attributable**
   AND **fresh**, and the attribution scope differs per metric* — 5h/7d are per-account
   (resets-based freshness), `context_pct` is per-session (session-match + write-age freshness).
   A stale/misattributed metric must degrade to "unknown," never be surfaced (it misleads AND
   induces downstream confabulation — see §1b).
4. **Port re-check (reframed by prospect):** `plugin-antigravity` ships the 2 scripts but its
   resolution targets `~/.gemini/antigravity.json` and it has **no Claude-Desktop hosting
   scenario** → **N/A with reason** (the `claude-code-sessions` tiers are Claude-Desktop-only;
   porting them would be inert/harmful). `codex`/`cursor`/`cowork` do **not** ship the scripts
   (N/A). Document the exemption; do not copy the fix. Sync `/statusline` skill copy-paths only
   if a new file must be copied (none — resolver is in `config.sh` + inlined, no new file).
4b. **`/statusline` wiring:** add `"refreshInterval": 30` to the `statusLine` object the skill
   writes into `~/.claude/settings.json` (primary freshness mechanism, §4.7). On refresh/repair,
   set it if absent; preserve a user's existing higher-frequency value. Document the 30s timer +
   rationale in `skills/statusline/SKILL.md` and `CONFIG.md`.
5. Resolve the OPEN backlog entry (2026-06-05) and update `CLAUDE.md` last-reviewed line.
6. Update the `account_email`/snapshot-field docs in `CONFIG.md` + `skills/statusline/SKILL.md`
   to reflect runtime-aware keying (email CLI-only; new `runtime` field). No code there.

---

## 8. Out of scope / deferred

- Exact Desktop email-segment replacement UI (Mike-deferred).
- Reading the encrypted Desktop identity store (hard constraint; never).
- Recovering the Desktop *email* (only the account UUID is recoverable plainly).
