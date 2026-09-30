#!/bin/bash
# build-kernel.sh — build the Qua Station 6.18 kernel (Image, DTB, modules) from the monarch-6.18 fork.
# usage: ./build-kernel.sh <kernel-src-dir(branch qua-dist)> <outdir>
# The initramfs (kernel/initramfs-init + a static busybox with findfs/switch_root/devmem) is built into the Image:
# CONFIG_INITRAMFS_SOURCE must point at a directory laid out as  init, bin/busybox, bin/<applet symlinks>, dev, proc, sys, mnt, tmp
set -euo pipefail
SRC=${1:?kernel source}; OUT=${2:?outdir}; HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT"; cd "$SRC"
cp "$HERE/kernel/config-6.18.52-qua1" .config
sed -i "s|^CONFIG_INITRAMFS_SOURCE=.*|CONFIG_INITRAMFS_SOURCE=\"$HERE/kernel/initramfs\"|" .config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image dtbs modules
"$HERE/build/make-uimage.py" arch/arm64/boot/Image "$OUT/uImage"
cp arch/arm64/boot/dts/realtek/rtd1295-qua-station.dtb "$OUT/QuaStation.dtb"
rm -rf "$OUT/modules"; make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$OUT/modules" modules_install
rm -f "$OUT"/modules/lib/modules/*/build "$OUT"/modules/lib/modules/*/source
ls "$OUT/modules/lib/modules"
