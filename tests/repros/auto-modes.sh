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
grep -qiE 'default whenever a goal is given|no mode keyword and no goal|bare. `/auto`' "$SK" \
  && ok "B bare-/auto behaviour documented" || bad "B default" "no bare-/auto rule"
grep -qiE '`set` mode|\bset mode\b' "$SK" && bad "B no set mode" "a 'set' mode reappeared (Option A rejected it)" || ok "B no set mode (Option A held)"

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

# I: ADR-094 acknowledged (5-port discipline) + this skill's scope within it.
grep -qiF 'ADR-094' "$SK" && ok "I ADR-094 runtime gate" || bad "I ADR-094" "no runtime gate"
# The second leg previously asserted the skill NAMES a namespaced `/auto` Cowork variant. That
# variant exists in no port — verified in plugin-claude-cowork/skills with a positive control —
# so the assertion certified a broken redirect as correct for as long as it stood. It came from
# the ADR-094 colliding-name template, not from a measurement. Replaced, not deleted: the true
# fact is that this skill is Code-only and therefore outside the collision set. Directly
# contradicts nothing else in this suite; FG1 asserts the dead token's absence.
grep -qiF 'ships in the Claude Code port only' "$SK" \
  && ok "I declared Code-only (outside the collision set)" || bad "I code-only" "Code-only scope not declared"

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

# Y: config guided walkthrough mode (per-run, never persists)
# The old pattern carried a `|preflight` alternative from when that was an alias. v2.44.1
# retired the alias AND added ~10 references to the /preflight SKILL, so that alternative
# now matches unconditionally -- the assertion could not fail. Dropped.
grep -qiE '/auto config|`config`' "$SK" && ok "Y config mode present" || bad "Y config" "no config mode"

# Y2: `preflight` is retired as a mode keyword and must NOT be reachable as one. Retired,
# not deleted: the parser has to recognise the word and redirect, because falling through
# to `mode = arc` turns `/auto full preflight` into an arc building something called
# "preflight". Mirrors the MM group's treatment of `loop`.
grep -qiE 'alias `/auto preflight`|\(or `/auto preflight`\)' "$SK" \
  && bad "Y2 alias gone" "the config alias /auto preflight reappeared" || ok "Y2 config alias retired"
grep -qiE 'matches `arc`, `execute`, `plan`, or `config`' "$SK" \
  && ok "Y2 preflight not a mode keyword" || bad "Y2 keyword" "preflight still parsed as a mode"
grep -qiE 'RETIRED mode keyword and must never fall through' "$SK" \
  && ok "Y2 retired word cannot become a goal" || bad "Y2 fallthrough" "no rule stopping preflight becoming a goal"
grep -qiE 'no `preflight` mode' "$SK" \
  && ok "Y2 tombstone documents the retirement" || bad "Y2 tombstone" "no tombstone for the preflight mode"
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

# SD: standing directives block exists with all seven directives
grep -qF '## Standing Directives' "$SK" \
  && ok "SD block present" || bad "SD block" "no '## Standing Directives' heading"
for d in D1 D2 D3 D4 D5 D6 D7; do
  grep -qF "**$d" "$SK" && ok "SD directive: $d" || bad "SD $d" "not in SKILL.md"
done

# SD-D1: 5h binds, 7d ignored, two distinct thresholds
grep -qiE '7[- ]day.*ignor|ignor.*7[- ]day' "$SK" \
  && ok "SD D1 ignores 7-day" || bad "SD D1 7d" "7-day not explicitly ignored"
grep -qF '90%' "$SK" && ok "SD D1 90% arm threshold" || bad "SD D1 90" "no 90% threshold"
grep -qF '95%' "$SK" && ok "SD D1 95% pause threshold" || bad "SD D1 95" "no 95% pause"
grep -qiE 'no statusline|not visible|desktop' "$SK" \
  && ok "SD D1 no-statusline caveat" || bad "SD D1 caveat" "no ask-when-invisible rule"

# SD-D7: judgment ledger contract
grep -qiF 'judgment ledger' "$SK" \
  && ok "SD D7 ledger named" || bad "SD D7 name" "ledger not named"
grep -qF 'logs/auto/' "$SK" \
  && ok "SD D7 ledger path" || bad "SD D7 path" "no logs/auto/ path"
grep -qF 'knowledge_folder' "$SK" \
  && ok "SD D7 resolves knowledge_folder" || bad "SD D7 resolve" "path not config-resolved"
grep -qF '~/knowledge/' "$SK" \
  && bad "SD D7 phantom path" "literal ~/knowledge/ present (v2.40.2 defect)" \
  || ok "SD D7 no phantom path"
for t in "Validated" "Deterministic" "Traced" "Confirmed after"; do
  grep -qF "$t" "$SK" && ok "SD D7 test: $t" || bad "SD D7 $t" "four-part test incomplete"
done
grep -qiE '0 judgment calls|empty ledger' "$SK" \
  && ok "SD D7 empty-ledger stated" || bad "SD D7 empty" "empty ledger not stated"

# SD: arc contract surfaces the retyped clauses
grep -qiE 'Judgment ledger:' "$SK" \
  && ok "SD contract shows ledger" || bad "SD contract ledger" "not in arc contract"
grep -qiE 'never pre-authorized|never grantable' "$SK" \
  && ok "SD contract push-never-granted" || bad "SD contract push" "push grant not excluded"

# MM: plan mode + arc as an explicit keyword
grep -qiE '\| *\*\*plan\*\* *\|' "$SK" \
  && ok "MM plan mode row" || bad "MM plan" "no plan mode row in the table"
grep -qiE 'stop at a prospected|No code\.' "$SK" \
  && ok "MM plan stops before code" || bad "MM plan stop" "plan mode doesn't forbid code"
grep -qiE 'matches `arc`|`arc`, `execute`' "$SK" \
  && ok "MM arc is a mode keyword" || bad "MM arc" "arc not parseable as a mode"

# MM: the three modifiers, stackable
for m in full tickets; do
  grep -qF "**\`$m\`**" "$SK" && ok "MM modifier: $m" || bad "MM $m" "modifier not documented"
done
grep -qiE 'stackable|they stack' "$SK" && ok "MM modifiers stack" || bad "MM stack" "stacking not stated"

# MM: full grants everything EXCEPT push
grep -qiE 'except push|except the one that leaves' "$SK" \
  && ok "MM full excludes push" || bad "MM full push" "full's push carve-out missing"
grep -qiE 'does not remove them|raised, finite' "$SK" \
  && ok "MM full keeps stopgaps finite" || bad "MM full stopgaps" "stopgaps not preserved"

# MM: `loop` stays retired. It reduced to a strict alias for `unattended continue` once
# resume-arming moved to the presence axis, and it had already drifted (claiming arming that
# `full` also claimed) and was the worst mid-prose collision. The tombstone must survive so
# it is not reintroduced by someone reading only the modifier list.
grep -qiE 'no .loop. modifier|deliberately no .loop.' "$SK" \
  && ok "MM loop retirement is recorded" || bad "MM loop tombstone" "retirement rationale missing"
if grep -qE '^- \*\*`loop`\*\*' "$SK"; then
  bad "MM loop reintroduced" "a loop modifier is defined again"
else
  ok "MM no loop modifier defined"
fi

# VL: no vendor LOCK — naming a vendor inside an example list is fine (that is what
# /digest does and it helps the probe); treating one vendor as THE tracker is not.
if grep -qiE 'linear (mcp|id|ticket)|linear-id|<linear' "$SK"; then
  bad "VL no vendor lock" "a vendor is still treated as THE tracker"
else
  ok "VL no vendor lock (vendor-as-the-tracker absent)"
fi
# ...and if a vendor is named, it must sit in a list with other trackers.
if grep -qi 'linear' "$SK"; then
  grep -qiE 'linear.*(asana|jira|atlassian|monday|clickup|notion|github issues)' "$SK" \
    && ok "VL vendor named only as one example among several" \
    || bad "VL example list" "a vendor is named without sibling trackers beside it"
else
  ok "VL no vendor named at all"
fi
grep -qF 'ticket-id' "$SK" && ok "VL generic ticket-id" || bad "VL ticket-id" "not genericized"
grep -qiE 'project.tracker' "$SK" \
  && ok "VL tracker category probed" || bad "VL probe" "no tracker category probe"
grep -qiE 'ticketing_plugins' "$SK" \
  && ok "VL honors ticketing_plugins" || bad "VL config" "config key not honored"
grep -qiE 'never verify|not verify' "$SK" \
  && ok "VL inherits no-installed-probe rule" || bad "VL probe rule" "installability rule missing"
grep -qF 'A-Z]{2,}-' "$SK" \
  && ok "VL reuses the agnostic ticket regex" || bad "VL regex" "ticket-ID regex absent"

# VL: Gate B — /auto's own description must not have grown
AUTO_DESC=$(awk '/^description:/{f=1;print;next} f&&/^[a-z_-]+:/{f=0} f' "$SK" | wc -c | tr -d ' ')
[ "$AUTO_DESC" -le 1232 ] \
  && ok "VL description within budget ($AUTO_DESC B <= 1232)" \
  || bad "VL budget" "description grew to $AUTO_DESC B (was 1232)"

# SCH: durable:true is a documented no-op and must not be instructed
# durable:true may appear ONLY inside a prohibition — a mention is not an instruction.
if grep -E 'durable: ?true' "$SK" | grep -qvE 'Do not pass|never pass|no effect'; then
  bad "SCH durable no-op" "durable:true is instructed somewhere without a negation"
else
  ok "SCH durable:true appears only as a prohibition"
fi
grep -qiE 'session-only' "$SK" \
  && ok "SCH session-only stated" || bad "SCH session-only" "CronCreate reality not stated"

# SCH: availability-gated, with CronCreate retained as the always-available default
grep -qiE 'CronCreate.*(is the|stays the) (baseline|default)|baseline and the default' "$SK" \
  && ok "SCH CronCreate is the default" || bad "SCH default" "CronCreate not stated as baseline"
grep -qiE 'every runtime' "$SK" \
  && ok "SCH availability is the gate" || bad "SCH availability" "no availability-first rule"
grep -qiE 'desktop' "$SK" \
  && ok "SCH names the desktop-only constraint" || bad "SCH desktop" "scheduled-task surface not scoped to desktop"
grep -qiE 'launchd' "$SK" \
  && ok "SCH names the CLI durable option" || bad "SCH launchd" "no CLI-side durable mechanism"
grep -qiE 'probe' "$SK" \
  && ok "SCH probes before naming a mechanism" || bad "SCH probe" "no runtime probe rule"
grep -qiE 'never promise durability|cannot deliver' "$SK" \
  && ok "SCH no over-promise" || bad "SCH over-promise" "missing the don't-promise guard"

# CD: bare /auto falls through to the config picker. Modifiers and toggles say HOW, never
# WHAT — so an invocation carrying only those has not named a goal, and guessing one from
# SESSION.md is exactly the stale-resume hazard "verify before you trust" warns about.
grep -qiE 'no mode keyword and no goal|neither a mode nor a goal|falls through to .?config' "$SK" \
  && ok "CD bare /auto defaults to config" || bad "CD default" "no config-default rule"
grep -qiE 'modifiers and toggles.*do not count|do not count as a goal' "$SK" \
  && ok "CD modifiers/toggles are not goal context" || bad "CD tokens" "does not exclude modifiers/toggles"
grep -qiE 'pre-seed' "$SK" \
  && ok "CD picker pre-seeded with what was typed" || bad "CD preseed" "picker discards the typed modifiers"

# MP: modifiers are recognised only at the ENDS, never mid-prose. Without this,
# "/auto fix the render loop bug" silently becomes an unattended self-restarting run.
grep -qiE 'contiguous run|only at the (start|ends)|never mid-prose|once goal prose begins' "$SK" \
  && ok "MP modifier scan is edge-bounded" || bad "MP scan" "modifiers still matched anywhere in args"
grep -qiF 'render loop' "$SK" \
  && ok "MP the collision case is documented" || bad "MP example" "no worked mid-prose example"

# AT: presence is a TWO-VALUED axis, always stated, never silently inferred.
grep -qF 'attended` / `unattended' "$SK" \
  && ok "AT presence is two-valued" || bad "AT values" "presence not a two-valued axis"
grep -qiE 'surfaced\s+\*\*immediately\*\*|surfaced immediately' "$SK" \
  && ok "AT attended surfaces non-blocking residuals live" || bad "AT live" "does not change non-blocking handling"
grep -qiE 'presence' "$SK" && ok "AT presence named as an axis" || bad "AT axis" "presence axis not named"
grep -qiE 'always states which is in force|Always stated; never inferred' "$SK" \
  && ok "AT contract always states presence" || bad "AT contract" "presence not always surfaced"
grep -qiE 'knob 7|^7\. \*\*Presence\*\*' "$SK" \
  && ok "AT config asks presence when unspecified" || bad "AT knob" "not a config knob"

# WALL: the usage wall and the context wall need different mechanisms — never conflated.
grep -qiE 'cannot rescue a context wall|re-enters the same full session' "$SK" \
  && ok "WALL usage vs context distinguished" || bad "WALL" "the two walls are conflated"
# Matcher deliberately SHORT: grep is line-based, and a phrase longer than the prose's wrap
# width fails on correct text. Third occurrence of that trap in this suite — keep patterns
# inside one line's worth of words.
grep -qiE 'is inert unless' "$SK" \
  && ok "WALL self-restart wrapper caveat stated" || bad "WALL wrapper" "implies the run is self-healing"
grep -qiE 'Arming a resume is NOT an authority grant' "$SK" \
  && ok "WALL arming is not an authority grant" || bad "WALL arming" "full still claims resume arming"

# ARM: resume-arming keys on UNFINISHED WORK, not on presence and not on `continue`.
#
# These three surfaces disagreed in v2.43.0, and the disagreement was silent: D1 said "at 90%
# arm the resume" unconditionally, Step 6 said "only for an unattended run", and config knob 6
# said "only meaningful when #2 = continue". Under `/auto full attended <goal>` that resolves
# to NOT arming -- so a scoped attended run hitting the 95% pause mid-goal simply stopped,
# goal unfinished, nothing scheduled to resume it.
#
# The gate was on the wrong axis. `continue` means "find NEW work after the queue clears"; it
# says nothing about FINISHING the goal already given. Arming is about unfinished work at the
# usage wall. Presence governs only whether the resume announces itself.
# Matcher is a distinctive PHRASE, not the bare stem: "unfinished" already appears ~200 lines
# away in "unfinished investigation", so a stem match would pass on unrelated prose.
grep -qiE 'work remains unfinished' "$SK" \
  && ok "ARM keys on unfinished work" || bad "ARM key" "arming still gated on presence/continue"
if grep -qiE 'Only for an unattended, away-from-keyboard run' "$SK"; then
  bad "ARM step6 gate" "Step 6 still restricts arming to unattended runs"
else
  ok "ARM Step 6 not restricted to unattended"
fi
if grep -qF 'Only offered/meaningful when #2 = `continue`' "$SK"; then
  bad "ARM knob gate" "config knob still gates arming on continue"
else
  ok "ARM config knob not gated on continue"
fi
grep -qiE 'announces itself|silently, without' "$SK" \
  && ok "ARM presence governs announcement only" || bad "ARM presence" "presence still claims to own arming"
if grep -qiE 'arm[^.]{0,60}(requires|only when)[^.]{0,20}`continue`' "$SK"; then
  bad "ARM contradiction" "a surface still conditions arming on continue"
else
  ok "ARM no surface conditions arming on continue"
fi

# PFG: the preflight commit gate is SATISFIED, never routed around. Under a configured
# deny (gate=deny / deny_repos / deny_paths) an unattended arc that does nothing would
# not stall politely -- it would burn 3 denials and trip the circuit breaker, DEGRADING
# the user's gate for the whole session. So both halves are pinned: run the checklist,
# and never take any of the three shortcuts that would defeat it.
grep -qiE 'run `/preflight`' "$SK" \
  && ok "PFG /auto runs /preflight for a gated commit" || bad "PFG run" "no instruction to run /preflight"
grep -qF 'preflight_deny_repos' "$SK" \
  && ok "PFG knows the repo-scoped deny key" || bad "PFG repos" "preflight_deny_repos not referenced"
grep -qiE 'never write the marker|fake a recorded run' "$SK" \
  && ok "PFG forbids faking the marker" || bad "PFG marker" "marker-faking not forbidden"
grep -qiE 'never flip `preflight_gate` to `off`' "$SK" \
  && ok "PFG forbids disabling the gate" || bad "PFG disable" "gate-disabling not forbidden"
# Anchored on the preflight-specific wording, NOT a bare 'degrade' -- /auto already says
# "Degrade gracefully" about absent Superpowers skills, so the loose pattern matched the
# pre-edit file and could never fail. A guard that cannot go red protects nothing.
grep -qiE 'never let the circuit breaker|three consecutive denials degrade' "$SK" \
  && ok "PFG forbids riding the circuit breaker" || bad "PFG breaker" "breaker abuse not forbidden"
grep -qiE 'FAIL[^.]{0,40}not[^.]{0,20}stop|preflight FAIL is \*\*not\*\* a stop' "$SK" \
  && ok "PFG a FAIL verdict does not stall the arc" || bad "PFG fail" "FAIL-is-not-a-stop missing"
# Anchored on the bullet's own label: a bare 'pre-answered' matches the SECTION HEADING,
# which exists whether or not the gate case was ever added to the list.
grep -qiE 'a preflight-gated commit' "$SK" \
  && ok "PFG gate case is pre-answered, not a fork" || bad "PFG preanswered" "not in the pre-answered set"

# FO: the fan-out axis must be PARSEABLE, not merely described in the Step 5 stopgaps prose.
# Before this group, `workflow` / `fanout=<pct>` / `agents=<N>` appeared in the stopgaps
# paragraph and in NO modifier list, NO argument-hint and NO description — so under the
# documented ENDS scan an unrecognised token ends the modifier run and the rest becomes goal:
# the opt-in silently never registered AND the goal gained a stray word. Failed safe (Workflow
# stayed hard-OFF, tighter defaults held), which is exactly why it survived shipped docs.
grep -qF 'the **fan-out** axis: raise or open the three' "$SK" \
  && ok "FO1 fan-out trio is in the modifier list" || bad "FO1 modifier-list" "fan-out tokens absent from the modifier set"

# Anchored on the argument-hint LINE, not the file: these tokens now appear in the body too,
# so a file-wide grep would report PASS with the frontmatter still omitting them.
grep '^argument-hint:' "$SK" | grep -q 'workflow' \
  && grep '^argument-hint:' "$SK" | grep -q 'fanout=' \
  && grep '^argument-hint:' "$SK" | grep -q 'agents=' \
  && ok "FO2 argument-hint advertises the fan-out trio" || bad "FO2 argument-hint" "hint omits a fan-out token"

# Same line-anchoring reason. Six axes: authority, presence, duration, work-source,
# context-recovery, fan-out. The description said "one word per axis" and then listed three
# plus two loose extras, so a reader counting axes to check an invocation got the wrong number.
grep '^description:' "$SK" | grep -qi 'six axes' \
  && ok "FO3 description states six axes" || bad "FO3 axis-count" "description undercounts the axes"

# The ENDS rule protects mid-prose only. A bare modifier that lands at the very end of a goal
# IS consumed — true for `tickets`/`continue`/`stop` before this change and now for `workflow`.
# Stated rather than fixed by widening the scan, which is strictly worse.
grep -qF 'a bare modifier at the very END of a goal IS consumed' "$SK" \
  && ok "FO4 trailing-collision exposure is stated" || bad "FO4 trailing" "trailing bare-modifier exposure undocumented"

# Pins ENDS-only for the `=`-bearing tokens against a future "improvement" that widens the
# scan: a general <word>=<value> match would eat a goal like "checks count=20".
grep -qF 'Deliberately NOT recognised anywhere-in-args' "$SK" \
  && ok "FO5 anywhere-scan explicitly rejected" || bad "FO5 anywhere" "no rationale pinning ENDS-only for = tokens"

# FG: the runtime precondition must check a CAPABILITY, not offer a nonexistent variant.
# /auto is Code-only and outside ADR-094's collision set, but its section was copied from the
# colliding-name template and offered to hand off to a Cowork /auto that has never existed in
# any port — a `y` reply would have called the Skill tool on a missing skill. The section now
# checks Bash availability and routes a `stop` to the Cowork gates that DO exist.
#
# NOTE: the skill body deliberately says "no Cowork counterpart" instead of naming the dead
# token, precisely so FG1 can assert the token's absence without matching the skill's own prose.
# If someone reintroduces the literal for readability, FG1 fails by design — rephrase the
# skill, do not weaken this assertion.
if grep -qF 'aria-cowork:auto' "$SK"; then
  bad "FG1 dead-redirect" "names a Cowork /auto variant that exists in no port"
else
  ok "FG1 no redirect to a nonexistent Cowork variant"
fi

grep -qF 'do not restore a redirect to a Cowork variant' "$SK" \
  && ok "FG2 do-not-restore instruction present" || bad "FG2 no-restore" "nothing stops the redirect being re-added"

# The redirect and the Bash check lived in one section; removing the first must not take the
# second with it. This is the assertion that would catch an over-broad deletion.
grep -qiF 'check that the `Bash` tool is available' "$SK" \
  && ok "FG3 Bash capability check survived" || bad "FG3 bash-check" "runtime capability precondition lost"

# Polarity guard. Across the other ADR-094 gates `n` means "run this variant anyway"; phrasing
# this one as "proceed anyway?" would invert `n` for this skill alone.
grep -qF 'declines to run this variant' "$SK" \
  && ok "FG4 y/n polarity matches the other gates" || bad "FG4 polarity" "y/n meaning not pinned against the family"

# The stop branch must route somewhere real. All four exist in plugin-claude-cowork/skills.
# One cause, one assertion: the loop collects the misses and reports them together rather than
# emitting a separate failure per gate, which made a single defect read as five.
FG5_MISSING=""
for g in prospect retrospect handoff wrapup; do
  grep -qF "aria-cowork:$g" "$SK" || FG5_MISSING="$FG5_MISSING /aria-cowork:$g"
done
[ -z "$FG5_MISSING" ] \
  && ok "FG5 stop branch routes to all four real Cowork gates" \
  || bad "FG5 manual-route" "stop branch omits:$FG5_MISSING"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
