#!/bin/sh
# usage: readiness-gate.sh DIR
# Resolves depends, makedepends and checkdepends (and their _x86_64 variants)
# of DIR/.SRCINFO, with version floors, against the synced sync databases
# (expac -S). Prints one line per unmet dependency, "held:<dep><op><ver>" when
# a package exists below the floor and "gap:<name>" when no package or provider
# exists, or "ok". A provide without a version never satisfies a floor, as in
# pacman. READINESS_TABLE names a TSV (name, version, space-separated provides)
# that replaces the databases; READINESS_EXTRA names a TSV of the same shape
# for the private repository. Exit 0 ok, 1 held or gap, 2 usage or missing input.
set -eu
set -f

if [ "$#" -ne 1 ]; then
    printf 'usage: readiness-gate.sh DIR\n' >&2
    exit 2
fi
srcinfo=$1/.SRCINFO
if [ ! -f "$srcinfo" ]; then
    printf 'readiness=refused reason=missing_srcinfo\n' >&2
    exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' 0 HUP INT TERM
table=$work/table
if [ -n "${READINESS_TABLE:-}" ]; then
    if [ ! -r "$READINESS_TABLE" ]; then
        printf 'readiness=refused reason=table_unreadable\n' >&2
        exit 2
    fi
    cp -- "$READINESS_TABLE" "$table"
else
    if ! command -v expac > /dev/null 2>&1; then
        printf 'readiness=not_run reason=expac_missing (pacman -S expac)\n' >&2
        exit 2
    fi
    expac -S -l ' ' '%n\t%v\t%P' > "$table"
fi
if [ -n "${READINESS_EXTRA:-}" ]; then
    if [ ! -r "$READINESS_EXTRA" ]; then
        printf 'readiness=refused reason=extra_unreadable\n' >&2
        exit 2
    fi
    cat -- "$READINESS_EXTRA" >> "$table"
fi
if [ ! -s "$table" ]; then
    printf 'readiness=refused reason=empty_database\n' >&2
    exit 2
fi

own=$work/own
awk '/^[[:space:]]*pkgname = / { print $3 }' "$srcinfo" > "$own"
awk -F' = ' '/^[[:space:]]*(depends|makedepends|checkdepends)(_x86_64)? = / { print $2 }' "$srcinfo" > "$work/deps.raw"
sort -u "$work/deps.raw" > "$work/deps"

status=0
while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    name=$dep
    op=
    ver=
    case "$dep" in
        *'>='*) name=${dep%%>=*}; op='>='; ver=${dep#*>=} ;;
        *'<='*) name=${dep%%<=*}; op='<='; ver=${dep#*<=} ;;
        *'='*)  name=${dep%%=*};  op='=';  ver=${dep#*=} ;;
        *'>'*)  name=${dep%%>*};  op='>';  ver=${dep#*>} ;;
        *'<'*)  name=${dep%%<*};  op='<';  ver=${dep#*<} ;;
    esac
    if grep -qxF -- "$name" "$own"; then
        continue
    fi
    # Candidate versions of name: the package itself and every provide of it;
    # "*" marks a provide without a version.
    awk -F'\t' -v n="$name" '
        $1 == n { print $2 }
        {
            m = split($3, p, " ")
            for (i = 1; i <= m; i++) {
                split(p[i], kv, "=")
                if (kv[1] == n) print (kv[2] == "" ? "*" : kv[2])
            }
        }' "$table" > "$work/cands"
    if [ ! -s "$work/cands" ]; then
        printf 'gap:%s\n' "$name"
        status=1
        continue
    fi
    if [ -z "$op" ]; then
        continue
    fi
    met=0
    while IFS= read -r cand; do
        [ "$cand" = '*' ] && continue
        cmp=$(vercmp "$cand" "$ver")
        case "$op" in
            '>=') [ "$cmp" -ge 0 ] && met=1 ;;
            '<=') [ "$cmp" -le 0 ] && met=1 ;;
            '=')  [ "$cmp" -eq 0 ] && met=1 ;;
            '>')  [ "$cmp" -gt 0 ] && met=1 ;;
            '<')  [ "$cmp" -lt 0 ] && met=1 ;;
        esac
        [ "$met" -eq 1 ] && break
    done < "$work/cands"
    if [ "$met" -ne 1 ]; then
        printf 'held:%s%s%s\n' "$name" "$op" "$ver"
        status=1
    fi
done < "$work/deps"

if [ "$status" -eq 0 ]; then
    printf 'ok\n'
fi
exit "$status"
