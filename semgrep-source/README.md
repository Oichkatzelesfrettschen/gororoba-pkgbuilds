# semgrep-source

`semgrep-source` builds Semgrep from the upstream source release instead of
using the binary repository package.  The package is for stock x86_64 output:
`-march=x86-64 -mtune=generic -O2`, with Clang/LLVM 22 selected by command
name.

## Compiler distribution model

Semgrep has two different compile surfaces:

- C and C++ foreign stubs, tree-sitter runtime code, and scanner code use the
  normal compiler environment.  This package routes those jobs through a distcc
  masquerade directory when `SEMGREP_SOURCE_USE_DISTCC=1`.
- OCaml modules are built by Dune through `ocamlopt` and `ocamlc`.  Dune
  supports local parallelism and a shared content cache, but it does not expose
  a distcc-style remote execution switch for OCaml compile actions.

The practical layered setup is therefore:

1. Use distcc for Clang/LLVM C and C++ jobs.
2. Use Dune cache for OCaml reuse across repeated local builds.
3. Treat Bazel remote execution with `rules_ocaml` as a separate migration
   project, not as a package-time switch for this Semgrep source tree.

Why this split exists:

- `distcc` distributes C, C++, Objective C, and Objective C++ compiler
  invocations.  It does not understand OCaml module typing, `.cmi`/`.cmx`
  dependencies, or Dune's action graph.
- Dune's supported acceleration surface is local parallelism plus a shared build
  cache.  A cache hit restores a rule result; it is not remote execution of that
  rule on another host.
- `ocamlopt` separate compilation depends on compiled interface and native
  metadata files.  Moving those actions to arbitrary workers requires a build
  system that declares the complete action input set and toolchain, not a
  compiler-name wrapper.
- Bazel remote execution can provide that model, but only after the build has
  been expressed as hermetic Bazel actions and toolchains.  That is a migration
  project, not an environment variable for this upstream Dune tree.

The package therefore uses a hybrid that is honest about the boundary:
distributed Clang where the source language and compiler protocol support it,
cached local Dune where the source language requires Dune's OCaml dependency
model.

## Build controls

Useful environment variables:

- `SEMGREP_SOURCE_USE_DISTCC=0` disables distcc masquerade.
- `SEMGREP_SOURCE_DISTCC_HOSTS` overrides the package host list.
- `SEMGREP_SOURCE_DUNE_CACHE_ROOT` points Dune at a persistent cache.
- `SEMGREP_SOURCE_OPAMROOT` and `SEMGREP_SOURCE_OPAM_SWITCH` select an existing
  opam root and switch.
- `SEMGREP_SOURCE_AR` and `SEMGREP_SOURCE_STRIP` override LLVM archive/strip
  tools.

The Arch/CachyOS LLVM 22 packages expose most LLVM tools as unversioned names
such as `llvm-ar`, `llvm-strip`, `lld`, `clangd`, and `lldb`.  Only the Clang
driver is reliably available as `clang-22` and `clang++-22`.

The expected LLVM 22 suite on CachyOS/Arch hosts is:

- `clang`
- `llvm`
- `llvm-libs`
- `compiler-rt`
- `libclc`
- `lld`
- `lldb`
- `openmp`
- `polly`
- `libc++`
- `libc++abi`
- `llvm-bolt`

`libunwind` and `lib32-libunwind` are versioned independently by Arch, but are
kept installed with this toolchain on the current build hosts so C++ and
multilib unwind behavior stays aligned.

## Compute-host validation

The stock x86_64 package was built and installed on a compute host with:

- `SEMGREP_SOURCE_USE_DISTCC=1`
- `SEMGREP_SOURCE_DISTCC_HOSTS="compute-host-1/32,lzo compute-host-2/16,lzo localhost/2,lzo"`
- `SEMGREP_SOURCE_OPAM_SWITCH=semgrep-k8-5.3.0`
- `SEMGREP_SOURCE_DUNE_CACHE_ROOT=$HOME/.cache/dune-semgrep-source`

The build completed `semgrep-core`, built the Python wheel, downloaded the
offline wheelhouse, passed `check()`, and emitted:

```sh
semgrep-source-1.164.0-1-x86_64.pkg.tar.zst
```

The package replaced the repository `semgrep` package on a compute host
and installed a virtual environment from the local wheelhouse under
`/usr/share/semgrep-source/venv`.

Post-install checks:

```sh
pacman -Q semgrep-source
semgrep --version
semgrep --quiet --config rule.yml sample.py --json
```

The ReKit Tier S calibration passed on the same host with `~/.local/bin` added
to `PATH` so the already-installed `weggli` binary is visible to non-interactive
SSH shells:

```sh
PATH="$HOME/.local/bin:$PATH" \
  mesa-rekit/staged/code-analysis-tier-s/calibration/run_source_intelligence_calibration.sh
```

That calibration certified Semgrep known-good/known-bad fixtures, weggli,
ast-grep, ctags, cscope, and GNU Global replay.
