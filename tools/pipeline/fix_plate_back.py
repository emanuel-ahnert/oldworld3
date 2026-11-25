"""Paints over a bake miss on the plate outfit: an oval brown spot in the middle of the back
plate (the source knight model had something there, so the bake fell back to the base body's
shirt). Smooth fill from the surrounding steel. Run after baking the plate outfit.

blender -b --python tools/pipeline/fix_plate_back.py -- <plate_color.png>
"""
import sys

import bpy
import numpy as np

path = sys.argv[sys.argv.index("--") + 1]
img = bpy.data.images.load(path)
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
cx, cy_top = 397, 1840
cy = H - 1 - cy_top
ys, xs = np.mgrid[0:H, 0:W]
bad = ((xs - cx) / 50.0) ** 2 + ((ys - cy) / 30.0) ** 2 < 1.0     # the blotch, measured in a zoom
rgb = px[..., :3]
# Smooth (harmonic) fill: start from the boundary's mean, then relax each filled pixel to the
# average of its neighbours, in a window around the hole only.
y0, y1 = np.nonzero(bad.any(1))[0][[0, -1]]
x0, x1 = np.nonzero(bad.any(0))[0][[0, -1]]
y0, y1, x0, x1 = y0 - 4, y1 + 5, x0 - 4, x1 + 5
win = rgb[y0:y1, x0:x1].copy()
hole = bad[y0:y1, x0:x1]
ring = (np.roll(hole, 1, 0) | np.roll(hole, -1, 0) | np.roll(hole, 1, 1) | np.roll(hole, -1, 1)) & ~hole
win[hole] = win[ring].mean(axis=0)
for _ in range(3000):
    avg = (np.roll(win, 1, 0) + np.roll(win, -1, 0) + np.roll(win, 1, 1) + np.roll(win, -1, 1)) / 4
    win[hole] = avg[hole]
# A little of the steel's grain back (copied from the surroundings' high frequencies).
rng = np.random.default_rng(1)
win[hole] += rng.normal(0, 0.008, (int(hole.sum()), 1)).astype(np.float32)
out = rgb.copy()
out[y0:y1, x0:x1] = win
px[..., :3] = out
img.pixels[:] = px.ravel()
img.filepath_raw = path; img.file_format = "PNG"; img.save()
print("FIXED", int(bad.sum()))
