# shellcheck shell=sh
# test-runtime-gates.sh — runtime gates self-correct instead of asking (v2.51.0).
# T5 of docs/superpowers/plans/2026-08-28-runtime-gate-auto-redirect-plan.md.
#
# Before this file there were ZERO tests touching any of the 57 runtime gates in
# either plugin — measured. So both the old behaviour and the new one were unguarded.
#
# NOTE: sourced under run.sh's `set -eu`; capture intended-nonzero exits with
# `RC=0; cmd || RC=$?`, never `cmd; RC=$?`, which would abort the suite.
PCC="$(cd "$(dirname "$0")/.." && pwd)"
RGROOT="$(cd "$PCC/.." && pwd)"
RG_TMP="${TMPDIR:-/tmp}/aria-rg-$$"
mkdir -p "$RG_TMP"

# A gate is IN SCOPE iff the counterpart skill exists on the other side. Derived,
# never hardcoded — a hardcoded list silently rots the next time a skill is ported.
rg_inscope() { # SIDE -> prints skill names
  _me="$1"; _other=$([ "$_me" = "cowork" ] && echo code || echo cowork)
  for _f in "$RGROOT/plugin-claude-$_me"/skills/*/SKILL.md; do
    [ -f "$_f" ] || continue
    grep -q '^## Runtime Gate' "$_f" || continue
    _n=$(basename "$(dirname "$_f")")
    [ -d "$RGROOT/plugin-claude-$_other/skills/$_n" ] && printf '%s\n' "$_n"
  done
}

# ---------- RG1: every in-scope gate redirects, and none of them still asks ----------
RG1_NOREDIR=0; RG1_ASKS=0
for _side in cowork code; do
  for _n in $(rg_inscope "$_side"); do
    _f="$RGROOT/plugin-claude-$_side/skills/$_n/SKILL.md"
    grep -q 'Do not ask — redirect' "$_f" || { RG1_NOREDIR=$((RG1_NOREDIR+1)); printf '    missing redirect: %s/%s\n' "$_side" "$_n"; }
    if grep -q 'Wait for an explicit reply' "$_f" || grep -qF '(`y` / `n`)' "$_f"; then
      RG1_ASKS=$((RG1_ASKS+1)); printf '    still asks: %s/%s\n' "$_side" "$_n"
    fi
  done
done
assert_eq "[RG1] every in-scope gate redirects" "0" "$RG1_NOREDIR"
assert_eq "[RG1b] no in-scope gate still asks y/n" "0" "$RG1_ASKS"

# ---------- RG2: D4 — a gate with NO counterpart must NOT auto-redirect ----------
# This is the guard that stops D4 decaying. Auto-redirecting a skill whose counterpart
# does not exist recreates the v2.49.0 defect: a redirect gate pointing at nothing.
RG2=0; RG2_SEEN=0
for _f in "$RGROOT/plugin-claude-code"/skills/*/SKILL.md; do
  [ -f "$_f" ] || continue
  grep -q '^## Runtime Gate' "$_f" || continue
  _n=$(basename "$(dirname "$_f")")
  [ -d "$RGROOT/plugin-claude-cowork/skills/$_n" ] && continue
  RG2_SEEN=$((RG2_SEEN+1))
  grep -q 'Do not ask — redirect' "$_f" && { RG2=$((RG2+1)); printf '    redirects with no target: code/%s\n' "$_n"; }
done
assert_eq "[RG2] no-counterpart gates do not auto-redirect" "0" "$RG2"
# The check is only meaningful if such gates exist at all — pin that they do.
[ "$RG2_SEEN" -ge 1 ] && RG2C=yes || RG2C=no
assert_eq "[RG2b] the no-counterpart set is non-empty (check is live)" "yes" "$RG2C"

# ---------- RG3: cowork descriptions advertise no BARE slash form (D1) ----------
rg_bare() { # FILE -> prints bare slash tokens found in the description
  awk '/^description:/{flag=1} flag{print} flag&&/"[[:space:]]*$/{exit}' "$1" \
    | grep -oE "'/[a-z][a-z-]*'" | grep -v 'aria-cowork' || true
}
RG3=0
for _f in "$RGROOT/plugin-claude-cowork"/skills/*/SKILL.md; do
  [ -f "$_f" ] || continue
  [ -n "$(rg_bare "$_f")" ] && { RG3=$((RG3+1)); printf '    bare form advertised: %s\n' "$(basename "$(dirname "$_f")")"; }
done
assert_eq "[RG3] no cowork description advertises a bare slash form" "0" "$RG3"

# Positive control: plant one in a copy. A zero without this is a dead instrument.
cp "$RGROOT/plugin-claude-cowork/skills/wrapup/SKILL.md" "$RG_TMP/ctl.md"
sed -i.bak "s|Triggers — |Triggers — '/wrapup', |" "$RG_TMP/ctl.md" 2>/dev/null || \
  sed -i '' "s|Triggers — |Triggers — '/wrapup', |" "$RG_TMP/ctl.md"
[ -n "$(rg_bare "$RG_TMP/ctl.md")" ] && RG3C=yes || RG3C=no
assert_eq "[RG3b] positive control: the bare-form check can see one" "yes" "$RG3C"

# ---------- RG4: the false nonexistent-counterpart claim stays dead ----------
# Three Code gates asserted "No Cowork variant ships yet" while cowork shipped all
# three, so a Cowork user was offered a degraded Code run instead of the right variant.
RG4=$(grep -rl 'No Cowork variant ships yet' "$RGROOT/plugin-claude-code/skills" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "[RG4] no gate claims a counterpart is missing that exists" "0" "$RG4"

rm -rf "$RG_TMP"
