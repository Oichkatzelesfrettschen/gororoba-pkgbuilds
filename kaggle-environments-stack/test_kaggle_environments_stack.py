"""Offline validation of the Kaggle Environments library installed by this package.

Every test runs without network access or credentials. SDL uses its dummy
drivers so a pygame import does not need a display.
"""

from __future__ import annotations

import importlib.metadata as md
import os
import pathlib
import re
import subprocess
import sys

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")

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
    if sys.version_info[:2] != (3, 13):
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
    import kaggle_environments

    if md.version("kaggle-environments") != "1.33.3" or kaggle_environments.__version__ != "1.33.3":
        raise AssertionError(md.version("kaggle-environments"))


def test_connectx_random_episode() -> None:
    from kaggle_environments import make

    env = make("connectx")
    steps = env.run(["random", "random"])
    statuses = [agent.status for agent in steps[-1]]
    if statuses != ["DONE", "DONE"]:
        raise AssertionError((len(steps), statuses))


def test_open_spiel_tic_tac_toe() -> None:
    import pyspiel

    game = pyspiel.load_game("tic_tac_toe")
    state = game.new_initial_state()
    if game.num_players() != 2 or state.is_terminal():
        raise AssertionError((game.num_players(), state.is_terminal()))
