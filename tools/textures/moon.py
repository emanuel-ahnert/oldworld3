"""The moon's disc as seen from the ground (game/assets/sky/moon.png, RGBA, transparent around).

python3 tools/textures/moon.py [out.png] [size]

Generated, not painted: the near side's maria (the dark "seas") at their real places on a
sphere (Oceanus Procellarum, Imbrium, Serenitatis, Tranquillitatis, Crisium, Nubium, ...), so
the familiar face shows; bright highlands with a fine mottle, craters of all sizes (dark floor,
lit rim), and the bright ray craters (Tycho with its long rays in the south, Copernicus, Kepler,
Aristarchus). A little limb darkening, a soft edge. Drawn in the sky by day_night.gd
(shaders/moon.gdshader adds the halo).
"""
import struct
import sys
import zlib
from pathlib import Path

import numpy as np

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "game/assets/sky/moon.png"
N = int(sys.argv[2]) if len(sys.argv) > 2 else 512
rng = np.random.default_rng(7)

# --- the visible hemisphere ----------------------------------------------------------------------
c = (np.arange(N) + 0.5) / N * 2 - 1
u, v = np.meshgrid(c, -c)                 # v up
r2 = u * u + v * v
inside = r2 < 1.0
nz = np.sqrt(np.clip(1 - r2, 0, 1))
P = np.stack([u, v, nz], -1)              # unit sphere points (x east/right, y north, z to us)
lon = np.degrees(np.arctan2(u, nz))
lat = np.degrees(np.arcsin(np.clip(v, -1, 1)))


def unit(lo, la):
    lo, la = np.radians(lo), np.radians(la)
    return np.array([np.cos(la) * np.sin(lo), np.sin(la), np.cos(la) * np.cos(lo)])


def angle_to(lo, la):
    """Great-circle angle (degrees) from every point to (lo, la)."""
    return np.degrees(np.arccos(np.clip(P @ unit(lo, la), -1, 1)))


# --- noise on the sphere (value noise on a 3D lattice, smooth) -----------------------------------
def value_noise(p, freq, seed):
    q = p * freq
    i0 = np.floor(q).astype(np.int64)
    f = q - i0
    f = f * f * (3 - 2 * f)
    out = np.zeros(p.shape[:-1])
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                h = (i0[..., 0] + dx) * 73856093 ^ (i0[..., 1] + dy) * 19349663 ^ (i0[..., 2] + dz) * 83492791 ^ seed * 2654435761
                h = (h ^ (h >> 13)) * 1274126177
                val = ((h ^ (h >> 16)) & 0xFFFF) / 65535.0
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                out += val * w
    return out


def fbm(p, freq, octaves, seed, gain=0.5):
    s, a, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        s = s + a * value_noise(p, freq * 2 ** o, seed + o)
        tot += a
        a *= gain
    return s / tot


# --- highlands and maria ---------------------------------------------------------------------------
alb = 0.74 + 0.10 * (fbm(P, 3, 5, 1) - 0.5) + 0.04 * (fbm(P, 30, 3, 2) - 0.5) + 0.04 * np.clip(-v, 0, 1)
# (lon, lat, radius along lon, radius along lat, darkness): the near side's seas.
MARIA = [
    (-57, 15, 24, 30, 1.0), (-48, 35, 14, 12, 0.9), (-62, -5, 12, 16, 0.9),     # Procellarum
    (-17, 34, 19, 15, 1.0),                                                       # Imbrium
    (17, 28, 11, 10, 1.0),                                                         # Serenitatis
    (31, 8, 15, 11, 1.0), (24, 14, 6, 5, 0.9),                                     # Tranquillitatis
    (59, 17, 7, 5, 1.05),                                                         # Crisium
    (51, -6, 8, 11, 0.85),                                                        # Fecunditatis
    (34, -15, 6, 6, 0.85),                                                        # Nectaris
    (-17, -20, 11, 9, 0.85), (-23, -10, 6, 6, 0.8),                               # Nubium, Cognitum
    (-39, -24, 6, 6, 0.9),                                                        # Humorum
    (-30, 7, 9, 7, 0.8),                                                          # Insularum
    (4, 13, 6, 4, 0.8), (1, 2, 4, 3, 0.6),                                        # Vaporum, Medii
    (-5, 56, 32, 4.5, 0.85), (25, 57, 14, 4, 0.75),                               # Frigoris
    (8, 6, 4, 4, 0.5), (-8, 46, 6, 4, 0.7),                                       # small bays
    (4, 31, 7, 5, 0.75), (23, 19, 6, 6, 0.9), (-4, 20, 8, 5, 0.6),                # the straits
    (40, 12, 6, 5, 0.7), (42, -3, 6, 6, 0.7),                                     # between the
]
# A soft union of the seas (summed fields, no ellipse edges showing), the shore frayed by noise
# at two scales; inside, darker and lighter patches (lava flows of different age).
edge_noise = (fbm(P, 7, 5, 5) - 0.5) * 0.9 + (fbm(P, 22, 3, 6) - 0.5) * 0.35
field = np.zeros_like(alb)
for lo, la, rl, rb, dark in MARIA:
    d2 = ((lon - lo) / rl) ** 2 + ((lat - la) / rb) ** 2
    field += dark * np.exp(-d2 * 1.25)
mare = np.clip((field + edge_noise * 0.5 - 0.36) / 0.3, 0, 1)
mare = mare * mare * (3 - 2 * mare)
alb = alb * (1 - 0.46 * mare * (0.75 + 0.5 * fbm(P, 10, 4, 8)))

# --- craters -----------------------------------------------------------------------------------------
def crater(lo, la, rad, depth=0.10, rim=0.12):
    a = angle_to(lo, la) / rad
    floor = np.where(a < 0.85, -depth * (1 - (a / 0.85) ** 2) * 0.6 - depth * 0.4, 0.0)
    ring = rim * np.exp(-((a - 0.95) / 0.12) ** 2)
    ejecta = 0.4 * rim * np.exp(-np.clip(a - 1.0, 0, None) * 2.5) * (a > 1.0)
    return floor + ring + ejecta


cr = np.zeros_like(alb)
# At full moon the sun is behind the viewer: craters barely show, only as faint mottling.
for _ in range(700):
    lo, la = rng.uniform(-88, 88), np.degrees(np.arcsin(rng.uniform(-0.99, 0.99)))
    rad = min(0.3 * rng.pareto(1.8) + 0.3, 3.5)
    cr += crater(lo, la, rad, depth=0.025 + 0.02 * rng.random(), rim=0.015 + 0.02 * rng.random())
alb += cr * (1 - 0.5 * mare)

# Ray craters: bright, young, with streaks along great circles.
def ray_crater(lo, la, rad, rays, length, bright):
    global alb
    a = angle_to(lo, la)
    # Direction of every point as seen from the crater (bearing), for the streaks.
    c0 = unit(lo, la)
    east = np.cross([0, 1, 0], c0)
    east /= np.linalg.norm(east)
    north = np.cross(c0, east)
    bearing = np.arctan2(P @ north, P @ east)
    streak = np.zeros_like(alb)
    for _ in range(rays):
        b = rng.uniform(-np.pi, np.pi)
        ln = length * rng.uniform(0.35, 1.0)
        # Wide near the crater, a narrow faint band far out (an angle, so narrower with distance).
        w = rng.uniform(0.05, 0.12) * (rad * 3.0 / np.maximum(a, rad * 3.0)) ** 0.5
        db = np.angle(np.exp(1j * (bearing - b)))
        streak = streak + 0.6 * np.exp(-(db / w) ** 2) * np.clip(1 - a / ln, 0, 1) ** 1.2
    streak = np.clip(streak, 0, 1) * (0.6 + 0.4 * fbm(P, 30, 2, 11))
    halo = np.exp(-(a / (rad * 2.5)) ** 2)
    alb = alb + bright * (0.5 * halo + 0.28 * streak * np.clip(a / rad - 1.5, 0, 1)) + crater(lo, la, rad, 0.02, 0.05)


ray_crater(-11, -43, 1.6, 22, 55, 0.2)      # Tycho
ray_crater(-20, 10, 1.7, 16, 22, 0.15)       # Copernicus
ray_crater(-38, 8, 0.9, 12, 14, 0.18)        # Kepler
ray_crater(-47, 24, 0.7, 6, 8, 0.35)         # Aristarchus
ray_crater(51, -7, 0.6, 8, 14, 0.15)         # Langrenus area
ray_crater(25, -50, 0.9, 8, 12, 0.12)

# --- shading, colour, edge -----------------------------------------------------------------------------
alb = np.clip(alb, 0.03, 1.0)
lum = alb * (0.80 + 0.20 * nz ** 0.6)        # the full moon is nearly flat; a little limb darkening
tint = np.array([1.0, 0.985, 0.95])
rgb = np.clip(lum[..., None] * tint, 0, 1)
px = 2.0 / N
alpha = np.clip((1 - np.sqrt(r2)) / (1.5 * px), 0, 1)
img = np.concatenate([rgb, alpha[..., None]], -1)
img[~inside, :3] = rgb[inside].mean(0)        # no dark fringe when filtered
img8 = (img * 255 + 0.5).astype(np.uint8)


def write_png(path, a):
    h, w, ch = a.shape
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


write_png(OUT, img8)
print("wrote", OUT, f"{N}x{N}, mare cover {mare[inside].mean():.2f}")
