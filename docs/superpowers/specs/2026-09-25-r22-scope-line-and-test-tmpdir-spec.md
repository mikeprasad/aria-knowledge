# Rule 22: a post-edit Scope line is not a pre-edit marker; the plugin suite stops touching the real $TMPDIR

**Date:** 2026-09-25 · **Status:** DRAFT (SPPPE gate 1) · **Target:** aria-knowledge v2.54.2 + codex `2.46.5-codex.0`
**Ruled by Mike (2026-09-25):** "do all fixes and another release when done. include all items" — A (Scope line), B (test temp dir), C (CLAUDE.md footer), D (push the knowledge repo).

## 1. Problem

**A — measured live 2026-09-25 (S8, 2.54.1 installed).** A `doc-updater` Write with no pre-edit assessment was allowed because the line directly above it was the subagent's answer to the previous edit's scope check, `[Rule 22 · Scope] PASS — …`. Every marker matcher accepts `[Rule 22 · <anything>]`:
- `plugin-claude-code/bin/pre-edit-check.sh:214` (`MARKER`) and `:397` (`LINE_MARKER`), mirrored in `plugin-antigravity` by regeneration;
- `plugin-claude-code/bin/pre-bash-r22-carrier.sh:49` (`MARK`) — a heredoc holding a Scope line records a carrier;
- `plugin-openai-codex/bin/codex-hook.py:189` — codex's live detector; codex also prompts for a Scope line after every edit (`:640`);
- `plugin-openai-codex/bin/pre-edit-check.sh:114` — shipped but referenced by nothing.
The framework (`template/rules/change-decision-framework.md:247`) names `· Scope` as the POST-edit line; ADR 036 requires a Low/High Impact assessment before every edit. So answering each scope check satisfies the next edit's gate without assessing it. Live where visible text persists (subagents ~95%); mostly latent on the Claude Code 2.1.280 main thread.

**B — found 2026-09-24/25.** `plugin-claude-code/tests/run.sh` does not isolate `TMPDIR`. Seven test files write under `${TMPDIR:-/tmp}`, and `test-external-fetch-gate.sh:88` `ef_reset` runs `rm -f ${TMPDIR:-/tmp}/aria-extfetch-*` — **deleting every live session's external-fetch cooldowns and breaker counters on each suite run**. Residue measured: `aria-r22-denies-pp2`…`pp5` in the real `$TMPDIR`.

## 2. Acceptance criteria

- **A1** A window whose only marker is `[Rule 22 · Scope] …` → **deny** (text-block form and line-start-in-tool-input form).
- **A2** `[Rule 22]`, `[Rule 22] Low Impact —`, `· Planning`, `· Batch N/M`, `· Implementation` still allow (all measured in use; `· Implementation` 110× this session, undocumented — so the fix EXCLUDES Scope rather than allow-listing).
- **A3** The recorder does not record a carrier whose only marker is a Scope line.
- **A4** Codex's detector rejects a Scope-only window; its other forms still pass.
- **A5** Every post-edit form measured in local transcripts is excluded — `· Scope`, `· scope`, `· SCOPE`, `· Scope check`, `· Scope-check` — while `· Scoped change` (a different word) still counts. *(Gate 2: the first design, `(?!(?i:scope)\])`, still accepted `Scope check` / `Scope-check`.)*
- **A6** Docs say so: framework:247, the always-on digest, and the deny message.
- **B1** A full plugin-suite run leaves the real `$TMPDIR` byte-identical in its `aria-*` entries (listing before = after, with a planted sentinel `aria-extfetch-SENTINEL` surviving).
- **B2** All suites still pass.
- **C1** aria-knowledge `CLAUDE.md` gains a session footer for 2.54.0–2.54.2; `CODEMAP.md` lines that describe marker detection are corrected (secondary impact of A — they would become more wrong).
- **D1** The knowledge repo is pushed after a content scan with a positive control and a visibility check.
- **R** Release 2.54.2 (claude-code + antigravity) and `2.46.5-codex.0`; artifact-verified.

## 3. Design

- **A.** In all six matchers, add a negative lookahead after the separator: `(?!(?i:scope)\b)`. Python `re` supports scoped inline flags (verified on 3.12.4). Example: `\[Rule 22(\s\xb7\s(?!(?i:scope)\b)[^\]]+)?\]`. Codex: `\[Rule 22(?:\s*[·.-]\s*(?!(?i:scope)\b)[^\]]+)?\]`. The carrier's `case *'[Rule 22'*` prefilter is left alone — it only decides whether to start python.
- **B.** `run.sh`: `export TMPDIR="$TMP/tmpdir"; mkdir -p "$TMPDIR"` before any test is sourced; the existing `trap` removes it.
- **C.** Footer in `CLAUDE.md` for 2.54.0–2.54.2; `CODEMAP.md` lines 105, 131, 149, 151 corrected. `CODEMAP.md` is 30 days old overall — a full `/codemap update` stays out of scope.
- **D.** Content-scan `origin/master..HEAD` in the knowledge repo with a positive control; any hit stops the push. Commit nothing of the 86 uncommitted files other sessions hold.

## 4. Alternatives rejected

- Allow-list the documented variants — breaks `· Implementation`, which is in heavy use.
- Stop prompting for the Scope line — the post-edit check is its own discipline (ADR 006); the defect is the matcher, not the prompt.
- Per-test `TMPDIR` fixes in seven files — seven copies of one rule; the runner is the single entry point.

## 5. Risks

- **R1** Agents that relied on Scope lines get denied until they emit a real assessment. The three-strikes breaker prevents a deadlock; the deny message names the fix.
- **R2** A test that silently depended on a real-`TMPDIR` artefact goes red — that is information, not a regression.
