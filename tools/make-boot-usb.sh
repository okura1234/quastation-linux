#!/bin/bash
# make-boot-usb.sh — prepare the USB stick the vendor U-Boot boots from (FAT32, label BOOT, holds uImage + QuaStation.dtb).
#   sudo ./make-boot-usb.sh /dev/sdX uImage QuaStation.dtb
# THIS ERASES THE USB STICK. The vendor U-Boot reads /uImage and /QuaStation.dtb from the first FAT partition of the first USB disk.
set -euo pipefail
DISK=${1:?usb stick}; UI=${2:?uImage}; DTB=${3:?QuaStation.dtb}
[ -b "$DISK" ] || exit 1
lsblk -o NAME,SIZE,MODEL "$DISK"; read -rp "ERASE $DISK? [type YES] " a; [ "$a" = YES ] || exit 1
for m in $(lsblk -nro MOUNTPOINT "$DISK" | grep . ); do umount "$m"; done 2>/dev/null || true
wipefs -a "$DISK"
parted -s "$DISK" mklabel msdos mkpart primary fat32 1MiB 256MiB set 1 boot on
partprobe "$DISK"; sleep 2
P=$(lsblk -nrpo NAME "$DISK" | sed -n 2p)
mkfs.vfat -F 32 -n BOOT "$P"
M=$(mktemp -d); mount "$P" "$M"; cp "$UI" "$M/uImage"; cp "$DTB" "$M/QuaStation.dtb"; sync; umount "$M"; rmdir "$M"
echo "done. Optional: copy a wpa_supplicant.conf onto this stick; it is imported on first boot."
