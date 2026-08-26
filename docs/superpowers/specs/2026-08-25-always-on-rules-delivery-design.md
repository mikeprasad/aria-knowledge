# Always-On Rules Delivery — Design

**Date:** 2026-08-25
**Status:** GATED — gate 1 (`/prospect`) RUN 2026-08-25, verdict **PROCEED-WITH-CHANGES**.
All required amendments applied in the same session that ran the gate (§2.3 severity,
§4.2 two-hook rewrite, §4.2a deferral, §6 cost, §7 AC7+AC8, §8 OQ1 struck / OQ2 closed /
OQ4 added). Gate report: `knowledge/logs/prospect/2026-08-25-file-always-on-rules-delivery.md`.
**Awaiting: Mike's spec review → then the implementation plan → then gate 2. No code yet.**
**Scope:** `plugin-claude-code` only. Codex and Cowork mirror after this is verified.
**Measured at:** `plugin-claude-code` v2.46.5 (installed v2.46.4), Claude Code session `9936caf6`.

⛔ **AMENDED 2026-08-26 after implementation — the channel fix shipped and the rules still
do not arrive. `additionalContext` has an undocumented per-emission size cap; the 19,557-char
payload is delivered as a 2,000-char preview plus a file path, so 90% is discarded silently.
See §2.6 (measurement), §10 (channel inventory and the reopened decision). §8's question —
one hook or two — is downstream of this and is no longer the deciding one.**
Measured at installed **v2.47.0**, Claude Code 2.1.245, session `1e88dad7`.

---

## 1. Problem

A stock ARIA install writes `working-rules.md` (38 rules, 49 KB) and `user-rules.md`
into the knowledge folder, and **nothing ever delivers them to model context.**

Users report that their Claude does not follow ARIA's rules. The measured cause is not
weak compliance — it is non-delivery. Their sessions never receive the rules.

The maintainer's own workspace does not exhibit the symptom because he hand-built a
delivery layer the plugin does not ship:

| Always-on surface | Maintainer | Stock install |
|---|---|---|
| Root `CLAUDE.md` with inline rule citations | 23 citations | none |
| `@.claude/discipline-index.md` | 88 KB | none |
| `@.claude/project-index.md` | 243 KB | none |
| Path from context to `working-rules.md` | `CLAUDE.md:212` | none |
| U-rule titles in model context | (see §2 — also absent) | none |

`/setup` deliberately writes no `CLAUDE.md` pointer
(`skills/setup/SKILL.md:279`, "CLAUDE.md reference handling deferred to first-write").
That ADR is sound in its own terms and is revisited in §5.4, not overturned silently.

## 2. Evidence

### 2.1 The session-start channel does not reach the model — measured, two-sided

`bin/session-start-check.sh:428-431` emits `{"systemMessage": ...}`. Transcript records
from session `9936caf6` (`~/.claude/projects/-Users-mikeprasad-Projects/9936caf6-*.jsonl`):

| Arm | Hook | Field emitted | Transcript record | Reached model |
|---|---|---|---|---|
| Subject | ARIA `SessionStart` | `systemMessage` | `hook_system_message` (line 8, 9,124 ch) | **no** |
| Control 1 | ARIA `PreToolUse:Bash` | `additionalContext` | `hook_additional_context` (line 36) | yes |
| Control 2 | harness `SessionStart` | `additionalContext` | `hook_additional_context` (line 9) | yes |

**Control 2 is load-bearing.** Same hook event, same session, different field, opposite
outcome. It proves `SessionStart` + `additionalContext` reaches model context in this
Claude Code build, so the failure is the field and not the event. No remaining risk that
the target channel is silently dropped.

The hook itself is healthy: `exitCode 0`, `durationMs 1109`, `stdout` 9,150 ch.
This is a delivery failure, not a hook failure.

**Instrument note.** A naive `grep -c` for payload strings in the transcript returns
non-zero and reads as *present* — because this session's own conversation quoted those
strings. Only classification by record type discriminates. Any future verification of
this claim must classify, never count.

### 2.2 The plugin already knows the correct channel

`additionalContext` is used correctly in five other hooks: `post-edit-check.sh`,
`bash-cd-check.sh`, `post-compact-check.sh`, `post-push-retrospect-check.sh`,
`subagent-start-selfreport.sh`. `session-start-check.sh` is the sole `systemMessage`-only
emitter among the context-bearing hooks. This is a channel slip in one file.

### 2.3 A blocking enforcement has an invisible instruction

`bin/pre-edit-check.sh:362` returns `permissionDecision: "deny"` when the `[Rule 22]`
marker is absent above an Edit/Write. The only text instructing the model to emit that
marker is the RULE 22 ORDERING block inside the undelivered payload. On a stock install
the enforcement is live and its instruction is not.

**Severity: friction, not deadlock — corrected at gate 1.** An earlier draft of this
section implied a stock user's Claude is stuck. Sourced and falsified: `pre-edit-check.sh:358`
builds a `permissionDecisionReason` that names the exact marker format, states the ordering
requirement, and instructs "then retry the same tool call." Recovery is available after one
denial. The gap is real — the rule is learned by being blocked rather than by being told —
but it is friction, and the spec must not overstate it.

### 2.4 The needed artifact already exists for another runtime

`plugin-antigravity/rules/aria-rules.md` (6.8 KB) is a condensed always-on digest —
one explanatory line per rule, pointing at the full file for depth. Its own header reads
"Plugin-Bundled, Always-On … loads on every Antigravity session."

Census of all four ports: **antigravity ships it; claude-code, codex, and cowork do not.**
`plugin-claude-code/rules/` does not exist.

**The digest has already drifted:** it states "ARIA enforces 34 working rules" while
`working-rules.md` contains 38. It must be regenerated, not copied — and the drift is
itself evidence that a hand-maintained digest needs a mechanical gate (§4.1).

### 2.5 Payload composition

The 9,124-character payload is a mixture. Figures below are measured per block from the
live `hook_system_message` record, not estimated:

- **User-facing questions — 406 ch / ~100 tok.** Knowledge-audit overdue (183),
  config-audit due (85), ARIA-updated/run-`/setup` (138). These ask the human to authorize
  an action. Correctly `systemMessage`; they stay there.
- **Model directives — 8,718 ch / ~2,181 tok.** STANDING USER RULES (1,770), SESSION STATE
  (1,609), DECISION ROUTING (1,202), ARIA ACTIVE CONTEXT (895), TASK BUDGET (888), Project
  Picker (798), RULE 22 ORDERING (725), MEMORY PATHWAY (307), CODEMAP Found (287), INSIGHT
  CAPTURE (237). Useless to a human; these are the loss.

⚠ Those are the **maintainer's** figures. A stock install emits only a subset — see the
gate table in §4.2a, which is what determines this spec's unit boundary.

Therefore the fix is a **split**, not a channel flip. Moving the whole payload would put
audit nags into model context as noise.

### 2.6 The delivered payload is capped, and the cap is silent — measured 2026-08-26

Added after Unit 1 shipped and was installed. **The channel fix works and the feature does
not.** `bin/session-start-rules.sh` ran clean (exit 0, 19,743 ch stdout) and produced a real
`hook_additional_context` record. The harness then replaced the payload with a
`<persisted-output>` wrapper: a **2,000-character preview** plus a path to a file on disk.
The preview length is the constant `K5=2000`, read out of the Claude Code binary.

⚠ **Refinement, measured 2026-08-26: `K5=2000` is the BUDGET; the DELIVERED preview is 1,929 ch.**
The cut lands on a line boundary — the largest whole-line prefix under the budget — so the last
delivered character is the end of the `Rule 1` line at char 1,928, and file content at chars
1,990–2,010 is provably absent from context. ⚠ **And the harness counts CHARACTERS, not bytes:**
its own wrapper reads `19.1KB` = 19,557/1024, while the file is 19,813 B. A design sized against
the byte figure is 256 ch off. Size against characters.

| | |
|---|---|
| `additionalContext` emitted | 19,557 ch |
| Reached model context | 2,000 ch (**10%**) |
| Discarded | 17,557 ch |
| Numbered rules delivered | **2 of 38** |
| U-rule references delivered | **0 of 19** |
| `RULE 22 ORDERING` in context | **no** |

⭐ **Reproduced across FORTY-TWO sessions** — 42 distinct session directories, each holding
exactly one persisted payload, all byte-identical at 19,813 B, all stamped 2026-08-26 between
01:25 and 03:21, across both project dirs (`-Users-mikeprasad` 30, `-Users-mikeprasad-Projects`
12). Re-measured 2026-08-26; this read **nine** when the section was written and grew by normal
use, not by a new defect. Every session since the 01:14 install. Not a one-off.

⭐ **The cap is PER EMISSION, not per session.** In the same aggregate record, sibling strings
of 1,018 and 3,321 ch (the output-style plugin and superpowers) passed through **intact**
while only the 19,557-ch string was wrapped. Were the cap applied to the concatenation, all
three would have been wrapped together. This is what makes a multi-emission design possible
and what answers §8.1 in the opposite direction from its recommendation.

⚠ **Prevalence, for scale:** across 171 session directories and 285 `hook_additional_context`
samples, ARIA's digest is the **only** payload that trips the cap. Largest sibling delivered
whole: 3,321 ch.

⛔ **Consequence: §2.3 is not fixed.** `pre-edit-check.sh:362` still denies an Edit/Write
without a `[Rule 22]` marker, and the only text instructing the model to emit that marker is
still absent from model context. The channel changed; the outcome did not. In the maintainer's
workspace the symptom stays hidden because the project `CLAUDE.md` documents the marker
independently — the same masking §1 identifies.

✅ **Stated fairly, this is still a net gain:** delivered rule text went from **0 to 2,000
characters**. It is 10% of the intent, not a regression.

⚠ **Bound — the exact cap is unpinned.** Proven safe at 3,321 ch; proven truncating at
19,557 ch. Two probes at 12,000 and 16,385 ch returned whole, but they went through the
**Bash tool** consumer, not the hook consumer, and do not transfer. Recorded as a bracket,
not a number, so no design sizes itself against a figure measured on the wrong channel.

⛔ **And the bracket cannot be narrowed from history — measured 2026-08-26.** Across every
`tool-results/` file in all 171 session directories, the **smallest persisted output of any kind
is 19,813 B**; only two others exist under 30 KB (23,595 and 28,146), and all 42
`additionalContext` payloads are the identical 19,813 B. There has never been an emission between
3,321 and 19,557 ch. **The bracket is wide because no payload of intermediate size has ever
existed to be measured, not because a measurement failed** — so no amount of transcript
archaeology closes it. Only a purpose-built emission **on the hook channel** can.

⚑ **Instrument note, extending §2.1's.** A negative control run in this session returned
**1**, not 0, because the transcript already contained the command text that carried the
control string — the probe's own text defeated it. Classification by record type was
unaffected. §2.1's rule holds and widens: in transcript work, *your own instrument is part
of the corpus.*

## 3. Decision

Adopt **Option 3** (ruled by Mike, 2026-08-25): bundled rules digest delivered over
`additionalContext`, plus `PostCompact` re-injection, plus a `/setup` offer to write a
`CLAUDE.md` pointer.

Rejected alternatives, with the defect that removed each:

- **Title-index only (~900 tok).** Titles alone carry no reasoning. "Rule 13 — simplest
  solution wins" binds on its title; "Rule 35 — decision routing" does not. Rejected as
  insufficient for the rules that most need to bind.
- **Wholesale channel flip.** Pushes user-facing nags into model context and leaves the
  human with no startup surface at all. Defect named in §2.5.
- **`CLAUDE.md` pointer alone (no hook payload).** Requires per-repo setup, writes into
  git-tracked files teammates share, and does nothing for users who decline. Retained
  only as the persistence backstop in §4.4, never as the primary mechanism.

## 4. Design

Four components. Each is independently testable and independently revertible.

### 4.1 `plugin-claude-code/rules/aria-rules.md` — the digest

A new bundled file: one explanatory line per working rule, grouped by the four domains
already used in `working-rules.md` (Coding / Process / Meta / Behavioral Foundation),
followed by a pointer to the full file. Target ≤ 7 KB.

Authored by regenerating from `working-rules.md` at current HEAD (38 rules), using the
antigravity digest as the *format* precedent only. Its content is stale and its rule
count is wrong; it is a template, not a source.

**Drift gate.** Keyed on the set of rule NUMBERS, not a count — a count matches while the
membership differs, which is exactly how "34" survived four new rules.

⛔ **Corrected 2026-08-25 (found while writing the plan): this does NOT belong in
`bin/check-port-drift.sh`.** An earlier draft of this section said it did. That script is a
**cross-port hash ledger** — it answers "does antigravity's copy of file X match
claude-code's?" via `port_surface_paths()` and a JSON ledger — and `claude-code` is its
explicit baseline (`case "$1" in claude-code) : ;;  # baseline — version only, no
surfaces`). A within-port semantic check has no home there and would be off-pattern.

The gate belongs in the existing shell test suite: `tests/test-aria-rules-digest.sh`, run
by `tests/run.sh`, using the `assert_eq MSG EXPECTED ACTUAL` helper from
`tests/helpers.sh`. That is also the only home where AC3's mutation verification is
natural.

### 4.2 A second SessionStart hook — `bin/session-start-rules.sh` (NEW)

**Amended at gate 1. The original design emitted `systemMessage` and
`hookSpecificOutput.additionalContext` as sibling keys in one JSON. That mechanism has
zero precedent across all 30 `bin/*.sh` scripts and zero across the six live hook
emissions measured in session `9936caf6`. It is replaced, and OQ1 is struck rather than
deferred — the new design does not need it answered.**

Register a **second entry** in the existing `SessionStart` hooks array in
`.claude-plugin/plugin.json`, pointing at a new script `bin/session-start-rules.sh`.

- `session-start-check.sh` — **byte-unchanged.** Keeps emitting `systemMessage` with the
  audit/update nags. Zero regression risk to existing behavior.
- `session-start-rules.sh` — new. Emits `hookSpecificOutput.additionalContext` carrying:
  1. the contents of `rules/aria-rules.md` (§4.1),
  2. the generated U-rule title index (logic ported verbatim from
     `session-start-check.sh:411-427` — same two-tier shape, same `UR_N > 0` gate, same
     3,000-char overflow fallback),
  3. the RULE 22 ORDERING block, because it is a rule and its enforcement is live.

**Why two hooks rather than two fields.** Measured in session `9936caf6`: four
`SessionStart:startup` hooks ran concurrently — lines 3 and 4 emitting
`additionalContext` (the output-style plugin and the **superpowers** plugin), lines 5 and
7 emitting `systemMessage`. All four were honored, each on its own channel. Coexistence
at the *hook* level is therefore measured; coexistence at the *field* level is not.

This also buys three properties the single-script design lacked: the rules payload is
independently revertible (delete one array entry), independently testable, and cannot
regress the nag path because that script is not touched.

**Precedent worth naming.** The superpowers plugin solves the identical problem the
identical way: an always-on behavioral instruction set that must bind every session,
delivered at `SessionStart` via `additionalContext`. ARIA is the outlier here, not the
pioneer.

**Documentation warning.** The official hooks reference states that `SessionStart` does
not support `additionalContext`. That is **false for this build** and is falsified by the
two plugin hooks above. Do not "correct" this design back toward the documented shape
without re-measuring. Because that source was wrong on a checkable claim, no other claim
from it is relied on here.

### 4.2a Unit boundary — default-on ships now, opt-in ships later

**Redrawn 2026-08-25 on measured gate conditions (Mike's ruling, option 1).** An earlier
draft split on "rules vs workflow directives" — a taxonomy this spec invented. It also
said "seven directives" while listing **eight**. Both are corrected here: the boundary now
follows the one the code already draws, which is whether a block fires on a default install.

There are **eight** non-rule directives. Gate conditions read from `session-start-check.sh`
against defaults in `bin/config.sh:127-143`:

| Block | Fires on a stock install? | Gate | ~Tok |
|---|---|---|---:|
| RULE 22 ORDERING | **yes** | unconditional (`:218`) | 181 |
| TASK BUDGET (short variant) | **yes** | no statusline → `:241` branch | 93 |
| MEMORY PATHWAY | **yes** | unconditional (`:320`) | 76 |
| INSIGHT CAPTURE | **yes** | `auto_capture` default `true` | 59 |
| ARIA ACTIVE CONTEXT | after first `/index` | needs `index.md`; template ships none — see §4.5 | 223 |
| STANDING USER RULES | grows from 0 | template has 0 `### U` headers | 0→ |
| CODEMAP Found | no | no CODEMAPs exist yet | 71 |
| ARIA Project Picker | **no** | `projects_enabled` **false** AND `session_start_project_picker` **false** | 199 |
| SESSION STATE | **no** | `session_state` default **false** | 402 |
| DECISION ROUTING | **no** | `autonomy` default **`default`** → injects nothing | 300 |

**A stock install's entire undelivered payload is ~409 tokens** (~632 after `/index`),
against the maintainer's 2,281. The four largest directives are all opt-in and off.

**Unit 1** — every block a default install emits: the rules digest, RULE 22 ORDERING, the
U-rule index, TASK BUDGET (short variant), INSIGHT CAPTURE, MEMORY PATHWAY, ARIA ACTIVE
CONTEXT.

**Unit 2** — the four opt-in blocks: Project Picker, SESSION STATE, DECISION ROUTING,
CODEMAP. These reach only users who deliberately enabled them.

**Both units ship in this arc (Mike's ruling, 2026-08-25), as separate commits.** This
supersedes an earlier recommendation in this spec to defer Unit 2.

⚑ **Why separate commits satisfy `fix-bundling` and a single commit would not.** The
pattern's concern is *attribution* — "no clear primary fix; the bundle relies on
'one of these will work'." Its counter-discipline is one concern per commit, which is
exactly what is specified here, and the repo already has the precedent
(`atomic-commit-per-bug-enables-single-concern-reverts`). A per-block commit boundary
means a startup regression bisects to a single directive and reverts without touching the
others. Deferral was one way to buy attribution; commit granularity is a cheaper way that
does not leave known-broken delivery in place for the users who opted in.

**Commit boundaries (one concern each):**

1. `rules/aria-rules.md` digest + its drift gate (§4.1)
2. `bin/session-start-rules.sh` + `plugin.json` registration, Unit 1 payload (§4.2)
3. Unit 2 payload added to the same script (§4.2a)
4. `post-compact-check.sh` re-injection (§4.3)
5. `/setup` CLAUDE.md offer (§4.4)
6. `template/index.md` + ACTIVE CONTEXT gate tightening + `/setup` runs `/index` (§4.5b)

⛔ **Commit 3 excludes the TASK BUDGET long variant.** See the warning below: it is a
defect requiring rework, not a block requiring migration. Migrating it as written would
deliver an instruction the maintainer has repeatedly corrected. It stays on
`systemMessage` until rewritten, and that rewrite is not in this arc.

⚠ **TASK BUDGET has two variants and only the short one is in scope.** The long variant
(`:239`, fires when the status-line meter is installed) instructs the model to consult
usage figures before `/handoff`, `/wrapup`, or compaction — behavior the maintainer has
repeatedly corrected ("usage measurements are wrong, ignore them and proceed"). The short
variant (`:241`) says the opposite: *"Don't assume depletion or wrap up autonomously."*
Unit 1 ships the short variant only. **The long variant is a separate defect** — delivering
it as written would cause a corrected behavior — and must be re-examined before Unit 2,
not migrated as-is.

### 4.3 `post-compact-check.sh` — survive compaction

Append the digest and the U-rule index to the existing `additionalContext` emission.
This hook already uses the correct field, so the change is additive. Compaction is the
main way an always-on rule stops being always-on mid-session.

### 4.4 `/setup` — offer the `CLAUDE.md` pointer

Add an explicit, **default-no** prompt at the end of `/setup`, per repo, that shows the
exact block before writing and reports whether the target is git-tracked.

The block is a pointer, not a copy — roughly:

```markdown
## ARIA Rules
Working rules (38): `<knowledge>/rules/working-rules.md`
User rules: `<knowledge>/rules/user-rules.md`
Read either before acting on anything it plausibly covers.
```

This preserves what the §2 ADR was protecting (no surprise writes into shared repos, no
aspirational conventions, per-repo nuance) while giving users the one surface Claude Code
natively re-injects after `/compact`. §4.3 covers users who decline, so this is a
backstop and not a dependency.

### 4.5 Discoverability of the opt-in features, and the missing `index.md`

Two additions raised by Mike, 2026-08-25. Both were measured before speccing.

**4.5a — Setup options for the session and project features already exist. No new
prompts needed; verify presentation only.** Measured in `skills/setup/SKILL.md`: all five
relevant keys are prompted in Step 6 and written to the config block at `:300-340` —
`projects_enabled`, `projects_list`, `auto_load_project_context`,
`session_start_project_picker`, `session_state` (plus `session_stale_days`,
`session_state_tracked`, `autonomy`). Step 6 presents each with an explanation and Step 9
validates the written values.

So the gap is **not** a missing option. It is that all five default off, so a user who
accepts defaults never meets the features — and until this spec lands, would not benefit
if they did, because the directives were undeliverable anyway. Action for this unit:
**no new config keys.** Add one line to Step 6's session/project block noting that these
directives now reach the model, so enabling them has a visible effect. Anything beyond
that is a defaults question (§8 OQ5), not a delivery question.

**4.5b — Ship `index.md` in the template, and tighten the gate that reads it.** Three
coupled changes; none is correct alone.

Measured: `template/` scaffolds 15 entries and **no `index.md`**, `/setup` never creates
one and never invokes `/index`, and `setup/SKILL.md:466` already emits a doc link to
`../../index.md`. Meanwhile ARIA ACTIVE CONTEXT is gated on `[ -f "$INDEX_FILE" ]`
(`:247`). Consequences: a fresh install has a dangling link, and the whole active-context
capability is silent until the user independently discovers `/index`.

1. **Template ships an `index.md` skeleton** — the `## Tag Index` heading, the `## Other
   Tags` heading, and a one-line note that `/index` populates it. Fixes the dangling link,
   gives `/index` a target, and makes the tag system visible to someone reading their own
   knowledge folder for the first time.
2. **Tighten the ACTIVE CONTEXT gate** from "file exists" to "file exists **and** contains
   at least one `### ` tag header." Required, not optional: with (1) alone the gate would
   pass on day one and spend 223 tokens per session describing a matching procedure that
   cannot match anything, since the block needs ≥2 tag hits to act.
3. **`/setup` runs `/index` at the end** so the file is populated from whatever the user
   already has, rather than waiting on a second discovery step.

Together these close an ordering trap: today a user can promote knowledge and still get
nothing, because promotion and indexing are separate discoveries.

⚠ Change (2) alters existing behavior for **current** users whose `index.md` has zero tag
headers — they lose a directive they were never receiving anyway (it was on
`systemMessage`), so the observable change is nil. Worth stating so the diff is not
mistaken for a regression.

## 5. Non-goals

- Codex and Cowork ports. Same gap, deliberately deferred until claude-code is verified.
- Changing any rule's text.
- Making `working-rules.md` itself always-loaded. 49 KB is not a per-session cost worth
  paying; the digest plus on-demand reads is the two-tier shape already proven in the
  maintainer's own index.
- Retiring the `/rules` skill.

## 6. Cost

**Revised twice.** The first table estimated; these figures are measured per block from the
live payload (`hook_system_message`, session `9936caf6`), except the digest, which does not
exist yet.

⛔ **STALE AS OF 2026-08-26 — do not quote this table.** It models the digest at ~1,750 tok
and Unit 1 at ~2,824. As built, the emission is **19,557 ch ≈ 4,900 tok**, of which **~500
tok is delivered** and the rest discarded (§2.6). ⚑ The gap is a **unit mismatch, not an
error**: `rules/aria-rules.md` really is 11,960 ch / ~12 KB — the figure the maintainer ruled
on — but the hook wraps it with ~7,600 ch of other Unit-1 blocks, and the cap applies to the
**emission**, not the artifact. Re-derive both numbers from a live run before any sizing
decision, and say which unit each one measures.

| Unit 1 item | ~Tok | New spend? |
|---|---:|---|
| Rules digest (new artifact) | ~1,750 | **yes — genuinely new** |
| STANDING USER RULES index | 442 (0 for a new user) | no — re-channelled |
| RULE 22 ORDERING | 181 | no — re-channelled |
| ARIA ACTIVE CONTEXT | 223 (0 until `/index`) | no — re-channelled |
| TASK BUDGET (short variant only) | 93 | no — re-channelled |
| MEMORY PATHWAY | 76 | no — re-channelled |
| INSIGHT CAPTURE | 59 | no — re-channelled |
| **Unit 1 total, mature install** | **~2,824** | |
| **Unit 1 total, fresh install** | **~2,159** | |
| Unit 2 — SESSION STATE 402, DECISION ROUTING 300, Picker 199, CODEMAP 71 | 972 | no — re-channelled |
| **Both units, maintainer's config** | **~3,796** | |
| **Both units, fresh install** | **~2,159** | *(all 4 Unit-2 blocks are gated off)* |

Read honestly:

- **~1,750 of it is genuinely new** — the digest, paid every session including ones where
  no rule applies. That is the price of "always active"; no version of this avoids it.
- **The rest is not new spend.** Those characters are already generated and rendered
  today, addressed to a model, delivered to a human who cannot act on them. Re-channelling
  converts waste into effect.
- **For the users who reported the problem, the digest is ~81% of the gain** (1,750 of
  ~2,159). The other blocks matter, but they are not why a stock install ignores the rules.

## 7. Acceptance criteria

Each is falsifiable and names its own red condition. Verification instrument is the
transcript record classification validated in §2.1 — **classify by record type, never
count string occurrences.**

- **AC1** — A fresh session in a configured project produces a `hook_additional_context`
  record for `SessionStart` whose content includes **the LAST working-rule title in the
  digest** (not merely "at least one"). *Red when:* the `additionalContext` emission is
  reverted, **or the payload is truncated anywhere before its end.**
  ⛔ **AMENDED 2026-08-26. As originally written this AC passed while 90% of the payload was
  discarded** — a 2,000-char preview contains Rule 1, which satisfies "at least one" forever.
  Right threshold, wrong unit: the AC was written against a channel assumed lossless, so it
  could not fail for the one reason it now needs to. Asserting the *last* title makes
  truncation the failure it should always have been.
  ✅ **BUILT 2026-08-26** — `plugin-claude-code/tests/test-aria-rules-digest.sh`, 11 assertions
  appended: a positive control on the needle, a deterministic worst-case fixture proven to carry
  all six conditional blocks, a downward-only size ratchet at **20,322** normalised codepoints,
  and the last-rule-title check on both the minimal and worst-case paths. ⚠ **Named as a PROXY in
  the code:** it measures what the hook EMITS; the transcript-classification half of AC1 cannot
  run in a suite that never sees a transcript. Mutation record — M1 ceiling−1 → only the ratchet
  fires; M2 needle emptied → the control fires **while both last-title assertions stay green**,
  which is exactly why the control exists; M3 emission truncated before the escape step → both
  last-title assertions fire; M4 fixture loses `autonomy` → the DECISION ROUTING fixture assertion
  fires. ⚑ **Four of seven mutation attempts were unfaithful** (a no-op insert, a `sed` that never
  matched, and twice truncating a variable after its value had been copied out) — every one caught
  by proving the condition was created, none by re-reading. ⛔ **And the first version of the guard
  survived its own mutation:** it counted raw characters, and the payload interpolates the
  knowledge-folder path 3 times, so the total moved with the temp-dir path length (21,074 at a
  144-char path vs 20,942 at 100). `wc -m` was no better — under `LC_ALL=C` it counts bytes.
  The measure is now jq's literal string split, which is path- and locale-independent.
- **AC2** — That same session still produces a `hook_system_message` record containing
  the audit nags. *Red when:* the change is a move rather than a split. AC1 and AC2 must
  pass in the same session; either alone is satisfiable by the wrong implementation.
- **AC3** — The drift gate fails when a rule number present in `working-rules.md` is
  absent from the digest. *Red when:* mutated by deleting one rule line from the digest.
  Must be mutation-verified, not merely observed green.
- **AC4** — After `/compact`, a `hook_additional_context` record for `PostCompact`
  contains the digest. *Red when:* the `post-compact-check.sh` addition is reverted.
- **AC5** — `/setup` declined writes zero bytes to any `CLAUDE.md`. *Red when:* the
  default is flipped to yes. Verified two-sided: accepted writes exactly the block,
  declined writes nothing.
- **AC6** — With `user-rules.md` containing zero `### U` headers, no U-rule index is
  emitted on either channel. *Red when:* the `UR_N > 0` gate is removed. This is the
  brand-new-user case and is the current behavior; the AC pins it against regression.
- **AC7** (added at gate 1) — One session's transcript contains BOTH a
  `hook_additional_context` record originating from `session-start-rules.sh` AND a
  `hook_system_message` record originating from `session-start-check.sh`. *Red when:* the
  second hook entry is removed from `plugin.json`. This is what proves coexistence, and
  it tests the mechanism actually used rather than the one the documentation describes.
  Subsumes and replaces AC2's role as the split-not-move check.
- **AC8** (added at gate 1) — `session-start-check.sh` is byte-identical to its
  pre-change state. *Red when:* any edit lands in that file. This is the zero-regression
  guarantee that justifies the two-hook shape over editing the existing script.
  ✅ **AMENDED 2026-08-26 — ONE named exception, and the ruling predates this amendment.**
  AC8 now reads: *byte-identical except for the TASK BUDGET block reworked in `d31493c`
  (+13/−1).* No further edit to that file is permitted under this AC; a second exception
  requires re-opening AC8, not extending this clause.
  ⚑ This is **propagation, not a new decision**: `aria-knowledge/CLAUDE.md`'s v2.47.0 footer
  already records it verbatim — *"THE `TASK BUDGET` REWORK is the one deliberate AC8
  exception"* — with the reasoning (the long variant directed the model to gate its own
  stopping decisions on usage figures, a behaviour the maintainer has repeatedly corrected;
  it was harmless only while the channel was unread, so **delivering it verbatim would have
  caused it**). The spec's AC8 was simply never reconciled to that ruling, which is the
  drift class `adopted-with-revisions-must-propagate-to-authoritative-docs`.
  ⛔ **The stated verification command was ALSO wrong and is corrected.**
  `git diff --exit-code -- bin/session-start-check.sh` returns **0** here, because it compares
  the working tree to `HEAD` and the change is *committed* — so the AC's own check could not
  see its own violation. Verify against the arc's base:
  `git diff --exit-code origin/main HEAD -- plugin-claude-code/bin/session-start-check.sh`,
  and expect exactly the `d31493c` hunk.
  ⚠ **Pattern hit, and it named this in advance:**
  `acceptance-criterion-a-correct-implementation-cannot-satisfy` (canonical, first identified
  2026-07-30) calls out "byte-identical" by name as an absolute a *correct* implementation
  cannot meet when the intended change **is** a diff. An absolute AC needs a named exception
  list from the start, or a different phrasing.
- **AC9** (§4.5b) — `template/index.md` exists and contains a `## Tag Index` heading, and
  `setup/SKILL.md:466`'s `../../index.md` link resolves against a freshly scaffolded
  folder. *Red when:* the template file is removed.
- **AC10** (§4.5b) — Given an `index.md` with **zero** `### ` tag headers, the ARIA ACTIVE
  CONTEXT block is **not** emitted; given one with ≥1, it **is**. *Red when:* the gate is
  left as bare `[ -f "$INDEX_FILE" ]`. **Must be verified two-sided** — a one-sided check
  passes against the unfixed gate in the ≥1 case, which is exactly the vacuous form this
  spec's own §2.1 warns about.
- **AC11** (§4.5a) — A fresh `/setup` run writes all five session/project keys
  (`projects_enabled`, `auto_load_project_context`, `session_start_project_picker`,
  `session_state`, `autonomy`) to the config with their documented defaults. *Red when:*
  any key is dropped from the Step 6 block. This pins existing behavior against
  regression; it is not new work, and finding it already true is the expected result.

## 8. The end state, and the one measurement that decides it

⛔ **SUPERSEDED IN PRIORITY 2026-08-26 — read §10 first.** This section asks whether the two
hooks collapse into one. That is a machinery question, and it sits *downstream* of §2.6: with
the payload capped at 2,000 delivered characters, both the one-hook and two-hook shapes
deliver 10% of the rules. Nothing here is retracted — §8.1's reasoning still holds on its own
terms, and §8.2's recipe is corrected in place — but the deciding question is now **which
channel carries the full rule text at all**, not how many hooks emit it.

**Added 2026-08-26, ruled by Mike.** The two-hook design in §4.2 is a workaround for an
unverified capability, not the target architecture. Recording the target here so it is not
rediscovered.

### 8.1 Target: one hook, two channels, routed by audience

The principled decomposition is not *which code computes what* — it is **who each message
is addressed to**. That is a per-message property and belongs at the message, not at the
file:

- asks a **human** to authorize something (audit overdue, config due, run `/setup`) → `systemMessage`
- instructs the **model** (rules, Rule 22 ordering, SESSION state, decision routing, CODEMAP, active-context) → `hookSpecificOutput.additionalContext`

One script computes session-start state **once** and routes each message. `session-start-rules.sh`
is deleted; `session-start-check.sh` becomes the single emitter.

Why one beats two, measured rather than argued:

- **One computation pass.** Two hooks that each compute CODEMAP staleness run
  `find -maxdepth 2` plus per-file `grep`/`stat`/`date` twice per session.
- **One ledger interaction per trigger.** See §8.3 — this is the concrete hazard.
- **No drift surface.** The ~70 lines of staleness logic exist once.
- **Rule 13.** Two files plus five shared helper dependencies is more machinery than the
  problem needs.

⚠ The arguments originally made *for* two hooks do not survive scrutiny and are retracted
here: "independently revertible" (reverting a field is no harder than reverting an array
entry) and "the nag path cannot regress" (that safety comes from the tests, not from file
separation).

### 8.2 The deciding measurement — dual-field emission

Everything above is conditional on **OQ1**, struck at gate 1 as dissolved: *can one hook
emit `systemMessage` and `hookSpecificOutput` in the same JSON and have both honoured?*
Still unverified, still zero in-repo precedent, and now the deciding question.

⛔ **Do not resolve this from documentation.** The hooks reference was falsified on a
checkable claim during gate 1 (it states `SessionStart` does not support
`additionalContext`, which two plugin hooks in the same session demonstrably do), so every
claim from that source is unsourced — see pattern
`source-discredited-on-one-claim-still-cited-on-another`.

**Recipe** — cannot be run from the session that writes the hook, because hooks arm at
session start:

1. Make one hook emit both fields in a single JSON object.
2. Start a **fresh** session in a configured project.
3. Locate that session's transcript by a unique string from it:
   `(cd ~/.claude/projects/<project-dir> && /usr/bin/grep -l "<unique phrase>" *.jsonl)`
4. Classify its hook records — **classify by record type, never count string occurrences**;
   the session's own conversation will contain the payload strings and a count inverts the
   answer:
   ```bash
   python3 -c "
   import json,sys
   for i,l in enumerate(open(sys.argv[1])):
       try: d=json.loads(l)
       except: continue
       a=d.get('attachment') or {}
       if isinstance(a,dict) and str(a.get('type','')).startswith('hook_'):
           print(i, a.get('type'), a.get('hookName'))
   " <transcript>.jsonl
   ```
5. ~~**Pass:** both a `hook_system_message` and a `hook_additional_context` record appear
   with the **same `hookName`**.~~ ⛔ **THIS DISCRIMINATOR IS UNSATISFIABLE — corrected
   2026-08-26 by measurement, before the recipe was ever run.** In this build the
   `hook_additional_context` record is a **per-session aggregate**: exactly one record, a
   generic `hookName` of `SessionStart`, and a `content` **list** holding one string per
   contributing hook. `hook_system_message` records are per-hook, named
   `SessionStart:startup`. The two names therefore can never match, however the hook is
   written.
   ✅ **Corrected pass criterion:** the aggregate record's content list contains the
   dual-emitter's payload string, **and** a `hook_system_message` record bearing that
   hook's name also appears. Trace each back to its `hook_success` record (which carries
   the `command`) rather than trusting `hookName` alone.
   ⚠ **And step 1 was never done:** measured 2026-08-26, `session-start-rules.sh` emits only
   `hookSpecificOutput` and `session-start-check.sh` only `systemMessage`. No hook emits both,
   so OQ1 remains unanswered and this recipe cannot be run until one does.

**If it passes** → collapse per §8.1, re-baseline AC8 against the merged file.
**If it fails** → the two-hook split is forced. The correct shape is then a shared
`lib-session-start.sh` computing once and exposing `SS_USER_MESSAGES` /
`SS_MODEL_MESSAGES`, with the ledger write assigned to exactly one emitter. Strictly more
machinery for the same outcome, but correct.

### 8.3 Why two Unit-2 blocks were not copied

Task 3 shipped only the two pure-text directives (SESSION STATE, DECISION ROUTING). The
other two stay in `session-start-check.sh` until the collapse:

- **Tracked artifacts** records to the session ledger. ⚠ Multiple callers of
  `kt_artifact_record_ledger` are the **design** — three hooks already call it on different
  triggers, and `kt_artifact_filter_ledger` dedups before each records. The hazard is
  specific to a *second hook on the same trigger*: whichever runs first records the paths,
  the second filters them out and emits nothing, so **which channel receives the directive
  depends on hook execution order**, silently and with no error. (An earlier draft of this
  spec called it a ledger double-write. That was wrong; the dedup filter prevents
  corruption and produces a race instead.)
- **CODEMAP staleness** is ~70 lines of `find`/`stat`/`date` logic that would drift between
  two copies.

Neither is fixed by copying. Both are dissolved by §8.1.

⚠ **Consequence accepted by Mike, 2026-08-26:** the CODEMAP directive stays undelivered
until the collapse.

## 9. Open questions

- ~~**OQ1** — Does Claude Code honor `systemMessage` and `hookSpecificOutput` together in
  one hook JSON?~~ **STRUCK at gate 1 — dissolved, not deferred.** The two-hook design
  (§4.2) does not need it answered. Recorded because the answer is still unknown: if a
  future change reaches for dual-field emission, it is unverified and has no in-repo
  precedent.
- ~~**OQ2** — Is `permissionDecisionReason` instructive enough to recover after one
  denial?~~ **CLOSED at gate 1 — YES.** Sourced from `pre-edit-check.sh:358`; §2.3
  downgraded from deadlock to friction accordingly.
- **OQ3** — Should the digest be bundled-static (authored, gated) or generated at
  runtime from `working-rules.md`? This spec chooses bundled-static because the
  explanatory line per rule cannot be derived from a heading. The drift gate is what
  makes that choice safe; if the gate proves unreliable, revisit. **Still open** — but it
  is a settled default with a named revisit trigger, not a blocker.
- **OQ5** (new, 2026-08-25, §4.5a) — Should any of the five session/project features
  default **on** for new users? Measured: `projects_enabled`, `auto_load_project_context`,
  `session_start_project_picker`, `session_state` all default `false` and `autonomy`
  defaults `default` (injects nothing), so a stock install runs a markedly quieter ARIA
  than the maintainer's — most of the session-lifecycle behavior is opt-in and plausibly
  undiscovered. **Explicitly out of scope for this unit:** it is a product/defaults
  decision, not a delivery defect, and changing a default alters behavior for every
  existing user on upgrade. Recorded so the observation is not lost now that delivery is
  fixed and enabling them finally has an effect.
- **OQ4** (new, gate 1) — Is root `CLAUDE.md` genuinely the only surface Claude Code
  re-injects after `/compact`? Recorded in workspace notes, not measured. Unmeasurable in
  a session that has not compacted. Affects how much §4.4 is worth, not whether it works;
  §4.3 covers persistence regardless, so a wrong premise costs a redundant pointer.

## 10. The channel inventory, and the decision §2.6 reopens

**Added 2026-08-26.** §2.6 establishes that the hook channel cannot carry 19,557 characters.
This section enumerates every always-on channel Claude Code actually has, measured, so the
design choice is made against evidence rather than preference.

### 10.1 What each channel is proven to carry

| Channel | Always-on | Largest size **proven** | Zero user action on a stock install |
|---|---|---|---|
| Hook `additionalContext` | yes | **3,321 ch** (19,557 → cut to 2,000) | **yes** |
| `~/.claude/rules/*.md`, no `paths:` | yes, every project | **32,056 B — measured, probe C** | no — one write to user config |
| `<project>/.claude/rules/*.md` + `paths:` | only on a matching file read | 10,596 B | no |
| `CLAUDE.md` + `@import` | yes | **261,442 B** | no — writes the user's repo |
| `claudeMd` settings key | **no — inert at user scope** | **0 B — measured, probe B** | n/a |
| Plugin `rules/` directory | **not loaded** | — | — |
| Plugin `output-style` | yes | — | yes, but only one style can be active |

Two measured negatives, both worth keeping so they are not re-litigated:

- ⛔ **Plugin `rules/` directories are not read as instructions.** The plugin already ships
  `rules/aria-rules.md` (11,960 ch) and it appears in **0 of 4,129** lines of
  `~/.claude/instructions-loaded.log`. Corroborated by the documented plugin component list —
  `skills, agents, hooks, mcp, lsp, output-style, channel` — which has no rules or
  instructions component. **A plugin cannot ship always-on instruction text.** That single
  fact is why the hook was reached for in the first place, and it is the real constraint.
- ⛔ **`claudeMd` would have been ideal and is now MEASURED out of reach — probe B, 2026-08-26.**
  It injects CLAUDE.md-formatted instructions with no physical file, but is honoured only in the
  managed and policy settings layers, which a plugin cannot and must not write. This bullet
  previously read *"documented, not measured"* and asked for one empirical test, on the grounds
  that this arc had already caught the same doc set wrong once. **The test was run and the docs
  are right this time:** a top-level `"claudeMd"` string carrying the sentinel `PROBE-B-QX7K` was
  written to `~/.claude/settings.json`, the next session started, and the sentinel is absent from
  model context. ⚠ **It fails SILENTLY** — no warning, no error, no log line; the key is simply
  ignored, which is why documentation was the only available evidence for so long. ⭐ **The result
  is interpretable only because probe A was live in the SAME session:** probe A's file arrived in
  full through the user-scope config channel, proving that channel was working and that this
  context genuinely receives user config content — so probe B's absence is attributable to the key
  rather than to a dead session. **A negative result needs a positive control in the same arm.**

### 10.2 The compressibility measurement

The digest is not irreducible. Measured over `rules/aria-rules.md`:

| Slice | Chars |
|---|---:|
| All 38 rule **titles** | 1,693 |
| Titles + `Rule N — ` prefixes | **~2,149** |
| Rule **bodies** (elaboration past the title) | 9,411 (247 avg/rule) |
| Non-rule prose (preamble, tiers, foundation) | 2,549 |

⭐ **A complete trigger index of all 38 rules fits in a single emission**, inside the envelope
already proven safe. 79% of the rule text is elaboration beyond the title.

⚠ **But a title is not always a sufficient trigger.** For judgment rules ("Rule 11 —
Popularity is not validation") it is. For rules whose content *is* a literal instruction — the
`[Rule 22]` marker format and its ordering requirement — the text itself must be present, or
the blocking hook at `pre-edit-check.sh:362` denies with no instruction available. That is the
line the design must be drawn on: **not size, but what breaks when the text is absent.**

### 10.3 Four candidate designs

- **W — one emission, titles only** (~2,149 ch). Zero user action, nothing to configure.
  ⛔ Rejected: drops the literal `[Rule 22]` text, so it fails the one thing that must not fail.
- **X — all 38 titles plus the procedural blocks verbatim** (~3,500 ch). Zero user action;
  every rule triggered; the damage-preventing text present verbatim.
  ⛔ **CORRECTED 2026-08-26 — there is no zero-machinery split.** This entry read *"two or three
  emissions … split into ~1,750-ch emissions … roughly 5× margin"*, silently assuming one hook can
  contribute several emissions. It cannot: `bin/session-start-rules.sh:165` is a single `printf` of
  a single JSON object with a single `additionalContext` field, and §2.6's per-emission evidence is
  **siblings from different plugins**, not several records from one script. So the split form needs
  2–3 **hook entries** and is small-N **Y**, not a cheaper X. The implementable one-hook X is **one
  emission**, and at ~2,972 ch its margin under the only figure measured on this channel (3,321 ch)
  is **349 ch / 11.7%** — a measured margin on the right channel, but an order of magnitude tighter
  than the retracted 5×. Size it against characters, and guard it.
- **Y — N emissions carrying the full 19,557 ch** (~7 hooks × ~2,800). Zero user action and
  **nothing lost at all**; the per-emission finding in §2.6 is what makes it possible. Costs
  seven process spawns at session start, seven plugin entries, and a Rule 13 objection — and
  its correctness still rests on an undocumented number.
- **Z — a file channel**: `~/.claude/rules/aria-rules.md` (user scope, never touches a shared
  repo) or the `CLAUDE.md` `@`-import (proven at 261 KB). Full fidelity, **and the only option
  that does not depend on an undocumented cap at all.** Costs a user file write, so it cannot
  be the default for every install.

### 10.4 Recommendation

⛔ **RULED 2026-08-26 (Mike): the file channel is `~/.claude/rules/`, not the `CLAUDE.md`
`@`-import.** Verbatim: *"A i prefer rules"*. Chosen with the trade stated — the rules channel
was proven only to 13,101 B against an `@`-import proven to 261,442 B, so it accepts one probe
session in exchange for never writing the user's repo. Probe C is armed for that (§10.5).
⛔ **And the architecture changed with it — see §10.7. The four designs in §10.3 all assume one
channel wins; the measurement says the emission is 61% static / 39% computed, so the split is by
MUTABILITY, not by audience (§8.1) or fidelity (§10.3).** The text below predates that finding
and is kept as the reasoning that led to it.


**X as the floor, Z as the ceiling, and a loud guard as the thing that makes either durable.**

X guarantees that every user, with zero setup, receives a trigger for all 38 rules and the
verbatim text of the rules whose absence breaks a tool call. Z gives full fidelity to anyone
who opts in, and is the only channel immune to the cap. Y is a legitimate alternative if
"zero setup, zero loss" outranks machinery — it is not rejected, it is a different trade.

⛔ **The guard is the durable part, and it matters more than the channel choice.** This defect
ran undetected for nine sessions because truncation emits no error. A test asserting the
emitted payload stays under a hard ceiling turns future growth into a red build instead of a
silent 90% loss — and AC1 (§7, amended) must assert the *last* rule title so truncation cannot
pass. Any channel can be undone by a payload that grows; only the guard prevents recurrence.

### 10.6 The file channel reaches subagents; the hook channel does not

**Added 2026-08-26, from a subagent dispatched to report its own context.** This was not a
planned measurement — it fell out of an attempt to read probe A without a fresh session — and
it is the strongest argument for a file channel yet found.

| Surface | Present in a subagent's context? |
|---|---|
| `~/.claude/rules/*.md` (user-scope, no `paths:`) | **yes** |
| Project `CLAUDE.md` + both `@`-imports (~240 KB) | **yes, in full** |
| `MEMORY.md` | yes |
| Hook-delivered `additionalContext` (ARIA's digest, the output-style text, superpowers) | **no** |

⛔ **Consequence: ARIA's rules currently reach subagents NOT AT ALL** — not the 2,000 chars
that survive the cap, not any of it. Every delegated agent runs with zero ARIA rules. Under a
file channel (option Z) they would reach the main session *and* every subagent, in full. Option
X's single emission fixes the main session only.

⭐ Independent corroboration for Z's size claim: the subagent described `project-index.md` as
"the largest single block in my context", consistent with ~240 KB — a **second** context, assembled
separately from this session's, carrying that payload without truncation.

⚠ **Evidential bound, stated because the two halves are not equally strong.** The *positive*
half is proven: the agent reproduced `context7.md` verbatim, and that text appears in **none** of
its logged transcript records, so it can only have come from its system prompt. The *negative*
half — that the probe and the hook payload were absent — is the agent's **self-report**, because
subagent transcripts do not log system prompts, so a record-classification pass cannot see the
surface in question. The control firing is what makes the self-report credible; it is not a
substitute for classification. Re-derive from a fresh session if a decision rests on it.

⚑ Mechanism, now measured from a second context: the instruction-file **set is snapshotted at
session start** and re-delivered to subagents from that snapshot — so a rules file created
mid-session reaches neither the creating session nor any subagent it spawns. That is why probe A
requires a genuinely new session and cannot be closed by delegation.

### 10.7 The cap is per-tool and remotely mutable — read out of the binary, 2026-08-26

**This is the finding that explains why the arc did not converge for three sessions: it was
trying to pin a number that is not a constant.**

Read from the live binary — `/Users/mikeprasad/.local/share/claude/versions/2.1.245`, a
Bun-compiled executable with the transpiled JS embedded. ⚠ The `cli.js` at
`/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code` is **2.0.8**, from October, and
reading it would have been the same wrong-unit error a third time.

```js
function Rae(e, t, n = Cae, r = !1) {      // e=toolName  t=maxResultSizeChars  n=ceiling
  if (!Number.isFinite(t)) return t;
  if (r) return Math.min(t, n);
  let s = Me(Byo, {})?.[e];                 // Byo = "tengu_velvet_ibis", map keyed by TOOL NAME
  if (typeof s === "number" && Number.isFinite(s) && s > 0) return s;
  return Math.min(t, n);
}
```

| Fact | Status |
|---|---|
| `K5 = 2000` (preview length) | ✅ **confirmed** — §2.6 was right |
| `V5 = "<persisted-output>"`, `vrt = "</persisted-output>"` | ✅ confirmed |
| `threshold = min(tool.maxResultSizeChars, ceiling)` | ✅ measured |
| override map keyed by **tool name**, gate `"tengu_velvet_ibis"` | ✅ measured |
| that gate is **server-side**, so the cap is remotely mutable | ⚠ **strong inference, not measured** |

The inference is labelled because it is load-bearing. Basis: `tengu_*` is this binary's
gate/telemetry namespace throughout (`Dt("tengu_coral_beacon", !1)`,
`U("tengu_tool_result_persisted", …)`) and no settings-key spelling for it exists. A gate fetch
was **not** observed.

⛔ **Three consequences, and the third ends the "find the cap" line of work:**

1. **The threshold is per-tool.** This is *structural* confirmation of §2.6's "the Bash-tool
   probes do not transfer" — not merely an empirical coincidence. Corroborated in-session: a
   26,389 B Bash tool result came back whole while a 19,557 ch hook payload was wrapped, so the
   two consumers demonstrably differ by more than 6,800 characters in the same session.
2. **`tengu_velvet_ibis` is not a lever.** It is a gate name, not a settings key — there is
   nothing a plugin or a user can set.
3. ⛔ **No payload may be sized against the cap, and locating it exactly would not make a hook
   design safe.** X, Y, and the "split by mutability" hook half all rest on a value that can
   change with no client release and no signal. **Stop sizing against it. Put everything that
   can be static on the file channel, and make the hook half degradation-tolerant rather than
   cap-fitted** — i.e. the file carries the *behaviour* and the hook carries only the resolved
   *values*, so a truncated hook payload is no longer damaging.

⭐ **The composition measurement that makes the split possible.** The emission is assembled at
`bin/session-start-rules.sh:35-39` — `cat` the static digest, then append generated blocks:

| | Chars | A static file can carry it? |
|---|---:|---|
| Static digest (`rules/aria-rules.md`, 38 rules + prose) | 11,960 | ✅ **12,166 B, under probe C's proven 32,056 B — 2.6× headroom** |
| Generated blocks (`RULE 22 ORDERING`, `DECISION ROUTING`, `SESSION STATE`, `TASK BUDGET`, `ARIA ACTIVE CONTEXT`, `STANDING USER RULES`) | 7,598 | ❌ **no** — each is computed from config or project state |
| **Emitted total** | **19,557** | |

⛔ **So option Z is NOT a superset of the hook channel** — a file written once is identical in
every project and cannot carry a block whose content depends on `autonomy`, `session_state`, the
project's tag index, or `user-rules.md`.

⚑ **A correction worth keeping, because it is the same error twice in one session.** This spec
was told at one point that "Z at full digest size is unproven by 51%". That was wrong: it compared
probe A's 13,101 B capacity against the *hook's composed* 19,813 B emission, when a file would
carry only the 12,166 B static digest. Same wrong-unit shape as probe A itself
(`feedback_guard_scoped_to_the_wrong_unit`), committed in the same session that named the pattern.

⚠ **Worst case, measured deterministically for the guard:** with every conditional block on and
the U-rule index at the hook's own internal 3,000-ch branch point, the emission is **20,322
codepoints** (path- and locale-normalised). That is **6.1× the 3,321 ch** that is the only size
measured to cross this channel intact.

### 10.8 The split, measured per block — the architecture probe C unblocks

**Added 2026-08-26 (second session), after probe C closed the channel question.** §10.7 ruled the
split by MUTABILITY and stated the principle — the file carries the behaviour, the hook carries only
the resolved values. This section measures it per block and turns it into an implementable shape.
Every figure is measured from a worst-case run of `bin/session-start-rules.sh` unless labelled an
estimate: 40 U-rules, an `index.md` with tag headers, `autonomy: autonomous`, `session_state: true`,
path-normalised exactly as the delivery guard normalises.

| Block | Chars | Text a literal? | What varies at runtime | Destination |
|---|---:|---|---|---|
| Rules digest + preamble | 12,059 | ✅ a `cat` of a file | nothing | **file** |
| RULE 22 ORDERING | 711 | ✅ | nothing — unconditional | **file** |
| MEMORY PATHWAY | 321 | ✅ | nothing — unconditional | **file** |
| TASK BUDGET | 751 | ✅ (2 variants) | which variant — a `$HOME` file's existence | **file**, condition is model-visible |
| INSIGHT CAPTURE | 195 | ✅ | gate `auto_capture`; interpolates KF | **file + config value** |
| ARIA ACTIVE CONTEXT | 864 | ✅ | gate `active_surfacing` + index state; interpolates KF | **file + config value** |
| SESSION STATE | 1,610 | ✅ | gate `session_state` | **file + config value** |
| DECISION ROUTING | 1,202 | ✅ (2 variants) | gate `autonomy` | **file + config value** |
| STANDING USER RULES | 2,610 | ❌ **generated from the user's own file** | the titles themselves | **second file** — below |
| **Total** | **20,322** | | | |

⭐ **The finding that reframes §10.7's "39% computed": exactly ONE block is genuinely computed.**
Every other block is a shell literal whose *gate* is computed, not whose *text* is. **17,712 of the
20,322 chars (87.2%) are static text a bundled file can carry verbatim**; what the hook actually
contributes is a handful of boolean and enum decisions. The 61/39 figure understated the file's
reach by 26 points because it counted a block as computed whenever its *emission* was conditional —
a wrong-unit read of the same shape this spec has now made three times, and the reason to state the
axis explicitly: **conditional emission is not computed content.**

**So a static file CAN carry conditional behaviour**, by stating the condition for the model to
evaluate instead of resolving it in shell. Two mechanisms, both needed:

- **Model-visible conditions become stated conditionals, with no hook involvement at all.** TASK
  BUDGET branches on whether `~/.claude/aria-statusline-state-*.json` exists — something the model
  can determine for itself. The file carries both variants behind one sentence naming the condition.
- **Config-visible conditions need one resolved value each.** `autonomy`, `session_state`,
  `auto_capture`, `active_surfacing` and the knowledge-folder path live in
  `~/.claude/aria-knowledge.local.md`, which the model has no reason to have read. The file carries
  every variant keyed by value; the hook emits the values.

⛔ **The file must carry EVERY variant where the emission carries one.** Measured directive
literals, all variants, before shell substitution: RULE 22 **709** · MEMORY PATHWAY **319** · TASK
BUDGET **739 + 346** · INSIGHT CAPTURE **211** · ARIA ACTIVE CONTEXT **881** · SESSION STATE
**1,608** · DECISION ROUTING **763** (balanced) **+ 1,201** (autonomous) = **6,777 ch**. With the
12,166 B digest that is a **measured floor of 18,943 B** for the file, before a word of conditional
framing prose is written.

#### The U-rule index cannot stay in the hook — forced by measurement, not preferred

`session-start-rules.sh:62` bounds the inline index at **3,000 chars of titles** before falling back
to a 171-char pointer. So that block's own ceiling is ~3,000 plus the ~277-char substituted template
= **~3,277 ch**, and a hook carrying it alongside a config block (~250 ch, estimate) lands at
**~3,527 ch — above the 3,321 ch that is the only size ever measured to cross this channel intact.**

⇒ The generated index must reach a file too, as a **second, generated** user-scope rules file
`~/.claude/rules/aria-user-rules.md`. ⚑ **Note the shape of that conclusion: it was not chosen, it
was forced by two independently measured numbers meeting.** The 3,000-char branch point has been in
the code since the block was ported and the 3,321-char figure since §2.6; neither was written with
the other in view. Keeping the index in the hook would leave the post-split payload over the only
proven-safe figure — i.e. the split would fail at the one thing it exists to fix.

#### The resulting three surfaces

| Surface | Carries | Changes when | Worst case | Reaches subagents |
|---|---|---|---:|---|
| `~/.claude/rules/aria-rules.md` — bundled, **byte-identical for every install** | digest + all 8 directives, every variant, gates as stated conditionals | a plugin release | **18,943 B measured** + framing | ✅ |
| `~/.claude/rules/aria-user-rules.md` — **generated** | the U-rule title index | the user edits `user-rules.md` | ~3,277 ch | ✅ |
| SessionStart `additionalContext` | **resolved config values only** | every session | **~250 ch (estimate)** | ❌ |

**Hook payload 20,322 → ~250 ch, a 98.8% reduction.** ⛔ **The margin is not the justification and
must never be quoted as one.** Per §10.7 the cap is per-tool and remotely mutable; what makes this
design safe is that a truncated hook now costs only *which posture is selected*, and the file states
the safe default for exactly that case — *"if no autonomy value is present, treat it as `default`,
which adds no routing directive."* Degradation-tolerant, not cap-fitted. No amount of headroom would
have bought that property.

⭐ **Aggregate capacity is proven too, and probe C is what proved it — unplanned.** Probe C did not
run alone: `context7.md` (2,338 B) was live in the same session and arrived whole, its last line on
disk (`4. Answer from the fetched docs.`) being the last line that reached context. So the channel is
proven at **34,394 B across two files**, not merely 32,056 B in one. The two-file design needs
~22,220 B aggregate — inside a figure that has been measured rather than extrapolated from a
single-file result, which matters because nothing here may be sized against an extrapolation.

#### One fork that is a judgment call, and one that is not

⛔ **Not a fork — `/setup` must NOT bake resolved config values into the file.** It has a provable
defect: a user who later edits `autonomy` or `session_state` would get no effect and no error, which
is precisely the failure class this whole arc exists to fix. The file stays generic; the hook stays
the source of resolved values. Named here in one line rather than offered as an option, per U18.

⏳ **A real fork — what regenerates `aria-user-rules.md`, and when.** Per §10.6 a rules file written
mid-session reaches neither that session nor its subagents, so **every option carries a one-session
lag** and the question is only which trigger is least surprising:

1. `/setup` and `/rules` regenerate it. Explicit and simple; silently stale between runs.
2. A `PostToolUse` hook on writes to `user-rules.md` regenerates it. Event-driven, matches the
   `MEMORY-FULL.md` precedent already live in this workspace, and the one-session lag is
   attributable by the user to the edit they just made.
3. The SessionStart hook rewrites it every session. Self-healing, but writes user config on every
   launch and still lags one session.

Recommendation is **(2), with (1) as a manual repair path**. None of the three is provably wrong, so
this is Mike's call, not a decidable fork.

#### ⛔ A defect in the delivery guard, found while measuring for this section

The worst-case fixture in `tests/test-aria-rules-digest.sh` is **environment-dependent**, in exactly
the way its own comment forbids. It builds the knowledge folder synthetically — *"never the
developer's real knowledge folder, which would make the ceiling environment-dependent"* — but
`session-start-rules.sh:83` also branches on `ls "$HOME"/.claude/aria-statusline-state-*.json`, and
the fixture does not control `$HOME`. Measured two-sided in one session:

| `$HOME` | TASK BUDGET variant | worst-case payload |
|---|---|---:|
| the maintainer's real home (statusline meter installed) | **long** | **20,322** ch |
| an empty home | short | **19,919** ch |

**403 chars of the ratchet are environmental.** It does not false-fail today — 19,919 ≤ 20,322 — but
the ratchet is meant to be *lowered* as this split lands, and lowering it to a value measured on a
statusline-free machine makes it fail on the maintainer's. ⚑ The fixture's own maximality proof
covers the U-rule variant (*"worst-case fixture fires the LONG U-rule variant"*) and not this one,
so the guard asserts a bound it has not proven maximal — `feedback_guard_scoped_to_the_wrong_unit`,
inside the guard written to prevent that class. Fix belongs with the ratchet change, not separately:
both edit the same assertions, and doing them apart means touching one line twice.

### 10.5 Open, and how it gets closed

- ✅ **The user-scope rules channel holds 13,101 B — probe A READ 2026-08-26, all eight sentinels
  present including the tail at 13,051.** Both probes are now removed and the tree is clean,
  verified with a working positive control so the sentinel absence is a real absence and not a
  dead grep. This raises the §10.1 proven figure for that channel from 2,338 B to **13,101 B, a
  5.6× improvement**, and closes the one gap in option Z's default. ⛔ **Its stated bound — *"13,101 B is proven, the digest is 19,813 B, so Z at full digest size
  is unproven by 51%"* — is RETIRED on two independent grounds, and both are worth keeping.**
  First it was the wrong unit (§10.7: a file carries only the 12,166 B static digest, never the
  hook's composed emission). Second and decisively, **probe C superseded the capacity figure
  itself** — 32,056 B, below. Neither correction rescued the other: the unit error would have
  made the bound wrong even at 13,101 B, and the capacity result makes it moot at any unit.
- ✅ **PROBE C READ 2026-08-26 (second session) — ALL NINE MARKERS PRESENT. The rules channel
  carries 32,056 B in full, the ruled design is unconditionally safe, and this line of
  measurement is CLOSED — do not re-arm it.**
  Under the §10.7 split the file must hold the static digest (11,960 ch) **plus** the conditional
  blocks rewritten as stated conditionals — bounded above by the hook script's own 13,807 ch, so
  ~25,800 ch worst case. Probe A proved only 13,101 B, so this is the one measurement the ruled
  design still needs. ⭐ **It is deliberately armed ABOVE the worst case, at ~32,000 ch, so that a
  pass settles the channel permanently and no further probe is ever needed.** File
  `~/.claude/rules/_probe-c-size.md`, **32,056 B**, nine markers `PROBE-C-M4T9-*` at measured
  offsets **703 / 4,052 / 8,067 / 12,008 / 16,023 / 20,038 / 24,053 / 28,068 / TAIL 32,009**.
  **Result: 9 of 9 present, classified from context and never from disk** — a `cat` of the file
  returns the same nine markers whether or not the channel delivered them, so a disk read is an
  instrument that cannot fail. ⭐ **The TAIL marker is the load-bearing one**: any partial delivery
  presents as a prefix, so markers 1–8 prove nothing about the ceiling; only `TAIL-32009`, arriving
  with its terminating sentence intact, proves nothing was cut. ⇒ **§10.1's proven figure for this
  channel rises 13,101 B → 32,056 B (2.4×), clearing the ruled design's ~25,800 ch worst case with
  ~6.1 KB of headroom.** ⛔ **That headroom is NOT a budget.** §10.7 established that this channel's
  threshold is per-tool and remotely mutable; 32,056 B is a proven floor at one moment, not a
  constant, and the whole point of the file/hook split is that no payload is sized against a cap.
  ✅ Probe file removed the same session (`rm ~/.claude/rules/_probe-c-size.md`); it was untracked
  in the `~/.claude` repo, so nothing was lost. ⚠ Per §10.6 it could not be read by the session
  that created it — the instruction-file set is snapshotted at session start — which is why this
  is stamped by a later session.
- ⛔ **The exact `additionalContext` cap is STILL OPEN, and probe A could never have closed it.**
  The bullet above previously sat under this heading and claimed the probe would *"locate the cut
  to within ~2 KB"*. **It cannot, and the reason is the part worth keeping:** a
  `~/.claude/rules/*.md` file is delivered through the instruction-file assembly path; the capped
  payload is delivered through the **hook-output** path. Both are directly observable side by side
  in one context — the probe file arrived whole inside the `claudeMd` block while the hook payload
  arrived as a `<persisted-output>` wrapper — so they are demonstrably different consumers with
  different limits, and a measurement on one does not transfer to the other. ⚑ **§2.6 states this
  exact rule**, rejecting two earlier probes for going *"through the Bash tool consumer, not the
  hook consumer"* — and the next section then armed a third probe on a third wrong channel.
  `feedback_guard_scoped_to_the_wrong_unit`: the instrument was drawn around the wrong unit, and a
  stated bound did not protect the design that cited it. **The bracket (>3,321 safe, ≤19,557
  truncating) is unchanged**, and per §2.6 it is unreachable from history — only a purpose-built
  emission on the hook channel closes it.
- **OQ1 / dual-field** — still unanswered, and per §8.2 it cannot be run until a hook actually
  emits both fields. Now a low-priority question rather than the deciding one.
