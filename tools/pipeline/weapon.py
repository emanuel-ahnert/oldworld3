"""Prepares a generated one-handed weapon for holding: long axis along +Y (from the grip toward
the tip), origin at the middle of the grip, real length.

blender -b --python tools/pipeline/weapon.py -- <in.glb> <out.glb> [length_m]

The handle end is the one with a bump at its very end (the pommel): there the end slice is
wider than the slices just before it, while a blade narrows into its point.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import common  # noqa: E402

a = common.args()
src, dst = a[0], a[1]
length = float(a[2]) if len(a) > 2 else 0.85
common.reset()
obj = common.import_glb(src, "Weapon")
common.largest_part(obj)

co = np.array([v.co[:] for v in obj.data.vertices])
c = co.mean(axis=0)
_, _, vt = np.linalg.svd(co - c, full_matrices=False)
axis = vt[0]
t = (co - c) @ axis
# Width profile along the axis, 24 bins.
bins = np.linspace(t.min(), t.max(), 25)
perp = co - c - np.outer(t, axis)
width = np.array([np.linalg.norm(perp[(t >= bins[i]) & (t <= bins[i + 1])], axis=1).max(initial=0)
                  for i in range(24)])
# Pommel bump: end bin wider than the next-but-one bin. If the + end has it, flip the axis so
# +axis runs from the handle toward the tip.
lo_bump = width[0] - width[2]
hi_bump = width[-1] - width[-3]
if hi_bump > lo_bump:
    axis, t, width = -axis, -t, width[::-1]
    bins = -bins[::-1]
# Grip: the narrowest bin within the first 30% from the handle end (skipping the pommel bin).
grip_bin = 1 + int(np.argmin(width[1:8]))
grip_t = (bins[grip_bin] + bins[grip_bin + 1]) / 2 if hi_bump <= lo_bump else -(bins[grip_bin] + bins[grip_bin + 1]) / 2

# Rotation taking `axis` to +Z (Blender up, which becomes glTF/Godot +Y).
rot = Vector(axis).rotation_difference(Vector((0, 0, 1))).to_matrix().to_4x4()
grip = Vector(c) + Vector(axis) * float(np.sort(t)[0] + (grip_bin + 0.5) * (t.max() - t.min()) / 24)
obj.data.transform(Matrix.Translation(-grip))
obj.data.transform(rot)
lo, hi = common.bounds(obj)
s = length / (hi.z - lo.z)
obj.data.transform(Matrix.Scale(s, 4))
obj.data.update()
common.export_glb([obj], dst)
print("REPORT", {"length": length, "grip_bin": grip_bin, "pommel_bump": [round(float(lo_bump), 4), round(float(hi_bump), 4)],
                 "width_profile": [round(float(w), 3) for w in width]})
