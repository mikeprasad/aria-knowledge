#!/bin/sh
# tests/repros/session-start-single-emitter.sh — one SessionStart hook routes each message by
# audience (spec docs/superpowers/specs/2026-10-25-session-start-single-emitter-spec.md).
#
#   systemMessage                         → renders to the USER only; never reaches the model
#   hookSpecificOutput.additionalContext  → reaches the MODEL
#
# Measured 2026-10-25 on Claude Code 2.1.308 and 2.1.310 that one hook may emit both fields and
# both are honoured. Every assertion decodes the JSON with jq; none greps raw output, because a
# raw grep passes on an escaped-but-broken payload.
set -u
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DIR/plugin-claude-code/scripts/session-start-check.sh"
MANIFEST="$DIR/plugin-claude-code/.claude-plugin/plugin.json"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want '$2', got '$3'"; fi; }

TODAY=$(date +%Y-%m-%d)
mk_kf() { # $1 = dir, $2 = knowledge-audit date ('' = no log → first run), $3 = config-audit date
  mkdir -p "$1/logs" "$1/rules"
  [ -n "$2" ] && printf -- '- **Date:** %s\n' "$2" > "$1/logs/knowledge-audit-log.md"
  [ -n "$3" ] && printf -- '- **Date:** %s\n' "$3" > "$1/logs/config-audit-log.md"
  printf '## Tag Index\n### alpha\n- a.md — A\n' > "$1/index.md"
  printf '### U1 — A user rule\nBody.\n' > "$1/rules/user-rules.md"
}
mk_cfg() { # $1 = path, $2 = knowledge_folder
  printf -- '---\nknowledge_folder: %s\nautonomy: autonomous\nsession_state: true\nactive_knowledge_surfacing: true\n---\n' "$2" > "$1"
}
run() { # $1 = home, $2 = cfg, $3 = source, $4 = out file
  printf '{"session_id":"sse-%s","source":"%s"}' "$$" "$3" \
    | (cd "$TMP" && HOME="$1" KT_CONFIG="$2" sh "$HOOK" 2>/dev/null) > "$4" || true
}
sm()  { jq -r '.systemMessage // ""' "$1" 2>/dev/null; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // ""' "$1" 2>/dev/null; }
# `--` matters: a needle beginning with "-" is otherwise read as an option, grep errors, and an
# absence check answers "no" whatever the payload holds.
has() { if printf '%s' "$1" | grep -qF -- "$2"; then echo yes; else echo no; fi; }

# --- AC1: one registration; the rules script is archived -------------------------------
check "AC1 one SessionStart command" "1" \
  "$(jq '[.hooks.SessionStart[].hooks[]] | length' "$MANIFEST" 2>/dev/null)"
check "AC1 it is session-start-check.sh" "yes" \
  "$(has "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$MANIFEST" 2>/dev/null)" 'session-start-check.sh')"
check "AC1 session-start-rules.sh is no longer a live script" "no" \
  "$([ -f "$DIR/plugin-claude-code/scripts/session-start-rules.sh" ] && echo yes || echo no)"
check "AC1 it is archived, not deleted" "yes" \
  "$([ -f "$DIR/plugin-claude-code/scripts/.archived/session-start-rules.sh" ] && echo yes || echo no)"

# --- Fixtures ---------------------------------------------------------------------------
H="$TMP/home"; mkdir -p "$H/.claude"
printf '{}' > "$H/.claude/aria-statusline-state-x.json"   # makes the old banner emit TASK BUDGET
KF="$TMP/kf"; mk_kf "$KF" 2020-01-01 ""                   # nags due: old audit, no config audit
CFG="$TMP/cfg.md"; mk_cfg "$CFG" "$KF"

# First run with this HOME = first install (no rules files yet): it installs them and names them in a notice.
run "$H" "$CFG" startup "$TMP/fallback.json"
# Second run = steady state.
run "$H" "$CFG" startup "$TMP/startup.json"

# --- AC2: startup routes by audience ----------------------------------------------------
S=$(sm "$TMP/startup.json"); C=$(ctx "$TMP/startup.json")
check "AC2 banner carries the audit nag" "yes" "$(has "$S" 'Knowledge audit')"
# ⛔ An absence check on a banner that did not DECODE passes for the wrong reason: jq yields "",
# and "" contains nothing. Measured 2026-10-25 — all ten passed against the old script, whose
# banner is invalid JSON. So each absence is only credited when the banner decoded non-empty.
for h in 'RULE 22 ORDERING' 'TASK BUDGET' 'ARIA ACTIVE CONTEXT' 'SESSION STATE' 'INSIGHT CAPTURE' \
         'MEMORY PATHWAY' 'DECISION ROUTING' 'STANDING USER RULES' 'Project Picker' 'CODEMAP'; do
  if [ -z "$S" ]; then bad "AC2 banner carries no '$h'" "banner did not decode — absence unproven"
  else check "AC2 banner carries no '$h'" "no" "$(has "$S" "$h")"; fi
done
check "AC2 model context carries the ARIA CONFIG line" "yes" "$(has "$C" 'ARIA CONFIG —')"
check "AC2 config line carries session_state=true" "yes" "$(has "$C" 'session_state=true')"
check "AC2 hookEventName is SessionStart" "SessionStart" \
  "$(jq -r '.hookSpecificOutput.hookEventName // ""' "$TMP/startup.json" 2>/dev/null)"

# --- AC3: compact shows no banner, leads with the compact block ---------------------------
run "$H" "$CFG" compact "$TMP/compact.json"
check "AC3 no systemMessage on compact" "false" "$(jq 'has("systemMessage")' "$TMP/compact.json" 2>/dev/null)"
case "$(ctx "$TMP/compact.json")" in
  "ARIA WORKING RULES — still in force after compaction"*) _lead=yes ;;
  *) _lead=no ;;
esac
check "AC3 compact context leads with the rules pointer" "yes" "$_lead"
check "AC3 compact context carries ARIA CONFIG" "yes" "$(has "$(ctx "$TMP/compact.json")" 'ARIA CONFIG —')"

# --- First run (no audit log): welcome banner AND model context ---------------------------
KF1="$TMP/kf1"; mk_kf "$KF1" "" ""; CFG1="$TMP/cfg1.md"; mk_cfg "$CFG1" "$KF1"
run "$H" "$CFG1" startup "$TMP/first.json"
check "first run shows the welcome" "yes" "$(has "$(sm "$TMP/first.json")" 'ARIA Knowledge Active')"
check "first run still sends model context" "yes" "$(has "$(ctx "$TMP/first.json")" 'ARIA CONFIG —')"

# --- No nags: no banner key at all, model context still sent -----------------------------
KF2="$TMP/kf2"; mk_kf "$KF2" "$TODAY" "$TODAY"; CFG2="$TMP/cfg2.md"; mk_cfg "$CFG2" "$KF2"
run "$H" "$CFG2" startup "$TMP/quiet.json"
check "no nags → no systemMessage" "false" "$(jq 'has("systemMessage")' "$TMP/quiet.json" 2>/dev/null)"
check "no nags → model context still sent" "yes" "$(has "$(ctx "$TMP/quiet.json")" 'ARIA CONFIG —')"

# --- AC13: every arm is strict JSON -----------------------------------------------------
printf -- '---\nknowledge_folder: relative/path\n---\n' > "$TMP/cfg-err.md"
run "$H" "$TMP/cfg-err.md" startup "$TMP/err.json"
run "$H" "$TMP/does-not-exist.md" startup "$TMP/unconf.json"
for arm in fallback startup compact first quiet err unconf; do
  if [ -s "$TMP/$arm.json" ] && jq -e . "$TMP/$arm.json" >/dev/null 2>&1; then ok "AC13 $arm parses strictly"
  else bad "AC13 $arm parses strictly" "$(head -c 160 "$TMP/$arm.json" 2>/dev/null)"; fi
done
# The first run on an empty HOME installs the rules files and points the model at them. It no
# longer inlines the digest: measured 2026-10-29, a 35.3 KB inline payload reached the model as a
# ~2 KB preview that stopped before the first working rule (spec 2026-10-29-rules-changed-notice).
check "first run points the model at the installed rules" "yes" \
  "$(has "$(ctx "$TMP/fallback.json")" 'ARIA RULES REFRESHED')"
check "first run does not inline the digest body" "no" \
  "$(has "$(ctx "$TMP/fallback.json")" '- **Rule 1 —')"

# --- AC5 / AC6: CODEMAP value line, and tracked artifacts --------------------------------
# A workspace holding one configured project with a fresh CODEMAP.
WS="$TMP/ws"; mkdir -p "$WS/projx"
printf '# CODEMAP\n\n> Last updated: %s\n\n## Directory\n- a\n\n## 1. Section\n' "$TODAY" > "$WS/projx/CODEMAP.md"
CFGP="$TMP/cfgp.md"
printf -- '---\nknowledge_folder: %s\nprojects_enabled: true\nprojects_list: projx:projx\nactive_knowledge_surfacing: true\n---\n' "$KF2" > "$CFGP"
SID="sse-ta-$$"; rm -f "/tmp/aria-active-$SID"
runp() { # $1 = cwd, $2 = out
  printf '{"session_id":"%s","source":"startup"}' "$SID" \
    | (cd "$1" && HOME="$H" KT_CONFIG="$CFGP" sh "$HOOK" 2>/dev/null) > "$2" || true
}
runp "$WS" "$TMP/ws.json"
check "AC5 CODEMAP value line names the map" "yes" \
  "$(has "$(ctx "$TMP/ws.json")" 'ARIA CODEMAPS — 1 current: projx/CODEMAP.md')"
runp "$WS/projx" "$TMP/proj1.json"
check "AC6 tracked artifacts fire with a session id" "yes" \
  "$(has "$(ctx "$TMP/proj1.json")" '[aria] Loaded CODEMAP directory for projx')"
check "AC6 the ledger records the map once" "1" \
  "$(grep -c 'projx/CODEMAP.md' "/tmp/aria-active-$SID" 2>/dev/null || echo 0)"
runp "$WS/projx" "$TMP/proj2.json"
check "AC6 a second run in the same session is deduplicated" "no" \
  "$(has "$(ctx "$TMP/proj2.json")" '[aria] Loaded CODEMAP directory')"
rm -f "/tmp/aria-active-$SID"

# --- Latent defects the routing change made model-visible (retrospect 2026-10-29) --------
# (1) The CODEMAP scan takes the first 5 maps under CWD. Hidden directories are worktrees and
#     scratch copies (.wt-*), and they crowded the real maps out of the line.
WS2="$TMP/ws2"; mkdir -p "$WS2/.wt-scratch" "$WS2/realrepo"
printf '# C\n\n> Last updated: %s\n' "$TODAY" > "$WS2/.wt-scratch/CODEMAP.md"
printf '# C\n\n> Last updated: %s\n' "$TODAY" > "$WS2/realrepo/CODEMAP.md"
printf '{"session_id":"sse-cm-%s","source":"startup"}' "$$" \
  | (cd "$WS2" && HOME="$H" KT_CONFIG="$CFG2" sh "$HOOK" 2>/dev/null) > "$TMP/ws2.json" || true
CM2=$(ctx "$TMP/ws2.json" | grep '^ARIA CODEMAPS')
check "CODEMAP line names the real map" "yes" "$(has "$CM2" 'realrepo/CODEMAP.md')"
check "CODEMAP line skips hidden directories" "no" "$(has "$CM2" '.wt-scratch')"
# (2) Two tags mapped to one path (a real config does this on purpose). The tie went to
#     whichever came first; it must go to the tag named like the folder.
WS3="$TMP/ws3"; mkdir -p "$WS3/projy"
printf -- '---\nknowledge_folder: %s\nprojects_enabled: true\nauto_load_project_context: true\nprojects_list: alias:projy,projy:projy\n---\n' "$KF2" > "$TMP/cfg3.md"
printf '{"session_id":"sse-pt-%s","source":"startup"}' "$$" \
  | (cd "$WS3/projy" && HOME="$H" KT_CONFIG="$TMP/cfg3.md" sh "$HOOK" 2>/dev/null) > "$TMP/ws3.json" || true
check "tied path resolves to the tag named like the folder" "yes" \
  "$(has "$(ctx "$TMP/ws3.json")" "ARIA PROJECT — this session started inside configured project 'projy'.")"

# --- Rules-file notice (spec 2026-10-29-rules-changed-notice) ------------------------------
# Claude Code loads ~/.claude/rules/ BEFORE SessionStart hooks run, so a file the hook rewrites
# reaches this session as its previous version. The hook must say so, in the model channel.
BUNDLED="$DIR/plugin-claude-code/rules/aria-rules.md"
notice() { ctx "$1" | grep '^ARIA RULES' | head -1; }
lead() { ctx "$1" | head -1; }
KFR="$TMP/kfr"; mk_kf "$KFR" "$TODAY" "$TODAY"; CFGR="$TMP/cfgr.md"; mk_cfg "$CFGR" "$KFR"
HR="$TMP/hr"; mkdir -p "$HR/.claude"
run "$HR" "$CFGR" startup "$TMP/rn0.json"                   # installs both files
printf '\nstale line from an older release\n' >> "$HR/.claude/rules/aria-rules.md"
run "$HR" "$CFGR" startup "$TMP/rn1.json"
N1=$(notice "$TMP/rn1.json")
case "$(lead "$TMP/rn1.json")" in "ARIA RULES REFRESHED"*) _l=yes ;; *) _l=no ;; esac
check "RN1 changed digest → the notice leads the model context" "yes" "$_l"
check "RN1 the notice names the digest" "yes" "$(has "$N1" '/aria-rules.md')"
check "RN1 the notice does not name the unchanged user-rules file" "no" "$(has "$N1" 'aria-user-rules.md')"
check "RN1 the installed digest is current again" "yes" \
  "$(cmp -s "$BUNDLED" "$HR/.claude/rules/aria-rules.md" && echo yes || echo no)"
run "$HR" "$CFGR" startup "$TMP/rn2.json"
check "RN2 nothing changed → no notice" "" "$(notice "$TMP/rn2.json")"
printf '### U2 — A second user rule\nBody two.\n' >> "$KFR/rules/user-rules.md"
run "$HR" "$CFGR" startup "$TMP/rn3.json"
N3=$(notice "$TMP/rn3.json")
check "RN3 changed user rules → the notice names aria-user-rules.md" "yes" "$(has "$N3" 'aria-user-rules.md')"
check "RN3 the notice does not name the unchanged digest" "no" "$(has "$N3" '/aria-rules.md')"
printf '\nstale line\n' >> "$HR/.claude/rules/aria-rules.md"
printf '### U3 — A third user rule\nBody three.\n' >> "$KFR/rules/user-rules.md"
run "$HR" "$CFGR" startup "$TMP/rn4.json"
N4=$(notice "$TMP/rn4.json")
check "RN4 both changed → the digest is named" "yes" "$(has "$N4" '/aria-rules.md')"
check "RN4 both changed → the user rules are named" "yes" "$(has "$N4" 'aria-user-rules.md')"
H5="$TMP/h5"; mkdir -p "$H5/.claude"
run "$H5" "$CFGR" startup "$TMP/rn5.json"
N5=$(notice "$TMP/rn5.json")
check "RN5 first install → the digest is named" "yes" "$(has "$N5" '/aria-rules.md')"
check "RN5 first install → the user rules are named" "yes" "$(has "$N5" 'aria-user-rules.md')"
check "RN5 first install inlines no digest body" "no" "$(has "$(ctx "$TMP/rn5.json")" '- **Rule 1 —')"
check "RN5 first install context stays under 2,000 characters" "yes" \
  "$([ "$(ctx "$TMP/rn5.json" | wc -m | tr -d ' ')" -lt 2000 ] && echo yes || echo no)"
H6="$TMP/h6"; mkdir -p "$H6/.claude"; : > "$H6/.claude/rules"   # a FILE, so mkdir -p fails
run "$H6" "$CFGR" startup "$TMP/rn6.json"
N6=$(notice "$TMP/rn6.json")
check "RN6 unwritable → NOT INSTALLED notice" "yes" "$(has "$N6" 'ARIA RULES NOT INSTALLED')"
check "RN6 the notice names the bundled digest" "yes" "$(has "$N6" "$BUNDLED")"
check "RN6 the notice names the source user rules" "yes" "$(has "$N6" "$KFR/rules/user-rules.md")"
check "RN6 no digest body inlined" "no" "$(has "$(ctx "$TMP/rn6.json")" '- **Rule 1 —')"
printf '\nstale line\n' >> "$HR/.claude/rules/aria-rules.md"
run "$HR" "$CFGR" compact "$TMP/rn7.json"
case "$(lead "$TMP/rn7.json")" in "ARIA WORKING RULES — still in force after compaction"*) _l=yes ;; *) _l=no ;; esac
check "RN7 compact still leads with the rules pointer" "yes" "$_l"
check "RN7 compact carries the notice" "yes" "$(has "$(ctx "$TMP/rn7.json")" 'ARIA RULES REFRESHED')"
for arm in rn1 rn2 rn3 rn4 rn5 rn6 rn7; do
  if [ -s "$TMP/$arm.json" ] && jq -e . "$TMP/$arm.json" >/dev/null 2>&1; then ok "RN8 $arm parses strictly"
  else bad "RN8 $arm parses strictly" "$(head -c 160 "$TMP/$arm.json" 2>/dev/null)"; fi
  check "RN8 $arm banner never carries the notice" "no" "$(has "$(sm "$TMP/$arm.json")" 'ARIA RULES')"
done

printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
