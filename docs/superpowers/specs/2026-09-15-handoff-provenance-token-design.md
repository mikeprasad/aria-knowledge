# The handoff provenance token — design

⛔ **SUPERSEDED 2026-09-15 by `2026-09-15-handoff-resume-and-provenance-token-merged-design.md`** — its own `/prospect` found that D-B overlapped the
ratified-but-unbuilt `/handoff resume` design; Mike ruled "Merge into one spec". **Do not execute from
this file.** Its measurements, D-A/D-C and the two-arm fixture are carried forward with provenance.

**Status:** DRAFT, pre-`/prospect`. Authored 2026-09-15.
**Decision owner:** Mike. **Requested:** "the handoff should have a unique ID or wording so the new
session knows it's a copy/pasted handoff" + "at session start, the first user input should be checked
to see if it matches an existing handoff prompt from that project's SESSION.md".
**Runtime:** authored against `plugin-claude-code`. Source and installed are byte-identical on all
four files this touches (measured 2026-09-15, `cmp`, with a positive control), so every measurement
below holds against source.

---

## 0. Summary

A handoff prompt that the operator **copies out of `/handoff` and pastes into the next session** is
invisible to the ledger. It is never marked consumed, never removed, and the session that picks it up
**silently takes over its identity**. Measured, not inferred (§1.1).

Separately, a session that replaces the active prompt body **without rewriting the front-matter**
leaves the file asserting one session's identity over another session's work — and the *next*
`/handoff`, behaving exactly as its skill instructs, stamps that wrong identity onto the body
permanently (§1.2). This happened on 2026-09-14 and cost a real handoff its attribution.

Both paths have one cause: **the active prompt's only attribution channel is the front-matter, and
the front-matter is rewritten by machinery that does not touch the body.**

This spec adds a **provenance token** — one visible, plain-ASCII, data-shaped line carried *inside*
the opener fence, naming the project, the authoring session and its timestamp. Because Step 3e's
opener is authored once and reused verbatim in both the pasteable artifact and the `SESSION.md`
prompt block (`skills/handoff/SKILL.md:211`), the token lands in both. That makes it **self-locating**:
the receiving session finds the prompt by searching for the token itself, rather than matching text or
trusting a header.

Three decisions: **D-A** the token, **D-B** token-keyed resume and consumption, **D-C** a structural
check that fails when the active body's token disagrees with the front-matter.

---

## 1. The defect

### 1.1 The copy-paste path — measured, two arms

Fixture: a `SESSION.md` in `lastEvent: handoff` with `sessionId: AAAA`, a non-empty
`## Next session prompt`, and session `BBBB` making its first edit. The sequence simulated is
`post-edit-check.sh:97-107` exactly — the **only** code path in the plugin that marks a ledger entry
consumed (`kt_ss_ledger_mark_consumed` has exactly one caller; censused).

| arm | fixture | prompt after | consumed marker | front-matter after |
|---|---|---|---|---|
| 1 | active prompt, **no `### AAAA` entry** (the real copy-paste case) | **survives** | **none** | `in-progress`, `sessionId: BBBB` |
| 2 | same **plus** a `### AAAA` entry in Pending (**positive control**) | survives | **entry marked consumed** | `in-progress`, `sessionId: BBBB` |

Arm 2 proves the helper works and the harness is live. Arm 1 is the defect, and the mechanism is
structural, not a bug: **`kt_ss_ledger_mark_consumed` keys on `^### .*<sid>`, and the active prompt
has no `### ` header by construction.** The consume call fires and matches nothing.

The third column is the part nobody asked about and the part that does the damage: `kt_ss_mark_inprogress`
rewrites the front-matter keys and passes the body through, so **the prompt is re-attributed to whoever
picked it up.** The 2026-09-11 spec calls this state a "HOOK ARTIFACT" and rules the true author
"not recoverable from the file". Under the current format that is correct. §2 is why it stops being
correct.

⚠ **The existing resume trigger is not the problem, and fixing it would not help.** The SessionStart
directive keys on *"the user's opening message included the word `handoff`"*. Measured across all 152
stored prompts in the 8 tracked ledgers, **129 (85%) contain that word** — usually incidentally, as
prose like *"from the 2026-09-14 handoff"*. So it mostly fires, by luck. But whether it fires or not,
**consumption of an active prompt is 0%**, because there is nothing keyed to mark. A better trigger on
the current format buys nothing.
⚠ *Bound:* that 85% measures the word in the **stored prompt** as a proxy for the **pasted opening
message**. Identical when the whole fence is pasted; divergent under a partial paste or an added
preamble.

### 1.2 The stale-front-matter path — the 2026-09-14 incident

`bc3579b` (a `/handoff snap`) resumed the P4 T4.2b work and:

1. moved that handoff's body from `## Pending handoffs` into the active slot;
2. **deleted its `### 5214cae2-… · 2026-09-13T19:15:00Z · unconsumed` entry**, its own commit message
   calling it *"my earlier duplicate"* — it belonged to a different session;
3. **left the front-matter untouched** (`sessionId: 374e75de`, a serialization `currentFocus`) over a
   T4.2b body.

Fourteen minutes later `13ad7ba` ran `/handoff` **correctly**, demoted the incumbent by "reading the
prior file's values first" exactly as `SKILL.md:216` instructs, and stamped 5214cae2's body with
374e75de's sid, `at`, `focus` and `next`. The file lied to it.

Net: 374e75de's handoff ended with its **metadata on one entry** and its **body on another**; 5214cae2's
identity was gone. Repaired 2026-09-15 (`proj-a` `cc2f66c`), every value recovered verbatim from
`bc3579b~1`.

⛔ **The skill's existing guard cannot catch this.** It fires when the value to be passed *equals this
session's own id* while the body is not one it wrote. Here the stale sid belonged to a **third**
session, so the condition was false and the guard stayed silent. Correct code, wrong predicate.

### 1.3 Frequency — measured, and it argues for a cheap check

Across all 8 tracked `SESSION.md` (315 commits that changed an active prompt body):

- **32** changed the body while leaving `sessionId` + `at` unchanged (10%);
- of those, **28 are corrections** — a session editing its *own* opener, where leaving the identity
  alone is **correct**;
- **4 are substitutions** — different work swapped in, identity stale (**1.3%**): `bc3579b` and
  `00aa051` (proj-a), `a6282f0` and `5aa761c` (root). Body similarity 0.07–0.14.

Separately, **6 unconsumed entry keys genuinely vanished** across the last 80 `proj-a/SESSION.md` commits.

⚠ **Instrument note, because the first cut of both numbers was wrong.** A naive `grep -c '^-### .*unconsumed'`
counts an `unconsumed → consumed` re-marking as a deletion; it reported 17 vanishes where a set
difference on `sid|ts` reports 6, and it inflated the stale count by including same-session
corrections. Both figures above are the corrected ones.

⇒ **1.3% does not justify a new promote/demote helper.** It justifies a check that cannot be forgotten.

### 1.4 Why nothing caught either path

`tools/check-session-ledger.py`'s unconsumed-loss detector (`check_unconsumed_loss`) is keyed on the
**entry key**. A promotion deletes the key and preserves the body; a destruction deletes both. **To
that instrument the two are identical** — it correctly reported the 2026-09-14 promotion as a loss, and
would equally have missed a promotion that *did* lose the body. The detector is not wrong; it has no
instrument for the active slot, because the active slot has no key.

---

## 2. What this supersedes, and why the premise changed

The 2026-09-11 design (`2026-09-11-demote-gate-sessionid-conjunct-design.md`) §5 lists as explicitly
out of scope:

> **Recovering the true author** of a hook-stamped entry. Unrecoverable from the file; D-B annotates
> the uncertainty rather than pretending to resolve it.

That is a **scope exclusion for that spec**, not a prohibition — and its embedded factual claim is true
**of the current format only**. The author is unrecoverable because nothing in the file carries the
author except the front-matter, which `post-edit-check.sh` overwrites.

**D-A changes that premise.** The token lives in the prompt **body**, which `kt_ss_mark_inprogress`
passes through untouched (bare `{ print }`) and which `13ad7ba`-shaped demotes copy verbatim. After
D-A the author *is* recoverable from the file, so §5's annotation-instead-of-resolution ruling is
retired for tokened prompts and **retained unchanged for tokenless ones** (§7).

§5 also excludes "any helper change", on the grounds that `lib-session-state.sh` "is already correct on
this axis and must not be edited to match a skill that was wrong". D-B **does** require a helper change.
That exclusion was about not corrupting a correct helper to match a wrong clause; D-B adds a capability
that does not exist in any form (`kt_ss_ledger_promote` is absent — censused, negative control). It
does not alter existing helper semantics.

⇒ **This must be an explicit, argued supersession in the plan, not an assumption.** `/prospect` should
attack it first.

---

## 3. D-A — the provenance token

One line, first line **inside** the Step 3e opener fence:

```
aria-handoff: proj-a/5214cae2-71ab-42b8-8d5e-f31cacadec31@2026-09-13T19:15:00Z
```

**Shape:** `aria-handoff: <project>/<sessionId>@<at>` where `<project>` is the `projects_list` slug and
`<sessionId>`/`<at>` are the same values Step 3f would pass to `kt_ss_ledger_add`.

**Why these properties:**

- **Inside the fence** — `SKILL.md:328` already rules that a line which must survive the paste goes
  inside the fence, because anything after the closing fence "is silently dropped on paste". Same
  reasoning, same placement. **First** line so a head-truncated paste still carries it.
- **Visible, plain ASCII, `key: value`** — Mike's ruling (C). Matches the front-matter idiom already in
  the file. Greppable by eye and by tooling. An HTML comment was considered and rejected: tidier, but
  easier to lose in a partial copy, and invisible to the operator who is the one person able to notice
  it is wrong.
- **Data-shaped, never imperative** — it must not read as an instruction to the receiving session.
  `key: value` cannot.
- **Collides with no existing matcher** — it matches neither `^### ` (`is_entry_header`, `ENTRY_RE`,
  `kt_ss_ledger_mark_consumed`), nor `^## ` (the heading-scoped readers), nor `<!-- aria:entry-end -->`
  (the helper boundary). **Not a ledger format change**; no consumer census owed. To be re-verified as
  AC5.
- **Carries the project** — so a paste into the *wrong* project is detectable. This is a real failure
  mode with no current detection.

**Existing openers keep their `proj-a`-slug first line**; the token is additive, on the line above.

---

## 4. D-B — token-keyed resume and consumption

The SessionStart directive gains a token branch **above** the existing word-`handoff` branch:

If the opening message contains `aria-handoff: <proj>/<sid>@<at>`:

1. **Locate by the token itself**, not by sid — search that project's `SESSION.md` for the literal
   token string. It resolves whether the prompt is still in the active slot or has since been demoted
   into a `### ` entry by another session. *(That relocation is not hypothetical: `13ad7ba` demoted a
   prompt 14 minutes after it was written.)*
2. **Found in a `### ` entry** → mark **that entry** consumed.
   ⛔ **Not via `kt_ss_ledger_mark_consumed` as it stands.** Measured: its awk matches `^### .*sid`, a
   **substring test that ignores the timestamp**, and `proj-a/SESSION.md` currently holds
   `374e75de…` under **two** different `at` values. Marking by sid would close both. D-B needs a
   key-exact variant, or the existing helper gains an optional `at` conjunct.
   ⚠ **Corrected at `/prospect` (2026-09-15):** an earlier draft called this "a new finding, not
   previously recorded". That is wrong. `logs/prospect/2026-08-25-file-handoff-resume-mode.md` already
   recorded that the sid "is interpolated into an awk regex unescaped, working on today's legacy sid by
   luck." Different axis — escaping, not timestamp-blindness — but **the same matcher**. Rule 38: the
   helper change closes **both** defects, or it leaves the class open.
3. **Found in the active slot** → demote it to a `### ` entry marked consumed, creating the ledger
   record that is missing today (§1.1 arm 1).
4. **Not found** → say so plainly. The prompt was pasted from another project, edited past recognition,
   or already pruned. **Do not fabricate an entry.**
5. **Found but already terminal** → ⛔ **refuse to proceed silently; surface it.** This is the guard for
   the concrete hazard this arc began with: the T4.2b prompt sat `unconsumed` while its work was
   shipped and irreversible (`space/0263` on `origin/master` with seven migrations above it), so a
   session taking the pickup would have re-applied an applied `RemoveField`.

**Fallback is retained, not replaced.** 152 stored prompts carry no token; for them behaviour is
byte-identical to today.

---

## 5. D-C — the structural check

`tools/check-session-ledger.py` gains: when the active `## Next session prompt` carries a token whose
`<sid>`/`<at>` disagree with the front-matter `sessionId`/`at`, report it.

This is the `bc3579b` detector, and it is deterministic — both values are explicit in the file, so it
has no false-positive mode of the "plausible rule" kind §5 of the prior spec warns about. It fires only
on §1.3's 4-in-315 shape, never on the 28 corrections (a correcting session's own token still matches
its own front-matter).

Severity **WARN**, baseline-and-ratchet via `tools/session-ledger-baseline.txt`, consistent with every
other check in that tool. It is read-only, like the rest of the checker — ⛔ it must never repair.

---

## 6. Scope

**Clause/code sites** (`plugin-claude-code`, canonical):

| # | File | Change |
|---|---|---|
| 1 | `skills/handoff/SKILL.md` §3e | emit the token as the opener's first in-fence line |
| 2 | `skills/handoff/SKILL.md` §3f/:216 | pass the token's values to `kt_ss_ledger_add`; prefer the token over front-matter when they disagree |
| 3 | `bin/session-start-check.sh` | the token branch of the SESSION STATE directive (D-B) |
| 4 | `bin/lib-session-state.sh` | key-exact consume (D-B step 2); active-slot demote-as-consumed (step 3) |
| 5 | `bin/post-edit-check.sh` | consult the token before treating front-matter `sessionId` as prior attribution |
| 6 | `tools/check-session-ledger.py` + baseline | D-C |

**Ports** (censused 2026-09-15, excluding `dist/`):

| surface | ports carrying it |
|---|---|
| `lib-session-state.sh` | antigravity, claude-code, cursor-template, openai-codex (**4**) |
| `post-edit-check.sh` | antigravity, claude-code, cursor-template, openai-codex (**4**) |
| `skills/handoff/SKILL.md` | antigravity, claude-code, claude-cowork, openai-codex (**4**) + `tests/` |
| `session-start-check.sh` | claude-code, cursor-template, openai-codex (**3** — ⚠ antigravity has none) |

**Parity ruling inherited from the prior spec's OQ1:** land `claude-code` first, then close the ports in
**one deliberate parity unit** — a partial parity pass is worse than a tracked gap (U16). The
antigravity asymmetry means D-B has **no host** there and needs its own answer (§9 OQ2).

⚠ The prior arc's measured failure mode applies directly: the bad `/wrapup` clause reached six files and
**only `claude-code` was fixed**. Any port claim here must be `cmp`-verified, never assumed.

---

## 7. Explicitly NOT in this spec

- **A `kt_ss_ledger_promote` helper.** 1.3% incidence (§1.3) does not earn one; D-C catches the same
  class for the cost of a comparison.
- **Retro-fitting tokens onto the 152 existing stored prompts.** They keep today's behaviour exactly.
- **Recovering the true author of a *tokenless* hook-stamped entry.** Still unrecoverable; the prior
  spec's §3 annotation convention stands unchanged for those.
- **The terminator gap.** `proj-a/SESSION.md` measures 128 entries against 124 `<!-- aria:entry-end -->`
  (gap 4). Pre-existing, separate class, tracked elsewhere.
- **The `## Archived — superseded …` heading-spelling warnings.** Separate.
- **Any repair capability in the checker.** It reports; it never writes.

---

## 8. Acceptance criteria

Each must be able to go **red for the right reason**; a mutation test is owed per AC.

- **AC1** `/handoff` emits the token as the first line inside the opener fence, and the identical token
  appears in the `SESSION.md` prompt block. *Red if:* the two differ, or the token lands outside the fence.
- **AC2** Re-run §1.1's two-arm fixture with a tokened prompt. Arm 1 now yields a **consumed ledger
  entry** for the active prompt. Arm 2 unchanged. *Red if:* arm 1 still yields no marker.
- **AC3** A token whose entry is already terminal causes the session to **surface and stop**, not resume.
  Driven by a fixture carrying a `consumed` entry.
- **AC4** Key-exact consume: a fixture with the **same sid under two different `at` values** marks
  exactly one. *Red if:* both are marked — which today's `kt_ss_ledger_mark_consumed` would do.
- **AC5** Token-line safety: a tokened prompt leaves `^### ` counts, terminator counts and
  `check-session-ledger.py`'s verdict unchanged vs. the same prompt untokened. *Red if:* any matcher
  reacts to the token.
- **AC6** D-C fires on a reconstruction of `bc3579b` (token sid ≠ front-matter sid) and stays silent on
  a reconstruction of one of the 28 corrections. **Both arms required** — silent-on-corrections is the
  half that makes it usable.
- **AC7** Tokenless regression: the 152 existing prompts and the word-`handoff` fallback behave
  byte-identically to today.
- **AC8** Port parity: every port claim in §6 `cmp`-verified, with the antigravity gap explicitly
  dispositioned rather than silently skipped.

---

## 9. Open questions

- **OQ1 — token in the fence vs. the operator's paste discipline.** The token is only as good as the
  paste. If Mike habitually copies the fence *contents*, first-line placement is safe. If he sometimes
  copies from the `## Next session prompt` block in the file instead, it is equally safe (same bytes).
  **Is there a path by which he obtains an opener that never passed through the fence?** If yes, D-B's
  "not found" branch (§4.4) is load-bearing rather than defensive. **Ask Mike; do not infer.**
- **OQ2 — antigravity has no `session-start-check.sh`.** D-B has no host there. Options: skip D-B for
  that port and ship D-A only (the token still repairs attribution via §3f, just without auto-consume);
  or find its equivalent surface. **Recommendation: D-A everywhere, D-B where a session-start surface
  exists, and state the asymmetry in the parity unit rather than leaving it implicit.**
- **OQ4 — ⛔ D-B overlaps a ratified, unbuilt design. Surfaced by this spec's own `/prospect`; it
  falsified the assumption that no surface owns resume.** `docs/superpowers/specs/2026-08-25-handoff-resume-mode-design.md`
  specs a `/handoff resume` mode — load the SESSION.md resume prompt, handle >1 unconsumed, and its S7
  is literally *"Execute selection; mark consumed via `kt_ss_ledger_mark_consumed`"*. It was prospected
  `PROCEED-WITH-CHANGES` on 2026-08-25 and **never shipped** (the skill's `argument-hint` is
  `"[auto|brief|snap]"` — no `resume`). Building D-B alongside it creates **two owners of one surface**.
  ⇒ **D-B (§4, steps S3/S5/S6) is DEFERRED pending a decision: revive 2026-08-25 as-is, supersede it
  with D-B, or merge both into one spec.** D-A and D-C are unaffected and proceed.
- **OQ3 — release.** Prior spec's OQ2 chose a dedicated patch release for a live data-loss path in an
  always-loaded skill. The copy-paste path is **attribution loss, not content loss** (§1.1 — the body
  always survives), which is less severe. Ride the next release, or its own? **Recommendation: ride the
  next release**, since nothing here is losing work today.
