#!/bin/sh
set -eu

tool_name=$(basename "$0")
exec "/usr/share/semgrep-source/venv/bin/${tool_name}" "$@"
