#!/usr/bin/env python3
"""
Genera l'icona dell'installer di assistenza remota.

    python3 genera-icona.py [cartella_di_destinazione]

Produce elettrosmart.ico (7 risoluzioni) e due PNG di anteprima. Non richiede
alcuna libreria esterna: il disegno e' rasterizzato a mano e le codifiche PNG e
ICO sono scritte direttamente, cosi' lo script gira ovunque ci sia Python 3.

Alle dimensioni minime (16, 24, 32 px) viene disegnata una variante
semplificata con il solo fulmine: la cornice del monitor, a quelle dimensioni,
diventerebbe una macchia illeggibile.

Il sorgente vettoriale equivalente e' in elettrosmart.svg.
"""
import sys

import zlib, struct, math

# ---------------------------------------------------------------- geometria
def rrect(x, y, x0, y0, x1, y1, r):
    """punto dentro un rettangolo con angoli arrotondati"""
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r

def poly(x, y, pts):
    """punto dentro un poligono (ray casting)"""
    inside = False
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        if (y0 > y) != (y1 > y):
            xin = (x1 - x0) * (y - y0) / (y1 - y0) + x0
            if x < xin:
                inside = not inside
    return inside

# ---------------------------------------------------------------- tavolozza
BG_TOP    = (0x2F, 0x7D, 0xF6)   # blu elettrico
BG_BOT    = (0x1E, 0x40, 0xAF)   # blu profondo
WHITE     = (0xFF, 0xFF, 0xFF)
BOLT      = (0xFF, 0xC5, 0x3D)   # ambra

BOLT_PTS_N = [(0.74,0.00),(0.00,0.55),(0.36,0.55),(0.24,1.00),(1.00,0.43),(0.62,0.43)]

def bolt_pts(x0, y0, w, h):
    return [(x0 + px * w, y0 + py * h) for px, py in BOLT_PTS_N]

def sample(x, y, simple):
    """restituisce (r,g,b,a) per un punto nello spazio 0..256"""
    # sfondo
    if not rrect(x, y, 3, 3, 253, 253, 56):
        return None
    t = y / 256.0
    bg = tuple(int(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t) for i in range(3))

    if simple:
        # alle dimensioni minime resta solo il fulmine, molto piu' grande
        if poly(x, y, bolt_pts(50, 24, 156, 208)):
            return BOLT + (255,)
        return bg + (255,)

    # monitor: cornice bianca
    if rrect(x, y, 40, 46, 216, 178, 18) and not rrect(x, y, 54, 60, 202, 164, 6):
        return WHITE + (255,)
    # collo e base del supporto
    if rrect(x, y, 114, 178, 142, 197, 2) or rrect(x, y, 82, 197, 174, 212, 7):
        return WHITE + (255,)
    # fulmine dentro lo schermo
    if poly(x, y, bolt_pts(86, 66, 84, 92)):
        return BOLT + (255,)
    return bg + (255,)

def render(size, simple=False, ss=4):
    """rasterizza con supersampling per l'antialiasing"""
    px = []
    scale = 256.0 / size
    inv = 1.0 / (ss * ss)
    for j in range(size):
        row = []
        for i in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sj in range(ss):
                for si in range(ss):
                    x = (i + (si + 0.5) / ss) * scale
                    y = (j + (sj + 0.5) / ss) * scale
                    c = sample(x, y, simple)
                    if c is not None:
                        acc[0] += c[0]; acc[1] += c[1]; acc[2] += c[2]; acc[3] += 255
            a = acc[3] * inv
            if a < 0.5:
                row.append((0, 0, 0, 0))
            else:
                n = acc[3] / 255.0
                row.append((int(acc[0] / n), int(acc[1] / n), int(acc[2] / n), int(round(a))))
        px.append(row)
    return px


OUT = sys.argv[1] if len(sys.argv) > 1 else '.'

# ------------------------------------------------------------------ PNG
def png(px, path):
    h = len(px); w = len(px[0])
    raw = bytearray()
    for row in px:
        raw.append(0)                      # filtro "none"
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    out = b'\x89PNG\r\n\x1a\n'
    out += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
    out += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    out += chunk(b'IEND', b'')
    open(path, 'wb').write(out)
    return len(out)

# ------------------------------------------------------------------ ICO
def dib(px):
    """immagine in formato DIB 32bpp + maschera AND, come richiesto dal formato ICO"""
    h = len(px); w = len(px[0])
    hdr = struct.pack('<IiiHHIIiiII', 40, w, h * 2, 1, 32, 0, 0, 0, 0, 0, 0)
    xor = bytearray()
    for j in range(h - 1, -1, -1):         # le righe vanno dal basso verso l'alto
        for r, g, b, a in px[j]:
            xor += bytes((b, g, r, a))
    stride = ((w + 31) // 32) * 4          # 1bpp allineato a 4 byte
    andm = bytearray()
    for j in range(h - 1, -1, -1):
        bits = bytearray(stride)
        for i in range(w):
            if px[j][i][3] < 128:          # trasparente -> bit a 1
                bits[i // 8] |= 0x80 >> (i % 8)
        andm += bits
    return hdr + bytes(xor) + bytes(andm)

def ico(entries, path):
    out = struct.pack('<HHH', 0, 1, len(entries))
    offset = 6 + 16 * len(entries)
    blobs = []
    for size, data in entries:
        s = 0 if size == 256 else size
        out += struct.pack('<BBBBHHII', s, s, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
        blobs.append(data)
    open(path, 'wb').write(out + b''.join(blobs))
    return offset

# ------------------------------------------------------------------ build
SIZES = [(16, True), (24, True), (32, True), (48, False),
         (64, False), (128, False), (256, False)]

entries = []
for size, simple in SIZES:
    p = render(size, simple)
    entries.append((size, dib(p)))
    if size in (256, 64):
        n = png(p, f'{OUT}/elettrosmart-{size}.png')
        print(f'  PNG {size}x{size}: {n} byte')

total = ico(entries, f'{OUT}/elettrosmart.ico')
print(f'  ICO: {total} byte, {len(entries)} risoluzioni ->',
      ', '.join(str(s) for s, _ in SIZES))
