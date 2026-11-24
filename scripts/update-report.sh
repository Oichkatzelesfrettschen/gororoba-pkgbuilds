#!/bin/sh
# usage: update-report.sh UPDATE_TSV
# Turns the update-check.sh table (name current latest status) into a Markdown
# table with one readiness-gate verdict per outdated recipe. The gate's exit
# status stays visible: "(gate exit N)" follows its output, and exit 2 (the
# gate could not run) makes this script exit 1 after the table is printed.
# Run from the repository root.
set -eu
set -f

if [ "$#" -ne 1 ] || [ ! -r "$1" ]; then
    printf 'usage: update-report.sh UPDATE_TSV\n' >&2
    exit 2
fi
here=$(cd -- "$(dirname -- "$0")" && pwd)
fail=0

printf 'Weekly upstream check (every other Monday).\n\n'
printf '| package | current | latest | status | readiness |\n'
printf '|---|---|---|---|---|\n'
while read -r name current latest status; do
    [ "$status" = current ] && continue
    readiness=-
    if [ "$status" = outdated ]; then
        readiness='no recipe directory'
        set +f
        for d in */; do
            [ -f "${d}.SRCINFO" ] || continue
            if grep -qxF "pkgname = $name" "${d}.SRCINFO"; then
                rc=0
                out=$(sh "$here/readiness-gate.sh" "$d") || rc=$?
                readiness="$(printf '%s' "$out" | tr '\n' ' ') (gate exit $rc)"
                [ "$rc" -le 1 ] || fail=1
                break
            fi
        done
        set -f
    fi
    printf '| %s | %s | %s | %s | %s |\n' "$name" "$current" "$latest" "$status" "$readiness"
done < "$1"
exit "$fail"
