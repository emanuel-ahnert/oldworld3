"""Builds a hunting bow from shapes in Blender: two curved wooden limbs, a wrapped grip and a
string. Origin at the grip, the bow along +Z (glTF +Y = up in the left hand), the string toward
-Y (the archer's side).

blender -b --python tools/pipeline/bow.py -- <out.glb> [length_m]
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bmesh  # noqa: E402
import bpy  # noqa: E402

import common  # noqa: E402

a = common.args()
out = a[0]
length = float(a[1]) if len(a) > 1 else 1.4
common.reset()


def material(name, color, metallic, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = roughness
    return m


wood = material("wood", (0.42, 0.26, 0.12), 0.0, 0.6)
leather = material("leather", (0.2, 0.12, 0.06), 0.0, 0.8)
string = material("string", (0.85, 0.82, 0.72), 0.0, 0.7)

# The limbs: a tube along a curve that bows forward (+Y) at the tips.
half = length / 2
me = bpy.data.meshes.new("limbs")
bm = bmesh.new()
rings = []
n = 24
for i in range(n + 1):
    t = i / n * 2 - 1                        # -1 (bottom tip) .. 1 (top tip)
    z = t * half
    y = 0.16 * (abs(t) ** 2.2)               # recurve toward the front
    r = 0.016 * (1.0 - 0.55 * abs(t)) + 0.004
    ring = []
    for k in range(8):
        ang = k / 8 * math.tau
        ring.append(bm.verts.new((math.cos(ang) * r, y + math.sin(ang) * r * 0.6, z)))
    rings.append(ring)
for r0, r1 in zip(rings, rings[1:]):
    for k in range(8):
        bm.faces.new((r0[k], r0[(k + 1) % 8], r1[(k + 1) % 8], r1[k]))
bm.to_mesh(me)
bm.free()
limbs = bpy.data.objects.new("limbs", me)
bpy.context.scene.collection.objects.link(limbs)
limbs.data.materials.append(wood)
parts = [limbs]
bpy.ops.mesh.primitive_cylinder_add(radius=0.022, depth=0.14, vertices=12, location=(0, 0.0, 0))
grip = bpy.context.object
grip.data.materials.append(leather)
parts.append(grip)
# The string from tip to tip (straight, behind the limbs' tips).
bpy.ops.mesh.primitive_cylinder_add(radius=0.0025, depth=length * 0.98, vertices=6, location=(0, 0.16, 0))
s = bpy.context.object
s.data.materials.append(string)
parts.append(s)
for p in parts:
    common.select_only([p])
    bpy.ops.object.shade_smooth()
bow = common.join(parts)
bow.name = "Bow"
common.apply_transforms(bow)
common.export_glb([bow], out)
print("REPORT", out)
