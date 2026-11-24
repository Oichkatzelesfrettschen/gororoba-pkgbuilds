"""Offline validation of the Kaggle Benchmarks library installed by this package.

Every test runs without network access or credentials. BENCHMARK_MODE=TESTING
is set before the library import so the default client stays in memory and
the UI does not start.
"""

from __future__ import annotations

import importlib.metadata as md
import os
import pathlib
import re
import subprocess
import sys

os.environ["BENCHMARK_MODE"] = "TESTING"
os.environ["BENCHMARK_CONSOLE_UI"] = "False"
os.environ["INTERACTIVE_UI"] = "False"

HERE = pathlib.Path(__file__).resolve().parent
LOCK = HERE / "requirements.lock"


def pins(path: pathlib.Path) -> dict[str, str]:
    out = {}
    for line in path.read_text().splitlines():
        match = re.match(r"^([A-Za-z0-9_.-]+)(?:\[[^\]]*\])?==([^\s;\\]+)", line)
        if match:
            out[match.group(1).lower().replace("_", "-")] = match.group(2)
    return out


def test_interpreter() -> None:
    if sys.version_info[:2] != (3, 14):
        raise AssertionError(sys.version)


def test_lock_installed_exactly() -> None:
    wrong = {n: (md.version(n), v) for n, v in pins(LOCK).items() if md.version(n) != v}
    if wrong:
        raise AssertionError(wrong)


def test_pip_check() -> None:
    result = subprocess.run([sys.executable, "-m", "pip", "check"], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise AssertionError(result.stdout + result.stderr)


def test_pinned_version() -> None:
    import kaggle_benchmarks

    if md.version("kaggle-benchmarks") != "0.6.3" or kaggle_benchmarks.__version__ != "0.6.3":
        raise AssertionError(md.version("kaggle-benchmarks"))


def test_task_registers_without_a_provider() -> None:
    import kaggle_benchmarks as kbench

    # No return annotation: the decorator then uses PassFail. A bool
    # annotation is not one of the keys in results.types.
    @kbench.task(name="two_plus_two", store_task=False)
    def two_plus_two():  # type: ignore[no-untyped-def]
        return 2 + 2 == 4

    registered = kbench.client.registry["two_plus_two"]
    if registered.name != "two_plus_two" or registered.func() is not True:
        raise AssertionError(registered.name)
