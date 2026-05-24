---
description: "Build or verify cross-repo STITCH.md linking backend + frontends in a product group. Modes: create, verify, diff, section. Uses CODEMAPs as drift source by default. Trigger: '/stitch create <group>', '/stitch diff <group>'."
---

# /stitch — Cross-repo stitch layer

Generate a cross-repo binding artifact (`STITCH.md`) for a product group (backend + one or more frontends). Tables only, not narrative. Drift detection uses CODEMAP endpoint sections by default with explicit opt-in fallback to grep.

## Step 0: Load config

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

**For `/stitch` specifically:** the group MUST have multiple sub-repos (at least one `backend` role + at least one frontend role). If single-repo, stop with *"/stitch requires a multi-repo group; use `/codemap` for single repos"*.

## Step 1: Resolve paths & output target

- `BACKEND_ROOT` = `<project_root>/<backend folder>` (the one role=backend entry)
- `FRONTEND_ROOTS` = list of `<project_root>/<folder>` for all non-backend roles
- `STITCH_FILE` = `<project_root>/STITCH.md` by default. Override: if `projects_groups[<tag>]` contains a `stitch_path` field, use that (relative to `<project_root>`).

For `create` mode, require `BACKEND_ROOT/CODEMAP.md` and each `frontend_root/CODEMAP.md`. If any missing, list what's missing and recommend running `/codemap create` in each affected repo first.

## Step 2: Load template (create mode only)

Start from `${CLAUDE_PLUGIN_ROOT}/template/stitch/STITCH.template.md`. Fill **Group identity** with:
- Group tag
- Backend repo folder name + `git rev-parse HEAD` if git available
- Frontend repo folder names + revisions
- CODEMAP absolute paths for each repo
- Configured `STITCH_FILE` path

## Step 3: Build sections 2–5 (create + section modes)

Using the loaded CODEMAPs, populate:

- **2. Auth stitch** — token path FE → BE. Source: FE auth slice/hook + BE auth middleware/JWT handler. Table rows: step | location (file) | notes. Mermaid optional, keep minimal.
- **3. Endpoint stitch** — union of FE RTK/fetch calls → BE routes. Normalize paths (strip env prefixes, trailing slashes). Table columns: FE hook/client | HTTP method | FE file | Path | BE urls module | View/handler | Permission | Notes.
- **4. Entity stitch** — when traceable from CODEMAP model/serializer/type tables. Columns: Domain | FE type/schema | BE serializer | Model | Notes.
- **5. Integration stitch** — external services from backend CODEMAP's Integrations section; note FE usage where mentioned. Columns: Service | Env keys | Owner repo | Files | FE usage.

Only populate cells with information that appears in the loaded CODEMAPs. Leave cells blank rather than inventing.

## Step 4: Drift log (create + diff modes)

**Precedence (check in order):**

1. **User-provided script** — check for `<workspace_root>/analyze-stitch.sh` or `<workspace_root>/analyze-stitch.py`. If either exists, invoke with JSON stdin:
   ```json
   {"backend_root": "<abs path>", "frontend_roots": ["<abs path>", ...], "group": "<tag>"}
   ```
   Expect JSON stdout:
   ```json
   {"fe_orphans": [{"call": "...", "file": "..."}, ...], "be_orphans": [{"route": "...", "file": "..."}, ...]}
   ```
   Label output section: *"Drift source: user script (analyze-stitch.*)"*.

2. **CODEMAP-based** (default expected path) — check both CODEMAPs for required endpoint sections:
   - **Backend:** look for URLConf tree section (match heading like `## N. URLConf` or similar). Parse endpoint rows.
   - **Frontend:** look for API client / RTK Query / endpoint table section. Parse endpoint definitions.
   - If both present → normalize to `method + path` tuples, diff the sets. Label: *"Drift source: CODEMAPs (sections: <backend section name>, <frontend section name>)"*.

3. **Missing CODEMAP endpoint data** — **prompt user explicitly** (do NOT silently fall through):
   ```
   STITCH drift detection requires endpoint sections in both CODEMAPs.
   Currently missing:
     - <backend_path>/CODEMAP.md: <missing section name>
     - <frontend_path>/CODEMAP.md: <missing section name> (if applicable)

   Recommended: run `/codemap section <missing section>` in the affected repo(s) first
   (better accuracy, self-improving as you maintain CODEMAPs).

   Fallback: proceed with grep-based drift (coarse — catches presence/absence,
   misses HTTP methods, dynamic paths, non-REST conventions). Output will be
   labeled "Drift source: fallback grep."

   Choose: [C]odemap (stop here, regenerate first) / [G]rep fallback (proceed now)
   ```

4. **On [G]rep fallback** — grep FE for `/api/` strings (and `api/v1/`, `apiSlice`, `fetch(` variants), grep backend for route definitions (Django `urls.py` patterns, or equivalent). Compare normalized sets. Label output: *"Drift source: fallback grep — CODEMAPs incomplete; see recommendation above"*.

5. **On [C]odemap choice** — exit `/stitch` with instruction: *"Run `/codemap section <name>` in <repo>, then re-invoke `/stitch <mode> <tag>`."*

Populate STITCH.md section 6 (Drift log):
- Header row with drift source labeled
- FE orphans table (FE calls missing BE routes): columns FE call | FE file | Notes
- BE orphans table (BE routes unused by FE): columns BE route | BE file | Notes

## Step 5: Write STITCH.md (create mode)

**Overwrite safety** (mirrors `/distill` Step 4):
- If `STITCH_FILE` exists and non-empty, **first-run notice** explains auto-archive.
- **Default:** move existing `STITCH_FILE` to `<workspace>/.aria-stitch/archive/STITCH-YYYY-MM-DD-HHMMSS.md`, then write fresh.
- **Flags:**
  - `--append` — add new dated section below existing (rare for `/stitch`; `section <n>` mode usually preferred; warn user)
  - `--out=<path>` — write to alternate path
  - `--no-archive` — destructive overwrite, explicit opt-in

## Modes

| Mode | Behavior |
|------|----------|
| `create <group>` | Execute Steps 0-5. Write full `STITCH_FILE`. |
| `verify <group>` | Re-read `STITCH_FILE` tables; check cited file paths still exist on disk; flag stale rows. No rewrite unless user requests. |
| `diff <group>` | Run drift detection only (Step 4). Print drift summary; do not modify `STITCH_FILE`. |
| `section <group> <n>` | Rebuild section `n` in-place in `STITCH_FILE`. Skips overwrite safety (only that section changes). |

## Rules

- Tables over narrative.
- Every file path cited must exist on disk when written.
- Do not invent endpoints not evidenced in CODEMAP or code.
- If `--append` is used for `create`, warn user: *"Append on /stitch is rare; `section <n>` is usually the right mode for incremental updates."*
