# gororoba-pkgbuilds agent guide

This public repository holds the Arch Linux and CachyOS recipes of the gororoba
workspace whose sources come from an upstream release: Python and native
libraries, vendor SDK stacks, CUDA packages and tools. Each recipe is built and
tested by CI on GitHub-hosted runners, and the workspace's private recipes
without an upstream (configuration packages, machine tuning) stay in their
private homes. The workspace guide (`AGENTS.md` in the directory above this
checkout) holds the shared rules; this file governs where the two differ.

## Publication boundary

- The repository is public. A recipe, script, log or document names no host,
  address, account, credential location, private repository or absolute home
  path. `scripts/scrub-check.sh` enforces this before every push.
- A recipe enters through a scrub verdict and one `PROVENANCE.tsv` row naming
  its origin repository, path and commit. History from the origin does not
  come with it.

## Layout

- `<pkgname>/` at the top level: `PKGBUILD`, `.SRCINFO`, local sources.
- `nvchecker/<pkgname>.toml`: the upstream version source for that recipe,
  read from its `source=()` artifact.
- `scripts/`: the pipeline stages; POSIX `sh`, `set -eu`,
  `shellcheck -S error` clean.
- `.github/workflows/`: CI.
- `docs/`: the pipeline design and its decisions ledger.

## Recipes

- sha256sums for every non-VCS source; SPDX license identifiers;
  `.SRCINFO` regenerated with `makepkg --printsrcinfo` and tracked.
- A bump sets `pkgrel=1`, runs `updpkgsums`, and keeps coupled groups
  (listed in `docs/package-update-ci.md`) in one pull request.
- BUILDDIR, SRCDEST and PKGDEST point outside the checkout.
- Builds and test suites run in CI or on a compute host, never on the
  workstation that serves as the workspace build host.

## Landing

Pull request, CI green, merge commit by the owner. Commit subjects read
`component: mechanism`; commits and pull requests carry no AI attribution.
Text is emoji-free American English.
