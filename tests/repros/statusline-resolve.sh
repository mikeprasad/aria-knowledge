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
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier 2>/dev/null || true
out=$(PATH="/usr/bin:/bin" kt_resolve_account "sid-cli")
key=$(printf '%s' "$out" | cut -f1); rt=$(printf '%s' "$out" | cut -f2); em=$(printf '%s' "$out" | cut -f3)
[ "$key" = "cli-uuid-1" ] || fail "CLI key: got '$key'"
[ "$rt" = "cli" ] || fail "CLI runtime: got '$rt'"
[ "$em" = "a@example.com" ] || fail "CLI email: got '$em'"

# --- Case CLI second account (v2.24.2 multi-account no-regress) ---
cat > "$HOME/.claude.json" <<'JSON'
{"oauthAccount":{"accountUuid":"cli-uuid-2","emailAddress":"b@example.com"}}
JSON
out=$(PATH="/usr/bin:/bin" kt_resolve_account "sid-cli2"); key=$(printf '%s' "$out" | cut -f1)
[ "$key" = "cli-uuid-2" ] || fail "CLI acct2 key: got '$key'"

# --- Case Desktop via PATH (acct/org form), validated by claude-code-sessions dir ---
CCS="$HOME/Library/Application Support/Claude/claude-code-sessions"
mkdir -p "$CCS/desk-acct-9/org-7"
out=$(PATH="/x/local-agent-mode-sessions/desk-acct-9/org-7/rpm/bin:/usr/bin" kt_resolve_account "sid-desk")
key=$(printf '%s' "$out" | cut -f1); rt=$(printf '%s' "$out" | cut -f2); em=$(printf '%s' "$out" | cut -f3)
[ "$key" = "desk-acct-9" ] || fail "Desktop PATH key: got '$key'"
[ "$rt" = "desktop" ] || fail "Desktop runtime: got '$rt'"
[ -z "$em" ] || fail "Desktop email must be empty: got '$em'"

# --- Case org-not-user guard: skills-plugin/<org>/<acct> must NOT yield org ---
out=$(PATH="/x/local-agent-mode-sessions/skills-plugin/org-7/desk-acct-9/bin:/x/local-agent-mode-sessions/desk-acct-9/org-7/bin:/usr/bin" kt_resolve_account "sid-desk")
key=$(printf '%s' "$out" | cut -f1)
[ "$key" = "desk-acct-9" ] || fail "skills-plugin flip must still yield account: got '$key'"

# --- Case Desktop FS fallback: PATH parse blocked, session id under claude-code-sessions ---
echo '{"cliSessionId":"sid-fs"}' > "$CCS/desk-acct-9/org-7/local_x.json"
export CLAUDE_CODE_ENTRYPOINT=claude-desktop
out=$(PATH="/usr/bin:/bin" kt_resolve_account "sid-fs"); key=$(printf '%s' "$out" | cut -f1); rt=$(printf '%s' "$out" | cut -f2)
[ "$key" = "desk-acct-9" ] || fail "Desktop FS key: got '$key'"
[ "$rt" = "desktop" ] || fail "Desktop FS runtime: got '$rt'"

# --- Case Desktop unresolved -> degrade ---
rm -rf "$CCS"
out=$(PATH="/usr/bin:/bin" kt_resolve_account "sid-unknown"); key=$(printf '%s' "$out" | cut -f1); rt=$(printf '%s' "$out" | cut -f2)
[ "$key" = "desktop-unknown" ] || fail "degrade key: got '$key'"
[ "$rt" = "desktop-unknown" ] || fail "degrade runtime: got '$rt'"

echo "PASS statusline-resolve"
