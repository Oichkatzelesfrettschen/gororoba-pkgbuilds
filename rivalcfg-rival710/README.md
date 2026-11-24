# rivalcfg-rival710

A drop-in replacement for upstream `rivalcfg` that splits the **SteelSeries
Rival 710** (1038:1730) into its own device profile so that 710-specific
features can be added independently of the Rival 700.

## Status

**Phase 1 scaffold.** This release ships *only* the file-split refactor.
Stock `rivalcfg` and this fork expose the same settings for the Rival 710:

- `--sensitivity1` / `--sensitivity2` — DPI presets
- `--polling-rate`
- `--logo-color` (two-zone RGB)
- `--wheel-color` (two-zone RGB — see [upstream issue #189][i189])
- `--save`
- `--print-debug` reports firmware version

What rivalcfg-rival710 makes possible (future bumps): tactile button
mapping ([upstream WIP PR #133][p133]), OLED display, lift-off distance,
sleep timeout, onboard profile slots, full button/wheel remapping, accel /
decel / angle-snapping / smoothing.

Each future setting will land here only after end-to-end verification
against the physical hardware per the [wiggly-catmull verification
protocol][plan] (capture under SteelSeries GG → compare wire bytes →
dry-run via `RIVALCFG_DRY=1` → live test → power-cycle persistence
check).

## Installation

```sh
makepkg -si
```

This replaces stock `rivalcfg`. To revert:

```sh
sudo pacman -S extra/rivalcfg
```

## Files

- `PKGBUILD` — build recipe
- `rival710.py` — new device profile (drop-in to `rivalcfg/devices/`)
- `rival700.py.patch` — diff removing the 710 entry from
  `devices/rival700.py`
- `commands.md` — protocol synthesis: confirmed, WIP, and field-exists
  command IDs with evidence sources
- `rival710-probe.py` — staging harness for verifying new commands
  against the physical mouse one at a time (do not run before reading
  the brick-prevention rules in `commands.md` and the wiggly-catmull
  plan §8c)

## Coexistence with steelseries-rival710-stack

The sibling `steelseries-rival710-stack` package targets *kernel-side*
input handling (udev, the `BTN_FORWARD` filter daemon, the wheel-quirks
HID-BPF). This package targets *user-space firmware configuration*. No
filesystem overlap. The stack ships under `/usr/lib/udev`,
`/usr/lib/systemd`, `/usr/lib/firmware/hid/bpf`; this fork ships
pure-Python under `/usr/lib/python*/site-packages/rivalcfg`.

## Upstream contribution

This fork's first PR back to `flozz/rivalcfg` is the file-split refactor
itself (zero behavior change). Each verified new setting becomes its own
follow-up PR with the captured pcap excerpt as evidence.

[i189]: https://github.com/flozz/rivalcfg/issues/189
[p133]: https://github.com/flozz/rivalcfg/pull/133
[plan]: ~/.claude/plans/build-a-plan-for-wiggly-catmull.md
