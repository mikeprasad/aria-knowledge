---
description: "Executed pre-completion checklist — third sibling of /prospect (before execution) and /retrospect (after shipping). Six checks, three outcomes each (PASS/FAIL/INVALID); an unrun check blocks the verdict. Catches failures that emit no error: a check whose FORM bounds what it finds, and a decision correct in isolation but wrong in context. Use BEFORE claiming done/fixed/shipped/verified/'none found', before a PR, or before posting a result on a ticket. Triggers: '/preflight', '/preflight ticket <id>', '/preflight file <path>'."
argument-hint: "[<scope>] [<scope-arg>] [--claim \"<sentence>\"] [--quick]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, WebFetch, WebSearch
---

# /preflight — the checklist you run before you report

`/prospect` looks forward at a plan. `/retrospect` looks back at shipped work. **This runs at the
moment in between: you believe you are done, and you are about to say so.**

## What this is NOT

**It is not `superpowers:verification-before-completion`,** which owns the principle — *no completion
claim without fresh verification evidence* — and owns it well. That skill answers **whether** to
verify. This one answers **what to verify**, and specifically: the checks whose *absence produces no
signal at all*.

If you have not internalised the Iron Law, read that skill first. This one assumes it and adds the
cases where you ran a verification, it passed, and the thing was still broken.

## The two failure families this exists for

Every check below descends from one of these. Neither produces an error, a failing test, or a warning.

1. **The check's FORM bounds what it can find.** A search whose pattern bounds its result; a review
   whose scope bounds its result; a probe whose anchor bounds its result. The instrument reports
   truthfully about the thing it measured — and you asked it the wrong question.
2. **A decision correct in isolation, wrong in context**, where nothing you looked at was measuring
   the part that broke. A green build measures compilation, not reachability. A docstring records a
   decision without disclosing it. A model's name states one job, not both.

> **The consequence they share: the absence of a problem signal is not evidence there is no problem.**
> Family 1 because your check couldn't see it. Family 2 because nothing was checking.

## How to run it

Work through the checks that apply to your change. **Every applicable check gets a recorded result.**
An unrun check is not a pass — it blocks the verdict.

Each check has **three** outcomes, never two:

| | |
|---|---|
| **PASS** | the check ran and the property holds |
| **FAIL** | the check ran and the property does not hold |
| **INVALID** | the check could not distinguish absence from a broken probe — **report no verdict, fix the probe** |

The third outcome is the whole point. A probe that returns "nothing found" because it was pointed at
a path that does not exist reads exactly like a clean result.

---

## P1 — Requirements diff · *does what shipped match what was asked?*

**A rationalisation in code is not a disclosure.** Nobody diffs docstrings against requirements at
review, so an omission explained in the source is invisible in exactly the place it needed a second
opinion.

1. List every field, endpoint, behaviour and response shape the request named. Mark each
   **shipped / not shipped**. Mechanical; it takes a minute.
2. Every "not shipped" goes in a **ticket comment** — not a docstring, not a commit message, not a
   PR body.
3. **"There is nowhere to store this" is a question, not a decision.** Say so and stop. Do not narrow
   the deliverable to fit the schema you found — that is the signal the request and the schema
   disagree, and that is the owner's call.
4. Check what the **UI promises** against what you returned. A surface labelled with a word the data
   cannot support is a defect even when every line is correct.
5. Where you substituted something, **name the substitution.** "Returned the resolved email instead
   of the requested username" is reviewable; silence is not.
6. **Enumerate the paths, don't re-read the diff.** A fix can close a disclosure on two code paths
   and leave it open on a third — re-reading the change will not show you the path you never touched.

---

## P2 — Consumer census · *does this symbol have a second job?*

**A model's name and fields do not tell you its jobs.** A row can be a record *and* a permission at
the same time; a delete that is obviously right for the first is a silent privilege change for the
second, and nothing in the model, the migration or your endpoint will mention it.

```bash
# every consumer, minus vendored code and migrations
grep -rn "<SYMBOL>" --include='*.<ext>' . | grep -v "/<vendor_dir>/\|/migrations/"

# of those, which sit inside an authorization decision?
grep -rn "<SYMBOL>" --include='*.<ext>' . | grep -viE "test|migration" \
  | grep -iE "allow|permission|access|authoriz|can_view|visibility|entitle"
```

1. Run it **before** writing the endpoint, not after.
2. **Write out what each consumer uses it for.** The census is worthless unread; writing it is what
   surfaces the surprise.
3. If any consumer is an authorization or access check, **a delete on that model is a permission
   change** — say so explicitly and get it ruled on rather than shipping it inside a feature.
4. Ask what the **absence** of a row means, not just its presence. Where presence grants something,
   deletion revokes it — and "cancel" is then the wrong word for the button.
5. **Beware the inverted fix.** On discovering a row doubles as a grant, do not "clean up" by
   deleting it at some lifecycle point. That revokes access. The fix is usually a new column or a
   derived flag.
6. **Aliasing:** can two rows point at the same underlying resource? If so, deleting A's "old"
   resource may destroy B's live one.

---

## P3 — Reachability · *is it actually wired in?*

**A green build measures compilation, not reachability.** A component nothing imports is tree-shaken
out: it compiles, it deploys, and it is not in the product.

**Frontend**

```bash
# does anything import it? zero here = the feature does not exist
grep -rn "<COMPONENT>" src --include='*.js' | grep -v "<COMPONENT>/"
```

After deploy, read the **source map's module list**, not the bundle's strings — a string search
cannot distinguish "not deployed yet" from "deployed but tree-shaken." Both return zero. **Always
include a control module from the same page**, or "absent" is indistinguishable from a broken probe.

**Backend / any callable**

Ask what makes it reachable, then verify *that*: a route table entry, a registered webhook, a
scheduled job actually installed, a feature flag. **Include a control** — a sibling you did not touch
— so a zero result is interpretable.

⚠ **A test that calls a function directly does not exercise its routing.** If your suite invokes the
handler rather than the URL, the suite stays green with the route deleted. That is a real gap, not a
pedantic one; check the wiring separately and say which you verified.

⚠ **Never write "build green" or "tests pass" as evidence of shipping.** Say "imported and present in
the bundle," or "routed at `<path>`," or make no claim.

---

## P4 — Census bound · *what could this search NOT have found?*

**Report the instrument, not just the result.** A census reports its own bound or it is not a census.

1. **Run ≥2 idioms.** A symbol may be reached by a bare name, a dynamic dispatch, a `**kwargs` spread,
   a re-export, or a differently-quoted string. One idiom returning zero is not absence.
2. **Census by BEHAVIOUR, not by name.** Names move; behaviour is what you care about. Resolve an
   argument back to its assignment rather than pattern-matching the call.
3. ⛔ **`grep | wc -l` cannot report failure.** A missing path, a genuine absence and a real zero all
   print `0`. Read grep's **exit code**, or verify the path first.
4. **Discount definitions, re-exports and tests.** A symbol existing is not a symbol running; what
   remains after those are removed is the answer.
5. **State the bound in the report.** "Censused X across A, B, C excluding D — this is a code census,
   not a data census." A bound stated is a bound a reader can challenge.
6. **A handed-over finding list is a LOWER bound.** Re-census in your own consumer.

---

## P5 — Non-vacuity · *did the test actually execute the code?*

**The most dangerous green is the one that ran nothing.** A request refused upstream, a fixture
missing a field, an exception swallowed into a success envelope — the assertions never execute and
every one of them passes.

1. **Assert a POSITIVE signal that the code ran**, not merely the absence of a failure: a call count,
   a success envelope, an observable side effect. Put it in the shared fixture so it protects every
   test, not the one that happened to notice.
2. ⚠ **An HTTP status is not that signal** where the codebase wraps failures in a 200 envelope. Check
   the envelope's own success field.
3. **Scope the guard to the right unit.** A blanket "this was never called" can fail for a reason
   unrelated to the property under test — and, worse, can pass while the defect is live if the
   defect operates by a different route.
4. **Ask what ELSE produces this outcome.** An outcome consistent with your hypothesis is not the
   cause. Was the precondition for failure ever actually met?

---

## P6 — Mutation · *have you SEEN the guard go red?*

**Never cite a gate you have not watched fail.** This applies to guards you wrote *and* guards you
inherited.

1. Break the thing the guard protects. Confirm it goes red, and that it reds **for the stated
   reason** rather than erroring.
2. **Restore from a byte backup taken before the mutation**, then `cmp`. Do not restore with version
   control if the working edit is uncommitted — that discards it.
3. Check the kill lands in the **right scope**. A mutation in module A reddening only module B's
   tests means the two are coupled, or one is inert.
4. ⚠ **On a scripted multi-file edit, read the insert/delete ratio.** For a purely additive change,
   deletions should be zero or exactly the lines you meant to rewrite. A net-negative diff on an
   additive edit is a first-class signal that something was dropped.

---

## Output

Emit a compact table, then the verdict. Do not bury a FAIL in prose.

```
PREFLIGHT — <scope>
P1 requirements diff   PASS    3 named / 3 shipped
P2 consumer census     FAIL    ProfileInvites is read by 2 authz views — delete = permission change
P3 reachability        PASS    routed at /api/x, control /api/y present
P4 census bound        PASS    2 idioms, exit codes read; CODE census, data not checked
P5 non-vacuity         PASS    envelope asserted + 5 size-writes observed
P6 mutation            INVALID probe restored from git, working edit lost — redo from byte backup

VERDICT: NOT READY — 1 FAIL, 1 INVALID
```

**Any FAIL or INVALID ⇒ do not make the claim.** Fix, or state the limitation explicitly in the same
sentence as the claim. An INVALID is not a soft pass — it means you do not know.

**Skipped checks are listed as skipped, with why.** "N/A — no model touched" is a result. Silence is
not.

## Recording

**Always write the session marker — this is what the commit gate reads.** One line per run,
appended:

```bash
printf '%s\t%s\t%s\n' "$(date +%H:%M)" "<VERDICT>" "<scope>" \
  >> "${TMPDIR:-/tmp}/aria-preflight-${CLAUDE_SESSION_ID}"
```

`pre-commit-preflight-check.sh` fires on `git commit` and warns when no marker exists for the
session. **Any recorded verdict satisfies it, including NOT READY** — recording a FAIL and
committing anyway is a legitimate, visible choice; the failure being guarded against is not running
the checks at all. Escalation to deny is opt-in via `preflight_gate` + `preflight_deny_paths`.

Then write the table to `<knowledge_folder>/logs/preflight/<date>-<scope>.md` when the change is
non-trivial, and run aria's standard intake. A preflight that found something is a candidate
insight — the pattern that produced the FAIL is usually more reusable than the fix.

## Composes with

- **`superpowers:verification-before-completion`** — owns the Iron Law. Run it; this adds the *what*.
- **`/prospect`** — same discipline, earlier: before the work rather than before the claim.
- **`/retrospect`** — after shipping. A FAIL here that you shipped anyway belongs there.
- **Rule 22 / Rule 38** — per-edit scope, and closing the class rather than the instance.

> **Why a skill and not a rule.** Every check here descends from a rule someone already knew. The
> failures happened anyway — including one where a defective probe was run within an hour of reading
> the note warning against it. Reading a rule does not execute it. **Run the checks.**
