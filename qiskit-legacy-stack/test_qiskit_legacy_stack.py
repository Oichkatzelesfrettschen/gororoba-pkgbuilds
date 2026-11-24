"""Offline validation of the qiskit-dynamics environment installed by this package.

Every test runs without network access or credentials: it compares the pinned
distribution set with the lock and exercises one local import or computation.
"""

from __future__ import annotations

import importlib.metadata as md
import pathlib
import re
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
LOCK = HERE / "requirements.lock"


def pins(path: pathlib.Path) -> dict[str, str]:
    out = {}
    for line in path.read_text().splitlines():
        m = re.match(r"^([A-Za-z0-9_.-]+)(?:\[[^\]]*\])?==([^\s;\\]+)", line)
        if m:
            out[re.sub(r"[-_.]+", "-", m.group(1)).lower()] = m.group(2)
    return out


class StackTest(unittest.TestCase):
    def test_interpreter(self) -> None:
        self.assertEqual(sys.version_info[:2], (3, 13))

    def test_installed_equals_lock(self) -> None:
        locked = pins(LOCK)
        installed = {
            re.sub(r"[-_.]+", "-", d.metadata["Name"]).lower(): d.version
            for d in md.distributions()
        }
        for name, version in locked.items():
            self.assertEqual(installed.get(name), version, name)

    def test_qiskit_is_pre_two(self) -> None:
        import qiskit

        self.assertEqual(qiskit.__version__, "1.3.0")

    def test_dynamics_signal(self) -> None:
        from qiskit_dynamics import Signal

        self.assertAlmostEqual(abs(Signal(1.0, 5.0)(0.0)), 1.0)


if __name__ == "__main__":
    unittest.main()
