# Design — runtime gates self-correct instead of asking; bare forms belong to Code

**Date:** 2026-08-28
**Status:** DRAFT — plan gated separately before any code.
**Ruling:** Mike, 2026-08-27/28: *"instead of asking the user if they want to instead use the
correct aria knowledge command, it should automatically do it… always use the correct skill for
the current mode if called by mistake"* + *"lets have the /skillname prioritize the code version
and cowork can use the /aria-cowork:skillname"*.

## The problem

Every dual-port skill carries a **Runtime Gate** that detects a runtime mismatch correctly and
then **stops to ask `y/n`**. The gate text already concedes the point — it says *"This is the
default-yes path — auto-redirect is the helpful action"* — and asks anyway. The cost is a stall
on the one path where the right answer is knowable without the user.

Detection is already sound and needs no new machinery:
- **Cowork variant, `Bash` IS available** ⇒ running in Claude Code ⇒ the Code variant is correct.
- **Code variant, `Bash` is NOT available** ⇒ running in Cowork ⇒ the Cowork variant is correct.

## Two changes, and they compose

**D1 — bare forms resolve to Code; Cowork is namespaced-only.**
This is ADR-094 §Part 1's existing rule, and it is enforced by **description content**, not by any
harness resolution rule: Code descriptions advertise the bare triggers, Cowork descriptions
advertise only `/aria-cowork:<x>` and carry a `(Cowork variant — namespaced-only.)` marker.
⛔ **Measured: 22 of 24 cowork skills already comply. Exactly one is defective** —
`plugin-claude-cowork/skills/interview/SKILL.md` advertises bare `'/interview'` and carries no
marker, while Code ships a colliding `interview`. `aria-setup` and `daily-audit` also lack the
marker and are **correct**: their names are deliberately distinct from Code's (`setup`,
`aria-assist`), so no bare collision exists to resolve.

**D2 — the gate redirects automatically, both directions.**
Replace ask-then-wait with: state the mismatch in one line, invoke the counterpart with the
original arguments, do not run this variant's steps.

**D5 — together they are self-correcting, which is why both ship at once.**
D1 decides *which variant a bare invocation reaches*; D2 decides *what happens when that is wrong
for the runtime*. With both: bare `/x` → Code variant → auto-redirects to Cowork if the runtime is
Cowork. `/aria-cowork:x` → Cowork variant → auto-redirects to Code if the runtime is Code. Neither
entry point can strand the user, and neither change alone achieves that.

## Decisions

**D3 — no escape hatch.** Dropping the `n` branch removes the ability to force the mismatched
variant. That is not a loss worth machinery: the Cowork variant running inside Code is *strictly
worse* — it skips `~/.claude/projects/.../memory/` and `~/.claude/plans/` precisely because it
assumes no shell — so there is no legitimate reason to want it. Port inspection is done by reading
the file. Reversible in one line per gate if this proves wrong.

**D4 — a gate with no counterpart must NOT auto-redirect.** Seven Code gates have no Cowork
twin: `audit`, `audit-rules`, `audit-style`, `audit-usage`, `auto`, `recap`, `roadmap`. They keep
their current shape. ⛔ This is the v2.49.0 lesson, shipped hours earlier: **a redirect gate is
only honest when a redirect target exists**; where none does, the correct construct is a
capability precondition. Three of those seven were converted for exactly this reason. Auto-
redirecting them would recreate the bug just fixed.

**D6 — the redirect announces itself.** One line naming what was invoked, what is running
instead, and why. A silent variant swap is worse than the stall it replaces.

**D7 — the auto-mode carve-out is retired.** Every gate currently ends with *"This gate applies
even when `mode = auto`… auto-mode's implicit-yes is suspended for the runtime-mismatch check."*
That paragraph exists only because the gate was a question. With no question, there is nothing for
auto mode to bypass, and the paragraph becomes a claim about a branch that no longer exists.

## Scope (censused, not estimated)

| Surface | Count | Note |
|---|---|---|
| Cowork gates with a Code counterpart | **22** | all in scope |
| Code gates with a Cowork counterpart | **22** | in scope |
| Code gates with **no** counterpart | 7 | ⛔ excluded by D4 |
| Cowork descriptions advertising a bare form | **1** | `interview` (D1) |

**45 files.** ⚠ Four carry **non-standard gate scaffolding** and need individual handling rather
than a uniform transform: cowork `foundational-review`, `interview`, `readiness-audit`; Code
`interview`. (Measured by absence of the `Wait for an explicit reply` block.)

## Test posture

⛔ **Zero tests currently touch any of the 57 runtime gates in either plugin** — measured across
both suites. So the present behaviour is unguarded and the new behaviour would be too. Coverage is
part of this work, not a follow-up:
- every in-scope gate names its counterpart and contains no `y`/`n` wait;
- the 7 D4-excluded gates still contain **no** auto-redirect (the guard that keeps D4 from decaying);
- `interview`'s cowork description advertises no bare form, with a positive control proving the
  check can see one.

## Open question for execution

**OQ1 — natural-language triggers are shared and are deliberately left alone.** Cowork `wrapup`
triggers on "wrap up", and so does Code's. Stripping them from Cowork would make Code always win
the phrase, but would leave a Cowork-only user (no Code plugin loaded) unable to invoke by phrase
at all. D5 makes this moot in the both-loaded case — whichever variant matches, the gate corrects
the runtime — so the recommendation is to change nothing here and record the reasoning.
