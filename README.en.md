# Qua Station (au HVD1 / RTD1295) — mainline Linux 7.3 / 6.18 LTS + Ubuntu 26.04

> ⚠️ **Status: v0.1 (pre-release).** Rebuilt from a running unit (same kernel config, same DTB, hand-built rootfs of the same shape), but **this exact image has not yet been boot-tested on hardware**. Reports welcome via Issues.

Distribution kit that runs the au **Qua Station (HVD1, Realtek RTD1295)** on a **mainline-based Linux 6.18 LTS** kernel with
**Ubuntu 26.04 (arm64)** instead of the vendor 4.9 kernel. All on-board hardware that is reachable from Linux is enabled.

Japanese walkthrough: [Qiita (6)](https://qiita.com/kaz32/items/9984c6e11d5331066a3e)

## Kernel lines (since 2026-10-19)

| line | version | role | where |
|---|---|---|---|
| **main** | **7.3** (`7.3.0-7x07`) | running on the real box; re-applied onto each new stable | vanilla v7.3 + [`kernel/patches-7.3.0/`](kernel/patches-7.3.0/) (8 patches, verified with `git am --3way`) + `kernel/config-7.3.0-7x07` |
| stable / fallback | 6.18 LTS | the distributed uImage is still this line | fork [`okura1234/monarch-6.18`](https://github.com/okura1234/monarch-6.18), branch `qua-dist-6.18.56` |

Nothing gets noticeably better on this box with 7.3; the point is staying on a line that can move to the next LTS.

## Hardware status
CPU 4× A53 / 2 GB ✅ · SATA bay ✅ (root lives here, found by `LABEL=qua-root`) · USB 3.0 ×2 + USB 2.0 ✅ · Wi-Fi 5 GHz RTL8812AE ✅ (`rtl8821ae`) ·
Wi-Fi 2.4 GHz RTL8192EE ✅ (rx can stick at 1 Mbps) · Bluetooth RTL8761ATV ✅ (auto pinmux + `rtk_hciattach`) · LTE modem 🟡 (detected, SIM untested) ·
eMMC ❌ (not detected on 6.18; vendor U-Boot only boots from USB anyway) · 11 LEDs + COPY button ✅ · internal GMAC — (no RJ45 on most units) · Mali GPU — (headless).

## Files
`uImage` (kernel 6.18.52-qua1 with built-in initramfs, header patched for the vendor U-Boot), `QuaStation.dtb`,
`quastation-ubuntu2604-rootfs.tar.gz`, `tools/flash-ssd.sh`, `tools/make-boot-usb.sh`.

## Install
1. `sudo tools/flash-ssd.sh /dev/sdX quastation-ubuntu2604-rootfs.tar.gz` — erases the SSD, one ext4 partition labelled `qua-root`.
2. `sudo tools/make-boot-usb.sh /dev/sdY uImage QuaStation.dtb` — erases the USB stick, FAT32 labelled `BOOT`.
   Optionally drop a `wpa_supplicant.conf` on it (template in `overlay/etc/wpa_supplicant/`); it is imported on first boot.
3. Insert SSD and USB stick, plug a USB Ethernet adapter (Realtek RTL8153 recommended) into your router, power on.
   Front-left LED lights up, then after ~40–60 s the HDD LED turns from red to green.
4. `ssh qua@quastation.local` (mDNS) — user `qua`, password `qua`, **password change is forced at first login**, `sudo` works.
   Direct PC-to-box cable without a router: set the PC to 192.168.1.x and use `192.168.1.44`.

First boot (`qua-firstboot.service`) generates SSH host keys, creates `/swapfile` (2 GB) and imports the Wi-Fi config from the BOOT stick.

## Networking
systemd-networkd matches NICs by **driver name** (never `Name=`: wlan0/wlan1 swap between boots).
Route metrics: GMAC 10 → USB-LAN 20 → 5 GHz 100 → 2.4 GHz 600 → anything else 1000. Both `wpa_supplicant@wlan0` and `@wlan1` get the same config.

## Bluetooth
Mainline has no RTD1295 pinctrl driver, so `qua-uart1-pinmux.service` writes register `0x98007310` every boot to route uart1 to the pins;
`rtk-bluetooth.service` then attaches the chip on `/dev/ttyS1` (H5) with `rtk_hciattach`.

## Known issues
Rare silent root I/O hang (ping works, nothing can exec) — `qua-iowd.service` detects it and reboots via sysrq; disable if unwanted.
PCIe IRQ chatter from the 5 GHz card in `dmesg`. 2.4 GHz rx may stick at 1 Mbps. `rtl_nic/rtl8153a-2.fw` load failure is harmless.
No eMMC boot (vendor U-Boot 2015.07 reads only USB `uImage`/`QuaStation.dtb`; a serial console is needed to change `bootcmd`). Timezone defaults to UTC.

## Build it yourself
`build/build-kernel.sh <okura1234/monarch-6.18, branch qua-dist> out/kernel` then
`sudo build/build-rootfs.sh ubuntu-base-26.04.1-base-arm64.tar.gz out/kernel/modules/lib/modules/6.18.52-qua1+ out/rootfs` (needs qemu-user-binfmt on x86).
`DIST_USER`/`DIST_PASS` override the default account.

## Credits
Kernel base: [symops/monarch-6.18](https://github.com/symops/monarch-6.18) (WD My Cloud Home, same SoC) plus Qua-specific DTS, SATA clock/power, PCIe MSI fixes,
USB 2.0, LEDs and initramfs. References: Andreas Färber's rtd1295 tree, kisgezenguz/linux-4.9 (vendor BSP). `rtk_hciattach` built from radxa/rtkbt.
Wi-Fi firmware from linux-firmware (redistributable). ⚠️ BT firmware `rtlbt/rtl8761a_fw` / `rtl_bt/rtl8761a_fw.bin` was extracted from the device's own Android eMMC image and differs from the linux-firmware `rtl8761a_fw.bin`; redistribution is at your own discretion (the linux-firmware file can be dropped in with the same name, untested).

Kernel and scripts: GPL-2.0. Firmware under the respective vendor licences.
