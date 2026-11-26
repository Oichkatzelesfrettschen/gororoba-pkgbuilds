# python-linac

Recipe for linac 1.0.1 (GPL-3.0-only), the GPU row reduction library of
Giuseppe De Laurentis. The package installs the CPU routes and the CUDA
sources; the GPU route needs `python-pycuda` and `cuda` (nvcc at run time).

## Dependencies

- `python-pyadic` is in this repository; `python-pycoretools` and
  `python-syngular` are new recipes beside this one.
- `python-multiset` (a dependency of syngular) and `python-galois` (an
  optional reference field) are AUR-only; no recipe here provides them.
- Upstream pins `numpy<2.0` in its wheel metadata. The recipe builds against
  the system NumPy and leaves that metadata as upstream wrote it; the CPU
  `check()` is the evidence that the CPU routes run under the system NumPy.
  The GPU route is not exercised under NumPy 2.

## Known defect: wide matrices (source reading confirmed, not observed on one GPU)

`linac/pycuda_row_reduce.py` launches `ConditionalRescaleRow` with ceil(N / 1,024) blocks of equal width
(`pycuda_tools.py`, `number_of_foldings` and `folded_number_of_columns`), so 1,100 columns run as two blocks of
550. Thread 0 of every block reads the pivot `Matrix[i * NbrColumns + j]` from global memory, the block that owns
column `j` writes the rescaled pivot (1) back, and the only barrier, `__syncthreads()`, orders threads within one
block. A block that reads after that write inverts 1 and leaves its chunk unscaled.

Measured on 2026-11-26 (RTX 4090 Laptop GPU, driver 610.74, nvcc 13.1.115, Python 3.12.16 in a venv, linac 1.0.1,
numpy 1.26.4, pycuda 2026.1, python-flint 0.9.0; single session):

- Race test: 64 rows by N columns, N in {1,000, 1,100, 3,000}, primes 32003, 9223372036854775783 and
  18446744073709551557, two matrix shapes, 300 repetitions per cell (5,400 GPU reductions): every GPU result equals
  `python-flint` `nmod_mat.rref`, and at 32003 the CPU route agrees too (its int64 products overflow at the two
  large primes, so it was not run there). The race did not occur on this device.
- Calibration: a copy whose non-owner blocks sleep 200 microseconds before reading the pivot fails 20 of 20 runs at
  1,100 columns, so the test detects the defect when the read follows the write.
- Rank: 1,000 matrices of size 64 by 64 over 32003, 300 of them rank-deficient by construction: 0 disagreements with
  `python-flint`; the GPU route took 84.4 s in all (about 84 ms a matrix with the compiled kernel cached; stock
  linac recompiles with nvcc on every call) against 0.75 s for `python-flint`.
- NumPy below 2 has no wheel for Python 3.14, so the GPU route ran under Python 3.12 in a venv; under the system
  Python and NumPy 2 the GPU route stays unexercised.

The recipe changes nothing in the sources. The retained scripts and logs are in gororoba-math
`local/a5-tower/research/linac-gpu/` (not tracked).
