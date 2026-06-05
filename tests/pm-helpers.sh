# shellcheck shell=sh
# Shared helpers for the aria-assist (pm-*) repro suites. Sourced, never run directly.
PM_PASS=0; PM_FAIL=0
assert_eq() { # MSG EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then PM_PASS=$((PM_PASS+1)); printf '  ok: %s\n' "$1"
  else PM_FAIL=$((PM_FAIL+1)); printf '  FAIL: %s\n    expected: [%s]\n    actual:   [%s]\n' "$1" "$2" "$3"; fi
}
pm_summary() { printf '  (%d ok, %d fail)\n' "$PM_PASS" "$PM_FAIL"; }
# utc_iso EPOCH -> UTC ISO8601 with trailing Z
utc_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
# make_fixture DIR ISO_DATE : a fake project git repo with one commit at ISO_DATE
make_fixture() {
  rm -rf "$1"; mkdir -p "$1"
  ( cd "$1" && git init -q && git config user.email t@t && git config user.name t \
    && echo seed > seed.txt && git add . \
    && GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git commit -q -m seed )
}
