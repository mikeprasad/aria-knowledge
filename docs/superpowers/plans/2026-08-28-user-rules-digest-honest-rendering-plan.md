# Plan — user-rules digest: honest rendering (A6), and the valve deferred

**Status:** ⛔ **SLICE 1 EXECUTED AND SPENT — do NOT re-execute a task.** Gated ×2
(`knowledge/logs/prospect/2026-08-28-file-user-rules-digest-{budget,honest-rendering}.md`), all 10
required changes applied, then executed 2026-08-28 as v2.52.0. T0 all 7 trip-wires matched · T1
byte-identical on the live corpus · T2/T2c 10/7/8/0 with 0 ellipses · **T2d added at execution, see
below** · T3 20+3 assertions, 5 mutations each killed by its NAMED control · T4/T5 done ·
T6 live digest regenerated, **15 ellipses → 0**. Gate A: plugin **316/0**, hook-repro **38 suites**,
both bare exit 0. Gate D clean, positive-controlled.
⚠ **Still open: A1's valve landed (21,000) but slice 2's whole-digest title tier did not** — see §3.
**T4b (header over-budget count) was VALIDATED AGAINST and not built** — see its section.
**Spec:** `docs/superpowers/specs/2026-08-28-user-rules-digest-budget-design.md` (GATED)
**Gate 1:** `knowledge/logs/prospect/2026-08-28-file-user-rules-digest-budget.md` — PROCEED-WITH-CHANGES,
all 5 required changes applied to the spec before this plan was written.
**Subject:** `plugin-claude-code/bin/lib-user-rules.sh` — **one file, one port** (verified: no other
plugin carries it; `plugin-antigravity/build.sh:208` has an explicit skip arm).

---

## 0. Two slices, and why the split is load-bearing

| Slice | Contents | Blocked? |
|---|---|---|
| **1 — honest rendering** | D3 (multi-line lead), A6 (sentence-cut / carry-whole / ceiling) | **No.** Every decision is measured; no ruling needed. |
| **2 — the valve** | D2's self-imposed budget + whole-digest title tier | **Yes — needs Mike's number** (spec §5). |

⛔ **Slice 1 must not wait on slice 2.** D1 and D3 are live rendering defects with measured fixes;
D2 is a mis-calibrated threshold whose urgency A6 *reduces* (slice 1 leaves the digest at 8,807 B (full block)
growing ~320 B per new rule, so ~35 more rules before it reaches even 20,000 B). Coupling them would
hold a measured fix behind a judgment call.

⚑ The title *rendering* is needed in slice 1 — it is A6's ceiling branch. Slice 2 re-uses the same
renderer at whole-digest scope. That is the only dependency, and it points the right way.

⛔ **STATE PLAINLY, so a later reader does not read it as this arc's oversight: D2 remains OPEN after
slice 1, by design.** `KT_USER_RULES_MAX` stays at its measured-unreachable 20,000. Slice 1 does not
create that defect — it **inherits** it — and A6 does not worsen it (+710 B against a 21,000 B
threshold, itself raised this arc per ruling A1). ⚠ Branch (iv) is likewise not a dead path: it never fires on live data but a synthetic
fixture exercises it, and the repo's *"a check that cannot fail is not documentation"* ruling governs
**checks**, not defensive **branches**.

---

## 1. Baseline — T0 (trip-wire, run FIRST)

⛔ **Every figure below is a trip-wire, not decoration. If any disagrees at execution time, STOP and
re-measure — do not proceed on a stale baseline.** Two prior arcs in this repo halted a healthy tree
because a T0 figure was quoted in the wrong unit.

⛔ **Every row carries a RUNNABLE command.** Gate 2 found three rows naming a quantity whose
"method" was a description — *"shipped generator, `KT_KNOWLEDGE_FOLDER` set"* is not something an
executing session can run, and **a trip-wire nobody can run is decoration.** Set
`. plugin-claude-code/bin/config.sh` first — it resolves `KT_KNOWLEDGE_FOLDER` from
`~/.claude/aria-knowledge.local.md`, which is the same path the generator itself uses. Then
`UR="$KT_KNOWLEDGE_FOLDER/rules/user-rules.md"`. ⚠ Do **not** hardcode a home path here: Gate D
(public hygiene, FATAL) rejects a real account name in tracked content, and it caught exactly that
in this table's first draft — making the trip-wires runnable is what introduced it.

| Quantity | Expected | Command |
|---|---|---|
| Rules in corpus | **25** | `grep -c '^### U' "$UR"` |
| Digest block, window 240 | **8,097 B** | `( . plugin-claude-code/bin/lib-user-rules.sh; kt_user_rules_block; printf '%s' "$KT_USER_RULES_BLOCK" ) \| wc -c` |
| Rules rendering severed | **15** | same pipeline, `\| grep -c '…'` |
| Rule lines in block | **25** | same pipeline, `\| grep -c '^- \*\*U'` |
| Generated file | **8,258 B** | `wc -c < ~/.claude/rules/aria-user-rules.md` (161 B = its own header) |
| Leads > 240 B | **15**, exit **1** | `sh plugin-claude-code/bin/check-rule-lead-bytes.sh "$UR" \| grep -c '^OVER'` |
| Multi-line first paragraphs | **0** | `awk '/^### U[0-9]+/{c=1;n=0;next} c{if($0~/^[ \t]*$/){if(n>0){if(n>1)m++;c=0};next}n++} END{print m+0}' "$UR"` |

| Plugin suite | `plugin-claude-code/tests/run.sh` bare exit **0** | `test-*.sh`, auto-globbed |
| Repro suite | `tests/run.sh` bare exit **0** | `repros/*.sh` |

⚠ **`wc -c` on a pipeline measures the block, not the file** — the two differ by exactly the 161 B
header the generated file carries, and the block/rule-lines pair differ by a further 246 B. Gate 1
flagged that two prior arcs halted a healthy tree on exactly this kind of unit mismatch, and this
plan then made the same slip itself (AC-T2c). **Read which of the three a row names before comparing.**
⚑ This note was orphaning the two suite rows out of the table until it was moved below them —
inserting prose into the middle of a markdown table is invisible in source and obvious when rendered.

⚠ **Read the bare exit code, never a piped one.** Both runners are gated on their own exit; a
`| tail` reports the pipe's status and has produced a false green in this repo twice.

---

## 2. Slice 1 tasks

### T1 — D3: capture the whole lead paragraph, not its first line

`lib-user-rules.sh:95-102` guards with `para == ""`, so only the first non-empty line survives and
the paragraph's remainder is dropped **with no ellipsis**. `check-rule-lead-bytes.sh:52` joins the
paragraph. Make the generator agree with the gate.

- **Change:** accumulate (`para = (para == "" ? t : para " " t)`) while collecting, and stop at the
  blank line rather than at the first line.
- **AC-T1a** With a two-line-lead fixture, the rendered line contains text from **both** lines.
- **AC-T1b — SPLIT BY GATE 2.** The byte-identity property is right; asserting it against the *live*
  corpus is not executable, because this workspace has measured **four concurrent sessions** and an
  `/audit rules` run mid-execution would add a rule and break the comparison for a reason unrelated
  to the change.
  - **AC-T1b-i (test):** byte-identity against a **frozen 2-rule fixture** inside the test file —
    deterministic, no live dependency, safe to keep permanently.
  - **AC-T1b-ii (one-time execution check, NOT a test):** capture the live block before the edit,
    compare after, in the same session. Recorded in T6's verification, not asserted in the suite.
  ⭐ The safety property either way: the fix is a **no-op today** (0/25 multi-line) and closes the
  divergence before a hard-wrapped rule makes it live.
- ⚠ Keep the `**Origin:` skip and the leading/trailing-whitespace trims — they are separate
  behaviours that the accumulation must not disturb.

### T2 — A6: three honest renderings, no severed claims

Replace the guillotine at `lib-user-rules.sh:73-78` with:

| | Condition | Rendering |
|---|---|---|
| (i) | `length(p) <= WINDOW` | full lead |
| (ii) | over, **and** a `. ` boundary exists within the window | cut at the last such boundary |
| (iii) | over, no boundary, **and** `length(p) <= CEILING` | **carried whole** |
| (iv) | over, no boundary, over CEILING | **title only** |

- `WINDOW = 240` — unchanged **in this slice**, and paired with `check-rule-lead-bytes.sh`'s default
  (`audit-rules/SKILL.md:134` Step 7.2 asks an author to verify a lead fits it).
  ⚠ **CORRECTED 2026-08-28 (retrospect): this read "and it is a contract", which overstates it.**
  The gate holds 240 because the generator does; it was created to fix a chars-vs-bytes unit error,
  and the generator's 240 was an implementation choice under a ruling about titles vs summaries.
  ⇒ The window is revisable as a **coordinated two-constant change**; AC-T2f polices the pairing.
- `CEILING` — proposed **800**. Inert today (longest live lead 565 B) and bounds only the
  pathological case. Named as a constant with its reason in a comment.
- **AC-T2a** Live corpus renders **10 full / 7 sentence-cut / 8 carried-whole / 0 title-only**.
- **AC-T2b** `grep -c '…'` on the generated digest is **0** (from 15).
- **AC-T2c** Digest block is **8,807 B** (+710 vs the 8,097 B baseline); rule lines still **25**.
  ⚠ **State the unit.** 8,561 B is the same render measured as *rule lines only*; the block adds a
  constant 246 B header. The plan's first draft compared A6's rule-lines figure against today's
  block figure and reported +464 — wrong by 246 B in one direction. Ranking unaffected, delta was not.
- **AC-T2d** No rendering severs a claim: every emitted body ends at a lead's end, a `. ` boundary,
  or is absent (title-only). Assert by construction, not by eyeballing.
- **AC-T2e** A synthetic 2,000-B uncuttable lead renders **title-only**, not whole.
- ⛔ **OQ2 discharge required in the same change:** `length()`/`substr()` are **bytes** under
  `LC_ALL=C`. The existing space-backoff is multi-byte-safe because a space is single-byte; a `. `
  backoff is safe for the same reason (both `.` and ` ` are ASCII and cannot appear inside a UTF-8
  continuation byte). **State this in a comment** — it is the argument, not the code, that a future
  reader needs.

### T2d — the regeneration guard was blind to the generator (ADDED AT EXECUTION)

⛔ **T6 could not pass, and that is how this was found.** `session-start-rules.sh` regenerated the
installed digest only when the SOURCE was newer than the output:

```sh
[ ! -f "$INSTALLED_URULES" ] || [ "$SOURCE_URULES" -nt "$INSTALLED_URULES" ]
```

That test is blind to the **generator** changing. So T2's rendering fix produced a **byte-identical
file** through it, and had it shipped, **every existing user would have kept their old severed digest**
until they happened to edit `user-rules.md`. The fix would have shipped and done nothing.

⛔ **A timestamp test cannot be repaired by adding the generator to it.** `release.sh` ships the
plugin as a **zip**, and unzip preserves stored mtimes, so a freshly-installed generator is routinely
*older* than the user's existing rendering — the guard would stay silent on the commonest upgrade path.

✅ **Fix: compare CONTENT, which is what the digest arm eight lines above already does**, and for the
reason its own comment gives — *"Exact, self-healing across plugin upgrades, and no version marker to
keep in sync."* Render to a temp in the same directory, `cmp`, `mv` only on difference.
- Cost measured: **12.0 ms** per session start against the hook's **10 s** timeout (0.12%); the
  digest arm already spends 3.4 ms on its own `cmp`.
- The temp+`mv` also makes the write **atomic** — the old in-place `>` truncated the live always-on
  file and could leave it partial. Not scope creep: comparing content requires rendering it somewhere.
- The temp name does not end in `.md`, so the instruction-file glob cannot pick it up mid-write.
- **AC-T2d** (assertions UD12a/b/c) A corrupted installed rendering self-heals **even though it is
  NEWER than the source** — the discriminating condition, since that is exactly where a timestamp
  test skips. Mutation-proven two-sided: content guard heals it (25 rules), timestamp gate leaves it
  corrupted (0 rules).
- ⚑ Idempotence preserved: a second run leaves the file's mtime untouched.

### T3 — Tests and the mutation ledger

New file `plugin-claude-code/tests/test-user-rules-digest.sh` — **auto-discovered** by
`plugin-claude-code/tests/run.sh:7` (`for t in "$DIR"/test-*.sh`). No wiring task.

⚠ **The runner SOURCES each test into one shell** (`. "$t"`, line 18) with shared `APM_PASS`/
`APM_FAIL`. So: prefix every variable, and never `exit`. It syntax-checks with `sh -n` before
sourcing, so a parse error counts as a failure rather than aborting the run — do not rely on that
as a substitute for running it.

**Mutation ledger.** Per the amended rule, each mutation needs **two** proofs: (a) name the control
that must catch it and confirm *that* control fired; (b) prove the mutation actually created the
condition.

| | Mutation | Control that must fire | Proof the condition was created |
|---|---|---|---|
| M1 | Revert T1's accumulation to `para == ""` | AC-T1a | the fixture's second line is absent from output |
| M2 | Delete branch (ii) | AC-T2a (7→0 sentence-cut) **and** AC-T2b (ellipses return) | count of `…` goes 0→15 |
| M3 | Delete branch (iii) | AC-T2a (8 carried-whole→0) | 8 lines lose their bodies |
| M4 | Delete branch (iv)'s ceiling | AC-T2e | the 2,000-B fixture emits whole |
| M5 | Raise `WINDOW` to 600 | **AC-T2f: assert the RELATIONSHIP** — generator `WINDOW` == `check-rule-lead-bytes.sh`'s default | the two numbers disagree |

⛔ **M5 exists because the killed option must stay killed** — without a mechanical guard the contract
is remembered, not enforced, and gate 1 caught a live attempt to raise it.
⛔ **But do NOT pin the literal.** Gate 2 falsified that form: an assertion that a constant equals a
literal guards **spelling**, and it goes red for a *correct* coordinated change (if Mike later rules
400 is the right budget, a literal pin fails a legitimate edit and trains its own deletion).
✅ **Assert the relationship instead** — the generator's window must equal the gate's default
(`check-rule-lead-bytes.sh:23`, `BUDGET="${2:-240}"`, greppable). That fires on **drift**, which is
the real failure mode, and stays green through a coordinated change to both.

⚠ **M2's control is deliberately two assertions.** AC-T2b alone (ellipsis count) would also fire if
branch (iii) broke, so it cannot attribute the failure. Pairing it with the per-branch counts is
what makes the kill land in the right scope.

### T4 — Document that 240 is a contract

- One comment block at the `WINDOW` constant: it is mandated by `audit-rules/SKILL.md` Step 7.2;
  raising it relaxes an authoring contract; the sibling gate `check-rule-lead-bytes.sh` defaults to
  the same 240 **on purpose, not by coincidence**.
- Amend the file header's two-tier paragraph (`lib-user-rules.sh:50-54`) to describe the four
  renderings, replacing the current "truncation backs off to the last space" description, which
  becomes wrong at T2.
- **AC-T4** `grep` finds the contract note; the header no longer describes truncation as the only
  over-budget behaviour.

### T4b — Header over-budget count (⚠ AWAITING MIKE'S YES/NO — additive; slice 1 ships without it)

⛔ **Gate 2 found a real defect in A6 and this is its mitigation.** Under A6, branch (iii) carries an
over-budget lead **whole** — so a rule that violates the 240 contract renders in full and **nothing
looks wrong**. Today it renders with an ellipsis. The audit gate still catches violations at
promotion, but U-rules are user-owned and a hand-edit never runs the audit, so A6 removes the only
always-visible signal. ⚠ Honest qualifier: the ellipsis is **weak** feedback — an author sees it only
in a later session's context, never at authoring time.

- **Change:** the digest header already reads *"STANDING USER RULES (N, always in force …)"*. Append,
  only when the count is non-zero: `— M exceed the 240-byte authoring budget`. ~45 B, one
  expression, no new branch, no new constant, no config key.
- **AC-T4b** With the live corpus the header reports **15**; with an all-compliant fixture the
  clause is **absent** (both arms — an always-present clause would be the vacuous version).
- ⚠ **It changes what Mike reads every session, so it is his surface, not a correctness question.**
  Slice 1 is complete and shippable without it.

### T5 — Version + CHANGELOG

- `plugin-claude-code/.claude-plugin/plugin.json` **2.51.0 → 2.52.0** — **MINOR, on precedent, not
  on mechanics.** `CHANGELOG:206` (**v2.48.0**) made exactly this class of change — the U-rule block
  went from *"a bare title index"* to *"a **digest** (title plus a one-line summary)"* — and took a
  minor. `CHANGELOG:481` (**v2.42.0**) states the rule: *"Minor bump (… **new always-on injection** =
  new user-inheritable capability surface)"*. ⚠ Counter-argument recorded rather than hidden: 2.48.1
  and 2.48.2 were patches and D1/D3 are defects, so "patch" is arguable. The precedent turns on
  **what the user inherits** — here a four-branch rendering contract, not a bug fix.
- CHANGELOG entry naming: D1 re-framed against the grandfather clause, D3, A6's four renderings,
  and the killed option with its reason.
- ⚠ **Gate D (public hygiene) is FATAL and scans TRACKED content.** This change adds prose to a
  CHANGELOG and a `bin/` file. **No private project identifiers** — the spec and gate log stay in
  their own repos; nothing from them is quoted into `plugin-claude-code/`.

### T6 — Verification (the observable)

1. Regenerate: `sh plugin-claude-code/bin/session-start-rules.sh </dev/null` (never hand-edit
   `~/.claude/rules/aria-user-rules.md`; its header forbids it).
2. **AC-T6a** `grep -c '…'` on the regenerated file: **0**.
3. **AC-T6b** `grep -c '^- \*\*U'`: **25**.
4. **AC-T6c** file size ≤ **8,800 B** (baseline 8,258 + ~464 + slack).
5. **AC-T6d** Both suites bare exit **0**.
6. ⛔ **AC-T6e — KILLED BY GATE 2 AS VACUOUS. Do not reinstate it.** It required
   `check-rule-lead-bytes.sh` to still exit 1 with 15 OVER, reasoning that a gate going quiet would
   prove the contract had been relaxed. **It cannot fail for that reason, or any reason connected to
   this change:** the gate takes `FILE="${1:-}"` (`:22`) and reads **`user-rules.md`, the source
   corpus** (`:58`), while this change edits the **generator**; its only two mentions of
   `lib-user-rules.sh` are **comments** (`:5`, `:17`). So it passes identically whether the fix
   works, is broken, or is never made. The property it was reaching for — *"has the contract been
   relaxed?"* — is owned by **AC-T2f's relationship assertion** (T3), which is scoped to the two
   artifacts that actually carry the contract.

---

## 3. Slice 2 — the valve (BLOCKED)

**Entry condition: Mike supplies the self-imposed digest budget** (spec §5). Not startable without it.

- A whole-digest title tier as stage 2, replacing the count-plus-pointer as the first fallback
  (2,213 B for 25 rules; 88 B/rule; ~118 rules capacity — extraction proven byte-identical to the
  generator's own).
- `KT_USER_RULES_MAX` default moves from 20,000 to the chosen value.
- ⛔ **The value may NOT be derived from channel capacity** — parent spec §10.7: *"the whole point of
  the file/hook split is that no payload is sized against a cap."* It must be justified on
  share-of-channel or readability grounds.
- ⛔ **Do not restate the headroom figures (2,577 B / 463 B) as constraints.** They are
  extrapolations on the file-count axis (probe C proved two files; the channel holds three).

---

## 4. Out of scope, named so it is not mistaken for an oversight

- `aria-rules.md`'s 66% share of the channel — the larger lever, different artifact, own owner.
- The 3-file aggregate probe (gate 1 residual, `NO-MOVEMENT-STRUCTURAL`): the instruction-file set
  is snapshotted at session start, so a session cannot read a probe file it created.
- Rewording the 15 grandfathered leads to fit 240. That is `/audit rules` work, one rule at a time,
  and A6 exists precisely so it is not urgent.
- Ports: none. Single-port artifact, verified.

---

## 5. Open questions carried into gate 2

- **OQ-P1** Is `CEILING = 800` right, or should branch (iv) be dropped and (iii) made unconditional?
  The ceiling is inert today, so it is unfalsifiable against the live corpus — it is defended only
  by argument, which is exactly what gate 2 should pressure.
- **OQ-P2** Should branch (ii)'s boundary set include this corpus's real clause enders (`⛔`, `⚠`,
  `⇒`, `·`, em-dash) rather than `. ` alone? Spec OQ1, unresolved. Measured consequence of NOT
  extending it: 7 of 15 get a sentence cut; the other 8 fall through to carry-whole — which is
  already honest, so extending the set is an improvement, not a fix.
- **OQ-P3** Is 2.51.1 the right bump, or does changing the rendering of an always-on artifact that
  other sessions read constitute a minor? The rendering is what every session sees.
- **OQ-P4** AC-T1b asserts byte-identity before/after T1. Is a byte-identity assertion on a
  *generated* artifact stable enough to live in a test, or does it belong in the plan as a one-time
  execution check?
