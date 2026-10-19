# Linux 7.3 への移植パッチ（2026-10-19・実機稼働中）

mainline **v7.3**（Linus のリリース版）に当てると Qua Station（RTD1295）で起動する一連のパッチです。
実機で **SATA root・USB 3.0/2.0・RTL-SDR・USB-LAN・Bluetooth・Wi-Fi 5 GHz（mainline rtl8821ae）・Wi-Fi 2.4 GHz（rtl8192ee）・Docker 13 コンテナ** の動作を確認しています（`7.3.0-7x07`）。

7.2.11 用の系列（[`../patches-7.2.11/`](../patches-7.2.11/)）に 7.3 の API 変更 1 件を足しただけです。
7.2 → 7.3 で RTD1295 側の差分に衝突はありませんでした。

| ファイル | 内容 |
|---|---|
| `0001` | monarch-6.18 ＋ Qua 用パッチの RTD1295 差分（約 1.8 万行・ほぼ追加のみ） |
| `0002` | 7.2 の API 変更への追従 4 件（`clk_ops.determine_rate` / `of_gpio.h` 削除 / `reserved_mem.fdt_node` 削除 / PCIe MSI を `msi_parent_ops` へ） |
| `0003` | PCIe の MSI を無効化（INTx 経路）。切り分け用に入れたまま。戻せる見込み（未確認） |
| `0004` | `pcie-rtd129x` の `alloc_workqueue` に `WQ_PERCPU`（7.x の WARNING 対策） |
| `0005` | **rtlwifi の workqueue を per-CPU に戻す。これが無いと Wi-Fi の if up で無言ハング→再起動ループ**（7.x 上流の `WQ_UNBOUND` 化が原因） |
| `0006` `0007` | **PCIe host の自動リンク再トレーニング**。2.4 GHz 側（RTL8192EE）のリンクが列挙後に落ちる個体差（6.18/7.2/7.3 共通・約 1/3 の起動）に対し、cfg アクセスの timeout が続いたら EP をリセットして再トレーニング→再列挙。手動は `echo 1 > /sys/bus/platform/devices/9804e000.pci/retrain` |
| `0008` | **7.3 で削除された `irq_domain_add_linear()` を `irq_domain_create_linear(of_fwnode_handle())` に置換**（irqchip と PCIe の 2 か所）。7.3 で必要だった変更はこれだけ |
| `../config-7.3.0-7x07` | 実機で動かしている `.config`（`CONFIG_INITRAMFS_SOURCE` と `CONFIG_CMDLINE` の `root=` は自分の環境に合わせること） |

## 当て方

```bash
git clone --depth=1 -b v7.3 https://github.com/gregkh/linux.git linux-7.3
cd linux-7.3
git am --3way ../patches-7.3.0/*.patch          # 素の v7.3 に 8 本すべて当たることを確認済み（2026-10-19）
cp ../config-7.3.0-7x07 .config
# CONFIG_INITRAMFS_SOURCE（kernel/initramfs の絶対パス）と root= を自分の環境に直す
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=-7x -j4 Image dtbs modules
```

uImage 化（`text_offset` の書き換え・末尾パディング）は `build/make-uimage.py`、
まとめてやるなら `build/build-kernel.sh linux-7.3 out/kernel`（既定でこの config を使います）。

## 既知の事項

- `r8169soc`（内蔵 GMAC）は NETPOLL 有効時にコンパイルが通らないため config で無効化しています。副作用で USB-LAN の名前が `eth1`→`eth0` になります（`.network` を MAC 一致にしておけば実害なし）
- `pcie-rtd129x.c` に未使用変数の警告が 1 件出ます（MSI を切っている影響。無害）
- 2.4 GHz（RTL8192EE）の PCIe リンクが列挙後に落ちることがあります。`0006`/`0007` の自動再トレーニングで復帰する想定（手動トリガは実機確認済み・自動発火は観測中）
- 7.3 で良くなるところは、この機体に関しては**特にありません**。上げる理由は「次の LTS に乗り換えられる状態を保つ」「セキュリティ修正が届く側にいる」の 2 つです
- initramfs の `init` は busybox `findfs` が `PARTUUID=` を解釈しない問題を直した版（`kernel/initramfs/init`）を使ってください

経緯と切り分けの詳細: [Qiita 導入記録（7）Linux 7.2→7.3 移植編](https://qiita.com/kaz32/items/6e37a54b2a68b7f5e27d)
