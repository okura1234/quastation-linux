# Linux 7.2.11 への移植パッチ（実験的・2026-10-18）

mainline **v7.2.11** に当てると Qua Station（RTD1295）で起動する一連のパッチです。
6.18 系（`okura1234/monarch-6.18` ブランチ `qua-dist-6.18.56`）に入っている RTD1295 対応一式を 7.2 へ載せ替えたもので、
実機で **SATA root・USB 3.0/2.0・RTL-SDR・USB-LAN・Bluetooth・Wi-Fi 5 GHz（mainline rtl8821ae）・Docker** の動作を確認しています。

| ファイル | 内容 |
|---|---|
| `0001-*.patch` | monarch-6.18 ＋ Qua 用パッチの RTD1295 差分を v7.2.11 に当てたもの（約 1.8 万行・ほぼ追加のみ。Kconfig/Makefile の衝突 4 件は解決済み） |
| `0002-*.patch` | 7.2 の API 変更への追従 4 件（`clk_ops.determine_rate` / `of_gpio.h` 削除 / `reserved_mem.fdt_node` 削除 / PCIe MSI を `msi_parent_ops` へ） |
| `0003-*.patch` | PCIe の MSI を無効化（INTx 経路）。切り分け用に入れたまま。Wi-Fi の死因は MSI ではなかったので戻せる見込み（未確認） |
| `0004-*.patch` | `pcie-rtd129x` の `alloc_workqueue` に `WQ_PERCPU`（7.x の WARNING 対策） |
| `0005-*.patch` | **rtlwifi の workqueue を per-CPU に戻す。これが無いと Wi-Fi の if up で無言ハング→再起動ループ**（7.x 上流の `WQ_UNBOUND` 化が原因。rtw88 の同型変更は上流で revert 済み） |
| `0006-*.patch` | （⚠️ 素の `git diff` でヘッダ無し。`git am` では止まるので `git apply` で当てる。format-patch 版は `../patches-7.3.0/0006`,`0007`）**PCIe host の自動リンク再トレーニング**。2.4GHz 側（RTL8192EE）のリンクが列挙後に落ちる個体差（6.18/7.2 共通・約 1/3 の起動で発生）に対し、cfg アクセスの timeout が 3 回続いたら EP をリセットして再トレーニング→再列挙する。手動は `echo 1 > /sys/bus/platform/devices/9804e000.pci/retrain`（実測 0.3 秒で復帰） |
| `../config-7.2.11-7x05` | 実機で動かしている `.config`（稼働機の 6.18 config を `olddefconfig` したもの。`CONFIG_CMDLINE` の `root=` は自分の環境に合わせること） |

## 当て方

```bash
git clone --depth=1 -b v7.2.11 https://github.com/gregkh/linux.git linux-7.2
cd linux-7.2
git am ../patches-7.2.11/*.patch        # または git apply --3way
cp ../config-7.2.11-7x05 .config
# initramfs の置き場（CONFIG_INITRAMFS_SOURCE）と root= を自分の環境に直す
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=-7x -j4 Image dtbs modules
```

uImage 化（`text_offset` の書き換え・末尾パディング）は 6.18 と同じで `build/make-uimage.py` を使えます。

## 既知の事項

- `r8169soc`（内蔵 GMAC）は NETPOLL 有効時に 7.2 でコンパイルが通らないため config で無効化しています。副作用で USB-LAN の名前が `eth1`→`eth0` になります（`.network` を MAC 一致にしておけば実害なし）
- 2.4 GHz（RTL8192EE）の PCIe リンクが列挙後に落ちることがあります（6.18 でも発生・約 1/3 の起動）。`0006` の自動再トレーニングで復帰する想定（手動トリガは実機確認済み・自動発火は観測待ち）
- 6.18 で必要だった「5 GHz をベンダー 8812ae.ko にバインドし直す service」は 7.2 では不要でした（mainline `rtl8821ae` で接続）
- initramfs の `init` は busybox `findfs` が `PARTUUID=` を解釈しない問題を直した版（`kernel/initramfs/init`）を使ってください

経緯と切り分けの詳細: [Qiita 導入記録（7）Linux 7.2→7.3 移植編](https://qiita.com/kaz32/items/6e37a54b2a68b7f5e27d)
