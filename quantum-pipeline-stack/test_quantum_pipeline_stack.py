"""Offline checks of the quantum-pipeline closure; no Kafka or registry is contacted."""

import unittest
from importlib.metadata import version


class StackTest(unittest.TestCase):
    def test_versions(self) -> None:
        for dist, wanted in {
            "quantum-pipeline": "2.5.1",
            "qiskit": "2.6.1",
            "qiskit-aer": "0.17.2",
            "qiskit-nature": "0.8.0",
        }.items():
            self.assertEqual(version(dist), wanted)

    def test_aer_estimator(self) -> None:
        from qiskit import QuantumCircuit
        from qiskit.quantum_info import SparsePauliOp
        from qiskit_aer.primitives import EstimatorV2

        circuit = QuantumCircuit(1)
        circuit.x(0)
        value = EstimatorV2().run([(circuit, SparsePauliOp("Z"))]).result()[0].data.evs
        self.assertAlmostEqual(float(value), -1.0)

    def test_pipeline_imports(self) -> None:
        import quantum_pipeline  # noqa: F401
