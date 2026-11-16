#!/bin/sh
# state-dir-model-facing.sh — 2.58.0 private state dir, Task 6 (spec D5 + gate amendments G1-1, G1-2).
#
# The hooks know where the state directory and this session's ledger are; the model does not. Every
# port whose hooks write the ledger therefore STATES both paths in a session-start value line named
# `ARIA CONFIG` (`state_dir=<dir|none> ledger=<path|none>`), and the skills read and write through the
# CLI `aria-state.sh path <name>` instead of a guessed temp path. "Stated = written" is the property
# that matters: a line naming a path no writer uses is worse than no line, because the model would
# trust it.
#
#   M1 config_line_every_source      claude-code: startup / compact / clear carry the paths; the prompt
#                                    hook writes exactly the stated ledger
#   M2 config_line_no_state          no state dir: `none`, one user-facing line at startup, none on compact
#   M3 ports_state_their_paths       Cursor, Codex, Antigravity: one `ARIA CONFIG` line each, ledger =
#                                    the path that port's own writer creates for the same input
#   M4 digest_clause                 the 59-byte clause, the 26,152-byte digest, the lock still green
#   M5 preflight_record_block        the /preflight block: no id -> no file; id -> one READY line the
#                                    commit gate accepts; an id outside [A-Za-z0-9._-] -> no marker
#   M12 skill_writes_broken_dir      /preflight block and the /extract + /audit knowledge digest lines
#                                    (Claude Code, Codex) under a broken state dir write nothing anywhere
#   M6 skills_name_no_old_location   no skill or rules surface names /tmp/aria-… or ${TMPDIR…}/aria-…
#   M7 descriptions_unchanged        (GUARD) no SKILL.md description moved since e24934f
#
# Fix round 1 (M8-M10), measured on fbe7c8e: 11 red; the 4 M8 reject rows, M8's four-copies-identical
# row and M9[X], M9[H] pass there by design (GUARD), plus M8's two instrument rows. Each of the 7 GUARDs
# was seen red under one mutation of its own (strip instead of reject, accept "/", fall back on an empty
# id, fall back past a reject, codex keyed turn_id-first, antigravity bash-cd keyed on another id, one
# drifted copy), each restored and cmp-checked.
# Measured on 77fa848: 19 arms red, 5 pass by design and are labelled — GUARD (M1's no-other-ledger,
# M4's lock, M7: non-regression, not evidence the change landed) or instrument (the 59-byte constant,
# M6's planted control: they prove the probe can fire). Hooks run from the
# repo tree with HOME, TMPDIR, KT_STATE_BASE and KT_TMP_SWEEP_ROOT all inside one scratch dir, so no
# run reads or writes the real /tmp, the real state dir or ~/.claude/rules.

DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2] got [$3]"; fi; }
has() { case $1 in *"$2"*) echo 1 ;; *) echo 0 ;; esac; }
count() { printf '%s' "$1" | awk -v n="$2" '{ while ((i = index($0, n)) > 0) { c++; $0 = substr($0, i + length(n)) } } END { print c + 0 }'; }

command -v jq >/dev/null 2>&1 || { echo "SKIP  state-dir-model-facing: jq is required"; exit 0; }

R=$(mktemp -d "${TMPDIR:-/tmp}/aria-sdmf.XXXXXX") || exit 1
R=$(cd "$R" && pwd)
trap 'chmod -R u+rwx "$R" 2>/dev/null; rm -rf "$R"' EXIT
UIDN=$(id -u)
GOOD="$R/base"; SD="$GOOD/aria-knowledge-$UIDN"
BROKEN="$R/broken"
mkdir -p "$GOOD" "$BROKEN" "$R/home/.claude" "$R/home/.gemini/antigravity" "$R/tmp" "$R/sweep"
: > "$BROKEN/aria-knowledge-$UIDN"     # a regular file at the state name: reason "not a directory"
mkdir -m 700 "$SD"
unset XDG_RUNTIME_DIR KT_HOOK_DEBUG_LOG CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID CLAUDE_SESSION_ID \
  CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier KT_SURFACE_CACHE_DIR
export HOME="$R/home" TMPDIR="$R/tmp" KT_TMP_SWEEP_ROOT="$R/sweep" KT_STATE_BASE="$GOOD"

C="$DIR/plugin-claude-code/scripts"
X="$DIR/plugin-openai-codex/bin"
U="$DIR/plugin-cursor-template/scripts/aria"
H="$DIR/plugin-antigravity/bin/antigravity/pre-invocation-aria.sh"

# Fixtures: the shared surfacing index (the prompt below fires on proj-b + payments) in a knowledge
# folder whose audit logs say audits happened, so every port takes its normal (not first-run) path.
KF="$R/kf"; P="$R/w/proj"
mkdir -p "$KF/logs" "$P"
cp "$DIR/tests/repros/fixtures/surfacing/index.md" "$KF/index.md"
printf -- '- **Date:** 2026-11-01 — audit\n' > "$KF/logs/knowledge-audit-log.md"
printf -- '- **Date:** 2026-11-01 — audit\n' > "$KF/logs/config-audit-log.md"
CFG="$R/cfg.md"
printf -- '---\nknowledge_folder: %s\nactive_knowledge_surfacing: true\nprojects_enabled: true\nprojects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c\n---\n' "$KF" > "$CFG"
export KT_CONFIG="$CFG"
Q="add the roof job to the proj-b payments tab"
DEP="projects/proj-b/deposits.md"

# run BASE OUT CMD... — CMD from cwd $P, state base BASE, stdin $R/in, stdout OUT.
run() { _rb=$1; _ro=$2; shift 2; (cd "$P" && KT_STATE_BASE="$_rb" "$@" < "$R/in" > "$_ro" 2>/dev/null); return 0; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' "$1" 2>/dev/null; }
sysmsg() { jq -r '.systemMessage // empty' "$1" 2>/dev/null; }
ledgers() { ls "$SD" 2>/dev/null | grep '^aria-active-' | tr '\n' ' '; }

# --- M1 — claude-code: every SessionStart source states the paths; the prompt hook writes that ledger --
for src in startup compact clear; do
  sid="m1-$src"
  printf '{"session_id":"%s","source":"%s"}' "$sid" "$src" > "$R/in"
  run "$GOOD" "$R/m1.json" sh "$C/session-start-check.sh"
  stated=$(has "$(ctx "$R/m1.json")" "state_dir=$SD ledger=$SD/aria-active-$sid.")
  printf '{"session_id":"%s","prompt":"%s"}' "$sid" "$Q" > "$R/in"
  run "$GOOD" "$R/m1p.json" sh "$C/prompt-context-check.sh"
  written=$( [ -f "$SD/aria-active-$sid" ] && grep -qxF "$DEP" "$SD/aria-active-$sid" && echo 1 || echo 0)
  check "M1 config_line_every_source[$src]: stated|written to the stated path" "1|1" "$stated|$written"
done
check "M1 config_line_every_source (GUARD): the prompt hook wrote no other ledger" \
  "aria-active-m1-clear aria-active-m1-compact aria-active-m1-startup " "$(ledgers)"

# --- M2 — no state directory: `none`, the reason once at startup, nothing on compact -------------------
printf '{"session_id":"m2","source":"startup"}' > "$R/in"
run "$BROKEN" "$R/m2s.json" sh "$C/session-start-check.sh"
printf '{"session_id":"m2","source":"compact"}' > "$R/in"
run "$BROKEN" "$R/m2c.json" sh "$C/session-start-check.sh"
M2LINE='ARIA: private state directory unavailable (not a directory) — hooks are running without state.'
check "M2 config_line_no_state: startup none|compact none|startup user line|compact has no systemMessage" \
  "1|1|1|0" \
  "$(has "$(ctx "$R/m2s.json")" 'state_dir=none ledger=none.')|$(has "$(ctx "$R/m2c.json")" 'state_dir=none ledger=none.')|$(has "$(sysmsg "$R/m2s.json")" "$M2LINE")|$(jq -r 'has("systemMessage")' "$R/m2c.json" 2>/dev/null | grep -c true)"

# --- M3 — Cursor, Codex, Antigravity: one ARIA CONFIG line each, naming the ledger its writer uses ----
# Every fixture carries BOTH id fields with DIFFERENT values, so a port keyed on the wrong one fails.
# U (Cursor): conversation_id is the key of prompt-capture-check.sh + prompt-context-inject.sh.
printf '{"conversation_id": "m3u-conv", "session_id": "m3u-sess", "hook_event_name": "sessionStart"}' > "$R/in"
run "$GOOD" "$R/m3u.json" sh "$U/session-start-check.sh"
um=$(jq -r '.agentMessage // empty' "$R/m3u.json" 2>/dev/null)
printf '{"conversation_id":"m3u-conv","generation_id":"g1","session_id":"m3u-sess","prompt":"%s","workspace_roots":["%s"]}' "$Q" "$P" > "$R/in"
run "$GOOD" "$R/m3uc.out" sh "$U/prompt-capture-check.sh"
printf '{"conversation_id":"m3u-conv","generation_id":"g1","session_id":"m3u-sess"}' > "$R/in"
run "$GOOD" "$R/m3ui.out" sh "$U/prompt-context-inject.sh"
check "M3 ports_state_their_paths[U]: one line|names the conversation ledger|writer wrote it" "1|1|1" \
  "$(count "$um" 'ARIA CONFIG —')|$(has "$um" "ARIA CONFIG — state_dir=$SD ledger=$SD/aria-active-m3u-conv.")|$(grep -qxF "$DEP" "$SD/aria-active-m3u-conv" 2>/dev/null && echo 1 || echo 0)"

# X (Codex): session_id is the key of codex-hook.py's session_key (turn_id is only its fallback).
printf '{"session_id":"m3x-sess","turn_id":"m3x-turn","source":"startup"}' > "$R/in"
run "$GOOD" "$R/m3x.json" sh "$X/session-start-check.sh"
xm=$(sysmsg "$R/m3x.json")
printf '{"session_id":"m3x-sess","turn_id":"m3x-turn","prompt":"%s","cwd":"%s"}' "$Q" "$P" > "$R/in"
run "$GOOD" "$R/m3xp.json" env ARIA_CODEX_PLUGIN_ROOT="$DIR/plugin-openai-codex" python3 -B "$X/codex-hook.py" user-prompt-submit
check "M3 ports_state_their_paths[X]: one line|names the session ledger|writer wrote it" "1|1|1" \
  "$(count "$xm" 'ARIA CONFIG —')|$(has "$xm" "ARIA CONFIG — state_dir=$SD ledger=$SD/aria-active-m3x-sess.")|$([ -s "$SD/aria-active-m3x-sess" ] && echo 1 || echo 0)"

# H (Antigravity PreInvocation): the sanitised conversationId is responsibility 4's key. One model call
# with invocationNum 0 runs responsibility 2 (the session-start message) and responsibility 4.
cp "$DIR/plugin-antigravity/tests/fixtures/transcript-user-input.jsonl" "$R/t.jsonl"
jq -cn --arg t "$R/t.jsonl" '{conversationId:"m3h-conv", session_id:"m3h-sess", workspacePaths:["/tmp"],
  transcriptPath:$t, artifactDirectoryPath:"/tmp/art", invocationNum:0, initialNumSteps:5}' > "$R/in"
run "$GOOD" "$R/m3h.json" bash "$H"
hm=$(jq -r '(.injectSteps // [])[0].ephemeralMessage // empty' "$R/m3h.json" 2>/dev/null)
check "M3 ports_state_their_paths[H]: one line|names the conversation ledger|writer wrote it" "1|1|1" \
  "$(count "$hm" 'ARIA CONFIG —')|$(has "$hm" "ARIA CONFIG — state_dir=$SD ledger=$SD/aria-active-m3h-conv.")|$(grep -qxF "$DEP" "$SD/aria-active-m3h-conv" 2>/dev/null && echo 1 || echo 0)"

# H's session-start tracked-artifact load records into that same ledger. Until 2.58.0 it keyed on a
# session_id, which Antigravity payloads do not carry, so it never fired; it now keys on the
# conversationId, as responsibility 4 does. (A project with a CODEMAP, matched from the cwd.)
printf '# CODEMAP\n\n## Directory\n' > "$P/CODEMAP.md"
CFGT="$R/cfg-ta.md"
printf -- '---\nknowledge_folder: %s\nactive_knowledge_surfacing: true\nprojects_enabled: true\nprojects_list: fx:proj\n---\n' "$KF" > "$CFGT"
jq -cn '{conversationId:"m3t-conv", session_id:"m3t-sess", workspacePaths:["/tmp"], transcriptPath:"/nonexistent",
  artifactDirectoryPath:"/tmp/art", invocationNum:0, initialNumSteps:5}' > "$R/in"
run "$GOOD" "$R/m3t.json" env KT_CONFIG="$CFGT" bash "$H"
check "M3 ports_state_their_paths[H tracked artifacts]: instruction|recorded in the stated ledger" "1|1" \
  "$(has "$(jq -r '(.injectSteps // [])[0].ephemeralMessage // empty' "$R/m3t.json" 2>/dev/null)" 'Loaded CODEMAP directory for fx')|$(grep -qxF "$P/CODEMAP.md" "$SD/aria-active-m3t-conv" 2>/dev/null && echo 1 || echo 0)"
rm -f "$P/CODEMAP.md"

# First-run welcome path (a knowledge folder with no audit log): U and X exit early there, and still
# state the paths.
KFW="$R/kf-welcome"; mkdir -p "$KFW"; cp "$KF/index.md" "$KFW/index.md"
CFGW="$R/cfg-welcome.md"
printf -- '---\nknowledge_folder: %s\nactive_knowledge_surfacing: true\n---\n' "$KFW" > "$CFGW"
printf '{"conversation_id": "m3w", "session_id": "m3w-sess", "source": "startup"}' > "$R/in"
run "$GOOD" "$R/m3wu.json" env KT_CONFIG="$CFGW" sh "$U/session-start-check.sh"
run "$GOOD" "$R/m3wx.json" env KT_CONFIG="$CFGW" sh "$X/session-start-check.sh"
check "M3 ports_state_their_paths[welcome]: U welcome+line|X welcome+line" "1|1|1|1" \
  "$(has "$(jq -r '.agentMessage // empty' "$R/m3wu.json" 2>/dev/null)" 'ARIA Knowledge Active')|$(has "$(jq -r '.agentMessage // empty' "$R/m3wu.json" 2>/dev/null)" "ARIA CONFIG — state_dir=$SD ledger=$SD/aria-active-m3w.")|$(has "$(sysmsg "$R/m3wx.json")" 'ARIA Knowledge Active')|$(has "$(sysmsg "$R/m3wx.json")" "ARIA CONFIG — state_dir=$SD ledger=$SD/aria-active-m3w-sess.")"

# No state dir: each port says `none` for both.
for t in U X; do
  case $t in
    U) printf '{"conversation_id": "m3b", "hook_event_name": "sessionStart"}' > "$R/in"
       run "$BROKEN" "$R/m3b.json" sh "$U/session-start-check.sh"; bm=$(jq -r '.agentMessage // empty' "$R/m3b.json" 2>/dev/null) ;;
    X) printf '{"session_id":"m3b","source":"startup"}' > "$R/in"
       run "$BROKEN" "$R/m3b.json" sh "$X/session-start-check.sh"; bm=$(sysmsg "$R/m3b.json") ;;
  esac
  check "M3 ports_state_their_paths[$t no state]: none for both" "1" "$(has "$bm" 'ARIA CONFIG — state_dir=none ledger=none.')"
done
jq -cn --arg t "$R/t.jsonl" '{conversationId:"m3b", workspacePaths:["/tmp"], transcriptPath:$t,
  artifactDirectoryPath:"/tmp/art", invocationNum:0, initialNumSteps:5}' > "$R/in"
run "$BROKEN" "$R/m3b.json" bash "$H"
check "M3 ports_state_their_paths[H no state]: none for both" "1" \
  "$(has "$(jq -r '(.injectSteps // [])[0].ephemeralMessage // empty' "$R/m3b.json" 2>/dev/null)" 'ARIA CONFIG — state_dir=none ledger=none.')"

# --- M4 — the digest clause (G1-2) ----------------------------------------------------------------------
DIGEST="$DIR/plugin-claude-code/rules/aria-rules.md"
NEWCL='Skip paths in the file named by `ledger=` in `ARIA CONFIG`.'
check "M4 digest_clause: new clause is 59 bytes (instrument)" "59" "$(printf '%s' "$NEWCL" | wc -c | tr -d ' ')"
check "M4 digest_clause: carries the new clause|drops the old ledger name|drops the ls -t warning" "1|0|0" \
  "$(grep -cF "$NEWCL" "$DIGEST")|$(grep -cF 'aria-active-$CLAUDE_CODE_SESSION_ID' "$DIGEST")|$(grep -cF 'never use `ls -t`' "$DIGEST")"
dsize=$(wc -c < "$DIGEST" | tr -d ' ')
check "M4 digest_clause: size = 26152 and within the 26198 ceiling" "26152|1" "$dsize|$([ "$dsize" -le 26198 ] && echo 1 || echo 0)"
# The per-rule lock, run as plugin-claude-code/tests/test-aria-rules-digest.sh runs it: green with no relock.
SRC="$DIR/plugin-claude-code/template/rules/working-rules.md"
LOCK="$DIR/plugin-claude-code/tests/fixtures/aria-rules.digest-lock.tsv"
. "$DIR/plugin-claude-code/tests/lib-digest-lock.sh"
dl_bad=""; dl_n=0
for n in $(cut -f1 "$LOCK" 2>/dev/null); do
  dl_n=$((dl_n + 1))
  [ "$(kt_dl_source_sha "$SRC" "$n")" = "$(awk -F'\t' -v n="$n" '$1 == n { print $2 }' "$LOCK")" ] || dl_bad="$dl_bad source:$n"
  [ "$(kt_dl_digest_sha "$DIGEST" "$n")" = "$(awk -F'\t' -v n="$n" '$1 == n { print $3 }' "$LOCK")" ] || dl_bad="$dl_bad digest:$n"
done
check "M4 digest_clause (GUARD): lock rules examined > 30|lock mismatches" "1|" "$([ "$dl_n" -gt 30 ] && echo 1 || echo 0)|$dl_bad"

# --- M5 — the /preflight record block (AC7, locally) ----------------------------------------------------
PFSKILL="$DIR/plugin-claude-code/skills/preflight/SKILL.md"
awk '/^```/ { if (inb) { if (keep) { printf "%s", buf; exit } inb = 0; buf = ""; keep = 0; next } inb = 1; next }
     inb { buf = buf $0 "\n"; if (index($0, "aria-state.sh\" path \"aria-preflight-")) keep = 1 }' "$PFSKILL" \
  | grep -v 'NOT READY' > "$R/pf-block.sh"
check "M5 preflight_record_block: the block was found (instrument)" "1" "$([ -s "$R/pf-block.sh" ] && echo 1 || echo 0)"
pf_run() { (cd "$P" && env CLAUDE_PLUGIN_ROOT="$DIR/plugin-claude-code" KT_STATE_BASE="$GOOD" "$@" sh "$R/pf-block.sh" 2>&1); }
pf_none=$(pf_run)
check "M5 preflight_record_block[no id]: refusal printed|no marker anywhere" "1|0" \
  "$(has "$pf_none" 'preflight: no session id — marker not written')|$(find "$R" -name 'aria-preflight-*' 2>/dev/null | grep -c .)"
pf_run CLAUDE_CODE_SESSION_ID=pf-x > /dev/null
check "M5 preflight_record_block[id]: one READY line in the state dir" "1|1" \
  "$(grep -c . "$SD/aria-preflight-pf-x" 2>/dev/null || echo 0)|$(grep -c '	READY$' "$SD/aria-preflight-pf-x" 2>/dev/null || echo 0)"
# The commit gate reads that marker: a code commit under preflight_gate: deny is allowed for pf-x and
# denied for a session with no marker (the positive control).
GR="$R/gitrepo"; mkdir -p "$GR"
(cd "$GR" && git init -q && printf 'x\n' > a.sh && git add a.sh) >/dev/null 2>&1
GCFG="$R/gate-cfg.md"
printf -- '---\nknowledge_folder: %s\npreflight_gate: deny\n---\n' "$KF" > "$GCFG"
gate() { printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' "$1" > "$R/in"
         (cd "$GR" && KT_STATE_BASE="$GOOD" KT_CONFIG="$GCFG" sh "$C/pre-commit-preflight-check.sh" < "$R/in" 2>/dev/null); }
check "M5 preflight_record_block: gate allows pf-x|denies an unrecorded session (control)" "0|1" \
  "$(has "$(gate pf-x)" '"deny"')|$(has "$(gate pf-none)" '"deny"')"
# Task 9 M2: the block writes a session marker only for an id the gate can read (kt_session_key_check's
# set, through `aria-state.sh key`). Before, `ab+cd` got a marker the gate never read: written, then denied.
PF_UUID="3b9e1c2a-7d4f-4e8a-9c1b-2f6d8e0a4b7c"
pf_n0=$(find "$SD" -name 'aria-preflight-*' 2>/dev/null | grep -c .)
pf_bad=$(pf_run CLAUDE_CODE_SESSION_ID='ab+cd')
check "M5 preflight_record_block[rejected id ab+cd]: refusal printed|reason printed|no new marker in the state dir|gate still denies" "1|1|$pf_n0|1" \
  "$(has "$pf_bad" 'preflight: the session id is not one the commit gate can read — marker not written')|$(has "$pf_bad" 'aria-state: session id not accepted')|$(find "$SD" -name 'aria-preflight-*' 2>/dev/null | grep -c .)|$(has "$(gate 'ab+cd')" '"deny"')"
pf_run CLAUDE_CODE_SESSION_ID="$PF_UUID" > /dev/null
check "M5 preflight_record_block[UUID]: one READY line|gate allows it" "1|0" \
  "$(grep -c '	READY$' "$SD/aria-preflight-$PF_UUID" 2>/dev/null || echo 0)|$(has "$(gate "$PF_UUID")" '"deny"')"
# Codex: the session marker follows the same rule; its per-repository marker is still written for any id
# (CHANGELOG: "On Codex it also writes a per-repository marker, even when the id is empty").
PFX="$DIR/plugin-openai-codex/skills/preflight/SKILL.md"
awk '/^```/ { if (inb) { if (keep) { printf "%s", buf; exit } inb = 0; buf = ""; keep = 0; next } inb = 1; next }
     inb { buf = buf $0 "\n"; if (index($0, "aria-state.sh\" path \"aria-preflight-")) keep = 1 }' "$PFX" \
  | grep -v 'NOT READY' > "$R/pfx-block.sh"
XB="$R/basex"; XSD="$XB/aria-knowledge-$UIDN"; mkdir -p "$XB"; mkdir -m 700 "$XSD"
pfx_run() { (cd "$GR" && env PLUGIN_ROOT="$DIR/plugin-openai-codex" KT_STATE_BASE="$XB" "$@" sh "$R/pfx-block.sh" 2>&1); }
pfx_bad=$(pfx_run CODEX_THREAD_ID='ab+cd')
check "M5 preflight_record_block[codex ab+cd]: refusal printed|no session marker|repo marker written" "1|0|1" \
  "$(has "$pfx_bad" 'preflight: the session id is not one the commit gate can read — session marker not written')|$(find "$XSD" -name 'aria-preflight-ab*' 2>/dev/null | grep -c .)|$(find "$XSD" -name 'aria-preflight-repo-*' 2>/dev/null | grep -c .)"
pfx_run CODEX_THREAD_ID="$PF_UUID" > /dev/null
check "M5 preflight_record_block[codex UUID]: session marker has one READY line" "1" \
  "$(grep -c '	READY$' "$XSD/aria-preflight-$PF_UUID" 2>/dev/null || echo 0)"
# Every port's record block checks the id through the one rule before naming the marker.
pf_ports=""
for f in "$PFSKILL" "$PFX" "$DIR/plugin-antigravity/skills/preflight/SKILL.md" "$DIR/plugin-cursor-template/.cursor/rules/aria-commands.mdc"; do
  pf_ports="$pf_ports$(grep -c 'aria-state.sh" key "$_pf_sid"' "$f")"
done
check "M5 preflight_record_block: claude|codex|antigravity|cursor blocks each check the id once" "1111" "$pf_ports"

# --- M12 — skill state writes under a BROKEN state dir (spec D3, last row) -------------------------------
# M5 runs the record block only against a healthy directory. D3 says a skill that cannot get the state
# dir says why and writes nowhere else. Two broken shapes: a file at the state name ("not a directory")
# and a directory of mode 755 ("mode not 700"). Every arm counts files under the WHOLE scratch root, so a
# fallback to any guessed path (HOME, TMPDIR, cwd) is caught. Before this, a block that fell back to
# $HOME/aria-preflight-<id> on resolver failure, or a digest line that did, left this suite green.
B755="$R/base755"; mkdir -p "$B755"; mkdir -m 755 "$B755/aria-knowledge-$UIDN"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"m12 capture"}}' > "$R/m12-cap.jsonl"
m12_n() { find "$R" -name "$1" 2>/dev/null | grep -c .; }
for m12_b in "$BROKEN|not a directory" "$B755|mode not 700"; do
  m12_base=${m12_b%%|*}; m12_why=${m12_b#*|}
  m12_out=$(cd "$P" && env CLAUDE_PLUGIN_ROOT="$DIR/plugin-claude-code" KT_STATE_BASE="$m12_base" CLAUDE_CODE_SESSION_ID=m12-id sh "$R/pf-block.sh" 2>&1)
  check "M12 preflight[$m12_why]: reason printed|no marker anywhere" "1|0" \
    "$(has "$m12_out" "aria-state: $m12_why")|$(m12_n 'aria-preflight-m12-id*')"
  m12_r0=$(m12_n 'aria-preflight-repo-*')
  m12_out=$(cd "$GR" && env PLUGIN_ROOT="$DIR/plugin-openai-codex" KT_STATE_BASE="$m12_base" CODEX_THREAD_ID=m12-xid sh "$R/pfx-block.sh" 2>&1)
  check "M12 codex preflight[$m12_why]: reason printed|no session marker|no new repo marker" "1|0|$m12_r0" \
    "$(has "$m12_out" "aria-state: $m12_why")|$(m12_n 'aria-preflight-m12-xid*')|$(m12_n 'aria-preflight-repo-*')"
done
# The digest lines of /extract and /audit knowledge (Claude Code + Codex), with the placeholders filled.
m12_i=0
for m12_f in "$DIR/plugin-claude-code/skills/extract/SKILL.md" "$DIR/plugin-claude-code/skills/audit-knowledge/SKILL.md" \
             "$DIR/plugin-openai-codex/skills/extract/SKILL.md" "$DIR/plugin-openai-codex/skills/audit-knowledge/SKILL.md"; do
  m12_port=claude-code; m12_env="CLAUDE_PLUGIN_ROOT=$DIR/plugin-claude-code"
  case $m12_f in */plugin-openai-codex/*) m12_port=codex; m12_env="PLUGIN_ROOT=$DIR/plugin-openai-codex" ;; esac
  m12_sk=$(basename "$(dirname "$m12_f")")
  grep -F 'aria-state.sh" path "aria-digest-' "$m12_f" > "$R/m12-lines"
  m12_k=0
  while IFS= read -r m12_l; do
    m12_i=$((m12_i + 1)); m12_k=$((m12_k + 1)); m12_name="m12d$m12_i.md"
    printf '%s\n' "$m12_l" | sed "s|{filename}|$m12_name|; s|{capture_path}|$R/m12-cap.jsonl|; s|{snapshot_path}|$R/m12-cap.jsonl|" > "$R/m12-d.sh"
    m12_good=$(cd "$P" && env "$m12_env" KT_STATE_BASE="$GOOD" sh "$R/m12-d.sh" 2>/dev/null)
    check "M12 $m12_port $m12_sk digest line $m12_k (control): healthy dir prints the digest path and writes it" "$SD/aria-digest-$m12_name|1" \
      "$m12_good|$([ -s "$SD/aria-digest-$m12_name" ] && echo 1 || echo 0)"
    rm -f "$SD/aria-digest-$m12_name"
    for m12_b in "$BROKEN|not a directory" "$B755|mode not 700"; do
      m12_base=${m12_b%%|*}; m12_why=${m12_b#*|}
      m12_d0=$(m12_n 'aria-digest-*'); (cd "$P" && env "$m12_env" KT_STATE_BASE="$m12_base" sh "$R/m12-d.sh" > "$R/m12-o" 2> "$R/m12-e"); m12_rc=$?
      check "M12 $m12_port $m12_sk digest line $m12_k [$m12_why]: non-zero exit|reason on stderr|nothing on stdout|no new digest anywhere" "1|1||$m12_d0" \
        "$([ "$m12_rc" -ne 0 ] && echo 1 || echo 0)|$(has "$(cat "$R/m12-e")" "aria-state: $m12_why")|$(cat "$R/m12-o")|$(m12_n 'aria-digest-*')"
    done
  done < "$R/m12-lines"
done
check "M12 digest lines examined (instrument: extract 1 + audit-knowledge 2, per port)" "6" "$m12_i"

# --- M6 — no skill or rules surface names an old state location ----------------------------------------
m6_scan() { grep -nE '/tmp/aria-|TMPDIR[^ ]*/aria-' "$@" 2>/dev/null; }
M6_FILES=$(ls "$DIR"/plugin-claude-code/skills/*/SKILL.md "$DIR"/plugin-openai-codex/skills/*/SKILL.md \
  "$DIR"/plugin-antigravity/skills/*/SKILL.md "$DIR"/plugin-antigravity/overlays/skills/*/SKILL.md \
  "$DIR"/plugin-cursor-template/.cursor/rules/*.mdc \
  "$DIR"/plugin-claude-cowork/skills/prospect/SKILL.md "$DIR"/plugin-claude-cowork/skills/retrospect/SKILL.md \
  "$DIR"/plugin-claude-code/rules/aria-rules.md "$DIR"/plugin-antigravity/rules/aria-rules.md 2>/dev/null)
m6_n=$(printf '%s\n' "$M6_FILES" | grep -c .)
printf 'a /tmp/aria-active-x\nb ${TMPDIR:-/tmp}/aria-r22-bypass-x\nc "$TMPDIR/aria-preflight-x"\nd the state directory\n' > "$R/m6-control.md"
check "M6 skills_name_no_old_location (instrument): files examined > 100|control reports exactly 3" "1|3" \
  "$([ "$m6_n" -gt 100 ] && echo 1 || echo 0)|$(m6_scan "$R/m6-control.md" | grep -c .)"
check "M6 skills_name_no_old_location: hits" "" "$(m6_scan $M6_FILES | sed "s|^$DIR/||")"

# --- M8 — one session key rule: shell kt_session_key == Python session_key_raw (fix round 1; raw text, D9) ----------------
# An id is accepted only as [A-Za-z0-9._-]+ and used UNCHANGED; anything else is no key (never a stripped
# one — stripping is not injective). The first of session_id, turn_id holding a string decides.
SK_LIB="$DIR/plugin-claude-code/scripts/lib-state-key.sh"
U36="8f14e45f-ceea-467a-9f6e-1d2c3b4a5e6f"
L200=$(awk 'BEGIN { for (i = 0; i < 40; i++) printf "a.b_-" }')
{
  printf 'uuid\t{"session_id":"%s"}\t%s\n' "$U36" "$U36"
  printf 'spaced\t{ "session_id" : "%s", "x": 1 }\t%s\n' "$U36" "$U36"
  printf 'plus\t{"session_id":"ab+cd"}\t\n'
  printf 'slash\t{"session_id":"a/b"}\t\n'
  printf 'empty\t{"session_id":""}\t\n'
  printf 'long200\t{"session_id":"%s"}\t%s\n' "$L200" "$L200"
  printf 'turn-only\t{"turn_id":"t-1"}\tt-1\n'
  printf 'no-fallback-past-a-reject\t{"session_id":"ab+cd","turn_id":"t-1"}\t\n'
  # D9 (Task 9b): the rule runs on the RAW text, never the decoded value. The JSON escapes below DECODE to
  # an accepted id but the shell sees a backslash and rejects; a duplicated key decodes to the LAST value
  # but the shell takes the FIRST textual match.
  printf '%s\t%s\t%s\n' 'escape-unicode' '{"session_id":"A\u0062c"}' ''
  printf '%s\t%s\t%s\n' 'escape-quote' '{"session_id":"ab\"cd"}' ''
  printf '%s\t%s\t%s\n' 'duplicate-first-wins' '{"session_id":"a","session_id":"b"}' 'a'
  printf '%s\t%s\t%s\n' 'spacing-colon' '{"session_id" : "x"}' 'x'
  printf '%s\t%s\t%s\n' 'non-string-is-absent' '{"session_id":123}' ''
  printf '%s\t%s\t%s\n' 'non-string-then-turn' '{"session_id":123,"turn_id":"t-1"}' 't-1'
} > "$R/sk-cases"
check "M8 session_key_parity (instrument): 200-char id is 200 bytes" "200" "$(printf '%s' "$L200" | wc -c | tr -d ' ')"
: > "$R/sk-shell"
while IFS="$(printf '\t')" read -r lab js want; do
  got=$(sh -c '. "$1"; kt_session_key "$2" session_id turn_id' _ "$SK_LIB" "$js" 2>/dev/null)
  printf '%s\t%s\n' "$lab" "$got" >> "$R/sk-shell"
  # A reject case wants "", which an absent function also prints: GUARD on fbe7c8e, not landing evidence.
  check "M8 session_key_parity[shell $lab]${want:+}$( [ -z "$want" ] && echo " (GUARD)")" "$want" "$got"
done < "$R/sk-cases"
python3 -B - "$X/codex-hook.py" "$R/sk-cases" > "$R/sk-py" 2>/dev/null <<'SKPY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("codex_hook", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
for line in open(sys.argv[2], encoding="utf-8"):
    lab, js, _want = line.rstrip("\n").split("\t")
    print(lab + "\t" + m.session_key_raw(js))
SKPY
check "M8 session_key_parity: python ran every case (instrument)" "14" "$(grep -c . "$R/sk-py")"
check "M8 session_key_parity: shell == python on every case" "" "$(diff "$R/sk-shell" "$R/sk-py")"
# M8b: the hook receives RAW BYTES on stdin. A text-mode read translates a bare CR (and CRLF) to LF, which
# the shell never does (CR is [[:space:]], not a line break): A would read '' and B would fall through to
# turn_id. Both sides are fed the same bytes through real stdin / a file.
printf '%s' '{"session_id"' > "$R/skb-A"; printf '\r:"x"}' >> "$R/skb-A"
printf '%s' '{"session_id":"a' > "$R/skb-B"; printf '\rb","turn_id":"t-1"}' >> "$R/skb-B"
printf '%s' '{"session_id":"u1"}' > "$R/skb-C"; printf '\r\n' >> "$R/skb-C"
: > "$R/skb-shell"; : > "$R/skb-py"
for c in "A	x" "B	" "C	u1"; do
  lab=${c%%	*}; want=${c#*	}
  sgot=$(sh -c '. "$1"; kt_session_key "$(cat "$2")" session_id turn_id' _ "$SK_LIB" "$R/skb-$lab" 2>/dev/null)
  pgot=$(python3 -B -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("codex_hook", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
raw, _data = m.load_input()
print(m.session_key_raw(raw))' "$X/codex-hook.py" < "$R/skb-$lab" 2>/dev/null)
  check "M8b raw_bytes_cr[shell $lab]" "$want" "$sgot"
  check "M8b raw_bytes_cr[python $lab]: stdin read keeps CR, same key as the shell" "$want" "$pgot"
done
# The arm above drives ONE copy of the helper; every port sources its own. (GUARD: identical on fbe7c8e too.)
check "M8 session_key_parity (GUARD): the four lib-state-key.sh copies are byte-identical" "1" \
  "$(cksum "$SK_LIB" "$DIR/plugin-antigravity/bin/lib-state-key.sh" "$X/lib-state-key.sh" "$U/lib-state-key.sh" \
     | awk '{ print $1, $2 }' | sort -u | wc -l | tr -d ' ')"

# Fixture for M9/M10: a project with a CODEMAP (bash-cd and the session-start tracked-artifact load
# both record it in the ledger), and the shared prompt that fires on proj-b + payments.
printf '# CODEMAP\n\n## Directory\n' > "$P/CODEMAP.md"
CFGP="$R/cfg-p.md"
printf -- '---\nknowledge_folder: %s\nactive_knowledge_surfacing: true\nprojects_enabled: true\nprojects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c,fx:proj\n---\n' "$KF" > "$CFGP"
actives() { ls "$SD" 2>/dev/null | grep '^aria-active-' | tr '\n' ' '; }
named()   { ls "$SD" 2>/dev/null | grep -cE 'ab\+cd|abcd'; }
wipe()    { rm -rf "$SD"; mkdir -m 700 "$SD"; }
ag_cd()   { jq -cn --arg c "$1" --arg cmd "cd $P" '{conversationId:$c, workspacePaths:["/tmp"], transcriptPath:"/nonexistent",
            artifactDirectoryPath:"/tmp/art", stepIdx:0, toolCall:{name:"run_command", args:{CommandLine:$cmd, Cwd:"/tmp"}}}' > "$R/in"; }
ag_inv()  { jq -cn --arg c "$1" --arg t "$R/t.jsonl" '{conversationId:$c, workspacePaths:["/tmp"], transcriptPath:$t,
            artifactDirectoryPath:"/tmp/art", invocationNum:0, initialNumSteps:5}' > "$R/in"; }
AGCD="$DIR/plugin-antigravity/bin/antigravity/bash-cd-aria.sh"
# port_run PORT ID — that port's session start (SPACED payload, both id fields where the port has two)
# and every ledger writer it has, all for one session; sets ST (the session-start text).
port_run() {
  case $1 in
    C) printf '{"session_id": "%s", "source": "startup"}' "$2" > "$R/in"
       run "$GOOD" "$R/pr.json" env KT_CONFIG="$CFGP" sh "$C/session-start-check.sh"; ST=$(ctx "$R/pr.json")
       printf '{"session_id": "%s", "prompt": "%s"}' "$2" "$Q" > "$R/in"; run "$GOOD" "$R/o" env KT_CONFIG="$CFGP" sh "$C/prompt-context-check.sh"
       printf '{"command":"cd %s","session_id":"%s"}' "$P" "$2" > "$R/in"; run "$GOOD" "$R/o" env KT_CONFIG="$CFGP" sh "$C/bash-cd-check.sh"
       printf '{"session_id":"%s","task_subject":"%s","task_description":"d"}' "$2" "$Q" > "$R/in"; run "$GOOD" "$R/o" env KT_CONFIG="$CFGP" sh "$C/task-context-check.sh" ;;
    X) printf '{"session_id": "%s", "turn_id": "%s-turn", "source": "startup"}' "$2" "$2" > "$R/in"
       run "$GOOD" "$R/pr.json" env KT_CONFIG="$CFGP" sh "$X/session-start-check.sh"; ST=$(sysmsg "$R/pr.json")
       printf '{"session_id": "%s", "turn_id": "%s-turn", "prompt": "%s", "cwd": "%s"}' "$2" "$2" "$Q" "$P" > "$R/in"
       run "$GOOD" "$R/o" env KT_CONFIG="$CFGP" ARIA_CODEX_PLUGIN_ROOT="$DIR/plugin-openai-codex" python3 -B "$X/codex-hook.py" user-prompt-submit
       printf '{"command":"cd %s","session_id":"%s","turn_id":"%s-turn"}' "$P" "$2" "$2" > "$R/in"; run "$GOOD" "$R/o" env KT_CONFIG="$CFGP" sh "$X/bash-cd-check.sh" ;;
    U) printf '{"conversation_id": "%s", "session_id": "%s-sess", "hook_event_name": "sessionStart"}' "$2" "$2" > "$R/in"
       run "$GOOD" "$R/pr.json" env KT_CONFIG="$CFGP" sh "$U/session-start-check.sh"; ST=$(jq -r '.agentMessage // empty' "$R/pr.json" 2>/dev/null)
       printf '{"conversation_id": "%s", "generation_id": "g9", "session_id": "%s-sess", "prompt": "%s", "workspace_roots": ["%s"]}' "$2" "$2" "$Q" "$P" > "$R/in"
       run "$GOOD" "$R/o" env KT_CONFIG="$CFGP" sh "$U/prompt-capture-check.sh"
       printf '{"conversation_id": "%s", "generation_id": "g9", "session_id": "%s-sess"}' "$2" "$2" > "$R/in"
       run "$GOOD" "$R/o" env KT_CONFIG="$CFGP" sh "$U/prompt-context-inject.sh"
       printf '{"command":"cd %s","conversation_id":"%s","session_id":"%s-sess"}' "$P" "$2" "$2" > "$R/in"; run "$GOOD" "$R/o" env KT_CONFIG="$CFGP" sh "$U/bash-cd-check.sh" ;;
    H) ag_inv "$2"; run "$GOOD" "$R/pr.json" env KT_CONFIG="$CFGP" bash "$H"
       ST=$(jq -r '(.injectSteps // [])[0].ephemeralMessage // empty' "$R/pr.json" 2>/dev/null)
       ag_cd "$2"; run "$GOOD" "$R/o" env KT_CONFIG="$CFGP" bash "$AGCD" ;;
  esac
}

# --- M9 — every ledger writer in a port writes ONLY the ledger that port's session start states ---------
# Spaced session-start payloads (claude-code read only the compact form and stated `none` while its
# prompt hook wrote a ledger), and two id fields with different values (Cursor's bash-cd keyed on
# session_id — a second, unstated ledger). Codex and Antigravity pass on fbe7c8e (GUARD there).
for t in C X U H; do
  wipe; port_run "$t" "m9$(printf '%s' "$t" | tr 'CXUH' 'cxuh')"
  sid="m9$(printf '%s' "$t" | tr 'CXUH' 'cxuh')"
  case $t in X|H) g=" (GUARD)" ;; *) g="" ;; esac
  check "M9 stated_eq_written_spaced[$t]$g: stated|ledgers in the state dir" "1|aria-active-$sid " \
    "$(has "$ST" "state_dir=$SD ledger=$SD/aria-active-$sid.")|$(actives)"
done

# --- M10 — an id outside [A-Za-z0-9._-]+ names nothing: ledger=none, and no file anywhere in the state dir
# carries it or its stripped form (the hooks used to strip it to `abcd`, or keep `ab+cd` raw).
for t in C X U H; do
  wipe; port_run "$t" "ab+cd"
  check "M10 invalid_id_no_state[$t]: states ledger=none|aria-active files|files named ab+cd/abcd" "1||0" \
    "$(has "$ST" 'ledger=none.')|$(actives)|$(named)"
done
rm -f "$P/CODEMAP.md"
wipe

# --- M11 — the in-progress mark under a rejected id: marked anyway (spec D3), no cache, raw id unwritten
# A rejected id is no key, so no aria-session-inprogress-* cache; the project is still marked (D3:
# "Mark anyway") with an empty session id, so SESSION.md keeps its prior sessionId — the raw id, or a
# stripped one, never reaches the front matter. A valid id is the positive control (marked under it,
# cache written). Codex's twin is plugin-openai-codex/tests test_state_name_with_slash_refused.
MK="$R/w/mk"; mkdir -p "$MK"; : > "$MK/CLAUDE.md"; : > "$MK/a.txt"
CFGS="$R/cfg-s.md"
printf -- '---\nknowledge_folder: %s\nsession_state: true\n---\n' "$KF" > "$CFGS"
mk_seed() { printf -- '---\nlastEvent: wrapup\nat: 2026-01-01T00:00:00Z\nsessionId: prior-sid\n---\nbody\n' > "$MK/SESSION.md"; }
fm() { awk 'NR==1{next} $0=="---"{exit} {print}' "$MK/SESSION.md" | grep "^$1:" | sed "s/^$1: *//"; }
for t in C U G; do
  case $t in C) pe="$C/post-edit-check.sh" ;; U) pe="$U/post-edit-check.sh" ;; G) pe="$DIR/plugin-antigravity/bin/post-edit-check.sh" ;; esac
  wipe; mk_seed
  printf '{"file_path":"%s","session_id":"ab+cd"}' "$MK/a.txt" > "$R/in"; run "$GOOD" "$R/o" env KT_CONFIG="$CFGS" sh "$pe"
  rej="$(fm lastEvent)|$(fm sessionId)|$(ls "$SD" 2>/dev/null | grep -c 'session-inprogress')|$(named)"
  wipe; mk_seed
  printf '{"file_path":"%s","session_id":"m11ok"}' "$MK/a.txt" > "$R/in"; run "$GOOD" "$R/o" env KT_CONFIG="$CFGS" sh "$pe"
  pos="$(fm lastEvent)|$(fm sessionId)|$( [ -f "$SD/aria-session-inprogress-m11ok" ] && echo 1 || echo 0)"
  check "M11 rejected_id_marks_anyway[$t]: rejected lastEvent|sessionId|caches|id-named files; valid lastEvent|sessionId|cache" \
    "in-progress|prior-sid|0|0; in-progress|m11ok|1" "$rej; $pos"
done
wipe

# --- M7 (GUARD) — no SKILL.md description changed since the base of the 2.58.0 plan ----------------------
if git -C "$DIR" rev-parse --verify -q e24934f >/dev/null 2>&1; then
  check "M7 descriptions_unchanged (GUARD)" "" \
    "$(git -C "$DIR" diff e24934f -- '*SKILL.md' 2>/dev/null | grep -E '^[-+]description:')"
else
  echo "SKIP  M7 descriptions_unchanged: e24934f not in this checkout"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
