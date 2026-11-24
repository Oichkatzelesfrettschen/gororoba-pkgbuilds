#!/bin/sh
# usage: publish-gate.sh -i INSTALLED_TSV -o OWNERS -d DKMS_TSV PKGFILE...
#   INSTALLED_TSV  name<TAB>version<TAB>builddate(epoch) of installed packages
#   OWNERS         pacman -Ql snapshot: "package /absolute/path" per line
#   DKMS_TSV       module<TAB>owning-package of installed DKMS modules
# Per package file prints "pkgname result detail". Results: ok, or refused with
# reason version_not_newer, builddate_not_newer, file_conflict or dkms_duplicate.
# Exit 0 when every package is ok, 1 when any is refused, 2 on usage or an
# unreadable input.
set -eu

installed=
owners=
dkms=
while getopts 'i:o:d:h' opt; do
    case "$opt" in
        i) installed=$OPTARG ;;
        o) owners=$OPTARG ;;
        d) dkms=$OPTARG ;;
        *) sed -n '2,10p' "$0"; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
if [ -z "$installed" ] || [ -z "$owners" ] || [ -z "$dkms" ] || [ "$#" -lt 1 ]; then
    printf 'usage: publish-gate.sh -i INSTALLED_TSV -o OWNERS -d DKMS_TSV PKGFILE...\n' >&2
    exit 2
fi
for input in "$installed" "$owners" "$dkms"; do
    if [ ! -r "$input" ]; then
        printf 'publish=refused reason=unreadable_input\n' >&2
        exit 2
    fi
done

work=$(mktemp -d)
trap 'rm -rf "$work"' 0 HUP INT TERM
names=$work/names
modules=$work/modules
: > "$names"
: > "$modules"

# Pass 1: transaction names and the DKMS module names each package builds.
for pkg in "$@"; do
    name=$(bsdtar -xOf "$pkg" .PKGINFO | awk -F' = ' '$1 == "pkgname" { print $2; exit }')
    if [ -z "$name" ]; then
        printf 'publish=refused reason=no_pkginfo file=%s\n' "$pkg" >&2
        exit 2
    fi
    printf '%s\n' "$name" >> "$names"
    for conf in $(bsdtar -tf "$pkg" | grep -E '^usr/src/[^/]+/dkms\.conf$' || true); do
        built=$(bsdtar -xOf "$pkg" "$conf" |
            sed -n 's/^BUILT_MODULE_NAME\[[0-9]*\]=["'"'"']\{0,1\}\([^"'"'"' ]*\).*/\1/p')
        if [ -z "$built" ]; then
            built=$(bsdtar -xOf "$pkg" "$conf" |
                sed -n 's/^PACKAGE_NAME=["'"'"']\{0,1\}\([^"'"'"' ]*\).*/\1/p')
        fi
        for module in $built; do
            printf '%s\t%s\n' "$module" "$name" >> "$modules"
        done
    done
done

status=0
for pkg in "$@"; do
    info=$(bsdtar -xOf "$pkg" .PKGINFO)
    name=$(printf '%s\n' "$info" | awk -F' = ' '$1 == "pkgname" { print $2; exit }')
    version=$(printf '%s\n' "$info" | awk -F' = ' '$1 == "pkgver" { print $2; exit }')
    builddate=$(printf '%s\n' "$info" | awk -F' = ' '$1 == "builddate" { print $2; exit }')
    reason=

    old=$(awk -F'\t' -v n="$name" '$1 == n { print $2 "\t" $3; exit }' "$installed")
    if [ -n "$old" ]; then
        old_version=${old%%	*}
        old_date=${old##*	}
        if [ "$(vercmp "$version" "$old_version")" -le 0 ]; then
            reason=version_not_newer
        elif [ "$builddate" -le "$old_date" ]; then
            reason=builddate_not_newer
        fi
    fi

    if [ -z "$reason" ]; then
        bsdtar -tf "$pkg" | grep -v -e '/$' -e '^\.' | sed 's|^|/|' | sort -u > "$work/files"
        # A file owned by an installed package outside the transaction conflicts.
        awk -v names="$work/names" '
            BEGIN { while ((getline l < names) > 0) mine[l] = 1 }
            NR == FNR { want[$0] = 1; next }
            ($2 in want) && !($1 in mine) { print $2 " (" $1 ")" }
        ' "$work/files" "$owners" > "$work/conflicts"
        if [ -s "$work/conflicts" ]; then
            reason=file_conflict
            detail=$(head -n 1 "$work/conflicts")
        fi
    fi

    if [ -z "$reason" ]; then
        # Every module this package builds must have no other owner.
        awk -F'\t' -v me="$name" -v names="$work/names" '
            BEGIN { while ((getline l < names) > 0) mine[l] = 1 }
            FILENAME == ARGV[1] { if ($2 != me) other[$1] = $2; next }
            FILENAME == ARGV[2] { if (!($2 in mine)) other[$1] = $2; next }
            ($2 == me) && ($1 in other) { print $1 " (" other[$1] ")"; exit }
        ' "$modules" "$dkms" "$modules" > "$work/dups"
        if [ -s "$work/dups" ]; then
            reason=dkms_duplicate
            detail=$(head -n 1 "$work/dups")
        fi
    fi

    if [ -n "$reason" ]; then
        printf '%s refused:%s %s\n' "$name" "$reason" "${detail:-$version}"
        status=1
    else
        printf '%s ok %s\n' "$name" "$version"
    fi
    detail=
done
exit "$status"
