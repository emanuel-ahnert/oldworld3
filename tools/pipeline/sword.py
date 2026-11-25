"""Builds a one-handed sword from shapes in Blender (TRELLIS makes thin blades thick and
cone-like, see design/gen3D-server.md). Origin at the middle of the grip, blade along +Z
(glTF +Y), like weapon.py's output, so it attaches to the hand the same way.

blender -b --python tools/pipeline/sword.py -- <out.glb> [blade_length_m]
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
blade_len = float(a[1]) if len(a) > 1 else 0.68
common.reset()


def material(name, color, metallic, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = roughness
    return m


steel = material("steel", (0.78, 0.79, 0.8), 1.0, 0.28)
dark = material("dark_steel", (0.42, 0.4, 0.37), 1.0, 0.42)
leather = material("leather", (0.25, 0.13, 0.06), 0.0, 0.8)

GRIP = 0.12          # grip length; the origin is its middle
guard_z = GRIP / 2


def blade():
    """Diamond cross-section, slightly tapering, with a pointed tip (last 12%)."""
    me = bpy.data.meshes.new("blade")
    bm = bmesh.new()
    rings = []
    n = 14
    for i in range(n + 1):
        s = i / n
        z = guard_z + 0.01 + s * blade_len
        taper = 1.0 - 0.25 * s
        if s > 0.88:
            taper *= (1.0 - s) / 0.12
        w = 0.026 * taper + 0.0005      # half width
        t = 0.0045 * taper + 0.0005     # half thickness at the ridge
        ring = [bm.verts.new((w, 0, z)), bm.verts.new((0, t, z)), bm.verts.new((-w, 0, z)), bm.verts.new((0, -t, z))]
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(4):
            bm.faces.new((r0[k], r0[(k + 1) % 4], r1[(k + 1) % 4], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("blade", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(steel)
    return o


def box(name, size, loc, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.modifier_add(type="BEVEL")
    o.modifiers[-1].width = 0.004
    o.modifiers[-1].segments = 2
    bpy.ops.object.modifier_apply(modifier=o.modifiers[-1].name)
    o.data.materials.append(mat)
    return o


parts = [blade()]
# Crossguard, its ends bent slightly toward the blade.
g = box("guard", (0.17, 0.022, 0.018), (0, 0, guard_z), dark)
for v in g.data.vertices:
    v.co.z += 0.25 * (abs(v.co.x) / 0.085) ** 2 * 0.03
parts.append(g)
bpy.ops.mesh.primitive_cylinder_add(radius=0.0145, depth=GRIP, vertices=16, location=(0, 0, 0))
grip = bpy.context.object
grip.data.materials.append(leather)
parts.append(grip)
for z in (-GRIP / 2 + 0.01, GRIP / 2 - 0.01):   # metal rings at the grip's ends
    bpy.ops.mesh.primitive_cylinder_add(radius=0.017, depth=0.008, vertices=16, location=(0, 0, z))
    bpy.context.object.data.materials.append(dark)
    parts.append(bpy.context.object)
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.023, segments=16, ring_count=10, location=(0, 0, -GRIP / 2 - 0.018))
pommel = bpy.context.object
pommel.scale = (1, 0.7, 1)
pommel.data.materials.append(dark)
parts.append(pommel)

for p in parts:
    common.select_only([p])
    if p.name.startswith("blade"):
        bpy.ops.object.shade_flat()
    else:
        bpy.ops.object.shade_smooth()
sword = common.join(parts)
sword.name = "Sword"
# The edges point up and down when the hand holds it forward (they used to face sideways).
sword.rotation_euler = (0, 0, math.pi / 2)
common.apply_transforms(sword)
common.export_glb([sword], out)
print("REPORT", out, "length", round(GRIP / 2 + 0.01 + blade_len + GRIP / 2 + 0.04, 3))
