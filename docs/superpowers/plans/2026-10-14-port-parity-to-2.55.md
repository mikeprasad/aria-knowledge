# Port parity to canonical 2.55.x + site refresh — plan (2026-10-14)

Mike: "review all the ports, cowork, antigravity, etc, and update them to be parity with
the claude code version, then update the website."

## Measured state (this session)

| Port | Version | Last parity target | Measured drift vs canonical HEAD |
|---|---|---|---|
| claude-code (canonical) | 2.55.0 released; HEAD = 2.55.0 + 2 unpushed `/snapshot` commits (`ceaf819`, `cac7721`, Claude-Code-only) | — | — |
| antigravity | 2.55.0 | 2.55.0 | `build.sh` regenerates with **zero diff** — at parity |
| cursor | `2.53.1-cursor.0` (ledger says 2.52.8) | 2.52.8 | generator moves 1 file (`aria-rule-22.mdc`); hand-mirrored `knowledge/` 9 files stale since v2.46.2 (incl. Rule 23 text in working-rules, README tree, index.md missing); `scripts/aria` portable scripts unchecked |
| codex | `2.46.5-codex.0` | 2.46.4 | 1,300 lines of canonical skill/template change since v2.46.4; `audit-rules` skill missing; portable `bin/` scripts (lib-session-state +653, config.sh +329, …) |
| cowork | 1.7.0 | 2.46.4 | ~600 lines of canonical delta across 22 skills; template (working-rules Rule 23, change-decision-framework) |
| site | badge v2.51.0 | — | latest release v2.55.0; port lists omit Antigravity in 3 places |

## Method — 3-way merge, never overwrite

Ports carry deliberate adaptations (no ADR-094 gates in codex/cursor; cowork bodies diverge by
design, ADR-014). A copy-over would erase them. Per file:
`git merge-file <port-file> <canonical@base> <canonical@HEAD>` where base = the canonical version
the port was last synced to. Clean hunks land mechanically; conflicts are resolved by hand,
keeping the port's adaptation and taking canonical's new substance.

Canonical-side content that is **Claude-Code-only** (transcript-reading Rule 22 hook mechanics,
Bash-heredoc carriers, statusline, launchd, `${CLAUDE_SESSION_ID}`) is NOT ported into a runtime
that has no such surface — each such hunk is dropped or reworded, and listed in that port's notes.

## Units

- **U1 Antigravity** — verified at parity; no change. Ledger re-stamp only if canonical version moves.
- **U2 Cursor** — accept generator output; 3-way merge `knowledge/` (base v2.46.2 template);
  check portable `scripts/aria` deltas (lib-session-state functions the skills now call);
  bump `scripts/aria/VERSION`; PORTING notes; `./release-cursor.sh`.
- **U3 Codex** — 3-way merge all skills (base v2.46.4) with gate+frontmatter preserved; add
  `audit-rules`; template sync; portable `bin/` 3-way merge (lib-session-state, config,
  session-start-check backlog count, etc.) without re-adding the three deleted `post-*` scripts;
  `tests/run.sh` green; version bump; PORTING notes; `./release-codex.sh`.
- **U4 Cowork** — 3-way merge 22 skills (base v2.46.4), template sync; decide on new portable
  skills (audit-rules) against the 9000-char description cap; version 1.8.0; `release.sh` cap gate.
- **U5 Ledger + docs** — `check-port-drift.sh --update` per port; CLAUDE.md port sections.
- **U6 Release** — needs Mike's grant (public repo push + GH release + 6 stable aliases).
- **U7 Site** — badge to the newest *released* tag (never plugin.json); add Antigravity to the
  three port lists; catalog count vs `ls plugin-claude-code/skills` (37); promote; deploy needs grant.

## Success criteria (declared before running)

1. `./plugin-antigravity/build.sh` → zero diff. 2. Cursor generator idempotent (second run zero
diff). 3. `plugin-openai-codex/tests/run.sh` exit 0. 4. Every skill a port ships calls only
`kt_ss_*` / helper functions that exist in that port's `bin/` (grep census, positive control).
5. Zero leftover conflict markers (`grep -rn '^<<<<<<<\|^>>>>>>>'` = 0). 6. Zero ADR-094 gate
text in codex/cursor. 7. cowork summed description chars < 9000 (release.sh gate). 8. All three
release scripts + cowork release.sh exit 0, incl. public-hygiene gate. 9. Site badge equals
`gh release list` newest tag after release.
