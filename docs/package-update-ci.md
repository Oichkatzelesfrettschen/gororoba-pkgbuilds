# Package update CI

This document defines the pipeline that keeps the recipes in this repository
in step with their upstreams, and publishes the results to the workstation only
after the CachyOS and Arch packages they depend on have landed. Every rule below
traces to an entry in [decisions/package-update-ci.md](decisions/package-update-ci.md)
(D-NNN). Each stage carries a status line: "implemented" names the script or
workflow that performs the stage; "planned" names a stage that no script or
workflow performs yet.

Branch note (2026-11-24): the scripts and workflows named here live on branch
`ci-pipeline`; the recipe directories named in the tables live on branch
`review-20261124`. Neither branch has merged to `main` yet.

## Pipeline

A run proceeds through seven stages. Each stage writes one line per package to a
run ledger (`package stage result detail`), and a package stops at the first
stage that does not return `ok`.

1. **toolchain-watch** (D-012). Sync the repository databases and record the
   versions of python, python311, python313, cuda, nvidia-utils, boost-libs, icu,
   qt6-base, protobuf and abseil-cpp. A change since the previous run opens a
   rebuild wave: every manifest package that links or installs against the changed
   anchor is queued for a pkgrel bump, and ordinary version bumps are held until
   the wave publishes.
   Status: planned. No script on branch `ci-pipeline` records these versions.
2. **update-check** (D-001). nvchecker resolves each manifest package from the
   artifact named in its `source=()`, using the configuration file
   `nvchecker/<pkgname>.toml`. A package with no entry reports `unchecked`. A
   candidate is the newest stable release whose artifact URL answers HTTP 200.
   Status: implemented in `scripts/update-check.sh` (nvchecker runs over
   `nvchecker/*.toml`; `unchecked` for a recipe without an entry; exit 2 when
   nvchecker is absent) and `.github/workflows/update-check.yml` (weekly schedule
   that skips odd ISO weeks). The HTTP 200 asset check is planned: the script
   compares versions and does not fetch the artifact URL.
3. **readiness-gate** (D-009, D-010). Render the bumped .SRCINFO and resolve
   depends, makedepends and checkdepends against the synced databases plus this
   pipeline's own private repository. Results: `ok`, `held:<floor>` (a floor the
   repositories do not yet satisfy), `gap:<name>` (a package no repository provides).
   Status: implemented in `scripts/readiness-gate.sh`, which emits `ok`,
   `held:` and `gap:` results from its inputs.
4. **build** (D-013, D-015, D-016). Build each recipe with `makepkg`, with BUILDDIR,
   SRCDEST and PKGDEST outside the checkout, PACKAGER stamped and `check()` enabled.
   The target is a clean CachyOS chroot on a compute host.
   Status: partly implemented in the `build` job of `.github/workflows/ci.yml`
   (BUILDDIR, SRCDEST and PKGDEST under `/var/tmp/build`; PACKAGER from the job
   environment; build order from `scripts/build-order.sh`; hosted runners build only
   the recipes on `ci/build-allowlist.txt`). The clean chroot is planned, and so is
   the rule that makes warnings in the recipe's own scripts fatal.
5. **gpu-gate** (D-011). CUDA packages run their GPU tests only where
   `/proc/driver/nvidia/version` matches nvidia-utils; otherwise `skip: driver mismatch`.
   Status: planned.
6. **publish-gate** (D-005, D-006, D-008). Against a snapshot of the workstation
   (`pacman -Qq`, `pacman -Ql`, `dkms status`): vercmp and BUILDDATE must both
   advance, `pacman -Sp` must resolve, no file may belong to an installed package
   outside the transaction, and no two DKMS packages may build one module name.
   Status: partial. `scripts/publish-gate.sh` implements the vercmp and BUILDDATE
   comparisons, the file-owner check and the DKMS duplicate check, reading the
   installed, owner and DKMS snapshots as TSV inputs. The `pacman -Sp` resolution,
   the capture of the workstation snapshot, and the lock and checksum checks of
   D-024 are planned.
7. **publish**. repo-add to a signed private repository; open one pull request per
   coupled group carrying the bump commits and the run ledger rows. A merge stays
   the owner's act.
   Status: planned.

The workstation consumes the private repository with an ordinary `pacman -Syu`;
paru ignores every manifest name (D-003).

## CI as implemented

The `build` job of `.github/workflows/ci.yml` runs in one `archlinux:base-devel`
container on a GitHub-hosted runner. The job installs git and sudo, creates a
non-root `builder` user, and runs
`makepkg --syncdeps --noconfirm --needed --cleanbuild` for each allowlisted recipe
in the order `scripts/build-order.sh` gives. After each successful build, `repo-add`
adds the package to a container-local repository (`ci-local.db.tar.gz`). The
repository section is registered in pacman.conf only after that first `repo-add`,
because pacman fails every sync while a configured repository lacks its database.
Recipes that are not on the allowlist are skipped with a log line and build on a
compute host. The clean CachyOS chroot of stage 4 is planned; the current job does
not use a chroot.

## Cadence and ordering

- Scheduled run every other Monday 08:00 UTC, plus manual dispatch.
- A run starts only after the CachyOS repositories have settled: the
  toolchain-watch stage waits until two database syncs one hour apart return
  identical anchor versions, so a half-landed rebuild never seeds a build.
  Status: planned with toolchain-watch.
- Coupled groups bump together or not at all. Each group lists its members as
  they exist in this repository on branch `review-20261124`:
  - braket (schemas, default-simulator, sdk): all present.
  - aws-cdk (lib, cloud-assembly-schema, asset-awscli-v1, jsii): all present.
  - qiskit-ibm (runtime, catalog): present. The names python-qiskit-ibm-serverless
    and python-qiskit-ibm-noise-learning are not in this repository;
    python-qiskit-serverless and python-qiskit-noise-learning are, and they are
    not yet in the group (open decision 4).
  - aer (python-qiskit-aer, python-qiskit-aer-cuda): present. An earlier list also
    named a gororoba-quantum copy, which is not a recipe in this repository.
  - TensorRT (python-torch-tensorrt-cp314): tensorrt and python-tensorrt are not in
    this repository, so python-torch-tensorrt-cp314 is the only member present.
  - kuna (kuna-bin): present. ghidra-extension-kuna-bin is not in this repository.
  - oci (oci-cli): present. python-oci is not in this repository. python-oci-genai-auth,
    python-oci-openai and python-ocifs are present and belong to no group.
  - hypercomplex (algebra, engine, eigenkit): python-hypercomplex-algebra,
    python-hypercomplex-engine and python-eigenkit are all present.

## Tiers

| Tier | Meaning | Packages (2026-11-24) |
|---|---|---|
| A, hosted | Auto-bump, build on GitHub-hosted runners, open PR | The 18 names on `ci/build-allowlist.txt` (branch `ci-pipeline`): qcsuper, python-hupper, python-pycrate, deqp-runner, wakaru-bin, jadx-headless-mcp-bin, rea-agents, python-amazon-ion, python-kagglehub, python-kingdon, python-eigenkit, python-hypercomplex-algebra, python-hypercomplex-engine, python-jupytext, python-scmver, python-boltons, python-pauli-prop, python-scramp |
| A, compute host | Auto-bump, build on a compute host, open PR | aide, datasette, kuna-bin, oci-cli, cvcuda-bin (also Tier B, open decision 5), nvimgcodec-bin (also Tier B, open decision 5), python-pyathena, python-bedrock-agentcore (held on boto3), python-cytoolz (gap), the braket, aws-cdk and qiskit-ibm groups, originquantum-stack, qxelarator-python313 |
| B | Auto-detect; build and publish after owner review | Patched or toolchain-pinned recipes: perfetto, semgrep-source (multi-hour build), webkit2gtk-4.1-hardened, xorg-server-glamor-r300fix, evil-opencode (bun pin; not in this repository), open-webui-stack and kaggle stacks (lock regeneration), every CUDA recipe (python-qiskit-aer-cuda, python-cuquantum, python-torch-tensorrt-cp314) |
| C | Never automatic | Configuration packages without an upstream, which live in pkgbuilds-personal (D-022; e.g. case-leds-indigo-dim), deliberate pins (tree-sitter-0.22-compat, gcc13-sidecar-bin, uefitool, obs-face-tracker, rr, which is not in this repository), firmware tools (micron-storage-executive-cli-crucial-mx500-updater), local_only/ |

## Blast radius per anchor

| Anchor change | What rebuilds | Measured scope |
|---|---|---|
| Python minor (3.14 to 3.15) | every foreign python-* package and the one 3.14 stack | 553 foreign packages installed; 1 stack |
| python313 or python311 removal | 9 and 4 /opt stacks respectively, plus qxelarator-python313 | 14 stacks |
| CUDA major or cuDNN | aer-cuda, cuquantum, TensorRT group, cvcuda-bin, nvimgcodec-bin | 7 packages |
| nvidia-utils minor | nothing rebuilds; GPU tests wait for a reboot (D-011) | 0 |
| Kernel | DKMS modules only (acpi_call, chipsec, ryzen_smu, v4l2loopback, vmware) | 5 modules |

## Gap sweep (2026-11-24)

Method: every `import` and `from` in the tracked Python of gororoba-quantum,
gororoba-math, gororoba-open, the private workspace infrastructure repository and
gororoba-alpoge-replay (2408 files), minus the standard library and minus
modules defined in those repositories, checked against the system
site-packages and every /opt stack.

**Covered.** The higher-dimensional algebra stack is complete for current
use: clifford (including conformal G3C), galgebra, kingdon, numpy-quaternion,
quaternionic, pyquaternion, pyoctonion, octonion, cayley_dickson,
Cayley_Calculator, SplitOct, hypercomplex, hypercomplex-algebra,
hypercomplex-engine, pyadic and python-flint (p-adic), hyprat, sage (Jordan
and Hopf algebras, p-adic fields, Clifford algebras), sympy, numpy-quaddtype,
numpy-flint-arb, cvxpy. Quantum vendors without system packages run from
their stacks: qbraid, bluequbit, ionq, iqm-resonance, quantuminspire
(opensquirrel, cqasm, pennylane), originquantum (pyqpanda3), quafu,
quantum-pipeline (qiskit-nature, qiskit-algorithms).

**Imported but provided nowhere.**

| Module | Call site | Provider | Action |
|---|---|---|---|
| openquantum_sdk | provider client | PyPI only | recipe (Tier A) or stack |
| planck_sdk | stack test | recipe exists, not installed | install planck-stack |
| qiskit_debugger | stack test | stack installed; import path differs | read the stack's test |
| seekpath | lattice cross-check | AUR python-seekpath 2.2.1 | install from AUR or recipe |
| mineru_vl_utils, chandra | OCR tooling | PyPI only | OCR runs on a compute host; no workstation package |
| zendriver | browser automation | PyPI only | recipe if it runs on the workstation |
| pyspiel | stack test | open_spiel, none packaged | stack extra |
| mlflow | reference templates | AUR (out of date) | none; reference code only |

**Qiskit gaps.** Not installed and available in the AUR (one maintainer,
iyanmv, keeps them in step): python-qiskit-algorithms, -machine-learning,
-optimization, -nature, -dynamics, -ibm-transpiler (flagged out of date),
-addon-sqd, -addon-obp, -addon-cutting, -addon-mpf, -addon-aqc-tensor.
qiskit-experiments and qiskit-qasm3-import are installed. qiskit-ionq is
packaged nowhere (it lives in ionq-stack).

**Vendor and adjacent gaps.** Not packaged anywhere: pytket, pennylane-lightning,
pennylane-qiskit, iqm-client, mitiq, tensornetwork, opt-einsum,
amazon-braket-pennylane-plugin, CUDA-Q (cudaq). In the AUR: cirq 1.7.0,
qutip 5.3.1, openfermion (orphaned, out of date), pennylane (out of date).
Installed: stim, quimb, cotengra (AUR 0.8.4 fails one upstream plotting test
in check()).

**Optimization.** Installed: cvxpy, pyscipopt with SCIP 10.1, HiGHS and
highspy, coin-or-cbc, pulp, jax, optax. Available: or-tools (AUR),
pyomo (AUR), jaxlib-cuda (AUR, out of date). Not packaged: ipopt, casadi,
python-ortools.

**Linear algebra on Zen 3.** The active BLAS is OpenBLAS (blas-openblas from
cachyos-v3). AMD's AOCL recipes in the private workspace infrastructure repository (blis, libflame,
lapack, utils, crypto) sit at 5.3 while upstream ships 6.0.0, and none is
installed. FlexiBLAS (AUR 3.5.0) switches backends at run time without a
package swap, which makes an OpenBLAS / AOCL-BLIS / MKL comparison on the
5600X3D a measurement rather than a migration. The comparison needs a
profile of a target workload first; no backend change lands without one.

**Ricing.** The synthesis-menta suite (19 packages) pins its theme commit on
purpose and reports current; dracula-gtk-theme-gtk4-compat and
orchis-gtk-theme-full track tags (orchis upstream 2026-07-07 is newer than the
recipe's 2025-04-25).

## Open decisions

1. Compute host for the runner: answered by D-019 (GitHub-hosted runners on this public repository).
2. Where the private package repository is served from and which key signs it.
3. Which gap rows become recipes.
4. Whether python-qiskit-serverless and python-qiskit-noise-learning join the qiskit-ibm group, and whether the group keeps the names python-qiskit-ibm-serverless and python-qiskit-ibm-noise-learning.
5. Tier overlap: cvcuda-bin and nvimgcodec-bin are listed under Tier A (compute host) and under Tier B (CUDA recipes). Which tier governs them.
