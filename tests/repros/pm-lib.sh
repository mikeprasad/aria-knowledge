#!/bin/sh
# pm-lib.sh — pure-helper assertions for the aria-assist PM library.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../pm-helpers.sh"
. "$SCRIPT_DIR/../../plugin-claude-code/bin/pm-lib.sh"
PM_TMP="$(mktemp -d)"; trap 'rm -rf "$PM_TMP"' EXIT

assert_eq "now honors override" "1000000" "$(ARIA_PM_NOW_EPOCH=1000000 apm_now_epoch)"

NOW=1780531200   # 2026-06-04T00:00:00Z
THREE_AGO=$((NOW - 3*86400))
assert_eq "days_since 3d" "3" "$(ARIA_PM_NOW_EPOCH=$NOW apm_days_since "$THREE_AGO")"
assert_eq "days_since same" "0" "$(ARIA_PM_NOW_EPOCH=$NOW apm_days_since "$NOW")"

assert_eq "date_to_epoch" "1780531200" "$(apm_date_to_epoch 2026-06-04)"
assert_eq "tilde expand" "$HOME/x" "$(apm_expand_tilde '~/x')"

assert_eq "tier override wins" "WARM" "$(apm_tier 0 "" WARM 3 9)"
assert_eq "session in-progress forces ACTIVE" "ACTIVE" "$(apm_tier 99 in-progress "" 3 9)"
assert_eq "session handoff forces ACTIVE" "ACTIVE" "$(apm_tier 99 handoff "" 3 9)"
assert_eq "recency 2d -> ACTIVE" "ACTIVE" "$(apm_tier 2 "" "" 3 9)"
assert_eq "recency 3d -> ACTIVE (inclusive)" "ACTIVE" "$(apm_tier 3 "" "" 3 9)"
assert_eq "recency 5d -> WARM" "WARM" "$(apm_tier 5 "" "" 3 9)"
assert_eq "recency 9d -> WARM (inclusive)" "WARM" "$(apm_tier 9 "" "" 3 9)"
assert_eq "recency 20d -> DORMANT" "DORMANT" "$(apm_tier 20 "" "" 3 9)"
assert_eq "no signal -> DORMANT" "DORMANT" "$(apm_tier "" "" "" 3 9)"

MDIR="$PM_TMP/mr"; mkdir -p "$MDIR"
assert_eq "decide: no reviews -> generate" "generate" "$(apm_decide_mode "$MDIR")"
: > "$MDIR/2026-06-05.md"
assert_eq "decide: fresh unreviewed -> review" "review" "$(apm_decide_mode "$MDIR")"
printf '%s' "$(( $(date +%s) + 100 ))" > "$MDIR/.last-reviewed"
assert_eq "decide: reviewed -> generate" "generate" "$(apm_decide_mode "$MDIR")"
rm -f "$MDIR/.last-reviewed"; touch -t 202601010000 "$MDIR/2026-06-05.md"
assert_eq "decide: stale >24h -> generate" "generate" "$(apm_decide_mode "$MDIR")"

CK="$PM_TMP/ck"; make_fixture "$CK" "$(utc_iso 1780531200)"
assert_eq "checkpoint: no backlog -> noop" "" "$(apm_checkpoint_backlog "$CK")"
printf 'idea1\n' > "$CK/IDEAS-BACKLOG.md"; ( cd "$CK" && git add IDEAS-BACKLOG.md && git commit -q -m add )
assert_eq "checkpoint: clean tracked -> noop" "" "$(apm_checkpoint_backlog "$CK")"
printf 'idea2\n' >> "$CK/IDEAS-BACKLOG.md"
out=$(apm_checkpoint_backlog "$CK"); case "$out" in checkpointed*) ok=1 ;; *) ok=0 ;; esac
assert_eq "checkpoint: dirty tracked -> commits" "1" "$ok"
if git -C "$CK" diff --quiet HEAD -- IDEAS-BACKLOG.md; then cln=1; else cln=0; fi
assert_eq "checkpoint: tree clean after commit" "1" "$cln"
case "$(git -C "$CK" log -1 --format=%s)" in chore\(aria-pm\)*checkpoint*) m=1 ;; *) m=0 ;; esac
assert_eq "checkpoint: commit message stamped" "1" "$m"
assert_eq "checkpoint: non-repo -> noop" "" "$(apm_checkpoint_backlog "$PM_TMP/nope")"

pm_summary
exit "$PM_FAIL"
