#!/usr/bin/env bash
# release.sh — build a clean plugin zip for Local Zip install.
#
# Reads version from plugin-claude-code/.claude-plugin/plugin.json (source of truth),
# syncs marketplace.json to match, stages plugin-claude-code/ with junk excluded,
# and emits <name>-<version>.zip at repo root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_MANIFEST="$REPO_ROOT/plugin-claude-code/.claude-plugin/plugin.json"
MARKETPLACE_MANIFEST="$REPO_ROOT/.claude-plugin/marketplace.json"

log()  { printf '\033[0;36m[release]\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m[  ok   ]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[ warn  ]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[ fail  ]\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight --------------------------------------------------------------
[[ -f "$MARKETPLACE_MANIFEST" ]] || die "not at repo root (missing .claude-plugin/marketplace.json)"
[[ -f "$PLUGIN_MANIFEST" ]]       || die "missing $PLUGIN_MANIFEST"
command -v python3 >/dev/null     || die "python3 required for JSON parsing"
command -v rsync   >/dev/null     || die "rsync required"
command -v zip     >/dev/null     || die "zip required"
command -v unzip   >/dev/null     || die "unzip required"

# --- read plugin manifest ---------------------------------------------------
read_json() {
    python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
for key in sys.argv[2].split("."):
    data = data[key]
print(data)
' "$@"
}

PLUGIN_NAME=$(read_json "$PLUGIN_MANIFEST" "name")
PLUGIN_VERSION=$(read_json "$PLUGIN_MANIFEST" "version")

log "plugin:  $PLUGIN_NAME v$PLUGIN_VERSION"

# --- release gates (v2.30.0) ------------------------------------------------
# Parity with release-codex.sh: never ship an untested or over-budget surface.

# Gate A — tests must pass: the canonical repro suite + the plugin-claude-code
# suite. Capture output so a failing suite is visible in the abort message.
log "gate A: tests"
if ! gate_a_out=$(sh "$REPO_ROOT/tests/run.sh" 2>&1); then
    printf '%s\n' "$gate_a_out" >&2
    die "gate A failed: tests/run.sh (see failing suite above)"
fi
if ! gate_a_out=$(sh "$REPO_ROOT/plugin-claude-code/tests/run.sh" 2>&1); then
    printf '%s\n' "$gate_a_out" >&2
    die "gate A failed: plugin-claude-code/tests/run.sh (see failing suite above)"
fi
ok "gate A: all test suites pass"

# Gate B — skill-discovery surface budget. The summed frontmatter-description
# bytes across skills/*/SKILL.md are loaded EVERY session (the dominant always-on
# fixed cost — docs/value-analysis.md). Method mirrors value-analysis.md exactly.
# Default 18944 B: re-baselined at v2.30.0 from the v2.28.1-era 16384 after
# v2.29.0's /foundational-review + /readiness-audit landed (live ~17979 + headroom).
# Raise the default deliberately in the commit that adds a skill; ARIA_SKILL_BUDGET
# overrides only for emergencies and warns loudly.
ARIA_SKILL_BUDGET="${ARIA_SKILL_BUDGET:-18944}"
[[ "$ARIA_SKILL_BUDGET" != "18944" ]] && \
    warn "ARIA_SKILL_BUDGET overridden to $ARIA_SKILL_BUDGET (default 18944) — emergency override in effect"
log "gate B: skill-discovery budget"
budget_total=0
budget_report=""
for f in "$REPO_ROOT"/plugin-claude-code/skills/*/SKILL.md; do
    b=$(awk '/^description:/{flag=1; print; next} flag && /^[a-z_-]+:/{flag=0} flag {print}' "$f" | wc -c)
    b=$((b))
    budget_total=$((budget_total + b))
    budget_report="${budget_report}${b} $(basename "$(dirname "$f")")
"
done
if [[ "$budget_total" -gt "$ARIA_SKILL_BUDGET" ]]; then
    warn "skill-discovery surface ${budget_total} B exceeds budget ${ARIA_SKILL_BUDGET} B"
    warn "3 largest descriptions:"
    printf '%s' "$budget_report" | sort -rn | head -3 | while read -r line; do warn "    $line B"; done
    die "gate B failed: trim a description, or raise ARIA_SKILL_BUDGET deliberately and justify it in the commit"
fi
ok "skill-discovery surface: ${budget_total} bytes (budget ${ARIA_SKILL_BUDGET})"

# Gate C — port drift. Report-only this release (initial ledger baselines current
# reality, so ports are legitimately behind; a fatal gate would block on drift it
# did not cause). TODO(v2.31.0): drop the `|| true` to make this a fatal gate.
log "gate C: port drift (report-only)"
if [[ -x "$REPO_ROOT/plugin-claude-code/bin/check-port-drift.sh" ]]; then
    sh "$REPO_ROOT/plugin-claude-code/bin/check-port-drift.sh" || true   # TODO(v2.31.0): make fatal
else
    warn "gate C skipped: plugin-claude-code/bin/check-port-drift.sh not found"
fi

# --- marketplace.json carries no version (current marketplace schema) -------
# Version's source of truth is plugin.json; the marketplace.json plugins[]
# entries intentionally have no version field, so there is nothing to sync.
# (Removed the obsolete name-keyed-dict sync block — it pre-dated the switch
# to the schema-compliant plugins-as-list form and broke on it.)

# --- stage ------------------------------------------------------------------
STAGING=$(mktemp -d -t "aria-release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT

log "staging: $STAGING/$PLUGIN_NAME"
rsync -a \
    --exclude='.DS_Store' \
    --exclude='__MACOSX' \
    --exclude='.claude/' \
    --exclude='tests/' \
    "$REPO_ROOT/plugin-claude-code/" \
    "$STAGING/$PLUGIN_NAME/"

# --- zip --------------------------------------------------------------------
ZIP_PATH="$REPO_ROOT/$PLUGIN_NAME-plugin-$PLUGIN_VERSION.zip"
# zip -rX appends to an existing archive — remove first so the build is a clean
# rebuild (otherwise files removed from the plugin, e.g. tests/, persist forever).
if [[ -f "$ZIP_PATH" ]]; then
    warn "removing existing $ZIP_PATH (clean rebuild)"
    rm -f "$ZIP_PATH"
fi

log "zipping: $(basename "$ZIP_PATH")"
(cd "$STAGING" && zip -rXq "$ZIP_PATH" "$PLUGIN_NAME")

# --- verify -----------------------------------------------------------------
junk=$(unzip -l "$ZIP_PATH" | grep -cE '(__MACOSX|\.DS_Store|\.claude/settings)' || true)
[[ "$junk" -eq 0 ]] || die "verification failed: $junk junk entries in zip"

manifest=$(unzip -l "$ZIP_PATH" | grep -c "$PLUGIN_NAME/\.claude-plugin/plugin\.json" || true)
[[ "$manifest" -eq 1 ]] || die "verification failed: manifest missing or duplicated ($manifest found)"

# tests/ must not ship (parity with release-codex.sh; the suite is dev-only)
tests=$(unzip -l "$ZIP_PATH" | grep -c "$PLUGIN_NAME/tests/" || true)
[[ "$tests" -eq 0 ]] || die "verification failed: tests/ should not ship in canonical zip ($tests found)"

# --- version-stable copy (for /releases/latest/download/<stable>.zip URLs) --
STABLE_ZIP_PATH="$REPO_ROOT/$PLUGIN_NAME-plugin.zip"
cp "$ZIP_PATH" "$STABLE_ZIP_PATH"

# --- report -----------------------------------------------------------------
SIZE=$(stat -f%z "$ZIP_PATH")
ENTRIES=$(unzip -l "$ZIP_PATH" | tail -1 | awk '{print $2}')

ok "built $PLUGIN_NAME v$PLUGIN_VERSION"
printf '         path:    %s\n' "$ZIP_PATH"
printf '         stable:  %s\n' "$STABLE_ZIP_PATH"
printf '         size:    %s bytes\n' "$SIZE"
printf '         entries: %s files\n' "$ENTRIES"
