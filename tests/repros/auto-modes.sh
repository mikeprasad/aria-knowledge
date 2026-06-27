#!/bin/sh
# auto-modes.sh — asserts /auto SKILL.md documents the 3 modes + no-keyword default, drives
# the arc by COMPOSING the real skills (not re-encoding Rule 35), states an up-front arc
# contract, and is a pure explicit override (never writes config; /setup owns that). Dispatch is Claude-executed prose;
# this checks the documented contract, not runtime.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SK="$REPO_ROOT/plugin-claude-code/skills/auto/SKILL.md"
WR="$REPO_ROOT/plugin-claude-code/template/rules/working-rules.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

[ -f "$SK" ] && ok "A auto SKILL.md exists" || bad "A exists" "no auto/SKILL.md"

# B: both modes + the no-keyword default documented (Option A: no `set` mode)
for m in "arc" "execute"; do
  grep -qiF "$m" "$SK" && ok "B mode documented: $m" || bad "B mode $m" "not in SKILL.md"
done
grep -qiE 'no-keyword default|default when the first arg|default `arc`' "$SK" \
  && ok "B no-keyword default documented" || bad "B default" "no bare-/auto default rule"
grep -qiE 'Two modes' "$SK" && ok "B two-mode surface (no set mode)" || bad "B two-mode" "still advertises >2 modes"

# C: composes the real process skills via the Skill tool (driver, not summary)
for skill in "brainstorming" "/prospect" "test-driven-development" "/retrospect"; do
  grep -qiF "$skill" "$SK" && ok "C composes: $skill" || bad "C compose $skill" "not referenced"
done
grep -qiE 'invoking the real skills|Skill. tool, not by summarizing|composition' "$SK" \
  && ok "C compose-not-summarize stated" || bad "C compose-principle" "doesn't say invoke real skills"

# D: does NOT re-encode the decision policy — defers to Rule 35 as the single source
grep -qiE 'Rule 35' "$SK" && ok "D defers to Rule 35" || bad "D Rule 35" "no reference to the policy source"
grep -qiE 'single source of truth|belongs in Rule 35, not in this skill|does NOT re-define' "$SK" \
  && ok "D single-source-of-truth guard" || bad "D SSOT" "no don't-duplicate-the-policy guard"
# Rule 35 must actually exist for the deferral to be valid
grep -qiE '^### 35\.|Rule 35' "$WR" && ok "D Rule 35 exists in working-rules" || bad "D Rule 35 real" "Rule 35 missing from working-rules.md"

# E: states an up-front arc contract (decide-myself vs stop-and-ask, legible before driving)
grep -qiE 'arc contract|contract before driving|I.ll decide myself|I.ll stop and ask' "$SK" \
  && ok "E up-front arc contract" || bad "E contract" "no legible decide-vs-stop contract"

# F: the stop-rule names the ungranted-approval cases (push/deploy/destructive/scope/credentials)
for word in "push" "destructive" "scope change" "credentials"; do
  grep -qiF "$word" "$SK" && ok "F stop-rule covers: $word" || bad "F stop $word" "not in stop-rule"
done

# G: Option A — /auto NEVER writes config; the standing posture is /setup's job (one writer)
grep -qiE 'never write|only via .?/setup|/setup.s job|owned by .?/setup|/setup.*exclusiv' "$SK" \
  && ok "G config-write is /setup-only (auto never writes)" || bad "G config-write" "doesn't state /auto never writes / /setup owns the key"
grep -qiE 'override.* the standing|overrides the standing|explicit.* grant|invocation is the grant' "$SK" \
  && ok "G explicit-override semantics" || bad "G override" "explicit-override-of-config not documented"

# H: gates run but don't count as stopping (prospect/retrospect are checks, not stops)
grep -qiE 'not count as stopping|not stops|checks, not stops|don.t count as stopping' "$SK" \
  && ok "H gates-are-checks-not-stops" || bad "H gates" "doesn't distinguish gates from stops"

# I: ADR-094 Runtime Gate present (5-port discipline) + canonical-owner framing
grep -qiF 'ADR-094' "$SK" && ok "I ADR-094 runtime gate" || bad "I ADR-094" "no runtime gate"
grep -qiF 'aria-cowork:auto' "$SK" && ok "I namespaced cowork variant named" || bad "I cowork" "no namespaced variant"

# J: routes AWAY to the right sibling when /go is the wrong tool (anti-overtrigger)
for sib in "/prospect" "/retrospect" "/handoff" "/wrapup"; do
  grep -qF "$sib" "$SK" && ok "J routes-to sibling: $sib" || bad "J route $sib" "not in When-NOT-to-use"
done

# K: bare "go" is context-gated, not a standalone trigger (over-trigger guard)
grep -qiE 'bare .?go.? (alone )?is ambiguous|context is clearly|not when it.s conversational' "$SK" \
  && ok "K bare-go is context-gated" || bad "K bare-go" "bare go not disambiguated from conversational go"

# L: degrades gracefully when a composed skill / MCP is absent (no opaque failure)
grep -qiE 'Degrade gracefully|degraded form|isn.t installed|unavailable' "$SK" \
  && ok "L graceful degradation documented" || bad "L degrade" "no fallback when a composed skill/tool is absent"

# --- absorbed operational mandate (from AUTONOMOUS-SESSION-TEMPLATE.md) ---

# M: On-queue-complete toggle (continue|stop), default stop
grep -qiE 'continue\|stop|On-queue-complete|On-complete' "$SK" && ok "M queue-complete toggle present" || bad "M toggle" "no continue|stop toggle"
grep -qiE 'default.*stop|stop.*default|Default to this if unset|Default to STOP' "$SK" \
  && ok "M toggle defaults to stop" || bad "M default-stop" "toggle default not stated"

# N: pre-answered never-stop list (the autonomous-run friction class)
for item in "nowledge placement" "permission" "backlog" "Linear" "commit cadence"; do
  grep -qiF "$item" "$SK" && ok "N pre-answered: $item" || bad "N pre-answered $item" "not in never-stop list"
done

# O: verify-before-trust is present as the #1 discipline
grep -qiE 'Verify before you trust|verify.* empirically|VERIFY STATE FIRST|may be stale' "$SK" \
  && ok "O verify-before-trust" || bad "O verify-first" "no empirical-verify-first discipline"

# P: budget-binding — usage vs context decides cron vs handoff
grep -qiE 'which budget binds|usage.*context|context-bound|usage-bound' "$SK" \
  && ok "P budget-binding (usage vs context)" || bad "P budget" "no budget-binding discipline"
grep -qiE 'at 90%' "$SK" && ok "P context-90%-extract" || bad "P 90%" "no 90% context trigger"

# Q: work-selection order + never-invent-a-feature
grep -qiE 'SESSION.md|Next session prompt|existing queue|work.* the .*queue' "$SK" \
  && ok "Q work-selection order" || bad "Q work-select" "no queue-order work selection"
grep -qiE 'never invent a feature|Never invent a feature|do NOT pick up new work' "$SK" \
  && ok "Q never-invent guard" || bad "Q never-invent" "no never-invent-a-feature guard"

# R: subagent NEED-IT gate (budgeted, not reflexive) + Workflow over-cap
grep -qiE 'NEED-IT|inline.* baseline|budgeted.* escalation|do the work .*inline' "$SK" \
  && ok "R subagent need-it gate" || bad "R subagent" "no subagent budgeting discipline"
grep -qiF 'Workflow' "$SK" && ok "R Workflow over-cap noted" || bad "R workflow" "Workflow not flagged as over-cap"

# W: three orthogonal fan-out stopgaps (count-burst / spend-burst / count-over-time)
grep -qiE 'opt-in only|hard OFF by default' "$SK" && ok "W1 Workflow opt-in hard-off" || bad "W1 workflow-optin" "Workflow not hard-off-by-default"
grep -qiE 'Budget-fraction pre-flight|% of the remaining usage|fanout=' "$SK" && ok "W2 budget-fraction gate" || bad "W2 budget-frac" "no pre-flight budget-fraction gate"
grep -qiE 'Cumulative per-arc|count of total subagents|after .*total|agents=<?N' "$SK" && ok "W3 cumulative per-arc cap" || bad "W3 cumulative" "no cumulative per-arc subagent cap"
grep -qiE 'per-spawn quality check.* NOT a cumulative|NOT a cumulative budget ceiling' "$SK" \
  && ok "W need-it-is-not-a-cap clarified" || bad "W need-it-clarify" "doesn't state NEED-IT != aggregate cap"
grep -qiE 'orthogonal' "$SK" && ok "W stopgaps-are-orthogonal" || bad "W orthogonal" "doesn't state the three cover distinct axes"

# X: no phantom config key — thresholds are invocation-scoped defaults, not a claimed config key
grep -qiF 'auto_fanout_budget_fraction' "$SK" && bad "X no-phantom-key" "references a config key that config.sh does not parse" || ok "X no phantom config key"
grep -qiE 'no standing config key|invocation-scoped|built-in default' "$SK" \
  && ok "X thresholds framed as invocation defaults" || bad "X invocation-scoped" "thresholds not framed as invocation-scoped"

# S: optional resume-cron, gated on usage-bound + arm early
grep -qiE 'CronCreate|resume cron|self-perpetuat' "$SK" \
  && ok "S resume-cron path" || bad "S cron" "no resume-cron mechanism"

# Y: config/preflight guided walkthrough mode (per-run, never persists)
grep -qiE '/auto config|`config`|preflight' "$SK" && ok "Y config mode present" || bad "Y config" "no config/preflight mode"
grep -qiE 'one at a time|one-knob-at-a-time|one knob' "$SK" && ok "Y one-at-a-time picker" || bad "Y picker" "walkthrough not one-at-a-time"
grep -qiE 'recognition-not-recall|remember nothing|set nothing from memory|never have to .*recall' "$SK" \
  && ok "Y recall-burden-on-skill" || bad "Y recall" "doesn't state the no-memory principle"
grep -qiE 'never persists|configures THIS (run|arc) only|Nothing persists|per-run only' "$SK" \
  && ok "Y config is per-run (no persist)" || bad "Y persist" "config-mode persistence not bounded"

# Z: resume-cron fires +5 min AFTER reset (not at the boundary) — chain-break guard
grep -qiE '5 minutes AFTER|\+5.?min|after the (next )?5-hour reset' "$SK" \
  && ok "Z cron +5min-after-reset guard" || bad "Z cron-timing" "cron not guarded past the exact reset boundary"

# T: commit gate on the bare test exit code (no && commit after non-test cmd)
grep -qiE 'bare exit code|bare.*exit|never chain .&& commit|atomic commit' "$SK" \
  && ok "T commit-gate discipline" || bad "T commit-gate" "no bare-exit-code commit gate"

# U: never force-push + verify ahead-count→0 (git safety)
grep -qiE 'never force-push|force-push' "$SK" && ok "U never-force-push" || bad "U force-push" "no force-push guard"
grep -qiE 'ahead-count|ahead.count.*0' "$SK" && ok "U verify ahead-0" || bad "U ahead-0" "no post-push ahead-count verify"

# V: verification reality — real verify path + honest GUI-gated classification (don't fake/skip)
grep -qiE 'Verification reality|real working verification|device-?/?GUI-gated|documented residual' "$SK" \
  && ok "V verification-reality" || bad "V verify-reality" "no real-verify-path / honest-classification discipline"
grep -qiE 'never fake or silently skip|classify it, never fake|model == backend' "$SK" \
  && ok "V honest-classify (no fake/skip)" || bad "V honest" "no don't-fake-or-skip clause"

# SR: context-window self-restart (Piece A) — gated on continue + the self-restart flag,
# writes a restart-signal file for the external bin/auto-runloop.sh wrapper, never self-/clear.
grep -qiE 'self-restart' "$SK" && ok "SR self-restart flag documented" || bad "SR flag" "no self-restart flag in the arg grammar"
grep -qiE 'restart-signal|auto-restart-requested|signal file' "$SK" \
  && ok "SR restart-signal file" || bad "SR signal" "no restart-signal-file write documented"
grep -qiE 'auto-runloop' "$SK" && ok "SR names the external wrapper" || bad "SR wrapper" "doesn't point at bin/auto-runloop.sh"
# Gate: BOTH continue-mode AND the explicit flag (never auto-clears an attended/default run)
grep -qiE 'continue.*(and|\+|&).*self-restart|self-restart.*(and|requires|only).*continue|both .*continue.* and .*self-restart' "$SK" \
  && ok "SR gated on continue AND the flag" || bad "SR gate" "gate (continue AND self-restart) not stated"
# The skill itself must NOT claim to /clear — it writes the signal and stops; the wrapper restarts
grep -qiE 'cannot .*/clear|can.t (issue|self-issue) .*/clear|never .*/clear|does not .*/clear' "$SK" \
  && ok "SR skill-never-clears invariant" || bad "SR no-clear" "doesn't state the skill can't/won't /clear"
# Must still be prose-first (the opener the wrapper relaunches with)
grep -qiE 'prose-first|start with prose|never (a |with a )?(leading )?slash' "$SK" \
  && ok "SR prose-first opener" || bad "SR prose" "prose-first opener requirement absent"
# Honesty: the wrapper trips the auto-mode classifier → user must allowlist to run unattended
grep -qiE 'allowlist|permission rule|classifier|dangerously-skip-permissions' "$SK" \
  && ok "SR documents the permission gate" || bad "SR perms" "doesn't warn the wrapper needs a permission allowlist"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
