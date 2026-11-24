# annas-mcp package

Build recipe of the `annas-mcp` package installed on the build host (0.1-5, `/usr/bin/annas-mcp`). Both files are
byte copies of the recipe that built the installed package; the working copy that holds the built package files is
the working copy of this recipe on the build host. Service, credential and MCP facts are on
[providers/annas-archive.md](../../providers/annas-archive.md).

| File | sha256 | Content |
|---|---|---|
| `PKGBUILD` | `2ca0c7d48ff9b2b33185c2cbcc5c834882a6e286841e9dbb979a92d982318a44` | AUR `annas-mcp` (maintainer Jamison Lahman, AUR release 0.1-3) at pkgrel 5; source pinned to upstream commit `c095963ad5d10d33da3c614495246b6ec7f680d4` (release v0.1, 2026-06-26) |
| `0001-fix-error-handling-and-slum-resolver.patch` | `1b4c7b0c1648412c0e5def22818e770471c9d63b58e0b1d711a7b94987933290` | local patch over 12 files of `internal/` (anna, env, logger, mirror, modes, version): error handling, the SLUM resolver, and tests |

Build with `makepkg -si` in a copy of this directory; `check()` runs `go test ./...`, which passes on the patched
tree with go 1.27.3. The wrapper `/usr/local/bin/annas-mcp-wrapper` is outside this package.

## Why search and DOI lookup answer 403

Anna's Archive serves every HTML route through DDoS-Guard, and DDoS-Guard answers an automated client with a
JavaScript challenge. Measured on 2026-11-01 against the three mirrors SLUM lists (`annas-archive.gl`, `.pk`,
`.gd`): `GET /search?q=...` answers 302 to `?check=1`, and that URL answers 403 with `Server: ddos-guard` and a page
that loads `check.ddos-guard.net/check.js`. The client fetches pages with Go's colly, which runs no JavaScript, so
it receives the 403 page. Upstream issue https://github.com/iosifache/annas-mcp/issues/22 ("403 for all requests")
records the same measurement since 2026-08-18; upstream has had no commit since v0.1 (2026-06-26).

| Code path | Route | State |
|---|---|---|
| `FindBook` (`book_search`) | `/search` HTML through colly | 403 |
| `FindArticle` (`article_search`) | `/search` HTML through colly | 403 |
| `LookupDOI` (`article_download` by DOI) | `/scidb/<doi>` HTML through colly | 403 |
| `Book.Download` (`book_download`) | `/dyn/api/fast_download.json?md5=&key=` | outside the challenge: the route answers JSON (`401 text/json` without a key) |
| `Paper.Download` | `/scidb?doi=` HTML | 403 |

The challenge is not User-Agent gated: the client already sends a browser User-Agent, and curl with a full browser
header set receives the same page (issue #22). SLUM's heartbeat route `/api/status-page/heartbeat/slum` answers 404,
so `ANNAS_AUTO_BASE_URL=true` ranks mirrors in page order; the patched resolver logs this and falls back to
`ANNAS_BASE_URL`.

## Routes past the challenge, and their state

Anna's Archive lets a signed-in member of tier Lucky Librarian or higher past the browser check. The secret key that
authorizes `fast_download.json` also signs in: a form POST of `key` to `/account/` sets the session cookie
`aa_account_id2` on its redirect, and that cookie lasts about a week. The fork https://github.com/SokolskyNikita/annas-mcp
(MIT, Go, release line v0.2) implements this sign-in, renews the session on a 403, and keeps the same four tools and
environment variables; its `anna/session.go` documents the flow. A browser-copied `aa_account_id2` cookie is the
manual form of the same session.

Two facts decide whether either route works for this account, and neither was measured: whether the key signs in,
and whether the account's tier is Lucky Librarian or higher. The measurement and the patch both wait on the owner,
because the agent session's permission policy refused the sign-in request as bot-check circumvention on
2026-11-01. A patch to this recipe that adds the session (sign-in, a cookie on the three colly collectors, one
renewal on 403) is about 150 lines over `internal/anna/anna.go` and `internal/env/env.go`; building the fork from a
pinned commit instead replaces this recipe's source and its local patch. The donation page limits the
check-free member session to normal browser use and points scripts to the metadata torrents, so neither route is a
sanctioned way to script search; the recipe stays as it is, and downloads by MD5 through the JSON API remain the
agent path.
