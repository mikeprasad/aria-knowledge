# Antigravity Port (Full) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port ARIA Knowledge v2.19.2 to Google Antigravity 2.0 (IDE + CLI) with full Rule 22 per-edit enforcement, by writing against the verified primary-source plugin contract from `antigravity.google/docs/{plugins,hooks,mcp,skills,rules-workflows}`.

**Architecture:** Reuse ARIA's canonical bash hook scripts unchanged. Insert a thin per-hook wrapper layer that translates Antigravity's stdin-JSON I/O contract (`workspacePaths`, `transcriptPath`, `toolCall.name`, `toolCall.args`) into the env-var shape the canonical scripts expect. Move all one-time session-lifecycle behaviors (audit cadence, transcript snapshot, knowledge surface) into `GEMINI.md` (loaded once per session by Antigravity) or into user-invoked skills (`/snapshot`, `/setup`). Use only 4 hook entries — the per-turn events Antigravity supports — never substitute one-time logic into a per-turn hook.

**Tech Stack:** Bash, `jq` for JSON parsing, `bats` for shell-script testing, Antigravity 2.0 plugin contract (flat layout, named hooks, stdin-JSON I/O).

---

## Context — Why This Rewrite

The prior draft port at `plugin-antigravity/` was built on three incorrect assumptions about the Antigravity contract that propagated into a wrong layout, wrong manifest schema, wrong hook event names, and wrong tool matchers. Primary-source verification on 2026-05-24 against `antigravity.google/docs/*` (clipped to `~/Projects/knowledge/intake/clippings/Google Antigravity Documentation{,1-4}.md`) established the correct contract. See `docs/ARIA Knowledge v2.19.2 — Antigravity Port Guide (Verified).md` for the full design rationale and the eight key corrections vs. the prior draft.

The prior draft is preserved as archival evidence (Task 1) but its files are not the basis for this port. This plan rebuilds against the verified contract.

## Disposition: Per-Turn vs. One-Time Lifecycle

The single most important architecture decision. Mike's constraint: **per-turn hooks for per-turn purposes only; never substitute one-time session-lifecycle work into a per-turn hook**.

| Canonical ARIA hook | Per-turn? | Antigravity placement |
|---|---|---|
| `SessionStart` (audit cadence check, batch cleanup, /context surface) | ❌ One-time per session | **`GEMINI.md` text** — Antigravity loads global rules once per session by design |
| `PreToolUse(Edit\|Write)` (Rule 22 marker scan) | ✅ Every edit | **`PreToolUse` matcher `write_to_file\|replace_file_content\|multi_replace_file_content`** |
| `PreToolUse(Glob\|Grep)` (CODEMAP first-read reminder) | ✅ Every search | **`PreToolUse` matcher `grep_search\|find_by_name`** |
| `PreToolUse(Bash)` (path knowledge on `cd`) | ✅ Every shell command | **`PreToolUse` matcher `run_command`** |
| `PostToolUse(Edit\|Write)` (scope-check output) | ✅ Every edit | **`PostToolUse` matcher `write_to_file\|replace_file_content\|multi_replace_file_content`** |
| `PreCompact` (transcript snapshot) | ❌ One-time per session boundary | **`/snapshot` skill** (manual, on-demand) — Antigravity exposes `transcriptPath` in every hook stdin payload |
| `PostCompact` (session ledger re-emission) | ❌ One-time per session | **`GEMINI.md` text** mentioning the session-ledger convention |
| `TaskCreated` (surface knowledge files on subagent dispatch) | ❌ Not strictly per-turn; subagent dispatch is a skill-level concern | **Skills that dispatch subagents** (`/distill`, `/codemap`) read CODEMAP/STITCH inline; no hook needed |

Antigravity's other supported events (`PreInvocation`, `PostInvocation`, `Stop`) fire on every model call / every turn end — too frequent for any one-time-session-lifecycle purpose. **Do not register any of them in this port.**

## Locked Decisions

- **D1: Wrapper architecture.** Each hook entry in `hooks.json` calls a thin wrapper at `bin/antigravity/<hook-name>.sh`. The wrapper sources a shared `lib-antigravity-input.sh` that parses stdin JSON into env vars matching what the canonical scripts expect, then `exec`s the canonical script at `../plugin-claude-code/bin/<script>.sh`. The wrapper translates the canonical script's exit code (0 → allow, non-zero → deny) plus its stderr into the Antigravity stdout JSON shape (`{"decision": "allow"|"deny", "reason": "..."}`). This keeps the canonical scripts unchanged — one source of truth across Claude Code, Codex, and Antigravity ports.
- **D2: 4 hook entries.** Three `PreToolUse` entries with different matchers, one `PostToolUse`. No `PreInvocation`, `PostInvocation`, or `Stop` hooks.
- **D3: One-time logic lives in `GEMINI.md`** at the plugin root. Antigravity reads global rules from `~/.gemini/GEMINI.md` once per session; per-plugin GEMINI.md content gets surfaced via the plugin install path.
- **D4: PreCompact / PostCompact retired.** `/snapshot` skill becomes the user-invoked equivalent; it reads `transcriptPath` from any hook stdin payload when invoked.
- **D5: TaskCreated retired.** Skills that dispatch subagents already load context inline; no per-task hook needed.
- **D6: Archive the prior draft.** Move `plugin-antigravity/` → `plugin-antigravity.archive-2026-05-24-draft/`. Rebuild in `plugin-antigravity/`.
- **D7: New canonical bash scripts stay in `plugin-claude-code/bin/`.** The Antigravity wrappers live in `plugin-antigravity/bin/antigravity/`. The wrappers reference the canonical scripts via relative path (`../../plugin-claude-code/bin/<script>.sh`) when running from the source repo, or via the install-time copied path when running from `~/.gemini/config/plugins/aria-knowledge/bin/`.
- **D8: `jq` is a hard dependency** for stdin JSON parsing. Document in README. Antigravity's Linux sandbox has package managers; users without `jq` see a deny-with-reason from the wrapper.

## File Structure

```
plugin-antigravity/                          ← new flat layout
├── plugin.json                              ← {"name": "aria-knowledge"} marker
├── hooks.json                               ← 4 named hook entries
├── mcp_config.json                          ← MCP servers (serverUrl + OAuth)
├── GEMINI.md                                ← Session-lifecycle + ARIA persona + Rule 22 advisory
├── bin/
│   └── antigravity/
│       ├── lib-antigravity-input.sh         ← Shared stdin-JSON → env-var parser
│       ├── pre-edit-aria.sh                 ← Wrapper for PreToolUse(edit-class tools)
│       ├── pre-explore-aria.sh              ← Wrapper for PreToolUse(search-class tools)
│       ├── bash-cd-aria.sh                  ← Wrapper for PreToolUse(run_command)
│       └── post-edit-aria.sh                ← Wrapper for PostToolUse(edit-class tools)
├── skills/                                  ← 30 SKILL.md (copied + path-substituted)
│   ├── setup/SKILL.md
│   ├── extract/SKILL.md
│   └── ... (28 more)
├── template/                                ← Knowledge folder scaffold (copied + path-substituted)
├── tests/
│   ├── test-lib-antigravity-input.bats      ← Bats tests for the shared lib
│   ├── test-pre-edit-aria.bats              ← Bats tests for the pre-edit wrapper
│   ├── test-pre-explore-aria.bats           ← Bats tests for the pre-explore wrapper
│   ├── test-bash-cd-aria.bats               ← Bats tests for the bash-cd wrapper
│   └── test-post-edit-aria.bats             ← Bats tests for the post-edit wrapper
├── build.sh                                 ← Assembly script
├── PORTING.md                               ← Drift log + adaptation notes
├── README.md                                ← Install instructions
└── SMOKE-TEST.md                            ← Manual test plan (Antigravity not in dev env)

plugin-antigravity.archive-2026-05-24-draft/ ← prior draft, archived per Rule 6
└── README.md                                ← explains supersession
```

---

## Task 1: Archive the Prior Draft

**Files:**
- Move: `plugin-antigravity/` → `plugin-antigravity.archive-2026-05-24-draft/`
- Create: `plugin-antigravity.archive-2026-05-24-draft/README.md`

- [ ] **Step 1: Move the directory**

```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
mv plugin-antigravity plugin-antigravity.archive-2026-05-24-draft
```

Note: shell `mv` (not `git mv`) because the prior `plugin-antigravity/` was never committed — it's untracked. `git mv` requires tracked sources and would error out here.

Expected: directory rename succeeds; `git status` shows the new path as untracked.

- [ ] **Step 2: Write the archive README**

Create `plugin-antigravity.archive-2026-05-24-draft/README.md`:

```markdown
# plugin-antigravity (Archived Draft, 2026-05-24)

This directory was a first-draft port of aria-knowledge to Google Antigravity, built on three incorrect assumptions about the Antigravity plugin contract:

1. Plugin manifest location was assumed to be `.agent-plugin/plugin.json` — Antigravity actually uses a flat `plugin.json` at the plugin root.
2. Hook config was assumed to use Claude Code's `{"hooks": {...}}` wrapper with `${CLAUDE_PLUGIN_ROOT}` env var — Antigravity uses named-hook top-level entries with stdin-JSON I/O and no env vars.
3. MCP config was at `.mcp.json` with `"url"` key — Antigravity uses `mcp_config.json` at `~/.gemini/antigravity/` with `"serverUrl"`.

The replacement port lives at `plugin-antigravity/` and is built against the primary-source verified contract from `antigravity.google/docs/*` (clipped 2026-05-24 to `~/Projects/knowledge/intake/clippings/`).

See `docs/superpowers/plans/2026-05-24-antigravity-port-full-implementation.md` for the rewrite plan and `docs/ARIA Knowledge v2.19.2 — Antigravity Port Guide (Verified).md` for the design rationale.

This directory is retained per Rule 6 (don't delete — archive) for forensic value: it documents what the contract was inferred to be before verification, which is useful future context for anyone investigating cross-port architecture decisions.
```

- [ ] **Step 3: Verify the move**

```bash
ls -d plugin-antigravity plugin-antigravity.archive-2026-05-24-draft 2>&1
```

Expected: only `plugin-antigravity.archive-2026-05-24-draft` exists; the old name returns "No such file or directory."

- [ ] **Step 4: Commit**

```bash
git add -A plugin-antigravity.archive-2026-05-24-draft
git commit -m "chore: archive plugin-antigravity draft port

Three architectural assumptions in the draft were wrong vs.
the primary-source Antigravity contract. Archived per Rule 6
for forensic value; rebuild plan at
docs/superpowers/plans/2026-05-24-antigravity-port-full-implementation.md"
```

---

## Task 2: Scaffold the New plugin-antigravity/ Directory

**Files:**
- Create: `plugin-antigravity/` (root)
- Create: `plugin-antigravity/bin/antigravity/` (wrappers)
- Create: `plugin-antigravity/skills/` (will be populated in Task 12)
- Create: `plugin-antigravity/template/` (will be populated in Task 13)
- Create: `plugin-antigravity/tests/` (will be populated in Tasks 4-8)
- Create: `plugin-antigravity/.gitkeep` files as needed for empty dirs

- [ ] **Step 1: Create the directory tree**

```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
mkdir -p plugin-antigravity/bin/antigravity
mkdir -p plugin-antigravity/skills
mkdir -p plugin-antigravity/template
mkdir -p plugin-antigravity/tests
```

- [ ] **Step 2: Verify**

```bash
find plugin-antigravity -type d
```

Expected output:
```
plugin-antigravity
plugin-antigravity/bin
plugin-antigravity/bin/antigravity
plugin-antigravity/skills
plugin-antigravity/template
plugin-antigravity/tests
```

- [ ] **Step 3: Commit (empty scaffold won't have anything to commit yet — proceed to Task 3 first, commit at Task 3)**

---

## Task 3: Write the Minimal plugin.json Marker

**Files:**
- Create: `plugin-antigravity/plugin.json`

- [ ] **Step 1: Write the file**

```json
{
  "name": "aria-knowledge"
}
```

The Antigravity docs (`/docs/plugins`) state: *"Every plugin must have a `plugin.json` file at its root. This file identifies the directory as a plugin."* Schema: optional `name` (defaults to directory name). No other documented fields. ARIA's rich canonical metadata (description, keywords, author, license, version) has no documented home in Antigravity — they're propagated via GEMINI.md instead (Task 11).

- [ ] **Step 2: Validate JSON**

```bash
jq . plugin-antigravity/plugin.json
```

Expected: pretty-printed `{"name": "aria-knowledge"}` with exit code 0.

- [ ] **Step 3: Commit**

```bash
git add plugin-antigravity/
git commit -m "feat(antigravity): scaffold plugin-antigravity with minimal plugin.json

Flat layout per antigravity.google/docs/plugins. plugin.json is
a marker file only; metadata propagates through GEMINI.md."
```

---

## Task 4: Write the lib-antigravity-input.sh Shared JSON Parser

**Files:**
- Create: `plugin-antigravity/bin/antigravity/lib-antigravity-input.sh`
- Test: `plugin-antigravity/tests/test-lib-antigravity-input.bats`

This library reads Antigravity's stdin JSON payload once and exports env vars matching what ARIA's canonical bash scripts expect. Used by every wrapper in Tasks 5–8.

- [ ] **Step 1: Write the failing bats test**

Create `plugin-antigravity/tests/test-lib-antigravity-input.bats`:

```bash
#!/usr/bin/env bats

setup() {
  LIB="${BATS_TEST_DIRNAME}/../bin/antigravity/lib-antigravity-input.sh"
}

@test "lib parses stdin JSON and exports CLAUDE_PLUGIN_ROOT" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/ws"],"transcriptPath":"/t.jsonl","artifactDirectoryPath":"/art","toolCall":{"name":"write_to_file","args":{"TargetFile":"/ws/f.py"}},"stepIdx":3}'
  result=$(echo "$PAYLOAD" | bash -c "source '$LIB' && echo \"\$CLAUDE_PLUGIN_ROOT:\$WORKSPACE_PATH:\$ARIA_TOOL_NAME:\$ARIA_TOOL_TARGET_FILE\"")
  # CLAUDE_PLUGIN_ROOT derived from the lib's own path; just check format
  [[ "$result" =~ ^/.+:/ws:write_to_file:/ws/f\.py$ ]]
}

@test "lib handles missing optional fields gracefully" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/ws"],"transcriptPath":"/t","artifactDirectoryPath":"/art","stepIdx":0}'
  result=$(echo "$PAYLOAD" | bash -c "source '$LIB' && echo \"name=\${ARIA_TOOL_NAME:-EMPTY}\"")
  [ "$result" = "name=EMPTY" ]
}

@test "lib fails closed when jq is missing" {
  PAYLOAD='{}'
  result=$(echo "$PAYLOAD" | PATH=/usr/bin bash -c "source '$LIB' 2>&1; echo exit=\$?") || true
  [[ "$result" =~ jq ]] || [[ "$result" =~ exit=0 ]]  # If jq exists at /usr/bin/jq, test is a no-op
}
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
bats plugin-antigravity/tests/test-lib-antigravity-input.bats
```

Expected: FAIL with "No such file or directory" for the lib.

- [ ] **Step 3: Implement the lib**

Create `plugin-antigravity/bin/antigravity/lib-antigravity-input.sh`:

```bash
#!/bin/bash
# lib-antigravity-input.sh — shared stdin-JSON → env-var translator
#
# Sourced (not exec'd) by every Antigravity hook wrapper in this directory.
# Reads the hook input payload on stdin and exports env vars matching what
# ARIA's canonical bash scripts (in ../../../plugin-claude-code/bin/) expect.
#
# Hard dependency: jq. If missing, the lib writes a deny-JSON to stdout
# and exits the calling wrapper with code 1 (fail-closed).

if ! command -v jq >/dev/null 2>&1; then
  printf '{"decision":"deny","reason":"aria-knowledge requires jq to parse Antigravity hook input. Install jq (apt-get install jq / brew install jq) and re-try."}\n'
  exit 1
fi

# Read stdin once and cache it; subsequent jq invocations operate on the cache.
ARIA_HOOK_INPUT="$(cat -)"
export ARIA_HOOK_INPUT

# Extract common fields. All hook events deliver these per docs/hooks.
export ARIA_CONVERSATION_ID
export ARIA_WORKSPACE_PATHS
export WORKSPACE_PATH               # first workspace, for canonical-script convenience
export ARIA_TRANSCRIPT_PATH
export ARIA_ARTIFACT_DIR
export ARIA_STEP_IDX

ARIA_CONVERSATION_ID=$(jq -r '.conversationId // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_WORKSPACE_PATHS=$(jq -r '.workspacePaths // [] | join(":")' <<<"$ARIA_HOOK_INPUT")
WORKSPACE_PATH=$(jq -r '.workspacePaths[0] // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TRANSCRIPT_PATH=$(jq -r '.transcriptPath // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_ARTIFACT_DIR=$(jq -r '.artifactDirectoryPath // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_STEP_IDX=$(jq -r '.stepIdx // 0' <<<"$ARIA_HOOK_INPUT")

# Tool-call fields (PreToolUse / PostToolUse only). Empty string when absent.
export ARIA_TOOL_NAME
export ARIA_TOOL_TARGET_FILE
export ARIA_TOOL_COMMANDLINE
export ARIA_TOOL_CWD
export ARIA_TOOL_QUERY
export ARIA_TOOL_PATTERN
export ARIA_TOOL_ARGS_JSON

ARIA_TOOL_NAME=$(jq -r '.toolCall.name // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TOOL_TARGET_FILE=$(jq -r '.toolCall.args.TargetFile // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TOOL_COMMANDLINE=$(jq -r '.toolCall.args.CommandLine // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TOOL_CWD=$(jq -r '.toolCall.args.Cwd // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TOOL_QUERY=$(jq -r '.toolCall.args.Query // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TOOL_PATTERN=$(jq -r '.toolCall.args.Pattern // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TOOL_ARGS_JSON=$(jq -c '.toolCall.args // {}' <<<"$ARIA_HOOK_INPUT")

# CLAUDE_PLUGIN_ROOT: ARIA's canonical scripts read this. In Antigravity there
# is no equivalent env var, so derive it from the wrapper's own path. The lib
# lives at <plugin-root>/bin/antigravity/lib-antigravity-input.sh, so the
# plugin root is two levels up.
export CLAUDE_PLUGIN_ROOT
CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Helper: emit Antigravity stdout JSON decision payload.
# Usage: aria_emit_decision allow|deny|ask|force_ask "reason text"
aria_emit_decision() {
  local decision="$1"
  local reason="${2:-}"
  jq -cn --arg d "$decision" --arg r "$reason" '{decision: $d} + (if $r == "" then {} else {reason: $r} end)'
}
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
bats plugin-antigravity/tests/test-lib-antigravity-input.bats
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add plugin-antigravity/bin/antigravity/lib-antigravity-input.sh plugin-antigravity/tests/test-lib-antigravity-input.bats
git commit -m "feat(antigravity): add shared stdin-JSON → env-var translator lib

Bridges Antigravity's hook I/O contract (stdin JSON, stdout JSON
decision) to ARIA canonical bash scripts' env-var expectations.
CLAUDE_PLUGIN_ROOT is derived from BASH_SOURCE since Antigravity
exposes no equivalent env var.

Hard dep: jq. Fails closed with reason if jq missing."
```

---

## Task 5: Write pre-edit-aria.sh Wrapper

**Files:**
- Create: `plugin-antigravity/bin/antigravity/pre-edit-aria.sh`
- Test: `plugin-antigravity/tests/test-pre-edit-aria.bats`

PreToolUse hook for edit-class tools. Wraps `plugin-claude-code/bin/pre-edit-check.sh` (the canonical Rule 22 marker scan).

- [ ] **Step 1: Write the failing bats test**

Create `plugin-antigravity/tests/test-pre-edit-aria.bats`:

```bash
#!/usr/bin/env bats

setup() {
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/pre-edit-aria.sh"
}

@test "wrapper allows by default on write_to_file" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"write_to_file","args":{"TargetFile":"/tmp/f.txt","CodeContent":"x"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  decision=$(echo "$result" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "wrapper output is valid JSON" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"write_to_file","args":{"TargetFile":"/tmp/f.txt"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  echo "$result" | jq -e . >/dev/null
}

@test "wrapper sources lib successfully" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"replace_file_content","args":{"TargetFile":"/tmp/f.txt"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  [ -n "$result" ]
}
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
bats plugin-antigravity/tests/test-pre-edit-aria.bats
```

Expected: FAIL with "No such file or directory" for the wrapper.

- [ ] **Step 3: Implement the wrapper**

Create `plugin-antigravity/bin/antigravity/pre-edit-aria.sh`:

```bash
#!/bin/bash
# pre-edit-aria.sh — Antigravity PreToolUse wrapper for edit-class tools.
#
# Matched on hooks.json by: write_to_file|replace_file_content|multi_replace_file_content
# Reads stdin JSON via lib-antigravity-input.sh, sets env vars for the canonical
# script, then translates exit code + stderr into the Antigravity decision JSON.

set -uo pipefail

# Source the shared parser. It reads stdin, sets env vars including
# CLAUDE_PLUGIN_ROOT, ARIA_TOOL_NAME, ARIA_TOOL_TARGET_FILE, WORKSPACE_PATH.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

# Canonical script lives at <plugin-root>/bin/pre-edit-check.sh. CLAUDE_PLUGIN_ROOT
# is set by the lib to <plugin-antigravity>/, so the canonical script in the
# install layout is co-located with the wrapper's parent.
CANONICAL="$CLAUDE_PLUGIN_ROOT/bin/pre-edit-check.sh"

if [ ! -x "$CANONICAL" ]; then
  aria_emit_decision "allow" "aria-knowledge canonical pre-edit-check.sh not found at $CANONICAL; allowing without Rule 22 scan."
  exit 0
fi

# Canonical script reads Claude Code env vars. Translate Antigravity's tool
# names into the file path the canonical script expects to scan.
export CLAUDE_TOOL_NAME="$ARIA_TOOL_NAME"
export CLAUDE_TARGET_FILE="$ARIA_TOOL_TARGET_FILE"
export CLAUDE_TRANSCRIPT_PATH="$ARIA_TRANSCRIPT_PATH"

# Capture canonical script's stdout + stderr; advisory output goes to stderr in
# the canonical impl (visible to the agent in Claude Code via the hook log).
ADVISORY=$("$CANONICAL" 2>&1)
CANONICAL_EXIT=$?

if [ $CANONICAL_EXIT -eq 0 ]; then
  # Allow. Pass any advisory text through as the reason so the agent sees it.
  if [ -n "$ADVISORY" ]; then
    aria_emit_decision "allow" "$ADVISORY"
  else
    aria_emit_decision "allow"
  fi
else
  # Non-zero exit from canonical = Rule 22 deny.
  aria_emit_decision "deny" "${ADVISORY:-Rule 22 pre-edit check denied this edit.}"
fi
```

- [ ] **Step 4: Make executable, run test, verify pass**

```bash
chmod +x plugin-antigravity/bin/antigravity/pre-edit-aria.sh
bats plugin-antigravity/tests/test-pre-edit-aria.bats
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add plugin-antigravity/bin/antigravity/pre-edit-aria.sh plugin-antigravity/tests/test-pre-edit-aria.bats
git commit -m "feat(antigravity): add PreToolUse wrapper for edit-class tools

Matches Antigravity tools write_to_file|replace_file_content|
multi_replace_file_content. Translates stdin JSON to env vars,
delegates to canonical plugin-claude-code/bin/pre-edit-check.sh, converts
exit code + advisory text to Antigravity decision JSON.

Antigravity's documented deny semantic means Rule 22 is fail-closed
here (unlike Claude Code where the deny is advisory)."
```

---

## Task 6: Write pre-explore-aria.sh Wrapper

**Files:**
- Create: `plugin-antigravity/bin/antigravity/pre-explore-aria.sh`
- Test: `plugin-antigravity/tests/test-pre-explore-aria.bats`

PreToolUse hook for search-class tools (`grep_search`, `find_by_name`). Wraps `plugin-claude-code/bin/pre-explore-codemap-check.sh`.

- [ ] **Step 1: Write the failing bats test**

Create `plugin-antigravity/tests/test-pre-explore-aria.bats`:

```bash
#!/usr/bin/env bats

setup() {
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/pre-explore-aria.sh"
}

@test "wrapper allows grep_search by default" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"grep_search","args":{"SearchPath":"/tmp","Query":"foo"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  decision=$(echo "$result" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "wrapper allows find_by_name by default" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"find_by_name","args":{"SearchDirectory":"/tmp","Pattern":"*.py"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  decision=$(echo "$result" | jq -r '.decision')
  [ "$decision" = "allow" ]
}
```

- [ ] **Step 2: Run test, verify failure**

```bash
bats plugin-antigravity/tests/test-pre-explore-aria.bats
```

Expected: FAIL.

- [ ] **Step 3: Implement the wrapper**

Create `plugin-antigravity/bin/antigravity/pre-explore-aria.sh`:

```bash
#!/bin/bash
# pre-explore-aria.sh — Antigravity PreToolUse wrapper for search-class tools.
# Matched on hooks.json by: grep_search|find_by_name
# Wraps canonical pre-explore-codemap-check.sh which surfaces CODEMAP-read
# reminders when exploring an unfamiliar codebase.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

CANONICAL="$CLAUDE_PLUGIN_ROOT/bin/pre-explore-codemap-check.sh"

if [ ! -x "$CANONICAL" ]; then
  aria_emit_decision "allow"
  exit 0
fi

# Translate Antigravity tool args into the canonical script's expectations.
# The canonical script reads CLAUDE_TOOL_NAME and an optional path arg.
export CLAUDE_TOOL_NAME="$ARIA_TOOL_NAME"
case "$ARIA_TOOL_NAME" in
  grep_search)
    export CLAUDE_SEARCH_PATH=$(jq -r '.toolCall.args.SearchPath // ""' <<<"$ARIA_HOOK_INPUT")
    ;;
  find_by_name)
    export CLAUDE_SEARCH_PATH=$(jq -r '.toolCall.args.SearchDirectory // ""' <<<"$ARIA_HOOK_INPUT")
    ;;
esac

ADVISORY=$("$CANONICAL" 2>&1)
CANONICAL_EXIT=$?

if [ $CANONICAL_EXIT -eq 0 ]; then
  if [ -n "$ADVISORY" ]; then
    aria_emit_decision "allow" "$ADVISORY"
  else
    aria_emit_decision "allow"
  fi
else
  aria_emit_decision "deny" "${ADVISORY:-Codemap pre-check denied this exploration.}"
fi
```

- [ ] **Step 4: Make executable, run test, verify pass**

```bash
chmod +x plugin-antigravity/bin/antigravity/pre-explore-aria.sh
bats plugin-antigravity/tests/test-pre-explore-aria.bats
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add plugin-antigravity/bin/antigravity/pre-explore-aria.sh plugin-antigravity/tests/test-pre-explore-aria.bats
git commit -m "feat(antigravity): add PreToolUse wrapper for search-class tools

Matches grep_search|find_by_name. CODEMAP-read reminder via
canonical pre-explore-codemap-check.sh."
```

---

## Task 7: Write bash-cd-aria.sh Wrapper

**Files:**
- Create: `plugin-antigravity/bin/antigravity/bash-cd-aria.sh`
- Test: `plugin-antigravity/tests/test-bash-cd-aria.bats`

PreToolUse hook for `run_command`. Surfaces path-keyed knowledge when the agent runs `cd`.

- [ ] **Step 1: Write the failing bats test**

Create `plugin-antigravity/tests/test-bash-cd-aria.bats`:

```bash
#!/usr/bin/env bats

setup() {
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/bash-cd-aria.sh"
}

@test "wrapper allows a non-cd command" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"run_command","args":{"CommandLine":"ls -la","Cwd":"/tmp"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  decision=$(echo "$result" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "wrapper allows a cd command and surfaces path knowledge advisory" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"run_command","args":{"CommandLine":"cd /Users/mikeprasad/Projects/cs","Cwd":"/tmp"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  decision=$(echo "$result" | jq -r '.decision')
  [ "$decision" = "allow" ]
}
```

- [ ] **Step 2: Run, verify fail**

```bash
bats plugin-antigravity/tests/test-bash-cd-aria.bats
```

- [ ] **Step 3: Implement**

Create `plugin-antigravity/bin/antigravity/bash-cd-aria.sh`:

```bash
#!/bin/bash
# bash-cd-aria.sh — Antigravity PreToolUse wrapper for run_command.
# Matched on hooks.json by: run_command
# Wraps canonical bash-cd-check.sh which surfaces path-keyed knowledge
# files when the agent runs cd into a tracked directory.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

CANONICAL="$CLAUDE_PLUGIN_ROOT/bin/bash-cd-check.sh"

if [ ! -x "$CANONICAL" ]; then
  aria_emit_decision "allow"
  exit 0
fi

# Canonical script expects CLAUDE_BASH_COMMAND.
export CLAUDE_BASH_COMMAND="$ARIA_TOOL_COMMANDLINE"
export CLAUDE_BASH_CWD="$ARIA_TOOL_CWD"

ADVISORY=$("$CANONICAL" 2>&1)
CANONICAL_EXIT=$?

if [ $CANONICAL_EXIT -eq 0 ]; then
  if [ -n "$ADVISORY" ]; then
    aria_emit_decision "allow" "$ADVISORY"
  else
    aria_emit_decision "allow"
  fi
else
  aria_emit_decision "deny" "${ADVISORY:-bash-cd-check denied this command.}"
fi
```

- [ ] **Step 4: Make executable, run, verify pass**

```bash
chmod +x plugin-antigravity/bin/antigravity/bash-cd-aria.sh
bats plugin-antigravity/tests/test-bash-cd-aria.bats
```

- [ ] **Step 5: Commit**

```bash
git add plugin-antigravity/bin/antigravity/bash-cd-aria.sh plugin-antigravity/tests/test-bash-cd-aria.bats
git commit -m "feat(antigravity): add PreToolUse wrapper for run_command

Matches run_command. Surfaces path-keyed knowledge via canonical
bash-cd-check.sh when the agent cd's into a tracked dir."
```

---

## Task 8: Write post-edit-aria.sh Wrapper

**Files:**
- Create: `plugin-antigravity/bin/antigravity/post-edit-aria.sh`
- Test: `plugin-antigravity/tests/test-post-edit-aria.bats`

PostToolUse hook for edit-class tools. Wraps `plugin-claude-code/bin/post-edit-check.sh` (the scope-check PASS/CONDITIONAL/FAIL emitter).

- [ ] **Step 1: Write the failing bats test**

Create `plugin-antigravity/tests/test-post-edit-aria.bats`:

```bash
#!/usr/bin/env bats

setup() {
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/post-edit-aria.sh"
}

@test "wrapper returns empty JSON object on success" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":5,"error":""}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  # PostToolUse spec says output is {} on success.
  parsed=$(echo "$result" | jq -c .)
  [ "$parsed" = "{}" ] || [[ "$parsed" =~ ^\{ ]]
}

@test "wrapper produces valid JSON even on canonical script error" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":5,"error":"exit status 1"}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  echo "$result" | jq -e . >/dev/null
}
```

- [ ] **Step 2: Run, verify fail**

```bash
bats plugin-antigravity/tests/test-post-edit-aria.bats
```

- [ ] **Step 3: Implement**

Create `plugin-antigravity/bin/antigravity/post-edit-aria.sh`:

```bash
#!/bin/bash
# post-edit-aria.sh — Antigravity PostToolUse wrapper for edit-class tools.
# Matched on hooks.json by: write_to_file|replace_file_content|multi_replace_file_content
# Wraps canonical post-edit-check.sh which emits the Rule 22 scope-check
# PASS / CONDITIONAL / FAIL output for the just-completed edit.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

CANONICAL="$CLAUDE_PLUGIN_ROOT/bin/post-edit-check.sh"

# PostToolUse output schema per docs: empty JSON {} on success. The canonical
# script writes scope-check text to stdout; we surface that as the agent sees it
# via stderr-equivalent (Antigravity's hook log), but the protocol-level reply
# is {} unless we want to short-circuit (we don't here).

# Translate Antigravity error field into a canonical-friendly signal.
ERROR_FIELD=$(jq -r '.error // ""' <<<"$ARIA_HOOK_INPUT")
export CLAUDE_TOOL_ERROR="$ERROR_FIELD"
export CLAUDE_TRANSCRIPT_PATH="$ARIA_TRANSCRIPT_PATH"

# Run canonical, capture but don't propagate output. Antigravity's PostToolUse
# does NOT support reasoning back to the agent — output is {}. If we want to
# show the scope-check to the user, it has to go via a side channel (e.g. file
# log). For v1, log to ~/.gemini/antigravity/aria-knowledge-scope-check.log.
LOG_FILE="$HOME/.gemini/antigravity/aria-knowledge-scope-check.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

if [ -x "$CANONICAL" ]; then
  {
    echo "--- $(date -u '+%Y-%m-%dT%H:%M:%SZ') stepIdx=$ARIA_STEP_IDX error=${ERROR_FIELD:-none}"
    "$CANONICAL" 2>&1
  } >> "$LOG_FILE" || true
fi

# Per docs/hooks PostToolUse: output is {} on success.
printf '{}\n'
```

- [ ] **Step 4: Make executable, run, verify pass**

```bash
chmod +x plugin-antigravity/bin/antigravity/post-edit-aria.sh
bats plugin-antigravity/tests/test-post-edit-aria.bats
```

- [ ] **Step 5: Commit**

```bash
git add plugin-antigravity/bin/antigravity/post-edit-aria.sh plugin-antigravity/tests/test-post-edit-aria.bats
git commit -m "feat(antigravity): add PostToolUse wrapper for edit-class tools

PostToolUse protocol returns {}; scope-check output is logged
side-channel to ~/.gemini/antigravity/aria-knowledge-scope-check.log
since PostToolUse cannot reason back to the agent."
```

---

## Task 9: Write hooks.json with 4 Named Hook Entries

**Files:**
- Create: `plugin-antigravity/hooks.json`

- [ ] **Step 1: Write the file**

Create `plugin-antigravity/hooks.json`:

```json
{
  "aria-pre-edit": {
    "PreToolUse": [
      {
        "matcher": "write_to_file|replace_file_content|multi_replace_file_content",
        "hooks": [
          {
            "type": "command",
            "command": "bash ./bin/antigravity/pre-edit-aria.sh",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "aria-pre-explore": {
    "PreToolUse": [
      {
        "matcher": "grep_search|find_by_name",
        "hooks": [
          {
            "type": "command",
            "command": "bash ./bin/antigravity/pre-explore-aria.sh",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "aria-bash-cd": {
    "PreToolUse": [
      {
        "matcher": "run_command",
        "hooks": [
          {
            "type": "command",
            "command": "bash ./bin/antigravity/bash-cd-aria.sh",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "aria-post-edit": {
    "PostToolUse": [
      {
        "matcher": "write_to_file|replace_file_content|multi_replace_file_content",
        "hooks": [
          {
            "type": "command",
            "command": "bash ./bin/antigravity/post-edit-aria.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Note: paths are relative (`./bin/...`). Antigravity sets CWD to the plugin root when invoking hooks (per `/docs/plugins` documenting plugin discovery; if confirmed otherwise during smoke test in Task 17, the wrapper paths flip to absolute). The probe-hook in Task 15 verifies the CWD assumption empirically.

- [ ] **Step 2: jq validate the JSON**

```bash
jq . plugin-antigravity/hooks.json
```

Expected: pretty-printed JSON, exit 0.

- [ ] **Step 3: Verify schema against docs**

```bash
# All matchers use Antigravity tool names — grep for any Claude Code tool names that snuck in:
grep -E '"matcher":\s*"(Edit|Write|Glob|Grep|Bash|Read)"' plugin-antigravity/hooks.json
```

Expected: no output (no Claude Code tool names).

- [ ] **Step 4: Commit**

```bash
git add plugin-antigravity/hooks.json
git commit -m "feat(antigravity): add hooks.json with 4 per-turn hook entries

Three PreToolUse matchers + one PostToolUse, all using verified
Antigravity tool names (write_to_file|replace_file_content|
multi_replace_file_content, grep_search|find_by_name, run_command).
No PreInvocation/PostInvocation/Stop hooks — those are per-turn
events too frequent to substitute for one-time session lifecycle.

Per-turn discipline (Mike, 2026-05-24): only per-turn hooks where
needed; SessionStart-equivalent content lives in GEMINI.md instead."
```

---

## Task 10: Write mcp_config.json with serverUrl + OAuth Adaptation

**Files:**
- Create: `plugin-antigravity/mcp_config.json`

- [ ] **Step 1: Read the canonical .mcp.json**

```bash
cat /Users/mikeprasad/Projects/aria/aria-knowledge/plugin-claude-code/.mcp.json
```

Expected: the 12-server HTTP-MCP block with `"type": "http", "url": "..."` shape.

- [ ] **Step 2: Write mcp_config.json with translated shape**

Create `plugin-antigravity/mcp_config.json`:

```json
{
  "mcpServers": {
    "slack": {
      "serverUrl": "https://mcp.slack.com/mcp"
    },
    "ms365": {
      "serverUrl": "https://microsoft365.mcp.claude.com/mcp"
    },
    "gmail": {
      "serverUrl": ""
    },
    "linear": {
      "serverUrl": "https://mcp.linear.app/mcp"
    },
    "asana": {
      "serverUrl": "https://mcp.asana.com/v2/mcp"
    },
    "atlassian": {
      "serverUrl": "https://mcp.atlassian.com/v1/mcp"
    },
    "monday": {
      "serverUrl": "https://mcp.monday.com/mcp"
    },
    "clickup": {
      "serverUrl": "https://mcp.clickup.com/mcp"
    },
    "notion": {
      "serverUrl": "https://mcp.notion.com/mcp"
    },
    "box": {
      "serverUrl": "https://mcp.box.com/"
    },
    "egnyte": {
      "serverUrl": "https://mcp.egnyte.com/mcp"
    },
    "google docs": {
      "serverUrl": ""
    }
  }
}
```

Adaptations from canonical:
- Filename: `.mcp.json` → `mcp_config.json`
- Top-level structure: identical (`mcpServers` object)
- HTTP URL key: `"url"` → `"serverUrl"` (per `/docs/mcp` verbatim)
- Removed `"type": "http"`: not part of Antigravity schema (transport inferred from `serverUrl` presence)
- Slack `oauth` block: removed (canonical used `callbackPort`; Antigravity uses `clientSecret` for non-DCR servers, or the UI flow for DCR-supporting servers — Slack supports DCR per Antigravity's `/docs/mcp` OAuth section, so no inline OAuth needed)
- `"google docs"` (with space): preserved per v2.18.1 canonical fix

- [ ] **Step 3: Validate JSON**

```bash
jq . plugin-antigravity/mcp_config.json
```

Expected: exit 0, valid JSON.

- [ ] **Step 4: Verify no leaked Claude Code shape**

```bash
grep -E '("url"|"type":\s*"http"|"callbackPort")' plugin-antigravity/mcp_config.json
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add plugin-antigravity/mcp_config.json
git commit -m "feat(antigravity): add mcp_config.json with serverUrl shape

12 MCP servers, all HTTP transport via serverUrl per
antigravity.google/docs/mcp. OAuth handled by Antigravity's UI
flow on first connect (supports DCR for all current MCP vendors)."
```

---

## Task 11: Write GEMINI.md (Session-Lifecycle + ARIA Persona)

**Files:**
- Create: `plugin-antigravity/GEMINI.md`

This file is the one-time-per-session injection point. Antigravity loads `~/.gemini/GEMINI.md` as global rules; for plugin-scoped content the convention (per `/docs/rules-workflows`) is workspace rules at `.agents/rules/`. We ship a single `GEMINI.md` at the plugin root which the user copies/symlinks to either location during install. 12,000-char limit per file applies.

- [ ] **Step 1: Compose the content**

Create `plugin-antigravity/GEMINI.md`:

```markdown
# ARIA Knowledge — Antigravity Session Discipline

You have access to aria-knowledge, a persistent human-governed knowledge plugin. ARIA's five-phase lifecycle (capture → govern → promote → apply → refresh) is active. This file is the session-lifecycle equivalent of Claude Code's SessionStart hook — it loads once per session and tells you what to do at session boundaries that Antigravity's per-turn hooks cannot.

## At the start of every session

1. **Check audit cadence.** Read `~/.gemini/antigravity/aria-knowledge.local.md`. If `audit_cadence_knowledge` days have passed since the last `/audit-knowledge` (per the log at `{knowledge_folder}/logs/knowledge-audit-log.md`), surface the prompt: *"Knowledge audit is due — want me to run /audit-knowledge?"*
2. **Surface relevant knowledge.** If `active_knowledge_surfacing: true` and the user's first prompt contains project tags or topic keywords, suggest `/context <tags>` to load relevant knowledge files before answering.
3. **Check for stale batch manifest.** If `~/.gemini/antigravity/active-batch.json` exists and its `expires_at` is in the past, delete it silently.

Do these checks at most once per session, in your first response to the user.

## Rule 22 — Change Decision Framework (advisory text)

Every Edit/Write/Bash you propose triggers `pre-edit-aria.sh` / `bash-cd-aria.sh` hooks that scan for `[Rule 22]` markers and emit Antigravity's deny semantic if the change is high-impact without justification. To stay ahead of the hook:

- **Before any Edit/Write**, emit a `[Rule 22] Low Impact — <reason>` or `[Rule 22] High Impact — <reason>` marker that completes the 7-step framework (identify change → intake → criteria → solutions → rank → decide → execute).
- **After any Edit/Write**, the `post-edit-aria.sh` hook logs a scope check to `~/.gemini/antigravity/aria-knowledge-scope-check.log`. Read your own log periodically to catch scope drift.

Full framework: `~/Projects/knowledge/rules/change-decision-framework.md` (or wherever knowledge_folder points). 34 working rules: `~/Projects/knowledge/rules/working-rules.md`.

## MCP category placeholders

ARIA skills use `~~category` placeholders (e.g. `~~chat`, `~~docs`, `~~project tracker`). At install, run `cowork-plugin-customizer` to replace these with your team's connectors, or leave as-is and let skills probe at runtime per ADR-015 (capability-probe pattern).

## Snapshot before context loss

Antigravity has persistent sessions but long sessions still eventually exceed context. Before context becomes critical:

- `/snapshot` — archives current transcript via `transcriptPath` from any hook's stdin payload
- `/wrapup` — closes the session cleanly
- `/handoff` — produces a passoff brief for the next session

The session-ledger pattern (canonical PostCompact behavior) re-emerges via these manual skills — Antigravity has no PostCompact event.

## Knowledge folder

Knowledge lives at the `knowledge_folder` path in your config (`~/.gemini/antigravity/aria-knowledge.local.md`). Standard structure: `intake/`, `approaches/`, `decisions/`, `references/`, `rules/`, `projects/`, `logs/`. The folder is port-agnostic — same content works across Claude Code, Codex, Cursor, and Antigravity installs.

## Commands

`/setup` first. Then `/help` for the full command reference.
```

- [ ] **Step 2: Verify character count under 12k**

```bash
wc -c plugin-antigravity/GEMINI.md
```

Expected: under 12000.

- [ ] **Step 3: Verify no Claude-specific paths leaked**

```bash
grep -E '~/\.claude/' plugin-antigravity/GEMINI.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add plugin-antigravity/GEMINI.md
git commit -m "feat(antigravity): add GEMINI.md for session-lifecycle content

Per-session SessionStart-equivalent behaviors (audit cadence check,
knowledge surfacing, stale batch cleanup) live here instead of in
per-turn hooks. Antigravity loads workspace rules / global GEMINI.md
once per session by design.

Per Mike 2026-05-24: per-turn hooks for per-turn purposes only;
session-lifecycle content goes in GEMINI.md."
```

---

## Task 12: Copy + Path-Adapt skills/

**Files:**
- Create: `plugin-antigravity/skills/<name>/SKILL.md` × 30

- [ ] **Step 1: Copy skills from canonical**

```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
cp -R plugin-claude-code/skills/. plugin-antigravity/skills/
ls plugin-antigravity/skills/ | wc -l
```

Expected: 30 skill directories.

- [ ] **Step 2: Run path substitutions**

```bash
find plugin-antigravity/skills/ -name 'SKILL.md' -exec sed -i '' \
  -e 's|~/\.claude/aria-knowledge\.local\.md|~/.gemini/antigravity/aria-knowledge.local.md|g' \
  -e 's|~/\.claude/projects/|~/.gemini/antigravity/transcripts/|g' \
  -e 's|~/\.claude/active-batch\.json|~/.gemini/antigravity/active-batch.json|g' \
  {} +
```

(macOS `sed -i ''` syntax. On Linux use `sed -i` without the empty string arg.)

- [ ] **Step 3: Verify no Claude paths remain**

```bash
grep -rln '~/\.claude/' plugin-antigravity/skills/
```

Expected: no output.

- [ ] **Step 4: Strip the ADR-094 bare-slash runtime-gate prose from skill descriptions**

The runtime-gate prose was added for the Claude Code / Claude Cowork dual-runtime collision (ADR-094). In Antigravity, aria-cowork is not installed alongside aria-knowledge — the gate framing is dead text. Strip it from the `description:` field of affected skills.

```bash
# Identify affected skills:
grep -l 'Bare-slash canonical' plugin-antigravity/skills/*/SKILL.md
```

For each affected file, manually edit the `description:` field to remove the leading `**Bare-slash canonical (Claude Code).** ... RUNTIME GATE: ...` block, keeping only the actual skill description.

Pattern to remove (regex):
```
\*\*Bare-slash canonical \(Claude Code\)\.\*\*[^.]*\.\s+RUNTIME GATE:[^.]*\.\s+
```

```bash
# Apply the strip (handles multi-sentence, multi-skill cases):
find plugin-antigravity/skills/ -name 'SKILL.md' -exec sed -i '' \
  -E 's|\*\*Bare-slash canonical \(Claude Code\)\.\*\*[^.]*\.\s+RUNTIME GATE: if invoked from a non-Code runtime [^)]*\)\.\s+||g' \
  {} +
```

- [ ] **Step 5: Verify stripping**

```bash
grep -l 'Bare-slash canonical' plugin-antigravity/skills/*/SKILL.md
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add plugin-antigravity/skills/
git commit -m "feat(antigravity): copy + path-adapt 30 SKILL.md files

Substitutions:
- ~/.claude/aria-knowledge.local.md → ~/.gemini/antigravity/aria-knowledge.local.md
- ~/.claude/projects/ → ~/.gemini/antigravity/transcripts/
- ~/.claude/active-batch.json → ~/.gemini/antigravity/active-batch.json
- Stripped ADR-094 bare-slash runtime-gate prose (not applicable in Antigravity
  since aria-cowork is not installed alongside)"
```

---

## Task 13: Copy + Path-Adapt template/

**Files:**
- Create: `plugin-antigravity/template/...` (knowledge folder scaffold)

- [ ] **Step 1: Copy template tree**

```bash
cd /Users/mikeprasad/Projects/aria/aria-knowledge
cp -R plugin-claude-code/template/. plugin-antigravity/template/
```

- [ ] **Step 2: Path-substitute**

```bash
find plugin-antigravity/template/ -name '*.md' -exec sed -i '' \
  -e 's|~/\.claude/aria-knowledge\.local\.md|~/.gemini/antigravity/aria-knowledge.local.md|g' \
  -e 's|~/\.claude/projects/|~/.gemini/antigravity/transcripts/|g' \
  -e 's|~/\.claude/active-batch\.json|~/.gemini/antigravity/active-batch.json|g' \
  {} +
```

- [ ] **Step 3: Verify**

```bash
grep -rln '~/\.claude/' plugin-antigravity/template/
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add plugin-antigravity/template/
git commit -m "feat(antigravity): copy + path-adapt knowledge folder template

Knowledge folder schema is port-agnostic; only the local-config
path references differ between ports."
```

---

## Task 14: Write build.sh for the Flat Antigravity Layout

**Files:**
- Create: `plugin-antigravity/build.sh`

Re-runnable assembly script. Reads from canonical `plugin/`, applies adaptations, writes into the port directory.

- [ ] **Step 1: Write the script**

Create `plugin-antigravity/build.sh`:

```bash
#!/bin/sh
# build.sh — assemble plugin-antigravity from canonical plugin/ source.
# Run after any plugin/ update to propagate canonical changes.
#
# Usage: bash plugin-antigravity/build.sh
# Safe to re-run.
#
# What this script adapts:
#   1. KT_CONFIG default path:   ~/.claude/aria-knowledge.local.md
#                              → ~/.gemini/antigravity/aria-knowledge.local.md
#   2. mkdir paths inside scripts: $HOME/.claude → $HOME/.gemini/antigravity
#   3. SKILL.md path references:   same substitutions
#   4. ADR-094 runtime-gate prose: stripped from skill descriptions
#
# What this script does NOT touch (hand-authored, durable across rebuilds):
#   - plugin.json                  (marker file, never changes)
#   - hooks.json                   (4 named hook entries)
#   - mcp_config.json              (12 servers, manual updates)
#   - GEMINI.md                    (session-lifecycle content)
#   - bin/antigravity/             (4 wrappers + 1 lib + tests)
#   - PORTING.md, README.md, SMOKE-TEST.md

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO/plugin"
DST="$SCRIPT_DIR"

echo "[aria-knowledge] Building Antigravity port (flat layout) ..."
echo "  Source: $SRC"
echo "  Dest:   $DST"

# --- skills/ (copy + path-substitute + strip ADR-094 prose) ---
rm -rf "$DST/skills" 2>/dev/null || true
cp -R "$SRC/skills" "$DST/skills"

find "$DST/skills" -name 'SKILL.md' -exec sed -i.bak \
  -e 's|~/\.claude/aria-knowledge\.local\.md|~/.gemini/antigravity/aria-knowledge.local.md|g' \
  -e 's|~/\.claude/projects/|~/.gemini/antigravity/transcripts/|g' \
  -e 's|~/\.claude/active-batch\.json|~/.gemini/antigravity/active-batch.json|g' \
  {} +
find "$DST/skills" -name 'SKILL.md.bak' -delete

# Strip ADR-094 runtime-gate prose from skill descriptions
find "$DST/skills" -name 'SKILL.md' -exec sed -i.bak -E \
  's|\*\*Bare-slash canonical \(Claude Code\)\.\*\*[^.]*\.\s+RUNTIME GATE: if invoked from a non-Code runtime [^)]*\)\.\s+||g' \
  {} +
find "$DST/skills" -name 'SKILL.md.bak' -delete

echo "  Copied $(find "$DST/skills" -maxdepth 1 -type d | wc -l | tr -d ' ') skill directories."

# --- template/ (knowledge folder scaffold) ---
rm -rf "$DST/template" 2>/dev/null || true
cp -R "$SRC/template" "$DST/template"

find "$DST/template" -name '*.md' -exec sed -i.bak \
  -e 's|~/\.claude/aria-knowledge\.local\.md|~/.gemini/antigravity/aria-knowledge.local.md|g' \
  -e 's|~/\.claude/projects/|~/.gemini/antigravity/transcripts/|g' \
  -e 's|~/\.claude/active-batch\.json|~/.gemini/antigravity/active-batch.json|g' \
  {} +
find "$DST/template" -name '*.bak' -delete

echo "  Copied template/."

# --- bin/ canonical scripts (copied — wrappers reference these) ---
mkdir -p "$DST/bin"
# Skip pre-compact-check.sh and post-compact-check.sh (no Antigravity equivalent
# events; transcript snapshot handled by /snapshot skill).
for f in "$SRC/bin"/*.sh; do
  name=$(basename "$f")
  case "$name" in
    pre-compact-check.sh|post-compact-check.sh)
      echo "  [skip] $name (no Antigravity equivalent event)"
      continue
      ;;
    config.sh)
      # Path substitution for config.sh
      sed \
        -e 's|$HOME/.claude/aria-knowledge.local.md|$HOME/.gemini/antigravity/aria-knowledge.local.md|g' \
        -e 's|mkdir -p "$HOME/.claude"|mkdir -p "$HOME/.gemini/antigravity"|g' \
        "$f" > "$DST/bin/config.sh"
      chmod +x "$DST/bin/config.sh"
      continue
      ;;
  esac
  cp "$f" "$DST/bin/$name"
  chmod +x "$DST/bin/$name"
done

echo "  Copied $(ls "$DST/bin"/*.sh 2>/dev/null | wc -l | tr -d ' ') canonical bin scripts."

echo ""
echo "[aria-knowledge] Antigravity port build complete."
echo "  Hand-authored files preserved: plugin.json, hooks.json, mcp_config.json, GEMINI.md, bin/antigravity/*, PORTING.md, README.md, SMOKE-TEST.md"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x plugin-antigravity/build.sh
```

- [ ] **Step 3: Run it to verify idempotency**

```bash
bash plugin-antigravity/build.sh
git status plugin-antigravity/
```

Expected: no diff after the rebuild (the script's output matches what's already on disk from Tasks 12 + 13).

- [ ] **Step 4: Commit**

```bash
git add plugin-antigravity/build.sh
git commit -m "feat(antigravity): add build.sh assembly script

Re-runnable. Idempotent. Adapts skills/, template/, bin/ from
canonical plugin/. Does NOT touch hand-authored config files
(plugin.json, hooks.json, mcp_config.json, GEMINI.md, wrappers)."
```

---

## Task 15: Add Probe-Hook for First-Session Empirical Verification

**Files:**
- Modify: `plugin-antigravity/bin/antigravity/pre-edit-aria.sh:1-5`

Insert a one-shot probe at the top of `pre-edit-aria.sh` that dumps the runtime env contract to `~/aria-antigravity-probe.log` on first run, then self-deletes. Verifies OQ-1 (env var availability, CWD assumption, jq path, etc.) empirically on first install.

- [ ] **Step 1: Add the probe block**

Insert after the shebang in `plugin-antigravity/bin/antigravity/pre-edit-aria.sh`:

```bash
#!/bin/bash
# pre-edit-aria.sh — Antigravity PreToolUse wrapper for edit-class tools.
# (Matched on hooks.json by: write_to_file|replace_file_content|multi_replace_file_content)

# --- ONE-SHOT PROBE (self-deletes after first successful run) ---
PROBE_FLAG="$HOME/.gemini/antigravity/.aria-probe-fired"
if [ ! -f "$PROBE_FLAG" ]; then
  {
    echo "=== aria-knowledge first-session probe @ $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
    echo "--- pwd ---"
    pwd
    echo "--- which bash ---"
    which bash
    echo "--- env (filtered) ---"
    env | grep -iE 'PLUGIN|AGY|ANTIGRAVITY|GEMINI|HOME|PATH' | sort
    echo "--- bash version ---"
    bash --version | head -1
    echo "--- jq version ---"
    jq --version 2>&1 || echo "jq missing"
    echo "--- BASH_SOURCE[0] ---"
    echo "${BASH_SOURCE[0]}"
    echo "--- derived CLAUDE_PLUGIN_ROOT ---"
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
    cd - >/dev/null
    echo "--- stdin payload (first 1000 bytes) ---"
    cat - | head -c 1000
  } > "$HOME/aria-antigravity-probe.log" 2>&1
  mkdir -p "$(dirname "$PROBE_FLAG")" 2>/dev/null || true
  touch "$PROBE_FLAG"
  # Read stdin again for normal hook execution. Since cat consumed it above,
  # the wrapper will see empty stdin this once. Emit allow + reason.
  printf '{"decision":"allow","reason":"aria-knowledge probe-hook fired; see ~/aria-antigravity-probe.log. Future hooks operate normally."}\n'
  exit 0
fi
# --- END PROBE ---

set -uo pipefail
# ... (rest of wrapper unchanged)
```

- [ ] **Step 2: Verify probe block syntax**

```bash
bash -n plugin-antigravity/bin/antigravity/pre-edit-aria.sh
```

Expected: exit 0 (no syntax error).

- [ ] **Step 3: Test probe in isolation (simulate first run)**

```bash
# Clear any prior probe flag
rm -f ~/.gemini/antigravity/.aria-probe-fired ~/aria-antigravity-probe.log

PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/t","artifactDirectoryPath":"/art","stepIdx":0,"toolCall":{"name":"write_to_file","args":{"TargetFile":"/tmp/f"}}}'
echo "$PAYLOAD" | bash plugin-antigravity/bin/antigravity/pre-edit-aria.sh

cat ~/aria-antigravity-probe.log
```

Expected: probe log file written with env dump.

- [ ] **Step 4: Verify probe is self-suppressing on second run**

```bash
echo "$PAYLOAD" | bash plugin-antigravity/bin/antigravity/pre-edit-aria.sh
# Second run should NOT overwrite the log
ls -l ~/aria-antigravity-probe.log
```

Expected: mtime unchanged (file untouched on second run).

- [ ] **Step 5: Commit**

```bash
git add plugin-antigravity/bin/antigravity/pre-edit-aria.sh
git commit -m "feat(antigravity): add one-shot probe-hook for first-session env verification

Empirically resolves OQ-1 (env var availability), OQ-2 (CWD when
Antigravity invokes hooks), and OQ-3 (jq path). Self-suppresses
via flag file after one successful fire.

Probe output: ~/aria-antigravity-probe.log
Flag: ~/.gemini/antigravity/.aria-probe-fired"
```

---

## Task 16: Write PORTING.md Drift Log

**Files:**
- Create: `plugin-antigravity/PORTING.md`

- [ ] **Step 1: Compose the drift log**

Create `plugin-antigravity/PORTING.md`:

```markdown
# PORTING.md — Antigravity Port of aria-knowledge

This file tracks divergence between `plugin/` (canonical Claude Code port) and `plugin-antigravity/` (this port), per the same convention as `cursor-template/PORTING.md` and `plugin-openai-codex/`.

---

## Port overview

| Dimension | Canonical (Claude Code) | Antigravity port |
|---|---|---|
| Plugin manifest path | `.claude-plugin/plugin.json` | **`plugin.json` (flat, at plugin root)** |
| Manifest schema | Rich metadata (name, version, description, hooks block, keywords, author, license) | **Marker only: `{"name": "aria-knowledge"}`** |
| Hook config path | Inline `hooks` block in `plugin.json` | **Separate `hooks.json` at plugin root** |
| Hook JSON shape | `{"hooks": {"PreToolUse": [...]}}` | **`{"named-hook-id": {"PreToolUse": [...]}}`** — named entries at top level |
| Hook events supported | SessionStart, PreToolUse, PostToolUse, PreCompact, PostCompact, TaskCreated, Stop, Notification, etc. | **PreToolUse, PostToolUse, PreInvocation, PostInvocation, Stop** (only) |
| Hook I/O contract | Env vars (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_TRANSCRIPT_PATH`, etc.) | **stdin JSON in, stdout JSON out**; no env vars; context fields are `workspacePaths`, `transcriptPath`, `artifactDirectoryPath`, `toolCall.{name,args}`, `stepIdx` |
| Hook tool matchers | Claude Code tool names (`Edit`, `Write`, `Glob`, `Grep`, `Bash`) | **Antigravity tool names** (`write_to_file`, `replace_file_content`, `multi_replace_file_content`, `grep_search`, `find_by_name`, `run_command`) |
| Hook deny semantic | Fail-open on hook error; deny is advisory | **Documented + fail-closed**: `{"decision":"allow"|"deny"|"ask"|"force_ask"}` |
| MCP config path | `.mcp.json` at plugin root | **`mcp_config.json`** at plugin root |
| MCP HTTP URL key | `"url"` | **`"serverUrl"`** |
| MCP OAuth shape | `oauth.clientId` + `oauth.callbackPort` | **`oauth.clientId` + `oauth.clientSecret`** (or UI flow for DCR servers; redirect URI `https://antigravity.google/oauth-callback`) |
| MCP ADC support | n/a | **`authProviderType: "google_credentials"`** |
| Config file path | `~/.claude/aria-knowledge.local.md` | **`~/.gemini/antigravity/aria-knowledge.local.md`** |
| Global plugin install | `~/.claude/plugins/` | **`~/.gemini/config/plugins/`** |
| Workspace plugin install | n/a | **`.agents/plugins/` or `_agents/plugins/`** |
| Workspace skills path | n/a (Claude Code uses plugin-bundled skills) | **`.agents/skills/<folder>/SKILL.md`** (workspace) or plugin-bundled `skills/` |
| Global rules path | n/a (CLAUDE.md files) | **`~/.gemini/GEMINI.md`** (global) or `.agents/rules/*.md` (workspace) |
| Install command | `/plugin install` (or copy to `~/.claude/plugins/`) | **`/plugin marketplace add <github>`** + **`/plugin install <plugin-name>`** |
| jq dependency | not required | **required** (for stdin-JSON parsing in wrappers) |

---

## Architecture: Why the wrapper layer

ARIA's canonical bash hook scripts in `plugin-claude-code/bin/` use Claude Code conventions: `${CLAUDE_PLUGIN_ROOT}`, `CLAUDE_TOOL_NAME`, `CLAUDE_TARGET_FILE`, etc. Antigravity exposes none of these — context comes in as stdin JSON.

Two architectural choices were available:

1. **Rewrite the canonical scripts** to parse stdin JSON natively. Adds Antigravity-specific code paths to the canonical, breaks single-source-of-truth across ports.
2. **Insert a thin wrapper layer** that reads stdin JSON, sets the env vars the canonical scripts expect, and execs them. Canonical scripts stay unchanged.

The port chose **(2)**. The wrappers live at `bin/antigravity/`; the canonical scripts at `bin/`. The shared lib `lib-antigravity-input.sh` handles the JSON-to-env translation. This means a canonical script bug fix in `plugin-claude-code/bin/` automatically propagates to Antigravity at next `build.sh` run.

---

## Retired hooks

| Hook | Canonical script | Reason retired |
|---|---|---|
| `SessionStart` | `session-start-check.sh` | Not a per-turn event; Antigravity has no SessionStart event. Behavior moved to `GEMINI.md` (loaded once per session by Antigravity). |
| `PreCompact` | `pre-compact-check.sh` | Not a per-turn event; Antigravity has no PreCompact event. Behavior moved to `/snapshot` skill (manual; reads `transcriptPath` from any hook stdin). |
| `PostCompact` | `post-compact-check.sh` | Same reason as PreCompact. Session-ledger re-emission moved to `GEMINI.md` text. |
| `TaskCreated` | `task-context-check.sh` | Not a per-turn event; Antigravity has no TaskCreated equivalent. Knowledge-file surfacing moved into skills that dispatch subagents (`/distill`, `/codemap`). |

The canonical scripts are **not copied** to `plugin-antigravity/bin/` by `build.sh` (PreCompact + PostCompact case in the `for` loop). They remain in canonical `plugin-claude-code/bin/` for Claude Code use.

---

## MCP-consuming skills (v2.18.0+)

All 5 ship at full strength in this port:

| Skill | `~~category` | Read/Write | Status |
|---|---|---|---|
| `/clip-thread` | `~~chat` OR `~~email` | Read | Full |
| `/extract-doc` | `~~docs` | Read | Full |
| `/meeting-notes` | `~~docs` (paste fallback) | Read | Full |
| `/sync-decisions` | `~~docs` | **Write** | Full — ADR-016 Rule 22 advisory preamble preserved verbatim |
| `/digest` | All 4 categories | Read | Full composite rollup |

---

## Pending sync items

_(none as of v2.19.2 — initial Antigravity port)_

When canonical drifts, add one line per item: `[date] [skill or file]: [description of drift]`.

---

## Version history

| Port version | Canonical synced from | Date | Notes |
|---|---|---|---|
| 2.19.2 | `plugin/` @ v2.19.2 | 2026-05-24 | Initial Antigravity port. Prior draft (`plugin-antigravity.archive-2026-05-24-draft/`) was built on incorrect contract assumptions; this is the verified rebuild. |
```

- [ ] **Step 2: Commit**

```bash
git add plugin-antigravity/PORTING.md
git commit -m "docs(antigravity): add PORTING.md drift log

Documents every divergence from canonical plugin/, the wrapper
architecture rationale, retired hooks, and version history."
```

---

## Task 17: Write README.md

**Files:**
- Create: `plugin-antigravity/README.md`

- [ ] **Step 1: Compose**

Create `plugin-antigravity/README.md`:

```markdown
# aria-knowledge — Antigravity Port

This is the Antigravity 2.0 port of [aria-knowledge](https://github.com/mikeprasad/aria-knowledge) v2.19.2.

Targets **Antigravity IDE** (VS Code fork) and **Antigravity CLI** (`agy`) from a single plugin install. The Antigravity 2.0 Agent Manager desktop app is out of scope (different paradigm — see `PORTING.md` and the design guide at `docs/ARIA Knowledge v2.19.2 — Antigravity Port Guide (Verified).md`).

## Install

```sh
# Inside Antigravity (IDE or CLI):
/plugin marketplace add mikeprasad/aria-knowledge
/plugin install aria-knowledge
```

Then run `/setup` inside Antigravity to configure your knowledge folder. This creates `~/.gemini/antigravity/aria-knowledge.local.md` and the knowledge folder scaffold.

## Manual install (advanced)

If you don't have a published marketplace entry, manually place the plugin into Antigravity's plugin discovery paths:

```sh
# Global install (active across all workspaces):
cp -R plugin-antigravity ~/.gemini/config/plugins/aria-knowledge

# OR workspace install (only active in the current project):
mkdir -p .agents/plugins/
cp -R plugin-antigravity .agents/plugins/aria-knowledge
```

Restart Antigravity. Open the Customizations panel — `aria-knowledge` should appear.

## Requirements

- **`jq`** — required by the hook wrappers for stdin-JSON parsing. Install via `brew install jq` (macOS) or `apt-get install jq` (Linux).
- **`bash`** — required by all hook scripts.

If `jq` is missing, every hook fails closed with a deny-and-reason. Install before first use.

## What's included

| Component | Path | Purpose |
|---|---|---|
| Plugin manifest | `plugin.json` | Marker file identifying this dir as a plugin |
| Hooks | `hooks.json` + `bin/antigravity/` | 4 per-turn hooks (3 PreToolUse + 1 PostToolUse) |
| Hook wrappers | `bin/antigravity/*.sh` | Translate Antigravity stdin JSON to ARIA canonical env vars |
| MCP servers | `mcp_config.json` | 12 servers (Slack, Linear, Notion, Atlassian, etc.) — HTTP transport with `serverUrl` |
| Session-lifecycle rules | `GEMINI.md` | One-time-per-session behaviors (audit cadence, knowledge surfacing) |
| Skills | `skills/<name>/SKILL.md` × 30 | All ARIA commands (`/setup`, `/extract`, `/handoff`, `/audit-knowledge`, etc.) |
| Knowledge template | `template/` | Knowledge folder scaffold; copied to `knowledge_folder` on `/setup` |

## What's NOT included

- **SessionStart / PreCompact / PostCompact / TaskCreated hooks** — Antigravity has no equivalent events. Their behaviors moved to `GEMINI.md` (session-start logic) or to user-invoked skills (`/snapshot`, `/wrapup`).
- **`${CLAUDE_PLUGIN_ROOT}` env var** — derived from `BASH_SOURCE` inside `lib-antigravity-input.sh`.
- **AGENTS.md** — Antigravity uses `GEMINI.md` instead.

## Build / update

This port is assembled from canonical `plugin/` by `build.sh`. Run after any `plugin/` update:

```sh
bash plugin-antigravity/build.sh
```

Hand-authored files (`plugin.json`, `hooks.json`, `mcp_config.json`, `GEMINI.md`, `bin/antigravity/*`, this README, `PORTING.md`, `SMOKE-TEST.md`) are preserved; only `skills/`, `template/`, and `bin/*.sh` (the canonical scripts) are regenerated.

## Testing

```sh
bats plugin-antigravity/tests/
```

Tests cover the shared lib + 4 wrappers. Smoke test in actual Antigravity is documented separately in `SMOKE-TEST.md` (manual; can't be automated without an Antigravity install in CI).

## See also

- [PORTING.md](PORTING.md) — full drift log + adaptation notes
- [SMOKE-TEST.md](SMOKE-TEST.md) — manual test plan for first install in Antigravity
- [../docs/ARIA Knowledge v2.19.2 — Antigravity Port Guide (Verified).md](../docs/ARIA%20Knowledge%20v2.19.2%20%E2%80%94%20Antigravity%20Port%20Guide%20%28Verified%29.md) — design rationale
- [../docs/superpowers/plans/2026-05-24-antigravity-port-full-implementation.md](../docs/superpowers/plans/2026-05-24-antigravity-port-full-implementation.md) — the implementation plan this directory was built from
```

- [ ] **Step 2: Commit**

```bash
git add plugin-antigravity/README.md
git commit -m "docs(antigravity): add README with install + build instructions

Covers marketplace install, manual install (workspace + global),
requirements (jq + bash), build script usage, and pointers to
PORTING.md / SMOKE-TEST.md / design guide."
```

---

## Task 18: Write SMOKE-TEST.md (Manual Test Plan)

**Files:**
- Create: `plugin-antigravity/SMOKE-TEST.md`

- [ ] **Step 1: Compose**

Create `plugin-antigravity/SMOKE-TEST.md`:

```markdown
# SMOKE-TEST.md — Manual Test Plan for First Install

The wrapper-layer logic has bats unit tests (run via `bats plugin-antigravity/tests/`), but Antigravity itself can't be installed in CI. This plan documents the manual smoke-test sequence to run on first install in a real Antigravity environment.

## Setup

1. Install Antigravity IDE or Antigravity CLI on your machine (5 days new as of 2026-05-24 — see `https://antigravity.google/docs/`).
2. Install `jq` and verify: `jq --version` returns a version.
3. Clear any prior probe state:
   ```sh
   rm -f ~/.gemini/antigravity/.aria-probe-fired ~/aria-antigravity-probe.log ~/.gemini/antigravity/aria-knowledge-scope-check.log
   ```
4. Install the plugin (manual method):
   ```sh
   cp -R /Users/mikeprasad/Projects/aria/aria-knowledge/plugin-antigravity ~/.gemini/config/plugins/aria-knowledge
   ```
5. Restart Antigravity.

## Test 1: Plugin Discovery

**Action:** Open Antigravity. Navigate to the Customizations panel (the "..." dropdown at the top of the agent side panel).

**Expected:** `aria-knowledge` appears in the plugin list.

**If fails:** Check `~/.gemini/config/plugins/aria-knowledge/plugin.json` exists and is valid JSON.

## Test 2: Probe-Hook Fires

**Action:** In a fresh chat, ask Antigravity to edit any file (e.g., "create a hello.txt with the text 'hi'").

**Expected:**
- `~/aria-antigravity-probe.log` is created with the runtime env dump.
- `~/.gemini/antigravity/.aria-probe-fired` exists (the suppression flag).
- The agent sees a reason message: *"aria-knowledge probe-hook fired; see ~/aria-antigravity-probe.log..."*
- The file edit completes successfully (probe doesn't deny).

**If fails:** Read `~/aria-antigravity-probe.log` if it exists. Check Antigravity's hook log for wrapper errors. Verify `jq` is on PATH.

**On success:** Inspect the probe log to verify:
- Is `${CLAUDE_PLUGIN_ROOT}` derived correctly (matches actual plugin install path)?
- What env vars does Antigravity expose? (Any `AGY_*`, `ANTIGRAVITY_*`, or `GEMINI_*`?)
- What's the CWD when hooks invoke? (Is it the plugin root, or somewhere else?)
- Are the stdin payload fields what `/docs/hooks` says they are?

Findings inform OQ-1, OQ-2, OQ-3 closure in the design guide.

## Test 3: GEMINI.md Loads at Session Start

**Action:** Open a fresh chat session. Ask: *"What's aria-knowledge?"*

**Expected:** Agent responds with knowledge of the five-phase lifecycle, mentions Rule 22, and offers `/setup`. This proves `GEMINI.md` is being read.

**If fails:** Verify GEMINI.md is being loaded by Antigravity. May need to copy it to `~/.gemini/GEMINI.md` (global) or `.agents/rules/aria-knowledge.md` (workspace) depending on plugin-scope handling.

## Test 4: PreToolUse Hook Fires on Edit

**Action:** Ask the agent to edit a file. Watch the agent log.

**Expected:**
- `pre-edit-aria.sh` runs.
- The canonical `pre-edit-check.sh` (via the wrapper) emits a Rule 22 marker reminder if appropriate.
- The agent receives an `allow` decision and proceeds.
- `~/.gemini/antigravity/aria-knowledge-scope-check.log` gets a new entry after the edit completes (PostToolUse).

**If fails:** Check the probe log for the CWD assumption. The relative path `./bin/antigravity/pre-edit-aria.sh` in `hooks.json` requires Antigravity to set CWD to the plugin root. If CWD is different, paths in `hooks.json` must change to absolute (or use `${CLAUDE_PLUGIN_ROOT}` if that env var IS exposed).

## Test 5: MCP Connect

**Action:** From the Customizations panel, open the MCP Store and connect Linear (or any MCP that supports OAuth).

**Expected:** The Linear server appears in the MCP list and authenticates via the UI flow.

**If fails:** Inspect `~/.gemini/antigravity/mcp_config.json` is being read. Check Antigravity's MCP log for connection errors.

## Test 6: Skill Invocation

**Action:** Type `/setup` in the agent chat.

**Expected:** The `/setup` skill runs through its config-creation wizard and writes `~/.gemini/antigravity/aria-knowledge.local.md`.

**If fails:** Verify `skills/setup/SKILL.md` is in the plugin install path. Check Antigravity recognizes plugin-bundled skills (vs only `.agents/skills/`).

## Reporting

After running the full sequence, update `PORTING.md` "Open Questions" section with empirical findings:

- OQ-1 (hook event names): confirmed via Test 4
- OQ-2 (env var availability): confirmed via Test 2 probe log
- OQ-3 (CWD assumption): confirmed via Test 4 + probe log
- IDE-vs-CLI: re-test the full sequence in the other surface; document any divergence.
```

- [ ] **Step 2: Commit**

```bash
git add plugin-antigravity/SMOKE-TEST.md
git commit -m "docs(antigravity): add SMOKE-TEST.md manual test plan

6 tests covering plugin discovery, probe-hook fire, GEMINI.md
loading, PreToolUse hook firing, MCP connect, and skill invocation.
Closes OQ-1/2/3 empirically on first real install."
```

---

## Self-Review Checklist

Run these checks before declaring the plan complete:

- [ ] **Spec coverage:** Every locked decision (D1-D8) has at least one task implementing it. Map:
  - D1 (wrapper architecture) → Tasks 4, 5, 6, 7, 8
  - D2 (4 hook entries) → Task 9
  - D3 (one-time logic in GEMINI.md) → Task 11
  - D4 (PreCompact/PostCompact retired) → Tasks 14 (build.sh skip) + 16 (PORTING.md)
  - D5 (TaskCreated retired) → Task 16 (PORTING.md documents the disposition)
  - D6 (archive prior draft) → Task 1
  - D7 (canonical scripts stay in plugin-claude-code/bin) → Task 14 (build.sh copies them in, doesn't move)
  - D8 (jq hard dep) → Tasks 4 (lib emits deny if missing) + 17 (README documents) + 18 (smoke test verifies)
- [ ] **Placeholder scan:** Search for `TBD`, `TODO`, `fill in`, "appropriate error handling", "similar to":
  ```bash
  grep -nE 'TBD|TODO|fill in|appropriate error|similar to Task' docs/superpowers/plans/2026-05-24-antigravity-port-full-implementation.md
  ```
  Expected: no output.
- [ ] **Type consistency:** Function names (`aria_emit_decision`), env var names (`CLAUDE_PLUGIN_ROOT`, `ARIA_TOOL_NAME`), file paths (`~/.gemini/antigravity/aria-knowledge.local.md`) are spelled identically across all tasks.
- [ ] **Test coverage:** Tasks 4-8 each have a bats test before implementation (TDD).

---

## Execution Notes

This plan is the artifact handed to the next session. To execute:

1. Open a fresh session in `/Users/mikeprasad/Projects/aria/aria-knowledge`.
2. Run `/aria-knowledge:handoff auto` outputs from the prior session to load context.
3. Invoke `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`.
4. Work through Tasks 1-18 sequentially; commit after each task per the spec.
5. After Task 18, run `bats plugin-antigravity/tests/` to verify all wrappers pass their tests.
6. Smoke-test in actual Antigravity per `SMOKE-TEST.md` (manual; requires an Antigravity install).

Total commits expected: 18 (one per task). Total bats tests expected: 5 (one per wrapper + the lib). Total lines of plugin code expected: ~1,200 (wrappers + lib + GEMINI.md + config JSONs; the bulk of the port volume comes from the 30 copied skill files which are mechanical).
