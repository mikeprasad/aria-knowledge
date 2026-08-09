# Design — check local references before fetching externally

**Date:** 2026-08-09
**Status:** Prospected 2026-08-09 — PROCEED-WITH-CHANGES, amendments C1/C2/C3
folded in (§4.6a–c, AC11–13). Ready for a plan.
**Scope:** `plugin-claude-code` only (Bash hook). Ports tracked-drift.
**Ships as:** new `bin/pre-external-fetch-check.sh` + 2 config keys + tests.

---

## 1. The problem, plainly

An agent hits a wall on some external surface — a credential, an endpoint, a
vendor API — and reaches straight for the vendor's public documentation. The
answer was already written down locally, by a past session, often *because that
same wall cost hours once before*.

The recorded instance (2026-08-09, Bitbucket auth):

1. Two API tokens returned "not supported for this endpoint."
2. The agent correctly declined to conclude anything from that failure.
3. It then fetched Atlassian's support docs — two `WebFetch` calls.
4. The user interrupted: *"check how we did it before we used a different method."*
5. The local reference answered it, and named the canonical username
   (`x-bitbucket-api-token-auth`) the agent had spent two calls not finding.

The governing rule already existed —
`feedback_read_recorded_reference_before_probing_known_surface` — and had been
written precisely because this failure had already happened once. So:

> **This is not a missing rule. It is a rule that nothing surfaces at the moment
> it applies.** The fix is a surfacing mechanism, not more prose.

That distinction sets the whole design. Adding another rule, or strengthening the
wording of the existing one, is the intervention that already failed.

---

## 2. Prior art in this plugin

`bin/pre-explore-codemap-check.sh` is the structural template:

> *A CODEMAP exists at `<path>` — read the Directory section before exploring
> further. Fires once per project per session.*

That is the same sentence with two substitutions: `Glob|Grep` → `WebFetch|WebSearch`,
and "CODEMAP" → "recorded local reference." The new hook copies its shape
wholesale: PreToolUse, extract a key from tool input, look up a local artifact,
per-session cooldown, fail open on anything unparseable.

---

## 3. What was measured, and what it ruled out

All figures measured 2026-08-09 against the live corpus
(`~/Projects/knowledge`, 223 MB, 2,088 live `.md`) and the auto-memory dir
(989 files, 7.2 MB). Warm cache, this machine.

### 3.1 The existing tag matcher is the wrong instrument — RULED OUT

`lib-index-match.sh` was the obvious reuse candidate. Driven with the three
queries the failing session would have produced:

| Query | Result |
|---|---|
| `https://support.atlassian.com/bitbucket-cloud/docs/using-api-tokens/` | 5 files, **5/5 irrelevant** |
| `bitbucket api token scopes` | 0 matches |
| `can scopes be edited on an existing atlassian api token` | 0 matches |

The 5 "hits" were design-token documents — a DF sizing guide, a cascade-layer
pre-mortem, an `!important` retrospective, two Android icon ADRs. `api` and
`tokens` cleared the ≥2-tag precision floor **by homonym**: auth tokens vs design
tokens.

Root cause: `bitbucket` is **not among the 362 known tags**, so no tag match can
ever reach the file that helps — even though that file
(`projects/cs/references/staging-postgres-mcp-and-bitbucket-auth.md`) is
referenced **36 times** in `index.md`.

This is the recorded failure class *guard scoped to the wrong unit*: the tag
index is drawn around **topics**; the need is drawn around **surfaces** — host,
vendor, credential, tool. A hook that surfaces 5 wrong files is worse than
silence, because it trains the reader to dismiss it.

### 3.2 Host-keying works, with a cap

| Key | Hits | Time | Note |
|---|---|---|---|
| `atlassian.com` (knowledge) | 3 | 1.09 s | **#1 is the exact file that was needed** |
| `bitbucket.org` (memory) | 2 | 0.06 s | includes the governing feedback memory itself |
| `github.com` (knowledge) | 76 | 0.29 s | ambient — carries no signal |

Domain-frequency distribution across the corpus (402 distinct registrable
domains): 205 appear in 1 file, 124 in 2–3, 60 in 4–10, 11 in 11–30, 2 in 31+.
`atlassian.com` sits at 3. The ambient tail is `common.space` (93),
`thecollab.co` (23), `github.com` (11), `google.com` (11).

⇒ **A hit-count cap is load-bearing, not a nicety.** Above it, stay silent.

### 3.3 Both stores are required — neither is redundant

- `atlassian.com` → 3 hits in knowledge, **0 in memory**.
- `bitbucket.org` → 2 hits in memory, and the top one *is*
  `feedback_read_recorded_reference_before_probing_known_surface.md`.

Either store alone misses half the case. Memory-dir grep costs 0.06 s, so no
cost argument arises.

### 3.4 Prose keying is viable — with a stopword filter

378 distinct domain stems exist in the corpus. **51 of them are ordinary English
words**: `common`, `session`, `index`, `key`, `space`, `field`, `head`, `body`,
`size`, `style`, `text`, `card`, `gate`, `medium`, `message`, `parent`, `schema`,
`template`, `run`, `seen`, `secondary`, `subscription`, … Simulated against
realistic queries:

| Query | Stem hits |
|---|---|
| `how to debounce a react hook` | none |
| `swiftui list performance large data` | none |
| `postgres index bloat vacuum full` | `postgres`, **`index`** ← false positive |
| `bitbucket api token scopes` | `bitbucket` ✅ |
| `atlassian api token edit scopes` | `atlassian` ✅ |

⇒ Prose matching works once the dictionary-word stems are excluded. The two real
queries fire cleanly on exactly the right stem.

### 3.5 Timing rules out a domain inventory — RULED OUT

| Operation | Time | Verdict |
|---|---|---|
| Single-domain `grep -rl` | 0.90–1.09 s | fine |
| 5-word alternation `grep -rlE` | 2.32 s | acceptable |
| Full domain-inventory build (`grep -roE`) | **7.32 s** | **exceeds the 5 s hook timeout** |

An inventory cannot be built inside a PreToolUse hook. Caching it would require
a build step elsewhere plus invalidation logic.

**But measuring it showed the inventory was never needed.** `WebFetch` already
carries the domain; prose only needs to know *whether* coverage exists, not which
stem produced it. A single alternation `-l` grep answers that directly. This
removes the cache, the invalidation logic, and the runtime dependency on
`/usr/share/dict/words` (a macOS symlink to `web2`, not guaranteed on Linux, and
this plugin ships to other people).

---

## 4. Design

### 4.1 Registration

```json
{
  "matcher": "WebFetch|WebSearch",
  "hooks": [{
    "type": "command",
    "command": "bash ${CLAUDE_PLUGIN_ROOT}/bin/pre-external-fetch-check.sh",
    "timeout": 5
  }]
}
```

Tool input fields verified against the live schemas: `WebFetch.url` (required,
`format: uri`), `WebSearch.query` (required, `minLength: 2`), and
`WebSearch.allowed_domains` (optional array).

### 4.2 Key extraction

| Source | Key | Ambiguity |
|---|---|---|
| `WebFetch.url` | registrable domain — last two labels of the host | none — match the full domain |
| `WebSearch.allowed_domains[]` | each entry, as-is | none — same as above |
| `WebSearch.query` | lowercase words, minus stopwords, longest-first, **capped at 4** | ambiguous — match `stem\.[a-z]` |

The 4-word cap bounds the alternation so the worst case stays at the measured
2.32 s rather than growing with query length.

### 4.3 Lookup

Two stores, both grepped with `/usr/bin/grep` (the workspace `grep` is a ugrep
wrapper that honors `.gitignore` and silently skips embedded repos):

1. `$KT_KNOWLEDGE_FOLDER`, `--include='*.md' --exclude-dir=archive`
2. `~/.claude/projects/*/memory` — globbed, so no cwd-encoding logic is needed

`-l` (stop at first match per file), never `-o`.

### 4.4 Cap

Total hits across both stores > `external_fetch_max_hits` (default **8**) →
`exit 0`, silent. 389 of 402 domains sit at or below 8; the 13 above are all
ambient.

### 4.5 One-shot gate

Cooldown file `/tmp/aria-extfetch-<session_id>-<cooldown_key>`, matching the
`pre-explore-codemap-check.sh` convention (session id from the hook payload,
`$$` as fallback).

**`cooldown_key` is defined per source, and must be stable across a retry** —
otherwise the retry mints a new key, is denied again, and the gate becomes an
infinite block rather than a one-shot:

| Source | `cooldown_key` |
|---|---|
| `WebFetch.url` | the registrable domain (`atlassian.com`) |
| `WebSearch.allowed_domains[]` | the domains, sorted, joined by `_` |
| `WebSearch.query` | the surviving candidate stems, **sorted**, joined by `_` |

Sorting is what makes it stable: the prose path selects stems longest-first, so
without a canonical sort the same query could yield a different key ordering and
defeat the cooldown. All keys are sanitised to `[a-z0-9._-]` before use in a
filename.

- **Present** → `exit 0`. This is the retry; allow it.
- **Absent** → write it, **verify the write landed**, then emit:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse",
 "permissionDecision":"deny",
 "permissionDecisionReason":"<reason naming the matched paths>"}}
```

**`deny`, not `ask` — deliberate.** `deny` returns the reason to the model as
tool feedback and the model retries. `ask` raises a dialog in front of the *user*.
The friction belongs on the agent, not on the user's attention. The user is not
the one who needs redirecting.

The reason text must state three things: the matched paths, that the correct next
step is *read them, then fetch only what they do not answer*, and that the retry
will pass.

### 4.6 Fail open, always

Unparseable payload, missing config, absent knowledge folder, `grep` non-zero,
zero hits, unresolvable session id → `exit 0`. A gate that cannot read its own
input must never block. Precedent: `pre-cron-check.sh` header.

**Plus two cases the precedent hook never has to handle** — amendments C1 and C3
from the 2026-08-09 prospect:

- **Cooldown write failed** → `exit 0`, allow. See §4.6a.
- **Own runtime budget exceeded** → `exit 0`, allow. See §4.6c.

### 4.6a C1 — the cooldown write is a precondition of denying

`pre-explore-codemap-check.sh:66` writes its cooldown as
`date +%s > "$COOLDOWN_FILE" 2>/dev/null` and never checks the result. That is
safe **there** because that hook is *advisory* — a failed write merely repeats a
reminder.

Transplanted into a **denying** hook, the consequence inverts:

```
write fails → deny → model retries → cooldown still absent → deny → …
```

— an unbounded block. Therefore:

> **Write the cooldown first, confirm it exists, and only then emit the denial.
> If the write fails, `exit 0` and allow the fetch.**

A gate that cannot record that it fired must not fire. This is the general rule,
not a patch: the denial and its own record land together or not at all.

### 4.6b C2 — deny-rate circuit breaker

`pre-edit-check.sh` gained a deny-rate circuit breaker in **v2.30.0** because
this class of deadlock happened in production: after **3 consecutive denials
with no intervening allowed call**, it degrades to allow-with-loud-warning
(per-session counter in `$TMPDIR/aria-r22-denies-<session_id>`; confirmed
working end-to-end 2026-07-06 — 3 denials → breaker tripped → subsequent writes
proceeded).

This is the plugin's **second denying PreToolUse hook** and adopts the same
mechanism, with its own counter at `$TMPDIR/aria-extfetch-denies-<session_id>`:

- 3 consecutive denials with no intervening allowed fetch → degrade to allow,
  and say so loudly in the reason text.
- Any allowed fetch resets the counter, restoring blocking enforcement.
- Self-healing under future harness changes, which is the point: C1 fixes the
  one deadlock cause now known; **C2 closes the class**, including causes not
  yet enumerated.

### 4.6c C3 — self-bound the runtime; do not rely on harness timeout semantics

The §3.5 timings were measured on **one machine, warm cache, a 223 MB corpus**.
A cold cache, a larger corpus, or a slower disk could exceed the 5 s
registration timeout — and **what a PreToolUse timeout does is undocumented
locally**: `reference_claude_code_hook_and_settings_facts` records measured
harness behaviour for settings-arming, classifier denials, `$defaults`,
prompt-hook limits, `systemMessage` vs `additionalContext`, and Stop-hook loop
protection, and is silent on this.

Rather than resolve the unknown, **remove the dependency on it** — the script
bounds its own work:

- Cap candidate stems at 4 (already in §4.2).
- Wrap each store's grep so it cannot exceed ~1 s.
- Exceeding the total budget → `exit 0`, silent.

This converts unknown-semantics risk into designed behaviour, and keeps holding
as the corpus grows.

### 4.7 Config

Parsed in `config.sh` following the established idiom exactly:

```sh
KT_EXTERNAL_FETCH_GATE=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" \
  | grep '^external_fetch_gate:' | sed 's/^external_fetch_gate: *//')
KT_EXTERNAL_FETCH_MAX_HITS=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" \
  | grep '^external_fetch_max_hits:' | sed 's/^external_fetch_max_hits: *//')
```

| Key | Values | Default |
|---|---|---|
| `external_fetch_gate` | `on` \| `off` | `off` |
| `external_fetch_max_hits` | integer | `8` |

Ships **default-off**, per the `preflight_gate` / `auto_prospect` /
`session_state` precedent. Surfaced in `/setup` Advanced Options — the v2.44.1
lesson was a wizard that wrote and validated keys it never offered, so both keys
must appear in the picker, not only in the writer.

### 4.8 Stopword list — inline, not a bundled file

The stopword list lives **inline in the hook script** as a shell variable, not as
a separate data file.

Checked first: `bin/` contains only `.sh` files and `template/` is the
user-copied knowledge-folder skeleton. Neither is a home for plugin-internal
data, and there is no `data/` convention — so shipping a file would mean
inventing one for ~51 words. Inline is strictly simpler: no path resolution, no
missing-file branch, and nothing that can go absent in a hook required to fail
open.

Content: the 51 measured dictionary collisions (`common`, `session`, `index`,
`key`, `space`, `field`, `head`, `body`, `size`, `style`, `text`, `card`, `gate`,
`medium`, `message`, `parent`, `schema`, `template`, `run`, `seen`, …) plus
common English filler. **No runtime dependency on `/usr/share/dict/words`** — a
macOS symlink to `web2`, not guaranteed on Linux.

The list is derived from one corpus, so it is a *floor*, not a complete set. A
stem that slips through produces one spurious denial, which the cooldown clears
on retry — a bounded, self-healing failure. This is the intended direction: the
cap in §4.4 is the primary noise defence, the stopword list is secondary.

---

## 5. Scope boundaries — stated, not discovered later

**`context7` is excluded.** The user's standing global rule is to always use it
for library documentation, even when the answer seems known. It answers *"what is
this library's API"*, not *"how did we do this here"*. Gating it would fight a
standing instruction, and it was not the tool in the failing case. One-line knob
if this proves wrong.

**A query with no vendor word stays silent.** *"how do I rotate a git
credential"* has nothing to key on. Host-keying fires on named surfaces only;
this hook is not a general-purpose recall system.

**The probes themselves are not gated.** In the recorded instance the waste began
with `ls-remote` and auth attempts, *before* any `WebFetch`. This catches the
second half of the sequence. Gating Bash probes is a separate, larger question
and is explicitly out of scope.

**It is an interrupt, not a verification.** The hook cannot confirm the
reference was read. The cooldown clears on the retry whether or not anything was
opened, so compliance stays voluntary — what changes is that the pointer arrives
at the moment of the fetch instead of living in a rule nobody consulted. AC1 and
AC2 prove the gate *fires and clears*; **no acceptance criterion proves behaviour
changed**, and none can. The honest claim is one round trip of friction plus a
list of paths. Whether that is enough is measurable only after live use — denial
→ read rate — and is deliberately not asserted here.

**It claims coverage, not currency.** "A local note exists" is not "the note is
still true." Reading it is step one, not the answer — and per
`a_capture_is_a_snapshot_not_current_state`, a recorded reference must still be
re-verified against live state before it is asserted as fact.

**Transcript dumps count as coverage — observed, not tuned away.** The live
smoke (2026-08-10) denied a `twilio.com` fetch on the strength of a single
`intake/pre-compact-captures/` file: a raw session transcript, not a curated
reference. Measured before deciding: that directory holds **2 files**, and the
ambient cap already bounds any surface to ≤8, so the damage is bounded and a
capture can legitimately hold the answer. **No exclusion added** — that would be
speculative tuning. **Revisit trigger:** if a denial's path list becomes
majority `logs/` or `intake/*captures*` in normal use. `logs/` is already 1,050
files and grows every prospect, so this is the ratio to watch.

**Only `archive/` is excluded from the knowledge grep.** The measurement also
excluded a Mike-specific `ditto-*` corpus; that is local noise, not a shipped
convention, so it is not encoded in the hook.

---

## 6. Acceptance criteria

Each is stated so a test can go red for the right reason.

| # | Criterion |
|---|---|
| AC1 | With the gate `on`, a `WebFetch` to a host with 1–8 local hits is **denied once**, and the reason names at least one matched path. |
| AC2 | The immediate retry of that same `WebFetch` **passes** (cooldown consumed). |
| AC3 | A `WebFetch` to a host with **0** local hits passes silently, first call. |
| AC4 | A `WebFetch` to a host with **> max_hits** local hits passes silently (ambient-host cap). |
| AC5 | A `WebSearch` whose query contains a stopword-only stem match (`postgres index bloat`) does not fire on `index`. |
| AC6 | A `WebSearch` for `bitbucket api token scopes` **is denied once** and names a bitbucket-bearing path. |
| AC7 | With the gate `off` (default), no call is ever denied. |
| AC8 | Malformed JSON payload, missing config, and absent knowledge folder each `exit 0` with no output. |
| AC9 | The emitted JSON is valid and uses `permissionDecision`/`permissionDecisionReason`, never `systemMessage`. |
| AC10 | Worst-case runtime (4-stem alternation over both stores) stays under the 5 s hook timeout. |
| AC11 | **(C1)** With the cooldown location unwritable, the call **passes** and no output is emitted — the denial and its record land together or not at all. |
| AC12 | **(C2)** Three consecutive denials with no intervening allowed fetch trip the breaker; the 4th call passes with a loud degraded-mode reason. One allowed fetch resets the counter and restores blocking. |
| AC13 | **(C3)** A corpus large enough to exceed the self-imposed runtime budget yields a silent pass — never a block, never a hang. |

**Negative controls required** (per `guard_scoped_to_the_wrong_unit`): AC3, AC4,
AC5 and AC7 are the assertions that prove the gate can stay quiet. Each must be
observed failing for the *right* reason before it is trusted — a hook that
`exit 0`s because of a typo'd path passes AC3 vacuously. AC8 must assert the
*absence of output*, not merely a zero exit.

---

## 7. Distribution

- **Claude-Code-canonical only.** Bash hook; no counterpart in
  codex / cursor / antigravity / cowork. Record as tracked-drift in
  `PORT-LEDGER.json`.
- **Version:** minor bump — a new config-key capability every user inherits via
  the `/setup` diff, per the `v2.35.0` `autonomy`-key and `v2.39.0`
  `planning_paths` precedents.
- **Gate B:** hook + config keys add no skill frontmatter, so the
  skill-discovery byte budget is unaffected. To be confirmed by `release.sh`,
  not assumed.

---

## 8. Open questions — resolved by `/prospect` 2026-08-09

Log: `knowledge/logs/prospect/2026-08-09-file-local-reference-before-external-fetch.md`
Verdict: **PROCEED-WITH-CHANGES.** Four assumptions sourced; **zero external
fetches required** — the local stores answered all four, which is the mechanism
this spec proposes, exercised on the spec itself.

| # | Question | Resolution |
|---|---|---|
| 1 | Is `deny` the right verb — does the reason even reach the model? | **✅ RESOLVED.** Verified three ways: `session-start-check.sh:218` states it; three hooks emit the shape and `test-r22-planning-paths.sh:43` asserts on it; and `pre-edit-check.sh` **denied the first `Write` of the prospecting session**, its reason reaching the model verbatim. Reproduction-then-confirm. |
| 2 | Does the timing hold on a cold cache / larger corpus? | **⚠ UNRESOLVED, and now moot.** No local source documents PreToolUse timeout semantics. Answered by **removing the dependency** — §4.6c bounds the script's own runtime. |
| 3 | Is `max_hits: 8` stable across corpora? | **OPEN — deliberately.** One corpus is one sample. Kept absolute for v1 because it is legible and adjustable; revisit if a second corpus disagrees. A relative cap is the fallback, not the default. |
| 4 | Is per-session-per-key cooldown the right granularity? | **CONFIRMED, with a bounded cost.** A research-heavy session touching N covered hosts pays up to N denials, one each. §4.6b's breaker caps the pathological case at 3. Accepted. |

**Two defects found and folded in** (§4.6a, §4.6b) — both from the same root:
the spec copied a precedent hook's *structure* without its *history*.

- **C1** — the cooldown idiom is safe in `pre-explore-codemap-check.sh` only
  because that hook is advisory; in a denying hook a failed write is an
  unbounded block.
- **C2** — `pre-edit-check.sh` gained a circuit breaker in v2.30.0 *because this
  already happened in production*; a second denying hook inherits the need.

Proposed novel pattern, pending approval:
**`second-instance-omits-hard-won-safety`** — the Nth instance of a mechanism
inherits the original's shape but not the safety machinery added after the
original failed. Detection cue: a component described as "mirrors `<existing>`"
whose spec is shorter than the existing component's current implementation.
Counter-discipline: diff the precedent's current code against its first commit —
whatever accumulated in between is scar tissue, and the new instance likely
needs it.
