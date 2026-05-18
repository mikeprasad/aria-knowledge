#!/usr/bin/env bash
# release-codex.sh — build a clean Codex port zip.
#
# Reads version from plugin-codex/.codex-plugin/plugin.json (source of truth),
# stages plugin-codex/ with junk excluded, and emits
# aria-knowledge-codex-<canonical-version>.zip at repo root.
#
# Sibling of release.sh (Claude port). Independent build per the
# multi-port release decision: each port is built standalone.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_MANIFEST="$REPO_ROOT/plugin-codex/.codex-plugin/plugin.json"

log()  { printf '\033[0;36m[release]\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m[  ok   ]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[ warn  ]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[ fail  ]\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight --------------------------------------------------------------
[[ -f "$CODEX_MANIFEST" ]]     || die "missing $CODEX_MANIFEST"
command -v python3 >/dev/null  || die "python3 required for JSON parsing"
command -v rsync   >/dev/null  || die "rsync required"
command -v zip     >/dev/null  || die "zip required"
command -v unzip   >/dev/null  || die "unzip required"

# --- read manifest ----------------------------------------------------------
read_json() {
    python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
for key in sys.argv[2].split("."):
    data = data[key]
print(data)
' "$@"
}

CODEX_NAME=$(read_json "$CODEX_MANIFEST" "name")
CODEX_VERSION=$(read_json "$CODEX_MANIFEST" "version")

# Canonical version for filename = strip the "-codex.N" prerelease suffix
CANONICAL_VERSION="${CODEX_VERSION%-codex.*}"

log "codex:   $CODEX_NAME v$CODEX_VERSION (canonical $CANONICAL_VERSION)"

# --- stage ------------------------------------------------------------------
STAGING=$(mktemp -d -t "aria-codex-release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT

STAGE_DIR="$STAGING/$CODEX_NAME"
log "staging: $STAGE_DIR"
rsync -a \
    --exclude='.DS_Store' \
    --exclude='__MACOSX' \
    --exclude='.claude/' \
    --exclude='PORTING.md' \
    "$REPO_ROOT/plugin-codex/" \
    "$STAGE_DIR/"

# --- zip --------------------------------------------------------------------
ZIP_PATH="$REPO_ROOT/$CODEX_NAME-codex-$CANONICAL_VERSION.zip"
[[ -f "$ZIP_PATH" ]] && warn "overwriting existing $ZIP_PATH"

log "zipping: $(basename "$ZIP_PATH")"
(cd "$STAGING" && zip -rXq "$ZIP_PATH" "$CODEX_NAME")

# --- verify -----------------------------------------------------------------
junk=$(unzip -l "$ZIP_PATH" | grep -cE '(__MACOSX|\.DS_Store|\.claude/settings|PORTING\.md)' || true)
[[ "$junk" -eq 0 ]] || die "verification failed: $junk junk entries in zip"

manifest=$(unzip -l "$ZIP_PATH" | grep -c "$CODEX_NAME/\.codex-plugin/plugin\.json" || true)
[[ "$manifest" -eq 1 ]] || die "verification failed: codex manifest missing or duplicated ($manifest found)"

# --- version-stable copy (for /releases/latest/download/<stable>.zip URLs) --
STABLE_ZIP_PATH="$REPO_ROOT/$CODEX_NAME-codex.zip"
cp "$ZIP_PATH" "$STABLE_ZIP_PATH"

# --- report -----------------------------------------------------------------
SIZE=$(stat -f%z "$ZIP_PATH")
ENTRIES=$(unzip -l "$ZIP_PATH" | tail -1 | awk '{print $2}')

ok "built $CODEX_NAME codex port v$CODEX_VERSION"
printf '         path:    %s\n' "$ZIP_PATH"
printf '         stable:  %s\n' "$STABLE_ZIP_PATH"
printf '         size:    %s bytes\n' "$SIZE"
printf '         entries: %s files\n' "$ENTRIES"
