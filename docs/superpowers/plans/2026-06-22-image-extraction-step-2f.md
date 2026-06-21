# Image Extraction in Step 2f — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/audit-knowledge` Step 2f stops silently skipping image clippings — images (`.png/.jpg/.jpeg/.gif/.webp`) get vision-read, transcribed, graduated, and mined under the existing Graduate disposition.

**Architecture:** Four surgical edits to `plugin-claude-code/skills/audit-knowledge/SKILL.md` Step 2f (scan line, menu prompt, new image sub-flow, shared `git mv` per-file-tracked fix) + a repro + version/CHANGELOG. Extends the v2.35.1 clippings-graduation feature.

**Tech Stack:** Markdown skill file, bash repro suite, JSON manifest.

## Global Constraints

- **Port scope:** `plugin-claude-code` ONLY (Cowork has no Step 2f; antigravity/codex normal sync).
- **Version:** `2.35.1` → `2.35.2` (+0.0.1 patch, per Mike).
- **Spec:** `docs/superpowers/specs/2026-06-22-image-extraction-step-2f-design.md` (commit 15a8785).
- **Prospect:** PROCEED, zero residual (`knowledge/logs/prospect/2026-06-22-file-image-extraction-step-2f.md`).
- **Extensions:** `.png .jpg .jpeg .gif .webp` (raster; SVG excluded).
- **Repro baseline:** 23 suites → 24.
- **House style:** Step 2f expresses scans as PROSE, not globs (sourced OQ2) — match that.

---

### Task 1: Extend the Step 2f scan + menu for images, add the image sub-flow, fix git mv

**Files:**
- Modify: `plugin-claude-code/skills/audit-knowledge/SKILL.md` (Step 2f block only)

This is one task (one cohesive edit to one step), executed as four sub-edits below.

- [ ] **Step 1: Extend the scan line.** Replace:

```
Scan `{knowledge_folder}/intake/clippings/` for `.md` files. **If the directory doesn't exist or is empty**, skip silently to Step 3.
```

with:

```
Scan `{knowledge_folder}/intake/clippings/` for `.md` files **and image files** (`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`). **If the directory doesn't exist or is empty**, skip silently to Step 3.
```

- [ ] **Step 2: Extend the menu prompt** to break out markdown vs images + the cost guard. Replace:

```
**If clippings exist**, report the count and total size, then ask the user:

> "Found N clipping(s) (total ~X KB) — saved URLs / snippets / threads (captured via `/intake` or dropped into the folder by hand). Options:"
> 1. **Graduate** (default) — preserve each clipping whole as a durable source in `references/sources/` AND mine it for knowledge
> 2. **Skip** — leave for the next audit
```

with:

```
**If clippings exist**, report the count and total size — broken out as markdown vs images (e.g., "N clipping(s): M markdown, K images") — then ask the user:

> "Found N clipping(s) (total ~X KB) — saved URLs / snippets / threads (captured via `/intake` or dropped into the folder by hand), plus K image(s). Options:"
> 1. **Graduate** (default) — preserve each clipping whole as a durable source in `references/sources/` AND mine it for knowledge
> 2. **Skip** — leave for the next audit

**Image cost guard:** if there are **more than 5 images**, warn that each is a non-trivial vision read and offer **review all / review first N / defer the rest to next audit** before processing. (≤5: process inline.)
```

- [ ] **Step 3: Add the image sub-flow** after the existing markdown Graduate steps. Insert this block immediately before the line `There is no discard-the-source path:`:

```
**Image clippings (`.png`/`.jpg`/`.jpeg`/`.gif`/`.webp`)** take an image sub-flow instead of the markdown mine path above:

1. **Vision-read** the image via the Read tool (model-native; no OCR/script dependency). If the image is unreadable/corrupt, skip it with a one-line note in the Step 6 report and leave it in `clippings/` (don't graduate a file you couldn't open).
2. **Transcribe** the content to text — a faithful rendering of the visual (nodes + edges for a diagram, on-screen text for a screenshot, series/values for a chart), not just a caption. If content is ambiguous, transcribe what's legible and flag the uncertainty in the transcription body.
3. **Derive + confirm tags** (same as markdown step 1).
4. **Tier decision (per image):** ask whether the transcription is a **faithful-twin** of the image (→ write it to `references/sources/{name}.md`, beside the asset) or **distilled knowledge** that stands alone (→ write it to top-level `references/{name}.md`). Suggest a default — twin if it largely restates an existing synthesis, distilled if it stands alone — and let the user confirm.
5. **Graduate the asset:** move the image to `references/sources/{filename}` (see the tracked-file rule in markdown step 2).
6. **Mine** the transcribed text into the six buckets exactly as a markdown source; dedup reference fragments against any existing synthesis (cross-link, never duplicate).
7. **Ledger** in `archive/audit-{date}/clippings/REMOVED.md`: `{image} | disposition: graduated (image; transcribed → {transcription-path}) | dest: references/sources/{image}`.
8. **No minable content** (decorative/illustrative): the asset still graduates; ledger `graduated (image, source only)`; still write a minimal caption/transcription so the asset is findable.
```

- [ ] **Step 4: Fix the `git mv` line** (shared per-file-tracked correction). Replace:

```
2. **Preserve the source.** Ensure the clipping has `Last updated:` + the confirmed `tags:` frontmatter, then move the whole file to `{knowledge_folder}/references/sources/{filename}.md` (create `references/sources/` if absent). Use `git mv` when the knowledge folder is a git repo, else `mv`.
```

with:

```
2. **Preserve the source.** Ensure the clipping has `Last updated:` + the confirmed `tags:` frontmatter, then move the whole file to `{knowledge_folder}/references/sources/{filename}.md` (create `references/sources/` if absent). **Move rule:** use `git mv` only when the specific file is git-tracked — check with `git ls-files --error-unmatch "{path}"`; if it's untracked (even inside a git repo), use plain `mv` (a bare `git mv` fails on untracked files and would silently leave the clipping behind). This applies to image assets too.
```

- [ ] **Step 5: Verify all four edits landed.**

Run:
```bash
AK=/Users/mikeprasad/Projects/aria/aria-knowledge/plugin-claude-code/skills/audit-knowledge/SKILL.md
S2F=$(awk '/^## Step 2f/,/^## Step 3/' "$AK")
printf '%s' "$S2F" | grep -c '\.png.*\.jpg.*\.jpeg.*\.gif.*\.webp'   # >=1 (scan or sub-flow lists the 5 exts)
printf '%s' "$S2F" | grep -c 'Vision-read'                           # >=1
printf '%s' "$S2F" | grep -c 'Tier decision'                         # >=1 (per-image faithful-twin vs distilled)
printf '%s' "$S2F" | grep -c 'git ls-files --error-unmatch'          # >=1 (per-file-tracked guard)
printf '%s' "$S2F" | grep -c 'more than 5 images'                    # >=1 (cost guard)
printf '%s' "$S2F" | grep -c 'image, source only'                    # >=1 (no-content path)
```
Expected: all ≥1.

- [ ] **Step 6: Commit.**

```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
git add plugin-claude-code/skills/audit-knowledge/SKILL.md
git commit -m "feat: Step 2f handles image clippings (vision-read → transcribe → graduate) + git-mv per-file-tracked fix"
```

---

### Task 2: Repro suite

**Files:**
- Create: `tests/repros/image-extraction.sh`

- [ ] **Step 1: Inspect the harness to match shape.**

Run: `head -25 /Users/mikeprasad/Projects/aria/aria-knowledge/tests/repros/clippings-graduate.sh`
Expected: see the `#!/bin/sh` + `set -e` + `DIR=…/../..` + `ok()/bad()` + footer convention (this is the sibling repro from the prior arc — match it exactly).

- [ ] **Step 2: Write `tests/repros/image-extraction.sh`** matching that harness, asserting against `plugin-claude-code/skills/audit-knowledge/SKILL.md` Step 2f (scope checks to the Step 2f block via the same `awk '/^## Step 2f/,/^## Step 3/'` slice):
  1. scan/sub-flow names all 5 image extensions (`png`, `jpg`, `jpeg`, `gif`, `webp`);
  2. image sub-flow present: `Vision-read`, `Transcribe`, `Tier decision` (faithful-twin vs distilled), graduate, ledger `graduated (image`;
  3. per-file-tracked guard present: `git ls-files --error-unmatch`;
  4. cost guard present: `more than 5 images`.

Use the same `ok()/bad()` + `printf "%d passed, %d failed"` + bare `[ "$FAIL" -eq 0 ]` convention as `clippings-graduate.sh` (exact code deferred to Step 1's inspection — match it).

- [ ] **Step 3: Run the new suite.**
Run: `sh /Users/mikeprasad/Projects/aria/aria-knowledge/tests/repros/image-extraction.sh`
Expected: all PASS, exit 0.

- [ ] **Step 4: Run the full set, confirm 23→24 green.**
Run: `sh /Users/mikeprasad/Projects/aria/aria-knowledge/tests/run.sh`
Expected: all suites green; SUMMARY = 24 suite(s) passed, 0 failed.

- [ ] **Step 5: Commit.**
```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
git add tests/repros/image-extraction.sh
git commit -m "test: repro suite for Step 2f image extraction"
```

---

### Task 3: Version bump + CHANGELOG

**Files:**
- Modify: `plugin-claude-code/.claude-plugin/plugin.json` (version)
- Modify: `CHANGELOG.md` (prepend entry)

- [ ] **Step 1: Bump.** In `plugin-claude-code/.claude-plugin/plugin.json`, change `"version": "2.35.1"` to `"version": "2.35.2"`.

- [ ] **Step 2: Prepend CHANGELOG entry** below the `All notable changes…` line, above `## 2.35.1`:

```markdown
## 2.35.2 — 2026-06-22

**Step 2f handles image clippings — `/audit-knowledge` stops silently skipping images.**

v2.35.1 made clippings graduate to `references/sources/` but scanned `.md` only — image clippings (`.png/.jpg/.jpeg/.gif/.webp`) were invisible (caught when `karpathy-kb-map.jpeg` had sat unprocessed in clippings since April, logged as "kept" across ~7 audits but mechanically unreadable).

- **Step 2f image sub-flow:** images are now scanned and, under Graduate, vision-read (model-native, no OCR) → transcribed to text → tier-decided per image (faithful-twin → `references/sources/`, distilled → top-level `references/`) → asset graduated → transcription mined into the six buckets → ledgered `graduated (image; transcribed → …)`. Decorative images graduate source-only.
- **Cost guard:** >5 images triggers a review-all / review-N / defer-rest prompt (vision reads are non-trivial).
- **Shared fix:** graduation's move rule now uses `git mv` only when the *specific file* is tracked (`git ls-files --error-unmatch`), else plain `mv` — corrects a v2.35.1 bug where `git mv` failed on untracked files (the FB-Instagram clipping hit it). Applies to `.md` and image graduation alike.
- New repro `tests/repros/image-extraction.sh`; suite count 23 → 24.
- **Ports:** Code-canonical. Cowork has no Step 2f (N/A); antigravity/codex normal sync. `/intake` image branch + bulk-dir image pickup deferred (recorded in the spec).
```

- [ ] **Step 3: Verify.**
```bash
SRC=/Users/mikeprasad/Projects/aria/aria-knowledge
grep '"version"' "$SRC/plugin-claude-code/.claude-plugin/plugin.json"   # 2.35.2
head -8 "$SRC/CHANGELOG.md" | grep -c "2.35.2"                          # 1
```

- [ ] **Step 4: Commit.**
```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
git add plugin-claude-code/.claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore: release 2.35.2 — Step 2f image extraction"
```

---

## Self-Review

- **Spec coverage:** scan change → T1S1; menu+cost-guard → T1S2; image sub-flow (vision/transcribe/tier/graduate/mine/ledger/no-content) → T1S3; git-mv fix → T1S4; repro → T2; version/CHANGELOG → T3. All spec sections mapped. ✓
- **Placeholder scan:** T2S2 defers exact repro code to a harness-inspection step (match the sibling), not a placeholder — assertions fully enumerated. No other placeholders. ✓
- **Consistency:** `references/sources/` + `graduated (image` + `git ls-files --error-unmatch` used identically across T1, T2, T3. Repro baseline 23→24 corrected from the spec's 24→25 (live count is 23). ✓
- **Port scope:** all edits in `plugin-claude-code/` or repo-root CHANGELOG. ✓

## Out of scope (recorded)

- `/intake` image branch + bulk-dir image pickup — deferred.
- SVG handling — deferred (text, not vision).
- `/setup` line-63 unreviewed-clippings `.md`-only count won't tally images — cosmetic undercount, optional, not in this plan (noted in prospect).
- Other ports.
