#!/bin/sh
# usage: update-check.sh
# Runs nvchecker over nvchecker/*.toml and compares each result with the
# epoch and pkgver of the recipe's .SRCINFO. Prints "pkgname current latest
# status" per recipe; current is [epoch:]pkgver-pkgrel. Status is current,
# outdated, invalid (upstream version holds characters a pkgver cannot) or
# unchecked (no entry, or no result). The comparison binds the recipe's epoch to
# both sides and ignores pkgrel. GITHUB_TOKEN, when set, becomes the nvchecker
# github key. nvchecker runs with --failures and its exit status is checked.
# Exit 0 compared, 1 nvchecker failed or produced no result, 2 a tool is
# missing: a missing tool never reads as "current".
set -eu

case "${1:-}" in
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
esac
for tool in nvchecker jq vercmp; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        printf 'update-check=not_run reason=%s_missing\n' "$tool" >&2
        exit 2
    fi
done

work=$(mktemp -d)
trap 'rm -rf "$work"' 0 HUP INT TERM
current=$work/current
latest=$work/latest
: > "$current"
: > "$latest"

# Recipes: every top-level directory with a .SRCINFO. Rows: name epoch pkgver pkgrel.
for srcinfo in ./*/.SRCINFO; do
    [ -f "$srcinfo" ] || continue
    awk '
        /^\tepoch = / { epoch = $3 }
        /^\tpkgver = / { ver = $3 }
        /^\tpkgrel = / { rel = $3 }
        /^pkgname = / { names[++n] = $3 }
        END { for (i = 1; i <= n; i++) print names[i], (epoch == "" ? 0 : epoch), ver, rel }
    ' "$srcinfo" >> "$current"
done

keyfile=
if [ -n "${GITHUB_TOKEN:-}" ]; then
    case "$GITHUB_TOKEN" in
        *[!A-Za-z0-9_]*) printf 'update-check=refused reason=token_characters\n' >&2; exit 1 ;;
    esac
    ( umask 077; printf '[keys]\ngithub = "%s"\n' "$GITHUB_TOKEN" > "$work/keyfile.toml" )
    keyfile=$work/keyfile.toml
fi

for config in nvchecker/*.toml; do
    [ -f "$config" ] || continue
    rc=0
    if [ -n "$keyfile" ]; then
        nvchecker -c "$config" -k "$keyfile" --failures --logger json > "$work/nv.json" 2> "$work/err" || rc=$?
    else
        nvchecker -c "$config" --failures --logger json > "$work/nv.json" 2> "$work/err" || rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        printf 'update-check=refused reason=nvchecker_failed config=%s exit=%s\n' "$config" "$rc" >&2
        exit 1
    fi
    if ! jq -rR 'fromjson? | select(.event == "updated" or .event == "up-to-date")
            | select((.name | type) == "string" and (.version | type) == "string")
            | [.name, .version] | @tsv' "$work/nv.json" >> "$latest"; then
        printf 'update-check=refused reason=json_parse_failed config=%s\n' "$config" >&2
        exit 1
    fi
done
if [ -s "$current" ] && [ ! -s "$latest" ]; then
    printf 'update-check=refused reason=no_results\n' >&2
    exit 1
fi

while read -r name epoch ver rel; do
    if [ "$epoch" -ne 0 ]; then
        have=$epoch:$ver-$rel
    else
        have=$ver-$rel
    fi
    want=$(awk -F'\t' -v n="$name" '$1 == n { v = $2 } END { print v }' "$latest")
    if [ -z "$want" ]; then
        printf '%s %s - unchecked\n' "$name" "$have"
        continue
    fi
    case "$want" in
        *[!A-Za-z0-9._+~]*)
            printf '%s %s - invalid\n' "$name" "$have"
            continue
            ;;
    esac
    cmp=$(vercmp "$epoch:$want" "$epoch:$ver")
    if [ "$cmp" -gt 0 ]; then
        printf '%s %s %s outdated\n' "$name" "$have" "$want"
    else
        printf '%s %s %s current\n' "$name" "$have" "$want"
    fi
done < "$current"
