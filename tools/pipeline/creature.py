"""Prepares a generated four-legged creature (static mesh) for the game: body axis along the
forward direction (Blender -Y = glTF +Z, the game's model front), real length, feet on the
ground, centered. The game animates it procedurally (bob, lunge, fall).

blender -b --python tools/pipeline/creature.py -- <in.glb> <out.glb> <length_m> [flip] [preview.png]

The head end is guessed as the end whose top is higher (heads are carried higher than tails);
`flip` reverses it. The preview (side view) shows the result for a check.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import common  # noqa: E402

a = common.args()
src, dst, length = a[0], a[1], float(a[2])
flip = len(a) > 3 and a[3] == "flip"
preview = a[4] if len(a) > 4 else (a[3] if len(a) > 3 and a[3] != "flip" else None)
common.reset()
obj = common.import_glb(src, "Creature")
common.largest_part(obj)

co = np.array([v.co[:] for v in obj.data.vertices])
xy = co[:, :2] - co[:, :2].mean(axis=0)
_, _, vt = np.linalg.svd(xy, full_matrices=False)
axis = vt[0]                                    # long horizontal axis
t = xy @ axis
lo_end = co[t < np.quantile(t, 0.2)]
hi_end = co[t > np.quantile(t, 0.8)]
head_is_hi = np.quantile(hi_end[:, 2], 0.95) > np.quantile(lo_end[:, 2], 0.95)
if flip:
    head_is_hi = not head_is_hi
fwd = axis if head_is_hi else -axis
# Rotate so the head points to -Y (Blender front, exports as glTF +Z).
ang = math.atan2(fwd[0], -fwd[1])
obj.data.transform(Matrix.Rotation(ang, 4, "Z"))
lo, hi = common.bounds(obj)
s = length / (hi.y - lo.y)
obj.data.transform(Matrix.Translation(-Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))))
obj.data.transform(Matrix.Scale(s, 4))
obj.data.update()
common.export_glb([obj], dst)
if preview:
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = 600, 400
    cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
    sc.collection.objects.link(cam)
    cam.data.type, cam.data.ortho_scale = "ORTHO", length * 1.4
    cam.location = Vector((6, 0, length * 0.35))
    cam.rotation_euler = (math.radians(90), 0, math.radians(90))
    sc.camera = cam
    sc.render.filepath = preview
    bpy.ops.render.render(write_still=True)
lo, hi = common.bounds(obj)
print("REPORT", dst, "size", [round(v, 2) for v in (hi - lo)], "head_was_hi_end", bool(head_is_hi))
