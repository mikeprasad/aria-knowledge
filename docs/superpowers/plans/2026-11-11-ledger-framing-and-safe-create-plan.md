# Ledger framing, duplicate scope, safe create, Codex temp files — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop every `kt_ss_ledger_*` writer from acting where no reader looks, stop stored prompts from forging ledger structure, make every predictable-name temp/ledger create link-safe in all shell ports, and make the Codex hook's four `/tmp` files and three text subprocesses unable to follow a link, block on a FIFO or raise.

**Architecture:** One awk prelude (`_kt_ss_awk_regions`) defines `kt_region()`; every ledger program is that prelude plus its own body, so "where ACTIVE ends" and "what is an entry header" have one definition. New entries are built by one builder (`_kt_ss_entry_block`) that backslash-escapes column-0 structural lines (mbox-style, injective). One POSIX `kt_create_new` / `kt_is_ours` pair, byte-identical in the 11 shell library copies, replaces every check-then-append. Codex gets `_ours_*` open helpers with `O_NOFOLLOW|O_NONBLOCK`.

**Tech Stack:** POSIX sh + awk (all four shell ports), Python 3 (`plugin-openai-codex/bin/codex-hook.py`), bats (antigravity tests).

**Spec:** `docs/superpowers/specs/2026-11-11-ledger-framing-and-safe-create-spec.md` (binding). Gate-1 /prospect changes G1-1…G1-4 are folded in below and override the spec where they differ.

## Global Constraints

- Shell is `sh` (bash 3.2 as `/bin/sh` on macOS) or bash for antigravity hooks — never zsh. No bashisms in any `lib-*.sh` (no `local`, no `[[`, no arrays).
- Every directory-dependent command is one parenthesised absolute cd: `(cd "$WT" && <cmd>)`, where `$WT` is the absolute worktree path the controller hands you. Never a bare `cd`.
- Before every Edit/Write emit the Rule 22 marker through Bash: `cat <<'R22'` / `[Rule 22] LOW|HIGH IMPACT — <what>` / `R22`.
- `lib-session-state.sh` parity is **per function** across 4 ports: edit `plugin-claude-code/scripts/` (canonical); hand-port into `plugin-cursor-template/scripts/aria/` and `plugin-openai-codex/bin/`; antigravity's copy is regenerated ONLY by `./plugin-antigravity/build.sh`, never hand-edited.
- `lib-prompt-surface.sh` ×3, `lib-index-match.sh` ×4, `lib-tracked-artifacts.sh` ×4 stay byte-identical: edit canonical, copy to cursor + codex (antigravity via `build.sh`), `cksum` all copies.
- Cursor `.mdc` changes ONLY via `python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`. Never hand-edit a generated `.mdc`.
- Never `check-port-drift.sh --update all`; re-baseline one port at a time after verifying it.
- Digest `plugin-claude-code/rules/aria-rules.md` is NOT edited: byte count stays **26,198**; `git diff --quiet 3e44761 -- plugin-claude-code/rules/aria-rules.md`; digest lock test green without relock.
- Gate B and Cowork summed descriptions unchanged: `git diff 3e44761 -- '*SKILL.md' | grep -E '^[-+]description:'` prints nothing. Cowork (`plugin-claude-cowork/`) is not touched.
- Tests use scratch dirs (`mktemp -d`) only. Never touch a real `SESSION.md`, the real `~/.claude/session-ledger-receipts` (export `KT_SS_RECEIPTS` into scratch), `~/.claude/rules`, or a live `/tmp/aria-active-*` (Codex end-to-end tests use a per-test unique key and delete in `finally`, as `test_active_ledger_link_is_neither_read_nor_written` does).
- Public repo: placeholders `proj-a` / `proj-b` only; no home paths, no private names in code, fixtures, commit messages or this repo's docs.
- After every commit: `sh plugin-claude-code/scripts/check-public-hygiene.sh "$WT"` → exit 0 (exit 2 = the gate's self-test failed, not clean).
- Commit with `git commit -F -` + heredoc (backticks in `-m` are command substitution). Stage named paths only. No push, no version bump, no release.
- Each guard gets one mutation: back up the file (`cp f "$SCRATCH/f.bak"`), mutate, run, observe the named arm go red for the named reason, restore with `cp`, then `cmp` against the backup.
- **GATES** (run at the end of every task, each must exit 0, read the bare exit code — never through a pipe):
  `sh tests/run.sh` · `sh plugin-claude-code/tests/run.sh` · `sh plugin-openai-codex/tests/run.sh` · `bats plugin-antigravity/tests/` · `sh tests/repros/claude-ai-upload-limits.sh`. Close stdin on any hook you run by hand (`</dev/null`). If the plugin suite's real-rules guard fails, check whether another session's SessionStart rewrote `~/.claude/rules` during the run before treating it as a defect.

## Review Focus

1. **CRLF prompts.** A prompt pasted with `\r\n` line ends: `## x\r` is still escaped (prefix match), a terminator line with a trailing `\r` is neither structural to readers nor escaped; round trip must still be byte-identical. → Task 2, arm AA2.
2. **Hand-edited anchor variants.** `**## Pending Handoffs**`, `### pending handoffs`, trailing spaces still anchor and are canonicalised; an INDENTED one no longer anchors (column 0 required) and add appends a new section at EOF. → Task 1, arm AD2.
3. **Empty and fence-only prompts.** An empty prompt stores `- prompt:` + one empty line exactly as today; a prompt that is only ```` ``` ```` stores ```` \``` ```` and decodes back. → Task 2, arm AA3.
4. **Create in an unusual place.** NAME with no `/`, NAME in an unwritable directory, `link` absent from `PATH` → `kt_create_new` returns 1, nothing is written, no `.aria-new.*` left behind. → Task 3, arm `safe_create_fail_safe`.
5. **Empty or all-unsafe Codex key** (`session_id` = `"/"`): every `/tmp` write is skipped and the hook still emits its context. → Task 4, `test_empty_safe_key_skips_every_tmp_write`.

## Task order (and why B comes before A)

Task 0 records the non-regression baselines on the untouched tree. Task 1 is **Decision B** (walker + scoping) and Task 2 is **Decision A** (builder + escape), in that order, because:
- A's acceptance arm AA asserts "0 lines *the walker calls structural*" — that predicate is the walker's, so it must exist first;
- the F1–F3 / (d) data-loss arms (AB–AF) are all fixed by scoping, not by escaping (F3 destroys a handoff through the anchor scan before any new entry is written), so B is independently shippable and testable on legacy-shaped fixtures;
- both decisions edit `kt_ss_ledger_add` / `kt_ss_ledger_add_verified`; doing B first means A drops its builder into already-scoped code instead of B re-scoping A's fresh builder.

Then Task 3 (**C**), Task 4 (**D**), Task 5 (prose/ports/CHANGELOG/ledger), Task 6 (review + retrospect, stop).

---

### Task 0: Baselines and non-regression guards (AH, N extension, generator baseline)

**Files:**
- Modify: `tests/repros/session-state.sh` (new block AH after block Z; extend `_SS_PARITY_FNS` in block N)
- Create: `tests/fixtures/session-reader-baseline/<fixture>.out` (one per file in `tests/fixtures/session-contract-vendored/*.SESSION.md`)

**Interfaces:**
- Produces: `AH_EMITTER_SENTENCE` (test constant, exact text below) that Task 5 appends to the cursor and codex SESSION STATE strings.

- [ ] **Step 1: Generator clean-tree baseline.** On the clean tree run `(cd "$WT" && ./plugin-antigravity/build.sh)` and `(cd "$WT" && python3 plugin-cursor-template/scripts/port-skills-to-mdc.py)`, then `git status --porcelain`. Expected: only the untracked spec/plan docs. If anything else changed, STOP and report — that is pre-existing port drift and is committed separately, never absorbed into a task.
- [ ] **Step 2: Measure parity of the readers.** For each of `kt_ss_ledger_mark_consumed kt_ss_ledger_mark_superseded kt_ss_ledger_candidates kt_ss_ledger_token_locate kt_ss_read_live_prompt kt_ss_read_active_token`, compute `_ss_fnsum` across the 4 ports. Expected: all identical (spec §7 measured the first five; `kt_ss_read_active_token` is this plan's addition — if it differs, hand-port it to canonical's body first, in this task, before adding it).
- [ ] **Step 3: Write the AH guard (non-regression — expected GREEN now, labelled so in the block comment).**
  - Record baselines: for each vendored fixture `F`, write `tests/fixtures/session-reader-baseline/$(basename F .SESSION.md).out` containing, in order and each preceded by a `== <reader>` line: `kt_ss_ledger_candidates`, `kt_ss_read_live_prompt`, `kt_ss_read_active_token`, `kt_ss_read_active_sid`, `kt_ss_read_active_at`, and `kt_ss_ledger_token_locate` with token `aria-handoff: proj-a/none@none` (a token that matches nothing — pins the empty path). Generate with the canonical lib at this commit (copy `F` into scratch as `SESSION.md` first).
  - `AH1 <fixture>`: each reader's output on a scratch copy equals the recorded `.out` byte-for-byte (`cmp`).
  - `AH2` (G1-1): the cursor and codex SESSION STATE directive line (`grep 'SESSION STATE —'` on `plugin-cursor-template/scripts/aria/session-start-check.sh` and `plugin-openai-codex/bin/session-start-check.sh`), with every occurrence of the literal `AH_EMITTER_SENTENCE` removed, has `cksum` equal to the value measured at `3e44761` (write the two numbers into the test as literals).
  - `AH_EMITTER_SENTENCE` (no backticks, no `$`, trailing space included — those strings are double-quoted shell): `A stored prompt line that begins with one backslash before ##, ###, a code fence or the entry-end terminator line is escaped; read it without that one backslash. `
  - Positive control `AH0`: the fixture glob found ≥ 9 files and every `.out` is non-empty — a guard over zero files is a gate with no subject.
- [ ] **Step 4: Extend `_SS_PARITY_FNS`** with the six names from Step 2. Keep the port list as literal words.
- [ ] **Step 5: Run** `sh tests/repros/session-state.sh`. Expected: all AH and N arms PASS (non-regression guards start green by design).
- [ ] **Step 6: Mutations.** (a) In a scratch-backed edit, change canonical `kt_ss_ledger_candidates`'s `^## Pending handoffs` regex to `^## Pending  handoffs` → `AH1` and `N kt_ss_ledger_candidates` go red; restore, `cmp`. (b) Append `x` inside the cursor SESSION STATE string → `AH2` red; restore, `cmp`.
- [ ] **Step 7: GATES.**
- [ ] **Step 8: Commit** `test(session-state): pin reader output on the vendored contract and the cursor/codex directive; parity covers the ledger readers` — paths: `tests/repros/session-state.sh tests/fixtures/session-reader-baseline/`. Hygiene gate.

---

### Task 1: Decision B — one region walker; every writer acts only where readers look

> **Gate-2 amendment G2-1 (binding — /prospect 2026-11-11, log `knowledge/logs/prospect/2026-11-11-file-plan-ledger-framing-and-safe-create.md`): execute this task as TWO commits with a checkpoint between them.**
> - **Task 1a (behaviour-neutral):** add `_kt_ss_awk_regions` and convert ONLY the readers — `kt_ss_ledger_candidates`, `kt_ss_ledger_token_locate`, `kt_ss_read_live_prompt`, `kt_ss_read_active_token`. Ports + `build.sh`. Expected: AH, every pre-existing block and AG(1)(2) GREEN; then run Step 7's corpus check part 1 (old vs new candidates identical, counts only). Commit `refactor(session-state): one region walker; the ledger readers use it`.
> - **Task 1b (behaviour-changing):** scope the writers (add anchor, RC-3 / `_ss_av_had` windows, add_verified counts, `mark_*`, prune, consume_active's clear); arms AB–AF red-first on the 1a tree; AG(3); Step 7 part 2 (phantoms / lost after prune). Commit with the Step 9 subject.

**Files:**
- Modify: `plugin-claude-code/scripts/lib-session-state.sh` — add `_kt_ss_awk_regions`; rewrite the awk in `kt_ss_ledger_add` (anchor scan + RC-3 window), `kt_ss_ledger_add_verified` (`_ss_av_had` window + header counts), `kt_ss_ledger_mark_consumed`, `kt_ss_ledger_mark_superseded`, `kt_ss_ledger_prune`, `kt_ss_ledger_candidates`, `kt_ss_ledger_token_locate`, `kt_ss_read_live_prompt`, `kt_ss_read_active_token`, and the clear in `kt_ss_ledger_consume_active`
- Hand-port: `plugin-cursor-template/scripts/aria/lib-session-state.sh`, `plugin-openai-codex/bin/lib-session-state.sh`
- Regenerate: `plugin-antigravity/bin/lib-session-state.sh` via `./plugin-antigravity/build.sh`
- Test: `tests/repros/session-state.sh` (blocks AB–AG; N list)

**Interfaces:**
- Produces: `_kt_ss_awk_regions()` — prints awk source (single-quote-free) defining:
  - `function kt_region_reset()` — call when `FNR == 1` (two-pass programs read the file twice).
  - `function kt_region(line)` — returns the line's kind and sets globals:
    - return / `R_KIND` ∈ `fm` | `heading` | `content` | `entry_header` | `body` | `terminator`
    - `R_SEC` ∈ `""` (before any heading) | `FM` | `ACTIVE` | `LEDGER` | `ARCH` | `OTHER` (for a `heading` line, the section it opens)
    - `R_ENTRY` = FNR of the open entry's header line (0 outside an entry); `R_FENCED` = 1 when the line is inside a fence at its scope.
  - Optional input array `KT_HASTERM[hdr_fnr]` (prune only; empty for every reader).
- Classification rules (spec §4, exact): FM = line 1 `---` through next `---`. Outside an entry a column-0 line starting ```` ``` ```` toggles the fence; fenced lines are `content`. Unfenced column-0 `## ` is a `heading`: `^## Next session prompt[[:space:]]*$` → ACTIVE; `^## Pending handoffs[[:space:]]*$` or `^## Prior sessions[[:space:]]*$` → LEDGER; `^## Archived` → ARCH; else OTHER. In LEDGER/ARCH, unfenced and outside an entry, `^### ` with ≥2 ` · ` (the existing `is_entry_header`) opens an entry. Inside an entry a separate fence counter applies: odd → `body`; even → `<!-- aria:entry-end -->` (exact line) is `terminator` and closes; a well-formed header closes and opens the next; a `## ` line closes the entry and is classified as a heading — **unless** `KT_HASTERM[R_ENTRY]` is set, in which case it is `body` (prune's unchanged M9c/M9d rule). In ACTIVE and OTHER every `### ` line is `content`.
- Each converted program is `awk "$(_kt_ss_awk_regions)"'<body>'` (or `-f` a temp file holding both — pick one form and use it everywhere).
- Writer scopes (spec §4 table):
  - **add anchor:** the first line, Pending family before Prior family (existing precedence), with `R_FENCED == 0`, `R_ENTRY == 0`, `R_SEC` ∉ {`FM`,`ACTIVE`} (a heading line counts with the section it opens), at column 0, whose `norm()` (strip trailing whitespace and `*`, lowercase — leading whitespace NOT stripped) is one of `## pending handoffs`, `### pending handoffs`, `## prior sessions`, `### prior sessions`. Paired canonicalising write unchanged. Readers keep the exact heading names above.
  - **RC-3 skip and `_ss_av_had`:** a byte-identical window counts only if its first line is an `entry_header` with `R_SEC == LEDGER`.
  - **add_verified header counts (`_ss_av_n0/_ss_av_n1`):** count only `entry_header` lines in LEDGER that start with `### <sid> · <at> · `.
  - **mark_consumed / mark_superseded:** rewrite only `entry_header` lines in LEDGER ∪ ARCH (existing literal `index()` sid/at matching unchanged).
  - **prune:** pass 1 runs the walker and records `KT_HASTERM[hdr]` when an entry closes on a terminator, and `FB[hdr]` when the entry is still open at EOF; for `FB` entries compute today's fence-blind boundaries. Pass 2 reaps only entries whose header is in LEDGER ∪ ARCH; FM/ACTIVE/OTHER lines pass through byte-identical; `FB` entries are reaped by exactly today's rule. Receipts, word-bounded status tests, M9c recovery, `is_entry_header` threshold unchanged.
  - **candidates / token_locate / read_live_prompt / read_active_token / consume_active's clear:** ACTIVE = lines with `R_SEC == ACTIVE`; ledger headers = `entry_header`. Output format unchanged.

- [ ] **Step 1: Write failing arms** in `tests/repros/session-state.sh` (each fixture built in `$TMP`, `KT_SS_RECEIPTS` already scratch):
  - `AB` (F1): active prompt fenced, containing a column-0 `### f1 · 2026-01-01T00:00:00Z · handoff · consumed` and two following lines, plus one live pending entry below. Run `kt_ss_ledger_prune`. Assert: the ACTIVE region (from `## Next session prompt` to the next unfenced `## `) is byte-identical before/after; `kt_ss_ledger_candidates` output identical before/after (2 rows).
  - `AC` (F2): same plus a raw `<!-- aria:entry-end -->` line inside the active fence; `kt_ss_ledger_consume_active` with the slot's token, then prune. Assert: the live pending entry is still a candidate; no `<!-- aria:entry-end -->` or ```` ``` ```` line exists outside an entry per the walker dump (in Task 1 use the walker; on 3e44761 the arm fails at the candidate assertion first).
  - `AD` (F3): active fence quotes the line `## Pending handoffs`, an indented `  ## Pending handoffs`, and a bold `**## Pending handoffs**`; one real `## Pending handoffs` section below. `consume_active` → rc 0; the consumed entry sits under the real heading with its `### <sid> · <at> ·` header and its `aria-handoff:` token; `grep -c '^## Pending handoffs$'` = 1; no orphan terminator.
  - `AD2` (Review Focus 2): a file whose only anchor is `**## Pending Handoffs**` → add lands under it and canonicalises it to `## Pending handoffs`; same for `### pending handoffs  `; a file whose only anchor is `  ## Pending handoffs` (indented) → add appends a new `## Pending handoffs` at EOF and the indented line is untouched. (Non-regression for the first two — label it; the indented case is new behaviour.)
  - `AE` (census shape, synthetic): a consumed entry whose body holds, inside a fence, two column-0 `### x · <at> · handoff · unconsumed` headers and two raw terminators; one live entry after it. Prune. Assert: 0 candidates that were not candidates before (phantoms), 0 terminator lines outside an entry, live entry still a candidate.
  - `AE2` (fallback, non-regression — label it): a consumed entry with an odd fence count and no closing terminator before EOF. Prune output equals the output of the 3e44761 library on the same input (run `git show 3e44761:plugin-claude-code/scripts/lib-session-state.sh > "$TMP/old-lib.sh"` and source it in a subshell).
  - `AF` (d): build one block (focus/next/prompt with **no** structural lines, so it is identical before and after Task 2's escape) and place byte-identical copies under `## Archived sessions` and inside the active fence. `kt_ss_ledger_add` → a new entry appears under `## Pending handoffs` (count +1 there); `kt_ss_ledger_add_verified` returns 0 because the LEDGER header count rose by 1 (assert the count, not just rc); `consume_active` on a slot holding that block → exactly one consumed entry under Pending, and the archived copy byte-identical. Positive control `AF0`: the same block already under Pending → add writes nothing, add_verified returns 0 (Y9 behaviour).
  - `AG` (agreement) on one hostile fixture (fenced and unfenced structural lines in ACTIVE, OTHER and inside entries): (1) the set of lines `kt_ss_read_live_prompt` returns equals the walker's ACTIVE lines and equals the lines prune leaves untouched in ACTIVE; (2) the header lines `kt_ss_ledger_candidates`/`token_locate` report equal the walker's LEDGER `entry_header` lines; (3) `kt_ss_ledger_mark_consumed` and `mark_superseded` on a sid present both as a real header and as fenced content change only the real header line (diff count 1 each).
- [ ] **Step 2: Run red** on the Task-0 tree: `sh tests/repros/session-state.sh`. Expected FAIL: AB (ACTIVE changed), AC (candidates 0 or 1 instead of 1 live), AD (two `## Pending handoffs` / missing header), AE (phantoms ≥ 1), AF (add skipped; add_verified rc 0 by allowance with Pending count unchanged), AG (prune and readers disagree). AD2/AE2/AF0 pass (non-regression, labelled).
- [ ] **Step 3: Implement** `_kt_ss_awk_regions` and convert every function listed above in canonical. Add `_kt_ss_awk_regions` to `_SS_PARITY_FNS`.
- [ ] **Step 4: Port.** Hand-port each changed function to cursor and codex (copy canonical bodies; comments may differ). Run `./plugin-antigravity/build.sh`; `git status` must show only `plugin-antigravity/bin/lib-session-state.sh` changed in antigravity.
- [ ] **Step 5: Run green.** `sh tests/repros/session-state.sh` → AB–AG, AH, N, and all pre-existing blocks (A–Z incl. M8, M9, M9d, S, T7, U, V, W, X, Y) PASS.
- [ ] **Step 6: Mutations.** (a) Make `kt_region` treat `### ` in ACTIVE as an entry header → AB and AG red. (b) Drop the `R_SEC == LEDGER` condition from the RC-3 window → AF red. (c) Drop the `KT_HASTERM` exception → the existing M9d arm red. Restore each from backup, `cmp`.
- [ ] **Step 7: Corpus validation (G1-3), read-only, counts only.** The controller supplies the projects-tree root. In a scratch dir: copy every `SESSION.md` found by `/usr/bin/find <root> -name SESSION.md -type f` to `$SCRATCH/c/<n>/SESSION.md` (never open the originals for writing). Extract the 3e44761 lib to `$SCRATCH/old.sh`. With `KT_SS_RECEIPTS=$SCRATCH/receipts`:
  1. candidates (old lib) == candidates (new lib) on every copy;
  2. after `kt_ss_ledger_prune` with the new lib: phantoms (rows after not in before) = 0; lost live entries (`|pending` rows before not in after) = 0;
  3. report: files found, files with ledger entries, entry headers, candidate mismatches, phantoms, lost — numbers only, in the task report, never in the repo. Compare against spec §1 (226 / 51 / 383) and explain any drift by date, not by assumption. Any mismatch in 1 or a non-zero in 2 → STOP and report; do not commit.
- [ ] **Step 8: GATES.**
- [ ] **Step 9: Commit** `fix(session-state): one region walker; prune, marks, anchor and duplicate checks act only where readers look` — the four `lib-session-state.sh` copies + `tests/repros/session-state.sh`. Hygiene gate.

---

### Task 2: Decision A — shared entry builder that escapes structural lines

**Files:**
- Modify: `plugin-claude-code/scripts/lib-session-state.sh` (add `_kt_ss_entry_block`; `kt_ss_ledger_add` and `kt_ss_ledger_add_verified` use it)
- Hand-port cursor + codex; regenerate antigravity via `build.sh`
- Test: `tests/repros/session-state.sh` (block AA; N list)

**Interfaces:**
- Consumes: `_kt_ss_awk_regions` / `kt_region` (Task 1).
- Produces: `_kt_ss_entry_block <sid> <at> <focus> <next> <prompt>` — writes to **stdout** exactly:
  `### <sid> · <at> · handoff · unconsumed` `\n` `- focus: <focus>` `\n` `- next: <next>` `\n` `- prompt:` `\n` `<encoded prompt>` `\n` `<!-- aria:entry-end -->` `\n`.
  Callers redirect it to their block file (`> "$_ss_blkf"`) and splice with `cat "$_ss_blkf"`; never capture it with `$( )` (that strips the trailing newline).
- Encode (one awk pass over the prompt, `printf '%s\n' "$prompt" | awk …`): a line matching `^\\*(## |### |```|<!-- aria:entry-end -->$)` gets one leading `\`. Focus/next are not encoded. Indented lines, `#### `, `~~~`, `aria-handoff:` lines are untouched.
- Reference decoder (test-only, never shipped): remove one leading `\` from a line matching `^\\+(## |### |```|<!-- aria:entry-end -->$)`.

- [ ] **Step 1: Write failing arms:**
  - `AA` hostile prompt (lines, in order): `### f · 2026-01-01T00:00:00Z · handoff · consumed`, `### f · 2026-01-01T00:00:00Z · handoff · unconsumed`, `## Pending handoffs`, `## Where we left off`, `<!-- aria:entry-end -->`, one ```` ``` ```` (odd fence count), `\## x`, ```` \\``` ````, and `aria-handoff: proj-a/aa@2026-01-01T00:00:00Z`. `kt_ss_ledger_add` it into a fresh file with a `## Pending handoffs` section. Assert: (1) the walker dump classifies every stored prompt line as `body` (0 `heading`/`entry_header`/`terminator` inside the entry); (2) reference-decode of the stored prompt lines is byte-identical to the input; (3) `kt_ss_ledger_candidates` lists exactly 1 row; `kt_ss_ledger_token_locate` with the token returns that entry `|pending`.
  - `AA2` (Review Focus 1): the same prompt with CRLF line ends round-trips byte-identically and yields 1 candidate.
  - `AA3` (Review Focus 3): empty prompt → stored block identical to the 3e44761 format (`- prompt:` + one empty line); a prompt that is exactly ```` ``` ```` stores ```` \``` ```` and decodes back.
  - `AA4` add_verified: the AA prompt added via `kt_ss_ledger_add_verified` returns 0 and the LEDGER header count rose by exactly 1.
- [ ] **Step 2: Run red** → AA(1)(3), AA2, AA3's fence case, AA4 FAIL (structural lines stored raw; extra candidates). AA3's empty case passes (non-regression, labelled).
- [ ] **Step 3: Implement** `_kt_ss_entry_block`; replace the hand-typed block in both `kt_ss_ledger_add` and `kt_ss_ledger_add_verified`. Add `_kt_ss_entry_block` to `_SS_PARITY_FNS`.
- [ ] **Step 4: Port** (cursor, codex by hand; antigravity via `build.sh`).
- [ ] **Step 5: Run green** — whole `session-state.sh` incl. Y9, AF, AH.
- [ ] **Step 6: Mutation.** Drop ```` ``` ```` from the encode alternation → AA(1) red; restore, `cmp`.
- [ ] **Step 7: GATES.**
- [ ] **Step 8: Commit** `fix(session-state): one entry builder escapes structural prompt lines on write` — four libs + test. Hygiene gate.

---

### Task 3: Decision C — shared safe create (`kt_create_new`, `kt_is_ours`) and every caller

**Files:**
- Modify (canonical, then copy): `plugin-claude-code/scripts/lib-prompt-surface.sh` (`kt_ps_log`, `_kt_ps_append_kept`), `plugin-claude-code/scripts/lib-index-match.sh` (`kt_match_record_ledger`), `plugin-claude-code/scripts/lib-tracked-artifacts.sh` (`kt_artifact_record_ledger`) — each also defines `kt_create_new` and `kt_is_ours`. Copies: cursor `scripts/aria/`, codex `bin/` (index-match, tracked-artifacts), antigravity via `build.sh`.
- Modify: `plugin-antigravity/bin/antigravity/pre-invocation-aria.sh` (hand-authored): delete `ag_create_new`; source `lib-tracked-artifacts.sh` before `ag_debug_log`'s first call; `ag_debug_log`, `ag_record_step`, `ag_log_once` call `kt_create_new` / `kt_is_ours`; housekeeping sweep adds `.aria-new.*` (keeps `.aria-ag-new.*` for legacy leftovers).
- Modify sweeps: `plugin-claude-code/scripts/session-start-check.sh`, `plugin-cursor-template/scripts/aria/session-start-check.sh`, `plugin-openai-codex/bin/session-start-check.sh` — add `find /tmp "${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}" -maxdepth 1 -name '.aria-new.*' -user "$(id -u)" -mmin +1440 -exec rm -f {} + 2>/dev/null`.
- Create: `plugin-claude-code/tests/test-safe-create.sh` (same subshell + reported-count protocol as `test-prompt-surface-core.sh`), `tests/repros/safe-create-census.sh`.
- Modify: `plugin-antigravity/tests/test-pre-invocation-aria.bats` (`.aria-ag-new.` → `.aria-new.` in R4 fifo/window/orphan arms; new arms below).

**Interfaces:**
- Produces (exact body, identical in all 11 copies — the spec fixes it; POSIX, no `local`):

```sh
kt_create_new() {
  if [ -e "$1" ] || [ -L "$1" ]; then return 1; fi
  case $1 in */*) _kt_cn_d=${1%/*}; [ -n "$_kt_cn_d" ] || _kt_cn_d=/ ;; *) _kt_cn_d=. ;; esac
  _kt_cn_t=$(mktemp "$_kt_cn_d/.aria-new.XXXXXX" 2>/dev/null) || return 1
  _kt_cn_rc=0; link "$_kt_cn_t" "$1" 2>/dev/null || _kt_cn_rc=1
  rm -f "$_kt_cn_t" 2>/dev/null
  return $_kt_cn_rc
}
kt_is_ours() { [ ! -L "$1" ] && [ -f "$1" ] && [ -O "$1" ]; }
```

- Writer pattern (every caller): compute the content first; then `[ -e "$N" ] || [ -L "$N" ] || kt_create_new "$N" || :` ; then `kt_is_ours "$N" || return 0` ; then the append on the very next line. No command between `kt_is_ours` and the append. The `|| :` is required: callers run under `set -e`. `kt_ps_log` computes `date` **before** the create/check. `_kt_ps_append_kept` creates only when it has something to add.

- [ ] **Step 1: Write failing arms** in `plugin-claude-code/tests/test-safe-create.sh`, each against `kt_ps_log`, `_kt_ps_append_kept` (via `kt_ps_commit`), `kt_match_record_ledger`, `kt_artifact_record_ledger`, with every path in the test dir and `KT_SURFACE_CACHE_DIR`/`TMPDIR`/`HOME` isolated. A bounded runner `sc_bounded SECONDS cmd…` (background + poll + kill, as antigravity's `r4_run_bounded`; no `timeout` binary):
  - `safe_create_static_plants <writer>`: NAME pre-planted as symlink to a file, dangling symlink, FIFO, directory → link target unchanged (`cksum`), nothing created inside the directory, FIFO run finishes inside `sc_bounded 5`. (Non-regression for the static cases — the 3e44761 checks already refuse them; label it.)
  - `safe_create_window_plant <writer>`: a `mktemp` shim on `PATH` that, when asked for `*.aria-new.*`, plants a symlink (then, second run, a FIFO) at NAME. Assert (a) the shim fired (marker file — the instrument control), (b) link target unchanged, (c) bounded, (d) no `.aria-new.*` left. **RED on the pre-task tree for a structural reason:** no writer calls `mktemp`, so (a) fails — the create is an unguarded `O_CREAT` append with no exclusive step.
  - `safe_create_log_date_window`: a `date` shim that plants a symlink at the debug-log name; run `kt_ps_log` with the log absent. Assert target unchanged. **Behavioural RED** on the pre-task tree (it calls `date` between its checks and the append).
  - `safe_create_steady_state`: a counting `link` shim; two `kt_match_record_ledger` calls into an absent ledger → shim count 1, both records present.
  - `safe_create_fail_safe` (Review Focus 4): NAME with no `/` (run in a scratch cwd), NAME in a `chmod 500` dir, `PATH` without `link` → `kt_create_new` returns 1, no file, no `.aria-new.*`.
  - `safe_create_sweep`: `session-start-check.sh` run with `KT_SURFACE_CACHE_DIR=$T/cache`, isolated `HOME`, `</dev/null`, removes a `.aria-new.OLD` (mtime 2020) there and keeps `.aria-new.NEW`. (Plants only in the scratch cache dir.)
- [ ] **Step 2: Census repro** `tests/repros/safe-create-census.sh`:
  - `CC1` the `kt_create_new` and `kt_is_ours` bodies (function-extract + cksum, comments kept) are identical across the 11 copies; a MISSING copy fails.
  - `CC2` the 4 `lib-tracked-artifacts.sh` copies are byte-identical (the other two libs are already pinned in `surfacing-ranking-verbatim.sh`).
  - `CC3` `lib-tracked-artifacts.sh` is side-effect-free at source time: `sh -c '. lib' </dev/null` prints nothing and the file has no top-level statement outside a function (awk scan).
  - `CC4` write-idiom census (AC5): in every shell file under the four ports' script dirs, find lines that write with any of `>>`, `>` (not `>&`, not `/dev/null`), `tee -a`, `tee`, `printf …>`, `echo …>`, and whose target or enclosing function names `aria-active-`, `aria-surface-hook.log`, a ledger variable (`_kt_ledger`, `$1` in `_kt_ps_append_kept`, `_kt_ps_logf`, `lf` in `ag_debug_log`) or the antigravity state/marker names. Each must be immediately preceded (previous non-blank, non-comment line) by a `kt_is_ours` test. (The Python half of the census is `CC5`, added in Task 4.)
  - `CC0` positive control: run the CC4 scanner over a scratch copy containing `printf x >> /tmp/aria-active-x` and `tee -a "$_kt_ledger"` with no preceding check → it must report exactly those 2 lines.
- [ ] **Step 3: Antigravity bats arms:** rename `.aria-ag-new.` to `.aria-new.` in the R4 `fifo_at_create_does_not_hang`, `plant_in_create_window_is_harmless` (the shim's `case` pattern) and `orphan_new_temp_pruned` arms; add `R4 legacy_ag_new_temp_still_pruned` (a 2020 `.aria-ag-new.OLD` is removed on invocationNum 0) and `R4 create_helper_is_shared` (`grep -c 'ag_create_new' pre-invocation-aria.sh` = 0; the hook sources `lib-tracked-artifacts.sh` on a line before the first `ag_debug_log` call).
- [ ] **Step 4: Run red.** `sh plugin-claude-code/tests/run.sh` → `safe_create_window_plant` ×4 and `safe_create_log_date_window` FAIL; `sh tests/repros/safe-create-census.sh` → CC1/CC3/CC4 FAIL (no helper; unguarded appends); bats → renamed arms and the two new arms FAIL.
- [ ] **Step 5: Implement** the helper pair in the three canonical libs, convert the four writers, copy to cursor/codex, run `build.sh`, edit the antigravity hook (source line: `. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-tracked-artifacts.sh" 2>/dev/null || true`, placed before `ag_debug_log` is first called), add the sweeps. `cksum` every lib copy.
- [ ] **Step 6: Run green**: the three suites above plus `tests/repros/surfacing-ranking-verbatim.sh` (byte-identity arms) and `test-prompt-surface-core.sh` (existing link arms).
- [ ] **Step 7: Mutations.** (a) Move `kt_is_ours` above the `date` call in `kt_ps_log` → `safe_create_log_date_window` red. (b) Replace `link` with `ln` in one copy → CC1 red. (c) Delete the `kt_is_ours` line in `kt_artifact_record_ledger` → CC4 red. Restore each, `cmp`.
- [ ] **Step 8: GATES.**
- [ ] **Step 9: Commit** `fix(surfacing): one link-safe create for every predictable-name ledger and log, in every shell port` — the 11 lib copies, the 3 `session-start-check.sh`, the antigravity hook, the new and changed tests. Hygiene gate.

---

### Task 4: Decision D — Codex hook temp files and text-mode subprocesses

**Files:**
- Modify: `plugin-openai-codex/bin/codex-hook.py`
- Test: `plugin-openai-codex/tests/test_codex_port.py`; `tests/repros/safe-create-census.sh` (CC4 Python half)

**Interfaces:**
- Produces (module-level, all failures return the falsy value, never raise):
  - `ARIA_TMP: Path = Path("/tmp")` — the four sites build names from it (names and location unchanged; tests monkeypatch it in-process).
  - `safe_key(raw: str) -> str` — `re.sub(r"[^A-Za-z0-9._-]", "", raw)` (parity with `kt_ps_sanitize_id`; `a/../b` → `a..b`). Empty result ⇒ the caller skips every write.
  - `_ours_open(path: Path, flags: int) -> int | None` — `os.open(path, flags | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, 0o600)`, then `os.fstat` must be `S_ISREG` with `st_uid == os.getuid()`, else close → `None`. Catches `OSError`.
  - `_ours_read(path: Path) -> str | None` — `O_RDONLY`; reads all, decodes utf-8 `errors="ignore"`.
  - `_ours_append(path: Path, text: str) -> bool` — `O_WRONLY|O_APPEND|O_CREAT`, one `os.write`.
  - `_ours_create(path: Path, text: str) -> bool` — `O_WRONLY|O_APPEND|O_CREAT|O_EXCL`.
  - `_ours_replace(path: Path, text: str) -> bool` — `tempfile.mkstemp(dir=path.parent, prefix=".aria-new.")`, write, `os.replace(tmp, path)`; on any `OSError` remove the temp and return `False`.
- Sites (spec §6): `aria-context-<key>` → `_ours_read` + `_ours_replace`; `aria-active-<key>` → `ledger_filter` via `_ours_read`, `ledger_record` via one `_ours_append` (`ledger_is_ours` removed if it has no remaining caller); `aria-codex-codemap-<session>-<digest>` → `_ours_create`, and the reminder is returned only when the create succeeded (a pre-existing name, link or failure ⇒ `None`); `aria-session-inprogress-codex-<key>` → `_ours_read` + `_ours_replace`. All keys pass through `safe_key`.
- Subprocesses: `run_legacy_capture`, `git_value`, the `/retrospect` `rev-list --count` — add `encoding="utf-8", errors="replace"`; wrap each `subprocess.run` in `try/except (OSError, subprocess.SubprocessError, ValueError)`; failure ⇒ `(0, "", "")` / `""` / `""` respectively.

- [ ] **Step 1: Write failing tests** (each in a `TemporaryDirectory`, `module = load_hook_module()`, `module.ARIA_TMP = Path(tmp)` for in-process tests):
  - `test_codex_tmp_files_never_follow_a_link`: for each of the four names, plant a symlink to a sentinel file (and, separately, a dangling symlink), drive the owning function (`user_prompt_submit` with `_surfacing_setup` config for context + active; `maybe_codemap_reminder` with a `CODEMAP.md` in cwd; `maybe_mark_session_state` with `session_state: true` config); assert sentinel bytes unchanged and no file created at a dangling link's target.
  - `test_codex_tmp_files_do_not_block_on_fifo`: plant a FIFO at each name; run the same driver in a `multiprocessing`/subprocess wrapper with a 2 s deadline; assert it returned.
  - `test_session_key_is_sanitised`: `session_id` `a/../b` → files appear as `aria-context-a..b`, `aria-active-a..b`; nothing outside `ARIA_TMP`.
  - `test_empty_safe_key_skips_every_tmp_write` (Review Focus 5): `session_id` `"/"` → no file under `ARIA_TMP`, and `user_prompt_submit` still emits its `ARIA ACTIVE` context.
  - `test_run_legacy_capture_survives_a_lone_surrogate`: with a stub script under a scratch plugin root, `module.run_legacy_capture("stub.sh", "\udcff")` returns a tuple, no exception.
  - `test_git_value_survives_a_missing_git`: with `PATH` set to an empty dir, `module.git_value(Path(tmp), "rev-parse", "HEAD")` returns `""`.
  - `test_every_text_mode_subprocess_run_names_an_encoding`: AST-walk `codex-hook.py`; every `subprocess.run` call with `text=True` (or `universal_newlines=True`) has an `encoding` keyword. Positive control in the same test: the walker flags a parsed snippet `subprocess.run(["x"], text=True)`.
  - Extend `tests/repros/safe-create-census.sh` with `CC5`: every `open(`, `.write_text(`, `.read_text(` and `os.open(` whose argument expression builds an `aria-` `/tmp` name lives inside an `_ours_*` function (positive control: a planted `Path("/tmp")/"aria-active-x").write_text("x")` in a scratch copy is reported).
- [ ] **Step 2: Run red**: `sh plugin-openai-codex/tests/run.sh` → link test FAILS (cooldown/codemap/inprogress follow the link), FIFO test FAILS (cooldown `read_text` blocks), sanitise and empty-key FAIL, surrogate FAILS (`UnicodeEncodeError`), git FAILS (`FileNotFoundError`), encoding census FAILS (3 sites). `test_active_ledger_link_is_neither_read_nor_written` still PASSES (non-regression).
- [ ] **Step 3: Implement** helpers, sites and subprocess changes.
- [ ] **Step 4: Run green**: codex suite, `sh tests/repros/safe-create-census.sh`.
- [ ] **Step 5: Mutations.** (a) Remove `O_NOFOLLOW` from `_ours_open` → link test red. (b) Remove `O_NONBLOCK` → FIFO test red (bounded). (c) Remove `encoding=` from `git_value` → census red. Restore each, `cmp`.
- [ ] **Step 6: GATES.**
- [ ] **Step 7: Commit** `fix(codex): /tmp hook files never follow a link or block on a FIFO; text subprocesses name an encoding` — `codex-hook.py`, `test_codex_port.py`, `safe-create-census.sh`. Hygiene gate.

---

### Task 5: Ports, SKILL.md prose, emitter sentence, CHANGELOG, PORT-LEDGER

**Files:**
- Modify: `plugin-claude-code/skills/handoff/SKILL.md` (Step 0r; the 3f helper bullet), `plugin-openai-codex/skills/handoff/SKILL.md` (same, by hand); antigravity `skills/handoff/SKILL.md` via `build.sh`; cursor `.cursor/rules/aria-commands.mdc` via `port-skills-to-mdc.py`
- Modify: `plugin-cursor-template/scripts/aria/session-start-check.sh`, `plugin-openai-codex/bin/session-start-check.sh` (append `AH_EMITTER_SENTENCE`)
- Modify: `CHANGELOG.md` (`[Unreleased]`), `PORT-LEDGER.json`
- Test: `tests/repros/session-state-token-directive.sh` (new emitter assertion)

**Interfaces:**
- Consumes: `AH_EMITTER_SENTENCE` (Task 0) verbatim.

- [ ] **Step 1: Failing assertion** in `session-state-token-directive.sh`: `b7 "codex hook"` / `b7 "cursor hook"` — the rendered directive (run each `session-start-check.sh` with isolated `HOME`, `KT_SESSION_STATE=true` config, `</dev/null`, capture the emitted text) contains `AH_EMITTER_SENTENCE` exactly once. Asserting the RENDERED output, not the source, catches a shell-quoting accident. Run → FAIL.
- [ ] **Step 2: Emitters.** Insert `AH_EMITTER_SENTENCE` immediately before the closing `"` of the SESSION STATE `MESSAGES` line in both hooks (after `Offer the resume once per session. `). Run → b7 PASS and Task 0's `AH2` still PASS.
- [ ] **Step 3: Step 0r prose (canonical + codex by hand).** At the point the chosen entry's stored prompt is read to resume (after item 5), add one sentence: "⚠ Entries stored since 2.58.0 escape structural lines: a stored line that begins with `\` before `## `, `### `, ```` ``` ```` or `<!-- aria:entry-end -->` is escaped — read it without that one backslash, and never copy the backslash into a command."
- [ ] **Step 4: 3f helper bullet (canonical + codex).** The sentence "⚠ The terminator declares the boundary for the SHELL HELPERS ONLY …" becomes true only of legacy entries: state that entries written by 2.58.0+ carry escaped structural lines and are framed safely for every reader, and that the warning still applies to entries written before 2.58.0. Keep the measured-incident text.
- [ ] **Step 5: Regenerate** `./plugin-antigravity/build.sh` and `python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`. `git status`: only the expected handoff skill / `.mdc` changes (Task 0's clean baseline makes this attributable).
- [ ] **Step 6: CHANGELOG `[Unreleased]`.** One entry for this unit: walker scoping (F1–F3, the six-copy phantom class), escaped prompt lines, shared safe create, Codex temp files + subprocesses. Replace the existing known-limit clause beginning "⚠ Pre-existing, not changed here: a stored prompt that contains a column-0 `### ` line…" with: legacy entries are not rewritten; an unfenced column-0 entry header inside a legacy terminated body stays indistinguishable (spec §10). New known limits: (1) the Claude Code digest's SESSION STATE `|pending` resume path does not carry the unescape sentence (digest is at its 26,198-byte bound and is unchanged); `/handoff` Step 0r and the cursor/codex directives do; (2) generalise the antigravity `link` limit to every shell port: without `link`, ledgers and the debug log are not written (fail safe; dedup lost, so files can re-surface each prompt); (3) the external session-ledger checker must learn the escape before its next touch (out of scope here). No version number.
- [ ] **Step 7: PORT-LEDGER.** Run `sh plugin-claude-code/scripts/check-port-drift.sh` (report). For each of `claude-code`, `antigravity`, `cursor-template`, `openai-codex`, one at a time: diff that port's handoff skill against canonical for the two changed passages, then `--update <port>`, then re-run the report. Never `--update all`. `claude-cowork` untouched.
- [ ] **Step 8: Invariants.** `wc -c < plugin-claude-code/rules/aria-rules.md` = 26198; `git diff --quiet 3e44761 -- plugin-claude-code/rules/aria-rules.md`; the description-diff check prints nothing.
- [ ] **Step 9: GATES.**
- [ ] **Step 10: Commit** `docs(handoff): stored prompt lines are escaped; directives and CHANGELOG say how to read them` — the skill files, `.mdc`, the two hooks, the directive test, `CHANGELOG.md`, `PORT-LEDGER.json`. Hygiene gate.

---

### Task 6: Whole-branch review and retrospect — then stop

- [ ] **Step 1:** Dispatch one fresh reviewer on the most capable model over `3e44761..HEAD` with the spec and this plan. Brief: verify AC1–AC7 against the code (not against this plan), the per-function parity claims by re-running `_ss_fnsum`, and that every non-regression guard is labelled and every RED arm was red for its stated reason. Re-verify each finding before acting; fix only findings that reproduce, each with its own commit and a re-run of GATES.
- [ ] **Step 2:** Invoke `/retrospect range 3e44761..HEAD` (invoke the skill — do not run it inline).
- [ ] **Step 3:** Report and STOP: commits, gate results, the Task 1 corpus counts, any finding not fixed. No push, no bump, no release.
