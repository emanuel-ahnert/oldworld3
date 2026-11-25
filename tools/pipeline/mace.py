"""Builds a one-handed flanged mace from shapes in Blender. Origin at the grip, along +Z
(glTF +Y), like sword.py, so it attaches to the hand the same way.

blender -b --python tools/pipeline/mace.py -- <out.glb>
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402

import common  # noqa: E402

out = common.args()[0]
common.reset()


def material(name, color, metallic, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = roughness
    return m


steel = material("steel", (0.75, 0.74, 0.7), 1.0, 0.3)
gold = material("gold", (0.85, 0.65, 0.25), 1.0, 0.3)
leather = material("leather", (0.25, 0.13, 0.06), 0.0, 0.8)
parts = []
bpy.ops.mesh.primitive_cylinder_add(radius=0.016, depth=0.5, vertices=14, location=(0, 0, 0.15))
shaft = bpy.context.object
shaft.data.materials.append(steel)
parts.append(shaft)
bpy.ops.mesh.primitive_cylinder_add(radius=0.019, depth=0.13, vertices=14, location=(0, 0, 0.0))
grip = bpy.context.object
grip.data.materials.append(leather)
parts.append(grip)
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, segments=16, ring_count=10, location=(0, 0, 0.42))
head = bpy.context.object
head.data.materials.append(gold)
parts.append(head)
for k in range(6):
    a = k * math.pi / 3
    bpy.ops.mesh.primitive_cube_add(size=1, location=(math.cos(a) * 0.05, math.sin(a) * 0.05, 0.42))
    f = bpy.context.object
    f.scale = (0.05, 0.012, 0.11)
    f.rotation_euler = (0, 0, a)
    f.data.materials.append(steel)
    parts.append(f)
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.022, segments=12, ring_count=8, location=(0, 0, -0.08))
pommel = bpy.context.object
pommel.data.materials.append(gold)
parts.append(pommel)
for p in parts:
    common.select_only([p])
    bpy.ops.object.shade_smooth()
mace = common.join(parts)
mace.name = "Mace"
common.apply_transforms(mace)
common.export_glb([mace], out)
print("REPORT", out)
