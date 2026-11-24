#!/bin/sh
# usage: calibrate.sh [GATE...]
# Runs every gate script against its known-good and known-bad fixtures under
# ci/fixtures/GATE/ and fails when a verdict differs from the expected exit
# status or output. A gate that accepts a known-bad input, or refuses a
# known-good one, makes its verdict meaningless; CI runs this before trusting
# the gates. GATE is one of: changed build-order build-plan readiness
# update-check update-report scrub publish-gate (default: all). Needs git,
# jq, bsdtar, vercmp and tsort. Exit 0 all expectations held, 1 otherwise.
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/.." && pwd)
fx=$root/ci/fixtures
work=$(mktemp -d)
trap 'rm -rf "$work"' 0 HUP INT TERM
tab=$(printf '\t')
checks=0
failures=0

# run DIR NAME WANT_EXIT CMD...: runs CMD in DIR; output joins "$work/all".
run() {
    dir=$1
    name=$2
    want=$3
    shift 3
    rc=0
    ( cd -- "$dir" && "$@" ) > "$work/out" 2> "$work/err" || rc=$?
    cat "$work/out" "$work/err" > "$work/all"
    checks=$((checks + 1))
    if [ "$rc" -ne "$want" ]; then
        failures=$((failures + 1))
        printf 'FAIL %s: want exit %s, got %s\n' "$name" "$want" "$rc"
        sed 's/^/    /' "$work/all"
    else
        printf 'ok   %s\n' "$name"
    fi
}
# saw TEXT: the last run printed the line TEXT.
saw() {
    checks=$((checks + 1))
    if ! grep -qxF -- "$1" "$work/all"; then
        failures=$((failures + 1))
        printf 'FAIL expected line: %s\n' "$1"
        sed 's/^/    /' "$work/all"
    fi
}
# sawpart TEXT: the last run printed TEXT somewhere.
sawpart() {
    checks=$((checks + 1))
    if ! grep -qF -- "$1" "$work/all"; then
        failures=$((failures + 1))
        printf 'FAIL expected text: %s\n' "$1"
        sed 's/^/    /' "$work/all"
    fi
}
# lacks TEXT: the last run did not print the line TEXT.
lacks() {
    checks=$((checks + 1))
    if grep -qxF -- "$1" "$work/all"; then
        failures=$((failures + 1))
        printf 'FAIL unexpected line: %s\n' "$1"
    fi
}

gate_changed() {
    repo=$work/changed
    git init -q "$repo"
    g() { git -C "$repo" -c user.name=calibrate -c user.email=calibrate@example.invalid -c commit.gpgsign=false "$@"; }
    cp -R "$fx/changed/base/." "$repo/"
    g add -A
    g commit -q -m base
    first=$(g rev-parse HEAD)
    cp -R "$fx/changed/head/." "$repo/"
    g add -A
    g commit -q -m head
    run "$repo" "changed: changed recipes only" 0 sh "$here/changed-recipes.sh" "$first"
    saw alpha
    saw gamma
    lacks beta
    lacks notes
    run "$repo" "changed: nothing changed" 0 sh "$here/changed-recipes.sh" HEAD
    run "$repo" "changed: all-zero before-SHA compares to the empty tree" 0 \
        sh "$here/changed-recipes.sh" 0000000000000000000000000000000000000000
    saw beta
    run "$repo" "changed: all" 0 sh "$here/changed-recipes.sh" all
    saw alpha
    run "$repo" "changed: unresolved base refused" 2 sh "$here/changed-recipes.sh" no-such-revision
    mkdir "$repo/bad name"
    printf 'pkgname=x\n' > "$repo/bad name/PKGBUILD"
    g add -A
    g commit -q -m badname
    run "$repo" "changed: recipe name outside the allowed characters refused" 1 \
        sh "$here/changed-recipes.sh" "$first"
}

gate_build_order() {
    run "$fx/build-order/good" "build-order: provides, _x86_64 and chain order" 0 sh "$here/build-order.sh" c
    saw a
    saw b
    saw c
    lacks z
    run "$fx/build-order/good" "build-order: dependency first" 0 sh "$here/build-order.sh" c
    first_line=$(sed -n '1p' "$work/out")
    checks=$((checks + 1))
    if [ "$first_line" != a ]; then
        failures=$((failures + 1))
        printf 'FAIL build-order: first member is %s, want a\n' "$first_line"
    fi
    run "$fx/build-order/cycle" "build-order: dependency cycle refused" 1 sh "$here/build-order.sh" x
    run "$fx/build-order/good" "build-order: directory without .SRCINFO refused" 2 sh "$here/build-order.sh" nonexistent
    run "$fx/build-order/good" "build-order: no arguments refused" 2 sh "$here/build-order.sh"
}

gate_build_plan() {
    bo=$fx/build-order
    run "$bo/good" "build-plan: closure fully allowlisted" 0 sh "$here/build-plan.sh" "$bo/allow-good.txt" c
    saw "a build"
    saw "b build"
    saw "c build"
    run "$bo/good" "build-plan: non-allowlisted change is skipped and reported" 0 \
        sh "$here/build-plan.sh" "$bo/allow-good.txt" z
    saw "z skipped:not_allowlisted"
    run "$bo/good" "build-plan: closure member off the allowlist fails before building" 1 \
        sh "$here/build-plan.sh" "$bo/allow-open-closure.txt" c
    saw "closure member not allowlisted: b"
    : > "$work/empty-allow"
    run "$bo/good" "build-plan: empty allowlist refused" 2 sh "$here/build-plan.sh" "$work/empty-allow" c
    run "$bo/good" "build-plan: missing allowlist refused" 2 sh "$here/build-plan.sh" "$work/none" c
}

gate_readiness() {
    rd=$fx/readiness
    gate() { READINESS_TABLE=$rd/table.tsv sh "$here/readiness-gate.sh" "$@"; }
    run "$rd" "readiness: satisfied floors, provide versions and own name" 0 gate ok
    saw ok
    run "$rd" "readiness: dependency below its floor" 1 gate held
    saw "held:libx>=3.0"
    run "$rd" "readiness: absent dependency in an _x86_64 field" 1 gate gap
    saw "gap:missingdep"
    run "$rd" "readiness: bare provide never satisfies a floor" 1 gate bare
    saw "held:libbare>=1"
    run "$rd" "readiness: glob characters stay literal" 1 gate glob
    saw "gap:lib*"
    run "$rd" "readiness: missing SRCINFO refused" 2 gate nonexistent
    run "$rd" "readiness: unreadable table refused" 2 env READINESS_TABLE="$work/none" sh "$here/readiness-gate.sh" ok
}

gate_update_check() {
    tree=$fx/update-check/tree
    uc() { PATH="$fx/update-check/bin:$PATH" NVFAKE=$1 sh "$here/update-check.sh"; }
    run "$tree" "update-check: epoch, pkgrel, invalid and unchecked statuses" 0 uc ok
    saw "one 1.0-2 1.1 outdated"
    saw "two 1:2.0-1 2.0 current"
    saw "three 5-1 - invalid"
    saw "four 3-1 - unchecked"
    saw "five 1:2.0-1 3.0 outdated"
    run "$tree" "update-check: nvchecker failure refused" 1 uc fail
    run "$tree" "update-check: no results refused" 1 uc empty
}

gate_update_report() {
    rd=$fx/readiness
    report() { READINESS_TABLE=$1 sh "$here/update-report.sh" "$rd/report.tsv"; }
    run "$rd" "update-report: gate verdict and status kept" 0 report "$rd/table.tsv"
    sawpart "| ok | 1 | 2 | outdated | ok (gate exit 0) |"
    sawpart "| held | 1 | 2 | outdated | held:libx>=3.0 (gate exit 1) |"
    sawpart "| stale | 1 | - | unchecked | - |"
    run "$rd" "update-report: gate that cannot run fails the report" 1 report "$work/none"
    sawpart "(gate exit 2)"
}

gate_scrub() {
    sc() { sh "$here/scrub-check.sh" "$@"; }
    run "$fx/scrub" "scrub: known-good text accepted" 0 sc good.txt
    saw "scrub=accepted"
    mkdir "$work/scrub"
    n=0
    while IFS="$tab" read -r class left right; do
        case "$class" in '#'*|'') continue ;; esac
        n=$((n + 1))
        printf 'x %s%s y\n' "$left" "$right" > "$work/scrub/bad$n.txt"
        run "$work/scrub" "scrub: known-bad $class ($n)" 1 sc "bad$n.txt"
        sawpart ": $class"
    done < "$fx/scrub/bad.tsv"
    printf 'a\000 10.1.%s \000b\n' 2.3 > "$work/scrub/binary.bin"
    run "$work/scrub" "scrub: binary file scanned as text" 1 sc binary.bin
    run "$work/scrub" "scrub: missing path refused" 2 sc no-such-file
    run "$work/scrub" "scrub: directory path refused" 2 sc "$work"
    mkdir "$work/emptyrepo"
    git init -q "$work/emptyrepo"
    run "$work/emptyrepo" "scrub: empty tracked list refused" 2 sc
    printf 'ssh EvilHost.invalid now\n' > "$work/scrub/host.txt"
    printf 'evilhost.invalid\n' > "$work/scrub/hosts.txt"
    run "$work/scrub" "scrub: listed host flagged" 1 sc -H hosts.txt host.txt
    sawpart ": private-host"
    run "$fx/scrub" "scrub: unlisted host accepted" 0 sc -H hosts.txt good.txt
    run "$work/scrub" "scrub: missing hosts file refused" 2 sc -H no-hosts good.txt
    printf 'evilhost.invalid\n\n' > "$work/scrub/blank-hosts.txt"
    run "$work/scrub" "scrub: blank line in hosts file refused" 2 sc -H blank-hosts.txt host.txt
}

gate_publish() {
    pg=$fx/publish-gate
    mkdir "$work/pkgs"
    for d in "$pg"/pkgs/*; do
        name=$(basename -- "$d")
        ( cd -- "$d" && find . -type f | sed 's|^\./||' | sort > "$work/pkgs/$name.list" &&
            bsdtar -cnf "$work/pkgs/$name.pkg.tar" -T "$work/pkgs/$name.list" )
    done
    pgate() {
        inst=$1
        dk=$2
        shift 2
        sh "$here/publish-gate.sh" -i "$pg/$inst" -o "$pg/owners.txt" -d "$pg/$dk" "$@"
    }
    p() { printf '%s' "$work/pkgs/$1.pkg.tar"; }
    run "$pg" "publish-gate: newer package accepted" 0 pgate installed.tsv dkms.tsv "$(p good)"
    saw "good ok 2.0-1"
    run "$pg" "publish-gate: new DKMS module with no other owner accepted" 0 pgate installed.tsv dkms.tsv "$(p dkmsok)"
    run "$pg" "publish-gate: version not newer refused" 1 pgate installed.tsv dkms.tsv "$(p old)"
    sawpart "old refused:version_not_newer"
    run "$pg" "publish-gate: builddate not newer refused" 1 pgate installed.tsv dkms.tsv "$(p stale)"
    sawpart "stale refused:builddate_not_newer"
    run "$pg" "publish-gate: file owned by another package refused" 1 pgate installed.tsv dkms.tsv "$(p clash)"
    sawpart "clash refused:file_conflict"
    run "$pg" "publish-gate: owned path with a space refused" 1 pgate installed.tsv dkms.tsv "$(p clashspace)"
    sawpart "clashspace refused:file_conflict"
    run "$pg" "publish-gate: duplicate DKMS module refused" 1 pgate installed.tsv dkms.tsv "$(p dkmsdup)"
    sawpart "dkmsdup refused:dkms_duplicate"
    run "$pg" "publish-gate: empty DKMS snapshot with header accepted" 0 pgate installed.tsv dkms-empty.tsv "$(p dkmsdup)"
    run "$pg" "publish-gate: snapshot without header refused" 2 pgate installed-noheader.tsv dkms.tsv "$(p good)"
    run "$pg" "publish-gate: empty installed snapshot refused" 2 pgate installed-empty.tsv dkms.tsv "$(p good)"
    run "$pg" "publish-gate: non-numeric installed builddate refused" 2 pgate installed-badnum.tsv dkms.tsv "$(p good)"
    run "$pg" "publish-gate: non-numeric package builddate refused" 2 pgate installed.tsv dkms.tsv "$(p baddate)"
    run "$pg" "publish-gate: missing package file refused" 2 pgate installed.tsv dkms.tsv "$work/pkgs/none.pkg.tar"
}

gates=$*
[ -n "$gates" ] || gates="changed build-order build-plan readiness update-check update-report scrub publish-gate"
for gate in $gates; do
    case "$gate" in
        changed) gate_changed ;;
        build-order) gate_build_order ;;
        build-plan) gate_build_plan ;;
        readiness) gate_readiness ;;
        update-check) gate_update_check ;;
        update-report) gate_update_report ;;
        scrub) gate_scrub ;;
        publish-gate) gate_publish ;;
        *) printf 'calibrate: unknown gate %s\n' "$gate" >&2; exit 2 ;;
    esac
done
printf 'calibrate: %s checks, %s failures\n' "$checks" "$failures"
[ "$failures" -eq 0 ]
