"""Builds a one-handed bearded axe from shapes in Blender: an ash haft, a leather grip, a
crescent steel blade (thin at the edge) and a small back spike. Origin at the grip, along +Z
(glTF +Y), like sword.py and mace.py, so it attaches to the hand the same way.

blender -b --python tools/pipeline/axe.py -- <out.glb>
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bmesh  # noqa: E402
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


steel = material("steel", (0.72, 0.72, 0.7), 1.0, 0.3)
wood = material("wood", (0.45, 0.3, 0.17), 0.0, 0.65)
leather = material("leather", (0.22, 0.12, 0.06), 0.0, 0.8)
parts = []

bpy.ops.mesh.primitive_cylinder_add(radius=0.017, depth=0.62, vertices=12, location=(0, 0, 0.19))
haft = bpy.context.object
haft.data.materials.append(wood)
parts.append(haft)
bpy.ops.mesh.primitive_cylinder_add(radius=0.02, depth=0.14, vertices=12, location=(0, 0, 0.0))
grip = bpy.context.object
grip.data.materials.append(leather)
parts.append(grip)


def slab(name, outline, thick_at):
    """A flat piece in the XZ plane from an outline [(x, z)], thickness per point."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    front = [bm.verts.new((x, thick_at(x), z)) for x, z in outline]
    back = [bm.verts.new((x, -thick_at(x), z)) for x, z in outline]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(steel)
    return obj


# The blade on +X: a crescent edge with a "beard" hanging down.
blade = slab("blade", [(0.012, 0.37), (0.07, 0.35), (0.12, 0.27), (0.15, 0.29), (0.168, 0.36),
                       (0.17, 0.43), (0.158, 0.5), (0.13, 0.51), (0.07, 0.47), (0.012, 0.47)],
             lambda x: 0.009 if x < 0.06 else (0.006 if x < 0.13 else 0.0025))
parts.append(blade)
spike = slab("spike", [(-0.012, 0.4), (-0.07, 0.42), (-0.012, 0.45)], lambda x: 0.007)
parts.append(spike)
bpy.ops.mesh.primitive_cylinder_add(radius=0.024, depth=0.12, vertices=12, location=(0, 0, 0.42))
socket = bpy.context.object
socket.data.materials.append(steel)
parts.append(socket)
for p in parts:
    common.select_only([p])
    if p in (blade, spike):
        bpy.ops.object.shade_flat()
    else:
        bpy.ops.object.shade_smooth()
axe = common.join(parts)
axe.name = "Axe"
# The edges point up and down when the hand holds it forward (they used to face sideways).
axe.rotation_euler = (0, 0, math.pi / 2)
common.apply_transforms(axe)
common.export_glb([axe], out)
print("REPORT", out)
