"""Makes a generated texture tileable and resizes it.

blender -b --python tools/pipeline/seamless.py -- <in.png> <out.png> [size]

The image is blended with a copy shifted by half its size. The weight of the original is 1
in the middle and falls to 0 at the borders, where the shifted copy (whose own middle is there)
takes over, so opposite edges match. Organic textures (grass, dirt, rock) hide the blend.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402
import numpy as np  # noqa: E402

import common  # noqa: E402

a = common.args()
src, dst = a[0], a[1]
size = int(a[2]) if len(a) > 2 else 1024
img = bpy.data.images.load(src)
w, h = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
shifted = np.roll(np.roll(px, h // 2, axis=0), w // 2, axis=1)
u = np.sin(np.linspace(0, np.pi, w)) ** 0.7
v = np.sin(np.linspace(0, np.pi, h)) ** 0.7
weight = np.minimum.outer(v, u)[:, :, None]
out = px * weight + shifted * (1 - weight)
out[:, :, 3] = 1
res = bpy.data.images.new("out", w, h)
res.pixels[:] = out.ravel()
if size != w:
    res.scale(size, size)
res.filepath_raw = dst
res.file_format = "PNG"
res.save()
print("REPORT", dst, size)
