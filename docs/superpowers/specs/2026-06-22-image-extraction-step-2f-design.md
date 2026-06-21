# Design: Image Extraction in /audit-knowledge Step 2f

**Date:** 2026-06-22
**Status:** Design — pending /prospect, then writing-plans
**Scope:** `plugin-claude-code` only
**Author:** mipr
**Extends:** the v2.35.1 clippings-graduation feature (`2026-06-21-clippings-graduate-to-references-design.md`)

## Problem

`/audit-knowledge` Step 2f scans `intake/clippings/` for **`.md` files only**. Image clippings (`.png/.jpg/.jpeg/.gif/.webp`) are silently skipped — never seen by any audit step. Caught concretely in the 87th audit pass: `karpathy-kb-map.jpeg` had sat in clippings since 2026-04-04, was logged across ~7 audits as a "kept as active reference" decision, yet was mechanically unprocessable (every step globs `.md`). It was handled manually this session (Read → transcribe → graduate), proving the capability exists at the tool layer but isn't wired into the skill.

## Decisions (locked during brainstorm 2026-06-22)

1. **Surface: `/audit-knowledge` Step 2f ONLY.** `/intake` single-image branch and bulk-dir image pickup are explicitly deferred (recorded out-of-scope). The clippings drop-zone is where the gap actually bites.
2. **Output shape: graduate asset + transcription** (the manual karpathy-kb-map pattern). Image asset → `references/sources/`; a transcription `.md` is written; the transcribed text is mined into the six buckets.
3. **Transcription tier: per-image decision.** Step 2f asks per image whether the transcription is a *faithful-twin* (→ `references/sources/` beside the asset) or *distilled-knowledge* (→ top-level `references/`). A default is suggested; the user confirms. No fixed rule — both are legitimate depending on whether the transcription is a 1:1 rendering or curated knowledge.
4. **Extensions: `.png .jpg .jpeg .gif .webp`** (common raster). SVG excluded — it's text/XML, read as markup not vision; different path.
5. **`git mv` per-file-tracked fix (shared correction).** Graduation uses `git mv` only when the specific file is tracked (`git ls-files --error-unmatch` check), else plain `mv`. The current Step 2f says "use `git mv` when the knowledge folder is a git repo" — which is wrong: `git mv` fails on an untracked file even in a git repo (the FB-Instagram clipping hit this in the 87th pass). This corrects `.md` graduation too.
6. **Token-cost guard.** Vision reads are non-trivial. If clippings holds >5 images, Step 2f warns and offers review-all / review-N / defer-rest framing (mirrors the capture-step digest-vs-detail pattern).

## Component: Step 2f image sub-flow

Under the existing **Graduate** disposition, when a clipping is an image (extension match), run the image sub-flow instead of the `.md` mine path:

1. **Vision-read** the image via the Read tool (model-native rendering; no OCR/script dependency).
2. **Transcribe** to text — faithful rendering of the visual: nodes+edges for a diagram, on-screen text for a screenshot, data/series for a chart. Capture structure, not just a caption.
3. **Tags:** propose 2-5 tags matched against `index.md` vocabulary; confirm/edit.
4. **Tier decision (per-image):** ask faithful-twin (→ `references/sources/{name}.md`) vs distilled-knowledge (→ top-level `references/{name}.md`). Offer a default based on whether the transcription restates an existing synthesis (→ twin) or stands alone (→ top-level).
5. **Graduate the asset:** move the image to `references/sources/{filename}`. **Tracked-file check:** `git ls-files --error-unmatch "{path}"` → `git mv` if tracked, else plain `mv`.
6. **Mine** the transcribed text into the six buckets (insights/decisions/feedback/project/references/ideas), same as a `.md` source. Dedup any reference fragment against existing syntheses — cross-link, never duplicate.
7. **Ledger** in `archive/audit-{date}/clippings/REMOVED.md`: `{image} | disposition: graduated (image; transcribed → {transcription-path}) | dest: references/sources/{image}`.
8. **No minable content** (decorative/illustrative image): asset still graduates; ledger `graduated (image, source only)`; no transcription mining, but a minimal transcription/caption is still written so the asset is findable.

## Data flow

```
intake/clippings/{image}.{png|jpg|jpeg|gif|webp}
        │  (Step 2f: Graduate → image sub-flow)
        ├─► Read (vision) ─► transcribe to text
        ├─► tier decision: faithful-twin → references/sources/{name}.md
        │                  distilled    → references/{name}.md
        ├─► git mv|mv asset ─► references/sources/{image}   [tracked-file check]
        ├─► mine transcribed text → six buckets → backlogs / fragments
        └─► ledger ─► archive/audit-{date}/clippings/REMOVED.md (disposition: graduated, image)
```

## Cost guard

Before processing, count image clippings. If >5: warn ("N images — each vision-read is ~non-trivial tokens") and offer **review all / review first N / defer rest to next audit**. ≤5: process inline. Mirrors Step 2d/2e capture digest-vs-detail.

## Error handling

- **Unreadable / corrupt image** → skip with a one-line note in the Step 6 report ("could not read {file} — left in clippings"); do not graduate a file the model couldn't open.
- **Untracked file** → plain `mv` (the §Decision-5 fix); never let a `git mv` failure silently leave the file behind (the 87th-pass bug).
- **Ambiguous content** (model unsure what the image shows) → transcribe what's legible, flag uncertainty in the transcription body, still graduate.

## Testing / validation

New repro `tests/repros/image-extraction.sh` (24→25 suites) asserting against `plugin-claude-code/skills/audit-knowledge/SKILL.md` Step 2f:
- scan covers the 5 image extensions (`png|jpg|jpeg|gif|webp`);
- image sub-flow steps present (vision-read → transcribe → per-image tier decision → graduate → ledger);
- the per-file-tracked `git mv` guard is documented (`git ls-files --error-unmatch`);
- the >5-image cost guard is present.
Plus the full `tests/run.sh` set stays green (count 24→25).

## Versioning

Code-port patch bump (+0.0.1, per Mike): `2.35.1` → `2.35.2`. Refines existing Step 2f (additive image path + the `git mv` correction). CHANGELOG entry with ports note (Code-canonical; Cowork has no Step 2f, so N/A there).

## Out of scope (recorded)

- `/intake` single-image branch (today misroutes an image arg to bulk-scan → no-op). Deferred.
- `/intake` bulk-dir image pickup. Deferred.
- SVG handling (text-based; mine as markup via the normal `.md`-ish path if ever needed).
- Other ports (cowork has no clippings step; antigravity/codex normal sync).

## Open questions for /prospect

- Does the current Step 2f text need the `git mv` line changed in exactly one place, or are there multiple `git mv` references across the skill that should all get the tracked-file guard?
- Is there an existing extension-matching idiom in the skills (e.g., a glob or case pattern) to mirror, so the image-extension check is consistent with house style?
- Confirm no other skill consumes `intake/clippings/` assuming `.md`-only (would a non-`.md` file there break anything upstream of Step 2f)?
