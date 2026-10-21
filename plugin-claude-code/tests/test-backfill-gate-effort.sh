# shellcheck shell=sh
# Task 6 (D-2): backfill-gate-effort.py repairs `effort:` in gate logs from the
# transcript record of the Write call that created each log.
# Sourced by run.sh under `set -eu`.
BGE_SCRIPT="$DIR/../scripts/backfill-gate-effort.py"
BGE_BASE="$TMPDIR/bge"; rm -rf "$BGE_BASE"; mkdir -p "$BGE_BASE"
BGE_TODAY=$(date +%Y-%m-%d)

bge_log() { # FILE EFFORT_LINE(or empty for none)
  if [ -n "$2" ]; then
    printf -- '---\ntitle: t\n%s\nstatus: x\n---\nbody effort: unrecorded\n' "$2" > "$1"
  else
    printf -- '---\ntitle: t\nstatus: x\n---\nbody\n' > "$1"
  fi
}
bge_rec() { # FILE EFFORT  -> one transcript line
  printf '{"type":"assistant","effort":"%s","timestamp":"t","message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s","content":"x"}}]}}\n' "$2" "$1"
}
bge_build() { # DIR : fresh fixture
  d="$1"; rm -rf "$d"; mkdir -p "$d/k/logs/prospect" "$d/t/p1" "$d/t/p1/s1/subagents"
  L="$d/k/logs/prospect"
  bge_log "$L/a.md" 'effort: unrecorded'
  bge_log "$L/b.md" 'effort: unrecorded'
  bge_log "$L/c.md" 'effort: unrecorded'
  bge_log "$L/d.md" 'effort: medium'
  bge_log "$L/e.md" ''
  {
    bge_rec "$L/a.md" high
    printf 'not json {{{\n'
    bge_rec "$L/b.md" high
    bge_rec "$L/d.md" high
    bge_rec "$L/e.md" high
    printf '{"type":"assistant","effort":"max","message":{"content":"plain string"}}\n'
    printf '{"type":"assistant","effort":"max","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s"}}]}}\n' "$L/c.md"
  } > "$d/t/p1/sess.jsonl"
  bge_rec "$L/b.md" xhigh > "$d/t/p1/s1/subagents/agent-1.jsonl"
  bge_rec "$L/a.md" high >> "$d/t/p1/s1/subagents/agent-1.jsonl"
}
bge_sums() { cksum "$1"/k/logs/prospect/*.md; }

bge_build "$BGE_BASE/r"
bge_before=$(bge_sums "$BGE_BASE/r")
python3 -I -B "$BGE_SCRIPT" --knowledge "$BGE_BASE/r/k" --transcripts "$BGE_BASE/r/t" > "$BGE_BASE/dry.out" 2>&1 || :
assert_eq "bge: dry-run summary" "SUMMARY fill=1 correct=0 ambiguous=1 unmatched=1 errors=0 skipped=0" "$(grep '^SUMMARY' "$BGE_BASE/dry.out" || :)"
assert_eq "bge: dry-run reports FILL a" "1" "$(grep -c '^FILL .*/a.md high$' "$BGE_BASE/dry.out" || :)"
assert_eq "bge: dry-run reports AMBIGUOUS b" "1" "$(grep -c '^AMBIGUOUS .*/b.md high,xhigh$' "$BGE_BASE/dry.out" || :)"
assert_eq "bge: dry-run reports UNMATCHED c" "1" "$(grep -c '^UNMATCHED .*/c.md$' "$BGE_BASE/dry.out" || :)"
assert_eq "bge: dry-run reports CORRECT d (preview)" "1" "$(grep -c '^CORRECT .*/d.md medium -> high$' "$BGE_BASE/dry.out" || :)"
assert_eq "bge: no-effort log e not reported" "0" "$(grep -c '/e.md' "$BGE_BASE/dry.out" || :)"
assert_eq "bge: dry-run changes no file" "$bge_before" "$(bge_sums "$BGE_BASE/r")"

# --apply
bge_build "$BGE_BASE/ap"
bge_before=$(bge_sums "$BGE_BASE/ap")
L="$BGE_BASE/ap/k/logs/prospect"
python3 -I -B "$BGE_SCRIPT" --knowledge "$BGE_BASE/ap/k" --transcripts "$BGE_BASE/ap/t" --apply > "$BGE_BASE/ap.out" 2>&1 || :
assert_eq "bge: apply summary" "SUMMARY fill=1 correct=0 ambiguous=1 unmatched=1 errors=0 skipped=0" "$(grep '^SUMMARY' "$BGE_BASE/ap.out" || :)"
assert_eq "bge: a filled" "effort: high  # from transcript $BGE_TODAY" "$(sed -n 3p "$L/a.md")"
assert_eq "bge: a rest of file intact" "1" "$(printf -- '---\ntitle: t\neffort: high  # from transcript %s\nstatus: x\n---\nbody effort: unrecorded\n' "$BGE_TODAY" | cmp -s - "$L/a.md" && echo 1 || echo 0)"
for f in b c d e; do
  assert_eq "bge: $f byte-identical after apply" "$(cksum "$BGE_BASE/r/k/logs/prospect/$f.md")" "$(cksum "$L/$f.md" | sed "s#/ap/#/r/#")"
done
assert_eq "bge: exactly one line removed overall" "1" "$(diff -r "$BGE_BASE/r/k" "$BGE_BASE/ap/k" | grep -c '^<' || :)"

# idempotent second run
bge_before=$(bge_sums "$BGE_BASE/ap")
python3 -I -B "$BGE_SCRIPT" --knowledge "$BGE_BASE/ap/k" --transcripts "$BGE_BASE/ap/t" --apply > "$BGE_BASE/ap2.out" 2>&1 || :
assert_eq "bge: second apply fill=0" "SUMMARY fill=0 correct=0 ambiguous=1 unmatched=1 errors=0 skipped=0" "$(grep '^SUMMARY' "$BGE_BASE/ap2.out" || :)"
assert_eq "bge: second apply changes nothing" "$bge_before" "$(bge_sums "$BGE_BASE/ap")"

# --correct-self-reported
bge_build "$BGE_BASE/co"
L="$BGE_BASE/co/k/logs/prospect"
python3 -I -B "$BGE_SCRIPT" --knowledge "$BGE_BASE/co/k" --transcripts "$BGE_BASE/co/t" --apply --correct-self-reported > "$BGE_BASE/co.out" 2>&1 || :
assert_eq "bge: correct summary" "SUMMARY fill=1 correct=1 ambiguous=1 unmatched=1 errors=0 skipped=0" "$(grep '^SUMMARY' "$BGE_BASE/co.out" || :)"
assert_eq "bge: d corrected" "effort: high  # corrected from transcript $BGE_TODAY; was medium" "$(sed -n 3p "$L/d.md")"
python3 -I -B "$BGE_SCRIPT" --knowledge "$BGE_BASE/co/k" --transcripts "$BGE_BASE/co/t" --apply --correct-self-reported > "$BGE_BASE/co2.out" 2>&1 || :
assert_eq "bge: corrected is idempotent" "SUMMARY fill=0 correct=0 ambiguous=1 unmatched=1 errors=0 skipped=0" "$(grep '^SUMMARY' "$BGE_BASE/co2.out" || :)"

# CRLF preserved, realpath symlink match, same value twice not ambiguous, trailing comment stripped
rm -rf "$BGE_BASE/x"; mkdir -p "$BGE_BASE/x/k/logs/retrospect" "$BGE_BASE/x/t/p"
ln -s "$BGE_BASE/x/k" "$BGE_BASE/x/klink"
printf -- '---\r\ntitle: t\r\neffort: unrecorded  # old note\r\n---\r\nbody\r\n' > "$BGE_BASE/x/k/logs/retrospect/z.md"
{ bge_rec "$BGE_BASE/x/klink/logs/retrospect/z.md" low; bge_rec "$BGE_BASE/x/k/logs/retrospect/z.md" low; } > "$BGE_BASE/x/t/p/s.jsonl"
python3 -I -B "$BGE_SCRIPT" --knowledge "$BGE_BASE/x/k" --transcripts "$BGE_BASE/x/t" --apply > "$BGE_BASE/x.out" 2>&1 || :
assert_eq "bge: symlink + same-value-twice fills" "SUMMARY fill=1 correct=0 ambiguous=0 unmatched=0 errors=0 skipped=0" "$(grep '^SUMMARY' "$BGE_BASE/x.out" || :)"
assert_eq "bge: CRLF preserved" "1" "$(printf -- '---\r\ntitle: t\r\neffort: low  # from transcript %s\r\n---\r\nbody\r\n' "$BGE_TODAY" | cmp -s - "$BGE_BASE/x/k/logs/retrospect/z.md" && echo 1 || echo 0)"

# no logs dir: exit 0
mkdir -p "$BGE_BASE/empty"
python3 -I -B "$BGE_SCRIPT" --knowledge "$BGE_BASE/empty" --transcripts "$BGE_BASE/empty" > "$BGE_BASE/em.out" 2>&1 && bge_rc=0 || bge_rc=$?
assert_eq "bge: no logs dir exits 0" "0" "$bge_rc"
assert_eq "bge: no logs dir summary" "SUMMARY fill=0 correct=0 ambiguous=0 unmatched=0 errors=0 skipped=0" "$(grep '^SUMMARY' "$BGE_BASE/em.out" || :)"

# --- fix round 1 ---
# F1a: a log edited between scan and apply is SKIPPED, not overwritten with stale offsets.
bge_build "$BGE_BASE/cc"
L="$BGE_BASE/cc/k/logs/prospect"
cat > "$BGE_BASE/cc.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("bge", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
k, t, a_md = sys.argv[2], sys.argv[3], sys.argv[4]
plan = m.build_plan(k, t)
with open(a_md, "wb") as f:  # concurrent writer: longer frontmatter, effort now carries a value
    f.write(b"---\ntitle: a much longer title than before\neffort: medium\nstatus: x\n---\nbody\n")
m.execute(plan, apply=True, correct=False)
PY
rm -rf "$DIR/../scripts/__pycache__"   # I1c: start clean so the assertion below can fail
python3 -I -B "$BGE_BASE/cc.py" "$BGE_SCRIPT" "$BGE_BASE/cc/k" "$BGE_BASE/cc/t" "$L/a.md" > "$BGE_BASE/cc.out" 2>&1 || :
assert_eq "bge: F1a SKIPPED printed" "1" "$(grep -c '^SKIPPED .*/a.md changed-since-scan$' "$BGE_BASE/cc.out" || :)"
assert_eq "bge: F1a concurrent edit preserved" "1" "$(printf -- '---\ntitle: a much longer title than before\neffort: medium\nstatus: x\n---\nbody\n' | cmp -s - "$L/a.md" && echo 1 || echo 0)"
assert_eq "bge: F1a SUMMARY counts the skip" "SUMMARY fill=0 correct=0 ambiguous=1 unmatched=1 errors=0 skipped=1" "$(grep '^SUMMARY' "$BGE_BASE/cc.out" || :)"
# I1c: importing the tool must not leave bytecode beside it (release zips copy the working tree).
assert_eq "bge: F1a harness writes no bytecode" "0" "$([ -d "$DIR/../scripts/__pycache__" ] && echo 1 || echo 0)"

# F1b: two names for one file -> rewritten exactly once
bge_build "$BGE_BASE/sl"
L="$BGE_BASE/sl/k/logs/prospect"
ln -s a.md "$L/a-link.md"
python3 -I -B "$BGE_SCRIPT" --knowledge "$BGE_BASE/sl/k" --transcripts "$BGE_BASE/sl/t" --apply > "$BGE_BASE/sl.out" 2>&1 || :
assert_eq "bge: F1b symlink alias fills once" "SUMMARY fill=1 correct=0 ambiguous=1 unmatched=1 errors=0 skipped=0" "$(grep '^SUMMARY' "$BGE_BASE/sl.out" || :)"
assert_eq "bge: F1b no SKIPPED" "0" "$(grep -c '^SKIPPED' "$BGE_BASE/sl.out" || :)"
assert_eq "bge: F1b alias still a symlink" "1" "$([ -L "$L/a-link.md" ] && echo 1 || echo 0)"
assert_eq "bge: F1b bytes correct" "1" "$(printf -- '---\ntitle: t\neffort: high  # from transcript %s\nstatus: x\n---\nbody effort: unrecorded\n' "$BGE_TODAY" | cmp -s - "$L/a.md" && echo 1 || echo 0)"

# F2: a hostile effort value never writes
rm -rf "$BGE_BASE/inj"; mkdir -p "$BGE_BASE/inj/k/logs/prospect" "$BGE_BASE/inj/t/p"
bge_log "$BGE_BASE/inj/k/logs/prospect/i.md" 'effort: unrecorded'
bge_log "$BGE_BASE/inj/k/logs/prospect/j.md" 'effort: unrecorded'
printf '{"type":"assistant","effort":"high\\ninjected: 1","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s"}}]}}\n' "$BGE_BASE/inj/k/logs/prospect/i.md" > "$BGE_BASE/inj/t/p/s.jsonl"
printf '{"type":"assistant","effort":"high\\ninjected: 1","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s"}}]}}\n' "$BGE_BASE/inj/k/logs/prospect/j.md" >> "$BGE_BASE/inj/t/p/s.jsonl"
bge_rec "$BGE_BASE/inj/k/logs/prospect/j.md" max >> "$BGE_BASE/inj/t/p/s.jsonl"
python3 -I -B "$BGE_SCRIPT" --knowledge "$BGE_BASE/inj/k" --transcripts "$BGE_BASE/inj/t" --apply > "$BGE_BASE/inj.out" 2>&1 || :
assert_eq "bge: F2 summary" "SUMMARY fill=1 correct=0 ambiguous=0 unmatched=1 errors=0 skipped=0" "$(grep '^SUMMARY' "$BGE_BASE/inj.out" || :)"
assert_eq "bge: F2 injected log untouched" "0" "$(grep -c 'injected' "$BGE_BASE/inj/k/logs/prospect/i.md" || :)"
assert_eq "bge: F2 valid sibling record still used" "effort: max  # from transcript $BGE_TODAY" "$(sed -n 3p "$BGE_BASE/inj/k/logs/prospect/j.md")"

# F3: an unwritable directory yields ERROR, others still applied, exit 0
if [ "$(id -u)" != 0 ]; then
  bge_build "$BGE_BASE/er"
  mkdir -p "$BGE_BASE/er/k/logs/retrospect"
  bge_log "$BGE_BASE/er/k/logs/retrospect/r.md" 'effort: unrecorded'
  bge_rec "$BGE_BASE/er/k/logs/retrospect/r.md" low >> "$BGE_BASE/er/t/p1/sess.jsonl"
  chmod 555 "$BGE_BASE/er/k/logs/retrospect"
  python3 -I -B "$BGE_SCRIPT" --knowledge "$BGE_BASE/er/k" --transcripts "$BGE_BASE/er/t" --apply > "$BGE_BASE/er.out" 2>&1 && bge_rc=0 || bge_rc=$?
  chmod 755 "$BGE_BASE/er/k/logs/retrospect"
  assert_eq "bge: F3 exit 0" "0" "$bge_rc"
  assert_eq "bge: F3 ERROR printed" "1" "$(grep -c '^ERROR .*/r.md ' "$BGE_BASE/er.out" || :)"
  assert_eq "bge: F3 summary counts error" "SUMMARY fill=1 correct=0 ambiguous=1 unmatched=1 errors=1 skipped=0" "$(grep '^SUMMARY' "$BGE_BASE/er.out" || :)"
  assert_eq "bge: F3 other file still applied" "effort: high  # from transcript $BGE_TODAY" "$(sed -n 3p "$BGE_BASE/er/k/logs/prospect/a.md")"
fi
