#!/bin/sh
# usage: ci-build.sh ALLOWLIST DIR...
# Container build driver, run as root from the checkout. Plans with
# build-plan.sh, then builds each planned recipe as the unprivileged user
# "builder" with per-recipe BUILDDIR, SRCDEST and PKGDEST under BUILD_ROOT
# (default /var/tmp/build). Built packages join a repository "ci-local" that
# exists only in a copy of pacman.conf under BUILD_ROOT, so later recipes
# resolve them and /etc/pacman.conf stays untouched. Prints
# "recipe DIR built", "recipe DIR skipped:REASON" or "recipe DIR refused:REASON"
# for every changed recipe. Exit 0 when nothing is refused, 1 otherwise.
set -eu
set -f

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=${BUILD_ROOT:-/var/tmp/build}
if [ "$#" -lt 2 ]; then
    printf 'usage: ci-build.sh ALLOWLIST DIR...\n' >&2
    exit 2
fi
allow=$1
shift

work=$(mktemp -d)
trap 'rm -rf "$work"' 0 HUP INT TERM

report() {
    printf 'recipe %s %s\n' "$1" "$2"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        printf -- '- %s: %s\n' "$1" "$2" >> "$GITHUB_STEP_SUMMARY"
    fi
}

if ! sh "$here/build-plan.sh" "$allow" "$@" > "$work/plan"; then
    for d in "$@"; do report "$d" refused:plan; done
    exit 1
fi

install -d "$root/repo"
cp -- /etc/pacman.conf "$root/pacman.conf"
cp -- /etc/makepkg.conf "$root/makepkg.conf"
printf 'PACMAN_OPTS=(--config %s)\n' "$root/pacman.conf" >> "$root/makepkg.conf"
chmod a+r "$root/pacman.conf" "$root/makepkg.conf"
local_repo=no
status=0
while IFS=' ' read -r dir verdict; do
    if [ "$verdict" != build ]; then
        report "$dir" "$verdict"
        continue
    fi
    install -d -o builder -g builder "$root/work/$dir" "$root/src/$dir" "$root/pkg/$dir"
    printf '::group::%s\n' "$dir"
    if ! ( cd -- "$dir" && sudo -u builder env \
            PACKAGER="$PACKAGER" BUILDDIR="$root/work/$dir" \
            SRCDEST="$root/src/$dir" PKGDEST="$root/pkg/$dir" \
            makepkg --config "$root/makepkg.conf" --syncdeps --noconfirm --needed --cleanbuild ); then
        printf '::endgroup::\n'
        report "$dir" refused:build_failed
        status=1
        continue
    fi
    produced=0
    set +f
    for pkg in "$root/pkg/$dir"/*.pkg.tar.zst; do
        [ -f "$pkg" ] || continue
        cp -- "$pkg" "$root/repo/"
        repo-add -q "$root/repo/ci-local.db.tar.gz" "$root/repo/$(basename -- "$pkg")"
        produced=1
    done
    set -f
    if [ "$produced" -eq 0 ]; then
        printf '::endgroup::\n'
        report "$dir" refused:no_package_produced
        status=1
        continue
    fi
    # pacman refuses every sync operation while a configured repository lacks
    # its database, so the section joins the copy after the first repo-add.
    if [ "$local_repo" = no ]; then
        printf '\n[ci-local]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$root/repo" >> "$root/pacman.conf"
        local_repo=yes
    fi
    pacman --config "$root/pacman.conf" -Sy --noconfirm > /dev/null
    printf '::endgroup::\n'
    report "$dir" built
done < "$work/plan"
exit "$status"
