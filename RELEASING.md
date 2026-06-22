# Releasing

How aria-knowledge ports get built, published, and kept linkable from the
marketing site (`ariaknowledge.com`).

## Release groups

Three groups, each versioned on its own cadence:

1. **Canonical** — `plugin-claude-code` → tag `v2.x.y` (the primary release; this is what `/releases/latest/` resolves to)
2. **Cowork** — `plugin-claude-cowork` → tag `cowork-vX.Y.Z`
3. **Ports** — `plugin-antigravity` + `plugin-openai-codex` + `plugin-cursor-template`

## The asset contract (why links don't break)

The site links to **stable, non-versioned** asset names via
`https://github.com/mikeprasad/aria-knowledge/releases/latest/download/<name>`:

| Site button | Stable asset name |
|-------------|-------------------|
| Claude Code | `aria-knowledge-plugin.zip` |
| Antigravity | `aria-knowledge-antigravity.zip` |
| Codex       | `aria-knowledge-codex.zip` |
| Cursor      | `aria-knowledge-cursor.zip` |
| Cowork      | `aria-cowork.plugin` |

`/latest/` resolves to the **newest release across all tags** — in practice the
canonical `v2.x` tag. A link only works if a fixed-name asset is attached
*there*. **Decision (2026-06-23): all 6 stable aliases ride the canonical
`v2.x` release** — it is the single asset hub `/latest/` points at, regardless
of how each port is versioned in source. Versioned artifacts
(`aria-knowledge-plugin-2.35.2.zip`, `aria-knowledge-codex-2.35.2.zip`, etc.)
may also go to their own group tags for provenance, but the site does not
depend on them.

Each `release-*.sh` already *builds* its stable alias at repo root (and the
cowork one at `plugin-claude-cowork/aria-cowork.plugin`). They do **not**
publish — that is `publish-release.sh`'s job.

## Steps

```bash
# 1. Build every port's artifacts (creates versioned + stable aliases)
./release.sh
./release-antigravity.sh
./release-codex.sh
./release-cursor.sh
(cd plugin-claude-cowork && ./release.sh)

# 2. Cut the canonical release if it doesn't exist yet
gh release create v2.35.2 --repo mikeprasad/aria-knowledge --title "..." --notes "..."
#    (cowork/port group tags are cut separately on their own cadence)

# 3. Attach ALL 6 stable aliases to the canonical release
./publish-release.sh              # dry run — shows what it would upload
./publish-release.sh --apply      # really upload, then verifies /latest/ links
```

`publish-release.sh` defaults the tag to `v<plugin.json version>`, preflights
that every stable alias exists, uploads with `--clobber`, then checks that all
five site `/latest/download/` URLs return 200. If a port wasn't rebuilt this
cycle, its previously-built alias is reused (re-run its `release-*.sh` to refresh).

## The failure mode this prevents

Historically the publish step uploaded only the versioned canonical zip, so the
3 port buttons and the cowork button on the site 404'd (the stable aliases were
never attached to any release). `publish-release.sh` makes "what was built"
and "what was published" match, and its verification step fails loudly if a
`/latest/` link doesn't resolve.
