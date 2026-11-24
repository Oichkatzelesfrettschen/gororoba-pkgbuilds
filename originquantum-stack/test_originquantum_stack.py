"""Offline validation of the Origin Quantum pyqpanda3 stack installed by this package.

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
    if sys.version_info[:2] != (3, 13):
        raise AssertionError(sys.version)


def test_lock_installed_exactly() -> None:
    wrong = {n: (md.version(n), v) for n, v in pins(LOCK).items() if md.version(n) != v}
    if wrong:
        raise AssertionError(wrong)


def test_pip_check() -> None:
    r = subprocess.run([sys.executable, "-m", "pip", "check"], capture_output=True, text=True, check=False)
    if r.returncode != 0:
        raise AssertionError(r.stdout + r.stderr)


def test_pinned_version() -> None:
    if md.version("pyqpanda3") != "0.5.1":
        raise AssertionError(md.version("pyqpanda3"))


def test_bell_circuit_on_local_simulator() -> None:
    from pyqpanda3.core import CNOT, CPUQVM, H, QCircuit, QProg, measure

    circuit = QCircuit(2)
    circuit << H(0) << CNOT(0, 1)
    if circuit.count_ops() != {"CNOT": 1, "H": 1} or circuit.depth() != 2:
        raise AssertionError((circuit.count_ops(), circuit.depth()))
    prog = QProg()
    prog << circuit << measure(0, 0) << measure(1, 1)
    machine = CPUQVM()
    machine.run(prog, 1000)
    counts = machine.result().get_counts()
    if set(counts) != {"00", "11"} or sum(counts.values()) != 1000:
        raise AssertionError(counts)
