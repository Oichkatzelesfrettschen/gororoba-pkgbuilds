"""Offline validation of the qBraid client stack installed by this package.

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


def test_pinned_versions() -> None:
    got = {n: md.version(n) for n in ("qbraid", "qbraid-core")}
    if got != {"qbraid": "0.13.0", "qbraid-core": "0.6.36"}:
        raise AssertionError(got)


QASM3 = 'OPENQASM 3.0;\ninclude "stdgates.inc";\nqubit[2] q;\nbit[2] c;\nh q[0];\ncx q[0], q[1];\nc = measure q;\n'


def test_qasm3_program_metadata() -> None:
    from qbraid.programs import load_program

    program = load_program(QASM3)
    if (program.num_qubits, program.depth) != (2, 3):
        raise AssertionError((program.num_qubits, program.depth))


def test_qasm3_to_ionq_conversion() -> None:
    from qbraid import transpile

    out = transpile(QASM3, "ionq")
    gates = [(g["gate"], g.get("control"), g["target"]) for g in out["circuit"]]
    if out["qubits"] != 2 or gates != [("h", None, 0), ("cnot", 0, 1)]:
        raise AssertionError(out)
