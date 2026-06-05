# Runtime-Aware + Freshness-Aware Statusline Usage Tracking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the aria-knowledge statusline usage tracking account-correct, stale-safe, and session-correct across the standalone Claude Code CLI and Claude-Desktop-hosted runtimes — without alert spam.

**Architecture:** A single canonical `kt_resolve_account` function in `config.sh` resolves the *real* session account (per-user UUID) from runtime signals — env `$PATH` → `claude-code-sessions/<acct>/<org>/` lookup → graceful degrade → `~/.claude.json` (CLI, = v2.24.2). The two in-place hooks (`usage-threshold-inject.sh`, `session-start-check.sh`) source it; the standalone-copied `statusline-meter.sh` carries a byte-identical inlined mirror (sync-tested). Per-metric guards: identity→resolver, 5h/7d→`resets_at`, context%→`session_id`+`null`-guard. `refreshInterval: 30s` keeps 5h/7d values current during idle.

**Tech Stack:** POSIX `sh`, `jq`, `date`; tests are plain-`sh` repros under `tests/repros/` (run by `tests/run.sh`). Public repo — no secrets in commits.

**Spec:** `docs/superpowers/specs/2026-06-05-runtime-aware-account-resolution-design.md` (twice-prospected). Version bump 2.24.2 → **2.24.3**.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `plugin-claude-code/bin/config.sh` | Canonical `kt_resolve_account` (sourced by both hooks) | Modify (add function) |
| `plugin-claude-code/bin/usage-threshold-inject.sh` | Read key via resolver; 5h/7d staleness guard; context session+null guard; suppress on `desktop-unknown` | Modify |
| `plugin-claude-code/bin/session-start-check.sh` | `_uk` via resolver; TASK BUDGET staleness/scope instruction | Modify |
| `plugin-claude-code/bin/statusline-meter.sh` | Inlined resolver mirror; schema (`session_id`,`runtime`,`seven_day_resets_at`); key by resolved account; email CLI-only; null-guard context | Modify |
| `plugin-claude-code/skills/statusline/SKILL.md` | Wire `refreshInterval: 30`; document runtime-aware keying | Modify |
| `plugin-claude-code/CONFIG.md` | Snapshot-field + runtime-keying doc update | Modify |
| `plugin-claude-code/.claude-plugin/plugin.json` | Version → 2.24.3 | Modify |
| `CHANGELOG.md` | 2.24.3 entry | Modify |
| `~/Projects/knowledge/projects/aria/decisions/099-*.md` | ADR-099 (two principles) | Create |
| `tests/repros/statusline-resolve-*.sh` etc. | Repro tests | Create |

**Resolver contract (referenced by all tasks):** `kt_resolve_account [session_id]` echoes three TAB-separated fields: `<key>\t<runtime>\t<email>` where `runtime ∈ {cli, desktop, desktop-unknown}`. Callers split on TAB.

---

### Task 1: Canonical `kt_resolve_account` in config.sh

**Files:**
- Modify: `plugin-claude-code/bin/config.sh` (add function near `kt_json_escape`, before the `if [ -f "$KT_CONFIG" ]` block)
- Test: `tests/repros/statusline-resolve.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/repros/statusline-resolve.sh`:

```sh
#!/bin/sh
# Repro: kt_resolve_account resolves account key + runtime across runtimes.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
CONFIG_SH="$HERE/../../plugin-claude-code/bin/config.sh"
fail() { echo "FAIL: $1"; exit 1; }

# Sandbox HOME so we never touch the real ~/.claude.json or Desktop dir.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
mkdir -p "$HOME/.claude"

# We only need the function, not the config parse. Source it.
KT_CONFIG="$HOME/.claude/aria-knowledge.local.md" . "$CONFIG_SH"

# --- Case CLI: no Desktop signals, ~/.claude.json present ---
cat > "$HOME/.claude.json" <<'JSON'
{"oauthAccount":{"accountUuid":"cli-uuid-1","emailAddress":"a@example.com"}}
JSON
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier
PATH="/usr/bin:/bin" out=$(kt_resolve_account "sid-cli")
key=$(printf '%s' "$out" | cut -f1); rt=$(printf '%s' "$out" | cut -f2); em=$(printf '%s' "$out" | cut -f3)
[ "$key" = "cli-uuid-1" ] || fail "CLI key: got '$key'"
[ "$rt" = "cli" ] || fail "CLI runtime: got '$rt'"
[ "$em" = "a@example.com" ] || fail "CLI email: got '$em'"

# --- Case CLI second account (v2.24.2 multi-account no-regress) ---
cat > "$HOME/.claude.json" <<'JSON'
{"oauthAccount":{"accountUuid":"cli-uuid-2","emailAddress":"b@example.com"}}
JSON
out=$(kt_resolve_account "sid-cli2"); key=$(printf '%s' "$out" | cut -f1)
[ "$key" = "cli-uuid-2" ] || fail "CLI acct2 key: got '$key'"

# --- Case Desktop via PATH (acct/org form), validated by claude-code-sessions dir ---
CCS="$HOME/Library/Application Support/Claude/claude-code-sessions"
mkdir -p "$CCS/desk-acct-9/org-7"
PATH="/x/local-agent-mode-sessions/desk-acct-9/org-7/rpm/bin:/usr/bin" \
  out=$(kt_resolve_account "sid-desk")
key=$(printf '%s' "$out" | cut -f1); rt=$(printf '%s' "$out" | cut -f2); em=$(printf '%s' "$out" | cut -f3)
[ "$key" = "desk-acct-9" ] || fail "Desktop PATH key: got '$key'"
[ "$rt" = "desktop" ] || fail "Desktop runtime: got '$rt'"
[ -z "$em" ] || fail "Desktop email must be empty: got '$em'"

# --- Case org-not-user guard: skills-plugin/<org>/<acct> must NOT yield org ---
PATH="/x/local-agent-mode-sessions/skills-plugin/org-7/desk-acct-9/bin:/x/local-agent-mode-sessions/desk-acct-9/org-7/bin:/usr/bin" \
  out=$(kt_resolve_account "sid-desk"); key=$(printf '%s' "$out" | cut -f1)
[ "$key" = "desk-acct-9" ] || fail "skills-plugin flip must still yield account: got '$key'"

# --- Case Desktop FS fallback: PATH parse blocked, session id under claude-code-sessions ---
echo '{"cliSessionId":"sid-fs"}' > "$CCS/desk-acct-9/org-7/local_x.json"
export CLAUDE_CODE_ENTRYPOINT=claude-desktop
PATH="/usr/bin:/bin" out=$(kt_resolve_account "sid-fs"); key=$(printf '%s' "$out" | cut -f1); rt=$(printf '%s' "$out" | cut -f2)
[ "$key" = "desk-acct-9" ] || fail "Desktop FS key: got '$key'"
[ "$rt" = "desktop" ] || fail "Desktop FS runtime: got '$rt'"

# --- Case Desktop unresolved -> degrade ---
rm -rf "$CCS"
PATH="/usr/bin:/bin" out=$(kt_resolve_account "sid-unknown"); key=$(printf '%s' "$out" | cut -f1); rt=$(printf '%s' "$out" | cut -f2)
[ "$key" = "desktop-unknown" ] || fail "degrade key: got '$key'"
[ "$rt" = "desktop-unknown" ] || fail "degrade runtime: got '$rt'"

echo "PASS statusline-resolve"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `sh tests/repros/statusline-resolve.sh`
Expected: FAIL (kt_resolve_account not defined → `kt_resolve_account: not found` non-zero exit).

- [ ] **Step 3: Add the function to `config.sh`**

Insert immediately AFTER the `kt_json_escape() { … }` definition (top of file, before `if [ -f "$KT_CONFIG" ]`):

```sh
# >>> kt_resolve_account — KEEP BYTE-IDENTICAL with the statusline-meter.sh inline mirror
# Resolves the session's account key for usage-snapshot scoping. POSIX sh, no awk
# intervals (macOS awk lacks them). Echoes TAB-separated "<key>\t<runtime>\t<email>";
# runtime in {cli, desktop, desktop-unknown}. $1 = session id (falls back to env).
kt_resolve_account() {
  _kra_sid="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
  _kra_cl="$HOME/Library/Application Support/Claude"
  _kra_acct=""; _kra_org=""

  # Tier 1: env-only PATH parse of local-agent-mode-sessions/<acct>/<org>
  _kra_oifs=$IFS; IFS=:
  for _kra_p in $PATH; do
    case "$_kra_p" in
      */local-agent-mode-sessions/*)
        _kra_seg=${_kra_p#*local-agent-mode-sessions/}
        _kra_a=${_kra_seg%%/*}
        _kra_r=${_kra_seg#*/}; _kra_b=${_kra_r%%/*}
        case "$_kra_a" in skills-plugin|'') continue ;; esac
        _kra_acct=$_kra_a; _kra_org=$_kra_b; break ;;
    esac
  done
  IFS=$_kra_oifs
  if [ -n "$_kra_acct" ] && [ -d "$_kra_cl/claude-code-sessions/$_kra_acct/$_kra_org" ]; then
    printf '%s\tdesktop\t' "$_kra_acct"; return 0
  fi

  # Desktop-hosting signal (positive, false-positive-safe)
  _kra_desktop=0
  case "${CLAUDE_CODE_ENTRYPOINT:-}" in claude-desktop) _kra_desktop=1 ;; esac
  case "${CLAUDE_CODE_EXECPATH:-}" in *claude-code-vm*|*/Claude/claude-code/*) _kra_desktop=1 ;; esac
  case "${__CFBundleIdentifier:-}" in *claudefordesktop*) _kra_desktop=1 ;; esac

  # Tier 2: authoritative FS lookup by session id — gated on Desktop signal
  if [ "$_kra_desktop" = 1 ] && [ -n "$_kra_sid" ] && [ -d "$_kra_cl/claude-code-sessions" ]; then
    _kra_hit=$(grep -rl "$_kra_sid" "$_kra_cl/claude-code-sessions" 2>/dev/null | head -1)
    if [ -n "$_kra_hit" ]; then
      _kra_acct=$(basename "$(dirname "$(dirname "$_kra_hit")")")
      printf '%s\tdesktop\t' "$_kra_acct"; return 0
    fi
  fi

  # Tier 3: Desktop but unresolved -> degrade (never assert an account)
  if [ "$_kra_desktop" = 1 ]; then
    printf 'desktop-unknown\tdesktop-unknown\t'; return 0
  fi

  # Tier 4: CLI / VS Code / API-key -> ~/.claude.json (v2.24.2 behavior, unchanged)
  _kra_uuid=""; _kra_email=""
  if command -v jq >/dev/null 2>&1 && [ -f "$HOME/.claude.json" ]; then
    _kra_uuid=$(jq -r '.oauthAccount.accountUuid // empty' "$HOME/.claude.json" 2>/dev/null)
    _kra_email=$(jq -r '.oauthAccount.emailAddress // empty' "$HOME/.claude.json" 2>/dev/null)
  fi
  printf '%s\tcli\t%s' "${_kra_uuid:-default}" "$_kra_email"
}
# <<< kt_resolve_account
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `sh tests/repros/statusline-resolve.sh`
Expected: `PASS statusline-resolve`

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/bin/config.sh tests/repros/statusline-resolve.sh
git commit -m "feat(statusline): add kt_resolve_account runtime-aware account resolver"
```

---

### Task 2: Inject hook — resolver key + 5h/7d staleness + context guard + suppress

**Files:**
- Modify: `plugin-claude-code/bin/usage-threshold-inject.sh`
- Test: `tests/repros/statusline-inject.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/repros/statusline-inject.sh`:

```sh
#!/bin/sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/../../plugin-claude-code/bin/usage-threshold-inject.sh"
fail() { echo "FAIL: $1"; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"; mkdir -p "$HOME/.claude"
cat > "$HOME/.claude.json" <<'JSON'
{"oauthAccount":{"accountUuid":"cli-uuid-1","emailAddress":"a@example.com"}}
JSON
export KT_CONFIG="$HOME/.claude/aria-knowledge.local.md"
printf -- '---\nusage_alert_threshold: 80\n---\n' > "$KT_CONFIG"
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier
PATH_KEEP=$PATH; PATH="/usr/bin:/bin"   # force CLI tier
NOW=$(date +%s); PAST=$((NOW-3600)); FUT=$((NOW+3600))
STATE="$HOME/.claude/aria-statusline-state-cli-uuid-1.json"
run() { printf '{"session_id":"%s"}' "$1" | PATH="/usr/bin:/bin" sh "$HOOK"; }

# (a) 5h over threshold, window NOT reset -> alerts
cat > "$STATE" <<JSON
{"five_hour_pct":95,"five_hour_resets_at":$FUT,"seven_day_pct":10,"context_pct":10,"session_id":"S1","written_at":"x"}
JSON
out=$(run S1); printf '%s' "$out" | grep -q "5-hour" || fail "(a) expected 5h alert; got: $out"

# (b) 5h over threshold but window already reset (now>resets_at) -> NO 5h alert
cat > "$STATE" <<JSON
{"five_hour_pct":95,"five_hour_resets_at":$PAST,"seven_day_pct":10,"context_pct":10,"session_id":"S1","written_at":"x"}
JSON
out=$(run S1); printf '%s' "$out" | grep -q "5-hour" && fail "(b) stale 5h must NOT alert; got: $out"

# (c) context over threshold, session matches -> context alert
cat > "$STATE" <<JSON
{"five_hour_pct":10,"five_hour_resets_at":$FUT,"context_pct":95,"session_id":"S1","written_at":"x"}
JSON
out=$(run S1); printf '%s' "$out" | grep -qi "context" || fail "(c) expected context alert; got: $out"

# (d) context over threshold but DIFFERENT session -> NO context alert
out=$(run S2); printf '%s' "$out" | grep -qi "context" && fail "(d) cross-session context must NOT alert; got: $out"

# (e) context null (post-/compact) -> NO context alert
cat > "$STATE" <<JSON
{"five_hour_pct":10,"five_hour_resets_at":$FUT,"context_pct":null,"session_id":"S1","written_at":"x"}
JSON
out=$(run S1); printf '%s' "$out" | grep -qi "context" && fail "(e) null context must NOT alert; got: $out"

echo "PASS statusline-inject"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `sh tests/repros/statusline-inject.sh`
Expected: FAIL on case (b) (current hook has no staleness guard, so it alerts on the reset window) or (d)/(e).

- [ ] **Step 3: Edit the hook**

**Single stdin read, single `SID` variable.** Today the hook reads `INPUT=$(cat)` at line 50 and derives `SID` at line 51 — *after* the key block (lines 33-38). The refactor must (a) read stdin exactly once, and (b) use exactly one `SID` variable feeding both the key resolver and the existing `WARNFILE`.

BEFORE (current):
```sh
ACCT_KEY="default"                                 # line 33
if [ -f "$HOME/.claude.json" ]; then               # 34
  _u=$(jq -r '.oauthAccount.accountUuid // empty' "$HOME/.claude.json" 2>/dev/null)
  [ -n "$_u" ] && ACCT_KEY="$_u"
fi
STATE="$HOME/.claude/aria-statusline-state-${ACCT_KEY}.json"   # 38
[ -f "$STATE" ] || exit 0
...
INPUT=$(cat)                                       # line 50
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)   # 51
[ -z "$SID" ] && SID="default"                     # 52
```

AFTER — move the stdin read + `SID` ABOVE the key block, then resolve the key from `SID`:
```sh
INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && SID="default"

# Resolve this session's account key via the shared runtime-aware resolver
# (handles CLI vs Claude-Desktop-hosted; see config.sh kt_resolve_account).
_resolved=$(kt_resolve_account "$SID")
ACCT_KEY=$(printf '%s' "$_resolved" | cut -f1)
RUNTIME=$(printf '%s' "$_resolved" | cut -f2)
STATE="$HOME/.claude/aria-statusline-state-${ACCT_KEY}.json"
[ -f "$STATE" ] || exit 0
```
Delete the old lines 33-38 (`ACCT_KEY` block) and the old lines 50-52 (`INPUT`/`SID`). `WARNFILE` (below) keeps using the same `SID`. There is now exactly ONE `$(cat)` and ONE `SID`.

Add the staleness + context guards. After the existing `ctx`/`five`/`five_reset`/`seven` reads, add:

```sh
seven_reset=$(jq -r '.seven_day_resets_at // empty' "$STATE" 2>/dev/null)
snap_sid=$(jq -r '.session_id // empty' "$STATE" 2>/dev/null)
ctx_raw=$(jq -r '.context_pct' "$STATE" 2>/dev/null)   # "null" if absent/compact
NOW=$(date +%s 2>/dev/null)

# 5h/7d staleness: a window already past its reset is expired -> ignore that metric.
is_expired() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ -n "$NOW" ] && [ "$NOW" -gt "$1" ]; }
is_expired "$five_reset"  && five=""
is_expired "$seven_reset" && seven=""

# context: trust only if this session AND a real measurement (not null/post-compact).
if [ "$snap_sid" != "$SID" ] || [ "$ctx_raw" = "null" ] || [ -z "$ctx_raw" ]; then
  ctx=""
fi

# Desktop-unresolved: suppress entirely (never assert an unattributable account).
[ "$RUNTIME" = "desktop-unknown" ] && exit 0
```

(`SID` here is the session id already parsed for `WARNFILE`; ensure it's parsed before these guards. The `band`/`prev_band` logic then naturally skips any metric set to "".)

- [ ] **Step 4: Run the test to verify it passes**

Run: `sh tests/repros/statusline-inject.sh`
Expected: `PASS statusline-inject`

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/bin/usage-threshold-inject.sh tests/repros/statusline-inject.sh
git commit -m "fix(statusline): runtime-aware key + 5h/7d staleness + context session/null guards in inject hook"
```

---

### Task 3: session-start-check — resolver key + TASK BUDGET staleness/scope instruction

**Files:**
- Modify: `plugin-claude-code/bin/session-start-check.sh` (the `_uk`/`USAGE_SNAP` block ~232-236 + the TASK BUDGET `MESSAGES` string)
- Test: `tests/repros/statusline-session-start.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/repros/statusline-session-start.sh`:

```sh
#!/bin/sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../../plugin-claude-code/bin/session-start-check.sh"
fail() { echo "FAIL: $1"; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"; mkdir -p "$HOME/.claude"
cat > "$HOME/.claude.json" <<'JSON'
{"oauthAccount":{"accountUuid":"cli-uuid-1"}}
JSON
export KT_CONFIG="$HOME/.claude/aria-knowledge.local.md"
printf -- '---\nknowledge_folder: %s/.claude/k\n---\n' "$HOME" > "$KT_CONFIG"
out=$(printf '{"session_id":"S1","source":"startup"}' | PATH="/usr/bin:/bin" sh "$SCRIPT" 2>/dev/null)
# Path is keyed by the resolved (CLI) account
printf '%s' "$out" | grep -q "aria-statusline-state-cli-uuid-1.json" || fail "USAGE_SNAP key not resolved: $out"
# Staleness rule taught to the agent
printf '%s' "$out" | grep -qi "resets_at" || fail "missing resets_at staleness rule"
printf '%s' "$out" | grep -qi "re-read" || fail "missing re-read-fresh directive"
printf '%s' "$out" | grep -qi "session_id" || fail "missing context session-scope rule"
echo "PASS statusline-session-start"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `sh tests/repros/statusline-session-start.sh`
Expected: FAIL (key currently from inline `_uk`; staleness/scope text absent).

- [ ] **Step 3: Edit the script**

Replace the `_uk` block (lines ~232-236) with:

```sh
# Resolve the current account's snapshot path via the shared resolver (CLI vs Desktop).
_resolved=$(kt_resolve_account)
_uk=$(printf '%s' "$_resolved" | cut -f1)
USAGE_SNAP="~/.claude/aria-statusline-state-${_uk}.json"
```

Then extend the TASK BUDGET `MESSAGES` string (append after the existing "READ it…" sentence) with the staleness/scope rule:

```sh
MESSAGES="${MESSAGES}When you read ${USAGE_SNAP}, RE-READ it fresh at decision time (do not rely on usage numbers mentioned earlier in this conversation). Treat 5-hour/7-day figures as STALE if the current time is past five_hour_resets_at/seven_day_resets_at (that window has reset — the stored % is not current). Treat context_pct as valid only if the snapshot's session_id matches this session AND context_pct is present (a null/absent value means just after /compact — unknown, not the old high value). If a figure is stale/unknown and a decision depends on it, say so and check the live status line rather than asserting the stored number. "
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `sh tests/repros/statusline-session-start.sh`
Expected: `PASS statusline-session-start`

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/bin/session-start-check.sh tests/repros/statusline-session-start.sh
git commit -m "fix(statusline): resolver key + staleness/scope rule in SessionStart TASK BUDGET"
```

---

### Task 4: Meter — inlined resolver mirror + schema + key + email-CLI-only + context null-guard + sync-test

**Files:**
- Modify: `plugin-claude-code/bin/statusline-meter.sh`
- Test: `tests/repros/statusline-meter.sh`, `tests/repros/statusline-resolver-sync.sh`

- [ ] **Step 1: Write the failing tests**

Create `tests/repros/statusline-resolver-sync.sh` (byte-equality of the inlined mirror):

```sh
#!/bin/sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BIN="$HERE/../../plugin-claude-code/bin"
fail() { echo "FAIL: $1"; exit 1; }
extract() { awk '/^# >>> kt_resolve_account/{f=1} f{print} /^# <<< kt_resolve_account/{f=0}' "$1"; }
a=$(extract "$BIN/config.sh"); b=$(extract "$BIN/statusline-meter.sh")
[ -n "$a" ] || fail "config.sh has no kt_resolve_account block"
[ -n "$b" ] || fail "statusline-meter.sh has no kt_resolve_account mirror"
[ "$a" = "$b" ] || fail "resolver mirror drifted from config.sh canonical"
echo "PASS statusline-resolver-sync"
```

Create `tests/repros/statusline-meter.sh` (snapshot schema + key + null-guard):

```sh
#!/bin/sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
METER="$HERE/../../plugin-claude-code/bin/statusline-meter.sh"
fail() { echo "FAIL: $1"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP (no jq)"; exit 0; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"; mkdir -p "$HOME/.claude"
cat > "$HOME/.claude.json" <<'JSON'
{"oauthAccount":{"accountUuid":"cli-uuid-1","emailAddress":"a@example.com"}}
JSON
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier
PAYLOAD='{"session_id":"S1","model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1780000000},"seven_day":{"used_percentage":50,"resets_at":1781000000}}}'
printf '%s' "$PAYLOAD" | PATH="/usr/bin:/bin" sh "$METER" >/dev/null
ST="$HOME/.claude/aria-statusline-state-cli-uuid-1.json"
[ -f "$ST" ] || fail "snapshot not written to resolved key"
[ "$(jq -r '.session_id' "$ST")" = "S1" ] || fail "session_id not stamped"
[ "$(jq -r '.runtime' "$ST")" = "cli" ] || fail "runtime not stamped"
[ "$(jq -r '.seven_day_resets_at' "$ST")" = "1781000000" ] || fail "seven_day_resets_at missing"
[ "$(jq -r '.account_email' "$ST")" = "a@example.com" ] || fail "CLI email should be present"

# context null payload (post-/compact) -> context_pct omitted/null
P2='{"session_id":"S1","model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1780000000}}}'
printf '%s' "$P2" | PATH="/usr/bin:/bin" sh "$METER" >/dev/null
v=$(jq -r '.context_pct // "ABSENT"' "$ST"); [ "$v" = "ABSENT" ] || fail "context_pct should be absent when payload has none; got $v"
echo "PASS statusline-meter"
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `sh tests/repros/statusline-resolver-sync.sh` → FAIL (no mirror yet).
Run: `sh tests/repros/statusline-meter.sh` → FAIL (no `session_id`/`runtime`/`seven_day_resets_at`; email always written; key still from `~/.claude.json` directly).

- [ ] **Step 3: Edit the meter**

(a) Paste the EXACT `# >>> kt_resolve_account … # <<<` block from Task 1 Step 3 near the top of `statusline-meter.sh` (after the ANSI/helper functions, before `input=$(cat)`). It must be byte-identical (the sync-test enforces this).

(b) Replace the `~/.claude.json` identity block (lines ~94-100) with:

```sh
# Resolve account via the inlined runtime-aware resolver (mirror of config.sh).
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
_resolved=$(kt_resolve_account "$sid")
acct_uuid=$(printf '%s' "$_resolved" | cut -f1)
runtime=$(printf '%s' "$_resolved" | cut -f2)
acct_email=$(printf '%s' "$_resolved" | cut -f3)   # empty unless runtime=cli
```

(c) The email segment (lines ~143-145) already guards on `[ -n "$acct_email" ]` — since the resolver returns empty email for non-CLI, no further change needed (email shows only on CLI).

(d) Snapshot key already uses `_key="${acct_uuid:-default}"` — keep. Add `runtime`, `session_id`, `seven_day_resets_at`, and make `context_pct` conditional on a non-empty `ctx_i`. In the `jq -n` snapshot builder add args + fields:

```sh
  week_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)
  # ... in the jq -n call, add: --arg seven_reset "$week_reset" --arg runtime "$runtime" --arg sid "$sid"
  #   + (if $seven_reset != "" then {seven_day_resets_at:($seven_reset|tonumber)} else {} end)
  #   + (if $runtime != "" then {runtime:$runtime} else {} end)
  #   + (if $sid != "" then {session_id:$sid} else {} end)
  # context_pct already guarded by: (if $ctx != "" then {context_pct:($ctx|tonumber)} else {} end)
  # — ensure $ctx is "" when context_window.used_percentage is null/absent (round_int already
  #   returns empty for null), so post-/compact renders omit context_pct. No extra change needed.
```

(Note: `week_reset` is already parsed at line ~93 — reuse it; do not re-parse.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/repros/statusline-resolver-sync.sh` → `PASS`
Run: `sh tests/repros/statusline-meter.sh` → `PASS`

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/bin/statusline-meter.sh tests/repros/statusline-meter.sh tests/repros/statusline-resolver-sync.sh
git commit -m "feat(statusline): meter resolver mirror + session_id/runtime/seven_day_resets_at schema + CLI-only email"
```

---

### Task 5: `/statusline` wiring — `refreshInterval: 30` + doc updates

**Files:**
- Modify: `plugin-claude-code/skills/statusline/SKILL.md` (Step 4 — the settings.json write)
- Modify: `plugin-claude-code/CONFIG.md` (snapshot-field + runtime-keying paragraph)

- [ ] **Step 1: Update SKILL.md settings write**

In the Step 4 instructions where the skill writes the `statusLine` object into `~/.claude/settings.json`, change the written object to include `refreshInterval`:

```json
"statusLine": { "type": "command", "command": "<abs path>/aria-statusline-meter.sh", "refreshInterval": 30 }
```

Add a sentence to the skill body: *"`refreshInterval: 30` re-runs the meter every 30s so the 5-hour/7-day usage values stay current even while the session is idle (it does not affect alert frequency — alerts fire on your prompt). On a refresh/repair where settings already has a `statusLine`, set `refreshInterval` to 30 if absent; preserve a user's existing higher-frequency (smaller) value."*

- [ ] **Step 2: Update CONFIG.md**

Replace the snapshot-field paragraph (the one listing `account_email, account_uuid, context_pct, …`) so it: (a) lists the new fields `runtime`, `session_id`, `seven_day_resets_at`; (b) states the key is the **resolved per-user account** (CLI: `~/.claude.json`; Desktop: `claude-code-sessions/<acct>/`); (c) notes email shows only on the CLI runtime; (d) notes the 30s `refreshInterval`.

- [ ] **Step 3: Verify no script references broke**

Run: `grep -rn "refreshInterval" plugin-claude-code/skills/statusline/SKILL.md` → shows the new wiring.
Run: `sh tests/run.sh` → all repros still PASS.

- [ ] **Step 4: Commit**

```bash
git add plugin-claude-code/skills/statusline/SKILL.md plugin-claude-code/CONFIG.md
git commit -m "feat(statusline): wire refreshInterval:30 + document runtime-aware keying"
```

---

### Task 6: Version bump + CHANGELOG

**Files:**
- Modify: `plugin-claude-code/.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Bump version**

In `plugin-claude-code/.claude-plugin/plugin.json` change `"version": "2.24.2"` → `"version": "2.24.3"`.

- [ ] **Step 2: Add CHANGELOG entry**

Prepend under the top of `CHANGELOG.md`:

```markdown
## 2.24.3 — Runtime-aware statusline account resolution + staleness guards

- **Fix:** usage tracking resolved the account from `~/.claude.json` (the CLI store), which
  is wrong when Claude Code runs hosted inside Claude Desktop — causing false/cross-account
  usage alerts. The meter, the `UserPromptSubmit` inject hook, and the SessionStart TASK
  BUDGET reader now share `kt_resolve_account`, which keys the per-user account from runtime
  signals (env `$PATH` / `claude-code-sessions/`) under Desktop and falls back to
  `~/.claude.json` for the CLI (v2.24.2 behavior preserved). Honors ADR-099.
- **Fix:** the inject hook no longer alerts on a 5-hour/7-day figure whose window has already
  reset (`now > resets_at`), and treats `context_pct` as valid only for the current session
  with a real (non-post-`/compact`) measurement.
- **Add:** `refreshInterval: 30s` keeps 5h/7d values current during idle.
- Snapshot schema gains `runtime`, `session_id`, `seven_day_resets_at`; email is shown only
  on the CLI runtime.
```

- [ ] **Step 3: Verify**

Run: `jq -r '.version' plugin-claude-code/.claude-plugin/plugin.json` → `2.24.3`

- [ ] **Step 4: Commit**

```bash
git add plugin-claude-code/.claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore(release): 2.24.3 — runtime-aware statusline account resolution"
```

---

### Task 7: ADR-099

**Files:**
- Create: `~/Projects/knowledge/projects/aria/decisions/099-account-resolution-is-runtime-specific.md`

- [ ] **Step 1: Write the ADR**

```markdown
# ADR-099: Account resolution is runtime-specific; usage metrics need attribution + freshness

**Status:** Accepted (2026-06-05) — extends/qualifies ADR-098 (per-account statusline state, v2.24.2)

## Context
The statusline meter + inject hook + SessionStart reader resolved the session account from
`~/.claude.json → .oauthAccount`. That is the standalone Claude Code CLI credential store.
When Claude Code runs hosted inside Claude Desktop, `~/.claude.json` reports the CLI login
while the real session account is the Desktop login — so ADR-098's per-account keying
partitioned on the wrong runtime's identity (false/cross-account alerts). Current docs expose
no account field in the statusline or hook payload (Rule 33-verified), and the Desktop email
lives in an encrypted store unreadable by a POSIX hook.

## Decision
**1. Account resolution is runtime-specific, not `~/.claude.json`-universal.** A shared
`kt_resolve_account` resolves the per-user account UUID from runtime signals: env `$PATH`
`local-agent-mode-sessions/<acct>/<org>` → `claude-code-sessions/<acct>/<org>/` lookup by
session id (plain folder names, NOT the encrypted store) → graceful degrade
(`desktop-unknown`, suppress) → `~/.claude.json` (CLI, preserves ADR-098). The per-user UUID
is sufficient and canonical for keying (email was only ever a display segment).

**2. A persisted usage metric is trustworthy only when attributable AND fresh, and the
attribution scope differs per metric.** 5h/7d are per-account, staleness = `now > resets_at`.
`context_pct` is per-session, attribution = `session_id` match, freshness = non-`null`
(post-`/compact` sentinel). A stale/misattributed metric degrades to "unknown" — never
surfaced (it misleads AND induces downstream confabulation).

## Consequences
- CLI multi-account behavior (ADR-098) is preserved byte-for-byte (Tier 4).
- Relies on undocumented Desktop internals (PATH layout, `claude-code-sessions/`), mitigated by
  safe degrade to the CLI path; a `runtime` field is persisted so retrospects can measure
  resolve-vs-degrade rate.
- `refreshInterval: 30s` keeps 5h/7d values current during idle (value-currency, not correctness).
- Sibling ports: `plugin-antigravity` ships the scripts but targets `~/.gemini/antigravity.json`
  with no Claude-Desktop hosting — N/A (do not port the Desktop tiers). codex/cursor/cowork
  don't ship these scripts.

## Alternatives rejected
- Read the encrypted Desktop identity store — out of bounds (hard constraint).
- Increase the render debounce — not plugin-configurable + wrong direction.
- Relocate the inject hook — no hook payload carries usage; `UserPromptSubmit` is the only
  context-injection point.
- `written_at` age-window for context — defeated by `refreshInterval` re-stamp and unnecessary
  (context is conversation-scoped, restored on resume).
```

- [ ] **Step 2: Commit** (knowledge repo is separate)

```bash
cd ~/Projects/knowledge && git add projects/aria/decisions/099-account-resolution-is-runtime-specific.md && git commit -m "docs(adr): ADR-099 runtime-specific account resolution + metric attribution/freshness"
```

---

### Task 8: Backlog close + CLAUDE.md last-reviewed + port-exemption note

**Files:**
- Modify: `~/Projects/knowledge/intake/decisions-backlog.md` (mark the 2026-06-05 entry RESOLVED → ADR-099)
- Modify: `plugin-claude-code/CLAUDE.md` (last-reviewed line → 2.24.3)
- Modify: `aria-knowledge/CLAUDE.md` (last-reviewed footer → 2.24.3 summary)

- [ ] **Step 1: Close the backlog entry**

Edit the 2026-06-05 "statusline account resolution is CLI-only…" entry: change `Status: OPEN` → `Status: RESOLVED 2026-06-05 → ADR-099 (shipped v2.24.3)`.

- [ ] **Step 2: Update CLAUDE.md footers**

In `aria-knowledge/CLAUDE.md`, update the `*Last reviewed:*` line to note v2.24.3 (runtime-aware account resolution + staleness guards + refreshInterval; ADR-099). Add a one-line port note: antigravity N/A (different cred store), codex/cursor/cowork don't ship the scripts.

- [ ] **Step 3: Run full repro suite**

Run: `sh tests/run.sh`
Expected: all suites PASS (incl. the 5 new statusline repros).

- [ ] **Step 4: Commit** (two repos)

```bash
git add plugin-claude-code/CLAUDE.md && git commit -m "docs: note v2.24.3 statusline runtime-aware keying + port exemptions"
cd ~/Projects/knowledge && git add intake/decisions-backlog.md && git commit -m "docs: close statusline-account-resolution backlog -> ADR-099"
```

---

## Post-merge verification (NOT a code step — real-runtime, cannot dogfood in-session)

The plugin modifies its own live scripts; the installed copy (`~/.claude/aria-statusline-meter.sh` + marketplace cache) won't reflect edits until `/statusline` re-run + restart. After merge, in a **fresh Claude-Desktop-hosted session**:
1. Re-run `/statusline` (refresh the copied meter + add `refreshInterval`), restart.
2. Confirm `~/.claude/aria-statusline-state-<desktop-acct-uuid>.json` is written (not the CLI uuid), `runtime: "desktop"`, no `account_email`.
3. Confirm no false 5h/7d alert after a window reset; confirm context% only reflects this session.
4. Confirm a standalone-CLI session still keys by `~/.claude.json` uuid and shows the email.

---

## Self-Review

- **Spec coverage:** §1 keying→T1/T2/T4; §1a 5h/7d staleness→T2/T3; §1b context scope/null→T2/T3/T4; §4.2 resolver→T1; §4.2 wiring (config+mirror+sync)→T1/T4; §4.4 inject→T2; §4.4b session-start→T3; §4.5 degrade→T2; §4.7 refreshInterval+null-handling→T4/T5; §7 version→T6, ADR→T7, port re-check→T7/T8, backlog/CLAUDE→T8. Real-runtime (🚫) → post-merge section. ✓ all covered.
- **Placeholder scan:** none — every code/edit step shows code or an exact string.
- **Type consistency:** resolver contract `<key>\tTAB<runtime>\tTAB<email>` used identically in T1/T2/T3/T4; field names `runtime`/`session_id`/`seven_day_resets_at`/`context_pct` consistent across meter (writer) and inject/session-start (readers).
