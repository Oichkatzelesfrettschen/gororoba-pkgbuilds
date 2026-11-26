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

## Known defect: wide matrices (source reading, GPU test owed)

`linac/row_reduce.cu` launches `ConditionalRescaleRow` with one block per
1,024 columns. Every block of the launch computes the inverse of the pivot
`Matrix[i * NbrColumns + j]` from global memory and multiplies its own
chunk. The block that owns column `j` also overwrites the pivot with 1, and
no barrier orders that write against the reads of the other blocks. A later
block that reads the pivot after the write inverts 1 and leaves its chunk
unscaled. The window is a race, so a wrong result is intermittent and appears
only above 1,024 columns. The 1,024 to 3,072 column tests of upstream
`tests/test_row_reduce_random_cuda.py` pass when the blocks read before the
write.

Discriminating test (run on a GPU): reduce a matrix over an odd prime whose
rows each begin with 2 at the pivot column and end with 2 in the last column,
at 1,100 and 3,000 columns, a few hundred repetitions. The reduced pivot row
holds 1 at both ends; a 2 in the last column is the defect.

The recipe changes nothing in the sources.
