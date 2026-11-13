# shellcheck shell=sh
# test-safe-create.sh — the shared safe create (kt_create_new / kt_is_ours, spec §5 Decision C)
# and the four shell writers of predictable names that use it:
#   log   kt_ps_log                   (lib-prompt-surface.sh)  → <state dir>/aria-surface-hook.log
#   kept  _kt_ps_append_kept           (via kt_ps_commit)       → <state dir>/aria-active-<sid>
#   match kt_match_record_ledger       (lib-index-match.sh)     → <state dir>/aria-active-<sid>
#   art   kt_artifact_record_ledger    (lib-tracked-artifacts.sh) → <state dir>/aria-active-<sid>
# (the private state dir since 2.58.0; before, the ledger was a predictable /tmp name)
# plus post-edit-check.sh's <state dir>/aria-session-inprogress-<sid> (fix round 1, R3; RED on 696e819 for
# its link, FIFO and window arms) and session-start-check.sh's sweeps, run with the test-only
# KT_TMP_SWEEP_ROOT pointing at a scratch dir reached through a symlink (R2; RED on 696e819).
#
# Sourced by tests/run.sh under `set -eu`. Same protocol as test-prompt-surface-core.sh: the body
# runs in a SUBSHELL with its own EXIT trap and prints one `name<TAB>expected<TAB>actual` line per
# check; the parent replays them through assert_eq and asserts the count, so a body that dies
# partway fails instead of silently reporting fewer checks.
#
# Every NAME lives in this test's scratch dir (never /tmp/aria-active-*), and every writer runs in
# its own `sh -e` process (the callers run under set -e) with HOME and TMPDIR isolated; the log
# writer's state dir is pointed at the arm's scratch dir. A run that could block on a FIFO goes through sc_bounded, so a
# hang fails the arm instead of the suite.
#
# Which arms were RED on 71b8ca8 (before the helper existed), and why:
#   safe_create_window_plant ×4 writers — STRUCTURAL: no writer called mktemp, so the shim never
#     fired (the create was a plain O_CREAT append with no exclusive step to plant inside).
#   safe_create_log_date_window — BEHAVIOURAL: kt_ps_log ran `date` between its checks and its
#     append, so a link planted then was written through.
#   safe_create_steady_state (absent ledger) — INSTRUMENT: no create helper, so link count 0.
#   safe_create_fail_safe, safe_create_sweep — new function / new sweep (did not exist).
#   safe_create_static_plants, log fifo + log dir — BEHAVIOURAL: kt_ps_log refused only a link and
#     a foreign file, so a FIFO of ours hung it and a directory killed its `set -e` caller.
# Labelled GUARDS (green before and after): the other 14 safe_create_static_plants rows (the
# 3e44761 checks already refused a name that existed before the run) and the existing-file half
# of steady state.

SC_SD="$(cd "$(dirname "$0")/../scripts" && pwd)"

sc_body() {
  set +e +u
  T="${TMPDIR:-/tmp}/aria-sc-$$"
  # The post-edit arms' in-progress cache lives in the private state dir (2.58.0), resolved under a
  # scratch KT_STATE_BASE in $T, so nothing here touches /tmp or the real per-user state dir.
  SC_PE_SID="scpe$$x$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d ' ')"
  trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
  rm -rf "$T"; mkdir -p "$T/home" "$T/tmpdir" "$T/bin-mk" "$T/bin-date" "$T/bin-link"

  r() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

  REAL_MKTEMP=$(command -v mktemp)
  REAL_DATE=$(command -v date)
  REAL_LINK=$(command -v link)
  REAL_RM=$(command -v rm)

  # drive.sh WRITER NAME — one writer, in its own `sh -e` (as its callers run), sourcing the
  # libs from this tree. Writes $SC_DONE when the writer returned (the caller survived set -e).
  cat > "$T/drive.sh" <<'DRIVE'
set -e
W=$1; N=$2
HOME=$SC_T/home; TMPDIR=$SC_T/tmpdir; export HOME TMPDIR
case $W in
  log)   . "$SC_SD/lib-prompt-surface.sh"; . "$SC_SD/lib-state-key.sh"
         # kt_ps_log names its file with kt_state_path in the RESOLVED state dir. The arm's scratch
         # dir stands in for it: the safe create is under test here, not the resolver.
         KT_STATE_DIR=${N%/*}; kt_ps_log sc-test step reason ;;
  kept)  . "$SC_SD/lib-prompt-surface.sh"; KT_PS_PENDING='projects/proj-a/hooks.md'; kt_ps_commit "$N" ;;
  match) . "$SC_SD/lib-index-match.sh"; KT_MATCH_FILES_TMP=$SC_T/matches; kt_match_record_ledger "$N" ;;
  art)   . "$SC_SD/lib-tracked-artifacts.sh"; KT_ARTIFACTS_COUNT=1
         KT_ARTIFACT_PATHS='projects/proj-a/SESSION.md
'; kt_artifact_record_ledger "$N" ;;
esac
: > "$SC_DONE"
DRIVE
  printf 'projects/proj-a/hooks.md — a matched file\n' > "$T/matches"
  SC_T=$T; export SC_T SC_SD

  # The name each writer writes, inside DIR.
  sc_name() { # WRITER DIR
    case $1 in log) echo "$2/aria-surface-hook.log" ;; *) echo "$2/aria-active-sc-$1" ;; esac
  }
  # What each writer appends (one line), to tell "it wrote" from "it did not".
  sc_line() { # WRITER
    case $1 in
      log) echo 'sc-test step reason' ;; kept) echo 'projects/proj-a/hooks.md' ;;
      match) echo 'projects/proj-a/hooks.md' ;; art) echo 'projects/proj-a/SESSION.md' ;;
    esac
  }
  # leftover DIR → number of create temps left in DIR
  leftover() { ls -A "$1" 2>/dev/null | grep -c '^\.aria-new\.'; }

  # sc_bounded SECONDS CMD... — runs CMD in the background; SC_BOUNDED=ok if it finished within
  # SECONDS, else hung. On a hang every FIFO under $T is opened read-write (never blocks) to
  # release a writer stuck opening it, then the run is killed. No `timeout` binary needed.
  sc_bounded() {
    _sb_s=$1; shift
    "$@" </dev/null >/dev/null 2>&1 &
    _sb_p=$!; _sb_i=0; SC_BOUNDED=ok
    while kill -0 "$_sb_p" 2>/dev/null; do
      _sb_i=$((_sb_i + 1))
      if [ "$_sb_i" -gt $((_sb_s * 10)) ]; then
        SC_BOUNDED=hung
        for _sb_f in $(find "$T" -type p 2>/dev/null); do
          exec 9<>"$_sb_f"; exec 9>&-
        done
        kill "$_sb_p" 2>/dev/null
        break
      fi
      sleep 0.1
    done
    wait "$_sb_p" 2>/dev/null
  }
  # run_w WRITER NAME [ENV…] — bounded run of one writer; sets SC_BOUNDED and DONE (1/0).
  run_w() {
    _rw_w=$1; _rw_n=$2; shift 2
    rm -f "$T/done"
    sc_bounded 5 env SC_DONE="$T/done" "$@" sh "$T/drive.sh" "$_rw_w" "$_rw_n"
    if [ -e "$T/done" ]; then DONE=1; else DONE=0; fi
  }

  # --- safe_create_static_plants (names planted BEFORE the run; guards except kt_ps_log fifo/dir) -
  for W in log kept match art; do
    for K in filelink dangling fifo dir; do
      D="$T/s-$W-$K"; mkdir -p "$D"; N=$(sc_name "$W" "$D"); TG="$T/s-$W-$K.tgt"
      case $K in
        filelink) printf 'keep\n' > "$TG"; ln -s "$TG" "$N" ;;
        dangling) ln -s "$TG" "$N" ;;
        fifo)     mkfifo "$N" ;;
        dir)      mkdir "$N" ;;
      esac
      run_w "$W" "$N"
      case $K in
        filelink) I=$( [ "$(cat "$TG" 2>/dev/null)" = keep ] && [ -L "$N" ] && echo 1 || echo 0) ;;
        dangling) I=$( [ ! -e "$TG" ] && [ -L "$N" ] && echo 1 || echo 0) ;;
        fifo)     I=$( [ -p "$N" ] && echo 1 || echo 0) ;;
        dir)      I=$( [ -d "$N" ] && [ -z "$(ls -A "$N")" ] && echo 1 || echo 0) ;;
      esac
      r "safe_create_static_plants: $W $K → bounded|intact|caller-survived|temps-left" \
        "ok|1|1|0" "$SC_BOUNDED|$I|$DONE|$(leftover "$D")"
    done
  done

  # --- safe_create_window_plant (RED on 71b8ca8: structural) -----------------------------------
  # A mktemp shim plants at NAME when it is asked for the create temp, i.e. AFTER the writer's
  # existence test and BEFORE link — the only window left. SC_WIN_FIRED is the instrument check.
  cat > "$T/bin-mk/mktemp" <<SHIM
#!/bin/sh
case "\$*" in
  *.aria-new.*)
    : > "\$SC_WIN_FIRED"
    if [ -n "\${SC_WIN_NAME:-}" ] && [ ! -e "\$SC_WIN_NAME" ] && [ ! -L "\$SC_WIN_NAME" ]; then
      case "\$SC_WIN_KIND" in
        link) ln -s "\$SC_WIN_TGT" "\$SC_WIN_NAME" ;;
        fifo) mkfifo "\$SC_WIN_NAME" ;;
      esac
    fi ;;
esac
exec "$REAL_MKTEMP" "\$@"
SHIM
  chmod +x "$T/bin-mk/mktemp"
  for W in log kept match art; do
    for K in link fifo; do
      D="$T/w-$W-$K"; mkdir -p "$D"; N=$(sc_name "$W" "$D"); TG="$T/w-$W-$K.tgt"
      printf 'keep\n' > "$TG"; rm -f "$T/fired"
      run_w "$W" "$N" PATH="$T/bin-mk:$PATH" SC_WIN_FIRED="$T/fired" SC_WIN_NAME="$N" \
        SC_WIN_KIND="$K" SC_WIN_TGT="$TG"
      F=$( [ -e "$T/fired" ] && echo 1 || echo 0)
      case $K in
        link) I=$( [ "$(cat "$TG")" = keep ] && [ -L "$N" ] && echo 1 || echo 0) ;;
        fifo) I=$( [ "$(cat "$TG")" = keep ] && [ -p "$N" ] && echo 1 || echo 0) ;;
      esac
      r "safe_create_window_plant: $W $K in the create window → shim-fired|target-intact|bounded|temps-left" \
        "1|1|ok|0" "$F|$I|$SC_BOUNDED|$(leftover "$D")"
    done
  done

  # --- safe_create_log_date_window (RED on 71b8ca8: behavioural) -------------------------------
  # kt_ps_log forks `date`; a shim plants a link at the log name when it runs — at an absent
  # name, or over a just-created empty file (a writer whose check ran before `date` has already
  # created it). The append must not follow it — so `date` has to run before the
  # create/ownership check, not between it and the append.
  cat > "$T/bin-date/date" <<SHIM
#!/bin/sh
N=\${SC_DATE_NAME:-}
if [ -n "\$N" ] && [ ! -L "\$N" ] && { [ ! -e "\$N" ] || { [ -f "\$N" ] && [ ! -s "\$N" ]; }; }; then
  rm -f "\$N"; ln -s "\$SC_DATE_TGT" "\$N"; : > "\$SC_DATE_FIRED"
fi
exec "$REAL_DATE" "\$@"
SHIM
  chmod +x "$T/bin-date/date"
  D="$T/dw"; mkdir -p "$D"; N=$(sc_name log "$D"); printf 'keep\n' > "$T/dw.tgt"; rm -f "$T/dfired"
  run_w log "$N" PATH="$T/bin-date:$PATH" SC_DATE_NAME="$N" SC_DATE_TGT="$T/dw.tgt" \
    SC_DATE_FIRED="$T/dfired"
  r "safe_create_log_date_window: a link planted while kt_ps_log runs date → shim-fired|target-intact|still-link|bounded" \
    "1|1|1|ok" "$( [ -e "$T/dfired" ] && echo 1 || echo 0)|$( [ "$(cat "$T/dw.tgt")" = keep ] && echo 1 || echo 0)|$( [ -L "$N" ] && echo 1 || echo 0)|$SC_BOUNDED"

  # --- safe_create_steady_state ----------------------------------------------------------------
  # `link` is called only by kt_create_new, so a counting shim counts create attempts exactly.
  printf '#!/bin/sh\nprintf "x\\n" >> "$SC_LINKS"\nexec "%s" "$@"\n' "$REAL_LINK" > "$T/bin-link/link"
  chmod +x "$T/bin-link/link"
  links() { if [ -f "$T/links" ]; then wc -l < "$T/links" | tr -d ' '; else echo 0; fi; }
  # Absent ledger, two records (RED on 71b8ca8: no create helper, count 0).
  D="$T/st-absent"; mkdir -p "$D"; N=$(sc_name match "$D"); rm -f "$T/links"
  run_w match "$N" PATH="$T/bin-link:$PATH" SC_LINKS="$T/links"
  run_w match "$N" PATH="$T/bin-link:$PATH" SC_LINKS="$T/links"
  r "safe_create_steady_state: two records into an absent ledger → link-calls|records|regular" \
    "1|2|1" "$(links)|$(grep -cxF 'projects/proj-a/hooks.md' "$N" 2>/dev/null)|$( [ -f "$N" ] && [ ! -L "$N" ] && echo 1 || echo 0)"
  # Existing file of ours: no create call at all, the line is appended (GUARD).
  for W in log kept match art; do
    D="$T/st-$W"; mkdir -p "$D"; N=$(sc_name "$W" "$D"); : > "$N"; rm -f "$T/links"
    run_w "$W" "$N" PATH="$T/bin-link:$PATH" SC_LINKS="$T/links"
    r "safe_create_steady_state (guard): $W into an existing file → link-calls|appended" \
      "0|1" "$(links)|$(grep -cF "$(sc_line "$W")" "$N" 2>/dev/null)"
  done

  # --- safe_create_fail_safe (Review Focus 4) --------------------------------------------------
  # kt_create_new called directly. fs DIR NAME [PATH] → its return status, run from DIR.
  fs() {
    ( cd "$1" || exit 9; . "$SC_SD/lib-tracked-artifacts.sh"; [ -n "${3:-}" ] && PATH=$3
      kt_create_new "$2"; echo $? ) 2>/dev/null
  }
  ROOTUSER=$( [ "$(id -u)" = 0 ] && echo root || echo user)
  # A NAME with no `/` is created in the current directory (the pinned body maps it to `.`), and
  # nowhere else; in an unwritable current directory it fails safe.
  mkdir -p "$T/fs1" "$T/fs2"
  RC=$(fs "$T/fs1" plainname)
  r "safe_create_fail_safe: NAME without / in a writable cwd → rc|regular-ours-here|only-entry|temps-left" \
    "0|1|plainname|0" "$RC|$( [ -f "$T/fs1/plainname" ] && [ ! -L "$T/fs1/plainname" ] && [ -O "$T/fs1/plainname" ] && echo 1 || echo 0)|$(ls -A "$T/fs1")|$(leftover "$T/fs1")"
  chmod 500 "$T/fs2"
  RC=$(fs "$T/fs2" plainname)
  r "safe_create_fail_safe: NAME without / in an unwritable cwd → rc|file|temps-left ($ROOTUSER)" \
    "1|0|0" "$RC|$( [ -e "$T/fs2/plainname" ] && echo 1 || echo 0)|$(leftover "$T/fs2")"
  chmod 700 "$T/fs2"
  mkdir -p "$T/fs3"; chmod 500 "$T/fs3"
  RC=$(fs "$T" "$T/fs3/x")
  r "safe_create_fail_safe: NAME in a chmod 500 dir (mktemp fails) → rc|file|temps-left ($ROOTUSER)" \
    "1|0|0" "$RC|$( [ -e "$T/fs3/x" ] && echo 1 || echo 0)|$(leftover "$T/fs3")"
  chmod 700 "$T/fs3"
  # PATH holding mktemp and rm but no link.
  mkdir -p "$T/fs4" "$T/nolink"
  ln -s "$REAL_MKTEMP" "$T/nolink/mktemp"; ln -s "$REAL_RM" "$T/nolink/rm"
  r "safe_create_fail_safe: instrument — the no-link PATH really has no link" 0 \
    "$( (PATH="$T/nolink"; command -v link >/dev/null 2>&1) && echo 1 || echo 0)"
  RC=$(fs "$T" "$T/fs4/x" "$T/nolink")
  r "safe_create_fail_safe: link missing from PATH → rc|file|temps-left" \
    "1|0|0" "$RC|$( [ -e "$T/fs4/x" ] && echo 1 || echo 0)|$(leftover "$T/fs4")"
  # Positive control: the same dir and helper with the full PATH DOES create — so the arm above
  # is failing on the missing link, not on anything else.
  RC=$(fs "$T" "$T/fs4/y")
  r "safe_create_fail_safe: control — full PATH creates in the same dir → rc|regular" \
    "0|1" "$RC|$( [ -f "$T/fs4/y" ] && [ ! -L "$T/fs4/y" ] && echo 1 || echo 0)"
  # An existing regular file is never touched.
  printf 'keep\n' > "$T/fs4/z"
  RC=$(fs "$T" "$T/fs4/z")
  r "safe_create_fail_safe: an existing file → rc|content" "1|keep" "$RC|$(cat "$T/fs4/z")"

  # --- safe_create_post_edit (spec §5, fix round 1 R3) ---------------------------------------------
  # post-edit-check.sh records "this session already marked this project in progress" in
  # <state dir>/aria-session-inprogress-<session id> (/tmp before 2.58.0), a predictable name it used
  # to append to with a plain `>>` and no ownership check. RED on 696e819 for the link, FIFO and
  # window arms; the positive
  # arm is a guard (it also proves the scratch project really reaches the write).
  mkdir -p "$T/pe/proj" "$T/pe/kf" "$T/pe/home" "$T/pe/sb"
  mkdir -m 700 "$T/pe/sb/aria-knowledge-$(id -u)"
  printf '# p\n' > "$T/pe/proj/PROGRESS.md"; printf 'x\n' > "$T/pe/proj/a.txt"
  printf -- '---\nknowledge_folder: %s\nsession_state: true\n---\n' "$T/pe/kf" > "$T/pe/cfg.md"
  # pe_run SUFFIX [ENV…] — one post-edit run for session id $SC_PE_SID<SUFFIX>, bounded.
  pe_run() {
    _pe_sid="$SC_PE_SID$1"; shift
    printf '{"session_id":"%s","tool_input":{"file_path":"%s"}}' "$_pe_sid" "$T/pe/proj/a.txt" > "$T/pe/in.json"
    printf 'sh "$1" < "$2"\n' > "$T/pe/run.sh"
    sc_bounded 5 env HOME="$T/pe/home" KT_CONFIG="$T/pe/cfg.md" TMPDIR="$T/tmpdir" KT_STATE_BASE="$T/pe/sb" "$@" \
      sh "$T/pe/run.sh" "$SC_SD/post-edit-check.sh" "$T/pe/in.json"
  }
  PEL="$T/pe/sb/aria-knowledge-$(id -u)/aria-session-inprogress-${SC_PE_SID}"
  # Positive: no plant → the ledger is created, regular and ours, holding the project root once
  # (and a second edit does not add it again).
  pe_run p; pe_run p
  r "safe_create_post_edit: no plant → regular-ours|root-recorded-once|bounded" "1|1|ok" \
    "$( [ -f "${PEL}p" ] && [ ! -L "${PEL}p" ] && [ -O "${PEL}p" ] && echo 1 || echo 0)|$(grep -cxF "$T/pe/proj" "${PEL}p" 2>/dev/null)|$SC_BOUNDED"
  # A link to a file planted at the name: never written through.
  printf 'keep\n' > "$T/pe/l.tgt"; ln -s "$T/pe/l.tgt" "${PEL}l"
  pe_run l
  r "safe_create_post_edit: a planted link → target-intact|still-link|bounded" "1|1|ok" \
    "$( [ "$(cat "$T/pe/l.tgt")" = keep ] && echo 1 || echo 0)|$( [ -L "${PEL}l" ] && echo 1 || echo 0)|$SC_BOUNDED"
  # A FIFO planted at the name: never opened.
  mkfifo "${PEL}f"
  pe_run f
  r "safe_create_post_edit: a planted FIFO → bounded|still-fifo" "ok|1" "$SC_BOUNDED|$( [ -p "${PEL}f" ] && echo 1 || echo 0)"
  # A link planted in the create window (the mktemp shim above): harmless.
  printf 'keep\n' > "$T/pe/w.tgt"; rm -f "$T/fired"
  pe_run w PATH="$T/bin-mk:$PATH" SC_WIN_FIRED="$T/fired" SC_WIN_NAME="${PEL}w" SC_WIN_KIND=link \
    SC_WIN_TGT="$T/pe/w.tgt"
  r "safe_create_post_edit: a link planted in the create window → shim-fired|target-intact|bounded" "1|1|ok" \
    "$( [ -e "$T/fired" ] && echo 1 || echo 0)|$( [ "$(cat "$T/pe/w.tgt")" = keep ] && echo 1 || echo 0)|$SC_BOUNDED"

  # --- safe_create_sweep -----------------------------------------------------------------------
  # session-start-check.sh sweeps stale aria files from /tmp and the surfacing cache dir. Its /tmp
  # root is overridden (KT_TMP_SWEEP_ROOT, test-only) to a scratch dir reached through a SYMLINK, as
  # macOS /tmp is: `find <link> -maxdepth 1` does not follow a symlinked start point, which is why
  # the sweeps never ran on macOS before fix round 1 (R2). The real /tmp is never swept here.
  mkdir -p "$T/cache" "$T/realtmp"; ln -s "$T/realtmp" "$T/tmplink"
  : > "$T/cache/.aria-new.OLD123"; touch -t 202001010000 "$T/cache/.aria-new.OLD123"
  : > "$T/cache/.aria-new.NEW123"
  for _sw in aria-active-scOLD aria-session-inprogress-scOLD .aria-new.scOLD; do
    : > "$T/realtmp/$_sw"; touch -t 202001010000 "$T/realtmp/$_sw"
  done
  : > "$T/realtmp/aria-active-scNEW"
  # The second root is $TMPDIR, where the surfacing debug log (and so its create temps) lived
  # before 2.58.0; KT_SURFACE_CACHE_DIR, which could move it, is retired.
  HOME="$T/home" KT_CONFIG="$T/home/absent.local.md" \
    KT_TMP_SWEEP_ROOT="$T/tmplink" TMPDIR="$T/cache" sh "$SC_SD/session-start-check.sh" </dev/null >/dev/null 2>&1
  r "safe_create_sweep: TMPDIR — a 2020 .aria-new.* goes, a fresh one stays → old|new" "0|1" \
    "$( [ -e "$T/cache/.aria-new.OLD123" ] && echo 1 || echo 0)|$( [ -e "$T/cache/.aria-new.NEW123" ] && echo 1 || echo 0)"
  r "safe_create_sweep: /tmp root through a symlink — stale active|inprogress|create-temp go, fresh active stays" \
    "0|0|0|1" "$( [ -e "$T/realtmp/aria-active-scOLD" ] && echo 1 || echo 0)|$( [ -e "$T/realtmp/aria-session-inprogress-scOLD" ] && echo 1 || echo 0)|$( [ -e "$T/realtmp/.aria-new.scOLD" ] && echo 1 || echo 0)|$( [ -e "$T/realtmp/aria-active-scNEW" ] && echo 1 || echo 0)"
}
SC_RESULTS=$(sc_body)

# Every `r` call in sc_body reports exactly once; raise this when adding a check.
SC_EXPECTED=43
SC_GOT=0
SC_TAB=$(printf '\t')
SC_OLD_IFS=$IFS
while IFS="$SC_TAB" read -r sc_name sc_exp sc_act; do
  if [ -n "$sc_name" ]; then
    SC_GOT=$((SC_GOT + 1))
    assert_eq "safe-create: $sc_name" "$sc_exp" "$sc_act"
  fi
done <<SC_EOF
$SC_RESULTS
SC_EOF
IFS=$SC_OLD_IFS
assert_eq "safe-create: every check reported (sc_body ran to the end)" "$SC_EXPECTED" "$SC_GOT"
