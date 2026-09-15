# `/handoff resume` + the provenance token — merged design

**Status:** ✅ **GATED 2026-09-15 — `/prospect` verdict PROCEED-WITH-CHANGES; changes applied below
in the same edit that records them.** Gate log:
`knowledge/logs/prospect/2026-09-15-file-handoff-resume-and-provenance-token-merged.md`.
⭐ The gate's load-bearing change is an **execution-order** one, recorded at §9 OQ3: **D10 ships
first and alone.** Authored 2026-09-15.
**Supersedes two specs, by Mike's ruling 2026-09-15 ("Merge into one spec"):**
- `2026-08-25-handoff-resume-mode-design.md` — GATED 2026-08-25, `PROCEED-WITH-CHANGES`, **never built**.
- `2026-09-15-handoff-provenance-token-design.md` — GATED 2026-09-15, `PROCEED-WITH-CHANGES`, whose own
  gate surfaced the overlap that produced this merge.

Both predecessors carry a SUPERSEDED banner pointing here. Their gate logs remain valid evidence:
`knowledge/logs/prospect/2026-08-25-file-handoff-resume-mode.md` and
`knowledge/logs/prospect/2026-09-15-file-handoff-provenance-token.md`.

**Repo:** `aria-knowledge`. **Runtime:** authored against `plugin-claude-code` (canonical).
Source↔installed verified byte-identical on all touched files (`cmp`, positive control, 2026-09-15).

---

## 0. Why one spec — the merge is load-bearing, not tidiness

⭐ **Each predecessor fixes a hole the other cannot see.**

2026-08-25 **D3** rules that `/handoff resume` sources the active prompt **and** pending entries as
**one candidate set**. Its **AC8** then says marking consumed reuses `kt_ss_ledger_mark_consumed` and
"introduces no new write path".

⛔ **Those two cannot both hold.** That helper matches `^### .*<sid>`, and the **active prompt has no
`### ` header by construction**. So when the user picks the *active* candidate — the most common case,
present in 5 of 6 measured projects — AC8's mechanism silently marks nothing. Measured 2026-09-15 in a
two-arm fixture: with no `### ` entry the consume call fires and matches nothing; with one present it
marks correctly. **The older spec has a latent hole exactly at its own most common path.**

The token closes it by giving the active prompt a durable identity. Conversely, 2026-08-25 supplies
what the token spec lacked: a **command surface** reachable mid-session (G1), **staleness gating**
(D1), a **multi-candidate picker** (D2/D3), and a measured **parser** for four ledger format axes (§4)
that the token spec never enumerated.

---

## 1. The problem — four measured paths

### 1.1 Multi-candidate is the norm (carried from 2026-08-25 §1)

Across the workspace 2026-08-25: 5 of 6 projects holding pending entries had **≥2 candidates**. The
capability was already hand-invented — one live active prompt read *"read BOTH pending handoffs below,
then pick one."*

### 1.2 A copy-pasted handoff is invisible to the ledger (from 2026-09-15 §1.1)

Measured, two arms, simulating `post-edit-check.sh:97-107` — the **only** caller of
`kt_ss_ledger_mark_consumed`:

| arm | fixture | prompt after | consumed marker | front-matter after |
|---|---|---|---|---|
| 1 | active prompt, no `### ` entry (**the real case**) | survives | **none** | `in-progress`, sid → picker's |
| 2 | plus a `### ` entry (**positive control**) | survives | **marked** | `in-progress`, sid → picker's |

The third column is the damage nobody asked about: `kt_ss_mark_inprogress` rewrites the front-matter
and passes the body through, so **the prompt is re-attributed to whoever picked it up.**

### 1.3 A stale front-matter propagates a wrong identity (from 2026-09-15 §1.2)

`bc3579b` swapped the active body without rewriting the front-matter. Fourteen minutes later
`13ad7ba` ran `/handoff` **correctly** — demoting by "reading the prior file's values first", exactly
as the clause instructs — and stamped the wrong identity on permanently. Repaired at `cs cc2f66c`.
Incidence measured across 8 tracked ledgers: **4 substitutions in 315 body-changing commits (1.3%)**;
28 further stale-identity commits are legitimate same-session corrections.

### 1.4 Three structural gaps (carried from 2026-08-25 §3)

- **G1** — no command surface. Resume is reachable only at session start, once, only if the hook fires.
- **G2** — staleness is checked on the *active* prompt only; pending entries are offered with none.
- **G3** — a pending entry with **no active sibling** surfaces nothing (the clause is an `ALSO:` hanging
  off an active-prompt precondition).

---

## 2. What already exists — this composes

- `bin/session-start-check.sh` emits the SESSION STATE directive: locate `SESSION.md`; auto-resume
  without confirmation when the opening message contains "handoff"; else state `lastEvent` + age and
  ask y/n; apply `session_stale_days` (default 7).
  ✅ **CORRECTED 2026-09-15 — 2026-08-25 §7's "byte-identical in two shipped files" risk is RESOLVED.**
  Re-measured with a positive control: `session-start-rules.sh` now contains **zero** session-state
  text (loose patterns: `SESSION STATE|Next session prompt|Pending handoffs|session_stale_days` → 0,
  control → 1). The directive lives in **one** file. Do not carry the two-file scope forward.
- `kt_ss_ledger_add` stores **full fidelity** — `focus`, `next`, and the complete multi-line prompt.
  ⇒ the picker's rows need **no LLM synthesis**, and `at:` is per-entry so staleness is mechanical.
- `skills/handoff/SKILL.md:211` — the 3e opener is **authored once and reused verbatim** in both the
  pasteable artifact and the `SESSION.md` prompt block. **This single-source property is what makes a
  token self-locating.**
- `SKILL.md:328` — paste-critical lines must sit **inside** the opener fence; anything after the
  closing fence "is silently dropped on paste". Direct precedent for the token's placement.

---

## 3. Decisions

### D1 — staleness shown at summarization **and** gated at selection *(carried, unchanged)*

62% of the pending corpus measured stale (5 of 8, two by ~2 months). Every row carries a freshness
verdict; picking a stale row requires a confirm offering `[resume / keep]`.
⛔ **`archive` stays SPLIT OUT** — no `kt_ss_ledger_archive` exists; it is new write machinery and its
own unit. Do not smuggle it in.

### D2 — combine is recommended only on same-root + disjoint `next:` *(carried, unchanged)*

Offered as an extra numbered option, never auto-selected; its absence is not an error.

### D3 — active prompt + pending entries are ONE candidate set *(carried, EXTENDED)*

Closes G3 by construction. **Extended here:** the active candidate is no longer unmarkable, because D4
gives it an identity — see §0.

### D4 — the provenance token *(new; was 2026-09-15 D-A)*

One line, **first line inside** the 3e opener fence:

```
aria-handoff: cs/5214cae2-71ab-42b8-8d5e-f31cacadec31@2026-09-13T19:15:00Z
```

Shape `aria-handoff: <project>/<sessionId>@<at>`. Visible, plain ASCII, `key: value` — Mike's ruling
(2026-09-15, "visible"). An HTML comment was considered and rejected: tidier, but easier to lose in a
partial copy and invisible to the one person able to notice it is wrong.

It matches **no** existing matcher — not `^### ` (`is_entry_header`, `ENTRY_RE`,
`kt_ss_ledger_mark_consumed`), not `^## ` (the heading-scoped readers), not `<!-- aria:entry-end -->`.
**Not a ledger format change**; verified as AC9. Carrying the project makes a paste into the *wrong*
project detectable — a failure mode with no current detection.

### D5 — token-keyed resume, folded into the `/handoff resume` flow *(new; was 2026-09-15 D-B)*

The token is a **fast path into D3's candidate set**, not a second surface:

1. **Locate by the token string itself** — not by sid, not by parsing. It resolves whether the prompt
   is still active or has since been demoted. *(Not hypothetical: `13ad7ba` demoted a prompt 14
   minutes after it was written.)*
2. **Found, single candidate** → resume it and mark it consumed.
3. **Found in the active slot** → D3 already admits it as a candidate; marking it consumed requires
   the key-exact helper of D6, since it has no `### ` header today.
4. **Not found** → say so plainly. Pasted from another project, edited past recognition, or pruned.
   ⛔ **Do not fabricate an entry.**
5. **Found but already terminal** → ⛔ **surface and stop.** This is the guard for the concrete hazard
   that produced this arc: a T4.2b prompt sat `unconsumed` while its work was shipped and irreversible
   (`space/0263` on `origin/master`, seven migrations above it), so a session taking the pickup would
   have re-applied an applied `RemoveField`.

**Fallback retained, not replaced.** 152 stored prompts carry no token; for them, behaviour is
byte-identical to today, and D1–D3's picker is the path.

### D6 — one helper change closing **both** sid defects *(merged)*

`kt_ss_ledger_mark_consumed` has two independent defects on the same matcher, found by two different
gates. **Rule 38 — close the class, not the instance:**

- **Unescaped interpolation** *(2026-08-25 AC8)* — the sid goes into an awk regex unescaped. aria's
  live legacy sid `e95b0202 (contract-coherence)` matches **by luck**; a sid containing `[`, `*` or `.`
  would mis-match or over-match silently.
- **Timestamp-blindness** *(2026-09-15, measured)* — the match is `^### .*<sid>`, ignoring `at`.
  `cs/SESSION.md` holds `374e75de…` under **two** different `at` values, so a sid-keyed mark closes
  both entries.

⇒ extract the sid as the text before the first ` · `, match it **literally**, and add an `at` conjunct.

### D7 — ⭐ the operator's own words outrank the stored prompt *(new — from Mike's 2026-09-15 ruling)*

Mike copies the whole fenced block **"but sometimes adds a sentence preceding it."** Two requirements
follow, and both would have been missed:

- **R1 — scan the whole opening message for the token, never just the first line.** A preamble pushes
  the token down.
- **R2 — ⛔ any operator text accompanying the pasted block is an INSTRUCTION and takes precedence over
  the stored prompt.** The current directive says *"execute that prompt directly (no confirmation)"* —
  which would drive straight past *"before you start, see the parallel session's work"*. That sentence
  shape is a **mandatory pre-execution state-verify gate** (user rule U14), and auto-resume must not
  trample it. ⇒ when the opening message carries text beyond the pasted block, **surface that text and
  reconcile it against the prompt before executing**, rather than resuming silently.

### D8 — the structural check *(new; was 2026-09-15 D-C)*

`tools/check-session-ledger.py` reports when the active prompt's token `sid`/`at` disagree with the
front-matter `sessionId`/`at`. Deterministic — both operands are explicit — and it cannot fire on the
28 corrections, because a correcting session's own token matches its own front-matter. Severity WARN,
baseline-and-ratchet. ⛔ Read-only, like every sibling check; it must never repair.

### D9 — the demote/promote path writes a receipt *(prior art — diagnosed 2026-09-14, unbuilt)*

⛔ **Not novel to this spec, and the source is an always-loaded file.** `aria-knowledge/CLAUDE.md`'s
2026-09-15 footer already records it, **naming this arc's exact entry**:

> *"a **demoted** entry also vanishes from the `(sid|ts)` key while its content is explicitly
> preserved, so the guard still reports it as a loss — the third false-positive shape in this class,
> and the fix shape already exists (the demote path should write a receipt as prune now does).
> Measured live on `cs/SESSION.md` entry `5214cae2`."*

Verified 2026-09-15: `kt_ss_ledger_add` contains **0** receipt writes against `kt_ss_ledger_prune`'s
14. The fix shape is real and unbuilt.

⛔⛔ **KILLED AS SPECIFIED, 2026-09-15, on measurement — and implementing it literally would have
been ACTIVELY HARMFUL. Do not restore it.**

The recorded fix shape was *"the demote path should write a receipt as prune now does."* Measured
against a fixture: **`kt_ss_ledger_add` is purely additive** — entry keys went 1 → 2, the
pre-existing key survived untouched, and no receipt was written (correctly, because nothing was
removed).

⇒ A receipt emitted from `kt_ss_ledger_add` would name a key that **SURVIVED**. `kt_ss_ledger_prune`'s
own contract comment states the consequence in terms this spec cannot improve on:

> *"A receipt naming an entry that SURVIVED would later suppress a genuine loss report for it. The
> difference between the sets is exactly where that bug would live."*

So the literal fix does not merely fail to help — it **blinds the detector to a future real
destruction** of that entry. That is the inverse of the defect it was meant to close.

**Where the obligation actually belongs.** A receipt is owed by whatever operation **removes a key
while preserving the content**. Today no helper does that: the 2026-09-14 incident was a hand-edit
(`bc3579b`), and the promote half of the cycle has no helper at all — which is precisely the gap
**D5 step 3** fills. ⇒ **the receipt moves to the active-slot promote path in Unit C**, computed the
way prune computes its own: before-minus-after, appended only after the write commits, and
**outside** the awk whose stdout is the new file.

⭐ **And D4 substantially dissolves the symptom without any receipt.** The key vanished because the
promote removed it and the later demote re-created it under a *different* identity read from stale
front-matter. With the token, the demote restores the **original** sid + `at`, so the key reappears
rather than being replaced. A receipt would only ever have been needed for the window between the
two — which is Unit C's concern, not `kt_ss_ledger_add`'s.

⚠ **This is a different problem from D8 and neither substitutes for the other.** D9 removes a **false
positive** (a legitimate relocation reported as destruction — the FAIL that opened this arc). D8
catches a **real defect** (a body whose identity disagrees with its front-matter). Shipping only D9
would silence the alarm while leaving the mis-attribution it was pointing at.

⚑ **Method note worth carrying:** this was missed by a U10 "has it been done" census that searched
`docs/`, `intake/` and `logs/prospect/` — but live status lives in the **always-loaded CLAUDE.md
footers**, which no pass searched. A prior-art census must include them.

### D10 — `at`-ordering guard: an older session SELF-DEMOTES instead of skipping or clobbering

⛔ **Reported by Mike 2026-09-15 as "a common issue on both `/wrapup` and `/handoff`."** A session
reaching Step 6.5 finds the active slot owned by a *newer, still-live* session and faces what looks
like a two-way choice: **clobber** newer state with its own older state, or **skip** the write and
lose its own record entirely. Sessions have been choosing skip, correctly but lossily.

⭐ **There is a third move and nobody wrote it down: self-demote.** Write your own prompt into
`## Pending handoffs` and leave the newer active slot untouched. Neither side loses anything.

**The mechanism, measured — and the field reported reason for skipping is WRONG in a way that
matters.** A live report read *"a `/wrapup` adds no pending entry, so writing mine would only replace
newer state."* `/wrapup` Step 6.5 **does** demote someone else's pickup — its "adds NO pending entry"
clause is scoped to the **wrapped session's own** state, since a clean close has no next-session
prompt to retain. So the incumbent's **prompt** survives.

⇒ **The damage is not to the prompt; it is to the FRONT-MATTER.** Step 6.5's step 3 is a *full
rewrite*, which replaces `lastEvent`, `at`, `currentFocus` and `nextAction` wholesale. Demote is
**prompt-shaped protection against state-shaped damage** — which is exactly what the skill's own
warning already says: *"unconsumed handoffs survive at full fidelity … is TRUE of entries inside
`## Pending handoffs` and **FALSE of a handoff sitting in the active** slot."*

⛔ **Nothing orders the writers.** Measured 2026-09-15: `bin/lib-session-state.sh` contains **0**
comparisons of the incumbent's `at`. The front-matter is a single-valued, last-writer-wins record of
"where this project stands", written by N concurrent sessions with no ordering check at all.

**The rule:** before the full rewrite, compare the incumbent's front-matter `at` with your own.

- incumbent **older or absent** → rewrite as today (demote its prompt first, unchanged).
- incumbent **newer** → ⛔ **do not regress it.** Write your prompt as a `## Pending handoffs` entry,
  leave the active front-matter alone, and **say so in the closing report** — naming the owning
  session and both timestamps.

✅ Viable: measured **8 of 8** tracked ledgers carry a front-matter `at:` in ISO-8601 `Z`, which
compares correctly as a plain string — no date parsing, no locale dependence.

⚠ **Stated bound, because `at` is not what it looks like.** `kt_ss_mark_inprogress` rewrites the
front-matter on a session's first edit, so `at` tracks **last touch**, not last meaningful state — a
session that merely edited one file outranks a session holding a real handoff. That failure is
**benign under this rule and only under this rule**: the handoff still lands in Pending rather than
being dropped. It would NOT be benign under a "newest wins, older skips" rule, which is why
self-demote is the resolution rather than a refusal.

⚠ Applies to **both** skills. `/handoff` has the same shape: its demote protects the incumbent's
prompt and its rewrite still regresses the incumbent's state.

---

## 4. The parser — and what the token sidesteps *(carried from 2026-08-25 §5)*

Four independent format axes; a naive parser silently drops candidates:

1. **Two headings** — `## Pending handoffs` (current) and `## Prior sessions` (legacy, still live).
2. **Two terminators** — `<!-- aria:entry-end -->`, and *nothing* on legacy entries. **Measured: 3 of
   8 unconsumed entries (37.5%) are invisible to a terminator-based parser, with no error.** Fall back
   to "next `### ` or next `## `".
3. **Two prompt serializations** — `- prompt: |` + indented YAML block scalar (legacy); `- prompt:` +
   raw unindented lines (current).
4. **Three-plus header state forms** — `· handoff · unconsumed`, `· consumed <ts> by <sid>`,
   `· in-progress (demoted, UNFINISHED) · unconsumed`.

⭐ **What the merge buys: the token reduces the parser's blast radius.** D5's literal string search
resolves a pasted candidate regardless of heading spelling, terminator presence or serialization — so
the parser is load-bearing only for the **multi-candidate picker**, not for every resume. It does not
remove the parser requirement; it removes the parser from the paste path.

⛔ **Acceptance still needs the negative control** — a parser that finds 5 of 8 looks exactly like a
`SESSION.md` with 5 entries.

---

## 5. Scope

| # | File | Change | From |
|---|---|---|---|
| 1 | `skills/handoff/SKILL.md` §3e | emit the token as the opener's first in-fence line | D4 |
| 2 | `skills/handoff/SKILL.md` §3f/:216 | prefer the token's identity over front-matter on disagreement | D4 |
| 3 | `skills/handoff/SKILL.md` Step 0 + `argument-hint` | declare `resume` mode; update the mode-list string | 08-25 AC1 |
| 4 | `skills/handoff/SKILL.md` (new step) | the picker: candidate set, freshness, combine, selection | D1/D2/D3 |
| 5 | `bin/session-start-check.sh` | token branch + D7's precedence rule in the SESSION STATE directive | D5/D7 |
| 6 | `bin/lib-session-state.sh` | key-exact + literal-match consume; active-slot marking | D6 |
| 7 | `tools/check-session-ledger.py` + baseline | the structural check | D8 |
| 8 | `bin/lib-session-state.sh` | receipt on demote/relocate; `at`-comparison helper | D9/D10 |
| 9 | `skills/wrapup/SKILL.md` + `skills/handoff/SKILL.md` Step 6.5 / 3f | the `at`-ordering guard and self-demote branch | D10 |

⚠ **One file only for #5** — see §2's correction. Do **not** carry 2026-08-25's two-file scope.

**Ports** (censused 2026-09-15, `dist/` excluded): `lib-session-state.sh` **4** (antigravity,
claude-code, cursor-template, openai-codex) · `post-edit-check.sh` **4** · `skills/handoff/SKILL.md`
**4** + `tests/` · **`skills/wrapup/SKILL.md` 4** (antigravity, claude-code, claude-cowork,
openai-codex — measured, identical set to handoff; cursor compiles both into `.mdc` instead) ·
`session-start-check.sh` **3** — ⚠ **antigravity has none**, so D5/D7 have no host there.

**Parity ruling** (inherited from 2026-08-25 §8 and the 2026-09-11 spec's OQ1): **claude-code this
round**, then one deliberate parity unit. A partial parity pass is worse than a tracked gap (U16).
⚠ Measured precedent: a prior `/wrapup` clause fix reached six files and **only claude-code was
fixed**. Every port claim must be `cmp`-verified, never assumed.

---

## 6. Acceptance criteria

Each must be able to go **red for the right reason**; a mutation is owed per AC. Provenance is marked
`[08-25]`, `[09-15]` or `[merged]`.

- **AC1** `[08-25]` `resume` is a declared mode: `argument-hint`, description trigger, Step 0 parse.
  ⚠ Step 0's fallback **enumerates the modes verbatim** — update that string, or the error lists 4 of 5.
- **AC2** `[08-25]` One candidate → states `focus` + age, confirms, executes. Zero → says so, no error.
- **AC3** `[08-25]` ≥2 candidates → numbered table of `focus`/`next`/age/freshness from stored fields
  with **no synthesis**, then a pick.
- **AC4** `[08-25]` Every row carries a freshness verdict; picking a stale row requires a confirm
  offering `[resume / keep]`.
- **AC5** `[08-25]` **Legacy parity:** a fixture holding one legacy entry (`## Prior sessions`, no
  terminator) and one current entry yields **2** candidates. Mutation: remove the legacy fallback →
  red, naming the dropped entry. ✅ Extend the existing
  `tests/fixtures/session-contract-vendored/handoff-multi-session.SESSION.md`; do not author a new one.
- **AC6** `[08-25]` A `SESSION.md` with pending entries and **no** active prompt still lists them (G3).
- **AC7** `[08-25]` Combine is offered only under D2's predicate, never auto-selected; absence ≠ error.
- **AC8** `[merged]` `/handoff` emits the token as the first in-fence line, and the **identical** token
  appears in the `SESSION.md` prompt block. *Red if:* the two differ, or it lands outside the fence.
- **AC9** `[09-15]` **Token inertness:** a tokened prompt leaves `^### ` counts, terminator counts and
  `check-session-ledger.py`'s verdict unchanged vs. the same prompt untokened.
- **AC10** `[merged]` Re-run §1.2's two-arm fixture with a tokened prompt: **arm 1 now yields a
  consumed ledger entry for the ACTIVE prompt.** Arm 2 unchanged. *Red if:* arm 1 still yields none.
  **This is the AC that proves §0's hole is closed.**
- **AC11** `[merged]` **Key-exact + literal consume, both defects:** (a) a fixture with the same sid
  under two different `at` values marks exactly **one**; (b) a fixture whose sid contains regex
  metacharacters (`e95b0202 (contract-coherence)` is live; add `[`/`*`) marks correctly.
  *Red if:* (a) marks both, or (b) mis-matches.
- **AC12** `[09-15]` A token whose entry is already terminal causes the session to **surface and stop**.
- **AC13** `[merged, D7]` **Operator precedence:** an opening message of `<a sentence>` + the pasted
  block (i) still detects the token — proving R1's whole-message scan — and (ii) surfaces the sentence
  and reconciles before executing. *Red if:* the token is missed when not on line 1, **or** the prompt
  auto-executes with the sentence unaddressed.
- **AC14** `[09-15]` D8 fires on a reconstruction of `bc3579b` (token sid ≠ front-matter sid) and stays
  **silent** on a reconstruction of one of the 28 corrections. **Both arms required.**
- **AC15** `[09-15]` **Tokenless regression:** the 152 existing prompts and the word-`handoff` fallback
  behave byte-identically to today.
- **AC16** `[08-25]` Gate B headroom measured after the description edit, not asserted (427 B at
  2026-08-25 authoring — **re-measure, do not quote**).
- **AC17** `[was D9 → now UNIT C, D5 step 3]` **Relocation is not reported as destruction.**
  ⛔ **Retargeted 2026-09-15 with D9.** It cannot be satisfied by `kt_ss_ledger_add`, which is purely
  additive (measured) and therefore has no removed key to receipt. It belongs to the **promote** path
  — the operation that actually removes a key while preserving content — which Unit C builds.
  Drive a promote against a fixture so the `(sid|ts)` key disappears while the content survives, then
  run `check-session-ledger.py`: it reports **no loss**, and a receipt naming that key exists.
  *Red if:* the loss fires, or the receipt is absent.
  ⛔ **A receipt must NEVER name a surviving entry** — assert the receipted key is genuinely absent
  from the file afterwards, or this AC certifies the exact bug D9 would have shipped.
  ⛔ **Paired negative control, non-optional:** the same run against a fixture where the content is
  genuinely **gone** must still report the loss. Without it, AC17 passes for a receipt writer that
  suppresses everything — which is strictly worse than the false positive it replaces.
  ⚠ Test isolation: export `KT_SS_RECEIPTS` into the scratch dir. The sibling suite was measured
  writing the **user's real receipts file** on all 11 of its prune calls.
- **AC18** `[D10]` **An older session cannot regress a newer session's state.** Three arms, all
  required, driven against fixtures for **both** `/wrapup` and `/handoff`:
  (a) incumbent `at` **newer** → the active front-matter is **byte-unchanged**, and the writing
  session's prompt appears as a new `## Pending handoffs` entry;
  (b) incumbent `at` **older** → the rewrite proceeds exactly as today (**the non-regression arm** —
  without it, a guard that always self-demotes passes (a) and breaks the normal path);
  (c) incumbent `at` **absent** → treated as older; rewrite proceeds, no crash.
  *Red if:* (a) mutates the front-matter, (b) fails to rewrite, or (c) raises.
  ⚠ The comparison is a plain string compare on ISO-8601 `Z`; a fixture using a local-offset stamp
  must be rejected loudly rather than silently mis-ordered.

---

## 7. Risks — each measured, per the `unsourced-risk-section` pattern

- **The parser drops legacy entries** — measured 3 of 8. Mitigated by AC5 + mutation.
- **Two sid defects on one matcher** — both measured, by two different gates. Mitigated by AC11's two arms.
- **Gate B headroom** — 427 B at 2026-08-25; the description now gains a mode token *and* the skill
  gains token vocabulary. ⚠ **Re-measure before editing**; trim rather than raise.
- **Directive duplication** — ✅ **retired.** Re-measured 2026-09-15 with a positive control: one file.
- **Scope exceeds the measured harm** — the stale-front-matter class is 1.3%. Mitigated by the merge:
  the bulk of this spec is the resume picker, whose driver (multi-candidate, 5 of 6 projects) is the
  larger measured problem.
- **Concurrent writers** — `SESSION.md` is written by several live sessions; measured during this
  arc, a body moved 58 lines between two reads minutes apart. Any write must re-read immediately
  before editing and prefer a surgical anchor.

---

## 8. Out of scope

Changing `kt_ss_ledger_add`'s format · auto-archiving aged entries (time must not evict) · the
`archive` verb and its helper (D1, its own unit) · porting to cowork/codex/cursor/antigravity (one
parity unit, §5) · any change to `/handoff`'s write modes · retro-fitting tokens onto the 152 existing
prompts · recovering the true author of a **tokenless** hook-stamped entry (still unrecoverable; the
2026-09-11 spec's annotation convention stands) · the `## Pending handoffs` terminator gap
(`cs/SESSION.md` measures 128 entries / 124 terminators) · any repair capability in the checker.

---

## 9. Open questions

- **OQ1 — release.** 2026-08-25 was silent; the 2026-09-11 spec chose a dedicated patch release for a
  live data-loss path in an always-loaded skill. Nothing here loses *work* (bodies always survive), but
  D5.5's terminal-entry guard prevents re-running an irreversible migration, which is the strongest
  argument for not waiting. **Recommendation: ride the next release, unless the terminal-entry guard is
  judged urgent on its own.**
- **OQ2 — antigravity has no `session-start-check.sh`,** so D5/D7 have no host. **Recommendation:**
  D4 + D6 + D8 everywhere; D5/D7 where a session-start surface exists; state the asymmetry explicitly
  in the parity unit rather than leaving it implicit.
- **OQ3 — RESOLVED BY THE GATE, and the resolution reordered the arc.** The draft proposed three
  units ordered by decision number. The gate found **D10 has zero dependencies** — no token, no
  parser, no new helper, no format change: it reads a front-matter field present in **8 of 8**
  ledgers, string-compares it, and on the newer-incumbent branch calls `kt_ss_ledger_add`, which
  already exists. It is also the only decision addressing a failure reported as happening **often,
  on two skills, today**; every other decision addresses a failure measured at 1.3% of commits or
  reconstructed from a single incident.

  **Ruled order — five units:**

  | Unit | Steps | Decisions | Gate status |
  |---|---|---|---|
  | **0** | S9 | **D10** | ✅ all pre-validated — **ships first, alone** |
  | **A** | S1 S2 S6 S7 S8 | D4 D6 D8 D9 | ✅ all pre-validated |
  | **B** | S3 S4 | D1 D2 D3 | ⚠ re-measure the multi-candidate driver first (21 days old) |
  | **C** | S5 | D5 D7 | ⚠ depends on A **and** B |
  | **P** | S10 | — | 🚫 one deliberate parity pass; not interleaved (U16) |

  ⚑ **Why this was missed at authoring, recorded because the shape recurs:** D10 arrived mid-arc
  and was appended after D9, so it inherited the tail position from **authoring order** rather than
  from dependency or value. Nothing re-sorts a late decision. Candidate pattern:
  `late-decision-inherits-tail-position`.
