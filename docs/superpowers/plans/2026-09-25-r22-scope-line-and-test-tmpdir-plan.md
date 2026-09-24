# Plan — v2.54.2: Scope line is not a pre-edit marker; plugin suite isolates $TMPDIR (SPPPE gate 3)

**Spec:** `docs/superpowers/specs/2026-09-25-r22-scope-line-and-test-tmpdir-spec.md` (gate 2 PROCEED-WITH-CHANGES, applied). **Ends:** release 2.54.2 + codex `2.46.5-codex.0`, artifact-verified; knowledge repo pushed.

## T1 — Tests first (declare old-code reds before running)
- **New `tests/repros/r22-scope-line-not-a-marker.sh`** on the real base fixture (`transcript-cc21280-real-base.jsonl`, target `toolu_fx_3`), using the `text.jsonl` construction from the carrier suite (replace the line before the target):
  - **SC1** text block = each post-edit form (`Scope`, `scope`, `SCOPE`, `Scope check`, `Scope-check`) → **deny**, one case per form.
  - **SC2** text block = each pre-edit form (`[Rule 22] Low Impact —`, `· Planning`, `· Batch 1/2`, `· Implementation`, `· Scoped change`) → **allow**.
  - **SC3** the Scope line at line start in a prior Bash `tool_use` input (the line-start channel) → **deny**; a Low Impact line there → allow.
  - **SC4** recorder: a Bash call whose heredoc holds only `[Rule 22 · Scope] PASS` writes **no** carrier state; one holding `[Rule 22] Low Impact` writes it.
  - Old code: SC1 ×5 RED, SC3-deny RED, SC4-scope RED; SC2 and the allow arms green.
- **Codex** — new test in `plugin-openai-codex/tests/test_codex_port.py`: `has_rule22_marker` rejects the five post-edit forms and accepts the five pre-edit forms. Old code: RED.
- **B1** — new repro `tests/repros/plugin-suite-leaves-real-tmpdir-alone.sh`: export a fresh `mktemp -d` as the INHERITED `TMPDIR` (standing in for the real one — gate 4: never plant in the user's real `$TMPDIR`), plant `aria-extfetch-SENTINEL` and `aria-r22-denies-SENTINEL` there, list its entries, run the REAL `plugin-claude-code/tests/run.sh`, re-list; assert both sentinels survive and no entry appeared. Old code: RED (`ef_reset` deletes the fetch sentinel; `pp*` files appear). Cost ~34 s.

## T2 — A: the six matchers
`plugin-claude-code/bin/pre-edit-check.sh:214,397`, `bin/pre-bash-r22-carrier.sh:49`, `plugin-openai-codex/bin/codex-hook.py:189`, `plugin-openai-codex/bin/pre-edit-check.sh:114` (unwired, kept consistent), and antigravity by regeneration. Lookahead `(?!(?i:scope)\b)` after the separator.

## T3 — A docs
`template/rules/change-decision-framework.md:247` (a Scope line does not satisfy the pre-edit gate), `rules/aria-rules.md` digest sentence, the pre-edit deny message, `bin/session-start-check.sh` if it restates the accepted forms. Census first: `grep -rn 'Rule 22 · <variant>\|<variant>\]' plugin-claude-code/{rules,template,bin}`.

## T4 — B: runner
`plugin-claude-code/tests/run.sh`: `export TMPDIR="$TMP/tmpdir"; mkdir -p "$TMPDIR"` right after `TMP` is made.

## T5 — Verify
Mutations with named controls: drop the lookahead in each of the six sites (→ SC1/SC3/SC4/codex test) · lookahead with `\]` instead of `\b` (→ SC1 `Scope check`) · remove the case-insensitive flag (→ SC1 `scope`) · remove the `run.sh` export (→ B1). Old-code run with declared reds. Full suites: root, plugin, antigravity bats, codex port, port idempotence; hygiene gate.

## T6 — C docs
`CLAUDE.md` session footer for 2.54.0–2.54.2; `CODEMAP.md` 105, 131, 149, 151.

## T7 — Release
CHANGELOG 2.54.2; claude-code + antigravity manifests 2.54.2; codex `.codex-plugin/plugin.json` → `2.46.5-codex.0` (no codex CHANGELOG exists — record it in the canonical entry); ledger `--update` for `antigravity`, `claude-code`, `openai-codex`; `/preflight`; commit by explicit paths; `./release.sh`, `./release-antigravity.sh`, `./release-codex.sh` BEFORE push; push; annotated tag; `gh release create`; `publish-release.sh --apply`; verify zip contents (lookahead present in all shipped matchers, runner export present).

## T8 — D: knowledge repo
Commit this arc's logs by path. Content-scan `origin/master..HEAD` (tokens: `AKIA`, `sk_live_`, `ghp_`, `ATATT`, `-----BEGIN`, `eyJhbGci`, `xox[bp]-`) with a positive control on a scratch file; zero hits → push; verify by `ls-remote`.
