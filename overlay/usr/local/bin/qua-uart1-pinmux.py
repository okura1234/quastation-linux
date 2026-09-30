#!/usr/bin/env python3
"""QuaStation (Realtek RTD1295): uart1 の 4 ピンを GPIO から uart1 機能へ mux する。

mainline 6.18 には RTD1295 の pinctrl ドライバが無く、dts にも
「TODO: Port GPIO and pinctrl」としてピン設定が存在しない。そのため uart1
(= RTL8761ATV Bluetooth の H5 リンク) のピンが GPIO のまま残り、UART は
ttyS1 として登録されクロックも供給されているのに信号がピンに出ない。

レジスタとビット位置の出典:
  Realtek ベンダー pinctrl ドライバ
  drivers/pinctrl/realtek/pinctrl-rtd129x.{c,h}
  Copyright (c) 2017 Realtek Semiconductor Corp. (GPL-2.0-or-later)
  取得元: https://github.com/kisgezenguz/linux-4.9

    pinctrl-rtd129x.c:761  pctl->iso_membase = of_iomap(node, 3);
      4.9 DTB の reg = <0x9801a000 .. 0x9804d000 .. 0x98012000 .. 0x98007000 ..>
      → index 3 = 0x98007000 (ISO)
    pinctrl-rtd129x.h:438-441  ur1_{rx,tx,cts_n,rts_n}: pmux_regoff=0x310,
      pmux_regbit=14/16/18/20, pmux_regbitmsk=0x3
    pinctrl-rtd129x.h:975-988  RTK_FUNCTION(0x0,"gpio") / RTK_FUNCTION(0x1,"uart1")

⚠️ この設定は揮発する（電源断で失われる）ため、起動ごとに適用する。
   恒久的な解は pinctrl-rtd.c 向けの RTD1295 ピン表を書くこと。
"""
import mmap, os, struct, sys

PAGE, OFF   = 0x98007000, 0x310
MASK, UART1 = 0x003fc000, 0x00154000      # bit14..21 / 4フィールドすべて 0b01
FIELDS      = ((14, "ur1_rx"), (16, "ur1_tx"), (18, "ur1_cts_n"), (20, "ur1_rts_n"))

# 機種ガード: 別の板で走らせない
try:
    compat = open("/proc/device-tree/compatible", "rb").read().split(b"\0")
except OSError:
    compat = []
if b"realtek,rtd1295" not in compat:
    print("[uart1-pinmux] RTD1295 ではないのでスキップ")
    sys.exit(0)

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
try:
    m = mmap.mmap(fd, mmap.PAGESIZE, mmap.MAP_SHARED,
                  mmap.PROT_READ | mmap.PROT_WRITE, offset=PAGE)
finally:
    os.close(fd)

cur = struct.unpack_from("<I", m, OFF)[0]
new = (cur & ~MASK) | UART1
if cur == new:
    print(f"[uart1-pinmux] 既に uart1 (0x{cur:08x})。何もしない")
    m.close(); sys.exit(0)

# msync はデバイスメモリのマッピングでは EINVAL を返す。O_SYNC + MAP_SHARED の
# Device マップなのでストアはそのまま到達する＝flush 不要。
struct.pack_into("<I", m, OFF, new)
back = struct.unpack_from("<I", m, OFF)[0]
m.close()

print(f"[uart1-pinmux] 0x{PAGE+OFF:08x}: 0x{cur:08x} -> 0x{back:08x}  " +
      " ".join(f"{n}={(back >> b) & 3}" for b, n in FIELDS))
sys.exit(0 if back == new else 1)
