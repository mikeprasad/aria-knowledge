# shellcheck shell=sh
# lib-digest-lock.sh — extraction shared by test-aria-rules-digest.sh and relock-rules-digest.sh.
#
# The digest lock (tests/fixtures/aria-rules.digest-lock.tsv) binds each always-on digest line
# in rules/aria-rules.md to the source rule it summarises in template/rules/working-rules.md.
# One line per rule: N<TAB>sha256(source section)<TAB>sha256(digest line).
#
# Dev-only: tests/ is excluded from every built artifact, and this file is not named test-*.sh,
# so run.sh does not execute it as a test.

# sha256 of rule N's section in working-rules.md: from '### N. ' up to the next heading of
# level 1-3 (the '## Process Rules' / '## Meta Rules' group headings sit between rules), or EOF.
kt_dl_source_sha() { # SOURCE_FILE N
  awk -v n="$2" '
    $0 ~ "^### " n "\\. " { f = 1; print; next }
    f && /^#{1,3} / { exit }
    f { print }' "$1" 2>/dev/null | shasum -a 256 | cut -c1-64
}

# sha256 of the digest line for rule N: the single line beginning '- **Rule N — '.
kt_dl_digest_sha() { # DIGEST_FILE N
  grep -E "^- \\*\\*Rule $2 — " "$1" 2>/dev/null | shasum -a 256 | cut -c1-64
}

# sha256 of empty input. An extraction that matched nothing produces this value; it must never
# be written into the lock, or a broken extractor would compare equal forever.
kt_dl_empty_sha() { printf '' | shasum -a 256 | cut -c1-64; }

# Rule numbers in the source, one per line, ascending.
kt_dl_source_nums() { # SOURCE_FILE
  grep '^### [0-9]' "$1" 2>/dev/null | sed 's/^### \([0-9]*\)\..*/\1/' | sort -n
}
