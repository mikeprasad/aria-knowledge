# /audit-knowledge — Knowledge Audit

Scan the current conversation transcript + artifact directory for extractable knowledge.

## Steps

Invoke the aria-knowledge **`audit-knowledge`** skill. Compares the current conversation's working state (transcript + artifacts) against what's already in the knowledge folder, surfaces anything worth promoting to backlogs or knowledge files, and routes user-approved items through the Accept submenu (tracker, ADR, ROADMAP, TODO, backlog, bundle, rule).

Triggered automatically by the pre-invocation hook on first-call when audit cadence is exceeded; can also be run manually anytime.
