#!/bin/sh
# usage: update-check.sh
# Runs nvchecker over nvchecker/*.toml and compares each result with the
# pkgver of the recipe's .SRCINFO. Prints "pkgname current latest status" per
# recipe; status is current, outdated or unchecked (no entry, or no result).
# GITHUB_TOKEN, when set, becomes the nvchecker github key. Exit 2 when
# nvchecker is absent: a missing tool never reads as "current".
set -eu

case "${1:-}" in
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
esac
if ! command -v nvchecker >/dev/null 2>&1; then
    printf 'update-check=not_run reason=nvchecker_missing (pacman -S nvchecker)\n' >&2
    exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' 0 HUP INT TERM
current=$work/current
latest=$work/latest
: > "$current"
: > "$latest"

# Recipes: every top-level directory with a PKGBUILD and a .SRCINFO.
for srcinfo in ./*/.SRCINFO; do
    [ -f "$srcinfo" ] || continue
    awk '
        /^pkgbase = / { next }
        /^\tpkgver = / { ver = $3 }
        /^pkgname = / { names[++n] = $3 }
        END { for (i = 1; i <= n; i++) print names[i], ver }
    ' "$srcinfo" >> "$current"
done

keyargs=
if [ -n "${GITHUB_TOKEN:-}" ]; then
    umask 077
    printf '[keys]\ngithub = "%s"\n' "$GITHUB_TOKEN" > "$work/keyfile.toml"
    keyargs="-k $work/keyfile.toml"
fi

for config in nvchecker/*.toml; do
    [ -f "$config" ] || continue
    # shellcheck disable=SC2086
    nvchecker -c "$config" $keyargs --logger json 2>"$work/err" |
        sed -n 's/.*"name": *"\([^"]*\)".*"version": *"\([^"]*\)".*/\1 \2/p' >> "$latest" || {
            printf 'update-check=refused reason=nvchecker_failed config=%s\n' "$config" >&2
            exit 1
        }
done

while read -r name have; do
    want=$(awk -v n="$name" '$1 == n { v = $2 } END { print v }' "$latest")
    if [ -z "$want" ]; then
        printf '%s %s - unchecked\n' "$name" "$have"
        continue
    fi
    if [ "$(vercmp "$want" "$have")" -gt 0 ]; then
        printf '%s %s %s outdated\n' "$name" "$have" "$want"
    else
        printf '%s %s %s current\n' "$name" "$have" "$want"
    fi
done < "$current"
