"""Offline validation of the Planck SDK installed by this package.

Every test runs without network access or credentials: it checks the pinned
distribution set and exercises the client's local validation and the circuit
dataclass; the SDK builds no circuits locally and sends nothing in these tests.
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


def test_pinned_version_and_no_runtime_dependencies() -> None:
    import planck_sdk

    if md.version("planck-sdk") != "1.0.0" or planck_sdk.__version__ != "1.0.0":
        raise AssertionError(md.version("planck-sdk"))
    runtime = [r for r in md.requires("planck-sdk") or [] if "extra ==" not in r]
    if runtime:
        raise AssertionError(runtime)


def test_client_construction_and_key_validation() -> None:
    import pytest
    from planck_sdk import AuthenticationError, PlanckUser

    user = PlanckUser(api_key="dummy_key_0123456789", base_url="https://example.invalid/")
    if user.base_url != "https://example.invalid":
        raise AssertionError(user.base_url)
    with pytest.raises(AuthenticationError):
        PlanckUser(api_key="short")
    with pytest.raises(AuthenticationError):
        PlanckUser(api_key="bad key with spaces!")


def test_circuit_response_roundtrip() -> None:
    from planck_sdk import CircuitBuildOptions, QuantumCircuit

    resp = {"qasm": "// c\nOPENQASM 2.0;\nqreg q[2];\n", "qubits": 2, "depth": 3, "gateCount": 4, "algorithm": "bell"}
    qc = QuantumCircuit.from_api_response(resp)
    if (qc.qubits, qc.depth, qc.gate_count, qc.algorithm) != (2, 3, 4, "bell"):
        raise AssertionError(qc)
    if qc.clean_qasm != "OPENQASM 2.0;\nqreg q[2];":
        raise AssertionError(qc.clean_qasm)
    if CircuitBuildOptions(max_qubits=8, angle_scale=2.0).to_dict() != {"maxQubits": 8, "angleScale": 2.0}:
        raise AssertionError
