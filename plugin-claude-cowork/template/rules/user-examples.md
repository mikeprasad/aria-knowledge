# Your Per-Rule Examples

**Last updated:** (update when you edit this file)

This file is for **your** project-specific before/after examples illustrating the rules in `working-rules.md`. ARIA ships and maintains the rule definitions; this file is yours to own. ARIA never overwrites it, never diffs it, never touches it on `/aria-setup` updates.

## Why Examples Are User-Specific

Examples earn their illustrative value by being grounded in *your* context — meeting notes, doc references, conversations, project conventions that are real to you. A "universal Rule N example" tends to drift back toward being part of the rule itself, OR a separate canonical pattern (in `retrospect-patterns.md`).

That's why ARIA ships zero example content. The plugin defines the format and the discovery mechanism; you author examples grounded in your own work.

## How `/rules` Finds Your Examples

When you run `/rules N`, the skill reads this file and returns any example whose heading matches `## Rule N`. No forward-link maintenance in `working-rules.md` needed — discovery is automatic.

## Format

Use a `## Rule N` heading per example. Required sub-sections: `### Before` and `### After`. Everything else is optional — use whatever helps the example land.

**Required:**

- `## Rule N — {short title}` heading
- `### Before` with text or scenario showing the failure mode
- `### After` with text or scenario showing the rule applied

**Optional (use as helpful, omit otherwise):**

- `**Calibrated against:** {project / meeting / date / incident}` — what makes this example real for you
- `### Why this example` — 1–2 sentences naming the load-bearing decision
- Inline citations to docs, conversations, decisions

## When to Add an Example

When you've made a decision, sent a message, or finalized a deliverable that vividly illustrates one of the rules — and future-you would benefit from seeing the before/after side-by-side. Don't force examples for every rule. Let them emerge from real cases.

-----

## Cowork-flavored starter examples

*(replace these with your own real examples, or delete them once you've added enough above)*

<!--

## Rule 16 — Clear naming

### Before
A doc titled `meeting-notes.md` in a folder of 30 other `meeting-notes.md`-style files. Searching for the Q3 stakeholder prep doc requires opening each one to check the date.

### After
A doc titled `meeting-notes/2026-09-q3-stakeholder-prep.md` — date + topic + role in one glance. Searchable, sortable, self-documenting.

**Calibrated against:** {your project name} — what made this rename worth the friction.


## Rule 13 — Simplest solution wins

### Before
Drafting a 12-slide deck for a weekly status update because "leadership likes decks." Spent 90 minutes building, 5 minutes presenting.

### After
A one-paragraph brief in the team channel: status, blockers, next milestone. 8 minutes to write, same information delivered, async-friendly. Deck reserved for quarterly reviews where the format earns its weight.

**Calibrated against:** {your project name} — the moment you noticed the deck-to-substance ratio was wrong.


## Rule 22 — Change decision framework

### Before
"Should we use Slack channel #project-x or set up a dedicated email thread for client comms?" Decided in passing during a hallway conversation; both got used inconsistently for 6 weeks; client missed two updates because they were in the wrong surface.

### After
Walked through the 7-step framework explicitly: (1) change = single source of truth for client comms, (2) intake = client preference + team availability + audit trail need, (3) criteria = searchable, async, traceable, (4) options = Slack channel / email thread / shared doc, (5) ranked: email thread wins on audit + searchable + client-preferred, (6) validated by asking client directly, (7) executed in 10 minutes with a kickoff email + Slack-channel-as-internal-only rule.

**Calibrated against:** {your project name, date}.

-->
