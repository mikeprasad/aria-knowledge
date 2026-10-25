# SessionStart single emitter — route every message by audience

> Status: DRAFT 2026-10-25 · Implements the target recorded in
> `2026-08-25-always-on-rules-delivery-design.md` §8.1 (ruled 2026-08-26), which was gated
> on OQ1. OQ1 was measured today and passes (§2.2), so §8.2's "if it passes → collapse"
> branch applies.

## 1. Problem

`session-start-check.sh` emits one `systemMessage`. That channel renders to the user and
**never reaches the model**. The script still builds model-directed instructions into it,
so they reach no one who can act on them.

Measured on a real session that went through idle compaction (Claude Code 2.1.310,
2026-10-25), by reading the transcript's `api-request-blob` records, which hold the
request as sent:

- None of the banner's distinctive strings (`Knowledge audit overdue`,
  `ARIA Project Picker`, `CODEMAP Found`) appear in any request, at startup or after
  compaction. Positive control: the `ARIA CONFIG — knowledge_folder` line emitted by
  `session-start-rules.sh` on `additionalContext` is present in the post-compaction
  request.
- The banner is 12.1 KB. Above ~2 KB the UI persists it to a file and shows a 2 KB
  preview, and it re-renders on every `source=compact` SessionStart. Idle compaction
  makes that frequent.

Four kinds of defect follow from that one routing mistake:

| # | Defect | Blocks |
|---|---|---|
| D1 | Model-directed text that exists **only** in the banner and has never reached the model | Project Picker · Project Context (`auto_load_project_context`) · passive ARIA CONTEXT (`active_surfacing: false`) · tracked artifacts (CODEMAP/STITCH active load) · CODEMAP staleness list · the resolved usage-snapshot path |
| D2 | Newer wording that exists only in the banner; the delivered digest carries an older copy | ARIA ACTIVE CONTEXT ledger sentence (`$CLAUDE_CODE_SESSION_ID`, never `ls -t`) · SESSION STATE clauses (`FIFTH argument` reason, `never silently`, the terminal-entry reason, operator-text reconcile, `state-verify gate, not a preamble`) |
| D3 | Stale copies in the banner that contradict the digest | MEMORY PATHWAY names `/clip` (absorbed into `/intake` in 2.46.3) · RULE 22 says "As of v2.10.5" |
| D4 | The tracked-artifacts block is dead in addition to misrouted | It reads `$INPUT` for the session id, and the script never sets `INPUT`, so the block never fires |

D2 has a second consequence. The digest's ARIA ACTIVE CONTEXT still says
`/tmp/aria-active-${session_id}`, the literal that repro `session-ledger-resolution.sh` G
forbids — but G checks `session-start-check.sh`, the copy nobody receives.

Several existing tests are green for the wrong reason: `picker-gating`, `autonomy-posture`
C1/C2 and `session-state-token-directive` assert directive text in the banner, a channel
the model never sees (`feedback_guard_scoped_to_the_wrong_unit`).

## 2. Evidence

### 2.1 The banner is display-only

Above. The script's own comment (line ~248) already says "systemMessage never reached the
model".

### 2.2 OQ1 — one hook can emit both fields — PASSES (measured 2026-10-25)

A fresh headless session (`claude -p`, Claude Code 2.1.310, `--setting-sources project`)
ran one SessionStart hook that printed
`{"systemMessage":"OQ1-SYS-7Q banner","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"OQ1-CTX-7Q: the probe word is ZEBRA-41."}}`.

- The model answered `ZEBRA-41`, so the context half reached it.
- Transcript records: `hook_system_message` (`SessionStart:startup`, "OQ1-SYS-7Q banner")
  and `hook_additional_context` (aggregate, content `["OQ1-CTX-7Q …"]`) — §8.2's corrected
  pass criterion.
- API request blobs: `OQ1-SYS-7Q` count 0 in every request; `OQ1-CTX-7Q` count 1 in the
  system blob. The banner stays user-only; the context reaches the model.

Repeated with the desktop app's own bundled binary (Claude Code **2.1.308**, the version
this desktop session runs): identical result — model answered `ZEBRA-41`, both records
present, banner absent from every API request.

Bound: two Claude Code versions (2.1.308, 2.1.310), the startup source. The compact source uses the same
SessionStart output handling (the idle-compaction session above shows both a
`hook_system_message` and a `hook_additional_context` record under `SessionStart:compact`).

## 3. Decision

Per §8.1: **`session-start-check.sh` becomes the single SessionStart emitter.** It
computes session-start state once and routes each message by audience in one JSON object:

- asks a **human** to act (audit due, config due, run `/setup`, welcome, config errors)
  → `systemMessage`
- instructs the **model** → `hookSpecificOutput.additionalContext`

`session-start-rules.sh` moves to `scripts/.archived/` with a pointer (Rule 6).

Per §10.8 (split by mutability): **behaviour lives in the bundled digest file; the hook
carries only resolved values.** A truncated hook payload then costs "which values", for
which the digest states the safe default (no value line ⇒ that directive is off).

Options considered:

| Option | Verdict |
|---|---|
| A. Collapse into one emitter (§8.1) | **Chosen.** Ruled target; OQ1 now passes; one computation pass, one ledger interaction, no copy to drift. |
| B. Keep two hooks, MOVE the model-directed blocks from check into rules | Viable (moving, not copying, avoids §8.3's drift and ledger race), but keeps two scripts, two config resolutions and two stdin readers for the same trigger — the machinery §8.1 rejected under Rule 13 — and leaves a two-hook shape the spec already ruled a workaround. |
| C. Copy the blocks into the rules hook | Rejected — §8.3: CODEMAP logic would drift between copies, and two hooks recording the tracked-artifacts ledger race on the same trigger. |
| D. Leave the banner alone, only skip it on compact | Rejected — fixes the noise, leaves D1–D4 in place. |

## 4. Design

### 4.1 Script flow (`session-start-check.sh`)

1. Read hook input: `[ -t 0 ] || INPUT=$(cat)`; parse `session_id` and `source` (fixes D4).
2. Housekeeping (unchanged).
3. Config error / not configured / missing knowledge folder → user message only, exit
   (the rules hook exited silently in these cases; unchanged for the model).
4. Capture `DIGEST_WAS_PRESENT`, then `kt_ensure_rules_files` (moved verbatim, with its
   comments and the capture-before-ensure ordering guard).
5. **User messages** — skipped entirely when `source=compact` (the human saw them at
   startup). First-run welcome, audit nags, version and update prompts. Nothing
   model-directed.
6. **Model payload**, in delivery-priority order (the hook channel delivers about the
   first 2,000 characters, so whatever does damage when lost goes first):
   1. compact block (`source=compact` only; moved verbatim)
   2. steady state: the `ARIA CONFIG` line · fallback (digest absent at snapshot time):
      digest + U-rule block + `ARIA CONFIG` (moved verbatim)
   3. `ARIA PROJECT — …` (CWD inside a configured project, `auto_load_project_context`)
   4. tracked-artifacts instruction (unchanged lib output; ledger recorded once)
   5. `ARIA PROJECTS — …` menu + root (picker enabled, CWD outside a project; **not on
      compact** — the offer is once per session and belongs to the opening message)
   6. `ARIA CODEMAPS — …` staleness list
   7. `ARIA USAGE — …` the resolved snapshot path (status-line meter installed)
7. Emit one JSON object holding whichever of the two fields are non-empty. The model
   payload keeps `kt_json_escape_multiline` (newlines preserved); the banner keeps
   `kt_json_escape`.

First run keeps the welcome banner and **still emits the model payload** — the first run
is usually the first-install session, which is exactly when the fallback arm matters.

### 4.2 Value-line formats

```
ARIA PROJECT — this session started inside configured project '<tag>'.
ARIA PROJECTS — menu: <kt_project_menu output>; projects root: <root>.
ARIA CODEMAPS — <entries, same text as today's "CODEMAP Found" list>.
ARIA USAGE — this account's usage snapshot: <path>.
```

### 4.3 Digest additions (`plugin-claude-code/rules/aria-rules.md`)

A new section, "Conditional on a session-start value line", each directive keyed on its
line having reached the model, with the absence stated as off:

- **PROJECT PICKER** (keyed on `ARIA PROJECTS`) — today's picker text, with the menu and
  root read from the line.
- **PROJECT CONTEXT** (keyed on `ARIA PROJECT`) — suggest `/context <tag>` once.
- **CODEMAP** (keyed on `ARIA CODEMAPS`) — read a listed map's Directory section before
  exploring that codebase; a map marked stale may not match the code.
- **TASK BUDGET** gains one sentence: if an `ARIA USAGE` line reached you, that path is
  this account's snapshot.

And in the existing sections:

- passive ARIA CONTEXT under `active_surfacing` `false`.
- D2 ports: the ACTIVE CONTEXT ledger sentence, and the five SESSION STATE clauses.
  Measurement history ("measured 2026-09-17 … 636,898 chars") is evidence, not
  instruction, and stays out.

### 4.4 Registration and references

- `plugin.json`: one SessionStart command, `session-start-check.sh`.
- Re-point references to `session-start-rules.sh`: `lib-user-rules.sh`,
  `pre-compact-check.sh`, `CONFIG.md`, `skills/setup`, `skills/audit-rules`,
  `plugin-antigravity/build.sh` (exclusion list keeps the archived name harmlessly; the
  live name is already excluded), and tests.
- Antigravity regenerates its skills from canonical; it ships neither script.

### 4.5 Test isolation (hazard introduced by this change)

`session-start-check.sh` gains a write to `$HOME/.claude/rules/`. Four existing callers run
it without isolating `HOME` (`picker-gating` ×2, `session-state-token-directive` ×2,
`test-count-backlog-entries` `cb_hook`), so after this change a plain test run would
overwrite the developer's live `aria-rules.md` with the worktree's copy and regenerate
`aria-user-rules.md` from a fixture. Every caller gets `HOME=<sandbox>` and `</dev/null`,
and both runners get a guard that the real files are byte-unchanged (seen red first, by
running one unisolated caller).

### 4.5a Gate findings folded in (prospect 2026-10-25)

- **F1 — the banner's JSON is not valid today.** Run with the real config, the script's
  output fails a strict parse ("Invalid \escape" at char 7,701): `echo` under macOS `sh`
  halves the backslashes `kt_json_escape` doubled, leaving a bare `\x` from the literal
  `\xe2\x98\x85`. The harness rendered it anyway. In one object with the model context, a
  strict reader would lose both. ⇒ The single emitter writes with `printf '%s'` only, and
  AC13 parses every output arm strictly.
- **F2 — retired-subject guards.** `test-aria-rules-digest.sh` asserts that
  `session-start-rules.sh` contains neither `kt_artifact_record_ledger` nor `CODEMAP Found`,
  via `grep … 2>/dev/null`. Once the file is archived the grep fails and both read green
  forever. Replace them with assertions on the live subject: exactly one SessionStart
  registration, and the ledger recorded once per session (AC6). Repro G moves from the banner
  script to the digest, which is where the forbidden `${session_id}` literal actually lives.
- **F3 — standing cost.** The digest grows by an estimated 2–2.5 KB (~550–650 tokens) in every
  session in every project, and in subagents. The hook payload grows by about 1 KB only when
  there are values to report. Measured: the three user rules files total 35,976 B today and
  arrive in full (tails present in a 2.1.310 request). The 2026-08-26 ruling accepted ~5,430
  tokens/session on this channel; this adds ~11%. The real number is measured at AC11.
- **F6 — existing assertions that change meaning**, each re-pointed to the channel it was meant
  to guard: `test-aria-rules-digest.sh` (HOOK var; "does NOT emit systemMessage" becomes "the
  banner carries no directive"; the two F2 guards), `test-audit-rules.sh` AR8,
  `test-user-rules-digest.sh:153`, `statusline-session-start.sh`, `picker-gating.sh`,
  `autonomy-posture.sh` B/C, `session-state-token-directive.sh`,
  `test-count-backlog-entries.sh` `cb_hook`, `session-ledger-resolution.sh` G.
- **Runtime.** Measured at a projects root with five CODEMAPs: check 0.8–1.2 s, rules 0.2 s.
  The merged hook stays far inside its 10 s timeout.

### 4.6 Ports

- Codex and Cursor ship their own `session-start-check.sh` and their own hook adapters;
  their channel semantics differ and are **not changed here** (reported, not ported).
- Cowork has no hooks. Antigravity excludes both scripts.

## 5. Non-goals

No version bump, release or push. No change to nag wording or cadence logic. No change to
the fallback arm's ordering. Codex and Cursor unchanged.

## 6. Acceptance criteria

Each AC names its instrument. Payload checks decode the JSON (`jq`), never grep raw text.

- **AC1** `plugin.json` registers exactly one SessionStart command; `session-start-rules.sh`
  is under `scripts/.archived/` with a pointer comment.
- **AC2** Startup, configured fixture with nags due: `systemMessage` holds the nags and
  **none** of: `RULE 22 ORDERING`, `TASK BUDGET`, `ARIA ACTIVE CONTEXT`, `SESSION STATE`,
  `INSIGHT CAPTURE`, `MEMORY PATHWAY`, `DECISION ROUTING`, `STANDING USER RULES`,
  `Project Picker`, `CODEMAP`. `additionalContext` holds the `ARIA CONFIG` line.
- **AC3** `source=compact`: no `systemMessage` key; `additionalContext` starts with the
  compact block, holds `ARIA CONFIG`, and holds no `ARIA PROJECTS` line.
- **AC4** Picker enabled and CWD outside a project → `ARIA PROJECTS` with the fixture menu
  in `additionalContext`; disabled → absent. (Re-points `picker-gating`.)
- **AC5** A fixture CODEMAP under CWD → `ARIA CODEMAPS` naming it in `additionalContext`.
- **AC6** Given a `session_id` and a configured project with a CODEMAP, the tracked-artifacts
  instruction appears in `additionalContext` and the ledger records it once (D4). Seen red
  against the old script (it never fires there).
- **AC7** Every behaviour sentence of each deleted banner directive is present in the digest
  (sentence census, measurement-history sentences excluded and listed). Repro G checks the
  digest. `session-state-token-directive` and `autonomy-posture` C1/C2 assert against the
  digest (behaviour) and `additionalContext` (config), not the banner.
- **AC8** Fallback arm unchanged: with the digest absent before the run, `additionalContext`
  carries the digest (existing `test-aria-rules-digest` assertions, re-pointed).
- **AC9** Both suites leave the real `~/.claude/rules/aria-rules.md` and
  `aria-user-rules.md` byte-unchanged; the guard goes red when one caller's `HOME`
  isolation is removed.
- **AC10** Every test caller of the hook closes stdin; the full suites finish (no hang).
- **AC11** Measured model-payload size, steady and compact, at a projects root with a
  realistic 30-entry menu and 5 CODEMAPs. Reported as measured; the design does not depend
  on a margin (§3).
- **AC12** Live: a fresh headless session with the worktree plugin (`--plugin-dir`) shows
  the picker and CODEMAP values in its `hook_additional_context` record and a nags-only
  `hook_system_message`. The compact arm cannot be triggered headlessly; it is owed after
  install (one live compaction, its `SessionStart:compact` records classified).
- **AC13** Every output arm parses with a strict JSON parser: config error, not configured,
  missing folder, first run, startup with nags, startup with no nags, compact, fallback.
  Seen red first against the current script (which fails at char 7,701 with the real config).
