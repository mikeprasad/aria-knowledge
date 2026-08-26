# Spec — restore `pre-bash-write-check.sh` with resolved mutation targets

**Status:** GATED 2026-08-27 — **PROCEED-WITH-CHANGES**; all three changes (C1 drop
`Path.write_text()`, C2 pin the pre-filter invariant, C3 census the ports) are applied in this
revision. Gate: `knowledge/logs/prospect/2026-08-27-file-bash-write-target-resolution.md`.
**Release target:** v2.48.1 (current released: v2.48.0).
**Arc:** `/auto arc full unattended`, push + release granted explicitly by Mike.

## 1. Why this exists — v2.48.0 removed the guard and affirmed the intent

The v2.48.0 CHANGELOG, verbatim:

> **Removed — `pre-bash-write-check.sh`, a guard that was provably wrong in both directions.**
> It warned when a shell command mutated a file in place, bypassing the Rule 22 gate. **The intent
> was sound; the method decided from the command string instead of resolving the mutation target.**

So the intent is not in question and does not need re-litigating — it was *affirmed at the moment of
removal*. What was missing was target resolution, and the archived script says exactly why it was not
attempted:

> Why not fixed instead: resolving the real target needs a shell-command parser (redirections,
> quoting, compound statements, heredocs), and this project's standing rule is that a real false
> positive means KILL the guard rather than tune it. Ruled by Mike, 2026-08-26: *"if it is wrong then
> don't use it."*

**That parser now exists and is measured.** `tools/bash-discipline-check.py::write_targets()` resolves
write targets **per statement** using `shlex` in `punctuation_chars` mode, handling redirections,
quoting, compound statements and heredoc bodies, under 117 mutation-verified controls.

⇒ This spec restores the guard's **measured scope unchanged** and replaces **only** the method.

## 2. The two historical defects, and why ONE mechanism fixes both

| # | Direction | Archived cause | Fixed by |
|---|---|---|---|
| 1 | **False negative** | `case "$COMMAND" in */tmp/*` exempts when the command *string mentions* a temp path. So `cp f /tmp/bak && sed -i … f` was silent — **backup-then-mutate, the careful pattern this project mandates**. Doing the safe thing disarmed the check. | Exempt on the **resolved target path**, never on a string mention. `sed -i … f` resolves to `f`, which is not under a temp root, so it fires. |
| 2 | **False positive** | The idiom match is unanchored, so any command that merely *quotes* an idiom trips it. Observed: a `git commit` whose **message** quoted `sed -i`. | Quoting and heredoc bodies are handled by the lexer. A heredoc body is stripped before tokenizing; a quoted `"use sed -i on f.py"` is ONE token whose basename is `f.py`, so the `sed` verb branch never matches. |

⚑ Both are the same root — deciding from the command *string* rather than the resolved *target* — which
is why one mechanism closes both and no tuning is involved. This is the **KILL-not-loosen rule being
honoured, not circumvented**: the guard was killed, and what returns is a different method, not the
same method with a wider threshold.

## 3. Scope — UNCHANGED from the archived guard, and that is deliberate

The archived scope was **measured, not assumed**: across **25,508 real Bash calls**, `cat > newfile`
is overwhelmingly a throwaway probe or diagnostic harness (legitimate, frequent), while `sed -i` and
`.write_text()` on a tracked file are the actual lapse. The narrowed rule fired on **0.674%** of calls,
about 1 in 148.

⛔ **Do NOT widen to all writes.** The resolver *can* see `>` creation, and using it would raise the
fire rate far above the measured baseline and turn the hook into noise. The scope decision was right;
only the method was wrong. Fixing more than the defect is how a correct guard becomes an ignored one.

**In scope**: `sed -i` · `perl -i` · `awk -i inplace` · an append-redirect (`>>`) into a **source**
file (`.py .ts .tsx .js .jsx .sh .swift .kt .java .rb .go .rs`).

⛔ **`Path.write_text()` is DROPPED from the archived scope — gate change C1, and it is the one
place this restoration is deliberately narrower than the original.** Its target lives inside Python
source text, which a shell lexer cannot reach, so keeping it would mean matching the raw command
string — **precisely the method §2 identifies as defect 2's cause.** A commit message containing
`.write_text()` would fire, reproducing the archived false positive in miniature. Shipping a guard
whose thesis is *"the method was wrong; here is the right method"* while it still carries a fragment
of the wrong method is incoherent, and this restoration's whole credibility rests on defect 2 being
closed.

⚠ **This loses a measured, real lapse** — `.write_text()` on a tracked file was one of the two idioms
the original measurement identified. Stated as a bound, not hidden. **Return condition:** a resolver
that can parse Python source well enough to resolve the argument, at which point it re-enters scope
by the same rule as every other idiom — resolved target, never a string mention.
**Out of scope** (unchanged): file creation via `>` · appends to `.md`/`.json` backlogs (measured always
benign, 1.27% of calls) · anything resolving under a temp/scratch root.

⛔ **EXISTENCE RULE — amended 2026-08-27 during execution, BEFORE the code that implements it.**
A resolved target is reported **only if it exists on disk** at hook time. Three reasons, and the
first is the one that forced it:

1. **A warning hook cannot afford over-detection.** In the root-repo tool over-detection is nearly
   free (a non-path snapshots ABSENT and produces no finding), so `sed -i '' s/a/b/ f` yielding
   `['s/a/b/', 'f']` is harmless there. **Here it would name `s/a/b/` — a sed script — as a mutated
   file, in a message a human reads.** The two tools inherit opposite economics from the same
   resolver, and this is where they must diverge.
2. **It is what "mutates a file IN PLACE" means.** In-place mutation presupposes the file exists;
   requiring existence is the definition, not a heuristic.
3. **It makes `>>` fall out correctly for free.** An append to a file that does not yet exist
   *creates* it — and creation is out of scope (AC5). No separate rule needed.

⚠ Consequence for the controls: fixtures must be **real files**, created by the suite in its own
`TMPDIR`. An AC written against a bare name like `f` would fail for the right reason and read as a
bug. ⚠ Unstattable path (permissions) ⇒ not reported ⇒ fail open, consistent with §D2.

⚠ The archived note that its 0.674% fire rate is an **underestimate** still stands — the corpus could
not count what the hook was blind to (defect 1). Expect the corrected hook to fire somewhat more often.
That is the defect being fixed, not a regression.

## 4. Design

### D1 — WARN-ONLY. It never denies. [DECISION]

`exit 0` always; the message reaches the model via
`{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"…"}}`, which is the archived
hook's own proven channel for putting text into model context without blocking.

⛔ This is what makes the restoration safe, and it is not a compromise. Three false-positive classes were
measured on a *blocking* Bash-write gate in the 24h before this spec — cross-session ledger attribution,
token-bleed, and a marker parser that **denied valid `[Rule 22]` markers three times before its breaker
opened**. A warn-only hook removes **all three by construction**: it keeps no ledger (no attribution), it
parses no transcript (no marker verdict), and it cannot deny (no denial to be wrong about).

### D2 — Resolve targets per statement. [DECISION]

Port `write_targets()`'s approach: strip heredoc bodies, tokenize with
`shlex.shlex(posix=True, punctuation_chars=True, whitespace_split=True)`, split on
`&& || ; | & ( )`, and extract within each statement. Unparseable (`ValueError`) ⇒ **fail open**.

### D3 — `sh` wrapper + `python3` resolver, failing open. [DECISION]

Registration stays `bash ${CLAUDE_PLUGIN_ROOT}/bin/pre-bash-write-check.sh` to match every sibling
hook. The wrapper execs a `python3` helper because quote-aware shell parsing is not expressible in
POSIX `sh` — the reason the fix was deferred in the first place. **If `python3` is absent, exit 0
silently**: a missing interpreter must never cost the user a Bash call. Precedent for Python in this
plugin: `plugin-openai-codex/bin/codex-hook.py`.

⛔ **THE PRE-FILTER INVARIANT — gate change C2, and it must be pinned in the script itself, not
only here.** A cheap `sh` pre-filter runs before `python3` is spawned, so the interpreter is not
started for the ~99% of calls that cannot match. That pre-filter is necessarily string-based, which
is defect 2's method — so it is safe under exactly one condition:

> **The pre-filter may only ever cause a cheap EXIT. It may never cause a warning.
> Every warning must originate in the resolver.**

Under that invariant a pre-filter false *positive* costs one wasted `python3` spawn and nothing
else, and a pre-filter false *negative* is the pre-existing blind spot rather than a new one.
Violate it — let the pre-filter emit — and defect 2 is back through a side door. **Write it as a
comment at the pre-filter AND as a control**, or the next contributor "helpfully" makes it emit.

### D4 — Keep the session-scoped bypass ledger. [DECISION]

Retain the archived `${TMPDIR:-/tmp}/aria-r22-bypass-<session_id>` append, mirroring
`pre-edit-check.sh`'s `aria-r22-denies-<session_id>`. ⚑ Keyed by **session id in the filename**, so
cross-session attribution — the worst of the three measured false-positive classes — is
**unrepresentable** rather than filtered. This is the record that makes "checked" true: a warning the
model ignores would otherwise leave no trace, and an ignored gate is the failure this guard exists to
catch.

### D5 — ADR 085 audit (Bash-tier hook extensions). [DECISION]

Required by `projects/aria/decisions/085`, which governs any Bash-tier hook change:
1. **Infrastructure already paid?** **Yes** — `PreToolUse:Bash` already runs `bash-cd-check.sh` and
   `pre-commit-preflight-check.sh`. This restores a third to a surface that already pays the cost.
2. **Marginal cost?** One `python3` spawn per Bash call, gated behind a cheap `sh` idiom pre-filter so
   the interpreter is not started for the ~99% of calls that cannot match.
3. **Value per fire?** ~0.674% measured, each fire a real Rule 22 bypass.
   **Verdict:** acceptable under the asymmetry test.

## 5. Acceptance criteria

- **AC1** `cp f /tmp/bak && sed -i '' s/a/b/ f` **WARNS** (defect 1 — the archived guard was silent).
- **AC2** `git commit -F -` with a heredoc body quoting `sed -i` is **SILENT** (defect 2).
- **AC3** `git commit -m "use sed -i on f.py"` is **SILENT** (defect 2, quoted form).
- **AC4** `sed -i '' s/a/b/ /tmp/scratch.py` is **SILENT** (temp exemption, by resolved path).
- **AC5** `cat > newfile.py` is **SILENT** (creation is out of scope, measured).
- **AC6** `echo x >> notes.md` is **SILENT**; `echo x >> mod.py` **WARNS** (source-extension rule).
- **AC7** The hook **never** exits non-zero, for any input including malformed JSON and unbalanced quotes.
- **AC8** With `python3` absent, the wrapper exits 0 and emits nothing.
- **AC9** A fire appends one line to `${TMPDIR}/aria-r22-bypass-<session_id>`; nothing is appended when silent.
- **AC10** Every control above is **mutation-verified** — each seen red for its own named reason.
- **AC11** The pre-filter invariant holds: a command that trips the `sh` pre-filter but resolves to
  **no target** is **SILENT**. This is the control for §D3's invariant — it is what proves a warning
  can only come from the resolver, and AC2/AC3 are its concrete instances (a `git commit` whose text
  contains `sed -i` passes the pre-filter and must still produce nothing).

## 6. Non-goals

- Re-arming the root-repo `tools/bash-discipline-check.py` write gate. It stays disarmed; this spec
  does not depend on it and does not repair it.
- Any denial behaviour. Escalating to deny would need a fresh measurement, exactly as the archived
  header said.
- Widening scope to file creation (§3).
- Porting to the other runtimes. **Censused, gate change C3 — the earlier claim was asserted without
  one.** Exactly **two** copies of `pre-bash-write-check` exist in the repo:
  `plugin-claude-code/bin/.archived/` (archived, registered nowhere) and
  `plugin-cursor-template/scripts/aria/pre-bash-write-check.sh`. **`plugin-antigravity` and
  `plugin-openai-codex` carry none.**
  ⚠ **The cursor template's copy is REGISTERED in its `hooks.json` — it is the only port shipping a
  LIVE hook that still uses the provably-wrong method.** Named as a residual and deliberately not
  fixed here: each port needs its own verification, and the cursor template has no test harness in
  this repo. It is the first follow-up after v2.48.1.

## 7. Open questions — ALL CLOSED by the gate

- **OQ1 — CLOSED.** The pre-filter is string-based and is safe under one pinned invariant: it may
  only cause a cheap exit, never a warning. Written into §D3 and enforced by a control.
- **OQ2 — CLOSED, and it falsified the spec's own proposal.** Keeping `Path.write_text()` as a
  string-matched idiom re-imports defect 2. **Dropped** from scope (§3, change C1) with its return
  condition recorded.
- **OQ3 — CLOSED, verified two ways.** `additionalContext` reaches model context: **14** live
  registered hooks in this plugin emit it, including `bash-cd-check.sh` on the **same** `PreToolUse`
  event and the **same** `Bash` matcher this hook will use; and it was observed directly during the
  gate — `post-edit-check.sh`'s scope-check text arrives through that channel after every edit.
