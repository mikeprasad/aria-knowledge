---
name: aria-probe
description: >
  Run a 4-step validation probe for the aria-cowork spec. Tests whether this Cowork plugin can verify cwd, write to the user-attached knowledge folder, read a file pre-placed by aria-knowledge in Code, and capture or fall back gracefully on the transcript surface. Outputs structured results both to the conversation and to a probe-results file. Use when validating the aria-cowork spec before Phase 1 build. Triggers: "/aria-probe", "run aria probe", "validate aria-cowork", "test cowork filesystem".
---

# aria-probe

You are running a **validation probe** for the aria-cowork plugin spec. Your goal is to determine whether this Cowork environment supports the bidirectional knowledge folder pattern that aria-cowork's design depends on.

You will perform **4 probes** in sequence. For each probe, output a clear PASS/FAIL/INCONCLUSIVE verdict to the conversation AND append a structured result line to `probe-results-<timestamp>.md` at the cwd root.

## Setup

Before the first probe, ensure both expected folders are attached. Ask the user:

> This probe needs **two folder attaches** for full coverage:
> 1. **Required:** your knowledge folder (e.g. `~/Projects/knowledge/`) — used by probes 11, 2, 3, 7
> 2. **Optional but recommended:** `~/.claude/` — used by probe 12 (tests whether Cowork can read the legacy aria-knowledge.local.md config)
>
> If both are attached via Cowork's folder picker, confirm the absolute paths. If only the knowledge folder is attached, probes 11/2/3/7 will run but probe 12 will be skipped. If neither is attached, attach at least the knowledge folder via Cowork's folder picker, then re-run /aria-probe.

If the user confirms at least the knowledge folder is attached, proceed. Probe 12 has its own gate that handles the absent-`~/.claude/` case gracefully.

Once attached, create the results file at the cwd root with this header:

```markdown
# aria-cowork validation probe results

**Date:** <ISO 8601 timestamp>
**Cowork version:** <ask user; if not known, write "unknown">
**Attached folder:** <absolute path the user confirmed>

---

## Results
```

---

## Probe 11 — Folder attachment / cwd resolution

**Question:** Does cwd resolve to the user-attached folder?

**Action:**
1. Output the current working directory.
2. Compare to the path the user confirmed.

**Verdict:**
- **PASS** — cwd matches the user-confirmed attached folder.
- **FAIL** — cwd is different (e.g. resolves to a sandbox path or empty).
- **INCONCLUSIVE** — cwd cannot be determined.

**Append to results file:**
```markdown
### Probe 11 — Folder attachment
- cwd resolved to: `<actual cwd>`
- user-confirmed attach: `<user path>`
- **Verdict:** PASS | FAIL | INCONCLUSIVE
```

If FAIL, stop here and report. The remaining probes depend on this one.

---

## Probe 2 — Filesystem write to attached folder

**Question:** Can this plugin write a new file under the user-attached folder?

**Action:**
1. Generate a timestamp: `YYYY-MM-DDTHH-MM-SS`.
2. Create a directory `probe-test/` at cwd root if it doesn't exist.
3. Write the following file at `probe-test/cowork-write-test-<timestamp>.md`:

```markdown
---
written_by: aria-probe (running in Cowork)
written_at: <timestamp>
purpose: validation probe 2 — confirm Cowork plugin can write user folder
---

This file was written by aria-probe in Cowork to verify probe 2 of the aria-cowork validation gate.

If aria-knowledge (in Code) can read this file, probes 2 and 3 of the validation gate pass.
```

4. Verify the file exists by reading it back.

**Verdict:**
- **PASS** — file was created and read-back content matches what was written.
- **FAIL** — write was rejected, or read-back failed, or content didn't match.
- **INCONCLUSIVE** — error during the operation that doesn't clearly indicate write capability.

**Append to results file:**
```markdown
### Probe 2 — Filesystem write
- write target: `probe-test/cowork-write-test-<timestamp>.md`
- write succeeded: yes | no
- read-back matches: yes | no
- error (if any): `<error text>`
- **Verdict:** PASS | FAIL | INCONCLUSIVE
```

---

## Probe 3 — Cross-surface read

**Question:** Can this plugin read a file that aria-knowledge (in Code) wrote earlier?

**Setup pre-condition:** A fixture file should already exist at `probe-test/code-write-test.md`. (If not, the user is instructed via README.md to place it first.)

**Action:**
1. Check whether `probe-test/code-write-test.md` exists.
2. If it exists, read it.
3. Validate that the content has the expected fixture marker (the fixture file contains the literal string `FIXTURE_MARKER:ARIA_PROBE_3_CODE_SIDE_WROTE_THIS`).

**Verdict:**
- **PASS** — file was found, read, and contained the expected marker.
- **FAIL** — file was not found, or didn't contain the expected marker.
- **INCONCLUSIVE** — read attempt errored in a way that doesn't indicate file absence (e.g. permission error mid-read).

**Append to results file:**
```markdown
### Probe 3 — Cross-surface read
- target: `probe-test/code-write-test.md`
- file found: yes | no
- expected marker present: yes | no
- file contents (first 200 chars): `<excerpt>`
- error (if any): `<error text>`
- **Verdict:** PASS | FAIL | INCONCLUSIVE
```

---

## Probe 7 — Transcript capture surface

**Question:** Can this plugin capture the current conversation transcript, or must it fall back to user-paste?

**Action:**
1. Attempt to read the conversation history. Cowork may expose this via:
   - A built-in tool (try invoking it if you know one)
   - A file in the Cowork app data directory (try common paths if any are documented)
   - No mechanism (then fall back to user-paste)
2. If automated capture works, write a snippet of the conversation to `probe-test/transcript-capture-<timestamp>.md`.
3. If no automated capture, prompt the user: "Cowork does not appear to expose a transcript API. Paste the relevant part of this conversation here, or skip this probe."

**Verdict:**
- **PASS (auto)** — transcript captured automatically.
- **PASS (paste)** — user-paste fallback works (acceptable degraded mode).
- **FAIL** — neither automated nor paste-fallback succeeded.
- **SKIPPED** — user chose to skip.

**Append to results file:**
```markdown
### Probe 7 — Transcript capture
- automated capture attempted: yes | no
- automated capture worked: yes | no
- mechanism (if any): `<description>`
- fallback used: paste | skip | none
- **Verdict:** PASS (auto) | PASS (paste) | FAIL | SKIPPED
```

---

---

## Probe 12 — Legacy aria-knowledge config readability *(v0.2.0 addition)*

**Question:** If the user attaches `~/.claude/` as an additional workspace folder, can this Cowork plugin read `~/.claude/aria-knowledge.local.md` (the existing aria-knowledge config from Code)?

**Why this matters:** if YES, aria-cowork doesn't need to relocate config to `<knowledge_folder>/aria-config.md` — it can read the existing aria-knowledge config directly, retiring the planned aria-knowledge v2.13.0 migration entirely. ADR-002 simplifies. If NO, the current relocation plan stands.

**Action:**

1. **Detect whether `~/.claude/` is attached.** Scan `/sessions/*/mnt/` for a folder whose name matches `.claude` OR whose contents look like a Claude Code config dir (presence of `aria-knowledge.local.md`, `settings.json`, or `projects/`).
2. **If `~/.claude/` is NOT attached:** mark probe 12 as `NOT_TESTED` and report: *"`~/.claude/` not attached to this session. Attach it and re-run /aria-probe to test probe 12. (Optional — probe 12 only affects ADR-002's config-relocation decision.)"*
3. **If `~/.claude/` IS attached:**
   a. Compute the absolute path equivalent: `/Users/<user>/.claude/aria-knowledge.local.md` (use `$HOME` resolution if the user shell is reachable, or ask the user to confirm their home directory absolute path).
   b. Try reading the file via BOTH:
      - The sandbox-mount path (`<sandbox-mount-of-.claude>/aria-knowledge.local.md`)
      - The absolute path (`/Users/<user>/.claude/aria-knowledge.local.md`)
   c. Report which paths worked.
   d. If the read succeeded, validate that the file contains a `knowledge_folder:` field in YAML frontmatter (proves it's a real aria-knowledge config, not an unrelated file at the same path).
4. **Edge case — file doesn't exist:** if `~/.claude/` IS attached but `aria-knowledge.local.md` is missing (user hasn't set up aria-knowledge in Code), mark `CONFIG_NOT_FOUND` and report: *"`~/.claude/` is reachable but no `aria-knowledge.local.md` found there. This is normal if you've never run aria-knowledge's /setup in Code. Probe 12 can't determine readability without the file."*

**Verdict:**
- **PASS** — `~/.claude/` was attached; `aria-knowledge.local.md` was read successfully via at least one path; content contains `knowledge_folder:` field. Cowork can read existing aria-knowledge config when granted access.
- **FAIL** — `~/.claude/` was attached but reads errored (permission denied, sandbox blocked, etc.). Indicates Cowork has additional restrictions beyond folder attach.
- **NOT_TESTED** — `~/.claude/` not attached. User should attach and re-run to determine.
- **CONFIG_NOT_FOUND** — `~/.claude/` attached but the legacy config file doesn't exist there. Inconclusive for ADR-002 decision; doesn't say whether Cowork could read it if it existed.

**Append to results file:**

```markdown
### Probe 12 — Legacy aria-knowledge config readability (v0.2.0)
- ~/.claude/ attached: yes | no
- sandbox-mount path tried: `<path-or-N/A>`
- absolute path tried: `/Users/<user>/.claude/aria-knowledge.local.md`
- read via sandbox-mount: succeeded | failed | N/A — `<error if any>`
- read via absolute path: succeeded | failed | N/A — `<error if any>`
- file contains knowledge_folder field: yes | no | N/A
- file content (first 200 chars, redacted of sensitive fields): `<excerpt>`
- **Verdict:** PASS | FAIL | NOT_TESTED | CONFIG_NOT_FOUND
- **Implication for ADR-002:** [if PASS] config relocation MAY be unnecessary; legacy config is reachable. [if FAIL] folder attach is insufficient; relocation plan stands. [if NOT_TESTED] attach `~/.claude/` and re-run. [if CONFIG_NOT_FOUND] inconclusive.
```

---

## Final summary

After all 4 (or 5, with probe 12) probes, append to the results file:

```markdown
---

## Summary

| Probe | Verdict |
|-------|---------|
| 11 — Folder attachment | <verdict> |
| 2 — Filesystem write | <verdict> |
| 3 — Cross-surface read | <verdict> |
| 7 — Transcript capture | <verdict> |
| 12 — Legacy config readability (v0.2.0) | <verdict> |

**Hard-fail probes (2, 3, 11):** <all PASS or list failures>

**Recommendation for aria-cowork build:**
- If all hard-fail probes PASS: GREEN — proceed to (or continue) Phase 1.
- If any hard-fail probe FAILS: RED — return to spec; consult VALIDATION.md fail consequences.
- If hard-fail probes are mixed PASS/INCONCLUSIVE: YELLOW — investigate the inconclusive probe before committing.

**Probe 12 implications for ADR-002 (config location):**
- Probe 12 PASS → aria-cowork v0.1.1+ MAY read existing `~/.claude/aria-knowledge.local.md` directly when `~/.claude/` is attached. Retires the planned aria-knowledge v2.13.0 migration. ADR-002 needs amendment to "config stays at legacy path; aria-cowork reads via two-folder attach." Trade-off: more friction at first /setup (two folder attaches) but no aria-knowledge release dependency.
- Probe 12 FAIL → current ADR-002 stands. aria-cowork relocates config to `<knowledge_folder>/aria-config.md`; aria-knowledge v2.13.0 migrates with read-both/write-new fallback.
- Probe 12 NOT_TESTED → re-run with `~/.claude/` attached to settle the decision. aria-cowork v0.1.0 ships with current spec until then.
- Probe 12 CONFIG_NOT_FOUND → reachability is unverified. Either set up aria-knowledge in Code first (so the file exists) and re-run, or ship with current spec and revisit later.
```

Then output the same summary to the conversation so the user sees it immediately, and tell them:

> Probe results saved at `probe-test/probe-results-<timestamp>.md`. Share this file (or a copy of the conversation summary) when you next ask Claude to evaluate aria-cowork's build readiness.

---

## Notes for the agent

- Use Cowork's native file Read/Write semantics. Do NOT attempt to use a Filesystem MCP connector.
- Do NOT modify any files outside `probe-test/` directory under cwd.
- Do NOT delete any existing files.
- If any probe encounters an unexpected error, mark it INCONCLUSIVE rather than guessing PASS/FAIL.
- Keep the conversation output concise — Mike will read the results file for full detail.
