# Vendored — SESSION.md contract conformance fixtures

These `*.SESSION.md` files are a **verbatim copy** of the canonical SESSION.md
contract conformance set owned by **aria-atlas** (the contract consumer / owner).

- **Source:** `aria-atlas/tests/fixtures/session-contract/`
- **Vendored:** 2026-06-11
- **Why:** aria-knowledge is the **producer** — `plugin-*/bin/lib-session-state.sh`
  writes `SESSION.md`. Pinning the producer's repro (`tests/repros/session-state.sh`,
  section H) to the same bytes the consumer asserts against turns any contract
  drift into a test failure here, in the repo that would cause it.

## Re-sync recipe

When the canonical fixtures change in aria-atlas (a contract change — see
`aria-atlas/docs/SESSIONS.md` § Contract evolution), re-vendor:

```sh
cp ../aria-atlas/tests/fixtures/session-contract/*.SESSION.md \
   tests/fixtures/session-contract-vendored/
```

Then re-run `tests/repros/session-state.sh` and reconcile any new contract
assertions in its section H.

## Scope note

Only the `*.SESSION.md` fixture files are vendored. The canonical `README.md`
(naming rationale, the full set table, ownership + change protocol) lives at the
source path above and is **not** copied here — single-sourced on purpose.
