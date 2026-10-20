"""Write NAGDeathRadar/Media/HotRing.tga: a white ring on transparent, 128 x 128, 32-bit uncompressed TGA (the
format every WoW client reads). The radar tints it red and lays it over the ring art while the player stands in
a hot cell. The band runs from INNER to OUTER of the width from the centre (radar.lua HOT_INNER, HOT_OUTER);
edges antialiased by 8 x 8 supersampling. Deterministic: the same bytes every run.

    python3 -I tools/make_hotring.py
"""
import struct
from pathlib import Path

SIZE = 128
INNER, OUTER = 0.425, 0.5   # shares of the width: the band is 54.4 .. 64 px from the centre
SUB = 8
OUT = Path(__file__).resolve().parent.parent / "NAGDeathRadar" / "Media" / "HotRing.tga"


def coverage(x, y):
    c, rin, rout, n = SIZE / 2, INNER * SIZE, OUTER * SIZE, 0
    for i in range(SUB):
        for j in range(SUB):
            dx, dy = x + (i + 0.5) / SUB - c, y + (j + 0.5) / SUB - c
            r2 = dx * dx + dy * dy
            if rin * rin <= r2 <= rout * rout:
                n += 1
    return n / (SUB * SUB)


def main():
    # Header: no id, no colour map, type 2 (uncompressed true colour), 32 bits, 8 alpha bits, origin bottom-left.
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    body = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            body += bytes((255, 255, 255, round(coverage(x, y) * 255)))  # B, G, R, A
    OUT.write_bytes(head + bytes(body))
    print("wrote %s (%d bytes)" % (OUT, OUT.stat().st_size))


if __name__ == "__main__":
    main()
