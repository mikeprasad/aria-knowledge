#!/bin/sh
# public-hygiene-private-terms.sh — gate D also reads an UNTRACKED private name list.
#
# Gate D's built-in TERMS/CODES/ARTIFACTS live inside this public repo, so a private name
# can only be listed there by publishing it. Private names that were never listed passed
# silently. The gate now also reads ${ARIA_PRIVATE_TERMS_FILE:-$HOME/.claude/aria-private-terms.txt}:
# one entry per line, `#` comments, `path:X` matched path-anchored like CODES, every other
# line matched like TERMS (case-insensitive substring), never echoing the whole list.
#
# Every term below is SYNTHETIC (zqx…). A real private name must never appear in this file:
# it is tracked, and the gate itself would then have to exclude it.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$REPO_ROOT/plugin-claude-code/scripts/check-public-hygiene.sh"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.claude"

# make_repo NAME CONTENT -> a git repo whose one tracked file holds CONTENT
make_repo() {
  r="$T/$1"; mkdir -p "$r"
  git -C "$r" init -q . && git -C "$r" config user.email t@t.t && git -C "$r" config user.name t
  printf '%s\n' "$2" > "$r/a.md"; git -C "$r" add a.md
  printf '%s' "$r"
}
# run_gate ROOT LIST_FILE -> sets OUT and EX. HOME points at an empty fixture so the
# developer's real private list never leaks into a test result.
run_gate() {
  OUT=$(HOME="$T/home" ARIA_PRIVATE_TERMS_FILE="$2" sh "$GATE" "$1" 2>&1); EX=$?
}
has() { case "$OUT" in *"$1"*) return 0 ;; *) return 1 ;; esac; }

printf 'zqxprivterm\n' > "$T/one.txt"

# A1 positive control: list loaded, nothing planted -> clean, and the count is stated.
R=$(make_repo a1 "hello world"); run_gate "$R" "$T/one.txt"
[ "$EX" -eq 0 ] && ok "A1 clean repo with a loaded list exits 0" || bad "A1 clean repo" "exit $EX: $OUT"
has "private terms: 1 loaded from" && ok "A1 summary states the count" || bad "A1 summary" "$OUT"

# A2 a planted private term fails the gate (exit code, not just output — a class that prints
# but does not feed the verdict exits 0, which this gate has done before).
R=$(make_repo a2 "see zqxprivterm here"); run_gate "$R" "$T/one.txt"
[ "$EX" -eq 1 ] && ok "A2 planted term exits 1" || bad "A2 planted term" "exit $EX"
# A3 case-insensitive, like TERMS
R=$(make_repo a3 "see ZQXPRIVTERM here"); run_gate "$R" "$T/one.txt"
[ "$EX" -eq 1 ] && ok "A3 uppercase planted term exits 1" || bad "A3 case" "exit $EX"

# B path: entries are anchored like CODES — `x/` matches, the bare word does not.
printf 'path:zqxdir/\n' > "$T/path.txt"
R=$(make_repo b1 "see ~/Projects/zqxdir/notes.md"); run_gate "$R" "$T/path.txt"
[ "$EX" -eq 1 ] && ok "B1 path entry matches zqxdir/" || bad "B1 path match" "exit $EX"
R=$(make_repo b2 "the zqxdir word on its own"); run_gate "$R" "$T/path.txt"
[ "$EX" -eq 0 ] && ok "B2 path entry ignores the bare word" || bad "B2 path bare word" "exit $EX: $OUT"

# C absent file is REPORTED, never silent, and is not an error.
R=$(make_repo c1 "see zqxprivterm here"); run_gate "$R" "$T/does-not-exist.txt"
[ "$EX" -eq 0 ] && ok "C1 absent list passes (public lists only)" || bad "C1 absent" "exit $EX"
has "private terms: none (file absent)" && ok "C1 says the list is absent" || bad "C1 summary" "$OUT"
# C2 the default path is used when the override is unset
cp "$T/one.txt" "$T/home/.claude/aria-private-terms.txt"
R=$(make_repo c2 "see zqxprivterm here")
OUT=$(HOME="$T/home" sh "$GATE" "$R" 2>&1); EX=$?; rm -f "$T/home/.claude/aria-private-terms.txt"
[ "$EX" -eq 1 ] && ok "C2 default \$HOME/.claude path is read" || bad "C2 default path" "exit $EX"

# D regex metacharacters in a term are literal (a dot must not be a wildcard).
printf 'zqx.dot\n' > "$T/dot.txt"
R=$(make_repo d1 "see zqxadot here"); run_gate "$R" "$T/dot.txt"
[ "$EX" -eq 0 ] && ok "D1 dot is literal, not a wildcard" || bad "D1 metachar" "exit $EX"
R=$(make_repo d2 "see zqx.dot here"); run_gate "$R" "$T/dot.txt"
[ "$EX" -eq 1 ] && ok "D2 literal dotted term matches" || bad "D2 dotted term" "exit $EX"

# E comments, blank lines and CRLF are tolerated; only real entries count.
printf '# a comment\n\n  zqxcrlf  \r\n' > "$T/crlf.txt"
R=$(make_repo e1 "see zqxcrlf here"); run_gate "$R" "$T/crlf.txt"
[ "$EX" -eq 1 ] && ok "E1 CRLF/padded entry still matches" || bad "E1 crlf" "exit $EX"
has "private terms: 1 loaded from" && ok "E1 comments and blanks are not counted" || bad "E1 count" "$OUT"

# F an unpushed COMMIT MESSAGE carrying a private term fails the gate.
R=$(make_repo f1 "clean content"); git -C "$R" commit -qm "initial"
git init -q --bare "$T/f1-remote.git"; git -C "$R" remote add origin "$T/f1-remote.git"
git -C "$R" push -q -u origin HEAD 2>/dev/null
printf 'more\n' >> "$R/a.md"; git -C "$R" commit -qam "touch zqxprivterm notes"
run_gate "$R" "$T/one.txt"
[ "$EX" -eq 1 ] && ok "F1 private term in an unpushed commit message exits 1" || bad "F1 commit message" "exit $EX: $OUT"

# G the list itself is never echoed: an unmatched entry must not appear in the output.
printf 'zqxprivterm\nzqxneverseen\n' > "$T/two.txt"
R=$(make_repo g1 "see zqxprivterm here"); run_gate "$R" "$T/two.txt"
[ "$EX" -eq 1 ] && ok "G1 planted term still fails" || bad "G1 planted" "exit $EX"
has "zqxneverseen" && bad "G1 list echoed" "unmatched entry appeared in output" || ok "G1 unmatched entry is never printed"

# H the gate's own self-test still passes (exit 2 would mean the matcher is broken).
R=$(make_repo h1 "hello"); run_gate "$R" "$T/does-not-exist.txt"
[ "$EX" -ne 2 ] && ok "H1 existing self-test passes" || bad "H1 self-test" "exit 2"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
