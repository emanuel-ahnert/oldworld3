"""The head map of the base body: for every texel of the head (vertex color slot 0, plus the neck
under it), where it is on the head, so shaders/body_slots.gdshader can tell hair, face, jaw and
chin apart whatever the pose (hair colour, beards).

blender -b --python tools/pipeline/head_map.py -- <body_dir> <out.png>

RGB = (up, ahead, side) from the head's middle (headgear.py's HC: on the face's center line,
10 cm over the head bone), each m / RANGE + 0.5; ahead is toward the face, side to the body's
left. A = 1 on the head (and a few texels round it), 0 elsewhere. Rasterized in UV space (it holds for any mesh with the
body's UVs, decimated or not), then grown a few texels past the islands' edges (no seams).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402
import numpy as np  # noqa: E402

import common  # noqa: E402

a = common.args()
body_dir, out = Path(a[0]), Path(a[1])
SIZE = 1024
RANGE = 0.4

bpy.ops.wm.open_mainfile(filepath=str(body_dir / "body.blend"))
body = bpy.data.objects["Body"]
rig = bpy.data.objects["Skeleton"]
rig.data.pose_position = "REST"
m = body.data
bco = np.array([body.matrix_world @ v.co for v in m.vertices])
NECK = float((rig.matrix_world @ rig.data.bones["Head"].head_local).z)
head_g = body.vertex_groups["Head"].index
head_v = np.array([any(g.group == head_g and g.weight > 0.5 for g in v.groups) for v in m.vertices])
head_y = float(np.median(bco[head_v, 1]))
H_ = bco[head_v]
mid_ = H_[(H_[:, 2] > NECK + 0.06) & (H_[:, 2] < NECK + 0.12)]
low_ = H_[(H_[:, 2] > NECK - 0.05) & (H_[:, 2] < NECK + 0.02)]
CX = float((mid_[np.argmin(mid_[:, 1]), 0] + low_[np.argmin(low_[:, 1]), 0]) / 2)
HC = np.array([CX, head_y, NECK + 0.10])
print(f"HEADMAP center {HC}")

slot = np.array([d.color[0] for d in m.color_attributes["slot"].data])
on = (np.abs(slot - 0.0625) < 0.02)
rel = bco - HC
code = np.stack([rel[:, 2], -rel[:, 1], rel[:, 0]], axis=1) / RANGE + 0.5

uvl = m.uv_layers["UVMap"].data
img = np.zeros((SIZE, SIZE, 4), np.float32)
m.calc_loop_triangles()
n = 0
for tri in m.loop_triangles:
    vs = tri.vertices
    if not all(on[v] for v in vs):
        continue
    n += 1
    uv = np.array([uvl[l].uv for l in tri.loops]) * SIZE
    c = code[list(vs)]
    x0, y0 = np.floor(uv.min(axis=0)).astype(int)
    x1, y1 = np.ceil(uv.max(axis=0)).astype(int)
    xs, ys = np.meshgrid(np.arange(max(x0, 0), min(x1 + 1, SIZE)), np.arange(max(y0, 0), min(y1 + 1, SIZE)))
    p = np.stack([xs.ravel() + 0.5, ys.ravel() + 0.5], axis=1)
    (ax, ay), (bx, by), (cx, cy) = uv
    det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(det) < 1e-12:
        continue
    l1 = ((by - cy) * (p[:, 0] - cx) + (cx - bx) * (p[:, 1] - cy)) / det
    l2 = ((cy - ay) * (p[:, 0] - cx) + (ax - cx) * (p[:, 1] - cy)) / det
    l3 = 1 - l1 - l2
    ins = (l1 >= -0.02) & (l2 >= -0.02) & (l3 >= -0.02)
    if not ins.any():
        continue
    w = np.stack([l1, l2, l3], axis=1)[ins]
    val = w @ c
    px, py = p[ins, 0].astype(int), p[ins, 1].astype(int)
    img[py, px, :3] = val
    img[py, px, 3] = 1.0
print(f"HEADMAP {n} triangles, {int(img[..., 3].sum())} texels")
# Grow past the edges: empty texels take their filled neighbours' mean, and count as head (the
# vertices on an island's edge read between the texels there: with A 0 outside, they read "not
# head", stayed put under the beard's volume and tore it open).
filled = img[..., 3] > 0
rgb = img[..., :3].copy()
for _ in range(6):
    acc = np.zeros_like(rgb)
    cnt = np.zeros(filled.shape, np.float32)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        f = np.roll(np.roll(filled, dy, 0), dx, 1)
        acc += np.roll(np.roll(rgb, dy, 0), dx, 1) * f[..., None]
        cnt += f
    grow = (~filled) & (cnt > 0)
    rgb[grow] = acc[grow] / cnt[grow][:, None]
    filled = filled | grow
img[..., :3] = rgb
img[..., 3] = filled.astype(np.float32)
im = bpy.data.images.new("headmap", SIZE, SIZE, alpha=True, float_buffer=False)
im.colorspace_settings.name = "Non-Color"
im.pixels.foreach_set(np.clip(img, 0, 1).ravel())
im.filepath_raw = str(out)
im.file_format = "PNG"
im.save()
print(f"HEADMAP saved {out}")
