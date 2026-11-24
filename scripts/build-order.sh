#!/bin/sh
# usage: build-order.sh DIR...
# Prints the recipe directories to build for the given directories, in
# dependency order: each directory's depends, makedepends and checkdepends
# (including the _x86_64 variants) that another recipe in this repository
# provides, by pkgname or by a provides entry, are built first. A name that
# a recipe's pkgname supplies wins over a provides entry; names no recipe
# supplies are left to pacman. Exit 0 ordered, 1 dependency cycle, 2 usage or a
# directory without .SRCINFO.
set -eu
set -f

if [ "$#" -lt 1 ]; then
    printf 'usage: build-order.sh DIR...\n' >&2
    exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' 0 HUP INT TERM
map=$work/map
edges=$work/edges
: > "$map"
: > "$edges"

# "kind name directory" for every pkgname (n) and provides entry (p), version
# constraints stripped.
set +f
for srcinfo in */.SRCINFO; do
    [ -f "$srcinfo" ] || continue
    dir=${srcinfo%/.SRCINFO}
    awk -v dir="$dir" '
        /^[[:space:]]*pkgname = / { k = "n" }
        /^[[:space:]]*provides(_x86_64)? = / { k = "p" }
        k != "" {
            v = $0
            sub(/^[^=]*= /, "", v)
            sub(/[<>=].*/, "", v)
            gsub(/[[:space:]]/, "", v)
            if (v != "") print k, v, dir
            k = ""
        }
    ' "$srcinfo" >> "$map"
done
set -f

# In-repository directories that supply a dependency of directory $1.
deps_of() {
    awk '
        FILENAME == ARGV[1] {
            if ($1 == "n") byname[$2] = byname[$2] " " $3
            else byprov[$2] = byprov[$2] " " $3
            next
        }
        /^[[:space:]]*(depends|makedepends|checkdepends)(_x86_64)? = / {
            v = $0
            sub(/^[^=]*= /, "", v)
            sub(/[<>=:].*/, "", v)
            gsub(/[[:space:]]/, "", v)
            s = (v in byname) ? byname[v] : byprov[v]
            n = split(s, a, " ")
            for (i = 1; i <= n; i++) print a[i]
        }
    ' "$map" "$1/.SRCINFO" > "$work/deps.raw"
    sort -u "$work/deps.raw"
}

# Closure over in-repository dependencies, then a topological sort.
queue=$*
seen=" "
while [ -n "$queue" ]; do
    # shellcheck disable=SC2086
    set -- $queue
    dir=$1
    shift
    queue=$*
    case "$dir" in
        *[!A-Za-z0-9._+-]*|[!A-Za-z0-9]*)
            printf 'build-order: refused directory name\n' >&2
            exit 2
            ;;
    esac
    case "$seen" in *" $dir "*) continue ;; esac
    seen="$seen$dir "
    [ -f "$dir/.SRCINFO" ] || { printf 'build-order: %s has no .SRCINFO\n' "$dir" >&2; exit 2; }
    printf '%s %s\n' "$dir" "$dir" >> "$edges"
    deps_of "$dir" > "$work/deps"
    while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        [ "$dep" = "$dir" ] && continue
        printf '%s %s\n' "$dep" "$dir" >> "$edges"
        queue="$queue $dep"
    done < "$work/deps"
done
tsort "$edges"
