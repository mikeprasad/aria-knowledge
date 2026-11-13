#!/bin/sh
# surfacing-cli-references.sh — tests for the --file / --git-range reference
# inputs of scripts/aria-surface.sh. A reference carries no free text through a
# shell: the model passes a path or a ref range, the script reads the content.
#
# Run under sh or bash only.
#
# SURFACING_CLI overrides the CLI path (used for mutation checks).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLI="${SURFACING_CLI:-$REPO_ROOT/plugin-claude-code/scripts/aria-surface.sh}"
FIX="$SCRIPT_DIR/fixtures/surfacing"

PASS=0
FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/aria-surfacing-cli-test.XXXXXX") || exit 1
trap 'chmod -R u+w "$SCRATCH" 2>/dev/null; rm -rf "$SCRATCH"' EXIT
T="$SCRATCH/t"; mkdir -p "$T" "$SCRATCH/tmp" "$SCRATCH/home/.claude" "$SCRATCH/cache"
TMPDIR="$SCRATCH/tmp"; export TMPDIR
# The CLI's parse cache lives in the private state dir (2.58.0), here under a scratch base.
unset XDG_RUNTIME_DIR
KT_STATE_BASE="$SCRATCH/cache"; export KT_STATE_BASE
cat > "$SCRATCH/home/.claude/aria-knowledge.local.md" <<CFG
---
knowledge_folder: $FIX
projects_enabled: true
projects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c
---
CFG

RC_FILE="$SCRATCH/rc"; : > "$RC_FILE"
# run_cli <cwd> args... — stdout in cli_out, rc recorded for exit_always_zero.
run_cli() {
  _cwd=$1; shift
  cli_out=$(cd "$_cwd" && HOME="$SCRATCH/home" KT_CONFIG= KT_KNOWLEDGE_FOLDER= KT_PROJECTS_LIST= KT_PROJECTS_ENABLED= \
    sh "$CLI" "$@" </dev/null 2>/dev/null); cli_rc=$?
  echo "$cli_rc" >> "$RC_FILE"
}

# --- scratch git repo whose commit subject names proj-b payments ---
REPO="$SCRATCH/repo"; mkdir -p "$REPO"
(cd "$REPO" && git init -q . && git config user.email t@example.invalid && git config user.name t \
  && git commit -q --allow-empty -m "initial" && git tag base \
  && git commit -q --allow-empty -m "proj-b payments retry" && git tag tip) >/dev/null 2>&1

# --- file_ranks_from_content ---
printf '# proj-b payments\n\nSome body text.\n' > "$T/note.md"
run_cli "$T" --file "$T/note.md"
first=$(printf '%s\n' "$cli_out" | sed -n 1p)
second=$(printf '%s\n' "$cli_out" | sed -n 2p)
case "$first" in
  "tags: "*proj-b*payments*|"tags: "*payments*proj-b*)
    case "$second" in *proj-b*) ok "file_ranks_from_content" ;; *) bad "file_ranks_from_content" "first path '$second'" ;; esac ;;
  *) bad "file_ranks_from_content" "out '$cli_out'" ;;
esac

# --- git_range_ranks_from_subjects ---
run_cli "$REPO" --git-range base..tip
first=$(printf '%s\n' "$cli_out" | sed -n 1p)
second=$(printf '%s\n' "$cli_out" | sed -n 2p)
case "$first" in
  "tags: "*proj-b*payments*|"tags: "*payments*proj-b*)
    case "$second" in *proj-b*) ok "git_range_ranks_from_subjects" ;; *) bad "git_range_ranks_from_subjects" "first path '$second'" ;; esac ;;
  *) bad "git_range_ranks_from_subjects" "out '$cli_out'" ;;
esac

# --- file_content_is_never_shell ---
# hostile_content <markerdir> — backticks, $(...), a bare ARIA_TASK line then a
# touch line, plus words that must still rank (proj-b payments).
hostile_content() {
  printf '# notes\n'
  printf '`touch %s/m1`\n' "$1"
  printf '$(touch %s/m2)\n' "$1"
  printf 'ARIA_TASK\n'
  printf 'touch %s/m3\n' "$1"
  printf 'proj-b payments $HOME\n'
}
hostile_content "$T" > "$T/hostile.md"
run_cli "$T" --file "$T/hostile.md"
made=""
for m in m1 m2 m3; do [ -e "$T/$m" ] && made="$made $m"; done
# Firing control: the SAME content through a deliberately unsafe double-quoted
# command, against a separate marker dir with no spaces in its path. The
# detector must see markers here, or "no markers" above proves nothing.
CTL="$SCRATCH/ctl"; mkdir -p "$CTL"
ctl_c=$(hostile_content "$CTL")
sh -c "printf '%s' \"$ctl_c\"" >/dev/null 2>&1
ctl_made=""
for m in m1 m2; do [ -e "$CTL/$m" ] && ctl_made="$ctl_made $m"; done
case "$cli_out" in
  "tags: "*)
    if [ -n "$made" ]; then bad "file_content_is_never_shell" "markers created:$made"
    elif [ "$ctl_made" != " m1 m2" ]; then bad "file_content_is_never_shell" "control did not fire (markers:$ctl_made) — detector unproven"
    else ok "file_content_is_never_shell"; fi ;;
  *) bad "file_content_is_never_shell" "out '$cli_out' markers:$made (want a tags: line)" ;;
esac

# --- git_range_leading_dash_rejected ---
run_cli "$REPO" --git-range "--output=$T/x..HEAD"
if [ "$cli_out" = "unavailable: invalid --git-range" ] && [ ! -e "$T/x" ]; then
  ok "git_range_leading_dash_rejected"
else
  bad "git_range_leading_dash_rejected" "out '$cli_out' x-exists=$([ -e "$T/x" ] && echo yes || echo no)"
fi

# --- file_missing_unavailable ---
run_cli "$T" --file "$T/none.md"
[ "$cli_out" = "unavailable: invalid --file" ] && ok "file_missing_unavailable" \
  || bad "file_missing_unavailable" "out '$cli_out'"

# --- unknown_option_unavailable ---
run_cli "$T" --fil "$T/note.md"
o1=$cli_out
run_cli "$T" "--file=$T/note.md"
o2=$cli_out
if [ "$o1" = "unavailable: unknown option --fil" ] && [ "$o2" = "unavailable: unknown option --file" ]; then
  ok "unknown_option_unavailable"
else
  bad "unknown_option_unavailable" "--fil -> '$o1'; --file=x -> '$o2'"
fi

# --- unknown_option_name_stops_at_whitespace --- a prompt that starts with `--` must not be echoed
run_cli "$T" "--not-an-option some secret words"
if [ "$cli_out" = "unavailable: unknown option --not-an-option" ]; then ok "unknown_option_name_stops_at_whitespace"
else bad "unknown_option_name_stops_at_whitespace" "out '$cli_out'"; fi

# --- exit_always_zero ---
if [ -s "$RC_FILE" ] && ! grep -qv '^0$' "$RC_FILE"; then
  ok "exit_always_zero"
else
  bad "exit_always_zero" "exit codes: $(tr '\n' ' ' < "$RC_FILE")"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
