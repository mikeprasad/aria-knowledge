# Template Parity Registry

Tracks template files that aria-cowork shares with aria-knowledge. Per ADR-007 (template/ duplicated across both repos), shared files maintain content parity within an additive-only deprecation window — edits to shared surfaces should preserve cross-plugin compatibility.

## Scope

| Property | Description |
|---|---|
| **Schema source-of-truth** | aria-knowledge (per D2 of v0.3.0 design) — output formats, frontmatter conventions, structural shape |
| **Surface-specific seeds** | Cowork ships surface-flavored seed content (e.g., commented-out alias examples) for files where content matters; structure stays parity |
| **Verification** | `release.sh` diff check (planned for v0.3.0 — see item #24) compares shared files against aria-knowledge's last-known version |

A file appears in this registry if its **content shape** is shared with aria-knowledge. Files that are wholly cowork-specific (e.g., `template/archive/README.md` extended with audit-cohort conventions cowork ships first) appear in the "Cowork-leading" section.

## Shared files

### Files synced to aria-knowledge content (cowork mirrors)

| File | Sync target | Cowork notes |
|---|---|---|
| `template/aliases.md` | aria-knowledge v2.16.0+ | Structure mirror; cowork-flavored seed examples (meeting/brief/doc/action/customer) per B4 lock |
| `template/rules/working-rules.md` | aria-knowledge v2.14.3+ | Full content mirror; 34 rules, Behavioral Foundation preamble, Rule 20 dual-form, 7 v2.14.3 refinements (lands in v0.3.0 Phase 1 item #3) |
| `template/rules/change-decision-framework.md` | aria-knowledge v2.14.3+ | Full content mirror (lands in Phase 1 item #3) |
| `template/rules/enforcement-mechanisms.md` | aria-knowledge v2.14.3+ | Full content mirror (lands in Phase 1 item #3) |
| `template/rules/user-examples.md` | aria-knowledge v2.14.2+ | aria-knowledge ships empty; cowork ships with 3 commented-out cowork-flavored examples (Rules 16/13/22 per B6 lock) |
| `template/README.md` | aria-knowledge v2.16.0+ | Structure mirror; semantic-hints frontmatter convention documented inline per item #2 |

### Cowork-leading files (cowork ships extended content first)

| File | Cowork content | aria-knowledge state |
|---|---|---|
| `template/archive/README.md` | Full audit-cohort conventions (MANIFEST schema, disposition taxonomy, verify-no-loss, ledger-vs-archive policy, user-override clause) per v0.3.0 item #4 | 3-line general-archive stub. Aria-knowledge candidate for v2.17.1 sync. |

## Non-shared template files

These files are cowork-specific and have no aria-knowledge counterpart (or have intentionally divergent content):

- `template/LOCAL.md` — user-owned guide; cowork-specific opening attribution + config-file-location note
- `template/OVERVIEW.md` — cowork-specific positioning
- `template/intake/*` — backlog files structurally shared (insights-backlog.md, decisions-backlog.md, extraction-backlog.md, rules-backlog.md); content user-authored

## Deprecation discipline

Per ADR-002 (additive-only schema, ≥2-version deprecation window):

- New fields or sections in shared template files are **additive** — cowork picks them up at the next parity-sync cycle without disrupting existing knowledge folders
- Renames or removals require a deprecation notice in both plugins' CHANGELOG, with the field/section preserved for at least 2 minor versions before removal
- Plugin-specific divergences (e.g., cowork's snapshot full-archive vs aria-knowledge's snapshot ledger pattern) are documented at the divergence point, not enforced as a parity break

## Sync history

| Date | Cowork version | aria-knowledge target | Notes |
|---|---|---|---|
| 2026-05-18 | v0.3.0 (in progress) | v2.16.1+ / v2.17.0+ | Initial TEMPLATE-PARITY.md registry; aliases.md + working-rules.md sync + semantic-hints + user-examples seed all land together |

## Related

- ADR-002 — additive-only schema with ≥2-version deprecation window
- ADR-007 — template/ duplicated in both repos
- aria-cowork [CONFIG.md](../CONFIG.md) — config schema parity (file location divergence, schema shared)
- aria-knowledge [`plugin/CONFIG.md`](https://github.com/mikeprasad/aria-knowledge/blob/main/plugin/CONFIG.md) — schema source-of-truth
