# Codex /snapshot locator + port delta to 2.57.4 — plan (2026-10-25)

Mike: "do B and D then push both and deploy the site."

## Measured (this session)

- **Skills:** a normalised 3-way merge of canonical v2.55.1→HEAD changes nothing substantive in Codex or Cowork skills. The remaining differences are `bin/`→`scripts/`, `${CLAUDE_PLUGIN_ROOT}` quoting, and sections each port deliberately diverges in (Cowork SESSION.md ledger, Codex `/auto` self-restart). Codex already has the `CLAUDE_EFFORT` rule and the audit-usage rule; Cowork records `effort: unrecorded` with its reason.
- **Scripts with a real, portable canonical change** (3-way merge into the port copy changes it):
  - `pre-external-fetch-check.sh` (2.57.4 message: "not a refusal", domain-name-only, retry; curated dirs via `KT_CONTENT_DIRS`; time budget inside the scan loop; modified dates) → Codex + Cursor.
  - `config.sh` gains `KT_CONTENT_DIRS` → Codex + Cursor (the dependency of the above).
- **Not ported, deliberately:** Cursor `pre-edit-check.sh` (Claude Code transcript-based Rule 22), the session-start RULE 22 ORDERING sentence about Claude Code 2.1.308, Codex `pre-compact-check.sh` removal (Codex PreCompact output schema not found in current docs — left unchanged, residual).
- **Codex transcripts** (measured on disk + current Codex docs): `${CODEX_HOME:-~/.codex}/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`; `CODEX_THREAD_ID` is set in every shell command Codex spawns and equals the uuid; first record is `session_meta` with `payload.id`. Docs: the label may be missing, consumers must handle that.

## Units

1. **D** — rewrite `plugin-openai-codex/bin/save-transcript.sh`: id from `$CODEX_THREAD_ID` then `$1`; locate `rollout-*-<id>.jsonl` under the sessions dir; confirm the `session_meta` id matches; a known id with no match exits 1 and writes nothing; no id → newest rollout with a `⚠ GUESSED` line. Output path/shape unchanged. Update the skill's Step 1 description; add a test to `tests/test_codex_port.py` (id match, id-no-match exit 1, guessed fallback, never picks another session's newer file). Close the PORTING.md open item.
2. **B** — 3-way merge the two scripts into Codex + Cursor; resolve conflicts keeping port output shape (Codex hookSpecificOutput via adapter, Cursor agentMessage); run suites; re-baseline Codex + Cowork in PORT-LEDGER with the evidence above.
3. Gates: codex suite, session-state, release-codex/cursor/antigravity + cowork build, public hygiene (after commit).
4. Push aria-knowledge (origin/main..HEAD incl. another session's docs commit 8fcde5a — authorised by "push both"); push aria-site; `./deploy.sh` dry-run, then `--apply`; verify live badge + strings.

## Success criteria

Codex suite green incl. new snapshot test (seen red on the old script); external-fetch test green in Codex; Cursor generator idempotent; release builds exit 0; `ls-remote` shows both repos at local HEAD; live ariaknowledge.com serves `v2.57.4` and the Antigravity strings.
