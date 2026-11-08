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
KT_SURFACE_CACHE_DIR="$SCRATCH/cache"; export KT_SURFACE_CACHE_DIR
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
{
  printf '# notes\n'
  printf '`touch %s/m1`\n' "$T"
  printf '$(touch %s/m2)\n' "$T"
  printf 'ARIA_TASK\n'
  printf 'touch %s/m3\n' "$T"
  printf 'proj-b payments $HOME\n'
} > "$T/hostile.md"
run_cli "$T" --file "$T/hostile.md"
made=""
for m in m1 m2 m3; do [ -e "$T/$m" ] && made="$made $m"; done
case "$cli_out" in
  ""|"tags: "*) [ -z "$made" ] && ok "file_content_is_never_shell" || bad "file_content_is_never_shell" "markers created:$made" ;;
  *) bad "file_content_is_never_shell" "out '$cli_out' markers:$made" ;;
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

# --- exit_always_zero ---
if [ -s "$RC_FILE" ] && ! grep -qv '^0$' "$RC_FILE"; then
  ok "exit_always_zero"
else
  bad "exit_always_zero" "exit codes: $(tr '\n' ' ' < "$RC_FILE")"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
