"""Offline validation of the BluQubit client installed by this package.

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
    import bluequbit

    if md.version("bluequbit") != "0.19.0b1" or bluequbit.version.__version__ != "0.19.0b1":
        raise AssertionError(md.version("bluequbit"))


def test_pauli_sum_parser() -> None:
    from bluequbit.tools import parse_pauli_sum_str

    if parse_pauli_sum_str("0.5*XZ+YY") != [("XZ", 0.5), ("YY", 1.0)]:
        raise AssertionError(parse_pauli_sum_str("0.5*XZ+YY"))


def test_client_entry_points() -> None:
    import bluequbit

    if not callable(bluequbit.init) or not isinstance(bluequbit.BQClient, type):
        raise AssertionError
