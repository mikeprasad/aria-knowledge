# Subagent Knowledge Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture knowledge from subagent execution that `/extract` currently misses — archive heavyweight subagent transcripts on `SubagentStop`, and inject a self-report instruction into routine subagents on `SubagentStart` — under ARIA's capture→govern→promote model.

**Architecture:** Two new bash hook scripts in `plugin-claude-code/bin/`, both sourcing the existing `config.sh`. A-side (`SubagentStop`) copies the subagent transcript into a new sticky-retention `intake/subagent-captures/` folder, gated to configured heavyweight `agent_type`s. B-side (`SubagentStart`) emits `additionalContext` with a self-report instruction, gated to routine `agent_type`s. Three additive config keys control both. `/audit-knowledge`, `/extract`, and `/setup` learn about the new folder. The B-side ships only after an empirical validation gate (V1) confirms `SubagentStart` injects into the subagent.

**Tech Stack:** POSIX sh (hook scripts), Claude Code hooks (`SubagentStart`/`SubagentStop`), markdown skill definitions, `~/.claude/aria-knowledge.local.md` config.

**Spec:** `aria/aria-knowledge/docs/superpowers/specs/2026-05-31-subagent-knowledge-capture-design.md`
**Prospect:** `~/Projects/knowledge/logs/prospect/2026-05-31-file-subagent-knowledge-capture.md` (verdict: PROCEED-WITH-CHANGES)

**Verification note:** These are hook scripts, not unit-testable modules. Each code task's "test" is a fixture-driven run: pipe a crafted stdin JSON payload (the shape Claude Code sends) to the script and assert the side-effect. All paths are relative to the repo root `aria/aria-knowledge/` unless absolute.

**Ship units (from prospect §Implementation sequencing):**
- **Phase 0** — Validation V1 (run first; gates Phase 2).
- **Phase 1** — A-side. No blockers; fully shippable on its own.
- **Phase 2** — B-side. Ships only on a V1 pass; else descope to dispatch-convention.

---

## Phase 0 — Validation Gate V1

### Task 1: V1 — confirm SubagentStart/SubagentStop fire, capture real `agent_type` strings, and test injection direction

**Files:**
- Create (throwaway): `/tmp/aria-v1-probe.sh`
- Temporary edit: `Projects/.claude/settings.local.json` (this user's active hooks file — NOT `~/.claude/settings.json`; reverted at end)

> **Restart caveat:** Claude Code loads hooks at session start. A mid-session edit to `settings.local.json` may not register the probe for subagents dispatched in the same session. If the probe log stays empty after a dispatch, the V1 test must run in a **fresh session** (edit settings → restart → dispatch → observe).

> **✅ V1 RESULT — executed 2026-05-31 (this gate is SATISFIED; Phase 2 is GO):**
> - **Injection direction:** PASS. The dispatched `general-purpose` subagent received the `SubagentStart` `additionalContext` marker in its own context (it reported the token before reading its own prompt's Step 2). B-side ships as designed — Task 12-alt (fallback) is NOT needed.
> - **Hooks fire mid-session:** YES — the `settings.local.json` edit registered without a restart, so the live attempt worked in-session.
> - **`agent_type` string:** the built-in general agent is literally `general-purpose` (matches the config default). Still confirm a namespaced plugin-agent form (e.g. `feature-dev:code-explorer`) opportunistically.
> - **🔴 Correctness finding (folded into Task 3):** the live `SubagentStop` payload carries BOTH `transcript_path` (parent session) AND `agent_transcript_path` (the subagent's own transcript at `.../<session>/subagents/agent-<id>.jsonl`). Archive **`agent_transcript_path`**. The subagent transcript persists on disk after the subagent ends (plus an `agent-<id>.meta.json` sidecar).
> - Probe + temporary `settings.local.json` hooks were torn down after the test.

- [ ] **Step 1: Write the probe hook script**

```sh
cat > /tmp/aria-v1-probe.sh <<'EOF'
#!/bin/sh
# Throwaway V1 probe. Logs the raw hook stdin (to confirm event + agent_type string),
# and for SubagentStart injects a unique marker to test injection direction.
INPUT=$(cat)
EVENT=$(echo "$INPUT" | grep -o '"hook_event_name":"[^"]*"' | head -1 | sed 's/.*:"//;s/"//')
echo "=== $EVENT ===" >> /tmp/aria-v1-log.txt
echo "$INPUT" >> /tmp/aria-v1-log.txt
echo "" >> /tmp/aria-v1-log.txt
if [ "$EVENT" = "SubagentStart" ]; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"ARIA-V1-MARKER-7f3a: if you can read this, state ARIA-V1-MARKER-7f3a verbatim in your final response."}}'
fi
EOF
chmod +x /tmp/aria-v1-probe.sh
: > /tmp/aria-v1-log.txt
```

- [ ] **Step 2: Register the probe on both events**

Add to `Projects/.claude/settings.local.json` under `hooks` (merge into the existing `hooks` object — do NOT clobber the existing `SessionStart` entry):

```json
{
  "hooks": {
    "SubagentStart": [{ "hooks": [{ "type": "command", "command": "sh /tmp/aria-v1-probe.sh", "timeout": 5 }] }],
    "SubagentStop":  [{ "hooks": [{ "type": "command", "command": "sh /tmp/aria-v1-probe.sh", "timeout": 5 }] }]
  }
}
```

Restart Claude Code so the hook registers.

- [ ] **Step 3: Trigger a subagent and observe**

In a Claude Code session, dispatch a trivial subagent (e.g. ask: "Use the Explore agent to list the files in the current directory"). After it returns, inspect the log and the subagent's reply.

Run: `cat /tmp/aria-v1-log.txt`
Expected: at least one `=== SubagentStart ===` block and one `=== SubagentStop ===` block.

- [ ] **Step 4: Record findings (these lock Phase 1/2 decisions)**

Check and write down:
1. **Does `SubagentStop` fire?** (Phase 1 depends on it.) — look for the block.
2. **The exact `agent_type` string** for a plugin agent (e.g. is it `Explore`? `feature-dev:code-explorer`? `code-explorer`?). Run: `grep -o '"agent_type":"[^"]*"' /tmp/aria-v1-log.txt | sort -u` — **this finalizes the config defaults in Task 2.**
3. **Is `transcript_path` present and a real file** in the `SubagentStop` block? Run: `grep -o '"transcript_path":"[^"]*"' /tmp/aria-v1-log.txt | head -1`.
4. **Injection direction (gates Phase 2):** did the **subagent** echo `ARIA-V1-MARKER-7f3a` in its final response? PASS = subagent saw it → build Phase 2 as designed. FAIL = only the parent saw it (or nobody) → descope Phase 2 to the dispatch-convention fallback (Task 12 alt).

- [ ] **Step 5: Tear down the probe**

Remove the two probe hook entries from `~/.claude/settings.json`, then:

```bash
rm -f /tmp/aria-v1-probe.sh /tmp/aria-v1-log.txt
```

Restart Claude Code. **Do not commit anything in this task** — it is pure validation.

---

## Phase 1 — A-side (archive heavyweight subagent transcripts)

### Task 2: Add the 3 config keys to `config.sh`

**Files:**
- Modify: `plugin-claude-code/bin/config.sh` (insert after line 38, the `KT_LAST_SETUP_VERSION` parse; add defaults near line 55)

> Use the exact `agent_type` strings recorded in Task 1 Step 4.2 for the capture/self-report defaults. The values below are the spec defaults; adjust if V1 showed a different namespaced form.

- [ ] **Step 1: Add the three field parses**

Insert immediately after the `KT_LAST_SETUP_VERSION=...` line (line 38):

```sh
  KT_SUBAGENT_CAPTURE=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^subagent_capture:' | sed 's/^subagent_capture: *//')
  KT_SUBAGENT_CAPTURE_TYPES=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^subagent_capture_types:' | sed 's/^subagent_capture_types: *//')
  KT_SUBAGENT_SELFREPORT_TYPES=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^subagent_selfreport_types:' | sed 's/^subagent_selfreport_types: *//')
```

- [ ] **Step 2: Add defaults + normalization**

Insert in the "Defaults if not set" block (after line 55, the `KT_STITCH_STALENESS_DAYS` default):

```sh
  KT_SUBAGENT_CAPTURE=${KT_SUBAGENT_CAPTURE:-true}
  KT_SUBAGENT_CAPTURE_TYPES=${KT_SUBAGENT_CAPTURE_TYPES:-general-purpose,Plan,feature-dev:code-architect,feature-dev:code-explorer,feature-dev:code-reviewer}
  KT_SUBAGENT_SELFREPORT_TYPES=${KT_SUBAGENT_SELFREPORT_TYPES:-Explore}
  # Strip spaces so comma-list membership tests are exact
  KT_SUBAGENT_CAPTURE_TYPES=$(printf '%s' "$KT_SUBAGENT_CAPTURE_TYPES" | tr -d ' ')
  KT_SUBAGENT_SELFREPORT_TYPES=$(printf '%s' "$KT_SUBAGENT_SELFREPORT_TYPES" | tr -d ' ')
```

- [ ] **Step 3: Add boolean validation for the toggle**

Insert after the `KT_AUTO_CAPTURE` `case` block (after line 92):

```sh
  case "$KT_SUBAGENT_CAPTURE" in
    true|false) ;; # valid
    *) KT_SUBAGENT_CAPTURE=true ;;
  esac
```

- [ ] **Step 4: Verify config parses without error**

Run:
```bash
sh -c '. plugin-claude-code/bin/config.sh; echo "cap=$KT_SUBAGENT_CAPTURE types=[$KT_SUBAGENT_CAPTURE_TYPES] self=[$KT_SUBAGENT_SELFREPORT_TYPES] err=[$KT_CONFIG_ERROR]"'
```
Expected: `cap=true types=[general-purpose,Plan,feature-dev:code-architect,feature-dev:code-explorer,feature-dev:code-reviewer] self=[Explore] err=[]` (no spaces in the type lists; empty error).

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/bin/config.sh
git commit -m "feat: add subagent_capture config keys (capture toggle + heavyweight/routine type lists)"
```

### Task 3: Create the A-side hook script `subagent-stop-capture.sh`

**Files:**
- Create: `plugin-claude-code/bin/subagent-stop-capture.sh`

- [ ] **Step 1: Write the script**

```sh
#!/bin/sh
# subagent-stop-capture.sh — SubagentStop hook for aria-knowledge
# Archives a heavyweight subagent's transcript before it is lost. Capture only —
# synthesis happens later via /extract or /audit-knowledge, because a subagent
# cannot reliably self-extract (it is already done when this hook fires).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# Guards — exit 0 silently (SubagentStop supports no additionalContext; a bare
# exit is the correct no-op).
[ "$KT_CONFIGURED" = "false" ] && exit 0
[ -n "$KT_CONFIG_ERROR" ] && exit 0
[ ! -d "$KT_KNOWLEDGE_FOLDER" ] && exit 0
[ "$KT_AUTO_CAPTURE" = "false" ] && exit 0
[ "$KT_SUBAGENT_CAPTURE" = "false" ] && exit 0

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | grep -o '"agent_type":"[^"]*"' | head -1 | sed 's/"agent_type":"//;s/"//')

# Gate: only archive configured heavyweight types. Comma-wrapped membership test.
case ",$KT_SUBAGENT_CAPTURE_TYPES," in
  *",$AGENT_TYPE,"*) : ;;   # matched — continue
  *) exit 0 ;;              # not a capture type
esac

SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
AGENT_ID=$(echo "$INPUT" | grep -o '"agent_id":"[^"]*"' | head -1 | sed 's/"agent_id":"//;s/"//')
# IMPORTANT: archive the SUBAGENT's transcript (agent_transcript_path), NOT the parent
# session's (transcript_path). Verified against a live SubagentStop payload 2026-05-31.
# The grep anchors on the leading quote so "agent_transcript_path" and "transcript_path"
# do not collide.
TRANSCRIPT_PATH=$(echo "$INPUT" | grep -o '"agent_transcript_path":"[^"]*"' | head -1 | sed 's/"agent_transcript_path":"//;s/"//')

CAPTURES_DIR="$KT_KNOWLEDGE_FOLDER/intake/subagent-captures"
mkdir -p "$CAPTURES_DIR" 2>/dev/null

# Copy transcript if it exists and is readable. Sticky retention: this body is
# preserved until /extract or /audit-knowledge processes it (no ledger-clear here).
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
  TODAY=$(date +%Y-%m-%d)
  SESSION_SHORT=$(echo "$SESSION_ID" | cut -c1-8)
  AGENT_SHORT=$(echo "$AGENT_ID" | cut -c1-8)
  AGENT_TYPE_SAFE=$(printf '%s' "$AGENT_TYPE" | sed 's/[^A-Za-z0-9._-]/-/g')
  SNAPSHOT_FILE="$CAPTURES_DIR/${TODAY}_${SESSION_SHORT}_${AGENT_TYPE_SAFE}_${AGENT_SHORT}.md"
  cp "$TRANSCRIPT_PATH" "$SNAPSHOT_FILE" 2>/dev/null
fi
exit 0
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x plugin-claude-code/bin/subagent-stop-capture.sh`

- [ ] **Step 3: Fixture test — a heavyweight type IS captured**

```bash
TF=$(mktemp /tmp/aria-fake-transcript.XXXX.jsonl); echo '{"x":1}' > "$TF"
printf '{"hook_event_name":"SubagentStop","session_id":"abcd1234-aaaa","agent_id":"ef567890-bbbb","agent_type":"general-purpose","agent_transcript_path":"%s"}' "$TF" \
  | sh plugin-claude-code/bin/subagent-stop-capture.sh
ls -1 "$HOME/Projects/knowledge/intake/subagent-captures/" | grep general-purpose
```
Expected: a file like `2026-05-31_abcd1234_general-purpose_ef567890.md` is listed.

- [ ] **Step 4: Fixture test — a non-listed type is NOT captured**

```bash
BEFORE=$(ls -1 "$HOME/Projects/knowledge/intake/subagent-captures/" 2>/dev/null | wc -l)
printf '{"hook_event_name":"SubagentStop","session_id":"abcd1234-aaaa","agent_id":"ef567890-cccc","agent_type":"Explore","agent_transcript_path":"%s"}' "$TF" \
  | sh plugin-claude-code/bin/subagent-stop-capture.sh
AFTER=$(ls -1 "$HOME/Projects/knowledge/intake/subagent-captures/" 2>/dev/null | wc -l)
[ "$BEFORE" = "$AFTER" ] && echo "PASS: Explore not captured" || echo "FAIL"
```
Expected: `PASS: Explore not captured`.

- [ ] **Step 5: Clean up fixtures**

```bash
rm -f "$TF" "$HOME/Projects/knowledge/intake/subagent-captures/2026-"*_abcd1234_general-purpose_*.md
```

- [ ] **Step 6: Commit**

```bash
git add plugin-claude-code/bin/subagent-stop-capture.sh
git commit -m "feat: add SubagentStop archive hook for heavyweight subagent transcripts"
```

### Task 4: Register `SubagentStop` in `plugin.json` + version bump

**Files:**
- Modify: `plugin-claude-code/.claude-plugin/plugin.json` (add a `SubagentStop` entry to `hooks`; bump `version`)

- [ ] **Step 1: Add the hook registration**

In the `hooks` object, add a sibling key after the `TaskCreated` block:

```json
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/bin/subagent-stop-capture.sh",
            "timeout": 10
          }
        ]
      }
    ]
```

- [ ] **Step 2: Bump the version**

Change `"version": "2.20.4"` to `"version": "2.21.0"` (new feature → minor bump).

- [ ] **Step 3: Verify JSON is valid**

Run: `jq empty plugin-claude-code/.claude-plugin/plugin.json && echo "valid JSON"`
Expected: `valid JSON`

- [ ] **Step 4: Verify the hook is registered**

Run: `jq '.hooks.SubagentStop' plugin-claude-code/.claude-plugin/plugin.json`
Expected: the array with the `subagent-stop-capture.sh` command.

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/.claude-plugin/plugin.json
git commit -m "feat: register SubagentStop hook; bump to v2.21.0"
```

### Task 5: Ship the template folder

**Files:**
- Create: `plugin-claude-code/template/intake/subagent-captures/.gitkeep`

- [ ] **Step 1: Create the folder + .gitkeep**

```bash
mkdir -p plugin-claude-code/template/intake/subagent-captures
: > plugin-claude-code/template/intake/subagent-captures/.gitkeep
```

- [ ] **Step 2: Verify it sits alongside the existing capture folder**

Run: `ls -1 plugin-claude-code/template/intake/ | grep captures`
Expected: both `pre-compact-captures` and `subagent-captures` are listed.

- [ ] **Step 3: Commit**

```bash
git add plugin-claude-code/template/intake/subagent-captures/.gitkeep
git commit -m "feat: add subagent-captures template intake folder"
```

### Task 6: Teach `/setup` to create/repair the folder

**Files:**
- Modify: `plugin-claude-code/skills/setup/SKILL.md` (the plugin-managed folder list / folder-repair step)

- [ ] **Step 1: Find the folder list**

Run: `grep -n "pre-compact-captures" plugin-claude-code/skills/setup/SKILL.md`
This locates the section that enumerates the `intake/` subfolders setup creates.

- [ ] **Step 2: Add `subagent-captures/` next to `pre-compact-captures/`**

Wherever `intake/pre-compact-captures/` is listed as a folder to create/repair (with `.gitkeep`), add a sibling line for `intake/subagent-captures/` using the identical wording/format. If the list is a code block of `mkdir`/path lines, add `intake/subagent-captures/` in the same style and alphabetical position.

- [ ] **Step 3: Verify**

Run: `grep -n "subagent-captures" plugin-claude-code/skills/setup/SKILL.md`
Expected: at least one line in the folder-creation/repair section.

- [ ] **Step 4: Commit**

```bash
git add plugin-claude-code/skills/setup/SKILL.md
git commit -m "feat: /setup creates and repairs intake/subagent-captures/"
```

### Task 7: Add the `/audit-knowledge` subagent-captures review step

**Files:**
- Modify: `plugin-claude-code/skills/audit-knowledge/SKILL.md` (new step after Step 2d "Review Pre-Compact Captures"; new REMOVED.md ledger path; add to the §Output-policy conditional list)

- [ ] **Step 1: Locate the end of Step 2d**

Run: `grep -n "Step 2d\|Step 3:\|Pre-Compact Captures" plugin-claude-code/skills/audit-knowledge/SKILL.md`
Identify where Step 2d ends and Step 3 begins.

- [ ] **Step 2: Insert a new "Step 2e: Review Subagent Captures" section**

Insert between the end of Step 2d and Step 3. Use this content (mirrors 2d's structure, reuses `digest-transcript.sh`, but **sticky retention → no bare-Clear option**):

```markdown
## Step 2e: Review Subagent Captures

Scan `{knowledge_folder}/intake/subagent-captures/` for `.md` files. **If the directory doesn't exist or is empty**, skip silently to Step 3.

**If captures exist**, report the count and total size, then ask the user:

> "Found N subagent transcript capture(s) (total ~X KB) from heavyweight subagents. A subagent cannot extract its own session, so these are held until reviewed. Options:"
> 1. **Digest** — extract high-signal content via script, then review (default)
> 2. **Detailed** — read full transcripts for exhaustive review
> 3. **Skip** — leave for the next audit

There is **no bare-Clear option** for subagent captures: unlike pre-compact snapshots, they are sticky-until-extracted (their source subagent transcript is not assumed to persist), so a body is only removed *after* its knowledge is folded into a backlog.

**Digest mode (default):** for each capture, run:
```
bash ${CLAUDE_PLUGIN_ROOT}/bin/digest-transcript.sh "{capture_path}" "/tmp/aria-digest-{filename}"
```
Then read the digest. Extract insights/decisions/feedback/references per the standard six-bucket categorization.

For each reviewed capture:
- **Approved items** → append to the appropriate backlog (insights-backlog.md / decisions-backlog.md / extraction-backlog.md), then ledger-clear the capture: create `{knowledge_folder}/archive/audit-{date}/subagent-captures/` if needed, append an entry to its `REMOVED.md` (filename + parent-session-id + agent_type + agent_id + capture-timestamp), then `rm` the capture `.md`.
- **Rejected items** → ledger-clear with `disposition: rejected` + a one-line reason.
- **Skip** → leave the capture for the next audit.

Note findings for presentation in Step 6 under a "Subagent Captures" section.
```

- [ ] **Step 3: Add to the Output-policy conditional-omission list**

Run: `grep -n "Pre-Compact Captures, Codemap Staleness" plugin-claude-code/skills/audit-knowledge/SKILL.md`
In that "Output policy" sentence, add "Subagent Captures" to the list of subsections that omit when the feature doesn't apply (so an empty folder produces no noise).

- [ ] **Step 4: Add the Step 6 report subsection**

Run: `grep -n "### Pre-Compact Captures (from intake/pre-compact-captures/)" plugin-claude-code/skills/audit-knowledge/SKILL.md`
Immediately after that subsection, add a parallel one:

```markdown
### Subagent Captures (from intake/subagent-captures/)
```
with the same zero-state convention as Pre-Compact Captures (emit a zero-count line only when the folder exists).

- [ ] **Step 5: Verify**

Run: `grep -n "Step 2e\|Subagent Captures" plugin-claude-code/skills/audit-knowledge/SKILL.md`
Expected: the new step + the two subsection references.

- [ ] **Step 6: Commit**

```bash
git add plugin-claude-code/skills/audit-knowledge/SKILL.md
git commit -m "feat: /audit-knowledge reviews intake/subagent-captures/ with sticky retention"
```

### Task 8: Add the `/extract` sweep-all pickup

**Files:**
- Modify: `plugin-claude-code/skills/extract/SKILL.md` (add a step that folds pending subagent captures into the same six-bucket synthesis)

- [ ] **Step 1: Locate the categorization step**

Run: `grep -n "six buckets\|categorize findings\|## " plugin-claude-code/skills/extract/SKILL.md`
Find where `/extract` enumerates its synthesis buckets and writes to the backlogs.

- [ ] **Step 2: Insert a "Subagent capture sweep" step**

Add a step (before the final backlog-write step) with this content:

```markdown
## Subagent capture sweep (pending captures from heavyweight subagents)

Scan `{knowledge_folder}/intake/subagent-captures/` for **all** pending `.md` captures. If the folder is absent or empty, skip silently.

> **Why sweep all (not just this session):** a skill does not receive the runtime `session_id`, so it cannot match captures to "the current session" by the `{parent-session-8}` filename token. Captures are sticky and governed regardless of origin, so sweeping all pending ones is safe — nothing is double-processed because each folded-in capture is ledger-cleared.

For each capture, run the digest for cheap review:
```
bash ${CLAUDE_PLUGIN_ROOT}/bin/digest-transcript.sh "{capture_path}" "/tmp/aria-digest-{filename}"
```
Fold any insights/decisions/feedback/references into the SAME six-bucket synthesis as the main conversation. After an item is captured into a backlog, ledger-clear that capture: append to `{knowledge_folder}/archive/extract-{date}/subagent-captures/REMOVED.md` (filename + parent-session-id + agent_type + agent_id) and `rm` the capture `.md`. Leave captures you did not process for `/audit-knowledge`.
```

- [ ] **Step 3: Verify**

Run: `grep -n "subagent-captures\|Subagent capture sweep" plugin-claude-code/skills/extract/SKILL.md`
Expected: the new step.

- [ ] **Step 4: Commit**

```bash
git add plugin-claude-code/skills/extract/SKILL.md
git commit -m "feat: /extract sweeps and folds pending subagent captures (sweep-all, ledger-clear processed)"
```

### Task 9: Document the config keys + changelog (A-side)

**Files:**
- Modify: `plugin-claude-code/CONFIG.md` (document 3 keys)
- Modify: `CHANGELOG.md` (v2.21.0 entry)

- [ ] **Step 1: Document the keys in CONFIG.md**

Run: `grep -n "auto_capture" plugin-claude-code/CONFIG.md`
After the `auto_capture` documentation, add entries for the three new keys, matching the existing field-doc format:

```markdown
### `subagent_capture`
`true` | `false` (default `true`). Master toggle for subagent knowledge capture. Also gated by `auto_capture` — both must be `true` for the SubagentStop/SubagentStart hooks to act.

### `subagent_capture_types`
Comma-separated `agent_type` names whose transcripts are **archived** on `SubagentStop` (the "heavyweight" set). Default: `general-purpose, Plan, feature-dev:code-architect, feature-dev:code-explorer, feature-dev:code-reviewer`. Matched case-sensitively against the hook's `agent_type` field (spaces are ignored). Captures land in `intake/subagent-captures/` and are held until `/extract` or `/audit-knowledge` reviews them.

### `subagent_selfreport_types`
Comma-separated `agent_type` names that receive a **self-report instruction** on `SubagentStart` (the "routine" set) so their findings return in their final message. Default: `Explore`.
```

- [ ] **Step 2: Add the CHANGELOG entry**

Run: `head -20 CHANGELOG.md`
Add a new top entry:

```markdown
## v2.21.0

### Added
- **Subagent knowledge capture.** New `SubagentStop` hook archives heavyweight subagent transcripts to a new sticky-retention `intake/subagent-captures/` folder (gated by `subagent_capture_types`); `/audit-knowledge` and `/extract` review and fold them in. New config keys: `subagent_capture`, `subagent_capture_types`, `subagent_selfreport_types`. (B-side `SubagentStart` self-report ships separately pending validation — see plan.)
```

- [ ] **Step 3: Verify**

Run: `grep -n "subagent_capture" plugin-claude-code/CONFIG.md && grep -n "v2.21.0" CHANGELOG.md`
Expected: matches in both.

- [ ] **Step 4: Commit**

```bash
git add plugin-claude-code/CONFIG.md CHANGELOG.md
git commit -m "docs: document subagent capture config keys + v2.21.0 changelog"
```

---

## Phase 2 — B-side (self-report for routine subagents) — GATED ON V1 PASS

> **Gate:** Only execute Tasks 10–11 if Task 1 Step 4.4 recorded a PASS (the subagent saw the injected marker). If FAIL, skip to Task 12 (alt) for the dispatch-convention fallback.

### Task 10: Create the B-side hook script `subagent-start-selfreport.sh`

**Files:**
- Create: `plugin-claude-code/bin/subagent-start-selfreport.sh`

- [ ] **Step 1: Write the script**

```sh
#!/bin/sh
# subagent-start-selfreport.sh — SubagentStart hook for aria-knowledge
# Injects a self-report instruction into routine subagents so their durable
# findings ride back in the return message for the parent's /extract.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

[ "$KT_CONFIGURED" = "false" ] && exit 0
[ -n "$KT_CONFIG_ERROR" ] && exit 0
[ ! -d "$KT_KNOWLEDGE_FOLDER" ] && exit 0
[ "$KT_AUTO_CAPTURE" = "false" ] && exit 0
[ "$KT_SUBAGENT_CAPTURE" = "false" ] && exit 0

INPUT=$(cat)
AGENT_TYPE=$(echo "$INPUT" | grep -o '"agent_type":"[^"]*"' | head -1 | sed 's/"agent_type":"//;s/"//')

# Gate: only inject into configured routine types.
case ",$KT_SUBAGENT_SELFREPORT_TYPES," in
  *",$AGENT_TYPE,"*) : ;;
  *) exit 0 ;;
esac

MSG=$(kt_json_escape "Before you return, briefly surface any durable findings worth persisting — non-obvious discoveries, dead-ends you ruled out (and why), and decisions you made. Put them in your final message so they aren't lost when this subagent ends.")
printf '%s' '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"'"$MSG"'"}}'
exit 0
```

- [ ] **Step 2: Make executable**

Run: `chmod +x plugin-claude-code/bin/subagent-start-selfreport.sh`

- [ ] **Step 3: Fixture test — routine type gets injection**

```bash
printf '{"hook_event_name":"SubagentStart","agent_type":"Explore"}' \
  | sh plugin-claude-code/bin/subagent-start-selfreport.sh | jq -e '.hookSpecificOutput.additionalContext | test("durable findings")' && echo "PASS: Explore injected"
```
Expected: `true` then `PASS: Explore injected`.

- [ ] **Step 4: Fixture test — heavyweight type gets NO injection**

```bash
OUT=$(printf '{"hook_event_name":"SubagentStart","agent_type":"general-purpose"}' | sh plugin-claude-code/bin/subagent-start-selfreport.sh)
[ -z "$OUT" ] && echo "PASS: general-purpose not injected" || echo "FAIL: $OUT"
```
Expected: `PASS: general-purpose not injected`.

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/bin/subagent-start-selfreport.sh
git commit -m "feat: add SubagentStart self-report hook for routine subagents"
```

### Task 11: Register `SubagentStart` in `plugin.json`

**Files:**
- Modify: `plugin-claude-code/.claude-plugin/plugin.json`

- [ ] **Step 1: Add the hook registration**

In the `hooks` object, add:

```json
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/bin/subagent-start-selfreport.sh",
            "timeout": 10
          }
        ]
      }
    ]
```

- [ ] **Step 2: Verify JSON validity + registration**

Run: `jq -e '.hooks.SubagentStart[0].hooks[0].command | test("subagent-start-selfreport")' plugin-claude-code/.claude-plugin/plugin.json`
Expected: `true`

- [ ] **Step 3: End-to-end check**

Restart Claude Code; dispatch an `Explore` subagent; confirm it self-reports durable findings in its return message.

- [ ] **Step 4: Commit**

```bash
git add plugin-claude-code/.claude-plugin/plugin.json
git commit -m "feat: register SubagentStart self-report hook"
```

### Task 12: B-side docs (CHANGELOG)

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Extend the v2.21.0 Added note**

Append to the v2.21.0 `### Added` block:

```markdown
- **SubagentStart self-report.** Routine subagents (`subagent_selfreport_types`, default `Explore`) receive an injected instruction to surface durable findings in their return message, so the parent's `/extract` captures them. Validated to inject into the subagent context (see plan Task 1 V1).
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog note for SubagentStart self-report"
```

### Task 12 (alt): B-side FALLBACK — dispatch convention (only if V1 FAILED)

> Execute this **instead of** Tasks 10–12 if Task 1 Step 4.4 recorded a FAIL (injection did not reach the subagent).

**Files:**
- Modify: `plugin-claude-code/CLAUDE.md` (or the project's orchestration guidance doc) + `CHANGELOG.md`

- [ ] **Step 1: Document the dispatch convention**

Add guidance that when dispatching a routine search/explore subagent, the orchestrator includes in the prompt: "Before returning, surface any durable findings (non-obvious discoveries, dead-ends, decisions) in your final message." Note that hook-based injection was tested (V1) and does not reach subagents, so this is convention-based.

- [ ] **Step 2: Changelog the descope**

Add a v2.21.0 note that the B-side ships as a documented dispatch convention rather than a hook, with the V1 finding as rationale.

- [ ] **Step 3: Commit**

```bash
git add plugin-claude-code/CLAUDE.md CHANGELOG.md
git commit -m "docs: B-side self-report as dispatch convention (V1 showed SubagentStart injects to parent, not subagent)"
```

---

## Final verification (after all executed tasks)

- [ ] `jq empty plugin-claude-code/.claude-plugin/plugin.json` passes.
- [ ] `sh -c '. plugin-claude-code/bin/config.sh; echo $KT_CONFIG_ERROR'` prints empty.
- [ ] A real heavyweight subagent run (live session) produces a file in `~/Projects/knowledge/intake/subagent-captures/`.
- [ ] A real `Explore` run produces NO capture file (and, if Phase 2 shipped, self-reports findings).
- [ ] `/audit-knowledge` lists pending subagent captures and offers Digest/Detailed/Skip (no bare-Clear).
- [ ] All template/skill/config/doc changes committed; version is `2.21.0`.
- [ ] Per Mike's cadence: commits are local — **do not push** unless Mike asks.

## Future ports (out of scope here)

Once proven on `plugin-claude-code`, port to codex / cursor / antigravity per the canonical-first workflow, verifying each runtime actually fires `SubagentStart` / `SubagentStop` (support is not assumed). Also: separately verify whether the existing `TaskCreated` `additionalContext` in `task-context-check.sh` is a live injection or a silent no-op (docs list `TaskCreated` as not supporting `additionalContext`).
