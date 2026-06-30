# Changelog

All notable changes to ARIA will be documented in this file.

## 2.38.1 — 2026-06-30

**Behavioral Foundation framing — strictness tiers + a genuine-ties tie-breaker.** Two additive paragraphs in `template/rules/working-rules.md`'s Behavioral Foundation; no new numbered rule, no renumber, rule count unchanged. Makes explicit what the ruleset already enforced implicitly.

- **Two strictness tiers.** Names the rigid-vs-default distinction the ruleset always carried but never stated: some rules are **gates** (don't adapt away under pressure — the verification/authorization rules, e.g. 20, 22, 33, 34, 35; surface a blocking gate, don't route around it); the rest are **defaults** (strong starting points, judgment applies, deviate-and-say-why). When unsure which, treat as a gate.
- **Tie-breaker for genuine ties.** When two options are of equal merit, prefer the one that preserves reversibility and an audit trail. Explicitly *not* a bias against irreversible choices — a clearly-correct irreversible option isn't a tie; it runs through Rule 35's authorization gate (surface it, get the go-ahead), not through this tie-breaker.

Distilled from `knowledge/approaches/portable-working-method.md` (the portable distillation of this ruleset). **Ports:** Claude-Code-canonical only; codex/cursor/antigravity/cowork stay tracked-drift (framing reaches them at the next template-sync parity pass). Pre-existing note: `plugin.json` description still reads "35 working rules" (actual 37 since v2.38.0) — unrelated stale count, left for a description-budget pass.

## 2.38.0 — 2026-06-29

**Two new universal working-rules + two strengthened — synced to Claude Code + Cowork.** Distilled from `knowledge/approaches/mike-engineering-standards.md` via a gap-analysis against the enforced ruleset; only principle-level, domain-agnostic items were universalized.

- **New Rule 36 — "a pass signal only counts if it can fail for the right reason."** Bind a gated conclusion to the load-bearing result, never a proxy (a pipeline's last command, a transport status code, an absent guard a negative-only test can't detect). A validated confirmation is only valid in its case context and isn't fully valid until its *failure* is equally understood + validated (both pass AND fail matching intended outcome); mechanical understanding of *why* it passes/fails is what makes validation generalize across contexts and variants. Composes with Rules 15 + 20.
- **New Rule 37 — "anything temporary names its own removal trigger up front."** First justify temporary-ness against a foundational alternative (Rule 18); then any temporary thing (code, doc, config, stub, deferral, flag, workaround) carries a documented context/trigger/condition/timing for removal at introduction, never a someday cleanup ticket. Contrast with Rule 6 (which protects content meant to last).
- **Strengthened Rule 15** — a guard test needs a positive case, not only a negative (a negative-only test is a false green; if you removed the guard the suite must go red). RED→GREEN per guard.
- **Strengthened Rule 21** — for a non-trivial/hard-to-reverse decision, record the full ADR shape: alternatives-with-rejection-rationale + consequences across positive/negative/neutral/deferred + the forward-looking downstream commitments the decision dictates. Scale the artifact to reversibility.

working-rules.md 35 → 37 rules. Template content (not SKILL frontmatter) — skill-discovery budget unaffected (17186/18944). Minor bump (new universal rules = capability surface every user inherits, per the v2.35.0 precedent). **Ports:** synced to plugin-claude-code + plugin-claude-cowork (coordinated cowork v1.5.0, which also closed a missing-Rule-35 drift); codex/cursor/antigravity tracked-drift (rules reach them via template sync at next parity pass).

## 2.37.1 — 2026-06-25

**New `/recap project` mode — lateral cross-project orientation.** Where `/recap`'s existing modes orient you *temporally* (this session, this repo's git), `project` mode orients you *laterally* — the current state of one project, or of the whole portfolio. A terminal-table analogue of the aria-atlas dashboard.

- **One verb, three breadths** (a trailing second arg selects breadth): `/recap project` → the current session's main project (Step-1 walk-up from cwd, no roster needed) · `/recap project <name>` → a named project (the `<name>:` tag in `projects_list`; unknown tag lists available tags, no fuzzy match) · `/recap project all` → roster glance across every `projects_list` entry.
- **Reuses canonical surfaces, adds no machinery:** the roster comes from `projects_list` read exactly as `/aria-assist` reads it (**read-only on `projects_list`**); per-project state comes from `SESSION.md` (`lastEvent` + next-session prompt) and `PROGRESS.md` (latest arc + open items); git rows (`log -1`, `status --short`) only when the dir is a git repo **and** Bash is available — **silently omitted otherwise** (a per-project version of the Runtime-Gate Bash check). All reads are tolerant — a missing/malformed file degrades to a blank/omitted row, never throws. No new config key, no new tool.
- **Two output shapes:** single-project = full orientation in the standard `What/Where/Status` table with an indented `↳` context sub-row per item (so "T0 completed" reads with what T0 *was*); roster = terse rows + one ~6-word in-flight fragment, recency-sorted, `+N more (older)` tail. Always prints the resolved project path (single) / roster total (all) per the honest-about-inference rule. Escalation offer (never auto-run): single → `/retrospect`, roster → `/aria-assist`.
- **Read-only preserved:** still `allowed-tools: Read, Glob, Grep, Bash` — Write/Edit excluded; the mode writes nothing.
- **All-modes refinement — self-descriptive `What` cells.** Any `What` cell that isn't understandable on its own (a bare artifact name like `group G`, `T0`, a flag/config key, a ticket ID) must carry a short detail clause (≤~8 words) so the row reads without prior context (`group G — 9 recap-mode contract assertions`, not `group G`); cells that already read plainly need no addition. Single-project mode does this via the `↳` sub-row; terse roster rows use the inline `— detail` form. Sharpens "Glance, not essay" (every row understandable at a glance) rather than fighting it.
- `recap-modes.sh` extended with a 9-assertion group G (breadth sub-modes + roster source + read-only-on-roster + repo-absent degradation + path-print transparency + escalation offer); 22 assertions green, full plugin suite 45 green, all 25 repros green.
- **Ports:** Claude-Code-canonical only — codex/cursor/antigravity/cowork stay tracked-drift (recap is Bash-native git + the SESSION.md/PROGRESS reads are Code-filesystem-default). **Local dogfood only — not tagged / GH-released / port-propagated** (same posture as 2.37.0). Built execute-mode via `/auto` (spec → /prospect [PROCEED, all 4 steps pre-validated] → plan → execute → gates).

## 2.37.0 — 2026-06-25

**New skill `/auto` — the entry point for an autonomous execution arc.** A single invocation drives the full gate chain (brainstorm→spec→/prospect→plan→/prospect→TDD→/retrospect) under the autonomous decision-routing posture, deciding objectively-validatable forks itself and stopping only on a genuine load-bearing fork or an ungranted approval.

- **Two modes:** `/auto [goal] [continue|stop]` (full arc; `continue` keeps finding new work after the planned queue for unattended/overnight runs, `stop` checkpoints + hands off — the default) and `/auto execute <plan|spec|linear-id>` (a plan exists — skip ideation).
- **Explicit override of the `autonomy` config (Option A):** `/auto` runs fully autonomously regardless of the standing `autonomy` posture (incl. `default`) and **never writes config** — the standing posture stays `/setup`'s exclusive job (one writer, no drift). The invocation *is* the grant. Named `/auto` for uniformity with Claude Code's "auto mode."
- **Compose-not-duplicate:** the decide-vs-ask *logic* stays in **Rule 35** (the skill instantiates the routing table, doesn't re-list it); the skill adds only the *operational* discipline Rule 35 doesn't enumerate. Builds on the v2.35.0 `autonomy` config + SessionStart directive.
- **Absorbs the prior paste-at-top-of-session mandate** (`knowledge/AUTONOMOUS-SESSION-TEMPLATE.md`, now a tombstone) as the single source of truth: pre-answered never-stops (knowledge placement, tool/permission approvals, backlog/deferral, Linear filing, commit cadence), verify-state-empirically, legitimate-stops, budget-binding (usage→cron / context→handoff; auto-/extract at 90% context), work-selection, subagent NEED-IT gate, optional resume-cron, never-force-push, verification-reality, knowledge-capture-as-you-go. Coverage verified by a mechanical claim-by-claim diff (43/43). Companion: a pre-authorized tool allowlist in `.claude/settings.local.json`.
- New repro `auto-modes.sh` (49 assertions: modes + no-keyword default + compose-not-duplicate + Rule-35 deferral + arc contract + stop-rule + never-stop list + budget-binding + work-selection + subagent gate + resume-cron + verification-reality); skill-reviewer Pass.
- **Ports:** **Claude-Code-canonical only this release** — codex/cursor/antigravity/cowork stay 2.36.0 tracked-drift (the Cowork variant needs a trimmed description vs its 9000-char summed cap). **Released for local dogfood; not yet tagged / GH-released / port-propagated** — a live `/auto` run is the gating acceptance per the session retrospect before public release.

## 2.36.0 — 2026-06-24

**Anti-over-build upgrade — simplification marker + opt-in over-build review lens.** Ports two patterns from the Ponytail project (github.com/DietrichGebert/ponytail, a YAGNI-for-agents tool) into ARIA's existing primitives — minimal footprint, no new skill, no new numbered rule.

- **Simplification marker (Rule 13 clause).** When an agent deliberately takes the simpler path on non-trivial logic, it now leaves an inline `aria:simplification — <what> | limitation: <gap> | upgrade: <path>` marker. Folded into existing Rule 13 (still 35 rules — the bias against rule-count growth holds); operationalizes Rule 21's "document decisions" for the specific decision *"I chose less."*
- **`overbuild-patterns.md` (new shared rules file).** A ladder (needed? → stdlib? → platform-native? → installed-dep? → one-line? → minimal-build) + 6 seed smells (`speculative-abstraction`, `dependency-for-a-oneliner`, `config-knob-nobody-asked-for`, `premature-generalization`, `framework-for-a-function`, `unmarked-simplification`). One source of truth all three lenses read; mirrors `retrospect-patterns.md`'s entry format and grows by accretion.
- **`--lens=overbuild` mode** on `/prospect` (forward, on a plan → SHRINK/KILL verdicts) and `/retrospect` (backward, on a diff → findings + marker-respect), plus an **over-build per-surface probe** in `/readiness-audit` (whole-repo sweep). **Opt-in** — bare invocations are unchanged. Every finding must cite the failed ladder rung + a concrete leaner alternative or it's suppressed; a hunk carrying a valid marker is reported "resolved (marked)", never flagged.
- New repro `test-overbuild.sh` (marker-grammar contract + per-skill lens-documented lint); 45 plugin tests green. Behavioral spot-check confirmed the retrospect lens flags a `dependency-for-a-oneliner` and respects a marked simplification.
- Built brainstorm→spec→prospect→plan→prospect→execute. The spec-prospect corrected the `/readiness-audit` integration (per-surface probe, not a "checklist dimension"); the plan-prospect produced a new canonical `prospect-patterns.md` pattern (`prose-deliverable-test-honesty`). **Ports:** propagated to all 5 (codex/antigravity/cowork/cursor); cowork's `/readiness-audit` adapted to its sequential no-subagent body; cursor compiled to `aria-commands.mdc`. PORT-LEDGER re-baselined; drift check clean.

## 2.35.2 — 2026-06-22

**Step 2f handles image clippings — `/audit-knowledge` stops silently skipping images.**

v2.35.1 made clippings graduate to `references/sources/` but scanned `.md` only — image clippings (`.png/.jpg/.jpeg/.gif/.webp`) were invisible (caught when `karpathy-kb-map.jpeg` had sat unprocessed in clippings since April, logged as "kept" across ~7 audits but mechanically unreadable).

- **Step 2f image sub-flow:** images are now scanned and, under Graduate, vision-read (model-native, no OCR) → transcribed to text → tier-decided per image (faithful-twin → `references/sources/`, distilled → top-level `references/`) → asset graduated → transcription mined into the six buckets → ledgered `graduated (image; transcribed → …)`. Decorative images graduate source-only.
- **Cost guard:** >5 images triggers a review-all / review-N / defer-rest prompt (vision reads are non-trivial).
- **Shared fix:** graduation's move rule now uses `git mv` only when the *specific file* is tracked (`git ls-files --error-unmatch`), else plain `mv` — corrects a v2.35.1 bug where `git mv` failed on untracked files (the FB-Instagram clipping hit it). Applies to `.md` and image graduation alike.
- New repro `tests/repros/image-extraction.sh`; suite count 23 → 24.
- **Ports:** Code-canonical. Cowork has no Step 2f (N/A); antigravity/codex normal sync. `/intake` image branch + bulk-dir image pickup deferred (recorded in the spec).

## 2.35.1 — 2026-06-21

**Clippings graduate to `references/` — `intake/clippings/` becomes a durable-source on-ramp.**

Previously `/audit-knowledge` Step 2f mined a clipping then *deleted* the source (ledger-clear). There was no path to preserve a clipping as a citable reference. This makes graduation the default: every processed clipping is preserved whole AND mined.

- **Step 2f (`plugin-claude-code/skills/audit-knowledge/SKILL.md`):** disposition menu is now **Graduate (default) / Skip**; the mine-and-discard path is removed. Graduate derives+confirms tags, `git mv`s the whole clipping to `references/sources/{file}.md`, mines all six buckets to the backlogs, and ledgers `disposition: graduated` (not deleted). No-minable-content clippings still graduate their source.
- **Two-tier `references/`:** top-level = curated fragments/notes; `references/sources/` = verbatim graduated clippings (raw artifacts). Documented in the template `references/README.md`.
- **`/index` (`plugin-claude-code/skills/index/SKILL.md`):** Step 1 now scans `references/` **recursively**, so `references/sources/` is indexed (without this, graduated sources would be invisible — confirmed via /prospect).
- New repro `tests/repros/clippings-graduate.sh`; suite count 22 → 23.
- **Corpus-schema (ADR-013 / ADR-014):** the `references/sources/` path + `graduated` ledger disposition are canonical corpus-wide now; this is a row-3 bidirectional feature. **Ports:** Code-canonical this round — Cowork has no clippings step (its Step 2 ends at 2d); porting it (and the missing 2e/2f) is deferred and must conform to this schema. antigravity/codex follow their normal sync.
- **Distribution note:** the template `references/README.md` change surfaces as a `/setup` diff for existing users; benign, not silent.

## 2.35.0 — 2026-06-21

**New Rule 35 (decision routing) + `autonomy` config posture — make the ask-vs-decide policy binding.**

The decision-routing policy (investigate-first; spend the human's decision budget only on what the agent can't resolve) previously lived only in scattered non-binding `feedback` memories, so it had to be hand-restated each session. This promotes it to the binding tiers.

- **Rule 35 (`template/rules/working-rules.md`, universal):** consolidates the calibration into one operative rule — the decision-budget economics (the human's attention is the scarce resource; agent speed/context is cheap) + the routing table (resolvable→investigate→act · objectively-validatable→decide+show · mechanical/already-decided→act · intent/preference/judgment-with-no-gainable-visibility→ask · ungranted-explicit-approval→ask) + sequential composition. The quality bar for a validatable decision is the existing Rules 13/14/18 (referenced, not duplicated). Always-on for every user; ships via `/setup`'s plugin-managed diff.
- **`autonomy` config key (`default` | `balanced` | `autonomous`, ship default `default`):** gates a scaled SessionStart directive in `session-start-check.sh`. `default` injects **nothing** (zero behavior change, zero context cost — the safe failure mode). `balanced` injects a light investigate-first directive. `autonomous` injects the full posture: decide objectively-validatable forks yourself (checked against Rules 13/14/18), quality gates as checks-not-stops, stop only on a no-visibility judgment call or ungranted explicit approval. Parsed by `config.sh` (so Step 7e self-validation recognizes it; the hook reads `$KT_AUTONOMY`). Surfaced in `/setup`.
- New repro `tests/repros/autonomy-posture.sh` (Rule 35 presence + default=no-injection + balanced/autonomous directive emission, driven via the picker-gating KT_CONFIG-stub technique); 22 repro suites green.
- **Distribution note:** editing the plugin-managed `working-rules.md` means every existing user sees a Rule 35 diff prompt on their next `/setup` — intended, benign, not silent. **Ports:** Rule 35 reaches all ports via the shared template; the SessionStart injection is Claude-Code-canonical.

## 2.34.0 — 2026-06-21

**New skill: `/recap` — read-only orientation.** A scannable `What / Where / Status` table of *what just happened*, to situate the user at a glance. The orient-side counterpart to `/handoff` (which packages state for the next reader) — `/recap` re-orients the *current* reader. Distinct from `/retrospect`: recap summarizes, never validates/judges (it may *offer* to escalate to `/retrospect`, never runs verdict work).

- **Five modes** dispatched by input: `/recap` (this session — conversation synthesis) · `/recap arc` (the last product arc — from the nearest `PROGRESS.md`'s most recent heading; states the inferred boundary) · `/recap commit [<hash>]` (`git show`) · `/recap push` (`git log @{push}..HEAD` — what I sent up) · `/recap pull` (`git log ORIG_HEAD..HEAD`, reflog fallback if stale — what came down to me; always prints the resolved range).
- **push vs pull** are surfaced as opposites: push = my commits sent up; pull = others' commits I merged.
- **Read-only by construction:** `allowed-tools: Read, Glob, Grep, Bash` — `Write`/`Edit` deliberately excluded so the runtime cannot write even if prose drifts. No logs, no files; the one pure-read skill in the orient/capture family.
- New repro `tests/repros/recap-modes.sh` (asserts 5 modes + pull resolution + the consistent table + the no-Write invariant); 21 repro suites green. **Ports:** Claude-Code-canonical (git modes are Bash-native); not added to other ports this round.

## 2.33.0 — 2026-06-21

**`/intake` consolidation — `/clip`, `/clip-thread`, `/extract-doc` retired into `/intake`; clippings review gap closed.**

- **One capture command.** `/intake` now dispatches by input shape: a single URL or text snippet **clips whole** to `intake/clippings/`; files/dirs/globs **bulk-scan** into the backlogs; `/intake extract <source>` **decomposes** a source (incl. a `~~docs`-MCP doc) into backlog entries; `/intake doc <source>` captures the 5-section reflection artifact; `/intake thread <id>` pulls a chat/email thread via `~~chat`/`~~email` MCP (and auto-detects a chat/email URL). Only `extract`/`doc`/`thread` need a keyword — sources with a detectable shape route automatically.
- **Behavior change:** a bare URL now CLIPS WHOLE (previously `/intake <url>` mined into backlogs). Mine a single URL via `/intake extract <url>`, or let `/audit-knowledge` decompose the clipping later.
- **Retired (archived per Rule 6, not deleted):** `/clip`, `/clip-thread`, `/extract-doc` moved to `skills/.archived/` with pointer headers; their trigger phrases are absorbed into `/intake`'s description so discovery survives. Bare-slash collision set drops 24 → 21.
- **`/audit-knowledge` Step 2f (Review Clippings) — NEW.** Audit never scanned `intake/clippings/`, so clipped items (and hand-dropped files) were never reviewed — `/clip`'s "reviewed at next audit" was a dead-end. Step 2f (modeled on the subagent-captures step) now scans clippings, routes extractable content to the backlogs, and ledger-clears processed clippings to `archive/audit-{date}/clippings/`.
- **MCP modes are Code-native** once the bundled `~~chat`/`~~docs` MCP is authenticated — `thread`/MCP-doc surface an authenticate prompt (not a Cowork redirect).
- New repro `tests/repros/intake-dispatch.sh` (grammar precedence + Step 2f presence + retirement + no-dangling-ref gate); 20 repro suites green. **Ports:** Claude-Code-canonical; the bare-slash removal must propagate to cowork/codex/cursor/antigravity at the next parity pass.

## 2.32.0 — 2026-06-21

**SESSION.md multi-session ledger + nested-workspace routing fix.** Two changes to the `SESSION.md` producer (Claude-Code-only; gated on `session_state`).

- **Multi-session ledger.** A project's `SESSION.md` now holds N sessions instead of last-writer-wins clobbering. The newest unconsumed handoff stays in the front-matter + `## Next session prompt` (atlas's single-active view, unchanged); prior sessions are demoted into a new `## Prior sessions` body section that the aria-atlas parser ignores by construction (it stops at the first `## ` after the prompt). **Keep-until-consumed:** a `/handoff` demotes the prior active entry and prunes any already-`consumed` entry; a resume (first-edit on the project) stamps the prior handoff `consumed`; `/wrapup` prunes consumed entries without adding one for itself. **Nothing unconsumed is silently lost.** New `lib-session-state.sh` helpers: `kt_ss_ledger_add` / `kt_ss_ledger_mark_consumed` / `kt_ss_ledger_prune` / `kt_ss_read_active_sid` (all temp-file+mv, fail-safe). The consume-stamp lives in `post-edit-check.sh` inside the existing once-per-(session,project) guard, so it fires once per resumed root, not per edit.
- **Age relevance prompt.** A saved resume prompt older than the new `session_stale_days` config key (default 7) triggers a "still relevant? [resume / archive / keep]" prompt at session start instead of being presented as live. Prompt-only — never auto-evicts (latched-state discipline). `archive` moves the entry under a `## Archived sessions` heading (also atlas-ignored).
- **Nested-workspace routing fix.** `kt_ss_find_root` previously only rejected a `$HOME`-direct-child container, so nested workspace-index roots (a directory that indexes child projects) wrongly received a `SESSION.md`. Now a root carrying an `aria_workspace_root: true` CLAUDE.md line or a `.aria-workspace-root` sentinel is skipped; the walk continues to the nearer real sub-project root. The wrapup/handoff Step 1 skill prose already used the equivalent semantic check — the hook and skill now agree.
- **Contract-safe by construction:** zero aria-atlas changes; existing session-contract fixtures untouched (only a new `handoff-multi-session.SESSION.md` fixture added). New repro sections I (routing), J (ledger), K (consume), L (atlas-isolation guard). 19 repro suites green.
- **Ports:** Claude-Code-canonical only; cowork/codex/cursor/antigravity tracked-drift (SESSION.md producer is Bash + Claude-Code-only, as since v2.22.0).

## 2.31.0 — 2026-06-17

**New skill: `/interview` — elicit knowledge through dialogue.** The existing capture family is all *harvest*-based — `/extract` reads the current conversation, `/intake` scans files/URLs, `/clip` saves a snippet, `/meeting-notes` folds a transcript. None of them draw out knowledge that lives only in your head. `/interview` fills that gap: it *asks you questions*, and the answers become the staged knowledge. Modeled on the `grill-with-docs` / `deep-interview` Socratic pattern.

- **Three modes** (`/interview <mode>`):
  - `project` — scope a new project/build (problem · users · scope-in/out · constraints · stack · success · risks) → `intake/projects/{date}-{slug}.md`
  - `knowledge` — get a topic out of your head into the KB (claim · basis · confidence · contested · connections · what-would-change-my-mind) → `intake/interviews/{date}-{slug}.md`
  - `deep-dive` — comprehensively extract the rationale behind an existing-but-undocumented system you built; questions are evidence-cited, clustered by leverage, and hunt negative space ("what did you deliberately NOT build?") → `intake/interviews/{date}-{slug}.md`
- **Cadence chosen in-session** (not a flag): `socratic` (one question at a time, adaptive) or `battery` (research-then-present a full clustered question set you answer at once). The skill recommends a cadence and accepts an override.
- **`deep-dive` requires a basis** (`--ground=<path|glob|url>[,...]`) — an explicit early-return gate stops it from asking questions until you point it at code, a doc, a plan, a project, a data file, or a URL. The gate *is* deep-dive's identity; without a basis it would just be `knowledge` mode.
- **Stages for manual review**, never auto-promotes. `/audit-knowledge` scans a fixed set (the four backlogs + `intake/ideas/`) and does not sweep `intake/projects|interviews/` — so `/interview` output follows the `/meeting-notes` model: you promote it later by hand or via `/extract`.
- **Process:** brainstormed → spec → `/prospect` (PROCEED-WITH-CHANGES) → plan → `/prospect` (PROCEED) → executed. The pre-mortems caught a falsified spec claim (the `/audit-knowledge` review path) and prevented an unnecessary second file (banks are ~10 lines; the skill is 148 lines total, single-file).
- **Skill-budget Gate B:** summed skill-discovery surface 15,846 B (budget 18,944) — 3,098 B headroom.
- **Ports:** Claude-Code-canonical only; cowork/codex/cursor/antigravity stay tracked-drift (re-sync in a coordinated parity pass).

## 2.30.1 — 2026-06-15

**Skill-discovery surface trim (~480 tok / ~11%), zero capability loss.** Continues the v2.30.0-codex.0 alias-skill removal: the per-session skill-discovery fixed cost had grown to ~4,364 tok (largest fixed cost, driven by v2.29.0's two review skills). This trims it back to ~3,884 tok by relocating non-dispatch bytes out of frontmatter `description:` fields — the descriptions exist for natural-language dispatch; documentation belongs in the skill body (read only when the skill fires, off the per-session surface).

- **Tier 1 — ADR-094 parenthetical (24 skills):** shortened the repeated `(Claude Code variant — bare-slash canonical when both ports loaded; see ADR-094.)` (~84 B each) to `(Code port — ADR-094.)` (~22 B). The cross-port ownership rule is *enforced by the Runtime Gate in each skill body* (verified present 24/24), not by the description text — so no enforcement is lost. `aria-assist` keeps its scheduler-specific variant (carries dispatch-relevant info).
- **Tier 2 — mechanism-narration (2 skills):** compressed the internal `→` pipeline narration in `/readiness-audit` and `/foundational-review` descriptions to one-clause summaries; the full pipelines remain documented in each skill's body (verified). Kept all dispatch-critical content: intent, sibling-contrast clauses, and the complete Triggers lists.
- **Verified:** skill-discovery surface 17,458 → 15,537 B (~4,364 → ~3,884 tok); `release.sh` Gate B passes (15,537 ≤ 18,944 budget). Pre-mortemed via `/prospect` (PROCEED-WITH-CHANGES; the one guard — body-pipeline-coverage before trimming Tier 2 descriptions — was verified before execution).
- **Ports:** Claude-Code-canonical only; cowork/codex/cursor/antigravity stay tracked-drift (re-sync in a coordinated parity pass).
- **Docs:** `docs/value-analysis.md` cost surface refreshed to the post-trim figure.

## 2.30.0-codex.0 — 2026-06-11

**Codex parity pass for the v2.29/v2.30 review-and-release surfaces.** The OpenAI Codex port now tracks canonical `plugin-claude-code` v2.30.0 where Codex has an equivalent runtime surface.

- **Add:** `/foundational-review` and `/readiness-audit` to `plugin-openai-codex/skills/`, with ADR-094 Claude/Cowork runtime gates stripped and the canonical process doc bundled at `skills/foundational-review/foundational-review-chain.md`.
- **Keep explicit non-equivalents:** `/statusline` remains absent because Codex has no plugin statusline/usage-percentage payload. `/aria-assist` and the `pm-*` scheduler scripts remain absent because this Codex plugin surface has no bundled launchd/headless scheduler equivalent yet.
- **Release path:** `release-codex.sh` now runs the port-drift report gate like the canonical release path and removes an existing zip before rebuild so removed files cannot linger in an appended archive.
- **Drift checker:** `check-port-drift.sh` normalizes `-codex.N` and `-cursor.N` prerelease suffixes when comparing a port version against its canonical parity target, avoiding false `lag` rows for parity-aligned port releases.
- **Tests:** Codex port suite expanded to assert the review skills ship, ADR-094 gates do not leak, `/aria-assist` remains documented as non-equivalent, and statusline remains documented as non-equivalent. Focused `port-drift-check.sh` repro covers prerelease suffix normalization.
- **Build:** `./release-codex.sh` produced `aria-knowledge-codex-2.30.0.zip` plus stable alias `aria-knowledge-codex.zip` (149 files, tests excluded).
- **Remove the alias skills across all ports** (`/knowledge-audit`, `/config-audit`, `/share-audit` — pure aliases of `/audit-knowledge` / `/audit-config` / `/audit-share`). They charged every session's skill-discovery surface for zero capability. The slash-forms still route — folded into each canonical audit skill's description trigger list (`Also invoked as '/knowledge-audit'.`) — so muscle memory is preserved; only the separate skill dirs are gone. Canonical surface 17,979 → 17,458 B; cowork summed descriptions → 8,489 (under the 8,500 warn). Antigravity + cursor regenerated from canonical; codex folded in-port. Same version numbers (folded into this release, no bump).

## Cursor port 2.35.2-cursor.0 — 2026-06-22

**Cursor parity pass for canonical v2.35.2.** Brings `plugin-cursor-template/` to equivalent skill + hook coverage with `plugin-claude-code` v2.35.2 where Cursor has an equivalent runtime surface.

- **Add:** `/interview`, `/recap` compiled into `aria-commands.mdc`.
- **Consolidate:** retired `/clip`, `/clip-thread`, `/extract-doc` — folded into `/intake` (modes `clip`, `thread`, `extract`, `doc`).
- **Sync:** `/audit-knowledge` Step 2f clippings graduation + image extraction sub-flow; `/index` recursive `references/` scan; Rule 35 + `autonomy` config + SessionStart directive.
- **Sync:** SESSION.md multi-session ledger (`lib-session-state.sh`), workspace-root routing, `session_stale_days` resume/archive prompt; handoff consume-stamp in `post-edit-check.sh`.
- **Sync:** hook scripts + `knowledge/` template rsync @ v2.35.2 (`references/` tier, `working-rules.md` Rule 35).
- **Keep explicit non-equivalents:** `/statusline`, `pm-*`, PreCompact transcript hooks, Rule 22 `permissionDecision: deny`, v2.30 deny-rate circuit breaker (Cursor advisory enforcement only).
- **Build:** `./release-cursor.sh` → `aria-knowledge-cursor-2.35.2.zip` + stable alias `aria-knowledge-cursor.zip` (not run this pass).

## Cursor port 2.30.0-cursor.0 — 2026-06-11

**Cursor parity pass for canonical v2.30.0.** Brings `plugin-cursor-template/` to equivalent skill + hook coverage with `plugin-claude-code` v2.30.0 where Cursor has an equivalent runtime surface.

- **Add:** `/foundational-review`, `/readiness-audit` compiled into `aria-commands.mdc`; bundled process doc at `knowledge/approaches/foundational-review-chain.md`.
- **Add:** `/wrapup snap` + `/handoff snap` (snap runs Cursor-native `/snapshot` task-boundary capture instead of `/extract`).
- **Add:** `session_start_project_picker` + `projects_labels` config keys + SessionStart project menu in `session-start-check.sh`; path-boundary fix in `kt_project_for_path`.
- **Sync:** hook scripts from canonical (excluding Code-only: PreCompact, statusline, pm-*, deny circuit breaker); `knowledge/` template rsync @ v2.30.0.
- **Keep explicit non-equivalents:** `/statusline`, Rule 22 `permissionDecision: deny`, v2.30 deny-rate circuit breaker (Cursor advisory enforcement only).
- **Build:** `./release-cursor.sh` → `aria-knowledge-cursor-2.30.0.zip` + stable alias `aria-knowledge-cursor.zip` (95 files).

## 2.30.0 — 2026-06-11

**Structural consolidation — self-enforcing gates replace prose-and-vigilance at the three points where failure had already recurred.** A foundational review found the two highest-stakes surfaces (Rule 22 enforcement; the five-port distribution) governed by hand-vigilance rather than mechanical checks. This release adds the structure, with no user-visible change except a degraded-mode warning banner.

- **Add: deny-rate circuit breaker in `pre-edit-check.sh`.** Converts the "confident-no deny loop" failure class (a transcript-format change that parses cleanly but shifts semantics → `no` → deny → editor deadlock; the Opus 4.7 split-message and Fable 5 dropped-text incidents) from fail-closed deadlock into self-healing fail-open. A per-session counter (`${TMPDIR}/aria-r22-denies-<session_id>`; falls back to the transcript basename; disabled if neither resolves — never a shared cross-session counter) trips after **3 consecutive denials with zero intervening compliant edits**. While tripped, edits are **allowed with a loud `systemMessage`** (the same fail-open-LOUD philosophy as the existing "unknown" branch — enforcement is never lost silently). A single compliant edit deletes the counter and restores blocking enforcement. Model-agnostic — supersedes per-model parser patches.
- **Add: release gates in `release.sh`** (parity with `release-codex.sh`, which already gated). **Gate A** runs `tests/run.sh` + `plugin-claude-code/tests/run.sh` and aborts on any failure. **Gate B** sums the frontmatter-`description:` bytes across `skills/*/SKILL.md` (the always-on per-session discovery cost) against `ARIA_SKILL_BUDGET` (default **18944**; aborts with the total + 3 largest on a breach; raise the default deliberately in the commit that adds a skill). **Gate C** runs the port-drift checker, report-only this release (TODO v2.31.0: make fatal). Also **fixes** a latent bug — the canonical zip shipped `plugin-claude-code/tests/` (no exclusion + `zip -rX` appending onto a stale archive); adds `--exclude='tests/'`, a verify step asserting zero `tests/` entries, and a clean rebuild (`rm` before zip).
- **Add: machine-readable port-parity ledger.** `PORT-LEDGER.json` (repo root) records per-port `{version, parity_target, last_parity_pass, sla, surfaces:{path:sha256}}` for the five ports; `bin/check-port-drift.sh` recomputes surface hashes and reports `ok`/`drifted`/`missing`/`within-SLA` plus the antigravity `version.txt`-vs-`plugin.json` version-pair trap (modes: default table, `--quiet`, `--update <port|all>`). Replaces the CLAUDE.md footer's prose "tracked-drift" narration with a mechanical check. `sla` ships `undeclared` (SLA values are a separate gated decision); drift on an undeclared port is shown but tolerated so the check does not flag pre-existing version lag.
- **Tests:** two new repro suites (`r22-circuit-breaker.sh`, `port-drift-check.sh`); the two existing hook repros isolate `TMPDIR` per run so the breaker counter can't accumulate across runs; a stale statusline-session-start fixture fixed (19 repro suites + 35 plugin tests green). `docs/release-validation.md` gains a Release gates section.
- **Ports:** Claude-Code-canonical only; cowork/codex/cursor/antigravity tracked-drift (now recorded in `PORT-LEDGER.json` rather than prose). No port re-sync this release.

## 2.29.0 — 2026-06-11

**Two new review skills — `/foundational-review` + `/readiness-audit` — productizing the foundational review chain.** A decision-anchored foundational review genre (distinct from code review, retrospective, and plain audit) plus its recurring surface-audit sibling. Both mirror `/prospect`'s structure and **transclude a single canonical process doc** rather than forking its content into the SKILL bodies.

- **Add: `/foundational-review <scope-root> [--decision "..."] [--extend]`** — verdict-led foundational review (sections A–F + named premises + irreversibility inventory) → design spec (D-decisions + gates) → cold-executable plan (owner routing, default executor) → composed `/prospect` with amendments applied **in place** → commit + paste-ready executor kickoff. **Requires a named irreversible decision** (freeze / format-or-spec tag / public flip / major re-scope) — with none, it redirects to `/prospect` or `/readiness-audit` rather than running. Bakes in: the reviewer-model effort ladder, the coupling-mechanism grouping heuristic for multi-repo families, a pairing check (run the audit first on ship/freeze/flip), and a pre-commit failure-mode self-check. `--extend` adds the system-design assessment + waves roadmap chain.
- **Add: `/readiness-audit <scope-root> [--for "<event>"]`** — "is it clean/legal/consistent to ship for THIS event?" Parallel per-surface exploration → **controller re-verification of every load-bearing agent claim** with a correction trail → tiered (Tier 0/High/Medium/Low) findings each with a verified Evidence cell → conceptual observations → phased remediation (findings are **not** a shipping list) → end-to-end verification recipe → gates via `AskUserQuestion`. **Read-only probes only**, with a mandatory artifact `git diff --stat` check before staging. No decision anchor required.
- **Add:** plugin-bundled canonical process doc at `skills/foundational-review/foundational-review-chain.md` (genericized, public-clean). Both skills read it at Step 1, **preferring a user's richer copy at `<knowledge_root>/approaches/foundational-review-chain.md`** when present, else the bundled copy — so a fresh install is self-contained (no broken reference) and a user's promoted version still wins.
- **Docs:** `/help` command table + Model Recommendations row; README prose + capability table.
- **Ports:** Claude-Code-canonical only. The cowork/codex/cursor/antigravity ports are tracked-drift for a later parity pass (the cowork port's 9000-char summed-description cap is full — a cowork variant needs a coordinated trim pass).

## 2.28.1 — 2026-06-10

**Statusline shows the reasoning-effort level after the model name.** The `/effort` setting (low/medium/high/xhigh/max) now renders as a compact letter suffix on the model segment — e.g. `Opus 4.8 (1M) H` at `/effort high`. Verified the Claude Code statusline JSON exposes `.effort.level` (reflects live mid-session `/effort` changes; absent when the model has no effort parameter).

- **Add:** `statusline-meter.sh` parses `.effort.level` (jq tier) and maps it to `L` · `M` · `H` · `XH` · `MX` (max→`MX` to avoid colliding with medium's `M`), appended after the model name in the model-colored segment. No suffix renders when `.effort.level` is absent.
- **Correctness:** the suffix is display-only — `$model` stays bare so the state-snapshot (`{model:…}` consumed by the usage-inject + SessionStart readers) records the raw model name, not the effort-suffixed one.
- **Docs:** `/statusline` skill example now shows `Fable 5 H` + a bullet documenting the `L/M/H/XH/MX` mapping; demo payload gains an `effort` field. Script header documents the new consumed field.
- **Install:** re-run `/statusline` to refresh the installed copy (`~/.claude/aria-statusline-meter.sh`) — the running status line uses that mirror, not the repo source.
- **Ports:** Claude-Code-only (the status line is a Code feature; antigravity/codex/cursor/cowork don't ship the meter).

## 2.28.0 — 2026-06-10

**`snap` mode for `/wrapup` + `/handoff` — defer knowledge synthesis when context is high.** A new mode that runs the full silent close-out/handoff (summary, PROGRESS, CLAUDE.md, memory, commit — plus the next-session opener for `/handoff`) but archives the raw transcript via `/snapshot` for later extraction **instead of** running `/extract` now. `/extract` is the expensive, compaction-risky step; when context is near-full, snap preserves the transcript cheaply (a bash file copy) so a later `/extract` or the next `/audit-knowledge` digest pass can synthesize knowledge when context isn't a constraint. Definitionally minimal: **`snap` ≡ `auto` + one swap** (`/extract` → `/snapshot`); it inherits all of auto's silent/implicit-yes behavior and overrides exactly the capture step.

- **Add:** `/wrapup snap` — third mode (peer to default + `auto`). Parses in Step 0; every per-step auto-conditional now reads `If mode = auto (or snap)`; Step 8 (renamed "Capture Session Knowledge") branches snap→`/snapshot`, auto→`/extract`. Runtime gate and Rules updated; closing report notes the deferred capture.
- **Add:** `/handoff snap` — fourth mode (peer to default + `auto` + `brief`). Parses in Step 0; Step 4 review + Step 5 apply now include snap alongside auto; Step 6 (renamed "Capture Session Knowledge") branches snap→`/snapshot`, auto→`/extract`. The next-session opener is still the headline artifact (snap is NOT brief — it produces the full package + opener + commit). Checklist + report + Rules updated.
- **Invariant:** snap **defers, never drops** capture — the snapshot always runs (no skip path, same as auto's "extract always runs" rule). snap is otherwise byte-for-byte auto behavior (silent, local commit only, never push). `/snapshot` requires Bash, which the existing Step-0 runtime gate already guarantees.
- **Docs:** `/help` table advertises `/wrapup [auto|snap]` and `/handoff [auto|brief|snap]`.
- **Ports:** Claude-Code-canonical only. The cowork/codex/cursor/antigravity `/wrapup`+`/handoff` are tracked-drift for a later parity pass (cowork's snap would call its 3-path `/snapshot`).

## 2.27.2 — 2026-06-10

**Fix the Fable-5 guidance: difficulty is the trigger, not context size.** The v2.27.1 notes justified reaching for Fable 5 partly via "the 1M window" — but Opus 4.8 *also* has a 1M context window, so window size is not a Fable-vs-Opus differentiator and the framing would mis-route large-but-tractable work to a 2×-cost model. Re-anchored both notes on raw capability/judgment.

- **Docs:** `/handoff` skill — the Fable rubric note now triggers on extreme *difficulty* (novel architecture, gnarly cross-system debugging, high-asymmetric-failure-cost reasoning), explicitly states Fable and Opus share the same 1M window, and keeps large-but-tractable tasks on `Opus`.
- **Docs:** `/help` skill — the Fable note now leads with capability/judgment (not context), and reframes the `/codemap create` "large-context variant preferred" qualifier as legacy (any current top-tier model, Opus 4.8 included, already carries 1M).
- **Ports:** Claude-Code-canonical only (same scope as 2.27.1).

## 2.27.1 — 2026-06-10

**Fable 5 readiness — model-tier prose updated for the new tier above Opus.** Anthropic's Fable 5 (`claude-fable-5`, displayed "Fable 5", 1M-token context) is the first capability tier *inserted* above Opus since ARIA's model-recommendation prose was written. The plugin's runtime is already model-agnostic (the statusline meter reads `model.display_name` dynamically; usage/context hooks are percentage-based), so this is a docs-only pass with no code changes.

- **Docs:** `/handoff` skill — added `Fable` to the de-version family list (both copies) and the effort-ladder support clause; added one advisory note that `Fable · xhigh` replaces the top row's `Opus · xhigh` when the hardest first action also needs the 1M window (large-repo `/codemap`, multi-doc synthesis). Rubric rows unchanged; `Opus · high` stays the uncertainty fallback.
- **Docs:** `/help` skill — added a note after the Model Recommendations table positioning Fable as the step-up top tier (and noting the "large-context variant preferred" `/codemap create` qualifier is moot on Fable's 1M window). Table rows unchanged.
- **Docs:** `/statusline` skill — refreshed the example output + test payload from `Opus 4.8` to `Fable 5` (cosmetic; the meter script is dynamic and untouched).
- **Ports:** Claude-Code-canonical only. The `plugin-antigravity` skill mirror (handoff/help/statusline) is tracked-drift for a later parity pass; codex/cursor/cowork carry no model tables.

## 2.27.0 — 2026-06-10

**ARIA Assist morning-run schedule surfaces in aria-atlas (read-only) + a global status overlay.** The `/aria-assist` launchd schedule now writes a small global `.aria-assist.json` overlay next to the digests, which aria-atlas reads to render a read-only "Morning run" card (ON/OFF · time · last-run). Enable/disable stays on the aria side (`pm-schedule.sh` via `/setup`); atlas never shells to `launchctl` — preserving its standalone portability.

- **Add:** `apm_write_assist_status` (+ `apm_assist_status_path`) in `pm-lib.sh` — `jq` deep-merge writer for `<pm_digest_dir>/.aria-assist.json` (create-if-absent, preserves sibling sections).
- **Add:** `pm-schedule.sh` writes the `schedule` section on install (`enabled:true` + time + label) and flips `enabled:false` on `--uninstall` (file retained so atlas can show OFF).
- **Add:** `pm-morning-run.sh` records a `lastRun` section (timestamp, result, digest date, summary) after each run.
- **Fix:** `pm-schedule.sh` install crashed at any hour ≥ 08 (`printf '%d'` treated a leading-zero hour like `08` as invalid octal); now base-10 coerced via `$((10#$HOUR))`. Latent because the shipped default `07:30` parses as valid octal.
- **Fix:** removed the `/wrapup` token from the `/handoff` skill description so typing `/wrapup` no longer surfaces `/handoff` in the slash-command picker.
- **Test:** revived the `pm-*` repro harness into `plugin-claude-code/tests/` (it had shipped untested since v2.25.0) — 35 assertions green, incl. the new overlay cases.
- **Docs:** `/setup` schedule step notes the aria-atlas surfacing. The aria-atlas reader/endpoint/card live in the aria-atlas repo.
- **Ports:** Claude-Code-canonical only (the schedule is Bash + macOS launchd); other ports tracked-drift.

## 2.26.0 — 2026-06-06

**Opt-in, non-blocking SessionStart project picker.** Multi-project users (a parent dir like `~/Projects` holding sibling project folders) can have ARIA suggest a project menu at session start, generated from `projects_list` — replacing hand-written `settings.local.json` SessionStart hooks that duplicated and drifted from the configured roster.

- **Add:** two config fields, both gated by existing `projects_enabled`: `session_start_project_picker` (bool, default `false`) and `projects_labels` (optional `tag:Label` display map; empty ⇒ bare-tag menu).
- **Add:** `kt_project_menu` helper in `config.sh` (pure function: `projects_list` + `projects_labels` → menu string).
- **Add:** gated, **non-blocking** picker block in `session-start-check.sh` — suggests `'Which project today? …'` only when the opening message doesn't already name a project/task AND CWD isn't already inside a configured project (that case stays `auto_load_project_context`'s). On selection, reads the project's `CLAUDE.md`/`PROGRESS.md`. Never blocks.
- **Add:** `/setup` questions for both fields (project tier); `CONFIG.md` + README documentation; ADR-100.
- **Path resolution:** inline `pm_projects_root` read (default `~/Projects`), the same key ARIA Assist uses; a canonical `KT_PROJECTS_ROOT` unification is deferred to its own coordinated ADR (backlogged).
- **Migration:** after enabling, remove any custom SessionStart project-prompt hook from `.claude/settings.local.json` (ARIA does not edit personal settings).
- **Ports:** Claude-Code-canonical only; other ports inherit the inert config keys safely (named-key parse ignores unknowns) — hook-block port-out is tracked-drift.

## 2.25.2 — 2026-06-06

**Superpowers is now a recommended companion, surfaced in `/setup`.** ARIA is the knowledge + edit-discipline layer; [Superpowers](https://github.com/obra/superpowers) is the complementary process-discipline layer (brainstorming, `writing-plans`, `executing-plans`, TDD, subagent-driven development). They interlock into a full plan → `/prospect` → build → `/retrospect` loop, and ARIA already stores plans/specs in the `docs/superpowers/{plans,specs}/` convention.

- **Add:** `/setup` **Step 5c** — detects whether Superpowers is installed (same idiom as the explanatory-output-style check), recommends it if absent with the verified install command (`/plugin install superpowers@claude-plugins-official`), and reports the outcome in the Step 8 summary. **Strongly recommended but optional** — ARIA never depends on Superpowers and no skill is gated on it.
- **Add:** README "Works Well With Superpowers" section describing the interlock.
- **Ports:** Claude-Code-canonical only; other ports tracked-drift (separate parity pass).

## 2.25.1 — 2026-06-06

**SessionStart token trim — ~11% smaller injection, zero enforcement/behavior change.** The SessionStart guidance block had grown to ~1,270 tokens as features shipped; this trims it to ~1,120 with no loss of any rule.

- **Change:** the **TASK BUDGET** guidance emitted *both* the "usage snapshot exists → read it" and the "no snapshot → watch for strain" branches every session, but only one is ever true — and the two read as self-contradictory. The hook now gates on whether the (account-keyed, sticky) status-line snapshot exists and emits only the applicable branch; the UUID-bearing path is stated once instead of twice, and the staleness/scope rules (re-read fresh; 5h/7d stale past `resets_at`; `context_pct` unknown on `session_id` mismatch or null) are preserved verbatim-in-meaning but tightened. ~588 B saved on this segment.
- **Change:** the **CODEMAP Found** report now shows full staleness detail only for stale / possibly-stale / unknown-date maps and collapses current maps to a `+N current: name, name` tail (current maps need no action). Preserves the "read its CODEMAP Directory section first" instruction.
- **Untouched:** the RULE 22 ORDERING enforcement block, the PreToolUse deny mechanism, and all INSIGHT CAPTURE / MEMORY PATHWAY / ARIA ACTIVE CONTEXT / SESSION STATE guidance.
- **Ports:** Claude-Code-canonical only; codex/cursor/antigravity SessionStart equivalents tracked-drift (separate sync pass).

## 2.25.0 — 2026-06-06

**ARIA Assist — morning product-management review across your portfolio (`/aria-assist`).** Incorporates the standalone aria-pm assistant into the plugin as a generic, publishable skill + `pm-*` bin scripts.

- **Add:** `/aria-assist` skill (`generate` / `review` modes). `generate` (headless-safe) reads a deterministic facts scan, deep-reviews **ACTIVE** projects (state · next action · ideas · proposed operator actions), applies logged light-writes, and writes a dated digest. `review` (interactive) walks the digest and executes approved proposals. A bare `/aria-assist` auto-decides via `pm-mode.sh`.
- **Add:** `bin/pm-{lib,collect,notify,mode,morning-run,schedule}.sh` (POSIX sh). `pm-collect.sh` scans the **`projects_list`** roster (the full portfolio = the scan universe) and tier-classifies each project from git/PROGRESS recency + `SESSION.md` state into `facts.json` (`~/.claude/aria-pm-facts.json`); the tier filter narrows deep review to ACTIVE ones.
- **Add:** settings via new **`pm_*` keys** in `~/.claude/aria-knowledge.local.md`, read by a local `pm_cfg` helper (the shared `config.sh` is unchanged): `pm_active_max_days`, `pm_warm_max_days`, `pm_dormant_nudge_days`, `pm_light_writes`, `pm_idea_count`, `pm_digest_dir`, `pm_notify_desktop`, `pm_notify_imessage`, `pm_imessage_handle`, `pm_schedule_time`.
- **Add:** per-project **`PM-REVIEW.md`** producer output (ACTIVE projects only) — an atlas-readable sibling of `SESSION.md` (consumed read-only by aria-atlas; contract `aria-atlas/docs/TEMPLATE_PMREVIEW.md`).
- **Add:** optional `/setup` step + `bin/pm-schedule.sh` to install a macOS launchd morning job (`com.aria.morning`). **Claude Code / macOS only** — other ports run `/aria-assist generate|review` manually (no scheduler). Desktop banner is the always-works notifier; iMessage is best-effort (one-time Automation grant).
- **Authority model preserved:** light-writes (IDEAS-BACKLOG appends) are logged under "Auto-applied this run" and checkpoint-before-write (named-path commit, never `git add -A`); operator actions are only ever *proposed* in `generate` and execute in `review` after approval; never touches application code; won't propose acting on an `in-progress` (live) project.
- **Ports:** Claude-Code-canonical this release; codex/cursor/antigravity/cowork manual-only variants tracked-drift (separate sync pass).

## 2.24.3 — 2026-06-05

**Runtime-aware statusline account resolution + staleness/scope guards (ADR-099).** Fixes false/cross-account usage alerts when Claude Code runs **hosted inside Claude Desktop**.

- **Fix:** the meter, the `UserPromptSubmit` inject hook, and the SessionStart TASK BUDGET reader resolved the account from `~/.claude.json` — the *CLI* credential store, which is wrong under Desktop hosting (it reports the CLI login, not the session account). They now share `kt_resolve_account` (in `config.sh`, byte-mirrored into the standalone-copied meter), which keys the per-user account from runtime signals (`$PATH` `local-agent-mode-sessions` → `claude-code-sessions/<acct>/` lookup) under Desktop, and falls back to `~/.claude.json` for the CLI (v2.24.2 behavior preserved). Graceful-degrades (suppress) when Desktop-hosted but unresolvable.
- **Fix:** the inject hook no longer alerts on a 5h/7d figure whose window already reset (`now > resets_at`); `context_pct` (per-session) is trusted only for the matching `session_id` and a non-null (non-post-`/compact`) measurement.
- **Fix:** the SessionStart TASK BUDGET guidance now tells the agent to re-read the snapshot fresh and apply the same staleness/scope rules (closes the resume-after-hours stale-read + the context confabulation).
- **Add:** `refreshInterval: 30` in the `/statusline` wiring keeps 5h/7d values current during idle (no token cost, no extra alerts).
- Snapshot schema gains `runtime`, `session_id`, `seven_day_resets_at`; the account-email status-line segment renders only on the CLI runtime.
- **Ports:** statusline scripts ship only in `plugin-claude-code` (+ `plugin-antigravity`, which targets `~/.gemini/antigravity.json` and has no Claude-Desktop hosting → exempt). codex/cursor/cowork don't ship these scripts.

## Cursor port 2.24.2-cursor.0 — 2026-06-04

**Version alignment** — tracks `plugin-claude-code` v2.24.2. Canonical delta is **statusline-only** (per-account usage snapshot + email segment; Claude Code CLI). No Cursor port code or `.mdc` resync required. Release artifact: `aria-knowledge-cursor-2.24.2.zip` via `./release-cursor.sh`.

## Cursor port 2.24.1-cursor.0 — 2026-06-04

**Cursor port parity pass** — brings `plugin-cursor-template/` to equivalent coverage with `plugin-claude-code` v2.24.1. Release artifact: `aria-knowledge-cursor-2.24.1.zip` via `./release-cursor.sh`.

### Added — hooks (Cursor-native mappings)

- `afterFileEdit` → `post-plan-prospect-check.sh` (auto-prospect on plan writes; config `auto_prospect`)
- `afterShellExecution` → `post-push-retrospect-check.sh` (auto-retrospect on `git push`; config `auto_retrospect`)
- `subagentStart` → `subagent-start-selfreport.sh` (weaker than Claude — parent `agentMessage` only)
- `subagentStop` → `subagent-stop-capture.sh` (archive to `intake/subagent-captures/`)

### Added — scripts + config keys

- `lib-session-state.sh` + SESSION.md in-progress piggyback in `post-edit-check.sh` (gated on `session_state`)
- Config keys: `session_state`, `subagent_capture*`, `auto_prospect`, `auto_retrospect`, `retrospect_*`, `usage_alert_threshold` (default `off` in Cursor — no statusline)

### Changed

- **`port-skills-to-mdc.py` rewritten** — full-regenerates `aria-commands.mdc`, `aria-audit.mdc`, `aria-context.mdc`, and `aria-rule-22.mdc` from canonical v2.24.1 (preserves Cursor-native `/snapshot` + audit Step 2d + Rule 22 advisory hooks)
- Skill parity restored: `/index` ephemeral-tag exclusion, `/extract` Step 2.5 subagent sweep, `/wrapup`+`/handoff` SESSION.md + multi-root disambiguation, `/setup` reads `scripts/aria/VERSION`, Step 5b statusline skipped
- `post-edit-check.sh`: SESSION ledger key falls back to transcript-path hash when `sessionId` absent
- `knowledge/` template lockstep sync from `plugin-claude-code/template/`
- Planning-path globs extended to `docs/superpowers/{plans,specs}/`
- `session-start-check.sh`: reads `scripts/aria/VERSION`, SESSION STATE resume directive, stale in-progress ledger sweep

### Intentional Cursor gaps (no native equivalent)

- `/statusline` + `usage-threshold-inject` — Claude Code CLI status line only
- Rule 22 `permissionDecision: deny` — advisory edit-intent marker only
- `PreCompact`/`PostCompact` transcript archival — use `stop` → `task-boundary-captures/` instead
- `SubagentStart` additionalContext into subagent — Cursor hook surface is weaker
- `/handoff` model+effort recommendation line — Claude Code model selection concept

## v2.24.2 — 2026-06-04

- **`/statusline` meter — per-account usage state + account email label (Claude Code only):**
  - **Why:** Running two Claude accounts on one machine (e.g. Desktop on one, CLI `/login`-switched to another) shared a single `~/.claude/aria-statusline-state.json`. Last-writer-wins meant the `usage-threshold-inject` hook could read the *other* account's usage and fire a false "5-hour at 100%" alert in a session that was actually fine. The meter also gave no way to tell which account a status-line window belonged to.
  - **What:** (1) The meter now writes its snapshot to a **per-account** file, `~/.claude/aria-statusline-state-<accountUuid>.json`, keyed by `oauthAccount.accountUuid` read from `~/.claude.json` (which updates on every `/login` switch). `usage-threshold-inject.sh` and the SessionStart TASK BUDGET guidance resolve the same key, so each session only ever reads its own account's usage — the false cross-account alert is gone. (2) The meter appends the full **account email** as the last status-line segment (`… │ you@example.com`), placed last so a width-truncated line clips only the email, never the usage. Both degrade cleanly: API-key users (no `oauthAccount`) fall back to a `default` key and render no email.
  - **Why `~/.claude.json`, not `claude auth status`:** the status-line payload carries no account field (verified against the docs); a file read avoids spawning the Node CLI on every render.
  - **Tests:** `tests/repros/statusline-usage.sh` → 35 cases (per-account write, account-correct inject incl. the cross-account false-alert repro, email-segment render, no-`oauthAccount` degrade).
  - **Ports:** **all four ports synced to v2.24.2 parity this release.** The statusline feature is Claude Code-only (no status bar in the other runtimes) and rides dormant where a port mirrors all skills. plugin-antigravity (2.20.2 → 2.24.2) and plugin-openai-codex (2.20.2 → 2.24.2-codex.0) take a full multi-version catch-up (subagent capture, SESSION.md, auto-prospect/retrospect — all port-tested green); plugin-cursor-template → 2.24.2-cursor.0 (version alignment — see its own entry); plugin-claude-cowork → v1.1.5 (skills-only: `/index` ephemeral-tag exclusion + `/wrapup` picker fix; statusline + hook features N/A).

## v2.24.1 — 2026-06-04

- **`/statusline` meter — model label trim + am/pm reset clocks (Claude Code only):**
  - **Why:** Two readability papercuts in the v2.24.0 meter. The model label rendered the full `Opus 4.8 (1M context)` — the ` context` word is redundant in a width-constrained status line. And the 7-day window showed only a bare percentage (`7d 12%`) with no reset time, while the 5-hour window's reset rendered in 24-hour `↺07:00` form.
  - **What:** (1) The model label trims a trailing ` context)` suffix → `Opus 4.8 (1M)`. (2) Both reset clocks now render in 12-hour am/pm form, dropping `:00` on the hour: `↺7am`, `↺1:30pm` (5h was 24-hour `↺07:00`). (3) The 7-day window now shows its reset as **weekday + time** (`7d 12% ↺Fri 1pm`), reading the newly-consumed `rate_limits.seven_day.resets_at` field — the weekday is the decision-relevant dimension for a days-away window, where the 5-hour window stays time-only. Graceful degrade preserved: a window present without `resets_at` still renders its percentage with no reset suffix.
  - **Portability:** am/pm formatting is normalized in-script (drop leading zero, drop `:00`, lowercase meridiem) because no BSD/GNU `date` format specifier produces it directly; `reset_clock` (time) is the single formatter and `reset_when` (weekday + time) reuses it. Verified under both `sh` and strict `dash`.
  - **Tests:** `tests/repros/statusline-usage.sh` grows to 26 cases (model trim, 5h/7d am/pm, on-the-hour `:00`-drop, off-the-hour minutes, no-`resets_at` degrade), TZ-pinned for determinism. Also fixes a latent harness bug surfaced by the new cases — `strip_ansi` used a `\033` literal that BSD sed (macOS) treats as inert, so ANSI was never actually stripped there (older assertions passed only because their needles were ANSI-free substrings); the ESC byte is now injected at runtime.
  - **Ports:** tracked drift — the status line is a Claude Code-only surface. Not ported.

## v2.24.0 — 2026-06-04

- **`/statusline` — CLI status-line meter (Claude Code only, opt-in):**
  - **Why:** No at-a-glance context-window or plan-usage readout existed in the CLI. `/context` and `/usage` are on-demand commands; a persistent meter answers "how full is context?" and "how much of my 5-hour window is left?" without typing.
  - **What:** New `bin/statusline-meter.sh` renders `model │ context-bar % │ 5h % ↺reset │ 7d %` from the Claude Code status-line JSON (`context_window.used_percentage`, `rate_limits.{five_hour,seven_day}.used_percentage`), with green/yellow/red thresholds. New `/statusline [on|off|status]` skill copies the script to `~/.claude/aria-statusline-meter.sh` (stable across plugin updates) and merges a `statusLine` block into `~/.claude/settings.json` (existing keys preserved, backup at `settings.json.aria-bak`, JSON validated post-write). `/help` + `CONFIG.md` updated.
  - **Agent awareness (the session's Claude can know its own usage):** the meter also persists a snapshot to `~/.claude/aria-statusline-state.json` on each render — the only path by which the agent can see context/5h/7d, since no hook payload carries it. Default is **on-demand**: the SessionStart TASK BUDGET guardrail now tells Claude to read the snapshot when judging budget / before `/handoff`/`/wrapup`/compaction (was previously "Claude can't see usage"). Additive **threshold alert**: new `bin/usage-threshold-inject.sh` (`UserPromptSubmit` hook) injects a warning when context/5h/7d crosses `usage_alert_threshold` (new config key, default 80, `off` disables), band-gated (once per 5-pt band, escalates, rearms on drop) so it never spams. The hook is a silent no-op until the meter is installed.
  - **Setup integration:** `/setup` gains Step 5b (offer to install/refresh the meter, delegating to `/statusline`) and surfaces `usage_alert_threshold` in Advanced Options + the config template + Step 7b round-trip.
  - **Constraint:** a plugin manifest cannot register a main `statusLine` (only `agent`/`subagentStatusLine` are plugin-defaultable), so this is a one-time opt-in command, not automatic. jq-preferred with a graceful model-only degrade; 5h/7d render only on Pro/Max sessions after the first response.
  - **Tests:** `tests/repros/statusline-usage.sh` (17 cases — meter render/degrade/rounding, snapshot write, threshold-inject fire/silence/band-gating/off/no-snapshot).
  - **Ports:** tracked drift — the status line is a Claude Code-only surface (Cowork is skills-only; Codex/Cursor/Antigravity are other runtimes). Not ported.

## v2.23.0 — 2026-06-04

- **Deterministic `SESSION.md` `in-progress` marking via first-edit piggyback (Claude Code only, gated on `session_state`):**
  - **Why:** v2.22.0 marked `in-progress` by emitting a soft SessionStart instruction for Claude to execute once the project resolved. It proved unreliable — Claude routinely prioritized the user's task and skipped the write, so atlas never showed "in session" (the `handoff`/`wrapup` states worked because they come from explicit skill runs).
  - **What:** new `bin/lib-session-state.sh` (`kt_ss_find_root` + idempotent, body-preserving `kt_ss_mark_inprogress`) is now invoked from the existing `post-edit-check.sh` (PostToolUse:Edit|Write) **after** the scope-check response. It derives the project from the **edited file path** (works even when cwd is the `~/Projects` root) and writes `lastEvent: in-progress` itself. Guarded **once per (session, project)** via a `/tmp/aria-session-inprogress-<key>` ledger (key = `session_id`, falling back to a `transcript_path` hash), so there is **no per-edit rewrite/churn** and **no added context output**. The write preserves `currentFocus`/`nextAction`/`by` and the entire body (including any `## Next session prompt`), refreshes `at`/`branch`/`headCommit`, and ensures `SESSION.md` is gitignored.
  - **SessionStart change:** `session-start-check.sh` keeps the resume-offer half of the SESSION STATE directive (it must run before the first turn) and **drops** the now-redundant in-progress-write instruction. Stale ledgers swept (>1 day) alongside `aria-active-*`.
  - **Two guards (found via live dogfooding before release):** (1) the hook **skips when the edited file is itself a `SESSION.md`** — otherwise it would clobber `/handoff` and `/wrapup`'s own writes, flipping their `handoff`/`wrapup` state back to `in-progress`. (2) `kt_ss_find_root` **rejects the projects container** (a direct child of `$HOME` whose `CLAUDE.md` is the master index, e.g. `~/Projects`) — otherwise a loose file resolves the root as a "project" and writes a spurious root `SESSION.md`.
  - **Read-only sessions** (no edits) are not marked in-progress by design — the board shows the manifest base status. Other 4 ports: tracked drift (cowork is skills-only, no PostToolUse).
  - New tests: `tests/repros/session-state.sh` (15 cases — root resolution, container-reject, fresh create, refresh-preserve-body, idempotency, gitignore).

## v2.22.3 — 2026-06-04

- **`/index` Step 4 — ephemeral-tag exclusion (Claude Code canonical):**
  - **Why:** Step 4 promoted ANY freeform tag at ≥`freeform_promotion_threshold` files (default 3) to Known Tags. Session/phase/plan stamps (`s82`×8, `s75`×6, `s60`/`s86`/`s88`/`s111`, `phase-3`, `p-23`) recur across files so they hit the threshold, but they are not durable concepts — they surfaced repeatedly as "NEEDS-MIKE" noise in the 2026-06-03 `/audit-knowledge` 70th/71st-pass `/index --deep` runs.
  - **What:** Step 4 now drops candidates matching ephemeral patterns before applying the threshold — `^s\d+$` (session stamps), `^p-?\d+$` (work-item ids), `^phase-?\d+$`, `^plan-\d+[a-z]?$`, plus a literal denylist (`future-session-plan`, `soft-launch`). Patterns empirically grounded against the live corpus: no `s3`/AWS-S3 collision exists and 1-digit session stamps (`s4`/`s5`/`s6`) are real, so `^s\d+$` (not `\d{2,}`) is correct.
  - **Safety:** suppresses AUTO-promotion only — not a hard ban. The skipped set is emitted as a one-line note (visible, not silent) so a genuine concept caught by a pattern can be hand-added to Known Tags (a Known tag never re-enters the freeform pool). No config field added (Rule 13 — the hand-add override + documented list cover it).
  - **Ports:** tracked drift — `plugin-openai-codex`, `plugin-claude-cowork`, `plugin-antigravity` (`skills/index/SKILL.md`) and `plugin-cursor-template` (`.cursor/rules/aria-context.mdc`) NOT re-synced this change (quality-of-life index tweak, not a correctness fix). Re-sync on the next port-parity pass.

## v2.22.2 — 2026-06-02

- **Auto-prospect & auto-retrospect hooks (Claude Code only, opt-in, default off):**
  - `post-plan-prospect-check.sh` (PostToolUse:Write) — when `auto_prospect` is `nudge`/`run`, a plan written to `docs/plans/` or `docs/superpowers/plans/` offers/runs `/prospect file <path>`. `docs/specs/` excluded.
  - `post-push-retrospect-check.sh` (PostToolUse:Bash) — when `auto_retrospect` is `nudge`/`run`, a `git push` of ≥`retrospect_min_commits` commits to a `retrospect_branches` branch offers/runs `/retrospect range <old>..<new>`. Parses the range from `tool_response.stderr`; skips force-pushes, no-ops, below-threshold, and off-branch pushes.
  - New config keys: `auto_prospect`, `auto_retrospect`, `retrospect_min_commits`, `retrospect_branches`. Surfaced in `/setup`.
  - Other 4 ports: tracked drift (not re-synced).

## v2.22.1 — 2026-06-01

**SESSION.md producer — dogfood fixes (Claude Code only).** Two defects caught by running `/wrapup auto` against the installed v2.22.0:

- **Project resolution at a multi-project root.** `/wrapup` Step 1 (and `/handoff` via inheritance) now disambiguates: when cwd resolves to a workspace/multi-project root (e.g. `~/Projects`), it infers the active project from session context (files edited, repos committed, project named) instead of writing `SESSION.md` at the projects-root. Mirrors the SessionStart re-entry instruction's "which project" signal.
- **`SESSION.md` is gitignored, never committed.** The producer (`/wrapup` Step 6.5, `/handoff` 3f, the SessionStart instruction) now appends `SESSION.md` to the project's `.gitignore` (if a git repo and not already ignored) and never stages it — it's ephemeral per-session state read from disk by atlas; PROGRESS.md remains the durable narrative. Avoids multi-session churn/conflicts.

## v2.22.0 — 2026-06-01

**SESSION.md producer (Claude Code only).** Per-project `SESSION.md` current-state snapshot across the session lifecycle, gated by a new `session_state` config key (default **off**, surfaced in `/setup`).

### Added

- **`/wrapup`** writes a `wrapup`-state `SESSION.md` (Step 6.5) — blank next-session prompt.
- **`/handoff`** writes a `handoff`-state `SESSION.md` (draft 3f) — the next-session opener embedded **verbatim** in the `## Next session prompt` block (single source: same opener as the closing report).
- **`bin/session-start-check.sh`** injects a flag-gated SESSION RE-ENTRY instruction: after the project resolves, offers resume from a saved prompt (auto-resume when the project utterance includes `handoff`), then **light-touch-marks** `in-progress` (refreshes the header, preserves prior body).
- New `session_state` config key in `bin/config.sh` (default `false`, validated `true`/`false`); `/setup` surfaces it (Advanced Options bullet + Step 7 template + Step 7b round-trip; Step 7e auto-covers it via config.sh derivation).
- Contract: `aria-atlas/docs/TEMPLATE_SESSION.md` — three lifecycle states (`in-progress` / `wrapup` / `handoff`). Consumer: **aria-atlas** (read-only; never writes the file).

### Scope

- **plugin-claude-code only.** Codex / Cursor / Cowork / Antigravity ports NOT re-synced — tracked drift (the read-side is a SessionStart hook; per-runtime support unverified, Cowork is skills-only).
- The live-session JSON registry (`aria-atlas-sessions.json`) is intentionally **not** implemented (removed from aria-atlas; SESSION.md is now the single session-status source).

## v2.21.0 — 2026-05-31

**Subagent knowledge capture.** Knowledge generated inside subagent execution was being lost — only a subagent's final message returns to the parent, so its full transcript (discoveries, dead-ends, decisions) was discarded. This release captures it, under the standard capture → govern → promote model.

### Added — A-side: `SubagentStop` transcript archive (plugin-claude-code)

- New `bin/subagent-stop-capture.sh` (registered on `SubagentStop`) copies a finishing subagent's **own** transcript (`agent_transcript_path`, not the parent's `transcript_path`) into a new `intake/subagent-captures/` folder, gated to configured heavyweight `agent_type`s.
- **Sticky retention:** captures are body-preserved until an extraction processes them — never cleared on sight (distinct from pre-compact snapshots). `/audit-knowledge` gains a Step 2e (digest/detailed/skip, no bare-clear); `/extract` gains a Step 2.5 sweep that folds pending captures into its buckets and ledger-clears the processed ones.
- `/setup` creates/repairs `intake/subagent-captures/`; `template/intake/subagent-captures/.gitkeep` ships.

### Added — B-side: `SubagentStart` self-report (plugin-claude-code)

- New `bin/subagent-start-selfreport.sh` (registered on `SubagentStart`) injects a "surface durable findings before returning" instruction into configured routine `agent_type`s (default `Explore`), so their findings ride back in the return message for the parent's `/extract`. Validated empirically (2026-05-31) that `SubagentStart` `additionalContext` reaches the subagent's own context.

### Added — config keys

- `subagent_capture` (master toggle, default `true`, also gated by `auto_capture`), `subagent_capture_types` (archive set), `subagent_selfreport_types` (self-report set).

### Fixed

- `/wrapup` description no longer contains the word "handoff" (it referenced `/handoff` as the alternative). The skill picker matches on description, so typing `/aria-knowledge:handoff` surfaced `/wrapup` first. Reworded to keep the "not for passoff" anti-trigger without naming the skill.

### Scope

- plugin-claude-code only this release. Codex / Cursor / Antigravity ports deferred (each runtime's `SubagentStart`/`SubagentStop` support must be verified first).

## v2.20.4 — 2026-05-30

**`/handoff` next-session opener now recommends a model + effort.** The current session — which has the most context about what comes next — emits a one-line posture recommendation for the next session.

### Added — `Suggested next session:` line in the opener (plugin-claude-code)

- `skills/handoff/SKILL.md` Step 3e: the next-session opener template gains a `Suggested next session: {model · effort}` line (with a one-line rationale) directly under the `Resume …` line. Applies to **default + auto modes only** — brief mode (coworker prose, no resume mechanics) is unchanged.
- A rubric maps the next session's hardest first action → model + effort (`Opus · xhigh` for novel/ambiguous/high-stakes work down to `Sonnet · medium` for mechanical execution and `Haiku` for trivial lookups; `opusplan` when planning is the hard part).
- **De-versioned:** the line names only the model family (`Opus`/`Sonnet`/`Haiku`) — a bare family name denotes the latest version, so the rubric never goes stale on a model release (consistent with v2.20.3's de-versioning of shipped model references).
- The line is advisory (user selects via `/model` + `/effort`); it does not auto-set the model. Because Step 8 already echoes the full opener, the line reaches both the user (in the report) and the next Claude instance (on paste) with no second render site.
- Rules section documents the always-on invariant.

### Scope

- **Claude Code only.** Effort/model selection is a Claude Code concept that does not map cleanly to every runtime. The cursor / codex / antigravity / cowork ports are **not** re-synced in this release — a tracked follow-up, consistent with the v2.20.3 scoping precedent.

## v2.20.3 / cowork v1.1.4 — 2026-05-29

**Opus 4.8 readiness.** Hardens Rule 22 enforcement for the current model generation and de-versions stale model references that shipped to users.

### Changed — Rule 22 PreToolUse hook (plugin-claude-code)

- **Loud fail-open** (`bin/pre-edit-check.sh`): when the compliance detector can't evaluate an edit (`unknown` — a transcript/schema/runtime failure, which the model cannot reach by reasoning), the hook still allows the edit (no v2.10.5-style deadlock) but now emits a visible warning `systemMessage` so enforcement is never lost *silently*. Determinate marker-absent — including a marker placed only in a thinking block — still denies.
- **Planning-path fix** (`bin/pre-edit-check.sh`): the planning-path glob now recognizes `docs/superpowers/{plans,specs}`, so plan/spec docs get the abbreviated `[Rule 22 · Planning]` variant instead of being misclassified as full-impact edits.

### Added — regression guards

- `tests/repros/4-8-thinking-and-failopen.sh` + fixtures: lock the marker-must-be-visible-text deny contract, the loud fail-open, and the planning-path classification, so a future model/harness change fails a test instead of bricking the editor.

### Changed — de-versioned stale model references

- `/help` Model Recommendations table: capability tiers (Highest-capability Opus / Sonnet mid-tier) replace pinned "Opus 4.6 (1M context)" / "Sonnet 4.6"; exclusion reworded to "below Sonnet-equivalent capability."
- SessionStart MEMORY PATHWAY injected message + two present-tense comments: model-agnostic wording instead of "enhanced in 4.7."
- `working-rules.md` (both ports): the Rule "Why:" clause de-versioned to "modern Claude models'." Historical Origin / 4.7 references intentionally preserved (they document why the code is shaped as it is).

### Pending follow-up

- Downstream ports (cursor / codex / antigravity) mirror the canonical `/help` table, `working-rules.md`, and (codex/antigravity) the hook scripts. They are **not** re-synced in this release — scoped intentionally to Claude Code + Cowork. Re-sync via `port-skills-to-mdc.py` + `release-cursor.sh`, `release-codex.sh`, and `plugin-antigravity/build.sh` is a tracked follow-up.

## Cursor port 2.20.2-cursor.0 — 2026-05-27

**Cursor port parity pass** — brings `plugin-cursor-template/` to equivalent coverage with `plugin-claude-code` v2.20.2. Independent version file: `plugin-cursor-template/scripts/aria/VERSION`. Release artifact: `aria-knowledge-cursor-2.20.2.zip` via `./release-cursor.sh`. No changes to the canonical Claude Code plugin in this pass.

### Added — maintainer re-sync tooling

- `plugin-cursor-template/scripts/port-skills-to-mdc.py` — compiles canonical `SKILL.md` bodies into `.cursor/rules/aria-commands.mdc`; strips ADR-094 Runtime Gate blocks; adapts paths for Cursor (`AGENTS.md`, `.cursor/aria-knowledge.local.md`, Cursor Settings → MCP); idempotent upsert for MCP skill sections.

### Added — five MCP skills in Cursor `.mdc`

Compiled into `aria-commands.mdc` (Cursor-adapted, no per-skill Runtime Gates):

- `/clip-thread`, `/extract-doc`, `/meeting-notes`, `/digest`, `/sync-decisions`

### Added — `/intake doc` mode in Cursor

Doc-mode steps D1–D6 from canonical `intake/SKILL.md` now present in `aria-commands.mdc`.

### Changed — v2.20.2 wrapup/handoff invariants mirrored

- `/wrapup`: Wrapup Checklist, Session Wrapup Complete, ALWAYS invoke `/extract` in auto mode (no judgment-skip).
- `/handoff`: ALWAYS invoke `/extract` in default + auto (brief mode carveout preserved).

### Changed — `/extract` project detection prose

Longest-matching `projects_list` path wins (aligned with `scripts/aria/config.sh` v2.19.2 fix).

### Changed — docs

- `plugin-cursor-template/PORTING.md` — sync status @ 2.20.2, maintainer workflow.
- `plugin-cursor-template/AGENTS.md`, `QUICKSTART.md` — command table + session-end behavior.
- `CLAUDE.md` — Cursor Port section + updated project structure and workflow.
- `README.md` — Cursor install blurb + ports table version note.

### Intentional Cursor divergences (unchanged platform limits)

- No ADR-094 per-skill Runtime Gates (preamble-only note).
- Advisory Rule 22 via edit-intent marker (no transcript deny).
- No bundled `.mcp.json` — MCP via Cursor Settings.
- `task-boundary-captures/` via `stop` hook instead of PreCompact transcripts.

## v2.20.2 — 2026-05-25

**Patch release — two latent wrapup/handoff spec bugs surfaced post-v2.20.1.** Coordinated with aria-cowork v1.1.3 + antigravity rebuild. No new skills, no schema changes, no MCP changes. Pure content fixes in `/wrapup` + `/handoff` skill bodies. Both bugs were latent since v2.19.0 (2026-05-19 intent split) — invisible across every auto-mode wrapup/handoff session for 6 days until Mike named them at the v2.20.1 release wrapup.

### Fixed — `/wrapup` closing report uses correct heading + checklist

Bug 1: `plugin-claude-code/skills/wrapup/SKILL.md` Step 7 + Step 9 carried "Handoff" labels from pre-v2.19.0 when `/wrapup` was the only end-of-session skill (and "handoff" was the natural closing-report label). The v2.19.0 intent split made `/handoff` distinct from `/wrapup`; the skill names became precise but the internal template strings inside the wrapup body stayed pre-split. Result: every `/wrapup auto` since v2.19.0 has emitted `## Handoff Checklist` and `## Session Handoff Complete` — confusing labels at the moment when distinct intent matters most.

Fixed:
- `## Step 7: Verify Handoff Readiness` → `## Step 7: Verify Wrapup Readiness`
- `## Handoff Checklist` → `## Wrapup Checklist` (inside the rendered output template)
- `## Session Handoff Complete` → `## Session Wrapup Complete` (closing-report heading)
- Added clarifying paragraph below Step 9 contrasting the two skills' closing headings explicitly

Mirror applied to `plugin-claude-cowork/skills/wrapup/SKILL.md` (cowork's intent split shipped in v1.1.0, same date as aria-knowledge v2.19.0 — same labeling drift).

### Fixed — `/extract` always runs under auto mode (no judgment-skip)

Bug 2: `plugin-claude-code/skills/wrapup/SKILL.md` Step 8 used procedural language `**If mode = auto:** invoke the /extract skill without prompting.` — read literally, this is correct, but a model running auto-mode through Step 8 could rationalize skipping (e.g., "session was short, nothing new to extract") because the spec didn't explicitly forbid that judgment surface. Same shape in `plugin-claude-code/skills/handoff/SKILL.md` Step 6: `Invoke /extract programmatically...` permitted similar rationalization. Result: across multiple recent auto-mode sessions, `/extract` was occasionally skipped — losing session knowledge irrecoverably, which is the exact failure mode ARIA is built to prevent.

Fixed with imperative + anti-rationalization phrasing:
- Wrapup Step 8 auto-mode now reads: `ALWAYS invoke the /extract skill. No judgment-skip allowed — even if the session feels short, conversational, or seems to have nothing new to extract, run /extract anyway.` Plus explicit "extract always runs" rule + post-yes auto-run rule for gated mode.
- Handoff Step 6 rewritten with the same `ALWAYS invoke` + anti-rationalization clause covering default + auto. Brief-mode carveout note preserved (brief mode never reaches Step 6).

Mirror applied to cowork wrapup Step 8 + cowork handoff Step 6 (using `/aria-cowork:extract` namespaced form). Same auto-mode invariant established across both ports + both skills.

### Auto-mode invariants — design pattern named

ADR-094 §Part 3 (shipped v2.19.1 / revised v2.20.1) carved a single explicit exception to auto-mode's "implicit-yes" rule: the runtime-mismatch gate must always prompt. v2.20.2 ships the inverse exception: `/extract` under auto mode is always-invoked, no judgment-skip permitted. Both are instances of a shared pattern: **auto-mode invariants** — surfaces where auto's default behavior is overridden in a specific direction (always run / always ask / always skip) to protect a load-bearing semantic. Document each invariant explicitly so the model can't rationalize around it. Worth promoting to a working-rule or approach doc at a future audit.

### Antigravity rebuild

`plugin-antigravity/` rebuilt from canonical via `build.sh`. v2.20.1's strip rules (trailing parenthetical + entire Runtime Gate body section) continue to apply unchanged; v2.20.2's Step 7+8+9 + Step 6 fixes propagate cleanly to antigravity skills.

### Coordinated release pairing

- **aria-cowork v1.1.3** (released 2026-05-25 same day) — companion release; mirror fixes shipped to cowork's `/wrapup` + `/handoff`. See cowork CHANGELOG v1.1.3 entry.
- **Cursor port 2.20.2-cursor.0** (released 2026-05-27) — mirror of wrapup/handoff invariants + full v2.18 MCP skill surface in compiled `.mdc`. See Cursor port changelog entry above.

## v2.20.1 — 2026-05-25

**Patch release — bare-slash gate UX revision (ADR-094 §Part 1/2/3 revision).** Coordinated with aria-cowork v1.1.2. No new skills, no schema changes. The 24 colliding dual-port skills get a UX refresh of the description format + Runtime Gate question + on-yes mechanism per the 2026-05-24 ADR-094 revision. Closes 4 carry-forward items from the 2026-05-24 maintenance idea file.

### Changed — description format (Strategy 1 trailing parenthetical)

The leading `**Bare-slash canonical (Claude Code).**` boilerplate (~60-80 words of ADR-094 narrative) is stripped from each Code-side skill description. Port-identification moved to a compact trailing parenthetical:

- Code-side: `(Claude Code variant — bare-slash canonical when both ports loaded; see ADR-094.)`
- Cowork-side: `(Cowork variant — namespaced-only.)` (short form, see Cowork SKILL_CAP note below).

Skill purpose now leads in every UI surface (`/help`, Claude Desktop plugin browser). Description-level model routing signal preserved by trailing port-id — the model reads the full description field; only UI truncation hides the parenthetical from human browsing.

Also closes a real Item 4 audit gap on the Cowork side: ADR-094 §Part 1 specified a `Namespaced-only` clause + `Do NOT match bare /X` anti-trigger that v2.19.1 implementation didn't carry on cowork descriptions (0/24). v2.20.1 restores both surfaces: the description-level "namespaced-only" routing signal in the trailing parenthetical, plus the verbose ADR-094 narrative + explicit "Do NOT match bare /X" anti-trigger in each skill's Runtime Gate body preamble.

**Cowork SKILL_CAP constraint:** aria-cowork's release.sh enforces a 9000-char hard cap on summed SKILL.md description chars (empirical install-fail at 9233, documented v0.2.1 + v1.0.0). The long-form trailing parenthetical used on the Code side would push cowork to ~10335 chars (over cap). Cowork uses the short form `(Cowork variant — namespaced-only.)` to stay under cap; the verbose ADR-094 reference + "Do NOT match bare /X" anti-trigger live in the Runtime Gate body preamble where no cap applies.

### Changed — Runtime Gate question inverted + Skill-tool auto-redirect on yes

`## Runtime Gate (per ADR-094)` body section in each colliding skill gets three updates:

1. **Canonical resolution preamble** — opens with `**Canonical resolution:** This is the [Code/Cowork] variant. ...` paragraph re-stating cross-port routing (replaces the leading-clause narrative that previously lived in `description:`).
2. **Question inverted** — `Proceed with the [variant] anyway? (y/n)` → `**Use /[correct-variant] instead?** (y/n)`. Default-yes is now "fix it for me" instead of "proceed with wrong port".
3. **Skill-tool auto-redirect on yes** — on `y`, the skill uses Claude's `Skill` tool to invoke the correct-port variant with the same arguments the user originally provided. Auto-redirect runs the correct skill to completion; wrong-port skill exits without executing.

The `n` path preserves the opt-in-anyway escape; no-response is fail-closed exit.

### Changed — auto-mode friction analysis (§Part 3)

ADR-094 §Part 3's "auto-mode is NOT exempt from the runtime gate" principle is preserved unchanged. The friction analysis is updated to reflect that auto-redirect on `y` lowers the gate's cost from "manually re-invoke" to "~1 keystroke" — the gate still catches accidental wrong-variant invocations under `auto`, but the safety check is now near-zero cost in the common case.

### Added — ADR-094 Revision history + Validated By

ADR-094 (`knowledge/projects/aria/decisions/094-bare-slash-canonical-owner-and-dual-runtime-gate.md`) gains a Revision history section documenting the three surface changes and a populated Validated By section with two entries: 2026-05-23 initial implementation + 2026-05-25 revision/closure session. Skill-tool chaining empirical behavior is flagged as the residual unknown pending runtime spot-test (see Validated By).

### Docs sync

- `README.md` — added `Last reviewed: 2026-05-25` footer.
- `plugin-claude-code/README.md` — added `Last reviewed: 2026-05-25` footer.
- `plugin-claude-cowork/README.md` — bumped Status block from v1.0.0 → v1.1.1 (later → v1.1.2 in this release); added "What's new in v1.1.1 / v1.1.0 / v1.0.1" sections above the existing v1.0.0 section; added footer.
- `plugin-claude-cowork/CONNECTORS.md` — 2 stale `v0.4.0` references (pre-1.0 codename) bumped to current.

### Coverage

- 48 SKILL.md files changed (24 dual-port skills × 2 ports including 2 alias pairs).
- 44/44 canonical-resolution preambles (22 non-alias × 2 ports).
- 44/44 inverted-question gates.
- 44/44 Skill-tool auto-redirect mentions.
- 48/48 trailing parentheticals.
- 0 boilerplate residue, 0 old "Proceed ... anyway" question residue.

### Empirical unknown

Whether a SKILL.md body's instruction to use the `Skill` tool to invoke another port's skill chains cleanly at runtime is not documented by Anthropic. If host plugin-loaders don't honor in-skill Skill-tool invocation across plugin boundaries, the auto-redirect on `y` silently fails to chain — the gate still works as a notification (user re-types the namespaced command). Risk is contained: worst case is a revert to the original "proceed anyway" UX. Documented as the residual unknown in ADR-094's Validated By.

## v2.20.0 — 2026-05-24

**Antigravity port parity pass.** Primary-source verification against `antigravity.google/docs/*` clippings closed all v2.19.2 Known Drift items + restored 3 behavioral parities lost in the initial port:

- **PreInvocation hook** restores automatic session-start, Rule 22 scope-check feedback to agent, and transcriptPath caching for skills
- **Overlay pattern** at `overlays/skills/` ships port-specific bodies for `/snapshot`, `/audit-knowledge`, `/audit-config` (canonical bodies depend on Claude-Code-specific filesystem layouts)
- **version.txt sidecar** since Antigravity plugin.json schema has no version field
- **Workflows surface** ships 10 thin-shim workflows for true slash-command invocation
- **Plugin-bundled rules** at `plugin-antigravity/rules/` exposes ARIA rules via Antigravity's Always-On rule activation

7 v2.20 arc commits (Phases A–E) + 2 v2.21 follow-up commits (workflows + rules).

Canonical Claude Code plugin: no behavioral changes; version bumped synchronously for release coordination.

### Repository consolidation

`aria-cowork` (previously `mikeprasad/aria-cowork`, last standalone release v1.1.1) is now `plugin-claude-cowork/` inside `mikeprasad/aria-knowledge`. Full git history preserved via subtree import. The aria-cowork repo is archived with a redirect README pointing here. Renames applied across all ports:

- `plugin/` → `plugin-claude-code/`
- `plugin-codex/` → `plugin-openai-codex/`
- `cursor-template/` → `plugin-cursor-template/`
- aria-cowork repo → consolidated into `plugin-claude-cowork/` via git subtree (full history preserved)

5 active ports in this repo, all sharing the canonical `~/Projects/knowledge/` schema.

## [2.19.2] - 2026-05-24

**Patch release — `kt_project_for_path` longest-match-wins fix.** No new skills, no schema changes. Fixes a silent mis-tag bug for nested sub-project configs.

### Fixed — `kt_project_for_path` no longer shadows nested sub-projects

`bin/config.sh:kt_project_for_path` previously iterated `KT_PROJECTS_LIST` with first-match-wins substring matching — so for nested configs like `aria:aria,aria-core:aria/aria-core`, any CWD inside `aria/aria-core/` would mechanically match the `aria:aria` entry first and return `aria` (the workspace), shadowing the `aria-core` sub-project tag. The bug was masked when the markdown-driven `/extract` skill ran, because the skill body inferred project from conversation context — but any bash-driven consumer (hooks, audit-config, automation scripts) would mis-tag.

Fix: walk the entire list and return the tag whose configured path is the **longest** substring match of CWD. Backward-compatible — flat single-project configs are unaffected (only one entry ever matches → it's also the longest by definition).

**Files:**
- `plugin-claude-code/bin/config.sh` — Claude port
- `plugin-openai-codex/bin/config.sh` — Codex port
- `plugin-cursor-template/scripts/aria/config.sh` — Cursor port

All 3 ports' `kt_project_for_path` function bodies remain byte-identical post-fix (verified via `diff`).

### Reproducer (closed)

Reported via `/extract` 2026-05-24 — `[insights-backlog.md]` and `[intake/ideas/2026-05-24-cross-projects-list-longest-prefix-or-path-anchored-matching.md]`.

## [2.19.1] - 2026-05-23

**Patch release — bare-slash namespace ownership + dual runtime gate (ADR-094).** No new skills, no schema changes. 24 colliding skill names between aria-knowledge and aria-cowork now have deterministic routing when both plugins are loaded in the same session (most common in Claude Desktop).

### Changed — bare-slash canonical owner clarified

When both aria-knowledge and aria-cowork are loaded, bare slash commands (`/handoff`, `/wrapup`, `/extract`, etc.) now deterministically resolve to **aria-knowledge** (the canonical Code-side variant). The 24 affected SKILL.md descriptions in `plugin-claude-code/skills/` get a prepended canonical-owner clause asserting bare-slash ownership. For the Cowork variant, users invoke the namespaced form (`/aria-cowork:handoff`, etc.) — which remains available everywhere.

### Added — Runtime Gate section per skill

Each of the 24 colliding skills carries a new `## Runtime Gate (per ADR-094)` section in its body. The gate fires at invocation time and checks tool availability (Bash presence) as the runtime fingerprint:

- If a Code-canonical variant is invoked from a non-Code runtime (no Bash, e.g., Cowork) → surface a notification suggesting the Cowork-variant invocation. User confirms before proceeding.
- Each gate is **informational, not blocking** — the user might legitimately be using both runtimes.
- **Gate applies even when invoked under `auto` semantics** — auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check per ADR-094 §Part 3. Other auto-mode gates remain bypassed.

### Coordinated with aria-cowork v1.1.1

Same-day coordinated patch pair. aria-cowork v1.1.1 ships the inverse-direction edits — its 24 colliding skill descriptions get a namespaced-only clause + removal of bare-slash triggers + a Cowork-side Runtime Gate (which fires when Bash IS present, suggesting the Code-canonical invocation).

### Codex + Cursor ports

Plugin-codex port mirrors the aria-knowledge SKILL.md edits byte-faithfully (ADR-087 — Codex is an independent runtime with shared schema). Cursor port adds a single ADR-094 namespace-policy cross-reference at the top of `aria-commands.mdc` rather than 24 per-skill sections, preserving the cursor port's "proportionate compression" philosophy (ADR-092).

### Compatibility

- **No breaking changes.** Existing namespaced invocations (`/aria-knowledge:X`, `/aria-cowork:X`) continue to work everywhere unchanged.
- **User-visible change for Cowork-only users (no aria-knowledge installed):** bare `/handoff` etc. no longer matches aria-cowork's variant in that configuration — must use the namespaced form. Documented in README.

### Full ADR

See [ADR 094 — Bare-slash canonical owner + dual runtime gate for sibling plugins](https://github.com/mikeprasad/knowledge/blob/main/projects/aria/decisions/094-bare-slash-canonical-owner-and-dual-runtime-gate.md) for the full reasoning, alternatives considered, and per-skill ownership matrix.

## [2.19.0] - 2026-05-19

**Minor release — `/wrapup` vs `/handoff` intent split clarified; `/wrapup auto` mode added.** No new skills, no template changes, no MCP changes, no schema additions. Two existing skills (`/wrapup`, `/handoff`) get a behavioral and documentation refactor that makes their distinct purposes unambiguous, plus `/wrapup` gains an `auto` mode mirroring `/handoff auto`. Cursor port catches up on the pre-existing `/handoff brief` mode drift in the same release.

### Changed — `/wrapup` and `/handoff` skill descriptions reframed by intent

Previously the two skills overlapped: both covered "end-of-session" with `/handoff` framed as "/wrapup + opener." Users couldn't tell from the descriptions which to use, and the auto-invocation triggers competed. The refactor splits them by **audience**, not posture:

- **`/wrapup`** is now the "I'm done, no passoff" skill — close out cleanly, no next-session opener emitted. Title in body changed from "Session Handoff" to "Session Close-Out" to reinforce the intent.
- **`/handoff`** is now the "passoff package" skill — for future-you in a new session (typically when context is high and you need to restart) or for a coworker (via `brief` mode). The paste-ready next-session opener is the **headline artifact**, always emitted in default + auto modes regardless of whether other surfaces changed.

Same surfaces touched (PROGRESS / CLAUDE / memory / git commit / `/extract`); different framing and different headline output. Description trigger phrases extended with passoff-explicit phrases ("context is full, restart this", "pass off to next session") and done-explicit phrases ("I'm done", "close out", "saying goodbye") to improve auto-invocation accuracy.

The canonical `/handoff` body intro was also tightened: removed the "Same end-of-session coverage as /wrapup" framing that read as superset; replaced with passoff-led framing that names the next-session opener as the headline artifact.

### Added — `/wrapup auto` mode

Mirrors `/handoff auto`: implicit-yes on all per-step gates (session summary, PROGRESS, CLAUDE.md, memory, commit, `/extract`), runs silently, emits final report only. Invoke as `/wrapup auto`. Use when the session is short and unambiguous, or when a combined-go signal (`yes to all`, `yes to all with extract`) has already been given.

`argument-hint` extended from `""` to `"[auto]"`. The Step 0 mode parse follows the same `gated`/`auto` pattern `/handoff` already uses, so the two skills' auto modes feel identical at the user level. Local commit only — auto mode never pushes (existing rule preserved + reinforced in the wiring).

### Added — `/handoff brief` mode in cursor port

The cursor port's `.cursor/rules/aria-commands.mdc` was pre-existing-drifted on `/handoff brief` — it documented Two modes when canonical had shipped Three modes since v2.17.0. v2.19.0 catches the cursor port up: brief bullet added to the modes list, Step 0 parse extended to recognize `brief`, new Step 2B section added at proportionate compression matching the rest of the cursor port. AGENTS.md naming preserved throughout.

### Compatibility

- **No breaking changes.** Existing `/wrapup` invocations (no arg) continue to behave exactly as before — gated, per-step prompts. `auto` is opt-in via the explicit argument.
- **No new dependencies.**
- **`/handoff brief` schema unchanged** Code-side (shipped v2.17.0; cursor port is only catching up to existing canonical behavior).
- **No skill template changes.** Knowledge folder schema unaffected.

### Coordinated release pairing

- **aria-cowork v1.1.0** ships the same intent split + `/wrapup auto` mode Cowork-side. Per ADR-013, aria-knowledge remains the schema source-of-truth; cowork-side descriptions diverge (much shorter — 415/527 chars vs unconstrained Code-side) to satisfy Cowork's aggregate-bytes cap, but the behavior split and mode shape are byte-aligned.

### Surface area touched

- `plugin-claude-code/skills/wrapup/SKILL.md` + `plugin-openai-codex/skills/wrapup/SKILL.md` (byte-identical) — frontmatter description rewritten, `argument-hint` set, Step 0 + 6 gates + Rules section updated for mode-conditional behavior.
- `plugin-claude-code/skills/handoff/SKILL.md` + `plugin-openai-codex/skills/handoff/SKILL.md` (byte-identical) — frontmatter description rewritten + body intro tightened (passoff-led framing).
- `plugin-cursor-template/.cursor/rules/aria-commands.mdc` — `/wrapup` and `/handoff` sections updated for parity (AGENTS.md naming preserved); brief mode added.
- `plugin-claude-code/.claude-plugin/plugin.json` + `plugin-openai-codex/.codex-plugin/plugin.json` + `.claude-plugin/marketplace.json` — version bumps.

## [2.18.1] - 2026-05-19

**Patch release — `.mcp.json` directory-entry-name fix + companion prose alignment.** No skill changes; no schema changes. Surface area touched: `.mcp.json` (both `plugin/` and `plugin-openai-codex/` ports) + prose mentions across CHANGELOG, 4 SKILL.md files in each port. Coordinated with aria-cowork v1.0.0 release (2026-05-19) which fixed the same underlying bug Cowork-side, where it manifested as install failure.

### Fixed — `.mcp.json` `google_docs` → `google docs`

Both `plugin-claude-code/.mcp.json` and `plugin-openai-codex/.mcp.json` declared `"google_docs"` (underscore) with an empty `url` for the Google Docs MCP server. The canonical Cowork directory-entry name uses a space: `"google docs"`. Per the Cowork plugin-customizer schema reference (`cowork-plugin-management/skills/cowork-plugin-customizer/references/mcp-servers.md`), servers with empty `url` must match a directory entry name *exactly* to validate — the underscore form silently fails Cowork's server-side validator. **Invisible bug Code-side** (Code's MCP client doesn't validate against Cowork's directory) but parity-preserving for ADR-013's byte-faithful intent against the Cowork sibling. Fix applied to both ports; prose mentions of `google_docs` across SKILL.md frontmatter enum docs + CHANGELOG swept to `google docs` for internal consistency with the new manifest key.

### Companion: aria-cowork v1.0.0 fix arc (informational)

aria-cowork v1.0.0 hit the same `google_docs` bug PLUS a second undocumented Cowork constraint — an aggregate-bytes cap (~9 KiB, working answer 9,216 = 9 KiB) on the summed `description` fields across all `skills/*/SKILL.md`. v1.0.0's 6 new MCP-consuming skills tipped the aggregate from v0.3.0's 7,645 chars to 10,404 chars, tripping the cap. **aria-knowledge is unaffected by the description cap** because Code-side installs don't run Cowork's server-side validator, but the cap is documented in `~/Projects/knowledge/guides/claude/cowork-plugin-validation.md` "Key Constraint 2" with the full empirical bisection trail (Probes A-K, ~2.5 hours). ADR-013 now lists "SKILL.md description length" as the 4th axis of cowork-side allowed divergence from aria-knowledge — manifest-level, not per-skill body, and only applies Cowork-side.

### Compatibility

- **No breaking changes.** Existing v2.18.0 installs upgrade in-place. No skill bodies modified; no template changes; no schema additions.
- **No new dependencies.**
- **MCP runtime behavior unchanged.** The `google_docs` → `google docs` rename only affects how Cowork's directory lookup matches the entry; Code-side MCP clients treat both forms as opaque server names.

### Coordinated release pairing

- **aria-cowork v1.0.0** (released 2026-05-19) — companion release. Same `.mcp.json` fix Cowork-side, plus the description-length sanitization noted above. aria-cowork-side this was a blocker (install failed); aria-knowledge-side this is purely parity hygiene.

## [2.18.0] - 2026-05-18

**First MCP-consuming release. 5 new cross-tool skills + `.mcp.json` + `CONNECTORS.md` + 2 new architectural ADRs.** aria-knowledge gains a category of capability it didn't previously have — pulling from connected MCP servers (Slack, Notion, Linear, Gmail, etc.) and writing structured artifacts back into the knowledge folder. 5 new skills (clip-thread, extract-doc, meeting-notes, digest, sync-decisions) consume 4 `~~category` placeholders (chat / email / project tracker / docs) via the `~~` customization-marker convention from `cowork-plugin-management`. Minor bump because this is a structural-shift-by-addition: the manifest's new `.mcp.json` declaration is additive (existing installs without `.mcp.json` continue to work), but a whole external-integration surface arrives. Bidirectional flow continues — aria-cowork v1.0.0 ships shortly with 5/5 of these skills imported byte-faithfully + 1 cowork-only `daily-audit` skill per ADR-014.

### Added — `/clip-thread` skill

New skill at `plugin-claude-code/skills/clip-thread/SKILL.md`. Captures a chat or email thread from a connected `~~chat` (slack, ms365) or `~~email` (gmail, ms365) MCP into `intake/clippings/{YYYY-MM-DD}-{slug}.md`. Source-type detection by URL pattern (Slack archives, Teams message links, Gmail thread IDs, MS365 message IDs). 50-message cap with truncation notice. Per-message structure preserves author + timestamp + body + reactions/attachments-noted. Reaction section left empty as user-fill slot (matches `/intake doc` precedent from v2.17.0).

### Added — `/extract-doc` skill

New skill at `plugin-claude-code/skills/extract-doc/SKILL.md`. Pulls insights from a single Notion / Confluence / Google Doc / Box / Egnyte page via `~~docs` MCP. **Differs from `/intake doc`** (v2.17.0): `/intake doc` captures one structured artifact per doc; `/extract-doc` decomposes a doc into N intake-backlog entries for audit routing. 5 standard intake categories (insight / decision / extraction / idea / reference). 20KB extraction cap with truncation notice. Default fewer-but-stronger ranking discipline.

### Added — `/meeting-notes` skill

New skill at `plugin-claude-code/skills/meeting-notes/SKILL.md`. Folds a meeting transcript into `intake/meetings/{YYYY-MM-DD}-{slug}.md` with structured participants / topics / action items / decisions / open questions sections + raw transcript preserved verbatim. **Unique among Phase 2 skills:** offers a **paste fallback** when no `~~docs` MCP is connected (Granola exports, hand-typed notes, transcript paste-from-clipboard). The only skill in v2.18.0 that doesn't hard-stop on missing MCP. New `intake/meetings/` lazy-created subfolder convention.

### Added — `/digest` skill

New skill at `plugin-claude-code/skills/digest/SKILL.md`. Cross-tool rollup synthesizing what's pending / what shipped / what's blocked across `~~chat` + `~~email` + `~~project tracker` + `~~docs`. The composite-MCP skill — probes all 4 categories and degrades gracefully when partial connection (surfaces gap callouts in output). Time window args: `--week` (default), `--month`, `--quarter`, `--since YYYY-MM-DD [--until YYYY-MM-DD]`. Output to `intake/digests/{YYYY-MM-DD}.md` (lazy-created subfolder). Inspired by Anthropic's productivity plugin `update --comprehensive` mode, adapted for ARIA's intake-then-audit model.

### Added — `/sync-decisions` skill

New skill at `plugin-claude-code/skills/sync-decisions/SKILL.md`. **First WRITE-side skill in ARIA.** Mirrors approved decisions from `{knowledge_folder}/decisions/` out to a `~~docs` MCP destination (Notion page, Confluence space, Google Doc, Box/Egnyte file). Embeds the 4-step Rule 22 advisory preamble per ADR-016 with explicit per-decision go-gate (`Ready to write? (yes / no / edit)`). The only path to batch is the literal phrase `yes to all` per ADR-016's batch carve-out. Logs every sync attempt (success / skip / fail) to `logs/sync-decisions.md`. Adds new `synced_to_~~docs:` frontmatter field on synced decision files for sync-state tracking.

### Added — `plugin-claude-code/.mcp.json`

First time aria-knowledge ships an `.mcp.json` manifest. Declares 12 MCP servers across 4 categories — mirrors Anthropic's published `productivity/.mcp.json` shape:

| Category | MCPs declared |
|---|---|
| Chat | slack, ms365 |
| Email | gmail (placeholder URL), ms365 |
| Project tracker | linear, asana, atlassian, monday, clickup, notion |
| Docs | notion, atlassian, box, egnyte, google docs (placeholder URL) |

Slack ships with Anthropic's published OAuth config (clientId `1601185624273.8899143856786`, callbackPort 3118) — mirrored from productivity's manifest. Gmail + google docs ship with empty URLs (placeholder declarations per productivity's pattern, pending public MCP server availability).

### Added — `plugin-claude-code/CONNECTORS.md`

First time aria-knowledge ships a `CONNECTORS.md`. Documents the `~~category` marker convention per the canonical guidance from `cowork-plugin-management/skills/cowork-plugin-customizer/SKILL.md`. Four categories (chat / email / project tracker / docs) — a focused subset of productivity's 6 (we don't have calendar or office-suite skills). Per-skill MCP-usage table shows which `~~category` each new skill consumes + the fallback behavior. "What this plugin does NOT integrate with" section preempts confusion about calendar / office-suite / code-hosting omissions.

### Added — ADR-015 + ADR-016 (in `~/Projects/knowledge/projects/aria-cowork/decisions/`)

Two new ADRs lock the v2.18.0 design decisions:

- **ADR-015 — Capability-Probe Pattern (Prose-Only, No API).** Locks the `~~category` probe convention verified against productivity plugin reference: prose-only, no helper script, Claude's runtime tool list IS the probe, SKILL.md handles missing-MCP via explicit fallback prose. Composes with ADR-004 (no hooks in cowork) — Layer-1 + Layer-3 only.
- **ADR-016 — Rule 22 Advisory Preamble for External-Write Skills.** Locks the 4-step preamble + explicit `Ready to write? (yes / no / edit)` go-gate that all WRITE-side skills MUST embed. Applies to `sync-decisions` in v2.18.0; pattern is durable for future write-side skills. Composes with ADR-004 + v0.2.5 "Principles transfer, enforcement doesn't" framing.

Both ADRs include a **Stability and revision triggers** section acknowledging that the patterns derive from Anthropic-published Cowork plugins as of 2026-05-18 and may revise as future Anthropic releases ship new capability surfaces (formal capability-probe APIs, Cowork hook surface for MCP write tools, etc.).

### Schema impact

| Surface | Change | Compatibility |
|---|---|---|
| `plugin-claude-code/.mcp.json` | New file declaring 12 MCP servers | Additive — installs without `.mcp.json` continue to work (existing skills don't probe MCPs) |
| `plugin-claude-code/CONNECTORS.md` | New companion doc explaining `~~` markers | Additive — documentation only |
| `intake/clippings/` | Existing folder, new content shape (`<date>-<slug>.md` with thread structure) | Additive — `/clip-thread` writes alongside `/clip` outputs; no shape conflict |
| `intake/meetings/` | New subfolder, lazy-created | Additive — created on first `/meeting-notes` invocation |
| `intake/digests/` | New subfolder, lazy-created | Additive — created on first `/digest` invocation |
| `logs/sync-decisions.md` | New artifact, lazy-created | Additive — created on first `/sync-decisions` invocation |
| `synced_to_~~docs:` frontmatter field on decision files | New optional field | Additive — decisions without the field still work; `/audit-knowledge` ignores the field for routing |

### Cross-plugin parity (bidirectional flow continuing per ADR-014)

5/5 new skills are bidirectional per [ADR-014](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/014-bidirectional-feature-flow.md) row 3 — the cross-tool workflow problem exists in both Code and Cowork surfaces. Per ADR-013 (schema-source-of-truth), aria-knowledge ships first; aria-cowork v1.0.0 imports the 5 SKILL.md bodies byte-faithfully with only the Step 0 config-resolution path diverging per ADR-013's "input-discovery diverges per-surface; output-schema converges per-corpus" principle.

aria-cowork v1.0.0 also adds 1 cowork-only skill (`daily-audit` — first-message audit substitute since Cowork has no SessionStart hook per ADR-004). That skill does NOT ship in aria-knowledge.

Output schema is byte-identical across plugins per ADR-013. Both plugins write to the same shared `intake/clippings/`, `intake/meetings/`, `intake/digests/`, `logs/sync-decisions.md` paths in the user's `~/Projects/knowledge/` (or configured) folder.

### Files changed

- New: `plugin-claude-code/.mcp.json` (~50 lines, 12 MCP server declarations)
- New: `plugin-claude-code/CONNECTORS.md` (~80 lines, ~~category convention reference)
- New: `plugin-claude-code/skills/clip-thread/SKILL.md` (~155 lines)
- New: `plugin-claude-code/skills/extract-doc/SKILL.md` (~145 lines)
- New: `plugin-claude-code/skills/meeting-notes/SKILL.md` (~170 lines)
- New: `plugin-claude-code/skills/digest/SKILL.md` (~180 lines)
- New: `plugin-claude-code/skills/sync-decisions/SKILL.md` (~200 lines, Rule 22 preamble embedded)
- Modified: `plugin-claude-code/.claude-plugin/plugin.json` (version bump 2.17.0 → 2.18.0)
- Modified: `README.md` (skill list additions in Capture + Promote sections, MCP integration mention in Install)
- Modified: `CLAUDE.md` (Sibling Plugin section refreshed for v0.3.0 → v1.0.0 SHIPPED on disk; originally drafted as v0.4.0 + bumped to v1.0.0 mid-build per ADR-006 stability claim)
- Cross-knowledge: `~/Projects/knowledge/projects/aria-cowork/decisions/015-capability-probe-pattern.md` + `016-rule-22-advisory-preamble-for-external-writes.md` (new ADRs)

### Compatibility

- **No breaking changes.** Existing skills work unchanged. New skills are opt-in by invocation; no auto-fire hooks reference the new skills.
- **No new required config.** Existing `aria-knowledge.local.md` works unchanged. Future `default_sync_target:` field is optional (consumed only by `/sync-decisions`).
- **No new dependencies.** Pure markdown + the MCP runtime that Code already provides. `.mcp.json` is read by Code's MCP client; aria-knowledge doesn't build or host any MCP server itself.
- **Graceful degradation built-in.** If no MCPs are connected, all 5 new skills output a clear fallback notice and stop. `/meeting-notes` additionally offers a paste-fallback path.
- **MCP-consuming is opt-in.** Users who don't want any of the 5 new skills can ignore them; no behavior changes to the existing 23 skills.
- **Cowork sibling release coming:** aria-cowork v1.0.0 ships shortly with 5/5 bidirectional ports + the cowork-only `/daily-audit`.

### Known limitations

- **Slack OAuth clientId** is mirrored from productivity plugin's public manifest. May "just work" if Anthropic's Slack OAuth app covers third-party plugins; may require aria-knowledge to register its own Slack OAuth app if reality differs. Capability probe per ADR-015 will surface "No `~~chat` MCP connected" if Slack auth fails — degraded but not broken.
- **`gmail` and `google docs` MCPs ship with empty URLs** (placeholders, per productivity plugin's pattern). Will be populated when Anthropic's hosted Google MCPs go public. Patchable in v2.18.1 if/when that lands.
- **Probe semantics may evolve.** ADR-015 + ADR-016 explicitly note that future Anthropic releases (formal capability-probe API, Cowork MCP-aware PreToolUse hook) would trigger revision.

## [2.17.0] - 2026-05-18

**Two new mode flags on existing skills: `/handoff brief` + `/intake doc`.** Both originate as cross-plugin parity items from aria-cowork's v0.3.0 design discussion — this release implements them in aria-knowledge first (per the schema-source-of-truth principle), so aria-cowork's v0.3.0 port can import the templates byte-identical. Minor bump because of the new `intake/docs/` subfolder convention + new `intake-doc` frontmatter type — additive schema, no breaking changes.

### Added — `/handoff brief` mode

New mode flag on the existing `/handoff` skill: `/handoff brief` produces a copy/paste coworker brief (Hey [coworker]-style prose, 80-150 words, capped at 200) instead of the default mode's next-session opener. Different artifact, different audience — brief mode is for handing off to a person, not to a future session.

- **No side effects.** Unlike default and `auto` modes, `brief` skips PROGRESS.md / CLAUDE.md / memory / commit / `/extract` entirely. The brief is the only artifact.
- **`[coworker]` is a literal placeholder.** Users fill the recipient name at paste time — supports "send to multiple people" use cases without forcing an upfront prompt.
- **Sections:** "What happened" / "Key decisions" / "What's next" / "Where to pick up" (last line omitted if no concrete artifact reference applies).
- **Tone:** warm-but-professional default. No `casual` / `formal` variants in v2.17.0 (deferred unless demand emerges).
- **Users who want both:** run `/handoff brief` first, then `/handoff` (or `/handoff auto`) for the state-updating pass. Two invocations, two artifacts.

### Added — `/intake doc` mode

New mode flag on the existing `/intake` skill: `/intake doc <url-or-title-or-path>` captures a single doc with a structured 5-section body (claims / worth keeping / contested / action / reaction) instead of bulk scanning multiple sources.

- **New subfolder convention:** `{knowledge_folder}/intake/docs/{YYYY-MM-DD}-{slug}.md`. Lazy-created on first doc-mode capture (not bootstrapped on `/setup`).
- **New frontmatter type:** `type: intake-doc` plus `source_url` (optional), `source_title`, `source_author` (optional), `captured_at`, `read_at` (separate from `captured_at` so users can capture notes days after reading), `tags`, `semantic-hints`.
- **Body sections (D3 step):**
  - **What the doc claims** — central thesis or key argument in your own words
  - **Worth keeping** — durable insights / quotes / data points (2-6 bullets typical)
  - **Contested or unclear** — populated if scan surfaced debatable claims; omitted otherwise
  - **Action implied** — populated if doc suggests a decision or next step; omitted otherwise
  - **My reaction** — left as user-fill placeholder (the user's voice, not Claude's)
- **Source types accepted:** URL (WebFetch), file path (Read), or title-only (user fills body manually — valid use case for "notes while reading something offline").
- **Slug generation:** lowercased, hyphenated, max ~60 chars from source title. Collision handling: append `-2`, `-3` etc. if `{date}-{slug}.md` already exists.
- **Preview before write (D4 step):** populated entry shown for user confirmation; per-section `edit` directives allowed.

### Added — `plugin-claude-code/template/intake/intake-doc.md`

New plugin-managed template defining the 5-section body structure. Read by `/intake doc` Step D3 when populating new doc-mode captures. Single new file (~42 lines).

### Changed — `plugin-claude-code/skills/handoff/SKILL.md`

- Frontmatter `argument-hint`: `[auto]` → `[auto|brief]`; `description` updated to introduce three modes
- Step 0 mode parser: added `brief` branch; error message updated to mention all three modes
- New Step 2B (Brief Output): runs only when `mode = brief`; emits the prose brief via the locked template; exits without running Steps 3-8
- Rules section: scoped existing rules (e.g., "always emit next-session opener" qualified to default + auto only); added 3 brief-mode-specific rules (no side effects, literal placeholder, 200-word cap)

### Changed — `plugin-claude-code/skills/intake/SKILL.md`

- Frontmatter `argument-hint`: `<path|directory|glob|url> [path2] [path3]` → `[doc <url-or-title>] | <path|directory|glob|url> [path2] [path3]`; `description` updated to introduce both modes
- Step 0 renamed to "Resolve Config + Mode Detection"; doc-mode branch added at end of Step 0
- New Doc Mode Steps section (D1-D6) inserted before existing Step 1; runs to completion + exits when `mode = doc`
- Rules section: scoped existing rules to bulk vs doc mode; added 4 doc-mode-specific rules (reaction-is-user-voice, lazy subfolder creation, slug collisions, title-only captures valid)

### Changed — `plugin-claude-code/skills/help/SKILL.md`

- Existing `/handoff` row updated: `[auto]` → `[auto|brief]` with brief mode description appended
- New `/intake doc [url or title]` row added below existing `/intake` row, naming the 5-section body and `intake/docs/` destination

### Schema impact

| Surface | Change | Compatibility |
|---|---|---|
| `intake/docs/` subfolder | New, lazy-created on first doc-mode capture | Additive — no impact on existing intake folders |
| `type: intake-doc` frontmatter value | New value | Additive — `/audit-knowledge` routes intake-doc files through same disposition flow as other intake entries |
| `source_url` / `source_title` / `source_author` / `read_at` frontmatter fields | New optional fields on doc-mode captures | Additive — no impact on other knowledge file types |

### Cross-plugin parity (bidirectional flow precedent)

Both modes originated in aria-cowork's v0.3.0 design discussion as B2 + B5 candidates. This release is the **first instance of cowork→aria-knowledge feature flow** — features conceived in cowork's context, designed cross-plugin, shipped in aria-knowledge first (schema source-of-truth) so aria-cowork's port can import the resulting templates byte-identical. Pattern documented in aria-cowork ADR 014.

The plugin-openai-codex/ port mirrors the same skill body + template changes per the Codex Port Workflow ("keep durable knowledge template/schema changes in sync with `plugin/` — Claude remains the schema standard").

### Files changed

- New: `plugin-claude-code/template/intake/intake-doc.md` (42 lines)
- Modified: `plugin-claude-code/skills/handoff/SKILL.md` (195 → 260 lines, +65)
- Modified: `plugin-claude-code/skills/intake/SKILL.md` (177 → 271 lines, +94)
- Modified: `plugin-claude-code/skills/help/SKILL.md` (59 → 60 lines, +1)
- Modified: `plugin-claude-code/.claude-plugin/plugin.json` (version bump 2.16.1 → 2.17.0)
- Modified: `CLAUDE.md` (bidirectional flow note added per aria-cowork ADR 014)
- Mirrored: same changes in `plugin-openai-codex/skills/{handoff,intake,help}/SKILL.md` + `plugin-openai-codex/template/intake/intake-doc.md`

### Compatibility

- **No breaking changes.** Existing `/handoff` and `/intake` invocations work exactly as before. New modes are additive flags.
- **No new config schema.** Existing `aria-knowledge.local.md` works unchanged.
- **No new dependencies.** Pure markdown + WebFetch (already in /intake's `allowed-tools`).
- **Cowork sibling release coming:** aria-cowork v0.3.0 will land shortly with the doc-mode + brief-mode ports plus a much larger parity catch-up arc.

## [2.16.1] - 2026-05-14

**Full session-lifecycle CODEMAP/STITCH awareness.** Completes v2.16.0's surfacing story — passive `/context` surfacing (v2.16.0) + proactive trigger-based loading (v2.16.1). 6 trigger sites + 4 companion surfaces share the same primitive and config flag. Patch bump — no new schema, no new dependencies; reuses the existing `active_knowledge_surfacing` flag for atomic toggling.

### Added — Trigger-based CODEMAP + STITCH loading (6 sites)

- **New shared lib** `plugin-claude-code/bin/lib-tracked-artifacts.sh` — boundary-detected CODEMAP directory load (~600-1200 tokens) + full STITCH load (~4K tokens) when multi-repo. Reuses the existing `/tmp/aria-active-{session_id}` ledger from v2.15.0 for cross-trigger dedup.
- **T-1 `bash-cd-check.sh`** (PreToolUse:Bash with cd) — surfaces tracked artifacts on first cd into a configured project per session, alongside knowledge-file surfacing. Restructured to compute-both-then-decide pattern.
- **T-2 `session-start-check.sh`** (SessionStart) — surfaces tracked artifacts when `$PWD` substring-matches a `projects_list` entry. Complementary to the existing multi-project CODEMAP staleness reporter; non-interfering.
- **T-3 `task-context-check.sh`** (TaskCreated) — surfaces tracked artifacts for the project containing `$PWD` at subagent-spawn time, giving subagents structural context.
- **T-4 `post-compact-check.sh`** (PostCompact) — auto-covered via the shared ledger; tracked-artifact paths recorded by T-1/T-2/T-3 are re-surfaced after compaction with zero code changes.
- **T-5 `/prospect` Step 0.5** — extended with Step 11 detecting the plan's project (`--group=<tag>` → Linear prefix → plan-path match) and loading CODEMAP directory + STITCH.
- **T-6 `/retrospect` Step 0.5** — extended with Step 11 detecting the analyzed range's project via `git diff --name-only` majority-file-path match against `projects_list`.

### Added — Companion surfaces (S-3, S-4, S-7)

- **`/audit-config` Step 5a** — cadence-based tracked-artifact staleness audit. Classifies CODEMAP/STITCH into Critical (refusal zone, >2× threshold) / Should Fix (>threshold) / Low Priority (missing) / Healthy. Feeds existing 4-tier findings table without schema change.
- **`/stats` Step 3b + presentation** — cross-project dashboard view of CODEMAP + STITCH freshness across all `projects_list` entries. New "Cross-Project Tracked Artifacts" section in Step 6 template. Pairs with cwd-focused Step 3a (kept as-is).
- **`/handoff` + `/wrapup` Step 7 checklists** — added "Tracked artifacts" line to handoff-readiness checklist. Visibility-only; doesn't block at session end.

### Config flag scope expansion

- **`active_knowledge_surfacing`** (existing, default `true`) now ALSO gates CODEMAP/STITCH loading at all 6 trigger sites + skips companion surfacing when `false`. Single atomic toggle for the entire proactive-surfacing capability — no new flag bloat.
- **`/setup`** Advanced Options help text updated to describe the expanded scope.
- **`CONFIG.md`** consumers table row updated.

### Load model

- **CODEMAP**: directory section only (boundary-detected via `awk '/^## [0-9]+\.|^---$/ && NR>5'`; fallback `limit=50`). ~600-1200 tokens per project; never the full 1790-line CODEMAP.
- **STITCH**: full file (~4K tokens; typical 188-200 lines). Loads only when `STITCH.md` exists (multi-repo signal).
- **Staleness thresholds** (from v2.16.0): `codemap_staleness_threshold_days` (14), `stitch_staleness_threshold_days` (30). Grossly-stale (>2× threshold) refuses to load with warning.
- **User-facing output**: every load fires `[aria] Loaded {artifact} for {project} ({N days fresh|STALE|REFUSED})` notification. No silent context injection.

### Files

- **New:** `plugin-claude-code/bin/lib-tracked-artifacts.sh` (~180 LOC).
- **Modified:** 3 hooks (`bash-cd-check.sh`, `session-start-check.sh`, `task-context-check.sh`), 6 skills (`/prospect`, `/retrospect`, `/audit-config`, `/stats`, `/handoff`, `/wrapup`, `/setup`), 1 docs (`CONFIG.md`).

### Compatibility

- **No breaking changes.** All v2.16.1 behavior gated by `active_knowledge_surfacing: true` (existing default-on flag); passive-mode users see no new behavior.
- **No new dependencies.** Pure markdown + sh extensions.
- **No new config schema.** Reuses v2.16.0's `codemap_staleness_threshold_days` + `stitch_staleness_threshold_days`.
- **`pre-explore-codemap-check.sh`** (PreToolUse:Glob|Grep) **deliberately not extended** in v2.16.1 — existing CODEMAP nudge surface kept independent for scope discipline; v2.16.2+ enhancement candidate.

## [2.16.0] - 2026-05-13

**Five additive items: staleness gap close, vocabulary primitives, ecosystem doc.** Closes the CODEMAP/STITCH surfacing gap in `/context`; introduces two new optional frontmatter primitives (`semantic-hints` + tag aliases via `aliases.md`); refactors staleness logic into a shared block; adds the ARIA family section to the README. Minor bump — no breaking changes; existing knowledge folders work unchanged.

### Added

- **`/context` surfaces CODEMAP and STITCH artifacts** for queried projects with staleness markers (`[STALE — run /codemap update]`, etc.). Project-tag-gated; topic-only queries unaffected. (P-1, ADR 081)
- **`semantic-hints:` optional frontmatter field** — list of free-form phrases that match query tokens via substring (case-insensitive, hyphen-normalized). Indexed under new `## Semantic Hints Index` section of `index.md`. (P-4)
- **Tag aliases via `aliases.md`** — user-edited synonym map (`` `rn` → `react-native` ``). `/context` resolves alias queries to canonical tags before matching. Validates chains + collisions at `/index` time with user-actionable error messages. (P-13)
- **Shared staleness-marker block** in `/context` Step 5 — pure state-computation primitive (age + stale marker). Consumed by Pending Ideas and Tracked Artifacts. (P-2, ADR 082)
- **"ARIA family" section** in README documenting sibling projects and license posture. aria-cowork mentioned conceptually (public release planned); aria-hypergraph held out per privacy. (P-16)
- **`/stats` semantic-hints coverage line** — adoption signal showing `N of M files (P%)` declaring hints.

### Config

- New optional keys in `~/.claude/aria-knowledge.local.md` (defaults baked into `bin/config.sh` for graceful degradation when absent):
  - `codemap_staleness_threshold_days: 14` — CODEMAP age before flagged stale
  - `stitch_staleness_threshold_days: 30` — STITCH age before flagged stale (slower decay because cross-repo contracts change less often)

### Templates

- **New user-owned template:** `aliases.md` — bootstrapped on first `/setup`, never overwritten, never diffed.

### Skills affected

`/context` (5 changes: shared block, Pending Ideas refactor, Tracked Artifacts surfacing, semantic-hints matching, alias Step 2.5 + display), `/index` (3 changes: hints parse, aliases Step 2b + Step 9 annotation), `/ask` (2 changes: hints + alias resolution at Step 2), `/setup` (5 changes: 4 declarative-list updates + new template bootstrap), `/stats` (2 changes: extraction + output template).

### Compatibility

- **No breaking changes.** Files without `semantic-hints:` or aliases.md behave identically to v2.15.x. Existing knowledge folders work without modification.
- **Byte-identical refactor guarantee** for Pending Ideas rendering — verified via pre/post capture-diff at implementation time.
- **Graceful degradation** for missing config keys: `bin/config.sh` defaults apply silently if `codemap_staleness_threshold_days` / `stitch_staleness_threshold_days` are absent from existing configs.

## [2.15.2] - 2026-05-13

**Three quality-of-life arcs bundled.** Generalizes v2.15.1's archive-don't-delete rule to all known deletion call-sites; structural fix for Rule 22 marker enforcement under tool-call-interleaved transcripts; defense-in-depth against `/setup` discipline failures. Patch bump — no new features, only safety + correctness fixes.

### Arc 1 — Comprehensive delete-call-site audit

Generalizes v2.15.1's archive-don't-delete rule beyond `/audit-knowledge` Phase 2c2's ideas-routing. Investigation grep across all `plugin-claude-code/skills/*/SKILL.md` + `plugin-claude-code/bin/*.sh` classified each deletion site as compliant / needs-ledger / needs-archive / out-of-scope.

- **`/audit-knowledge` Step 2d (pre-compact snapshots)** — Clear / Approved / Rejected branches no longer `rm` snapshot files. Apply the **ledger-clear pattern**: write `{knowledge_folder}/archive/audit-{date}/pre-compact-captures/REMOVED.md` with frontmatter (`audit_date`, `removed_count`, `canonical_source_pattern`) + per-snapshot list (filename + session-id + capture-timestamp + canonical-jsonl-pointer), then remove snapshot bodies. Bodies are *derived copies* of Claude Code's per-session transcript log; canonical preservation lives at `~/.claude/projects/{cwd-encoded}/{session-id}.jsonl` until Claude Code rotates the log. Ledger pattern chosen over full archive because snapshots are large (100KB-1MB each) and the canonical source exists elsewhere.
- **`/audit-knowledge` Step 5e (cross-project pattern Remove)** — doc clarification: this is already verify-no-loss-compliant (source moves to cross-project file with `originally_at:` frontmatter providing audit trail). Added `(v2.15.2 note: ...)` inline comment so the compliance is explicit for future readers. No behavior change.
- **`/backlog clear`** — destructive "remove entries" replaced with **archive-then-remove pattern**: matching entries are copied to `{knowledge_folder}/archive/backlog-cleared-{type}-{YYYY-MM-DD-HHmmss}.md` with frontmatter metadata (`archived_at`, `source_backlog`, `cleared_through_date`, `entry_count`, `reason: /backlog clear user-invoked`) before removal from the live backlog. Full archive (not ledger) because backlog entries are user-authored content with no canonical source elsewhere. Skill's `allowed-tools` extended to include `Write` (was `Read, Edit, Grep`).
- **User-override clause for all three never-delete sites** — Step 2c2 (ideas, inherited from v2.15.1), Step 2d (snapshots, new), `/backlog clear` (new) all gain an explicit-user-override escape hatch. If the user explicitly approves or asks for a deletion that skips archive/ledger (phrases like *"delete without archiving"*, *"really delete this"*, *"skip the archive"*), the destructive operation is permitted. Default safety floor remains archive-on-disk; override is one-off per invocation (does not flip default for subsequent files); requires surfacing what would have been preserved before confirming. Legitimate use cases: sensitive content the user doesn't want traceable, archive-growth aversion, test/spam entries that don't deserve archive space.
- Out-of-scope sites (no spec change): all `rm` calls in `bin/*.sh` operate on temp files (`/tmp/aria-match-*`) or ephemeral runtime state (`active-batch.json`); descriptive "delete"/"remove" mentions in handoff/codemap/wrapup/snapshot are session-summary fields, not deletion calls.

### Arc 2 — Marker-window structural fix (`bin/pre-edit-check.sh`)

Rule 22's marker-detection walker in `pre-edit-check.sh` stopped at any `type: "user"` message going backward through the transcript. But Claude Code encodes tool_results as `type: "user"` messages too — so a `[Rule 22]` marker emitted in an assistant text block, followed by a Bash/Read tool call, followed by an Edit/Write, hit the tool_result boundary and the marker became invisible. Result: false-deny on the Edit/Write, requiring re-emit of the marker.

The fix: distinguish actual user prompts from tool_results via a conservative `all()` heuristic — if the user-typed message's content blocks are ALL `tool_result` blocks, walk past (it's a tool result, not a real user message); if any non-tool_result content exists, treat as a real user turn boundary. 6-line addition to the Python walker.

**Risk profile**: low. Heuristic uses `all()` so any mixed-content message stops the walker (conservative — avoids false-allow). Fail-open behavior preserved on any parse error. Worst case under future Claude Code transcript-format changes: hook denies, same workaround as today (re-emit marker).

### Arc 3 — `/setup` discipline hardening (3 sub-items, defense-in-depth)

- **3a — `/setup` Step 7e (Self-Validation Audit)** — after Step 7b's round-trip verification, enumerate known fields from `bin/config.sh`'s grep patterns, scan user's config for each, surface missing-fields list with defaults, prompt `(y/n/select)` to add. Catches the failure mode where `/setup` Step 6's Advanced Options bundle silently skipped surfacing a new field (the `active_knowledge_surfacing` gap that surfaced this arc).
- **3b — `/audit-config` Step 3b (Missing-Known-Fields Cascade)** — same check as 3a but runs at config-audit cadence (default 14 days). Catches gaps that escaped `/setup`'s self-validation — defense-in-depth at audit cadence. Reports missing fields under **Should Fix** with field name + default value + recommended action.
- **3c — [NEW]-detection observability** — before showing Step 6's Advanced Options bundle, emit a transcript-visible one-liner naming the detection result: flagged-N-keys / none / fresh-install-skipped. Makes the [NEW]-detection step observable so users can verify it ran instead of silently skipping.

### Changed — `bin/pre-edit-check.sh`

Python walker: 6-line addition distinguishing tool_results from actual user prompts.

### Changed — `plugin-claude-code/skills/audit-knowledge/SKILL.md`

Step 2d (Clear / Approved / Rejected) — ledger-clear pattern. Step 5e Remove — doc-only clarification. New ### Ledger schema subsection at end of Step 2d.

### Changed — `plugin-claude-code/skills/backlog/SKILL.md`

Step 4 (Clear) — archive-then-remove pattern. `allowed-tools` frontmatter: `Read, Edit, Grep` → `Read, Edit, Write, Grep`.

### Changed — `plugin-claude-code/skills/setup/SKILL.md`

Step 6 Advanced Options — [NEW]-detection observability emit-summary paragraph added after the existing detection-mechanism sentence. New Step 7e (Self-Validation Audit) inserted between Step 7d and Step 8.

### Changed — `plugin-claude-code/skills/audit-config/SKILL.md`

New Step 3b (Missing-Known-Fields Cascade) inserted between Step 3a and Step 4.

### Out of scope (deferred)

- Backfill of historical destructive audits (e.g., the 2026-05-13 parallel-session incident from v2.15.1's Origin) is handled per-incident by the operator.
- Pre-compact snapshot retention TTL (when Claude Code rotates jsonl) is not addressed — users who need belt-and-suspenders retention can set up their own backup tooling for `~/.claude/projects/`.

### Origin

Three independent threads converged in this release:

1. **Comprehensive delete-call-site audit** — v2.15.1 fixed ideas-routing but left other deletion sites under the old "git history will preserve it" assumption. A grep across the plugin surfaced two more sites needing the new rule (Step 2d snapshots, `/backlog clear`) plus one already-compliant site needing only doc clarification (Step 5e). User asked: "lets do all of them in the same release."
2. **Marker-window discovery** — encountered live during v2.15.1's session: writing the retrospect log triggered a false-deny because the `[Rule 22]` marker became invisible past an intervening Bash call. Documented as a novel failure mode in `logs/retrospect/2026-05-13-session-active-knowledge-surfacing-v2150.md` §9 row 6.
3. **`/setup` discipline failure** — user's parallel `/setup` run on v2.15.1-installed plugin did NOT surface the new `active_knowledge_surfacing` field as `[NEW]` in the Advanced Options bundle, despite v2.15.1's setup SKILL.md correctly containing the bullet. Diagnosis: Step 6's [NEW] detection is a soft instruction to Claude, not hook-enforced; the wizard skipped it. v2.15.2's defense-in-depth approach (Step 7e + Step 3b + observability) ensures detection failures are caught at three different moments.

## [2.15.1] - 2026-05-13

**`/audit-knowledge` Phase 2c2 — never delete; archive instead.** Closes a destructive failure mode in the ideas-routing flow: prior versions assumed `git log --all -- intake/ideas/` would recover idea bodies after Phase 2c2 deletion, but that assumption silently fails for any idea file created since the last git commit (untracked files have no history). Patch bump because the change is a safety fix on existing behavior, not a new feature surface.

### Changed — `plugin-claude-code/skills/audit-knowledge/SKILL.md` Step 2c2

Three coordinated edits replace "delete after routing" with "move-or-archive, never delete":

1. **Disposition list rewritten** — Accept / Reject / Reclassify no longer delete the idea file. Accept moves to destination (full-body preservation) OR to `archive/audit-{date}/` (summary-only destinations, with `demoted-to:` frontmatter). Reject moves to archive with `dismissal-reason:` frontmatter. Reclassify moves to archive with `reclassified-to:` frontmatter. Defer unchanged (no-op).
2. **Verify-no-loss check added** — before any Accept disposition's move-to-destination is executed, the audit inventories the original idea's substantive content ({Why, Motivation, Implementation, Source}) against the planned destination's coverage. Three outcomes: full coverage → move to destination; insufficient coverage → archive alongside; partial coverage → surface options to user. Edits/revisions during move are explicitly permitted — the rule is "no useful substantive content is lost," not "body byte-identical."
3. **Archive-folder canonical-preservation semantics + MANIFEST.md spec** — `archive/audit-{date}/` is the new canonical preservation surface; git tracking no longer assumed. Per-audit `MANIFEST.md` captures the cohort (touched, moved, archived-by-reason) as a human-readable counterpart to the audit log.
4. **Bundle row updated** — source idea files in a bundle disposition move to archive with `bundled-into:` frontmatter (not deleted). Verify-no-loss runs on the merged file's destination, not per-source individually.

### Why this matters (non-git users)

Prior versions effectively required users to commit `intake/ideas/` before every `/audit-knowledge` run. Users who don't keep their knowledge folder under git (a valid configuration) had no preservation guarantee — Phase 2c2's delete was destructive without recourse. v2.15.1 makes archive-on-disk the universal preservation surface, with non-git knowledge folders first-class.

### Out of scope (deferred to future patch)

- `/audit-knowledge` Step 2d (pre-compact captures) and other deletion points in other skills are NOT yet rewritten under the new rule. They use separate semantics (transcript snapshots are auto-generated, larger, and their substance is the conversation — already persisted in Claude Code's own transcript log). A v2.15.x audit of all delete-call-sites across the plugin is queued for follow-up.
- Backfill of historical destructive audits (e.g., the 2026-05-13 parallel-session incident that surfaced this bug) is handled per-incident by the operator, not by this skill's spec.

### Origin

A parallel `/audit-knowledge` session on 2026-05-13 deleted 36 idea files whose bodies were never in git history (untracked working-tree files). The user surfaced the destructive damage mid-session; recovery surfaces (Trash, APFS snapshots, Time Machine, VS Code local history) were all exhausted, confirming the bodies were permanently lost. Three iterations of design discussion converged on: never delete; verify substantive coverage before claiming move-preservation is sufficient; archive on insufficient coverage. The shape of the spec change captures all three: dispositions move-or-archive, Accept gates through verify-no-loss, archive folder is the universal preservation surface.

## [2.15.0] - 2026-05-13

**Active Knowledge Surfacing.** New `active_knowledge_surfacing: true` config field (default `true` per D4 of the design discussion) that promotes ARIA's apply pillar from passive (hook suggests `/context`, user types it) to active (hook + skill instructs Claude to autonomously Read matched files, then summarize what loaded before answering). Four hook trigger sites (SessionStart, TaskCreated, PreToolUse:Bash with cd-pattern matching, PostCompact) plus two skill trigger sites (`/prospect` and `/retrospect` via new Step 0.5). Honors a session-scoped dedup ledger at `/tmp/aria-active-{session_id}` so files surfaced by one trigger aren't re-Read by another within the same session. Cleared on SessionStart per the fresh-per-session decision; cross-session continuity comes from PostCompact's re-surface block, not from a persistent ledger. Minor bump (not patch) because the default-true posture is a posture flip, not just an additive knob — existing users upgrading to 2.15.0 will see autonomous Read calls on first session-start.

### Added — `bin/lib-index-match.sh`

New shared shell helper exporting `kt_index_match`, `kt_match_cleanup`, `kt_match_filter_ledger`, and `kt_match_record_ledger`. Refactored out of the inline matcher previously living in `task-context-check.sh` (lines 55-99 of v2.14.4). Single source of truth for the tokenize → match → file-collection → ledger pipeline; called by 3 of the 4 hooks (TaskCreated, Bash-cd, PostCompact reads but doesn't re-match). The two skills do Claude-driven matching via Read on `index.md` rather than shelling out, because skills run inside Claude where `${CLAUDE_PLUGIN_ROOT}` isn't reachable. Preserves the existing ≥2-tag-match threshold and 5-file emission cap as policy constants — changing them is a deliberate cross-cutting decision, not a per-caller knob.

### Added — `bin/bash-cd-check.sh`

New PreToolUse:Bash hook. Parses `cd <path>` from the command string (including compound commands like `cd foo && bar`), resolves relative + `~`-prefixed paths against `$PWD`/`$HOME`, derives a query from the destination path's last 2 basenames (e.g., `cd web/web-app` → query `"web web-app"`), and surfaces matched knowledge files. Per-project-per-session cooldown via `/tmp/aria-bashcd-{session_id}-{project_key}` so repeated cd into the same project doesn't re-prompt. Never blocks the cd — emits `additionalContext` only.

### Added — `Step 0.5: Active Knowledge Surfacing` in `/prospect` and `/retrospect`

Both skills gain an identically-shaped Step 0.5 between Step 0 (Inputs & Mode Detection) and Step 1 (Anchor Block). 10-substep Claude-driven algorithm: query-build (from skill arguments) → Read `index.md` → tokenize → match → threshold gate → collect → ledger filter (best-effort via `ls -t /tmp/aria-active-*`) → Read top-5 → 3-line summarize block → carry-forward into Steps 2 and 3.5. The /retrospect variant adds a `prefer logs/retrospect/` priority hint in substep 8 — past retros on overlapping tags are the loop-closure case (retrospect output becomes the next prospect's input on the same topic, after `/index` promotes them to the tag index).

### Changed — `bin/config.sh`

Adds parse + default (`true`) + validation case for `active_knowledge_surfacing`. Mirrors the `auto_capture` shape exactly (3 contiguous lines in each of the three blocks). Invalid values fall back to `true` (active mode is the secure default per D4).

### Changed — `bin/task-context-check.sh`

Inline matcher removed; delegates to `kt_index_match` via the new shared helper. Cooldown, threshold, and emission cap behavior preserved byte-identical to v2.14.4. Active mode branches: filters previously-surfaced paths via the session ledger, swaps "Run /context" wording for an active-Read instruction, records emitted paths to the ledger after a successful surfacing. Passive mode (when the flag is `false`) preserves the v2.14.4 message verbatim.

### Changed — `bin/session-start-check.sh`

Adds a janitor pass clearing stale `aria-active-*` ledgers older than 24h at session start. The knowledge-surfacing block now branches on the flag: active mode emits a 6-step prescriptive algorithm for Claude to execute after the first user task statement (Read index.md → tokenize → match ≥2 known tags → Read top-5 → summarize 1-2 sentences); passive mode preserves the v2.14.4 "suggest `/context`" wording verbatim.

### Changed — `bin/post-compact-check.sh`

Existing pre-compact snapshot detection preserved. New parallel block reads the active-surfacing ledger and emits a re-surface reminder after compaction wipes context. Both blocks coalesce into a single `additionalContext` emission since each hook fires one JSON output. Active-mode-gated; passive mode skips Block 2 entirely.

### Changed — `.claude-plugin/plugin.json`

Registers `PreToolUse:Bash` matcher pointing to `bash-cd-check.sh` (5s timeout, same as the other PreToolUse entries). Existing `PreToolUse: Edit|Write` and `PreToolUse: Glob|Grep` entries untouched.

### Changed — `/setup` wizard

Adds Step 6 Advanced Options bullet for `active_knowledge_surfacing` (named all six trigger sites + ledger path + thresholds inline). Adds Step 7 YAML template line. Adds Step 7b round-trip validation row. Existing users running `/setup` after upgrade will see the field marked `[NEW]` per the existing new-key detection behavior.

### Changed — `CONFIG.md`

New row in the hook-parsed-fields table positioned between `auto_capture` and `critical_paths`. "Read by" column enumerates all six consumers (4 hooks + 2 skills).

### Origin

Design discussion 2026-05-13: user invoked `aria/aria-knowledge` skill context and asked how indexed knowledge gets auto-surfaced, then requested a setup toggle to switch between passive ("suggest `/context`") and active ("autonomously Read matches") modes. Decisions locked through a 4-question form (Active-Read semantic; SessionStart + TaskCreated + Bash:cd + PostCompact trigger surface; single boolean field; default true) plus an addition for skill insertion on /prospect and /retrospect. Step 0.5 placement chosen over Step 0 inline so the conditional active block stays audit-visible separate from each skill's unconditional Inputs step. Implementation followed a 3-checkpoint plan with `[Rule 22]` markers per edit; final retrospect runs after this changelog lands.

## [2.14.4] - 2026-05-12

**New `/handoff` express-handoff skill + `/audit-config` release-state cascade checks.** Closes two ideas filed during the 2026-05-09 wrapup and the 2026-05-11 cascade-traced pipeline-adoption arc. Together they form a prospective↔retrospective release-discipline loop: `/handoff` writes the post-release version-stamp and adoption-state docs (and emits a paste-ready next-session opener); the next `/audit-config` mechanically catches any surfaces that didn't get touched. Patch bump per `feedback_aria_versioning_patch_for_new_skill`: new isolated skill + additive extension to an existing skill, no schema or contract change.

### Added — `/handoff` skill (`plugin-claude-code/skills/handoff/SKILL.md`)

Express end-of-session handoff. Same coverage as `/wrapup` (review session work → update PROGRESS.md / CLAUDE.md / memory → commit → run `/extract` → verify continuity) compressed into a single combined-go review. Two modes:

- **Default (`/handoff`)** — Generates ALL drafts (session synthesis, PROGRESS entry, CLAUDE.md edits, memory updates, commit message, next-session opener) into one scroll, asks once for combined-go (`yes` / `edit {section}` / `skip {section}` / `abort`), then applies atomically. Preserves the verification pass with the lowest interruption cost.
- **`auto` (`/handoff auto`)** — Implicit-yes on all gates. Runs silently. Applies all drafts without confirmation. Emits final report only. For short, unambiguous sessions.

Always emits a paste-ready **next-session opener** as the headline artifact, even when no other surfaces changed — a fenced block with project marker + read list + "where we left off" + open threads + first action, formatted to drop directly into the next session.

`/wrapup` stays the interactive default for ambiguous sessions; `/handoff` is the express lane. Both call `/extract` (already non-interactive by design); neither ever pushes to git.

### Changed — `/audit-config` skill (`plugin-claude-code/skills/audit-config/SKILL.md`)

Two new check categories added to Step 3 + a dedicated Step 3a documenting the detection patterns:

- **Version-stamp ripple (Step 3a.1)** — After a plugin/package release, version references typically touch 5+ surfaces (manifest, project CLAUDE.md, parent container CLAUDE.md, project memory file description + body + version-row, MEMORY.md index entry). Detection: for each manifest's canonical version, grep CLAUDE.md / memory files for older semver strings near a project-name mention, flag any surface where the stated version is older than the manifest's.
- **Adoption-state cascade (Step 3a.2)** — When a binary config value flips (e.g., enabled flag, placeholder folder becomes a built artifact), N referenced docs may still describe the prior state. Detection: pattern table of phrases (`"currently disabled"`, `"NOT YET BUILT"`, `"(placeholder)"`, `"pipeline built but not yet adopted"`, `"deferred to v{X.Y.Z}+"` where X.Y.Z is now in the past) cross-checked against the underlying flag/manifest/artifact state.

Both check classes report under **Should Fix** (not **Critical**) because they're pattern-based heuristics — false positives possible. Surface + contradicting phrase + underlying state are presented for user judgment.

"What This Audit Catches" table extended with a **Release-state cascade** row covering both shapes.

### Changed — `/help` skill (`plugin-claude-code/skills/help/SKILL.md`)

`/handoff [auto]` added to the commands table directly after `/wrapup`, and to the "Sonnet 4.6, medium effort" row in Model Recommendations alongside `/wrapup` (same complexity class: structured work with prescribed output).

### Origin

Two ideas filed during prior sessions converged in this release:
- 2026-05-09 wrapup insight (PROGRESS.md Phase F): post-aria-cowork-v0.2.5 release surfaced a 5-surface version-stamp ripple shape; idea filed to extend `/audit-config` with a version-stamp drift check.
- 2026-05-11 idea file (`intake/ideas/2026-05-11-cross-audit-config-adoption-state-cascade-check.md`): the ariaknowledge.com pipeline-adoption arc traced an 11-surface cascade from a single `0`→`1` flag flip; idea filed to extend `/audit-config` with adoption-state cascade detection.

Both share structural shape (one source-of-truth change → N downstream surfaces drift), so they bundled cleanly into one `/audit-config` extension. The /handoff skill provides the writer side of the same loop — emit the version-stamp + adoption-state updates at release time, let /audit-config verify them later.

## [2.14.3] - 2026-05-08

**Cull-pass refinement of 7 working rules — closes ADR 069's S4 deferral.** Applied Karpathy's litmus test (*"Would removing this rule cause Claude to make a mistake it couldn't recover from?"*) to all 34 working rules across a live-review session. **Zero retirements, zero MERGEs, zero file-class changes** — every flagged candidate became KEEP, REFINE, or KEEP+REFINE after deeper read surfaced scope-mismatch concerns and accuracy gaps yesterday's analogical reasoning had missed. Patch bump per `feedback_aria_versioning_patch_for_new_skill`: in-place content refinements without semver-meaningful behavior change. The cull-pass-became-refinement-pass outcome is a more honest result than the original DEMOTE-heavy plan would have shipped.

### Changed — Rule 4 retitled and rewritten for accuracy (`template/rules/working-rules.md`)

**Title:** "Prefer CLIs over MCP servers" → "**Choose the lower-token option per operation**"

**Body:** Replaced misleading blanket claim ("CLIs reduce token overhead, unless...") with operationally accurate guidance naming the cases where each form wins. CLI is leaner for simple stdout-friendly Unix operations (file listing, grep, git log); MCP is leaner for structured queries (Linear, Supabase, browser state, API/auth) because it returns only the fields requested. Rule 4 now asks the operational question (*"which form returns sparser output for THIS task?"*) rather than encoding a wrong default.

**Why:** the original blanket was 2024-era intuition that's only directionally true for some operations and false for others (structured-data MCP queries are routinely cheaper than equivalent CLI). Rule numbers preserve per Rule 14 policy — readers expecting Rule 4 still find Rule 4, with sharpened content.

### Changed — Rule 8 expanded with broad-scope clause + Origin (`template/rules/working-rules.md`)

Rule 8's body adds a paragraph naming its broad scope (applies to design / exploration / debugging / advice — not just before edits) and an Origin section. The motivating concern: yesterday's plan flagged Rule 8 as a MERGE candidate into Rule 22 Step 2, but Rule 22 hooks fire only on Edit/Write while Rule 8 should apply whenever reasoning starts. The scope-mismatch would have been lost in a merge. The refinement makes the broad scope and the Rule-22-Step-2 composition explicit so future merge-temptation has documented counter-evidence.

### Changed — Rule 16 example list extended (`template/rules/working-rules.md`)

Added a language-agnostic naming example (`fetchUserOrders` over `getUO`) alongside the existing React hook-naming example (`useRequireAuth` over `useAuthGuard`). Recognition for non-JS readers; ~5 words added; original example preserved.

### Changed — Rule 19 retitled and refined for capture-stage clarity (`template/rules/working-rules.md`)

**Title:** "When something fails, learn from it" → "**When something fails, capture the learning**"

**Body:** Original "Failures are data, not just problems" reframe leads. Added paragraph naming the *capture* stage explicitly — applies to test failures, deploy failures, design didn't meet need, hypothesis contradicted, tool call surprised. Names the staging discipline ("capture into extraction-backlog or insights-backlog; do NOT promote into rules at this stage"). Reciprocal composition pointer to Rule 23.

### Changed — Rule 23 retitled and refined for rule-poisoning gate (`template/rules/working-rules.md`)

**Title:** "Review learnings before saving" → "**Review captured learnings before saving them as rules**"

**Body:** Original sentence preserved. Added "Why this gate exists" section naming the load-bearing concern: saved rules become enforced via `/rules` lookups, Rule 22 hooks, and CLAUDE.md context; a wrong rule, once saved, propagates its error across all future sessions until detected and revoked. The review step is the check against rule-poisoning. Reciprocal composition pointer to Rule 19.

The Rule 19 ↔ Rule 23 pairing now explicitly forms the lifecycle: failure → capture (Rule 19) → review (Rule 23) → save.

### Changed — Rule 27 expanded to structural parallel with Rule 33 (`template/rules/working-rules.md`)

Rule 27 gains three sub-sections that mirror Rule 33's existing structure:

1. **Triggers — when this rule fires** — recognizable failure shapes (API error mismatch, version mismatch, deprecation warning, previously-working call now fails)
2. **Routing order** — 5 prioritized verification sources (discovery endpoints → release notes → status page → registry → ask user)
3. **Composes with Rule 33** — reciprocal pointer (Rule 33 already had "Composes with Rule 27"; the asymmetry is now closed)

Original body preserved verbatim; Origin preserved at end. Rule 27 (retrospective verification) and Rule 33 (prospective verification) now read as visibly paired halves of the same external-verification discipline.

### Changed — Rule 29 gains composition pointer to Rule 28 (`template/rules/working-rules.md`)

Inserted a 2-sentence composition note between the minimization tips and the Origin section: Rule 29 specializes Rule 28's "write only as much as needed" discipline to the visual-testing case where tool-cost asymmetry is highest. The pointer surfaces Rule 29 as a worked-example of broader output discipline rather than a standalone tool-cost concern.

### Origin — Karpathy 4-line article review, S4 deferral closes

Surfaced from a 2026-05-06 → 2026-05-08 design conversation walking the 6 cull candidates yesterday's plan flagged. Two patterns fired retrospectively on the original plan's analogical reasoning:

- **`judgment-confused-with-evidence`** — Rules 4 and 29 were flagged as DEMOTE on "tool-specific narrow scope" reasoning that didn't survive deeper read (both turned out to be universal AI-coding cost guidance, not Mike-specific tooling preference)
- **`pattern-matched-from-memory`** — Rule 29's DEMOTE flag was pattern-matched from Rule 4's flag without examining whether the rules served different audiences

The live review surfaced two new analytical lenses worth carrying forward:
- **The universal-vs-personal axis** — DEMOTE-to-user-rules.md is appropriate for personal preferences; harmful for universal cost guidance
- **The scope-mismatch concern** — MERGE proposals frequently collapse rules with different firing conditions (Rule 8's broad reasoning scope vs Rule 22's Edit/Write hook scope; Rule 19's capture stage vs Rule 23's governance stage)

### Considered and rejected

- **DEMOTE Rule 4 / Rule 29 to user-rules.md** — both turned out to be universal cost guidance; demoting harms users who don't read migration notes. Refined in place instead.
- **MERGE Rule 8 → Rule 22 Step 2** — would lose Rule 8's broad-reasoning scope (applies to design / exploration / debugging / advice; Rule 22 hooks fire only on Edit/Write). Hooks were source-traced as parsing markers not framework body, so the merge was *technically* feasible but *semantically* lossy.
- **MERGE Rule 19 → Rule 23 (or vice versa)** — would lose either the "failures are data" reframe (Rule 19) or the broader rule-candidate review scope (Rule 23, which covers non-failure-derived learnings too). Kept paired with reciprocal composition pointers.
- **MERGE Rule 27 → Rule 33** — would lose the timing distinction (Rule 27 retrospective, Rule 33 prospective). Both rules cover stale third-party information but fire on different triggers. Kept paired.
- **Patch (v2.14.3) vs Minor (v2.15.0)** — v2.15.0 was originally targeted assuming retirements/structural shift. With zero retirements and only content refinements, patch is more honest. No semver-meaningful behavior change.

### Self-binding observation

The cull-pass-became-refinement-pass outcome (zero retirements out of 6 candidates) suggests the 34 working rules are leaner than the Karpathy article's "Configuration Paradox" framing assumed for ARIA's context. v2.14.0's Behavioral Foundation preamble already absorbed the four-line discipline as the entry point; the 34 below it earned their keep when each was tested against operational use. Future cull passes should default to KEEP-or-REFINE; only flag for retirement when a rule is demonstrably never load-bearing across multiple sessions.

### Preserved

- All 34 rule numbers preserved per Rule 14 policy
- All hook-enforced rules unchanged in structure (Rule 22, 25, 26)
- Behavioral Foundation preamble (v2.14.0) and `user-examples.md` tier (v2.14.2) unchanged
- Rule 33's "Composes with Rule 27" reference (already correct) unchanged — reciprocity now achieved by Rule 27's new pointer
- All `/rules`, `/index`, `/audit-knowledge`, `/setup`, `/prospect`, `/retrospect` skill behavior unchanged

---

## [2.14.2] - 2026-05-07

**New `rules/user-examples.md` — user-owned file for per-rule before/after examples + `/rules N` skill extension to surface matching examples automatically.** Closes ADR 069's S5 deferral (the "should ARIA ship per-rule examples?" question) with a user-owned single-file design that honors the principle *examples are inherently user-specific* — generic examples drift back into being the rule itself or a separate canonical pattern; project-specific examples ship as foreign content to other users. Patch bump per `feedback_aria_versioning_patch_for_new_skill`: skill extension + new user-owned file is patch-scoped (smaller than a new skill). Plugin ships zero example content; `user-examples.md` is created once on `/setup` from a stub template, then never diffed.

### Added — `rules/user-examples.md` user-owned template (`plugin-claude-code/template/rules/user-examples.md`)

A new user-owned file alongside `user-rules.md` for project-specific before/after examples illustrating the rules in `working-rules.md`. Mirrors the user-rules.md voice — friendly intro, "examples are user-specific" framing, naming convention, format guidance, skeleton template clearly labeled for replacement.

**Format:**
- Required: `## Rule N — {short title}` heading + `### Before` + `### After` sub-sections
- Optional: `**Calibrated against:** {project / commit / date / incident}`, `### Why this example`, inline citations

**Ownership:** user-owned (created once on `/setup`, never overwritten or diffed). Same class as `LOCAL.md`, `rules/user-rules.md`, directory README stubs.

### Added — `/rules` skill extension (`plugin-claude-code/skills/rules/SKILL.md`)

Step 3 (Lookup by Identifier) extended with an "Examples lookup" sub-section:

After returning a rule's body, the skill now also reads `{knowledge_folder}/rules/user-examples.md` (if it exists) and searches for a heading matching `## Rule N`. Matching example bodies are appended to the output as a separate section. Multiple examples for the same rule are returned in document order, separated by `---`. If `user-examples.md` doesn't exist or has no matching heading, the example section is omitted silently — no warning for the normal "no examples authored yet" state.

Discovery is automatic: no forward-link maintenance in `working-rules.md` required.

### Added — Documentation surface updates

- `plugin-claude-code/skills/setup/SKILL.md` — `rules/user-examples.md` added to Expected files list (line 55), User-owned files list (line 57), User-owned bullet in first-setup educational note (line 66), and "Never diff" list (line 107). Same set of integration surfaces as `rules/user-rules.md` since the file class is identical.
- `plugin-claude-code/template/OVERVIEW.md` — User-owned files paragraph (line 201) updated with `rules/user-examples.md` and v2.14.2 origin annotation.
- `plugin-claude-code/template/README.md` — `rules/` tree listing gained `user-examples.md` between `user-rules.md` and `change-decision-framework.md`, grouping user-owned files together visually.

### Origin — Karpathy 4-line article review (S5 deferral closes)

Surfaced from a 2026-05-07 design conversation that revisited the originally-recommended Option B (plugin-managed stub with forward-links from `working-rules.md`). Two underweighted concerns invalidated B's trajectory:

1. **Cost to non-users** — plugin-managed stub means recurring diff prompts during `/setup` for users who never author examples (compounds over time)
2. **Examples are inherently user-specific** — Mike's articulated principle: a "universal Rule N example" drifts back toward being the rule itself OR a new canonical pattern; examples earn their illustrative value by being grounded in *specific context* (file paths, commits, project conventions)

Refined Option H (user-owned file + `/rules` extension, zero shipped examples) emerged from synthesizing two alternative designs Mike proposed:
- **Ship-and-freeze with seeds** (no diffs after install, didactic seeds bake at install time)
- **Working/user split** (mirrors rules-split, automatic `/rules` discovery)

The hybrid keeps the no-diff property of the first (user-owned) and the automatic-discovery property of the second (skill extension), while *removing* the seed authoring (which would have violated the user-specific principle).

### Considered and rejected

- **Option B — plugin-managed stub + forward-link convention.** Recurring diff-prompt cost; manual forward-link discipline; speculative demand without empirical motivation.
- **Option F — single file shipped with seeds, becomes user-owned post-install.** Seeds violate user-specific principle (either project-specific = foreign to most users, or generic = should be in the rule itself); bake-time risk.
- **Option G — working-examples.md / user-examples.md split mirroring `working-rules.md` / `user-rules.md`.** Doubles file count; inflates example importance to rule-tier parity; ongoing curation burden on plugin author.
- **Option H-original — user-owned file + 2–3 seed examples + `/rules` extension.** Seeds violate user-specific principle (same as F).
- **Inline `**Example:**` subsections under each rule in `working-rules.md`.** File balloons; behavioral foundation gets buried; re-introduces the Configuration Paradox v2.14.0 was designed to fight.

See ADR 070 (`~/Projects/knowledge/projects/aria/decisions/070-rules-examples-user-owned-tier-decision.md`) for the full alternatives evaluation and consumer-distinction rationale (`detection-mediated tiers = plugin-curated; illustration-only tier = user-authored`).

### Self-binding constraint

ADR 070 records: **no further additions to `rules/` (working-, user-, or otherwise) without an ADR.** Current rule-tier files (`working-rules.md`, `user-rules.md`, `user-examples.md`, `change-decision-framework.md`, `enforcement-mechanisms.md`, `retrospect-patterns.md`, `prospect-patterns.md`) are sufficient for the rule-tier consumer model.

### Preserved

All 34 rules and the Behavioral Foundation preamble (v2.14.0) unchanged. Rule 20's two-half structure preserved verbatim. /retrospect, /prospect, /index, /audit-knowledge, /audit-config, /setup, all hooks: behavior unchanged for users who never author examples. Empty `user-examples.md` is the expected fresh-install state.

---

## [2.14.1] - 2026-05-06

**New /prospect skill (forward-looking pre-mortems on plans before execution) + active Evidence-Sourcing Pass on both /prospect and /retrospect + new release/deployment scopes for /retrospect with hybrid detection cascade + structured-frontmatter persistent log under `~/knowledge/logs/{prospect,retrospect}/` + /index discoverability for review reports.** /prospect is the forward-looking counterpart to /retrospect — runs a 10-section pre-mortem on a plan before any code is written, with the same per-step validation discipline /retrospect applies after a fix ships. Both skills now run a synchronous Evidence-Sourcing Pass (new procedural Step 3.5) that autonomously sources accessible evidence (codebase reads, public docs, MCP queries) and surfaces user-input asks for anything that requires judgment — converting unsupported assumptions to ✅/❌ before the report finalizes. Patch bump per `feedback_aria_versioning_patch_for_new_skill`: additive new skill + extension to existing skills + index scan extension; no breaking changes.

### Added — /prospect skill (`plugin-claude-code/skills/prospect/SKILL.md`)

Forward-looking pre-mortem on a plan or approach that has been *created but not yet executed*. Mirror of /retrospect's shape so the same review muscle works in both directions. Six positional scopes plus a no-args default:

| Scope | Plan source |
|---|---|
| `plan` (default) | Current conversation's articulated plan — TodoWrite + recent assistant plan + in-session plan files |
| `session` | Synonym for `plan` |
| `todos` | Just the active TodoWrite list |
| `file <path>` | Explicit plan markdown file |
| `linear <id>` | Linear ticket Technical Intake |
| `branch <name>` | Uncommitted/unpushed local branch changes |

Backward-compat flag forms (`--plan`, `--linear`, `--branch`, `--todos`, `--session`) accepted indefinitely. Modifier flags: `--linear-post` (post verdict to detected Linear tickets), `--no-source` (skip Step 3.5).

Produces a 10-section markdown report with anchor / plan-specificity gate / per-step verdict / failure-mode pattern check / cross-step tally / frame check / diagnosis confidence / action verdict / process pre-mortem / pre-execution evidence ask. Per-step actions: PROCEED / SHRINK / SPLIT / DEFER / KILL / DEFER-PENDING-DESIGN. Risk-status taxonomy mirrors /retrospect's validation taxonomy in forward form: ✅ Pre-validated / ⚠ Theory-driven / ❌ Falsified / ❓ Unsupported / 🚫 Unverifiable-yet.

Hard rule: a step's Action cannot be PROCEED unless post-Step-3.5 Risk? is ✅ Pre-validated, OR ⚠ Theory-driven WITH explicit "Acceptable risk because: …" appended. The theory-driven carve-out exists because every plan is theory-driven by definition (you're imagining, not measuring) — the carve-out forces the planner to *name the risk* rather than block all forward motion.

### Added — Evidence-Sourcing Pass on both skills (`plugin-claude-code/skills/{prospect,retrospect}/SKILL.md`)

New procedural Step 3.5 inserted between Step 3 (Enumerate) and Step 4 (Render Report). For each candidate with non-✅ preliminary status, Step 3.5 generates the *single most decisive question* whose answer would upgrade the verdict to ✅ or ❌, categorizes the answer source as AUTO-SOURCEABLE / USER-INPUT / MIXED, then either sources autonomously or surfaces a structured ask to the user.

**Auto-source tools** (allowed-tools extended with `WebFetch` + `WebSearch`):
- Codebase: Read, Grep, Glob — for file content, references, structure
- Version control: `git log`, `git diff`, `git show`, `git blame`
- Public web: WebFetch (specific URL — library docs, official spec) and WebSearch (when URL is unknown). Per Rule 33, prefer official sources; per Rule 27, verify identifiers/versions are still current.
- Local probes: `curl`, `gh`, log-tail, file-existence checks
- MCP queries that don't require new credentials and that the user has already authorized in this session

**User-input ask format** (codified inline, respecting 7 prior feedback rules — `ask_with_inline_context`, `numbered_options`, `neutral_option_framing`, `per_question_explicit_pick`, `per_item_review_cadence`, `hold_gate_steps`, `terse_numeric_answers`): one ask at a time, citations inline, four numbered options with the fourth always being "Skip — leave at <preliminary status>; will DEFER in §4.10". Synchronous barrier — the skill holds for response. "Skip" defaults to DEFER per `feedback_no_self_fabricated_go_signals` (the skill never invents a decision the user didn't make).

**Constraints** (apply to both skills): two corroborating sources required for ✅ upgrade (single source upgrades only to ⚠ Theory-driven with sub-tag `single-source-inferred`); one contradicting authoritative source falsifies to ❌; no credential reads without explicit per-session permission (per `feedback_ask_before_credentials`); no destructive probes (read-only commands only); time-box ~5 tool-call rounds per question.

**Skip path:** `--no-source` flag skips the entire pass for quick structural reviews. When skipped, all preliminary statuses pass through unchanged and §4.10 lists every gap as `SKIPPED-BY--no-source`.

/retrospect's Step 3.5 has *two* sub-passes (vs /prospect's single pass) — bundle-marker first (resolves 🤷 by sourcing the deployed bundle and grepping for the in-bundle marker), then outcome (resolves ⚠/❓/🚫 by sourcing post-deploy logs/repros). Bundle-marker pass feeds §4.2's emit value; outcome pass feeds §4.3's emit value.

### Added — `release` and `deployment` scopes for /retrospect (`plugin-claude-code/skills/retrospect/SKILL.md`)

Two new positional scopes joining the existing `commit`, `range`, `pr`, `session` set:

- **`release`** — `git describe --tags --abbrev=0` to find the most recent semver tag, then `git log <tag>..HEAD`. If no tags, fall back to auto-range with a warning.
- **`deployment`** — hybrid detection cascade (4 steps): (1) `gh release view --json publishedAt,tagName`, (2) `git tag --sort=-creatordate | head -1` matching `v?\d+\.\d+\.\d+`, (3) last commit on `origin/main` (or `origin/master`), (4) prompt user. First success wins. Print the resolved marker source in §4.1 Anchor so the user can verify what the skill thought "deployment" meant.

Designed to cover the union of CS (semver tags), SS (Bitbucket pipelines without GH releases), and builder repos (semver) deploy conventions without per-project config.

### Added — RESHIP-AND-VERIFY action for /retrospect (`plugin-claude-code/skills/retrospect/SKILL.md`)

New action introduced when §4.2 emits ❌ Not-in-bundle (Step 3.5.1 positively confirmed the fix did NOT ship, e.g., bundle returned 200 but the marker grep was empty, OR the deploy log shows a failed/superseded job). The fix's code is correct — it just didn't ship. §4.8 emits a project-appropriate re-deploy command (from `aria-config.md`'s `projects_list[<tag>]` if present, otherwise prompt user) plus a directive: "After re-deploy, re-run `/retrospect deployment` to confirm the bundle now contains the fix and validate outcome." Closes the loop between failed-deploy detection and re-validation.

### Changed — Positional scope syntax for /prospect and /retrospect

First positional argument is now the **scope keyword**; subsequent positional arguments are scope-specific. Existing flag forms (`--range`, `--pr`, `--session`, `--commit`, `--plan`, `--linear`, `--branch`, `--todos`) remain accepted indefinitely as backward-compat aliases. Both `/retrospect range a..b` and `/retrospect --range a..b` resolve identically. Argument-hint frontmatter updated to `[<scope>] [<scope-arg>] [--linear-post] [--no-source]`.

### Changed — `--linear` renamed to `--linear-post` on /retrospect (no alias)

For consistency with /prospect's existing `--linear-post` flag. The verb form makes the side-effect explicit (the flag triggers a POST to Linear, doesn't just consult it). Per Mike's pick, no `--linear` alias — old invocations break, but the rename is documented in plugin.json description and Step 0 mode table.

### Changed — Persistent log filename + structured YAML frontmatter

Reports persist to `~/knowledge/logs/prospect/<YYYY-MM-DD>-<scope>-<slug>.md` and `~/knowledge/logs/retrospect/<YYYY-MM-DD>-<scope>-<slug>.md` (existing files under the older `<YYYY-MM-DD>-<slug>.md` pattern are grandfathered — no rename).

Each report is now prepended with structured YAML frontmatter (Q1.1=2 schema):

```yaml
---
type: prospect | retrospect
date: <YYYY-MM-DD>
scope: <scope keyword>
goal: <one-line>
tickets: [<LINEAR-123>, ...]
steps_count | fixes_count: <N>
sourcing_pass: <flat block for prospect; nested bundle_marker + outcome blocks for retrospect>
patterns_hit: [...]
overall_verdict (prospect): PROCEED | PROCEED-WITH-CHANGES | HOLD | KILL
overall_outcome (retrospect): closed | partial | unresolved | mixed
related: [<paths to overlapping prior runs>]
tags: [<type>, <scope>, <project-tag-if-detected>, <pattern-tag-if-applicable>]
---
```

`related:` auto-detection (Q1.2=1, ticket-based): before writing, glob `~/knowledge/logs/{prospect,retrospect}/*.md` for files whose frontmatter `tickets:` overlaps with the current report's tickets. Cap at 10 most-recent overlaps. Bidirectional discoverability — yesterday's retrospect surfaces in today's prospect's `related:` and vice versa.

`overall_outcome` derivation (retrospect): `closed` if every fix's post-Step-3.5 Validated? is ✅; `unresolved` if any fix is ❌ Invalidated or ❌ Not-in-bundle; `partial` if any fix is ⚠ partial AND none are ❌; `mixed` for any other combination.

### Added — Reviews tier scan + Review Index in `/index` (`plugin-claude-code/skills/index/SKILL.md`)

Q1.3=1 (review reports discoverable via /context). Step 1's "Do NOT scan: ... logs/" rule replaced with a more precise carve-out: top-level `logs/*.md` (audit logs, hook debug log) remain excluded, but `logs/prospect/` and `logs/retrospect/` ARE scanned via a new "Reviews tier scan" sub-step. Review files are stored with `source: "review"` and pull retrospect/prospect-specific frontmatter (`type`, `scope`, `tickets`) alongside standard tags.

Step 9's `index.md` schema gets a new `## Review Index` section between `## Team-Shared Tag Index` and `## Stale Files`, with two subsections (Retrospects, Prospects), descending-by-date sort, compact one-line entries showing date / scope / goal (truncated) / tickets / overall_outcome|overall_verdict.

### Considered and deferred — Step 8 / 8c filter for review files (option C)

Considered applying a high-signal triple-gate filter (ticket-ID match / pattern-hit match / explicit citation) to /index Step 8 (Cross-Reference Pass) for review files, plus a skip-with-mention-exception for Step 8c (Skill Connection Discovery). Motivation: review files have rich tag sets that match many things shallowly via the existing ≥2-tag heuristic, producing dozens of low-signal Y/N suggestions per /index run; reviews are CONSUMERS of knowledge, not SOURCES that other files should link back to. Three options were proposed (A: high-signal triple-gate + direction asymmetry + Step 8c skip; B: skip Step 8 + Step 8c entirely; C: defer with documentation).

**Mike's pick: C.** Deferred because pattern depth is not yet known — until /index runs against several real review files in active /context queries, the actual signal-to-noise of the existing heuristic is theoretical. Better to ship the review-tier scan now, observe noise on real runs, refine filtering based on observed cases. Full design captured in `aria/IDEAS-BACKLOG.md` (2026-05-06 entry — `/index Step 8 + 8c filter for review files`) including implementation sketch and composes-with pointers to existing entries (the 2026-05-05 "/index focused-session cross-reference-only mode" and the 2026-04-30 "25th-Pass /index Run Findings").

### Preserved

All 34 working rules unchanged. Behavioral Foundation preamble from v2.14.0 unchanged. retrospect-patterns.md from v2.13.9 unchanged. /retrospect's existing 10-section report structure preserved verbatim (no section renumbering, no removals); the additions are: Step 3.5 procedural step inserted between Step 3 and Step 4, and §4.2/§4.3/§4.5/§4.7/§4.8/§4.10/Step 8 bodies extended to integrate Step 3.5 findings without breaking the section count.

### Origin — applying /retrospect's discipline to forward-looking work

The /prospect design surfaced from a 2026-05-06 session question: "we have /retrospect for shipped work, but the same per-fix validation discipline applies to plans before they ship — what if every step in a plan got the same scrutiny *before* code lands?" The answer was a mirror skill with parallel structure: same 10 sections, same validation taxonomy (in forward form), same hard rule (with a theory-driven carve-out for the obvious case that all plans are theory-driven). The Evidence-Sourcing Pass was added to *both* skills in the same pass to close the gap between "name the missing evidence" and "actively try to gather it" — a refinement Mike requested after seeing /prospect ship without it.

---

## [2.14.0] - 2026-05-06

**Behavioral Foundation preamble + Rule 20 reframed for upfront-criteria leverage + Evidence-and-limits section in README.** Distills the 34 working rules into four behavioral principles aligned with [Andrej Karpathy's January 2026 diagnosis](https://x.com/karpathy/status/2015883857489522876) and the [4-line CLAUDE.md repo](https://github.com/forrestchang/andrej-karpathy-skills) it inspired. Positions the 4-line foundation as a load-bearing entry point with the 34 rules as the operationalized expansion. Minor bump because the preamble is a user-visible structural addition above all 34 rules.

### Added — Behavioral Foundation preamble (`template/rules/working-rules.md`)

A new section between "How to Use This Document" and "Coding Rules" introduces four behavioral principles distilling what the 34 rules collectively enforce:

1. **Don't assume — surface tradeoffs.** *(Rules 5, 7, 9, 10)*
2. **Simplest solution wins — nothing speculative.** *(Rules 13, 14, 18)*
3. **Touch only what you must.** *(Rules 22, 25, 26)*
4. **Define success criteria upfront, loop until verified.** *(Rule 20)*

Each principle cross-references the rules below that operationalize it. Includes a "Why both layers exist" paragraph naming the conditions that justify expansion past four lines: (a) work spans multiple sessions and needs persistent discipline, (b) failures have asymmetric cost and need explicit gating, or (c) team coordination requires shared, named conventions. The volume past four is justified by the operational context, not added for its own sake.

### Changed — Rule 20 reframed for leverage + discipline (`template/rules/working-rules.md`)

Rule 20 retitled from "Always validate before assuming completion" to "Define success criteria upfront, validate before assuming completion." The original verify-before-done discipline is preserved verbatim as the second half. A new first half introduces the leverage framing: strong, verifiable criteria let Claude loop independently; weak criteria ("make it work", "fix the bug") require constant clarification. Concrete transformations included:

- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Refactor X" → "Ensure tests pass before and after"

A "Why both halves matter" paragraph names the distinction: verify-before-done is *discipline* (catches failure after the work), define-criteria-first is *leverage* (prevents most failure by giving the agent a verifiable target to loop against). Composes-with pointers to Rule 22 Step 6 and Rule 24 added.

### Added — Evidence and limits section (`README.md`)

A new section between "Philosophy" and "ARIA vs Other Memory Architectures" honestly names the calibration shape: real-failure data from the plugin author's projects, not controlled study; the 5-instance close-out cycle on 2026-05-05 as the strongest single calibration; no before/after benchmarks across the broader developer population. References the Karpathy 4-line repo as a peer with the same evidence shape ("strong resonance, no controlled study") and notes ARIA now ships those 4 principles as the Behavioral Foundation preamble. Includes "Where ARIA is most likely to help" and "Where ARIA may be overkill" lists to set expectations.

### Origin — applying the Karpathy 4-line article to ARIA

Surfaced from a 2026-05-06 review of [Yanli Liu's "The 4 Lines Every CLAUDE.md Needs"](https://levelup.gitconnected.com/the-4-lines-every-claude-md-needs-2717a46866f6) and the underlying `forrestchang/andrej-karpathy-skills` repo. The article's diagnosis — that behavioral constraints outperform feature checklists past a certain rule-count threshold — is partially a critique of ARIA-shaped systems. v2.14.0's response: keep the 34 rules (justified by ARIA's operational scope), add the 4-line foundation as the entry point, and acknowledge the evidence limit honestly. The four principles are not a replacement; they're the elevator-pitch summary of what the rules already enforce.

### Considered and deferred — `rules-examples.md` plugin-managed tier (S5)

Considered shipping a new plugin-managed file `template/rules/rules-examples.md` with before/after code walkthroughs per rule (modeled on [the Karpathy repo's EXAMPLES.md](https://github.com/forrestchang/andrej-karpathy-skills/blob/main/EXAMPLES.md)). Deferred because (1) per v2.13.7's "Considered and rejected — full approach file in plugin source" precedent, adding a new tier of shipped content is an ADR-class decision, not a routine release, (2) the integration cost is non-trivial — README.md tree, OVERVIEW.md managed-files list, setup SKILL.md (3 places) all require updates, and (3) the design intent question ("does ARIA ship per-rule examples, and at what tier — plugin-managed, user-curated like `approaches/`, or mixed?") deserves explicit deliberation. Recorded as a candidate for an ADR + future release.

### Considered and deferred — aria-cowork tool-portability framing (S6)

Considered adding a "principles transfer, phrasing doesn't" section to aria-cowork's README acknowledging the article's tool-portability point and the design challenge of generalizing aria-knowledge's enforcement layer (Code-only) to Cowork's skills-only surface. Deferred because aria-cowork is a sibling plugin with its own release cycle (v0.2.4 BUILT 2026-05-05); the framing edit belongs in aria-cowork's source, not aria-knowledge's. Recorded for the next aria-cowork release.

### Considered and deferred — litmus-test cull pass on 34 rules (S4)

Considered running Karpathy's litmus test ("Would removing this cause Claude to make a mistake it couldn't recover from?") on each of the 34 working rules to identify candidates for removal, demotion to user-side, or merging into adjacent rules. Deferred per user direction to a separate review session — the cull is judgment-heavy and shouldn't be bundled into a release that introduces new structure.

### Preserved

All 34 rules unchanged in body content and numbering. Rule 20's title evolved (refinement allowed per the file's stated rule-evolution policy) but the original "validate before assuming completion" sentence is preserved verbatim as the second half of the reframed rule. Retrospect-patterns.md from v2.13.9 unchanged.

---

## [2.13.9] - 2026-05-06

**Two new canonical retrospect patterns: `fix-without-call-site-audit` and `new-artifact-without-consumer-trace`.** Decomposes the broader completion-claim-without-trace family that v2.13.8 opened — covers two distinct sub-shapes surfaced by a five-instance real-use cycle, each with independent calibration data and distinct counter-disciplines. Pure additive content; no plugin behavior, schema, or skill changes.

### Added — Two canonical retrospect patterns (`template/rules/retrospect-patterns.md`)

- **`fix-without-call-site-audit`** — fixing a function-contract bug at one call site without auditing all sibling call sites of the same function for the identical gap. Detection cues cover commit-message framing ("fix at X" naming the symptom rather than the function), recurrence at sibling call sites within hours, and missing "audited all callers" language. Counter-discipline: grep all call sites of the function before claiming complete; document why any unpatched sibling is exempt. Calibrated against four sequential call-site instances in one 2026-05-05 close-out cycle — the strongest single-session calibration in the canonical library.

- **`new-artifact-without-consumer-trace`** — creating a new artifact (blueprint, route, skill, handler, template) consumed by a static enumerator (registry, manifest, dispatch table, type union) and claiming end-to-end completeness without verifying or updating the enumerator. Detection cues include the new file matching a plural-file shape, completion-claim language ("will work end-to-end", "auto-mirrors", "deployed") elided of consumer naming, and the consumer being reachable by a single grep that wasn't run. Counter-discipline: identify the consumer, grep for analogous entries, name the consumer explicitly in the completion claim. Inverse of the call-site discipline above: where `fix-without-call-site-audit` covers existing-function → multiple-callers, this pattern covers new-artifact → existing-enumerator. Calibrated against a new-artifact-vs-registry instance from the same 2026-05-05 close-out cycle.

### Origin — Sub-shape decomposition

Both patterns were surfaced by the same 2026-05-05 close-out cycle. The cycle produced five instances of completion-claim failure: four sharing the call-site-audit shape and one sharing the consumer-trace shape. Decomposition into two pattern entries (rather than one umbrella) preserves each calibration: 4x for `fix-without-call-site-audit`, 1x for `new-artifact-without-consumer-trace` — both at or above the bake level v2.13.8 shipped at.

### Layering map across four same-week releases

| Version | Layer | Surface |
|---|---|---|
| v2.13.6 | Rule text | "Architectural claims about existing systems" trigger added to Rule 34 |
| v2.13.7 | Layer 3 enforcement | Recognition cues + required `[Rule 34]` marker format |
| v2.13.8 | Retrospective × 1 | `architectural-claim-without-source-trace` (negative-existence claims about existing systems) |
| v2.13.9 | Retrospective × 2 | `fix-without-call-site-audit` + `new-artifact-without-consumer-trace` (two distinct completion-claim sub-shapes) |

The three v2.13.x retrospective patterns now cover three distinct completion-claim sub-shapes: "X doesn't enforce Y" (v2.13.8), "fixed at site X" omitting siblings (v2.13.9), and "X will work" omitting consumers (v2.13.9). Each has independent calibration data and distinct counter-disciplines.

### Considered and rejected — single umbrella pattern

Considered shipping one umbrella pattern (`completion-claim-without-trace`) covering both sub-shapes. Rejected because the 4x and 1x calibrations point to genuinely different counter-disciplines (audit call sites vs. grep registry consumers) — an umbrella would dilute both. Each canonical pattern in the library targets a specific counter-discipline, and merging the two would break that convention.

### Considered and deferred — artifact-shape hook gate

Considered shipping an artifact-shape gate in `pre-edit-check.sh` that fires on `Write` of new files matching registered globs in a per-project artifact-shape registry, emitting an advisory line ("creating artifact X matches shape Y; consumer is Z; have you grepped?"). Deferred because (1) one calibration instance for the consumer-trace shape is insufficient bake to lock the gate's storage location, severity (advisory vs. ack-required), and registry schema, (2) source-trace work required (read `pre-edit-check.sh`, current `aria-knowledge.local.md` schema, `enforcement-mechanisms.md` Layer 2/3 boundary criteria) is non-trivial and shouldn't be combined with content additions, and (3) the call-site-audit sub-shape is a poor fit for hook enforcement since it operates over edit-history not file-paths. Recorded as plan-of-record for v2.14.x pending usage data on (a) `new-artifact-without-consumer-trace` retrospective hit rate, (b) registry-shape diversity across projects, and (c) whether the canonical pattern alone closes the gap or hook enforcement is required.

### Preserved

All template content from v2.13.8 unchanged. `retrospect-patterns.md` is purely additive — the 10 prior canonical entries (`diagnose-from-shape-not-path`, `fix-bundling`, `bundle-unverification`, `speculative-iteration`, `judgment-confused-with-evidence`, `phrase-tell-consistent-with-evidence`, `pattern-matched-from-memory`, `pushback-as-cue`, `user-not-recruited`, `architectural-claim-without-source-trace`) are byte-identical to v2.13.8.

---

## [2.13.8] - 2026-05-05

**New canonical retrospect pattern: `architectural-claim-without-source-trace`.** Adds the failure-mode detection counterpart to v2.13.7's prospective Rule 34 layering. Where v2.13.7 added recognition cues + required marker format to catch the trigger *before* claiming, v2.13.8 adds the post-incident pattern that `/retrospect` runs detect when the trigger fired but wasn't caught — closing the prospective-plus-retrospective discipline pair against the same recognition gap.

### Added — Canonical retrospect pattern (`template/rules/retrospect-patterns.md`)

- **`architectural-claim-without-source-trace`** — new canonical pattern entry following the existing pattern-library format. Detection cues cover both code-side (architectural-substitution proposals before source-trace) and docs-side (stale "STILL OPEN" tracker entries written without source-trace) instances of the same recognition gap. The pattern's *Why it's a problem* names negative-existence claims ("X is not enforced") as the highest-confidence wrong-claim shape — *exactly* the claim that requires a source-trace because the cost of being wrong is shipping work that duplicates existing infrastructure or replaces working code. Counter-discipline cross-references Rule 34, framing the rule-text as the prospective catch and the pattern as the retrospective catch.
- First identified in a real-use retrospective on 2026-05-05 — same incident lineage as v2.13.6's Rule 34 trigger expansion and v2.13.7's enforcement layering. v2.13.8 closes the third leg.

### Origin — Layering map across three same-day releases

| Version | Layer | Surface |
|---|---|---|
| v2.13.6 | Rule text | "Architectural claims about existing systems" trigger added to Rule 34 (working-rules.md) |
| v2.13.7 | Layer 3 enforcement | Recognition cues + required `[Rule 34]` marker format + self-check questions (working-rules.md + change-decision-framework.md) |
| v2.13.8 | Retrospective detection | `/retrospect` pattern entry for post-incident bundle scans (retrospect-patterns.md) |

The three releases form a complete prospective-plus-retrospective discipline pair against the architectural-claims recognition gap. Rule 34 catches the trigger before the architectural turn happens; the new pattern catches the failure shape when `/retrospect` runs on a bundle where the trigger fired uncaught.

### Preserved

All template content from v2.13.7 unchanged. `retrospect-patterns.md` is purely additive — the 9 prior canonical entries (`diagnose-from-shape-not-path`, `fix-bundling`, `bundle-unverification`, `speculative-iteration`, `judgment-confused-with-evidence`, `phrase-tell-consistent-with-evidence`, `pattern-matched-from-memory`, `pushback-as-cue`, `user-not-recruited`) are byte-identical to v2.13.7.

---

## [2.13.7] - 2026-05-05

**Rule 34 enforcement layered up to soft Layer 3 (non-hook), plus restoration of `rules/retrospect-patterns.md` references in two user-facing template docs that were inadvertently dropped in v2.13.6.** Adds recognition cues, layer-trace methodology, required `[Rule 34]` marker format, self-check questions, and a CODEMAP-gap conditional clause to Rule 34's enforcement surface — without crossing to Layer 2 (hook). Closes the prevention-work item filed 2026-05-05 from a nav-architecture audit.

### Added — Rule 34 enforcement layered to Layer 3 (`template/rules/`)

Per `enforcement-mechanisms.md`, Rule 34 previously sat at Layer 1 (rule text + honor-system marker). The S62 nav-architecture audit (2026-05-04) provided calibration data: ~6 turns of architectural recommendation produced from a single-file render-layer read, when the actual rule was already implemented in a 20-day-old commit at the data-loader layer. **Recognition was the failure mode, not absence of rule text.** This release adds non-hook catches at Layer 3 — required output format that forces visible reasoning — without yet crossing to Layer 2 (hook prompt). Mirrors Rule 22's evolution arc: text first, format spec second, hooks once usage data clarifies trigger surface.

- **`template/rules/working-rules.md`** — under Rule 34's trigger list, added a **"Recognition cues"** sub-section listing two phrase-pattern categories that signal architectural-claims trigger risk:
  - *Positive architectural framing* — "the right model" / "the wrong model" / "architectural endpoint" / "the data flow should" / "this changes how [system] works" / "via substitution" / "substitution model" / "append model" / "should be [substituting / appending / merging]"
  - *Negative existence claims* (highest-confidence wrong-claim shape) — "doesn't enforce" / "isn't implemented" / "isn't handled" / "no [rule / check / validation] for this" / "this should be enforced but isn't" / "X is missing from [layer]"

  Phrase fragments give Claude concrete recognition cues, lowering threshold for the gate to fire. Single words like "append" or "merge" appear in routine code talk and are too noisy alone, so the gate is on phrase-fragments only.

  Also added a **"CODEMAP-gap conditional"** clause: if the project has a CODEMAP and the trigger fires for an area whose CODEMAP doesn't surface the rule-enforcement layer, file a gap before claiming. **Conditional on CODEMAP existence** — does not force CODEMAP creation as a Rule 34 prerequisite. If the project doesn't use CODEMAPs, the layer-trace methodology still applies; the gap-filing requirement doesn't.

- **`template/rules/change-decision-framework.md`** — under "Plan-Level Application (Rule 34)":
  - Added **"Layer-trace methodology (architectural-claims trigger)"** sub-section with the 5-step trace that populates Step 2 (Intake) and Step 6 (Validate) of the 7-step framework when the architectural-claims trigger fires: CODEMAP-first → cross-layer grep across data/transform/render/export/type/validator → `git blame` recent commits → simulate data flow with current state → only then claim.
  - Expanded the terse "Marker:" paragraph into a full **"Required marker format"** specification with a concrete 7-step body example. Per the 2026-05-02 design decision pinning the marker name (`[Rule 34]`, not `[Plan · Rule 22]`), the block mirrors Rule 22's per-edit marker structure but covers the whole plan, with framework body identical to Rule 22 High Impact format (Identify / Intake / Criteria / Solutions / Rank / Validate / Execute). Each labeled field is a recognition checkpoint; skipping a field means the framework step it represents was skipped at plan-formation time.
  - Added **"Self-check before claiming"** sub-section with 4 forcing-function questions targeting the highest-value recognition gaps (have I read the layer that actually contains the rule's enforcement; recent commits; CODEMAP coverage; cross-layer grep for negative-existence claims).
  - Updated **"Enforcement state"** paragraph to reflect Layer 3 status. Self-audit of transcripts for missing `[Rule 34]` blocks where they should appear is named as the calibration data feeding the eventual Layer 2 hook decision.

### Origin — Rule 34 enforcement layering

Surfaced from a nav-architecture conversation (2026-05-04): ~6 turns of architectural recommendation about a "missing" append model when the append model was already implemented in the loader, committed 2026-04-15 (20 days before the conversation). User explicit pushback ("review and validate") triggered the audit that surfaced the gap. The S62 retrospective produced a validated approach (`audit-before-architecture-claims.md`, user-side) and queued plugin-source prevention work as an extraction-backlog item dated 2026-05-05. This release closes that loop. The phrase-pattern categories and methodology shipped in plugin source are abstracted from that approach; concrete project-specific examples, file references, and memory cross-refs stay user-side.

### Considered and rejected — full approach file in plugin source

Considered shipping `template/approaches/audit-before-architecture-claims.md` as a new tier of plugin-managed content. Rejected because (1) plugin design intent (per `setup` SKILL.md) treats `approaches/` as user-curated content with only the README skeleton shipped, (2) the approach was validated 2026-05-05 with one example session — insufficient bake time across diverse projects to generalize, (3) project-specific examples (commit hashes, file paths, memory cross-refs) are what make it concrete; sanitizing for general use weakens it, and (4) shipping one approach establishes a precedent requiring a generalizability principle for which others ship — better filed as an ADR-class decision than a routine patch. The Layer 3 mechanism shipping here closes most of the gap the approach addresses without changing plugin source's content model.

### Fixed — `template/README.md` rules/ tree

The `rules/` directory tree in the README's "Structure" section now lists `retrospect-patterns.md` alongside the other four rules-tier files. Previously the file shipped at `plugin-claude-code/template/rules/retrospect-patterns.md` and was referenced by `/retrospect` and `/setup`, but the user-facing tree omitted it — making it undiscoverable to anyone reading the template README to understand what's in their knowledge folder.

### Fixed — `template/OVERVIEW.md` plugin-managed files paragraph

The "Plugin-Managed vs User-Owned Files" section's managed-files list now includes `rules/retrospect-patterns.md` between `rules/enforcement-mechanisms.md` and `projects/README.md`. This brings OVERVIEW.md in sync with `plugin-claude-code/skills/setup/SKILL.md` (lines 65 and 105), which already listed the file as plugin-managed and in the `/setup` diff loop — the contradiction has now been resolved.

### Origin — README/OVERVIEW docs regression

Surfaced during a `/setup` diff session on a v2.13.6-installed knowledge folder where the user noticed both files were listed as "user ahead, plugin regressed." Cross-checked against the file's actual presence in `plugin-claude-code/template/rules/` (still shipped) and against `setup/SKILL.md` (still authoritative on managed-file status). Both were correct; the documentation surface was the only point of drift. This patch restores the documentation invariant.

## [2.13.6] - 2026-05-05

**Documentation patch — surface aria-cowork as a sibling plugin, cross-reference the new Cowork plugin-authoring guide, and refine Rule 34's trigger list with an architectural-claims trigger surfaced by a real failure mode.** Pure CLAUDE.md + template/rules/ additions; no plugin behavior, schema, or skill changes.

### Added — Rule 34 trigger refinement in `template/rules/`

A new trigger added to Rule 34's plan-level review list: **"Architectural claims about existing systems"** — asserting how a system's data flow, rendering model, or rule-enforcement layer currently works *or doesn't work*. Single-layer reads frequently produce wrong claims when transformations live upstream; the claim becomes a load-bearing premise for downstream proposals.

- **`template/rules/working-rules.md`** — added the trigger bullet to Rule 34's trigger list, between "Asymmetric failure cost" and the "Out of scope" sub-section.
- **`template/rules/change-decision-framework.md`** — added the matching "or claims about existing systems" qualifier to the parenthetical trigger summary at the start of "Plan-Level Application (Rule 34)" so the summary stays in sync with the authoritative list.

**Origin:** A multi-turn conversation produced ~6 turns of architectural recommendation about an existing nav-construction layer, based on a single-file render-layer read. The actual rule was already implemented at the data-loader layer, in a commit predating the conversation by 20 days. Audit found this only after explicit pushback. The "currently works or doesn't work" qualifier specifically catches the highest-confidence wrong-claim shape — claims that an existing rule *isn't* enforced when it actually is, where the proposed fix duplicates already-existing logic.

**Cross-plugin parity:** aria-cowork v0.2.4 mirrors this template change in the same patch window — both plugins ship the same Rule 34 trigger list per the cross-plugin compatibility note in their CLAUDE.mds.

### Added — `CLAUDE.md` updates

- **New "Sibling Plugin (aria-cowork)" section** between the intro and Project Structure. Names the sibling repo (`mikeprasad/aria-cowork`, public, at `~/Projects/aria/aria-cowork/`), notes the shared `~/Projects/knowledge/` folder + additive-only `aria-config.md` schema (per aria-cowork's ADR-002), flags shared-surface edit caution (cross-plugin compatibility on field names, template/rules/ content, working-rules.md numbering), summarizes the 10-of-23 skills port + 5 explicit Code-only exclusions per aria-cowork's ADR-005, and forward-points to `knowledge/guides/claude/cowork-plugin-validation.md`.
- **New cross-project knowledge bullet**: `knowledge/guides/claude/cowork-plugin-validation.md` added to the Knowledge Repository list alongside the existing Code-side `plugin-development.md`. The Cowork guide captures durable findings from the aria-cowork v0.2.0 → v0.2.1 description-length-cap diagnostic — relevant to anyone coordinating with aria-cowork or shipping a Cowork-side plugin.

### Considered and rejected — `captured_via: aria-knowledge` field backport

aria-cowork v0.1.0–v0.2.3 wrote `captured_via: aria-cowork` to `/ask` and `/clip` frontmatter. Backporting a symmetric `captured_via: aria-knowledge` was considered for cross-surface provenance audit. **Rejected** per Rules 13 + 18 (simplest solution wins; foundational design over patching) — per-doc metadata accumulates unbounded cost across 100s of captured docs over months for a hypothetical-only consumer. aria-cowork v0.2.4 also removes the field on the same reasoning, restoring symmetry rather than breaking it. Better alternatives if surface-provenance becomes a real audit need: centralized `logs/capture-log.md` event log, time-correlation against existing surface session logs, or discretionary `tags: [surface:cowork]` on specific captures.

### Preserved

- All skill behavior unchanged.
- All hook configurations unchanged.
- aria-config.md schema unchanged.
- License + repository + keywords + homepage in plugin.json unchanged.
- All template content outside Rule 34 trigger list unchanged.

---

## [2.13.5] - 2026-05-03

Patch release adding the `/retrospect` skill — a structured retrospective tool for shipped commit ranges with per-fix validation enforcement, simpler-alternative discipline, re-diagnosis when fixes failed, and a growing failure-mode pattern library.

### Added — `/retrospect` skill in `plugin-claude-code/skills/retrospect/SKILL.md`

A new slash command that runs a 10-section retrospective on a shipped commit range, single commit, PR, or current session. The skill enforces a validation discipline: no fix is marked effective without explicit, named evidence (log event, reproduction-then-fix-verified, production instrumentation, or deployed-state check). Unvalidated fixes are flagged 🤷 Bundle-unverified or ❓ Unvalidated and cannot reach a KEEP action. Failed/partial fixes feed back into a re-diagnosis section that names surviving hypotheses and the specific instrumentation needed to discriminate between them — converting failed releases into evidence for the next attempt rather than another speculative fix.

The skill also runs a **failure-mode pattern check** against `rules/retrospect-patterns.md` (canonical) and `projects/<proj>/retrospect-patterns.md` (project-specific when applicable). Pattern hits surface named process failure modes (e.g., `diagnose-from-shape-not-path`, `bundle-unverification`, `speculative-iteration`, `phrase-tell-consistent-with-evidence`) so that recurring discipline gaps are visible across retrospectives. Novel patterns identified during a retrospective can be added to either library on user approval.

### Added — Canonical pattern library at `plugin-claude-code/template/rules/retrospect-patterns.md`

Seeded with 9 canonical, project-agnostic failure-mode patterns derived from real retrospective evidence. Each entry includes detection cues, why-it's-a-problem, counter-discipline, and a references list. The file is registered as plugin-managed in `plugin-claude-code/skills/setup/SKILL.md` — user-added patterns appear as diff prompts on plugin upgrades, never silently overwritten.

### Added — Plugin-managed registration in `plugin-claude-code/skills/setup/SKILL.md`

`rules/retrospect-patterns.md` added to both the educational plugin-managed file list and the diff-loop file list, so `/setup` recognizes the new template.

### Added — `/retrospect` listing in `plugin-claude-code/skills/help/SKILL.md` and `README.md`

Discoverability via `/help` and the public-facing skill catalog.

### Why this skill now

After shipping releases that produced multi-fix bundles where some fixes were necessary, some addressed misdiagnosed causes, and some over-engineered working code paths, the failure mode was clear: without a structured retrospective, the next instinct after a partial release is another speculative fix, repeating the loop. The `/retrospect` skill makes a structured retrospective the default response to a failed/partial release and treats post-deploy reality (not pre-merge code review) as the primary source of truth. Validation enforcement is the keystone — no fix is marked "shipped" without named evidence — and the failure-mode pattern library makes process learnings reusable across projects rather than re-discovered each retrospective.

### Soft-suggest trigger

The skill instructions include Claude-side judgment for offering `/retrospect` (never auto-executing) when the user's message contains regression cues ("still broken," "didn't fix," "review what you did," sharing test logs that show failure) and the current session has shipped recent fixes. Hook-based auto-trigger is deferred to v2 pending real-world calibration of which release events deserve auto-prompting.

### Out of scope (v1)

- Cross-change pattern *interpretation* (raw counts only)
- Automated pattern cue matching (judgment-based in v1)
- Auto-trigger on git push events
- Linear ticket auto-creation for FOLLOWUP-TICKET actions (drafts only in v1)
- Multi-bundle/series retrospectives

### Upgrade notes

- **Reinstall recommended** to pick up the new skill, the seeded canonical pattern library, and the setup registration.
- **No config migration** — no new hooks, no new top-level config keys. (A future `retrospect:` block in `~/.claude/aria-knowledge.local.md` will configure default destinations; v1 uses fixed defaults.)
- **No existing skill behavior changed** — `/retrospect` is purely additive.

## [2.13.4] - 2026-05-02

Patch release adding **Rule 34: Validate the plan with Rule 22's framework before executing** to the working-rules template, plus supporting cross-references in `change-decision-framework.md` and `enforcement-mechanisms.md`. Rule 33's plan-level counterpart — extends the same framework discipline from per-edit to per-plan scope.

### Added — Rule 34 in `plugin-claude-code/template/rules/working-rules.md`

Plan-formation discipline rule directing that any qualifying plan be validated with Rule 22's full 7-step framework *before* execution begins. The goal: validate that this is the right plan based on (a) what we know now, (b) what's accessible to know, and (c) the actual goal. A plan can pass per-edit Rule 22 on every edit and still fail systemically if any framework step — Identify, Intake, Criteria, Solutions, Rank, Validate, Execute — was skipped or shortcut at plan-formation time.

**Triggers (plan-level review required):** new features, external surfaces (composes with Rule 33), architecture/structural changes, re-implementations/rewrites/migrations, unfamiliar-domain plans, asymmetric failure cost (irreversible operations, shared state, public-repo content).

**Out of scope:** localized bug fixes, doc-only changes within existing structure, single-edit operations, routine maintenance.

**Marker:** Claude emits a `[Rule 34]` block before the first qualifying edit, formatted the same as Rule 22's per-edit marker but covering the whole plan. Per-edit `[Rule 22]` markers continue to fire after; in-scope edits can briefly reference the plan instead of re-deriving the framework.

### Added — Plan-Level Application section in `change-decision-framework.md`

Documents that Rule 22's framework runs at two scopes: per-edit (hook-enforced via `PreToolUse`/`PostToolUse` on Edit/Write) and per-plan (currently discipline-enforced via Rule 34's `[Rule 34]` marker). Includes plan-level application of all 7 framework steps and clarifies the relationship to ARIA's existing batch-manifest mechanism — batch manifests reduce ceremony *during* execution within a declared scope; Rule 34 validates plan *quality before* execution starts. Distinct axes, complementary in practice.

### Added — Rule 34 enforcement note in `enforcement-mechanisms.md`

Brief paragraph noting Rule 34 currently uses Layer 1 only (CLAUDE.md text + discipline-emitted marker). Hook enforcement deferred pending real-world calibration of trigger heuristics — matches Rule 22's own evolution arc (text first, hooks added once usage data clarified the trigger surface).

### Why this rule now

Same scraping-API origin as Rule 33: an integration was planned, executed cleanly per per-edit Rule 22, and failed on every call due to assumptions that the freely-accessible documentation would have corrected. Rule 33 patches the third-party-API-specific case at the call layer; Rule 34 patches the general plan-formation case at the framework layer. Both Rule 27's model-ID-rename origin and Rule 33's scraping-API origin fit Rule 34's trigger set retroactively, which validated the rule's design before shipping.

### Dogfood note

This release applied Rule 34 to its own creation. The original 8-surface plan (working-rules.md + plugin.json + marketplace.json + CHANGELOG + CLAUDE.md + 2 README refs + Projects/CLAUDE.md) was expanded to 10 surfaces after plan-level intake surfaced two real dependents — `change-decision-framework.md` (cross-reference target of Rule 34's wording) and `enforcement-mechanisms.md` (Rule 34's enforcement state belongs alongside Rule 22's). Without the plan-level review, Rule 34 would have shipped with a silent cross-reference inconsistency to a doc that's per-edit-only. The rule earned its keep on its first run.

### Upgrade notes

- **Reinstall recommended** to pick up Rule 34 in `working-rules.md`, the new section in `change-decision-framework.md`, and the enforcement-mechanisms note. Existing rules 1-33 are unchanged.
- **No config migration.** No new fields, no new hooks (yet), no skill changes.
- **Rule numbering preserved.** Rule numbers remain permanent IDs per the file's "How to Use" directive.

### Maintainer notes

- README.md and CLAUDE.md rule-count references updated from "33 rules" to "34 rules".
- Hook implementation deferred — trigger heuristics need real-world data before mechanism design. Discipline-only ship matches Rule 22's text-first evolution arc.
- Per `feedback_aria_versioning_patch_for_new_skill`: a single isolated rule addition is a patch bump.

## [2.13.3] - 2026-05-02

Patch release adding **Rule 33: Verify third-party surfaces against current docs before use** to the working-rules template. Single isolated rule addition; no skill, hook, or behavior changes.

### Added — Rule 33 in `plugin-claude-code/template/rules/working-rules.md`

Proactive doc-check rule directing that any third-party API, SDK, library, CLI, or external tool surface be verified against current documentation before the call is written. Defines *current* as fetched-or-read-this-session (not training memory, not analogy, not cached belief). Provides four objective triggers (first-use, version-volatile surfaces, silent-failure-prone calls, project-version-differs-from-training-version), a five-step routing order (local docs → `context7` → official docs → `--help` → ask the user), an explicit out-of-scope clause for language standard library, and a Rule 7 escape hatch when docs are inaccessible.

Composes with **Rule 27** as its proactive counterpart: Rule 27 verifies external identifiers after a failure; Rule 33 verifies before the call.

### Why this rule now

A new scraping API integration in another session produced multiple runtime errors — payload shape, auth, pagination — every one of which was resolved by reading the API documentation after the fact. Reading the docs before writing the integration would have prevented all of them. The rule names this failure mode (trained-knowledge drift + unfamiliar surfaces produce calls that look correct, pass review, and fail at runtime) and routes around it deterministically.

### Upgrade notes

- **Reinstall recommended** to pick up the new rule in `working-rules.md`. Existing rules 1-32 are unchanged.
- **No config migration.** No new fields, no new hooks, no skill changes.
- **Rule numbering preserved.** Rule numbers remain permanent IDs per the file's "How to Use" directive.

### Maintainer notes

- README.md and CLAUDE.md rule-count references updated from "31 rules" to "33 rules" (the count had been stale since Rule 32 added in v2.10.6; v2.13.3 corrects both the previous drift and the current addition).
- Per `feedback_aria_versioning_patch_for_new_skill`: a single isolated rule addition is a patch bump, not a minor.

## [2.13.2] - 2026-04-29

Documentation patch release. Adds three Tier-2 docs (public on the GitHub repo, NOT shipped in the plugin zip) that surface positioning, cross-pollination tracking, and release-validation discipline. **No plugin behavior changes** — `plugin/` is unchanged from v2.13.1, so users running v2.13.1 do not need to reinstall.

### Added — `docs/non-goals.md`

Explicit statement of what aria-knowledge does NOT aim to do, separated into permanently out of scope vs deferred. Helps prospective users self-select before installing, especially given the existence of adjacent execution-first plugins. Includes a pointer to [aria-ex1](https://github.com/nrek/aria-ex1) for users whose fit is execution scaffolding without the personal-knowledge-management surface.

### Added — `docs/related-repo-delta-ledger.md`

Append-only ledger of notable changes from related Claude Code plugin repos (currently aria-ex1), classified IMPORT / OPTIONAL / REJECT / N/A per change. Tracks both directions of cross-pollination — changes adopted from related repos AND changes that originated in aria-knowledge and were adopted downstream. Auditable record of design relationships across versions.

### Added — `docs/release-validation.md`

Pre-release checklist walking each skill, hook, and release-artifact step across eight phases (setup, exploration, capture, audit, lookup, hooks, distill, release artifacts). Catches regressions that `tests/run.sh` doesn't surface — drifted skill prose, renamed commands, broken `/setup` flows on existing config. Codifies the two-commit release pattern (source changes commit → `release.sh` → release artifacts commit → push).

### Why these now

aria-knowledge cross-pollinates with [aria-ex1](https://github.com/nrek/aria-ex1) (a leaner fork). Until v2.13.2 the relationship was implicit; the three new docs make it auditable, help users choose between adjacent plugins, and capture release-validation discipline that's been informal until now. All three docs adopt patterns observed in aria-ex1 v0.1.1 with content fully written from aria-knowledge's perspective.

### Upgrade notes

- **No reinstall required** for users on v2.13.1 — the plugin zip's contents are unchanged.
- **For new installs**, the v2.13.2 zip is functionally identical to v2.13.1's; the version bump exists to give the documentation additions a release reference.
- **Maintainers:** consult `docs/release-validation.md` before tagging the next release. Consult `docs/related-repo-delta-ledger.md` when reviewing changes from aria-ex1 (or future related repos) for adoption.

## [2.13.1] - 2026-04-29

Patch release fixing two real spec gaps surfaced during the first `/audit-share` run on a non-trivial knowledge folder. Both issues caused the v2.13.0 audit-share to silently produce zero shareable candidates on data that should have produced 15+. No config migration; no new fields; backward-compatible with v2.13.0 setups.

### Fixed — Path-derived tag detection (`/audit-share` Step 2)

The v2.13.0 spec required a frontmatter `project:` field for tag detection — but ARIA's actual data model uses `tags:` arrays plus path location under `projects/<tag>/`. `/index` Phase 4 (since v2.8.0) already recognized this via Decision #9 (path-derived tag union); `/audit-share` Step 2 just hadn't picked up the convention.

`/audit-share` Step 2 now derives project tag(s) from three sources, unioned (matches `/index` exactly):
- **Path-derived:** files under `{knowledge_folder}/projects/<tag>/` carry `<tag>` implicitly.
- **Frontmatter `project:` field** if present (multi-value comma-split).
- **Frontmatter `tags:` array:** any tag matching a project in `projects_shared_knowledge` triggers a share recommendation.

Multi-tag files (e.g., a file tagged `[architecture, cs, ss]` with `cs,ss` enabled) generate one share recommendation per matching project — independent destinations per share. This is cross-PROJECT-GROUP relevance, not cross-sub-repo within one group, so it doesn't trigger `cross/` treatment.

### Fixed — Multi-repo destination resolution (`/audit-share` Step 5, `/index` Phase 5, `/setup` folder detection)

The v2.13.0 spec wrote files to `<project-root>/_project-knowledge/` and ran `git add` from that path — assuming `<project-root>` is always a git repo. But `projects_list` paths often resolve to **container directories** that hold multiple sub-repos (e.g., a project group whose sub-repos are `<project-root>/<backend-sub-repo>/`, `<project-root>/<web-sub-repo>/`, `<project-root>/<mobile-sub-repo>/`). When the container isn't a git repo, the v2.13.0 `git add` step silently no-ops; files land in untracked container directories.

`projects_groups` already documents the role:sub-repo mapping per project tag (since v2.9.0, parsed by `/distill` and `/stitch`). v2.13.1 makes `/audit-share`, `/index`, and `/setup` all consult `projects_groups[tag]` when resolving destinations:

- **`/audit-share` Step 2.3 target-path resolution** — single-repo path unchanged. Multi-repo path runs a **role-detection heuristic** on file content + tags (keyword scoring against `backend`, `web`, `mobile`, plus any custom roles): single dominant role → that sub-repo's `_project-knowledge/`; multiple roles or tied scores → **primary sub-repo** (first declared role) `_project-knowledge/cross/`. User can `modify N` in the batch summary to override the recommendation.
- **`/audit-share` Step 5.8 `git add`** — now uses `git -C <sub-repo-root> add ...` to make the working tree explicit; protects against the silent-no-op trap where `git add` from a non-repo container exits cleanly without staging.
- **`/audit-share` Step 7 IDEAS-BACKLOG migration** — multi-repo migration target is `<project-root>/<primary-sub-repo>/_project-knowledge/IDEAS-BACKLOG.md` (always primary, since IDEAS-BACKLOG entries are project-wide queue items, not per-role). Filesystem `mv` from the container, then `git -C <primary-sub-repo-root> add` to stage.
- **`/audit-share` Step 5.5 public-repo flag** — visibility detection scoped per sub-repo (was per-container).
- **`/index` Phase 5** — single-repo scan unchanged. Multi-repo scan iterates `projects_groups[tag]` role:sub-repo pairs and scans each sub-repo's `_project-knowledge/`. The path stored for each entry is absolute-from-home so `/context` can render it correctly; the `project:` annotation is the parent project tag (not the sub-repo name) so cross-sub-repo discovery within a group still groups by project.
- **`/setup` existing-folder detection** — same single-vs-multi branch; multi-repo projects probe each sub-repo independently.

### Why fold these patches together

Both fixes are corrections to the same narrow surface (where do we read from / write to for the team-shared tier) that v2.13.0 shipped with overly narrow assumptions. They share the same `projects_groups[tag]` lookup and the same single-vs-multi-repo branch shape, so fixing them in one release keeps the spec internally consistent across audit-share / /index / /setup.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` (or unzip the v2.13.1 release zip into that directory).
- **Run `/setup` after upgrade** to record `last_setup_version: 2.13.1`. No config field changes from v2.13.0 — `projects_shared_knowledge` (comma-separated tag list) and `author_tag` (string) are unchanged in shape.
- **Backward-compatible with v2.13.0 configs.** Single-repo project setups continue to work identically. Multi-repo project setups (those with `projects_groups[tag]`) now actually function — previously they would silently produce zero shareable candidates and zero indexable team-shared files.

## [2.13.0] - 2026-04-28

Minor release. Adds a third knowledge tier — **Shared Knowledge** — that lets developers promote selected personal knowledge into per-repo `_project-knowledge/` folders so teammates working in the same code repo can find and read it. The personal knowledge tier (`~/Projects/knowledge/`) and project knowledge tier (`projects/{tag}/`) are unchanged; the new tier composes with both. Fully opt-in and **per-project**: the `projects_shared_knowledge` config field is a comma-separated tag list (e.g., `cs,ss`) — empty/missing means feature disabled, populated means enabled for those specific projects only. Most users have many repos but only a few with teams to share with; this avoids accidentally exposing solo projects to a non-existent team-share workflow.

The release also renames the `/audit-knowledge` Accept submenu disposition from `plan` to `backlog` (with corresponding rename of the destination file `PLAN.md` → `IDEAS-BACKLOG.md`) — the `plan` term was overloaded with implementation-plan semantics elsewhere (`docs/plans/`, `superpowers:writing-plans`) and consistently produced confusion about what the destination was for.

### New — `audit-share` skill (alias `share-audit`)

The batch-review surface for promoting personal knowledge to team-shared. Walks `~/Projects/knowledge/insights/`, `decisions/`, `approaches/`, `rules/`, plus IDEAS-BACKLOG.md entries, and recommends a destination per item:

- **Repo-scoped** items (matching a project tag in `projects_list`) → `<project-root>/_project-knowledge/{YYYY-MM-DD}-{author}-{slug}.md`
- **Cross-cutting** items (`project: cross`) → `<project-root>/_project-knowledge/cross/{YYYY-MM-DD}-{author}-{slug}.md` in a user-selected repo
- **Skip** items (no project tag, or types out of scope — `feedback`, `references`)

Presents a numbered batch summary grouped by recommended action; user picks `all`, specific numbers, `modify N` to change action/destination/slug, or `skip`. Public-repo targets get a sanitization warn-prompt before each write. Files are `git add`-ed but not committed — user reviews staged changes and commits through their normal flow.

Frontmatter back-pointers maintain provenance both directions: personal copies gain a `shared:` array entry pointing at where each share landed; team copies carry `origin:`, `shared_by:`, and `shared_at:` fields naming the source.

### New — `_project-knowledge/` folder convention

Each project repo where the user has shared knowledge gains a conventional folder:

```
<project-root>/
└── _project-knowledge/
    ├── README.md                           (auto-created on first share — convention explainer for non-ARIA teammates)
    ├── IDEAS-BACKLOG.md                    (idea queue moves here when feature enabled)
    ├── {YYYY-MM-DD}-{author}-{slug}.md     (repo-scoped knowledge)
    └── cross/                              (cross-cutting items)
        ├── IDEAS-BACKLOG.md
        └── {YYYY-MM-DD}-{author}-{slug}.md
```

Folder name `_project-knowledge/` — leading underscore sorts to top of repo listings; NOT hidden; tool-agnostic so non-ARIA teammates can read/write the markdown directly.

### New — `/index` Phase 5 + `/context` "Team-shared" grouping

Read-side aggregation — no STITCH integration needed:

- `/index` gains a new scan phase that walks each project's `_project-knowledge/` folder and adds entries to a new `## Team-Shared Tag Index` section in `index.md`. Path-derived metadata (`project: <tag>`, `scope: repo|cross`) is preserved as annotation.
- `/context` reads the new section in Step 4c and groups results in Step 5 as **Team-shared → Project-specific → Cross-project** (continuous numbering across all three).

Tag-based discovery works seamlessly — a query like `/context api` surfaces team-shared `api` files alongside personal/project results. No new STITCH file format; no new query syntax.

### New — `/setup` integration

After Project Setup completes, `/setup` asks two follow-up questions when projects tier is enabled:

1. *"Which projects do you want to enable shared knowledge for?"* — sets `projects_shared_knowledge` to a comma-separated tag list (or empty for disabled); each tag must already exist in `projects_list`
2. *"Author tag for shared-knowledge filenames?"* — sets `author_tag: <string>` (falls back to deriving from `git config user.name`)

Followed by an offer to invoke `/audit-share` inline as the cold-start sweep.

The CLAUDE.md reference offer (a 5-line "Team-Shared Knowledge" section pointing teammates at the convention) lives inside `/audit-share` Step 6.5 rather than at setup time. It fires the first time `audit-share` actually writes to a repo's `_project-knowledge/` folder — at that moment the folder + README exist (no aspirational forward reference), the user has just made an active sharing decision, and the prompt can carry per-repo confirmation with git-tracked detection and three warning tiers (public remote / private remote / unknown). Default is `N` regardless of tier; idempotency check skips the prompt on subsequent shares to repos that already have the reference.

For multi-repo projects (those with a `projects_groups` entry), Step 6.5b runs after the sub-repo offer to additionally surface the **container's** CLAUDE.md with a group-aware text variant. The container variant references each sub-repo's `_project-knowledge/` folder by name rather than describing a non-existent `<container>/_project-knowledge/`. Same per-file confirmation, default-N posture, and three-tier warning system as 6.5a. A session-level cache prevents re-prompting when subsequent shares hit sibling sub-repos within the same `audit-share` invocation; idempotency at the file level (existing-heading probe) prevents duplicate appends across runs.

### Changed — `/audit-knowledge` Accept submenu disposition `plan` → `backlog`

The previous `plan` disposition wrote to `plans/{slug}.md` (or `PLAN.md`) with `## Goal`/`## Why` headers — overloading the `plan` term with execution-plan semantics that already had separate homes (`docs/plans/`, `superpowers:writing-plans` output). Renamed to `backlog` with destination `IDEAS-BACKLOG.md` at the project-root path; treats the destination as a queue (dated entries) rather than a sequenced execution doc.

When the project's tag appears in `projects_shared_knowledge`, the destination shifts to `<project-root>/_project-knowledge/IDEAS-BACKLOG.md` (team-visible); migration of existing project-root `IDEAS-BACKLOG.md` files happens on first `/audit-share` invocation. Projects whose tags are NOT in `projects_shared_knowledge` keep IDEAS-BACKLOG.md at the project root (personal-tier behavior unchanged).

16 surfaces across 7 files updated for terminology consistency: `audit-knowledge/SKILL.md`, `template/intake/ideas/README.md`, `template/OVERVIEW.md`, `template/README.md`, `QUICKSTART.md`, `extract/SKILL.md`, `audit-config/SKILL.md`. The previous `audit-config` Step 5 PLAN.md alignment check (now obsolete under queue semantics) replaced with an IDEAS-BACKLOG.md presence check.

### Changed — `/setup` Step 8 summary surfaces shared-knowledge status

Adds one bullet to the post-setup confirmation: *"Shared knowledge: enabled (author_tag: {tag}) | disabled (opt-in via re-run /setup)"*.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` (or unzip the v2.13.0 release zip into that directory).
- **Run `/setup` after upgrade** to record `last_setup_version: 2.13.0` and (optionally) opt into the new Shared Knowledge tier. The two new config fields (`projects_shared_knowledge`, `author_tag`) are introduced as `[NEW]` markers in the advanced-options bundle on re-run.
- **Backward-compatible defaults.** `projects_shared_knowledge` defaults to empty (feature disabled, no projects enabled); existing users who don't opt in see no behavior change. A legacy literal `true` from any pre-publish v2.13.0 stub is treated the same as empty and triggers `/setup` to populate the list properly on next run. The `plan → backlog` disposition rename is also backward-compatible — the new disposition keyword `backlog` is recognized; users with existing IDEAS-BACKLOG.md files at project-root continue to work.
- **No config migration required.** Existing configs (with or without `projects_groups`, with or without project tier enabled) work unchanged.

## [2.12.2] - 2026-04-26

Patch release. Closes a long-standing documentation gap around `projects_groups`, the multi-line YAML field consumed by `/distill` and `/stitch` for multi-repo group mapping. Until now the field was documented only inline in the two consuming skills' shared-block, with no single-page schema reference and no `/setup` awareness — users running `/setup` got no signal that the field existed in their config, and users hand-editing `~/.claude/aria-knowledge.local.md` had no canonical place to look for the schema. v2.12.2 adds a dedicated `CONFIG.md` reference covering all 18 frontmatter fields plus the skill-only tier, and extends `/setup` with read-only awareness so re-runs surface existing groups and link to the schema.

### New — `plugin/CONFIG.md` configuration schema reference

A single-page reference documenting every field in `~/.claude/aria-knowledge.local.md`:

- **Two parser tiers** — explicit framing of the hook-parsed (column-1, grep+sed-safe) versus skill-only (multi-line YAML, parsed by Claude in skill context) split per ADR 028. Helps users understand why some fields fit the `/setup` advanced-options bundle and others don't.
- **Hook-parsed table** — all 18 single-line fields with type, default, and which hook or skill reads them.
- **Skill-only schema** — `projects_groups` block structure with standard role names (`backend`, `web`, `mobile`), custom-role conventions, and the optional `stitch_path` sub-field per ADR 034.
- **Format rules and hand-editing checklist** — the same parser invariants that have been embedded in the `/setup` SKILL Step 7 formatting block, surfaced here for users who edit the config directly without running `/setup`.

Cross-linked from `QUICKSTART.md`, `setup` SKILL Step 6, and the `<!-- shared-block: group-loader -->` opening line in both `distill` and `stitch` SKILL.md.

### Changed — `/setup` awareness for skill-only fields

Four touch-points in `setup` SKILL extended to surface `projects_groups` without trying to flatten or interactively edit it:

- **Step 1** — when an existing config is detected, also detect the `projects_groups` block and report current group count alongside the standard "already configured" announcement. Uses an awk pattern bounded by the closing frontmatter delimiter so it can't escape the block.
- **Step 6** — new "Skill-only fields (read-only awareness)" subsection below the advanced-options bundle. Restates the current group count if Step 1 detected it, or describes how `/distill --group=<tag>` and `/stitch create <tag>` auto-populate the field via their existing bootstrap (ADR 032). Explicit that `/setup` never writes new entries here.
- **Step 7** — two new formatting rules: skill-only multi-line YAML blocks must sit at the end of the frontmatter (after every column-1 hook-parsed key), and the block must be preserved verbatim in update mode (no reformatting, no reordering, no sub-entry stripping).
- **Step 7b** — three structural validation checks for `projects_groups`: block placement (must be last), indentation shape (2-space tag, 4-space role), and tag cross-check against `projects_list` (warn, do not fail — staging tags before path-mapping is a legitimate pattern).

### Changed — `distill` and `stitch` shared-block cite `CONFIG.md`

The opening line of the `<!-- shared-block: group-loader -->` block in both `distill/SKILL.md` and `stitch/SKILL.md` now references `CONFIG.md` "Skill-only fields" as the canonical schema reference, including the optional `stitch_path` sub-field and custom-role conventions. The shared-block remains the operational specification (what the skill does at runtime); `CONFIG.md` is the schema reference (what valid input looks like).

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` (or unzip the v2.12.2 release zip into that directory).
- **Run `/setup` after upgrade** to record `last_setup_version: 2.12.2` and surface the new Step 1 group-count detection if you have `projects_groups` configured.
- **No breaking changes.** `projects_groups` schema is unchanged from prior versions; the auto-propose bootstrap in `/distill` and `/stitch` continues to work identically. No new config keys; no existing config keys changed shape; no skill behaviors changed beyond `setup` awareness.
- **No config migration required.** Existing configs (with or without `projects_groups`) work unchanged.

## [2.12.1] - 2026-04-26

Patch release. Closes a version-awareness gap: existing users who upgrade ARIA between 30-day setup-cadence windows currently see no prompt to re-run `/setup`, so template diffs and any new config keys land silently until either the cadence fires or the user notices independently. v2.12.1 adds an immediate version-mismatch prompt at session start and surfaces the running ARIA version inside `/setup` itself so users always know which version configured their knowledge folder.

### New — `last_setup_version` config field

`/setup` now records the plugin version active at the time of the run as a YAML frontmatter field in `~/.claude/aria-knowledge.local.md`:

```yaml
last_setup_version: 2.12.1
```

Read at Step 1 from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` via the same grep+sed pattern as every other config field (no jq dependency added). Written at Step 7 alongside the other config keys. Verified at Step 7b for semver shape and round-trip match against the Step 1 capture. Format rules: bare digits-and-dots, no `v` prefix, no quotes — matches the parser invariant for the rest of the frontmatter.

### New — version-mismatch prompt at session start

`bin/session-start-check.sh` now compares the installed plugin version against `last_setup_version` from config. When they differ:

> *"ARIA was updated (last /setup ran on v{old}, plugin is now v{new}). Run /setup to apply template diffs and surface any new config keys?"*

Three guards keep the prompt silent in non-upgrade cases: installed version must be parseable from `plugin.json`, `last_setup_version` must be present in config (so fresh installs and pre-2.12.1 users don't trigger), and the two strings must differ. The existing 30-day cadence prompt becomes the fallback — it only fires when the version-mismatch prompt did not, so users never see two competing update prompts in one session.

### Changed — `/setup` displays the ARIA version

Three surfaces in `setup` SKILL now show the version:

- **Step 1 announcement:** *"aria-knowledge v{version} is already configured"* (existing config) or *"Let's set up aria-knowledge v{version}"* (fresh install). When the recorded `last_setup_version` differs from the installed version, an additional line surfaces: *"Plugin upgraded from v{X} → v{Y} since last setup. Diff prompts and any new config keys will surface in the steps below."*
- **Step 8 summary:** the `Setup complete!` header becomes `Setup complete for ARIA v{version}.` so users see what they configured.
- **Step 7 frontmatter write:** `last_setup_version` is recorded so the next session-start hook has the data it needs to detect the next upgrade.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` (or unzip the v2.12.1 release zip into that directory).
- **Run `/setup` once after upgrade.** This populates `last_setup_version` in your config so the next plugin upgrade triggers the new prompt. Until then, existing v2.12.0 users still see the time-based cadence prompt as before — the version-mismatch prompt is silent without `last_setup_version` in config.
- **No breaking changes.** The session-start hook's existing 30-day cadence check is preserved as a fallback for users who haven't yet recorded `last_setup_version`. No existing config keys changed shape; no existing skills changed behavior beyond `setup`.
- **No config migration required.** Existing configs work unchanged. The new key is added on the next `/setup` run.

## [2.12.0] - 2026-04-26

Minor release. Expands the idea-disposition vocabulary in `/audit-knowledge` from a single Accept verb (which previously only meant "copy to external tracker") to a seven-destination submenu: `tracker | roadmap | todo | adr | plan | bundle | rule`. Adds a new `intake/rules-backlog.md` artifact to receive the `rule` path. Adds a `ticketing_plugins` config key so the audit can hint at user-installed ticket-drafting plugins per project tag without coupling ARIA to any specific plugin name. Adds detection probes that surface `roadmap` / `todo` only when the relevant file exists at the project root or under `docs/`. Adds bundle auto-clustering when the audit detects 2+ ideas sharing project tag and ≥2 significant title words. No behavior changes for existing knowledge backlogs (insights/decisions/extraction); existing single-Accept disposition still works as `Accept → tracker` (the new default).

### Why this matters

The single-Accept-to-tracker model assumed every actionable idea belonged in an external issue tracker. In practice many ideas are too small for tickets (TODO line), too coarse for tickets (roadmap entry), too principled for tickets (working-rule), or actually decisions in disguise (ADR candidate). The new submenu lets each idea route to the surface that fits its weight, while preserving the routes-out-not-promotes invariant — `adr` and `rule` paths land in their respective backlogs for normal audit-cycle review, not directly in `decisions/` or `rules/`.

### New — Accept submenu in `/audit-knowledge`

Step 2c2 expanded with the seven-destination spec. Step 6 Pending Ideas presentation now uses a two-step prompt (top-level Accept/Reject/Defer/Reclassify; Accept submenu computed per idea). Submenu items are conditional:

- `tracker | adr | plan | rule` — always available.
- `roadmap` — only if `ROADMAP.md` exists at the idea's project root (closest ancestor with `.git/` or `CLAUDE.md`) or under that root's `docs/`.
- `todo` — same probe pattern for `TODO.md`.
- `bundle` — only when the audit detects a cluster (same project tag + ≥2 shared significant title words across 2+ pending ideas).

Routing behavior per destination is documented in the SKILL Step 2c2 table and mirrored in `intake/ideas/README.md`.

### New — `intake/rules-backlog.md` artifact

Mirrors the shape of `decisions-backlog.md` but for rule candidates — observations or proposals about *how to work* (rather than *what is*). Populated three ways: via the `Accept → rule` path during idea audits, via `/extract` when conversation surfaces a repeating discipline, or by manual append. Reviewed in `/audit-knowledge` Step 2c3 with three valid promotion targets — all inside the user memory directory or `{knowledge_folder}` (ARIA never writes to project source):

- **User memory** — write `feedback_*.md` under the active project's `~/.claude/projects/{cwd-encoded}/memory/` directory (matches existing feedback-memory pattern).
- **Cross-project ARIA rule** — append to `{knowledge_folder}/rules/user-rules.md` (user-owned counterpart to plugin-managed `working-rules.md`).
- **Project-tier working rule** (projects tier only) — append to `{knowledge_folder}/projects/{tag}/rules/working-rules.md`. Setup's Step 7c scaffolds the parent `rules/` subdirectory under each configured project so this destination is always available when the projects tier is enabled.

Rejected entries clear from the backlog. The new file is registered in `setup` SKILL Step 3 expected-files list and Step 4 never-diff list (user-owned).

### New — `ticketing_plugins` config key

User-declared registry mapping project tags to ticket-drafting plugin commands (e.g., `proj-a:foo-ticket,proj-b:bar-ticket`). Format mirrors `projects_list` so the existing pure-grep/sed config parser handles it without `bin/config.sh` changes. When set, `/audit-knowledge` prints a one-line hint during `Accept → tracker` disposition (e.g., *"Use `/foo-ticket` to draft this as a ticket"*) for ideas whose project matches a mapped tag. Hint only — never auto-invokes the other plugin's skill (preserves consent and avoids cross-plugin coupling). Empty default; users who don't use a ticketing plugin or prefer manual tracker copy-paste leave it empty.

`setup` SKILL extended at four surfaces: Step 6 Advanced Options (now always shown — see "Advanced Options now unconditional" below), Step 7 frontmatter write, Step 7 formatting rules, and Step 7b round-trip + empty-sentinel verification. The advanced-options bullet for `ticketing_plugins` carries inline validation rules (each pair has exactly one `:`, tags reject `:`/`,`, plugin commands strip leading `/` with a warning). Step 8 summary line confirms the disposition (configured count or empty default). Plugin tags follow the same `:`/`,` exclusion as `projects_list`; plugin-command values must be bare command names without leading `/` (the audit prepends the slash when printing the hint).

### Changed — `/stats` and `/backlog` now read four backlogs

Both skills updated to include `intake/rules-backlog.md` alongside insights/decisions/extraction:

- `/stats` Intake section gains a `Pending rules: N` line.
- `/backlog` overview emits a Rules row; `/backlog rules` opens the detail view; `/backlog clear rules YYYY-MM-DD` clears entries by date.
- `/audit-knowledge` Step 1 backlog-count loop includes rules-backlog so the entry-count trigger threshold (default 20) accounts for rule candidates too.

Audit-log fields in Step 8 now break out per-destination counts (`accepted: A1 tracker / A2 roadmap / ... / A7 rule`) and add `R rules reviewed` to the Counts line. Zero-valued sub-counts are omitted to keep entries readable.

### Changed — `ideas_staleness_threshold_days` default lowered 21 → 7

Pending ideas under the staleness threshold auto-defer (no per-entry prompt) per Step 6's existing rule. At the 21-day default, modest-volume idea capture from `/extract` could silently accumulate for three weeks before any forced engagement, and high-volume capture (the migration brought 188 entries onto a single user's machine in this release) compounds that. Lowering the default to 7 days aligns staleness pressure with the existing knowledge audit cadence (`audit_cadence_knowledge: 7` default) — every safety-net audit cycle now finds at least one tier of ideas eligible for forced disposition. Trade-off: fresh ideas captured today get nagged within a week. For users who prefer the old behavior, set `ideas_staleness_threshold_days: 21` (or any other integer) in `~/.claude/aria-knowledge.local.md`.

Surfaces touched: `setup` SKILL Step 6 advanced-options prompt + Step 7 frontmatter default; `audit-knowledge` SKILL Step 2c2 + Step 6 default-mentions; `context` SKILL `KT_IDEAS_STALENESS_DAYS` default and fallback; `intake/ideas/README.md` staleness paragraph. Existing user configs retain whatever value they had — the source default change only affects new installs that use empty advanced-options answers.

### Changed — Advanced Options now unconditional + new-key highlighting

`setup` SKILL Step 6 Advanced Options previously rendered only when the user explicitly asked for it OR re-ran setup with an existing config. Fresh installs that didn't ask got the entire bundle silently (defaults applied without surfacing what was tunable). With the bundle now containing settings whose right values depend on user landscape — `ticketing_plugins`, `critical_paths`, `ideas_staleness_threshold_days` — silent defaults misfire often enough that the gate was costing users more than it saved.

**New behavior:** the Advanced Options bundle is shown on every `/setup` run, fresh or re-run. New users see what's tunable up front; returning users get a chance to surface and adjust values they didn't configure initially. Auto-mode users still get the bundle and can press enter to accept defaults — the difference is that the no-op is now an explicit choice rather than a silent skip.

**New-key highlighting (re-runs only):** before rendering the bundle, `setup` runs `grep -q '^{key}:'` against the existing config for each Advanced Option key. Any key missing from the user's config (an upgrade case where a plugin update added the key) gets a `[NEW]` annotation in the bundle and a one-line preamble note: *"Some settings are new since your last `/setup` run — `[NEW]` markers below indicate keys added by plugin updates that aren't yet in your config. Consider whether to set them now."* Fresh installs skip the comparison since there's no prior config — bundle just renders defaults.

**Step 6b removed.** The original v2.12.0 design added Step 6b as a focused y/n for `ticketing_plugins` to escape the gate. With the gate gone, Step 6b became redundant — the always-on bundle subsumes its purpose. Its missing-key detection and inline validation rules survived; they now live in the always-on Advanced Options bundle directly. No regression for `ticketing_plugins` setup: upgraders still see it flagged `[NEW]` and can populate it from the bundle.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the SKILL changes, the new template artifact, and the version bump.
- **Run `/setup` to land `intake/rules-backlog.md`** in your knowledge folder. Existing folders won't get the file automatically — `/setup` adds missing files in update mode without overwriting anything else. Until then, `/audit-knowledge` will report the missing file with a "run /setup to repair" note.
- **`ticketing_plugins` surfaced via the always-on Advanced Options bundle.** Every `/setup` run (fresh install or re-run) shows the bundle; on re-runs, keys missing from the existing config are flagged `[NEW]` so upgraders see what the plugin update added. To set a value: type the comma-separated mapping (e.g., `proj-a:foo-ticket,proj-b:bar-ticket`) when prompted, or press enter to keep the current value/default. Plugin commands are bare names (no leading `/`); leading `/` is stripped automatically with a warning.
- **No behavior change for existing dispositions.** A user choosing `Accept` and not picking a submenu destination receives a follow-up prompt — there's no implicit default. Older `Accept → tracker` muscle memory still works since it remains an explicit option.
- **Public-repo discipline preserved.** No project-specific plugin names ship in templates, SKILLs, or the manifest. Examples in docs use generic placeholders (`proj-a:foo-ticket`).
- **Backward compatible audit-log entries.** Pre-2.12.0 entries kept the old four-option Ideas-disposition shape (`A accepted → tracker, B rejected, C deferred, D reclassified`); these remain valid and don't need rewriting. New entries use the seven-destination breakdown.

## [2.11.2] - 2026-04-24

Patch release. Adds `/snapshot`, an on-demand equivalent of the pre-compact transcript capture hook. Until now the only way to archive a raw session transcript was to wait for Claude Code's PreCompact event — a useful safety net, but not a control the user can reach for mid-session before switching context or kicking off a risky operation. `/snapshot` closes that gap by reusing the hook's archival contract under explicit user invocation.

### New — `/snapshot` skill

`plugin-claude-code/skills/snapshot/SKILL.md` registers the command. The skill is a thin wrapper: it delegates to `bin/save-transcript.sh` and relays the output verbatim. Description triggers include `/snapshot`, "snapshot the session", "save this conversation", "archive this session", and explicitly contrasts with `/extract` (knowledge synthesis) and `/clip` (URL or snippet capture) so the LLM routes cleanly between the three. `allowed-tools: Bash`.

Also registered in `/help`: row added to the commands table and to the Sonnet-low-effort row of the model-recommendations table. `/snapshot` is mechanical (bash-script-driven), so Sonnet is the right default — no judgment lift from a larger model.

### New — `bin/save-transcript.sh` helper

Mirrors the archival logic of `pre-compact-check.sh` with three differences driven by the on-demand context:

- **Bypasses `KT_AUTO_CAPTURE`.** The config key's name scopes it to hook-driven auto capture; explicit `/snapshot` always runs. Honoring the gate would silently refuse an explicit command, which is worse UX than violating the (auto-scoped) flag.
- **Discovers the transcript instead of receiving it.** The hook gets `session_id` and `transcript_path` via stdin JSON. A skill-invoked shell has neither. The script finds the current session's transcript by picking the most recently modified `*.jsonl` under `~/.claude/projects` using fractional-second mtime (`stat -f "%Fm"`), which disambiguates concurrent Claude Code windows that `ls -t`'s second granularity cannot.
- **Writes to the same captures directory.** Snapshots land in `intake/pre-compact-captures/{YYYY-MM-DD}_{sid8}.md` — same filename convention and same folder as the hook, so `/extract` and audit review pick them up without change.

Same-session repeats overwrite (matches hook behavior — filename is determined by date + session-id-short).

### Changed — SessionStart hook surfaces codemap staleness

`bin/session-start-check.sh` now annotates each `CODEMAP.md` found under cwd with age, git-activity count, and staleness classification (current / possibly stale / stale) — previously it only listed the paths. Classification mirrors `/audit-knowledge` Step 5d exactly:

- **Stale** — `>30 days` since last update AND `>0` files changed
- **Possibly stale** — `>14 days` since last update AND `>20` files changed
- **Current** — otherwise

Header parse looks for `> Last updated: YYYY-MM-DD | …`; falls back to file mtime when the header is missing. Activity count runs `git log --name-only --since="$CM_DATE"` from the codemap's directory — multi-repo parent folders (where the parent dir isn't itself a git repo) report 0 files changed, matching the same limitation as `/audit-knowledge` Step 5d. Guarded on `command -v git` so the hook degrades gracefully when git isn't installed. Head-5 cap on codemap count preserved. Bash-side cost is well under the hook's 10s timeout.

The goal is cheap visibility: users now see staleness classifications at session start without having to run a full `/audit-knowledge`. The audit remains the canonical classifier — session-start just mirrors its logic so the two surfaces agree.

### Changed — `/stats` dashboard adds Codemap Status section

`skills/stats/SKILL.md` gains a new Step 3a that globs for `CODEMAP.md` files under cwd (depth 0-2), parses the `Last updated` header, and reports date + days-since per codemap. The new `### Codemap Status` section renders between `### Audit Status` and `### Index Health` in the dashboard output. Frontmatter description updated to include "codemap dates" in the metric list.

Presentation-only: `/stats` reports the raw date; classification and git-activity checks remain with `/audit-knowledge` Step 5d. This keeps `/stats`'s read-only posture and its "fast — just counting and date parsing, no heavy analysis" rule intact — no Bash added to allowed-tools.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the new skill, helper script, and hook changes.
- **No config migration.** No hook contract changes. No behavior changes for existing skills beyond the additive surfaces.
- **macOS-only.** Three BSD-specific constructs: `stat -f "%Fm"` (save-transcript.sh fractional mtime), `stat -f "%Sm" -t "%Y-%m-%d"` (session-start codemap mtime fallback), and `date -j -f "%Y-%m-%d"` (session-start epoch math). A Linux port would need `stat -c "%.Y"`, `date -r $(stat -c %Y …) +%Y-%m-%d`, and `date -d "$date" +%s` respectively. Matches the rest of the shipped hooks.
- **Concurrent-session disclaimer (snapshot).** If two or more Claude Code windows are active on the same machine, `/snapshot` picks the most-recently-written transcript, which is usually but not always the invoking window. The source path is shown in the output so users can verify at a glance.
- **Multi-repo codemap limitation (session-start).** Codemaps at the root of a parent folder that contains sub-repos but isn't itself a git repo report 0 files changed — `git log` runs from the codemap's directory and returns empty for non-git paths. Classification will read as "current" regardless of sub-repo activity. Same limitation as `/audit-knowledge` Step 5d today; a future enhancement could recurse into sub-repos.

## [2.11.1] - 2026-04-24

Patch release. Reduces Rule 22 compliance-block verbosity under Claude Opus 4.7 without weakening the forcing function. Driven by observation that 4.7 fills open-ended slot placeholders more expansively than 4.5/4.6 did, multiplied by ARIA's per-edit emission frequency. No hook, regex, doctrine, or enforcement-mechanism changes — the shift is entirely in the template examples and in a single template slot that was duplicating work the pre-edit block already performed.

### Changed — Post-Edit PASS templates collapse to secondary-status clause

Both tiers (High Impact and Low Impact) now use `[Rule 22 · Scope] PASS — [secondary status: none / what was reviewed]` as the pass-format template. Previously the placeholder was `[what was done + why it passes, including secondary status]` — which invited Claude to restate the plan that the pre-edit block had already established. The revised slot keeps the Q5 secondary-impact check visible (which is the post-edit hook's primary discipline) while dropping the "what was done" restatement. This is the biggest per-session saver because post-edit PASS fires on the majority of successful edits. The `pass with secondary` and `fail` templates are unchanged.

### Changed — 10 examples tightened to one-clause grain

All 10 worked examples in `rules/change-decision-framework.md` rewritten to one-clause slot fills. Slot structure, marker format, and decision sequence are unchanged — only the prose inside each slot is compressed. 4.7 length-matches example grain aggressively, so tightening the examples is the lowest-risk behavioral lever: no doctrine added, no placeholder syntax changed, no hook logic touched. Worked examples affected: High pre-edit pass/flag, High post-edit pass/pass-with-secondary/fail, Low pre-edit pass/flag, Low post-edit pass/pass-with-secondary/fail.

### Mechanism preserved

- Marker regex `\[Rule 22(\s·\s[^\]]+)?\]` unchanged — legacy longer blocks from in-flight sessions still validate.
- Slot structure (Change/Intake/Criteria/Solutions/Rank/Validate/Execute for High; Change/Solutions/Execute for Low) unchanged.
- Ordering discipline, Rationalizations-that-do-not-apply doctrine, batch-manifest variants, Planning variant, Reference-Based Builds — all unchanged.
- Post-edit 5-question scope check unchanged; the compressed PASS template surfaces Q5's result inline rather than restating Q1-Q4.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the framework-doc changes.
- **Template diff on `/setup`:** `rules/change-decision-framework.md` has example-grain changes and two template-slot changes. Accept to adopt the tighter grain; decline to keep your customized local copy.
- **No config migration.** No hook changes. No behavior changes beyond what Claude emits in Rule 22 blocks.
- **Backward compatible:** older sessions mid-way through longer emissions continue to pass the marker regex unchanged.

## [2.11.0] - 2026-04-21

Minor release. Splits the ideas backlog from a single `intake/ideas-backlog.md` file to per-file storage under `intake/ideas/`. Driven by three observed pain points in the single-file design: (a) `ideas-backlog.md` crossed the Read tool's 25k-token context limit (~1200 lines in production), forcing offset/limit workarounds during audits; (b) "Pattern 21" drift between audit passes — entries logically cleared but physically still in place — was a recurring hygiene burden that only existed because of single-file semantics; (c) HTML-comment cleared-history markers accrued metadata in the content layer that already lived in `logs/knowledge-audit-log.md`. This release moves ideas to one markdown file per idea with YAML frontmatter, glob-driven reads, and delete-on-disposition semantics. Single-file format is retained for `insights-backlog.md`, `decisions-backlog.md`, and `extraction-backlog.md` — those backlogs stay under the threshold because they're cleared every 3-day audit cycle.

### New — `intake/ideas/` directory with per-file storage

Ideas now live as individual markdown files under `intake/ideas/` with the naming pattern `{YYYY-MM-DD}-{project}-{slug}.md`. Each file has YAML frontmatter (`date`, `project`, `type`, `title`) followed by the body (`**Proposal:**`, `**Motivation:**`, `**Source:**`). Filename collisions are handled by appending `-2`, `-3`, etc. The new `template/intake/ideas/README.md` documents the format, disposition flow (Accept/Reject/Defer/Reclassify with file-delete semantics), and migration path from pre-2.11 installations.

### Changed — `/extract` writes new files instead of appending

Step 4's "Ideas" section now writes one file per idea to `intake/ideas/` with frontmatter-first format. Step 1's timestamp-detection uses the date prefix of the most recent `*.md` file in the directory; Step 3's dedup loop globs `intake/ideas/*.md`. Step 5's summary line updated from "appended to ideas-backlog.md" to "written to intake/ideas/". If a legacy `ideas-backlog.md` is detected alongside the new directory, Step 5 surfaces a one-line migration pointer (but never attempts the migration from within `/extract` — that's `/setup`'s job).

### Changed — `/audit-knowledge` globs the directory

Step 2c2 "Review Ideas Directory" replaces "Review Ideas Backlog": globs `intake/ideas/*.md`, reads frontmatter for staleness computation (falls back to filename date prefix if frontmatter is missing), and surfaces Accept/Reject/Reclassify as file-delete operations. Git history becomes the audit trail — disposition notes still go to `knowledge-audit-log.md`, but the HTML-comment cleared-history pattern in the content file is retired. Legacy-file detection added: if `intake/ideas-backlog.md` exists alongside `intake/ideas/`, surface a "Legacy Ideas Backlog" finding in Step 6 with a migration pointer.

### Changed — `/context` reads frontmatter for project-scoped ideas

The "Pending Ideas surfacing" block in Step 5 now globs `intake/ideas/*.md` and filters by the frontmatter `project:` field rather than parsing entry headers from a single file. Staleness uses frontmatter `date:` with filename-prefix fallback. Multi-project entries (`project: aria,cross`) appear under each matching project query. Legacy-file detection surfaces a one-line informational note.

### New — `/setup` Step 3b: Legacy `ideas-backlog.md` Detection

Inserted between Step 3 (structure validation) and Step 4 (file diffing). Counts active entries in any legacy `ideas-backlog.md` and prompts the user with three options: migrate now (runs `bin/migrate-ideas-backlog.sh`), skip for this run (prompts again next time), or never migrate (writes a `.legacy-skipped` sentinel that suppresses future prompts). Empty legacy files are handled separately (offer to delete). This is the catch-net that ensures upgrading users see the migration path on their first post-upgrade `/setup` without an active prompt on every `/extract`.

### New — `bin/migrate-ideas-backlog.sh` one-shot migration script

Takes an optional knowledge-folder argument (falls back to config lookup). Parses `intake/ideas-backlog.md`, strips HTML comment blocks (cleared-history markers — information already lives in `logs/knowledge-audit-log.md`), splits on `^### YYYY-MM-DD — ` headers, emits one file per entry with generated frontmatter. Title extracted from header; `type` extracted from `**Type:**` body line (normalized to one of `feature|bug|design|refactor|workflow`, defaults to `feature` on missing/unparseable). Filename collisions resolved with `-2`, `-3`, ... up to 99. On success, renames the original to `ideas-backlog.md.pre-2.11-migration` (preserves rollback). Bash wrapper around embedded python3 heredoc, matching the `pre-edit-check.sh` pattern.

### Changed — template and doc updates

- `template/README.md` tree diagram: `ideas-backlog.md` line replaced with `ideas/` directory line.
- `template/OVERVIEW.md`: three references updated — the "Ideas Backlog" flow description (with migration pointer), the user-owned files paragraph, and the Batch Manifests future-consumer mention.
- `template/rules/user-rules.md`: "What Belongs Here vs ideas-backlog.md" section heading, feature-proposal bullet, and auto-routing paragraph all updated to reference `intake/ideas/`.
- `template/rules/change-decision-framework.md`: "If a rationalization seems novel" paragraph updated to file new escape-hatch requests in `intake/ideas/`.
- `template/intake/ideas-backlog.md` deleted from the shipped template; `template/intake/ideas/README.md` added.
- `bin/session-start-check.sh`: comment at line 82 updated to reference `intake/ideas/` terminology; shell logic unchanged (ideas were already excluded from the audit-eligible count).

### Retained — single-file format for other backlogs

`insights-backlog.md`, `decisions-backlog.md`, and `extraction-backlog.md` remain single-file. These are promotion-eligible and cleared on every 3-day audit cycle, so they stay under the size threshold where single-file semantics are fine. Only `ideas-backlog.md` had the retention profile (longest shelf life + largest entries + external-tracker destination rather than in-tree promotion) that crossed the threshold. If any of the other backlogs cross the threshold later, the same per-file split is available as a precedent.

### Fixed — `/help` commands table now lists `/codemap` and `/wrapup`

Both skills were referenced in the Model Recommendations table below but absent from the Commands table — an internal inconsistency within `/help`'s own output. Added `/codemap [mode]` grouped with the other mapping skills (`/distill`, `/stitch`) and `/wrapup` immediately before `/help` as the session-end meta. No behavior change; reference-doc sync only.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the skill and template changes.
- **Migration:** run `bash ${CLAUDE_PLUGIN_ROOT}/bin/migrate-ideas-backlog.sh` or re-run `/setup` (Step 3b will prompt). Migration preserves the original file as `ideas-backlog.md.pre-2.11-migration` — nothing is deleted.
- **Template diffs on `/setup`:** the plugin-managed template files (`README.md`, `OVERVIEW.md`, `rules/change-decision-framework.md`) have minor wording updates for the new terminology. Accept to take the v2.11 language; decline to keep customized local copies.
- **User-owned additions:** `intake/ideas/README.md` is classified user-owned (consistent with other directory README stubs) and will not diff on future `/setup` runs. Customize freely.
- **No action needed if your backlog was empty:** fresh installs create `intake/ideas/` directly; no legacy file to migrate.

## [2.10.6] - 2026-04-20

Patch release. Resolves a structural deadlock introduced in v2.10.5 under Claude Opus 4.7: the PreToolUse compliance scanner assumed text and tool_use blocks co-locate in a single assistant message, but 4.7's harness splits them into separate messages, causing every Edit/Write to deny. Diagnosed in a 2026-04-20 session via statistical tally of 51 assistant messages (zero text+tool_use co-location). v2.10.6 replaces same-message scan with turn-scoped walk-back bounded by the previous Edit/Write tool_use or user message — preserves per-edit marker requirement, aligns implementation with the framework doc's "same assistant turn" language. Also bundles four supporting fixes, a new rule (32), and the first test infrastructure for hook contracts.

### Changed â `plugin-claude-code/bin/pre-edit-check.sh` turn-scoped scanner

The embedded python scanner now walks backward through assistant messages, collecting text blocks until encountering either a previous Edit/Write tool_use (which caps the walk and clears collected blocks from before that cap) or a user message (turn boundary). The walk also handles a prior Edit/Write in the target tool_use's own message by resetting the collection mid-message. Marker regex unchanged; fail-open paths unchanged; deny REASON wording updated to clarify "text output (not thinking)" and "between the previous Edit/Write (if any) and this one" — closing the thinking-block loophole and making the per-edit scope explicit. Verified via three test fixtures (see `tests/`).

### Changed â `plugin-claude-code/bin/session-start-check.sh` accuracy + guardrails

The RULE 22 ORDERING text at line 192 previously claimed "the PreToolUse hook cannot enforce this; discipline is Claude-side." v2.10.5's `permissionDecision: deny` mechanism made that statement false, and under 4.7's literal reading the contradiction was an active compliance hazard. Rewritten to accurately describe the deny behavior, the per-edit scope ("between the previous Edit/Write and this one"), and four common rationalizations (added "too trivial" to the existing three). Also adds two new guardrails: **TASK BUDGET** (prompts Claude to surface strain symptoms — cut-short responses, deep sessions, compaction warnings — to the user for decision, since Claude Code's UI exposes actual usage to the user but not to the model; explicitly forbids self-defeating `/extract` during strain since the raw transcript persists via PreCompact anyway) and **MEMORY PATHWAY** (routes 4.7's enhanced file-system memory through ARIA's `/clip`, `/extract`, `/intake`, `/audit-knowledge` flow so the knowledge tree stays curated rather than fragmenting into ad-hoc notes).

### Changed â `plugin-claude-code/bin/post-edit-check.sh` prose trimmed

Non-planning-path `additionalContext` reduced from ~580 to ~515 characters. All five verification questions (scope held, nothing extra touched, no unnecessary rewrites, matches decision, secondary impact) preserved. All three output formats (PASS, PASS CONDITIONAL, FAIL) preserved with full markers. Only redundant prose removed. Saves ~65 chars per edit; scales favorably under 4.7's 1.0â1.35Ã tokenizer inflation.

### Changed â `plugin-claude-code/bin/task-context-check.sh` case normalization

Index tag extraction now pipes through `tr '[:upper:]' '[:lower:]'` so mixed-case tags in `index.md` (e.g., `### TypeScript`, `### React`) match against task words (which were already lowercased). Prior to this fix, any mixed-case tag was silently never-matched, suppressing context suggestions. Single-pipeline change; no other behavior affected.

### New â Rule 32: Halt on direct contradiction with a written directive

Added to `plugin-claude-code/template/rules/working-rules.md` (and mirrored in `knowledge/rules/working-rules.md` for this install). If a user request directly contradicts a written directive (rule in `rules/working-rules.md`, instruction in the currently-invoked skill's prompt, or recorded decision under `decisions/` or `projects/{tag}/decisions/`), halt before any tool call, name the contradiction verbatim, and ask for explicit override. Trigger is literal textual contradiction only â perceived expectations and inferred intent don't trigger (handled by Rule 7); scope-creep concerns remain governed by Rule 22. Motivated by 4.7's literal instruction-following: silent resolution of a contradiction masks a disagreement the user may not know exists.

### New â `tests/` directory with hook regression protection

First-ever test infrastructure for ARIA hook contracts. Three fixtures under `tests/fixtures/` capture the 4.7 split-message transcript shape in three scenarios (compliant, non-compliant, second-edit-without-fresh-marker). A repro script at `tests/repros/4-7-split-message.sh` invokes `pre-edit-check.sh` with each fixture and asserts the expected allow/deny outcome. A minimal runner at `tests/run.sh` executes all repros and reports pass/fail. The absence of this infrastructure was identified as the root cause of the v2.10.5 regression (mechanism-shift release without replay validation); future hook changes should add or update fixtures as appropriate.

### Retracted â v2.10.5 "self-recovers within one retry" claim

The v2.10.5 CHANGELOG stated that Claude "self-recovers within one retry" when the deny fires on a missing marker. That claim did not hold under 4.7 â the split-message architecture made every retry produce the same deny outcome, creating an unbounded deny loop. v2.10.6's turn-scoped scan makes the original self-recovery semantic work as intended. The claim is retracted in this release rather than silently corrected, so users reviewing the version history understand why the bug presented differently than the v2.10.5 notes suggested.

### Explicitly rejected â softening LOW-impact post-edit scope check

An external analysis suggested that 4.7's native self-verification makes the post-edit scope check redundant for LOW-impact edits and recommended dropping the required output on that path. This was considered and rejected. Native self-verification is internal reasoning; Rule 22's scope check is an external audit artifact â a grep-able, user-reviewable compliance record. Dropping the LOW-path output would eliminate the audit trail for ~80%+ of edits, defeating Rule 24's process-steps-define-done semantics. The token savings pursued in v2.10.6 come from trimming redundant prose (`post-edit-check.sh` above), not from dropping enforcement surface. Decision captured as ADR 039 at `knowledge/projects/aria/decisions/039-preserve-post-edit-scope-check.md`.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the hook changes. Sessions running the pre-v2.10.6 hook continue to deadlock under 4.7 until reinstalled.
- **Template diffs on `/setup`:** `plugin-claude-code/template/rules/working-rules.md` has a new Rule 32. `/setup` will present a diff prompt on next run. Accept to take Rule 32; decline to keep your customized local copy (and note that Rule 32 applies regardless of which version of the doc is loaded when the user opts to adopt it).
- **Regression protection:** run `sh tests/run.sh` at `Projects/aria/` to verify the hook scanner behavior on the 4.7 split-message shape. All three cases should pass.
- **Related references:** `knowledge/projects/aria/references/opus-4-7-aria-compatibility.md` documents the verified 4.7 behaviors this release is designed around and serves as the canonical ARIAâ4.7 design reference.
- **Deferred to v2.11.x:** `config.sh` sed batching (CPU, not 4.7-specific), usage-monitor hook (automatic token-usage observation via transcript sum), post-edit scope-check structural enforcement (Scenario E gap), Bash-write detection (Scenario C gap).

## [2.10.5] - 2026-04-20

Patch release. Replaces instructional Rule 22 enforcement with compliance-detecting mechanism. The v2.10.1 PreToolUse hook emitted "output retroactively AND prospectively" as an unconditional directive because the hook text claimed the platform gave hooks "no preventive authority." This claim was incorrect — PreToolUse hooks can return `permissionDecision: "deny"` to block the tool call. Under Claude 4.7's literal reading of ambiguous instructions, the "AND" clause was applied unconditionally, causing duplicate block emission per edit (one prospective above, one retroactive after, one prospective for next). Diagnosed in a live 4.7 session on 2026-04-20 after ~15 edits accrued ~3-6k wasted tokens. This release makes the retroactive path unreachable by construction: the PreToolUse hook now parses the current assistant turn's transcript, looks for a `[Rule 22]` marker, and denies with recovery instructions if absent. There is no code path in which compliance is satisfied after the edit lands, so the instruction ambiguity that drove duplication no longer exists.

### Changed — `plugin-claude-code/bin/pre-edit-check.sh` rewrite

Full rewrite. Preserves all v2.10.x path-classification logic (planning path, protected basenames, knowledge-folder conditional protection, critical paths, batch-manifest layers 3a/3b/3c/4/5). Adds compliance detection: parses `transcript_path` for the assistant message containing the current `tool_use_id`, scans text blocks preceding the tool_use for regex `\[Rule 22(\s·\s[^\]]+)?\]`. On match, exits silently (no `additionalContext` emission — compliant path is now zero-noise). On miss, emits `permissionDecision: "deny"` with a concise recovery message naming the expected format for the matched variant (planning / batch / full). Fail-open on every detector error path: unreadable transcript, malformed JSONL, missing `tool_use_id`, or python exception all fall through to allow rather than block.

### Changed — `plugin-claude-code/bin/post-edit-check.sh` scope marker

Scope-check output format updated to `[Rule 22 · Scope] PASS — ...`, `[Rule 22 · Scope] PASS CONDITIONAL — ...`, `[Rule 22 · Scope] FAIL — ...` (planning branch: `[Rule 22 · Scope] OK — planning doc.`). Marker is symmetric with pre-edit compliance blocks — same regex, same readability. Hook logic (path classification, protection detection) unchanged.

### Changed — `plugin-claude-code/template/rules/change-decision-framework.md` harmonization

Three classes of edit: (1) "Ordering (required)" opening paragraphs rewritten — the "hook has no preventive authority" claim is replaced with the accurate v2.10.5 mechanism description including marker format + `permissionDecision: "deny"` behavior; (2) "The hook can only be satisfied retroactively" rationalization subsection marked historical — retained per Rule 6 archive principle (the rationalization was real in v2.10.1–v2.10.4 sessions; naming it preserves institutional memory for future instruction-design patches); (3) marker convention note added to "Required Output Formats" section; all format templates and examples (Impact headers + Scope pass/fail lines) prefixed with `[Rule 22]` / `[Rule 22 · Scope]` so doc and hook teach the same format.

### New — marker convention

Every Rule 22 compliance block starts with `[Rule 22]` or `[Rule 22 · <variant>]` on its header line:

- `[Rule 22] Low Impact — ...` (full low-impact block)
- `[Rule 22] High Impact — ...` (full high-impact 7-step block)
- `[Rule 22 · Planning] <file>` (planning-path abbreviated)
- `[Rule 22 · Batch N/M] <file> per declared scope.` (batch-manifest compressed)
- `[Rule 22 · Scope] PASS | PASS CONDITIONAL | FAIL — ...` (post-edit scope check)

The marker serves two purposes: (1) unambiguously signals the block as a compliance artifact so the hook's detector has zero false positives / negatives in prose that mentions Rule 22; (2) gives readers a greppable anchor when auditing sessions for compliance history.

### Resolved from v2.10.4 deferrals

The v2.10.4 CHANGELOG deferred "Rule 22 hook text strengthening (v2.11.x candidate)" pending observed drift. Drift emerged in a 2026-04-20 session where 4.7 emitted the retroactive block unconditionally. The structural fix shipping here supersedes the instruction-wording strengthening originally sketched in `knowledge/intake/ideas-backlog.md` — rather than reinforcing language in the instruction, the mechanism is changed so the ambiguous instruction is no longer reachable. That ideas-backlog entry can be closed on next `/audit-knowledge`.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the hook rewrite. Sessions running the pre-v2.10.5 hook continue to behave as before (retroactive-AND-prospective instruction fires, duplicate blocks possible); only reinstalled sessions get the deny-on-miss mechanism.
- **No config migration:** no new fields in `~/.claude/aria-knowledge.local.md`. Existing configs continue to work unchanged.
- **First-edit teaching moment for Claude-in-flight:** immediately after reinstall, the first Edit/Write in any session will be denied if Claude hasn't yet emitted a `[Rule 22]` marker. The deny message includes the expected format template; Claude self-recovers within one retry. No user action required.
- **Template diff on `/setup`:** `plugin-claude-code/template/rules/change-decision-framework.md` changed; `/setup` will present a diff prompt on next run. Accept to take the v2.10.5 teaching content; decline to keep a customized local copy (and note that the marker convention applies regardless of which version of the doc is loaded — enforcement is hook-side, not doc-side).
- **Examples now use the marker:** if you had copied an older example block as a snippet or template, update the first line to include `[Rule 22]` before re-using it.

## [2.10.4] - 2026-04-18

Patch release. Applies Opus 4.7 best-practices guidance to ARIA's bulk-scan and bulk-output skills. Two distinct changes landed: (1) explicit parallel-Read directives in skills that read multiple files per step — 4.7's less-eager tool use would otherwise serialize these under the new defaults, doubling per-step I/O latency and token consumption; (2) top-level output policy guards + per-section zero-state rules in skills producing structured reports — 4.7's adaptive response-length behavior would otherwise silently collapse empty sections that are actually informational signals ("0 integrity issues detected" confirms the audit ran the check). All edits are skill-markdown directives; no behavior/schema/hook/API changes. No config migration required.

### Changed — Parallel-Read directives in bulk-scan skills (Change 1)

Added explicit "issue Read calls in a single parallel tool-use block" guidance to steps that read multiple files of the same kind for the same purpose. Under 4.6 defaults the model tended to parallelize implicitly; under 4.7's less-eager tool use, these serialize unless told. Scope kept strictly within-step to protect each skill's cross-step sequencing and user-approval checkpoints.

- `plugin-claude-code/skills/audit-knowledge/SKILL.md` — Step 3 (memory files), Step 4 (plan files), Step 5 (knowledge-folder dedup — feeds 5b/5c without re-reads), Step 5b ("do not re-read" reinforcement at the highest-risk re-read site)
- `plugin-claude-code/skills/audit-config/SKILL.md` — Step 3 (CLAUDE.md scan), Step 4 (knowledge-folder verify), Step 5 (PROGRESS.md scan)
- `plugin-claude-code/skills/intake/SKILL.md` — Step 2 (source-file reads, with explicit URL/WebFetch exception), Step 4 (dedup reads)

### Changed — Output policy guards in bulk-output skills (Change 2)

Added top-level "emit every section defined below" directives to skills producing structured comprehensive reports, plus per-section zero-state rules where empty-state behavior was previously ambiguous. Guards against 4.7 adaptively collapsing dashboards into prose or silently omitting zero-finding sections that carry informational signal. The pattern that emerged: **top-level output policy directive placed between the "Output in this format:" / "Present ... in this format:" opener and the fenced code-block template.**

- `plugin-claude-code/skills/audit-knowledge/SKILL.md` — Step 6 top-level output policy directive + per-section zero-state rules for four previously-ambiguous subsections (Pending Insights, Pending Decisions, Category C Items, Cross-Reference Findings). Four other subsections already had explicit conditional-on-feature-presence omission rules and were left unchanged.
- `plugin-claude-code/skills/audit-config/SKILL.md` — Step 6 top-level output policy directive only (existing `[list items or "None"]` template was already prescriptive per-section; gap was the whole-report-is-None collapse case).
- `plugin-claude-code/skills/stats/SKILL.md` — Step 6 top-level output policy directive only (existing dashboard template was already prescriptive; gap was potential misreading of Rules section's "Fast — just counting and date parsing, no heavy analysis" as "keep output short" rather than as an implementation-effort directive).

### Declined / Deferred — Intentional no-change decisions

Per-skill Change 1 and Change 2 assessments identified 5 skills where no edit was warranted, with rationale documented for durable scope-memory:

- **`/codemap` Change 1 (declined)** — Step 4's "process one feature at a time to manage context" is a deliberate sequentialization discipline. A parallel-Read directive would pressure the model against the explicit serialization instruction. Step 2 indexing uses Grep/Glob rather than Read, so parallelism has low payoff anyway.
- **`/stitch` Change 1 (deferred)** — the relevant read logic lives in the `group-loader` shared-block, which is duplicated verbatim in `/distill`. Editing one copy without the other triggers `/audit-knowledge` Step 5b3 shared-block drift detection. Modest gain (2–4 CODEMAPs per load) doesn't justify the coordinated-edit ceremony. Revisit when the shared block is touched for other reasons.
- **`/backlog` Change 2 (no-edit)** — content-proportional by design across all three modes (overview dashboard, detail view, interactive clear flow). No structured comprehensive output to guard.
- **`/context` Change 2 (no-edit)** — adaptive-by-design. Skill purpose is targeted retrieval with deliberate section omission; has 6 existing explicit omission rules throughout Step 5. Adding an emit-all directive would actively fight the skill's intent.
- **`/codemap` Change 2 (no-edit)** — already rigorously guarded. Every user-facing output has forcing confirmation prompts or explicit format templates; CODEMAP.md section content has explicit required elements per feature.

Full scope records with per-skill revisit triggers captured in `knowledge/intake/ideas-backlog.md` (2026-04-18 entries: "Change 1 propagation scope" and "Change 2 sweep").

### Deferred — Rule 22 hook text strengthening (v2.11.x candidate)

Considered and deferred: reinforcing language in `plugin-claude-code/bin/pre-edit-check.sh` rejecting "extensive prose reasoning = compliant" readings under 4.7's adaptive thinking. The framework mechanism is correct (adaptive thinking expands *quantity* of reasoning, not *shape* — Rule 22's slots force the shape). Current hook text fires cleanly in real sessions; no observed drift tied to 4.7. **Revisit after 2-3 weeks of 4.7 usage if drift emerges** where the block "technically fires" but named slots are under-addressed. Candidate phrasing captured in `knowledge/intake/ideas-backlog.md` (2026-04-18 entry: "Strengthen Rule 22 hook text against 4.7 adaptive-thinking drift").

### Shared-pattern opportunity — not acted on

The top-level output policy directive across `/audit-knowledge`, `/audit-config`, and `/stats` is near-identical. Could become a shared-block like `group-loader` in `/distill` and `/stitch`. **Deferred** — 3 instances is near the shared-block amortization threshold but not clearly over it. Revisit if a 4th skill needs the same directive.

### No migration required

All edits are additive skill-markdown directives. No schema change, no hook change, no config change, no API change. Existing sessions pick up new behavior on next skill invocation. Reinstall `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` per usual; no config migration needed.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the skill changes.
- **No template diff on `/setup`:** the edits are skill-internal; `plugin-claude-code/template/` is unchanged.
- **No Rule 22 hook change:** the v2.10.3 hook text is unchanged. The v2.11.x candidate strengthening (captured in `ideas-backlog.md`) is future work.
- **Empty-state output verification:** next run of `/audit-knowledge`, `/audit-config`, or `/stats` on a clean baseline should emit zero-state lines/counts explicitly — if you see collapsed or prose-style summaries instead, the skill didn't reload.

## [2.10.3] - 2026-04-18

Patch release. Replaces the day-only `/audit-knowledge` trigger with activity-driven OR-logic and tiered messaging. The prior 3-day cadence mis-fired in both directions — prompting on empty backlogs during low-activity weeks, and staying silent through high-activity days where backlogs had already crossed the reviewable ceiling. This release makes backlog-entry count the primary trigger and keeps elapsed-days as a safety net for silent-drift periods. No breaking changes: existing configs keep working; the new field takes its default (20) when absent.

### Added — `audit_trigger_threshold` config field (default 20)

New YAML frontmatter key in `~/.claude/aria-knowledge.local.md` counted via `^### ` headers across `intake/insights-backlog.md`, `intake/decisions-backlog.md`, and `intake/extraction-backlog.md`. `ideas-backlog.md` is deliberately excluded — ideas route out rather than promoting, so counting them would conflate staging with action. Parsing and numeric-validation plumbed through `plugin-claude-code/bin/config.sh` alongside existing cadence fields.

### Changed — Tiered SessionStart prompt messaging

`plugin-claude-code/bin/session-start-check.sh` now composes one of three prompt tiers based on backlog size (tier boundaries derived from `audit_trigger_threshold` via fixed `+15` / `+30` offsets):

- `count ≥ threshold` → *"Knowledge audit suggested — N entries ready for review."*
- `count ≥ threshold + 15` → *"Knowledge audit recommended — N entries, near one-pass ceiling."*
- `count ≥ threshold + 30` → *"Knowledge audit overdue — N entries, plan for multi-pass."*

If both entry-count and elapsed-days triggers fire, the entry-tier message wins and the day-count is appended as context. Every prompt embeds a `(trigger: count=N threshold=T days=D)` hint — both for user clarity and for greppable post-ship tuning. The day-only prompt (fired when count tier doesn't trigger but cadence has) is reformatted to *"Knowledge audit due — N days since last audit. (trigger: days=N threshold=C; backlog=M) Run /audit-knowledge?"* — same firing conditions as before, with the trigger hint appended so the audit log can capture it.

### Changed — `audit_cadence_knowledge` default 3 → 7 days

Bumped throughout: `plugin-claude-code/bin/config.sh` default + fallback, `plugin-claude-code/skills/setup/SKILL.md` prompt prose + Step 7 config template, `plugin/QUICKSTART.md` documented default. Rationale: once activity-count is the primary signal, the day-based check becomes the safety net for "did anything drift silently while I wasn't writing" — weekly cadence matches that intent better than the original 3 days, which was calibrated for day-only triggering.

### Added — `Trigger:` subfield in audit-log entries

`plugin-claude-code/skills/audit-knowledge/SKILL.md` Step 8 audit-log template (both promoted-items and empty-audit variants) now records `Trigger: count=N threshold=T days=D cadence=C — (which fired)`. This makes trigger distribution greppable across audits, enabling data-driven tuning once 3-4 entries accumulate. Applied to both promoted and yield-zero audits — the yield-zero cases are the most important tuning signal since they indicate the threshold fired but nothing promoted.

### Skill updates

`plugin-claude-code/skills/audit-knowledge/SKILL.md` Step 0 reads `audit_trigger_threshold`; Step 1 computes current backlog count and enumerates tier-message semantics so user-invoked runs see the same state as hook-triggered prompts.

### No migration required

Existing configs lacking `audit_trigger_threshold` automatically use the default (20). Existing configs with `audit_cadence_knowledge: 3` continue working unchanged; only the default for fresh installs changes. No schema breakage, no hook-timing change, no API change.

## [2.10.2] - 2026-04-18

Patch release. Strengthens v2.10.1's Rule 22 ordering discipline after a real-session failure mode was observed: an in-flight session continued across a plugin reinstall produced ~dozens of retroactive Rule 22 assessments, then (when challenged) proposed to "skip the block for this review" as an escape hatch the framework does not offer. Root causes: (1) the v2.10.1 hook message put the retroactive recovery clause first and the prospective-next-edit requirement second — the second half got skimmed; (2) SessionStart injection only fires at session start, so continued sessions across plugin updates don't receive the preventive layer; (3) no doctrine named and rejected the specific rationalizations Claude was inventing. v2.10.2 addresses (1) and (3) directly, and partially mitigates (2) via the stronger hook text. No config migration or API changes.

### Changed — Hook message leads with prospective requirement, names escape hatches inline

`plugin-claude-code/bin/pre-edit-check.sh` MAIN_MSG reworded. The message now opens with:

> "REQUIRED: your NEXT Edit/Write must be preceded (in the same assistant turn, ABOVE the tool call) by the Low/High Impact block."

— making the prospective requirement load-bearing text a skim-reader cannot miss. The retroactive-recovery clause is secondary. The message then explicitly names four rationalizations observed in the wild ("conversation already covered it," "docs-only / in-review / discuss-then-edit cadence," "only way to satisfy the hook is retroactively," "skipping for this session is a plugin-config option") and rejects each inline. HIGH/LOW format specs unchanged.

### Added — "Rationalizations that do not apply" section in doctrine

New `## Rationalizations that do not apply` section in `plugin-claude-code/template/rules/change-decision-framework.md`, placed between the v2.10.1 `## Ordering (required)` section and `## Required Output Formats`. Names and rejects the four escape hatches with framework-semantic reasoning (not just "don't do it"):

- **"Conversation already established the reasoning"** — conversation surfaces decisions; the block surfaces ranked alternatives and scope checks. Skipping drops the alternative-ranking.
- **"Hook can only be satisfied retroactively"** — reading only half the AND clause; retroactive is recovery, not method.
- **"Docs-only / in-review / routine edit"** — the framework is about decision discipline, not edit content. Tier is determined by stakes; exemption is not an option.
- **"Skipping is a plugin-config the user can make"** — no such config exists. The correct response to ceremony cost is shorter LOW blocks or a batch manifest, not skipping.

Plus a catch-all subsection for novel rationalizations: file as an `ideas-backlog.md` entry, not adopted mid-session.

### Changed — SessionStart reminder references the new doctrine section

`plugin-claude-code/bin/session-start-check.sh` RULE 22 ORDERING reminder updated to cite both `"Ordering (required)"` and `"Rationalizations that do not apply"` sections, and to name three of the specific invalid arguments inline as quick-reference against skim-reading. Length increase ~50 tokens per session-start; acceptable cost for closing the doctrine cross-reference.

### Observed failure this patch addresses

For maintainers auditing whether the fix matches the observed failure:

- **Session:** pre-v2.10.1 session continued across plugin reinstall (new hook message loaded; SessionStart context stale)
- **Failure pattern:** ~30 Rule 22 assessments output retroactively across a single-file review pass; when challenged, Claude cited the hook text as justification ("the only way to satisfy it is retroactively")
- **Proposed escape:** "Skip the blocks for the rest of this review — we've already established the reasoning conversationally"
- **Why v2.10.2 catches it:** the new hook message leads with the prospective requirement (so skim-reading catches it); the doctrine explicitly rejects the "conversation already covered it" argument; the SessionStart text names invalid-argument examples a model might reach for

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/`. No config migration needed.
- **Template diff on next `/setup`:** `rules/change-decision-framework.md` gains the new `## Rationalizations that do not apply` section. Accept to receive the canonical doctrine.
- **Continued sessions across this reinstall:** SessionStart injection still only fires on fresh sessions. Sessions already in progress at reinstall time will get the new MAIN_MSG per-edit but not the new SessionStart text until restart. The v2.10.2 hook message change is strong enough to compensate; if you see the failure mode recur, restart the session to pick up the new SessionStart injection.
- **Longer-term fix for the continued-session gap:** filed as a v2.11.x candidate — the Layer 4 verification hook in `ideas-backlog.md` would detect the failure mode mechanically rather than relying on doctrinal text.

## [2.10.1] - 2026-04-18

Patch release. Fixes a coordination gap between v2.10.0's batch-manifest mechanism and the knowledge-folder protection layer that prevented `/audit-knowledge` — v2.10.0's sole motivating use case — from receiving the compression v2.10.0 was designed to deliver. Also clarifies Rule 22 ordering discipline across three enforcement layers (doctrine, SessionStart injection, hook message) to close a long-standing gap where the pre-edit assessment was being output retroactively (after the tool call) instead of prospectively (above it). Behavior is unchanged for non-manifest sessions, for declared-high ops, for structural-signal paths, and for protected basenames (`CLAUDE.md`, `working-rules.md`, `plugin.json`, etc.). No config migration or user-visible API changes.

### Fixed — Knowledge-folder protection now respects batch-manifest declarations (ADR 035)

In v2.10.0, `pre-edit-check.sh` marked every file inside `KT_KNOWLEDGE_FOLDER` as `IS_PROTECTED=true` unconditionally, which pre-empted the layer 3a compression check. Since `/audit-knowledge`'s entire workload lives inside the knowledge folder, ADR 021's compression never activated for the workload that motivated it.

v2.10.1 reorders the hook so `SIGNALS` and `BATCH_MATCH` are computed before knowledge-folder protection, then gates knowledge-folder protection on batch state:

- **No manifest (or file not matched):** knowledge folder stays protected — full Rule 22 (unchanged from v2.10.0).
- **Declared-low + matched + no structural signals:** knowledge folder protection is lifted for this file only; layer 3a compression activates.
- **Declared-high + matched:** full Rule 22 with `BATCH DECLARED-HIGH` prefix (unchanged).
- **Declared-low + matched + signals fire:** full Rule 22 with `BATCH SIGNAL OVERRIDE` prefix (unchanged).
- **Protected basename (`CLAUDE.md`, `working-rules.md`, `plugin.json`, etc.):** full Rule 22 regardless of manifest — protected basenames are stricter than knowledge-folder blanket.
- **User `critical_paths` protection:** unchanged by this patch — critical paths represent explicit user intent to always scrutinize and are NOT overridden by batch manifest.

### Verified — Six-scenario hook regression matrix

This fix was validated against six enforcement scenarios before shipping:

1. **No manifest** → full Rule 22 ✓
2. **Declared-low + matched + no signals** → compressed directive ✓
3. **Declared-low + matched + signals fire** → `BATCH SIGNAL OVERRIDE` + full Rule 22 ✓
4. **Declared-high + matched** → `BATCH DECLARED-HIGH` + full Rule 22 ✓
5. **Protected basename (`plugin.json`) + declared-low matched** → full Rule 22 (protection wins) ✓
6. **Manifest active, file NOT matched** → full Rule 22 (scope-drift detection) ✓

Documented in ADR 035 as candidate test cases for future hook refactors.

### Changed — `pre-edit-check.sh` decision hierarchy comment updated

Header comment block in `plugin-claude-code/bin/pre-edit-check.sh` now documents the v2.10.1 conditional-protection semantics inline, with explicit `v2.10.1:` markers at the two logic sites for future maintainability.

### Clarified — Rule 22 ordering discipline (three-layer fix)

Prior versions had a latent gap: the PreToolUse hook fires alongside the tool result (not before the tool runs), so Claude was reading the CHANGE DECISION CHECK reminder AFTER each Edit/Write landed, then outputting the Low/High Impact block retroactively. The hook's wording ("Output this REQUIRED format before proceeding... STOP and do so before proceeding.") implied preventive behavior that Claude Code's tool lifecycle can't actually provide. v2.10.1 adds three coordinated layers so the ordering discipline shifts from hook-driven correction to Claude-side proactive output.

**Layer 1 — Doctrine:** New `## Ordering (required)` section in `plugin-claude-code/template/rules/change-decision-framework.md` states the rule explicitly, with WRONG/RIGHT examples and the reasoning that the hook is a safety net, not a primary mechanism. Plugin-managed file — users will see this as a `/setup` diff on next update.

**Layer 2 — SessionStart injection:** `plugin-claude-code/bin/session-start-check.sh` now emits a `RULE 22 ORDERING` reminder on every non-first-run session start, so the ordering rule is in Claude's foreground context before the first edit of the session, not after. This is the preventive layer — the only one that fires before any Edit/Write.

**Layer 3 — Hook message rewrite:** `plugin-claude-code/bin/pre-edit-check.sh` MAIN_MSG reworded. Removed the deceptive "before proceeding" / "STOP and do so before proceeding" phrasing (which implied preventive timing the hook doesn't have). Replaced with honest framing: the hook fires with the tool result, so if Claude is reading the message the edit has already landed. Dual-action recovery: output retroactively now AND put the next edit's block above the tool call. HIGH/LOW format specs preserved verbatim — only the framing around them changed. Batch-mode (BATCH_MSG) variant unchanged since its timing framing is already honest.

**Why three layers, not one:** the PreToolUse hook cannot technically prevent the ordering violation (it fires too late). Rewriting its wording alone would have improved honesty but not the failure rate. The SessionStart injection is the only preventive layer — without it, the doctrine and hook rewrite stay corrective. All three are complementary: doctrine is canonical reference, SessionStart puts the rule in foreground before first edit, hook rewrite is the per-edit safety net when discipline slips.

**Post-edit hook unchanged:** the POST-EDIT SCOPE CHECK fires after the edit by design (that's when scope verification makes sense), so its timing framing ("Output this REQUIRED format after edit") was already honest. No change needed.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` as per `CLAUDE.md`. No config migration needed.
- **Template diff on next `/setup`:** the new Ordering section in `rules/change-decision-framework.md` is plugin-managed, so `/setup` will surface it as a diff prompt. Accept to receive the canonical ordering rule; if you've customized the file locally, the diff will let you merge selectively.
- **No CHANGELOG rollback needed for v2.10.0** — the v2.10.0 entry correctly describes the designed mechanism; v2.10.1 is the implementation correction that makes v2.10.0's design operational for its motivating case.

## [2.10.0] - 2026-04-17

Ceremony-reduction release. Implements ADR 021 Plan A's bundled Upgrades 1+2 — the batch-manifest mechanism that compresses Rule 22 ceremony for declared-mechanical bulk operations while preserving full CHANGE DECISION CHECK for high-impact edits. Requires `jq` on PATH (graceful degradation to full Rule 22 if jq missing). No breaking changes to existing skills; hook behavior is unchanged for edits with no active manifest.

### Added — Batch-manifest mechanism (core infrastructure)

Skills and manual plan-execution can declare an active batch by writing `~/.claude/active-batch.json`. The `pre-edit-check.sh` hook detects the manifest and, for matching low-impact ops with no structural signals and no protected-path conflict, emits a compressed directive ("BATCH OPERATION (N/M) — declared scope: ...") instead of the full CHANGE DECISION CHECK template. Out-of-scope edits, declared-high ops, signal-triggering files, and protected paths all continue to get full format.

**Manifest schema** (validated by `kt_batch_begin`):

```json
{
  "batch_id": "unique-identifier",
  "skill_name": "invoking-skill or 'manual-plan-execution'",
  "plan_summary": "one-line description",
  "started_at": "ISO-8601 UTC timestamp",
  "expected_operations": [
    {
      "file_path_pattern": "glob pattern",
      "operation_type": "create|update|delete",
      "impact": "high|low",
      "justification": "non-empty string"
    }
  ]
}
```

**New helpers in `plugin-claude-code/bin/config.sh`:**
- `kt_batch_begin SKILL_NAME PLAN_SUMMARY OPS_JSON` — validates the ops array (each op must have non-empty `file_path_pattern`, `impact` in {high, low}, and non-empty `justification`) and writes the manifest
- `kt_batch_end` — removes the active manifest (safe no-op if none exists)
- `kt_batch_find_match FILE_PATH` — used by the hook to check if an edit matches an expected op
- `kt_batch_clear_stale [MAX_AGE_SECONDS]` — removes stale manifests (default 30 minutes) to recover from crashed sessions

### Added — Safety floor (multi-layer defense)

The batch mechanism compresses ceremony only when every safety layer clears. Any layer firing degrades to full Rule 22:

1. **Protected paths always win** — `CLAUDE.md`, `working-rules.md`, `change-decision-framework.md`, `enforcement-mechanisms.md`, `settings.local.json`, `plugin.json`, the knowledge folder itself, and user `critical_paths` always get full assessment regardless of manifest declaration.
2. **Structural signal override** — if `kt_detect_signals` detects auth, migration, model, routing, or external-service signals on a declared-low op, the hook escalates to full Rule 22 with a `BATCH SIGNAL OVERRIDE` prefix. Signals are ground truth from the filesystem; cannot be self-declared away. This promotes `kt_detect_signals` from advisory-only (v2.9.0) to having override authority when a batch manifest is active.
3. **Declared-high fires full format** — `impact: high` in the manifest always gets the full CHANGE DECISION CHECK with a `BATCH DECLARED-HIGH` prefix.
4. **Scope-drift detection** — edits to files not matched by any manifest op get full Rule 22. The manifest is both compression signal and declared-scope boundary; the hook catches wandering automatically.
5. **Post-edit scope check unchanged** — `post-edit-check.sh` ceremony is not compressed; aggregate drift detection (many individually-small edits collectively constituting an architectural change) surfaces there.
6. **Justification validation** — manifest entries with empty or missing `justification` fall back to full Rule 22 for that op (enforces articulated intent).
7. **Stale-manifest auto-clear** — `session-start-check.sh` removes manifests older than 30 minutes so crashed sessions don't silently suppress Rule 22 on later unrelated edits.

### Added — Three-tier ceremony calibration

With v2.10.0 the framework has three ceremony tiers, each triggered by a file-based signal:

| Tier | Trigger | Output |
|------|---------|--------|
| Planning | Edit to `*/docs/plans/*` or `*/docs/specs/*` | Abbreviated ("Planning edit — [filename]") |
| Batch declared-low | Edit matches manifest op + impact:low + no signals + not protected | Compressed directive (single-line acknowledgment) |
| Default | Everything else (no batch; declared-high; signal override; scope drift; protected) | Full CHANGE DECISION CHECK |

All three tiers use file-based signals — post-compaction safe per ADR 006 because the hook re-derives the tier from filesystem state on every fire.

### Added — `/audit-knowledge` batch integration

`/audit-knowledge` gains Step 7a (after user-approved promotion plan, before executing promotions) that constructs and writes a batch manifest classifying each approved op as high/low impact. Step 8b (after audit log is updated) clears the manifest. The audit's 15-30 edits per pass was the primary cost center that motivated ADR 021; this integration delivers the compression value for exactly that case.

**Classification guidance documented in Step 7a:** stub-and-reference, backlog clears, log appends, and new `approaches/`/`guides/`/`references/` files are typically declared `low`; new `decisions/` ADRs, new/modified `rules/` entries, and cross-project consolidations that create new authoritative files are typically declared `high`. "When in doubt, declare high — full Rule 22 is always the safe choice."

### Added — Manual plan-execution use case (general-purpose mechanism)

The batch manifest is **skill-agnostic by design**. When Claude is executing a user-supplied multi-file plan (e.g., implementing `docs/plans/feature-x.md`), Claude can write the manifest itself using the same helpers — no skill wrapper required. Documented in the new OVERVIEW.md "Batch Manifests for Ceremony Reduction" section with example. This generalization makes the mechanism useful for any declared-scope multi-edit operation, not just built-in skills.

### Deferred to follow-up releases

- **`/wrapup` manifest integration** (v2.10.1 candidate) — typical wrapup edit volume (2-4 files) is below the ceremony-reduction value threshold; filed for future evaluation.
- **`/extract` manifest integration** (v2.10.1 candidate) — /extract's dynamic-scope capture pattern doesn't pre-declare cleanly; filed for future design work on loose-pattern manifests.
- **post-edit-check.sh manifest symmetry** (v2.10.x) — ideas-backlog entry for symmetric post-edit compression on declared-low ops.
- **Bash-write-matcher extension** (v2.10.x) — widen hook matcher to catch `cat >>`, `sed -i`, shell redirect patterns that currently bypass Rule 22 (filed as separate ideas-backlog entry from v2.9.0).

### Changed

- `plugin-claude-code/.claude-plugin/plugin.json` — version bumped to 2.10.0.
- `plugin-claude-code/bin/pre-edit-check.sh` — rewritten with safety-floor decision hierarchy (planning → protected → batch compression → full with contextual prefixes). Backward-compatible for all no-batch edits.
- `plugin-claude-code/bin/session-start-check.sh` — added `kt_batch_clear_stale 1800` early in the hook.
- `plugin-claude-code/template/OVERVIEW.md` — new "Batch Manifests for Ceremony Reduction" section (between "Plugin-Managed vs User-Owned Files" and "Design Principles").
- `plugin-claude-code/skills/audit-knowledge/SKILL.md` — added Step 7a (declare manifest) and Step 8b (clear manifest).

### Dependencies

- **Requires `jq` on PATH.** Install via `brew install jq` (macOS) or your package manager. Graceful degradation: if jq is missing, the hook falls back to full Rule 22 format for all edits — batch compression is lost but correctness is preserved.

### Related ADRs

- `knowledge/projects/aria/decisions/021-rule22-ceremony-plan-a.md` — updated to "Implemented in v2.10.0" with implementation notes (split-calibration field, signal-override promotion, justification validation).
- `knowledge/projects/aria/decisions/006-full-rule22-format-every-edit.md` — unchanged. Batch manifest is a narrow file-based exception structurally equivalent to the planning-path exception; ADR 006's core principle (no session-history-based self-judgment; file-based signals only) remains load-bearing.


---

For versions prior to v2.10.0, see [CHANGELOG.archive.md](CHANGELOG.archive.md).
