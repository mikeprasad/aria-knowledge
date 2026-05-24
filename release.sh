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

# --- sync marketplace.json (auto-sync per design) ---------------------------
MARKETPLACE_VERSION=$(read_json "$MARKETPLACE_MANIFEST" "plugins.$PLUGIN_NAME.version")

if [[ "$MARKETPLACE_VERSION" != "$PLUGIN_VERSION" ]]; then
    warn "marketplace.json drift: $MARKETPLACE_VERSION → $PLUGIN_VERSION (auto-syncing)"
    python3 -c '
import json, sys
path, name, ver = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    mkt = json.load(f)
mkt["plugins"][name]["version"] = ver
with open(path, "w") as f:
    json.dump(mkt, f, indent=2)
    f.write("\n")
' "$MARKETPLACE_MANIFEST" "$PLUGIN_NAME" "$PLUGIN_VERSION"
    ok "marketplace.json synced to $PLUGIN_VERSION"
else
    ok "marketplace.json already in sync"
fi

# --- stage ------------------------------------------------------------------
STAGING=$(mktemp -d -t "aria-release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT

log "staging: $STAGING/$PLUGIN_NAME"
rsync -a \
    --exclude='.DS_Store' \
    --exclude='__MACOSX' \
    --exclude='.claude/' \
    "$REPO_ROOT/plugin-claude-code/" \
    "$STAGING/$PLUGIN_NAME/"

# --- zip --------------------------------------------------------------------
ZIP_PATH="$REPO_ROOT/$PLUGIN_NAME-plugin-$PLUGIN_VERSION.zip"
[[ -f "$ZIP_PATH" ]] && warn "overwriting existing $ZIP_PATH"

log "zipping: $(basename "$ZIP_PATH")"
(cd "$STAGING" && zip -rXq "$ZIP_PATH" "$PLUGIN_NAME")

# --- verify -----------------------------------------------------------------
junk=$(unzip -l "$ZIP_PATH" | grep -cE '(__MACOSX|\.DS_Store|\.claude/settings)' || true)
[[ "$junk" -eq 0 ]] || die "verification failed: $junk junk entries in zip"

manifest=$(unzip -l "$ZIP_PATH" | grep -c "$PLUGIN_NAME/\.claude-plugin/plugin\.json" || true)
[[ "$manifest" -eq 1 ]] || die "verification failed: manifest missing or duplicated ($manifest found)"

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
