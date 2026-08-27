# Audit verb migration — retire the hyphenated forms from every advertised surface (design)

**Date:** 2026-08-27 · **Status:** GATED — /prospect PROCEED-WITH-CHANGES 2026-08-27, amendment MA1 applied in place (gate log: `knowledge/logs/prospect/2026-08-27-file-audit-verb-migration.md`) · **Target:** plugin-claude-code (canonical)
· **Companion:** `2026-08-27-audit-rules-sub-audit-design.md` (workstream 1 of the same plan; this
is workstream 2 — they share the dispatcher and ship together)

## 1. The directive and the structural bound

User directive (2026-08-27, verbatim): *"lets migrate off /audit-knowledge to fully commit to
/audit knowledge or /audit config over /audit-config so we can retire the - forms fully."*

**The structural bound:** the umbrella `/audit` works by delegating to the sub-skills BY NAME via
the Skill tool, so the skill directories (`audit-knowledge/`, `audit-config/`, `audit-style/`,
`audit-usage/`) cannot be deleted or renamed — they are the delegation targets. "Retire fully"
therefore means: **the space forms become the only advertised forms on every surface** (docs,
descriptions, cadence nudges, cross-references), and the typed hyphen forms survive only as
**unadvertised compat** — exactly the standing posture of the legacy `linear` spellings ("aliases,
not separate behaviour — never advertise them as the canonical form").

## 2. Decision summary

| # | Decision | Basis |
|---|---|---|
| M1 | **Dispatcher argument passthrough:** `/audit <verb> [args…]` delegates to the sub-skill WITH the trailing args (grammar widens from "at most one trailing verb") | prerequisite for retirement — `/audit style recent` and `/audit rules promote R1 R3` are impossible under the no-args convention, which would leave the hyphen forms load-bearing |
| M2 | Sub-skill descriptions **demoted to internal**: one line naming the facet + "invoke via `/audit <verb>`"; their trigger phrases **absorbed into `/audit`'s description** | model routing is description-driven — prose like "run a knowledge audit" must still route, via the umbrella; the v2.33.0 `/intake` consolidation is the absorption precedent |
| M3 | The sweep discriminator is the **leading slash**: `/audit-knowledge` (user-facing) migrates; slashless `audit-knowledge` in "use the Skill tool to invoke…" instructions is the mechanism name and is **kept** | changing the mechanism name breaks delegation; changing only prose breaks nothing |
| M4 | `bin/session-start-check.sh`'s cadence nudge names the **space forms**; any functional matcher keyed on the typed command string is censused before the sweep | the dispatcher's own Back-Compat section currently says the nudge names the hyphen forms directly |
| M5 | `skills/.archived/*` are **excluded** from the sweep | Rule 6 — tombstones are historical record |
| M6 | Legacy description aliases (e.g. "Also invoked as '/config-audit'") are retired from descriptions in the same pass; they keep working as typed compat, undocumented | same posture, one pass, frees Gate B bytes |
| M7 | **Ports:** antigravity + cursor inherit via their build scripts at the next parity pass; codex is hand-sync; **cowork KEEPS its hyphen forms as primary** — it has no `/audit` dispatcher (excluded on the 9,000-char cap arithmetic, a settled won't-fix), so there is nothing to migrate to there | documented divergence, not drift |
| M8 | The companion audit-rules spec's `promote` routing is **amended by this workstream**: re-entry is `/audit rules promote <labels>` through M1's passthrough; the direct form remains unadvertised compat | resolves the contradiction between the two workstreams |
| M9 | Gate B effect is measured, not assumed — expected **net decrease** (four descriptions shrink to one line each; the umbrella grows by the absorbed triggers) | this funds workstream 1's new description; both land in one budget measurement |

## 3. Sweep inventory (censused 2026-08-27, canonical plugin only)

| Form | Files | Occurrences |
|---|---|---|
| `/audit-knowledge` | 33 | 109 |
| `/audit-config` | 8 | 20 |
| `/audit-style` | 3 | 4 |
| `/audit-usage` | 2 | 3 |

Of the 33: 22 live skill bodies, 4 bin scripts (`session-start-check.sh`, `subagent-stop-capture.sh`,
`save-transcript.sh`, `migrate-ideas-backlog.sh`), 7 template files (ship to users via `/setup`
diffs), 3 archived tombstones (excluded per M5). *(Gate amendment MA1:)* **plus
`rules/aria-rules.md:106`** — the bundled always-on digest's MEMORY PATHWAY directive names
`/audit-knowledge`; the first census's directory list (`skills/ bin/ template/`) omitted `rules/`
entirely. The installed copy at `~/.claude/rules/aria-rules.md` self-heals — `session-start-rules.sh`
byte-compares it against the bundled file and re-copies on mismatch. Counts are a snapshot —
**re-census at execution FROM THE REPO ROOT** (the omission above is why; parallel in-flight work
moves counts too), and split every hit by the M3 discriminator before editing.

## 4. Surface-by-surface plan shape

1. **`audit/SKILL.md`** — grammar gains passthrough (M1); the Back-Compat section is rewritten:
   space forms canonical, hyphen forms unadvertised compat, cadence nudges name the space forms.
2. **Four sub-skill descriptions** — demoted per M2; bodies keep their full step logic unchanged.
   Each body gains one line at top: "Canonical invocation: `/audit <verb>`. The direct form is
   retained for compatibility and no longer advertised."
3. **`/audit` description** — absorbs the four trigger vocabularies + workstream 1's (`rules`).
4. **`session-start-check.sh`** — nudge strings flipped; execution first greps for any conditional
   or matcher keyed on the typed hyphen string (M4) — prose changes only, no logic change expected.
5. **20 other live skill bodies + 7 template files** — mechanical prose sweep under the M3
   discriminator. Template edits reach existing users through `/setup`'s normal diff flow.
6. **Docs:** README, QUICKSTART, `/help` table rows (the table gains `/audit <verb>` forms and
   drops the hyphen rows), CHANGELOG entry describing the retirement + compat posture.

## 5. Acceptance criteria

- **MC1:** `/audit style recent` and `/audit rules promote R1` reach their sub-skills with args
  (fixture assertion on the dispatcher grammar text; the passthrough clause names args explicitly).
- **MC2:** zero slash-leading hyphen forms remain in live (non-archived) `skills/`, `bin/`,
  `template/` — grep with the M5 exclusion, with a positive control on the archived copies.
- **MC3:** slashless Skill-tool delegation references are byte-unchanged (count before == after).
- **MC4:** Gate B total measured before/after; the CHANGELOG records both numbers.
- **MC5:** the umbrella description carries every absorbed trigger phrase (grep per phrase).
- **MC6:** cowork tree untouched by this workstream (git diff scope assertion).

## 6. Non-goals

Deleting or renaming sub-skill directories (structural bound, §1) · breaking typed hyphen
invocations (compat is kept, silently) · porting in this release (M7) · sweeping the user's own
knowledge folder or workspace docs (the compat path keeps them working; a local sweep is the
user's separate call).
