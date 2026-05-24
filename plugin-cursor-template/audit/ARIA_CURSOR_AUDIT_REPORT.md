# ARIA Cursor Port — Audit & Fix Report

**Audited:** 2026-05-18
**Port path:** `/home/user/workspace/aria-knowledge`
**Upstream:** `https://github.com/mikeprasad/aria-knowledge` @ `965d69a` (HEAD)
**Port basis version:** 2.16.1 (unchanged — upstream HEAD is also 2.16.1; the only commit on top is `965d69a` docs: QUICKSTART.md)

---

## 1. Upstream Sync Status

`git log` on upstream shows the latest tagged release matching the port (`2.16.1`). The only commit on top of `2.16.1` is `965d69a docs: add QUICKSTART.md` — a documentation addition, no code/skill/hook changes.

**Decision:** No upstream feature-port required. Add a Cursor-adapted `QUICKSTART.md` so docs parity with upstream is restored. Done.

| Item | Upstream `2.16.1` | Port baseline | Action |
|---|---|---|---|
| `plugin.json` version | 2.16.1 | n/a (Cursor — no plugin.json) | Port mirrors via `scripts/aria/VERSION` (2.16.1) + `last_setup_version: 2.16.1` in local config. Confirmed. |
| QUICKSTART.md | Present (new file from `965d69a`) | **Was missing** | **Added** Cursor-adapted `QUICKSTART.md` at port root. |
| 25 skill SKILL.md files | All present | 22 ported (canonical) + 3 aliases referenced | **Added** `/help` and `/audit-share` to `aria-commands.mdc`; aliases documented in preamble + AGENTS.md. Parity now 25/25. |
| Knowledge folder template | `intake/pre-compact-captures/` present | **Removed by design** | Correct per migration plan (Cursor has no compaction lifecycle). Replaced with `intake/task-boundary-captures/`. |

---

## 2. Parity Matrix

Status legend: ✅ exact · ≈ equivalent · ⚠ advisory · ✗ unavailable.

### Plugin packaging

| Upstream feature | Original | Cursor equivalent | Status | Enforcement | Fix applied |
|---|---|---|---|---|---|
| Plugin manifest | `.claude-plugin/plugin.json` | `.cursor/hooks.json` (hooks) + `.cursor/rules/*.mdc` (skills) + repo root `AGENTS.md` | ≈ | n/a (manifest is registry metadata) | None needed — Cursor's native layout. |
| Version reporting | `plugin.json:version` | `scripts/aria/VERSION` + `last_setup_version` in `.cursor/aria-knowledge.local.md` | ≈ | session-start uses static `INSTALLED_VERSION` | Confirmed correct. |
| Marketplace ID | `marketplace.json` | n/a | ✗ | n/a | No Cursor marketplace concept. Documented in audit. |

### Hooks

| Upstream hook | Original | Cursor equivalent | Status | Enforcement | Fix applied |
|---|---|---|---|---|---|
| `SessionStart` | `bin/session-start-check.sh` | `sessionStart` → `scripts/aria/session-start-check.sh` | ≈ | advisory (agentMessage) | Cursor port: stripped `${CLAUDE_PLUGIN_ROOT}` and `INSTALLED_VERSION` set static. |
| `PreToolUse: Edit\|Write` | `bin/pre-edit-check.sh` (transcript scan) | `beforeFileEdit` → `scripts/aria/pre-edit-check.sh` (intent marker) | ⚠ | advisory (no agent-side deny) | Intent-marker enforcement added via `record-edit-intent.sh` + `KT_EDIT_INTENT_FILE`. Missing/stale/mismatched markers escalate wording. |
| `PostToolUse: Edit\|Write` | `bin/post-edit-check.sh` | `afterFileEdit` → `scripts/aria/post-edit-check.sh` | ≈ | advisory | Consumes the intent marker on successful matching edit. |
| `PreToolUse: Bash` | `bin/bash-cd-check.sh` | `beforeShellExecution` → `scripts/aria/bash-cd-check.sh` | ≈ | advisory (cd-into surfacing) | Output format flipped to `agentMessage`. |
| `PreToolUse: Glob\|Grep` | `bin/pre-explore-codemap-check.sh` | `beforeReadFile` → `scripts/aria/pre-explore-codemap-check.sh` | ≈ (broader trigger) | advisory | Fires on file reads more broadly than Glob/Grep but the surfacing logic still gates output. |
| `TaskCreated` | n/a (Claude-only) | `stop` → `scripts/aria/task-context-check.sh` + `capture-task-boundary.sh` | ⚠ | advisory | `stop` fires at task end, not task start. Self-trigger instruction added in `AGENTS.md`. |
| `PreCompact` | `bin/pre-compact-check.sh` + `save-transcript.sh` | **removed by design** | ✗ | n/a | No Cursor compaction lifecycle. Task-boundary capture substitutes. |
| `PostCompact` | `bin/post-compact-check.sh` | **removed by design** | ✗ | n/a | Same. |

### Skills (all 25)

| Skill | Upstream SKILL.md | Cursor port | Status |
|---|---|---|---|
| `/setup` | `plugin-claude-code/skills/setup/SKILL.md` | `.cursor/rules/aria-commands.mdc#/setup` | ✅ |
| `/help` | `plugin-claude-code/skills/help/SKILL.md` | `.cursor/rules/aria-commands.mdc#/help` (**added**) | ✅ |
| `/extract` | `plugin-claude-code/skills/extract/SKILL.md` | `.cursor/rules/aria-commands.mdc#/extract` | ✅ |
| `/audit-knowledge` + alias `/knowledge-audit` | `plugin-claude-code/skills/audit-knowledge/`, `plugin-claude-code/skills/knowledge-audit/` | `.cursor/rules/aria-audit.mdc#/audit-knowledge`; alias documented | ✅ |
| `/audit-config` + alias `/config-audit` | `plugin-claude-code/skills/audit-config/`, `plugin-claude-code/skills/config-audit/` | `.cursor/rules/aria-audit.mdc#/audit-config`; alias documented | ✅ |
| `/audit-share` + alias `/share-audit` | `plugin-claude-code/skills/audit-share/`, `plugin-claude-code/skills/share-audit/` | `.cursor/rules/aria-commands.mdc#/audit-share` (**added**); alias documented | ✅ |
| `/context` | `plugin-claude-code/skills/context/` | `.cursor/rules/aria-context.mdc#/context` | ✅ |
| `/rules` | `plugin-claude-code/skills/rules/` | `.cursor/rules/aria-context.mdc#/rules` | ✅ |
| `/index` | `plugin-claude-code/skills/index/` | `.cursor/rules/aria-commands.mdc#/index` | ✅ |
| `/backlog` | `plugin-claude-code/skills/backlog/` | `.cursor/rules/aria-commands.mdc#/backlog` | ✅ |
| `/stats` | `plugin-claude-code/skills/stats/` | `.cursor/rules/aria-commands.mdc#/stats` | ✅ |
| `/ask` | `plugin-claude-code/skills/ask/` | `.cursor/rules/aria-commands.mdc#/ask` | ✅ |
| `/clip` | `plugin-claude-code/skills/clip/` | `.cursor/rules/aria-commands.mdc#/clip` | ✅ |
| `/intake` | `plugin-claude-code/skills/intake/` | `.cursor/rules/aria-commands.mdc#/intake` | ✅ |
| `/codemap` | `plugin-claude-code/skills/codemap/` | `.cursor/rules/aria-commands.mdc#/codemap` | ✅ |
| `/distill` | `plugin-claude-code/skills/distill/` | `.cursor/rules/aria-commands.mdc#/distill` | ✅ |
| `/stitch` | `plugin-claude-code/skills/stitch/` | `.cursor/rules/aria-commands.mdc#/stitch` | ✅ |
| `/handoff` | `plugin-claude-code/skills/handoff/` | `.cursor/rules/aria-commands.mdc#/handoff` | ✅ |
| `/prospect` | `plugin-claude-code/skills/prospect/` | `.cursor/rules/aria-commands.mdc#/prospect` | ✅ |
| `/retrospect` | `plugin-claude-code/skills/retrospect/` | `.cursor/rules/aria-commands.mdc#/retrospect` | ✅ |
| `/snapshot` | `plugin-claude-code/skills/snapshot/` (transcript snapshot) | `.cursor/rules/aria-commands.mdc#/snapshot` (task-boundary capture — repurposed) | ≈ |
| `/wrapup` | `plugin-claude-code/skills/wrapup/` | `.cursor/rules/aria-commands.mdc#/wrapup` | ✅ |

Rule22 framework (`/rules/change-decision-framework.md`) lives at `.cursor/rules/aria-rule-22.mdc` — full text verbatim.

### Knowledge folder format

| Item | Upstream | Port | Compatible? |
|---|---|---|---|
| Directory structure (`approaches/`, `decisions/`, `rules/`, `guides/`, `references/`, `archive/`, `distill/`, `stitch/`, `projects/`) | ✅ | ✅ | Yes |
| Intake structure (`insights-backlog.md`, `decisions-backlog.md`, `extraction-backlog.md`, `rules-backlog.md`, `notes/`, `clippings/`, `attachments/`, `ideas/`) | ✅ | ✅ | Yes |
| `intake/pre-compact-captures/` | present | **omitted** (Cursor has no PreCompact) | Yes — additive-only removal of unused subdir, no schema change |
| `intake/task-boundary-captures/` | not present (Cursor-only) | present | Yes — additive-only addition, doesn't affect upstream readers |
| Frontmatter (`name`, `description`, `type`, `tags`, `semantic-hints`) | ✅ | ✅ | Yes |
| `index.md` tag-index format | ✅ | ✅ (built by `/index`) | Yes |
| `aliases.md` format | ✅ | ✅ | Yes |
| `working-rules.md`, `change-decision-framework.md`, `enforcement-mechanisms.md`, `retrospect-patterns.md`, `user-examples.md`, `user-rules.md` | ✅ | ✅ | Yes |
| Audit log formats (`logs/knowledge-audit-log.md`, `logs/config-audit-log.md`, `logs/hook-debug.log`) | ✅ | ✅ | Yes |

**Knowledge folder format is fully compatible with upstream.** A Claude Code repo and a Cursor port repo can share the same knowledge folder.

---

## 3. Fixes Applied

### 3.1 Cursor `.mdc` frontmatter (5 files)

**Root cause:** Cursor's project-rules spec at `.cursor/rules/*.mdc` requires YAML frontmatter with `description`, `globs`, `alwaysApply`. The port shipped without it — rules might load as untyped markdown, or not at all.

**Fix:** Added frontmatter to each:

| File | description (truncated) | globs | alwaysApply |
|---|---|---|---|
| `aria-rule-22.mdc` | "Rule 22 — change decision framework…" | `["**/*"]` | `true` |
| `aria-core.mdc` | "ARIA core — five-phase knowledge lifecycle…" | `["**/*"]` | `true` |
| `aria-context.mdc` | "ARIA context surfacing — /context and /rules…" | `["knowledge/**/*.md"]` | `false` |
| `aria-audit.mdc` | "ARIA audit skills — /audit-knowledge … /audit-config…" | `["knowledge/intake/**/*", "knowledge/index.md", ".cursor/aria-knowledge.local.md", "AGENTS.md"]` | `false` |
| `aria-commands.mdc` | "ARIA workflow commands — /extract, /index…" | `["knowledge/**/*", "CODEMAP.md", "STITCH-*.md"]` | `false` |

Validation: YAML parsed cleanly on all 5; all fields present.

### 3.2 Missing skills

Added `/help` and `/audit-share` SKILL content to `aria-commands.mdc` (port verbatim from upstream, with paths substituted to `.cursor/aria-knowledge.local.md` and `AGENTS.md`).

Documented aliases `/knowledge-audit`, `/config-audit`, `/share-audit` in:
- `aria-audit.mdc` preamble
- `aria-commands.mdc` preamble
- `AGENTS.md` command table

### 3.3 `AGENTS.md` skill list

`AGENTS.md` previously listed 15 commands. **Added:** `/help`, `/audit-share`, `/distill`, `/stitch`, `/prospect`, `/retrospect`, `/handoff`. Now covers all 22 canonical commands + 3 aliases.

### 3.4 QUICKSTART.md (Cursor port)

Upstream introduced `QUICKSTART.md` in commit `965d69a`. Added a Cursor-adapted equivalent at port root that:
- Preserves the structure of upstream's QUICKSTART.
- Adds a "What's different from the Claude Code version" comparison.
- Documents the edit-intent marker workflow.
- Calls out fail-open semantics and Cursor Cloud agent limitations.

---

## 4. Validation Results

### 4.1 JSON / YAML / bash parse

```
.cursor/hooks.json: HOOKS_JSON_OK
.cursor/rules/aria-audit.mdc:    OK fields=alwaysApply,description,globs
.cursor/rules/aria-commands.mdc: OK fields=alwaysApply,description,globs
.cursor/rules/aria-context.mdc:  OK fields=alwaysApply,description,globs
.cursor/rules/aria-core.mdc:     OK fields=alwaysApply,description,globs
.cursor/rules/aria-rule-22.mdc:  OK fields=alwaysApply,description,globs
.cursor/aria-knowledge.local.md: LOCAL_CONFIG_OK (knowledge_folder + cadences + last_setup_version present)
bash -n on all 13 scripts: OK_ALL
```

### 4.2 Executable bits

All `scripts/aria/*.sh` have the executable bit set (rwxr-xr-x).

### 4.3 Hook payload smoke tests

Run order:

```
1) sessionStart                          → 148-byte agentMessage, JSON_OK
2) beforeFileEdit (no intent marker)    → 740 bytes, "PROTECTED FILE + NO EDIT-INTENT MARKER" advisory, JSON_OK
3) record-edit-intent.sh                → wrote .cursor/aria-edit-intent.json
4) beforeFileEdit (with marker)         → 498 bytes, normal Rule 22 reminder (no escalation), JSON_OK
5) afterFileEdit (with marker)          → 534 bytes scope-check, marker consumed
6) beforeShellExecution (`cd /tmp`)     → silent (no surfacing match for /tmp)
7) beforeReadFile                       → silent
8) stop (task-context-check.sh)         → silent
9) stop (capture-task-boundary.sh)      → wrote knowledge/intake/task-boundary-captures/20260518-040535-s2.md
```

All hook outputs (non-empty) parse as valid JSON. Marker write→verify→consume cycle confirmed end-to-end.

### 4.4 Unsupported dependencies grep (active instructions only)

```
grep -E 'transcript_path|tool_use_id|PreCompact|PostCompact|pre-compact-captures|save-transcript' scripts/aria/*.sh
→ Only comments documenting the Cursor differences. No active dependencies.

grep -E 'CLAUDE_PLUGIN_ROOT|~/.claude/|HOME/.claude/' scripts/aria/*.sh
→ Zero hits. All paths use $KT_ROOT and .cursor/.
```

### 4.5 Protected-file matching

`pre-edit-check.sh` and `post-edit-check.sh` protect `AGENTS.md|working-rules.md|change-decision-framework.md|enforcement-mechanisms.md|hooks.json` (not the Claude `CLAUDE.md|plugin.json`). Confirmed by smoke test #2 above — editing `AGENTS.md` without a marker triggers the protected-file branch.

---

## 5. Enforcement Audit (where Cursor is weaker than Claude Code)

| Capability | Claude Code | Cursor | Mitigation in port | Residual gap |
|---|---|---|---|---|
| **Transcript proof of Rule 22** (verify `[Rule 22]` block was emitted above the Edit/Write tool call) | Python transcript scan walks the JSONL backwards | None — no transcript_path | Edit-intent marker file written by `record-edit-intent.sh`; `beforeFileEdit` checks file+session+age (<10 min) and escalates wording on missing/stale/mismatch. | **Advisory only.** Agent can still call Edit/Write without a marker. The marker check escalates the warning but does not block. |
| **Pre-edit deny** | `hookSpecificOutput.permissionDecision: "deny"` | No documented stable agent-side deny for `beforeFileEdit` | Strong wording for protected-file + missing-marker; `permission:"deny"` is emitted only on shell hooks per Cursor's spec | Cursor docs are unclear whether emitting `{"permission":"deny","userMessage":...,"agentMessage":...}` from `beforeFileEdit` is honored. The port stays fail-open. **Future fix:** if Cursor adds documented `beforeFileEdit` deny, swap the protected-file branch to emit it. |
| **PreCompact / PostCompact** | Pre/post compaction transcripts captured | No compaction lifecycle in Cursor | `stop` → `capture-task-boundary.sh` writes a non-transcript snapshot (git + status + diff + active batch + recent hook log) | **No transcript content.** Captures structural state only. |
| **TaskCreated** | Fires at sub-task creation | No equivalent | Self-trigger instruction in `AGENTS.md`: tokenize task text, match `## Tag Index`, load files | **Compliance is instruction-bound.** If the agent skips the self-trigger, no auto-surfacing. |
| **InstructionsLoaded / SkillsLoaded** | n/a (Claude Code uses skill auto-load) | n/a — `.cursor/rules/*.mdc` are persistent context | All 5 `.mdc` files have correct frontmatter (`description`, `globs`, `alwaysApply`); core + rule-22 set `alwaysApply: true` | None; this is Cursor's design. |
| **Path-loading for skills** | Claude resolves `${CLAUDE_PLUGIN_ROOT}` | Cursor resolves `command` paths relative to `.cursor/hooks.json` | All scripts source `config.sh` which sets `KT_ROOT` from `git rev-parse --show-toplevel \|\| pwd` | None. |

**Proposed future fixes (only if Cursor adds the capability):**

1. If Cursor publishes a stable `beforeFileEdit` deny semantic, change `pre-edit-check.sh` to emit `{"permission":"deny", …}` when (a) the file is protected AND (b) no marker exists. This would make protected-file Rule 22 fail-closed.
2. If Cursor adds a `taskStart` or `userPromptSubmitted` event, wire `task-context-check.sh` to it instead of (or in addition to) `stop`, so context surfaces at task *start* rather than *end*.
3. If Cursor exposes a transcript path to hooks, restore the transcript-scoped Rule 22 scan and drop reliance on the marker file.

---

## 6. Final File Tree

See `/home/user/workspace/ARIA_CURSOR_FILE_TREE.txt` for the complete listing (53 entries). Directory shape:

```
aria-knowledge/
├── AGENTS.md
├── QUICKSTART.md            ← NEW (Cursor-adapted)
├── .cursor/
│   ├── aria-knowledge.local.md
│   ├── hooks.json
│   └── rules/
│       ├── aria-audit.mdc       ← frontmatter added
│       ├── aria-commands.mdc    ← frontmatter added; /help and /audit-share added
│       ├── aria-context.mdc     ← frontmatter added
│       ├── aria-core.mdc        ← frontmatter added
│       └── aria-rule-22.mdc     ← frontmatter added
├── knowledge/
│   ├── OVERVIEW.md
│   ├── LOCAL.md
│   ├── README.md
│   ├── aliases.md
│   ├── approaches/
│   ├── archive/
│   ├── decisions/
│   ├── distill/
│   ├── guides/
│   ├── intake/
│   │   ├── attachments/
│   │   ├── clippings/
│   │   ├── decisions-backlog.md
│   │   ├── extraction-backlog.md
│   │   ├── ideas/
│   │   ├── insights-backlog.md
│   │   ├── notes/
│   │   ├── rules-backlog.md
│   │   └── task-boundary-captures/   ← Cursor-specific
│   ├── logs/
│   ├── projects/
│   ├── references/
│   ├── rules/
│   │   ├── change-decision-framework.md
│   │   ├── enforcement-mechanisms.md
│   │   ├── retrospect-patterns.md
│   │   ├── user-examples.md
│   │   ├── user-rules.md
│   │   └── working-rules.md
│   └── stitch/
└── scripts/aria/
    ├── VERSION
    ├── bash-cd-check.sh
    ├── capture-task-boundary.sh
    ├── config.sh
    ├── digest-transcript.sh
    ├── lib-index-match.sh
    ├── lib-tracked-artifacts.sh
    ├── migrate-ideas-backlog.sh
    ├── post-edit-check.sh
    ├── pre-edit-check.sh
    ├── pre-explore-codemap-check.sh
    ├── record-edit-intent.sh
    ├── session-start-check.sh
    └── task-context-check.sh
```

---

## 7. Files Changed in This Audit

| File | Change |
|---|---|
| `.cursor/rules/aria-rule-22.mdc` | + YAML frontmatter (`description`, `globs`, `alwaysApply: true`) |
| `.cursor/rules/aria-core.mdc` | + YAML frontmatter (`alwaysApply: true`) |
| `.cursor/rules/aria-context.mdc` | + YAML frontmatter; preamble line mentions `/context` + `/rules` |
| `.cursor/rules/aria-audit.mdc` | + YAML frontmatter; preamble mentions `/knowledge-audit` and `/config-audit` aliases |
| `.cursor/rules/aria-commands.mdc` | + YAML frontmatter; preamble mentions `/share-audit` alias; appended `/help` and `/audit-share` SKILL sections |
| `AGENTS.md` | Command table expanded to all 22 canonical commands + 3 aliases (was 15) |
| `QUICKSTART.md` | **NEW** — Cursor-adapted quickstart mirroring upstream `965d69a` |

No scripts modified — all 13 `scripts/aria/*.sh` already pass `bash -n` and smoke tests.
No knowledge folder schema changes.
No config schema changes.

---

## 8. Shippable / Source Zip Recommendation

A regenerated zip would be useful if the audited port is the artifact users install. Recommend rebuilding both `aria-knowledge-cursor-2.16.1-shippable.zip` and `aria-knowledge-cursor-2.16.1-source.zip` with the audit fixes applied. Existing zips in `/home/user/workspace/` predate the frontmatter + skill fixes.

Stage path used previously (per workspace contents): `/home/user/workspace/_aria_zip_stage/`. Same script can be re-run on the updated tree.
