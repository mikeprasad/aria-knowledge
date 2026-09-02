# Design — the permission surface, and verifying the resume loop

**Date:** 2026-09-03
**Status:** DRAFT — plan gated separately. **No code until `/prospect` passes.**
**Scope:** four residuals carried out of the `/auto` resume-and-restart arc, resolved to end states.
**Prior art:** `2026-08-31-auto-resume-and-restart-per-wall-per-runtime-design.md` (D1–D11),
`logs/prospect/2026-09-01-file-auto-resume-and-restart-*.md`,
`logs/retrospect/2026-09-01-range-auto-resume-and-restart-phases-a-b.md`

**Mike's framing:** *"lets resolve B C D and E properly, best long term end state."*

---

## ⛔ Headline — this spec opens by falsifying two of its own prior arc's conclusions

**Claude Code runs a built-in set of Bash commands as read-only, with no permission prompt in any
mode, and the set is NOT configurable.** Official docs, `code.claude.com/docs/en/permissions`:

> *"Claude Code recognizes a built-in set of Bash commands as read-only and runs them without a
> permission prompt in every mode. These include `ls`, `cat`, `echo`, `pwd`, `head`, `tail`,
> `grep`, `find`, `wc`, `which`, `diff`, `stat`, `du`, `cd`, and read-only forms of `git`. The set
> is not configurable"*

Two consequences, both retractions:

**(1) The arc's validating probes could not validate.** Probe 2 used `ls`; R2 used `git log`. Both
are in that set, so both would have executed **with or without** any `permissions.allow` entry.
Neither probe could distinguish *"the allowlist cleared the gate"* from *"the command never met the
gate."* ⇒ **D10's premise is UNPROVEN, not validated.** This is
`control-cannot-split-the-live-hypotheses` — persisted from this same arc — firing on the two
probes the design rests on. *(Probe 1's stall remains valid and informative: `printf` is absent
from the set, which is exactly why it stalled.)*

**(2) Phase C, already shipped, may be a no-op grant.** It offers `Bash(head:*)`, `Bash(tail:*)`,
`Bash(git merge-base:*)` — all three are in the built-in set. A grant that widens standing
permissions for zero benefit is worse than no grant. **See D-C1 for the disposition.**

⏳ **One probe is in flight and decides both.** `npm list --depth=0` — allowlisted as
`Bash(npm list:*)`, and `npm` is **not** in the built-in set — run in an unattended scheduled task.
Executes ⇒ allow rules do function there, D10 validated at last. Stalls ⇒ allow rules do **not**
help a scheduled task, and only built-in read-only commands run unattended. **Both branches are
specified below; do not execute this spec's plan without the result.**

---

## B — settings precedence: RESOLVED from official docs

**Ranking is `deny` > `ask` > `allow`, evaluated across ALL scopes before file precedence, and
independent of specificity.** Verbatim:

> *"if user settings allow a permission and project settings deny it, the deny rule blocks it. The
> reverse is also true: **a user-level deny blocks a project-level allow, because deny rules from
> any scope are evaluated before allow rules.**"*

> *"The same precedence applies between ask and allow: **a matching ask rule prompts even when a
> more specific allow rule also matches the same call.**"*

And lists **merge** rather than replace:

> *"When you set the same list key, such as `permissions.allow`, in more than one file, Claude Code
> combines the lists instead of picking one"*

**File precedence, for keys that are not lists:** managed > command line > project local
(`.claude/settings.local.json`) > shared project (`.claude/settings.json`) > user
(`~/.claude/settings.json`).

**D-B1 — the answer to the arc's open question.** `Bash(git push:*)` is `allow` at project scope;
`Bash(git push *)` is `ask` at user scope. **The `ask` wins.** So an unattended task reaching
`git push` **prompts**, and with nobody to answer it **stalls silently** — it does not push
silently. That is the safer of the two outcomes the arc feared, and it is already covered by the
contract line shipped in Phase B (`durable resume: ARMED | UNAVAILABLE`).

**D-B2 — deny is the lever, and this is what makes E tractable.** Because a user-scope `deny`
beats a project-scope `allow`, the exec vectors in E can be closed **additively**, with no removal
and no friction increase. The arc's earlier reasoning — *"prefer narrowing the allow, because deny
is unverifiable in-session"* — is **superseded**: the docs are a better instrument than a probe
that cannot run, and Rule 33 routes to current docs first.

---

## E — the exec surface: four vectors measured, and one of them is open-ended

All measured 2026-09-01/03 in a scratch repo with injected-marker probes.

| Vector | Verified | Note |
|---|---|---|
| `--upload-pack=<cmd>` | ✅ executes | `ls-remote`, `fetch`, `clone`, `pull` |
| `--receive-pack=<cmd>` | ✅ executes | `push` |
| `--exec=<cmd>` | ✅ executes | **synonym for `--receive-pack`**; also `git archive --exec` |
| **`git -c <key>=<cmd>`** | ✅ executes | `core.fsmonitor` executed; **`alias.x='!<shell>'` executed** |

⛔ **`git -c` cannot be enumerated by config key.** Alias injection (`-c alias.zz='!<shell>' zz`)
runs arbitrary shell, so a key-by-key denylist is whack-a-mole by construction. `core.fsmonitor` was
one instance, not the boundary. ⚠ Short forms tested and **do not** execute (`git ls-remote -u`,
`git fetch -u` both returned nothing), and `-u` means `--set-upstream` for `push`, so denying it
would break legitimate work. **Do not deny `-u`.**

**D-E1 — the single worst entry is `Bash(git *)`, and it is already present.** It matches every git
command, and the docs' own table confirms the shape: *"`Bash(git * main)` matches … `git -c
core.fsmonitor=<script> diff main`"*. ⇒ **that one entry grants arbitrary command execution**, and
it subsumes the 21 other git allow entries.

**D-E2 — the end state is ADDITIVE DENIES, not removals.** Four user-scope deny rules:

```
"Bash(git -c *)"
"Bash(* --upload-pack*)"
"Bash(* --receive-pack*)"
"Bash(* --exec*)"
```

Rationale, and why this beats the alternatives:
- **Deny outranks allow from any scope** (D-B2), so these close the vectors while `Bash(git *)`
  keeps working for `git merge`, `git checkout`, `git worktree`, `git cherry-pick` — none of which
  any other entry covers.
- **Removing `Bash(git *)` was considered and rejected:** it would start prompting for those
  commands, and this workspace runs 9 worktrees. A remedy that adds friction to daily work is a
  remedy that gets reverted.
- `*` is documented to work at the start, middle or end of a Bash rule, and the pre-subcommand-`*`
  startup warning applies to **allow** rules only — so a leading-`*` deny is a sanctioned shape.

⚠ **Stated bound, not glossed:** this closes the *measured git* vectors. `Bash(ssh *)` and
`Bash(curl *)` remain open-ended and are **out of scope** — they are presumably load-bearing for
staging work, and Mike's standing preference on pre-existing wide entries is documented exposure.
D11 records the standard; this closes the part that is closable without cost.

⛔ **D-E2a — `Bash(git -c *)` CANNOT SHIP YET. `git -c` and `git -C` differ only in case, and this
user has SEVEN allowlisted `git -C <path>` entries.** If Claude Code's Bash matcher is
case-insensitive, that deny blocks all seven — and deny beats allow, so re-adding them would not
help.

**The docs do not settle it.** They state *"Matching is case-insensitive"* explicitly for
**PowerShell** rules and for **WebFetch** rules, and say **nothing** for Bash. Inferring
case-sensitivity from that silence is precisely the shape this arc has been burned by; it is an
absence, not a measurement. ⇒ **unresolved, and it gates the most important vector.**

⇒ **Ship in two steps.** The three flag denies (`--upload-pack`, `--receive-pack`, `--exec`) have
no case-differing sibling and are unambiguous — they go first. `git -c` waits on OQ4.

**Two candidate resolutions for `git -c`, both real, neither free:**
1. **Settle the case question**, then ship `Bash(git -c *)` — cheapest if matching is
   case-sensitive. Resolution method: add the deny in a scratch settings scope and observe a
   `git -C` call in a **fresh session** (settings arm at session start), or ask Mike to run one.
   ⚠ A discriminating variant exists — `Bash(git -c *=*)` requires an `=`, which `git -C <path>
   <subcommand>` does not contain — but it is only a mitigation, not a resolution, and it fails if
   a path ever contains `=`.
2. **Remove `Bash(git *)` and enumerate the subcommands in use** — then `git -c …` matches no allow
   rule at all and needs no deny. Costs a subcommand census and more entries, and re-opens the
   friction objection D-E2 rejected. ⚠ The census cannot come from
   `~/.claude/bash-discipline.log`: that log records **violations only**, so it is a biased sample,
   not a usage census.

⚠ **Simulation bound:** the deny set was validated against 6 malicious and 17 legitimate commands
with **zero** unblocked-malicious and **zero** false positives — but via Python `fnmatch`, **not**
Claude Code's matcher, which is shell-operator-aware and splits compound commands. That is *design*
validation. Behaviour validation needs the rules in place plus a fresh session (AC2).

**D-E3 — 28 of 161 allow entries are redundant, but only 13 are safely removable.** Censused
2026-09-03. The built-in read-only set makes an allow rule for those commands a no-op. **But the
docs carry an exception:** *"commands with write-capable or exec-capable flags, such as `find`,
`sort`, `sed`, and `git`, prompt when an unquoted glob is present."*
⇒ `Bash(find:*)` and the read-only-`git` entries are **NOT** purely redundant — they cover the glob
case. Only the no-exec-flag commands are: `ls cat echo pwd head tail grep wc which diff stat du cd`.
Several are also **duplicated across both settings files**. Removal is optional clarity with zero
behaviour change; it is not required by D11 and should not be bundled with the deny work.

---

## D — the ratchet, and a real permissions audit

**D-D1 — it belongs in `/audit-config` Step 2, which already owns this.** That step already
instructs *"Check all `Bash(...)` permission paths exist on disk"* and *"Flag stale or redundant
permissions."* The second instruction was **unrunnable until now** because the built-in read-only
set was not known. This spec supplies the missing input.

Three checks, all derived from measurements above:

1. **Arc-resume set assertion** — assert the permitted set equals exactly what was decided, per apex
   decision `2026-015` (*assert the set, never a count*), so a new entry is a visible diff.
2. **Redundant-grant report** — flag allow entries for built-in read-only commands (13 safely
   removable; report `find`/read-only-`git` separately as glob-covering, not redundant).
3. **Exec-capable-grant report** — flag any allow pattern that admits `git -c`, `--upload-pack`,
   `--receive-pack` or `--exec`, and report whether the corresponding denies are present.

**D-D2 — report, never mutate.** `/audit-config`'s existing contract is Step 6 *Present Findings* →
Step 7 *Wait for User Review*. These checks report; they do not edit `permissions`. That keeps D10's
rule intact: **`/setup` is the only writer, and `/auto` never widens permissions.**

---

## C — verifying the resume loop

**Current state:** every link is measured (fresh context per run; `fireAt` firing; `/handoff`
writing a prose-first opener) and the composition has never run. Classified
`NO-MOVEMENT-STRUCTURAL` in both gates — a real context wall cannot be induced cheaply.

**D-C1 — the end state is a REHEARSAL PROCEDURE, not waiting for reality.** Waiting makes
verification an accident of when a window happens to fill. A rehearsal makes it exercisable on
demand, forever, and is the foundational answer:

1. Pick a trivial, idempotent goal with a checkable artifact (e.g. append one dated line to a
   scratch file).
2. Run the branch's four steps **manually at a chosen moment**, not at 90% context:
   `/extract` → `/handoff` → `create_scheduled_task(fireAt = now + 2 min)` → stop.
3. Verify by the **task-produced artifact**, never `lastRunAt` — D7: a stalled task sets
   `lastRunAt` and disables itself while executing nothing.
4. Record the result with its date, and re-run after any change to `/handoff` or the branch.

⏳ **Blocked on the in-flight probe, and the two branches differ in kind:**
- **Probe EXECUTES** ⇒ a resumed task can run allowlisted non-builtin commands. The rehearsal is
  worth building and the branch is sound. Proceed with D-C1.
- **Probe STALLS** ⇒ a resumed task can run **only built-in read-only commands**. It could not
  `git commit`, run a test, or do anything an arc needs. **The Desktop context-wall branch would be
  unworkable as designed, not merely unexercised** — and Phase B's B3 would need retraction, not
  rehearsal. Escalate to Mike rather than patching.

**D-C2 — Phase C's disposition depends on the same probe.** If the probe stalls, Phase C's knob is
a no-op grant and should be **reverted** (`2da33ce`). If it executes, the knob is still offering
three built-in read-only patterns and should be **re-scoped** to the commands an arc actually needs
that are *not* built-in — which, measured against this user's config, are already present
(`Bash(git add:*)`, `Bash(git commit:*)`, project build/test entries). Either way **the shipped
three-pattern set is wrong**; only the reason differs.

---

## Acceptance criteria

- **AC1** — Every clause in the shipped `/auto` and `/setup` prose that asserts D10's premise as
  *validated* is corrected to reflect the probe's actual result. Falsifier: a grep for
  "two shapes" / "validated" in the durable-resume sections returning a claim the probe didn't support.
- **AC2a** — The **three flag denies** (`--upload-pack`, `--receive-pack`, `--exec`) are present in
  `~/.claude/settings.json`, and a post-change probe confirms at least one vector is closed.
  ⚠ **Not verifiable in the session that adds them** — settings arm at session start; verification
  requires a fresh session.
- **AC2b** — `Bash(git -c *)` ships **only after OQ4 is settled**, and its acceptance includes a
  positive check that a `git -C <path> status` call still works. Falsifier: that call starts
  prompting or failing ⇒ the deny is case-insensitive and must be withdrawn, not tuned.
- **AC3** — `Bash(git *)` still permits a legitimate command (`git worktree list`) after the denies
  land. This is the no-friction assertion, and it must be run: a deny that also blocks daily work
  is the remedy that gets reverted.
- **AC4** — `/audit-config` Step 2 carries the three checks, each reporting and none mutating.
- **AC5** — The redundant-grant report names 13 safely-removable entries and lists `find` +
  read-only-`git` separately as glob-covering. Mutation: classify them together and the report
  recommends removing a grant that is doing work.
- **AC6** — Phase C is either reverted or re-scoped, with the reason stated, and its `/setup` knob
  no longer offers a built-in read-only pattern.
- **AC7** — The rehearsal procedure (D-C1) is recorded where the branch is documented, and has been
  run once with its result dated.

## Open questions

- **OQ1** — the in-flight probe. Blocks C and Phase C's disposition. Resolves within minutes.
- **OQ2** — does `ssh *` / `curl *` warrant the same treatment? Out of scope by Mike's standing
  preference, but D11 now gives a standard they do not meet. His call, not this spec's.
- **OQ3** — AC2a's verification needs a fresh session. Should the plan stop at "denies added,
  verification owed", or should it end with a stamped fresh-session check? Sequencing question for
  the plan.
- **OQ4 — is Claude Code's Bash rule matching case-sensitive?** Gates the single most important
  deny (`git -c`, the open-ended vector) against 7 working `git -C` entries. **Docs are silent**;
  they state case-insensitivity for PowerShell and WebFetch only. Not inferable from that silence.
  Resolution is a fresh-session observation or Mike's own check — see D-E2a for the two candidate
  paths. ⚠ Until settled, the flag denies ship and `git -c` does not.
