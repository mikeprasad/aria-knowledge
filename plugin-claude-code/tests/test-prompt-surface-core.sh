# shellcheck shell=sh
# test-prompt-surface-core.sh — scripts/lib-prompt-surface.sh (the shared capture core, spec C1)
#
# Sourced by tests/run.sh under `set -eu`. Same protocol as test-prompt-context-check.sh: the
# body runs in a SUBSHELL with its own EXIT trap and prints one `name<TAB>expected<TAB>actual`
# line per check; the parent replays them through assert_eq and asserts the count, so a body
# that dies partway fails instead of silently reporting fewer checks.
#
# Every lib call runs in its own subshell with HOME, TMPDIR, KT_CONFIG and KT_STATE_BASE isolated
# (the second ps_call argument is that BASE: the lib's caches and debug log live in
# <BASE>/aria-knowledge-<uid>, the private state dir, since 2.58.0), and with a ledger path inside
# the test dir. Nothing here touches /tmp.

PS_SD="$(cd "$(dirname "$0")/../scripts" && pwd)"
PS_LIB="$PS_SD/lib-prompt-surface.sh"
PS_FIXTURE="$(cd "$(dirname "$0")/../../tests/repros/fixtures/surfacing" && pwd)/index.md"

# Defined at top level and CALLED inside $( ): bash 3.2 (macOS /bin/sh) cannot parse a `case`
# pattern's closing `)` written directly inside a command substitution.
ps_header_ok() { # TEXT → 1 if it opens with the injection header
  case "$1" in "ARIA ACTIVE — "*" knowledge file(s) for this task (tags: "*"). Read them before answering and say in one line which you used and why:"*) echo 1 ;; *) echo 0 ;; esac
}
ps_has_line() { # TEXT LINE → 1 if LINE is one of TEXT's lines
  printf '%s\n' "$1" | grep -cxF -- "$2"
}

ps_body() {
  set +e +u
  T="${TMPDIR:-/tmp}/aria-psc-$$"
  RUN_ID="psc-$$-$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d ' ')"
  trap 'rm -rf "$T"' EXIT
  rm -rf "$T"; mkdir -p "$T/tmpdir" "$T/cache"
  UIDN=$(id -u)
  # mksd BASE — a fresh state base with its state dir already made (mode 700), to plant in.
  mksd() { rm -rf "$1"; mkdir -p "$1"; mkdir -m 700 "$1/aria-knowledge-$UIDN"; }

  r() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

  mk_kf() { # DIR [no-index]
    mkdir -p "$1"
    [ "${2:-}" = no-index ] || cp "$PS_FIXTURE" "$1/index.md"
    for p in projects/proj-a/hooks.md projects/proj-b/deposits.md projects/proj-b/crew-notes.md \
             projects/proj-b/estimates.md projects/proj-c/billing-1.md references/webhook-basics.md; do
      mkdir -p "$1/${p%/*}"; printf 'body for %s\n' "$p" > "$1/$p"
    done
  }
  mk_cfg() { # FILE KF [extra frontmatter line]
    mkdir -p "${1%/*}"
    {
      printf -- '---\nknowledge_folder: %s\nprojects_enabled: true\nprojects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c\n' "$2"
      [ -n "${3:-}" ] && printf '%s\n' "$3"
      printf -- '---\n\nSynthetic config for test-prompt-surface-core.sh.\n'
    } > "$1"
  }
  KF="$T/kf"; mk_kf "$KF"
  CFG="$T/cfg/main.local.md"; mk_cfg "$CFG" "$KF"

  # ps_call CONFIG STATE-BASE TEXT LEDGER — sources the lib in a fresh subshell, resolves the
  # state dir under STATE-BASE (as every hook does before its first lib call), runs
  # kt_ps_surface, then (as an adapter does once it has delivered) kt_ps_commit — unless
  # PS_NOCOMMIT=1. Sets PS_STATUS (empty if the lib could not run); stdout → $T/out;
  # KT_PS_PENDING → $T/pending.
  ps_call() {
    rm -f "$T/out" "$T/status" "$T/pending"
    (
      HOME="$T/home"; KT_CONFIG=$1; KT_STATE_BASE=$2; TMPDIR="$T/tmpdir"
      export HOME KT_CONFIG KT_STATE_BASE TMPDIR
      KT_PS_SCRIPT_DIR="$PS_SD"; KT_PS_RUNTIME=core-test
      . "$PS_LIB" || exit 1
      . "$PS_SD/lib-state-key.sh" || exit 1; kt_state_resolve
      kt_ps_surface "$3" "$4" > "$T/out" 2>"$T/err"
      printf '%s' "$KT_PS_STATUS" > "$T/status"
      printf '%s' "${KT_PS_PENDING:-}" > "$T/pending"
      [ "${PS_NOCOMMIT:-}" = 1 ] || kt_ps_commit "$4"
    ) 2>/dev/null
    PS_STATUS=$(cat "$T/status" 2>/dev/null)
  }
  out() { cat "$T/out" 2>/dev/null; }
  outsize() { if [ -f "$T/out" ]; then wc -c < "$T/out" | tr -d ' '; else echo missing; fi; }
  # ps_fn FUNCTION [ARGS…] — runs one lib function with stdin passed through.
  ps_fn() {
    ( KT_PS_SCRIPT_DIR="$PS_SD"; . "$PS_LIB" || exit 1; "$@" ) 2>/dev/null
  }
  inodes() { ls -i "$1/aria-knowledge-$UIDN" 2>/dev/null | grep 'aria-prompt-config' | awk '{print $1}' | sort | tr '\n' ' '; }
  ncache() { ls "$1/aria-knowledge-$UIDN" 2>/dev/null | grep -c '^aria-prompt-config.*\.cache$'; }

  PROMPT_PAY="how do we handle payments for proj-b deposits"

  # --- core_injects_paths --------------------------------------------------
  ps_call "$CFG" "$T/cache" "$PROMPT_PAY" "$T/ledger-1"
  O=$(out)
  r "core_injects_paths: status injected" injected "$PS_STATUS"
  r "core_injects_paths: opens with the ARIA ACTIVE header" 1 "$(ps_header_ok "$O")"
  r "core_injects_paths: lists the ranked absolute path" 1 "$(ps_has_line "$O" "- $KF/projects/proj-b/deposits.md")"
  N=$(printf '%s' "$O" | sed -n 's/^ARIA ACTIVE — \([0-9]*\) knowledge.*/\1/p')
  L=$(printf '%s\n' "$O" | grep -c '^- /')
  r "core_injects_paths: n in header equals absolute path lines" "$N" "$L"
  r "core_injects_paths: under 10,000 chars" 1 "$( [ "${#O}" -gt 0 ] && [ "${#O}" -lt 10000 ] && echo 1 || echo 0)"
  r "core_injects_paths: ledger records the relative path" 1 "$(grep -cx 'projects/proj-b/deposits.md' "$T/ledger-1" 2>/dev/null)"

  # --- core_nothing_new ------------------------------------------------------
  ps_call "$CFG" "$T/cache" "$PROMPT_PAY" "$T/ledger-1"
  r "core_nothing_new: second call, same ledger — status" nothing-new "$PS_STATUS"
  r "core_nothing_new: second call prints nothing" 0 "$(outsize)"
  r "core_nothing_new: nothing is recorded twice" 1 "$(grep -cx 'projects/proj-b/deposits.md' "$T/ledger-1" 2>/dev/null)"

  # --- core_surface_does_not_record / core_commit_records (F1) ----------------------
  # kt_ps_surface ranks and filters against the ledger but RECORDS NOTHING: a host that
  # delivers later (Cursor's postToolUse) must not mark as seen what the model never got.
  # ps_src CONFIG — inside a subshell: isolated env + the lib sourced.
  ps_src() {
    HOME="$T/home"; KT_CONFIG=$1; KT_STATE_BASE="$T/cache"; TMPDIR="$T/tmpdir"
    export HOME KT_CONFIG KT_STATE_BASE TMPDIR
    KT_PS_SCRIPT_DIR="$PS_SD"; KT_PS_RUNTIME=core-test
    . "$PS_LIB" && . "$PS_SD/lib-state-key.sh" && { kt_state_resolve; :; }
  }
  printf 'references/seed-entry.md\n' > "$T/ledger-c"; SEED=$(cksum < "$T/ledger-c")
  PS_NOCOMMIT=1; ps_call "$CFG" "$T/cache" "$PROMPT_PAY" "$T/ledger-c"; PS_NOCOMMIT=
  EXP=$(out | sed -n "s|^- $KF/||p"); EXPL=$(printf '%s' "$EXP" | tr '\n' '|')
  NEXP=$(printf '%s\n' "$EXP" | grep -c .)
  r "core_surface_does_not_record: surface alone still injects" injected "$PS_STATUS"
  r "core_surface_does_not_record: ledger unchanged after surface alone" "$SEED" "$(cksum < "$T/ledger-c")"
  r "core_surface_does_not_record: KT_PS_PENDING is exactly the surfaced relative paths" \
    "1|$EXPL" "$( [ "$NEXP" -gt 0 ] && echo 1 || echo 0)|$(tr '\n' '|' < "$T/pending" 2>/dev/null)"
  ps_call "$CFG" "$T/cache" "$PROMPT_PAY" "$T/ledger-c"
  r "core_commit_records: after kt_ps_commit the ledger is the seed plus exactly those paths" \
    "references/seed-entry.md|$EXPL|" "$(tr '\n' '|' < "$T/ledger-c")"
  printf 'references/seed-entry.md\n' > "$T/ledger-d"
  ( ps_src "$CFG" || exit 1; kt_ps_surface "$PROMPT_PAY" "$T/ledger-d" >/dev/null
    kt_ps_commit "$T/ledger-d"; kt_ps_commit "$T/ledger-d" ) 2>/dev/null
  r "core_commit_records: a second kt_ps_commit adds nothing" "$((NEXP + 1))" "$(wc -l < "$T/ledger-d" | tr -d ' ')"

  # --- core_commit_paths: commit later, from a stored pending file (Task 3's shape) ----
  printf 'projects/proj-a/hooks.md\n\nreferences/webhook-basics.md\n' > "$T/pending-file"
  : > "$T/ledger-p"
  ( ps_src "$CFG" || exit 1; kt_ps_commit_paths "$T/ledger-p" "$T/pending-file" ) 2>/dev/null
  r "core_commit_paths: records the stored paths, blank lines dropped" \
    "projects/proj-a/hooks.md|references/webhook-basics.md|" "$(tr '\n' '|' < "$T/ledger-p")"
  ln -s "$T/pending-file" "$T/pending-link"; : > "$T/ledger-q"
  ( ps_src "$CFG" || exit 1; kt_ps_commit_paths "$T/ledger-q" "$T/pending-link" ) 2>/dev/null
  r "core_commit_paths: a symlinked paths file is refused" 0 "$(wc -c < "$T/ledger-q" | tr -d ' ')"

  # --- core_commit_paths_rejects_bad_lines: only plain relative paths reach the ledger ----
  # Ledger lines are later shown to the model (session start after compaction), so a stored
  # paths file is shape-filtered line by line. `x..y` in a NAME is legitimate and kept (the
  # positive control: a filter that dropped everything would fail here too).
  printf 'projects/proj-a/hooks.md\n/etc/passwd\n../outside.md\nprojects/../up.md\nprojects/proj-b/..\n..\nprojects/tab\there.md\nprojects/esc\033x.md\nprojects/cr.md\r\nprojects/proj-c/a..b.md\nreferences/webhook-basics.md\n' > "$T/pending-bad"
  : > "$T/ledger-b"
  ( ps_src "$CFG" || exit 1; kt_ps_commit_paths "$T/ledger-b" "$T/pending-bad" ) 2>/dev/null
  r "core_commit_paths_rejects_bad_lines: only plain relative paths are recorded" \
    "projects/proj-a/hooks.md|projects/proj-c/a..b.md|references/webhook-basics.md|" "$(tr '\n' '|' < "$T/ledger-b")"
  printf 'projects/proj-a/hooks.md\nprojects/nul\000x.md\n' > "$T/pending-nul"
  : > "$T/ledger-n"
  ( ps_src "$CFG" || exit 1; kt_ps_commit_paths "$T/ledger-n" "$T/pending-nul" ) 2>/dev/null
  r "core_commit_paths_rejects_bad_lines: a paths file holding a NUL byte is refused whole" \
    0 "$(wc -c < "$T/ledger-n" | tr -d ' ')"

  # --- core_commit_filters_like_commit_paths: the in-process commit uses the same filter ----
  : > "$T/ledger-k"
  ( ps_src "$CFG" || exit 1
    KT_PS_PENDING=$(printf 'projects/proj-a/hooks.md\n/abs/outside.md\nprojects/../up.md\nprojects/cr.md\r\nprojects/proj-c/a..b.md')
    kt_ps_commit "$T/ledger-k" ) 2>/dev/null
  r "core_commit_filters_like_commit_paths: kt_ps_commit records only plain relative paths" \
    "projects/proj-a/hooks.md|projects/proj-c/a..b.md|" "$(tr '\n' '|' < "$T/ledger-k")"

  # --- core_ledger_link_refused (final fix wave (a)+F7) ------------------------------------------
  # The ledger lives at <state dir>/aria-active-<id> (before 2.58.0, a predictable /tmp name). The
  # guard stays as a second one inside the private dir (spec D2). A link planted there must neither be
  # READ (kt_match_filter_ledger: a planted list would silently suppress surfacing) nor WRITTEN
  # through (_kt_ps_append_kept: an append would land in whatever the link names).
  printf '%s\n' $EXP > "$T/planted-ledger"; PLANTED=$(cksum < "$T/planted-ledger")
  ln -s "$T/planted-ledger" "$T/ledger-link"
  ps_call "$CFG" "$T/cache" "$PROMPT_PAY" "$T/ledger-link"
  r "core_ledger_link_refused: a symlinked ledger is not read (still injects)" injected "$PS_STATUS"
  r "core_ledger_link_refused: nothing is appended through the link" "$PLANTED" "$(cksum < "$T/planted-ledger")"
  r "core_ledger_link_refused: the link itself is left a link" 1 "$( [ -L "$T/ledger-link" ] && echo 1 || echo 0)"
  # Control: the SAME list as a regular file is honoured — so the arm above refuses the link, not
  # the list.
  cp "$T/planted-ledger" "$T/ledger-regular"
  ps_call "$CFG" "$T/cache" "$PROMPT_PAY" "$T/ledger-regular"
  r "core_ledger_link_refused: control — the same list as a regular file filters" nothing-new "$PS_STATUS"
  # The in-flow check above cannot fail on its own while the filter still reads the link (nothing is
  # delivered, so nothing is committed). Drive the writer directly.
  : > "$T/planted-empty"; ln -s "$T/planted-empty" "$T/ledger-link2"
  ( ps_src "$CFG" || exit 1; KT_PS_PENDING='projects/proj-a/hooks.md'; kt_ps_commit "$T/ledger-link2" ) 2>/dev/null
  r "core_ledger_link_refused: kt_ps_commit does not write through a link" 0 "$(wc -c < "$T/planted-empty" | tr -d ' ')"
  # Residual (scoped re-review): the bash-cd and task-context hooks record through
  # kt_match_record_ledger, a second writer onto the same ledger.
  printf 'projects/proj-a/hooks.md — d\n' > "$T/rec-matches"
  : > "$T/rec-target"; ln -s "$T/rec-target" "$T/rec-link"; : > "$T/rec-regular"
  # ps_src does not define kt_match_record_ledger (the core loads the matcher lazily); the control
  # below is what showed that — source the matcher lib directly.
  ( ps_src "$CFG" || exit 1; . "$PS_SD/lib-index-match.sh" || exit 1; KT_MATCH_FILES_TMP="$T/rec-matches"
    kt_match_record_ledger "$T/rec-link"; kt_match_record_ledger "$T/rec-regular" ) 2>/dev/null
  r "core_ledger_link_refused: kt_match_record_ledger does not write through a link" 0 "$(wc -c < "$T/rec-target" | tr -d ' ')"
  r "core_ledger_link_refused: control — kt_match_record_ledger records into a regular ledger" \
    "projects/proj-a/hooks.md|" "$(tr '\n' '|' < "$T/rec-regular")"

  # --- core_unsafe_entries_never_surfaced: delivered must equal recordable -----------------
  # An index entry that is not a plain relative path (absolute, or with a `..` segment) is
  # dropped BEFORE it enters the injection: it could never be recorded, so delivering it would
  # re-surface it on every prompt. The entries are listed under BOTH firing tags so they rank
  # into the top-5 cap (under one tag they rank below it and the arm would prove nothing). The
  # cap makes call 1 differ from a clean fixture by construction; call 2 must match it.
  KU="$T/ku"; mk_kf "$KU" no-index
  awk '{ print } /^### (payments|proj-b)$/ { print "- /abs/outside.md — Absolute entry"; print "- ../escape.md — Escape entry" }' \
    "$PS_FIXTURE" > "$KU/index.md"
  CFGU="$T/cfg/unsafe.local.md"; mk_cfg "$CFGU" "$KU"
  KC="$T/kc"; mk_kf "$KC"; CFGC="$T/cfg/clean.local.md"; mk_cfg "$CFGC" "$KC"
  mksd "$T/cache-u"; mksd "$T/cache-c"
  ps_call "$CFGU" "$T/cache-u" "$PROMPT_PAY" "$T/ledger-u"; U1=$(out | sed "s|$KU/|KF/|g")
  ps_call "$CFGC" "$T/cache-c" "$PROMPT_PAY" "$T/ledger-cc"
  ps_call "$CFGU" "$T/cache-u" "$PROMPT_PAY" "$T/ledger-u"; U2=$(out | sed "s|$KU/|KF/|g"); U2S=$PS_STATUS
  ps_call "$CFGC" "$T/cache-c" "$PROMPT_PAY" "$T/ledger-cc"; C2=$(out | sed "s|$KC/|KF/|g"); C2S=$PS_STATUS
  r "core_unsafe_entries_never_surfaced: neither entry is in the injection" \
    0 "$(printf '%s\n' "$U1" | grep -c -e '/abs/outside\.md' -e 'escape\.md')"
  r "core_unsafe_entries_never_surfaced: first call still fires with the safe paths" \
    "1|1" "$(ps_header_ok "$U1")|$(ps_has_line "$U1" "- KF/projects/proj-b/deposits.md")"
  r "core_unsafe_entries_never_surfaced: second call matches the clean fixture (output, status)" \
    "$(printf '%s' "$C2" | cksum)|$C2S" "$(printf '%s' "$U2" | cksum)|$U2S"
  r "core_unsafe_entries_never_surfaced: the drop is logged as dropped-unsafe-entry" \
    1 "$( [ "$(grep -c ' surface dropped-unsafe-entry$' "$T/cache-u/aria-knowledge-$UIDN/aria-surface-hook.log" 2>/dev/null)" -ge 1 ] && echo 1 || echo 0)"
  r "core_unsafe_entries_never_surfaced: the ledger never holds them" \
    0 "$(grep -c -e '^/abs' -e 'escape\.md' "$T/ledger-u" 2>/dev/null)"

  # --- hook flow: the Claude Code adapter commits only after its emission succeeded ----
  HH="$T/hhome"; mk_cfg "$HH/.claude/aria-knowledge.local.md" "$KF"; mksd "$T/cache-h"
  PCC="$PS_SD/prompt-context-check.sh"
  hook_run() { # SID [PATH-PREFIX]
    jq -n --arg s "$1" --arg p "$PROMPT_PAY" \
      '{session_id:$s, prompt:$p, hook_event_name:"UserPromptSubmit"}' > "$T/hin.json"
    env HOME="$HH" TMPDIR="$T/tmpdir" KT_STATE_BASE="$T/cache-h" KT_CONFIG= \
      PATH="${2:+$2:}$PATH" sh "$PCC" < "$T/hin.json" > "$T/hout" 2>/dev/null
  }
  hook_run "$RUN_ID-ok"
  r "hook: a delivered injection is recorded" "1|1" \
    "$(grep -c '^{"hookSpecificOutput"' "$T/hout")|$(grep -cx 'projects/proj-b/deposits.md' "$T/cache-h/aria-knowledge-$UIDN/aria-active-$RUN_ID-ok" 2>/dev/null)"
  # A jq shim that fails ONLY the emission call (`jq -cn …`); extraction still works.
  mkdir -p "$T/jqshim"
  printf '#!/bin/sh\ncase " $* " in *" -cn "*) exit 1 ;; esac\nexec "%s" "$@"\n' "$(command -v jq)" > "$T/jqshim/jq"
  chmod +x "$T/jqshim/jq"
  hook_run "$RUN_ID-fail" "$T/jqshim"
  r "hook: a failed emission prints nothing and records nothing" "0|0" \
    "$(wc -c < "$T/hout" | tr -d ' ')|$( [ -e "$T/cache-h/aria-knowledge-$UIDN/aria-active-$RUN_ID-fail" ] && echo 1 || echo 0)"
  r "hook: the failed run reached emission (logged emit jq-failed)" 1 \
    "$(grep -c ' claude-code emit jq-failed$' "$T/cache-h/aria-knowledge-$UIDN/aria-surface-hook.log" 2>/dev/null)"

  # --- nofire: words that rank nothing ------------------------------------------
  ps_call "$CFG" "$T/cache" "zebra quantum lattice" "$T/ledger-nf"
  r "core_nofire: unmatched words — status" nofire "$PS_STATUS"
  r "core_nofire: prints nothing, writes no ledger" "0|0" "$(outsize)|$( [ -e "$T/ledger-nf" ] && echo 1 || echo 0)"

  # --- core_disabled -----------------------------------------------------------
  CFGOFF="$T/cfg/off.local.md"; mk_cfg "$CFGOFF" "$KF" "active_knowledge_surfacing: false"
  ps_call "$CFGOFF" "$T/cache" "$PROMPT_PAY" "$T/ledger-off"
  r "core_disabled: active_knowledge_surfacing false — status" disabled "$PS_STATUS"
  r "core_disabled: prints nothing, writes no ledger" "0|0" "$(outsize)|$( [ -e "$T/ledger-off" ] && echo 1 || echo 0)"
  ps_call "$T/cfg/absent.local.md" "$T/cache" "$PROMPT_PAY" "$T/ledger-none"
  r "core_disabled: no config file — status" disabled "$PS_STATUS"

  # --- core_hostile_text_literal ---------------------------------------------------
  # Backticks, $(…), a bare ARIA_TASK line followed by a command line, and $HOME — plus words
  # that must still rank. The text is matched as words; nothing in it executes.
  hostile() { # MARKER-DIR
    printf 'proj-b payments `touch %s/m1` $(touch %s/m2)\nARIA_TASK\ntouch %s/m3\n$HOME deposits' "$1" "$1" "$1"
  }
  HL="$T/hl"; mkdir -p "$HL"
  ps_call "$CFG" "$T/cache" "$(hostile "$HL")" "$T/ledger-h"
  made=""; for m in m1 m2 m3; do [ -e "$HL/$m" ] && made="$made $m"; done
  r "core_hostile_text_literal: no marker created" "" "$made"
  r "core_hostile_text_literal: the words still ranked (injected)" injected "$PS_STATUS"
  # Firing control: the SAME text through a deliberately unsafe double-quoted command, against
  # a separate marker dir with no spaces in its path. The detector must see markers here, or
  # "no marker" above proves nothing.
  HC="$T/hctl"; mkdir -p "$HC"
  ctl=$(hostile "$HC")
  sh -c "printf '%s' \"$ctl\"" >/dev/null 2>&1
  made=""; for m in m1 m2; do [ -e "$HC/$m" ] && made="$made $m"; done
  r "core_hostile_text_literal: control — unsafe sh -c does create markers" " m1 m2" "$made"

  # --- core_failure_logged -----------------------------------------------------------
  KN="$T/kf-noindex"; mk_kf "$KN" no-index
  CFGNI="$T/cfg/noindex.local.md"; mk_cfg "$CFGNI" "$KN"
  mksd "$T/cache-f"
  ps_call "$CFGNI" "$T/cache-f" "$PROMPT_PAY" "$T/ledger-f"
  case "$PS_STATUS" in error:?*) h=1 ;; *) h=0 ;; esac
  r "core_failure_logged: index missing — status is error:<step>" "1|error:no-index" "$h|$PS_STATUS"
  r "core_failure_logged: nothing on stdout" 0 "$(outsize)"
  LOGF="$T/cache-f/aria-knowledge-$UIDN/aria-surface-hook.log"
  r "core_failure_logged: exactly one line in the debug log" 1 "$(wc -l < "$LOGF" 2>/dev/null | tr -d ' ')"
  r "core_failure_logged: line is <UTC> <runtime> <step> <reason>" 1 \
    "$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z core-test surface no-index$' "$LOGF" 2>/dev/null)"
  # Control: a SUCCESSFUL call against the same cache dir adds no line (the log is failures only).
  ps_call "$CFG" "$T/cache-f" "$PROMPT_PAY" "$T/ledger-f2"
  r "core_failure_logged: control — a successful call logs nothing" "injected|1" "$PS_STATUS|$(wc -l < "$LOGF" 2>/dev/null | tr -d ' ')"

  # --- core_strip_pasted ---------------------------------------------------------------
  NL='
'
  st() { printf '%s' "$1" | ps_fn kt_ps_strip_pasted | tr '\n' '|'; }
  r "core_strip_pasted: multi-line block dropped" "hi|after|" \
    "$(st "hi${NL}<pasted_content id=\"x\">${NL}secret proj-b${NL}</pasted_content>${NL}after")"
  r "core_strip_pasted: one-line block drops that line" "after|" \
    "$(st "hi <pasted_content id=\"y\">payload</pasted_content>${NL}after")"
  r "core_strip_pasted: unterminated block drops everything after it" "keep|" \
    "$(st "keep${NL}<pasted_content id=\"z\">${NL}x${NL}y")"
  r "core_strip_pasted: text without a paste passes through" "a b||c \`d\` \$(e)|" \
    "$(st "a b${NL}${NL}c \`d\` \$(e)")"

  # --- core_sanitize_id: RETIRED 2026-11-13 --------------------------------------------------
  # kt_ps_sanitize_id stripped bytes (non-injective) and is gone; the ledger id is kt_session_key in
  # lib-state-key.sh, pinned by tests/repros/state-dir-model-facing.sh M8 (shell == Python).

  # --- core_two_configs_two_caches (G1) -------------------------------------------------------
  # Two configs naming two knowledge folders share ONE cache dir. With a single fixed cache name
  # each call would evict the other's entry; keyed by config path, each one's second call is a
  # hit. A miss rewrites through mv (new inode); a hit leaves the file alone.
  KB="$T/kf-b"; mk_kf "$KB"
  CFGA="$T/cfg/a.local.md"; mk_cfg "$CFGA" "$KF"
  CFGB="$T/cfg/b.local.md"; mk_cfg "$CFGB" "$KB"
  mksd "$T/cache-2"
  ps_call "$CFGA" "$T/cache-2" "$PROMPT_PAY" "$T/ledger-2a1"; A1=$(out)
  ps_call "$CFGB" "$T/cache-2" "$PROMPT_PAY" "$T/ledger-2b1"; B1=$(out)
  I1=$(inodes "$T/cache-2")
  r "core_two_configs_two_caches: one cache file per config" 2 "$(ncache "$T/cache-2")"
  ps_call "$CFGA" "$T/cache-2" "$PROMPT_PAY" "$T/ledger-2a2"; A2=$(out)
  ps_call "$CFGB" "$T/cache-2" "$PROMPT_PAY" "$T/ledger-2b2"; B2=$(out)
  r "core_two_configs_two_caches: second call for each was a hit (no rewrite)" "1|$I1" \
    "$( [ -n "$I1" ] && echo 1 || echo 0)|$(inodes "$T/cache-2")"
  r "core_two_configs_two_caches: A injects A's folder on miss and hit" "1|1" \
    "$(ps_has_line "$A1" "- $KF/projects/proj-b/deposits.md")|$(ps_has_line "$A2" "- $KF/projects/proj-b/deposits.md")"
  r "core_two_configs_two_caches: B injects B's folder on miss and hit" "1|1" \
    "$(ps_has_line "$B1" "- $KB/projects/proj-b/deposits.md")|$(ps_has_line "$B2" "- $KB/projects/proj-b/deposits.md")"

  # --- core_cache_symlink_refused (at the keyed name) -------------------------------------------
  # G1 renamed the cache, so test-prompt-context-check.sh's symlink arms now plant the OLD name
  # and no longer reach the cache this lib reads. These arms plant the name it actually uses.
  PK=$(printf '%s' "$CFG" | cksum | awk '{print $1}')
  KEYED="aria-prompt-config.$PK.cache"
  mksd "$T/cache-l"
  printf 'touch "%s"\n' "$T/sym-marker" > "$T/evil.sh"; cp "$T/evil.sh" "$T/evil.orig"
  ln -s "$T/evil.sh" "$T/cache-l/aria-knowledge-$UIDN/$KEYED"
  ps_call "$CFG" "$T/cache-l" "$PROMPT_PAY" "$T/ledger-l"
  r "core_cache_symlink_refused: never executed (no marker)" 0 "$( [ -e "$T/sym-marker" ] && echo 1 || echo 0)"
  r "core_cache_symlink_refused: output still correct" 1 "$(ps_has_line "$(out)" "- $KF/projects/proj-b/deposits.md")"
  r "core_cache_symlink_refused: link target left unmodified" 1 "$(cmp -s "$T/evil.sh" "$T/evil.orig" && echo 1 || echo 0)"
  # A valid-looking data cache (right header and key) naming a DIFFERENT folder, behind a link.
  KS="$T/kf-s"; mk_kf "$KS"
  VKEY=$(cksum "$CFG" "$PS_SD/config.sh")
  VKEY="$(printf '%s\n' "$VKEY" | sed -n 1p) | $(printf '%s\n' "$VKEY" | sed -n 2p)"
  printf '%s\n' "aria-prompt-config 1" "$VKEY" true "" "$KS" true true \
    "proj-a:proj-a,proj-b:proj-b,proj-c:proj-c" end > "$T/planted.dat"
  mksd "$T/cache-v"
  ln -s "$T/planted.dat" "$T/cache-v/aria-knowledge-$UIDN/$KEYED"
  ps_call "$CFG" "$T/cache-v" "$PROMPT_PAY" "$T/ledger-v"
  r "core_cache_symlink_refused: planted data behind a link is not used" "1|0" \
    "$(ps_has_line "$(out)" "- $KF/projects/proj-b/deposits.md")|$(out | grep -cF -- "$KS/")"
  # Control: the SAME data as a regular file at the same name IS used — so the arm above is
  # refusing the link, not rejecting a malformed entry.
  mksd "$T/cache-w"
  cp "$T/planted.dat" "$T/cache-w/aria-knowledge-$UIDN/$KEYED"
  ps_call "$CFG" "$T/cache-w" "$PROMPT_PAY" "$T/ledger-w"
  r "core_cache_symlink_refused: control — the same data as a regular file is used" 1 \
    "$(ps_has_line "$(out)" "- $KS/projects/proj-b/deposits.md")"
}
PS_RESULTS=$(ps_body)

# Every `r` call in ps_body reports exactly once; raise this when adding a check.
PS_EXPECTED=60
PS_GOT=0
PS_TAB=$(printf '\t')
PS_OLD_IFS=$IFS
while IFS="$PS_TAB" read -r ps_name ps_exp ps_act; do
  if [ -n "$ps_name" ]; then
    PS_GOT=$((PS_GOT + 1))
    assert_eq "prompt-surface-core: $ps_name" "$ps_exp" "$ps_act"
  fi
done <<PS_EOF
$PS_RESULTS
PS_EOF
IFS=$PS_OLD_IFS
assert_eq "prompt-surface-core: every check reported (ps_body ran to the end)" "$PS_EXPECTED" "$PS_GOT"
