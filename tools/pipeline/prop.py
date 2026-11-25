"""Prepares a generated static model that stays upright (floating spirits, bushes, props):
optionally cuts away everything below a fraction of its height (a pot, a base plate), then
scales it to `height` meters, bottom on the ground, centered.

blender -b --python tools/pipeline/prop.py -- <in.glb> <out.glb> <height_m> [cut_below_frac]
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bmesh  # noqa: E402
import bpy  # noqa: E402

import common  # noqa: E402

a = common.args()
src, out, height = a[0], a[1], float(a[2])
cut = float(a[3]) if len(a) > 3 else 0.0
common.reset()
obj = common.import_glb(src, "Prop")
if cut > 0.0:
    lo, hi = common.bounds(obj)
    z = lo.z + (hi.z - lo.z) * cut
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < z], context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    common.largest_part(obj, keep_frac=0.01)
common.normalize(obj, height)
common.export_glb([obj], out)
lo, hi = common.bounds(obj)
print("REPORT", out, "size", [round(hi.x - lo.x, 2), round(hi.y - lo.y, 2), round(hi.z - lo.z, 2)])
