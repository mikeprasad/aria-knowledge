# Active Surfacing — Single-Source Ranking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** gate 2 PROCEED-WITH-CHANGES, G2-1..G2-6 applied. **HOLD before execution** (owner: "SPPP then hold for E", 2026-11-08).

**Goal:** One tested implementation decides which knowledge files ARIA surfaces, ranked project-first, delivered deterministically on every prompt in Claude Code.

**Architecture:** `kt_index_match` (shell lib) gains the D2 ranking, D3 project vocabulary and D4 aliases, answering from an mtime-keyed parse cache. A new `UserPromptSubmit` hook and a CLI wrapper both call it; the model-executed prose algorithm is deleted on Claude Code and replaced by one canonical ranking paragraph (guarded verbatim) where no code can run.

**Tech Stack:** POSIX `sh` + `awk` (hooks, lib), `jq` (prompt extraction only; absent ⇒ silent exit), bash test harness (`tests/run.sh`, `plugin-claude-code/tests/run.sh`).

**Spec:** `docs/superpowers/specs/2026-11-08-active-surfacing-single-source-ranking-spec.md` (gate 1 PROCEED-WITH-CHANGES, C1–C7 applied).

## Global Constraints

- Public repo: fixtures and docs use placeholders only (`proj-a`, `proj-b`, `proj-c`, `site-1`). Run `plugin-claude-code/scripts/check-public-hygiene.sh` AFTER each commit (it scans tracked files and commit messages).
- Firing rule: ≥2 matched tags, OR ≥1 matched project tag (`KT_PROJECTS_LIST`).
- Order: (1) carries a matched project tag → (2) more matched tags → (3) more task-word overlap → (4) authored (path not under `logs/`) before logs → (5) rarest matched tag carried (fewest Tag Index files) → (6) index order. Cap 5.
- Task words: lowercase, split on non-alphanumerics, drop tokens of length ≤2 and the stopword list `the and for from into with this that are was were have has add fix new update about make use`.
- Hook latency: p95 ≤ 150 ms warm on a ~45k-line index; exit 0 always; never block the prompt.
- Hook injects PATHS only (host replaces any `additionalContext` over 10,000 chars with a file path + preview).
- Host premises stamped: Claude Code 2.1.319, docs read 2026-11-08.
- Libs run under `sh`/`bash` only — under zsh the word-splitting differs and the lib reads 0 matches.
- The session ledger stays `/tmp/aria-active-<session_id>` (shared with `task-context-check.sh:73` and `bash-cd-check.sh`); only the parse cache honours `TMPDIR`. Tests isolate `TMPDIR` and `HOME`, use a unique fake `session_id`, and delete its ledger on exit (G2-5).

## Review Focus

1. A prompt that is mostly pasted text (a log, a transcript) — expect matching on the user's own words only. → Task 4 test `pasted_block_ignored`.
2. A prompt mentioning a short project tag (`proj-c`) and nothing else — expect it to fire, but only once per file per session. → Task 4 test `single_project_tag_fires_once`.
3. `index.md` rebuilt mid-session — expect the next prompt to rank from the new index, not the cache. → Task 2 test `cache_invalidates_on_index_change`.
4. Missing `jq`, missing config, or missing index — expect silence and exit 0, never an error the user sees. → Task 4 tests `no_jq_silent`, `no_index_silent`.
5. Known Tags aliases written with spaces instead of commas — expect both forms to resolve. → Task 1 test `alias_space_separated`.

---

### Task 1: Ranking, project vocabulary and aliases in `kt_index_match`

**Files:**
- Modify: `plugin-claude-code/scripts/lib-index-match.sh` (`kt_index_match`, lines 39–122)
- Create: `tests/repros/fixtures/surfacing/index.md`, `tests/repros/fixtures/surfacing/config.md`
- Test: `tests/repros/surfacing-rank.sh`

**Interfaces:**
- Consumes: env `KT_KNOWLEDGE_FOLDER` (required), `KT_PROJECTS_LIST` (optional, `tag:path,tag:path`).
- Produces (contract UNCHANGED for existing callers): `kt_index_match "<text>"` sets `KT_MATCH_TAGS` (space-separated), `KT_MATCH_COUNT` (0–5), `KT_MATCH_FILES_TMP` (file of `path — description` lines, ranked). Also exports `kt_index_tokens "<text>"` → task words on stdout, one per line (used by Task 4).

- [ ] **Step 1: Build the synthetic fixture.** `index.md` with `## Known Tags` (including `proj-b [aliases: site-1, site-2]` and `three-js [aliases: threejs three.js]`), and a `## Tag Index` where: `proj-b` lists 2 authored `projects/proj-b/…` files + 2 `logs/` files (one whose description contains "payments"); `payments` lists 6 files from `proj-c`; `proj-c` lists 4 files; one file appears under both `proj-b` and `payments`. `config.md` sets `projects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c`.

- [ ] **Step 2: Write the failing tests** (each asserts exact ranked paths from the fixture):
  - `project_first_over_longer_tag` — "add the roof job to the proj-b payments tab" → first 2 results carry `proj-b`.
  - `two_matched_tags_outrank_one` — the file under both `proj-b` and `payments` is rank 1.
  - `task_words_break_tie` — among `proj-b`-only logs, the one whose description contains "payments" ranks before the other.
  - `authored_before_logs` — equal on 1–3 ⇒ `projects/proj-b/…` before `logs/…`.
  - `lone_project_tag_fires` — "look at proj-b" → `KT_MATCH_COUNT` > 0.
  - `lone_generic_tag_silent` — "look at payments" → `KT_MATCH_COUNT` = 0 (negative arm).
  - `project_without_tag_section` — `proj-a` has no `### proj-a` but has `projects/proj-a/x.md` lines under another tag → "work on proj-a" surfaces it.
  - `alias_comma_and_space` — "site-1 skylights" resolves `proj-b`; "threejs scene" resolves `three-js`.
  - `cd_query_lone_project_fires` — the query `bash-cd-check.sh:75-76` builds from a path ending in `proj-b` now fires (intended behaviour change; its per-project cooldown and the ledger bound it) (G2-6).
  - `cap_is_five` and `existing_callers_contract` — `KT_MATCH_FILES_TMP` lines keep the `path — description` shape.

- [ ] **Step 3: Run to see them fail** — `sh tests/repros/surfacing-rank.sh`. Expected: FAIL on every arm except `cap_is_five`/`existing_callers_contract` (current lib: length-desc order, no project vocabulary, no aliases). Record which arms passed on the OLD lib; any arm other than those two that passes is a dead test — fix it before Step 4.

- [ ] **Step 4: Implement** the D2 order in one `awk` program over the parsed Tag Index (Task 2 supplies the parse; until then parse inline). `kt_index_tokens` implements the Global Constraints task-word rule.

- [ ] **Step 5: Run** `sh tests/repros/surfacing-rank.sh` and `sh tests/run.sh`. Expected: all green, bare exit 0.

- [ ] **Step 6: Commit** — `git add` the three files by path; `git commit -m "feat(surfacing): project-first ranking, project vocabulary, aliases in kt_index_match"`; then run the hygiene gate.

### Task 2: Parsed-index cache + latency budget

**Files:**
- Modify: `plugin-claude-code/scripts/lib-index-match.sh`
- Test: `tests/repros/surfacing-rank.sh` (add arms)

**Interfaces:**
- Produces: `kt_index_cache_path` → path of a TSV `tag<TAB>path<TAB>description` (+ `@alias<TAB>alias<TAB>canonical` rows) under `${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}/aria-surface-<cksum of index path>.tsv`, rebuilt when the `cksum` of `index.md` differs from the value stored in its first line — content-keyed, because `stat` mtime flags differ between BSD and GNU (G2-4; measured ~10 ms for 44,480 lines).

- [ ] **Step 1: Failing tests** — `cache_built_on_first_call` (file exists after one match); `cache_invalidates_on_index_change` (append a tag line to the fixture, next match sees it — no sleep needed, the key is content); `cache_survives_unwritable_dir` (cache dir read-only ⇒ match still correct, exit 0).
- [ ] **Step 2: Run** — expected FAIL (no cache yet).
- [ ] **Step 3: Implement** cache build (one `awk` pass) + answer-from-cache in `kt_index_match`. Write to a temp file and `mv`, so a concurrent reader never sees a half-written cache.
- [ ] **Step 4: Run** the suite — green.
- [ ] **Step 5: Latency check (local, not committed).** Under `bash`, against the maintainer's real index, run 20 warm matches on mixed phrasings; record p95. Expected ≤ 150 ms. Record the figure in the PR/commit body without private phrasing.
- [ ] **Step 6: Commit** `feat(surfacing): mtime-keyed parse cache for kt_index_match`; hygiene gate.

### Task 3: `scripts/aria-surface.sh` CLI

**Files:**
- Create: `plugin-claude-code/scripts/aria-surface.sh`
- Test: `tests/repros/surfacing-rank.sh` (add arms)

**Interfaces:**
- Consumes: `config.sh` (for `KT_KNOWLEDGE_FOLDER`, `KT_PROJECTS_LIST`), Task 1/2 lib.
- Produces: `sh aria-surface.sh "<text>"` → line 1 `tags: <space-separated>`; then one ranked path per line; nothing when it does not fire. Exit 0 always.

- [ ] **Step 1: Failing tests** — `cli_prints_tags_then_paths`, `cli_silent_when_not_fired`, `cli_exit0_without_config` (HOME pointed at an empty dir).
- [ ] **Step 2: Run** — FAIL (file absent).
- [ ] **Step 3: Implement** the wrapper (source `config.sh`, call `kt_index_match`, print, `kt_match_cleanup`).
- [ ] **Step 4: Run** — green.
- [ ] **Step 5: Commit** `feat(surfacing): aria-surface.sh CLI`; hygiene gate.

### Task 4: `UserPromptSubmit` surfacing hook

**Files:**
- Create: `plugin-claude-code/scripts/prompt-context-check.sh`
- Modify: `plugin-claude-code/.claude-plugin/plugin.json` (`UserPromptSubmit` hooks array — add a second entry beside `usage-threshold-inject.sh`, `"timeout": 5`)
- Test: `plugin-claude-code/tests/test-prompt-context-check.sh`

**Interfaces:**
- Consumes: stdin JSON `{session_id, prompt, …}`; `kt_index_tokens`, `kt_index_match`, `kt_match_filter_ledger "$LEDGER"`, `kt_match_record_ledger "$LEDGER"` with `LEDGER=/tmp/aria-active-<session_id>` (same ledger as `task-context-check.sh:73`); `KT_ACTIVE_SURFACING`.
- Produces: on fire, stdout `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"ARIA ACTIVE — <n> knowledge file(s) for this task (tags: …). Read them before answering and say in one line which you used and why:\n- <path>\n…"}}`; otherwise no output. Exit 0 always.

- [ ] **Step 1: Failing tests** (fixture from Task 1; `HOME` + `TMPDIR` isolated; stdin closed explicitly):
  - `fires_with_paths_only` — JSON parses with `jq`; `additionalContext` lists ranked paths and contains no file bodies; length < 10,000.
  - `pasted_block_ignored` — prompt = "hi" + a `<pasted_content id="x">` block full of tag words + closing line ⇒ no output.
  - `single_project_tag_fires_once` — same prompt twice in one session ⇒ output once (ledger), second call silent.
  - `active_surfacing_false_silent` — `active_surfacing: false` in config ⇒ no output.
  - `no_jq_silent`, `no_index_silent`, `malformed_stdin_silent` — no output, exit 0.
  - `registered_in_plugin_json` — the manifest lists the script under `UserPromptSubmit` with a quoted `${CLAUDE_PLUGIN_ROOT}` path.
- [ ] **Step 2: Run** `sh plugin-claude-code/tests/run.sh` — FAIL on all new arms.
- [ ] **Step 3: Implement** — extract `prompt` and `session_id` with `jq -r`; delete lines from each `<pasted_content` opening line through its matching closing line; pass the rest to `kt_index_match`; ledger filter; emit with `jq -n --arg` (never hand-built JSON).
- [ ] **Step 4: Run** — green; also `tests/repros/hook-commands-survive-spaced-plugin-root.sh` (the new command must be quoted).
- [ ] **Step 5: Commit** `feat(surfacing): UserPromptSubmit hook surfaces ranked knowledge per prompt`; hygiene gate.

### Task 5: Rules text + canonical ranking paragraph

**Files:**
- Create: `plugin-claude-code/scripts/surfacing-ranking.txt` (the canonical paragraph — exact text below)
- Modify: `plugin-claude-code/rules/aria-rules.md:126` (`ARIA ACTIVE CONTEXT` block)
- Modify: `plugin-claude-code/tests/test-aria-rules-digest.sh` (keep the `:370` presence assertion and the `:759` block list)
- Test: `tests/repros/surfacing-ranking-verbatim.sh`

Canonical paragraph (exact copy):

> Rank the candidate files: (1) a file carrying a matched project tag first; (2) then files carrying more of the matched tags; (3) then files whose path or index description contains more of the task's own words (lowercase, length over 2, common words dropped); (4) then authored files before files under `logs/`; (5) then the file whose rarest matched tag has the fewest files; (6) then index order. Fire when 2 or more tags match, or when 1 matched tag is a configured project. Keep the top 5.

- [ ] **Step 1: Failing tests** — `verbatim_guard`: every file containing the marker pair `<!-- surfacing-ranking:start -->` / `<!-- surfacing-ranking:end -->` carries exactly the canonical text between them (fails today: no copies yet; positive control: a planted copy with one changed word must fail). `digest_no_algorithm`: the Claude Code `ARIA ACTIVE CONTEXT` block no longer contains `cap at top-5` or a numbered matching procedure, and does contain `ARIA ACTIVE CONTEXT —`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Rewrite** the block RUNTIME-NEUTRALLY — one text correct in every port, because `plugin-antigravity/build.sh:170-183` regenerates `rules/` from canonical and that port has no surfacing hook: (a) if ARIA injected ranked knowledge paths with the prompt, read them before answering and say in one line which you used and why; (b) if nothing was injected and Bash is available, run `aria-surface.sh` on the task text and read what it prints; (c) otherwise match the task's words against `## Tag Index` headers and order candidates by the marked canonical paragraph (embedded here between the markers). Keep the ledger sentence. `digest_no_algorithm` becomes `digest_ranking_is_canonical`: the block contains the marked paragraph and no other ordering rule (`cap at top-5` / `first-appearance` absent).
- [ ] **Step 3b: Size check (G2-1).** `test-aria-rules-digest.sh:650-662` enforces a DOWNWARD-ONLY ratchet (20,311 normalised codepoints). Measure the rewritten block against the old one; it must not grow the digest. If it does, tighten the wording; if it still does, STOP and ask the owner — raising a downward-only ratchet is a decision, not a fix.
- [ ] **Step 4: Run** both suites plus `tests/repros/session-start-single-emitter.sh` (its line 69 checks the directive block) — green.
- [ ] **Step 5: Commit** `refactor(surfacing): runtime-neutral directive with the canonical ranking paragraph`; hygiene gate.

### Task 6: Skill Step 0.5 copies

**Files:**
- Modify: `plugin-claude-code/skills/{prospect,retrospect}/SKILL.md` (Step 0.5 items 2–6)
- Modify: `plugin-claude-cowork/skills/{prospect,retrospect}/SKILL.md` (same items)
- Test: `tests/repros/surfacing-ranking-verbatim.sh` (extend)

- [ ] **Step 1: Failing test** — `no_first_appearance_order`: no SKILL.md under `plugin-claude-code/` or `plugin-claude-cowork/` contains `first-appearance order` (Task 7 extends this to every port); `code_skills_call_cli`: the two Claude Code skills contain `"${CLAUDE_PLUGIN_ROOT}/scripts/aria-surface.sh"`; `cowork_carries_paragraph`: the two Cowork skills contain the marked canonical paragraph.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Edit** — Claude Code items 2–6 become: run the CLI on the built query and Read the printed paths (ledger + item 7 onward unchanged). Cowork items 2–6 keep the procedure but replace the ordering sentence with the marked paragraph.
- [ ] **Step 4: Run** — green; then Gate B (`release.sh`'s summed-description check) and the Cowork 9,000-char description cap are unaffected (bodies only).
- [ ] **Step 5: Commit** `refactor(surfacing): skills use the shared ranking`; hygiene gate.

### Task 7: Ports and drift ledger

**Files:**
- Modify: `plugin-openai-codex/bin/lib-index-match.sh`, `plugin-cursor-template/scripts/aria/lib-index-match.sh` (copy canonical byte-for-byte)
- Regenerate: `plugin-antigravity/` via `./plugin-antigravity/build.sh`; `plugin-cursor-template/.cursor/rules/*.mdc` via `python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`
- Modify: `plugin-openai-codex/skills/{prospect,retrospect}/SKILL.md` Step 0.5 → call `"${ARIA_PLUGIN_ROOT}/bin/aria-surface.sh"` (Codex's root variable); copy `aria-surface.sh` into `plugin-openai-codex/bin/` and `plugin-cursor-template/scripts/aria/` (G2-3)
- Modify: `PORT-LEDGER.json` — re-baseline ONLY claude-code, antigravity, cursor-template (`--update <port>` each); for openai-codex add the lib surface's hash with a targeted `jq` edit that leaves its `parity_target` / `last_parity_pass` untouched — its other drift is unverified and `--update all` would certify it (G2-2)
- Modify: the hand-maintained `ARIA ACTIVE CONTEXT` copies — codex `bin/session-start-check.sh`, cursor `scripts/aria/session-start-check.sh`, antigravity `bin/antigravity/pre-invocation-aria.sh:224` — to the Task 5 runtime-neutral text. (Antigravity `rules/aria-rules.md` is NOT hand-edited: `build.sh` regenerates it from canonical.)

- [ ] **Step 1: Failing test** — extend `surfacing-ranking-verbatim.sh`: `four_libs_identical` (cksum of the 4 lib copies equal) and the verbatim guard over the 3 ports' rules text.
- [ ] **Step 2: Run** — FAIL (codex differs; ports lack the paragraph).
- [ ] **Step 3: Copy, regenerate, edit** as listed; run `check-port-drift.sh --update` for the three named ports only AFTER the guard is green. NEVER `--update all`. Extend `no_first_appearance_order` to every port (codex skills, antigravity regenerated skills, cursor `.mdc`).
- [ ] **Step 4: Run** `sh tests/run.sh`, `sh plugin-claude-code/tests/run.sh`, `sh plugin-openai-codex/tests/run.sh`, `plugin-antigravity/tests`, `tests/repros/port-generation-idempotence.sh` — all bare exit 0.
- [ ] **Step 5: Commit** `chore(ports): shared surfacing lib + ranking paragraph in every port`; hygiene gate.

### Task 8: Measure (AC7, AC9) and prepare the release note — then STOP

**Files:**
- Modify: `CHANGELOG.md` (Unreleased entry: behaviour change — surfacing now fires on a single named project and ranks project-first)
- Private (NOT in this repo): measurement record in the maintainer's knowledge folder

- [ ] **Step 1: AC7** — run the REAL lib under `bash` on the 13 private phrasings (kept in the maintainer's knowledge folder). Expected: ≥60/65 project-relevant, controls 5/5, the proj-b payments task's top-5 contains its payments-plan log.
- [ ] **Step 2: AC9** — sample ≥30 real first user messages from local transcripts; run the CLI; judge task relevance per top-5 file; compare to the old lib (checkout of `origin/main`). A control regression BLOCKS release.
- [ ] **Step 3: CHANGELOG** entry; commit `docs: changelog for active-surfacing ranking`; hygiene gate.
- [ ] **Step 4: STOP.** Version bump, push, build and `publish-release.sh` need the owner's go-ahead (RELEASING.md flow; build from the real checkout, not `/tmp` — the bash-write resolver treats `/tmp` as scratch).
