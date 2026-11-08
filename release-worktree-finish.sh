#!/usr/bin/env bash
# release-worktree-finish.sh — finish a release built in a separate git worktree: copy its built
# artifacts to the main checkout, verify every copy, and only then remove the worktree.
#
#   ./release-worktree-finish.sh <worktree>                  copy, verify, remove
#   ./release-worktree-finish.sh --no-artifacts <worktree>   remove a worktree that built nothing
#
# Why this exists: the built artifacts are IGNORED files (`aria-knowledge-*.zip` at the root,
# `plugin-claude-cowork/*.plugin`). `git worktree remove` refuses only on untracked or modified files,
# and ignored files are neither, so a plain removal deletes the zips with exit 0 and no prompt
# (man git-worktree; reproduced by tests/repros/release-worktree-finish.sh C1). RELEASING.md's
# "Releasing from a worktree" section runs this as its last step.
#
# Refuses (non-zero, worktree left in place) when: a copy or its cmp fails; no artifacts are found
# and --no-artifacts was not given (an empty glob must not pass for a successful copy); the path is
# the main checkout; or git itself refuses the removal. Never uses --force.
set -u

die() { printf 'release-worktree-finish: %s\n' "$2" >&2; exit "$1"; }

NO_ARTIFACTS=0; WT=""
for arg in "$@"; do
  case "$arg" in
    --no-artifacts) NO_ARTIFACTS=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    -*) die 64 "unknown option: $arg" ;;
    *) [ -z "$WT" ] || die 64 "one worktree path only"; WT="$arg" ;;
  esac
done
[ -n "$WT" ] || die 64 "usage: $0 [--no-artifacts] <worktree>"
[ -d "$WT" ] || die 1 "not a directory: $WT"
WT=$(cd "$WT" && pwd -P)

top=$(git -C "$WT" rev-parse --show-toplevel 2>/dev/null) || die 1 "not a git worktree: $WT"
[ "$(cd "$top" && pwd -P)" = "$WT" ] || die 1 "give the worktree's top-level directory, not a subdirectory: $WT"
common=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die 1 "cannot resolve the repository for $WT"
[ "$(basename "$common")" = ".git" ] || die 1 "the repository at $common has no main checkout to copy into (bare repo?)"
MAIN=$(cd "$(dirname "$common")" && pwd -P)
[ "$MAIN" != "$WT" ] || die 1 "refusing: $WT is the main checkout, not a release worktree"

# Collect artifacts, relative to the worktree root.
artifacts=()
for f in "$WT"/aria-knowledge-*.zip "$WT"/plugin-claude-cowork/*.plugin; do
  [ -f "$f" ] && artifacts+=("${f#"$WT"/}")
done

if [ "${#artifacts[@]}" -eq 0 ] && [ "$NO_ARTIFACTS" -eq 0 ]; then
  die 1 "no release artifacts found in $WT (looked for aria-knowledge-*.zip and plugin-claude-cowork/*.plugin). If this worktree built nothing, re-run with --no-artifacts."
fi

failed=0
for rel in ${artifacts[@]+"${artifacts[@]}"}; do
  src="$WT/$rel"; dst="$MAIN/$rel"
  if mkdir -p "$(dirname "$dst")" 2>/dev/null && cp -p "$src" "$dst" 2>/dev/null && cmp -s "$src" "$dst"; then
    printf 'copied  %s  (%s bytes, cksum %s)\n' "$rel" "$(wc -c < "$dst" | tr -d ' ')" "$(cksum < "$dst" | cut -d' ' -f1)"
  else
    printf 'release-worktree-finish: could not copy %s to %s\n' "$rel" "$dst" >&2
    failed=1
  fi
done
[ "$failed" -eq 0 ] || die 1 "one or more artifacts were not copied and verified; the worktree was left in place: $WT"

git -C "$MAIN" worktree remove "$WT" || die 1 "git refused to remove $WT (uncommitted or untracked files?); the artifacts are already copied"
printf 'removed %s (%d artifact(s) kept in %s)\n' "$WT" "${#artifacts[@]}" "$MAIN"
