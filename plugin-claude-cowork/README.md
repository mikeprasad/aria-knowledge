# aria-cowork

Knowledge management for Claude Cowork — capture, organize, and apply durable knowledge across your work, available in any project workspace.

Companion plugin to [aria-knowledge](https://github.com/mikeprasad/aria-knowledge) for Claude Code. Both plugins share the same `~/Projects/knowledge/` folder, so insights flow between conversational work (Cowork) and engineering work (Code).

> **Using both plugins?** When aria-cowork and aria-knowledge are loaded in the same session (most common in Claude Desktop), bare slash commands (`/handoff`, `/wrapup`, `/extract`, etc.) resolve to **aria-knowledge** as the canonical Code-side owner. To use the Cowork variant of any skill, type the namespaced form: `/aria-cowork:handoff`, `/aria-cowork:wrapup`, etc. Natural-language triggers (e.g., "hand it off", "wrap up", "extract knowledge") still route to the Cowork variant in Cowork sessions. Each colliding skill carries a Runtime Gate that surfaces a notification if invoked from the wrong runtime. See [ADR 094](https://github.com/mikeprasad/knowledge/blob/main/projects/aria/decisions/094-bare-slash-canonical-owner-and-dual-runtime-gate.md) for the full design.

**Status**: **v1.0.0 — first MCP-consuming release + v1.0 stable-contract claim.** Knowledge folder is reachable from every Cowork session regardless of which project folder is the active workspace. **26 skills** (24 distinct + 2 aliases) covering setup, capture, lookup, audit, retrospective, pre-mortem, end-of-session handoff, **plus 6 new Cowork-native skills** (5 cross-tool MCP-consuming + 1 cowork-only audit-cadence checker). Coordinated release pair with aria-knowledge v2.18.0 — 5 bidirectional skills shared per ADR-014 schema-source-of-truth. v1.0 commits to skill manifest shape, knowledge folder schema, and cross-plugin parity per ADR-006 — see CHANGELOG v1.0.0 entry for the full stability claim. Phase 1 public-repo release scheduled separately.

---

## What's new in v1.0.0

First MCP-consuming release + v1.0 stable-contract claim. Originally built as v0.4.0; bumped to v1.0.0 mid-build per ADR-006's v1.0 stability criteria (capability triggers landed). 6 new Cowork-native skills shipped + `.mcp.json` + `CONNECTORS.md`. Coordinated release pair with aria-knowledge v2.18.0.

### 6 new Cowork-native skills

**5 bidirectional skills** (also ship in aria-knowledge v2.18.0; byte-faithful imports per ADR-013):

- **`/clip-thread`** — Capture a chat or email thread from a connected `~~chat` or `~~email` MCP (Slack, Teams, Gmail, MS365). Source-type detection by URL pattern; per-message structure + reactions + attachment notes; user-fill reaction section.
- **`/extract-doc`** — Decompose a single Notion / Confluence / Google Doc / Box / Egnyte page (via `~~docs` MCP) into N intake-backlog entries for audit routing. Differs from `/intake doc` which captures one doc as one artifact.
- **`/meeting-notes`** — Fold a meeting transcript into structured intake (participants / topics / action items / decisions / open questions + raw transcript). Source can be a `~~docs` MCP page OR pasted transcript text (Granola, hand-typed notes, transcript exports) — the one skill with a paste fallback when no MCP is connected.
- **`/digest`** — Cross-tool weekly rollup synthesizing what's pending / shipped / blocked across `~~chat` + `~~email` + `~~project tracker` + `~~docs`. Probes all 4 categories and degrades gracefully when partial connection.
- **`/sync-decisions`** — Mirror approved decisions from `decisions/` out to a connected `~~docs` MCP destination. **First WRITE-side ARIA skill** — embeds Rule 22 advisory preamble per ADR-016 with explicit per-decision go-gate. Logs every sync to `logs/sync-decisions.md`.

**1 cowork-only skill** (no aria-knowledge analog — aria-knowledge users get this coverage via SessionStart hook):

- **`/daily-audit`** — First-message audit-cadence substitute. Reads aria-config.md for `last_audit_date` + `last_config_audit_date` + thresholds + stale-ideas count; reports status; recommends `/audit-knowledge` or `/audit-config` invocation if overdue. Recommend-only — never auto-invokes. No MCP dependency.

### `.mcp.json` + `CONNECTORS.md` foundation

- **`.mcp.json`** — declares 12 MCP servers across 4 categories (slack, ms365, gmail-placeholder, linear, asana, atlassian, monday, clickup, notion, box, egnyte, google docs-placeholder). Byte-identical to aria-knowledge v2.18.0's manifest.
- **`CONNECTORS.md`** — documents the `~~category` marker convention per Anthropic's `cowork-plugin-customizer` guidance. 4 categories (chat / email / project tracker / docs). Per-skill MCP-usage table including cowork-only daily-audit row.

### Cross-plugin architecture (2 new ADRs)

- **ADR-015** — Capability-probe pattern (prose-only, no API). Locks the `~~category` probe convention verified against productivity plugin reference: Claude's runtime tool list IS the probe; SKILL.md handles missing-MCP via explicit fallback prose.
- **ADR-016** — Rule 22 advisory preamble for external-write skills. Locks the 4-step preamble + explicit `Ready to write? (yes / no / edit)` go-gate that all WRITE-side skills MUST embed. Applies to `/sync-decisions` in v0.4.0.

Both ADRs include **Stability and revision triggers** sections acknowledging that the patterns derive from Anthropic-published Cowork plugins as of 2026-05-18 and may revise as future Anthropic releases ship new capability surfaces.

### Coordinated release pairing

- **aria-knowledge v2.18.0** (released 2026-05-18) — companion release. Ships the 5 bidirectional skills first per D2 schema-source-of-truth. v0.4.0 imports the templates byte-faithfully with only Step 0 config resolution + frontmatter shape + skill-name phrasing diverging per ADR-013.

---

## What's new in v0.3.0

This release brings cowork to substantive feature parity with aria-knowledge through 8 stages of work:

### New skills (5 planned-but-missing + 3 net-new = 8 skill bodies + 2 aliases)

**Planned-but-missing skills** (originally listed in OVERVIEW.md's 14-skill manifest but unshipped through v0.2.5):

- **`/extract`** — Pure port. Capture insights, decisions, feedback, project context, references, and ideas from the current conversation. Operates on Claude's working-memory recall (no transcript jsonl read needed).
- **`/snapshot`** — Highest cowork-divergence. Save a snapshot of the current Cowork conversation via 3-path source acquisition: Cowork transcript MCP (if exposed) → user-paste → Claude-recall structured fallback. Schema-identical output to aria-knowledge's `/snapshot` regardless of source path.
- **`/wrapup`** — Light cowork-modification. End-of-session handoff with summary + PROGRESS.md / CLAUDE.md / memory updates. Git step generates a copy-paste commit message for the user to run (cowork has no shell access).
- **`/audit-knowledge`** (+ alias **`/knowledge-audit`**) — Largest cowork-modified skill (~926 lines). Reviews intake backlogs, routes ideas via Accept submenu, archives cleared content per audit-cohort conventions, rebuilds index. Memory/plans scan steps are aria-knowledge-only (cowork can't reach `~/.claude/projects/`); archive output is schema-identical so cross-plugin audits merge cleanly.
- **`/audit-config`** (+ alias **`/config-audit`**) — Cowork-modified. Checks knowledge folder for drift, broken references, version-stamp ripple, adoption-state cascade, missing config fields. CONFIG.md replaces `bin/config.sh` as field-enumeration source; cowork-scoped surfaces + cowork-relevant phrase library; Step 5a tracked-artifact staleness skipped per ADR-005.

**Net-new skills** (added to aria-knowledge after cowork's original spec, ported in v0.3.0):

- **`/prospect`** — Forward-looking pre-mortem on plans before execution. Per-step risk enforcement, Evidence-Sourcing Pass, action verdicts. Step 11 CODEMAP/STITCH skipped per ADR-005; Step 0.5 Active Knowledge Surfacing ports skill-side with `/tmp/` ledger → in-memory dedup fallback.
- **`/retrospect`** — Per-fix-validated retrospective on shipped work. 6 scopes: session + decision work natively in cowork; commit/range/PR/release/deployment use user-paste fallback for git output (cowork has no shell access). Once paste is in context, downstream analysis is identical to aria-knowledge.
- **`/handoff`** — Express end-of-session handoff with three modes: default (combined-go review), `auto` (silent apply), and `brief` (copy/paste coworker prose). Brief mode is parity with aria-knowledge v2.17.0 — first cowork-originated feature ported into aria-knowledge first (see ADR-014 bidirectional feature flow).

### New mode on existing skill

- **`/intake doc <url-or-title>`** — Captures a single doc with structured 5-section body (claims / worth keeping / contested / action / reaction) under `intake/docs/`. Parity with aria-knowledge v2.17.0 doc mode.

### Knowledge folder schema parity (v2.14.0 → v2.16.0 catch-up)

- **`aliases.md`** user-owned template (v2.16.0) — maps freeform query tokens to canonical tags. Cowork ships with 5 commented-out cowork-flavored seed aliases (meeting, brief, doc, action, customer).
- **`semantic-hints:`** frontmatter convention (v2.16.0) — free-form descriptive phrases on knowledge files for substring-matched discovery via `/context` + `/ask`.
- **Archive-cohort conventions** (v2.15.1 + v2.15.2) — `archive/audit-{date}/MANIFEST.md` shape, disposition-attribution frontmatter taxonomy (5 fields), verify-no-loss check, user-override clause, same-day collision handling. Schema-identical across plugins; same-day audits from both plugins merge into one cohort.
- **`template/rules/working-rules.md`** synced to aria-knowledge v2.14.3 baseline — Behavioral Foundation preamble (v2.14.0), Rule 20 dual-form reframe (v2.14.0), 7 rule body refinements (Rules 4, 8, 16, 19, 23, 27, 29 per v2.14.3).
- **`user-examples.md`** user-owned template — illustration-only tier with 3 cowork-flavored starter examples (Rules 16, 13, 22). `/rules N` auto-discovers matching `## Rule N` examples.
- **`TEMPLATE-PARITY.md`** registry — tracks shared template files between plugins per ADR-007.

### Cross-plugin architecture (3 new + 1 amended ADR)

- **ADR-005 Section 5b** — Documents the v0.3.0 ports (planned-but-missing + net-new categories).
- **ADR-013** — Cowork-modified skills produce schema-identical knowledge-folder outputs (locks the D3 principle from v0.3.0 design).
- **ADR-014** — Bidirectional feature flow precedent. Features may originate in either plugin; aria-knowledge remains schema source-of-truth.

### Cowork-only enhancements (not in aria-knowledge)

- **`/aria-setup` Step 1b Access Probe** — Read+write+delete round-trip validates persistent-grant + folder access before scaffold begins. Catches read-only grants, revoked permissions, FS errors that simpler read-checks would miss. Productized from the 2026-04-30 probe arc.
- **`/aria-setup` Step 4c Advanced Options + Step 5b Self-Validation Audit** — Surface `active_knowledge_surfacing` field with [NEW]-detection observability; audit aria-config.md against CONFIG.md known-fields list after write.

### Bidirectional flow

v0.3.0's `/handoff brief` and `/intake doc` modes originated in cowork's design discussion as B2 + B5 candidates. They shipped in aria-knowledge v2.17.0 first per schema-source-of-truth, then cowork v0.3.0 imported the templates byte-faithfully. First instance of cowork→aria-knowledge feature flow. Documented in ADR-014.

---

## What aria-cowork does

- **Capture** — clip URLs, snippets, and notes into a structured knowledge folder
- **Organize** — tag, index, and audit captured material for findability
- **Apply** — surface relevant decisions, approaches, and rules when you start new work
- **Govern** — track which audits are due, where backlogs are growing, what rules apply

aria-cowork operates on a knowledge folder that's persistently granted to Cowork (typically `~/Projects/knowledge/`). It reads and writes the same files aria-knowledge writes from Code, so a decision captured in one mode is available in the other.

## Install (in Cowork)

> **Note (2026-05-24):** This plugin is now developed in `mikeprasad/aria-knowledge` under `plugin-claude-cowork/`. Clone that repo and build from source, or use a pre-built `.plugin` artifact from the [aria-knowledge releases page](https://github.com/mikeprasad/aria-knowledge/releases).

The plugin uses a **default-path convention**: the knowledge folder is expected at `~/Projects/knowledge/`. Users with knowledge folders elsewhere can override via `aria-config.md` (the setup skill will prompt for the path on first run).

### 1. Install the plugin

```bash
# Clone from the consolidated repo
git clone https://github.com/mikeprasad/aria-knowledge
cd aria-knowledge/plugin-claude-cowork
./release.sh  # builds aria-cowork-<version>.plugin
```

Then drag the generated `.plugin` file onto a Cowork conversation, OR install via Cowork's Settings → Plugins → Install from file.

### 2. Run setup in any Cowork conversation

In any Cowork session — your knowledge folder doesn't need to be the workspace folder — invoke setup using **natural language**:

> set up aria-cowork
> *or*
> configure my knowledge folder
> *or*
> aria-cowork setup

aria-cowork uses Anthropic's canonical Cowork pattern — skills auto-invoke when you describe what you want to do, rather than via slash commands. The skill's `description` field contains trigger phrases Claude matches against your message.

Setup will:

1. Try the default knowledge folder location (`~/Projects/knowledge/`). If it doesn't exist, prompt you for an alternate absolute path.
2. Check whether the folder is reachable from the current Cowork session.
3. **If reachable**: scaffold any missing structure, write `aria-config.md`, and confirm.
4. **If unreachable** (folder isn't granted to Cowork): walk you through adding the folder path to Cowork's desktop config so aria-cowork can reach it from every Cowork session:

   ```json
   // ~/Library/Application Support/Claude/claude_desktop_config.json (macOS)
   {
     "additionalDirectories": [
       "/Users/yourname/Projects/knowledge"
     ]
   }
   ```

   (Exact key may differ — `additionalDirectories`, `additional_directories`, or similar. Check your existing config or Cowork's docs.) Save, restart Cowork, then re-run `/aria-setup`.

**Alternative for one-off testing**: run `/add-dir <knowledge-folder-path>` in your Cowork conversation to grant per-session access without editing the desktop config. Persistent grant is recommended for normal use — it works across all your Cowork projects without re-granting per session.

## Install (in Claude Code — companion plugin aria-knowledge)

aria-cowork ships separately from aria-knowledge. To get the full ARIA family across both surfaces:

```bash
# In Code, install aria-knowledge
claude plugin marketplace add mikeprasad/aria-knowledge
claude plugin install aria-knowledge@aria-knowledge
```

Both plugins read the same `aria-config.md` at the knowledge folder root. (aria-knowledge v2.13.0+ reads the new path with two-version legacy fallback for existing users.)

## The 20 v0.3.0 skills

**Invocation note**: aria-cowork skills auto-invoke when you describe what you want to do. There are no slash commands — Cowork's canonical pattern (matching Anthropic's published plugins) is natural-language triggering via skill descriptions. The names below are the skill identifiers; trigger them by saying things like "save this to aria-cowork", "what do we know about X", "show aria-cowork stats", etc.

### Pre-v0.3.0 skills (carried forward, with v0.3.0 enhancements)

| Skill | What it does |
|-------|--------------|
| `aria-setup` | First-run scaffold: verifies knowledge folder reachability, guides desktop-config grant if needed, writes `aria-config.md`. **v0.3.0** adds Step 1b access probe, Step 4c Advanced Options bundle with `[NEW]`-detection, Step 5b Self-Validation Audit. |
| `help` | List available commands and quick reference (updated for v0.3.0 skill set) |
| `clip` | Save a URL or snippet to `intake/clippings/` |
| `intake` | Bulk import files, URLs, or directories into the knowledge folder. **v0.3.0** adds `intake doc <url-or-title>` mode for doc-anchored capture with 5-section body. |
| `ask` | Research a question, save the answer to the appropriate category. **v0.3.0** adds alias resolution + semantic-hint matching at Step 2. |
| `context` | Load relevant knowledge by topic. **v0.3.0** adds Step 2.5 alias resolution + semantic-hint substring matching + `[hint: ...]` annotation + no-match alias display. |
| `index` | Rebuild the tag index. **v0.3.0** adds semantic-hints parsing + Step 2b alias validation + Known Tags `[aliases: ...]` annotations + Semantic Hints Index section. |
| `stats` | Knowledge base health. **v0.3.0** adds semantic-hints coverage line. |
| `rules` | Quick lookup of working rules. **v0.3.0** adds `/rules N` matching-examples extension (auto-discovers `## Rule N` examples from `user-examples.md`). |
| `backlog` | View and manage pending intake. **v0.3.0** `backlog clear` adopts archive-then-remove pattern with user-override clause. |

### New in v0.3.0 (10 skill bodies, including 2 aliases)

| Skill | What it does |
|-------|--------------|
| **`extract`** | Capture insights, decisions, feedback, project context, references, and ideas from the current conversation |
| **`snapshot`** | Save a snapshot of the current Cowork conversation. 3-path source acquisition: Cowork transcript MCP → user-paste → Claude-recall fallback |
| **`wrapup`** | Interactive end-of-session handoff: review work, update PROGRESS/CLAUDE/memory, generate commit message, prompt /extract |
| **`audit-knowledge`** | Review intake backlogs, route ideas via Accept submenu, archive cleared content per audit-cohort conventions, rebuild index |
| **`knowledge-audit`** | Alias for `audit-knowledge` (alternative phrasing) |
| **`audit-config`** | Check knowledge folder for drift, broken references, version-stamp ripple, adoption-state cascade, missing config fields |
| **`config-audit`** | Alias for `audit-config` (alternative phrasing) |
| **`prospect`** | Forward-looking pre-mortem on plans before execution. Per-step risk enforcement, Evidence-Sourcing Pass, action verdicts |
| **`retrospect`** | Retrospective on shipped work. 6 scopes (session + decision native; commit/range/PR/release/deployment use user-paste fallback) |
| **`handoff`** | Express handoff with three modes: combined-go default, silent `auto`, copy/paste coworker `brief` |

## How it works with aria-knowledge

Both plugins read and write `<knowledge_folder>/aria-config.md` (the canonical config) and operate on the same folder structure (`intake/`, `decisions/`, `approaches/`, `rules/`, etc.). Schema is additive-only — neither plugin removes fields the other writes.

aria-cowork's path-discovery mechanism (Cowork userConfig) is Cowork-only; aria-knowledge in Code reads `aria-config.md` from the absolute path directly (with legacy `~/.claude/aria-knowledge.local.md` fallback through aria-knowledge v2.14.0).

## Principles transfer, enforcement doesn't

plugin-claude-cowork shares the working-rules + 7-step change-decision framework with its sibling port [plugin-claude-code](https://github.com/mikeprasad/aria-knowledge/tree/main/plugin-claude-code) in the same repo. Both ports read from the same `~/Projects/knowledge/` folder and write to the same canonical config. **The principles transfer cleanly**: *Don't assume — surface tradeoffs*, *Simplest solution wins*, *Touch only what you must*, *Define success criteria upfront, loop until verified* are good discipline regardless of which Claude surface you're working in.

**What doesn't transfer is the enforcement layer.** aria-knowledge runs in Claude Code, which has PreToolUse / PostToolUse hooks — Rule 22's change-decision framework fires automatically on every Edit/Write, with required-output format making compliance visible at the point of action. aria-cowork runs in Claude Cowork, which is skills-only: there are no hook events, no automatic enforcement. The same rules apply, but you (or the model, prompted by `/rules` lookups and session context) carry the discipline manually.

This is intentional, not incidental. From [Yanli Liu's "The 4 Lines Every CLAUDE.md Needs"](https://levelup.gitconnected.com/the-4-lines-every-claude-md-needs-2717a46866f6) (the article that informed aria-knowledge v2.14.0's Behavioral Foundation preamble):

> *"These guidelines were written for Claude Code specifically. Cursor, Copilot, and Codex have overlapping but different failure modes. The principles transfer. 'Don't assume' is good advice regardless of which agent you're using. But the specific phrasing and how much the agent responds to it will vary by tool."*

aria-cowork inherits the principles. It doesn't inherit Layer 2 enforcement — that's a Code-only feature surface (per `template/rules/enforcement-mechanisms.md`'s 5-tier ladder; aria-cowork operates at Layers 1 + 3 only, never Layer 2). If you switch between Code and Cowork sessions on the same project, expect the rules to apply consistently and the **enforcement strength to differ**: Code's hooks make compliance visible per-tool-call; Cowork's skills make compliance available per-`/rules`-lookup or per-session-prompt.

The asymmetry is by design. Layer-2 enforcement requires a hook surface; Cowork doesn't expose one. Should that change in a future Cowork release, the framing here becomes the guide for porting Code's hook-enforced rules (22, 25, 26) into Cowork — the rule bodies are already shared via the template.

## What's deferred to v0.4.0+

The following are NOT in v0.3.0 — planned for future releases:

- **MCP integrations** (Slack, Notion, Linear, Gmail, etc.) — `.mcp.json` + `CONNECTORS.md` customization guide for orgs adopting aria-cowork
- **Cowork-native skills**: `/digest` (cross-tool weekly rollup), `/clip-thread` (Slack/Teams/email thread capture), `/extract-doc` (Notion/Google Doc/Confluence insight extraction), `/sync-decisions` (mirror approved decisions out to team docs), `/meeting-notes` (fold meeting transcript into intake), `/daily-audit` (first-message audit substitute)
- **Cowork transcript MCP integration** — when/if Cowork exposes a current-session transcript surface, `/snapshot` Path 1 (MCP-verbatim) will become the primary source path

## Spec and design docs

The full spec, ADRs, and validation history live in the knowledge folder itself, under `~/Projects/knowledge/projects/aria-cowork/`:

- `OVERVIEW.md` — canonical spec
- `decisions/001-014-*.md` — 14 architectural decisions (as of v0.3.0)
- `VALIDATION.md` — Cowork environment validation results

## License

CC BY-NC-SA 4.0. See [LICENSE](LICENSE).
