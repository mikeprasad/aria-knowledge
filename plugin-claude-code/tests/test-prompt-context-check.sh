# shellcheck shell=sh
# test-prompt-context-check.sh — scripts/prompt-context-check.sh (UserPromptSubmit surfacing hook)
#
# Sourced by tests/run.sh under `set -eu`. The whole body runs in a SUBSHELL with its own
# EXIT trap (it must delete /tmp/aria-active-<fake session id>, which the hook writes to /tmp
# regardless of TMPDIR) — a trap set at top level would replace run.sh's own cleanup trap.
# The subshell prints one `name<TAB>expected<TAB>actual` line per check; the parent replays
# them through assert_eq so the counters land in run.sh.
#
# HOME, TMPDIR and KT_SURFACE_CACHE_DIR are isolated for every hook call. Every call runs under
# a watchdog, so a hook that blocks on stdin reports `hung` instead of stalling the suite.

PCC_HOOK="$(cd "$(dirname "$0")/../scripts" && pwd)/prompt-context-check.sh"
PCC_PLUGIN_JSON="$(cd "$(dirname "$0")/.." && pwd)/.claude-plugin/plugin.json"
PCC_FIXTURE="$(cd "$(dirname "$0")/../../tests/repros/fixtures/surfacing" && pwd)/index.md"

# Defined at top level and CALLED inside $( ): bash 3.2 (macOS /bin/sh) cannot parse a `case`
# pattern's closing `)` written directly inside a command substitution.
pcc_body() {
  set +e +u
  T="${TMPDIR:-/tmp}/aria-pcc-$$"
  RUN_ID="pcc-test-$$-$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d ' ')"
  trap 'rm -rf "$T"; rm -f /tmp/aria-active-"$RUN_ID"-* 2>/dev/null' EXIT
  rm -rf "$T"; mkdir -p "$T/tmpdir" "$T/cache"

  r() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

  # --- fixture: knowledge folder + config ---------------------------------
  mk_kf() { # DIR [no-index]
    mkdir -p "$1"
    [ "${2:-}" = no-index ] || cp "$PCC_FIXTURE" "$1/index.md"
    for p in projects/proj-a/hooks.md projects/proj-b/deposits.md projects/proj-b/crew-notes.md \
             projects/proj-b/estimates.md projects/proj-c/billing-1.md references/webhook-basics.md; do
      mkdir -p "$1/${p%/*}"; printf 'PCC-BODY-SENTINEL file body for %s\n' "$p" > "$1/$p"
    done
  }
  mk_home() { # HOMEDIR KF [extra frontmatter line]
    mkdir -p "$1/.claude"
    {
      printf -- '---\nknowledge_folder: %s\nprojects_enabled: true\nprojects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c\n' "$2"
      [ -n "${3:-}" ] && printf '%s\n' "$3"
      printf -- '---\n\nSynthetic config for test-prompt-context-check.sh.\n'
    } > "$1/.claude/aria-knowledge.local.md"
  }
  KF="$T/kf"; mk_kf "$KF"
  H="$T/home"; mk_home "$H" "$KF"

  # Isolated PATH without jq: a farm of links to every tool the hook and lib run.
  NJ="$T/nojq-bin"; mkdir -p "$NJ"
  for tool in sh bash cat cksum awk sed tr sort grep mktemp wc cut head mv rm cp dirname date od env; do
    tp=$(command -v "$tool" 2>/dev/null) && ln -s "$tp" "$NJ/$tool"
  done

  # pcc_exec STDIN-FILE|closed [env assignments…] — runs the hook under a 15 s watchdog.
  # Sets PCC_RC (exit code, or `hung`); stdout → $T/out.
  pcc_exec() {
    _in=$1; shift
    if [ "$_in" = closed ]; then
      env HOME="$H" TMPDIR="$T/tmpdir" KT_SURFACE_CACHE_DIR="$T/cache" KT_CONFIG= "$@" sh "$PCC_HOOK" <&- >"$T/out" 2>"$T/err" &
    else
      env HOME="$H" TMPDIR="$T/tmpdir" KT_SURFACE_CACHE_DIR="$T/cache" KT_CONFIG= "$@" sh "$PCC_HOOK" <"$_in" >"$T/out" 2>"$T/err" &
    fi
    _pid=$!; _i=0
    while kill -0 "$_pid" 2>/dev/null; do
      _i=$((_i + 1))
      if [ "$_i" -gt 150 ]; then kill "$_pid" 2>/dev/null; wait "$_pid" 2>/dev/null; PCC_RC=hung; return; fi
      sleep 0.1
    done
    wait "$_pid"; PCC_RC=$?
  }
  # payload SID PROMPT → a hook stdin file (real-shaped: session_id, prompt, cwd, event name)
  payload() {
    jq -n --arg s "$1" --arg p "$2" \
      '{session_id:$s, transcript_path:"/x/t.jsonl", cwd:"/x", hook_event_name:"UserPromptSubmit", prompt:$p}' > "$T/in.json"
  }
  sid() { printf '%s-%s' "$RUN_ID" "$1"; }
  ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' "$T/out" 2>/dev/null; }
  outsize() { wc -c < "$T/out" | tr -d ' '; }

  PROMPT_PAY="how do we handle payments for proj-b deposits"

  # --- fires_with_paths_only ----------------------------------------------
  payload "$(sid fire)" "$PROMPT_PAY"; pcc_exec "$T/in.json"
  r "fires: exit 0" 0 "$PCC_RC"
  r "fires: valid JSON with the UserPromptSubmit event" UserPromptSubmit \
    "$(jq -r '.hookSpecificOutput.hookEventName // empty' "$T/out" 2>/dev/null)"
  C=$(ctx)
  case "$C" in "ARIA ACTIVE — "*" knowledge file(s) for this task (tags: "*"). Read them before answering and say in one line which you used and why:"*) h=1 ;; *) h=0 ;; esac
  r "fires: header text" 1 "$h"
  case "$C" in *"
- $KF/projects/proj-b/deposits.md"*) h=1 ;; *) h=0 ;; esac
  r "fires: lists the ranked absolute path" 1 "$h"
  N=$(printf '%s' "$C" | sed -n 's/^ARIA ACTIVE — \([0-9]*\) knowledge.*/\1/p')
  L=$(printf '%s\n' "$C" | grep -c '^- /')
  r "fires: n in header equals path lines" "$N" "$L"
  r "fires: at most 5 paths" 1 "$( [ "${L:-0}" -ge 1 ] && [ "${L:-0}" -le 5 ] && echo 1 || echo 0)"
  case "$C" in *PCC-BODY-SENTINEL*|*"Deposit handling"*) h=1 ;; *) h=0 ;; esac
  r "fires: no file bodies, no descriptions" 0 "$h"
  r "fires: additionalContext under 10,000 chars" 1 "$( [ "${#C}" -lt 10000 ] && echo 1 || echo 0)"
  r "fires: top-level shape is only hookSpecificOutput" hookSpecificOutput "$(jq -r 'keys|join(",")' "$T/out" 2>/dev/null)"
  r "fires: ledger records the relative path" 1 \
    "$(grep -cx 'projects/proj-b/deposits.md' "/tmp/aria-active-$(sid fire)" 2>/dev/null)"

  # --- pasted_block_ignored -----------------------------------------------
  NL='
'
  payload "$(sid paste)" "hi${NL}<pasted_content id=\"x\">${NL}payments proj-b proj-c webhooks${NL}more payments for proj-b${NL}</pasted_content>"
  pcc_exec "$T/in.json"
  r "paste: multi-line block ignored (no output)" "0|0" "$PCC_RC|$(outsize)"
  payload "$(sid paste1)" "hi <pasted_content id=\"y\">payments proj-b proj-c</pasted_content>"
  pcc_exec "$T/in.json"
  r "paste: single-line block ignored (no output)" "0|0" "$PCC_RC|$(outsize)"
  payload "$(sid paste2)" "hi${NL}<pasted_content id=\"z\">${NL}payments proj-b proj-c${NL}(no closing line)"
  pcc_exec "$T/in.json"
  r "paste: unterminated block ignored to the end" "0|0" "$PCC_RC|$(outsize)"
  # Positive control: the SAME words typed by the user do fire, so the arms above are
  # silent because of the strip, not because the words cannot match.
  payload "$(sid paste3)" "hi${NL}payments proj-b proj-c webhooks${NL}more payments for proj-b"
  pcc_exec "$T/in.json"
  r "paste: control — same words outside a paste fire" 1 "$(ctx | grep -c '^ARIA ACTIVE')"
  payload "$(sid paste4)" "payments for proj-b${NL}<pasted_content id=\"w\">${NL}noise${NL}</pasted_content>${NL}"
  pcc_exec "$T/in.json"
  r "paste: user words around a paste still fire" 1 "$(ctx | grep -c '^ARIA ACTIVE')"

  # --- single_project_tag_fires_once (ledger cadence) ----------------------
  payload "$(sid once)" "notes on proj-a please"
  pcc_exec "$T/in.json"
  r "once: first call fires" 1 "$(ctx | grep -c "^- $KF/projects/proj-a/hooks.md\$")"
  pcc_exec "$T/in.json"
  r "once: second identical call is silent" "0|0" "$PCC_RC|$(outsize)"
  payload "$(sid once)" "$PROMPT_PAY"
  pcc_exec "$T/in.json"
  r "once: a prompt ranking NEW files fires in the same session" 1 "$(ctx | grep -c '^ARIA ACTIVE')"
  case "$(ctx)" in *projects/proj-a/hooks.md*) h=1 ;; *) h=0 ;; esac
  r "once: already-surfaced path is not re-injected" 0 "$h"

  # --- active_surfacing_false_silent ---------------------------------------
  HA="$T/home-off"; mk_home "$HA" "$KF" "active_knowledge_surfacing: false"
  payload "$(sid off)" "$PROMPT_PAY"
  pcc_exec "$T/in.json" HOME="$HA"
  r "off: active_knowledge_surfacing false is silent" "0|0" "$PCC_RC|$(outsize)"

  # --- config cache: a config edit is seen on the next prompt ---------------
  HC="$T/home-cc"; mk_home "$HC" "$KF"
  payload "$(sid cc1)" "$PROMPT_PAY"; pcc_exec "$T/in.json" HOME="$HC"
  r "cache: fires before the edit" 1 "$(ctx | grep -c '^ARIA ACTIVE')"
  mk_home "$HC" "$KF" "active_knowledge_surfacing: false"
  payload "$(sid cc2)" "$PROMPT_PAY"; pcc_exec "$T/in.json" HOME="$HC"
  r "cache: edit to false is honoured at once" "0|0" "$PCC_RC|$(outsize)"
  mk_home "$HC" "$KF"
  payload "$(sid cc3)" "$PROMPT_PAY"; pcc_exec "$T/in.json" HOME="$HC"
  r "cache: edit back to true fires again" 1 "$(ctx | grep -c '^ARIA ACTIVE')"

  # --- config cache round-trip: a hit returns what config.sh returned -------
  KQ="$T/k f'o \"q\" \$x"; mk_kf "$KQ"
  HQ="$T/home-q"; mk_home "$HQ" "$KQ"
  rm -rf "$T/cache-q"; mkdir -p "$T/cache-q"
  payload "$(sid rt1)" "$PROMPT_PAY"; pcc_exec "$T/in.json" HOME="$HQ" KT_SURFACE_CACHE_DIR="$T/cache-q"
  OUT1=$(ctx)
  r "roundtrip: miss writes the config cache" 1 "$(ls "$T/cache-q" | grep -c '^aria-prompt-config')"
  payload "$(sid rt2)" "$PROMPT_PAY"; pcc_exec "$T/in.json" HOME="$HQ" KT_SURFACE_CACHE_DIR="$T/cache-q"
  OUT2=$(ctx)
  case "$OUT1" in *"- $KQ/projects/proj-b/deposits.md"*) h=1 ;; *) h=0 ;; esac
  r "roundtrip: miss fires with the quoted knowledge path" 1 "$h"
  # Compared by cksum: the values are multi-line and this protocol is one line per check.
  r "roundtrip: cache hit fires" 1 "$(printf '%s\n' "$OUT2" | grep -c '^ARIA ACTIVE')"
  r "roundtrip: cache hit output equals miss output" \
    "$(printf '%s' "$OUT1" | cksum)" "$(printf '%s' "$OUT2" | cksum)"

  # --- KT_CONFIG is honoured the way config.sh honours it -------------------
  HN="$T/home-none"; mkdir -p "$HN"
  payload "$(sid nocfg)" "$PROMPT_PAY"; pcc_exec "$T/in.json" HOME="$HN"
  r "no config file: silent" "0|0" "$PCC_RC|$(outsize)"
  payload "$(sid ktcfg)" "$PROMPT_PAY"; pcc_exec "$T/in.json" HOME="$HN" KT_CONFIG="$H/.claude/aria-knowledge.local.md"
  r "KT_CONFIG pointing at a config: fires" 1 "$(ctx | grep -c '^ARIA ACTIVE')"

  # --- no_jq_silent / no_index_silent / malformed_stdin_silent --------------
  payload "$(sid nojq)" "$PROMPT_PAY"; pcc_exec "$T/in.json" PATH="$NJ"
  r "no jq: silent, exit 0" "0|0" "$PCC_RC|$(outsize)"
  payload "$(sid jqctl)" "$PROMPT_PAY"; pcc_exec "$T/in.json" PATH="$NJ:$(dirname "$(command -v jq)")"
  r "no jq: control — the same PATH plus jq fires" 1 "$(ctx | grep -c '^ARIA ACTIVE')"
  KN="$T/kf-noindex"; mk_kf "$KN" no-index; HI="$T/home-noindex"; mk_home "$HI" "$KN"
  payload "$(sid noidx)" "$PROMPT_PAY"; pcc_exec "$T/in.json" HOME="$HI"
  r "no index: silent, exit 0" "0|0" "$PCC_RC|$(outsize)"
  printf 'not json {' > "$T/bad.json"; pcc_exec "$T/bad.json"
  r "malformed stdin: silent, exit 0" "0|0" "$PCC_RC|$(outsize)"
  printf '"%s"' "$PROMPT_PAY" > "$T/str.json"; pcc_exec "$T/str.json"
  r "non-object JSON: silent, exit 0" "0|0" "$PCC_RC|$(outsize)"
  jq -n --arg p "$PROMPT_PAY" '{prompt:$p}' > "$T/nosid.json"; pcc_exec "$T/nosid.json"
  r "no session_id: silent, exit 0" "0|0" "$PCC_RC|$(outsize)"
  : > "$T/empty.json"; pcc_exec "$T/empty.json"
  r "empty stdin: silent, exit 0" "0|0" "$PCC_RC|$(outsize)"

  # --- stdin is consumed (latency-independent) ------------------------------
  pcc_exec closed
  r "stdin closed: returns, exit 0, silent" "0|0" "$PCC_RC|$(outsize)"
  # A ~450 KB payload through a real pipe. The writer marks completion only if every byte
  # was read: a hook that exits without draining stdin, or reads only part of it, kills cat
  # with SIGPIPE. Size matters — at ~114 KB a 4 KB partial read still passed, because what
  # was left after the reader's buffered read fit in the 64 KB pipe buffer (mutation-measured).
  PAD=$(awk 'BEGIN { for (i = 0; i < 24000; i++) printf "padding words here "; }')
  jq -n --arg s "$(sid pipe)" --arg p "$PROMPT_PAY $PAD" '{session_id:$s, prompt:$p}' > "$T/big.json"
  rm -f "$T/writer-done"
  ( cat "$T/big.json" && : > "$T/writer-done" ) \
    | env HOME="$H" TMPDIR="$T/tmpdir" KT_SURFACE_CACHE_DIR="$T/cache" KT_CONFIG= sh "$PCC_HOOK" >"$T/out" 2>"$T/err" &
  _pid=$!; _i=0; PIPE_STATE=done
  while kill -0 "$_pid" 2>/dev/null; do
    _i=$((_i + 1)); if [ "$_i" -gt 150 ]; then kill "$_pid" 2>/dev/null; PIPE_STATE=hung; break; fi; sleep 0.1
  done
  wait "$_pid" 2>/dev/null
  r "stdin piped (>64 KB): hook returns" done "$PIPE_STATE"
  r "stdin piped (>64 KB): every byte was read" 1 "$( [ -f "$T/writer-done" ] && echo 1 || echo 0)"
  r "stdin piped (>64 KB): still fires" 1 "$(ctx | grep -c '^ARIA ACTIVE')"

  # --- registered_in_plugin_json --------------------------------------------
  r "registered: UserPromptSubmit runs the hook with a quoted plugin root, timeout 5" \
    'bash "${CLAUDE_PLUGIN_ROOT}/scripts/prompt-context-check.sh"|5' \
    "$(jq -r '.hooks.UserPromptSubmit[].hooks[] | select(.command | test("prompt-context-check")) | "\(.command)|\(.timeout)"' "$PCC_PLUGIN_JSON" 2>/dev/null)"
  r "registered: usage-threshold-inject.sh entry kept" 1 \
    "$(jq '[.hooks.UserPromptSubmit[].hooks[] | select(.command | test("usage-threshold-inject"))] | length' "$PCC_PLUGIN_JSON" 2>/dev/null)"
}
PCC_RESULTS=$(pcc_body)

PCC_TAB=$(printf '\t')
PCC_OLD_IFS=$IFS
while IFS="$PCC_TAB" read -r pcc_name pcc_exp pcc_act; do
  [ -n "$pcc_name" ] && assert_eq "prompt-context-check: $pcc_name" "$pcc_exp" "$pcc_act"
done <<PCC_EOF
$PCC_RESULTS
PCC_EOF
IFS=$PCC_OLD_IFS
