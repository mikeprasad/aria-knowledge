#!/bin/sh
# Repro: /snapshot (save-transcript.sh) captures the INVOKING session's transcript,
# identified by session id — never "the newest *.jsonl under ~/.claude/projects".
#
# Founding defect (reproduced 2026-08-15 and 2026-10-11): with several Claude Code
# sessions live, the helper copied whichever transcript was written most recently —
# another session's — and still printed "saved" with exit 0. The fixture below makes
# a FOREIGN transcript the newest file on purpose; any recency-based pick fails it.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../../plugin-claude-code/bin/save-transcript.sh"
fail() { echo "FAIL: $1"; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP"
mkdir -p "$HOME/.claude/k"
export KT_CONFIG="$HOME/.claude/aria-knowledge.local.md"
printf -- '---\nknowledge_folder: %s/.claude/k\n---\n' "$HOME" > "$KT_CONFIG"
CAPS="$HOME/.claude/k/intake/pre-compact-captures"

MINE=aaaaaaaa-1111-4111-8111-111111111111
OTHER=bbbbbbbb-2222-4222-8222-222222222222
P="$HOME/.claude/projects/-Users-x-Projects"
mkdir -p "$P/$MINE/subagents" "$P/vercel-plugin"
echo '{"who":"mine"}'  > "$P/$MINE.jsonl"
sleep 1
echo '{"who":"other"}' > "$P/$OTHER.jsonl"          # foreign session, NEWER than mine
sleep 1
echo '{"who":"subagent"}' > "$P/$MINE/subagents/agent-x.jsonl"   # newer still, not a session
echo '{"who":"plugin"}'   > "$P/vercel-plugin/skill-injections.jsonl"  # newest, not a session

run() { out=$(sh "$SCRIPT" "$@" 2>&1); rc=$?; }
reset_caps() { rm -rf "$CAPS"; }

# A. The env var names this session: copy MY transcript even though others are newer.
reset_caps
CLAUDE_CODE_SESSION_ID=$MINE run
[ "$rc" -eq 0 ] || fail "A: exit $rc: $out"
snap=$(ls "$CAPS"/*_aaaaaaaa.md 2>/dev/null | head -1)
[ -n "$snap" ] || fail "A: no snapshot named for my session: $out"
cmp -s "$snap" "$P/$MINE.jsonl" || fail "A: snapshot content is not my transcript"
[ "$(ls "$CAPS" | wc -l | tr -d ' ')" = 1 ] || fail "A: extra files written: $(ls "$CAPS")"
printf '%s' "$out" | grep -q "GUESSED" && fail "A: warned GUESSED although the id was known"

# B. No env var, id passed as an argument (the skill's \${CLAUDE_SESSION_ID}).
reset_caps
env -u CLAUDE_CODE_SESSION_ID sh "$SCRIPT" "$MINE" > "$TMP/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] || fail "B: exit $rc: $(cat "$TMP/out")"
cmp -s "$CAPS"/*_aaaaaaaa.md "$P/$MINE.jsonl" || fail "B: arg id not honoured"

# C. Env id names a session with no transcript file (e.g. --continue startup id), but the
#    arg id is valid: fall through to the arg rather than failing or guessing.
reset_caps
CLAUDE_CODE_SESSION_ID=cccccccc-3333-4333-8333-333333333333 run "$MINE"
[ "$rc" -eq 0 ] || fail "C: exit $rc: $out"
cmp -s "$CAPS"/*_aaaaaaaa.md "$P/$MINE.jsonl" || fail "C: did not fall through to arg id"

# D. An id is known but NO transcript matches it: fail loudly, write nothing, never guess.
reset_caps
CLAUDE_CODE_SESSION_ID=cccccccc-3333-4333-8333-333333333333 run
[ "$rc" -ne 0 ] || fail "D: exited 0 with no matching transcript: $out"
[ -z "$(ls "$CAPS" 2>/dev/null)" ] || fail "D: wrote a file anyway: $(ls "$CAPS")"
printf '%s' "$out" | grep -q "cccccccc" || fail "D: error does not name the id: $out"

# E. A malformed id (path characters) is rejected, never used to build a path.
reset_caps
CLAUDE_CODE_SESSION_ID='../../etc/x' run
[ "$rc" -ne 0 ] || fail "E: accepted a malformed id: $out"
[ -z "$(ls "$CAPS" 2>/dev/null)" ] || fail "E: wrote a file for a malformed id"

# F. No id anywhere (older Claude Code): legacy newest-file pick, but only among
#    top-level SESSION transcripts — never subagent or plugin .jsonl — and it must
#    announce that it guessed.
reset_caps
env -u CLAUDE_CODE_SESSION_ID sh "$SCRIPT" > "$TMP/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] || fail "F: exit $rc: $(cat "$TMP/out")"
grep -q "GUESSED" "$TMP/out" || fail "F: no GUESSED warning: $(cat "$TMP/out")"
cmp -s "$CAPS"/*_bbbbbbbb.md "$P/$OTHER.jsonl" \
  || fail "F: legacy pick was not the newest top-level session file: $(ls "$CAPS")"

echo "PASS: snapshot-session-id (6 arms)"
