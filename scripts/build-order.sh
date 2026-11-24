#!/bin/sh
# usage: build-order.sh DIR...
# Prints the recipe directories to build for the given directories, in
# dependency order: each directory's depends, makedepends and checkdepends
# (including the _x86_64 variants) that another recipe in this repository
# provides, by pkgname or by a provides entry, are built first. A name that
# a recipe's pkgname supplies wins over a provides entry; a name that only a
# provides entry supplies is left to pacman when a sync repository has a
# package of that exact name (a recipe providing blas does not capture every
# depends=blas); names no recipe supplies are left to pacman. Exit 0 ordered, 1 dependency cycle, 2 usage or a
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
            if (v in byname) { k = "n"; s = byname[v] } else { k = "p"; s = byprov[v] }
            n = split(s, a, " ")
            for (i = 1; i <= n; i++) print k, v, a[i]
        }
    ' "$map" "$1/.SRCINFO" > "$work/deps.raw"
    : > "$work/deps.dirs"
    # Distinct names: the caller's loop holds the current directory in $dir.
    while read -r dep_kind dep_name dep_dir; do
        if [ "$dep_kind" = p ] && repo_has "$dep_name"; then
            continue
        fi
        printf '%s\n' "$dep_dir" >> "$work/deps.dirs"
    done < "$work/deps.raw"
    sort -u "$work/deps.dirs"
}

# Whether a sync repository holds a package named exactly $1 (cached per run).
# Without pacman (a non-Arch host) nothing counts as repository-supplied.
repo_has() {
    command -v pacman > /dev/null 2>&1 || return 1
    if grep -qxF -- "+$1" "$work/repo.cache" 2> /dev/null; then return 0; fi
    if grep -qxF -- "-$1" "$work/repo.cache" 2> /dev/null; then return 1; fi
    if pacman -Si -- "$1" > /dev/null 2>&1; then
        printf '+%s\n' "$1" >> "$work/repo.cache"
        return 0
    fi
    printf -- '-%s\n' "$1" >> "$work/repo.cache"
    return 1
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
