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

## Releasing from a worktree

Building in a separate worktree (so a parallel session's commits on `main` cannot ride along) is
fine, with one trap: the built artifacts — `aria-knowledge-*.zip` at the root and
`plugin-claude-cowork/*.plugin` — are **ignored** files, and `git worktree remove` deletes ignored
files **without asking** (it refuses only on untracked or modified files). Removing the worktree
before copying the artifacts out destroys the release you just built, with exit 0.

Run these in order. Do not remove the worktree any other way.

```bash
# From the main checkout. Build the worktree somewhere other than /tmp: the suite's bash-write
# tests treat /tmp paths as scratch and fail there.
git worktree add -b release/<version> ../.wt-<version>-aria-knowledge origin/main
cd ../.wt-<version>-aria-knowledge

# 1. Commit the release, then build every port's artifacts (Steps 1 above).
./release.sh && ./release-antigravity.sh && ./release-codex.sh && ./release-cursor.sh

# 2. Copy the artifacts out, verify each copy, and only then remove the worktree — one command.
cd -
./release-worktree-finish.sh ../.wt-<version>-aria-knowledge

# 3. Merge release/<version> into main, then publish from the main checkout as in Steps 2-3.
#    This comes AFTER step 2 on purpose: publish-release.sh uploads the stable aliases at the root
#    of the checkout it runs in, so publishing before the copy would upload older artifacts.
```

`release-worktree-finish.sh` copies every artifact to the same path in the main checkout, `cmp`s
each copy, prints its size and checksum, and only if all of them match runs `git worktree remove`
(never `--force`). On any failed copy, or if it finds no artifacts at all, it exits non-zero and
leaves the worktree in place; a worktree that built nothing is removed with `--no-artifacts`.
⛔ Never `git worktree remove --force` a release worktree: `--force` skips even the
untracked-file refusal, and the artifacts were never protected by that in the first place.

## The failure mode this prevents

Historically the publish step uploaded only the versioned canonical zip, so the
3 port buttons and the cowork button on the site 404'd (the stable aliases were
never attached to any release). `publish-release.sh` makes "what was built"
and "what was published" match, and its verification step fails loudly if a
`/latest/` link doesn't resolve.
