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

## Test 7: PreInvocation Hook Behaviors

Verifies the v2.20 PreInvocation hook (`aria-pre-invocation`) restores three behavioral parities lost in the initial port.

### 7a: transcriptPath caching

**Action:** Open a fresh chat. Send any message and let the agent respond.

**Expected:** After the agent's first response, the cache file exists and contains a valid path:

```sh
cat ~/.gemini/antigravity/.last-transcript-path
```

Should output an absolute path like `/path/to/workspace/.gemini/jetski/transcript.jsonl`. The file at that path should exist.

**If fails:** PreInvocation hook didn't fire OR didn't have stdin access. Check Antigravity's hook log. Verify `bash ./bin/antigravity/pre-invocation-aria.sh` is registered in hooks.json's `aria-pre-invocation` entry. Verify `jq` is on PATH.

### 7b: artifactDirectoryPath caching

**Action:** Same as 7a — first agent response.

**Expected:**

```sh
cat ~/.gemini/antigravity/.last-artifact-dir
```

Should output an absolute path to an artifacts directory (typically `/path/to/workspace/.gemini/jetski/artifacts`).

### 7c: Session-start ephemeralMessage injection

**Action:** Open a brand-new conversation. The first model invocation should have `invocationNum: 0`. Watch the agent's first response.

**Expected:** The agent's first response should include behaviors triggered by the injected ephemeralMessage: check audit cadence, clean stale batch manifests, surface relevant knowledge based on the user's first message.

You can verify the injection happened by looking at Antigravity's trajectory log (if accessible) for an ephemeralMessage step at position 0 containing the string "[ARIA] First call of session".

**If fails:** Hook didn't fire on first call, OR `invocationNum == 0` detection didn't match, OR injectSteps output schema was wrong. Inspect the trajectory.

### 7d: Rule 22 scope-check feedback drain

**Action:**
1. Ask the agent to make any small edit to a test file.
2. Watch — the `aria-post-edit` hook fires after the edit, writing scope-check output to `~/.gemini/antigravity/aria-knowledge-scope-check.log`.
3. Continue the conversation — ask the agent to do another small task that does NOT involve editing.
4. The next model invocation should see the scope-check feedback injected as an ephemeralMessage from the drain logic.

**Expected:**
- After step 2: `cat ~/.gemini/antigravity/aria-knowledge-scope-check.log` shows a `[Rule 22 · Scope]` entry.
- After step 4 (the NEXT model call): the log file is empty (drained) and the agent's response shows awareness of the scope-check (it may comment on the prior edit's scope or proceed normally without explicit mention — but the log should be drained).

**If fails:** Either post-edit-aria didn't write the log, or pre-invocation-aria didn't drain it. Verify both wrappers are registered + executable. Verify the log file is at the exact path `~/.gemini/antigravity/aria-knowledge-scope-check.log`.

### 7e: /snapshot reads cached transcript

**Action:** After some conversation activity (so the transcript cache is warm), type `/snapshot` in the agent chat.

**Expected:** Snapshot succeeds. The output prints both the source path (from the cache) and the destination path (under `{knowledge_folder}/intake/pre-compact-captures/`).

**If fails:** Likely the cache file is missing or stale, OR `save-transcript.sh` wasn't patched correctly. Verify `grep -c 'last-transcript-path' ~/.gemini/config/plugins/aria-knowledge/bin/save-transcript.sh` returns at least 1.

## Reporting

After running the full sequence, update `PORTING.md` "Open Questions" section with empirical findings:

- OQ-1 (hook event names): confirmed via Test 4
- OQ-2 (env var availability): confirmed via Test 2 probe log
- OQ-3 (CWD assumption): confirmed via Test 4 + probe log
- v2.20 PreInvocation behaviors (transcript cache, artifact cache, session-start injection, scope-check drain, /snapshot integration): all 5 confirmed via Test 7a-7e
- IDE-vs-CLI: re-test the full sequence in the other surface; document any divergence.
