# Design — check local references before fetching externally

**Date:** 2026-08-09
**Status:** Draft — pending `/prospect`
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
- **Absent** → write it, then emit:

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

**It claims coverage, not currency.** "A local note exists" is not "the note is
still true." Reading it is step one, not the answer — and per
`a_capture_is_a_snapshot_not_current_state`, a recorded reference must still be
re-verified against live state before it is asserted as fact.

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

## 8. Open questions for `/prospect`

1. Is `deny` the right decision verb, or does a denial of a *read-only* tool
   overreach? (`ask` was rejected as placing friction on the user;
   `additionalContext` was rejected as the intervention that already failed.)
2. Does the 4-word alternation cap hold its 2.32 s measurement on a cold cache,
   and on a corpus substantially larger than 223 MB?
3. `max_hits: 8` is derived from one corpus. Is it stable, or should the cap be
   relative (e.g. a percentile of the domain distribution) rather than absolute?
4. Is a per-session, per-key cooldown the right granularity — or should a single
   denial per session per *store* be enough, so a long session isn't gated
   repeatedly across many distinct hosts?
