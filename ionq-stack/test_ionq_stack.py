"""Offline validation of the IonQ Qiskit provider installed by this package.

Every test runs without network access or credentials: it checks the pinned
distribution set and exercises one local object construction or pure function.
"""

from __future__ import annotations

import importlib.metadata as md
import pathlib
import re
import subprocess
import sys
from typing import NoReturn

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


def test_pinned_versions() -> None:
    got = {n: md.version(n)[:1] for n in ("qiskit", "qiskit-ionq")}
    if md.version("qiskit-ionq") != "1.1.1" or got["qiskit"] != "2":
        raise AssertionError({n: md.version(n) for n in got})


def test_provider_and_bell_translation() -> None:
    import socket
    import warnings

    from qiskit import QuantumCircuit
    from qiskit_ionq import IonQProvider
    from qiskit_ionq.helpers import qiskit_circ_to_ionq_circ

    def refuse(*args: object, **kwargs: object) -> NoReturn:
        raise AssertionError("network access")

    real_connect = socket.socket.connect
    socket.socket.connect = refuse  # type: ignore[method-assign]
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            backend = IonQProvider("dummytoken").get_backend("ionq_simulator")
        qc = QuantumCircuit(2)
        qc.h(0)
        qc.cx(0, 1)
        qc.measure_all()
        gates, n_qubits, _ = qiskit_circ_to_ionq_circ(qc)
    finally:
        socket.socket.connect = real_connect  # type: ignore[method-assign]
    if backend.name != "ionq_simulator" or n_qubits != 2:
        raise AssertionError((backend.name, n_qubits))
    if gates != [{"gate": "h", "targets": [0]}, {"gate": "x", "targets": [1], "controls": [0]}]:
        raise AssertionError(gates)
