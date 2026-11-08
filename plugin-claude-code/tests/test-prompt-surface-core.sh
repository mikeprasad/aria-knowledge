# shellcheck shell=sh
# test-prompt-surface-core.sh — scripts/lib-prompt-surface.sh (the shared capture core, spec C1)
#
# Sourced by tests/run.sh under `set -eu`. Same protocol as test-prompt-context-check.sh: the
# body runs in a SUBSHELL with its own EXIT trap and prints one `name<TAB>expected<TAB>actual`
# line per check; the parent replays them through assert_eq and asserts the count, so a body
# that dies partway fails instead of silently reporting fewer checks.
#
# Every lib call runs in its own subshell with HOME, TMPDIR, KT_CONFIG and KT_SURFACE_CACHE_DIR
# isolated, and with a ledger path inside the test dir (never /tmp/aria-active-*).

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
  trap 'rm -rf "$T"' EXIT
  rm -rf "$T"; mkdir -p "$T/tmpdir" "$T/cache"

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

  # ps_call CONFIG CACHE-DIR TEXT LEDGER — sources the lib in a fresh subshell and runs
  # kt_ps_surface. Sets PS_STATUS (empty if the lib could not run); stdout → $T/out.
  ps_call() {
    rm -f "$T/out" "$T/status"
    (
      HOME="$T/home"; KT_CONFIG=$1; KT_SURFACE_CACHE_DIR=$2; TMPDIR="$T/tmpdir"
      export HOME KT_CONFIG KT_SURFACE_CACHE_DIR TMPDIR
      KT_PS_SCRIPT_DIR="$PS_SD"; KT_PS_RUNTIME=core-test
      . "$PS_LIB" || exit 1
      kt_ps_surface "$3" "$4" > "$T/out" 2>"$T/err"
      printf '%s' "$KT_PS_STATUS" > "$T/status"
    ) 2>/dev/null
    PS_STATUS=$(cat "$T/status" 2>/dev/null)
  }
  out() { cat "$T/out" 2>/dev/null; }
  outsize() { if [ -f "$T/out" ]; then wc -c < "$T/out" | tr -d ' '; else echo missing; fi; }
  # ps_fn FUNCTION [ARGS…] — runs one lib function with stdin passed through.
  ps_fn() {
    ( KT_PS_SCRIPT_DIR="$PS_SD"; . "$PS_LIB" || exit 1; "$@" ) 2>/dev/null
  }
  inodes() { ls -i "$1" 2>/dev/null | grep 'aria-prompt-config' | awk '{print $1}' | sort | tr '\n' ' '; }
  ncache() { ls "$1" 2>/dev/null | grep -c '^aria-prompt-config.*\.cache$'; }

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
  rm -rf "$T/cache-f"; mkdir -p "$T/cache-f"
  ps_call "$CFGNI" "$T/cache-f" "$PROMPT_PAY" "$T/ledger-f"
  case "$PS_STATUS" in error:?*) h=1 ;; *) h=0 ;; esac
  r "core_failure_logged: index missing — status is error:<step>" "1|error:no-index" "$h|$PS_STATUS"
  r "core_failure_logged: nothing on stdout" 0 "$(outsize)"
  LOGF="$T/cache-f/aria-surface-hook.log"
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

  # --- core_sanitize_id -----------------------------------------------------------------
  r "core_sanitize_id: x/../y" "x..y" "$(ps_fn kt_ps_sanitize_id 'x/../y')"
  r "core_sanitize_id: spaces, shell and non-ASCII removed" "abc-d_e.f" "$(ps_fn kt_ps_sanitize_id 'a b$c;-d_e.f é')"

  # --- core_two_configs_two_caches (G1) -------------------------------------------------------
  # Two configs naming two knowledge folders share ONE cache dir. With a single fixed cache name
  # each call would evict the other's entry; keyed by config path, each one's second call is a
  # hit. A miss rewrites through mv (new inode); a hit leaves the file alone.
  KB="$T/kf-b"; mk_kf "$KB"
  CFGA="$T/cfg/a.local.md"; mk_cfg "$CFGA" "$KF"
  CFGB="$T/cfg/b.local.md"; mk_cfg "$CFGB" "$KB"
  rm -rf "$T/cache-2"; mkdir -p "$T/cache-2"
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
  rm -rf "$T/cache-l"; mkdir -p "$T/cache-l"
  printf 'touch "%s"\n' "$T/sym-marker" > "$T/evil.sh"; cp "$T/evil.sh" "$T/evil.orig"
  ln -s "$T/evil.sh" "$T/cache-l/$KEYED"
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
  rm -rf "$T/cache-v"; mkdir -p "$T/cache-v"
  ln -s "$T/planted.dat" "$T/cache-v/$KEYED"
  ps_call "$CFG" "$T/cache-v" "$PROMPT_PAY" "$T/ledger-v"
  r "core_cache_symlink_refused: planted data behind a link is not used" "1|0" \
    "$(ps_has_line "$(out)" "- $KF/projects/proj-b/deposits.md")|$(out | grep -cF -- "$KS/")"
  # Control: the SAME data as a regular file at the same name IS used — so the arm above is
  # refusing the link, not rejecting a malformed entry.
  rm -rf "$T/cache-w"; mkdir -p "$T/cache-w"
  cp "$T/planted.dat" "$T/cache-w/$KEYED"
  ps_call "$CFG" "$T/cache-w" "$PROMPT_PAY" "$T/ledger-w"
  r "core_cache_symlink_refused: control — the same data as a regular file is used" 1 \
    "$(ps_has_line "$(out)" "- $KS/projects/proj-b/deposits.md")"
}
PS_RESULTS=$(ps_body)

# Every `r` call in ps_body reports exactly once; raise this when adding a check.
PS_EXPECTED=37
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
