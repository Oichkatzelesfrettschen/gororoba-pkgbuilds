# Decisions ledger: package update CI

Append-only. Each entry records the observation, the rule it establishes, the
evidence, and the check that enforces the rule in CI. An entry that a later
finding overturns stays, with a "Superseded by" line naming the entry that
replaces it.

## D-001 Upstream versions resolve from the source artifact, never from `url`

- Observation (2026-11-24): a census that took the first GitHub URL in a
  recipe reported 96 "outdated" rows across this repository and
  the private workspace infrastructure repository. About 40 were wrong: `url` named a
  sibling project (`litert-lm` and `ollama-gemini-shim` both "at" v0.20.0),
  a monorepo tag scheme (`aws-cdk` asset tags, `langchain-oracledb`), a
  different product (`physx-sdk` vs `ovphysx-0.8.0`), or a pinned commit
  (19 `synthesis-menta` packages).
- Rule: the version source is the artifact in `source=()`, declared per
  package in an nvchecker entry. A candidate whose artifact URL does not
  return HTTP 200 is not a candidate (`litert-lm` v0.20.0 has no
  `lit.linux_x86_64` asset).
- CI check: `update-check` resolves only declared nvchecker entries; a recipe
  without one reports `unchecked`, never `current`.
- Status: partly enforced by `scripts/update-check.sh` (nvchecker resolution over `nvchecker/*.toml`; `unchecked` for a recipe without an entry, branch `ci-pipeline`). The HTTP 200 asset check is planned.

## D-002 Installed-version reads use the exact package name

- Observation: `pacman -Q python-qiskit-aer` answered with the provider
  `python-qiskit-aer-cuda 0.18.2-3`, so the census believed the CPU recipe
  was installed.
- Rule: compare the `Name` field of `pacman -Qi` with the queried name.
- CI check: the install-state reader fails on a provides-match.
- Status: planned. No install-state reader exists on branch `ci-pipeline`.

## D-003 Packages built from local recipes leave the AUR upgrade path

- Observation: `paru -Sua` listed ten packages whose installed build came from
  a recipe here or in the private workspace infrastructure repository (`joern-git`, `perfetto`,
  `kuna-bin`, `rea-agents`, `oci-cli`, `python-jupytext`, ...). For
  `joern-git` the AUR recipe is older (4.0.523) than the local build
  (4.0.614); the AUR upgrade would have regressed it.
- Rule: one manifest lists every package whose recipe lives in these
  repositories. The workstation's paru configuration ignores those names, so
  AUR upgrades never replace them; CI owns their updates.
- CI check: `manifest-check` fails when a manifest package is installed with
  a different recipe origin (PACKAGER stamp, D-015).
- Status: planned. `manifest-check` is not implemented on branch `ci-pipeline`.

## D-004 Scriptlets have no network

- Observation: pacman 7.1 runs scriptlets and hooks in a loopback-only network
  namespace (`man pacman.conf`, DisableSandboxNetwork). BlackArch `brakeman`
  and `checkov` download gems and wheels in `post_upgrade` and silently keep
  stale contents (checkov stayed 3.3.1 under a 3.4.6 package).
- Rule: keep the sandbox. A recipe here never fetches in a scriptlet; a
  third-party package that does is listed with its manual post step.
- CI check: a grep of `*.install` for curl, wget, pip, npm, bundle and gem
  fails the lint job.
- Status: planned. No `*.install` lint exists on branch `ci-pipeline`.

## D-005 A version that sorts higher can be older code

- Observation: BlackArch `rr 6869.556551e4-1` (built 2024-07, depends on
  python2) sorts above the local 5.9.0 and the AUR's 5.10.0.
- Rule: an upgrade whose candidate build date precedes the installed build
  date is a downgrade until proven otherwise; such packages stay in
  IgnorePkg and update from the named source (`paru -S aur/rr`).
- CI check: the publish gate compares BUILDDATE as well as vercmp.

## D-006 One kernel module name, one DKMS owner

- Observation: `chipsec` (BlackArch, 2.0.10) and `chipsec-dkms-git` (local
  AUR build, 2.0.9) both registered `chipsec.ko`; whichever built second
  exited 6 on every kernel upgrade.
- Rule: a DKMS module name has exactly one owning package.
- CI check: `dkms-check` reads `dkms status` and every `dkms.conf`
  BUILT_MODULE_NAME; a duplicate fails.

## D-007 Kernel upgrades must retire the previous module tree

- Observation: `linux-modules-cleanup.service` (kernel-modules-hook) was
  disabled; 11 removed kernels left about 3.2 GB of module trees, and DKMS
  rebuilt into each on every upgrade.
- Rule: the service stays enabled; /usr/lib/modules/.old (where it copies
  trees) is emptied after the boot that follows a kernel upgrade.
- CI check: the host audit counts unowned /usr/lib/modules trees other than
  the running kernel; more than zero after a reboot fails.
- Status: planned. No host audit of module trees exists on branch `ci-pipeline`.

## D-008 A new dependency can collide with an installed package's files

- Observation: `python-cle` gained `extra/python-uefi-firmware`, whose 87
  files were owned by BlackArch `uefi-firmware-parser`; the whole
  transaction aborted.
- Rule: before publish, resolve the transaction against a snapshot of the
  workstation's file ownership.
- CI check: `publish-gate` runs `pacman -Sp` plus a file-conflict pass in a
  chroot seeded with `pacman -Qq` from the workstation.

## D-009 A bump waits until its runtime floor exists in the repositories

- Observation: `python-bedrock-agentcore` 1.27.0 requires boto3 >= 1.44.5;
  the repositories carry 1.43.108. `evil-opencode` pins `bun=1.4.4` while
  the system carries 1.4.5.
- Rule: a candidate whose depends or makedepends floors are unsatisfiable from
  the current repository snapshot is `held`, re-evaluated each run, and
  never published early.
- CI check: `readiness-gate` resolves the candidate's .SRCINFO against the
  synced repository databases; unsatisfiable floors produce `held`.

## D-010 Missing build or check dependencies are packaging gaps, not failures

- Observation: `datasette` needs python-pytest-runner, `python-cytoolz` needs
  python-setuptools-git-versioning, AUR `python-numdifftools` needs a
  python-lineprofiler chain that fails to build.
- Rule: the readiness gate names the missing package; the gap enters the
  manifest as a recipe to write or a dependency to drop.
- CI check: as D-009, with result `gap:<name>`.

## D-011 GPU-dependent checks run only where driver and library agree

- Observation: after the 620.73.04 userspace upgrade the running kernel module
  stayed 620.70.06 until reboot; `nvidia-smi` reported a version mismatch and
  python-cuquantum's `check()` failed with cuStateVec NOT_INITIALIZED.
- Rule: CUDA packages build without the GPU and run their GPU tests as a
  separate gate on a host whose `/proc/driver/nvidia/version` matches
  nvidia-utils.
- CI check: `gpu-gate` refuses to run (result `skip: driver mismatch`)
  rather than report a test failure.
- Status: planned. `gpu-gate` is not implemented on branch `ci-pipeline`.

## D-012 Three Python interpreters carry the stacks

- Observation: /opt stacks run on python3.13 (9 stacks, from `python313`),
  python3.11 (4 stacks, from `python311`) and the system 3.14 (1 stack);
  553 foreign packages are installed (`pacman -Qm`).
- Rule: a CachyOS Python minor bump is a rebuild wave across every foreign
  python package; the stacks additionally depend on `python311` and
  `python313` staying installable.
- CI check: `toolchain-watch` records python, cuda, nvidia-utils, boost-libs,
  icu, qt6-base, protobuf and abseil-cpp versions each run; a change opens a
  rebuild wave and holds ordinary bumps until the wave publishes.
- Status: planned. `toolchain-watch` is not implemented on branch `ci-pipeline`.

## D-013 Build trees live outside recipe directories

- Observation: `kaggle-benchmarks-stack` check() failed with BUILDDIR inside
  the checkout, because the repository's pyproject.toml sets
  `filterwarnings=error` and pytest collected it.
- Rule: BUILDDIR, SRCDEST and PKGDEST point outside any checkout.

## D-014 Recipes have one home

- Observation: `litert-lm`, `ollama-gemini-shim` and `llama.cpp-cuda` exist
  in two origin repositories at different releases.
- Rule: gororoba workspace recipes live in the private workspace infrastructure repository; this
  repository's copies are retired with a pointer once that home is current.
- CI check: `manifest-check` fails on a package name defined twice.
- Status: planned. `manifest-check` is not implemented on branch `ci-pipeline`.

## D-015 Every CI build is stamped

- Observation: every locally built package reads "Unknown Packager", so AUR
  builds and local builds are indistinguishable.
- Rule: CI builds set PACKAGER to a fixed CI identity; manual builds set the
  owner's identity.

## D-016 No builds on the build host; CI on hosted runners

- Observation: the owner forbade builds, compiles and test suites on the
  workstation (2026-11-16); this run nevertheless built about 60 packages
  there on request, at load 70 with memcg OOM kills in peer scopes. Workflows
  in the private origin repository never ran, and its `update-check.yml`
  calls a `scripts/check-updates.sh` that does not exist.
- Rule: builds run in CI or in a clean Arch chroot on a compute host; the
  workstation only installs packages that CI or a compute host produced.

## D-017 Claims in commit messages match the recipe

- Observation: commit 6ae84a5 says the aide build "runs check()"; the recipe
  has no check(). Corrected in a PR comment.
- Rule: acceptance reads the recipe for check() before a message claims tests.

## D-018 The trash is shared

- Observation: peer sessions trash their scratch into the same
  ~/.local/share/Trash; the owner rule is "trash-put, then remove this
  session's trash entries; no global trash-empty".
- Rule: CI cleanup removes only its own build trees and never empties a trash.

## D-019 Public repositories run GitHub-hosted CI

- Observation: on this repository, workflow run 45463251281 executed its
  shellcheck, recipes and scrub-check jobs with 8 steps each and passed.
- Rule: recipes that CI builds live in public repositories.

## D-020 Private history is not published; recipes move with fresh history

- Observation: the PKGBUILDS history carries personal contact details,
  absolute home paths, local network addresses and machine-specific package
  history. Rewriting it needs a force-push, which is prohibited.
- Rule: recipes enter this repository and pkgbuilds-personal as fresh files
  from a pinned origin commit, after a scrub verdict, with a provenance row;
  the origin repositories keep their history private.

## D-021 One public maintainer identity

- Observation: recipes carried three identities (a local-host address, the
  GitHub noreply address, a personal email).
- Rule: public recipes name
  `Oichkatzelesfrettschen <151315375+Oichkatzelesfrettschen@users.noreply.github.com>`;
  other people's Contributor lines stay.

## D-022 Upstream recipes and personal recipes have separate homes

- Rule: a recipe with an upstream release lives here and is tracked by
  nvchecker; a recipe without one (configuration, ricing, local tools) lives
  in pkgbuilds-personal, where each configuration value carries its
  justification and falsifier. Theme packages whose source repository is
  private stay out of both.

## D-023 Public text is scrubbed before it is pushed

- Observation (2026-11-24): the first push of this ledger named workspace
  hosts and file paths inside a private repository; the push was stopped
  before it left the machine.
- Rule: documents pass the same scrub as recipes (host-name list, home paths,
  private-repository paths) before a push.

## D-024 A package file a queued transaction lists is immutable

- Observation (2026-11-24): a package archive was replaced by a rebuilt
  revision while a queued `pacman -U` listed it. pacman committed 25 of the
  other packages, removed the old package's files, left an empty local
  database entry, and printed "no packages were upgraded".
- Rule: CI publishes a new revision under a new file name and never touches
  a file a pending transaction lists; a failed transaction is verified with
  `pacman -Dk` and the log's "upgraded" lines, never its closing message.
- CI check: publish-gate refuses to run while the pacman lock exists and
  checksums every listed file before and after the transaction.
- Status: planned. `scripts/publish-gate.sh` on branch `ci-pipeline` implements the version, build-date, file-owner and DKMS checks; it has no pacman lock check and no checksum pass.

## D-025 Measured hardware overrides recorded hardware

- Observation: documentation recorded 2 x 16 GiB of RAM; the system holds
  4 x 16 GiB from two kits rated 3600 and 2666, all at 3200 MT/s.
- Rule: tuning values derive from a measurement taken in the same run, and a
  disagreement with older documentation is recorded beside the value.

## D-026 CI builds the in-repository dependency closure through a local repository

- Observation: the first build of qcsuper failed because python-pycrate exists
  only here; the second failed because a pacman repository section without its
  database makes every sync operation fail. Run 45471278213 then built
  python-pycrate, published it to the container-local repository and built
  qcsuper against it.
- Rule: scripts/build-order.sh sorts the in-repository closure of depends,
  makedepends and checkdepends; the build job registers the local repository
  only after its first repo-add.

## D-027 Local builds are fenced from the AUR by an included IgnorePkg list

- Observation: paru offered AUR builds of ten names built from these recipes,
  one of them an older recipe than the installed build.
- Rule: the workstation's pacman.conf includes a generated IgnorePkg list of
  installed packages without a repository packager that a sync repository or
  the AUR also offers; official builds of the same names (xorg-server) stay
  out of the list so their updates continue.

## D-028 CachyOS [cachyos] fills repository gaps in the build container

- Observation: the archlinux container ships neither python313 nor python311,
  which the venv stacks pin, so a from-source CPython recipe stood in for a
  package the CachyOS repository already builds; pacman-key --lsign-key then
  failed because the image carries no local master key.
- Rule: the build job runs pacman-key --init, imports the CachyOS key by its
  full fingerprint, and appends [cachyos] after core and extra, so an Arch
  package of the same name always wins and [cachyos] supplies only names Arch
  lacks.

## D-029 The compute-host tier builds on hosted runners

- Observation: the recipes held for a compute host (or-tools, casadi, the
  pyscf chain of libcint, libxc and xcfun, python-qiskit-addon-sqd,
  python-hupper, python-amazon-ion) fit the hosted build job, whose limit is
  the 360-minute default; python-qiskit took 65 minutes with its full test
  suite in the same job. The clean compute-host chroot of D-016 remains
  unbuilt.
- Rule: those recipes and their in-repository closure, computed by
  scripts/build-order.sh before the allowlist change (python-py-build-cmake
  for python-amazon-ion), join ci/build-allowlist.txt in one change; a recipe
  that exceeds the runner's time, memory or disk returns to the compute-host
  tier with the measured limit recorded here.
