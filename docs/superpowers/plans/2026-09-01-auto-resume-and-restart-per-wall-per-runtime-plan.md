# `/auto` resume-and-restart per wall and per runtime — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/auto` cover both the usage wall and the context wall in both runtimes, with presence selecting the *mechanism* rather than *whether* a resume is armed.

**Architecture:** Prose-only change to three diverged `skills/auto/SKILL.md` ports plus one new `/setup` knob. No new scripts. Three mechanisms already exist (`CronCreate`, `mcp__scheduled-tasks__create_scheduled_task`, `bin/auto-runloop.sh`) and one runtime classifier already exists (`kt_resolve_account`); this connects them per wall and per runtime instead of hardcoding one default.

**Tech Stack:** Markdown skill definitions; `bin/config.sh` (POSIX sh, read-only here); `permissions.allow` in `~/.claude/settings.json`.

**Spec:** `docs/superpowers/specs/2026-08-31-auto-resume-and-restart-per-wall-per-runtime-design.md` (committed `1de8164`)

**Gate:** `knowledge/logs/prospect/2026-09-01-file-auto-resume-and-restart-per-wall-per-runtime.md` (committed `35e00f7`) — verdict PROCEED-WITH-CHANGES. All three required changes are applied in this plan: **#3 SHRINK** (Task B2 uses a capability check as primary, classifier advisory), **#10 SPLIT** (Phase C is 10a only; 10b is out of scope), **#11 DEFER** (Task D1, blocking nothing in A or B).

## Global Constraints

Exact values copied from the spec. Every task's requirements implicitly include this section.

- **Three ports, diverged.** `plugin-claude-code` (65,104 B, md5 `024e8cbe…`), `plugin-antigravity` (64,895 B, `11abea01…`), `plugin-openai-codex` (52,099 B, `c85bc2f8…`). `plugin-claude-cowork` has no `auto` skill. **No patch applies to more than one port unchanged.**
- **Per-port reason required.** The gate's `census-does-not-license-its-disposition` hit: codex is a trimmed port missing 2 of 4 defect sites, which is evidence it is deliberately reduced. **Every port edit states why that port is being edited.** Never inherit "3 files" from a census as an instruction.
- **D1 — arming condition is UNCHANGED.** Arm whenever work is unfinished and the binding budget is usage. **Not gated on presence. Not gated on `continue`.** `SKILL.md:443/445/447` and config knob 6 must survive untouched.
- **D4 — push is never grantable by any modifier, including `full`.**
- **D11 — no grant may permit a destructive or force-overwriting operation without user approval or
  an explicit stated grant.** (Mike, 2026-09-01.) Binds every entry Task C1 offers. ⛔ A pattern
  whose argument glob permits an exec flag (`--upload-pack`, `--receive-pack`, `--exec`) permits
  the whole destructive class and therefore **fails D11** — verify each proposed pattern against
  its own flag surface, not just against what you intend to run with it. This is how
  `git ls-remote:*` was disqualified.
- **D2 (aria's) — a scheduled prompt never starts with `/`.** Applies to every scheduling mechanism.
- **D8 — no new modifier word.** Nothing new to type in any branch.
- **Routing — `desktop` → Desktop branch · `desktop-unknown` → Desktop branch · `cli` → CLI branch.** `desktop-unknown` means Desktop-with-unresolved-*account*, never unknown-runtime.
- **Capability presence is the authority; the classifier is the hint.**
- **Never modify `bin/config.sh`.** Line 42 is marked `KEEP BYTE-IDENTICAL` with a `statusline-meter.sh` mirror. This plan only reads it.

## File Structure

| File | Responsibility in this plan |
|---|---|
| `plugin-claude-code/skills/auto/SKILL.md` | Canonical port. All of Phase A + Phase B land here first. |
| `plugin-antigravity/skills/auto/SKILL.md` | Near-parity port. Carries 4 of 5 defects. Mirrors A + B. |
| `plugin-openai-codex/skills/auto/SKILL.md` | Trimmed port. Carries 3 of 5 defects. **Mirrors only the defects it actually has.** |
| `plugin-claude-code/skills/setup/SKILL.md` | Gains the Phase C allowlist knob. |
| `~/.claude/settings.json` | **Not edited by this plan.** Phase C ships the knob; the user runs it. |

## Phase ordering — and why

**Phase A is documentation truth. Phase B is the mechanism. A must land first and must be independently committable.**

The gate's frame check found two goals riding together: five documentation corrections (unfalsifiably safe — they replace measured falsehoods) bundled with one mechanism change (resting on a premise validated by a single probe). They share files but not risk profiles. Sequencing truth-first means a stall in B or C cannot hold the corrections hostage.

---

## Phase A — Documentation truth

### Task A1: Correct the port-scope claim

**Why this port set: TWO ports, not three.** ⛔ **CORRECTED AT EXECUTION 2026-09-01 — an earlier
draft of this task said "all three carry the false sentence (measured: `grep -c` = 1 each)". That
was measured on ONE port and inferred for the others; the per-port census script never checked this
defect.** Re-measured: `port only` = claude-code **1**, antigravity **1**, codex **0**. Codex has
**no Runtime-precondition section at all** — it is the trimmed port and omits it.

⇒ **Do NOT edit codex here.** Adding the sentence would *invent* a section that port deliberately
omits, which is the exact failure this plan's Global Constraints forbid ("never inherit '3 files'
from a census as an instruction").

**Files:**
- Modify: `plugin-claude-code/skills/auto/SKILL.md:15`
- Modify: `plugin-antigravity/skills/auto/SKILL.md` (same sentence, different line)
- **Skip:** `plugin-openai-codex/skills/auto/SKILL.md` — no such claim exists

**Interfaces:**
- Consumes: nothing.
- Produces: nothing. Pure correction.

- [ ] **Step 1: Write the failing acceptance check**

```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
for p in plugin-claude-code plugin-antigravity plugin-openai-codex; do
  printf '%-22s %s\n' "$p" "$(/usr/bin/grep -c 'ships in the Claude Code port only' "$p/skills/auto/SKILL.md")"
done
```

- [ ] **Step 2: Run it to confirm it fails**

Expected now: `1` for every port. That is the defect — the sentence is false; two other ports carry the skill.

- [ ] **Step 3: Make the edit, per port**

Replace the clause `**`/auto` ships in the Claude Code port only, and that is deliberate.**` with:

```
**`/auto` ships in three ports — `plugin-claude-code` (canonical), `plugin-antigravity`, and
`plugin-openai-codex` — which have diverged (three distinct md5s as of 2026-09-01). Cowork has no
`auto` skill, which is why this section checks a CAPABILITY and not an ownership: there is no
canonical-owner question to resolve here and nothing to hand off to. Do not restore a redirect to
a Cowork variant.**
```

Keep the rest of the paragraph (the ADR-094 sentence and the do-not-restore warning) intact.

- [ ] **Step 4: Run the check to confirm it passes**

Expected: `0` for every port. Then confirm the replacement landed:

```bash
/usr/bin/grep -c 'ships in three ports' plugin-*/skills/auto/SKILL.md
```

Expected: `1` per port.

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/skills/auto/SKILL.md plugin-antigravity/skills/auto/SKILL.md plugin-openai-codex/skills/auto/SKILL.md
git commit -m "fix(auto): the skill ships in three ports, not one"
```

---

### Task A2: Correct the stale modifier count

**Why this port set: TWO ports, not three.** ⛔ **CORRECTED AT EXECUTION 2026-09-01, and this is the
most instructive correction in the arc. A STRING census is not a DEFECT census.** The sentence
`three stackable modifiers` is present in all three ports — but whether it is *false* depends on
the rest of that file, which the grep never looked at. Measured: claude-code and antigravity have
**4** modifier bullet groups and say **"Six orthogonal axes"**, so their count is stale. **Codex has
exactly 3 bullet groups (`full`, `attended`/`unattended`, `tickets`) and says "Three orthogonal
axes"** — its count is **TRUE and internally consistent**. Editing codex would make it wrong.

**Derived replacement count — not invented.** claude-code/antigravity structure: 4 bullet groups =
**7** modifier tokens (`full`, `attended`, `unattended`, `tickets`, `workflow`, `fanout=<pct>`,
`agents=<N>`), plus the separately-named **On-queue-complete toggle** (`continue`, `stop`) and
**Context-self-restart flag** (`self-restart`) = **10 tokens across 6 axes**.

**Files:**
- Modify: `plugin-claude-code/skills/auto/SKILL.md:137`
- Modify: `plugin-antigravity/skills/auto/SKILL.md:135`
- **Skip:** `plugin-openai-codex/skills/auto/SKILL.md:85` — its count is correct for its own content

- [ ] **Step 1: Write the failing acceptance check**

```bash
/usr/bin/grep -c 'three stackable modifiers' plugin-*/skills/auto/SKILL.md
```

- [ ] **Step 2: Run it to confirm it fails**

Expected now: `1` per port. The bullet list below it has **four** groups / **eight** tokens, and the paragraph ~80 lines later correctly says "Six orthogonal axes."

- [ ] **Step 3: Make the edit**

Replace `Four modes, three stackable modifiers, and a toggle:` with:

```
Four modes, eight stackable modifier tokens across six orthogonal axes, and a toggle:
```

- [ ] **Step 4: Run the check to confirm it passes**

```bash
# expect 0 · 0 · 1 — codex KEEPS its count, which is true for its own 3-group content.
/usr/bin/grep -c 'three stackable modifiers' plugin-*/skills/auto/SKILL.md

# expect 1 · 1 · 0 — the new sentence lands only where the count was stale.
/usr/bin/grep -c 'ten tokens across six orthogonal axes' plugin-*/skills/auto/SKILL.md

# Internal-consistency pin: each port's count sentence must agree with its OWN axes sentence.
# (Case matters — the axes sentence is capitalised. A lowercase grep reads 0 on a healthy file.)
for p in plugin-claude-code plugin-antigravity plugin-openai-codex; do
  f="$p/skills/auto/SKILL.md"
  printf '%-22s groups=%s axes-said=%s\n' "$p" \
    "$(sed -n '/^\*\*Modifiers\*\*/,/orthogonal axes/p' "$f" | /usr/bin/grep -cE '^- \*\*')" \
    "$(/usr/bin/grep -oE '(Three|Six) orthogonal axes' "$f" | head -1)"
done
```

Expected: `groups=4 axes-said=Six orthogonal axes` for claude-code and antigravity;
`groups=3 axes-said=Three orthogonal axes` for codex. **This is the check that would have caught
the mis-scoping** — it compares each file against itself instead of counting a string across files.

- [ ] **Step 5: Commit**

```bash
git add plugin-*/skills/auto/SKILL.md
git commit -m "fix(auto): modifier count agrees with the axis count"
```

---

### Task A3: Stop saying presence arms the resume

**Why this port set:** `unattended` arms the resume` = claude-code **1**, antigravity **1**, codex **0**. `arms its own resume` (config knob 7) = **1 in all three**. So codex gets only the knob-7 edit. This is the per-port reason the Global Constraints demand.

**Files:**
- Modify: `plugin-claude-code/skills/auto/SKILL.md:201` and knob 7 (`:286`)
- Modify: `plugin-antigravity/skills/auto/SKILL.md` (both sites)
- Modify: `plugin-openai-codex/skills/auto/SKILL.md` (knob 7 only)

**Interfaces:**
- Consumes: nothing.
- Produces: the corrected presence semantics that Task B1's table relies on.

- [ ] **Step 1: Write the failing acceptance check**

```bash
for p in plugin-claude-code plugin-antigravity plugin-openai-codex; do
  f="$p/skills/auto/SKILL.md"
  printf '%-22s arms-the-resume=%s  own-resume=%s  ungated-rule=%s\n' "$p" \
    "$(/usr/bin/grep -c 'unattended\` arms the resume' "$f")" \
    "$(/usr/bin/grep -c 'arms its own resume' "$f")" \
    "$(/usr/bin/grep -c 'NOT gated on presence' "$f")"
done
```

- [ ] **Step 2: Run it to confirm it fails**

Expected now: the first two columns non-zero where the sites exist, while `ungated-rule` is already `1`. **The file contradicts itself** — that disagreement is the defect.

- [ ] **Step 3: Make the edits**

At the presence-axis bullet, replace `` `unattended` arms the resume for the usage wall; the context wall needs `self-restart` **explicitly** `` with:

```
`unattended` selects the DURABLE resume mechanism for the usage wall (it does not decide whether
one is armed — see Step 6); the context wall needs `self-restart` **explicitly**
```

At config knob 7, replace `(nobody is reachable; residuals are carried to the handoff and the run arms its own resume)` with:

```
(nobody is reachable; residuals are carried to the handoff, and the resume — armed on its own
condition per knob 6 — uses the DURABLE mechanism rather than a session-only one)
```

- [ ] **Step 4: Run the check to confirm it passes**

```bash
/usr/bin/grep -c 'arms the resume\|arms its own resume' plugin-*/skills/auto/SKILL.md   # expect 0

# D1 survival — assert the SENTENCE verbatim, not its occurrence count.
# (Gate 2 / ADR 2026-015: a count is satisfied by a rewrite that keeps the phrase
#  while inverting the claim around it.)
for p in plugin-claude-code plugin-antigravity plugin-openai-codex; do
  f="$p/skills/auto/SKILL.md"
  printf '%-22s %s\n' "$p" "$(/usr/bin/grep -qF 'Arming is NOT gated on presence, and NOT gated on `continue`.' "$f" && echo INTACT || echo 'ALTERED — STOP')"
done
```

The second check is the one that matters: **D1's ungated rule must survive this task untouched.**
Expected `INTACT` for every port that carries the sentence. **Mutation check:** reword any part of
that sentence and this must print `ALTERED — STOP`. A count-based version of this guard passes
under exactly the rewrite it exists to catch.

- [ ] **Step 5: Commit**

```bash
git add plugin-*/skills/auto/SKILL.md
git commit -m "fix(auto): presence selects the resume mechanism, never whether one is armed"
```

---

### Task A4: Document the approval-stall trap

**Why this port set:** measured **0 of 3** ports document it. It is the silent-failure mode of the whole Desktop path, so every port that can reach a Desktop durable mechanism needs it.

**Files:**
- Modify: all three `skills/auto/SKILL.md` — inside Step 6, directly beneath the mechanism table

- [ ] **Step 1: Write the failing acceptance check**

⛔ **CORRECTED AT EXECUTION 2026-09-01.** The original check grepped `permission gate` and
`not allowlisted` — **phrases from a draft of the block, not the wording that shipped.** An
acceptance check written against text you have not finalised tests your memory of your intention.
Grep the marker phrases that actually exist:

```bash
for pat in 'SILENT FAILURE MODE' 'DISPATCH oracle' 'list_scheduled_tasks' 'D11 — a pattern'; do
  printf '%-24s ' "$pat"; /usr/bin/grep -c "$pat" plugin-*/skills/auto/SKILL.md | tr '\n' ' '; echo
done
# Structural check — the whole block, not one phrase:
for p in plugin-claude-code plugin-antigravity plugin-openai-codex; do
  printf '%-22s block lines: %s\n' "$p" \
    "$(sed -n '/SILENT FAILURE MODE/,/^\*\*Selection rule/p' "$p/skills/auto/SKILL.md" | wc -l | tr -d ' ')"
done
```

⚠ **Instrument note, worth carrying:** while diagnosing the failing check I asserted BSD `grep`
lacked GNU BRE alternation. **That diagnosis was wrong** — the ERE form read 0 as well. And the
"positive control" I ran could not have told me: a `0` from the BRE form is equally consistent with
*"BRE alternation is literal"* and *"the phrase is not in the file"*. **A control that cannot
discriminate between the two live hypotheses is not a control.**

- [ ] **Step 2: Run it to confirm it fails**

Expected now: `0` per port.

- [ ] **Step 3: Add the trap block**

Insert beneath Step 6's mechanism table:

```
⛔ **THE SILENT FAILURE MODE — read before arming a durable resume.** A scheduled task stalls on
the first Bash call that is **not** in `permissions.allow`: it fires, sets `lastRunAt`, flips
`enabled: false`, and executes NOTHING. Measured two-sided 2026-08-31 — an unallowlisted command
(`printf`) stalled with a `tool_use` and no `tool_result` anywhere in its transcript; an
allowlisted one (`ls`) executed normally, cold and unattended.

⇒ **`lastRunAt` is a DISPATCH oracle, not a success oracle.** A stalled task reports as having run
and is never retried. **Verify a resume by an artifact the task itself produces.**

⇒ Satisfy the precondition once, via `/setup` (it installs a narrow allowlist). "Run now" also
captures approvals but needs a human, so it does not serve a cold unattended run. A **recurring**
task does not help either: approvals inherit forward only when a human GRANTED them, so recurring
relocates the human step rather than removing it.

⚠ `ls ~/.claude/scheduled-tasks/` is not a registration oracle — de-registering a task leaves its
`SKILL.md` on disk by design. Use `list_scheduled_tasks`.
```

- [ ] **Step 4: Run the check to confirm it passes**

Expected: non-zero per port. Then confirm the oracle correction specifically:

```bash
/usr/bin/grep -c 'DISPATCH oracle' plugin-*/skills/auto/SKILL.md   # expect 1 per port
```

- [ ] **Step 5: Commit**

```bash
git add plugin-*/skills/auto/SKILL.md
git commit -m "docs(auto): document the scheduled-task approval stall and its dispatch-vs-success oracle"
```

---

### Task A5: Phase A holistic check

The gate's `per-task-review-blind-spot-needs-final-holistic-pass` applies: A1–A4 each touched the same three files.

- [ ] **Step 1: Confirm no self-contradiction remains**

```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
for p in plugin-claude-code plugin-antigravity plugin-openai-codex; do
  f="$p/skills/auto/SKILL.md"
  echo "--- $p"
  for pat in 'ships in the Claude Code port only' 'three stackable modifiers' 'arms the resume' 'arms its own resume'; do
    printf '  %-40s %s\n' "$pat" "$(/usr/bin/grep -c "$pat" "$f")"
  done
  printf '  %-40s %s\n' 'NOT gated on presence (must be 1)' "$(/usr/bin/grep -c 'NOT gated on presence' "$f")"
done
```

Expected: first four all `0`; the last `1`.

- [ ] **Step 2: Confirm Phase A changed no mechanism**

⛔ **Before Task A1's first edit, capture the base — do not use a commit-count-relative range.**
`HEAD~4` assumes Phase A lands as exactly four commits; a task split, an extra fixup, or a parallel
session's commit silently moves the window and this assertion becomes vacuous. This repo had 4
unpushed commits from 3 sessions when the plan was written.

```bash
# Run this ONCE, before Task A1:
git rev-parse HEAD > /tmp/phaseA-base.sha      # or note it in the session log
# Also capture the pre-Phase-A mechanism baseline, so "unchanged" has something to compare to:
/usr/bin/grep -c 'create_scheduled_task' plugin-*/skills/auto/SKILL.md > /tmp/phaseA-mech.txt
```

```bash
# Run this at A5:
BASE=$(cat /tmp/phaseA-base.sha)
git diff "$BASE"..HEAD --stat -- plugin-claude-code/skills/auto/SKILL.md \
  plugin-antigravity/skills/auto/SKILL.md plugin-openai-codex/skills/auto/SKILL.md
echo "--- files changed OUTSIDE the three ports (expect none):"
git diff "$BASE"..HEAD --name-only | /usr/bin/grep -v 'skills/auto/SKILL.md' || echo "(none)"
echo "--- mechanism baseline diff (expect identical):"
/usr/bin/grep -c 'create_scheduled_task' plugin-*/skills/auto/SKILL.md | diff /tmp/phaseA-mech.txt - && echo "UNCHANGED" || echo "MOVED — Phase A leaked mechanism work"
```

Expected: only the three `SKILL.md` files changed, nothing outside them, and `UNCHANGED` on the
mechanism baseline — Phase A is truth-only. **Note the pre-capture is what makes "unchanged"
checkable at all**; without it the count has nothing to be compared against and the check is a
printout, not a test.

- [ ] **Step 3: Commit if anything was corrected**

```bash
git add -p
git commit -m "fix(auto): Phase A holistic pass"
```

---

## Phase B — The mechanism

### Task B1: Re-key Step 6 per wall and per runtime

**Files:**
- Modify: `plugin-claude-code/skills/auto/SKILL.md` Step 6 (table + Selection rule, canonical `:449-458`)
- Modify: the same section in both other ports

**Interfaces:**
- Consumes: Task A3's corrected presence semantics.
- Produces: the mechanism-selection table that Task B2's probe feeds and Task B3's Desktop branch cites.

- [ ] **Step 1: Write the failing acceptance check**

```bash
f=plugin-claude-code/skills/auto/SKILL.md
printf 'default-CronCreate-claim=%s  selection-table=%s\n' \
  "$(/usr/bin/grep -c 'CronCreate\` is the \*\*baseline and stays the default' "$f")" \
  "$(/usr/bin/grep -c 'presence selects the mechanism' "$f")"
```

- [ ] **Step 2: Run it to confirm it fails**

Expected now: the default-CronCreate claim present, the selection table absent.

- [ ] **Step 3: Replace the Selection rule with the presence×runtime table**

```
**Selection rule — the WALL picks the timing, PRESENCE picks the mechanism, the RUNTIME picks
what is available.** Arming is decided by D1's condition and nothing here changes it.

| Presence | Runtime | Mechanism | Why |
|---|---|---|---|
| `unattended` | Desktop-class | `create_scheduled_task` (`fireAt`) | nobody keeps the app open or the Mac awake |
| `unattended` | CLI | `launchd` if installed, else `CronCreate` **and state the exposure** | no `scheduled-tasks` verb on the CLI |
| `attended` | either | `CronCreate` | the session is being watched |

⛔ **Never default a CLI user to a Desktop mechanism.** That constraint is inherited verbatim from
the 2026-07-30 design and is the reason this is a probe and not a default. What changed is a
premise that design never examined — *"an unattended run keeps its session open by design"* —
which Mac sleep, app auto-update, crash and OS restart each falsify.
```

- [ ] **Step 4: Run the check to confirm it passes**

```bash
/usr/bin/grep -c 'presence selects the mechanism' plugin-*/skills/auto/SKILL.md   # expect 1 per port
/usr/bin/grep -c 'Never default a CLI user' plugin-*/skills/auto/SKILL.md          # expect 1 per port
```

- [ ] **Step 5: Commit**

```bash
git add plugin-*/skills/auto/SKILL.md
git commit -m "feat(auto): select the resume mechanism by presence and runtime, not one default"
```

---

### Task B2: Capability-first runtime probe (gate SHRINK applied)

**The gate shrank this task.** The spec's D3 proposed reusing `kt_resolve_account()`. The gate's finding: the spec already states *capability presence is the authority*, so spending a `config.sh` dependency to restate it adds a second consumer to a file marked `KEEP BYTE-IDENTICAL`. **Capability check is primary; the classifier is advisory only and optional.**

**Files:**
- Modify: all three `skills/auto/SKILL.md`, Step 6, directly above Task B1's table

**Interfaces:**
- Consumes: Task B1's table (it is what the probe selects from).
- Produces: nothing consumed downstream — this is a prose instruction, not an API.

- [ ] **Step 1: Write the failing acceptance check**

```bash
/usr/bin/grep -c 'is the verb callable' plugin-*/skills/auto/SKILL.md
```

- [ ] **Step 2: Run it to confirm it fails** — expected `0` per port.

- [ ] **Step 3: Add the probe instruction**

```
**Resolving the runtime — probe the CAPABILITY, never the name.** The only question that decides
the mechanism is *is the verb callable here?* Check for `create_scheduled_task`; if it is present
this is a Desktop-class runtime and the durable mechanism is available. If it is absent, take the
CLI row — **including when other signals say Desktop.** Availability, not identity, is the
authority, which is what makes a misread classification unable to select an absent mechanism.

⚠ Optional corroboration only: `kt_resolve_account()` (`bin/config.sh`) returns `{cli, desktop,
desktop-unknown}`. If you consult it, note that **`desktop-unknown` means Desktop with an
unresolved ACCOUNT — it is a Desktop-class value, not an unknown runtime**, so it takes the
Desktop row. ⛔ Never modify that function; its first block is kept byte-identical with a
statusline mirror.
```

- [ ] **Step 4: Run the check to confirm it passes**

```bash
/usr/bin/grep -c 'is the verb callable' plugin-*/skills/auto/SKILL.md         # expect 1 per port
/usr/bin/grep -c 'unresolved ACCOUNT' plugin-*/skills/auto/SKILL.md          # expect 1 per port
```

The second grep is the mutation guard for the error the spec's own first draft made — routing `desktop-unknown` to CLI. Revert that sentence and the check goes red.

- [ ] **Step 5: Commit**

```bash
git add plugin-*/skills/auto/SKILL.md
git commit -m "feat(auto): resolve the runtime by capability, with the classifier advisory only"
```

---

### Task B3: Add the Desktop context-wall branch

**Files:**
- Modify: `plugin-claude-code/skills/auto/SKILL.md` Step 3¾ (canonical `:404`)
- Modify: `plugin-antigravity/skills/auto/SKILL.md` Step 3¾
- **Skip codex — and the real reason is better than the one this plan first gave.** ⛔ **CORRECTED AT
  EXECUTION 2026-09-01:** the draft said codex "has no Step 3¾ claim to correct… editing it would
  invent a section the port deliberately omits." Measured: codex **does have Step 3¾**
  (`grep -c 'Context-self-restart across a fresh process'` = 1); only the "only autonomous path"
  sentence is absent. **Its Step 3¾ is a deliberate DEGRADATION NOTICE** — *"a skill cannot launch
  a fresh Codex task or reset its own context, so `self-restart` degrades to the normal Step 3
  path… do not write the Claude restart signal or promise an automatic restart."*
  ⇒ Adding a Desktop-class branch there would promise a capability the Codex runtime does not have
  (no wrapper **and** no `scheduled-tasks` verb) — which that port's own text explicitly forbids.
  **Skip stands; the reason is a live constraint, not an absent section.**

- [ ] **Step 1: Write the failing acceptance check**

```bash
/usr/bin/grep -c 'only autonomous path to clean context' plugin-claude-code/skills/auto/SKILL.md plugin-antigravity/skills/auto/SKILL.md
```

- [ ] **Step 2: Run it to confirm it fails**

Expected now: `1` each. The claim is false on Desktop, and the file's own Step 6 table contradicts it with a `Fresh context: Yes` row.

- [ ] **Step 3: Replace the claim and add the branch**

Replace `The only autonomous path to clean context is a **fresh `claude` process**, which an external wrapper provides.` with:

```
On the **CLI** the only autonomous path to clean context is a fresh `claude` process, which the
external wrapper provides. On a **Desktop-class runtime there is a second path and no wrapper is
needed**: a scheduled task starts with no memory of the conversation, so scheduling one a couple of
minutes out and stopping cleanly IS a fresh-context relaunch.

**Desktop-class branch** (take this when `create_scheduled_task` is callable):
1. AUTO-run `/extract`.
2. Run `/handoff` for a prose-first opener. ⛔ Prose-first is mandatory — a leading slash command
   is parsed as an unknown command and the whole mandate is silently discarded.
3. `create_scheduled_task` with `fireAt` ≈ now + 2 minutes and the opener as the prompt.
4. Stop cleanly.

⚠ This branch inherits the approval precondition in Step 6: if the arc's Bash patterns are not
allowlisted, the resumed task stalls silently. Report availability in the arc contract; never arm
a path that will stall.
```

- [ ] **Step 4: Run the check to confirm it passes**

```bash
/usr/bin/grep -c 'only autonomous path to clean context' plugin-claude-code/skills/auto/SKILL.md plugin-antigravity/skills/auto/SKILL.md  # expect 0
/usr/bin/grep -c 'Desktop-class branch' plugin-claude-code/skills/auto/SKILL.md plugin-antigravity/skills/auto/SKILL.md                    # expect 1
/usr/bin/grep -c 'Desktop-class branch' plugin-openai-codex/skills/auto/SKILL.md                                                           # expect 0
```

The third check is the deliberate-skip guard: codex must NOT gain this branch.

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/skills/auto/SKILL.md plugin-antigravity/skills/auto/SKILL.md
git commit -m "feat(auto): Desktop gains a context-wall path; the wrapper is the CLI-only route"
```

---

### Task B4: Report durable-resume availability in the arc contract

**Files:**
- Modify: all three `skills/auto/SKILL.md`, Step 0.5 contract block

- [ ] **Step 1: Write the failing acceptance check**

```bash
/usr/bin/grep -c 'durable resume:' plugin-*/skills/auto/SKILL.md
```

- [ ] **Step 2: Run it to confirm it fails** — expected `0` per port.

- [ ] **Step 3: Add the contract line**

Add to the Step 0.5 contract block, beside the existing `Usage:` line:

```
> **Durable resume:** <ARMED via <mechanism> | UNAVAILABLE (patterns not allowlisted — run `/setup`)>
```

- [ ] **Step 4: Run the check to confirm it passes, and confirm the ABSENT path is specified**

```bash
/usr/bin/grep -c 'durable resume:' plugin-*/skills/auto/SKILL.md          # expect 1 per port
/usr/bin/grep -c 'UNAVAILABLE (patterns not allowlisted' plugin-*/skills/auto/SKILL.md   # expect 1 per port
```

The second grep matters because of the gate's `precondition-placed-after-its-consumer` hit: the reporting must cover the **absent-allowlist** path, not only the present one.

- [ ] **Step 5: Commit**

```bash
git add plugin-*/skills/auto/SKILL.md
git commit -m "feat(auto): the arc contract reports durable-resume availability, not just that a resume is armed"
```

---

## Phase C — The `/setup` allowlist knob (10a only)

✅ **PREMISE STATUS: R2 RAN AND PASSED — 2026-09-01 01:22 JST. Recorded here so no executor needs
an ephemeral file.** The pending-branch version of this block pointed at
`/private/tmp/…/tasks/*.output`, which will not exist for a later reader — a check whose subject
has vanished. Result recorded instead:

- **Probe 2** (2026-08-31): bare-builtin pattern `Bash(ls:*)`, command `ls -1 …` → **EXECUTED**
  (`tool_result` `is_error=False`, real directory listing). Transcript `52c058ac…jsonl`.
- **R2** (2026-09-01): git-subcommand pattern `Bash(git log:*)`, command `git log --oneline -1` →
  **EXECUTED** (`tool_result` `is_error=False`, output `70f5870 docs(memory): …`). Transcript
  `cd55b518…jsonl`, 28 records.

⇒ **Hypothesis A holds across TWO pattern shapes** — a bare-builtin `:*` and a
subcommand-qualified `git <sub>:*`. That is the shape Phase C's `git merge-base:*` /
`git ls-remote:*` entries need.

⚠ **The bound, stated rather than rounded up to "validated":** two shapes, one runtime, two
moments. Untested shapes include a fully-literal pattern (no `:*`) and a quoted-compound pattern.
Neither is needed by Phase C, so this is a named bound, not a blocker.

⚑ Incidental operational fact from R2: a scheduled task runs with **cwd =
`/Users/mikeprasad/Projects`** (the bare `git log` resolved against the root repo). So a
cwd-dependent command works but silently binds to the root repo, not a sub-repo — prefer absolute
paths in any scheduled prompt.

### Task C1: Add the knob

**Files:**
- Modify: `plugin-claude-code/skills/setup/SKILL.md`
- **Not** the other ports — `/setup` is Code-only for this purpose; confirm with
  `ls plugin-*/skills/setup/SKILL.md` before assuming.

**Interfaces:**
- Consumes: Task B4's contract line (the knob is what flips it from UNAVAILABLE to ARMED).
- Produces: a documented, enumerable pattern set that `/audit-config` can later diff.

- [ ] **Step 1: Re-confirm the premise still holds (it held on 2026-09-01)**

The PREMISE STATUS block above records both probes as EXECUTED, so this step is a **staleness
re-check, not a first measurement.** The permission surface is user-editable and the runtime
updates, so confirm the two patterns Phase C depends on are still allowlisted before writing:

```bash
python3 - <<'PY'
import json
need={"git merge-base","head","tail"}   # git ls-remote DROPPED: already allowlisted AND exec-capable (Step 4)
have=set()
for p in ["/Users/mikeprasad/.claude/settings.json",
          "/Users/mikeprasad/Projects/.claude/settings.local.json"]:
    try: d=json.load(open(p))
    except FileNotFoundError: continue
    for a in (d.get("permissions",{}).get("allow") or []):
        if isinstance(a,str) and a.startswith("Bash("):
            have.add(a[5:-1].split(":")[0])
print("already allowlisted:", sorted(need & have))
print("still to add:      ", sorted(need - have))
PY
```

Expected on a clean run: all four in `still to add` (the knob has not been run yet). If any are
already present, the knob offers only the remainder — never re-add a duplicate.

⛔ If you need to re-measure the premise itself rather than the allowlist, do NOT reason about it:
create a one-shot `fireAt` task ~3 min out whose prompt runs a single allowlisted command, then
read its transcript for a `tool_result`. Presence of `tool_result` is the oracle; `lastRunAt` is
not (a stalled task sets it anyway).

- [ ] **Step 2: Write the failing acceptance check**

```bash
/usr/bin/grep -c 'arc-resume allowlist' plugin-claude-code/skills/setup/SKILL.md
```

Expected: `0`.

- [ ] **Step 3: Add the knob**

```
### Arc-resume allowlist (optional)

An unattended `/auto` resume on a Desktop-class runtime runs as a scheduled task, which stalls
silently on any Bash call absent from `permissions.allow`. Offer to add this **narrow, read-only**
set — measured as the exact delta between an arc's working set and what is already allowlisted
(15 of 21 commands were already covered):

    Bash(head:*)
    Bash(tail:*)
    Bash(git merge-base:*)

⛔ A fourth was proposed and is **DROPPED, resolved 2026-09-01** — `Bash(git ls-remote:*)`. Two
independent reasons: it is **already allowlisted** as `Bash(git ls-remote *)`, and it is **not
read-only** (`--upload-pack` executes an arbitrary command — measured). See the resolution note at
Step 4. Step 4's set assertion expects exactly the three above and will report DRIFT if a fourth
appears.

⛔ Do NOT offer `Bash(sh:*)` or `Bash(bash:*)`. Bare shell access is an escape hatch that nullifies
the allowlist (`sh -c '<anything>'`). If a helper must run, scope it:
`Bash(sh */plugin-claude-code/bin/*.sh:*)`.

⚠ State plainly that an allowlist widens standing permissions for **every** session, not only
scheduled ones. Show the four lines and require an explicit yes. Never widen silently.

⚠ Enumerate what is added so `/audit-config` can diff it later. An allowlist that is only ever
appended to is how a 161-entry list happens with nobody having decided the total.
```

✅ **HOLD RESOLVED 2026-09-01 — there is no fourth pattern to add, and the reason matters more than
the omission.**

**(1) It is already allowlisted.** `Bash(git ls-remote *)` exists in
`Projects/.claude/settings.local.json`. An earlier census reported it missing because the matcher
handled only the `Bash(cmd:*)` colon idiom and not the `Bash(cmd *)` space idiom — see
`characterised-from-memory-of-an-earlier-read` for the class. **Re-censused with both idioms:
`head`, `tail`, `git merge-base` are genuinely missing; `git ls-remote` is not.**

**(2) It was never read-only.** ⛔ **Measured 2026-09-01:
`git ls-remote --upload-pack='<any command>' .` EXECUTES that command locally** (probe printed the
injected marker). So `Bash(git ls-remote:*)` is **arbitrary command execution** — functionally the
`Bash(sh:*)` escape hatch this same task bans. The spec's and Step 3's "read-only, trivially safe"
description was **false** and is retracted here.

⇒ **C1 ships exactly three patterns.** Do not add a `git ls-remote` entry under any spelling.

⚠ The same flag family reaches further than this task — see Task D2, which this finding reframes.

- [ ] **Step 4: Run the check to confirm it passes — assert the SET, never a count**

```bash
f=plugin-claude-code/skills/setup/SKILL.md
/usr/bin/grep -c 'arc-resume allowlist' "$f"   # expect >=1 — presence only, no semantics claimed

# The `sh` line must be the BAN, not an offer. A count cannot separate those, so match the form:
/usr/bin/grep -qE 'Do NOT offer .*Bash\(sh:\*\)' "$f" && echo "BAN present" || echo "BAN MISSING — STOP"

# Assert the offered SET equals exactly what was decided (ADR 2026-015 Component 1):
python3 - <<'PY'
import re
txt=open("plugin-claude-code/skills/setup/SKILL.md").read()
m=re.search(r'^### Arc-resume allowlist.*?(?=^### |\Z)', txt, re.M|re.S)
offered=set(re.findall(r'^\s{4}(Bash\([^)]*\))\s*$', m.group(0), re.M))
expected={"Bash(head:*)","Bash(tail:*)","Bash(git merge-base:*)"}   # ls-remote HELD, see above
print("offered :", sorted(offered))
print("expected:", sorted(expected))
print("VERDICT :", "SET MATCHES" if offered==expected else f"DRIFT — extra={sorted(offered-expected)} missing={sorted(expected-offered)}")
PY
```

Expected: `BAN present` and `SET MATCHES`. **Mutation checks — run both:** add a fifth pattern to
the block and the set assertion must report `DRIFT`; reword the `Do NOT offer` line and the ban
check must report `BAN MISSING`. A count-based version of either passes under the exact change it
exists to catch.

- [ ] **Step 4b: Ship the ratchet, not just the knob**

The set assertion above is the ratchet — **commit it as a runnable check, not as prose in this
plan**, so a fifth pattern is a visible diff rather than a silent append. Home it wherever
`/audit-config` will actually invoke it; a check nobody runs is worth nothing.

**Why this is mandatory rather than nice-to-have:** this user's allowlist has grown to **161 Bash
entries with nobody having decided that total** — an append-only knob is how 162 happens. This is
`registry-allowlist-discipline`'s counter-discipline verbatim ("add a schema test asserting the two
surfaces match") reaching its first cross-project instance.

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/skills/setup/SKILL.md
git commit -m "feat(setup): offer a narrow arc-resume allowlist, three read-only patterns + a set ratchet"
```

---

## Phase D — Deferred (do not execute without its own gate)

### Task D1: Resolve cross-scope permission precedence — DEFERRED (gate #11)

Project `settings.local.json` **allows** `Bash(git push:*)`; user `settings.json` **asks**. For an
unattended task the two resolutions are *push silently* and *hang silently*, and D4 forbids the
first. **Read current Claude Code docs on allow/ask/deny precedence across user vs project scope**
(Rule 33 — current docs, not memory). Blocks nothing in Phase A or B; blocks any claim that D4 is
enforced by permissions rather than by prose.

### Task D2: The pre-existing entries — OUT OF SCOPE, but REFRAMED 2026-09-01

⛔ **"Wide" understates it. Three already-allowlisted git families permit ARBITRARY COMMAND
EXECUTION, verified by probe 2026-09-01:**

| Already allowlisted | Exec flag | Verified |
|---|---|---|
| `Bash(git push:*)` · `Bash(git push *)` | `--receive-pack=<cmd>` | injected marker printed |
| `Bash(git fetch:*)` | `--upload-pack=<cmd>` | injected marker printed |
| `Bash(git ls-remote *)` | `--upload-pack=<cmd>` | injected marker printed |

Each is functionally equivalent to `Bash(sh:*)` — the grant Task C1 explicitly bans. `Bash(ssh *)`
and `Bash(curl *)` remain wide in the ordinary sense.

⚑ **Consequence for this arc's own design:** the spec's **D4** — *"push is never grantable by any
modifier, including `full`"* — is enforced **only by the skill's prose.** The permission layer
already grants something strictly worse than push: arbitrary execution, which can then push. That
does not make D4 wrong; it makes D4 the *sole* control, which is worth knowing before relying on it
for an unattended run.

⚠ **Candidate remedy, NOT verified — do not implement from this note.** `deny` outranks `allow`, and
this user's deny list already uses mid-command globs (`Bash(git push --force *)`,
`Bash(curl * | bash)`), so denials on `--upload-pack` / `--receive-pack` / `--exec` would plausibly
close the vector while leaving every normal git command working. **Untested:** whether a `deny`
pattern actually matches a flag mid-command. Verify before proposing it.

**Still out of scope for this arc** — it is Mike's config, narrowing affects every session, and his
stated preference on the pre-existing entries was to accept documented exposure. The reframing
changes what is being accepted, so it warrants a fresh look; it does not change the ownership.

---

## Self-Review

**1. Spec coverage.** D1 → Global Constraints + A3 Step 4 guard. D2 → B1. D3 → B2 (shrunk per gate).
D4 → B3. D5 → B4. D6 → A4 + B4. D7 → A4 (the dispatch-vs-success oracle). D8 → Global Constraints
(no task adds a word; A2 only corrects a count). D9 → A1. D10 → C1. **All ten decisions map to a
task.** ACs: AC1→A2, AC2→A3, AC3→B3, AC4→A4, AC5→A1, AC6→B2, AC7→B4, AC8 → ⚠ **no task** —
AC8 asserts the prose-first hook still matches both scheduling verbs after the edits. **Gap found
and closed:** added as A5 Step 2's companion below.

- [ ] **A5 Step 2b (added by self-review): confirm the D2 hook still matches both verbs**

```bash
python3 -c "
import json; d=json.load(open('plugin-claude-code/.claude-plugin/plugin.json'))
print(d['hooks']['PreToolUse'][4]['matcher'])"
```

Expected: `CronCreate|mcp__scheduled-tasks__create_scheduled_task`, unchanged. This plan adds no
guard and must not disarm the existing one.

**2. Placeholder scan.** No TBD/TODO. Every prose edit carries its actual replacement text; every
step carries a runnable command with an expected value. Phase C's pending input is a *specified
branch*, not a placeholder — both outcomes have a defined action.

**3. Type consistency.** No code symbols introduced. Cross-task names checked: `create_scheduled_task`
(B1/B2/B3/A4), `kt_resolve_account` (B2 only, read-only), `lastRunAt` (A4), `desktop-unknown` (B2),
`durable resume:` (B4/C1) — all spelled identically across tasks.
