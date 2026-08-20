# Plan — frontmatter for `/auto` judgment ledgers

**Spec:** `docs/superpowers/specs/2026-08-17-auto-judgment-ledger-frontmatter-design.md`
**Spec prospect:** `knowledge/logs/prospect/2026-08-17-file-auto-judgment-ledger-frontmatter.md` → **PROCEED-WITH-CHANGES**
**Date:** 2026-08-17. **Status:** DRAFT, not executed.

**Cold-executable.** Written to be run by a session with no prior context. Every task names the
file, the exact anchor, and how to verify it landed. Nothing here depends on the authoring session.

⚠ **This plan implements the PROSPECTED verdict, not the spec verbatim.** The spec's Option C is
**falsified** and must not be built as written — see T3.

---

## 0. Preconditions — verify before touching anything

Run these first. Any FAIL stops the plan.

```bash
# P1 — two repos exist and are the ones this plan means
test -f ~/Projects/aria/aria-knowledge/plugin-claude-code/skills/auto/SKILL.md && echo "P1a OK"
test -f ~/Projects/knowledge/tools/build-index.py && echo "P1b OK"

# P2 — /auto exists in EXACTLY ONE port (measured 2026-08-17: 1). If >1, this plan's
#      no-propagation assumption is void and T1 must be re-scoped.
find ~/Projects/aria/aria-knowledge -name SKILL.md -path '*auto*' | wc -l   # expect 1

# P3 — the T1 anchor is still present and unique
grep -c 'Write to `<knowledge_folder>/logs/auto/' \
  ~/Projects/aria/aria-knowledge/plugin-claude-code/skills/auto/SKILL.md    # expect 1

# P4 — the T2 anchors are still present
grep -n 'def parse_file' ~/Projects/knowledge/tools/build-index.py          # expect 1 hit
grep -c 'for rel, (tags, title) in sorted' ~/Projects/knowledge/tools/build-index.py  # expect 1
```

⛔ **P5 — repo posture, and it is not a formality.** `aria-knowledge` held **18 uncommitted files
from a parallel session** when this plan was written. Re-measure:

```bash
cd ~/Projects/aria/aria-knowledge && git status --porcelain | wc -l
```

If non-zero, **T1's commit is HELD** (see T6). Do not commit into a repo mid-work; do not `git add -A`
anywhere in this plan.

---

## 1. Baseline capture — T0

**Nothing else runs until these numbers exist.** Three ACs are before/after comparisons, and a
comparison without a captured before-value is not a check.

```bash
cd ~/Projects/knowledge
# B1 — untagged count and its single group (expect 49, all logs/)
python3 tools/build-index.py --validate | sed -n '4,8p' | tee /tmp/plan-baseline-index.txt

# B2 — sibling-family compliance, the AC5 regression baseline.
# ⛔ ASSERT THE RATIO, NOT THE COUNTS. An earlier draft of this plan hardcoded
# "expect 779/779 and 319/319"; 40 minutes later the live values were 783/783 and 320/320
# because parallel sessions landed 4 prospect + 1 retrospect logs. The INVARIANT (100%)
# held perfectly — only the literal was stale. In a shared tree a count is a claim about a
# moment; the AC means "still 100%".
for d in logs/prospect logs/retrospect; do
  tot=$(find "$d" -maxdepth 1 -name '*.md' | wc -l | tr -d ' '); fm=0
  for f in "$d"/*.md; do [ "$(head -c 3 "$f")" = "---" ] && fm=$((fm+1)); done
  if [ "$fm" = "$tot" ]; then echo "$d OK 100% ($fm/$tot)"; else echo "$d FAIL $fm/$tot"; fi
done | tee /tmp/plan-baseline-siblings.txt

# B3 — the 41 ledgers that must remain untouched (AC4)
git -C ~/Projects/knowledge status --porcelain logs/auto/ | wc -l   # expect 0
ls -1 logs/auto/*.md | wc -l | tee /tmp/plan-baseline-ledgers.txt
```

---

## 2. T1 — pin the frontmatter block in `auto/SKILL.md`  *(spec Step #1 + #2 · AC1)*

**File:** `~/Projects/aria/aria-knowledge/plugin-claude-code/skills/auto/SKILL.md`
**Anchor (unique, verified by P3):** the line beginning ``  Write to `<knowledge_folder>/logs/auto/``
**Edit:** insert the block below **between** the `Create logs/auto/ lazily.` sentence and the existing
`Entry shape:` line. Do not alter D7's four-test prose above it or the `### J<N>` entry shape below it.

Text to insert (indented to match the surrounding D7 continuation, 2 spaces):

```
  **Frontmatter is required.** Begin the file with exactly this block, then the entries:

      ---
      type: auto-judgment-ledger
      date: <YYYY-MM-DD>
      arc: "<one line naming the arc this ledger belongs to>"
      status: <all-dispositioned | has-pending>
      tags: [<project-tag(s)>, judgment-ledger, d7]
      ---

  `status` is what makes the ledger queryable — it is the field that answers *"which arcs still
  have judgments waiting on me?"* across every ledger at once, which is currently answerable only
  by reading prose. Set `has-pending` while any entry is unresolved; set `all-dispositioned` only
  when every entry has been accepted, revisited or reverted.

  **`tags:` are required — a ledger IS a knowledge artifact** (Mike's ruling, 2026-08-18), so it
  belongs in the tag index alongside `/prospect` and `/retrospect` logs. Use the project tag(s) plus
  the two fixed tags `judgment-ledger` and `d7` (the standing directive that mandates the artifact).
  This is the convention the corpus already uses — see
  `logs/auto/2026-08-17-port-drift-live-lag-judgments.md`.
```

**Why `status` and not more keys:** the 17 ledgers that already carry frontmatter use **23 distinct
keys** and agree on none beyond four, so there is no de-facto schema to codify. Four keys is the
smallest set that answers the one measured recurring question.

**Verify:**

```bash
cd ~/Projects/aria/aria-knowledge
grep -c 'type: auto-judgment-ledger' plugin-claude-code/skills/auto/SKILL.md   # expect 1 (was 0)
grep -c 'judgment-ledger, d7' plugin-claude-code/skills/auto/SKILL.md          # expect 1 (the tags line)
grep -c 'No `tags:` key' plugin-claude-code/skills/auto/SKILL.md               # expect 0 — RETRACTED by the 2026-08-18 ruling
# the surrounding structure must be intact:
grep -c '### J<N> — <the decision, one line>' plugin-claude-code/skills/auto/SKILL.md  # expect 1
```

⚠ **Body-only edit — do NOT touch the skill's YAML `description`.** Gate B measures frontmatter
descriptions, not bodies. **Measure it anyway** at T5 rather than asserting it is unaffected.

---

## 3. T2 — make the generator able to tell the two cases apart  *(prospect SHRINK of Step #3)*

**File:** `~/Projects/knowledge/tools/build-index.py`

⛔ **Read this before editing.** The spec's Option C proposed a hardcoded `logs/auto/` path
exception. **That is falsified and must not be built.** `build-index.py`'s own header declares its
scope as *"sections that are a pure function of file frontmatter"*; a path exception contradicts the
file's stated design principle, and it rots silently the moment a directory is renamed. Key on the
**property** instead.

**The real work, which the spec did not surface:** `parse_file` returns `(tags, title)` and
**cannot distinguish** *no frontmatter at all* from *frontmatter that omits `tags:`* — both yield
`tags == []`. The property test is impossible until that distinction exists.

**T2a — widen the return.** In `parse_file`:
- docstring → `Return (tags, title, has_frontmatter).`
- the `except OSError` early return → `return [], None, False`
- add `has_fm = False`, set `has_fm = True` inside the `if end != -1:` branch (i.e. a *well-formed*
  frontmatter block — an unterminated `---` is not frontmatter)
- final return → `return tags, title, has_fm`

**T2b — update both call sites** (P4 verified there are exactly two):
- `out[rel] = parse_file(full)` — unchanged in form; the tuple simply widens
- `for rel, (tags, title) in sorted(files.items()):` → `for rel, (tags, title, has_fm) in sorted(files.items()):`

**T2c — classify in `build_sections`.** Where a file currently falls into `untagged` on `if not tags:`,
split it:

First widen the declaration on `build_sections`'s opening line (measured at `:166` — it currently
reads `known, other, untagged = {}, {}, []`, with **no `structured`**, so the snippet below raises
`NameError` without this):

```python
known, other, untagged, structured = {}, {}, [], []
```

Then classify:

```python
if not tags:
    (structured if has_fm else untagged).append(rel)
    continue
```

Return `structured` alongside `known, other, untagged`, and update the single unpacking call site in
`main()`.

**Verify T2 before T3 — this is the mutation check for the distinction itself:**

```bash
cd ~/Projects/knowledge
python3 - <<'PY'
import importlib.util
s=importlib.util.spec_from_file_location("bi","tools/build-index.py")
bi=importlib.util.module_from_spec(s); s.loader.exec_module(bi)
f=bi.scan()
# a file WITH frontmatter and WITH tags -> neither bucket
print("tagged sample:", [r for r,(t,_,h) in f.items() if t][:1])
# a file with NO frontmatter -> untagged, has_fm False
print("no-fm sample :", [(r,h) for r,(t,_,h) in f.items() if not t and not h][:1])
PY
```

⚠ **At this point `structured` is expected to be EMPTY** — no ledger carries frontmatter-without-tags
yet, because T1 only changes what *future* arcs emit. An empty `structured` here is the correct
result, not a failure. It populates as ledgers are written. **Do not "fix" this by backfilling.**

---

## 4. T3 — report the two populations separately  *(AC3)*

**File:** `~/Projects/knowledge/tools/build-index.py`, `render_untagged()`.

Rename to `render_untagged(untagged, structured)` and emit two `### ` groups under
`## Untagged Files`:
- the existing per-top-level-directory grouping for genuinely untagged files
- a new `### structured — intentionally untagged (N)` group listing `structured`, with one line
  stating that these files carry frontmatter and omit `tags:` **by design**, so they are queryable
  but deliberately absent from the tag index

Update `main()`'s `new["Untagged Files"]` counts to count both, and the splice call to pass both.

**Verify:**

```bash
cd ~/Projects/knowledge
python3 tools/build-index.py --validate | sed -n '4,8p'   # must reach fully clean (no DIFFERS)
```

⛔ **Then mutation-check the new group, two-sided** — a group that cannot appear is not a report:

```bash
# 1. create a temp file WITH frontmatter and NO tags inside a scanned root
printf -- '---\ntype: test-fixture\n---\n\n# temp\n' > references/zz-plan-fixture.md
python3 tools/build-index.py --validate | sed -n '/Untagged/p'   # count must rise by 1
python3 - <<'PY'
import importlib.util
s=importlib.util.spec_from_file_location("bi","tools/build-index.py")
bi=importlib.util.module_from_spec(s); s.loader.exec_module(bi)
f=bi.scan()
print("structured now:", [r for r,(t,_,h) in f.items() if not t and h])   # must list the fixture
PY
# 2. remove it and confirm the count returns to baseline (the control)
rm references/zz-plan-fixture.md
python3 tools/build-index.py --validate | sed -n '/Untagged/p'
```

Both arms are required. The first alone cannot distinguish "the group works" from "the group always
prints something".

---

## 5. T4 — regenerate and verify the index  *(AC3, AC5)*

⛔ **Rehearse on a copy first.** `--write` splices ~16,000 lines, and nine non-derivable sections
(Projects, Semantic Hints, Team-Shared, Review, Stale Files, Entities, Skill Connections,
Cross-Reference Suggestions, Cross-Project Promotion Candidates) must survive byte-identical.

```bash
cd ~/Projects/knowledge
S=$(mktemp -d); mkdir -p "$S/tools"
cp index.md "$S/"; cp tools/build-index.py "$S/tools/"
for r in approaches decisions guides references projects logs; do ln -s "$PWD/$r" "$S/$r"; done
grep '^## ' index.md > "$S/h-before.txt"
python3 "$S/tools/build-index.py" --write >/dev/null && grep '^## ' "$S/index.md" > "$S/h-after.txt"
diff "$S/h-before.txt" "$S/h-after.txt" && echo "REHEARSAL OK — 13 headers preserved"
```

Only if the rehearsal passes:

```bash
python3 tools/build-index.py --write
python3 tools/build-index.py --validate | sed -n '4,8p'    # must be fully clean
grep -c '^## ' index.md                                     # expect 13
```

**AC5 regression — the fix touches a sibling skill family, so this is not a formality:**

⛔ **An earlier draft of this step HUNG.** It ended `diff - /tmp/plan-baseline-siblings.txt
<<<"$(cat)"` — `$(cat)` reads the script's own stdin, which never closes; run verbatim it blocked
for a full 2-minute timeout with no output, and the stall looks like a slow index rebuild rather
than a broken command. Assert the invariant directly instead; nothing here can block:

```bash
for d in logs/prospect logs/retrospect; do
  tot=$(find "$d" -maxdepth 1 -name '*.md' | wc -l | tr -d ' '); fm=0
  for f in "$d"/*.md; do [ "$(head -c 3 "$f")" = "---" ] && fm=$((fm+1)); done
  [ "$fm" = "$tot" ] && echo "$d OK 100% ($fm/$tot)" || { echo "$d FAIL $fm/$tot"; exit 1; }
done
```

**AC4 — the 41 must be untouched:**

```bash
git -C ~/Projects/knowledge status --porcelain logs/auto/ | wc -l    # expect 0
```

---

## 6. T5 — gates

**`aria-knowledge`** (T1's repo) — run its own release gates, do not invent new ones:

```bash
cd ~/Projects/aria/aria-knowledge && ./release.sh
```

Gate A = test suites, Gate B = skill-discovery byte budget, Gate C = port-drift (report-only).
⚠ **Record Gate B's measured number.** T1 is body-only so it is *predicted* unaffected — the point
of recording it is that a prediction and a measurement are different things.

**`knowledge`** (T2/T3/T4's repo) — the generator's own gate:

```bash
cd ~/Projects/knowledge && python3 tools/build-index.py --validate
```

Must read fully clean. A permanently-DIFFERS row is a check people learn to ignore.

---

## 7. T6 — commit posture

**`knowledge`:** commit T2/T3/T4 by **explicit named path** — never `-A`, because parallel sessions
write this repo continuously:

```bash
cd ~/Projects/knowledge
git add tools/build-index.py index.md
git commit -F- <<'EOF'
feat(tools): index generator distinguishes structured-untagged from untagged
EOF
```

Push only with per-push permission; verify with `git ls-remote`, never the push command's exit code.

**`aria-knowledge`:** ⛔ **HOLD the commit if P5 measured non-zero.** Leave T1 as an uncommitted
working-tree change and say so in the close-out. Committing into a repo mid-work risks capturing a
parallel session's files, and this repo is **public**.

If P5 measured zero, commit `plugin-claude-code/skills/auto/SKILL.md` alone and bump
`plugin-claude-code/.claude-plugin/plugin.json` as a **patch** (body-only skill change; precedent
v2.38.1). Release ceremony (tag, GH release, 6 stable aliases) is a **separate decision** — do not
run it as part of this plan.

---

## 8. Out of scope — stated so it is not silently widened

- **Backfilling the 41 existing ledgers.** A ledger is a dated record; rewriting 41 of them to move
  a reporting metric edits history. If ever wanted, `status:` only, derived by *reading* each file.
- **The 4 untagged `logs/` root files** (`knowledge-audit-log.md`, `config-audit-log.md`, two 2026-05
  manifests). Neither the property test nor any path rule reaches them — they carry no frontmatter at
  all. They need their own decision. ⚠ **Consequence: AC3 passes while the reported count stays
  nonzero.** That is known and accepted here, not an oversight.
- **`logs/preflight/`'s 1 missing file.** Same class; the property test will cover it for free once
  that skill pins a block, which is not this plan's job.
- **Adding `tags:` to ledgers** (spec Option B). Deferred pending the residual decision below.
- **Port propagation.** P2 measures `/auto` in exactly one port.

## 9. Residual — USER-owned, does not block execution

**Is a judgment ledger a knowledge artifact (tag it, like its prospect/retrospect siblings) or an
operational record (structure it, don't tag it)?** This plan builds the *operational record* reading,
which is reversible in one line. Whether the 1,098 existing sibling tags are actually used for
retrieval is not measurable — it needs query telemetry this system does not have.

## 10. Rollback

Every task is a single-file edit with no migration and no data change.

- T1 — `git -C ~/Projects/aria/aria-knowledge checkout -- plugin-claude-code/skills/auto/SKILL.md` **only if that file is otherwise clean**; if the repo is mid-work, revert by hand from this plan's anchor text. ⛔ Never `git checkout` a path in a tree holding another session's uncommitted work.
- T2/T3 — revert `tools/build-index.py`; the generator is idempotent, so a re-run restores the prior index.
- T4 — reverting the script and re-running `--write` reproduces a **currently-correct** index from the live corpus. ⛔ It does **not** restore the previous file byte-for-byte: the corpus is not frozen (measured 2047 → 2078 scanned files in ~2 hours under parallel sessions). That is still an adequate rollback, because these sections are derived — but the claim has to say what it actually delivers.

## 11. Acceptance criteria → task map

| AC | Task | Verified by |
|---|---|---|
| AC1 block stated verbatim | T1 | two `grep -c` = 1, plus the structural intactness grep |
| AC2 a real arc emits it | **not in this plan** | 🚫 by construction — requires running an arc afterwards |
| AC3 untagged no longer counts ledgers | T3, T4 | `--validate` clean + two-sided fixture mutation |
| AC4 the 41 unchanged | T4 | `git status --porcelain logs/auto/` = 0 |
| AC5 siblings unaffected | T4 | diff against the B2 baseline |

⚠ **AC2 is deliberately outside this plan and is the one that matters most.** It observes a *future*
execution, so it cannot be closed by the session that makes the change. Whoever runs the next `/auto`
arc should check the emitted ledger. If it lacks the block, the conclusion is that instruction-level
pinning did not take here — and the answer is a template or a hook, not better wording.

---

## 12. Plan prospect verdict — 2026-08-17

`/prospect file …` on THIS plan → **PROCEED-WITH-CHANGES**.
Log: `knowledge/logs/prospect/2026-08-17-plan-auto-judgment-ledger-frontmatter.md`.

**All three amendments are applied above.** Every defect the pre-mortem found was in the plan's own
*instrumentation*, not in what it builds — the design, scoping and AC mapping passed unchanged.

- **T4 HUNG** (❌→fixed). The AC5 command blocked for a full 2-minute timeout when RUN. Found by
  executing the plan's own checks rather than reading them — in a plan sold as cold-executable, the
  checks *are* the deliverable. Catalogued as `plan-ships-an-unrun-command`.
- **T2c used an undeclared name** (❌→fixed). `build_sections:166` has no `structured`; the snippet
  would have raised `NameError` on first run.
- **T0/T4 baselines were stale literals** (❌→fixed). "779/779 and 319/319" measured **783/783 and
  320/320** forty minutes later. ⭐ The invariant held at 100% — only the literal moved, so the AC
  was right and its expression was wrong. Catalogued as `baseline-literal-in-a-moving-corpus`.
- **§10's rollback claim overstated** (fixed) — a re-run yields a currently-correct index, not the
  prior bytes.

**Upgraded to ✅ by sourcing:** T1's anchor is exact (`:77` / `:78`), and Gate B provably measures
frontmatter descriptions only (`release.sh:78`), so the body-only edit cannot move the budget.

T1, T3, T5, T6 clear as written. AC2 remains 🚫 by construction and is still the criterion that
decides whether this worked.
---

## 13. RULING APPLIED — a judgment ledger IS a knowledge artifact (Mike, 2026-08-18)

Spec §10 carries the full reasoning. What changed **in this plan**:

- ✅ **T1's block now carries `tags: [<project-tag(s)>, judgment-ledger, d7]`**, and its
  "No `tags:` key" paragraph is **retracted**. The tag convention is **taken from the corpus, not
  invented** — `logs/auto/2026-08-17-port-drift-live-lag-judgments.md` and the 2026-07-30 ledger both
  use exactly this shape. ⚑ Corroborating the ruling: **16 of the 19** ledgers that carry frontmatter
  already carry `tags:`.
- ✅ **T1's verify block was corrected too.** It still asserted `grep -c 'No `tags:` key' … expect 1`
  — a check for text the same amendment retracted, so the plan's own verification would have failed.
  ⚑ Caught because the post-amendment check read **1 where 0 was expected**; an amendment that leaves
  its verification asserting the old state is a half-fix.
- ⛔ **T2, T3 and their §11 AC row are DROPPED.** The ruling deletes the work: a tagged ledger leaves
  `## Untagged Files` by the ordinary path, so the "has frontmatter, deliberately no `tags:`" bucket
  has **zero** population (measured 2026-08-18: 80 untagged, 72 of them `logs/auto/`, and the 8
  non-auto remainder carry **no frontmatter at all**). **Do not widen `parse_file`. Do not touch
  `build-index.py`.** ⇒ **The plan is now T0 → T1 → T5 → T6 in `aria-knowledge` only**, and touches
  `knowledge/` for baselines and reporting only.
- ⚠ **AC5 is rewritten because it would have FAILED AT BASELINE.** It asserted `/prospect` at 100%;
  measured 2026-08-18 it is **801 of 803** — two logs hand-authored in prose without invoking the
  skill. T0's B2 already asserts the **ratio** rather than the literals, and it must now assert
  **no-regression against the captured baseline**, not 100%.
  ⚑ This refines the natural experiment rather than breaking it (**99.75% vs 29%**) and adds a bound:
  **pinning binds the skill's output, not a hand-authored artifact** — a second, independent reason
  AC2 cannot be closed by the executor.
- ⚠ **Backfill REOPENED and is Mike's call** — 53 of 69 ledgers are unreachable by the tag matcher.
  Spec §5's "do not backfill" rested on it being *a reporting metric*; under the ruling it is a
  **retrieval failure**. ⛔ Not in this plan's scope: `status` must be derived by **reading** each
  file, and a wrong `all-dispositioned` over a pending judgment is the worst error available here.
