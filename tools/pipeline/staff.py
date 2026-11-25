"""Builds a mage's staff from shapes in Blender: a tapered wooden shaft, a metal claw at the top
holding a glowing crystal. Origin at the grip, shaft along +Z (glTF +Y = up in the hand).

blender -b --python tools/pipeline/staff.py -- <out.glb> [length_m] [crystal r,g,b]
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bpy  # noqa: E402

import common  # noqa: E402

a = common.args()
out = a[0]
length = float(a[1]) if len(a) > 1 else 1.7
glow = tuple(float(v) for v in a[2].split(",")) if len(a) > 2 else (0.25, 0.55, 1.0)
common.reset()
GRIP = 0.62       # the hand holds the staff this far up from its foot


def material(name, color, metallic, roughness, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = roughness
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = 4.0
    return m


wood = material("wood", (0.32, 0.2, 0.11), 0.0, 0.75)
metal = material("metal", (0.6, 0.55, 0.45), 1.0, 0.35)
crystal = material("crystal", glow, 0.0, 0.1, emit=glow)

parts = []
# Shaft: a tapered, slightly bent cylinder made of segments.
bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.022, radius2=0.016, depth=length, location=(0, 0, length / 2 - GRIP))
shaft = bpy.context.object
shaft.data.materials.append(wood)
for v in shaft.data.vertices:
    v.co.x += 0.012 * math.sin(v.co.z * 4.0)
parts.append(shaft)
top = length - GRIP
# Claw: four curved prongs around the crystal.
for k in range(4):
    ang = k * math.pi / 2 + 0.4
    bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.012, radius2=0.004, depth=0.16,
                                    location=(math.cos(ang) * 0.035, math.sin(ang) * 0.035, top + 0.07))
    p = bpy.context.object
    p.rotation_euler = (math.sin(ang) * -0.45, math.cos(ang) * 0.45, 0)
    p.data.materials.append(metal)
    parts.append(p)
bpy.ops.mesh.primitive_torus_add(major_radius=0.03, minor_radius=0.008, location=(0, 0, top))
ring = bpy.context.object
ring.data.materials.append(metal)
parts.append(ring)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.045, location=(0, 0, top + 0.09))
gem = bpy.context.object
gem.scale = (1, 1, 1.5)
gem.data.materials.append(crystal)
parts.append(gem)
for p in parts:
    common.select_only([p])
    bpy.ops.object.shade_flat() if p is gem else bpy.ops.object.shade_smooth()
staff = common.join(parts)
staff.name = "Staff"
common.apply_transforms(staff)
common.export_glb([staff], out)
print("REPORT", out)
