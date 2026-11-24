"""
The "oled_image" handler ships a monochrome image to the Rival 710's
128x36 OLED via a 578-byte HID FEATURE report.

Packet layout (matches `openrival_tools.Rival710OLED.build_oled_packet`):

* byte 0: 0x61 (command id; supplied by `setting_info["command"]`)
* bytes 1-576: pixel data, MSB-first, row-major; bit_index =
  `x + (y * 128) + 8` (the +8 skips byte 0)
* byte 577: 0x00 (trailer)

CLI accepts a path to any image PIL can open, or one of the keywords
``clear`` / ``off`` (all pixels off), ``fill`` / ``on`` (all pixels on).

This handler is the cleanroom port of the Rival710OLED class verified to
send 576 bytes successfully on this user's Rival 710 firmware 0.114 in
the December 2025 openrival-tools session.  Visual confirmation that the
device renders 128x36 (vs 128x40 truncated) is pending.

Device Profile
--------------

::

    profile = {
        "settings": {
            "oled_image": {
                "label": "OLED display image",
                "description": "Upload an image to the 128x36 OLED",
                "cli": ["-o", "--oled-image"],
                "report_type": usbhid.HID_REPORT_TYPE_FEATURE,
                "command": [0x61],
                "value_type": "oled_image",
                "image_width": 128,
                "image_height": 36,
                "packet_size": 578,
            },
        },
    }
"""

import os


DISPLAY_WIDTH = 128
DISPLAY_HEIGHT = 36
PACKET_SIZE = 578
PIXEL_DATA_BYTES = PACKET_SIZE - 2  # 576 (1 byte command + 576 px + 1 byte trailer)


def _empty_payload() -> list:
    """Return PIXEL_DATA_BYTES zeros + 1 trailer (577 bytes total)."""
    return [0x00] * (PIXEL_DATA_BYTES + 1)


def _full_payload() -> list:
    """Return all-on pixel block + zero trailer (577 bytes total)."""
    return [0xFF] * PIXEL_DATA_BYTES + [0x00]


def _image_to_payload(image, width, height) -> list:
    """Encode a PIL Image into the 577-byte payload (576 px + trailer).

    Pixel ordering: row-major, MSB-first.  The bit_index formula
    `x + (y * 128) + 8` from openrival_tools is preserved here.  That +8
    offset means the *first* pixel sets bit 0 of byte 1 (not byte 0),
    because byte 0 carries the command id supplied separately by rivalcfg.
    """
    try:
        from PIL import Image  # type: ignore
    except ImportError as exc:
        raise RuntimeError(
            "Pillow (python-pillow) is required for --oled-image; install it"
        ) from exc

    if hasattr(image, "size"):
        img = image
    else:
        img = Image.open(image)

    if img.size != (width, height):
        img = img.resize((width, height))
    if img.mode != "1":
        img = img.convert("1")

    payload = bytearray(PIXEL_DATA_BYTES + 1)
    for y in range(height):
        for x in range(width):
            if img.getpixel((x, y)):
                bit_index = x + (y * width) + 8
                byte_index = (bit_index // 8) - 1  # -1: command byte is upstream
                if 0 <= byte_index < PIXEL_DATA_BYTES:
                    payload[byte_index] |= 1 << (7 - (bit_index % 8))

    return list(payload)


def process_value(setting_info, value):
    """Convert a CLI value to the bytes appended after `command`.

    :param dict setting_info: The setting's profile dict
    :param value: A path to an image, or one of "clear"/"off"/"fill"/"on"
    :rtype: list[int]
    """
    width = setting_info.get("image_width", DISPLAY_WIDTH)
    height = setting_info.get("image_height", DISPLAY_HEIGHT)

    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in ("clear", "off", ""):
            return _empty_payload()
        if lowered in ("fill", "on"):
            return _full_payload()
        if os.path.exists(value):
            return _image_to_payload(value, width, height)
        raise ValueError(
            "--oled-image expected a file path, 'clear'/'off', or "
            f"'fill'/'on'; got {value!r}"
        )

    return _image_to_payload(value, width, height)


def add_cli_option(cli_parser, setting_name, setting_info):
    description = setting_info["description"] + (
        ".  Accepts a path to any image (PNG/JPG/PGM/etc), or one of the "
        "keywords 'clear'/'off' (all pixels off) and 'fill'/'on' (all "
        "pixels on)."
    )
    cli_parser.add_argument(
        *setting_info["cli"],
        dest=setting_name,
        help=description,
        type=str,
        metavar=setting_name.upper(),
    )
