#!/bin/sh
# Print the recipe directories to build for the given directories, in dependency
# order: each directory's depends, makedepends and checkdepends that another
# recipe in this repository provides are built first. Names no recipe here
# provides are left to pacman. Usage: build-order.sh DIR...
set -eu

map=$(mktemp)
edges=$(mktemp)
trap 'rm -f "$map" "$edges"' EXIT INT TERM

# pkgname -> directory for every recipe in the repository.
for srcinfo in */.SRCINFO; do
    [ -f "$srcinfo" ] || continue
    dir=${srcinfo%/.SRCINFO}
    sed -n 's/^pkgname = //p' "$srcinfo" | while IFS= read -r name; do
        printf '%s %s\n' "$name" "$dir"
    done
done > "$map"

deps_of() {
    sed -n -E 's/^[[:space:]]*(depends|makedepends|checkdepends)(_x86_64)? = ([^<>=: ]+).*/\3/p' "$1/.SRCINFO" |
        sort -u | while IFS= read -r dep; do
            awk -v d="$dep" '$1 == d { print $2 }' "$map"
        done | sort -u
}

# Closure over in-repository dependencies, then a topological sort.
queue=$*
seen=" "
while [ -n "$queue" ]; do
    set -- $queue
    dir=$1
    shift
    queue=$*
    case "$seen" in *" $dir "*) continue ;; esac
    seen="$seen$dir "
    [ -f "$dir/.SRCINFO" ] || { printf 'build-order: %s has no .SRCINFO\n' "$dir" >&2; exit 2; }
    printf '%s %s\n' "$dir" "$dir" >> "$edges"
    for dep in $(deps_of "$dir"); do
        [ "$dep" = "$dir" ] && continue
        printf '%s %s\n' "$dep" "$dir" >> "$edges"
        queue="$queue $dep"
    done
done
tsort "$edges"
