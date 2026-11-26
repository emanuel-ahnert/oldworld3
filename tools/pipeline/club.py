"""Builds a crude one-handed wooden club from shapes in Blender (goblins, trolls, berserkers,
corsairs, hoplites' enemies with "weapon": "club"): a knobbly log thickening toward the head,
slightly crooked, a few knots, a leather-wrapped grip and a handful of iron studs driven into
the head. Origin at the grip, along +Z (glTF +Y), like sword.py and mace.py, so it attaches to
the hand the same way. (The old club.glb was a short steel blade.)

blender -b --python tools/pipeline/club.py -- <out.glb>
"""

import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import common  # noqa: E402

out = common.args()[0]
common.reset()
rng = random.Random(23)


def material(name, color, metallic, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = roughness
    return m


wood = material("wood", (0.11, 0.06, 0.03), 0.0, 0.9)          # linear: a dark brown
dark_wood = material("wood_knot", (0.05, 0.03, 0.015), 0.0, 0.95)
leather = material("leather", (0.07, 0.035, 0.015), 0.0, 0.85)
iron = material("iron", (0.32, 0.31, 0.3), 0.8, 0.55)
parts = []

# The log: rings from the butt (z = -0.1) to the head (z = 0.52), thickening toward the head,
# its axis bending a little, the radius bumpy (bark and knots).
RINGS, SIDES = 22, 12
z0, z1 = -0.10, 0.52
bm = bmesh.new()
rings = []
for i in range(RINGS):
    t = i / (RINGS - 1)
    z = z0 + (z1 - z0) * t
    r = 0.021 + 0.034 * t ** 1.6                       # grip 2 cm, head ~5.5 cm
    if t > 0.93:
        r *= 1 - (t - 0.93) / 0.07 * 0.45              # the rounded top
    bend = Vector((0.012 * math.sin(t * 2.6), 0.008 * math.sin(t * 3.7 + 1), 0))
    ring = []
    for k in range(SIDES):
        a = 2 * math.pi * k / SIDES
        bump = 1 + 0.08 * math.sin(3 * a + i * 0.9) * t + rng.uniform(-0.04, 0.04)
        ring.append(bm.verts.new(bend + Vector((math.cos(a) * r * bump, math.sin(a) * r * bump, z))))
    rings.append(ring)
for i in range(RINGS - 1):
    for k in range(SIDES):
        a0, a1 = rings[i][k], rings[i][(k + 1) % SIDES]
        b0, b1 = rings[i + 1][k], rings[i + 1][(k + 1) % SIDES]
        bm.faces.new((a0, a1, b1, b0))
bm.faces.new(list(reversed(rings[0])))
top = bm.verts.new(Vector((0.012 * math.sin(2.6), 0.008 * math.sin(4.7), z1 + 0.012)))
for k in range(SIDES):
    bm.faces.new((rings[-1][k], rings[-1][(k + 1) % SIDES], top))
me = bpy.data.meshes.new("Log")
bm.to_mesh(me)
bm.free()
log = bpy.data.objects.new("Log", me)
bpy.context.collection.objects.link(log)
log.data.materials.append(wood)
parts.append(log)

# Knots: flattened dark lumps on the thick part.
for z, a in ((0.26, 0.4), (0.38, 2.6), (0.44, 4.4)):
    t = (z - z0) / (z1 - z0)
    r = 0.021 + 0.034 * t ** 1.6
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.014, segments=10, ring_count=6,
                                         location=(math.cos(a) * r * 0.92, math.sin(a) * r * 0.92, z))
    k = bpy.context.object
    k.scale = (1.0, 1.0, 1.5)
    k.data.materials.append(dark_wood)
    parts.append(k)

# Leather wrap around the grip.
bpy.ops.mesh.primitive_cylinder_add(radius=0.0235, depth=0.13, vertices=12, location=(0, 0, -0.01))
wrap = bpy.context.object
wrap.data.materials.append(leather)
parts.append(wrap)

# Iron studs driven into the head: short squat cones pointing out.
for j in range(7):
    a = j * 2 * math.pi / 7 + rng.uniform(-0.3, 0.3)
    z = rng.uniform(0.36, 0.48)
    t = (z - z0) / (z1 - z0)
    r = 0.021 + 0.034 * t ** 1.6
    d = Vector((math.cos(a), math.sin(a), 0))
    bpy.ops.mesh.primitive_cone_add(radius1=0.008, radius2=0.0, depth=0.02, vertices=6,
                                    location=d * (r + 0.006) + Vector((0, 0, z)))
    s = bpy.context.object
    s.rotation_euler = Vector((0, 0, 1)).rotation_difference(d).to_euler()
    s.data.materials.append(iron)
    parts.append(s)

for p in parts:
    common.select_only([p])
    bpy.ops.object.shade_smooth()
club = common.join(parts)
club.name = "Club"
common.apply_transforms(club)
common.export_glb([club], out)
print("REPORT", out, len(club.data.polygons), "faces")
