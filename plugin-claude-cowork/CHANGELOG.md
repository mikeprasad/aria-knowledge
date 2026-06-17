# Changelog

All notable changes to aria-cowork are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/); aria-cowork uses [Semantic Versioning](https://semver.org/) per [ADR-006](https://github.com/mikeprasad/knowledge/projects/aria-cowork/decisions/006-versioning-independence.md).

Cross-plugin parity callouts (per ADR-006) note when changes coordinate with aria-knowledge releases.

## [1.4.0] — 2026-06-18

**Port `/interview` to Cowork (parity with aria-knowledge v2.31.0).** The 3-mode knowledge-elicitation skill — `project` (scope a new build), `knowledge` (get a topic into the KB), `deep-dive` (extract the rationale behind an existing system; requires a basis) — now ships in Cowork as `/aria-cowork:interview`. This closes the one genuine parity gap with canonical v2.31.0; ADR-094 had documented the Cowork variant as a deferred follow-on.

- **Add: `/aria-cowork:interview <project|knowledge|deep-dive> [topic] [--ground=...]`** — interviews the user to elicit knowledge through dialogue, then stages it to `intake/projects/` or `intake/interviews/` for **manual review** (never auto-promoted). In-session cadence choice (socratic one-at-a-time vs research-then-batch). The skill body — modes, cadence logic, deep-dive basis-gate, question banks, and output templates — is **byte-identical** to the canonical Code skill per ADR-013; only three surfaces diverge.
- **Cowork adaptations (the three diverging surfaces):** (1) cowork-side Runtime Gate — bare `/interview` resolves to aria-knowledge per ADR-094; this variant is `/aria-cowork:interview`; (2) **no Bash** — Step 0 reads `~/.claude/aria-knowledge.local.md` directly via the `Read` tool and falls back to asking the user to paste their knowledge-folder path when the runtime can't reach it; (3) `allowed-tools` drops `Bash`. Grounding ingestion uses Read/Glob/Grep/WebFetch (all available in Cowork).
- **Coordinated description trim (cap-relief).** Adding `/interview` pushed the summed SKILL.md description chars over the 9000 install-fail cap. Trimmed `/interview`'s own description to a tight routing signal and fixed three pre-existing **dangling/truncated** description clauses left mid-sentence by v1.3.0's trim pass (`clip-thread`, `digest`, `meeting-notes`). `release.sh` aggregate-description preflight: **summed = 8864 chars** (under the 9000 cap). Skill manifest: 26 → **27 distinct** (v1.3.0 had already removed the 2 aliases).
- **Out of scope (not gaps):** ADR-005's permanent exclusions — `/codemap`, `/stitch`, `/distill`, `/audit-share` — remain Code-only by design, each with a documented revisit-condition.
- **Parity:** coordinates with aria-knowledge v2.31.0. Claude-Cowork port only.

## [1.3.0] — 2026-06-11

**Two new review skills — `/aria-cowork:foundational-review` + `/aria-cowork:readiness-audit`** — porting aria-knowledge v2.29.0's foundational review chain to Cowork. Parity catch-up with aria-knowledge through v2.30.0 (whose other changes — the Rule 22 deny-rate circuit breaker, canonical `release.sh` gates, and the port-parity ledger — are hooks + Code-side release tooling that don't apply to skills-only Cowork).

- **Add: `/aria-cowork:foundational-review <scope-root> [--decision "..."] [--extend]`** — verdict-led foundational review before an irreversible decision (verdict + premises + sections A–F + irreversibility inventory → design spec → cold-executable plan → composed `/aria-cowork:prospect` → kickoff). Requires a named irreversible decision (else redirects to `/aria-cowork:prospect` or `/aria-cowork:readiness-audit`). **Cowork-adapted:** conversational, no parallel subagents and no Bash — reads via file tools and asks the user to paste anything it can't reach; no `git` (describes the commit instead).
- **Add: `/aria-cowork:readiness-audit <scope-root> [--for "<event>"]`** — the recurring surface-audit sibling: sequential per-surface probes → re-verify every load-bearing claim (the reviewer is both explorer and controller in Cowork) → tiered evidence-celled findings (Tier 0/High/Med/Low) → phased remediation (findings are not a shipping list) → verification recipe. Read-only; no decision anchor required.
- **Bundles** the genericized canonical process doc at `skills/foundational-review/foundational-review-chain.md` (read via `${CLAUDE_PLUGIN_ROOT}`, preferring a user's richer `<knowledge_root>/approaches/` copy when reachable).
- **Remove: the 2 alias skills `/aria-cowork:knowledge-audit` + `/aria-cowork:config-audit`** (pure aliases of `/audit-knowledge` / `/audit-config`). The alias slash-forms still route — they're named in the canonical skills' trigger lists — but no longer cost a separate skill dir against the description cap. This is the cap-relief pass that also made room for the two new review skills.
- **Coordinated description trim (the 9000-char cap pass flagged at v2.29.0):** trimmed the descriptions of `/handoff`, `/wrapup`, `/intake`, `/prospect`, `/retrospect`, and `/audit-knowledge` to tight routing signals (behaviors unchanged — the detail lives in each skill body) and tidied three dangling/truncated trigger phrases. With the 2 alias removals, summed descriptions land at **8489 chars** (under the 8500 warn). Skill manifest: 26 → 26 (was 24 distinct + 2 aliases; now 26 distinct + 0 aliases — added 2 review skills, removed 2 aliases).
- **Fix:** `release.sh` now removes the `.plugin` before zipping (clean rebuild, not append) so removed skills can't persist in the artifact; expected-skills smoke list updated.
- **Parity:** coordinated with aria-knowledge v2.30.0 (which removed its 3 audit aliases in the same pass). Claude-Cowork port only.

## [1.2.0] — 2026-06-10

**Minor release — `snap` mode for `/wrapup` + `/handoff` (parity with aria-knowledge v2.28.0).** A new mode that runs the full silent close-out/handoff (summary, PROGRESS, CLAUDE.md, memory, commit message — plus the next-session opener for `/handoff`) but archives the conversation via `/aria-cowork:snapshot` for later extraction **instead of** running `/aria-cowork:extract` now. Use when context is high: `/extract` is the expensive, compaction-risky step, so snap preserves the conversation and defers knowledge synthesis to a later session (or the next `/aria-cowork:audit-knowledge` digest pass, which reads `intake/pre-compact-captures/`). Definitionally minimal: **`snap` ≡ `auto` + one swap** (`/extract` → `/snapshot`). New mode parallels the v1.1.0 `auto`-mode addition (minor bump).

### Added — `snap` mode

- **`/aria-cowork:wrapup snap`** — third mode (peer to default + `auto`). Parses in Step 0; every per-step auto-conditional now reads `If mode = auto (or snap)`; Step 8 (renamed "Capture session knowledge") branches snap→`/aria-cowork:snapshot`, auto→`/aria-cowork:extract`. Runtime gate, checklist, report, and Rules updated.
- **`/aria-cowork:handoff snap`** — fourth mode (peer to default + `auto` + `brief`). Parses in Step 0; Step 4 review + Step 5 apply include snap; Step 6 (renamed "Capture Session Knowledge") branches snap→`/aria-cowork:snapshot`. Next-session opener still emitted (snap is NOT brief — it produces the full package + opener + commit message).
- **`/help`** table advertises `/wrapup [auto|snap]` and `/handoff [auto|brief|snap]`.

### Cowork adaptation notes

- **No Bash dependency** — unlike aria-knowledge's snap (which leans on `save-transcript.sh`), cowork's `/snapshot` uses 3-path source acquisition (transcript MCP → user-paste → Claude-recall), so snap works in cowork's no-shell runtime. The canonical "snap especially needs Bash" gate note is intentionally omitted here.
- **Invariant preserved** — snap defers, never drops, capture: the snapshot always runs (no skip path, same as auto's "extract always runs" rule). snap is otherwise byte-for-byte auto behavior (silent, commit-message-only — never runs git).
- **Fix (in-scope):** `/handoff` Step 7 checklist had duplicated canonical Git/extract rows (a stale copy-paste artifact the explanatory note claimed were "replaced"); collapsed to the cowork-correct rows.
- **Description budget:** summed SKILL.md descriptions at 8460 chars (well under the 9000 target / 9233 fail-point); `release.sh` aggregate-description preflight gates the build.

### Not ported (tracked-drift)

- aria-knowledge's `/handoff` model-recommendation rubric (the `Suggested next session:` line + Fable-5 tier prose, canonical v2.27.x) — cowork's `/handoff` never carried the rubric, and porting it raises Cowork-specific model/effort-selection UX questions. Flagged for a future parity pass; out of scope for the snap addition.

## [1.1.5] — 2026-06-04

**Patch release — skill-logic parity catch-up with aria-knowledge.** Two pure skill-content fixes ported from the canonical Code port; no schema, MCP, or manifest-shape changes. Hook/Bash/CLI-dependent canonical features since v1.1.4 (subagent capture, SESSION.md producer, auto-prospect/retrospect, the `/statusline` meter) are **not** ported — Cowork is skills-only with no hooks API and no CLI status line.

### Added — `/aria-cowork:index` Step 4 ephemeral-tag exclusion (parity with aria-knowledge v2.22.3)

- Step 4 now drops ephemeral candidates before applying the freeform-promotion threshold: session stamps (`^s\d+$`), work-item ids (`^p-?\d+$`), phase stamps (`^phase-?\d+$`), plan ids (`^plan-\d+[a-z]?$`), plus a literal denylist (`future-session-plan`, `soft-launch`). Session/phase/plan stamps recur across many files (so they hit the threshold) but are not durable concepts and were surfacing as promotion noise.
- Suppresses AUTO-promotion only — not a hard ban (hand-add still works; a Known tag never re-enters the freeform pool). The skipped set is surfaced (not silent) so a false-positive can be rescued.

### Fixed — `/aria-cowork:wrapup` description no longer trips the skill picker (parity with aria-knowledge v2.21.0)

- The `/aria-cowork:wrapup` description named `"/aria-cowork:handoff"` as the alternative, so the picker (which matches on description) surfaced `/wrapup` when the user typed `/aria-cowork:handoff`. Reworded to keep the "not for passoff" anti-trigger without naming the skill.

### Coordinated release pairing

- Parity with **aria-knowledge v2.21.0** (`/wrapup` picker) and **v2.22.3** (`/index` ephemeral exclusion). The v2.24.1 `/statusline` refinements that prompted this sync pass are Code-only and have no Cowork surface.

## [1.1.4] — 2026-05-29

**Patch release — Opus 4.8 readiness, coordinated with aria-knowledge v2.20.3.** `template/rules/working-rules.md` `Why`-clause model references de-versioned (a bare family name denotes the latest model, so the rule text never goes stale on a model release), mirroring plugin-claude-code. Cowork is skills-only, so aria-knowledge v2.20.3's hook-hardening changes do not apply here. No new skills, no schema changes, no MCP changes. (Backfilled 2026-06-04 — the version shipped in `plugin.json` ahead of this entry.)

## [1.1.3] — 2026-05-25

**Patch release — wrapup/handoff spec fixes coordinated with aria-knowledge v2.20.2.** No new skills, no schema changes, no MCP changes. Two latent bugs in `/aria-cowork:wrapup` + `/aria-cowork:handoff` skill bodies — latent since v1.1.0 (2026-05-19) intent split.

### Fixed — `/aria-cowork:wrapup` closing report uses correct heading + checklist

Mirror of aria-knowledge v2.20.2 Bug 1 fix. Cowork wrapup's Step 7 + Step 9 carried "Handoff" labels from pre-v1.1.0 when `/wrapup` was the only end-of-session skill. Result: every `/aria-cowork:wrapup auto` since v1.1.0 emitted `## Handoff Checklist` and `## Session Handoff Complete` — confusing labels.

Fixed:
- `## Step 7: Verify handoff readiness` → `## Step 7: Verify wrapup readiness`
- `## Handoff Checklist` → `## Wrapup Checklist`
- `## Session Handoff Complete` → `## Session Wrapup Complete`
- Clarifying paragraph below Step 9 contrasting `/aria-cowork:wrapup` vs `/aria-cowork:handoff` closing-report headings explicitly

### Fixed — `/aria-cowork:extract` always runs under auto mode (no judgment-skip)

Mirror of aria-knowledge v2.20.2 Bug 2 fix. Cowork `/aria-cowork:wrapup` Step 8 + `/aria-cowork:handoff` Step 6 used procedural "invoke without prompting" language that permitted models to rationalize skipping `/aria-cowork:extract` based on session-content judgment ("session was short, nothing new"). Result: across multiple recent auto-mode sessions, `/extract` was occasionally skipped — losing session knowledge irrecoverably.

Fixed with imperative + anti-rationalization phrasing:
- Wrapup Step 8 auto-mode now reads: `ALWAYS invoke the /aria-cowork:extract skill. No judgment-skip allowed...` Plus explicit "extract always runs" rule + post-yes auto-run rule for gated mode.
- Handoff Step 6 rewritten with the same `ALWAYS invoke` + anti-rationalization clause. Brief-mode carveout note preserved (brief mode never reaches Step 6).

### Auto-mode invariants — shared design pattern

ADR-094 §Part 3 (v1.1.1) established one auto-mode invariant: runtime-mismatch gate always prompts under auto. v1.1.3 ships the inverse: `/aria-cowork:extract` under auto always runs (no judgment-skip). Both are instances of **auto-mode invariants** — surfaces where auto's default behavior is overridden in a specific direction to protect a load-bearing semantic. See aria-knowledge v2.20.2 CHANGELOG for the pattern description.

### Coordinated release pairing

- **aria-knowledge v2.20.2** (released 2026-05-25 same day) — companion release; same two bugs fixed on the canonical Code side. See aria-knowledge CHANGELOG v2.20.2 entry for the full design.

## [1.1.2] — 2026-05-25

**Patch release — bare-slash gate UX revision (ADR-094 §Part 1/2/3 revision).** Coordinated with aria-knowledge v2.20.1. No new skills, no schema changes, no MCP changes. The 24 colliding dual-port skill bodies + descriptions are refreshed per the 2026-05-24 ADR-094 revision. First aria-cowork patch shipped from the consolidated `mikeprasad/aria-knowledge` monorepo (v2.20.0 consolidation absorbed the previously standalone `mikeprasad/aria-cowork` repo).

### Changed — description format (Strategy 1 trailing parenthetical)

Mid-description "Cowork variant —" framing is removed (where present); each colliding skill description ends with a short trailing parenthetical:

```
(Cowork variant — namespaced-only.)         # non-alias skills
(Cowork alias — namespaced-only.)            # config-audit, knowledge-audit
```

This restores the ADR-094 §Part 1 spec language (`namespaced-only` clause) that v1.1.1's implementation didn't carry on cowork descriptions (0/24 conformance pre-fix). UI truncation in plugin browsers now shows skill purpose first; port-identifier remains available for model-side description routing.

**Short form (vs Code-side's verbose form):** aria-cowork's release.sh enforces a 9000-char hard cap on summed SKILL.md description chars (empirical install-fail at 9233, documented v0.2.1 + v1.0.0). The verbose form used on the Code side `(Claude Code variant — bare-slash canonical when both ports loaded; see ADR-094.)` would push cowork's summed chars to ~10335 (over cap). The short form keeps cowork at ~8895 chars (under cap). The verbose ADR-094 reference + explicit "Do NOT match bare /X" anti-trigger live in each skill's Runtime Gate body preamble where no cap applies.

### Changed — Runtime Gate question inverted + Skill-tool auto-redirect on yes

Each colliding skill's `## Runtime Gate (per ADR-094)` body section is rewritten:

1. **Canonical resolution preamble** — opens with `**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. ...` paragraph re-stating cross-port routing, including the explicit `Do NOT match bare /X` anti-trigger.
2. **Question inverted** — `Proceed with the aria-cowork variant anyway? (y/n)` → `**Use /X instead?** (y/n)` (where `/X` is the bare-slash aria-knowledge canonical).
3. **Skill-tool auto-redirect on yes** — on `y`, the skill uses Claude's `Skill` tool to invoke the bare-slash canonical (which routes to aria-knowledge per ADR-094 §Part 1) with the same arguments. Auto-redirect runs the correct skill to completion; aria-cowork skill exits without executing.

The `n` path preserves the opt-in-anyway escape.

### Auto-mode behavior unchanged (§Part 3)

ADR-094 §Part 3's "auto-mode is NOT exempt from the runtime gate" rule is preserved — even under `auto`, the runtime-mismatch gate requires explicit confirmation. New friction profile: `y` triggers auto-redirect (zero-friction), `n` triggers wrong-port-anyway (degraded behavior the user explicitly opted into).

### Coverage (cowork-side)

- 24 SKILL.md files changed (24 dual-port skills including 2 alias pairs).
- 22/22 canonical-resolution preambles (22 non-alias × 1 port).
- 22/22 inverted-question gates.
- 22/22 Skill-tool auto-redirect mentions.
- 24/24 trailing parentheticals.

### Coordinated release pairing

- **aria-knowledge v2.20.1** (released 2026-05-25) — companion release; shares the same 48-file rewrite arc (24 dual-port skills × 2 ports) + ADR-094 Revision history + Validated By entries. See aria-knowledge CHANGELOG v2.20.1 for the full design rationale.

### Empirical unknown

Whether a SKILL.md body's instruction to use the `Skill` tool to invoke another port's skill chains cleanly at runtime is not documented by Anthropic. If host plugin-loaders don't honor in-skill Skill-tool invocation across plugin boundaries, the auto-redirect on `y` silently fails to chain — gate still works as a notification (user types the bare-slash form). Risk is contained: worst case is a revert to the original "proceed anyway" UX.

## [1.1.1] — 2026-05-23

**Patch release — bare-slash namespace ownership + dual runtime gate (ADR-094).** Coordinated with aria-knowledge v2.19.1. No new skills, no schema changes. 24 colliding skill names between aria-knowledge and aria-cowork now have deterministic routing when both plugins are loaded in the same session (most common in Claude Desktop).

### Changed — bare-slash routing now relies on aria-knowledge's canonical-owner claim

When both plugins are loaded, bare slash commands (`/handoff`, `/wrapup`, `/extract`, etc.) deterministically resolve to **aria-knowledge** as canonical owner per [ADR-094](https://github.com/mikeprasad/knowledge/blob/main/projects/aria/decisions/094-bare-slash-canonical-owner-and-dual-runtime-gate.md). The routing is driven by aria-knowledge's "Bare-slash canonical (Claude Code)" claim in its skill descriptions (the strong signal for the model's resolver). aria-cowork's 24 colliding skills:

- Have bare-slash trigger forms (e.g., `"/handoff"`) removed from their trigger lists — only namespaced (`"/aria-cowork:handoff"`) and natural-language triggers remain.
- Carry a new `## Runtime Gate (per ADR-094)` section in the **body** that fires when Bash IS available (i.e., when invoked from Claude Code) — surfaces a notification suggesting the Code-canonical invocation. Gate is informational, not blocking; user can proceed.
- **Gate applies even in `auto` modes** — auto's "implicit-yes" rule is suspended for the runtime-mismatch gate per ADR-094 §Part 3.

Description-level prepends were NOT added to cowork skills (aggregate-bytes cap on cowork is 9,000 chars and would have been exceeded). The architectural simplification is intentional: aria-knowledge owns bare-slash routing via its strong canonical claim; cowork doesn't need to actively disclaim, only document the gate in its body.

### User-visible change

If you use aria-cowork without aria-knowledge installed (Cowork-only setup), bare `/handoff`, `/wrapup`, etc. will no longer auto-invoke. Use the namespaced form (`/aria-cowork:handoff`, `/aria-cowork:wrapup`, etc.) instead. Natural-language triggers (e.g., "hand it off", "wrap up") still work.

### Compatibility

- **No breaking changes for namespaced invocations.** `/aria-cowork:*` calls work everywhere unchanged.
- **No new dependencies.** No MCP changes.
- **Bidirectional skills (clip-thread, extract-doc, meeting-notes, digest, sync-decisions) — same edits apply.** Cowork remains the runtime-natural variant for these (the canonical-owner clause documents this).

### Aggregate-bytes status

Description prepends increase aggregate frontmatter bytes. Pre-flight check via release.sh validates we remain under the 9,000-char internal hard-fail.

## [1.1.0] — 2026-05-19

**Minor release — `/wrapup` vs `/handoff` intent split clarified; `/wrapup auto` mode added.** No new skills, no schema changes, no MCP changes. Two existing skills (`/wrapup`, `/handoff`) get a behavioral and documentation refactor that makes their distinct purposes unambiguous, plus `/wrapup` gains an `auto` mode mirroring `/handoff auto`.

### Changed — `/wrapup` and `/handoff` skill descriptions reframed by intent

Previously the two skills overlapped: both covered "end-of-session" with `/handoff` framed as "/wrapup + opener." Users couldn't tell from the descriptions which to use. The refactor splits them by **audience**, not posture:

- **`/wrapup`** is now the "I'm done, no passoff" skill — close out cleanly, no next-session opener emitted.
- **`/handoff`** is now the "passoff package" skill — for future-you in a new session (typically when context is high) or a coworker (via `brief` mode). Headline artifact is the paste-ready next-session opener (or coworker prose brief in `brief` mode).

Same surfaces touched (PROGRESS / CLAUDE / memory / commit message / `/aria-cowork:extract`); different framing and different headline output. Descriptions trimmed to fit the v1.0.1 Cowork aggregate-bytes cap (per [ADR-013 axis 4](../../knowledge/projects/aria-cowork/decisions/013-cowork-modified-skills-schema-identical-outputs.md)) — aggregate now 8,145 chars (12% headroom under the 9,000 internal hard-fail).

### Added — `/wrapup auto` mode

Mirrors `/handoff auto`: implicit-yes on all per-step gates (session summary, PROGRESS, CLAUDE.md, memory, `/aria-cowork:extract`), runs silently, emits final report only. The commit-message step remains informational in both modes (Cowork has no shell access to run git — Q-4 Option B unchanged). Invoke as `/wrapup auto` or `/aria-cowork:wrapup auto`. Use when the session is short and unambiguous, or when a combined-go signal (`yes to all`) has already been given.

`argument-hint` extended to `'[auto]'`.

### Compatibility

- **No breaking changes.** Existing `/wrapup` invocations (no arg) continue to behave exactly as before — gated, per-step prompts. `auto` is opt-in via the explicit argument.
- **No new dependencies.**
- **`/handoff brief` mode unchanged** (shipped in v0.3.0). Schema-identical to aria-knowledge.

### Coordinated release pairing

- **aria-knowledge v2.19.0** ships the same intent split + `/wrapup auto` mode Code-side. Per ADR-013, aria-knowledge remains the schema source-of-truth; cowork-side description bodies diverge (much shorter) to satisfy Cowork's aggregate-bytes cap, but the behavior split and mode shape are byte-aligned.

## [1.0.1] — 2026-05-19

**Patch release — install-fix for two undocumented Cowork validator constraints.** v1.0.0 (2026-05-18) was tagged + released but its `.plugin` asset silently failed Cowork's server-side upload validator (generic "Plugin validation failed." dialog with no field-level detail). v1.0.1 ships the same skill manifest, schema, ADR set, and architectural commitments as v1.0.0 with two bug fixes that make the artifact actually installable. See the v1.0.0 entry below for the full bisection narrative (Probes A-K, ~2.5 hours).

### Fixed — `.mcp.json` `google_docs` → `google docs`

Cowork's directory-entry name for the Google Docs MCP uses a space, not an underscore. Servers with empty `url` must match a directory entry name exactly to validate; the underscore form silently failed Cowork's server-side validator. Same fix applied to aria-knowledge v2.18.1 sibling for parity per ADR-013. Prose mentions of `google_docs` across README + 4 SKILL.md files (frontmatter enum docs in `extract-doc`, `digest`, `sync-decisions`, `meeting-notes`) swept to `google docs` for consistency with the new manifest key.

### Fixed — SKILL.md description sanitization for Cowork aggregate-bytes cap

Cowork's validator enforces an aggregate cap of ~9 KiB on the summed `description` fields across all `skills/*/SKILL.md`. v1.0.0's 6 new MCP-consuming skills tipped the aggregate from v0.3.0's 7,645 chars to 10,404 chars, tripping the cap. Empirical bisection (Probes A-K) narrowed the cap to [9,151, 9,233]; working answer is 9,216 (9 KiB). All 26 skill descriptions trimmed at the 350-char per-skill ceiling, bringing total to 7,876 chars. Per-skill descriptions remain semantically intact (trigger phrases preserved); only verbose tails were clipped. **This is a new fourth axis of cowork-side allowed divergence from aria-knowledge per the [ADR-013](../../knowledge/projects/aria-cowork/decisions/013-cowork-modified-skills-schema-identical-outputs.md) amendment** — manifest-level, not per-skill body.

### Added — `release.sh` aggregate-description preflight

`release.sh` now sums skill descriptions at build time and warns at >8,500 / hard-fails at >9,000, preventing recurrence. Thresholds match the ≤9,000 safety recommendation in [`~/Projects/knowledge/guides/claude/cowork-plugin-validation.md`](../../knowledge/guides/claude/cowork-plugin-validation.md) "Key Constraint 2".

### Build artifact

`aria-cowork-1.0.1.plugin` — installs cleanly via Cowork drag-and-drop or Settings → Plugins → Install from file. v1.0.0 asset on GitHub (`aria-cowork-1.0.0.plugin`) retained for historical record but does not install; users should fetch v1.0.1 instead.

### Compatibility

- **No breaking changes vs v1.0.0** — same skill manifest (26 skills), same schema, same ADR set, same MCP declarations. Only install-blocking bugs are fixed.
- **No new dependencies.**
- **Existing v1.0.0 installs**: if you somehow have v1.0.0 installed (shouldn't be possible given the validator rejection, but if you sideloaded), reinstall v1.0.1 to pick up the description sanitization and the corrected MCP server name.

### Coordinated release pairing

- **aria-knowledge v2.18.1** (released 2026-05-19) — companion patch. Mirrors the `.mcp.json` `google docs` fix and prose sweep; no description sanitization needed Code-side.

## [1.0.0] — 2026-05-18

**First MCP-consuming release + v1.0 stable-contract claim.** aria-cowork gains the cross-tool synthesis surface that's been deferred since v0.2.0 AND simultaneously claims v1.0 maturity per ADR-006. Originally planned + built as v0.4.0; bumped to v1.0.0 mid-build (2026-05-19) per Mike's directive: the 4 v1.0 triggers I previously named (Cowork-native skills landed / MCP integrations stable / Phase 1 public release / one full audit cycle) are now 2-of-4 done via this release, and the capability-shipping triggers are the load-bearing ones — the Phase 1 public release + audit-cycle triggers are downstream ceremony rather than capability shifts. 6 new Cowork-native skills land: 5 bidirectional skills (clip-thread, extract-doc, meeting-notes, digest, sync-decisions) port byte-faithfully from aria-knowledge v2.18.0 per ADR-014 schema-source-of-truth; 1 cowork-only skill (daily-audit) replaces aria-knowledge's SessionStart hook since Cowork has no hook surface per ADR-004. Skill manifest grows 20 → 26 (24 distinct + 2 aliases). Coordinated release pair with aria-knowledge v2.18.0 — same coordination shape as v2.17.0 ↔ v0.3.0 last week.

### v1.0 stability claim — what this commits to

Per ADR-006 + ADR-011, the v0.x → v1.0 jump signals the public contract is locked. Specifically, v1.0+ commits to:

- **Skill manifest shape:** the 26 v1.0.0 skills are the durable surface area. Future additions are additive minors (v1.1.0+); breaking removals require major bumps (v2.0.0+).
- **Knowledge folder schema:** all `intake/*-backlog.md`, `intake/ideas/*.md`, `intake/docs/`, `intake/clippings/`, `intake/meetings/`, `intake/digests/`, `decisions/`, `approaches/`, `references/`, `rules/`, `logs/{prospect,retrospect,sync-decisions}.md` paths and frontmatter shapes are stable for the v1 line.
- **Cross-plugin schema parity with aria-knowledge:** the ADR-013 byte-faithful output-schema rule continues to apply; aria-knowledge remains the schema source-of-truth per ADR-014.
- **CC BY-NC-SA 4.0 license posture** unchanged from the v0.x line.
- **.mcp.json declaration shape:** 12 MCPs across 4 categories (chat / email / project tracker / docs). Adding MCPs is additive; removing or changing the 4-category structure requires a major bump.

The v1.0 claim does NOT yet commit to a public GitHub repo — Phase 1 public release ceremony (git init + push to `mikeprasad/aria-cowork` + `gh release create v1.0.0`) is scheduled separately per γ ("Yes but later in this session"). The plugin ships as a local `.plugin` zip at v1.0.0; public-repo posture is a follow-on decision.

### Added — `/clip-thread` skill (bidirectional import from aria-knowledge v2.18.0)

New skill at `skills/clip-thread/SKILL.md` (~165 lines). Captures a chat or email thread from a connected `~~chat` (slack, ms365) or `~~email` (gmail, ms365) MCP into `intake/clippings/{YYYY-MM-DD}-{slug}.md`. Source-type detection by URL pattern. 50-message cap. Reaction section left empty as user-fill slot. Byte-faithful import per ADR-013 — only Step 0 (config resolution path) + frontmatter shape + skill-name phrasing diverge from aria-knowledge equivalent.

### Added — `/extract-doc` skill (bidirectional import from aria-knowledge v2.18.0)

New skill at `skills/extract-doc/SKILL.md` (~155 lines). Decomposes a single Notion / Confluence / Google Doc / Box / Egnyte page (via `~~docs` MCP) into N intake-backlog entries for audit routing. Differs from `/intake doc` (v0.3.0) which captures one doc as one structured artifact. 5 standard intake categories. 20KB extraction cap. Byte-faithful import per ADR-013.

### Added — `/meeting-notes` skill (bidirectional import from aria-knowledge v2.18.0)

New skill at `skills/meeting-notes/SKILL.md` (~180 lines). Folds a meeting transcript into `intake/meetings/{YYYY-MM-DD}-{slug}.md` with structured participants / topics / action items / decisions / open questions + raw transcript preserved verbatim. **Unique among MCP-consuming skills:** paste fallback when no `~~docs` MCP connected (Granola exports, hand-typed notes). The one Phase 2 skill that doesn't hard-stop on missing MCP. New `intake/meetings/` lazy-created subfolder. Byte-faithful import per ADR-013.

### Added — `/digest` skill (bidirectional import from aria-knowledge v2.18.0)

New skill at `skills/digest/SKILL.md` (~195 lines). Cross-tool rollup synthesizing what's pending / shipped / blocked across `~~chat` + `~~email` + `~~project tracker` + `~~docs`. Composite-MCP probe — gathers from whichever subset is connected; surfaces gap callouts for disconnected categories. Time window args (`--week` default, `--month`, `--quarter`, `--since`). New `intake/digests/` lazy-created subfolder. Byte-faithful import per ADR-013.

### Added — `/sync-decisions` skill (bidirectional import from aria-knowledge v2.18.0)

New skill at `skills/sync-decisions/SKILL.md` (~215 lines). **First WRITE-side skill in either ARIA plugin.** Mirrors approved decisions from `decisions/` out to a `~~docs` MCP destination (Notion / Confluence / Google Doc / Box / Egnyte). Embeds the 4-step Rule 22 advisory preamble per [ADR-016](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/016-rule-22-advisory-preamble-for-external-writes.md) with explicit per-decision go-gate (`Ready to write? (yes / no / edit)`). Only path to batch is the literal phrase `yes to all`. Logs every sync to `logs/sync-decisions.md`. Adds new `synced_to_~~docs:` frontmatter field on synced decision files. Byte-faithful import per ADR-013.

### Added — `/daily-audit` skill (cowork-only, no aria-knowledge analog)

New skill at `skills/daily-audit/SKILL.md` (~90 lines). **Cowork-only** per [ADR-014](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/014-bidirectional-feature-flow.md) row 1. First-message audit-cadence substitute since Cowork has no SessionStart hook (per ADR-004). Reads aria-config.md for `last_audit_date` + `last_config_audit_date` + cadence thresholds + stale-ideas count; reports status; recommends `/audit-knowledge` or `/audit-config` invocation if overdue. Recommend-only — never auto-invokes. No MCP dependency. aria-knowledge users get this coverage automatically via `session-start-check.sh` hook, so the skill doesn't ship there.

### Added — `.mcp.json`

First time aria-cowork ships an `.mcp.json` manifest. Byte-identical to aria-knowledge v2.18.0's manifest — 12 MCP servers across 4 categories (slack, ms365, gmail-placeholder, linear, asana, atlassian, monday, clickup, notion, box, egnyte, google docs-placeholder). Slack ships with Anthropic's published OAuth config (clientId `1601185624273.8899143856786`, callbackPort 3118). Cowork-side users connect via Settings → Connectors; Code-side users connect via Code's MCP client OAuth flow.

### Added — `CONNECTORS.md`

First time aria-cowork ships a `CONNECTORS.md`. Documents the `~~category` marker convention per the canonical guidance from `cowork-plugin-management/skills/cowork-plugin-customizer/SKILL.md`. Four categories (chat / email / project tracker / docs) — focused subset matching the 5 MCP-consuming skills + 1 cowork-only daily-audit. Per-skill MCP-usage table includes the cowork-only daily-audit row marked "no MCP needed."

### Schema impact

| Surface | Change | Compatibility |
|---|---|---|
| `.mcp.json` | New file declaring 12 MCP servers | Additive — installs without `.mcp.json` continue to work |
| `CONNECTORS.md` | New companion doc | Additive — documentation only |
| `intake/clippings/` | Existing folder, new content shape from `/clip-thread` | Additive — coexists with `/clip` outputs |
| `intake/meetings/` | New subfolder, lazy-created | Additive |
| `intake/digests/` | New subfolder, lazy-created | Additive |
| `logs/sync-decisions.md` | New artifact, lazy-created | Additive |
| `synced_to_~~docs:` frontmatter on decisions | New optional field | Additive — `/audit-knowledge` ignores |
| `daily_audit_last_run:` in aria-config.md | New optional informational field | Additive |

### Cross-plugin parity (continuing bidirectional flow per ADR-014)

**Coordinated release pair with aria-knowledge v2.18.0** (released same day). 5 of the 6 new skills land in both plugins; the 1 cowork-only skill (daily-audit) is the exception per ADR-014 row 1 (cowork-only when there's no aria-knowledge analog — aria-knowledge has SessionStart hook).

Per ADR-013 (schema-source-of-truth), aria-knowledge defined the canonical SKILL.md bodies; this release imports them byte-faithfully with ONLY these divergences:

- **Step 0 config resolution** — aria-cowork reads `<knowledge_folder>/aria-config.md` (default-path + override per ADR-008/010); aria-knowledge reads `~/.claude/aria-knowledge.local.md`.
- **Frontmatter shape** — aria-cowork adds `name:` field + uses YAML-literal `description:` (`>`); drops `allowed-tools:` (Cowork natural-language invocation pattern per ADR-009).
- **Skill-name phrasing in trigger lists** — aria-cowork descriptions include `/aria-cowork:<skill>` invocation aliases per the natural-language pattern.

All other SKILL.md content (Steps 1-N, output schemas, body templates, Rules sections, Notes sections) is byte-identical. Output schemas in the shared knowledge folder are byte-identical per ADR-013.

### Compatibility

- **No breaking changes.** Existing 20 skills work unchanged. New 6 skills are opt-in by invocation.
- **No new required config.** Existing aria-config.md works unchanged. Optional new fields (`default_sync_target:`, `daily_audit_last_run:`) are absent-tolerant.
- **No new dependencies.** Pure markdown + the MCP runtime that Cowork already provides via Settings → Connectors.
- **Graceful degradation built-in.** If no MCPs connected, the 5 MCP-consuming skills output fallback notices and stop. `/meeting-notes` additionally offers a paste-fallback. `/daily-audit` runs without any MCPs.
- **MCP-consuming is opt-in.** Users who don't want the 5 MCP-consuming skills can ignore them.

### Install issue + supersession by v1.0.1

The v1.0.0 `.plugin` asset (released 2026-05-18 16:01 UTC, GitHub tag `v1.0.0`) **silently failed Cowork's server-side upload validator** due to two undocumented constraints discovered the next day. **Use v1.0.1 instead** — same skill manifest, schema, and ADR set as v1.0.0 with two bug fixes that make the artifact installable. See the [v1.0.1] entry above for the full diagnostic trail (Probes A-K, ~2.5 hours of empirical bisection logged in `~/Library/Logs/Claude/main.log` lines 87582–89221). The v1.0.0 release is retained as historical record but its assets do not install.

### Build artifact

`aria-cowork-1.0.0.plugin` — 248,523 bytes, 101 files, 26 skills. **Broken — install fails with generic "Plugin validation failed." dialog.** Superseded by `aria-cowork-1.0.1.plugin` (see v1.0.1 entry above). v1.0.0 asset retained on the GitHub release page for historical reference; do not install.

### Coordinated release pairing

- **aria-knowledge v2.18.0** (released 2026-05-18) — original companion release. Ships the 5 bidirectional skills first per D2 schema-source-of-truth. v1.0.0 imported the templates byte-faithfully. (aria-knowledge v2.18.1 followed on 2026-05-19 as the companion patch for the parity-affecting `.mcp.json` fix.)

## [0.3.0] — 2026-05-18

**Major parity-catch-up release.** Spans aria-knowledge v2.14.0 → v2.17.0 (six aria-knowledge minor/patch versions). 5 phases of work across 24+ items: schema parity, existing-skill enhancements, planned-but-missing skill ports, net-new skill ports, and release ceremony. Cowork's skill manifest grows from 10 → 20 skills (18 distinct + 2 aliases). 7 cowork-modified skills produce schema-identical knowledge-folder outputs per ADR-013. First instance of bidirectional cowork→aria-knowledge feature flow per ADR-014. Coordinates with aria-knowledge v2.17.0 (shipped 2026-05-18) which imported cowork-originated `/handoff brief` + `/intake doc` modes.

### Knowledge folder schema parity (Phase 1 — 5 items)

- **`template/aliases.md` user-owned template** (v0.3.0 / aria-knowledge v2.16.0+). Maps freeform query tokens to canonical tags. Bootstrapped once on first `/aria-setup`, never overwritten. Ships with 5 commented-out cowork-flavored seed aliases (meeting, brief, doc, action, customer).
- **`semantic-hints:` frontmatter convention** documented in `template/README.md`. Optional YAML list of free-form descriptive phrases. Case-insensitive + hyphen-normalized substring match. Indexed under `## Semantic Hints Index` in `index.md` by `/aria-cowork:index`.
- **Archive-cohort conventions** in `template/archive/README.md` (v0.3.0 / aria-knowledge v2.15.1+v2.15.2). Universal schema: `archive/audit-{date}/MANIFEST.md` + disposition-attribution frontmatter (5 fields) + verify-no-loss check + user-override clause. Same-day audits from both plugins merge into one cohort.
- **`CONFIG.md`** new schema reference mirroring aria-knowledge's `plugin/CONFIG.md` with cowork-specific "Read by" annotations. Documents the 3 new fields: `active_knowledge_surfacing` (consumed by /prospect + /retrospect Step 0.5), `codemap_staleness_threshold_days` (parse-tolerated), `stitch_staleness_threshold_days` (parse-tolerated).
- **`template/rules/working-rules.md`** synced to aria-knowledge v2.14.3 baseline. Adds Behavioral Foundation preamble (v2.14.0), Rule 20 dual-form reframe (v2.14.0), and 7 rule body refinements (Rules 4, 8, 16, 19, 23, 27, 29 per v2.14.3). `template/rules/change-decision-framework.md` + `enforcement-mechanisms.md` synced to current state. `/setup` references substituted to `/aria-setup` for cowork command naming.
- **`template/rules/user-examples.md`** new file (v0.3.0 / aria-knowledge v2.14.2+). User-owned, never-overwritten illustration tier. Ships with 3 commented-out cowork-flavored examples (Rules 16/13/22 — naming clarity, simplicity, decision framework). `/aria-cowork:rules N` auto-discovers matching `## Rule N` examples.
- **`template/TEMPLATE-PARITY.md`** new registry tracking shared template files between aria-cowork and aria-knowledge per ADR-007.

### Existing-skill enhancements (Phase 2 — 6 items)

- **`/aria-cowork:index`** — semantic-hints parsing + Step 2b aliases parse + chain/collision validation + Step 8 Known Tags `[aliases: ...]` annotations + Semantic Hints Index section in `index.md`.
- **`/aria-cowork:context`** — Step 2.5 alias resolution + semantic-hints substring matching (rule 2 of matching) + `[hint: <phrase>]` annotation on hint-matched results + no-match alias display (canonical with aliases in parens, cap 2 + `…`). Skipped Tracked Artifacts surfacing (per ADR-005); skipped shared-block refactor (cowork has only one consumer).
- **`/aria-cowork:ask`** — Step 2 alias resolution (internal, no notification) + semantic-hints substring matching alongside tag-index lookup.
- **`/aria-cowork:stats`** — semantic-hints coverage line (`N of M files (P%)`) in Index Health output. Always-emit policy preserves zero-coverage signal for trend tracking.
- **`/aria-cowork:backlog clear`** — archive-then-remove pattern replacing destructive removal. Writes `archive/backlog-cleared-{type}-{YYYY-MM-DD-HHmmss}.md` with frontmatter (`archived_at`, `source_backlog`, `cleared_through_date`, `entry_count`, `reason`, `plugin_version: aria-cowork@0.3.0`). User-override clause for explicit bare-delete with surface-before-confirm.
- **`/aria-cowork:aria-setup`** — 5 enhancements: Step 1b Access Probe (cowork-only B1 — read+write+delete round-trip validates persistent grant), Step 4 bootstrap entries for `aliases.md` + `rules/user-examples.md`, Step 4b alias chains validation (defense-in-depth with /index), Step 4c Advanced Options bundle with [NEW]-detection observability (`active_knowledge_surfacing` prompt), Step 5b Self-Validation Audit (reads CONFIG.md, scans user's aria-config.md, surfaces missing-consumed fields under Should Fix).
- **`/aria-cowork:rules N`** matching-examples extension — after returning the rule body, checks `user-examples.md` for `## Rule N` headings and appends matching examples.

### Planned-but-missing skill ports (Phase 3 — 5 items + 2 aliases)

- **`/aria-cowork:extract`** — pure port from aria-knowledge. Operates on Claude's working-memory recall. 6 categories: insights, decisions, feedback, project context, references, ideas. No cowork-runtime divergence. Includes `intake/ideas/*.md` per-file storage for ideas with Accept submenu routing at audit time.
- **`/aria-cowork:wrapup`** — cowork variant of aria-knowledge's /wrapup. Git step generates copy-paste commit message (cowork has no shell access); memory scope limited to attached knowledge folder (cowork can't reach `~/.claude/projects/.../memory/`); tracked-artifacts check skipped per ADR-005. Schema-identical PROGRESS.md output.
- **`/aria-cowork:audit-knowledge`** + **`/aria-cowork:knowledge-audit`** alias — largest cowork-modified skill (~926 lines). bin/ shell-outs replaced with Claude-driven inline logic (digest, batch manifest); Step 3 memory scan + Step 4 plans scan marked aria-knowledge-only (cowork can't reach `~/.claude/`); legacy ideas-backlog migration uses inline /aria-setup handling instead of `bin/migrate-ideas-backlog.sh`. Archive-cohort output byte-identical to aria-knowledge for cross-plugin merge.
- **`/aria-cowork:audit-config`** + **`/aria-cowork:config-audit`** alias — CONFIG.md replaces bin/config.sh as field-enumeration source. Step 3a.1 version-stamp ripple uses cowork-scoped surfaces (aria-cowork/.claude-plugin/plugin.json + aria-cowork/CLAUDE.md + aria/CLAUDE.md + project_aria_cowork.md + MEMORY.md index). Step 3a.2 adoption-state cascade adds cowork-relevant phrase library (local-only, will-become-public, Phase N+ deferral, skills-only-no-commands, {INSTALLED_VERSION} leaks). Step 3b Missing-Known-Fields cascade reads CONFIG.md tables. Step 5a tracked-artifact staleness skipped per ADR-005. Cadence integration runs at first aria-cowork skill invocation per session (cowork has no SessionStart hook).
- **`/aria-cowork:snapshot`** — highest cowork-divergence. 3-path source acquisition: (1) Cowork transcript MCP if exposed at invocation time, (2) user-paste, (3) Claude-recall structured fallback. Output to `intake/pre-compact-captures/` matches aria-knowledge path. Body-source attribution as visible `> Source: ...` header (no `capture_source:` frontmatter field per v0.2.4 precedent). Lazy folder creation. No hook companion — manual-invoke only.

### Net-new skill ports (Phase 4 — 3 items)

- **`/aria-cowork:prospect`** — forward-looking pre-mortem on plans before execution. Per-step risk enforcement, simpler-alternative discipline, action verdicts (PROCEED / SHRINK / SPLIT / DEFER / KILL), plan-formation diagnosis. 10-section report shape preserved byte-faithfully. Step 0.5 Active Knowledge Surfacing ports skill-side; `/tmp/aria-active-*` ledger has in-skill in-memory fallback when sandbox restricts /tmp writes. Step 11 CODEMAP/STITCH detection skipped per ADR-005. Evidence-Sourcing Pass + failure-mode pattern library (shared `rules/prospect-patterns.md`) port byte-faithfully.
- **`/aria-cowork:retrospect`** — per-fix-validated retrospective on shipped work. 6 scopes: **session + decision work natively in cowork** (no git dependency); commit/range/PR/release/deployment use **user-paste fallback for git output** (cowork has no shell access). Once paste is in context, downstream analysis is identical to aria-knowledge. Same Step 0.5 + Step 11 divergences as /prospect. Cross-plugin pattern-library writes to shared `rules/retrospect-patterns.md` + `projects/aria/retrospect-patterns.md`.
- **`/aria-cowork:handoff`** — express end-of-session handoff. Three modes: default (combined-go review), `auto` (silent apply), `brief` (copy/paste coworker prose). Brief mode (80-150 words, capped 200) imports v2.17.0 template byte-faithfully — first cowork-originated feature in aria-knowledge per ADR-014. Cowork divergences from aria-knowledge mirror `/aria-cowork:wrapup` (Q-4 git copy-paste, memory scoping, tracked-artifacts skip).

### Mode addition on existing skill

- **`/aria-cowork:intake doc <url-or-title>`** — doc-anchored capture mode added to existing `/intake` skill. 6-step doc-mode flow (D1-D6): acquire source → read/note content → populate template → preview → write → report. Writes to `intake/docs/{YYYY-MM-DD}-{slug}.md` with `type: intake-doc` frontmatter + 5-section body (claims / worth keeping / contested / action / reaction). Reaction section left as user-fill placeholder (the user's voice, not Claude's). `intake-doc.md` template copied from aria-knowledge v2.17.0 byte-faithfully. Lazy subfolder creation.

### Cross-plugin architecture (Phase 5)

- **ADR-005 Section 5b** (amended) — documents v0.3.0 ports: 5 planned-but-missing + 3 net-new skills. Original 5 exclusions (codemap/stitch/distill/audit-share/share-audit) stand.
- **ADR-013** (new) — cowork-modified skills produce schema-identical knowledge-folder outputs. Locks D3 principle: input-discovery diverges per-surface; output-schema converges per-corpus. Applies to 7 cowork-modified skills in v0.3.0.
- **ADR-014** (new) — bidirectional feature flow precedent. Features may originate in either plugin; aria-knowledge stays schema source-of-truth. 3-row trigger-condition table (cowork-only / aria-knowledge-only / bidirectional). v0.3.0's `/handoff brief` + `/intake doc` are the first cowork-originated features ported into aria-knowledge.
- **`CLAUDE.md`** updated with cross-plugin bidirectional flow paragraph (mirrors aria-knowledge's CLAUDE.md addition from v2.17.0).
- **`README.md`** comprehensive update: status line v0.2.5 → v0.3.0, new "What's new in v0.3.0" section, 20-skill table restructured into pre-v0.3.0 + new-in-v0.3.0 sub-tables, deferred-list reframed for v0.4.0+.

### Cowork-only enhancements (not in aria-knowledge)

- **`/aria-cowork:aria-setup` Step 1b Access Probe** — productizes the 2026-04-30 probe arc (probes 2, 3, 11) as a per-setup invariant. Read+write+delete round-trip with diagnostic table covering 4 failure modes (access-denied, read-only, write-without-read, delete-fails-warning). Halts setup on halt-class failures; warning-only on delete-fails. Unique to aria-cowork.
- **Cowork-flavored seed content** — `aliases.md` seed (meeting/brief/doc/action/customer), `user-examples.md` seed (Rules 16/13/22 with non-code examples), `template/README.md` semantic-hints example phrases (stakeholder framing for new initiative / exec summary template / decision options weighing). Surface-specific defaults preserve schema parity while reducing first-run activation cost.

### Compatibility

- **No breaking changes.** Existing v0.2.5 installs upgrade in-place — all existing skills continue to work; all existing knowledge folders remain compatible.
- **Schema additions are additive-only** per ADR-002. Three new aria-config.md fields are parse-tolerated even when cowork doesn't consume them; absent fields fall back to defaults via inline validation.
- **Cross-plugin coordination:** aria-knowledge v2.17.0 (released 2026-05-18) is the parity partner. Both plugins ship `/handoff brief` + `/intake doc` modes with byte-identical templates. v0.3.0 release notes attribute the bidirectional flow.

### Build artifact

`aria-cowork-0.3.0.plugin` — significantly larger than v0.2.5 (84KB → estimated 150-200KB) due to skill manifest growth (10 → 20 skills) and template additions. Built via new `release.sh` (per the 2026-05-09 open idea + ADR-007 + ADR-013 packaging-recipe contract).

### Coordinated release pairing

- **aria-knowledge v2.17.0** (released 2026-05-18) — companion release. Imports cowork-originated `/handoff brief` + `/intake doc` modes per ADR-014 bidirectional flow precedent. v0.3.0 imports the resulting templates byte-faithfully.

## [0.2.5] — 2026-05-08

**Add "Principles transfer, enforcement doesn't" framing to README — closes aria-knowledge ADR 069's S6 deferral.** Doc-only patch documenting the architectural asymmetry between aria-cowork (skills-only, Layers 1+3) and aria-knowledge (hook-enforced, Layers 1+2+3) so Cowork users don't experience silent expectation-mismatch when Rule 22 fires automatically in Code but not in Cowork. Surfaces the Karpathy article's tool-portability framing in inverted form: principles transfer, *enforcement* doesn't.

### Added — `README.md` "Principles transfer, enforcement doesn't" section

A new top-level section inserted between "How it works with aria-knowledge" and "What's deferred to v0.3.0+". Body covers:

- **Shared principles** — the 4-line behavioral foundation (Don't assume / Simplest solution wins / Touch only what you must / Define success criteria) transfers cleanly across both plugins
- **Enforcement divergence** — aria-knowledge fires Rule 22 hooks on every Edit/Write; aria-cowork has no hook surface and carries discipline manually via `/rules` lookups and session-prompt context
- **Karpathy article attribution** — quotes the tool-portability passage from [Yanli Liu's "The 4 Lines Every CLAUDE.md Needs"](https://levelup.gitconnected.com/the-4-lines-every-claude-md-needs-2717a46866f6) that informed aria-knowledge v2.14.0's Behavioral Foundation preamble
- **Layer-2-Code-only design rationale** — references `template/rules/enforcement-mechanisms.md`'s 5-tier ladder; names that aria-cowork operates at Layers 1 (CLAUDE.md rules) + 3 (required output format) only, never Layer 2 (hooks)
- **Future-portability bridge** — frames the asymmetry as design-not-incidental; notes that if Cowork ever exposes a hook surface, this section becomes the guide for porting Code's hook-enforced rules (22, 25, 26)

### Origin — Karpathy 4-line article review (S6 deferral closes)

Surfaced from a 2026-05-06 design conversation in aria-knowledge that produced ADR 069 (Karpathy 4-line foundation + Rule 20 leverage reframe). Three deferrals were recorded: S5 (per-rule examples tier — closed in aria-knowledge v2.14.2), S4 (cull pass on 34 working rules — closed in aria-knowledge v2.14.3), and **S6 (this release — aria-cowork tool-portability framing)**.

The S6 plan lived at `~/Projects/knowledge/projects/aria/2026-05-06-s6-aria-cowork-portability-plan.md` and stayed queued until aria-cowork's next release window. v0.2.5 closes it.

### Cross-plugin parity (per ADR-006)

aria-knowledge v2.14.0 (shipped 2026-05-06) introduced the Behavioral Foundation preamble in `working-rules.md` that this section mirrors and extends. aria-cowork's existing working-rules.md template already inherits those changes via the standard cross-plugin parity flow (rules-tier files are shared between both plugins via the same `~/Projects/knowledge/rules/` source). v0.2.5's README addition documents the **enforcement-layer divergence** that the rules-tier parity doesn't cover — the rules transfer; the hooks don't.

### Preserved

All 10 v0.2.4 skills unchanged. plugin.json structure unchanged (only version field bumped). Probe results, ADR 008 attached-folder pattern, persistent-grant architecture: all unchanged. CLAUDE.md status header unchanged (v0.2.4 → v0.2.5 update can ride a future maintenance pass; the README addition is the substantive change).

---

## [0.2.4] — 2026-05-05

**Remove speculative `captured_via: aria-cowork` field from `/ask` and `/clip` frontmatter, plus mirror aria-knowledge v2.13.6's Rule 34 trigger refinement in the working-rules template.** Two unrelated changes shipped in the same patch window per cross-plugin parity. Captured-via removal follows Rule 13 (simplest solution wins) and Rule 18 (foundational design over patching) — wait until a real audit consumer needs surface-provenance rather than pre-pollute every artifact. Rule 34 trigger refinement adds an architectural-claims trigger surfaced by a real failure mode in a sibling project.

### Added — Rule 34 trigger refinement in `template/rules/` (cross-plugin parity with aria-knowledge v2.13.6)

A new trigger added to Rule 34's plan-level review list: **"Architectural claims about existing systems"** — asserting how a system's data flow, rendering model, or rule-enforcement layer currently works *or doesn't work*. Single-layer reads frequently produce wrong claims when transformations live upstream; the claim becomes a load-bearing premise for downstream proposals.

- **`template/rules/working-rules.md`** — added the trigger bullet to Rule 34's trigger list, between "Asymmetric failure cost" and the "Out of scope" sub-section.
- **`template/rules/change-decision-framework.md`** — added the matching "or claims about existing systems" qualifier to the parenthetical trigger summary at the start of "Plan-Level Application (Rule 34)" so the summary stays in sync with the authoritative list.

**Origin:** Identified via a multi-turn conversation in a sibling project where ~6 turns of architectural recommendation about an existing nav-construction layer were produced from a single-file render-layer read; the actual rule was already implemented at the data-loader layer, in a commit predating the conversation by 20 days. Audit found this only after explicit pushback. The "currently works or doesn't work" qualifier specifically catches the highest-confidence wrong-claim shape — claims that an existing rule *isn't* enforced when it actually is.

**Cross-plugin parity:** aria-knowledge v2.13.6 ships the same template change in the same patch window per the cross-plugin compatibility note in both CLAUDE.mds.

### Changed

- **`skills/ask/SKILL.md` Step 5 frontmatter template**: removed `captured_via: aria-cowork` line. Drafted-doc frontmatter now contains only `tags: [...]`.
- **`skills/clip/SKILL.md` Step 4 frontmatter template**: removed `captured_via: aria-cowork` line. Clipping frontmatter now contains `source`, `date`, `tags` (no provenance field).
- **`skills/intake/SKILL.md` Step 6 Feedback/Project/References template**: removed the trailing instruction line *"Append `captured_via: aria-cowork` to entries' source line so audit knows which surface staged it."* Same speculative-provenance pattern as /ask and /clip; same rationale for removal.

### Migration impact

- **Existing captured docs** in `intake/clippings/`, `approaches/`, `decisions/`, `references/` that already have `captured_via: aria-cowork` keep that field per the universal "don't delete, archive" rule. New captures from v0.2.4 onward simply don't get it. Mixed state is harmless — the field is opt-in metadata, not schema-required.
- **No aria-knowledge coordination** — aria-knowledge never wrote a parallel `captured_via: aria-knowledge` field, so this removal restores symmetry rather than breaking it.

### Rationale captured for future revisit

If cross-surface provenance audit becomes a real workflow, **better alternatives** than per-doc metadata:

1. Centralized capture log at `~/Projects/knowledge/logs/capture-log.md` — one line per `/clip` or `/ask` event with surface + path + timestamp. Single file, queryable, doesn't pollute artifacts.
2. Inferred from time correlation against existing surface-side session logs.
3. Discretionary `tags: [surface:cowork]` at user discretion when provenance specifically matters for that capture.

The Code-side equivalent in aria-knowledge's `/ask` and `/clip` was never added in any version, so backporting `captured_via: aria-knowledge` was considered and rejected for the same reasons (per aria-knowledge v2.13.6 release notes — see B + C below).

### Preserved

- All other skill behavior unchanged.
- All template content outside Rule 34 trigger list unchanged.
- aria-config.md schema unchanged.
- Description length 368 chars (unchanged from v0.2.1; well under the 493-char Cowork validator cap).

---

## [0.2.3] — 2026-05-04

**Sync to aria-knowledge v2.13.5 baseline.** Three additive changes that ride forward from aria-knowledge without changing aria-cowork's scope or breaking any schema: two foundational working rules (33 + 34), the Plan-Level Application subsection in the change-decision-framework, the matching Rule 34 enforcement note, and a dynamic-version-from-plugin.json refactor in `aria-setup/SKILL.md` that eliminates the per-release hardcoded-version-stamp updates.

### Changed

- **Rules 33 + 34 added to `template/rules/working-rules.md`** (~67 lines appended after Rule 32). Source: aria-knowledge `plugin/template/rules/working-rules.md` lines 208-274 verbatim.
  - **Rule 33: "Verify third-party surfaces against current docs before use"** — pre-call doc-check discipline for any third-party API/SDK/library/CLI. Routes through local docs → context7 → official docs → CLI help → user. Composes with Rule 27 (which fires after external failure).
  - **Rule 34: "Validate the plan with Rule 22's framework before executing"** — plan-level entry gate complementing Rule 22's per-edit gate. Triggers on new features, external surfaces, architecture/structural changes, re-implementations, unfamiliar-domain plans, asymmetric failure cost. Marker format: `[Rule 34]` block before first qualifying edit.
- **"Plan-Level Application (Rule 34)" section added to `template/rules/change-decision-framework.md`** between the Lighter Check section and Post-Edit Scope Check. Documents the framework's plan-formation layer: same 7 steps (Identify, Intake, Criteria, Solutions, Rank, Validate, Execute) applied to the plan itself.
- **Rule 34 enforcement paragraph added to `template/rules/enforcement-mechanisms.md`** between the Layering section and Related links. Documents Layer-1-only enforcement (text + discipline marker; hooks deferred pending heuristic calibration, mirroring Rule 22's evolution).
- **`skills/aria-setup/SKILL.md` refactored to dynamic version reading.** New "Step 0: Read installed plugin version" captures `INSTALLED_VERSION` from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` once. All 5 prior hardcoded `aria-cowork v0.2.2` references and 1 `cowork_setup_version: 0.2.2` value now use `{INSTALLED_VERSION}` substitution placeholders. Eliminates the per-release manual find/replace burden previously queued as a v0.3.0 backlog item — landed here since the release was already touching skill bodies for the rules sync.

### Migration impact

- **Fresh installs**: get the full 34-rule template + dynamic-version aria-setup automatically.
- **Existing 0.2.2 installs (Mike)**: re-install 0.2.3. The on-disk plugin overwrites; running `/aria-setup` will pick up the new template and write `cowork_setup_version: 0.2.3` to `aria-config.md`. Existing user `~/Projects/knowledge/rules/working-rules.md` is **user-owned post-deploy** — the diff-on-update flow surfaces Rules 33 + 34 as additions for the user to accept, doesn't auto-overwrite their customizations.
- **No aria-knowledge coordination required** — additive content only. aria-knowledge's working-rules already shipped Rules 33 + 34 in v2.13.4+; this sync brings aria-cowork to baseline parity.

### Preserved

- All earlier rules (1-32) unchanged.
- All skills' behavior unchanged except `aria-setup`'s version-source (now dynamic instead of hardcoded — semantically equivalent at runtime).
- `aria-config.md` schema field NAMES unchanged (`cowork_setup_version`, `last_setup_date`, `last_setup_surface`); only the `cowork_setup_version` *value* now derives from `INSTALLED_VERSION`.
- Description length 368 chars (well under the empirical 493-char Cowork validator cap; v0.2.1 fix preserved).

### Out of scope (still queued for v0.3.0+)

- Port deferred skills (audit-config, audit-knowledge, extract, snapshot, wrapup) → v0.3.0
- MCP integrations + CONNECTORS.md → v0.3.0
- Cowork-native skills (digest, clip-thread, extract-doc, sync-decisions, meeting-notes, daily-audit) → v0.4.0
- OVERVIEW.md design-philosophy enrichment → separate scope

---

## [0.2.2] — 2026-05-04

**Rename `setup` skill to `aria-setup`** to avoid collision with other plugins' setup skills and to make natural-language invocation unambiguous. Cowork's canonical pattern is description-driven trigger matching (no literal slash commands), so a plugin-specific skill name is more reliable than the generic `setup`. Same skill behavior, same scaffold flow, just a more distinctive identifier.

### Changed

- **Skill `setup` renamed to `aria-setup`.** Directory `skills/setup/` → `skills/aria-setup/`. Frontmatter `name: setup` → `name: aria-setup`. Heading and trigger phrases updated.
- **Cross-references updated** in 8 sibling skills (ask, backlog, clip, context, index, intake, rules, stats) — their "Run `/aria-cowork:setup` to get started" prompts now read "Run `/aria-setup` to get started". Dropped the redundant `/aria-cowork:` plugin prefix; in Cowork the prefix is a hint pattern, not a literal command, and `aria-setup` is already self-disambiguating.
- **`help` skill command table** updated: `/setup` row now `/aria-setup`. Header refreshed from stale `v0.1.0 — Phase 1 thin port` to `v0.2.2`.
- **`stats` skill output template** updated: `Last /setup:` → `Last /aria-setup:` in the dashboard summary.
- **Template files** updated (deployed to `~/Projects/knowledge/` on first run): plugin-managed banners in `OVERVIEW.md`, `rules/working-rules.md`, `rules/enforcement-mechanisms.md`, `rules/change-decision-framework.md`, `decisions/README.md`, `rules/user-rules.md` now reference `/aria-setup` instead of `/setup` or `/aria-cowork:setup`.
- **Version stamps in `aria-setup/SKILL.md` body** bumped 0.2.0 → 0.2.2 for the `cowork_setup_version` value written into user `aria-config.md` files and the user-facing "setup complete" output.
- **README.md** updated for the rename + version stamps + plugin filename `aria-cowork-0.2.1.plugin` → `aria-cowork-0.2.2.plugin`.

### Migration impact

- **Fresh installs**: zero migration. Users invoke "set up aria-cowork" or "/aria-setup" naturally.
- **Existing 0.2.1 installs (this means Mike, who installed minutes before this rename)**: re-install 0.2.2 via the same drag-and-drop flow. The rename is name-only; the underlying skill behavior, aria-config.md schema, and folder structure are all unchanged.
- **No aria-knowledge coordination required** (per ADR-006 — independent semver). aria-knowledge keeps its `setup` skill name (Code-side, no collision concern).

### Preserved

- All other skill names (ask, backlog, clip, context, index, intake, rules, stats, help) unchanged.
- aria-config.md schema unchanged — field names `cowork_setup_version`, `last_setup_date`, `last_setup_surface` keep the literal substring "setup" because they're config field NAMES, not invocation references. Field values updated to reflect 0.2.2.

---

## [0.2.1] — 2026-05-04

**Hotfix: shorten `plugin.json` description below Cowork's undocumented length cap.** Cowork's account-marketplace upload validator silently rejects plugins whose `description` exceeds approximately 500 characters. v0.2.0's 565-char description tripped this cap; the desktop UI surfaced only the generic fallback message "Plugin validation failed." with no field-level detail, making the trigger non-obvious. v0.2.1 trims the description to 368 chars (well under the empirical 493-char passing threshold) without changing any other surface — same skills, same template, same architecture.

### Changed

- **`plugin.json` description shortened** from 565 chars to 368 chars. Dropped: implementation-detail prose ("v0.2.0 ships persistent-grant access via claude_desktop_config.json... regardless of which project folder is the active workspace"). Retained: product purpose, companion-to-aria-knowledge framing, default folder location.

### Diagnostic findings (durable — see also `~/Projects/knowledge/guides/claude/cowork-plugin-validation.md`)

Discovered via 11-test bisection of the failing v0.2.0 plugin. Each test isolated one variable; pass/fail signals progressively shrunk the search space from "anything in 59 files" to one scalar JSON value.

1. **Description length cap is the actual root cause** of all v0.2.0 install rejections, including the earlier variants with `userConfig` and `commands/`. Those variants had even longer descriptions (because they described the additional features) and would have tripped the same cap.
2. **The validator is server-side** at the account-marketplace upload endpoint — not client-side schema enforcement. The desktop's "Plugin validation failed." dialog is a fallback string emitted when the desktop's regex `/\): (.+)$/` fails to extract the server's actual error message. The server response is in the HTTP body, not in any app log file.
3. **Code-side install path differs from Cowork-side.** Drag-and-drop into a chat goes through Code-side `LocalPluginsWriter` (writes directly to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/<name>/`), bypassing the Cowork-side `uploadAccountPlugin` validator. This explains why aria-knowledge ships happily despite its longer description — its install was via the Code-side path. Cowork's plugin list reads from the cloud account marketplace, which is why a successful Code-side install can still be invisible in Cowork's UI.
4. **Memory correction**: the prior claim that `userConfig` was rejected because canonical `cowork-plugin-management/skills/create-cowork-plugin/SKILL.md` documented it as "User-prompted config at enable time" was wrong. Re-reading the skill + its `references/` shows zero mentions of `userConfig`. The original v0.2.0 attempt added the field unprompted; rejection followed for an unrelated length reason.

### Architectural notes preserved from v0.2.0

The v0.2.0 conservative simplifications (drop `userConfig`, drop `commands/`, default-path convention with `aria-config.md` override) still hold — they match Anthropic's published Cowork plugin pattern (skills-only, minimal manifest, natural-language invocation). The original rationale for those changes was the wrong-attributed rejection, but the resulting shape is correct on its own merits.

---

## [0.2.0] — 2026-05-01

**Architectural pivot to persistent-grant pattern.** v0.1.0 required the user to attach the knowledge folder AS the workspace folder — preventing simultaneous use with project work. v0.2.0 separates path discovery from folder access (`claude_desktop_config.json` persistent grant), so aria-cowork is reachable from every Cowork session regardless of which project folder is the active workspace. This matches how aria-knowledge feels to use in Code.

### Validation notes (Cowork divergences from documented behavior)

> **CORRECTION 2026-05-04**: The two rejection attributions below (`userConfig` field, `commands/` directory) are likely wrong. Both variants had longer descriptions than 500 chars and almost certainly tripped the description-length cap that v0.2.0 itself hit — see [0.2.1] release notes above and `~/Projects/knowledge/guides/claude/cowork-plugin-validation.md`. The conservative architectural simplifications (drop both, use skills-only minimal manifest) still made sense on their own merits, but the diagnostic story below mis-attributes the trigger. Original text retained for historical record.

Two parts of v0.2.0's design were rejected by Cowork's install validator despite passing `claude plugin validate` (CLI). Both are documented here as durable spec findings:

1. **`userConfig` field rejected.** First v0.2.0 attempt declared `userConfig.knowledge_folder` in `plugin.json` per the canonical `cowork-plugin-management/skills/create-cowork-plugin/SKILL.md` documentation. CLI accepted it; Cowork rejected the manifest with no specific error. Conservative fix: removed `userConfig` entirely. Replaced with a **default-path convention** (`~/Projects/knowledge/`) with override via `aria-config.md`'s `knowledge_folder:` field.

2. **`commands/` directory rejected.** Second attempt added 10 thin `commands/<name>.md` wrappers to enable explicit `/aria-cowork:setup`-style slash commands (matching Claude Code's invocation convention). CLI accepted; Cowork rejected the manifest. Reverted to **skills-only with natural-language invocation** — the canonical Cowork pattern matching Anthropic's 11 published Cowork plugins. Users invoke aria-cowork by describing what they want to do ("set up aria-cowork", "save this to aria-cowork") rather than typing slash commands. Skill `description` fields contain trigger phrases Claude matches.

v0.3.0+ may revisit either mechanism if working schemas/structures surface in published plugins or in updated Cowork docs.

### Changed

- **`plugin.json` is a minimal manifest** (name/version/description/author). No `userConfig`, no hooks, no `mcpServers` — same shape that v0.1.0 packaged successfully.
- **Setup skill rewritten** for the default-path flow: try default `~/Projects/knowledge/` → check for `aria-config.md` override → inline-prompt the user if neither default nor override exists → verify reachability → guide `claude_desktop_config.json` edit if folder not granted → scaffold/check structure → write `aria-config.md`.
- **All 10 skills' Step 0 updated** — use the default knowledge folder path (`~/Projects/knowledge/`, expanding `~` to the user's home directory). Skills then read `<knowledge_folder>/aria-config.md` for any non-default override or schema fields.
- **`aria-config.md` role**: cross-surface schema bridge between aria-cowork and aria-knowledge. Holds the canonical `knowledge_folder:` field for users with non-default locations. aria-knowledge in Code unchanged — still reads aria-config.md from absolute path with legacy fallback.

### Architecture (per [ADR-008](https://github.com/mikeprasad/knowledge/projects/aria-cowork/decisions/008-attached-folder-pattern-for-bidirectional-sharing.md) v0.2.0)

Two-layer mechanism:

1. **Path discovery** — Cowork's userConfig holds the knowledge folder absolute path. Skills read it at runtime.
2. **Folder access** — One-time grant via `claude_desktop_config.json` (or per-session `/add-dir` fallback for testing).

Result: install once, configure once, use across any Cowork project.

### Validated

- `claude plugin validate` passes on the new `userConfig` schema (verified field name `title` not `label` after first-pass schema rejection).
- Probe 11 evidence: Cowork file tools resolve absolute paths directly (no sandbox-mount path translation needed).
- Probe 12 evidence: Cowork enforces folder-grant at the path level — explicit grant required (validates the persistent-grant + userConfig design).

### Cross-plugin parity callouts

- **aria-knowledge v2.13.0 migration**: still required (aria-config.md as cross-surface schema bridge unchanged from v0.1.0 spec). Read-both, two-version deprecation window starting at v2.13.0.
- **Schema**: `aria-config.md` schema unchanged from v0.1.0 (just `knowledge_folder` + `cowork_setup_version` + `last_setup_date` + `last_setup_surface`). v0.3.0+ will add MCP-related fields.

### Deferred to future versions

- v0.3.0 — `.mcp.json` named MCPs (Slack, Notion, Linear, Gmail, etc.) + CONNECTORS.md customization markers + capability-probe helper + dual-use skill ports (extract, snapshot, audit-knowledge, audit-config, wrapup)
- v0.4.0 — 6 Cowork-native skills (digest, clip-thread, extract-doc, sync-decisions, meeting-notes, daily-audit)
- v0.5.0 (optional) — drift CI between aria-cowork and aria-knowledge

### Superseded

- **v0.1.0** as a user-facing release. The `aria-cowork-0.1.0.plugin` file built but never shipped (knowledge-folder-as-workspace model was too narrow). v0.2.0 is the first release users see.

---

## [0.1.0] — 2026-04-30

Phase 1 — thin port. First installable release. Validates the attached-folder pattern in Cowork; ports 10 lowest-risk skills from aria-knowledge.

### Added

- **Plugin scaffold** following Anthropic's canonical Cowork plugin structure (`.claude-plugin/plugin.json`, `skills/`, `template/`, README, LICENSE)
- **10 ported skills** from aria-knowledge, adapted for Cowork's runtime:
  - `setup` — first-run folder attach + `aria-config.md` write at attached-folder root
  - `help` — command reference
  - `clip` — save URL/snippet to `intake/clippings/`
  - `intake` — bulk import files, URLs, directories
  - `ask` — research + save to category
  - `context` — load knowledge by topic/tag
  - `index` — rebuild tag index
  - `stats` — knowledge folder health metrics
  - `rules` — working-rules + change-decision framework lookup
  - `backlog` — view/manage pending intake
- **Template seed** — minimal `~/Projects/knowledge/` bootstrap (intake/, decisions/, approaches/, rules/, archive/, README, OVERVIEW). Excludes `distill/` and `stitch/` per [ADR-005](https://github.com/mikeprasad/knowledge/projects/aria-cowork/decisions/005-code-only-skills-excluded.md).

### Architecture

- **Attached-folder pattern** ([ADR-008](https://github.com/mikeprasad/knowledge/projects/aria-cowork/decisions/008-attached-folder-pattern-for-bidirectional-sharing.md)) — skills resolve absolute path to user-attached folder once at `/setup`, store in `aria-config.md`, reference absolute path everywhere. NOT cwd-relative (Cowork's cwd is a per-session sandbox dir, NOT the attached folder).
- **No hooks** ([ADR-004](https://github.com/mikeprasad/knowledge/projects/aria-cowork/decisions/004-hook-replacement-strategy.md)) — Cowork supports hooks but the canonical pattern is skill-embedded discipline. aria-cowork ships zero hooks to match the published-plugin convention.
- **No MCPs in v0.1.0** — `.mcp.json` and named connectors land in v0.2.0. Filesystem I/O uses Cowork's native Read/Write semantics, not the Filesystem MCP connector.

### Validated

- aria-probe plugin (regression-test artifact at `probe/`) ran 2026-04-30. Probes 2 (filesystem write) and 3 (cross-surface read) PASS. Probe 11 (folder attach) INCONCLUSIVE-spec-finding (drove ADR 008 rename from "cwd pattern" to "attached-folder pattern"). Full results at `~/Projects/knowledge/probe-test/probe-results-2026-04-30T07-01-09.md`.

### Cross-plugin parity callouts

- **Schema**: aria-cowork v0.1.0 introduces `aria-config.md` at the knowledge folder root (vs aria-knowledge's `~/.claude/aria-knowledge.local.md`). aria-knowledge v2.13.0 (queued, not yet released) reads the new path first with two-version fallback to legacy. aria-knowledge users continue uninterrupted; aria-cowork users land directly on the new path.
- **Skill set**: 5 aria-knowledge skills (`codemap`, `stitch`, `distill`, `audit-share`, `share-audit`) are NOT ported per [ADR-005](https://github.com/mikeprasad/knowledge/projects/aria-cowork/decisions/005-code-only-skills-excluded.md) — they're git/repo-bound. aria-knowledge keeps these.

### Deferred to future versions

- v0.2.0 — `.mcp.json` with named MCPs (Slack, Notion, Linear, Gmail, etc.) + `CONNECTORS.md` companion + capability-probe helper for native skills + adapt `extract`/`snapshot`/`audit-knowledge`/`audit-config`/`wrapup` ports
- v0.3.0 — 6 Cowork-native skills (`digest`, `clip-thread`, `extract-doc`, `sync-decisions`, `meeting-notes`, `daily-audit`)
- v0.4.0+ — drift CI between aria-knowledge and aria-cowork; release.sh schema-diff
