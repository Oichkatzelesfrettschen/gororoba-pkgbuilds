# GPUFiniteFieldMatrices.jl on the Arch family

GPUFiniteFieldMatrices.jl (MIT) is a Julia package with no PKGBUILD here. The
rationale is Julia's own packaging model: a package is resolved with its
dependency graph (CUDA.jl and its CUDA artifacts) into a per-user project
environment by Pkg, so a system package would freeze one resolution for every
user and duplicate what the manifest records. This repository holds no Julia
package recipe, and `julia` itself comes from the `extra` repository.

## Upstream facts (read at tag v0.4.0, commit 2c13ff009952ef5f3cb1466d371dd7712cf865cf)

- Repository: github.com/p-adic-cohomology/GPUFiniteFieldMatrices.jl, MIT.
- Not in the Julia General registry (the registry holds no
  `G/GPUFiniteFieldMatrices` entry), so Pkg adds it by URL and tag.
- `Project.toml` compat: `julia = "1.12"`, `CUDA = "5, 6"`,
  `DispatchDoctor = "0.4.28"`, `IterTools = "1"`, `SparseArrays = "1.12.0"`,
  `Unroll = "0.1.0"`. Nothing beyond CUDA.jl needs a system library; CUDA.jl
  fetches its own CUDA runtime artifacts unless told to use the local toolkit.
- `pluq_batched!`, `pluq_batched`, `inverse_batched` and
  `LinearAlgebra.rank` exist; `src/CuModMatrix/inverse/api.jl` sets
  `_PLUQ_MAX_SAFE_MODULUS = typemax(Int32)`, and a larger modulus raises.

## Setup (per user, on a host with an NVIDIA driver)

```sh
sudo pacman -S julia                  # 1.13.x satisfies julia = "1.12"
mkdir -p "$HOME/julia-envs/gffm" && cd "$HOME/julia-envs/gffm"
julia --project=. -e '
  using Pkg
  Pkg.add(url="https://github.com/p-adic-cohomology/GPUFiniteFieldMatrices.jl",
          rev="v0.4.0")
  Pkg.instantiate()
  Pkg.precompile()
  using CUDA; CUDA.versioninfo()
'
```

`Pkg.add` writes `Project.toml` and `Manifest.toml` into the environment
directory. The manifest is the pin: it fixes the package commit and every
CUDA.jl artifact version. Keep it with the work that cites the library and
record its sha256 there (`sha256sum Manifest.toml`). Restore it later with
`julia --project=. -e 'using Pkg; Pkg.instantiate()'`. A manifest from this
setup does not exist in this repository: generating it needs a GPU host and
network access, which the session that wrote this file did not have.

## Smoke test

```sh
julia --project=. -e '
  using GPUFiniteFieldMatrices, LinearAlgebra
  A = CuModMatrix(rand(0:30, 64, 64); modulus = 31)
  println(rank(A))
'
```
