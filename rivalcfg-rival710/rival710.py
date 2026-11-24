"""
SteelSeries Rival 710 device profile (forked from rival700.py).

This profile splits the Rival 710 (1038:1730) out of the upstream
``devices/rival700.py`` so that 710-specific work can land independently of
the Rival 700.  All commands here are the same byte sequences that upstream
ships in 4.17.0 for the 700-family; new 710-only features (tactile, OLED,
lift-off, sleep, profile-slot, etc.) live in ``rival710_extras.py`` and are
gated until verified end-to-end against this user's specific hardware per
``wiggly-catmull §8``.

See ``commands.md`` in the package's source dir for the full protocol map.
"""

from .. import usbhid

# fmt: off
_RGBGRADIENTV2_HEADER = {
    "color_field_length": 139,  # Index of length of color field (used for padding)
    "duration_length": 2,       # Length of the "duration" field (in bytes)
    "maxgradient": 14,          # Max numbers of color stop (probably 14)
}
# fmt: on

_DEFAULT_RGBGRADIENTV2 = (
    "rgbgradient(duration=1000; colors=0%: #ff00e1, 33%: #ffea00, 66%: #00ccff)"
)

profile = {
    "name": "SteelSeries Rival 710",
    "models": [
        {
            "name": "SteelSeries Rival 710",
            "vendor_id": 0x1038,
            "product_id": 0x1730,
            "endpoint": 0,
        },
    ],
    "settings": {
        "sensitivity1": {
            "label": "Sensitivity preset 1",
            "description": "Set sensitivity preset 1 (DPI)",
            "cli": ["-s", "--sensitivity1"],
            "report_type": usbhid.HID_REPORT_TYPE_OUTPUT,
            "command": [0x03, 0x00, 0x01],
            "command_suffix": [0x00, 0x42],
            "value_type": "range",
            "input_range": [100, 12000, 100],
            "output_range": [0x00, 0x77, 1],
            "default": 800,
        },
        "sensitivity2": {
            "label": "Sensitivity preset 2",
            "description": "Set sensitivity preset 2 (DPI)",
            "cli": ["-S", "--sensitivity2"],
            "report_type": usbhid.HID_REPORT_TYPE_OUTPUT,
            "command": [0x03, 0x00, 0x02],
            "command_suffix": [0x00, 0x42],
            "value_type": "range",
            "input_range": [100, 12000, 100],
            "output_range": [0x00, 0x77, 1],
            "default": 1600,
        },
        "polling_rate": {
            "label": "Polling rate",
            "description": "Set polling rate (Hz)",
            "cli": ["-p", "--polling-rate"],
            "report_type": usbhid.HID_REPORT_TYPE_OUTPUT,
            "command": [0x04, 0x00],
            "value_type": "choice",
            "choices": {
                125: 0x04,
                250: 0x03,
                500: 0x02,
                1000: 0x01,
            },
            "default": 1000,
        },
        "logo_color": {
            "label": "Logo LED colors and effects",
            "description": "Set the logo colors and effects",
            "cli": ["-c", "--logo-color"],
            "command": [0x05, 0x00],
            "report_type": usbhid.HID_REPORT_TYPE_FEATURE,
            "value_type": "rgbgradientv2",
            "rgbgradientv2_header": _RGBGRADIENTV2_HEADER,
            "led_id": 0x0,
            "default": _DEFAULT_RGBGRADIENTV2,
        },
        "wheel_color": {
            "label": "Wheel LED colors and effects",
            "description": "Set the wheel colors and effects",
            "cli": ["-C", "--wheel-color"],
            "command": [0x05, 0x00],
            "report_type": usbhid.HID_REPORT_TYPE_FEATURE,
            "value_type": "rgbgradientv2",
            "rgbgradientv2_header": _RGBGRADIENTV2_HEADER,
            "led_id": 0x1,
            "default": _DEFAULT_RGBGRADIENTV2,
        },
        # tactile_button_mapping: WIRE-VERIFIED on this user's Rival 710 fw 0.114.
        # Carries the bytes from flozz/rivalcfg PR #133 (nixtux), which had been
        # WIP since 2020 awaiting hardware verification.  We supplied that
        # verification: see commands.md "Upstream-WIP commands" section + the
        # captures/tactile/tactile-probe-1778609373.pcap frame 2088 evidence.
        "tactile_button_mapping": {
            "label": "Tactile button feedback mapping",
            "description": "Map per-button tactile feedback (haptic motor)",
            "cli": ["-t", "--tactile-mapping"],
            "command": [0x92, 0x00],
            "report_type": usbhid.HID_REPORT_TYPE_OUTPUT,
            "value_type": "tactile_button_map",
        },
        # oled_image: REMOVED 2026-05-12 after NEGATIVE-VERIFIED on hardware.
        # The 0x61 + 578-byte FEATURE bytes that openrival-tools Dec 2025
        # reported as "send_feature_report returned 576 bytes successfully"
        # were a USB-ACK success only; the OLED is unchanged after the
        # write.  See captures/oled-negative/oled-baseline.pcap frame 84
        # for the wire-byte confirmation that our send was structurally
        # correct, and commands.md for the negative-finding entry.
        #
        # The handler module (rivalcfg/handlers/oled_image.py) stays in
        # the fork as infrastructure for when the correct command ID
        # arrives -- the encoding (MSB-first, row-major) is likely
        # correct, only the wire command/transport differs.
        #
        # Next session needs to either Wine-host SteelSeries GG +
        # frida-trace EvalDeviceFunction to capture the real command,
        # or Windows-boot GG with USBPcap to do the same.  Until then,
        # no --oled-image flag is exposed.
    },
    "save_command": {
        "report_type": usbhid.HID_REPORT_TYPE_OUTPUT,
        "command": [0x09, 0x00],
    },
    "firmware_version": {
        "report_type": usbhid.HID_REPORT_TYPE_OUTPUT,
        "command": [0x10, 0x00],
        "response_length": 2,
    },
}
