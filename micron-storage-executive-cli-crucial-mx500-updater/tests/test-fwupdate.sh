#!/bin/sh
# Exercises crucial-mx500-fwupdate against stub lsblk and msecli binaries and a
# sysfs fixture. Run from any directory: sh tests/test-fwupdate.sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)
tool=$here/../crucial-mx500-fwupdate.sh
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT INT TERM

mkdir -p "$work/fw/firmware" "$work/bin" "$work/sys/block/sdz/sdz1"
printf 'pkg_ver=2\n[1]\ndrive_model=MX500\nfirmware_type=CR\nprecondition=M3CR043,M3CR044,M3CR045\n' \
    >"$work/fw/firmware/firmware.properties"
printf 'M3CR046\n' >"$work/fw/VERSION"

# lsblk stub: STUB_MODEL, STUB_TYPE, STUB_MOUNTS, STUB_FSTYPE describe the
# disk. The FSTYPE pattern precedes TYPE because "FSTYPE" contains "TYPE".
cat >"$work/bin/lsblk" <<'EOF'
#!/bin/sh
case "$*" in
    *PATH,MODEL*) printf '/dev/sdz %s\n' "${STUB_MODEL:-CT1000MX500SSD1}" ;;
    *FSTYPE*) printf '%s\n' "${STUB_FSTYPE:-ext4}" ;;
    *TYPE*) printf '%s\n' "${STUB_TYPE:-disk}" ;;
    *MODEL*) printf '%s\n' "${STUB_MODEL:-CT1000MX500SSD1}" ;;
    *MOUNTPOINTS*) printf '%s\n' "${STUB_MOUNTS:-}" ;;
esac
EOF

# msecli stub: revision lives in $STUB_STATE; -U records its arguments and
# stdin, then moves the revision to M3CR046 unless STUB_FLASH_FAILS is set.
cat >"$work/bin/msecli" <<'EOF'
#!/bin/sh
case "$1" in
    -L)
        printf 'Serial No            : SER123            \n'
        printf 'FW-Rev               : %s             \n' "$(cat "$STUB_STATE")"
        ;;
    -U)
        printf '%s\n' "$*" >>"$STUB_CALLS"
        cat >>"$STUB_CALLS"
        [ -n "${STUB_FLASH_FAILS:-}" ] || printf 'M3CR046\n' >"$STUB_STATE"
        ;;
esac
EOF
chmod +x "$work/bin/lsblk" "$work/bin/msecli"

export MSECLI="$work/bin/msecli" LSBLK="$work/bin/lsblk" SYSFS="$work/sys"
export FWROOT="$work/fw" LOGDIR="$work"
export CRUCIAL_FWUPDATE_UID=0 STUB_STATE="$work/state" STUB_CALLS="$work/calls"

fails=0
pass() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
fresh() { : >"$work/calls"; printf '%s\n' "$1" >"$work/state"; }
expect() { # name, expected exit status, command...
    name=$1 want=$2
    shift 2
    set +e
    out=$("$@" 2>&1 </dev/null)
    got=$?
    set -e
    if [ "$got" -eq "$want" ]; then
        pass "$name"
    else
        bad "$name: exit $got, wanted $want"
        printf '%s\n' "$out"
    fi
    last=$out
}
contains() { # name, needle
    case $last in
        *"$2"*) pass "$1" ;;
        *) bad "$1: output lacks \"$2\""; printf '%s\n' "$last" ;;
    esac
}
no_flash() { # name: msecli -U has not been called since the last fresh
    if [ -s "$work/calls" ]; then bad "$1"; else pass "$1"; fi
}

fresh M3CR043
expect list 0 sh "$tool" --list
contains 'list shows revision' 'M3CR043'

fresh M3CR043
expect 'check plans update' 0 sh "$tool" --check /dev/sdz
contains 'check names transition' 'M3CR043 -> M3CR046'
no_flash 'check flashes nothing'

fresh M3CR046
expect 'already current' 0 sh "$tool" /dev/sdz
contains 'already current message' 'nothing to do'

fresh M3CR032
expect 'revision outside precondition' 1 sh "$tool" --yes /dev/sdz
contains 'precondition message' 'accepts only M3CR043,M3CR044,M3CR045'

fresh M3CR043
expect 'wrong model' 1 env STUB_MODEL='Samsung SSD 980 PRO' sh "$tool" --yes /dev/sdz
contains 'wrong model message' 'MX500 disks only'
expect 'partition target' 1 env STUB_TYPE=part sh "$tool" --yes /dev/sdz
contains 'partition message' 'pass the whole disk'
no_flash 'model and type refusals flash nothing'

fresh M3CR043
expect 'mounted target' 1 env STUB_MOUNTS=/srv/data sh "$tool" --yes /dev/sdz
contains 'mounted message' 'active mounts or swap (/srv/data'
no_flash 'mounted refusal flashes nothing'

fresh M3CR043
expect 'check on mounted disk reports blocker' 1 env STUB_MOUNTS=/srv/data sh "$tool" --check /dev/sdz
contains 'blocked check still prints plan' 'M3CR043 -> M3CR046'
contains 'blocked check names the blocker' 'is in use'

mkdir -p "$work/sys/block/sdz/sdz1/holders"
: >"$work/sys/block/sdz/sdz1/holders/dm-0"
fresh M3CR043
expect 'partition holder blocks' 1 sh "$tool" --yes /dev/sdz
contains 'holder message' 'kernel holders (dm-0'
no_flash 'holder refusal flashes nothing'
rm -f "$work/sys/block/sdz/sdz1/holders/dm-0"
mkdir -p "$work/sys/block/sdz/holders"
: >"$work/sys/block/sdz/holders/md0"
expect 'whole-disk holder blocks' 1 sh "$tool" --yes /dev/sdz
contains 'md holder message' 'kernel holders (md0'
rm -f "$work/sys/block/sdz/holders/md0"

for fstype in linux_raid_member LVM2_member zfs_member crypto_LUKS bcache; do
    fresh M3CR043
    expect "$fstype signature blocks" 1 env STUB_FSTYPE="$fstype" sh "$tool" --yes /dev/sdz
    contains "$fstype message" "member signatures ($fstype"
    no_flash "$fstype refusal flashes nothing"
done

fresh M3CR043
expect 'plain ext4 is not a blocker' 0 sh "$tool" --check /dev/sdz

fresh M3CR043
expect 'no confirmation without --yes' 1 sh "$tool" /dev/sdz
contains 'confirmation message' 'no confirmation read'
no_flash 'unconfirmed run flashes nothing'

fresh M3CR043
expect 'non-root refused' 1 env CRUCIAL_FWUPDATE_UID=1000 sh "$tool" --check /dev/sdz
contains 'root message' 'run as root'

fresh M3CR043
expect 'flash with --yes' 0 sh "$tool" --yes /dev/sdz
contains 'read-back message' 'now reports M3CR046'
contains 'power-off advice on success' 'Power the machine off completely'
if grep -q -- "-U -i $work/fw/firmware -n .* -v -s $work/crucial-mx500-fwupdate-SER123.log" "$work/calls"; then
    pass 'msecli arguments'
else
    bad 'msecli arguments'
    cat "$work/calls"
fi
if grep -qx 'Y' "$work/calls"; then pass 'msecli confirmation fed'; else bad 'msecli confirmation fed'; fi

fresh M3CR043
expect 'revision unchanged after flash' 1 env STUB_FLASH_FAILS=1 sh "$tool" --yes /dev/sdz
contains 'power-off advice on mismatch' 'power the machine off completely'

if [ "$fails" -eq 0 ]; then
    echo 'all tests passed'
else
    echo "$fails failure(s)"
    exit 1
fi
