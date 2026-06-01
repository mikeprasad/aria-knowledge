# Auto-Prospect & Auto-Retrospect Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship opt-in, per-skill-configurable (`off|nudge|run`) hooks that auto-prospect a written plan and auto-retrospect a `git push`, in the aria-knowledge Claude Code port (v2.22.2).

**Architecture:** Two new standalone POSIX-sh hook scripts in `plugin-claude-code/bin/`, each sourcing the existing `config.sh` and emitting `hookSpecificOutput.additionalContext`. Registered as two new `PostToolUse` entries in `plugin.json` (matcher `Write` for prospect; matcher `Bash` for retrospect), coexisting with the existing `PostToolUse` and `PreToolUse` hooks. Four new config keys (all default-off/conservative) parsed in `config.sh`, surfaced in `/setup`, documented in `CONFIG.md`/`README.md`. Tests are self-asserting `tests/repros/*.sh` scripts that pipe crafted hook-input JSON into the scripts and grep the output.

**Tech Stack:** POSIX `sh`, `grep`/`sed` (NO `jq` — repo convention), git, Claude Code hooks (`PostToolUse`, `tool_response.stderr`, `additionalContext`).

**Spec:** `docs/superpowers/specs/2026-06-01-auto-prospect-retrospect-hooks-design.md` (decisions A & B locked: retrospect default framing = `nudge` recommended; prospect globs exclude `docs/specs/`).

**Conventions to follow (verified in-repo):**
- Hook scripts begin `#!/bin/sh`, read `INPUT=$(cat)`, then `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; . "$SCRIPT_DIR/config.sh"`.
- Field extraction pattern: `VALUE=$(echo "$INPUT" | grep -o '"key":"[^"]*"' | head -1 | sed 's/"key":"//;s/"//')`.
- Config keys: a parse line in the frontmatter block + a `KT_X=${KT_X:-default}` default line, both in `bin/config.sh`.
- Silent no-op = `exit 0` with no stdout. Guidance = print one JSON object to stdout.
- `kt_json_escape` (already defined in `config.sh`) escapes a string for safe JSON embedding.

---

## File Structure

| File | Create/Modify | Responsibility |
|------|---------------|----------------|
| `plugin-claude-code/bin/config.sh` | Modify | Parse + default the 4 new keys |
| `plugin-claude-code/bin/post-plan-prospect-check.sh` | Create | Auto-prospect trigger (PostToolUse:Write) |
| `plugin-claude-code/bin/post-push-retrospect-check.sh` | Create | Auto-retrospect trigger (PostToolUse:Bash) |
| `plugin-claude-code/.claude-plugin/plugin.json` | Modify | Register 2 new PostToolUse entries + version bump |
| `plugin-claude-code/skills/setup/SKILL.md` | Modify | Surface the 4 keys in `/setup` |
| `plugin-claude-code/CONFIG.md` | Modify | Document the 4 keys |
| `plugin-claude-code/README.md` | Modify | Add hooks to the hook table |
| `CHANGELOG.md`, `CLAUDE.md` | Modify | Release notes + last-reviewed |
| `tests/repros/auto-prospect.sh` | Create | Prospect hook assertions |
| `tests/repros/auto-retrospect.sh` | Create | Retrospect hook assertions (parse + gates) |

---

## Task 1: Config keys

**Files:**
- Modify: `plugin-claude-code/bin/config.sh` (parse block ~lines 20-46; defaults block ~lines 47-66)

- [ ] **Step 1: Add the four parse lines** in the frontmatter-parse block, immediately after the `KT_SESSION_STATE=$(... 'session_state:' ...)` line:

```sh
  KT_AUTO_PROSPECT=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^auto_prospect:' | sed 's/^auto_prospect: *//')
  KT_AUTO_RETROSPECT=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^auto_retrospect:' | sed 's/^auto_retrospect: *//')
  KT_RETROSPECT_MIN_COMMITS=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^retrospect_min_commits:' | sed 's/^retrospect_min_commits: *//')
  KT_RETROSPECT_BRANCHES=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^retrospect_branches:' | sed 's/^retrospect_branches: *//')
```

- [ ] **Step 2: Add the four default lines** in the defaults block, immediately after the `KT_SESSION_STATE=${KT_SESSION_STATE:-false}` line:

```sh
  KT_AUTO_PROSPECT=${KT_AUTO_PROSPECT:-off}
  KT_AUTO_RETROSPECT=${KT_AUTO_RETROSPECT:-off}
  KT_RETROSPECT_MIN_COMMITS=${KT_RETROSPECT_MIN_COMMITS:-3}
  KT_RETROSPECT_BRANCHES=${KT_RETROSPECT_BRANCHES:-main,master,production}
  # Strip spaces so comma-list membership tests are exact
  KT_RETROSPECT_BRANCHES=$(printf '%s' "$KT_RETROSPECT_BRANCHES" | tr -d ' ')
```

- [ ] **Step 3: Verify the script still sources cleanly.**

Run: `sh -n plugin-claude-code/bin/config.sh && echo "syntax OK"`
Expected: `syntax OK`

- [ ] **Step 4: Verify defaults resolve with no config present.**

Run:
```sh
KT_CONFIG=/nonexistent sh -c '. plugin-claude-code/bin/config.sh; echo "$KT_AUTO_PROSPECT/$KT_AUTO_RETROSPECT/$KT_RETROSPECT_MIN_COMMITS/$KT_RETROSPECT_BRANCHES"'
```
Expected: prints nothing for the keys because the defaults block is inside the `if [ -f "$KT_CONFIG" ]` branch — confirm by instead creating a temp config (next step covers real resolution). This step only confirms no syntax/sourcing error: expected output is an empty `///` line, NOT a crash.

- [ ] **Step 5: Commit.**

```bash
git add plugin-claude-code/bin/config.sh
git commit -m "feat: add auto_prospect/auto_retrospect config keys"
```

---

## Task 2: Auto-prospect hook

**Files:**
- Create: `plugin-claude-code/bin/post-plan-prospect-check.sh`
- Create: `tests/repros/auto-prospect.sh`
- Modify: `plugin-claude-code/.claude-plugin/plugin.json`

- [ ] **Step 1: Write the failing test** at `tests/repros/auto-prospect.sh`:

```sh
#!/bin/sh
# tests/repros/auto-prospect.sh — assertions for post-plan-prospect-check.sh
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/plugin-claude-code/bin/post-plan-prospect-check.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert_contains() { # desc, haystack, needle
  if printf '%s' "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; fi
}
assert_empty() { # desc, haystack
  if [ -z "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s (got: %s)\n' "$1" "$2"; fi
}

# Config with auto_prospect: run
cat > "$TMP/run.md" <<EOF
---
knowledge_folder: $TMP/kn
auto_prospect: run
---
EOF
mkdir -p "$TMP/kn"

PLAN_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/x/docs/plans/2026-06-01-foo.md"}}'
NONPLAN_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/x/src/foo.ts"}}'
SPEC_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/x/docs/specs/2026-06-01-foo-design.md"}}'

# 1. run + plan path → injects run instruction
OUT=$(printf '%s' "$PLAN_INPUT" | KT_CONFIG="$TMP/run.md" sh "$HOOK")
assert_contains "run+plan injects /prospect" "$OUT" "/prospect file"
assert_contains "run+plan says run inline" "$OUT" "Run "

# 2. nudge + superpowers plan path → injects offer
cat > "$TMP/nudge.md" <<EOF
---
knowledge_folder: $TMP/kn
auto_prospect: nudge
---
EOF
SP_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/x/docs/superpowers/plans/2026-06-01-bar.md"}}'
OUT=$(printf '%s' "$SP_INPUT" | KT_CONFIG="$TMP/nudge.md" sh "$HOOK")
assert_contains "nudge+plan offers /prospect" "$OUT" "/prospect file"
assert_contains "nudge wording is an offer" "$OUT" "Offer"

# 3. off (default) → silent
cat > "$TMP/off.md" <<EOF
---
knowledge_folder: $TMP/kn
auto_prospect: off
---
EOF
OUT=$(printf '%s' "$PLAN_INPUT" | KT_CONFIG="$TMP/off.md" sh "$HOOK")
assert_empty "off → silent" "$OUT"

# 4. spec path (decision B: excluded) → silent even with run
OUT=$(printf '%s' "$SPEC_INPUT" | KT_CONFIG="$TMP/run.md" sh "$HOOK")
assert_empty "spec path excluded → silent" "$OUT"

# 5. non-plan path → silent
OUT=$(printf '%s' "$NONPLAN_INPUT" | KT_CONFIG="$TMP/run.md" sh "$HOOK")
assert_empty "non-plan path → silent" "$OUT"

printf '%d pass, %d fail\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run the test, verify it fails** (hook doesn't exist yet).

Run: `sh tests/repros/auto-prospect.sh`
Expected: FAIL (no such file / non-zero exit).

- [ ] **Step 3: Implement** `plugin-claude-code/bin/post-plan-prospect-check.sh`:

```sh
#!/bin/sh
# post-plan-prospect-check.sh — PostToolUse hook for Write.
# When a plan file is written and auto_prospect is nudge|run, surface an
# instruction to /prospect the plan. Decision B (2026-06-01): docs/specs/
# is intentionally NOT a trigger path (a spec is pre-plan).

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# Gate 1: configured + enabled
[ "$KT_CONFIGURED" = "true" ] || exit 0
case "$KT_AUTO_PROSPECT" in nudge|run) ;; *) exit 0 ;; esac

# Extract the written file path
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')
[ -n "$FILE_PATH" ] || exit 0

# Gate 2: plan-path glob (decision B — specs excluded)
case "$FILE_PATH" in
  */docs/plans/*.md|*/docs/superpowers/plans/*.md) ;;
  *) exit 0 ;;
esac

if [ "$KT_AUTO_PROSPECT" = "run" ]; then
  MSG="AUTO-PROSPECT (run): a plan was written at ${FILE_PATH}. Run /prospect file ${FILE_PATH} inline now, before any execution."
else
  MSG="AUTO-PROSPECT (nudge): a plan was written at ${FILE_PATH}. Offer to run /prospect file ${FILE_PATH} before execution and ask the user (do not auto-run)."
fi
MSG_ESCAPED=$(kt_json_escape "$MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$MSG_ESCAPED"
```

- [ ] **Step 4: Run the test, verify it passes.**

Run: `sh tests/repros/auto-prospect.sh`
Expected: `5 pass, 0 fail` and exit 0.

- [ ] **Step 5: Register the hook** in `plugin-claude-code/.claude-plugin/plugin.json` — add a new entry to the existing `PostToolUse` array (after the `Edit|Write → post-edit-check.sh` entry):

```json
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/bin/post-plan-prospect-check.sh",
            "timeout": 5
          }
        ]
      }
```

- [ ] **Step 6: Verify the manifest is valid JSON.**

Run: `python3 -m json.tool plugin-claude-code/.claude-plugin/plugin.json > /dev/null && echo "JSON OK"`
Expected: `JSON OK`

- [ ] **Step 7: Commit.**

```bash
git add plugin-claude-code/bin/post-plan-prospect-check.sh tests/repros/auto-prospect.sh plugin-claude-code/.claude-plugin/plugin.json
git commit -m "feat: add auto-prospect PostToolUse:Write hook"
```

---

## Task 3: Auto-retrospect hook

**Files:**
- Create: `plugin-claude-code/bin/post-push-retrospect-check.sh`
- Create: `tests/repros/auto-retrospect.sh`
- Modify: `plugin-claude-code/.claude-plugin/plugin.json`

- [ ] **Step 1: Write the failing test** at `tests/repros/auto-retrospect.sh`. NOTE the JSON `tool_response.stderr` uses literal `\n` escapes (two chars) exactly as Claude Code delivers them:

```sh
#!/bin/sh
# tests/repros/auto-retrospect.sh — assertions for post-push-retrospect-check.sh
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/plugin-claude-code/bin/post-push-retrospect-check.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert_contains() { if printf '%s' "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; fi; }
assert_empty()    { if [ -z "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s (got: %s)\n' "$1" "$2"; fi; }

# A real git repo so rev-list --count works on a real range.
REPO="$TMP/repo"; mkdir -p "$REPO"; cd "$REPO"
git init -q; git config user.email t@t; git config user.name t
echo 0 > f; git add f; git commit -qm c0
OLD=$(git rev-parse HEAD)
for i in 1 2 3 4; do echo $i > f; git add f; git commit -qm c$i; done
NEW=$(git rev-parse HEAD)
cd "$ROOT"

cfg() { cat > "$1" <<EOF
---
knowledge_folder: $TMP/kn
auto_retrospect: $2
retrospect_min_commits: ${3:-3}
retrospect_branches: ${4:-main,master,production}
---
EOF
mkdir -p "$TMP/kn"; }

# tool_response with a fast-forward summary on STDERR (4 commits, branch main)
ff_input() { printf '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"tool_response":{"stdout":"","stderr":"To github.com:x/y.git\\n   %s..%s  main -> main\\n","exit_code":0}}' "$(echo "$OLD"|cut -c1-7)" "$(echo "$NEW"|cut -c1-7)"; }

cfg "$TMP/nudge.md" nudge 3 main,master,production

# 1. nudge + 4-commit push to main → offers /retrospect with the range
OUT=$(ff_input | KT_CONFIG="$TMP/nudge.md" sh -c "cd $REPO; sh $HOOK")
assert_contains "nudge offers /retrospect range" "$OUT" "/retrospect range"
assert_contains "range carries old..new" "$OUT" "$(echo "$OLD"|cut -c1-7)..$(echo "$NEW"|cut -c1-7)"

# 2. off → silent
cfg "$TMP/off.md" off
OUT=$(ff_input | KT_CONFIG="$TMP/off.md" sh -c "cd $REPO; sh $HOOK")
assert_empty "off → silent" "$OUT"

# 3. below threshold (min_commits 10) → silent
cfg "$TMP/thresh.md" nudge 10
OUT=$(ff_input | KT_CONFIG="$TMP/thresh.md" sh -c "cd $REPO; sh $HOOK")
assert_empty "below threshold → silent" "$OUT"

# 4. off-branch (push to feature, filter=main) → silent
FEAT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git push origin feature/x"},"tool_response":{"stdout":"","stderr":"To x\\n   %s..%s  feature/x -> feature/x\\n","exit_code":0}}' "$(echo "$OLD"|cut -c1-7)" "$(echo "$NEW"|cut -c1-7)")
OUT=$(printf '%s' "$FEAT" | KT_CONFIG="$TMP/nudge.md" sh -c "cd $REPO; sh $HOOK")
assert_empty "off-branch → silent" "$OUT"

# 5. Everything up-to-date (no range line) → silent
UTD='{"tool_name":"Bash","tool_input":{"command":"git push"},"tool_response":{"stdout":"","stderr":"Everything up-to-date\n","exit_code":0}}'
OUT=$(printf '%s' "$UTD" | KT_CONFIG="$TMP/nudge.md" sh -c "cd $REPO; sh $HOOK")
assert_empty "up-to-date → silent" "$OUT"

# 6. force-push (command has --force) → silent
FORCE=$(printf '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"},"tool_response":{"stdout":"","stderr":"To x\\n + %s...%s  main -> main (forced update)\\n","exit_code":0}}' "$(echo "$OLD"|cut -c1-7)" "$(echo "$NEW"|cut -c1-7)")
OUT=$(printf '%s' "$FORCE" | KT_CONFIG="$TMP/nudge.md" sh -c "cd $REPO; sh $HOOK")
assert_empty "force-push → silent" "$OUT"

# 7. non-push Bash command → silent
NP='{"tool_name":"Bash","tool_input":{"command":"git status"},"tool_response":{"stdout":"clean","stderr":"","exit_code":0}}'
OUT=$(printf '%s' "$NP" | KT_CONFIG="$TMP/nudge.md" sh -c "cd $REPO; sh $HOOK")
assert_empty "non-push → silent" "$OUT"

printf '%d pass, %d fail\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run the test, verify it fails** (hook doesn't exist).

Run: `sh tests/repros/auto-retrospect.sh`
Expected: FAIL / non-zero exit.

- [ ] **Step 3: Implement** `plugin-claude-code/bin/post-push-retrospect-check.sh`:

```sh
#!/bin/sh
# post-push-retrospect-check.sh — PostToolUse hook for Bash.
# When a `git push` lands a real fast-forward range and auto_retrospect is
# nudge|run, surface an instruction to /retrospect the pushed range.
# Parses the range from tool_response.stderr (git push writes its summary to
# stderr). No jq — decode literal \n escapes, then grep the SHA-range line.

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# Gate 1: configured + enabled
[ "$KT_CONFIGURED" = "true" ] || exit 0
case "$KT_AUTO_RETROSPECT" in nudge|run) ;; *) exit 0 ;; esac

# Gate 2: is this a git push?
COMMAND=$(echo "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')
case "$COMMAND" in *"git push"*) ;; *) exit 0 ;; esac

# Gate 3: force-push skip. Space-wrap $COMMAND so an end-of-command flag
# (e.g. `git push origin main -f`) is caught. NOTE: the SHA-range regex
# below is the AUTHORITATIVE correctness gate (it rejects forced three-dot
# `a...b` ranges); this glob is just a cheap pre-filter — do not "tighten"
# the regex on the assumption this glob catches every force.
case " $COMMAND " in *" --force"*|*" -f "*|*" --force-with-lease"*) exit 0 ;; esac

# Decode the whole payload's literal \n escapes to real newlines, then find
# the SHA-range summary line. (..  with two-dot range = fast-forward only;
# forced pushes use ...three-dot and are already gated out above.)
DECODED=$(printf '%s' "$INPUT" | sed 's/\\n/\
/g')
SUMMARY=$(printf '%s' "$DECODED" | grep -E '[0-9a-f]{7,40}\.\.[0-9a-f]{7,40}' | head -1)
[ -n "$SUMMARY" ] || exit 0   # no range line (up-to-date / new branch) → skip

RANGE=$(printf '%s' "$SUMMARY" | grep -oE '[0-9a-f]{7,40}\.\.[0-9a-f]{7,40}' | head -1)
[ -n "$RANGE" ] || exit 0
BRANCH=$(printf '%s' "$SUMMARY" | sed -n 's/.*-> \([A-Za-z0-9._/-]*\).*/\1/p')

# Gate 4: branch filter (empty list = any branch)
if [ -n "$KT_RETROSPECT_BRANCHES" ] && [ -n "$BRANCH" ]; then
  case ",$KT_RETROSPECT_BRANCHES," in
    *",$BRANCH,"*) ;;
    *) exit 0 ;;
  esac
fi

# Gate 5: commit-count threshold (local objects still present post-push)
COUNT=$(git rev-list --count "$RANGE" 2>/dev/null)
[ -n "$COUNT" ] || exit 0
[ "$COUNT" -ge "$KT_RETROSPECT_MIN_COMMITS" ] 2>/dev/null || exit 0

if [ "$KT_AUTO_RETROSPECT" = "run" ]; then
  MSG="AUTO-RETROSPECT (run): pushed ${COUNT} commits (${RANGE}) to ${BRANCH}. Run /retrospect range ${RANGE} inline now."
else
  MSG="AUTO-RETROSPECT (nudge): pushed ${COUNT} commits (${RANGE}) to ${BRANCH}. Offer to run /retrospect range ${RANGE} and ask the user (do not auto-run)."
fi
MSG_ESCAPED=$(kt_json_escape "$MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$MSG_ESCAPED"
```

- [ ] **Step 4: Run the test, verify it passes.**

Run: `sh tests/repros/auto-retrospect.sh`
Expected: `7 pass, 0 fail` and exit 0.

- [ ] **Step 5: Register the hook** in `plugin.json` — add a new entry to the existing `PostToolUse` array (after the Write/prospect entry from Task 2):

```json
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/bin/post-push-retrospect-check.sh",
            "timeout": 5
          }
        ]
      }
```

- [ ] **Step 6: Verify the manifest is valid JSON.**

Run: `python3 -m json.tool plugin-claude-code/.claude-plugin/plugin.json > /dev/null && echo "JSON OK"`
Expected: `JSON OK`

- [ ] **Step 7: Run the full repro suite to confirm no regressions.**

Run: `sh tests/run.sh`
Expected: `SUMMARY` line with `0 suite(s) failed`.

- [ ] **Step 8: Commit.**

```bash
git add plugin-claude-code/bin/post-push-retrospect-check.sh tests/repros/auto-retrospect.sh plugin-claude-code/.claude-plugin/plugin.json
git commit -m "feat: add auto-retrospect PostToolUse:Bash hook"
```

---

## Task 4: /setup integration

**Files:**
- Modify: `plugin-claude-code/skills/setup/SKILL.md`

Follow the existing `session_state` pattern: a `>` summary bullet describing the key + default, a frontmatter writer line, and a verification-step mention.

- [ ] **Step 1: Add a config summary bullet** near the existing `Session state file` bullet (~line 172):

```markdown
> - **Auto-prospect (`auto_prospect`):** off (when `nudge`, writing a plan to `docs/plans/` or `docs/superpowers/plans/` prompts an offer to run `/prospect file <path>`; when `run`, it runs inline. `docs/specs/` is intentionally not a trigger. Change later via `auto_prospect` in `~/.claude/aria-knowledge.local.md`.)
> - **Auto-retrospect (`auto_retrospect`):** off (when `nudge` [recommended], a `git push` of ≥`retrospect_min_commits` commits to a branch in `retrospect_branches` prompts an offer to run `/retrospect range <old>..<new>`; `run` runs it inline — note the post-push session is not disposable, so `run` adds real cost. Gates: `retrospect_min_commits` default 3, `retrospect_branches` default `main,master,production`.)
```

- [ ] **Step 2: Add the four writer lines** to the `aria-knowledge.local.md` frontmatter the skill emits (near `session_state: [...]`, ~line 268):

```
auto_prospect: [off/nudge/run, default off]
auto_retrospect: [off/nudge/run, default off]
retrospect_min_commits: [integer, default 3]
retrospect_branches: [comma-list, default main,master,production]
```

- [ ] **Step 3: Add to the verification checklist** (near the `session_state` confirm line, ~line 331):

```markdown
   - `auto_prospect` / `auto_retrospect` — confirm each is `off`, `nudge`, or `run`
```

- [ ] **Step 4: Verify no broken markdown / the file still parses as a skill** (frontmatter intact):

Run: `head -5 plugin-claude-code/skills/setup/SKILL.md`
Expected: YAML frontmatter `---` / `name:` / `description:` lines unchanged.

- [ ] **Step 5: Commit.**

```bash
git add plugin-claude-code/skills/setup/SKILL.md
git commit -m "feat: surface auto_prospect/auto_retrospect keys in /setup"
```

---

## Task 5: Docs + version bump

**Files:**
- Modify: `plugin-claude-code/CONFIG.md`, `plugin-claude-code/README.md`, `CHANGELOG.md`, `CLAUDE.md`, `plugin-claude-code/.claude-plugin/plugin.json`

- [ ] **Step 1: Add four rows to the `CONFIG.md` key table** (after the `subagent_capture` rows, ~line 62):

```markdown
| `auto_prospect` | `off` \| `nudge` \| `run` | off | post-plan-prospect-check.sh |
| `auto_retrospect` | `off` \| `nudge` \| `run` | off | post-push-retrospect-check.sh |
| `retrospect_min_commits` | integer | 3 | post-push-retrospect-check.sh |
| `retrospect_branches` | comma-separated branch names | `main,master,production` | post-push-retrospect-check.sh |
```

- [ ] **Step 2: Add the two hooks to the `README.md` hook table.** First locate it:

Run: `grep -n "PostToolUse\|post-edit-check\|Hook" plugin-claude-code/README.md | head`

Then add two rows mirroring the existing format, e.g.:

```markdown
| `PostToolUse` (Write) | `post-plan-prospect-check.sh` | Offers/runs `/prospect` on a written plan (opt-in via `auto_prospect`) |
| `PostToolUse` (Bash) | `post-push-retrospect-check.sh` | Offers/runs `/retrospect` on a qualifying `git push` (opt-in via `auto_retrospect`) |
```

- [ ] **Step 3: Bump the version** in `plugin-claude-code/.claude-plugin/plugin.json` from `2.22.1` to `2.22.2`:

```json
  "version": "2.22.2",
```

- [ ] **Step 4: Add a `CHANGELOG.md` entry** at the top under a new `## v2.22.2` heading:

```markdown
## v2.22.2

- **Auto-prospect & auto-retrospect hooks (Claude Code only, opt-in, default off):**
  - `post-plan-prospect-check.sh` (PostToolUse:Write) — when `auto_prospect` is `nudge`/`run`, a plan written to `docs/plans/` or `docs/superpowers/plans/` offers/runs `/prospect file <path>`. `docs/specs/` excluded.
  - `post-push-retrospect-check.sh` (PostToolUse:Bash) — when `auto_retrospect` is `nudge`/`run`, a `git push` of ≥`retrospect_min_commits` commits to a `retrospect_branches` branch offers/runs `/retrospect range <old>..<new>`. Parses the range from `tool_response.stderr`; skips force-pushes, no-ops, below-threshold, and off-branch pushes.
  - New config keys: `auto_prospect`, `auto_retrospect`, `retrospect_min_commits`, `retrospect_branches`. Surfaced in `/setup`.
  - Other 4 ports: tracked drift (not re-synced).
```

- [ ] **Step 5: Update `CLAUDE.md` "Last reviewed" line** to reference v2.22.2 and the new hooks (one sentence, matching the existing style at the bottom of the file).

- [ ] **Step 6: Final validation — JSON valid + full suite green.**

Run: `python3 -m json.tool plugin-claude-code/.claude-plugin/plugin.json > /dev/null && sh tests/run.sh`
Expected: `JSON OK`-equivalent (no error) and `0 suite(s) failed`.

- [ ] **Step 7: Commit.**

```bash
git add plugin-claude-code/CONFIG.md plugin-claude-code/README.md CHANGELOG.md CLAUDE.md plugin-claude-code/.claude-plugin/plugin.json
git commit -m "docs: document auto-prospect/auto-retrospect hooks; bump to v2.22.2"
```

---

## Notes & Risks (from /prospect 2026-06-01)

- **`tool_response.stderr` parsing is the fragile seam.** The Task 3 fixtures cover fast-forward / up-to-date / new-branch(implicit via no-range) / force / off-branch / below-threshold / non-push. If real `git push` output differs by version/locale, the "no SUMMARY line → exit 0" guard fails safe (silent), per spec discipline.
- **`run` vs `nudge` for retrospect:** `nudge` is the recommended default in `/setup` copy because the post-push session is not disposable (asymmetric-cost finding). Both are supported.
- **Ports:** Claude Code only. Do not edit Codex/Cursor/Antigravity/Cowork in this plan.
- **Out of scope:** deploy/PR-merge retrospect triggers; per-port rollout.
