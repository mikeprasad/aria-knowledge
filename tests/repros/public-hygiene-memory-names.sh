#!/bin/sh
# public-hygiene-memory-names.sh — gate D fails when a shipped plugin file names a memory file.
#
# Shipped skills used to cite rules by the maintainer's private memory-file names
# ("per <memory-file name>"). Those names mean nothing to any other user and leak the shape of
# a private memory corpus. Gate D now fails on a memory-file name in any TRACKED file whose path
# starts with `plugin-`. Other tracked paths (design docs, notes) are out of scope.
#
# ⛔ The token is BUILT AT RUNTIME and never written literally in this file: a literal one would
# make the plain grep that verifies the class find this repro itself.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REAL_GATE="$REPO_ROOT/plugin-claude-code/scripts/check-public-hygiene.sh"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.claude"
cp "$REAL_GATE" "$T/gate.sh"   # a copy, so the scratch run reads the gate as it is on disk now

tok="feedback""_example_rule"

# make_repo NAME PATH CONTENT -> a git repo whose one tracked file PATH holds CONTENT
make_repo() {
  r="$T/$1"; mkdir -p "$r/$(dirname "$2")"
  git -C "$r" init -q . && git -C "$r" config user.email t@t.t && git -C "$r" config user.name t
  printf '%s\n' "$3" > "$r/$2"; git -C "$r" add "$2"
  printf '%s' "$r"
}
# run_gate ROOT -> sets OUT and EX. HOME and the private list point at empty fixtures so the
# developer's real private list never decides a result here.
run_gate() {
  OUT=$(HOME="$T/home" ARIA_PRIVATE_TERMS_FILE="$T/no-list.txt" sh "$T/gate.sh" "$1" 2>&1); EX=$?
}
has() { case "$OUT" in *"$1"*) return 0 ;; *) return 1 ;; esac; }

# (a) positive: a memory-file name in a tracked plugin-*/ file fails the gate and names the file.
R=$(make_repo a "plugin-x/skills/s/SKILL.md" "Ask one at a time (per \`$tok\`).")
run_gate "$R"
[ "$EX" -eq 1 ] && ok "(a) memory-file name under plugin-*/ exits 1" || bad "(a) exit" "exit $EX: $OUT"
has "plugin-x/skills/s/SKILL.md" && ok "(a) the finding names the file" || bad "(a) file named" "$OUT"

# (b) guard: the same name outside plugin-*/ is out of scope.
R=$(make_repo b "docs/notes.md" "Ask one at a time (per \`$tok\`).")
run_gate "$R"
[ "$EX" -eq 0 ] && ok "(b) memory-file name outside plugin-*/ exits 0" || bad "(b) scope" "exit $EX: $OUT"

# (c) the real tree: no shipped plugin file names a memory file.
OUT=$(HOME="$T/home" ARIA_PRIVATE_TERMS_FILE="$T/no-list.txt" sh "$T/gate.sh" "$REPO_ROOT" 2>&1); EX=$?
[ "$EX" -eq 0 ] && ok "(c) real tree exits 0" || bad "(c) real tree" "exit $EX: $OUT"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
