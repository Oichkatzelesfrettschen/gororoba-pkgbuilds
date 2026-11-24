"""Offline checks: the pinned Qiskit 0.43 API that qiskit-debugger imports."""

import unittest
from importlib.metadata import version


class StackTest(unittest.TestCase):
    def test_versions(self) -> None:
        for dist, wanted in {
            "qiskit": "0.43.2",
            "qiskit-terra": "0.24.1",
            "qiskit-aer": "0.12.1",
            "qiskit-debugger": "0.1.2",
        }.items():
            self.assertEqual(version(dist), wanted)

    def test_legacy_execute_on_aer(self) -> None:
        from qiskit import Aer, QuantumCircuit, execute

        circuit = QuantumCircuit(1, 1)
        circuit.x(0)
        circuit.measure(0, 0)
        counts = execute(circuit, Aer.get_backend("qasm_simulator"), shots=64, seed_simulator=1).result().get_counts()
        self.assertEqual(counts, {"1": 64})

    def test_debugger_imports(self) -> None:
        from qiskit_debugger import QCDebugger, QuantumDebugCircuit

        self.assertTrue(issubclass(QuantumDebugCircuit, __import__("qiskit").QuantumCircuit))
        self.assertTrue(callable(QCDebugger))
