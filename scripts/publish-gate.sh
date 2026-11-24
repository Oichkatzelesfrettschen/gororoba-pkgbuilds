#!/bin/sh
# usage: publish-gate.sh -i INSTALLED -o OWNERS -d DKMS PKGFILE...
#   INSTALLED  header "# publish-gate installed v1", then
#              name<TAB>version<TAB>builddate(epoch) of installed packages
#   OWNERS     header "# publish-gate owners v1", then the pacman -Ql
#              snapshot: "package /absolute/path" per line (the path may hold spaces)
#   DKMS       header "# publish-gate dkms v1", then
#              module<TAB>owning-package of installed DKMS modules (may be empty)
# Per package file prints "pkgname result detail". Results: ok, or refused with
# reason version_not_newer, builddate_not_newer, file_conflict or dkms_duplicate.
# Exit 0 when every package is ok, 1 when any is refused, 2 on usage or an
# unreadable, headerless, malformed or empty input (INSTALLED and OWNERS need
# at least one row), or a package file without a readable .PKGINFO.
set -eu

installed=
owners=
dkms=
while getopts 'i:o:d:h' opt; do
    case "$opt" in
        i) installed=$OPTARG ;;
        o) owners=$OPTARG ;;
        d) dkms=$OPTARG ;;
        *) sed -n '2,15p' "$0"; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
if [ -z "$installed" ] || [ -z "$owners" ] || [ -z "$dkms" ] || [ "$#" -lt 1 ]; then
    printf 'usage: publish-gate.sh -i INSTALLED -o OWNERS -d DKMS PKGFILE...\n' >&2
    exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' 0 HUP INT TERM

refuse_input() {
    printf 'publish=refused reason=%s\n' "$1" >&2
    exit 2
}

# Strips and checks the header; leaves the rows in "$work/NAME".
load_snapshot() {
    kind=$1
    file=$2
    [ -r "$file" ] || refuse_input "unreadable_input_$kind"
    first=$(sed -n '1p' "$file")
    [ "$first" = "# publish-gate $kind v1" ] || refuse_input "bad_header_$kind"
    sed '1d' "$file" > "$work/$kind"
}
load_snapshot installed "$installed"
load_snapshot owners "$owners"
load_snapshot dkms "$dkms"
[ -s "$work/installed" ] || refuse_input empty_installed
[ -s "$work/owners" ] || refuse_input empty_owners

awk -F'\t' 'NF != 3 || $1 == "" || $2 == "" || $3 !~ /^[0-9]+$/ { bad = 1 } END { exit bad }' \
    "$work/installed" || refuse_input malformed_installed
awk '{ p = index($0, " ") } p < 2 || substr($0, p + 1, 1) != "/" { bad = 1 } END { exit bad }' \
    "$work/owners" || refuse_input malformed_owners
awk -F'\t' 'NF != 2 || $1 == "" || $2 == "" { bad = 1 } END { exit bad }' \
    "$work/dkms" || refuse_input malformed_dkms

names=$work/names
modules=$work/modules
: > "$names"
: > "$modules"

# Pass 1: transaction names and the DKMS module names each package builds.
for pkg in "$@"; do
    bsdtar -xOf "$pkg" .PKGINFO > "$work/pkginfo" 2> /dev/null || refuse_input "no_pkginfo"
    name=$(awk -F' = ' '$1 == "pkgname" { print $2; exit }' "$work/pkginfo")
    [ -n "$name" ] || refuse_input "no_pkgname"
    printf '%s\n' "$name" >> "$names"
    bsdtar -tf "$pkg" > "$work/list" || refuse_input "unreadable_package"
    grep -E '^usr/src/[^/]+/dkms\.conf$' "$work/list" > "$work/confs" || [ "$?" -eq 1 ] || refuse_input grep_failed
    while IFS= read -r conf; do
        bsdtar -xOf "$pkg" "$conf" > "$work/conf" || refuse_input unreadable_package
        sed -n 's/^BUILT_MODULE_NAME\[[0-9]*\]=["'"'"']\{0,1\}\([^"'"'"' ]*\).*/\1/p' "$work/conf" > "$work/built"
        if [ ! -s "$work/built" ]; then
            sed -n 's/^PACKAGE_NAME=["'"'"']\{0,1\}\([^"'"'"' ]*\).*/\1/p' "$work/conf" > "$work/built"
        fi
        while IFS= read -r module; do
            [ -n "$module" ] || continue
            printf '%s\t%s\n' "$module" "$name" >> "$modules"
        done < "$work/built"
    done < "$work/confs"
done

status=0
for pkg in "$@"; do
    bsdtar -xOf "$pkg" .PKGINFO > "$work/pkginfo" 2> /dev/null || refuse_input "no_pkginfo"
    name=$(awk -F' = ' '$1 == "pkgname" { print $2; exit }' "$work/pkginfo")
    version=$(awk -F' = ' '$1 == "pkgver" { print $2; exit }' "$work/pkginfo")
    builddate=$(awk -F' = ' '$1 == "builddate" { print $2; exit }' "$work/pkginfo")
    [ -n "$version" ] || refuse_input no_pkgver
    case "$builddate" in
        ''|*[!0-9]*) refuse_input nonnumeric_builddate ;;
    esac
    reason=
    detail=

    old=$(awk -F'\t' -v n="$name" '$1 == n { print $2 "\t" $3; exit }' "$work/installed")
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
        bsdtar -tf "$pkg" > "$work/list" || refuse_input unreadable_package
        { printf '#\n'; grep -v -e '/$' -e '^\.' "$work/list" | sed 's|^|/|' | sort -u; } > "$work/files" || true
        { printf '#\n'; cat "$work/owners"; } > "$work/owners.idx"
        { printf '#\n'; cat "$names"; } > "$work/names.idx"
        # A file owned by an installed package outside the transaction conflicts.
        awk '
            FNR == 1 { idx++; next }
            idx == 1 { files[$0] = 1; next }
            idx == 2 { mine[$0] = 1; next }
            {
                p = index($0, " ")
                owner = substr($0, 1, p - 1)
                path = substr($0, p + 1)
                if ((path in files) && !(owner in mine)) print path " (" owner ")"
            }
        ' "$work/files" "$work/names.idx" "$work/owners.idx" > "$work/conflicts"
        if [ -s "$work/conflicts" ]; then
            reason=file_conflict
            detail=$(sed -n '1p' "$work/conflicts")
        fi
    fi

    if [ -z "$reason" ]; then
        # Every module this package builds must have no other owner. Each input
        # starts with a "#" line so FNR == 1 marks every file, empty or not.
        { printf '#\n'; cat "$names"; } > "$work/names.idx"
        { printf '#\n'; cat "$modules"; } > "$work/modules.idx"
        { printf '#\n'; cat "$work/dkms"; } > "$work/dkms.idx"
        awk -F'\t' -v me="$name" '
            FNR == 1 { idx++; next }
            idx == 1 { tx[$0] = 1; next }
            idx == 2 { if ($2 == me) mine[$1] = 1; else other[$1] = $2; next }
            { if (!($2 in tx)) other[$1] = $2 }
            END { for (m in mine) if (m in other) print m " (" other[m] ")" }
        ' "$work/names.idx" "$work/modules.idx" "$work/dkms.idx" | sort > "$work/dups"
        if [ -s "$work/dups" ]; then
            reason=dkms_duplicate
            detail=$(sed -n '1p' "$work/dups")
        fi
    fi

    if [ -n "$reason" ]; then
        printf '%s refused:%s %s\n' "$name" "$reason" "${detail:-$version}"
        status=1
    else
        printf '%s ok %s\n' "$name" "$version"
    fi
done
exit "$status"
