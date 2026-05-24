# aria-probe — Cowork validation probe

A throwaway plugin to verify Cowork's filesystem semantics for aria-cowork's design. Install, run, read results, uninstall. Builds nothing permanent.

**Current version: v0.2.0** — adds probe 12 (legacy aria-knowledge config readability via two-folder attach).

**What it tests** (5 probes, ~5-7 minutes wall time):

| Probe | Question | Hard-fail? |
|-------|----------|------------|
| 11 | Does cwd resolve to the user-attached folder? | yes |
| 2 | Can the plugin write a new file under the attached folder? | yes |
| 3 | Can the plugin read a file aria-knowledge already wrote there? | yes |
| 7 | Can the plugin capture transcript automatically, or must it fall back to user-paste? | no |
| **12** | **(v0.2.0)** If `~/.claude/` is also attached, can the plugin read `~/.claude/aria-knowledge.local.md` (the legacy aria-knowledge config)? | no |

If all hard-fail probes pass, aria-cowork's spec is greenlit. If any hard-fail probe fails, return to spec — see [VALIDATION.md](../../knowledge/projects/aria-cowork/VALIDATION.md) for fail-consequence paths.

**Probe 12 specifically settles ADR-002's biggest open question:** can aria-cowork read the existing aria-knowledge config from `~/.claude/`, or do we need to relocate config and migrate aria-knowledge to a v2.13.0 read-both fallback? Probe 12 PASS retires the migration plan entirely.

---

## Pre-conditions (do these in Code first)

The fixture file for probe 3 should already exist at `~/Projects/knowledge/probe-test/code-write-test.md`. If it doesn't (or if you want to regenerate it), run from Code:

```bash
mkdir -p ~/Projects/knowledge/probe-test
cat > ~/Projects/knowledge/probe-test/code-write-test.md <<'EOF'
---
written_by: aria-knowledge (running in Claude Code)
written_at: 2026-04-30
purpose: validation probe 3 fixture — Cowork must read this from the user-attached folder
---

# Probe 3 fixture

FIXTURE_MARKER:ARIA_PROBE_3_CODE_SIDE_WROTE_THIS

This file was written from Claude Code by Mike (or by aria-knowledge) into the
shared knowledge folder. aria-probe (running in Cowork) will read this file
in probe 3 to verify cross-surface read works.
EOF
```

(I — Claude in this Code session — already placed this file as part of the spec round. If you've moved or modified it, regenerate.)

---

## Step-by-step

### 1. Package the plugin

From Code (terminal):

```bash
cd ~/Projects/aria/aria-cowork/probe
zip -r /tmp/aria-probe.plugin . -x "*.DS_Store"
```

This produces `/tmp/aria-probe.plugin` per Anthropic's `cowork-plugin-management` packaging recipe.

### 2. Install in Cowork

Open Cowork (desktop app). Drag `/tmp/aria-probe.plugin` into Cowork's plugin install location, OR use Cowork's Settings → Plugins → Install from file.

Verify the plugin appears in your Cowork plugin list as `aria-probe v0.2.0`.

### 3. Attach folder(s)

In a fresh Cowork conversation, attach folders via Cowork's folder picker:

- **Required:** `~/Projects/knowledge/` — used by probes 11, 2, 3, 7. (This is the same folder aria-cowork attaches in production.)
- **Optional but recommended:** `~/.claude/` — used by probe 12. Without this, probe 12 reports `NOT_TESTED` and the ADR-002 config-relocation question stays open. With this, probe 12 settles whether aria-cowork can read existing aria-knowledge config directly.

**Privacy note:** `~/.claude/` contains your Claude Code config + plugin caches + possibly auth state. Attaching it grants Cowork plugins (this probe and any other Cowork plugin running in the session) read access to all of it. The probe is read-only and inspects only `aria-knowledge.local.md`, but the broader access is real. If that's a concern, run probe 12 in a one-off Cowork session and detach `~/.claude/` afterward.

### 4. Run the probe

In the conversation, say:

> /aria-probe

The skill walks through up to 5 probes (probe 12 only runs if `~/.claude/` is attached), asking for confirmation as needed. Total wall time ~5-7 minutes.

### 5. Read the results

After completion, the skill writes a results file at `~/Projects/knowledge/probe-test/probe-results-<timestamp>.md` and outputs a summary table to the conversation.

### 6. Report back to Code

In your next Claude Code session, say:

> read the latest probe-results file and tell me whether aria-cowork is greenlit for Phase 1, and whether probe 12 retires the ADR-002 migration plan

Claude (in Code) will read the results, evaluate against the hard-fail criteria + probe-12 implications, and recommend GREEN / YELLOW / RED + ADR-002 next steps.

### 7. Uninstall (optional cleanup)

After the results are recorded, uninstall `aria-probe` from Cowork. The fixture file at `~/Projects/knowledge/probe-test/code-write-test.md` and the results file can be archived or deleted at your discretion. The `probe-test/` folder doesn't carry over into aria-cowork production usage — it's just a regression-test artifact.

---

## What "PASS" means for each probe

| Probe | PASS criterion |
|-------|----------------|
| 11 | Cowork accepts the folder attachment; cwd reported by the skill matches `~/Projects/knowledge/` |
| 2 | New file appears at `probe-test/cowork-write-test-<timestamp>.md` with the expected content |
| 3 | Skill reads `probe-test/code-write-test.md` and finds the marker `FIXTURE_MARKER:ARIA_PROBE_3_CODE_SIDE_WROTE_THIS` |
| 7 | Either automated transcript capture works, OR user-paste fallback works (both are PASS) |
| **12** | **`~/.claude/` was attached AND `~/.claude/aria-knowledge.local.md` was read successfully (via sandbox-mount path or absolute path) AND content contains `knowledge_folder:` field** |

## What "FAIL" means

| Probe | FAIL consequence |
|-------|------------------|
| 11 FAIL | Folder picker doesn't attach `~/Projects/`. Investigate Cowork settings; check macOS folder permissions; check Cowork's `allowedWorkspaceFolders` admin allowlist if any. |
| 2 FAIL | **Existential.** Cowork sandboxes plugin writes. aria-cowork architecture invalidated. Re-spec to MCP-backed knowledge store + Code-side `/sync` skill. |
| 3 FAIL | Cowork can write but can't read what Code wrote. Investigate Cowork's filesystem-snapshot semantics. May indicate sandbox copies content rather than mounting. |
| 7 FAIL | Both automated and paste fallback failed. Less critical — affects `/snapshot` skill design only. Worst case: drop `/snapshot` from aria-cowork's skill manifest. |
| **12 FAIL** | **`~/.claude/` was attached but the file couldn't be read despite the attach. Indicates Cowork has sandbox restrictions beyond folder-grant. Current ADR-002 config-relocation plan stands; aria-knowledge v2.13.0 migration ships as planned.** |
| **12 NOT_TESTED** | **`~/.claude/` not attached. Re-run with both folders attached to settle the ADR-002 decision. Not a failure — just deferred.** |
| **12 CONFIG_NOT_FOUND** | **`~/.claude/` reachable but `aria-knowledge.local.md` missing (you haven't run aria-knowledge `/setup` in Code yet). Inconclusive. Either run aria-knowledge `/setup` first, then re-run; or proceed with current spec.** |

---

## Why this is a separate folder, not a probe inside aria-cowork

The `probe/` folder is a **throwaway artifact**. It's deliberately separate from `aria-cowork/plugin/` (which doesn't exist yet — that's Phase 1's deliverable) so it can be cleanly deleted after validation without touching production scaffolding. Think of `probe/` as the aria-cowork equivalent of a unit test that exercises the system before the system exists.

After Phase 1 build, `probe/` stays as a regression test — re-runnable any time Mike updates Cowork or wants to confirm aria-cowork still works in a new environment.
