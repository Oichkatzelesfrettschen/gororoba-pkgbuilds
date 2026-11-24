#!/bin/sh
# usage: changed-recipes.sh [BASE_REF]
# Prints each top-level directory that holds a PKGBUILD and differs from
# BASE_REF (default origin/main), one per line. With BASE_REF equal to "all",
# prints every recipe directory.
set -eu

base=${1:-origin/main}
if [ "$base" = all ]; then
    changed=$(git ls-files | sed -n 's|^\([^/]*\)/.*|\1|p' | sort -u)
else
    changed=$(git diff --name-only "$base"...HEAD | sed -n 's|^\([^/]*\)/.*|\1|p' | sort -u)
fi
for dir in $changed; do
    if [ -f "$dir/PKGBUILD" ]; then
        printf '%s\n' "$dir"
    fi
done
