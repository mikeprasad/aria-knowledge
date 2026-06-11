#!/usr/bin/env bash
# release.sh — build a clean aria-cowork.plugin zip for Cowork Local Zip install.
#
# Reads version from .claude-plugin/plugin.json (source of truth),
# pre-checks the description-length cap (~500 chars per v0.2.1 lesson),
# warns on TEMPLATE-PARITY drift vs aria-knowledge (best-effort),
# stages the plugin contents with junk excluded,
# and emits aria-cowork-<version>.plugin at repo root.
#
# Usage:
#   bash release.sh        # standard build
#   bash release.sh -v     # verbose (manifest fields, file count, archive size)
#
# Per ADR-006 (independent semver), ADR-007 (template parity), ADR-013 (cowork-modified
# skills produce schema-identical outputs).

set -euo pipefail

VERBOSE=0
[[ "${1:-}" == "-v" || "${1:-}" == "--verbose" ]] && VERBOSE=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_MANIFEST="$REPO_ROOT/.claude-plugin/plugin.json"
ARIA_KNOWLEDGE_TEMPLATE="${ARIA_KNOWLEDGE_REPO:-$REPO_ROOT/../aria-knowledge/plugin/template}"

log()  { printf '\033[0;36m[release]\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m[  ok   ]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[ warn  ]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[ fail  ]\033[0m %s\n' "$*" >&2; exit 1; }
vlog() { if [[ "$VERBOSE" -eq 1 ]]; then printf '\033[0;37m[verbose]\033[0m %s\n' "$*"; fi; }

# --- preflight --------------------------------------------------------------
[[ -f "$PLUGIN_MANIFEST" ]] || die "not at repo root (missing $PLUGIN_MANIFEST)"
command -v python3 >/dev/null     || die "python3 required for JSON parsing"
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
PLUGIN_DESC=$(read_json "$PLUGIN_MANIFEST" "description")

log "plugin:  $PLUGIN_NAME v$PLUGIN_VERSION"

# --- description length pre-check (v0.2.1 lesson) ---------------------------
# Cowork's account-marketplace upload validator silently rejects descriptions
# exceeding ~500 chars. v0.2.0's 565-char description tripped this; the
# diagnostic surfaced as a generic "Plugin validation failed." dialog with no
# field-level detail. See ~/Projects/knowledge/guides/claude/cowork-plugin-validation.md
# for the full diagnostic story.

DESC_LEN=${#PLUGIN_DESC}
DESC_CAP=500
vlog "description length: $DESC_LEN chars (cap: ~$DESC_CAP)"

if [[ "$DESC_LEN" -gt "$DESC_CAP" ]]; then
    die "plugin.json description is $DESC_LEN chars (cap ~$DESC_CAP per v0.2.1 lesson). Trim before release."
elif [[ "$DESC_LEN" -gt $((DESC_CAP - 50)) ]]; then
    warn "description is $DESC_LEN chars — within $((DESC_CAP - DESC_LEN)) chars of the ~$DESC_CAP cap. Consider trimming."
fi

# --- total SKILL.md description-bytes cap (v1.0.0 lesson) -------------------
# Cowork rejects plugins whose summed SKILL.md description lengths exceed
# 9 KiB. Empirically bisected 2026-05-19 via aria-cowork v1.0.0:
#   passes:  total 9151 chars (probe K, max 445 — highest verified pass)
#   fails:   total 9233 chars (probe D, max 450 — lowest verified fail)
#   passes:  total 5496 chars (probe F, handoff at 707 — proves NO per-skill cap)
# Per-skill descriptions can be any length individually; only the sum matters.
# Cap window: [9,151, 9,233]; working answer is 9,216 (9 × 1,024 = 9 KiB exactly,
# the only round-number candidate fitting the empirical window).
# See ~/Projects/knowledge/guides/claude/cowork-plugin-validation.md for the
# full bisection trail and ADR-013 for the cowork-side description-trim
# divergence rationale. Warn at >8500, hard-fail at >9000 to leave 216-char
# margin under the suspected cap.

SKILL_TOTAL=$(python3 - <<PY
import yaml, glob, os
total = 0
for f in sorted(glob.glob(os.path.join("$REPO_ROOT", "skills/*/SKILL.md"))):
    with open(f) as fh:
        text = fh.read()
    if not text.startswith("---\n"):
        continue
    end = text.find("\n---\n", 4)
    if end == -1:
        continue
    try:
        fm = yaml.safe_load(text[4:end])
    except Exception:
        continue
    desc = " ".join((fm.get("description") or "").split())
    total += len(desc)
print(total)
PY
)
SKILL_WARN=8500
SKILL_CAP=9000
vlog "total skill description chars: $SKILL_TOTAL (warn >$SKILL_WARN, fail >$SKILL_CAP)"

if [[ "$SKILL_TOTAL" -gt "$SKILL_CAP" ]]; then
    die "summed SKILL.md description chars = $SKILL_TOTAL (hard cap $SKILL_CAP per v1.0.0 lesson; empirical fail at 9233). Trim individual descriptions to bring total down."
elif [[ "$SKILL_TOTAL" -gt "$SKILL_WARN" ]]; then
    warn "summed SKILL.md description chars = $SKILL_TOTAL — within $((SKILL_CAP - SKILL_TOTAL)) chars of the ~$SKILL_CAP cap. Empirical pass-floor is 7876. Consider trimming."
fi

# --- TEMPLATE-PARITY drift check (best-effort) ------------------------------
# Per ADR-007: shared template files between aria-cowork and aria-knowledge
# should maintain content parity. release.sh runs a best-effort diff for the
# canonical shared files. Warnings only — does not block release.

if [[ -d "$ARIA_KNOWLEDGE_TEMPLATE" ]]; then
    log "template-parity check vs $ARIA_KNOWLEDGE_TEMPLATE"
    DRIFT_COUNT=0
    for f in rules/working-rules.md rules/change-decision-framework.md rules/enforcement-mechanisms.md aliases.md intake/intake-doc.md; do
        cowork_file="$REPO_ROOT/template/$f"
        upstream_file="$ARIA_KNOWLEDGE_TEMPLATE/$f"
        if [[ -f "$cowork_file" && -f "$upstream_file" ]]; then
            if ! diff -q "$cowork_file" "$upstream_file" >/dev/null 2>&1; then
                # Diff is OK if it's the /setup → /aria-setup substitution; flag others.
                # Split diff capture from filter pipeline — diff returns 1 when files differ
                # (expected here), and with pipefail+set -e that propagates fatal otherwise.
                DIFF_OUTPUT=$(diff "$cowork_file" "$upstream_file" || true)
                CHANGES=$(printf '%s\n' "$DIFF_OUTPUT" | { grep -v "/aria-setup\|/setup" || true; } | wc -l | tr -d ' ')
                if [[ "$CHANGES" -gt 0 ]]; then
                    warn "TEMPLATE-PARITY drift: $f differs beyond expected /setup ↔ /aria-setup substitution"
                    DRIFT_COUNT=$((DRIFT_COUNT + 1))
                else
                    vlog "template/$f: only expected /setup ↔ /aria-setup substitution differences"
                fi
            else
                vlog "template/$f: byte-identical to aria-knowledge"
            fi
        elif [[ -f "$cowork_file" && ! -f "$upstream_file" ]]; then
            vlog "template/$f: present in cowork, absent in aria-knowledge (expected for cowork-leading files)"
        fi
    done
    if [[ "$DRIFT_COUNT" -gt 0 ]]; then
        warn "$DRIFT_COUNT template file(s) drifted from aria-knowledge canonical. Review before release."
    else
        ok "template-parity check clean"
    fi
else
    vlog "aria-knowledge template path not found at $ARIA_KNOWLEDGE_TEMPLATE — skipping parity check"
fi

# --- stage ------------------------------------------------------------------
STAGING=$(mktemp -d -t "aria-cowork-release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT

log "staging: $STAGING/$PLUGIN_NAME"
# Cowork plugin layout: .claude-plugin/, skills/, template/, plus root docs
# Exclude: build artifacts (.plugin files), macOS junk, git state, probe folder
rsync -a \
    --exclude='.DS_Store' \
    --exclude='__MACOSX' \
    --exclude='.claude/' \
    --exclude='.git/' \
    --exclude='*.plugin' \
    --exclude='probe/' \
    --exclude='release.sh' \
    --exclude='CODEMAP.md' \
    --exclude='IDEAS-BACKLOG.md' \
    "$REPO_ROOT/" \
    "$STAGING/$PLUGIN_NAME/" 2>/dev/null || \
{
    # rsync may not be available — fall back to cp
    warn "rsync unavailable, using cp fallback"
    mkdir -p "$STAGING/$PLUGIN_NAME"
    (cd "$REPO_ROOT" && tar --exclude='.DS_Store' --exclude='__MACOSX' --exclude='.claude' \
        --exclude='.git' --exclude='*.plugin' --exclude='probe' --exclude='release.sh' \
        --exclude='CODEMAP.md' --exclude='IDEAS-BACKLOG.md' \
        -cf - .) | (cd "$STAGING/$PLUGIN_NAME" && tar -xf -)
}

vlog "staged file count: $(find "$STAGING/$PLUGIN_NAME" -type f | wc -l | tr -d ' ')"

# --- zip --------------------------------------------------------------------
ZIP_PATH="$REPO_ROOT/$PLUGIN_NAME-$PLUGIN_VERSION.plugin"
# zip -rX appends to an existing archive — remove first so the build is a clean
# rebuild (otherwise skills removed from the plugin persist in the .plugin forever).
if [[ -f "$ZIP_PATH" ]]; then
    warn "removing existing $ZIP_PATH (clean rebuild)"
    rm -f "$ZIP_PATH"
fi

log "zipping: $(basename "$ZIP_PATH")"
(cd "$STAGING" && zip -rXq "$ZIP_PATH" "$PLUGIN_NAME")

# --- verify -----------------------------------------------------------------
junk=$(unzip -l "$ZIP_PATH" | grep -cE '(__MACOSX|\.DS_Store|\.claude/settings|\.git/)' || true)
[[ "$junk" -eq 0 ]] || die "verification failed: $junk junk entries in zip"

manifest=$(unzip -l "$ZIP_PATH" | grep -c "$PLUGIN_NAME/\.claude-plugin/plugin\.json" || true)
[[ "$manifest" -eq 1 ]] || die "verification failed: manifest missing or duplicated ($manifest found)"

# --- expected-content sanity check ------------------------------------------
# v0.3.0 ships 20 skills + intake-doc.md template + 14 template files.
# Quick existence checks (release-time, not exhaustive).
expected_skills="ask audit-config audit-knowledge context extract handoff index intake prospect retrospect rules snapshot stats wrapup aria-setup help backlog clip foundational-review readiness-audit"
missing_skills=""
# Capture unzip listing once — avoids SIGPIPE+pipefail false-positives when
# grep -q early-exits inside a piped pipeline (kills unzip, pipefail trips).
UNZIP_LIST=$(unzip -l "$ZIP_PATH" 2>/dev/null || true)
for skill in $expected_skills; do
    if ! printf '%s\n' "$UNZIP_LIST" | grep -q "$PLUGIN_NAME/skills/$skill/SKILL.md"; then
        missing_skills="$missing_skills $skill"
    fi
done
if [[ -n "$missing_skills" ]]; then
    warn "missing expected skills:$missing_skills"
fi

# --- report -----------------------------------------------------------------
SIZE=$(stat -f%z "$ZIP_PATH" 2>/dev/null || stat -c%s "$ZIP_PATH")
ENTRIES=$(unzip -l "$ZIP_PATH" | tail -1 | awk '{print $2}')

ok "built $PLUGIN_NAME v$PLUGIN_VERSION"
printf '         path:     %s\n' "$ZIP_PATH"
printf '         size:     %s bytes\n' "$SIZE"
printf '         entries:  %s files\n' "$ENTRIES"
printf '         skills:   %s\n' "$(unzip -l "$ZIP_PATH" 2>/dev/null | grep -c "$PLUGIN_NAME/skills/[^/]*/SKILL\.md$" || echo "?")"

if [[ "$VERBOSE" -eq 1 ]]; then
    echo ""
    echo "Verbose: manifest contents"
    cat "$PLUGIN_MANIFEST"
    echo ""
    echo "Verbose: top-level zip listing (first 30 entries)"
    unzip -l "$ZIP_PATH" | head -35
fi

echo ""
echo "Next steps:"
echo "  1. Install in Cowork: drag $ZIP_PATH onto a Cowork conversation"
echo "     OR Settings → Plugins → Install from file"
echo "  2. Run /aria-setup in any Cowork session to verify"
echo "  3. If targeting public release: create GitHub repo first; then 'gh release create' (Phase 1+)"
