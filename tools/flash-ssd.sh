#!/bin/bash
# flash-ssd.sh — write the Qua Station root filesystem onto a SATA SSD/HDD (single partition layout).
# Run on a PC with the disk attached via USB-SATA, or on the Qua Station itself booted from the old system.
#   sudo ./flash-ssd.sh /dev/sdX quastation-ubuntu2604-rootfs.tar.gz
# THIS ERASES THE WHOLE DISK.
set -euo pipefail
DISK=${1:?target disk, e.g. /dev/sdb}; TAR=${2:?rootfs tarball}
[ -b "$DISK" ] || { echo "$DISK is not a block device"; exit 1; }
lsblk -o NAME,SIZE,MODEL,MOUNTPOINT "$DISK"; read -rp "ERASE $DISK and install Qua Station rootfs? [type YES] " a; [ "$a" = YES ] || exit 1
for m in $(lsblk -nro MOUNTPOINT "$DISK" | grep . ); do umount "$m"; done 2>/dev/null || true
wipefs -a "$DISK"
parted -s "$DISK" mklabel msdos mkpart primary ext4 1MiB 100%
partprobe "$DISK"; sleep 2
P=$(lsblk -nrpo NAME "$DISK" | sed -n 2p)
mkfs.ext4 -q -F -L qua-root "$P"
M=$(mktemp -d); mount "$P" "$M"
tar --keep-directory-symlink --numeric-owner --xattrs -xzpf "$TAR" -C "$M"
for l in lib bin sbin; do [ -L "$M/$l" ] || { echo "usrmerge symlink /$l broken"; exit 1; }; done
sync; umount "$M"; rmdir "$M"
echo "done: $P labelled qua-root. Put uImage + QuaStation.dtb on the BOOT USB stick (see make-boot-usb.sh) and power on."
