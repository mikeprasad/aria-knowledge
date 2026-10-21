# shellcheck shell=sh
# test-content-dirs.sh — KT_CONTENT_DIRS is one constant, present with no config file.
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

out=$(KT_CONFIG=/nonexistent sh -c ". $ROOT/scripts/config.sh; printf %s \"\$KT_CONTENT_DIRS\"" 2>/dev/null || :)
assert_eq "content dirs constant" "approaches references projects rules guides decisions" "$out"
