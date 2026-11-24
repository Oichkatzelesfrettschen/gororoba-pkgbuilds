# Graft local package

The package builds Graft 0.21.1 from graft-gororoba commit
`012bb4e418e7aa9b437a66d6be108651fbfcca0b`, our fork of `trailhq/Graft`.
GitHub redirects the historical `NanoNets/Graft` repository to `trailhq/Graft`;
the npm namespace remains `@nanonets/graft`. The fork's `main` is upstream
`fe30ead` plus:

- trailhq/Graft #521 and stacked #522, open upstream at the source check and
  carried with their original commits (`14c3e5b..c1d91b7`): stable path-hash
  synthesis batches, deterministic ordered merging, failure gating,
  `--synth-concurrency`, `--synth-model`, and `--synth-batch-chars` with cache
  isolation, compatibility and input clamps.
- `-j` forwarded to the concept pass on both the CLI and the workspace child
  path (`test/cli-concept-concurrency.test.ts`).
- One concept-synthesis batch in flight by default. qwen-nvidia PR #100's
  bounded model/slot qualification retains single-slot serving because both
  two-slot models changed factual conclusions between repeats; upstream's
  proposed default of four stays an explicit experiment.
- C function scopes that follow pointer and parenthesized return declarators
  to their own declaration or definition (`test/generic-c-declarator.test.ts`).
- A crux collector that keeps a target pending until a nonblank summary exists
  and resolves an echoed ID only when ID, kind and line span match exactly
  (`test/graph-enrich-identity.test.ts`).

The batch-key migration can require one cold synthesis pass; existing caches
stay retained. Separate synthesis-model selection also requires an endpoint
that serves that model; the flag alone grants neither model loading nor
quality admission.

## Trail auto-push

Graft 0.21 adds a background `graft trail push`, started by the session-start
hook that `graft init` installs, at most once a day and only for a repository
with a trail attached whose HEAD moved since the last push
(`src/brain/autopush.ts`). `GRAFT_TRAIL_AUTOPUSH=0` in the environment, or
`"trailAutoPush": false` in a repository's `.graft/config.json`, turns it off.
A repository without a trail never reaches the network through this path.

## Build and checks

From this package directory:

```sh
: "${PYTHON:?set PYTHON to the intended interpreter}"
export PYTHON SOURCE_DATE_EPOCH=1791055277
gh api repos/Oichkatzelesfrettschen/graft-gororoba/tarball/012bb4e418e7aa9b437a66d6be108651fbfcca0b \
  > graft-012bb4e418e7aa9b437a66d6be108651fbfcca0b.tar.gz
mkdir -p build-logs
SRCDEST="$PWD" BUILDDIR="$PWD" PKGDEST="$PWD" LOGDEST="$PWD/build-logs" \
  makepkg --force --cleanbuild --log
namcap PKGBUILD graft-0.21.1-1-x86_64.pkg.tar.zst
```

`SOURCE_DATE_EPOCH` is the pinned commit's timestamp.

## Build policy

The source archive and local patches carry SHA-256 checksums. `npm ci` uses the
fork's lockfile and its integrity hashes. Dependency lifecycle hooks stay
disabled; the recipe builds every native binding explicitly against system
Node headers with Arch compiler and linker flags, then compiles TypeScript and
the bundled viewer. The package excludes vendor prebuilds and intermediate
build files. Upstream prebuilds lack full RELRO, which makes source builds
necessary for the package hardening check.

Two dependency patches make existing scanner intent explicit under `-Werror`:
PHP marks an intentional switch fallthrough, and Python explicitly discards
the values returned by three stack pops. Both preserve the scanner operations.
They patch `node_modules` after `npm ci`, so they stay in the package while the
lockfile pins tree-sitter-php 0.23.12 and tree-sitter-python 0.21.0.

Namcap's `elfnopie` rule assumes every ELF path lacking `.so` is an executable.
Node's `.node` files are shared modules loaded through `dlopen`, so that rule
reports a false PIE warning for each binding. Check the full report, then run
`namcap -e elfnopie` alongside `readelf` checks for `ET_DYN`, `GNU_RELRO`,
`BIND_NOW`, and the absence of a program interpreter on every `.node` module.

`check()` runs the extraction, enrichment, synthesis and CLI test files that
cover the fork's changes. Fixture directories live under the build source
directory. A Git discovery ceiling prevents the packaging checkout's ignore
rules from hiding standalone fixture sources. `CI=1` and `DO_NOT_TRACK=1` close
upstream telemetry gates during builds and checks. Installation creates the
package-owned `/usr/bin/graft` link and runs no upstream install hook. Graft
host wiring remains an explicit `graft init` action.

To repeat the archive smoke tests after extracting the package:

```sh
CI=1 DO_NOT_TRACK=1 GRAFT_PACKAGE_ROOT="/absolute/extraction/usr/lib/node_modules/@nanonets/graft" \
  node --test package-smoke.mjs
```

The hosted validator uses `scripts/check-srcinfo.sh` to render metadata under
an unprivileged account with writable private scratch directories.

## Validation record

Release 0.21.1-1 builds with `makepkg --force --cleanbuild --log` and
dependency checks on, using Node 22.23.2, npm 12.0.2, GCC 16.2.1, Python
3.14.7, namcap 3.6.0 and `SOURCE_DATE_EPOCH=1791055277`.

- `check()`: 86 tests, 86 pass, 0 fail, 0 skipped.
- `package-smoke.mjs` against the extracted archive: 4 of 4 pass, and the
  packaged CLI reports `0.21.1`. The packaged `package-lock.json` matches the
  source archive byte for byte.
- All ten native bindings report `ET_DYN`, `GNU_RELRO`, `BIND_NOW` and no
  program interpreter. The full namcap report holds exactly the ten documented
  `elfnopie` warnings; `namcap -e elfnopie` and `namcap PKGBUILD` are empty.
- The build log holds zero compiler warning or error diagnostics, zero makepkg
  warnings and zero failed or fuzzy hunks. `bash -n`, `shellcheck -s bash -S
  error`, `scripts/check-srcinfo.sh` and `git diff --check` pass.

The package artifact is `graft-0.21.1-1-x86_64.pkg.tar.zst`, SHA-256
`6dd1174fedd01a44ef9996f73ccb11105f64308f4d48faafc12725a385032196`. Raw build
output stays in ignored `build-logs/`.
