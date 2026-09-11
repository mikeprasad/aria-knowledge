#!/bin/sh
# pm-morning-run.sh — the orchestrator must report its REAL outcome, not a fixed "ok".
#
# Why this suite exists: for 94 consecutive days (2026-06-09 -> 2026-09-10) the launchd job
# printed "pm-morning-run OK" and wrote result:"ok" while step 2 never ran, because
# `command -v claude` fails inside launchd and the hardcoded fallback path did not exist. The
# failure was swallowed by `|| true` and the success signals were unconditional. Nothing in the
# repo exercised the orchestrator.
#
# Isolation: a temp HOME, a temp KT_CONFIG, and a temp PATH that deliberately EXCLUDES the real
# `claude` so binary resolution is under test. `osascript` is stubbed so the notification text is
# OBSERVED rather than inferred.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$(cd "$SCRIPT_DIR/../../plugin-claude-code/bin" && pwd)"
. "$SCRIPT_DIR/../pm-helpers.sh"
PM_TMP="$(mktemp -d)"; trap 'rm -rf "$PM_TMP"' EXIT

REAL_JQ="$(command -v jq || true)"
REAL_GIT="$(command -v git || true)"

# ---------------------------------------------------------------------------
# pm_env — build a pristine run environment. Returns via globals: T_HOME, T_KF, T_BIN, T_CONF.
# Each call gets its own numbered sandbox so arms cannot contaminate each other.
# ---------------------------------------------------------------------------
PM_CASE=0
pm_env() {
  PM_CASE=$((PM_CASE+1))
  T_ROOT="$PM_TMP/case$PM_CASE"
  T_HOME="$T_ROOT/home"; T_KF="$T_ROOT/knowledge"; T_BIN="$T_ROOT/bin"
  T_CONF="$T_ROOT/aria-knowledge.local.md"
  mkdir -p "$T_HOME/Projects" "$T_KF/pm-reviews" "$T_BIN" "$T_HOME/.claude/logs"
  # Minimal toolchain WITHOUT claude. /usr/bin + /bin carry sed/grep/date/cat/mkdir/dirname.
  [ -n "$REAL_JQ" ] && ln -sf "$REAL_JQ" "$T_BIN/jq"
  [ -n "$REAL_GIT" ] && ln -sf "$REAL_GIT" "$T_BIN/git"
  # osascript stub: records every notification invocation so AC4 is observable.
  cat > "$T_BIN/osascript" <<'OSA'
#!/bin/sh
printf '%s\n' "$*" >> "$NOTIFY_LOG"
OSA
  chmod +x "$T_BIN/osascript"
  cat > "$T_CONF" <<EOF
---
knowledge_folder: $T_KF
pm_digest_dir: $T_KF/pm-reviews
pm_light_writes: false
pm_notify_desktop: true
pm_notify_imessage: false
projects_list:
---
EOF
  NOTIFY_LOG="$T_ROOT/notify.log"; : > "$NOTIFY_LOG"
  STATUS="$T_KF/pm-reviews/.aria-assist.json"
}

# pm_run [CANDIDATES] — execute the orchestrator in the sandbox. Sets RC to its BARE exit code.
# Nothing follows the command whose exit code is read (trailing-echo-masks-exit-code rule).
#
# ⛔ PM_CLAUDE_CANDIDATES is ALWAYS set, defaulting to a path that cannot exist. Without it the
# production candidate list (absolute /opt/homebrew/bin/claude, /usr/local/bin/claude) ESCAPES the
# temp HOME, so the suite resolves the machine's REAL claude and invokes
# `claude -p "/aria-assist generate"` for real — token-spending and side-effecting from a test.
# It also made AC1 pass for the WRONG REASON: it reported `claude-failed` (the real binary ran and
# failed) where the arm exists to prove `claude-not-resolved`.
pm_run() {
  HOME="$T_HOME" KT_CONFIG="$T_CONF" NOTIFY_LOG="$NOTIFY_LOG" \
    PM_CLAUDE_CANDIDATES="${1:-$T_ROOT/nonexistent/claude}" \
    PATH="$T_BIN:/usr/bin:/bin" sh "$BIN/pm-morning-run.sh" >"$T_ROOT/out.log" 2>&1
  RC=$?
}

# pm_stub_claude BODY — install a fake `claude` on the sandbox PATH.
pm_stub_claude() {
  printf '#!/bin/sh\n%s\n' "$1" > "$T_BIN/claude"; chmod +x "$T_BIN/claude"
}

# pm_status FIELD — read lastRun.<FIELD> from the status overlay ('' when absent).
pm_status() { "$REAL_JQ" -r --arg f "$1" '.lastRun[$f] // ""' "$STATUS" 2>/dev/null || printf ''; }

# ===========================================================================
# AC1 — no resolvable `claude` => result "error", reason names the cause, non-zero exit.
# Expected RED against current code (which swallows and stamps "ok").
# ===========================================================================
pm_env
pm_run
assert_eq "AC1 result is error when claude is unresolvable" "error" "$(pm_status result)"
# ⛔ EXACT, not a glob. A tolerant `*claude*` matcher passed on `claude-failed` — a DIFFERENT
# cause produced by invoking the real binary — so the arm proving resolution-failure detection
# was vacuous (a-loose-pattern-matches-the-subjects-own-output).
assert_eq "AC1 reason is exactly claude-not-resolved" "claude-not-resolved" "$(pm_status reason)"
assert_eq "AC1 exits non-zero" "1" "$([ "$RC" -ne 0 ] && echo 1 || echo 0)"
# HERMETICITY CONTROL — the suite must never resolve a binary outside its own sandbox.
case "$(cat "$T_ROOT/out.log")" in
  *"/opt/homebrew/"*|*"/usr/local/bin/claude"*|*"$HOME/.local/bin/claude"*) ok=1 ;; *) ok=0 ;;
esac
assert_eq "AC1 no machine-real claude path appears in the run log" "0" "$ok"

# ===========================================================================
# AC2 — POSITIVE CONTROL. A stub that writes a digest => "ok", and `digest` is that file's
# ACTUAL name. Expected GREEN even on current code; its job is to catch a deny-all regression
# in which D2 reports "error" for everything and the five RED arms all pass vacuously.
# ===========================================================================
pm_env
pm_stub_claude 'printf "# digest\n" > '"$T_KF"'/pm-reviews/2099-01-02.md'
pm_run
assert_eq "AC2 result is ok on a real success" "ok" "$(pm_status result)"
assert_eq "AC2 digest is the produced file's actual name" "2099-01-02" "$(pm_status digest)"
assert_eq "AC2 exits zero" "0" "$RC"

# ===========================================================================
# AC3 — DECISIVE ARM. Stub exits 0 but writes NO digest => "error" / reason no-digest.
# This is the 94-day case: the exit code was fine, the artifact never appeared.
# ===========================================================================
pm_env
pm_stub_claude 'exit 0'
pm_run
assert_eq "AC3 result is error when no digest was produced" "error" "$(pm_status result)"
assert_eq "AC3 reason is no-digest" "no-digest" "$(pm_status reason)"
assert_eq "AC3 exits non-zero" "1" "$([ "$RC" -ne 0 ] && echo 1 || echo 0)"

# ===========================================================================
# AC3b — REGRESSION GUARD for the falsified premise. The producer names the digest with its
# LOCAL date; a checker computing the UTC date would miss it during the 00:00-09:00 JST window
# and report no-digest on a SUCCESSFUL run. An mtime-based check is basis-free and must accept
# any name. Deliberately uses a name that matches NO plausible date computation.
# ===========================================================================
pm_env
pm_stub_claude 'printf "# digest\n" > '"$T_KF"'/pm-reviews/1970-12-31.md'
pm_run
assert_eq "AC3b a non-UTC-dated digest still counts as success" "ok" "$(pm_status result)"
assert_eq "AC3b digest reports the actual name, not a computed date" "1970-12-31" "$(pm_status digest)"

# ===========================================================================
# AC3d — REASON PRECEDENCE. A stub that EXITS NON-ZERO and writes nothing must report
# `claude-failed`, not `no-digest`. Those are different diagnoses ("the binary broke" vs "the
# binary ran and produced nothing") and the no-digest check must not overwrite the more specific
# one. Guards the `[ -n "$REASON" ] ||` precedence.
# ===========================================================================
pm_env
pm_stub_claude 'exit 3'
pm_run
assert_eq "AC3d a failing binary reports claude-failed, not no-digest" "claude-failed" "$(pm_status reason)"
assert_eq "AC3d result is error" "error" "$(pm_status result)"

# ===========================================================================
# AC3e — THE `-newer` PROPERTY. A digest left behind by a PREVIOUS run must not be mistaken for
# this run's output. Without the marker comparison the check degrades from "did THIS RUN produce a
# digest" to "does a digest exist", which is exactly the distinction D3 exists to make — and the
# 94-day failure would have reported success from 2026-06-09's surviving file.
# The stale file is backdated so it is unambiguously older than the run.
# ===========================================================================
pm_env
printf '# stale digest from a previous run\n' > "$T_KF/pm-reviews/2020-01-01.md"
touch -t 202001010900 "$T_KF/pm-reviews/2020-01-01.md"
pm_stub_claude 'exit 0'
pm_run
assert_eq "AC3e a pre-existing digest does not count as this run's output" "error" "$(pm_status result)"
assert_eq "AC3e reason is still no-digest" "no-digest" "$(pm_status reason)"

# ===========================================================================
# AC3c — DID-IT-RUN CHANNEL. On a FAILED run `at` must still update while `digest` keeps its
# prior value. A fresh `at` + stale `digest` = "ran, produced nothing"; a stale `at` = "never
# fired". Collapsing both to conditional makes those two diagnoses indistinguishable.
# ===========================================================================
pm_env
"$REAL_JQ" -n '{schema:1,lastRun:{at:"1999-01-01T00:00:00Z",result:"ok",digest:"1999-01-01"}}' > "$STATUS"
pm_stub_claude 'exit 0'
pm_run
assert_eq "AC3c digest is preserved across a failed run" "1999-01-01" "$(pm_status digest)"
assert_eq "AC3c at is updated even on a failed run" "0" \
  "$([ "$(pm_status at)" = "1999-01-01T00:00:00Z" ] && echo 1 || echo 0)"

# ===========================================================================
# AC4 — a failed run must not claim success. Observed through the osascript stub, which
# records the real pm-notify.sh invocation rather than us inferring it.
# ===========================================================================
pm_env
printf 'STALE SUMMARY FROM MONTHS AGO\n' > "$T_KF/pm-reviews/.last-summary"
pm_stub_claude 'exit 0'
pm_run
case "$(cat "$NOTIFY_LOG")" in *"Morning review ready"*) ok=1 ;; *) ok=0 ;; esac
assert_eq "AC4 failed run sends no success notification" "0" "$ok"
case "$(cat "$NOTIFY_LOG")" in *"STALE SUMMARY"*) ok=1 ;; *) ok=0 ;; esac
assert_eq "AC4 failed run does not send the stale summary" "0" "$ok"
assert_eq "AC4 failed run still notifies something" "0" \
  "$([ -s "$NOTIFY_LOG" ] && echo 0 || echo 1)"

# ===========================================================================
# AC5 — BACK-COMPAT CONTROL. The legacy ~/.claude/local/claude must still resolve when it
# exists. The arm CREATES ITS OWN fake executable inside the temp HOME — depending on the real
# path would be vacuous, since it does not exist on this machine
# (instrument-anchored-to-a-live-defect-expires-on-success).
# ===========================================================================
pm_env
mkdir -p "$T_HOME/.claude/local"
printf '#!/bin/sh\nprintf "# digest\\n" > %s/pm-reviews/2099-03-04.md\n' "$T_KF" \
  > "$T_HOME/.claude/local/claude"
chmod +x "$T_HOME/.claude/local/claude"
pm_run "$T_HOME/.claude/local/claude"
assert_eq "AC5 legacy fallback path still resolves" "ok" "$(pm_status result)"
assert_eq "AC5 legacy path produced the digest" "2099-03-04" "$(pm_status digest)"

# ===========================================================================
# AC5b — ORDER. When several candidates are executable, the FIRST in the list wins. Guards the
# precedence contract, which must mirror PATH precedence (~/.local/bin before homebrew) — a
# reordering would silently change which install the morning job runs.
# ===========================================================================
pm_env
mkdir -p "$T_ROOT/first" "$T_ROOT/second"
printf '#!/bin/sh\nprintf "# d\\n" > %s/pm-reviews/2099-first.md\n' "$T_KF" > "$T_ROOT/first/claude"
printf '#!/bin/sh\nprintf "# d\\n" > %s/pm-reviews/2099-second.md\n' "$T_KF" > "$T_ROOT/second/claude"
chmod +x "$T_ROOT/first/claude" "$T_ROOT/second/claude"
pm_run "$T_ROOT/first/claude:$T_ROOT/second/claude"
assert_eq "AC5b first executable candidate wins" "2099-first" "$(pm_status digest)"

pm_summary
exit "$PM_FAIL"
