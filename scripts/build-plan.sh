#!/bin/sh
# usage: build-plan.sh ALLOWLIST DIR...
# Decides what CI builds for the changed recipe directories DIR.... Prints
# "DIR skipped:not_allowlisted" for a changed recipe absent from ALLOWLIST and
# "DIR build" for each recipe to build, in dependency order. The order is the
# closure of the allowlisted recipes over in-repository dependencies; a closure
# member absent from ALLOWLIST fails the plan before any build starts with
# "closure member not allowlisted: NAME". Exit 0 planned, 1 closure refused,
# 2 usage or an unreadable or empty ALLOWLIST.
set -eu
set -f

here=$(cd -- "$(dirname -- "$0")" && pwd)
if [ "$#" -lt 2 ]; then
    printf 'usage: build-plan.sh ALLOWLIST DIR...\n' >&2
    exit 2
fi
allow=$1
shift
if [ ! -r "$allow" ] || [ ! -s "$allow" ]; then
    printf 'plan=refused reason=allowlist_unreadable_or_empty\n' >&2
    exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' 0 HUP INT TERM
: > "$work/allowed"
for d in "$@"; do
    if grep -qxF -- "$d" "$allow"; then
        printf '%s\n' "$d" >> "$work/allowed"
    else
        printf '%s skipped:not_allowlisted\n' "$d"
    fi
done
if [ ! -s "$work/allowed" ]; then
    exit 0
fi

tr '\n' ' ' < "$work/allowed" > "$work/args"
read -r args < "$work/args"
# shellcheck disable=SC2086
if ! sh "$here/build-order.sh" $args > "$work/order"; then
    printf 'plan=refused reason=build_order_failed\n' >&2
    exit 1
fi
status=0
while IFS= read -r member; do
    if ! grep -qxF -- "$member" "$allow"; then
        printf 'closure member not allowlisted: %s\n' "$member" >&2
        status=1
    fi
done < "$work/order"
if [ "$status" -ne 0 ]; then
    exit 1
fi
while IFS= read -r member; do
    printf '%s build\n' "$member"
done < "$work/order"
