# Qxelarator on CPython 3.13

The package installs Qxelarator 0.10.0 in `/opt/qxelarator-python313`
and exposes `qxelarator-python`. The launcher selects the package's isolated
interpreter; the native CPython 3.13 extension stays separate from the host's
Python 3.14 ABI and from Quantum Inspire's existing user environment.

PyPI and GitHub both identify 0.10.0 as the latest stable release at the
2026-10-22 UTC audit. Git tag `0.10.0` resolves to commit
`94ed74a2652d90707e41ef1e4df14744f1ca6c57`. The PKGBUILD retains the official
Linux x86_64 CPython 3.13 wheel, SHA-256
`112e50a4f42267424a3540b19007eb3216528eeedc426d0e9adae069989acbd2`.
The package disables binary stripping and removes the wheel's stale upstream Conan
build-directory RUNPATH. The native ELF therefore differs from the published
artifact by that explicit sanitation; its RECORD hash is regenerated.
The five unittest cases and `bell_pair.cq` are unchanged upstream files from
`test/qxelarator/` at the pinned commit. The tests cover file execution,
string execution, malformed input, deterministic seeding, and the Rn gate.

Build and install:

```sh
makepkg --cleanbuild
SUDO_ASKPASS=/usr/bin/unified-askpass sudo -A pacman -U ./qxelarator-python313-0.10.0-2-x86_64.pkg.tar.zst
export PYTHON=/usr/bin/qxelarator-python
"$PYTHON" -m unittest discover -v -s /usr/share/qxelarator-python313/tests
"$PYTHON" -c 'import qxelarator; print(qxelarator.__file__)'
```

`qxelarator-python` accepts normal interpreter arguments. Local execution
uses the packaged extension and requires neither credentials nor cloud access.
The installed package provides a separate local-emulator interpreter; exporting
that interpreter as `QI_PYTHON` would omit the Quantum Inspire SDK, libqasm and
OpenSquirrel packages required by the full provider stack. Keep the existing
full-stack `QI_PYTHON` binding for those operations.

The current isolated Quantum Inspire environment already contains 0.10.0;
all eight non-RECORD wheel members matched the freshly downloaded artifact
byte for byte. The package installation adds reproducible package ownership;
it does not claim an upstream version increase or repair the release's known
reset/measurement-register semantics. A local emulator remains a syntax and
encoding witness rather than Tuna hardware evidence.

Rollback the added isolated runtime with
`SUDO_ASKPASS=/usr/bin/unified-askpass sudo -A pacman -R qxelarator-python313`.
The Quantum Inspire user environment remains independently managed.

Package-level `namcap` does not model an isolated `/opt` Python 3.13 runtime:
it reports the ELF placement and the absence of a host `python` dependency.
The interpreter symlink resolves `/usr/bin/python3.13`, owned by `python313`,
and installed upstream tests qualify that declared dependency directly.
The published ELF remains unstripped and lacks full RELRO; sanitizing its
RUNPATH does not add linker hardening. The generated SWIG wrapper also retains
a Python-2 `__builtin__` fallback, and the prebuilt ELF retains an unused
pthread dependency. These upstream properties remain explicit limitations;
the recipe and installed-runtime checks do not constitute a clean binary
hardening audit or a source-build qualification.
