"""Builds a low, wide shrub whose foliage reaches the ground out of a generated bush that came
out as a small tree (canopy on a stem): the canopy is cut off the stem (like prop.py) and
several copies, turned, tilted outward and of different sizes, are merged into one mound.
SDXL draws a tree for every "bush" prompt, so this is the reliable way to a real shrub.

blender -b --python tools/pipeline/shrub.py -- <bush.glb> <out.glb> [cut_below_frac] [seed]
"""

import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bmesh  # noqa: E402
import bpy  # noqa: E402

import common  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

a = common.args()
src, out = a[0], a[1]
cut = float(a[2]) if len(a) > 2 else 0.45
rnd = random.Random(int(a[3]) if len(a) > 3 else 1)
common.reset()
canopy = common.import_glb(src, "Canopy")
lo, hi = common.bounds(canopy)
z = lo.z + (hi.z - lo.z) * cut
bm = bmesh.new()
bm.from_mesh(canopy.data)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < z], context="VERTS")
bm.to_mesh(canopy.data)
bm.free()
common.largest_part(canopy, keep_frac=0.01)
common.normalize(canopy, 1.0)     # 1 m tall clump, bottom at 0

# One big clump in the middle, a ring of smaller ones leaning outward: together a mound.
parts = []
clumps = [(0.0, 0.0, 1.0, 0.0)] + [(a_ + rnd.uniform(-0.3, 0.3), rnd.uniform(0.45, 0.6), rnd.uniform(0.65, 0.85), rnd.uniform(18, 30))
                                   for a_ in [k * math.tau / 5 for k in range(5)]]
for ang, dist, size, tilt in clumps:
    c = canopy.copy()
    c.data = canopy.data.copy()
    bpy.context.collection.objects.link(c)
    c.scale = (size, size, size * rnd.uniform(0.85, 1.0))
    c.rotation_mode = "ZXY"
    # Lean away from the center: tilt about the axis perpendicular to the outward direction.
    c.rotation_euler = (0, 0, rnd.uniform(0, math.tau))
    c.location = (math.cos(ang) * dist, math.sin(ang) * dist, -0.12 * size)
    if tilt:
        # Rotate about the horizontal axis (-sin, cos, 0) so the clump leans outward.
        axis = Vector((-math.sin(ang), math.cos(ang), 0))
        c.matrix_world = Matrix.Translation(c.location) @ Matrix.Rotation(math.radians(tilt), 4, axis) @ \
            Matrix.Translation(-c.location) @ c.matrix_world
    parts.append(c)
bpy.data.objects.remove(canopy)
for p in parts:
    common.apply_transforms(p)
shrub = common.join(parts)
# Nothing below the ground.
bm = bmesh.new()
bm.from_mesh(shrub.data)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < 0.0], context="VERTS")
bm.to_mesh(shrub.data)
bm.free()
common.normalize(shrub, 1.0)
common.export_glb([shrub], out)
lo, hi = common.bounds(shrub)
print("REPORT", out, "size", [round(hi.x - lo.x, 2), round(hi.y - lo.y, 2), round(hi.z - lo.z, 2)],
      "tris", sum(len(p.vertices) - 2 for p in shrub.data.polygons))
