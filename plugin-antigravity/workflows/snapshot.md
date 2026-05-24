# /snapshot — Archive Current Transcript

Save the current Antigravity conversation transcript to the knowledge intake.

## Steps

Invoke the aria-knowledge **`snapshot`** skill. Reads the cached `transcriptPath` (set by the `aria-pre-invocation` hook) and copies the transcript to `{knowledge_folder}/intake/pre-compact-captures/`.

If the cache file doesn't exist yet, let the agent respond once first (the pre-invocation hook fires on every model call), then re-run.
