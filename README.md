# Qua Station (au HVD1 / RTD1295) — mainline Linux 6.18 + Ubuntu 26.04

> ⚠️ **状態: v0.1 (pre-release)**。この配布セットは稼働中の実機（同じカーネル設定・同じ DTB・同じ構成の手組み rootfs）から再構成したものですが、**配布イメージそのものでの実機起動はまだ検証していません**。試した結果は Issue で知らせてもらえると助かります。

au **Qua Station (HVD1, Realtek RTD1295)** を、ベンダー 4.9 カーネルではなく **mainline 系 Linux 6.18 LTS** と
**Ubuntu 26.04 (arm64)** で動かすための配布セットです。ハードウェアはひととおり Linux から使える状態にしてあります。

[English README](README.en.md) ／ 解説記事（導入手順）: [Qiita 導入記録（6）配布イメージ公開編](https://qiita.com/kaz32/items/9984c6e11d5331066a3e)

## 何が動くか

| ハード | 状態 | 備考 |
|---|---|---|
| CPU 4 コア (Cortex-A53) / 2 GB RAM | ✅ | zram swap (768 MB, lz4) ＋ root 上に 2 GB swapfile |
| SATA (内蔵 2.5 インチベイ) | ✅ | **root はここ**。`LABEL=qua-root` で探す |
| USB 3.0 ×2 / 本体 USB 2.0 | ✅ | USB-LAN・USB メモリ・RTL-SDR など |
| Wi-Fi 5 GHz (RTL8812AE, PCIe) | ✅ | mainline `rtl8821ae`。主回線向け |
| Wi-Fi 2.4 GHz (RTL8192EE, PCIe) | ✅ | 予備回線。rx が 1 Mbps に張り付く持病あり |
| Bluetooth (RTL8761ATV, UART H5) | ✅ | 起動時に pinmux と `rtk_hciattach` を自動実行 |
| LTE モデム (ASKEY WWHC060, USB) | 🟡 | `cdc_ether`/`qmi_wwan` で検出。SIM 運用は未検証 |
| eMMC (8 GB) | ❌ | 6.18 では未認識（ベンダー 4.9 では読めた）。起動にも使わない |
| LED 11 個・COPY ボタン | ✅ | `/sys/class/leds/`。起動完了で HDD LED が赤→緑 |
| 内蔵 GMAC | — | 筐体に RJ45 が無い個体がほとんど。ドライバは載るが link down のまま |
| Mali GPU | — | ヘッドレス前提。未対応 |


## 🧪 Linux 7.2 への移植（実験的・2026-10-18）

mainline **7.2.11** でも起動・稼働することを実機で確認しました（SATA root・USB・RTL-SDR・Bluetooth・Wi-Fi 5 GHz・Docker 13 コンテナ）。
パッチ列と config は [`kernel/patches-7.2.11/`](kernel/patches-7.2.11/) にあります。
Wi-Fi が起動時に無言ハングする問題は上流 rtlwifi の `WQ_UNBOUND` 化が原因で、`0005` のパッチで回避しています。
配布イメージ（uImage/rootfs）は引き続き 6.18 系です。

## 配布物

| ファイル | 内容 |
|---|---|
| `uImage` | カーネル 6.18.52-qua1（initramfs 内蔵、raw arm64 Image を U-Boot 向けにヘッダ調整済み） |
| `QuaStation.dtb` | Qua Station 用 Device Tree |
| `quastation-ubuntu2604-rootfs.tar.gz` | Ubuntu 26.04 root filesystem（モジュール・ファームウェア・起動用サービス込み） |
| `tools/flash-ssd.sh` | SSD を 1 パーティションで初期化して rootfs を展開 |
| `tools/make-boot-usb.sh` | 起動用 USB メモリ（FAT32, `BOOT`）を作る |

## 導入手順

必要なもの: 2.5 インチ SATA SSD/HDD、USB メモリ（1 GB 以上）、USB-LAN アダプタ（Realtek RTL8153 系推奨）、
作業用 Linux PC（USB-SATA 変換があると楽）。

1. **SSD を作る**（PC で）
   ```bash
   sudo tools/flash-ssd.sh /dev/sdX quastation-ubuntu2604-rootfs.tar.gz   # sdX = SSD。全消去
   ```
   1 パーティション・ext4・ラベル `qua-root` になります。
2. **起動 USB を作る**（PC で）
   ```bash
   sudo tools/make-boot-usb.sh /dev/sdY uImage QuaStation.dtb              # sdY = USB メモリ。全消去
   ```
   Wi-Fi を最初から使いたい場合は、この USB に `wpa_supplicant.conf` を置いてください
   （雛形: `overlay/etc/wpa_supplicant/wpa_supplicant.conf.example`）。初回起動時に取り込まれます。
3. SSD をベイに、USB メモリを背面 USB に挿し、**USB-LAN をルーターに繋いで**電源 ON。
   前面左 LED が点灯 → 約 40〜60 秒で HDD LED が赤から緑に変われば起動完了。
4. **ログイン**
   ```bash
   ssh qua@quastation.local        # mDNS。だめならルーターの DHCP 一覧で "quastation" を探す
   ```
   ユーザー `qua` / パスワード `qua`。**初回ログインでパスワード変更を求められます**。`sudo` 可。
   ルーターが無く PC と直結する場合は PC 側を `192.168.1.x` にして `ssh qua@192.168.1.44`。

## 初回起動時に自動で行われること
`qua-firstboot.service` が SSH ホスト鍵の生成、`/swapfile` (2 GB) の作成、BOOT USB 上の `wpa_supplicant.conf` の取り込みを行います。

## ネットワークの考え方
`systemd-networkd` で **ドライバ名で NIC を判定**しています（`Name=` は使いません。wlan0/wlan1 の割り当ては起動ごとに入れ替わるため）。
優先度: 内蔵 GMAC (10) → USB-LAN (20) → 5 GHz (100) → 2.4 GHz (600) → その他 (1000)。
Wi-Fi は `wpa_supplicant@wlan0` と `@wlan1` の両方に同じ設定を入れます（`/etc/wpa_supplicant/README`）。

## Bluetooth
mainline 6.18 には RTD1295 の pinctrl ドライバが無いため、`qua-uart1-pinmux.service` が起動ごとにレジスタ `0x98007310` を書いて
uart1 のピンを有効化し、`rtk-bluetooth.service` が `rtk_hciattach` で `/dev/ttyS1` に H5 で attach します。`bluetoothctl` で使えます。

## 既知の問題・注意
- **root I/O ハング**（SATA が無言で止まり、ping は通るのに何も exec できなくなる）が稀に起きます。`qua-iowd.service` が検知して
  `sysrq b` で自動再起動します。不要なら `systemctl disable qua-iowd`。
- 5 GHz カード側の PCIe 割り込みがログを埋めることがあります（無害だが `dmesg` が読みにくい）。
- 2.4 GHz カードは受信が 1 Mbps に固着することがあります。SSH は通ります。
- USB-LAN で `rtl_nic/rtl8153a-2.fw` の読み込み失敗が出ますが、無くても動きます（気になるなら `linux-firmware` を入れる）。
- eMMC からの起動は未対応。U-Boot（ベンダー 2015.07）は USB の `uImage`/`QuaStation.dtb` しか読みません。
  シリアルコンソール（内部 UART, 115200）があると `bootcmd` を変えられます。
- タイムゾーンは UTC。`sudo timedatectl set-timezone Asia/Tokyo` で変更。

## 自分でビルドする
```bash
# カーネル（ホスト: Ubuntu 26.04 x86_64, gcc-aarch64-linux-gnu）
git clone -b qua-dist-6.18.56 https://github.com/okura1234/monarch-6.18 linux-qua   # symops/monarch-6.18 の fork（6.18.56 追従版。旧 qua-dist は 6.18.52）
build/build-kernel.sh linux-qua out/kernel
# rootfs（qemu-user-binfmt が必要）
sudo build/build-rootfs.sh ubuntu-base-26.04.1-base-arm64.tar.gz out/kernel/modules/lib/modules/6.18.52-qua1+ out/rootfs
```
`DIST_USER` / `DIST_PASS` 環境変数で初期ユーザーを変えられます。

## 中身の出典・謝辞
- カーネル土台: [symops/monarch-6.18](https://github.com/symops/monarch-6.18)（WD My Cloud Home＝同じ RTD1295）。Qua 向けに DTS、SATA クロック/電源、PCIe(MSI 修正)、USB2.0、LED、initramfs を追加
- 参考: Andreas Färber 氏の rtd1295 実験ツリー、kisgezenguz/linux-4.9（ベンダー BSP）
- `rtk_hciattach`: radxa/rtkbt を本機でビルドしたもの
- Wi-Fi ファームウェア: linux-firmware の `rtlwifi/`（再配布可）
- ⚠️ BT ファームウェア `rtlbt/rtl8761a_fw`・`rtl_bt/rtl8761a_fw.bin`: **本機 eMMC の Android 領域から取り出したもの**（linux-firmware 収録の `rtl8761a_fw.bin` とは別物・ハッシュ不一致）。再配布の可否は各自判断。差し替える場合は linux-firmware 版を同名で置く（動作未確認）

## ライセンス
カーネル・スクリプトは GPL-2.0。ファームウェアは各ベンダーのライセンスに従います。
