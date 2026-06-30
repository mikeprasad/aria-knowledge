# shellcheck shell=sh
# test-r22-planning-paths.sh — scaffold templates + the planning_paths config knob
# downgrade an edit to the abbreviated [Rule 22 · Planning] marker (still required),
# while deliverable templates and critical_paths keep the full assessment.
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
PRE="$ROOT/bin/pre-edit-check.sh"
POST="$ROOT/bin/post-edit-check.sh"

# --- transcript fixtures (in the suite's temp dir) ---
PP_TMP="${APM_TMP:-/tmp}/r22-pp"; mkdir -p "$PP_TMP"
MARKER_TX="$PP_TMP/marker.jsonl"
NOMARKER_TX="$PP_TMP/nomarker.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"[Rule 22 · Planning] findings.md"},{"type":"tool_use","id":"toolu_present_001","name":"Write","input":{"file_path":"x"}}]}}' > "$MARKER_TX"
{
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"please write the file"}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Writing it now."},{"type":"tool_use","id":"toolu_absent_001","name":"Write","input":{"file_path":"x"}}]}}'
} > "$NOMARKER_TX"

# fixture config: a user planning_path + a critical_path, valid absolute knowledge_folder elsewhere
PP_CFG="$PP_TMP/config.md"
printf '%s\n' '---' 'knowledge_folder: /tmp/kf-does-not-exist-r22pp' 'planning_paths: my-scaffolds' 'critical_paths: secret-stuff' '---' > "$PP_CFG"

SCAFFOLD="/tmp/proj/.claude/skills/audit-security/templates/findings.md"
DELIVERABLE="/tmp/proj/templates/deliverables/security-review/index.html"

# run_pre <file_path> <transcript> <tool_use_id> <session_id> [KT_CONFIG] -> stdout
pp_run_pre() {
  rm -f "${TMPDIR:-/tmp}/aria-r22-denies-$4" 2>/dev/null
  printf '{"file_path":"%s","transcript_path":"%s","tool_use_id":"%s","session_id":"%s"}' "$1" "$2" "$3" "$4" \
    | KT_CONFIG="${5:-/nonexistent}" sh "$PRE"
}
pp_run_post() { printf '{"file_path":"%s"}' "$1" | KT_CONFIG="${2:-/nonexistent}" sh "$POST"; }
# 1 if stdout contains needle, else 0
pp_has() { case "$2" in *"$1"*) echo 1 ;; *) echo 0 ;; esac; }

# [1] built-in scaffold glob, marker present -> allow (empty stdout)
out=$(pp_run_pre "$SCAFFOLD" "$MARKER_TX" toolu_present_001 pp1)
assert_eq "scaffold + marker -> allow (empty stdout)" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# [2] built-in scaffold glob, marker absent -> deny naming the abbreviated format
out=$(pp_run_pre "$SCAFFOLD" "$NOMARKER_TX" toolu_absent_001 pp2)
assert_eq "scaffold + no marker -> deny" "1" "$(pp_has '"permissionDecision":"deny"' "$out")"
assert_eq "scaffold deny names [Rule 22 · Planning]" "1" "$(pp_has '[Rule 22 · Planning]' "$out")"

# [3] deliverable template, marker absent -> deny naming the FULL format (no over-match)
out=$(pp_run_pre "$DELIVERABLE" "$NOMARKER_TX" toolu_absent_001 pp3)
assert_eq "deliverable deny names full 7-step" "1" "$(pp_has '7-step' "$out")"
assert_eq "deliverable deny is NOT abbreviated" "0" "$(pp_has '[Rule 22 · Planning]' "$out")"

# [4] user planning_paths knob, marker absent -> abbreviated format
out=$(pp_run_pre "/tmp/proj/my-scaffolds/thing.md" "$NOMARKER_TX" toolu_absent_001 pp4 "$PP_CFG")
assert_eq "user planning_paths -> abbreviated format" "1" "$(pp_has '[Rule 22 · Planning]' "$out")"

# [5] critical_paths still escalates (protect beats planning) -> full
out=$(pp_run_pre "/tmp/proj/secret-stuff/x.md" "$NOMARKER_TX" toolu_absent_001 pp5 "$PP_CFG")
assert_eq "critical_paths -> full format" "1" "$(pp_has '7-step' "$out")"
assert_eq "critical_paths NOT downgraded" "0" "$(pp_has '[Rule 22 · Planning]' "$out")"

# [6] post-hook: scaffold -> planning advisory; deliverable -> full scope check
assert_eq "post-hook scaffold -> PLANNING PATH" "1" "$(pp_has 'PLANNING PATH' "$(pp_run_post "$SCAFFOLD")")"
assert_eq "post-hook deliverable -> full scope check" "1" "$(pp_has 'POST-EDIT SCOPE CHECK' "$(pp_run_post "$DELIVERABLE")")"
