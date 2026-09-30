#!/bin/bash
# qua-iowd : root I/O ハング検知ウォッチドッグ
#
# 🚩 なぜ必要か（2026-09-21 の実害）
#   15:36:50 に rootfs(SATA sdb4) の I/O が無言で停止した。
#   ・journald も書けない（ログが一切残らない）
#   ・新しいプロセスを exec できない（SSH は接続だけ通って即 reset）
#   ・しかし ping は 4-9ms で応答し続ける（カーネルとネットは生きている）
#   この状態が約5分半続き、最後は物理で電源を抜くしかなかった。
#   復旧に半日を要し、ADS-B も停止した。
#
# 🔴 systemd の RuntimeWatchdogSec は「この種のハング」では発火しない。
#    systemd 本体はメモリ上で動き続けるので watchdog を pet し続けてしまう。
#
# 🔴 設計上の制約: ハング中は exec ができない。
#    /bin/sleep も /usr/bin/timeout も rootfs 上にあるため起動できない。
#    よって本スクリプトは **bash の組み込みコマンドだけ**で1周を回す:
#      待ち     → read -t + tmpfs 上の名前付きパイプ（sleep を使わない）
#      生死判定 → rootfs にファイルを作る（メタデータ書き込み＝ジャーナルが要る）
#      時間切れ → サブシェルを fork して kill -0 で監視（fork は exec を伴わない）
#      再起動   → echo b > /proc/sysrq-trigger（procfs なのでハングしない）
#
# 🚫 ここに外部コマンドを足さないこと。足した瞬間、肝心の場面で動かなくなる。

PROBE_DIR=/var/lib/qua-iowd
PROBE="$PROBE_DIR/probe"
FIFO=/run/qua-iowd.fifo          # tmpfs 上（ハング中も使える）

INTERVAL=30                      # 判定間隔（秒）
IO_TIMEOUT=10                    # 1回の書き込みに許す秒数
THRESHOLD=6                      # 連続失敗がこの回数でリブート（6×30s = 3分）

set +m                          # kill -9 の "Killed" メッセージを出さない
fails=0

# fd 9 = 何も流れてこないパイプ。read -t の「眠るだけ」に使う
exec 9<>"$FIFO"
# fd 8 = カーネルリングバッファ。組み込み echo で書ける
exec 8>/dev/kmsg 2>/dev/null

log() { echo "qua-iowd: $1" >&8 2>/dev/null; }

log "started (interval=${INTERVAL}s timeout=${IO_TIMEOUT}s threshold=${THRESHOLD})"

while : ; do
    # --- rootfs への書き込みをサブシェルで試す（fork のみ・exec なし） ---
    ( : > "$PROBE" ) &
    child=$!

    waited=0
    while (( waited < IO_TIMEOUT )) ; do
        kill -0 "$child" 2>/dev/null || break
        read -t 1 -u 9 _ 2>/dev/null
        (( waited++ ))
    done

    if kill -0 "$child" 2>/dev/null ; then
        # 時間内に書き終わらなかった＝I/O が詰まっている
        kill -9 "$child" 2>/dev/null
        (( fails++ ))
        log "root I/O did not complete in ${IO_TIMEOUT}s (fail ${fails}/${THRESHOLD})"

        if (( fails >= THRESHOLD )) ; then
            log "root I/O hung for $(( fails * INTERVAL ))s -- forcing reboot via sysrq"
            echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
            echo b > /proc/sysrq-trigger 2>/dev/null
            # ここへは到達しないはず
        fi
    else
        wait "$child" 2>/dev/null
        if (( fails > 0 )) ; then
            log "root I/O recovered after ${fails} failure(s)"
            fails=0
        fi
    fi

    read -t "$INTERVAL" -u 9 _ 2>/dev/null
done
