---
status: DRAFT — /prospect gate 1 PROCEED-WITH-CHANGES (G1-1…G1-4, log knowledge/logs/prospect/2026-11-11-file-ledger-framing-and-safe-create-spec.md); awaiting plan
date: 2026-11-11
owner: Mike (ruling: "do C and put it in the 2.58.0 release", 2026-11-11)
follows: docs/superpowers/specs/2026-11-08-surfacing-no-model-text-transport-spec.md (whole-branch review items (c), (d); final-fix concerns 2–3)
---

# Ledger entry framing, duplicate scope, safe create, Codex temp files

One hardening unit, four parts, shipped inside 2.58.0. No digest bytes: every change is code, tests or
SKILL.md prose (the digest `plugin-claude-code/rules/aria-rules.md` is at its 26,198-byte bound and is not
touched; the SESSION STATE directive's wording stays valid unchanged).

## 1. Measured (this session, scratch copies only; real files read, never written)

Reproduced on fixtures against `lib-session-state.sh` at `3e44761` (claude-code copy; all four ports'
ledger functions are comment-normalised identical, cksum-checked per function):

| # | Fixture | Observed |
|---|---|---|
| F1 | active prompt (fenced) holds a column-0 `### x · <at> · handoff · consumed`; run prune | tail lines **and the closing fence** deleted from the ACTIVE slot; the now-unbalanced fence makes `kt_ss_ledger_candidates` drop a live pending entry (2 candidates → 1) |
| F2 | same, plus a raw `<!-- aria:entry-end -->` line; consume_active, then prune | consume rc 0; prune reaps the entry only to the inner terminator, leaks the tail + a lone fence line; **candidates returns nothing** — a live unconsumed entry below it is hidden |
| F3 | active prompt (fenced) quotes the line `## Pending handoffs`; consume_active | **rc 0 and the handoff is destroyed**: `kt_ss_ledger_add`'s anchor scan is whole-file and fence-blind, so the entry is spliced inside the active fence; the clear then removes its header and token; the file gains a second `## Pending handoffs` and an orphan terminator |
| F4 | (d) a byte-identical block present only under `## Archived …` or quoted in another region | add's RC-3 skip and add_verified's allowance search the whole file, so the add is skipped and "landed" is reported (by inspection of both awk programs; arm AF makes it a fixture) |

Corpus census — every `SESSION.md` under the maintainer's projects tree: **226 files, 166 distinct by
content, 51 with ledger entries, 383 entry headers (368 terminated)**. Counts only, nothing quoted:

- **36** column-0 entry headers (all status `unconsumed`) and **42** raw terminators sit *inside fences*
  inside **consumed** entries; 13 more fenced terminators sit inside live entries.
- Running the shipped prune on scratch copies of all 51: **6 files would gain 6 phantom unconsumed
  candidates each** (one lineage copied into six worktrees — identical candidate set in all six) and
  **21 orphan terminators** remain. These are latent today: the next `/wrapup` or `/handoff` prune in any
  of those copies resurrects them.
- 0 lines already starting with `\` + a structural token (escape collision, §3); 0 terminated bodies with
  an odd fence count; 0 entry headers outside an entry section; 0 consumed entries under `## Archived`;
  exactly 1 tolerant anchor match per file in all 58 files that have one (0 indented, 0 fenced).
  ⚠ A first census reported 57 anchors "in the active slot" — an instrument error (it classified the
  heading line before updating the section); re-measured with a per-state count.
- A reference model of the §4 walker reproduces the shipped `kt_ss_ledger_candidates` output exactly on
  all 51 files (0 mismatches), and its prune leaves 0 phantoms, 0 lost live entries, and only the 13
  fenced terminators that belong to surviving entries.

## 2. Root cause

Two independent faults, both in the same "boundaries" contract:

1. **In-band framing.** A stored prompt is written verbatim, so any line that *looks* structural
   (`## `, `### a · b · c`, ```` ``` ````, the terminator) is structural to some reader. The terminator
   was declared to fix this ("BOUNDARIES ARE DECLARED, NOT INFERRED") but the declaration itself is
   forgeable from inside the body, and readers disagree on fences (candidates/token_locate/
   read_live_prompt are fence-aware; prune and add's anchor scan are not).
2. **Unscoped writers.** prune, the anchor scan, both duplicate checks and both `mark_*` functions
   operate on the whole file, including the ACTIVE slot and archived/other sections, while the readers
   are section-scoped. A writer that acts where no reader looks is how F1–F3 destroy data with rc 0.

## 3. Decision A — escape structural lines on write (closes the class for every new entry)

`kt_ss_ledger_add` encodes every line of the prompt before building the block. One shared builder,
`_kt_ss_entry_block <sid> <at> <focus> <next> <prompt>`, is used by `kt_ss_ledger_add` and
`kt_ss_ledger_add_verified` (which today re-types the block format by hand — Y9 is the only thing
keeping the two in step).

- **Escaped set** (column 0 only): a line matching `^\\*(## |### |```|<!-- aria:entry-end -->$)`.
- **Encode:** prepend one `\`. **Decode:** remove one leading `\` from a line matching
  `^\\+(## |### |```|<!-- aria:entry-end -->$)`. This is mbox `>From ` quoting: encode is injective, so
  decode(encode(x)) = x for every x, including a prompt that already contains `\## …` (it becomes
  `\\## …` and decodes back).
- **Not escaped:** `aria-handoff:` token lines (located by substring, not by structure), indented
  lines (no reader is column-0-blind except add's tolerant anchor, which §4 scopes), `#### ` and deeper,
  `~~~` (no reader toggles on it), focus/next (always behind `- focus: ` / `- next: `).
- **Why `\`:** it is the CommonMark escape, so a raw read of `SESSION.md` (the model reading a pending
  entry to resume it, a human, atlas) shows the original text; no reader needs code to understand it.
- **Backward compatibility:** existing entries are not rewritten. Decode is a no-op on all measured legacy
  bodies (0 collisions). Legacy entries keep whatever framing they have; §4 makes readers and prune agree
  on them.
- **Who decodes:** no code path returns a stored body today (prune deletes, candidates/token_locate read
  headers, add_verified compares the *encoded* block it builds). So no decoder ships in the library — a
  function with no caller is the shipped-but-unwired defect. The test suite carries a reference decoder
  that proves the round trip. `/handoff` Step 0r (4 ports' SKILL.md, prose only) gains one sentence: a
  stored line beginning with `\` before `##`, `###`, ```` ``` ```` or the terminator is escaped; read it
  without that one backslash.

Rejected:
- **Fence the body / fence-aware prune alone** — prune's own comment records that openers contain nested
  fences; a fence is not a reliable boundary and an odd count desynchronises every later reader (F2).
- **Line-count or per-entry nonce in the header** (`· lines=N`, `<!-- aria:entry-end <nonce> -->`) — a
  hand edit to a body (people do edit `SESSION.md`) silently misframes the *next* entry, a worse failure;
  it also changes the machine-parsed ` · ` header every matcher and the external ledger checker split.
- **Indent structural lines** — up to three spaces still renders as a heading and is not reversible.
- **Base64 / encoded body** — unreadable to the model and humans who resume from the raw file.
- **Escape only `### ` and the terminator** — leaves `## ` (the measured 75-entry orphaning class for
  heading-scoped readers) and fences (F2) open.

## 4. Decision B — one region walker; every writer acts only where readers look

A single awk prelude, emitted by `_kt_ss_awk_regions` (a function, so the existing per-function parity
arm covers it), defines `function kt_region(line)` and is concatenated into every program below. It
classifies each line as FM / heading / ACTIVE / LEDGER / ARCH / OTHER, and within LEDGER/ARCH as
entry-header / body / terminator:

1. Front matter: line 1 `---` through the next `---`.
2. Outside an entry: a ```` ``` ```` line toggles fence state; while fenced, every line is content.
   Unfenced column-0 `## ` is a section heading: `## Next session prompt` → ACTIVE; `## Pending handoffs`
   / `## Prior sessions` (trailing whitespace tolerated) → LEDGER; `## Archived…` → ARCH; else OTHER.
3. In LEDGER/ARCH, unfenced and outside an entry, a well-formed header (`### ` + ≥2 ` · `) opens an
   entry. Inside an entry a separate fence counter applies: while odd, every line is body; while even,
   the terminator closes the entry, a well-formed header closes it and opens the next (legacy recovery),
   and a `## ` heading closes it and changes section (today's reader behaviour, M9d).
4. In ACTIVE and OTHER, `### ` lines are always content.

Scope per function (all four ports):

| Function | Today | After |
|---|---|---|
| `kt_ss_ledger_add` anchor scan | whole file, fence-blind, leading-ws tolerant | first walker heading in LEDGER (tolerant set kept: case, bold, level 2/3, trailing ws; **column 0 required** — 0 real anchors are indented) |
| RC-3 duplicate skip (add) and `_ss_av_had` (add_verified) | sliding window over whole file | window must start at a walker entry-header in **LEDGER** (not ARCH, not ACTIVE, not inside a body) |
| add_verified header count | whole file | walker entry-headers in LEDGER |
| `mark_consumed`, `mark_superseded` | every `^### ` line | walker entry-headers in LEDGER ∪ ARCH (ARCH kept: token_locate can return `|archived` and a human may resume it) |
| `kt_ss_ledger_prune` | whole file | reaps only entries opened in LEDGER ∪ ARCH; FM, ACTIVE, OTHER pass through byte-identical. Pass 1 keeps `hasterm[]`, now fence-aware within entries; an entry whose fence-aware walk reaches EOF unclosed falls back to today's fence-blind rule, so the change can never delete more than today |
| `kt_ss_ledger_candidates`, `kt_ss_ledger_token_locate`, `kt_ss_read_live_prompt`, consume_active's clear | each its own fence-aware walk | the walker (one definition of "where ACTIVE ends"; read_live_prompt's comment already demands it) |

Prune's receipts, word-bounded status tests, M9c recovery and `is_entry_header` threshold are unchanged.
The model in §1 shows the candidate output is identical on all 51 real ledgers.

Rejected: per-function fixes (the `mark_superseded` false-parity incident is the precedent for copies
drifting); a pre-pass that tags lines and every awk strips the tag (rewrites every program's I/O); scoping
prune to LEDGER only (silently stops reaping archived consumed entries — 0 today, but a behaviour change
nobody asked for).

## 5. Decision C — shared safe create (`kt_create_new`)

Contract (POSIX sh, no bashisms):

```
kt_create_new NAME   # 0: created a new, empty regular file of ours at NAME. 1: anything else —
                     # NAME exists in any form (file, link, dangling link, dir, FIFO), mktemp failed,
                     # `link` missing or failed. Never opens or follows NAME.
                     # Body: [ -e ] || [ -L ] → 1; t=$(mktemp "<dir of NAME>/.aria-new.XXXXXX");
                     # link "$t" NAME; rc=$?; rm -f "$t"; return rc
kt_is_ours NAME      # 0 iff NAME is not a link, is a regular file, and is owned by the caller
```

Every writer of a predictable name uses one pattern: `[ -e N ] || [ -L N ] || kt_create_new N;
kt_is_ours N || return 0; <append>`. The existence skip keeps steady state at zero extra forks
(antigravity's measured p95 margin). Bound, stated: after creation the file is ours, and in a sticky
directory (`/tmp`) or a private one (macOS `$TMPDIR`) no other user can replace it before the append; in a
non-sticky world-writable directory nothing at this layer helps.

**Home:** the identical body is defined in each library that has a writer — `lib-prompt-surface.sh` (×3),
`lib-index-match.sh` (×4), `lib-tracked-artifacts.sh` (×4) — guarded by one cross-file body-parity arm.
Rejected: `kt_ps_create_new` in `lib-prompt-surface.sh` only (Codex has no copy, and
`lib-tracked-artifacts.sh`'s callers never source it); a new `lib-safe-create.sh` (adds a sourcing path to
three libraries that have no directory contract — `kt_ps_log` can run before anything else is loaded —
and a missing file would silently disable every writer).

**Callers:** `kt_ps_log` (debug log), `_kt_ps_append_kept` (`/tmp/aria-active-<sid>`),
`kt_match_record_ledger`, `kt_artifact_record_ledger`. Antigravity: `ag_create_new` is deleted and
`ag_debug_log` / `ag_record_step` / `ag_log_once` call `kt_create_new`; the hook sources
`lib-tracked-artifacts.sh` before its first use (the plan must verify that file is side-effect-free at
source time; if not, `ag_create_new` stays as a byte-identical body inside the same parity arm).
`session-start-check.sh`'s 24 h sweep (and antigravity's `.aria-ag-new.*` sweep) also removes
`.aria-new.*` leftovers. Missing `link`: fails safe (no file, no write, dedup lost — re-surfacing each
call); the CHANGELOG limit antigravity already carries is generalised to all shell ports.

## 6. Decision D — Codex hook temp files and text-mode subprocesses

Census of `plugin-openai-codex/bin/codex-hook.py` (all under `/tmp`, names from `session_key`, which falls
back to the **PID**):

| File | Today | Fix |
|---|---|---|
| `aria-context-<key>` (30 s cooldown) | `read_text` + `write_text`: follows a link, truncates its target | `_ours_read` + `_ours_replace` |
| `aria-active-<key>` (shared with the shell hooks) | lstat check, then `open("a")` — the create race | `_ours_append` |
| `aria-codex-codemap-<session>-<digest>` | `exists()` then `write_text("seen")`: follows a link | exclusive create via `_ours_create` |
| `aria-session-inprogress-codex-<key>` | `read_text` + `write_text` of project paths: follows a link, overwrites its target | `_ours_read` + `_ours_replace` |

Helpers: `_ours_append`/`_ours_create` = `os.open(path, O_WRONLY|O_APPEND|O_CREAT[|O_EXCL]|O_NOFOLLOW|
O_NONBLOCK|O_CLOEXEC, 0o600)` then `fstat` must be a regular file with our uid, else close and skip
(`O_NOFOLLOW` refuses a link, `O_NONBLOCK` turns a planted FIFO into `ENXIO` instead of a hang).
`_ours_read` = the same with `O_RDONLY`. `_ours_replace` = `mkstemp` in the same directory + `os.replace`
(rename never follows a link; in sticky `/tmp` a foreign name fails `EPERM`, caught). All failures are
silent skips, never exceptions. The key is reduced to `[A-Za-z0-9._-]` (parity with `kt_ps_sanitize_id`);
an empty key skips every write. Names and the `/tmp` location stay: the active ledger is shared with the
shell hooks by name.

Text-mode subprocess sites without an encoding: `run_legacy_capture` (`input=` encodes the hook payload),
`git_value`, and the `/retrospect` commit count. All three get `encoding="utf-8", errors="replace"`, and
each call site catches `(OSError, subprocess.SubprocessError, ValueError)`; `run_legacy_capture` returns
`(0, "", "")` on failure, the same fail-open as a missing script. Measured red: `subprocess.run(['cat'],
input='\udcff', text=True)` raises `UnicodeEncodeError` under the default UTF-8 locale — the earlier "not
demonstrated" note needed a lone surrogate, not a C locale.

## 7. Port parity

| Surface | Relation | How it moves |
|---|---|---|
| `lib-session-state.sh` | 4 ports, per-function comment-normalised parity (block N) | edit canonical; hand-port cursor + codex; antigravity regenerated by `build.sh`, never hand-edited. Add to `_SS_PARITY_FNS`: `_kt_ss_awk_regions`, `_kt_ss_entry_block`, `kt_ss_ledger_mark_consumed`, `kt_ss_ledger_mark_superseded`, `kt_ss_ledger_candidates`, `kt_ss_ledger_token_locate`, `kt_ss_read_live_prompt` (all measured identical today, so the arm starts green) |
| `lib-prompt-surface.sh` | 3 byte-identical copies (no Codex) | edit once, copy, cksum |
| `lib-index-match.sh`, `lib-tracked-artifacts.sh` | 4 byte-identical copies each | edit once, copy, cksum |
| `kt_create_new` / `kt_is_ours` | 11 copies across the above | new cross-file body-parity arm |
| SKILL.md prose (`/handoff` Step 0r; the 3f "terminator declares the boundary for the SHELL HELPERS ONLY" warning, now true only of legacy entries) | 4 hooked ports; cursor `.mdc` regenerated | regenerate cursor on a clean tree first (baseline lesson); codex hand-sync |
| `PORT-LEDGER.json` | per port | re-baseline one port at a time after cksum checks |

## 8. Tests (each arm seen RED on `3e44761` first, unless marked; one mutation per guard, restored from a byte backup and `cmp`-checked)

`tests/repros/session-state.sh`:
- **AA round trip** — hostile prompt: column-0 `### f · <at> · handoff · consumed`, `### f · <at> · handoff · unconsumed`, `## Pending handoffs`, `## Where we left off`, raw terminator, an odd fence count, a line already `\## x`, a line `\\```` (positive controls). Assert: stored body has 0 lines the walker calls structural; reference-decode(stored) is byte-identical to the input; candidates/token_locate see exactly one entry. RED: structural lines present.
- **AB** F1 (prune with a forged consumed header in the ACTIVE slot): ACTIVE byte-identical after prune; candidates unchanged. RED measured.
- **AC** F2 (consume + prune): the live entry below stays a candidate; no orphan terminator/fence outside an entry. RED measured.
- **AD** F3 (quoted `## Pending handoffs` in the active fence, plus an indented and a bold variant): consume rc 0 *and* the consumed entry exists under the real heading with its header and token; one `## Pending handoffs` in the file. RED measured.
- **AE** legacy shape from the census (fenced inner unconsumed headers + fenced terminators inside a consumed entry, synthetic): prune leaves 0 phantom candidates, 0 orphan terminators. RED measured on scratch copies.
- **AF** (d): an identical block under `## Archived` and inside the ACTIVE prompt → add writes into Pending; add_verified reports landed by *count*, not by the allowance; consume_active leaves exactly one consumed Pending entry and the archived copy untouched. Positive control: a true re-run (identical block already in Pending) still skips (Y9 stays green).
- **AG** walker agreement: for one hostile fixture, candidates, token_locate, read_live_prompt, prune and both `mark_*` agree on where ACTIVE ends and which lines are entry headers.
- **AH** backward compatibility: every reader's output on `tests/fixtures/session-contract-vendored/*` and the existing M/S/T/U fixtures is unchanged (expected values recorded before the change). Not a RED arm — a non-regression guard, labelled so.
- **N** parity list extended (§7); planted single-port divergence must redden it.

Prompt-surface core suite, antigravity bats, Codex suite:
- **Safe create** (each shell writer + antigravity's three): planted symlink / dangling link / FIFO / directory / foreign-owner name (foreign owner untestable without a second user — accepted, as in Task 5b) → target unchanged, no hang under a `timeout`, nothing appended; a mktemp shim that plants a link or FIFO **in the create window** (antigravity's existing arm, generalised) → harmless; steady state forks no create. RED: the window-plant arm on the four core writers.
- **Codex** per file in §6: planted link → target bytes unchanged; planted FIFO → returns within 2 s; key `a/../b` → sanitised name; `run_legacy_capture` with `'\udcff'` → no exception (RED measured).

## 9. Acceptance criteria

1. No sequence of `kt_ss_ledger_*` calls on a file whose ACTIVE slot or stored bodies contain structural-looking lines changes ACTIVE, FM or OTHER bytes, or removes any unconsumed entry (AB–AG).
2. A prompt stored by this release round-trips byte-identically through the reference decoder (AA).
3. On every legacy fixture and the vendored contract fixtures, reader output is unchanged (AH); on the census shape, prune creates no phantom candidate and no orphan terminator (AE).
4. Duplicate detection only matches whole entries in LEDGER (AF).
5. Every create of `/tmp/aria-active-<sid>` and the surfacing debug log, in every shell port, goes through `kt_create_new`; a census by symbol finds no `>>` onto those names without `kt_is_ours` immediately before it.
6. Codex: no read or write of the four §6 files follows a link, blocks on a FIFO, or raises; no text-mode `subprocess.run` lacks an encoding.
7. All suites bare exit 0: `tests/run.sh`, plugin-claude-code, codex, antigravity bats, upload limits, drift 0, generators clean, public hygiene; digest byte count unchanged (26,198).

## 10. Risks

- **Legacy ambiguity stays.** An *unfenced* column-0 entry header inside a legacy terminated body is indistinguishable from an unterminated entry followed by a real one; no parse can separate them. Bound: not counted (indistinguishable by definition); fenced cases measured and fixed (§1). New entries cannot create it.
- **Escaped text in a resumed prompt.** A model reading a stored opener sees `\```` and `\## …`; CommonMark semantics make the intent clear, but a model could copy a backslash into a command. Mitigation: Step 0r sentence; no code consumer exists.
- **Shared prelude in every awk program** widens the blast radius of one bug; mitigated by AG and by the model-vs-shipped equivalence check (§1) re-run as part of the plan's validation.
- **`link` dependency** generalised from antigravity to all shell ports (macOS `/bin/link`, GNU coreutils); fails safe.
- **Concurrent writers** (no lock on `SESSION.md`) are unchanged: last writer wins, as today.
- **Codex `/tmp` names stay predictable** by design (cross-hook contract); safety comes from the open flags, not the name.

## 11. Out of scope

The external `tools/check-session-ledger.py` checker (workspace, not this repo; it should learn the escape
before its next touch — note filed, not built); migrating legacy entries; moving Codex files out of `/tmp`;
`mark_session_inprogress`'s `.gitignore` test in Codex.
