# /wrapup — Close Session Cleanly

Close out a session when work is done and no passoff is intended.

## Steps

Invoke the aria-knowledge **`wrapup`** skill. Reviews session work, updates PROGRESS.md / CLAUDE.md / memory, commits changes, runs `/extract` for session knowledge capture, and confirms wrap-up. For passoff handoffs, use `/handoff` instead.

`/wrapup auto` applies implicit-yes on all gates and runs silently.
