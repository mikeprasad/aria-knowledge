# Cowork `/interview` Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the `/interview` skill to `plugin-claude-cowork/` so cowork is just as capable as canonical v2.31.0, then re-baseline the drift ledger and ship cowork v1.4.0.

**Architecture:** COPY-then-refactor. The cowork skill is canonical's `/interview` SKILL.md with exactly three surfaces adapted (frontmatter, Runtime Gate, Step 0 config-read); everything else — mode logic, cadence logic, deep-dive basis-gate, question banks, output paths, templates — is copied verbatim so output stays byte-identical per ADR-013. The cap is gated by `release.sh`'s aggregate-description preflight, read BEFORE the version bump is committed.

**Tech Stack:** Markdown SKILL.md files; bash `release.sh` + `check-port-drift.sh`; `jq` (already a dependency).

**Executable acceptance criterion (from prospect §6.3):** parity iff (a) 3 modes + cadence + deep-dive basis-gate preserved; (b) output paths + templates byte-identical to canonical; (c) only divergences are the documented cowork adaptations; (d) `release.sh` passes; (e) drift-checker shows `interview = ok`.

**Working directory:** `/Users/mikeprasad/Projects/aria/aria-knowledge`

---

### Task 1: Create the cowork `/interview` skill (COPY-then-refactor)

**Files:**
- Create: `plugin-claude-cowork/skills/interview/SKILL.md`
- Reference (read-only): `plugin-claude-code/skills/interview/SKILL.md` (canonical source)
- Reference (pattern): `plugin-claude-cowork/skills/foundational-review/SKILL.md` (proven cowork gate/fallback shape)

- [ ] **Step 1: Copy canonical verbatim as the starting point**

```bash
mkdir -p plugin-claude-cowork/skills/interview
cp plugin-claude-code/skills/interview/SKILL.md plugin-claude-cowork/skills/interview/SKILL.md
```

- [ ] **Step 2: Replace the frontmatter (description + allowed-tools)**

Replace the canonical frontmatter block (lines 1–5) with the cowork frontmatter. The description is a tight routing signal (target ~300–380 chars; canonical's ~1100 would blow the cap). Drop `Bash` from `allowed-tools`.

```yaml
---
description: "Interview the user to ELICIT knowledge through dialogue, then stage it to the intake/ tree (elicit-side counterpart to /extract /intake /clip which HARVEST existing sources). Three modes: 'project' (scope a new build), 'knowledge' (get a topic out of your head into the KB), 'deep-dive' (extract the rationale behind something you already built — REQUIRES a basis). Cadence (one-at-a-time socratic vs research-then-batch) chosen in-session. Use when user says '/interview', 'interview me about X', 'grill me on X', 'deep dive on X', 'scope this project'. Stages to intake/ for manual review; never auto-promotes. (Cowork variant — namespaced-only.)"
argument-hint: "<project|knowledge|deep-dive> [topic] [--ground=<path|glob|url>[,...]]"
allowed-tools: Read, Glob, Grep, Write, Edit, WebFetch
---
```

- [ ] **Step 3: Replace the Runtime Gate with the cowork-side gate**

Replace the canonical `## Runtime Gate (per ADR-094)` section (the "Canonical resolution: This is the Claude Code variant…" block) with the cowork-side gate, modeled on `foundational-review`'s proven shape — Bash-PRESENT is the mismatch signal, redirect to the canonical:

```markdown
## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session, bare `/interview` resolves to aria-knowledge's variant — Code is the canonical owner of all dual-port skills per ADR-094 §Part 1. To reach this skill, use the namespaced form: `/aria-cowork:interview`. Do NOT match bare `/interview` — that belongs to aria-knowledge.

**Before Step 0:** Check whether the `Bash` tool is available in this session. If `Bash` IS available (you are running in Claude Code or another runtime with shell access), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-cowork's `/interview` from a runtime with shell access.**
>
> This variant runs conversationally and resolves your knowledge folder by reading the config file directly (no Bash). For the Code-native variant, use `/interview` (the aria-knowledge canonical).
>
> **Use `/interview` instead?** (`y` / `n`)

- **`y` / `yes`** — Use the `Skill` tool to invoke `interview` (the bare-slash canonical) with the same arguments. Do not proceed here; the aria-knowledge variant takes over. This is the default-yes path.
- **`n` / `no`** — Proceed with this (aria-cowork) variant anyway. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. If `Bash` is NOT available (normal Cowork runtime), proceed to Step 0.
```

- [ ] **Step 4: Adapt Step 0 (config read) — drop Bash, add paste fallback**

Replace canonical's `## Step 0: Resolve Config` block with the cowork no-Bash version:

```markdown
## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` with the `Read` tool and extract `knowledge_folder`. If the file is not reachable in this runtime (Cowork's attached-folder sandbox may not expose `~/.claude/`), do NOT stop — ask the user: "I can't reach your aria-knowledge config from here. Paste your knowledge-folder path (e.g. `~/Projects/knowledge`) and I'll use it for this session." Use the pasted path. If the user has never run `/setup`, point them there first.
```

- [ ] **Step 5: Verify ONLY the three surfaces changed (diff the bodies)**

Run: `diff <(sed -n '/^## Step 1/,$p' plugin-claude-code/skills/interview/SKILL.md) <(sed -n '/^## Step 1/,$p' plugin-claude-cowork/skills/interview/SKILL.md)`
Expected: **no output** (Steps 1–6, question banks, and output templates are byte-identical from `## Step 1` onward — the only edits were frontmatter, Runtime Gate, and Step 0, all above `## Step 1`).

If the diff shows anything, the copy was edited too broadly — restore the verbatim body. This is the ADR-013 byte-identical-output guarantee made into a check.

- [ ] **Step 6: Sanity-check the description char length**

Run: `python3 -c "import re; t=open('plugin-claude-cowork/skills/interview/SKILL.md').read(); m=re.search(r'^description:\s*\"(.*?)\"', t, re.M|re.S); print(len(m.group(1)))"`
Expected: a number in the ~300–420 range. (Not the cap gate — that's Task 3's release.sh preflight — just an early smell check.)

- [ ] **Step 7: Commit**

```bash
git add plugin-claude-cowork/skills/interview/SKILL.md
git commit -m "feat(cowork): port /interview skill (cowork-adapted, parity w/ canonical v2.31.0)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Update the release.sh expected-skills smoke list

**Files:**
- Modify: `plugin-claude-cowork/release.sh` (the expected-skills list the build smoke-checks)

- [ ] **Step 1: Find the expected-skills list**

Run: `grep -n "expected_skills=" plugin-claude-cowork/release.sh`
Expected (verified): a single space-separated shell string at ~line 209 — `expected_skills="ask audit-config audit-knowledge context extract handoff index intake prospect retrospect rules snapshot stats wrapup aria-setup help backlog clip foundational-review readiness-audit"`. It is NOT alphabetical — the last two (`foundational-review readiness-audit`) were appended in v1.3.0.

- [ ] **Step 2: Append `interview` to the string**

Append ` interview` to the end of the `expected_skills="…"` string (same append-style as v1.3.0's two additions). The edited line becomes:

```bash
expected_skills="ask audit-config audit-knowledge context extract handoff index intake prospect retrospect rules snapshot stats wrapup aria-setup help backlog clip foundational-review readiness-audit interview"
```

- [ ] **Step 3: Commit**

```bash
git add plugin-claude-cowork/release.sh
git commit -m "chore(cowork): add /interview to release.sh expected-skills smoke list

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Run release.sh preflight and READ the cap (gate before bump)

This is the prospect's required-change task: the aggregate-description preflight is read BEFORE the version bump is committed, so a cap overage fails loud and pre-commit.

**Files:** none modified in this task (verification only).

- [ ] **Step 1: Run the release build in its verifying form**

Run: `cd plugin-claude-cowork && ./release.sh` (or its `--verbose`/dry equivalent if one exists — check `head -30 release.sh` for flags first).
Expected: the script prints `total skill description chars: <N> (warn >8500, fail >9000)`.

- [ ] **Step 2: Read the char count and branch**

- If `<N> <= 8500`: PASS — proceed to Task 4.
- If `8500 < N <= 9000`: build passes with a warn — acceptable, but note it in the CHANGELOG. Proceed to Task 4.
- If `N > 9000`: **STOP.** The build hard-fails. Trim the least-load-bearing existing cowork skill descriptions (candidates: the longest non-routing-critical ones — check with `python3` per-skill measurement) until under 9000. Re-run Step 1. Do NOT proceed until the build passes. (Per spec §2: there is no canonical-trim carry-over slack, so any needed trim is fresh — favor trimming verbose trigger lists over removing routing keywords.)

- [ ] **Step 3: Confirm the .plugin artifact contains the interview skill**

Run: `unzip -l plugin-claude-cowork/aria-cowork-*.plugin 2>/dev/null | grep interview` (or inspect the built artifact path the script reported).
Expected: `skills/interview/SKILL.md` present.

No commit in this task — it is a gate.

---

### Task 4: Version bump + CHANGELOG (after cap is confirmed)

**Files:**
- Modify: `plugin-claude-cowork/.claude-plugin/plugin.json` (version)
- Modify: `plugin-claude-cowork/CHANGELOG.md` (new entry)

- [ ] **Step 1: Bump the version**

In `plugin-claude-cowork/.claude-plugin/plugin.json`, change `"version": "1.3.0"` → `"version": "1.4.0"`.

- [ ] **Step 2: Add the CHANGELOG entry**

Prepend below the `# Changelog` preamble in `plugin-claude-cowork/CHANGELOG.md`:

```markdown
## [1.4.0] — 2026-06-18

**Port `/interview` to Cowork (parity with aria-knowledge v2.31.0).** The 3-mode knowledge-elicitation skill — `project` (scope a new build), `knowledge` (get a topic into the KB), `deep-dive` (extract the rationale behind an existing system; requires a basis) — now ships in Cowork as `/aria-cowork:interview`.

- **Add: `/aria-cowork:interview <project|knowledge|deep-dive> [topic] [--ground=...]`** — interviews the user to elicit knowledge through dialogue, then stages it to `intake/projects/` or `intake/interviews/` for manual review (never auto-promoted). In-session cadence choice (socratic vs battery). Output files (paths + frontmatter + body templates) are byte-identical to the canonical Code skill per ADR-013.
- **Cowork adaptations:** cowork-side Runtime Gate (bare `/interview` resolves to aria-knowledge; this variant is `/aria-cowork:interview`); no Bash — Step 0 reads the config file directly and falls back to asking the user to paste their knowledge-folder path; `allowed-tools` drops `Bash`. Grounding ingestion uses Read/Glob/Grep/WebFetch (all available in Cowork).
- **Parity:** coordinates with aria-knowledge v2.31.0. Skill manifest 26 → 27 distinct. Summed SKILL.md description chars = <N> (under the 9000 cap; release.sh preflight gated).
- **Note:** ADR-005's permanent exclusions (`/codemap`, `/stitch`, `/distill`, `/audit-share`) remain out — not gaps.
```

(Replace `<N>` with the actual count read in Task 3 Step 2.)

- [ ] **Step 3: Commit**

```bash
git add plugin-claude-cowork/.claude-plugin/plugin.json plugin-claude-cowork/CHANGELOG.md
git commit -m "release(cowork): v1.4.0 — /interview parity with canonical v2.31.0

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Re-baseline the drift ledger

**Files:**
- Modify: `PORT-LEDGER.json` (via the tool, not by hand)

- [ ] **Step 1: Re-baseline only the cowork port**

Run: `./plugin-claude-code/bin/check-port-drift.sh --update claude-cowork`
Expected: `re-baselined claude-cowork: version=1.4.0 parity_target=2.31.0 surfaces=<N> last_parity_pass=2026-06-18`

(Verified in prospect: `--update <port>` recomputes only the `claude-cowork` key via jq and re-reads cowork's plugin.json version; other ports untouched.)

- [ ] **Step 2: Verify the drift report is now clean for cowork**

Run: `./plugin-claude-code/bin/check-port-drift.sh --table | grep claude-cowork`
Expected: `interview` row = `ok`; no `drifted`/`missing` rows for cowork (the v1.2.0-vs-v1.3.0 noise and removed-alias `missing` flags are cleared by the re-baseline); the version line shows `1.4.0 → target 2.31.0`.

- [ ] **Step 3: Commit**

```bash
git add PORT-LEDGER.json
git commit -m "chore(ledger): re-baseline claude-cowork to v1.4.0 (interview parity)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Update docs (CLAUDE.md footers + skill count)

**Files:**
- Modify: `plugin-claude-cowork/CLAUDE.md` (skill count + current-release status)
- Modify: `aria-knowledge/CLAUDE.md` (the "Cowork Port" section footer — current cowork release)

- [ ] **Step 1: Update cowork CLAUDE.md skill count**

In `plugin-claude-cowork/CLAUDE.md`, update the skill count references from "26 skills (24 distinct + 2 aliases)" to "27 skills (27 distinct + 0 aliases)" (v1.3.0 already removed the 2 aliases; this adds `interview`). Update the status line to note v1.4.0 / `/interview` parity. Match the existing prose style; do not rewrite surrounding history.

- [ ] **Step 2: Update the canonical CLAUDE.md Cowork Port footer**

In `aria-knowledge/CLAUDE.md`, in the `## Cowork Port (plugin-claude-cowork/)` section, update "**Current cowork release: v1.2.0**" (or whatever it currently reads) to "**Current cowork release: v1.4.0** (2026-06-18, with aria-knowledge v2.31.0 — `/interview` skill ported, cowork-adapted)" and bump the "26 skills (24 distinct + 2 aliases)" reference to "27 skills (27 distinct)". Match existing style.

- [ ] **Step 3: Commit**

```bash
git add plugin-claude-cowork/CLAUDE.md CLAUDE.md
git commit -m "docs(cowork): record v1.4.0 /interview parity in CLAUDE.md footers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification (executable acceptance criterion)

After all tasks, confirm against the prospect's 5-point bar:

- [ ] (a) **Modes preserved:** `grep -c "project\|knowledge\|deep-dive" plugin-claude-cowork/skills/interview/SKILL.md` shows the mode logic + deep-dive basis-gate present.
- [ ] (b) **Byte-identical output:** Task 1 Step 5's diff was empty (Steps 1–6 + templates unchanged).
- [ ] (c) **Only documented divergences:** the only body changes vs canonical are frontmatter, Runtime Gate, Step 0.
- [ ] (d) **release.sh passes:** Task 3 build succeeded under the cap.
- [ ] (e) **Drift clean:** Task 5 Step 2 shows `interview = ok`.

**Out of scope (do NOT do):** re-port `/codemap`, `/stitch`, `/distill`, `/audit-share` (ADR-005 permanent exclusions); port canonical v2.30.0 Code-only hook/release changes; add the `/handoff` model rubric.

**Push:** per Mike's push-division convention (GitHub = Claude's side for aria-knowledge), offer to push + tag `cowork-v1.4.0` + GH release at the end — but only on explicit confirmation (per-push-confirm).
