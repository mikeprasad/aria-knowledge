# shellcheck shell=sh
# test-user-rules-digest.sh — bin/lib-user-rules.sh: four honest renderings + D3.
# T3 of docs/superpowers/plans/2026-08-28-user-rules-digest-honest-rendering-plan.md.
#
# NOTE: sourced by run.sh under `set -eu` into a SHARED shell with shared APM_PASS /
# APM_FAIL counters — so every variable here is UD_-prefixed, there is no `exit`, and
# any intended-nonzero exit uses `RC=0; cmd || RC=$?` (never `cmd; RC=$?`, which aborts
# the whole suite).

UD_BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
UD_LIB="$UD_BIN/lib-user-rules.sh"
UD_TMP="${TMPDIR:-/tmp}/aria-ud-$$"
mkdir -p "$UD_TMP"

# ud_render FIXTURE_DIR -> the digest block for a fixture knowledge folder
ud_render() { ( KT_KNOWLEDGE_FOLDER="$1"; . "$UD_LIB"; kt_user_rules_block; printf '%s' "$KT_USER_RULES_BLOCK" ); }
# ud_rules FIXTURE_DIR -> just the rule lines
ud_rules() { ud_render "$1" | grep '^- \*\*U' || true; }
# ud_fixture NAME BODY... -> writes $UD_TMP/NAME/rules/user-rules.md, echoes the dir
ud_fixture() { mkdir -p "$UD_TMP/$1/rules"; cat > "$UD_TMP/$1/rules/user-rules.md"; printf '%s' "$UD_TMP/$1"; }

# ---------- branch (i): a lead inside the window renders in full ----------
UD_D=$(ud_fixture fits <<'EOF'
### U1. Short rule

Do the thing, then verify it.
EOF
)
assert_eq "[UD1] lead inside the window renders in full" \
  "- **U1 — Short rule** — Do the thing, then verify it." "$(ud_rules "$UD_D")"

# ---------- branch (ii): over the window WITH a sentence boundary -> cut there ----------
# 260-byte lead whose only '. ' sits at ~60 bytes, well inside the 240 window.
UD_D=$(ud_fixture sentence <<'EOF'
### U2. Sentence rule

First sentence ends here and is the useful claim. Then a long trailing clause that runs past the window and carries qualifications nobody needs in a digest, padding this lead well beyond two hundred and forty bytes so the window is exceeded.
EOF
)
UD_OUT="$(ud_rules "$UD_D")"
assert_eq "[UD2a] cuts at the sentence boundary" \
  "- **U2 — Sentence rule** — First sentence ends here and is the useful claim." "$UD_OUT"
assert_eq "[UD2b] no ellipsis on a sentence cut" "0" "$(printf '%s' "$UD_OUT" | grep -c '…' || true)"

# ---------- branch (iii): over the window with NO boundary -> carried WHOLE ----------
# One clause, no '. ' anywhere, 300+ bytes. Must survive intact.
UD_D=$(ud_fixture whole <<'EOF'
### U3. Uncuttable rule

never do the thing unless the other thing has already happened and been verified twice by two different instruments, because a single instrument that agrees with itself is not corroboration and the failure mode here is silent rather than loud, which is the expensive kind
EOF
)
UD_OUT="$(ud_rules "$UD_D")"
assert_eq "[UD3a] carries the whole lead when it cannot be cut" "1" \
  "$(printf '%s' "$UD_OUT" | grep -c 'which is the expensive kind$' || true)"
assert_eq "[UD3b] no ellipsis when carried whole" "0" "$(printf '%s' "$UD_OUT" | grep -c '…' || true)"

# ---------- branch (iv): past the CEILING -> title only ----------
UD_D=$(mkdir -p "$UD_TMP/ceiling/rules" && { printf '### U4. Pathological rule\n\n'; awk 'BEGIN{s="";for(i=0;i<200;i++)s=s "word ";print s}'; } > "$UD_TMP/ceiling/rules/user-rules.md" && printf '%s' "$UD_TMP/ceiling")
UD_OUT="$(ud_rules "$UD_D")"
assert_eq "[UD4a] past the ceiling renders title only" "- **U4 — Pathological rule**" "$UD_OUT"
assert_eq "[UD4b] no body leaks past the ceiling" "0" "$(printf '%s' "$UD_OUT" | grep -c ' — word' || true)"

# ---------- the CLASS property: no rendering ever severs a claim ----------
UD_ALL=$(mkdir -p "$UD_TMP/all/rules" && cat "$UD_TMP"/fits/rules/user-rules.md "$UD_TMP"/sentence/rules/user-rules.md "$UD_TMP"/whole/rules/user-rules.md "$UD_TMP"/ceiling/rules/user-rules.md > "$UD_TMP/all/rules/user-rules.md" && printf '%s' "$UD_TMP/all")
assert_eq "[UD5] no ellipsis across all four branches" "0" "$(ud_render "$UD_ALL" | grep -c '…' || true)"
assert_eq "[UD5b] all four rules still render a line" "4" "$(ud_rules "$UD_ALL" | grep -c '^- \*\*U' || true)"

# ---------- D3: a multi-line lead carries EVERY line of its paragraph ----------
UD_D=$(ud_fixture multiline <<'EOF'
### U5. Wrapped rule

First line of the lead
and the second line of the same paragraph.

**Origin:** must not appear in the digest.
EOF
)
UD_OUT="$(ud_rules "$UD_D")"
assert_eq "[UD6a] D3 — second line of the lead is present" "1" \
  "$(printf '%s' "$UD_OUT" | grep -c 'and the second line of the same paragraph' || true)"
assert_eq "[UD6b] provenance block does not leak into the lead" "0" \
  "$(printf '%s' "$UD_OUT" | grep -c 'Origin' || true)"

# ---------- a LEADING provenance block is skipped, not rendered ----------
UD_D=$(ud_fixture originfirst <<'EOF'
### U6. Origin-first rule

**Origin:** stamped by an audit.

The actual claim is here.
EOF
)
assert_eq "[UD7] a leading Origin block is skipped" \
  "- **U6 — Origin-first rule** — The actual claim is here." "$(ud_rules "$UD_D")"

# ---------- AC-T2f: the RELATIONSHIP, not the literal ----------
# The generator window and check-rule-lead-bytes.sh's default MUST be equal. 240 is an
# authoring contract (audit-rules Step 7.2), so the two moving apart is the defect —
# a coordinated change to both is legitimate and must stay green, which is why this
# asserts the relationship and NOT the number.
UD_GEN_W="$(sed -n 's/^  _kt_ur_window=\([0-9]*\).*/\1/p' "$UD_LIB" | head -1)"
UD_GATE_W="$(sed -n 's/^BUDGET="${2:-\([0-9]*\)}".*/\1/p' "$UD_BIN/check-rule-lead-bytes.sh" | head -1)"
assert_eq "[UD8a] generator window is discoverable" "1" "$([ -n "$UD_GEN_W" ] && echo 1 || echo 0)"
assert_eq "[UD8b] gate default is discoverable" "1" "$([ -n "$UD_GATE_W" ] && echo 1 || echo 0)"
assert_eq "[UD8c] AC-T2f — generator window equals the gate default" "$UD_GATE_W" "$UD_GEN_W"

# ---------- AC-T1b-i: byte-identity against a FROZEN fixture ----------
# Deterministic stand-in for the live-corpus check, which is not assertable here: this
# workspace runs concurrent sessions and an /audit rules run mid-suite would change the
# corpus for a reason unrelated to the code.
UD_D=$(ud_fixture frozen <<'EOF'
### U1. Alpha

Alpha claim, short and complete.

### U2. Beta

Beta claim, also short.
EOF
)
assert_eq "[UD9] frozen fixture renders byte-for-byte as expected" \
  "- **U1 — Alpha** — Alpha claim, short and complete.
- **U2 — Beta** — Beta claim, also short." "$(ud_rules "$UD_D")"

# ---------- the valve: above KT_USER_RULES_MAX the digest becomes a pointer ----------
UD_OUT="$( KT_KNOWLEDGE_FOLDER="$UD_D" KT_USER_RULES_MAX=10 sh -c '. "$0"; kt_user_rules_block; printf "%s" "$KT_USER_RULES_BLOCK"' "$UD_LIB" )"
assert_eq "[UD10a] over the valve, the pointer tier replaces the digest" "1" \
  "$(printf '%s' "$UD_OUT" | grep -c 'too many to summarise inline' || true)"
assert_eq "[UD10b] over the valve, no rule lines are emitted" "0" \
  "$(printf '%s' "$UD_OUT" | grep -c '^- \*\*U' || true)"

# ---------- the empty-state contract: absent file / zero rules inject NOTHING ----------
mkdir -p "$UD_TMP/empty/rules"
assert_eq "[UD11a] absent user-rules.md injects nothing" "" "$(ud_render "$UD_TMP/nonexistent-dir")"
: > "$UD_TMP/empty/rules/user-rules.md"
assert_eq "[UD11b] a file with zero U-rules injects nothing" "" "$(ud_render "$UD_TMP/empty")"


# ---------- the regeneration guard is CONTENT-based, so a stale rendering self-heals ----------
# ⛔ This is the discriminating condition, and it is why the guard cannot be a timestamp test:
# the installed file is written AFTER the source here, so it is strictly NEWER. A
# source-vs-output `-nt` test therefore skips, and the stale rendering survives — which is
# exactly what shipped before 2.52.0 and is why a plugin upgrade that changed the rendering
# reached no existing user. Mutation-proven both ways: content guard heals it, timestamp gate
# leaves it corrupted.
UD_H="$UD_TMP/home"
mkdir -p "$UD_H/.claude/rules" "$UD_TMP/kf/rules"
printf '### U1. Alpha\n\nAlpha claim, short and complete.\n' > "$UD_TMP/kf/rules/user-rules.md"
printf -- '---\nknowledge_folder: %s\n---\n' "$UD_TMP/kf" > "$UD_H/.claude/aria-knowledge.local.md"
printf 'CORRUPTED — not what the generator would produce\n' > "$UD_H/.claude/rules/aria-user-rules.md"
HOME="$UD_H" KT_CONFIG="$UD_H/.claude/aria-knowledge.local.md" \
  sh "$UD_BIN/session-start-rules.sh" </dev/null >/dev/null 2>&1 || true
assert_eq "[UD12a] a stale rendering self-heals even when it is NEWER than the source" "1" \
  "$(grep -c '^- \*\*U1' "$UD_H/.claude/rules/aria-user-rules.md" 2>/dev/null || true)"
assert_eq "[UD12b] the corrupted content is gone" "0" \
  "$(grep -c 'CORRUPTED' "$UD_H/.claude/rules/aria-user-rules.md" 2>/dev/null || true)"
assert_eq "[UD12c] no temp file is left behind" "0" \
  "$(ls "$UD_H/.claude/rules/" 2>/dev/null | grep -c 'tmp' || true)"

rm -rf "$UD_TMP"
