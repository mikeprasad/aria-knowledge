# User-rules digest — truncation window, growth, and a valve that cannot fire

**Status:** GATED — gate 1 (`/prospect`) run 2026-08-28, verdict **PROCEED-WITH-CHANGES**; all
5 required changes applied. Gate report: `knowledge/logs/prospect/2026-08-28-file-user-rules-digest-budget.md`.
Still no code — the plan and gate 2 come next.
**Date:** 2026-08-28
**Subject:** `plugin-claude-code/bin/lib-user-rules.sh` (the only port that carries it)
**Parent:** `docs/superpowers/specs/2026-08-25-always-on-rules-delivery-design.md` — that spec
owns the channel; this one owns the U-rule digest's own sizing. **Read its §10.7 before
proposing anything that references channel capacity.**

**Origin:** Mike asked whether a U-rule over 240 characters is silently truncated (yes, and in
BYTES not characters), then — after the measurements below — asked the question this spec exists
to answer: *"400 is fine but what if i add new rules... it could hit limit"*.

---

## 1. What is measured

All figures derived this session by script, against the live 25-rule corpus at
`knowledge/rules/user-rules.md`. Digest sizes come from the **shipped awk program** with only
its window literal varied — not a reimplementation. Faithfulness control: the harness at window
240 emits 25 rule lines and 8,097 B; the live generated `~/.claude/rules/aria-user-rules.md`
carries the same 25 lines at 8,258 B, the 161 B delta being the file's own markdown header.

### 1.1 The truncation window

| Window (bytes) | Digest block | Rules complete |
|---:|---:|---:|
| **240 (current)** | 8,097 | **10 / 25** |
| 300 | 8,892 | 15 / 25 |
| 400 | 9,698 | 19 / 25 |
| 500 | 10,099 | 22 / 25 |
| **600** | **10,211** | **25 / 25** |
| 700 | 10,211 | 25 / 25 |

⭐ **600 saturates.** 700 is byte-identical, because the corpus's longest lead is 565 B. So 600
is the measured *ceiling of need* for this corpus, not a preference — and any window above it is
indistinguishable from it until a longer rule is written.

### 1.2 Cost per rule, by rendering tier

| Tier | B/rule | 25 rules | Rules inside the digest's current ~10.4 KB allocation |
|---|---:|---:|---:|
| Title-only | **88** | 2,213 | **~118** |
| Digest, window 240 | 323 | 8,097 | ~32 |
| Digest, window 600 | 408 | 10,211 | ~25 |

### 1.3 Where the channel's bytes actually are

| File | Bytes | Share |
|---|---:|---:|
| `aria-rules.md` (the plugin's own 38 working rules) | 21,221 | **66%** |
| `aria-user-rules.md` (this digest) | 8,258 | 25% |
| `context7.md` | 2,338 | 7% |
| **total** | **31,817** | |

⚠ **The user digest is the minority tenant.** Any framing of this as "the user digest is
crowding the channel" is wrong by a factor of 2.6.

### 1.4 The 240 is functioning as an authoring discipline, not only a display cap

`bin/check-rule-lead-bytes.sh` shipped in v2.49.0 and **is wired** — `skills/audit-rules/SKILL.md`
Step 7 runs it, and `tests/test-audit-rules.sh` assertion AR7 guards that wiring. Its effect is
visible in the corpus:

```
U19 209   U20 230   U21 233   U22 232   U23 229   U24 234   U25 232      (newest seven)
U1  297   U3  348   U5  299   U7  357   U9  454  ... U17 565             (older, pre-gate)
```

Seven consecutive newest rules landing at 209-234 B against a 240 B budget is authored-to-fit.
⛔ **Consequence: raising the window is not a neutral display change — it raises the authoring
budget too, and removes the constraint currently keeping per-rule cost near 230 B.** No prior
document states this, and it is the main argument against simply raising the number.

### 1.5 Sentence boundaries

For each of the 15 over-budget rules, is there a `. ` sentence boundary inside the first 240 B?

- **7 rules: yes** — truncating there yields a complete sentence instead of a severed clause.
- **8 rules: no** — U5, U7, U9, U11, U12, U14, U15, U16. For these, no sentence-boundary rule can
  help; the fallback must be something other than a cut.

⚑ Re-derived by script this session rather than quoted. An earlier statement of this finding gave
only the negative half ("cannot help the 8"), which is true and misleading — it helps 7.

---

## 2. The two defects

**D1 — the guillotine is the wrong instrument for a knowingly-legacy set.** 15 of 25 rules render
with their operative text cut to an ellipsis. A half-claim is worse than a title, because a severed
qualifier can invert the rule's meaning: a lead reading `never X unless Y` truncated before
`unless` instructs the opposite of the rule.

⛔ **Framed precisely — and this framing is what makes the fix small.** The existence of truncation
is **not** an open defect: `/audit rules` Step 7 item 6 explicitly grandfathers these rules —
*"scope the check to the new rules — **older rules may legitimately carry one**"*. So the accepted
state is *"new rules fit 240; the legacy set may truncate."* The defect is therefore **not** that
240 exists, nor that old rules exceed it — it is that the *rendering* chosen for that legacy set is
a hard cut that can invert meaning, when two honest renderings are available at comparable cost.
⇒ **Fix the rendering, not the number.**

**D2 — `KT_USER_RULES_MAX` cannot fire.** The valve replaces the digest with a
count-plus-pointer above 20,000 B. The digest is 8,097 B and the channel's remaining headroom
above today's total is **2,577 B**. So the valve sits at **7.8x the space actually available**: the
channel truncates its own tail long before the valve trips. The graceful degradation the design
has is present, correct, and unreachable.

⚑ D2's shape is `feedback_guard_scoped_to_the_wrong_unit` — the threshold is not mis-tuned, it is
measured against the wrong quantity (the digest in isolation, rather than the digest's share of a
shared channel).

**D3 — a multi-line lead loses everything after its first line, silently.** `lib-user-rules.sh:95`
guards its assignment with `para == ""`, so only the **first non-empty line** of the lead is
captured; subsequent lines of the same paragraph match no rule and are discarded — **with no
ellipsis and no signal**, which is strictly worse than truncation, since truncation at least marks
itself. `check-rule-lead-bytes.sh:52` by contrast joins the whole paragraph
(`lead = lead " " $0`), so **the gate and the generator measure different quantities**.

⚠ **Latent, not live: 0 of 25 rules have a multi-line first paragraph** (measured), which is the
only reason every figure in §1 is valid — the two extractions coincide today by content, not by
construction. Fixing the generator to join the paragraph is a **no-op on today's corpus** and closes
the divergence before a hard-wrapped rule makes it live.

---

## 3. The constraint that governs any fix

Parent spec **§10.7**, read out of the Claude binary 2026-08-26: the channel threshold is
`min(tool.maxResultSizeChars, ceiling)` with a per-tool override map behind a server-side gate.
Its third consequence is explicit:

> ⛔ **No payload may be sized against the cap** ... Stop sizing against it.

and of the file channel's headroom, §10:

> ⛔ **That headroom is NOT a budget.** ... 32,056 B is a proven floor at one moment.

⛔ **This kills the obvious fix.** Computing the valve at generation time as
`proven_channel - size(other rules files)` is precisely sizing a payload against the cap. It was
the recommendation carried into this spec and it is **withdrawn on the parent spec's own ruling**,
not on a judgment call.

✅ **What the ruling permits.** §10.7 forbids deriving a budget *from the cap*. It does not forbid
the design having a **self-imposed** budget justified on other grounds — share-of-channel,
readability, or a deliberate ceiling on always-on cost. A self-imposed budget can be small,
stable, and knowable, which is what makes a valve able to fire.

⛔ **CONSEQUENCE FOR THIS SPEC: every headroom figure below is an EXTRAPOLATION and is NOT
load-bearing.** Probe C proved 34,394 B aggregate across **two** files (`_probe-c-size.md` 32,056 +
`context7.md` 2,338). The live channel now holds **three** files totalling 31,817 B. Both proven
bounds are individually satisfied — largest single file 21,221 < 32,056; aggregate 31,817 < 34,394 —
but the **file-count axis is unmeasured**, and the parent spec's own rule is that nothing here may
be sized against an extrapolation.

⇒ **The figures "2,577 B headroom now" and "463 B at window 600" are context, not constraints.**
They are retained because they are true of a measured moment, and they must not appear in any
argument that decides the design. **The design must be correct without knowing the headroom** —
which is what §4.1's three honest degradation stages deliver.

---

## 4. Options, filtered

Per U18: options with a provable defect are named and excluded here rather than offered.

### Fork A — the truncation window

| | Option | Disposition |
|---|---|---|
| A1 | Keep 240 unchanged | ⛔ **Excluded** — it is D1. 15 of 25 rules ship severed claims today. |
| A2 | Raise the window to 600 | ⛔ **Excluded — dominated by A5** (below): identical output today, strictly worse on the next long rule. |
| A3 | Raise to 400 | ⛔ **Excluded** — 19/25 complete, so it does not close D1; and it costs 1,601 B for a partial fix. |
| A4 | Keep 240, sentence-cut else **title-only** | ⚠ **Viable but lossy** — 5,498 B (32% *smaller* than today), zero severed claims, but **8 rule bodies delivered today are reduced to bare titles** — a content regression. |
| A5 | Window 600 + sentence-else-title | ⛔ **EXCLUDED — same ground as A2.** |
| **A6** | **Keep 240; sentence-cut where possible, carry the lead WHOLE where not** | ✅ **Recommended.** |

⛔ **A1, A2, A3 and A5 are all excluded on ONE ground, and it is not byte cost.** `/audit rules`
Step 7 item 2 (`skills/audit-rules/SKILL.md:134`) makes 240 a **binding authoring contract**:

> *"The always-on digest builder truncates each rule's first paragraph at **240 BYTES** … a failing
> lead is reworded before proceeding, **never shipped to truncate**."*

Raising the window raises the authoring budget with it, relaxing a contract another skill's
promotion mechanics mandate — and dismantling the discipline §1.4 measures working. **The window is
not an available axis.** (A1 is excluded separately: it is D1.)

### A6 — the window is a target, not a guillotine

A lead renders as one of three things, and **none of them severs a claim**:

| | Condition | Rendering | Count today |
|---|---|---|---:|
| (i) | lead ≤ 240 B | full lead | **10** |
| (ii) | lead > 240 B **and** a `. ` boundary exists inside the window | cut at that boundary — a complete sentence | **7** |
| (iii) | lead > 240 B **and** no boundary exists | **carried whole** | **8** |

⛔ **UNIT CORRECTED 2026-08-28 (execution). The first draft of this table mixed two units** —
`today` was a **full block** figure while `A4` and `A5` were **rule-lines-only** — so every delta
was computed across units. The block carries a constant **246 B** header, so the *ranking* was
unaffected and no decision changes; the *deltas* were wrong. Restated below in **full-block bytes
throughout**, measured.

| Option | Digest (full block) | vs today | Severed claims | Rule text lost |
|---|---:|---:|---:|---|
| today — 240 guillotine | 8,097 | — | **15** | severed tails |
| A4 — else title-only | 5,744 | −2,353 | 0 | **8 rule bodies** |
| **A6 — else whole** | **8,807** | **+710** | **0** | **none** |
| A5 — window 600 | 10,457 | +2,360 | 0 | none, but breaks the 240 contract |

⭐ **A6 costs +710 B — 2.2% of the channel — and is the only option that severs nothing, loses no
text, and leaves the authoring contract intact.** It dominates A5 (cheaper, same honesty, contract
preserved) and dominates A4 on content (A4 withdraws 8 bodies that ship today).

⚠ **A6 needs a second bound.** For an uncuttable lead the window stops bounding anything, so the
carry-whole branch takes an **absolute ceiling** above which it falls to title-only. The longest
live lead is 565 B, so a ceiling around 800 B is inert today and bounds only the pathological case.

### Fork B — the valve

| | Option | Disposition |
|---|---|---|
| B1 | Leave 20,000 | ⛔ **Excluded** — it is D2; measured unreachable. |
| B2 | Derive it from proven channel capacity | ⛔ **Excluded by §10.7**, quoted in §3. |
| B3 | Remove the valve; rely on the payload being small | ⛔ **Excluded — dominated by B4**: same cost, but no signal when the design's own ceiling is passed. |
| **B4** | **A self-imposed digest budget, valve calibrated to it** | ✅ **Recommended.** Its *value* is the one thing this spec cannot settle alone — see §5. |

### Fork C — what happens when the budget is exceeded (Mike's growth question)

| | Option | Disposition |
|---|---|---|
| C1 | Nothing — let the channel truncate | ⛔ **Excluded** — silent, and it drops the *tail*, which is load-ordering, not importance. |
| C3 | Keep full lines for as many rules as fit, titles for the rest | ⛔ **Excluded — provable defect**: the demotion order would be U-number, which is arbitrary with respect to importance. It would silently privilege low-numbered rules. |
| C4 | Fall to a bare count-plus-pointer (today's behaviour) | ⛔ **Excluded — dominated by C2**: same channel cost, delivers zero triggers where C2 delivers ~118. |
| **C2** | **Fall to the title tier for all rules** | ✅ **Recommended.** 88 B/rule => ~118 rules in the digest's current allocation. |

⭐ **C2 is not new machinery.** The title tier *is* the shape the U-rule block had before the
2026-08-26 widening to a digest — recorded in `lib-user-rules.sh`'s own header comment. It is a
rendering that already shipped and worked, retained as the degradation tier rather than invented
for it.

### 4.1 The resulting three stages

| Stage | Rendering | Capacity in the digest's ~10.4 KB |
|---|---|---|
| 1 | Full digest, <=600 B/rule, sentence-safe | ~25 rules |
| 2 | Title tier | **~118 rules** |
| 3 | Count-plus-pointer | unbounded |

**This is the answer to the growth question.** Growth costs bytes but never costs correctness: no
stage severs a claim, and the transition between stages is signalled rather than silent.

---

## 5. The one ruling owed

Everything above is decided by measurement or by the parent spec's ruling. One question is
genuinely Mike's, because it has no objectively best answer:

**What share of the always-on channel should his own 25 rules get?**

Concretely, the value of B4's self-imposed budget. Context for deciding: the plugin's own 38
working rules currently take 21,221 B (66% of the channel) and his 25 take 8,258 B (25%). At
window 600 his rise to 10,372 B (31%). The tradeoff is not against a cap — it is against his own
rules being summaries he must go and read versus arriving ready to apply.

This is stated here and carried into the plan as an open ruling. **It does not block gate 1.**

---

## 6. Open questions for gate 1

- **OQ1** Does the sentence-boundary scan need to handle this corpus's actual sentence enders?
  Leads here routinely end clauses with the stop/warn glyphs, arrows, middle dots and em-dashes
  rather than `. `. A scan keyed only on `. ` may find fewer boundaries in future rules than in
  these.
- **OQ2** `length()` and `substr()` in the shipped generator operate on **bytes** under the C
  locale. A sentence-boundary cut must not land mid-codepoint. The existing space-backoff is
  safe by construction; a `. `-backoff needs the same argument made explicitly.
- **OQ3** Is there any consumer of the digest that parses its shape? A title-only line has no
  ` — ` body separator, so a consumer splitting on it would see a malformed line. Census owed.
- **OQ4** The title tier drops the *only* always-on statement of a rule's content. For a rule
  whose title is imperative (`U2 — Don't use Bash file redirects to bypass Edit/Write hooks`) that
  is still a usable trigger; for one whose title is a noun phrase it may not be. Sample and judge.
- **OQ5 — RESOLVED AND CLOSED (gate 1).** Asked whether `check-rule-lead-bytes.sh`'s 240 default
  should move with the window. ⛔ **It must not, and under A6 the question dissolves** — the gate
  and the generator both hold 240, so there is no divergence to reconcile. Recorded here because a
  future session will otherwise read the two numbers as drift and "fix" it by raising one:
  **240 is a contract (`audit-rules` Step 7.2), not a tunable.** The residual is a code comment
  saying so.
- **OQ6** `tests/run.sh` executes `repros/*.sh` only. `test-audit-rules.sh` and
  `test-aria-rules-digest.sh` sit at `tests/` top level — how does the release Gate A reach them?
  Answer before assuming a new test file is picked up.

---

## 7. Scope

**In:** `plugin-claude-code/bin/lib-user-rules.sh`; possibly
`plugin-claude-code/bin/check-rule-lead-bytes.sh` (OQ5); a test file; CHANGELOG.

**Out:** `aria-rules.md`'s own 66% share — the larger lever, but a different artifact with a
different owner and its own retirement question. Naming it here so it is not mistaken for an
oversight.

**Ports:** `lib-user-rules.sh` exists in **one** plugin only (`plugin-claude-code`);
`plugin-antigravity/build.sh:208` carries an explicit skip arm for it. **No port drift to
reconcile** — verified this session, not assumed.
