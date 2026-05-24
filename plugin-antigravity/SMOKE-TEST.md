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
