---
status: DRAFT — /prospect gate 1 PROCEED-WITH-CHANGES, C1–C6 applied; awaiting plan
date: 2026-11-08
owner: Mike (rulings: "A best long term foundational"; "1" = overturn OQ3, 2026-11-08)
supersedes: OQ3 of docs/superpowers/specs/2026-11-08-active-surfacing-single-source-ranking-spec.md ("Codex / Antigravity hook equivalents are deferred")
amends: the 2.58.0 final-review fix wave (C1) — removes the quoted-heredoc transport it introduced
---

# Active surfacing — no free text in any model-composed shell command

## 1. Problem

The 2.58.0 fix for C1 moved model-run surfacing to `sh "<cli>" - <<'ARIA_TASK'` … `ARIA_TASK`. A quoted
heredoc stops expansion, but its terminator is in-band: a task-text line that is exactly `ARIA_TASK`
ends the heredoc and the next line runs as shell (re-review confirmed under sh, bash and zsh). The
delimiter is public in this repo, so pasted third-party text can carry it on purpose.

The root cause is not the delimiter. It is that **the model carries untrusted free text into a shell
command at all**. Every "safe" carrier (double quotes, a heredoc, a fixed or random delimiter, a
one-line rule) is a framing the text can still interact with, or an instruction the model must
follow. Claude Code and Codex already avoid it: their prompt hooks hand the prompt to code as an
argument (`jq --arg`, a `subprocess` argv list). Cursor, Antigravity and the skills do not.

## 2. Goal

No instruction anywhere tells a model to compose a shell command that contains free text. Text
reaches the matcher only through code (a hook's stdin JSON, a file read by the CLI itself, `git log`
run by the CLI). Every runtime with hooks ranks in code; only a runtime with no hooks (Cowork) asks
the model to rank by hand, and that path involves no shell.

## 3. Evidence (read 2026-11-08)

- **Cursor** (cursor.com/docs/hooks via Context7): `beforeSubmitPrompt` input carries `prompt` and
  `attachments`; output is only `continue` + `user_message` (cannot inject). `postToolUse` output
  accepts `additional_context` ("injected into the conversation after the tool result"). Every hook
  receives `conversation_id` (stable) and `generation_id` ("changes with every user message").
  `sessionStart` accepts `additional_context` but carries no prompt.
- **Antigravity** (antigravity.google/docs/hooks via Context7): `PreInvocation` fires before every
  model call; input has `invocationNum`, `initialNumSteps`, `conversationId`, `transcriptPath` — **not
  the prompt**; output `injectSteps` accepts `ephemeralMessage`. The port already registers it
  (`bin/antigravity/pre-invocation-aria.sh`).
- **Antigravity transcript, measured on this machine:** records carry `type`, `content`, `source`,
  `status`, `step_index`, `created_at`; user turns are `type == "USER_INPUT"` with `content` a string
  and `source == "USER_EXPLICIT"`. ⚠ Bound: one App transcript, 3 USER_INPUT records; the IDE variant
  had no transcript to read; whether the newest USER_INPUT is written BEFORE `PreInvocation` fires is
  undocumented and unmeasured.
- **Claude Code / Codex:** prompt hooks already argv-safe (2.58.0 Tasks 4 and 7).

## 4. Design

### D1 — The CLI takes references, never free text from a model
`aria-surface.sh` gains two reference inputs and the model-facing text inputs are retired from every
instruction:
- `--file <path>` — the CLI reads the file itself and builds the query from its Markdown headings
  (`^#{1,6} `) plus its first 40 non-blank lines.
- `--git-range <a>..<b>` — the CLI runs `git log --format=%s <a>..<b>` itself (first 20 subjects).
- Either or both; each argument is validated (path: exists, regular file, readable, read with
  `--`-terminated tools; range: each side matches `^[A-Za-z0-9._/~^@{}][A-Za-z0-9._/~^@{}-]*$` — **no
  leading `-` on either side**, because git parses a leading dash as an option — both sides resolve with
  `git rev-parse --verify --end-of-options`, and the log runs as `git log --format=%s --end-of-options
  <a>..<b>`); an invalid reference prints `unavailable: invalid <flag>` (exit 0, AC2 unchanged). [gate-1 C6]
- Positional text and stdin `-` stay for programmatic callers (the Codex hook passes argv in a
  `subprocess` list; tests), but **no instruction to a model uses them**.
- Instructions quote reference arguments in single quotes (`--file '<path>'`): a path or ref is
  model-known, not third-party text, and single quotes stop all expansion.

### D2 — Skill Step 0.5 builds references, not a query string (8 copies + cursor `.mdc`)
`/prospect` and `/retrospect` Step 0.5 run the CLI with the references the scope already has: the
plan/spec/file under review (`--file`), the commit range (`--git-range`). For scopes whose only source
is text the model holds (a ticket body fetched via MCP, `session`, `todos`), the skill writes that
text to a scratch file with the runtime's file-WRITE tool (never a shell redirect) and passes
`--file`. Cowork keeps its by-hand procedure (no shell).

### D3 — Cursor capture hooks (new; overturns OQ3)
- `beforeSubmitPrompt` → `scripts/aria/prompt-capture-check.sh`: reads `prompt`, `conversation_id`,
  `generation_id` with `jq`; ranks in-process via `kt_index_match` (no shell text); applies the session
  ledger; writes the ranked absolute paths to a per-generation pending file under the parse-cache
  directory; always returns `{"continue":true}`; any failure → still `{"continue":true}`, no file.
- `postToolUse` → `scripts/aria/prompt-context-inject.sh`: if a pending file exists for this
  `conversation_id` + `generation_id`, emits `{"additional_context":"ARIA ACTIVE — …"}` once, records
  the ledger, deletes the pending file; otherwise `{}`.
- ⚠ Known limit (documented): delivery is after the first tool call of a generation; a prompt the
  agent answers without any tool gets no injection.

### D4 — Antigravity capture in PreInvocation (overturns OQ3)
`pre-invocation-aria.sh` gains a responsibility: read the newest `USER_INPUT` record from
`transcriptPath`; if its `step_index` has not been surfaced for this `conversationId` (state file),
rank its `content` in-process, apply the ledger, inject `{"ephemeralMessage":"ARIA ACTIVE — …"}`,
record the `step_index` and the ledger. Missing transcript, no USER_INPUT, unparseable line, or no
fire → no injection, exit 0. If the newest user turn is logged only after the hook, the injection
lands one model call later (still correct, never duplicated).

### D5 — The directive and value line carry no command
- `ARIA SURFACE — "<abs path>"` becomes path-only (no `run: … <<'ARIA_TASK'` template); skills use
  it with D1's reference flags.
- The digest's branch (b) ("run the ARIA SURFACE command on the task text") is deleted. The
  directive becomes: (a) an `ARIA ACTIVE —` injection is the source wherever hooks run — none = read
  nothing; (c) only where no hook can run, match the task's words against `## Tag Index` and order by
  the canonical paragraph. Digest stays ≤ 26,198 bytes (Mike's bound).
- Per-port emitters (Codex, Cursor, Antigravity) carry the same (a)/(c) with their own hook named.

### D6 — Tests
- **Class guard:** no tracked instruction file (skills, `.mdc`, digest, emitters, value line) contains a
  model-facing text transport: `<<'ARIA_TASK'`, `aria-surface.sh" -`, `"<task`, `"<the query`. Planted
  copy must fail.
- **CLI:** `--file` and `--git-range` rank from the referenced content; invalid references →
  `unavailable: invalid …`; a referenced file whose CONTENT holds backticks, `$(…)` and a bare
  `ARIA_TASK` line is ranked as literal words and creates no marker (the content never meets a shell).
- **Cursor:** capture→inject exactly once per `generation_id`; silent on missing jq / index / pending;
  `continue` always true; ledger shared; pending file removed; `conversation_id` sanitised.
- **Antigravity:** synthetic `transcript.jsonl` fixture in the measured schema; injects once per
  USER_INPUT `step_index`; silent with no USER_INPUT / malformed lines / missing transcript; existing
  session-start and scope-drain responsibilities unchanged.
- Every new arm red before the change; one mutation per guard.

## 5. Acceptance criteria
- AC1 No model-facing instruction in any port composes a shell command containing free text (D6 class
  guard, census exact).
- AC2 `aria-surface.sh --file` / `--git-range` work; invalid references → `unavailable:`; exit 0.
- AC3 Cursor ranks each prompt in `beforeSubmitPrompt` and injects once per generation via `postToolUse`.
- AC4 Antigravity ranks the newest USER_INPUT in `PreInvocation` and injects once per step.
- AC5 Directive branch (b) gone; digest ≤ 26,198 bytes; ARIA SURFACE path-only.
- AC6 All suites + port tests + idempotence + drift green; hostile-content arms prove no execution.
- AC7 CHANGELOG states Cursor and Antigravity capture is unverified in a live runtime (owed), and the
  Cursor no-tool-call limit.

## 6. Risks
- **Unverified runtimes** (Cursor, Antigravity): hooks are built to the docs + one measured transcript;
  both fail silent. Live verification owed before release, as for Codex.
- **Antigravity write-order** unknown (D4) — worst case one call late.
- **Cursor delivery lag** (D3) — no injection on tool-free answers.
- **Rule 22 friction** for text-only skill scopes (D2 writes a scratch file with the Write tool, which
  the Claude Code gate requires a marker for).
- **More hook work per prompt** in Cursor/Antigravity: same lib + cache budget as the Claude Code hook.

## 7. Rulings
- R1 OQ3 overturned by Mike (2026-11-08, "1"): Cursor and Antigravity get capture hooks.
- R2 The quoted-heredoc transport from the fix wave is retired, not hardened.

## 8. Gate-1 amendments (/prospect 2026-11-08, PROCEED-WITH-CHANGES — log `knowledge/logs/prospect/2026-11-08-file-surfacing-no-model-text-transport-spec.md`)
- **C1 One capture core.** Factor the Claude Code hook's "prompt text → ledger-filtered, ranked
  injection text" (config-value cache, `kt_index_match`, ledger filter/record, `ARIA ACTIVE —`
  formatting, 10,000-char bound) into ONE shared sourced function. The Claude Code prompt hook, the
  Cursor capture hook (D3) and the Antigravity PreInvocation responsibility (D4) each keep only an I/O
  adapter. No second or third copy of that logic.
- **C2 Stamp host premises.** §3's Cursor and Antigravity facts are "docs as read 2026-11-08 via
  Context7" + "one App transcript measured 2026-11-08". At runtime the hooks record `cursor_version`
  (Cursor) / `modelName` (Antigravity) in the debug log (C3), so a later host change is diagnosable.
- **C3 Failure status.** On any hook error (missing jq, unreadable transcript, schema miss, lib error)
  append one line `<UTC> <runtime> <step> <reason>` to `${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}/aria-surface-hook.log`;
  never to model context. A dead hook is then distinguishable from a nofire.
- **C4 Latency.** Cursor `beforeSubmitPrompt` (it blocks the send) and the Antigravity responsibility
  meet p95 ≤ 150 ms warm on a ~45k-line index — the Claude Code hook's budget — via C1's config cache.
  Add to AC3/AC4.
- **C5 Review.** The plan ends with a whole-branch review on the most capable model (the 2.58.0 C1
  defect escaped every per-task review).
- **C6** applied in D1 (range validation).
