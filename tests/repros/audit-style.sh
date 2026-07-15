#!/bin/sh
# audit-style.sh — /audit style SKILL.md documents: the 5-step pipeline, the receipts gate
# (>=2 distinct sessions + dated verbatim quotes, fail-closed), all 3 layers, source-rejection
# of aria's own artifacts, the over-cap prompt, write-confinement, preview-first, and the
# Rule 36 mutation guard. Dogfood ceiling — asserts the DOCUMENTED contract.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SK="$REPO_ROOT/plugin-claude-code/skills/audit-style/SKILL.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
[ -f "$SK" ] || { bad "exists" "no audit-style/SKILL.md"; printf "\n0 passed, 1 failed\n"; exit 1; }
# A: receipts gate — the load-bearing contract
grep -qiE '2 (distinct|different) session|>= ?2 session|two distinct session' "$SK" && ok "gate: >=2 sessions" || bad "gate sessions" "no >=2-session rule"
grep -qiE 'verbatim' "$SK" && ok "gate: verbatim quotes" || bad "gate verbatim" "no verbatim requirement"
grep -qiE 'dropped, not|fail.?closed|discard' "$SK" && ok "gate: fail-closed" || bad "gate fail-closed" "no drop-not-soften rule"
# B: all three layers named
for L in "definition of done" "rejection" "debug" "design" "writing" "voice"; do
  grep -qiF "$L" "$SK" && ok "layer cue: $L" || bad "layer $L" "layer not covered"
done
# C: source rejection (no feedback loop)
grep -qiE 'reject.*(command|artifact)|never.*(CLAUDE|MEMORY|feedback_)|not.*evidence' "$SK" && ok "source-rejection documented" || bad "source-reject" "aria-artifact rejection missing"
grep -qF "extract-user-prose.py" "$SK" && ok "cites reference filter" || bad "filter cite" "does not cite extract-user-prose.py"
# D: safety — write confinement + no direct feedback write
grep -qF "rules-backlog.md" "$SK" && ok "writes rules-backlog" || bad "write target" "no rules-backlog target"
grep -qiE 'never.*write.*feedback_|not.*feedback_\*|human-gated' "$SK" && ok "no direct feedback write" || bad "no-feedback-write" "confinement not stated"
# E: over-cap prompt (recent/all/window/cancel)
for opt in recent all window cancel; do
  grep -qiF "$opt" "$SK" && ok "over-cap opt: $opt" || bad "over-cap $opt" "option not documented"
done
# F: report-is-the-preview (merged into disposition — no separate preview-y gate)
grep -qiE 'report IS the preview|nothing (is|has been) written' "$SK" && ok "F report-is-preview documented" || bad "F preview" "report-as-preview not stated"
# G: opt-in / never cadence-fired
grep -qiE 'opt-in|never.*(cadence|SessionStart)|explicit' "$SK" && ok "opt-in documented" || bad "opt-in" "not stated"
# H: Rule 36 mutation marker — the gate is documented such that its removal is detectable
grep -qiE 'Rule 36|fail for the right reason|removing the .*(gate|guard)' "$SK" && ok "Rule 36 guard referenced" || bad "rule36" "no fail-for-right-reason note"
# I: Step 5 is a FIXED-STRUCTURE report (not a collapsible one-liner)
grep -qiE 'fixed-structure|emit every subsection|emit-all' "$SK" && ok "I fixed-structure emit-all directive present" || bad "I emit-all" "no anti-collapse directive in Step 5"
# I2: the three distinguishable zero-states are documented (schema-drift != no-signal != thin-window)
grep -qiE 'three (distinguishable )?zero-state|distinguishable zero-state' "$SK" && ok "I zero-states named" || bad "I zero-states" "three zero-states not documented"
grep -qiE 'schema-drift.*NOT.*no signal|NOT .no signal.|extractor broke' "$SK" && ok "I schema-drift != no-signal distinguished" || bad "I drift" "drift-vs-no-signal not distinguished"
# I3: report surfaces passing candidates WITH receipts
grep -qiE 'Passed the receipts gate|distinct sessions ·|distinct sessions\]' "$SK" && ok "I passing candidates + receipts in report" || bad "I passed" "report doesn't render passing candidates+receipts"
# I4: EVERY rule stated individually — dropped rules get rule+reason, NOT just counts
grep -qiE 'each rule \+ why|state the RULE and its REASON|dropped: <specific reason' "$SK" && ok "I4 dropped rules stated individually w/ reason" || bad "I4 drops" "dropped set collapsed to counts, not per-rule+reason"

# J: "Your Working Style" card
grep -qiE 'Your Working Style' "$SK" && ok "J working-style section present" || bad "J section" "no Your Working Style section"
grep -qiE 'Reasoning Type' "$SK" && ok "J Reasoning Type (not archetype)" || bad "J reasoning-type" "archetype not relabeled Reasoning Type"
# J2: ARIA-unique elements — corroboration-vs-memory, blind spots (incl. user-unaware), decision-discipline
grep -qiE 'CONFIRMS.*feedback_|corroboration vs' "$SK" && ok "J2 corroboration-vs-memory (ARIA-unique)" || bad "J2 corrob" "no confirms-vs-new-memory element"
grep -qiE 'blind spot' "$SK" && ok "J2 blind spots" || bad "J2 blind" "no blind-spots element"
grep -qiE 'may not be aware|absence is itself a signal|not be aware of' "$SK" && ok "J2 user-unaware blind spots" || bad "J2 unaware" "no user-unaware blind-spot inference"
grep -qiE 'decision-discipline fingerprint|from the user.?s? artifacts|ADR' "$SK" && ok "J2 decision-discipline fingerprint" || bad "J2 fingerprint" "no artifact-derived discipline element"
# J3: coverage stats are LABELED (fixes ditto's bare-token wart)
grep -qiE 'LABELED with what it means|only your typed prose|never emit a raw token' "$SK" && ok "J3 labeled stats" || bad "J3 stats" "stats not required to be labeled"
# J4: card is a strict SUBSET — #11 contradictions + #14 project-weighting in-session only, no letter grade
grep -qiE 'strict subset|NOT.*(written into|go into).*card|in-session.only' "$SK" && ok "J4 card strict-subset of report" || bad "J4 subset" "card-vs-report subset not stated"
grep -qiE 'NO letter grade|#16 excluded|no letter grade' "$SK" && ok "J4 no letter grade" || bad "J4 grade" "letter grade not excluded"
# J5: shareable card written to references/working-style/
grep -qiE 'references/working-style' "$SK" && ok "J5 card written to references/working-style" || bad "J5 cardfile" "card write location not specified"

# K: merged disposition gate — keep(default, no feedback write) / promote / specify / cancel
for d in keep promote specify cancel; do
  grep -qiF "$d" "$SK" && ok "K disposition: $d" || bad "K $d" "disposition option not documented"
done
grep -qiE 'default.*never writes .?feedback_|keep.*default|Enter.*keep' "$SK" && ok "K keep-is-default, no feedback write" || bad "K default" "default disposition not keep/no-feedback-write"

# L: efficiency mechanisms (live-validated this session)
grep -qiE 'agent-.*prefix|Skip subagent sessions|subagent worker transcript' "$SK" && ok "L subagent-skip pre-filter documented" || bad "L skip" "no agent-* subagent skip"
grep -qiE 'prior external mine|Reuse a prior.*mine|reused .*prior-mined|delta' "$SK" && ok "L prior-mine reuse + delta documented" || bad "L reuse" "no prior-mine reuse / delta-only mining"
grep -qiE 'BEFORE the count in Step 1b|runs BEFORE' "$SK" && ok "L skip runs before over-cap count" || bad "L order" "skip-before-count ordering not stated"
printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
