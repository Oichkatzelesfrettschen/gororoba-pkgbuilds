#!/usr/bin/env python3
"""rival710-probe.py — send one candidate command to the Rival 710 and observe.

This is a *staging* harness for verifying new HID command IDs end-to-end
before they are added to ``rival710.py``.  Do **not** run blindly.  Read
``commands.md`` and ``wiggly-catmull §8c`` (brick-prevention rules) first.

The Rival 710 firmware accepts commands on Interface 0 (hidraw1, vendor
usage page 0xFFC0).  This script opens that interface explicitly and
sends one command at a time.  It is designed to be used alongside
``tshark -i usbmonN -Y 'usb.idVendor == 0x1038'`` so each send can be
correlated with a captured pcap frame.

Safe defaults:
- Default action is the firmware-version query (``[0x10, 0x00]``) -- the
  least invasive probe the firmware supports.  If it stops returning the
  expected 2-byte response, stop testing immediately and recover.
- ``--save`` is NOT issued automatically.  Save-to-flash uses NOR with a
  finite ~100k erase budget; explicit ``--save`` only.
- Unknown command IDs require ``--unsafe`` to actually send.  This is to
  prevent typos from bricking firmware via undocumented sub-commands.

Usage::

    # Safe: query firmware version (returns 2 bytes)
    python3 rival710-probe.py --query-firmware

    # Send a known-good command (DPI preset 1 = 800)
    python3 rival710-probe.py --cmd 0x03 --byte2 0x00 --byte3 0x01 \\
                              --payload 0x00 --suffix 0x00,0x42

    # Probe an unverified command (tactile feedback, PR #133)
    python3 rival710-probe.py --unsafe --cmd 0x92 --byte2 0x00 \\
                              --buf-size 28 --buf-offset 1 --buf-value 0x04
"""

from __future__ import annotations

import argparse
import sys
import time

try:
    import hid
except ImportError:
    sys.exit("python-hidapi not available; install python-hidapi")


VENDOR_ID = 0x1038
PRODUCT_ID = 0x1730
COMMAND_INTERFACE = 0


def open_command_interface() -> "hid.device":
    """Open Interface 0 (vendor-control) on the first Rival 710 attached."""
    for info in hid.enumerate(VENDOR_ID, PRODUCT_ID):
        if info["interface_number"] == COMMAND_INTERFACE:
            dev = hid.device()
            dev.open_path(info["path"])
            return dev
    raise SystemExit(
        f"Rival 710 ({VENDOR_ID:04x}:{PRODUCT_ID:04x}) interface "
        f"{COMMAND_INTERFACE} not found"
    )


def send_output(dev: "hid.device", payload: bytes) -> int:
    """Send an HID OUTPUT report.  payload[0] is the command id."""
    # hidapi expects a leading report id byte 0x00 for non-numbered reports
    buf = bytes([0x00]) + payload
    return dev.write(buf)


def send_feature(dev: "hid.device", payload: bytes) -> int:
    """Send an HID FEATURE report (SET_REPORT 0x09 / report type 3)."""
    buf = bytes([0x00]) + payload
    return dev.send_feature_report(list(buf))


def query_firmware(dev: "hid.device") -> bytes:
    """Send [0x10, 0x00] OUTPUT and read 2-byte response.

    This is the standard health-check.  If it does not return ~2 bytes,
    the device is in an unexpected state -- stop testing.
    """
    send_output(dev, bytes([0x10, 0x00]))
    time.sleep(0.05)
    return bytes(dev.read(2, timeout_ms=500))


def build_payload(args: argparse.Namespace) -> bytes:
    """Construct a command payload from argparse fields.

    --cmd / --byte2 / --byte3 / --payload set the leading bytes.  If
    --buf-size is given a zero-filled buffer of that size is appended and
    the value at --buf-offset is set to --buf-value (for testing
    PR-style multi-byte payloads like tactile feedback).
    """
    head = []
    if args.cmd is not None:
        head.append(args.cmd)
    if args.byte2 is not None:
        head.append(args.byte2)
    if args.byte3 is not None:
        head.append(args.byte3)
    if args.payload:
        head.extend(args.payload)

    if args.buf_size:
        body = bytearray(args.buf_size)
        if args.buf_offset is not None and args.buf_value is not None:
            body[args.buf_offset] = args.buf_value
        head.extend(body)

    if args.suffix:
        head.extend(args.suffix)

    return bytes(head)


def parse_hex_list(s: str) -> list[int]:
    return [int(x, 0) for x in s.split(",") if x.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--query-firmware",
        action="store_true",
        help="Send the safe firmware-version probe and exit",
    )
    parser.add_argument(
        "--unsafe",
        action="store_true",
        help="Allow command IDs outside the known-safe whitelist",
    )
    parser.add_argument(
        "--feature",
        action="store_true",
        help="Send as FEATURE report (default is OUTPUT)",
    )
    parser.add_argument("--cmd", type=lambda x: int(x, 0), default=None)
    parser.add_argument("--byte2", type=lambda x: int(x, 0), default=None)
    parser.add_argument("--byte3", type=lambda x: int(x, 0), default=None)
    parser.add_argument(
        "--payload",
        type=parse_hex_list,
        default=[],
        help="Extra leading bytes after cmd/byte2/byte3, comma-separated",
    )
    parser.add_argument(
        "--buf-size",
        type=int,
        default=0,
        help="Zero-fill a buffer of this size after the head bytes",
    )
    parser.add_argument(
        "--buf-offset",
        type=lambda x: int(x, 0),
        default=None,
        help="Within the buffer, set this offset",
    )
    parser.add_argument(
        "--buf-value",
        type=lambda x: int(x, 0),
        default=None,
        help="Value for the buffer offset",
    )
    parser.add_argument(
        "--suffix",
        type=parse_hex_list,
        default=[],
        help="Trailing bytes appended after the buffer",
    )
    parser.add_argument(
        "--save",
        action="store_true",
        help="After the command, send [0x09, 0x00] to commit to flash"
        " -- only when intentionally persisting",
    )
    args = parser.parse_args()

    safe_cmds = {0x03, 0x04, 0x05, 0x09, 0x10}  # verified-upstream
    if args.cmd is not None and args.cmd not in safe_cmds and not args.unsafe:
        sys.exit(
            f"command 0x{args.cmd:02x} is not in the safe whitelist "
            f"{{0x03,0x04,0x05,0x09,0x10}}; pass --unsafe to override"
        )

    dev = open_command_interface()
    try:
        fw = query_firmware(dev)
        print(f"firmware probe returned {len(fw)} bytes: {fw.hex()}")

        if args.query_firmware:
            return 0

        if args.cmd is None:
            sys.exit("no --cmd given (and --query-firmware not set)")

        payload = build_payload(args)
        if args.feature:
            n = send_feature(dev, payload)
            print(f"FEATURE 0x{args.cmd:02x}: sent {n} bytes ({len(payload)+1} requested)")
        else:
            n = send_output(dev, payload)
            print(f"OUTPUT 0x{args.cmd:02x}: sent {n} bytes ({len(payload)+1} requested)")

        time.sleep(0.05)

        if args.save:
            print("save: sending [0x09, 0x00] OUTPUT")
            send_output(dev, bytes([0x09, 0x00]))
            time.sleep(0.1)

        fw_after = query_firmware(dev)
        print(f"post-send firmware probe returned {len(fw_after)} bytes: {fw_after.hex()}")
    finally:
        dev.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
