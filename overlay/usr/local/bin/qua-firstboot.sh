#!/bin/bash
# Runs on every boot (fast no-op after the first): host keys, swapfile, Wi-Fi import from BOOT.
set -u
log(){ echo "[qua-firstboot] $*"; }
# 1. SSH host keys (removed from the image on purpose)
if ! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
  ssh-keygen -A && log "generated ssh host keys"
fi
# 2. swapfile (2 GiB) on the root filesystem
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && log "created /swapfile"
fi
swapon /swapfile 2>/dev/null || true
# 3. Wi-Fi config dropped on the BOOT partition
B=$(findfs LABEL=BOOT 2>/dev/null) || B=""
if [ -n "$B" ]; then
  mkdir -p /run/qua-boot && mount -o rw "$B" /run/qua-boot 2>/dev/null && {
    if [ -f /run/qua-boot/wpa_supplicant.conf ]; then
      for i in wlan0 wlan1; do install -m 600 /run/qua-boot/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant-$i.conf; done
      systemctl enable --now wpa_supplicant@wlan0 wpa_supplicant@wlan1 >/dev/null 2>&1
      mv /run/qua-boot/wpa_supplicant.conf /run/qua-boot/wpa_supplicant.conf.imported
      sync; log "imported wpa_supplicant.conf from BOOT"
    fi
    umount /run/qua-boot
  }
fi
exit 0
