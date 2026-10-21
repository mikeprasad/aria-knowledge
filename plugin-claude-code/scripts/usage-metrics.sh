#!/bin/sh
# usage-metrics.sh — deterministic value/ROI metrics over the user's knowledge corpus.
# Emits a labeled key-value block on stdout. Consumed by skills/audit-usage.
# Usage: sh usage-metrics.sh   (reads KT_KNOWLEDGE_FOLDER via config.sh)
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/config.sh" 2>/dev/null || true
KF="${KT_KNOWLEDGE_FOLDER}"
if [ -z "$KF" ] || [ ! -d "$KF" ]; then
  echo "USAGE_METRICS_ERROR knowledge_folder-unset-or-missing"
  exit 0
fi

# --- Prospect verdict distribution (primary key only) ---
pdir="$KF/logs/prospect"
p_total=0; p_pwc=0; p_clean=0; p_hold=0
if [ -d "$pdir" ]; then
  for f in "$pdir"/*.md; do
    [ -e "$f" ] || continue
    v=$(grep -m1 '^overall_verdict:' "$f" 2>/dev/null | sed 's/^overall_verdict: *//')
    [ -z "$v" ] && continue
    p_total=$((p_total+1))
    case "$v" in
      PROCEED-WITH-CHANGES) p_pwc=$((p_pwc+1)) ;;
      PROCEED)              p_clean=$((p_clean+1)) ;;
      *)                    p_hold=$((p_hold+1)) ;;
    esac
  done
fi
echo "PROSPECT_TOTAL $p_total"
echo "PROSPECT_PWC $p_pwc"
echo "PROSPECT_CLEAN $p_clean"
echo "PROSPECT_HOLD $p_hold"

# --- Prospect month buckets ---
if [ -d "$pdir" ]; then
  for ym in $(ls "$pdir" 2>/dev/null | grep -oE '^[0-9]{4}-[0-9]{2}' | sort -u); do
    m_pwc=0; m_clean=0; m_hold=0
    for f in "$pdir"/"$ym"-*.md; do
      [ -e "$f" ] || continue
      v=$(grep -m1 '^overall_verdict:' "$f" 2>/dev/null | sed 's/^overall_verdict: *//')
      [ -z "$v" ] && continue
      case "$v" in
        PROCEED-WITH-CHANGES) m_pwc=$((m_pwc+1)) ;;
        PROCEED)              m_clean=$((m_clean+1)) ;;
        *)                    m_hold=$((m_hold+1)) ;;
      esac
    done
    echo "PROSPECT_MONTH $ym $m_pwc $m_clean $m_hold"
  done
fi

# --- Retrospect outcome distribution + per-fix-verdict presence ---
rdir="$KF/logs/retrospect"
r_total=0; r_closed=0; r_partial=0; r_mixed=0; r_unres=0; r_vfiles=0
if [ -d "$rdir" ]; then
  for f in "$rdir"/*.md; do
    [ -e "$f" ] || continue
    o=$(grep -m1 '^overall_outcome:' "$f" 2>/dev/null | sed 's/^overall_outcome: *//')
    if [ -n "$o" ]; then
      r_total=$((r_total+1))
      case "$o" in
        closed)     r_closed=$((r_closed+1)) ;;
        partial)    r_partial=$((r_partial+1)) ;;
        mixed)      r_mixed=$((r_mixed+1)) ;;
        unresolved) r_unres=$((r_unres+1)) ;;
      esac
    fi
    if grep -qE '✅|KEEP|REVERT|REVISE' "$f" 2>/dev/null; then
      r_vfiles=$((r_vfiles+1))
    fi
  done
fi
echo "RETRO_TOTAL $r_total"
echo "RETRO_CLOSED $r_closed"
echo "RETRO_PARTIAL $r_partial"
echo "RETRO_MIXED $r_mixed"
echo "RETRO_UNRESOLVED $r_unres"
echo "RETRO_VERDICT_FILES $r_vfiles"

# --- Retrospect month buckets (closed / total) ---
if [ -d "$rdir" ]; then
  for ym in $(ls "$rdir" 2>/dev/null | grep -oE '^[0-9]{4}-[0-9]{2}' | sort -u); do
    m_c=0; m_t=0
    for f in "$rdir"/"$ym"-*.md; do
      [ -e "$f" ] || continue
      o=$(grep -m1 '^overall_outcome:' "$f" 2>/dev/null | sed 's/^overall_outcome: *//')
      [ -z "$o" ] && continue
      m_t=$((m_t+1))
      [ "$o" = "closed" ] && m_c=$((m_c+1))
    done
    echo "RETRO_MONTH $ym $m_c $m_t"
  done
fi

# --- Pattern libraries: every rules/*-patterns.md (headings `## kebab` / `### kebab`, optionally backticked) ---
pat_total=0; pat_lines=""
for pf in "$KF"/rules/*-patterns.md; do
  [ -f "$pf" ] || continue
  n=$(grep -cE '^###? `?[a-z0-9]+(-[a-z0-9]+)+`?$' "$pf" 2>/dev/null)
  n=${n:-0}
  pat_total=$((pat_total+n))
  pat_lines="${pat_lines}PATTERN_LIB $(basename "$pf") $n
"
done
echo "PATTERN_COUNT $pat_total"
printf '%s' "$pat_lines"

# --- Gate yield + model/effort: one awk over every prospect/retrospect log, frontmatter only ---
# Filenames arrive on stdin and the program getlines each file, stopping at the closing
# '---' (so bodies with look-alike lines are never read and there is no ARG_MAX ceiling).
# Counted populations: PROSPECT_YIELD/_MONTH = logs with an overall_verdict AND a
# sourcing_pass key (older logs predate the block; counting them would dilute yield).
# RETRO_BUNDLE/CLAIMS = every retrospect log carrying a sourcing_pass. GATE_MODEL/EFFORT
# = every log in both dirs; a missing field is "absent".
{ [ -d "$pdir" ] && find "$pdir" -name '*.md' -type f; [ -d "$rdir" ] && find "$rdir" -name '*.md' -type f; } 2>/dev/null |
awk -v rdir="$rdir/" '
function trim(x) { sub(/^[ \t]+/, "", x); sub(/[ \t\r]+$/, "", x); return x }
function val(x) { sub(/^[^:]*:/, "", x); sub(/[ \t]+#.*$/, "", x); return trim(x) }
function acc(blk, k, v) {
  v = v + 0
  if (blk == "bundle_marker") {
    if (k == "candidates") bc += v; else if (k == "upgraded_verified") bv += v; else if (k == "upgraded_not_in_bundle") bn += v
  } else if (blk == "outcome") {
    if (k == "candidates") oc += v; else if (k == "upgraded_validated") ov += v; else if (k == "upgraded_partial") op += v; else if (k == "upgraded_invalidated") oi += v
  } else {
    if (k == "candidates") c += v; else if (k == "upgraded_validated") va += v; else if (k == "upgraded_falsified") fa += v
    else if (k == "no_movement") nm += v; else if (k == "no_movement_capability") nc += v; else if (k == "no_movement_structural") ns += v
  }
}
function inline(body,   n, parts, i, kv) {
  sub(/^[^{]*\{/, "", body); sub(/\}.*$/, "", body)
  n = split(body, parts, ",")
  for (i = 1; i <= n; i++) { split(parts[i], kv, ":"); acc("", trim(kv[1]), trim(kv[2])) }
}
{
  f = $0; ym = f; sub(/^.*\//, "", ym); ym = substr(ym, 1, 7)
  isr = (index(f, rdir) == 1)
  c = va = fa = nm = nc = ns = 0; bc = bv = bn = oc = ov = op = oi = 0
  model = ""; effort = ""; verdict = ""; hassp = 0; insp = 0; blk = ""; first = 1; started = 0
  while ((getline line < f) > 0) {
    sub(/\r$/, "", line)
    if (first) { first = 0; if (line != "---") break; started = 1; continue }
    if (line == "---") break
    if (line ~ /^[A-Za-z_]+:/) {
      insp = 0; blk = ""
      if (line ~ /^sourcing_pass:/) { hassp = 1; insp = 1; if (line ~ /\{/) { inline(line); insp = 0 } }
      else if (line ~ /^model:/) model = val(line)
      else if (line ~ /^effort:/) effort = val(line)
      else if (line ~ /^overall_verdict:/) verdict = val(line)
      continue
    }
    if (insp && match(line, /^ +[a-z_]+:/)) {
      ind = RLENGTH - length(trim(substr(line, 1, RLENGTH)))
      key = trim(substr(line, 1, RLENGTH)); sub(/:$/, "", key)
      v = val(line)
      if (ind <= 2) { blk = ""; if (v == "") { blk = key; continue } }
      acc(blk, key, v)
    }
  }
  close(f)
  if (!started) { model = ""; effort = ""; verdict = ""; hassp = 0 }
  sub(/\[1m\]/, "", model); model = trim(model); gsub(/[ \t]+/, "_", model); if (model == "") model = "absent"
  effort = trim(effort); if (effort == "") effort = "absent"
  gm[model]++; ge[effort]++
  if (isr) {
    if (hassp) { rbc += bc; rbv += bv; rbn += bn; roc += oc; rov += ov; rop += op; roi += oi }
  } else if (verdict != "" && hassp) {
    runs++; tc += c; tv += va; tf += fa; tn += nm; tnc += nc; tns += ns
    if (ym ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]$/) { mr[ym]++; mc[ym] += c; mf[ym] += fa; mn[ym] += nm }
  }
}
END {
  print "PROSPECT_YIELD " runs+0, tc+0, tv+0, tf+0, tn+0, tnc+0, tns+0
  for (m in mr) print "PROSPECT_YIELD_MONTH " m, mr[m], mc[m], mf[m], mn[m]
  print "RETRO_BUNDLE " rbc+0, rbv+0, rbn+0
  print "RETRO_CLAIMS " roc+0, rov+0, rop+0, roi+0
  for (m in gm) print "GATE_MODEL " m, gm[m]
  for (e in ge) print "GATE_EFFORT " e, ge[e]
}' | LC_ALL=C sort

# --- Corpus: per-content-dir .md counts (exclude README.md) ---
corpus_total=0
for d in $KT_CONTENT_DIRS; do
  if [ -d "$KF/$d" ]; then
    n=$(find "$KF/$d" -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
  else
    n=0
  fi
  echo "CORPUS_$d $n"
  corpus_total=$((corpus_total+n))
done
echo "CORPUS_TOTAL $corpus_total"

# --- Cost surface: skill-discovery description bytes over the INSTALLED plugin ---
skills_dir="$DIR/../skills"
sd_bytes=0; sk_count=0
if [ -d "$skills_dir" ]; then
  for sf in "$skills_dir"/*/SKILL.md; do
    [ -e "$sf" ] || continue
    b=$(awk '/^description:/{flag=1; print; next} flag && /^[a-z_-]+:/{flag=0} flag {print}' "$sf" | wc -c | tr -d ' ')
    sd_bytes=$((sd_bytes+b)); sk_count=$((sk_count+1))
  done
fi
echo "SKILL_DISCOVERY_BYTES $sd_bytes"
echo "SKILL_COUNT $sk_count"

# --- Fixed cost: always-on bytes every session pays (skill descriptions + rules digests) ---
rd_file="$DIR/../rules/aria-rules.md"
ur_file="${HOME:-}/.claude/rules/aria-user-rules.md"
if [ -f "$rd_file" ]; then
  rd_bytes=$(wc -c < "$rd_file" | tr -d ' ')
  echo "RULES_DIGEST_BYTES $rd_bytes"
else
  rd_bytes=0
  echo "RULES_DIGEST_BYTES unmeasured"
fi
if [ -f "$ur_file" ]; then ur_bytes=$(wc -c < "$ur_file" | tr -d ' '); else ur_bytes=0; fi
echo "USER_RULES_DIGEST_BYTES $ur_bytes"
if [ -f "$rd_file" ]; then
  echo "FIXED_COST_BYTES $((sd_bytes+rd_bytes+ur_bytes))"
else
  echo "FIXED_COST_BYTES $((sd_bytes+rd_bytes+ur_bytes)) partial"
fi

# --- Audit passes: highest "Nth pass" ordinal; fallback to the dated-entry count ---
alog="$KF/logs/knowledge-audit-log.md"
ap=0; ad=0
if [ -f "$alog" ]; then
  ad=$(grep -cE '^- \*\*Date:\*\*' "$alog" 2>/dev/null)
  ad=${ad:-0}
  ap=$(awk '{ s = $0; while (match(s, /[0-9]+(st|nd|rd|th) pass/)) { n = substr(s, RSTART, RLENGTH) + 0; if (n > mx) mx = n; s = substr(s, RSTART + RLENGTH) } } END { print mx + 0 }' "$alog")
  [ "$ap" -gt 0 ] 2>/dev/null || ap=$ad
fi
echo "AUDIT_PASSES $ap"
echo "AUDIT_DATED_ENTRIES $ad"
