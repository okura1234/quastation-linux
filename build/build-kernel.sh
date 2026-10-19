#!/bin/bash
# build-kernel.sh — build the Qua Station kernel (Image, DTB, modules).
# usage: ./build-kernel.sh <kernel-src-dir> <outdir> [config]
#   default config = kernel/config-7.3.0-7x07 (mainline v7.3 + kernel/patches-7.3.0/).
#   for the 6.18 line (monarch-6.18 fork, branch qua-dist-6.18.56) pass kernel/config-6.18.52-qua1.
# The initramfs (kernel/initramfs-init + a static busybox with findfs/switch_root/devmem) is built into the Image:
# CONFIG_INITRAMFS_SOURCE must point at a directory laid out as  init, bin/busybox, bin/<applet symlinks>, dev, proc, sys, mnt, tmp
set -euo pipefail
SRC=${1:?kernel source}; OUT=${2:?outdir}; HERE=$(cd "$(dirname "$0")/.." && pwd)
CFG=${3:-$HERE/kernel/config-7.3.0-7x07}
mkdir -p "$OUT"; cd "$SRC"
cp "$CFG" .config
sed -i "s|^CONFIG_INITRAMFS_SOURCE=.*|CONFIG_INITRAMFS_SOURCE=\"$HERE/kernel/initramfs\"|" .config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image dtbs modules
"$HERE/build/make-uimage.py" arch/arm64/boot/Image "$OUT/uImage"
cp arch/arm64/boot/dts/realtek/rtd1295-qua-station.dtb "$OUT/QuaStation.dtb"
rm -rf "$OUT/modules"; make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$OUT/modules" modules_install
rm -f "$OUT"/modules/lib/modules/*/build "$OUT"/modules/lib/modules/*/source
ls "$OUT/modules/lib/modules"
