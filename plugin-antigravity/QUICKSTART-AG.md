# ARIA Quickstart — Antigravity Edition

Get ARIA running in 5 minutes on your Google Antigravity (IDE or CLI) setup, and learn the rhythm that makes persistent knowledge invaluable.

---

## 🚀 5-Minute Setup

### 1. Install the Plugin

If you don't have a published marketplace entry, copy `plugin-antigravity/` directly into Antigravity's plugin discovery directory:

```sh
# Global install (active across all workspaces):
cp -R plugin-antigravity ~/.gemini/config/plugins/aria-knowledge
```

Restart your Antigravity IDE/CLI. Open the **Customizations** panel to verify that `aria-knowledge` is loaded and active.

### 2. Run `/setup`

Launch a terminal session in your project workspace and run:

```sh
/setup
```

The setup wizard will walk you through:
- **Knowledge Folder Location**: Typically `~/Projects/knowledge/` (a folder you'll commit to your own private git repo, separate from the project codebases).
- **Antigravity Workspace Automation**: Setup will automatically detect your active workspace and:
  1. Copy **10 thin-shim workflows** to `.agents/workflows/` to enable native slash commands.
  2. Copy **aria-rules.md** to `.agents/rules/aria-rules.md` to activate native Always-On rule enforcement.
- **Audit Cadences & Advanced Options**: Tune audit cadences, ticketing system integrations, and active knowledge surfacing.

### 3. Build the Initial Index

Run:

```sh
/index
```

This scans your knowledge folder, builds `index.md` with the tag index, and flags any untagged files. Re-run whenever you add or move knowledge files.

### 4. Confirm the Connection

Run:

```sh
/stats
```

This displays your knowledge base health: file counts, intake backlog status, audit dates, and index health. If `/stats` outputs a clean table, ARIA is fully configured!

---

## 🔄 Antigravity Workspace Integration

The Antigravity port leverages native IDE features to bring ARIA's discipline directly into your workflow:

### 1. True Slash-Command Parity (Workflows)
During `/setup`, ARIA deploys thin-shim workflows to `.agents/workflows/` in your workspace. This enables actual slash-command execution within Antigravity:
* `/setup` — Configures/updates ARIA local settings.
* `/context <tag>` — Retrieves and loads relevant knowledge matching tags.
* `/snapshot` — Archives the current conversation transcript for later review.
* `/extract` — Synthesizes session insights, decisions, and rules into backlogs.
* `/handoff [auto|brief]` — Generates a passoff brief and next-session opener.
* `/wrapup` — Conducts the end-of-session ceremony (updates PROGRESS.md, CLAUDE.md, git commits).
* `/audit-knowledge` — Promotes or archives pending backlog items.
* `/audit-config` — Reconciles local config and documentation drift.

### 2. Always-On Rule Enforcement
Setup deploys `aria-rules.md` to `.agents/rules/aria-rules.md`. Antigravity's native rule engine parses this file on every prompt, ensuring Rule 22 and ARIA's other core coding/process standards are actively enforced without needing manual mentions.

### 3. Session-Start & Transcript Caching (PreInvocation Hook)
The flat layout registers a `PreInvocation` hook (`bin/antigravity/pre-invocation-aria.sh`) firing before every model call. It automatically:
* Caches `transcriptPath` and `artifactDirectoryPath` to `~/.gemini/antigravity/` so `/snapshot` and `/audit-knowledge` can locate them.
* Replicates the SessionStart hook behavior (audit cadence prompts, stale manifest sweeps, tag matching) on the first call of each conversation (`invocationNum == 0`).
* Drains Rule 22 scope-check feedback from `aria-knowledge-scope-check.log` and injects it as an ephemeral message on the next turn.

---

## 🎨 Best Practices by Session Phase

### Session Start
* **Let the pre-invocation checks run**: When you start a chat, ARIA will let you know if a knowledge audit is due or if a stale manifest needs sweeping.
* **Contextualize early**: Run `/context <project-tag>` at the start of a task to load matching ADRs, approaches, and project maps.

### During Work
* **Respect the [Rule 22] marker**: Before making file edits, always state your impact classification and justification (`[Rule 22] Low Impact — ...`). The hook will fail closed (deny the edit) if you skip this step.
* **Keep commits atomic**: Atomic commits allow `/retrospect` (when auditing releases/PRs) to produce highly precise, validated feedback.

### Session End
* **Run `/extract`**: Always run `/extract` before wrapping up to harvest the session's insights and store them safely in your backlog.
* **Run `/wrapup` or `/handoff`**: Let ARIA update your project documents, help you commit, and generate the copy-paste opener for your next session.

---

## 📚 What to Read Next
* [PORTING.md](PORTING.md) — Architectural design differences between the Claude Code and Antigravity ports.
* [README.md](README.md) — Detailed feature list, manual install steps, and requirements.
