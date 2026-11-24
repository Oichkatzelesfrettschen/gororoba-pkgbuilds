"""Offline validation of the Quafu client installed by this package.

Every test runs without network access or credentials: it checks the pinned
distribution set and exercises one local object construction or pure function.
"""

from __future__ import annotations

import importlib.metadata as md
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
LOCK = HERE / "requirements.lock"


def pins(path: pathlib.Path) -> dict[str, str]:
    out = {}
    for line in path.read_text().splitlines():
        m = re.match(r"^([A-Za-z0-9_.-]+)(?:\[[^\]]*\])?==([^\s;\\]+)", line)
        if m:
            out[m.group(1).lower().replace("_", "-")] = m.group(2)
    return out


def test_interpreter() -> None:
    if sys.version_info[:2] != (3, 11):
        raise AssertionError(sys.version)


def test_lock_installed_exactly() -> None:
    wrong = {n: (md.version(n), v) for n, v in pins(LOCK).items() if md.version(n) != v}
    if wrong:
        raise AssertionError(wrong)


def test_pip_check() -> None:
    r = subprocess.run([sys.executable, "-m", "pip", "check"], capture_output=True, text=True, check=False)
    if r.returncode != 0:
        raise AssertionError(r.stdout + r.stderr)


def test_pinned_versions() -> None:
    if md.version("pyquafu") != "0.4.5" or md.version("numpy") != "1.26.4":
        raise AssertionError((md.version("pyquafu"), md.version("numpy")))


def test_bell_circuit_openqasm() -> None:
    from quafu import QuantumCircuit

    qc = QuantumCircuit(2)
    qc.h(0)
    qc.cnot(0, 1)
    qc.measure([0, 1])
    qasm = qc.to_openqasm()
    for line in ("OPENQASM 2.0;", "qreg q[2];", "h q[0];", "cx q[0],q[1];"):
        if line not in qasm:
            raise AssertionError(qasm)
