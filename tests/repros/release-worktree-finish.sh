#!/bin/sh
# tests/repros/release-worktree-finish.sh — built release zips survive removing a release worktree
# (spec docs/superpowers/specs/2026-11-07-rules-writer-version-guard-and-consume-expected-token-spec.md, I-5).
#
# `git worktree remove` refuses only on untracked or modified files; IGNORED files are neither, so the
# built zips (`aria-knowledge-*.zip`, `plugin-claude-cowork/*.plugin`, both ignored) are deleted
# without a prompt. release-worktree-finish.sh copies them to the main checkout, verifies each copy,
# and only then removes the worktree.
#
# C1 is the CONTROL: it shows a plain removal really loses the zip in this git, so a passing C2 means
# the helper saved it, not that git kept it. Hermetic: a throwaway repo under mktemp.
set -u
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$DIR/release-worktree-finish.sh"
TMP=$(mktemp -d); trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

mk_repo() { # $1 = dir → a repo with this project's ignore rules and one commit
  mkdir -p "$1/plugin-claude-cowork"
  ( cd "$1" && git init -q -b main . && git config user.email t@t && git config user.name t \
    && printf 'aria-knowledge-*.zip\n' > .gitignore && printf '*.plugin\n' > plugin-claude-cowork/.gitignore \
    && printf 'x\n' > README && git add -A && git commit -q -m init ) >/dev/null 2>&1
}
mk_wt() { # $1 = repo, $2 = worktree dir, $3 = branch; builds two "artifacts" in it
  git -C "$1" worktree add -q -b "$3" "$2" >/dev/null 2>&1
  printf 'ZIP-%s\n' "$3" > "$2/aria-knowledge-plugin-9.9.9.zip"
  printf 'PLUGIN-%s\n' "$3" > "$2/plugin-claude-cowork/aria-cowork-9.9.9.plugin"
}

# C1 — control: a plain removal deletes the ignored zip, with exit 0 and no prompt.
R="$TMP/r1"; mk_repo "$R"; mk_wt "$R" "$TMP/w1" c1
git -C "$R" check-ignore -q aria-knowledge-plugin-9.9.9.zip && _ign=yes || _ign=no
git -C "$R" worktree remove "$TMP/w1" >/dev/null 2>&1; _rc=$?
if [ "$_ign" = yes ] && [ "$_rc" -eq 0 ] && [ ! -e "$TMP/w1" ]; then
  ok "C1 control: plain 'git worktree remove' deleted the ignored zip (exit 0, no prompt)"
else
  bad "C1 control" "ignored=$_ign rc=$_rc exists=$([ -e "$TMP/w1" ] && echo yes || echo no) — the hazard did not reproduce, so C2 proves nothing"
fi

# C2 — the helper copies both artifacts byte-identical, then removes the worktree.
R="$TMP/r2"; mk_repo "$R"; mk_wt "$R" "$TMP/w2" c2
cp "$TMP/w2/aria-knowledge-plugin-9.9.9.zip" "$TMP/c2-zip"; cp "$TMP/w2/plugin-claude-cowork/aria-cowork-9.9.9.plugin" "$TMP/c2-plugin"
"$HELPER" "$TMP/w2" >/dev/null 2>&1; _rc=$?
if [ "$_rc" -eq 0 ] && [ ! -e "$TMP/w2" ] \
   && cmp -s "$TMP/c2-zip" "$R/aria-knowledge-plugin-9.9.9.zip" \
   && cmp -s "$TMP/c2-plugin" "$R/plugin-claude-cowork/aria-cowork-9.9.9.plugin"; then
  ok "C2 helper: both artifacts copied byte-identical to the main checkout, worktree removed"
else
  bad "C2 helper" "rc=$_rc worktree_exists=$([ -e "$TMP/w2" ] && echo yes || echo no) — artifacts missing or different in the main checkout"
fi

# C3 — destination unwritable: refuse, keep the worktree AND the zip.
R="$TMP/r3"; mk_repo "$R"; mk_wt "$R" "$TMP/w3" c3
chmod a-w "$R"
"$HELPER" "$TMP/w3" >/dev/null 2>"$TMP/c3.err"; _rc=$?
chmod u+w "$R"
if [ "$_rc" -ne 0 ] && grep -q "could not copy" "$TMP/c3.err" && [ -f "$TMP/w3/aria-knowledge-plugin-9.9.9.zip" ]; then
  ok "C3 unwritable destination: refused (rc=$_rc), worktree and zip kept"
else
  bad "C3 unwritable destination" "rc=$_rc zip_kept=$([ -f "$TMP/w3/aria-knowledge-plugin-9.9.9.zip" ] && echo yes || echo no)"
fi

# C4 — no artifacts: an empty glob must not pass for a successful copy.
R="$TMP/r4"; mk_repo "$R"; git -C "$R" worktree add -q -b c4 "$TMP/w4" >/dev/null 2>&1
"$HELPER" "$TMP/w4" >/dev/null 2>"$TMP/c4.err"; _rc=$?
if [ "$_rc" -ne 0 ] && grep -q "no release artifacts" "$TMP/c4.err" && [ -d "$TMP/w4" ]; then ok "C4 no artifacts: refused, worktree kept"
else bad "C4 no artifacts" "rc=$_rc exists=$([ -d "$TMP/w4" ] && echo yes || echo no)"; fi
"$HELPER" --no-artifacts "$TMP/w4" >/dev/null 2>&1; _rc=$?
if [ "$_rc" -eq 0 ] && [ ! -e "$TMP/w4" ]; then ok "C4 --no-artifacts: worktree removed"
else bad "C4 --no-artifacts" "rc=$_rc exists=$([ -e "$TMP/w4" ] && echo yes || echo no)"; fi

# C5 — pointed at the main checkout: refuse.
R="$TMP/r5"; mk_repo "$R"
"$HELPER" --no-artifacts "$R" >/dev/null 2>"$TMP/c5.err"; _rc=$?
if [ "$_rc" -ne 0 ] && grep -q "main checkout" "$TMP/c5.err" && [ -f "$R/README" ]; then ok "C5 main checkout: refused"
else bad "C5 main checkout" "rc=$_rc"; fi

printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
