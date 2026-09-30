#!/usr/bin/env python3
"""make-uimage.sh — turn arch/arm64/boot/Image into the raw 'uImage' the Qua Station vendor U-Boot expects.
   usage: make-uimage.sh <Image> <uImage-out>
   * sets text_offset (u64 at byte 8) to 0x280000 (vendor U-Boot loads at 0x03000000 and memmoves to RAM base + text_offset)
   * no gzip, no mkimage wrapper; 512 KiB of zero padding appended
   * refuses if 0x280000 + image_size would reach 0x1b00000 (bluecore.audio / DTB live there)"""
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
d = bytearray(open(src, 'rb').read())
assert d[56:60] == b'ARM\x64', 'not an arm64 Image'
isz = struct.unpack_from('<Q', d, 16)[0]
assert 0x280000 + isz < 0x1b00000, 'Image too large for the vendor U-Boot memory map'
struct.pack_into('<Q', d, 8, 0x280000)
d += b'\0' * (512 * 1024)
open(dst, 'wb').write(d); print(f'{dst}: {len(d)} bytes, image_size=0x{isz:x}')
