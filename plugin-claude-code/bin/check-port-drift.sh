#!/bin/sh
# check-port-drift.sh — mechanical port-parity drift detection (v2.30.0).
#
# WHAT: replaces prose "tracked-drift" narration with a machine check. Reads
# PORT-LEDGER.json (repo root) — a per-port snapshot of the sha256 of every
# surface that port mirrors — recomputes each surface's current hash, and reports
# which surfaces have changed since their recorded baseline. A snapshot tripwire:
# it flags a mirrored file whose content moved after the last recorded parity
# pass, so an unintended edit or an un-baselined re-sync becomes visible instead
# of silently accruing as prose drift-debt.
#
# It does NOT regenerate ports from canonical (cursor compiles to .mdc, cowork has
# port-divergent bodies by design — ADR-014); detection is cheap and universal,
# generation is neither.
#
# MODES:
#   (default)          print a PORT | SURFACE | STATUS table
#   --quiet            no output; exit 0 iff no out-of-SLA drift/missing, else 1
#   --update <port>    re-baseline one port: recompute its surfaces + stamp
#                      last_parity_pass=today + parity_target=current canonical
#   --update all       re-baseline every port
#
# STATUS: ok (hash matches) · drifted (changed) · missing (file gone) ·
#         within-SLA (drifted but the port's SLA tolerates it for now) ·
#         version-pair-drift (antigravity version.txt vs plugin.json disagree).
# A drift on an SLA=undeclared port is shown but TOLERATED (never fails --quiet)
# until an SLA is declared — so the gate does not brick on pre-existing lag.
#
# Hashing: shasum -a 256. JSON rewrite: jq (precedent: pm-lib.sh requires jq).
# Test seam: PORT_LEDGER overrides the ledger path; PORT_LEDGER_ROOT overrides the
# base dir surfaces resolve against (both default to the resolved repo root).
#
# THE LAG LINE IS A VERSION-STRING COMPARISON, AND THAT IS CORRECT — do not "fix" it
# to compare content or to stay quiet on patch bumps. Measured 2026-08-19 across the
# 11 canonical tag-to-tag transitions from v2.40.0 to v2.46.3, counting files changed
# under plugin-claude-code/{skills,template} (the surfaces ports mirror):
#
#   10 of 11 bumps carried portable change. Only two did not (v2.46.0→.1 and
#   v2.46.1→.2, both hook-only fixes, and hooks are Claude-Code-canonical).
#
# Both cheaper-looking alternatives are falsified by that data:
#   * "only lag on minor/major, patches are cosmetic" — 3 of 5 patch bumps carried
#     portable change (v2.45.1's /interview cadence fix reached cowork as a real gap),
#     while 2 minor bumps carried none. Wrong in BOTH directions.
#   * "hash canonical's portable surface instead" — there is no well-defined portable
#     surface to hash: cursor COMPILES skills to .mdc, cowork diverges by design
#     (ADR-014), and some canonical skills (/statusline, /auto) have no port at all.
#
# So a bump usually DOES mean a port has something to re-verify, and the line saying
# so is signal, not noise. It is display-only (inside the non-quiet branch), never
# reaching is_failure() or the --quiet exit code, so it cannot brick a release.
# Clear it by doing the parity work and re-baselining — never by muting it.
#
# Fatality is gated on a DECLARED SLA, not on a version number. release.sh runs this
# report-only; a port whose `sla` is `undeclared` is tolerated by is_failure() by
# construction, so declaring an SLA is what makes the gate bite for that port. (A
# `TODO(v2.31.0): make fatal` lived here until 2026-08-17, by which time canonical was
# 2.46.1 — fifteen minor versions past its own flag day. Retired, not re-dated.)
set -u

LEDGER_BASENAME="PORT-LEDGER.json"
CANONICAL_MANIFEST="plugin-claude-code/.claude-plugin/plugin.json"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# Repo root: prefer git; fall back to two levels up (script lives at
# <root>/plugin-claude-code/bin/). Validate by the ledger's presence.
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "${REPO_ROOT:-}" ] || [ ! -f "$REPO_ROOT/$LEDGER_BASENAME" ]; then
  _cand=$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd || true)
  [ -n "${_cand:-}" ] && REPO_ROOT="$_cand"
fi

LEDGER="${PORT_LEDGER:-$REPO_ROOT/$LEDGER_BASENAME}"
ROOT="${PORT_LEDGER_ROOT:-$REPO_ROOT}"

command -v jq >/dev/null 2>&1 || { echo "check-port-drift: jq not found (required)" >&2; exit 2; }

today() { date +%Y-%m-%d; }

# Epoch seconds for a YYYY-MM-DD date; BSD (macOS) date first, GNU date fallback.
date_epoch() {
  date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null || echo 0
}

# Tolerance window in days by SLA class. continuous = none; undeclared handled
# separately (always tolerated until declared).
sla_window_days() {
  case "$1" in
    continuous) echo 0 ;;
    coordinated) echo 35 ;;   # release-paired; one release cadence of grace
    quarterly) echo 90 ;;
    *) echo 0 ;;
  esac
}

sha() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

# Current canonical version (for parity_target stamping). Tolerant: empty if absent.
canonical_version() {
  _m="$ROOT/$CANONICAL_MANIFEST"
  [ -f "$_m" ] || return 0
  grep '"version"' "$_m" | head -1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
}

# Read a port's declared version from its manifest (best-effort, tolerant).
port_manifest_version() {
  case "$1" in
    claude-code)     _f="$ROOT/plugin-claude-code/.claude-plugin/plugin.json" ; _mode=json ;;
    claude-cowork)   _f="$ROOT/plugin-claude-cowork/.claude-plugin/plugin.json" ; _mode=json ;;
    openai-codex)    _f="$ROOT/plugin-openai-codex/.codex-plugin/plugin.json" ; _mode=json ;;
    cursor-template) _f="$ROOT/plugin-cursor-template/scripts/aria/VERSION" ; _mode=raw ;;
    antigravity)     _f="$ROOT/plugin-antigravity/version.txt" ; _mode=raw ;;
    *) return 0 ;;
  esac
  [ -f "$_f" ] || return 0
  if [ "$_mode" = json ]; then
    grep '"version"' "$_f" | head -1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
  else
    head -1 "$_f" | tr -d ' \t\r\n'
  fi
}

# Glob spec → repo-relative surface paths for the known ports. Emits one path per
# line for every file that currently exists. Unknown ports emit nothing (the
# --update fallback then re-hashes whatever the ledger already lists).
port_surface_paths() {
  case "$1" in
    claude-code) : ;;  # baseline — version only, no surfaces
    claude-cowork)
      for f in "$ROOT"/plugin-claude-cowork/skills/*/SKILL.md; do [ -f "$f" ] && printf '%s\n' "${f#$ROOT/}"; done
      [ -f "$ROOT/plugin-claude-cowork/template/rules/working-rules.md" ] && printf '%s\n' "plugin-claude-cowork/template/rules/working-rules.md"
      ;;
    openai-codex)
      for f in "$ROOT"/plugin-openai-codex/skills/*/SKILL.md; do [ -f "$f" ] && printf '%s\n' "${f#$ROOT/}"; done
      for f in "$ROOT"/plugin-openai-codex/template/rules/*.md; do [ -f "$f" ] && printf '%s\n' "${f#$ROOT/}"; done
      ;;
    cursor-template)
      [ -f "$ROOT/plugin-cursor-template/.cursor/rules/aria-commands.mdc" ] && printf '%s\n' "plugin-cursor-template/.cursor/rules/aria-commands.mdc"
      [ -f "$ROOT/plugin-cursor-template/knowledge/rules/working-rules.md" ] && printf '%s\n' "plugin-cursor-template/knowledge/rules/working-rules.md"
      ;;
    antigravity)
      for f in "$ROOT"/plugin-antigravity/skills/*/SKILL.md; do [ -f "$f" ] && printf '%s\n' "${f#$ROOT/}"; done
      ;;
  esac
}

ports() { jq -r 'keys[]' "$LEDGER"; }

# --- antigravity version-pair check (the documented silent-drift trap) ---
# version.txt (sidecar, build.sh-synced) must equal plugin.json's version field
# (hand-bumped). Returns "ok" or "version-pair-drift"; empty if files absent.
antigravity_version_pair_status() {
  _vt="$ROOT/plugin-antigravity/version.txt"
  _pj="$ROOT/plugin-antigravity/plugin.json"
  [ -f "$_vt" ] && [ -f "$_pj" ] || return 0
  _a=$(head -1 "$_vt" | tr -d ' \t\r\n')
  _b=$(grep '"version"' "$_pj" | head -1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
  if [ "$_a" = "$_b" ]; then echo "ok"; else echo "version-pair-drift"; fi
}

# Classify a single surface: prints the status word.
surface_status() {
  _port="$1"; _path="$2"; _baseline="$3"; _sla="$4"; _last="$5"
  _file="$ROOT/$_path"
  if [ ! -f "$_file" ]; then echo "missing"; return; fi
  _cur=$(sha "$_file")
  if [ "$_cur" = "$_baseline" ]; then echo "ok"; return; fi
  # drifted — does the SLA tolerate it?
  case "$_sla" in
    undeclared) echo "drifted" ;;          # shown, but tolerated for exit code
    continuous) echo "drifted" ;;
    coordinated|quarterly)
      _win=$(sla_window_days "$_sla")
      _age=$(( ( $(date_epoch "$(today)") - $(date_epoch "$_last") ) / 86400 ))
      if [ "$_age" -lt "$_win" ]; then echo "within-SLA"; else echo "drifted"; fi
      ;;
    *) echo "drifted" ;;
  esac
}

# Is a status a --quiet failure for a given SLA? missing always fails;
# drifted fails unless the SLA is undeclared (no contract to violate yet).
is_failure() {
  _status="$1"; _sla="$2"
  case "$_status" in
    missing) return 0 ;;
    version-pair-drift) return 0 ;;
    drifted) [ "$_sla" = "undeclared" ] && return 1 || return 0 ;;
    *) return 1 ;;
  esac
}

run_report() {
  _quiet="$1"
  _fail=0
  # Resolve canonical ONCE for the lag line below — it is the same value for every port,
  # and canonical_version() shells out to grep+sed each call.
  _canon_live=$(canonical_version)
  [ "$_quiet" = no ] && printf '%-16s %-60s %s\n' "PORT" "SURFACE" "STATUS"
  [ "$_quiet" = no ] && printf '%-16s %-60s %s\n' "----" "-------" "------"
  for p in $(ports); do
    _sla=$(jq -r --arg p "$p" '.[$p].sla // "undeclared"' "$LEDGER")
    _last=$(jq -r --arg p "$p" '.[$p].last_parity_pass // "1970-01-01"' "$LEDGER")
    # NOTE: the ledger's `version` field is deliberately NOT read here any more. It is a
    # port's own declared version and is no longer an operand of the lag comparison below;
    # it remains in the ledger for provenance and for `--update` stamping.
    _ptarget=$(jq -r --arg p "$p" '.[$p].parity_target // "?"' "$LEDGER")
    # version-lag line (informational; not a surface, not a failure).
    #
    # Compares the port's `parity_target` — the canonical version it was last synced
    # AGAINST — to LIVE canonical. Deliberately NOT the port's own `version`: those two
    # ledger fields are written together by `--update`, so they are equal by construction
    # the moment a baseline is taken and never diverge as canonical moves on afterwards.
    # That made this line silent for the only lag that actually exists — the kind that
    # accrues AFTER a baseline. Measured 2026-08-17: antigravity read 2.36.0/2.36.0 and
    # reported nothing while canonical was 2.46.1, nine minor versions ahead.
    #
    # Dropping the port's own version as an operand also removes claude-cowork's permanent
    # false positive for free: cowork versions on an independent 1.x scheme that can never
    # equal a 2.x target, so the old comparison flagged it on every run forever. That was a
    # symptom of comparing the wrong two things, not a case needing an exemption.
    #
    # An unresolvable canonical emits NO lag line. canonical_version() is deliberately
    # tolerant (empty when the manifest is absent) because its original caller is `--update`
    # stamping, where a missing manifest must not break a re-baseline. Empty as a comparison
    # operand would instead make every port "differ" and report lag — so guard it here, at
    # the call site whose meaning differs. Lag is undefined without a reference point.
    if [ "$_quiet" = no ] && [ "$p" != "claude-code" ] && [ -n "$_canon_live" ] \
       && [ "$_ptarget" != "$_canon_live" ]; then
      printf '%-16s %-60s %s\n' "$p" \
        "(synced to $_ptarget → canonical $_canon_live, sla=$_sla)" "lag"
    fi
    # surfaces
    _surfaces=$(jq -r --arg p "$p" '.[$p].surfaces // {} | keys[]?' "$LEDGER")
    for s in $_surfaces; do
      _base=$(jq -r --arg p "$p" --arg s "$s" '.[$p].surfaces[$s]' "$LEDGER")
      _st=$(surface_status "$p" "$s" "$_base" "$_sla" "$_last")
      [ "$_quiet" = no ] && printf '%-16s %-60s %s\n' "$p" "$s" "$_st"
      if is_failure "$_st" "$_sla"; then _fail=1; fi
    done
    # antigravity version-pair pseudo-surface
    if [ "$p" = "antigravity" ]; then
      _vp=$(antigravity_version_pair_status)
      if [ -n "$_vp" ]; then
        [ "$_quiet" = no ] && printf '%-16s %-60s %s\n' "$p" "version.txt vs plugin.json" "$_vp"
        if is_failure "$_vp" "$_sla"; then _fail=1; fi
      fi
    fi
  done
  return $_fail
}

update_port() {
  _port="$1"
  [ -f "$LEDGER" ] || echo '{}' > "$LEDGER"
  _ver=$(port_manifest_version "$_port"); [ -z "$_ver" ] && _ver=$(jq -r --arg p "$_port" '.[$p].version // "unknown"' "$LEDGER")
  _canon=$(canonical_version)
  if [ "$_port" = "claude-code" ]; then
    _ptarget="$_ver"   # the baseline is its own target
  else
    _ptarget="${_canon:-$(jq -r --arg p "$_port" '.[$p].parity_target // "unknown"' "$LEDGER")}"
  fi
  _sla=$(jq -r --arg p "$_port" '.[$p].sla // "undeclared"' "$LEDGER")
  _date=$(today)

  # Build the surfaces object. Prefer the glob spec; fall back to the paths the
  # ledger already lists (covers test ports / ad-hoc surfaces with no glob).
  _paths=$(port_surface_paths "$_port")
  if [ -z "$_paths" ]; then
    _paths=$(jq -r --arg p "$_port" '.[$p].surfaces // {} | keys[]?' "$LEDGER")
  fi
  _surf_json="{}"
  for s in $_paths; do
    _h=$(sha "$ROOT/$s")
    [ -z "$_h" ] && continue
    _surf_json=$(printf '%s' "$_surf_json" | jq --arg k "$s" --arg v "$_h" '. + {($k): $v}')
  done

  _tmp="${LEDGER}.tmp.$$"
  jq --arg p "$_port" --arg ver "$_ver" --arg pt "$_ptarget" --arg lp "$_date" \
     --arg sla "$_sla" --argjson surf "$_surf_json" \
     '.[$p] = {version:$ver, parity_target:$pt, last_parity_pass:$lp, sla:$sla, surfaces:$surf}' \
     "$LEDGER" > "$_tmp" && mv "$_tmp" "$LEDGER"
  echo "re-baselined $_port: version=$_ver parity_target=$_ptarget surfaces=$(printf '%s' "$_surf_json" | jq 'length') last_parity_pass=$_date"
}

# --- arg parsing ---
case "${1:-}" in
  --quiet)
    run_report quiet; exit $?
    ;;
  --update)
    [ -n "${2:-}" ] || { echo "usage: check-port-drift.sh --update <port|all>" >&2; exit 2; }
    if [ "$2" = all ]; then
      for p in claude-code claude-cowork openai-codex cursor-template antigravity; do update_port "$p"; done
    else
      update_port "$2"
    fi
    exit 0
    ;;
  ""|--table)
    run_report no
    _rc=$?
    [ "$_rc" -ne 0 ] && echo "" && echo "drift detected (out-of-SLA surfaces or version-pair mismatch above)"
    exit "$_rc"
    ;;
  *)
    echo "usage: check-port-drift.sh [--table | --quiet | --update <port|all>]" >&2
    exit 2
    ;;
esac
