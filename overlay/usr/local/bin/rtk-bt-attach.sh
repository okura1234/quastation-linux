#!/bin/bash
# Realtek RTL8761ATV を /dev/ttyS1 (H5) に attach する
# 2026-09-20: 6.18環境へ移植。旧24.04版は rfkill1 決め打ちだったのを動的検索に変更。
# 2026-09-20(2): pinmux 確認と GPIO63 による電源リセットを追加。
#
# ⚠️ 罠1: FWロード済みのチップに再attachすると版数照合が外れ rtl_none_fw を探して失敗する(実測)。
#         必ずチップの電源を落としてから attach すること。
# ⚠️ 罠2: rfkill の bluetooth エントリは hci0 が存在する間しか現れない（鶏と卵）。
#         そのため rfkill が無い場合は GPIO を直接叩く。
#         GPIO の出典 = 4.9 ベンダー DTB の
#           rfkilligpio { compatible = "realtek,rfkill";
#                         gpios = <&rtk_misc_gpio@9801b100 63 1 1>; }
#         → 6.18 では gpiochip1 の line 63。どのドライバも claim していない。
# 🚩 IC: NONE / rtl_none_fw が見つからないエラーは出るが致命的ではない。
#    eFuse の設定にフォールバックして hci0 は UP RUNNING になる（2026-09-20 実測）。
set -u

BT_GPIO_CHIP=gpiochip1
BT_GPIO_LINE=63

# カーネルにBluetoothが無ければ何もせず正常終了（旧カーネルで起動した時の空振り防止）
if [ ! -d /sys/class/bluetooth ]; then
  echo "[rtk-bt] カーネルにBluetoothサポートが無いためスキップ"
  exit 0
fi
[ -c /dev/ttyS1 ] || { echo "[rtk-bt] /dev/ttyS1 が無い"; exit 1; }

# --- pinmux が当たっているか確認（qua-uart1-pinmux.service が先に走る想定）---
if [ -x /usr/local/bin/qua-uart1-pinmux.py ]; then
  /usr/local/bin/qua-uart1-pinmux.py || echo "[rtk-bt] pinmux 適用に失敗（続行する）"
else
  # 無言でスキップすると、BT が繋がらない時にログから原因（配置漏れ・実行権限漏れ）が追えない
  echo "[rtk-bt] ⚠️ /usr/local/bin/qua-uart1-pinmux.py が無いか実行不可。pinmux 未適用の可能性あり"
fi

# --- チップの電源リセット ---
RF=""
for d in /sys/class/rfkill/rfkill*; do
  [ -r "$d/type" ] || continue
  if [ "$(cat "$d/type")" = "bluetooth" ]; then RF="$d"; break; fi
done

if [ -n "$RF" ]; then
  echo "[rtk-bt] rfkill=$RF で電源リセット"
  echo 1 > "$RF/soft"; sleep 1
  echo 0 > "$RF/soft"; sleep 1
elif command -v gpioset >/dev/null 2>&1; then
  echo "[rtk-bt] rfkill が無いので $BT_GPIO_CHIP line $BT_GPIO_LINE で電源リセット"
  timeout 20 gpioset -c "$BT_GPIO_CHIP" -t 3s,0 "$BT_GPIO_LINE"=0 \
    || echo "[rtk-bt] gpioset 失敗（続行する）"
  sleep 2
else
  echo "[rtk-bt] 電源リセット手段が無い（rfkill も gpioset も不在）。そのまま attach を試す"
fi

echo "[rtk-bt] rtk_hciattach 実行"
exec /usr/local/bin/rtk_hciattach -n -s 115200 /dev/ttyS1 rtk_h5
