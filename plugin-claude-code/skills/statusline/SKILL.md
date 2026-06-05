---
description: "Install or remove the aria-knowledge status-line meter — a context-window progress bar plus the rolling 5-hour and 7-day plan-usage percentages, shown at the bottom of the Claude Code CLI. Use when the user says '/statusline', 'add a context meter', 'show context usage in the status line', 'show my 5-hour usage', 'usage meter', 'enable the status line', or 'turn off the status line meter'. Claude Code only (the status line is a Code feature). Triggers: '/statusline', '/statusline on', '/statusline off', '/statusline status'."
argument-hint: "[on|off|status]"
allowed-tools: Read, Write, Edit, Bash, Glob
---

# /statusline — Context + Usage Meter

Wire up (or remove) a persistent status line at the bottom of the Claude Code CLI showing:

```
Opus 4.8 │ ███░░░░░░░ 31% ctx │ 5h 24% ↺01:00 │ 7d 88%
```

- **context bar + %** — how full the context window is (input-only percentage, green → yellow → red).
- **5h NN% ↺HH:MM** — rolling 5-hour plan-usage window + when it resets (Pro/Max plans only).
- **7d NN%** — rolling 7-day window (Pro/Max plans only).

The 5h/7d segments render only on Pro/Max subscription sessions and only after the first response of a session. On API-key sessions they're absent and the line shows model + context only.

The meter's last segment is the **account email** (read from `~/.claude.json`), placed last so a width-truncated line only ever clips the email, not the usage — and so you can tell which account a terminal belongs to when running more than one.

Installing the meter also lets the **session's Claude** know these numbers: on each render the meter writes a snapshot, **keyed by account**, to `~/.claude/aria-statusline-state-<accountUuid>.json`, which Claude reads on demand (e.g. before `/handoff` or compaction — see the SessionStart TASK BUDGET guardrail). Per-account keying means a second logged-in account never clobbers the first's usage (which previously caused the alert to fire on the wrong account). A `UserPromptSubmit` hook additionally injects a warning when context/5h/7d crosses `usage_alert_threshold` (default 80%, configurable in `/setup`; set `off` to disable). All of this is dormant until the meter is installed.

## Why a command and not automatic

A Claude Code plugin **cannot** register a `statusLine` from its manifest — the main status line is read only from the user's `~/.claude/settings.json`. So this skill performs the one-time wiring: it copies the meter script to a stable location and points your settings at it. (`subagentStatusLine` is the only status-line key a plugin may default, and it's a different surface.)

## Runtime note

This is a Claude Code feature. If the `Bash` tool is unavailable (you're in Cowork or another non-Code runtime), tell the user: *"The status-line meter is a Claude Code feature and can't be configured from this runtime."* and stop. Otherwise proceed.

## Argument routing

Parse the argument (default `on` when none given):

- **`on`** (or empty) → run **Install / Refresh**.
- **`off`** → run **Remove**.
- **`status`** → run **Status**.

---

## Install / Refresh

### Step 1 — Locate the meter script and check dependencies

```bash
SRC="${CLAUDE_PLUGIN_ROOT}/bin/statusline-meter.sh"
DEST="$HOME/.claude/aria-statusline-meter.sh"
SETTINGS="$HOME/.claude/settings.json"
[ -f "$SRC" ] && echo "source ok: $SRC" || echo "MISSING SRC"
command -v jq >/dev/null 2>&1 && echo "jq: present" || echo "jq: MISSING"
echo "HOME=$HOME"
```

- If `MISSING SRC`: tell the user the plugin install looks incomplete and stop.
- If `jq: MISSING`: warn — *"`jq` isn't installed. The meter needs it to read the status-line data; without it the line will show only the model name. Install with `brew install jq` (macOS) or your package manager, then re-run `/statusline`."* Continue anyway (a model-only line still installs cleanly), but make the limitation explicit.
- Capture the literal `HOME` value — you will write an **absolute** path into settings.json (do not write `~` or `${CLAUDE_PLUGIN_ROOT}`; neither is guaranteed to expand in the settings file, and the plugin's own install dir is version-stamped and changes on update).

### Step 2 — Copy the meter to the stable path

```bash
mkdir -p "$HOME/.claude"
cp "${CLAUDE_PLUGIN_ROOT}/bin/statusline-meter.sh" "$HOME/.claude/aria-statusline-meter.sh"
chmod +x "$HOME/.claude/aria-statusline-meter.sh"
echo "copied to $HOME/.claude/aria-statusline-meter.sh"
```

Copying (rather than referencing the plugin dir directly) means the meter survives plugin updates and reinstalls. The trade-off: when a plugin update improves the meter, the user re-runs `/statusline` to refresh this copy — say so in the final summary.

### Step 3 — Read existing settings and detect conflicts

Read `~/.claude/settings.json` with the Read tool.

- **If the file doesn't exist:** you'll create it in Step 4 with a single `statusLine` key.
- **If it exists and has no `statusLine` key:** you'll merge one in, preserving every existing key.
- **If it exists and already has a `statusLine` key:**
  - If its `command` already points at `…/aria-statusline-meter.sh`, this is a refresh — no settings change needed (the Step 2 copy already updated the script). Report that and skip to Step 5.
  - If it points elsewhere (a foreign/custom status line), **stop and ask**: *"Your settings.json already has a custom status line: `<command>`. Replace it with the aria-knowledge meter? (y/n)"* — only proceed on explicit `y`. On `n`, leave settings untouched and tell the user the meter script is staged at `~/.claude/aria-statusline-meter.sh` if they want to wire it manually.

### Step 4 — Back up and write settings

Before any write, back up the existing file (only if it exists):

```bash
[ -f "$HOME/.claude/settings.json" ] && cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.aria-bak" && echo "backed up to settings.json.aria-bak"
```

Then write `~/.claude/settings.json` with the `statusLine` block merged in, **preserving all existing keys** (read the current JSON, add/replace only the `statusLine` key, write the whole object back — valid JSON, 2-space indent). The block:

```json
"statusLine": {
  "type": "command",
  "command": "<HOME>/.claude/aria-statusline-meter.sh",
  "refreshInterval": 30
}
```

Substitute `<HOME>` with the literal absolute path captured in Step 1 (e.g. `/Users/alice/.claude/aria-statusline-meter.sh`). If the file didn't exist, the whole file is just `{ "statusLine": { … } }`.

`refreshInterval: 30` re-runs the meter every ~30s **in addition to** the event-driven renders, so the persisted usage snapshot stays current even while the session is idle or just after a resume (when no assistant message has fired a render yet). It re-runs only the meter — a local ~5ms script with **no API token cost** — and does **not** change how often the usage *alert* fires (that's the `UserPromptSubmit` hook, band-gated on your prompt). On a refresh/repair where settings already has a `statusLine` pointing at the aria meter, set `refreshInterval` to `30` if it's absent, but **preserve a user's existing smaller (higher-frequency) value**.

**Validate the written JSON** before declaring success:

```bash
if command -v jq >/dev/null 2>&1; then
  jq empty "$HOME/.claude/settings.json" && echo "settings.json: valid JSON" || echo "settings.json: INVALID — restoring backup"
fi
```

If validation fails, restore from `settings.json.aria-bak` and report the error rather than leaving broken settings in place.

### Step 5 — Verify the rendered line

Prove it works by piping a representative payload through the installed copy (don't ask the user to eyeball the CLI — show them the rendered output):

```bash
echo '{"model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":31},"rate_limits":{"five_hour":{"used_percentage":24,"resets_at":0},"seven_day":{"used_percentage":12}}}' | "$HOME/.claude/aria-statusline-meter.sh"; echo
```

### Step 6 — Confirm

Summarize:

```
Status-line meter installed.
- Script: ~/.claude/aria-statusline-meter.sh
- Wired in: ~/.claude/settings.json (backup at settings.json.aria-bak)
- Shows: model · context bar · 5h usage · 7d usage (5h/7d on Pro/Max only)

It appears at the bottom of the CLI on the next render (start typing, or open a new session if it doesn't show).
Re-run /statusline after a plugin update to refresh the meter script.
Remove it anytime with /statusline off.
```

If `jq` was missing, append the install hint and note the line will show model-only until jq is installed.

---

## Remove

1. Read `~/.claude/settings.json`. If it has no `statusLine` key, report "No status-line meter is configured." and stop.
2. If the `statusLine.command` does **not** reference `aria-statusline-meter.sh`, it's not ours — **stop and ask** before removing: *"The configured status line isn't the aria-knowledge meter (`<command>`). Remove it anyway? (y/n)"*.
3. Back up (`cp settings.json settings.json.aria-bak`), then rewrite settings.json with the `statusLine` key removed, preserving all other keys. Validate the result is valid JSON (restore backup on failure).
4. Offer to delete the staged script + snapshots: *"Also delete the meter script (`~/.claude/aria-statusline-meter.sh`) and its per-account usage snapshots (`~/.claude/aria-statusline-state-*.json`)? (y/n)"* — on `y`, `rm -f` the script plus the `aria-statusline-state-*.json` glob (and the legacy `aria-statusline-state.json` if present), plus any `/tmp/aria-usage-warn-*` band-state files.
5. Confirm: "Status-line meter removed. Backup at ~/.claude/settings.json.aria-bak." (The usage-alert hook stays registered but is now a silent no-op with no snapshot to read.)

---

## Status

1. Report whether `~/.claude/aria-statusline-meter.sh` exists.
2. Read `~/.claude/settings.json` and report whether `statusLine` is set and what `command` it points at (and whether that's the aria-knowledge meter).
3. Report whether `jq` is installed (`command -v jq`).
4. If installed and pointing at our meter, render the sample line (Install Step 5) so the user sees current output.
