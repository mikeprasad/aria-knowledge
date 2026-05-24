---
description: "Turn raw task text into a tiered executable spec per TASK.schema.md. Auto-tiers by complexity (micro/standard/full). Optional --group loads CODEMAPs for cited context. Trigger: '/distill', '/distill --group=<tag> \"…\"'."
argument-hint: "<text or file path> [--group=tag] [--tier=micro|standard|full] [--append|--out=path|--no-archive]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# /distill — Task transformation

Turn raw task text into a tiered executable spec following `TASK.schema.md`. Auto-tiers by complexity or accepts explicit `--tier`. Optional `--group` loads CODEMAPs for cited-path context.

## Step 0: Inputs

- **Raw task input** — inline string argument, file path, or prompt user to paste if no argument provided.
- **Optional `--group=<tag>`** — load CODEMAPs + STITCH for cited-path context (see shared-block below).

<!-- shared-block: group-loader -->
Read `~/.gemini/antigravity/aria-knowledge.local.md`. Parse YAML frontmatter `projects_groups` (multi-line YAML block — see `CONFIG.md` "Skill-only fields" for canonical schema, including the optional `stitch_path` sub-field and custom-role conventions).

Look up `<tag>` in `projects_list` (get `project_root`) and `projects_groups` (get role → folder dict).

- If `<tag>` missing from `projects_list`: stop with *"unknown project tag: <tag>"*.
- If `<tag>` in `projects_list` but missing from `projects_groups` and `<project_root>` has multiple sub-dirs with repo markers: trigger **auto-propose bootstrap**.
- If `<tag>` is a single-repo project (no multi-repo sub-dirs detected): load `<project_root>/CODEMAP.md` only.

**Auto-propose bootstrap** (when `projects_groups[<tag>]` is missing but `<project_root>` contains multiple repo-marker sub-directories):
1. Scan `<project_root>` one level deep for sub-directories with repo markers:
   - `manage.py` + `settings.py` → `backend` (Django)
   - `composer.json` + `artisan` → `backend` (Laravel)
   - `Gemfile` with `rails` → `backend` (Rails)
   - `package.json` with `express`/`fastify`/`nestjs` → `backend` (Node)
   - `next.config.*` → `web` (Next.js)
   - `app.json` + `expo` in package.json → `mobile` (Expo)
   - `package.json` with `react` (no `next`/`expo`) → `web` (React SPA)
   - other `package.json` → prompt user for role name
2. Handle role conflicts: if two dirs inferred as same role, prompt user to assign distinct keys (`web`, `web-admin`, etc.).
3. Propose the group structure to user: sub-repo names, inferred roles, YAML block to insert. Show a preview diff of the change to `~/.gemini/antigravity/aria-knowledge.local.md`.
4. On approval, edit the config file to add the `projects_groups[<tag>]` entry, preserving existing fields and YAML structure.
5. On decline, stop with *"proceed after registering group manually"*.

Resolve each `(role, folder)` pair to absolute path: `<project_root>/<folder>`. For each absolute path, read `CODEMAP.md` if it exists. Read `<project_root>/STITCH.md` if it exists. Return resolved path map + warnings for any missing CODEMAPs.
<!-- /shared-block: group-loader -->

- **Optional `--tier=micro|standard|full`** — explicit tier overrides auto-scoring. Else compute score:

| Signal | Points |
|--------|--------|
| >1 layer (FE+BE, BE+DB, …) | +2 |
| New endpoint / route / model / migration | +2 |
| External service (Stripe, Twilio, S3, SendGrid, Algolia, OpenAI, Vercel, …) | +2 |
| Auth / permissions / security | +2 |
| Input >150 words or multi-paragraph | +1 |
| Names >3 files | +1 |
| Single-sentence trivial edit | −3 |

Score ≤ 0 → `micro`; 1–3 → `standard`; ≥ 4 → `full`.

## Step 1: Schema

Follow `${CLAUDE_PLUGIN_ROOT}/template/distill/TASK.schema.md` section tags `[R]` `[L]` `[O]` `[F]`.

- **Always emit (`[R]`):** 1 Objective, 2 Scope, 5 Dependencies & API Requirements, 10 QA, 11 DoD.
- **Layers (`[L]`):** include Frontend / Backend / Database only if the task actually touches that layer. Never emit empty headings.
- **Tier gates:**
  - `full` adds **3 Non-Goals** (`[F]`).
  - `standard` and `full` add **4 Assumptions** (`[O]`, include when non-empty) and **9 Edge Cases** (`[O]`, include when non-empty).
  - `micro` skips Non-Goals; Assumptions only if a blocking ambiguity exists.

## Step 2: Single chosen approach

One implementation path per layer section. No option menus inside a layer. Matches the discipline of Rule 22's Execute step: commit to one plan.

## Step 3: Validation

- All `[R]` sections present for the chosen tier.
- No empty `[L]` sections (omit entirely if layer not touched).
- With `--group`, every cited file path must appear in the loaded CODEMAP or STITCH content. If Claude invents a path, either remove the citation or promote the uncertainty to **Assumptions** as a blocking item.
- **Advisory vocabulary check:** scan output for the list in `TASK.schema.md` (`flexible`, `extensible`, `scalable framework`, `we could also`, `alternatively`, `one option`, `potentially`, `might want to`). Prefer concrete alternatives. Not a hard rejection — surface as a soft warning in skill output, continue otherwise.

On validation failure: self-correct once, then move remaining gaps to **Assumptions** as blocking items.

## Step 4: Output

Default output path: `TASK.md` in CWD.

**Overwrite safety:**
- If `TASK.md` exists and is non-empty, **first-run behavior**: emit a one-time notice explaining the auto-archive default. Subsequent runs are silent.
- **Default:** move existing `TASK.md` to `.aria-distill/archive/TASK-YYYY-MM-DD-HHMMSS.md`, then write fresh output to `TASK.md`.
- **Archive directory** (`.aria-distill/archive/`) created lazily on first archive. First-run notice suggests adding `.aria-distill/` to `.gitignore`.

**Flags override defaults:**
- `--append` — add new entry below existing `TASK.md` content, separated by `---` and a `## Distilled YYYY-MM-DD HH:MM` header. No archive.
- `--out=<path>` — write to the specified path. Existing `TASK.md` untouched; no archive.
- `--no-archive` — overwrite existing `TASK.md` without archiving. Destructive opt-in; display a warning before proceeding.

**Writing steps:**
1. Determine final target path from flags / default.
2. If archive applies: verify `.aria-distill/archive/` exists (create if not), move existing file in with timestamped name.
3. Write spec to target path.
4. Print summary: tier chosen, score (if auto), target path, archive path (if any), advisory-vocab warnings (if any).

No backlog or side files beyond the archive.
