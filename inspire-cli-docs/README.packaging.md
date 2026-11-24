# DeadmanXXXII/Inspire documentation package

Upstream commit 40301831dac2d804bf692061c27c434be870332f contains README.md and
LICENSE.md. The package preserves both files as documentation. Upstream ships
no executable, Python module, build system, or independent CLI implementation.

README.upstream.md contains legacy examples referring to quantuminspire.qiskit
and token-based QuantumInspireAPI initialization. Treat the examples as historical
reference, rather than executable instructions for the maintained SDK. The
maintained provider imports QIProvider from qiskit_quantuminspire.qi_provider;
quantuminspire-qiskit-stack supplies that provider in a supported Python runtime.

Installation runs no upstream examples and creates no CLI launcher. The official
SDK CLI is available separately as qi-stack. Remove inspire-cli-docs with pacman
to roll back this documentation installation.
