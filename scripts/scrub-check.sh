#!/bin/sh
# usage: scrub-check.sh [PATH...]
# Fails when a tracked file holds an IPv4 literal outside 127.0.0.0/8 and the
# documentation ranges, a home-directory path, a localhost mailbox, a private
# key header, or a common token shape. Prints "file:line: class" per hit.
# With no PATH, checks every tracked file of the repository at the cwd.
set -eu

case "${1:-}" in
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' 0 HUP INT TERM
list=$work/files
hits=$work/hits
: > "$hits"

if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@" > "$list"
else
    git ls-files > "$list"
fi

# Patterns are written so that this file does not match itself.
scan() {
    class=$1
    pattern=$2
    while IFS= read -r path; do
        [ -f "$path" ] || continue
        grep -InE -e "$pattern" -- "$path" 2>/dev/null |
            while IFS= read -r line; do
                num=${line%%:*}
                printf '%s:%s: %s\n' "$path" "$num" "$class"
            done >> "$hits" || true
    done < "$list"
}

scan home-path '(^|[^A-Za-z0-9_.-])/home/[A-Za-z0-9_][A-Za-z0-9_.-]*/'
scan localhost-mailbox '@local[h]ost'
scan private-key '-----BEGIN [A-Z ]*PRIVATE[ ]KEY'
scan github-token '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}'
scan aws-key '(AKIA|ASIA)[0-9A-Z]{16}'
scan slack-token 'xox[baprs]-[0-9A-Za-z-]{10,}'
scan api-key 'sk-[A-Za-z0-9_-]{32,}|AIza[0-9A-Za-z_-]{35}'

# IPv4: candidate dotted quads, then the private-range filter in awk. Four-part
# version strings (26.09.0.8, 6.7.80.0) look like public addresses, so only the
# ranges that name a local network or mesh peer are flagged: RFC 1918 and the
# RFC 6598 shared space used by CGNAT and overlay meshes.
while IFS= read -r path; do
    [ -f "$path" ] || continue
    grep -InoE -e '(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}($|[^0-9.]|\.[^0-9])' -- "$path" 2>/dev/null |
        awk -F: -v path="$path" '
            {
                num = $1
                rest = substr($0, length($1) + 2)
                if (match(rest, /([0-9]{1,3}\.){3}[0-9]{1,3}/) == 0) next
                ip = substr(rest, RSTART, RLENGTH)
                split(ip, o, ".")
                for (i = 1; i <= 4; i++) if (o[i] + 0 > 255) next
                priv = (o[1] == 10) ||
                    (o[1] == 172 && o[2] >= 16 && o[2] <= 31) ||
                    (o[1] == 192 && o[2] == 168) ||
                    (o[1] == 100 && o[2] >= 64 && o[2] <= 127)
                if (!priv) next
                printf "%s:%s: ipv4-literal\n", path, num
            }' >> "$hits" || true
done < "$list"

if [ -s "$hits" ]; then
    sort -u "$hits"
    printf 'scrub=refused hits=%s\n' "$(sort -u "$hits" | wc -l)" >&2
    exit 1
fi
printf 'scrub=accepted\n'
