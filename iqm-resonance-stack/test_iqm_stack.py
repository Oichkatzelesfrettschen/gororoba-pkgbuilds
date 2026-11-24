"""Offline validation of the IQM Resonance client stack installed by this package.

Every test runs without network access or credentials: it checks the pinned
distribution set, the Qiskit and Cirq integrations against IQM's fake
backends, and the IQM Server URL rules the client enforces.
"""

from __future__ import annotations

import importlib.metadata as md
import pathlib
import re
import subprocess
import sys
from typing import Any

import pytest

HERE = pathlib.Path(__file__).resolve().parent
CONSTRAINTS = HERE / "constraints-iqm-qccsw-4.7.0.txt"
LOCK = HERE / "requirements.lock"


def pins(path: pathlib.Path) -> dict[str, str]:
    out = {}
    for line in path.read_text().splitlines():
        m = re.match(r"^([A-Za-z0-9_.-]+)(?:\[[^\]]*\])?==([^\s;\\]+)", line)
        if m:
            out[m.group(1).lower().replace("_", "-")] = m.group(2)
    return out


def test_interpreter_is_313() -> None:
    if sys.version_info[:2] != (3, 13):
        raise AssertionError(sys.version)


@pytest.mark.parametrize("name,version", sorted(pins(CONSTRAINTS).items()))  # type: ignore[untyped-decorator, unused-ignore]
def test_constraints_installed(name: str, version: str) -> None:
    if md.version(name) != version:
        raise AssertionError((name, md.version(name), version))


def test_lock_installed_exactly() -> None:
    wrong = {n: (md.version(n), v) for n, v in pins(LOCK).items() if md.version(n) != v}
    if wrong:
        raise AssertionError(wrong)


def test_pip_check() -> None:
    r = subprocess.run([sys.executable, "-m", "pip", "check"], capture_output=True, text=True, check=False)
    if r.returncode != 0:
        raise AssertionError(r.stdout + r.stderr)


def test_imports() -> None:
    import iqm.benchmarks  # noqa: F401
    import iqm.cirq_iqm  # noqa: F401
    import iqm.cpc  # noqa: F401
    import iqm.data_definitions  # noqa: F401
    import iqm.error_reduction_tools  # noqa: F401
    import iqm.iqm_client  # noqa: F401
    import iqm.pulse  # noqa: F401
    import iqm.qaoa  # noqa: F401
    import iqm.qiskit_iqm  # noqa: F401
    import iqm.qrisp_iqm  # noqa: F401
    import iqm.qubit_selector  # noqa: F401
    import iqm.station_control.client  # noqa: F401


def bell() -> Any:
    from qiskit import QuantumCircuit

    qc = QuantumCircuit(2)
    qc.h(0)
    qc.cx(0, 1)
    qc.measure_all()
    return qc


def native_ops(circuit: Any) -> set[str]:
    return {inst.operation.name for inst in circuit.data}


def test_crystal_transpile_and_simulate() -> None:
    from iqm.qiskit_iqm import transpile_to_IQM
    from iqm.qiskit_iqm.fake_backends.fake_garnet import IQMFakeGarnet

    backend = IQMFakeGarnet()
    if backend.num_qubits != 20:
        raise AssertionError(backend.num_qubits)
    isa = transpile_to_IQM(bell(), backend, seed_transpiler=7)
    extra = native_ops(isa) - {"r", "cz", "measure", "barrier"}
    if extra:
        raise AssertionError(extra)
    counts = backend.run(isa, shots=2000, seed_simulator=11).result().get_counts()
    correlated = counts.get("00", 0) + counts.get("11", 0)
    if correlated < 1800:
        raise AssertionError(counts)


def test_star_move_routing() -> None:
    from iqm.qiskit_iqm import transpile_to_IQM
    from iqm.qiskit_iqm.fake_backends import IQMFakeDeneb
    from qiskit import QuantumCircuit

    backend = IQMFakeDeneb()
    qc = QuantumCircuit(3)
    qc.h(0)
    qc.cx(0, 1)
    qc.cx(0, 2)
    isa = transpile_to_IQM(qc, backend, seed_transpiler=3)
    if "move" not in native_ops(isa):
        raise AssertionError(native_ops(isa))


def test_final_rz_kept_by_default() -> None:
    from iqm.qiskit_iqm import transpile_to_IQM
    from iqm.qiskit_iqm.fake_backends.fake_garnet import IQMFakeGarnet
    from qiskit import QuantumCircuit

    qc = QuantumCircuit(1)
    qc.h(0)
    qc.rz(0.3, 0)
    kept = transpile_to_IQM(qc, IQMFakeGarnet(), seed_transpiler=1)
    dropped = transpile_to_IQM(qc, IQMFakeGarnet(), seed_transpiler=1, remove_final_rzs=True)
    if "rz" in native_ops(dropped) or len(kept.data) <= len(dropped.data):
        raise AssertionError((kept.data, dropped.data))


@pytest.mark.parametrize(  # type: ignore[untyped-decorator, unused-ignore]
    "url,fragment",
    [
        ("http://resonance.iqm.tech", "Insecure HTTP"),
        ("https://cocos.resonance.iqm.tech", "CoCoS API is obsolete"),
        ("https://resonance.iqm.tech/garnet", "must not contain the quantum computer name"),
        # _normalize_url tests the path rule before the timeslot rule.
        ("https://resonance.iqm.tech/garnet:timeslot", "must not contain the quantum computer name"),
    ],
)
def test_server_url_rules(url: str, fragment: str) -> None:
    from iqm.iqm_server_client.iqm_server_client import IQMServerClient

    with pytest.raises(Exception, match=fragment):
        IQMServerClient._normalize_url(url, None)


def test_server_url_base() -> None:
    from iqm.iqm_server_client.iqm_server_client import IQMServerClient

    if IQMServerClient._normalize_url("https://resonance.iqm.tech/", "garnet") != (
        "https://resonance.iqm.tech",
        "garnet",
    ):
        raise AssertionError
