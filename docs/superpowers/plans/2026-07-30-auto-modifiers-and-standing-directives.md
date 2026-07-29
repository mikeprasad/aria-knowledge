# `/auto` Modifiers, Standing Directives & Mechanical Guards — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `/auto` a modifier vocabulary (`full` · `loop` · `tickets`) and seven always-on standing directives, remove its vendor lock, and escalate three recurring prose-only guards to mechanical hooks — shipped as one version, committed as three separable deliverables.

**Architecture:** Deliverable A is prose-only edits to a single `SKILL.md`, validated by grep-against-contract assertions in the existing repro harness. Deliverables B and C add POSIX-sh hook scripts registered in `plugin.json`, each with a repro that observes the guard going RED before it is trusted. Nothing new is invented: modifiers pre-set knobs the skill's own Step 0¾ already enumerates, the tracker probe mirrors `/digest`, and the hooks copy `bash-cd-check.sh`'s stdin idiom and `pre-edit-check.sh`'s deny idiom.

**Tech Stack:** POSIX `sh` (hooks + tests, no `jq`, no bashisms), Markdown (`SKILL.md`), JSON (`plugin.json`).

## Global Constraints

- **Public repository.** Zero personal info, secrets, internal URLs, or vendor lock-in in any shipped file.
- **POSIX sh only** in `bin/` and `tests/`. Existing hooks parse JSON with `grep -o` / `sed`, never `jq`. Match that.
- **Gate B budget: 18,944 bytes.** Live before this change: 18,938 (6 B headroom). `/auto`'s description is 1,232 B. Trim ≥150 B from it in Task 3 so the net stays ≤ 18,938. `argument-hint` is NOT counted (Gate B's awk stops at the next top-level key).
- **Ports: none.** `/auto` and Bash hooks are Claude-Code-canonical. Do not touch `plugin-claude-cowork/`, `plugin-openai-codex/`, `plugin-cursor-template/`, or `plugin-antigravity/`.
- **Never `git add -A`.** Stage named paths only.
- **Gate before commit on the bare exit code.** Run the suite, READ green, then commit. Never chain `&& git commit` after a non-test command.
- **`knowledge_folder` resolution:** always from `~/.claude/aria-knowledge.local.md`. A literal `~/knowledge/` is a defect (the v2.40.2 phantom-path bug).
- **Version:** bump `plugin-claude-code/.claude-plugin/plugin.json` `2.42.0` → `2.43.0` in Task 8 only.

---

## File Structure

| File | Responsibility | Deliverable |
|---|---|---|
| `plugin-claude-code/skills/auto/SKILL.md` | All prose: standing directives, modes, modifiers, declass, ledger, scheduling tiers, frontmatter | A |
| `tests/repros/auto-modes.sh` | Contract assertions for every A change | A |
| `plugin-claude-code/bin/pre-cron-check.sh` | **New.** PreToolUse deny on a `/`-leading scheduled prompt | B |
| `tests/repros/cron-slash-guard.sh` | **New.** Drives the hook; must observe RED | B |
| `plugin-claude-code/bin/pre-bash-write-check.sh` | **New.** PreToolUse warn on shell writes that bypass Edit/Write | C |
| `plugin-claude-code/bin/post-edit-tautology-check.sh` | **New.** PostToolUse warn on syntactically-tautological assertions | C |
| `tests/repros/lapse-guards.sh` | **New.** Drives both C hooks; must observe RED | C |
| `plugin-claude-code/.claude-plugin/plugin.json` | Hook registration (B, C) + version bump (Task 8) | B, C |
| `CHANGELOG.md` | Release entry | Task 8 |

---

# Deliverable A — `/auto` prose

## Task 1: Standing Directives block (D1–D7) + arc-contract lines

**Files:**
- Modify: `plugin-claude-code/skills/auto/SKILL.md` (insert a block before `## Step 0`; extend the Step 0.5 contract at ~line 99-106)
- Test: `tests/repros/auto-modes.sh`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: the literal heading `## Standing Directives` and the seven labels `**D1`…`**D7` — Tasks 2, 3, 4 cross-reference these IDs. The ledger path token `logs/auto/` is produced here and referenced nowhere else.

- [ ] **Step 1: Write the failing assertions**

Append to `tests/repros/auto-modes.sh`, immediately before the final `printf` summary line:

```sh
# SD: standing directives block exists with all seven directives
grep -qF '## Standing Directives' "$SK" \
  && ok "SD block present" || bad "SD block" "no '## Standing Directives' heading"
for d in D1 D2 D3 D4 D5 D6 D7; do
  grep -qF "**$d" "$SK" && ok "SD directive: $d" || bad "SD $d" "not in SKILL.md"
done

# SD-D1: 5h binds, 7d ignored, two distinct thresholds
grep -qiE '7[- ]day.*ignor|ignor.*7[- ]day' "$SK" \
  && ok "SD D1 ignores 7-day" || bad "SD D1 7d" "7-day not explicitly ignored"
grep -qF '90%' "$SK" && ok "SD D1 90% arm threshold" || bad "SD D1 90" "no 90% threshold"
grep -qF '95%' "$SK" && ok "SD D1 95% pause threshold" || bad "SD D1 95" "no 95% pause"
grep -qiE 'no statusline|not visible|desktop' "$SK" \
  && ok "SD D1 no-statusline caveat" || bad "SD D1 caveat" "no ask-when-invisible rule"

# SD-D7: judgment ledger contract
grep -qiF 'judgment ledger' "$SK" \
  && ok "SD D7 ledger named" || bad "SD D7 name" "ledger not named"
grep -qF 'logs/auto/' "$SK" \
  && ok "SD D7 ledger path" || bad "SD D7 path" "no logs/auto/ path"
grep -qF 'knowledge_folder' "$SK" \
  && ok "SD D7 resolves knowledge_folder" || bad "SD D7 resolve" "path not config-resolved"
grep -qF '~/knowledge/' "$SK" \
  && bad "SD D7 phantom path" "literal ~/knowledge/ present (v2.40.2 defect)" \
  || ok "SD D7 no phantom path"
for t in "Validated" "Deterministic" "Traced" "Confirmed after"; do
  grep -qF "$t" "$SK" && ok "SD D7 test: $t" || bad "SD D7 $t" "four-part test incomplete"
done
grep -qiE '0 judgment calls|empty ledger' "$SK" \
  && ok "SD D7 empty-ledger stated" || bad "SD D7 empty" "empty ledger not stated"

# SD: arc contract surfaces the retyped clauses
grep -qiE 'Judgment ledger:' "$SK" \
  && ok "SD contract shows ledger" || bad "SD contract ledger" "not in arc contract"
grep -qiE 'never pre-authorized|never grantable' "$SK" \
  && ok "SD contract push-never-granted" || bad "SD contract push" "push grant not excluded"
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/repros/auto-modes.sh`
Expected: FAIL lines beginning `FAIL  SD block`, `FAIL  SD D1` … and a nonzero failed count in the summary.

- [ ] **Step 3: Write the Standing Directives block**

Insert immediately above `## Step 0: Parse mode, posture, and the queue-complete toggle`:

```markdown
## Standing Directives — always on, never need asking for

These bind every `/auto` run in every mode. They are not modifiers and cannot be turned off.

- **D1 — Usage: the 5-hour figure binds; the 7-day figure is ignored.** When a statusline is
  visible, gate only on the 5-hour number. The 7-day number is never a reason to slow,
  shrink, defer, or stop. At **90% 5h**, arm or re-arm the resume schedule (Step 6). At
  **95% 5h**, PAUSE: checkpoint, commit, then wait for the reset if a resume is armed, else
  `/handoff`. When no statusline is visible (desktop runtime), do not infer a number and do
  not gate on one — ask.
- **D2 — A scheduled prompt never starts with `/`.** Applies to every scheduling mechanism.
  A leading `/token` is parsed as an unknown command and the whole mandate is silently
  discarded. Lead with prose; name a skill mid-sentence if you must reference one. The
  prompt must instruct the next scheduled run to start prose-first too. Enforced by
  `bin/pre-cron-check.sh`, not by this paragraph.
- **D3 — Foundational is always the answer**, unless the foundational fix would itself
  derail the arc. Never take the patching branch to protect schedule. Every firing of this
  carve-out is a D7 ledger entry.
- **D4 — Local commits only; push is never grantable.** No modifier, including `full`,
  pre-authorizes a push. Push stays a legitimate stop in every mode.
- **D5 — Report the live model name at every checkpoint**, so a silent model swap is visible.
- **D6 — A non-blocking stop never idles the run.** Note it, keep working, surface at handoff.
- **D7 — The judgment ledger.** Any decision that could not be **Validated** (checked
  against ground truth, not asserted), **Deterministic** (same inputs, same verdict for
  anyone re-running it), **Traced** (the check is nameable and re-runnable), and
  **Confirmed after** (what was predicted actually held) is logged. All four hold → an
  ordinary `[DECISION]` line. Any one fails → a ledger entry.

  Write to `<knowledge_folder>/logs/auto/<YYYY-MM-DD>-<slug>-judgments.md`, resolving
  `knowledge_folder` from `~/.claude/aria-knowledge.local.md`. Create `logs/auto/` lazily.
  Entry shape:

      ### J<N> — <the decision, one line>
      - **Chose:** <what was done>
      - **Alternative not taken:** <what was rejected>
      - **Why not deterministic:** <which of the four tests failed, and how>
      - **Would be falsified by:** <the concrete check that would prove it wrong>
      - **Blast radius / reversal:** <files · commit · how to undo>
      - **Type:** judgment | D3-carve-out
      - **Disposition:** pending → accepted | revisit | reverted

  At arc close the ledger is reported **first**, ahead of the landed-work summary, and the
  user is explicitly prompted to review each entry (accept / revisit / revert); dispositions
  are written back. If the arc ends via a context wall, a scheduled handoff, or a restart
  instead of a clean close, carry the ledger path in the `/handoff` opener and `SESSION.md`.
  **An empty ledger is stated, never omitted:** "0 judgment calls — every decision was
  deterministically validated." Silence and zero must be distinguishable.
```

- [ ] **Step 4: Extend the Step 0.5 arc contract**

In the Step 0.5 blockquote, after the `**Push policy:**` line, add:

```markdown
> **Usage:** gating on 5h only; 7d ignored · arm at 90% · pause at 95% (D1).
> **Push:** local commits only — never pre-authorized by any modifier (D4).
> **Tools:** MCP / plugins / skills pre-approved.
> **Foundational:** always preferred; any carve-out is logged (D3 → D7).
> **Judgment ledger:** `<resolved path>` — reported first at close, for your review (D7).
> **Model:** <live model name> — re-reported at each checkpoint (D5).
```

- [ ] **Step 5: Run to verify it passes**

Run: `sh tests/repros/auto-modes.sh`
Expected: all `SD ` assertions PASS; summary shows `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugin-claude-code/skills/auto/SKILL.md tests/repros/auto-modes.sh
git commit -m "feat(auto): standing directives D1-D7 incl. the judgment ledger"
```

---

## Task 2: `plan` mode, `arc` keyword, and the three modifiers

**Files:**
- Modify: `plugin-claude-code/skills/auto/SKILL.md` (Step 0 mode table ~line 49-53; parsing paragraph ~line 61)
- Test: `tests/repros/auto-modes.sh`

**Interfaces:**
- Consumes: `**D4` and `**D7` labels from Task 1 (the `full` row cites them).
- Produces: the literal mode keyword `plan` and modifier tokens `full`, `loop`, `tickets` — Task 3 rewrites the frontmatter to advertise exactly these.

- [ ] **Step 1: Write the failing assertions**

Append to `auto-modes.sh` before the summary:

```sh
# MM: plan mode + arc as an explicit keyword
grep -qiE '\| *\*\*plan\*\* *\|' "$SK" \
  && ok "MM plan mode row" || bad "MM plan" "no plan mode row in the table"
grep -qiE 'stop at a prospected|No code\.' "$SK" \
  && ok "MM plan stops before code" || bad "MM plan stop" "plan mode doesn't forbid code"
grep -qiE 'matches `arc`|`arc` \| `execute`|arc. \| .execute' "$SK" \
  && ok "MM arc is a mode keyword" || bad "MM arc" "arc not parseable as a mode"

# MM: the three modifiers, stackable
for m in full loop tickets; do
  grep -qF "**\`$m\`**" "$SK" && ok "MM modifier: $m" || bad "MM $m" "modifier not documented"
done
grep -qiE 'stackable|stack' "$SK" && ok "MM modifiers stack" || bad "MM stack" "stacking not stated"
grep -qiF 'wide' "$SK" && bad "MM wide" "rejected modifier 'wide' leaked in" || ok "MM no wide"

# MM: full grants everything EXCEPT push
grep -qiE 'except push|except the one that leaves' "$SK" \
  && ok "MM full excludes push" || bad "MM full push" "full's push carve-out missing"
grep -qiE 'raises the three fan-out stopgaps|does not remove them|raised, finite' "$SK" \
  && ok "MM full keeps stopgaps finite" || bad "MM full stopgaps" "stopgaps not preserved"

# MM: loop implies continue + self-restart, and the contradiction is resolved
grep -qiE 'loop.*implies.*continue|continue.*self-restart' "$SK" \
  && ok "MM loop implies continue+self-restart" || bad "MM loop" "loop expansion undocumented"
grep -qiE 'contradictor|explicit token' "$SK" \
  && ok "MM loop+stop contradiction resolved" || bad "MM loop stop" "contradiction unhandled"
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/repros/auto-modes.sh`
Expected: FAIL on `MM plan`, `MM full`, `MM loop`, etc.

- [ ] **Step 3: Add the `plan` row and make `arc` a keyword**

In the Step 0 mode table, change the `arc` row's Trigger cell to `` `/auto`, `/auto arc`, or `/auto <goal>` `` and insert after the `execute` row:

```markdown
| **plan** | `/auto plan [<goal>]` | Produce a prospected, cold-executable plan and STOP. Runs brainstorm → spec → /prospect → plan → /prospect. **No code.** The mirror of `execute`. |
```

- [ ] **Step 4: Add the modifiers section**

Insert immediately after the mode table:

```markdown
**Modifiers** (stackable, any position, case-insensitive):

- **`full`** — maximum authority on every axis **except push**: tools/MCP/plugins
  pre-approved · Workflow fan-out ON (default is hard-OFF) · cumulative subagent cap
  10 → 30 · fan-out budget-fraction gate 25% → 40% · resume armed automatically when
  usage-bound · self-decide every objectively-validatable fork. `full` is defined by its
  boundary: **every grant except the one that leaves the machine** (D4). It **raises the
  three fan-out stopgaps; it does not remove them** — raised, finite, still live, because an
  unattended max-authority run is the case most exposed to unbounded spend and the
  budget-fraction gate is what protects D1's 95% pause.
- **`loop`** — unattended preset. Implies `continue` **and** `self-restart`, arms the resume
  at 90%, never idles on a non-blocking stop, and checkpoint-commits each milestone. An
  explicit trailing `stop` after `loop` is contradictory: resolve to the explicit token and
  say so in the arc contract.
- **`tickets`** — tracker-bound. Work selection comes from the connected tracker by
  priority; comment on the ticket at every commit; never claim a ticket without verified
  validation.

Authority is orthogonal to duration: `full` sets *how much latitude*, `loop`/`continue`/`stop`
set *how long*. `/auto full` (max authority, scoped) and `/auto full loop` (max authority,
overnight) are both valid.
```

- [ ] **Step 5: Update the parsing paragraph**

Replace the `**Parsing:**` sentence with:

```markdown
**Parsing:** if the first arg case-insensitively matches `arc`, `execute`, `plan`, `config`,
or `preflight`, that is the mode; otherwise the mode is `arc` and the arg begins the goal.
Anywhere in the args, `full`/`loop`/`tickets` are modifiers (a set — they stack). A trailing
`continue`/`stop` sets the on-queue-complete toggle and a trailing `self-restart` sets the
context-restart flag. Everything else is the goal. Example: `/auto full loop tickets clear
the payments queue` → mode `arc`, modifiers `{full, loop, tickets}`, goal "clear the
payments queue".
```

- [ ] **Step 6: Run to verify it passes**

Run: `sh tests/repros/auto-modes.sh`
Expected: all `MM ` assertions PASS; `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add plugin-claude-code/skills/auto/SKILL.md tests/repros/auto-modes.sh
git commit -m "feat(auto): add plan mode, arc keyword, and full/loop/tickets modifiers"
```

---

## Task 3: Declass the vendor lock + rewrite the frontmatter within budget

**Files:**
- Modify: `plugin-claude-code/skills/auto/SKILL.md` lines 2, 3, 52, 75, 102, 120, 128, 144
- Test: `tests/repros/auto-modes.sh`

**Interfaces:**
- Consumes: modifier tokens `full`/`loop`/`tickets` and mode `plan` from Task 2 (the new description advertises them).
- Produces: a `/auto` description ≤ 1,232 B. No later task depends on its exact text.

- [ ] **Step 1: Write the failing assertions**

```sh
# VL: zero vendor lock remains — this assertion is what keeps the class closed
if grep -qi 'linear' "$SK"; then
  bad "VL no vendor lock" "$(grep -ci linear "$SK") 'linear' matches remain"
else
  ok "VL no vendor lock in auto/SKILL.md"
fi
grep -qF 'ticket-id' "$SK" && ok "VL generic ticket-id" || bad "VL ticket-id" "not genericized"
grep -qiE 'project.tracker' "$SK" \
  && ok "VL tracker category probed" || bad "VL probe" "no tracker category probe"
grep -qiE 'ticketing_plugins' "$SK" \
  && ok "VL honors ticketing_plugins" || bad "VL config" "config key not honored"
grep -qiE 'never verify|not verify.*installed|no installed-plugin probe' "$SK" \
  && ok "VL inherits no-installed-probe rule" || bad "VL probe rule" "installability rule missing"
grep -qF '[A-Z]{2,}-\\d+' "$SK" \
  && ok "VL reuses the agnostic ticket regex" || bad "VL regex" "ticket-ID regex absent"

# VL: Gate B — /auto's own description must not have grown
AUTO_DESC=$(awk '/^description:/{f=1;print;next} f&&/^[a-z_-]+:/{f=0} f' "$SK" | wc -c)
[ "$AUTO_DESC" -le 1232 ] \
  && ok "VL description within budget ($AUTO_DESC B <= 1232)" \
  || bad "VL budget" "description grew to $AUTO_DESC B (was 1232)"
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/repros/auto-modes.sh`
Expected: `FAIL  VL no vendor lock — 8 'linear' matches remain` plus the other VL failures.

- [ ] **Step 3: Replace the frontmatter description and argument-hint**

Replace line 2 wholesale (this trims 185 B of trigger synonyms and 356 B of mode restatement, paying for the new vocabulary):

```yaml
description: "Drive an autonomous execution arc end-to-end — compose brainstorm→spec→/prospect→plan→/prospect→TDD→/retrospect under the Rule 35 posture, decide objectively-validatable forks yourself, and stop only on a load-bearing fork or an ungranted approval. Modes: 'arc' (default), 'execute <plan|spec|ticket-id>' (skip ideation), 'plan' (stop at a prospected plan, no code), 'config' (guided per-run knob picker). Stackable modifiers: 'full' (max authority except push), 'loop' (unattended: continue + self-restart + armed resume), 'tickets' (tracker-bound work selection + per-commit ticket comments). Toggles: continue|stop, self-restart. An explicit grant of autonomous latitude that overrides the standing `autonomy` config for the arc and never writes it. Use when the user hands off a goal, plan, ticket, or SESSION.md with latitude to execute WITHOUT per-step approval — 'combined go', 'run overnight', 'just build it', 'do as much as you can'. ENTRY POINT for a multi-step arc, NOT a single concrete change; distinct from /prospect, /retrospect, /handoff, /wrapup. (Code port — ADR-094.)"
```

Replace line 3:

```yaml
argument-hint: "[arc|execute|plan|config] [<goal | plan-path | ticket-id>] [full] [loop] [tickets] [continue|stop]"
```

- [ ] **Step 4: Declass the five body sites**

| Site | Change |
|---|---|
| mode table `execute` row | `<plan-path \| linear-id \| "the plan">` → `<plan-path \| ticket-id \| "the plan">` |
| Step 0¾ knob 1 | `a Linear ID` → `a ticket ID from your connected tracker` |
| Step 0.5 contract | `Linear ticket filing` → `ticket filing` |
| Pre-answered bullet | `**Linear tickets** — create freely:` → `**Tickets** — create freely in the connected tracker:` |
| Degrade paragraph + `execute` resolution | `needs Linear MCP` → `needs a connected project-tracker MCP`; `Linear ID → MCP fetch` → `ticket ID → tracker MCP fetch` |

- [ ] **Step 5: Add the tracker-resolution paragraph**

Append to the `tickets` modifier bullet added in Task 2:

```markdown
  **Resolving the tracker (never hardcode a vendor).** Probe at runtime for a connected
  `~~project-tracker` MCP and adapt, as `/digest` §3c does — Linear · Asana · Atlassian/Jira ·
  Monday · ClickUp · Notion-as-tracker · GitHub Issues. Prose-only probing; there is no
  helper API (ADR-015). If `ticketing_plugins` is set in `~/.claude/aria-knowledge.local.md`
  (`tag:plugin-command` pairs, read directly from the file as `/audit-knowledge` does), it
  wins — it is the user's explicit declaration. **Never verify that a mapped command is
  actually installed**: enumerating installed plugins couples this skill to runtime
  internals, and a loud failure at invocation beats a silently-absent hint. Detect ticket
  IDs with the vendor-neutral `\b([A-Z]{2,}-\d+)\b`. With no tracker connected and no
  mapping, say so once and fall back to the Step 4 work-selection order — `tickets` never
  hard-fails an arc.
```

- [ ] **Step 6: Run to verify it passes**

Run: `sh tests/repros/auto-modes.sh`
Expected: all `VL ` assertions PASS; `0 failed`.

- [ ] **Step 7: Verify the whole-plugin budget**

```bash
t=0; for f in plugin-claude-code/skills/*/SKILL.md; do b=$(awk '/^description:/{f=1;print;next} f&&/^[a-z_-]+:/{f=0} f' "$f" | wc -c); t=$((t+b)); done; echo "$t / 18944"
```

Expected: a total ≤ 18,938. If it exceeds, trim the description further — do NOT raise `ARIA_SKILL_BUDGET`.

- [ ] **Step 8: Commit**

```bash
git add plugin-claude-code/skills/auto/SKILL.md tests/repros/auto-modes.sh
git commit -m "fix(auto): declass Linear hardcoding across 7 sites; tracker-agnostic tickets"
```

---

## Task 4: Tiered scheduling + remove the `durable: true` no-op

**Files:**
- Modify: `plugin-claude-code/skills/auto/SKILL.md` Step 6 (~line 218-220)
- Test: `tests/repros/auto-modes.sh`

**Interfaces:**
- Consumes: `**D1` and `**D2` from Task 1 (Step 6 cites both thresholds and the prose-first rule).
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing assertions**

```sh
# SCH: durable:true is a documented no-op and must not be instructed
grep -qE 'durable: ?true' "$SK" \
  && bad "SCH durable no-op" "still instructs durable:true (tool docs: has no effect)" \
  || ok "SCH no durable:true"
grep -qiE 'session-only' "$SK" \
  && ok "SCH session-only stated" || bad "SCH session-only" "CronCreate reality not stated"

# SCH: availability-gated, with CronCreate retained as the always-available default
grep -qiE 'CronCreate.*default|default.*CronCreate|baseline' "$SK" \
  && ok "SCH CronCreate is the default" || bad "SCH default" "CronCreate not stated as baseline"
grep -qiE 'every runtime|always available' "$SK" \
  && ok "SCH availability is the gate" || bad "SCH availability" "no availability-first rule"
grep -qiE 'desktop' "$SK" \
  && ok "SCH names the desktop-only constraint" || bad "SCH desktop" "scheduled-task surface not scoped to desktop"
grep -qiE 'launchd' "$SK" \
  && ok "SCH names the CLI durable option" || bad "SCH launchd" "no CLI-side durable mechanism"
grep -qiE 'probe' "$SK" \
  && ok "SCH probes before naming a mechanism" || bad "SCH probe" "no runtime probe rule"
# The failure this guards: never promise durability the runtime cannot deliver.
grep -qiE 'never promise durability|cannot deliver' "$SK" \
  && ok "SCH no over-promise" || bad "SCH over-promise" "missing the don't-promise guard"
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/repros/auto-modes.sh`
Expected: `FAIL  SCH durable no-op`, `FAIL  SCH tier1`, etc.

- [ ] **Step 3: Rewrite Step 6**

Replace the Step 6 body with:

```markdown
Only for an unattended run. **Mechanisms are gated on availability first, capability second.**
`CronCreate` is the **baseline and the default**: it is the only one present in **every
runtime**. Its session-only nature is an accepted constraint, not a defect — an unattended
run keeps its session open by design. Do **not** pass `durable: true`; the tool documents it
as having no effect.

| Mechanism | Available | Survives session death | Fresh context | Use for |
|---|---|---|---|---|
| **`CronCreate`** — the default | **Always, every runtime** | No — session-only, in-memory; recurring auto-expires at 7 days; fires only while the REPL is idle | No — re-enters this session | Usage-bound resume with the session left open. The normal unattended run. |
| **`create_scheduled_task`** | **Desktop runtime only** — probe, never assume | Yes — runs at next app launch if missed | Yes | A resume that must survive the session ending, where the runtime offers it |
| **launchd** (the `pm-schedule.sh` pattern) | macOS only; user opts in | Yes — OS-level | Yes — a fresh `claude` invocation | Truly session-independent recurring work on the CLI |
| **`bin/auto-runloop.sh`** (`self-restart`) | Wrapper must already be running | Wrapper-dependent | Yes — a fresh `claude -p` process | A context wall mid-arc |

**Selection rule.** Default to `CronCreate`. Reach past it only when the resume genuinely must
survive the session ending — and then **probe what this runtime actually offers** rather than
naming a mechanism the user may not have. State which one was chosen and why. **Never promise
durability the runtime cannot deliver.**

Arm EARLY and re-arm at or before **90%** 5h usage per D1 — never wait until the end, since
the session can die first and break the chain. Fire **5 minutes after** the reset boundary,
never at it: firing at the boundary risks landing before the window has propagated and
re-firing into a still-exhausted window. The prompt is a compressed, self-sufficient mandate
plus "VERIFY STATE FIRST — this prompt may be stale" and an instruction to re-arm the next
cycle. **D2 governs the prompt whichever mechanism is used: it must lead with prose.** Arming
is part of the remit when the user asked for a self-perpetuating run; it is not something to
do silently on an ordinary scoped arc.

The mechanisms solve different problems and do not substitute for one another: a schedule
resumes work at a *time*, while `self-restart` recovers from a *context wall*. Choose by the
constraint that actually binds, and by what this runtime has.
```

- [ ] **Step 4: Run to verify it passes**

Run: `sh tests/repros/auto-modes.sh`
Expected: all `SCH ` PASS; `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/skills/auto/SKILL.md tests/repros/auto-modes.sh
git commit -m "fix(auto): tier the resume mechanism; drop the durable:true no-op"
```

---

# Deliverable B — the D2 guard

## Task 5: `pre-cron-check.sh` — deny a `/`-leading scheduled prompt

**Files:**
- Create: `plugin-claude-code/bin/pre-cron-check.sh`
- Create: `tests/repros/cron-slash-guard.sh`
- Modify: `plugin-claude-code/.claude-plugin/plugin.json` (`hooks.PreToolUse`)

**Interfaces:**
- Consumes: `config.sh` (for `KT_CONFIGURED` / `KT_CONFIG_ERROR`), mirroring `bash-cd-check.sh`.
- Produces: a hook that emits `permissionDecision:"deny"` — exact JSON shape copied from `pre-edit-check.sh:362`.

- [ ] **Step 1: Write the failing test**

Create `tests/repros/cron-slash-guard.sh`:

```sh
#!/bin/sh
# cron-slash-guard.sh — the D2 guard must DENY a scheduled prompt that starts with '/'
# and stay silent otherwise. A guard never observed failing is not a guard.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/plugin-claude-code/bin/pre-cron-check.sh"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

[ -x "$HOOK" ] && ok "A hook exists and is executable" || bad "A exists" "missing or not +x"

# RED case: a slash-leading prompt must be denied.
OUT=$(printf '%s' '{"tool_name":"CronCreate","tool_input":{"cron":"5 4 * * *","prompt":"/auto execute the plan"}}' | sh "$HOOK" 2>/dev/null || true)
echo "$OUT" | grep -q '"permissionDecision":"deny"' \
  && ok "B denies a /-leading prompt" || bad "B deny" "no deny for '/auto ...' (got: $OUT)"
echo "$OUT" | grep -qi 'prose' \
  && ok "B reason tells the caller what to do" || bad "B reason" "deny reason lacks guidance"

# GREEN case: a prose-leading prompt must pass silently.
OUT2=$(printf '%s' '{"tool_name":"CronCreate","tool_input":{"cron":"5 4 * * *","prompt":"This is a scheduled resume. Verify state first."}}' | sh "$HOOK" 2>/dev/null || true)
echo "$OUT2" | grep -q '"permissionDecision":"deny"' \
  && bad "C allows prose" "denied a legitimate prose prompt" || ok "C allows a prose prompt"

# The other scheduling verb is covered too.
OUT3=$(printf '%s' '{"tool_name":"mcp__scheduled-tasks__create_scheduled_task","tool_input":{"taskId":"x","prompt":"/auto continue"}}' | sh "$HOOK" 2>/dev/null || true)
echo "$OUT3" | grep -q '"permissionDecision":"deny"' \
  && ok "D covers create_scheduled_task" || bad "D scheduled-tasks" "not denied (got: $OUT3)"

# Registration.
grep -q 'pre-cron-check.sh' "$REPO_ROOT/plugin-claude-code/.claude-plugin/plugin.json" \
  && ok "E registered in plugin.json" || bad "E registered" "hook not wired"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/repros/cron-slash-guard.sh`
Expected: `FAIL  A exists — missing or not +x` and `FAIL  B deny`. **Confirm the RED before writing the hook — this is the step that proves the guard can fail.**

- [ ] **Step 3: Write the hook**

Create `plugin-claude-code/bin/pre-cron-check.sh`:

```sh
#!/bin/sh
# pre-cron-check.sh — PreToolUse hook enforcing standing directive D2.
#
# A scheduled prompt that begins with '/' is parsed as a slash command. In a
# scheduled/headless context it usually does not resolve, the runtime reports an
# unknown command, and the ENTIRE remaining mandate is silently discarded.
#
# The rule shipped as prose in v2.37.3 and was violated twice afterward, so it is
# enforced here instead. Fail-open on anything unparseable: this hook must never
# block a well-formed schedule because it could not read its own input.

INPUT=$(cat)

# Pull the prompt field. POSIX grep/sed only — no jq dependency, matching the
# sibling hooks. JSON escapes real newlines as \n, so the first character after
# the opening quote is exactly the character the parser will see.
PROMPT=$(echo "$INPUT" | grep -o '"prompt":"[^"]*"' | head -1 | sed 's/"prompt":"//;s/"$//')
[ -z "$PROMPT" ] && exit 0

# Leading whitespace is stripped by the parser too, so strip it before testing.
TRIMMED=$(printf '%s' "$PROMPT" | sed 's/^[[:space:]]*//')

case "$TRIMMED" in
  /*) ;;
  *) exit 0 ;;
esac

REASON='Scheduled prompt starts with "/" — blocked by ARIA standing directive D2. A leading slash token is parsed as a command, and when it does not resolve the whole mandate is silently discarded. Rewrite the prompt to LEAD WITH PROSE (name a skill mid-sentence if you must reference one), make it self-sufficient, and instruct the next scheduled run to start prose-first as well.'

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON"
```

Then: `chmod +x plugin-claude-code/bin/pre-cron-check.sh`

- [ ] **Step 4: Register the hook**

In `plugin-claude-code/.claude-plugin/plugin.json`, add a fourth entry to `hooks.PreToolUse`:

```json
{
  "matcher": "CronCreate|mcp__scheduled-tasks__create_scheduled_task",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/bin/pre-cron-check.sh",
      "timeout": 5
    }
  ]
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `sh tests/repros/cron-slash-guard.sh`
Expected: `5 passed, 0 failed` (or more, all PASS).

Also verify the JSON stayed valid:
Run: `python3 -c "import json;json.load(open('plugin-claude-code/.claude-plugin/plugin.json'));print('valid')"`
Expected: `valid`

- [ ] **Step 6: Commit**

```bash
git add plugin-claude-code/bin/pre-cron-check.sh tests/repros/cron-slash-guard.sh plugin-claude-code/.claude-plugin/plugin.json
git commit -m "feat(hooks): enforce D2 — deny a scheduled prompt that leads with a slash"
```

---

# Deliverable C — recurring-lapse guards

## Task 6: `pre-bash-write-check.sh` — warn on shell writes that bypass Edit/Write

**Files:**
- Create: `plugin-claude-code/bin/pre-bash-write-check.sh`
- Create: `tests/repros/lapse-guards.sh`
- Modify: `plugin-claude-code/.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `additionalContext` output only — **never** `permissionDecision`. Task 7 appends to the same repro file.

- [ ] **Step 1: Measure the false-positive rate BEFORE writing the hook**

This gate decides whether the guard is safe. Run:

```bash
python3 - <<'EOF'
import json,glob,os,re
pat = re.compile(r"write_text\s*\(|open\s*\([^)]*['\"][wa]['\"]|sed\s+-i|(^|\s)tee\s+\S|>\s*\S+\.(py|ts|tsx|js|jsx|sh|md|json|swift|kt|java|rb|go|rs)\b")
hits=tot=0; samples=[]
for f in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
    try:
        for line in open(f, errors='ignore'):
            if '"Bash"' not in line: continue
            try: d=json.loads(line)
            except: continue
            for c in (d.get('message',{}).get('content') or []):
                if not isinstance(c,dict) or c.get('name')!='Bash': continue
                cmd=(c.get('input') or {}).get('command','')
                if not cmd: continue
                tot+=1
                if pat.search(cmd):
                    hits+=1
                    if len(samples)<25: samples.append(cmd[:150])
    except Exception: pass
print(f"Bash calls scanned: {tot}\nPattern hits: {hits} ({100*hits/max(tot,1):.1f}%)")
print("\n--- sample hits (classify each: BYPASS vs LEGITIMATE) ---")
for s in samples: print(" *", s)
EOF
```

Record the hit rate and classify the samples. **If more than ~20% of hits are legitimate
(temp files, scratchpad, logs, generated artifacts), narrow the pattern before proceeding.**
Write the measured numbers into the commit message — a silent cap reads as full coverage.

- [ ] **Step 2: Write the failing test**

Create `tests/repros/lapse-guards.sh`:

```sh
#!/bin/sh
# lapse-guards.sh — the two recurring-lapse guards. Both are WARN-only by design:
# they must never emit permissionDecision, because a false positive would block
# legitimate work in every session.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BW="$REPO_ROOT/plugin-claude-code/bin/pre-bash-write-check.sh"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

[ -x "$BW" ] && ok "A bash-write hook exists" || bad "A exists" "missing or not +x"

# RED: a python structural write to a source file must warn.
OUT=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"from pathlib import Path; Path(1).write_text(2)\""}}' | sh "$BW" 2>/dev/null || true)
echo "$OUT" | grep -q 'additionalContext' \
  && ok "B warns on write_text" || bad "B write_text" "no warning (got: $OUT)"
echo "$OUT" | grep -q 'permissionDecision' \
  && bad "B warn-only" "emitted a permissionDecision; must be warn-only" \
  || ok "B is warn-only (no deny)"

# RED: sed -i on a source file must warn.
OUT2=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ src/app.ts"}}' | sh "$BW" 2>/dev/null || true)
echo "$OUT2" | grep -q 'additionalContext' \
  && ok "C warns on sed -i" || bad "C sed -i" "no warning (got: $OUT2)"

# GREEN: ordinary read-only commands must stay silent.
for cmd in "git status" "grep -rn foo src/" "ls -la" "echo hi > /tmp/scratch.txt"; do
  O=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" | sh "$BW" 2>/dev/null || true)
  if [ -z "$O" ]; then ok "D silent on: $cmd"; else bad "D silent $cmd" "warned on a benign command: $O"; fi
done

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 3: Run to verify it fails**

Run: `sh tests/repros/lapse-guards.sh`
Expected: `FAIL  A exists` and `FAIL  B write_text`. Confirm RED before implementing.

- [ ] **Step 4: Write the hook**

Create `plugin-claude-code/bin/pre-bash-write-check.sh`:

```sh
#!/bin/sh
# pre-bash-write-check.sh — PreToolUse:Bash hook. Warns when a shell command
# performs a STRUCTURAL FILE WRITE that routes around the Edit/Write tools and
# therefore around the Rule 22 PreToolUse gate.
#
# WARN-ONLY BY DESIGN. This hook never denies. A false positive here would block
# legitimate shell work in every session, which is worse than the lapse it
# catches. Escalate to deny only after the false-positive rate is measured.
#
# Deliberately narrow: only high-confidence structural-write idioms, and only
# when the target looks like source. Temp, scratchpad, and log writes are out.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')
[ -z "$COMMAND" ] && exit 0

# Never warn on writes to temp/scratch locations — those are legitimate.
case "$COMMAND" in
  */tmp/*|*scratchpad*|*/var/folders/*) exit 0 ;;
esac

IDIOM=""
case "$COMMAND" in
  *write_text\(*)        IDIOM="Path(...).write_text()" ;;
  *sed\ -i*)             IDIOM="sed -i" ;;
esac

# Redirect into a source-shaped path.
if [ -z "$IDIOM" ]; then
  if echo "$COMMAND" | grep -qE '>>?[[:space:]]*[^[:space:]]+\.(py|ts|tsx|js|jsx|sh|md|json|swift|kt|java|rb|go|rs)([[:space:]]|$)'; then
    IDIOM="shell redirect into a source file"
  fi
fi

[ -z "$IDIOM" ] && exit 0

MSG="ARIA: this command uses $IDIOM to write a file directly. Structural edits made through the shell bypass the Edit/Write tools and therefore the Rule 22 pre-edit gate — the change lands with no scope assessment recorded. Use Edit or Write for structural edits. If this write is genuinely not a structural edit (a generated artifact, a temp file, a log), proceed and say why."

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$MSG"
```

Then: `chmod +x plugin-claude-code/bin/pre-bash-write-check.sh`

- [ ] **Step 5: Register the hook**

Add to the existing `hooks.PreToolUse` array in `plugin.json`:

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/bin/pre-bash-write-check.sh",
      "timeout": 5
    }
  ]
}
```

- [ ] **Step 6: Run to verify it passes**

Run: `sh tests/repros/lapse-guards.sh`
Expected: all PASS, `0 failed`.

Run: `python3 -c "import json;json.load(open('plugin-claude-code/.claude-plugin/plugin.json'));print('valid')"`
Expected: `valid`

- [ ] **Step 7: Commit** (include the Step 1 measurement in the body)

```bash
git add plugin-claude-code/bin/pre-bash-write-check.sh tests/repros/lapse-guards.sh plugin-claude-code/.claude-plugin/plugin.json
git commit -m "feat(hooks): warn when a shell write bypasses the Edit/Write Rule 22 gate

Warn-only, not deny. False-positive measurement over local transcripts:
<N> Bash calls scanned, <M> hits (<P>%), <K> of 25 sampled hits legitimate."
```

---

## Task 7: `post-edit-tautology-check.sh` — warn on assertions that cannot fail

**Files:**
- Create: `plugin-claude-code/bin/post-edit-tautology-check.sh`
- Modify: `tests/repros/lapse-guards.sh` (append)
- Modify: `plugin-claude-code/.claude-plugin/plugin.json` (`hooks.PostToolUse`)

**Interfaces:**
- Consumes: the `lapse-guards.sh` harness from Task 6 (`ok`/`bad`/`PASS`/`FAIL` already defined).
- Produces: `additionalContext` only.

- [ ] **Step 1: Write the failing test**

In `lapse-guards.sh`, insert before the final `printf` summary:

```sh
TA="$REPO_ROOT/plugin-claude-code/bin/post-edit-tautology-check.sh"
[ -x "$TA" ] && ok "E tautology hook exists" || bad "E exists" "missing or not +x"

# RED: an identical-operand assertion in a test file must warn.
OUT4=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/x/tests/test_a.py","content":"def test_x():\n    assert value == value\n"}}' | sh "$TA" 2>/dev/null || true)
echo "$OUT4" | grep -q 'additionalContext' \
  && ok "F warns on identical-operand assert" || bad "F identical" "no warning (got: $OUT4)"
echo "$OUT4" | grep -q 'permissionDecision' \
  && bad "F warn-only" "emitted permissionDecision; must be warn-only" || ok "F is warn-only"
echo "$OUT4" | grep -qi 'semantic' \
  && ok "G states its own limit" || bad "G limit" "does not say what it cannot detect"

# RED: assert True must warn.
OUT5=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/x/tests/test_b.py","content":"def test_y():\n    assert True\n"}}' | sh "$TA" 2>/dev/null || true)
echo "$OUT5" | grep -q 'additionalContext' \
  && ok "H warns on assert True" || bad "H assert True" "no warning"

# GREEN: a real assertion, and any non-test file, stay silent.
OUT6=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/x/tests/test_c.py","content":"def test_z():\n    assert parse(raw) == expected\n"}}' | sh "$TA" 2>/dev/null || true)
[ -z "$OUT6" ] && ok "I silent on a real assertion" || bad "I real" "warned on a valid test: $OUT6"
OUT7=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/x/src/app.py","content":"assert x == x\n"}}' | sh "$TA" 2>/dev/null || true)
[ -z "$OUT7" ] && ok "J scoped to test paths" || bad "J scope" "warned on a non-test file"
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/repros/lapse-guards.sh`
Expected: `FAIL  E exists`, `FAIL  F identical`, `FAIL  H assert True`.

- [ ] **Step 3: Write the hook**

Create `plugin-claude-code/bin/post-edit-tautology-check.sh`:

```sh
#!/bin/sh
# post-edit-tautology-check.sh — PostToolUse:Edit|Write hook. Warns when a test
# file gains an assertion that cannot fail. An assertion that cannot fail is a
# false green — the exact class Rule 36 exists to prevent.
#
# WARN-ONLY, and deliberately SYNTACTIC. It detects identical-operand comparisons
# and literal-true assertions. It cannot detect semantic tautologies, and it says
# so in its own message: a clean run from this hook must never be read as "no
# tautologies present", or the guard becomes its own false green.

INPUT=$(cat)

FILE=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"$//')
[ -z "$FILE" ] && exit 0

# Only test-shaped paths.
case "$FILE" in
  *test*|*spec*|*Test*|*Spec*) ;;
  *) exit 0 ;;
esac

# Body: Write sends "content", Edit sends "new_string". Two separate passes —
# BSD sed does NOT support \| alternation in a BRE, so a combined expression
# silently yields garbage. Uses the same grep -o idiom as bash-cd-check.sh.
BODY=$(echo "$INPUT" | grep -o '"content":"[^"]*"' | head -1 | sed 's/"content":"//;s/"$//')
[ -z "$BODY" ] && BODY=$(echo "$INPUT" | grep -o '"new_string":"[^"]*"' | head -1 | sed 's/"new_string":"//;s/"$//')
[ -z "$BODY" ] && exit 0

FOUND=""

# Literal-true assertions.
if echo "$BODY" | grep -qE 'assert[[:space:]]+(True|true)([^A-Za-z0-9_]|$)|assertTrue\((True|true)\)|expect\((true|True)\)\.(toBe|toEqual)\((true|True)\)'; then
  FOUND="a literal-true assertion"
fi

# Identical operands. NO REGEX BACKREFERENCES: they are a BRE feature, are not
# guaranteed in ERE, and this machine's PATH grep (ugrep) hard-errors on \1 in
# -E. awk extracts both operands and compares them as strings instead, which is
# portable across every grep/awk on any host.
if [ -z "$FOUND" ]; then
  DUP=$(printf '%s\n' "$BODY" | tr '\\n' '\n' | awk '
    {
      if (match($0, /assert[ \t]+[A-Za-z_][A-Za-z0-9_.]*[ \t]*==[ \t]*[A-Za-z_][A-Za-z0-9_.]*/)) {
        s = substr($0, RSTART, RLENGTH); sub(/^assert[ \t]+/, "", s)
      } else if (match($0, /expect\([A-Za-z_][A-Za-z0-9_.]*\)\.(toBe|toEqual)\([A-Za-z_][A-Za-z0-9_.]*\)/)) {
        s = substr($0, RSTART, RLENGTH)
        sub(/^expect\(/, "", s); sub(/\)\.(toBe|toEqual)\(/, "==", s); sub(/\)$/, "", s)
      } else next
      n = index(s, "=="); if (n == 0) next
      l = substr(s, 1, n - 1); r = substr(s, n + 2)
      gsub(/[ \t]/, "", l); gsub(/[ \t]/, "", r)
      if (l != "" && l == r) { print l; exit }
    }')
  [ -n "$DUP" ] && FOUND="an assertion whose two operands are both \`$DUP\`"
fi

[ -z "$FOUND" ] && exit 0

MSG="ARIA: this test file contains $FOUND — it cannot fail, so it proves nothing and reads as a passing gate (Rule 36). Rewrite it so it fails for the right reason, then watch it go RED before trusting it. NOTE: this check is syntactic only; it cannot detect semantic tautologies, so a clean result here is not evidence that the file is free of them."

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$MSG"
```

Then: `chmod +x plugin-claude-code/bin/post-edit-tautology-check.sh`

- [ ] **Step 4: Register the hook**

Add to `hooks.PostToolUse` in `plugin.json`:

```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/bin/post-edit-tautology-check.sh",
      "timeout": 5
    }
  ]
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `sh tests/repros/lapse-guards.sh`
Expected: all PASS, `0 failed`.

Run: `python3 -c "import json;json.load(open('plugin-claude-code/.claude-plugin/plugin.json'));print('valid')"`
Expected: `valid`

- [ ] **Step 6: Commit**

```bash
git add plugin-claude-code/bin/post-edit-tautology-check.sh tests/repros/lapse-guards.sh plugin-claude-code/.claude-plugin/plugin.json
git commit -m "feat(hooks): warn on syntactically-tautological assertions in test files"
```

---

## Task 8: Version bump, CHANGELOG, and full release gates

**Files:**
- Modify: `plugin-claude-code/.claude-plugin/plugin.json` (`version`)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: every prior task.
- Produces: the release artifact.

- [ ] **Step 1: Run every gate before touching the version**

```bash
sh tests/repros/auto-modes.sh && sh tests/repros/cron-slash-guard.sh && sh tests/repros/lapse-guards.sh; echo "EXIT=$?"
```

Expected: `EXIT=0`. Read it. Do not proceed on a nonzero exit.

- [ ] **Step 2: Bump the version**

In `plugin-claude-code/.claude-plugin/plugin.json`, change `"version": "2.42.0"` to `"version": "2.43.0"`.

Minor, not patch: modifiers, `plan` mode, and three hooks are new capability surface every user inherits — matching the v2.35.0 and v2.39.0 precedents.

- [ ] **Step 3: Write the CHANGELOG entry**

Prepend under the top heading of `CHANGELOG.md`:

```markdown
## [2.43.0] — 2026-07-30

### Added
- **`/auto` modifiers** — `full` (maximum authority on every axis **except push**, which no
  modifier can grant), `loop` (unattended: `continue` + `self-restart` + armed resume), and
  `tickets` (tracker-bound work selection + a ticket comment per commit). Stackable, any
  position. Authority is orthogonal to duration, so `/auto full` and `/auto full loop` are
  both expressible.
- **`/auto plan` mode** — produce a prospected, cold-executable plan and stop before any
  code. The mirror of `execute`.
- **Standing Directives D1–D7** — always-on, never need asking for: 5h-binds/7d-ignored
  usage gating with a 90% arm and 95% pause; prose-first scheduled prompts; foundational-
  always; local-only with push never grantable; live-model reporting at checkpoints;
  non-blocking stops never idle; and the **judgment ledger**.
- **The judgment ledger (D7)** — any decision that could not be validated, deterministically,
  traceably, and confirmed-after is logged to `<knowledge_folder>/logs/auto/`, reported
  first at arc close, and reviewed by the user per entry. An empty ledger is stated, not
  omitted, so silence and zero stay distinguishable.
- **`bin/pre-cron-check.sh`** — denies a scheduled prompt that begins with `/`. This rule
  shipped as prose in v2.37.3 and was violated twice afterward; prose in a rarely-read step
  is not enforcement.
- **`bin/pre-bash-write-check.sh`** — warns when a shell command performs a structural file
  write that routes around Edit/Write and therefore around the Rule 22 gate. Warn-only.
- **`bin/post-edit-tautology-check.sh`** — warns when a test file gains an assertion that
  cannot fail (Rule 36). Warn-only, syntactic only, and it states that limit in its own
  message.

### Fixed
- **`/auto` no longer hardcodes one ticket vendor.** Seven sites genericized, including the
  frontmatter `description` and `argument-hint` that every user loads each session. The
  tracker is resolved by probing the connected `~~project-tracker` MCP (as `/digest` does)
  and by honoring `ticketing_plugins`, read directly from the config file as
  `/audit-knowledge` reads it — never verifying that a mapped command is installed. A
  regression assertion keeps the class closed.
- **`/auto` Step 6 no longer instructs `durable: true`**, which the tool documents as having
  no effect. Scheduling is now tiered by one question — does the resumed work need this
  session's in-memory state? — with the persistent scheduled-task surface preferred, cron as
  the session-only fallback, and the self-restart wrapper reserved for headless loops.

### Notes
- Claude-Code-canonical only. cowork / codex / cursor / antigravity remain tracked-drift.
- Gate B skill-discovery budget: net-negative — `/auto`'s description was trimmed by more
  than the new vocabulary added.
```

- [ ] **Step 4: Run the release gates**

Run: `./release.sh`
Expected: Gate A both suites green; **Gate B reports a total ≤ 18,938 / 18,944**; Gate C drift report-only. If Gate B fails, trim `/auto`'s description further — do not raise the budget.

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/.claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore(release): v2.43.0 — /auto modifiers, standing directives, mechanical guards"
```

- [ ] **Step 6: Report, do not push**

Push is a legitimate stop (D4). Report the commit range, the Gate B number, and the Task 6 false-positive measurement, then stop and await authorization.

---

## Self-Review

**Spec coverage.** Standing directives D1–D7 → Task 1. Modes `plan`/`arc` and modifiers → Task 2. The seven-site declass, the tracker mechanism, and the frontmatter/Gate B trim → Task 3. Step 6 tiering and the `durable` no-op → Task 4. Deliverable B → Task 5. Deliverable C1/C2 → Tasks 6/7. Version, CHANGELOG, gates → Task 8. The spec's rejected `wide` and `ship` modifiers are asserted absent in Task 2. No spec requirement is unassigned.

**Placeholders.** None. Every step carries the literal prose, shell, or JSON to apply. The one runtime-variable value — Task 6's false-positive count — is produced by a runnable command in Step 1 and carried into the Step 7 commit message.

**Type consistency.** Directive labels are `**D1`…`**D7` in Task 1 and cited in the same form in Tasks 2 and 4. Modifier tokens are `full`/`loop`/`tickets` in Task 2 and advertised identically in Task 3's frontmatter. `lapse-guards.sh` is created in Task 6 and appended to in Task 7 using the `ok`/`bad`/`PASS`/`FAIL` names defined there. Both hook JSON shapes are copied from verified sources: deny from `pre-edit-check.sh:362`, `additionalContext` from `bash-cd-check.sh:147`.

**Red-first discipline.** Tasks 5, 6, and 7 each require observing the guard FAIL before implementing it. Task 6 additionally gates its own safety on a measurement rather than an assumption.
