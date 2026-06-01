#!/usr/bin/env python3
"""Generate a simple 1024x1024 PNG app icon without external deps."""
import sys
import struct
import zlib
import math

def write_png(path, pixels, w, h):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)  # 8-bit RGBA
    raw = b"".join(b"\x00" + bytes(row) for row in pixels)
    idat = zlib.compress(raw, 9)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "icon_1024.png"
    size = 1024
    cx, cy = size/2, size/2
    radius = size*0.46
    pixels = []
    for y in range(size):
        row = []
        for x in range(size):
            dx, dy = x-cx, y-cy
            d = math.sqrt(dx*dx + dy*dy)
            # Background: rounded square with gradient
            corner = 220
            inside_bg = (
                corner < x < size-corner or
                corner < y < size-corner or
                math.sqrt((max(corner-x,0)+max(x-(size-corner),0))**2 +
                          (max(corner-y,0)+max(y-(size-corner),0))**2) < corner
            )
            if inside_bg:
                t = y/size
                r = int(60 + 30*t)
                g = int(120 + 60*t)
                b = int(220 - 40*t)
                a = 255
            else:
                r,g,b,a = 0,0,0,0
            # Gauge needle (triangle)
            if d < radius:
                # ring
                if abs(d - radius*0.85) < 12:
                    r,g,b = 255,255,255
                # arc segments
                ang = math.atan2(dy, dx)
                if -math.pi*0.85 < ang < -math.pi*0.15 and abs(d - radius*0.62) < 28:
                    r,g,b = 250,210,80
                # needle
                if d < radius*0.6:
                    nx = math.cos(-math.pi*0.65)
                    ny = math.sin(-math.pi*0.65)
                    proj = dx*nx + dy*ny
                    perp = abs(-dx*ny + dy*nx)
                    if 0 <= proj <= radius*0.6 and perp < (radius*0.6 - proj)*0.08 + 4:
                        r,g,b = 255,255,255
                # center dot
                if d < 26:
                    r,g,b = 255,255,255
            row.extend([r,g,b,a])
        pixels.append(row)
    write_png(out, pixels, size, size)

if __name__ == "__main__":
    main()
