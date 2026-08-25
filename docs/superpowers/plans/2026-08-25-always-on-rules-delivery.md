# Always-On Rules Delivery — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** GATED — gate 2 (`/prospect`) RUN 2026-08-25, verdict **PROCEED-WITH-CHANGES**.
All five amendments applied in the same session that ran the gate: multiline JSON escape
(Task 2, blocking), structure assertion + its mutation check (Task 2 Steps 1/5b, blocking),
hermetic `KT_CONFIG` fixture hoisted to one definition (Task 2 Step 1), human digest review
(Task 1 Step 6), symbol-based copy anchors (Task 3).
Gate report: `knowledge/logs/prospect/2026-08-25-file-always-on-rules-delivery-plan.md`.
**EXECUTION-READY.** Task 1 Step 6 is a human gate — Tasks 2–6 wait on Mike reading the digest.

**Goal:** Make ARIA's working rules and user rules reach model context in every session, for every user — not only for the maintainer, who hand-built a delivery layer the plugin does not ship.

**Architecture:** ARIA's only `SessionStart` hook emits `{"systemMessage": ...}`, which renders to the user's terminal and never enters model context. Rather than edit that script, register a **second** `SessionStart` hook that emits `hookSpecificOutput.additionalContext` — the channel two other plugins in the same session (output-style, superpowers) already use successfully. The existing script is left byte-unchanged, so the nag path cannot regress.

**Tech Stack:** POSIX `sh` (hooks), the plugin's own shell test harness (`tests/run.sh` + `tests/helpers.sh`), `jq` (already a dependency of `check-port-drift.sh`), markdown.

**Spec:** `docs/superpowers/specs/2026-08-25-always-on-rules-delivery-design.md` — read it first. The plan argues from the spec; every task below cites the section it implements.

## Global Constraints

- **Repo:** `aria/aria-knowledge`. **Port:** `plugin-claude-code` **only.** Codex, Cowork, and Antigravity have the same gap and are explicitly out of scope (spec §5).
- **`bin/session-start-check.sh` must end byte-identical to its pre-change state — through Task 6.** This is AC8 and it is the guarantee that justifies the two-hook design. Verify with `git diff --exit-code -- plugin-claude-code/bin/session-start-check.sh` after Tasks 2, 3, 4 and 6.
  ⚠ **Task 7 is the single, deliberate exception**, added after AC8 was written: it reworks the TASK BUDGET long variant *in that file*, because the defect lives there and cannot be fixed from the new script. Sequencing protects the guarantee — AC8 holds unmodified across every delivery-mechanism task, and only the last task touches the file, for a reason unrelated to delivery. **Re-baseline AC8 against the post-Task-7 state**, and say so in that commit message so a later reader does not read the diff as a violation.
- **Shell dialect is POSIX `sh`, not bash.** Every existing hook starts `#!/bin/sh`. No `[[ ]]`, no arrays, no `local` beyond what the existing scripts already use.
- **Emit `hookSpecificOutput.additionalContext`, never `systemMessage`, from the new script.** The reverse is the defect being fixed.
- **Never migrate the TASK BUDGET long variant** (`session-start-check.sh:239`). Only the short variant (`:241`) is in scope. Spec §4.2a carries the reason.
- **Six commits, one concern each** (spec §4.2a). Do not squash.
- **Directory-dependent Bash calls carry their own parenthesised absolute `cd`** — `(cd "$ARIA_REPO/…" && cmd)`. A bare leading `cd` is blocked by a PreToolUse hook.
- **Set `ARIA_REPO` once before executing**, to the absolute path of your `aria-knowledge` checkout:
  ```bash
  ARIA_REPO="$(git -C . rev-parse --show-toplevel)"   # run from anywhere inside the repo
  ```
  Every command below uses it. ⚠ This repo is **public** and its tracked docs are readable by anyone — a hardcoded home path is both a portability bug for other checkouts and needless local detail in a public artifact. (Measured: `release.sh` Gate D does **not** flag home paths, and existing tracked plans contain them, so this is a correctness convention, not a hygiene violation.)
- **Never pipe a command whose exit code you will cite.** Read the bare exit code in its own call.
- **Rule counts are derived, never hardcoded in prose.** The digest's own count comes from `grep -c '^### [0-9]' template/rules/working-rules.md` (currently 38). Hardcoding is the defect that produced the "34" drift.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `plugin-claude-code/rules/aria-rules.md` | **create** | The always-on digest: one explanatory line per working rule, plus a pointer to the full file. The only new content artifact. |
| `plugin-claude-code/bin/session-start-rules.sh` | **create** | The second SessionStart hook. Builds and emits the `additionalContext` payload. Sole owner of the model-directed channel. |
| `plugin-claude-code/.claude-plugin/plugin.json` | modify | Register the second hook in the existing `SessionStart` array. |
| `plugin-claude-code/tests/test-aria-rules-digest.sh` | **create** | Drift gate + payload assertions. Sourced by `tests/run.sh`. |
| `plugin-claude-code/bin/post-compact-check.sh` | modify | Append the digest to its existing `additionalContext` emission. |
| `plugin-claude-code/skills/setup/SKILL.md` | modify | CLAUDE.md pointer offer (§4.4); `/index` invocation and Step 6 copy (§4.5). |
| `plugin-claude-code/template/index.md` | **create** | Tag-index skeleton so the file always exists. |
| `plugin-claude-code/bin/session-start-check.sh` | **UNTOUCHED** | Guarded by AC8. |

Boundary rationale: all model-directed payload construction lives in one new script, so the channel has exactly one owner. The existing script keeps exactly one responsibility (user-facing nags) and loses none.

---

### Task 1: The rules digest and its drift gate

Implements spec §4.1. Commit 1 of 8.

**Files:**
- Create: `plugin-claude-code/rules/aria-rules.md`
- Create: `plugin-claude-code/tests/test-aria-rules-digest.sh`

**Interfaces:**
- Consumes: `plugin-claude-code/template/rules/working-rules.md` (38 rules, headings `### N. <title>`).
- Produces: `rules/aria-rules.md` containing one `- **Rule N — <short title>** — <one-line gloss>` per rule. Task 2 reads this file verbatim.

⛔ **SOURCE OF TRUTH: `plugin-claude-code/template/rules/working-rules.md` — the canonical
plugin copy. NEVER the maintainer's installed copy at
any **installed** copy at `{knowledge_folder}/rules/working-rules.md`.** (Mike's
instruction, 2026-08-25.)

An installed copy is **user-owned and diverges by design** — `/setup` diffs it on updates
precisely so users can customize it. Measured on the maintainer's: **472** lines vs the
template's **470**, the extra two being a personal annotation on Rule 18 about a pattern
that has not met the promotion bar. Digesting from an installed copy would ship one user's
private working notes to every ARIA user inside a plugin artifact.

⚠ **A rule-count check cannot catch this**: both files have exactly 38 rules. The drift
gate in this task compares number sets, so it would pass on a digest built from the wrong
file. The only protection is sourcing correctly in the first place — hence the explicit
`SRC="$APM_ROOT/template/..."` in the test, which is repo-relative and cannot resolve to a
user's knowledge folder.

⚠ **Do not copy `plugin-antigravity/rules/aria-rules.md`.** It is the *format* precedent only: its content says "ARIA enforces 34 working rules" while the source has 38. Copying it reproduces the exact drift this task's gate exists to prevent.

- [ ] **Step 1: Write the failing test**

Create `plugin-claude-code/tests/test-aria-rules-digest.sh`:

```sh
# shellcheck shell=sh
# Drift gate: the digest must cover every rule in working-rules.md, by NUMBER SET.
# A count comparison is insufficient — the antigravity digest's "34" matched a
# stale count while membership had moved to 38.
APM_ROOT="$(cd "$DIR/.." && pwd)"
SRC="$APM_ROOT/template/rules/working-rules.md"
DIGEST="$APM_ROOT/rules/aria-rules.md"

# Rule numbers present in the source, sorted, comma-joined.
src_nums=$(grep '^### [0-9]' "$SRC" | sed 's/^### \([0-9]*\)\..*/\1/' | sort -n | tr '\n' ',')
# Rule numbers claimed by the digest.
dig_nums=$(grep -o '^- \*\*Rule [0-9]*' "$DIGEST" 2>/dev/null | sed 's/^- \*\*Rule //' | sort -n | tr '\n' ',')

assert_eq "digest covers every working rule by number" "$src_nums" "$dig_nums"

# Positive control: the source parse must be non-empty, or the assertion above
# is satisfied by two empty strings and proves nothing.
assert_eq "source rule parse is non-empty" "yes" "$([ -n "$src_nums" ] && echo yes || echo no)"

# The digest must point at the full file rather than replacing it.
assert_eq "digest points at the full rules file" "yes" \
  "$(grep -q 'rules/working-rules.md' "$DIGEST" 2>/dev/null && echo yes || echo no)"
```

- [ ] **Step 2: Run it and verify it fails for the right reason**

Run: `(cd "$ARIA_REPO"/plugin-claude-code && sh tests/run.sh)`

Expected: FAIL on "digest covers every working rule by number", actual side empty (the digest does not exist yet). The "source rule parse is non-empty" control must **pass** — if it fails, the source path is wrong and the gate is measuring nothing.

- [ ] **Step 3: Write the digest**

Create `plugin-claude-code/rules/aria-rules.md`. Derive every line from `template/rules/working-rules.md` — read each rule's heading and body, then write one line capturing what it *directs*, not what it is titled.

Header and the first entries, verbatim as the format contract:

```markdown
# ARIA Working Rules — Always-On Digest

Condensed working rules, loaded into context at the start of every session. For the full
reasoning, examples, and edge cases behind any rule, read
`{knowledge_folder}/rules/working-rules.md` (created by `/setup`).

These are behavioural rules. Apply them as you work; do not wait to be asked.

## Behavioural Foundation

1. **Don't assume — surface tradeoffs.** Flag uncertainty, present alternatives, push back when warranted.
2. **Simplest solution wins — nothing speculative.** No abstraction or feature beyond what is asked.
3. **Touch only what you must.** Match scope to the request.
4. **Define success criteria upfront, then validate.** Strong criteria enable independent loops.

## Coding Rules

- **Rule 1 — Scope tightly, see holistically** — break work into focused steps but keep the integration picture.
- **Rule 2 — Let errors guide context** — don't preemptively document everything; add context to correct recurring mistakes.
- **Rule 3 — Use reference implementations wisely** — cite canonical examples, but present tradeoffs when alternatives exist.
- **Rule 4 — Choose the lower-token option per operation** — CLI for simple Unix ops, structured queries for structured data.
- **Rule 5 — Explain reasoning before changes** — walk through new patterns for approval; batch existing ones.
```

Continue through **Rule 38**, following the source's own four groupings (Behavioural Foundation, Coding Rules, Process Rules, Meta Rules). Close with:

```markdown
---

Full text, with reasoning and worked examples, at `{knowledge_folder}/rules/working-rules.md`.
The user's own rules — binding alongside these — are at `{knowledge_folder}/rules/user-rules.md`.
```

Target ≤ 7 KB. If it exceeds that, shorten the glosses; do not drop rules — the gate will catch a dropped rule and the size target is not a reason to fail it.

- [ ] **Step 4: Run the test and verify it passes**

Run: `(cd "$ARIA_REPO"/plugin-claude-code && sh tests/run.sh)`
Expected: all three assertions pass, bare exit 0.

- [ ] **Step 5: Mutation-verify the gate (AC3 — required, not optional)**

Delete one rule line from the digest, re-run, confirm FAIL naming the missing number, then restore and confirm PASS.

```bash
(cd "$ARIA_REPO"/plugin-claude-code && cp rules/aria-rules.md "$TMPDIR/digest.bak" && grep -v '^- \*\*Rule 13' rules/aria-rules.md > /tmp/d && mv /tmp/d rules/aria-rules.md)
```

Run the suite: expect FAIL. Then restore from the byte backup and re-run: expect PASS.

```bash
(cd "$ARIA_REPO"/plugin-claude-code && cp "$TMPDIR/digest.bak" rules/aria-rules.md && cmp "$TMPDIR/digest.bak" rules/aria-rules.md)
```

⚠ Restore from the **byte backup**, never `git checkout --` — the digest is a new untracked file at this point and `git checkout` would delete it.

- [ ] **Step 6: HUMAN GATE — Mike reads the digest before Task 2 begins**

⛔ **Blocking. Added at gate 2 (change 4).** The drift gate proves every rule *number* is
present. It cannot tell a good gloss from a bad one — 38 lines of nonsense pass every
assertion in this task. This is the only genuinely authorial artifact in the arc and it
ships to every user on every session, so the one thing no mechanical check covers is the
thing that matters most.

Present the finished digest and ask for a read. Do not start Task 2 until it comes back.
Corrections are cheap now and expensive after five commits sit on top of it.

- [ ] **Step 7: Commit**

```bash
(cd "$ARIA_REPO" && git add plugin-claude-code/rules/aria-rules.md plugin-claude-code/tests/test-aria-rules-digest.sh && git commit -m "feat(rules): add always-on working-rules digest with a number-set drift gate")
```

---

### Task 2: The second SessionStart hook — Unit 1 payload

Implements spec §4.2. Commit 2 of 8.

**Files:**
- Create: `plugin-claude-code/bin/session-start-rules.sh`
- Modify: `plugin-claude-code/.claude-plugin/plugin.json` (the `SessionStart` array, currently lines 24-35)
- Modify: `plugin-claude-code/tests/test-aria-rules-digest.sh` (add payload assertions)

**Interfaces:**
- Consumes: `rules/aria-rules.md` from Task 1; `bin/config.sh` for `KT_CONFIGURED`, `KT_CONFIG_ERROR`, `KT_KNOWLEDGE_FOLDER`, `KT_ACTIVE_SURFACING`, `KT_AUTO_CAPTURE`, and the `kt_json_escape` helper (used the same way at `session-start-check.sh:429`).
- Produces: a single JSON object on stdout, `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}`. Task 3 extends the same script; Task 4 reuses the same payload-building logic.

- [ ] **Step 1: Write the failing test**

Append to `plugin-claude-code/tests/test-aria-rules-digest.sh`:

```sh
# --- session-start-rules.sh emits additionalContext, never systemMessage ---
#
# Fixture defined ONCE here and reused by every later block in this file — the hook
# must never be run against the developer's real config, or the suite is
# environment-dependent and slow. KT_CONFIG is overridable (config.sh:5).
CFG="$APM_TMP/aria-cfg.md"
KF="$APM_TMP/kf"; mkdir -p "$KF/rules"
printf -- '---\nknowledge_folder: %s\n---\n' "$KF" > "$CFG"

HOOK="$APM_ROOT/bin/session-start-rules.sh"
OUT="$APM_TMP/ssr-out.json"
KT_CONFIG="$CFG" sh "$HOOK" > "$OUT" 2>/dev/null
rc=$?

assert_eq "hook exits 0" "0" "$rc"
assert_eq "emits additionalContext" "yes" \
  "$(grep -q 'additionalContext' "$OUT" && echo yes || echo no)"
assert_eq "does NOT emit systemMessage" "no" \
  "$(grep -q 'systemMessage' "$OUT" && echo yes || echo no)"
assert_eq "payload carries a digest rule line" "yes" \
  "$(grep -q 'Rule 13' "$OUT" && echo yes || echo no)"
assert_eq "payload carries RULE 22 ORDERING" "yes" \
  "$(grep -q 'RULE 22 ORDERING' "$OUT" && echo yes || echo no)"
assert_eq "payload is valid JSON" "yes" \
  "$(jq -e . "$OUT" >/dev/null 2>&1 && echo yes || echo no)"

# Structure preservation (gate 2, change 2 — BLOCKING).
# The digest is a 38-line structured document. config.sh's kt_json_escape ends with
# `tr '\n' ' '`, which would collapse it to one run-on line. This asserts the payload
# carries real newlines after jq decodes it — i.e. that the multiline escape was used.
assert_eq "digest structure survives escaping" "yes" \
  "$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" 2>/dev/null | grep -qc '^- \*\*Rule ' >/dev/null 2>&1 && \
     [ "$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" | wc -l | tr -d ' ')" -gt 20 ] && echo yes || echo no)"
```

⚠ Assert on the **decoded** value via `jq -r`, not on the raw file. Grepping the raw
JSON for a literal backslash-n is brittle and passes on an escaped-but-broken payload.
Decoding is what proves a consumer sees the structure.

- [ ] **Step 2: Run it and verify it fails**

Run: `(cd "$ARIA_REPO"/plugin-claude-code && sh tests/run.sh)`
Expected: FAIL on "hook exits 0" — the script does not exist yet.

- [ ] **Step 3: Write the hook**

Create `plugin-claude-code/bin/session-start-rules.sh`:

```sh
#!/bin/sh
# session-start-rules.sh — SessionStart hook for aria-knowledge.
#
# Sole owner of the MODEL-directed session-start channel. Emits
# hookSpecificOutput.additionalContext, which reaches model context.
#
# Its sibling bin/session-start-check.sh emits systemMessage, which renders to
# the USER and never reaches the model. That split is deliberate: nags ask a
# human to authorise something; the payload here instructs the model.
#
# ⛔ Never emit systemMessage from this script. Never migrate the TASK BUDGET
# long variant (session-start-check.sh:239) here — it instructs behaviour the
# maintainer has repeatedly corrected. Short variant only.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

[ -n "$KT_CONFIG_ERROR" ] && exit 0
[ "$KT_CONFIGURED" = "false" ] && exit 0
[ ! -d "$KT_KNOWLEDGE_FOLDER" ] && exit 0

# Escape for a JSON string value, PRESERVING newlines as the two-character \n escape.
#
# ⛔ Deliberately NOT kt_json_escape from config.sh. That helper ends with
# `tr '\n' ' '` — it STRIPS newlines. Correct for the single-paragraph directives
# it was written for; wrong here, because it would collapse the 7 KB structured
# digest into one run-on line, destroying every heading and bullet.
# ⛔ Do NOT "fix" the shared helper instead. Four other hooks depend on its current
# behaviour and none of them wants structure preserved.
# Precedent: the superpowers plugin's SessionStart payload carries literal \n
# sequences for exactly this reason.
kt_json_escape_multiline() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' -e 's/\r//g' \
    | awk 'BEGIN{ORS=""} NR>1{print "\\n"} {print}'
}

MESSAGES=""

# --- the always-on rules digest ---
DIGEST="$SCRIPT_DIR/../rules/aria-rules.md"
if [ -f "$DIGEST" ]; then
  MESSAGES="${MESSAGES}ARIA WORKING RULES (always in force — apply as you work, do not wait to be asked):
$(cat "$DIGEST")
"
fi

# --- Rule 22 ordering (a rule, and its enforcement is a blocking PreToolUse hook) ---
MESSAGES="${MESSAGES}RULE 22 ORDERING — The Low/High Impact block must appear ABOVE the Edit/Write tool call in the same assistant turn, never below. The PreToolUse hook structurally enforces this: if the [Rule 22] marker is absent from a text block between the previous Edit/Write and this one, the hook returns permissionDecision: deny and blocks the tool call. Emit the block prospectively, not retroactively. Arguments for skipping ('conversation already covered it', 'docs-only edit', 'routine change', 'too trivial') are all invalid — see rules/change-decision-framework.md 'Ordering (required)'. "

# --- standing user rules (U-namespace), two-tier index; ported verbatim from
#     session-start-check.sh:411-427, destination changed, logic unchanged ---
UR_FILE="$KT_KNOWLEDGE_FOLDER/rules/user-rules.md"
if [ -f "$UR_FILE" ]; then
  UR_N=$(grep -c '^### U' "$UR_FILE" 2>/dev/null)
  if [ "${UR_N:-0}" -gt 0 ]; then
    UR_HEADERS=$(grep '^### U' "$UR_FILE" 2>/dev/null | sed 's/^### //' | awk '{printf "%s%s", sep, $0; sep="; "}')
    if [ ${#UR_HEADERS} -gt 3000 ]; then
      MESSAGES="${MESSAGES}STANDING USER RULES — ${UR_N} of the user's own rules are in force, at ${UR_FILE} (too many to index inline). Read that file before acting on anything it plausibly covers. "
    else
      MESSAGES="${MESSAGES}STANDING USER RULES (${UR_N}, always in force — the user's own rules, binding alongside the working rules above): ${UR_HEADERS}. These titles are the index; read ${UR_FILE} for the full text of any rule bearing on the task. "
    fi
  fi
fi

if [ -n "$MESSAGES" ]; then
  # kt_json_escape_multiline, NOT kt_json_escape — see the comment above.
  ESCAPED=$(kt_json_escape_multiline "$MESSAGES")
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESCAPED"
fi

exit 0
```

Then `chmod +x plugin-claude-code/bin/session-start-rules.sh`.

- [ ] **Step 4: Register the hook**

In `plugin-claude-code/.claude-plugin/plugin.json`, add a second command to the existing inner `hooks` array under `SessionStart`:

```json
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/bin/session-start-check.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/bin/session-start-rules.sh",
            "timeout": 10
          }
        ]
      }
    ],
```

Verify the file still parses: `(cd "$ARIA_REPO"/plugin-claude-code && jq -e . .claude-plugin/plugin.json > /dev/null)` — read the bare exit code, expect 0.

- [ ] **Step 5: Run the tests and verify they pass**

Run: `(cd "$ARIA_REPO"/plugin-claude-code && sh tests/run.sh)`
Expected: all assertions pass, bare exit 0.

- [ ] **Step 5b: Mutation-verify the structure assertion (gate 2, change 2)**

Temporarily swap the emission back to the shared stripping escape and confirm the new
assertion goes **red** for the right reason:

```bash
(cd "$ARIA_REPO"/plugin-claude-code && cp bin/session-start-rules.sh "$TMPDIR/ssr.bak" && sed -i '' 's/kt_json_escape_multiline "\$MESSAGES"/kt_json_escape "$MESSAGES"/' bin/session-start-rules.sh)
```

Run the suite: expect **exactly one** new failure — "digest structure survives escaping".
If other assertions also fail, the mutation changed more than intended; investigate before
restoring. Then restore from the byte backup and confirm identity:

```bash
(cd "$ARIA_REPO"/plugin-claude-code && cp "$TMPDIR/ssr.bak" bin/session-start-rules.sh && cmp "$TMPDIR/ssr.bak" bin/session-start-rules.sh)
```

⚠ Restore from the byte backup, never `git checkout --` — at this point the file is
untracked and `git checkout` would delete it outright.

- [ ] **Step 6: Verify AC8 — the sibling script is untouched**

```bash
(cd "$ARIA_REPO" && git diff --exit-code -- plugin-claude-code/bin/session-start-check.sh)
```

Read the bare exit code. Expected 0. **Non-zero here fails the task** — the two-hook design's whole justification is that this file does not change.

- [ ] **Step 7: Commit**

```bash
(cd "$ARIA_REPO" && git add plugin-claude-code/bin/session-start-rules.sh plugin-claude-code/.claude-plugin/plugin.json plugin-claude-code/tests/test-aria-rules-digest.sh && git commit -m "feat(hooks): deliver working rules and user rules to model context via a second SessionStart hook")
```

---

### Task 3: Unit 2 — the four opt-in directives

Implements spec §4.2a. Commit 3 of 8.

**Files:**
- Modify: `plugin-claude-code/bin/session-start-rules.sh`
- Modify: `plugin-claude-code/tests/test-aria-rules-digest.sh`

**Interfaces:**
- Consumes: `KT_PROJECTS_ENABLED`, `KT_SESSION_START_PROJECT_PICKER`, `KT_SESSION_STATE`, `KT_AUTONOMY`, `KT_PROJECTS_LIST` from `config.sh`; the CODEMAP-discovery block at `session-start-check.sh:328-397`.
- Produces: the same single JSON object, with four conditionally-appended blocks.

⚠ **Copy each block's text verbatim from `session-start-check.sh`.** Do not rewrite or improve the wording in this task — a reworded directive changes behaviour and makes a regression unattributable. Wording changes are a separate concern and a separate commit.

⛔ **Do not touch the TASK BUDGET long variant** (`:239`). It stays on `systemMessage`.

- [ ] **Step 1: Write the failing tests — gates, both directions**

Append to `plugin-claude-code/tests/test-aria-rules-digest.sh`:

```sh
# --- Unit 2 blocks are gated; each must be absent by default, present when on ---
CFG="$APM_TMP/aria-cfg.md"

run_hook_with() { # CONFIG_BODY -> writes $APM_TMP/u2.json
  printf -- '---\nknowledge_folder: %s\n%s\n---\n' "$KT_KNOWLEDGE_FOLDER" "$1" > "$CFG"
  KT_CONFIG="$CFG" sh "$APM_ROOT/bin/session-start-rules.sh" > "$APM_TMP/u2.json" 2>/dev/null
}

run_hook_with "autonomy: default"
assert_eq "DECISION ROUTING absent at autonomy=default" "no" \
  "$(grep -q 'DECISION ROUTING' "$APM_TMP/u2.json" && echo yes || echo no)"

run_hook_with "autonomy: autonomous"
assert_eq "DECISION ROUTING present at autonomy=autonomous" "yes" \
  "$(grep -q 'DECISION ROUTING' "$APM_TMP/u2.json" && echo yes || echo no)"

run_hook_with "session_state: false"
assert_eq "SESSION STATE absent when off" "no" \
  "$(grep -q 'SESSION STATE' "$APM_TMP/u2.json" && echo yes || echo no)"

run_hook_with "session_state: true"
assert_eq "SESSION STATE present when on" "yes" \
  "$(grep -q 'SESSION STATE' "$APM_TMP/u2.json" && echo yes || echo no)"

assert_eq "TASK BUDGET long variant never migrated" "no" \
  "$(grep -q 'aria-statusline-state' "$APM_TMP/u2.json" && echo yes || echo no)"
```

Both directions are required. A present-only assertion passes against an ungated block, which is the vacuous form this plan's spec warns about at §2.1.

- [ ] **Step 2: Run and verify failure**

Run: `(cd "$ARIA_REPO"/plugin-claude-code && sh tests/run.sh)`
Expected: FAIL on the four "present when on" assertions; the "absent when off" ones pass trivially (nothing is emitted yet). That asymmetry is expected and is exactly why both directions are asserted.

- [ ] **Step 3: Add the four gated blocks**

Insert into `session-start-rules.sh` before the final emission, each guard copied from the cited line in `session-start-check.sh` and each message body copied verbatim:

```sh
# --- CODEMAP staleness (guard + body from session-start-check.sh:328-397) ---
# ... discovery loop copied verbatim ...

# --- Project picker (guard from :267) ---
if [ "$KT_PROJECTS_ENABLED" = "true" ] && [ "$KT_SESSION_START_PROJECT_PICKER" = "true" ]; then
  # ... PICKER_MENU construction and message body copied verbatim from :268-277 ...
  :
fi

# --- SESSION STATE (guard from :308) ---
if [ "$KT_SESSION_STATE" = "true" ]; then
  MESSAGES="${MESSAGES}SESSION STATE — ...verbatim from :309... "
fi

# --- Autonomy posture (guard from :404) ---
if [ "$KT_AUTONOMY" = "balanced" ]; then
  MESSAGES="${MESSAGES}DECISION ROUTING (balanced) — ...verbatim from :405... "
elif [ "$KT_AUTONOMY" = "autonomous" ]; then
  MESSAGES="${MESSAGES}DECISION ROUTING (autonomous) — ...verbatim from :407... "
fi
```

- [ ] **Step 4: Run tests and verify they pass**

Run: `(cd "$ARIA_REPO"/plugin-claude-code && sh tests/run.sh)`
Expected: all pass, bare exit 0.

- [ ] **Step 5: Re-verify AC8**

```bash
(cd "$ARIA_REPO" && git diff --exit-code -- plugin-claude-code/bin/session-start-check.sh)
```
Bare exit code 0. The blocks were **copied**, not moved — the original must still contain them.

- [ ] **Step 6: Commit**

```bash
(cd "$ARIA_REPO" && git add plugin-claude-code/bin/session-start-rules.sh plugin-claude-code/tests/test-aria-rules-digest.sh && git commit -m "feat(hooks): deliver the four opt-in session directives to model context")
```

---

### Task 4: Survive compaction

Implements spec §4.3. Commit 4 of 8.

**Files:**
- Modify: `plugin-claude-code/bin/post-compact-check.sh:50-58`
- Modify: `plugin-claude-code/tests/test-aria-rules-digest.sh`

**Interfaces:**
- Consumes: `rules/aria-rules.md`; the existing `MESSAGES` accumulator in `post-compact-check.sh`.
- Produces: no new interface. The existing `additionalContext` emission gains the digest.

- [ ] **Step 1: Write the failing test**

```sh
# --- the digest survives compaction ---
printf '{"session_id":"test-sess"}' | sh "$APM_ROOT/bin/post-compact-check.sh" > "$APM_TMP/pc.json" 2>/dev/null
assert_eq "post-compact re-injects the digest" "yes" \
  "$(grep -q 'Rule 13' "$APM_TMP/pc.json" && echo yes || echo no)"
assert_eq "post-compact still uses additionalContext" "yes" \
  "$(grep -q 'additionalContext' "$APM_TMP/pc.json" && echo yes || echo no)"
```

- [ ] **Step 2: Run and verify it fails**

Expected: FAIL on "post-compact re-injects the digest".

- [ ] **Step 3: Add the digest to the accumulator**

In `post-compact-check.sh`, before the emission block at `:54`:

```sh
# Block 3: re-inject the always-on rules digest. Compaction is the main way an
# always-on rule stops being always-on mid-session.
DIGEST="$SCRIPT_DIR/../rules/aria-rules.md"
if [ -f "$DIGEST" ]; then
  MESSAGES="${MESSAGES}ARIA WORKING RULES (re-injected after compaction — still in force): $(cat "$DIGEST") "
fi
```

- [ ] **Step 4: Run tests and verify they pass**

Run: `(cd "$ARIA_REPO"/plugin-claude-code && sh tests/run.sh)`
Expected: all pass, bare exit 0.

- [ ] **Step 5: Commit**

```bash
(cd "$ARIA_REPO" && git add plugin-claude-code/bin/post-compact-check.sh plugin-claude-code/tests/test-aria-rules-digest.sh && git commit -m "feat(hooks): re-inject the rules digest after compaction")
```

---

### Task 5: `/setup` offers the CLAUDE.md pointer

Implements spec §4.4. Commit 5 of 8.

**Files:**
- Modify: `plugin-claude-code/skills/setup/SKILL.md` (the ADR paragraph at `:279`, plus a new step)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: nothing consumed by later tasks.

⚠ **This reverses a documented ADR.** The reversal must be recorded in `SKILL.md` at the ADR's own location, not left as a silent contradiction (spec §4.4, and Rule 21 — document decisions).

- [ ] **Step 1: Amend the ADR paragraph in place**

At `skills/setup/SKILL.md:279`, append to the existing paragraph:

```markdown

**Amended 2026-08-25.** The blanket deferral above is narrowed to `_project-knowledge/`
references, which remain first-write-triggered. A *rules pointer* is now offered at the
end of `/setup` (see the Rules Pointer step below): the rules files exist the moment
`/setup` finishes, so the "documenting a convention before the folder exists" objection
does not apply to them. The offer is explicit, default-no, per-repo, and shows the exact
block before writing — preserving what this ADR protects.
```

- [ ] **Step 2: Add the offer step**

```markdown
### Rules Pointer (optional, default no)

After the config is written, offer once per repo:

> "Add a 4-line ARIA rules pointer to this repo's `CLAUDE.md`? The rules already reach
> Claude through the SessionStart hook; `CLAUDE.md` is the one surface Claude Code also
> re-injects after `/compact`. This file is [git-tracked / untracked], so a write here
> [would / would not] be visible to teammates. (y/N)"

On `y`, append exactly:

```markdown
## ARIA Rules
Working rules: `{knowledge_folder}/rules/working-rules.md`
User rules: `{knowledge_folder}/rules/user-rules.md`
Read either before acting on anything it plausibly covers.
```

On `n` or no reply, write nothing. Detect tracking with
`git ls-files --error-unmatch CLAUDE.md` — never by checking `.gitignore`, since an
ignore rule is a no-op on an already-tracked path.
```

- [ ] **Step 3: Verify the ADR no longer self-contradicts**

Run: `(cd "$ARIA_REPO"/plugin-claude-code && grep -n "CLAUDE.md reference handling deferred\|Amended 2026-08-25" skills/setup/SKILL.md)`
Expected: both lines present, the amendment immediately after the original.

- [ ] **Step 4: Commit**

```bash
(cd "$ARIA_REPO" && git add plugin-claude-code/skills/setup/SKILL.md && git commit -m "feat(setup): offer a CLAUDE.md rules pointer, default no")
```

---

### Task 6: `index.md` template, gate tightening, and `/index` on setup

Implements spec §4.5. Commit 6 of 8. **Three coupled changes — shipping any one alone makes things worse** (spec §4.5b).

**Files:**
- Create: `plugin-claude-code/template/index.md`
- Modify: `plugin-claude-code/bin/session-start-rules.sh` (ACTIVE CONTEXT gate)
- Modify: `plugin-claude-code/skills/setup/SKILL.md` (run `/index`; Step 6 copy)
- Modify: `plugin-claude-code/tests/test-aria-rules-digest.sh`

**Interfaces:**
- Consumes: `KT_ACTIVE_SURFACING`; the ACTIVE CONTEXT body from `session-start-check.sh:249`.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing test — both directions (AC10)**

```sh
# --- ACTIVE CONTEXT gates on tag CONTENT, not mere file existence ---
IDX="$APM_TMP/kf/index.md"; mkdir -p "$APM_TMP/kf"

printf '# Index\n\n## Tag Index\n\n' > "$IDX"   # zero tags
KT_CONFIG="$CFG" KT_KNOWLEDGE_FOLDER="$APM_TMP/kf" sh "$APM_ROOT/bin/session-start-rules.sh" > "$APM_TMP/idx.json" 2>/dev/null
assert_eq "ACTIVE CONTEXT absent with zero tags" "no" \
  "$(grep -q 'ARIA ACTIVE CONTEXT' "$APM_TMP/idx.json" && echo yes || echo no)"

printf '# Index\n\n## Tag Index\n\n### somejtag\n- a.md — x\n' > "$IDX"   # one tag
KT_CONFIG="$CFG" KT_KNOWLEDGE_FOLDER="$APM_TMP/kf" sh "$APM_ROOT/bin/session-start-rules.sh" > "$APM_TMP/idx.json" 2>/dev/null
assert_eq "ACTIVE CONTEXT present with one tag" "yes" \
  "$(grep -q 'ARIA ACTIVE CONTEXT' "$APM_TMP/idx.json" && echo yes || echo no)"

assert_eq "template ships an index.md" "yes" \
  "$([ -f "$APM_ROOT/template/index.md" ] && echo yes || echo no)"
```

- [ ] **Step 2: Run and verify it fails**

Expected: FAIL on "template ships an index.md" and on "ACTIVE CONTEXT present with one tag".

- [ ] **Step 3: Create the template**

`plugin-claude-code/template/index.md`:

```markdown
# Knowledge Index

Generated by `/index`. Run it after promoting files to rebuild this index.

## Tag Index

_No tags yet. Promote knowledge with `/audit-knowledge`, then run `/index`._

## Other Tags

_Freeform tags appear here. They are deliberately excluded from automatic surfacing._
```

- [ ] **Step 4: Add the gated ACTIVE CONTEXT block**

In `session-start-rules.sh`, gating on tag **content**, not existence:

```sh
# --- ARIA ACTIVE CONTEXT (gate tightened: file must exist AND carry ≥1 tag) ---
INDEX_FILE="$KT_KNOWLEDGE_FOLDER/index.md"
if [ "$KT_ACTIVE_SURFACING" = "true" ] && [ -f "$INDEX_FILE" ] \
   && grep -q '^### ' "$INDEX_FILE" 2>/dev/null; then
  MESSAGES="${MESSAGES}ARIA ACTIVE CONTEXT — ...verbatim from session-start-check.sh:249... "
fi
```

- [ ] **Step 5: Make `/setup` run `/index` and mention the new delivery**

In `skills/setup/SKILL.md`, after the config-write step, add: *"Run `/index` to populate `{knowledge_folder}/index.md` from whatever is already promoted. The skeleton ships with the template; this fills it."*

In Step 6's session/project block, add one line: *"These directives now reach Claude directly (SessionStart → additionalContext), so enabling them has a visible effect. They all default off."*

- [ ] **Step 5b: Close the new coupling in `audit-knowledge` (Mike's C, 2026-08-25)**

⚠ **`/index` after `audit-knowledge` is already handled — do not add a prompt.** Measured:
`skills/audit-knowledge/SKILL.md:918-943` **Step 7b runs the full 8-step `/index` logic
unconditionally** after promotions and writes `index.md`, with an explicit first-run branch
("Building knowledge index for the first time"). Automatic is stronger than prompted; a
prompt would be a regression.

**What this task does create, though, is a new consequence for that rebuild.** Until now an
index with zero `### ` tag headers was merely unhelpful. After Step 4, it silently keeps
ARIA ACTIVE CONTEXT switched off. Step 7b has no reason to mention that today.

Add to `skills/audit-knowledge/SKILL.md` Step 7b, after "write the final `index.md`":

```markdown
After writing, count tag sections (`grep -c '^### ' index.md`). If **zero**, note:
> "Index rebuilt with no tag sections. Active knowledge surfacing stays off until at
> least one promoted file carries a tag — the SessionStart hook gates on tag content,
> not on the index file existing."
```

Modify: `plugin-claude-code/skills/audit-knowledge/SKILL.md`.

- [ ] **Step 6: Run tests and verify they pass**

Run: `(cd "$ARIA_REPO"/plugin-claude-code && sh tests/run.sh)`
Expected: all pass, bare exit 0.

- [ ] **Step 7: Commit**

```bash
(cd "$ARIA_REPO" && git add plugin-claude-code/template/index.md plugin-claude-code/bin/session-start-rules.sh plugin-claude-code/skills/setup/SKILL.md plugin-claude-code/skills/audit-knowledge/SKILL.md plugin-claude-code/tests/test-aria-rules-digest.sh && git commit -m "feat(setup): ship an index.md skeleton, gate active-context on tag content, run /index on setup")
```

---

### Task 7: Rework the TASK BUDGET long variant

Added 2026-08-25 (Mike: "D also address this"). Commit 7 of 8. Spec §4.2a names this a
**defect**, not a migration candidate.

**Files:**
- Modify: `plugin-claude-code/bin/session-start-check.sh:239` — ⚠ **the one exception to
  AC8.** Re-baseline AC8 against the post-Task-7 state and note it in the commit message.
- Modify: `plugin-claude-code/bin/session-start-rules.sh` (deliver the reworked variant)
- Modify: `plugin-claude-code/tests/test-aria-rules-digest.sh`

**Interfaces:** consumes `KT_KNOWLEDGE_FOLDER` and the statusline-snapshot path check at `:238`.

**The defect.** The long variant fires only when the status-line meter is installed, and
instructs: *"consult it when judging whether to keep going, and before /handoff, /wrapup,
or compacting."* That is the behaviour Mike has corrected repeatedly — *"usage measurements
are wrong, ignore them and proceed"*, *"why did you stop? there's context left"*. Migrating
it as written would take an instruction that has never reached a model and start delivering
it, causing a known-unwanted behaviour. The short variant (`:241`) is already correct and
ships unchanged in Task 2.

**The rework — preserve the capability, remove the directive.** The snapshot is genuinely
useful for *answering* a usage question. It must not be used to *decide* whether to stop.

- [ ] **Step 1: Write the failing test**

```sh
# --- TASK BUDGET must never instruct autonomous stopping ---
run_hook_with "usage_snapshot_present: true"
BODY=$(jq -r '.hookSpecificOutput.additionalContext' "$APM_TMP/u2.json" 2>/dev/null)
assert_eq "no autonomous-stop directive" "no" \
  "$(printf '%s' "$BODY" | grep -qi 'judging whether to keep going\|before /handoff, /wrapup, or compacting' && echo yes || echo no)"
assert_eq "snapshot still reachable for answering" "yes" \
  "$(printf '%s' "$BODY" | grep -q 'aria-statusline-state' && echo yes || echo no)"
```

- [ ] **Step 2: Run and verify it fails** — expect FAIL on "no autonomous-stop directive".

- [ ] **Step 3: Rewrite the long variant**

Replace the body at `session-start-check.sh:239` and deliver the replacement from
`session-start-rules.sh`:

```
TASK BUDGET — A usage snapshot is written by the aria-knowledge status-line meter at
${USAGE_SNAP} (context-window %, 5-hour, 7-day). Read it when the USER asks about usage,
and re-read it fresh at that moment rather than citing a number from earlier in the
conversation. Treat the 5-hour/7-day figures as stale past five_hour_resets_at /
seven_day_resets_at, and context_pct as unknown if the snapshot's session_id does not
match this session. ⛔ Do NOT use these figures to decide whether to stop, shorten, skip
a required step, or wrap up — that decision is the user's. If you believe the session is
strained, say so and offer options; never resolve it unilaterally toward less work.
```

- [ ] **Step 4: Run tests, verify pass.** `(cd "$ARIA_REPO"/plugin-claude-code && sh tests/run.sh)`

- [ ] **Step 5: Commit**

```bash
(cd "$ARIA_REPO" && git add plugin-claude-code/bin/session-start-check.sh plugin-claude-code/bin/session-start-rules.sh plugin-claude-code/tests/test-aria-rules-digest.sh && git commit -m "fix(hooks): stop TASK BUDGET instructing autonomous wrap-up; keep the snapshot for answering")
```

---

### Task 8: Discoverability of the opt-in features

Added 2026-08-25 (Mike: "D also address this"). Commit 8 of 8. Implements the
recommendation recorded at spec §9 OQ5. **Changes no defaults** — OQ5 stays open.

**Files:**
- Modify: `plugin-claude-code/skills/setup/SKILL.md`

**Why not change defaults.** Measured: `projects_enabled`, `auto_load_project_context`, and
`session_start_project_picker` are dependent on a `projects_list` a new user has not
populated — flipping them enables machinery with no data. `session_state: true` would write
`SESSION.md` files into users' repos unasked, the same posture the §4.4 ADR protects.
`autonomy: balanced` changes agent behaviour for every existing user on upgrade. The gap is
discovery, not defaults.

- [ ] **Step 1: Move the project block out from behind Advanced Options**

The Project Setup flow (questions 1-6, `skills/setup/SKILL.md:242+`) currently sits under
Advanced Options, so a user on the fast path never sees it. Promote it to the main flow as
a single yes/no with a one-line description, defaulting **no**, keeping the detailed
questions behind that yes.

- [ ] **Step 2: Add a post-setup summary of what is off**

After the config is written:

```
ARIA is configured. These features are available and currently OFF:
  - Project knowledge tier ......... projects_enabled
  - Session resume (SESSION.md) .... session_state
  - Project picker at session start  session_start_project_picker
  - Autonomy posture ............... autonomy: default | balanced | autonomous
Enable any of them by editing ~/.claude/aria-knowledge.local.md, or re-run /setup.
```

Emit on `systemMessage` — it asks the user to make a decision, which is what that channel
is for. This is the same reasoning that keeps the audit nags there.

- [ ] **Step 3: Verify both changes are present**

Run: `(cd "$ARIA_REPO"/plugin-claude-code && grep -c "currently OFF" skills/setup/SKILL.md)` — expect 1.

- [ ] **Step 4: Commit**

```bash
(cd "$ARIA_REPO" && git add plugin-claude-code/skills/setup/SKILL.md && git commit -m "feat(setup): surface the opt-in session and project features instead of burying them")
```

---

## Post-execution verification (AC1, AC2, AC7 — cannot be done by the suite)

The shell suite proves the hook *emits* correctly. It cannot prove Claude Code *delivers* it. Those three ACs need a real session.

- [ ] Start a fresh Claude Code session in a configured project.
- [ ] Locate that session's transcript by a unique string from it: `(cd ~/.claude/projects/<project-dir> && /usr/bin/grep -l "<unique phrase>" *.jsonl)`.
- [ ] Classify hook records by type — **classify, never count string occurrences**; the session's own conversation will contain the payload strings and a count inverts the answer:

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

- [ ] **AC1** — a `hook_additional_context` record for `SessionStart` whose content includes a digest rule title.
- [ ] **AC7** — in the *same* session, both a `hook_additional_context` (from `session-start-rules.sh`) **and** a `hook_system_message` (from `session-start-check.sh`).
- [ ] **AC2** — that `hook_system_message` still carries the audit nags.
- [ ] **AC4** — after a `/compact`, a `hook_additional_context` for `PostCompact` containing the digest.

⚠ Hooks arm at **session start**. Never verify a hook change from the session that made it.

---

## Self-Review

**Spec coverage:** §4.1→Task 1 · §4.2→Task 2 · §4.2a→Task 3 · §4.3→Task 4 · §4.4→Task 5 · §4.5a→Task 6 Step 5 · §4.5b→Task 6. AC1/AC2/AC4/AC7 → post-execution section. AC3→Task 1 Step 5. AC5→Task 5. AC6→Task 2 (the `UR_N > 0` gate is preserved verbatim). AC8→Tasks 2 and 3. AC9/AC10→Task 6. **AC11 has no task** — it pins existing `/setup` behaviour and is verified by reading `SKILL.md:300-340`; folded into Task 6 Step 5's verification rather than given its own task, since it asserts that nothing changed.

**Placeholder scan:** Task 3 Step 3 and Task 6 Step 4 say "verbatim from `<file>:<line>`" rather than inlining ~4 KB of directive text. This is deliberate and is **not** a placeholder — it is a copy instruction with an exact source, and inlining would create a second copy that can drift from the original. The line numbers are pinned to the current HEAD; re-resolve by symbol if the file has moved.

**Type consistency:** `MESSAGES` accumulator, `kt_json_escape`, `KT_*` variable names, and `assert_eq MSG EXPECTED ACTUAL` are used identically across all tasks and match the existing scripts.

**Known gap carried forward:** the TASK BUDGET long variant remains on `systemMessage` and undelivered, by design. It is a defect needing rework, tracked in spec §4.2a, and deliberately not in this plan.
