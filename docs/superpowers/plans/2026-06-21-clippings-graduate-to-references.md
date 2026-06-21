# Clippings Graduate to References — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `intake/clippings/` a durable-source on-ramp — clippings *graduate* (default) to `references/sources/` whole AND get mined, instead of being mined-then-deleted.

**Architecture:** Three coordinated edits to the `plugin-claude-code` port: (1) rewrite `/audit-knowledge` Step 2f's disposition flow, (2) make `/index` scan `references/` recursively so graduated sources are indexed, (3) document the two-tier `references/` layout in the plugin template README. Plus a repro suite, version bump, and CHANGELOG entry.

**Tech Stack:** Markdown skill files (`SKILL.md`), bash repro suite (`tests/repros/*.sh`), JSON plugin manifest.

## Global Constraints

- **Port scope:** `plugin-claude-code` ONLY. Do NOT edit `plugin-claude-cowork`, `plugin-antigravity`, or `plugin-openai-codex` skill bodies. (Cowork lacks a clippings step entirely; its port is deferred per spec.)
- **Corpus-schema is canonical (ADR-013):** the `references/sources/` path and `graduated` ledger disposition are corpus-wide schema — any future Cowork port must match them. Encode them precisely.
- **References README: TEMPLATE ONLY.** Edit `plugin-claude-code/template/references/README.md`. Do NOT touch the user's live `~/Projects/knowledge/references/README.md` (user-owned).
- **Version bump:** `2.35.0` → `2.35.1` (PATCH — refinement of existing clippings behavior, per Mike's directive 2026-06-21; not a minor/new-feature bump).
- **Repro convention:** every feature ships `tests/repros/<feature>.sh`; the suite count must stay green.
- **Spec source of truth:** `docs/superpowers/specs/2026-06-21-clippings-graduate-to-references-design.md` (commits 79568ab, 936a69e).
- **Prospect verdict:** PROCEED-WITH-CHANGES (`knowledge/logs/prospect/2026-06-21-file-clippings-graduate-to-references.md`).

---

## File Structure

- `plugin-claude-code/skills/audit-knowledge/SKILL.md` — MODIFY Step 2f (the behavior).
- `plugin-claude-code/skills/index/SKILL.md` — MODIFY Step 1 scan list (one line: `references/` → recursive).
- `plugin-claude-code/template/references/README.md` — MODIFY (add two-tier doc).
- `tests/repros/clippings-graduate.sh` — CREATE (structural assertions).
- `plugin-claude-code/.claude-plugin/plugin.json` — MODIFY (version bump).
- `CHANGELOG.md` — MODIFY (prepend 2.35.1 entry).

---

### Task 1: Rewrite Step 2f disposition flow

**Files:**
- Modify: `plugin-claude-code/skills/audit-knowledge/SKILL.md` (the `## Step 2f: Review Clippings` block)

**Interfaces:**
- Produces: the `references/sources/{file}.md` destination convention + `disposition: graduated` ledger entry that Task 2 (index) and Task 4 (repro) rely on.

- [ ] **Step 1: Replace the Step 2f block.** Find the exact current block (heading `## Step 2f: Review Clippings` through the line before `## Step 3: Scan Memory Files`) and replace it with:

```markdown
## Step 2f: Review Clippings

Scan `{knowledge_folder}/intake/clippings/` for `.md` files. **If the directory doesn't exist or is empty**, skip silently to Step 3.

**If clippings exist**, report the count and total size, then ask the user:

> "Found N clipping(s) (total ~X KB) — saved URLs / snippets / threads (captured via `/intake` or dropped into the folder by hand). Options:"
> 1. **Graduate** (default) — preserve each clipping whole as a durable source in `references/sources/` AND mine it for knowledge
> 2. **Skip** — leave for the next audit

Under **Graduate**, for each clipping:

1. **Derive tags.** Propose tags from the clipping's content, matched against the existing tag vocabulary in `index.md` (mirror `/index`'s tagging). If the clipping already carries `/intake` frontmatter `tags:`, carry them over. **Show the proposed tags for confirm/edit** before writing.
2. **Preserve the source.** Ensure the clipping has `Last updated:` + the confirmed `tags:` frontmatter, then move the whole file to `{knowledge_folder}/references/sources/{filename}.md` (create `references/sources/` if absent). Use `git mv` when the knowledge folder is a git repo, else `mv`.
3. **Mine all six buckets** (insights, decisions, feedback, project context, references, ideas) — same scan as `/extract`. Append findings to the appropriate backlog (`insights-backlog.md` / `decisions-backlog.md` / `extraction-backlog.md`) and route ideas to `intake/ideas/`. Reference-type fragments become curated notes destined for **top-level** `references/` (a distinct tier from the raw source now in `references/sources/`). Because the whole source is preserved in `references/sources/`, dedup any reference fragment against it before promoting — promote a fragment only when it is a distinct, smaller, independently-useful note, not a restatement of the source.
4. **Ledger as graduated.** Create `{knowledge_folder}/archive/audit-{date}/clippings/` if needed; append an entry to its `REMOVED.md`: filename + source + clip-date + `disposition: graduated` + destination `references/sources/{filename}.md`.
5. **No minable content:** the source STILL graduates to `references/sources/` (archival value). Ledger note `disposition: graduated (source only, no fragments mined)`.

There is no discard-the-source path: every processed clipping graduates. "Skip" defers an uncertain clipping to the next audit.

Note findings for presentation in Step 6 under a "Clippings" section (report each as `graduated → references/sources/{filename}` plus any mined items).

```

- [ ] **Step 2: Verify the replacement landed and the old behavior is gone.**

Run:
```bash
SRC=/Users/mikeprasad/Projects/aria/aria-knowledge/plugin-claude-code/skills/audit-knowledge/SKILL.md
grep -c "references/sources/" "$SRC"            # expect >= 3
grep -c "disposition: graduated" "$SRC"          # expect >= 2
grep -c "Graduate.*default" "$SRC"               # expect >= 1
awk '/^## Step 2f/,/^## Step 3/' "$SRC" | grep -c "ledger-clear"   # expect 0 (old discard pattern gone from Step 2f)
awk '/^## Step 2f/,/^## Step 3/' "$SRC" | grep -c "Skip"           # expect >= 1
```
Expected: sources≥3, graduated≥2, Graduate-default≥1, Step-2f ledger-clear=0, Step-2f Skip≥1.

- [ ] **Step 3: Commit.**

```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
git add plugin-claude-code/skills/audit-knowledge/SKILL.md
git commit -m "feat: clippings graduate to references/sources/ (Step 2f, code port)"
```

---

### Task 2: Make `/index` scan `references/` recursively

**Files:**
- Modify: `plugin-claude-code/skills/index/SKILL.md` (Step 1 scan list, the `references/` bullet)

**Interfaces:**
- Consumes: the `references/sources/` convention from Task 1.
- Produces: indexed graduated sources (the consumer trace the prospect confirmed mandatory).

- [ ] **Step 1: Add the recursive annotation.** In `## Step 1: Scan Promoted Folders`, change the line:

```
- `{knowledge_folder}/references/`
```

to:

```
- `{knowledge_folder}/references/` (recursive — includes `sources/` and other subdirectories)
```

(This mirrors the existing `guides/ (recursive — includes subdirectories)` idiom on the line above.)

- [ ] **Step 2: Verify.**

Run:
```bash
SRC=/Users/mikeprasad/Projects/aria/aria-knowledge/plugin-claude-code/skills/index/SKILL.md
grep -nE "references/.*recursive" "$SRC"   # expect 1 hit
```
Expected: one match showing the recursive annotation on the `references/` line.

- [ ] **Step 3: Commit.**

```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
git add plugin-claude-code/skills/index/SKILL.md
git commit -m "feat: /index scans references/ recursively (indexes references/sources/)"
```

---

### Task 3: Document the two-tier layout in the template README

**Files:**
- Modify: `plugin-claude-code/template/references/README.md`

- [ ] **Step 1: Replace the README body.** Current content:

```markdown
# References

External resources — research articles, vendor evaluations, tool comparisons, bookmarked documentation. Content from outside your team that informs decisions.

**File naming:** kebab-case (`stripe-vs-paddle-evaluation.md`, `react-server-components-research.md`)
```

Replace with:

```markdown
# References

External resources — research articles, vendor evaluations, tool comparisons, bookmarked documentation. Content from outside your team that informs decisions.

## Two tiers

- **Top-level `references/`** — curated notes, fragments, and research docs. The distilled, tagged, `/context`-findable layer.
- **`references/sources/`** — verbatim graduated clippings: raw source artifacts preserved whole (each carries `Last updated:` + `tags:` frontmatter). Populated by `/audit-knowledge` Step 2f when a clipping graduates. Both tiers are indexed by `/index` (which scans `references/` recursively).

**File naming:** kebab-case (`stripe-vs-paddle-evaluation.md`, `react-server-components-research.md`)
```

- [ ] **Step 2: Verify.**

Run:
```bash
SRC=/Users/mikeprasad/Projects/aria/aria-knowledge/plugin-claude-code/template/references/README.md
grep -c "references/sources/" "$SRC"   # expect >= 1
grep -c "Two tiers" "$SRC"             # expect 1
```
Expected: both present.

- [ ] **Step 3: Commit.**

```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
git add plugin-claude-code/template/references/README.md
git commit -m "docs: document references/ two-tier layout (template)"
```

---

### Task 4: Repro suite

**Files:**
- Create: `tests/repros/clippings-graduate.sh`

**Interfaces:**
- Consumes: the conventions established by Tasks 1-3.

- [ ] **Step 1: Inspect an existing repro to match the harness shape.**

Run:
```bash
ls /Users/mikeprasad/Projects/aria/aria-knowledge/tests/repros/ | head
head -40 /Users/mikeprasad/Projects/aria/aria-knowledge/tests/repros/autonomy-posture.sh
```
Expected: see the suite's shebang, helper/assert convention, and exit-code pattern. **Match it** (do not invent a new harness shape).

- [ ] **Step 2: Write the repro** following the inspected convention. It must assert:
  1. `audit-knowledge/SKILL.md` Step 2f contains `references/sources/` (≥3) and `disposition: graduated` (≥2).
  2. Step 2f offers `Graduate` as default and `Skip`; contains no discard-the-source path (no `ledger-clear` inside the Step 2f block).
  3. `index/SKILL.md` Step 1 has the `references/` recursive annotation.
  4. `template/references/README.md` documents `references/sources/` + "Two tiers".

Use the same assert-helper and `PASS`/`FAIL` + exit-code convention as the inspected suite. (Exact code deferred to Step 1's inspection — match the existing repros byte-faithfully rather than guessing the harness.)

- [ ] **Step 3: Run the suite; verify green.**

Run: `bash /Users/mikeprasad/Projects/aria/aria-knowledge/tests/repros/clippings-graduate.sh`
Expected: all assertions PASS, exit 0.

- [ ] **Step 4: Run the FULL repro set to confirm no regressions + the suite-count rises by one.**

Run the repo's all-repros runner (discover it — likely `tests/repros/run-all.sh` or a make target; if none, loop `for f in tests/repros/*.sh; do bash "$f"; done`).
Expected: all suites green; count = previous + 1 (was 22 at 2.35.0 → expect 23).

- [ ] **Step 5: Commit.**

```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
git add tests/repros/clippings-graduate.sh
git commit -m "test: repro suite for clippings graduation"
```

---

### Task 5: Version bump + CHANGELOG

**Files:**
- Modify: `plugin-claude-code/.claude-plugin/plugin.json` (version)
- Modify: `CHANGELOG.md` (prepend entry)

- [ ] **Step 1: Bump the version.** In `plugin-claude-code/.claude-plugin/plugin.json`, change `"version": "2.35.0"` to `"version": "2.35.1"`.

- [ ] **Step 2: Prepend the CHANGELOG entry.** Insert directly below the `All notable changes...` line, above `## 2.35.0`:

```markdown
## 2.35.1 — 2026-06-21

**Clippings graduate to `references/` — `intake/clippings/` becomes a durable-source on-ramp.**

Previously `/audit-knowledge` Step 2f mined a clipping then *deleted* the source (ledger-clear). There was no path to preserve a clipping as a citable reference. This makes graduation the default: every processed clipping is preserved whole AND mined.

- **Step 2f (`plugin-claude-code/skills/audit-knowledge/SKILL.md`):** disposition menu is now **Graduate (default) / Skip**; the mine-and-discard path is removed. Graduate derives+confirms tags, `git mv`s the whole clipping to `references/sources/{file}.md`, mines all six buckets to the backlogs, and ledgers `disposition: graduated` (not deleted). No-minable-content clippings still graduate their source.
- **Two-tier `references/`:** top-level = curated fragments/notes; `references/sources/` = verbatim graduated clippings (raw artifacts). Documented in the template `references/README.md`.
- **`/index` (`plugin-claude-code/skills/index/SKILL.md`):** Step 1 now scans `references/` **recursively**, so `references/sources/` is indexed (without this, graduated sources would be invisible — confirmed via /prospect).
- New repro `tests/repros/clippings-graduate.sh`; suite count 22 → 23.
- **Corpus-schema (ADR-013 / ADR-014):** the `references/sources/` path + `graduated` ledger disposition are canonical corpus-wide now; this is a row-3 bidirectional feature. **Ports:** Code-canonical this round — Cowork has no clippings step (its Step 2 ends at 2d); porting it (and the missing 2e/2f) is deferred and must conform to this schema. antigravity/codex follow their normal sync.
- **Distribution note:** the template `references/README.md` change surfaces as a `/setup` diff for existing users; benign, not silent.
```

- [ ] **Step 3: Verify.**

Run:
```bash
SRC=/Users/mikeprasad/Projects/aria/aria-knowledge
grep '"version"' "$SRC/plugin-claude-code/.claude-plugin/plugin.json"   # expect 2.35.1
head -8 "$SRC/CHANGELOG.md" | grep -c "2.35.1"                          # expect 1
```
Expected: version 2.35.1; CHANGELOG top entry is 2.35.1.

- [ ] **Step 4: Commit.**

```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
git add plugin-claude-code/.claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore: release 2.35.1 — clippings graduation"
```

---

## Self-Review

- **Spec coverage:** Surface 1 (Step 2f) → Task 1. Surface 2 (`/index`) → Task 2. Surface 3 (template README) → Task 3. Version/CHANGELOG → Task 5. Repro convention → Task 4. All spec surfaces mapped. ✓
- **Placeholder scan:** Task 4 Step 2 intentionally defers exact repro code to a harness-inspection step (Step 1) rather than guessing the assert convention — this is "match the existing pattern," not a placeholder; the assertions themselves are fully enumerated. All other steps carry literal content. ✓
- **Type/name consistency:** `references/sources/` and `disposition: graduated` are used identically across Tasks 1, 2, 4, 5. ✓
- **Port scope:** every task touches `plugin-claude-code/` only (or repo-root CHANGELOG); no other port edited. ✓
- **Version:** 2.35.1 (patch) used consistently in Task 5 + Global Constraints + CHANGELOG. ✓

## Out of scope (recorded)

- Cowork port of the clippings step (it lacks Step 2e + 2f entirely) — separate follow-up; must conform to this `references/sources/` schema.
- antigravity / openai-codex ports — normal sync cadence.
- aria-site update — evaluated separately after release (conditional on whether the site documents clippings/audit behavior).
- User's live `knowledge/references/README.md` — user-owned, out of scope.
