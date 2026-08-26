# Rules Delivery — The File/Hook Split — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> ⚠ **Tick the boxes as you go.** Its predecessor shipped with 54 of 54 unticked and had to be stamped SPENT after the fact to stop a future session rebuilding live work.

**Status:** GATED — gate 2 (`/prospect`) RUN 2026-08-26, verdict **PROCEED-WITH-CHANGES**.
All executor-applicable changes are applied below in the same session that ran the gate.
Report: `knowledge/logs/prospect/2026-08-26-file-rules-file-hook-split.md`.
✅ **ALL THREE ASKS RULED BY MIKE, 2026-08-26 — NOTHING IS BLOCKED.** ASK #1 → **A1**, accept the
standing cost as designed. ASK #2 → **B1**, the hook writes the file when absent, conditional on
firing once per session and not per tool use (**answered: `SessionStart`, see T2**). ASK #3 →
**C 1 and 2**, both triggers, not one.
⛔ **This arc CANNOT be self-validated.** Per spec §10.6 the instruction-file set is snapshotted
at session start, so a file written mid-session reaches neither that session nor its subagents:
**AC1 and AC2 are both next-session criteria and the arc ends in a handoff by construction.**

**Goal:** Move ARIA's always-on rules from a capped hook channel onto the file channel probe C
proved, so the payload no longer depends on an undocumented, per-tool, remotely-mutable cap — and
so the rules reach **subagents**, which today receive none of them.

**Architecture:** Split by **mutability**, not by audience or fidelity (spec §10.7). A bundled,
byte-identical file carries the behaviour — all 38 rules plus all 8 directives with every variant,
their gates rewritten as conditionals the *model* evaluates. A second, generated file carries the
U-rule title index. The hook is reduced to the resolved config *values* the model cannot otherwise
see. A truncated hook then costs only "which posture is selected", for which the file states a safe
default.

**Tech Stack:** POSIX `sh` (hooks), the plugin's shell test harness (`tests/run.sh` +
`tests/helpers.sh`), `jq`, markdown.

**Spec:** `docs/superpowers/specs/2026-08-25-always-on-rules-delivery-design.md` — **§10.7 and
§10.8 are the load-bearing reads.** §10.8 carries the per-block measurement every task below cites.

**Predecessor:** `2026-08-25-always-on-rules-delivery.md`, **SPENT** — it built the single-channel
architecture this plan supersedes. Do not re-execute it.

---

## Global Constraints

- **Repo:** `aria/aria-knowledge`. **Port:** `plugin-claude-code` **only.** The other three ports
  have the same gap and are explicitly out of scope, as in the predecessor (spec §5).
- ⛔ **No payload may be sized against the cap.** §10.7: the threshold is
  `min(tool.maxResultSizeChars, ceiling)` with a per-tool override behind a server-side gate. Any
  step whose correctness argument is "it fits" is wrong even when the arithmetic is right. The
  correctness argument must be "truncation is no longer damaging."
- ⛔ **No flag day.** At no point may an install exist for which the rules reach neither the file
  nor the hook. The hook's shrink is **conditional on the file being present** (T4), never a
  version cutover.
- **Shell dialect is POSIX `sh`.** No `[[ ]]`, no arrays.
- **Every directive's text is copied VERBATIM** from `session-start-rules.sh` into the file. A
  reworded directive is a behaviour change that reads as a copy. Only the *framing sentence* naming
  the condition is new prose.
- **Directory-dependent Bash calls carry their own parenthesised absolute `cd`** — `(cd "$ARIA_REPO/…" && cmd)`.
  A bare leading `cd` is blocked by a PreToolUse hook.
- **Never pipe a command whose exit code you will cite.** Read the bare exit code in its own call.
- **Set `ARIA_REPO` once:** `ARIA_REPO="$(git -C . rev-parse --show-toplevel)"`. This repo is
  public; no hardcoded home paths in tracked files.
- **One concern per commit.** Do not squash.

---

## Standing cost — stated because capacity alone is not a reason to spend it

⛔ **Gate finding, and the reason ASK #1 exists.** Spec §10.4 ruled the file channel on
*fidelity* grounds against a cost table (§6) that is stamped STALE and models only the hook
emission. Measured this session:

| | Delivered to model context | ~Tokens |
|---|---:|---:|
| Today (hook, capped at the 2,000-ch preview) | 2,000 ch | ~500 |
| After the split (file 20,196 + user-rules 3,277 + hook 250) | 23,723 ch | ~5,930 |
| **Increase — every session, every project, permanently** | **+21,723 ch** | **~+5,430 (11.9×)** |

⚑ **§6's central claim inverts under §2.6.** It argues *"the rest is not new spend — those
characters are already generated and rendered today."* Generated-and-**discarded** costs the model
nothing; generated-and-**delivered** costs it everything. The finding that motivates this split is
the same finding that invalidates the cost table justifying it. ⚠ For scale: the spec called probe
C's ~8k tok/session *"a cost in EVERY session in EVERY project"* and had it deleted on those
grounds; the permanent file is **63% of that probe's size** and is never deleted. It also reaches
projects with no ARIA involvement, because `~/.claude/rules/` is user-scope and unconditional.

✅ **RULED A1, Mike 2026-08-26 — accepted as designed.** The cost is now a disclosed, ruled trade
rather than an unstated one, and it must be named in the release notes (T6). ⛔ Do **not** re-open
this as a reason to trim the digest later: option (3) in the gate report was rejected precisely
because §10.2 measured that a title alone is not a sufficient trigger for the rules whose text *is*
the instruction.

**This is not an argument against the design** — the alternative is rules that reach nobody, and
the maintainer already carries 331 KB of always-on context by choice. It is an argument that the
number must be **ruled, not assumed**, since the ruling that chose this channel predates it.

## The forks that are Mike's, not the executor's

⛔ **Gate 2 must not resolve these. They are judgment calls with no measurable answer, and each
changes what gets built.** Options are enumerated with what each costs; recommendations are stated
but not pre-confirmed.

### Fork A — ✅ RULED **B1** (Mike, 2026-08-26): the hook writes it when absent

This is the **highest-stakes** question in the plan, because getting it wrong is a silent
regression for every existing user: they would go from *truncated rules* to *no rules at all*.

1. **The hook writes the file if it is missing, and emits the legacy payload for the current
   session.** Fully self-healing, zero user action, no flag day. Per §10.6 the file takes effect
   next session, and the legacy emission covers the lag. **Cost: a plugin writes to `~/.claude/rules/`
   without being asked.** That is user scope, not a shared repo — materially less invasive than the
   `CLAUDE.md` write §4.4 deliberately gates behind a default-no prompt — but it is still an
   unprompted write to user config.
2. **`/setup` writes it; the hook falls back to the legacy payload forever if absent.** No
   unprompted write. **Cost: most existing installs never converge**, so the subagent fix and the
   cap fix reach only users who re-run `/setup` — i.e. the defect stays live for the majority.
3. **The hook writes it only after a one-time prompt** (default-no, like §4.4). Consent preserved,
   convergence likely. **Cost: the prompt renders on `systemMessage`, which reaches the user but
   not the model — so a user who ignores it stays on option 2's outcome, silently.**

✅ **RULED: (1), narrowed.** Mike's condition — *"only triggered once per session and not every
tool use"* — is satisfied, and the answer to *which hook* is **`SessionStart`, via the existing
`bin/session-start-rules.sh`**:

- **It cannot fire per tool use.** `PostToolUse` is the only per-tool-call event; this is a
  different event. Structural, not a matter of configuration.
- **Zero new process spawns.** That script already runs at SessionStart, already sources
  `config.sh`, already resolves the knowledge folder. The addition is one guarded line.
- ⭐ **The absence guard, not the firing count, is what enforces the condition.** Both SessionStart
  entries register with **no matcher**, so they fire on `startup`, `resume`, `clear` and `compact`
  alike. Measured against a SessionStart hook that keeps a run log: **518 fires / 366 clusters at a
  ≤10 s gap = 1.42 fires per cluster** (233 singles · 116 doubles · 15 triples · 2 quads).
  ⚠ **Bound: that log has no session id and this workspace runs concurrent sessions, so one session
  firing twice is indistinguishable from two sessions firing once.** The guard makes it moot —
  exactly one write happens regardless, and every later fire costs one `stat`.
- ⛔ **Do NOT "fix" this by narrowing the matcher to `startup`.** That would mean a `/clear` or a
  resume never repairs a missing file. Absence-guarding is strictly better than matcher-narrowing.

⏳ **One sub-decision this ruling does not cover, surfaced rather than buried:** *write-only-when-
absent* means a plugin upgrade that changes the digest **never reaches an existing install**. Same
silent-staleness class the arc exists to fix. Planned fix — a version marker on the file's first
line, refreshed when the plugin version moves; one `head -1` per session. That is the only case in
which the hook overwrites, and it overwrites a **bundled artifact**, never the user's own
`working-rules.md`. Mike can veto; it is one line of T2.

### Fork B — ✅ RULED **C 1 and 2** (Mike, 2026-08-26): both triggers, not one

Every option carries a one-session lag (§10.6), so the question is only which trigger is least
surprising.

1. `/setup` and `/rules` regenerate it. Explicit; silently stale between runs.
2. A `PostToolUse` hook on writes to `user-rules.md`. Event-driven, matches the `MEMORY-FULL.md`
   precedent live in this workspace, and the lag is attributable to the edit the user just made.
3. The SessionStart hook rewrites it every session. Self-healing; writes user config every launch.

✅ **RULED: (1) AND (2) together** — `/setup` and `/rules` regenerate it, **and** a `PostToolUse`
hook on writes to `user-rules.md` regenerates it. Not either/or.

⚑ **Why both is the right shape rather than redundant:** they cover disjoint failure modes. (2)
catches the common case — the user edits a rule and the index follows — but cannot fix an index that
is already wrong, missing, or was never generated. (1) is the repair path for exactly that, and it
is the path `/setup` already walks on a fresh install. Neither alone converges from an arbitrary
starting state.

⛔ **(2) must filter cheaply and FIRST.** `PostToolUse` fires on every `Edit|Write`, so the hook's
first act is a path test that exits non-zero-cost only for `user-rules.md`. The precedent is in this
repo: `post-edit-check.sh` reads the tool input, extracts `file_path`, and branches with a `case`
before doing any real work. Follow that shape — **do not source config or read files before the path
test.** ⚠ This is the one place in the arc where a hook runs per tool use, and it is accepted because
its body is a string comparison.

---

## File Structure

```
plugin-claude-code/
  rules/aria-rules.md            # T1 — restructured: digest + all 8 directives, all variants
  bin/session-start-rules.sh     # T4 — reduced to config values; conditional legacy fallback
  bin/aria-write-user-rules.sh   # T3 — NEW: generates aria-user-rules.md  (shape depends on Fork B)
  tests/test-aria-rules-digest.sh # T0, T5 — ratchet made deterministic, then lowered
  skills/setup/SKILL.md          # T2 — writes/refreshes the user-scope rules file
```

---

## Task 0: Make the delivery ratchet measure the right thing

**Why first:** every later task's acceptance is measured by this guard, and it is currently
environment-dependent. Lowering a ratchet with a 403-char environmental component is how a green
suite on one machine becomes a red suite on another. Spec §10.8, final subsection.

- [ ] **Step 1 — Reproduce the defect two-sided before changing anything.** Run the worst-case
      fixture with the real `$HOME` and again with `HOME` pointed at an empty directory. Expect
      **20,322** and **19,919** path-normalised chars, and the long vs short TASK BUDGET variant
      respectively. If the numbers differ from these, stop: the defect has moved and the fix below
      is aimed at the wrong thing.
- [ ] **Step 2 — Make the fixture control `$HOME`.** Point it at a temp home and create a stub
      `aria-statusline-state-*.json` there, so the LONG variant fires deterministically on every
      machine. ⛔ Do **not** fix this by deleting the branch or by lowering the ceiling — the goal
      is a deterministic maximum, not a smaller one.
- [ ] **Step 3 — Add the missing maximality assertion.** The fixture already proves it fires the
      long U-rule variant; add the sibling proving it fires the **long TASK BUDGET** variant. State
      in a comment that a maximality proof must cover every branch that changes size, or it bounds
      a payload it has not shown to be maximal.
- [ ] **Step 4 — Mutation-verify.** Remove the stub statusline file from the fixture; the new
      assertion must go RED. Restore from a byte backup (`cp`, not `git checkout --`, which would
      discard uncommitted work in a shared tree) and `cmp` to confirm restoration.
- [ ] **Step 5 — Gate.** `sh plugin-claude-code/tests/run.sh`, bare exit code read in its own call.
      Baseline before this task is **213 passed / 0 failed**; expect 214+ after.
- [ ] **Step 6 — Commit.** `fix(tests): make the delivery ratchet independent of $HOME`

## Task 1: Restructure `rules/aria-rules.md` into the full static file

Spec §10.8. Measured floor **18,943 B** (12,166 digest + 6,777 of directive literals) plus framing.
Probe C proved the channel at 32,056 B in one file and 34,394 B aggregate.

- [ ] **Step 1 — Append the two unconditional directives verbatim**: RULE 22 ORDERING (709 ch) and
      MEMORY PATHWAY (319 ch). No gate, no framing needed beyond a heading.
- [ ] **Step 2 — Append TASK BUDGET as a model-evaluated conditional.** Both variants (739 + 346),
      behind one sentence naming the condition: whether `~/.claude/aria-statusline-state-*.json`
      exists. This block needs **no** hook value — the model can check it.
- [ ] **Step 3 — Append the four config-gated directives**, each with every variant, keyed by the
      config value: INSIGHT CAPTURE (211, `auto_capture`), ARIA ACTIVE CONTEXT (881,
      `active_surfacing` + index state), SESSION STATE (1,608, `session_state`), DECISION ROUTING
      (763 balanced + 1,201 autonomous, `autonomy`).
- [ ] **Step 4 — State the degradation defaults explicitly.** For each config-gated block, one
      sentence for the case where no value was received: *"if no `autonomy` value is present, treat
      it as `default`, which adds no routing directive."* ⛔ **This is the step that makes the design
      degradation-tolerant rather than cap-fitted — it is the reason the split is safe, not the
      size.** Do not drop it as boilerplate.
- [ ] **Step 5 — Replace the KF interpolations with a stated reference.** Three directives
      interpolate the knowledge-folder path. In the file it becomes a named value the hook supplies.
- [ ] **Step 6 — Extend the drift gate** to assert every directive present in
      `session-start-rules.sh` is also present in the file, by name. A new directive added to the
      hook and not the file must go RED. Mutation-verify by deleting one directive from the file.
- [x] **Step 6b — GATE (ASK #1): RULED A1 by Mike 2026-08-26** — the standing cost is accepted as
      designed. Carry the number into the release notes (T6 Step 2); do not treat it as settled
      quietly, and do not re-open it later as a reason to trim the digest.
- [ ] **Step 7 — Human review gate (Mike).** The file is what every user reads every session. It is
      not merely a size change; it is new prose framing 8 directives. **Tasks 2–5 wait on this.**
- [ ] **Step 8 — Commit.** `feat(rules): carry every directive and variant in the static digest`

## Task 2: `/setup` installs the user-scope rules file

✅ **UNBLOCKED — Fork A ruled B1.** Two writers, one target.

- [ ] **Step 1** — `bin/session-start-rules.sh` writes `~/.claude/rules/aria-rules.md` **when
      absent**. Guard on absence first; the guard is what makes the firing count irrelevant.
- [ ] **Step 2** — Version marker on the file's first line; refresh when the plugin version moves.
      One `head -1` per session. ⛔ This is the **only** overwrite path, and it overwrites a bundled
      artifact — never the user's own `working-rules.md`.
- [ ] **Step 3** — `/setup` writes it too, and reports the write plainly, naming the path. A user
      running `/setup` should not have to wait for a session restart.
- [ ] **Step 4** — Test the matrix: absent → written · present-and-current → untouched (assert **no
      write**, not merely identical content) · present-and-stale-version → refreshed · present-and-
      hand-edited-at-current-version → **untouched**.
- [ ] **Step 5** — Measure the added SessionStart cost in the steady state. It must be one `stat`
      plus one `head -1`; if it is more, the guard is in the wrong order.
- [ ] **Step 5 — Commit.** `feat(setup): install the always-on rules file to user scope`

## Task 3: The generated U-rule index file

⚠ **Shape depends on Fork B.** Spec §10.8: this block cannot stay in the hook — at its own
3,000-char branch point plus a config block it lands ~3,527 ch, above the 3,321 ch proven safe.

⛔ **GATE FINDING — T3 and T4 contradicted each other as originally written**
(`relocation-without-a-retirement-lane`). "Extract into a script" reads as a *move*, but T4's
legacy fallback arm must still emit this index for installs without the file. As written the
logic would be either **duplicated with no gate**, or the fallback would be **silently
incomplete**. **The retirement lane, named:** the generator becomes ONE shared `sh` function with
TWO callers — the new writer script and the hook's fallback arm — and the second caller is retired
only when the fallback arm itself is.

### T3a — extract the generator (UNBLOCKED, no fork dependency)

- [ ] **Step 1** — Extract the index generation from `session-start-rules.sh:57-73` into a shared
      function in a sourceable file. Logic byte-unchanged, including the 3,000-char overflow
      fallback. ⛔ **One implementation, two callers** — do not copy it.
- [ ] **Step 2** — Point the hook's existing emission at the shared function. No behaviour change;
      the emission must be byte-identical before and after. Assert that, do not assume it.
- [ ] **Step 3** — Add the writer script that renders the same function's output to
      `~/.claude/rules/aria-user-rules.md`.

### T3b — wire BOTH regeneration triggers (✅ UNBLOCKED — Fork B ruled C 1+2)

- [ ] **Step 4** — Wire the `PostToolUse` trigger on `Edit|Write`. ⛔ **Path test FIRST**, before
      sourcing config or reading anything — follow `post-edit-check.sh`'s shape. Exit immediately
      unless the written path is the configured `user-rules.md`.
- [ ] **Step 5** — Wire the `/setup` and `/rules` regeneration path, as the repair route for an
      index that is missing, stale, or was never generated.
- [ ] **Step 6** — Test that the two triggers converge from every starting state: no file · stale
      file · current file · file present with `user-rules.md` deleted.
- [ ] **Step 7** — Measure the `PostToolUse` cost on a NON-matching path. This hook now runs on
      every edit in every project; if the non-matching path costs more than a `case` test, it is
      wrong. Assert it.
- [ ] **Step 3** — Absent or empty `user-rules.md` must write **no file at all**, not an empty one —
      the current "injects nothing" behaviour is correct for a brand-new user.
- [ ] **Step 4** — Test both tiers and the zero case; mutation-verify the overflow branch.
- [ ] **Step 5 — Commit.** `feat(rules): deliver the user-rule index through the file channel`

## Task 4: Reduce the hook to resolved config values

- [ ] **Step 0 — Enumerate what already tests this file, BEFORE rewiring**
      (`enumerate-existing-tests-of-touched-files-before-rewiring`). Several assertions in the
      21,842 B suite grep the emission for directive text; those become false under the
      file-present arm. They must **move to the fallback arm**, not be deleted — a deleted
      assertion and a relocated one look identical in a green run.
- [ ] **Step 1 — Add the presence check.** If `~/.claude/rules/aria-rules.md` exists, emit config
      values only. If it does not, emit the legacy payload unchanged. ⛔ **No flag day** — this
      branch is the whole migration story and must land before any payload is removed.
- [ ] **Step 2 — Emit the config block**, ~250 ch (estimate — measure it, do not assume):
      `autonomy`, `session_state`, `auto_capture`, `active_surfacing`, `knowledge_folder`.
- [ ] **Step 3 — Test both arms.** File present → config-only, and the legacy directives absent.
      File absent → legacy payload byte-identical to today's. Assert **both**; a test of only the
      new arm cannot see the regression the fallback exists to prevent.
- [ ] **Step 4 — Measure the real post-split emission** under the worst-case fixture, and record it.
- [ ] **Step 5 — Commit.** `feat(hooks): emit resolved config values, defer behaviour to the file`

## Task 5: Lower the ratchet

- [ ] **Step 0 — SHRUNK per gate:** record the measured number and assert **both arms** first;
      change the ceiling constant only once both are covered. A ratchet lowered before the
      fallback arm is asserted would accept a silently-empty fallback.
- [ ] **Step 1** — Set `ARIA_EMIT_CEILING` to the measured post-split worst case from T4 Step 4,
      plus a stated allowance. ⛔ **Record it as a downward-only ratchet, and do not justify the new
      value by its distance from 3,321** — per §10.7 that distance is not a safety argument.
- [ ] **Step 2** — Assert the *fallback* arm separately, since it is the one that can still be large.
- [ ] **Step 3** — Mutation-verify: reinstate one directive into the hook's file-present arm; RED.
- [ ] **Step 4 — Commit.** `test(rules-digest): ratchet the emission down to the post-split payload`

## Task 6: Documentation

- [ ] **Step 1** — Spec: stamp §10.8 with the built shape and the measured post-split figures.
- [ ] **Step 2** — `CLAUDE.md` footer: the arc's outcome, including that rules now reach subagents.
- [ ] **Step 3** — `CODEMAP.md` (37 days old against a 14-day threshold — refresh in this arc).
- [ ] **Step 4** — Stamp this plan SPENT on completion. **Tick every box as it lands.**
- [ ] **Step 5 — Commit.** `docs: record the file/hook split`

---

## Acceptance Criteria

- **AC1** — All 38 rule titles, including the **last**, present in a fresh session's context via the
  file channel. Proxy tests cannot close this; it is a transcript classification, next-session.
- **AC2** — All 38 rule titles present in a **subagent's** context. ⛔ **Next-session, like AC1** — a file written mid-session reaches neither that session nor its subagents (§10.6). This is the property option Z
  exists for and the one the hook channel can never satisfy (§10.6). ⚠ Per §10.6 the negative half
  of that finding was a self-report; re-derive with a positive control in the same arm.
- **AC3** — With the file present, the hook emission carries no directive text. Measured, not asserted.
- **AC4** — With the file absent, the emission is byte-identical to today's. **This is the
  no-regression criterion and the one most likely to be skipped.**
- **AC5** — Worst-case emission is deterministic across machines — same number with any `$HOME`.
- **AC6** — Every directive and every variant present in the file; drift gate RED if one is dropped.
- **AC7** — Suite green, bare exit 0, count ≥ 213 + new tests.
- **AC8** — `bin/session-start-check.sh` byte-unchanged. Inherited from the predecessor; still holds.

## Out of scope

- The other three ports (Codex, Cowork, Antigravity) — same gap, deliberately deferred (spec §5).
- The exact `additionalContext` cap (§10.5). The split's whole point is that it no longer matters.
- OQ1 / dual-field emission (§8.2).
