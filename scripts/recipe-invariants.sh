#!/bin/sh
# usage: recipe-invariants.sh [-r ROOT] TABLE
# Checks the recipe invariants TABLE lists against the recipes under ROOT
# (default: the repository root). TABLE rows are "kind<TAB>directory<TAB>
# arguments"; blank lines and lines starting with # are skipped. Kinds:
#   depends-include NAME...      every NAME is a depends entry of the
#                                directory's .SRCINFO (a library its dynamic
#                                loader opens, for example)
#   backup-covers-envfile UNIT   every EnvironmentFile= path of the systemd
#                                unit file UNIT in the directory is a backup
#                                entry of its .SRCINFO, so an upgrade keeps
#                                the local configuration
# Prints "ok|violated kind directory detail" per check. Exit 0 every
# invariant holds, 1 any is violated, 2 on usage, an unreadable or empty
# table, an unknown kind, or a missing .SRCINFO or unit file.
set -eu

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
if [ "${1-}" = -r ]; then
    [ $# -ge 2 ] || { printf 'usage: recipe-invariants.sh [-r ROOT] TABLE\n' >&2; exit 2; }
    root=$2
    shift 2
fi
[ $# -eq 1 ] || { printf 'usage: recipe-invariants.sh [-r ROOT] TABLE\n' >&2; exit 2; }
table=$1
[ -r "$table" ] || { printf 'recipe-invariants: cannot read %s\n' "$table" >&2; exit 2; }

tab=$(printf '\t')
rows=0
violations=0

# has_srcinfo_line DIR KEY VALUE: DIR/.SRCINFO holds the line "<TAB>KEY = VALUE".
has_srcinfo_line() {
    grep -Fqx "$tab$2 = $3" "$root/$1/.SRCINFO"
}

while IFS="$tab" read -r kind dir args || [ -n "$kind" ]; do
    case $kind in
        ''|'#'*) continue ;;
    esac
    rows=$((rows + 1))
    [ -r "$root/$dir/.SRCINFO" ] || { printf 'recipe-invariants: %s/.SRCINFO is unreadable\n' "$dir" >&2; exit 2; }
    case $kind in
        depends-include)
            for name in $args; do
                if has_srcinfo_line "$dir" depends "$name"; then
                    printf 'ok %s %s %s\n' "$kind" "$dir" "$name"
                else
                    printf 'violated %s %s %s\n' "$kind" "$dir" "$name"
                    violations=$((violations + 1))
                fi
            done
            ;;
        backup-covers-envfile)
            unit=$root/$dir/$args
            [ -r "$unit" ] || { printf 'recipe-invariants: %s/%s is unreadable\n' "$dir" "$args" >&2; exit 2; }
            paths=$(sed -n 's/^EnvironmentFile=-\{0,1\}\/\{0,1\}//p' "$unit")
            [ -n "$paths" ] || { printf 'violated %s %s %s names no EnvironmentFile\n' "$kind" "$dir" "$args"; violations=$((violations + 1)); continue; }
            for path in $paths; do
                if has_srcinfo_line "$dir" backup "$path"; then
                    printf 'ok %s %s %s\n' "$kind" "$dir" "$path"
                else
                    printf 'violated %s %s %s\n' "$kind" "$dir" "$path"
                    violations=$((violations + 1))
                fi
            done
            ;;
        *)
            printf 'recipe-invariants: unknown kind %s\n' "$kind" >&2
            exit 2
            ;;
    esac
done < "$table"

[ "$rows" -gt 0 ] || { printf 'recipe-invariants: %s lists no invariant\n' "$table" >&2; exit 2; }
[ "$violations" -eq 0 ]
