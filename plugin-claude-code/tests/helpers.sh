# shellcheck shell=sh
APM_PASS=0; APM_FAIL=0
assert_eq() { # MSG EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then APM_PASS=$((APM_PASS+1)); printf '  ok: %s\n' "$1"
  else APM_FAIL=$((APM_FAIL+1)); printf '  FAIL: %s\n    expected: [%s]\n    actual:   [%s]\n' "$1" "$2" "$3"; fi
}
# utc_iso EPOCH -> UTC ISO8601 with trailing Z (so git parses it as UTC, not local)
utc_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
# make_fixture DIR ISO_DATE : a fake project git repo with one commit at ISO_DATE
make_fixture() {
  rm -rf "$1"; mkdir -p "$1"
  ( cd "$1" && git init -q && git config user.email t@t && git config user.name t \
    && echo seed > seed.txt && git add . \
    && GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git commit -q -m seed )
}
