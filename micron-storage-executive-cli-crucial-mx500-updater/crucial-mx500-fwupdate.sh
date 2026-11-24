#!/bin/sh
# crucial-mx500-fwupdate: guarded firmware update for Crucial MX500 SATA SSDs.
#
# The firmware image and manifest (firmware.properties) come from Crucial's
# bootable-ISO updater. msecli (micron-storage-executive-cli) validates the
# manifest precondition and performs the ATA microcode download. The ISO runs
# with no disk in use; the wrapper enforces the equivalent on a live system:
# model match, whole-disk target, no mount, swap, sysfs holder (md,
# device-mapper) or RAID/LVM/ZFS/LUKS/bcache signature on the disk, a current
# revision the manifest accepts, a typed serial-number confirmation, and a
# revision read-back.
#
# MSECLI, LSBLK, SYSFS, FWROOT, LOGDIR and CRUCIAL_FWUPDATE_UID exist so the
# test suite can substitute stubs. sudo's default env_reset drops them, so a
# normal sudo invocation always uses the system tools.
set -eu

MSECLI=${MSECLI:-msecli}
LSBLK=${LSBLK:-lsblk}
SYSFS=${SYSFS:-/sys}
FWROOT=${FWROOT:-/usr/share/micron-storage-executive-cli-crucial-mx500-updater}
LOGDIR=${LOGDIR:-/var/log}
RUN_UID=${CRUCIAL_FWUPDATE_UID:-$(id -u)}

prog=crucial-mx500-fwupdate

usage() {
    cat <<EOF
usage: $prog --list
       $prog --check DEVICE
       $prog [--yes] DEVICE

  --list     list Crucial MX500 disks (root adds the firmware revision)
  --check    report whether DEVICE accepts the packaged firmware and name
             anything that keeps it in use; change nothing. Exits 1 when the
             disk is blocked.
  --yes      skip the typed serial-number confirmation

DEVICE is a whole disk such as /dev/sda. Packaged firmware: $(cat "$FWROOT/VERSION" 2>/dev/null || printf unknown).
Back up the disk first; the vendor states a firmware update is at the user's own risk.
EOF
}

die() {
    printf '%s: %s\n' "$prog" "$*" >&2
    exit 1
}

need_root() {
    [ "$RUN_UID" -eq 0 ] || die "run as root (msecli needs raw device access)"
}

# Print a msecli -L field ("FW-Rev", "Serial No") for DEVICE without padding.
msecli_field() {
    "$MSECLI" -L -n "$2" | sed -n "s/^$1[[:space:]]*:[[:space:]]*\\([^[:space:]]*\\).*/\\1/p" | head -n 1
}

is_mx500() {
    case $1 in
        CT[0-9]*MX500SSD[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}

blockers=
add_blocker() {
    blockers=${blockers:+$blockers; }$1
}

mode=update
assume_yes=0
dev=
while [ "$#" -gt 0 ]; do
    case $1 in
        --list) mode=list ;;
        --check) mode=check ;;
        --yes) assume_yes=1 ;;
        -h | --help) usage; exit 0 ;;
        -*) usage >&2; exit 2 ;;
        *)
            [ -z "$dev" ] || { usage >&2; exit 2; }
            dev=$1
            ;;
    esac
    shift
done

if [ "$mode" = list ]; then
    "$LSBLK" -dno PATH,MODEL | while read -r path model; do
        is_mx500 "$model" || continue
        if [ "$RUN_UID" -eq 0 ]; then
            printf '%s %s %s\n' "$path" "$model" "$(msecli_field FW-Rev "$path")"
        else
            printf '%s %s\n' "$path" "$model"
        fi
    done
    exit 0
fi

[ -n "$dev" ] || { usage >&2; exit 2; }
need_root
[ -r "$FWROOT/firmware/firmware.properties" ] || die "no packaged firmware under $FWROOT"
target=$(cat "$FWROOT/VERSION")

dev=$(readlink -f -- "$dev")
type=$("$LSBLK" -dno TYPE "$dev" 2>/dev/null) || die "$dev is not a block device"
[ "$type" = disk ] || die "$dev is a $type; pass the whole disk, not a partition"

model=$("$LSBLK" -dno MODEL "$dev" | sed 's/[[:space:]]*$//')
is_mx500 "$model" || die "$dev is '$model'; this tool updates Crucial MX500 disks only"

current=$(msecli_field FW-Rev "$dev")
serial=$(msecli_field 'Serial No' "$dev")
[ -n "$current" ] && [ -n "$serial" ] || die "msecli did not report a firmware revision and serial for $dev"

if [ "$current" = "$target" ]; then
    printf '%s %s serial %s already runs %s; nothing to do\n' "$dev" "$model" "$serial" "$target"
    exit 0
fi

allowed=$(sed -n 's/^precondition=//p' "$FWROOT/firmware/firmware.properties")
case ",$allowed," in
    *",$current,"*) ;;
    *) die "$dev runs $current; the packaged firmware accepts only $allowed" ;;
esac

# In-use detection: a mount or swap on the disk or a partition, a kernel
# holder (md array, device-mapper target), or a signature of a stack that can
# hold the disk open without a mount (RAID member, LVM PV, ZFS vdev, LUKS,
# bcache).
mounts=$("$LSBLK" -nro MOUNTPOINTS "$dev" | sed '/^$/d' | tr '\n' ' ')
[ -z "$mounts" ] || add_blocker "active mounts or swap ($mounts)"

holders=$(find "$SYSFS/block/${dev##*/}" -maxdepth 3 -path '*/holders/*' -printf '%f\n' 2>/dev/null | sort -u | tr '\n' ' ')
[ -z "$holders" ] || add_blocker "kernel holders ($holders)"

members=$("$LSBLK" -nro FSTYPE "$dev" | grep -xE 'linux_raid_member|LVM2_member|zfs_member|crypto_LUKS|bcache' | sort -u | tr '\n' ' ' || true)
[ -z "$members" ] || add_blocker "member signatures ($members)"

printf 'plan: %s %s serial %s: %s -> %s\n' "$dev" "$model" "$serial" "$current" "$target"
if [ -n "$blockers" ]; then
    die "$dev is in use: $blockers; release it first"
fi
[ "$mode" = check ] && exit 0

if [ "$assume_yes" -ne 1 ]; then
    printf 'Type the serial number %s to flash: ' "$serial"
    read -r answer || die "no confirmation read; aborting"
    [ "$answer" = "$serial" ] || die "serial mismatch; aborting"
fi

log=$LOGDIR/$prog-$serial.log
# msecli asks "Are you sure (Y|N)" on stdin; the confirmation above is the gate.
printf 'Y\n' | "$MSECLI" -U -i "$FWROOT/firmware" -n "$dev" -v -s "$log" ||
    die "msecli failed; see $log"

after=$(msecli_field FW-Rev "$dev")
if [ "$after" = "$target" ]; then
    printf '%s now reports %s (log: %s)\n' "$dev" "$after" "$log"
    printf 'Power the machine off completely (not a warm reboot) and start it again so the drive runs the new image, then run: %s --check %s\n' "$prog" "$dev"
else
    die "$dev reports $after after the update, expected $target; power the machine off completely and run '$prog --check $dev'"
fi
